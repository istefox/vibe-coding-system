<!-- project-tasks: prefix=VCS lastId=11 -->
# PROJECT TASKS

Updated: 2026-08-05 · Open: 8 (P1: 0) · In progress: 2

This ledger holds only what is **not** already a GitHub issue or a `PROJECT.md` roadmap row.
Duplicating those here would create the second source of truth ADR-0024 forbids. Anything with an
issue number lives there; this file is for what would otherwise be lost when the context is.

## Open Issues

- [ ] `VCS-001` **P2** ADR-0126 exists only on a local branch that was never pushed, so a branch prune deletes it — branch-local at `docs/architecture/ADR-0126-293-task-identifier-letter-suffix.md` on `feat/task-num-extracts-digits-only-so-a-lette`, absent from `main` (a `file-missing` STALE record on this entry is the symptom, not a closure) <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-002` **P2** feature #293 must have its chain re-run from Step 2 — the architect stalled after writing the ADR and before the plan, and the manifest is terminal for today's slug so it cannot be restarted under the same name today <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-004` **P3** the autopilot run report is gitignored, so a run's spend and per-feature metrics survive only on the machine that produced them — `.claude/autopilot-report.json` (renamed from `nightly-report.json` by ADR-0127; a `file-missing` STALE record under the old name is that rename, not a closure) <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-009` **P2** deploying the ADR-0127 rename needs two by-hand steps `sync-to-claude.sh` structurally cannot perform — repoint `~/.claude/settings.json:201` at `autopilot-guard.sh` and delete the two stale `~/.claude/hooks/nightly-*.sh`; until both are done `--apply` refuses, and if it did not, the old guard would stay wired, find no marker and exit 0 inert <!-- src:session opened:2026-08-05 -->
- [ ] `VCS-010` **P3** `rtf-blocker` is read by the guard and cleared by the disarm but written by nothing; ADR-0127 §D6 deliberately left it without a producer because deciding when a review blocker is run-level rather than feature-level is ADR-0111 territory and needs its own issue <!-- src:session opened:2026-08-05 -->
- [ ] `VCS-011` **P2** other sessions work in this same checkout, and on 2026-08-05 two tracked files (`PROJECT.md`, `.markdownlint-cli2.jsonc`) left the working tree with no attributed cause while `git add -u` swept one into a commit — verify the staged set with `git diff --name-status --staged` after staging, never from an earlier `git status` snapshot <!-- src:session opened:2026-08-05 -->
- [ ] `VCS-006` **P2** `CLAUDE.md` is 3470 lines / 265 KB loaded on every session and 97.7% of it is ADR summaries duplicating files that all exist on disk; `claude-md-slim` yields 3.0% and misfiles four ADR records as shell-scoped rules, so the reduction needs a purpose-built condenser — `CLAUDE.md` <!-- src:session opened:2026-08-05 -->
- [ ] `VCS-007` **P3** a nightly-opened PR carries no `Closes #N`, so the feature's issue stays open after the merge unless the body is edited by hand — hit on PR #362 / issue #292 <!-- src:session opened:2026-08-05 -->

## In Progress

- [-] `VCS-008` **P2** the autopilot reposition is mid-chain on `feat/autopilot-long-session-runner` — ADR-0127 and Part 1 (the full rename, harness 73/73) are done and uncommitted; Parts 2–4 remain: `commit --branch` (#363), the prep-branch fork point (#364), scoping plus the token bound (#365) <!-- src:session opened:2026-08-05 -->

## Backlog / To Add

_none_

## Blocked / Decisions Needed

_none_

## Project Map

- **Entry point**: not a code project. `docs/vibe-coding-system.md` is the blueprint; `staging/` is the deployable surface synced into `~/.claude` by `staging/sync-to-claude.sh`
- **Modules**: `staging/plugin/skills/` (30 skills) · `staging/plugin/scripts/` (hooks) · `staging/plugin/agents/` · `staging/plugin/scripts/tests/` (73 harnesses + the plant registry) · `docs/architecture/` (129 ADRs) · `docs/specs/` · `docs/superpowers/plans/` · `docs/manifests/`
- **Build & test**: no build, no lint, no package manager. test-cmd: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`. Mutation testing: `bash staging/plugin/scripts/tests/plant-check.sh`
- **Key ADRs**: ADR-0022 nightly-autopilot · ADR-0068 worktree isolation contract · ADR-0086 when a derived guard is extracted · ADR-0108 the plant registry · ADR-0114 required-checks audit
- **Invariants**: merge stays human, always · a check that did not run must be distinguishable from a check that found nothing (exit 3) · a checker branches on its exit code, a reporter always exits 0 and prints `CLEAN` · an assertion nobody planted pins nothing · a needle must belong to the mechanism, not to the prose describing it · measure an issue's own claim before designing

## Done

- [x] `VCS-005` PRs #362, #367 and #368 all merged; zero PRs open (2026-08-05)
- [x] `VCS-003` Five Phase-P SPECs reached `main` — #335, #336, #350, #355 and #358 all present under `docs/specs/` on `origin/main` since PR #362 merged (2026-08-05)
