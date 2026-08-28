# ADR-0175 — Extract `## 5. HITL gates` out of `concept-to-code/SKILL.md`

- **Status:** Accepted
- **Date:** 2026-08-28
- **Builds on:** ADR-0172 (safety net + reverted pilot, physical-presence coupling class),
  ADR-0173 (`skill-extraction-preflight.sh`), ADR-0174 (Step 5 extraction — D2's three mechanical
  patterns, D3 population-glob coupling, D4 merged-view splice), repo rule 6 (extract only where
  divergence would be a defect), rule 7 (guard the denominator), rule 8 (ask which direction the
  check runs in), rule 12 (a cross-reference names a distinctive anchor, not a line number), rule
  18 (a scan is satisfied by the whole population it searches, not the part it meant).

## Context

After ADR-0174 (`VCS-047`), `concept-to-code/SKILL.md` was 3,042 lines. `## 5. HITL gates` (lines
1780–2948, the body immediately after the heading) was the other large block `VCS-042` identified:
1,169 lines, 23% of the file — every Gate from `Gate 0 — Chain routing` through `Gate 5.6 —
Transition to commit`, loaded in full on every chain invocation even though most gates fire once,
at a specific step. This is the second and last of `VCS-042`'s two blocks; closing it closes
`VCS-042`.

`skill-extraction-preflight.sh` (ADR-0173), run against `concept-to-code/SKILL.md 1780 2948`,
enumerated 16 in-range `# plant:` declarations across 6 files and 4 awk-range extraction sites
whose start anchor sits inside the range. A direct grep for Gate heading literals additionally
found `proportional-audit-depth.test.sh`, not caught by the plant/awk scan — the same "whole-file
grep" class VCS-047's own research had to hand-supplement. The plan's own research also
**falsified** a stale `TODO.md` claim before writing: "Gate approval recording"'s five
cross-references were checked directly and confirmed to live entirely inside the moved range, not
outside it as the old note claimed (repo rule 13 — measure the premise, not the note).

The actual blast radius, found by running the full suite after the move (not by trusting the
pre-research table), was substantially larger than the 11-file estimate: 19 files broke. The gap
between "16 plants + 4 awk-sites across ~11 files" and "19 files actually broke" is itself the
finding this ADR records — `skill-extraction-preflight.sh` finds `# plant:` declarations and
single-line awk-range anchors; it does not find whole-file greps, population-glob builders, or
positional cross-file classifiers, all three of which this section's move exercised harder than
Step 5's did.

## Decision

### D1 — Full `## 5. HITL gates`, not a partial sub-block

Same reasoning as ADR-0174 D1: the section has no internal sub-heading structure that separates
cleanly (every `Gate N — ...` entry is a `**bold**` paragraph under the one `## 5.` heading, not
its own markdown heading), and it is referenced by name as a whole from §4's dispatch templates
throughout. A partial cut would still need every Gate-specific test re-pointed and gains nothing in
reduced blast radius.

`staging/plugin/skills/concept-to-code/references/hitl-gates.md` now holds the body
byte-identically (`diff <(git show HEAD:…SKILL.md | sed -n '1781,2948p') references/hitl-gates.md`
is empty — confirmed against the commit immediately preceding this move). `SKILL.md` keeps the
`## 5. HITL gates` heading plus a plain prose pointer, matching ADR-0174's exact convention — never
`@path`. One `PAIRS` line was added to `sync-to-claude.sh`.

### D2 — ADR-0174's three mechanical patterns, reused without modification

Simple repoint, whole-file-uniqueness concatenation, and boundary-straddling concatenation all
recurred here exactly as ADR-0174 D2 described them, applied per each assertion's own stated
semantics. The dominant shape this time was **simple repoint of an entire Gate block**: Gate 0,
Gate 2 (audit-profile), Gate 2b, Gate 4, Gate 4.0, Gate 4.5/5 heading anchors, and the "Gate
approval recording" block each moved wholesale, so the fix was almost always "read `$HITL_REF`
instead of `$CC`" for a heading-anchored `awk` range — `gate0-recommendation.test.sh`,
`gate2b-trust-probe.test.sh`, `gate4-implementation-axes.test.sh`, `hitl-gate-audit-trail.test.sh`,
`proportional-audit-depth.test.sh`, `external-dependency-gate.test.sh`,
`recovery-preflight.test.sh` (RH1/RH2/RH3/RH4/RH5/RH6/RI4/RI6/BR7, all reading the Gate 4.0 block).

