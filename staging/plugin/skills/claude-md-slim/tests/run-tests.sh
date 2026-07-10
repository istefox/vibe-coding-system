#!/bin/bash
# claude-md-slim test harness — bash 3.2-clean
# T01-T10 cover parse-sections, classify-sections, content-union-check,
# validate-frontmatter, and SKILL.md structural anchors.

set -u

SKILL="$HOME/.claude/skills/claude-md-slim/SKILL.md"
SCRIPTS="$HOME/.claude/skills/claude-md-slim/scripts"
FIXTURES="$HOME/.claude/skills/claude-md-slim/tests/fixtures"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# ---------------------------------------------------------------------------
# T01 — parse-sections.sh correctly identifies H2 sections + PREAMBLE
# ---------------------------------------------------------------------------
OUT=$(bash "$SCRIPTS/parse-sections.sh" "$FIXTURES/sample-claude-md.md")
count=$(printf '%s\n' "$OUT" | grep -c '.')
[ "$count" -eq 5 ] \
  && ok "T01: parse-sections produces 5 rows" \
  || bad "T01: expected 5 rows, got $count"
printf '%s\n' "$OUT" | grep -q '^PREAMBLE' \
  && ok "T01: PREAMBLE row present" \
  || bad "T01: PREAMBLE row missing"
printf '%s\n' "$OUT" | grep -q 'Shell Conventions' \
  && ok "T01: Shell Conventions row present" \
  || bad "T01: Shell Conventions row missing"

# ---------------------------------------------------------------------------
# T02 — classify-sections.sh marks shell/python extractable, Git non-extractable
# ---------------------------------------------------------------------------
PARSE_TMP=$(mktemp /tmp/t02.XXXXXX)
bash "$SCRIPTS/parse-sections.sh" "$FIXTURES/sample-claude-md.md" > "$PARSE_TMP"
CLASS=$(bash "$SCRIPTS/classify-sections.sh" "$PARSE_TMP" "$FIXTURES/sample-claude-md.md")
printf '%s\n' "$CLASS" | grep -q 'Shell Conventions.*extractable' \
  && ok "T02: Shell extractable" \
  || bad "T02: Shell not extractable"
printf '%s\n' "$CLASS" | grep -q 'Python Environment.*extractable' \
  && ok "T02: Python extractable" \
  || bad "T02: Python not extractable"
printf '%s\n' "$CLASS" | grep -q 'Git Workflow.*non-extractable' \
  && ok "T02: Git non-extractable" \
  || bad "T02: Git not non-extractable"
rm -f "$PARSE_TMP"

# ---------------------------------------------------------------------------
# T03 — classify-sections.sh marks MIXED section correctly
# ---------------------------------------------------------------------------
PARSE_TMP=$(mktemp /tmp/t03.XXXXXX)
bash "$SCRIPTS/parse-sections.sh" "$FIXTURES/sample-claude-md.md" > "$PARSE_TMP"
CLASS=$(bash "$SCRIPTS/classify-sections.sh" "$PARSE_TMP" "$FIXTURES/sample-claude-md.md")
printf '%s\n' "$CLASS" | grep -q 'Swift and Xcode.*mixed' \
  && ok "T03: Swift+Xcode section classified as mixed" \
  || bad "T03: Swift+Xcode section not mixed"
rm -f "$PARSE_TMP"

# ---------------------------------------------------------------------------
# T04 — content-union-check.sh pass + fail cases
# ---------------------------------------------------------------------------
bash "$SCRIPTS/content-union-check.sh" \
  "$FIXTURES/sample-claude-md.md" \
  "$FIXTURES/expected-trimmed.md" \
  "$FIXTURES/expected-shell-rules.md" \
  >/dev/null 2>&1 \
  && ok "T04: content-union-check passes on complete set" \
  || bad "T04: content-union-check failed on complete set"

bash "$SCRIPTS/content-union-check.sh" \
  "$FIXTURES/sample-claude-md.md" \
  "$FIXTURES/expected-trimmed.md" \
  >/dev/null 2>&1 \
  && bad "T04: content-union-check should fail with incomplete output set" \
  || ok "T04: content-union-check correctly fails with incomplete output set"

