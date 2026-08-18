#!/bin/bash
# project-tasks-ledger.test.sh — project-tasks becomes a vendored chain member with a bilateral
# GitHub issue ledger (ADR-0153; SPEC.md; plan
# docs/superpowers/plans/2026-08-17-project-tasks-vendored-bilateral-ledger.md).
#
# NO REQUIREMENT-ID RANGE ON THIS LINE, deliberately, and NO REQUIREMENT ID ANYWHERE IN THIS
# COMMENT EITHER. The header used to spell the SPEC's id span as a dotted range. spec-coverage.sh
# cannot tell a range endpoint from a citation, so the span's upper endpoint counted as a mention
# in a scoped test file, staled that requirement's own `(no-test: ...)` waiver and exited 3.
# Measured 2026-08-18: the range manufactured a mention for exactly one id and for no other. The
# first attempt at this very comment then reintroduced the same id three times while explaining
# the removal, and the checker stayed red — rule 1, a needle that matches the prose describing the
# mechanism. The real citations are the per-block comment headers (`# NT0 (R-01) — ...`), the form
# ADR-0138 asks for. Do not reinstate a range, and do not name a requirement id here.
#
# THIS FILE IS THE HARNESS ADR-0153 §D7 ADDS. Its subject is one skill, `project-tasks`, and it is
# a new file rather than an extension of an existing one for the reason §D7 states: no existing
# harness has this subject, and each existing one states its own single subject in its own header.
#
# Task 1 of the plan (tester-owned) writes the structural, litter and scanner assertions below —
# NT0..NT10 plus a Z1 assertion-count floor — against a feature that has not been built yet.
# EVERY ASSERTION IN THIS TASK IS EXPECTED RED (batching table, Batch A): the vendored tree does
# not exist, `deployed-only: project-tasks` has not been removed, scan.sh has not been narrowed,
# and neither chain names the skill yet. That is the deliverable of this task, not a defect in it.
#
# Two assertions in this block are the DO4/DO5 shape (pairs-completeness.test.sh's own precedent):
# a "backward self-test" that proves a detection PREDICATE itself works, run against a synthetic
# fixture the predicate was never meant to depend on production code to evaluate. Those are
# expected to be GREEN already, same as DO4/DO5 are green today with no coder work behind them —
# see NT3's own comment for the citation (ADR-0153 §D8). Z1's floor is a forward declaration of
# this file's eventual size across Tasks 1, 4 and 6 (ADR-0153 §D7 lists the assertion set), so it
# stays red until Task 6 lands regardless of any single task's own count.
#
# No `# plant:` declarations in this file yet — that is Task 9's job (ADR-0108/ADR-0149). Three
# assertions below (NT2, NT5, NT10) are declared, at their own site, to carry none ever, each for a
# different reason stated where it stands.
#
# Hermetic, offline, no $HOME dependency, no .git dependency. Root resolution is the idiom every
# sibling harness uses.
# Bash 3.2 clean. Run: bash project-tasks-ledger.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILL="$STAGING/plugin/skills/project-tasks"
SCAN="$SKILL/scripts/scan.sh"
SKILLMD="$SKILL/SKILL.md"
SYNC="$STAGING/sync-to-claude.sh"
C2C="$STAGING/plugin/skills/concept-to-code/SKILL.md"
CONDUCTOR="$STAGING/plugin/skills/project-conductor/SKILL.md"
CIWF="$STAGING/../.github/workflows/docs-ci.yml"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# flatten_prose <file> — collapse to one line, strip markdown decoration (**bold**, `code`),
# lowercase, squeeze whitespace. A clause is the same clause whether it wraps across lines, is
# backticked, is bolded or opens a sentence (rule 3) — never matched against a literal source line.
flatten_prose() {
  tr '\n' ' ' < "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/\*\*//g' -e 's/`//g' -e 's/  */ /g'
}

# pt_litter_check <dir> — THE ONE detection predicate for R-03's litter absence. NT2 and NT3 must
# both call this exact function: NT3 exists specifically to prove this predicate detects litter it
# is handed, and it can only prove that about the code NT2 actually runs (ADR-0153 §D8 part 3).
pt_litter_check() {
  find "$1" \( -name '.remember' -o -path '*/.claude/test-cmd' \) 2>/dev/null
}

