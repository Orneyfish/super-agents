#!/usr/bin/env bash
# Heartbeat the watchdog reads. Workers (own worktree) write ./.job/status.json; team members (main checkout) write ./.job/status-<name>.json.
#   job-status.sh [--name N] init <NNN> <ticket-dir> <phase>
#   job-status.sh [--name N] <phase> [note]          phase: building | testing | reviewing | done | blocked | waiting
#   waiting = stopped to ask the user (the note is the question): the worker gate lets that stop through and the watchdog reports it once.
# Call it at every phase change and at least every few minutes while working.
here="$(cd "$(dirname "$0")" && pwd)"; name=""; [ "${1:-}" = --name ] && { name=$2; shift 2; }
[[ -z $name || $name =~ ^[A-Za-z0-9._-]{1,64}$ ]] || { echo "job-status: --name must be 1-64 of A-Z a-z 0-9 . _ -" >&2; exit 2; }   # it becomes part of a file name
f=".job/status${name:+-$name}.json"; now=$(date -u +%FT%TZ); mkdir -p .job
if [ "${1:-}" = init ]; then
  dir=$(cd "${3:?ticket dir}" 2>/dev/null && pwd || echo "$3")   # absolute, so the gate does not depend on whose cwd it runs in
  "$here/sa-native.sh" hookio status-init "${2:?ticket}" "$dir" "${4:?phase}" "$now" "$name" > "$f.tmp" && mv "$f.tmp" "$f"
else
  [ -f "$f" ] || { echo "run 'job-status.sh init <NNN> <dir> <phase>' first" >&2; exit 1; }
  "$here/sa-native.sh" hookio status-set "$f" "${1:?phase}" "${2:-}" "$now" > "$f.tmp" && mv "$f.tmp" "$f"
fi
if [ -z "$name" ] && { [ "${1:-}" = building ] || [ "${1:-}" = init ]; }; then rm -f .job/gate_blocks; fi   # a new build round (or a restarted worker) gets a fresh worker-gate block count
