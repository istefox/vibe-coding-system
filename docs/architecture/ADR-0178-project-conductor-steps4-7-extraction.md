# ADR-0178 — Extract `### Step 4` through `### Step 7` out of `project-conductor/SKILL.md`

- **Status:** Accepted
- **Date:** 2026-08-29
- **Builds on:** ADR-0172 (safety net + reverted pilot, physical-presence coupling class),
  ADR-0173 (`skill-extraction-preflight.sh`), ADR-0174/ADR-0175 (`concept-to-code` extraction —
  the three mechanical repoint patterns, population-glob coupling, merged-view splice,
  split-invocation-and-sum, negative-shaped-check widening), repo rule 6 (extract only where
  divergence would be a defect), rule 8 (ask which direction the check runs in), rule 12 (a
  cross-reference names a distinctive anchor, not a line number), rule 18 (a scan is satisfied by
  the whole population it searches, not the part it meant).

## Context

`VCS-049` asked whether `autopilot/SKILL.md` and `project-conductor/SKILL.md` — the second and
third heaviest skills in the repo after `concept-to-code`, neither previously measured — were
worth the extraction pattern ADR-0174/0175 established, following the issue's own instruction to
decide from measured benefit rather than raw line count, since `concept-to-code`'s own outlier
ratio fell from 4x to 1.65x after that round.

**Measurement.** Per-section byte shares plus `skill-extraction-preflight.sh` (ADR-0173) over
both files:

| file | bytes | max section | max/mean ratio |
|---|---|---|---|
| `project-conductor/SKILL.md` | 60,875 (1,054 ln) | `## Phases` = 78.5% | 7.1x |
| `autopilot/SKILL.md` | 73,247 (1,228 ln) | `## 2. Phase 0` = 30.6% | 2.75x |

`project-conductor` was more skewed than `concept-to-code` was *before* ADR-0174 (4x); `autopilot`
was not — nine sections, evenly spread, and it carries an AWK-RANGE coupling site
(`weakening-wiring.test.sh:483`, start-anchor at `## 3. Phase 1 —`) that a 30%-section extraction
would need the merged-view-splice treatment for. `autopilot/SKILL.md` is left untouched; this ADR
covers `project-conductor` only.

Within `project-conductor`'s `## Phases` (813 lines), `### Step 4 — Invoke concept-to-code`
(20.6%) and `### Step 5 — Evaluate chain outcome` (29.7%) together were half the file. The chosen
cut is wider than either alone: lines 489–1026, `### Step 4` through the end of `### Step 7 — All
features complete`. This is the real load boundary — Steps 0–3 (load/reconcile `PROJECT.md`, show
status, HITL gate) run on every invocation; Steps 4–7 run only after a human confirms a feature —
and it is one contiguous range, so every inter-step `go to Step 6B` / `return to Step 2` /
`return to Step 3` inside the moved text either stays inside the new file or points at a heading
that stays in `SKILL.md`, with no dangling reference either way. Cutting only Step 4+5 would have
stranded Steps 5b/6A/6B/7 (2.4 KB of pure branch targets) alone in `SKILL.md`.

## Decision

### D1 — Byte-identical move, pointer stays, `references/` plural

`sed -n '489,1026p'` moved verbatim into
`project-conductor/references/steps-4-7-chain-execution.md`; `diff` against the pre-move body is
empty. `SKILL.md` drops from 1,054 to 518 lines (a 51% cut). The heading `### Step 4 — Invoke
concept-to-code` moves with its content (it is the first line of the moved range) — unlike
`concept-to-code`'s single-step extractions, which kept the step heading in `SKILL.md` and pointed
into a reference file starting at the first *sub*-heading, this move spans four step headings
(Step 4, 5, 5b, 6A/6B, 7) with no single wrapping heading to keep, so the pointer paragraph itself
carries the anchor: `Read \`references/steps-4-7-chain-execution.md\` when you reach Step 4 — it
contains the full Step 4 through Step 7 content for this section.` One `PAIRS` line added to
`staging/sync-to-claude.sh`, next to the existing `project-conductor/SKILL.md` entry.

### D2 — ADR-0174's three mechanical patterns, reused without modification

