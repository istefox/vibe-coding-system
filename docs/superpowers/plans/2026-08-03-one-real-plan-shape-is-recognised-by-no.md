# Implementation plan — #290 plan-shape predicate: vacuity guard + corpus baseline

- **ADR:** `docs/architecture/ADR-0121-290-plan-shape-predicate.md`
- **SPEC:** `docs/specs/290-one-real-plan-shape-is-recognised-by-no.spec.md`
- **Requirements:** R-01, R-02

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield

---

## Environment notes (read first)

**No predicate byte changes.** `plan-task-predicate.awk` is NOT widened — ADR-0121 §D1 measured both
halves and rejected both. If you find yourself editing `is_task_line()` or `is_task_opener()`, stop:
that is the decision this plan exists to record, not to implement.

**These assertions are green on the day they are written.** `PTE4`, `PTJ1` and `BOV1` assert today's
true state, so there is no pre-fix red for them. Their evidence is the declared plant (Task 5), per
ADR-0108. Do not "fix" the harness to make them fail first. `PTH0`–`PTH2` *are* red until Task 2
lands the baseline, and that ordering is deliberate (ADR-0101: an assertion must not share a batch
with the task that greens it).

**Measured numbers to verify against** (re-derive; do not trust this table if it disagrees with the
tree):

| | |
| --- | --- |
| Corpus size | 61 plans |
| `--count` = 0 | 1 plan: `2026-06-06-claude-md-slim.md` |
| `--count-openers` = 0 | 2 plans: the above + `2026-05-30-deep-refactor-skill.md` (36 lines, 0 openers) |
| `--count` ≠ `--count-openers` | 52 of 61, all over-counts, all `>= 6` |
| Current assertion totals | `plan-task-count` 44 passed; `batch-dispatch-openers` 16 passed |

**Plant contract** (`staging/plugin/scripts/tests/plant-check.sh` header — read it before writing
one): declaration at **column 1**, exactly one match required, no ` | ` inside any field, **no
newline in a replacement**. Paths are staging-relative. The needle's words are `re.escape`d and
joined on `\s+`, so regex metacharacters in a needle are safe and a wrapped clause still matches. A
plant may target the file that declares it — declaration lines are masked before matching.

**ASSERTION-ID SAFETY — this constrains every id below.** `plant-check.sh` decides a plant fired
with `grep -q "^FAIL: $aid"`, a **prefix** match. An id that is a prefix of another id in the same
file can therefore have its plant satisfied by the *wrong* assertion failing. Measured across the
registry: **41 of 148 declared plants already sit on such a collision** (`SP5`/`SP5b`,
`TC1`/`TC10`, `G1`/`G1b`, …). That is a pre-existing defect of the registry, **out of scope here**
and disclosed as a follow-up — but this feature must not add to it. Every id below was checked in
**both** directions against the ids already in its file:

| id | file | status |
| --- | --- | --- |
| `PTE4`, `PTH0`, `PTH1`, `PTH2`, `PTJ1` | `plan-task-count.test.sh` | safe |
| `BOV1` | `batch-dispatch-openers.test.sh` | safe |

`PTG11` and `BO5c` were the obvious sequential names and **both are unsafe**: `PTG1` is a prefix of
`PTG11`, `BO5` is a prefix of `BO5c`. Do not tidy the ids back to the sequential form.

**Bash 3.2 / POSIX awk only.** No `mapfile`, no `<<<`, no process substitution, no assoc arrays.
`grep -c … || echo 0` yields the two-line string `0\n0` — use `|| true`.

## Observable-contract note

Nothing observable moves: no predicate change, no script interface change, no exit-code change.
Grepped call-sites, for the record — `is_task_line`: `spec-coverage.sh:256`, `plan-tasks.sh`;
`is_task_opener`: `diff-budget-check.sh:191`, `plan-tasks.sh`; `plan-tasks.sh` itself:
`concept-to-code/SKILL.md` (Step 5 pre-dispatch, twice) and `autopilot-build/SKILL.md` check 5.
**No call-site updates are required.** Run the **full** suite anyway at Task 7, not just the two
files touched — the predicate is shared, and a shared file is where an unrelated harness breaks.

---

## Tasks

### Task 1 — RED: baseline assertions PTH0/PTH1/PTH2 (R-02)

Add a `PTH` section to `staging/plugin/scripts/tests/plan-task-count.test.sh`, after the existing
`PTG` corpus block and before `Z1`.

