#!/usr/bin/env bash
# Run by the watchdog's Monitor: every round print the board's problems, but only when they changed.
# Interval comes from .super-agents/watchdog.conf (interval_min, default 10); re-read each round.
here="$(cd "$(dirname "$0")" && pwd)"; last=""
root=$(dirname "$(realpath "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)")")
while true; do
  out=$("$here/board.py" scan 2>&1)
  [ -n "$out" ] && [ "$out" != "$last" ] && echo "$out"
  last="$out"
  mins=$(sed -n 's/^interval_min *= *//p' "$root/.super-agents/watchdog.conf" 2>/dev/null | head -1)
  sleep $(( ${mins:-10} * 60 ))
done
