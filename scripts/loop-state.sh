#!/usr/bin/env bash
# The one writer of the review-loop's .super-agents/state.md (eval-gate.sh and session-start.sh read it) and of its run log.
#   loop-state.sh start <dir> <low|medium|high> [session-id]   new state file; base and checkpoint = HEAD
#   loop-state.sh end <done|stuck|cap|stopped>                  one line appended to .super-agents/history.tsv, then active: false
# history.tsv (UTC end time, dir, risk, rounds, evals passing/total, gate blocks in the last round, outcome) is the record of how real runs went.
# shortcut: no lock; one orchestrator per loop calls this, so concurrent start/end is not expected. Add flock if routers ever call it.
here="$(cd "$(dirname "$0")" && pwd)"
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "loop: not inside a git repository" >&2; exit 2; }
sd="$top/.super-agents"; st="$sd/state.md"; hist="$sd/history.tsv"
get() { sed -n "s/^$1: *//p" "$st" | head -1; }
# same refusal as eval-gate.sh: a symlinked state path would make our writes land somewhere else
{ [ -L "$sd" ] || [ -L "$st" ] || [ -L "$hist" ]; } && { echo "loop: .super-agents, its state.md or history.tsv is a symlink; refusing to write through it" >&2; exit 1; }
live() { [ -f "$st" ] && [ "$(get active)" = true ] && [ -n "$(find "$st" -mmin -720)" ]; }   # older than 12h counts as abandoned, as in eval-gate.sh
put() { local tmp; tmp=$(mktemp "$sd/.state.XXXXXX") && cat > "$tmp" && mv -f "$tmp" "$st" || { rm -f "$tmp"; echo "loop: could not write $st" >&2; exit 1; }; }   # complete file, then rename: never a half-written state.md
case "${1:-}" in
  start)
    dir=${2:-}; risk=${3:-}; sid=${4:-}
    [[ $dir =~ ^[A-Za-z0-9._/-]+$ && $dir != *..* && -d "$top/$dir" ]] || { echo "loop: <dir> must be an existing repo-relative directory (A-Z a-z 0-9 . _ / -)" >&2; exit 2; }
    [[ $risk =~ ^(low|medium|high)$ ]] || { echo "loop: risk must be low, medium or high" >&2; exit 2; }
    [[ -z $sid || $sid =~ ^[A-Za-z0-9-]{1,64}$ ]] || { echo "loop: session id must be 1-64 of A-Z a-z 0-9 -" >&2; exit 2; }
    live && { echo "loop: a review-loop for $(get dir) is still active; continue it, or end it first (super-agents loop end stopped)" >&2; exit 1; }
    head=$(git -C "$top" rev-parse HEAD) || exit 1
    mkdir -p "$sd" || exit 1
    { printf -- '---\ndir: %s\n' "$dir"; [ -n "$sid" ] && printf 'session: %s\n' "$sid"
      printf 'active: true\nawaiting_user: false\nrisk: %s\nround: 0\nmax_rounds: 5\ngate_blocks: 0\nbase: %s\ncheckpoint: %s\n---\n' "$risk" "$head" "$head"
      printf '| id | class | severity | location | first | last | status |\n|----|-------|----------|----------|-------|------|--------|\n'; } | put || exit 1
    echo "ok loop started for $dir (max_rounds 5)";;
  end)
    out=${2:-}; [[ $out =~ ^(done|stuck|cap|stopped)$ ]] || { echo "loop: outcome must be done, stuck, cap or stopped" >&2; exit 2; }
    [ -f "$st" ] && [ "$(get active)" = true ] || { echo "loop: no active review-loop" >&2; exit 1; }
    dir=$(get dir)
    # 'done' is a claim the evals pass: the same check as the Stop hook and 'board set done', or the gate could be closed by saying so
    if [ "$out" = "done" ]; then chk=$("$here/check-evals.sh" "$top/$dir" --passed) || { echo "$chk"; echo "loop: not ended as done: every eval must pass with evidence in results.md first" >&2; exit 1; }; fi
    n=$(grep -cE '^## E[0-9]+' "$top/$dir/evals.md" 2>/dev/null)
    p=$(grep -iE '^\| *E[0-9]+ *\| *pass *\|' "$top/$dir/results.md" 2>/dev/null | sed -E 's/^\| *(E[0-9]+).*/\1/' | sort -u | wc -l | tr -d ' ')
    # log first: a failed append leaves the loop active so 'loop end' can be retried
    { [ -f "$hist" ] || printf 'ended\tdir\trisk\trounds\tevals\tgate_blocks\toutcome\n'
      printf '%s\t%s\t%s\t%s\t%s/%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$dir" "$(get risk)" "$(get round)" "${p:-0}" "${n:-0}" "$(get gate_blocks)" "$out"; } >> "$hist" \
      || { echo "loop: could not append to $hist; the loop is still active" >&2; exit 1; }
    sed 's/^active:.*/active: false/' "$st" | put || exit 1
    echo "ok loop ended ($out); logged to .super-agents/history.tsv";;
  *) echo "usage: super-agents loop start <dir> <low|medium|high> [session-id] | loop end <done|stuck|cap|stopped>" >&2; exit 2;;
esac
