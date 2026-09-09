# ADR-0018 — deep-refactor skill: whole-codebase health audit with regression-safe incremental fix

**Status:** Accepted  
**Date:** 2026-05-30  
**Author:** istefox  
**Supersedes:** none  
**Superseded by:** none  
**Related:** ADR-0002 (refactor-snapshot harness — behavior-preservation contract the fix phase reuses), ADR-0003 (concept-to-code chain — Gate 5.1 insertion point)  

---

## Context

### The problem

The `review-triage-fix` (RTF) skill reviews and fixes the files changed by a single unit
of work — the diff produced in Step 5 of the concept-to-code chain, or a deliberate scope
the user points it at. It is intentionally narrow: review → triage → fix → re-review →
recap → STOP, on a bounded changeset.

What is missing is a **whole-codebase** maintenance pass: a periodic audit of the entire
source tree for accumulated technical debt that no single changeset would surface. Dead
code that lingers after a feature is removed, performance regressions spread across files,
oversized units that grew over many commits, and latent security issues (hardcoded
secrets, unguarded URL construction) are all invisible to a diff-scoped reviewer. On
working applications like NotchDrop and CleanKey, this debt compounds silently between
chain runs.

The irreducible outcome (per BRAINSTORM first-principles framing) is **a verifiably
cleaner codebase**, not a report. The report is a secondary artifact that explains what
changed. Any design that prioritizes report completeness over fix safety is inverted.

### Irreducible constraints

These are physically true, not conventions:

1. Safety can only be verified via the test suite. No other signal is authoritative.
2. A file can only be safely modified if its behavior is observable through tests.
3. Some symbols that appear unused are alive at runtime: Swift reflection, `dynamic`
   dispatch, `@objc`, protocol witnesses, `#selector`, string-typed ObjC bridge identifiers.
   A passing test suite does **not** prove these are dead.
4. Concurrency bugs (`async`/`actor`/`DispatchQueue`/`Sendable`/`nonisolated` races) are
   not detectable by a unit test suite alone. A perf fix that touches concurrency can pass
   all tests and still introduce a race.

Constraints 3 and 4 are the two **mandatory guards**: they are not future hardening, they
are part of the initial design. Violating either produces the worst failure mode for this
skill — a green test suite hiding a runtime crash or race that the skill itself introduced.

### Existing assets this skill reuses

- **Agents (unchanged):** `reviewer` (4 parallel dimension audits), `coder` / `refactorer`
  / `debugger` (fixes), all dispatched at `model: opus`. No new agent types (SPEC out-of-scope).
- **Workflow dispatch (ADR-0016):** `hook_verified=true` is confirmed on v2.1.156 with hook
  v1.3. The parallel fan-out audit phase (4 agents, no mid-run HITL) is the canonical
  Workflow use case. The fix phase deliberately does **not** use Workflow (see Decision).
- **test-cmd trust mechanism (ADR-0014):** `.claude/test-cmd` is the authoritative baseline
  signal, read exactly as RTF reads it.
- **Skill-standalone + chain-gate pattern (ADR-0011, ADR-0015):** a self-contained skill,
  invokable directly *and* wired into the c2c chain at a single gate. This is the 5th
  instance of this pattern; it is stable.
- **Circuit breaker vocabulary (RTF Step 0/3):** baseline GREEN/RED, abort-on-regression.
  deep-refactor uses a **global** circuit breaker (see Decision), simpler than RTF's
  per-fix A/B/D breakers.

### Assumptions (unvalidated at design time)

1. The audit reviewer agents, given explicit Swift-specific pattern lists, reliably tag
   `@objc`/`dynamic`/protocol-witness findings as `risk_level: high → fix_type: report-only`.
   This rests on prompt quality, validated by the pilot, not the harness.
2. Three `xcodebuild test` runs (one per fixable dimension) is acceptable wall-clock cost on
   NotchDrop/CleanKey-scale projects (~3-6 min total per BRAINSTORM note 5). Larger projects
   pay proportionally; the design does not parallelize test runs across dimensions in v1.
3. Workflow dispatch for the **audit** phase inherits the ADR-0016 `hook_verified` guarantee.
   Audit agents only Read (no Edit), so hook propagation matters less for them than for the
   fix phase — but the gating is kept identical for consistency and future-proofing.
4. The SPEC's per-dimension circuit breaker ("proceed to next dimension on red") is
   **superseded** by the brief's global circuit breaker. This ADR documents the global
   variant as the decision and notes the SPEC divergence explicitly (see Decision §Circuit
   breaker and Consequences/Neutral).

