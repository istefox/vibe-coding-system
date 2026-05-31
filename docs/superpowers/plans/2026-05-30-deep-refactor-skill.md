# deep-refactor skill — whole-codebase health audit (TDD Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement task-by-task. Steps use
> checkboxes (`- [ ]`).

**Changelog:**
- v1.0 (2026-05-30): initial — derived from `ADR-0018-deep-refactor-skill.md`, `SPEC.md`,
  `BRAINSTORM.md`. 8 tasks: T1 skill scaffold + frontmatter, T2 Phase 0 pre-flight +
  report-only fallback, T3 Phase 1 audit dispatch (Workflow/Agent split) + mandatory guards,
  T4 Phase 2 fix loop + global circuit breaker, T5 Phase 3/4 report + commit gate,
  T6 source-enumeration helper script (bash 3.2) + unit tests, T7 Gate 5.1 integration into
  c2c SKILL.md + c2c harness anchor, T8 deep-refactor structural-anchor harness.

**Goal:** create `~/.claude/skills/deep-refactor/SKILL.md` — a standalone skill that audits an
entire codebase across four dimensions (dead-code, perf, structure, security), auto-fixes
low/medium-risk findings dimension-by-dimension under a global circuit breaker, and commits a
findings report alongside the changes. Wire it into concept-to-code as Gate 5.1.

**Architecture:** Hybrid severity-bucketed dimension pipeline (ADR-0018 / BRAINSTORM Alt D).
Audit = 4 parallel `reviewer` agents (Workflow if `hook_verified=true`, else sequential
Agent-tool). Fix = sequential Agent-tool per dimension at `model: opus`, severity-ordered,
one test run per dimension, global circuit breaker on any red. Two mandatory guards
(@objc/dynamic dead-code → report-only; async/concurrency perf → report-only). Security =
always report-only. Report at `<root>/docs/deep-refactor/YYYY-MM-DD-<slug>.md`.

**ADR:** `docs/architecture/ADR-0018-deep-refactor-skill.md` (Proposed 2026-05-30).
**SPEC:** `/Users/stefanoferri/Developer/vibe-coding-system/SPEC.md`.
**BRAINSTORM:** `/Users/stefanoferri/Developer/vibe-coding-system/BRAINSTORM.md`.

---

## Environment notes (read first)

- **Implementation target: `~/.claude/skills/deep-refactor/` and
  `~/.claude/skills/concept-to-code/SKILL.md` (NOT the vibe-coding-system doc repo).** The doc
  repo holds only the ADR and this plan. Never edit source under the doc repo.
- **No git in `~/.claude/`.** Per-task checkpoint = harness green + report. No commit step here.
- **Bash 3.2-clean for all scripts** (`~/.claude` runs bash 3.2.57): no assoc arrays, no
  `mapfile`, no `${v^^}`, no process substitution, no here-strings `<<<`. Use `grep -Eq`,
  `case`, `[ -f ]`, temp-file maps, the `ok`/`bad` reporter idiom.
- **No new agents.** reviewer/coder/refactorer/debugger invoked as-is at `model: opus`.
- **Do NOT edit:** any agent file, any hook (pattern-enforce, stop-gate, db-backup-guardrail),
  `settings.json`, `.mcp.json`, the RTF skill, the `commit` skill, `manifest-init.sh`
  (no new manifest fields — `hook_verified` already exists per ADR-0016).
- **Only existing-file edit:** the additive Gate 5.1 block in `concept-to-code/SKILL.md`
  (T7). Its "Skip" path MUST be a verbatim no-op preserving today's Gate 5 → Gate 5.5 / Step 7
  flow — zero regression to runs that decline deep-refactor.
- **Anchor preservation HARD.** Baseline before T7: `concept-to-code PASS=32 FAIL=0` (confirm
  with `bash ~/.claude/skills/concept-to-code/tests/run-tests.sh`). Do not regress it; T7 adds
  anchors (new PASS count is higher, never lower).

---

## Observable-contract note (grep before T7)

T7 inserts a new gate into a live chain skill. Before editing, the implementer MUST grep the
c2c SKILL.md for the Gate 5 / Gate 5.5 transition wiring so the insertion is surgical:

