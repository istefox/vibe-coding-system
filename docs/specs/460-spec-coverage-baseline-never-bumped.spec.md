# SPEC — the spec-coverage baseline never bumps itself when a chain enrols a new corpus member

**Topic slug:** 460-spec-coverage-baseline-never-bumped

## Objective

`spec-coverage.test.sh`'s RS7/RS8a assertions compare the live `(SPEC, requirement id)` population
against a frozen per-item baseline (`spec-coverage-scope-baseline.tsv`, ADR-0138 §D5). Step 7.0b of
the `concept-to-code` chain archives every chain's SPEC into `docs/specs/`, which is exactly what
enrols that chain's `(SPEC, plan)` pair into the population RS7/RS8a check. Nothing in the chain
updates the baseline when this happens, so the enrolling chain's own commit leaves the harness red
for whoever runs it next — a mystery they did not cause and cannot easily attribute (issue #460,
hit live by the #447 chain on 2026-08-17, and reproduced live by the #470 chain on 2026-08-22 while
building this SPEC).

This feature makes the enrolling chain bump its own baseline rows, in the same commit that causes
the enrolment, so the harness never goes red on someone else's watch for a reason they did not
create.

## Scope

**In scope:**
- A standalone script that computes the baseline rows for one `(SPEC, plan)` pair — the single
  source of truth both `spec-coverage.test.sh` and the chain read, so the two can never compute a
  different answer for the same input (ADR-0086).
- `spec-coverage.test.sh`'s RS7–RS10 block rewritten to call that script instead of carrying its
  own inline per-pair derivation.
- A new step inside `concept-to-code`'s Step 7.0b (`staging/plugin/skills/concept-to-code/SKILL.md`)
  that bumps the baseline for the chain's OWN `(SPEC, plan)` pair only, before the commit invocation,
  so the new rows land in the same commit as the archived SPEC and the rest of the feature.
- Failure behavior: an unresolvable bump (script missing, `spec-coverage.sh` unavailable, or a
  computed row that conflicts with an existing frozen row) stops the chain before the commit gate —
  loud, at the point someone can still act on it, never silent at the next CI run.

**Out of scope:**
- Closing any PRE-EXISTING gap between the population on disk and the baseline's rows. Measured
  2026-08-22 on `main`: the live population is 16 pairs, the baseline has 16 rows, zero divergence
  — there is no existing debt to close. (`312-spec-coverage-measures-citation-not-impl` resolves as
  a 17th live pair but is the script's own deliberate self-exclusion, per its existing
  `RS_SELF_PLAN` guard — unrelated to this feature and unchanged by it.)
- Bumping rows for any pair other than the chain's own. A chain completing does not repair debt
  left by other, unrelated chains — that stays a separate, explicitly-decided operation (an
  operator running the extracted script by hand, the way `docs/specs/470-...` was bumped manually
  on 2026-08-22 while this SPEC was interviewed).
- Rewriting or "correcting" any row already in the baseline for a different SPEC (CLAUDE.md rule
  14 — a frozen record is not corrected in place).
- Any change to `spec-coverage.sh`'s own coverage logic, its exit codes, or its `UNCOVERED` /
  `UNSCOPED` / `COVERED` verdict tokens.
- Fixing `spec-coverage.sh`'s unrelated continuation-line blindness to `(no-test: …)` markers
  (already recorded as a defect wanting its own issue, ADR-0165 §D8 — not this feature's subject).

## Stack

Bash 3.2-clean (macOS-portable: no `[[ ]]`, no arrays, no `mapfile`, no `${var^^}`, no process
substitution), matching every other script in `staging/plugin/scripts/`. TSV read/write via
`awk`/`grep`/`sed`, matching the existing baseline file's own format. No new external dependency.

## Architecture

### The extracted script — single source of derivation (ADR-0086)

A new script, `staging/plugin/scripts/spec-coverage-baseline-rows.sh`, replaces the per-pair inline
logic currently duplicated inline inside `spec-coverage.test.sh`'s RS7–RS10 block (the loop that
calls `spec-coverage.sh --list` then `spec-coverage.sh --tests-root` and classifies each id as
`COVERED`/`UNCOVERED`/`UNSCOPED`).

**Two modes:**

1. **`--rows --spec <spec> --plan <plan> --tests-root <root>`** — prints TSV rows
   (`<spec-basename>\t<id>\t<verdict>`) for every id the SPEC declares, one line per id, computed
   from `spec-coverage.sh`'s own `--list` and default output — never a second interpretation of
   the tokens (same rule ADR-0069/ADR-0072 already apply to `spec-coverage.sh` itself). Prints
   nothing (exit 0, empty stdout) if the SPEC declares no ids.