# ===========================================================================================
# NT0 (R-01) — denominator guard. The vendored tree staging/plugin/skills/project-tasks/ exists
# and holds at least 7 regular files, each of the seven named individually rather than matched by
# a glob — a misspelled directory name must fail here, loudly, before NT2's absence check runs
# (rule 7: guard the denominator, not only the matches). Zero files reads exactly like a clean
# absence, which is why this assertion sits ahead of NT2 in the file.
# ===========================================================================================
PT_EXPECTED_FILES="SKILL.md scripts/scan.sh scripts/selftest.sh reference/file-format.md reference/capture-sources.md reference/chain-integration.md templates/TODO.template.md"
_nt0_missing=""
for _f in $PT_EXPECTED_FILES; do
  [ -f "$SKILL/$_f" ] || _nt0_missing="$_nt0_missing $_f"
done
_nt0_count=$(find "$SKILL" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ -z "$_nt0_missing" ] && [ "$_nt0_count" -ge 7 ]; then
  ok "NT0 (R-01): vendored tree holds all 7 named files ($_nt0_count files total)"
else
  bad "NT0 (R-01): vendored tree incomplete or absent (found $_nt0_count file(s); missing:$_nt0_missing)"
fi

# ===========================================================================================
# NT1 (R-01) — every one of the nine PAIRS src|dst lines from the plan's vendoring table is
# present in sync-to-claude.sh's PAIRS block, matched whole-line against the block extracted with
# the same awk pairs-completeness.test.sh uses. NINE, NOT SEVEN: Tasks 5 and 7 add gh-issues.sh and
# ledger-merge.sh, and this is the assertion that notices if they do not land.
# ===========================================================================================
NT1_BLOCK="$TMP/nt1-pairs-block"
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNC" > "$NT1_BLOCK"

cat > "$TMP/nt1-expected" <<'EOF'
plugin/skills/project-tasks/SKILL.md|skills/project-tasks/SKILL.md
plugin/skills/project-tasks/scripts/scan.sh|skills/project-tasks/scripts/scan.sh
plugin/skills/project-tasks/scripts/selftest.sh|skills/project-tasks/scripts/selftest.sh
plugin/skills/project-tasks/reference/file-format.md|skills/project-tasks/reference/file-format.md
plugin/skills/project-tasks/reference/capture-sources.md|skills/project-tasks/reference/capture-sources.md
plugin/skills/project-tasks/reference/chain-integration.md|skills/project-tasks/reference/chain-integration.md
plugin/skills/project-tasks/templates/TODO.template.md|skills/project-tasks/templates/TODO.template.md
plugin/skills/project-tasks/scripts/gh-issues.sh|skills/project-tasks/scripts/gh-issues.sh
plugin/skills/project-tasks/scripts/ledger-merge.sh|skills/project-tasks/scripts/ledger-merge.sh
EOF

_nt1_missing=""
while IFS= read -r _line; do
  [ -n "$_line" ] || continue
  grep -qxF "$_line" "$NT1_BLOCK" || _nt1_missing="$_nt1_missing
  $_line"
done < "$TMP/nt1-expected"
if [ -z "$_nt1_missing" ]; then
  ok "NT1 (R-01): all 9 project-tasks PAIRS lines are present in sync-to-claude.sh"
else
  bad "NT1 (R-01): PAIRS line(s) missing —$_nt1_missing"
fi

# ===========================================================================================
# NT2 (R-03) — absence. No path component `.remember` and no `.claude/test-cmd` anywhere under
# the vendored skill.
# NO PLANT AT THIS ASSERTION, DECLARED HERE RATHER THAN LEFT SILENT: a plant substitutes a needle
# inside an EXISTING file; it cannot create litter that is not there (ADR-0153 §D8 part 2). Task 9
# does not add one for NT2.
# The vendored-tree existence check is inline (not left to NT0 alone) because an absence assertion
# over a directory that does not exist reads exactly like a clean one (rule 7) — this must fail
# loudly right now, not pass vacuously because there is nothing to find litter in.
# ===========================================================================================
NT2_HITS=$(pt_litter_check "$SKILL")
if [ -d "$SKILL" ] && [ -z "$NT2_HITS" ]; then
  ok "NT2 (R-03): no .remember/ or .claude/test-cmd litter under the vendored skill"
else
  bad "NT2 (R-03): vendored tree absent, or litter present — $NT2_HITS"
fi

