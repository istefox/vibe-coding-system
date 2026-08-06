<!-- project-tasks: prefix=VCS lastId=13 -->
# PROJECT TASKS

Updated: 2026-08-06 · Open: 7 (P1: 0) · In progress: 2

This ledger holds only what is **not** already a GitHub issue or a `PROJECT.md` roadmap row.
Duplicating those here would create the second source of truth ADR-0024 forbids. Anything with an
issue number lives there; this file is for what would otherwise be lost when the context is.

## Open Issues

- [ ] `VCS-001` **P2** ADR-0126 exists only on a local branch that was never pushed, so a branch prune deletes it — branch-local at `docs/architecture/ADR-0126-293-task-identifier-letter-suffix.md` on `feat/task-num-extracts-digits-only-so-a-lette`, absent from `main` (a `file-missing` STALE record on this entry is the symptom, not a closure) <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-002` **P2** feature #293 must have its chain re-run from Step 2 — the architect stalled after writing the ADR and before the plan, and the manifest is terminal for today's slug so it cannot be restarted under the same name today <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-004` **P3** the autopilot run report is gitignored, so a run's spend and per-feature metrics survive only on the machine that produced them — `.claude/autopilot-report.json` (renamed from `nightly-report.json` by ADR-0127; a `file-missing` STALE record under the old name is that rename, not a closure) — now also carried as PROJECT.md Phase 11 Wave 5, where Wave 1's budget recalibration depends on it <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-010` **P3** `rtf-blocker` is read by the guard and cleared by the disarm but written by nothing; ADR-0127 §D6 attributed that to a deferred ADR-0111-shaped decision, and **that attribution is now known to be wrong**: ADR-0129 §D6 measured the real cause — no review cycle runs unattended at all (Gate 5's autopilot default is Skip), so a producer inside `review-triage-fix` could never fire where the guard exists. Filed as issue #374; this entry closes when #374 decides whether the unattended path reviews <!-- src:session opened:2026-08-05 -->
- [ ] `VCS-011` **P2** other sessions work in this same checkout, and on 2026-08-05 two tracked files (`PROJECT.md`, `.markdownlint-cli2.jsonc`) left the working tree with no attributed cause while `git add -u` swept one into a commit — verify the staged set with `git diff --name-status --staged` after staging, never from an earlier `git status` snapshot <!-- src:session opened:2026-08-05 -->
- [ ] `VCS-006` **P2** `CLAUDE.md` is 3470 lines / 265 KB loaded on every session and 97.7% of it is ADR summaries duplicating files that all exist on disk; `claude-md-slim` yields 3.0% and misfiles four ADR records as shell-scoped rules, so the reduction needs a purpose-built condenser — `CLAUDE.md` <!-- src:session opened:2026-08-05 -->
- [ ] `VCS-012` **P3** four harnesses print `FAIL <label>` without the colon the registry attributes on — `external-dependency-gate`, `hook-probe`, `hook-verify-workflow`, `prep` — so a plant declared in any of them is unattributable; ADR-0128 §D4 makes that a loud `BADPLANT` instead of a false "the assertion pins nothing", but the four are not converted and a green plant run says nothing about assertions in them — `staging/plugin/scripts/tests/plant-check.sh` <!-- src:session opened:2026-08-06 -->

## In Progress

- [-] `VCS-008` **P2** the autopilot reposition is mid-chain — ADR-0127 Parts 1-3 (#363, #364) are merged; **Part 4 is now the #365 chain**, tracked as `VCS-013`. One clause of Part 4 is superseded: the `token-budget` producer is **not** built, the halt is removed outright (ADR-0129 §D6), because a ceiling checked at publish cannot stop the feature that breached it. `rtf-blocker` keeps its mechanism and its corrected sentence <!-- src:session opened:2026-08-05 -->
- [-] `VCS-013` **P2** the concept-to-code chain for issue #365 is paused at Gate 4 on `feat/365-scope-and-bound-the-autopilot-run`, which is **local-only** and therefore carries `VCS-001`'s exposure — a branch prune deletes `SPEC.md` (11 requirement ids), `ADR-0129` (11 decisions) and a 9-task plan whose coverage gate reads 11/11. Manifest at `ready_for_implementation`, tree clean, harness 0 red of 73 after merging `main` in at `c771806`. Resume with `/skill concept-to-code resume docs/manifests/2026-08-06-365-scope-and-bound-the-autopilot-run.manifest.yml` in a **fresh** session — that was the Gate 4 choice, taken for orchestrator headroom across 9 task groups <!-- src:session opened:2026-08-06 -->

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

- [x] `VCS-007` Issue #370, ADR-0128, merged in PR #371 at `5af6e55`: `publish-feature.sh --issue <N>` puts `Closes #N` in the body and `project-conductor` reads the number off the roadmap line before the checkbox flip. The mechanism is shipped but **unproven end to end** — #370 closed because a human wrote the keyword into #371 by hand; the first unattended PR is the evidence, tracked as Phase 11 Wave 2 (2026-08-06)
- [x] `VCS-009` The ADR-0127 rename is deployed: `~/.claude/settings.json` names `autopilot-guard.sh`, zero stale `nightly-guard.sh` references, zero `~/.claude/hooks/nightly-*.sh` remaining, `sync-to-claude.sh --apply` proceeds (2026-08-05)
- [x] `VCS-005` PRs #362, #367 and #368 all merged; zero PRs open (2026-08-05)
- [x] `VCS-003` Five Phase-P SPECs reached `main` — #335, #336, #350, #355 and #358 all present under `docs/specs/` on `origin/main` since PR #362 merged (2026-08-05)