```
grep -n "Gate 5\|Gate 5.5\|review-triage-fix\|step_7_commit\|gate_5_review_decision" \
  ~/.claude/skills/concept-to-code/SKILL.md
```

Known call-sites (from architect grep, 2026-05-30):
- Line ~1209-1227 — Gate 5 block; "Skip review" and "Run review-triage-fix" both currently
  flow to "evaluate Gate 5.5". Gate 5.1 inserts **between** these outcomes and Gate 5.5.
- Line ~1231-1254 — Gate 5.5 block (humanize); Gate 5.1's continuation targets this.
- Line ~166-167 — state-machine transition list (`gate_5_review_decision → ... → step_7_commit`):
  verify whether Gate 5.1 needs a transition entry or rides inside `gate_5_review_decision`
  (recommend: keep it inside the Gate 5 → Gate 5.5 hop, NO new state — it is an optional sub-gate,
  mirroring how Gate 5.5 is conditional without its own state).
- Line ~1258-1279 — Coexistence invariants list: add a line documenting deep-refactor is
  invoked at Gate 5.1 and does not modify any agent/hook.

After T7, run the **full** c2c harness (not just the new anchors) — a gate edit can break
unrelated transition-wiring anchors that share the same strings.

---

## Tasks

### T1 — Skill scaffold + frontmatter
- [ ] Create `~/.claude/skills/deep-refactor/SKILL.md` with YAML frontmatter (`name:
      deep-refactor`, `description:` with explicit trigger phrases: "deep-refactor", "codebase
      health audit", "full refactor audit", "whole-codebase cleanup"; and a NEGATIVE trigger
      steering quick findings-only requests to `review-triage-fix` / built-in code-review, and
      diff-scoped fixes to RTF).
- [ ] Add "Hard constraints (read first)" section mirroring RTF: orchestrator-session only
      (sub-agents do not spawn sub-agents → stop if invoked from a sub-agent); dispatch always
      sequential in the FIX phase; skill isolation (no superpowers checks mid-cycle); STOP/commit
      only via Gate 2.
- [ ] State the four dimensions and the `model: opus` requirement for all dispatched agents.
- **Contract:** new file. No changes to existing contracts.

### T2 — Phase 0 pre-flight + report-only fallback
- [ ] Write Phase 0: `git rev-parse --git-dir` check (abort if not a repo); **isolation:none
      pre-check** if project_root is a non-git subdirectory (per `feedback_coder-worktree-subdirectory`
      — never dispatch fix agents with worktree on a non-git root); capture baseline commit hash;
      read `.claude/test-cmd`.
- [ ] Report-only fallback (hard): if test-cmd is `NONE`/absent OR baseline run is RED (incl.
      Xcode codesign-bound failure), BLOCK all auto-fix → report-only mode (audit + report, no
      source edits, only report committed). Present the block explicitly at Gate 0.
- [ ] Enumerate source files via `git ls-files`, excluding `*.xcarchive`, `DerivedData/`,
      `Pods/`, `.build/`, `*.generated.swift` (delegate to T6 helper).
- [ ] **HITL Gate 0** via `AskUserQuestion` (Proceed / Abort) showing root, file count, baseline
      PASS/FAIL, dimensions, and a dirty-working-tree warning if `git status` is non-empty.
- **Contract:** defines the baseline + report-only gate. Anchor strings the harness will check:
  the report-only fallback phrase and the `git ls-files` enumeration.

### T3 — Phase 1 audit dispatch + mandatory guards
- [ ] Write Phase 1: dispatch 4 `reviewer` dimension agents. **Dispatch split:** Workflow
      (parallel fan-out, "workflow" keyword) when `hook_verified=true`; sequential Agent-tool
      fallback otherwise. Document both branches explicitly.
- [ ] Each audit agent returns the **Finding schema** JSON (SPEC Data Model). Merge + dedup
      (same file+line+overlapping description → keep higher severity). Sort dead-code → perf →
      structure → security, then P1→P2→P3.
