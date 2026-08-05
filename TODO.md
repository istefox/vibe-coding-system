<!-- project-tasks: prefix=VCS lastId=7 -->
# PROJECT TASKS

Updated: 2026-08-05 · Open: 5 (P1: 0) · In progress: 1

This ledger holds only what is **not** already a GitHub issue or a `PROJECT.md` roadmap row.
Duplicating those here would create the second source of truth ADR-0024 forbids. Anything with an
issue number lives there; this file is for what would otherwise be lost when the context is.

## Open Issues

- [ ] `VCS-001` **P2** ADR-0126 exists only on a local branch that was never pushed, so a branch prune deletes it — branch-local at `docs/architecture/ADR-0126-293-task-identifier-letter-suffix.md` on `feat/task-num-extracts-digits-only-so-a-lette`, absent from `main` (a `file-missing` STALE record on this entry is the symptom, not a closure) <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-002` **P2** feature #293 must have its chain re-run from Step 2 — the architect stalled after writing the ADR and before the plan, and the manifest is terminal for today's slug so it cannot be restarted under the same name today <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-004` **P3** the nightly morning report is gitignored, so a run's spend and per-feature metrics survive only on the machine that produced them — `.claude/nightly-report.json` <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-006` **P2** `CLAUDE.md` is 3470 lines / 265 KB loaded on every session and 97.7% of it is ADR summaries duplicating files that all exist on disk; `claude-md-slim` yields 3.0% and misfiles four ADR records as shell-scoped rules, so the reduction needs a purpose-built condenser — `CLAUDE.md` <!-- src:session opened:2026-08-05 -->
- [ ] `VCS-007` **P3** a nightly-opened PR carries no `Closes #N`, so the feature's issue stays open after the merge unless the body is edited by hand — hit on PR #362 / issue #292 <!-- src:session opened:2026-08-05 -->

## In Progress

- [-] `VCS-005` **P2** PR #367 (roadmap Phase 10.1) and PR #368 (this ledger) are open and green, awaiting the human merge the nightly design deliberately never automates — branches `chore/roadmap-add-nightly-run-findings`, `chore/add-project-task-ledger` <!-- src:session opened:2026-08-04 -->

## Backlog / To Add

_none_

## Blocked / Decisions Needed

_none_

## Project Map

- **Entry point**: not a code project. `docs/vibe-coding-system.md` is the blueprint; `staging/` is the deployable surface synced into `~/.claude` by `staging/sync-to-claude.sh`
- **Modules**: `staging/plugin/skills/` (30 skills) · `staging/plugin/scripts/` (hooks) · `staging/plugin/agents/` · `staging/plugin/scripts/tests/` (73 harnesses + the plant registry) · `docs/architecture/` (127 ADRs) · `docs/specs/` · `docs/superpowers/plans/` · `docs/manifests/`
- **Build & test**: no build, no lint, no package manager. test-cmd: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`. Mutation testing: `bash staging/plugin/scripts/tests/plant-check.sh`
- **Key ADRs**: ADR-0022 nightly-autopilot · ADR-0068 worktree isolation contract · ADR-0086 when a derived guard is extracted · ADR-0108 the plant registry · ADR-0114 required-checks audit
- **Invariants**: merge stays human, always · a check that did not run must be distinguishable from a check that found nothing (exit 3) · a checker branches on its exit code, a reporter always exits 0 and prints `CLEAN` · an assertion nobody planted pins nothing · a needle must belong to the mechanism, not to the prose describing it · measure an issue's own claim before designing

## Done

- [x] `VCS-003` Five Phase-P SPECs reached `main` — #335, #336, #350, #355 and #358 all present under `docs/specs/` on `origin/main` since PR #362 merged (2026-08-05)
