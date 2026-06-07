# claude-md-slim skill — CLAUDE.md section extraction to path-scoped rules (TDD Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement task-by-task. Steps use
> checkboxes (`- [ ]`).

**Changelog:**
- v1.0 (2026-06-06): initial — derived from `ADR-0019-claude-md-slim-skill.md` and
  `SPEC.md`. 8 steps: scaffold, SKILL.md orchestrator prompt, parse-sections.sh,
  classify-sections.sh, validate-frontmatter.sh + content-union-check.sh, test harness,
  CLAUDE.md Decisions block update.

**Goal:** create `~/.claude/skills/claude-md-slim/` — a standalone skill that parses a
project CLAUDE.md, identifies H2 sections extractable to path-scoped `.claude/rules/`
files via keyword heuristic, validates a content-preservation invariant, presents a
unified diff to the user at a blocking HITL gate, and on Approve backs up and applies
the extraction. Optional `--global` flag detects cross-file duplicates vs `~/.claude/CLAUDE.md`.

**Architecture:** Single-session skill. Orchestrator (LLM) drives the pipeline. Four
bash scripts (bash 3.2-clean) handle I/O, section splitting, keyword classification,
frontmatter validation, and content-preservation verification. Ten structural/functional
tests in the harness cover scripts + SKILL.md anchors.

**ADR:** `docs/architecture/ADR-0019-claude-md-slim-skill.md` (Accepted 2026-06-06).
**SPEC:** `/Users/stefanoferri/Developer/vibe-coding-system/SPEC.md`.

---

## Environment notes (read first)

- **Implementation target: `~/.claude/skills/claude-md-slim/` only.** The vibe-coding-system
  doc repo holds only the ADR and this plan. Never edit source under the doc repo.
- **No git in `~/.claude/`.** Checkpoint = harness green. No commit step within this skill.
- **Bash 3.2-clean for ALL scripts** (`~/.claude` runs bash 3.2.57 on macOS system shell):
  no assoc arrays, no `mapfile`, no `${v^^}`, no process substitution `<(...)`, no here-strings
  `<<<`. Use `grep -Eq`, `case`, `[ -f ]`, temp-file maps, the `ok`/`bad` reporter idiom.
  Reference: `~/.claude/skills/deep-refactor/tests/run-tests.sh` for established idiom.
- **Do NOT edit:** any agent file, any hook, `settings.json`, `.mcp.json`, any other skill.
- **No new manifest fields.** This skill has no manifest integration in v1.
- **AskUserQuestion is mandatory for HITL gate.** Text-box prompts are bypassed silently
  in Auto mode. Every user-approval step must use `AskUserQuestion`.
- **Content-preservation invariant is a HARD gate.** If `content-union-check.sh` exits 1,
  abort immediately — do not show the diff, do not write any file.

---

## Observable-contract note

This skill creates new files only (no edits to existing skill contracts). No existing
call-sites are affected. The only observable contract introduced is the SKILL.md pipeline
itself and the TSV formats produced by `parse-sections.sh` and `classify-sections.sh`;
these are consumed only by the orchestrator LLM and the harness. No grep across other
skills is required.

---

## Steps

### Step 0 — Scaffold skill directory structure

**What to create:**
```
~/.claude/skills/claude-md-slim/
  SKILL.md                                  (empty placeholder, filled in Step 1)
  scripts/
    parse-sections.sh
    classify-sections.sh
    validate-frontmatter.sh
    content-union-check.sh
  tests/
    run-tests.sh
    fixtures/
      sample-claude-md.md
      sample-global-claude-md.md
      expected-trimmed.md
      expected-shell-rules.md
```

**Key implementation details:**

Create the directory tree. Make all scripts executable (`chmod +x`).

The `SKILL.md` placeholder at this step need only contain the YAML frontmatter block:
```yaml
---
name: claude-md-slim
description: >
  Use this skill to audit and slim a project CLAUDE.md by extracting file-type-specific
  sections to path-scoped .claude/rules/ files. Reduces always-loaded token cost.
  Trigger phrases: "slim CLAUDE.md", "extract rules", "claude-md-slim", "/skill claude-md-slim".
  NEGATIVE: Do NOT use for code review (review-triage-fix) or repo cleanup (clean-public-repo).
---
```

Full body is written in Step 1.

**Definition of done:**
- Directory tree exists at `~/.claude/skills/claude-md-slim/` with all files.
- All `.sh` files are executable.
- Running `ls -la ~/.claude/skills/claude-md-slim/scripts/` shows four scripts.
- Running `ls -la ~/.claude/skills/claude-md-slim/tests/fixtures/` shows four fixture files.

---

### Step 1 — SKILL.md orchestrator prompt

**What to create/modify:**
`~/.claude/skills/claude-md-slim/SKILL.md` — write the full prompt body.

**Key implementation details:**

The SKILL.md must open with the YAML frontmatter from Step 0, then implement the full
7-step pipeline. Write each step as a clearly delineated section with a heading.

**Invocation signature section:**
```
/skill claude-md-slim [--global] [<project-root>]
```
- `<project-root>` defaults to `$PWD`.
- `--global` enables the Step 3 duplication scan. Without `--global`, Step 3 is skipped entirely.

**Hard constraints section (required, mirrors ADR-0019 and deep-refactor pattern):**
State explicitly:
- Orchestrator-session only. Never dispatch a sub-agent.
- Never write any file without HITL approval at Step 6.
- Content-preservation invariant is a HARD gate — if violated, abort plan before showing the diff.
- `~/.claude/CLAUDE.md` is read-only in all modes.
- Backup file `.bak-YYYY-MM-DD` must be created before any write.

