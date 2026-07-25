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
- **Hook safety was the blocker, and it was cleared.** Hook propagation into workflow subagents
  was undocumented at spec time; the smoke test of 2026-05-29 on CC v2.1.156 confirmed
  `PreToolUse` fires and `agent_type` is set from the script's `agentType`, which is what moved
  ADR-0016 from Proposed to Accepted. It took `pre-flight-pattern-enforce.sh` v1.3 to get there:
  v2.1.154 had silently moved workflow subagent transcripts to
  `subagents/workflows/<wf_id>/agent-<id>.jsonl`, so the hook needed a `find`-based fallback.
  Read the recorded result in ADR-0016 § Smoke Test Result before treating this as open again —
  its stale phrasing here already sent one investigation down a closed question. **Re-verified
  2026-07-25 on the current build** (issue #87): a three-arm sandbox run confirmed propagation
  still holds, the `subagents/workflows/<wf_id>/` layout is unchanged, and the hook validates the
  canonical `PATTERN: <CATEGORY> | <payload>` format rather than merely the `PATTERN:` substring —
  an em-dash instead of the pipe is blocked. The evidence stays build-specific, not permanent:
  v2.1.154 is proof the substrate moves underneath, so re-run the test after a major CC bump
  rather than trusting either date. `hook_verified` still defaults `false` per manifest, so the
  safe fallback is unchanged.
- **Fallback path.** If the keyword trigger fails or `hook_verified=false`, Step 5 reverts
  to the current Agent-tool batch dispatch (2-3 tasks per batch). No chain breakage.
- **File handoff.** Workflow writes `.claude/step5-report.json`; orchestrator reads it
  instead of relying on an in-context coder report. Schema: `tasks_completed`, `tasks_failed`,
  `test_result`, `files_modified`, `harness_deltas`.
- **Manifest fields.** `hook_verified` (bool, default false) and `step5_mode`
  (`workflow|agent_fallback|null`) added to `manifest-init.sh` as additive fields.
  No schema version bump required.

**Addendum 2026-07-25 (orchestrator effort).** The session `effortLevel` moves to `high`. Since
the Workflow tool inherits the session effort whenever `opts.effort` is omitted, exactly as it
inherits the session model when `model` is omitted, Step 5 now pins `effort` explicitly on every
`agent()` call from each agent's frontmatter (architect `xhigh`; coder/reviewer/debugger `high`;
tester/refactorer `medium`; doc-writer/researcher `low`). Without that pin, raising the
orchestrator would have silently raised every dispatched agent and discarded the per-agent
calibration. The table in SKILL.md is not linked to the frontmatter files: changing one means
changing both.

**Addendum 2026-07-25b (Step 6).** The same pin now covers the Step 6 review-and-fix workflow,
which the first pass missed: it was explicit about `model` and silent about `effort`, so the whole
cycle inherited the orchestrator's level, `refactorer` most visibly (frontmatter `medium`). Both
`reviewer` dispatches pin `sonnet`/`high`; the fix agents resolve effort through a `FIX_EFFORT`
lookup keyed by `fix_type`, since `agentType` there is chosen at runtime. `step6-effort-pin.test.sh`
asserts the map against the agent frontmatter, so Step 6 is the one call site where the
not-linked problem above is caught by CI rather than by review. Corrected in the same edit: the
Step 6 template called `agent(opts, prompt)`, inverting the `agent(prompt, opts)` API that Step 5
already had right.

**Correction (same day).** That addendum first said Phase 3's `model: "opus"` override was
"recorded in no ADR". Wrong. It is the third site of a cross-skill convention decided in
**ADR-0018 § Dispatch model** and written out twice — `review-triage-fix/SKILL.md:170` and
`deep-refactor/SKILL.md`'s "model: opus requirement" section. It reached this file byte-identical
through the ADR-0024 vendoring commit (`5e87329`), which is why no design commit for it exists
here. What was actually missing was Step 6's cross-reference, now added in Phase 3 along with the
note that model (`opus`, overridden) and effort (frontmatter, via `FIX_EFFORT`) come from
different places on purpose. Recorded in the same comment: ADR-0018 requires fix phases to be
sequential, and Phase 3 parallelises anyway — safe only because Phase 2 groups findings by file,
one file per agent. That mitigation is load-bearing and was implicit; `step6-effort-pin.test.sh`
F1/F2 now pin both notes.

