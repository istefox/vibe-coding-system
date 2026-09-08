# Skills & Agents — Usage Guide

> Last updated: 2026-06-08. This guide is the practical companion to `docs/vibe-coding-system.md`.
> Read this when you need to know *which tool to use* and *how to invoke it*.

---

## Mental model

The system has two layers:

- **Skills** (`/skill <name>`) — orchestrator-level tools you invoke directly in chat. They
  coordinate agents, run HITL gates, write files, and produce deliverables.
- **Agents** — sub-agents dispatched by the orchestrator (or by skills). You rarely invoke
  agents directly; skills and the concept-to-code chain call them for you.

The main exception: you can explicitly ask for an agent by its role ("debug this crash",
"review this code", "refactor this function") and the orchestrator will dispatch the right one.

---

## Quick-reference table

| Name | Type | One-line | Invoke |
|---|---|---|---|
| `concept-to-code` | Skill | Full chain: interview → ADR → plan → impl → commit | `/skill concept-to-code <topic>` |
| `project-conductor` | Skill | Multi-feature orchestration (runs c2c chains in sequence) | `/skill project-conductor` |
| `commit` | Skill | HITL commit wizard with optional push + PR | `/skill commit` |
| `review-triage-fix` | Skill | Full review+fix cycle with routing to fix agents | `/skill review-triage-fix` |
| `deep-refactor` | Skill | Codebase health audit + regression-safe auto-fix | `/skill deep-refactor` |
| `project-init` | Skill | Bootstrap project CLAUDE.md + context.md | `/skill project-init` |
| `session-state` | Skill | Write cross-session `.claude/context.md` (auto + manual) | `/skill session-state` |
| `vibe-status` | Skill | System health check | `/skill vibe-status` |
| `interview-driver` | Skill | User interview → SPEC.md | `/skill interview-driver` |
| `adr-writer` | Skill | Write an Architecture Decision Record | `/skill adr-writer <topic>` |
| `design-brainstorm` | Skill | Pre-architecture ideation → BRAINSTORM.md | `/skill design-brainstorm` |
| `claude-md-generator` | Skill | Generate CLAUDE.md from SPEC.md + ARCH.md | `/skill claude-md-generator` |
| `claude-md-slim` | Skill | Extract CLAUDE.md sections to path-scoped rules | `/skill claude-md-slim [--global]` |
| `clean-public-repo` | Skill | Remove tool markers before public release | `/skill clean-public-repo` |
| `humanize-en` | Skill | Remove AI tells from English prose | `/skill humanize-en <file>` |
| `macos-ux` | Skill | macOS HIG design interview OR SwiftUI HIG review | `/skill macos-ux` / `/skill macos-ux review` |
| `ui-layout-audit` | Skill | Layout bugs in SwiftUI or HTML/CSS | `/skill ui-layout-audit [file]` |
| `swiftui-pro` | Skill | SwiftUI code review (modern APIs, perf, maintainability) | Keyword-triggered or explicit |
| `swift-vibe` | Skill | SwiftUI patterns quick reference | Keyword-triggered |
| `refactor-snapshot` | Skill | Behavior-preservation harness (used internally by refactorer) | Internal only |
| `code-review-checklist` | Skill | Structured review by severity (used internally by reviewer) | Internal only |
| `agent-design` | Skill | Agent / MCP / orchestration design KB | Keyword-triggered |
| `find-skills` | Skill | Discover and install skills from the open ecosystem | Keyword-triggered |
| `architect` | Agent | Plans, ADRs, design — never writes production code | Dispatched by c2c Step 2 |
| `coder` | Agent | Implements approved plans; worktree-isolated | Dispatched by c2c Step 5 |
| `reviewer` | Agent | Pre-commit code review by severity | Pre-commit or explicit |
| `tester` | Agent | Unit/integration tests after implementation | Post-impl or explicit |
| `debugger` | Agent | Root-cause analysis + minimal fix | On failures or explicit |
| `refactorer` | Agent | Structure improvement with behavior-preservation | Explicit or reviewer-flagged |
| `doc-writer` | Agent | Docs: README, ADR, CHANGELOG, inline | Post-merge or explicit |
| `researcher` | Agent | Citation-backed research brief | Explicit or lookup-needed |

---