2. **`--bump --baseline <file> --spec <spec> --plan <plan> --tests-root <root>`** — computes the
   same rows, then, for each:
   - Row absent from `<file>` → append it.
   - Row present with an IDENTICAL verdict → skip silently (idempotent — a resumed chain re-running
     Step 7.0b must not fail on its own already-bumped rows).
   - Row present with a DIFFERENT verdict → **fail**, exit non-zero, name the SPEC, the id, both
     verdicts, and print nothing to `<file>` — a frozen row is never overwritten by this path
     (CLAUDE.md rule 14). This should not occur for the chain's own first bump of a genuinely new
     pair; its only realistic trigger is a hand-edited baseline or a chain resumed after the
     underlying code changed between runs, and both deserve a human looking at the file, not a
     silent correction.
   Exits 0 with a one-line summary (`BUMPED <n> row(s) for <spec-basename>` or
   `BUMP-NOOP: SPEC declares no ids` or `BUMP-NOOP: already present`) on success.

`spec-coverage.test.sh`'s RS7–RS10 block is rewritten to call `--rows` for each pair its own
`RS_PAIRS` derivation resolves (that corpus-wide pairing scan — "which plan matches which SPEC by
issue-number prefix" — stays inside the test; it is a many-pairs concern the chain never needs,
since the chain always knows its own single pair from `manifest.artifacts.{spec,plan}`), building
`RS_LIVE` from the script's output instead of its own inline `spec-coverage.sh` calls. RS7's exact
per-row comparison against the baseline, RS8a/RS8b's orphan checks in both directions, and RS9's
denominator guard are unchanged — only the origin of `RS_LIVE`'s rows moves from inline logic to
the extracted script's `--rows` output.

### The chain-side bump — Step 7.0b, before the commit

Inserted into `staging/plugin/skills/concept-to-code/SKILL.md`'s Step 7.0b, immediately after the
existing `spec-archive.sh` call and its manifest repoint, before Step 7.0c's transition to
`completed`:

```bash
bash staging/plugin/scripts/spec-coverage-baseline-rows.sh --bump \
  --baseline staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv \
  --spec <the just-archived SPEC path> \
  --plan <manifest.artifacts.plan> \
  --tests-root <project_root>
```
(resolved via the same `CLAUDE_PLUGIN_ROOT` then `~/.claude` two-tier lookup every other
skill-helper script in this file already uses.)

- Exit 0, `BUMP-NOOP: ...` → nothing to do (this chain's SPEC declares no requirement ids, or the
  rows are already present from a prior run of this same Step 7.0b) — proceed silently.
- Exit 0, `BUMPED <n> row(s)` → the baseline file is now modified on disk. Step 7's existing
  `--include` mechanism (already used for the archived SPEC and the manifest) is extended to also
  include the baseline file path, so the new rows land in the SAME commit as the rest of the
  feature — never a second, orphaned commit.
- Non-zero exit (script missing, `spec-coverage.sh` unresolvable, or a row conflict) → **stop
  before the commit gate**, print the script's own stderr verbatim, and do NOT invoke `commit`.
  This is the loud failure the issue's own success criteria ask for: an unbumpable baseline halts
  the chain that would have caused the drift, at the point a human is still looking at it, rather
  than surfacing as a red CI run the next unrelated author inherits.

