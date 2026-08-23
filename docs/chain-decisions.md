# Chain decision records — narrative archive

One narrative block per `concept-to-code` chain that reached Step 7, in the order they were
written. These are the blocks that lived in `CLAUDE.md` until issue #380 (ADR-0136) moved them
here: `CLAUDE.md` is loaded in full into every orchestrator turn, and at 95 blocks it had grown to
~75,000 tokens per turn.

**This is not a summary of the ADRs.** Measured before the move: whole-line overlap with the ADR
each block points at is 6 lines of 3,132, and distinctive-phrase overlap is 5%. Four of six
distinctive claims spot-checked were absent from their ADR entirely, and eleven blocks carry an
explicit cross-ADR synthesis (*"third of its family"*) which by construction cannot live in any
single ADR. This file is the only home of that material.

**It is a historical record and is not corrected in place** (ADR-0034 precedent). A count written
inside a block is a correct snapshot of the day it was written; several are stale today and that is
what a record is. Re-derive any number from the files before citing it — never from this file.

The live, always-loaded material is the recurring rules, in `CLAUDE.md` under `## Rules`. The
one-line index of what each ADR decided is in `docs/chain-decision-index.md`, which is looked up
rather than loaded (ADR-0163).

---

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
  (`workflow|agent_batch|null`) added to `manifest-init.sh` as additive fields.
  No schema version bump required.

**Addendum 2026-07-25 (orchestrator effort).** The session `effortLevel` moves to `high`. Since
the Workflow tool inherits the session effort whenever `opts.effort` is omitted, exactly as it
inherits the session model when `model` is omitted, Step 5 now pins `effort` explicitly on every
`agent()` call from each agent's frontmatter (architect/coder/tester `xhigh`; reviewer/debugger `high`;
refactorer `medium`; doc-writer/researcher `low`). Without that pin, raising the
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
  The value domain is the caller's and has to be: `hook_verified` is `true|false`, `step5_mode` is
  `workflow|agent_batch|null`, `step5_review_mode` is `none|checkpoint`. There is no general
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

## Decisions from the step5_mode value domain (ADR-0092)

Closes issue #240, third of Wave E. ADR-0076 §D2 makes the value domain the **caller's** and offers
`step5_mode` as its worked example: `workflow|agent_fallback|null`. **Nothing has ever written
`agent_fallback`** — measured over 41 manifests: 18 `agent_batch`, 2 `workflow`, 19 `null`, 2 absent,
**0**. Both producers write `agent_batch`.

- **Latent, and that is what makes it a trap.** `manifest-validate.sh` has no invariant for the
  field, so nothing catches it. But the wrong string sits in `manifest-field-state.sh`'s header, the
  live worked example ADR-0076 tells the next author to follow: a checker built on it passes on a
  fresh manifest (`null`) and rejects all 18 historical ones the first time it meets one. ADR-0075 /
  #123 replayed exactly.
- **The issue was wrong about the origin, and that is the useful part. ADR-0016 is CORRECT** and
  always was (`"workflow" | "agent_batch"`). The error entered in a **summary** of that ADR in
  `CLAUDE.md` and spread from the summary into ADR-0076 and thence into the helper header. Four
  wrong sites, not three, and the source was not among them.
- **The fix is not four corrected strings.** Section `V` of `manifest-field-state.test.sh` derives
  the WRITTEN set from the producers and the DOCUMENTED set from the helper header and compares them
  **in both directions**. The reverse direction is what catches this — a documented value nothing
  writes — the ADR-0043 direction lesson applied to a value domain. `V4` pins ADR-0016 as the
  correct source, because the drift ran source → summary and a later "correction" would otherwise
  fix the wrong file. Instance 8 of the derived-guard pattern, **with no waiver mechanism: a value
  domain with an exemption is not a domain.**
- **ADR-0076's body is not edited** (ADR-0034 precedent); it gains a dated `## Correction`. The 18
  historical manifests are untouched — they are accurate.

**Lesson, fourth of its family, met while deriving the guard itself:** the helper's sentence wraps
across two comment lines, so the first line-based derivation of the documented set returned
**nothing** — which would have made `V2` vacuously true, the exact shape it exists to catch. Both
derivations are count-guarded now. ADR-0073 line wrap, ADR-0076 comment marker, ADR-0080 backticks,
ADR-0082 one-line marker, and now a derivation reading its own source.

Known consequence: the guard covers `step5_mode` only — `hook_verified` and `step5_review_mode` are
named in the same sentence and are not derived, since their producers are shaped differently.

Detail: `docs/architecture/ADR-0092-240-step5-mode-value-domain.md`.

## Decisions from the macOS-detection false positives (ADR-0093)

Closes issue #232, fourth of Wave E. `detect-macos.sh` gates Gate 1c, which offers a HIG design step
for windows, navigation, Settings and menu bar. Measured over all 36 SPECs here: **it fired on six,
and not one was a macOS UI target.**

- **Two classes, and the issue named one.** (1) The keyword inside a longer **identifier**:
  `macos-ux` is a skill name every meta-SPEC about this chain mentions. **Measuring found a second,
  `swiftui-pro`, which SURVIVES the narrowing #232 itself proposed** — dropping bare `macos` keeps
  `swiftui`, so the second collision would have remained. (2) The keyword naming the **host**:
  `Bash 3.2 (macOS-portable, …)` says which shell, not which UI.
- **Two boundary sets, deliberately different.** Keyword boundaries treat `-` as part of a word, so
  `macos-ux` and `swiftui-pro` are single tokens. Noun boundaries treat `-` as a separator, because
  `window-based` is ordinary English. Using the keyword set for both lost `A window-based macOS
  tool` — **the two halves of the fix interfering**, caught by the fixtures, invisible in the regex.
- **Bare `macos` must keep company; `swiftui`/`appkit`/`menu bar` need none.** The platform name
  counts only within 60 characters, either side of a UI noun. Corpus false positives **6 → 0**, with
  every genuine macOS-UI fixture still detected.
- **The cost is an assertion, not a discovery.** A headless `macOS daemon` is deliberately NOT
  detected — Gate 1c offers window and menu design a daemon cannot use. Pinned as `M7`.
- **`mac app` never matched `macOS app`**, only the literal "Mac app". The keyword was nearly dead
  before this change; kept, and neither it nor the proximity rule is load-bearing alone.
- **A new CI-runnable harness, because the existing one is CI-dark.** Four `detect-macos` assertions
  lived in `concept-to-code/tests/run-tests.sh`, which resolves `SKILL_DIR="$HOME/.claude/skills/…"`
  — **fourth instance of the class ADR-0032 named.** All four still hold and are re-homed into
  section `P`, running in CI for the first time; the original file is byte-untouched.

**Two lessons from running it.** An empty ERE alternative `(…|)` is rejected by BSD grep, and the
failure is silent in the worst direction: every SPEC then reads `NOT_MACOS`, so **the corpus sweep
reported zero false positives while the rule was not running at all** — a check that did not run
reading as a check that found nothing, inside the measurement built to verify the fix. `bash -n`
cannot see it; the pattern is a string until grep reads it. `M20b` now counts errors as a **third**
sweep outcome and `M21` pins the construct out of the source. And **`M21`'s own first draft failed
on a correct file**, because its needle `|)` matched the header comment explaining why not to use
the construct — rule 12, in a test written the same hour as an ADR citing rule 12.

Detail: `docs/architecture/ADR-0093-232-macos-detection-false-positives.md`.

## Decisions from the RTF gitignore glob (ADR-0094)

Closes issue #250, last of Wave E. `review-triage-fix`'s state file is per-branch by design, and
`triage-state.sh commit` gitignored it by appending its **resolved** name. The branch is deleted at
merge; the line is not. One dead entry per branch, forever — and on a public repo, a list of every
feature branch ever reviewed.

- **It defeated its own purpose too.** A per-branch line protects exactly one branch; the next
  branch is unprotected until its own cycle appends its own line. Now one glob, permanent, covering
  the first cycle on a new branch as well.
- **`git check-ignore`, not a literal grep for the script's own line.** A human may have written a
  broader rule by hand, and **this repository's `.gitignore` is the proof** — it carried
  `.claude/.triage-fix-last*.json` before the glob existed. Exit-code contract as `commit/SKILL.md`
  already documents it: **1 means "not ignored", a clean result, not a failure**; non-zero takes the
  append branch, the safe direction, and the append is idempotent.
- **A basename is passed, because `git -C` moves the cwd.** A relative `$SF` would be resolved
  against the file's own directory a second time, yielding `.claude/.claude/…` and a "not ignored"
  answer for a file that is ignored. RTF passes an absolute path, so this is defensive — pinned
  anyway, because *defensive* and *untested* together make a later simplification look free.

**The lesson is the assertion, not the fix.** `T10b` exists to pin the basename, and its first two
drafts **passed and caught nothing**: seeded with the script's own glob, the literal-grep fallback
suppressed the append so the `check-ignore` branch never ran; seeded with `.claude/`, that rule
covers the *doubled* path the bug produces, so `check-ignore` said "ignored" for the wrong reason.
The seed had to differ from the script's own glob **and** not cover the doubled path — verified by
running `check-ignore` against both paths before writing the assertion. Neither draft was detectably
wrong by reading. **An assertion that cannot be made to fail is pinning nothing, and a fixture must
be chosen against the failure mode rather than merely be plausible.**

Detail: `docs/architecture/ADR-0094-250-triage-state-gitignore-glob.md`.

## Decisions from the transition-producer chain (ADR-0095)

Closes issue #248, Wave A2. At the end of Step 5 the chain transitioned to `step_6_review` and was
refused, correctly: the graph is `ready_for_implementation → step_5_implementation → step_6_review`
and **nothing on the default path performed the first hop.** Every producer of
`step_5_implementation` sits inside the Step 4.5 tracer-bullet block, which runs only when
`tracer_bullet_mode = probe`; `manifest-init.sh` writes `skip`. Step 5 could be entered and never
left. Third instance of the class after #173 and #238.

- **ADR-0057's own wording is the giveaway** — *"exactly as before this feature existed"*. The pair
  sat in the legal-pairs table with **no caller at all**, and the tracer-bullet feature became its
  only caller, behind a flag that defaults off. The feature that reads as if it inherited the
  transition is the only thing that ever performed it.
- **Step 5.0.5 produces the state, and its placement is load-bearing in both directions.** Later
  leaves the gap open; earlier strands a *refused* pre-flight in `step_5_implementation`, when every
  refusal above says "do not proceed" precisely so the manifest stays at `ready_for_implementation`
  — the state a Form B resume is defined for. Step 4.5's producer stays and needs no guard: a
  same-to-same call returns 0, and `TP9` pins that idempotence because it is what lets two producers
  coexist and nothing in either block says so.
- **The fix breaks Form B resume, so Form B is fixed in the same edit.** Its branch list accepted
  `ready_for_implementation` and nothing else in that stretch, which worked only because the chain
  never left it. ADR-0050's own 5.0.3 (*"already non-null … a resumed Step 5 run"*) anticipates a
  resumed Step 5 explicitly: the recovery path was specified and the state that reaches it was not.
  **Closing a transition hole by opening a recovery one is not a fix.**
- **The class guard does NOT catch #248, and that boundary is the design.** It catches the #238
  shape (a target with no producer anywhere); it cannot catch a target whose only producers are
  behind a default-off flag, because conditionality is not mechanical from prose. #248 is pinned
  **instance-level** (`TP6`/`TP7`); the guard is justified by what it found instead.
