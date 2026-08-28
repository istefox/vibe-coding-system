# ADR-0174 — Extract Step 5 out of `concept-to-code/SKILL.md`

- **Status:** Accepted
- **Date:** 2026-08-28
- **Builds on:** ADR-0172 (safety net + reverted pilot, physical-presence coupling class),
  ADR-0173 (`skill-extraction-preflight.sh`, blind-extraction guard hardening, `VCS-042`/`VCS-047`
  research), repo rule 6 (extract only where divergence would be a defect), rule 7 (guard the
  denominator, not only the matches), rule 8 (ask which direction the check runs in), rule 18 (a
  scan is satisfied by the whole population it searches, not by the part it meant).

## Context

`concept-to-code/SKILL.md` was 4,729 lines / 316,590 bytes, loaded in full on every invocation of
the primary chain regardless of which of the state machine's 8 steps is reached. `### Step 5 —
Implementation` (old lines 1018–2708) measured at 38.2% of the file's bytes — the single largest
contiguous block, and needed by exactly one step out of eight.

ADR-0172's pilot (Express+Hybrid paths, 3% of the file) was reverted after the full local suite —
not the pre-research — found tests that plant a `sed` mutation or grep an exact sentence directly
into `SKILL.md`'s own body (**physical-presence coupling**): no population-glob widening fixes
this, the content has to physically stay in `SKILL.md`, or every coupled site has to be
individually re-pointed. ADR-0173 built `skill-extraction-preflight.sh` — a reporter, not a
checker, that finds every `# plant:` declaration and `awk`-range extraction coupled to a given
line range — and used it to fully enumerate Step 5's blast radius: 21 awk-range extraction sites,
~30 whole-file grep sites, 20 `# plant:` declarations, 5 fence markers, across ~25 test files. This
ADR performs the cut the prior two prepared.

## Decision

### D1 — Full Step 5, not a partial sub-block

Measured: no sub-block dominates (largest is `#### Fallback` at 7.8%, `#### Recovery-readiness
pre-flight` at 6.4%, the rest 0.7–4.9%), while 21 of the coupled sites anchor the whole `### Step
5 —` → `### Step 6 —` span and are therefore hit by any partial cut too. A smaller cut buys risk
reduction that is largely illusory and gives up most of the benefit (repo rule 13: measure the
premise, not the intuition).

