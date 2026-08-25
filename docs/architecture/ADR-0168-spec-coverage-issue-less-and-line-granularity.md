# ADR-0168 — an issue-less SPEC resolves, and a claimed file's own R-NN is not every feature's

- **Topic slug:** `spec-coverage-issue-less-and-line-granularity`
- **Issue:** none — found while implementing `commit-outcome-backstop-hook` (PR #509), itself an
  issue-less feature. Tracked as `VCS-034` and `VCS-035` in `TODO.md`.
- **SPEC:** none — a bounded change to two scripts, no requirement ids of its own
- **Extends:** ADR-0157 (the cross-feature id collision, file-level claim classification).
  Supersedes nothing.
- **Refuses:** widening `OWN_RE`'s file-level classification with ADR citations, on measured cost
  (A1)

## Status

Accepted — 2026-08-24.

## Context

Two bugs in `spec-coverage.sh` / `spec-coverage-baseline-rows.sh`'s requirement-coverage tracking,
both surfaced by the same feature: `commit-outcome-backstop-hook` has no GitHub issue, so its SPEC
carries no numeric prefix.

### VCS-034 — `do_pair()` cannot resolve an issue-less SPEC

`do_pair()`'s fallback slug construction unconditionally stripped the first hyphen-separated
segment of a SPEC's basename, even when that segment was not the numeric issue prefix. For an
issue-less SPEC (`spec-coverage-scope-back-reference.spec.md`), this built the mutilated fallback
slug `coverage-scope-back-reference`, which never matched the real plan
(`2026-08-18-spec-coverage-scope-back-reference.md`). The pair silently never resolved, and the
SPEC left `spec-coverage.test.sh`'s `RS_PAIRS` corpus sweep without a trace.

A previous attempt to fix only this (commit `ba1cba6`, reverted) measured the cost too late: fixing
the slug correctly also resolved other, previously-hidden issue-less SPECs already in `docs/specs/`,
producing 39 new `RS7` divergences and 36 new `RS8a` orphans against a baseline never regenerated to
account for them — a genuine fix with an unmeasured blast radius, and it shipped anyway.

### VCS-035 — a whole file's claim, not a line's

ADR-0157 classifies each discovered test file as `owned`, `foreign-claimed`, or `unclaimed` for a
given feature, by scanning the WHOLE FILE for a `#<n>` token. Once a file is `owned`, ANY `R-NN`
token anywhere in it — even a line that explicitly cites a different feature's issue — is read as
this feature's coverage.

Concretely: `sync-manual-steps.test.sh` is legitimately in scope for `#222` (its plan names it, it
names the plan back). `commit-outcome-backstop-hook`'s own plan added an unrelated comment to that
same file — `# commit-outcome-backstop (…, ADR-0168 Task 7, R-03) is the …` — and `#222`'s `R-03`
flipped from the frozen `UNSCOPED` to a live `COVERED`: a false green, one feature's stray comment
laundered into another's coverage record.

Measured on the corpus (101 discovered test files, 2026-08-24): **63% cite more than one feature's
`#<n>`.** This is the norm, not an edge case.

The stray line carried no `#<n>` at all — `commit-outcome-backstop-hook` has no issue number to sign
with — only its own ADR (`ADR-0168`). A filter keyed only on `#<n>` cannot see it.

## Decision

### D1 (VCS-034) — strip the first segment only when it is the issue prefix

`do_pair()`: the unconditional `_p_rest=${_p_bn#*-}` becomes conditional on `_p_n` (the digit check
already performed one line above) being non-empty. An issue-less SPEC's fallback slug is now its
whole basename, unmutilated.

Applied in two commits, not one, so the corpus growth this correctly enables is a measured,
attributable step rather than an unmeasured side effect: one commit lands the code fix alone
(deliberately red — `RS8a`, 36 new orphans, the two previously-hidden issue-less SPECs entering the
corpus for the first time), the next bumps the baseline via `spec-coverage-baseline-rows.sh --bump`
(verified pure append — `git diff -U0` shows zero removed or modified lines).

### D2 (VCS-035) — a line-granular NEGATIVE filter, inside `grep_boundary_test()` only

The file-level classification ADR-0157 built (`$OWN_RE`, `$FOREIGN_CLAIMED`, `$TESTFILES_UNCLAIMED`)
is unchanged — a file is still admitted to scope as a whole. What changes is which matching LINE
inside an in-scope file may be read as this feature's coverage:

- A claim token on a line: `#<n>` (already used file-level) **or** `ADR-NNNN` — an issue-less
  feature's only possible signature.
- A matching line carrying a foreign claim token and no own-key on that same line is discarded.
- A line carrying both (ownership beats a foreign claim at line granularity, same as ADR-0157
  already does at file granularity) or neither (the ordinary case — 864 of 972 `R-NN` mentions in
  this repo) is kept.

The own-key set for this line filter, `OWN_LINE_RE`, is a **new, separate variable** from `OWN_RE`
— `OWN_RE` still governs only the file-level classification and is **not** widened there. Measured
(ADR-0157's own comment, corroborated 2026-08-24): an ADR-based key set at file granularity would
admit 39–61 files per feature (median 47 of 98) instead of 1–11 — the exact reason ADR-0157 refused
`$BACKREF_RE` for this question in the first place. `OWN_LINE_RE` extends only the line-level
own-key, with the ADRs this feature's own plan cites (`$BACKREF_ADRS_UNIQ`, already computed for
`$BACKREF_RE`).

`grep_boundary_test_claimed()` — the helper that decides `UNSCOPED` vs. `UNCOVERED` — is
**deliberately left unfiltered**. Two reasons: filtering it would make a file's `UNSCOPED_POP`
membership depend on a line-level reason, breaking `RZ3`'s pinned guarantee that half-1 (plan-named)
membership is unconditional; and both `UNSCOPED` and `UNCOVERED` already mean "not proven" — there
is no false-`COVERED` on that axis to correct.

### D3 — the naive extension was measured and rejected

A first design recognized `ADR-NNNN` as a claim token without extending the own-key set. Measured:
it would mark 108 of 972 `R-NN` lines as claim-bearing (up from 32), and 76 of those are a feature
legitimately citing its OWN ADR — exactly the failure this fix exists to close, inverted. The
accepted design (`OWN_LINE_RE` extended with `$BACKREF_ADRS_UNIQ`) was then measured against the
full frozen corpus before being written: **0 verdict flips across all 154 rows, 19 pairs.** Three
initially-suspect `COVERED` rows (`410`/R-05, `385`/R-02, `176`/R-11) were checked individually and
confirmed unmoved — each survives because its claim-bearing line cites an ADR its own plan also
cites.

### D4 — what is enforcement and what is not (rule 16)

All of it is mechanical: a handful of `grep`/`printf` pipelines and one `awk` scan already in use for
`$BACKREF_RE`. Nothing here asks a model to behave.

## Consequences

- Two previously-hidden issue-less SPECs (`spec-coverage-scope-back-reference.spec.md`,
  `project-tasks-vendored-bilateral-ledger.spec.md`) enter the corpus: 36 new frozen rows, 21 pairs
  total.
- A file that legitimately belongs to more than one feature (63% of the corpus) no longer leaks an
  unrelated feature's stray `R-NN` mention into this feature's coverage.
- An issue-less feature's own ADR citations remain readable as coverage of its own SPEC (`RZ10`);
  only a foreign one is discarded (`RZ9` — the case that motivated this ADR).
- `spec-coverage-baseline-rows.sh --bump`'s existing refusal-on-conflict (a frozen row is never
  silently corrected, CLAUDE.md rule 14) meant VCS-035's fix needed no baseline hand-edit at all —
  the measured 0-flip result made D2 a pure code change with no accompanying `CORRECTION` block.