- [ ] **MANDATORY GUARD 1 (dead-code):** explicit reviewer instruction — tag as `risk_level:
      high → fix_type: report-only` any `@objc`, `dynamic var/func`, protocol conformances used
      only in `as?` casts, `#selector(...)`, `NSNotification.Name`/string-typed ObjC bridge
      identifiers, reflection-reachable, protocol-witness symbols.
- [ ] **MANDATORY GUARD 2 (perf):** explicit reviewer instruction — tag as `risk_level: high →
      report-only` any finding touching `async`/`await`/`actor`/`DispatchQueue`/`Sendable`/
      `nonisolated`. Auto-fix only synchronous perf patterns.
- [ ] **HITL Gate 1** via `AskUserQuestion`: findings summary (per-dimension counts + severity
      breakdown + routable total); options "Fix all routable" / "Report only" / "Abort".
- **Contract:** the two guard instruction blocks and the dispatch-split are the load-bearing
  anchors. Security high-risk and all guard-tagged findings are report-only downstream.

### T4 — Phase 2 fix loop + global circuit breaker
- [ ] Write Phase 2: dimension order dead-code → perf → structure (security never fixed). For
      each dimension: sort by severity P1→P2→P3, dispatch fix agents **sequentially** at
      `model: opus` by `fix_type` (coder with micro-piano / refactorer / debugger); **skip** any
      `report-only` or `risk_level: high` finding (→ deferred/report-only section).
- [ ] After each dimension's fixes: run `.claude/test-cmd` ONCE. GREEN → commit-per-dimension
      (auditability, BRAINSTORM note 3), continue. RED → **GLOBAL CIRCUIT BREAKER**: stop ALL
      remaining fixes across ALL remaining dimensions; commit verified fixes up to the breaker;
      tag the report `CIRCUIT BREAKER FIRED AT: <dimension>`; mark remaining dimensions `SKIPPED`.
- [ ] Preserve the ADR-0001 `PATTERN:` pre-flight contract in every coder dispatch (do not
      suppress it); the pattern-enforce hook fires unchanged.
- **Contract:** the exact tag string `CIRCUIT BREAKER FIRED AT:` is a harness anchor (matches
  the brief). Global (not per-dimension) breaker — this SUPERSEDES SPEC §Phase 2.3; note the
  divergence inline in SKILL.md referencing ADR-0018.

### T5 — Phase 3/4 report + commit gate
- [ ] Write Phase 3: security report-only section (all security findings, file/line/description/
      suggested remediation, tag `ACTION REQUIRED — not auto-fixed`).
- [ ] Write Phase 4: write report to `<root>/docs/deep-refactor/YYYY-MM-DD-<slug>.md` (create
      dir if absent) per the SPEC Report schema — baseline vs post-fix PASS/FAIL, fixed/deferred/
      report-only counts, regressions caught, per-dimension findings. Handle edge cases: 0
      findings → "Codebase is clean across all dimensions", exit without committing; all
      report-only → commit report file only.
- [ ] **HITL Gate 2** via `AskUserQuestion`: Approve-and-commit / Stage-only / Abort. On approve
      → invoke `commit` skill with context-hint `"deep-refactor: <project> audit"`. On abort →
      `git reset HEAD` (unstage), leave working tree.
- **Contract:** report path/schema + Gate 2 options are anchors. Commit only via the `commit`
  skill after explicit user click (never self-commit).

### T6 — Source-enumeration helper + unit tests (bash 3.2)
- [ ] Create `~/.claude/skills/deep-refactor/scripts/enumerate-sources.sh <root> [<path-override>]`:
      `git ls-files` honoring `.gitignore`, apply the exclude globs (T2 list), apply optional
      path-override glob/dir. Bash 3.2-clean. Reporter style: print one path per line; print
      nothing on empty (caller handles 0-files).
- [ ] Create `~/.claude/skills/deep-refactor/tests/enumerate-sources.test.sh` with the RTF
      `ok`/`bad` idiom in an isolated `mktemp -d` repo: asserts exclude globs filter out
      `DerivedData/`/`Pods/`/`*.generated.swift`; path-override restricts scope; non-git dir →
      empty/error path.
- **Contract:** new pure helper + tests. No existing contract touched.

