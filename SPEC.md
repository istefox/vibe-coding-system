# SPEC — claude-md-slim

**Date:** 2026-06-06
**Topic slug:** claude-md-slim
**Manifest:** docs/manifests/2026-06-06-claude-md-slim.manifest.yml

---

## Objectives

Build a Claude Code skill (`/skill claude-md-slim`) that audits a project's `CLAUDE.md`,
identifies sections extractable to path-scoped `.claude/rules/` files, generates a unified
diff, and applies the refactor after HITL approval. Goal: reduce CLAUDE.md token footprint
by conditionally loading rules only when relevant files are in context.

The skill also handles the optional `--global` flag to detect cross-file duplication between
the project `CLAUDE.md` and the global `~/.claude/CLAUDE.md`.

---

## Scope

**In scope:**
- Parsing project `CLAUDE.md` into H2-delimited sections
- Detecting extractable sections via file-pattern keyword heuristics
- Mapping sections to `.claude/rules/<domain>.md` target files with `paths:` glob frontmatter
- Merging into existing rules files (deduplicating) or creating new ones
- Generating a unified diff (rules file changes + trimmed CLAUDE.md)
- HITL gate before any file writes
- Backing up CLAUDE.md before overwriting
- `--global` mode: detecting cross-file duplicates between project and global CLAUDE.md

**Out of scope:**
- Modifying `~/.claude/CLAUDE.md` itself (read-only even in --global mode)
- Sub-agent dispatch (single-session skill, LLM + bash)
- Automatic re-run or iteration without user request
- Detecting semantic duplication across sections (keyword-only heuristic, no LLM judging)

---

## Invocation

```
/skill claude-md-slim [--global] [<project-root>]
```

- `--global`: enable cross-file duplication check against `~/.claude/CLAUDE.md`
- `<project-root>`: defaults to `$PWD`

---

## Architecture

Single-session skill. No sub-agent dispatch. The orchestrator (LLM) drives all steps.
Bash helpers (bash 3.2 compatible) handle file I/O and validation.

### Pipeline

```
Step 0 — Locate & validate
  → resolve project_root, CLAUDE.md path
  → verify .claude/ directory exists (create .claude/rules/ if needed)
  → read current CLAUDE.md line count (N_before)
  → [--global] read ~/.claude/CLAUDE.md

Step 1 — Parse sections
  → split CLAUDE.md on H2 headings (`## `)
  → for each section: extract heading + body text

Step 2 — Classify sections
  → apply keyword heuristic (file-pattern keywords → extractable)
  → for each extractable section: map to rules file path + paths glob
  → for remaining sections: keep in CLAUDE.md (non-extractable)

Step 3 — [--global] Duplication scan
  → compare each project-CLAUDE.md section body against global CLAUDE.md
  → if substantial overlap (>60% line match): flag as DUPLICATE → propose deletion

Step 4 — Plan extraction
  → for each extractable section:
      if target rules file exists → merge (append, deduplicate by exact-line match)
      if target rules file absent → create new with YAML frontmatter
  → compute trimmed CLAUDE.md (extractable sections removed/replaced by delegation note)

Step 5 — Validate plan
  → verify each planned rules file has valid paths: glob
  → verify content-preservation invariant: union(trimmed CLAUDE.md + rules files) ≥ original
  → compute N_after (trimmed CLAUDE.md line count)
  → if (N_before - N_after) / N_before < 0.30 → warn "< 30% reduction achievable"

Step 6 — HITL gate
  → display unified diff in markdown code block
  → AskUserQuestion: Approve / Reject / Abort
  → on Reject: show diff again with optional notes (loop once)
  → on Abort: exit, no writes

Step 7 — Apply
  → backup: cp CLAUDE.md CLAUDE.md.bak-<YYYY-MM-DD>
  → write each rules file (create or overwrite with merged content)
  → write trimmed CLAUDE.md
  → report: N_before → N_after lines, files written, reduction %
