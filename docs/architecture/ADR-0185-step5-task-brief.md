# ADR-0185 — VCS-057 Fase 2 L1: `step5-brief.sh`, a per-batch dispatch brief

- **Status:** Accepted
- **Date:** 2026-08-31
- **Corrects:** ADR-0070's disclosed `task_num()` digits-only limit, and ADR-0100's `--count-openers`
  arithmetic (see the dated Corrections appended to both, and to ADR-0121, rule 14).
- **Related:** ADR-0069/ADR-0070/ADR-0100/ADR-0121 (the shared plan-task predicate and its two
  questions), ADR-0052 (the diff-budget/scope reporter whose parser this reuses), ADR-0184
  (VCS-057 Fase 1, the memory-shard question this ADR does not touch).

## Context

VCS-057's plan opened with two distinct problems: whether `coder`'s persistent memory could
survive Step 5's merge-back (Fase 1, closed by ADR-0184), and a measured, unconditional preamble
cost paid by every Step 5 dispatch regardless of path (Fase 2). Measured 2026-08-30: `PROJECT.md`
alone is ~37,600 tokens, injected unconditionally into the Workflow dispatch prompt; separately,
every dispatched tester/coder — on both the Workflow path and the Agent-tool fallback — is told to
unconditionally read the full plan, ADR, SPEC.md and project CLAUDE.md before opening a single
source file, for a batch that touches only 2-3 of the plan's tasks. `dispatch-state.sh`'s own
recorded fact — 32 of 34 recorded dispatch modes are `agent_batch`, 2 are `workflow` — means the
per-batch cost on the Agent-tool fallback, not the one-time Workflow preamble, is what actually
gets paid on almost every run.

## Decision

`step5-brief.sh` (new, `staging/plugin/skills/concept-to-code/scripts/`) materializes, once per
batch, a small Markdown brief carrying:

1. The **byte-exact, contiguous slice** of the plan text for the batch's tasks — never a
   paraphrase, so it cannot lose a constraint the way a summary could.
2. The **union of files** declared by those tasks' `Budget:` lines, via `plan-budget-parse.awk`
   (loaded, not restated — rule 6), noting per-task "no Budget: declared" where absent (absent is
   never zero).
3. Which **other tasks are excluded** from this batch, each pointing at the plan's own path, for
   recovery if a constraint was misattributed.
4. **ADR/SPEC/project CLAUDE.md as paths with a stated reason** — no longer read unconditionally.
   A Claude Design artifact (Gate 1d, ADR-0181), when present, is still read directly by both
   dispatch templates: its own manifest gate already scopes it to "if not null", and D0/CD4
   (`claude-design-gate.test.sh`) pin its exact wording — reopening that contract was out of
   scope here.

`--verify` recomputes the plan's true per-task line spans independently and checks, backward from
the plan to the briefs (rule 8): every real task assigned to exactly one brief (GAP/OVERLAP if
not), and each brief's own declared `lines=` matches the true span for its own declared task set
(BOUNDARY-MISMATCH otherwise — the dangerous failure mode named below).

**Contract, a CHECKER not a reporter:** `0` written/clean, `1` verify found a coverage problem,
`2` bad invocation, `3` DID-NOT-RUN (the plan has zero task openers — the caller falls back to
today's full-plan prompt and **declares** that the fallback fired; this script does not decide
that silently, rule 4).

**Enforcement vs. instruction, stated explicitly (rule 16).** The slice, the file-map union and
the `--verify` coverage check are enforcement — shell, exit-coded, testable. "Read the brief, open
the ADR only when it says so" is instruction: nothing stops a dispatched agent from reading the
ADR anyway. The failure shape changes (an agent that ignores the brief pays the preamble cost
again, quietly); no guard here can catch that, and the brief's own header says so rather than
implying a guarantee that does not exist.

**Dangerous failure mode.** A brief that verifies "clean" by task-number set — every task
assigned to exactly one brief — but whose slice boundary is off by one line (an opener's
`start_line` miscomputed) is invisible to a set-only check. `--verify` additionally recomputes
each brief's TRUE span from the plan and compares it to what the brief declared, which is why the
plants on `step5-brief.test.sh` target the coverage check, the DID-NOT-RUN branch, and the
producer/consumer path match specifically.

## Two defects found while building this, fixed here, corrected forward elsewhere (rule 14)

Neither defect was hypothetical — both were measured against the real corpus in
`docs/superpowers/plans/` (79 plans) while smoke-testing this script, and neither had ever mattered
to an existing consumer, which is exactly why they had gone unnoticed:

