#!/usr/bin/env bash
# B9 probe: deny a Write to a file named protected.txt, but only for the plugin agent probe-worker, using the payload alone.
# $1 = path to the plugin copy's sa-native.sh (its JSON helper is the thing under test).
sa=$1; in=$(cat)
[ "$("$sa" hookio get tool_name <<<"$in")" = Write ] || exit 0
[[ $("$sa" hookio get agent_type <<<"$in") =~ (^|:)probe-worker$ ]] || exit 0
[[ $("$sa" hookio get tool_input.file_path <<<"$in") == */protected.txt ]] || exit 0
"$sa" hookio emit deny "PROBE_DENY: protected.txt is off limits to probe-worker"
