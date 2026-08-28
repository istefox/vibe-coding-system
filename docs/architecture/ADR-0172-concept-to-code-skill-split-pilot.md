# ADR-0172 — `concept-to-code/SKILL.md` split: safety net + a low-risk pilot extraction

- **Status:** Accepted
- **Date:** 2026-08-28
- **Builds on:** the 2026-08-28 token/speed audit (`TODO.md` `VCS-042`), repo rule 6 (extract only
  when divergence would be a defect), rule 10 (a floor absorbs its own plant), rule 18 (exact
  match, not substring — the same class of population-glob gap this ADR closes for fence coverage).

## Context

`~/.claude/skills/concept-to-code/SKILL.md` (4,729 lines, mirrored at
`staging/plugin/skills/concept-to-code/SKILL.md`) is the single biggest per-invocation token cost
in this repo's setup: it loads in full every time the primary chain workflow is invoked, whether
the session needs Step 1 or Step 7. The 2026-08-28 audit flagged it as `VCS-042`, four times the
size of the next-largest skill.

Before proposing a cut, three research agents were dispatched in parallel to verify the premise
and measure regression risk, rather than assuming either:

1. **The premise holds.** Claude Code does not preload a skill directory's contents — the SKILL.md
   body arrives via the Skill tool result; a sibling file only enters context on an explicit `Read`
   the model issues itself. Six skills in this repo already split step- or topic-local content into
   `references/*.md` this way (`git-repo-init`, `project-tasks`, `macos-ux`, `prompt-builder`,
   `humanize-en`, `swiftui-pro`), and the third-party `impeccable` skill (85-line `SKILL.md` +
   35 reference files, ~4,500 lines) is the scale proof. The one hard condition: the reference must
   be a plain-prose "Read `<path>` when you reach step X" instruction, never `@path` — `@path`
   resolves at `load_reason: include` and preloads unconditionally, which would spend the whole
   exercise for nothing.
2. **The file is densely, bidirectionally cross-referenced.** 44 test files under
   `staging/plugin/scripts/tests/*.test.sh` read its content directly; 80 `# plant:` declarations
   across 24 of those files key on its literal path; `cross-reference-form.test.sh` asserts
   "exactly one occurrence" for several markers inside it — a naive split that duplicates a marker
   between the orchestrator and a step file breaks that assertion by construction.
3. **A specific silent-failure trap exists today, independent of any split.**
   `fence-contract-coverage.test.sh`, `skill-fence-positional-tokens.test.sh`, and the WS0–WS7
   wrapper-divergence scan all derive their checked population from the glob `"$SKILLS"/*/SKILL.md`
   guarded by a `>= 100`/`>= 25` floor (rule 10). A `fence-contract`-tagged fence moved into a
   `references/*.md` file, without widening that glob, leaves the checked population while the
   floor likely still passes — the harness reports clean over an unenforced rule (rule 16).
   `pairs-completeness.test.sh`'s reverse deployment check has the identical shape: it covers
   `*/SKILL.md` one directory level under `plugin/skills` only, so a new reference file with no
   PAIRS entry silently never reaches `~/.claude/`.
4. **Step 5 (1,691 lines, 4 `fence-contract` markers) and §5 HITL gates (1,169 lines, 1 marker) are
   the real prize but also the highest-risk targets.** Over 15 test files anchor extraction windows
   inside or around these two sections (`agent-metrics`, `batch-boundary-precedence`,
   `batch-dispatch-openers`, `diff-budget-scope`, `gate0-recommendation`, `gate2b-trust-probe`,
   `gate4-implementation-axes`, `recovery-preflight`, `reward-hack-detectors`, `spec-coverage`,
   `step6-effort-pin`, `test-write-scope`, `transition-producer`, `weakening-wiring`,
   `worktree-isolation-contract`), plus two tests (`spec-pointer-archive.test.sh`,
   `step7-snapshot-collapse.test.sh`) that extract a *fixed 200-line window* from the
   `### Step 7 — Commit` heading — a window that would silently absorb unrelated trailing content
   if Step 7 were shortened.

## Decision

### D1 — Split in phases, not in one pass

Given the measured coupling, this ADR covers only: (a) widening the two silent-failure-prone test
populations and the deployment completeness check so they cover a `references/` directory before
any content moves into one, and (b) a single low-risk pilot extraction to prove the mechanism live.
Step 5 and §5 are deliberately deferred to dedicated follow-up sessions (`TODO.md`), each scoped to
one sub-block, reusing the test inventory this ADR's research already produced instead of
re-deriving it.

### D2 — Pilot attempted (Express + Hybrid paths), then reverted: text-mutation coupling, not just population-glob coupling

`### Express path — E1–E4` (lines 3264–3354) and `### Hybrid path — H1–H5` (3355–3466) were
identified as the lowest-risk extractable slice: 203 lines combined, 8 bash fences between them,
zero `fence-contract` markers, and — per the pre-implementation research — touched by exactly one
test as a boundary marker only. The pilot was implemented (body moved to
`references/express-hybrid-paths.md`, `SKILL.md` left with heading + prose pointer, PAIRS entry
added) and run against the full local suite, per this ADR's own D1 ("the real suite is the actual
gate, not the research"). It failed three files that the research had not flagged, for a different
reason than the fence/PAIRS population-glob trap D3 closes:

