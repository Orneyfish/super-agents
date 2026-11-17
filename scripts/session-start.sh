#!/usr/bin/env bash
# SessionStart: put the working agreement in every session; the flow and session id only in git projects; nudge un-set-up git projects; resume an active loop.
here="$(cd "$(dirname "$0")" && pwd)"
why=$("$here/sa-native.sh" --version 2>&1 >/dev/null) || { echo "super-agents: its native helper sa-core is not available here, so its hooks (the done-gates) are switched off. Run 'super-agents install-core' to see why.${why:+ The launcher said: $why}"; exit 0; }
in=$(cat); cwd=$("$here/sa-native.sh" hookio get cwd <<<"$in"); sid=$("$here/sa-native.sh" hookio get session_id <<<"$in"); cd "${cwd:-.}" 2>/dev/null || exit 0

ctx="The super-agents plugin is active. Working agreement: a task counts as done only when proven with output run in this session (test results, screenshot, eval pass), not on the agent's own say-so."

if top=$(git rev-parse --show-toplevel 2>/dev/null); then
  # the flow only matters where specs and branches exist; its skill names are already in the skill list
  ctx+=" For non-trivial work here, any kind of work (code, documents, research, plans, operations): /super-agents:write-eval, then /super-agents:review-loop; for several features, /super-agents:write-tickets."
  [ -n "$sid" ] && ctx+=" This session's id is $sid; a review-loop started here records it as 'session:' in .super-agents/state.md, so only this session is gated by it."
  st="$top/.super-agents/state.md"
  if [ ! -f "$top/review.md" ]; then
    ctx+=" This git project has no review.md, so it is not set up for super-agents; /super-agents:setup-project sets it up in one step (worth one mention if the user starts feature work)."
  elif [ -f "$st" ] && grep -q '^active: true' "$st"; then
    # this text reaches every session's context: only the grammar the gate accepts, anything else is left out
    d=$(sed -n 's/^dir: *//p' "$st" | head -1); [[ $d =~ ^[A-Za-z0-9._/-]+$ && $d != *..* ]] || d=
    r=$(sed -n 's/^round: *//p' "$st" | head -1); [[ $r =~ ^[0-9]{1,3}$ ]] || r=
    what="${d:+dir $d }${r:+round $r}"
    ctx+=" A review-loop is active here (${what% }); .super-agents/state.md holds its state. If this session is continuing that loop, set its 'session:' line to this session's id."
  fi
  [ -f "$top/specs/tickets/BOARD.md" ] && ctx+=" A ticket board exists at specs/tickets/BOARD.md; ready tickets are built in parallel by the router the user starts with 'superagent', not in an ordinary session."
fi

"$here/sa-native.sh" hookio emit context "$ctx"
