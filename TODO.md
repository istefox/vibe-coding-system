<!-- project-tasks: prefix=VCS lastId=19 -->
# PROJECT TASKS

Updated: 2026-08-11 · Open: 4 (P1: 0) · In progress: 0

This ledger holds only what is **not** already a GitHub issue or a `PROJECT.md` roadmap row.
Duplicating those here would create the second source of truth ADR-0024 forbids. Anything with an
issue number lives there; this file is for what would otherwise be lost when the context is.

## Open Issues

- [ ] `VCS-002` **P2** feature #293 must have its chain re-run from Step 2 — the architect stalled after writing the ADR and before the plan, and the manifest is terminal for today's slug so it cannot be restarted under the same name today <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-004` **P3** the autopilot run report is gitignored, so a run's spend and per-feature metrics survive only on the machine that produced them — `.claude/autopilot-report.json` (renamed from `nightly-report.json` by ADR-0127; a `file-missing` STALE record under the old name is that rename, not a closure) — now also carried as PROJECT.md Phase 11 Wave 5, where Wave 1's budget recalibration depends on it <!-- src:session opened:2026-08-04 -->
- [ ] `VCS-011` **P2** other sessions work in this same checkout, and on 2026-08-05 two tracked files (`PROJECT.md`, `.markdownlint-cli2.jsonc`) left the working tree with no attributed cause while `git add -u` swept one into a commit — verify the staged set with `git diff --name-status --staged` after staging, never from an earlier `git status` snapshot <!-- src:session opened:2026-08-05 -->
- [ ] `VCS-012` **P3** four harnesses print `FAIL <label>` without the colon the registry attributes on — `external-dependency-gate`, `hook-probe`, `hook-verify-workflow`, `prep` — so a plant declared in any of them is unattributable; ADR-0128 §D4 makes that a loud `BADPLANT` instead of a false "the assertion pins nothing", but the four are not converted and a green plant run says nothing about assertions in them — `staging/plugin/scripts/tests/plant-check.sh` <!-- src:session opened:2026-08-06 -->

## In Progress

_none_

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