- Define `BASELINE="$STAGING/plugin/scripts/tests/plan-shape-baseline.tsv"`.
- `PTH0` — denominator guard. The baseline file resolves AND holds `>= 55` rows. A baseline that
  has stopped resolving discovers nothing and reads exactly like full agreement (ADR-0085). On
  failure, `bad` and **skip** `PTH1`/`PTH2` rather than letting them pass vacuously.
- `PTH1` — stale-entry guard. Every basename in the baseline still exists under
  `docs/superpowers/plans/`. Report the missing ones by name.
- `PTH2` — the comparison. For every baseline row **whose file exists**, recompute both counts and
  require exact agreement. Report each disagreement as `<plan>: lines A->B openers C->D`. Rows whose
  file is missing are `PTH1`'s business, not this one's — keeping them out is what makes Task 5's
  plants isolate one assertion each (ADR-0104).
- Recompute with a single awk pass loading the shared predicate, never a reimplementation
  (ADR-0069 §D2). Write the counter program into `"$TMP"` as the file already does for `openct.awk`.

Declare the three plants at column 1 in the file's plant block:

```
# plant: PTH0 | plugin/scripts/tests/plan-task-count.test.sh | BASELINE="$STAGING/plugin/scripts/tests/plan-shape-baseline.tsv" | BASELINE="$STAGING/plugin/scripts/tests/no-such-baseline.tsv"
# plant: PTH1 | plugin/scripts/tests/plan-shape-baseline.tsv | 2026-05-30-deep-refactor-skill.md 36 0 | 2026-05-30-deleted-plan.md 36 0
# plant: PTH2 | plugin/scripts/tests/plan-shape-baseline.tsv | 2026-07-30-222-vendor-deployed-only-skills.md 38 7 | 2026-07-30-222-vendor-deployed-only-skills.md 38 9
```

**Checkpoint:** run the file. `PTH0` must fail (no baseline yet) and `PTH1`/`PTH2` must be skipped,
not passing. Everything else stays green.

- Budget: `staging/plugin/scripts/tests/plan-task-count.test.sh` (~55 lines)

### Task 2 — GREEN: generate the corpus baseline (R-02)

Create `staging/plugin/scripts/tests/plan-shape-baseline.tsv`, one row per plan:
`<basename>\t<is_task_line count>\t<is_task_opener count>`, sorted by basename.

Generate it — do not hand-write it:

```sh
cat > /tmp/gen.awk <<'EOF'
FNR==1 { if (NR>1) emit(); f=FILENAME; L=0; O=0 }
{ if (is_task_line($0)) L++; if (is_task_opener($0)) O++ }
END { emit() }
function emit(  n,p,b) { n=split(f,p,"/"); b=p[n]; printf "%s\t%d\t%d\n", b, L, O }
EOF
awk -f staging/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk \
    -f /tmp/gen.awk docs/superpowers/plans/*.md | sort > \
    staging/plugin/scripts/tests/plan-shape-baseline.tsv
```

Verify the generator before trusting it — an awk measurement that silently reads nothing is this
repository's signature failure (ADR-0100). Required spot checks:

- exactly **61** rows;
- `2026-06-06-claude-md-slim.md` → `0  0`;
- `2026-05-30-deep-refactor-skill.md` → `36  0`;
- `2026-07-30-222-vendor-deployed-only-skills.md` → `38  7`.

If any differs, the generator is wrong, not the corpus. (Known limit worth a comment in the file: a
zero-byte plan never triggers `FNR==1` and would be skipped — the row-count check is what catches
it.)

Add a header comment to the `PTH` block recording the regeneration command and stating that a
**deliberate** predicate change regenerates this file and the diff is the review evidence
(ADR-0121 §D3).

**Checkpoint:** `PTH0`/`PTH1`/`PTH2` green; file total 47 passed.

- Budget: `staging/plugin/scripts/tests/plan-shape-baseline.tsv`, `staging/plugin/scripts/tests/plan-task-count.test.sh` (~75 lines)

### Task 3 — Vacuity assertions PTE4 and PTJ1 (R-01)

In `staging/plugin/scripts/tests/plan-task-count.test.sh`:

- `PTE4`, beside `PTE3` inside the same `else` branch: `plan-tasks.sh --count "$PLANS_DIR/$PTE_KNOWN"`
  still returns `0`. The failure message must say the exemption now covers nothing and must be
  **deleted**, naming `PTE2`.
- `PTJ1`, beside `PTG10`: every basename in `$TMP/ptg-known` still yields `0` from
  `--count-openers`. Report which one stopped needing its exemption. (Named `PTJ1`, not `PTG11` —
  see ASSERTION-ID SAFETY above.)

