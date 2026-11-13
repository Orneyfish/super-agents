#!/usr/bin/env bash
# Stop hook: while a review-loop is active, refuse "done" until every eval passes in results.md.
# Escape hatches (so it can never wedge a session): awaiting_user, a stale state file, and a 3-block cap.
# The gate applies to one session per loop, the 'session:' line of state.md. The review-loop records the session that started it
# (its id comes from the SessionStart context). A state file without that line falls back to a claim: the first session to stop
# while the loop is active takes it, which can be an unrelated session that answers a short question first. Other sessions are never gated.
here="$(cd "$(dirname "$0")" && pwd)"; get_json() { "$here/sa-native.sh" hookio get "$@"; }
# a gate that cannot run says so where the user sees it (a systemMessage; stderr of a hook that exits 0 is shown to nobody)
"$here/sa-native.sh" --version >/dev/null 2>&1 || { echo '{"systemMessage": "super-agents: eval gate skipped: sa-core is not available here (run super-agents install-core); nothing checked that the evals pass."}'; exit 0; }
in=$(cat)
cwd=$(get_json cwd <<<"$in") || { "$here/sa-native.sh" hookio emit message "super-agents: hook input unreadable; eval gate not evaluated."; exit 0; }
st="$cwd/.super-agents/state.md"
[ -f "$st" ] || exit 0
[ -n "$(find "$st" -mmin -720)" ] || exit 0          # abandoned loop (>12h old): ignore
get() { sed -n "s/^$1: *//p" "$st" | head -1; }
[ "$(get active)" = true ] || exit 0
[ "$(get awaiting_user)" = true ] && exit 0           # waiting on the human, not claiming done
# a state file the repository ships (git-tracked) or a symlink is not a loop the user started: ignore it, with fixed text only
if [ -L "$st" ] || [ -L "$cwd/.super-agents" ] || git -C "$cwd" ls-files --error-unmatch -- "$st" >/dev/null 2>&1; then
  "$here/sa-native.sh" hookio emit message "super-agents: .super-agents/state.md is tracked by git or a symlink, so it is ignored and no eval gate runs. Remove it from git (git rm --cached) to use the review-loop here."; exit 0
fi
dir=$(get dir); [[ $dir =~ ^[A-Za-z0-9._/-]+$ && $dir != *..* && -d "$cwd/$dir" ]] || exit 0
sid=$(get_json session_id <<<"$in"); owner=$(get session)
# one append (a missing final newline would otherwise merge the claim into the last line); re-read: with two claims at once the first line wins
if [ -z "$owner" ] && [ -n "$sid" ]; then nl=; [ -n "$(tail -c1 "$st")" ] && nl=$'\n'; printf '%ssession: %s\n' "$nl" "$sid" >> "$st"; owner=$(get session); fi
[ -n "$owner" ] && [ -n "$sid" ] && [ "$owner" != "$sid" ] && exit 0
# a stop while a subagent still runs is a wait, not a claim of "done": allow it without spending one of the three blocks.
# shortcut: reads the compact JSON text (an entry with no status counts as running); parse it in sa-core once the payload's shape is documented.
bg=$(get_json background_tasks <<<"$in")
if [[ $bg == \[*\{* ]] && { [[ $bg != *'"status"'* ]] || [[ $bg == *'"status":"running"'* ]]; }; then exit 0; fi

out=$("$(dirname "$0")/check-evals.sh" "$cwd/$dir" --passed) && exit 0
left=$(grep -c '^FAIL' <<<"$out")

n=$(get gate_blocks); [[ $n =~ ^[0-9]{1,3}$ ]] && n=$((10#$n)) || n=0   # never arithmetic on text from the file; garbage counts as 0, so the gate blocks
if [ "$n" -ge 3 ]; then
  "$here/sa-native.sh" hookio emit message "super-agents: eval gate released after 3 blocks; evals still unmet."; exit 0
fi
if grep -q '^gate_blocks:' "$st"; then sed "s/^gate_blocks:.*/gate_blocks: $((n+1))/" "$st" > "$st.tmp" && mv "$st.tmp" "$st"; else echo "gate_blocks: $((n+1))" >> "$st"; fi

"$here/sa-native.sh" hookio emit block "$left problem(s) in $dir mean the feature is not done:
$out
Keep going through the review-loop, or set awaiting_user: true in .super-agents/state.md and ask the user. If you must stop anyway, say plainly which evals are unmet."