**Step 0 — Locate & validate:**
1. Resolve `project_root` (argument or `$PWD`).
2. Check `<project_root>/CLAUDE.md` exists. If absent: exit with "No CLAUDE.md found at `<path>`".
3. Check `<project_root>/.claude/` exists. If absent: warn "`.claude/` directory not found —
   it will be created on Approve along with `.claude/rules/`". Do NOT create it yet.
4. Read CLAUDE.md line count: `N_before=$(wc -l < "$CLAUDE_MD")`.
5. If `--global`: check `~/.claude/CLAUDE.md` exists. If absent: warn "global CLAUDE.md not found —
   --global duplication scan disabled" and clear the flag silently.

**Step 1 — Parse sections:**
Call `parse-sections.sh "$CLAUDE_MD"`. Capture TSV output to a temp file:
```bash
PARSE_TMP=$(mktemp /tmp/claude-md-slim-parse.XXXXXX)
bash "$SKILL_DIR/scripts/parse-sections.sh" "$CLAUDE_MD" > "$PARSE_TMP"
```
If TSV is empty (no lines output): report "CLAUDE.md has no H2 sections — nothing to parse" and exit.

The TSV columns are: `heading<TAB>line_start<TAB>line_end`.

**Step 2 — Classify sections:**
Call `classify-sections.sh "$PARSE_TMP" "$CLAUDE_MD"`. Capture TSV output to a temp file:
```bash
CLASS_TMP=$(mktemp /tmp/claude-md-slim-class.XXXXXX)
bash "$SKILL_DIR/scripts/classify-sections.sh" "$PARSE_TMP" "$CLAUDE_MD" > "$CLASS_TMP"
```
The output TSV columns are: `heading<TAB>domain<TAB>glob<TAB>classification`.

If no rows are `extractable`: report "No extractable sections found — CLAUDE.md already lean (0
extraction candidates)" and exit cleanly (no writes).

If all rows are `non-extractable`: same report and exit.

**Step 3 — [--global only] Duplication scan:**
Skip entirely if `--global` flag is not set or was cleared in Step 0.

When active: for each section in the parse TSV, extract its body (lines `line_start` to `line_end`
from CLAUDE.md). Compute line count of the section body. Compare each line against `~/.claude/CLAUDE.md`
using `grep -Fc`. If `matching_lines / total_lines >= 0.60`: flag section as `DUPLICATE`.

The duplication check should use a temp file for the section body:
```bash
# extract section body from CLAUDE.md lines line_start..line_end
sed -n "${line_start},${line_end}p" "$CLAUDE_MD" > "$SECTION_TMP"
total=$(wc -l < "$SECTION_TMP")
matched=$(grep -Fc -f "$SECTION_TMP" "$HOME/.claude/CLAUDE.md" 2>/dev/null || echo 0)
# note: grep -F -c -f counts matching lines in the global file, not exact ratio
# use awk for ratio: matched/total >= 0.60
```

IMPORTANT: `grep -c -f` counts lines in the target file that match ANY pattern in the pattern file,
not lines in the pattern file that appear in the target. The correct approach is to check each line
of the section body individually and count hits:
```bash
matched=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  grep -qF "$line" "$HOME/.claude/CLAUDE.md" && matched=$((matched + 1))
done < "$SECTION_TMP"
```
Use integer arithmetic: `$(( matched * 100 / total )) -ge 60`.

DUPLICATE sections are added to a separate list, distinct from the extraction candidates list.
They are shown in the HITL diff as `[DUPLICATE — delete from project CLAUDE.md]` blocks.

**Step 4 — Plan extraction:**
For each `extractable` section:
- Determine target rules file path: `<project_root>/.claude/rules/<domain>.md`
- If target file exists: plan = MERGE (append, dedup by exact-line match). Note the existing file.
- If target file absent: plan = CREATE (new file with YAML frontmatter + content).

For each `mixed` section:
- Add to plan as `MANUAL — flagged for user review`. Do not auto-extract.

Compute the trimmed CLAUDE.md:
- For each `extractable` section that is 100% extracted (nothing of the original section remains):
  remove the section block entirely (no delegation note).
- For each `extractable` section partially extracted:
  replace extracted content with: `<!-- <domain> rules moved to .claude/rules/<domain>.md (paths: <glob>) -->`
- For each `DUPLICATE` section: replace with `<!-- duplicate of ~/.claude/CLAUDE.md — removed -->`.
- All other sections: keep verbatim.

**Step 5 — Validate plan:**

1. Validate frontmatter for each CREATE plan entry:
   ```bash
   bash "$SKILL_DIR/scripts/validate-frontmatter.sh" "$planned_rules_file_content"
   ```
   Since the file doesn't exist yet, write the planned content to a temp file and validate that.

2. Run content-preservation invariant:
   ```bash
   bash "$SKILL_DIR/scripts/content-union-check.sh" \
     "$CLAUDE_MD" "$planned_trimmed_tmp" "$planned_rules_file1_tmp" ...
   ```
   If exits 1: ABORT. Print the missing-line count from stderr. Do not proceed to Step 6.
   Print: "Content-preservation invariant violated — plan aborted. N lines from original CLAUDE.md
   would be lost. Re-run after reviewing the classification output."

3. Compute `N_after` (line count of planned trimmed CLAUDE.md).
   Reduction = `(N_before - N_after) * 100 / N_before`.
   If reduction < 30: warn "< 30% line reduction achievable (actual: N%)". Continue — the user
   may still want the extraction even below the threshold.

