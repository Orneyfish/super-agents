#!/usr/bin/env bash
# Logging hook: saves the hook's stdin JSON and a filtered environment, one pair of files per event. Never blocks, prints nothing.
d=${SA_PROBE_LOG:-}; [ -n "$d" ] || exit 0; mkdir -p "$d"
b="$d/$(date +%s%N)-$$-${1:-event}"
cat > "$b.json"
{ echo "HOOK_PWD=$PWD"; env | grep -E '^(CLAUDE_PROJECT_DIR|CLAUDE_PLUGIN_ROOT|CLAUDE_CODE_ENTRYPOINT|CLAUDE_ENV_FILE|CLAUDECODE|PATH)=' ; } > "$b.env"
exit 0
