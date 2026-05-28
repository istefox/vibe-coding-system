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
    │  ├─ Explore        (read-only, Haiku, codebase search)
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
```

> **Deployment note (2026-05-26):** `isolation: worktree` is now active in the deployed file `~/.claude/agents/coder.md`. Behavior on projects without git: silent fallback, direct edits (no error). The resulting branch on git repos is managed by the orchestrator in the review/merge phase — no changes required to the concept-to-code chain.

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
---

You are a technical researcher.

Sources priority:
1. Official documentation of the library/standard
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

### 3.9 Cost model

Models and effort levels chosen to reduce token spend while maintaining quality:

| Agent | Model | Effort | Rationale |
|--------|---------|--------|-----------|
| architect | opus (→ 4.7) | **xhigh** | Native default for Opus 4.7; ADR/design = most impactful step in the chain. Automatic fallback to `high` if dispatched with `model: sonnet` override |
| reviewer, debugger | sonnet (→ 4.6) | **high** | Pre-commit gate and root-cause: requires reasoning, not just execution |
| coder, refactorer, tester | sonnet (→ 4.6) | **medium** | Execute a pre-defined plan; downstream reviewer and snapshot harness cover errors |
| doc-writer, researcher | haiku (→ 4.5) | **low** | Bottleneck is I/O (reading code/searching), not reasoning |

**Available effort levels by model:**
- Opus 4.7: `low`, `medium`, `high`, `xhigh`, `max`
- Opus 4.6 / Sonnet 4.6: `low`, `medium`, `high`, `max` (`xhigh` → fallback to `high`)
- `max` is session-level only (not persistable in settings.json)

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
    "pr": ""
  },
  "permissions": {
    "defaultMode": "acceptEdits"
  }
}
```

- `$schema`: enables autocomplete and JSON validation in Cursor/VS Code
- `attribution.commit: ""`: removes "Co-Authored-By: Claude Sonnet ..." from the commit message. Commits will appear as made by Stefano, no AI attribution
- `attribution.pr: ""`: same for PR body
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

`agent: Explore` uses the built-in Explore (Haiku, read-only). The subagent does the work, the main context receives only the summary.

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

---

## 10. Permission modes — operational guide

Six modes available. Cycle with `Shift+Tab` (modes included: default → acceptEdits → plan → auto). Auto and bypassPermissions require explicit activation.

| Mode | Behavior | When to use |
|------|---------------|---------------|
| `default` | Asks for every edit and bash | Session start, sensitive tasks, exploration |
| `acceptEdits` | Auto-accepts file edits, asks for bash | During active implementation |
| `plan` | Read-only, proposes plan without executing | Starting a new feature, structural refactor |
| `auto` | Classifier in background, blocks prompt injection and scope escalation | Long tasks on Team/Enterprise plan |
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
    "pr": ""
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
      "Bash(git push --force*)",
      "Bash(rm -rf*)"
    ]
  }
}
```

**UI management:**
- `/config` opens the tabbed settings interface (Status, Config). More convenient than direct JSON editing
- `/status` shows which settings sources are active in the current session (User / Project / Local / Managed). Confirms the file is being loaded

**Settings precedence** (high → low):
1. Managed settings (server or MDM)
2. CLI args (`--permission-mode`, `--settings`)
3. `.claude/settings.local.json` (gitignored, personal per project)
4. `.claude/settings.json` (project, versioned)
5. `~/.claude/settings.json` (user)

Arrays (`permissions.allow`, `deny`) are **concatenated and deduplicated** across scopes; scalars (`defaultMode`, `model`) use the value at the highest priority.

---

## 11. End-to-end workflow: concept → code

> Official Anthropic pattern from `code.claude.com/docs/en/best-practices`
> (sections "Explore first, then plan, then code" and "Let Claude interview you").

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

---

## 12. Worktrees — robust parallelization

Parallel `coder` sub-agents use `isolation: worktree` in the frontmatter: they automatically get an isolated git worktree. Internal pattern managed by Claude Code, nothing to configure on the sub-agent side.

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

For Stefano: leave it active. Claude accumulates patterns from your projects over time (build commands, debug insights, conventions). Periodically verify via `/memory` to check what has been saved.

**Sub-agents with `memory: project`** (defined in sec. 3): have separate memory in `.claude/agent-memory/<name>/`. The reviewer accumulates recurring issues, the debugger bug patterns, the architect past decisions. Shareable via git (useful on codebases with multiple collaborators).

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

**When Stefano has field-tested the 7 custom skills from sec. 8.3** (interview-driver, adr-writer, claude-md-generator, swift-vibe, fastapi-react-vibe, code-review-checklist, project-bootstrap), he can package them into a `stefano-vibe-coding` plugin (skills + agents) and share it via a private GitHub repo. Advantage: versioned, updatable, reusable.

---

## 15. Installation checklist

### Global (once, on work Macs)

- [ ] Create `~/.claude/CLAUDE.md` (sec. 4) — target <100 lines
- [ ] Create `~/.claude/settings.json` with `attribution: {commit:"", pr:""}` to disable Claude signature in commits
- [ ] Create `~/.claude/rules/python.md`, `typescript-react.md`, `swift.md`, `sql-migrations.md` (sec. 5.1)
- [ ] Create sub-agent files in `~/.claude/agents/` for architect, coder, reviewer, tester, debugger, doc-writer, refactorer, researcher (sec. 3) — use `/agents` interactive
- [ ] Create global hooks in `~/.claude/settings.json` + scripts in `~/.claude/hooks/` (sec. 7)
- [ ] Configure default permission mode `acceptEdits` + allowlist (sec. 10)
- [ ] Install core MCP via `claude mcp add --scope user` (sec. 9.1): sequential-thinking (stdio), github (HTTP), sqlite. XcodeBuildMCP already present.
- [ ] Create custom skills in `~/.claude/skills/` (`interview-driver`, `adr-writer`, `claude-md-generator`, `swift-vibe`, `fastapi-react-vibe`, `code-review-checklist`, `project-bootstrap`) using `skill-creator`
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
| `/agents` | Browse/create/edit sub-agents |
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