### T7 — Gate 5.1 integration into concept-to-code SKILL.md
- [ ] Run the grep from the "Observable-contract note" above; confirm the Gate 5 / Gate 5.5
      insertion point.
- [ ] Insert a **Gate 5.1** block in `~/.claude/skills/concept-to-code/SKILL.md` AFTER the Gate
      5 outcomes and BEFORE Gate 5.5, using `AskUserQuestion` (per `feedback_automode-gate-bypass`:
      only AskUserQuestion pauses under Auto mode): options "Run deep-refactor" /
      "Skip (proceed to commit)". "Run" → invoke `/skill deep-refactor` (Skill tool), then
      transition to Gate 5.5 / Step 7. "Skip" → silent no-op, proceed to Gate 5.5 / Step 7
      exactly as today.
- [ ] Update both Gate 5 outcome lines so "Skip review" and "Run review-triage-fix" flow to
      "evaluate Gate 5.1" (which then flows to Gate 5.5), preserving the chain order.
- [ ] Add a line to the Coexistence-invariants list (~line 1258+) documenting deep-refactor is
      invoked at Gate 5.1 and modifies no agent/hook/RTF.
- [ ] Decide state-machine wiring: keep Gate 5.1 inside the existing Gate 5 → Gate 5.5 hop with
      NO new manifest state (mirror Gate 5.5's conditional, state-less design).
- [ ] **Run the FULL c2c harness** (`bash ~/.claude/skills/concept-to-code/tests/run-tests.sh`)
      — not only the new anchor — to confirm no existing transition-wiring anchor regressed.
- **Contract:** CHANGES the c2c chain's gate sequence (observable contract). Add a c2c harness
  anchor asserting the Gate 5.1 block + "Skip" no-op path exist. Full harness must stay GREEN at
  the new (higher) PASS count.

### T8 — deep-refactor structural-anchor harness
- [ ] Create `~/.claude/skills/deep-refactor/tests/run-tests.sh` (bash 3.2, `ok`/`bad` idiom)
      asserting SKILL.md contains the load-bearing structural anchors: (a) four dimensions named;
      (b) MANDATORY GUARD 1 `@objc`/`dynamic`/protocol-witness → report-only; (c) MANDATORY GUARD
      2 async/concurrency → report-only; (d) global circuit-breaker tag `CIRCUIT BREAKER FIRED AT:`;
      (e) report-only fallback for absent/RED baseline; (f) dispatch split (Workflow audit when
      `hook_verified`, Agent-tool fix sequential); (g) security ALWAYS report-only; (h) Gate 0 /
      Gate 1 / Gate 2 AskUserQuestion gates; (i) `commit`-skill-only commit (no self-commit);
      (j) report path `docs/deep-refactor/`. Source the T6 enumerate-sources tests so one
      `run-tests.sh` invocation runs the whole suite.
- [ ] Print a final `PASS=N FAIL=M` line (vibe-status / harness-runner compatible).
- **Contract:** new harness. This is the `TEST-CMD CANDIDATE`. Honest-testability boundary:
  structural anchors only; runtime behavior validated by the pilot, not here.

---

## Definition of done

- [ ] `bash ~/.claude/skills/deep-refactor/tests/run-tests.sh` → `PASS=N FAIL=0`.
- [ ] `bash ~/.claude/skills/concept-to-code/tests/run-tests.sh` → GREEN at a PASS count ≥ 32
      (new Gate 5.1 anchor added, nothing regressed).
- [ ] SKILL.md contains both mandatory guards, the global circuit-breaker tag, the report-only
      fallback, and the Workflow-audit / Agent-fix dispatch split.
- [ ] Gate 5.1 "Skip" path is a verbatim no-op (no behavior change to declining chain runs).
- [ ] No edits to any agent, hook, settings, `.mcp.json`, RTF, commit skill, or `manifest-init.sh`.
- [ ] All `scripts/` helpers are bash 3.2-clean.
- [ ] **Pilot (post-merge, manual, NOT in this plan):** run `/skill deep-refactor` on NotchDrop
      or CleanKey to validate runtime behavior — guard tagging on real Swift, circuit-breaker
      firing, report accuracy. The harness cannot cover these.
