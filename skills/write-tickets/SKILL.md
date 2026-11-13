---
name: write-tickets
description: Turn a request or a PRD into one ticket per feature, each written down in full (requirements plus strict evals) so a worker can build it without asking anything, and a BOARD.md saying which tickets can run in parallel. Use when the user wants several features planned for parallel building, or says "write tickets", "break this PRD down". For a single feature use write-eval.
argument-hint: <request, or path to a PRD>
allowed-tools: Bash(super-agents *)
---

A ticket is one feature, or one self-contained piece of any other work (a document, an analysis, a plan), written down so completely that an agent can build and check it without asking anyone. Workers never talk to the user, so everything that needs a human decision is settled here, before any work starts. Do not build anything in this skill.

Input: "$ARGUMENTS" (read it if it is a file path).

1. **Split into tickets.** One ticket per feature, or per self-contained part of any other piece of work: the smallest piece that can be shipped and checked on its own and is worth something to whoever relies on it. "Add auth and a dashboard" is two tickets. "Add a button, and make the button save the form" is one, because the button is useless without the saving. Rules for the split:
   - A ticket goes end to end: every layer or part it needs to work and be checked, not one layer of the whole. For a document, a report section that is researched, written and cited is a ticket; "all research, then all writing" is the horizontal split to avoid.
   - A ticket fits one fresh context window: a worker that has read only its own `RD.md` and `evals.md` and the files named in Touches can finish it. If it cannot, split it again.
   - A change that cannot land alone is sequenced as separate tickets: add the new beside the old, move the users over, remove the old. Each lands and passes its own evals.
   Show the user the split as a numbered list (title, what it delivers, waits for) and confirm it before any ticket is written. Change it as they ask. Done when: the user has confirmed the list.
2. **Read the project first**, briefly: enough to write precise tickets, not to audit it. Done when: you could name the files each ticket touches.
3. **Settle every open decision, by frontier.** The frontier is the set of undecided questions that block the most tickets. Ask it in rounds of at most four questions, through AskUserQuestion (or your harness's question tool; otherwise ask in chat), and give each question a recommended answer first, then 1-3 other options. Look a fact up in the project instead of asking about it. Ask about anything that changes what the reader or user sees or gets: behaviour, wording, limits, permissions, data, what happens when it is empty or fails. Skip a round when nothing is undecided. Write each answer under Decisions in the ticket it affects. When `GLOSSARY.md` exists at the project root, use its terms in the `FR-` lines and add a term (name, one sentence, an Avoid list) when an answer settles one; it is the project's own file, outside `specs/`. If answers change the split, show it again. Done when: a worker could build each ticket without making any decision that changes the result.
4. **Location and numbers.** Tickets go in `specs/tickets/NNN-slug/`, with three-digit numbers continuing from the highest existing one (first ticket: `001`). Done when: every ticket has its directory name.
5. **Write each ticket** by following the `super-agents:write-eval` skill with that directory, from choosing the kind through validation (kind and deliverable, requirements, risk, evals plus mockup for UI): skip its hand-over and stop steps, the hand-over is step 8 here. Each ticket gets its own `**Kind:**` and `**Deliverable:**` line. Extras for tickets:
   - Names other tickets rely on (tables, columns, routes, functions, headings, files) are written out exactly in the `FR-` lines of the ticket that creates them, and cited by the tickets that use them. That is the contract between tickets.
   - When the ticket has a running app, each eval Setup gives it its own port (3100 + NNN), its own data directory and test account `tNNN` (or what `review.md` says), so tickets built at the same time never share state. Otherwise Setup names a scratch directory of its own.
   Done when: every ticket has an `RD.md` and `evals.md` that the write-eval steps accept.
6. **`specs/tickets/BOARD.md`**:
   ```
   # Board
   | # | Title | Status | Mode | Runs |
   |---|-------|--------|------|------|
   | 001 | Foundations | draft | team | alongside |
   | 002 | Password reset | draft | solo | waits for 001: needs the mailer and tokens table |
   ```
   Every ticket starts `draft`. **Mode** is `team` only when the ticket spans several independent areas that different people could own file by file and is big enough that one worker would be the bottleneck; otherwise `solo`. **Runs** is `alongside`, or `waits for NNN[, NNN]: reason` when the ticket needs another's output or a contract it creates, or when both change the same files (name the files). Two tickets that change the same binary file (docx, xlsx, pptx, an image) wait for each other, because git cannot merge it; name the file in Runs. When unsure, make it wait: a needless wait costs minutes, a conflict costs a merge. Done when: every ticket has a row, a mode and a Runs entry.
7. **Validate.** `super-agents board check` and `super-agents check-evals <ticket dir>` for each ticket; fix until everything prints `OK`. Done when: every command prints `OK`.
8. **Hand over.** Give the user the ticket folders, the split, the board, and every decision you made yourself. All tickets are `draft`. Tell them to read the tickets (RD.md and evals.md are what they approve), then `/super-agents:mark-ready 001 002 ...` to mark the ones to build, then run `superagent` in a terminal. Build nothing. Done when: you have told the user all of this.
