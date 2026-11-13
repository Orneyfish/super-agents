# Evals: Greet command

Approved by the user before building. Nobody edits this file while building; outcomes go in results.md.

## Setup
1. Python 3 only (standard library). No install step.
2. Run every check from the repository root, the directory that contains `greeter.py`. Each check is a shell command; `cat -A` makes trailing newlines and stray characters visible.
3. This feature has no port, no data directory and no test account: it is a command-line app with no server and no stored state. Nothing is written to disk except what the checks themselves redirect into `out.txt` and `err.txt` in the current directory; run them in a scratch copy of the repository, not in a checkout you care about.

## E1: greet prints the greeting
- covers: FR-1
- check: `python3 greeter.py greet Ada | cat -A; echo "exit=${PIPESTATUS[0]}"`, then `python3 greeter.py greet "  Grace Hopper  " | cat -A`, then `python3 greeter.py greet Ada 2>err.txt >/dev/null; wc -c < err.txt`
- pass when: the first output is exactly `Hello, Ada!$` and then `exit=0`; the second output is exactly `Hello, Grace Hopper!$` (surrounding spaces removed, inner space kept); the stderr byte count is `0`.
- fail when: the name is hard-coded (a stub that always prints `Hello, Ada!` fails the second check); the `!`, the comma or the newline is missing or doubled; `greet` prints the `hello` text; the exit code is not 0; anything lands on stderr.

## E2: greet --shout prints the line in upper case
- covers: FR-2
- check: `python3 greeter.py greet Ada --shout | cat -A; echo "exit=${PIPESTATUS[0]}"`, then `python3 greeter.py greet "grace hopper" --shout | cat -A`, then `python3 greeter.py greet Ada --shout 2>err.txt >/dev/null; wc -c < err.txt`
- pass when: the first output is exactly `HELLO, ADA!$` then `exit=0`; the second is exactly `HELLO, GRACE HOPPER!$`; the stderr byte count is `0`.
- fail when: the flag is ignored (prints `Hello, Ada!`); only the name is upper-cased (`Hello, ADA!`); the literal text `--shout` appears in the output; the flag is printed as part of the name (`HELLO, ADA --SHOUT!`); exit code is not 0.

## E3: a missing name is a usage error
- covers: FR-3
- check: `python3 greeter.py greet >out.txt 2>err.txt; echo "exit=$?"; wc -c < out.txt; wc -c < err.txt; grep -c Traceback err.txt; grep -c 'usage: greeter.py hello' err.txt`
- pass when: `exit=2`; the stdout byte count is `0`; the stderr byte count is greater than `0`; the traceback count is `0`; the last count (`usage: greeter.py hello`) is `0`. That line is what the unknown-command path prints, so seeing it means `greet` was never implemented.
- fail when: exit 0 (a stub that prints nothing and exits 0 fails); exit 1 from an unhandled exception (a traceback appears on stderr); the message goes to stdout instead of stderr; `Hello, !` or any greeting is printed.

## E4: empty, whitespace-only and shout-only names are usage errors (failure mode, riskiest requirement)
- covers: FR-3
- check: run each of these five argument lists and record the result for each one. Run the loop from the repository root:
  ```
  for a in 'greet ""' 'greet "   "' 'greet --shout' 'greet "" --shout' 'greet "	"'; do
    eval "python3 greeter.py $a" >out.txt 2>err.txt; code=$?
    echo "[$a] exit=$code stdout_bytes=$(wc -c < out.txt) stderr_bytes=$(wc -c < err.txt) traceback=$(grep -c Traceback err.txt) unknown_cmd_usage=$(grep -c 'usage: greeter.py hello' err.txt)"
  done
  ```
- pass when: all five lines show `exit=2 stdout_bytes=0`, a stderr count greater than `0`, `traceback=0` and `unknown_cmd_usage=0`. The last field is the unknown-command usage line; seeing it means `greet` was never implemented.
- fail when: `greet ""` prints `Hello, !` (exit 0); whitespace-only prints `Hello,    !` or similar; `greet --shout` prints `HELLO, --SHOUT!` (the flag taken as the name); `greet "" --shout` prints `HELLO, !`; any case exits 1 with a traceback; an error is printed on stdout.

## E5: extra or misplaced arguments are usage errors
- covers: FR-5
- check: run each of these five argument lists with the same loop as E4:
  ```
  for a in 'greet Ada Bob' 'greet Ada --shout --shout' 'greet --loud Ada' 'greet --foo' 'greet --shout Ada'; do
    eval "python3 greeter.py $a" >out.txt 2>err.txt; code=$?
    echo "[$a] exit=$code stdout_bytes=$(wc -c < out.txt) stderr_bytes=$(wc -c < err.txt) traceback=$(grep -c Traceback err.txt) unknown_cmd_usage=$(grep -c 'usage: greeter.py hello' err.txt)"
  done
  ```
- pass when: all five lines show `exit=2 stdout_bytes=0`, a stderr count greater than `0`, `traceback=0` and `unknown_cmd_usage=0` (the unknown-command usage line means `greet` was never implemented).
- fail when: `greet Ada Bob` prints only `Hello, Ada!` (the second name silently ignored); `greet --loud Ada` or `greet --foo` prints a greeting (the flag taken as text or name); `greet --shout Ada` prints `HELLO, ADA!` (order not enforced); any case exits 0.

## E6: hello and the unknown-command path still work
- covers: FR-4
- check: `python3 greeter.py hello | cat -A; echo "exit=${PIPESTATUS[0]}"`, then `python3 greeter.py nope 2>/dev/null; echo "exit=$?"`, then `git diff HEAD -- test_greeter.py | grep -c '^-[^-]'`, then `python3 -m unittest -v 2>&1 | grep -E 'test_hello|test_unknown_command|^OK'`
- pass when: the first output is exactly `hello, world$` then `exit=0`; the second prints `exit=2`; the removed-line count is `0` (no existing test line was deleted or edited); the unittest output shows `test_hello ... ok`, `test_unknown_command_is_usage_error ... ok` and a final `OK`.
- fail when: `hello` prints anything else (for example the usage line, or `Hello, ...`); `hello` exits non-zero; `nope` exits 0; the existing tests were rewritten or removed to make the suite pass; the suite fails.

## E7: standard library only, and the project's build and lint still pass
- covers: NFR-1, NFR-2
- check: `python3 -m py_compile greeter.py; echo "compile=$?"`, then `grep -E '^\s*(import|from) ' greeter.py`, then `python3 -m unittest -v 2>&1 | tail -1`
- pass when: `compile=0`; every import line names a standard-library module (for example `sys`, `argparse`), with nothing from pip and no network, socket, or file-writing module; the last unittest line is `OK`.
- fail when: a third-party import is added (`requests`, `click`, ...) or a network/file-writing module is imported; the file does not compile; the unittest run ends in `FAILED`.

## Definition of done
- [ ] Every eval above has a pass row in results.md, with evidence
- [ ] Nothing under "Out of scope" was built and nothing under "Must not touch" changed
- [ ] The project's lint and build pass
