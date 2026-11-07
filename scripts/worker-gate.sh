#!/usr/bin/env bash
# SubagentStop hook: a ticket worker may not finish until every eval passes in results.md (or it declared itself blocked).
# Escape hatches: no job file, a blocked phase, and a 3-block cap, so it can never wedge a worker. A gate that cannot run says so.
here="$(cd "$(dirname "$0")" && pwd)"; get() { "$here/hookio.py" get "$@"; }; emit() { "$here/hookio.py" emit "$@"; }
in=$(cat)
grep -q worker <<<"$in" || exit 0                                       # cheap pre-filter
re='(^|:)worker$'; [[ $(get agent_type <<<"$in") =~ $re ]] || exit 0
skip() { emit message "super-agents: worker gate skipped ($1); nothing checked that its evals pass."; exit 0; }
cwd=$(get cwd <<<"$in"); st="$cwd/.job/status.json"; [ -f "$st" ] || skip "no $st"
dir=$(get dir <"$st"); [[ $dir == /* ]] || dir="$cwd/$dir"; [ -d "$dir" ] || skip "ticket dir $dir does not exist"
[ "$(get phase <"$st")" = blocked ] && exit 0
out=$("$(dirname "$0")/check-evals.sh" "$dir" --passed) && exit 0
n=$(cat "$cwd/.job/gate_blocks" 2>/dev/null || echo 0)
[ "$n" -ge 3 ] && { emit message "super-agents: worker gate released after 3 blocks; evals still unmet."; exit 0; }
echo $((n+1)) > "$cwd/.job/gate_blocks"
emit block "Not done yet:
$out
Fix and re-test, then update results.md. If you truly cannot, run 'super-agents job-status blocked \"<why>\"' and say so in your report."
