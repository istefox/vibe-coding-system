# Vibe Coding System for Stefano Ferri — Multi-Agent Architecture v2.1

**Version:** 2.1 (third full audit against complete official Anthropic documentation)
**Author:** Adriano per Stefano Ferri
**Date:** 17 May 2026
**Target:** Claude Code (CLI) v2.1.32+ with hybrid orchestration, sub-agents, agent teams (experimental), skills, hooks, and MCP

---

## Changes from previous versions

### v1.0 → v2.0
Structural corrections (sub-agents as formal entities with YAML, agent-teams as a separate pattern, CLAUDE.md size limit, path-scoped rules, complete hooks, worktree isolation, bundled skills, 6 permission modes).

### v2.0 → v2.1 (this version)
Full audit against official `code.claude.com/docs` pages (best-practices, sub-agents, agent-teams, memory, skills, hooks-guide, permission-modes, common-workflows, features-overview, mcp, claude-directory, settings, plugins, worktrees). Point corrections added:

- **`attribution` setting** (sec. 4): disables the "Co-Authored-By: Claude" signature in commits for professional branding. Important because Claude Code adds the trailer to commits by default
- **`$schema` in settings.json**: enables JSON validation in Cursor/VS Code
- **MCP GitHub remote via HTTP**: the modern pattern is `https://api.githubcopilot.com/mcp/` with Bearer token, no longer stdio. Section 9.1 updated
- **`claude mcp add` CLI**: Anthropic-recommended pattern vs direct editing of `.mcp.json`
- **`alwaysLoad: true`** for MCP servers with always-needed tools (skip tool search)
- **`MAX_MCP_OUTPUT_TOKENS`** to limit MCP output (default 25,000)
- **Worktrees: operational details** (sec. 12): path `.claude/worktrees/<name>/`, branch `worktree-<name>`, `worktree.baseRef: "head"` to branch from local HEAD, PR worktree with `#<num>`, caveats on `node_modules`/`uv venv` not carried over
- **`.worktreeinclude`**: project root file for copying gitignored files (`.env`, `secrets`) into newly created worktrees
- **Full diagnostic commands** (sec. 16): `/config`, `/context`, `/status`, `/doctor`, `/skills`, `/permissions`, `/plugin`
- **Plugin `--plugin-dir`/`--plugin-url`** (sec. 14): local and CI testing of plugins in development
- **Hook `InstructionsLoaded`** (sec. 7): debug path-scoped rules loading

### Correction 2026-05-19 (post-live hooks verification)

Direct verification of `code.claude.com/docs/en/hooks` (2026-05-19) found two
inaccuracies in sec. 7 and sec. 17, corrected inline here:

- **`type: prompt` and `type: agent` are NOT supported on the `Stop` event**:
  on `Stop` only `command`, `http`, `mcp_tool` are valid. Sections 7.4 and 7.5
  (prompt/agent-based Stop gates) are **wrong as written** — see
  corrective admonition in place. The correct pattern for a gate on `Stop` is
  a `type: command` hook with the contract `{"decision":"block","reason":"…"}`
  or exit code 2.
- **No `stop_hook_active` / native loop-protection for `Stop`**: an
  anti-loop guardrail (per-session counter on `session_id`) is the
  hook author's responsibility, not provided by Claude Code.

Confirmed in the same verification: `session_id` stable per session,
`tool_input.file_path` on PostToolUse, multiple hooks per event in parallel
(one "block" wins).

### Reconciliation 2026-05-19 (Stop-gate testcmd — implemented and deployed live)

The correct pattern indicated in the previous correction is no longer just a
*design*: it has been **implemented and deployed live** in `~/.claude/` (subagent-driven
execution). The as-built state supersedes any description of "design to do":

- The `Stop` gate is a `type: command` hook (`~/.claude/hooks/stop-gate.sh`) with
  a 3-tier ladder on an **explicit per-project declaration**
  `<repo>/.claude/test-cmd`: absent→bounded nudge / `NONE`→opt-out fail-open /
  present-not-approved→approve tier (NO exec) / approved→runs the command
  authoritatively (real exit code, timeout, counter-based anti-loop).
- **Trust-on-first-use**: a real command runs only after explicit approval
  via `~/.claude/hooks/approve-test-cmd.sh` (register `<sha256>\t<root>` in
  `~/.claude/state/stop-gate/trust`); modifying `test-cmd` invalidates the hash →
  re-approval required. **In the `concept-to-code` chain (Gate 2b, 2026-05-26):** approval
  goes through `AskUserQuestion` — the orchestrator calls `approve-test-cmd.sh` only after
  the user's explicit click. This resolves the stop-hook/auto-approve loop in which
  the orchestrator self-approved before the user could respond.
- **The grep heuristic `clear-dirty-on-test.sh` is RETIRED** (deleted and unwired
  from `settings.json`): structurally resolves the defect by which non-standard runners
  were not recognized. No more pattern-matching on test output.
- **Total fail-open** (spec §7): missing jq/sha256/timeout/session_id, exit
  124/125/126/127 → allow, never exit≠0.
- **Phases B/C** of the old agentic-swarm spec are **subsumed**
  by the authoritative tier (no separate remaining work).
- As-built authority: `docs/superpowers/specs/2026-05-19-swarm-testcmd-design.md`
  + `docs/superpowers/plans/2026-05-19-swarm-testcmd.md`. Harness
  `~/.claude/hooks/tests/run-hook-tests.sh` (PASS=28 FAIL=0). Pristine backup +
  rollback §9 in `~/.claude/state/backups/2026-05-19-swarm-testcmd/`.

Sec. 7.4/7.5 (admonitions updated to the as-built reference) and 7.6 (filesystem
layout updated to the deployed state) reflect this. Tier validation on the
pilot project = single open item (see sec. 17).

### Audit 2026-07-19 (CC 2.1.125–2.1.146, retroactive gap)

Source: `CHANGELOG.md` in the `anthropics/claude-code` GitHub repository, fetched byte-exact via
the GitHub API (`gh api repos/anthropics/claude-code/contents/CHANGELOG.md`), same method as every
audit since 2026-07-15. This range was never audited: the existing "Update 2026-05-25" note below
covers 2.1.147–149 and "Review 2026-06-20" above covers 2.1.170–183, leaving 2.1.125–146 as a real
gap. Backfilled on user request alongside the 2.1.150–169 gap and the 2.1.212–215 range.

- **Fixed a permission-prompt bypass on Bash env-var assignments** (sec. 10): CC 2.1.145 fixed bare
  variable assignments to non-allowlisted environment variables in Bash commands being auto-approved
  without a prompt. Closes a real gap in the Bash permission layer that `pre-flight-pattern-enforce.sh`
  and `db-backup-guardrail.sh` sit on top of; no hook change needed, the platform now enforces what
  those hooks always assumed.