---

## Decision

Introduce a new skill at `~/.claude/skills/deep-refactor/SKILL.md` implementing the
**Hybrid severity-bucketed dimension pipeline** (BRAINSTORM Alternative D): audit all four
dimensions in parallel, gate on a findings summary, then fix dimension-by-dimension with
severity-ordered fixes inside each dimension and one test run per dimension, under a single
global circuit breaker. Wire it into concept-to-code as **Gate 5.1** (after RTF / Gate 5,
before Gate 5.5 / Step 7). No new agents; no changes to existing agents, hooks, or the RTF
skill.

### Dispatch model (hybrid, per BRAINSTORM note 1)

- **Audit phase — parallel fan-out.** Four `reviewer` dimension agents (dead-code, perf,
  structure, security) dispatched in parallel. **Workflow dispatch when `hook_verified=true`**
  in the manifest (or via a standalone environment probe); **sequential Agent-tool fallback**
  otherwise. Pure fan-out, no mid-run HITL — the canonical Workflow case.
- **Fix phase — sequential Agent-tool, never Workflow.** Two reasons make Workflow wrong here:
  (1) the fix phase must pause at the Gate 1 findings-summary HITL between audit and fix, and
  Workflow has no mid-run user input (ADR-0016); (2) fixes mutate the shared codebase, so
  parallel fixes within a dimension risk edit conflicts (RTF "dispatch always sequential"
  invariant). Each fix is an Agent-tool dispatch at `model: opus` with the coder's ADR-0001
  Pre-flight Pattern Classifier (`PATTERN:`) and the pattern-enforce hook intact.

### The Hybrid pipeline (Alternative D)

```
Phase 0  Pre-flight (blocking)
         git repo? → baseline commit hash → read .claude/test-cmd
         test-cmd NONE/absent OR baseline RED → report-only mode (no fix, no source commit)
         enumerate source files via git ls-files (excludes generated/build artifacts)
         HITL Gate 0 — approval to start
Phase 1  Parallel audit (Workflow if hook_verified else sequential)
         4 reviewer agents → merged Finding[] JSON
         dedup (same file+line+overlap → keep higher severity)
         HITL Gate 1 — findings summary; choose fix-all | report-only | abort
Phase 2  Fix loop, dimension order: dead-code → perf → structure
         for each dimension:
           sort findings by severity P1→P2→P3
           dispatch fix agents sequentially (coder/refactorer/debugger), opus
           skip report-only and risk_level:high findings
           run test-cmd ONCE
             GREEN → commit-per-dimension, continue
             RED   → GLOBAL CIRCUIT BREAKER: stop all remaining fixes
Phase 3  Security = report-only ALWAYS (never auto-fixed)
Phase 4  Write report, stage, HITL Gate 2 — commit approval
```

**Scheduling axis:** dimension governs the test-run unit (3 runs max, not O(N)); severity
governs fix order *within* each dimension batch (critical findings land first).

### Mandatory guards (hard constraints, in the initial design)

These are explicit reviewer-agent prompt instructions in SKILL.md, not post-hoc tagging:

1. **Dead-code guard.** The dead-code reviewer MUST tag as `risk_level: high → fix_type:
   report-only` any symbol matching: `@objc`, `dynamic var/func`, protocol conformances used
   only in `as?` casts, `#selector(...)`, `NSNotification.Name` / string-typed ObjC bridge
   identifiers, and anything reachable only via reflection or protocol witness. These are a
   static-analysis blind spot: tests pass, runtime crashes.
2. **Concurrency-aware perf guard.** The perf reviewer MUST tag as `risk_level: high →
   fix_type: report-only` any finding touching `async`/`await`, `actor`, `DispatchQueue`,
   `Sendable`, `nonisolated`, or any concurrency primitive. Auto-fix is allowed only for
   synchronous perf patterns. Unit tests do not catch the races these refactors can introduce.

`risk_level: high` is a hard skip in the fix loop regardless of `fix_type`. The skill never
auto-fixes a high-risk finding.

### Global circuit breaker (supersedes SPEC's per-dimension breaker)

Any RED test run during the fix loop fires the **global** circuit breaker: stop all
remaining fixes across all remaining dimensions immediately. Rationale (BRAINSTORM): if one
fix breaks the suite, trust in the unverified remaining fixes is compromised; a global stop
is simpler to reason about and matches the "verifiably cleaner" goal. On fire:

- Commit everything verified up to the breaker (commit-per-dimension granularity, BRAINSTORM
  note 3 — auditability over atomicity).
