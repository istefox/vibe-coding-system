# ADR-0069 — One canonical plan-task form, in one place the consumers derive from

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #172
- **Related:** ADR-0048 (`spec-coverage.sh`), ADR-0052 (`diff-budget-check.sh`), ADR-0020
  (`autopilot-build` pre-flight), issue #174 / the leading-dash fix that had to land first,
  issue #184 (the fourth parser, deliberately out of scope — see §D5)
- **Reported as:** a live chain failure, not an audit finding.

## Context

On the first end-to-end chain run in an external project, Step 5's plan-structure check reported
zero pending tasks on a plan holding eight, and refused to dispatch with a message asserting the
plan "may be malformed". It was not malformed.

The architect had written its tasks as headings:

```
## Task 1 — … (R-01, R-02)
## Task 2 — … (R-03)
```

`architect.md`'s Output Format sanctions exactly this: *"Every task cites the requirement IDs it
satisfies, form `### Task 3 — … (R-02, R-05)` **or on a checkbox item**"*, and
`concept-to-code/SKILL.md`'s architect dispatch repeats the same permission verbatim. So the
heading form is one of two documented outputs, and the consumer that rejected it was reading a
narrower contract than the one the writer was given.

### What the count actually measures

`concept-to-code/SKILL.md` and `autopilot-build/SKILL.md` both count with the same line, and both
call the result `unchecked`:

```bash
unchecked=$(grep -c -e '- \[ \]' "$plan" 2>/dev/null); unchecked=${_uc:-0}
```

The name implies progress tracking, and there is none. **Nothing in the chain ever writes `[x]`
back into a plan file.** Task completion is recorded in `step5-report.json` as `tasks_completed`;
the `[x]` machinery in `concept-to-code/SKILL.md` (lines 361, 867, 1910–1922) belongs to
`PROJECT.md`, the roadmap, not to the plan. A plan's checkboxes are therefore always unchecked, and
the check is not "is there pending work" — it is "does this file contain any task at all", a
malformed-plan guard. That reframing is what makes §D1 cheap: a form with no done-marker loses
nothing, because the marker was never read.

The same measurement shows the count is not counting tasks either. In a heading-form plan the
checkboxes that do appear are **sub-steps inside a task** (`- [ ] Re-run Task 2. Sections A and B
green.`), so `grep -c '- \[ \]'` returns the number of sub-steps across the whole plan. It works
only because the consumer needs `>= 1` and never the value.

### Measured, not assumed: four parsers, three definitions, 57 plans

`docs/superpowers/plans/` on 2026-07-29:

| Parser | Predicate | Plans matched |
|---|---|---|
| `spec-coverage.sh:201` | checklist item **or** H2–H4 containing `Task` | **56 / 57** |
| `concept-to-code/SKILL.md`, `autopilot-build/SKILL.md` | any `- [ ]` | 50 / 57 |
| `diff-budget-check.sh:102` | `- [ ] **Task N` | 18 / 57 |

Seven plans carry no checkbox at all and would abort both consumers today. **The heading form is
not a tolerated deviation, it is what architects write**, and `spec-coverage.sh` — the newest of
the parsers, and the only one written after the architect contract was — already agrees with them.

The 57th plan is recognised by **nothing**, including `spec-coverage.sh` today:
`2026-06-06-claude-md-slim.md` structures its work as `### Step 0 — Scaffold …`, a third word.
Named rather than absorbed — see §D6.

## Decision

### D1 — The canonical form is `is_task_line = checklist item OR H2–H4 heading containing "Task"`

Both documented writer forms are accepted, unchanged. `architect.md:60` and
`concept-to-code/SKILL.md:380` are correct as written and are not touched.

`spec-coverage.sh`'s existing predicate is promoted rather than a new one invented: it is the only
one that matches the whole corpus, it was written against the current architect contract, and it
has ADR-0048's backward-compatibility guarantees behind it.

### D2 — The predicate lives in one file, shared by `awk -f`

