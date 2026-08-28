# ADR-0173 — Skill-extraction preflight tool + blind-extraction guard hardening

- **Status:** Accepted
- **Date:** 2026-08-28
- **Builds on:** ADR-0172 (safety net + reverted pilot, `VCS-042`), repo rule 4 (did-not-run is not
  found-nothing), rule 5 (a reporter always exits 0), rule 7 (guard the denominator, not only the
  matches), rule 16 (an instruction is not an enforcement).

## Context

ADR-0172 named `VCS-042` (splitting `concept-to-code/SKILL.md`, 4,729 lines) not resolved, and
recorded one coupling class its pilot found: tests that plant a `sed` mutation or grep an exact
sentence directly inside `SKILL.md`'s body (physical-presence coupling), which no population glob
can fix. This session was asked to reconsider whether the split is worth pursuing at all, given
that outcome.

Measuring first (repo rule 13) changed the shape of the answer. Byte-share measurement: Step 5 is
38% of the file (~30k of ~79k estimated tokens), §5 HITL gates 23% — 61% combined, loaded on every
invocation regardless of which of the state machine's 8 steps is actually reached. The benefit is
real and larger than the reverted pilot's ~4% slice suggested.

But re-deriving the plant/anchor inventory (rather than trusting the hand grep VCS-047's own
research note used) surfaced **a second, distinct coupling class ADR-0172 did not name**: ten test
files extract a block of `SKILL.md` with an inline `awk` range (`/^### Step 5 —/{f=1} /^### Step
6 —/{f=0} f`), copy-pasted independently in each file with no shared helper. Most already guard the
extraction's emptiness (`[ -s "$BLOCK" ]` → `bad`, repo rule 7) and would fail loud if a heading
moved. Two did not, and both wrap the extracted block in a **negative-shaped** assertion (`bad` if
a phrase IS found, `ok` otherwise) — so an empty extraction, from an innocent heading rename, would
read as `ok` with no evidence anything was actually checked:

- `test-write-scope.test.sh` TL1 (`ABSTEP5`, extracted from `autopilot-build/SKILL.md`, not
  `concept-to-code/SKILL.md` — the same failure shape, a different skill file).
- `step6-effort-pin.test.sh` G1 (`SELECTION`, `concept-to-code/SKILL.md`'s Step 6).

This is exactly rule 7's hazard ("zero matches can be correct; zero candidates is a broken
derivation, and from outside they look identical") landing on a negative-shaped assertion, where
the two states are indistinguishable without an explicit guard.

## Decision

### D1 — Build `skill-extraction-preflight.sh`, a reporter (not a checker), before touching Step 5

`staging/plugin/scripts/skill-extraction-preflight.sh` takes a skill-relative path and a line
range, and reports every `# plant:` declaration whose needle resolves inside that range (using the
*same* whitespace-joined matcher `plant-check.sh`'s worker uses, not an approximation) plus every
`awk`-range extraction whose anchors overlap it. It always exits 0 (rule 5) — it answers "what is
coupled here", not "is this safe."

Validated against the known case: run against the reverted pilot's own range (3264–3466), it
reports `CTO05`, `CTO14`, and `worktree-isolation-contract.test.sh`'s `L4`/`L8`/`L9` — the sites
ADR-0172's D2 found by revert. It also found 3 sites the hand-research for `VCS-047` had missed
(`concept-to-code-bsd-autopilot-gates.test.sh:351`, `recovery-preflight.test.sh:126`,
`agent-metrics.test.sh:231`) and corrected one hand-research error (`TP1` was attributed to the
Express/Hybrid range; it actually resolves inside Step 5, line 1766). A hand grep across ~25 files
is exactly the kind of derivation rule 13 says not to trust without re-measuring.

Known limitation, stated in the tool's own output rather than hidden: end-anchor detection only
scans a single line (`grep`, no `-z`), so a multi-line `awk` program (e.g.
`step6-effort-pin.test.sh`'s three-line form) reports its end-anchor as `<none>`. This does not
cause a false negative on the primary "start anchor inside range" condition, only on the narrower
"range fully spans the extraction" case.

### D2 — Harden the two true silent-pass sites; add diagnostic-only guards to five already-safe ones

`test-write-scope.test.sh` TL1 and `step6-effort-pin.test.sh` G1 each gained a `-s`-based guard
assertion (`TL0`, `G0`) ahead of them, following the pre-existing `WC0`/`WF0` pattern already used
elsewhere in this same codebase, and the consuming assertion itself was changed to `bad` rather
than fall through to `ok` when its extraction is empty.

Five further sites named in this session's initial research turned out, on inspection, to already
fail loud (positive-shaped `grep -qF … && …` conditions, safe by construction) —
`spec-coverage-baseline-bump.test.sh` (`STEP70B`/`BUMPBLOCK`), `weakening-wiring.test.sh`
(`AB_STEP5`/`AB_STEP6`, `NA_PHASE1`). These got the same `WC0`-style guard anyway, for diagnostic
clarity and consistency with the convention the same files already use elsewhere (a failure reads
as "extraction empty" rather than "content wrong"), not because they were at risk of a silent pass.

One site, `agent-metrics.test.sh`'s `DISPATCH_TEMPLATES` extraction, turned out to be dead code —
extracted, never read (the consuming assertion already scans `$STEP5` directly per its own
comment). Removed rather than guarded.

### D3 — Defer the Step 5 / §5 split itself

This session's scope was making the suite capable of validating a split, not performing one.
`VCS-047`/`VCS-048` remain open, now with a tool (D1) that turns "which tests are coupled to this
range" from an error-prone hand grep into a single reproducible command.

## Alternatives rejected

- **Extract a shared `extract_section()` helper across the ten `awk`-range test files.** Rejected
  for this pass: each file answers a locally different question about a different heading pair,
  ADR-0086's criterion (share only when divergence would be a defect, repo rule 6) does not clearly
  force it, and it would be a larger, independently-reviewable refactor mixed into a
  hardening-only change.
- **Proceed straight to the Step 5/§5 extraction now that the byte-share case is strong.** Rejected
  — the same session that found the blind-extraction class is not the session to spend the tool on
  its first real use against the highest-stakes cut in the file. Prove the tool and the guards
  hold, in a change with a small, fully-enumerable blast radius, before trusting it for Step 5.

## Consequences

### Positive

- Two genuine silent-pass sites closed (`TL1`, `G1`), each verified RED against a planted heading
  rename in a scratch copy before being trusted (repo rule 2).
- A reusable, validated tool exists for the next extraction attempt, more accurate than the hand
  research it replaces (found 3 additional coupled sites, corrected 1 misattribution).
- `VCS-042`'s cost/benefit is now grounded in a measured byte-share (61% combined for Step 5 + §5)
  rather than a line-count guess, and the decision to keep the split alive (rather than close it as
  won't-do) rests on that number.

### Negative, stated plainly

- `VCS-042` is still not resolved; `SKILL.md` is unchanged. This session narrowed the risk on the
  eventual attempt without shipping any part of it.
- The tool's end-anchor detection is single-line only (D1); a future extraction touching a
  multi-line `awk` program's end anchor needs a manual look, not a clean report.
- Five of the seven hardened sites added a guard assertion with no correctness payoff (D2) — pure
  diagnostic-clarity overhead, adopted for consistency with a convention already present rather
  than because a defect was found there.

Detail of the phased follow-up: `TODO.md` `VCS-047` onward.
