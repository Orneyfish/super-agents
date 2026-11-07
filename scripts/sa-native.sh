#!/usr/bin/env bash
# sa-native.sh <args>: run sa-core, the plugin's native helper, for this machine.
# Order: $SUPER_AGENTS_CORE, a local build (core/target/release), then a cached copy of the release
# asset for this plugin version, downloaded once and checked against dist/checksums/v<version>.txt.
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
if [ ! -x "$bin" ]; then
  want=$(awk -v f="$name" '$2 == f || $2 == "*" f { print $1 }' "$root/dist/checksums/v$ver.txt" 2>/dev/null)
  [ -n "$want" ] || { echo "super-agents: no checksum for $name in dist/checksums/v$ver.txt; build it with: $build" >&2; exit 3; }
  url="${SUPER_AGENTS_CORE_URL:-https://github.com/Orneyfish/super-agents/releases/download/v$ver}/$name"
  mkdir -p "$dir" && tmp=$(mktemp "$dir/.download.XXXXXX") || exit 3
  if ! curl -fsSL --retry 2 -o "$tmp" "$url"; then
    rm -f "$tmp"; echo "super-agents: could not download $url; build it with: $build" >&2; exit 3
  fi
  got=$( { sha256sum "$tmp" 2>/dev/null || shasum -a 256 "$tmp"; } | awk '{print $1}')
  if [ "$got" != "$want" ]; then
    rm -f "$tmp"; echo "super-agents: checksum mismatch for $url (got $got, want $want); not running it" >&2; exit 3
  fi
  chmod +x "$tmp" && mv -f "$tmp" "$bin" || exit 3
fi
exec "$bin" "$@"
