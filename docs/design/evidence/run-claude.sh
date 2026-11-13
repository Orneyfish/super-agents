#!/usr/bin/env bash
# One headless Claude Code run for the probes, isolated from the user's own setup:
#  - a clean environment (env -i), so nothing from the calling session leaks in;
#  - --setting-sources project,local, so the user's settings (their enabled plugins and hooks) are not loaded;
#  - --plugin-dir <copy>, the only plugin; its bin/ is first on PATH so `super-agents` is the copy's;
#  - no MCP servers; tools that would prompt are denied, the listed ones are allowed.
# Usage: run-claude.sh <label> <project-dir> <plugin-copy> <model> <max-turns> <max-usd> <prompt> [extra claude args ...]
set -u
label=$1; proj=$2; plugin=$3; model=$4; turns=$5; usd=$6; prompt=$7; shift 7
E=$(cd "$(dirname "$0")" && pwd); out="$E/live/$label"; mkdir -p "$out/hooklog"
claude_bin=$(command -v claude)
# NO_ALLOWLIST=1 drops the tool allowlist, so the permission mode alone decides (used for the auto-mode probe)
allow=(--allowedTools "Read,Write,Edit,NotebookEdit,Bash,Glob,Grep,Agent,Task,Skill,TodoWrite,SendMessage"); [ -n "${NO_ALLOWLIST:-}" ] && allow=()
cd "$proj" || exit 1
printf '%s\n' "$prompt" > "$out/prompt.txt"
{ echo "cwd=$proj"; echo "plugin=$plugin"; echo "model=$model max_turns=$turns max_usd=$usd"; echo "extra: $*"; echo "claude: $("$claude_bin" --version)"; date -u +%FT%TZ; } > "$out/invocation.txt"
env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${USER:-$(id -un)}" LANG="${LANG:-C.UTF-8}" TERM=dumb SHELL=/bin/bash \
  PATH="$plugin/bin:$(dirname "$claude_bin"):/usr/local/bin:/usr/bin:/bin" SA_PROBE_LOG="$out/hooklog" \
  timeout "${RUN_TIMEOUT:-540}" "$claude_bin" -p "$prompt" --model "$model" --max-turns "$turns" --max-budget-usd "$usd" \
    --setting-sources project,local --plugin-dir "$plugin" --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
    --permission-prompts none "${allow[@]}" \
    --output-format stream-json --verbose --debug-file "$out/debug.log" "$@" > "$out/stream.jsonl" 2> "$out/stderr.txt"
rc=$?; echo "exit=$rc" >> "$out/invocation.txt"
echo "exit=$rc  events=$(ls "$out/hooklog" 2>/dev/null | grep -c '\.json$')"
python3 - "$out/stream.jsonl" <<'PY'
import json, sys
init = res = None
for line in open(sys.argv[1], errors="replace"):
    try: m = json.loads(line)
    except Exception: continue
    if m.get("type") == "system" and m.get("subtype") == "init": init = m
    if m.get("type") == "result": res = m
if init:
    print("session_id:", init.get("session_id")); print("model:", init.get("model")); print("permissionMode:", init.get("permissionMode"))
    print("plugins:", json.dumps(init.get("plugins")))
    print("agents:", init.get("agents")); print("skills/commands:", [c for c in (init.get("slash_commands") or []) if "super" in c])
if res:
    print("result subtype:", res.get("subtype"), "| turns:", res.get("num_turns"), "| cost_usd:", res.get("total_cost_usd"), "| duration_ms:", res.get("duration_ms"))
    print("result text:\n" + str(res.get("result"))[:6000])
PY
