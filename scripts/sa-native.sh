#!/usr/bin/env bash
# sa-native.sh <args>: run sa-core, the plugin's native helper, for this machine.
# Order: $SUPER_AGENTS_CORE, a local build (core/target/release), then a cached copy of the release
# asset for this plugin version, downloaded once and checked against dist/checksums/v<version>.txt on every run.
# A download whose sha256 does not match is deleted and never run. Without a usable binary it exits 3,
# never 2: Claude Code reads exit 2 from a hook as "block", and a missing helper must not block anything.
root="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)               t=x86_64-unknown-linux-musl  x='' ;;
  Linux-aarch64|Linux-arm64)  t=aarch64-unknown-linux-musl x='' ;;
  Darwin-x86_64)              t=x86_64-apple-darwin        x='' ;;
  Darwin-arm64)               t=aarch64-apple-darwin       x='' ;;
  MINGW*-x86_64|MSYS*-x86_64) t=x86_64-pc-windows-msvc     x=.exe ;;
  *)                          t=''                         x='' ;;
esac
build="cargo build --release --locked --manifest-path $root/core/Cargo.toml"
[ -n "${SUPER_AGENTS_CORE:-}" ] && exec "$SUPER_AGENTS_CORE" "$@"
[ -x "$root/core/target/release/sa-core$x" ] && exec "$root/core/target/release/sa-core$x" "$@"
[ -n "$t" ] || { echo "super-agents: no prebuilt sa-core for $(uname -s)-$(uname -m); build it with: $build" >&2; exit 3; }

ver=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" | head -1)
name="sa-core-$t$x"; dir="${XDG_CACHE_HOME:-$HOME/.cache}/super-agents/$ver"; bin="$dir/$name"
want=$(awk -v f="$name" '$2 == f || $2 == "*" f { print $1 }' "$root/dist/checksums/v$ver.txt" 2>/dev/null)
[ -n "$want" ] || { echo "super-agents: no checksum for $name in dist/checksums/v$ver.txt; build it with: $build" >&2; exit 3; }
sum() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | awk '{print $1}'; }
# the cache is as writable as any other file: it is checked on every run, not only after the download
if [ -x "$bin" ] && [ "$(sum "$bin")" != "$want" ]; then
  echo "super-agents: the cached $bin does not match dist/checksums/v$ver.txt; deleted, downloading it again" >&2; rm -f "$bin"
fi
if [ ! -x "$bin" ]; then
  url="${SUPER_AGENTS_CORE_URL:-https://github.com/Orneyfish/super-agents/releases/download/v$ver}/$name"
  mkdir -p "$dir" || exit 3
  # Hooks run this on every tool call or stop, so a failed download must not be paid for again and again: it is not retried for
  # 10 minutes (SA_NATIVE_FORCE=1, set by 'super-agents install-core', retries at once), and curl gives up instead of hanging.
  failed="$dir/.last-failure"
  if [ -z "${SA_NATIVE_FORCE:-}" ] && [ -n "$(find "$failed" -mmin -10 2>/dev/null)" ]; then
    echo "super-agents: not downloading sa-core again, the last try failed less than 10 minutes ago (run 'super-agents install-core' to retry now); build it with: $build" >&2; exit 3
  fi
  find "$dir" -name '.download.*' -mmin +60 -delete 2>/dev/null   # left by runs that were killed
  tmp=$(mktemp "$dir/.download.XXXXXX") || exit 3
  trap 'rm -f "$tmp"' EXIT
  if ! curl -fsSL --retry 1 --connect-timeout 5 --max-time "${SUPER_AGENTS_CORE_TIMEOUT:-20}" -o "$tmp" "$url"; then
    rm -f "$tmp"; touch "$failed"; echo "super-agents: could not download $url; build it with: $build" >&2; exit 3
  fi
  got=$(sum "$tmp")
  if [ "$got" != "$want" ]; then
    rm -f "$tmp"; touch "$failed"; echo "super-agents: checksum mismatch for $url (got $got, want $want); not running it" >&2; exit 3
  fi
  chmod +x "$tmp" && mv -f "$tmp" "$bin" || exit 3
  rm -f "$failed"; trap - EXIT
fi
exec "$bin" "$@"
