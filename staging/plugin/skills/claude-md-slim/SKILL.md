---
name: claude-md-slim
description: >
  Use this skill to audit and slim a project CLAUDE.md by extracting file-type-specific
  sections to path-scoped .claude/rules/ files. Reduces always-loaded token cost.
  Trigger phrases: "slim CLAUDE.md", "extract rules", "claude-md-slim", "/skill claude-md-slim".
  NEGATIVE: Do NOT use for code review (review-triage-fix) or repo cleanup (clean-public-repo).
---

# claude-md-slim — CLAUDE.md section extraction to path-scoped rules

## Invocation

```
/skill claude-md-slim [--global] [<project-root>]
```

- `<project-root>` defaults to `$PWD`.
- `--global` enables the cross-file duplication scan (Step 3) against `~/.claude/CLAUDE.md`.
  Without `--global`, Step 3 is skipped entirely.

## Hard constraints (read first — non-negotiable)

- **Orchestrator-session only.** This skill runs exclusively in the orchestrator LLM session.
  Never dispatch a `coder`, `refactorer`, `reviewer`, or any other sub-agent from this skill.
  Blocking HITL gates require the orchestrator; a sub-agent in Auto mode would bypass them.
- **Never write any file without HITL approval at Step 6.** All writes are gated on the
  Approve answer from `AskUserQuestion`. The Reject and Abort paths must perform zero writes.
- **Content-preservation invariant is a HARD gate.** If `content-union-check.sh` exits non-zero
  in Step 5, abort the plan before showing the diff. Do not show the diff, do not present the
  HITL question, do not write any file.
- **`~/.claude/CLAUDE.md` is read-only in all modes.** Even with `--global`, the global file is
  scanned only; the skill never modifies it.
- **Backup before any write.** Step 7 must create `CLAUDE.md.bak-YYYY-MM-DD` (and equivalent
  `.bak-YYYY-MM-DD` copies of any rules file being extended) before overwriting.
- **Bash 3.2 invariant.** All helper scripts under `scripts/` run on the macOS system shell
  (bash 3.2.57). Do not rewrite them with assoc arrays, `mapfile`, `${v^^}`, `<<<`, or process
  substitution.

## Skill directory

```bash
SKILL_DIR="$HOME/.claude/skills/claude-md-slim"
```

All helper scripts are invoked by absolute path through `$SKILL_DIR/scripts/`.

---

## Pipeline (7 steps)

### Step 0 — Locate & validate

1. Resolve `project_root`: take the first non-flag argument, or fall back to `$PWD`.
2. `CLAUDE_MD="$project_root/CLAUDE.md"`. If it does not exist, exit with the message
   `No CLAUDE.md found at <path>` and stop.
3. Check whether `<project_root>/.claude/` exists. If absent, warn:
   `.claude/ directory not found — it will be created on Approve along with .claude/rules/`.
   Do NOT create the directory yet.
4. Record `N_before=$(wc -l < "$CLAUDE_MD")` for the reduction calculation.
5. If `--global` was passed: check that `~/.claude/CLAUDE.md` exists. If absent, warn
   `global CLAUDE.md not found — --global duplication scan disabled` and clear the flag for
   the rest of the run.

### Step 1 — Parse sections

```bash
PARSE_TMP=$(mktemp /tmp/claude-md-slim-parse.XXXXXX)
bash "$SKILL_DIR/scripts/parse-sections.sh" "$CLAUDE_MD" > "$PARSE_TMP"
```

The TSV columns are `heading<TAB>line_start<TAB>line_end`. Line numbers are 1-indexed.

If `$PARSE_TMP` is empty (no rows), report
`CLAUDE.md has no H2 sections — nothing to parse` and exit cleanly with no writes.

### Step 2 — Classify sections

```bash
CLASS_TMP=$(mktemp /tmp/claude-md-slim-class.XXXXXX)
bash "$SKILL_DIR/scripts/classify-sections.sh" "$PARSE_TMP" "$CLAUDE_MD" > "$CLASS_TMP"
```

The TSV columns are `heading<TAB>domain<TAB>glob<TAB>classification`. `classification` is
one of `extractable`, `mixed`, `non-extractable`.

If no row is `extractable` (the file is either already lean or fully behavioural), report
`No extractable sections found — CLAUDE.md already lean (0 extraction candidates)` and exit
cleanly with no writes. The same exit message applies when every row is `non-extractable`.

### Step 3 — [--global only] Duplication scan

Skip this step entirely if `--global` was not passed or was cleared in Step 0.

For each section in the parse TSV:

```bash
SECTION_TMP=$(mktemp /tmp/claude-md-slim-section.XXXXXX)
sed -n "${line_start},${line_end}p" "$CLAUDE_MD" > "$SECTION_TMP"
total=0; matched=0
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  total=$((total + 1))
  if grep -qF -- "$line" "$HOME/.claude/CLAUDE.md"; then
    matched=$((matched + 1))
  fi
done < "$SECTION_TMP"
rm -f "$SECTION_TMP"
if [ "$total" -gt 0 ] && [ "$(( matched * 100 / total ))" -ge 60 ]; then
  # flag this section as DUPLICATE
  ...
fi
```

DUPLICATE sections are tracked separately from the `extractable` plan list. They appear in
the Step 6 diff as `<!-- duplicate of ~/.claude/CLAUDE.md — removed -->` blocks. The global
file is never written.

### Step 4 — Plan extraction

For each `extractable` row:

- Compute the target rules path: `<project_root>/.claude/rules/<domain>.md`.
- If the target file exists, the plan entry is `MERGE` (append non-duplicate lines, dedup by
  exact-line match).
