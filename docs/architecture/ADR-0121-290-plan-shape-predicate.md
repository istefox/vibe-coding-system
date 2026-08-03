# ADR-0121 — the plan-shape exemptions are live but vacuity-blind; no widening

- **Issue:** #290 — "one real plan shape is recognised by no task predicate"
- **Status:** Accepted
- **Date:** 2026-08-03
- **Supersedes / amends:** nothing. Corrects three stale claims in ADR-0069, ADR-0070 and ADR-0100
  by dated `## Correction` (bodies unedited, ADR-0034 precedent).

---

## Context

`plan-task-predicate.awk` is the one place that decides what a plan task looks like (ADR-0069 §D2).
It holds two predicates answering two different questions:

- `is_task_line()` — "is there a task here", the `>= 1` malformed-plan guard, deliberately loose.
  Consumed by `plan-tasks.sh --count` and by `spec-coverage.sh` for **requirement-token extraction**.
- `is_task_opener()` — "does a task BLOCK START here", the attribution boundary. Consumed by
  `plan-tasks.sh --count-openers` and by `diff-budget-check.sh`.

Issue #290 asserts that `2026-06-06-claude-md-slim.md` writes `### Step N — …` and is exempted by
name in `PTE2`, and that **"ADR-0100 §PTG9 records two further plans using `### T1 —` and
`### Step 0 —` that match no predicate at all."** It asks for the corpus to be re-derived rather
than inherited, for every unrecognised plan to be exempted by name with a companion existence
assertion, and for any widening to prove it does not change token extraction.

### The measurement

