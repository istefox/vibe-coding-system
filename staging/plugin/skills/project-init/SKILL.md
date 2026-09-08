---
name: project-init
description: >
  Generates a lean project CLAUDE.md from filesystem auto-detection — no SPEC.md or ADR needed.
  Use at the start of any session on a project that lacks a CLAUDE.md, or to refresh an existing one
  with --update. For projects going through the concept-to-code chain, use claude-md-generator
  instead (it has richer context from SPEC+ADR). Triggers on: "init project", "create CLAUDE.md",
  "setup project context", "project-init", "/skill project-init".
---

# project-init — Project CLAUDE.md Generator

Bootstraps a project with a lean, stack-appropriate `CLAUDE.md` and an initial `.claude/context.md`.
Reads the filesystem; asks at most 2 questions; shows a HITL gate before writing anything.

## Invocation

```
/skill project-init [--update]
```

- No flag: aborts if `CLAUDE.md` already exists (shows content, asks if the user wants to update).
- `--update`: skip the existence guard, go straight to regeneration with diff shown.

`project_root` = `$PWD`.

---

## Pipeline (5 steps)

### Step 0 — Guards

1. **SPEC.md guard:** if `<project_root>/SPEC.md` exists, emit:
   `"SPEC.md found — for richer output run through concept-to-code (claude-md-generator has ADR+spec context). Continue anyway? [y/n]"`
   Wait for inline user reply. If `n`: stop.

2. **Existence guard (skip if `--update`):**
   If `<project_root>/CLAUDE.md` exists, show its current content and present:
   ```
   AskUserQuestion:
     question: "CLAUDE.md already exists. What do you want to do?"
     header: "project-init"
     options:
       - label: "Update — regenerate with --update mode"
       - label: "Abort — keep the existing file"
   ```
   On "Update": continue as `--update`. On "Abort": stop.

### Step 1 — Detect stack

```bash
STACK=$(bash "$HOME/.claude/skills/project-init/scripts/detect-stack.sh" "<project_root>")
```

Also read supplementary signals for the template:
- `README.md` first paragraph → candidate project description
- `package.json` `.description` field → candidate description
- `Package.swift` / `.xcodeproj` scheme name → Swift target
- `.venv/` presence → Python venv confirmed
- `uv.lock` or `uv` in `pyproject.toml` → uv project (use `uv run` prefix)

**Architecture file scan (read in priority order, stop at first found):**
Look for these files in `<project_root>`:
`ARCHITECTURE.md`, `ARCH.md`, `OVERVIEW.md`, `BRIEF.md`, `BRIEFING.md`,
`DESIGN.md`, `PROJECT.md`, `NOTES.md`

If none found by name, scan all `.md` files in the root (excluding `README.md`,
`CLAUDE.md`, `CHANGELOG.md`, `LICENSE.md`) — if exactly one remains, treat it as
the architecture file.

When an architecture file is found:
- Read its full content into `$ARCH_CONTEXT`
- Extract: description (first non-heading paragraph), architecture pattern, key
  components, any mentioned gotchas or constraints
- Emit: `"Architecture context loaded from <filename> — will inform template"`
- This content is the primary source for the Architecture and Gotchas sections
  of the generated CLAUDE.md; it also pre-fills the description

When no architecture file is found and the repo is sparse (< 3 non-hidden files):
- Emit: `"Repo is sparse — consider dropping an ARCHITECTURE.md or OVERVIEW.md
  first for a richer CLAUDE.md"`

Emit one line: `"Stack detected: <STACK>"`.

**Canonical-mechanism detection (ADR-0063, optional):**

```bash
for cat in http logger config; do
  bash "$HOME/.claude/skills/project-init/scripts/detect-canonical-mechanism.sh" "<project_root>" "$cat"
done
```

Each line of output is `name<TAB>count` for a category with a clear dominant mechanism; a category
with no output has no dominant mechanism (a tie, or too thin a sample — SPEC edge case) and is
skipped. Detection is sound here specifically because the property being detected (which mechanism
is used most) and the property being declared ("this is the canonical mechanism") are the same
property — that does NOT generalise. Contrast ADR-0055 §A4, which rejected path-based
auto-derivation of `risk` for the opposite reason: a file's location does not determine its risk.

If at least one category produced a result, build a draft `.claude/rules/canonical-mechanisms.md`
(flat list, `name → import path or symbol`, `paths:` frontmatter scoped to the detected stack) and
carry it into Step 4's HITL gate as a proposal. **Never write it without approval** — the same
propose-not-write-silently contract CLAUDE.md itself uses in this skill (ADR-0063 §D2, ADR-0053
§D6, ADR-0055 §D5). If no category produced a result, skip the draft entirely and say nothing
about it in the gate.

