# ADR-0088 — The tester/coder split is dispatched per task, but a task divides by file

- **Status:** Accepted
- **Date:** 2026-07-30
- **Issues:** #241 (found by the Phase 7.1 shakedown run, at Step 5 of the chain on #222)
- **Related:** ADR-0049 (the decision this amends — its dispatch, never its decision), ADR-0048
  (the requirement-ID brief the fallback chain is built on), ADR-0035 (a contract belongs in the
  agent's own file), ADR-0086 (the extraction criterion applied and declined here), ADR-0073
  (the line-wrap lesson, reproduced by this feature's own first test run)

## Context

ADR-0049 split test authoring from implementation: the tester runs before the coder per task group,
and `test-write-scope.sh` denies the coder any create or edit of a test-shaped path once its
dispatch prompt carries the TEST-AUTHORING SCOPE marker. The decision is right and this ADR reverses
none of it.

The Phase 7.1 shakedown run was the first time any chain reached Step 5 (#239 records why: the
pre-flight it had to pass could never be satisfied). It stopped there. #222's plan has seven tasks,
and four of them have edits to `staging/plugin/scripts/tests/*.test.sh` as their deliverable. The
coder is denied those files by a hook doing exactly what it was designed to do, and nothing had ever
told it they were not its work.

### The issue's framing was too narrow, and the measurement is what shows it

Issue #241 was filed as "a feature whose deliverable is test code". Measured over
`docs/superpowers/plans/`: **56 of 57 plans name both test-shaped and implementation paths**; one
names no test-shaped path at all. Adding #222's own plan makes it 57 of 58. This is not a category
of feature. It is the shape of essentially every plan this repository has produced, and the chain
would have hit it on any of them.

### The cause is granularity, not perimeter

- The coder is dispatched on a **range of tasks**.
- A plan task is a **mixed unit**: some sub-steps target test-shaped paths, some do not.
- The tester's brief is a strict fallback chain — SPEC `R-NN` ids first, Success Criteria second,
  **the plan's task text only if both are absent**. On a SPEC that declares ids, which ADR-0048
  makes the normal case, the plan is never read for scope, so the tester is never told which of the
  batch's sub-steps are its own.
- The coder's brief says the batch's red tests "already exist … Make them green", which presumes
  they were separate deliverables rather than sub-steps of the coder's own tasks.

So for any task containing a test-shaped sub-step: either the tester writes it by luck, or the
coder is denied and the task cannot close.

### Generator/verifier separation is already preserved, and saying so is the decision

The #222 plan encodes it by task ordering without anyone having designed it that way: Task 1 writes
`F10` and confirms it RED against the real repository; Task 2 vendors the file and turns it GREEN.
Mapped onto the roles, **the tester writes the assertion and confirms its RED, and the coder makes
the change that turns it GREEN**. The verifier still authors the criterion; the generator still
satisfies it.

That is the answer to the question the fix had to settle — *who verifies an assertion, when the
red-test-first protocol has no meaning because the deliverable **is** the red test*. Nothing about
the perimeter needs to move.

## Decision

### D1 — The plan is read for scope in every case, never as a fallback

The existing fallback chain is untouched: it decides **what** to assert. A second, unconditional
instruction is added to both tester dispatch sites — the plan decides **where and under what name**.
The tester works through the batch's sub-steps and executes every one that creates or edits a test
file, because the coder dispatched next is denied them, so **a skipped sub-step is a sub-step nobody
can do**. Where a sub-step says to confirm a failing assertion and stop, it stops: a red assertion
left red is the deliverable, not an unfinished task.

### D2 — The coder is told what is not its work, and the report is the escape

Both coder dispatch templates gain the same block, immediately after the marker line and inside the
same verbatim prompt text: the batch's test-shaped sub-steps were executed by the tester and are not
the coder's; do not repeat them, do not edit those files; if that leaves a task looking incomplete,
say so in the report rather than closing the gap. The existing "Make them green" is qualified in the
same block — an assertion the plan defers to a later task stays red, and the report names it.

### D3 — ADR-0049 A5 stands: no manifest field, no opt-out, no change to the marker

A5 rejected an opt-in field on the ground that separation which is optional is off on the runs that
most need it. That argument is untouched here, because the separation is **preservable** in the case
that appeared to require an exemption. A fix that weakened the marker would have been solving the
wrong problem, and `test-write-scope.test.sh` `TM5` is the guard that says so: it pins the marker
byte-identical, ASCII hyphen, at one hook site and three `concept-to-code` sites. **A "fix" for #241
that changes the marker is the failure mode, not the remedy.**

`test-write-scope.sh` is byte-untouched. It behaves exactly as designed.

### D4 — No new script, and the reason is measured

A mechanical per-task file split was the obvious alternative and it is not available. It needs a
per-task file declaration in the plan, and no convention covers the corpus: `**File(s):**` appears in
**18 of 58** plans, a `Budget:` line parseable by `diff-budget-check.sh` in **2 of 58**. A mechanism
derived from either would be inert on the majority and inert **silently**, which is the failure class
this repository keeps filing issues about.

So the split is made by the agent from the plan text, and **the hook is the backstop**: a
misclassification produces a loud deny plus an agent report, never a silent wrong result. That is
what lowers the bar for an instruction here — the enforcement layer already exists and catches the
error.

A second copy of the path predicate is deliberately not created. ADR-0086's criterion would call it
extractable, since two copies giving different answers would be a defect. Extracting it **into** the
hook is what that would mean in practice, and it would weaken a self-contained security guardrail
whose contract is allow-on-every-failure-mode: a missing predicate file would become an allow. The
briefs therefore do not restate the predicate at all. They state the rule and leave classification to
the deny message, which explains itself.

### D5 — Batch boundaries are a design choice, and the rule is written where batches are chosen

The tester runs once per batch, before the coder, so an assertion that depends on another task's
output cannot see it when both sit in the same batch — the merge-back that would make it visible
happens at the batch boundary. Two rules follow: do not put an assertion in the same batch as the
task it depends on, and do not split a red assertion from the task that turns it green. #222's plan
is the worked example, stated at the call site: Task 3's `C7` must see Task 2's vendored file, so
they belong to different batches, while Task 1's `F10` and Task 2's vendoring belong to the same one.

### D6 — `tester.md` states the contract in its own file

ADR-0035's finding, applied for the second time to this agent: a contract that lives only in the
dispatching skill is a contract the agent cannot read. `tester.md` gains a Process step, an Output
Format line, and an edge case for the confirm-a-failure-and-stop sub-step.

No new `step5-report.json` field. `tests_written_by` (ADR-0049 §D5) already answers "who wrote the
tests", and it is a record, never a gate.

## Alternatives rejected

- **A1 — Drop the marker for batches that touch test files.** The hook arms only on the marker, so
  this works and disables the separation for the whole batch, including the parts where it should
  apply. Rejected: it trades a briefing gap for a perimeter hole.
- **A2 — Give the test-file tasks to the tester as a general-purpose editor.** Allowed by the hook,
  and it produces a dishonest record: the tester briefed to "write failing tests" while the actual
  task is "add assertion `C7`". D1 achieves the same routing with the brief telling the truth.
- **A3 — Implement inline as the orchestrator.** The hook allows the main session by design. Works,
  and forfeits Step 5 entirely.
- **A4 — A manifest field declaring the feature's deliverable is test code.** ADR-0049 A5, and the
  57-of-58 measurement makes it worse than that: the field would be set on essentially every run,
  which is an opt-out with extra steps.
- **A5 — Derive the split mechanically from the plan.** Rejected on measurement, §D4.

## Consequences

### Positive

- The chain can complete a plan whose tasks are mixed, which is 56 of the 57 plans on `main`.
- The tester's role becomes legible: it owns test files, in every case, for the whole batch.
- The red-assertion-as-deliverable case is stated for the first time, in the skill and in the agent.

### Negative, and not fully mitigated

1. **This ships an instruction, not an enforcement.** Nothing guarantees an agent follows the brief.
   What changes is the failure shape: a misclassification is now a loud deny and a report, instead
   of a task nobody can close. The harness pins that the instruction exists, never that it is
   obeyed — the same distinction ADR-0047 and ADR-0048 record for their own gates.
2. **The batch-boundary rule has no mechanism.** Whoever chooses batches must read the plan. #242
   (the `≥6` threshold consuming a count that is not a task count) is where a mechanism belongs if
   one is ever built.
3. **The Workflow path's prompt is model-generated text** (ADR-0049 negative consequence 2). The new
   clauses inherit the marker's own limit on that path: they are asked for, not copied.
4. **Inert until `sync-to-claude.sh --apply`**, like every skill fix in this repository. The paused
   #222 run executes the deployed copy, so it stays blocked until the sync lands.

### Neutral

- No new file, no new script, no CI registry change. `test-write-scope.test.sh` gains a section and
  its first assertion-count floor.

## Verification

`TM1`–`TM4` were seen RED against the unmodified tree and are the fix evidence. `TM5`, `TM6`, `TM7`,
`TM8` and `Z1` pass before and after — forward guards and executed premises, labelled as such in the
harness so a later reader does not mistake them for evidence.

Three checks were run in the failing direction: an em dash substituted at one marker site
(`TM5` fails, reporting 2 sites instead of 3); the tester clause reworded at one of the two dispatch
sites (`TM1` fails, reporting 1 instead of 2); the plan corpus pointed at an empty directory (`TM6`
fails on the **denominator** guard, not by reporting zero mixed plans as a clean result — ADR-0085's
lesson).

`TM7`/`TM8` run the hook against a real file in this repository — a marker-carrying coder is denied
`pairs-completeness.test.sh`, the tester is allowed the same path. That is ADR-0088's whole premise
executed rather than asserted (rule 11).

**Harness lesson, the fourth of its family.** `TM2` and `TM3` reported 0 on their first run against
clauses that were present and correct, because the clauses **wrap across two lines**. ADR-0073 hit
the line-wrap form, ADR-0076 the comment-marker form, ADR-0080 the backtick form; this is the same
lesson met while writing an ADR that cites it. Every prose clause assertion now matches against a
whitespace-flattened copy, and `count_flat` is separate from `count_lit` because `TM5` must stay
line-based: the hook greps a single line, so a marker split across two is a marker the hook cannot
see, and flattening would hide exactly the defect it exists to catch.

## Correction 2026-07-31 (issue #247, ADR-0101)

**§D5 states its two batch-boundary rules as if they were jointly satisfiable. They are not, and
issue #222's own plan — the worked example this ADR uses — is a case where they conflict.**

Rule 1 (do not put an assertion in the same batch as the task it depends on) forces Task 3 into a
later batch than Task 2: `C7`'s RED must be *"the vendored file exists but does not name gate
5.05"*, which the tester cannot observe before Task 2 vendors it. Rule 2 (do not split a red
assertion from the task that turns it green) wants Tasks 2 and 3 together, because
`skill-coverage-perimeter.test.sh`'s `S1` reddens at Task 2 and greens at Task 3.

No batching satisfies both. §D5 gave a reader applying it in good faith no way to choose.

**Rule 1 outranks rule 2, and the reason is what to carry forward rather than the verdict: evidence
quality beats checkpoint tidiness.** Violating rule 1 makes an assertion fail for the wrong reason,
so the recorded RED proves nothing and writing the test first bought nothing. Violating rule 2
leaves an intermediate checkpoint red — visible, explainable, resolved by a later batch inside the
same Step 5.

ADR-0101 also adds what §D5 never said: **what a red intermediate checkpoint means.** ADR-0049's
flow assumes red-then-green within a batch, and `S1` is neither — it is a third-party guard in a
file nobody in the batch touched. The reading rule now lives beside the checkpoint instruction.

This ADR's body is not edited in place (ADR-0034 precedent). Detail:
`docs/architecture/ADR-0101-247-batch-boundary-precedence.md`.