## Skills in depth

### concept-to-code — the main chain

Use this for any non-trivial feature that spans multiple files or layers.

```
/skill concept-to-code <topic>
/skill concept-to-code express <topic>   # skip design-brainstorm and macos-ux
/skill concept-to-code resume docs/manifests/YYYY-MM-DD-<slug>.manifest.yml
```

**What it does (Gates 0–7):**

| Gate | What happens | Your action |
|---|---|---|
| 0 | Route: Express / Hybrid / Standard | Click to approve routing |
| 0b | Detect public remote → anonymize flag | Click to confirm |
| 0c | Humanize flag for public repos | Click to confirm |
| 0d | Auto-detect brownfield vs greenfield | Automatic |
| 1 | Run interview-driver → SPEC.md | Answer questions |
| 1b | Run design-brainstorm (Standard/Hybrid) | Review BRAINSTORM.md |
| 1c | Run macos-ux HIG design (Mac apps only) | Review UX-BLUEPRINT.md |
| 2 | Run architect → ADR + plan | Approve plan |
| 2b | Propose test-cmd → TOFU approval | Click to approve test command |
| 3 | Generate project CLAUDE.md | Approve CLAUDE.md |
| 4 | **Session boundary** — open fresh session | Open fresh session, resume |
| 5 | Dispatch coder agents in worktree | Wait for implementation |
| 5.1 | Run deep-refactor Gate 5.1 | Review findings |
| 5.5 | Humanize deliverables (public repos) | Automatic |
| 6 | Run review-triage-fix | Review recap |
| 7 | Run commit skill | Click to commit |

**Resume after session boundary:**
After Gate 4, open a fresh session in the project directory and run:
```
/skill concept-to-code resume docs/manifests/YYYY-MM-DD-<slug>.manifest.yml
```

**When NOT to use it:** for scoped edits touching 1–3 files, use plan mode directly.

---

### commit — always use this for commits

```
/skill commit
/skill commit <context-hint>
```

Every commit goes through this skill. It:
1. Reads the diff and derives a Conventional Commits message
2. Shows you the message for approval (HITL — you must click)
3. On approval: commits, then asks if you want to push + PR

**Never commits before you click Approve.** Even in autopilot chains, the gate fires.