Five files reused ADR-0174 D3's population-glob-coupling fix (widen a corpus builder to include
the new `references/*.md` file, not just `SKILL.md`): `transition-producer.test.sh` (`$PROD`),
`gate5-state-removal.test.sh` (`$FLAT`, plus GR5's own negative-shaped check — see D3 below),
`step5-checkpoint-review.test.sh` (`$CC_FLAT`), `concept-to-code-bsd-autopilot-gates.test.sh`
(`$FLAT_SKILL`).

Four files carried the `## 5. HITL gates`-anchored awk-range extraction ADR-0173's preflight tool
flagged directly (`agent-metrics.test.sh`, `concept-to-code-bsd-autopilot-gates.test.sh`,
`diff-budget-scope.test.sh`, `reward-hack-detectors.test.sh`) — in every case the range became the
whole extracted file, so ADR-0174's preferred fix applied unchanged: drop the awk range, `cp
"$HITL_REF" "$GATES"` instead.

### D3 — Rule 8/18 applied to a genuinely new instance: a negative-shaped check that must widen, not just a positive one

`gate5-state-removal.test.sh`'s GR5 asserts a REMOVED state (`gate_5_review_decision`) has no live
reference anywhere. Before this move, grepping `$CC` alone was correct — that was the entire
population. After the move, a stale reference could equally live in `$HITL_REF`, and a
`$CC`-only grep would report "clean" for the wrong reason: not because no live reference exists,
but because the grep never looked where one could be. Widened to `grep ... "$CC" "$HITL_REF"`.
This is the same rule ADR-0174's own accessibility-i18n.test.sh AIG2 fix established during Step
5's extraction — recorded here because it recurred on a genuinely different assertion (a removed-
state forward guard, not a stale-count guard), confirming it is a property of the coupling class,
not a one-off.

A second, independently-discovered instance of the same shape surfaced only by running
`plant-check.sh` itself, not by inspection: `concept-to-code-bsd-autopilot-gates.test.sh`'s G10
asserts a consolidated inline SPEC pre-flight string does not survive anywhere on the routing
path (`grep -cF 'Autopilot requires an existing SPEC.md' "$SKILL_MD"` must be 0). The plant's
target moved to `$HITL_REF`, so a plant that reintroduced the banned string there left the
`$SKILL_MD`-only grep unaffected — `G10_N` stayed 0, the assertion reported `ok`, and
`plant-check.sh`'s PC1 caught it directly: "the assertion still passed with the mechanism
removed." Fixed the same way as GR5: sum occurrences across `"$SKILL_MD" "$HITL_REF"` rather than
reading one file. Confirmed twice now on structurally different assertions (a removed-state
forward guard, a consolidated-string ban) that this coupling class is not caught by code review or
by the mechanical re-point patterns alone — only `plant-check.sh`'s own PC1 pass, run to
completion, actually exercises it.

### D4 — A second merged-view-splice instance, confirming ADR-0174 D4's class generalizes

`commit-transition-order.test.sh`'s `order_check()` classifies every `Invoke the commit skill`
occurrence against the **nearest preceding manifest write, by absolute line number, within one
file**. Before the move, Gate 4.0's own commit invocation, its preceding manifest write, and its
`commit-order-exempt` waiver all lived together in `SKILL.md`; the move put them all in
`$HITL_REF`, but the check's population (`derive_commit_lines "$C2C"`) still read only `SKILL.md`
— so CTO02's denominator dropped from 4 to 3 and CTO03's waiver check found 0 declared exemptions
where 1 was expected. Concatenation would not fix this either: `order_check`'s logic is
line-number-*positional* (it needs "which write is nearest, by line number, to this invocation"),
and two files concatenated naively would put Gate 4.0's own internally-consistent write→invocation
pair in the right relative order only by coincidence.

The fix is ADR-0174 D4's exact pattern, applied at a second, independently-discovered site: an
`awk` pass builds `$C2C_MERGED` by splicing `$HITL_REF`'s full content in at the `## 5. HITL gates`
heading's position (replacing the vacated span up to `## 6. Coexistence invariants`), and
`order_check`, the `EXEMPT_LINES` derivation, and `derive_commit_lines` for CTO03 all read
`$C2C_MERGED` instead of `$C2C`. This confirms the merged-view-splice need is not an artifact
specific to `worktree-isolation-contract.test.sh`'s classifier — it is the correct fix whenever a
check's logic is genuinely positional (nearest-by-line-number, not just "does X appear"), and any
future extraction should check for this shape explicitly rather than assume ADR-0174 D2's three
patterns are exhaustive.

### D5 — A pattern ADR-0174 did not need: split-invocation-and-sum, for a real checker taking one file argument

`path-rule-check.sh` is production code (a genuine checker, not a test-only helper), invoked from
three test files, whose interface is deliberately one file per invocation — "a later issue can
point this at autopilot-build/SKILL.md ... without editing this script" (the script's own header).
Concatenating two files into a synthetic merged blob before passing it in would corrupt the line
numbers `FINDING` output reports, which the caller does not consume here but a future caller might.
The correct fix, matching ADR-0174's own F2 precedent (which already ran the checker twice,
separately, against `$SKILL_MD` and `$STEP5_REF`) — extended one file further: `EG2/F2` in
`concept-to-code-manifest-helpers-guards.test.sh` now invoke the checker three times (`$SKILL_MD`,
`$STEP5_REF`, `$HITL_REF`) and require all three to be clean; `F4/F5`'s DENOMINATOR count guards
sum the three runs' `occurrences=` stderr fields rather than reading one run's count. `helpers=` is
read once (it is a property of the helper directory, not of which skill file is scanned, so it is
constant across the three invocations by construction).

