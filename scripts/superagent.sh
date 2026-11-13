#!/usr/bin/env bash
# superagent: start the router for this project. One agent to talk to; it hands tickets to workers.
# Usage: superagent [extra claude args]
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "superagent: not inside a git repo" >&2; exit 1; }
cd "$top" || exit 1
[ -f specs/tickets/BOARD.md ] || echo "superagent: no specs/tickets/BOARD.md yet. Write tickets first with /super-agents:write-tickets in a normal session." >&2

b=$(git branch --show-current)
case "$b" in main|master|trunk|"")
  n="integration/$(date +%Y%m%d-%H%M%S)"
  read -r -p "On '${b:-detached HEAD}'. Finished tickets merge into the current branch, so start an integration branch '$n'? [Y/n] " a
  if [[ ${a:-y} =~ ^[Yy] ]]; then git switch -c "$n" || exit 1; else echo "superagent: refusing to merge tickets into '$b'" >&2; exit 1; fi;;
esac

# Workers get worktrees of committed files only: tickets, review.md and .gitignore must be committed before they start (and again
# for tickets approved while this runs: 'super-agents commit-tickets'). The script lists what it commits and asks first.
"$(dirname "$(readlink -f "$0")")/commit-tickets.sh" -q || exit 1

# Team tickets use Claude Code's experimental agent teams: enabled for this session only, never globally.
# Workers run unattended, so default to auto permission mode unless the caller passes their own --permission-mode.
mode=(--permission-mode auto); case " $* " in *" --permission-mode"*) mode=();; esac
# Worktrees must start from this branch's HEAD: by default, in a repository with a remote, they start from the remote's default
# branch, which does not have the tickets committed above.
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 exec claude --settings '{"worktree":{"baseRef":"head"}}' --agent super-agents:router --name router "${mode[@]}" "$@"