### Step 2 — Ask (max 2 questions)

**If `$ARCH_CONTEXT` is populated:** skip Q2 entirely (description comes from the
architecture file). Q1 is still required.

Use a single `AskUserQuestion` with 1-2 questions.

**Q1 — Project type (always ask):**
```
question: "What kind of project is this?"
header: "Project type"
options:
  - label: "Work / professional"
    description: "Team conventions, deployment context, structured"
  - label: "Personal / hobby"
    description: "Minimal, just the essentials"
  - label: "OSS / public"
    description: "Contribution guidelines hint, license section"
```

**Q2 — Description (skip if `$ARCH_CONTEXT` found or description found in README/package.json):**
```
question: "One-line description of what this project does"
header: "Description"
options:
  - label: "<infer from files if possible>"
  - label: "Write a custom description"
```
If a candidate description was found in Step 1, pre-fill option 1 and mark it Recommended.

Do NOT ask about the test runner — derive it from stack (see templates below).

### Step 3 — Build content

Choose template by `$STACK`. Fill in all `<placeholders>` from Step 1 + Step 2 answers.

**When `$ARCH_CONTEXT` is populated**, use it aggressively:
- Replace the `<description>` placeholder with the extracted description from the arch file.
- Replace the `## Architecture` section body with the key components and patterns extracted
  from the arch file — summarized to 3-5 bullet points, not a verbatim dump.
- Replace the `## Gotchas` section with any constraints, limitations, or non-obvious design
  decisions mentioned in the arch file.
- If the arch file mentions specific commands (run, test, build), prefer those over the
  template defaults.
- Do not paste the arch file content verbatim — synthesize it. The CLAUDE.md must stay < 80 lines.

---

#### Template: `swift`

```markdown
# CLAUDE.md

## What is this project
<description>

## Stack
Swift 6, <SwiftUI|AppKit>, <macOS|iOS> <target>.
Build via Xcode or `xcodebuild` from terminal.

## Commands
- Build: `xcodebuild -scheme <scheme> -destination 'platform=macOS,arch=arm64'`
- Test:  `xcodebuild test -scheme <scheme> -destination 'platform=macOS,arch=arm64'`

## Architecture
<brief note on folder structure, e.g. "MVVM with Observable+Bindable (iOS 17+)">

## Gotchas
- Swift 6 strict concurrency: actors, Sendable, and deinit isolation must be explicit.
- NSPanel / NSHostingView bridging requires AppKit lifecycle awareness.
```

Work variant adds:
```markdown
## Deployment
<App Store / TestFlight / direct distribution — fill in>
```

---

#### Template: `python`

```markdown
# CLAUDE.md

## What is this project
<description>

## Stack
Python 3.x. <uv project: `uv run` prefix | venv: `source .venv/bin/activate`>.
Dependencies: <`uv sync` | `pip install -r requirements.txt`>.

## Commands
- Test: `<source .venv/bin/activate && >python3 -m pytest`
- Lint: `<source .venv/bin/activate && >python3 -m ruff check .`
- Type: `<source .venv/bin/activate && >python3 -m mypy --strict .`
<if web framework>
- Run:  `<uvicorn main:app --reload | flask run | etc.>`
</if>

## Architecture
<brief note, e.g. "Single-file CLI" or "FastAPI app, routes in app/routers/">

## Gotchas
- Always use `python3`, never `python`.
- Test command requires venv active — never use system Python.
```

---

#### Template: `typescript`

```markdown
# CLAUDE.md

## What is this project
<description>

## Stack
TypeScript <version>. Node <version>. Package manager: npm.

## Commands
- Install: `npm install`
- Dev:     `npm run dev`
- Build:   `npm run build`
- Test:    `npm test`
- Lint:    `npm run lint`

## Architecture
<brief note, e.g. "Next.js App Router, components in app/, shared in lib/">

## Gotchas
<fill in or remove>
```

---

#### Template: `javascript`

Same as `typescript` but without the TypeScript stack line and type-check command.

---

#### Template: `go`

```markdown
# CLAUDE.md

## What is this project
<description>

## Stack
Go <version from go.mod>.

## Commands
- Build: `go build ./...`
- Test:  `go test ./...`
- Lint:  `golangci-lint run` (if `.golangci.yml` present)

## Architecture
<brief note>
```

---

#### Template: `rust`

