#!/usr/bin/env bash
# Usage: init-project.sh [dir ...]      default: current dir. Idempotent; only touches git repos.
# Adds review.md, keeps the super-agents block in CLAUDE.md current (it @-imports review.md), and git-ignores run state.
root="$(cd "$(dirname "$0")/.." && pwd)"
block="$root/templates/claude-block.md"

init_one() {
  local top; top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || { echo "skip   $1 (not a git repo; branches and rollback need git)"; return; }
  cd "$top" || return
  [ -f review.md ] || { cp "$root/templates/review.md" review.md; echo "wrote  $top/review.md"; }

  for f in CLAUDE.md AGENTS.md; do
    [ "$f" = AGENTS.md ] && [ ! -f AGENTS.md ] && continue                 # AGENTS.md (read by most other harnesses) is refreshed, never created
    if grep -q SUPER_AGENTS_START "$f" 2>/dev/null; then
      if ! grep -q SUPER_AGENTS_END "$f"; then   # refreshing without an END marker would delete everything after START
        echo "skip   $top/$f has SUPER_AGENTS_START but no SUPER_AGENTS_END; fix the markers by hand, then re-run"
      elif ! diff -q <(sed -n '/SUPER_AGENTS_START/,/SUPER_AGENTS_END/p' "$f") "$block" >/dev/null; then   # refresh an old block in place
        awk -v b="$block" '/SUPER_AGENTS_START/{while((getline l<b)>0)print l;skip=1} !skip{print} /SUPER_AGENTS_END/{skip=0}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
        echo "updated super-agents block in $top/$f"
      fi
    else
      { [ -s "$f" ] && echo; cat "$block"; } >> "$f"
      echo "added  super-agents block to $top/$f"
    fi
  done

  for pat in .super-agents/ .job/ .claude/worktrees/; do
    grep -qxF "$pat" .gitignore 2>/dev/null && continue
    { [ -n "$(tail -c1 .gitignore 2>/dev/null)" ] && echo; echo "$pat"; } >> .gitignore
    echo "added  $pat to $top/.gitignore"
  done
  echo "ready  $top"
}

[ $# -eq 0 ] && set -- .
for d in "$@"; do ( init_one "$d" ); done
