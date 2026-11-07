#!/usr/bin/env bash
# Heartbeat the watchdog reads. Workers (own worktree) write ./.job/status.json; team members (main checkout) write ./.job/status-<name>.json.
#   job-status.sh [--name N] init <NNN> <ticket-dir> <phase>
#   job-status.sh [--name N] <phase> [note]          phase: building | testing | reviewing | done | blocked
# Call it at every phase change and at least every few minutes while working.
name=""; [ "${1:-}" = --name ] && { name=$2; shift 2; }
f=".job/status${name:+-$name}.json"; now=$(date -u +%FT%TZ); mkdir -p .job
if [ "${1:-}" = init ]; then
  dir=$(cd "${3:?ticket dir}" 2>/dev/null && pwd || echo "$3")   # absolute, so the gate does not depend on whose cwd it runs in
  jq -n --arg t "${2:?ticket}" --arg d "$dir" --arg p "${4:?phase}" --arg n "$now" --arg who "$name" \
    '{ticket:$t,dir:$d,phase:$p,started:$n,updated:$n,note:"",agent:$who}' > "$f"
else
  [ -f "$f" ] || { echo "run 'job-status.sh init <NNN> <dir> <phase>' first" >&2; exit 1; }
  jq --arg p "${1:?phase}" --arg note "${2:-}" --arg n "$now" '.phase=$p|.note=$note|.updated=$n' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
fi
if [ -z "$name" ] && [ "${1:-}" = building ]; then rm -f .job/gate_blocks; fi   # a new build round gets a fresh worker-gate block count
