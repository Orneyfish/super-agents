#!/usr/bin/env bash
# Usage: check-evals.sh <feature-dir> [--ready] [--passed]       e.g. specs/checkout or specs/tickets/003-login
#   (no flag)  RD.md + evals.md are well formed: every requirement is covered, every eval complete, no TODO left, **Kind:** (missing = code) is a known kind, a non-code kind names a **Deliverable:** and every deliverable path is repo-relative, not under specs/ or .git/, and not git-ignored
#   --ready    also **Status:** must be ready (the user approved the evals)
#   --passed   also every deliverable is a non-empty regular file (no directory, no symlink) in this checkout, every eval has exactly one row in results.md, a pass pointing at a non-empty evidence/ file, a Review line (if any) says clean or findings-fixed, and evals.md and RD.md (its Status line aside) match the fingerprints written at approval (no fingerprint = fail)
# Exit 0 = ok. Exit 1 = every problem printed as a FAIL line.
here="$(cd "$(dirname "$0")" && pwd)"; d="${1:?feature dir}"; shift; rd="$d/RD.md"; ev="$d/evals.md"; rs="$d/results.md"; bad=0; ready=0; passed=0
for a; do case $a in --ready) ready=1;; --passed) passed=1;; esac; done
fail() { echo "FAIL: $*"; bad=1; }
[ -f "$rd" ] || fail "missing $rd"; [ -f "$ev" ] || fail "missing $ev"
[ "$bad" = 1 ] && exit 1

