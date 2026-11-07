#!/usr/bin/env bash
# Regression tests for the deterministic parts: validator, board, both gates, heartbeat, watchdog scan,
# init, launcher and the tool-use / session hooks. The agents and skills are prompts: test those live (see README).
# Usage: tests/run.sh      Exit 0 = all passed.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"; X="$R/scripts"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0; LAST=""
# the plugin must not need jq: any script that calls it fails loudly against this shim
mkdir -p "$T/nojq"; printf '#!/bin/sh\necho "jq was called, but the plugin must work without it" >&2\nexit 97\n' > "$T/nojq/jq"; chmod +x "$T/nojq/jq"; PATH="$T/nojq:$PATH"
jget() { "$X/hookio.py" get "$1"; }                                   # value of a path in the JSON on stdin
js() { python3 -c 'import json,sys;print(json.dumps(dict(a.split("=",1) for a in sys.argv[1:])))' "$@"; }   # js k=v ... : a flat JSON object of strings
t()   { local n=$1 want=$2; shift 2; LAST=$("$@" 2>&1); local rc=$?; [ "$rc" = "$want" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL $n: exit $rc, wanted $want"; echo "$LAST" | head -4; }; }
has() { grep -qF -- "$2" <<<"$LAST" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL $1: output lacks '$2'"; echo "$LAST" | head -4; }; }
hasnt() { grep -qF -- "$2" <<<"$LAST" && { fail=$((fail+1)); echo "FAIL $1: output has '$2'"; } || pass=$((pass+1)); }
silent() { [ -z "$LAST" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL $1: expected no output, got: $LAST" | head -3; }; }
# portable between GNU and BSD/macOS userlands: in-place sed, "N minutes ago" timestamp, backdated mtime
sedi() { local f=${!#}; sed -i.bak "$@" && rm -f "$f.bak"; }
iso() { python3 -c 'import datetime as d,sys;print((d.datetime.now(d.timezone.utc)-d.timedelta(minutes=float(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
age() { python3 -c 'import os,sys,time;t=time.time()-float(sys.argv[2])*3600;os.utime(sys.argv[1],(t,t))' "$1" "$2"; }

# ---- hookio.py (the JSON glue that replaces jq)
H=$X/hookio.py; eq() { [ "$2" = "$3" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL $1: got '$2', wanted '$3'"; }; }
J='{"a":{"b":"x y"},"n":5,"o":{"k":[1]},"z":null,"t":true}'
eq hookio-get-nested "$(echo "$J" | $H get a.b)" "x y";            eq hookio-get-number "$(echo "$J" | $H get n)" 5
eq hookio-get-object "$(echo "$J" | $H get o)" '{"k":[1]}';        eq hookio-get-bool "$(echo "$J" | $H get t)" true
eq hookio-get-missing "$(echo "$J" | $H get a.nope.deeper)" "";    eq hookio-get-null "$(echo "$J" | $H get z)" ""
eq hookio-get-bad-json "$(echo '{oops' | $H get a 2>/dev/null)" ""; t hookio-bad-json-exit 1 bash -c "echo '{oops' | $H get a"
# each response is parsed and checked at the exact path Claude Code reads, so a field under the wrong parent fails
t hookio-emit-block 0 $H emit block 'line1
line2 "quoted" é';                                                  eq hookio-emit-block "$(echo "$LAST" | $H get decision)" block
eq hookio-emit-roundtrip "$(echo "$LAST" | $H get reason)" 'line1
line2 "quoted" é'
t hookio-emit-deny 0 $H emit deny why;                              eq hookio-emit-deny "$(echo "$LAST" | $H get hookSpecificOutput.permissionDecision)/$(echo "$LAST" | $H get hookSpecificOutput.permissionDecisionReason)/$(echo "$LAST" | $H get hookSpecificOutput.hookEventName)" "deny/why/PreToolUse"
t hookio-emit-context 0 $H emit context hi;                         eq hookio-emit-context "$(echo "$LAST" | $H get hookSpecificOutput.additionalContext)/$(echo "$LAST" | $H get hookSpecificOutput.hookEventName)" "hi/SessionStart"
t hookio-emit-message 0 $H emit message hi;                         eq hookio-emit-message "$(echo "$LAST" | $H get systemMessage)" hi; eq hookio-emit-message-top-level "$(echo "$LAST" | $H get hookSpecificOutput)" ""
t hookio-usage 1 $H

# ---- fixture: git repo with three tickets
cd "$T" && mkdir repo && cd repo && git init -q -b main && git config user.email t@t && git config user.name t && echo x > f && git add . && git commit -qm init
mk() { d=specs/tickets/$1-$2; mkdir -p $d
  printf '# %s\n\n**Status:** %s\n**Risk:** low\n\n## Functional requirements\n- FR-1: a\n- NFR-1: b\n\nUI: no\n' "$2" "$3" > $d/RD.md
  printf '# E\n\n## E1: a\n- covers: FR-1\n- check: c\n- pass when: p\n- fail when: f\n\n## E2: b\n- covers: NFR-1\n- check: c\n- pass when: p\n- fail when: f\n' > $d/evals.md; }
mk 001 found draft; mk 002 reset draft; mk 003 profile draft
printf '# Board\n| # | Title | Status | Mode | Runs |\n|---|---|---|---|---|\n| 001 | Found | draft | team | alongside |\n| 002 | Reset | draft | solo | waits for 001: mailer |\n| 003 | Profile | draft | solo | alongside |\n' > specs/tickets/BOARD.md
D=specs/tickets/001-found

# ---- board.py
t board-ok 0 $X/board.py check;                                  has board-ok "OK: board (3 tickets)"
sedi 's/waits for 001/waits for 009/' specs/tickets/BOARD.md; t board-missing-dep 1 $X/board.py check; has board-missing-dep "not on the board"; sedi 's/waits for 009/waits for 001/' specs/tickets/BOARD.md
cp specs/tickets/BOARD.md B.bak; sedi 's/| 001 | Found | draft | team | alongside |/| 001 | Found | draft | team | waits for 002: x |/' specs/tickets/BOARD.md; t board-cycle 1 $X/board.py check; has board-cycle "dependency cycle"; cp B.bak specs/tickets/BOARD.md
t set-ticket 0 $X/board.py set 001 ready;                         grep -q '| 001 | Found | ready' specs/tickets/BOARD.md && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL set-ticket: board row"; }
t set-dir-syncs-row 0 $X/board.py set specs/tickets/002-reset ready; t board-still-ok 0 $X/board.py check
t set-bad-status 1 $X/board.py set 001 wip
mkdir -p sub/deep; t set-from-subdir 0 bash -c "cd sub/deep && $X/board.py set 001 building"; t board-ok-2 0 $X/board.py check

# ---- check-evals.sh
t eval-structure 0 $X/check-evals.sh $D
t eval-ready-while-building 1 $X/check-evals.sh $D --ready;       has eval-ready-while-building "must approve"
$X/board.py set $D ready >/dev/null; t eval-ready 0 $X/check-evals.sh $D --ready
t eval-passed-no-results 1 $X/check-evals.sh $D --passed;          has eval-passed-no-results "no row"
mkdir -p $D/evidence; echo ok > $D/evidence/a.png
printf '| eval | result | evidence |\n|---|---|---|\n| E1 | pass | evidence/a.png: ok |\n| E2 | fail | slow |\n' > $D/results.md
t eval-passed-failing 1 $X/check-evals.sh $D --passed;             has eval-passed-failing "E2 is not passing"
sedi 's#| E2 | fail | slow |#| E2 | pass | evidence/gone.png: ok |#' $D/results.md
t eval-passed-missing-file 1 $X/check-evals.sh $D --passed;        has eval-passed-missing-file "does not exist"
echo ok > $D/evidence/gone.png; t eval-passed 0 $X/check-evals.sh $D --passed
# a pass row must point at a real, non-empty evidence/ file: free text, path tricks and empty files are not proof
printf '| eval | result | evidence |\n|---|---|---|\n| E1 | pass | evidence/a.png: ok |\n| E2 | pass | trust me |\n' > $D/results.md
t eval-passed-free-text 1 $X/check-evals.sh $D --passed;           has eval-passed-free-text "without an evidence/ file"
sedi 's#trust me#evidence/../RD.md#' $D/results.md
t eval-passed-traversal 1 $X/check-evals.sh $D --passed;           has eval-passed-traversal "without an evidence/ file"
sedi 's#evidence/../RD.md#evidence/gone.png: ok#' $D/results.md; : > $D/evidence/gone.png
t eval-passed-empty-file 1 $X/check-evals.sh $D --passed;          has eval-passed-empty-file "does not exist or is empty"
echo ok > $D/evidence/gone.png; t eval-passed-again 0 $X/check-evals.sh $D --passed
# #7: a fingerprint with CRLF line ends (Windows, or git autocrlf) still matches
cp $D/.evals.sha256 $T/fp.bak; sed 's/$/\r/' $T/fp.bak > $D/.evals.sha256; t eval-passed-crlf-fingerprint 0 $X/check-evals.sh $D --passed; cp $T/fp.bak $D/.evals.sha256
# the evals the user approved are fingerprinted when marked ready; changing them afterwards fails the gate
[ -s $D/.evals.sha256 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL ready did not write .evals.sha256"; }
cp $D/evals.md $T/evals.bak; printf '\n<!-- loosened -->\n' >> $D/evals.md
t eval-tampered 1 $X/check-evals.sh $D --passed;                   has eval-tampered "changed after the user approved"
cp $T/evals.bak $D/evals.md; t eval-untampered 0 $X/check-evals.sh $D --passed
# a worker's worktree copy: even with its own fingerprint file deleted, the main checkout's copy still catches the change
git worktree add -q $T/wt2 -b w2 >/dev/null 2>&1; mkdir -p $T/wt2/$D; cp -R $D/. $T/wt2/$D/; rm -f $T/wt2/$D/.evals.sha256
t eval-worktree-clean 0 $X/check-evals.sh $T/wt2/$D --passed
printf '\n<!-- loosened -->\n' >> $T/wt2/$D/evals.md
t eval-worktree-tampered 1 $X/check-evals.sh $T/wt2/$D --passed;   has eval-worktree-tampered "changed after the user approved"
git worktree remove --force $T/wt2
cp $D/evals.md $T/evals.bak; sedi 's/covers: NFR-1/covers: FR-1/' $D/evals.md; t eval-uncovered 1 $X/check-evals.sh $D; has eval-uncovered "NFR-1 has no eval"; cp $T/evals.bak $D/evals.md
# FR-1 must not count as covered just because an eval covers NFR-1 or FR-10
cp $D/evals.md $T/evals.bak; sedi 's/covers: FR-1$/covers: NFR-1, FR-10/' $D/evals.md; t eval-uncovered-lookalike 1 $X/check-evals.sh $D; has eval-uncovered-lookalike "FR-1 has no eval"; cp $T/evals.bak $D/evals.md
cp $D/RD.md $T/rd.bak
printf '\nTODO fill\n' >> $D/RD.md; t eval-todo 1 $X/check-evals.sh $D;                has eval-todo "unfilled placeholder"
cp $T/rd.bak $D/RD.md; printf '\nUsers can add a `TODO` item.\n' >> $D/RD.md; t eval-todo-backticked 0 $X/check-evals.sh $D
cp $T/rd.bak $D/RD.md
# H3: a ticket with no approval fingerprint anywhere cannot pass (a worker could have deleted or never had one)
# L2: the tester prints PASS, the gate takes it in any case. L5: '## E2E ...' is not an eval, and an id never keeps its colon
fp() { python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1/evals.md" > "$1/.evals.sha256"; }
mkfix() { mkdir -p $1/evidence; echo ok > $1/evidence/E1.txt
  printf '# t\n\n**Status:** building\n**Risk:** low\n\n## Functional requirements\n- FR-1: a\n\nUI: no\n' > $1/RD.md
  printf '# E\n\n## Setup\nx\n\n## E1: a\n- covers: FR-1\n- check: c\n- pass when: p\n- fail when: f\n' > $1/evals.md
  printf '| eval | result | evidence |\n|---|---|---|\n| E1 | PASS | evidence/E1.txt: ok |\n' > $1/results.md; }
F=$T/f1; mkfix $F
t eval-no-fingerprint 1 $X/check-evals.sh $F --passed;             has eval-no-fingerprint "no approval fingerprint"
fp $F; t eval-pass-uppercase 0 $X/check-evals.sh $F --passed
printf '\n## E2E setup\nStart the browser first.\n' >> $F/evals.md; fp $F
t eval-e2e-heading 0 $X/check-evals.sh $F;                         t eval-e2e-heading-passed 0 $X/check-evals.sh $F --passed
sedi 's/^- check: c$//' $F/evals.md
t eval-missing-line 1 $X/check-evals.sh $F;                        has eval-missing-line 'FAIL: E1 is missing its "check" line'
# PR review: a worker's worktree lives in .claude/worktrees; a fingerprint the worker wrote there must not count when the user's checkout has none
M3=$T/m3; mkfix $M3/specs/tickets/001-x; git -C $M3 init -q -b main; git -C $M3 add -A >/dev/null; git -C $M3 -c user.email=t@t -c user.name=t commit -qm base
mkdir -p $M3/.claude; git -C $M3 worktree add -q $M3/.claude/worktrees/w -b w; WT=$M3/.claude/worktrees/w/specs/tickets/001-x
fp $WT; t eval-worker-forged-fp 1 $X/check-evals.sh $WT --passed;   has eval-worker-forged-fp "no approval fingerprint"
fp $M3/specs/tickets/001-x; t eval-worker-main-fp 0 $X/check-evals.sh $WT --passed

# ---- eval-gate.sh (Stop hook of the review-loop)
mkdir -p .super-agents; st=.super-agents/state.md; in="{\"cwd\":\"$T/repo\"}"
state() { printf -- "---\ndir: %s\nactive: %s\nawaiting_user: %s\ngate_blocks: %s\n---\n" "${1:-$D}" "${2:-true}" "${3:-false}" "${4:-0}" > $st; }
gate() { LAST=$(echo "$in" | $X/eval-gate.sh); }
state; gate; silent gate-passing
sedi 's/| E2 | pass |/| E2 | fail |/' $D/results.md
state; gate; has gate-blocks '"decision": "block"'; grep -q 'gate_blocks: 1' $st && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL gate counter"; }
state $D true true; gate; silent gate-awaiting-user
state $D false; gate; silent gate-inactive
state $D true false 3; gate; has gate-cap "released after 3 blocks"
state ../../etc; gate; silent gate-path-traversal
state; age $st 13; gate; silent gate-stale
# M5: the first session to stop claims the loop; a second session in the same repo is never gated by it
gs() { LAST=$(echo "{\"cwd\":\"$T/repo\",\"session_id\":\"$1\"}" | $X/eval-gate.sh); }
state; gs A; has gate-session-claim '"decision": "block"'; grep -q '^session: A' $st && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL gate did not record the owning session"; }
gs B; silent gate-other-session
gs A; has gate-owner-still-gated '"decision": "block"'
# PR review: two sessions stopping at the same moment still leave exactly one owner
for i in 1 2 3 4 5; do state
  echo "{\"cwd\":\"$T/repo\",\"session_id\":\"A\"}" | $X/eval-gate.sh > $T/ra.out & echo "{\"cwd\":\"$T/repo\",\"session_id\":\"B\"}" | $X/eval-gate.sh > $T/rb.out & wait
  [ "$(cat $T/ra.out $T/rb.out | grep -c '"decision": "block"')" = 1 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL gate race round $i: not exactly one session was gated"; }
done
# #5: a state file whose last line has no newline must not swallow the claim ("---session: A")
printf -- "---\ndir: %s\nactive: true\nawaiting_user: false\ngate_blocks: 0\n---" "$D" > $st
gs A; has gate-claim-no-newline '"decision": "block"'
grep -q '^session: A$' $st && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL gate-claim-no-newline: the claim is not on its own line: $(tail -c 40 $st)"; }
gs B; silent gate-claim-no-newline-other
# #5: a loop that recorded its owner when it started is gated only for that owner, whichever session stops first
printf -- "---\ndir: %s\nactive: true\nawaiting_user: false\ngate_blocks: 0\nsession: A\n---\n" "$D" > $st
gs B; silent gate-recorded-owner-other-first
gs A; has gate-recorded-owner-gated '"decision": "block"'
sedi 's/| E2 | fail |/| E2 | pass |/' $D/results.md; rm -rf .super-agents

# ---- job-status.sh + worker-gate.sh (SubagentStop)
W=$T/wt; mkdir -p $W; cd $W || exit
t job-init 0 $X/job-status.sh init 001 "$T/repo/$D" building; [ "$(jget phase < .job/status.json)" = building ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL job-init"; }
# PR review: a worker restarted in an old worktree starts with a fresh block count
echo 3 > .job/gate_blocks; $X/job-status.sh init 001 "$T/repo/$D" building; [ ! -f .job/gate_blocks ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL init kept the old gate_blocks"; }
t job-update 0 $X/job-status.sh testing "note"; [ "$(jget phase < .job/status.json)$(jget note < .job/status.json)" = testingnote ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL job-update"; }
t job-team-file 0 $X/job-status.sh --name 001-a init 001 "$T/repo/$D" building; [ -f .job/status-001-a.json ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL job-team-file"; }
wg() { LAST=$(echo "{\"cwd\":\"$W\",\"agent_type\":\"$1\"}" | $X/worker-gate.sh); }
wg super-agents:builder; silent wgate-other-agent
sedi 's/| E2 | pass |/| E2 | fail |/' $T/repo/$D/results.md
wg super-agents:worker; has wgate-blocks '"decision": "block"'
# #7: only this plugin's worker is gated; another plugin's (or a bare) 'worker' gets neither a block nor a notice
wg other-plugin:worker; silent wgate-other-plugin-worker; wg worker; silent wgate-bare-worker
$X/job-status.sh blocked why; wg super-agents:worker; silent wgate-blocked-phase
$X/job-status.sh building; echo 3 > .job/gate_blocks; wg super-agents:worker; has wgate-cap "released after 3 blocks"
# M2: going back to building (a fix round) starts a fresh block count
echo 2 > .job/gate_blocks; $X/job-status.sh building; [ ! -f .job/gate_blocks ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL building did not reset gate_blocks"; }
sedi 's/| E2 | fail |/| E2 | pass |/' $T/repo/$D/results.md; wg super-agents:worker; silent wgate-passing
# M2: init stores an absolute ticket dir; a relative one in status.json is resolved against the worker's cwd, not the hook's
W3=$T/wt3; mkdir -p $W3/$D $W3/.job; cp -R $T/repo/$D/. $W3/$D/; sedi 's/| E2 | pass |/| E2 | fail |/' $W3/$D/results.md
(cd $W3 && $X/job-status.sh init 001 $D building); [[ $(jget dir < $W3/.job/status.json) == /* ]] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL job-status init kept a relative dir"; }
sedi 's#"dir": "[^"]*"#"dir": "specs/tickets/001-found"#' $W3/.job/status.json
cd $T/repo || exit; LAST=$(echo "{\"cwd\":\"$W3\",\"agent_type\":\"super-agents:worker\"}" | $X/worker-gate.sh); has wgate-relative-dir '"decision": "block"'
# M2: a worker whose gate cannot run is told so
LAST=$(echo "{\"cwd\":\"$T/np\",\"agent_type\":\"super-agents:worker\"}" | $X/worker-gate.sh); has wgate-skip-notice "worker gate skipped"
cd $T/repo || exit

# ---- board.py scan (watchdog)
$X/board.py set 001 building >/dev/null
t scan-no-heartbeat 0 $X/board.py scan;                           has scan-no-heartbeat "no status file"
mkdir -p .job; js ticket=001 phase=testing started="$(iso 3)" updated="$(iso 2)" note="" agent=a > .job/status-001-a.json
t scan-healthy 0 $X/board.py scan;                                silent scan-healthy
js ticket=001 phase=building started="$(iso 41)" updated="$(iso 40)" note="" agent=a > .job/status-001-a.json
t scan-silent 0 $X/board.py scan;                                 has scan-silent "silent for"
# a worker in testing/reviewing is blocked on its own tester/reviewer and cannot heartbeat: it gets wait_min (45), not stale_min (15)
js ticket=001 phase=testing started="$(iso 41)" updated="$(iso 40)" note="" agent=a > .job/status-001-a.json
t scan-waiting-ok 0 $X/board.py scan;                             silent scan-waiting-ok
js ticket=001 phase=testing started="$(iso 51)" updated="$(iso 50)" note="" agent=a > .job/status-001-a.json
t scan-waiting-too-long 0 $X/board.py scan;                       has scan-waiting-too-long "silent for"
js ticket=001 phase=building started="$(iso 41)" updated="$(iso 40)" note="" agent=a > .job/status-001-a.json
mkdir -p .super-agents; printf 'ignore=001\n' > .super-agents/watchdog.conf; t scan-ignore 0 $X/board.py scan; silent scan-ignore
js ticket=001 phase=blocked started="$(iso 2)" updated="$(iso 1)" note="db down" agent=a > .job/status-001-a.json; : > .super-agents/watchdog.conf
t scan-blocked 0 $X/board.py scan;                                has scan-blocked "blocked: db down"
# L6: one unreadable status file or one bad number in watchdog.conf must not hide the other problems
$X/board.py set 003 building >/dev/null
js ticket=001 phase=building agent=a > .job/status-001-a.json
t scan-malformed 0 $X/board.py scan;                              has scan-malformed "001 status file unreadable"; has scan-malformed-others "003 is 'building'"
printf '{not json' > .job/status-001-a.json
t scan-badjson 0 $X/board.py scan;                                has scan-badjson "status-001-a.json unreadable"
js ticket=001 phase=building started="$(iso 41)" updated="$(iso 40)" note="" agent=a > .job/status-001-a.json; printf 'stale_min=abc\n' > .super-agents/watchdog.conf
t scan-bad-conf 0 $X/board.py scan;                               has scan-bad-conf "silent for"
# PR review: nan/inf thresholds fall back to the defaults, one bad file does not hide its siblings, a finished ticket's stale file is not a problem
printf 'stale_min=nan\nslow_min=inf\n' > .super-agents/watchdog.conf
t scan-nonfinite 0 $X/board.py scan;                              has scan-nonfinite "silent for"
: > .super-agents/watchdog.conf
js ticket=001 phase=building agent=a > .job/status-001-a.json
js ticket=001 phase=blocked started="$(iso 6)" updated="$(iso 5)" note="db down" agent=b > .job/status-001-b.json
t scan-malformed-sibling 0 $X/board.py scan;                      has scan-malformed-sibling "blocked: db down"; has scan-malformed-sibling-flag "unreadable"
rm -f .job/status-001-b.json; printf 'ignore=001,003\n' > .super-agents/watchdog.conf; printf '{broken' > .job/status-001-a.json
t scan-stale-unreadable 0 $X/board.py scan;                       silent scan-stale-unreadable
: > .super-agents/watchdog.conf
$X/board.py set 003 ready >/dev/null

# L1: a bad interval_min falls back to 10 minutes (with a warning) instead of busy-looping or killing the watchdog
mkdir -p $T/fs; printf '#!/bin/sh\necho "SLEEP $1"\nkill $PPID\n' > $T/fs/sleep; chmod +x $T/fs/sleep
wl() { printf 'interval_min=%s\n' "$1" > .super-agents/watchdog.conf; LAST=$(PATH="$T/fs:$PATH" $X/watchdog-loop.sh 2>&1); }
wl 5;      has watchdog-interval "SLEEP 300"
wl 0;      has watchdog-zero "SLEEP 600"
wl five;   has watchdog-word "SLEEP 600"
wl 0.5;    has watchdog-fraction "SLEEP 600"; has watchdog-fraction-warns "bad interval_min"
rm -rf .job .super-agents

# ---- init-project.sh
mkdir -p $T/p1 $T/np; git -C $T/p1 init -q -b main
printf '# P\nmine\n\n<!-- SUPER_AGENTS_START -->\nold\n<!-- SUPER_AGENTS_END -->\n\nafter\n' > $T/p1/CLAUDE.md
t init 0 $X/init-project.sh $T/p1 $T/np;                           has init-refresh "updated super-agents block"; has init-skip-nongit "not a git repo"
grep -q "write-tickets" $T/p1/CLAUDE.md && grep -q "^after" $T/p1/CLAUDE.md && grep -q "^mine" $T/p1/CLAUDE.md && [ "$(grep -c SUPER_AGENTS_START $T/p1/CLAUDE.md)" = 1 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL init block content"; }
t init-idempotent 0 $X/init-project.sh $T/p1;                      hasnt init-idempotent "updated"; hasnt init-idempotent "wrote"; hasnt init-idempotent "added"
# a START marker without END must be left alone: refreshing it would delete everything after START
mkdir -p $T/p4; git -C $T/p4 init -q -b main; printf '# P\n<!-- SUPER_AGENTS_START -->\nold\nrules the user wrote\n' > $T/p4/CLAUDE.md; cp $T/p4/CLAUDE.md $T/p4.bak
t init-no-end 0 $X/init-project.sh $T/p4;                          has init-no-end "no SUPER_AGENTS_END"
cmp -s $T/p4/CLAUDE.md $T/p4.bak && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL init rewrote a CLAUDE.md that has no END marker"; }
# #7: an END marker that comes before START is no END for this block; refreshing would delete everything after START
mkdir -p $T/p7; git -C $T/p7 init -q -b main; printf 'keep1\n<!-- SUPER_AGENTS_END -->\nkeep2\n<!-- SUPER_AGENTS_START -->\nold\nkeep3\n' > $T/p7/CLAUDE.md; cp $T/p7/CLAUDE.md $T/p7.bak
t init-end-before-start 0 $X/init-project.sh $T/p7;                has init-end-before-start "no SUPER_AGENTS_END"
cmp -s $T/p7/CLAUDE.md $T/p7.bak && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL init rewrote a CLAUDE.md whose END marker comes before START: $(tr '\n' '|' < $T/p7/CLAUDE.md)"; }
# M6: only marker LINES count; prose that names the markers is the user's text and must survive
mkdir -p $T/p5; git -C $T/p5 init -q -b main
printf '# Project\nWe use the SUPER_AGENTS_START marker from the plugin.\nrule A: never touch billing/\nrule B: run make lint\nIt ends at SUPER_AGENTS_END.\nrule C\n' > $T/p5/CLAUDE.md
t init-prose-markers 0 $X/init-project.sh $T/p5;                   has init-prose-markers "added  super-agents block"
grep -q '^rule A' $T/p5/CLAUDE.md && grep -q '^rule B' $T/p5/CLAUDE.md && grep -q '^rule C' $T/p5/CLAUDE.md && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL init deleted user lines that only mention the markers"; }
t init-prose-idempotent 0 $X/init-project.sh $T/p5;                hasnt init-prose-idempotent "updated"; hasnt init-prose-idempotent "added  super-agents"

# ---- superagent.sh with a fake claude
mkdir -p $T/bin; printf '#!/bin/sh\necho "ARGS: $*"; echo "TEAMS=$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"\n' > $T/bin/claude; chmod +x $T/bin/claude
cd $T/repo || exit; git switch -q main; git add specs && git commit -qm "tickets"
t launch-yes 0 bash -c "echo y | PATH=$T/bin:\$PATH $X/superagent.sh --foo"; has launch-args "--agent super-agents:router --name router --permission-mode auto --foo"; has launch-teams "TEAMS=1"
[ "$(git branch --show-current)" != main ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL launch did not branch"; }
[[ $(git branch --show-current) =~ ^integration/[0-9]{8}-[0-9]{6}$ ]] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL integration branch name has no seconds: $(git branch --show-current)"; }
git switch -q main; t launch-no 1 bash -c "echo n | PATH=$T/bin:\$PATH $X/superagent.sh"; has launch-no "refusing"
t launch-nongit 1 bash -c "cd $T && PATH=$T/bin:\$PATH $X/superagent.sh"
git switch -q -c feat/x; t launch-mode-override 0 env PATH="$T/bin:$PATH" $X/superagent.sh --permission-mode default
has launch-mode-override "--permission-mode default"; hasnt launch-mode-override "--permission-mode auto"; git switch -q main
# M3: workers get worktrees of committed files, so approved-but-uncommitted tickets are committed first (or the launch stops)
git switch -q -c feat/y; echo more > specs/tickets/003-profile/extra.md
t launch-uncommitted-no 1 bash -c "echo n | PATH=$T/bin:\$PATH $X/superagent.sh"; has launch-uncommitted-no "uncommitted"
t launch-uncommitted-yes 0 bash -c "echo y | PATH=$T/bin:\$PATH $X/superagent.sh"; has launch-uncommitted-yes "ARGS:"
[ -z "$(git status --porcelain -- specs/tickets)" ] && git cat-file -e HEAD:specs/tickets/003-profile/extra.md && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL launch did not commit the tickets"; }
# PR review: work the user staged for something else is not swept into the tickets commit
echo mine > mine.txt; git add mine.txt; echo again >> specs/tickets/003-profile/extra.md
t launch-staged 0 bash -c "echo y | PATH=$T/bin:\$PATH $X/superagent.sh"
! git show --name-only --format= HEAD | grep -q mine.txt && git diff --cached --name-only | grep -q mine.txt && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL launch committed (or unstaged) the user's own staged file"; }
git rm -q --cached mine.txt; rm mine.txt
# #7: tickets approved after launch are committed by commit-tickets (the router has no Bash); it lists what it commits
echo late > specs/tickets/003-profile/late.md; echo mine > CLAUDE.md
t commit-tickets-no 1 bash -c "echo n | $X/commit-tickets.sh"; has commit-tickets-lists-ticket "late.md"; has commit-tickets-lists-claude "CLAUDE.md"; has commit-tickets-no "refusing"
t commit-tickets-yes 0 bash -c "echo y | $X/commit-tickets.sh"
[ -z "$(git status --porcelain -- specs/tickets CLAUDE.md)" ] && git cat-file -e HEAD:specs/tickets/003-profile/late.md && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL commit-tickets did not commit the new ticket file"; }
t commit-tickets-clean 0 $X/commit-tickets.sh; has commit-tickets-clean "nothing to commit"
echo again >> specs/tickets/003-profile/late.md; t commit-tickets-yes-flag 0 $X/commit-tickets.sh -y; [ -z "$(git status --porcelain -- specs/tickets)" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL commit-tickets -y left changes"; }
git switch -q main; echo more >> specs/tickets/003-profile/late.md; t commit-tickets-on-main 1 $X/commit-tickets.sh -y; has commit-tickets-on-main "integration branch"; git checkout -q -- specs/tickets; git switch -q feat/y
git switch -q main; git branch -q -D feat/y

# ---- hooks
ftu() { LAST=$(python3 -c 'import json,sys;print(json.dumps({"cwd":sys.argv[3],"agent_type":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$1" "$2" "$T" | $X/block-code-reads.sh); }
ftu "" "cat src/app.py"; silent hook-main-agent-free
ftu super-agents:builder "grep -r x ."; silent hook-other-agent-free
ftu super-agents:first-time-user "cat src/app.py"; has hook-ftu-cat-denied '"permissionDecision": "deny"'
ftu super-agents:first-time-user "curl -s http://localhost:3000/"; silent hook-ftu-curl-allowed
# a verb only counts where a command starts: words inside arguments are the user's own data, not a peek at the code
for c in 'curl -s -d "q=find a flight" http://localhost:3000/search' 'curl -s http://localhost:3000/ls' './launcher.sh add "cat food"' 'bash ./launcher.sh list'; do
  ftu super-agents:first-time-user "$c"; silent "hook-ftu-allowed: $c"
done
for c in 'echo hi | cat f' 'cd /tmp && cat f' 'FOO=1 cat f' '/usr/bin/cat f' 'xargs cat < list' 'env cat f' 'time cat f' 'echo $(cat f)' 'if true; then cat f; fi' 'bash -c "cat f"' 'curl file:///etc/passwd'; do
  ftu super-agents:first-time-user "$c"; has "hook-ftu-denied: $c" '"permissionDecision": "deny"'
done
# L7: reading verbs that were missing from the denylist
for c in 'sort */*' 'wc -c */*.py' 'jq . package.json' 'sqlite3 data.db .dump' 'base64 config/settings.py' 'paste -s main.py'; do
  ftu super-agents:first-time-user "$c"; has "hook-ftu-denied: $c" '"permissionDecision": "deny"'
done
# L8: filtering the app's own output after a pipe is ordinary use; the deny reason names what matched
for c in 'curl -s localhost:3000/health | grep ok' 'curl -s localhost:3000/ | head -5' './launcher.sh list | sort | wc -l'; do
  ftu super-agents:first-time-user "$c"; silent "hook-ftu-allowed: $c"
done
ftu super-agents:first-time-user "echo hi | cat f"; has hook-ftu-reason-names-match "'cat'"
# L7: browser tools are checked too: the app's URLs are fine, file: URLs are not
ftb() { LAST=$(python3 -c 'import json,sys;print(json.dumps({"cwd":sys.argv[2],"agent_type":"super-agents:first-time-user","tool_name":"mcp__claude-in-chrome__navigate","tool_input":json.loads(sys.argv[1])}))' "$1" "$T" | $X/block-code-reads.sh); }
ftb '{"url":"http://localhost:3000/"}'; silent hook-ftu-browser-allowed
ftb '{"url":"file:///home/me/project/src/app.py"}'; has hook-ftu-browser-file-denied '"permissionDecision": "deny"'
ftb '{"url":"FILE:///home/me/project/src/app.py"}'; has hook-ftu-browser-FILE-denied '"permissionDecision": "deny"'
# PR review: a filter after a pipe that reads files, and a read hidden in shell expansion, are still denied; plain filters are fine
for c in 'curl -s x | grep -f .secret' 'curl -s x | grep -rn foo .' 'curl -s x | sed -f edit.sed' 'echo "$(<src/app.py)"' 'curl FILE:///etc/passwd'; do
  ftu super-agents:first-time-user "$c"; has "hook-ftu-denied: $c" '"permissionDecision": "deny"'
done
for c in 'curl -s x | grep -n ok' "curl -s x | sed 's/a/b/'" 'curl -s x | jq .items | head -3'; do
  ftu super-agents:first-time-user "$c"; silent "hook-ftu-allowed: $c"
done
# #6: a filter after a pipe that is given a file reads that file and ignores its stdin; only a slash used to give that away
for c in 'curl -s localhost:3000/ | head main.py' 'curl -s localhost:3000/ | grep def app.py' 'curl -s localhost:3000/ | sed -n 1,40p app.py' 'curl -s localhost:3000/ | tail -n +1 server.js' './run.sh | head app.py' \
         'curl -s x | wc -l main.py' 'curl -s x | sort main.py' 'curl -s x | cut -d, -f1 data.csv' 'curl -s x | jq .a data.json' 'curl -s x | uniq main.py' 'curl -s x | head -n 5 main.py' \
         'curl -s x | grep ok < main.py' 'curl -s x | head < main.py' "curl -s x | sed 'r main.py'" "curl -s x | sed -n '1R main.py'" 'curl -s x | grep -e ok main.py' 'curl -s x | grep ok main.py app.py'; do
  ftu super-agents:first-time-user "$c"; has "hook-ftu-denied: $c" '"permissionDecision": "deny"'
done
for c in 'curl -s localhost:3000/ | head -n 5' 'curl -s x | tail -n +2' "curl -s x | sed -n '1,40p'" 'curl -s x | cut -d, -f1' 'curl -s x | cut -d , -f 1' 'curl -s x | sort | uniq -c' 'curl -s x | sort -k 2 -n | head -3' 'curl -s x | wc -l' \
         'curl -s x | grep -A 2 error' 'curl -s x | grep -nA 2 error' 'curl -s x | grep "two words"' "curl -s x | grep -o 'href=\"/a/b\"'" 'curl -s x | grep -e ok -e done' 'curl -s x | jq -r .items[0].name' 'curl -s x | tr a-z A-Z' './run.sh | head -20 | tail -n 5'; do
  ftu super-agents:first-time-user "$c"; silent "hook-ftu-allowed: $c"
done
# #6: a | or ; inside quotes does not end the stage, so the file after it is still an operand
for c in 'curl -s x | grep "a|b" main.py' "curl -s x | grep 'a|b' main.py" 'curl -s x | grep "a\" | b" main.py' 'curl -s x | sed "s/a;b/c/" main.py'; do
  ftu super-agents:first-time-user "$c"; has "hook-ftu-denied: $c" '"permissionDecision": "deny"'
done
for c in 'curl -s x | grep "a|b"' 'curl -s x | grep -E "error|warn" | head -5' "curl -s x | sed 's/a;b/c/'"; do
  ftu super-agents:first-time-user "$c"; silent "hook-ftu-allowed: $c"
done
# #6: sed can run or write through its s flags too; writing the filtered output to a file is not a read
for c in "curl -s x | sed 's/.*/cat main.py/e'" "curl -s x | sed 's|.*|cat main.py|e'" "curl -s x | sed -n 's/a/b/w out.txt'" 'curl -s x | grep ">" main.py' 'curl -s x | head >(cat main.py)'; do
  ftu super-agents:first-time-user "$c"; has "hook-ftu-denied: $c" '"permissionDecision": "deny"'
done
for c in 'curl -s x | head -5 > out.txt' 'curl -s x | head -5 >> out.txt' 'curl -s x | grep ok 2>/dev/null' 'curl -s x | grep ok >out.txt' 'curl -s x | grep ">"' "curl -s x | sed 's/a/b/g'" "curl -s x | sed 's/error/ok/i'"; do
  ftu super-agents:first-time-user "$c"; silent "hook-ftu-allowed: $c"
done
# #6 follow-up: reading a file through $(<f), `<f` or the `.` builtin (source) is a read like cat is
for c in 'echo $(<main.py)' 'echo "$(<main.py)"' 'x=$( < main.py)' 'echo `<main.py`' '. ./main.sh' 'cd /tmp && . ./run.sh' 'if true; then . f; fi'; do
  ftu super-agents:first-time-user "$c"; has "hook-ftu-denied: $c" '"permissionDecision": "deny"'
done
for c in 'echo done.' './launcher.sh add "a . b"' 'curl -d "x=$(date)" http://localhost:3000/' 'curl -s x > out.txt' './launcher.sh list | sort | wc -l' 'curl -s http://localhost:3000/ -d "<a>1</a>"'; do
  ftu super-agents:first-time-user "$c"; silent "hook-ftu-allowed: $c"
done
python3 -c 'import json,sys;sys.exit("mcp__claude-in-chrome__" not in json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["matcher"])' "$R/hooks/hooks.json" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL hooks.json matcher does not cover the browser tools"; }
LAST=$(echo "{\"cwd\":\"$T/np\"}" | $X/session-start.sh); has session-agreement "super-agents plugin is active"
# L4: the active-loop note lists dir and round
mkdir -p $T/p6/.super-agents; git -C $T/p6 init -q -b main; touch $T/p6/review.md; printf -- '---\ndir: specs/x\nactive: true\nround: 2\n---\n' > $T/p6/.super-agents/state.md
LAST=$(echo "{\"cwd\":\"$T/p6\"}" | $X/session-start.sh); has session-active-loop "dir specs/x round 2"
LAST=$(echo "{\"cwd\":\"$T/repo\"}" | $X/session-start.sh); has session-nudge "/super-agents:setup-project"
# #5: the session id goes into the context, so the review-loop can record who started the loop
LAST=$(echo "{\"cwd\":\"$T/repo\",\"session_id\":\"sessZ\"}" | $X/session-start.sh); has session-start-id "This session's id is sessZ"
LAST=$(echo "{\"cwd\":\"$T/repo\"}" | $X/session-start.sh); hasnt session-start-no-id "session's id"
t session-no-python 0 env PATH="$T/nopath" "$BASH" $X/session-start.sh;  has session-no-python "python3 is not installed"   # hooks need python3; say so instead of silently doing nothing


# ---- AGENTS.md is refreshed when present, never created
mkdir -p $T/p2 $T/p3; git -C $T/p2 init -q -b main; git -C $T/p3 init -q -b main; echo "# agents" > $T/p3/AGENTS.md
t setup-agents-md 0 $X/init-project.sh $T/p2 $T/p3;                  [ ! -f $T/p2/AGENTS.md ] && grep -q SUPER_AGENTS_START $T/p3/AGENTS.md && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL AGENTS.md handling"; }

# ---- bin/super-agents dispatcher (the harness-neutral entry point), also through a symlink
B="$R/bin/super-agents"; ln -s "$B" $T/bin/super-agents; SA=$T/bin/super-agents
t sa-usage 2 $SA;                                                   has sa-usage "usage: super-agents"
t sa-template 0 $SA template RD.md;                                 has sa-template "**Status:** draft"
t sa-template-traversal 2 $SA template ../README.md
cd $T/repo || exit; $X/board.py set 001 ready >/dev/null; $X/board.py set 002 ready >/dev/null; $X/board.py set 003 ready >/dev/null
t sa-board 0 $SA board check;                                       has sa-board "OK: board"
t sa-check-evals 0 $SA check-evals specs/tickets/003-profile --ready
t sa-link-skills 0 $SA link-skills $T/skills-out;                   [ "$(ls $T/skills-out | wc -l)" = "$(ls $R/skills | wc -l)" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL link-skills count"; }
# L10: a skill folder or link of the same name that is not ours is skipped with a warning, never replaced or nested into
mkdir -p $T/skills2/fix-bug $T/skills2/elsewhere; ln -s $T/skills2/elsewhere $T/skills2/write-eval
t sa-link-skills-collision 0 $SA link-skills $T/skills2;            has sa-link-skills-collision "skip"
[ -d $T/skills2/fix-bug ] && [ ! -L $T/skills2/fix-bug ] && [ ! -e $T/skills2/fix-bug/fix-bug ] && [ "$(readlink $T/skills2/write-eval)" = "$T/skills2/elsewhere" ] && [ -L $T/skills2/classify-risk ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL link-skills clobbered or nested into an existing skill"; }
t sa-link-skills-again 0 $SA link-skills $T/skills-out;             hasnt sa-link-skills-again "skip"

# L12: inside a submodule the main checkout is the submodule itself, not <superproject>/.git/modules
git init -q -b main $T/sub && git -C $T/sub -c user.email=t@t -c user.name=t commit -q --allow-empty -m s
git init -q -b main $T/sup && (cd $T/sup && git -c protocol.file.allow=always submodule add -q ../sub sub)
mkdir -p $T/sup/sub/specs/tickets; printf '# Board\n| # | Title | Status | Mode | Runs |\n|---|---|---|---|---|\n' > $T/sup/sub/specs/tickets/BOARD.md
t board-in-submodule 0 bash -c "cd $T/sup/sub && $X/board.py check";  has board-in-submodule "OK: board"
mkfix $T/sup/sub/f; fp $T/sup/sub/f
(cd $T/sup/sub && git add -A f >/dev/null && git -c user.email=t@t -c user.name=t commit -qm f && git worktree add -q $T/subwt -b w)
rm -f $T/subwt/f/.evals.sha256; sedi 's/- fail when: f/- fail when: loosened/' $T/subwt/f/evals.md
t eval-in-submodule-tampered 1 $X/check-evals.sh $T/subwt/f --passed;  has eval-in-submodule-tampered "changed after the user approved"

# H1: the merger's sequence leaves nothing to revert, so merging the fixed branch again keeps the ticket's work
# (the old 'merge, then git revert -m 1 HEAD' sequence lost it: the re-merge saw the ticket's commits as already merged)
h=$T/h1; git init -q -b main $h; (cd $h && git config user.email t@t && git config user.name t && echo a > f && git add . && git commit -qm base \
  && git switch -q -c integration && git switch -q -c ticket main && echo work > work.txt && git add . && git commit -qm work \
  && git switch -q integration && git merge -q --no-ff --no-commit ticket >/dev/null 2>&1 && git merge --abort \
  && git switch -q ticket && echo fix > fix.txt && git add . && git commit -qm fix \
  && git switch -q integration && git merge -q --no-ff ticket -m remerge)
[ -f $h/work.txt ] && [ -f $h/fix.txt ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL re-merge after an aborted merge lost the ticket's work"; }

# ---- portable skill lint (Agent Skills format): name == folder, sane name/description, no Claude-only variable in skills
for d in "$R"/skills/*/; do n=$(basename "$d"); f="$d/SKILL.md"
  nm=$(sed -n 's/^name: *//p' "$f" | head -1); desc=$(sed -n 's/^description: *//p' "$f" | head -1)
  [ "$nm" = "$n" ] && [[ $n =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#n} -le 64 ]] && [ -n "$desc" ] && [ ${#desc} -le 1024 ] && ! grep -q 'CLAUDE_PLUGIN_ROOT' "$f" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL skill lint: $n"; }
done

# ---- repo consistency (static): things that break the plugin silently if they drift
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
# M1: the plugin's bin/ is on the agents' PATH, scripts/ is not: prompts must say 'super-agents job-status' / 'super-agents board', never the bare script
for f in "$R"/agents/*.md "$R"/skills/*/SKILL.md; do
  grep -qE 'job-status\.sh|board\.py' "$f" && bad "$f names job-status.sh or board.py directly; use 'super-agents job-status' / 'super-agents board'" || ok
done
for py in "$X"/*.py; do python3 -B -c 'import ast,sys;ast.parse(open(sys.argv[1]).read())' "$py" && ok || bad "scripts/$(basename "$py") does not parse"; done
# #7: only the job that publishes may write to the repository; the job that runs the tests gets a read-only token
[ "$(grep -c 'contents: write' "$R/.github/workflows/release.yml")" = 1 ] && awk '/^  [a-z]+:$/{job=$1} /contents: write/{print job}' "$R/.github/workflows/release.yml" | grep -qx 'publish:' && ok || bad "release.yml: contents: write must appear once, in the publish job only"
# #7: prompt changes with no behaviour to run: guard them against being undone (the router cannot commit tickets; the merger blocks only on a running team; the reviewer is given its base)
grep -q 'super-agents commit-tickets' "$R/agents/router.md" && ok || bad "router.md no longer asks the user to run 'super-agents commit-tickets' for tickets approved late"
grep -q "building.*team" "$R/agents/merger.md" && grep -q 'stray files' "$R/agents/merger.md" && ok || bad "merger.md no longer tells a running team's files from stray files"
grep -q '^base: ' "$R/skills/review-loop/SKILL.md" && grep -q '`base` and `checkpoint`' "$R/skills/review-loop/SKILL.md" && grep -q '`base` in round 1' "$R/agents/reviewer.md" && ok || bad "the review-loop no longer records base or passes base and checkpoint to the reviewer"
t sa-commit-tickets-route 1 bash -c "cd $T && $SA commit-tickets"; has sa-commit-tickets-route "not inside a git repo"
v1=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$R/.claude-plugin/plugin.json"); v2=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["plugins"][0]["version"])' "$R/.claude-plugin/marketplace.json")
[ -n "$v1" ] && [ "$v1" = "$v2" ] && ok || bad "manifest versions differ: plugin.json '$v1', marketplace.json '$v2'"
for s in $(python3 -c 'import json,re,sys;print(*re.findall(r"/scripts/([A-Za-z0-9._-]+)", open(sys.argv[1]).read()))' "$R/hooks/hooks.json"); do
  [ -x "$X/$s" ] && ok || bad "hooks.json runs scripts/$s, which is missing or not executable"
done
for f in "$R"/scripts/* "$R"/bin/*; do [ -x "$f" ] && ok || bad "$f is not executable"; done
for f in "$R"/agents/*.md; do n=$(basename "$f" .md)
  [ "$(sed -n 's/^name: *//p' "$f" | head -1)" = "$n" ] && [ -n "$(sed -n 's/^description: *//p' "$f" | head -1)" ] && ok || bad "agent $n: frontmatter name must equal the filename and description must be set"
done
for ref in $(grep -ohE 'super-agents:[a-z][a-z-]*' "$R"/agents/*.md "$R"/skills/*/SKILL.md | sort -u); do r=${ref#super-agents:}
  [ -f "$R/agents/$r.md" ] || [ -d "$R/skills/$r" ] && ok || bad "'$ref' names no agent or skill (typo in an Agent(...) allowlist silently stops dispatch)"
done

for c in "$R"/evals/*/; do n=$(basename "$c"); [ "$n" = results ] && continue   # a case without a grader fails to load in 'claude plugin eval'
  [ -f "$c/prompt.md" ] && [ -n "$(ls "$c"/graders/*.md 2>/dev/null)" ] && ok || bad "eval case $n needs prompt.md and at least one graders/*.md"
done

echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