- [x] `VCS-015` Filed as issue **#398** and therefore leaves this ledger. `commit` Step 6b maps `rc=0` from `timeout 480 gh pr checks --watch --fail-fast` to "CI green — all required checks passed" and proceeds to the merge proposal, but `gh` exits 0 when the WATCH dies, not only when every check passed. Observed live on PR #397: `net/http: TLS handshake timeout` with `shell-tests` still `pending` and `mergeStateStatus: UNSTABLE`. The `rc=124`/`rc=8` branch immediately below already models "still pending" correctly — the gap is only that a dead watch does not land there (2026-08-11)
- [x] `VCS-016` Filed as issue **#399** and therefore leaves this ledger. `autopilot` Phase P step 3 iterates every `_issue-map.tsv` row whose SPEC is absent, reading neither the roadmap state nor the run scope: 74 rows, 4 missing, all four already completed, so it would generate SPECs for closed issues into `docs/specs/` — the namespace ADR-0106 uses as the archive. `--only` cannot bound it by design (ADR-0129 §D7 keeps Phase S away from `PROJECT.md`) (2026-08-11)
- [x] `VCS-018` Filed as issue **#400** and therefore leaves this ledger. `autopilot-disarm.sh` clears `.claude/autopilot-state/scope` with the marker — ADR-0112 defined the whole-set clear before ADR-0129 put the scope file in that directory. The hazard is the relaunch: a bare `/skill autopilot` after a disarm runs UNBOUNDED, and nothing says the bound is gone. Same shape as the defect ADR-0112 closed, pointed the other way — there a leftover file blocked, here a removed file silently permits (2026-08-11)
- [x] `VCS-017` Filed as issue **#401** and therefore leaves this ledger. `autopilot` Phase P step 4 has no defined `_prep_ref` when steps 1-3 all skip: with nothing changed the `commit` skill stops on "Nothing to commit", and the fork point every feature branch depends on is left to accident — the exact thing ADR-0127 §D4 exists to prevent. The `prep:`-absent case IS handled; the gap is the marker that has a `prep:` block whose every step skips (2026-08-11)
- [x] `VCS-019` Filed as issue **#402** and therefore leaves this ledger. `_issue-map.tsv` is written `slug \t issue \t title` (`roadmap-from-issues.sh:107`) and no consumer says so. Reading the first two columns in the other order does not fail — it reported **74 missing SPECs against a true 4**, and was caught only because a file it called missing demonstrably existed (2026-08-11)
- [x] `VCS-001` `ADR-0126-293-task-identifier-letter-suffix.md` (325 lines, `Status: Proposed`) and the aborted chain's manifest are on `main`, recovered from `feat/task-num-extracts-digits-only-so-a-lette` before that branch could be pruned. The exposure was measured, not assumed: a cleanup pass on 2026-08-10 deleted 23 merged branches and this one was the single candidate the verification saved — it held the only copy of a document `TODO.md` already cited. All ten of the ADR's cross-references resolve against `main`, and the manifest validates (`aborted`/`aborted` is terminal, so ADR-0078 exempts its developer-machine `project_root` and CI does not fail on it). Issue #293 stays open and the ADR stays `Proposed`; what is still missing is the plan, which is `VCS-002` (2026-08-10)
- [x] `VCS-014` The #385 chain ran to completion and merged in PR **#393** at `eb774be`, so the local-only exposure it shared with `VCS-001` is resolved: `ADR-0132`, the 9-task plan and the SPEC are all on `main`. The branch was deleted on 2026-08-10 after verifying by content rather than by ancestry — the Step 7 snapshot collapse orphans the merge history, so `git branch --merged` reports nothing and proves nothing. What the chain then exposed is issue #394, merged in PR **#395** at `e1f00a5`: the same argument-substitution class one layer down, where a fence is executed by the host shell rather than by bash (2026-08-10)
- [x] `VCS-013` The #365 chain ran to completion and merged in PR **#382** at `58e9486`. The local-only exposure it shared with `VCS-001` is resolved: `SPEC.md`, `ADR-0129` and the 9-task plan are all on `main`, and the branch survives at `origin/feat/365-scope-and-bound-the-autopilot-run` as well. What the shipped bound then proved is separate and lives in `PROJECT.md` Phase 12, not here: the first run under it (`--features 1 --only 294`, PR #383) refused #293 `OUT-OF-SCOPE` and stopped at `EXHAUSTED 1/1` without writing `[~]`, a `skipped-features` entry or `needs-human` (2026-08-08)
- [x] `VCS-008` The autopilot reposition is no longer mid-chain: ADR-0127 Parts 1-3 (#363, #364) and Part 4 (#365, PR #382) are all merged. The superseded clause stands as recorded — the `token-budget` producer was **not** built and the halt was removed outright (ADR-0129 §D6), because a ceiling checked at publish cannot stop the feature that breached it; `rtf-blocker` keeps its mechanism and its corrected sentence, tracked as issue #374 (2026-08-08)
- [x] `VCS-006` Filed as issue **#380** and therefore leaves this ledger, which holds only what is not already a GitHub issue. Re-measured before filing and the entry's own numbers were understated: the file is 3,592 lines / 274 KB / ~68,500 tokens and **98%** of it is 90 ADR blocks, against 80 lines of everything else. The cost claim is now measured rather than asserted — ~21.5% of the orchestrator's cache-read volume, ~$1,616, about four times the coder's entire cost. Sub-agents are unaffected: they do not load the project `CLAUDE.md` (ADR-0130 `## Correction`) (2026-08-06)
- [x] `VCS-007` Issue #370, ADR-0128, merged in PR #371 at `5af6e55`: `publish-feature.sh --issue <N>` puts `Closes #N` in the body and `project-conductor` reads the number off the roadmap line before the checkbox flip. The mechanism is shipped but **unproven end to end** — #370 closed because a human wrote the keyword into #371 by hand; the first unattended PR is the evidence, tracked as Phase 11 Wave 2 (2026-08-06)
- [x] `VCS-009` The ADR-0127 rename is deployed: `~/.claude/settings.json` names `autopilot-guard.sh`, zero stale `nightly-guard.sh` references, zero `~/.claude/hooks/nightly-*.sh` remaining, `sync-to-claude.sh --apply` proceeds (2026-08-05)
- [x] `VCS-005` PRs #362, #367 and #368 all merged; zero PRs open (2026-08-05)
- [x] `VCS-003` Five Phase-P SPECs reached `main` — #335, #336, #350, #355 and #358 all present under `docs/specs/` on `origin/main` since PR #362 merged (2026-08-05)
- [x] `VCS-010` Answered by ADR-0129 §D6, which states in terms so a future edit does not tidy it away: `rtf-blocker` is neither given a producer nor removed — the mechanism is kept, byte-unchanged, with its unreachability documented and measured (`concept-to-code` Gate 5's autopilot default is "Skip review", so no review cycle runs on an unattended roadmap run at all). The larger question this uncovered — whether the unattended path should review — is out of scope for #365 and stays open as issue #374, which needs no separate TODO entry since it already has a GitHub issue number (2026-08-06)