- **Fixed the Stop-hook infinite-block loop, and `/goal` misfiring while subagents are still running**
  (ADR-0022, sec. 7): CC 2.1.143 caps a Stop hook that blocks repeatedly at 8 consecutive blocks
  (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`), ending the turn with a warning instead of looping forever. This
  is a second, independent layer on top of `stop-gate.sh`'s own anti-loop guardrail (a per-session
  counter that self-unblocks after N entries, see sec. 7.5) — belt and suspenders, no code change
  needed. The same release fixed `/goal` firing its completion evaluator while background shells or
  delegated subagents were still running, a direct false-positive risk for `nightly-autopilot`'s outer
  loop (ADR-0022). Also in 2.1.143: worktree cleanup no longer falls back to `rm -rf` when
  `git worktree remove` fails, preventing loss of gitignored or in-progress files — relevant to
  `coder`'s `isolation: worktree` (sec. 3.2) and `refactor-snapshot`'s worktree use (ADR-0031).
- **Fixed `/goal` hanging under `disableAllHooks`, and `/loop` scheduling redundant polling wakeups**
  (ADR-0022): CC 2.1.140 fixed `/goal` silently hanging with no resolution indicator when
  `disableAllHooks` or `allowManagedHooksOnly` is set. This system keeps safety hooks (`stop-gate.sh`,
  `nightly-guard.sh`, etc.) always active per ADR-0022's design, so the precondition never triggers
  here, but it is the exact failure class ADR-0022's hang-detection thread exists to catch. The same
  release fixed `/loop` scheduling redundant wakeups to poll for background tasks that already notify
  on completion — this is the platform-side origin of the "don't poll, you'll be notified" guidance
  this session's own `ScheduleWakeup` tool description now carries.
- **`/goal` and `claude agents` (agent view) introduced** (ADR-0022, sec. 3.10): CC 2.1.139 shipped
  the `/goal` command and the agent view — the two platform primitives ADR-0022's nightly-autopilot
  outer loop is built on. Noted here for the record since the existing ADR-0022 addenda start at
  2.1.198. Same release: hooks now run without terminal access (fixed a hook-writing-to-terminal bug
  that could corrupt an on-screen interactive prompt) and `Skill(name *)` wildcard permission rules
  were fixed to prefix-match like `Bash(ls *)`.
- **Fixed plan mode not blocking writes when a matching `Edit(...)` allow rule exists** (sec. 4, sec.
  11): CC 2.1.136 closes a gap where an `Edit(...)` allow rule could let plan mode write files despite
  the mode's read-only contract. Direct precursor to the 2.1.212 fix (see the 2.1.212–215 audit below)
  for plan mode auto-running file-modifying Bash; both erode the same invariant this system's CLAUDE.md
  states unconditionally ("Plan mode required for any task modifying >1 file"). Same release fixed
  `CronList` output missing qualifiers and the scheduled prompt — relevant to `nightly-autopilot`'s
  deferred `CronCreate` wrap-up (sec. "Cron scheduling... wrap once the Phase 4 smoke test passes").
- **Fixed subagents unable to discover skills via the Skill tool** (sec. 3): CC 2.1.133 fixed
  project/user/plugin skills not being discoverable by subagents through the Skill tool at all. Same
  release: hooks now receive the active effort level via `effort.level` in their JSON input and
  `$CLAUDE_EFFORT` in the environment, usable by any hook wanting effort-aware logic (none currently do).
- **`CLAUDE_CODE_SESSION_ID` added to the Bash subprocess environment, matching hooks** (ADR-0029):
  CC 2.1.132 is where Bash tool subprocesses first received `CLAUDE_CODE_SESSION_ID`, the same variable
  hooks already got. This is the platform mechanism ADR-0029's session-scoped filter in
  `hook-verify-workflow.sh` depends on — dates and confirms the primitive that fix relies on. Same
  release fixed `--permission-mode` being ignored when resuming a plan-mode session with
  `-p --continue`/`--resume`, and plan mode not being re-applied after `ExitPlanMode` in the same
  session — relevant to `autopilot-build`'s headless resume path.
- **Sub-agent progress summaries: prompt-cache fix and idle-cost cap** (sec. 3.10): CC 2.1.128 fixed
  sub-agent progress summaries missing the prompt cache (~3× reduction in `cache_creation` cost) and
  capped summaries re-firing repeatedly while a sub-agent's transcript is static. Pure cost benefit for
  any heavy subagent fan-out (Dynamic Workflows, `nightly-autopilot` roadmap runs).
- **`--dangerously-skip-permissions` widened to bypass `.claude/`/`.git/` writes** (sec. 10): CC 2.1.126
  changed `--dangerously-skip-permissions` to also bypass prompts for writes to `.claude/`, `.git/`,
  `.vscode/`, and shell config files (catastrophic removal commands still prompt). This system's
  `defaultMode` is `"auto"` (verified: `staging/user/settings.json:87`), not bypass mode, so the change
  doesn't affect normal operation; noted because `protect-files.sh` (`PreToolUse` on `Edit|Write`) is a
  hook, and hooks run independently of the permission-mode layer — so even under bypass mode, that
  guard would still fire per the blueprint's layered-defense design (sec. 10).

Out of scope (no blueprint impact): the `/plugin` Discover/Browse component previews, terminal
rendering/scrolling/IME fixes, Windows-only fixes (PowerShell tool defaults, background-daemon
launcher issues), `claude agents` UI/UX polish (columns, badges, footer hints), the `worktree.baseRef`
setting default-branch change (this system doesn't rely on `EnterWorktree`'s implicit base), MCP
pagination/timeout/OAuth fixes (no custom MCP servers with those configs here), and the various
Bedrock/Vertex/Foundry-specific fixes (no third-party provider in use). Source: `anthropics/claude-code`
`CHANGELOG.md` (GitHub, fetched 2026-07-19).

### Audit 2026-07-19 (CC 2.1.150–2.1.169, retroactive gap)

Source: `CHANGELOG.md` in the `anthropics/claude-code` GitHub repository, fetched byte-exact via
the GitHub API, same method as the 2.1.125–146 audit above. This range sits between the existing
"Update 2026-05-25" note (2.1.147–149) and "Review 2026-06-20" (2.1.170–183) and was never audited.

- **Hardened cross-session `SendMessage`: relayed messages no longer carry user authority** (sec. 3.10):
  CC 2.1.166 changed messages relayed via `SendMessage` from another Claude session to no longer carry
  the sending user's authority — receivers now refuse relayed permission requests, and auto mode blocks
  them outright. Directly relevant to this system's heavy `SendMessage`/`Agent` usage under `defaultMode:
  "auto"`: before this fix, a compromised or misbehaving subagent could in principle use `SendMessage`
  to push a permission request that looked user-authorized to another session. Pure hardening, no
  action needed.
- **Fixed Workflow agents with `isolation: "worktree"` blocked from editing their own worktree in
  background sessions** (sec. 3.2, ADR-0016): CC 2.1.161 fixed a bug where a Workflow `agent()` call
  dispatched with `isolation: "worktree"` from a background session was refused Edit access inside its
  own isolated worktree — the exact combination `coder` uses when dispatched through a Step 5 Dynamic
  Workflow. Before this fix, that specific pairing could have silently blocked implementation work.
- **Fixed subagents in background sessions bypassing the worktree-isolation guard entirely** (sec. 3.2,
  sec. 12): CC 2.1.154 is the more severe sibling of the 2.1.161 fix above — before it, a subagent
  running in a background session could write directly to the shared checkout instead of its isolated
  worktree, defeating the guarantee sec. 3.2 documents for `coder`. Same release fixed
  `worktree.baseRef: "head"` resolving to the main checkout's HEAD instead of the current worktree's
  HEAD when spawning subagents or calling `EnterWorktree` from inside a linked worktree — a correctness
  bug in the same subsystem.
- **`acceptEdits` mode gains a code-execution-config write prompt; workflow trigger rename confirmed**
  (sec. 10, ADR-0016): CC 2.1.160 made `acceptEdits` mode prompt before writing build-tool config files
  that grant code execution (`.npmrc`, `.pre-commit-config.yaml`, `.devcontainer/`, etc.). This system's
  actual `defaultMode` is `"auto"`, not `acceptEdits` (verified: `staging/user/settings.json:87`), so
  the new prompt doesn't apply directly — auto mode's own destructive-action classifier is the operative
  guard here (already documented at the 2.1.183 alignment above). Same release: the dynamic-workflow
  trigger keyword rename from `workflow` to `ultracode` — this is the exact platform change ADR-0016
  already cites ("renamed from 'workflow' in CC v2.1.160"); confirmed consistent, no drift.
- **`Stop`/`SubagentStop` hooks can return feedback instead of being labeled an error; `claude -p`
  no longer hangs forever on an orphaned backgrounded command** (sec. 7): CC 2.1.163 let `Stop` and
  `SubagentStop` hooks return `hookSpecificOutput.additionalContext` to give Claude feedback and keep
  the turn going, instead of every non-empty return being treated as a hook error. `stop-gate.sh`
  currently uses the older `{"decision":"block","reason":...}` contract exclusively (verified:
  `staging/plugin/scripts/stop-gate.sh`) — this is a genuine, currently-unused enhancement opportunity,
  not a bug fix that changes existing behavior. Same release fixed `claude -p` hanging forever after
  its final result when a backgrounded command never exits, relevant to `autopilot-build` and
  `nightly-autopilot`'s headless/print-mode runs.
- **Fixed subagent frontmatter MCP servers ignoring `--strict-mcp-config` and managed-MCP policy; fixed
  `subagent_type: 'claude'` silently discarding gitignored outputs** (sec. 3.8, ADR-0036): CC 2.1.153
  fixed inline `mcpServers` in agent frontmatter ignoring `--strict-mcp-config`, `--bare`, and
  enterprise-managed MCP allow/deny policy. `researcher.md` has no inline `mcpServers` deployed yet
  (ADR-0036 Finding 4, deployment deferred) — this fix removes one more risk factor for that eventual
  rollout. Same release fixed the `Agent` tool with `subagent_type: 'claude'` running in an undocumented
  temporary worktree that could silently discard outputs written to gitignored paths — worth knowing
  for any ad hoc catch-all `claude` agent dispatch that writes to a gitignored location.
- **Plugin/skill loading and worktree hygiene** (sec. 8, sec. 12): CC 2.1.157 made plugins in
  `.claude/skills/` auto-load without a marketplace entry, matching how this system's skills are
  deployed via `sync-to-claude.sh`. Same release: Claude-managed worktrees are now left unlocked when
  an agent finishes so `git worktree remove`/`prune` can clean them up, and a bug where background-agent
  worktrees under `.claude/worktrees/` were orphaned past the 30-day retention sweep was fixed — both
  reduce orphaned-worktree buildup from `coder`/`refactor-snapshot` worktree use.
- **`--safe-mode` troubleshooting flag; "CLAUDE.md too long" threshold now scales with context window**
  (ADR-0019): CC 2.1.169 added `--safe-mode`/`CLAUDE_CODE_SAFE_MODE` to start with all customizations
  disabled for troubleshooting, and `disableBundledSkills` to hide built-ins from the model. The same
  release scaled the "CLAUDE.md is too long" warning threshold to the model's context window instead of
  a fixed line count — `claude-md-slim`'s ≥30% reduction target (ADR-0019) stays a fixed, model-agnostic
  goal regardless, no change needed.

Out of scope (no blueprint impact): the LSP `workspaceSymbol` query-param fix and the `--tools`
CLI-flag Grep/Glob fix (2.1.162, a different mechanism from the agent-frontmatter `tools:` field
ADR-0038 covers — no overlap), WebFetch preapproved-domain precedence, MCP timeout-flooring and
pagination fixes (no custom MCP timeout config here), the hook `if: "Bash(...)"` subshell-matching fix
(2.1.163 — verified: no hook in `staging/user/settings.json` uses the native `if:` field, all Bash-scoped
hooks use `matcher` plus their own internal regex), `~`-path deny-rule/`$HOME` fix (no home-directory
deny rules configured), `fallbackModel` (2.1.166, not currently configured), the various terminal
rendering, Windows-only, and background-agent-UI fixes across this range. Source:
`anthropics/claude-code` `CHANGELOG.md` (GitHub, fetched 2026-07-19).

### Review 2026-06-20 (CC 2.1.170–2.1.183 cross-skill pass)

Audit of the full 2.1.170–2.1.183 changelog range against 26 skills, 8 agents, and 15 hooks. One item required a documentation update; the rest are no-ops or already covered.

- **Flat architecture decision record** (sec. 2.2): CC 2.1.172 enabled sub-agent nesting up to 5 levels deep (pre-launch classifier added in 2.1.178; depth cap enforced in 2.1.181). The system keeps the flat orchestrator → sub-agent model by design: predictable dispatch and cost, clean hook propagation for the ADR-0016 hook_verified smoke test, and bounded fan-out. The four dispatching skills now cross-reference §2.2 instead of presenting the flat model as a platform constraint. Source: `code.claude.com/docs/en/changelog.md` v2.1.172, v2.1.178, v2.1.181.
- **Workflow `agent()` attribution confirmed** (sec. 3.10): CC 2.1.174 fixed Workflow tool `agent()` subagents missing attribution headers. All git commits in this system route through the `commit` skill via the Skill tool, not directly from workflow `agent()` subagents, so the fix has no behavioral impact. Config-level attribution (`commit`/`pr` empty, `sessionUrl: false`) still governs. Source: `code.claude.com/docs/en/changelog.md` v2.1.174.

No-op confirmations: nested-skills double-load clean (26 unique names, no nested SKILL.md after PR #6 swiftui-pro fix); hook if-conditions (2.1.176) N/A, hooks use matcher-only config; MCP auth-stub fix (2.1.183) N/A, researcher/architect use only unauthenticated context7 tools; Fable 5 (2.1.170) no fit for the haiku/sonnet/opus tiering.

### Alignment 2026-06-20 (CC 2.1.181–2.1.183)

Relevant capabilities from CC 2.1.181 and 2.1.183, incorporated inline in the indicated sections:

- **`attribution.sessionUrl: false`** (sec. 4, sec. 10, checklist sec. 15): new CC 2.1.183 setting that omits the claude.ai session link from commits and PRs in web and Remote Control sessions. Added to `settings.json` alongside `commit` and `pr`. Complemented by a `claude.ai/session` pattern added to `detect-tool-traces.sh` in the `clean-public-repo` skill, providing retroactive coverage for CLI-local sessions and any URL already in history. Source: `code.claude.com/docs/en/changelog.md` v2.1.183.
- **Native auto-mode destructive-git blocking** (sec. 10): CC 2.1.183 blocks `git reset --hard`, `git checkout -- .`, `git clean -fd`, `git stash drop` (when not asked to discard local work) and `git commit --amend` (when the commit does not belong to the agent this session) in auto mode, plus `terraform/pulumi/cdk destroy`. Hardened here to defense-in-depth: explicit deny entries added for these commands plus `rm -rf *` (previously only `/` and `~` were denied). The native block covers auto mode only; deny entries cover all permission modes.
- **`/config key=value` set-from-prompt** (sec. 10): added in CC 2.1.181. `/config --help` lists all available shorthand keys. Previously `/config` opened only the tabbed settings UI.
- **Model-deprecation warnings now cover agent frontmatter** (sec. 3.9): CC 2.1.183 now shows a warning when a model declared in an agent's `model:` field is deprecated or auto-updated. All 8 system agents use bare tier aliases (`opus`/`sonnet`/`haiku`) that resolve at runtime, insulated from specific version IDs by design.
- **WebSearch fix in subagents** (sec. 3.10): CC 2.1.183 fixed WebSearch returning empty results in subagents. The `researcher` and `architect` agents are the only two with WebSearch in their tool list; both benefit without any modification.
- **Foreground subagent 5-level depth limit enforced** (sec. 3.10): CC 2.1.181 now enforces this for foreground subagents. The architecture here is flat (orchestrator → subagent, max 1–3 levels); the "no sub-agent spawns sub-agent" invariant keeps it comfortably below the limit with no impact.
- **Autocomplete dedup of user-level skills** (sec. 8.6): CC 2.1.183 fixed duplicate entries in autocomplete when multiple plugins are active. A nested `~/.claude/skills/swiftui-pro/skills/swiftui-pro/` copy (v1.0, stale relative paths) was the root cause of a `swiftui-pro` duplicate in this system. Removed; canonical v1.1 retained.

### Audit 2026-06-23 (CC 2.1.186)

Changelog items reconciled with the blueprint. The behavior-changing items (autopilot prompt stall, retry watchdog, workflow schema abort) are assumed from the changelog text and are not yet verified live here.

- **Background subagents surface permission prompts in the main session** instead of auto-denying
  (sec. 10, ADR-0020 addendum). For unattended autopilot this turns an out-of-allowlist tool call
  into a stall rather than a silent deny. The fix is an allowlist-completeness pre-flight, paired
  with the retry watchdog below.
- **`CLAUDE_CODE_MAX_RETRIES` caps at 15**, with `CLAUDE_CODE_RETRY_WATCHDOG` recommended for
  unattended sessions (ADR-0020 addendum, set in the autopilot session env not in `settings.json`).
- **Workflow `agent({schema})` subagents abort after 5 schema-validation failures** instead of
  looping (ADR-0016 addendum). The existing Step-5 fallback already covers the incomplete-report case.
- **`Agent(type)` deny and `Agent(x,y)` allow rules are now enforced for named subagent spawns**
  (sec. 10). The blueprint documents the capability but ships no active Agent allowlist, since a
  restrictive rule would also have to enumerate the built-in Explore/Plan/general-purpose and
  Workflow agent types or it would break plan mode and parallel dispatch.
- **New settings adopted/documented:** `respondToBashCommands: false` in `staging/user/settings.json`
  (sec. 10), `claude mcp login`/`logout` with `--no-browser` SSH (sec. 9), `teammateMode: "iterm2"`
  (sec. 2). The `MEMORY.md` compaction reminder (sec. 13) and flexible skill-frontmatter casing
  (sec. 8) need no change on our side. `/review <pr>` now matches `/code-review medium`. (Superseded by the 2026-07-07 audit: CC 2.1.202 reverts `/review` to a single-pass review.)

### Update 2026-06-24 (in-chain autopilot at Gate 4)

- The concept-to-code Standard path now offers "Implement now (autopilot, this session)" as a third
  Gate-4 option, so unattended Steps 5-7 can run from the planning session without the fresh-session
  resume. Coexists with the standalone `autopilot-build` skill (ADR-0020 addendum). Supporting fixes:
  restored `hook_verified` default to `false` in `manifest-init.sh` (re-enables the Step-5 smoke gate)
  and added an autopilot default to the smoke gate (no unattended stall). Live `~/.claude` changes;
  repo docs unchanged elsewhere.

### Audit 2026-06-24 (CC 2.1.187)

Changelog items reconciled with the blueprint. The behavior-changing items are assumed from the changelog text and are not yet verified live here.

- **Workflow `agent({schema})` structured-output success-path fix** (ADR-0016 addendum). The model
  no longer re-calls `StructuredOutput` after a valid result and follow-up turns return structured
  output reliably. Completes the 2.1.186 abort-after-5 fix and makes `step5-report.json` more
  dependable.
- **Background jobs no longer hang on empty output** (ADR-0020 addendum). A subagent that ends a
  turn without structured output used to leave the agents view stuck in "working"; it now resolves.
  Closes one autopilot hang mode but not the 2.1.186 permission-prompt stall.
- **`sandbox.credentials` setting** (sec. 10) blocks sandboxed commands from reading credential
  files and secret env vars. Documented, not pinned: the settings schema does not yet list it, so
  the value format is unconfirmed (same discipline as `CLAUDE_CODE_RETRY_WATCHDOG`).
- **Remote MCP idle abort** (sec. 9): a remote MCP tool call with no response for 5 minutes now
  aborts with an error instead of blocking forever, with `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT` as the
  override. Documented; not pinned.
- **Subagent depth tracking** (sec. 3.10): forked subagents now count toward the depth cap and
  resumed subagents restore their original spawn depth. Tightens the cap the flat model already
  stays under.
- **Leaked worktree-registration cleanup** (sec. 12): locked `.git/worktrees/` entries from killed
  agents now clean up automatically, removing a manual-cleanup footgun for parallel `coder` dispatch.

Out of scope (no blueprint impact): org-configured model restrictions, mouse-click menu selection,
`--resume`/`-p` no-turn fix, CJK paste mojibake, Ghostty Cmd+click, optional `/install-github-app`
workflow, `/btw` navigation, `/plugin` cleanup surfacing, VSCode resume fix, stop-notification
wording. `staging/user/settings.json` is unchanged this pass, deliberately (sandbox.credentials and
the MCP idle-timeout override are document-only until the schema confirms their format).

### Audit 2026-06-26 (CC 2.1.190–2.1.193)

Changelog range reconciled with the blueprint. 2.1.192 does not exist (the changelog jumps
2.1.191 to 2.1.193); 2.1.190 is detail-less ("Bug fixes and reliability improvements"). The
behavior-changing items below are assumed from the changelog text and are not yet verified live
here.

- **Idle background-shell memory-pressure reaping** (ADR-0016 addendum, ADR-0020 addendum): CC
  2.1.193 added automatic reaping of idle background shell commands under memory pressure, with
  `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` to disable it. Long Workflow Step-5 runs and
  unattended autopilot can hold idle background shells long enough to be reaped; the disable
  variable is the mitigation, documented as a session-env recommendation (not pinned in
  `settings.json`), same discipline as `CLAUDE_CODE_RETRY_WATCHDOG`.
- **Background-agent dispatch fixes** (sec. 3.10, ADR-0016/0020 addenda): CC 2.1.193 stopped the
  background-agent launch result from instructing Claude to "end your response", so the
  orchestrator keeps working while a dispatched agent runs; it also fixed a phantom
  `general-purpose (resumed)` subagent re-running the main conversation, pinned background agents
  being re-prompted after each auto-update, and the agent panel hiding sibling agents. Net effect:
  more reliable Step-5 parallel dispatch and unattended autopilot.
- **`autoMode.classifyAllShell` (opt-in)** (sec. 10): CC 2.1.193 added a setting that routes all
  Bash/PowerShell through the auto-mode classifier instead of only arbitrary-code-execution
  patterns. Documented as opt-in only and left off: the deterministic `pre-flight-pattern-enforce`
  hook stays authoritative regardless of permission mode (layered defense, ADR-0001/0004). The same
  release surfaces auto-mode denial reasons in the transcript, the denial toast, and `/permissions`
  recent denials, which complements the HITL gates as observability.
- **OTEL `assistant_response` log event** (sec. 10, security note): CC 2.1.193 added
  `claude_code.assistant_response`, redacted unless `OTEL_LOG_ASSISTANT_RESPONSES=1`; when that
  variable is unset it follows `OTEL_LOG_USER_PROMPTS`, so a deployment already logging prompts
  starts logging response text on upgrade. This system ships no OTEL config, so the item is N/A in
  practice; the note records the mitigation (`OTEL_LOG_ASSISTANT_RESPONSES=0`) for any future
  telemetry setup.

Verified, not assumed: the CC 2.1.191 comma-separated-matcher bug (hooks with matchers like
`"Bash,PowerShell"` silently never firing) does not affect this system. Every hook matcher in
`staging/plugin/hooks/hooks.json` and `staging/user/settings.json` uses the pipe form
(`Edit|Write`, `Bash`).

Out of scope (no blueprint impact): plugin auto-rename `renames` map followed automatically
(sec. 14, the system ships as a plugin but no rename is pending); MCP `headersHelper` re-run on
401/403 and the MCP-auth startup notice (sec. 9, our context7 server is unauthenticated); 2.1.191
reliability items (`/rewind` resuming from before `/clear`, −37% streaming CPU, MCP discovery
retries, sandbox host-remember, background-agent resurrection fix); bash-mode `!` path
autocomplete. `staging/user/settings.json` is unchanged this pass, deliberately. Source:
`code.claude.com/docs/en/changelog.md` v2.1.190, v2.1.191, v2.1.193.

### Audit 2026-06-27 (CC 2.1.194–2.1.195)

Changelog extended to the latest published release. 2.1.194 does not exist (the changelog
jumps 2.1.193 to 2.1.195, the same gap pattern as 2.1.192); 2.1.195 is current. The
behavior-changing item below is assumed from the changelog text and is not yet verified live
here.

- **Background-agent reliability fixes** (ADR-0016 addendum, ADR-0020 addendum): CC 2.1.195
  fixed background jobs disappearing from `claude agents`, a crashed background task reopening
  to a blank screen, and background-agent daemons running unreachable when the control socket
  fails. These continue the 2.1.193 background-agent thread and are additive: they harden the
  Step-5 parallel-dispatch path and the unattended autopilot run without changing any contract.
  The daemon-reachability fix in particular lowers the risk on the deferred autopilot smoke
  test, where a long unattended run holds background agents across Steps 5–7 with no human to
  recover a wedged daemon.

Verified, not assumed: the CC 2.1.195 hyphenated-matcher bug (hook matchers with hyphenated
identifiers accidentally substring-matching) does not affect this system, the same conclusion
and reason as the 2.1.191 comma-matcher item. No matcher uses a hyphenated identifier: every
matcher in `staging/plugin/hooks/hooks.json` and `staging/user/settings.json` is a pipe or
single-token form (`Edit|Write`, `Bash`, `compact`, `idle_prompt`).

Out of scope (no blueprint impact): `CLAUDE_CODE_DISABLE_MOUSE_CLICKS` (fullscreen mouse
toggle), voice-dictation fixes (macOS silence capture, no-space-language auto-submit, Linux
voice mode), `/plugin` enable/disable and project `.claude/settings.json` plugin-load fixes
(sec. 14, the system ships as a plugin but no such config is used), and the Remote-session
provisioning checklist. `staging/` is unchanged this pass, deliberately. Source:
`code.claude.com/docs/en/changelog.md` v2.1.195 (and the 2.1.194 gap).

### Audit 2026-06-30 (CC 2.1.196–2.1.197)

Changelog extended to the latest published release. 2.1.194 stays the only gap in this
window (the jump 2.1.193 → 2.1.195 noted in the prior audit); 2.1.196 and 2.1.197 both
exist. 2.1.197 is a single-item release (the model default); 2.1.196 is a large reliability
release. Behavior-changing items below are assumed from the changelog text and not yet
verified live here unless marked otherwise.

- **Sonnet 5 is the new default model** (sec. 3.10): CC 2.1.197 makes Claude Sonnet 5 the
  default in Claude Code, with a native 1M-token context and promotional pricing of $2/$10
  per Mtok through Aug 31, after which it rises to $3/$15. All five Sonnet-pinned agents
  (`coder`, `reviewer`, `tester`, `debugger`, `refactorer`) use the bare `sonnet` alias, so
  the upgrade lands with no config change; the `opus` and `haiku` agents are unaffected. The
  cost rationale in sec. 3.10 carries a known step-up date (Aug 31). On agentic coding Opus
  4.8 still leads Sonnet 5 (roughly 69 vs 63 on the launch benchmark), so the `architect`
  agent stays on Opus by design.
- **Background-session durability and crash recovery** (ADR-0016 addendum, ADR-0020 addendum):
  CC 2.1.196 made background sessions survive their process being stopped, restarted, or
  updated, including a shell hand-off on Windows; daemon-killed workers now auto-resume when
  the agents view opens, and Remote sessions interrupted by a server restart auto-resume on
  the next worker. These continue the 2.1.193/2.1.195 background-agent thread and harden the
  Step-5 fan-out and the long unattended autopilot run.
- **Background-job conversation-deletion fix** (ADR-0016 addendum, ADR-0020 addendum): CC
  2.1.196 fixed waking a background job permanently deleting its conversation and re-running
  the original prompt when the transcript probe misread a real transcript; the file is now
  set aside, never deleted. This is a data-loss fix on the background path Step 5 and
  autopilot depend on.
- **Duplicate-recap / StructuredOutput fix** (ADR-0016 addendum): CC 2.1.196 stopped a
  schema-rejected StructuredOutput attempt rendering alongside its retry after a background
  turn. This touches the `step5-report.json` handoff, which is StructuredOutput-backed.
- **Stream idle watchdog on by default** (sec. 10): CC 2.1.196 turned the streaming idle
  watchdog on by default for all providers; it aborts and retries when a response stream
  produces no events for 5 minutes, disabled with `CLAUDE_ENABLE_STREAM_WATCHDOG=0`. This
  was a documented session-env recommendation (alongside `CLAUDE_CODE_RETRY_WATCHDOG`) and is
  now a platform default that benefits long Workflow and autopilot runs.

Verified, not assumed: the CC 2.1.196 MCP self-approval hardening (`claude mcp list`/`get` no
longer spawn `.mcp.json` servers a repo self-approved via a committed `.claude/settings.json`;
untrusted workspaces show `⏸ Pending approval`) aligns with the sec. 9 MCP posture and the
sec. 10 layered-permission model. The context7 server this system ships is unauthenticated and
not committed-self-approved, so there is no behavior change; the item is recorded as upstream
hardening consistent with the design.

Out of scope (no blueprint impact): the `/code-review` finder-merge token cut (skill-internal,
roughly −25%); `claude agents` side-panel UX fixes (focus, subagent-type retention, status
labels); `/context` showing 0 tokens on Bedrock (not this stack); voice-dictation, PowerShell
`git diff`/`grep` exit-code, and MCP-OAuth `scopes_supported` fixes; the single-`←` agents-view
open. `staging/` is unchanged this pass, deliberately. Source:
`code.claude.com/docs/en/changelog.md` v2.1.196, v2.1.197.

### Audit 2026-07-02 (CC 2.1.198)

Changelog reconciled with the blueprint. Source note: the online pages at `code.claude.com/docs`
still end at 2.1.196, so this pass verifies against the changelog bundled with the installed CLI at
`~/.claude/cache/changelog.md`, the local primary source for 2.1.198. Two items below contradict the
current online pages, which have not caught up; the bundled changelog confirms both as real changes.

- **`claude agents` launcher now auto-commits, pushes, and opens a draft PR on worktree finish**
  (ADR-0022 addendum): a background agent launched from `claude agents` commits, pushes, and opens a
  draft PR when it finishes code work in a worktree, rather than stopping to ask. This is the
  standalone launcher, a separate path from nightly-autopilot (skill + `/goal` + Agent/Workflow
  dispatch) and from the `coder` sub-agent (Agent-tool, `isolation: worktree`); neither of those
  auto-pushes. The ADR-0022 boundary holds. The guardrail (never drive nightly or autopilot through
  `claude agents`) is recorded in the ADR-0022 addendum.
- **Explore now inherits the session model, capped at opus** (sec. 3.10; was Haiku): the built-in
  Explore agent no longer runs on Haiku by default. Broad Explore fan-out is no longer
  cheap-by-default and now tracks the session model on cost.
- **Subagents and compaction inherit the session extended-thinking config** (sec. 3.10): delegated
  tasks and context compaction now carry the session thinking budget, which improves output quality
  on dispatched work. No config change here.
- **Transient network drops retry with backoff** (sec. 10): a brief mid-response drop such as
  ECONNRESET no longer aborts the turn; it retries with backoff. This narrows the stream and retry
  watchdogs to true hangs and promotes the earlier assumed transient-retry item toward verified.
- **Workflow worktree edit-block fixed** (ADR-0016 addendum): Workflow agents spawned with
  `isolation: 'worktree'` in background sessions were blocked from editing files inside their own
  worktree; resolved. Removes a latent no-edit failure mode on the Step-5 Workflow coder path.
- **Agent messages stay task direction, never approval** (sec. 4, boundary): 2.1.198 restates that a
  message from the launching agent is normal task direction and never counts as the user's approval.
  This is external confirmation of the HITL invariant the system already enforces.
- **New Notification events `agent_needs_input` and `agent_completed`** (sec. 7): they fire for
  `claude agents` sessions that need input or finish. Our nightly path is skill + `/goal`, not a
  `claude agents` background session, so the events are available but not wired; recorded for a
  revisit if nightly ever runs under `claude agents`.
- **Agent-teams resilience and plan-mode read-only auto-allow** (sec. 2, sec. 11): a teammate that
  dies on an API error now reports "failed" to the lead, and messaging a stuck teammate wakes it to
  retry; plan mode now auto-allows read-only tool calls when a session starts in plan mode, matching
  the interview and plan gates. Both are one-line behavior notes with no change here.
- **`/agents` wizard removed** (sec. 16): the interactive wizard is gone; subagents are managed by
  asking Claude or by editing `.claude/agents/` directly. The command table and the two guides are
  corrected accordingly.

Verified, not assumed: the `.claude/rules/` symlink-path fix (conditional rules failing to load when
the target is reached through a symlink) does not affect this system. Rules deploy by copy through
`sync-to-claude.sh`, never by symlink. `staging/` is unchanged this pass, deliberately. Source:
`~/.claude/cache/changelog.md` (bundled CC 2.1.198); online `code.claude.com/docs` still at 2.1.196.

Out of scope (no blueprint impact): Claude in Chrome general availability, the `/dataviz` skill, the
AWS gateway provider and its failover, AWS/Mantle STS auto-refresh, the markdown-table fullscreen
fix, SSH shortcut labels, highlight.js 11, the `--bg` plus `--print` conflict guard, the
background-task "Running" unstick, classifier throttling, `/diff` refresh on branch switch, and
`/branch` fork-name derivation.

### Audit 2026-07-03 (CC 2.1.199–2.1.200)

Changelog range 2.1.199–2.1.200 reconciled with the blueprint. Source: the changelog bundled with the installed CLI at `~/.claude/cache/changelog.md`; the installed version is 2.1.200. The online pages at `code.claude.com/docs` still lag, so the bundled changelog is the primary source for both releases. Two behavior changes touch the HITL and permission model directly; the rest harden the multi-agent chain and the overnight path.

- **`AskUserQuestion` no longer auto-continues by default** (sec. 4, sec. 10, sec. 11): CC 2.1.200 makes every AskUserQuestion dialog block until the user answers; an idle timeout is now opt-in via `/config`. This matches the system's "NEVER auto-answer a gate" invariant: the commit gate, the concept-to-code gates, and the autopilot pre-flight gates are now hard-block by default with no config work. One distinction to keep straight: the "No response after N seconds, proceed" fallback seen in agent-driven (headless/SDK) runs is a runtime-harness behavior, not the `/config` idle timeout, and is not governed by this setting. Source: `~/.claude/cache/changelog.md` v2.1.200.
- **Default permission mode renamed "default" to "Manual"** (sec. 10): CC 2.1.200 renames the mode across the CLI, `--help`, VS Code, and JetBrains; `--permission-mode manual` and `"defaultMode": "manual"` are accepted alongside the old `default`. The blueprint's strategy is unchanged (acceptEdits as working default, explicit plan mode for new features); only the label for the base mode moves. Existing `default` values keep working. Source: v2.1.200.
- **Subagents now propagate API errors instead of reporting false success** (sec. 3.10, ADR-0016/0020/0022): CC 2.1.199 fixes two failure modes at once. A subagent that hit an API error such as "usage limit reached" used to return a successful-looking result; it now reports the error to the parent. A subagent cut off by a rate limit or server error used to fail silently; it now returns its partial work. This directly hardens the Step-5 Workflow and Agent dispatch and the unattended autopilot: an orchestrator can no longer proceed on a subagent's false "done" after a quota or capacity failure. It also bears on model-quota exhaustion, for example an agent pinned to a promo model that runs dry mid-chain. Promotes the earlier assumed subagent-error behavior toward verified. Source: v2.1.199.
- **Project-scoped plugins and skills now load in git worktrees** (ADR-0016): CC 2.1.200 fixes project-scoped plugins not loading from a git worktree of the same repository. The `coder` sub-agent runs with `isolation: worktree`, and the Step-5 Workflow coder path uses worktrees; skills and plugins now resolve there as in the main tree. Removes a latent gap on the worktree coder path, alongside the 2.1.198 worktree edit-block fix. Source: v2.1.200.
- **Hook stderr on exit code 2 is now shown** (sec. 7): CC 2.1.199 fixes `SessionStart`, `Setup`, and `SubagentStart` hooks silently hiding stderr when they exit 2. The system's hook stack (pattern-enforce ADR-0001, stop-gate, session-context-inject, chain-memory ADR-0021) becomes easier to debug: a blocking hook's own diagnostics now reach the transcript. Source: v2.1.199.
- **`claude stop` is honored over a concurrent respawn; retry watchdog widened** (ADR-0022, sec. 10): CC 2.1.199 stops a background agent from being silently respawned after `claude stop`, which tightens the nightly-guard stop path. The same release raises `CLAUDE_CODE_RETRY_WATCHDOG`'s default retry count to 300 and lifts the 15-cap on `CLAUDE_CODE_MAX_RETRIES` for non-capacity transient errors, and retries unrelated 429s with backoff for subscribers. This continues the 2.1.198 transient-retry note toward verified. Source: v2.1.199.
- **`SendMessage` detects a reused agent name** (sec. 2, agent-teams): CC 2.1.199 fixes SendMessage misrouting when a respawned agent reuses a previous agent's name; it now flags the mismatch and asks the caller to retarget. Relevant only to the agent-team topology, not the flat sub-agent path. Source: v2.1.199.
- **Stacked slash-skill invocations load up to 5 leading skills** (sec. 8): CC 2.1.199 makes `/skill-a /skill-b do XYZ` load all leading skills, not just the first. Available for composing skill chains; no change required. Source: v2.1.199.
- **Plan mode now prompts for state-changing browser calls** (sec. 10, sec. 11): CC 2.1.199 fixes plan mode not gating state-changing browser tool calls while auto-allowing read-only `browser_batch`. Complements the 2.1.198 plan-mode read-only auto-allow. Source: v2.1.199.

Background-session reliability (sec. 7, ADR-0022): CC 2.1.200 fixes a cluster of background and daemon failures relevant to the overnight path: sessions stopping after sleep/wake, an Esc-cancelled turn re-running after a stall respawn, a stale `daemon.lock` with an OS-reused PID blocking restart, daemon handover now judged by build timestamp, and roster corruption. No config change; the nightly-autopilot runtime holds up better unattended.

Out of scope (no blueprint impact): startup crash on a non-array `disabledMcpServers`/`enabledMcpServers`, tmux 3.4+ flicker, screen-reader and decorative-glyph improvements, voice-dictation no-audio message, control bytes in the agent view, `claude agents --plugin-dir` flag ordering, `/mcp` list focus for assistive tech, the install-script OOM message, config-recovery backup-before-reset, the Chrome reconnect-page loop, `claude --dangerously-skip-permissions daemon <subcommand>` parsing, `claude agents` PR-link label, transcript growth on a no-new-message resume, background job progress stalls, memory-starved session messages, the Linux daemon ~50s self-kill (macOS host here), and the SSH cold-start audit-session regression (no SSH launch here). Source: `~/.claude/cache/changelog.md` (bundled CC 2.1.199–2.1.200); online `code.claude.com/docs` still behind.

### Audit 2026-07-07 (CC 2.1.201–2.1.202)

Changelog range 2.1.201–2.1.202 reconciled with the blueprint. Source: the changelog bundled with the installed CLI at `~/.claude/cache/changelog.md`; the installed version is 2.1.202. The online pages at `code.claude.com/docs` still lag, so the bundled changelog is the primary source. No skill or chain file needs a code change: every relevant item is a platform-internal fix (pure benefit) or an advisory setting. Two items touch documented behavior directly; the rest harden the workflow and background paths.

- **`/review <pr>` reverted to a single-pass review** (sec. 16, this section supersedes the 2.1.186 audit note): CC 2.1.202 changes `/review <pr>` back to a fast single-pass review and reserves the multi-agent path for `/code-review <level> <pr#>`. This reverses the earlier "`/review <pr>` now matches `/code-review medium`" note in the Audit 2026-06-23 (CC 2.1.186) block. No system impact: the fix/review skills (`review-triage-fix`, `code-review-checklist`) drive the `reviewer` agent and the `code-review` skill explicitly, never the bare `/review <pr>` alias, and the `/code-review ultra <PR#>` multi-agent cloud path is unaffected. Source: `~/.claude/cache/changelog.md` v2.1.202.
- **"Dynamic workflow size" `/config` setting** (sec. 10, ADR-0016): CC 2.1.202 adds a `/config` control for how large Claude generally makes dynamic workflows (small/medium/large agent counts). It is explicitly an advisory guideline, not an enforced cap, so it co-exists with ADR-0016's hard limits (16 concurrent, 1000 total per run) and does not relax them. Useful to bound Step-5 fan-out cost by default; the ADR-0016 caps and the Agent-tool fallback are unchanged. Source: v2.1.202.
- **Workflow script parse reliability** (ADR-0016): CC 2.1.202 fixes workflow scripts with unicode quote escapes being corrupted before parsing, and makes parse errors show the offending line instead of always blaming TypeScript. The Step-5 workflow script is generated by Claude, so this narrows a latent script-corruption failure mode on the dispatch path; the existing parse-failure fallback (Agent-tool batch dispatch when `step5-report.json` is absent) still covers any residual parse failure. Source: v2.1.202.
- **Re-invoking a loaded skill no longer duplicates its instructions** (sec. 8): CC 2.1.202 stops a re-invoked skill from appending a second copy of its instructions to context. Pure benefit to any chain that re-enters a skill in one session (`project-conductor` resuming, `nightly-autopilot`, a second `humanize-en` or `commit` pass): it removes a hidden per-re-invocation token cost. No change required. Source: v2.1.202.
- **Workflow OpenTelemetry attributes** (sec. 10, OTEL security note): CC 2.1.202 adds `workflow.run_id` and `workflow.name` attributes to telemetry from workflow-spawned agents, so a Step-5 workflow run can be reconstructed from OTel data. Observability-only; same handling as the 2.1.193 `assistant_response` log-event note (telemetry is opt-in and stays off unless explicitly enabled). Source: v2.1.202.
- **CC 2.1.201 — Sonnet 5 harness-reminder delivery** (no blueprint impact): CC 2.1.201 stops Sonnet 5 sessions using the mid-conversation system role for harness reminders. This is an internal reminder-delivery change; it does not alter hook propagation, the pattern-enforce contract, or agent behavior. The system's Sonnet-tier agents (coder, reviewer, tester, debugger, refactorer) are unaffected. Source: v2.1.201.

Background and worktree reliability (sec. 7, ADR-0016, ADR-0022): CC 2.1.202 fixes several items on the background and worktree paths the overnight and worktree-coder flows rely on: opening a chat from `claude agents` failing with "currently running as a background agent" followed by a worker crash/respawn loop, resuming a session by name (or the resume picker) taking minutes and large memory in repositories with many git worktrees, and `/rename` on a background session being reverted on job restart. No config change; the nightly-autopilot runtime and the `isolation: worktree` coder path hold up better unattended.

Out of scope (no blueprint impact): the inline Ctrl+R history-search crash, transient mTLS handshake failures during client-cert rotation, Remote Control "Unknown command" and dropped uncaptioned images/files, the wrong permission mode shown in `/remote-control` mobile/web, the SSH-wrapped sign-in URL not being clickable, unbounded voice-dictation retry on mic failure, installer/updater "aborted" retry on mid-download network drops, the `/workflows` agent-list layout polish, and the MCP `url`-without-`type` error-message improvement. Source: `~/.claude/cache/changelog.md` (bundled CC 2.1.201–2.1.202); online `code.claude.com/docs` still behind.

### Audit 2026-07-08 (CC 2.1.203–2.1.204)

Changelog range 2.1.203–2.1.204 reconciled with the blueprint. Source: the changelog bundled with the installed CLI at `~/.claude/cache/changelog.md`, cross-checked against the upstream `CHANGELOG.md`; the installed version is 2.1.204. This range is almost entirely a hardening pass on the background-agent, worktree-isolation, and headless-hook paths the overnight and Step-5 flows depend on: every item is a platform-internal fix (pure benefit), so no skill or chain file needs a code change. Two items carry a correctness or reliability weight worth stating precisely.

- **Worktree-isolated subagents no longer run shell commands in the parent checkout** (sec. 3.10, sec. 11, ADR-0016): CC 2.1.203 fixes worktree-isolated subagents that sometimes executed Bash in the parent checkout instead of their own worktree. The `coder` sub-agent runs with `isolation: worktree` and the Step-5 workflow coder path uses worktrees, so before the fix a coder's shell steps (test runs, shell-driven edits) could have touched the main tree and mis-attributed the `step5-report.json` file list. This is a correctness fix, not a convenience one; it closes the last known worktree-shell gap alongside the 2.1.198 edit-block and 2.1.200 plugin-load fixes. Source: `~/.claude/cache/changelog.md` v2.1.203.
- **Headless `SessionStart` hooks no longer idle-reap the worker mid-hook** (sec. 7, ADR-0022): CC 2.1.204 fixes hook events not streaming during `SessionStart` hooks in headless sessions, which could get a remote or background worker idle-reaped in the middle of the hook. The system runs a `SessionStart` hook (session-context-inject, chain-memory surfacing) that fires in every session including the headless `nightly-autopilot` and `autopilot-build` runs, so this removes a real unattended-failure mode on the overnight path. Distinct from the ADR-0016 `hook_verified` blocker, which concerns `PreToolUse`/`PostToolUse` propagation inside Workflow subagents — a different hook event in a different context, and still open. Source: v2.1.204.
- **Forked background sessions honor `effortLevel` from settings.json** (sec. 3.9, sec. 3.10): CC 2.1.203 fixes background sessions ignoring `effortLevel` changes when forked through the daemon. This complements the 2026-06-23 workflow model-pinning note: a workflow subagent dispatched with an explicit `effort` (or reading the settings default) now gets it honored even on the forked background path, so per-agent reasoning effort holds in Step-5/6 dispatch. Source: v2.1.203.
- **`TaskStop`/`TaskOutput` resolve agents spawned by another agent** (ADR-0016): CC 2.1.203 fixes these failing to find background agents spawned by another agent, and errors now list running agents by id and description. This hardens the Workflow orchestrator's inspect and kill path for nested dispatch; no contract change, the `step5-report.json` handoff and the Agent-tool fallback are unchanged. Source: v2.1.203.
- **Subagents are less likely to re-delegate their whole task** (sec. 2, sec. 2.2): CC 2.1.203 makes an agent less likely to hand its entire task to another subagent. This reinforces the blueprint's flat "sub-agents do NOT spawn sub-agents" invariant natively rather than by convention alone; the design is unchanged, the platform default now leans the same way. Source: v2.1.203.
- **Login-expiry warning before background sessions are interrupted** (ADR-0022, RUNBOOK): CC 2.1.203 adds a warning when the login is about to expire, so a re-authentication can happen before background sessions break. Relevant to long overnight runs; the RUNBOOK pre-flight (fresh auth before launch) stays the primary control since the warning is interactive, but it narrows the window where an expiring login silently halts a nightly run. Source: v2.1.203.

Background and daemon reliability (sec. 7, ADR-0022): CC 2.1.203 fixes a large cluster the unattended path relies on — a background daemon auto-upgrade failure silently killing all running sessions, background agents crash-looping when their working directory is deleted or replaced (now one clean error), a stale daemon session token now auto-recovering instead of leaving the session permanently unresponsive, `claude agents` no longer silently stopping running subagents and re-running from scratch on return, and worktree creation no longer rejecting nested repositories in multi-repo workspaces. No config change; the nightly-autopilot and worktree-coder runtimes hold up better unattended.

Out of scope (no blueprint impact): the Windows-only stale-`PATH` and dropped-`ANTHROPIC_BASE_URL` background fixes (macOS host here, no custom base URL), the `argument list too long` Bash fix in many-worktree repos, assorted `claude agents` view and composer fixes, the grey ⏸ manual-mode footer badge, MCP `roots/list` additional-working-directories exposure, the ~7 MB binary and startup-memory reduction, the context-usage indicator CPU regression fix, transcript-scroll and bash-mode flicker fixes, the reattach escape-code and `/clear` empty-output-on-Windows fixes, LSP-only plugin disuse-flagging, and the `[VSCode]` remote-control toggle. Source: `~/.claude/cache/changelog.md` (bundled CC 2.1.203–2.1.204), cross-checked against upstream `CHANGELOG.md`; online `code.claude.com/docs` still behind.

### Audit 2026-07-09 (CC 2.1.205)

Changelog range 2.1.205 reconciled with the blueprint. Source: the changelog bundled with the installed CLI at `~/.claude/cache/changelog.md`, cross-checked against the upstream `CHANGELOG.md`. Note on versions: the installed CLI reports `2.1.206`, but upstream has published no changelog entry, no git tag, and no GitHub release for it — tags stop at `v2.1.205`. The 2.1.206 binary shipped ahead of its notes, so it is deliberately **not** covered here and must be reconciled once Anthropic publishes them. This range is a guardrail-and-observability release: the two new auto-mode rules and the notification-provenance fix land on the permission strategy (sec. 10) and on the unattended path, while the rest is agent-view and platform-internal polish. Every item is a platform-internal fix or a native guardrail (pure benefit), so no skill, hook, or chain file needs a code change. One item carries real safety weight for the unattended flows and is stated precisely first.

- **Fabricated in-transcript approvals can no longer be acted on** (sec. 10, ADR-0020, ADR-0022): CC 2.1.205 makes background task notifications explicitly state that no human input has occurred, so an agent cannot read a synthesized notification as though a human had approved something. This is upstream hardening for exactly the failure mode the unattended ADRs were designed around. The defense in this system has always been structural — `autopilot-build` takes only local reversible actions, `nightly-autopilot` publishes only behind a committed per-repo opt-in marker, and neither treats any in-transcript text as authorization — so the boundary is unchanged. What changes is that the same hole is now also closed at the notification layer: a second, independent barrier under the first. The HITL gates (commit, push, deploy, schema change, permanent deletion) and the `AskUserQuestion` contract are untouched. Source: `~/.claude/cache/changelog.md` v2.1.205.
- **Auto mode blocks tampering with session transcript files** (sec. 10, sec. 7): CC 2.1.205 adds an auto-mode rule denying writes to session transcript files. The transcript is the audit record an unattended run leaves behind, and `protect-files.sh` plus the hook-deny rules already guard the sensitive paths this system cares about. The layered-defense posture (hook-deny overrides any permission mode) is unchanged; the outermost layer now covers transcripts natively rather than by convention. Source: v2.1.205.
- **Auto mode asks before `rm -rf` on an unresolved variable** (sec. 10, sec. 7): CC 2.1.205 makes auto mode prompt before running `rm -rf` on a variable it cannot resolve from context. This is native coverage of ground the destructive-command guardrail already holds (never run `rm -rf` or `DROP TABLE` without asking). It narrows the blast radius of an unattended run without displacing the hook-level deny, which stays authoritative. Source: v2.1.205.
- **The `--json-schema` fix is the headless CLI flag, not Workflow `agent({schema})`** (ADR-0016): CC 2.1.205 fixed `--json-schema` silently producing unstructured output when the schema was invalid, and schemas using the `format` keyword being rejected. This concerns the headless CLI flag. Workflow structured output — `agent(prompt, {schema})`, which validates at the tool-call layer and makes the subagent retry on mismatch — is a separate mechanism. Step 5 does not depend on `--json-schema` (it hands off through `.claude/step5-report.json`), so this is informational and must not be read as touching the workflow path. Source: v2.1.205.
- **Session-to-PR linking now catches a PR opened from a large Bash call** (ADR-0022, RUNBOOK): CC 2.1.205 fixed session-to-PR linking missing a PR created in a Bash call whose output exceeded the 30K inline limit. `nightly-autopilot` opens each feature PR with `gh pr create` in Bash, and a verbose `gh` invocation can cross that limit, so overnight PRs previously risked not appearing linked in `claude agents`. Observability only; the `NIGHTLY-PUBLISH` status line and `nightly-report.json` remain the authoritative morning record. Source: v2.1.205.
- **`/doctor` is now a full setup checkup, `/checkup` its alias** (RUNBOOK): CC 2.1.205 turned `/doctor` into a setup checkup that can diagnose and fix issues. Useful as a pre-flight before the one-time per-repo bootstrap, where a broken hook path or an unauthenticated `gh` surfaces cheaply. Not a launch precondition; the RUNBOOK pre-flight checks stay the primary control. Source: v2.1.205.

Agent-view observability (ADR-0022, RUNBOOK): CC 2.1.205 improves the morning read of an overnight run. Rows now show a colored state word and a classifier-written headline instead of raw tool-call text, and the peek opens with full status including the exact ask for a blocked session; sessions that edit, merge, comment on, or push to an existing PR now link it; background agents no longer stay shown as "failed" or "completed" after being resumed with `SendMessage`; background jobs no longer flip from "needs input" back to "working" when a turn contained no readable text; `claude attach` waits for a background agent mid-upgrade-restart instead of erroring; and Remote Control panels no longer show a stale "Running" status. A halted nightly run is faster to triage. No config change, no contract change.

Still open, not resolved by this range: the ADR-0016 `hook_verified` blocker. No 2.1.205 item addresses `PreToolUse`/`PostToolUse` hook propagation inside Workflow subagents, so the Step-5 smoke test gating the workflow path (and the Agent-tool fallback when `hook_verified=false`) remains required exactly as before. The smoke test was deliberately not re-run for this range. All items above are assumed-not-verified-live.

Out of scope (no blueprint impact): the Windows-only fixes (worktree removal deleting files outside the worktree across an NTFS junction or directory symlink, the crash when the launch directory is deleted/locked/unmounted mid-command), the message silently lost when a turn ended at the `--max-turns` limit, the `claude mcp add-from-claude-desktop` hang on a server name with unsupported characters, the plugin LSP server whose failed initialization blocked a valid LSP server from another plugin, the crash when a file watcher closed during an in-flight directory scan, project verify skills being rewritten every session, the agent view rendering one line too high, the ~400 MB peak-memory reduction in the auto-update binary download, the reserved "Claude Browser" MCP server name, and the Cowork VM-mode local-agent login failure on CLI 2.1.203+. Source: `~/.claude/cache/changelog.md` (bundled CC 2.1.205), cross-checked against upstream `CHANGELOG.md`; online `code.claude.com/docs` still behind.

### Audit 2026-07-09 (loop taxonomy: `/loop`, `/schedule`, Routines)

Prompted by "Getting started with loops" (@delba_oliveira on the @ClaudeDevs account, 2026-07-06), which sets out the Claude Code team's own taxonomy of agent loops. The article is secondary source material; every claim below was checked against the primary docs — `code.claude.com/docs/en/goal`, `/en/scheduled-tasks`, `/en/routines` — fetched 2026-07-09. Where the two differ, the docs win. The taxonomy itself is a lens, not a spec, and it is worth adopting because it names four things this blueprint already builds and one it never mentions.

**The four loop types.** *Turn-based*: one user prompt, Claude judges completion; the verification step is improved by encoding it as a skill. *Goal-based*: `/goal`, for tasks with a verifiable exit criterion and an explicit turn cap. *Time-based*: `/loop` on an interval locally, or `/schedule` to move the routine to Anthropic-managed cloud infrastructure. *Proactive*: no human in real time, composed from a schedule trigger, `/goal` for the done-condition, skills for verification, dynamic workflows for orchestration, and auto mode so the run does not stop for permission.

The last one is worth stating plainly: **the overnight path in ADR-0022 is a "proactive loop" under the team's own taxonomy**, and the recipe the article gives for that type is the composition this system arrived at independently — schedule the run, define done with `/goal`, verify with skills, orchestrate with workflows. That is convergence, not a correction. The article's own table nonetheless categorizes goal-based loops as "triggered by a manual prompt in real time"; that is a simplification of the taxonomy, not a constraint, since the docs explicitly support headless `/goal` via `claude -p`.

- **A scheduled `/loop` fire does not execute manual-only skills** (sec. 8, sec. 8.1, sec. 16): from CC v2.1.196, a scheduled fire only runs skills Claude is allowed to invoke on its own. Skills marked `disable-model-invocation: true` — along with built-in commands such as `/permissions` or `/clear`, skills withheld by a `skillOverrides` setting or a `Skill` deny rule, and MCP prompts — **reach Claude as plain text instead of executing**. Three staged skills carry that flag (`interview-driver`, `project-bootstrap`, `fastapi-react-vibe`), so `/loop 20m /interview-driver …` would silently do nothing but paste a string. This is a live trap, not a theoretical one. Source: `/en/scheduled-tasks`.
- **`/loop` tasks are session-scoped and expire** (sec. 16): recurring tasks fire one last time and delete themselves **seven days** after creation. Tasks fire only while Claude Code "is running and idle" — closing the terminal stops them, though backgrounding the session carries them over. There is no catch-up for a missed fire. A session holds at most 50 scheduled tasks. Sources: `/en/scheduled-tasks`.
- **`/loop` has three shapes and a config file** (sec. 8.1): interval plus prompt runs on a fixed cron; prompt alone lets Claude pick the delay each iteration (1 min to 1 hour) based on what it observed; neither runs a built-in maintenance prompt, overridable by `.claude/loop.md` (project) or `~/.claude/loop.md` (user). For a dynamic loop the **Monitor tool** is often the better primitive: it streams a background script's output instead of re-running a prompt on an interval, which is cheaper and more responsive than polling. Source: `/en/scheduled-tasks`.
- **`CLAUDE_CODE_DISABLE_CRON=1` removes the scheduler entirely** (sec. 7, sec. 10): the cron tools and `/loop` become unavailable and already-scheduled tasks stop firing. Worth knowing alongside `disableAllHooks`, which separately disables `/goal`. Source: `/en/scheduled-tasks`, `/en/goal`.
- **`/schedule` and Routines are a primitive this blueprint has never covered** (new; ADR-0022): a routine is a saved Claude Code configuration — prompt, repositories, connectors — that runs on Anthropic-managed cloud infrastructure on a schedule, on an API call, or on a GitHub event. **Research preview.** Created at `claude.ai/code/routines` or from the CLI with `/schedule`. Available on Pro, Max, Team, and Enterprise plans with Claude Code on the web enabled. Minimum interval one hour. Each repo is cloned fresh on every run from its default branch, Claude may push only to `claude/`-prefixed branches unless unrestricted pushes are enabled, and the run is fully autonomous: "there is no permission-mode picker and no approval prompts during a run." A routine sees only skills **committed to the cloned repository**, not `~/.claude/`. Evaluated against the overnight design and **not adopted** — reasoning in ADR-0022. Source: `/en/routines`.
- **`/schedule` requires a claude.ai subscription login** (sec. 10, ADR-0022): the docs list a Console API key, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `apiKeyHelper`, or a Bedrock/Vertex/Foundry provider as reasons the command is hidden. Recorded because a widely-circulated third-party skill attributes this same requirement to `/goal`, where it is false. The requirement is real, but it belongs to `/schedule`. Sources: `/en/routines`, `/en/goal`.

Token discipline (sec. 3.10, ADR-0016): the article's operational rules are consistent with this system's existing posture and worth stating. Pilot a dynamic workflow on a small slice before a large run, because a workflow "can spawn hundreds of agents". Prefer a script to reasoning through deterministic steps, since running a script is cheaper than re-deriving it. Match a routine's interval to how often the watched thing actually changes. Three inspection paths: `/usage` breaks spend down by skill, subagent, and MCP (already at sec. 16); a bare `/goal` reports turns and tokens spent so far; `/workflows` shows each agent's token usage and can stop an agent mid-run. The last two are new to this document.

Out of scope (no blueprint impact): the cron expression reference and vixie-cron day-of-week semantics, scheduler jitter (recurring tasks fire up to 30 minutes late, one-shots up to 90 seconds early, offset derived from the task ID), one-time natural-language reminders, the `CronCreate`/`CronList`/`CronDelete` tool triple, routine API triggers and their `experimental-cc-routine-2026-04-01` beta header, routine GitHub triggers and their PR filter fields, cloud-environment network allowlists, and the Bedrock/Vertex/Foundry `/loop` fallbacks. Sources: `code.claude.com/docs/en/scheduled-tasks` and `/en/routines` (both fetched 2026-07-09), plus the @ClaudeDevs article of 2026-07-06 as the prompt for this audit.

### Correction 2026-07-11 (project-bootstrap retired from staging)

`docs/specs/29-refresh-stale-staging-copies-from-the-de.spec.md` (issue #29, ADR-0025) confirms
`project-bootstrap` is no longer present in the deployed skill tree (`~/.claude/skills/`) and removes the
retired skill from `staging/plugin/skills/`. Two prose references are corrected here; `staging/plugin/agents/`,
the seven repo-native `SKILL.md` files, and `staging/user/` are refreshed from the deployed tree in the same
issue (staleness tracked since ADR-0022's `staging/` bridge; ADR-0024 covered the first, larger vendoring pass).

- Sec. 14 packaging note (~line 2282) now lists the 6 remaining field-tested skills from sec. 8.3
  (`interview-driver`, `adr-writer`, `claude-md-generator`, `swift-vibe`, `fastapi-react-vibe`,
  `code-review-checklist`); `project-bootstrap` dropped from both the count and the list.
- Sec. 15 installation checklist (~line 2297) drops `project-bootstrap` from the custom-skills list.
- Sec. 8.3's per-skill design catalog (~line 1650) and sec. 8.6's deployed-skills table are left untouched by
  design: 8.3 documents what was designed (historically accurate, not a live-status claim) and 8.6 already
  omits `project-bootstrap`. Also out of scope for this correction: `docs/RUNBOOK.md`'s own stale count
  comments (Steps 4, 7, 8) and the global-CLAUDE.md template at sec. 4 (~line 970), which is illustrative
  content, not this system's live configuration.

### Correction 2026-07-11 (backup-before-deploy.sh retired from staging)

`docs/specs/38-hook-hardening-enum-value-lock-ownership.spec.md` (issue #38, ADR-0034) confirms
`backup-before-deploy.sh` was never vendored into `staging/plugin/scripts/` by ADR-0024's vendoring
pass: its body is a hardcoded one-shot backup dated 2026-05-19, and it is wired to no hook event in the
deployed `settings.json`. It is retired; `docs/RUNBOOK.md` and `staging/sync-to-claude.sh`'s PAIRS table
name no further deploy path for it, and `staging/sync-to-claude.sh` now carries a MANUAL STEP note for a
human to review and delete the deployed-side copy (`~/.claude/hooks/backup-before-deploy.sh`) — this
repo does not write under `~/.claude`.

Deliberately **not** touched, and stated here so it is not later mistaken for an omission: sec. 7.6's
`AS-BUILT 2026-05-19` hook filesystem tree (`~line 1437`) and
`docs/architecture/ADR-0005-vibe-status-skill.md`'s own Q5 example report (`~line 201`) both name
`backup-before-deploy.sh`; both are dated, point-in-time illustrations, not live-status claims (the same
category the correction immediately above already applied to sec. 8.3's design catalog). ADR-0034 is
the amendment of record for this staleness, consistent with the precedent ADR-0033 already set for
`ADR-0005` itself (amended by reference, never edited in place). A repo-wide grep for
`backup-before-deploy` confirms these are its only two mentions anywhere in this document or in
`ADR-0005`; sec. 15's installation checklist and sec. 8.6's "Deployed custom skills" table — the two
locations this document's own convention treats as live-status claims — never named a hook at all, so
there is nothing to correct there.

### Correction 2026-07-11 (issue #40, agent tool scoping reconciliation)

`docs/specs/40-agent-tool-scoping-per-blueprint-section.spec.md` (issue #40, ADR-0036) reconciles four
places where `staging/plugin/agents/{architect,reviewer,researcher}.md` (byte-identical to the deployed
`~/.claude/agents/` copies -- confirmed by diff before this correction) had drifted from sec. 3 with no
recorded reason:

- **architect Bash scope** (sec. 3.1): was fully unrestricted `Bash`; now `Bash(git *), Bash(rg *)`
  (restored, matching the example above verbatim) plus `Bash(bash *), Bash(npx markdownlint-cli2*), Bash(npx --yes markdownlint-cli2*), Bash(python3 *),
  Bash(shasum *)` (a deliberate widening beyond the example, for the verification-by-execution this
  roadmap's own architect dispatches routinely use) -- see the deployment note under sec. 3.1.
- **architect `permissionMode: plan`** (sec. 3.1): was already absent from the deployed file; confirmed
  **not** restorable without breaking every unattended architect dispatch -- verified live against
  `code.claude.com/docs/en/agent-sdk/permissions` (fetched 2026-07-11), plan mode blocks all file
  writes pending manual approval regardless of allow rules, and architect's sole deliverable is writing
  the ADR and the plan. Deliberate divergence, recorded rather than silently left unexplained.
- **architect `effort`** (sec. 3.10): was `max`; restored to `xhigh` -- `max` does not persist in
  file-based agent configuration (`code.claude.com/docs/en/model-config`, fetched 2026-07-11), so the
  deployed value was very likely inert.
- **reviewer Bash scope** (sec. 3.3): was fully unrestricted `Bash`; now `Bash(git diff*), Bash(git
  log*)` (restored verbatim, still no `git add`/`git commit`) plus `Bash(bash *), Bash(awk *),
  Bash(python3 *)` for the same verify-by-execution need, narrower than architect's set since reviewer
  processes untrusted diff content -- see the deployment note under sec. 3.3.
- **researcher `mcpServers`** (sec. 3.8, sec. 3.9): the inline example was already syntactically stale
  -- current docs (`code.claude.com/docs/en/sub-agents`, fetched 2026-07-11) show a YAML **list**
  syntax with an explicit `type: stdio` field, not the map-keyed form both sections showed. Corrected
  in place in both sections. The corrected block is **not** deployed to the live `researcher.md` in
  this pass -- no live smoke test is available to confirm the resulting tool-name prefix reaches the
  agent's `tools` allowlist before trusting it unattended (same smoke-test-before-deploy posture as
  ADR-0016/ADR-0029) -- the sec. 3.8 note beneath the corrected example records this and what the
  deployed file relies on instead (the global `context7` plugin, unaffected, already working).

`staging/plugin/agents/` is **not** refreshed by this correction -- the reverse of ADR-0025's usual
direction: this time the fix lands in `staging/` first and reaches `~/.claude/` only at the next human
sync, same disclosed convention as ADR-0024 through ADR-0035.

### Audit 2026-07-14 (CC 2.1.206–2.1.209)

Changelog range 2.1.206–2.1.209 reconciled with the blueprint. Source: the changelog bundled with the installed CLI at `~/.claude/cache/changelog.md` (installed version 2.1.209), cross-checked against the upstream `CHANGELOG.md` (fetched 2026-07-14). This range also closes the version-gap debt the 2026-07-09 audit recorded: Anthropic has since published the 2.1.206 notes, so 2.1.206 is reconciled here rather than left open. Character of the range: one settings-surface behavior change (`autoMode` scope), two native guardrail and validation wins (the substitution-wrapped catastrophic-removal prompt and the agent tools-list error), and a broad reliability cluster for background and headless runs. Verified against this repo before writing: no skill, hook, chain, or settings file needs a code change for this range.

- **`autoMode` is no longer read from repo-level `.claude/settings.local.json`** (sec. 10, sec. 16): from CC 2.1.207 only user-level `~/.claude/settings.json`, `--settings`, and managed settings are honored for `autoMode`. This system is unaffected: its `autoMode.allow` rules live in `staging/user/settings.json` and deploy to the user level. The generic settings-precedence list in sec. 16 must not be read as applying to this key, so a carve-out note is added there. The motivation is the same threat model as the 2.1.207 plugin fixes below: a cloned repo must not be able to widen auto mode's authority. Source: `~/.claude/cache/changelog.md` v2.1.207.
- **Catastrophic removals wrapped in `$(…)`, backticks, or `<(…)` now prompt even in auto mode and `--dangerously-skip-permissions`** (sec. 7, sec. 10, ADR-0020, ADR-0022): CC 2.1.208 extends the plain-form protection (e.g. `rm -rf ~`) to command-substitution forms, which are exactly the shapes the hook-deny layer targets. The layered-defense posture is unchanged and the hook-deny rules stay authoritative; what changes is that the outermost native layer no longer has the substitution blind spot. Consequence for the unattended paths: such a command now stalls on a prompt instead of executing silently. That is the safe direction, and ADR-0022 plus the nightly RUNBOOK record the stall shape. Source: v2.1.208.
- **The Agent tool now fails with a clear error, naming the unrecognized entries, when a subagent's `tools` list resolves to nothing** (sec. 3, ADR-0036): before CC 2.1.208 such a subagent launched silently with no tools. This validates the scoped frontmatter issue #40 shipped (`Bash(git *)`, `Bash(rg *)`, and the rest) at no cost: a typo in any entry now surfaces as a named error on first dispatch instead of a mute agent. Recommended post-upgrade action (not part of this audit): one smoke dispatch per custom agent to let the validation run once. Source: v2.1.208.
- **Plugin-hook shell-injection fix** (sec. 7): CC 2.1.207 rejects `${user_config.*}` in shell-form plugin hook, monitor, and headersHelper commands (exec-form `args` arrays or `$CLAUDE_PLUGIN_OPTION_<KEY>` are the supported paths), and plugin option values (`pluginConfigs`) are no longer read from project-level `.claude/settings.json`. Verified: no staged plugin hook uses either mechanism; informational only. Source: v2.1.207.
- **Background/overnight reliability cluster** (ADR-0016, ADR-0020, ADR-0022 addendum): the background daemon no longer fails permanently after an update replaces the binary a running `claude agents` process was launched from (2.1.208), and background agents now upgrade in the background right after a CLI update instead of paying a slow stale-session upgrade on attach (2.1.206). Completed background agents stay listed in `/tasks` until cleanup instead of vanishing (2.1.208). Session transcript size drops up to 79x in edit-heavy sessions with checkpoint disk usage bounded, 2.1.208 fixes several long-session memory leaks (MCP stdio stderr capped instead of accumulating up to 64 MB per server, LSP documents on a 50-doc LRU, tool-result payload growth in headless/SDK sessions), and the false "100% context used" indicator after a CLI auto-update is gone. This continues the background-agent hardening thread running since 2.1.193; no contract change on our side. Source: v2.1.206, v2.1.208.
- **Headless stream-json fixes** (ADR-0023 Phase P): CC 2.1.208 fixes truncated stream-json/JSON output when piping large responses from `claude -p`, sessions dying on blank CRLF lines from Windows-style SDK hosts, and headless sessions hanging permanently on a malformed `control_request`. Pure benefit for the headless design path; no change needed. Source: v2.1.208.
- **Permission-rule matchers are compiled once and cached** (sec. 10): CC 2.1.208 removes multi-second per-turn slowdowns in sessions with many deny/ask rules. This system ships a large allow/deny list in `staging/user/settings.json`, so the fix lands directly on its per-turn cost. Source: v2.1.208.
- **Malformed bracket patterns in rules globs and skill paths fixed** (sec. 5, sec. 8): CC 2.1.207 stops such patterns from breaking file reads, file suggestions, and worktree creation. Benefits the `.claude/rules/` `paths:` frontmatter mechanism; none of the staged globs use bracket patterns today. Source: v2.1.207.
- **Agent-teams mailbox crash loop fixed** (sec. 2): CC 2.1.207 stops a malformed teammate mailbox message from erroring every second until the file was deleted by hand. Stability note for the experimental agent-teams topology; the blueprint's guidance (sub-agents as the default, teams as the experimental alternative) is unchanged. Source: v2.1.207.
- **`/code-review` findings quality improved on claude-opus-4-8 at all effort levels** (sec. 16; RTF cost-pilot note): CC 2.1.206 moved the opus review baseline mid-pilot. The three-way review-triage-fix comparison (opus baseline vs sonnet-xhigh vs advisor) must record the CC version per run, or the baseline drift will contaminate the comparison. Source: v2.1.206.
- **MCP `request_timeout_ms` honored for `--mcp-config` and `.mcp.json` servers** (sec. 9): CC 2.1.206 fixes the per-server value being ignored in fresh sessions, which forced long-running MCP tool calls onto the 60s default. Relevant to any target project that tunes a slow server; the blueprint's `.mcp.json` guidance needs no change. Source: v2.1.206.

Still open, not resolved by this range: the ADR-0016 `hook_verified` blocker. No item in 2.1.206–2.1.209 addresses `PreToolUse`/`PostToolUse` hook propagation inside Workflow subagents, so the Step-5 smoke test gating the workflow path (and the Agent-tool fallback when `hook_verified=false`) remains required exactly as before. The smoke test was deliberately not re-run for this range. All items above are assumed-not-verified-live.

2.1.209 is a single-item release: it reverts an overly broad guard that blocked `/model` and other dialogs in `claude agents` background sessions. Recorded for completeness; no blueprint impact beyond restoring expected background-session behavior.

Out of scope (no blueprint impact): screen-reader mode (`--ax-screen-reader`), `vimInsertModeRemaps`, `CLAUDE_CODE_PROCESS_WRAPPER` corporate launchers, mouse-click support for multi-select menus, the Bedrock/Vertex/Foundry items (auto-mode default-on for those providers, Opus 4.8 default, SSO and credential fixes, the Windows credential-stall guard), `/usage-credits` input validation, the `/upgrade` login-flow fix, `/cd` path suggestions, the `/doctor` CLAUDE.md-trim check and Homebrew-channel fix, `/commit-push-pr` push-remote auto-allow (this system's own `/commit` skill supersedes that command), gateway `/login` endpoints, the `EnterWorktree` out-of-tree confirmation, the `/model` picker and agents-view rendering fixes, the `/release-notes` context-injection fix, and the markdown-table rendering cap. Source: `~/.claude/cache/changelog.md` (bundled CC 2.1.209), cross-checked against upstream `CHANGELOG.md` (fetched 2026-07-14).

### Correction 2026-07-14 (issue #63, native-build agent tool resolution)

The post-upgrade smoke test recommended by the audit above ran the same day and found that every
Bash-equipped agent (architect, coder, reviewer, tester, debugger, refactorer) launches without the
dedicated Grep/Glob tools its frontmatter declares, while the two Bash-less agents (doc-writer,
researcher) receive them. A forced-call probe on debugger confirmed the tools are genuinely not
registered. Root cause: CC v2.1.117 replaced Grep/Glob on native macOS/Linux builds with embedded
`bfs`/`ugrep` served **through the Bash tool**; v2.1.119 restored the dedicated tools when Bash is
absent; v2.1.162 made an explicit listing effective for the CLI `--tools` flag only. Agent
frontmatter remains silently ignored on native builds when Bash is present: intentional platform
behavior since v2.1.117, not a regression, and invisible to CC 2.1.208's tools-list validation,
which fires only when the whole list resolves to nothing. LSP does not register in subagents on
this build either, and coder's `memory: local` Memory tool (pilot P1) is observed inert.
Consequence for this document: sec. 3's frontmatter examples that list Grep/Glob next to Bash are
build-dependent, honored on npm/Windows installs and inert on the native macOS build this system
runs on. The one real defect was reviewer, whose ADR-0036 Bash scope allowed no direct `grep`/`rg`:
fixed by widening its scope with `Bash(rg *), Bash(grep *)` and making its LSP first pass
conditional. Decision record: ADR-0038.

### Audit 2026-07-15 (CC 2.1.210)

Source: `CHANGELOG.md` in the `anthropics/claude-code` GitHub repository, fetched byte-exact via
the GitHub API (`gh api repos/anthropics/claude-code/contents/CHANGELOG.md`) to rule out
summarization drift from a prompt-based fetch. `code.claude.com/docs/en/changelog.md` still lags
at 2.1.209 as of this writing, the same publish-order gap the 2026-07-09 and 2026-07-14 audits hit
with 2.1.206; GitHub's file is treated as the primary source per that precedent. The installed CLI
already reports 2.1.210, so this range is fully current, not a future release. Every relevant item
is a platform-internal fix; **no skill, hook, chain, or settings file needs a code change for this
range** (verified: no `Write(path)`/`Glob(path)` permission rules in `staging/user/settings.json`
that would trip the new startup warning, and no genuine `$1`/`$2` slash-command placeholders in any
staged skill).

- **Worktree-isolation git-mutation bug fixed** (sec. 3.2, sec. 12): CC 2.1.210 fixes
  `isolation: 'worktree'` subagents being able to run git-mutating commands against the main repo
  checkout instead of their own isolated worktree. `coder` runs with `isolation: worktree`
  (`staging/plugin/agents/coder.md`), so this closes a real gap between the isolation boundary the
  blueprint documents and what the platform actually enforced before this fix. Pure benefit; no
  action needed.
- **`ultracode` keyword no longer fires from non-human-originated input** (ADR-0016, ADR-0023
  Phase P): CC 2.1.210 fixes the `ultracode` Dynamic Workflows trigger firing on webhook payloads
  and relayed PR comments. `spec-from-issue` reads GitHub issue bodies verbatim, and
  `nightly-autopilot` processes PR activity, so a labeled issue or a bot-relayed comment
  containing the word could previously have misfired workflow orchestration unattended. Closes a
  narrow but real injection surface on both paths.
- **Hook-callback timeout no longer misreported as a user rejection** (ADR-0020, ADR-0022): CC
  2.1.210 fixes a hook callback timeout being read by the model as a user rejection, which made
  unattended sessions stop and wait for input that would never come. This is exactly the
  silent-hang failure mode those ADRs are written to guard against; see the ADR-0022 addendum
  below for what it means for the overnight path specifically.
- **Plan-mode approval-without-edits bug fixed** (sec. 4, sec. 11): CC 2.1.210 fixes a plan
  approved with no edits being mislabeled "(edited by user)" and overwriting the plan file with a
  stale snapshot. Relevant to every Standard-chain and Express/Hybrid plan-mode step in this
  system; no corresponding gap on our side, just a platform bug now closed.
- **Fable temporarily unavailable as an advisor** (sec. 16): CC 2.1.210 notes Fable is shown as
  unavailable in the `/advisor` picker while a server-side issue causing Fable advisor failures is
  fixed. Caveats the 2026-07-14 advisor-tool evaluation: the Fable+Fable pairing listed there as
  the highest-capability option is not currently usable. Temporary, tracked here only so a future
  audit knows when it resolved.

Out of scope (no blueprint impact): the elapsed-time counter on collapsed tool summaries, screen
reader mode announcing permission-mode changes, the dataviz skill's perceptual color-difference
recalibration, Grep pagination false negatives, MCP server re-sync and SDK MCP connection-timing
fixes, the background-worker crash-loop and `git worktree lock` cleanup fixes (continuing the
2.1.193→2.1.208 background-agent hardening thread, no contract change), the `claude attach`
session-transition fix, the auto-mode permission classifier defaulting to Sonnet 5 for external
sessions, and the Agent-tool indirect-prompt-injection hardening (pure benefit, no blueprint
surface it touches directly). Source: `anthropics/claude-code` `CHANGELOG.md` (GitHub, fetched
2026-07-15).

### Audit 2026-07-17 (CC 2.1.211)

Source: `CHANGELOG.md` in the `anthropics/claude-code` GitHub repository, fetched byte-exact via
the GitHub API (`gh api repos/anthropics/claude-code/contents/CHANGELOG.md`), continuing the
2026-07-15 precedent over a prompt-based fetch. The installed range advances from 2.1.210 to
2.1.211. Every relevant item is a platform-internal fix; **no skill, hook, chain, or settings
file needs a code change for this range** (verified: `db-backup-guardrail.sh` is the only hook in
`staging/plugin/scripts/` that emits an `ask` decision, and it already relies on that decision
being honored rather than working around it; the `coder` agent's model pin in
`staging/plugin/agents/coder.md` is unaffected since the bug this range fixes was in session-resume
behavior, not frontmatter parsing).

- **Background agents no longer respawn stale prompts after a user kill, and background-agent
  status reporting no longer fabricates results** (sec. 3.10, ADR-0016, ADR-0022): CC 2.1.211
  fixes two related bugs — a user-killed background agent auto-respawning and a revived agent
  re-running a prompt from an old session, and Claude Code's own reporting of a still-running
  background agent now waits for real completion instead of synthesizing a result. Both continue
  the background-agent hardening thread since 2.1.193 (sec. "Background/overnight reliability
  cluster" above) and extend the `claude stop`-is-honored fix from 2.1.199 (sec. above, "retry
  watchdog widened"). Relevant to the nightly-autopilot morning report and to any Step-5 Workflow
  dispatch that inspects a background coder's status; no contract change, `nightly-report.json`
  and `step5-report.json` stay the authoritative record. See the ADR-0022 addendum below for the
  overnight-specific read.
- **"Always allow" permission approvals now save at the repository root instead of the worktree**
  (sec. 3.2, sec. 10, sec. 12, ADR-0020, ADR-0022): CC 2.1.211 changes where an always-allow rule
  is persisted, so an approval granted inside a git worktree now survives across sessions and
  worktrees instead of being scoped to that one worktree. Directly affects the `coder` agent's
  `isolation: worktree` path (sec. 3.2) and TOFU-trust approvals for `.claude/test-cmd`: before
  this fix, a nightly-autopilot run touching several feature-branch worktrees overnight could have
  re-prompted for the same approval in each new worktree, one more path to the stall
  `nightly-guard` is designed to catch. See the ADR-0022 addendum below.
- **Auto mode no longer overrides a `PreToolUse` hook's `ask` decision for unsandboxed Bash**
  (sec. 7, sec. 10): CC 2.1.211 fixes auto mode silently proceeding past a hook that returned
  `ask`, instead flooring the decision at a prompt. `db-backup-guardrail.sh:232` is the one hook
  in this system that emits `ask` (a detected DB-backup-relevant command with no backup evidence,
  top-level session context). Before this fix, a session running in auto mode could have bypassed
  that gate entirely; this closes a real gap between the hook's intent and what auto mode
  enforced. No hook change needed, the `ask` decision was always correct, only the platform's
  handling of it was wrong.
- **Subagents with an explicit model override no longer revert to the parent session's model on
  resume or follow-up** (sec. 3, sec. 3.10): CC 2.1.211 fixes a subagent's pinned model (e.g.
  `architect` → Opus, `coder`/`debugger` → Sonnet) silently reverting to whatever model the parent
  session is running whenever that subagent is resumed or sent a follow-up message. This is the
  same failure shape the 2026-06-23 workflow-model-pinning update (below) fixed for unpinned
  Workflow `agent()` calls, but on the resume path instead of dispatch. Relevant wherever a
  sub-agent session is resumed rather than freshly dispatched: `SendMessage`-continued agents, and
  any multi-turn chain step that sends a follow-up to an already-running sub-agent. No frontmatter
  change needed, the model pins were already correct; the platform now honors them correctly
  across resume.

Out of scope (no blueprint impact): the `--forward-subagent-text` opt-in flag (no current user of
subagent thinking/text passthrough in this system), the permission-preview bidirectional-override
and look-alike-character neutralization (native hardening against a spoofed approval message, pure
benefit, no hook surface here relies on visual review of tool-input previews), the
shared-credential simultaneous-logout and plugin-MCP idle-reconnect fixes (single-user,
single-session workstation here), the Vertex/Bedrock default-model startup notice (explicit model
configured, N/A), nested `.claude/rules/*.md` files loading even when settings sources exclude
project settings (sec. 5; this repo never excludes project settings, so the bug's precondition
never triggers here), the DOS-device-suffix file-upload and multiple-hard-link fixes, Chrome
file-upload path validation and `save_to_disk` fix, the `?`-input edit-swallow fix, the
Chrome-extension-not-running startup hang, the 300ms async-content reveal delay, the
reopened-background-session blank-conversation fix, `/loop` hiding its session from `/resume`
after one use, the screen-reader terminal-bell fix, the LLM-gateway auth daemon-respawn "Not
logged in" fix (no `ANTHROPIC_AUTH_TOKEN` gateway in use here), the undeletable-`claude
agents`-job-on-missing-worktree fix (now shows the refusal reason instead of silently
reappearing, minor observability win with no contract change), the `/clear` cost-counter reset,
Windows-only fixes (Chrome setup pages, headless print-mode stdin crash), the background
session-title refusal-text display fix, Routines reporting a next-run time in the year 1 (sec.
"loop taxonomy" above; this system does not currently rely on unscheduled Routines), synced
skill/plugin directory naming on Windows, terminal layout/rendering performance, the memory-index
over-limit warning's frontmatter/HTML-comment exclusion, scientific-notation and digit-separator
support for integer env vars, updated documentation links, `/usage-credits` confirmation, Vim-mode
`s`/`S` in NORMAL mode, the `[VSCode]` Remote Control banner copy, and the Bedrock/Vertex/Mantle/
Foundry prompt-caching billing regression (no non-Anthropic-API backend in use here). Source:
`anthropics/claude-code` `CHANGELOG.md` (GitHub, fetched 2026-07-17).

### Audit 2026-07-19 (CC 2.1.212–2.1.215)

Source: `CHANGELOG.md` in the `anthropics/claude-code` GitHub repository, fetched byte-exact via
the GitHub API, continuing the established precedent over a prompt-based fetch. The installed range
advances from 2.1.211 to 2.1.215 (2.1.213 does not exist in the published changelog — versions are not
guaranteed contiguous). Every relevant item is a platform-internal fix or a new opt-in limit; **no
skill, hook, chain, or settings file needs a code change for this range**.

- **Fixed plan mode auto-running file-modifying Bash commands without a permission prompt** (sec. 4,
  sec. 11, ADR-0022): CC 2.1.212 fixes plan mode letting `touch`/`rm`-class Bash commands run
  unprompted, bypassing both the interactive permission dialog and the SDK `canUseTool` callback. Same
  bug class as the 2.1.136 `Edit(...)` allow-rule gap documented in the 2.1.125–146 audit above — this
  is the third and most direct hit on the invariant CLAUDE.md states unconditionally ("Plan mode
  required for any task modifying >1 file"). Pure fix, no gap on our side, just one more platform bug
  closed on a behavior this system depends on being true.
- **Fixed worktree creation following a repo-committed symlink at `.claude/worktrees`** (sec. 3.2, sec.
  12): CC 2.1.212 fixes a symlink committed at `.claude/worktrees` being followed during worktree
  creation, which could create files outside the repository. Direct relevance to `coder`'s
  `isolation: worktree` and `refactor-snapshot`'s worktree harness — a malicious or accidental symlink
  at that path could previously have escaped the isolation boundary those systems assume.
- **Fixed a `continue:false` hook's halt being dropped, and hook infrastructure errors being
  misreported as user rejections** (ADR-0022, sec. 7): CC 2.1.212 fixes two related bugs — a
  `continue:false` hook halt getting silently dropped when the tool fails or completes mid-stream, and
  hook infrastructure errors (crashes, timeouts) being read by the model as a user rejection rather than
  a platform fault. This directly extends the 2.1.210 hook-timeout-misreport fix already logged in this
  system's ADR-0022 addenda — same failure shape (a hook problem disguised as a human "no"), a second
  instance closed. See the ADR-0022 addendum below.
- **New session-wide caps on subagent spawns and WebSearch calls** (sec. 3.10, ADR-0016): CC 2.1.212
  adds a default 200-subagent-per-session cap (`CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`) and a default
  200-WebSearch-per-session cap (`CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION`), both to stop runaway
  delegation/search loops; `/clear` resets both budgets. This is a session-wide ceiling, separate from
  Dynamic Workflows' own 1000-agent lifetime cap (ADR-0016) — a large `nightly-autopilot`/
  `project-conductor` roadmap run (the 2026-07-07 13-feature roadmap spawned 49 agents total, per
  session memory) sits comfortably under 200 today, but this is a ceiling worth watching as roadmaps
  grow, not an immediate gap.
- **Fixed single-segment `dir/**` allow rules and hook `if:` conditions matching nested directories at
  any depth instead of only `<cwd>/dir`** (sec. 5, sec. 7): CC 2.1.214 tightens both `Edit(src/**)`-style
  permission rules and hook `if:` conditions to match only the top-level `<cwd>/dir` on a single-segment
  pattern; `**/dir/**` is now required for any-depth matching (deny/ask rules are unaffected, they keep
  matching any depth). Verified: no `Edit(...)`/`Write(...)`-scoped allow rule in
  `staging/user/settings.json` uses a single-segment `dir/**` pattern (the allow list scopes `Edit`/
  `Write` unconditionally), and no hook in this system's config uses the native `if:` field at all (see
  the 2.1.150–169 audit above) — this fix has no bearing here, confirmed by inspection rather than
  assumed.
- **Fixed scheduled tasks refusing their own configured prompt as untrusted input** (ADR-0022): CC
  2.1.214 fixes a `Cron`-scheduled task's fired prompt being treated as untrusted input instead of being
  delivered as the session's assigned task. `CronCreate` is explicitly deferred in both
  `nightly-autopilot` and `autopilot-build` ("wrap once the Phase 4 smoke test passes") — this fix
  removes a real blocker for that eventual wrap-up, since a self-injection false-positive on the
  scheduler's own prompt would have made unattended Cron dispatch unreliable regardless of the smoke
  test's outcome.
- **`/verify` and `/code-review` no longer auto-run on their own** (sec. 16): CC 2.1.215 stops Claude
  proactively invoking the built-in `/verify` and `/code-review` skills; they now require an explicit
  invocation. Verified: no skill or hook in this system relies on either auto-firing — `review-triage-fix`
  and `code-review-checklist` are invoked explicitly, and mentions of "`/verify`" elsewhere in this repo
  refer to the ADR-0014 test-cmd verification concept, not the built-in skill. No impact.

Out of scope (no blueprint impact): `/fork` becoming a background-session copy with `/subtask` as its
in-session replacement (no current `/fork` usage), MCP tool auto-backgrounding past 2 minutes, the
Task tool `mode` parameter deprecation (subagents already inherit the parent's permission mode by
default in this system — verified: no agent frontmatter sets `permissionMode`), Windows-only PowerShell
fixes, the `EndConversation` tool (already available this session, no action), the periodic
long-tool-call heartbeat, OpenTelemetry attribute additions (no OTel pipeline configured), the
`/ultrareview` UX fixes, and the various background-daemon/agent-view reliability fixes not specific to
worktree isolation or hooks. Source: `anthropics/claude-code` `CHANGELOG.md` (GitHub, fetched
2026-07-19).

### Audit 2026-07-22 (CC 2.1.216–2.1.217)

Source: `CHANGELOG.md` in the `anthropics/claude-code` GitHub repository, fetched byte-exact via the
GitHub API, continuing the established precedent over a prompt-based fetch. The installed range
advances from 2.1.215 to 2.1.217. Most items are platform-internal fixes or new opt-in limits; a
handful land directly on invariants this system depends on, and one confirms an existing hardening
already verified in this repo.

- **Worktree-isolated subagents can no longer redirect git into the shared checkout via `git -C`,
  `--git-dir`, or `GIT_DIR`/`GIT_WORK_TREE`** (sec. 3.2, sec. 12, ADR-0016): CC 2.1.216 closes this
  escape route. This is the fifth fix in the worktree-isolation-bypass thread already tracked in this
  document — the 2.1.198 edit-block fix, the 2.1.200 plugin/skill-load fix, the 2.1.203 parent-checkout
  shell-command fix, and the 2.1.212 `.claude/worktrees` symlink fix all precede it. `coder`'s
  `isolation: worktree` and the Step-5 Workflow coder path are the direct beneficiaries; verified no
  script in this system asks a worktree-isolated agent to run `git -C`/`--git-dir` against the parent
  tree (the `git -C` calls found in `staging/plugin/scripts/tests/` target throwaway fixture repos, not
  the shared checkout).
- **Workflow saves and scheduled-task writes no longer follow a symlink at `.claude`** (sec. 7,
  ADR-0016): CC 2.1.216 fixes writes redirecting outside the project through a symlinked `.claude`
  directory. Directly relevant to the Step-5 Workflow file handoff (`.claude/step5-report.json`,
  ADR-0016) and to the eventual `CronCreate` wrap-up in `nightly-autopilot`/`autopilot-build` — both
  assume a write to `.claude/...` lands inside the project, an assumption this fix now backs.
- **Telemetry no longer misreports failed permission-prompt requests or user interrupts as
  rejections** (ADR-0022): CC 2.1.216 is the fourth fix in the hook-halt-misreport thread this
  document and ADR-0022 already track (2.1.210 hook-timeout, 2.1.211 status fabrication, 2.1.212
  `continue:false` drop). See the ADR-0022 addendum below.
- **Resumed background agent sessions no longer revert to the default agent** (sec. 3, sec. 3.10,
  ADR-0022): CC 2.1.216 restores the agent's prompt and tool restrictions on resume instead of falling
  back to the default. Before this fix, a `nightly-autopilot`/`project-conductor` background session
  resumed after an interruption could have lost an agent's scoped tool grants (for example `reviewer`'s
  narrow read-only Bash set, ADR-0036/ADR-0038) and continued with the unrestricted default agent
  instead. No contract change to `nightly-guard` or the morning report; this closes one more concrete
  path to a silently-widened tool surface on the overnight path.
- **`AskUserQuestion` free-text answers asking Claude to wait or explain no longer get told to
  continue anyway** (sec. 11): CC 2.1.216 fixes the wording sent back for a free-text answer so it no
  longer nudges Claude past a user's explicit "wait" or "explain first". Every HITL gate in this system
  (commit/push/PR, Gate 0b/0c/0d, Gate 2b TOFU probe, the destructive-ops confirmations) is built on
  `AskUserQuestion`; this closes a real, if narrow, HITL-bypass-adjacent gap on the free-text answer
  path specifically (button-option answers were unaffected).
- **Bash permission checking now covers compound statements with redirects inside `&&` lists or
  negations** (sec. 10, ADR-0034/ADR-0038): CC 2.1.216 fixes a gap in how Bash commands are matched
  against allow/deny/ask rules when redirects sit inside a `&&` chain or a negated command. This is the
  same bug class as the permission-pattern-matching fixes already logged under ADR-0034
  (`permissionDecision` enum, hash-after-normalize) — a scoped grant like `architect`'s `Bash(git *)` or
  `reviewer`'s `Bash(rg *)`/`Bash(grep *)` (ADR-0036/ADR-0038) relies on this matching being exact; a
  crafted compound command was one concrete way to slip past a narrow Bash scope undetected.
- **A `CLAUDE.md` or `SKILL.md` `paths:` frontmatter value with many brace groups no longer OOM-kills
  or stalls the CLI at startup** (sec. 5): CC 2.1.217 budget-bounds brace expansion. Verified: three
  path-scoped rules files in this system's own rules set use brace-group globs —
  `staging/user/rules/shell.md` (`**/*.{sh,bash}`), `staging/user/rules/typescript-react.md`
  (`**/*.{ts,tsx}`), and `staging/user/rules/web-vanilla.md` (`**/*.{html,css,scss}`) — each with 2-3
  groups, far below whatever count triggers the stall. No incident on record, but this hardens a
  pattern this system actively ships rather than one it merely could hit.
- **Subagents no longer spawn nested subagents by default** (sec. 2.2, sec. 3.10): CC 2.1.217 makes
  the flat model the platform default (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` opts back into deeper
  nesting). This is a stronger version of the 2.1.203 "less likely to re-delegate" note already in
  this document at sec. 3.10 — the "no sub-agent spawns sub-agent" invariant in the four dispatching
  skills is now the platform's own default, not just a design choice this system happens to hold.
- **New cap on concurrently-running subagents** (sec. 3.10, ADR-0016): CC 2.1.217 adds a default
  20-concurrent-subagent limit (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`), separate from the
  2.1.212 200-per-session cap already logged above and from Dynamic Workflows' own `min(16, cpu
  cores - 2)` concurrency cap (ADR-0016). This system's own cap already sits under the new platform
  default; no conflict, no change needed.
- **`--max-budget-usd` now stops background subagents once the cap is reached** (sec. 3.10): CC
  2.1.217 denies new spawns and halts running background agents when the budget cap is hit, rather
  than only blocking new spawns. Relevant to any future cost-ceiling flag on a `nightly-autopilot` or
  `project-conductor` roadmap run; no current usage of `--max-budget-usd` in this system, noted for
  when it is adopted.

Out of scope (no blueprint impact): emoji shortcode autocomplete, transcript-write failure warnings,
the MCP tool-output memory leak, Windows auto-update and `claude.exe` recovery, background-session
symlink-canonicalization for workspace escape (a different code path from the `.claude`-symlink and
worktree-`git -C` fixes above — no current use of background sessions outside the sandboxed worktree
model), Bedrock/Opus-4.8 auto-compact, corporate mTLS/proxy settings in Claude Desktop, screen-reader
and thinking-row rendering, `OTEL_EXPORTER_OTLP_ENDPOINT` scope precedence (no OTel pipeline
configured), `--resume`/`--continue` TypeError on malformed attachments, Remote Control pending-prompt
visibility, background-shell stop reliability, transcript-preview layout, footer PR-badge hyperlinks,
the login-expiry warning window change, the frontend-design plugin tip impression cap, `sandbox.
filesystem.disabled`, the quadratic message-normalization slowdown fix, auto mode's HTTP 401
classifier fix, Claude Code on the web re-asking a dropped question, `@`-mention/vim-dot-repeat/
statusline/resume-picker fixes, worktree sessions landing in another project's leftover worktree,
undeletable worktree-less background sessions, `claude daemon stop --any` lockfile safety, Esc-Esc
rewind-picker reliability, Ctrl+X session deletion, background-subagent cancellation on a high-priority
message during startup, GUI-editor mouse/focus artifacts, Claude-in-Chrome 403-loop on reconnect, MCP
re-authenticate credential revocation ordering, Windows-only network-path and PowerShell fixes,
Bash non-ASCII word-boundary parsing (general hardening, no specific gap identified here), dialog and
`/config`/transcript-mode UI clipping, the Prometheus `# UNIT` fix (no Prometheus exporter configured),
skills/commands now hot-reloading mid-session without a restart (a workflow convenience for this
system's own skill development, no code change), plugin-prefixed skill names in autocomplete,
the `/fork` confirmation message, `git`/`gh` argument validation in the PowerShell tool, the
`/ultrareview` and `/code-review ultra` error-message improvements, the spend-limit adjustment prompt,
`/context`'s over-limit warning, `/rewind`'s symlink/hard-link hardening (consistent with the
`.claude`-symlink and worktree fixes above, no direct reliance on `/rewind` in this system's safety
design), background-session `/mcp`/`/install-github-app` needs-input parking, the bundled dataviz
skill update, `[VSCode]` RTL rendering, and cloud-session container-restart resume. Source:
`anthropics/claude-code` `CHANGELOG.md` (GitHub, fetched 2026-07-22).

### Audit 2026-07-23 (CC 2.1.218)

Source: `CHANGELOG.md` in the `anthropics/claude-code` GitHub repository, fetched byte-exact via the
GitHub API, continuing the established precedent. The installed range advances from 2.1.217 to 2.1.218.
Most items are platform-internal reliability and accessibility fixes; a handful touch documented
behavior (`/code-review ultra`, `/ultrareview`) or harden a pattern this system does not currently use.

- **`/code-review` now runs as a background subagent** (sec. 16): CC 2.1.218 stops `/code-review` from
  filling the conversation with review output and keeps stacked slash commands as its review target
  (e.g. `/skill-a /code-review`). `review-triage-fix` and the `code-review-checklist` reference drive
  the `reviewer` agent and the `code-review` skill directly rather than the bare `/code-review` command,
  so no chain contract changes; this is a pure UX improvement for any manual `/code-review` invocation
  outside those skills.
- **`/ultrareview` no longer fails on descriptive arguments** (sec. 16): CC 2.1.218 fixes
  `/ultrareview "review my auth changes"`-style invocations, which previously failed outright; the
  descriptive text is now applied as a note on a current-branch review instead. Directly relevant to
  this session's own guidance text describing `/ultrareview` as a deprecated alias for
  `/code-review ultra` — the alias is now more robust to how a user actually phrases the request, no
  documentation change needed since the alias relationship itself is unchanged.
- **`/code-review ultra` no longer silently runs a local review in non-interactive sessions** (sec. 16):
  CC 2.1.218 fixes a correctness bug, not just wording — a non-interactive session invoking
  `/code-review ultra` was previously getting the cheap local path with no indication the cloud review
  never launched. `nightly-autopilot` and `autopilot-build` run unattended but neither currently invokes
  `/code-review ultra` (they drive `review-triage-fix` and the `reviewer` agent directly), so no chain
  is retroactively affected; this closes a latent trap for any future unattended use of the ultra path.
- **Agent frontmatter hooks now require the agent file's own folder to have accepted workspace trust**
  (sec. 3, ADR-0036, ADR-0038): CC 2.1.218 fixes agent-defined `hooks:` running from untrusted folders.
  Verified: none of this system's 8 custom agents (`architect`, `coder`, `reviewer`, `tester`,
  `debugger`, `refactorer`, `doc-writer`, `researcher`) define a `hooks:` frontmatter field — this
  system's hook stack lives entirely in `settings.json` (ADR-0001, ADR-0009, ADR-0034), not in agent
  files. Hardens a pattern this system does not currently exercise; no impact today, noted for if an
  agent-level hook is ever adopted.
- **Skills with `context: fork` now run in the background by default** (sec. 8.5): CC 2.1.218 makes
  fork-context skills background by default, opt-out per skill via `background: false`. Verified:
  `grep -rl "context:\s*fork" staging/plugin/skills/*/SKILL.md` returns nothing — none of the 16
  deployed skills use `context: fork` (sec. 8.5's `deep-research` example is illustrative only, not a
  shipped skill in this system). No impact today; if a future skill adopts `context: fork`, its default
  behavior changes from foreground to background and may need an explicit `background: false` if the
  chain expects to block on it.
- **Auto mode's dangerous-rm, background-`&`, and suspicious-Windows-path checks no longer open
  permission dialogs; the auto-mode classifier judges them instead** (sec. 10): relevant because Auto
  Mode is this session's active permission mode. This system's own destructive-ops protection does not
  depend on the permission dialog for these three checks — `protect-files.sh`, `db-backup-guardrail.sh`,
  and the explicit HITL gates before commit/push/deploy/schema-change/deletion (sec. 4, this file's
  invariants) are separate hook-level and skill-level gates that fire regardless of permission mode. No
  contract change; documented here because the removed dialog is a real behavior change a user of Auto
  Mode would otherwise notice without an explanation on record.
- **Plan mode with auto no longer prompts for Bash commands the static analyzer can't prove read-only;
  the auto-mode classifier judges instead** (sec. 4, sec. 11): same class of change as the item above,
  applied to plan mode specifically. Plan mode's read-only contract (sec. 4's "Plan mode required for
  any task modifying >1 file" invariant) is unaffected in substance — the classifier is a platform-side
  judgment call on ambiguous Bash commands, not a relaxation of what plan mode blocks outright (Write,
  Edit, and known-mutating commands stay blocked).
- **Fixed a context-overflow retry loop re-sending doomed requests with a large thinking budget; `Ctrl+B`
  backgrounding now applies the same background-shell caps as other paths** (sec. 3.9, ADR-0036): this
  system pins `effort: xhigh` on several agents (`architect`, `reviewer` per ADR-0036) and workflow
  stages can run at `effort: max`. A large thinking budget hitting context overflow previously could
  retry-loop instead of failing fast; this closes that failure mode. No configuration change needed.
- **Fixed spurious "[Request interrupted by user]" messages after interrupted tool calls, and an
  unpaired `tool_use` block left in the transcript when a tool aborted mid-response**: adjacent to but
  distinct from the hook-halt-misreport thread tracked in the ADR-0022 addendum (2.1.210/2.1.211/2.1.212/
  2.1.216) — that thread is hook/telemetry infrastructure misreporting a platform fault as a human "no";
  this fix is a transcript-integrity bug after an interrupted tool call (e.g. `Esc` or `Ctrl+C` mid-tool)
  producing a misleading message and a dangling `tool_use` block. Not added to the ADR-0022 addendum:
  no hook or `nightly-guard` decision point is misled by this specific bug, it is a display/transcript
  artifact. Noted here for completeness, not as a sixth entry in that thread.

Out of scope (no blueprint impact): screen-reader announcements for word/line deletions, Windows
`\u`-prefixed path corruption to CJK characters, left-arrow-key conversation-discard confirmation, HTTP
status/error text in `claude mcp list`/`/mcp`, MCP config hidden-whitespace warning, multi-line paste
collapsing on Ctrl+J-encoding terminals, `/context` stale post-compact token usage, gateway spend
metering for Bedrock application-inference-profile ARNs, mojibake on truncated IDE selection mid-emoji,
silently-dropped tool executor errors, engine teardown phantom-turn race, VoiceOver trailing-space echo,
plugin/settings-panel cursor following for screen readers, max-call-stack crashes on deeply nested
watched-directory or UI-tree operations, PR events lost on immediate session exit, Bedrock setup wizard
assume-role verification in partitioned regions, turn-duration monotonic-clock fix, MCP-authentication
notice over-counting disconnected claude.ai connectors, prompt-history entries dropped or duplicated on
racing writes, fork-session lineage lost after compaction in headless/SDK sessions, resumed-session
crash on malformed delta attachment, `/ultrareview` error-feedback wording, fast-mode-change
announcement on model switch, server-managed settings no longer triggering approval for benign toggles,
agent markdown files rejecting `:` in names (none of this system's agent names contain `:`), skill/plugin
frontmatter booleans accepting `yes`/`no`/`on`/`off`/`1`/`0`, and remote sessions' heartbeat-after-worker-
replacement fix (no long-lived desktop/IDE remote-session usage in this system). Source:
`anthropics/claude-code` `CHANGELOG.md` (GitHub, fetched 2026-07-23).

### Audit 2026-07-24 (CC 2.1.219)

Source: `CHANGELOG.md` in the `anthropics/claude-code` GitHub repository, fetched byte-exact via the
GitHub API, continuing the established precedent. The installed range advances from 2.1.218 to 2.1.219,
the current published latest. Headline item is the Claude Opus 5 release; the rest is platform-internal
reliability work plus one advisory Dynamic Workflows default and one subagent-nesting default reversal.

- **Claude Opus 5 released, now the default Opus model** (sec. 3.10): see the new sec. 3.10 paragraph for
  the full analysis. Summary: `architect`'s bare `opus` tier alias would normally pick up Opus 5 with no
  frontmatter change, but the live `env.ANTHROPIC_DEFAULT_OPUS_MODEL` override (`claude-opus-4-8[1m]`,
  set before Opus 5 existed) takes precedence and pins `architect` to Opus 4.8 regardless of the platform
  default. This is the one concrete action item from this release: `staging/user/settings.json` is updated
  in this same audit to `claude-opus-5`, pending the mandatory-diff human sync to the live
  `~/.claude/settings.json` per `docs/RUNBOOK.md` Step 3.
- **Subagent nested-spawn default reversed again, depth 1 → depth 3** (sec. 2.2, sec. 3.10): CC 2.1.219
  raises the default `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` from 1 (set by 2.1.217, logged in the prior
  audit) back up to 3. No impact: this system's "no sub-agent spawns sub-agent" invariant (sec. 2.2) has
  always been enforced by convention in the four dispatching skills, never by relying on the platform
  default — confirmed no `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` override exists in either
  `staging/user/settings.json` or the live `~/.claude/settings.json`. The 2.1.217 entry's framing ("the
  flat model the platform default") held for about two releases and is superseded by this reversal; the
  invariant's real backstop is the design convention, not the platform default, which is exactly why the
  2.1.217 audit treated the prior alignment as a bonus rather than the mechanism.
- **Dynamic workflows default to a "medium" size guideline, aim for fewer than 15 agents** (sec. 3.10,
  ADR-0016): CC 2.1.219 adds a `workflowSizeGuideline` settings key alongside the existing `/config`
  control (2.1.202, already documented as advisory-only in sec. 3.10 and ADR-0016) and changes the
  out-of-the-box default to medium. Still explicitly advisory, not an enforced cap, so ADR-0016's hard
  limits (16 concurrent, 1000 total per run) are unchanged. No action needed: the 2026-07-07 13-feature
  roadmap spawned 49 agents total across 13 separate per-feature chain invocations (per session memory),
  averaging well under 15 agents per invocation already, so the new default guideline does not conflict
  with this system's actual usage pattern.

Out of scope (no blueprint impact): `sandbox.network.strictAllowlist` setting (no sandboxed-command
network egress configuration in this system), `DirectoryAdded` hook (no multi-root `/add-dir` usage),
`mcp_server_errors` in the headless stream-json init event, nested-subagent forwarding in stream-json
for depth-2+ (downstream of the depth-3 default above, observability-only), managed MCP allowlist/
denylist `${VAR}` resolution source change, self-hosted-runner permission/SIGTERM/failure-category
fixes (no self-hosted runners; GH Actions jobs are hosted per ADR history), `/model` picker UI fixes,
screen-reader input echoing, Vim-mode `←` behavior, GNU-screen copy-on-select, Remote Control fast-mode
staleness, `claude --teleport` repo-mismatch messaging, `claude -p` mid-stream error text recovery,
Fable model-row cache label fix, and the claude-api skill's own default-model migration (internal
Anthropic tooling, not this system's `researcher`/`architect` MCP usage). Source: `anthropics/claude-code`
`CHANGELOG.md` (GitHub, fetched 2026-07-24).

### Correction 2026-07-24 (humanize-en scope, ADR-0040)

`humanize-en` had become the most-invoked skill in the system. The cause was its wiring, not the
skill: the global rule, the skill's own `description` frontmatter, two hooks and two chain
integrations all pushed it onto internal artifacts. ADR-0040 narrows it to text an outside audience
reads and amends ADR-0015 accordingly.

- **Perimeter is the audience, not the format** (sec. 8.6): Reddit and HN posts, forum threads, blog
  posts, newsletters, announcements, marketing copy, third-party email. Not source code, config,
  commit messages, PR and issue text, ADRs, specs, plans, README and repo docs, changelogs, release
  notes, or anything gitignored. README sits on the internal side, recorded as a judgment call.
- **Invocation is manual only** (sec. 8.6): `concept-to-code` Gate 5.5 and `commit` Step 3.5 removed.
- **Gate 0c and Gate 5.5 removed from the chain** (sec. 11): every artifact the chain produces is
  internal, so neither gate could fire. Per ADR-0027 an unreachable gate is a defect, not a safe
  no-op. Gate 5.5's state transition to `step_7_commit` was load-bearing and survives as Gate 5.6,
  action-free. The letters `0c` and `5.5` are not reused.
- **`post-md-tells-hint.sh` retired** (sec. 7): it fired on every `.md` written. It was also already
  a no-op for the model, printing its hint as plain stdout on exit 0, which `PostToolUse` sends to
  the debug log rather than into context (`code.claude.com/docs/en/hooks`).
- **`prompt-en-prose-detect.sh` narrowed** (sec. 7): one regex becomes two greps in AND, a writing
  verb plus a publication target. It used to match the word rather than the intent, so a message
  *about* Reddit fired it. Internal targets dropped from the target list. ADR-0034's dual-envelope
  JSON output is preserved.

Detail: `docs/architecture/ADR-0040-humanize-en-scope-narrowing.md`.

### Update 2026-06-23 (workflow model pinning)

- **Workflow dispatch pins models explicitly** (sec. 3.10, `concept-to-code` Step 5/6): a workflow
  subagent dispatched with `agentType` but no `model` inherits the **main-loop (CLI session) model**,
  not the agent's frontmatter. So when the orchestrator runs on Opus, an unpinned `agent({agentType:
  "coder"})` would silently run the coder on Opus instead of its configured Sonnet. Fix: every
  `agent()` call in the Step 5/6 workflow scripts now passes an explicit `model` (coder → its
  `coder_model`, sonnet by default; reviewer → sonnet; fix agents → opus by chain choice). The
  Agent-tool dispatch paths (Step 2 architect, Step 5/6 fallback) already honor frontmatter and were
  unaffected. Net effect: the chain keeps its configured per-agent models regardless of which model
  the CLI session is set to.
- **`debugger` aligned to blueprint** (sec. 3.5): the live `~/.claude/agents/debugger.md` had drifted
  to `model: opus`; reset to `model: sonnet` with `effort: high`, matching sec. 3.5 and the sec. 3.10
  cost table (root-cause reasoning comes from high effort, not the model tier).

### Update 2026-06-22 (chain memory, ADR-0021)

- **Chain-memory PostToolUse hook** (sec. 7.7, sec. 13, ADR-0021): a deterministic `PostToolUse`
  hook (matcher `Bash`) records `concept-to-code` chain task completion and current state of fact
  into the native memory store, so progress persists across sessions and is browsable via
  `/memory`. It fires in the orchestrator session only (manifest helpers are orchestrator-run), so
  the ADR-0016 hook-propagation concern is out of scope. Per-topic files at
  `memory/chain-history/<slug>.md` (mirroring the ADR-0012 `agent-notes/` namespace) carry a
  rewritten-in-place STATE OF FACT header plus an append-only event log; a delimited managed block
  in `MEMORY.md` lists Active chains (surfaced at SessionStart) and the last 10 Archived chains.
  The writer is zero-LLM and bound to the session's own encoded dir (scope-safe), so the ADR-0013
  auto-write failure mode cannot recur. **`CLAUDE.md` is never touched.** *Verified:* dry-run
  harness (record/no-op/dedup/terminal-demote/preamble-preservation) green on bash 3.2. *Assumed,
  to validate in pilot:* PostToolUse(Bash) fires on the live manifest-helper calls in a real chain
  run.

### Update 2026-06 (post-deployment)

- **`concept-to-code` orchestrator skill** (sec. 8.6): the canonical implementation of sec. 11 as a deterministic state machine. Three paths — Express (<10 files, single session, plan mode), Hybrid (5–20 files, single session, interview+plan), Standard (full chain, fresh session). YAML manifest (schema 1.3, `chain_path`, `gate0.*`). 7+ HITL gates. Harness 78/78.
- **`review-triage-fix` skill** (sec. 8.6): per-branch JSON triage state machine, circuit breakers A–D, NIT batching. Step 6 in Standard chain. Prefix-cache discipline (PRIOR AGENT NOTES at END of dispatch briefs), no-op detection, hash-oscillation wording-preservation.
- **`deep-refactor` skill** (sec. 8.6, ADR-0018): 4-dimension parallel audit (dead-code/perf/structure/security) → sequential fix loop with global circuit breaker. Gate 5.1 in Standard chain. Two mandatory report-only guards: `@objc`/`dynamic`/protocol-witness dead code; `async`/`actor`/`Sendable` perf. No test-cmd = report-only mode.
- **`claude-md-slim` skill** (sec. 8.6, ADR-0019): audits project CLAUDE.md, extracts domain sections to `.claude/rules/<domain>.md`. Content-preservation hard gate. `--global` duplication scan. Harness 19/19.
- **`humanize-en` skill** (sec. 8.6, ADR-0015, narrowed by ADR-0040): English prose humanizer. Manual invocation only, scoped to text an outside audience reads (Reddit/HN, forum, blog, newsletter, announcement). The `post-md-tells-hint.sh` hook, Gate 0c, Gate 5.5 and commit Step 3.5 were removed; the conditional UserPromptSubmit hook survives, narrowed to a writing verb AND a publication target.
- **`design-brainstorm`, `macos-ux`, `ui-layout-audit`, `clean-public-repo`, `vibe-status`, `interview-driver`, `claude-md-generator`, `commit` skills** (sec. 8.6): chain-integrated skills and utilities — see sec. 8.6 table.
- **`agent-design` knowledge base** (sec. 8.6): 7 Sayfan reference files covering prefix caching, multi-agent patterns, tool design, evaluation, deployment.
- **Chain-stop fix** (sec. 11): CRITICAL continuation blocks for `interview-driver` and `design-brainstorm` now use positive-constraint imperative ("Your NEXT OUTPUT must be a Bash tool call") instead of passive prohibitions.
- **Sayfan prefix-cache discipline** applied across all chain skills: PRIOR AGENT NOTES blocks moved to END of dispatch briefs (stable content first, dynamic notes last).

### Update 2026-05-29 (2)

- **Chain-type routing at Gate 0** (sec. 11, ADR-0017): Gate 0 now fires on every invocation and routes to one of three paths. **Express** (chain_path=express): <10 files, single session, no sub-agents, plan mode + direct execution, manifest only. **Hybrid** (chain_path=hybrid): 5–20 files, single session, interview → SPEC.md → plan mode → direct execution, no fresh-session boundary. **Standard** (chain_path=standard): existing full chain unchanged. Auto-detect heuristic (file count + keyword vote on topic title) pre-selects a recommendation; user confirms or overrides. Gate 0 now always shows the routing choice — the old conditional/silent path is removed. Manifest schema bumped to 1.3 (new fields: `chain_path`, `gate0.chain_path`, `gate0.auto_detect_reason`). Validator accepts 1.0–1.3. 17 new transition pairs (5 Express + 12 Hybrid). Harness: 50/50 PASS.

### Update 2026-05-29

- **Gate 0d — Project scaffolding gate** (sec. 11): New gate in the `concept-to-code` chain that fires unconditionally after Gate 0b, before Step 1 (after Gate 0c until ADR-0040 removed that gate). Four questions in one `AskUserQuestion` call: git repo (private/public/none), license (MIT/Apache-2.0/GPL-3.0/None), Xcode project (yes/no), initial commit behavior (commit+push/commit-only/none). Conditional follow-ups: remote URL (if push selected), anonymize re-confirm (if public). Sets 6 new manifest fields: `git_init`, `git_visibility`, `license`, `xcode_project`, `initial_commit_push`, `git_remote_url`. These cascade into Step 2 architect brief (Xcode hint), Step 5 coder dispatch (LICENSE file + Xcode scaffold tasks), and Step 7 push logic.
- **Step 6 Dynamic Workflow dispatch** (sec. 11): The review-triage-fix cycle in Step 6 now has a workflow path mirroring ADR-0016 Step 5. When `hook_verified=true`: 4-phase JS workflow — (1) reviewer agent returns findings with file + fix_type fields, (2) in-script group-by-file, (3) parallel fixer dispatch per file group with `agentType` from `fix_type`, (4) re-reviewer. Writes `.claude/step6-report.json`. Sets `step6_mode: "workflow"` in manifest. When `hook_verified=false`: falls back to `/skill review-triage-fix`. New manifest field: `step6_mode`.
- **Step 7 push** (sec. 11): After commit, if `initial_commit_push=push` and `git_remote_url` is set: `git remote add origin <url>` (if absent) then `git push -u origin HEAD`. Graceful error handling — push failure reports to user without aborting the chain (commit already succeeded).
- **pre-flight-pattern-enforce v1.3** (sec. 7): Workflow subagent transcripts stored at `subagents/workflows/<wf_id>/agent-<id>.jsonl` (undocumented path change in v2.1.154). Hook v1.3 adds `find`-based fallback that searches the workflows directory. Smoke test 2026-05-29 on v2.1.156: `hook_verified=true` confirmed. ADR-0016 status: Proposed → Accepted.
- **`memory: local` on coder** (sec. 3.2): Pilot (P1) — coder agent gets `memory: local` frontmatter. Adds a Memory tool scoped to `.claude/agent-memory-local/coder/`. Guidance: use Memory tool only (not Edit/Write) to persist task progress, discovered patterns, key decisions across parallel batches. Pattern-enforce hook (ADR-0001) gates all Edit/Write calls as additional guardrail. See sec. 3.9 for field reference.
- **`mcpServers` inline on researcher** (sec. 3.8, 3.9): Pilot (P2) — researcher agent gets `mcpServers: context7` defined inline, making the agent self-contained (no global plugin dependency). New §3.9 documents all agent frontmatter fields (v2.1.154+) including `memory` and `mcpServers` scoping rules.

### Update 2026-05-26

- **`isolation: worktree` on coder — gap closed**: the frontmatter of `~/.claude/agents/coder.md` now includes `isolation: worktree` (was present in the doc template but not deployed). Verified behavior: on a git repo it creates an isolated worktree; on projects without git it silently falls back (no error, direct edits). The `concept-to-code` chain requires no changes: the worktree branch is already managed by the orchestrator in the review/merge phase (sec. 3.2, 12).
- **`manifest-validate.sh` accepts schema 1.2** (post-recovery fix): an accidental skill recovery had reverted `scripts/manifest-validate.sh` to the pre-ADR-0011 version, which did not accept `schema_version: "1.2"`. Fix applied inline; concept-to-code harness 27/0.
- **Gate 2b TOFU redesign** (fix stop-hook loop + auto-approve): in the `concept-to-code` chain, the old pattern "tell the user to run `approve-test-cmd.sh`" caused a loop: the stop hook blocked before the user could respond, the orchestrator tried to work around it by calling the script via Bash, auto mode let it through → auto-approval without human review. Fix: Gate 2b now uses `AskUserQuestion` with explicit options [Approve / Modify / Skip / Abort]. Only after the user's click does the orchestrator call `approve-test-cmd.sh`. Explicit guardrails in SKILL.md: NEVER call `approve-test-cmd.sh` before the click; NEVER modify `.claude/test-cmd` autonomously. The SHA-pinned TOFU mechanism is unchanged. Concept-to-code harness 29/0.
- **Gate 4 session boundary — made BLOCKING**: in the `concept-to-code` chain, the session boundary between Step 3 (architecture+CLAUDE.md) and Step 5 (implementation) was not strong enough — the orchestrator interpreted the `ready_for_implementation` state as a signal to continue directly into coder dispatch. Fix: Gate 4 now uses `AskUserQuestion` with a single option "Confirmed — I will /clear and resume" + explicit instruction `**STOP — do not dispatch coders, do not continue**` in SKILL.md. The `/clear` boundary is an architectural requirement: the interview/architect session context contaminates the implementation phase (context window + risk of overwriting already-made decisions). Concept-to-code harness +1 anchor (30/0).
- **Blueprint repo on git** (2026-05-26 afternoon): `vibe-coding-system` now has git initialized and a private remote at `github.com/istefox/vibe-coding-system`. `.gitignore` excludes session logs (`.remember/logs/`, `tmp/`, `now.md`, `today-*.md`, etc.) — only source artifacts are committed. Skill `/commit` field-tested on this repo: full flow verify→diff→HITL gate→commit→push working. The blueprint's `CLAUDE.md` has been updated accordingly (removed the "git not initialized" note).

### Update 2026-05-25 (CC 2.1.147–149)

Relevant news for this system, incorporated inline in the indicated sections:

- **`effort: xhigh` on architect** (sec. 3.1, 3.9): `xhigh` is the native effort level of Opus 4.7 for agentic/coding tasks; it is now the recommended default. The architect frontmatter template is updated from `high` to `xhigh`. Automatic fallback to `high` on Sonnet 4.6 when architect is dispatched with `model: sonnet` override (routine ADR).
- **Fix status bar effort frontmatter** (2.1.149): the status bar showed the session effort instead of the skill/agent frontmatter effort. Now correctly reflects the override. Confirmed working for our `effort: xhigh` on architect.
- **Fix `AskUserQuestion` in auto mode** (2.1.149): auto mode suppressed `AskUserQuestion` even when the skill used it explicitly. Resolved: the classifier reads user responses as intent signals. Relevant for `interview-driver`, `design-brainstorm`, and all HITL gates in the `concept-to-code` chain.
- **`/usage` breakdown by category** (2.1.149): shows cost detail by skill, subagent, plugin, MCP server. Added to sec. 16 commands.
- **`/code-review` (ex `/simplify`)** (2.1.147): `/simplify` renamed; now reports correctness bugs at configurable effort (`/code-review high`); `--comment` for inline PR comments. Updated sec. 16.
- **Fix sandbox worktree** (2.1.149): the write allowlist in git worktrees covered the entire main repo instead of just the shared `.git/`. Resolved. Relevant for `isolation: worktree` on coder (sec. 12).
- **Fix `find` macOS vnode table** (2.1.149): the Bash tool exhausted the macOS vnode table on very large directories, crashing the system. Resolved. The `find .` anti-pattern on large repos removed from the theoretical-risk list.
- **Remote bootstrap mechanism** (2.1.150): CC calls `api.anthropic.com/api/claude_cli/bootstrap` at startup and GrowthBook (`tengu_heron_brook`) every 60s; the content is injected into the system prompt. This is first-party configuration (Anthropic), not injection from third parties. For environments with immutability policies: `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` blocks both channels (added sec. 17).

---

## Changes from v1.0

v1.0 contained significant inaccuracies. Verified against `code.claude.com/docs`, these are the corrections:

- **Sub-agents**: they are formal entities with `.claude/agents/<name>.md` files and YAML frontmatter, not abstract concepts. Anthropic already provides built-ins (`Explore`, `Plan`, `general-purpose`)
- **Sub-agents do NOT spawn other sub-agents**: hard limit. For nesting, use `agent-teams`
- **Agent teams** (v2.1.32+, experimental): multi-session coordinated pattern via shared task list. This is the correct pattern for cross-layer work (backend + frontend + test in parallel)
- **CLAUDE.md target <200 lines** (was ~170, still high): trimmed to ~90 effective lines
- **`.claude/rules/`** with `paths:` frontmatter: recommended pattern for stack-specific rules (replaces most of the monolithic CLAUDE.md)
- **Auto memory**: real feature in `~/.claude/projects/<repo>/memory/`, worth mentioning
- **Hooks**: full section missing in v1.0, it is the most important deterministic mechanism
- **Worktrees for parallel Coders**: resolves the lock file conflict (open item v1.0)
- **Bundled skills**: `/batch`, `/simplify`, `/debug`, `/loop`, `/claude-api` exist out-of-the-box
- **Permission modes**: 6 real modes (`default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`), not just "plan/bypass"
- **`/init` with `CLAUDE_CODE_NEW_INIT=1`**: interactive multi-phase flow to generate CLAUDE.md, skills, and hooks together

---

## 1. Summary

**Topology.** Central orchestrator (Claude Code CLI) → up to 4 sub-agents in parallel (inside the session) for focused tasks, or teams of 3-5 independent teammates (separate sessions) for cross-layer work.

**Extension stack.** Global CLAUDE.md (~90 lines, identity+behavior only) + path-scoped rules in `.claude/rules/` for stack-specific + sub-agent files in `.claude/agents/` + skills in `.claude/skills/` + hooks in `settings.json` + MCP in `.mcp.json`.

**Permission strategy.** Plan mode by default for new features, `acceptEdits` during implementation, `auto` mode (if on Team/Enterprise plan) for long work with safety classifier in background.

**MCP core.** sequential-thinking, XcodeBuildMCP, github, sqlite/postgres-mcp.

**concept→code workflow** (sec. 11) based on the official Anthropic pattern: interview mode with `AskUserQuestion` → `SPEC.md` → fresh session with plan mode → parallel implementation → commit + PR.

---

## 2. System architecture

### 2.1 Logical topology

```
Orchestrator (main Claude Code CLI session)
    │
    ├─ Built-in sub-agent (Anthropic):
    │  ├─ Explore        (read-only, inherits session model cap opus, codebase search)
    │  ├─ Plan           (read-only, plan mode, research for planning)
    │  ├─ general-purpose (all tools, generic multi-step)
    │  └─ Bash, statusline-setup, Claude Code Guide
    │
    ├─ Custom sub-agents (.claude/agents/*.md, max 4 parallel):
    │  ├─ architect       (Opus, planning + ADR)
    │  ├─ coder           (Sonnet, edit, isolation: worktree)
    │  ├─ reviewer        (Sonnet, read-only, memory: project)
    │  ├─ tester          (Sonnet, bash + edit)
    │  ├─ debugger        (Sonnet, edit + bash, memory: project)
    │  ├─ doc-writer      (Haiku, text edit)
    │  ├─ refactorer      (Sonnet, edit, memory: project)
    │  └─ researcher      (Haiku, read-only + web)
    │
    └─ Agent team (experimental, separate sessions):
       For cross-layer work on large projects (backend + frontend + test
       in parallel) or investigation with competing hypotheses
```

### 2.2 Sub-agent vs agent team (critical decision)

Official Anthropic documentation distinguishes clearly:

| Characteristic | Sub-agent | Agent team |
|---------------|-----------|-----------|
| Architecture | Inside the current session | Independent coordinated sessions |
| Communication | Only toward the lead (report results) | Peer-to-peer + shared task list |
| Spawn others | NO | NO (also in teams, no nested) |
| State | `production-ready` | `experimental` (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) |
| Token cost | Lower (summary back) | Higher (each teammate = full session) |
| When to use | Isolated task with summary output | Work requiring coordination and debate |

**Rule for Stefano:**
- Sub-agent for: review, research, isolated debug, module test, component scaffold, doc generation. **Default for everything.**
- Agent team for: large cross-layer feature (FastAPI router + React page + tests in parallel), bug investigation with competing hypotheses, multi-perspective code review. **Only for large independent tasks.**

**Flat architecture, deliberate decision (CC 2.1.172 context):** CC 2.1.172 enabled sub-agent nesting up to 5 levels deep (pre-launch classifier in 2.1.178; cap enforced in 2.1.181). The system keeps the orchestrator → sub-agent flat model by design. Reasons: predictable dispatch and bounded cost; clean `PreToolUse`/`PostToolUse` hook propagation (the ADR-0016 `hook_verified` smoke test covers only the one-level dispatch path); fan-out capped at 4 concurrent agents per batch. All four dispatching skills (concept-to-code, deep-refactor, review-triage-fix, autopilot-build) reference §2.2 for this decision rather than restating the constraint as a platform limitation. Source: `code.claude.com/docs/en/changelog.md` v2.1.172, v2.1.178, v2.1.181.

### 2.3 Orchestrator parallelization logic

The orchestrator decides when to spawn sub-agents in parallel by applying 3 criteria (in order):

1. **File independence**: sub-agents touch different files/modules → parallel possible
2. **Test state**: green tests → aggressive parallel; red tests → serial (fix first)
3. **Task type**: research+planning serial; coding+test+doc parallelizable

**Lock file conflict (resolved):** each parallel `coder` runs with `isolation: worktree` in the frontmatter, getting an isolated git copy. No race conditions on imports or shared files.

**Maximum cap:** 4 sub-agents in parallel. If more are needed, sequential batches of 3-4.

---

## 3. Custom sub-agents — complete definitions

All sub-agents live in `~/.claude/agents/` (user-level, valid in all projects) or `.claude/agents/` (project-level, in repo). Managed with `/agents`.

### 3.1 architect

File: `~/.claude/agents/architect.md`

```markdown
---
name: architect
description: Designs system architecture, writes ADR, decomposes complex tasks into implementation plans. Use proactively at the start of any non-trivial feature or refactor. Never writes production code.
tools: Read, Grep, Glob, Bash(git *), Bash(rg *), WebSearch, WebFetch
model: opus
permissionMode: plan
memory: project
effort: xhigh
---

You are a senior software architect with 20+ years of experience.

Your job:
1. Read SPEC.md (if present), CLAUDE.md, ARCH.md, and relevant existing code
2. Decompose the task into 3-8 concrete implementation steps
3. Write or update an Architecture Decision Record at docs/architecture/ADR-NNN-<title>.md following this structure:
   - Context (problem statement)
   - Decision (chosen approach)
   - Alternatives considered (and why rejected)
   - Consequences (positive and negative)
4. Identify files to create/modify and the API/contract changes
5. Flag risks, dependencies, and HITL gates needed
6. NEVER write production code. Return the plan and stop.

Use sequential-thinking MCP when the design space is complex.
Update your memory with patterns and decisions you discover.
```

> **Deployment note (2026-07-11, ADR-0036):** the deployed/staging `architect.md` widens `tools` beyond the two entries above -- `Bash(git *), Bash(rg *)` stay unchanged, plus `Bash(bash *), Bash(npx markdownlint-cli2*), Bash(npx --yes markdownlint-cli2*), Bash(python3 *), Bash(shasum *)` for the verification-by-execution this roadmap's architect dispatches routinely use (test harness, `npx markdownlint-cli2`, frontmatter/YAML checks, content hashing) -- still far short of unrestricted Bash for direct invocations (the interpreter-class entries `bash`/`python3` remain a disclosed wrapped-command residual — ADR-0036 Consequences). `permissionMode: plan` is deliberately **not** restored: verified against `code.claude.com/docs/en/agent-sdk/permissions` (2026-07-11), plan mode blocks every file write pending manual approval "regardless of existing allow rules," and architect's only deliverable is writing the ADR and the plan -- every unattended dispatch (`autopilot-build`, `nightly-autopilot`) would stall on that gate. `effort: xhigh`, not `max` (`max` does not persist in file-based agent config -- `code.claude.com/docs/en/model-config`, 2026-07-11). `memory: project` (shown above) stays absent, superseded by ADR-0012/ADR-0013; not reintroduced. `Write` itself carries no path-scoped rule -- `code.claude.com/docs/en/tools-reference` (2026-07-11) documents path pattern matching for `Read`/`Grep`/`Edit` only, not `Write` -- the write-scope guard stays prompt-level plus the global `protect-files.sh` denylist, a disclosed residual gap. Full reasoning: ADR-0036.

### 3.2 coder

File: `~/.claude/agents/coder.md`

```markdown
---
name: coder
description: Implements production code following an approved plan or ADR. Use after architect has produced a plan and Stefano has approved it. Never commits.
tools: Read, Edit, Write, Glob, Grep, Bash
model: sonnet
isolation: worktree
effort: medium
memory: local
---

You are a senior implementation engineer.

Your job:
1. Read the relevant ADR or plan provided in context
2. Implement the code following the plan exactly
3. Use Conventional Commits in English in any commit message you draft (but NEVER commit yourself: leave that to the orchestrator)
4. Match existing code style by reading 2-3 similar files first
5. Write minimal, idiomatic code: no over-engineering, no premature abstraction
6. Validate your work with the relevant verification tool (test, lint, build) before declaring done
7. Return a summary: files modified, key decisions, verification status

Stack rules come from project CLAUDE.md and .claude/rules/. Read them before writing.
Run in an isolated worktree to avoid conflicts with other parallel coders.
Use the Memory tool (not Edit/Write) to persist context across batches — task completion status, discovered patterns, key decisions. Store sparingly; prefer the return report for anything that fits there.
```

> **Deployment note (2026-05-26):** `isolation: worktree` is now active in the deployed file `~/.claude/agents/coder.md`.
> **Deployment note (2026-05-29):** `memory: local` added. Coder gets a Memory tool scoped to `.claude/agent-memory-local/coder/`. Safety note: `memory:local` adds a dedicated Memory tool; coder must use ONLY that tool for memory writes — never Edit/Write on `.claude/` paths. The pattern-enforce hook (ADR-0001) gates all Edit/Write calls, providing an additional guardrail. See ADR-0016 §Smoke Test and ADR-0012 for memory architecture context.

### 3.3 reviewer

File: `~/.claude/agents/reviewer.md`

```markdown
---
name: reviewer
description: Reviews recently changed code for security, correctness, performance, and consistency with project patterns. Use proactively before any commit involving more than 50 lines of change.
tools: Read, Grep, Glob, Bash(git diff*), Bash(git log*)
model: sonnet
memory: project
---

You are a senior code reviewer.

Workflow:
1. Run `git diff` to see recent changes
2. Read modified files in full to understand context
3. Check your memory for known patterns and recurring issues in this project
4. Review against this checklist:
   - Security: input validation, SQL injection, hardcoded secrets, auth flow
   - Correctness: logic bugs, edge cases, error handling
   - Performance: N+1 queries, unnecessary loops, blocking calls in async paths
   - Consistency: matches existing patterns in the codebase
   - ADR alignment: any deviation from documented architectural decisions
5. Format output by severity: BLOCKER, MAJOR, MINOR, NIT
6. For each issue: file:line reference + suggested fix
7. Update your memory with patterns you observe (recurring issues, anti-patterns)

Output is markdown, not a code diff. The orchestrator decides what to apply.
```

> **Deployment note (2026-07-11, ADR-0036):** the deployed/staging `reviewer.md` keeps the read-only git scope above exactly (`Bash(git diff*), Bash(git log*)` -- no `git add`/`git commit`, preserving the agent's own "never run mutating git or shell commands" invariant) and widens `tools` beyond it with `Bash(bash *), Bash(awk *), Bash(python3 *)` for the verify-by-execution capability this roadmap's reviewer dispatches and the `review-triage-fix` skill rely on -- narrower than architect's set (no `npx`, no `shasum`, no bare `git *`) since reviewer processes untrusted diff content. This direct-invocation framing is qualified, not absolute -- the `bash`/`awk`/`python3` interpreter-class grants can wrap a mutating git command; the exclusion is an accidental-misuse guard, and the explicit risk-acceptance decision plus the hook-level follow-up are recorded in ADR-0036 Consequences. Full reasoning: ADR-0036.
>
> **Amended 2026-07-14 (ADR-0038):** the deployed/staging set also carries `Bash(rg *), Bash(grep *)`. On native macOS/Linux builds CC serves Grep/Glob through Bash as embedded `ugrep`/`bfs` (v2.1.117) and silently ignores the frontmatter's dedicated Grep/Glob entries, which had left this agent with no direct search path; the two grants are read-only and stay inside the same verify-by-execution category as the 2026-07-11 widening.

### 3.4 tester

File: `~/.claude/agents/tester.md`

```markdown
---
name: tester
description: Writes and runs unit/integration tests targeting ~70% coverage on critical business logic. Use after coder finishes implementing a feature.
tools: Read, Edit, Write, Glob, Grep, Bash
model: sonnet
---

You are a pragmatic test engineer.

Your scope:
- TEST: business logic, calculations, API endpoints, parsing, security-sensitive code
- SKIP: pure UI presentation, glue code, configuration, trivial getters/setters

Framework selection by stack:
- Python: pytest + pytest-asyncio
- TypeScript: Vitest + @testing-library/react
- Swift: XCTest + Swift Testing (prefer Swift Testing for new tests)

Workflow:
1. Read the code under test
2. Read existing tests in the project to match style and conventions
3. Cover: happy path, edge cases, error paths, boundary values
4. Run the test suite and verify all pass
5. Report: tests added, coverage on the touched modules, any failures

Never modify production code. If a test reveals a bug, report it and let the debugger or coder fix it.
```

### 3.5 debugger

File: `~/.claude/agents/debugger.md`

```markdown
---
name: debugger
description: Diagnoses errors, test failures, and unexpected behavior. Use proactively on any runtime error, red test, or bug report. Performs root cause analysis.
tools: Read, Edit, Bash, Grep, Glob
model: sonnet
memory: project
---

You are an expert debugger specializing in root cause analysis.

Workflow:
1. Capture the full error: stack trace, log lines, exact reproduction steps
2. Check your memory for similar past issues
3. Isolate the failure: which line, which input, which environment
4. Form 2-3 hypotheses, test each one with minimal probes (logging, repl, isolated repro)
5. Identify root cause (not symptom)
6. Apply minimal fix
7. Verify fix resolves the issue without breaking other paths
8. Update your memory with the bug pattern and resolution

Output:
- Root cause explanation
- Evidence supporting diagnosis
- Code fix applied
- Test added to prevent regression (or recommendation if test framework absent)
- Prevention recommendation

Focus on the underlying issue. Never suppress errors or symptoms.
```

### 3.6 doc-writer

File: `~/.claude/agents/doc-writer.md`

```markdown
---
name: doc-writer
description: Writes README sections, inline documentation, ADR, CHANGELOG entries. Use after a feature merges or on explicit request.
tools: Read, Edit, Write, Glob, Grep
model: haiku
---

You are a technical writer for software projects.

Language rules:
- All output in English.
- Commit messages: English (Conventional Commits)

Style:
- Specific over abstract
- Examples over explanations
- Diagrams (ASCII) where structure helps
- Maximum signal per token

For long-form English prose (articles, posts), invoke the human-writing-style skill.
```

### 3.7 refactorer

File: `~/.claude/agents/refactorer.md`

```markdown
---
name: refactorer
description: Improves code structure without changing behavior. Reduces duplication, simplifies logic, modernizes patterns. Use on explicit request or when reviewer flags structural issues.
tools: Read, Edit, Glob, Grep, Bash
model: sonnet
memory: project
---

You are a refactoring specialist.

Iron rules:
1. Existing tests must stay green. Run them before and after.
2. Maximum 200 lines changed per pass without a checkpoint
3. Each refactor commit must be behavior-preserving
4. If you cannot prove behavior preservation, stop and surface the risk

Patterns to apply:
- Extract method when a block has clear purpose
- Replace magic numbers with named constants
- Collapse duplicated branches
- Remove dead code (verified unused via grep)

Update your memory with refactoring patterns successful in this codebase.
```

### 3.8 researcher

File: `~/.claude/agents/researcher.md`

```markdown
---
name: researcher
description: Researches library documentation, API references, best practices, normative standards. Use when context7 MCP would help or when an unfamiliar library is being adopted.
tools: Read, Grep, Glob, WebSearch, WebFetch
model: haiku
effort: low
mcpServers:
  - context7:
      type: stdio
      command: npx
      args:
        - -y
        - "@upstash/context7-mcp"
---

You are a technical researcher.

Sources priority:
1. Official documentation of the library/standard (prefer context7 MCP for library docs)
2. Authoritative blogs (library author, language team)
3. Well-cited Stack Overflow / GitHub discussions
4. Recent dates only (last 18 months for fast-moving libraries)

Output discipline:
- Every claim has a URL citation
- Distinguish facts, opinions, and hypotheses
- If sources disagree, report the disagreement
- If you cannot verify, say "unverified"

Return a concise brief, not an essay. The orchestrator decides what to act on.
```

> **Deployment note (2026-05-29):** `mcpServers: context7` added inline. This makes researcher self-contained — no dependency on the global context7 plugin being installed. If both global and inline are present, they resolve to the same server; no conflict.

> **Correction (2026-07-11, ADR-0036):** the note above does not match deployed or staging reality -- no inline `mcpServers` block exists in either `~/.claude/agents/researcher.md` or `staging/plugin/agents/researcher.md` (confirmed by reading both). The syntax shown above is also stale: current `code.claude.com/docs/en/sub-agents` (2026-07-11) documents `mcpServers` as a YAML **list**, each inline entry keyed by server name with an explicit `type: stdio` field, corrected above. Not deployed to `researcher.md` in this pass -- no live smoke test is available to confirm the resulting tool-name prefix reaches the agent's `tools` allowlist before trusting it unattended (same posture as ADR-0016/ADR-0029). `researcher` currently relies entirely, and successfully, on the global `context7` plugin already installed -- unaffected by this correction.

### 3.9 Agent frontmatter — available fields (v2.1.154+)

| Field | Values | Purpose |
|---|---|---|
| `name` | string | Agent ID — used in dispatch and audit logs |
| `description` | string | Trigger description for orchestrator routing |
| `tools` | comma list | Allowed tools; omit a tool to restrict access |
| `model` | `opus`, `sonnet`, `haiku` | Model tier; defaults to session model. CC 2.1.183 shows a deprecation warning when this field names a deprecated or auto-updated model. Use bare tier aliases, not version-specific IDs, to stay insulated |
| `effort` | `low`/`medium`/`high`/`xhigh`/`max` | Effort level; overrides session `effortLevel` |
| `color` | color name | UI label color; cosmetic only |
| `isolation` | `worktree` | Run in an isolated git worktree (coder only) |
| `memory` | `local` / `project` / `user` | Persistent memory scope for this agent |
| `mcpServers` | YAML list | Inline MCP server definitions scoped to this agent |

**`memory: local`** scopes memory to `.claude/agent-memory-local/<name>/` — git-ignored, NOT the curated orchestrator auto-memory. The agent gets a dedicated Memory tool. All Edit/Write operations still go through the normal tool gate (pattern-enforce hook for coder). Use Memory tool only for memory writes, never Edit/Write on `.claude/` paths.

**`mcpServers` scoping rule:** general-purpose MCPs (github, sequential-thinking) stay global (settings.json or plugins). Domain-specific MCPs (project-specific databases, APIs, Figma tokens) go in the agent's frontmatter — this avoids polluting every session with servers only one agent needs, and makes the agent self-contained when shared across repos.

```yaml
# Example: researcher with inline context7 (self-contained, no plugin dependency)
mcpServers:
  - context7:
      type: stdio
      command: npx
      args:
        - -y
        - "@upstash/context7-mcp"
```

### 3.10 Cost model

Models and effort levels chosen to reduce token spend while maintaining quality:

| Agent | Model | Effort | Rationale |
|--------|---------|--------|-----------|
| architect | opus (→ 5) | **xhigh** | Native default for Opus; ADR/design = most impactful step in the chain. Automatic fallback to `high` if dispatched with `model: sonnet` override |
| reviewer, debugger | sonnet (→ 5) | **high** | Pre-commit gate and root-cause: requires reasoning, not just execution |
| coder, refactorer, tester | sonnet (→ 5) | **medium** | Execute a pre-defined plan; downstream reviewer and snapshot harness cover errors |
| doc-writer, researcher | haiku (→ 4.5) | **low** | Bottleneck is I/O (reading code/searching), not reasoning |

**CC 2.1.197 default-model shift:** Sonnet 5 is now the Claude Code default. Every agent pins a bare tier alias (`opus`/`sonnet`/`haiku`), so the five Sonnet agents pick up Sonnet 5 with no config change and the table holds as written. Sonnet 5 closes much of the gap to Opus 4.8 at a lower price (promo $2/$10 per Mtok through Aug 31, then $3/$15, versus Opus 4.8 at $5/$25). Where accuracy matters most on a Sonnet agent (reviewer, debugger, or a complex coder task), prefer raising effort toward `xhigh` over escalating the model: Sonnet 5 approaches Opus 4.8 mid-effort quality at its top reasoning tier while staying at Sonnet pricing. This is a per-invocation recommendation, not a frontmatter change.

**CC 2.1.219 Opus 5 release — one pinned override needs a manual fix:** Claude Opus 5 (`claude-opus-5`) is now the default Opus model, shipping with 1M context as a first-class feature (no separate opt-in variant confirmed) and fast-mode pricing of $10/$50 per Mtok; base (non-fast-mode) pricing is not stated in the source changelog entry, so it is not asserted here. `architect` pins the bare tier alias `opus`, which would normally pick up Opus 5 automatically with no frontmatter change, matching the 2.1.183 precedent (sec. 3.9) that all 8 agents are insulated from specific version IDs by design. **However**, the live `~/.claude/settings.json` (mirrored at `staging/user/settings.json`) sets `env.ANTHROPIC_DEFAULT_OPUS_MODEL: "claude-opus-4-8[1m]"` — an explicit override installed to pin the 1M-context variant of Opus 4.8 before Opus 5 existed (flagged, not stripped, by ADR-0025 §3.3 Alternative C as a "future issue"). This override takes precedence over the bare-alias resolution and would keep `architect` on Opus 4.8 indefinitely even after the platform default moves to Opus 5. Recommended fix (staged in this audit, pending the mandatory-diff sync described in `docs/RUNBOOK.md` Step 3): update the value to `"claude-opus-5"`, dropping the `[1m]` suffix since 1M context is native to the new model per the changelog wording, rather than an opt-in variant as it was for 4.8. Confidence: medium — the exact model-identifier string is corroborated by two independent sources (the changelog entry and this session's system-provided model-ID list), but whether a `[1m]`-suffixed variant exists or is required for Opus 5 is not confirmed by either source. Also noted: CC 2.1.219 removes Opus 4.7 from fast mode (`/fast` now covers Opus 5 and Opus 4.8 only) — no impact, this system does not document `/fast` usage on the architect dispatch path.

**Fable 5 promo experiment (2026-07-01 to 07-07), empirical recalibration:** the Fable 5 promo (a temporary quota running 07-01 to 07-07) prompted a narrow off-blueprint allocation. `architect` moved down-tier opus→fable-5, while `reviewer` and `debugger` moved up-tier sonnet→fable-5. One day of real use settled the question. On 2026-07-02 a full concept-to-code build (a six-tier app) drove roughly 2.68M Fable output tokens across 7 agent sessions, about 80% of the promo quota. The token snapshots put the bulk on the reviewer/debugger up-tier: Opus-class tokens spent on review and debug work that Sonnet handled well enough. On 07-03 the recalibration split the two. `reviewer` and `debugger` went back to sonnet; `architect` stayed on fable-5 through 07-07 (Opus-quality planning at promo price, one call per tier, the promo's real value), after which a scripted revert restores the blueprint tiers. The lesson holds: Fable has no permanent seat in the haiku/sonnet/opus tiering. Down-tiering opus→fable on the low-volume planning agent pays off under a promo; up-tiering sonnet→fable on per-tier review and debug agents burns the quota for a marginal quality gain. Verified against the token snapshots in `~/.claude/snapshots/`; the absolute quota percentage is the user's dashboard reading, not independently measured.

**CC 2.1.183:** WebSearch was returning empty results in subagents; now fixed. `researcher` and `architect` are the only agents with WebSearch and both benefit automatically.

**CC 2.1.172/2.1.178/2.1.181 nesting context:** CC 2.1.172 enabled foreground sub-agent nesting (up to 5 levels); 2.1.178 added a pre-launch classifier that evaluates each sub-agent spawn before it runs; 2.1.181 enforces the depth cap. This system keeps the flat model by deliberate choice. See §2.2 for the rationale. The "no sub-agent spawns sub-agent" invariant in the four dispatching skills is a design decision, not a platform limitation. CC 2.1.187 tightened depth tracking further: forked subagents now count toward the cap and resumed subagents restore their original spawn depth, so the limit holds across forks and resumes. The flat model stays comfortably under it regardless.

**CC 2.1.174 Workflow `agent()` attribution:** fixed Workflow tool `agent()` subagents missing attribution headers in commits and PRs. In this system all git commits route through the `commit` skill via the Skill tool (not from within workflow `agent()` subagents directly), so no behavioral change. Config-level attribution (`commit`/`pr` empty, `sessionUrl: false`) governs all commits regardless of dispatch path.

**Workflow `agent()` model inheritance (CLI model does NOT cascade into the chain):** a workflow
subagent dispatched with `agentType` but no `model` option inherits the **main-loop (CLI session)
model**, not the agent's frontmatter. The Agent-tool dispatch paths honor frontmatter; the Workflow
path does not unless `model` is passed. So the `concept-to-code` Step 5/6 workflow scripts pin
`model` on every `agent()` call (coder → `coder_model`, sonnet default; reviewer → sonnet; fix
agents → opus). This keeps the chain on the table above no matter which model the orchestrator
session runs — e.g. reasoning strategy in Opus while the chain still executes coder/reviewer on
Sonnet. See `concept-to-code` SKILL.md §4 Step 5/6.

**Available effort levels by model:**
- Opus 4.8 / Sonnet 5: `low`, `medium`, `high`, `xhigh`, `max` (Sonnet 5 exposes the `xhigh` "Extra High" tier the prior Sonnet generation lacked)
- Opus 4.6 / Sonnet 4.6: `low`, `medium`, `high`, `max` (`xhigh` → fallback to `high`)
- Opus 5: effort-tier support not stated in the CC 2.1.219 changelog entry; insufficient data to list here, assume parity with Opus 4.8 (`low`/`medium`/`high`/`xhigh`/`max`) pending live confirmation
- `max` is session-level only (not persistable in settings.json)

Sonnet 5 gaining `xhigh` is what makes the effort-over-model recommendation in sec. 3.10 viable: a Sonnet agent can now run at the same top reasoning tier as Opus. (The `xhigh` support on Sonnet 5 is drawn from launch coverage, not yet confirmed live here.)

Override possible at individual invocation level via `CLAUDE_CODE_SUBAGENT_MODEL`.
The session default (`effortLevel: high` in settings.json) is overridden by the sub-agent frontmatter; the env var `CLAUDE_CODE_EFFORT_LEVEL` takes precedence over everything.

---

## 4. Global CLAUDE.md (`~/.claude/CLAUDE.md`)

**Target <200 lines** per Anthropic best practice. Only things that apply to every session. Everything else goes in skills, rules, hooks.

```markdown
# CLAUDE.md — Stefano Ferri

## Identity

- User: Stefano Ferri
- My name is Adriano. The user is Stefano. Never invert.
- Language: English throughout — chat, docs, code, commits, docstrings.
- Tone: direct, concise, technical. No filler, hype, soft CTAs.

## Invariant behavioral rules

- IMPORTANT: Plan mode required for any task modifying >1 file or touching production migrations/config
- IMPORTANT: Conventional Commits in English (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`)
- IMPORTANT: Never `git push --force` without explicit approval from Stefano
- IMPORTANT: Never modify migrations already applied in production
- IMPORTANT: Never disable tests to make them pass. If a test needs changing, explain why in chat first.
- IMPORTANT: Confidence declared in chat at end of task. Never in deliverables.

## Default workflow

- For a new non-trivial task: interview mode → SPEC.md → fresh session → plan mode → implementation
- For a large cross-layer feature: consider agent-teams (requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
- For a focused task: orchestrator + custom sub-agent
- HITL gate always before: commit, push, deploy, DB schema changes, permanent deletions

## Custom sub-agents (in ~/.claude/agents/)

architect, coder, reviewer, tester, debugger, doc-writer, refactorer, researcher.
See /agents for details. Max 4 parallel.

## Custom skills (in ~/.claude/skills/)

To create with `skill-creator` for vibe coding workflows:
claude-md-generator, swift-vibe, fastapi-react-vibe, code-review-checklist,
adr-writer, interview-driver, project-bootstrap.

## Active MCP servers

sequential-thinking, github, XcodeBuildMCP, sqlite/postgres-mcp.
Optional if installed: serena, context7, playwright.

## Final response for each task

Close with (in order):
1. 2-3 line summary
2. Modified files (list)
3. Test status: green / red / not run
4. Confidence (e.g. "92% — verified on sample, missing edge case test X")

## Imports

Stack-specific goes in project CLAUDE.md (repo root) or in .claude/rules/.
```

**Adherence notes (Anthropic):**
- CLAUDE.md is loaded as a user message after the system prompt, not as the system prompt. Adherence is not guaranteed: specificity is required
- Keywords like "IMPORTANT" or "YOU MUST" increase adherence (verified in best practices)
- Block-level HTML comment `<!-- note -->` does not consume context (gets stripped). Useful for maintenance notes

**Settings complementary to CLAUDE.md (`~/.claude/settings.json`):**

For professional branding: disable the automatic "Co-Authored-By: Claude" signature in commits and PRs.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "attribution": {
    "commit": "",
    "pr": "",
    "sessionUrl": false
  },
  "permissions": {
    "defaultMode": "acceptEdits"
  }
}
```

- `$schema`: enables autocomplete and JSON validation in Cursor/VS Code
- `attribution.commit: ""`: removes "Co-Authored-By: Claude Sonnet ..." from the commit message. Commits will appear as made by Stefano, no AI attribution
- `attribution.pr: ""`: same for PR body
- `attribution.sessionUrl: false` (CC 2.1.183): omits the claude.ai session link from commits and PRs in web and Remote Control sessions. Has no effect on local CLI sessions; `detect-tool-traces.sh` covers those retroactively
- Without this override, Claude Code adds a `Co-Authored-By: Claude` trailer by default (old `includeCoAuthoredBy: false` is deprecated, use `attribution`)

---

## 5. Path-scoped rules (`.claude/rules/`)

Pattern recommended by Anthropic to **avoid bloating CLAUDE.md**. Rules with `paths:` frontmatter load only when Claude touches matching files.

### 5.1 Global rules (`~/.claude/rules/`)

`~/.claude/rules/python.md`:

```markdown
---
paths:
  - "**/*.py"
---

# Python rules

- Type hints required on public functions; mypy strict mode
- Google-style docstrings on public modules and classes
- f-strings for formatting, never `%` or `.format()`
- `pathlib.Path` instead of `os.path`
- Never `print()` in production code: use `logging`
- Async for I/O bound, sync for CPU bound
- Package manager: `uv` (not pip)
```

`~/.claude/rules/typescript-react.md`:

```markdown
---
paths:
  - "**/*.{ts,tsx}"
---

# TypeScript & React rules

- `interface` for props, `type` for union/utility
- Never `any`: use `unknown` + narrowing
- Function components + hooks, no class components
- `useState` for local state, Context/Zustand for shared
- No prop drilling beyond 2 levels
- Never `useEffect` without a correct dependencies array
- Never direct React state mutations
```

`~/.claude/rules/swift.md`:

```markdown
---
paths:
  - "**/*.swift"
---

# Swift & SwiftUI rules

- Prefer `struct` over `class` unless real hierarchies are needed
- `@Observable` (iOS 17+) instead of `ObservableObject` for new code
- `let` by default, `var` only when mutability is needed
- `private` by default
- Never force-unwrap `!` in production, never `try!` except in documented cases
- View < 150 lines, extract into private structs when it grows
- `body` pure: use `.onAppear`, `.task`, `.onChange` for side effects
- `LazyVStack`/`LazyHStack` for long lists
- Localizable.strings for all user-facing text
```

`~/.claude/rules/sql-migrations.md`:

```markdown
---
paths:
  - "**/alembic/versions/*.py"
  - "**/migrations/*.sql"
---

# DB migration rules

- IMPORTANT: Never modify a migration already applied in production
- DB backup before production migration
- HITL gate before `alembic upgrade head` in any environment other than dev
- Migrations generated with `alembic revision --autogenerate -m "..."`
- Always verify the generated diff before committing
```

### 5.2 Project rules (`<repo>/.claude/rules/`)

Each project can have specific rules committed in git, shared with the team. Example for a FastAPI API:

`<repo>/.claude/rules/api-conventions.md`:

```markdown
---
paths:
  - "backend/src/**/api/**/*.py"
---

# API conventions

- Router per domain in api/ (one per feature)
- Explicit Pydantic response model on every endpoint
- Status codes: 200/201/204/400/401/403/404/422/500
- Dependency injection for DB session, auth, settings
- Never `session.query(Model).filter(...)` (legacy): use `select(Model).where(...)`
- Explicit eager loading with `selectinload` / `joinedload`
```

### 5.3 Advantages of the rules pattern

1. CLAUDE.md stays under the <200-line threshold
2. Stefano sees only the rules relevant to the file being worked on
3. Minimal context cost (lazy loading on path match)
4. Modular: add/remove without touching CLAUDE.md

---

## 6. Project CLAUDE.md templates

### 6.1 SwiftUI / iOS template

`<ios-project>/CLAUDE.md`:

```markdown
# CLAUDE.md — [PROJECT_NAME] (iOS)

Inherits ~/.claude/CLAUDE.md. Specializes for this project.

## Project

- Type: iOS app SwiftUI
- Target: iOS 17+
- Bundle ID: com.example.[name]
- Swift 5.10+, pure SwiftUI, SwiftData

## Commands (via XcodeBuildMCP)

- Build: `build` (Debug default)
- Test: `test` (XCTest + Swift Testing)
- Clean: `clean`
- Simulator: `simulator boot/install`
- Archive: only on explicit HITL gate

## Structure

App/, Features/<Feature>/, Core/, DesignSystem/, Resources/, Tests/.

## Test target

70% coverage on business logic. Minimal UI tests: smoke + happy path.
Snapshot tests optional for DesignSystem.

## Accessibility (required)

- Every interactive View has .accessibilityLabel
- VoiceOver tested on main flows
- Dynamic Type supported

## Imports

@~/.claude/rules/swift.md
```

### 6.2 Generic template (FastAPI + React + Python)

`<project>/CLAUDE.md`:

```markdown
# CLAUDE.md — [PROJECT_NAME]

Inherits ~/.claude/CLAUDE.md. Specializes for this project.

## Project

- Type: web app (FastAPI backend + React frontend)
- Repository: [URL]
- Maintainer: Stefano Ferri

## Stack

| Layer | Choices | Version |
|-------|--------|----------|
| Backend | FastAPI + SQLAlchemy 2.x + Pydantic v2 + Alembic | latest |
| Frontend | React 19.2 + TypeScript 5.9 + Vite 6.4 + Tailwind 4.2 + shadcn/ui 4.0 | latest |
| DB dev | SQLite | — |
| DB prod | [production DB: SQL Server / PostgreSQL / MySQL] | — |
| Package | uv (Python), pnpm (Node) | — |

## Commands

- Backend test: `uv run pytest`
- Backend lint: `uv run ruff check`
- Frontend test: `pnpm test`
- Frontend lint: `pnpm lint`
- Type check: `uv run mypy src/` and `pnpm tsc --noEmit`

## Structure

See ARCH.md for details. Backend in backend/src/, frontend in frontend/src/.

## Imports

@~/.claude/rules/python.md
@~/.claude/rules/typescript-react.md
@~/.claude/rules/sql-migrations.md
@./docs/architecture/ADR-INDEX.md
```

---

## 7. Hooks — deterministic automation

Hooks are shell commands that run at precise points in the lifecycle. They are **deterministic**: no LLM involved (except `type: prompt` or `agent`, **not available on `Stop`** — see the 2026-05-19 correction at the top and admonitions in 7.4/7.5). They guarantee that an action always happens.

**Inspection:** `/hooks` opens the hooks browser with all hooks configured per event. Read-only; to modify, edit `settings.json`.

**Debug:** `InstructionsLoaded` hook fires when a CLAUDE.md or rules file is loaded — useful for debugging path-scoped loading or lazy-load in subdirectories.

### 7.1 Critical hooks to configure in `~/.claude/settings.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/auto-format.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Reminder: stack is FastAPI+React+TS, NO Flask/Bootstrap. Conventional Commits in English. Green tests before commit.'"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude is waiting for input\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}
```

### 7.2 Hook `protect-files.sh` (blocks .env, applied migrations, .git)

`~/.claude/hooks/protect-files.sh`:

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

PROTECTED_PATTERNS=(".env" "package-lock.json" "uv.lock" ".git/" "secrets.env")

for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "Blocked: $FILE_PATH matches protected pattern '$pattern'. Ask Stefano explicitly." >&2
    exit 2
  fi
done

exit 0
```

```bash
chmod +x ~/.claude/hooks/protect-files.sh
```

### 7.3 Hook `auto-format.sh` (automatic formatting after edit)

`~/.claude/hooks/auto-format.sh`:

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

case "$FILE_PATH" in
  *.py)
    ruff format "$FILE_PATH" 2>/dev/null
    ruff check --fix "$FILE_PATH" 2>/dev/null
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    if [ -f "package.json" ]; then
      npx prettier --write "$FILE_PATH" 2>/dev/null
    fi
    ;;
  *.swift)
    swift-format -i "$FILE_PATH" 2>/dev/null
    ;;
esac

exit 0
```

### 7.4 Advanced hook — verify green tests before Stop (prompt-based)

> ⚠️ **CORRECTION 2026-05-19 — this example is WRONG.** Live verification of
> `code.claude.com/docs/en/hooks`: `type: prompt` **is not supported
> on the `Stop` event** (only `command`, `http`, `mcp_tool`). Also the
> real block contract is `{"decision":"block","reason":"…"}` or exit code
> 2, **not** `{"ok": false}`. Correct pattern: `type: command` hook on `Stop`
> + counter-based anti-loop guardrail (no native `stop_hook_active`).
> **AS-BUILT 2026-05-19:** implemented and deployed live as a 3-tier testcmd
> gate + TOFU — see reconciliation at the top and
> `docs/superpowers/specs/2026-05-19-swarm-testcmd-design.md` (+ matching plan).
> The JSON example below is kept for historical reference only.

In `~/.claude/settings.json`, under `hooks`:

```json
{
  "Stop": [
    {
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Check if the user's task is complete. If tests should have been run and weren't, or if obvious work remains, respond with {\"ok\": false, \"reason\": \"specific remaining work\"}. Otherwise {\"ok\": true}."
        }
      ]
    }
  ]
}
```

This hook uses Haiku in the background to verify completeness. If not OK, it returns feedback that makes Claude continue.

### 7.5 Agent-based hook — effective green-test verification (more expensive)

> ⚠️ **CORRECTION 2026-05-19 — this example is WRONG.** `type: agent` **is not
> supported on the `Stop` event** (live verification `code.claude.com/docs/en/hooks`).
> To actually run tests before Stop, use a `type: command` hook
> that invokes the test suite and blocks with `{"decision":"block","reason":"…"}` /
> exit code 2. **AS-BUILT 2026-05-19:** this is exactly the function
> of the deployed authoritative tier (runs the command declared in
> `.claude/test-cmd`, approved via TOFU, real exit code) — "Phase B" of
> the old agentic-swarm spec is **subsumed** by it. See
> `docs/superpowers/specs/2026-05-19-swarm-testcmd-design.md` (+ matching plan).
> JSON example below kept for historical reference only.

```json
{
  "Stop": [
    {
      "hooks": [
        {
          "type": "agent",
          "prompt": "Run the project test suite. If any test fails or no test was run since last code change, respond with {\"ok\": false, \"reason\": \"test failures: <details>\"}.",
          "timeout": 120
        }
      ]
    }
  ]
}
```

More reliable (real verification), more expensive (subagent with tool access, up to 50 turns).

### 7.6 Hook filesystem layout

```
~/.claude/                       # AS-BUILT 2026-05-19 (Stop-gate testcmd live)
├── settings.json                # global hooks (Stop→stop-gate.sh)
├── hooks/
│   ├── protect-files.sh         # PreToolUse  Edit|Write
│   ├── auto-format.sh           # PostToolUse Edit|Write
│   ├── chain-memory-capture.sh  # PostToolUse Bash  → records chain state (ADR-0021)
│   ├── mark-dirty.sh            # PostToolUse Edit|Write  → marks .dirty
│   ├── ensure-state-dir.sh      # SessionStart            → creates state dir
│   ├── reset-gate-counter.sh    # UserPromptSubmit        → resets anti-loop counter
│   ├── stop-gate.sh             # Stop  → 3-tier testcmd gate (CANONICAL)
│   ├── stop-gate.v2.sh          #   byte-identical twin (backout artifact)
│   ├── approve-test-cmd.sh      # CLI TOFU (not a hook): approves test-cmd
│   ├── backup-before-deploy.sh  # pre-deploy backup utility
│   └── tests/run-hook-tests.sh  # unit harness (PASS=28 FAIL=0)
└── state/stop-gate/             # runtime state: trust, <sid>.dirty/.count

<repo>/.claude/
├── test-cmd                     # per-project declaration: command | NONE
└── settings.json                # optional project-specific hooks
```

### 7.7 Hook `chain-memory-capture.sh` (records chain state into the native store)

`PostToolUse` hook, matcher `Bash` (ADR-0021). It records `concept-to-code` chain task completion
and current state of fact into the native memory store, so progress persists across sessions and
is browsable via `/memory`. It is **deterministic** (zero-LLM) and **observational**: it always
exits 0 and never blocks the Bash tool.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$HOME\"/.claude/hooks/chain-memory-capture.sh" }
        ]
      }
    ]
  }
}
```

What it does on each Bash call:

1. **Gate on helper identity.** Acts only when `.tool_input.command` invokes a manifest helper
   (`manifest-transition.sh` / `manifest-set-gate.sh` / `manifest-set-flag.sh` /
   `manifest-set-artifact.sh`). Everything else is an immediate no-op.
2. **Gate on success.** If `.tool_response.exit_code` is present and non-zero, the mutation failed
   → record nothing.
3. **Resolve the store, scope-safely.** Derives `~/.claude/projects/<encoded>/memory/` from
   `dirname(.transcript_path)` — never re-encodes `$PWD` (ADR-0012 D2). It cannot write to another
   project's store.
4. **Write** the event to `memory/chain-history/<slug>.md` (STATE OF FACT header rewritten in
   place + append-only event log) and upsert a one-line pointer in the `MEMORY.md` managed block.

**Why a hook and why it is safe here:** the manifest helpers are run only by the orchestrator (the
main CLI session), where PostToolUse fires reliably — so the ADR-0016 question about hook
propagation into Step-5 workflow subagents is out of scope. Because the writer is a deterministic
hook bound to the session's own encoded dir (no LLM choosing the path), the ADR-0013 auto-write
failure cannot recur. Storage format and rotation are documented in sec. 13.

---

## 8. Skills — knowledge and workflows

### 8.1 Bundled skills (already available in Claude Code)

| Skill | Use |
|-------|-----|
| `/batch <instruction>` | Large-scale migration/refactor: decompose into 5-30 units, parallelize in git worktrees, opens PR. Official Anthropic pattern for batch ops |
| `/simplify [focus]` | Automated recent review: spawns 3 parallel review sub-agents, aggregates findings, applies fixes |
| `/debug [description]` | Enables debug logging, analyzes session log |
| `/loop [interval] <prompt>` | Execute prompt repeatedly (useful for deploy polling, CI) |
| `/claude-api` | Loads Claude API reference for the project language (Python, TS, Java, Go, etc.) |

### 8.2 Custom skills — agent to skill mapping

| Sub-agent | Recommended skills |
|-----------|-------------------|
| architect | `adr-writer` (new), `multi-role-brainstorm` (if present) |
| coder | `swift-vibe` (new), `fastapi-react-vibe` (new), `json-validator` |
| reviewer | `code-review-checklist` (new) |
| tester | (none specific) |
| debugger | `pdf-reading`, `file-reading` |
| doc-writer | `human-writing-style` (if present), `docx`/`pptx`/`xlsx`/`pdf` |
| refactorer | (none specific) |
| researcher | `youtube-dl` (if present) |

### 8.3 New skills to create (with `skill-creator`)

All in `~/.claude/skills/<name>/SKILL.md`.

**Frontmatter casing and resilience (CC 2.1.186).** The `display-name`, `default-enabled`,
`fallback`, and `metadata.*` keys now accept kebab-case, snake_case, and camelCase interchangeably.
The blueprint skills already use kebab-case, so nothing migrates. A malformed `SKILL.md` YAML
frontmatter block now loads the skill body with empty metadata instead of failing silently, which
makes a broken header visible rather than dropping the skill.

**`interview-driver`** — Starts interview mode with a standard prompt.

```yaml
---
name: interview-driver
description: Starts interview mode with AskUserQuestion to define SPEC.md for a new project or feature. Use proactively at the start of any new project or non-trivial feature.
argument-hint: [brief description of the project/feature]
disable-model-invocation: true
---

The user wants to build: $ARGUMENTS

Use the AskUserQuestion tool to interview in depth.
Cover: technical implementation, UI/UX (if applicable), edge cases,
trade-offs, operational constraints, Definition of Done.

Do not ask obvious questions. Dig into hard points. One question at a time,
max 3-4 options per question.

Continue until you have covered everything. Then write SPEC.md in the current folder
with: objectives, scope, stack, architecture, data model, API, UI flows,
edge cases, success criteria.
```

**`adr-writer`** — Generates a standardized ADR.

```yaml
---
name: adr-writer
description: Generates an Architecture Decision Record in the docs/architecture/ folder. Use when the user makes an architectural decision or uses the architect agent.
argument-hint: [decision title]
---

Create ADR-NNN-$ARGUMENTS.md in docs/architecture/ (with incremental NNN).

Required structure:
1. Status (Proposed / Accepted / Deprecated / Superseded)
2. Context (problem, constraints, requirements)
3. Decision (choice made, stated clearly)
4. Alternatives considered (at least 2, with reason for rejection)
5. Consequences (positive, negative, neutral)
6. References (links to related ADRs, docs, issues)

No fluff. Every section concrete and specific.
```

**`claude-md-generator`** — Generates a project CLAUDE.md.

```yaml
---
name: claude-md-generator
description: Generates root CLAUDE.md for a new project based on SPEC.md and ARCH.md. Use after SPEC and ARCH are ready.
---

Read SPEC.md and ARCH.md in the current folder.

Generate a project CLAUDE.md following the appropriate template:
- If stack is SwiftUI/iOS → iOS template (section 6.1 of Vibe Coding System)
- Otherwise → generic template (section 6.2)

Adapt: project name, actual stack, real commands, chosen folder structure.

Import @~/.claude/rules/ relevant to the stack.
Target: under 100 effective lines.
```

**`swift-vibe`** — SwiftUI patterns and snippets.

```yaml
---
name: swift-vibe
description: SwiftUI best practices with ready-to-use snippets for View, ViewModel, SwiftData, async/await. Use when working on iOS/SwiftUI projects.
paths:
  - "**/*.swift"
---

SwiftUI best practices with ready-to-use snippets.
Pattern: Observable+Bindable (iOS 17+), SwiftData @Query, URLSession async.
Expand this skill with additional patterns as you encounter them.
```

**`fastapi-react-vibe`** — Scaffold FastAPI endpoint + React component.

```yaml
---
name: fastapi-react-vibe
description: Generates scaffold for a FastAPI endpoint with Pydantic schema, service, router, test, and corresponding React component with fetch hook. Use when adding a CRUD feature to a FastAPI+React project.
argument-hint: [resource name]
disable-model-invocation: true
---

Generate scaffold for resource "$ARGUMENTS":

Backend (backend/src/<pkg>/):
- models/<arguments>.py: SQLAlchemy 2.x model with Mapped[]
- schemas/<arguments>.py: Pydantic v2 with Create/Update/Read
- services/<arguments>.py: business logic
- api/<arguments>.py: FastAPI router with CRUD endpoints
- tests/<arguments>_test.py: pytest with 4 base tests

Frontend (frontend/src/):
- features/<arguments>/api.ts: fetch wrappers
- features/<arguments>/hooks.ts: useQuery / useMutation
- features/<arguments>/<Arguments>List.tsx: shadcn/ui table
- features/<arguments>/<Arguments>Form.tsx: react-hook-form + zod form
- routes: add route to routing config

Follow existing ADRs. Match style with existing code.
```

**`code-review-checklist`** — Structured output for the reviewer agent.

```yaml
---
name: code-review-checklist
description: Performs structured review on git diff with categorical checklist. Use when the reviewer agent does a code review.
---

Run `git diff` and analyze recent changes.

Structured output by severity:

## BLOCKER (must fix before merge)
- ...

## MAJOR (should fix)
- ...

## MINOR (consider fixing)
- ...

## NIT (style/preference)
- ...

For each issue: file:line + description + suggested fix.

Required categories to cover:
- Security (input validation, secrets, auth)
- Correctness (logic, edge cases, error handling)
- Performance (N+1, blocking calls)
- Consistency (patterns, ADR alignment)
- Test coverage
```

**`project-bootstrap`** — Runs PHASE 1 of the concept→code workflow in one shot.

```yaml
---
name: project-bootstrap
description: Runs full bootstrap of a new project (interview → SPEC.md → ARCH.md → CLAUDE.md). Use only for small new projects that justify a fast workflow.
argument-hint: [brief description]
disable-model-invocation: true
---

Bootstrap project: $ARGUMENTS

Step 1: invoke interview-driver with the description
Step 2: after SPEC.md, generate ARCH.md (main architectural decisions with ADR-001..N)
Step 3: invoke claude-md-generator for root CLAUDE.md
Step 4: initialize git, make initial commit "chore: initial spec and architecture"
Step 5: present a summary of generated files

HITL gate after each step. Stefano must approve before proceeding.
```

### 8.4 Path-scoped skills

Pattern: skills with `paths:` frontmatter load only for matching files. Reduces context noise.

E.g. `swift-vibe` has `paths: ["**/*.swift"]` — Claude sees the skill only when editing Swift files.

### 8.5 Skills with `context: fork`

For skills that run in an isolated sub-agent (heavy research, batch ops):

```yaml
---
name: deep-research
description: In-depth research in isolated context
context: fork
agent: Explore
---

Research $ARGUMENTS:
1. Use Glob/Grep to find relevant files
2. Read and analyze
3. Summarize findings with file references
```

`agent: Explore` uses the built-in Explore (read-only; inherits the session model, capped at opus, since CC 2.1.198; was Haiku). The subagent does the work, the main context receives only the summary.

### 8.6 Deployed custom skills (active as of 2026-06)

| Skill | Invocation | When to use | Notes |
|-------|-----------|------------|-------|
| `concept-to-code` | `/skill concept-to-code [express\|hybrid\|standard] <title>` | Start any non-trivial feature | Orchestrator: 3 paths, manifest 1.3, 7+ HITL gates. Canonical implementation of §11 |
| `review-triage-fix` | `/skill review-triage-fix` | After implementation, before merge | Per-branch JSON state, circuit breakers A–D, NIT batching. Step 6 in Standard chain |
| `deep-refactor` | `/skill deep-refactor` | Whole-codebase health audit | 4-dim parallel audit → sequential fix. Gate 5.1 in Standard chain (ADR-0018) |
| `claude-md-slim` | `/skill claude-md-slim [--global] [<root>]` | CLAUDE.md has grown >100 lines | Extracts domain sections to rules files. ≥30% reduction target (ADR-0019) |
| `humanize-en` | `/skill humanize-en` | Before publishing prose to an outside audience (Reddit/HN, forum, blog, newsletter). NOT for docs, ADR, commits, PR bodies | Strips AI tells, preserves Vibrofer IT terms (ADR-0015, narrowed by ADR-0040) |
| `design-brainstorm` | invoked by `concept-to-code` at Gate 1b | When design space is wide, before architecture | Structured ideation → BRAINSTORM.md |
| `macos-ux` | invoked by `concept-to-code` at Gate 1c | macOS/SwiftUI projects | HIG + accessibility rules. Auto-detected from SPEC.md |
| `ui-layout-audit` | invoked by `concept-to-code` at Gate 5.05 | When UI files are present after implementation | Layout conformance review |
| `clean-public-repo` | `/skill clean-public-repo` or Gate 0b | Before pushing to a public remote | Anonymization + optional history rewrite (ADR-0011) |
| `vibe-status` | `/skill vibe-status` | System health check any time | Aggregates harness results for all skills, hooks, agents. <10s |
| `interview-driver` | invoked by `concept-to-code` at Step 1 | Start of any interview | AskUserQuestion loop → SPEC.md |
| `claude-md-generator` | invoked at Step 3 | After SPEC.md + ARCH.md ready | Generates project CLAUDE.md from spec |
| `commit` | `/skill commit [hint]` | After any implementation cycle | HITL-verified Conventional Commit wizard. Step 7 in all chain paths |
| `agent-design` | reference via Read | When designing new agents or multi-agent patterns | 7 Sayfan reference files (01–07) |

All live in `~/.claude/skills/<name>/`. Each has a `SKILL.md`, optional `scripts/` helpers, and a `tests/` harness. The chain skills (rows 1–4) are integrated into the `concept-to-code` orchestrator; they can also be invoked standalone.

---

## 9. MCP servers

### 9.1 Core MCP (install with priority)

**Anthropic-recommended pattern**: use the `claude mcp add` CLI instead of manually editing `.mcp.json`. The default scope is `local` (current project only, in `~/.claude.json`). To share with the team: `--scope project` writes to versioned `.mcp.json`.

```bash
# Sequential thinking (stdio)
claude mcp add --transport stdio --scope user sequential-thinking \
  -- npx -y @modelcontextprotocol/server-sequential-thinking

# GitHub remote MCP (HTTP — replaces the old stdio @modelcontextprotocol/server-github)
claude mcp add --transport http --scope user github \
  https://api.githubcopilot.com/mcp/ \
  --header "Authorization: Bearer $GITHUB_TOKEN"

# SQLite local (stdio)
claude mcp add --transport stdio --scope project sqlite \
  -- npx -y @modelcontextprotocol/server-sqlite --db-path ./dev.db

# XcodeBuildMCP (already installed by Stefano)
```

Alternatively, `.mcp.json` in project root for project scope (versioned with team):

```json
{
  "mcpServers": {
    "sequential-thinking": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer ${GITHUB_TOKEN}"
      },
      "alwaysLoad": false
    },
    "sqlite": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sqlite", "--db-path", "./dev.db"]
    }
  }
}
```

**Important notes:**
- `${VAR}` expands env vars; `${VAR:-default}` with fallback. Secret tokens never inline
- Server name `workspace` is reserved, never use it
- `alwaysLoad: true` forces loading all server tools at session start (see 9.3 tool search)

### 9.2 Recommended optional MCP

- **serena**: LSP wrapper, semantic code intelligence. Useful on large codebases for accurate refactors
- **context7**: up-to-date library docs. Reduces hallucinations when the researcher does API lookups
- **playwright**: automated web E2E tests for the tester
- **extended filesystem-mcp**: batch file operations

### 9.3 MCP tool search

Anthropic enables tool search by default (`ENABLE_TOOL_SEARCH=true`): only MCP tool names load at startup, full schemas are deferred until use. Idle MCP cost is minimal.

For servers with tools needed every turn (e.g. github): `"alwaysLoad": true` in server config. Loads all tools at startup. Trade-off: more context consumed always, but no search step.

**MCP output limits:**
- Default 25,000 tokens per tool result; warning at 10,000
- Override: `MAX_MCP_OUTPUT_TOKENS=50000` in env for tools producing large output (database query, log file)
- Server author can mark individual tool with `_meta["anthropic/maxResultSizeChars"]` up to 500,000

**Diagnostics:** `/mcp` shows status, token cost per server, and tool count. Disconnect unused servers.

**CLI auth (CC 2.1.186).** `claude mcp login <name>` and `claude mcp logout <name>` authenticate a
server straight from the CLI without opening the interactive `/mcp` menu, and `--no-browser`
redirects the flow through stdin so it completes over SSH. This is the headless-friendly path for
the GitHub remote MCP. `claude mcp get` and `claude mcp remove` now suggest the closest configured
server name on a typo and truncate long server lists.

**Remote-MCP idle abort (CC 2.1.187).** A remote MCP tool call that returns no response for five
minutes now aborts with an error instead of blocking indefinitely; `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT`
overrides the threshold. This bounds a hung GitHub remote MCP call the same way the 2.1.186 retry
watchdog bounds an unattended retry loop. The env var name is documented here; its value format is
not pinned, since the settings schema does not yet list it.

---

## 10. Permission modes — operational guide

Six modes available. Cycle with `Shift+Tab` (modes included: default → acceptEdits → plan → auto). Auto and bypassPermissions require explicit activation.

| Mode | Behavior | When to use |
|------|---------------|---------------|
| `default` | Asks for every edit and bash | Session start, sensitive tasks, exploration |
| `acceptEdits` | Auto-accepts file edits, asks for bash | During active implementation |
| `plan` | Read-only, proposes plan without executing | Starting a new feature, structural refactor |
| `auto` | Classifier in background, blocks prompt injection and scope escalation. CC 2.1.183 adds native blocking of destructive git commands (`git reset --hard`, `git checkout -- .`, `git clean -fd`, `git stash drop`, `git commit --amend` on non-agent commits) and IaC destroy commands in this mode | Long tasks on Team/Enterprise plan |
| `dontAsk` | Auto-deny everything except allowlist | CI, locked environments |
| `bypassPermissions` | Skip controls (with exceptions for `.git`, `.claude`) | Isolated containers, devcontainer |

### For Stefano specifically

Memory says "bypassPermissions mode configured". That is OK but risky for prompt injection. Better alternatives:

1. **If on Pro/Max plan** (likely Stefano's case):
   - Default: `acceptEdits` (set as default in `~/.claude/settings.json` → `permissions.defaultMode`)
   - Explicit plan mode for new features (`/plan` or `Shift+Tab` in session, `--permission-mode plan` at startup)
   - Allowlist for recurring commands (`uv run pytest`, `pnpm test`, `pnpm lint`, etc.)

2. **If moving to Team/Enterprise/API plan**:
   - `auto` mode is the new best practice: Sonnet 4.6 classifier in background, blocks prompt injection automatically
   - Requires Sonnet 4.6 or Opus 4.6 as the main model

3. **For large codebases**: combine with hook `protect-files.sh` (sec. 7.2). Hook deny rules take precedence over any permission mode, including `bypassPermissions`. Layered defense.

### Recommended allowlist for Stefano

`~/.claude/settings.json` (full example combining permission mode, allowlist, attribution):

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "attribution": {
    "commit": "",
    "pr": "",
    "sessionUrl": false
  },
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash(uv run pytest*)",
      "Bash(uv run ruff*)",
      "Bash(uv run mypy*)",
      "Bash(pnpm test*)",
      "Bash(pnpm lint*)",
      "Bash(pnpm build*)",
      "Bash(git status)",
      "Bash(git diff*)",
      "Bash(git log*)",
      "Bash(git add*)",
      "Bash(git commit*)",
      "Bash(rg*)",
      "Bash(fd*)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(git push --force*)",
      "Bash(git reset --hard*)",
      "Bash(git clean -f*)",
      "Bash(git stash drop*)",
      "Bash(git checkout -- *)"
    ]
  }
}
```

Note: `rm -rf *` replaces the narrower `rm -rf /` and `rm -rf ~` entries (the wildcard subsumes both). The git entries mirror the CC 2.1.183 native auto-mode block, extended to all permission modes via deny. `git commit --amend` is intentionally absent. The native block handles the agent-vs-human distinction correctly; a blanket deny would break legitimate amend of agent commits.

**UI management:**
- `/config` opens the tabbed settings interface (Status, Config). More convenient than direct JSON editing
- `/config key=value` sets a specific setting from the prompt (CC 2.1.181). `/config --help` lists all available shorthand keys
- `/status` shows which settings sources are active in the current session (User / Project / Local / Managed). Confirms the file is being loaded

**Settings precedence** (high → low):
1. Managed settings (server or MDM)
2. CLI args (`--permission-mode`, `--settings`)
3. `.claude/settings.local.json` (gitignored, personal per project)
4. `.claude/settings.json` (project, versioned)
5. `~/.claude/settings.json` (user)

Arrays (`permissions.allow`, `deny`) are **concatenated and deduplicated** across scopes; scalars (`defaultMode`, `model`) use the value at the highest priority.

**Exception (CC 2.1.207):** `autoMode` is read only from user-level `~/.claude/settings.json`, `--settings`, and managed settings, never from the repo-resident `.claude/settings.local.json` or `.claude/settings.json`, so a cloned repo cannot widen auto mode's authority.

**Subagent-spawn permission rules (CC 2.1.186).** `Agent(type)` deny rules and `Agent(x,y)`
allowed-types restrictions are now enforced for named subagent spawns; before 2.1.186 they were
ignored. This extends the layered-defense model to the spawn boundary: a deny rule can block a
specific agent type, and an allow rule can pin the set of types that may run. The blueprint does not
ship an active Agent allowlist in `staging/user/settings.json` on purpose. A restrictive allow rule
would also have to enumerate the built-in `Explore`, `Plan`, and `general-purpose` agents plus any
plugin agent types and the Workflow runtime, or it would silently break plan mode and the parallel
dispatch paths. The capability is documented here so a target project with a fixed agent set can opt
in; the blueprint default stays permissive and relies on hook-level guards.

**`respondToBashCommands` (CC 2.1.186).** The release made `!` bash commands trigger an automatic
Claude response to their output. The blueprint sets `respondToBashCommands: false` in
`staging/user/settings.json` to keep the previous context-only behavior, which suits the `!`-prefix
pattern used for quick checks and interactive logins where an auto-response each time is just noise.

**`sandbox.credentials` (CC 2.1.187).** The release added a `sandbox.credentials` setting that blocks
sandboxed commands from reading credential files and secret environment variables, hardening the
sandbox layer against secret exfiltration. This reinforces the global guardrail against exposing
secrets. It is documented here but not pinned in `staging/user/settings.json`: the settings schema
does not yet list the key, so its value shape (boolean or object) is unconfirmed. Pin it once the
schema confirms the format, the same discipline applied to `CLAUDE_CODE_RETRY_WATCHDOG` in 2.1.186.

---

## 11. End-to-end workflow: concept → code

> Official Anthropic pattern from `code.claude.com/docs/en/best-practices`
> (sections "Explore first, then plan, then code" and "Let Claude interview you").

**Canonical implementation.** The manual workflow described in §11.3–11.5 is codified as the `concept-to-code` orchestrator skill (§8.6). Use `/skill concept-to-code` for all non-trivial features. The skill selects the path (Express/Hybrid/Standard) via Gate 0, manages the manifest state machine, calls the sub-skills at the right gates, and enforces all HITL gates. The manual steps below remain accurate as a reference for understanding the workflow, but they are superseded in practice.

### 11.1 Founding principles

1. **Interview before code**: for non-trivial features/projects, AskUserQuestion before code. Decisions discovered while still "cheap"
2. **Spec as source of truth**: interview output = `SPEC.md`
3. **Fresh session to implement**: new session for coding (clean context). Never mix interview and coding in the same session
4. **Plan mode**: separates exploration from execution. `Ctrl+G` to edit the plan in editor
5. **Verification**: every feature has a self-verification method (tests, screenshot, expected output)
6. **Aggressive context**: `/clear` between unrelated tasks, `/compact` if needed for focus, sub-agents for deep investigations

### 11.2 Cowork vs Claude Code by phase

| Phase | Optimal tool |
|------|-------------------|
| Brainstorming, gathering sources | **Cowork** (UI, Gmail/GDrive/Notion connectors) |
| SPEC.md generation (interview mode) | **Cowork** or **Claude Code** (both valid) |
| ARCH.md generation | **Claude Code** (preferred, close to the code) |
| Root CLAUDE.md generation | **Claude Code** (tested immediately) |
| Scaffold, dependencies, structure | **Claude Code** |
| Code implementation | **Claude Code** |
| Tests, refactor, debug | **Claude Code** |
| PR, review, CI | **Claude Code** + `gh` CLI |
| Slides, client docs | **Cowork** (docx/pptx/pdf skills) |

### 11.3 Workflow A — Cowork → Claude Code

**Estimated time:** PHASE 1 in Cowork 30-90 minutes, PHASE 2 depends on project.

#### PHASE 1 — Cowork (concept → spec → structure)

**Step 1.1.** Open Cowork. Tab Cowork → New project → name `<project-name>`. Attach local folder `~/dev/<name>`. Mode: "Ask before acting".

**Step 1.2.** Brain dump. 2-3 free paragraphs of the idea. Attach documents, screenshots, mockups. Use connectors (Notion, GDrive, GitHub) if useful.

**Step 1.3.** Start Interview Mode. Prompt:

```
I want to build [1-2 line brief description].

Interview me in depth using the AskUserQuestion tool.
Cover: technical implementation, UI/UX, edge cases, trade-offs,
operational constraints, Definition of Done.

Do not ask obvious questions. One question at a time, max 3-4 options.
Continue until you have covered everything. Then write SPEC.md.
```

**Step 1.4.** Answer the questions (typically 15-40, up to 40+ for large projects).

**Step 1.5.** Cowork generates SPEC.md. Verify: objectives, scope, stack, architecture, data, API, UI flows, edge cases, success criteria.

**Step 1.6.** Generate ARCH.md:
```
Based on SPEC.md, create ARCH.md with a block diagram (ASCII),
architectural decisions (ADR-001..N), discarded trade-offs,
proposed folder structure.
```

**Step 1.7.** HITL gate: re-read SPEC.md and ARCH.md. Edit directly if needed. When satisfied, close Cowork.

#### PHASE 2 — Claude Code (CLAUDE.md → scaffold → implementation)

**Step 2.1.** Open Claude Code:
```bash
cd ~/dev/<name>
claude
```

Verify with `/memory` that `~/.claude/CLAUDE.md` is loaded.

**Step 2.2.** Generate project CLAUDE.md:
```
/claude-md-generator
```
(custom skill — sec. 8.3). Or direct prompt:
```
Based on SPEC.md and ARCH.md, generate root CLAUDE.md using the appropriate template
(SwiftUI/iOS or generic). Import rules from ~/.claude/rules/.
Target under 100 lines.
```

**Step 2.3.** Initialize git and initial commit:
```
initialize git, make initial commit "chore: initial spec and architecture"
with SPEC.md, ARCH.md, CLAUDE.md, docs/architecture/
```

**Step 2.4.** Project scaffold. Enter plan mode:
```
/plan
Read SPEC.md, ARCH.md, CLAUDE.md.
Propose a plan for the initial scaffold: folder structure, config files
(pyproject.toml / package.json / Package.swift), minimal dependencies,
test framework, linter, .gitignore.
Scaffold only, no production code.
```

**Step 2.5.** HITL gate: approve the plan. `Ctrl+G` to edit.

**Step 2.6.** Exit plan mode (Shift+Tab → acceptEdits). Execute scaffold. Verify setup works. Commit.

**Step 2.7.** First feature (multi-agent workflow):

```
Implement feature [name] described in SPEC.md section [X].

Workflow:
1. Invoke @"architect (agent)" for ADR-NNN-<name>.md
2. STOP for my approval
3. Parallelize max 4 sub-agents:
   - @"coder (agent)" backend (if applicable, isolation: worktree)
   - @"coder (agent)" frontend (if applicable, isolation: worktree)
   - @"tester (agent)"
   - @"doc-writer (agent)"
4. @"reviewer (agent)" final
5. STOP for commit approval
6. Commit Conventional Commits in English
```

**Step 2.8.** Iteration. After each feature: `/clear` to clean context. For an unrelated task: new session.

**Step 2.9.** Final PR:
```
Create PR via github MCP. Title "feat(<scope>): <description>".
Body: summary, link to SPEC.md section, modified files, test results.
```

### 11.4 Workflow B — All in Claude Code

Identical but with PHASE 1 inside Claude Code:

**Step B.1.** Create folder and open Claude Code.

**Step B.2.** Invoke custom skill:
```
/project-bootstrap [brief description]
```

Or manually:
```
/interview-driver [brief description]
```

**Step B.3.** Same steps 1.5-1.7 as variant A.

**Step B.4.** CRITICAL: `/clear` or fresh session before scaffold (`claude --continue` or new `claude`). The interview context contaminates the implementation.

**Step B.5.** Proceed from Step 2.4 of variant A.

### 11.5 Workflow diagram

```
┌────────────────────────────────────────────────────────────┐
│ PHASE 1 — CONCEPT & SPEC (Cowork or Claude Code)           │
│                                                             │
│   Brain dump → Interview mode (AskUserQuestion 15-40q)     │
│        ↓                                                    │
│   SPEC.md  ←──── HITL Stefano                              │
│        ↓                                                    │
│   ARCH.md (+ ADR-001..N)  ←──── HITL Stefano               │
│        ↓                                                    │
│   Root CLAUDE.md  ←──── HITL Stefano                       │
└─────────────────────┬──────────────────────────────────────┘
                      │
                /clear or fresh session
                      │
                      ▼
┌────────────────────────────────────────────────────────────┐
│ PHASE 2 — IMPLEMENTATION (Claude Code)                     │
│                                                             │
│   Scaffold (plan mode → HITL → execute → commit)           │
│        ↓                                                    │
│   ┌── Per feature: ───────────────────────────────────┐    │
│   │  architect → ADR → HITL                           │    │
│   │       ↓                                            │    │
│   │  [coder+tester+doc-writer parallel (worktree)]    │    │
│   │       ↓                                            │    │
│   │  reviewer → HITL                                   │    │
│   │       ↓                                            │    │
│   │  Conventional Commit → PR github MCP              │    │
│   │       ↓                                            │    │
│   │  /clear                                            │    │
│   └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘
```

### 11.6 When to use agent-teams (instead of sub-agents)

For complex cross-layer features Stefano can consider agent-teams. Example for a FastAPI+React web app:

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
claude
```

Prompt:
```
Create a team of 4 teammates to implement feature [X]:
- backend-dev: implement FastAPI endpoint + service + schema
- frontend-dev: implement React page + form + table
- test-engineer: write pytest and vitest tests for the feature
- reviewer: review all work and flag issues

Use subagent definitions (architect for initial planning, then spawn teammates
with the tools of the corresponding subagent). Coordinate via shared task list.
```

Advantages vs sub-agents:
- Each teammate has full context for their layer (vs sub-agent that has only a summary)
- They can debate and challenge each other (useful for debugging with competing hypotheses)
- Self-claim tasks: reduce orchestrator coordination

Limitations:
- Lead limited to Sonnet 4.6/Opus 4.6
- No `/resume` with in-process teammates
- More expensive (each teammate = full session)
- 3-5 teammates optimal, no scaling beyond
- `display mode`: `tmux` (split panes) or `in-process`. On macOS Stefano can use iTerm2 with `it2` CLI

**Teammate display backend (CC 2.1.186).** Agent-team display is now selectable with the
`teammateMode` setting; `teammateMode: "iterm2"` drives split sessions through the `it2` CLI, with a
warning when auto mode cannot find `it2` on PATH. This formalizes the iTerm2 note above and sits
alongside the `tmux` and `in-process` options. CC 2.1.186 also fixed teammates spawned through tmux
or pane backends so they inherit the leader's `--effort` level.

---

## 12. Worktrees — robust parallelization

Parallel `coder` sub-agents use `isolation: worktree` in the frontmatter: they automatically get an isolated git worktree. Internal pattern managed by Claude Code, nothing to configure on the sub-agent side.

**Killed-agent worktree cleanup (CC 2.1.187).** Locked `.git/worktrees/` entries left behind by killed agents are now cleaned up automatically, so a `coder` or workflow agent terminated mid-run no longer leaks a stale worktree registration that would need manual pruning.

**For Stefano (manual worktrees):**

```bash
# Terminal 1: auth feature
claude --worktree feature-auth
# creates .claude/worktrees/feature-auth/ with branch worktree-feature-auth

# Terminal 2: bug fix in parallel
claude -w bugfix-payments
# -w is short alias for --worktree

# Worktree from specific PR (parallel review)
claude --worktree "#456"
# fetches pull/456/head and creates .claude/worktrees/pr-456/
```

**Branching pattern (`worktree.baseRef` in settings.json):**

- Default `"fresh"`: branch from `origin/<default-branch>`. Clean worktree, aligned with remote
- `"head"`: branch from local HEAD. Carries unpushed commits and feature-branch state into the worktree. Useful for sub-agents working on in-progress work

```json
{
  "worktree": {
    "baseRef": "head",
    "symlinkDirectories": ["node_modules", ".cache"]
  }
}
```

**Important caveats:**
- Worktree does NOT automatically copy gitignored files (`.env`, `secrets.json`, etc.) — see `.worktreeinclude` below
- Worktree shares the `.git` object database with the main repo (disk-efficient) but does not carry `node_modules`, `uv venv`, `target/`, `.next/`. For large projects two options:
  - `worktree.symlinkDirectories: ["node_modules"]` — symlink from the main repo (risk: lock file conflict, needs testing)
  - Reinstall deps in the worktree (`uv sync`, `pnpm install`) — safe, slower

**`.worktreeinclude` — copy gitignored files into the worktree**

File at the project root (versioned with the team) that lists gitignored files to copy into every new worktree. Gitignore syntax.

```
# .worktreeinclude
.env
.env.local
config/secrets.json
```

Without this, every freshly created worktree is missing env files and must be set up manually before tests/build work.

**Automatic cleanup:** a worktree with no changes is cleaned up automatically when the session ends. A worktree with changes persists for manual review/merge.

> **Fix 2.1.149 — sandbox write allowlist:** before this version the write allowlist in a worktree covered the entire main repo instead of just the shared `.git/` (with `hooks/` and `config` denied). Resolved. The `coder` sub-agent with `isolation: worktree` is now correctly sandboxed.

**Practical limits:**
- 2-4 parallel worktrees are the reasonable ceiling (beyond that there is only review overhead)
- Multi-checkout IDEs: VS Code/Cursor OK. Others (Xcode on iOS, some JetBrains) flaky with worktrees

---

## 13. Auto memory

Real Claude Code feature (v2.1.59+). Saves automatic learnings in `~/.claude/projects/<repo>/memory/MEMORY.md`.

- Loading: first 200 lines or 25KB of MEMORY.md at each session
- Topic files (debugging.md, patterns.md, etc.) loaded on-demand
- Inspection: `/memory` to browse and edit
- Disable: `autoMemoryEnabled: false` in settings.json or `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` as env var
- Custom path: `autoMemoryDirectory: "~/my-memory"` in settings (accepted only by user settings, not project — security: a cloned repo could redirect memory)
- Compaction reminder (CC 2.1.186): the agent is reminded to compact its `MEMORY.md` index when the file nears the size limit. For chain memory (sec. 13.1, ADR-0021) this is a no-op, since the auto-maintained block is already bounded; the reminder applies only to the human-curated index above it.

For Stefano: leave it active. Claude accumulates patterns from your projects over time (build commands, debug insights, conventions). Periodically verify via `/memory` to check what has been saved.

**Sub-agents with `memory: project`** (defined in sec. 3): have separate memory in `.claude/agent-memory/<name>/`. The reviewer accumulates recurring issues, the debugger bug patterns, the architect past decisions. Shareable via git (useful on codebases with multiple collaborators).

### 13.1 Chain memory — `memory/chain-history/` (ADR-0021)

A third namespace under the native store records `concept-to-code` chain execution facts, written
by the deterministic `chain-memory-capture.sh` hook (sec. 7.7), not by any agent. It sits alongside
the curated `MEMORY.md` and the ADR-0012 `agent-notes/`, separate from both:

```
~/.claude/projects/<encoded>/memory/
├── MEMORY.md            # curated index (human) + a delimited chain-memory managed block
├── agent-notes/<agent>.md   # per-agent durable patterns (ADR-0012)
└── chain-history/<slug>.md  # per-feature chain execution facts (ADR-0021)
```

Each `chain-history/<slug>.md` carries a **STATE OF FACT** header (`current_step`, `status`,
`chain_path`, `last_gate`, `next_action`, `updated_at`) rewritten in place on each event, plus an
**append-only event log** (one line per step/gate/flag/artifact). `MEMORY.md` holds only a
one-line pointer per chain inside a delimited block (`<!-- chain-memory:begin -->` …
`<!-- chain-memory:end -->`): a `### Active chains` section surfaced at SessionStart, and a
`### Archived chains` section capped at the last 10 terminal chains. Human-curated content above the
begin marker is never touched, and **no `CLAUDE.md` is involved**.

- **Distinct from the manifest** (`docs/manifests/*.yml`): the manifest is the single-run live
  state in the tree; chain-history is the cross-run, cross-session history in the curated store. The
  hook reads the manifest to derive chain-history; it never replaces it.
- **Rotation:** event log capped at 200 lines (oldest pruned), archived pointers at 10 — the
  footprint stays well inside the 25KB SessionStart auto-load window.
- **Recall:** `/memory` browses `chain-history/` directly; a read-only `vibe-status` section lists
  active chains from the STATE OF FACT headers (follow-up live task).

---

## 14. Anthropic marketplace plugins

Ready-made packages from `/plugin`:

- **`superpowers`** (obra/superpowers): TDD enforcement, Socratic brainstorming, granular planning, automatic code review between tasks. Official Anthropic marketplace plugin.
- **`spec-kit`** (GitHub): Spec-Driven Development toolkit. Constitution → Specify → Plan → Tasks structure. Compatible with any coding agent.
- **code intelligence plugin**: if installed for the language (Python, TypeScript, Swift), Claude gets precise symbol navigation and automatic error detection after edits. Recommended.

Installation: `/plugin` → browse marketplace → install.

**Testing a plugin locally before packaging:**

```bash
# Load plugin directly from local folder (development/test)
claude --plugin-dir ./my-plugin

# Load plugin from remote .zip (CI/fast sharing)
claude --plugin-url https://example.com/plugin.zip
```

**When Stefano has field-tested the 6 custom skills from sec. 8.3** (interview-driver, adr-writer, claude-md-generator, swift-vibe, fastapi-react-vibe, code-review-checklist), he can package them into a `stefano-vibe-coding` plugin (skills + agents) and share it via a private GitHub repo. Advantage: versioned, updatable, reusable.

---

## 15. Installation checklist

### Global (once, on work Macs)

- [ ] Create `~/.claude/CLAUDE.md` (sec. 4) — target <100 lines
- [ ] Create `~/.claude/settings.json` with `attribution: {commit:"", pr:"", sessionUrl: false}` to disable Claude signature and session link in commits (CC 2.1.183)
- [ ] Create `~/.claude/rules/python.md`, `typescript-react.md`, `swift.md`, `sql-migrations.md` (sec. 5.1)
- [ ] Create sub-agent files in `~/.claude/agents/` for architect, coder, reviewer, tester, debugger, doc-writer, refactorer, researcher (sec. 3) — use `/agents` interactive
- [ ] Create global hooks in `~/.claude/settings.json` + scripts in `~/.claude/hooks/` (sec. 7)
- [ ] Configure default permission mode `acceptEdits` + allowlist (sec. 10)
- [ ] Install core MCP via `claude mcp add --scope user` (sec. 9.1): sequential-thinking (stdio), github (HTTP), sqlite. XcodeBuildMCP already present.
- [ ] Create custom skills in `~/.claude/skills/` (`interview-driver`, `adr-writer`, `claude-md-generator`, `swift-vibe`, `fastapi-react-vibe`, `code-review-checklist`) using `skill-creator`
- [ ] Evaluate plugin installation: `superpowers`, `spec-kit`, code intelligence for Python/TS/Swift
- [ ] Sync custom skills and agent files via private Git repo across development machines. Never inside iCloud Drive.

### Per project (for each new project)

- [ ] Create SPEC.md (interview mode PHASE 1)
- [ ] Create ARCH.md (with ADR-001..N)
- [ ] Create root CLAUDE.md (appropriate template, sec. 6) — target <100 lines
- [ ] Create `.claude/rules/` with project-specific rules (e.g. API conventions, deployment)
- [ ] Create project `.mcp.json` with specific servers (e.g. sqlite with local dev.db path)
- [ ] Create `.claude/settings.json` with project-specific hooks (e.g. pre-commit lint)
- [ ] Create `.worktreeinclude` with gitignored files to copy into parallel worktrees (`.env`, `secrets.json`)
- [ ] Add `CLAUDE.local.md` to `.gitignore` if personal unshared preferences are needed

### End-to-end test

- [ ] Run the full concept→code workflow on a mini pilot project (e.g. small Python tool)
- [ ] Verify parallel sub-agents with `isolation: worktree` do not create conflicts
- [ ] Verify hook `protect-files.sh` blocks attempts to edit `.env`
- [ ] Verify hook `auto-format.sh` automatically formats after edits
- [ ] (Only if on Team/Enterprise plan) Test `auto` mode on a long task

---

## 16. Anthropic best practices — quick reference

Top 10 to always follow (from `code.claude.com/docs/en/best-practices`):

1. **Verification path always present**: tests, screenshot, expected output
2. **Explore → Plan → Implement → Commit**: four phases, never mix them
3. **Specific context**: files with `@`, pattern references, symptom description
4. **Interview before code**: large features → AskUserQuestion → SPEC.md
5. **Aggressive context**: `/clear` between unrelated tasks, sub-agents for investigation
6. **Course-correct early**: `Esc` to stop, `/rewind` for checkpoint
7. **CLAUDE.md <200 lines**: cut everything Claude can infer from the code
8. **Hooks for must-happen**: more deterministic than CLAUDE.md instructions
9. **Trust then verify**: always verification before ship
10. **Develop intuition**: these rules are a starting point, not dogma

### Critical commands and shortcuts

| Command | Function |
|---------|----------|
| `/init` (or `CLAUDE_CODE_NEW_INIT=1 /init`) | Generates base CLAUDE.md from existing codebase |
| `/config` | Tabbed UI for managing settings (Status, Config) |
| `/status` | Shows active settings sources in the session (User/Project/Local/Managed) |
| `/context` | Token usage by category: system prompt, memory, skill, MCP, messages |
| `/usage` | Cost breakdown by category: skill, subagent, plugin, MCP server (CC 2.1.149) |
| `/doctor` | Installation and configuration diagnostics |
| `/agents` | Wizard removed in CC 2.1.198; manage sub-agents by asking Claude or editing `.claude/agents/` directly |
| `/hooks` | Browse configured hooks (read-only) |
| `/skills` | Skills available from project, user, plugin |
| `/permissions` | Current tool allowlist/denylist |
| `/memory` | Browse CLAUDE.md, rules, and auto memory |
| `/mcp` | MCP server status, token cost, OAuth authentication |
| `/plugin` | Browse marketplace, install/enable plugins |
| `/clear` | Reset context |
| `/compact <instructions>` | Compact with focus |
| `/rewind` or `Esc Esc` | Previous checkpoints |
| `/plan` | Single-turn plan mode (prompt prefix) |
| `/batch <instruction>` | Large-scale migration/refactor |
| `/code-review [effort]` | Correctness review at configurable effort; `--comment` for inline PR comments (ex `/simplify`, renamed CC 2.1.147) |
| `/effort [level]` | Sets effort level for the session; without argument opens interactive slider |
| `/debug [desc]` | Session debug logging |
| `/loop [interval] <prompt>` | Polling task |
| `/btw <question>` | Quick question out of context |
| `Ctrl+G` | Edit plan in editor |
| `Ctrl+B` | Backgroundize current task |
| `Esc` | Stop Claude mid-action (keeps context) |
| `Shift+Tab` | Cycle permission modes |
| `Shift+Down` | Cycle teammate (in agent-teams) |
| `@<file>` | Direct file reference |
| `@"<agent-name> (agent)"` | Explicit sub-agent invocation |
| `claude --continue` | Resume last session |
| `claude --resume` | Choose session from list |
| `claude --worktree <name>` or `-w <name>` | Session in isolated worktree |
| `claude --worktree "#<pr>"` | Worktree from pull request |
| `claude --from-pr <number>` | Resume session associated with a PR |
| `claude --agent <name>` | Start session as sub-agent (system prompt override) |
| `claude --plugin-dir <path>` | Local test of a plugin in development |
| `claude -p "<prompt>"` | Non-interactive mode |

### Writer/Reviewer pattern

For critical code reviews, two distinct sessions:

| Session A (Writer) | Session B (Reviewer) |
|---------------------|----------------------|
| Implements the feature | (fresh context) |
| | Review @src/<file>.ts — look for edge cases, race conditions, consistency |
| Applies B's feedback | |

Session B "fresh" → no bias toward recently written code.

### Anthropic anti-patterns (to avoid)

| Error | Symptom | Fix |
|--------|---------|-----|
| Kitchen sink session | Context contaminated by multiple tasks | `/clear` between unrelated tasks |
| Infinite corrections | Bug + fix + bug + fix | After 2 fixes: `/clear` + better prompt |
| Over-specified CLAUDE.md | Claude ignores rules | Aggressive pruning, target <200 lines |
| Trust-then-verify gap | Plausible but broken code | Always verification (test/screenshot) |
| Infinite exploration | Claude reads 100 files, context full | Explicit scope or sub-agent |
| Same session for interview + code | Contaminated context | Fresh session for coding |
| Skip plan mode on multi-file | Code "solves the wrong problem" | Plan mode when: multi-file change, unfamiliar code, uncertain approach |

---

## 17. Final notes

### Decisions that may evolve

- **Models per agent**: today mapped as (Opus architect, Sonnet coder/reviewer/tester/debugger/refactorer, Haiku doc-writer/researcher). Revisit when new models are released or real quality/cost ratios are measured on your projects
- **Parallelization cap 4**: can rise to 5-6 once stability is validated. Anthropic imposes no hard limit
- **Coverage 70%**: can be raised to 85% on the most critical modules (e.g. calculations, sensitive input validation, external integrations)
- **Agent teams in production**: experimental today. When GA ships, can replace many sub-agent + manual worktree patterns

### Remaining open items

- **Stop-gate testcmd tier validation on the pilot**: the gate is deployed live and harness-green, but the 4 tiers (nudge / opt-out / approve / authoritative green+red) need end-to-end validation in a fresh session on `~/developer/pricing-markup-cli` (swarm-testcmd plan Task 9 Steps 2-4, Stefano-run). Caveat: the pilot has no tests → at least one passing test and a PATH-robust `test-cmd` are needed (e.g. `.venv/bin/pytest -q`)
- **Real `auto` mode performance**: requires moving to Team/Enterprise plan to test. If Stefano stays on Pro/Max, `acceptEdits` + hook protect is the path
- **Auto memory hygiene**: periodically clean `~/.claude/projects/<repo>/memory/` if it grows too large or accumulates errors. `/memory` for inspection
- **Remote bootstrap (CC 2.1.150)**: CC calls `api.anthropic.com/api/claude_cli/bootstrap` at startup and GrowthBook (`tengu_heron_brook`) every 60s; injects content into the system prompt. This is first-party configuration (Anthropic), not injection from third parties. For environments with prompt immutability policies: add `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` in `settings.json` `env` block — blocks both channels
- **Skill testing**: the 7 proposed custom skills (sec. 8.3) need to be created with `skill-creator` and field-tested. Iterate the description based on trigger accuracy
- **`CLAUDE_CODE_NEW_INIT=1`**: worth testing the new multi-phase `/init` flow that explores the codebase, asks follow-up questions, and proposes CLAUDE.md + skills + hooks together. Could replace the concept→code workflow for small projects

### Verified vs assumed

**Verified** against official Anthropic docs:
- Sub-agent architecture (YAML files, frontmatter, built-in)
- Agent teams (architecture, limitations, activation)
- Permission modes (six modes, behavior, classifier)
- CLAUDE.md (load order, size target, AGENTS.md import)
- Skills (path-scoped, bundled, context: fork)
- Hooks (events, type, examples)
- MCP (configuration, scoping, tool search)
- Workflow Explore→Plan→Implement→Commit
- Interview mode with AskUserQuestion → SPEC.md → fresh session

**Assumed/to validate in use**:
- Specific models per agent (proposed Opus/Sonnet/Haiku mix)
- 70% coverage as a sensible target for typical projects
- Cap 4 parallel (may vary in practice)
- Effective trigger descriptions for custom skills
- CC 2.1.186 behavior items, taken from the changelog text and not yet smoke-tested here: background
  subagents stall an unattended autopilot run when a tool falls outside the allowlist (ADR-0020);
  `CLAUDE_CODE_RETRY_WATCHDOG` is the unattended retry control and its value format is unspecified;
  Workflow `agent({schema})` aborts after 5 validation failures (ADR-0016)
- CC 2.1.187 behavior items, taken from the changelog text and not yet smoke-tested here: the
  Workflow `agent({schema})` success-path fix (no re-call after a valid result, reliable follow-up
  turns; ADR-0016); background jobs no longer hang on empty subagent output (ADR-0020);
  `sandbox.credentials` blocks sandboxed secret reads but its value format is unconfirmed in the
  schema; remote MCP calls abort after a 5-minute idle with `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT` as
  override
- CC 2.1.198 behavior items, taken from the bundled changelog (`~/.claude/cache/changelog.md`) and
  not yet smoke-tested here: the `claude agents` launcher auto-commits, pushes, and opens a draft PR
  on worktree finish (ADR-0022, scoped to that launcher, not our path); Explore inherits the session
  model capped at opus (was Haiku); subagents and compaction inherit the session extended-thinking
  config; the Workflow worktree edit-block fix (ADR-0016). The online docs at `code.claude.com` still
  end at 2.1.196, so these await re-confirmation against the primary pages once they catch up

---

## Final confidence

**98%** — high confidence on:

- Sub-agent / agent-teams architecture (sec. 2-3): verified against `code.claude.com/docs/en/sub-agents` and `agent-teams`. Built-in subagents, frontmatter fields, persistent memory, worktree isolation, model selection are real and documented Anthropic concepts
- CLAUDE.md hygiene + `attribution` setting (sec. 4): target <200 lines is an explicit Anthropic recommendation, `attribution.commit:""` is the modern pattern for disabling Claude signature (replaces deprecated `includeCoAuthoredBy`)
- Path-scoped rules in `.claude/rules/` (sec. 5): documented pattern, glob support, frontmatter `paths:` verified
- Hooks (sec. 7): protect-files, auto-format, SessionStart compact reinjection examples are official Anthropic patterns. `/hooks` browser and `InstructionsLoaded` debug confirmed. **CORRECTION 2026-05-19:** the claim "`Stop` prompt/agent based" was **wrong** — `type: prompt`/`agent` not supported on `Stop` (live docs verification). Moved from "verified" to corrected; see correction 2026-05-19 at the top and admonitions 7.4/7.5. **AS-BUILT 2026-05-19:** the correct pattern (3-tier `type: command` testcmd gate + TOFU + anti-loop) is **implemented and deployed live**, harness green (PASS=28 FAIL=0) and verified in session — this is *internal as-built verification* (deploy + test), distinct from Anthropic-doc verification; `clear-dirty` heuristic retired
- MCP (sec. 9): `claude mcp add` CLI, local/project/user scope, http/sse/stdio transport, `alwaysLoad`, tool search, `MAX_MCP_OUTPUT_TOKENS` all verified. GitHub HTTP remote endpoint is the current official one
- Permission modes (sec. 10): six modes mapped 1:1 with docs, settings precedence verified, `/config` and `/status` confirmed
- Worktrees (sec. 12): `--worktree`, `-w`, `#<pr>`, `worktree.baseRef`, `.worktreeinclude`, path `.claude/worktrees/<name>/`, branch `worktree-<name>` all verified from docs + recent search results
- concept→code workflow (sec. 11): interview → SPEC.md → fresh session pattern directly from best-practices docs
- Bundled skills (sec. 8.1): `/batch`, `/simplify`, `/debug`, `/loop`, `/claude-api` are real bundled skills, documented
- Diagnostic commands (sec. 16): `/config`, `/context`, `/status`, `/doctor`, `/skills`, `/permissions`, `/plugin` all verified from claude-directory.md

**Remaining 2%** — residual uncertainty:

- Exact behavior of `isolation: worktree` with shared imports (e.g. Python virtual env, `node_modules`). Theoretically a separate git worktree is sufficient; in practice it needs testing on real projects where `uv` and Node modules are heavy. Known mitigations: `worktree.symlinkDirectories` or reinstall deps in the worktree
- The 7 proposed custom skills (sec. 8.3) are designed but not tested. They need to be created, tested for trigger accuracy, and iterated. Anthropic recommends iteration on the `description` field
- Real `auto` mode classifier behavior on Stefano's workflow: without a Team/Enterprise plan it cannot be tested. Anthropic guidance is clear but performance depends on the codebase

Reducing the remaining 2% requires real execution + iteration on a pilot project.

---

**Verified primary sources** (`code.claude.com/docs/`):

- `/en/best-practices` — official best practices
- `/en/sub-agents` — sub-agent architecture
- `/en/agent-teams` — coordinated multi-session
- `/en/memory` — CLAUDE.md, rules, auto memory
- `/en/skills` — complete skill system
- `/en/hooks-guide` — hook automation
- `/en/permission-modes` — six permission modes
- `/en/common-workflows` — common workflows
- `/en/features-overview` — when to use what
- `/en/mcp` — complete MCP (transport, scope, OAuth, tool search, managed)
- `/en/claude-directory` — `.claude/` and `~/.claude/` structure
- `/en/settings` — complete settings.json schema, precedence, attribution
- `/en/plugins` — complete plugin system
- `/en/worktrees` — verified via search (URL not directly fetchable)
- `/en/llms.txt` — complete documentation index

Supplementary:
- `anthropic.com/engineering/claude-code-best-practices` — engineering blog
- `support.claude.com/.../get-started-with-claude-cowork` — Cowork help center
- `kondasamy.com/blog/2026/claude-code-interview-mode/` — interview mode pattern
- `developersdigest.tech/blog/claude-code-interview-mode` — operational patterns
- `datacamp.com/tutorial/claude-code-best-practices` — TDD and spec-driven
- `pub.towardsai.net/...worktree-isolation...` — updated worktree isolation pattern