Keep `PTE3` and `PTG10` unchanged. "The file is gone" and "the file no longer needs exempting" are
different failures with different remedies (ADR-0121 §D2); do not merge them.

Branch on the **exit code** as well as the printed number — `plan-tasks.sh` is a checker and exit 3
means it did not run, which must not be read as "returned 0".

Plants:

```
# plant: PTE4 | plugin/skills/concept-to-code/scripts/plan-task-predicate.awk | return (lvl >= 2 && lvl <= 4) && (l ~ /Task/) | return (lvl >= 2 && lvl <= 4) && (l ~ /Task|Step/)
# plant: PTJ1 | plugin/skills/concept-to-code/scripts/plan-task-predicate.awk | return rest ~ /^[Tt]ask[ \t]+[0-9]+/ | return rest ~ /^([Tt]ask|[Ss]tep)[ \t]+[0-9]+|^T[0-9]+[ \t]/
```

- Budget: `staging/plugin/scripts/tests/plan-task-count.test.sh` (~35 lines)

### Task 4 — Vacuity assertion BOV1 (R-01)

In `staging/plugin/scripts/tests/batch-dispatch-openers.test.sh`, beside `BO5b`: assert
`2026-05-30-deep-refactor-skill.md` still yields `0` openers, so `BO5`/`BO7`'s zero-opener branch
still has a real subject. Note in the comment that `BO5` already asserts the population is
non-empty; `BOV1` is the per-name half, which is what goes stale silently. (Named `BOV1`, not
`BO5c` — see ASSERTION-ID SAFETY above.)

```
# plant: BOV1 | plugin/skills/concept-to-code/scripts/plan-task-predicate.awk | return rest ~ /^[Tt]ask[ \t]+[0-9]+/ | return rest ~ /^([Tt]ask|[Ss]tep)[ \t]+[0-9]+|^T[0-9]+[ \t]/
```

`BO1` in this same file already declares that needle with a different replacement; that is fine,
each plant runs against its own copy. Confirm both still fire in Task 5.

- Budget: `staging/plugin/scripts/tests/batch-dispatch-openers.test.sh` (~20 lines)

### Task 5 — Run the plant registry; every new plant must fire (R-01, R-02)

`bash staging/plugin/scripts/tests/plant-check.sh`.

All six new plants (`PTH0`, `PTH1`, `PTH2`, `PTE4`, `PTJ1`, `BOV1`) must be collected and must fire.
For each, **inspect what the plant actually produced** before believing the result (ADR-0090) —
confirm the mutation landed where intended and that the named assertion is the one that reddened.

If a plant does not fire, the defect is in the assertion or in the needle, not a formality:
- zero matches → the needle rotted;
- more than one match → it hits sites it did not intend;
- fires but the wrong assertion reddens → the assertion is covered by two guards and isolates
  neither (ADR-0104); split the fixture.

Two specific confirmations:
- `PTH1`'s plant must redden `PTH1` **only**. If it also reddens `PTH2`, the missing-file row is
  leaking into the comparison and `PTH2` needs its existence filter fixed.
- Re-run the both-directions id check before finishing, so no new id has become a prefix of another
  in the same file:
  ```sh
  for f in plan-task-count batch-dispatch-openers; do
    F=staging/plugin/scripts/tests/$f.test.sh
    grep -oE '(ok|bad) "[A-Za-z][A-Za-z0-9]*' "$F" | sed -E 's/^(ok|bad) "//' | sort -u > /tmp/ids.$f
    awk 'NR==FNR{a[$0];next}{for(i in a) if(i!=$0 && index(i,$0)==1) print "COLLISION: "$0" is a prefix of "i}' /tmp/ids.$f /tmp/ids.$f
  done
  ```
  Any line naming one of the six new ids must be resolved by renaming the **new** id.

- Budget: no files expected; corrective edits to the two test files if a plant misfires (~20 lines)

### Task 6 — Correct the stale counts and the conflated population (R-01)

Living instruction files only. **Grep for extraction anchors before editing any of them** —
`workflow-dispatch-pins.test.sh`, `path-rule-check.sh`, `fence-contract-coverage.test.sh` and the
`PTC`/`PTF` extractors in `plan-task-count.test.sh` all anchor on strings in these files. Do not
reword a heading or a marker; change only the prose numbers and the population claim.

