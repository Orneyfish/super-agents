#!/usr/bin/env bash
# Part C setup: the throwaway project for the live single-feature flow. Its own git repo, no remote, a trivial Python CLI.
# The plugin under test is the unmodified copy (plugin-copy) with sa-core built from source in it.
set -eu
S=${1:?scratchpad dir}; E=$S/evidence; W=$S/work; P=$W/plugin-copy; D=$W/demo
rm -rf "$D"; mkdir -p "$D"; cd "$D"; git init -q -b main .; git config user.email t@t; git config user.name t
cat > greeter.py <<'PY'
#!/usr/bin/env python3
"""greeter: a tiny command-line app used as a throwaway test project."""
import sys


def main(argv):
    if len(argv) >= 1 and argv[0] == "hello":
        print("hello, world")
        return 0
    print("usage: greeter.py hello", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY
cat > test_greeter.py <<'PY'
import subprocess, sys, unittest


def run(*args):
    return subprocess.run([sys.executable, "greeter.py", *args], capture_output=True, text=True)


class TestGreeter(unittest.TestCase):
    def test_hello(self):
        r = run("hello")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "hello, world\n")

    def test_unknown_command_is_usage_error(self):
        self.assertEqual(run("nope").returncode, 2)


if __name__ == "__main__":
    unittest.main()
PY
printf '# greeter\n\nA tiny command-line app. Run: `python3 greeter.py hello`. Test: `python3 -m unittest -v`.\n' > README.md
printf '__pycache__/\n' > .gitignore
"$P/bin/super-agents" setup .
# what /super-agents:setup-project step 2 would have a model do: replace the TODO lines in review.md with this project's real commands
python3 - <<'PY'
import re
t = open("review.md").read()
t = t.replace("- TODO: add this project's own failures (money, PII, migrations, external APIs, ...).\n", "")
t = re.sub(r"- TODO: run command.*\n", "- Run: `python3 greeter.py <command>`. Test: `python3 -m unittest -v`. Lint and build: `python3 -m py_compile greeter.py`. This is a command-line app: there is no server, port, database or account.\n", t)
open("review.md", "w").write(t)
PY
grep -n TODO review.md || echo "review.md: no TODO left"
mkdir -p .claude; printf '.claude/\n' >> .git/info/exclude
python3 - "$E/hooks/probe-log.sh" > .claude/settings.json <<'PY'
import json, sys
log = sys.argv[1]
events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart", "SubagentStop", "Stop", "SessionEnd"]
print(json.dumps({"hooks": {e: [{"hooks": [{"type": "command", "command": f'"{log}" {e}'}]}] for e in events}}, indent=1))
PY
git add -A; git commit -qm "greeter: base project, set up for super-agents"
python3 -m unittest 2>&1 | tail -3; git log --oneline | cat; cat .gitignore; echo "remotes: $(git remote | wc -l)"
