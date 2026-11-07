#!/usr/bin/env bash
# PreToolUse: keeps the first-time-user subagent blind to the code. Every other agent passes through untouched.
in=$(cat)
grep -q 'first-time-user' <<<"$in" || exit 0                                   # cheap pre-filter, most calls end here
jq -e '(.agent_type // "") | test("(^|:)first-time-user$")' <<<"$in" >/dev/null || exit 0

deny() { jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
msg="Blocked: you are a first-time user and must not look at the app's code. Use the app only through its UI, URL or CLI."

[ "$(jq -r .tool_name <<<"$in")" = Bash ] || deny "$msg"

cmd=$(jq -r '.tool_input.command // ""' <<<"$in"); cwd=$(jq -r '.cwd // ""' <<<"$in")
# shortcut: regex denylist, best effort (a determined agent could still find a way, e.g. by splitting a word with quotes); upgrade to a chroot/container if it does.
# A verb only counts where a command starts (line start, or after ; & | ( { ` $( then/do/else, VAR=x or a path prefix), so
# `curl -d "q=find a flight"` and `app add "cat food"` pass while `x | cat f`, `env cat f`, `xargs cat` and `bash -c "cat f"` do not.
verbs='cat|head|tail|less|more|bat|nl|tac|grep|egrep|rg|ag|ack|find|fd|ls|tree|sed|awk|cut|strings|xxd|od|diff|git|vi|vim|nvim|nano|emacs|source|python3?|node|perl|ruby|eval|exec|xargs|env|sudo|nohup|time|command'
start='(^|[;&|({`]|\$\()[[:space:]]*((then|do|else|elif|if|while|until|!)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*([^[:space:];&|(){`]*/)?'
paths='\.\./|file:|(^|[ =:"'"'"'])\.?/?(src|app|lib|server|backend|frontend|specs)/'
if grep -Eq "${start}(($verbs)([[:space:]]|\$)|(bash|sh|zsh|dash)[[:space:]]+-[A-Za-z]*c)|$paths" <<<"$cmd" || { [ -n "$cwd" ] && grep -qF "$cwd" <<<"$cmd"; }; then
  deny "$msg"
fi