1. `staging/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk` — "over the 57 plans …
   matches all 57" → 61 plans, 60 match (`claude-md-slim` yields 0). That claim contradicted the
   same file's `is_task_opener` header and ADR-0069's own `PTE2` exemption; say so in one clause.
   The `is_task_opener` header's "57 plans: 55 match" → 61 plans, 59 match.
2. `staging/plugin/skills/concept-to-code/scripts/plan-tasks.sh` — "58 plans … differ on 51" → 61
   and 52 (`#222`'s 38/7 is still correct — leave it). Correct the conflated line naming
   ``### T1 —`` and ``### Step 0 —`` as if they were two files: they are **two files** —
   `deep-refactor-skill.md` (`### T1 —`) and `claude-md-slim.md` (`### Step N —`, whose first
   heading happens to be `### Step 0 —`).
3. `staging/plugin/scripts/tests/batch-dispatch-openers.test.sh` header — "58 plans … diverge on
   51 … all 51" → 61, 52, all 52. Same population clarification.
4. `staging/plugin/scripts/tests/plan-task-count.test.sh` — the `PTG` corpus comment says "the same
   two named exemptions plus one more" above a list of exactly two entries. Correct to two, and name
   which shape each file uses.
5. `staging/plugin/skills/concept-to-code/SKILL.md` — the Step 5 line citing ADR-0070 §PTG9 and
   ADR-0069 §PTE2: make it say two plans, not two shapes implying three.

**Checkpoint:** full suite green. If an extraction-anchored test reddens, you reworded an anchor —
revert that edit rather than re-anchoring the test.

- Budget: `plan-task-predicate.awk`, `plan-tasks.sh`, `batch-dispatch-openers.test.sh`, `plan-task-count.test.sh`, `concept-to-code/SKILL.md` (~60 lines)

### Task 7 — Raise the Z1 floors and run the full suite (R-01, R-02)

- `plan-task-count.test.sh`: floor `43` → `48` (expected total 49).
- `batch-dispatch-openers.test.sh`: floor `13` → `16` (expected total 17).

A floor that no longer tracks its population has stopped measuring (ADR-0097 `RH2`). Set each just
below the new actual, not equal to it.

Then run the **whole** harness plus the plant registry:

```sh
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done
bash staging/plugin/scripts/tests/plant-check.sh
```

Both must be green. A shared predicate is exactly where an unrelated harness breaks, so a green
`plan-task-count` alone is not evidence.

- Budget: `staging/plugin/scripts/tests/plan-task-count.test.sh`, `staging/plugin/scripts/tests/batch-dispatch-openers.test.sh` (~10 lines)

### Task 8 — Record the corrections (R-01, R-02)

1. Append a dated `## Correction (2026-08-03, ADR-0121)` to each of
   `docs/architecture/ADR-0069-172-plan-task-form.md`,
   `docs/architecture/ADR-0070-184-diff-budget-task-predicate.md`,
   `docs/architecture/ADR-0100-242-batch-dispatch-openers.md`.
   **Bodies unedited** (ADR-0034 precedent). Each states today's corpus number and, for ADR-0100,
   that **one** plan — not two — has `openers = 0` with a non-zero `--count`.
2. `CLAUDE.md`: add the ADR-0121 decisions section following the file's existing format, and correct
   the ADR-0100 summary's "Two corpus plans have `openers = 0` with a non-zero `--count`" to one.
   That summary is the source of the drift this issue inherited (the ADR-0092 shape — an error
   entering through a summary and spreading from it), so correcting it at source matters more than
   the ADR footnotes.
3. In the same `CLAUDE.md` section, record the **disclosed, unfixed** registry defect: the
   `^FAIL: $aid` prefix match, 41 of 148 plants affected, and that new assertion ids must be checked
   in both directions until it is fixed.

- Budget: three ADR files, `CLAUDE.md` (~75 lines)

---

## Definition of done

- [ ] R-01 — every unrecognised plan is exempted by name AND paired with both an existence assertion
      (`PTE3`/`PTG10`/`BO5b`) and a vacuity assertion (`PTE4`/`PTJ1`/`BOV1`).
- [ ] R-02 — `plan-shape-baseline.tsv` exists with 61 verified rows and `PTH0`/`PTH1`/`PTH2` compare
      both predicates over the whole corpus, failing per plan on any change.
- [ ] All six new plants collected by `plant-check.sh` and seen firing, each reddening its own
      assertion; no new id is a prefix of another id in its file.
- [ ] Full `*.test.sh` suite green; `plant-check.sh` green.
- [ ] `plan-task-predicate.awk`'s two predicate functions are byte-identical to their pre-task state
      (`git diff` shows only comment lines changed in that file).