**Step 6 — HITL gate:**
Show a summary before the diff:
```
CLAUDE.md slim plan for <project_root>

Before:   N_before lines
After:    N_after lines  (reduction: R%)

Sections to extract:
  <domain>: "<heading>" → .claude/rules/<domain>.md [CREATE|MERGE]
  ...

Sections flagged MANUAL (mixed content — not auto-extracted):
  "<heading>" — reason: contains both domain keywords and global behavioral rules

[--global only] Sections flagged DUPLICATE (overlap with ~/.claude/CLAUDE.md):
  "<heading>" — N% overlap

<unified diff showing all planned changes>
```

Present via `AskUserQuestion` with options:
- `Approve — apply the plan` (Recommended if invariant passed and reduction ≥ 30%)
- `Reject — do not apply; show diff again with notes` (loops once: show diff + ask for notes, then exit)
- `Abort — exit with no writes`

On Approve: proceed to Step 7.
On Reject: show diff again, ask user for notes to bring to next invocation, then exit cleanly.
On Abort: exit immediately, no writes.

**Step 7 — Apply:**
1. Create `.claude/rules/` if it does not exist: `mkdir -p "$project_root/.claude/rules/"`.
2. Backup CLAUDE.md:
   ```bash
   BAK="${CLAUDE_MD}.bak-$(date +%Y-%m-%d)"
   if [ -f "$BAK" ]; then
     echo "ERROR: backup file already exists: $BAK — delete it manually first" >&2
     exit 1
   fi
   cp "$CLAUDE_MD" "$BAK"
   ```
3. For each existing rules file being extended (MERGE): backup it similarly
   (`cp "$rules_file" "${rules_file}.bak-$(date +%Y-%m-%d)"`).
4. Write each planned rules file (CREATE: new file; MERGE: append non-duplicate lines).
5. Write trimmed CLAUDE.md (overwrite in-place).
6. Report:
   ```
   Applied.
   CLAUDE.md: N_before → N_after lines (reduction: R%)
   Files written: .claude/rules/<domain>.md [created|extended] ...
   Backup: CLAUDE.md.bak-<date>
   ```

**SKILL.md must reference `SKILL_DIR` so scripts are called by absolute path:**
```bash
SKILL_DIR="$HOME/.claude/skills/claude-md-slim"
```

**Definition of done:**
- `~/.claude/skills/claude-md-slim/SKILL.md` contains all 7 step sections.
- `grep -q 'AskUserQuestion' SKILL.md` exits 0.
- `grep -q 'backup\|\.bak' SKILL.md` exits 0.
- `grep -q 'content-union-check\|content preservation\|content-preservation' SKILL.md` exits 0.
- `grep -q 'HITL\|Approve\|Reject\|Abort' SKILL.md` exits 0.
- `grep -q 'HARD gate\|hard gate\|abort.*invariant\|invariant.*abort' SKILL.md` exits 0.

---

### Step 2 — parse-sections.sh

**What to create:**
`~/.claude/skills/claude-md-slim/scripts/parse-sections.sh`

**Key implementation details:**

Inputs: `$1` = absolute path to a CLAUDE.md file.

Output: TSV to stdout, one row per H2 section. Columns: `heading<TAB>line_start<TAB>line_end`.
Line numbers are 1-indexed. `line_end` for the last section is the last line of the file.

Algorithm (bash 3.2-clean):
```bash
#!/bin/bash
set -u
CLAUDE_MD="$1"

if [ ! -f "$CLAUDE_MD" ]; then
  echo "parse-sections.sh: file not found: $CLAUDE_MD" >&2
  exit 1
fi

# Edge: empty file
total=$(wc -l < "$CLAUDE_MD")
if [ "$total" -eq 0 ]; then
  exit 0
fi

# Read line by line, detect H2 headings (lines starting with "## ")
# Store heading + start line in temp file, then compute end lines
HEADINGS_TMP=$(mktemp /tmp/psh-headings.XXXXXX)
lineno=0
while IFS= read -r rawline; do
  lineno=$((lineno + 1))
  case "$rawline" in
    "## "*)
      heading=$(printf '%s' "$rawline" | sed 's/^## //')
      printf '%s\t%d\n' "$heading" "$lineno" >> "$HEADINGS_TMP"
      ;;
  esac
done < "$CLAUDE_MD"

# Edge: no H2 headings at all — emit PREAMBLE for the whole file
if [ ! -s "$HEADINGS_TMP" ]; then
  printf 'PREAMBLE\t1\t%d\n' "$total"
  rm -f "$HEADINGS_TMP"
  exit 0
fi

# Compute end lines: for each heading, end = next heading start - 1 (or EOF)
prev_heading=""
prev_start=0
while IFS="	" read -r heading start; do
  if [ -n "$prev_heading" ]; then
    end=$((start - 1))
    printf '%s\t%d\t%d\n' "$prev_heading" "$prev_start" "$end"
  else
    # Check for preamble (content before first H2)
    if [ "$start" -gt 1 ]; then
      printf 'PREAMBLE\t1\t%d\n' "$((start - 1))"
    fi
  fi
  prev_heading="$heading"
  prev_start="$start"
done < "$HEADINGS_TMP"

# Emit last section with end = total lines
if [ -n "$prev_heading" ]; then
  printf '%s\t%d\t%d\n' "$prev_heading" "$prev_start" "$total"
fi

rm -f "$HEADINGS_TMP"
```

