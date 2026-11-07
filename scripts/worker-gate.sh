#!/usr/bin/env bash
# SubagentStop hook: a ticket worker may not finish until every eval passes in results.md (or it declared itself blocked).
# Escape hatches: no job file, a blocked phase, and a 3-block cap, so it can never wedge a worker.
in=$(cat)
grep -q worker <<<"$in" || exit 0                                       # cheap pre-filter
jq -e '(.agent_type // "") | test("(^|:)worker$")' <<<"$in" >/dev/null || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$in"); st="$cwd/.job/status.json"; [ -f "$st" ] || exit 0
dir=$(jq -r '.dir // empty' "$st"); [ -d "$dir" ] || exit 0
[ "$(jq -r .phase "$st")" = blocked ] && exit 0
out=$("$(dirname "$0")/check-evals.sh" "$dir" --passed) && exit 0
n=$(cat "$cwd/.job/gate_blocks" 2>/dev/null || echo 0); [ "$n" -ge 3 ] && exit 0
echo $((n+1)) > "$cwd/.job/gate_blocks"
jq -n --arg r "Not done yet:
$out
Fix and re-test, then update results.md. If you truly cannot, run job-status.sh blocked '<why>' and say so in your report." '{decision:"block",reason:$r}'