- If the target file is absent, the plan entry is `CREATE` (new file with YAML `paths:`
  frontmatter plus the section heading and body).

For each `mixed` row: add a `MANUAL — flagged for user review` entry. Do not auto-extract;
the section stays verbatim in the trimmed CLAUDE.md.

For each `non-extractable` row (other than `PREAMBLE`): keep the section verbatim.

`PREAMBLE` is always kept verbatim in the trimmed file.

Compute the planned trimmed CLAUDE.md by, for each `extractable` row:

- If extracting 100% of the section body (no remainder): remove the section block entirely
  with no delegation note.
- Otherwise, replace the extracted block with a single comment line:
  `<!-- <domain> rules moved to .claude/rules/<domain>.md (paths: <glob>) -->`.

For each `DUPLICATE` row (--global only): replace with
`<!-- duplicate of ~/.claude/CLAUDE.md — removed -->`.

Write the planned trimmed CLAUDE.md and each planned rules file to temp files for Step 5.

### Step 5 — Validate plan (HARD gate before HITL)

1. **Frontmatter validation** for every CREATE plan entry:
   ```bash
   bash "$SKILL_DIR/scripts/validate-frontmatter.sh" "$planned_rules_tmp"
   ```
   If any planned rules file fails frontmatter validation, abort with the script's stderr
   message. Do not show the diff.

2. **Content-preservation invariant** (the HARD gate):
   ```bash
   bash "$SKILL_DIR/scripts/content-union-check.sh" \
     "$CLAUDE_MD" \
     "$planned_trimmed_tmp" \
     "$planned_rules_tmp_1" \
     "$planned_rules_tmp_2" ...
   ```
   If the script exits non-zero, ABORT the plan immediately. Print the missing-line count
   reported on stderr. Do NOT show the diff, do NOT present the HITL question, do NOT write.
   The user message is:
   ```
   Content-preservation invariant violated — plan aborted.
   N lines from the original CLAUDE.md would be lost.
   Re-run after reviewing the classification output above.
   ```

3. **Reduction metric.** Compute
   `R = (N_before - N_after) * 100 / N_before`.
   If `R < 30`, emit a warning: `< 30% line reduction achievable (actual: R%)`. Do not abort
   — the user may still want the extraction below the threshold.

### Step 6 — HITL gate

Print the summary, then a unified diff of all planned changes:

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

<unified diff showing trimmed CLAUDE.md vs original, plus each new/extended rules file>
```

Present the HITL gate with `AskUserQuestion`. The three options are:

- `Approve — apply the plan`
  (Recommended when the content-preservation invariant passed AND `R >= 30`.)
- `Reject — do not apply; show diff again with notes`
  (Loops once: re-show the diff, ask the user for notes to carry into the next invocation,
  then exit cleanly with no writes.)
- `Abort — exit with no writes`

Behavior:
- On **Approve**: proceed to Step 7.
- On **Reject**: show the diff again, prompt the user for free-text notes, then exit cleanly.
  No writes.
- On **Abort**: exit immediately. No writes.

### Step 7 — Apply (only after Approve)

1. Create the rules directory if needed:
   ```bash
   mkdir -p "$project_root/.claude/rules"
   ```

2. Backup the project CLAUDE.md:
   ```bash
   BAK="${CLAUDE_MD}.bak-$(date +%Y-%m-%d)"
   if [ -f "$BAK" ]; then
     echo "ERROR: backup file already exists: $BAK — delete it manually first" >&2
     exit 1
   fi
   cp "$CLAUDE_MD" "$BAK"
   ```

3. For each MERGE target (an existing rules file being extended), create a same-day
   `.bak-YYYY-MM-DD` copy before appending:
   ```bash
   cp "$rules_file" "${rules_file}.bak-$(date +%Y-%m-%d)"
   ```
   Apply the same abort-if-backup-exists guard.

4. Write each planned rules file:
   - CREATE: write the new file with YAML `paths:` frontmatter plus heading and body.
   - MERGE: append only non-duplicate lines to the existing file (dedup by exact-line match).

5. Overwrite the project CLAUDE.md with the planned trimmed content.

6. Print the apply report:
   ```
   Applied.
   CLAUDE.md: N_before → N_after lines (reduction: R%)
   Files written:
     .claude/rules/<domain>.md [created|extended]
     ...
   Backup: <CLAUDE_MD>.bak-<date>
   ```

---

## Definition of done (single invocation)

- The trimmed CLAUDE.md exists with `N_after < N_before` lines.
- Every planned rules file exists and passes `validate-frontmatter.sh`.
- The original CLAUDE.md is preserved at `CLAUDE.md.bak-<date>`.
- `content-union-check.sh` (re-run post-apply against the same files) exits 0.

## Failure modes (expected, handled)

- **No CLAUDE.md:** Step 0 exits with the locate message.
- **No H2 sections:** Step 1 exits cleanly.
- **No extractable sections:** Step 2 exits cleanly.
- **Frontmatter validation fails:** Step 5 aborts before HITL.
- **Content-preservation violation:** Step 5 aborts before HITL (HARD gate).
- **User Reject:** Step 6 loops once, then exits with no writes.
- **User Abort:** Step 6 exits immediately, no writes.
- **Backup file already exists for today:** Step 7 aborts; the user must delete the existing
  backup before re-running on the same day.

## Notes for future maintainers

- Tie-breaking for multi-domain matches: first domain in the `classify-sections.sh` table
  order wins (shell > python > swift > typescript > javascript > migrations > markdown > sql).
- The MIXED classification is intentionally non-extracted in v1. Auto-splitting a mixed
  section risks misclassifying the boundary; manual review is the safer default.
- The 60% duplication threshold is fixed in v1. Re-calibration belongs in a follow-up ADR.