1. **A task number can legitimately open twice.** Most plans in the corpus carry a "Task
   checklist" index — a compact `- [x] Task N — ...` block near the top, scanned by
   `concept-to-code`/`autopilot-build` for progress tracking — immediately followed, much later,
   by the task's real `## Task N` heading. Both satisfy `is_task_opener()` by design (the
   predicate recognises both forms so a plan using ONLY the checklist form still counts). Measured
   across the full corpus: 66 of 672 opener lines were this exact restatement — the leading index
   line is always within 5 lines of the next task's own index line, never a genuine second block.
   `diff-budget-check.sh`'s pre-existing use of the predicate never needed a single unambiguous
   start/end line per task (it only asks "is task N a member of the requested set"), so this never
   surfaced there. `step5-brief.sh`'s byte-exact slicing does need exactly one start line per task,
   so `plan_task_starts()` now dedupes to the LAST occurrence per task number — corpus-verified to
   always be the real heading, never the index restatement.

2. **`task_num()` extracted digits only**, collapsing `"Task 1b"` and `"Task 1"` onto the same key
   `"1"` — a limit ADR-0070 disclosed and ADR-0100 carried forward, unfixed, because neither
   consumer needed the distinction. `step5-brief.sh` does: a numeric `--tasks N-M` range straddling
   a real letter-suffixed task must never silently absorb or skip it. `task_num()` (now in
   `plan-budget-parse.awk`, shared with `diff-budget-check.sh`, rule 6) keeps the full designation
   — measured: exactly two letter-suffixed tasks exist corpus-wide (`1b`, `4d`), both a single
   trailing letter. A numeric range that spans one is refused by name (`"tasks 1-2 ... also span
   task(s) 1b, which sit between 1 and 2 but are not integers"`), never silently mis-sliced.

**Collateral discovery, corrected forward (not part of this ADR's own decision, but load-bearing
for it): `plan-tasks.sh --count-openers` was itself double-counting**, for the same reason as
defect 1 — it summed opener LINES, not distinct tasks. Measured: `hook-hardening.md` reported 18
where 9 real tasks exist. This is the arithmetic Fase 2's own L2 (budget-driven batch sizing) will
depend on, so leaving it broken while building L1 would have built L2's threshold on a number
already known wrong. Fixed the same way (dedup by `task_num()`), re-verified against the full
79-plan corpus and against `batch-dispatch-openers.test.sh`/`plan-task-count.test.sh` (unchanged
pass counts). Dated Corrections recorded on ADR-0070, ADR-0100 and ADR-0121 (whose divergence
figures were measured against the pre-fix `--count-openers`) rather than edited in place.

**Third defect, caught by `plant-check.sh`'s own PC2, not by the harness going green (rule 2).**
The full sweep reported `PASS=661 FAIL=1` with three malformed plant declarations, none of them a
formality:

- `SB10` and `SB14` (`step5-brief.test.sh`) had needles that could never match: a needle field is
  matched verbatim, never unescaped (only a *replacement* field's `\n`/`\\` are — `plant-check.sh`
  says so explicitly), so a needle written with a literal `\n` standing in for a real line break, or
  a literal `\|` standing in for a plain pipe, matches zero times in the actual file. Fixed by
  relying on the matcher's own `\s+`-joined tokenization (which already crosses line breaks without
  help) and by choosing a pipe-free needle for `SB14` instead of escaping the pipe.
- `PTK9` (`plan-tasks.sh`, in `plan-task-count.test.sh`) went from one match to two: the
  `--count-openers` fix above added a second, byte-identical copy of the pre-existing "awk failed"
  exit-3 line into the new `openers`-mode branch. `PTK9`'s own comment already documented that
  branch as one mechanism shared by both modes (rule 6) — restored that by building the mode-specific
  `awk` argument list per branch and keeping a single shared invocation and a single error line,
  rather than duplicating the guard.

None of the three was caught by any single-harness run in isolation — each harness was green on its
own terms, since a plant that cannot fire never turns an assertion red by itself. Only the sweep's
own PC2 (a check that a plant's own needle is usable at all) surfaced them, which is the reason PC2
exists as a separate assertion from PC1.

## Consequences

### Positive

- Every Step 5 dispatch — Workflow path and Agent-tool fallback alike — reads a small, byte-exact
  brief instead of the full plan, ADR, SPEC.md and project CLAUDE.md, for the tasks it does not
  hold. `PROJECT.md`'s inline injection is unchanged here (its own digest is Fase 2's L2, an
  independent, Workflow-only step, deferred by design).
