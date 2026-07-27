# Project: vibe-coding-system

## Overview
Auto-generated roadmap from issues labeled `prep` (ADR-0023).

## Phases

### Phase 1 — prep
- [x] Vendor deployed-only skills and hooks into staging  (issue #28)  (completed: 2026-07-11)
- [x] Refresh stale staging copies from the deployed tree  (issue #29)  (completed: 2026-07-11)
- [x] clean-public-repo: keep private history out of the public branch  (issue #30)  (completed: 2026-07-11)
- [x] concept-to-code: BSD-safe slug stamp and autopilot gate fixes  (issue #31)  (completed: 2026-07-11)
- [x] Manifest helpers: count guards, exit codes, YAML escaping  (issue #32)  (completed: 2026-07-11)
- [x] hook-verify-workflow: filter the audit window by session  (issue #33)  (completed: 2026-07-11)
- [x] Scope guards: autopilot CWD check, conductor glob, nightly check 6  (issue #34)  (completed: 2026-07-11)
- [x] refactor-snapshot filter append and deep-refactor scope glob  (issue #35)  (completed: 2026-07-11)
- [x] claude-md-slim: whole-line content union check  (issue #36)  (completed: 2026-07-11)
- [x] vibe-status: recursion guard and active-chains wiring  (issue #37)  (completed: 2026-07-11)
- [x] Hook hardening: enum value, lock ownership, trust hash  (issue #38)  (completed: 2026-07-11)
- [x] Skill text corrections across five standalone skills  (issue #39)  (completed: 2026-07-11)
- [x] Agent tool scoping per blueprint section 3  (issue #40)  (completed: 2026-07-11)

### Phase 2 — agentic-spec integration (report: docs/books/INTEGRATION-REPORT-agentic-spec.md)
- [x] Secrets and dependency gate: content scan, lockfile check, CI steps  (issue #100)  (completed: 2026-07-26)
- [x] Wire the anti-test-weakening detector into every unattended path  (issue #101)  (completed: 2026-07-26)
- [x] Requirement IDs in SPEC and a coverage check  (issue #102)  (completed: 2026-07-26)
- [x] Generator/verifier separation: dispatch the tester, deny coder test writes  (issue #103)  (completed: 2026-07-26)
- [x] Recovery-readiness pre-flight for concept-to-code Step 5  (issue #104)  (completed: 2026-07-26)
- [x] Reward-hacking detectors: literal assertions, deleted symbols, swallowed errors  (issue #105)  (completed: 2026-07-26)
- [x] Per-task diff budget and scope check  (issue #106)  (completed: 2026-07-26)
- [x] Interface immutability gate  (issue #107)  (completed: 2026-07-26)
- [x] Run the deterministic checks in the target project CI  (issue #108)  (completed: 2026-07-26)
- [x] Proportional audit depth: risk and task_type axes  (issue #109)  (completed: 2026-07-26)
- [x] SAST job and a security-audit skill  (issue #110)  (completed: 2026-07-26)
- [x] Tracer-bullet probe step  (issue #111)  (completed: 2026-07-26)
- [x] Context-occupancy instrumentation and PreCompact guard  (issue #112)  (completed: 2026-07-26)
- [x] Untrusted-input hardening for issue-driven design  (issue #113)  (completed: 2026-07-26)
- [x] External-dependency feasibility gate  (issue #114)  (completed: 2026-07-26)
- [x] Human-gate coverage: test diff and direction check  (issue #115)  (completed: 2026-07-26)
- [x] Litter and debris discipline across agents  (issue #116)  (completed: 2026-07-26)
- [x] Canonical-mechanism conformance  (issue #117)  (completed: 2026-07-26)
- [x] Agent-level instrumentation metrics  (issue #118)  (completed: 2026-07-26)
- [x] Licence and provenance scanning  (issue #119)  (completed: 2026-07-26)
- [x] Accessibility and i18n gates  (issue #120)  (completed: 2026-07-26)

### Phase 3 — publish, deploy, reconcile (Phase 2 was coded, not shipped)
Phase 2 items above mean "implemented on a branch," not "merged, deployed, or closed."
Audited 2026-07-27: 21 stacked PRs open (#124→#145, `main ← 100 ← 101 ← ... ← 120`), only the
bottom PR had CI (workflows trigger on `pull_request: branches: [main]` only); none of the 21
features exist yet in the deployed `~/.claude` tree; issues #100-120 still open (PR bodies carry
no closing keyword); stray non-canonical branches/worktrees from parallel agent runs litter the
repo. This phase is operational (merge/deploy/cleanup), not a new concept-to-code chain per item —
project-conductor's per-item SPEC→ADR→plan→impl cycle does not apply here.

- [x] Merge train: PR #124→#145 bottom-up  (completed: 2026-07-27). Correction found live: this
  repo does NOT auto-retarget a stacked PR after its base branch is deleted — it auto-CLOSES the
  next PR instead, and a closed PR with a deleted base cannot be reopened or re-edited. Fixed by
  recreating each PR fresh against `main` (the feature branch itself survives; only the PR wrapper
  was lost). Circuit breaker fired once for real: PR #147 (#102) had a genuine pre-existing
  `markdownlint` MD010 hard-tab violation in ADR-0048 that had never run CI before (stacked PRs
  never got CI until this train gave each one a real `main` base) — fixed with `<TAB>` placeholders
  matching ADR-0046/0047's own convention, then the train resumed.
- [x] Close issues #100-120  (completed: 2026-07-27). Done inline by the merge-train script per PR.
- [x] Deploy: `staging/sync-to-claude.sh --apply`  (completed: 2026-07-27). 27 changed + 16 new
  files. Two hooks needed the documented manual `settings.json` wiring (`test-write-scope.sh` on
  `PreToolUse Edit|Write|MultiEdit`, `precompact-guard.sh` on the new `PreCompact` key) — added by
  hand per the sync script's own "MANUAL STEP" output.
- [x] Debris: reported and removed  (completed: 2026-07-27). All 10 non-canonical
  branches/worktrees (`local-102-work`, `my-101-work`, 8 `worktree-agent-*`) verified at
  zero unique commits vs `main` before removal — explicit human confirmation obtained first.
- [x] Final verification  (completed: 2026-07-27). 43/43 shell-test files green on `main`;
  docs-ci registry parity confirmed 43/43 (glob vs the explicit `shell-tests` job list).
- [x] Unplanned: fixed a live Stop-hook infinite loop  (completed: 2026-07-27, PR #166). The #112
  rewrite of `usage-daily-hint.sh` never checked `stop_hook_active`, so its own
  `additionalContext` triggered a Stop re-invocation that re-emitted the same context forever —
  hit live in production immediately after this deploy, 9 consecutive re-invocations before Claude
  Code's own hard cap forced the turn to end. Fixed in both the deployed copy and this staging
  source so a future sync does not reintroduce it.