Edge cases:
- Empty file (`wc -l` = 0): exit 0, no output.
- File with no H2 headings: emit one row `PREAMBLE<TAB>1<TAB><total>`.
- Content before first H2 heading (lines 1 to (first_H2 - 1)): emit a `PREAMBLE` row.
- Single section (no subsequent H2): emit with `line_end = total`.
- H2 headings with trailing whitespace: `sed 's/^## //'` handles this.

Do NOT emit H3 (`### `) or deeper headings as section boundaries. Only `## ` prefix.

**Definition of done:**
- Running against `tests/fixtures/sample-claude-md.md` produces a TSV with 5 rows
  (PREAMBLE + 4 H2 sections as defined in the fixture).
- Running against an empty file exits 0 with no output.
- Running against a file with no H2 headings emits one `PREAMBLE` row.
- Script is executable and bash 3.2-clean.

---

### Step 3 — classify-sections.sh

**What to create:**
`~/.claude/skills/claude-md-slim/scripts/classify-sections.sh`

**Key implementation details:**

Inputs:
- `$1` = path to TSV file produced by `parse-sections.sh` (or `-` to read from stdin)
- `$2` = path to the original CLAUDE.md (for body extraction by line range)

Output: TSV to stdout, one row per section. Columns:
`heading<TAB>domain<TAB>glob<TAB>classification`

Where `classification` is one of: `extractable`, `mixed`, `non-extractable`.
For `extractable` and `mixed` sections, `domain` and `glob` are populated.
For `non-extractable` sections, `domain` = `general` and `glob` = `*` (not used by the skill).

**Keyword table implementation using temp files (bash 3.2-clean — no assoc arrays):**

Write the domain→glob→keywords mapping to a temp file with a sentinel format:
```
shell|**/*.{sh,bash}|sh bash zsh shell AppleScript osascript shebang
python|**/*.py|Python python3 venv pip .py requirements
swift|**/*.swift|Swift SwiftUI SwiftData Xcode xcodebuild AppKit .swift
typescript|**/*.{ts,tsx}|TypeScript Node npm .ts .tsx
javascript|**/*.{js,jsx}|JavaScript .js .jsx
migrations|**/migrations/**|migrations migration ALTER TABLE schema change
markdown|**/*.md|Markdown .md documentation docs/
sql|**/*.sql|SQL database DB .sql
```

**Global behavioral keywords** (presence of any of these makes a section non-extractable
unless it also has domain keywords — in which case: mixed):
```
git commit push pull merge rebase branch convention workflow
tone identity security guardrail HITL always never must should
"Conventional Commits" "plan mode" "feature branch" language trust
```

**Classification algorithm per section:**
1. Extract body lines from CLAUDE.md using `sed -n "${line_start},${line_end}p"` into a temp file.
2. Build combined text from heading + body into a single temp file.
3. Scan the text for each domain's keyword list using `grep -qiF` (case-insensitive, fixed-string).
   Track matched domains. A section matches a domain if ANY keyword from that domain's list matches.
   For JavaScript: only match if NO TypeScript keyword also matched (per SPEC).
4. Scan the same text for global behavioral keywords using `grep -qiF`.
5. Classify:
   - `domain_matches > 0` AND `global_matches = 0` → `extractable`, domain = first matched domain.
   - `domain_matches > 0` AND `global_matches > 0` → `mixed`, domain = first matched domain.
   - `domain_matches = 0` (regardless of global) → `non-extractable`, domain = `general`, glob = `*`.

For sections where multiple domains match (e.g., a section about Python and TypeScript interop):
use the first domain in the keyword table order (shell > python > swift > typescript > ...).
Document this tie-breaking rule in a comment in the script.

PREAMBLE sections are always `non-extractable` (they contain file-level metadata, not conventions).
Check for heading = `PREAMBLE` explicitly at the top of the per-section logic.