Conventional Commits prefixes: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`.

---

### review-triage-fix — full review+fix cycle

```
/skill review-triage-fix
```

One invocation = one bounded cycle: review → triage findings → route to fix agents → re-review → recap → STOP.

Routing logic:
- BLOCKER (security, crash): `debugger` agent
- MAJOR (logic, perf): `refactorer` or `coder` agent
- MINOR/NIT: `refactorer` agent

Circuit breakers (automatic stop):
- Any test regression after a fix
- Security finding auto-fixed (never allowed)
- Test weakening detected
- Unverified fix after 2 attempts

**Verdict at the end:**
- `SAFE` — commit-ready
- `RE-RUN` — open findings remain, run another cycle
- `STOP` — circuit breaker fired, manual investigation needed
- `UNVERIFIED` — no test-cmd available

Use this instead of "review" when you want fixes applied, not just findings.

---

### deep-refactor — codebase health audit

```
/skill deep-refactor
```

Runs 4 parallel reviewer agents (dead-code, perf, structure, security), then fixes sequentially by severity across dimensions.

Requires `.claude/test-cmd` (TOFU-approved test command). If absent: report-only mode, no auto-fixes.

**Hard rules:**
- Security findings: always report-only, never auto-fixed
- Global circuit breaker: first RED test stops ALL remaining fixes immediately
- `@objc`/`dynamic`/protocol-witness dead code: report-only (static analysis can't prove safe)
- `async`/`actor`/`Sendable` perf changes: report-only

Output: `docs/deep-refactor/YYYY-MM-DD-<slug>.md` + per-dimension commits.

---

### project-init — bootstrap a new project

```
/skill project-init
/skill project-init --update   # refresh existing CLAUDE.md
```

Run this once when starting work on a project that has no CLAUDE.md. It auto-detects the stack
(Python, Swift, Node, etc.) and asks at most 2 questions. Produces:
- `CLAUDE.md` — lean, stack-appropriate, <80 lines
- `.claude/context.md` — initial minimal state (branch, next action), seeded inline

From the first `/commit` onward, `session-state` owns `.claude/context.md` and writes the full
template (branch, last commit, in progress, next, open decisions, notes). The context.md is
auto-injected at every `SessionStart` so you never have to re-explain state.

---

### session-state — cross-session state writer

```
/skill session-state
```

Writes `.claude/context.md`, the single file injected at every `SessionStart`. Called
automatically by `commit` Step 5.5 right after a successful commit (ADR-0197) — and transitively
at the end of `concept-to-code`, which invokes `commit` at its own Step 7. Also invocable by hand
at any point to snapshot in-progress, uncommitted work before ending a session (e.g. before a
reboot). Fields: `Branch`, `Last commit`, `In progress`, `Next` (1-3 items), `Open decisions`
(from an in-progress manifest or a recent ADR), `Notes` (non-obvious gotchas/blockers, omitted
when empty). Max 20 lines.

---

### vibe-status — health check

```
/skill vibe-status
```

Run this after any recovery, after installing new skills, or when something feels broken.
Reports: harness pass/fail per skill, agent files, hooks, ADRs, open manifests.

Flags: `--skip-harness` (fast mode, skip test runs), `--json` (machine-readable).

> Gotcha: the default 12s harness timeout can show concept-to-code as DEGRADED on slow machines.
> Use `VIBE_STATUS_HARNESS_TIMEOUT=20` to extend it.

---

### project-conductor — multi-feature projects

```
/skill project-conductor
```

If you have a PROJECT.md with multiple features to implement, this orchestrates them one by one,
running a full concept-to-code chain per feature. Auto-creates PROJECT.md if absent.

Status markers in PROJECT.md: `[ ]` pending, `[x]` completed, `[~]` skipped.
HITL gate fires before each feature chain starts.

---

### adr-writer — document architecture decisions

```
/skill adr-writer <topic>
```

Creates `docs/architecture/ADR-NNN-<topic>.md` with:
Status / Context / Decision / Alternatives (with rejection reasons) / Consequences / References.

Run this whenever you make a significant architectural choice — storage, auth, data model,
framework, pattern. The concept-to-code chain calls it automatically at Gate 2.

---

### interview-driver — produce a SPEC.md

```
/skill interview-driver
```

Runs an in-depth interview via `AskUserQuestion` and produces `SPEC.md` covering: objectives,
scope, stack, architecture, data model, API, UI flows, edge cases, success criteria, DoD.

Called automatically in concept-to-code Step 1. Run standalone when you need a spec without
going through the full chain.

---

### claude-md-slim — reduce CLAUDE.md token cost

```
/skill claude-md-slim
/skill claude-md-slim --global      # also scan against ~/.claude/CLAUDE.md for duplication
/skill claude-md-slim --global /path/to/project
```

Extracts file-type-specific sections into path-scoped `.claude/rules/<domain>.md` files,
then trims CLAUDE.md. Content-preservation invariant is a hard gate: every line from the
original must appear in the union of new files.

Run on any project CLAUDE.md that has grown beyond ~100 lines.

---

### macos-ux — Mac app design + HIG review

Two modes:

```
/skill macos-ux              # Design mode: interview → UX-BLUEPRINT.md
/skill macos-ux review       # Review mode: audit SwiftUI for HIG violations
```

Design mode asks questions about your app and produces `UX-BLUEPRINT.md` covering window
inventory, navigation model, settings, menu bar, toolbar, keyboard shortcuts, accessibility.

Review mode reads SwiftUI files and reports HIG violations only (not code quality issues).

---

### ui-layout-audit — fix layout bugs

```
/skill ui-layout-audit
/skill ui-layout-audit Sources/Views/MyView.swift
/skill ui-layout-audit "**/*.tsx"
```

Finds and auto-fixes P1/P2 layout bugs (truncation, overflow, hard-coded sizes, scroll,
dynamic-type blindness). P3 issues listed as recommendations.

Supports both SwiftUI (rules S1–S13) and HTML/CSS/TSX/Vue (rules W1–W12).

---

### humanize-en — remove AI tells

```
/skill humanize-en <file-path>
/skill humanize-en              # applies to clipboard or inline text
```

Rewrites English prose to remove vocabulary blacklist items (em-dashes, "leverage", "delve",
"meticulous", etc.), passive constructions, filler openers. Does not change facts, numbers,
names, or code.

Manual invocation only. Nothing calls it automatically (ADR-0040).

Use it for text an outside audience reads: Reddit and HN posts, forum threads, blog posts,
newsletters, announcements, marketing copy, email to third parties. Do not use it for
programming or internal artifacts — code, config, commit messages, PR and issue text, ADRs,
specs, plans, README and other repo docs, changelogs, release notes.

---

### clean-public-repo — prepare for public release

```
/skill clean-public-repo
```

Audits and optionally removes tool markers (Claude trailers, `# [Claude]` comments, emoji
added by tools) from a repo before public release. Two history strategies:
- Fresh-history publish (default) — new clean commit history, original preserved as a backup branch
- Surgical rewrite — git-filter-repo-based line removal (opt-in, HITL-gated)

