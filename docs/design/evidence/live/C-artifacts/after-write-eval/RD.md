# Greet command

**Status:** draft
**Risk:** low

## Summary
A user can run `python3 greeter.py greet <name>` to get a greeting for that name, optionally in upper case with `--shout`. The existing `hello` command is unchanged.

## User stories
- As a user of the greeter CLI, I want to greet a person by name, so that I get a friendly line I can paste or show.
- As a user, I want to shout the greeting with `--shout`, so that it is printed in upper case.
- As a user who makes a mistake, I want a clear error and a non-zero exit code when I forget the name, so that a script does not silently print a greeting for nobody.

## Functional requirements
- FR-1: `python3 greeter.py greet <name>` prints `Hello, <name>!` followed by a newline to stdout and exits 0. Nothing is written to stderr. `<name>` is the argument with surrounding whitespace removed.
- FR-2: `python3 greeter.py greet <name> --shout` prints the same line as FR-1 with every letter upper-cased (`HELLO, <NAME>!`), followed by a newline, and exits 0. `--shout` must come after the name.
- FR-3: When the name is missing (`greet` with no argument, or `greet --shout`) or empty (`greet ""`, or only whitespace), the command writes a non-empty error message to stderr, writes nothing to stdout, and exits 2. No traceback is printed.
- FR-4: The `hello` command keeps its current behaviour: `python3 greeter.py hello` prints `hello, world` followed by a newline and exits 0. An unknown command still prints the usage line to stderr and exits 2.
- FR-5: The `greet` command takes exactly one name, optionally followed by `--shout`. Any other argument (a second name, a `--flag` other than `--shout`, a repeated `--shout`, or `--shout` placed before the name) writes an error to stderr, writes nothing to stdout, and exits 2.

## Non-functional requirements
- NFR-1: The change uses only the Python standard library. `python3 -m py_compile greeter.py` and `python3 -m unittest -v` both pass after the change.
- NFR-2: The change does not add a dependency, a server, a file write, or a network call.

## Touches
- `greeter.py`: `main()` gets a new `greet` branch that parses the name and the optional `--shout`.
- `test_greeter.py`: new unit tests for `greet` are added next to the existing ones.

## Must not touch
- The `hello` branch of `main()` and the text it prints.
- The unknown-command branch of `main()` (its message and exit code 2).
- The existing tests `test_hello` and `test_unknown_command_is_usage_error`, which must pass unchanged.
- `README.md`, `review.md`, `CLAUDE.md`, and anything under `specs/` other than `specs/greet/`.

## Decisions
- D1: Surrounding whitespace is removed from the name before use, so `greet "  Ada  "` prints `Hello, Ada!`. A name that is only whitespace counts as empty (FR-3). The name is otherwise printed as given, so `greet "Grace Hopper"` prints `Hello, Grace Hopper!`.
- D2: `--shout` is only accepted after the name. Placing it before the name is a usage error (FR-5), so the argument order is never guessed.
- D3: Anything beyond one name plus an optional trailing `--shout` is a usage error with exit 2 (FR-5). A typo therefore fails loudly instead of printing a greeting for the wrong thing. Exit 2 matches the existing usage-error code.
- D4: "Upper case" means Python's `str.upper()` on the whole line, so the `Hello, ` prefix and `!` are upper-cased too (`HELLO, ADA!`).
- D5: The stderr error text is free wording. The evals only require a non-empty message on stderr and no traceback.
- D6: The unknown-command usage line in `main()` is left as it is (it still names only `hello`). The existing test checks only its exit code, and changing it is not needed for this feature. Listed under out of scope.
- D7: `hello` keeps ignoring extra arguments, as it does now. The new strict argument rules (D3) apply to `greet` only.
- D8: Risk is `low`, as given by the user. The worst case is a wrong greeting printed to a terminal; nothing is stored, sent, or charged.

## Out of scope
- A `--help` text for `greet`, or changing the unknown-command usage line to list `greet`.
- Greeting several names in one call, reading names from stdin or a file, or greeting in other languages.
- Any change to `hello`, including making it accept a name.
- README or documentation updates.

UI: no
