#!/usr/bin/env bash
# PreToolUse: keeps the first-time-user subagent blind to the code. Every other agent passes through untouched.
in=$(cat)
grep -q 'first-time-user' <<<"$in" || exit 0                                   # cheap pre-filter, most calls end here
jq -e '(.agent_type // "") | test("(^|:)first-time-user$")' <<<"$in" >/dev/null || exit 0

deny() { jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
msg="Blocked: you are a first-time user and must not look at the app's code. Use the app only through its UI, URL or CLI."

[ "$(jq -r .tool_name <<<"$in")" = Bash ] || deny "$msg"

cmd=$(jq -r '.tool_input.command // ""' <<<"$in"); cwd=$(jq -r '.cwd // ""' <<<"$in")
# shortcut: regex denylist, best effort (a determined agent could still find a way); upgrade to a chroot/container if it does.
verbs='cat|head|tail|less|more|bat|nl|tac|grep|egrep|rg|ag|ack|find|fd|ls|tree|sed|awk|cut|strings|xxd|od|diff|git|vi|vim|nvim|nano|emacs|source|python3?|node|perl|ruby'
paths='\.\./|file:|(^|[ =:"'"'"'])\.?/?(src|app|lib|server|backend|frontend|specs)/'
if grep -Eq "(^|[^[:alnum:]_-])($verbs)([^[:alnum:]_-]|$)|$paths" <<<"$cmd" || { [ -n "$cwd" ] && grep -qF "$cwd" <<<"$cmd"; }; then
  deny "$msg"
fi