`concept-to-code/scripts/plan-task-predicate.awk` holds `heading_level`, `is_checklist_item` and
`is_task_heading`. Both consumers of the predicate load it as an additional program file:

```bash
awk -f "<scripts>/plan-task-predicate.awk" -f "$TMPD/plan_parse.awk" "$PLAN"
```

This is the whole point of the ADR. #172's own diagnosis — *"the defect is three files
independently deciding what a plan task looks like"* — is not fixed by making three files agree
today; it is fixed by leaving only one file that decides. `awk -f` composition is what makes that
possible without restructuring `spec-coverage.sh`'s heredoc-built program.

`spec-coverage.sh` loses its inline copies of the three functions and gains the `-f` load. Its
behaviour is unchanged by construction — same function bodies, same call sites — and ADR-0048's
backward-compatibility section (the whole 34-SPEC corpus must stay silently passing) is the
regression net.

### D3 — `plan-tasks.sh` is the single counting entry point for both SKILL.md consumers

A new `concept-to-code/scripts/plan-tasks.sh --count <plan>` prints one integer: the number of
tasks the canonical predicate recognises. `concept-to-code/SKILL.md`'s Step 5 pre-dispatch block
and `autopilot-build/SKILL.md`'s check 5 both call it.

It is a **checker**, not a reporter — the caller branches on the printed count, and on exit code 2
for a bad invocation and 3 for an awk that cannot run the predicate. The third exit code exists for
the reason `secret-scan.sh` has one: a check that reports nothing must be distinguishable from a
check that finds nothing. The two adjacent gates at the same Step 5 checkpoint have the opposite
contract (`weakening-scan.sh` and `diff-budget-check.sh` are reporters that always exit 0), and
that trap is restated at both call sites, as ADR-0048 §D7 and ADR-0052 already had to do in the
same file.

### D4 — Both error messages stop naming the checkbox

`"no unchecked tasks (- [ ]) found"` is wrong for a heading-form plan and was the sentence that
sent the live investigation at the plan instead of at the checker. Both messages now name both
forms and say what was actually counted.

### D5 — `diff-budget-check.sh` is NOT reconciled here

It is the fourth parser and the strictest, and the same measurement shows it has never fired: the
single plan in the corpus that declares a `Budget:` is written in heading form, so it produces no
task block and no attribution. Filed as **issue #184**.

Kept out on purpose. Its predicate does strictly more than recognise a line — it **delimits a
block**, from one task line to the next, and a budget's file scope depends on that boundary.
Widening it turns a silent feature active and may produce findings on work in flight. That is a
behaviour change with its own risk, not a contract correction, and bundling the two would make a
regression impossible to attribute.

### D6 — The `Step`-form plan is exempted by name, not absorbed into the predicate

`2026-06-06-claude-md-slim.md` writes `### Step N — …`. Widening the predicate to `Task|Step` was
rejected: it changes `spec-coverage.sh`'s behaviour on the plan side for every plan, not only that
one — R-NN tokens would start being extracted from `Step` headings — and it is a decision made to
accommodate a single completed plan from before the architect contract existed. That plan will
never be dispatched again.

The exemption lives in the test (`PTE2`), keyed on the filename, with a companion assertion
(`PTE3`) that the file still exists. A **new** unrecognised plan therefore fails, instead of
disappearing into a tolerance threshold — and if that plan is ever deleted, `PTE3` fails and forces
the exemption out with it. If the `Step` form ever recurs in a plan an architect writes today, that
is the signal to widen the predicate deliberately, with its own measurement.

## Alternatives considered

### A — Narrow the writers to the checkbox form (issue #172's option B)

Rejected on measurement. It invalidates the seven checkbox-free plans retroactively, contradicts
what 56 of 57 plans actually contain, and requires deleting `is_task_heading` from
`spec-coverage.sh`, where it works and is covered. It is the smaller surface only if the corpus is
ignored.

It also removes information: a heading form gives a task a name and a level; `- [ ]` gives it
neither unless the writer also adds `**Task N**`, which is what `diff-budget-check.sh` discovered
the hard way by requiring it.

