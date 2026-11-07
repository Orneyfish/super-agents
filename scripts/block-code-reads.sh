#!/usr/bin/env bash
# PreToolUse: keeps the first-time-user subagent blind to the code. Every other agent passes through untouched.
here="$(cd "$(dirname "$0")" && pwd)"; get() { "$here/hookio.py" get "$@"; }
in=$(cat)
grep -q 'first-time-user' <<<"$in" || exit 0                                   # cheap pre-filter, most calls end here
re='(^|:)first-time-user$'; [[ $(get agent_type <<<"$in") =~ $re ]] || exit 0

deny() { "$here/hookio.py" emit deny "$1"; exit 0; }
msg="Blocked: you are a first-time user and must not look at the app's code. Use the app only through its UI, URL or CLI."

case $(get tool_name <<<"$in") in
  mcp__claude-in-chrome__*)   # the app's own pages are the whole point of the browser; local files are not
    grep -Eiq '(^|[^A-Za-z0-9])file:' <<<"$(get tool_input <<<"$in")" && deny "$msg (matched 'file:' in the browser call)"
    exit 0;;
  Bash) ;;
  *) deny "$msg";;
esac

cmd=$(get tool_input.command <<<"$in"); cwd=$(get cwd <<<"$in")
# shortcut: regex denylist, best effort (a determined agent could still find a way, e.g. by splitting a word with quotes); upgrade to a chroot/container if it does.
# A verb only counts where a command starts (line start, or after ; & | ( { ` $( then/do/else, VAR=x or a path prefix), so
# `curl -d "q=find a flight"` and `app add "cat food"` pass while `x | cat f`, `env cat f`, `xargs cat` and `bash -c "cat f"` do not.
# Exception: when the line starts with curl, wget, bash/sh or a path (the app or its launcher), a plain filter after a pipe reads that
# command's output, not a file, so `curl ... | grep ok` passes. A filter that reads files (grep -f/-r, sed/jq -f, a path argument) is not plain.
verbs='cat|head|tail|less|more|bat|nl|tac|grep|egrep|rg|ag|ack|find|fd|ls|tree|sed|awk|cut|strings|xxd|od|diff|git|vi|vim|nvim|nano|emacs|source|python3?|node|perl|ruby|eval|exec|xargs|env|sudo|nohup|time|command|sort|uniq|wc|jq|sqlite3|base64|paste|rev|tee|cp|mv|dd|hexdump|column|fold|file|stat|tar|unzip|zcat|cmp|comm|join'
filters='head|tail|grep|egrep|sort|uniq|wc|cut|tr|jq|less|more|sed'
start='(^|[;&|({`]|\$\()[[:space:]]*((then|do|else|elif|if|while|until|!)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*([^[:space:];&|(){`]*/)?'
paths='\.\./|(^|[^A-Za-z0-9])[Ff][Ii][Ll][Ee]:|(^|[ =:"'"'"'<>])\.?/?(src|app|lib|server|backend|frontend|specs)/'
checked=$cmd
if [[ $cmd =~ ^[[:space:]]*(curl|wget|bash|sh|[^[:space:]]*/) ]]; then
  segs=$(grep -Eo "\|[[:space:]]*($filters)([[:space:]][^|;&]*)?" <<<"$cmd")
  if ! { grep -Eq '^\|[[:space:]]*(grep|egrep)[^|]*[[:space:]](-[A-Za-z]*[frR]|--(file|recursive|dereference-recursive))' <<<"$segs" \
      || grep -Eq '^\|[[:space:]]*(sed|jq)[^|]*[[:space:]](-[A-Za-z]*f|--(file|from-file))' <<<"$segs" \
      || grep -v '^|[[:space:]]*sed' <<<"$segs" | grep -q '/'; }; then
    pass="s/(^|[^|])\|[[:space:]]*($filters)([[:space:]]|\$)/\1| _ /g"   # twice: a match eats the space before the next pipe
    checked=$(sed -E "$pass; $pass" <<<"$cmd")
  fi
fi
m=$(grep -Eo "${start}(($verbs)([[:space:]]|\$)|(bash|sh|zsh|dash)[[:space:]]+-[A-Za-z]*c)|$paths" <<<"$checked" | head -1)
[ -z "$m" ] && [ -n "$cwd" ] && grep -qF "$cwd" <<<"$cmd" && m="the project directory $cwd"
[ -n "$m" ] && deny "$msg (matched '$(sed -E 's/^[;&|({`$[:space:]]+//; s/[[:space:]]+$//' <<<"$m")')"
exit 0