**Implementation pattern (bash 3.2-clean):**
```bash
#!/bin/bash
set -u

TSV_FILE="$1"
CLAUDE_MD="$2"

# Domain table: one line per domain, format: domain|glob|keyword1 keyword2 ...
DOMAINS_TMP=$(mktemp /tmp/csh-domains.XXXXXX)
cat > "$DOMAINS_TMP" << 'DOMAINS'
shell|**/*.{sh,bash}|sh bash zsh shell AppleScript osascript shebang
python|**/*.py|Python python3 venv pip .py requirements
swift|**/*.swift|Swift SwiftUI SwiftData Xcode xcodebuild AppKit .swift
typescript|**/*.{ts,tsx}|TypeScript Node npm .ts .tsx
javascript|**/*.{js,jsx}|JavaScript .js .jsx
migrations|**/migrations/**|migrations migration schema change
markdown|**/*.md|Markdown .md documentation
sql|**/*.sql|SQL database .sql
DOMAINS

# NOTE: the here-doc (<<) IS bash 3.2 compatible. Only <<< (here-string) is not.

GLOBAL_KWDS="git commit push pull merge rebase branch tone identity security guardrail HITL always never must should"

while IFS="	" read -r heading line_start line_end; do
  # PREAMBLE is never extractable
  if [ "$heading" = "PREAMBLE" ]; then
    printf '%s\tgeneral\t*\tnon-extractable\n' "$heading"
    continue
  fi

  BODY_TMP=$(mktemp /tmp/csh-body.XXXXXX)
  sed -n "${line_start},${line_end}p" "$CLAUDE_MD" > "$BODY_TMP"

  matched_domain=""
  matched_glob=""
  has_global=0
  has_ts=0

  # Check TypeScript first to suppress JavaScript if TS matched
  grep -qiF "TypeScript" "$BODY_TMP" && has_ts=1
  grep -qiF "Node" "$BODY_TMP" && has_ts=1
  grep -qiF "npm" "$BODY_TMP" && has_ts=1
  grep -qiF ".ts" "$BODY_TMP" && has_ts=1

  while IFS="|" read -r domain glob keywords; do
    # Skip javascript if TypeScript already matched
    if [ "$domain" = "javascript" ] && [ "$has_ts" -eq 1 ]; then
      continue
    fi
    # Check each keyword (space-separated) against heading+body
    for kw in $keywords; do
      if grep -qiF "$kw" "$BODY_TMP" || printf '%s' "$heading" | grep -qiF "$kw"; then
        if [ -z "$matched_domain" ]; then
          matched_domain="$domain"
          matched_glob="$glob"
        fi
        break
      fi
    done
  done < "$DOMAINS_TMP"

  # Check global behavioral keywords
  for kw in $GLOBAL_KWDS; do
    if grep -qiF "$kw" "$BODY_TMP" || printf '%s' "$heading" | grep -qiF "$kw"; then
      has_global=1
      break
    fi
  done

  if [ -n "$matched_domain" ] && [ "$has_global" -eq 0 ]; then
    printf '%s\t%s\t%s\textractable\n' "$heading" "$matched_domain" "$matched_glob"
  elif [ -n "$matched_domain" ] && [ "$has_global" -eq 1 ]; then
    printf '%s\t%s\t%s\tmixed\n' "$heading" "$matched_domain" "$matched_glob"
  else
    printf '%s\tgeneral\t*\tnon-extractable\n' "$heading"
  fi

  rm -f "$BODY_TMP"
done < "$TSV_FILE"

rm -f "$DOMAINS_TMP"
```

**Known limitation:** the `for kw in $keywords` loop over a variable-in-while-read requires
storing keywords per domain in a temp file or parsing from IFS split. The implementation above
uses an inline read inside the domain loop which may not be bash 3.2-safe for complex cases.
The recommended implementation: write the `$keywords` part of each domain line to a separate
temp file per domain iteration and grep the body against that file:
```bash
KW_TMP=$(mktemp /tmp/csh-kw.XXXXXX)
printf '%s\n' $keywords | tr ' ' '\n' > "$KW_TMP"
grep -qif "$KW_TMP" "$BODY_TMP" && matched_domain="$domain" ...
```
Use `grep -qi -f` (pattern file, case-insensitive) for efficiency. This is bash 3.2 safe.

**Definition of done:**
- Running against `tests/fixtures/sample-claude-md.md` correctly classifies:
  - Shell section as `extractable|shell|**/*.{sh,bash}`.
  - Python section as `extractable|python|**/*.py`.
  - Git conventions section as `non-extractable|general|*`.
  - Mixed section as `mixed|<detected domain>|<glob>`.
- Running against a file where all sections are non-extractable outputs only `non-extractable` rows.
- Script is executable and bash 3.2-clean.

---

### Step 4 — validate-frontmatter.sh and content-union-check.sh

**What to create:**
- `~/.claude/skills/claude-md-slim/scripts/validate-frontmatter.sh`
- `~/.claude/skills/claude-md-slim/scripts/content-union-check.sh`

#### validate-frontmatter.sh

Inputs: `$1` = path to a rules file (or a temp file with planned content).

Checks (all must pass for exit 0):
1. First line of file is exactly `---`.
2. File contains a line starting with `paths:`.
3. File contains at least one line matching `  - "` (a quoted glob entry under `paths:`).
4. After the `paths:` block, there is a closing `---` line (second `---` before any non-frontmatter content).

Implementation:
```bash
#!/bin/bash
set -u
FILE="$1"
if [ ! -f "$FILE" ]; then
  printf 'validate-frontmatter: file not found: %s\n' "$FILE" >&2; exit 1
fi

# Check first line is ---
first=$(sed -n '1p' "$FILE")
if [ "$first" != "---" ]; then
  printf 'validate-frontmatter: missing opening --- at line 1\n' >&2; exit 1
fi

# Check paths: key exists
if ! grep -q '^paths:' "$FILE"; then
  printf 'validate-frontmatter: missing paths: key\n' >&2; exit 1
fi

# Check at least one quoted glob (  - "...)
if ! grep -q '^  - "' "$FILE"; then
  printf 'validate-frontmatter: no glob entry under paths:\n' >&2; exit 1
fi

# Check closing --- exists (line 2 or later, before any content)
closing=$(grep -n '^---' "$FILE" | awk -F: 'NR==2{print $1}')
if [ -z "$closing" ]; then
  printf 'validate-frontmatter: no closing --- found\n' >&2; exit 1
fi

exit 0
```

#### content-union-check.sh

Inputs:
- `$1` = path to the original CLAUDE.md
- `$2...$N` = paths to output files (trimmed CLAUDE.md + rules files, can be temp files)

Algorithm:
For each non-empty, non-comment line in `$1`:
- A line is a comment if it starts with `<!--` (delegation notes are new, not original).
- Check if the exact line appears in ANY of the output files using `grep -qF`.
- Count lines that appear in none of the output files.

Exit 0 if all lines are accounted for.
Exit 1 with a summary to stderr: `N lines from original not found in any output file`.

