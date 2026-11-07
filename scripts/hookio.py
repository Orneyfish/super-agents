#!/usr/bin/env python3
"""JSON glue for the hook and status scripts. The plugin needs python3 anyway (board.py, the fingerprint), so it does not also need jq.

  hookio.py get <a.b.c>                      value of a path in the JSON on stdin: strings raw, objects/arrays as compact JSON,
                                             a missing path or null as an empty string
  hookio.py emit block|message|deny|context <text>   print the hook response JSON for that event
  hookio.py status-init <ticket> <dir> <phase> <now> <agent>   print a new heartbeat record
  hookio.py status-set <file> <phase> <note> <now>             print <file> with the phase, note and updated time changed"""
import json, sys

RESPONSES = {
    "block": lambda t: {"decision": "block", "reason": t},
    "message": lambda t: {"systemMessage": t},
    "deny": lambda t: {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": t}},
    "context": lambda t: {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": t}},
}


def show(o): print(json.dumps(o, indent=2))


def get(path, data):
    for k in filter(None, path.split(".")):
        if not isinstance(data, dict) or k not in data: return ""
        data = data[k]
    if data is None: return ""
    return data if isinstance(data, str) else json.dumps(data, separators=(",", ":"))


if __name__ == "__main__":
    a = sys.argv[1:]
    try:
        if len(a) == 2 and a[0] == "get": print(get(a[1], json.load(sys.stdin)))
        elif len(a) == 3 and a[0] == "emit" and a[1] in RESPONSES: show(RESPONSES[a[1]](a[2]))
        elif len(a) == 6 and a[0] == "status-init":
            show({"ticket": a[1], "dir": a[2], "phase": a[3], "started": a[4], "updated": a[4], "note": "", "agent": a[5]})
        elif len(a) == 5 and a[0] == "status-set":
            j = json.load(open(a[1])); j.update(phase=a[2], note=a[3], updated=a[4]); show(j)
        else: sys.exit(__doc__)
    except (ValueError, OSError) as e:   # unreadable JSON: print nothing so a hook script falls back to "not mine, let it through"
        sys.exit(f"hookio.py: {e}")