- The corpus-wide double-counting in `plan-tasks.sh --count-openers` is fixed as a byproduct,
  correcting the batch-sizing arithmetic every Step 5 run has used since ADR-0100 shipped — toward
  MORE, SMALLER batches than warranted, never toward too few (see ADR-0100's Correction).
- `task_num()`'s letter-suffix fix closes a risk ADR-0070 explicitly disclosed and left open for
  over a month, because nothing needed it fixed until this feature did.

### Negative

- `--tasks N-M` cannot express a batch containing a letter-suffixed task (`1b`, `4d`) alongside an
  adjacent integer in one contiguous request — the caller must request the letter-suffixed task
  separately. Measured: 2 of 79 corpus plans are affected, and the refusal is explicit and named,
  never a silent mis-slice.
- A plan whose author places a task's real constraint inside an ADJACENT task's block (rather than
  its own) still under-matches — the brief's per-task slice attributes text to the wrong task, and
  nothing in this design catches it. The `Excluded tasks` section's back-pointer to the plan's own
  path is the recovery path, and it depends on a model choosing to use it (rule 16 disclosure,
  restated at the top-level of this ADR too).
- Inert until `sync-to-claude.sh --apply`, like every change to a deployed script.

### Neutral

- No manifest field, no schema bump, no new state-machine transition.
- `plan-tasks.sh` now loads `plan-budget-parse.awk` for `--count-openers` only, alongside
  `plan-task-predicate.awk` — `--count` (the loose, `>= 1` guard) is untouched.

## References

- `staging/plugin/skills/concept-to-code/scripts/step5-brief.sh` — the script itself
- `staging/plugin/scripts/tests/step5-brief.test.sh` — SB0-SB16, Z1; plants SB6/SB10/SB14
- `staging/plugin/skills/concept-to-code/scripts/plan-budget-parse.awk` — `task_num()`'s fix
- `staging/plugin/skills/concept-to-code/scripts/plan-tasks.sh` — `--count-openers`'s fix
- `docs/architecture/ADR-0070-184-diff-budget-task-predicate.md` §Correction 2026-08-31
- `docs/architecture/ADR-0100-242-batch-dispatch-openers.md` §Correction 2026-08-31
- `docs/architecture/ADR-0121-290-plan-shape-predicate.md` §Correction 2026-08-31
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` — "Materializing the
  per-batch brief", "Materializing the roadmap digest", and both dispatch templates
- `/Users/stefer/.claude/plans/zippy-whistling-crescent.md` — the approved plan, Fase 2 §L1

## Correction 2026-09-01 (the roadmap digest is L1's own scope, not L2's — and is now built)

**The Positive-consequences line "`PROJECT.md`'s inline injection is unchanged here (its own digest
is Fase 2's L2, an independent, Workflow-only step, deferred by design)" mislabelled which
mechanism owns the digest, and is superseded on both counts.** The approved plan's own L1 section
(`~/.claude/plans/zippy-whistling-crescent.md`, "### L1 — `step5-brief.sh`") states the digest
as one of L1's five brief contents and says so explicitly: "il digest è una modalità di
`step5-brief.sh`, non uno script suo" (rule 6 — PROJECT.md's Step-5-side reduced form has exactly
one consumer, so it is a mode of this ADR's own script, not a second producer). L2 is the
*separate* budget-driven batch-sizing switch (plan-sequence step 5, not yet built) — the digest was
never part of it; the deferral was only ever about *when* in plan-sequence step 3 was the byte-exact
per-task brief, step 4 the roadmap digest, both L1.

`step5-brief.sh --digest --project-md <file> --out <file>` now extracts every `### Phase` heading
and every checkbox line (`- [ ]` / `- [x]`) from PROJECT.md, dropping the narrative prose between
them — measured on this repo's own 1823-line PROJECT.md: 216 lines out, an ~88% reduction, holding
exactly what a dispatched coder needs to recognise an existing `[x]` interface without re-reading
the roadmap as a document. Same CHECKER contract as write/verify mode: exit 3 (DID-NOT-RUN) when
PROJECT.md has neither marker, and the Workflow dispatch prompt falls back to inlining PROJECT.md's
full content and **declares** that the fallback fired (rule 4) — never a silent full-file read
disguised as the reduced path. `step5-implementation.md`'s Workflow preamble now materializes the
digest once per run (not per batch — PROJECT.md does not change between batches) and references its
path instead of inlining PROJECT.md's content directly.

This does not touch Step 2 (architect), which keeps reading `PROJECT.md` in full — it is the one
agent that actually consumes the roadmap as a roadmap, not as a source of interface names to avoid
re-implementing (SKILL.md:627-629, untouched).

Superseded lines above are not edited in place (rule 14): they were a correct statement of what had
shipped on 2026-09-01's predecessor commit and stay that way in the historical record.