- **It found a real one on its first run, before any of this was written: `gate_5_review_decision`
  is entered by nothing** (issue #265). Step 5 transitions to `step_6_review` and presents Gate 5
  from there, while Gate 5 asserts `Trigger: … current_step = gate_5_review_decision`, the roll-up
  speaks of "the transition to" it, and Step 7 lists it as a valid source. Four unreachable pairs,
  no symptom — Step 7's `step_6_review → step_7_commit` is legal — which is why it survived.
  ADR-0027's Gates-0c/0d lesson, fourth instance. **Declared, not fixed:** the state sits *after*
  `step_6_review` while Gate 5 decides *whether* to review, so resolving it is a design question.
- **§3's exclusion fails CLOSED, and the safe direction is not the obvious one.** §3 names every
  pair and performs none, so including it makes every target trivially covered. If the heading range
  does not resolve, concept-to-code contributes nothing and 26 targets report producerless — loud,
  with `TP0c` naming the cause. Dropping the guard and including the file whole fails *open*; the
  test says so at that line.
- **The predicate needed the arrow form, and only running it showed why.** Gate 0d's routing block
  puts the verb on the **preceding** line (`Transition: … then immediately transition based on
  chain_path:` followed by a bullet list), so a same-line "transition" keyword reported `step_e1_plan`
  as producerless. A false positive of the guard, corrected before shipping.

Known consequences: a chain interrupted in `step_6_review` still matches no Form B branch
(pre-existing, named rather than half-fixed); the population stops at staged `SKILL.md`, so a
producer in a skill `scripts/` helper is invisible; a "producer" is a line that *mentions* the target
in a transition context, so a target only ever talked about looks produced. Instance 9 of the
derived-guard pattern, not extracted (ADR-0086). Third waiver syntax, deliberately.

Detail: `docs/architecture/ADR-0095-248-transition-producer.md`.

## Decisions from the spec-archive chain (ADR-0096)

Closes issue #228, Wave B. `concept-to-code` Step 1's greenfield branch writes to
`<project-root>/SPEC.md`, and **two states reach that branch** — only one of them is "no SPEC.md on
disk". The other is a root SPEC belonging to a different topic: `gate0-detect.sh` reads the
`**Topic slug:**` marker, reports `spec_topic_match=false`, and flips to greenfield, which
"disowns" the SPEC **for routing** and leaves the file exactly where the dispatch is about to write.
Gate 4.0 would then commit the overwrite. **The detection existed, was correct, fired, and protected
nothing** — not a missing check, a check wired to a decision that does not include the file.

- **Both of the issue's premises were wrong, and the second changed the design.** (1) #176's SPEC
  was already archived by #229 (`162b019`); the live subject is whatever the slot holds. (2) The
  archive is NOT named `docs/specs/<slug>.spec.md` — measured, **3 of 41** manifest topic slugs name
  an existing archive. Archive names come from the SPEC's title; a topic slug is truncated to 40
  chars (`100-secrets-and-dependency-gate-content` against
  `100-secrets-and-dependency-gate-content-scan.spec.md`). **A by-name "already archived?" check
  would have missed 38 archives and written a duplicate beside each, while looking correct and
  reporting nothing** — ADR-0091's shape in a new place.
- **Detect by CONTENT, write by NAME.** Content comparison is what makes it idempotent against a
  corpus named by a convention it does not follow; the slug destination is what makes it
  deterministic going forward. Nothing else combines both.
- **It copies, never moves.** Nothing is deleted without a human, and the incoming interview
  overwrites the slot anyway — a move buys nothing and loses the file if the interview fails.
- **The slug is an ARGUMENT.** `gate0-detect.sh` gains an additive `spec_topic_slug=` line and
  `spec-archive.sh` never re-derives the marker: two extractors that disagree would archive under a
  name the detector never saw (ADR-0086's criterion, applied and honoured).
- **A checker with `3` distinct from `0`.** Without it, "no SPEC to archive" — the common legitimate
  case — is indistinguishable from "did not run at all", which is #228 itself one level up.
  `COLLISION` halts rather than overwrites: writing over an archive is #228 reproduced inside the
  directory that exists to prevent it.
- **The fence is declared and ADR-0083's classifier cannot see it.** `fence_is_abort_capable` looks
  for `exit 1`/`exit 2` or the word "abort"; this fence ends `exit "$_rc"` and its abort belongs to
  the caller. So it aborts a chain in practice and sits outside the population that would require it
  to be run. Section `SF` extracts and runs it anyway. **First measured example of what lies outside
  that classifier**, recorded rather than worked around.
- **The fix was executed, not just written** (ADR-0081's rule applied to the fix): running it
  archived the live root slot to `docs/specs/222-vendor-deployed-only-skills.spec.md`, and a second
  run reported `ALREADY`.

**Two assertions failed against correct code, both worth keeping.** `SA3`/`SA4` failed on a
**fixture**: `mk_root` incremented a counter, but `r=$(mk_root)` runs it in a **subshell**, so every
call returned the same directory and the fixtures accumulated into each other — found by reading
what the fixture produced rather than what the assertion said. And `SA10`'s first draft grepped for
`topic[[:space:]]+slug` and matched the comment **explaining why the slug is not re-derived** (rule
12, third instance); it is now behavioural, and a behavioural check cannot be satisfied by prose.

Known consequences: a `COLLISION` halts Step 1 on the unattended paths too (correct direction, new
stop); the fence is a hard dependency on a deployed script, failing closed until sync;
`artifacts.spec` still points at the root slot in **all 41** manifests, so 40 name a file holding
another chain's SPEC — measured here, filed as **#267**, not fixed here; two naming conventions now
coexist in `docs/specs/`.

Detail: `docs/architecture/ADR-0096-228-spec-archive.md`.

## Decisions from the Gate 4 axes chain (ADR-0097)

Closes issue #237, first of Wave C. Gate 4 offered three options encoding **two orthogonal axes** —
WHERE Steps 5-7 run (this session or fresh) and HOW (attended, every downstream gate asking, or
unattended with `autopilot = true` driving each to its safe default). Four cells, two offered, on
the diagonal. **Staying in-session was therefore choosing to forfeit Gates 5, 5.05, 5.06, 5.1 and
5.6, and nothing at the gate said so.** Found by a run whose explicit purpose was to exercise those
gates: taking the offered option meant the gates under observation stopped firing.

- **The block contradicted itself in the same box, and that is what kept the missing cell hidden.**
  Option 1 said the context risk is *"mitigated since coders dispatch as isolated subagents"*;
  option 2 sold itself on *"the cleanest coder context"*. The first is right — a dispatched coder is
  an isolated subagent in its own worktree (ADR-0068) and never carried this session's conversation.
  What a fresh session buys is a clean **orchestrator** context: headroom, and briefs written
  without the whole chain behind them. ADR-0042's shape, and "cleanest coder context" is precisely
  the sentence that made the fresh session look necessary.
- **Add the cell, do not document its absence.** The only argument for forcing a fresh session was
  coder pollution, which ADR-0068 settles. An option that gives up nothing should not be
  unavailable. Four options is exactly the `AskUserQuestion` ceiling, so the matrix is spanned with
  no room left — a fifth would force a split into two questions.
- **The recommendation moves to attended-in-session**, because it is the only cell that forfeits
  nothing. **Gate 4 carried no `(Recommended)` marker at all** while every other gate does and the
  global convention requires it — found by the assertion, not by reading.
- **`RH2`'s floor raised 3 → 4 in the same change.** Left at 3 it passed while reporting "all three
  proceeding paths" (true before, false after) and would have tolerated one of the four silently
  losing its `Gate 4.0` call. **A floor that no longer tracks its population has stopped measuring.**
- **The shared principle with #227, recorded here as the first of the two:** *a gate must not
  present a choice whose options fail to span the decision, and must not present two signals as if
  they were one.* #237 is the first failure, #227 the second (two "recommended" markers that can
  disagree, no stated precedence). Both at the chain's two entry gates, both from the same run.
  #227 needs a precedence rule rather than a missing option, so one edit cannot serve both.

Known consequences: the default changes, so an operator clicking the first option without reading
now gets five gates they did not get yesterday; the gate is at its four-option ceiling, and any
further cell is a redesign; the two in-session handlers differ by **one line** and `G3b` is the only
thing holding them apart; the unattended-fresh-session cell is documented rather than offered.

Detail: `docs/architecture/ADR-0097-237-gate4-implementation-axes.md`.

## Decisions from the Gate 0 recommendation chain (ADR-0098)

Closes issue #227, second of Wave C and the twin of #237. Gate 0 showed **two "recommended" markers
that can point at different options** — the question string hardcoded `Recommended: [<path>]`, while
the global convention has the orchestrator put its own choice first with `(Recommended)` — and
**nothing declared which wins**. The user saw both in one box and asked which to believe. Neither
was wrong: the vote is mechanical, the orchestrator knew the run existed to exercise Steps 5 and 6,
which hybrid never reaches.

- **The orchestrator wins, and a divergence is SHOWN.** Picking a winner and hiding the loser would
  remove the contradiction from the screen without removing it from the system — the operator would
  simply stop being told two signals disagreed. What made this a defect was not which signal is
  better but that neither was declared to.
- **The second finding is an order of magnitude stronger than the issue states.** #227 says
  `file_vote` pins to `standard` "past a few hundred files". The threshold is **20**. Feeding a
  constant `standard` into the majority rule leaves two reachable outcomes, so **`express` can never
  be auto-recommended on any real repository** — available as a click, never as a suggestion.
  Corroborated by the corpus: three manifests ever recorded a `file_vote`, all three `standard`
  (repos of 255, 541, 595 files).
- **Rename, do not re-tune.** At Gate 0 there is no feature-size signal to be had — no SPEC, no
  plan, they are what the chain is about to produce — so a repo-size proxy is the only measurable
  thing at that moment. What was wrong was the NAME. `file_estimate` → `repo_file_count`, with what
  it measures and its degenerate consequence stated at the gate. Inventing better thresholds without
  a better signal is the same error with fresher numbers.

**The plant that did NOT fire is the useful one.** `N9`'s first draft grepped for `repo_file_count`
anywhere in the skill-private harness; the plant changed only the `grep -q` pattern and the
surrounding `ok()`/`bad()` messages still carried the new name, so the assertion passed a file that
would have gone red against the renamed script. **A needle must belong to the mechanism, not to the
prose describing it** — second instance the same day, `spec-archive.test.sh` `SA10` had the
identical shape hours earlier.

**Sixth instance of the decoration family, met while writing the ADR that cites the other five.**
`N7b` failed against correct text because its clause contains a backticked word. The flattened copy
now strips backticks and asterisks as well as line breaks: a clause is the same clause whether it
wraps, whether a word inside it is code-quoted, and whether it is bolded. Structural markers stay
line-wise, because there the decoration IS the structure.

Known consequences: `repo_file_count` has three consumers, and the third is the `$HOME`-coupled
`concept-to-code/tests/run-tests.sh`, which tests the DEPLOYED copy and reads red until sync;
historical `auto_detect_reason` strings keep the old name deliberately (ADR-0075's principle); the
routing vote itself is unchanged, so a gate that can only ever suggest two of its four options is a
real limitation now stated rather than discovered; the divergence line is prose nothing enforces.

Detail: `docs/architecture/ADR-0098-227-gate0-recommendation.md`.

## Decisions from the HITL audit-trail chain (ADR-0099)

Closes issue #238, last of Wave C. Two defects in one subject, each making the other's fix useless.
**`manifest-set-gate.sh` had no instructed call site anywhere in the chain** — correct, tested,
deployed, unreachable — and **the template had no `gate: 4` slot**, so recording the one gate that
matters most exited 3. Third instance this month of a producer specified in one place and consumed
in another with nothing checking the two meet (#173, #248, this).

- **The measurement is also the baseline: 39 of 164 gate entries approved across 41 manifests, and
  the distribution is bimodal** — four manifests at 4/4, thirteen at 1/4. That is not gates being
  answered differently, it is orchestrators remembering differently. Invariant 9 counts entries and
  never reads status, so an all-`pending` trail validates clean: the trail passed the check by
  existing.
- **Gate 4 is the one that mattered, because `autopilot: true` is ambiguous by construction.**
  `project-conductor`'s nightly mode sets the identical flag with no human at Gate 4 at all
  (ADR-0022), so afterwards the flag cannot distinguish a human choosing unattended implementation
  from a roadmap pre-authorising the whole run. The chosen option name in `notes` is the only thing
  that separates them — and it is labelled `implementation_mode`, not `session_boundary`, because
  after ADR-0097 the gate asks two things and the cell is what is worth recording.
- **No status invariant, and the reason is the issue's own.** A chain legitimately sits `pending`
  mid-run and a completed chain with a pending Gate 5 is real (the `step_6_review → completed`
  direct close skips it). A status check conditional on `current_step` is ADR-0076's rule and the
  same trap.
- **Invariant 9's minimum stays 4 with five slots written.** It is a MINIMUM; raising it to 5 fails
  all 41 historical manifests for a change they predate (ADR-0078's rule applied to a count). That
  the template writes five is asserted against the TEMPLATE, not against every manifest ever
  produced.

**Planting found two things reading did not.** `min_gates=4` was assigned **twice** and the first
was **dead** — a bare assignment above a `case` whose `*)` overwrote it on every path. Found by
raising it and watching nothing change, which is exactly how a future edit meaning to raise it would
fail: silently, while looking correct. And the second plant replaced a sentence by literal string
while **the same sentence appears twice and one wraps after the word "cannot"**, so it hit one site
and the survivor still satisfied the assertion. **A plant needle must be wrap-insensitive for the
same reason an assertion needle must be** — otherwise a failed plant reads as a weak assertion and
gets "fixed" in the wrong place. Seventh member of the decoration family here, and the first on the
plant side.

Known consequences: this ships an instruction, not an enforcement — nothing makes an orchestrator
call the helper, only there is now something to call at a named place; every pre-ADR-0099 manifest
returns exit 3 for gate 4 (reported, not fatal); the trail records what the orchestrator SAYS
happened, a self-report, so it is a record and never a gate (ADR-0047 §A3); Express and Hybrid have
their own gates and the same question, measured on Standard only and left there.

Detail: `docs/architecture/ADR-0099-238-hitl-gate-audit-trail.md`.

## Decisions from the batch-dispatch openers chain (ADR-0100)

Closes issue #242, Wave D. Step 5's pre-dispatch computes `tasks=$(plan-tasks.sh --count …)` for a
`>= 1` guard, and twelve lines later the Agent-tool fallback opens a **second, different** decision
— "≥6 tasks → batches of 2-3" — naming no source. The only count in scope is `$tasks`, and
ADR-0069 §D2 says in terms that this is the one thing it must not be used for. **One number
silently served two questions;** the batching arithmetic is the symptom.

- **Measured, and wider than the issue states.** It calls the case "benign on this plan by luck".
  Across the 58 corpus plans the two counts **diverge on 51, and all 51 are ≥6 and over-counted**.
  On #222's plan: **38 and 7** — batches of 2-3 over 38 dispatch a tester and a coder against tasks
  8 through 38, which do not exist. The threshold branch is identical either way, so only the
  arithmetic diverges, one step later.
- **`is_task_opener()` already existed** (ADR-0070, for `diff-budget-check.sh`). This is the THIRD
  consumer to need it, so it becomes a `--count-openers` mode of the shared script rather than a
  third private copy — ADR-0069's own rule applied to its own script.
- **Neither substitution is safe, and both call sites say so.** `--count` over-counts: safe for a
  guard, wrong for arithmetic. `--count-openers` returns **0** on plans using a different word for a
  task: safe for arithmetic that checks zero, wrong for a guard.
- **The obvious fix introduces a failure the issue does not mention.** Two corpus plans have
  `openers = 0` with a non-zero `--count` (`### T1 —`, `### Step 0 —`, the forms ADR-0070 §PTG9 and
  ADR-0069 §PTE2 exempt by name); `deep-refactor-skill.md` counts 36 and opens 0. Consuming openers
  naively turns over-batching into **batch-nothing**. The zero case dispatches as a single block and
  says why; exit 2/3 takes the same branch.
- **The Workflow path was checked, not assumed:** it derives task GROUPS by reading the plan for
  file-path mentions and invokes no counter. `BO9b` pins it so the answer is not re-derived.

**A measurement failed silently on the way, in this repository's signature manner.** The first
corpus sweep ran `awk -f predicate.awk '{…}' plan` — with `-f`, awk treats the positional program
as a **file**, so it read nothing, printed nothing, and raised no error. Trusted, it would have
reported that the two counts agree everywhere, inside the measurement built to prove they do not.
Fixed with a temp file, which is what `plan-tasks.sh` itself already does and documents.

Known consequences: batching behaviour changes on 51 of 58 plan shapes (threshold unmoved, ranges
corrected), so the first Step 5 after deploy produces visibly fewer batches than the old instruction
implied; `task_num()` extracts digits only, so `## Task 1b` cannot be a batch range (ADR-0070's
carried limit); the two zero-opener forms are handled by a fallback, not recognised; `plan-tasks.sh`
now has two modes with **opposite failure directions** and nothing but its header and the two call
sites prevents a future caller picking the wrong one.

Detail: `docs/architecture/ADR-0100-242-batch-dispatch-openers.md`.

## Decisions from the batch-boundary precedence chain (ADR-0101)

Closes issue #247, completing Wave D. **A correction to a rule shipped four hours earlier.**
ADR-0088 §D5 states two batch-boundary rules as if they were jointly satisfiable — *do not put an
assertion in the same batch as the task it depends on*, and *do not split a red assertion from the
task that turns it green* — and on #222's plan, the ADR's own worked example, they pull opposite
ways. Rule 1 forces task 3 into a later batch than task 2 (`C7`'s RED needs task 2's vendored file);
rule 2 wants them together (`S1` reddens at task 2, greens at task 3). **No batching satisfies
both**, and a reader applying them in good faith had no way to choose.

- **Rule 1 outranks rule 2, and the reason is what carries forward: evidence quality beats
  checkpoint tidiness.** Violating rule 1 makes an assertion fail for the *wrong reason*, so the
  recorded RED proves nothing and writing the test first bought nothing. Violating rule 2 leaves an
  intermediate checkpoint red — visible, explainable, resolved by a later batch inside the same
  Step 5. `BP2b` asserts the reason separately from the verdict, because the verdict alone is a coin
  toss written down.
- **The measurement shrank the issue.** It claims an unattended run "would stop … and present a
  correctly-working TDD sequence as a failure". `autopilot-build`'s breaker reads
  `step5-report.json` **after dispatch** — once, at the end of Step 5, not per checkpoint — and `S1`
  greens at task 3, inside Step 5. The claim holds only for a red surviving to the END of Step 5,
  which is a plan already violating rule 2 with no task to green it. `BP6` pins that cadence, so a
  future change to it fails loudly instead of invalidating this reasoning in silence.
- **A red intermediate checkpoint is now defined, in three cases**, and the third is what keeps it
  from being a licence: a red in an untouched file that a later task restores is expected; a red in
  this batch's own tests is not; **anything else stops**, because an unclassifiable red is the one
  that most needs a human. `BP4` asserts the negative half — a rule that only says what is excused
  excuses everything.
- **The mechanism is deferred to #273 with reasons, not omitted.** A plan-side expected-red
  declaration needs a syntax, and ADR-0091 is the live warning about a half-parsed one. Comparing
  against the previous checkpoint's failing set needs none — but it separates *new* from
  *carried-over*, not *intended* from *unintended*, and `S1` is new at checkpoint 1, so it would
  still be reported. **The breaker stays strict until one lands** (`BP7`, forward guard).

**Two needles failed against correct text, both decoration.** `test_result = RED → halt` carries
backticks, so a plant pattern joining the words with `\s+` cannot span `` RED` → halt `` — the
needle had to be read out of the file rather than guessed. And `BP3` failed on **capitalisation
alone**: the clause opens a sentence. Prose assertions there now match case-insensitively as well as
flat and undecorated — **a clause is the same clause whether it opens a sentence or sits inside
one.** Seventh member of the family.

Known consequences: nothing executable changes, so this is an instruction with no enforcement; the
classification is a model's judgement nothing verifies; #222's plan text is off by one about when
`ui-layout-audit` enters the population and is left unchanged as a historical record.

Detail: `docs/architecture/ADR-0101-247-batch-boundary-precedence.md`.

## Decisions from the Gate 2b trust-probe chain (ADR-0102)

Closes issue #233, Wave G. Gate 2b fires whenever `test_cmd_candidate` is present and not `NONE`,
and had **no branch for "this exact command is already trusted"**. On the shakedown run the command
was unchanged, the file untouched, the read-only probe returned `TRUSTED` — and the attended path
presented the gate anyway, asking a human to re-authorise a command whose SHA was already pinned.
Approving re-ran `approve-test-cmd.sh` on the same hash: a no-op.

- **The mechanism existed and one path used it.** The autopilot branch of the same gate carries the
  probe and the reasoning (*"reading existing trust is not granting it"*); the attended path never
  got the branch.
- **The cost is not the click.** A gate that fires with a foregone answer, every run, on every
  brownfield project, is a gate people learn to approve without reading — **and this is the gate
  that guards arbitrary command execution.** A safety gate that cries wolf is worse than one that
  fires rarely.
- **One probe, hoisted above the branch split, which REMOVES a copy rather than adding a third.**
  ADR-0086's criterion has no sharper application: two copies of a trust probe is a probe that can
  disagree with itself about whether a safety gate fires. Form B's stays — different entry point, no
  Gate 2b in scope.
- **Two invariants restated at the gate, because that is where the reader deciding to skip stands.**
  `NEVER call approve-test-cmd.sh before the click` lived in §4's TOFU rules and in Form B and **not
  in the Gate 2b block** — found by the assertion, not by reading. And the pin is on **content**: a
  differing SHA gates even when the command looks identical, because a changed file is a new
  authorisation.

**The fixture was wrong, not the fence, and the positive twin is the only thing that showed it.**
`run_probe`'s first draft was `HOME="$1" sed … | bash` — **an environment prefix binds to the first
command of a pipeline only**, so `bash` inherited the real `$HOME` and read this machine's actual
trust registry. `G2B9` (empty registry → NOT_TRUSTED) and `G2B11` (edited file → NOT_TRUSTED) both
**passed** against it, because the real registry holds neither entry; they pinned nothing.
**`G2B10`, the positive twin, is the only assertion that failed.** Rule 8 executed rather than
quoted. Third fixture bug this week reporting as a defect in correct code, after ADR-0090's
`HOME`-redirect and today's `mk_root` subshell.

Known consequences: a HITL gate now fires less often, bounded to same file / same SHA / same
normalised root; the skip depends on the probe being correct, which is why it is executed in both
directions rather than asserted to exist; **the fence is declared and `fence_is_abort_capable`
cannot see it** (no literal `exit 1|2`, no "abort"), so it is executed by its own file — second
measured example of what sits outside ADR-0083's population, after ADR-0096.

Detail: `docs/architecture/ADR-0102-233-gate2b-trust-probe.md`.

## Decisions from the recovery-baseline rebase chain (ADR-0103)

Closes issue #244, Wave F. ADR-0050 §D3 writes `recovery_baseline_sha` once and never rewrites it —
*"a baseline that moves is not a baseline"*. It guarantees the **field** does not move and says
nothing about the **history under it** moving. **The sha is still the right *state* and no longer
the right *object*, and §D3 reads as covering that case when it does not.**

- **Measured: one of two recorded baselines is orphaned, and it is the one whose chain was paused.**
  The sequence is the paused-run workflow, not an exotic one — Step 5 records the baseline,
  something halts the run, fixing the blocker means a PR to `main`, resuming means bringing the
  branch up to date, and a rebase is the obvious way. ADR-0089 already establishes a paused Step 5
  as normal. The orphaned object survives in the **reflog only**, so it is one `git gc` from
  unrecoverable, and a reset to it would detach from the branch's real history.
- **Three states, three sentences.** `BASELINE_OK`; `BASELINE_ORPHANED` (exists, not an ancestor);
  `BASELINE_GONE` (does not exist). Collapsing the last two tells a human "gone" when the commit is
  recoverable, or the reverse.
- **It REPORTS and never halts, and that is the decision rather than a default.** The run is not
  damaged, only its recovery path is, so halting would trade a working run for a hypothetical one.
  Opposite call from the four pre-flight assertions above it, and for a stated reason: those guard
  *entry* to a state the chain cannot safely be in; this describes a *contingency* that may never be
  exercised.
- **Exit 3 is load-bearing here specifically.** Without the no-repo guard, `git cat-file -e` fails
  and the check reports **`BASELINE_GONE`** — a definite, alarming verdict from a check that never
  ran. The plant that removes the guard produces exactly that.
- **The operational rule, which was written nowhere (verified by search): merge `main` into the
  feature branch; do not rebase it, once the baseline is set.** A merge preserves the recorded commit
  as an ancestor; a rebase orphans it.
- **The field is never corrected, including when the check says it is orphaned.** A baseline that
  gets "fixed" whenever it looks wrong is a baseline again only in name. The #222 manifest keeps
  `dfa9a6ff…`; the equivalent commit `f1a1df07…` is recorded in the ADR, where a human looking for
  it will be.
- **The structural option is deferred with its reason:** a tag or a tree hash is not a drop-in for a
  sha, because `git reset` to a tree is not the same operation — choosing without answering "what
  does recovery actually reset to" would be inventing a mechanism to avoid writing a sentence.

Known consequences: a resumed Step 5 now prints a warning that did not exist, and on this
repository's own #222 manifest it fires immediately — correct, and it will look like a new problem
the first time; the rule is an instruction nothing enforces, since policing git operations outside
the chain's turn is not a boundary this system has anywhere; **the check is declared and
`fence_is_abort_capable` cannot see it** (it never halts, by design), so it is executed by its own
file — third measured example outside ADR-0083's population, after ADR-0096 and ADR-0102.

Detail: `docs/architecture/ADR-0103-244-recovery-baseline-rebase.md`.

## Decisions from the Step 7 snapshot-collapse chain (ADR-0104)

Closes issue #249, completing Wave F and the Phase 8 fix roadmap. When Step 7 runs, **the feature is
already fully committed** — by the orchestrator, under `chore(step5): snapshot <stage> worktree
(<agent_type>)`. Ten commits on #222's branch, 1260 insertions, **not one describing the feature**.
The staged set is then the manifest and `.gitignore`, so `commit` reads `git diff --staged` and
faithfully describes a manifest state change. **The commit the whole skill exists to produce has
nothing left to describe.**

- **Nobody chose this.** ADR-0068 §D5 made the orchestrator the committer so the next stage could
  fork from a `HEAD` containing the previous stage's output; ADR-0049 §D1 ordered
  tester-before-coder, doubling the snapshots. Two correct decisions composing into a third
  behaviour. Survivable here only because this repository squash-merges — on a repo that merges,
  changelogs from `git log`, or bisects, the history is seven "snapshot worktree" entries.
- **Step 7.0 soft-resets to `recovery_baseline_sha`, and the argument is that the snapshots' purpose
  is spent:** they exist so the NEXT stage can fork, and Step 5 is over. Without that sentence this
  is rewriting history because the log looks untidy. **A soft reset keeps tree and index exactly as
  they are** — only the tip moves, the old tips stay in the reflog — which is why it needs no gate
  of its own; `commit`'s Step 4 gate still shows the resulting diff.
- **Four guarded refusals, each leaving HEAD untouched.** `foreignCommit` (a commit the chain did
  not make — folding it away would take **its message** with it), `notAncestor` (**#244's state**,
  refused rather than inherited — which is why #249 depended on #244), `baselineGone`/`noCommits`,
  and exit 3 outside a repo.
- **The alternatives lose for a stated reason.** Richer snapshot messages leave no commit describing
  the whole; documenting Step 7 as bookkeeping with the PR body as the record is honest but makes
  **squash-merge a hard requirement of the chain**, which nothing says, on repositories whose merge
  policy the chain does not choose.

**The plant that did not fire is the one worth keeping.** Removing the ancestry guard left `SC5`
passing: the fixture's default-branch commit was `-qm c`, which after the rebase sits in the range
where the **foreign-commit** guard caught it first. `SC5` passed for a reason it does not name.
**An assertion covered by two guards isolates neither** — the fixture's commit now carries a
chain-shaped message so only the ancestry guard can refuse, and the plant fires with `COLLAPSED 4`
onto an orphaned object. ADR-0089's rule again: a plant that does not fire is evidence about the
assertion.

Known consequences: the chain now rewrites its own branch history once, at Step 7, under four
guards; **`SC8` is a cross-file contract** — rewording the merge-back message makes the collapse
stop recognising its own commits and refuse quietly on every run, since `COLLAPSE_SKIP` is a normal
outcome; the collapsed commits live in the reflog only, so a later `git gc` removes the intermediate
history for good; the fence is declared and `fence_is_abort_capable` cannot see it, so it is executed
by its own file — fourth measured example outside ADR-0083's population.

Detail: `docs/architecture/ADR-0104-249-step7-snapshot-collapse.md`.

## Decisions from the Gate 5 state-removal chain (ADR-0105)

Closes issue #265, which the derived producer guard from #248 found on its **first run**.
`gate_5_review_decision` was entered by nothing: Step 5 transitions to `step_6_review` and presents
Gate 5 from there, while Gate 5 asserted `Trigger: … current_step = gate_5_review_decision`, the
roll-up spoke of "the transition to" it, and Step 7 listed it as a valid source. Four legal pairs,
structurally unreachable. **Nothing aborted** — which is why it survived.

- **The deciding argument is one neither of the issue's two options named.** §3 already documents a
  pattern for gates with no `current_step` of their own: *"Gate 2b and Gate 5.05/5.06 are already
  inline sub-gates with no dedicated state"*, and Step 4.5 follows it. **Gate 5 is the fifth
  instance.** So the state is the anomaly, not the missing producer, and deleting it makes Gate 5
  consistent with four siblings rather than merely making the graph smaller. Moving the gate would
  have added a fifth shape to a system that already had one.
- **Measured before deciding: zero manifests ever carried that `current_step`.** No record is
  invalidated.
- **The reason is written at Gate 5 with `Do not reintroduce one`**, because the next reader meeting
  a gate without a state will otherwise fix what looks like an omission. `GR6` is the only thing
  stopping that, and it asserts a sentence rather than a behaviour.
- **Five assertions pinned 49 and were updated, not relaxed** (`E1`/`E2`/`E3`/`E7`, `TBP1`).
  **`TBP1` was changed in kind:** its message claimed the amber/reduce-scope pair "is present" while
  its test was `ACTUAL_PAIRS >= 49` — a total that moves whenever any unrelated pair does, and never
  evidence about that pair. It now asserts the pair directly, with a count guard.

**Two of my own assertions counted their own explanation.** `GR1` was `grep -q "$GONE" "$TR"`, and
the script legitimately names the state while explaining why it no longer has one; `GR5` had the
same shape against `SKILL.md`. Both now target the **mechanism** — a pair line, an exemption line, a
graph arrow, an asserted `current_step` — never the name. **Rule 12, third and fourth instance in
one day**, after `spec-archive.test.sh` `SA10` and `gate0-recommendation.test.sh` `N9`. And `GR1`'s
count used `grep -c … || echo 0`, which yields `0\n0` on no match — **the exact idiom issue #174
documented here.** `|| true` is the fix.

Known consequences: the machine is four pairs smaller and `manifest-validate.sh` now rejects a
manifest hand-edited to that state (zero existing ones affected, measured); the pair count is stated
in three files and derived in one, so three chances to drift against one detector.

Detail: `docs/architecture/ADR-0105-265-gate5-state-removal.md`.

## Decisions from the SPEC pointer / archive-on-completion chain (ADR-0106)

Closes issue #267, measured while fixing #228 and filed rather than bundled. All 41 manifests record
`artifacts.spec: <project-root>/SPEC.md`, a **single mutable slot** every chain overwrites — so the
pointer resolves to whatever the slot holds today, right for at most one manifest and that one by
coincidence.

- **The second gap the issue does not name.** ADR-0096 archives the OUTGOING SPEC when a new chain
  is about to overwrite the slot — archive-on-**displacement**. So a chain's SPEC is archived only
  if a **later** chain happens to displace it, and **the most recent chain's SPEC is never
  archived**. This repository is the proof: #176's was archived by hand by #229, #222's by hand
  today, and `120-accessibility-i18n` still has none under its slug. 36 archives, 41 manifests.
- **Step 7.0b is archive-on-completion, the other trigger, and the two compose rather than
  duplicate** — a property of `spec-archive.sh` comparing by **content**, so a second call reports
  `ALREADY` and writes nothing.
- **On failure the pointer is left alone.** A pointer at a slot is today's behaviour; a pointer at
  an archive that was never written is a new defect. The failure direction matters more than the
  success.
- **Historical manifests are not rewritten** (ADR-0075's rule: falsifying a record for no consumer
  is worse than leaving it accurate-for-its-moment). `SP5` guards the 41 slot pointers.
- **Found while writing the block, not afterwards:** the ADR-0104 collapse leaves everything staged,
  and `commit`'s Step 1 then takes the staged set only — so the freshly-written archive (untracked)
  and the freshly-repointed manifest (modified *after* staging) would **both** be silently excluded.
  `--include` exists for precisely this caller shape (ADR-0071 §D2).

**`SP1`'s first form matched the prose**: `grep -q 'spec-archive.sh'`, while Step 7 legitimately
names the script explaining how the triggers compose — so the plant that deleted the actual
invocation walked straight through. **Rule 12, fifth instance in one day**, after `SA10`, `N9`, and
`GR1`/`GR5`. `SP6`–`SP6d` passed *before* the wiring existed, deliberately: they prove the helpers
work independently of whether anything calls them.

Known consequences: every completed chain writes and commits one more file; **`artifacts.spec` now
means two different things depending on when the manifest was written** — historical ones name a
slot, new ones an archive — documented rather than reconciled; the repoint's ordering after every
in-chain reader is load-bearing and unasserted.

Detail: `docs/architecture/ADR-0106-267-spec-pointer-archive.md`.

## Decisions from the fence-contract population chain (ADR-0107)

Closes issue #281, found by sweeping Phase 8's ADRs for a disclosure repeated four times.
`fence-contract-coverage.test.sh` derived `CONTRACT_IDS` from `ABORT_LIST` — the **abort-capable**
subset — so a fence that declares itself and then ends `exit 3` or `exit "$_rc"` sat outside `F4`,
`F6` and `F7`. **Measured: 18 declarations, 13 in the population, 5 invisible.**

- **The defect was never coverage.** All five were executed by a test and all five parsed, checked
  before proposing anything. **What was missing is that nothing checked it** — four ADRs (0096,
  0102, 0103, 0104) assert coverage by hand, in prose, and each was telling the truth. **A hand
  assertion that is true reads exactly like one that is verified**, which is ADR-0095's
  producer/consumer shape one level up.
- **The fifth entry is why it matters.** `concept-to-code-step5-plan-structure` had been outside its
  own guard since before the session, and no ADR noticed. Four disclosures were written about a
  population none of them had counted.
- **`F3`, `F5` and `F8` deliberately keep the narrow population.** `F3` asks "must an abort-capable
  fence declare itself", so that subset **is** its question; `F8` measures the escape hatch from
  `F3` and would change meaning if widened; `F5` rides on `F8` and there is exactly one illustration
  in the corpus, inside that subset — measured, with what would have to change if a second appeared
  outside it written at the site.
- **`F9` states a property, not a number**, so it cannot rot: every marker that exists must be in
  the checked set. `F10` guards the denominator — an enumeration that stops matching would empty
  `F4`, `F6`, `F7` and `F9` at once, and four silent passes read as coverage.

**An honest note about the RED evidence.** Reverting the derivation makes `F9` fail naming all five,
which is the evidence. `F6` also failed there with a nonsense message ("an id is reused") because
the plant reverted `CONTRACT_IDS` and not `RAW`, comparing two populations that never coexisted —
**an artifact of an incomplete plant, not a finding.** ADR-0090's "inspect what the plant actually
produced" rule, applied to my own plant.

Known consequences: four ADRs now carry a dated `## Correction` because their consequence bullets
became false (bodies unedited, ADR-0034 precedent); a declared fence that is genuinely not executed
now fails where it was invisible, which is a new way for the harness to redden on a file nobody
touched.

Detail: `docs/architecture/ADR-0107-281-fence-contract-population.md`.

## Decisions from the plant registry (ADR-0108)

Closes issue #284, Phase 9.1. **Rule 12 — a scan whose needle is a literal counts itself — bit five
times in one day** (`SA10`, `N9`, `GR1`, `GR5`, `SP1`): each an assertion whose needle was the NAME
of the thing it asserted about, matching a file that legitimately names it while explaining it.
Every one was caught by planting a defect and watching the assertion fail to fail. **The plants
worked; nothing made them durable** — a plant is typed into a shell, watched, and thrown away.

**THE MECHANISM — a plant is declared beside its assertion and executed by the harness:**
`# plant: <assertion-id> | <path-relative-to-staging> | <needle> | <replacement>`, run by
`plant-check.sh` against an isolated `cp -R` of the tree.

- **Two cheaper root fixes were measured and ruled out.** A static detector on multi-match needles
  flags **77 of 181** resolvable assertions (43%), dominated by legitimate cross-references, and is
  blind to the **362 of 543** that are not statically resolvable at all. A code-only projection
  catches **4 of the 5** — `N9` matched inside `ok`/`bad` **message strings**, which is code, not
  commentary — and collides with ADR-0086's refusal to share a helper across 67 hermetic files.
  **What distinguishes a rule-12 defect is behavioural**: the assertion still passes when the
  mechanism is removed. That is mutation testing and nothing else.
- **Three properties, each earned by a past failure.** The needle's words are joined on `\s+` so a
  wrapped clause is still matched (ADR-0099). **Exactly one match is required** — zero means the
  needle rotted, more than one means the plant hits sites it did not intend, and both happened the
  day this was designed (ADR-0099 `P4`/`P5`, ADR-0104 `P2`). Each plant runs against an isolated
  copy, so nothing can touch the real tree.
- **Replacement only in v1.** Two of the session's plants were insertions and are not expressible.
  Named as a limit rather than worked around.

**The registry found a real defect on its first run, which is the whole argument for it existing.**
14 of 15 plants fired; **`TP6` did not.** It checked that Step 5's pre-flight contains a
transition-ish word *and* the string `step_5_implementation` — and the prose introducing the block
satisfies both on its own, so replacing the actual `bash …manifest-transition.sh` call with `true`
left it green. **Rule 12's sixth instance, caught by the mechanism built for the first five**, on a
file written earlier the same day and reviewed twice.

The plan called for manufacturing a deliberately weak assertion to prove the runner reports a
non-firing plant. **That fixture was not needed** — the runner did it live, and `PC1` named it.
Live evidence beats a synthetic case built to pass.

Known consequences: CI gains a step that re-runs other harnesses against mutated copies, kept
separate because "an assertion pins nothing" is a different signal from a harness going red; ~0.8s
per plant, so 100 plants would want their own job; **the registry is itself an assertion corpus with
no plants of its own** — `PC0`/`PC3` guard its denominator, but the regress stops there, one level
higher than yesterday.

Detail: `docs/architecture/ADR-0108-284-plant-registry.md`.

## Decisions from the manifest entry-state chain (ADR-0109)

Closes issue #319, first of Phase 10.0 — the blockers found by trying to RUN the chain rather than
by reading it. The 2026-07-31 launch left a manifest at `step_0_init` and nothing could touch it:
Form A exits 2 saying *use resume*, Form B answers *resume not necessary, continue in current
session*. Both enforced by code.

**The whole issue reduces to one sentence: Form B's remedy named a command that does not exist.**
The in-session entry point is Form A, and Form A refused. Neither half was wrong about its own job;
nothing owned the seam.

- **Measured before designing, and the issue was under-stated four ways.** Form A's guard is on
  **file existence**, never state, so no transition can unblock it and Form C (abort) preserves the
  file, so it does not either. Form B resolved **2 of 13** standard states. **Three matched no
  branch at all** — `step_4_session_boundary`, `step_6_review`, `step_7_commit` — and ADR-0095 had
  disclosed only the second. Express/Hybrid can never resume. A **completed** chain was deadlocked
  too, with the two errors pointing at each other.
- **`step_4_session_boundary` was the one that mattered and was disclosed nowhere.** Gate 4's own
  "Abort chain" message tells the operator to resume from it, and `project-conductor` Step 3 and
  Step 5 branch B both act on it by invoking Form B — so the conductor's primary resume path
  targeted a state the table could not serve.
- **"No file" and "unparseable" are TOKENS, not exit 3, and the first draft got this wrong.**
  Folding them into *could not run* makes "nothing is there, create one" — the overwhelmingly
  common case — indistinguishable from "this machine has no PyYAML". **That is #319 reproduced one
  level down.** Absence and corruption are facts about the INPUT; exit 3 is a fact about the
  ENVIRONMENT (ADR-0076's line, drawn again).
- **The state enum is DERIVED from `manifest-validate.sh`, count-guarded at `>= 25`** — two copies
  would answer differently the day either gains a state, which is ADR-0086's criterion for
  extracting. But validity is judged on `current_step` **alone**, never by running the validator:
  its 28 invariants include ones a routable manifest can legitimately fail (ADR-0078's dead
  `project_root`, on five of this repository's own), and refusing an adoptable chain over an
  unrelated invariant would be a stricter defect than the one being fixed.
- **`status` is read as well as `current_step`, and that is the Form C case.** Form C sets `status:
  aborted` and leaves `current_step` where it was, so reading one field would restart a chain a
  human deliberately stopped. `MES8` is the negative twin of `MES2`: same fixture, one field apart,
  opposite verdicts.
- **`manifest-init.sh`'s exit-2 contract is untouched by design** (R-04). It became the backstop for
  the one case a classifier cannot cover: the date rolling between the check and the call.

Known consequences: **the manifest corpus cannot validate this value domain** — 42 manifests yield
41 `TERMINAL` and 1 `ADOPTABLE`, because a stored corpus is terminal by nature, so ADR-0092's
technique does not apply and the tokens are pinned by fixtures instead; the routing is an
instruction, not an enforcement; inert until sync, with `MES0b` as the only `PAIRS` guard since
`pairs-completeness.test.sh` cannot see a skill `scripts/` file; the near-midnight race survives on
purpose. `MES0`/`MES1`/`MESX4`/`MESW` pass before and after — forward guards. The five seen RED are
`MES2`, `MES4`, `MES8`, `MESF2`, `MESB1`.

Detail: `docs/architecture/ADR-0109-319-manifest-entry-state.md`.

## Decisions from the permission-posture pre-flight (ADR-0110)

Closes issue #320, second of Phase 10.0. `nightly-autopilot` states its first launch precondition
**three times in prose** — set a non-blocking permission mode — and Phase 0's eight checks verified
it **nowhere**. On 2026-07-31 pre-flight printed `PASSED`, the guard armed, the roadmap started, and
the chain died at its first Gate 0 write with nobody to answer the prompt. Every other precondition
fails loudly and early; this one failed silently and late, and it is the only one whose failure is
**guaranteed** fatal rather than conditional.

- **`settings.json` is the wrong source, and wrong in the direction that matters.** It holds
  `permissions.defaultMode` — the STORED DEFAULT. A session started with `--permission-mode` or
  switched with Shift+Tab never writes there, so a stored `acceptEdits` would **pass** while the
  session runs `auto` and dies. Proven live: settings said `auto` while the session was in `plan`.
  The environment carries nothing either — none of the nine `CLAUDE*` vars has a permission field.
- **The effective mode IS observable: `permissionMode` in the session transcript**, a top-level key
  on `user` entries and on a `type: "permission-mode"` entry emitted on change, with the transcript
  located from `CLAUDE_CODE_SESSION_ID` (ADR-0029's name). **The LAST value wins** — reading a first
  or stored value is the same defect in different clothes.
- **Build-stamped, and the field is NEW.** 39 of 42 local transcripts carry it; the two real
  exceptions are CC 2.1.219. So `UNOBSERVABLE` is a first-class token, and the gate **fails closed**
  on it: before 2.1.220 the unattended paths will not start. Stated in the message, chosen
  deliberately, because the alternative is the silent `PASSED` that cost the run.
- **A top-level JSON key, not a grep, and the reason is not the obvious one.** Measured on a
  transcript quoting the field inside a tool result: grep 114, parser 114 — no divergence. The naive
  grep survives *only* because JSON escapes nested quotes, an accidental property of the format.
  Relying on it would be rule 12 at run time.
- **`dontAsk` is refused as UNCLASSIFIED, and both messages say "not known-bad, just unmeasured".**
  For a pre-flight the safe direction is to refuse the unknown; telling an operator their mode is
  unsafe when nobody measured it sends them hunting a problem that may not exist.
- **Two call sites, one script** (ADR-0086): `nightly-autopilot` gets a **Phase M above Phase P** —
  Phase P writes files, so a check inside Phase 0 would let a blocking mode stall it first — and
  Phase 0 gains a sentence that the check **must not be added as a ninth** there. `autopilot-build`
  gets **check 1b**: not first (check 1 is the scope guard), not last (a blocking mode can deny the
  checks in between), with that rationale written at the site so nobody moves it.
- **`/permissions` does not set the mode**, and hooks are a third axis it does not touch. The launch
  order now names Shift+Tab, `--permission-mode`, and `permissions.defaultMode` — an instruction
  whose remedy names no runnable command is the defect ADR-0109 closed one level up.

Known consequences: whether `acceptEdits` is *sufficient* is unmeasured — Bash outside the allowlist
still prompts, so a green posture check is not "no prompt is possible"; `dontAsk` blocks runs until
someone measures it; inert **and worse than inert** until sync, since both fences abort with "the
check DID NOT RUN"; a pre-flight is a snapshot and cannot see a mode changed mid-run. `PM0`/`PM10`/
`PM11`/`PMF9` pass before and after; the five seen RED are `PM2`, `PM3`, `PM4`, `PMF3`, `PMF7`.

**A false positive that found a true defect**, recorded because ADR-0051 tracks this detector's
precision. `weakening-scan.sh` flagged the per-line `except Exception: continue` around
`json.loads` — a **correct** swallow, since an append-only transcript can have a half-flushed last
line. But looking at it surfaced a real defect two statements below: the `python3` call had
`2>/dev/null` and no status check, so an interpreter failure produced an empty result and reported
*"a pre-2.1.220 build does not write it"* — **a cause that is not the cause**, inside the file whose
whole subject is reporting the right reason for a state. `PM9b` pins it. The finding was wrong; the
investigation it triggered was not.

**Harness lesson, third fixture bug of its family this week:** `PMF2`–`PMF7` first failed against
*correct* fences because the stub generator mis-quoted a `printf`, and its first draft named the
stub directory from a counter incremented inside `$(...)` — a subshell, so every call would return
the same directory. ADR-0096's `mk_root` bug, met again ten days later by the same hand.

Detail: `docs/architecture/ADR-0110-320-permission-mode-preflight.md`.

## Decisions from the conductor entry-failure split (ADR-0111)

Closes issue #324. `project-conductor` Step 5 branch C wrote the **run-level** `needs-human` marker
for every feature that did not reach `completed`, and `nightly-guard` blocks that publish and every
subsequent one. ADR-0060 §D3 removed exactly this blast radius from `spec-from-issue`'s two skips
eleven days earlier; **it survived through a second door.**

- **#319 had already built the classifier and deferred this policy BY NAME**, in two places
  (`manifest-entry-state.sh`'s header, c2c step 4b). So the issue's central question — can branch C
  tell the causes apart from where it stands — answers **yes for the manifest-shaped causes**, and
  the token vocabulary existed. Both deferral notes are now the decision, because a stale "not
  decided here" sends the next investigation to a closed question (the ADR-0016 rot, recorded above).
- **The issue's cause 1 is stale in its stated form.** `manifest-init.sh` exit 2 is no longer how a
  same-day collision reaches branch C from inside c2c — step 4b intercepts first and it surfaces as
  `ENTRY-ROUTE: TERMINAL`. But **the conductor calls `manifest-init.sh` itself**, outside that
  guard: cause 1's remaining door, and why `conductor-step4-init-guard` exists.
- **Cause 2's evidence is NOT at branch C.** The conductor's own comment claimed *"the c2c autopilot
  pre-flight hard-aborts at Gate 0 for a missing SPEC.md"*. Measured: it does not — the chain routes
  greenfield and Step 1 dispatches `interview-driver`, **interactive**, unattended. The manifest is
  left `step_0_init`/`in_progress`, which reads `ADOPTABLE`, indistinguishable from any mid-flight
  state. Settled at Step 4 instead, where the conductor already knows — the issue's own instruction,
  applied. The sentence routing it to "Step 5C" is deleted: it pointed at a branch with no mechanism
  to act on it, the producer/consumer shape #173, #248 and #319 each recorded in turn.
- **A third contained cause nobody named:** Gate 4.5's autopilot default is *"Hand-code (abort)"* on
  a red tracer probe, transitioning `aborted aborted` with the reason recorded. A chain that wrote
  down exactly why it stopped is the clearest possible *known and contained*, and it halted the
  whole roadmap.
- **The token alone decides, and no timestamp is compared.** Separating "a previous run's terminal
  manifest" from "this run's chain aborted" buys nothing — both are decided ends — and breaks on any
  `git checkout`. What leaves an undecided state is a crash, and a crash leaves a **non-terminal**
  manifest. **ADR-0047 §D5's weakening halt never transitions, so it stays run-level with no
  carve-out** — a property of the rule rather than an exception in it. `B6` is the assertion that
  goes red if anyone widens the skip path.
- **Branch C's message was wrong on the live case**: it read `current_step` only, so a Form-C
  manifest (`status: aborted`, step untouched) reported `step_0_init`. ADR-0076 §THE RULE forbids
  that read; ADR-0109 built the classifier to read both fields for precisely this.

**The plant registry earned its keep on its first outside use.** Seventeen plants, **sixteen fired**;
`B9` did not. Inspecting what the plant produced (ADR-0090) showed the fence guards "did not run"
**twice** — missing file, and non-zero exit — and the fixture deleted the file, so the first guard
exited before the planted line ran. **An assertion covered by two guards isolates neither**
(ADR-0104, met again). Split into `B9` and `B9b`, one fixture per guard, eighteen plants all firing.
And `W8`'s needle was `manifest-entry-state.sh`, the script's **name**, which also appears in the
`_mes=` assignment — deleting the invocation would have left it green. **Rule 12, in the assertion
written to guard the mechanism it names**, the sixth instance in two days.

Known consequences: a run-level guard now passes on strictly more inputs (bounded to one token), so
the first nightly run past a previously-halting feature will look like a regression; this ships an
**instruction, not an enforcement**; inert until sync and **worse than inert** for branch C, whose
fence exits 3 when the classifier does not resolve — an un-synced machine halts rather than
mis-routes. **Recorded not fixed:** Gate 0 has no `[Autopilot default: …]` block at all, so an
unattended chain stalls at its first gate and the `[auto]` SPEC pre-flight is never reached —
filed as **#329**, because what the safe default *is* needs its own decision.

Detail: `docs/architecture/ADR-0111-324-conductor-entry-failure-split.md`.

## Decisions from the stale guard marker (ADR-0112)

Closes issues #321 and #323 together. `nightly-autopilot` arms `nightly-guard` in Phase 1 and
disarms in Phase 2 **only**, so a session that dies leaves the guard live in the human's own later
sessions with nothing pointing at the file to remove.

- **They ship together because neither explains the 2026-07-31 incident alone.** A stale marker
  blocks only *forbidden* publishes; an ordinary `git push` passes the halt checks. What turned an
  ordinary publish into a forbidden one is #323 — `is_forbidden_publish`'s destination rule ran over
  the **whole command** while the two rules above it are scoped to the push segment, so
  `git push -u origin feat/x && gh pr create --base main` read the PR's `--base` as the push's
  destination. **Third recorded instance of fixing a boundary in one rule and not its sibling**
  (ADR-0074 R1, ADR-0079 R2); the site now says *if you add a fourth rule here, scope it too.*
- **The pid #321 proposes is the one signal that cannot work.** The marker is written from a Bash
  tool call whose subprocess exits within milliseconds, so a recorded `$$` is always dead and a
  liveness check on it would report every live run as stale. Session id and timestamp are the two
  real signals; `.session_id` is already read by three hooks.
- **`.claude/nightly-state/started-at` exists in this repo and NOTHING writes it.** §3.1 said
  *"record `started_at`"* without naming a location, so an orchestrator invented one. **A value with
  no specified home gets one anyway, chosen by whoever runs the step** — which is why the marker's
  format is now written out rather than described.
- **The RUNBOOK's one grep hit was worse than a gap.** It sits in `## Aborting a run` — the section
  a human lands on after stopping a run — and says the tree "is intact", reading as *nothing left to
  do* at the exact moment the marker is being abandoned.
- **`nightly-disarm.sh` refuses the OWNING session**, so R-04 is a property of the mechanism rather
  than a sentence. It claims **no liveness oracle**: a different session id is not proof the owner is
  dead, and a transcript-mtime threshold would be a heuristic sold as proof. **The recovery path
  never fails closed** — a legacy ownerless marker and an unknown current session both disarm, with
  a note, because refusing there strands exactly the people it exists for.
- **It clears all five blockers, not just the marker.** A stale `build-status` reading `RED` halts
  `--check` regardless of the marker, so a marker-only disarm looks like it worked while the human
  stays blocked. Exit 3 (did not run) is separate from 0 because a blocked human reads 0 as "you are
  free now".
- **The guard names the exit only when it is NOT the owner.** Same session, or an unreadable id →
  message byte-identical to before. Inviting a running roadmap to disarm itself is what R-04 forbids.

**Plant lessons, two, both reusable.** Five of fifteen plants did not fire for one shared reason:
**they were negative assertions, and deleting a mechanism cannot break "X must not happen."** The
mutation must invert the condition or reintroduce the banned thing. Then `O5` survived that fix and
needed ADR-0090 applied literally: **a replacement cannot contain a newline**, so
`echo "..." >&2 exit 0` collapsed to one line makes `exit 0` two *arguments* to `echo` — no exit, and
the fall-through branch still exits 2, so the assertion kept passing. It matched exactly one site and
passed `PC2`; **`PC2` cannot see this class at all**, because the needle was fine and the mutation
simply was not the mutation it described.

Known consequences: the guard denies strictly less on one rule (every genuine push-to-main form is
asserted to still halt); the RUNBOOK names a command that does not exist until sync — the same defect
ADR-0109 closed, in a new place; the arming half is an instruction, so a run writing a bare `touch`
still arms an unattributable marker, which is why the legacy path is a tested first-class state.
**Recorded not fixed:** nothing detects a stale marker proactively — a human must be blocked once
before learning the command exists.

Detail: `docs/architecture/ADR-0112-321-323-stale-guard-marker.md`.

## Decisions from the invariant-4 two-field terminality chain (ADR-0113)

Closes issue #331. `manifest-validate.sh` invariant 4 exempts a dead `project_root` when the chain
is terminal and decided terminal by reading **`current_step` alone**. Form C sets `status: aborted`
and leaves `current_step` untouched, so an aborted chain is terminal by one field and live by the
other — the 2026-07-31 orphan validates on the machine that produced it and fails on CI, which is
the machine-dependence ADR-0078 exists to remove. **Third site of one defect**, after ADR-0109 built
`manifest-entry-state.sh` to read both fields and ADR-0111 applied the same reading to conductor
branch C.

- **The widening is smaller than it looks and the ADR says so.** All 41 corpus manifests are
  `completed | completed`, so every one already takes the exemption through `current_step`. Exactly
  one file's verdict changes: the 42nd. Invariants 7 and 8 also read one field, but their condition
  *is about that field by name* — invariant 4 is the only one asking "is this chain over", so there
  is no fourth site.
- **The two axes are exempt for two DIFFERENT reasons, and restating one over the other would be
  the defect.** ADR-0078's proof is that the exempt states never appear as a SOURCE in
  `manifest-transition.sh`'s pair table. `status` is not in that table at all — the script validates
  a **new** status passed as an argument and never inspects the one on disk — so a status-terminal
  manifest can still be hand-transitioned. Axis 2 rests instead on it being a **declared end**,
  ADR-0109's reading. The source instructs the next reader not to restate axis 1's proof over it.
- **Two copies, pinned by a derived guard, because ADR-0086's criterion meets a cycle.**
  `manifest-entry-state.sh` already reads both fields but DERIVES its state enum from
  `manifest-validate.sh`; a dependency the other way closes a loop. `A6` derives the terminal set
  from both files at run time and requires them equal, count-guarded on both sides.
- **An existing fixture was corrected, not an assertion relaxed.** Every fixture inherited BASE's
  `status: "completed"` while patching `current_step` alone, so a fixture *named* in-flight was
  terminal on the axis nothing was reading yet. `B4` went red the moment the second field was read:
  the assertion was right, the fixture was under-specified, and its coupling had never been stated.
  `mk()` now takes the status explicitly.
- **Found on the way, same class one list over — four harnesses had NEVER run in CI.**
  `docs-ci.yml`'s `shell-tests` job enumerates harnesses by name and had drifted by four, one from
  each of the last four merged PRs. `pairs-completeness.test.sh` — the file whose subject is *a file
  that exists but is in no list* (ADR-0043) — gains `CI0`/`CI0b`/`CI1`/`CI2`, with
  `# ci-dark-exempt:` travelling in the harness's own header. **Both denominators are guarded for
  asymmetric reasons:** an unmatched `for t in` line empties the list and makes everything read as
  uncovered (loud); an empty file glob leaves nothing to check and reads as full coverage (silent).
- **`CI1` carries no plant and the reason is written at the site.** `plant-check.sh` mutates
  `staging/` and `docs/`; the workflow file is in neither. Its evidence is live instead — the first
  run failed naming the four real harnesses. A missing plant that is not explained reads as an
  oversight.
- **`A1`'s derivation needed `s/).*//` rather than `s/)//`** once the case arm carried its body on
  the same line, or three assertions compared against `abortedproject_root_terminal=1;;` and
  reported a disagreement that did not exist. ADR-0077's `compliant()` lesson in a new place.

Known consequences: the exemption passes on strictly more inputs (bounded, with `B4`/`D2` asserting
both live axes still fail); `manifest-transition.sh` still does not refuse a status-terminal
manifest — disclosed, follow-up issue, ADR-0047 §A2's blast radius; nothing asserts the two fields
agree and nothing should, since Form C makes them disagree on purpose.

Detail: `docs/architecture/ADR-0113-331-invariant-4-two-field-terminal.md`.

## Decisions from the required-checks audit (ADR-0114)

Closes issue #322, the last Phase 10.0 chain blocker. `nightly-autopilot` pre-flight check 8 ended
*"verify the `ci` check is required on `main`"* while `main` requires **three** contexts —
`set-branch-protection.sh` unions exactly one into whatever is already there, so the other two
arrived by a route the pre-flight never knew about.

- **The issue understates it: check 8 had NO MECHANISM AT ALL.** Checks 3 and 6 carry fence
  contracts; check 8 was prose, and grepping `staging/` for a protection API call returns one hit,
  inside `set-branch-protection.sh`. It did not verify one context of three — it verified nothing,
  and nothing had ever executed it.
- **Authority: the LIVE required set, derived, never declared in the opt-in marker.** A declaration
  cannot lower what GitHub enforces, so one that disagrees is stale rather than lighter. The
  "a silently-added check should be a FINDING" concern is answered by **satisfiability** instead —
  nothing produces it, so the audit aborts — which keeps the property without a config field that
  can drift.
- **Three of five outcomes mean "nothing was found to be broken", and they are different
  sentences:** `PASS` (every one verified), `NO-REQUIRED-CHECKS` (nothing to verify),
  `DID-NOT-RUN` (nobody could look). Collapsing any pair is this feature's own defect one level
  down — ADR-0076's line drawn twice rather than once.
- **Producer evidence is a UNION of two sources, and the reason is the failure direction.**
  Observed check-runs on the branch HEAD ∪ job identifiers in `.github/workflows/*.yml`. Zero
  evidence from both is `DID-NOT-RUN`, never `UNSATISFIABLE`: a false PASS costs what the system
  already had (nothing verified), a false ABORT costs the whole night. Step-level `name:` values
  are deliberately excluded — a context called `Checkout` must not be satisfied by every checkout
  step in the repo.
- **`rc=3` ABORTS check 8.** Distinguishing "could not look" from "found nothing wrong" exists
  precisely so that branch can exist; a pre-flight starting a roadmap on an unknown merge gate has
  verified nothing while printing `PASSED` (ADR-0110's posture).
- **`ci_status` becomes the AGGREGATE over the required set**, with an additive `required_checks`
  detail object. Byte-identical on a repo requiring one check; correct rather than misleading on
  one requiring three. Never derived from `gh pr checks` output, which lists every check that ran
  whether required or not.
- **Measured and reported, not fixed: `shell-tests` is not a required check on `main`.** The job
  that runs the whole harness and the plant registry does not gate a merge. The audit reports it
  every run as `not-required:`; making it required is a repo-admin decision.

**Three plant lessons, all in the plants rather than the assertions.** `A2`'s plant aimed one line
off — it removed the `note:` header while the assertion reads the line below it. `A4`'s fixture ran
the wrong way round: the substring danger is a context contained IN a producer (`ci` in `cid`), not
the reverse, and dropping `-x` changed nothing under the inverted fixture. And **three plants were
silently truncated by the declaration syntax**: ` | ` is the field separator and *"cannot appear
inside a field"*, which every shell pipeline contains — `A3` and `C3` reported as **fired** from a
mutation that was not the one they described. **A plant that fires is not evidence until you have
seen what it produced** (ADR-0090, earned three times in one feature).

Known consequences: the pre-flight aborts on strictly more inputs; the fence is a hard dependency
on a deployed script and is **worse than inert** until sync; `PASS` means every required context has
a PRODUCER and never that it will be green; the `Workflow / job` context form is not decomposed.

Detail: `docs/architecture/ADR-0114-322-required-checks-audit.md`.

## Decisions from the Gate 0 autopilot default (ADR-0115)

Closes issue #329, the last Phase 10.0 chain blocker. §5 promises that under `autopilot = true`
every gate skips its `AskUserQuestion` and auto-selects a default listed inline as
`[Autopilot default: …]`. **Gate 0 — the chain's FIRST gate, which fires on every feature — had
none**, so an unattended run raised a question `/goal` cannot answer before doing any work. That is
the 2026-07-31 launch, in one sentence.

- **Nothing in the harness asserted the contract.** Grepping all 72 test files for `Autopilot
  default` returned **zero** hits, which is how one missing block survived thirteen present ones.
  Section G derives all 18 §5 gates at run time and requires a marker or a declared
  `<!-- autopilot-gate-exempt: … -->`. It found a **third marker spelling** on Gate 4.5
  (`[Autopilot default is deliberately NOT …`) on its first run — recognised by nothing, described
  by nothing. Normalised; Gate 4's `bypass:` is NOT, because `recovery-preflight.test.sh` `RH4`/`RI1`
  use it as an awk **extraction boundary**.
- **The default is `standard`, and the marker says why it is not the auto-detect vote.** Step H1
  invokes `interview-driver` **unconditionally** — unlike standard Step 1 it has no brownfield skip
  — and Express E1 runs plan mode. Only `standard` completes with nobody present. The vote is the
  obvious-looking choice and it is the wrong one.
- **The SPEC pre-flight moved from the `[auto]` option to §2 step 7b, and the old copy is deleted.**
  Inside the option it was unreachable by the only caller that needs it (nightly sets `autopilot`
  *before* Gate 0 renders, so nobody clicks `[auto]`); inside the gate the `express|hybrid|standard`
  prefix fast path would skip it. Two copies of one safety question can disagree about whether the
  gate fires — ADR-0086's criterion, applied.
- **Every abort transitions the manifest to `aborted` FIRST.** Left in flight it reads `ADOPTABLE`
  at conductor branch C → run-level halt, reintroducing the blast radius ADR-0111 had just removed.
  Exit 3 deliberately does not transition: an unread gate is not a decided end.
- **The conductor's SPEC-COPY guard stays primary and its text says `do not remove it`** — both are
  contained skips now, but that one settles the feature before any manifest exists, and it is the
  only cover for the attended *"Start in autopilot mode"* branch, which never runs the copy.
- **`chain_path: null` is tolerated, measured:** 18 of 41 corpus manifests carry `autopilot:true`
  with `chain_path:null`, all brownfield, all completed. `express`/`hybrid` with autopilot: **0**.

**Five assertion defects, all caught by planting, four of them shapes already in this file.** The
`^_c2c=` redirect anchor missed the fence's three-space list indentation, so `G5`–`G8` went green
**against the deployed copy**; `[^]]*standard` stopped at the `` `[s]` `` three characters in; the
`G1` plant did not fire because "standard" appears five times in one marker line; the `G4` plant did
not fire because the extractor matched `fence-contract: <id>` as a **substring** and the mutation
renamed by appending; the `G9` plant collapsed `echo` + `exit 0` onto one line (ADR-0112) and `G9`
was covered by two guards so it isolated neither (ADR-0104).

**The registry's own boundary, found the hard way.** `plant-check.sh` collects with
`grep '^# plant:'` — **column-anchored**. Eight declarations written beside their assertions inside
an `if` block were **silently skipped**: they did not run, did not fail, and the only symptom was a
file appearing to carry fewer plants than its author wrote. That is the registry's own failure mode
one level up. **`PC4`** now fails on any indented declaration.

Known consequences: this ships an instruction, not an enforcement (only the fence executes); the
fence is a hard dependency on a deployed script and **worse than inert until sync**; a tolerated
`null` chain_path makes a genuinely-unrouted run indistinguishable from 18 historical ones; Gate 0's
`⚠ topic could not be verified` warning still renders where nobody reads it. **This does not close
Phase 10.0** — the exit criterion is a launch reaching a `NIGHTLY-PUBLISH` line, which still needs
`permissions.defaultMode` off `auto`.

Detail: `docs/architecture/ADR-0115-329-gate0-autopilot-default.md`.

## Decisions from the permission-posture overpromise (ADR-0116)

Closes issue #339. The pre-flight accepts two modes as `NONBLOCKING` and printed **one** message for
both — `"✓ permission posture: acceptEdits — no per-tool prompt will fire."` True of
`bypassPermissions`, **false of `acceptEdits`**, which auto-accepts *edits* while a Bash command
outside `permissions.allow` still prompts. **Found by the operator running the chain, not by the
harness.**

- **ADR-0110 had named this and then contradicted it.** Its "known consequences" said *"whether
  `acceptEdits` is sufficient is unmeasured"* while the operator-facing text asserted the opposite.
  Now measured: this machine's allowlist holds **16** Bash entries and the chain's own surface
  (`bash ~/.claude/skills/*/scripts/manifest-*.sh`, `sed`, `awk`, `mkdir`, `git push`,
  `gh pr create`, the project's `test-cmd`) is **not among them**. Insufficient in concrete, not in
  principle.
- **Six sites, and the ORDERING was as much the defect as the wording:** both launch instructions,
  both success messages, both `BLOCKING` remedies named `acceptEdits` and never
  `bypassPermissions`. An operator following the instruction landed on the mode that does not work.
  **The "from `auto`, two presses" recipe is deleted** — it lands on `acceptEdits`, and it is a
  claim about a cycle order nobody here has verified. Read the mode off the status line.
- **`acceptEdits` stays `NONBLOCKING`; only the message changes.** A repo whose allowlist genuinely
  covers its Bash surface makes it sufficient, and deciding that is the caller's job — the reporter
  reports, the caller decides (ADR-0076 §D2). Demoting it would move policy into a script designed
  to hold none.
- **`docs/RUNBOOK-nightly-autopilot.md:74` still said `/permissions   # choose acceptEdits`** —
  wrong on both counts, and ADR-0110 had already established that `/permissions` does not set the
  mode. The correction had reached the SKILL and never the RUNBOOK, which is the document a human
  opens at launch.
- **The guard is derived over LIVING instructions** (`staging/plugin/skills/*/SKILL.md`, their
  `scripts/*.sh`, `docs/RUNBOOK-*.md` — 73 files, count-guarded): every line claiming no per-tool
  prompt must name `bypassPermissions` on that same line. `ADR-0022:179` keeps the old phrasing
  byte-unchanged and gains a dated `## Correction` (ADR-0034 precedent) — a historical ADR records
  its moment; the guard is about what someone reads at launch time.

**Second boundary of the plant registry, closed the same day as the first.** `PMQ3` asserts the
RUNBOOK, and its plant **could not be declared**: `plant-check.sh` resolved every target under
`staging/`, so a claim living in `docs/` was unplantable by construction — even though the sandbox
had been copying `docs/` all along so tests could read it. A literal `../docs/` prefix is now
accepted, with any other `..` refused so the widening cannot leave the sandbox. With `PC4`
(ADR-0115, hours earlier) that is two boundaries in one day, both the same shape: **a plant that
cannot exist looks exactly like a file that needs none.**

Known consequences: no run is newly blocked — an operator in `acceptEdits` is newly told what they
are actually getting, and the branch proceeds rather than refusing (refusing would demote the mode
by the back door). **Nothing verifies that a given repo's allowlist covers its chain's Bash
surface**; building that means enumerating a surface that is prose across several SKILL.md files —
named, not half-built. The RUNBOOK now names a mode this repository has not yet run a full night in.

Detail: `docs/architecture/ADR-0116-339-permission-posture-overpromise.md`.

## Decisions from the PATH-RULE bare-mention chain (ADR-0117)

Closes issue #286. ADR-0028 fixed five bare `manifest-set-flag.sh` mentions in
`concept-to-code/SKILL.md` and deferred a sixth. **Re-deriving the population rather than trusting
that count found 16 findings across 10 call sites** — and five of the ten were written by ADR-0099
(issue #238) *three weeks after* ADR-0028 counted, by an author with no reason to know the rule
existed. **That, not the deferred sixth, is how this class grows.** A count in a prior ADR is a
snapshot of its moment, not a fact.

- **Form cannot separate an instruction from prose, and the first design proved it.** ``via
  `<helper>` `` (the issue's own subject) and ``do not call `<helper>` `` are byte-identical in
  shape, so a "prose is a bare code span" rule classifies the defect as compliant — a guard going
  green against the thing it was commissioned for. The working discriminator was **measured**: the
  word immediately preceding each bare occurrence separates cleanly where the shape does not
  (prose is preceded by `—`, `(`, `in`, `the`, `to`, or start-of-line; the real call sites by
  `via`/`call`). Widening the verb set beyond the two observed adds **zero** false positives on the
  real corpus, so the extra entries are free coverage rather than a guess.
- **The checker sits outside every deployment path, deliberately.**
  `staging/plugin/scripts/tests/path-rule-check.sh` is outside `pairs-completeness.test.sh`'s
  non-recursive `plugin/scripts/*.sh` population and does not end in `.test.sh` — no `PAIRS` entry,
  no `docs-ci.yml` append, no `.claude/test-cmd` change, and therefore **no "inert until sync"
  dependency**, the class that has bitten six recent ADRs. Its assertions extend ADR-0028's own
  harness, already in CI's named list, so ADR-0113's CI-dark gap cannot reopen here.
- **Rule 12 bites at two levels once a guard has a declared waiver.** The documentation of the rule
  must not spell a real subject in a violating shape (it becomes a finding), and must not spell the
  waiver marker's literal opening (it becomes a malformed waiver). Placeholders for the first,
  naming-without-delimiters for the second.
- **Instance 11 of the derived-guard pattern, not extracted** (ADR-0086's criterion: its own
  population, its own question). The numbering had **already collided** — instance 10 is claimed
  twice and instance 7 carries no marker at all — so derive the next free number from the files,
  never from a brief.

Known consequences, recorded rather than fixed:
- The verb set is a judgement encoded as data. A call site using an invocation verb outside it is
  invisible; the honest reading of a green run is *"no recognised invocation shape is bare"*.
- The comment-line exemption skips any line whose first non-blank character is `#`, markdown
  headings included. Harmless today, a hole if a heading ever names a helper.
- The guard reads `concept-to-code/SKILL.md` only. `autopilot-build`, `project-conductor`,
  `nightly-autopilot`, `commit` and `deep-refactor` carry **24** bare occurrences between them and
  are out of scope by design — a decision, not a cleanup. The checker takes the file as an argument
  so a later issue can point it there without editing it.
- The checker verifies a **shape**, never that an instruction is correct: an absolute path naming a
  helper that does not exist passes.
- ADR-0028's body is not edited (ADR-0034 precedent); its §2.4 deferral was accurate for its moment.

Detail: `docs/architecture/ADR-0117-286-path-rule-bare-mentions.md`.

## Decisions from the RTF gitignore glob chain (ADR-0118)

Closes issue #287. `triage-state.sh commit` appends `${pref}.triage-fix-last-*.json` only when
`git check-ignore` says the state file is not already covered (ADR-0094). The issue asked whether
that glob and this repository's own `.gitignore` entry, differing "by a dash", cover the same set.

- **The premise was wrong in the direction that matters: there are TWO entries, not one.** Line 7
  (`.claude/.triage-fix-last*.json`) has been present since the initial commit `ac207d5`; line 36
  (`.claude/.triage-fix-last-*.json`) was added by `a482dbb` (PR #251) when the #222 chain
  dogfooded RTF on its own branch and a human swapped a dead per-branch line for the script's
  canonical glob **without checking that line 7 already covered it**. The mechanism was never at
  fault; a human reintroduced the exact redundant form `triage-state.sh`'s own comment warns about.
- **`git check-ignore -v` reports the LAST matching line, not every match**, so the obvious probe
  proves less than it appears to. What proves the coverage relation is the second probe: line 7's
  bare `*` matches a `triage-fix-last`-prefixed name with **no dash**, which line 36 structurally
  cannot — line 7 is a strict **superset**, not merely a similar rule. Corroborated by an assertion
  that already passes: `T5` seeds line 7's literal form alone in a fresh fixture repo, runs a real
  `triage-state.sh commit`, and the append is suppressed.
- **Line 7 survives, line 36 is deleted — chosen for coverage, not for symmetry with the script.**
  Removing line 7 instead would read textually identical to the glob the script writes and would
  silently drop protection for the vestigial flat name `.triage-fix-last.json`, which
  `vibe-status/scripts/aggregate.sh` and the legacy `review-triage-fix/tests/run-tests.sh` still
  reference. Symmetry is cosmetic; superset coverage with no collateral narrowing is not. A comment
  above the survivor exists so the next "chore" commit does not reintroduce the narrower form.
- **`triage-state.sh` is byte-untouched.** ADR-0094's per-branch design is out of scope and was
  never the defect, and `T2`/`T3`/`T8` pin the dash-glob as the script's output on a *fresh* repo —
  a property line 7's presence or absence does not affect.
- **The new fixture's seed is chosen against the failure mode, and the naive choice reproduces
  ADR-0094's own dead draft one level up.** Replaying this repository's exact historical two-line
  pair would pass under a `check-ignore`-disabled implementation too, because the literal-grep
  fallback recognises the glob string verbatim regardless of whether `check-ignore` ran. Found by
  tracing control flow, not by a live run: the architect's command scope (ADR-0042/ADR-0045)
  forbids creating a scratch git repository, so **running the plant and observing both directions
  is an explicit coder task**, not an architect claim.

Known consequences, recorded rather than fixed:
- The `.gitignore` entry still does not read textually identical to the script's glob. The
  difference is resolved in **coverage**, not in **text**, and the comment at the survivor is the
  only thing stopping a future reader from "fixing" that mismatch back into a duplicate.
- The two live-content assertions against the real committed `.gitignore` carry **no declared
  plant**. `plant-check.sh`'s sandbox copies only `staging/` and `docs/` (plus ADR-0116's
  `../docs/` hatch), so a repo-root file is unreachable; widening that registry for one feature's
  two byte-content checks was judged disproportionate. Follows `T12`'s existing precedent in the
  same file — disclosed, not silently skipped.
- **The architect's command scope blocks `git init` inside heredoc CONTENT**, because
  `agent-command-scope.sh` matches the full command string including text being written to a file.
  Inert data for a later script reads as a command. Recorded because it bounds what an architect
  can verify empirically, and hands live differential verification to the coder by construction.

Detail: `docs/architecture/ADR-0118-287-rtf-gitignore-glob-resolution.md`.

## Decisions from the transition-pair count chain (ADR-0120)

Closes issue #289. The legal transition-pair total was stated as a literal in nine places and
derived in three — and the issue's own title said "derived in one". Every number below was measured
before anything was designed; **three of the SPEC's premises did not reproduce.**

- **The count is 45**, confirmed five ways including **live execution of the pair block into a real
  file** rather than by grep alone (standard 25 / express 6 / hybrid 14). It counts distinct pairs
  emitted into `$PAIRS`; producer exemptions are outside it (they are comment declarations, and
  there are currently zero) and so is the unconditional `any → failed|aborted` wildcard, which
  short-circuits before `$PAIRS` is built.
- **Three derivations existed and they disagree — in two opposite directions.** Measured by mutating
  the source rather than by reading: `GR3` dedups but does not bound to the block, so a pair-shaped
  `echo` elsewhere in the file inflates it; `E7` bounds but does not dedup, so a duplicated line
  inflates it AND a renamed block marker silently returns **0**; `tracer-bullet-probe.test.sh`'s
  `ACTUAL_PAIRS` is wrong on both counts. All three agree on the unmutated input, which is worth
  nothing. **The operative semantics is `grep -Fxq`, so the correct rule is block-bounded AND
  distinct — which is none of the three.**
- **ADR-0086 and ADR-0069 are the same criterion read in two directions**, and this is the case that
  makes it legible: extract when copies answer the SAME question (three answers to one question is a
  defect), keep copies when they answer DIFFERENT questions. Decide by asking what each copy is a
  predicate *of*, never by counting copies. `transition-pair-count.sh` is the shared checker.
- **The checker sits outside every deployment path, deliberately.**
  `staging/plugin/scripts/tests/<name>.sh` with no `.test.sh` suffix is outside
  `pairs-completeness.test.sh`'s non-recursive `plugin/scripts/*.sh` population and outside
  `.claude/test-cmd`'s glob — so no `PAIRS` entry and **no inert-until-sync failure mode**, the
  class that has bitten six recent ADRs. Precedent: `path-rule-check.sh` (ADR-0117).
- **`TBP1` must not be converted to an equality.** ADR-0105 changed it in kind on purpose: a total
  is never evidence about a specific pair. Consolidating it back would reverse an Accepted decision.

Known consequences, recorded rather than fixed:
- The extractor couples to a shell idiom — rewriting the pair block as a heredoc or an array makes
  the derivation exit 3. Loud, but the block boundary strings become anchors in a file nobody
  previously treated as anchored.
- A fourth derivation written tomorrow passes every assertion, because the harness structurally
  cannot see one that is correct today. A grep checkpoint in the plan is the only guard.
- **Two live defects were found that a test was holding in place**, and both are in scope for that
  reason: `SKILL.md` contradicts itself nine lines apart (header `25 standard` against a bullet
  reading `28 + 1 = 29`) with `E5` pinning the stale bullet, and `E2`/`E3` carry messages naming the
  stale 49 while grepping 45 — so a **passing** `E3` prints the wrong number. **When you change a
  literal in an assertion, grep the message strings in the same edit**: the message is not covered
  by the assertion it belongs to.
- **Re-derive an assertion ID list from the file, never from a brief.** The SPEC named `GR4`/`GR5`
  as count assertions; they are `GR3b`/`GR3c`, and `GR4`/`GR5` are about entirely different
  subjects. It also missed a whole file and did not know R-02 was already two-thirds satisfied by
  `TBP2`/`TBP3`.

Detail: `docs/architecture/ADR-0120-289-transition-pair-count.md`.

## Decisions from the plan-shape predicate chain (ADR-0121)

Closes issue #290. Asks whether a real plan shape is recognised by no task predicate. **Measured on
the 61-file corpus, and three of the issue's premises did not reproduce.**

- **`### Step 0 —` is not a further plan.** It is the first heading *inside*
  `2026-06-06-claude-md-slim.md`, the file `PTE2` already exempts — its headings run `### Step 0`
  through `### Step 7`. The recurring "three shapes / two further plans" claim conflates one file's
  heading run with a second file.
- **Exactly ONE plan matches neither predicate**, and the second zero-opener plan
  (`2026-05-30-deep-refactor-skill.md`) is matched 36 times by `is_task_line` — it is not
  unrecognised, it simply has no `Task N` opener. The exemption list of two files is correct as it
  stands; only the prose describing it was wrong.
- **The real gap is a stale-waiver one, and R-01 was already satisfied literally.** `PTE3`, `PTG10`
  and `BO5b` assert the exempted **file exists**. The exemption's subject is *the file being
  unrecognised*. Reword that plan to `### Task N` and both assertions stay green while the waiver
  covers nothing — the ADR-0081 `ZA4` direction, which the issue cites and does not itself apply.
  Three vacuity assertions are added beside the existence checks, deliberately separate: "file
  gone" and "exemption no longer needed" want different remedies.
- **Widening is rejected on measured cost, not on inherited reasoning.** Making `is_task_opener`
  accept `Step N` changes **22 of 61** plans and **20 of those are collateral**: they use
  `- [ ] **Step N:` as sub-steps *inside* a task, so opener counts rise to equal the line counts
  (26→87, 11→67) and the predicate's stated purpose inverts. Widening `is_task_line` is cheap on
  the guard axis but feeds 15 new lines into `spec-coverage.sh`'s token extraction — none carrying
  an `R-NN` today, so latent rather than zero, in a merge-blocking gate. ADR-0069 §D6's refusal
  survives re-measurement and now carries the numbers it was originally asserted without.

Known consequences, recorded rather than fixed:
- **A registry-wide defect was found and is NOT fixed here: `plant-check.sh` decides a plant fired
  with `grep -q "^FAIL: $aid"`, a PREFIX match.** So `SP5`'s plant is satisfied by `SP5b` failing,
  `TC1`'s by `TC10`, `G1`'s by `G1b` — **41 of 148 declared plants sit on such a collision**. It is
  the fourth boundary of that registry after `PC4` and the `../docs/` hatch. Fixing it means
  re-verifying 148 plants and probably exposing a second red population, so it needs its own issue.
  This feature adds none: its new ids were chosen to avoid prefix collisions and verified both ways.
- The committed 61-row corpus baseline decays. A plan added after 2026-08-03 is outside it, and the
  count guard catches a baseline that stopped *resolving*, not one that merely aged. The first
  forgotten regeneration will read as a regression.
- The three vacuity assertions pass on day one, so their only evidence is the declared plant.
  Inspect what each plant actually produced (ADR-0090), never the word "fired".
- **The architect's command scope blocks `sed -i` and `rm -rf`**, so a differential simulation over
  a mutated corpus copy cannot be run at design time and must be handed to the coder as a declared
  plant. Same boundary ADR-0118 recorded.

Detail: `docs/architecture/ADR-0121-290-plan-shape-predicate.md`.

## Decisions from the bold-wrapped requirement id chain (ADR-0122)

Closes issue #291, the unclosed half of ADR-0072 §D4. **Four of the SPEC's premises did not
reproduce**, and one of them changes what the feature is for.

- **The corpus is 68 SPECs, not 36, and the harness is 73 files, not 68.** PR #317 (`4cacc76`) took
  `docs/specs/` from 36 to 67 in a single commit. Counts in a SPEC rot fast here — re-derive both
  before citing either.
- **Zero of the 68 SPECs carry a bold id in declaration position.** The three `**R-01**` occurrences
  are all inside backticks in prose. **The defect is hypothetical on today's corpus, not live** —
  which also means a green corpus sweep proves the change is a no-op and never that it works. Every
  bold assertion rests on fixtures; ADR-0092's derive-from-the-corpus technique does not apply.
- **The issue's "silence" claim is conditional.** Silent only when the plan cites nothing; with a
  citing plan the checker returns `rc=3 ORPHAN R-01` — noisy and misleading rather than quiet. The
  genuinely damaging shape is the **mixed** SPEC, which the issue's own edge-case section predicted:
  one plain id and one bold, plan citing the plain one, and the bold id vanishes with `rc=0` and a
  passing gate.
- **Bold reads as DECLARED, not `MALFORMED`.** The id *is* declared; the decoration is cosmetic. The
  supporting argument is this repository's own history: *a clause is the same clause whether it
  wraps, is backticked, is bolded, or is capitalised* — learned seven times about its own assertions
  (ADR-0073, ADR-0076, ADR-0080, ADR-0082, ADR-0098, ADR-0101) and never once applied to the parser
  it ships.
- **One shared `strip_emphasis()` in `spec-id-predicate.awk`, called by reader and writer**, which
  preserves ADR-0072 §D4's invariant *by construction*. **The exclusion was never about bold being
  unrepairable — it was about the checker being unable to read the repaired line.** Fix the reader
  and the exclusion's own reason evaporates. §D4's invariant is bidirectional and had been read as
  one-way.
- **`spec-coverage.sh` has THREE token-extraction sites, not one**, found by prototyping rather than
  reading. Patching two produced the worst reachable state: the repairer rewrites a bold plain
  bullet while the checker stays silent about it. Site 2 also carries an unguarded `match()` that
  writes an empty token on failure.
- **`RN12` inverts and is changed in kind** on the same fixture: from *"the disclosed limit is
  pinned"* to *"the round trip holds for the bold plain-bullet form"*.

Known consequences, recorded rather than fixed:
- **Task order is load-bearing.** Widening the near-miss predicate before the checker leaves a
  window that is ADR-0072 §D4's failure exactly. Do not commit between those two tasks.
- **`declared as plain bullets` is a three-way cross-file contract** — produced by
  `spec-coverage.sh`, consumed by `concept-to-code/SKILL.md`'s Step 5 auto-repair trigger, asserted
  by `RN3`. Rewording it disables the repair silently.
- **`plant-check.sh` copies only `staging/` and `docs/`**, so any assertion reading
  `.github/workflows/` fails in every plant sandbox and passes on the real tree. `RG1` is the known
  instance; do not chase it.
- **`BB2b`'s absolute ceiling fired for the THIRD time in one session**, on the third consecutive
  healthy feature (5→6→7→8). Its own comment already records the previous two as evidence against
  the absolute bound. A proportional bound needs its own issue rather than a fourth hand-edit.

Detail: `docs/architecture/ADR-0122-291-bold-wrapped-requirement-id.md`.

## Decisions from the SP5 frozen-baseline chain (ADR-0124)

Closes issue #346. `SP5` guarded ADR-0075's rule with a **count** against a hand-maintained floor,
and a floor absorbs its own plant whenever the corpus carries slack — `plant-check.sh` removes one
slot pointer, and if the slack is ≥ 1 the assertion still passes and pins nothing.

- **The issue names one source of slack; measuring found two, and the second is the one that
  matters here.** Corpus of 48: 46 `completed` (41 at the slot, 5 repointed), 2 `aborted` (1 at the
  slot). Source 1 is a chain in flight holding a filled pointer (`+1`, transient) — the issue's
  subject, closed by its proposed remedy. Source 2 is a chain that **aborts**, which keeps its slot
  pointer for good because Step 7.0b runs on completion only (`+1`, **permanent**). Not
  hypothetical: #288 is already one instance, and it is exactly the `+1` that forced the hand bump
  `HIST_FLOOR` 41 → 42 the day before. **A nightly run that halts mid-feature produces an aborted
  chain**, so the issue's own remedy would be re-broken by the first interrupted night — the very
  scenario the guard exists to make readable.
- **So the count goes, not the floor's value.** `SP5` now checks a frozen baseline of 42 basenames:
  each file must still exist and still point at the slot. A property no count can express, and one
  that corpus growth, in-flight chains and aborted chains leave untouched **by construction**.
  Nothing is bumped by hand again. **A new entry is never required** — a completing chain repoints
  to its own archive and never joins the set; an aborting one is not a record the baseline was
  frozen to protect.
- **It retires a disclosure as well as a mechanism.** The file had already recorded that a floor
  "is masked by concurrency: a historical manifest rewritten WHILE another chain sits at the slot
  leaves `SLOT` unchanged". A per-manifest check cannot be masked, because it never looks at a
  total.
- **`Z1`'s floor raised 13 → 16 in the same edit**, and this is the part worth remembering: left at
  13 it would have carried three units of slack and three assertions could have vanished while it
  stayed green. **The exact defect being removed from `SP5`, reintroduced in the same file by the
  change that removes it.** ADR-0120's RH2 lesson, met while fixing its sibling.
- **The freeze precondition is verified, not assumed:** zero chains in flight at generation time,
  reading both terminality axes (ADR-0113). An in-flight manifest frozen in would legitimately fail
  at its own Step 7.0b. The re-derivation one-liner is in the file so a reader can diff, not trust.

Known consequences: the baseline is a snapshot, so a legitimately deleted manifest reddens `SP5`
(correct under ADR-0075, and it will read as a regression the first time); **`SP8` carries no
plant** because it is a negative assertion and deleting a mechanism cannot break "X must not
happen" (ADR-0112) — the mutation would be a structural loop rewrite, not registry v1's one-line
replacement (#305), and `SP8b` plants the same function in the positive direction; `SP5`'s plant is
still subject to #355's prefix match, verified to redden none of `SP5b`/`SP5c`/`SP5d` on this
corpus, which is what makes attribution hold today rather than in general.

Detail: `docs/architecture/ADR-0124-346-spec-pointer-baseline.md`.

## Decisions from the value-domain guard chain (ADR-0125)

Closes issue #292. ADR-0092 built a derived guard comparing the WRITTEN value set against the
DOCUMENTED one, in both directions, and scoped it to `step5_mode` alone — leaving `hook_verified`
and `step5_review_mode` named in the same helper sentence and checked by nothing. **Five of the
SPEC's premises did not reproduce; two changed the design.**

- **Neither field has a phantom today, and saying so is the point.** Measured: `hook_verified`
  writes `true`/`false` (45 `false`, 4 `true`, 0 absent across 49 manifests); `step5_review_mode`
  writes `none`/`checkpoint`. Both directions clean on both fields. **This is ADR-0107's shape, not
  ADR-0092's** — the property holds and nothing checks it. A reader expecting a #240 repeat will
  hunt for one and find nothing; the answer is that a correct property with no check is one edit
  from an incorrect property with no check, and the last time that combination was left alone the
  wrong string stood for months.
- **`checkpoint` is written by no manifest in the corpus and that is NOT the #240 shape.** #240 was
  a value no *producer* writes; `checkpoint` has a producer and has simply never been opted into.
  The reverse check compares documented against **produced**, never against the corpus — that
  distinction is what keeps an unexercised opt-in from reading as a phantom.
- **Live defect 1: `hook_verified`'s documented domain is a TYPE, not a value set.** The header says
  *"a boolean"*, and ADR-0092's own derivation run against it yields the single token `a` — R-01 is
  unsatisfiable until the header enumerates. The ambiguity is reachable, not theoretical:
  `yaml.safe_load` is YAML 1.1, so `hook_verified: yes` reads `PRESENT|True` and **both** call
  sites accept it, while `manifest-set-flag.sh` — the only writer — structurally refuses anything
  but the literals. "A boolean" names a set strictly wider than any producer can write, in the one
  place ADR-0076 §D2 tells the next checker author to copy.
- **Live defect 2: the existing flatten does not survive the wrap the SPEC assumes it does.** Re-flow
  the sentence so a value list splits *inside* itself and the derivation returns `none|` — the set
  `{none}`, `checkpoint` silently dropped. Today's header wraps *between* `is` and its list, which
  the flatten does survive; the untested case is the one a routine re-flow produces. Fixed by a
  pipe-collapse `sed` clause, verified on three wrap shapes; `step5_mode` inherits it.
- **Per-field extractors, one shared derivation, one shared comparison — ADR-0086's criterion
  applied in BOTH directions inside one file.** The shared idiom is not merely inelegant on
  `hook_verified`: measured, it yields four English-word phantoms (`field`, `manifest`, `the`,
  `value`) lifted out of operator-facing error messages that use a colon, so the guard would fail on
  a correct tree on its first run. The obvious alternative `hook_verified=<word>` is worse — it adds
  `unchanged`, `hook-verify-workflow.sh`'s token meaning *do not write this field at all*. **Rule 12
  one level up:** not an assertion whose needle matches the prose explaining it, but a *derivation*
  whose needle matches the prose explaining the field.
- **Each field's enforcer is pinned, because that is what makes a narrow extractor trustworthy.**
  `manifest-set-flag.sh` validates `true|false` and exits 1 otherwise — enforced by code, and
  **asserted nowhere across all 73 harness files** until now. `manifest-validate.sh` invariant 14 is
  the symmetric enforcer for `step5_review_mode`: its behaviour is covered, its *agreement with the
  documented domain* was not, which is #240's shape with a different pair of files.
- **The extractor stays permissive on purpose.** `checkpoint`'s only real producer is a `sed`
  command inside a comment at `manifest-init.sh:134`, and `concept-to-code/SKILL.md` names the value
  twice in prose — so a permissive extractor keeps reporting it even if the producer were deleted.
  Narrowing to `scripts/*.sh` would fix that and go blind to a future genuine SKILL.md producer. The
  real producer is pinned separately instead.
- **No waiver mechanism, asserted behaviourally rather than stated.** A value domain with an
  exemption is not a domain (ADR-0092's rule, carried forward).

Known consequences, recorded rather than fixed:
- `V0b`/`V1`/`V2` are re-implemented onto shared functions. Ids and `ok`-line text are preserved
  byte-for-byte, but **ADR-0092's assertions stop being the code ADR-0092 describes**.
- Three different extractor shapes now live in one file, held apart by comments and a comparison
  that goes red when they are conflated. A tidying pass is the plausible failure mode.
- **`CLAUDE.md`'s restatement of the domain is corrected by hand and checked by nothing** —
  `plant-check.sh` copies only `staging/` and `docs/`, so a repo-root assertion is unplantable
  (ADR-0122's class). That is #240's exact drift route, left open and recorded rather than
  half-closed.
- The corpus is 49 manifests and the harness 73 files, not the 41 and 68 the SPEC states. Re-derive
  both before citing either.

Detail: `docs/architecture/ADR-0125-292-value-domain-guard-two-fields.md`.

## Decisions from the autopilot scope-and-bound chain (ADR-0129)

Closes issue #365, Phase 11 Wave 1. `autopilot` took **no arguments**, so a launch attempted every
unchecked row of `PROJECT.md` — 33 of them — and the only brakes were the `/goal` turn budget and a
human hand. It gains `--features N`, `--only <token>`, `--dry-run`, and an optional durable `scope:`
block in `.claude/autopilot.yml`.

- **`token-budget` is REMOVED, not wired, and the reason that settles it is structural.** Two
  findings look like implementation gaps: the producer ADR-0127 Part 4 proposed reads
  `step5-report.json`'s `task_metrics`, whose four ADR-0064 fields carry **no token count**, and no
  real report has that block at all — `agent-metrics.test.sh` GA1/GA2 assert the field name in the
  **schema inside SKILL.md**, a green schema over an empty report. The third decides:
  `autopilot-guard.sh` is a `PreToolUse` hook on the publish, so a ceiling evaluated afterwards
  **cannot stop the feature that breached it, only the one after** — which is cumulative drift, what
  `--features N` already bounds. **Accepted cost, stated rather than discovered: there is no spend
  ceiling.** If one is ever wanted it starts at the transcript (`usage-report.py`,
  `context-occupancy.sh`), is per-session not per-feature, and still cannot stop a feature in flight.
- **`rtf-blocker` keeps its mechanism and the verdict is NOT transferred** (§D6, stated in terms so
  the next reader does not tidy it away for consistency). That halt would work the moment something
  wrote it; `token-budget`'s could not. Its corrected sentence carries a **measured** reason rather
  than a deferral: `concept-to-code` Gate 5's autopilot default is "Skip review" and
  `project-conductor` invokes `concept-to-code` on **both** branches, never `autopilot-build` — so
  **no review cycle runs during an unattended roadmap run at all**, and a producer inside
  `review-triage-fix` could never fire where the guard that reads the file exists. That larger gap
  is recorded in Phase 11, not fixed here.
- **A slot is consumed by a PUBLISH, and `delivered` is the line count of the existing `published`
  ledger** (§D4) — one writer, one append per successful publish, already run-scoped and already
  cleared by the same disarm. A second counter would be a second producer of one fact with a crash
  window between them. Read with the guard's own idiom, never `grep -c … || echo 0`, which yields a
  two-line `0\n0` (issue #174).
- **Running out of slots leaves the roadmap untouched, superseding ADR-0127 §D7 IN PART** (§D5).
  §D7 said the run marks the next feature `[~]`; measured, `project-conductor` Step 2 selects the
  first `- [ ]` line, so **`[~]` is permanent** and every bounded run would quietly delete a feature
  from the roadmap. The other half of §D7 stands: never write `needs-human`. The clause was correct
  for a *token* bound, which can be reached mid-feature; a feature count is checked between
  features, so there is nothing to skip. ADR-0042's precedent — one clause, named, rest standing.
- **The scope travels as a file, `<root>/.claude/autopilot-state/scope`,** on the exact terms
  `published` already established, and it **stores the roadmap line text, never a re-derived slug**
  (§D2): the conductor derives a topic-slug in four places and a fifth derivation is ADR-0069's
  defect. `--only`'s slug form is **match-only**, so a disagreement produces a loud unresolved-token
  abort, never a silently wrong selection. An argument discards the marker's `scope:` block **whole**
  — per-key override lets a stale `only:` survive a `--features` that meant something else.
- **`--only` resolves an issue number first** (`--only 293,294`), a full topic-slug second; a token
  that resolves as neither **aborts in Phase 0**, before anything is written. The number is already
  on the roadmap line and is the same source ADR-0128 just made authoritative for `Closes #N`.

Known consequences, recorded rather than fixed: the stale scope file is **ADR-0112's class**,
mitigated only by the disarm clearing it, exactly as `published` is; three test assertions are
deleted and `weakening-scan.sh` will flag the diff, which no rule over a diff can distinguish from a
relaxation (ADR-0073); `autopilot-guard-disarm.test.sh` `D2` counts `>= 6` cleared files, so
removing `token-budget` without adding `scope` **in the same change** turns it red; Phase 0 gains a
ninth check, so ADR-0110's own sentence stops carrying a count and `permission-mode-state.test.sh`
PMP2 is re-anchored count-free.

Detail: `docs/architecture/ADR-0129-365-scope-and-bound-the-autopilot-run.md`.

## Decisions from the plan-tasks mode-binding chain (ADR-0131)

Closes issue #294. `plan-tasks.sh` has two modes with **opposite failure directions** — `--count`
over-counts (safe for a `>= 1` guard, wrong for arithmetic), `--count-openers` can legitimately
return 0 (safe for arithmetic that tests zero, wrong for a guard) — and the only thing stopping a
caller from picking the wrong one was a sentence in the script header. ADR-0100 is the proof that
is not enough: it fixed exactly that defect at one call site.

- **Three invocations, not two, and the SPEC's own premise did not reproduce.** `--count` and
  `--count-openers` sit in the **same** `concept-to-code-step5-plan-structure` fence, plus `--count`
  in `autopilot-build-check-5`. The batch-dispatch policy the SPEC calls a call site **invokes
  nothing** — it consumes `$openers` ~900 lines away. That killed the per-fence declaration design
  outright, before it was written.
- **The marker names the QUESTION, never the mode**, as a trailing comment on the invocation line:
  `# plan-tasks-question: guard`. Repeating the mode would add a field that can drift from the flag
  two words to its left. Naming only the question catches a changed flag, a changed marker, a new
  unmarked invocation and a copied call site — with less to go stale. Trailing rather than
  preceding, because the two c2c invocations are two lines apart with an `rc=$?` between them and a
  preceding marker for the second would read as belonging to neither.
- **The mode → question binding is EXTRACTED; the guard machinery is NOT** — ADR-0086's criterion
  applied in both directions in one feature. Two answers to "which question is `--count` for" is a
  defect by definition, so it lives in `plan-tasks.sh` as `# mode-contract:` lines and is loaded,
  never restated. The population derivation, marker syntax and count guards are instance **13** of
  the derived-guard pattern and stay a copy: a shared source failing would disable thirteen guards
  at once, in the stay-green way this repository has watched three times.
- **`mode-binding-check.sh` is a CHECKER placed where it cannot deploy** —
  `staging/plugin/scripts/tests/`, no `.test.sh` suffix, so it is outside `.claude/test-cmd`'s glob,
  outside `docs-ci.yml`'s explicit named list, and outside `pairs-completeness.test.sh`'s
  **non-recursive** `plugin/scripts/*.sh` population. No `PAIRS` entry, **no inert-until-sync failure
  mode** — the class that has bitten six recent ADRs. Precedents: `path-rule-check.sh` (ADR-0117),
  `transition-pair-count.sh` (ADR-0120). Exit 3 means DID NOT RUN and is never collapsed into a
  zero; it prints no `CLEAN` sentinel and must never grow one.
- **R-02 is per-call-site and EXACT, not a floor**, because ADR-0124's lesson is that **a floor
  absorbs its own plant**: with `>= 1`, removing one invocation still passes and the assertion pins
  nothing. The checker's own `invocations >= 3` denominator guard stays a floor and is *only* a
  vacuity guard; the division of labour is stated at both sites so nobody later consolidates one
  into the other.
- **The bound variable is asserted, and deliberately not as "that paragraph must not contain
  `$tasks`"** — it legitimately contains `$tasks` twice while explaining why not to use it, so such
  an assertion fails on correct text. Rule 12, for the seventh recorded time.

Known consequences, recorded rather than fixed:
- **The marker declares intent and nothing verifies it is honest.** A site declaring `guard` and
  feeding the number to arithmetic passes. A green run must never be read as closing #242's
  semantic class.
- `--count` is a strict **prefix** of `--count-openers`, so substring matching silently attributes
  the second invocation to the guard mode and reports agreement. Only the declared plant makes that
  visible.
- **Two live harness defects found on the way, both the same shape:** `plan-task-count.test.sh`
  `Z1` tests `>= 48` while both its messages say "floor 43"; `batch-dispatch-openers.test.sh` tests
  `>= 16` and says "floor 13". A *passing* assertion prints the wrong number — grep the message
  strings whenever a literal in an assertion changes.
- The derived-guard instance numbering has collided a **second** time: instance 12 is claimed by
  both ADR-0119 and ADR-0125 (ADR-0117 recorded the first, at 10). Re-derive the next free number
  from the files, never from a brief.
- `--count`'s new exit-3 assertion passes the day it is written (the script's exit-3 branch is
  shared), so it is a **forward guard, not fix evidence**, and its plant is the only thing making
  it mean anything.

Detail: `docs/architecture/ADR-0131-294-plan-tasks-mode-binding.md`.

## Decisions from the skill-argument substitution chain (ADR-0132)

Closes issue #385, Phase 12 Wave 1 — the P0 the first bounded `autopilot` run exposed. **When a
skill is invoked with arguments, Claude Code whitespace-splits the argument list and substitutes it
into every `$<digit>` token in the skill's own markdown body, 0-indexed, before the body reaches the
model.** A bash fence is text, so it is rewritten too: `autopilot` invoked with
`--features 1 --only 294` holds a `case` over its first positional parameter on disk and renders
`case "1" in`. Measured three times independently in one run (audit §F1), **build-stamped to CC
2.1.226**.

**THE RULE — a bash fence in a `SKILL.md` must contain no positional-parameter token; logic that
needs one lives in a `skills/<name>/scripts/` file, because a file is never rendered.** An awk field
reference is the same defect in different clothes: it moves too, or is rewritten field-free.

- **It outranks every other finding in that audit because ADR-0083's whole fence-contract mechanism
  rests on the rendered text being the executable text.** Here it was not, and the corruption is
  *silent* — syntactically valid shell that does the wrong thing. Three shipped fixes were being
  reintroduced at render time inside the very fences written to fix them (c2c Step 5.0.1's `rel()`
  reproduced ADR-0089's defect, both TOFU probes ADR-0102's), and `autopilot`'s own parser was
  corrupted, so ADR-0129's bound would not have parsed and the run would have gone unbounded across
  all 30 pending roadmap rows. **It survived only because the orchestrator read every fence from
  disk instead of executing the rendered text** — an ad-hoc workaround, not a designed mitigation.
- **Population re-measured rather than inherited: 30 staged `SKILL.md` files, 162 bash fences, 19
  occupied lines inside them, now 0.** Two counts in the design artifacts were wrong and both are
  corrected here rather than quietly reconciled. (1) The ADR's §Context table says **160** bash
  fences; the live figure is **162**, and it is not a parser artifact —
  `skill-fence-positional-tokens.test.sh` and `fence-contract-coverage.test.sh`'s independent,
  differently-written enumerator both report 162. (2) The plan's Task 2 heading says "the **eight**
  in-place rewrites" while its own sub-steps (3+2+1+1), its file list (7 line references) and its
  residual table (19 → 12) all describe **seven**; the eighth is `commit`'s, which the ADR's in-place
  table counts and the plan assigns to Task 7.
- **Four new scripts, excising the CASE and never the FENCE** (§D2): `scope-args-parse.sh`
  (`autopilot` Phase S), `conductor-args.sh` and `mark-roadmap-skipped.sh` (`project-conductor`
  Step 0, and the two `[~]` sites), `repo-rel-path.sh` (c2c Step 5.0.1). The three most affected
  fences are gates a human must read at the point of decision, so everything not needing a positional
  parameter stays in the document. Each new dependency fails **closed** in its own fence's exit
  vocabulary — an unresolved helper is *the check did not run*, never *the check found nothing*.
- **`commit`'s predicate is ELIMINATED, not relocated** (§D3), the one deliberate divergence from the
  SPEC's "they require external files". It had exactly one call site, so inlining its `grep -qE`
  deletes the token outright rather than moving it. A helper would have added a hard `~/.claude`
  dependency paid by `concept-to-code` Step 7, `project-init` and `autopilot-build`, whose
  unresolved-helper fallback could only be *no test files found* — the silent omission the H4 gate
  exists to prevent.
- **The guard partitions, it does not merely grep** (§D6). `skill-fence-positional-tokens.test.sh`
  splits every occurrence three ways — BASH fence / non-BASH fence / outside any fence — and asserts
  the buckets sum to the file-wide count. A denominator guard catches a glob that stopped resolving;
  only the sum identity catches a fence predicate that narrowed and now under-reports, which reads
  exactly like a clean corpus. `swiftui-pro`'s Swift line is not an exclusion-list entry — it is what
  keeps the non-BASH bucket non-empty, so the language filter is exercised by a real member.
- **The harness cannot see this defect and never will.** Every test reads a file; the model executes
  a *rendering* of that file. A green run says nothing about the failing quantity, so the guard is a
  **regression** guard on a property the harness can check, not evidence the defect is fixed. The
  only check that reads it is a live invocation compared byte-for-byte against the deployed file.

**Three findings from the run, one family: an assertion green while testing nothing.** `RJ14` never
exercised the guard it exists to protect — its inline fence invocation did not bind
`CLAUDE_PLUGIN_ROOT`, so resolution fell through to `$HOME/.claude`, the helper was absent, and the
assertion passed from the fall-through arm. **Any inline fence invocation in a test must bind
`CLAUDE_PLUGIN_ROOT`.** `CDA7` asserted a `DID-NOT-RUN` branch its own fixture could never reach,
because both resolution tiers resolved — **a fixture that cannot produce the state it names pins
nothing**. And two plant replacements collapsed a `printf … >&2` / `exit N` pair onto one line,
making the exit two more arguments to `printf`: no exit, plant silently inert (ADR-0112's lesson,
met twice more here).

Known consequences, recorded rather than fixed: four new hard `~/.claude` dependencies, each failing
closed, so those gates are **worse than inert until `staging/sync-to-claude.sh --apply`** — most
exposed is c2c Step 5.0.1, where an un-synced machine refuses *every* Step 5. `project-conductor`
Step 0's rendered behaviour changes because its rendered behaviour was wrong (`$@`/`$#` were the
executing shell's, empty, while its first token was filled by the substituter, so neither parse
worked). Prose occurrences are **reported, not gated** (§D8) — zero today, widening is a named
follow-up. The measurement is build-stamped: re-run the §Verification probe after a major CC bump
rather than trusting the date, though the fix is inert-safe either way since removing the tokens is
correct whether or not they are still substituted.

Detail: `docs/architecture/ADR-0132-385-skill-args-in-fences.md`.

## Decisions from the fence execution shell chain (ADR-0133)

Closes issue #394. A bash fence in a `SKILL.md` is executed by the **host shell** — zsh 5.9 on this
machine — while it was written and tested for bash. zsh does not word-split unquoted parameter
expansions, so `bash "$_sap" $_args` passes **one** argument where bash passes four, and `autopilot`
Phase S silently discarded `--features`/`--only`: a launch asking for one feature would have run
unbounded over all 28 pending roadmap rows.

**THE RULE — a bash fence in the declared population executes its body under `bash`, via a quoted
heredoc whose terminator sits at column 0, with an `export` prologue for its free variables. The
harness cannot observe this class at all: it runs extracted fences under bash, so a green suite says
nothing about the quantity that fails.**

- **Measured, not inherited: 162 bash fences, 32 contracts, 1 illustration, 129 unmarked; 14
  findings across 13 fences; population 32 ∪ 9 = 41.** ADR-0107 recorded 18 declarations and
  ADR-0132's Context table 160 fences — both were snapshots, neither is citable. Re-derive every
  time.
- **Four sites the issue's own scanner structurally could not see**, because it matched
  `for X in $VAR` and `set -- $VAR` only. One is `conductor-step0-args` — the **same fail-open shape
  as Phase S, in a second skill**; two more feed ADR-0048's merge-blocking coverage gate an
  unrecognised single argument. **A per-idiom guard inherits the blind spots of whoever enumerates
  the idioms**, which is exactly why the guard here is structural: if the wrapper is present the
  interpreter is bash and the question is closed regardless of the construct.
- **The defect predates ADR-0132.** The pre-#385 form `set -- $_args` fails identically, so the
  `--features` bound has **never** been applied on this machine, from ADR-0129's first run onward.
  Any earlier claim that a run was bounded must be read against that.
- **Failure directions differ, and only one is quiet.** Phase S fails **open**. `commit/SKILL.md`'s
  H4 test-diff gate (ADR-0061 §D1) fails **closed and wrongly**: its predicate receives one blob and
  classifies **every** changed file as a test file — observed live on 2026-08-08 and **misattributed
  at the time to an orchestrator scripting error**, which is how a real defect spent a day looking
  like a typo.
- **Every clause of the wrapper is earned by a probe, not by style.** An *indented* terminator
  swallows the rest of the script and **destroys the exit code silently**; the `export` prologue is
  required because 24 of the 32 contracts carry free variables that do not survive the new process
  boundary.
- **No declaration marker for the wrapper** — its presence in the body is the evidence. A marker
  would be a second source of truth that can disagree with the mechanism, the ADR-0042 shape.
- **`bash -n` is BLIND to a wrapped body**, measured: it accepts a wrapper whose body contains
  `if [ ; then`. So `F7` goes **vacuous the day the wrapper lands** — a check silently ceasing to
  check, on the day it is most needed. Repaired in the same change by parsing the inner body;
  `fence_body`'s dedent is fixed with it, since a column-0 terminator is otherwise unextractable.

Known consequences, recorded rather than fixed: **121 of 162 fences stay unwrapped by design**, and
that boundary is the thing most likely to be misread from a green run; `commit/SKILL.md` is invoked
on three unattended paths, so the first run after this reports differently and that difference is
the fix, not a regression; the CI job gains a `zsh` install for the executed proof.

Detail: `docs/architecture/ADR-0133-394-fence-execution-shell.md`.

## Decisions from the Phase P roadmap-state chain (ADR-0134)

Closes issue #399. `autopilot` Phase P step 3 decided which features need a generated SPEC by
reading one thing — whether `docs/specs/<slug>.spec.md` exists — so a completed feature whose SPEC
was never archived was indistinguishable from a pending one, and a run bounded to a single feature
still paid prep across the whole map. It now reads the two facts it already had: the row's state in
`PROJECT.md`, and the `--only` list Phase S parsed.

- **Four of the SPEC's own re-derived figures were wrong, and the count is the interesting one.**
  Issue #399 said 4 missing SPECs; the SPEC written for this chain said 3; **the truth is 4**, and
  the disagreement is a live defect: step 3's coverage predicate is the exact
  `docs/specs/<map-slug>.spec.md`, while `project-conductor/SKILL.md:574` globs
  `docs/specs/<issue>-*.spec.md` and takes `head -1`. Measuring "missing SPECs" with the glob gives
  a different number than the step actually uses. Disclosed, not fixed.
- **The state predicate is ROW-SHAPED and CAPTURES the marker character rather than enumerating it**
  (§D3). Measured: `PROJECT.md` carries `#### Wave N — … (issue #N)` headings beside its roadmap
  rows, so a file-wide `grep -F "(issue #N)"` returns two hits for `#365` and `#366` — two of the
  rows this feature exists to suppress. And capturing rather than restricting to `[ xX~]` is what
  keeps the *unrecognised state* branch REACHABLE: an enumerating regex sends `- [?]` to the
  *orphan* branch instead, and the branch the SPEC names becomes dead code. **A branch a
  specification names and no input can reach is worse than no branch — it reads as covered.**
- **The helper is a SELECTOR, a third contract beside this tree's checker and reporter** (§D2):
  stdout carries rows and nothing else, every note and the summary go to stderr, and exit 3 means
  the selection DID NOT RUN. It prints no `CLEAN` sentinel and must never grow one. The channel
  split diverges from the sibling `autopilot-scope-*` fences on purpose — their stdout is read by a
  human, this one is consumed as data, so a note on stdout would be a phantom row.
- **The denominator is EVERY map row, before any filtering** (§D5). Resolving state only for rows
  that survive `--only` and the coverage check would let an unrelated argument shrink the guard:
  `--only 294` would leave a single row as the entire denominator. A guard that can be reduced to
  n=1 is not a guard. ADR-0085's rule on a new population.
- **The helper never aborts on an unresolvable `--only` token** (§D6). Phase 0 check 9 stays the
  sole authority for that, and it resolves against `PROJECT.md` while the helper resolves against
  the map — two authorities answering one question from two populations is ADR-0086's defect. Note
  the phase order is **S → M → P → 0**: `--only` is *parsed* in Phase S and *resolved* in check 9,
  which runs AFTER Phase P, so a bad token costs one Phase P before the launch stops. Do not write
  "Phase S aborts it first".
- **ADR-0129 §D7's exclusion is lifted for this one step, and the distinction is written at the
  step** (§D7). §D7 keeps Phase S away from `PROJECT.md` because in auto-design the roadmap does not
  exist yet; step 3 runs after step 2 has generated it, so the reason does not extend. Stated at the
  site so a later reader does not "fix" the reference back.
- **This ships an instruction as well as an enforcement, and §D10 says which is which.** The helper
  and the fence are code; the per-row `Skill(skill="spec-from-issue", …)` invocation stays prose. A
  green harness does not mean the model issued exactly the printed calls — what changed is that the
  list is now computed with a stated contract instead of derived from a glob, so the failure shape
  moves from a silently wrong list to a list on screen a reader can compare against.

Known consequences, recorded rather than fixed: **Phase P is worse than inert until
`staging/sync-to-claude.sh --apply`** — an unresolved helper halts step 3 with no fallback (§D8),
because a fallback would restore the unbounded behaviour on the machine least likely to notice; a
green run on this repository proves the suppressing half only, since all four uncovered rows are
`[x]` and generation is exercised by fixtures alone; and check 9's own file-wide matcher means
`--only 365` and `--only 366` abort this repository's launches today, disclosed and unpinned.

Detail: `docs/architecture/ADR-0134-399-phase-p-roadmap-state.md`.

## Decisions from the terminal-transition ordering chain (ADR-0135)

Closes issue #410 — **and #357, which is the same defect filed eight days earlier and already a
roadmap row** (`PROJECT.md:1094`). That duplication is the first finding: a defect recorded with a
remedy and no mechanism gets re-filed, and the older issue carried the sharper measurement (5 of 57
manifests use a lowercase-`d` `/Users/stefer/developer/…`, which macOS resolves case-insensitively
and Linux CI does not).

`concept-to-code` Step 7 invoked `commit` and only afterwards transitioned the manifest to
`completed`, so the committed manifest was still `step_7_commit`/`in_progress` and the transition
that followed left an uncommitted change nothing ever commits. Under invariant 4 (ADR-0078,
ADR-0113) that manifest validates on the machine that produced it and fails everywhere else — green
locally, red on CI, which is why it survived until `shell-tests` became a required check.

- **The transition moves ahead of the `commit` invocation at all three commit-invoking steps**, and
  Step 7's new 7.0c must follow 7.0b's `artifacts.spec` repoint: `manifest-set-artifact.sh` has no
  terminal guard, so a repoint after the transition succeeds silently and lands outside the commit —
  the same defect one write over, in the step whose whole subject is that defect.
- **The invariant is phrased over WRITES, not over the numbered sub-steps** — *every manifest write
  in this step precedes the `commit` invocation, and this transition is the last of them*. A
  restatement of the step list ages the moment a sub-step is inserted, and inserting one is exactly
  how this returns. Verified rather than assumed: none of the post-commit actions writes the
  manifest.
- **The Standard and Hybrid transitions were PROSE, not commands** (`SKILL.md:2796`, `:2986`) — the
  PATH-RULE class ADR-0028 and ADR-0117 already fixed elsewhere in this file, and plausibly *why*
  the ordering drifted: there was no instruction to order. Only Express E4 had a real invocation,
  and it sat after the commit.
- **A declined commit now stops and reports.** Terminal states are absorbing, so there is no legal
  way back and no rollback pair is added — ADR-0078's invariant-4 exemption rests on that property.
  The check reads the **manifest**, never the skill: `commit` emits no machine-readable outcome, so
  one post-hoc fence asking *is the manifest terminal, tracked and clean* collapses the declined and
  nothing-to-commit cases without special-casing either.
- **The guard pairs by NEAREST PRECEDING MANIFEST WRITE, and the three obvious rules were each
  disqualified by measurement.** Proximity, adjacency in a two-kind stream, and regions bounded by
  successive commit invocations all **pass the pre-fix text** — because the anchors already alternate
  `T,C,T,C,T,C`. Introducing a third, broader anchor kind (any of the 61 lines naming a
  `manifest-*.sh` helper) is what restores discrimination, and it turns the guard into a direct
  statement of the invariant rather than a proxy for it. **When a guard must pair two file-wide
  anchors, check whether the anchor stream already alternates before choosing a rule.**
- **Anchored on the two mechanisms, never on headings** (ADR-0083 §D3: heading-anchored extractors
  went silently vacuous twice, one losing six assertions outright). A rename that breaks this guard
  is the same rename that breaks the thing it guards.
- **The Step 7 outcome fence is Standard-path only, and E4/H5 say so at the site.** On those paths
  the manifest is never committed at all, so applying it there would halt every Express and Hybrid
  run for a gap that is out of scope.

- **The one consumer that changes is `commit` Step 5.5, and #357 had asked exactly this.** Its
  `.claude/context.md` *"Open decisions"* line looks for a manifest at `status: in_progress`; after
  7.0c there is none, so it writes `none` rather than naming `step_7_commit`, and *"In progress"*
  derives from `completed`. Correct after the fact, skipped entirely in autopilot mode, and a real
  behaviour change. The other consumer, `commit` Step 2 item 3, reads topic and ADR path only.
  Measured, not assumed — which is the answer to #357's open question *"check whether any consumer
  reads `current_step` during Step 7"*.

Known consequences, recorded rather than fixed: **on Express and Hybrid the manifest is committed by
nothing, in any state** — filed as **#422**, since closing it is a design question with three
answers and bundling it here would make a bounded change unbounded; the legal-pair table, the shared
manifest helpers, Gate 4.0's in-flight commit and all 57 existing manifests are untouched; and the
corpus is green on invariant 4 today partly **by accident**, since the one tracked non-`completed`
manifest is exempt only through ADR-0113's second terminality axis, shipped nine days earlier.

Detail: `docs/architecture/ADR-0135-410-completed-transition-before-commit.md`.

## Decisions from the stop-gate trigger granularity chain (ADR-0137)

Closes issue #404. `mark-dirty.sh` armed the gate on every `Edit`/`Write` and threw the path away,
so editing a markdown file armed a shell test suite; `stop-gate.sh` then ran the whole suite under a
120 s ceiling.

**Three premises were measured and two did not survive, which is the second time in one day.**
`stop-gate.sh` is **not registered** in the deployed `~/.claude/settings.json` — one `Stop` hook,
`chat-done-notify.sh` — while `staging/user/settings.json` registers it and nothing else. Neither
file is a superset of the other, so #309's drift runs in both directions. `mark-dirty.sh` is
registered in both and keeps writing: 71 `.dirty` markers had accumulated since 20 June, none ever
removed, because they are removed only on a green run and no run had occurred. The suite measures
**2m43s here**, not the 15m37s the issue quotes from a GitHub runner, so a raised ceiling is a real
option rather than a theoretical one. And the commits the issue cites as wasted firings —
`PROJECT.md`, `TODO.md`, an ADR, a manifest — touch files this suite genuinely asserts over, so
arming on them was correct and the predicate's yield here is low by measurement.

- **Two defects sit behind one issue, and the ceiling is only one of them.** On timeout the hook
  exits fail-open, removes the output file and leaves the marker armed, and the anti-loop counter is
  incremented only inside `emit_block`, which a timeout never reaches — so a timing-out suite
  re-charges its full ceiling every turn, forever, uncounted. A ceiling shipped without the counter
  moves the defect to a rarer trigger instead of fixing it.
- **The harness proposes, the hook decides.** The subject check needs the hook's exact glob
  semantics, and extraction is declined with a stated reason: a sourced helper would give a globally
  registered guardrail hook a runtime dependency whose absence after a partial sync fails open. A
  cheap prefilter proposes one candidate per pattern and the real hook confirms it against a
  fixture; over-proposal is rejected by the confirmation, under-proposal reports no subject.
- **A check whose subjects are gitignored has three outcomes, not two.** Match is PASS; no match with
  a not-gitignored representative is FAIL; no match while ignored is SKIP with a reason — because a
  fresh CI checkout holds none of the day-one subjects, and collapsing SKIP into either neighbour
  makes the check CI-dark or CI-red.
- **The exclusion list is a waiver, so it carries a reverse check.** Every pattern must have a
  subject, count-guarded so an empty list cannot pass vacuously.
- **The producer/consumer drift is filed against #309, not fixed here.** Wiring one hook by hand is
  the practice #309 exists to end, so this feature is inert until that sync lands, and says so
  rather than letting a green harness imply otherwise.

Detail: `docs/architecture/ADR-0137-404-stop-gate-trigger-granularity.md`.

## Decisions from the spec-coverage scope chain (ADR-0138)

The requirement-coverage gate's test axis was believed weak. Measured 2026-08-14 over 78 SPECs, 71
plans and 92 discovered test files, it was **100% vacuous**: `grep_boundary_test()` scans the whole
discovered population while the `R-NN` namespace restarts at `R-01` for every feature, so all 27
tokens `R-01`…`R-20` exist somewhere in the harness and all 199 declared ids passed. #312's `R-01`
was covered because `R-01` appears in #399's test file.

Key architectural decisions:

- **The issue's remedy is a provable no-op, and the measurement is what showed it.** Requiring the
  mention to sit on a non-comment line flips 0 of 199 ids; the strictest form flips exactly one, and
  that one is a false negative. The comment header is where this harness cites requirement ids —
  53% of in-scope-covered ids are comment-only and #404 is 45 of 45 — so the proposed rule would have
  failed the best-tested features first.
- **Tighten by SCOPE, not by assertion shape.** A discovered test file is in scope when its basename
  appears as a whole token in the `--plan` file. 24 of 117 ids flip, against 0 for the issue's remedy.
  The scope filters `$TESTFILES` rather than re-deriving the discovery predicate, so the `.md`
  exclusion stays closed by construction and there is one answer to "what is a test file", not two.
- **`UNSCOPED` is a new stdout token on the existing exit-1 channel, not a fifth exit code.**
  `UNCOVERED` stays byte-identical, so the blocking channel carries zero regression. The tokens are
  separate because the remedies differ — write a test, versus cite the id in the test this feature
  wrote — and the SKILL.md `_rc = 1` prose must name it, or the token has a producer and no consumer.
- **A denominator guard on the scope itself.** Zero matches can be correct; zero candidates is a
  broken derivation and from outside the two are identical. A non-empty `$TESTFILES` with an empty
  scope reports `SCOPE-EMPTY`, falls back to the unscoped population for that invocation, and does not
  render every id red.
- **`no-test:` is a declared exemption with a 20-character reason floor and a reverse check.** Four
  requirements in the corpus are not test-assertable at all ("the ADR records X", "the issue is
  filed"); blocking on them is the false-negative class R-03 forbids. An id carrying the marker whose
  token *is* found in scope is `STALE-WAIVER`, exit 3 — and it is not auto-repaired, because deleting
  an author's prose is not the same act as adding a checkbox marker.
- **R-03 is proven by a frozen 117-row per-item baseline, not argued.** A `>= N` floor absorbs its own
  plant; the floors here are vacuity guards on the derivation and the site says so. Divergence is RED
  in both directions — a live verdict with no baseline row, and a baseline row with no live verdict.
- **No archived SPEC is edited.** Retro-fitting the marker into four completed SPECs would correct a
  historical record in place. `no-test:` governs SPECs written from now on; the baseline is a record
  *about* the corpus already written, and what it protects is the derivation.
- **A measurement artefact worth keeping.** Pairing spec-to-plan through manifests gave 49 pairs, but
  36 of those manifests predate ADR-0106 and still point `artifacts.spec` at the mutable root
  `SPEC.md` slot — which held the in-flight feature's own SPEC. Those 36 were 108 copies of R-01/R-02/
  R-03 measured against unrelated plans. Pair by issue-number prefix, never through a manifest.

Detail: `docs/architecture/ADR-0138-312-spec-coverage-scope-not-assertion-shape.md`.

## Decisions from the plant-registry cost chain (ADR-0143)

The registry was filed as a cost problem at 166 plants. Measured 2026-08-15 at `0622930` it is
**381 declarations across 41 files**, and the cost is paid where nobody had looked: the CI step took
**20m07s** on a PR and **25m51s** on `main`, **89% of the `shell-tests` job** — which is a required
check, so every merge waits for it. A full run spends `755s user, 1148s system` at **89% of one core
on an eighteen-core machine**: more time copying trees than running tests, and no concurrency at all.

Key architectural decisions:

- **The design had already paid for concurrency and was not spending it.** Every mutation run has its
  own sandbox and its own process; 78 of 81 harnesses use `mktemp`. The three fixed `/tmp` paths in
  declaring harnesses were checked one by one and are string values written into manifests and
  synthetic JSON, never files created or read. Parallelism is therefore not a new guarantee, it is
  the use of one already bought.
- **All three levers the issue proposed were rejected on measurement, and the fourth was not in it.**
  Filtering a harness to one assertion is a per-file property — `worktree-isolation-contract` would
  slice cleanly, `spec-coverage`'s sections mutate a SPEC in place across `RM03`…`RM07` — provable 41
  times and not once, against ADR-0086. Sandbox reuse is 190s, **9%**, not the dominant term the issue
  suspected. A separate CI job costs a new required context (ADR-0114, #336 open) to save ~3 min that
  the workers make irrelevant.
- **The dominant term is the target file's runtime, and now it is a number.** `autopilot-run-scope`
  carries 58 plants and costs less than `worktree-isolation-contract`'s 11. Two files are 45% of the
  total, eleven are 87% — more concentrated than the issue supposed, in the two files it had already
  named.
- **One code path, not two.** The worker is `plant-check.sh` re-entering itself with `--worker`,
  carrying the sequential loop body unchanged; the sequential path is that path with one worker.
  ADR-0086's criterion exactly: two copies answering the same question disagree eventually, and then
  nobody can say which verdict is the registry's.
- **Aggregation in declaration order is a decision, not a detail.** An output that reshuffles per run
  cannot be diffed against anything — and the diff is the only evidence that parallelising a
  validator did not change what it validates.
- **Every failure in the worker-count resolution lands on 1.** An unreadable core count must not
  become an unbounded fan-out on a runner nobody has measured. The ceiling is 8 because 8 is what was
  measured; an explicit `PLANT_JOBS` is uncapped, because someone setting it is someone about to
  record what they got.
- **A change to the validator needs evidence from outside it and inside it.** Outside: the full
  381-plant run at 1, 4 and 8 workers — 29.34 min, 9.69 min, 7.59 min — with **391 output lines
  identical byte for byte** across all three and against the pre-change file. That evidence costs
  half an hour and cannot be a test. Inside: a fixture harness with four harnesses and twelve plants,
  whose sleeps make completion order differ from declaration order and one of whose plants **cannot
  fire** — because an equivalence check between two runs that both found nothing is satisfied by a
  registry that does nothing.
- **A literal `# plant:` at column 1 in a fixture-building harness is collected as that harness's own
  declaration.** The collector greps `^# plant:` across `*.test.sh` and cannot know the line was meant
  for a fixture. The fixture's declarations are written as `@PLANT@` and substituted; the trap is
  recorded because the next author will meet it.
- **This buys a constant factor, not a change of shape.** Each plant still runs the whole declaring
  file. When `spec-coverage.test.sh` doubles again, the problem returns, and the separate-job lever is
  what to re-read.

Detail: `docs/architecture/ADR-0143-350-plant-registry-parallel.md`.

## Decisions from the #313/#314 triage (ADR-0144)

Two issues whose titles describe a change that measurement then refused. `literal-assertion-added`
was re-measured by enabling it and scanning **every** non-merge commit reachable from `main` — 383,
no sampling: 8 findings across 5 commits, **0 of them the behaviour it exists to catch**. Four are
comments narrating an assertion, two are `printf` calls writing JSON fixtures, two are the
detector's own fixture. `spec-coverage.sh`'s unrecognised-heading gap was measured by instrumenting
the checker and running it over all 78 SPECs: the outside-every-recognised-section population is
**empty in both branches**, the `DECL_N == 0` one and the mixed one nobody had counted.

Key architectural decisions:

- **A disabled detector is retired, not left disabled.** It shipped off at 25% precision under
  ADR-0051 §D5 and stayed there because nobody remembers to delete a feature nobody can rely on.
  The AWKGUARD interval probe went with it: it guarded only that rule, and a probe with no subject
  is the shape rule 9 warns about.
- **The retirement is bounded and says by what.** This corpus is documentation and Bash; the
  detector was written for `assert <expr> == <literal>` in application code, which this repository
  barely has. The decision is about THIS repository, and presenting the number as a general verdict
  would overreach.
- **Five assertions kept passing after their subject was deleted, which is why they had to go.**
  `HA4a`, `HC5`, `HG3`, `HG4`, `HG5` each asserted an ABSENCE that had become trivially true. An
  assertion satisfied by the deletion of its own subject reads as coverage and pins nothing.
  `RET1`/`RET2` replace them with a reverse guard over the EXECUTION surface — comment lines
  stripped first, so the header stays free to name what was retired without turning its own guard
  red (rule 12).
- **"No instances" is not a close.** #313's population is zero because two generator templates feed
  75 of 78 SPECs, and one template edit would end that silently. `RH1` derives the recognised set by
  RUNNING the predicate the checker runs — both files, in the checker's own load order — rather than
  restating the heading list, which would pass while the rule drifted away from it.
- **Widening was rejected for having no instance.** The recognised heading set is untouched, and so
  is ADR-0072 §D5's asymmetry: nothing measured argues against it, and the measurement says the
  branch is never reached.
- **The plants corrected the assertions again.** `RET1`'s first form re-added `LIT_ENABLED` and the
  assertion stayed green — the token list did not include the variable, so the needle did not reach
  the mechanism it named. Second time in three days, after ADR-0143's `PP0`.
- **A `set -u` failure inside a pipeline subshell fires the inherited `EXIT` trap.** One surviving
  reference to a removed variable killed the `printf` subshell, whose inherited
  `trap 'rm -rf "$TMP"' EXIT` deleted the shared fixture directory mid-run; fourteen later
  assertions then failed for reasons that looked unrelated. `bash -n` passes on that file.

Detail: `docs/architecture/ADR-0144-313-314-triage-outcomes.md`.

## Decisions from the anchored-fired-predicate chain (ADR-0145)

The registry decided a plant had fired with `grep -q "^FAIL: $aid"` — a prefix with no right anchor,
so a plant declared for `SP5` was credited when `SP5b` failed instead. #355 said anchoring was easy
but re-verifying the corpus afterwards was "the work, and it needs its own cycle". Measured first:
**33 of 387 plants are exposed to such a collision and 0 are mis-credited**, because every one of the
33 mutations turns the NAMED assertion red. The re-verification the issue deferred is that table, and
it came back clean.

Key architectural decisions:

- **Measure the exposure and the defect separately.** "How many plants COULD be mis-credited" and
  "how many ARE" are different questions with a factor of 33 between them, and only the second
  decides whether the fix is a cycle or an afternoon. The second was answered by re-running each
  exposed mutation and recording the full red set instead of a boolean.
- **The emitted id set is derived by RUNNING each harness**, not by reading its source: what matters
  is what the harness prints, because that is what the grep sees. `phase1.test.sh` prints
  `ok   <label>` and emits no `PASS:` line at all, so its 6 plants were covered from the call sites
  instead — weaker evidence, disclosed rather than skipped.
- **The id is escaped before it reaches the regex.** Assertion ids are not all alphanumeric
  (`CE-secret-scan.sh`), and an unescaped `.` would restore a looser match than the one being
  removed — the issue's own defect surviving its own fix.
- **One function, two call sites.** ADR-0140 built the vacuity guard to inherit the looseness on
  purpose so the two halves would agree; they now share a source rather than a convention.
- **The fixture manufactures what the corpus cannot show.** With 0 mis-credited plants in 387, an
  assertion pinned on the real corpus would have passed before the change too. `PP6` builds the case:
  a plant named `E1` whose mutation only `E1b` reads.
- **The fixture's own harnesses had to be anchored first** — they grep `MARK-<id>`, and `MARK-E1`
  matches `MARK-E1b`, so the fixture would have reproduced inside itself the defect it exists to
  demonstrate.

Detail: `docs/architecture/ADR-0145-355-anchored-fired-predicate.md`.

## Decisions from the undefined-helper-scope chain (ADR-0146)

ADR-0081 found the instance sideways: `pairs-completeness.test.sh` had no `ok()`/`bad()`, a draft
called them anyway, and six assertions printed "command not found" while the suite reported
`PASS=244 FAIL=0` and exited 0. Nothing here runs under `set -e`. Measured across all 82 harnesses
before building anything: **zero** such calls today.

Key architectural decisions:

- **Getting to that zero took three attempts, and the wrong ones are the lesson.** 47 findings, none
  real — the scan matched the English word "no" inside message strings, and `no` IS a helper here.
  Then 3, none real — two `case` labels and an assignment, all in command position. Then 0, once the
  scan tracked quote state ACROSS LINES (the messages wrap), masked heredoc bodies, and excluded
  `name=` and `name)`.
- **A detector reporting zero is a claim about the detector.** One `verdict` call was planted into a
  copy of the corpus: the scan found exactly it, and `bash` confirmed the live behaviour — printed
  on stderr, execution continues, exit unaffected. `HS2` keeps that demonstration in CI, because
  `HS1` would be green with a broken scanner.
- **A derived scan, not 82 copies of a runtime hook.** `command_not_found_handle` in every harness is
  the same shared-helper problem ADR-0086 already refused, with more surface.
- **The vocabulary is derived, never listed:** a helper is a function defined by two or more
  harnesses. A hand-written list would be blind to the file that invents a new helper name (rule 8).
- **R-02 was refused in the form it was written.** A per-file assertion-count floor is the instrument
  ADR-0124 retired: a floor absorbs its own plant, so 49 new floors would be 49 lines that mostly
  cannot fail — the false-green shape the issue exists to remove, added in bulk in its name. The
  successor is #449, with the measurement and the four things to derive first.

Detail: `docs/architecture/ADR-0146-310-undefined-helper-scope.md`.

## Decisions from the producer-destination-anchor chain (ADR-0147)

ADR-0095's `has_producer` counted a line as a producer if it named the target and carried the word
"transition" anywhere. Measured over the corpus first: 28 targets, 45 pairs, and **every target has
a genuine producer today** — the third issue running whose stated defect has no live instance.

Key architectural decisions:

- **The looseness was large and decidable.** On `step_6_review`, eleven lines counted as producers
  and exactly one was an instruction: three negations, one negation wrapped onto a second line, four
  narrations, one narrative arrow, and one line where the target is the SOURCE.
- **What that cost was not precision, it was plantability.** TP1 could not be planted: delete the
  one real producer and ten prose lines hold it green. Measured both ways on the same mutation — old
  predicate `PASS=14 FAIL=0`, new predicate `FAIL: TP1 … undeclared: step_6_review`.
- **The preceding word separates an instruction from prose, and form cannot** (ADR-0117, applied to
  a second predicate). `the transition to X`, `before transitioning to X`, `it never blocks the
  transition to X` are all narration and all decidable.
- **An arrow whose left operand is the target is the target's SOURCE** — #355's right anchor in a
  second place. The legal-source set is derived from the same pair table the targets come from;
  `block the Step 5 → step_6_review` has no source at all.
- **Paragraph joining was implemented and rejected on measurement.** It credited a second state with
  a first state's `manifest-transition.sh` call and destroyed the `step_e1_plan` arrow attribution —
  the exact form ADR-0095 had to add, and the regression R-03 names. Wrapping is handled by a
  one-line lookback for the split negation instead.
- **The residue is stated, not closed.** `transitioning to X` with no determiner in front reads as
  an imperative whether or not it is one. That is English word order, not a parse.

Detail: `docs/architecture/ADR-0147-300-producer-destination-anchor.md`.

## Decisions from the in-place-assertion-edit chain (ADR-0148)

ADR-0073 recorded the blind spot and declined to close it: an assertion edited in place removes one
assert-bearing line and adds one, so `assert-removed`'s count comparison cannot fire. Its closing
sentence is why the issue exists — anyone relying on the weakening gate for assertion integrity is
relying on something that does not exist. The gate is wired into four paths that can commit with
nobody present.

Key architectural decisions:

- **Re-measured before designing, and the answer held.** Every non-merge commit reachable from
  `main` — 383, no sampling: the rule fires 6 times, **0 true positives**. Four are prose or
  `ok`/`bad` message strings. The other two are genuine in-place edits that *raise* a floor
  (15 → 18, 9 → 10), which the rule cannot distinguish because it sees a count, not a direction.
- **The corpus grew 8% and the findings trebled while precision stayed at zero**, so 0-of-2 was not
  a small-sample artefact. R-01 forbids shipping anything that does not beat it; zero of six does
  not beat zero of two.
- **Third refusal on the same script.** ADR-0051 §D5 shipped `literal-assertion-added` disabled
  rather than face this; ADR-0144 retired it on 0 true positives in 383 commits; ADR-0073 declined a
  sibling. The structural argument outranks all three measurements: correcting a wrong test and
  relaxing a right one produce byte-identical diffs.
- **The work was R-02, and the gap was exactly where it hurts.** The limit was stated in the script
  header, at c2c Step 5 and at commit Step 1 — but not at CIRCUIT BREAKER B, which
  `commit/SKILL.md` itself calls "the actual enforcement point", and not at autopilot-build's
  breaker-B halt, the caller that runs unattended. The place most likely to be mistaken for coverage
  was the place with no disclosure.
- **Both numbers stay.** The header records 0-of-2 over 354 *and* 0-of-6 over 383. Overwriting the
  older one would delete the evidence that a larger corpus did not change the answer.
- **These assertions pin prose, deliberately** (rule 16). A green `WJ7` is evidence the sentence is
  present, never evidence anyone read it.

Detail: `docs/architecture/ADR-0148-311-in-place-assertion-edit-refusal.md`.

## Decisions from the plant-declaration-grammar chain (ADR-0149)

ADR-0108 named its own limit — replacement only, two of that session's plants were insertions and
not expressible. Measured before designing, 383 plants over 43 files, and half the premise had
already dissolved.

Key architectural decisions:

- **Deletion was never the problem.** 30 of 383 plants already neutralise with `true`, `:` or
  `if false; then`, and one prepends `exit 42;` on the same line, which is a same-line insertion
  spelled as a replacement. R-01 as written was satisfied on the day it was written.
- **What is inexpressible is adding a LINE** — the shape an exhaustiveness assertion guards: an
  extra table row, a duplicated transition pair, a second heading where the scan counts one.
- **Measuring found something worse than the issue.** The header says a ` | ` sequence cannot appear
  inside a field and the error says "need 4 fields", and *nothing checked the count*. One
  declaration had shipped with six: `A25` truncated its needle at the first inner pipe, substituted
  `wc -l` for the head of a pipeline, and produced a syntax error instead of `P=0`. The harness died
  of it and the plant was credited as fired — a plant that pins nothing, inside the mechanism built
  to find assertions that pin nothing (rule 17).
- **Enforce first, widen second.** A `\n` escape in a field that can be silently truncated is a
  widening built on a hole. Three fields is now the declared deletion form — what the code already
  did by accident, stated so the next reader does not "fix" it.
- **Two escapes and only two**, `\n` and `\\`. Backward compatible by measurement: zero of the 383
  existing replacements contains a backslash.
- **Every new assertion distinguishes.** A `\n` left literal keeps the added text on one line, so
  `grep -c` still counts one row and the plant reports NOFIRE — which is what makes `PP8` a test
  rather than a description. `PP9` runs one mutation past two assertions, one that must stay green
  and one that must go red, because "no double backslash" alone is satisfied by a mutation that
  never landed.

Detail: `docs/architecture/ADR-0149-305-plant-declaration-grammar.md`.

## Decisions from the vanished-assertion-baseline chain (ADR-0150)

ADR-0146 refused #310's per-file assertion floor and split the real question out as #449: a frozen
per-file baseline, red on any drop, bumped deliberately. Four things to measure first. All four were
measured, plus two the issue did not ask for, and the design does not survive them.

Key architectural decisions:

- **The static count is the wrong number, and the runtime one is already free.** A static count of
  `ok`/`bad` call sites agrees with the runtime count in 3 of 83 harnesses; the delta runs from −98
  to +256, because assertions are `if/else` pairs of which one branch executes and some are emitted
  inside a loop. But 77 of 83 harnesses already print `PASS=N`, matching the emitted count in 74.
  The issue's cost objection — a second suite run does not fit the 300s ceiling — dissolves.
- **95 of the last 100 harness-touching commits add or remove an assertion.** The issue set this as
  the deciding question, guard or tax. A line bumped on nineteen commits out of twenty is a line
  people learn to bump without reading.
- **No assertion has vanished silently.** Three net drops in those 100 commits, all deliberate, each
  leaving a comment where the assertion stood naming the issue and the ADR. Fourth issue in a row
  whose stated defect has no live instance.
- **The added population is real and is stated anyway:** 2622 of 2993 assertions carry no plant. The
  argument is not that the exposure is imaginary, it is that the proposed instrument costs more
  attention than it returns.
- **The issue named the wrong token.** A vanished planted assertion is caught as `NOFIRE`, not
  `BADPLANT` — the needle lives in the target file and still resolves. Correct outcome, wrong name,
  and the two have different repairs.
- **The practice that worked becomes rule 19**, and it is an instruction for 88% of assertions, an
  enforcement for the planted 12%. No diff-level rule can close the gap: measured twice on this
  exact question at zero precision (ADR-0073, ADR-0148).
- **Two of the measurement's own heuristics were wrong and were caught by inspection** — one counted
  loops over literal lists, the other missed a denominator guard worded differently from the grep
  looking for it. Rule 2's second clause, applied to a measurement rather than to a plant.

Detail: `docs/architecture/ADR-0150-449-vanished-assertion-baseline-refusal.md`.

## Decisions from the shard-the-plant-registry chain (ADR-0151)

The plant registry stops being one job and becomes four shards plus a union:
`.github/workflows/docs-ci.yml`, `staging/plugin/scripts/tests/plant-check.sh`.

Key architectural decisions:

- **The unit of the split is a plant, not a harness, and the issue did not pose it that way.**
  `spec-coverage.test.sh` alone is 29.5% of the modelled cost, so slicing by harness is capped at
  3.39x however many shards exist. A plant already costs one sandbox and one harness run, so it is
  the atomic unit and there is no such floor.
- **`shell-tests` becomes the union job and keeps its name.** It is one of four required contexts on
  `main`; making the union a new job would have meant a branch-protection change and a window where
  the registry is either ungated or blocking every PR. The price is ~2.5 min of harness loop moving
  onto the critical path, paid knowingly.
- **A matrix leg can never be a required context.** Measured: `required-checks-audit.sh` derives
  producers from job ids and `name:` keys, and a leg's context is `<display name> (<value>)`, which
  is declared nowhere. Requiring one blocks every PR forever.
- **A union written the obvious way is green while its shards are red.** Measured on a probe run:
  two of four dependencies `failure`, and inside the job `if: failure()` was skipped while
  `if: success()` ran. Status functions in a step `if` read that job's own previous steps, not
  `needs`. The predicate has to be an explicit `needs.<job>.result == 'success'` per leg.
- **The leg gate lives in `plant-check.sh`, not in the yaml.** A step `if:` cannot be planted, so in
  yaml the requirement could only ever be an assertion that some text exists (rule 16). As
  `--require-legs` it is a planted mechanism.
- **One code path: the sequential run is the 1-of-1 shard.** Both loops walk
  `seq "$SHARD" "$SHARDS" "$DECL_N"`, which at the defaults is the whole population. A sharded
  implementation kept beside a sequential one is two copies answering one question (ADR-0086).
- **A malformed slice refuses where a malformed `PLANT_JOBS` resolves downwards.** The asymmetry is
  deliberate and stated at the site: one is a performance knob, the other decides which plants run
  at all.
- **Assignment is by modulo on the declaration index, with no stored cost table.** It carries no
  state to go stale (rule 13) and balances precisely because it breaks files apart. The achieved
  imbalance is printed by the run rather than assumed by the design.
- **The union re-derives its own denominator.** With the population assertions deferred, a shard
  whose collector broke would exit 0 and read clean; `PC6` requires every declaration index to be
  reported exactly once. A per-slice floor was refused because a floor absorbs its own plant
  (rule 10).
- **No new numbered rule.** This is rules 4 and 7 applied to a new topology, not a new invariant.

Detail: `docs/architecture/ADR-0151-447-shard-the-plant-registry.md`.

## Decisions from the archive-fence-empty-root chain (ADR-0152)

The Step 1 archive fence stops halting on the case its own documentation calls a no-op:
`staging/plugin/skills/concept-to-code/scripts/spec-archive.sh`,
`staging/plugin/skills/concept-to-code/SKILL.md`.

Key architectural decisions:

- **The existence check moves above the slug validation, and that is the whole fix.** On an empty
  root `gate0-detect.sh` reports `spec_topic_slug=unknown`, the fence passes it through, and
  `spec-archive.sh` refused before it had looked for a file. The caller's contract on exit 3 is
  HALT, so a brand-new project could not get past Step 1 — the bootstrap path, which is what Gate
  0d's scaffolding survey exists to serve.
- **The shape guard stays ABOVE the existence check, and the split is two `case` blocks rather than
  one reorder.** Sinking the whole guard would make `spec-archive.sh <empty-root> ../../etc/passwd`
  return `NOSPEC`/0, turning a malformed call into a silent success. What ships preserves every
  refusal the script made and changes exactly the one that was wrong.
- **`gate0-detect.sh` is not touched, because the issue's premise did not survive.** It claimed the
  absent and markerless states are indistinguishable in the detector's output. `spec_owned` is `no`
  only when the file is absent, so `mode` separates them; the pair `mode` + `spec_topic_slug` is
  unique. R-02 closes with an assertion over output that already existed, which also keeps this
  clear of #454.
- **A green assertion over an input the caller cannot generate is not coverage of that caller.**
  The fence sees exactly two pairs. `SA1` tested `(no SPEC.md, valid slug)` — greenfield with no
  file always produces `unknown`, so that pair cannot occur — and it is what made the empty-root
  case look tested for two months. `SA5`'s pair is unproducible too, but SA5 declared itself as
  defence-in-depth and SA1 did not. Both keep their verdicts and gain the missing sentence.
- **SA16 and SF5 are one claim at two levels and carry two plants.** SA16's removes the mechanism,
  SF5's removes the wiring; SF5 runs the fence body extracted from `SKILL.md` by its fence-contract
  marker, so it is the orchestrator's own code on the orchestrator's own pair. One shared plant
  would have left SF5 unproven as a claim about `SKILL.md`.
- **The corrected prose names the ordering, not the outcome, and its assertion says it is prose.**
  `SA14b` cannot make the guard order right (rule 16); it stops the sentence reverting to the short
  form that was false for two months. Its plant is declared with that limitation stated.
- **Zero live instances, and the fix ships anyway.** 13 greenfield manifests, none from an empty
  root; the fence has never met one. The defect is invisible to this repository by construction,
  because its root slot is never empty.
- **No new numbered rule.** This is rule 17 — a producer and a consumer that never met — with
  rule 13 on both premises.

Detail: `docs/architecture/ADR-0152-455-archive-fence-empty-root.md`.

## Decisions from the project-tasks-vendored-bilateral-ledger chain (ADR-0153)

`project-tasks` stops being a private artifact on one machine and becomes a component of the
system, and `TODO.md` becomes a bilateral index of what is open:
`staging/plugin/skills/project-tasks/`, `staging/sync-to-claude.sh`,
`staging/plugin/scripts/tests/project-tasks-ledger.test.sh`, and the chain wiring in
`concept-to-code` and `project-conductor`.

Key architectural decisions:

- **The GitHub read is its own script, not a sixth `scan.sh` record type.** `scan.sh`'s selftest
  asserts that two consecutive runs are identical, and that assertion is what makes every other
  claim it makes reproducible; a network call would force its deletion. `gh-issues.sh` copies
  `roadmap-from-issues.sh`'s `--issues-json` offline hook, which is what turns the whole GitHub
  block from prose into executed assertions.
- **`runs:` is a pure function of the file on disk, so there is no counter to corrupt.** The
  promotion bar needs "survived two full runs", and a counter incremented before a write the
  operator then declines would drift silently while still looking plausible. Derived as
  `on-disk + 1` inside a filter that never writes, an abort discards the candidate and a retry
  re-derives the same value.
- **GitHub owns the issue's content, `TODO.md` owns what GitHub has no field for.** The split is
  per-field — title, state and labels regenerate; local priority, file reference and provenance
  survive verbatim — so the bilateral design needs no conflict resolution at all.
- **A declined promotion is recorded and never proposed again.** `reference/chain-integration.md`
  had already rejected automatic capture on the argument that a noisy ledger stops being read; a
  gate that re-asks every run is the same failure one level up.
- **Two premises of the SPEC did not survive measurement, and both inverted work.** The skill was
  already declared deployed-only, so vendoring means DELETING that declaration rather than adding
  anything — a waiver that outlives its subject reads as clean (rule 9). And the superseded
  "an item with an issue number leaves the file" rule lives in `TODO.md`'s own header, not in
  `reference/file-format.md`, so the requirement as first written was satisfiable by deleting
  nothing.
- **The marker detector is narrowed, not retired, and the two halves answer different cases.** A
  marker registers only in declaration form (keyword then colon) AND with a comment leader earlier
  on the line. Measured, each half is what rejects a different one of the observed false positives.
  ADR-0144 retired a detector at comparable precision; the difference is failure mode — that one
  produced a finding a human dismissed, this one produces a durable ledger entry.
- **An absence assertion gets a denominator, an absence, and a backward self-test.** "The litter is
  not in the vendored copy" reads identically to "the directory is not there", so the enumeration
  is guarded first (rule 7) and the predicate is run against a fixture that deliberately contains
  the litter. The absence half carries no plant, declared: a plant substitutes inside an existing
  file, it cannot create litter.
- **The chain wiring is an instruction, not an enforcement.** A harness pins that the text exists;
  nothing pins that a model obeys it (rule 16), and the ADR says which half is which rather than
  letting a green harness read as proof.

Detail: `docs/architecture/ADR-0153-project-tasks-vendored-bilateral-ledger.md`.

## Decisions from the spec-coverage-scope-back-reference chain (ADR-0154)

`spec-coverage.sh`'s test axis is narrowed a second time: a discovered test file counts only when
the plan names it **and** its own text names the plan or one of the ADRs the plan cites. Touched:
`staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh`, its harness, the frozen corpus
baseline, and one clause in `staging/plugin/agents/architect.md`.

Key architectural decisions:

- **The exposure was measured twice, independently, before this was designed.** On the ADR-0153
  plan, three harnesses cited as precedents carry seven ids inside that feature's own declared
  range, and four reported COVERED while cited nowhere in its harness. A separate measurement the
  day before, on a different feature, found 9 of 13 ids COVERED before implementation existed.
- **Two designs were refused on measurement, not on taste.** Scoping to a plan's `Budget:` lines
  would collapse 42 of 53 plans to an empty scope. Requiring the mention to sit in an id-mapping
  comment header would flip most genuine coverage to uncovered — 87 of 893 mentions have that form
  — which is the same wall ADR-0138 hit with its own candidate.
- **The adopted rule loses nothing measured.** 94 of 263 scoped files drop out, all of them
  precedent citations, and zero ids flip COVERED → UNCOVERED across 52 plans.
- **An empty scope now has two causes with opposite policies.** Zero *candidates* keeps its
  fallback, because it may be a broken derivation (rule 7). Zero *back-references* does not fall
  back: half 1 resolved and half 2 rejected everything, so the zero is a finding. Falling back
  there would silently restore the pre-ADR-0138 repo-wide scan.
- **The denominator guard is corpus-level and lives in the harness, not the script.** Per run, zero
  files passing half 2 is exactly the new legitimate state, so an in-script floor would fire on the
  state the script exists to report. It is declared a vacuity guard at its site, because a floor
  absorbs its own plant (rule 10); the regenerated per-row baseline is the real evidence.
- **The producer-side convention is stated once, in the architect's output contract.** A plan names
  the harness it creates; the harness names the plan or its ADR back. Rule 17: the producer and the
  consumer are in two files, so the convention lives with the producer rather than in both.
- **What it does not fix is stated rather than implied.** The same-file namespace collision
  survives: 8 of this feature's own 12 ids reported COVERED before a line of work existed, every
  one off a fixture token inside its own harness. The only candidate fixes are the ones ADR-0138
  measured and refused.
- **The feature's own SPEC blocked its own gate, and the block and the pass had the same cause.**
  Three ids carrying `(no-test: …)` reported STALE-WAIVER because their tokens exist as heredoc
  fixtures in the harness the plan names. Deleting the clauses cleared the block — and the same
  fixture tokens then reported those three ids COVERED. The deletion is paired with existence-level
  assertions for that reason; alone it converts a block into a false pass.

Detail: `docs/architecture/ADR-0154-spec-coverage-scope-back-reference.md`.

## Decisions from the compiled-language tester batch chain (ADR-0155)

`concept-to-code`'s tester-before-coder ordering gains a third batch-boundary rule for compiled and
type-checked languages: the tester's batch must leave the target building. Touched:
`staging/plugin/skills/concept-to-code/SKILL.md` (the batching rules, the checkpoint classification,
both tester dispatch briefs) and one clause in `staging/plugin/agents/architect.md`.

Key architectural decisions:

- **The ordering carried an assumption nobody wrote down.** ADR-0049 §D1 dispatches the tester first
  so it is briefed from the specification and never from the implementation. That works because a
  failing assertion still compiles — in bash. In Swift a test naming a type the coder has not written
  does not fail, it stops the target from building, and then no assertion runs at all.
- **The chain had no word for it, measured.** `grep -ci 'compil'` over the ~4200-line orchestrator
  skill returned **0**: not in the tester brief, not in the batching rules, not in the checkpoint
  classification. The machine was designed on an interpreted language and nothing stated what happens
  elsewhere.
- **The mechanism already permitted the fix; only the instruction was missing.**
  `test-write-scope.sh` line 69 short-circuits on anything that is not the coder, so the tester was
  always free to write an interface declaration on a production path. No hook changed.
- **The rule is a precondition, not a third peer.** Violating the existing rule 1 makes an assertion
  fail for the wrong reason, so the recorded RED proves nothing. Violating this one means there is no
  recorded RED at all, and no checkpoint state describing what happened — a strictly larger loss.
- **A fourth checkpoint state, because collapsing it is what stops the reading.** "The target did not
  build" is not a red: the expected-red table cannot be checked, the controller-side count read has
  nothing to read, and a real regression produces the same output as the intended state. Its remedy
  is a batching correction, not a fix to the code under test.
- **The separation caught the author.** The tester wrote all eight assertions from the requirements,
  never from the prose. Five passed on first contact and three did not, and in every case the
  assertion was right: `the coder owns the body` had been written as *the body is the coder's*,
  `instruction, not an enforcement` as *instruction, not enforcement*, `already permits` as *already
  free*, and `nothing blocks a dispatch` had been left out of the skill while the ADR said it. Four
  drifts from the house form in four sites, none of which would have surfaced had the same author
  written both halves.
- **Two assertions are softer than they look, and it is recorded at the site rather than chased.**
  `CB2` and `CB6` are ANDs whose second clause is already satisfied by pre-existing text, so a plan
  duplicating one token without adding the statement would pass. Measured by the plant author:
  removing one of two occurrences left each green, which is why both plants span the full range.
  Tightening them would be an in-place assertion edit, invisible to every gate here (ADR-0148).

Detail: `docs/architecture/ADR-0155-compiled-language-tester-batch.md`.

## Decisions from the stop-gate distinct-failure budget chain (ADR-0156)

`stop-gate.sh`'s anti-loop budget stops counting invocations and starts counting findings. Touched:
`staging/plugin/scripts/stop-gate.sh` only, plus six behavioural assertions and their plants in
ADR-0137's own harness.

Key architectural decisions:

- **The counter was written in two places and removed in none.** `$CF` is incremented inside
  `emit_block` and again on the timeout path; the green path cleared the dirty marker and the output
  file and left the counter alone. A session that reached the cap was disarmed *permanently*, and a
  later green run did not restore it.
- **5 of 16 sessions that ever blocked had reached the cap**, distributed `10 × 1`, `1 × 2`,
  `5 × 3`. The shape is the argument: a session that blocks once is a real red, seen and fixed; the
  five at the cap are the structurally red windows every tester-before-coder batch creates, which
  spent the whole budget on repeats and then guarded nothing for the rest of the session.
- **The budget is spent by distinct failures.** A failure whose output hashes to the signature
  already recorded spends nothing and does not block — the operator has read it. A different one
  still blocks and still spends, and that pairing is what stops the first half from being a bypass:
  a real regression has a different signature by definition. The gate became louder about new
  information and silent about old.
- **The signature is the OUTPUT, never the exit code.** A suite failing two different assertions
  exits `1` both times, so keying on the code would dedupe two findings into one and silently drop
  the second — a false negative in the direction the gate exists to prevent.
- **A green run now clears the counter and the signature**, so a verified tree refreshes the budget.
- **The stand-down moved into the `reason`.** This file's own comment on the timeout path already
  said why stderr is not enough — *a guard that stops guarding silently is this repository's
  signature failure* — while the block path stood down just as quietly.
- **The hook still learns nothing about the chain.** It reads only `$ROOT/.claude/`. #477's fourth
  question, a declared expected-red set both this hook and the Step 5 checkpoint could read, stays
  with #273: building it here is the one change that would make a project-owned hook depend on the
  chain's shape. A forward guard drives two identical sessions, one carrying a decoy manifest that
  declares the failure as expected, and requires the verdicts to match.
- **Two assertions are not isolable and it is recorded rather than smoothed.** `SGP25` and `SGP26`
  move together under any single-line mutation, because the count `SGP26` expects is defined against
  the same counter `SGP25` requires to stay untouched. The alternative mutation that separates them
  reaches `SGP28` instead — a worse entanglement, and one nobody had named.

Detail: `docs/architecture/ADR-0156-stop-gate-distinct-failure-budget.md`.

## Decisions from the cross-feature requirement-id collision chain (ADR-0157)

`spec-coverage.sh`'s mention scan stops reading the whole tests-root. Touched:
`staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh`, the frozen corpus baseline
`spec-coverage-scope-baseline.tsv`, and seven behavioural assertions with four plants in
ADR-0138's own harness.

Key architectural decisions:

- **Requirement ids restart at R-01 in every SPEC, and the discovered population is the whole
  tree.** Those two facts do not compose. A stranger's `R-13` satisfied the mention scan, so an
  untested id reported `UNSCOPED` — "the test exists, name its file in your plan" — and the field
  operator was left choosing between renumbering a released SPEC and waiving a requirement that
  was simply not tested. CLAUDE.md rule 18 in its second form; ADR-0138 named the first.
- **The false green nobody reported.** The same unfiltered population was copied *into scope* by
  ADR-0138's `SCOPE-EMPTY` fallback, so a stranger's id could report `COVERED`, exit 0. Nobody
  filed it, because nothing looks at a green.
- **ADR-0154's key set cannot answer this question, measured.** Half 2 admits a file naming the
  plan's basename *or any ADR the plan cites*: 39 to 61 of 98 files per feature, median 47. Half the
  repository "names any feature back". Reusing it here moved **0 of 130** corpus rows — the fix
  would have shipped green and inert. The plan basename alone is the opposite failure at **6 hits
  across 16 pairs**. The feature's own issue number as a `#N` token lands at **1 to 11**, and it is
  the token the house form already writes to say which feature a harness belongs to.
- **Half 2 is a conjunct; this key set is not.** Half 1 does the discriminating for ADR-0154, so
  half 2 can be generous. The ownership question has nothing to lean on, so its key set carries the
  discrimination alone. Two key sets, two questions, said at both sites (rule 6 permits copies that
  answer different questions and requires declaring it).
- **Absence of a claim is not evidence of foreign ownership, and two existing assertions said so
  before this paragraph was written.** The first implementation dropped every file that failed to
  claim this feature; it produced the same 12 rows and turned `RS1` and `RX6` red, whose fixture is
  a file the plan does not name and that claims *nobody* — ADR-0138's `UNSCOPED` state, whose remedy
  is right. The shipped rule has three states, and all 12 flips rest on positive evidence: the file
  claims a *different* feature.
- **A file the plan names is in the population unconditionally.** Even dropped by half 2, even
  claiming another feature. Telling that author to write a test that already exists two lines from
  where their own plan points is the failure mode the union exists to avoid.
- **The refusal token is not a prefix of the fallback token.** `SCOPE-FOREIGN-ONLY`, not
  `SCOPE-EMPTY-OWNED`: a token that is a prefix of another is indistinguishable to every `grep -q`
  already written against the shorter one, and two assertions branch on exactly that string. The
  first draft named it the wrong way and would have made both of them lie.
- **12 of 130 corpus rows move, 0 `COVERED` rows move in either direction.** No id loses coverage
  and none gains it; what changes is which remedy the 12 are told to apply. The 12 are listed by
  (spec, id) in the baseline's own dated block, each row carrying the reason in its annotation
  column, and the three already classed `not-test-assertable` keep that class.
- **Per-feature id namespacing is refused on cost, not on taste.** It was the field report's own
  proposal. It touches the declaration predicate, the normaliser, ADR-0122's `strip_emphasis()`
  shared by reader and repairer, ADR-0072's healer, both SPEC generators and 199+ ids in a closed
  corpus rule 14 forbids rewriting — and buys nothing the bounded population does not close.
- **A six-digit colour literal reads as a foreign claim.** Stated as a bound rather than left to be
  rediscovered: it makes a verdict stricter, never laxer.

Detail: `docs/architecture/ADR-0157-cross-feature-requirement-id-collision.md`.

## Decisions from the Step 6 no-commit / collapse-sees-whole-feature chain (ADR-0158)

Step 6 and Gate 5.06 stop committing their own corrections; Step 7.0's collapse fence gains a
`git add -u` after its soft reset. Touched: `concept-to-code/SKILL.md` (the fence and two
paragraphs), plus two behavioural assertions and one plant in ADR-0104's own harness.

Key architectural decisions:

- **One root cause, two field defects.** A Step 6 correction committed under a subject
  `_foreign` cannot attribute aborted the whole Step 7.0 collapse (#489) — the guard did exactly
  what it is for, refusing to fold a commit it could not attribute. A correction left uncommitted
  and unstaged was silently dropped by `commit`'s own "already staged" branch, which only
  *mentions* unstaged tracked changes as not included (#479). Both disappear once Step 6 and
  Gate 5.06 make no commit of their own.
- **Removing the cause, not widening the guard.** The other fix on the table was teaching
  `_foreign` to recognise a Step 6/Gate 5.06 commit subject. Rejected: it keeps a mid-feature
  commit that has to be specially recognised forever, for a case that has no reason to exist once
  the commit itself is removed. `_foreign`'s allowlist is untouched.
- **`git add -u`, never `git add -A`.** The exact scope `commit`'s own Step 1 already applies —
  tracked modifications, deletions and renames only. `git add -A` would also stage whatever debris
  the worktree-escape check (ADR-0068 §D11) exists to catch, and that boundary is pinned by its own
  forward-guard assertion rather than left to be rediscovered.
- **The reported count tells the two cases apart for free.** `COLLAPSED <n> <sha> staged=<k>`:
  `<k>` is the post-`git add -u` total, so it reads `>= <n>`'s file count exactly when a
  post-snapshot correction existed to sweep in, and equal to it otherwise — no second mechanism to
  keep in sync with the first.
- **A soft reset needed no new gate.** It changes nothing about the working tree or the index —
  only the branch tip moves — so one more staging step ahead of it needed no gate of its own;
  `commit`'s own Step 4 gate already shows the resulting diff before anything is written.
- **A ledger of controller-side corrections was rejected on rule 6.** It would be a second record
  of a fact the working tree already carries — which files changed — for no question the tree
  cannot already answer.

Detail: `docs/architecture/ADR-0158-step6-no-commit-collapse-sees-whole-feature.md`.

## Decisions from the one-build-root / completion-fact-before-merge-back chain (ADR-0159)

Two field defects sharing the same root cause: `isolation: worktree` bounds a dispatch's working
directory, never a resource outside it. Touched: `staging/plugin/scripts/detect-test-cmd.sh`,
`concept-to-code/SKILL.md` (a new pre-flight assertion and three reordered sequencing statements),
plus five behavioural assertions and their plants in ADR-0068's own harness.

Key architectural decisions:

- **A worktree isolates cwd, not a build's output directory.** `detect-test-cmd.sh` generated
  `xcodebuild` commands with no `-derivedDataPath`, so the build root was whatever the machine's
  Xcode preference resolved to — one location shared by every checkout, worktrees included.
  Reported live as a false red (an unsigned framework, a rerun); the direction that matters is the
  opposite one, a stale product from a different build reporting green on a broken tree.
- **The generator fix and the pre-flight gate answer two different populations.** D1 makes every
  newly generated candidate carry `-derivedDataPath`; D2 catches the project whose `.claude/test-cmd`
  was already approved before this ADR and will never be regenerated. Neither alone closes the field
  case — the report came from an existing project.
- **The completion-fact read and the merge-back were in the wrong order, and the ordering wasn't
  written down anywhere as a decision — it just happened to be that way.** `dispatch-state.sh`
  (ADR-0139) reads a marker the coder writes inside its own worktree, because the report itself
  arrives too late to trust. The SKILL.md text read that marker *after* running the merge-back,
  whose own last step, on success, deletes the very worktree holding it.
- **Measured, not assumed, which of the two possible failures this is.** A scratch repo on git
  2.50.1: a worktree whose only dirty content is gitignored is not "dirty" to `git worktree remove`
  — it succeeds and deletes the whole tree, marker included. `dispatch-state.sh` then correctly
  reports `NONE` for a directory that no longer exists, and `NONE` is wired to `HALT`. So the
  manifestation on a healthy batch is a **spurious halt**, not a silent stale-read pass — the safer
  of the two directions, and still a defect that would stop every clean run.
- **The helper's own contract did not move.** `dispatch-state.sh` answers correctly for the
  directory it is handed; the question was being asked at the wrong point in the sequence. Teaching
  it to distinguish "never existed" from "existed and was removed" was rejected (A2) as a second
  record of a fact the filesystem is supposed to be the sole source of.
- **Three independently-worded prose sites carry the reordering, not one shared assertion.** The
  coder-dispatch instruction, the completion-gate fence's lead-in, and the post-fence HALT branch
  each state the "read before remove" rule in their own words, so a reader who only sees one of the
  three still gets the invariant right. Stated as a disclosed limit rather than left implicit: none
  of `dispatch-state.sh`'s tokens can mechanically catch a future edit that puts the merge-back back
  in front — the assertions pin the wording, not the sequencing enforced.
- **The assertion-count floor was re-derived twice in the same file, not incremented by feel.**
  98 → 101 (Section M's first three assertions, issue #488) → 103 (M4/M5, issue #494) — each bump
  computed against the actual pre-mutation total rather than assumed, per rule 10.

Detail: `docs/architecture/ADR-0159-one-build-root-completion-fact-before-merge-back.md`.

## Decisions from the hash-not-comment / extension-not-view chain (ADR-0160)

Two detectors trusting a file's surface shape instead of its content, plus the forward guard that
change collided with. Touched: `weakening-scan.sh`, a new `ui-file-detect.sh`, `concept-to-code`'s
Gate 5.05 trigger, and `project-ci-checks.test.sh`'s CE section — nine behavioural assertions
across three harnesses, six plants.

Key architectural decisions:

- **`#` is a comment leader in Python; in Swift it opens a macro.** Every Swift Testing assertion —
  `#expect(...)`, `#require(...)` — starts with the character the body scan treated as a universal
  comment leader. Reported: 32 false `zero-assertion-test` findings against 12 real assertions in
  one file, all eleven repeats landing on the file that actually had coverage.
- **An allowlist, not a denylist, and the reason is stated rather than assumed.** Naming "languages
  where `#` is not a comment" would leave every language absent from that list mis-scanned too, just
  unmeasured. `is_hash_comment_lang()` names the languages where `#` IS a comment instead, and
  `.swift` is deliberately absent from it.
- **A `.swift` extension is not "this diff touched a view."** Gate 5.05's trigger was a bare
  extension match; a model, a service, a parser are all `.swift` and none is a view. Reported: a
  feature with no view and no `import SwiftUI` anywhere in its diff still ran the UI audit and
  recorded a checklist about work that did not exist.
- **The web extensions stay extension-only, on purpose — narrowing them would be guessing.** No
  measured false positive exists for `.html`/`.css`/`.tsx`/`.jsx`/`.vue` here; only `.swift` gets a
  content check, because only `.swift` has a measured false-positive shape (a non-UI Swift file) to
  correct.
- **The same shape `detect-macos.sh` already established (ADR-0093): a keyword counts only near its
  evidence.** `.swift` needs an import of a UI framework or a declaration conforming to a UI type in
  its OWN content, not merely its extension.
- **The forward guard this change collided with was narrower in intent than in its literal
  wording, and the user chose to narrow it again rather than revert the fix.** ADR-0054's CE section
  says no vendored check script may have an executable-line change — full stop, "if this goes RED,
  revert the script, never relax this assertion" written directly into the test. ADR-0054's actual
  constraint (§D1) was that the CI-wrapping feature must not achieve fail-closed by baking posture
  into the scripts; it was never a permanent freeze against a script's own correctness fixes. Already
  narrowed once before, for comment-only changes (ADR-0073 §D4) — this is the same move made again,
  for a different class.
- **The exemption is declared AND content-verified, not a standing grant.** `CE_EXEMPT_weakening_scan_sh="472"`
  passes CE only when the live diff itself cites `#472` as a standalone token — re-checked on every
  run. A later, unrelated edit to the same script that does not cite the issue is not covered by a
  stale table entry. Explicitly not a widened union (ADR-0044's refused shape): per-file, per-issue,
  content-checked.
- **A needle must never embed the plant declaration's own field delimiter.** AIJ1's first plant
  needle contained a literal ` | ` (the shell pipe in the invocation it was targeting), which
  silently mis-split the declaration into extra fields and produced a no-op mutation — caught only
  by manual inspection, since the probe reported "did not fire" rather than an error. Recorded as a
  needle-authoring lesson, not just a fixed instance.
- **Two pairs of assertions are documented as not isolable, the same precedent CB2/CB6 and
  SGP25/SGP26 already set.** AIJ4 and AIJ5 each exercise a fixture that satisfies two of
  `is_ui_swift()`'s three independently-sufficient checks at once by realistic construction (a real
  SwiftUI view both imports SwiftUI and declares `: View`), so no single-line mutation isolates
  either check alone — AIJ3's plant already pins the mechanism gating all three.

Detail: `docs/architecture/ADR-0160-hash-not-comment-in-swift-extension-not-view.md`.

## Decisions from the stop-gate fingerprint-cache chain (ADR-0161)

`stop-gate.sh` stops re-running a suite against a tree nothing has touched since the last run.
Touched: `staging/plugin/scripts/stop-gate.sh` only, plus five behavioural assertions and one plant
in ADR-0137's own harness.

Key architectural decisions:

- **ADR-0156's de-dup happens after the cost is already paid.** Spending the budget on distinct
  failures rather than repeats still requires running the suite once to learn a failure is a repeat.
  Reported live: a Stop fires on every turn spent waiting on an async dispatch, not only at a batch
  boundary, and each one re-ran the whole suite at this repository's 300s ceiling against a tree
  nothing had touched since the previous run.
- **The fingerprint is over the tree's own state, never the dirty marker alone.**
  `git status --porcelain` (what changed) plus `git diff HEAD` (what it changed to), both read at
  `$ROOT`. `mark-dirty.sh` only appends and never truncates, so its marker cannot tell "touched
  again with no new content" from "touched with new content" — exactly the ambiguity a content hash
  resolves and a marker cannot.
- **Not git means not cached, and the direction is fail-toward-running** — ADR-0055 §D2's
  strict-unknown convention (absent/unreadable resolves to the STRICTEST behavior, not the lightest)
  applied to a new question. An unreadable git state leaves the fingerprint empty, which can never
  match a stored one, so the suite always runs when the state cannot be read. There is no path
  through an unknown fingerprint to a skipped suite.
- **The cache skips the re-run, never the decision.** A cache hit still emits the exact block verdict
  the original run produced, still spends the ADR-0156 budget as if the suite had run again — because
  from the budget's perspective, the fingerprint match IS proof it would have. Skipping the re-run
  without also replaying the decision would have been silent tolerance.
- **125/126/127 are deliberately never cached.** They fail instantly by construction — the file's own
  prior comment already said so — so there is no wall-clock cost caching would save, only bookkeeping
  for a case that never benefits.
- **A green run clears the cache along with everything else it already clears (extends ADR-0156
  §D3).** Left behind, a stale fingerprint would let a LATER dirty state that happens to hash
  identically — the same edit made twice across a session — replay a verdict from a cycle the green
  run already closed.
- **The disclosed limit is the same one ADR-0156 already accepted, in the same direction, not a new
  one.** A suite whose own output varies run to run hashes the same tree and reuses a stale rc; this
  is stated as the same class of limit signature-equality already carried, not discovered later.

Detail: `docs/architecture/ADR-0161-stop-gate-fingerprint-cache.md`.

## Decisions from the session-context-inject compact-laziness chain (ADR-0162)

- **The measurement came first and changed the target.** The session was compacting every few turns
  and the obvious explanation — the context growing into its ceiling — is the one the data refused.
  `compactMetadata.preTokens` read out at 140,753 once and then sixteen times between 83,898 and
  86,906, against an `autoCompactWindow` of 300,000 that `/autocompact` confirms is read from
  settings. The context was never filling up. What was happening is that ~50k of every
  post-compaction context is fixed preamble, re-created on the first turn after each compaction
  (`cache_creation_input_tokens` of 48,456 / 52,942 / 50,057 / 53,877 / 54,945 / 54,624, against
  546–2,008 on the turns after), leaving ~35k of working room that one large tool output consumes.
  Rule 13, and it moved the work from a settings key to a hook.
- **The gap between the configured window and the observed threshold is left open, on purpose.** It
  would have been easy to write a sentence explaining it. Nothing was checked that could support
  one, so the ADR says the mechanism is not established and the fix is scoped to what *was*
  measured. A confident explanation would have been the more useful-looking artifact and the less
  true one.
- **The fail-open direction is the whole decision.** Reading `source` and skipping on `compact` is
  three lines; deciding what an unreadable payload means is the part worth an ADR. Here the costly
  failure is a context that silently stops being delivered, so absence resolves to *inject* — the
  inverse of ADR-0055 §D2's stop-gate case, from the same principle. Four of the six assertions pin
  that half rather than the saving, because the saving is what a future change would notice losing
  and the delivery is not.
- **A withheld payload is announced, not silently dropped.** Rule 4 is usually invoked for checks —
  "did not run" is not "found nothing". It applies identically to a saving: at `compact` the hook
  still prints its frame and names the file's absolute path, so the content stays reachable by
  someone who does not know the hook exists.
- **The precedent was already on the machine, one directory over.** The `remember` plugin's `MEMORY`
  block ships exactly this shape for its own payload and says so in the text it injects. The
  repository's own hook, sitting in the same `SessionStart` list, did not — and the handoff block
  was announcing "already delivered 18 times" while it happened. Reading a neighbour's solved
  version of the problem cost less than designing one.
- **`pairs-completeness` caught the omission the author would not have.** The new harness passed on
  its own and would have shipped never running in CI; CI1 flagged it in the same run. That check
  exists because of rule 8 — a check validating a list's entries is blind to what the list omits —
  and this is it paying for itself.

Detail: `docs/architecture/ADR-0162-session-context-inject-compact-lazy.md`.

---

## Decisions from the chain-decision-index-out-of-claude-md chain (ADR-0163)

The one-line index of what each ADR decided moves out of `CLAUDE.md`: `docs/chain-decision-index.md`.

Key architectural decisions:
- **The index is lookup data, not instruction:** 117 entries, 23,751 bytes, 66.5% of `CLAUDE.md`,
  re-created in context on the first turn after every compaction to answer a question nobody asked.
  `## Rules` stays, because that layer is loaded on purpose.
- **The heading stays and is load-bearing:** `CMC02` terminates its `sed` range on
  `/^## Chain decision index$/` and `CMC03` on the next level-2 heading. Delete the heading and both
  silently widen to end-of-file.
- **The plan's stated reason for moving three assertions out of the guard was false:**
  `build_sandbox()` copies `CLAUDE.md`, and has for some time. The real reason is that their subject
  is now a file under `docs/`, present in every environment, so an absence is a defect — `bad`, not
  `skip`. The false premise was corrected in the harness comment that carried it.
- **The producer switches on the destination's presence:** the same switch ADR-0136 gave the
  archive, so no project generated from this blueprint is broken. `CMC13` is what makes the producer
  and the consumer meet, and it is planted.
- **`CMC06` is declared unplantable with its reason:** a `>= 90` floor over 117 absorbs its own
  plant (rule 10). `CMC05`'s exact equality is where a plant bites.

Detail: `docs/architecture/ADR-0163-chain-decision-index-out-of-claude-md.md`.

---

## Decisions from the 460-spec-coverage-baseline-never-bumped chain (ADR-0166)

Step 7.0b archives a completing chain's SPEC into `docs/specs/`, which enrols it into
`spec-coverage.test.sh`'s frozen per-item baseline population — and nothing in the chain wrote the
matching baseline rows, so the enrolling chain's own commit left the harness red for whoever ran it
next. Hit live twice in five days: the #447 chain on 2026-08-17, and the #470 chain reproduced it on
2026-08-22 while this SPEC was being interviewed.

Key architectural decisions:
- **The bump lives beside `spec-coverage.sh`, not under `plugin/scripts/`:** a new
  `spec-coverage-baseline-rows.sh` at `staging/plugin/skills/concept-to-code/scripts/`, the exact
  deployed path the SPEC's own Definition of Done names, reached with no `pairs-zone-anomaly:`
  declaration.
- **Three modes, not the SPEC's two:** `--pair` (which plan the harness's own glob would resolve for
  a SPEC), `--rows` (verdicts for one pair), `--bump` (append absent rows). `--pair` exists because
  the chain knows its plan from `manifest.artifacts.plan` while the harness derives it by globbing —
  two answers to *which plan belongs to this SPEC* is exactly rule 6's defect condition, and without
  it a bump could write rows for a pair the harness will never resolve, moving the same mystery red
  to the other direction (`RS8b`, baseline-side orphan).
- **`--rows` forwards the checker's stderr verbatim:** `RY10`'s corpus denominator guard reads the
  `SCOPE-NO-BACKREF` token and the `N in scope` count off `spec-coverage.sh`'s stderr, not stdout. An
  extraction that dropped it would collapse `RY10` from 16 to 0 while every other assertion stayed
  green until the floor tripped — the single sharpest hazard in the refactor.
- **The exit-code contract mirrors `spec-coverage.sh`'s, and rule 20 is applied explicitly:** 0
  success, 1 conflict, 2 invalid, 3 did-not-run. The consumers are named (the new harness, and Step
  7.0b's own prose) precisely because this repo's own DID-NOT-RUN convention is not universal, and
  neither named consumer is `stop-gate.sh`.
- **Append-only, refuse on conflict, never rewrite (rule 14):** an absent row is appended; an
  identical verdict is skipped; a different verdict fails the whole bump, writing nothing, naming the
  SPEC, the id and both verdicts. Writes go through a temp file `mv`-ed over the baseline so a killed
  run cannot leave a half-written corpus file.
- **An absent baseline file is a genuine no-op — this repo's own baseline path gets its own
  assertion instead of a comment (rule 17):** `concept-to-code` runs on arbitrary projects, so a
  missing `--baseline` prints `BUMP-NOOP` and exits 0 rather than halting every foreign-project
  chain. That same design makes a typo in the path silent by construction, so the harness asserts the
  path this repo's own `SKILL.md` passes is real and plants against it.
- **Measurement corrected the SPEC's own number forward, not in place (rule 13, rule 14):** the SPEC
  said "16 live pairs, 16 baseline rows"; re-derivation found 16 pairs but 130 rows (106
  `COVERED`/12 `UNCOVERED`/12 `UNSCOPED`). Zero baseline rows changed — there was no pre-existing
  population-vs-baseline debt, only a mechanism that would go on missing every future one.
- **Whole-corpus regeneration was rejected, not merely deferred:** rewriting every row at Step 7.0b
  would silently re-freeze a later feature's genuine drift (a renamed test file flipping an existing
  pair's verdict) into the baseline, which is the one outcome a frozen per-item baseline exists to
  prevent (ADR-0138 §D5).
- **New assertions went into a new hermetic harness, not into the 1952-line
  `spec-coverage.test.sh`:** that file already runs the full 16-pair corpus twice per invocation and
  carries 43 plants: ADR-0143 §D7 measured plant cost as dominated by target-file runtime, so ~18 more
  plants there would have been the single most expensive place in the repository to add them.

Detail: `docs/architecture/ADR-0166-460-spec-coverage-baseline-never-bumped.md`.