Corpus: **61** plans in `docs/superpowers/plans/` (the SPEC says 58; `plan-task-predicate.awk`'s
header says 57; `plan-tasks.sh`'s header says 58). Both predicates run over every plan via
`awk -f plan-task-predicate.awk -f <counter> docs/superpowers/plans/*.md`, one process, per-file
totals keyed on `FILENAME`.

| Question | Measured |
| --- | --- |
| Plans in the corpus | 61 |
| Unrecognised by `is_task_line` (`--count` = 0) | **1** — `2026-06-06-claude-md-slim.md` |
| Unrecognised by `is_task_opener` (`--count-openers` = 0) | **2** — the above, plus `2026-05-30-deep-refactor-skill.md` (36 lines, 0 openers) |
| Match **neither** predicate | **1** — `2026-06-06-claude-md-slim.md` |
| `--count` ≠ `--count-openers` | 52 of 61 (ADR-0100 measured 51 of 58) |
| Divergences that are under-counts | **0** — every divergence is an over-count, as documented |

**The issue's central premise does not reproduce, three ways at once.** `### Step 0 —` is not a
further plan: it is the *first heading inside* `2026-06-06-claude-md-slim.md`, the file `PTE2`
already exempts, whose headings run `### Step 0` through `### Step 7`. There is exactly **one**
further plan, `2026-05-30-deep-refactor-skill.md`, and it does **not** "match no predicate at all"
— `is_task_line` matches it 36 times. So the population is one plan matching neither predicate and
one more matching only the loose one, not three plans and not two further ones.

Confirmed by `grep -ln '^### Step 0' docs/superpowers/plans/` → one file, `claude-md-slim`; and
`grep -ln '^### T[0-9]'` → one file, `deep-refactor-skill`.

### What R-01 already has

`PTE2` exempts `claude-md-slim` by name with `PTE3` asserting the file still exists. `PTG9` exempts
both plans from a two-entry list with `PTG10` asserting both still exist. `BO5b` asserts
`deep-refactor-skill.md` exists. Both harnesses are green (`plan-task-count` 44 passed,
`batch-dispatch-openers` 16 passed). **R-01's literal text is satisfied today.**

### The gap that is real

`PTE3` and `PTG10` assert that the exempted **file exists**. The subject of the exemption is not the
file — it is *the file being unrecognised*. Reading the code settles it:

- `PTE2` computes `pte_unexpected=$(grep -vxF "$PTE_KNOWN" "$TMP/pte-zero.txt" | grep -c .)`. When
  `pte-zero.txt` is **empty** — every plan recognised, exemption needed by nobody — that is `0`, and
  `PTE2` passes.
- `PTE3` is `[ -f "$PLANS_DIR/$PTE_KNOWN" ]`, which passes for any content whatsoever.

So if `claude-md-slim` were reworded to `### Task N —`, or a predicate widened to absorb it, the
exemption would protect nothing and **both assertions would stay green**. Same shape for `PTG10`
and `BO5b`. This is the stale-waiver direction that ADR-0081 `ZA4`, ADR-0082 `U2` and ADR-0084 `S7`
each run in their own populations, and that the SPEC's own edge-case bullet asks for by citing
`ZA4` — and does not get, because "the file exists" is a weaker claim than "the exemption still has
work to do".

### R-02 has no instrument

R-02 asks that a widening prove it does not change token extraction, "by comparing both predicates
over the whole corpus before and after". Nothing records the *before*. Today that comparison is a
hand re-derivation, which is exactly how ADR-0069's, ADR-0070's and ADR-0100's numbers drifted.

---

## Decision

### D1 — No widening. Both halves measured, both rejected.

The widening was split and each half measured independently against the 61-plan corpus.

**Half B — widen `is_task_opener` to accept `Step N` / `T<digits>`: refused, decisively.**
Changes **22 of 61** plans, of which **20 are collateral damage on plans that already work**.

```
2026-05-18-vibe-coding-system.md      openers  26 -> 87
2026-05-19-agentic-swarm-phase-a.md   openers  11 -> 67
2026-05-19-swarm-testcmd.md           openers   9 -> 53
2026-05-17-agents-improvement.md      openers  10 -> 32
… 16 more
2026-05-30-deep-refactor-skill.md     openers   0 -> 8   (intended, and correct: T1..T8)
2026-06-06-claude-md-slim.md          openers   0 -> 8   (intended, and correct: Step 0..7)
```

The cause, found by dumping the newly-matching lines rather than trusting the totals: **those plans
use `- [ ] **Step 1: …` as SUB-STEPS INSIDE a task.** `2026-05-17-agents-improvement.md` reads
`### Task 1: architect.md` followed by `- [ ] **Step 1: Scrivi il file**`, `- [ ] **Step 2:
Valida**`. Widening the opener to accept `Step N` turns every sub-step into a task-block boundary,
so the opener count rises to equal the *line* count. That is not noise — it is the precise failure
`is_task_opener` was created to prevent, stated in its own header: a sub-step "would close task 1's
block early and attribute its budget to task 2". The widening inverts the predicate's purpose on 20
plans to correct 2.

**Half A — widen `is_task_line`'s heading test from `/Task/` to `/Task|Step/`: refused, on a
subtler ground.** Changes only **2 of 61** plans (`claude-md-slim` lines 0 → 9, the intended fix;
`2026-05-19-review-triage-fix.md` 41 → 47, collateral). Openers unchanged. Over-counting is
documented as safe for a `>= 1` guard, so on the guard axis this half is nearly free.

It is refused because `is_task_line` is **also** what `spec-coverage.sh` feeds to `extract_tokens`
— the ADR-0048 requirement-coverage gate. Measured: Half A sends **15 new lines** into token
extraction, and **0 of them carry an `R-NN` token today**. The cost is therefore not zero, it is
**latent**: today's safety is an accidental property of which lines happen to exist, the same class
of accidental-property reasoning ADR-0110 refused to rely on. And the new lines are the wrong kind
of content — six of them are `## Step 0 — Pre-flight` … `## Step 5 — Recap` in
`2026-05-19-review-triage-fix.md`, which are steps of the *skill being specified*, not tasks of the
plan. A future plan describing a pipeline whose Step 3 mentions `R-04` would be scored as covering
`R-04`. Trading a latent false-covered channel in a merge-blocking gate for the recognition of one
completed historical plan that will never be dispatched again is a bad trade.

ADR-0069 §D6 refused `Task|Step` once, on the ground that it changes token extraction for every
plan to accommodate one completed plan. That reasoning survives re-measurement; this ADR records
the numbers it was asserted without.

### D2 — Exemptions gain a vacuity assertion: the named plan must still be unrecognised.

Three new assertions, each the reverse direction of an existing existence check:

- `PTE4` — `plan-tasks.sh --count` on the `PTE2`-exempt plan still returns `0`.
- `PTJ1` — `--count-openers` on each of `PTG9`'s two named plans still returns `0`.
- `BOV1` — `--count-openers` on `BO5b`'s named plan still returns `0`.

An exemption that stops being needed must be **deleted**, not left as a green waiver. `PTE3`,
`PTG10` and `BO5b` are kept unchanged beside them: "the file is gone" and "the file no longer needs
exempting" are different failures wanting different messages, and collapsing them would tell a
reader the plan was deleted when it was merely reworded.

The ids are `PTJ1` and `BOV1` rather than the sequential `PTG11` and `BO5c` for the reason in §D5.

### D3 — A frozen corpus baseline is the R-02 instrument.

`staging/plugin/scripts/tests/plan-shape-baseline.tsv`, one row per plan at baseline time:
`<basename>\t<is_task_line count>\t<is_task_opener count>`. Three assertions consume it: a
denominator guard (`PTH0`), a stale-entry guard (`PTH1`), and the comparison itself (`PTH2`).

This makes R-02 mechanical. Any edit to either predicate is run against the baseline and fails
naming exactly which plans moved and by how much — the "before/after comparison over the whole
corpus" R-02 asks for, executed rather than re-derived. A **deliberate** widening updates the
baseline in one regeneration step, and the resulting diff is the evidence that widening was
reviewed rather than assumed.

**It lives under `tests/`, deliberately.** That directory is outside `pairs-completeness.test.sh`'s
non-recursive `plugin/scripts/*.sh` population and the file is not a `.test.sh`, so it needs no
`PAIRS` entry, no `docs-ci.yml` edit and no `.claude/test-cmd` change — and therefore carries **no
"inert until sync" dependency**, the class that has bitten six recent ADRs. Same placement
reasoning as ADR-0117's `path-rule-check.sh`.

**No third mode on `plan-tasks.sh`.** Its two modes already have opposite failure directions with a
header warning that a caller must pick the right one and say which at the call site. Adding a third,
used only by a test, widens a documented hazard for no runtime benefit. The generator is a
documented awk one-liner in the test header instead.

### D4 — Stale counts and the conflated claim are corrected in the living files only.

`plan-task-predicate.awk`, `plan-tasks.sh`, `batch-dispatch-openers.test.sh`,
`plan-task-count.test.sh` and `concept-to-code/SKILL.md` are instructions someone reads while
working; they get today's numbers and the corrected population. ADR-0069, ADR-0070 and ADR-0100 get
a dated `## Correction` with their bodies unedited (ADR-0034 precedent) — a historical ADR records
its moment.

Two internal contradictions are corrected in passing, both found by reading rather than by any test:
`plan-task-predicate.awk`'s header claims "this predicate matches all 57" while the same file's
`is_task_opener` header, and ADR-0069's own `PTE2` exemption, record that it matches `claude-md-slim`
zero times; and `plan-task-count.test.sh`'s corpus comment says "the same two named exemptions plus
one more" above a list holding exactly two entries.

`CLAUDE.md`'s ADR-0100 summary states "Two corpus plans have `openers = 0` with a non-zero
`--count`". Measured: **one** does (`deep-refactor`, 36/0); `claude-md-slim` has `--count` 0 too.
This is the ADR-0092 drift shape — an error entering through a summary and spreading from it — so
the summary is corrected at source.

### D5 — New assertion ids are checked for prefix collision; the registry defect is disclosed, not fixed.

`plant-check.sh` decides a plant fired with `grep -q "^FAIL: $aid"` — a **prefix** match. An id that
is a prefix of another id in the same file can therefore have its plant satisfied by the **wrong**
assertion failing, which is a plant reading as fired while the assertion it names pins nothing: the
registry's own failure mode, and the fourth boundary found in it after `PC4`'s column anchoring
(ADR-0115), the `../docs/` target hatch (ADR-0116) and the self-targeting declaration mask.

Measured across the whole registry: **41 of 148 declared plants** already sit on such a collision —
`SP5`/`SP5b`/`SP5c`/`SP5d`, `TC1`/`TC10`–`TC13`, `G1`/`G1b`/`G10`/`G11`, `MES2`/`MES2b`,
`PM2`/`PM2b`, `RB1`/`RB10`, and more. Whether any is an *active* false positive depends on whether
each plant's mutation reddens the colliding assertion without reddening the named one, which is a
per-plant measurement.

**Not fixed here, and the reason is blast radius, not effort.** Anchoring the match on a word
boundary would re-verify all 148 plants at once, and its most likely outcome is discovering that
some currently-"firing" plant only ever fired through a prefix match — a finding that deserves its
own issue, its own measurement and its own red evidence, exactly as ADR-0047 §A2 and ADR-0107
argued for changes at this layer. Bundling it into a plan-predicate feature would put two unrelated
red populations in one review.

What this feature does instead is **not add to it**: the six new ids were checked in both directions
against the ids already in their file, which is what moved `PTG11` → `PTJ1` and `BO5c` → `BOV1`.
Both sequential names were unsafe (`PTG1` is a prefix of `PTG11`; `BO5` is a prefix of `BO5c`).

---

## Alternatives considered

**A. Widen both predicates to absorb `Step N` and `T<digits>` (the issue's implied fix).**
Rejected on measurement: 22 of 61 plans change and 20 of those are correct plans being corrupted,
because sub-step checkboxes reading `- [ ] **Step 1: …` become task-block boundaries. Opener counts
rise to equal line counts on 18 plans. This inverts the stated purpose of `is_task_opener`.

**B. Widen only `is_task_line` (Half A), leaving `is_task_opener` alone.**
Genuinely tempting — 2 plans change, over-counting is documented safe for the guard, and it removes
the `--count = 0` abort risk for the one plan that has it. Rejected because `is_task_line` also
drives `spec-coverage.sh`'s token extraction: 15 new lines enter the ADR-0048 coverage gate, none
carrying an `R-NN` today, which makes the cost latent rather than absent. The beneficiary is a
completed historical plan that will never be dispatched; the cost lands on every future plan
describing a pipeline with numbered steps.

**C. Rewrite the two unrecognised plans into the `### Task N` form.**
Rejected: the SPEC puts it out of scope, and correctly — `docs/superpowers/plans/` is a historical
record. Editing a completed plan to satisfy a present-day parser falsifies the record for no
consumer, the rule ADR-0075 and ADR-0078 both applied to manifests.

**D. Strengthen `PTE3`/`PTG10` in place rather than adding `PTE4`/`PTJ1`.**
Rejected: "the exempted file is gone" and "the exempted file no longer needs its exemption" are
different defects with different remedies (prune the list vs. prune the list *and* check what
changed). One assertion reporting both would name the wrong cause half the time, the failure
ADR-0104 recorded as "an assertion covered by two guards isolates neither".

**E. Compute the baseline on the fly from the previous git revision instead of committing a file.**
Rejected: it makes the harness depend on git history and on being run inside a repository with the
parent revision present, and it silently compares against whatever the last commit happened to
contain rather than against a reviewed record. A committed baseline is reviewable in a diff, which
is the point.

**F. Add a `--emit-baseline` mode to `plan-tasks.sh`.**
Rejected: that script's two modes have opposite failure directions and a header warning that a
caller must pick the right one and say which at the call site. Adding a third mode, used only by a
test, widens a documented hazard for no runtime benefit.

**G. Fix `plant-check.sh`'s prefix match in this feature.**
Rejected as scope, not as a judgement on the defect — see §D5. It re-verifies 148 plants at once and
its likely outcome is a second, unrelated red population inside a plan-predicate review.

---

## Consequences

**Positive.**
- An exemption can no longer outlive its usefulness silently: a reworded plan, or a predicate change
  that absorbs one, now fails naming the plan and the exemption to delete.
- R-02 becomes a command rather than an exercise. The blast radius of any predicate edit is reported
  per plan, which is what would have caught the drift in ADR-0069's, ADR-0070's and ADR-0100's
  numbers.
- The widening question is settled with numbers rather than by inheritance, so the next author does
  not have to re-run this to know what `Task|Step` costs.
- Six living files stop stating counts that are two corpus generations old.
- No deployed script changes, so nothing is inert until sync, and no `PAIRS` or CI list needs an
  entry — the two lists that have silently drifted before.
- A registry-wide defect is now on record with a number attached, found because this feature had to
  choose two assertion ids.

**Negative.**
- The baseline is a 61-row data file that a deliberate predicate change must regenerate. Forgetting
  to regenerate presents as a failing harness naming the changed plans, which is the intended
  behaviour but will read as a regression the first time.
- The baseline covers the corpus as of 2026-08-03. Plans added later are outside it and are neither
  compared nor reported by `PTH2`; coverage decays slowly unless someone regenerates. `PTH0`'s count
  guard catches a baseline that has stopped resolving, not one that has merely aged.
- `PTE4`/`PTJ1`/`BOV1` pass on the day they are written by construction — they assert today's state.
  Their evidence is the declared plant, not a pre-fix red, and a reader expecting a red harness will
  not find one.
- The exemption population is still identified by filename, so it does not travel on rename
  (ADR-0069 §PTD's objection). Accepted on the SPEC's own terms, now paired with two assertions
  rather than one.
- **41 of 148 plants remain on a prefix collision.** This feature does not add to it and does not
  reduce it. Anyone reading a green `plant-check.sh` as "every plant pins its own assertion" is
  reading something that is not currently true.
- The id-safety rule is prose plus a one-off check in the plan; nothing enforces it on the next
  assertion anyone writes.

**Neutral.**
- No predicate byte changes, so `spec-coverage.sh`, `diff-budget-check.sh`, `concept-to-code`
  Step 5 and `autopilot-build` check 5 are behaviourally untouched. Verified by grep: the only
  consumers of `is_task_line` are `spec-coverage.sh:256` and `plan-tasks.sh`; of `is_task_opener`,
  `diff-budget-check.sh:191` and `plan-tasks.sh`. No call-site updates are required, because no
  observable contract moves.
- ADR-0100's "51 of 58 diverge" becomes 52 of 61 — the property it asserted (every divergence is an
  over-count, all `>= 6`) still holds, so its conclusion is unaffected.
- Two `Z1` assertion floors rise, the routine cost of adding assertions.

---

## References

- Issue #290; `docs/specs/290-one-real-plan-shape-is-recognised-by-no.spec.md`
- `docs/architecture/ADR-0069-172-plan-task-form.md` — §D1/§D2 the shared predicate, §D6 the refused
  widening, §PTE2 the first exemption, §PTD the identity-waiver objection
- `docs/architecture/ADR-0070-184-diff-budget-task-predicate.md` — §D3 `is_task_opener`, §PTG9
- `docs/architecture/ADR-0100-242-batch-dispatch-openers.md` — the divergence measurement
- `docs/architecture/ADR-0048-102-requirement-ids-coverage.md` — the coverage gate Half A would feed
- `docs/architecture/ADR-0081-213-212-false-green-and-zone-anomalies.md` — `ZA4`, the stale-waiver
  direction
- `docs/architecture/ADR-0086-derived-guard-pattern-not-extracted.md` — why the two exemption lists
  stay separate
- `docs/architecture/ADR-0108-284-plant-registry.md` — the plant contract
- `docs/architecture/ADR-0115-329-gate0-autopilot-default.md` — `PC4`, the first registry boundary
- `docs/architecture/ADR-0116-339-permission-posture-overpromise.md` — the `../docs/` target hatch
- `docs/architecture/ADR-0117-286-path-rule-bare-mentions.md` — the `tests/`-placement precedent

### SPEC deviations recorded

- The SPEC places `PTG9`/`PTG10` in `staging/plugin/scripts/tests/diff-budget-scope.test.sh`. They
  are in `staging/plugin/scripts/tests/plan-task-count.test.sh`; `diff-budget-scope.test.sh`
  contains neither identifier.
- The SPEC states the corpus is 58 plans. It is 61.
- The SPEC's "The unrecognised shapes are `### Step N —`, `### Step 0 —`, and `### T1 —`" describes
  three shapes across two files, and the first two are the same file's heading run.
