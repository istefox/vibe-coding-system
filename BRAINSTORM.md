# BRAINSTORM — deep-refactor skill

**Date:** 2026-05-30
**Requirements source:** SPEC.md at /Users/stefanoferri/Developer/vibe-coding-system/SPEC.md
**Techniques applied:** first-principles, assumption-busting, cross-domain analogies (bank/ledger), alternatives synthesis, inversion/pre-mortem

---

## Reframed problem (first-principles)

The irreducible outcome is **a verifiably cleaner codebase** — not a report. Everything else
(dimensions, phases, batching, report format) is scaffolding in service of that outcome.
The report is a secondary artifact to explain what changed. Any design choice that prioritizes
report completeness over fix safety is inverted.

Irreducible constraints (physically true, not convention):
1. Can only verify safety via the test suite — no other signal is authoritative.
2. Files can only be safely modified if their behavior is observable through tests.
3. Some symbols that appear unused are alive at runtime (reflection, dynamic dispatch, `@objc`).
4. Concurrency bugs are not detectable by a unit test suite alone.

---

## Challenged assumptions

- **"Audit all dimensions before fixing anything"** — retained. Real constraint: a dead-code
  removal could delete a symbol that a perf-dimension fix was about to inline. Full scan first
  avoids cross-dimension conflicts.
- **"4 parallel specialist audit agents"** — retained. One generalist reviewer spreads too thin
  across dimensions. Parallel specialists = higher coverage, faster wall-clock time.
- **"Circuit breaker must be per-dimension"** — **dropped**. User chose global: any regression =
  full stop. Simpler to reason about, matches the "verifiably cleaner" goal. If one fix breaks
  something, trust is compromised for all remaining fixes.
- **"Dead-code removal is always safe if tests pass"** — **dropped** (pre-mortem risk 1). Tests
  pass even when `@objc`/dynamic/protocol-witness symbols are removed. This is a static analysis
  blind spot in Swift. Mandatory guard required.
- **"Performance fixes that pass tests are safe"** — **dropped** (pre-mortem risk 2). Async/
  actor/concurrency refactors can introduce races that unit tests won't catch. Mandatory guard
  required.

---

## Approach alternatives

### Alternative A — Dimension pipeline

**Idea:** Audit all 4 in parallel → HITL summary gate → fix entire dead-code batch → verify →
fix entire perf batch → verify → fix structure batch → verify → security report-only → commit.

**Axis of difference:** dimension is the scheduling unit for test runs.

**Pros:**
- Predictable: user knows exactly what phase ran vs what didn't if circuit breaker fires.
- Easy to communicate progress ("dead-code dimension complete, moving to perf").
- Simple orchestration: 3 sequential batches + 3 test runs.

**Cons:**
- A P1 performance finding is fixed AFTER all P3 dead-code findings — dimension order overrides
  severity.
- If circuit breaker fires on dead-code, nothing else gets fixed regardless of severity.

**Indicative cost/time:** medium — 3 test runs minimum.

---

### Alternative B — Severity-ordered ledger

**Idea:** Audit all 4 in parallel → merge findings, sort by P1→P2→P3 across all dimensions →
fix each finding atomically → verify after each → stop on first regression → commit all verified.

**Axis of difference:** severity is the scheduling unit (cross-dimension priority ordering).

**Pros:**
- Maximum value before failure: if circuit breaker fires at finding #7, the 6 most critical
  findings (across all dimensions) are already fixed and committed.
- Matches the bank/ledger model: each fix is a transaction; regression is a failed transaction.

**Cons:**
- Expensive: N findings = N test runs. 50 findings = ~50 minutes of `xcodebuild test`.
- No parallelism in fix phase. Hard to predict completion time.

**Indicative cost/time:** high — N test runs.

---

### Alternative C — Triage-first

**Idea:** Audit all 4 in parallel → present full findings list to user → user selects/deselects
specific findings → batch-fix approved set → verify once → commit.

**Axis of difference:** human is the scheduling unit (manual per-finding triage).

**Pros:** maximum control, no surprise fixes.

**Cons:** contradicts "full auto, minimal HITL" from SPEC. Doesn't scale on large codebases
(50 findings = 50 items to review). Regression detection happens too late (post-batch verify).

**Indicative cost/time:** low test cost, high user time cost.

---

### Alternative D — Hybrid (severity-bucketed dimension pipeline) ★ Recommended

**Idea:** Audit all 4 in parallel → HITL summary gate → for each dimension batch: sort findings
by severity (P1 first, then P2, then P3) → fix in that order → verify ONCE per dimension batch
→ global circuit breaker on red → commit all verified.

