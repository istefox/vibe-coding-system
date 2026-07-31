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

Gap 1 of issue #58 (interpreter-wrapper bypass) was deferred here on the false-positive argument;
**ADR-0045 closed it** after that argument turned out to be an artifact of substring matching.
Deployed by sync, **wired by hand**.

Detail: `docs/architecture/ADR-0041-58-agent-write-scope.md`.

## Decisions from the interpreter-wrapper closure (ADR-0045)

Closes issue #58 gap 1, the last piece. `agent-command-scope.sh`, a `PreToolUse` hook on `Bash`,
denies `architect` and `reviewer` any mutating git command, directly or through `bash -c`,
`python3 -c` or `awk`. Inert for every other agent, allow on every failure mode.

- **The objection that deferred this three times was wrong, and worth understanding.** A denylist on
  `git commit` blocks `rg "git commit" .` — true of a *substring* match, false of a
  **command-position** match. A verb inside quotes is data and never reaches a command position.
  That case is now section C of the test file and every assertion in it passes.
- **Threat model, stated in the ADR and the hook header: a guardrail against a shortcut, NOT a
  sandbox.** `subprocess.run(["git","push"])` splits the verb across list elements; `eval`, base64
  and variable splicing defeat it outright. **Two bypasses are pinned as expected-ALLOW** (section E),
  so if anyone closes one, the test fails and the threat-model paragraph has to move with the code.
  Anyone reading this hook as a security boundary will misuse it.
