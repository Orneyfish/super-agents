#!/usr/bin/env bash
# SessionStart: put the working agreement in every session; nudge un-set-up git projects; resume an active loop.
command -v python3 >/dev/null || { echo "super-agents: python3 is not installed, so its hooks (the done-gates) are switched off. Install python3 to turn them on."; exit 0; }
here="$(cd "$(dirname "$0")" && pwd)"
in=$(cat); cwd=$("$here/hookio.py" get cwd <<<"$in"); cd "${cwd:-.}" 2>/dev/null || exit 0

ctx="The super-agents plugin is active for this user. Working agreement: a task counts as done only when proven with output run in this session (test results, screenshot, eval pass), not on the agent's own say-so. For non-trivial user-visible features in git projects the flow is /super-agents:write-eval, then /super-agents:review-loop; for several features at once, /super-agents:write-tickets, /super-agents:mark-ready, then the user runs the 'superagent' command in a terminal. Also available: :classify-risk, :first-time-user, :fix-bug, :setup-project."

if top=$(git rev-parse --show-toplevel 2>/dev/null); then
  st="$top/.super-agents/state.md"
  if [ ! -f "$top/review.md" ]; then
    ctx+=" This git project has no review.md, so it is not set up for super-agents; /super-agents:setup-project sets it up in one step (worth one mention if the user starts feature work)."
  elif [ -f "$st" ] && grep -q '^active: true' "$st"; then
    ctx+=" A review-loop is active here ($(sed -n 's/^dir: /dir /p;s/^round: /round /p' "$st" | paste -sd' ' -)); .super-agents/state.md holds its state."
  fi
  [ -f "$top/specs/tickets/BOARD.md" ] && ctx+=" A ticket board exists at specs/tickets/BOARD.md; ready tickets are built in parallel by the router the user starts with 'superagent', not in an ordinary session."
fi

"$here/hookio.py" emit context "$ctx"
