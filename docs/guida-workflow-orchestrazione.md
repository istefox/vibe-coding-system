# Orchestration workflow — operational guide

**For:** Stefano Ferri (experienced user of the vibe-coding system).
**Purpose:** show step by step how to use the `/concept-to-code` chain (workflow v2) + all auxiliary tools, with the exact prompts to enter at every step.
**Date:** 2026-05-21 (post-deploy version ADR-0001...0008, workflow v2).

---

## Table of contents

1. [When to use what — decision tree](#1-when-to-use-what)
2. [Setting up a clean session](#2-setting-up-a-clean-session)
3. [Workflow A: non-trivial feature with `/concept-to-code` (v2)](#3-workflow-a-non-trivial-feature)
4. [The `design-brainstorm` skill (brainstorm-gate)](#4-the-design-brainstorm-skill)
5. [Workflow B: hotfix or micro-edit (direct coder dispatch)](#5-workflow-b-hotfix-or-micro-edit)
6. [Workflow C: refactor with behavior-preservation](#6-workflow-c-behavior-preserving-refactor)
7. [Workflow D: review/fix of existing code](#7-workflow-d-reviewfix-of-existing-code)
8. [Utility commands](#8-utility-commands)
9. [How to read the pattern classifier + hook](#9-pattern-classifier-and-hook)
10. [Troubleshooting](#10-troubleshooting)
11. [Cheat sheet](#11-cheat-sheet)
12. [Reusable prompt templates](#12-reusable-prompt-templates)
13. [When NOT to use `/concept-to-code`](#13-when-not-to-use-concept-to-code)
14. [Quick glossary](#14-quick-glossary)

---

## 1. When to use what

**Decision tree:**

```
Do you need to do something new?
├── Do you just want to EXPLORE ideas freely (interfaces, methodology, no commitment to build)?
│   └── `/superpowers:brainstorming` (standalone, disconnected from the chain) → §11
├── Is it a NON-TRIVIAL feature (requires design, multi-file, architectural decisions)?
│   └── Use `/concept-to-code <topic>` → Workflow A
│       (the chain offers, if needed, a structured design brainstorm at gate 1b → §4)
├── Is it a HOTFIX or micro-edit (known bug, <3 files, no architectural decision)?
│   └── Direct coder dispatch → Workflow B
├── Is it a REFACTOR (invariant behavior, improved structure)?
│   └── Dispatch refactorer agent → Workflow C
├── Is it a REVIEW of already-written code (want structured feedback + fixes)?
│   └── Invoke `/skill review-triage-fix` → Workflow D
└── Do you want to know the STATUS of the system?
    └── `bash ~/.claude/skills/vibe-status/scripts/aggregate.sh` → §8
```

**"Non-trivial" threshold:** ≥3 files modified or created, OR at least one architectural decision to make, OR requires a new ADR.

**Two brainstormings, two distinct uses:**
- **`/superpowers:brainstorming`** = standalone, explore freely AND writes spec+plan on its own. Use it outside the chain.
- **`design-brainstorm`** (internal to the chain, gate 1b) = explores design alternatives and returns a brief that feeds the architect. Does NOT write spec/plan. See §4.

---

## 2. Setting up a clean session

Open terminal in the project folder (e.g., `cd ~/Developer/Apple/rempay`).

Launch Claude Code:
```bash
claude
```

**Initial checks (optional but recommended):**

1. **Verify system status:**
   ```
   run vibe-status
   ```
   Expected output: `Health: HEALTHY`, all harnesses green.

2. **Confirm the project has `.claude/test-cmd`** (needed for refactor-snapshot and review):
   ```
   check that .claude/test-cmd exists and show me the content
   ```

3. **If the project is new (no `.claude/`):** consider running `/skill project-bootstrap` first for minimal scaffolding.

---

## 3. Workflow A: non-trivial feature

**Default** workflow for any feature of a certain size. The `/concept-to-code` v2 chain orchestrates: **Gate 0** → interview (or skip if brownfield) → Gate 1 → **brainstorm-gate 1b** → architect → Gate 2 → CLAUDE.md → Gate 3 → session boundary → implementation → Gate 5 review.

### Step 0 — Invocation

```
/concept-to-code <topic-full-title>
```

**Examples:**
```
/concept-to-code Rate limiter middleware for FastAPI
/concept-to-code Three-box document wizard for the new plan
```

The skill creates a YAML manifest in `docs/manifests/YYYY-MM-DD-<slug>.manifest.yml` (schema 1.1).

### Gate 0 — Chain-vs-lightweight triage (NEW in v2)

Before starting, the chain checks whether the project meets criteria that **advise against** the full chain:
- `SPEC.md` + ADR already exist (brownfield project)
- declared micro-scope (<3 files, no architectural decision)

**If no criterion is active:** Gate 0 is silent, proceed directly.

**If at least one criterion is active, what you see:**
```
============================================================
concept-to-code · Gate 0 · TRIAGE
============================================================
Criteria detected:
  [X] SPEC.md + ADR already exist (brownfield)
  [ ] micro-scope <3 files
============================================================
  [c] full chain (with brownfield mode)
  [l] lightweight workflow (direct plan, no chain)
  [a] abort
> _
```

**What to choose:**
- **`c`** — full chain. If brownfield, automatically activates "brownfield mode" (see below).
- **`l`** — lightweight workflow: the orchestrator makes a direct plan in plan mode, without formal interview/architect. Good for micro-features in mature projects.
- **`a`** — abort.

> This gate exists because without it, on projects with an existing SPEC, the orchestrator would decide *on its own* to skip the chain. Now **you decide**.

### Step 1 — Interview (GREENFIELD) or skip (BROWNFIELD)

**Greenfield (project without SPEC):** `interview-driver` asks you questions via `AskUserQuestion` (multiple choice). Covers objectives, scope, stack, edge cases, success criteria. At the end it writes `SPEC.md`.

**Brownfield (SPEC already exists — e.g., rempay):** Step 1 is **SKIPPED automatically**. The manifest points `artifacts.spec` at the existing SPEC (does NOT regenerate it, does NOT overwrite it) and marks Gate 1 as "pre-existing spec approved". No redundant interview.

### Gate 1 — Spec review (greenfield only)

In greenfield, after the interview:
```
============================================================
concept-to-code · Step 1 · INTERVIEW COMPLETE
============================================================
Artifact: /path/to/SPEC.md
Summary:  <5 lines: objective, scope, stack, edge cases, criteria>
============================================================
HITL Gate 1: spec_review
  [y] approve and proceed    [e] revise (notes)    [a] abort
> _
```

- **`y`** approve
- **`e`** + notes to revise. E.g.: `e: narrow scope to the GET /api/products endpoint only`
- **`a`** abort

(In brownfield, this gate is already marked approved and skipped to gate 1b.)

### Gate 1b — Design brainstorm (NEW in v2, optional)

Between the spec and the architecture, the chain **offers** a design brainstorming session:
```
============================================================
concept-to-code · Gate 1b · DESIGN BRAINSTORM
============================================================
Do you want to explore approach alternatives before fixing the architecture?
  [y] yes → design-brainstorm session (8 ideation techniques)
  [n] no → go directly to architect (classic behavior)
> _
```

**When to answer `y`:** when the feature has multiple possible approaches, when you want fresh applied ideas, when the architectural decision is important and not obvious. It is **the moment that makes the difference** on the architecture.

**When to answer `n`:** when the approach is obvious or already decided (e.g., a simple UI change).

**If `y`:** the `design-brainstorm` skill starts (see §4). Produces a `BRAINSTORM.md` with 2-4 alternatives + trade-offs, which is passed to the architect as context. The brainstorm alternatives become the "alternatives considered" in the ADR.

**If `n`:** direct transition to Step 2, architect operates as in v1.

### Step 2 — Architecture

Dispatch of the **`architect`** sub-agent (with `BRAINSTORM.md` attached if you did gate 1b). Produces:
- `docs/architecture/<NNNN>-<topic>.md` (ADR — **note:** the numbering convention follows the target repo, e.g., rempay uses `0002-title.md`, vibe-coding-system uses `ADR-0002`)
- `docs/superpowers/plans/YYYY-MM-DD-<topic>.md` (TDD plan with 6-10 tasks)
- (optional) `ARCH.md`

**What to type:** nothing. Wait.

### Gate 2 — Architecture review

```
============================================================
concept-to-code · Step 2 · ARCHITECTURE COMPLETE
============================================================
Artifact (ADR):  <path>
Artifact (Plan): <path>
Key decisions:   <top 3>
Risk flags:      <top 3>
============================================================
HITL Gate 2: architecture_review
  [y] approve    [e] revise (notes)    [a] abort
> _
```

**What to check:** does every architectural question have an answer + a rejected alternative? Does the plan have tasks with file paths, red/green, verify command? Are the risk flags acceptable?

- **`y`** approve
- **`e`** + binding notes. E.g.: `e: the ADR chose Redis but it must be standalone, no extra dependency. Redo with in-process LRU.`

### Step 3 — Project memory (CLAUDE.md)

Generates `CLAUDE.md.proposed`.

**Greenfield (no CLAUDE.md):** generates from scratch from SPEC + ADR.
**Brownfield (hand-crafted CLAUDE.md):** **ADDITIVE** mode — starts from the existing CLAUDE.md and only adds the reference to the new ADR + any gotchas. Never degrades curated content.

### Gate 3 — Project memory review

```
============================================================
concept-to-code · Step 3 · PROJECT MEMORY COMPLETE
============================================================
Proposed: <project-root>/CLAUDE.md.proposed
<full content (greenfield) or diff (brownfield)>
============================================================
HITL Gate 3: project_memory_review
  [y] apply    [e] revise    [s] skip    [a] abort
> _
```

- **`y`** apply (existing backed up to `.bak-<date>`)
- **`s`** skip (keep current CLAUDE.md unchanged — useful if it is already perfect)
- **`e`** + notes

### Step 4 — Session boundary (informational)

```
============================================================
concept-to-code · SESSION BOUNDARY
============================================================
Steps 1-3 complete. Now:
1. Close this session.
2. Open a NEW session in: <project-root>
3. Run: /concept-to-code resume <manifest-path>

Reason: a fresh session avoids polluting the context with
design turns before implementation.
============================================================
```

**What to do:**
1. **Copy the manifest path** shown
2. Exit (`Ctrl+D` or `/exit`)
3. New session (`claude`) in the same folder
4. `/concept-to-code resume <manifest-path>`

### Step 5 — Implementation

Dispatch of the **`coder`** with the plan. Reads plan + ADR + SPEC + CLAUDE.md (+ BRAINSTORM.md if it exists). Runs each TDD task (red → green → verify). **Emits `PATTERN:` before every Edit** (now *truly enforced* by hook v1.1 — see §9). Implements on a dedicated branch. Never commits.

**What to type:** nothing. Wait for the report.

### Gate 5 — Review cycle (optional)

```
============================================================
concept-to-code · Step 5 · IMPLEMENTATION COMPLETE
============================================================
Tasks completed:  N    Files modified: <list>
Test results:     green | red    Harness deltas: <...>
============================================================
HITL Gate 5: review_cycle_decision
  [r] run review-triage-fix    [s] skip    [a] abort
> _
```

- **`r`** recommended for features >50 LOC: runs reviewer + triage + fix of MAJOR items
- **`s`** skip → manifest `completed`

### Finale

Manifest → `completed`. The coder does NOT commit: you decide commit/push (e.g., `/skill commit`). For UI/frontend (e.g., SwiftUI), **verify manually** before push — agents do not test the GUI.

---

## 4. The `design-brainstorm` skill

Activated at **gate 1b** (by answering `y`) or standalone (`/skill design-brainstorm <topic>`). This skill explores **how** to build something and **what new things** are possible, before fixing the architecture.

**Do not confuse it with:**
- `interview-driver` — that extracts *requirements* (what), this explores *approaches* (how)
- `/superpowers:brainstorming` — that writes spec+plan on its own; `design-brainstorm` only returns a brief

### The 8 ideation techniques

The skill does not use all of them: it **selects 3-4** based on the problem, one technique → 1-2 questions → synthesis → next.

| # | Technique | What it is for |
|---|---------|--------------|
| 1 ★ | **First-principles** | decomposes the problem to its irreducible elements, rebuilds without inherited assumptions (anti-anchoring) |
| 2 ★ | **Cross-domain analogies** | "how would a video game / a bank / a biological system / logistics solve this flow?" |
| 3 ★ | **Inversion (pre-mortem)** | "how would we guarantee TOTAL FAILURE?" → invert to find hidden risks and requirements |
| 4 | **Forced constraints** | "what if I had 1/10 of the time? no database? offline?" → finds the lean version |
| 5 | **Assumption-busting** | makes implicit assumptions explicit and challenges them one by one |
| 6 | **Genuinely different alternatives** | 2-4 approaches that differ in data/concurrency/boundaries/deployment (not variants) |
| 7 | **Adjacent ideas** | nearby features that emerge — in-scope / future / explicitly excluded |
| 8 | **Prior-art** | "what do competing products do? where is there room to do better/differently?" (delegates to `researcher` if research is needed) |

★ = cornerstone, always considered first.

### Output: `BRAINSTORM.md`

Writes `<project-root>/BRAINSTORM.md` with: problem restated, challenged assumptions, 2-4 alternatives with trade-offs, pre-mortem risks, adjacent ideas, **preliminary** recommendation (not binding). Does NOT write SPEC/plan. The architect reads it and reuses the alternatives in the ADR.

### What you do during the brainstorm

Answer the `AskUserQuestion` questions (multiple choice + "Other/write it"). The skill synthesizes after each answer. If you don't know how to answer a technique, choose "skip". Converge in ~6-7 exchanges.

---

## 5. Workflow B: hotfix or micro-edit

**When:** known bug, small fix, no architectural decision. (The `[l]` outcome of Gate 0 also ends up here.)

**What to type:**
```
fix the bug in validate.py line 42: regex too loose, must require quoted path.
context: [...].
proposed fix: regex `^"/[^"]+"$`.
add a test that demonstrates the bug pre-fix and the fix post-fix.
```

**What the orchestrator does:** direct dispatch to `coder` (no architect, no chain). The coder writes red test, fixes, verifies green, emits `PATTERN:`. No HITL gate (auto mode).

**Useful pattern:** embedded TDD mini-plan in the prompt:
```
TDD task in 3 steps:
1. RED: add test in tests/test_validate.py that demonstrates the bug.
2. GREEN: fix the regex.
3. VERIFY: pytest tests/test_validate.py must be green.
```

---

## 6. Workflow C: behavior-preserving refactor

**When:** improve structure/readability without changing behavior.

**What to type:**
```
refactor the 3 autouse fixtures in tests/conftest.py + test_cli.py + test_pricing.py
into one in conftest.py. identical observable behavior.
use the refactorer agent with snapshot harness.
```

**What the refactorer does (8-step Process, ADR-0002):**
1. Baseline check (`.claude/test-cmd` green pre-refactor)
2-3. PRE-snapshot × N + determinism check (identical SHA256)
4. Apply refactor
5. POST-snapshot
6. Diff PRE vs POST → PASS / FAIL / UNVERIFIED
7. If FAIL → STOP + HITL ("behavior changed, is it intentional?")
8. If PASS → report

**Env vars:**
- `RFS_RUNS=5` more confidence in determinism (flaky suite) · `RFS_RUNS=1` skip determinism (deterministic test)
- `RFS_FULL=1` full suite (default = filter on touched files)
- `RFS_FILTER='-k test_pricing'` narrowing · `RFS_TIMEOUT=300` per-run timeout (default 120s)

---

## 7. Workflow D: review/fix of existing code

**When:** code already written, want structured review + fix of MAJOR items.

**What to type:**
```
run review-triage-fix on files modified in the last 2 hours.
focus: src/pricing/*.py
```

**What it does:** reviewer → findings by severity (BLOCKER/MAJOR/MINOR/NIT) → triage → fix of MAJOR/BLOCKER → re-review → recap. **Variant v1.2:** a `PATTERN: REPLACE` without `Remove:` is escalated to MAJOR (ADR-0001).

> Note: in the real test the review correctly left 5 findings as REPORT-ONLY (design-level / out-of-scope / Swift6 effort deferred) without inventing fixes. Mature triage does *not* force-fix everything.

---

## 8. Utility commands

### `vibe-status` — system status
```
run vibe-status
```
Markdown report with harness/ADR/manifest/skill/hook/memory. <3s. Flags: `--json`, `--skip-harness`, `--plain`.

### `concept-to-code resume / abort`
```
/concept-to-code resume <manifest-path>     # resume after session boundary
/concept-to-code abort <manifest-path>      # mark aborted, preserve artifacts
```

### Hook pattern-enforce (rare)
```bash
tail -50 ~/.claude/state/pattern-enforce/audit.log   # audit: allow/block/bypass per Edit
touch ~/.claude/state/pattern-enforce/disabled       # temporarily disable
rm ~/.claude/state/pattern-enforce/disabled          # re-enable
PATTERN_ENFORCE=off claude                            # disable for one session
```

---

## 9. Pattern classifier and hook

The `coder` always emits a `PATTERN:` header before every Edit/Write, and the **`pre-flight-pattern-enforce` hook v1.1 truly enforces it** (blocks the Edit if missing).

| Pattern | What it is | What to expect |
|---------|--------|-----------------|
| `ADD` | new code | only added lines |
| `REMOVE` | deletion | payload with "Callers checked: ..." |
| `REPLACE` | pattern substitution | MANDATORY `Add: ... \| Remove: ...` pair |
| `MODIFY` | in-place edit without structural change | rename, typo, internal refactor |

**How the hook works (v1.1):** reads `agent_type` from the PreToolUse payload. If `coder` → checks that a `PATTERN:` exists within the last 6 messages of the sub-agent transcript → `allow`; otherwise `block`. Other agents (architect, etc.) and the orchestrator → `bypass-noncoder`.

**Live verification (2026-05-21):** on a real coder, 26 Edit `allow` / 0 wrongful `block`. Works.

**When to be suspicious:** `PATTERN: ADD` with non-trivial deletions in the diff → mis-classified (reviewer catches it as `pattern-drift` MINOR). `PATTERN: REPLACE` with only `Add:` → the hook should have blocked it, check the audit log.

---

## 10. Troubleshooting

### "Skill X cannot be invoked from a skill"
**Cause:** the skill has `disable-model-invocation: true`, incompatible with chain invocation.
**Fix:** remove the flag if the skill is part of a chain. Ref: memory `feedback_disable-model-invocation-strong.md`.

### Hook blocks a coder Edit ("PATTERN missing in window=6")
**Cause:** the coder did not emit the `PATTERN:` within the last 6 messages before the Edit.
**Fix:** ask the coder to re-emit the correct PATTERN: and retry. Do **not** disable the hook. Diagnose: `tail ~/.claude/state/pattern-enforce/audit.log`.

### The chain skips interview / asks nothing on a project with SPEC
**This is not a bug:** it is **brownfield mode** (v2). If SPEC exists, the interview is intentionally skipped and `artifacts.spec` points to the existing one. If you still want to redo the spec, handle it at Gate 0 with `[c]` and then explicitly request it.

### Refactor in UNVERIFIED
**Cause:** non-deterministic tests (timestamps, random IDs, dict ordering).
**Fix 1:** fix the non-determinism. **Fix 2 (workaround):** create `.claude/refactor-snapshot-override`:
```
REASON: timestamps in test output, intentional
SCOPE: stdout
EXPIRES: 2026-07-20
```

### Manifest invalid / chain blocked
- Manifest already exists for same topic/day → `/concept-to-code abort <path>` or rename topic.
- YAML edited by hand and validate fails → restore or abort + new manifest. (Schema 1.1 is backward-compatible with 1.0.)

### vibe-status shows "Harness X/N" with low N
**Cause:** glob does not discover a harness in a non-standard location.
**Fix:** already covers `~/.claude/skills/*/tests/run-tests.sh` + `~/.claude/hooks/tests/*.sh`. Add other paths to the glob in `aggregate.sh` if needed.

### Label "Ready to code?" even when the chain only does design
**This is not our bug:** it is the fixed template of the ExitPlanMode harness. When the plan declares "design artifacts only", exiting plan mode does NOT write code — trust the content of the plan, not the label.

---

## 11. Cheat sheet

| What you want to do | Command |
|----------------|---------|
| Explore ideas freely (standalone) | `/superpowers:brainstorming` |
| Design brainstorm (standalone) | `/skill design-brainstorm <topic>` |
| New non-trivial feature | `/concept-to-code <topic>` |
| Resume after session boundary | `/concept-to-code resume <manifest-path>` |
| Abort chain | `/concept-to-code abort <manifest-path>` |
| Small hotfix | Direct prompt to coder with TDD mini-plan |
| Safe refactor | Prompt to refactorer (automatic snapshot) |
| Review + fix code | `/skill review-triage-fix` |
| System status | `bash ~/.claude/skills/vibe-status/scripts/aggregate.sh` |
| Hook audit | `tail -50 ~/.claude/state/pattern-enforce/audit.log` |
| Disable/re-enable hook | `touch`/`rm ~/.claude/state/pattern-enforce/disabled` |
| Refactor with N runs determinism | `RFS_RUNS=N` env var |
| Commit (if git) | `/skill commit` |

---

## 12. Reusable prompt templates

### Non-trivial feature
```
/concept-to-code <Full Feature Title>
```

### Gate choices
```
c        # Gate 0: full chain
l        # Gate 0: lightweight workflow
y        # Gate 1/2/3: approve  ·  Gate 1b: yes to brainstorm  ·  Gate 5: (r for review)
n        # Gate 1b: no to brainstorm, go directly to architect
s        # Gate 3: skip CLAUDE.md  ·  Gate 5: skip review
e: <concrete notes on what to change>     # rejection with feedback
a        # abort chain
```

### Hotfix with TDD mini-plan
```
fix bug in <file:line>: <description>.
context: <what it does now, what it should do>.
TDD plan: T1 RED test that demonstrates the bug · T2 GREEN fix · T3 VERIFY .claude/test-cmd.
```

### Refactor with snapshot
```
refactor <area>: <objective, no behavior change>.
use refactorer agent with snapshot harness. env: RFS_RUNS=<N> RFS_FILTER=<filter>.
```

### On-demand review
```
run review-triage-fix on files modified <since when> in path <pattern>. focus: MAJOR.
```

---

## 13. When NOT to use `/concept-to-code`

- **Hotfix under 30 minutes:** overhead not justified → direct coder (or Gate 0 `[l]`).
- **Throwaway experiment:** you don't need to persist ADR + plan → coder with exploratory prompt.
- **Tweak to an existing feature** (e.g., changing a default): it is MODIFY, not a new feature → direct coder.
- **Brownfield project with micro-scope:** Gate 0 will flag it and you can choose `[l]`.

---

## 14. Quick glossary

- **Orchestrator:** the main `claude` session that dispatches sub-agents.
- **Sub-agent:** isolated process (`coder`, `architect`, `reviewer`, etc.) that receives a prompt and returns a report. Does NOT spawn other sub-agents.
- **Skill:** markdown module in `~/.claude/skills/<name>/SKILL.md` that instructs the orchestrator (or a sub-agent).
- **Hook:** bash script in `~/.claude/hooks/` that fires on events (PreToolUse, etc.). `pre-flight-pattern-enforce` v1.1 enforces the coder's PATTERN:.
- **Manifest:** YAML that tracks the chain state. In `<project>/docs/manifests/`. Schema 1.1 (backward-compatible with 1.0).
- **Gate 0:** initial chain-vs-lightweight triage (v2).
- **Brownfield mode:** mode for projects with existing SPEC/CLAUDE.md — skip interview, additive CLAUDE.md (v2).
- **Brainstorm-gate (1b):** optional gate between spec and architecture that invokes `design-brainstorm` (v2).
- **HITL gate:** point that requires explicit user approval.
- **PATTERN: header:** mandatory coder declaration before every Edit (ADR-0001), enforced by the hook (ADR-0004).
- **ADR:** Architecture Decision Record, in `docs/architecture/`.
- **BRAINSTORM.md:** output of `design-brainstorm` — alternatives + trade-offs, feeds the architect (not SPEC nor plan).
- **Harness:** automatic test scripts (`tests/run-tests.sh`). **Anchor:** grep-pattern that the harness verifies; "anchor preservation" = don't break them.

---

*End of guide. For the "kid-friendly" version, see `guida-per-ragazzi-12-anni.md`. For the complete technical spec, see `vibe-coding-system.md`. Workflow v2 detail: `ADR-0008` + `2026-05-21-concept-to-code-workflow-v2-design.md`.*
