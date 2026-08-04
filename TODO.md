<!-- project-tasks: prefix=VCS lastId=5 -->
# PROJECT TASKS

Updated: 2026-08-04 · Open: 4 (P1: 0) · In progress: 1

This ledger holds only what is **not** already a GitHub issue or a `PROJECT.md` roadmap row.
Duplicating those here would create the second source of truth ADR-0024 forbids. Anything with an
issue number lives there; this file is for what would otherwise be lost when the context is.

## Open Issues

- [ ] `VCS-001` **P2** ADR-0126 exists only on a local branch that was never pushed, so a branch prune deletes it — `docs/architecture/ADR-0126-293-task-identifier-letter-suffix.md` on `feat/task-num-extracts-digits-only-so-a-lette` <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-002` **P2** feature #293 must have its chain re-run from Step 2 — the architect stalled after writing the ADR and before the plan, and the manifest is terminal for today's slug so it cannot be restarted under the same name today <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-003` **P2** five Phase-P SPECs live only on `feat/the-value-domain-guard-covers-step5-mode`, so a nightly run started from `main` finds no SPEC for #335, #336, #350, #355 or #358 and skips all five — `docs/specs/` <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-004` **P3** the nightly morning report is gitignored, so a run's spend and per-feature metrics survive only on the machine that produced them — `.claude/nightly-report.json` <!-- src:session opened:2026-08-04 -->

## In Progress

- [-] `VCS-005` **P2** PR #362 (feature #292) and PR #367 (roadmap Phase 10.1) are open and green, awaiting the human merge the nightly design deliberately never automates — branches `feat/the-value-domain-guard-covers-step5-mode`, `chore/roadmap-add-nightly-run-findings` <!-- src:session opened:2026-08-04 -->

## Backlog / To Add

_none_

## Blocked / Decisions Needed

_none_

## Project Map

- **Entry point**: not a code project. `docs/vibe-coding-system.md` is the blueprint; `staging/` is the deployable surface synced into `~/.claude` by `staging/sync-to-claude.sh`
- **Modules**: `staging/plugin/skills/` (29 skills) · `staging/plugin/scripts/` (hooks) · `staging/plugin/agents/` · `staging/plugin/scripts/tests/` (73 harnesses + the plant registry) · `docs/architecture/` (126 ADRs) · `docs/specs/` · `docs/superpowers/plans/` · `docs/manifests/`
- **Build & test**: no build, no lint, no package manager. test-cmd: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`. Mutation testing: `bash staging/plugin/scripts/tests/plant-check.sh`
- **Key ADRs**: ADR-0022 nightly-autopilot · ADR-0068 worktree isolation contract · ADR-0086 when a derived guard is extracted · ADR-0108 the plant registry · ADR-0114 required-checks audit
- **Invariants**: merge stays human, always · a check that did not run must be distinguishable from a check that found nothing (exit 3) · a checker branches on its exit code, a reporter always exits 0 and prints `CLEAN` · an assertion nobody planted pins nothing · a needle must belong to the mechanism, not to the prose describing it · measure an issue's own claim before designing

## Done

_none_