- Write a **partial report** tagged `CIRCUIT BREAKER FIRED AT: <dimension>`; remaining
  dimensions tagged `SKIPPED`. No silent partial state.
- Auto mode is active for this chain — there is no intermediate HITL to confirm the stop; the
  breaker fires deterministically and the partial report records it.

This diverges from SPEC §Phase 2.3 ("proceed to next dimension on red"). The brief is
authoritative: global stop. The SPEC text is treated as superseded and the divergence is
recorded here.

### Pre-flight report-only fallback

If `.claude/test-cmd` is `NONE`/absent, or the baseline run is RED (including Xcode
codesign-bound tests that fail without a signed bundle), the skill **blocks all auto-fix**
and runs in report-only mode: audit + report, no source edits, only the report file
committed. There is no verifiable baseline, so no fix is safe to apply (irreducible
constraint 1). This mirrors RTF Circuit Breaker D and is non-negotiable.

### Gate 5.1 integration into concept-to-code

A new gate inserted in `~/.claude/skills/concept-to-code/SKILL.md` between Gate 5 (review
cycle) and Gate 5.5 (humanize) / Step 7 (commit). After RTF completes or is skipped at Gate
5, an `AskUserQuestion` offers "Run deep-refactor" or "Skip". "Run" invokes
`/skill deep-refactor` via the Skill tool, then transitions to Gate 5.5 / Step 7. "Skip" is
a silent no-op preserving the existing path exactly (zero regression to chain runs that
decline it). Under Auto mode this gate still pauses, because it is an `AskUserQuestion`
(per the `feedback_automode-gate-bypass` finding: only `AskUserQuestion` forces a pause;
text-box gates are bypassed silently in Auto mode).

### Testability (honest, per the project's standing pattern)

The harness (`tests/run-tests.sh`) tests **structural anchors** in SKILL.md — pure,
deterministic grep assertions that required contracts are present: the two mandatory guards,
the global circuit-breaker tag string, the report-only fallback, the four dimensions, the
Gate 5.1 insertion in c2c SKILL.md, and the dispatch-mode split (Workflow audit / Agent fix).
Any helper script under `scripts/` (e.g. source-file enumeration) gets unit tests with the
RTF `ok`/`bad` reporter idiom. The harness does **not** and cannot test runtime behavior
(agent judgment, real fixes, real circuit-breaker firing) — that is what the **pilot**
validates on a real project (NotchDrop or CleanKey). This is the project's established
honest-testability split.

---

## Alternatives considered

### Alternative A — Dimension pipeline (pure)

Audit all four in parallel → HITL summary → fix the entire dead-code batch → verify → fix
the entire perf batch → verify → fix structure → verify → security report-only → commit. The
dimension is the only scheduling unit; findings inside a dimension are fixed in arbitrary
(or file-grouped) order.

**Rejected because:** it loses priority awareness inside a dimension. A P1 structural finding
is fixed in the same undifferentiated batch as P3 ones, so if a fix early in the batch trips
the circuit breaker, a more critical finding later in the same dimension never lands. The
predictability A offers (clean dimension boundaries, bounded 3 test runs) is real and worth
keeping — which is exactly why the chosen Hybrid *inherits* A's dimension-as-test-unit
structure and adds severity ordering on top. A on its own is strictly dominated by the
Hybrid: same cost, less value-before-failure.

### Alternative B — Severity-ordered ledger

Audit all four in parallel → merge findings → sort globally by P1→P2→P3 *across all
dimensions* → fix each finding atomically → run test-cmd after **every** finding → stop on
first regression → commit all verified. The bank/ledger model: each fix is a transaction, a
regression is a failed transaction, and value-before-failure is maximized because the N most
critical findings (across all dimensions) land first.

**Rejected because:** the test-run cost is O(N). On an Xcode project, `xcodebuild test`
dominates wall-clock time; 50 findings means ~50 test runs (~50 minutes per BRAINSTORM
estimate), which is operationally unacceptable for a maintenance pass meant to run between
chain steps. B also forbids any parallelism and makes completion time unpredictable. The
Hybrid recovers most of B's value-before-failure benefit (severity ordering inside each
dimension means the most critical findings in each dimension land first) while bounding test
cost at 3 runs. The only thing lost versus B is *cross-dimension* global severity ordering —
a P1 perf finding still waits for all dead-code fixes — which is an acceptable trade for a
~16x reduction in test-run cost.

### Alternative C — Triage-first (human-scheduled)

Audit all four in parallel → present the full findings list to the user → the user
selects/deselects specific findings → batch-fix the approved set → verify once → commit. The
human is the scheduling unit.

