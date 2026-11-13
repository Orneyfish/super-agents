#!/usr/bin/env python3
"""Summarise a hook log directory written by hooks/probe-log.sh: one line per event, in order.
Usage: summarize-hooklog.py <hooklog-dir> [--keys]   (--keys also prints every top-level key seen per event name)"""
import json, os, sys

d = sys.argv[1]
short = lambda s, n=70: (s if len(s) <= n else "..." + s[-(n - 3):])
keys = {}
for name in sorted(f for f in os.listdir(d) if f.endswith(".json")):
    try:
        m = json.load(open(os.path.join(d, name), errors="replace"))
    except Exception as e:
        print(f"{name}: unparseable ({e})"); continue
    env = dict(l.rstrip("\n").split("=", 1) for l in open(os.path.join(d, name[:-5] + ".env"), errors="replace") if "=" in l)
    ev = m.get("hook_event_name", "?")
    keys.setdefault(ev, set()).update(m.keys())
    ti = m.get("tool_input") or {}
    detail = ""
    if "tool_name" in m:
        tin = {k: (short(str(v), 60)) for k, v in ti.items() if k in ("file_path", "notebook_path", "command", "subagent_type", "skill", "query", "run_in_background")}
        detail = f" tool={m['tool_name']} input_keys={sorted(ti.keys())} {tin}"
    extra = {k: m[k] for k in ("source", "stop_hook_active", "agent_id", "permission_mode", "reason") if k in m}
    print(f"{ev:16} session={str(m.get('session_id'))[:8]} agent_type={m.get('agent_type')!r:32} cwd={short(str(m.get('cwd')), 60)} hook_pwd={short(env.get('HOOK_PWD', ''), 40)}{detail} {extra if extra else ''}")
if "--keys" in sys.argv:
    print()
    for ev, ks in keys.items():
        print(f"keys[{ev}]: {sorted(ks)}")
