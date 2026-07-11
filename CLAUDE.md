# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this repository

This is not a code project: it is the **blueprint repository** for the "Vibe Coding System for
Stefano Ferri — Multi-Agent Architecture v2.1". It contains one authoritative artifact:

- `docs/vibe-coding-system.md` (~1770 lines) — complete specification of the multi-agent Claude Code
  setup: sub-agents, agent-teams, path-scoped rules, hooks, MCP, permission modes,
  concept→code workflow. This is the **single source of truth**: every decision must be reconciled
  with this document.

The file exceeds 25k tokens: read it with `Read` using `offset`/`limit` per section, not
in one block. Sections are numbered (1–17) and cross-reference each other throughout the text.

## Inherits global rules

This project inherits `~/.claude/CLAUDE.md` (Stefano Ferri), loaded in every session.
**Do not duplicate here** the general conventions (Python/Swift/web style, git workflow,
Vibrofer terminology, safety): they already apply. This file specializes only for this repo.

## Invariant behavioral rules

From section 4 of the document, consistent with global conventions — apply here and to
any system generated from this blueprint:

- Plan mode required for any task modifying >1 file or touching production migrations/config
- Conventional Commits in English (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`)
- Never `git push --force` without explicit approval from Stefano
- Never modify migrations already applied in production
- Never disable a test to make it pass: if it needs changing, explain why in chat first
- Confidence declared in chat at end of task, **never** in deliverable files
- HITL gate always before: commit, push, deploy, DB schema changes, permanent deletions
- Language: English throughout — chat, docs, code, commits, docstrings
- Tone: direct, concise, technical — no filler

## Architecture described in the document (big picture)

Use this to orient without re-reading all 1770 lines. Details and rationale in the indicated sections.

- **Topology (sec. 2):** Orchestrator (main CLI session) → up to 4 sub-agents in parallel *within*
  the session (isolated tasks, return summary) **or** 3–5 teammates in an agent-team in *separate
  sessions* (cross-layer work, experimental, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). Sub-agents
  do NOT spawn other sub-agents.
- **8 custom sub-agents (sec. 3)** in `~/.claude/agents/`: `architect` (Opus, plans, ADR only),
  `coder` (Sonnet, `isolation: worktree`), `reviewer`/`tester`/`debugger`/`refactorer` (Sonnet),
  `doc-writer`/`researcher` (Haiku). Model chosen to balance cost/capability (sec. 3.9).
- **Layered extension stack:** `~/.claude/CLAUDE.md` global (identity+behavior only, <200 lines)
  → path-scoped rules in `.claude/rules/` with `paths:` frontmatter (sec. 5) → sub-agents in
  `.claude/agents/` → skills in `.claude/skills/` (sec. 8) → hooks in `settings.json` (sec. 7,
  deterministic automation) → MCP in `.mcp.json` (sec. 9). The rules pattern replaces most of
  the monolithic CLAUDE.md.
- **Permission strategy (sec. 10):** `acceptEdits` default, explicit plan mode for new features,
  allowlist for recurring commands; hook-deny rules override any permission mode (layered defense).
- **concept→code workflow (sec. 11):** interview mode (`AskUserQuestion`) → `SPEC.md` → `ARCH.md`
  (+ ADR) → project CLAUDE.md → **fresh session** → scaffold in plan mode → parallel multi-agent
  implementation (worktree) → review → commit + PR. Never mix interview and coding in the same session.
- **Identity convention (sec. 4, proposed design element):** assistant "Adriano", user "Stefano" —
  noted here as a blueprint element; effective identity is governed by `~/.claude/CLAUDE.md`.

## Working with the document

- When updating `docs/vibe-coding-system.md`: keep section numbering consistent, the
  "Changes from…" blocks (version changelog at the top), and the "Final confidence" +
  "Verified vs assumed" section at the bottom.
- Preserve the explicit **verified vs assumed** distinction: the document cites
  `code.claude.com/docs` as verified primary sources. Do not promote an assumption to
  a fact without verification and a citation.
- The checklists (sec. 15) and templates (sec. 4, 6) are intended to be copied into other
  repos: keep them self-consistent and valid as standalone documents.

## Commands

Documentation-only repository: **no** build, lint, test, or run commands.
Markdown only. Remote: `https://github.com/istefox/vibe-coding-system` (private).
The artifacts of the described system (agents, skills, hooks, rules) live in `~/.claude/`
and in the `.claude/` directories of target projects — not here.

## Decisions from the clean-public-repo chain (ADR-0011)

Anonymization mode for public repos: Gate 0b in the chain (auto-detect public remote →
`anonymize` flag) + `clean-public-repo` skill (audit/remedy, fresh-history publish by default,
surgical rewrite opt-in with backup+dry-run+HITL). Goal: quality + no auto-attribution of the
tool; **never** falsify authors.
Detail: `docs/architecture/ADR-0011-clean-public-repo-anonymize.md`.

## Decisions from the humanize-en chain (ADR-0015)

English prose humanizer: skill `humanize-en` + hook regex `PostToolUse` (hint, zero-LLM)
+ conditional `UserPromptSubmit` hook (keyword detection EN prose, ~80 tokens on match only).
Chain integration: Gate 0c (flag `humanize` post-anonymization) + Gate 5.5 (humanize
deliverable pre-commit) + commit Step 3.5 (humanize message on public repos pre-HITL).
Global chat in EN (default) with preservation of Vibrofer IT terminology.
Detail: `docs/architecture/ADR-0015-humanize-en-chain-integration.md`.

## Decisions from the dynamic-workflows-step5 chain (ADR-0016)

Dynamic Workflows integration into concept-to-code Step 5 (parallel coder dispatch):
keyword trigger (`"ultracode"` in the dispatch prompt; renamed from `"workflow"` in CC
v2.1.160 — the bare word "workflow" no longer triggers) causes Claude Code to generate a JS
orchestration script instead of turn-by-turn `Agent` tool calls. Max 16 concurrent subagents,
1000 total; state in script variables (not context window); session-bound resumability.

Key constraints:
- **Hook safety is a hard blocker.** `PreToolUse`/`PostToolUse` hook propagation inside
  workflow subagents is undocumented. A smoke test (`hook_verified` manifest field) must
  confirm pattern-enforce fires before the workflow path is used in production.
- **Fallback path.** If the keyword trigger fails or `hook_verified=false`, Step 5 reverts
  to the current Agent-tool batch dispatch (2-3 tasks per batch). No chain breakage.
- **File handoff.** Workflow writes `.claude/step5-report.json`; orchestrator reads it
  instead of relying on an in-context coder report. Schema: `tasks_completed`, `tasks_failed`,
  `test_result`, `files_modified`, `harness_deltas`.
- **Manifest fields.** `hook_verified` (bool, default false) and `step5_mode`
  (`workflow|agent_fallback|null`) added to `manifest-init.sh` as additive fields.
  No schema version bump required.

Detail: `docs/architecture/ADR-0016-dynamic-workflows-step5.md`.

## Decisions from chain deep-refactor-skill (ADR-0018)

Whole-codebase health audit + regression-safe incremental fix skill (`/skill deep-refactor`).
Integrated as Gate 5.1 in the concept-to-code chain (after RTF, before commit).

Key architectural decisions:
- **Hybrid pipeline (Alt D):** dimension is the test-run unit (3 runs max — dead-code → perf → structure); severity governs fix order within each batch (P1 first). Audit phase uses Workflow fan-out (4 parallel reviewer agents); fix phase uses sequential Agent-tool (shared tree + mid-run HITL gate required).
- **Two mandatory guards baked into reviewer prompts:** `@objc`/`dynamic`/protocol-witness dead code → `report-only`; `async`/`actor`/`DispatchQueue`/`Sendable` perf fixes → `report-only`. Static analysis cannot prove these safe; a green test suite does not either.
- **Global circuit breaker:** any regression = full stop. Verified fixes committed per-dimension with a partial report tagged `CIRCUIT BREAKER FIRED AT: <dimension>`. Remaining dimensions tagged `SKIPPED`.
- **No test-cmd = report-only mode:** if `.claude/test-cmd` is `NONE` or baseline is RED, auto-fix is blocked. Gate 0 messaging explains why no fixes landed.
- **Security findings:** always `report-only` regardless of `risk_level`. High-risk findings (hardcoded secrets, auth bypass) are never auto-fixed.

Detail: `docs/architecture/ADR-0018-deep-refactor-skill.md`.

## Decisions from the claude-md-slim chain (ADR-0019)

CLAUDE.md token-reduction skill (`/skill claude-md-slim [--global] [<project-root>]`): audits
project CLAUDE.md, identifies sections extractable to path-scoped `.claude/rules/` files, proposes
a unified diff, and applies the refactor after HITL approval.

Key architectural decisions:
- **Extraction heuristic:** file-pattern keywords (shell/python/swift/ts/migrations/markdown/sql) map
  sections to `.claude/rules/<domain>.md` with `paths:` globs. MIXED sections (domain + global
  behavioral keywords) are flagged but not auto-split in v1.
- **Apply after HITL:** unified diff shown → `AskUserQuestion` (Approve/Reject/Abort) → on Approve:
  backup (`.bak-YYYY-MM-DD`) + write rules files + write trimmed CLAUDE.md.
- **Merge strategy:** merge extracted content into existing rules files (deduplicate by exact-line
  match); create new rules file if absent.
- **Content-preservation invariant (hard gate):** union(trimmed CLAUDE.md + all rules files) must
  contain every line of the original. Verified by `content-union-check.sh` before the HITL gate;
  abort if violated.
- **`--global` flag:** enables cross-file duplication scan against `~/.claude/CLAUDE.md` (read-only);
  duplicated sections proposed for deletion from project CLAUDE.md only.
- **DoD:** ≥30% line reduction + valid `paths:` frontmatter on all rules files + no broken delegation
  references. Implementation: 4 bash 3.2-compatible scripts + SKILL.md 7-step pipeline + 10-test harness.

Detail: `docs/architecture/ADR-0019-claude-md-slim-skill.md`.

## Decisions from the autopilot-build skill (ADR-0020)

Standalone unattended implementation skill (`/skill autopilot-build <manifest-path>`): picks up
a concept-to-code manifest at `ready_for_implementation` (Gates 1–3 approved, SPEC+ADR+plan
human-reviewed) and runs Steps 5–7 without any human in the loop, ending at a local feature
branch commit plus a `autopilot-report.json`.

Key architectural decisions:
- **Autonomy boundary:** only local + reversible actions unattended (implement, test, review,
  local commit). Push, PR, merge, and DB changes are never taken unattended.
- **Eight hard pre-flight checks:** scope guard (script-level, not prompt-level), manifest state,
  gates 1–3 approved, artifacts on disk, unchecked plan tasks, test-cmd real + TOFU-trusted,
  `hook_verified` known, git repo present. Any failure → `aborted` report, no dispatch.
- **TOFU trust must pre-exist:** autopilot never auto-grants test-cmd trust. The human must have
  approved the command in a prior interactive session (ADR-0014 invariant preserved).
- **Reuses c2c Step 5–7 mechanics verbatim:** Workflow dispatch or Agent-tool batch fallback
  (ADR-0016), review cycle, `commit --autopilot` (local-only, no push). No reimplementation.
- **Circuit breaker on RED tests:** halt without commit after Step 5 or Step 6 RED; write a
  `partial` report for human inspection.
- **Safety hooks always active:** `stop-gate.sh`, `pre-flight-pattern-enforce.sh`,
  `protect-files.sh`, `db-backup-guardrail.sh` fire normally throughout.

Detail: `docs/architecture/ADR-0020-autopilot-build-skill.md`.

## Decisions from the nightly-autopilot capability (ADR-0022)

Overnight autonomous roadmap-to-PR runner (`/skill nightly-autopilot`): the human approves
SPEC/ADR/plan in the evening, sets `/goal` plus a non-blocking permission mode, launches the skill,
and by morning each roadmap feature is on its own `feat/*` branch, pushed, with an open PR to `main`
and CI green. Nothing is merged. A `nightly-guard` hook halts on real trouble and leaves a morning
report (`nightly-report.json`, schema v2.0).

Key architectural decisions:
- **Amends ADR-0020 D2:** unattended `git push` + open PR are allowed, but only on repos that opt in
  via a committed `.claude/nightly-autopilot.yml` (`publish: true`). Merge, force-push, `--no-verify`,
  and any write to `main` stay forbidden. A pushed branch and an open PR are reversible; a merge is
  not, so the merge stays human.
- **`/goal` is the outer loop, not a HITL bypass:** verified native command (CC v2.1.139+). It removes
  per-turn prompts only; it does not answer `AskUserQuestion` and its evaluator cannot call tools. So
  the run prints a `NIGHTLY-PUBLISH` status line per feature for the evaluator to read, and carries a
  `stop after N turns` hard budget.
- **Thin skill + conductor extension:** `nightly-autopilot` owns launch, publish, guard, CI, and the
  report; `project-conductor` gains a `nightly` roadmap-autopilot mode that pre-authorizes the whole
  roadmap and skips the per-feature Step 3 gate (invariant amended, scoped to this mode only).
- **`nightly-guard` fail-safe:** a `PreToolUse` hook on `git push`/`gh pr create` plus an in-script
  `--check` gate called by the publish helper (a wrapped `git push` is invisible to the hook matcher,
  so both paths are needed). Halts on red build, needs-human marker, RTF BLOCKER, or budget exceeded.
  It blocks on internal error (opposite of stop-gate's fail-open), and is inert outside a nightly run.
- **Blueprint here, synced to `~/.claude`:** ADR + plan + skill/hook/template source live in this repo
  (`staging/`, `docs/`); an explicit sync step copies them into `~/.claude`, showing a diff before
  overwriting any existing file.

Detail: `docs/architecture/ADR-0022-nightly-autopilot-goal.md`,
`docs/architecture/ADR-0022-implementation-plan.md`,
`docs/architecture/ADR-0022-morning-report-schema.md`,
`docs/RUNBOOK-nightly-autopilot.md`.

## Decisions from the nightly auto-design capability (ADR-0023)

`nightly-autopilot` gains a Phase P (prep) that generates the missing design inputs from a labeled
GitHub backlog, so a set of issues becomes PR-ready overnight with no evening design work. Amends the
ADR-0022 boundary: design-artifact generation (SPEC, ADR, plan, PROJECT.md, manifests) joins the
unattended set under the same per-repo opt-in.

Key architectural decisions:
- **Only two headless gaps existed:** `SPEC.md` (only `interview-driver`, interactive; c2c autopilot
  hard-aborts if absent) and `PROJECT.md` (only the 3-round setup). Everything downstream (architect
  → ADR + plan, claude-md-generator → CLAUDE.md, manifest-init, c2c autopilot, conductor nightly) is
  already headless and reused verbatim.
- **The TOFU-trust and gh-auth wall stays human** (one-time per repo / per machine). ADR-0020 already
  rejected a self-approving prep step. Phase P does auto-create the `.claude/test-cmd` *file* from
  stack detection, so the human's per-repo action collapses to one `approve-test-cmd.sh`.
- **Input = GitHub issues by label** (`prep.issues_label` in the opt-in marker); one issue = one
  feature; the issue body replaces the interview.
- **`spec-from-issue` is headless and refuses to fabricate:** a deterministic quality gate
  (`spec-issue-gate.sh`) skips a thin/vague issue with a `needs-human` note rather than inventing
  requirements.
- **PR is the design checkpoint:** the generated SPEC + ADR are committed inside the feature PR and
  reviewed at merge (merge stays human). No pre-implementation gate.
- **Single-SPEC-path handled** by a just-in-time copy of `docs/specs/<slug>.spec.md` to
  `<root>/SPEC.md` in `project-conductor nightly` before each feature's chain.

Detail: `docs/architecture/ADR-0023-nightly-auto-design.md`.

## Decisions from the vendor-deployed-only chain (ADR-0024)

Vendoring of the deployed-only executable surface (16 skills, 12 hooks + tests) from
`~/.claude` into `staging/`, extending `sync-to-claude.sh` PAIRS so repo-side fixes can
reach deployment (issue #28, enabler for the 2026-07-10 audit-fix roadmap).

Key architectural decisions:
- **Vendor scope:** full skill directories to `staging/plugin/skills/<name>/`, hooks to `staging/plugin/scripts/`; skip binary assets, `*.bak-*`, website-auditor (foreign symlink), backup-before-deploy.sh (retired by #38).
- **No second source of truth:** `concept-to-code/scripts/hook-verify-workflow.sh` (already vendored flat under ADR-0016) and runtime state (`memory/agent-notes/`) are excluded from the copy.
- **PAIRS stays one-entry-per-file, additive-only:** directory-level sync would need its own ADR.
- **Legacy `$HOME`-coupled hook tests:** vendored byte-identical but kept OUT of the `*.test.sh` glob and CI (they test the deployed tree and would fail on Actions); documented as a known CI-dark gap.
- **`pairs-completeness.test.sh`:** structural check only (every PAIRS src exists in staging), never byte-identity against live `~/.claude` — staging is expected to move ahead of deployed during the roadmap.

Detail: `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md`.

## Decisions from the staging-refresh chain (ADR-0025)

Refresh of every stale `staging/` file that has a deployed counterpart (issue #29): 8 agents,
7 repo-native SKILL.md, protect-files/auto-format hooks, user CLAUDE.md/rules, settings.json;
removes retired `project-bootstrap`; PAIRS gains `goal-loop` and `research-prompt`.

Key architectural decisions:
- **Full byte-identical mirror (`cp -p`), no selective patching:** undocumented drift (architect effort `max` vs blueprint `xhigh`, reviewer extra tools) is mirrored as-is — reconciling toward blueprint intent is issue #40's job.
- **PAIRS grows by exactly two entries** (goal-loop, research-prompt): `docs/RUNBOOK.md` bulk copy already reaches every refreshed file; PAIRS stays the lightweight single-file path.
- **settings.json via deterministic `jq del()`** of machine-local keys (model, theme, tui, editorMode, statusLine, cleanupPeriodDays); stays outside PAIRS.
- **Safety gap flagged, not fixed:** deployed `interview-driver`/`fastapi-react-vibe` lost `disable-model-invocation: true` (contradicts blueprint /loop safety design); mirrored per SPEC, unowned by #28-#40, needs a dedicated issue.

Detail: `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md`.

## Decisions from the clean-public-repo history-safety chain (ADR-0026)

Fixes three audit findings in the vendored clean-public-repo skill (issue #30): the P1
private-history leak (backup tarball staged into the public branch), the surgical-rewrite
false rollback story, and detect-tool-traces SHA matching with abbreviated hashes 8+.

Key architectural decisions:
- **Backup relocation resolves the true git top-level** (`git -C "$ROOT" rev-parse --show-toplevel`, then parent), never `dirname "$ROOT"` — a subdirectory ROOT would silently reproduce the leak.
- **Defense-in-depth hard-fail (exit 5):** prepare mode greps `git ls-files` for any staged `.git-backup-*.tar.gz` before printing HITL instructions, independent of the relocation.
- **Asymmetric tests:** findings 1/3 get live fixture-repo tests; finding 2 gets static source-anchor tests (git-filter-repo's unconditional version gate blocks live execution in every environment that matters).
- **Staging-only until human sync:** the deployed copy keeps the P1 leak until `sync-to-claude.sh --apply` — flagged with elevated urgency in the report.

Detail: `docs/architecture/ADR-0026-30-clean-public-repo-private-history.md`.

## Decisions from the c2c gate-fixes chain (ADR-0027)

Five audit fixes to the vendored concept-to-code skill (issue #31): BSD-safe slug stamp,
Gate 2b TOFU probe instead of unattended approval, Gate 0d autopilot commit-only, one
canonical Gate 0b/0c/0d order, and chain_path-conditional manifest invariant 7.

Key architectural decisions:
- **Slug stamp via awk + temp file + mv** (GNU-only `sed a\` removed); verified live on Darwin BSD sed/awk, idempotent.
- **Gate order fix needs zero manifest-transition.sh changes:** all needed pairs already exist; Gates 0c/0d were written but structurally unreachable. Behavior-visible consequence: Express/Hybrid now get Gates 0b/0c/0d too.
- **Gate 2b autopilot:** read-only TOFU-trust probe (reuses the Form-B resume mechanism); never calls approve-test-cmd.sh unattended.
- **Step 7 push:** double-guarded — Gate 0d autopilot always records `initial_commit_push: "commit"` AND Step 7 checks `autopilot != true`; nightly publish lives in publish-feature.sh, not c2c.
- **Invariant 7 conditional on chain_path** in manifest-validate.sh; Gate E3 Abort records `aborted`, not completed.

Detail: `docs/architecture/ADR-0027-31-c2c-bsd-slug-autopilot-gates.md`.

## Decisions from the manifest-helpers chain (ADR-0028)

Five audit fixes to the concept-to-code manifest helpers (issue #32): invariant-9 count
guard, exit-4 write-failure contract for set-artifact/set-gate, YAML title escaping in
manifest-init, five SKILL.md PATH-RULE call sites, transition-pair count reconciliation.

Key architectural decisions:
- **Exit-4 contract mirrored verbatim from manifest-set-flag.sh** (mktemp + trap + exit 4), no new error-handling idiom; `set -e` rejected.
- **Pair count independently recounted: 48** (two extraction methods); SKILL.md 213/229 and the manifest-transition.sh comment reconciled, hybrid enumeration completed (two gate_h1c pairs), plus the stale "21" and missing Express bullet in the same self-contradictory paragraph.
- **PATH-RULE fix strictly at the 5 named sites;** a 6th bare mention (SKILL.md:569) disclosed but deferred.
- **New sibling test file** (concept-to-code-manifest-helpers-guards.test.sh, 21 assertions) — one-file-per-issue hermetic pattern; #31's harness untouched.
- **CI-user caveat:** chmod-555 write-failure simulation may be inert if Actions runs as root; Task-3 checkpoint halts on unexpected all-green instead of papering over.

Detail: `docs/architecture/ADR-0028-32-manifest-helpers-guards.md`.

## Decisions from the hook-verify session-filter chain (ADR-0029)

Session-scopes hook-verify-workflow.sh's AFTER window (issue #33) so a concurrent
session's coder rows can no longer produce a false VERIFIED — the exact ADR-0016
hard-blocker false-positive.

Key architectural decisions:
- **Env var corrected with citation:** Claude Code sets `CLAUDE_CODE_SESSION_ID`, not the issue's literal `CLAUDE_SESSION_ID` (code.claude.com/docs/en/env-vars); implementing the literal name would have left the primary path silently dead while passing every offline test.
- **Same-session subagents share the parent session_id**, so the filter keeps legitimate workflow-coder rows.
- **No session id + multiple session ids after the marker → INCONCLUSIVE exit 3;** residual blind spot disclosed (single foreign session, no id: still a false VERIFIED, pinned by test S5, closing it would need statefulness — rejected).
- **Existing test file extended (26 → 39 assertions, 8 named cases)** per SPEC, overriding the one-file-per-issue pattern; no CI change needed.
- **Issue #34 gap disclosed:** no global smoke-test record exists (only per-manifest flags); #34 must design it, not assume it.

Detail: `docs/architecture/ADR-0029-33-hook-verify-session-filter.md`.