**Rejected because:** it contradicts the brief's "Auto mode active, no intermediate HITL"
constraint and the SPEC's "full auto, minimal HITL" goal. Per-finding manual triage does not
scale — 50 findings is 50 checkboxes — and it pushes regression detection to a single
post-batch verify, so a regression is discovered only after the whole approved set is applied,
with no way to attribute which fix caused it. C maximizes control at the cost of throughput
and late, coarse regression detection, the opposite of the design goals. The two HITL gates
the Hybrid keeps (Gate 1 fix/report/abort decision, Gate 2 commit approval) provide
sufficient control without per-finding micromanagement.

### Alternative D — Hybrid severity-bucketed dimension pipeline (chosen)

Audit all four in parallel → HITL summary gate → for each dimension batch, sort findings by
severity (P1→P2→P3), fix in that order, run test-cmd **once** per dimension, global circuit
breaker on red → commit-per-dimension. Dimension governs the test-run scheduling unit;
severity governs fix order within each batch.

**Chosen because:** it is the only alternative that simultaneously (1) bounds test-run cost
to 3 runs (from A), (2) preserves priority awareness so critical findings land first (from
B), and (3) gives clean circuit-breaker boundaries — a dimension either lands whole or not,
so the committed state is always coherent. It fits the project's safety-first posture: the
two mandatory guards live in the audit prompts, the global breaker gives a single simple stop
rule, and the report-only fallback covers the unverifiable-baseline case. Its one weakness —
no cross-dimension global severity ordering — is the cheapest concession available and does
not compromise safety.

---

## Consequences

### Positive

- **Whole-codebase coverage** that no diff-scoped reviewer (RTF) can provide: dead code,
  performance, structure, and security across the entire source tree in one invocation.
- **Bounded test cost.** At most 3 `xcodebuild test` runs (one per fixable dimension),
  regardless of finding count — ~3-6 min on NotchDrop/CleanKey-scale projects.
- **Value-before-failure.** Severity ordering inside each dimension means the most critical
  findings in a dimension are fixed before lower-priority ones; if the global breaker fires,
  the most valuable fixes have already landed and been committed.
- **Safety guards are structural, not advisory.** The two mandatory guards (@objc/dynamic dead
  code; async/concurrency perf) are explicit reviewer-prompt instructions tested by the
  harness as structural anchors. Security is *always* report-only. High-risk findings are a
  hard skip. The worst failure mode (green tests hiding a runtime crash/race the skill caused)
  is designed out, not patched after the fact.
- **Pattern reuse, zero blast radius on existing assets.** No new agents, no edits to
  reviewer/coder/refactorer/debugger, no edits to RTF, hooks, or settings. The only edit to an
  existing file is the additive Gate 5.1 block in c2c SKILL.md, whose "Skip" path is a verbatim
  no-op preserving today's behavior.
- **Fallback-safe dispatch.** Audit uses Workflow when `hook_verified=true`, sequential
  Agent-tool otherwise — degraded but correct on environments where workflows are unavailable
  (ADR-0016 fallback pattern, 6th instance of fail-safe-default).
- **No silent partial state.** A fired circuit breaker commits verified fixes per dimension and
  writes a partial report tagged `CIRCUIT BREAKER FIRED AT: <dimension>` with remaining
  dimensions `SKIPPED`.

### Negative / risks

- **Audit quality depends on reviewer prompt fidelity.** The mandatory guards are only as good
  as the Swift-specific pattern lists in the audit prompts. If the dead-code reviewer misses a
  `dynamic` form, or the perf reviewer misses a concurrency primitive, a high-risk finding
  could be mistagged `low` and auto-fixed. The harness verifies the *instructions are present*
  (structural anchor) but cannot verify the agent *obeys* them — only the pilot can. This is the
  highest-residual risk and the reason a pilot on a real Swift project is mandatory before
  production use.
- **Global circuit breaker can leave a dimension unattended.** A red test on the first perf fix
  stops perf *and* structure entirely. This is intentional (trust compromised) but means a
  single bad fix can block a lot of safe work. Mitigation: severity ordering ensures the most
  valuable findings in the failing dimension already landed; the partial report names the
  exact dimension and finding so the user can re-run after addressing it.
- **Three test runs may be expensive on large projects.** For projects much larger than
  CleanKey/NotchDrop, three `xcodebuild test` runs could be slow. v1 does not parallelize test
  runs across dimensions (BRAINSTORM note 5 flags worktree-isolated parallel test runs as
  future work). Acceptable for the target project sizes; revisit if a large project is onboarded.