hdr() { sed -n "s/^\*\*$1:\*\* *\([a-z]*\).*/\1/p" "$rd" | head -1; }
st=$(hdr Status); rk=$(hdr Risk)
case "$st" in draft|ready|building|done) ;; *) fail "RD.md needs '**Status:** draft|ready|building|done' (got '$st')";; esac
case "$rk" in low|medium|high) ;; *) fail "RD.md needs '**Risk:** low|medium|high' (got '$rk')";; esac
# keep equal to the headings of templates/kinds.md (tests/run.sh checks it)
kinds="code document research analysis design plan operations"
kind=$(sed -n 's/^\*\*Kind:\*\* *\([^[:space:]]*\).*/\1/p' "$rd" | head -1); kind=${kind:-code}
case " $kinds " in *" $kind "*) ;; *) fail "RD.md '**Kind:**' must be one of: $kinds (got '$kind')";; esac
# a deliverable may hold spaces, dots and slashes, so it is read whole instead of with hdr
deliv=$(sed -n 's/^\*\*Deliverable:\*\*[[:space:]]*//p' "$rd" | head -1 | tr -d '\r' | sed 's/[[:space:]]*$//')
[ "$kind" != code ] && [ -z "$deliv" ] && fail "a $kind piece of work needs '**Deliverable:** <path>[, <path>]' in RD.md"
# okpath PATH: letters, digits, . _ - and spaces in parts joined by single slashes (C locale, so it is the same on every machine);
# no '.' or '..' part, and not under specs/ or the tool's own state in any letter case (macOS and Windows ignore case)
okpath() { local LC_ALL=C re='^[A-Za-z0-9._ -]+(/[A-Za-z0-9._ -]+)*$' l; [[ $1 =~ $re && $1 != *..* ]] || return 1
  l=$(printf '%s' "$1" | tr 'A-Z' 'a-z'); case "/$l/" in */./*|/specs/*|/.git/*|/.super-agents/*|/.job/*) return 1;; esac; }
delivs=(); if [ -n "$deliv" ]; then while IFS= read -r p; do p=$(sed 's/^ *//;s/ *$//' <<<"$p")
  p=${p#'`'}; p=${p%'`'}   # models write paths in markdown backticks; accept one pair around a path
  okpath "$p" || fail "deliverable '$p' must be a path inside the repository: letters, digits, . _ / - and spaces, no '.' or '..' part, not absolute, not under specs/, .git/, .super-agents/ or .job/"
  delivs+=("$p"); done <<<"$(tr ',' '\n' <<<"$deliv")"
  # an ignored file is never committed: it would pass in a worker's worktree and be missing after the merge
  if dtop=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null); then for p in "${delivs[@]}"; do
    git -C "$dtop" check-ignore -q -- "$p" 2>/dev/null && fail "deliverable '$p' is git-ignored, so it would never be committed; name a path git tracks or change .gitignore"; done; fi
fi
[ "$ready" = 1 ] && [ "$st" != ready ] && fail "Status is '$st'; the user must approve the evals (Status: ready) before building"

grep -qE '^- (N?FR)-[0-9]+:' "$rd" || fail "RD.md defines no requirements (lines like '- FR-1: ...')"
for r in $(grep -oE '^- (N?FR)-[0-9]+:' "$rd" | sed -E 's/^- (.*):$/\1/'); do
  grep -qE "^- covers:.*[^A-Za-z0-9-]$r([^A-Za-z0-9-]|\$)" "$ev" || fail "$r has no eval that covers it"
done

grep -qiE '^UI: *yes' "$rd" && { [ -f "$d/mockup.html" ] || fail "RD.md says UI: yes but $d/mockup.html is missing"; }
# text inside `backticks` is ignored, so a feature that really uses the word (a todo app) can write `TODO`
todo=$(awk '{ l = $0; gsub(/`[^`]*`/, "", l) } l ~ /TODO/ { print "FAIL: unfilled placeholder (put the word in `backticks` if the feature really uses it) -> " FILENAME ":" FNR ":" $0 }' "$rd" "$ev")
[ -n "$todo" ] && { echo "$todo"; bad=1; }

awk '
  function flush(  i, F) { if (id == "") return
    split("covers check pass_when fail_when", F, " ")
    for (i in F) if (!(F[i] in s)) { print "FAIL: " id " is missing its \"" F[i] "\" line"; bad = 1 } }
  /^## E-?[0-9]+([:[:space:]]|$)/ { flush(); match($0, /E-?[0-9]+/); id = substr($0, RSTART, RLENGTH); delete s; n++; next }
  /^- covers:/    { s["covers"] = 1 }
  /^- check:/     { s["check"] = 1 }
  /^- pass when:/ { s["pass_when"] = 1 }
  /^- fail when:/ { s["fail_when"] = 1 }
  END { flush(); if (n == 0) { print "FAIL: no evals found (expected \"## E1: title\" blocks)"; bad = 1 } exit bad }
' "$ev" || bad=1

if [ "$passed" = 1 ]; then
  fp="$d/.evals.sha256"   # written by 'super-agents board set ... ready'
  # a worker runs in a git worktree and could rewrite its own copy, so prefer the user's copy in the main checkout
  main=$(cd "$d" && "$here/sa-native.sh" board root 2>/dev/null)
  if [ -n "$main" ] && pre=$(git -C "$d" rev-parse --show-prefix 2>/dev/null); then
    [ -f "$main/${pre}.evals.sha256" ] && fp="$main/${pre}.evals.sha256"
    # a worker's worktree (.claude/worktrees/*): only the user's copy counts, never a fingerprint the worker wrote itself
    case "$(cd "$d" && pwd -P)" in "$(cd "$main" && pwd -P)"/.claude/worktrees/*) fp="$main/${pre}.evals.sha256";; esac
  fi
  if [ -f "$fp" ]; then
    if got=$("$here/sa-native.sh" fingerprint "$ev"); then
      [ "$got" = "$(sed -n 1p "$fp" | tr -d ' \r\n')" ] || fail "evals.md changed after the user approved it; restore it (git checkout) or ask the user to re-approve"
      # line 2, "<hex>  RD.md": RD.md as approved, without its Status line. A one-line file was written by an older version: nothing to compare.
      want=$(sed -n '2s/[[:space:]].*//p' "$fp")
      if [ -n "$want" ]; then [ "$("$here/sa-native.sh" fingerprint-rd "$rd")" = "$want" ] || fail "RD.md changed after the user approved it; restore it (git checkout) or ask the user to re-approve"; fi
    else
      fail "could not fingerprint $ev; run 'super-agents install-core'"
    fi
  else   # no fingerprint means nothing proves these are the approved evals; tickets approved before fingerprints existed need one re-approval
    fail "no approval fingerprint (.evals.sha256) for $d; ask the user to approve it again with mark-ready"
  fi
  # a Review line, when results.md has one, must say the review ended without open findings (a file without the line is older or hand-made)
  if rv=$(grep -m1 '^\*\*Review:\*\*' "$rs" 2>/dev/null); then
    case "$rv" in '**Review:** clean'*|'**Review:** findings-fixed'*) ;; *) fail "the review is not finished or has open findings (results.md says '$rv')";; esac
  fi
  for id in $(grep -oE '^## E-?[0-9]+([:[:space:]]|$)' "$ev" | grep -oE 'E-?[0-9]+'); do
    rows=$(grep -cE "^\| *$id *\|" "$rs" 2>/dev/null)
    [ "${rows:-0}" -le 1 ] || { fail "$id has $rows rows in results.md; one row per eval, from the last tester run"; continue; }
    row=$(grep -E "^\| *$id *\|" "$rs" 2>/dev/null | head -1)
    res=$(awk -F'|' '{gsub(/ /,"",$3); print tolower($3)}' <<<"$row"); evc=$(awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}' <<<"$row")
    [ "$res" = pass ] || { fail "$id is not passing (results.md says '${res:-no row}')"; continue; }
    ef=${evc%%[ :]*}
    [[ $ef == evidence/* && $ef != *..* ]] || { fail "$id passes without an evidence/ file (results.md says '${evc:-nothing}')"; continue; }
    [ -s "$d/$ef" ] || fail "$id evidence file $ef does not exist or is empty"
  done
  # the deliverable is looked up in this checkout (a worker's own worktree for a ticket), not in the main one
  if [ ${#delivs[@]} -gt 0 ]; then
    if top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null); then
      topr=$(cd "$top" && pwd -P)
      for p in "${delivs[@]}"; do f="$top/$p"
        [ -s "$f" ] || { fail "deliverable '$p' does not exist or is empty in $top"; continue; }
        # a directory, a symlink, or a file reached through a symlinked folder is not work kept in this checkout
        dr=$(cd "$(dirname "$f")" 2>/dev/null && pwd -P)
        { [ -f "$f" ] && [ ! -L "$f" ] && case "$dr/" in "$topr"/*) true;; *) false;; esac; } || fail "deliverable '$p' must be a regular file inside $top, not a directory or a symlink"
      done
    else fail "cannot check the deliverable: $d is not inside a git repository"; fi
  fi
fi

[ "$bad" = 0 ] && echo "OK: $d"
exit "$bad"