```

---

## Extraction Heuristic

A section is **extractable** if its heading or body contains file-pattern keywords:

| Keyword pattern | Maps to | paths: glob |
|---|---|---|
| `*.sh`, `bash`, `zsh`, `shell`, `AppleScript` | `shell.md` | `**/*.{sh,bash}` |
| `*.py`, `Python`, `python3`, `venv`, `pip` | `python.md` | `**/*.py` |
| `*.swift`, `SwiftUI`, `Swift`, `SwiftData`, `Xcode`, `xcodebuild` | `swift.md` | `**/*.swift` |
| `*.ts`, `*.tsx`, `TypeScript`, `Node`, `npm` | `typescript.md` | `**/*.{ts,tsx}` |
| `*.js`, `*.jsx`, `JavaScript` (no TS present) | `javascript.md` | `**/*.{js,jsx}` |
| `migrations/`, `migration`, `ALTER TABLE`, `schema` | `migrations.md` | `**/migrations/**` |
| `*.md`, `Markdown`, `documentation`, `docs/` | `markdown.md` | `**/*.md` |
| `*.sql`, `SQL`, `database`, `DB` | `sql.md` | `**/*.sql` |

A section is **non-extractable** if it contains global behavioral rules (e.g., "Git conventions",
"Tone", "Security guardrails", "Identity") — these apply to all contexts and must remain in CLAUDE.md.

**Split rule:** if a section contains both extractable content (specific file patterns) AND
global behavioral rules (always-apply constraints), the section is flagged as MIXED. The skill
proposes a split: extractable part → rules file, non-extractable part stays in CLAUDE.md.
The HITL diff shows both halves clearly.

---

## Rules File Format

Each generated or extended `.claude/rules/<domain>.md` follows:

```markdown
---
paths:
  - "<glob>"
---

# <Domain heading>

<content from CLAUDE.md section>
```

The YAML frontmatter must have exactly one `paths:` list with at least one glob. The orchestrator
validates this before showing the HITL gate.

---

## Trimmed CLAUDE.md Format

Extracted sections are replaced by a one-line delegation note pointing to the rules file:

```markdown
<!-- <domain> rules moved to .claude/rules/<domain>.md (paths: <glob>) -->
```

This preserves discoverability: a reader of CLAUDE.md can see what was delegated and where.
Alternatively, sections can be deleted entirely (no delegation note) — this is a HITL option
shown at Step 6.

---

## --global Mode: Duplication Scan

When `--global` is set, the skill reads `~/.claude/CLAUDE.md` and checks each project
CLAUDE.md section for substantial overlap:

- **Substantial overlap**: ≥60% of section lines appear verbatim in the global file
- **Action**: flag as DUPLICATE; propose deletion from project CLAUDE.md (not extraction to rules)
- **Never**: modify `~/.claude/CLAUDE.md` (read-only in this skill)

Duplicates are shown as a separate block in the HITL diff labeled `[DUPLICATE — delete from project]`.

---

## Edge Cases

| Scenario | Behavior |
|---|---|
| CLAUDE.md has no extractable sections | Report "already lean — 0 extraction candidates", exit with no writes |
| CLAUDE.md already under 200 lines | Warn "already under target — proceeding anyway" (user may still want rules) |
| `.claude/rules/` does not exist | Create it as part of the apply step (no pre-check required) |
| Target rules file already contains identical content | Skip (no duplicate appended) |
| Section would be 100% extracted (nothing remains) | Remove section entirely from CLAUDE.md (no delegation note needed) |
| MIXED section where split is ambiguous | Flag as MANUAL — show in report, skip auto-extraction |
| project_root has no `.claude/` at all | Warn, offer to create `.claude/rules/` on approval |
| CLAUDE.md.bak-<date> already exists | Abort with error: "backup file already exists — delete it manually first" |
| --global but ~/.claude/CLAUDE.md absent | Disable duplication scan silently, warn in output |

---

## Backup Strategy

Before any write:
```bash
cp "$CLAUDE_MD" "${CLAUDE_MD}.bak-$(date +%Y-%m-%d)"
```

Follows the global CLAUDE.md safety rule: "Back up before modifying critical files." The
`.bak-YYYY-MM-DD` pattern is already in `.gitignore` (`*.bak-*`).

---

## Success Criteria

1. **CLAUDE.md reduced by ≥30%** line count compared to pre-run state
2. **All generated `.claude/rules/*.md`** have valid YAML frontmatter with `paths:` containing at least one glob
3. **Content-preservation invariant**: union of trimmed CLAUDE.md + all rules files contains all content from original CLAUDE.md
4. **No broken delegation references**: if delegation notes are added, they point to files that exist
5. **Skill produces its own test harness** at `~/.claude/skills/claude-md-slim/tests/run-tests.sh`

---

## Tests

The test harness (`tests/run-tests.sh`) covers:

- **T01**: section parser correctly splits a multi-H2 CLAUDE.md
- **T02**: keyword heuristic identifies shell/python/swift sections; skips git/tone/security sections
- **T03**: MIXED section detection (section with both extractable + global content)
- **T04**: rules file merge deduplicates identical lines
- **T05**: trimmed CLAUDE.md ≥30% smaller than original (on the vibe-coding-system CLAUDE.md fixture)
- **T06**: backup file created before writes
- **T07**: CLAUDE.md.bak already-exists guard fires correctly
- **T08**: --global flag detects cross-file duplicates (fixture: two files with shared content)
- **T09**: edge case — no extractable sections → correct "already lean" exit
- **T10**: generated rules files pass YAML frontmatter validation

---

## File Layout

```
~/.claude/skills/claude-md-slim/
  SKILL.md                   ← skill prompt
  scripts/
    parse-sections.sh        ← split CLAUDE.md on H2 headings → TSV output
    classify-sections.sh     ← keyword heuristic → TSV with domain + glob
    validate-frontmatter.sh  ← verify YAML frontmatter in a rules file
    content-union-check.sh   ← verify content-preservation invariant
  tests/
    run-tests.sh             ← harness (bash 3.2 compatible)
    fixtures/
      sample-claude-md.md
      sample-global-claude-md.md
      expected-shell-rules.md
      expected-trimmed-claude-md.md
```

All scripts: bash 3.2 compatible (no associative arrays, no `${v^^}`, no `mapfile`).

---

## Stack

- Language: Bash 3.2 (scripts), Markdown (output)
- No external dependencies beyond standard macOS tools (`grep`, `sed`, `awk`, `diff`)
- Operates entirely in `~/.claude/` and `<project-root>/` — no network access