- **Report-only mode is silent for unverifiable codebases.** Projects without a `.claude/test-cmd`
  (or with codesign-bound tests) get a report and no fixes. This is correct (no baseline = no
  safe fix) but means the skill delivers less value precisely where debt may be highest. The
  Gate 0/Gate 1 messaging must make this explicit so the user understands why nothing was fixed.
- **Workflow audit inherits ADR-0016 fragility.** The keyword trigger is implicit and the
  research-preview feature can change. Audit agents only Read, so the blast radius is smaller
  than the fix phase, and the sequential fallback is always correct — but a silent degradation
  to sequential mode (slower) is possible without the user noticing.
- **Dedup heuristic is approximate.** "Same file + same line + overlapping description → keep
  higher severity" can over-merge (two genuinely distinct findings on the same line) or
  under-merge (the same symbol flagged at different lines by two dimensions). The cost of a
  miss is low (a finding fixed twice is caught by the per-dimension test run, or simply
  re-reported), so an approximate heuristic is acceptable in v1.

### Neutral

- **SPEC divergence on the circuit breaker is recorded, not silent.** SPEC §Phase 2.3 specifies
  a per-dimension breaker (continue to next dimension on red); the brief specifies a global
  breaker. The global variant is implemented; the SPEC text is superseded by this ADR. Anyone
  reading the SPEC must treat this ADR as authoritative on breaker scope.
- **Commit granularity is per-dimension, not atomic** (BRAINSTORM note 3), trading a single
  clean commit for auditability — each dimension's fixes are a separate commit so a reviewer can
  see what each dimension changed and revert one without the others.
- **The skill is invocable standalone and via the chain** with identical internal behavior; the
  only difference is the entry point (direct `/skill deep-refactor` vs Gate 5.1 Skill-tool call).
- **No manifest schema change.** deep-refactor reads `hook_verified` (already additive in schema
  1.3 per ADR-0016) and `.claude/test-cmd`; it introduces no new manifest fields.
- **Report lives in the target repo** at `<project-root>/docs/deep-refactor/YYYY-MM-DD-<slug>.md`,
  created if absent, and is committed alongside the code changes.

---

## References

- SPEC.md: `/Users/stefanoferri/Developer/vibe-coding-system/SPEC.md`
- BRAINSTORM.md: `/Users/stefanoferri/Developer/vibe-coding-system/BRAINSTORM.md` (Alternative D
  recommended; mandatory guards; pre-mortem risks)
- ADR-0001: coder Pre-flight Pattern Classifier (`PATTERN:` contract, preserved in fix dispatch)
- ADR-0004: pre-flight pattern-enforce hook (fires in fix-phase Agent dispatch and Workflow
  subagents via hook v1.3)
- ADR-0011: clean-public-repo + anonymize (skill-standalone + chain-gate pattern; fallback-safe
  conditional dispatch)
- ADR-0014: architect proposes test-cmd (`.claude/test-cmd` trust mechanism, read as baseline)
- ADR-0015: humanize-en chain integration (Gate 5.5 neighbor; gate-insertion convention)
- ADR-0016: Dynamic Workflows Step 5 (`hook_verified=true` on v2.1.156 + hook v1.3; Workflow
  fan-out + Agent-tool fallback; smoke-test gate)
- review-triage-fix SKILL.md: baseline GREEN/RED, circuit-breaker vocabulary, sequential-dispatch
  invariant, `verify.sh` reporter idiom (`~/.claude/skills/review-triage-fix/`)
- MEMORY.md `feedback_automode-gate-bypass`: only `AskUserQuestion` pauses under Auto mode
- MEMORY.md `feedback_coder-worktree-subdirectory`: isolation:none pre-check on non-git roots
- concept-to-code SKILL.md §5: Gate 5 / Gate 5.5 region (Gate 5.1 insertion point)

## Correction (2026-09-08)

`deep-refactor` has been retired from this repo's vendored PAIRS surface and now lives at
`github.com/istefox/Skills` (`Deep_refactor`), symlinked at `~/.claude/skills/deep-refactor` —
the same pattern ADR-0191 already established for `project-tasks`. The canonical source for the
skill this ADR designed is that external repository, not `staging/plugin/skills/deep-refactor/`
in this one. `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh` and its test are
retained here at their original paths as a declared `contract-reference:`, never as a deploy
source. See `docs/architecture/ADR-0197-deep-refactor-migrated-to-istefox-skills.md` (Accepted
2026-09-07) for the migration decision; this note does not alter the design recorded above
(rule 14).