### D6 — Cross-reference-form.test.sh: two same-file references became boundary-straddling

`cross-reference-form.test.sh`'s C1/C2 assert an anchor phrase and its target definition both
appear **exactly twice in the same file** (`xref "C1" "$CC" '...' "$CC" 2`) — a same-file
cross-reference where the anchor mention and the definition it points at are meant to coexist. The
move put the definition (`**Gate 0d transition block:**`, `**Step 2b — TOFU guard (resume path
only):**`) in `$HITL_REF` while the referring mention stayed in `$CC`, turning a same-file check
into a straddling one. Fixed via ADR-0174 D2's third pattern: a merged `$CC_MERGED` (plain
concatenation, not splice — `xref`'s occurrence-count logic is not positional) built once and
passed as both the `_from` and `_to` argument to the two `xref` calls, and to the follow-up
marker-uniqueness checks (C1b/C2b).

### D7 — A preflight-tool false positive, distinct from every real coupling class above

Re-running `skill-extraction-preflight.sh concept-to-code/SKILL.md 1780 2948` after the move (as
the plan's verification step 1 requires) reported one apparent in-range plant:
`batch-boundary-precedence.test.sh`'s `CB4`, at line 1877. Investigated directly: `SKILL.md`
shrank from 3,042 to 1,877 lines after the move (only the heading + a short pointer paragraph
remain where the 1,169-line body used to be), so unrelated content that used to sit well past line
2948 — in this case, `## 7. Failure handling`'s port-conflict guidance, confirmed via
`awk '/^## [0-9]/'` to be the section actually containing line 1877 — shifted upward into the
now-vacated 1780–2948 numeric span. `CB4`'s needle never moved; it never lived in `## 5. HITL
gates` at all. This is a **known limitation of the preflight tool, not previously documented**:
running it with the pre-move line range against the **post-move** file produces false positives
for any unrelated content that happened to shift into the vacated numeric window, because the tool
matches on absolute line position, not on section membership. The correct read of "0 in-range" for
a post-move check is therefore "0 genuinely-coupled hits after individually verifying every
reported line," not "the raw count is 0" — for this extraction it required exactly one such manual
check, which cleared.

## Verification

1. `skill-extraction-preflight.sh concept-to-code/SKILL.md 1780 2948` post-move: 1 raw hit
   (`CB4`), verified a false positive per D7, 0 genuine in-range plants or awk sites remain.
2. Full local suite (91 test files, background run, not foreground): 0 failures.
3. `plant-check.sh` in full (background, 623 plant declarations): first run caught
   `concept-to-code-bsd-autopilot-gates.test.sh`'s G10 as a non-firing plant (D3's second
   instance) via PC1 (PASS=629 FAIL=1); fixed and re-run. Second run: PC1–PC4 and PC5b clean, but
   PC5 correctly flagged `claude-md-condensation.test.sh`'s CMC05 as vacuous (PASS=629 FAIL=1) —
   this ADR's paired `docs/chain-decisions.md` narrative section did not exist yet at that point
   in the sequence, so CMC05 was already RED in the unmutated sandbox (repo rule 2, an assertion
   nobody planted pins nothing; PC5's own job is to catch exactly this). A third run, after that
   `chain-decisions.md` section was written, confirmed PC1–PC5b fully clean: 623/623 declarations
   fired, PASS=631 FAIL=0.
4. `pairs-completeness.test.sh`: `references/hitl-gates.md`'s `PAIRS` line present and correct.
5. `fence-contract-coverage.test.sh`: 67/67 — no fence-contract/fence-illustration marker
   regression (§5 carries one declared fence, `c2c-gate2b-trust-probe`, confirmed still counted).
6. Byte-identical body: `diff` against the pre-move commit's `sed -n '1781,2948p'` extraction,
   empty.
7. Explicit checks for both ADR-0174-discovered coupling classes, not just the assertion-level
   fixes above: every `*/SKILL.md`-only population glob in the suite (8 files) already passes
   post-move (5 needed no change — they either don't touch Gate content or were already widened
   by ADR-0174); `worktree-isolation-contract.test.sh`'s `docs/GUIDA-USO-IT.md`-driven classifier
   (the exact shape D4 first found) passes unchanged at 104/104, confirming it has no positional
   dependency on `## 5. HITL gates` content the way it did on Step 5's.

## Alternatives rejected

- **A partial cut of the largest Gate sub-block only.** Rejected per D1, same reasoning as
  ADR-0174.
- **Fix D4's positional coupling by keeping a duplicate of Gate 4.0 in `SKILL.md`.** Rejected —
  the same rule-6 objection ADR-0174 raised for D3: two copies that could answer "which write
  precedes this invocation" differently is exactly the defect class this repository does not
  tolerate.
- **Skip verifying the `CB4` preflight hit as a false positive and just re-point it anyway.**
  Rejected — `CB4`'s needle genuinely still lives in `SKILL.md`'s `## 7. Failure handling`, so
  re-pointing it to `$HITL_REF` would have introduced a real defect (a plant whose needle is no
  longer where the plant claims) to silence a tool artifact. Verified before trusting the count,
  per rule 13.

## Consequences

### Positive

- `SKILL.md` drops from 3,042 to 1,877 lines (38% further reduction on top of ADR-0174's cut;
  75.6% smaller than the pre-`VCS-042` 4,729-line original), loaded in full on every invocation
  regardless of which Gate is actually reached.
- `VCS-042` closes — both its identified blocks (Step 5, `## 5. HITL gates`) are now extracted.
- D3 and D4 confirm both of ADR-0174's newly-discovered coupling classes generalize beyond the
  single instance each was first found in (a rule-8/18 negative check on a genuinely different
  assertion; a positional merged-view need on a genuinely different classifier). A third pattern
  (D5, split-invocation-and-sum for a real multi-caller checker) and a documented preflight-tool
  limitation (D7) are new to this extraction.
- The stale `TODO.md` "Gate approval recording" external-coupling note is corrected, replacing an
  untested claim with one verified before this ADR was written (repo rule 13).

### Negative, stated plainly

- The pre-move research table (16 plants / 4 awk-sites / ~11 files) undercounted the real blast
  radius (19 files) by a wide margin — `skill-extraction-preflight.sh` finds `# plant:` and
  single-line awk-range anchors; it does not and cannot find whole-file greps, population-glob
  builders, or positional cross-file classifiers. Any future extraction target should budget for a
  full-suite-driven residual pass as the actual verification step, not the pre-research table as a
  complete inventory.
- No further `concept-to-code/SKILL.md` splits are planned after this (per the plan's stated scope
  boundary) — any future token-cost work on the skill needs its own new measurement and issue, not
  an assumption that the same coupling classes are now exhaustively known.
