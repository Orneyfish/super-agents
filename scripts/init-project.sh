#!/usr/bin/env bash
# Usage: init-project.sh [dir ...]      default: current dir. Idempotent; only touches git repos.
# Adds review.md, keeps the super-agents block in CLAUDE.md current (it @-imports review.md), and git-ignores run state
# and the plugin's files of single-feature specs (specs/<name>/RD.md, evals.md, ...), so neither lands in a PR.
root="$(cd "$(dirname "$0")/.." && pwd)"
block="$root/templates/claude-block.md"

init_one() {
  local top; top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || { echo "skip   $1 (not a git repo; branches and rollback need git)"; return; }
  cd "$top" || return
  [ -f review.md ] || { cp "$root/templates/review.md" review.md; echo "wrote  $top/review.md"; }

  # only a marker on its own line counts: prose that merely names the markers is the user's text
  local start='^<!-- SUPER_AGENTS_START -->[[:space:]]*$' end='^<!-- SUPER_AGENTS_END -->[[:space:]]*$'
  for f in CLAUDE.md AGENTS.md; do
    [ "$f" = AGENTS.md ] && [ ! -f AGENTS.md ] && continue                 # AGENTS.md (read by most other harnesses) is refreshed, never created
    if grep -q "$start" "$f" 2>/dev/null; then
      if ! sed -n "/$start/,\$p" "$f" | grep -q "$end"; then   # refreshing without an END after START would delete everything after START
        echo "skip   $top/$f has SUPER_AGENTS_START but no SUPER_AGENTS_END after it; fix the markers by hand, then re-run"
      elif ! diff -q <(sed -n "/$start/,/$end/p" "$f") "$block" >/dev/null; then   # refresh an old block in place
        awk -v b="$block" -v s="$start" -v e="$end" '$0 ~ s{while((getline l<b)>0)print l;skip=1} !skip{print} $0 ~ e{skip=0}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
        echo "updated super-agents block in $top/$f"
      fi
    else
      { [ -s "$f" ] && echo; cat "$block"; } >> "$f"
      echo "added  super-agents block to $top/$f"
    fi
  done

  # specs/tickets stays tracked (worker worktrees only see committed files); 'super-agents drop-specs' removes it before a PR merges
  # Of a single feature's specs/<name>/ only the plugin's own files are ignored: the project may keep files of its own under specs/.
  # (Ticket files are one level deeper, specs/tickets/NNN-slug/, so these patterns do not reach them.)
  if grep -qxF 'specs/*' .gitignore 2>/dev/null && grep -qxF '!specs/tickets/' .gitignore; then   # what older versions added: it also ignored the project's own files
    grep -vxF -e 'specs/*' -e '!specs/tickets/' .gitignore > .gitignore.tmp; mv .gitignore.tmp .gitignore
    echo "removed specs/* and !specs/tickets/ from $top/.gitignore (replaced by patterns for the plugin's own files)"
  fi
  for pat in .super-agents/ .job/ .claude/worktrees/ 'specs/*/RD.md' 'specs/*/evals.md' 'specs/*/.evals.sha256' 'specs/*/results.md' 'specs/*/mockup.html' 'specs/*/evidence/'; do
    grep -qxF "$pat" .gitignore 2>/dev/null && continue
    { [ -n "$(tail -c1 .gitignore 2>/dev/null)" ] && echo; echo "$pat"; } >> .gitignore
    echo "added  $pat to $top/.gitignore"
  done
  echo "ready  $top"
}

[ $# -eq 0 ] && set -- .
for d in "$@"; do ( init_one "$d" ); done