# ---------------------------------------------------------------------------
# T05 — validate-frontmatter.sh pass + fail cases
# ---------------------------------------------------------------------------
bash "$SCRIPTS/validate-frontmatter.sh" "$FIXTURES/expected-shell-rules.md" >/dev/null 2>&1 \
  && ok "T05: validate-frontmatter passes valid file" \
  || bad "T05: validate-frontmatter failed on valid file"

INVALID_TMP=$(mktemp /tmp/t05-invalid.XXXXXX)
printf -- '---\n# Shell\nsome content\n---\n' > "$INVALID_TMP"
bash "$SCRIPTS/validate-frontmatter.sh" "$INVALID_TMP" >/dev/null 2>&1 \
  && bad "T05: validate-frontmatter should fail on missing paths:" \
  || ok "T05: validate-frontmatter correctly fails on missing paths:"
rm -f "$INVALID_TMP"

# ---------------------------------------------------------------------------
# T06 — SKILL.md backup/.bak anchors
# ---------------------------------------------------------------------------
grep -qi 'backup' "$SKILL" \
  && ok "T06: SKILL.md contains 'backup'" \
  || bad "T06: 'backup' missing from SKILL.md"
grep -q '\.bak' "$SKILL" \
  && ok "T06: SKILL.md contains '.bak'" \
  || bad "T06: '.bak' missing from SKILL.md"

# ---------------------------------------------------------------------------
# T07 — SKILL.md HITL anchors (AskUserQuestion + Approve)
# ---------------------------------------------------------------------------
grep -q 'AskUserQuestion' "$SKILL" \
  && ok "T07: AskUserQuestion present in SKILL.md" \
  || bad "T07: AskUserQuestion missing"
grep -q 'Approve' "$SKILL" \
  && ok "T07: Approve option present in SKILL.md" \
  || bad "T07: Approve missing"

# ---------------------------------------------------------------------------
# T08 — SKILL.md content-preservation anchor
# ---------------------------------------------------------------------------
grep -Eq 'content-union-check|content preservation|content-preservation' "$SKILL" \
  && ok "T08: content-preservation reference present in SKILL.md" \
  || bad "T08: content-preservation reference missing from SKILL.md"

# ---------------------------------------------------------------------------
# T09 — parse-sections.sh handles empty file gracefully
# ---------------------------------------------------------------------------
EMPTY_TMP=$(mktemp /tmp/t09-empty.XXXXXX)
OUT=$(bash "$SCRIPTS/parse-sections.sh" "$EMPTY_TMP" 2>/dev/null)
status=$?
[ "$status" -eq 0 ] \
  && ok "T09: parse-sections exits 0 on empty file" \
  || bad "T09: parse-sections non-zero exit on empty file"
[ -z "$OUT" ] \
  && ok "T09: parse-sections produces no output on empty file" \
  || bad "T09: parse-sections produced unexpected output on empty file"
rm -f "$EMPTY_TMP"

# ---------------------------------------------------------------------------
# T10 — classify-sections.sh produces 0 extractable rows for all-non-extractable input
# Note: 'extractable$' would match 'non-extractable' too — use a TAB-prefixed pattern
# so only rows ending exactly in TAB+extractable count.
# ---------------------------------------------------------------------------
NE_TMP=$(mktemp /tmp/t10-ne.XXXXXX)
printf -- '## Git Conventions\n\nAlways use Conventional Commits. Never commit secrets.\n\n## Identity\n\nMy name is Adriano.\n' > "$NE_TMP"
PARSE_TMP=$(mktemp /tmp/t10-parse.XXXXXX)
bash "$SCRIPTS/parse-sections.sh" "$NE_TMP" > "$PARSE_TMP"
CLASS=$(bash "$SCRIPTS/classify-sections.sh" "$PARSE_TMP" "$NE_TMP" 2>/dev/null)
TAB=$(printf '\t')
extractable_count=$(printf '%s\n' "$CLASS" | grep -c "${TAB}extractable\$")
[ -z "$extractable_count" ] && extractable_count=0
[ "$extractable_count" -eq 0 ] \
  && ok "T10: no extractable rows when all sections are non-extractable" \
  || bad "T10: expected 0 extractable rows, got $extractable_count"
rm -f "$NE_TMP" "$PARSE_TMP"

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
printf -- '----\n'
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
