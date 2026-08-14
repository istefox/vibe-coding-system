# ADR-0138 — spec-coverage's test axis is tightened by SCOPE, not by assertion shape (issue #312)

- **Date:** 2026-08-14
- **Issue:** #312 — "spec-coverage measures citation not implementation"
- **SPEC:** `docs/specs/312-spec-coverage-measures-citation-not-impl.spec.md` (R-01, R-02, R-03)
- **Supersedes:** nothing. **Amends:** ADR-0048 §D3 (test discovery and the whole-file token match).

## Status

Accepted.

## Context

### What the issue assumed

Issue #312 and the SPEC written from it state the problem as *citation versus implementation*: an
`R-NN` id cited by a no-op plan task and mentioned in a comment inside a test file reads as fully
covered. SPEC objective 2 proposes the remedy directly — "the gate cannot verify that an
implementation is correct, but it may be able to verify that the citing test contains an assertion
rather than a comment."

SPEC objective 1 asks for a corpus measurement first, and objective 2 says the decision follows from
it. It does. It follows somewhere else entirely.

### The corpus, measured 2026-08-14

Re-derived from the files, not taken from the issue (CLAUDE.md rule 13). The SPEC's own snapshot
("36+" SPECs, "57+" plans, a "68-file" harness) is stale in every term.

| Population | Count |
|---|---|
| `docs/specs/*.spec.md` | 78 |
| … of those, declaring at least one `R-NN` id | 44 |
| … total ids declared across those 44 | 199 |
| … SPECs declaring zero ids (the silent no-IDs path) | 34 |
| `docs/superpowers/plans/*.md` | 71 |
| Test files discovered from the project root by `spec-coverage.sh`'s own basename predicate | 92 |
| … of those, under `staging/plugin/scripts/tests/` | 79 |
| `R-NN` mention lines across the discovered test population | 456 |
| Manifests with an `artifacts.spec` **and** `artifacts.plan` on disk | 49 |
| … with `artifacts.spec` pointing into `docs/specs/` rather than the mutable root slot | 13 |
| **(spec, plan) pairs derivable by issue-number prefix, both on disk, spec declaring ids** | **15** |
| **ids in that paired population** | **117** |

The paired population is 15 and not 44 because 29 id-declaring SPECs are backlog: their chain has
not run, so no plan exists. #312, #313, #314 and the rest of Phase 11 Wave 3 are in that 29.

**A denominator guard caught a contaminated first derivation** (CLAUDE.md rule 7, and it fired
during this measurement rather than after it). Pairing by manifest yielded 49 pairs and 196 ids — but
36 of those manifests predate ADR-0106 and still point `artifacts.spec` at the mutable root `SPEC.md`
slot, which today holds *this feature's* SPEC. Those 36 pairs were 108 copies of R-01/R-02/R-03
measured against 36 unrelated plans. Every number below is from the guarded population.

### Finding 1 — the test axis is not weak, it is 100% vacuous

`grep_boundary_test()` greps the **entire** discovered test population for the id. The id namespace
is per-SPEC and restarts at `R-01` for every feature. There are 27 distinct `R-NN` tokens present
somewhere in the 92 discovered test files, covering `R-01`…`R-20` contiguously. No SPEC in this
repository declares more than 19 ids.

> **All 199 declared ids in the corpus are satisfied by the global scan. Every one. The tests half
> of ADR-0048's coverage gate has never rejected an id and, given the id namespace, cannot.**

`R-01` for issue #312 is "covered" because `R-01` appears in `prep-row-select.test.sh`, which belongs
to issue #399. This is not citation-instead-of-implementation. It is *somebody else's* citation.

### Finding 2 — the proposed remedy is provably a no-op

Requiring the mention to sit on something other than a comment line, with the global scan kept:

| Rule | ids still covered, of 199 | newly failing |
|---|---|---|
| Today — global whole-file token match | 199 (100%) | 0 |
| Global + mention must be on a non-comment line | 199 (100%) | **0** |
| Global + mention must be on an `ok`/`bad` assertion-call line | 198 (99.5%) | **1** |