```markdown
# CLAUDE.md

## What is this project
<description>

## Stack
Rust <edition from Cargo.toml>. Toolchain: stable.

## Commands
- Build: `cargo build`
- Test:  `cargo test`
- Lint:  `cargo clippy`
- Format: `cargo fmt`

## Architecture
<brief note>
```

---

#### Template: `generic`

```markdown
# CLAUDE.md

## What is this project
<description>

## Commands
- <fill in build command>
- <fill in test command>

## Architecture
<fill in>

## Gotchas
<fill in or remove>
```

---

**For all templates, OSS type adds:**
```markdown
## Contributing
See CONTRIBUTING.md. PRs welcome — open an issue first for non-trivial changes.
```

**For all templates, work type adds:**
```markdown
## Team conventions
<fill in: branching model, PR review requirements, deploy process>
```

**Never include** in any template: language/style conventions, git workflow, HITL rules,
security guardrails, Python/Swift/web style — those live in `~/.claude/CLAUDE.md` and
path-scoped rules. The generated file must be **< 80 lines**.

### Step 4 — HITL gate

Show the proposed content, then:

```
AskUserQuestion:
  question: "project-init — review proposed files\n\n
    === CLAUDE.md ===\n<content>\n\n
    === .claude/context.md ===\n<content>\n\n
    <if a canonical-mechanisms draft exists>
    === .claude/rules/canonical-mechanisms.md (proposed) ===\n<content>\n\n
    </if>
    Approve to write."
  header: "project-init · Approval"
  options:
    - label: "Approve — write files (Recommended)"
    - label: "Edit CLAUDE.md — select Other and paste corrected content"
    - label: "Abort"
```

If a canonical-mechanisms draft exists, the gate shows it as a fourth proposed file exactly like
CLAUDE.md and context.md — approval covers all files shown, there is no separate gate for it.

On "Edit": accept the corrected content from the Other field, re-show the gate once.
On "Abort": exit, write nothing — including the canonical-mechanisms draft.

### Step 5 — Write

1. If `--update` and `CLAUDE.md` exists: back it up first:
   ```bash
   cp "<project_root>/CLAUDE.md" "<project_root>/CLAUDE.md.bak-$(date +%Y-%m-%d)"
   ```
   Abort if backup already exists today (same guard as `claude-md-slim`).

2. Create `.claude/` if absent: `mkdir -p "<project_root>/.claude"`

3. Write `<project_root>/CLAUDE.md` with the approved content.

4. Write `<project_root>/.claude/context.md`:
   ```markdown
   ## Status (<YYYY-MM-DD>) — initial
   **Branch:** <current branch or "main">
   **In progress:** project init — CLAUDE.md generated
   **Next:** review generated CLAUDE.md, fill in <placeholders>, run /commit
   **Open decisions:** none
   ```
   This seed is intentionally minimal and written inline, not via the `session-state` skill: there
   is no session history yet to derive a `Notes` field from, and a structurally empty field is
   worse than its absence. From the first `/commit` onward, `session-state` (ADR-0197) owns the
   full template — see its `SKILL.md` for the authoritative field set.

5. If a canonical-mechanisms draft was approved at Step 4: create `.claude/rules/` if absent
   (`mkdir -p "<project_root>/.claude/rules"`) and write
   `<project_root>/.claude/rules/canonical-mechanisms.md` with the approved content. Never write
   this file when no draft was proposed, and never write it without the Step 4 approval that
   covered it (ADR-0063 §D2).

6. Emit apply report:
   ```
   Written:
     CLAUDE.md          (<N> lines, stack: <STACK>, type: <TYPE>)
     .claude/context.md (initial state)
     <if canonical-mechanisms draft approved>
     .claude/rules/canonical-mechanisms.md (<N> mechanisms declared)
     </if>
   <if --update>
     Backup: CLAUDE.md.bak-<date>
   
   Next: fill in any <placeholder> sections, then run /skill claude-md-slim to extract
   path-scoped rules if the file grows beyond 80 lines.
   ```

---

## Invariant guardrails

- **Never write without HITL approval** (Step 4 gate).
- **Never overwrite an existing CLAUDE.md without a backup** (--update path).
- **Never include global rules** (git workflow, HITL, security, language style) — they inherit
  from `~/.claude/CLAUDE.md`. Duplicating them bloats the file and creates drift.
- **Never abort the write if `.claude/context.md` fails** — CLAUDE.md is the critical output;
  context.md is a bonus. Log the failure, continue.
- **< 80 lines** — if the generated content exceeds this, trim placeholders and remove optional
  sections before showing the HITL gate.
