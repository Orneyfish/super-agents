#!/usr/bin/env bash
# Run by the watchdog's Monitor: every round print the board's problems, but only when the set of problems changed (not their minute counts).
# Interval comes from .super-agents/watchdog.conf (interval_min, default 10); re-read each round.
here="$(cd "$(dirname "$0")" && pwd)"; last=""; warned=""
root=$("$here/sa-native.sh" board root)
while true; do
  out=$("$here/sa-native.sh" board scan 2>&1)
  key=$(sed -E 's/[0-9]+ min/N min/g' <<<"$out")   # the minute counts grow every round; without this a problem that persists would be news each time
  [ -n "$out" ] && [ "$key" != "$last" ] && echo "$out"
  last="$key"
  mins=$(sed -n 's/^interval_min *= *//p' "$root/.super-agents/watchdog.conf" 2>/dev/null | head -1 | tr -d '[:space:]')
  if [ -z "$mins" ]; then mins=10
  elif ! { [[ $mins =~ ^[0-9]+$ ]] && [ $((10#$mins)) -ge 1 ]; }; then   # 0 or a word would busy-loop, 0.5 would kill this script
    [ "$mins" != "$warned" ] && echo "watchdog: bad interval_min '$mins' in watchdog.conf (needs a whole number of minutes, 1 or more); using 10"
    warned=$mins; mins=10
  fi
  sleep $((10#$mins * 60))
done
