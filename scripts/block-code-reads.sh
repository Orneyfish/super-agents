#!/usr/bin/env bash
# PreToolUse: keeps the first-time-user subagent blind to the code. Every other agent passes through untouched.
here="$(cd "$(dirname "$0")" && pwd)"; get() { "$here/sa-native.sh" hookio get "$@"; }
in=$(cat)
grep -q 'first-time-user' <<<"$in" || exit 0                                   # cheap pre-filter, most calls end here
"$here/sa-native.sh" --version >/dev/null 2>&1 || { echo '{"systemMessage": "super-agents: the first-time-user code block is off: sa-core is not available here (run super-agents install-core)."}'; exit 0; }
deny() { "$here/sa-native.sh" hookio emit deny "$1"; exit 0; }
# input that does not parse: this hook is the only control on its path, so the first-time-user's call is denied; anyone else is told
at=$(get agent_type <<<"$in") || {
  grep -Eq '"agent_type"[[:space:]]*:[[:space:]]*"([^"]*:)?first-time-user"' <<<"$in" && deny "super-agents: hook input unreadable, so this call is denied for the first-time-user agent."
  "$here/sa-native.sh" hookio emit message "super-agents: hook input unreadable; the first-time-user code block was not evaluated."; exit 0; }
re='(^|:)first-time-user$'; [[ $at =~ $re ]] || exit 0
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
# command's output, not a file, so `curl ... | grep ok` passes. A filter is plain only if it reads nothing but its stdin: any operand is a
# file (`head main.py`), except the one pattern, script or program that grep, sed and jq take (`plain_stage` below). Anything unfamiliar is not plain.
verbs='\.|cat|head|tail|less|more|bat|nl|tac|grep|egrep|rg|ag|ack|find|fd|ls|tree|sed|awk|cut|strings|xxd|od|diff|git|vi|vim|nvim|nano|emacs|source|python3?|node|perl|ruby|eval|exec|xargs|env|sudo|nohup|time|command|sort|uniq|wc|jq|sqlite3|base64|paste|rev|tee|cp|mv|dd|hexdump|column|fold|file|stat|tar|unzip|zcat|cmp|comm|join'
filters='head|tail|grep|egrep|sort|uniq|wc|cut|tr|jq|less|more|sed'
start='(^|[;&|({`]|\$\()[[:space:]]*((then|do|else|elif|if|while|until|!)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*([^[:space:];&|(){`]*/)?'
paths='\.\./|(^|[^A-Za-z0-9])[Ff][Ii][Ll][Ee]:|(^|[ =:"'"'"'<>])\.?/?(src|app|lib|server|backend|frontend|specs)/|\$\([[:space:]]*<|`[[:space:]]*<'
# The words of $1 as the shell splits them: quotes removed, nothing expanded, an unclosed quote runs to the end. Sets W (the words),
# RD (1 for a word that holds an unquoted >, a redirection to a file) and R=1 when an unquoted < appears (a redirection or <(...)
# reads a file). A quote or backslash the shell reads differently only adds words here, which makes a stage less plain, never more.
words() {
  local s=$1 w='' q='' c i have=0 rd=0; W=(); RD=(); R=0
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=
      elif [ "$c" = '\' ] && [ "$q" = '"' ]; then i=$((i + 1)); w+=${s:i:1}
      else w+=$c; fi
    else
      case $c in
        "'"|'"') q=$c; have=1;;
        '\') i=$((i + 1)); w+=${s:i:1}; have=1;;
        [[:space:]]) if ((have)); then W+=("$w"); RD+=("$rd"); w=; have=0; rd=0; fi;;
        '<') R=1; w+=$c; have=1;;
        '>') rd=1; w+=$c; have=1;;
        *) w+=$c; have=1;;
      esac
    fi
  done
  if ((have)); then W+=("$w"); RD+=("$rd"); fi
}
# The text after each | of $1 (STG), cut at | ; & and newlines outside quotes, so a quoted "a|b" is not split in two and the file
# after it stays an operand of its stage. Quotes stay in the text; words() removes them.
stages() {
  local s=$1 w='' q='' c i after=0; STG=()
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=; elif [ "$c" = '\' ] && [ "$q" = '"' ]; then w+=$c; i=$((i + 1)); c=${s:i:1}; fi
      w+=$c; continue
    fi
    case $c in
      "'"|'"') q=$c; w+=$c;;
      '\') i=$((i + 1)); w+=$c${s:i:1};;
      '|'|';'|'&'|$'\n') if ((after)); then STG+=("$w"); fi; w=; after=0; [ "$c" = '|' ] && after=1;;
      *) w+=$c;;
    esac
  done
  if ((after)); then STG+=("$w"); fi
}
# plain_stage "<filter> <args>": succeeds when the filter reads only its stdin. Options that take a value (head -n 5, cut -d , -f 1,
# grep -A 2) are skipped with their value; every other non-option word is an operand, and operands are files. Allowed operands: none,
# except one pattern (grep/egrep, none if -e is used), one script (sed, none if -e is used) or one program (jq). A redirection to a
# file (> out) only writes and is skipped. File options (grep -f/-r, sed -f/-i, sort -o), unknown filters and unknown long options
# fail the check, so the stage counts as reading files.
# Best effort for sed: a script with an r, R, w, W or e command after an address, or an s command with an e or w flag, is rejected too.
plain_stage() {
  local name t i k ch d e sflags vals='' expect='' ops=0 max=0 pat=0 scripts='' op1='' longok redir="^[0-9&]*>>?\$"
  longok='^--(ignore-case|line-number|only-matching|extended-regexp|fixed-strings|count|invert-match|word-regexp|quiet|silent|color(=[a-z]+)?|lines=[+-]?[0-9]+|bytes=[0-9]+|numeric-sort|reverse|unique|raw-output|compact-output|slurp|null-input)$'
  words "$1"; ((R)) && return 1
  name=${W[0]:-}
  case $name in
    head|tail) vals=nc;; cut) vals=dfbc;; sort) vals=ktST;; uniq) vals=fsw;; grep|egrep) vals=ABCme; max=1;;
    sed) vals=el; max=1;; jq) max=1;; wc|less|more) ;; tr) max=-1;; *) return 1;;
  esac
  for ((k = 1; k < ${#W[@]}; k++)); do
    t=${W[k]}
    if [ -n "$expect" ]; then [ "$expect" = e ] && scripts+=" $t"; expect=; continue; fi
    if [ "${RD[k]}" = 1 ]; then   # > file, >> file, 2>/dev/null, 2>&1: output only; a bare > takes the next word as its target
      [[ $t == '>('* ]] && return 1
      [[ $t =~ $redir ]] && expect=\>
      continue
    fi
    case $t in
      --) return 1;;
      --*) [[ $t =~ $longok ]] || return 1;;
      -?*) for ((i = 1; i < ${#t}; i++)); do
             ch=${t:i:1}
             case $name:$ch in
               grep:[rRf]|egrep:[rRf]|sed:[fi]|sort:o) return 1;;
               jq:[!rcsnejaSCMR]) return 1;;
             esac
             if [[ $vals == *"$ch"* ]]; then   # takes a value: the rest of this word, else the next word
               [ "$ch" = e ] && pat=1
               if ((i == ${#t} - 1)); then expect=$ch; else [ "$ch" = e ] && scripts+=" ${t:i+1}"; fi
               break
             fi
           done;;
      *) ops=$((ops + 1)); ((ops == 1)) && op1=$t;;
    esac
  done
  ((pat)) || scripts+=" $op1"
  if [ "$name" = sed ]; then
    [[ $scripts =~ (^|[\;\{\}[:space:]])(/[^/]*/|[0-9\$,!])*[[:space:]]*[rRwWe]([[:space:]]|[A-Za-z0-9_./~-]) ]] && return 1
    for d in / '|' '#' ',' : @ '!' %; do   # s<d>re<d>replacement<d>flags: a flag e runs the result, w writes it to a file
      e=$d; [ "$d" = '|' ] && e='\|'   # an unescaped | is alternation, which would match everything
      sflags="s${e}[^${d}]*${e}[^${d}]*${e}[0-9gpiImM]*[ewW]"
      [[ $scripts =~ $sflags ]] && return 1
    done
  fi
  ((max < 0 || ops <= max - pat))
}
checked=$cmd
if [[ $cmd =~ ^[[:space:]]*(curl|wget|bash|sh|[^[:space:]]*/) ]]; then
  plain=1; stages "$cmd"
  for seg in "${STG[@]}"; do
    words "$seg"; [[ ${W[0]:-} =~ ^($filters)$ ]] && { plain_stage "$seg" || plain=0; }
  done
  if [ "$plain" = 1 ]; then
    pass="s/(^|[^|])\|[[:space:]]*($filters)([[:space:]]|\$)/\1| _ /g"   # twice: a match eats the space before the next pipe
    checked=$(sed -E "$pass; $pass" <<<"$cmd")
  fi
fi
m=$(grep -Eo "${start}(($verbs)([[:space:]]|\$)|(bash|sh|zsh|dash)[[:space:]]+-[A-Za-z]*c)|$paths" <<<"$checked" | head -1)
[ -z "$m" ] && [ -n "$cwd" ] && grep -qF "$cwd" <<<"$cmd" && m="the project directory $cwd"
[ -n "$m" ] && deny "$msg (matched '$(sed -E 's/^[;&|({`$[:space:]]+//; s/[[:space:]]+$//' <<<"$m")')"
exit 0