Of the 456 `R-NN` mention lines in the harness, 203 are comments, 138 are `ok`/`bad` calls, 115 are
other code. Every token `R-01`…`R-18` appears on an `ok`/`bad` call line *somewhere* in the
population. Implementing SPEC objective 2 as written changes the verdict of zero ids out of 199. The
single id it would flip — `R-19` of `176-worktree-isolation-contract.spec.md` — is a false negative,
not a catch.

### Finding 3 — the comment *is* the idiomatic citation site, so the rule is backwards

Scoped to each feature's own test files, of the 93 ids whose citation lands in the feature's own
tests, **49 (53%) have every one of their mentions on a comment line.**

The extreme case is the most recently shipped feature. `stop-gate-path-predicate.test.sh` (issue
#404, merged 2026-08-13, 25 passing assertions) contains 45 `R-NN` mention lines. **All 45 are
comments.** Zero are assertion lines. The harness convention here is a comment header that says which
requirement a block of assertions answers, followed by the assertions:

```
# TASK 4 CHECKPOINT (R-09, R-10) — SGP10-SGP14 ADDED, WRITTEN AGAINST THE SAME PRE-FIX
```

That comment is the requirement-to-assertion map. It is exactly where the citation belongs. A rule
that reads it as *not evidence* would fail 14 of #404's 14 requirements and 49 of the corpus's 93
in-scope-covered ids — a new false-negative class an order of magnitude larger than anything the
issue was trying to catch, and categorically forbidden by R-03.

### Finding 4 — scoping is non-vacuous, and it works

Restricting the test-side scan to the test files the **plan itself names**:

| Rule | ids covered, of 117 paired | newly failing |
|---|---|---|
| Today — global | 117 (100%) | 0 |
| **Plan-scoped whole-file token match** | **93 (79.5%)** | **24** |
| Plan-scoped + non-comment line | 44 (37.6%) | 73 |

All 15 plans name at least one discovered test file, so the derivation never collapses. Of the 24
ids that flip, hand-review at authoring time classifies **20 as true positives** — the feature's own
tests never cite that id — and **4 as requirements that are not test-assertable at all**:

- `222 R-10` — "the full harness passes, `sync-to-claude.sh --apply` is run, and …" (a process step)
- `394 R-11` — "The ADR records that the defect predates issue #385 …" (documentation)
- `404 R-14` — "the ceiling decision is recorded in an ADR …" (documentation)
- `410 R-17` — "The E4/H5 uncommitted-manifest gap is filed as its own issue" (external process)

Those four are the residual false-negative class. They are 3.4% of the corpus, and they are the
reason this ADR ships an exemption mechanism rather than just a tighter predicate.

### The premise change, stated plainly

CLAUDE.md rule 13 records that measuring changed the direction or the premise on seven of twelve
Phase 8 issues. It happened again here, and it inverted the design:

- The issue's diagnosis — a *comment-only mention* reads as covered — is true but is not the defect.
  The defect is that a mention in **any file in the repository** reads as covered.
- The issue's remedy — distinguish an assertion from a comment — is a no-op on the global scan and a
  catastrophe on the scoped one, because in this corpus the comment is where the citation is
  *supposed* to live.
- The tightening that works is **scope**: whose test file the mention is in. That is what the
  measurement supports, and it is what this ADR designs for.

R-01's literal words are therefore satisfied in objective and deviated from in mechanism. This is
disclosed here, in the plan, and at the call site — not buried.

## Decision

Five parts. The predicate stays LOADED where it is loaded today (ADR-0069, ADR-0072); nothing here
pastes a rule into a second place.

### D1 — The test axis is scoped to the test files the plan names

`spec-coverage.sh` gains a scope filter between test discovery and `grep_boundary_test()`. A
discovered test file is **in scope** when its basename appears as a whole token anywhere in the
`--plan` file. Basename and not full path, because the corpus uses both forms — the #404 plan names
`hook-hardening.test.sh` bare and `staging/plugin/scripts/tests/pairs-completeness.test.sh` in full.

The scope is computed by **filtering `$TESTFILES`**, never by re-deriving the discovery predicate.
Two derivations of "what is a test file" that could disagree would be a defect (CLAUDE.md rule 6,
ADR-0086), so there is exactly one, and the `.md` exclusion the SPEC's edge case requires to stay
closed is closed by construction: `$TESTFILES` is already post-exclusion, so no `.md` can enter
scope through the new path.

The scan itself is unchanged — same both-sides-anchored token regex, same whole-file match. **The
comment/assertion distinction is not implemented, by decision, on Finding 3.**

**Direction.** Over-scoping (a plan that names a test file in prose about another feature) fails
toward passing. That is the same direction as today and strictly tighter, which is the acceptable
direction for a change to a gate — the same reasoning ADR-0069 applied to `is_task_line()`.

### D2 — A denominator guard on the scope

Zero matches can be correct; zero *candidates* is a broken derivation, and from outside they are
identical (CLAUDE.md rule 7, ADR-0085). If `$TESTFILES` is non-empty and the scope is empty, the
derivation produced nothing: the run reports `SCOPE-EMPTY` on stderr with a distinct sentence, falls
back to the unscoped population for that invocation, and does not silently fail every id. Measured
15/15 plans yield a non-empty scope, so this is an anomaly channel, not a routine path.

This is deliberately fail-open and visible, matching the gate's existing `_rc = 2` philosophy: an
unrunnable derivation must not read as a clean result (CLAUDE.md rule 4), and must not read as a
wall of failures either.

### D3 — `UNSCOPED`, a new stdout token on the existing exit-1 channel

| Condition | stdout | exit |
|---|---|---|
| id mentioned nowhere in the discovered population | `UNCOVERED<TAB>R-NN<TAB>…tests` | 1 (unchanged) |
| id mentioned in the population but **not in scope** | `UNSCOPED<TAB>R-NN<TAB><scope-size>` | 1 (new) |

No new exit code. The gate's four-value contract (0/1/2/3) is unchanged and the SKILL.md block's
`_rc = 1` branch already surfaces `_out`. A fifth exit code would need a fifth policy branch for no
gain. The token is separate because **the remedy is different**: `UNCOVERED` means "write a test",
`UNSCOPED` means "cite this id in the test file this feature actually wrote". A token whose consumer
does not read it is the ADR-0091 defect, so the SKILL.md `_rc = 1` prose must name `UNSCOPED` and its
remedy — that is a task in the plan, not an aspiration here (CLAUDE.md rule 17).

`UNCOVERED`'s semantics are byte-for-byte unchanged, which is why the blocking channel carries zero
regression: measured 0 of 117 ids fail it today and 0 will after.

### D4 — `no-test:`, a declared exemption with a reason floor

The four requirements in Finding 4 are not test-assertable. Blocking on them is the false-negative
class R-03 forbids. They get a declared escape, in the requirement's own success-criteria item:

```
- [ ] R-14 — the ceiling decision is recorded in an ADR. (no-test: a documentation obligation, nothing executable to assert)
```

- Matched on a **flattened, undecorated, case-insensitive** copy of the item text, so a backticked or
  bolded marker is the same marker (CLAUDE.md rule 3, ADR-0073/0076/0080/0098/0101).
- Exempts the id from the **test axis entirely** — both the scoped and the unscoped half. A
  documentation requirement has no test mention to find.
- **Never exempts the plan axis.** A requirement that is not testable must still be cited by a plan
  task, or nothing connects it to work at all.
- **Reason floor: ≥ 20 characters** after the colon. A bare `(no-test:)` is `MALFORMED`, exit 3. The
  precedent is ADR-0082's 40-character cross-reference reason and ADR-0087's deployed-only reason; 20
  is lower because this reason is one clause inside a sentence, not a standalone declaration.
- **The reverse check (CLAUDE.md rule 9, ADR-0081/0084).** An exemption that covers nothing reads as
  clean. An id carrying `no-test:` whose token *is* found in the scoped test set is a stale waiver:
  `STALE-WAIVER<TAB>R-NN`, exit 3. It is a SPEC defect and the remedy is deleting one clause — but it
  is **not** auto-repaired. ADR-0072's self-repair is licensed because adding a checkbox marker
  changes no content; deleting an author's prose does.

### D5 — R-03 is proven by a frozen per-item baseline, not argued

R-03 requires the absence of a new false-negative class to be *proven over the corpus*. A new `RS`
section in `staging/plugin/scripts/tests/spec-coverage.test.sh`:

1. Derives the (spec, plan) population by issue-number prefix over `docs/specs/` × `docs/superpowers/plans/`.
2. Guards the denominator: the derivation must resolve, and yield ≥ 15 pairs and ≥ 100 ids.
3. Computes the scoped verdict for every (spec, id) and compares it **exactly** against a checked-in
   baseline, `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv`:
   `<spec-basename><TAB><R-NN><TAB>COVERED|UNSCOPED<TAB><class><TAB><reason>`, 117 rows, of which 24
   are `UNSCOPED` — 20 classed `testable` and 4 classed `not-test-assertable`.
4. Diverges **in either direction**: a live verdict with no baseline row and a baseline row with no
   live counterpart are both RED (CLAUDE.md rule 8 — a check that validates a list's entries is blind
   to what the list omits).

**A frozen per-item baseline, deliberately, not a floor.** A `>= N` assertion over a population with
slack still passes when its own plant removes one member (CLAUDE.md rule 10, ADR-0124). The floors
here are only vacuity guards on the derivation, and the site says so.

**No archived SPEC is edited.** The baseline is a new record *about* the historical corpus, written
forward; retro-fitting `(no-test: …)` into 4 completed SPECs would correct a historical record in
place, which CLAUDE.md rule 14 and ADR-0034/0075/0078 forbid. `no-test:` governs SPECs written from
now on; the baseline governs the ones already written. Their chains are complete and the checker will
never run on them again — what the baseline protects is the *derivation*, so that a future change
that silently flips a 25th id is visible.

### What ships as an enforcement and what ships as an instruction

An instruction is not an enforcement (CLAUDE.md rule 16, ADR-0047/0088), and this feature ships both.

- **Enforced:** the scope filter, the denominator guard, the `UNSCOPED` token and its exit, the
  `no-test:` parse and its reason floor, the `STALE-WAIVER` reverse check, the frozen baseline.
- **Instruction only:** the guidance in `architect.md`, `interview-driver/SKILL.md` and
  `spec-from-issue/SKILL.md` to write `(no-test: …)` on a requirement that is not test-assertable.
  Nothing forces an author to. What changes is the **failure shape**: a documentation requirement
  that nobody marked now produces a halt naming a remedy, instead of a silent false pass. That is an
  improvement and it is not a guarantee.

## Alternatives considered

### A1 — Implement SPEC objective 2 as written: require the mention to be on an assertion line, keeping the global scan

**Rejected on measurement.** It changes the verdict of **0 of 199 ids**. Every `R-NN` token present
in the harness at all is present on a non-comment line, and `R-01`…`R-18` are each present on an
`ok`/`bad` assertion-call line. The strictest possible form of the rule flips exactly one id, and
that one is a false negative. This is the SPEC's own proposed remedy and it is a provable no-op; the
brief for this design explicitly licenses saying so.

### A2 — Assertion-line requirement *plus* scoping

**Rejected on measurement, harder than A1.** 73 of 117 paired ids flip, and 49 of the 93 in-scope
covered ids fail purely on the comment rule — including 14 of 14 for issue #404, the most recently
merged and among the best-tested features in the repository, whose 45 in-scope `R-NN` mentions are
all comments. The harness convention places the requirement citation in the comment header that
introduces a block of assertions, which is the correct place for it. Adopting A2 would mean either
rewriting the citation convention across 25 test files or shipping a 53% false-negative rate. R-03
forbids the second, and the first is far outside this feature's scope.

### A3 — Scope from the git diff since `manifest.recovery_baseline_sha`

**Rejected on measurability.** It is the truest notion of "files this feature touched", but it cannot
be proven over the corpus, which R-03 requires. Step 7.0 collapses the Step 5 snapshot commits
(ADR-0104) — this project's own memory records that `git branch --merged` is useless here for exactly
that reason — so the historical diffs are not recoverable for the 15 pairs. It also couples a
file-reading checker to a git repository and to a manifest field it does not take as an argument.

### A4 — Scope from `step5-report.json`'s `files_modified`

**Rejected on measurability and coupling.** `files_modified` is the real Step 5 change set and the
report exists by the time this gate runs. But `.claude/step5-report.json` is a single mutable slot,
never archived per feature — the file on disk today belongs to #404. There is no historical
`files_modified` for any of the 15 pairs, so R-03's corpus proof is unobtainable. It would also make
a checker read the very report the gate writes its own verdict into, and add a fourth input to a
three-input CLI.

### A5 — Scope by feature slug: a test file whose basename contains the SPEC's slug

**Rejected on fit.** The corpus does not name test files after feature slugs. Issue #404's slug is
`404-stop-gate-trigger-granularity`; its test file is `stop-gate-path-predicate.test.sh`. Issue
#287's slug is `rtf-s-gitignore-glob-and-this-repo-s-own`; its test file is
`triage-state-gitignore.test.sh`. A slug-similarity threshold that matched these would match most of
the harness, and one that did not would empty the scope for most features.

### A6 — Report the vacuity instead of tightening: keep exit 0, emit the scoped verdict as data

**Rejected on R-01.** It has the strongest property available — zero flips, R-02 and R-03 satisfied
by construction — and it is genuinely tempting given that the measured true-positive yield is 20
ids across a corpus of completed features. But R-01 says the affected cases must "no longer read as
covered", and a gate that exits 0 still reads as covered. This repository already has ADR-0047's
distinction between a checker and a reporter; turning a checker into a reporter to avoid deciding is
the fence-sitting the architect contract forbids. It was rejected, not overlooked.

### A7 — Widen `no-test:` into a general per-requirement waiver with no reverse check

**Rejected on CLAUDE.md rule 9 and ADR-0081/0084.** A waiver that covers nothing reads as clean, and
a stale waiver outlives its reason silently. The `STALE-WAIVER` check in D4 is what stops
`(no-test: …)` from becoming the line every author adds to make the gate quiet. The reason floor is
the second half of the same defence.

### A8 — Extract the scope predicate into a new loaded `.awk` file beside the other two

**Rejected on CLAUDE.md rule 6 / ADR-0086's criterion.** Extract only when two copies giving
different answers would be a defect. The scope filter does not answer a new question — it filters the
population `spec-coverage.sh` has already derived with its own discovery predicate, in the same file,
in shell. A third predicate file would introduce a second definition of "what is a test file" that
*could* drift, which is the defect, not the fix. It would also add a `PAIRS` entry and a deployment
surface for nothing.

## Consequences

### Positive

- The tests half of the Step 5 → Step 6 coverage gate stops being vacuous. It has never rejected an
  id in its life; measured against the corpus it will now reject 24 of 117, of which 20 are genuine
  drift the gate was built to catch and was silently passing.
- The two halves of R-01 are both answered by one mechanism. A no-op plan task produces no in-scope
  test file mentioning its id, so it flips to `UNSCOPED`; a comment-only mention in a *foreign* test
  file stops counting for the same reason.
- The blocking channel carries zero regression by construction. `UNCOVERED` keeps its exact
  semantics, and 0 of 117 ids fail it before or after.
- R-03 becomes an executed assertion with a per-item frozen baseline rather than a paragraph. A
  future change that flips a 25th id turns the harness red on the specific row.
- The `.md` self-coverage exclusion (ADR-0048 §D3) stays closed without a second guard, because the
  scope filter narrows an already-filtered population rather than re-deriving one.
- No new deployed file. The change is confined to `spec-coverage.sh` (already in `PAIRS`), the
  existing `spec-coverage.test.sh` (already in the CI `shell-tests` list), one new non-deployed data
  file under `staging/plugin/scripts/tests/`, and instruction text. No `PAIRS` entry and no
  `docs-ci.yml` edit are required — both of which a new `*.test.sh` file *would* have needed.

### Negative

- **R-01 is satisfied in objective and deviated from in mechanism.** The gate does not distinguish a
  comment from an assertion, because the corpus says the comment is the citation. Anyone reading
  issue #312 and then this implementation will find the stated remedy absent. That is why Finding 3
  is in this ADR at length and why the deviation is disclosed at the call site too.
- A new authoring obligation on every future SPEC that contains a documentation, process or
  deployment requirement. Measured at 4 of 117 ids, so roughly one requirement in thirty, but an
  author who does not know about `(no-test: …)` meets a halt rather than a pass.
- The scope derives from the plan, which is prose written *before* the work. A coder who renames a
  test file the plan named produces a halt that names the wrong cause. The remedy is visible and the
  disclosure mechanism for it already exists (ADR-0073's plan deviations), but it is friction the
  gate did not previously have.
- Over-scoping is unbounded on the loose end. A plan that names 18 test files (#365 does) gets an
  18-file scope, and the check is correspondingly weaker for that feature. The rule fails toward
  passing, which is the right direction, but the strength of the gate now varies with how many files
  a plan happens to mention.
- The baseline is 117 hand-frozen rows that must be regenerated whenever a chain completes and adds a
  16th pair. That is a maintenance cost on a file nobody will want to regenerate at 3am.
- Exit 3 gains a fourth cause (`STALE-WAIVER`) that ADR-0048's header comment does not describe. That
  header is now three amendments deep and is approaching the point where it explains less than it
  lists.

### Neutral

- `step5-report.json`'s `requirement_coverage` object gains an additive `unscoped` array beside
  `ids_declared`, `uncovered` and `status`. Additive by the same terms as `step5_mode`,
  `checkpoint_reviews`, `weakening_findings` and `plan_deviations` (ADR-0076): absent means the gate
  did not write one, never "none found". No schema version bump.
- The gate remains a **CHECKER** — branch on exit code — sitting a few lines from `weakening-scan.sh`,
  a **REPORTER**. Nothing here narrows that distinction and the instruction not to copy one block's
  branching into the other is untouched (ADR-0047, ADR-0048).
- `RE3`/`RE4`'s `>= 30` floor is left as a floor. CLAUDE.md rule 10 permits a floor kept purely as a
  vacuity guard when the site says so, and the id-less corpus grows with every feature, so an exact
  count would break on each one. The per-item baseline in D5 is where a plant must bite.
- Issue #313 (inertness for a SPEC under an unrecognised heading) and issue #314 (the
  literal-assertion-added detector) are adjacent and stay out. Neither is touched here.

## References

- `docs/specs/312-spec-coverage-measures-citation-not-impl.spec.md` — R-01, R-02, R-03
- `docs/superpowers/plans/2026-08-14-spec-coverage-measures-citation-not-impl.md` — the plan
- ADR-0048 (`docs/architecture/ADR-0048-102-requirement-ids-coverage.md`) — the gate this amends;
  §D3 test discovery, §D7/§D8 the silent no-IDs path
- ADR-0069, ADR-0072 — the predicate is loaded, never pasted
- ADR-0086 — the extraction criterion applied in A8
- ADR-0085 — guard the denominator, applied in D2
- ADR-0124 — a frozen per-item baseline replaces a floor, applied in D5
- ADR-0084, ADR-0081 — a declared exemption needs a reverse check, applied in D4
- ADR-0082, ADR-0087 — reason-floor precedent
- ADR-0091 — a new token needs a consumer that reads it
- ADR-0108 — the plant registry
- ADR-0104, ADR-0106 — why A3 and A4 are unmeasurable
- ADR-0034, ADR-0075, ADR-0078 — a historical record is corrected forward, not in place
- `staging/plugin/skills/concept-to-code/SKILL.md` — the Step 5 → Step 6 gate block
- `staging/plugin/scripts/tests/spec-coverage.test.sh` — the harness