### B — Widen each consumer in place, no shared file

Rejected. It satisfies #172's acceptance criteria literally (the three files agree) and leaves the
defect intact: three copies that agree today and drift tomorrow, with no file that owns the answer.
The repository has this failure mode on record — ADR-0043's PAIRS gap and issue #174's five
scattered warnings for one idiom are both "fixed where a comment happened to be written".

### C — A test that asserts the four parsers agree, changing none of them

Rejected as the weakest form of the same idea. It detects divergence after the fact instead of
making divergence unrepresentable, and it would have to encode the canonical answer somewhere
anyway — at which point that place should be the implementation.

### D — Make the count meaningful by writing `[x]` back into the plan as tasks complete

Rejected as a larger design that this issue does not need. It would give `unchecked` its literal
meaning and enable resume-from-task-N, but it puts a mutation of a human-reviewed design artifact
on the unattended path, and `step5-report.json` already records completion for the consumers that
care. Noted here because the field name will keep implying it.

## Consequences

### Positive

- A heading-form plan dispatches. The chain's most recent real plan
  (`2026-07-28-176-worktree-isolation-contract.md`) and the six other checkbox-free plans stop
  being rejected by a message that blames them.
- One file decides what a plan task is. A future consumer gets it by `awk -f`, not by copying a
  regex.
- The unattended paths stop aborting on a correct plan: `autopilot-build` `exit 1` writes an
  `aborted` report and `nightly-autopilot` reaches Steps 5–7 through the same check.
- `spec-coverage.sh` is no longer a third opinion; it is the source of the one opinion.

### Negative

- `plan-tasks.sh` is a new cross-skill dependency: `autopilot-build` now calls a script inside
  `concept-to-code/scripts/`. That is the third such dependency (ADR-0047 §D2 for
  `weakening-scan.sh`, and the pre-existing `manifest-*.sh` calls) and the accepted price of one
  source of truth.
- **Both call sites invoke the deployed path (`~/.claude/…`), so this change is inert — worse than
  inert — until a sync.** Without the two new `PAIRS` entries the scripts never reach `~/.claude`,
  both blocks exit 127, and the "did not run" branch aborts every dispatch. `pairs-completeness.
  test.sh` cannot catch that: skill `scripts/` are vendored selectively and are outside its scope
  (ADR-0043). `PTB7` pins the two entries directly for that reason.
- The count over-counts on purpose. `## Tasks` as a section heading matches the predicate, and a
  checkbox sub-step still counts. For a `>= 1` guard the failure direction is dispatch-instead-of-
  abort, which is correct here, but the number must not be used as a task count by a future caller.
  Stated in the script header.
- The guard gets weaker in one respect: a genuinely malformed plan that happens to contain the word
  "Task" in an H2 now passes. It was already weak — nothing marks tasks done, so it could never
  detect "all tasks complete" either.
- One real plan stays unrecognised (§D6). A plan written with `Step` headings and no checkbox would
  still be rejected by a message that says "the plan may be malformed", which is the exact failure
  mode this ADR exists to fix — narrowed from seven plans to one, not eliminated.

### Neutral

- `architect.md` and the architect dispatch in `concept-to-code/SKILL.md` are unchanged. This ADR
  moves the consumers to the contract that was already written for the writer.
- No manifest field, no schema bump, no state-machine change.
- Deployed `~/.claude` keeps the old behaviour until an explicit sync.

## References

- Issue #172 — the contract split, and its A/B framing
- Issue #174 / commit `4eef7a8` — the leading-dash defect that masked this one and had to land first
- Issue #184 — `diff-budget-check.sh`, the fourth parser, deferred here
- `docs/architecture/ADR-0048-102-requirement-ids-coverage.md` — `spec-coverage.sh`, origin of the
  canonical predicate, and the checker-versus-reporter contract restated at each call site
- `docs/architecture/ADR-0052-106-diff-budget-scope-check.md` — the reporter whose predicate is
  deferred
- `staging/plugin/agents/architect.md` Output Format — the writer contract, unchanged
