#!/usr/bin/env bash
# Usage: check-evals.sh <feature-dir> [--ready] [--passed]       e.g. specs/checkout or specs/tickets/003-login
#   (no flag)  RD.md + evals.md are well formed: every requirement is covered, every eval complete, no TODO left
#   --ready    also **Status:** must be ready (the user approved the evals)
#   --passed   also every eval has a pass row in results.md and its evidence file exists
# Exit 0 = ok. Exit 1 = every problem printed as a FAIL line.
d="${1:?feature dir}"; shift; rd="$d/RD.md"; ev="$d/evals.md"; rs="$d/results.md"; bad=0; ready=0; passed=0
for a; do case $a in --ready) ready=1;; --passed) passed=1;; esac; done
fail() { echo "FAIL: $*"; bad=1; }
[ -f "$rd" ] || fail "missing $rd"; [ -f "$ev" ] || fail "missing $ev"
[ "$bad" = 1 ] && exit 1

hdr() { sed -n "s/^\*\*$1:\*\* *\([a-z]*\).*/\1/p" "$rd" | head -1; }
st=$(hdr Status); rk=$(hdr Risk)
case "$st" in draft|ready|building|done) ;; *) fail "RD.md needs '**Status:** draft|ready|building|done' (got '$st')";; esac
case "$rk" in low|medium|high) ;; *) fail "RD.md needs '**Risk:** low|medium|high' (got '$rk')";; esac
[ "$ready" = 1 ] && [ "$st" != ready ] && fail "Status is '$st'; the user must approve the evals (Status: ready) before building"

grep -qE '^- (N?FR)-[0-9]+:' "$rd" || fail "RD.md defines no requirements (lines like '- FR-1: ...')"
for r in $(grep -oE '^- (N?FR)-[0-9]+:' "$rd" | sed -E 's/^- (.*):$/\1/'); do
  grep -qE "^- covers:.*\b$r\b" "$ev" || fail "$r has no eval that covers it"
done

grep -qiE '^UI: *yes' "$rd" && { [ -f "$d/mockup.html" ] || fail "RD.md says UI: yes but $d/mockup.html is missing"; }
grep -n 'TODO' "$rd" "$ev" | sed 's/^/FAIL: unfilled placeholder -> /' | grep . && bad=1

awk '
  function flush(  i, F) { if (id == "") return
    split("covers check pass_when fail_when", F, " ")
    for (i in F) if (!(F[i] in s)) { print "FAIL: " id " is missing its \"" F[i] "\" line"; bad = 1 } }
  /^## E-?[0-9]+/ { flush(); id = $2; delete s; n++; next }
  /^- covers:/    { s["covers"] = 1 }
  /^- check:/     { s["check"] = 1 }
  /^- pass when:/ { s["pass_when"] = 1 }
  /^- fail when:/ { s["fail_when"] = 1 }
  END { flush(); if (n == 0) { print "FAIL: no evals found (expected \"## E1: title\" blocks)"; bad = 1 } exit bad }
' "$ev" || bad=1

if [ "$passed" = 1 ]; then
  for id in $(grep -oE '^## E-?[0-9]+' "$ev" | sed 's/## //'); do
    row=$(grep -E "^\| *$id *\|" "$rs" 2>/dev/null | head -1)
    res=$(awk -F'|' '{gsub(/ /,"",$3); print $3}' <<<"$row"); evc=$(awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}' <<<"$row")
    [ "$res" = pass ] || { fail "$id is not passing (results.md says '${res:-no row}')"; continue; }
    [[ $evc == evidence/* ]] && [ ! -f "$d/${evc%%[ :]*}" ] && fail "$id evidence file ${evc%%[ :]*} does not exist"
  done
fi

[ "$bad" = 0 ] && echo "OK: $d"
exit "$bad"
