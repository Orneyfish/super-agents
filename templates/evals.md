# Evals: TODO ticket title

Approved by the user before building. Nobody edits this file while building; outcomes go in results.md.

## Setup
1. TODO install and start steps. A ticket runs on its own port (3100 + ticket number), with its own data directory and test account (tNNN), so tickets built in parallel never share state.

## E1: TODO short title
- covers: FR-1
- check: TODO exact command or browser steps, runnable by someone who has not seen the code
- pass when: TODO the observable result
- fail when: TODO what a stub or lazy implementation would show, and the check can detect

## Definition of done
- [ ] Every eval above has a pass row in results.md, with evidence
- [ ] Nothing under "Out of scope" was built and nothing under "Must not touch" changed
- [ ] The project's lint and build pass