No new HITL gate. The bump is silent and automatic — it never rewrites an existing row (only ever
appends new ones for THIS chain's own pair), so CLAUDE.md rule 14 does not apply, and the same
"apply first, show after" precedent already governs `spec-normalize-ids.sh`'s self-repair inside
the Requirement-ID coverage gate. The new rows are visible to the human exactly as every other
Step 7.0b artifact is: in the diff `commit`'s own Step 4 gate shows before the human clicks
Approve.

## Data model

No new persistent state beyond the baseline TSV's existing three-to-five-column row format
(unchanged: `<spec-basename>\t<id>\t<verdict>[\t<class>\t<explanation>]`). This feature only ever
appends 3-column rows (`COVERED`/`UNCOVERED`/`UNSCOPED`, no `class`/`explanation` — those two extra
columns are reserved for the historical drift rows ADR-0157 already recorded and are never
produced by a fresh bump).

## API

Two new CLI flags on one new script, both described in full under Architecture above:
`spec-coverage-baseline-rows.sh --rows ...` and `spec-coverage-baseline-rows.sh --bump ...`.
No other script's CLI surface changes; `spec-coverage.sh` itself is untouched.

## Edge cases

- **The chain's own SPEC declares zero requirement ids.** `--bump` prints `BUMP-NOOP: SPEC
  declares no ids` and exits 0 — nothing to add, nothing to fail on.
- **Step 7.0b runs twice for the same chain** (a resumed manifest re-entering Step 7). The second
  `--bump` call finds its own rows already present with identical verdicts and no-ops per-row —
  the whole call still exits 0.
- **The SPEC declares ids but the plan cannot be resolved** (should not occur at this call site,
  since `manifest.artifacts.plan` is always set by Step 2 before Step 7 can be reached) — treated
  identically to `spec-coverage.sh --list` returning empty: `BUMP-NOOP`.
- **A computed row conflicts with an existing frozen row for the same `(spec-basename, id)`.**
  Fails loudly, writes nothing, names both verdicts. This is the one path where the feature
  deliberately refuses to be fully automatic, per CLAUDE.md rule 14 and the explicit design
  decision to never silently correct a frozen row.
- **The extracted script is missing or unreadable** (an un-synced deployment). The chain-side call
  fails loudly with a `sync-to-claude.sh --apply` remedy, matching every other skill-helper
  resolution block's own failure message in this same SKILL.md file.
- **`spec-coverage.test.sh`'s corpus-wide RS_PAIRS scan still finds pairs the chain-side bump never
  touches** (pairs whose SPEC was archived by a means other than this chain, e.g. hand-placed).
  Unaffected by this feature — RS7/RS8a still compare the full corpus against the baseline exactly
  as they do today; this feature only adds a producer for the chain's own pair, it does not change
  what the test checks.

## Success criteria

- [ ] R-01 — after a `concept-to-code` chain completes and its SPEC is archived (Step 7.0b), the
      baseline file already carries a row for every requirement id that chain's SPEC declares, in
      the SAME commit as the rest of the feature — `spec-coverage.test.sh` run immediately after
      that commit reports zero orphans for that chain's SPEC (RS8a).
- [ ] R-02 — the row-derivation logic exists in exactly one place (the extracted script); running
      `spec-coverage.test.sh`'s RS7 comparison and the chain's own `--bump` call against the same
      `(spec, plan)` pair produces byte-identical verdicts, because both read the same script's
      output rather than two independent implementations (ADR-0086).
- [ ] R-03 — a `--bump` call never overwrites, deletes, or changes the verdict of any row already
      present in the baseline for a DIFFERENT `(spec-basename, id)` pair — only appends rows for
      the pair it was invoked with, and only when that exact row is absent.
- [ ] R-04 — a `--bump` call whose computed row conflicts with an already-present row for the SAME
      `(spec-basename, id)` (different verdict) fails with a non-zero exit, writes nothing to the
      baseline file, and names both the id and both verdicts in its output.
- [ ] R-05 — when the chain-side bump at Step 7.0b fails for any reason (script unresolvable, or
      the R-04 conflict case), the chain halts before invoking the `commit` skill — the failure is
      visible to whoever is running the chain, not deferred to the next CI run.
- [ ] R-06 — a `--bump` call for a pair whose rows are already present in the baseline with
      identical verdicts (a re-run of Step 7.0b on a resumed chain) exits 0 and modifies nothing —
      idempotent.
- [ ] R-07 — `spec-coverage.test.sh`'s existing RS7/RS8a/RS8b/RS9 assertions, and every other
      assertion in that file, still pass after the RS7–RS10 block is rewritten to call the
      extracted script — the refactor changes where the per-pair derivation logic lives, not what
      any existing assertion measures (no-test: covered by re-running the harness itself, which is
      the mechanism this requirement is about — asserting "the test suite still passes" inside the
      test suite it names would be circular).
- [ ] R-08 — the current, pre-existing population-vs-baseline gap is measured and recorded as
      zero as of 2026-08-22 on `main` (16 live pairs, 16 baseline rows, `312-...` correctly
      self-excluded) — this feature closes no pre-existing debt because measurement found none
      (no-test: a one-time corpus measurement recorded in the ADR, not a property the running
      system can assert going forward).

## Definition of Done

- `spec-coverage-baseline-rows.sh` exists, is Bash 3.2-clean, and implements both `--rows` and
  `--bump` exactly as specified above.
- `spec-coverage.test.sh`'s RS7–RS10 block calls the script instead of its own inline derivation;
  the full harness still reports the same pass count (or higher, if new assertions are added for
  the script itself) with zero regressions.
- `concept-to-code/SKILL.md`'s Step 7.0b includes the bump call, its three exit-code branches
  (no-op / bumped / fail), and the `--include` extension to the `commit` skill invocation.
- Every plant declared for the new mechanism reports `FIRED` in `plant-check.sh` (CLAUDE.md rule
  2).
- `sync-to-claude.sh --apply` deploys the new script to `~/.claude/skills/concept-to-code/scripts/`
  (or wherever the deployed shape places it, per the existing PAIRS table) so the chain can resolve
  it via the same two-tier lookup every other helper uses.