# ===========================================================================================
# NT3 (R-03) — backward self-test (ADR-0153 §D8 part 3, the DO4/DO5 shape from
# pairs-completeness.test.sh). Build a fixture directory holding BOTH .remember/now.md and
# .claude/test-cmd, run NT2's EXACT detection predicate (pt_litter_check, the same function, not a
# re-implementation) against it, and assert it flags both. Without this, NT2's absence check is
# satisfiable by a predicate that detects nothing.
# THIS ONE CARRIES A PLANT in Task 9 — self-targeting, on the predicate inside this very file
# (plant-check.sh supports self-targeting because it masks `# plant:` lines out before matching).
# It is deliberately independent of the vendored tree's existence, so — same as DO4/DO5 today —
# it is expected to be GREEN already: it proves the checker's own logic is correct, which does not
# wait on the coder building anything.
# ===========================================================================================
NT3_FIXTURE="$TMP/nt3-litter-fixture"
mkdir -p "$NT3_FIXTURE/.remember" "$NT3_FIXTURE/.claude"
printf 'session litter\n' > "$NT3_FIXTURE/.remember/now.md"
printf 'echo hi\n' > "$NT3_FIXTURE/.claude/test-cmd"
NT3_HITS=$(pt_litter_check "$NT3_FIXTURE")
if printf '%s\n' "$NT3_HITS" | grep -q '/\.remember$' \
   && printf '%s\n' "$NT3_HITS" | grep -q '/\.claude/test-cmd$'; then
  ok "NT3 (R-03): the litter predicate flags a fixture holding both .remember and .claude/test-cmd"
else
  bad "NT3 (R-03): the predicate did not flag the litter fixture — got: $NT3_HITS"
fi

# ===========================================================================================
# NT4 (R-02) — sync-to-claude.sh contains NO `deployed-only: project-tasks` line. Needle built at
# run time (DMARK, rule 12) so this harness does not match its own explanatory prose above — the
# idiom pairs-completeness.test.sh line 226 already uses.
# ===========================================================================================
DMARK="deployed""-only"
if grep -q "^# *${DMARK}: project-tasks" "$SYNC" 2>/dev/null; then
  bad "NT4 (R-02): sync-to-claude.sh still declares project-tasks $DMARK"
else
  ok "NT4 (R-02): no '$DMARK: project-tasks' line in sync-to-claude.sh"
fi

# ===========================================================================================
# NT5 (R-02) — the deployed-only registry still holds at least 5 declarations AFTER project-tasks's
# line is removed, so DO1's floor (pairs-completeness.test.sh) is not breached by this feature.
# Compound with NT4's own detection deliberately: a bare count-floor check on the CURRENT registry
# would read >= 5 today (six entries, project-tasks among them) and pass vacuously before the
# removal even happens, which is exactly the false-green this assertion exists to rule out.
# VACUITY GUARD, NO PLANT (rule 10 — a floor absorbs its own plant): this is a floor check on a
# derived count, not a claim a single mutation can prove or disprove.
# ===========================================================================================
NT5_COUNT=$(grep -c "^# *${DMARK}: " "$SYNC" 2>/dev/null); [ -z "$NT5_COUNT" ] && NT5_COUNT=0
NT5_HAS_PT=$(grep -c "^# *${DMARK}: project-tasks" "$SYNC" 2>/dev/null); [ -z "$NT5_HAS_PT" ] && NT5_HAS_PT=0
if [ "$NT5_HAS_PT" -eq 0 ] && [ "$NT5_COUNT" -ge 5 ]; then
  ok "NT5 (R-02): registry holds $NT5_COUNT declaration(s) (>= 5) with project-tasks removed"
else
  bad "NT5 (R-02): not yet in the post-removal state (count=$NT5_COUNT, project-tasks still declared=$NT5_HAS_PT)"
fi

