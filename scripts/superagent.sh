#!/usr/bin/env bash
# superagent: start the router for this project. One agent to talk to; it hands tickets to workers.
# Usage: superagent [extra claude args]
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "superagent: not inside a git repo" >&2; exit 1; }
cd "$top" || exit 1
[ -f specs/tickets/BOARD.md ] || echo "superagent: no specs/tickets/BOARD.md yet. Write tickets first with /super-agents:write-tickets in a normal session." >&2

b=$(git branch --show-current)
case "$b" in main|master|trunk|"")
  n="integration/$(date +%Y%m%d-%H%M)"
  read -r -p "On '${b:-detached HEAD}'. Finished tickets merge into the current branch, so start an integration branch '$n'? [Y/n] " a
  if [[ ${a:-y} =~ ^[Yy] ]]; then git switch -c "$n" || exit 1; else echo "superagent: refusing to merge tickets into '$b'" >&2; exit 1; fi;;
esac

# Team tickets use Claude Code's experimental agent teams: enabled for this session only, never globally.
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 exec claude --agent super-agents:router --name router --permission-mode auto "$@"