`staging/plugin/skills/concept-to-code/references/step5-implementation.md` now holds the body
byte-identically (`diff <(git show HEAD~1:…SKILL.md | sed -n '1019,2708p') references/step5-implementation.md`
is empty). `SKILL.md` keeps the `### Step 5 —` heading plus a plain prose pointer — never `@path`,
which resolves at `load_reason: include` and preloads unconditionally, defeating the point (§8.7,
ADR-0172's rejected alternatives). `references/` is plural, matching
`pairs-completeness.test.sh`'s glob. One `PAIRS` line was added to `sync-to-claude.sh` — the copy
loop has no glob, every reference file needs its own entry.

### D2 — Three mechanical re-point patterns, applied by the assertion's own stated semantics

- **Simple repoint** (`$CC` → `$STEP5_REF`): the needle's content moved entirely and the check has
  no whole-file uniqueness semantics.
- **Whole-file-uniqueness concatenation** (`cat "$CC" "$STEP5_REF" | grep -c ...`): the assertion's
  own wording claims "exactly once **in the whole file**" — repointing to one file alone would
  silently narrow what "the whole file" means. Applied to `spec-coverage.test.sh` RF1,
  `test-write-scope.test.sh` TK1, `weakening-wiring.test.sh` WC1/WE5,
  `workflow-dispatch-pins.test.sh` B4a/B5, `batch-boundary-precedence.test.sh` BP0,
  `recovery-preflight.test.sh` RA1/RF2.
- **Boundary-straddling concatenation**: a count/needle has legitimate occurrences on both sides of
  the cut (one in a step that stayed, one inside Step 5). Neither file alone suffices; both must be
  read. Applied to `dispatch-completion.test.sh` (`FLAT`/`_gates`),
  `recovery-baseline-rebase.test.sh` (`FLAT`), `batch-boundary-precedence.test.sh`
  (`FB_BLOCK`/`S1_ANCHOR_N`), `test-write-scope.test.sh` (`TM_CC_ALL`),
  `workflow-dispatch-pins.test.sh` B5.

Choosing wrong in either direction was observed as a real, not hypothetical, failure mode during
this pass: a bare repoint on a whole-file-uniqueness check would have silently narrowed its own
claim; a bare repoint on a boundary-straddling count would have dropped the denominator to a floor
that reads as satisfied for the wrong reason (repo rule 7).

### D3 — A second coupling class, distinct from D2 and from ADR-0172's physical-presence class:
population-glob coupling

Several tests derive a **population** — of dispatch-site declarations, of `step5_mode`/
`hook_verified` producer literals, of the transition-producer's line-count denominator — via a glob
or `find` scoped to `*/SKILL.md`. That glob silently excludes `references/*.md` siblings: content
that physically moved into a `references/` file vanishes from the derived population with no error,
producing a false "drifted from baseline", a false "phantom value", or a genuinely too-narrow
derived set. This is repo rule 18's shape — a scan satisfied by the whole population it searches,
not the part it meant — but at the population-construction layer rather than at a single
assertion:

- `dispatch-completion.test.sh` DC21–DC25: `DISPATCH_SITE_FILES` widened from `SKILL.md`-only to
  `find "$SKILLS" \( -name 'SKILL.md' -o -path '*/references/*.md' \)`.
- `manifest-field-state.test.sh` `V_WRITTEN`/`WH_WRITTEN`: glob widened to include
  `*/references/*.md` alongside `*/SKILL.md`.
- `transition-producer.test.sh` TP1/TP1c2: `$PROD`'s builder explicitly appends `$STEP5_REF`, with
  an inline comment explaining that omitting it silently starves every producer inside old Step 5
  of a match.

The fix pattern (widen the glob to cover `*/references/*.md`) matches ADR-0172 D3's precedent for
the fence-contract/PAIRS-completeness globs, extended here to test-internal population builders
that were not part of that original safety net.

### D4 — One case needed a merged-view splice, not a repoint

`worktree-isolation-contract.test.sh`'s L2/L3 classify every step token `docs/GUIDA-USO-IT.md`
names against the SKILL.md block for that step, via a single-file `awk` scan
(`l_classify <file> <step-id>`). Step 5's heading (`### Step 5 —`) stayed in `SKILL.md`, but its
body (the `isolation: worktree` / `no sub-agents` mechanism `l_classify` actually looks for) moved
out — so scanning `$CC` alone finds the heading with an empty buffer behind it and misclassifies
Step 5 as `NEITHER`, producing a false L2 hit. Neither a repoint (there is no single file with both
the heading and the body) nor a concatenation (order matters — `l_classify`'s block boundaries are
positional) fixes this. The test now builds a merged view before classifying: an `awk` pass over
`$CC` that, on hitting `### Step 5 —`, prints the heading and then splices in `$STEP5_REF`'s full
content before resuming normal output at `### Step 6 —`. `STEP5_REF` carries no `### Step 5 —`/
`### Step 6 —` heading of its own, so this cannot mis-nest into a neighbouring step.

### D5 — Four sites needing individual judgement, all resolved per the plan's own table

- `worktree-isolation-contract.test.sh` W1: the write-scope clause's `>= 4` floor now counts
  against `$STEP5_REF` (all four occurrences moved together).
- `dispatch-completion.test.sh`: the `dispatch-state.sh` `>= 2` floor straddles the boundary (one
  hit stays in Step 4.5, one moved into Step 5) — fixed via boundary-straddling concatenation
  (D2), with an in-place comment naming the straddle per repo rule 7.
- `step7-snapshot-collapse.test.sh` SC8: the `chore(step5): snapshot …` literal exists both as the
  real `git commit -m` write site (moved to `$STEP5_REF`) and as an unrelated prose mention in
  SKILL.md's Step 7 intro (stayed). Pinned to `$STEP5_REF` specifically — the actual write site —
  per repo rule 18: a needle that also matches a stranger's occurrence is satisfied for the wrong
  reason.
- `step6-effort-pin.test.sh` E1: a Step-6 test whose two anchors both physically live in Step 5;
  re-pointed to `$STEP5_REF` with a comment stating it is a Step-5 non-regression check living in a
  Step-6 file.

### D6 — Two files needed fixes discovered by direct suite failure, not by the plan's own table

`fence-contract-coverage.test.sh` (S9, E20) and `hook-verify-workflow.test.sh` (S7, S8) were not
named in the original plan's enumeration but broke once the move landed: both looked up a
`fence-illustration:`-marked fence, or documentation prose, directly inside `concept-to-code/
SKILL.md` — content that had moved into `references/step5-implementation.md`. Both are simple
repoints (D2's first pattern). This is the expected shape of "nothing about the coupling is
unknown, what remains is mechanical" landing imperfectly on a hand-enumerated table: the direct
suite run (not the pre-research) is what actually catches the residual, consistent with ADR-0172's
own founding lesson.

## Verification

All done post-cut, matching the plan's verification section:

1. Full local suite (91 test files, run in background, not foreground — 2-minute cap): 0 failures.
2. `plant-check.sh` in full: 623/623 plants fired, PC1–PC5b clean, PASS=631 FAIL=0 — every
   re-pointed plant resolves to exactly one match in its new target, and no plant stopped firing.
3. `pairs-completeness.test.sh`: 322/322 — the new `references/` file has its `PAIRS` line and will
   deploy.
4. `fence-contract-coverage.test.sh`: 67/67 — all 4 `fence-contract` markers plus the 1
   `fence-illustration` marker are still counted after the move.
5. Byte-identical body: `diff` against `git show HEAD~1:…SKILL.md | sed -n '1019,2708p'` empty.
6. `skill-extraction-preflight.sh concept-to-code/SKILL.md 1018 2708`, run before the move, is what
   produced the enumerated blast radius this ADR's D2–D6 work off of (ADR-0173 D1).

## Alternatives rejected

- **A partial cut of the largest sub-block only.** Rejected per D1 — the coupling anchors the whole
  span regardless, so a partial cut trades most of the risk reduction for a smaller token win.
- **Fix the population-glob coupling (D3) by keeping a copy of Step 5's content in `SKILL.md` too.**
  Rejected — this is exactly the duplication rule 6 forbids where two copies could answer the same
  question differently; the fix belongs in the test's population construction, not in the shipped
  artifact.

## Consequences

### Positive

- `SKILL.md` drops from 4,729 to 3,042 lines / 195,754 bytes (38.2% reduction), loaded in full on
  every invocation regardless of which step is reached; the extracted content loads only when Step
  5 is actually reached.
- A second coupling class (population-glob, D3) is now named and fixed at every site this session
  found it, distinct from ADR-0172's physical-presence class and from the blind-extraction class
  ADR-0173 hardened — future extractions should check for it explicitly rather than assuming D2's
  three mechanical patterns are exhaustive.
- Two test files (`fence-contract-coverage.test.sh`, `hook-verify-workflow.test.sh`) gained
  fixes the original plan's table did not anticipate, found only by running the real suite —
  reinforcing ADR-0172's own lesson rather than needing to re-learn it.

### Negative, stated plainly

- `VCS-048` (`## 5. HITL gates`, 23% of the file) is deliberately out of scope for this PR and
  remains open. It can reuse D2's three patterns, D3's population-glob check, and
  `skill-extraction-preflight.sh`, but needs its own dedicated pass — nothing here proves §5's
  coupling inventory matches Step 5's.
- The population-glob coupling class (D3) was found by direct suite failure investigation, not by
  a systematic audit of every population-deriving test in the suite — other, not-yet-touched
  extraction targets may carry the same bug latently, undetected until they are cut.

Detail of the phased follow-up: `TODO.md` `VCS-048` onward.