# ===========================================================================================
# NT6 (R-15) — the two measured false positives no longer fire. Fixture holds, verbatim, a line
# `# UF. THE SELF-COLLISION IS EXPECTED, NOT A BUG (ADR-0059 §D4)` and a line
# `# plant: RRP1 | x.sh | needle | echo NONEMPTY-BUG`. Run the vendored scan.sh --root <fixture>
# and assert zero MARKER records. A Makefile in the fixture satisfies scan.sh's own project-root
# guard (exit 3 otherwise) without pulling in git.
# ===========================================================================================
NT6_DIR="$TMP/nt6-fixture"
mkdir -p "$NT6_DIR"
touch "$NT6_DIR/Makefile"
cat > "$NT6_DIR/fp.sh" <<'EOF'
# UF. THE SELF-COLLISION IS EXPECTED, NOT A BUG (ADR-0059 §D4)
# plant: RRP1 | x.sh | needle | echo NONEMPTY-BUG
EOF
NT6_OUT=""
[ -f "$SCAN" ] && NT6_OUT=$(bash "$SCAN" --root "$NT6_DIR" 2>/dev/null)
NT6_HITS=$(printf '%s\n' "$NT6_OUT" | grep -c '^MARKER'); [ -z "$NT6_HITS" ] && NT6_HITS=0
if [ -f "$SCAN" ] && [ "$NT6_HITS" -eq 0 ]; then
  ok "NT6 (R-15): the two measured false positives produce zero MARKER records"
else
  bad "NT6 (R-15): vendored scan.sh absent, or still emits $NT6_HITS MARKER record(s) for the false-positive fixture"
fi

# ===========================================================================================
# NT6b (R-15) — a markdown prose line in declaration form does not fire. Fixture holds, verbatim,
# in a .md file: `- narrowed: it matches \`TODO:\`, \`FIXME:\` and \`XXX:\` with the colon`. Zero
# MARKER records. This is the half the colon test ALONE cannot reject — the line has the colon but
# no comment leader earlier on the line (ADR-0153 §D9).
# ===========================================================================================
NT6B_DIR="$TMP/nt6b-fixture"
mkdir -p "$NT6B_DIR"
touch "$NT6B_DIR/Makefile"
printf -- '- narrowed: it matches `TODO:`, `FIXME:` and `XXX:` with the colon\n' > "$NT6B_DIR/note.md"
NT6B_OUT=""
[ -f "$SCAN" ] && NT6B_OUT=$(bash "$SCAN" --root "$NT6B_DIR" 2>/dev/null)
NT6B_HITS=$(printf '%s\n' "$NT6B_OUT" | grep -c '^MARKER'); [ -z "$NT6B_HITS" ] && NT6B_HITS=0
if [ -f "$SCAN" ] && [ "$NT6B_HITS" -eq 0 ]; then
  ok "NT6b (R-15): a markdown prose line in declaration form produces zero MARKER records"
else
  bad "NT6b (R-15): vendored scan.sh absent, or still emits $NT6B_HITS MARKER record(s) for the prose fixture"
fi

# ===========================================================================================
# NT7 (R-15) — genuine markers still fire, in both shapes. Fixture holds `// TODO: extract`,
# `// FIXME: leaks`, `// HACK: monkeypatch` on their own lines and `foo(); // TODO: fix` as a
# trailing comment. Assert exactly 4 MARKER records and that FIXME is classified as FIXME.
# ===========================================================================================
NT7_DIR="$TMP/nt7-fixture"
mkdir -p "$NT7_DIR"
touch "$NT7_DIR/Makefile"
cat > "$NT7_DIR/genuine.js" <<'EOF'
// TODO: extract
// FIXME: leaks
// HACK: monkeypatch
foo(); // TODO: fix
EOF
NT7_OUT=""
[ -f "$SCAN" ] && NT7_OUT=$(bash "$SCAN" --root "$NT7_DIR" 2>/dev/null)
NT7_TOTAL=$(printf '%s\n' "$NT7_OUT" | grep -c '^MARKER'); [ -z "$NT7_TOTAL" ] && NT7_TOTAL=0
NT7_FIXME=$(printf '%s\n' "$NT7_OUT" | grep -c '^MARKER.*FIXME'); [ -z "$NT7_FIXME" ] && NT7_FIXME=0
if [ -f "$SCAN" ] && [ "$NT7_TOTAL" -eq 4 ] && [ "$NT7_FIXME" -eq 1 ]; then
  ok "NT7 (R-15): genuine markers still fire — 4 MARKER records, FIXME classified correctly"
else
  bad "NT7 (R-15): vendored scan.sh absent, or found $NT7_TOTAL MARKER record(s) (want 4) / $NT7_FIXME FIXME record(s) (want 1)"
fi

