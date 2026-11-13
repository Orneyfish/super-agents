# Kinds of work

Every piece of work has a kind, set in `RD.md` as `**Kind:**`. A missing line means `code`. The kind changes what "done" is checked with, never whether it is checked: every eval still needs a `check` an agent that did not do the work can run, a `pass when` that can be observed, and a `fail when` that names what lazy work looks like.

Read the section for this work's kind. Whoever relies on the work is its reader, user or operator.

## code
- done when: it behaves as the requirements say in the running thing (tests, requests, a browser walk), at the sizes and states the spec names.
- eval patterns: a test command, a request with the expected response, a script, browser steps. A stub that returns a fixed value must fail.
- reviewer checks: wrong behaviour, missing error and edge handling, secrets, data loss, a change outside Touches.
- pre-merge checks: lint and build from `review.md`.

## document
- done when: every required part is present, every factual claim is supported, and a reader can act on it. The deliverable is the file.
- eval patterns: structure (grep each required heading, a word or page limit by command); reader test (questions and expected answers written in `evals.md`, answered from the document alone with the quoted passage); claims (every number and factual claim with its source, each source opened); links (fetch every URL); style (the project's linter or banned-word list, if any).
- reviewer checks: a heading with filler under it, a claim with no source, a number that contradicts another, content nobody asked for, a dead link.
- pre-merge checks: style or link check, or the build of the published form; `none` is allowed.

## research
- done when: the question is answered, each claim traces to a primary source, and what is unknown is stated.
- eval patterns: traceability (open the cited source and find the quoted text: all claims at high risk, a stated sample otherwise); source quality (first-party or the original study, not a summary of it); coverage (each sub-question answered or marked "not found, searched X"); counter-evidence (a section exists and cites at least the number of sources the eval names).
- reviewer checks: a quote that is not at the source, a secondary source, a sub-question silently dropped, a conclusion stronger than the evidence.
- pre-merge checks: link check, or `none`.

## analysis
- done when: the numbers reproduce from the raw data and answer the question asked.
- eval patterns: reproduce (copy the working tree as it is into a temp directory, delete the generated outputs there, run the script, and compare every number in the report; the work is not committed while it is tested, so a fresh clone would test an older version); reconcile (rows in equal rows out plus rows dropped, with reasons); known answer (the method run on a small fixture worked by hand in `evals.md`); sanity (totals equal the sum of parts, no value outside the stated range); charts (values from the chart's data file equal the table).
- reviewer checks: a hand-typed number, a filter that drops rows unreported, a chart drawn from different data, a claim of cause from correlation.
- pre-merge checks: the script's tests or lint, or `none`.

## design
- done when: every required state and size is shown and a newcomer can complete the listed tasks on it.
- eval patterns: states (each state named in `RD.md` is present and labelled); tasks (complete the listed tasks in a browser at desktop width and about 390px); accessibility (contrast and label check by tool); consistency (the project's tokens or components).
- reviewer checks: a missing state, a task that needs explanation, contrast below the stated ratio, a mockup that disagrees with the requirements.
- pre-merge checks: the project's design lint, or `none`.

## plan
- done when: someone could start step 1 without asking anything, and every goal is measurable.
- eval patterns: cold start (for each step, the questions written in `evals.md`, at least: what exactly is done, by whom, with what input, and how is it known to be finished; each answered from the plan alone with the quoted passage; fail when a question has no quoted passage or its answer needs a choice the plan does not make); structure (each step has an owner, an order or date, and an observable outcome; each risk has a response); dependencies (no step depends on a later one, no cycle); constraints (budget, dates and limits from `RD.md` add up, with the arithmetic shown).
- reviewer checks: "improve X" with no measure, a step that needs an undecided choice, totals over budget.
- pre-merge checks: `none`.

## operations
- done when: the procedure was executed on a safe target and the end state was read back. The real target is never touched; the real run is the user's, after done.
- eval patterns: dry run (a sandbox, a copy, or the tool's dry-run mode); end state (a command that reads the state back); repeat (run it twice, the second run changes nothing); rollback (run the undo and read the state back).
- reviewer checks: a step that was only described, no read-back, an undo that was never run, a command that would touch the real system.
- pre-merge checks: syntax or config validation, or `none`.

## Risk, for any kind

Ask: what happens to whoever relies on this if it is wrong?
- low: it reads or looks wrong, nothing follows from it. One check per requirement.
- medium: someone is misled or redoes work, and it can be corrected. Add an error or edge case per requirement.
- high: a decision about money, law, safety or people's data, or anything published or executed that cannot be taken back. Check every claim, not a sample, and add a rollback or correction path.

## Evidence formats

Evidence goes in `evidence/` and must show what was seen, not what was expected.
- claims or traceability check: a `.txt` table with columns claim, source, quoted text found, verdict.
- reader or cold-start check: a `.txt` table with columns question, quoted passage, location. A question with no quoted passage is a FAIL.
- reproduction: the command, its output, and the comparison.
- taste (tone, look, persuasiveness) is not an eval unless it was turned into something observable; it stays the user's own review at hand-over.
