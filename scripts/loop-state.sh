#!/usr/bin/env bash
# The one writer of the review-loop's .super-agents/state.md (eval-gate.sh and session-start.sh read it) and of its run log.
#   loop-state.sh start <dir> <low|medium|high> [session-id]   new state file; base and checkpoint = HEAD
#   loop-state.sh end <done|stuck|cap|stopped>                  active: false, and one line appended to .super-agents/history.tsv
# history.tsv (UTC end time, dir, risk, rounds, evals passing/total, gate blocks in the last round, outcome) is the record of how real runs went.
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "loop: not inside a git repository" >&2; exit 2; }
sd="$top/.super-agents"; st="$sd/state.md"; hist="$sd/history.tsv"
get() { sed -n "s/^$1: *//p" "$st" | head -1; }
case "${1:-}" in
  start)
    dir=${2:-}; risk=${3:-}; sid=${4:-}
    [[ $dir =~ ^[A-Za-z0-9._/-]+$ && $dir != *..* && -d "$top/$dir" ]] || { echo "loop: <dir> must be an existing repo-relative directory (A-Z a-z 0-9 . _ / -)" >&2; exit 2; }
    [[ $risk =~ ^(low|medium|high)$ ]] || { echo "loop: risk must be low, medium or high" >&2; exit 2; }
    [[ -z $sid || $sid =~ ^[A-Za-z0-9-]{1,64}$ ]] || { echo "loop: session id must be 1-64 of A-Z a-z 0-9 -" >&2; exit 2; }
    if [ -f "$st" ] && [ "$(get active)" = true ] && [ "$(get dir)" != "$dir" ]; then echo "loop: a review-loop for $(get dir) is still active; end it first (super-agents loop end stopped)" >&2; exit 1; fi
    head=$(git -C "$top" rev-parse HEAD) || exit 1
    mkdir -p "$sd"
    { printf -- '---\ndir: %s\n' "$dir"; [ -n "$sid" ] && printf 'session: %s\n' "$sid"
      printf 'active: true\nawaiting_user: false\nrisk: %s\nround: 0\nmax_rounds: 5\ngate_blocks: 0\nbase: %s\ncheckpoint: %s\n---\n' "$risk" "$head" "$head"
      printf '| id | class | severity | location | first | last | status |\n|----|-------|----------|----------|-------|------|--------|\n'; } > "$st"
    echo "ok loop started for $dir (max_rounds 5)";;
  end)
    out=${2:-}; [[ $out =~ ^(done|stuck|cap|stopped)$ ]] || { echo "loop: outcome must be done, stuck, cap or stopped" >&2; exit 2; }
    [ -f "$st" ] && [ "$(get active)" = true ] || { echo "loop: no active review-loop" >&2; exit 1; }
    dir=$(get dir); res="$top/$dir/results.md"
    p=$(grep -cE '^\| *E[0-9]+ *\| *pass *\|' "$res" 2>/dev/null); n=$(grep -cE '^\| *E[0-9]+ *\|' "$res" 2>/dev/null)
    sed 's/^active:.*/active: false/' "$st" > "$st.tmp" && mv "$st.tmp" "$st"
    [ -f "$hist" ] || printf 'ended\tdir\trisk\trounds\tevals\tgate_blocks\toutcome\n' > "$hist"
    printf '%s\t%s\t%s\t%s\t%s/%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$dir" "$(get risk)" "$(get round)" "${p:-0}" "${n:-0}" "$(get gate_blocks)" "$out" >> "$hist"
    echo "ok loop ended ($out); logged to .super-agents/history.tsv";;
  *) echo "usage: super-agents loop start <dir> <low|medium|high> [session-id] | loop end <done|stuck|cap|stopped>" >&2; exit 2;;
esac