# ===========================================================================================
# NT8 (R-20) — the six hard rules are still stated in the vendored SKILL.md. Matched against a
# flattened, undecorated, case-insensitive copy of each clause (rule 3, flatten_prose above), not
# the literal source line.
# ===========================================================================================
NT8_MISSING=""
if [ -f "$SKILLMD" ]; then
  NT8_FLAT=$(flatten_prose "$SKILLMD")
  for _clause in "never edit source files" "never write before the approval gate" "never invent an entry" "never delete user text" "never auto-close" "outside the cwd"; do
    case "$NT8_FLAT" in *"$_clause"*) ;; *) NT8_MISSING="$NT8_MISSING [$_clause]" ;; esac
  done
else
  NT8_MISSING="(SKILL.md not vendored)"
fi
if [ -z "$NT8_MISSING" ]; then
  ok "NT8 (R-20): all six hard rules are stated in the vendored SKILL.md (flattened match)"
else
  bad "NT8 (R-20): hard-rule clause(s) not found —$NT8_MISSING"
fi

# ===========================================================================================
# NT9 (R-19) — the vendored SKILL.md's description: names concept-to-code and project-conductor,
# AND both of those skills' own SKILL.md name project-tasks. Both directions in one assertion: a
# description claiming a wiring that does not exist is what made this requirement necessary.
# RED until Task 8.
# ===========================================================================================
NT9_OK=1
NT9_REASON=""
if [ -f "$SKILLMD" ]; then
  NT9_FLAT=$(flatten_prose "$SKILLMD")
  case "$NT9_FLAT" in *"concept-to-code"*) ;; *) NT9_OK=0; NT9_REASON="$NT9_REASON description-missing-concept-to-code" ;; esac
  case "$NT9_FLAT" in *"project-conductor"*) ;; *) NT9_OK=0; NT9_REASON="$NT9_REASON description-missing-project-conductor" ;; esac
else
  NT9_OK=0; NT9_REASON="$NT9_REASON project-tasks-SKILL.md-not-vendored"
fi
if [ -f "$C2C" ] && grep -qi 'project-tasks' "$C2C"; then :; else NT9_OK=0; NT9_REASON="$NT9_REASON concept-to-code-does-not-name-project-tasks"; fi
if [ -f "$CONDUCTOR" ] && grep -qi 'project-tasks' "$CONDUCTOR"; then :; else NT9_OK=0; NT9_REASON="$NT9_REASON project-conductor-does-not-name-project-tasks"; fi
if [ "$NT9_OK" -eq 1 ]; then
  ok "NT9 (R-19): project-tasks's description names both chains, and both chains name project-tasks back"
else
  bad "NT9 (R-19): wiring incomplete —$NT9_REASON"
fi

# ===========================================================================================
# NT10 (R-01) — project-tasks appears in .github/workflows/docs-ci.yml's shell-tests list as
# `project-tasks-ledger`.
# NO PLANT, DECLARED REASON AT THIS SITE (copying CI1's wording, issue #331): plant-check.sh's
# sandbox copies staging/ and docs/; .github/ is copied for reading but is not a legal plant
# target, so this assertion's mechanism is unreachable by mutation.
# ===========================================================================================
if [ -f "$CIWF" ] && grep -o 'for t in [^;]*' "$CIWF" | head -1 | tr ' ' '\n' | grep -qxF 'project-tasks-ledger'; then
  ok "NT10 (R-01): project-tasks-ledger is in docs-ci.yml's shell-tests list"
else
  bad "NT10 (R-01): project-tasks-ledger is missing from docs-ci.yml's shell-tests list"
fi

# ===========================================================================================
# Z1 — assertion-count floor, forward-declared across this file's Task 1, 4 and 6 blocks (ADR-0153
# §D7 names the full NT0..NT27 set; ADR-0083 §D3 is the floor pattern this repeats). The plan's own
# task list totals at least 31 named assertion ids once Tasks 4 (7 ids: NT11, NT12, NT13, NT13b,
# NT14, NT14b, NT15) and 6 (12 ids: NT16..NT27) land beside this task's 12. The floor is set below
# that total on purpose (margin for a compound id resolving to one check rather than several), so
# it is DELIBERATELY UNMET at the end of Task 1 (12 ids here) and needs no further edit to this
# line once Task 6's block is written — it turns green on its own.
# ===========================================================================================
_nt_total=$((PASS + FAIL))
if [ "$_nt_total" -ge 30 ]; then
  ok "Z1: assertion-count floor ($_nt_total >= 30)"
else
  bad "Z1: assertion count is $_nt_total (floor 30, forward-declared for Tasks 1+4+6) — not yet met at Task 1"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