---

## Agents in depth

### architect

**Dispatched by:** concept-to-code Step 2, or "design this feature", "write an ADR", "what architecture".

Produces:
- ADR with 2+ alternatives and rejection reasons
- Implementation plan (3–8 steps with acceptance criteria)
- Risks, HITL gates
- `TEST-CMD CANDIDATE` line (proposed test command for Gate 2b TOFU)
- `CODER-MODEL CANDIDATE` line (recommended model for coder dispatch)
- `DURABLE NOTES` (facts that should persist to future sessions)

Never writes production code. Always explores alternatives before deciding.
Uses context7 MCP to verify library API before committing to an external dependency.

---

### coder

**Dispatched by:** concept-to-code Step 5, or "implement this plan", "write the code for".

Emits a `PATTERN:` header before every Edit/Write — one of:
- `PATTERN: ADD <file>` — new file
- `PATTERN: REMOVE <file>` — delete file
- `PATTERN: REPLACE <file> | Add: <new> | Remove: <old>` — rename or swap
- `PATTERN: MODIFY <file>` — in-place change

This is enforced by a hook. If a coder response lacks `PATTERN:` before a file operation,
the hook blocks it.

Runs in `isolation: worktree`: a git worktree forked from `HEAD` (`worktree.baseRef: "head"`),
merged back into the feature branch by the orchestrator after each stage. If the project root is
not a direct git repo, the dispatch refuses with an actionable message — there is no fallback
mode (ADR-0068).

---

### reviewer

**Dispatched by:** pre-commit gate on >~50 changed lines, review-triage-fix Step 1, or "review this code".

Reports findings grouped by: BLOCKER / MAJOR / MINOR / NIT.
Each finding includes file:line + description + suggested fix.

Checks: security (OWASP Top 10), correctness, performance, consistency with project style,
test coverage gaps, pattern drift vs project conventions.

Uses LSP (documentSymbol, findReferences) before reading raw files.

---

### debugger

**Dispatched by:** any runtime error, red test, or "debug this", "fix this crash".

Process: forms 2–3 hypotheses → uses LSP diagnostics → traces execution path → identifies root cause.

Stages the fix with `git add` but never commits. Always recommends a regression test.
Emits `DURABLE NOTES` at the end (root cause pattern, prevention guidance).

---

### refactorer

**Dispatched by:** "refactor this", reviewer-flagged structural issues, review-triage-fix MAJOR routing.

Requires green baseline (`pytest` / `xcodebuild test` / whatever is in `.claude/test-cmd`).
Proceeds in ~200-line passes. Uses the `refactor-snapshot` harness to capture behavior before
and verify preservation after.

Never modifies `.claude/test-cmd`. If a test fails post-refactor, reverts that pass and reports.

---

### tester

**Dispatched by:** post-implementation, "write tests for", "improve coverage".

Writes: happy path + edge cases + error paths + boundaries.
Targets ~70% coverage on touched logic. Skips pure UI and trivial code.

If a test reveals a production bug: reports it, does NOT fix the production code.

---

### doc-writer

**Dispatched by:** post-merge, "document this", "update README", "write a CHANGELOG entry".

Writes to the appropriate location: README, `docs/`, ADR, CHANGELOG, or inline docstrings.
Style: specific over abstract, examples over prose, no invented behavior.

---

### researcher

**Dispatched by:** "research X", "how does Y work", "what's the best approach for Z".