**Addendum 2026-07-25c (Step 6 Phase 3 write scope, issue #83).** Phase 2's by-file grouping bounds
where the findings are, not where the edits land — an agent fixing an import could write a file that
was nobody's assigned file, and two agents would collide on it. The fix-agent prompt now forbids
editing anything but its assigned file; a cross-file need goes into a `deferred` array, is confirmed
or dismissed by Phase 4 without being acted on, and reaches the user through `step6-report.json`.
The divergence from ADR-0018's sequential-fix invariant is deliberate and recorded. **It is an
instruction, not an enforcement** — no hook constrains a subagent's write paths by file, and building
one needs its own issue. Phase 2's grouping stays load-bearing.

**Addendum 2026-07-25d (write scope enforced, issue #87).** `write-scope-enforce.sh`, a
`PreToolUse` hook on `Edit|Write|MultiEdit`, turns 25c's instruction into enforcement: it finds the
calling subagent's transcript via `.agent_id`, reads the `you may edit ONLY <path>` line from the
dispatch prompt, and denies writes elsewhere with a reason pointing at `deferred`. Inert by
construction — no scope line means allow-and-exit, so nothing outside Step 6 Phase 3 is affected.
Diverges from `pre-flight-pattern-enforce.sh` in two ways on purpose: it reads `user` entries (the
marker is in the prompt, not model output) and it has **no main-session fallback**, since an
orchestrator turn quoting a scope line would otherwise bind the whole session. The hook matches a
string that lives in SKILL.md, so rewording that prompt makes it silently inert —
`write-scope-enforce.test.sh` D1 pins the two together. Deployed by sync, **wired by hand**;
inert until the `settings.json` entry exists.

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

**Addendum 2026-07-25 (Branch A pins).** The audit phase's Branch A (Workflow, the default) pinned
neither `model` nor `effort`, so it ran on the session's values while the skill's own "model: opus
requirement" section demanded Opus. Root cause was that section's wording — "in every **Agent-tool**
dispatch" — naming one mechanism where two exist, leaving the Workflow branch outside its own rule.
Both branches now pin `model: "opus", effort: "high"`, and the requirement is stated for both
mechanisms. The model half was wrong on every default run; the effort half only looked right
because `reviewer`'s frontmatter happens to match the orchestrator's current level.

Same pass fixed the same class in `autopilot-build`, which delegated to `concept-to-code` by line
range (`§475–486` and three others). All four had drifted off target, partly from this repo's own
recent edits. They now name headings instead, and `workflow-dispatch-pins.test.sh` asserts each
named heading still exists in the file it points into — a reference that fails loudly instead of
rotting quietly. The Step 5 and Step 6 workflow blocks share a heading verbatim, so those two
references must name their step as well.

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

## Decisions from the scope-guards chain (ADR-0030)

Three scope/pre-flight fixes (issue #34): autopilot-build check-1 CWD guard, conductor
manifest-glob anchoring, nightly-autopilot pre-flight check 6.

Key architectural decisions:
- **Check 1 via `case "$project_root_n" in "$cwd_n"/*)`** — quoted, slash-anchored; matches ADR-0020's prose contract (parent passes, child aborts, sibling aborts).
- **Conductor lookup two-layer at all 3 sites:** date-anchored glob (`????-??-??-"$_slug".manifest.yml`) AND `topic:` field equality (the field IS the kebab slug) — anchoring alone still suffix-collides.
- **Check 6 zero-manifest branch: documented non-blocking pass, no invented record.** The SPEC's "global smoke-test record" does not exist (ADR-0029 confirmed); manifest-init's unconditional `hook_verified: false` default already guarantees the safe agent-batch fallback, so a lenient default is sound. Reviewers must not expect a record to appear.
- **Fenced SKILL.md bash blocks don't share state** — multi-call-site logic duplicated verbatim per site by design.

Detail: `docs/architecture/ADR-0030-34-scope-guards.md`.

## Decisions from the snapshot-and-refactor chain (ADR-0031)

Three fixes (issue #35): refactor-snapshot RFS_FILTER newline bug, deep-refactor glob
override, deep-refactor dirty-tree circuit-breaker advice.

Key architectural decisions:
- **capture.sh: one-line strip** `"${CMD_CONTENT%$'\n'}"` before EXEC_CMD is built — the filter was landing on a second bash -c line, freezing snapshot EXIT at 127 and silently defeating the regression channel.
- **enumerate-sources.sh: real glob semantics via a bash `case` matching engine** replacing grep -E entirely — mere ERE-escaping would leave `*.swift` inert, failing the SPEC's own criterion; case patterns match across `/`, bash 3.2-portable, no injection surface.
- **Gate 2 dirty-tree advice conditioned on DIRTY_TREE** using the file's existing `[If <condition>:]` bracket convention; disclosure-only (no stash-tracking mechanism invented — deferred as bigger than the ask).
- **Two always-PASS assertions (B4/B6) labeled in the plan** so checkpoints aren't mistaken for fix evidence.

Detail: `docs/architecture/ADR-0031-35-refactor-snapshot-deep-refactor.md`.

## Decisions from the union-check chain (ADR-0032)

Whole-line semantics for claude-md-slim's sole ADR-0019 content-preservation gate
(issue #36): `## Git` no longer counts as preserved when only `## GitHub Actions` survives.

Key architectural decisions:
- **One constructed union temp file + `grep -qxF`** (concatenated, trailing-trimmed outputs) — no regex escaping surface, single pass.
- **Trailing-whitespace tolerance made explicit:** the old substring bug provided it by accident; a naive `-x` fix would have regressed it (proven live with a strawman).
- **Multiplicity is a documented exemption, not enforced:** ADR-0019 D6 is set-based, and the pipeline's own merge-dedup legitimately reduces occurrence counts; enforcing multiplicity would fail correct behavior. Documented in the SKILL text per the SPEC's fallback clause.
- **New hermetic CI test file** (the skill's own run-tests.sh is $HOME-coupled and CI-dark — the third such skill found); the three pre-existing fixtures gain CI coverage for the first time.
- **Orthogonal gap disclosed, not bundled:** --global DUPLICATE-removed sections never feed the union check — candidate follow-up issue.

Detail: `docs/architecture/ADR-0032-36-claude-md-slim-union-check.md`.

## Decisions from the vibe-status chain (ADR-0033)

Recursion guard, orphan-process fix, Memory count guard, and the ADR-0021 Active-chains
wiring for vibe-status (issue #37).

Key architectural decisions:
- **Recursion guard in aggregate.sh itself** (name-scoped `VIBE_STATUS_RECURSING` sentinel), not just the test — any real unwrapped invocation recursed, not only test 10; the SPEC's TMP_AGG_HOME alternative kept only as dead-code cleanup.
- **harness-runner.sh's three-way timeout branches collapse to one bash job-control path** (`set -m` + negative-PID group kill) — nested timeouts escape into fresh process groups (reproduced live: PPID=1 orphan), and the rewrite removes the external-binary dependency.
- **INTEGRATION.md executed verbatim** (chain-memory-section.sh wiring + one PAIRS entry); JSON output untouched, no deploy.
- **Guard is a hardcoded path-suffix match** — stops protecting on rename/relocation (disclosed, not solved).

Detail: `docs/architecture/ADR-0033-37-vibe-status-recursion-chains.md`.

## Decisions from the hook-hardening chain (ADR-0034)

Five hook fixes (issue #38): permissionDecision enum, lock ownership, trust hash,
backup-before-deploy retirement, prose-detect dual-form JSON.

Key architectural decisions:
- **block → deny** in pre-flight-pattern-enforce.sh (ADR-0009 verified enum); the two greps in the LEGACY pattern-enforce test updated — that test reads RED (11/2) against the unsynced deployment until human sync, by design.
- **Scope extended to stop-gate.sh (disclosed):** it shares approve-test-cmd.sh's exact hash-after-normalize bug from the common 2026-05-20 template; fixing only one would leave the SPEC's own symptom (silently inert stop-gate) open. stop-gate needs a separate ROOT_NORM variable — it reuses ROOT to cd.
- **Hash the pre-normalization path; store the normalized form** — trust-line format unchanged, existing entries preserved; abort on empty hash.
- **Lock ownership:** trap set only after mkdir succeeds; on timeout skip the event (never proceed unlocked, never release a foreign lock).
- **ADR-0005/blueprint §7.6 NOT edited in place** (historical illustrations); correction recorded forward via changelog entry + sync-checklist NOTE heredoc for the deployed-side deletion.

Detail: `docs/architecture/ADR-0034-38-hook-hardening.md`.

## Decisions from the skill-text chain (ADR-0035)

Six instruction-layer fixes across five standalone skills (issue #39): caller-path
contract for claude-md-generator, ghost-skill removal, git-repo-init HITL gate + URL-only,
swiftui-pro scoping line, find-skills trigger narrowing.

Key architectural decisions:
- **claude-md-generator gains the explicit caller-provided-output-path contract in its own text** (the chain's dispatch override was papering over the bug) and its first PAIRS entry (109) — the gap ADR-0025 flagged by name.
- **git-repo-init's two Fase-5 defects land in one rewrite** (gate after the clean-public-repo audit, before first commit; recommended-option convention honestly conditioned).
- **One combined RED task + five per-file GREEN tasks** (departure from interleaved precedent — all assertions are static prose anchors, no runtime bash to extract).
- **find-skills body prose broader than the narrowed frontmatter** — deliberately left (SPEC cites line 3 only), disclosed for a future issue.

Detail: `docs/architecture/ADR-0035-39-skill-text-corrections.md`.

## Decisions from the agent-scoping chain (ADR-0036)

Reconciles staging/plugin/agents/ frontmatter with blueprint section 3 (issue #40, last
of the audit-fix roadmap).

Key architectural decisions:
- **permissionMode: plan NOT restored on architect** (deliberate divergence): plan mode blocks every Write regardless of allow rules (docs-verified), and the architect's sole deliverable is writing ADR+plan unattended.
- **Bash restored-plus-widened asymmetrically:** blueprint git-scoping as the floor plus independently-evidenced verification tools (architect: bash/npx/python3/shasum; reviewer: bash/awk/python3 — narrower, untrusted-diff threat model). No add/commit/push for reviewer.
- **effort pin → xhigh** (effort: max is session-only, inert in file frontmatter — docs-verified).
- **researcher.md untouched; blueprint 3.8 syntax corrected** (mcpServers is a YAML list with type: stdio now) — inline-server deployment deferred pending a live smoke test, per ADR-0016/0029 precedent.
- **Unscoped Write on architect has no frontmatter-level fix** (path patterns documented for Read/Grep/Edit only) — disclosed; closing it needs a dedicated hook (future issue).

Detail: `docs/architecture/ADR-0036-40-agent-tool-scoping.md`.

## Decisions from the architect Write-scope enforcement (ADR-0041)

`agent-write-scope.sh`, a `PreToolUse` hook on `Write|Edit|MultiEdit`, closes the gap ADR-0036 §3.3
disclosed: Claude Code's frontmatter grammar has no path restriction for `Write`, so the architect's
write-scope line was prose. The hook confines `agent_type: architect` to `docs/architecture/` and
`docs/superpowers/plans/`; inert for every other agent, allow on every failure mode.

Two findings from the investigation, both recorded rather than silently patched:

- **The declared scope was wrong.** `architect.md` named only `docs/architecture/**`, while c2c
  Step 2 requires the plan under `docs/superpowers/plans/` and hard-aborts without it. Enforcing
  the file literally would have broken every chain run. Both roots are now named, kept in agreement
  with the hook by test E and guarded by B2.
- **ADR-0036 §2.1 asserts an exclusion its own grant does not express** — it says `git commit`/`git
  push` are not in the allowlist while granting `Bash(git *)`, which matches every git subcommand,
  and no global deny covers plain commit/push. Left as-is deliberately: `agent-tool-scoping.test.sh`
  A1 pins that grant as blueprint text reproduced byte-for-byte, so narrowing it supersedes an
  Accepted decision and belongs in its own issue. **Resolved by ADR-0042** (issue #91) — see below.

Gap 1 of issue #58 (interpreter-wrapper bypass) is **not** implemented — it needs command-content
inspection, whose false-positive surface is real (`rg "git commit"` is a legitimate read-only
search). Deployed by sync, **wired by hand**.

Detail: `docs/architecture/ADR-0041-58-agent-write-scope.md`.

## Decisions from the architect git-grant narrowing (ADR-0042)

Closes issue #91, the contradiction ADR-0041 Finding B disclosed. `Bash(git *)` on `architect.md`
becomes `Bash(git log*), Bash(git diff*), Bash(git show*), Bash(git status*), Bash(git rev-parse*)`.
Supersedes ADR-0036 §2.1 **in part** — only that one entry; the rest of §2.1 stands.

- **The grant contradicted its own paragraph.** §2.1 asserted `git commit`/`git push` were not in
  the allowlist while granting `Bash(git *)`, which by its own word-boundary citation matches every
  subcommand. No deny rule covered plain commit/push either. The architect could commit and push.
  Issue #40's own `SPEC.md:11` had already named the symptom, so this corrects a pattern back to the
  reasoning it was written for, rather than reversing a decision.
- **Issue #91's Option B (deny rules) is unworkable, not merely worse.** `permissions.deny` is
  session-global with no per-agent scoping, and the allow list carries `Bash(git commit*)` because
  the `commit` skill needs it; deny overrides allow, so the rule would block the orchestrator's own
  commit flow. Agent frontmatter has `tools` and no deny field. That is what leaves narrowing as the
  only enforcement path.
- **No-space form on purpose.** The ADR-0036 plan's Risk B warned against normalising blueprint's
  space/no-space split *by accident*; this does it deliberately, toward sec. 3.3's reviewer form. No
  mutating git subcommand begins with any of the five allowed words.
- **Prose and grant now pinned together.** `architect.md` gains a **Command scope** bullet and test
  A14 asserts every granted subcommand is named in it — the defect was a file whose prose and
  frontmatter disagreed with no way to tell which was authoritative. A13 (no mutating entry) passes
  before and after: a forward guard, not fix evidence.
- **`architect.md` gets the first agent-file `PAIRS` entry.** `sync-to-claude.sh` did not touch
  `agents/` at all, which is why PR #90's correction to the same file's write-scope line had never
  reached `~/.claude` — found by this PR's own dry-run. Agent-file edits reach deployment only now.
- **#58 gap 1 stays open and this does not close it.** `Bash(bash *)`/`Bash(python3 *)` still allow
  a wrapped `bash -c "git commit …"`. Reviewer is untouched: its git grants were already read-only,
  and its exposure is the same wrapper class. Also named: `git -C <path> log` and `git --no-pager
  log` no longer match, a real behaviour change, tolerable because no chain brief asks architect for
  git at all.

Detail: `docs/architecture/ADR-0042-91-architect-git-grant.md`.

## Decisions from the PAIRS completeness check (ADR-0043)

Closes issue #93. PR #90's fix to `architect.md` never deployed and nothing reported it: `PAIRS` did
not mention `agents/` at all, so the file was never in the incremental path. Agent and rule files
reached `~/.claude` only through `docs/RUNBOOK.md` Step 6's bulk `cp`, a full-install procedure
nobody runs for a one-line frontmatter fix.

- **The defect is the check's direction, not the missing entries.** `pairs-completeness.test.sh`
  asserted every PAIRS *src* exists under `staging/` — it validates the list's own entries and is
  blind by construction to a file the list omits. The fourteen entries added here (7 agents, 7 rules)
  are the symptom; `check_complete` is the fix.
- **Second self-test, deliberately.** The reverse check runs against a real non-empty subtree with an
  empty PAIRS list and must flag every file. A glob matching nothing reports nothing, and a silent
  zero-file result reads exactly like full coverage — the same failure shape the ADR exists to stop.
- **Directory-level sync (Option B) deferred, not rejected.** ADR-0024 requires its own ADR for it,
  and the reason is real: it must decide what happens to a deployed file that disappears from
  staging, a question per-file `PAIRS` never has to answer. The completeness check gives most of the
  protection — a new uncovered file fails CI — without settling it.
- **`staging/plugin/hooks/hooks.json` excluded on purpose.** It has no deployed counterpart at all,
  so an entry would *create* a file that has never existed, and whether CC reads a `hooks.json`
  outside a plugin directory is unverified. Named as a choice, not left as an oversight.
- Deploys nothing today: all fourteen were already byte-identical. Purely preventive — which is also
  the condition that kept the gap invisible.

Detail: `docs/architecture/ADR-0043-93-pairs-completeness.md`.

## Decisions from the claude-md-slim global-duplicate gate (ADR-0044)

Closes issue #57. `--global` deletes a DUPLICATE section from the trimmed CLAUDE.md because its
content lives in `~/.claude/CLAUDE.md`, but Step 5.2's `content-union-check.sh` was never given that
file.

- **The issue's premise was stale and the truth was worse.** It said such a run "passes the gate only
  by accident" via substring matching. ADR-0032 replaced substring with whole-line matching, so it
  did not pass — it **aborted**, every time `--global` found a duplicate, which is all `--global`
  does. Reproduced live before fixing. #36 did not break it; it uncovered it. Test G1 pins the
  pre-fix behaviour.
- **Option 1 (append the global file to the union) rejected on gate strength, not effort.** It makes
  every original line satisfiable by the global file, so a line genuinely lost in a botched
  extraction would count as preserved because something identical sits in the global CLAUDE.md — a
  false pass on the hard gate, traded for a false abort. **Test G4 fails under Option 1**, which is
  what makes the choice enforced rather than merely stated.
- **The exemption is a verification, both flags or neither.** A line counts only if it is *both*
  declared removed *and* actually present whole-line in the global file (G3). One flag alone is a
  named usage error: a declared-but-unverified exemption is worse than none. G5/G6 assert the stderr
  text, not just a non-zero exit — before the fix those calls also exited non-zero, for the unrelated
  reason that the flag name was read as the `<original>` positional.
- **The skill's own `tests/run-tests.sh` tests the DEPLOYED copy** (`$HOME/.claude/skills/…`), so its
  green result during this work validated the old script and proved nothing about the change. Re-run
  it after sync. ADR-0032 flagged the file as `$HOME`-coupled and CI-dark; this is the first time it
  actively misled a verification step.
- **The 60% DUPLICATE heuristic is untouched:** a section only mostly present in the global file
  still gets removed whole, and its minority lines now fail loudly instead of vanishing. Right
  direction, not the same as solved.

Detail: `docs/architecture/ADR-0044-57-global-duplicate-union-check.md`.

## Decisions from the native-build tool-resolution fix (ADR-0038)

Root-cause classification and fix for issue #63 (found by the 2026-07-14 post-upgrade smoke test):
on native macOS/Linux builds CC serves Grep/Glob through Bash as embedded `ugrep`/`bfs` (v2.1.117)
and silently ignores dedicated Grep/Glob frontmatter entries on Bash-equipped agents; LSP and
coder's `memory: local` Memory tool do not register in subagents on this build either.

Key architectural decisions:
- **Intentional platform behavior since v2.1.117, not a regression** (changelog-cited, live-verified
  on 2.1.209 with an 8-agent smoke plus forced-call probe); invisible to 2.1.208's tools-list
  validation, which fires only on a fully-empty resolution.
- **Frontmatter entries stay** (Grep/Glob/LSP are honored on npm/Windows builds, inert on native);
  agent files remain build-portable.
- **reviewer widened with `Bash(rg *), Bash(grep *)`**: its ADR-0036 scope allowed no direct
  search on native builds; read-only grants, same asymmetric-widening rationale, mutation
  exclusions unchanged. Its LSP first pass is now conditional on tool availability.
- **coder/debugger LSP references and the coder Memory pilot (P1) disclosed as inert, not fixed**:
  each needs its own decision; upstream docs gap (Bash+Grep example without caveat) optionally
  reportable via /feedback.

Detail: `docs/architecture/ADR-0038-63-native-build-agent-tool-resolution.md`.

## Decisions from the early-coder-feedback design (ADR-0039)

Answer to the community "review every coder write" pattern. Split by what a check can decide
without context: deterministic per-write checks (D1-D4, **shipped**) and a per-task checkpoint
review in c2c Step 5 (D5-D9, decided, **not implemented**).

Key architectural decisions:
- **`post-write-check.sh`**, PostToolUse hook on `Edit|Write`, ordered after `auto-format.sh`.
  Advisory and never blocking: always exits 0 and never emits `decision`, because
  mid-implementation code is legitimately incomplete. One file, never a project-wide type check.
- **The only channel to the model is `hookSpecificOutput.additionalContext`.** Plain stdout on
  exit 0 reaches the debug log for every event except UserPromptSubmit / UserPromptExpansion /
  SessionStart. Exit-2-with-stderr works but presents as a hook failure, wrong for an advisory
  check. Only the nested envelope is emitted, no dual form (that is a UserPromptSubmit-specific
  hedge from ADR-0034 D4).
- **Syntax checks only, no external linters at all** (`bash -n`, `py_compile` with
  `cfile=/dev/null`, `jq empty`, `yaml.safe_load`, `swiftc -parse`). Two linters produced two
  false positives under the ADR's "error severity only" rule: swiftlint fails `let x = 1` on
  `identifier_name`, shellcheck fails `echo ok` on SC2148 (no shebang). A linter's severity
  tracks its configuration, not correctness, so the rule does not hold and the linters are out
  rather than tuned. Style belongs to auto-format and the reviewer.
- **Determinism is the second payoff:** the verdict no longer depends on which tools are
  installed. The shellcheck false positive was invisible on macOS (not installed) and red on the
  CI runner (installed) — the divergence found the bug, and removing linters closes it.
- **Checkpoint review (D5) is orchestrator-side, not a hook**, because ADR-0016's hook-propagation
  blocker into workflow subagents is still open. It is a `pipeline()` stage, never a barrier.
- **The checkpoint reviews and does not fix** (D5 amended): RTF has no per-task scope and keeps
  per-branch state, so invoking it at each checkpoint would re-review earlier tasks. BLOCKER and
  MAJOR findings feed the next task's coder brief ("found in task N, do not repeat this"); MINOR
  and NIT wait for Step 6, where RTF runs the full cycle unchanged. Reimplementing RTF's fix core
  inside c2c was rejected: two fix paths would drift.
- **Severity vocabulary is BLOCKER/MAJOR/MINOR/NIT** (D7 amended). The ADR's P1/P2/P3 comes from
  deep-refactor (ADR-0018) and does not exist on this path.
- **`step5_review_mode` defaults to `none`** (D8 amended), opt-in with no new gate, flipped by
  `sed` on the additive field exactly as `step5_mode` is. `manifest-set-flag.sh` cannot do it: it
  accepts only `true|false`, and widening it would drop the guard protecting every boolean flag.
  The generated manifest carries the exact command as a comment, the only place a human finds it. Invariant 14 in `manifest-validate.sh` is conditional,
  so pre-ADR-0039 manifests stay valid with no migration.
- **D9 collapsed:** "fix-or-halt on unattended paths" presupposed a fix cycle. Review-only means
  nothing can remain unresolved, so nothing halts. `autopilot-build` and `nightly-autopilot` reuse
  Step 5 by reference, so the `none` default left both untouched.
- **Both dispatch paths gate on the same field** and state the review-only contract independently,
  pinned by a test. Otherwise a chain would behave differently depending on whether `hook_verified`
  had flipped the Workflow path on.

Detail: `docs/architecture/ADR-0039-early-coder-feedback.md`.

## Decisions from the humanize-en scope narrowing (ADR-0040)

`humanize-en` had become the most-invoked skill in the system. Six wiring points pushed it onto
internal artifacts; the skill itself was never the problem. ADR-0040 amends ADR-0015.

Key architectural decisions:
- **Perimeter is the audience, not the format:** the skill applies to text an outside human reads
  (Reddit/HN, forum, blog, newsletter, announcement, marketing, third-party email) and never to
  source code, config, commit messages, PR/issue text, ADRs, specs, plans, README and repo docs,
  changelogs, release notes, or gitignored files. **README sits on the internal side** — a judgment
  call, recorded as one.
- **The skill's `description` frontmatter carries the perimeter** with a `NEGATIVE:` block: that
  field is what the model reads when deciding to invoke, so it matters as much as the global rule.
- **Invocation is manual only.** `concept-to-code` Gate 5.5 and `commit` Step 3.5 removed.
- **Gates removed, not defaulted off** (ADR-0027 principle): every artifact the chain produces is
  internal, so Gate 5.5 could never fire. Its state transition to `step_7_commit` was load-bearing
  and survives as **Gate 5.6**, action-free. Letters `0c` and `5.5` are not reused.
- **`post-md-tells-hint.sh` retired**, and found to have been a no-op all along: plain stdout on
  exit 0 reaches the debug log, not the model, for every event except UserPromptSubmit /
  UserPromptExpansion / SessionStart (`code.claude.com/docs/en/hooks`).
- **`prompt-en-prose-detect.sh` narrowed to a writing verb AND a publication target** (two greps in
  AND). It matched the word, not the intent, so a message *about* Reddit fired it. `post` is not a
  verb here — it is the noun in "a reddit post". ADR-0034's dual-envelope output preserved.
- **`manifest-validate.sh` invariant 12 untouched:** conditional on "if present", so pre-ADR-0040
  manifests stay valid. No migration, no schema bump.
- **Historical ADRs and plans not edited in place** (ADR-0034 precedent); living docs updated.

Detail: `docs/architecture/ADR-0040-humanize-en-scope-narrowing.md`.
