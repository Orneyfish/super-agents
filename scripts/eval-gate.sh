#!/usr/bin/env bash
# Stop hook: while a review-loop is active, refuse "done" until every eval passes in results.md.
# Escape hatches (so it can never wedge a session): awaiting_user, a stale state file, and a 3-block cap.
# The first session to stop while the loop is active claims it (a 'session:' line); other sessions in the repo are never gated.
here="$(cd "$(dirname "$0")" && pwd)"; get_json() { "$here/hookio.py" get "$@"; }
in=$(cat); cwd=$(get_json cwd <<<"$in"); st="$cwd/.super-agents/state.md"
[ -f "$st" ] || exit 0
[ -n "$(find "$st" -mmin -720)" ] || exit 0          # abandoned loop (>12h old): ignore
get() { sed -n "s/^$1: *//p" "$st" | head -1; }
[ "$(get active)" = true ] || exit 0
[ "$(get awaiting_user)" = true ] && exit 0           # waiting on the human, not claiming done
dir=$(get dir); [[ $dir =~ ^[A-Za-z0-9._/-]+$ && $dir != *..* && -d "$cwd/$dir" ]] || exit 0
sid=$(get_json session_id <<<"$in"); owner=$(get session)
if [ -z "$owner" ] && [ -n "$sid" ]; then echo "session: $sid" >> "$st"; owner=$(get session); fi   # re-read: with two claims at once the first line wins
[ -n "$owner" ] && [ -n "$sid" ] && [ "$owner" != "$sid" ] && exit 0

out=$("$(dirname "$0")/check-evals.sh" "$cwd/$dir" --passed) && exit 0
left=$(grep -c '^FAIL' <<<"$out")

n=$(get gate_blocks); n=${n:-0}
if [ "$n" -ge 3 ]; then
  "$here/hookio.py" emit message "super-agents: eval gate released after 3 blocks; evals still unmet."; exit 0
fi
if grep -q '^gate_blocks:' "$st"; then sed "s/^gate_blocks:.*/gate_blocks: $((n+1))/" "$st" > "$st.tmp" && mv "$st.tmp" "$st"; else echo "gate_blocks: $((n+1))" >> "$st"; fi

"$here/hookio.py" emit block "$left problem(s) in $dir mean the feature is not done:
$out
Keep going through the review-loop, or set awaiting_user: true in .super-agents/state.md and ask the user. If you must stop anyway, say plainly which evals are unmet."