**Axis of difference:** dimension governs scheduling unit (test runs); severity governs fix
ORDER within each batch.

**Pros:**
- Predictable phases (from A) + priority awareness within phases (from B).
- Test run cost bounded at 3 (one per dimension), not N.
- Circuit breaker fires at a dimension boundary — clean state (whole dimension either landed or
  didn't).
- Critical findings in each dimension are fixed before lower-priority ones.

**Cons:**
- A P1 perf finding is still fixed after all dead-code findings (dimension order governs at
  the macro level). Not as pure as B's global severity ordering.

**Indicative cost/time:** medium — 3 test runs.

---

## Risks emerged (inversion / pre-mortem)

- **@objc / dynamic dispatch / protocol witnesses flagged as dead code** — tests pass, runtime
  crashes. Mitigation: dead-code dimension must tag these as `risk_level: high` → `fix_type:
  report-only`. The reviewer agent needs explicit Swift-specific instructions: detect `@objc`,
  `dynamic`, protocol conformances used only in `as?` casts, `#selector(...)`,
  `NSNotification.Name`-style string identifiers.

- **Async/actor/concurrency perf fixes introducing races** — unit tests pass, real device or
  load test fails. Mitigation: any perf finding touching `async`/`await`, `actor`,
  `DispatchQueue`, `Sendable`, `nonisolated` must be tagged `risk_level: high` → `fix_type:
  report-only`. Auto-fix only for synchronous perf patterns.

- **Circuit breaker fires mid-run, partial state committed without clarity** — Mitigation:
  when circuit breaker fires, commit everything verified up to that point, write a partial
  report clearly tagged `CIRCUIT BREAKER FIRED AT: <dimension>`. Remaining dimensions tagged
  `SKIPPED`. No silent partial state.

---

## Adjacent ideas emerged

- **Safe-mode dead-code flag** — mandatory guard (not future): dead-code dimension is
  REPORT-ONLY for all `@objc`, `dynamic`, protocol witnesses, and string-typed ObjC bridge
  identifiers. Must be in the initial skill design.
- **Concurrency-aware perf flag** — mandatory guard (not future): async/actor touching perf
  fixes are REPORT-ONLY in all cases. Must be in the initial skill design.
- **Dry-run mode** — future: full audit + fix simulation without writing files, produces a
  report of what WOULD change.
- **Scheduled cadence** — future: monthly maintenance cron via `/skill schedule`.

---

## Preliminary recommendation

**Alternative D (Hybrid)** is the most promising. Dimension-ordered phases give predictability
and bound test-run cost to 3 runs. Severity-ordered fixes within each batch ensure the most
critical issues land first before any circuit breaker fires. It combines A's predictability
with B's priority awareness, without B's O(N) test run cost.

The two mandatory guards must be explicit reviewer agent instructions, not post-hoc tagging:
(1) dead-code: `@objc`/dynamic/protocol-witness → report-only; (2) perf: async/actor/concurrency
patterns → report-only.

Preliminary — the architect should validate whether 3 test runs is acceptable for
target project sizes, and whether Workflow dispatch for the parallel audit phase is safe
given ADR-0016 hook propagation constraints.

---

## Notes for the architect

1. **Workflow vs Agent-tool dispatch:** parallel audit (4 agents) is the primary Workflow use
   case — no HITL needed, pure fan-out. Fix phase uses Agent-tool (sequential per dimension,
   HITL at summary gate only). Hybrid dispatch model recommended.
2. **@objc / dynamic detection (Swift):** reviewer agents need explicit pattern lists:
   `@objc`, `dynamic var/func`, protocol conformances in `as?` casts, `#selector(...)`,
   `NSNotification.Name`, bridged string identifiers. This is a language-specific blind spot
   not covered by generic dead-code heuristics.
3. **Circuit breaker partial commit:** architect must decide whether verified fixes before
   the breaker land in a single commit (atomic) or a commit-per-dimension (granular).
   Recommend commit-per-dimension for auditability.
4. **Finding deduplication:** same file + same line + overlapping description across dimensions
   → merge findings, keep the higher-severity tag. Prevents the same symbol being "fixed" twice
   by two dimension agents.
5. **Test run cost at scale:** 3 `xcodebuild test` runs on NotchDrop/CleanKey-scale projects
   ≈ 3-6 min. Acceptable. For larger projects, evaluate parallel test runs via worktree
   isolation between dimension batches.
