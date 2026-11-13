# Results: greet
**Updated:** 2026-11-11T16:01:59Z
**Review:** clean
| eval | result | evidence |
|------|--------|----------|
| E1 | pass | evidence/E1-greet.txt: `Hello, Ada!$` exit=0, `Hello, Grace Hopper!$`, stderr 0 bytes |
| E2 | pass | evidence/E2-shout.txt: `HELLO, ADA!$` exit=0, `HELLO, GRACE HOPPER!$`, stderr 0 bytes |
| E3 | pass | evidence/E3-missing.txt: exit=2, stdout 0, stderr 55 bytes, traceback 0, unknown-command usage 0 |
| E4 | pass | evidence/E4-empty.txt: all 5 cases exit=2, stdout 0, stderr >0, traceback=0, unknown_cmd_usage=0 |
| E5 | pass | evidence/E5-extra.txt: all 5 cases exit=2, stdout 0, stderr >0, traceback=0, unknown_cmd_usage=0 |
| E6 | pass | evidence/E6-hello.txt: `hello, world$` exit=0, nope exit=2, removed test lines 0, existing tests ok, final OK |
| E7 | pass | evidence/E7-stdlib.txt: compile=0, only import is sys, unittest last line OK |