Implementation (bash 3.2-clean — key constraint: must not use process substitution):
```bash
#!/bin/bash
set -u
ORIGINAL="$1"
shift
# $@ is now the list of output files

missing=0
lineno=0
while IFS= read -r line; do
  lineno=$((lineno + 1))
  # Skip empty lines
  [ -z "$line" ] && continue
  # Skip comment lines (delegation notes)
  case "$line" in
    "<!--"*) continue ;;
  esac
  # Check if line appears in any output file
  found=0
  for outfile in "$@"; do
    if grep -qF "$line" "$outfile" 2>/dev/null; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    missing=$((missing + 1))
  fi
done < "$ORIGINAL"

if [ "$missing" -gt 0 ]; then
  printf '%d lines from original not found in any output file\n' "$missing" >&2
  exit 1
fi
exit 0
```

**Performance note:** for a 300-line CLAUDE.md, this runs 300 greps. On macOS with four output
files, each grep scans ~200 lines. Total: ~60 k comparisons. This is fast enough (< 1 second)
without optimization.

**Definition of done:**
- `validate-frontmatter.sh` exits 0 on a valid rules file; exits 1 with stderr on missing `paths:`.
- `validate-frontmatter.sh` exits 1 when first line is not `---`.
- `content-union-check.sh` exits 0 when all original lines appear in at least one output file.
- `content-union-check.sh` exits 1 and prints count when a line is missing.
- Both scripts are executable and bash 3.2-clean.

---

### Step 5 — Fixtures

**What to create:**
- `~/.claude/skills/claude-md-slim/tests/fixtures/sample-claude-md.md`
- `~/.claude/skills/claude-md-slim/tests/fixtures/sample-global-claude-md.md`
- `~/.claude/skills/claude-md-slim/tests/fixtures/expected-trimmed.md`
- `~/.claude/skills/claude-md-slim/tests/fixtures/expected-shell-rules.md`

**Key implementation details:**

**`sample-claude-md.md`** must contain exactly:
- A short preamble paragraph before any H2 heading (for PREAMBLE detection test).
- `## Shell Conventions` — body contains `bash`, `zsh`, `*.sh` → extractable (shell).
- `## Python Environment` — body contains `python3`, `venv`, `pip` → extractable (python).
- `## Git Workflow` — body contains `commit`, `branch`, `always`, `never`, `Conventional Commits`
  → non-extractable (global behavioral).
- `## Swift and Xcode` — body contains `Swift`, `xcodebuild` AND `always` (a constraint like
  "always run xcodebuild test before commit") → mixed (swift + global behavioral).

Five sections total (PREAMBLE + 4 H2). Each section body must be at least 5 lines to make the
deduplication and percentage tests meaningful.

**`sample-global-claude-md.md`** must contain:
- A subset of the Shell Conventions section lines (enough for ≥60% overlap with the shell section
  in `sample-claude-md.md`). This validates the --global duplication detection.
- Content not present in `sample-claude-md.md` (to avoid false positives in the content-union check).

**`expected-trimmed.md`** must be the expected output when the `sample-claude-md.md` is processed:
- Shell Conventions section replaced with: `<!-- shell rules moved to .claude/rules/shell.md (paths: **/*.{sh,bash}) -->`
- Python Environment section replaced with: `<!-- python rules moved to .claude/rules/python.md (paths: **/*.py) -->`
- Git Workflow section kept verbatim.
- Swift and Xcode section kept verbatim (MIXED → not auto-extracted).
- PREAMBLE kept verbatim.

**`expected-shell-rules.md`** must contain the expected output for `.claude/rules/shell.md`:
```markdown
---
paths:
  - "**/*.{sh,bash}"
---

# Shell Conventions

<verbatim content from ## Shell Conventions section in sample-claude-md.md>
```

**Definition of done:**
- All four fixture files exist and are non-empty.
- `parse-sections.sh tests/fixtures/sample-claude-md.md` produces exactly 5 rows (PREAMBLE + 4).
- `classify-sections.sh <parse-output> tests/fixtures/sample-claude-md.md` produces:
  - `Shell Conventions|shell|**/*.{sh,bash}|extractable`
  - `Python Environment|python|**/*.py|extractable`
  - `Git Workflow|general|*|non-extractable`
  - `Swift and Xcode|swift|**/*.swift|mixed`

---

### Step 6 — Test harness (run-tests.sh)

**What to create:**
`~/.claude/skills/claude-md-slim/tests/run-tests.sh`

**Key implementation details:**

Use the `ok`/`bad` reporter idiom from `deep-refactor/tests/run-tests.sh`. Set variables:
```bash
SKILL="$HOME/.claude/skills/claude-md-slim/SKILL.md"
SCRIPTS="$HOME/.claude/skills/claude-md-slim/scripts"
FIXTURES="$HOME/.claude/skills/claude-md-slim/tests/fixtures"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
```

**T01 — parse-sections.sh correctly identifies H2 sections + PREAMBLE:**
```bash
OUT=$(bash "$SCRIPTS/parse-sections.sh" "$FIXTURES/sample-claude-md.md")
# Should have 5 rows (PREAMBLE + 4 H2)
count=$(printf '%s\n' "$OUT" | grep -c '.')
[ "$count" -eq 5 ] && ok "T01: parse-sections produces 5 rows" || bad "T01: expected 5 rows, got $count"
# PREAMBLE row present
printf '%s\n' "$OUT" | grep -q '^PREAMBLE' \
  && ok "T01: PREAMBLE row present" || bad "T01: PREAMBLE row missing"
# Shell Conventions row present
printf '%s\n' "$OUT" | grep -q 'Shell Conventions' \
  && ok "T01: Shell Conventions row present" || bad "T01: Shell Conventions row missing"
```

