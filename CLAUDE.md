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
keyword trigger (`"workflow"` in the dispatch prompt) causes Claude Code to generate a JS
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