- `commit-transition-order.test.sh` (CTO02/CTO05/CTO10/CTO14) and `transition-producer.test.sh`
  (TP1) both use `sed`-based plants that mutate the *literal Express/Hybrid text inside `SKILL.md`
  itself* to simulate a regression, then assert the derivation still catches it. With that text
  moved out, the plant has nothing to mutate and the derivation's own denominator collapses — not
  a glob miss, but a requirement that the content physically live inside `SKILL.md`, not merely be
  `Read`-reachable from it.
- `worktree-isolation-contract.test.sh` (L6–L9) greps `SKILL.md` for the Express note's exact
  sentence ("no worktree isolation, by design" / "dispatches no sub-agent" / etc.) to verify the
  guide states its own worktree-isolation decision inline, next to the step it describes.

None of these three are population-glob checks like the ones D3 fixes — widening a glob does not
help when the check's contract is "this sentence is physically present in `SKILL.md`, at this
location, right where it must be visible." **Decision: revert the pilot rather than deepen the
fix.** The pilot's own token yield (~4% of the file) does not justify a second, harder-to-verify
round of surgery on three independent mutation-testing harnesses under the same session that
already found the fence/PAIRS gap. The three affected test files, and the shape of their coupling,
are recorded here so a future extraction attempt — of this slice or another — checks this class of
coupling before implementing, not after: **a content move breaks more than a `*/SKILL.md` glob
predicts whenever a test plants text mutations directly into `SKILL.md`'s own body, or greps it for
an exact inline sentence, rather than treating `SKILL.md` as one entry point among several.**

### D3 — Widen the fence-population and PAIRS-completeness globs before any content moves

`fence-contract-coverage.test.sh`'s `ALL_FENCES` population, `skill-fence-positional-tokens.test.sh`'s
fence-count (`FENCE_N`) and positional-token partition (`POP_FILE`) populations, and
`pairs-completeness.test.sh`'s reverse-completeness check now all also glob
`*/references/*.md` alongside `*/SKILL.md`. `skill-fence-positional-tokens.test.sh`'s SFP1
(a distinct "how many SKILL.md files exist" file-count guard) is deliberately left untouched — it
answers a different question than fence/token coverage and widening it would blur, not fix, its
denominator. None of these three widenings change today's measured counts (no `references/`
directory existed before this pilot), confirmed by re-running each harness before and after.

## Alternatives rejected

- **Split the whole file in one PR.** Rejected on the measured evidence: 44 test files, 80 plants,
  15+ high-risk anchors around Step 5/§5, and two fixed-window tests that would silently absorb
  wrong content if Step 7 shifted. The coordination cost of getting all of that right in one pass,
  reviewed in one sitting, is exactly the condition under which a regression ships unnoticed.
- **Use `@path` includes instead of prose `Read` instructions.** Rejected — confirmed live that
  `@path` resolves at `load_reason: include` and preloads unconditionally, which would make the
  whole split cost tokens for zero benefit.
- **Leave the fence-population/PAIRS gaps for whichever future PR first triggers them.** Rejected:
  both gaps are silent by construction (a floor that still passes, a deploy that silently drops a
  file) — better to close them once, now, while nothing yet depends on the widened behaviour, than
  to discover them the moment Step 5's fence-contract-bearing content is the thing that moves.

## Consequences

### Positive

- Closes two latent silent-failure traps (fence-population glob, PAIRS completeness) that would
  otherwise wait, undetected, for the day someone extracts fence-contract-bearing content — this
  holds regardless of the pilot's outcome, since no content has moved yet.
- `docs/vibe-coding-system.md` §8.7 now documents a pattern six skills already used without any
  written guidance — the next skill author doesn't have to reverse-engineer it from source.
- The reverted pilot still produced a real, checked result: a documented coupling class (D2) that
  a future extraction attempt now knows to check for *before* implementing, not after — the fence
  and text-mutation traps are qualitatively different failure modes, and only measuring caught the
  second one.

### Negative, stated plainly

- The pilot did not ship: `concept-to-code/SKILL.md` is unchanged at 4,729 lines. `VCS-042` is not
  resolved, not even partially — D2's attempt found a new obstacle rather than clearing one.
- The measured coupling (D2) means even the file's least-risky-looking slice was not actually
  extractable without further per-test rework; Step 5 and §5, already known to be more coupled, are
  likely to hit the same class of check (and possibly worse) on top of their already-identified
  high-risk tests.
- The widened globs (D3) are a permanent, small addition to every future fence/PAIRS harness run,
  for a directory (`references/`) that, as of this ADR, no skill in this repo populates — the
  infrastructure is ready but unused.

Detail of the phased follow-up plan: `TODO.md` `VCS-047` onward.