**T02 — classify-sections.sh marks shell/python as extractable, Git/tone as non-extractable:**
```bash
PARSE_TMP=$(mktemp /tmp/t02.XXXXXX)
bash "$SCRIPTS/parse-sections.sh" "$FIXTURES/sample-claude-md.md" > "$PARSE_TMP"
CLASS=$(bash "$SCRIPTS/classify-sections.sh" "$PARSE_TMP" "$FIXTURES/sample-claude-md.md")
printf '%s\n' "$CLASS" | grep -q 'Shell Conventions.*extractable' \
  && ok "T02: Shell extractable" || bad "T02: Shell not extractable"
printf '%s\n' "$CLASS" | grep -q 'Python Environment.*extractable' \
  && ok "T02: Python extractable" || bad "T02: Python not extractable"
printf '%s\n' "$CLASS" | grep -q 'Git Workflow.*non-extractable' \
  && ok "T02: Git non-extractable" || bad "T02: Git not non-extractable"
rm -f "$PARSE_TMP"
```

**T03 — classify-sections.sh marks MIXED section correctly:**
```bash
# Reuse CLASS from T02 (recreate if needed)
PARSE_TMP=$(mktemp /tmp/t03.XXXXXX)
bash "$SCRIPTS/parse-sections.sh" "$FIXTURES/sample-claude-md.md" > "$PARSE_TMP"
CLASS=$(bash "$SCRIPTS/classify-sections.sh" "$PARSE_TMP" "$FIXTURES/sample-claude-md.md")
printf '%s\n' "$CLASS" | grep -q 'Swift and Xcode.*mixed' \
  && ok "T03: Swift+Xcode section classified as mixed" \
  || bad "T03: Swift+Xcode section not mixed"
rm -f "$PARSE_TMP"
```

**T04 — content-union-check.sh passes when all lines preserved; fails when a line is missing:**
```bash
# Pass case: original + two output files together contain all lines
bash "$SCRIPTS/content-union-check.sh" \
  "$FIXTURES/sample-claude-md.md" \
  "$FIXTURES/expected-trimmed.md" \
  "$FIXTURES/expected-shell-rules.md" \
  >/dev/null 2>&1 \
  && ok "T04: content-union-check passes on complete set" \
  || bad "T04: content-union-check failed on complete set"

# Fail case: provide only expected-trimmed (shell section is missing)
bash "$SCRIPTS/content-union-check.sh" \
  "$FIXTURES/sample-claude-md.md" \
  "$FIXTURES/expected-trimmed.md" \
  >/dev/null 2>&1 \
  && bad "T04: content-union-check should fail with incomplete output set" \
  || ok "T04: content-union-check correctly fails with incomplete output set"
```

**T05 — validate-frontmatter.sh passes valid rules file; fails on missing paths:**
```bash
bash "$SCRIPTS/validate-frontmatter.sh" "$FIXTURES/expected-shell-rules.md" >/dev/null 2>&1 \
  && ok "T05: validate-frontmatter passes valid file" \
  || bad "T05: validate-frontmatter failed on valid file"

# Create a temp invalid file (no paths:)
INVALID_TMP=$(mktemp /tmp/t05-invalid.XXXXXX)
printf '---\n# Shell\nsome content\n---\n' > "$INVALID_TMP"
bash "$SCRIPTS/validate-frontmatter.sh" "$INVALID_TMP" >/dev/null 2>&1 \
  && bad "T05: validate-frontmatter should fail on missing paths:" \
  || ok "T05: validate-frontmatter correctly fails on missing paths:"
rm -f "$INVALID_TMP"
```

**T06 — SKILL.md contains "backup" and ".bak" (structural anchor):**
```bash
grep -qi 'backup' "$SKILL" \
  && ok "T06: SKILL.md contains 'backup'" || bad "T06: 'backup' missing from SKILL.md"
grep -q '\.bak' "$SKILL" \
  && ok "T06: SKILL.md contains '.bak'" || bad "T06: '.bak' missing from SKILL.md"
```

**T07 — SKILL.md contains "AskUserQuestion" and "Approve" (structural anchor — HITL gate present):**
```bash
grep -q 'AskUserQuestion' "$SKILL" \
  && ok "T07: AskUserQuestion present in SKILL.md" || bad "T07: AskUserQuestion missing"
grep -q 'Approve' "$SKILL" \
  && ok "T07: Approve option present in SKILL.md" || bad "T07: Approve missing"
```

**T08 — SKILL.md contains "content-union-check" or "content preservation" (structural anchor):**
```bash
grep -Eq 'content-union-check|content preservation|content-preservation' "$SKILL" \
  && ok "T08: content-preservation reference present in SKILL.md" \
  || bad "T08: content-preservation reference missing from SKILL.md"
```

**T09 — parse-sections.sh handles empty file gracefully (exit 0, no output):**
```bash
EMPTY_TMP=$(mktemp /tmp/t09-empty.XXXXXX)
# mktemp creates an empty file
OUT=$(bash "$SCRIPTS/parse-sections.sh" "$EMPTY_TMP" 2>/dev/null)
status=$?
[ "$status" -eq 0 ] && ok "T09: parse-sections exits 0 on empty file" \
  || bad "T09: parse-sections non-zero exit on empty file"
[ -z "$OUT" ] && ok "T09: parse-sections produces no output on empty file" \
  || bad "T09: parse-sections produced unexpected output on empty file"
rm -f "$EMPTY_TMP"
```