- A pre-existing pinned plant (`RZ4`, ADR-0157's own `SCOPE-FOREIGN-ONLY` refusal) stopped firing
  once this independent line filter also blocked its target mutation — defense in depth, not a
  regression, but it needed its fixture split (the file-level claim token and the `R-01` mention
  moved to separate lines) to keep pinning what it always pinned.

## Alternatives considered

**A1 — widen `$OWN_RE` (file-level classification) with ADR citations instead of adding a separate
line filter.** Measured (D2 above, reusing ADR-0157's own M2 measurement): 39–61 files per feature
admitted instead of 1–11. Refused for the same reason ADR-0157 refused `$BACKREF_RE` for this
question — the discrimination has no conjunct to lean on here, and an ADR-based key set is far too
generous alone.

**A2 — a same-line-STRICT filter (require an own-key on every covering line, no bare-line
exemption).** Measured: 939 of 972 `R-NN` lines carry no claim token at all — the ordinary case, a
comment naming an id once without repeating an issue number on every subsequent mention. This
design would have discarded 96% of legitimate coverage. Refused; pinned by `RZ8`.

**A3 — a proximity window (claim token within N lines of the R-NN mention) instead of same-line.**
Measured: no claim token exists within 200 lines for 140 of 972 mentions; a ±25-line window would
still lose 71% of mentions to noise from unrelated nearby claims. Same-line, negative-only, is the
only design with a near-zero measured cost.

**A4 — filter `grep_boundary_test_claimed()` too, for `UNSCOPED` → `UNCOVERED` precision.** Rejected
in D2 — breaks `RZ3`'s pinned half-1 unconditional-membership guarantee, and buys no correctness
since both verdicts already mean "not proven".

**A5 — fix VCS-034 and VCS-035 as one commit.** Rejected: the two require different baseline
mechanisms (`--bump`, pure append, for VCS-034's corpus growth; a targeted `CORRECTION` hand-edit
for any VCS-035 verdict flip — which the 0-flip measurement made moot, but was not knowable before
measuring). Mixing them would make a single row's change unattributable to its cause (CLAUDE.md
rule 14's per-row accounting).

## References

- ADR-0157 — the cross-feature id collision this ADR extends; its own M2 measurement (an ADR-based
  key set is too generous) is reused here at line granularity, confirming the same shape holds
- ADR-0138 — the scope axis, the `UNSCOPED` verdict, the frozen baseline
- ADR-0154 — the back-reference conjunction (`$BACKREF_RE`, `$BACKREF_ADRS_UNIQ`) this ADR's own-key
  extension reuses
- ADR-0166 — `spec-coverage-baseline-rows.sh --bump`'s refusal-on-conflict, the mechanism that made
  D2 need no baseline correction
- CLAUDE.md rules 2, 6, 7, 8, 13, 14, 16, 18
- `TODO.md` — `VCS-034`, `VCS-035`
- Reverted attempt: commit `ba1cba6` on `feat/commit-outcome-backstop-hook` (PR #509) — VCS-034
  fixed alone, unmeasured blast radius, reverted