Source priority: context7 MCP → WebSearch → WebFetch.
Tags each claim as Fact / Opinion / Hypothesis. Lists open/unverified items explicitly.
Fact-checks across 2+ independent sources before reporting.

---

## Key invariants to remember

### HITL gates

Never skip them. Commit, push, force-push, destructive delete, DB schema changes all require
explicit click. `AskUserQuestion` is how gates are presented. Auto Mode does NOT bypass them.

### Session boundary (concept-to-code)

After Gate 4, the orchestrator stops. You must open a fresh session in the project directory
and resume. This is intentional: planning and coding must not share context.

### test-cmd TOFU

`.claude/test-cmd` is a single-line test command registered with SHA256 + project root.
Agents read it, never modify it. Re-approval required if you change the command.

### PATTERN: pre-flight

Every coder/fix-agent Edit/Write must be preceded by a `PATTERN:` header in plain text.
This is hook-enforced. The pattern must appear in the assistant message, not inside a tool call.

### Circuit breakers

`deep-refactor`: one RED test = stop all remaining dimensions.
`review-triage-fix`: regression or security auto-fix = stop immediately.

### Security findings

Always report-only. Never auto-fixed by any skill or agent. Manual review required.

### Durable Notes

After any architect, debugger, or reviewer run, harvest Durable Notes:
```bash
~/.claude/hooks/agent-notes-harvest.sh harvest architect   # (or debugger / reviewer)
```
They are injected as `PRIOR NOTES` at the next dispatch of that agent.

### Bash 3.2

All hooks and skill scripts must be bash 3.2 compatible (macOS default).
No associative arrays, no `mapfile`, no `${var^^}`.

---

## Common workflows

### Start a new feature

```
/skill concept-to-code <feature topic>
```

Use `express` for pure back-end features (no UX design needed).
Use `standard` for user-facing features where HIG/UX matters.

### Fix a bug

Tell the orchestrator what's wrong. It will dispatch `debugger` automatically.
Or explicitly: "debug the crash in <file>:<line>".

### Commit current work

```
/skill commit
```

Always. Never type `git commit` directly.

### Full review cycle before merging

```
/skill review-triage-fix
```

Wait for `SAFE` verdict before committing.

### Start a project from scratch

```
/skill project-init
```

Then, for the first feature:
```
/skill concept-to-code <first feature>
```

### Check system health

```
/skill vibe-status
```

### Multi-feature roadmap

Create PROJECT.md with phases and feature list, then:
```
/skill project-conductor
```

---

## Skill trigger summary (keyword-triggered, no explicit invocation)

Some skills fire without `/skill` when specific keywords appear:

| Keyword pattern | Skill triggered |
|---|---|
| "design an agent", "orchestration pattern", "MCP server design" | `agent-design` |
| "is there a skill for", "find a skill that" | `find-skills` |
| SwiftUI / iOS code being written or reviewed | `swift-vibe`, `swiftui-pro` |
| "run the chain", "concept to code end-to-end" | `concept-to-code` |
| "review and fix", "triage findings" | `review-triage-fix` |

---

## Files produced by the system

| File | Produced by | Purpose |
|---|---|---|
| `SPEC.md` | interview-driver | Feature requirements |
| `ARCH.md` | architect | Architecture summary |
| `BRAINSTORM.md` | design-brainstorm | Pre-architecture alternatives |
| `UX-BLUEPRINT.md` | macos-ux | HIG design decisions |
| `CLAUDE.md` | claude-md-generator, project-init | Project instructions for Claude |
| `.claude/context.md` | project-init (seed), session-state (full, ADR-0197) | Cross-session state (auto-injected) |
| `.claude/test-cmd` | Gate 2b TOFU approval | Approved test command |
| `.claude/rules/<domain>.md` | claude-md-slim | Path-scoped rules |
| `docs/architecture/ADR-NNN-*.md` | adr-writer, architect | Architecture records |
| `docs/manifests/*.manifest.yml` | concept-to-code | Chain state across sessions |
| `docs/deep-refactor/YYYY-MM-DD-*.md` | deep-refactor | Refactor audit report |
| `memory/agent-notes/<agent>.md` | agent-notes-harvest.sh | Durable notes per agent |