- **Two rules.** R1: mutating verb at a shell command position (start, or after `;` `&&` `||` `|`
  brace backtick `$(` or an interpreter's `-c` and its quote). R2: an exec construct
  (`os.system`, `subprocess.*`, `execSync`, …) **and** a verb anywhere — compound, so
  `os.system("git log")` and `print("git commit")` both pass.
- **Removing the interpreter grants was rejected:** ADR-0036 §2.1 evidenced both from real dispatches
  (test harness, `python3` YAML one-liners). Denying inline `-c` outright was rejected for the same
  reason — the evidenced `python3` use *is* inline code.
- **`fetch`/`pull`/`clone`/`init` are in the mutating set** though not destructive: neither agent has
  reason to run them, and the failure direction is a denied read the agent can report.
- Both agent files gain a **Command scope** bullet; test F pins prose and hook together.
  Second-order execution stays invisible — `bash x.test.sh` is allowed and the hook cannot see what
  the script does.

Detail: `docs/architecture/ADR-0045-58-interpreter-wrapper-bypass.md`.

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
- **Syntax checks only, no external linters at all** (`bash -n`, the builtin `compile()`,
  `jq empty`, `yaml.safe_load`, `swiftc -parse`). Two linters produced two
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

**Correction 2026-07-27 (Python check, `cfile=/dev/null` retired).** The `.py` check was
`py_compile.compile(..., cfile='/dev/null')`, chosen so no `__pycache__` landed in the tree. Python
3.14 raises `FileExistsError` on a non-regular `cfile` (`py_compile.py:140`) **before reading the
source**, so under a 3.14 interpreter — Homebrew's `python3` is 3.14.6 — the hook reported a defect
on every `.py` file written, valid or not, in every project (the hook is global in `~/.claude`).
Replaced by the builtin `compile()` on bytes: no bytecode is produced at all, so there is nothing
to redirect and no version guard to trip; PEP 263 cookies stay honoured. **The harness stayed green
throughout**, because its only `.py` case fed a broken file and asserted it was reported — which a
permanently-failing check satisfies for the wrong reason. Test 4b (valid `.py` stays silent) and 4c
(encoding cookie) close that; both were seen RED against the old hook. The rule this earns: **a
negative-case assertion pins nothing without its positive twin** — it cannot distinguish a check
that works from a check that fails on everything. Same family as the ADR-0043 direction lesson.

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

## Decisions from the secret-scan / dependency-gate chain (ADR-0046)

Content-based secret detection and a dependency-diff check, wired into `commit` Step 1 and the
project CI template. Closes gap G-06 of `docs/books/INTEGRATION-REPORT-agentic-spec.md`, the first
of the 21-feature agentic-spec roadmap in `PROJECT.md` Phase 2.

Key architectural decisions:
- **Detection is prefix- or keyword-anchored, never entropy-based.** Measured, not assumed: the
  cheap proxy `[A-Za-z0-9+/]{32,}` matches ordinary prose here because `/` is in the base64
  alphabet, so absolute paths match. Eleven rules, one heuristic (`assigned-secret`) carrying four
  exclusions. Verified against all 350 tracked files with zero content-rule hits, clearing the
  seven Actions SHA pins and the 60-hex fake trust hash. That run is test section D.
- **Exit codes separate "found something" from "did not run":** 0 = scan completed (findings or
  not), 2 = bad invocation, 3 = awk cannot express the rules. The third exists because every rule
  uses `{16}` interval syntax and a pre-2019 awk treats the braces literally, making every rule
  silently inert. This is the ADR-0043 lesson restated: a check reporting nothing must be
  distinguishable from a check finding nothing.
- **Reporters, not gates.** Both scripts exit 0 even when they find something; the caller decides
  whether a finding blocks. Mirrors `weakening-scan.sh`, and is what lets issue #108 later run
  them fail-closed in CI without modifying them.
- **`secret-scan.sh` owns the filename rule too, with precedence** — one line per file on a
  filename match, content scan skipped. That satisfies "reported once, not twice" in the script
  rather than in skill prose, and stops a real `.env` producing fifty lines. `protect-files.sh` is
  byte-untouched.
- **`protect-files.sh` constrains filenames at design time.** It denies any path containing
  `secrets`, so three paths this feature's SPEC named literally could not be created. All use the
  singular `secret`. Check new filenames against that deny list before writing a spec.

Known consequences, recorded rather than fixed:
- The filename rule now fires deterministically on documentation *about* secrets, starting with
  this feature's own files. Narrowing it was rejected as weakening an existing invariant guardrail.
- `commit/SKILL.md` has no test coverage and is invoked by `concept-to-code` Step 7, `project-init`
  and `autopilot-build`; a `SECRET` finding aborting an unattended run is new blocking behaviour on
  an unattended path.
- The CI template steps are inert in a generated project until issue #108 copies the scripts in.

Detail: `docs/architecture/ADR-0046-100-secret-scan-dependency-gate.md`.

## Decisions from the weakening-scan wiring chain (ADR-0047)

Wires the existing `review-triage-fix/scripts/weakening-scan.sh` detector into every path that can
produce a commit with no human present — `concept-to-code` autopilot, `autopilot-build`,
`nightly-autopilot` — plus the interactive `commit` Step 1, closing the gap where an agent could
delete or skip a failing test and still ship a green, unattended commit.

Key architectural decisions:
- **Invoked in place, never moved or copied** (`review-triage-fix/scripts/weakening-scan.sh`
  stays byte-identical). Three skills now depend on a fourth skill's private `scripts/` directory —
  the same cross-skill script dependency `autopilot-build` already has on
  `concept-to-code/scripts/manifest-*.sh`, and the price of one source of truth: issue #105's new
  detectors reach all four call sites with no second edit.
- **The detector's own trap is the caller's problem, and it is written out at every call site.**
  It always exits 0 and prints the sentinel `CLEAN` on no finding, the reverse of ADR-0046's two
  reporters. The idiom is `printf '%s\n' "$out" | grep -q '^WEAKENED'`, never `[ -n "$out" ]`
  (true even on `CLEAN`) and never `grep -c … || echo 0` (two-line `0\n0` on no match — issue #100
  hit this exact bug; `|| true` is the fix).
- **Blocking is the caller's job, not the detector's.** The gate lives at the c2c Step 5 → Step 6
  boundary and the orchestrator runs the scan itself over the cumulative diff — the dispatched
  agent's `weakening_findings` in `step5-report.json` is a record, never the gate, per the same
  "do not trust the agent's self-report" rule `review-triage-fix` Step 3 already applies to its own
  breakers. `autopilot-build` and `nightly-autopilot` inherit the halt by reference; `commit` Step 1
  gets its own call and is advisory attended, `--autopilot`-abort unattended.
- **A gap found on the way, not asked for:** `autopilot-build` Step 6's existing circuit breaker
  only reads test colour, so weakening introduced by the *fix* cycle was flagged by CIRCUIT BREAKER
  B into a recap nothing reads, then committed anyway. Now a halt, consuming the existing BLOCKER
  signal rather than running a second scan.
- **This ships an instruction, not an enforcement** (ADR-0041/ADR-0045's distinction, applied
  here): every gate is prose in a SKILL.md a model is asked to follow. Enforcing the transition in
  `manifest-transition.sh` was rejected on blast radius — a 48-pair state machine that touches no
  git today would gain a new failure mode on every transition. The harness pins that the
  instruction exists; nothing pins that it is obeyed.

Detail: `docs/architecture/ADR-0047-101-weakening-scan-wiring.md`.

## Decisions from the requirement-ID coverage chain (ADR-0048)

A `spec-coverage.sh` checker (`R-NN` IDs in a SPEC's success criteria, matched against plan tasks
and discovered tests), wired as a third Step 5 → Step 6 gate beside #100's reporters and #101's
weakening scan (issue #102). Answers a gap the chain's own history evidenced twice (ADR-0030,
ADR-0035): a requirement can be written into the SPEC and never decomposed or tested, and every
existing gate stays green because none of them measures the SPEC against the plan.

Key architectural decisions:
- **`R-NN` collides with `ADR-NNNN` unless boundary-anchored on both sides.** Measured, not
  assumed: `grep -rE 'R-[0-9][0-9]'` matches 30+ of the 34 existing SPECs, every one from the
  letter run in `ADR-0016`, `ADR-0047`, and so on. `(^|[^A-Za-z0-9_])R-[0-9][0-9]([^0-9]|$)`
  clears the corpus down to two prose lines in this feature's own SPEC.
- **Backward compatibility is the hard gate, asserted against the real corpus, not a fixture.** A
  SPEC with no IDs passes silently — exit 0, empty stdout, empty stderr, not "0 IDs OK". Section
  RE runs the checker over all 34 existing `docs/specs/*.spec.md` plus `SPEC.md` and requires the
  silent pass on each, with a `>= 30` count guard against a vacuous loop (the
  `pairs-completeness.test.sh` self-test-2 lesson, reapplied).
- **It blocks, unlike #100's reporters, and for a different reason than #101's heuristic gate.**
  #101 blocks on a heuristic (a legitimately deleted test can trigger it); this gate blocks on a
  mechanical fact — an ID is cited or it is not — so its only false-positive class is "implemented
  but not cited", which is exactly the drift the feature exists to surface. A report nobody must
  act on is a report nobody reads, the same ADR-0047 §D7 lesson RTF breaker B already taught this
  codebase at the same boundary.
- **Two adjacent gates, two opposite caller idioms, stated at the call site.** `spec-coverage.sh`
  is a checker — the caller branches on its exit code. `weakening-scan.sh`, four lines above it in
  the same SKILL.md, is a reporter — it always exits 0 and signals through stdout only. The block
  carries the literal sentence "Do not copy one block's branching into the other," pinned by an
  assertion rather than left as prose a reflow can silently drop.
- **`.md` is never a test file, and the reason is a checker that would pass itself.** Discovery is
  by basename, narrowed from `weakening-scan.sh`'s own predicate; without the `.md` exclusion,
  `--tests-root <project-root>` would discover `docs/specs/102-*.spec.md` as a test file for its
  own IDs, and every SPEC would be trivially self-covered. A checker that always passes is worse
  than none.
- **This is an instruction, not an enforcement** (ADR-0041/ADR-0045's distinction, applied again):
  the gate is prose in a SKILL.md a model is asked to follow. Enforcing the transition in
  `manifest-transition.sh` was rejected on the same blast-radius ground as ADR-0047 A2. The
  harness pins that the instruction exists; nothing pins that it is obeyed.
- **No manifest field, no schema bump.** `step5-report.json` gains one additive
  `requirement_coverage` object (`ids_declared`, `uncovered`, `status`), the fourth extension of
  that schema on the same additive terms as `step5_mode`, `checkpoint_reviews`, and
  `weakening_findings`. `autopilot-build`, `nightly-autopilot`, `project-conductor`, `commit` and
  `review-triage-fix` are untouched — the c2c gate halts before any of them gets a turn.

Detail: `docs/architecture/ADR-0048-102-requirement-ids-coverage.md`.

## Decisions from the interview-driver invocation fix (ADR-0067)

`interview-driver` loses `disable-model-invocation: true`. That flag restricts a skill to user
invocation, and `concept-to-code` Step 1 / Step H1 dispatch the skill through the Skill tool, so the
chain's greenfield entry point failed outright with `cannot be used with Skill tool due to
disable-model-invocation`. Supersedes issue #56 / PR #95 (`4baf9b2`) **in part**, for this one file.

- **The rule already existed and every guard for it was instance-level.** "A skill invoked from a
  chain must not carry the flag" is recorded in `docs/guida-workflow-orchestrazione.md` §10, cited
  by ADR-0008 and ADR-0010, and mechanically enforced by negative anchors in `design-brainstorm`
  and `clean-public-repo`. #56 violated it on a third skill anyway, because nothing checked the
  **class**. `skill-text-corrections.test.sh` **F6** now derives the chain-invokable skill list from
  `concept-to-code` §25 at run time and asserts none of them carries the flag, with a count guard
  against a vacuous derivation. Seen RED against a reintroduced flag.
- **The chain worked by accident from #29 to #95.** The flag was lost in the issue-#29 staging
  refresh and the chain quietly came to depend on its absence. #56 correctly restored a documented
  blueprint default and, in doing so, broke Step 1. The lesson is not "do not restore defaults" —
  it is that a file's callers are part of its contract, and #56 checked the file against the
  blueprint without checking it against `concept-to-code` §25, which names this skill as
  chain-invokable, or against the skill's own `description`, which says the same.
- **There is no settings-level exemption, verified against the CC 2.1.220 binary.** Frontmatter
  locks the skill state to on/name-only; `skillOverrides` only ever disables further. The
  contradiction had to be resolved in one of the two disagreeing files, not in configuration.
- **Scoped to one skill.** `fastapi-react-vibe`, `goal-loop` and `research-prompt` keep the flag;
  no chain invokes any of them. `interview-driver` was the only chain-invoked carrier.
- **Residual risk accepted and bounded:** the model can self-invoke the interview again. No
  unattended path wants it (`nightly-autopilot` Phase P uses `spec-from-issue` precisely because the
  interview is interactive, `autopilot-build` starts post-SPEC, c2c autopilot hard-aborts without
  `SPEC.md`), so a stray invocation costs a turn in an attended session. A dead Step 1 costs the
  chain's whole greenfield entry.
- **`skill-text-corrections.test.sh` F5 changed direction, and that is the reusable part.** It
  banned the literal string `Three staged skills carry that flag` — yesterday's specific wrong
  wording. Under this ADR the count legitimately returns to three, so the ban would have fired on
  the *correct* sentence. It is now a positive check of the carrier list against the files. Same
  family as the ADR-0043 direction lesson: a guard written against one past error does not
  generalise, ask what it would do when the text changes for a good reason.

Detail: `docs/architecture/ADR-0067-interview-driver-model-invocation.md`.

## Decisions from the worktree isolation contract chain (ADR-0068)

One contract for how a dispatched agent's working environment is created, what it contains, and how
its output returns (issue #176, closing #175). Isolation is repaired, not removed; `isolation:
"none"` — a value the Agent tool rejects outright — is deleted from all 11 call sites and never
named again.

Twelve facts (F1–F12) were measured by live probe on 2026-07-28, CC 2.1.220, before any design; the
same probe then falsified two of the ADR's own first-draft premises (F13, F14), so the contract that
shipped is smaller than the one first approved at Gate 2. The SPEC's table records the probe behind
each fact. That discipline exists because ADR-0016 asserted `isolation: none` as pre-existing fact,
never checked it against the tool schema, and ADR-0049 and ADR-0050 then built on it.

Key architectural decisions:
- **The base contract is ONE layer, not two (§D1, revised 2026-07-28).** `worktree.baseRef: "head"`
  is the native mechanism — docs-verified: *"Subagent worktrees … branch from your repository's
  default branch unless `worktree.baseRef` is set to `"head"`"*, and `"head"` is documented for
  exactly this case. Both `~/.claude/settings.json` and `staging/user/settings.json` carried
  `"fresh"`. The first draft added a second layer, a `WorktreeCreate` hook, for scoped enforcement
  plus a per-creation audit record. **That layer is deleted** — the probe refuted the two premises
  it needed.
- **No hook is registered, and the reason is measured, not stylistic (§D2–§D4).** F13: the payload
  identifies the *dispatching session* — `session_id`, `transcript_path`, `cwd`, `prompt_id`,
  `hook_event_name`, `name` — never the agent about to run; no `agent_type`, no `agent_id`, no
  `base`/`branch` field of any kind. F14: exit 0 with empty stdout does not decline and fall through,
  it **aborts** the dispatch outright ("hook succeeded but returned no worktree path") — there is no
  allow path on this event at all. And the event has **no matcher**. The three compound: a
  registered hook cannot scope itself to this chain's four agent types and cannot decline for
  anyone else, so registering one means **owning every worktree creation on the machine** — every
  `--worktree` session, every background session, in every project. That blast radius is
  categorically different from this repository's existing hand-wired `PreToolUse`/`PreCompact`
  hooks, none of which can do that much damage wired wrong.
- **The audit record the hook would have carried moves into the orchestrator's merge-back (§D5), and
  is stronger there.** The hook could only log the base it *intended* to use, from inside the
  mechanism being audited, at creation time. The orchestrator instead reads
  `git -C "$worktreePath" rev-parse HEAD` after the dispatch returns and compares it against the
  feature branch's `HEAD` as it stood at dispatch time — observed evidence of what the worktree
  *actually* forked from, from outside it, after the fact. A mismatch halts, on the same path as a
  merge conflict.
- **The probe instrument is retained, unregistered, and must never be wired (§D2).**
  `staging/plugin/scripts/worktree-capture.sh` is the re-measurement tool that produced F13–F16; it
  carries no `PAIRS` entry and is not deployed, on the same terms as this repository's other
  probe-only scripts. Its header states in its first lines that registering it aborts every worktree
  creation on the machine, because it always returns no path.
- **The tester runs in a worktree too and merges first (§D6)**, so the coder forks from a `HEAD` that
  already contains the red tests. ADR-0049 §D2's dirty-tree condition is retired as a consequence,
  and ADR-0050 §D4's reconciliation paragraph with it.
- **`review-triage-fix/SKILL.md:158` is NOT retired (§D9)** though it greps identically. It selects
  dispatch-versus-inline, not one isolation value versus another, and its premise survives: a
  worktree forks from a *commit*, so forking from `HEAD` does not make uncommitted work visible —
  only §D5's commit-then-merge protocol does, and RTF has none. R-11's assertion anchors on the
  isolation-selection compound phrase for this reason, never on the bare command string.
- **Both dispatch paths pass isolation explicitly (§D7).** Frontmatter never reaches the Workflow
  path (F4, corrected by F16), which is why the two behaved oppositely rather than merely
  inconsistently. The Agent tool has no `effort` parameter; `opts.effort` exists on the Workflow
  path only.

Known consequences, recorded rather than fixed:
- **F13–F18 are true of CC 2.1.220 and of nothing else.** ADR-0016's v2.1.154 experience is the
  precedent: the substrate moves. A future build that adds an agent discriminator and an abstain
  state to `WorktreeCreate` reopens the two-layer design on its merits — re-run the probe with
  `worktree-capture.sh` and record the result before treating the question as settled again.
- `worktree.baseRef: "head"` is user-scope and global: it changes `--worktree` and `EnterWorktree`
  behaviour for every project on this machine, and it can drift back to `"fresh"` with no signal
  other than the Step 5 pre-flight assertion and §D5's per-stage base-fork comparison.
- Both halves of the contract are **wired by hand** — `sync-to-claude.sh` does not edit
  `settings.json`. Same inertness pattern as `write-scope-enforce.sh`, `agent-write-scope.sh`,
  `test-write-scope.sh` and `precompact-guard.sh`.
- `**Pre-dispatch: worktree isolation check` is anchored by `recovery-preflight.test.sh:251` and
  `workflow-dispatch-pins.test.sh:84`. Rewriting the block's body is safe; changing the heading
  breaks both silently.

Detail: `docs/architecture/ADR-0068-176-worktree-isolation-contract.md`.

## Decisions from the plan-task form chain (ADR-0069)

One canonical plan-task form, in one place the consumers derive from (issue #172). A heading-form
plan — `## Task 1 — … (R-01)`, no checkboxes — was refused by `concept-to-code` Step 5 and by
`autopilot-build` check 5, both telling the operator the plan "may be malformed". It was not:
`architect.md`'s Output Format sanctions **both** the heading and the checkbox form, and the
consumers were reading a narrower contract than the writer was given.

- **The count never measured what its name says.** Nothing in the chain ever writes `[x]` back into
  a plan file — completion lives in `step5-report.json` as `tasks_completed`, and the `[x]`
  machinery in c2c belongs to `PROJECT.md`. So a plan's checkboxes are always unchecked and
  `unchecked >= 1` is a malformed-plan guard, not progress. Worse, in a heading-form plan the
  checkboxes that exist are **sub-steps inside a task**, so the count was never counting tasks
  either. It worked only because every caller needs `>= 1` and never the value.
- **Measured, not assumed: 57 plans, four parsers, three answers.** `spec-coverage.sh` (checklist
  item OR H2–H4 containing "Task") matches 56; the two consumers (any `- [ ]`) match 50 — seven
  plans carry no checkbox at all; `diff-budget-check.sh` (`- [ ] **Task N`) matches 18. The
  heading form is not a tolerated deviation, it is what architects write.
- **The predicate lives in `plan-task-predicate.awk` and is LOADED, never pasted** — `awk -f
  <predicate> -f <program>`. Making three files agree would have left three answers that agree
  today; this leaves one file that decides. `spec-coverage.sh` had **two copies of its own** and
  now has none. `plan-tasks.sh --count` is the single entry point for both SKILL.md consumers.
- **It is a CHECKER (branch on exit code), and the two gates beside it at the same Step 5
  checkpoint are REPORTERS** (always exit 0, signal on stdout, print `CLEAN`). Exit 3 = the check
  did not run, distinct from 0 tasks — without it a broken awk prints 0 and every caller aborts
  blaming the plan, which is #172 reproduced one level down.
- **The 57th plan is recognised by nothing, including `spec-coverage.sh` today.**
  `2026-06-06-claude-md-slim.md` writes `### Step N — …`. Widening to `Task|Step` was rejected: it
  changes token extraction for every plan to accommodate one completed plan. Exempted **by name**
  in test `PTE2`, with `PTE3` asserting the file still exists so the exemption cannot outlive its
  subject. A new unrecognised plan fails; it does not disappear into a threshold.
- **`diff-budget-check.sh` is deliberately out of scope — issue #184.** Its predicate does not
  merely recognise a line, it *delimits a block*, and a budget's file scope depends on that
  boundary. Same measurement shows it has never fired: the single corpus plan declaring a `Budget:`
  is heading-form, so ADR-0052's check has produced no finding on a real plan since it shipped.

Known consequences, recorded rather than fixed:
- **Inert, and worse than inert, until sync.** Both call sites invoke `~/.claude/…`; without the two
  new `PAIRS` entries they exit 127 and the "did not run" branch aborts every dispatch.
  `pairs-completeness.test.sh` cannot see this (skill `scripts/` are outside its scope, ADR-0043) —
  `PTB7` pins the entries directly.
- The count over-counts on purpose: `## Tasks` as a section heading matches, a checkbox sub-step
  matches. Correct for a `>= 1` guard, wrong for anything that needs a real task count or a task
  block — that is exactly what #184 needs.
- `**Check 5 — Plan has tasks:**` and `**Pre-dispatch: plan structure validation` are extraction
  markers for `plan-task-count.test.sh` PTC/PTF. Rewriting either block's body is safe; changing a
  heading breaks the extraction. **That last clause said "reports as a skipped section rather
  than a failure" and was measured wrong — see ADR-0083 §D3: it reports as a LOUD failure that
  also removes five dependent assertions from the run. Both extractors were re-anchored on
  `fence-contract:` markers in #206, so a heading rewrite now breaks nothing.**

Detail: `docs/architecture/ADR-0069-172-plan-task-form.md`.

## Decisions from the diff-budget predicate chain (ADR-0070)

Closes issue #184. `diff-budget-check.sh` had produced no finding on any real plan since ADR-0052
shipped it in July, and nobody noticed: it is a reporter, so a plan it cannot parse looks exactly
like a plan with nothing to report — the common, documented, legitimate case.

- **Four independent defects, not one**, three invisible until the one above is fixed. (1) The task
  predicate needed `- [ ] **Task N` — 18 of 57 plans. (2) The budget syntax required the paren group
  at strict end-of-line, and the one plan that declares budgets writes them in italics
  (`*Budget: … (~90 lines)*`), so all nine failed. (3) `git diff --stat` **elides long paths** at the
  default 80 columns, so a file was reported out of scope AND its lines went uncounted. (4) git
  **right-aligns the count column**, and the extractor required a digit immediately after `" | "`, so
  every file narrower than the widest one in the diff was dropped from the candidate set entirely.
- **Defect 4 is the lesson.** It survives a correct predicate, a correct budget parse and an
  untruncated path, and it was found by running the checker on a two-file diff and asking why the
  totals were short. Not by reading it, and not by a harness that had been green for months.
- **`is_task_opener()` is a SECOND predicate, beside `is_task_line()` in the same shared file.**
  They answer different questions: "is there a task here" (guard, `>= 1`, over-counting is safe)
  versus "does a task BLOCK START here" (boundary, over-matching corrupts attribution). A checkbox
  sub-step reading `- [ ] Re-run Task 2.` satisfies the first and must not satisfy the second, or a
  `Budget:` gets attributed to whatever number the prose happened to mention.
- **`--stat=999` at both call sites, never a bare `--stat`.** The script also resolves an elided
  tail against the declared set, but only when it resolves to exactly one **distinct** path —
  `MASTER_SCOPE` is a union across tasks, so a file declared by five tasks appears five times and a
  raw line count reads that as ambiguity.
- **BB2 had pinned the bug as the contract.** It asserted every plan in the corpus stays `CLEAN`,
  which passed only because the check was inert, and would have blocked this fix. Its intent (a
  plan declaring nothing stays silent) is preserved; its population is corrected, and `BB2b` bounds
  the exclusion.

Known consequences, recorded rather than fixed:
- **A dormant feature becomes active.** The first Step 5 after this deploys may report `BUDGET`/
  `SCOPE` on work in flight, against budgets written when nothing read them. Advisory by contract,
  but the first one will look like a regression.
- `task_num()` extracts digits only, so `## Task 1b` and `## Task 1` both resolve to `1` and
  `--tasks 1b` cannot be expressed — a budget can be attributed to a sibling task on any plan using
  letter suffixes. Changing the identifier model touches `--tasks` expansion and the `BUDGET_FILE`
  key; deliberately out of scope.
- Two plans use a different word for a task entirely (`### Step 0 —`, `### T1 —`) and match no
  predicate. Exempted by name in `PTG9`, with `PTG10` asserting both still exist.

Detail: `docs/architecture/ADR-0070-184-diff-budget-task-predicate.md`.

## Decisions from the Step 5 pre-flight producer chain (ADR-0071)

Closes issue #173, the last of group A. ADR-0050's pre-flight asserts a clean tree on a feature
branch at Step 5 entry. Both assertions are right; **neither had a producer**. `git checkout -b`
appeared in `concept-to-code/SKILL.md` exactly once, inside 5.0.2's own error message, so every
first run of the chain failed the pre-flight — structurally, not situationally.

- **The printed remediation was actively wrong.** `git stash push -u` would have stashed `SPEC.md`,
  the ADR and the plan — exactly what the coder and tester dispatches read. The live run reached
  Step 5 only because the model overrode the instruction. 5.0.1 now branches on WHAT is dirty:
  commit for the chain's own artifacts (never stash), stash for the unrelated-dirty-tree resume that
  ADR-0050 §D2 describes, and commit-then-stash for both. `RH11` asserts the second case survives —
  a fix that narrows a behaviour must not delete it.
- **Gate 4.0 is the producer**, defined once and referenced by the three paths that proceed past
  Gate 4, and by NOT the "Abort chain" path — an aborted chain must not leave a commit behind
  (`RH3`). Gate 4 is the last point the old session can act and exactly where the fresh session's
  assumptions begin.
- **It invokes the `commit` skill and never hand-rolls git.** Step 3.6 there already creates the
  branch and structurally refuses the default branch; Step 7 of this chain already calls it. A
  dedicated branch-and-commit would be a second commit path that drifts from the first — the defect
  ADR-0069 had just removed from the plan-task predicate, in a new place. `RH4b` forbids raw
  `git checkout -b`/`commit`/`add` inside the Gate 4.0 block.
- **`--no-pr` is new on `commit`** and skips Steps 6/6b/6c/7 while **leaving the Step 4 approval gate
  intact** — that is the whole difference from `--autopilot`, which skips approval and skips Step 6
  as a side effect. Orthogonal, combinable. Documented in Arguments AND at Step 6, because a reader
  following the numbered steps does not re-read the header.
- **`autopilot-build`'s entry contract was the wrong half of a disagreement.** It said the artifacts
  "exist on disk" while handing off to a pre-flight requiring them committed on a feature branch. It
  now names the committed state and points at Gate 4.0.

Known consequences, recorded rather than fixed:
- The feature branch's first commit is documentation-only, and a chain abandoned during Step 5 leaves
  a branch carrying a design commit and nothing else. Cheap, reversible, and the price of a
  `recovery_baseline_sha` that points at a commit which actually contains the artifacts — before
  this it recorded a state that had never been committed.
- Gate 4.0 adds one HITL gate to the attended flow (the `commit` skill's own). It appears where a
  decision already existed implicitly, rather than adding a new decision.
- `commit/SKILL.md` still has no harness of its own (ADR-0046 noted this); `RH7`–`RH9` are the first
  assertions in the repository that read it.

Detail: `docs/architecture/ADR-0071-173-step5-preflight-producer.md`.

## Decisions from the SPEC near-miss self-repair chain (ADR-0072)

Closes issue #171. `spec-coverage.sh` ran against a SPEC declaring 17 requirements, reported
nothing and exited 0: they were written as `- R-01 — …`, and a declaration is recognised only as
the first token of a **checklist item**. A plain bullet was examined by nothing — the token reached
neither the declared set nor the malformed set nor the out-of-section set — so `DECL_N` stayed 0 and
the SPEC took the documented silent no-IDs path.

- **Detect and HEAL, not detect and block.** The issue framed it as fail-or-ignore; the third option
  is better. A chain that stops with a precise command beats one that stops with a wrong command,
  and a chain that applies the command itself beats both. `spec-normalize-ids.sh` adds the missing
  marker; `concept-to-code` Step 5 runs it automatically on that one diagnosable cause and prints
  the diff afterwards.
- **Normalise, never regenerate.** Re-invoking `interview-driver` means redoing the interview;
  `spec-from-issue` rebuilds from the issue and discards human edits. The SPEC has already passed
  Gate 1, so regeneration destroys an approved review. `- R-01 — X` and `- [ ] R-01 — X` say the
  same thing, so adding the marker changes no content — a FORMATTING repair, and the boundary is
  stated so nothing later grows into rewriting requirement text.
- **This composes with ADR-0071 and depends on it.** Automatic in-place editing is safe because
  Gate 4.0 has already committed the planning artifacts, so `git checkout -- <spec>` reverses it.
  Without #173's producer this would be writing to an unversioned file.
- **The detection is bound by the repair's reach (§D4):** every flagged line must become readable
  once the marker is added, or the gate reports a problem, rewrites the file and still fails. That
  invariant is what excludes a bold-wrapped id — `- [ ] **R-01**` is invisible to the checker too,
  so normalising would not help. A pre-existing blind spot in both forms, pinned by `RN12`.
- **The near-miss guard is NOT conditioned on `DECL_N`, unlike its sibling (§D5).** An id outside
  every recognised section is only evidence when nothing was declared; a plain bullet INSIDE a
  recognised section has no innocent reading. The mixed SPEC is the worse case — only *partially*
  silent. The first draft reused the `DECL_N == 0` condition and the mixed fixture caught it.
- **`spec-id-predicate.awk` is the one place that decides**, loaded by the checker and by the
  repairer. A repair keyed on a different rule than the check would rewrite what the check accepts
  or miss what it rejects. Depends on `plan-task-predicate.awk`, loaded first.

Known consequences, recorded rather than fixed:
- **A gate now edits a human-reviewed artifact without asking.** Bounded, reversible and printed as
  a diff, but it is the first time the chain does this to a SPEC.
- Bold-wrapped ids stay invisible to the checker in both forms. Named, tested, unfixed.
- No new stdout token: the near-miss reports as `MALFORMED` and the two causes are distinguished on
  stderr, so the exit-code contract is untouched.
- `RN1` is not fix evidence on its own — the pre-fix checker also exited 3 on the fixture, via
  `ORPHAN`. `RN2`/`RN3` distinguish the right code from the right code for the wrong cause; `RN6`-
  `RN9` guard the repair's blast radius rather than proving it runs.

Detail: `docs/architecture/ADR-0072-171-spec-id-near-miss-self-repair.md`.

## Decisions from the gate-blind-spot chain (ADR-0073)

Closes issues #178 and #177 together — the same question asked twice at the Step 5 → Step 6
boundary, with **opposite answers**, decided jointly because deciding either alone would have got
the other wrong.

- **#178 gets a disclosure, not a gate.** A coder declined three plan-specified Pydantic bounds for
  a sound reason accepted at Gate 5; it was found because the orchestrator read the diff. Every
  existing gate measures something adjacent and passes a deviation. `step5-report.json` gains an
  additive `plan_deviations` array (fifth extension, no version bump), the coder brief asks for a
  terminal `PLAN DEVIATIONS:` block with an explicit `none` form, and Gate 5 renders it.
- **The self-report objection does not apply, and the reason is worth keeping.** "Do not trust an
  agent's self-report" (ADR-0047 §A3) is a rule about **gates**. A disclosure feeding a human
  decision is the opposite case: a coder that hides a deviation leaves the reviewer exactly where it
  was before the field existed, so the field can only add information, never remove a check.
- **The Step 6 reviewer is briefed with the plan** (#178's option 2, yes) — and told a departure is
  **not automatically a defect**. Without that sentence the lens becomes the conformance gate the
  ADR rejects, implemented by prompt instead of by code, whose likely first act is blocking a
  correct deviation. A mechanical conformance gate is rejected structurally: a plan is prose.
- **#177 gets a sentence, not a detector, and the number is on record.** Measured over 354 commits
  (89 touching a test): a rule on `asrt_rm == asrt_add > 0` fires **twice**, and **both hits are
  prose** — a comment containing "assertion", an `ok "…"` message containing "asserts". Precision
  0 of 2. Secondary to the structural argument: correcting a wrong test and relaxing a right one
  produce **byte-identical diffs**, so no rule over a diff separates them. ADR-0051 §D5 hit the same
  wall on the same script; this applies that precedent one step earlier — not shipped at all.
- **`CLEAN` now says what it does not mean, in three places**: the script header, c2c's Step 5 gate
  block, and `commit`'s Step 1 block — because whoever reads a CLEAN line reads it there, not in the
  script. The `commit` block points at its **Test diff** section as what actually covers this class.
  It is a human step and the ADR does not pretend otherwise.
- **`plan_deviations` renders OUTSIDE the six-array roll-up** (ADR-0052 §D5 bounded it deliberately).
  The exclusion is semantic: the six are findings asking "review or not"; a deviation asserts nothing
  is wrong and asks "is this departure acceptable".

Known consequences, recorded rather than fixed:
- `plan_deviations` is unverified and always will be. A coder that deviates without declaring is
  exactly as invisible as before; the risk is a future reader treating a short list as evidence.
- **The in-place assertion blind spot stays open.** Documented, measured, unclosed. Anyone relying
  on the weakening gate for assertion integrity is relying on something that does not exist.
- The reviewer lens is prose in a prompt; nothing enforces that the plan is read.
- **Lesson pinned in the harness:** a prose assertion must not depend on where a line wraps. E5/E6/E8
  first failed on markdown reflow, not on missing content — `step5-checkpoint-review.test.sh` now
  matches against a flattened copy of the file. The line-wrap cousin of rule 3.

Detail: `docs/architecture/ADR-0073-177-178-what-the-gates-do-not-see.md`.

## Decisions from the self-arming marker chain (ADR-0074)

Closes issue #127. `write-scope-enforce.sh` bound a fix agent to the scope `[^` because it scanned
**every** `user` entry and **tool results are `user` entries** — an architect briefed to read the
hook's own source pulled the literal grep pattern into its transcript and armed the hook against
itself. Fixed in flight on 2026-07-26 (read only the FIRST `user` entry); this closes the missing
regression test and the sibling audit the issue asked for.

- **The class, not the instance:** a marker that is both instruction and trigger arms on any
  transcript that quotes it. The population most exposed is *agents working on the hook system*,
  because they are the ones told to read these files. No refinement of the marker helps — the
  dispatch prompt and a file quoting it are byte-identical by construction. Position is the only
  exact discriminator.
- **`agent-command-scope.sh` had the same class, reached through the command string, and two
  defects in opposite directions.** (1) R1's `-c` anchor was unqualified, so every search tool's
  COUNT flag matched and `grep -c "git commit -m" f` was **denied** — a guard arming on text about
  the thing it guards. The hook's own header says "an **interpreter's** -c": the prose was right,
  the regex was not. (2) R1's trailing boundary was `([[:space:]]|$)`, so the closing quote in
  `bash -c "git push"` escaped it — **the exact form ADR-0042 and ADR-0045 both name as the case
  this hook exists to close was ALLOWED.** Section A stayed green because every assertion in it
  carries an argument after the verb. Found by running the regex over the ADRs' own examples, not
  by reading it (rule 11 again).
- **`agent-write-scope.sh` is immune, structurally**, and `F1` asserts it — it reads no transcript,
  so no text an agent causes to be read can change what it enforces. Pinned as an assertion because
  a future "configurable roots per dispatch" change would remove exactly that property and would
  look like an improvement.
- **`test-write-scope.sh` already carried the fix** (ADR-0049 §D9, TB7/TB8). `pre-flight-pattern-
  enforce.sh` reads assistant entries and ALLOWS on match, so a spurious match is a missed check,
  never a deadlock. Both audited, neither changed.
- **E0 is the reason section E means anything:** it runs the pre-fix extraction over the fixture and
  requires the live incident's own `[^` back. Verified against a reconstructed pre-#127 hook — E1
  and E4 fail, everything else stays green, which is the shape of the original invisibility. E4
  anchors `head -1` by POSITION; a first draft grepped the neighbourhood, matched the pipeline's
  second unrelated `head -1`, and pinned nothing.

Known consequences, recorded rather than fixed:
- `agent-command-scope.sh` now denies strictly more than it did, on a live guardrail — correct
  direction, still a behaviour change.
- The interpreter list is a fixed enumeration; anything outside it takes the `-c` path unguarded.
- The threat model is unchanged: a guardrail against a shortcut, not a sandbox. E1/E2 still pin
  the list-form `subprocess.run` and variable-splicing bypasses as expected-ALLOW.

Detail: `docs/architecture/ADR-0074-127-self-arming-marker-class.md`.

## Decisions from the hook_verified state chain (ADR-0075)

Closes issue #123, the last of the open-issue roadmap. `nightly-autopilot` check 6 iterated every
manifest in `docs/manifests/` and aborted the whole roadmap on any `hook_verified` that was not
`true`/`false`. Two long-completed chains hit it. Neither was corrupted: both **predate the field**,
which ADR-0016 added to `manifest-init.sh` afterwards.

- **`m.get()` cannot tell three states apart.** It returns `None` for an ABSENT field and for an
  explicit null, and the shell one-liner produced an empty string when the file could not be PARSED
  at all — so one comparison reported three situations with one sentence, and that sentence named
  the least likely of them ("corrupted or was hand-edited"). Now four branches on a discriminated
  token: valid, absent-on-completed (pass, with a note), absent-in-flight (abort), invalid (abort,
  naming the value), unreadable (abort, as **did not run**). That last one is the same distinction
  `secret-scan.sh`, `spec-coverage.sh` and `plan-tasks.sh` already make — reporting an unread file
  as bad data is the original error one level down.
- **Leniency is bounded by `current_step: completed`, and the boundary is the point.** A completed
  chain's dispatch mode cannot affect a future run; a chain in flight without the field is one
  nobody knows the dispatch path of, and guessing is what the safe default exists to avoid.
- **The issue's third checkbox — narrow the loop to pending roadmap features — is declined with
  reasons.** It needs the PROJECT.md-feature → manifest mapping ADR-0030 §2.2 already had to fix
  twice for suffix collisions, and a wrong mapping there fails **silently** by skipping a manifest
  that matters. Worse than the bug being fixed.
- **`autopilot-build` check 7 had the MIRROR defect and is fixed in the same pass.** Same field,
  same one-liner, one skill over: `[ "$hv" = "None" ] || [ -z "$hv" ]` means anything that is
  neither PASSES, so `hook_verified: maybe` sailed through and the run branched on it. Nightly
  aborted on too much; autopilot-build aborted on too little. Now asserts the two VALID values —
  the form that cannot rot as the invalid set grows.
- **`project_root` note corrected:** it is **five** manifests carrying a dead
  `/Users/stefanoferri/…` path, not the one the issue named. Nothing iterates `project_root` across
  manifests, so it blocks nothing; left unfixed because rewriting five completed historical records
  to a path they were never created under falsifies the record for no consumer.

Known consequences: check 6 now passes on strictly more inputs (bounded to completed chains, but a
guard relaxing); the lenient branch prints a `note:` per tolerated manifest; the five invariant-4
failures remain. C8/C9/C12/C13/D1/D2 pass before and after — forward guards, not fix evidence.
C7/C10/C11/D3/D4 are the five that were RED.

Detail: `docs/architecture/ADR-0075-123-hook-verified-states.md`.

## Decisions from the additive-field state chain (ADR-0076)

Closes issue #195, phase 4.1 of the roadmap. #123 was the instance; this is the rule and the one
reader that makes following it cheap.

**THE RULE — a checker that reads a manifest field must treat ABSENT as a distinct state from
INVALID and from UNREADABLE, and must decide what absence means from the manifest's
`current_step`. Read the state through `concept-to-code/scripts/manifest-field-state.sh`; never
with a bare `m.get()`.**

- **Why a bare `m.get()` cannot work.** It returns `None` for a field that is absent AND for one
  explicitly set to null, and the shell one-liner around it returns an empty string when the file
  could not be PARSED at all, because the traceback went to `/dev/null`. Fields reach
  `manifest-init.sh` as additive by design (ADR-0016, ADR-0039), so absence is an expected state
  with an era attached, not an error.
- **The helper REPORTS, it never DECIDES** — `PRESENT|<value>` / `ABSENT|<current_step>` /
  `UNREADABLE`, exit 3 for "could not run" (environment) as distinct from `UNREADABLE` (input).
  The value domain is the caller's and has to be: `hook_verified` is a boolean, `step5_mode` is
  `workflow|agent_fallback|null`, `step5_review_mode` is `none|checkpoint`. There is no general
  "valid".
- **The two call sites apply OPPOSITE policies to the same ABSENT state and both are right.**
  nightly check 6 sweeps a corpus of long-completed chains whose dispatch mode cannot affect
  anything → tolerate. autopilot-build check 7 reads the one manifest about to be built, in flight
  by definition → abort. Both files carry the sentence **"Do not `reconcile` the two"**, and test
  section P asserts both branches and both notes still exist. A helper returning a verdict would
  have had to flatten this.
- **A missing helper fails the gate CLOSED**, with the sync remedy printed — the opposite of
  `commit`'s resolver, which degrades to today's behaviour because it guards an advisory reporter
  and this guards a gate. The dependency class is not new: check 8 of the same pre-flight already
  executes a `~/.claude` script.
- **Strictness preserved, including a case that looks like a bug:** a quoted `"true"` reads
  `true`, not `True`, so a caller asserting the booleans rejects it. That is what the one-liners
  did, and a quoted boolean in a machine-generated manifest is a hand-edit.
- `manifest-validate.sh` already applies this rule as a habit, case by case (invariants 12 and 14
  are conditional "if present" for exactly this reason) — the same rule discovered independently
  three times in one file, which is the evidence it is a rule. Its 28 invariants are NOT converted;
  invariant 4 is issue #197's subject.

Known consequences: two pre-flight gates now depend on a deployed script and fail closed until
sync; the rule is prose and nothing enforces that a new checker uses the helper (#193's derived
guard is the shape that could). P1/P2/R1 guard the design rather than evidence a fix.

**Harness lessons, recorded because they recur:** `X6` first failed at exit 127 — emptying `PATH`
to hide `python3` also hides `bash`. `P3` failed on a comment-line wrap, the ADR-0073 lesson one
layer down. `P4` counted the explanation as the defect: its needle was the old one-liner, which
both files legitimately quote while explaining why it was replaced (rule 12).

Detail: `docs/architecture/ADR-0076-195-additive-field-state.md`.

## Decisions from the transcript-scan class guard (ADR-0077)

Closes issue #193, phase 4.2 of the roadmap. #127 fixed one hook and audited three, and every guard
it left is instance-level — nothing asserted the rule, so a new marker-driven hook reproduces #127
with the whole harness still green.

**THE RULE — a hook that extracts a marker from a subagent transcript must read only the FIRST
`user` entry, or declare in its own source why it does not.** Tool results are `user` entries.

- **The derivation is BROAD on purpose** (every `plugin/scripts/*.sh` mentioning `transcript_path`
  or `.jsonl` — ten files, probes included) and narrowing happens through declared exemptions.
  Asking which direction the guard runs in settles it: a narrow derivation validates the files it
  names and is blind to one it omits, which is #127's own failure mode applied to its own guard.
- **Exemptions live in the hook, never in a list inside the test** — `# transcript-scan-exempt:
  <reason>`, line-anchored. A filename-keyed list is ADR-0069 PTD's identity waiver: it does not
  travel on rename and it lets a test author excuse a hook without touching it. T4 requires the
  reason to be ≥40 chars, Z3 requires a real declaration so a passing mention in prose does not
  excuse anything, T5 forbids the list in the test.
- **The two enforcing hooks must COMPLY, not declare** (T2), and must hold no exemption (T3) — a
  file that was both would let a later edit drop the `head -1` and still pass on a stale waiver.
- **`pre-flight-pattern-enforce.sh` is exempt on DIRECTION, the weaker kind**, and its declaration
  says so: it reads `assistant` entries and ALLOWS on match, so a spurious match is a missed check
  rather than a deadlock — but its real exposure is #194, open, and the last line reads *"Do not
  read this line as audited and fine"*. A waiver that reads as a clean bill of health is worse than
  none.
- **The guard found a defect in its own predicate on the first run.** `compliant()` required
  `| head -1` on the line AFTER the jq read — `write-scope-enforce.sh`'s shape. `test-write-scope.sh`
  writes the same pipeline on ONE line and was reported non-compliant. A predicate written against
  one syntactic shape, one level up from the rule it enforces.

Known consequences: the derivation stops at `plugin/scripts/` — no skill script reads a transcript
today (measured), so a future one would slip through and T0's count guard would not notice.
`compliant()` recognises the two shapes that exist; a third (python3, grep) would be a false
positive needing a predicate extension or an honest exemption. An exemption is a sentence a human
wrote — T4 checks it is long, nothing checks it is true. T5/Z4/T3 pass before and after.

Seen RED against a reverted tree (both enforcing hooks broken): T1 and both T2 fail naming both
files, the other nine pass.

Detail: `docs/architecture/ADR-0077-193-transcript-scan-class-guard.md`.

## Decisions from the terminal project_root chain (ADR-0078)

Closes issue #197, completing phase 4.2. `manifest-validate.sh` invariant 4 required `project_root`
to be an existing directory in EVERY state, which asserts that every manifest is validated on the
machine that produced it. Five of this repository's own manifests carry a path from a different
machine and failed for that reason alone.

- **The paths are not corrupt** — they are accurate for the machine those chains ran on. Presence
  is still required in every state (a missing field is corruption at any point); only the
  directory-exists half is now conditional.
- **Terminal means ABSORBING, verified against the state machine rather than assumed:** no
  transition pair in `manifest-transition.sh` has `completed`, `failed` or `aborted` as its SOURCE,
  and the unconditional `any -> failed|aborted` branch creates edges INTO two of them and none out.
  **Wider than ADR-0075's `completed`-only tolerance, deliberately** — that rule's argument covers
  all three identically, and ADR-0075 named one because one was all its two manifests had.
  Narrowing here would follow its letter past its reason.
- **It cannot weaken a live path**, which is what makes it safe rather than convenient: every
  consumer reads an in-flight manifest (`manifest-transition.sh` validates pre-transition and a
  terminal manifest never transitions; `autopilot-build` check 2 requires
  `ready_for_implementation` on the next line). B4 pins that an in-flight manifest with a dead root
  still fails, naming `project_root`.
- **Silent, not a note** — the script's only channel is `fail()` and its main caller discards
  stderr. Opposite of ADR-0075's nightly check 6, which prints a note because a pre-flight is
  talking to an operator.
- **The five files stay byte-unchanged, and C2 enforces it from the other side:** it asserts at
  least one manifest still carries a dead root, so C1 cannot go green the day someone "fixes" the
  five and leaves the exemption untested while looking covered.
- **The premise is pinned, not the conclusion.** Section A derives the absorbing set from the
  transition script and the exempt list from the validator's own source, both at run time. A0
  count-guards the derivation, A3 runs it in reverse (a live state must not be exempt, or an empty
  exempt list would satisfy A2).

Known consequences: a terminal manifest with a genuinely wrong root — a typo, not a machine
difference — now passes, indistinguishable by inspection and worth close to nothing to catch on a
chain that will never run again. A0/A3/B5/B6/B7/C2 pass before and after.

**Harness lesson:** the fixtures are built by patching a REAL manifest. A hand-written minimal one
trips five unrelated invariants, and a first draft did exactly that — reporting "still invalid" with
an empty `project_root` reason, a failure about everything except the thing under test.

Detail: `docs/architecture/ADR-0078-197-project-root-terminal.md`.

## Decisions from the grant-coverage chain (ADR-0079)

Closes issue #196. The issue asked whether `agent-command-scope.sh`'s fixed interpreter enumeration
is the right instrument. Measuring it produced a different answer than expected, twice.

- **The enumeration is not the risk, because the permission layer bounds it.** An agent can only
  invoke what its frontmatter grants, and the two scoped agents grant exactly three executors:
  `bash` and `python3` (both), `awk` (reviewer). All three are covered — the first two by
  `INTERP_C` at a command position, `awk` through `system()` which `R2_EXEC` matches. **The
  intersection of "outside the enumeration" and "actually invocable" is empty today.** So inverting
  to a tool-exclusion list buys nothing and costs the failure direction.
- **What is unguarded is WIDENING A GRANT**, and nothing would have noticed. The hook now carries a
  `# grant-covered:` line plus a prose classification of every granted command word, and test
  section J derives the words FROM THE AGENT FILES at run time. Verified in the failing direction:
  adding `Bash(deno *)` to reviewer.md makes J3 fail naming `deno`. J4 makes the classification
  behavioural, not lexical — both granted interpreters must be caught in practice, not just listed.
- **The real defect: R2's trailing boundary, the sibling of the one #127 fixed.** #127 widened R1's
  trailing class to accept a closing quote. `R2_GIT` already accepted a quote and was left alone —
  but inside a shell double-quoted string the inner quotes are BACKSLASH-escaped, so a verb-last
  call ends `push\"` and `["')]` does not match:
  `python3 -c "import os; os.system(\"git push\")"` was **ALLOWED**, while the same line with
  `git commit -m x` was denied because a space follows the verb. Test A6 passed throughout for
  exactly the accidental reason section A did before #127.
  **Fixing a boundary in one rule and not its sibling** is the lesson, and it is the second time
  this shape has appeared in this file. Found by running the hook over the forms an interpreter
  actually produces — not by reading it, and not by the harness, which was green.
- **The compound guard had to survive the widening:** `print(\"git commit\")` now matches the verb
  half and must still be allowed (I4), and a read-only verb behind a real exec construct stays
  allowed (I5).
- **The residual limit is pinned as expected-ALLOW (J5):** an interpreter neither enumerated nor
  using an `R2_EXEC` construct escapes — `lua -e "os.execute('git push')"` is the shape. Closed
  today ONLY by the permission layer, a different mechanism in a different file. Threat model
  unchanged: a guardrail against a shortcut, not a sandbox.

Known consequences: the hook denies strictly more than it did, the second widening in one day on a
live guardrail. The grant check reads two specific agent files — a third scoped agent needs adding
by hand. Anyone reading the coverage table as "these are the only executors" is reading a snapshot.
J2/J4/I4/I5 and all of section E pass before and after; I1/I2/I3/J1/J3 were RED.

Detail: `docs/architecture/ADR-0079-196-grant-coverage-and-r2-boundary.md`.

## Decisions from the pattern-enforce fallback verdict (ADR-0080)

Closes issue #194, completing phase 4. Measured on **CC 2.1.220**; the verdict is build-stamped.

**VERDICT: the main-session fallback STAYS.**

- **The flush-race hypothesis is dead, and that is what one probe could settle.** A controlled coder
  dispatch made three Edit/Write calls and all three logged `src=subagent`, **including the first**.
  The transcript file was born at `19:15:58Z`; the first decision was logged at `19:16:02Z`. The
  refutation is a timestamp, not an outcome. Supporting evidence, 193 files: both layouts exist on
  disk (137 regular, 56 under `subagents/workflows/<wf_id>/`) and both match the hook's lookups.
- **n = 3, Agent-tool path only.** No Workflow dispatch was probed — the path v2.1.154 relocated.
  Anyone reading this as "the fallback does not fire" is over-reading it.
- **Why keep it anyway:** dropping converts a rare false ALLOW into a rare chain-breaking DENY, and
  fail-open on every internal error is that file's stated contract since before any of this. **The
  asymmetry with `write-scope-enforce.sh` is real and NOT an inconsistency** — that hook's fallback
  would be *actively wrong* (it would bind a write scope from the orchestrator's text), this one is
  merely *permissive*. Different failure, different correct answer, now stated at this hook's own
  site instead of in a neighbour's header.
- **The drop condition is PRE-REGISTERED**, written before more data arrives so the outcome cannot
  be rationalised later: `src=main-fallback` = 0 across ≥50 coder decisions spanning at least one
  Workflow dispatch → drop it. **Non-zero → do NOT drop it**, investigate why the lookup failed. A
  fallback that fires is evidence the lookup is broken, and removing it would hide that. The second
  branch is worth stating because the intuitive reading runs the other way.
- **A verdict on n=3 is protected by its reasoning being legible, not by its sample.** Test section
  D asserts the header states the sample size, carries the drop condition, states the do-not-drop
  branch, and explains the sibling asymmetry. All four fail against the phase-1 header. They check
  the reasoning is PRESENT, never that it is TRUE.

**Lesson, third of its family:** D2 first failed because the header wraps across comment lines AND
marks `src=main-fallback` as code, so a plain-prose needle missed it. ADR-0073 hit the line-wrap
form, ADR-0076 the comment-marker form, this the backtick form. **A prose assertion must not depend
on how the text is decorated any more than on where it breaks.**

Detail: `docs/architecture/ADR-0080-194-fallback-verdict.md`.

## Decisions from the false-green / zone-anomaly chain (ADR-0081)

Closes issues #213 and #212, phase 6.1. Two unrelated defects fixed together because both are a
correct-looking artifact that reports success without having checked anything.

**#213 — the RUNBOOK's agent validation could not fail.** The path was wrong
(`plugins/cache/…/unknown/…`; the validator is under `plugins/marketplaces/…/plugins/…`), and **the
path is the lesser half.** `bash` on a missing script exits **127** and writes to stderr; the loop's
only signal was `grep -q "Validation failed"`, which finds nothing there, so the `||` branch printed
`OK` for every file. Reproduced verbatim from git history before fixing: **eight `OK` lines and the
validator had never existed.**
- **Branch on the exit code, not on grepped output.** `validate-agent.sh` exits 1/0 (read, then
  confirmed live). 127 is not 0, so a missing script cannot fake a pass; a grep for output wording
  can be defeated by the script's absence.
- **`find` + hard-fail, and the guard is the part that generalises** — the block says to keep it even
  if the path is ever pinned again. The `cache`/`marketplaces` split is evidence layouts move.
- **The fixed block was executed**, not just written: it validates all eight agent files and reports
  clean. First time this step has validated anything. Rule 11 applied to the fix, not only to the
  finding.
- The dead path survives in three **historical plans** — not edited (ADR-0034 precedent).

**#212 — two zone anomalies in `PAIRS`, one undeclared.** `hook-verify-workflow.sh` is flat in
staging (ADR-0016/0024) and remapped into `skills/concept-to-code/scripts/` on deploy; the audit
reported it as a missing file and the reason had to be reconstructed from an ADR.
- **There are TWO, not one.** The first sweep compared src/dst tails and returned forty hits, because
  `plugin/scripts/X → hooks/X` is the *normal* mapping. The right question is which entry lands in a
  **different subtree from its peers**: `hook-verify-workflow.sh` (undeclared) and `usage-report.py`
  (already documented at `sync-to-claude.sh:19`). #212 warned against assuming one, and was right.
- **Declared in `sync-to-claude.sh` via `# pairs-zone-anomaly:`, derived and checked in the test.** A
  third anomaly fails at introduction. ZA4 runs it backwards (a stale waiver would keep ZA3 green),
  ZA2 count-guards the `PAIRS` parse, ZA5 pins the flat source — the half that breaks if someone
  "fixes" the reference. Both ZA3 and ZA4 seen failing on planted cases.

**Found on the way, and it is the same defect one level in:** `pairs-completeness.test.sh` has no
`ok()`/`bad()` helpers — its counters are touched only by its `check_*` functions. The first ZA draft
called them anyway: **six assertions printed "command not found" and the suite reported
`PASS=244 FAIL=0` and exited 0.** Nothing there runs under `set -e`, so a call to an undefined helper
is indistinguishable from a passing assertion. Both helpers are now defined with that history above
them.

Detail: `docs/architecture/ADR-0081-213-212-false-green-and-zone-anomalies.md`.

## Decisions from the cross-reference form chain (ADR-0082)

Closes issues #207 and #210, phase 6.2. Rule 3 — a cross-reference by line number rots — had been
enforced on **one file** since ADR-0018's addendum. Nothing checked the class.

**THE RULE — a cross-reference must name a DISTINCTIVE ANCHOR, never a line number. A
`<file>:<digits>` or `line <digits>` string that is genuinely not a reference is declared in the
file that carries it, on ONE line: `xref-exempt: <token>|<token>|… — <reason ≥ 40 chars>`.**

- **The derivation found three wrong references neither issue named, in a third surface neither
  issue named.** #207 filed an inventory of five sites; #210 verified two and added the
  hook-source → `SKILL.md` surface the inventory excluded by construction; deriving over all of
  `staging/` found defects in skill-private `scripts/` — the subtree ADR-0043 recorded
  `pairs-completeness.test.sh` as blind to. Six wrong, one drifted, eight accurate-but-numeric,
  all fifteen converted. Rule 5 demonstrated three times on one defect.
- **The one to remember: `hook-verify-workflow.sh`'s pointer rotted the day ADR-0080 grew
  `pre-flight-pattern-enforce.sh`'s header by ~50 lines** — the same commit that was fixing a
  neighbouring defect in the same file, the day before. The population needing checks is not "old
  files someone forgot"; it is every file, including the ones being actively corrected.
- **The extractor SKIPS `xref-exempt:` lines, and that is what makes the waiver honest.** A
  declaration names the tokens it exempts, so those tokens appear on the declaration line; without
  the skip, a waiver for a token present nowhere else would look live (rule 12). `U2` runs it
  backwards — a declared-but-absent token is a stale exemption covering nothing (ADR-0081 ZA4's
  direction). `S3` is the fixture that proves the skip.
- **The one-line marker requirement is not cosmetic.** A reason wrapped across lines is a prose
  assertion that depends on where the text breaks — ADR-0073's line wrap, ADR-0076's comment
  marker, ADR-0080's backticks, now a fourth. `U3` measures only the marker line, so a wrapped
  reason fails at the moment it is written. Found the honest way: the first three declarations
  were wrapped and `U3` caught all three.
- **Self-references assert a count of 2, not `>= 1`** — the anchor at the target plus the reference
  naming it — so either half disappearing is loud. `C1b`/`C2b` pin the marker form at exactly 1,
  or "2 occurrences" could be two references and no anchor.

Known consequences: three markdown prompts gain an HTML comment (real if small prompt cost,
accepted because the alternative is a waiver that does not travel with the file); the check
verifies an anchor EXISTS, never that it is the right place for the claim — all six wrong
references had **true claims and wrong pointers**, and a false claim with a valid anchor would
pass; the `§<digits>` form is deliberately outside the extractor (it is an ADR section reference
here, and the one line-range use is already pinned by `workflow-dispatch-pins.test.sh` B1);
`spec-coverage.sh`'s reference into `docs/specs/` is converted but unverifiable, since `docs/` is
out of the population by design (ADR-0034 precedent — a line number in a historical record is a
correct snapshot of its moment). `C10`/`C11`/`C14`/`C15` pass before and after — forward guards,
labelled in the harness, with `U1` as their red evidence.

Detail: `docs/architecture/ADR-0082-207-210-cross-reference-form.md`.

## Decisions from the fence-contract chain (ADR-0083)

Closes issue #206, phase 6.3, and #218 which it found. Rule 11 measured: 138 bash fences across
`staging/plugin/skills/*/SKILL.md`, **13** abort-capable, **4** executed by anything.

**THE RULE — a bash fence that can ABORT a run declares itself `<!-- fence-contract: <id> -->` and
must be executed by a test, or `<!-- fence-illustration: <reason ≥ 40 chars> -->` on one line. The
marker is ALSO the extraction anchor.**

- **#218, found by running a fence rather than reading it: `autopilot-build` check 2 has never been
  able to pass.** `step=$(grep '^current_step:' … | awk '{print $2}')` does not strip the quotes
  that `manifest-init.sh:73` and `manifest-transition.sh:133` both write, so the comparison was
  never true and the unattended pre-flight aborted on every manifest the system has ever produced —
  printing `current_step is "ready_for_implementation", not ready_for_implementation`. A singleton,
  and that is the interesting part: `manifest-validate.sh` uses the correct `sed` idiom at 17 sites
  and check 1 uses a correct 3-sed chain **twenty-five lines above**. Check 2 invented a third.
- **Recount before building on a count.** #206 said 15 abort-capable, ~6 covered. Truth: 13 and 4.
  The 15 came from matching `ABORT` as a **substring**, which hits "aborted"; the 6 counted a fence
  that is not abort-capable. Both off by two the same way, so `15-6` and `13-4` agree on 9. **Two
  wrong numbers subtracting to the right one is not a check.**
- **`bash -n` is the contract-versus-illustration classifier**, so the split the issue calls the
  deeper finding was measured rather than settled by taste: exactly one of the 13 fails to parse
  (`concept-to-code`'s merge-back block, carrying `<base-fork halt: …>` pseudo-code). `F7` keeps a
  declared contract parseable.
- **The received description of the heading-anchor hazard was wrong, in two different ways, both
  worse.** Measured by rewording the anchors: `plan-task-count` 43/0 → **35 passed/2 failed** and
  `scope-guards` 29/0 → **27/2**. (1) Six of `plan-task-count`'s assertions **vanished** — a suite
  reporting fewer assertions does not read as broken, and nobody watches the count. (2)
  `scope-guards` **misattributes**: an empty extraction is an empty script, an empty script exits 0,
  so every *positive* assertion goes green and only the abort ones fail, with messages that blame
  the guard. A reader hunts for a bug in check 1 that does not exist. Not "passes quietly" as this
  file and the roadmap both said.
- **Three fixes, all verified in the failing direction:** marker anchors on all five pre-existing
  extractors (rewording `**Check 1 —` now leaves scope-guards 30/30); empty extraction returns
  **97**, outside the fence's own `0|1` contract, so deleting a marker now fails all four
  A-assertions instead of two; and an **assertion-count floor** `Z1` in each of the three files — a
  floor, not an exact count, so it catches a vanished assertion without a bump on every addition.
- **F4 accepts two needles and both are executions** (`run_fence "<id>"`, or the literal
  `fence-contract: <id> -->` used by a re-anchored bespoke extractor). A `# covered elsewhere`
  comment would have been a claim; a test cannot extract a fence without naming its id.
- **Both directions per contract** (ADR-0039): good fixture and the bad input it exists to catch.
  That is how #218 surfaced. Fixtures patch a **real** manifest, with the base chosen by *running*
  `manifest-validate.sh` over the corpus — ADR-0078's dead `project_root` makes a valid manifest
  fail for an unrelated reason as soon as `current_step` becomes non-terminal.

Known consequences: the `commit` fence's abort path is **not** forced (E17–E19 cover branch
creation, the no-op half, and the slug guard that stops a subject of "main" producing `feat/main`);
`fence_is_abort_capable` is lexical, so a fence that aborts only via a called script's exit code is
outside the population — twelve contracts is a floor on that set, not a proof of its size; two
markers sit inside indented list items, so the parser must be indentation-tolerant (`S3`), which is
why the issue's own first count said 101 instead of 138. **No synthetic pseudo-code fixture exists,
deliberately:** two drafts were written and both **parsed as valid bash** — `… || <base-fork halt: …
stop>` followed by another line consumes that line's first token as the `>` target, so the
construct only fails when the pseudo-code closes the block. `S9` runs the classifier over the real
fence (rule 10). `F5`/`F6`/`F7` passed on the empty declaration set — forward guards, not fix
evidence; `F3` listing all 13 unmarked fences is the red evidence.

Detail: `docs/architecture/ADR-0083-206-fence-contract-coverage.md`.

## Decisions from the skill-coverage perimeter chain (ADR-0084)

Closes issue #211, first half of phase 6.4. Ten of 29 staged skills had no test naming them, and
nothing distinguished **audited and deliberately uncovered** from **never looked at**.

**THE RULE — every staged skill is either read by a test that NAMES it, or declares in its own
`SKILL.md` why not: `<!-- skill-coverage-exempt: <reason ≥ 40 chars> -->`, one line, within three
lines of the frontmatter close.**

- **The count was right and the premise was wrong, which is the more useful half.** #211 said the
  ten were "read by no test at all". Measured: **three** derived sweeps already read the whole
  corpus (`worktree-isolation-contract`, `agent-tool-parameter-names`, `skill-text-corrections` F6).
  Under the obvious predicate — "some test opens this file" — **all 29 would pass**, the count guard
  would stay green, and the perimeter would be as unmeasured as before. A right number can sit on a
  wrong premise, and only the premise decides the design.
- **The predicate is the literal string `<name>/SKILL.md`**, because a sweep reaches a file through
  a glob or a variable and cannot produce one. `S6` pins that in the failing direction against a
  glob-only fixture; weaken `covered_by()` and `S6` is what goes red.
- **It proved itself on its own author.** The first draft of the `goal-loop`/`research-prompt`
  assertions was a two-element `for` loop, and the perimeter check went on reporting both as
  uncovered — correctly, since a hardcoded two-name loop is indistinguishable from a sweep. Now two
  named assertions (`F7`/`F8`) with the reason written at that site.
- **`goal-loop` and `research-prompt` were pinned only by a sentence in the blueprint.** If either
  lost `disable-model-invocation`, F5 would still pass (the sentence still names it) and F6 would
  still pass (neither is chain-invokable, so neither is in its derivation).
- **`humanize-en` was ADR-0040's unverified half:** that ADR moved the perimeter *into* the
  `description` field on the argument that the field is what the model reads when deciding to
  invoke. Nothing asserted the field.
- **`design-brainstorm`/`macos-ux` get the cross-file contract, not a waiver:** c2c §25 restricts
  each to a gate (`1b`, `1c`) and nothing checked the skill's own text agrees — the ADR-0042 shape.
  Both sides asserted, so a failure names which one moved.
- **`S2` count-guards the waiver population** (zero declarations ⇒ `S3`/`S4`/`S5`/`S7` vacuous) and
  **`S7` runs backwards** — a waiver on a covered skill is stale, and stale reads as clean
  (ADR-0081 ZA4).

Known consequences: the check verifies a skill is *named*, never that the naming assertion is any
good — a mention in a comment satisfies it. Three `SKILL.md` files gain an HTML comment (prompt cost
accepted, ADR-0083 terms). **Six skills are deployed in `~/.claude/skills/` and absent from
`staging/`** — `agent-design`, `daily-close`, `daily-open`, `ui-layout-audit`, `vibiso-intake`,
`website-auditor` (last one excluded on purpose by ADR-0024). `ui-layout-audit` is chain-invokable
per c2c §25 at gate 5.05, and F6's `[ -f ] || continue` skips it in silence; no staging test can
reach it, by construction. Widening to `~/.claude` would make the harness depend on deploy state,
the opposite of ADR-0024 — filed separately. `S0`/`S6`/`Z1` pass before and after; all seventeen
assertions were seen RED on a planted defect.

Detail: `docs/architecture/ADR-0084-211-skill-coverage-perimeter.md`.

## Decisions from the derived-guard boundaries chain (ADR-0085)

Closes issue #208, second half of phase 6.4. Three run-time-derived guards each stopped at a
boundary nobody checked — one question asked three times: **what is outside this derivation, and
would we notice?**

- **The guard goes on the DENOMINATOR, not on the matches.** `transcript-scan-rule`'s premise still
  holds (0 of 38 skill scripts read a transcript), so widening the sweep catches nothing new — `T1`
  does catch a rogue reader planted under a skill, verified. The real risk is the **glob silently
  ceasing to resolve**: a single `N >= 8` is satisfied by the hooks alone, so a renamed subtree
  would leave the second root uncovered with the count green. `T0b` counts **candidates** (38), not
  matches (0). Zero matches is correct; zero candidates is a broken derivation, and from outside
  they look identical.
- **`population()` takes file paths now, not a directory** — the two roots sit at different depths
  and a second dir-shaped function would be two predicates that agree today, which is the failure
  the file exists to guard one level up.
- **`compliant()`'s false positive stays, and the decision is EXECUTABLE.** A non-jq reader returns
  non-compliant at the first step, indistinguishable from the verdict on a full-scan hook. `Z5`
  pins a rule-abiding python3 reader as reported-non-compliant, with the instruction that the fix is
  to **extend the predicate, never to exempt the hook** — an exemption there would be false, since
  the hook complies, and would record the opposite for every later reader. A comment would have been
  a claim.
- **The scoped-agent list is derived from `agent-command-scope.sh`'s own `case` arm** (`J0a`), and
  every derived name must resolve to a real agent file (`J0b`) — a typo yields an empty file list,
  which yields zero grant words, which `J3` reads as "nothing unclassified". Third time in one issue
  that a derivation needed its own guard.
- **Running the third-agent case found a FOURTH boundary nobody had named.** `coder.md` grants a
  bare, unrestricted `Bash`, which yields zero `Bash(<word> …)` entries — so ADR-0079 §D1's whole
  argument (an agent can only invoke what it is granted, and the granted executors are covered) does
  not hold for it, and its silence would look exactly like coverage. `J0c` asserts no scoped agent
  holds one. Not hypothetical: `coder` is one line of the hook away from being in scope. Found by
  running the derivation against a hypothetical, the same route that found ADR-0079's R2 boundary
  and ADR-0083's #218.

Known consequences: no executable file changes — the hook and both enforcing hooks are
byte-untouched. The `compliant()` false positive is still there, now with an assertion naming it as
expected, so whoever writes the third shape sees a failure naming their file. The transcript
population still stops at two roots; a reader in `staging/user/` or outside `plugin/scripts/` is
outside both globs *and* outside `T0b`'s denominator guard — the boundary moved, it did not
disappear. `J0c` matches an exact bare `Bash` token, so `Bash(*)` would pass it. `T0a`/`J0a`/`J0b`
pass before and after; the five red-verified cases are subtree renamed, rogue reader planted under a
skill, predicate widened, arm removed, arm typo.

Detail: `docs/architecture/ADR-0085-208-derived-guard-boundaries.md`.

## Decisions from the derived-guard extraction question (ADR-0086)

Roadmap item 6.5, first point — the question PROJECT.md deferred until the call sites existed. Six
test files derive a population at run time, let a file declare its own waiver, and count-guard the
derivation. **Answer: six deliberate copies, no shared helper.**

**THE CRITERION, which is the reusable part rather than the verdict — extract only when two copies
giving different answers would be a DEFECT.**

- **ADR-0069 is the precedent that appears to settle it, and does not.** It pulled
  `plan-task-predicate.awk` out of three consumers because they were asking **one** question and
  getting three answers — drift, and it had already cost issue #172. The six guards ask **six**
  questions about six populations, so there is no shared answer that could diverge. `>= 8`, `>= 25`,
  `>= 100` and `>= 2` are legitimately different numbers, and the 40-character reason floor is a
  convention rather than a fact.
- **Two differences a single helper cannot reconcile, both measured.** `fence-contract`'s marker
  **is** the extraction anchor and must be found (ADR-0083 §D3); `cross-reference-form`'s must be
  **excluded** from extraction or a declaration satisfies itself, since the line naming the exempt
  tokens contains them. Contradictory requirements on the same field. And the marker's syntax
  follows the **file's language** — shell comment in the hook-facing guards, HTML comment in the
  markdown-facing ones — with three different payloads (reason, reason+id, reason+token-list) and
  one position constraint the others do not have.
- **Correlated failure is worse than duplication, for guards specifically.** Each file is hermetic
  and independently runnable by design (`Run: bash <file>`, and `docs-ci.yml` invokes them one by
  one). Six independent checks are worth having *because they fail independently*; a defect in a
  shared source disables all six at once, in the stay-green way this repository has already watched
  three times.
- **The rule is recorded in each of the six headers**, one line naming the instance, because the
  seventh will be written by **copying one of the six**. No test asserts those lines exist: an
  assertion that a comment is present cannot be seen meaningfully RED, prevents no defect beyond a
  missing comment, and would literally be the seventh instance of the pattern under review.

Known consequences: the count-guard idiom and the 40-char floor stay duplicated six times — the
claim is that a drift there is not a defect, not that it cannot happen. The decision has **no
enforcement** by choice, so a seventh copy skipping the header note is invisible. The instance count
is a snapshot: six on 2026-07-30, re-derived from the files because PROJECT.md said four and named
the wrong four.

Detail: `docs/architecture/ADR-0086-derived-guard-pattern-not-extracted.md`.

## Decisions from the test-authoring granularity chain (ADR-0088)

Closes issue #241, found by the Phase 7.1 shakedown at Step 5 — the first time any chain run reached
it (#239 records why it never had). ADR-0049 split test authoring from implementation and dispatched
the split at **task** granularity. A plan task is a **mixed** unit.

- **The issue's framing was too narrow, and the measurement is what shows it.** #241 was filed as "a
  feature whose deliverable is test code". Measured: **56 of 57 plans** in `docs/superpowers/plans/`
  name both test-shaped and implementation paths (57 of 58 with #222's own). Not a category of
  feature — the shape of essentially every plan this repository has produced.
- **The cause is granularity, not perimeter.** The tester's brief is a strict fallback chain —
  `R-NN` ids, then Success Criteria, then plan text — so on a SPEC that declares ids (the ADR-0048
  case, i.e. the normal one) the plan is never read for scope. The coder's brief says the red tests
  "already exist", presuming they were separate deliverables rather than sub-steps of its own tasks.
  So a task with a test-shaped sub-step either got written by luck or could not close.
- **Generator/verifier separation was already preserved, and saying so IS the decision.** #222's
  plan encodes it by task ordering without anyone designing it that way: Task 1 writes `F10` and
  confirms it RED, Task 2 vendors and turns it GREEN. Mapped onto the roles — the tester writes the
  assertion and confirms its RED, the coder makes the change that greens it. That answers *who
  verifies an assertion*, and no part of the perimeter has to move.
- **ADR-0049 A5 stands and the marker is untouched.** `test-write-scope.sh` is byte-unchanged.
  `TM5` pins the marker byte-identical at 1 hook site and 3 c2c sites: **a "fix" for #241 that
  changes the marker is the failure mode, not the remedy.**
- **No new script, and the reason is measured.** A mechanical per-task split needs a plan-side file
  declaration; `**File(s):**` appears in **18 of 58** plans, a parseable `Budget:` in **2 of 58**.
  Either would be inert on the majority and inert *silently*. The agent splits from the plan text
  and **the hook is the backstop** — a misclassification is a loud deny plus a report, never a
  silent wrong result. A second copy of the path predicate is refused: ADR-0086 would call it
  extractable, but extracting it *into* the hook turns a missing file into an allow, weakening a
  guardrail whose contract is allow-on-every-failure.
- **Batch boundaries are a design choice**, stated where batches are chosen: the tester runs once
  per batch before the coder, so an assertion cannot share a batch with the task it depends on, and
  a red assertion must not be split from the task that greens it.

Known consequences: this ships an **instruction, not an enforcement** — what changes is the failure
shape, from a task nobody can close to a loud deny with a report. The batch-boundary rule has no
mechanism (#242 is where one would belong). The Workflow path's prompt is model-generated, so the
new clauses inherit the marker's own limit there. Inert until sync; the paused #222 run executes the
deployed copy.

**Harness lesson, fourth of its family.** `TM2`/`TM3` reported 0 on their first run against clauses
that were present and correct, because the clauses **wrap across two lines** — ADR-0073's line wrap,
ADR-0076's comment marker, ADR-0080's backticks, now met while writing an ADR that cites all three.
Prose clauses match a whitespace-flattened copy via `count_flat`; `TM5` deliberately stays
line-based via `count_lit`, because a marker split across two lines is a marker the hook cannot see
and flattening would hide the very defect it guards.

Detail: `docs/architecture/ADR-0088-241-test-authoring-split-granularity.md`.

## Decisions from the deployed-only skills chain (ADR-0087)

Closes issue #222, Phase 7.2, and the feature the Phase 7.1 shakedown run was executed on. Six
skills exist in `~/.claude/skills/` and not in `staging/`.

**The issue's framing was one question; measuring the six showed it is two.** *Deployment* — must a
fresh machine restoring from this repository receive this file? — and *verification* — must the
harness be able to read it? ADR-0024 could answer them together for its sixteen skills. Here they
diverge: yes/yes for `ui-layout-audit` (c2c §25 declares it chain-invokable at gate 5.05 and Gate
5.05 invokes it by name), no/no for the other four. `daily-open`/`daily-close` are a personal
routine bound to local connectors; `vibiso-intake` is another project's intake contract;
`agent-design` carries `license: Proprietary internal knowledge base` over a `reference/` tree
distilled from a published book.

**So the defect is not "four skills are unvendored" — it is that nothing distinguishes "not part of
the blueprint" from "forgotten"**, the same gap that left `website-auditor`'s exclusion in prose
since ADR-0024.

- **The registry lives in `sync-to-claude.sh`**, beside the `# pairs-zone-anomaly:` declarations,
  because that file is what decides which files reach `~/.claude`. **ADR-0077's rule — a waiver
  travels with the file it excuses — cannot apply here**: the excused file is absent from
  `staging/` by construction, so there is nothing for the waiver to travel with. This is the one
  shape that rule does not cover.
- **Two verification directions, two homes, and the split is the point.** *Every entry names a
  skill absent from staging* (a stale waiver) is CI-runnable — it reads only `staging/`. *Every
  deployed skill is vendored or declared* needs `$HOME/.claude`, which ADR-0084 refused to make CI
  depend on, so it is a report in `sync-to-claude.sh` at deploy time, read by the one person who
  can answer "what is this skill".
- **F6's `continue` was doing two jobs.** Measured, c2c §25 yields nine backticked tokens: seven
  staged skills, `reviewer` (an **agent**), and `ui-layout-audit` (the gap). One skip could not tell
  "legitimately not a skill" from "missing from staging". A token resolving as neither a staged
  skill nor a staged agent is now a failure — derivation stays inside `staging/`, so no name list
  enters the test (the identity waiver ADR-0069 §PTD refused).
- **Task order is inverted on purpose, and reordering destroys the evidence.** F6 is fixed
  **before** `ui-layout-audit` is vendored, so the corrected check's first run fails citing the
  real gap rather than a planted fixture. Vendoring is what turns it green.
- **`ui-layout-audit` gets the gate contract, not a coverage waiver** — a `C7` of the same shape as
  `C5`/`C6`, so the third chain-invokable skill is asserted exactly as the first two.
- **Instance 7 of the derived-guard family, and it stays a copy** (ADR-0086's criterion: would two
  copies giving different answers be a defect? No — it is its own population asking its own
  question).

Known consequences: **no licence or provenance enforcement anywhere** — ADR-0065 (#119) deliberately
shipped no detector, so `agent-design`'s licence is recorded as a reason and checked by nothing. A
skill deployed tomorrow and never declared is invisible to CI by design; reading a green run as "the
deployed set is fully accounted for" reads something this feature does not claim. R-06 has no CI
coverage beyond `HOME`-override fixtures, the same asymmetry ADR-0084 already accepted.

Detail: `docs/architecture/ADR-0087-222-deployed-only-skills.md`.

## Decisions from the Step 5.0.1 manifest exemption (ADR-0089)

Closes issue #239, Wave A1 of Phase 8. ADR-0050's pre-flight asserts a clean tree at Step 5 entry.
The chain writes the manifest at every state change, and two of those writes land **between**
Gate 4.0's commit and that assertion — so the assertion had never been satisfied by a real run.
The Phase 7.1 shakedown reached it with a clean tree and a successful Gate 4.0 behind it and was
refused, with a message saying the planning artifacts were uncommitted. They were not.

- **No ordering fixes it, and that is what decides the design.** "Implement now" could be repaired
  by moving Gate 4.0 after the flag and the transition. The fresh-session branch cannot: Form B
  resume step 3 writes `session_boundary.resumed_at` unconditionally, after any commit the old
  session could have made. And 5.0.3 writes `recovery_baseline_sha` into the same file **on
  purpose**, three assertions later. *"The working tree is clean"* and *"the manifest is written at
  every state change"* are flatly incompatible requirements on one file; neither side is wrong,
  which is why it survived review on both.
- **The manifest leaves the dirty set, and only the manifest.** ADR-0050 §D2's purpose is work of
  **unknown provenance**; the chain is the manifest's only writer. `SPEC.md`, the ADR, the plan and
  `CLAUDE.md` stay in, each still refusing individually (`RJ3`).
- **The exemption is bounded by `manifest-validate.sh`, not by trust** — ADR-0075 measured
  hand-edited manifests as real. What is exempt is the file's **dirtiness**, never its **content**,
  and the skill says so, because the exemption reads at a glance exactly like a weakened check.
- **The block was not merely unexecuted, it was UNEXECUTABLE**, and that is the sharper form of
  rule 11. 5.0.1's classification was prose ("decide by intersecting…"), so it could not be an
  ADR-0083 contract and nothing guarded it. It is now `fence-contract:
  c2c-step5-preflight-dirty-classify`, with a token per branch and **exit 3 for "did not run"** —
  without which an unrunnable classifier is indistinguishable from a clean tree, which is #239 one
  level down.
- **The first draft was broken in the direction that looks like success.** `git rev-parse
  --show-toplevel` returns a *physical* path while the chain's manifest path is whatever `$PWD` was
  at Gate 0, so a raw prefix match shortened nothing, every artifact classified as `OTHER` —
  **including the manifest**, making the exemption silently inert while the fence still exited
  non-zero and still looked right. Eleven fixtures caught it on the first execution. Live on macOS:
  `/tmp` is a symlink to `/private/tmp` and this checkout is reachable through two differently-cased
  paths.
- **Only half the normalisation is evidenced, and the fence says which half.** Reverting `ROOT` to
  the unresolved value fires **no assertion** (git already returns a physical path); reverting the
  argument side fires five. Both are in the code, one is defence. Conflating them would be the
  claim this repository keeps catching.
- **`*.bak` is gitignored, and that is load-bearing for TWO checks.** 5.0.3 uses `sed -i.bak`; were
  it not ignored, the debris would dirty the tree at this assertion **and** trip ADR-0068 §D11's
  merge-back escape check on every stage. Verified, not assumed, and recorded so a `.gitignore` edit
  cannot break two unrelated checks in silence.

Known consequences: a pre-flight guard now passes on strictly more inputs (bounded to one file);
`manifest-validate.sh` becomes a hard dependency of the in-session Gate 4 branch, failing closed on
an un-synced machine (ADR-0076's rule); porcelain v1 means a **renamed** artifact classifies as
`OTHER` and a quoted path will not match; **#248 is not fixed by this** — entering Step 5 and
leaving it for Step 6 are two missing producers in the same stretch of chain.

**Plant lesson worth keeping:** two of nine plants did not fire, and both were informative rather
than formalities. One targeted dead code (the exclusion is upstream of the `case`); the other
targeted the untested half of the normalisation, which is what produced the honesty note above. A
plant that does not fire is evidence about the assertion, not a step to get past.

Detail: `docs/architecture/ADR-0089-239-step5-preflight-manifest-exemption.md`.

## Decisions from the check-6 fail-open fix (ADR-0090)

Closes issue #258, first of Wave E. `autopilot-build`'s pre-flight runs with no human present.
Check 6 read `test_cmd_placeholder` with a bare `m.get()` behind `2>/dev/null`, so an unparseable
manifest or a missing PyYAML produced an empty string that is not `"True"` — and the check
**passed**. Reproduced both ways before writing anything.

- **It is verbatim the pattern ADR-0076 §THE RULE forbids**, four lines above check 7 which
  ADR-0075 fixed for the same reason. Now read through `manifest-field-state.sh`, asserting the
  **valid** values rather than enumerating invalid ones (ADR-0075 §D4).
- **A singleton, and that is why it is worth recording.** All eight checks were classified, not just
  the reported one: five read state, four fail closed by four different correct idioms, one invented
  a fifth with the direction reversed. **Same shape as #218 in the same file** — check 2 invented
  its own quote handling while seventeen sites elsewhere used the correct `sed` idiom.
- **`ABSENT` PROCEEDS here, the opposite of check 7, and that asymmetry is the decision.** This flag
  is corroborating, not primary: the authoritative signal is the file itself (`content = NONE`,
  tested two lines above) and an unapproved command is caught by the TOFU check below.
  `hook_verified` has no fallback, which is why its absence aborts. Measured: 40 of 41 corpus
  manifests carry the field, the one `ABSENT` is `completed` and predates it. Both sites say **"Do
  not reconcile the two"**.
- **The two-tier helper resolution is a deliberate second copy.** ADR-0086's criterion calls it
  extractable, and it stays duplicated because a fence borrowing a variable bound in an **earlier
  fence** stops being independently executable — the property ADR-0083 F4/F7 rest on. `E7f` pins the
  two paths to agree instead.
- **Redirecting `HOME` in a test hides PyYAML.** Python derives per-user site-packages from `$HOME`,
  so the fixture HOME that fakes the TOFU trust registry makes `import yaml` fail wherever PyYAML
  came from `pip --user`. The fence then correctly reported "did not run" and correctly aborted —
  **the fixture was wrong, not the fence.** `PYTHONPATH` is now resolved from the module itself, so
  a system-installed PyYAML on CI is covered by the same line.
- **A correction to the sweep that found this:** it first reported "11 of 12 declared fence contracts
  have no `exit 3`". Right number, wrong premise (ADR-0084's lesson on my own measurement) — an
  `exit 3` **code** is only needed where a caller branches on it, and eleven of twelve already fail
  closed by whichever idiom suits them. One wrong check, not a class conversion.

**Plant lessons, both worth keeping.** The first plant bounded the replaced block on ``esac\n``` ``,
which matched a `esac` in a **different fence far later in the file** and silently deleted check 6's
TOFU section — the suite then reported nonsense that would have read as "the assertion does not pin
the bug" had the planted text not been inspected. **Inspect what a plant actually produced before
believing what it reports.** And E9 was green for the wrong reason for one run: the new dependency
made the fence abort on an unresolvable helper, also `rc=1`, and E9 asserted only the exit code. It
now asserts the message names TOFU — rule 8's family, a negative assertion pins nothing when every
failure looks alike.

Detail: `docs/architecture/ADR-0090-258-check6-placeholder-fail-open.md`.

## Decisions from the per-file budget half-parse (ADR-0091)

Closes issue #246, second of Wave E. ADR-0070 woke `diff-budget-check.sh` up after months of
inertness; **the first real plan it ran on produced two findings and both were false.** The parser
matched one paren group anchored at end of line, so a per-file declaration —
`Budget: a/SKILL.md (~165 lines, new), b/sync.sh (~1 line)` — kept only the LAST ceiling and left
everything before it in the file list. Three corruptions at once: a false `SCOPE` on a file the plan
declares explicitly, a ceiling of 1 instead of 166, and an inflated file count from the fragments
`(~165 lines` and `new)`.

- **One grammar, not two.** A left-to-right walk over paren groups SUBSUMES the documented
  single-ceiling form rather than branching on it, so there is no second code path to keep in
  agreement — the failure ADR-0069 removed from the plan-task predicate, not reintroduced. Mixed
  forms work as a consequence, not as a special case.
- **`MALFORMED` fires only on a recognisable ATTEMPT, and the discriminator is MEASURED.** At least
  one paren group carrying both a digit and the word "line". `Budget:` is matched as a
  case-insensitive **substring**, so the corpus holds `# Performance budget: <10s typical…` (a
  comment in a fenced code block) and `Budget: none (verification only, … Tasks 1-6 …)` (a prose
  escape). **A token firing on either would be this issue's own defect one level up.** Both pinned.
- **It is emitted BEFORE the whole-plan inert check**, because a plan whose only declarations are
  malformed has an empty budget set and would otherwise return `CLEAN` — the common, documented,
  legitimate case, indistinguishable from it. Exactly the invisibility ADR-0070 sat inside.
- **The token has a CONSUMER.** The Step 5 call site reads it, says the task's budget was **not
  measured**, and records `{task, malformed}` with no `files_*`/`lines_*` keys, since zeros there
  would read as a task that spent nothing (ADR-0064 §D3). A reporter line nobody reads is #238's
  shape, and creating a new instance while the roadmap closes that class would be a poor trade.
- **`BK9` embeds the pre-#246 parser as the specification of what must not change:** 16 declarations
  compared under both, **exactly 3 differ** (the per-file ones) and **none that the old parser could
  read has become unreadable.** Its boundary is stated — it compares the FUNCTION, so it is blind to
  a script that defines it and never calls it; `BK1`/`BK2`/`BK3` are what fail there, and the two
  must be read as a pair.

**Assertion lesson, three wrong drafts of one check, all planted rather than reasoned.** `BK10`
asserts the `MALFORMED` consumer exists. Draft 1 was a bare `grep -qF 'MALFORMED'` — the token is
named twice, so deleting one site left the other satisfying it (`recovery-preflight.test.sh` RI1's
defect, by the same hand, three days later). Draft 2 was an exact count of 2, which **failed on the
correct file** because `spec-coverage.sh` — a different checker twenty lines up in the same step —
emits a `MALFORMED` token of its own. Draft 3 used four needles, of which `not measured` still did
not fire: it appears twice more in Step 5 for the absent-field rule. **The general form: a needle
must belong to the block it asserts about and to nothing else, and the only way to know it does is
to plant it.**

Detail: `docs/architecture/ADR-0091-246-per-file-budget-half-parse.md`.