**Simple repoint** was the dominant shape: every `run_fence`/`extract_fence` call site naming one
of the three fence-contract IDs that moved (`conductor-fork-point`, `conductor-step4-nospec-skip`,
`conductor-step4-init-guard`, `conductor-branch-c-entry-classify`) changed its file argument from
`$PC` to a new `$PC_REF` — `conductor-entry-failure-split.test.sh` (18 call sites),
`scope-guards.test.sh`'s `extract_conductor_lookup` (anchored on the `### Step 5 — Evaluate chain
outcome` heading), `phase1.test.sh`'s CR8/CR9 (both landmarks moved together, so the line-order
check CR9 depends on survived the repoint unchanged).

**Whole-file-uniqueness concatenation** fixed three sites whose population was `SKILL.md` alone
and needed to become "the whole skill, wherever its content now lives": `autopilot-run-scope.test.sh`
CG9 (`cat "$PC" "$PC_REF"` before the flatten), `concept-to-code-bsd-autopilot-gates.test.sh`'s
`FLAT_COND` (mirrors that same file's own pre-existing `FLAT_SKILL` pattern for `concept-to-code`),
`human-gate-coverage.test.sh` HIC1a/HIC1b (`grep ... "$CONDUCTOR_SKILL" "$CONDUCTOR_REF"`),
`project-tasks-ledger.test.sh` NT9.

Boundary-straddling concatenation was not needed — no check here had its two halves land on
opposite sides of the cut.

### D3 — Negative-shaped checks must widen too (ADR-0175 §D3, confirmed a third time)

Two sites tested "this string appears nowhere," where the true population is now two files, not
one:

- `concept-to-code-bsd-autopilot-gates.test.sh` G11's `grep -qF 'Measured: it does not'
  "$CONDUCTOR_MD"` widened to check both `$CONDUCTOR_MD` and `$CONDUCTOR_REF`.
- `conductor-entry-failure-split.test.sh` W9's `! grep -q 'feature-level skip in Step 5C'
  "$TMPROOT/pc.flat"` widened to also read a new `"$TMPROOT/pc-ref.flat"`. This one was caught only
  by `plant-check.sh`'s PC1 pass after the mechanical fixes were believed complete — the full
  91-file suite was green with W9 still narrow, because its *positive* twin (the sentence's
  absence) trivially holds once the sentence physically leaves `SKILL.md`, regardless of what the
  reference file says. A green suite is not evidence for a negative-shaped check; only a plant that
  reintroduces the banned text in the new location, and a rerun of `plant-check.sh`, is. Confirmed
  a third time (ADR-0175 §D3 recorded two prior instances) that this coupling class survives
  inspection and mechanical repointing alike, and is caught only by running the mutation harness to
  completion.

### D4 — Plant target fields must follow their needle, not their historical file

Every `# plant:` declaration whose needle resolves inside the moved range had its target field
changed from `plugin/skills/project-conductor/SKILL.md` to
`plugin/skills/project-conductor/references/steps-4-7-chain-execution.md` — 16 declarations across
`autopilot-run-scope.test.sh` (CG9), `concept-to-code-bsd-autopilot-gates.test.sh` (G11, G11b),
`conductor-entry-failure-split.test.sh` (S1, S2, G2, G5, B1, B4, B6, B9, B9b, MR7, MR8, W8, W9),
`phase1.test.sh` (CR8, CR9), `project-tasks-ledger.test.sh` (NT9). Repo rule 1: a plant's target
field must belong to the mechanism it asserts about — `plant-check.sh`'s PC2 pass enforces this
directly (single-match-in-declared-file), and caught 12 stale target fields on the first rerun
after the mechanical repoints above, all inside `conductor-entry-failure-split.test.sh`, where the
sheer count of moved fence-contract call sites made it easy to repoint the *execution* site but
miss a plant declaration living in a separate comment block 200+ lines away from its check.

### D5 — No merged-view splice, no split-invocation-and-sum needed

Unlike ADR-0175's `commit-transition-order.test.sh` and `concept-to-code-manifest-helpers-guards.test.sh`,
no check here reads project-conductor content in a way that depends on absolute line-number
position across the two files, and no production checker takes a `project-conductor/SKILL.md` path
as an argument the way `path-rule-check.sh` does for `concept-to-code`. Checked explicitly per
ADR-0175 §D4's own warning that the three mechanical patterns are not exhaustive; neither shape
was needed this time.

## Verification

- `diff` of the extracted body against the pre-move `sed -n '489,1026p'` output: empty.
- Full local suite (92 files), run twice after all fixes: 0 failures both times.
- `plant-check.sh`: 626/626 plant declarations fired, PC1–PC5b clean, 634/634 assertions —
  including the W9 negative-shaped-check widening from D3, which required two full runs of
  `plant-check.sh` to surface (the first rerun cleared PC2's stale-target-field failures but still
  showed PC1's non-firing W9 plant; only the second rerun, after D3's fix, was fully clean).
- `pairs-completeness.test.sh` and `fence-contract-coverage.test.sh`: both clean with **no edit
  needed** — both were widened to cover `skills/*/references/*.md` by ADR-0172, ahead of any
  specific extraction, and picked the new file up automatically.
- `staging/sync-to-claude.sh --dry-run` lists `== NEW: skills/project-conductor/references/steps-4-7-chain-execution.md`.

## Consequences

### Positive

- `project-conductor/SKILL.md` drops from 1,054 to 518 lines (60,875 → ~27,400 bytes, roughly a
  55% cut), loaded on every invocation regardless of whether the run ever reaches Step 4. The
  common "show me project status" / HITL-gate-then-stop interactive path never needs Steps 4–7 at
  all.
- Confirms, for a fourth extraction (after the pilot and ADR-0174/0175), that the coupling classes
  this repo has now catalogued — population-glob, negative-shaped-check, plant-target-drift — are
  the actual recurring failure modes, not artifacts specific to `concept-to-code`.

### Negative, stated plainly

- `autopilot/SKILL.md` remains unmeasured-into-action: it was measured (this ADR's Context
  section) and found not to clear the bar, so `VCS-049` closes without touching it. A future
  token-cost pass needs its own new measurement and issue, per the same discipline VCS-048 left
  for this one.
- The blast radius here (7 test files, ~40 individual assertion/plant sites) was smaller than
  ADR-0175's HITL-gates move (19 files) — plausibly because `project-conductor` has fewer
  independent test harnesses coupled to it than `concept-to-code` does, not because this coupling
  class is rarer. The next extraction on a less-tested skill should not assume a small blast radius
  from this data point alone.
