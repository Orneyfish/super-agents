#!/usr/bin/env bash
# Regression tests for the deterministic parts: validator, board, both gates, heartbeat, watchdog scan,
# init, launcher and the tool-use / session hooks. The agents and skills are prompts: test those live (see README).
# Usage: tests/run.sh      Exit 0 = all passed.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"; X="$R/scripts"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0; LAST=""
t()   { local n=$1 want=$2; shift 2; LAST=$("$@" 2>&1); local rc=$?; [ "$rc" = "$want" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL $n: exit $rc, wanted $want"; echo "$LAST" | head -4; }; }
has() { grep -qF -- "$2" <<<"$LAST" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL $1: output lacks '$2'"; echo "$LAST" | head -4; }; }
hasnt() { grep -qF -- "$2" <<<"$LAST" && { fail=$((fail+1)); echo "FAIL $1: output has '$2'"; } || pass=$((pass+1)); }
silent() { [ -z "$LAST" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL $1: expected no output, got: $LAST" | head -3; }; }

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
sed -i 's/waits for 001/waits for 009/' specs/tickets/BOARD.md; t board-missing-dep 1 $X/board.py check; has board-missing-dep "not on the board"; sed -i 's/waits for 009/waits for 001/' specs/tickets/BOARD.md
cp specs/tickets/BOARD.md B.bak; sed -i 's/| 001 | Found | draft | team | alongside |/| 001 | Found | draft | team | waits for 002: x |/' specs/tickets/BOARD.md; t board-cycle 1 $X/board.py check; has board-cycle "dependency cycle"; cp B.bak specs/tickets/BOARD.md
t set-ticket 0 $X/board.py set 001 ready;                         grep -q '| 001 | Found | ready' specs/tickets/BOARD.md && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL set-ticket: board row"; }
t set-dir-syncs-row 0 $X/board.py set specs/tickets/002-reset ready; t board-still-ok 0 $X/board.py check
t set-bad-status 1 $X/board.py set 001 wip
mkdir -p sub/deep; t set-from-subdir 0 bash -c "cd sub/deep && $X/board.py set 001 building"; t board-ok-2 0 $X/board.py check

# ---- check-evals.sh
t eval-structure 0 $X/check-evals.sh $D
t eval-ready-while-building 1 $X/check-evals.sh $D --ready;       has eval-ready-while-building "must approve"
$X/board.py set $D ready >/dev/null; t eval-ready 0 $X/check-evals.sh $D --ready
t eval-passed-no-results 1 $X/check-evals.sh $D --passed;          has eval-passed-no-results "no row"
mkdir -p $D/evidence; touch $D/evidence/a.png
printf '| eval | result | evidence |\n|---|---|---|\n| E1 | pass | evidence/a.png: ok |\n| E2 | fail | slow |\n' > $D/results.md
t eval-passed-failing 1 $X/check-evals.sh $D --passed;             has eval-passed-failing "E2 is not passing"
sed -i 's#| E2 | fail | slow |#| E2 | pass | evidence/gone.png: ok |#' $D/results.md
t eval-passed-missing-file 1 $X/check-evals.sh $D --passed;        has eval-passed-missing-file "does not exist"
touch $D/evidence/gone.png; t eval-passed 0 $X/check-evals.sh $D --passed
sed -i 's/covers: NFR-1/covers: FR-1/' $D/evals.md; t eval-uncovered 1 $X/check-evals.sh $D; has eval-uncovered "NFR-1 has no eval"; sed -i '0,/covers: FR-1/! s/covers: FR-1/covers: NFR-1/' $D/evals.md
printf '\nTODO fill\n' >> $D/RD.md; t eval-todo 1 $X/check-evals.sh $D; sed -i '/TODO fill/d' $D/RD.md

# ---- eval-gate.sh (Stop hook of the review-loop)
mkdir -p .super-agents; st=.super-agents/state.md; in="{\"cwd\":\"$T/repo\"}"
state() { printf -- "---\ndir: %s\nactive: %s\nawaiting_user: %s\ngate_blocks: %s\n---\n" "${1:-$D}" "${2:-true}" "${3:-false}" "${4:-0}" > $st; }
gate() { LAST=$(echo "$in" | $X/eval-gate.sh); }
state; gate; silent gate-passing
sed -i 's/| E2 | pass |/| E2 | fail |/' $D/results.md
state; gate; has gate-blocks '"decision": "block"'; grep -q 'gate_blocks: 1' $st && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL gate counter"; }
state $D true true; gate; silent gate-awaiting-user
state $D false; gate; silent gate-inactive
state $D true false 3; gate; has gate-cap "released after 3 blocks"
state ../../etc; gate; silent gate-path-traversal
state; touch -d '13 hours ago' $st; gate; silent gate-stale
sed -i 's/| E2 | fail |/| E2 | pass |/' $D/results.md; rm -rf .super-agents

# ---- job-status.sh + worker-gate.sh (SubagentStop)
W=$T/wt; mkdir -p $W; cd $W
t job-init 0 $X/job-status.sh init 001 "$T/repo/$D" building; [ "$(jq -r .phase .job/status.json)" = building ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL job-init"; }
t job-update 0 $X/job-status.sh testing "note"; [ "$(jq -r '.phase+.note' .job/status.json)" = testingnote ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL job-update"; }
t job-team-file 0 $X/job-status.sh --name 001-a init 001 "$T/repo/$D" building; [ -f .job/status-001-a.json ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL job-team-file"; }
wg() { LAST=$(echo "{\"cwd\":\"$W\",\"agent_type\":\"$1\"}" | $X/worker-gate.sh); }
wg super-agents:builder; silent wgate-other-agent
sed -i 's/| E2 | pass |/| E2 | fail |/' $T/repo/$D/results.md
wg super-agents:worker; has wgate-blocks '"decision": "block"'
$X/job-status.sh blocked why; wg worker; silent wgate-blocked-phase
$X/job-status.sh building; echo 3 > .job/gate_blocks; wg worker; silent wgate-cap
sed -i 's/| E2 | fail |/| E2 | pass |/' $T/repo/$D/results.md; rm .job/gate_blocks; wg worker; silent wgate-passing
cd $T/repo

# ---- board.py scan (watchdog)
iso() { date -u -d "$1 minutes ago" +%FT%TZ; }
$X/board.py set 001 building >/dev/null
t scan-no-heartbeat 0 $X/board.py scan;                           has scan-no-heartbeat "no status file"
mkdir -p .job; jq -n --arg u "$(iso 2)" --arg s "$(iso 3)" '{ticket:"001",phase:"testing",started:$s,updated:$u,note:"",agent:"a"}' > .job/status-001-a.json
t scan-healthy 0 $X/board.py scan;                                silent scan-healthy
jq -n --arg u "$(iso 40)" --arg s "$(iso 41)" '{ticket:"001",phase:"building",started:$s,updated:$u,note:"",agent:"a"}' > .job/status-001-a.json
t scan-silent 0 $X/board.py scan;                                 has scan-silent "silent for"
mkdir -p .super-agents; printf 'ignore=001\n' > .super-agents/watchdog.conf; t scan-ignore 0 $X/board.py scan; silent scan-ignore
jq -n --arg u "$(iso 1)" --arg s "$(iso 2)" '{ticket:"001",phase:"blocked",started:$s,updated:$u,note:"db down",agent:"a"}' > .job/status-001-a.json; : > .super-agents/watchdog.conf
t scan-blocked 0 $X/board.py scan;                                has scan-blocked "blocked: db down"
rm -rf .job .super-agents

# ---- init-project.sh
mkdir -p $T/p1 $T/np; git -C $T/p1 init -q -b main
printf '# P\nmine\n\n<!-- SUPER_AGENTS_START -->\nold\n<!-- SUPER_AGENTS_END -->\n\nafter\n' > $T/p1/CLAUDE.md
t init 0 $X/init-project.sh $T/p1 $T/np;                           has init-refresh "updated super-agents block"; has init-skip-nongit "not a git repo"
grep -q "write-tickets" $T/p1/CLAUDE.md && grep -q "^after" $T/p1/CLAUDE.md && grep -q "^mine" $T/p1/CLAUDE.md && [ "$(grep -c SUPER_AGENTS_START $T/p1/CLAUDE.md)" = 1 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL init block content"; }
t init-idempotent 0 $X/init-project.sh $T/p1;                      hasnt init-idempotent "updated"; hasnt init-idempotent "wrote"; hasnt init-idempotent "added"

# ---- superagent.sh with a fake claude
mkdir -p $T/bin; printf '#!/bin/sh\necho "ARGS: $*"; echo "TEAMS=$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"\n' > $T/bin/claude; chmod +x $T/bin/claude
cd $T/repo; git switch -q main
t launch-yes 0 bash -c "echo y | PATH=$T/bin:\$PATH $X/superagent.sh --foo"; has launch-args "--agent super-agents:router --name router --permission-mode auto --foo"; has launch-teams "TEAMS=1"
[ "$(git branch --show-current)" != main ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL launch did not branch"; }
git switch -q main; t launch-no 1 bash -c "echo n | PATH=$T/bin:\$PATH $X/superagent.sh"; has launch-no "refusing"
t launch-nongit 1 bash -c "cd $T && PATH=$T/bin:\$PATH $X/superagent.sh"

# ---- hooks
ftu() { LAST=$(jq -nc --arg a "$1" --arg c "$2" --arg d "$T" '{cwd:$d,agent_type:$a,tool_name:"Bash",tool_input:{command:$c}}' | $X/block-code-reads.sh); }
ftu "" "cat src/app.py"; silent hook-main-agent-free
ftu super-agents:builder "grep -r x ."; silent hook-other-agent-free
ftu super-agents:first-time-user "cat src/app.py"; has hook-ftu-cat-denied '"permissionDecision": "deny"'
ftu super-agents:first-time-user "curl -s http://localhost:3000/"; silent hook-ftu-curl-allowed
LAST=$(echo "{\"cwd\":\"$T/np\"}" | $X/session-start.sh); has session-agreement "super-agents plugin is active"
LAST=$(echo "{\"cwd\":\"$T/repo\"}" | $X/session-start.sh); has session-nudge "/super-agents:setup-project"


# ---- AGENTS.md is refreshed when present, never created
mkdir -p $T/p2 $T/p3; git -C $T/p2 init -q -b main; git -C $T/p3 init -q -b main; echo "# agents" > $T/p3/AGENTS.md
t setup-agents-md 0 $X/init-project.sh $T/p2 $T/p3;                  [ ! -f $T/p2/AGENTS.md ] && grep -q SUPER_AGENTS_START $T/p3/AGENTS.md && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL AGENTS.md handling"; }

# ---- bin/super-agents dispatcher (the harness-neutral entry point), also through a symlink
B="$R/bin/super-agents"; ln -s "$B" $T/bin/super-agents; SA=$T/bin/super-agents
t sa-usage 2 $SA;                                                   has sa-usage "usage: super-agents"
t sa-template 0 $SA template RD.md;                                 has sa-template "**Status:** draft"
t sa-template-traversal 2 $SA template ../README.md
cd $T/repo; $X/board.py set 001 ready >/dev/null; $X/board.py set 002 ready >/dev/null; $X/board.py set 003 ready >/dev/null
t sa-board 0 $SA board check;                                       has sa-board "OK: board"
t sa-check-evals 0 $SA check-evals specs/tickets/003-profile --ready
t sa-link-skills 0 $SA link-skills $T/skills-out;                   [ "$(ls $T/skills-out | wc -l)" = "$(ls $R/skills | wc -l)" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL link-skills count"; }

# ---- portable skill lint (Agent Skills format): name == folder, sane name/description, no Claude-only variable in skills
for d in "$R"/skills/*/; do n=$(basename "$d"); f="$d/SKILL.md"
  nm=$(sed -n 's/^name: *//p' "$f" | head -1); desc=$(sed -n 's/^description: *//p' "$f" | head -1)
  [ "$nm" = "$n" ] && [[ $n =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#n} -le 64 ]] && [ -n "$desc" ] && [ ${#desc} -le 1024 ] && ! grep -q 'CLAUDE_PLUGIN_ROOT' "$f" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL skill lint: $n"; }
done

echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
