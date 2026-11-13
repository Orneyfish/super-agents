---
name: write-tickets
description: Turn a request or a PRD into one ticket per feature, each written down in full (requirements plus strict evals) so a worker can build it without asking anything, and a BOARD.md saying which tickets can run in parallel. Use when the user wants several features planned for parallel building, or says "write tickets", "break this PRD down". For a single feature use write-eval.
argument-hint: <request, or path to a PRD>
allowed-tools: Bash(super-agents *)
---

A ticket is one feature written down so completely that an agent can build and check it without asking anyone. Workers never talk to the user, so everything that needs a human decision is settled here, before any work starts. Do not build anything in this skill.

Input: "$ARGUMENTS" (read it if it is a file path).

1. **Split into features.** One ticket per feature: the smallest piece that can be shipped and checked on its own and is worth something to a user. "Add auth and a dashboard" is two tickets. "Add a button, and make the button save the form" is one, because the button is useless without the saving. A large epic becomes several tickets. Tell the user how you split it so they can merge or split differently.
2. **Read the codebase first**, briefly: enough to write precise tickets, not to audit the repo.
3. **Interview the user until nothing is left to guess.** Use AskUserQuestion (or your harness's question tool; otherwise ask in chat), **one question at a time**. When there is a choice, give 2-4 options with your recommendation first rather than an open question. Ask about anything that changes what the user sees or gets: behaviour, wording, limits, permissions, data, what happens when it is empty or fails. Keep going until a worker could build each feature without making any decision that changes the result.
4. **Location and numbers.** Tickets go in `specs/tickets/NNN-slug/`, with three-digit numbers continuing from the highest existing one (first ticket: `001`).
5. **Write each ticket** by following steps 1-5 of the `super-agents:write-eval` skill with that directory (requirements, risk, evals plus mockup for UI, validation); skip its steps 6-7, the hand-over is step 8 here. Two extras for tickets:
   - Names other tickets rely on (tables, columns, routes, functions) are written out exactly in the `FR-` lines of the ticket that creates them, and cited by the tickets that use them. That is the contract between tickets.
   - Each eval Setup gives the ticket its own port (3100 + NNN), its own data directory and test account `tNNN` (or what `review.md` says), so tickets built at the same time never share state.
6. **`specs/tickets/BOARD.md`**:
   ```
   # Board
   | # | Title | Status | Mode | Runs |
   |---|-------|--------|------|------|
   | 001 | Foundations | draft | team | alongside |
   | 002 | Password reset | draft | solo | waits for 001: needs the mailer and tokens table |
   ```
   Every ticket starts `draft`. **Mode** is `team` only when the ticket spans several independent areas that different people could own file by file and is big enough that one worker would be the bottleneck; otherwise `solo`. **Runs** is `alongside`, or `waits for NNN[, NNN]: reason` when the ticket needs another's output or a contract it creates, or when both change the same files (name the files). When unsure, make it wait: a needless wait costs minutes, a conflict costs a merge.
7. **Validate.** `super-agents board check` and `super-agents check-evals <ticket dir>` for each ticket; fix until everything prints `OK`.
8. **Hand over.** Give the user the ticket folders, the split, the board, and every decision you made yourself. All tickets are `draft`. Tell them to read the tickets (RD.md and evals.md are what they approve), then `/super-agents:mark-ready 001 002 ...` to mark the ones to build, then run `superagent` in a terminal. Build nothing.