**T10 — classify-sections.sh handles file with no extractable sections (only non-extractable rows):**
```bash
# Create a fixture with only non-extractable content
NE_TMP=$(mktemp /tmp/t10-ne.XXXXXX)
printf '## Git Conventions\n\nAlways use Conventional Commits. Never commit secrets.\n\n## Identity\n\nMy name is Adriano.\n' > "$NE_TMP"
PARSE_TMP=$(mktemp /tmp/t10-parse.XXXXXX)
bash "$SCRIPTS/parse-sections.sh" "$NE_TMP" > "$PARSE_TMP"
CLASS=$(bash "$SCRIPTS/classify-sections.sh" "$PARSE_TMP" "$NE_TMP" 2>/dev/null)
extractable_count=$(printf '%s\n' "$CLASS" | grep -c 'extractable$' || echo 0)
[ "$extractable_count" -eq 0 ] \
  && ok "T10: no extractable rows when all sections are non-extractable" \
  || bad "T10: expected 0 extractable rows, got $extractable_count"
rm -f "$NE_TMP" "$PARSE_TMP"
```

**Final summary block (required, matches deep-refactor idiom):**
```bash
printf -- '----\n'
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

**Definition of done:**
- `bash ~/.claude/skills/claude-md-slim/tests/run-tests.sh` outputs `PASS=16 FAIL=0`
  (or higher PASS if the implementer adds sub-assertions; FAIL must be 0).
- The harness is bash 3.2-clean (no assoc arrays, no mapfile, no <<<, no process substitution).
- T01–T10 each produce at least one PASS or FAIL line.

---

### Step 7 — Register ADR-0019 in vibe-coding-system CLAUDE.md Decisions block

**What to modify:**
`/Users/stefanoferri/Developer/vibe-coding-system/CLAUDE.md`

**Key implementation details:**

Append a new `## Decisions from the claude-md-slim chain (ADR-0019)` section to the end of the
file (after the `## Decisions from chain deep-refactor-skill (ADR-0018)` block).

The block follows the established format (see ADR-0011, ADR-0015, ADR-0016, ADR-0018 entries in
the same file). It must be concise: 4–6 bullet points summarizing key decisions only.

Content to add:
```markdown
## Decisions from the claude-md-slim chain (ADR-0019)

CLAUDE.md token-reduction skill (`/skill claude-md-slim`): parses H2 sections, classifies
via keyword heuristic, extracts file-type-specific sections to `.claude/rules/<domain>.md`
with `paths:` frontmatter, validates content-preservation invariant, applies after HITL approval.

Key architectural decisions:
- **Single-session skill (no sub-agent dispatch):** blocking HITL gates require orchestrator;
  keyword classification is deterministic, not LLM-judged.
- **Keyword heuristic (D2):** heading + body scanned for file-pattern keywords (shell/python/swift/
  typescript/javascript/migrations/markdown/sql). MIXED sections flagged for manual review.
- **Propose-then-apply after HITL (D3):** no report-only mode; Reject option covers the
  "show plan without applying" need. Single-session, no plan-file persistence.
- **Merge into existing rules files (D4):** dedup by exact-line match; no skip-on-exists,
  no suffix-numbered new files.
- **Content-preservation invariant is a HARD gate (D6):** abort plan before HITL if any
  original line would be lost. Not advisory.
- **--global flag (D5):** project CLAUDE.md read-only of `~/.claude/CLAUDE.md` (which is always
  read-only in this skill). Duplication threshold: ≥60% verbatim line overlap.

Detail: `docs/architecture/ADR-0019-claude-md-slim-skill.md`.
```

**Observable-contract note:** This edit adds a new section at the end of CLAUDE.md. It does not
modify any existing section. No call-site grep is required. The `## Commands` section and other
existing sections remain untouched.

**Definition of done:**
- `grep -q 'ADR-0019' /Users/stefanoferri/Developer/vibe-coding-system/CLAUDE.md` exits 0.
- `grep -q 'claude-md-slim' /Users/stefanoferri/Developer/vibe-coding-system/CLAUDE.md` exits 0.
- The Decisions block follows the established formatting pattern of prior ADR entries.
- No existing content in CLAUDE.md is modified.

---

## Test command

```bash
bash ~/.claude/skills/claude-md-slim/tests/run-tests.sh
```

Run this after Step 6 to verify the harness passes. Run it again after Step 7 is complete
to confirm no regression (the doc repo edit does not affect the harness, but confirming T06–T08
pass after SKILL.md is finalized is good practice).

---

## Dependency order

Steps must be implemented in this order:

1. Step 0 (scaffold) — creates the directory tree; all subsequent steps write into it.
2. Step 2 (parse-sections.sh) — Step 5 fixtures depend on its output; Step 6 harness calls it.
3. Step 3 (classify-sections.sh) — depends on parse-sections.sh output format.
4. Step 4 (validate-frontmatter.sh + content-union-check.sh) — independent of Steps 2/3 in logic
   but tested in Step 6 harness.
5. Step 5 (fixtures) — depends on knowing the expected output of Steps 2 and 3 to write correct
   expected files.
6. Step 1 (SKILL.md) — can be written after Step 0; logical content depends on all script contracts
   being defined (Steps 2–4). Write it after Steps 2–4 are stable.
7. Step 6 (harness) — depends on all scripts and fixtures existing.
8. Step 7 (CLAUDE.md update) — independent of all other steps; do last to avoid editing the doc
   repo before the implementation is proven working.
