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
# NO PLANT DECLARED, AND THIS IS THE REASON RATHER THAN AN OVERSIGHT. A plant SUBSTITUTES text
# inside one file; it cannot remove a file from the vendored tree, and file presence is the
# whole of what this assertion reads. Same shape as NT2's reason and a different cause: NT2
# cannot have litter CREATED for it, this one cannot have a file TAKEN AWAY. Planting the
# harness's own file list instead would prove the assertion reacts to its own mutation, which
# is rule 1's trap and not evidence about the tree.
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

# plant: NT1 | sync-to-claude.sh | plugin/skills/project-tasks/scripts/ledger-merge.sh|skills/project-tasks/scripts/ledger-merge.sh
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

# plant: NT3 | plugin/scripts/tests/project-tasks-ledger.test.sh | -name '.remember' -o -path '*/.claude/test-cmd' | -name '.no-such-litter-name'
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

# plant: NT4 | sync-to-claude.sh | # deployed-only: vibiso-intake | # deployed-only: project-tasks reinstated by a plant
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

# plant: NT6 | plugin/skills/project-tasks/scripts/scan.sh | MARKER_RE='(^[[:space:]]*\*|//|#|--|/\*|<!--|;)(.*[^A-Za-z_])?(TODO|FIXME|HACK|XXX|BUG):' | MARKER_RE='(^|[^A-Za-z_])(TODO|FIXME|HACK|XXX|BUG)([:( ]|$)'
# ===========================================================================================
# NT6 (R-15) — the two measured false positives no longer fire. Fixture holds, verbatim, a line
# `# UF. THE SELF-COLLISION IS EXPECTED, NOT A BUG (ADR-0059 §D4)` and a line
# a declaration line ending in `echo NONEMPTY-BUG` (assembled below, see the note there).
# Run the vendored scan.sh
# and assert zero MARKER records. A Makefile in the fixture satisfies scan.sh's own project-root
# guard (exit 3 otherwise) without pulling in git.
# ===========================================================================================
NT6_DIR="$TMP/nt6-fixture"
mkdir -p "$NT6_DIR"
touch "$NT6_DIR/Makefile"
# THE DECLARATION KEYWORD IS ASSEMBLED AT RUNTIME, and neither position for a literal works.
# plant-check.sh collects declarations with a column-1 anchor over the RAW TEXT of every test
# file, heredocs included, so a verbatim copy here is parsed as a real declaration targeting a
# file called x.sh; and PC4 refuses an indented one, so moving it right is not an escape either.
# Splitting the keyword leaves the FIXTURE line byte-identical to the measured original, which is
# where verbatim actually matters, and leaves this file with no declaration it did not intend.
_nt6_kw="pl""ant"
{
  printf '%s\n' "# UF. THE SELF-COLLISION IS EXPECTED, NOT A BUG (ADR-0059 §D4)"
  printf '# %s: RRP1 | x.sh | needle | echo NONEMPTY-BUG\n' "$_nt6_kw"
} > "$NT6_DIR/fp.sh"
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

# plant: NT7 | plugin/skills/project-tasks/scripts/scan.sh | grep -oE '(TODO|FIXME|HACK|XXX|BUG):' | grep -oE 'ZZZNOMATCH'
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
# Field 4 is the CLASSIFICATION; field 5 is the line's text, and the text of a FIXME marker
# contains the word FIXME whatever the classifier decides. Matching the record loosely let a
# plant that blanked the classifier pass — measured 2026-08-18 (rule 1).
NT7_FIXME=$(printf '%s\n' "$NT7_OUT" | awk -F'\t' '$1=="MARKER" && $4=="FIXME"' | grep -c .); [ -z "$NT7_FIXME" ] && NT7_FIXME=0
if [ -f "$SCAN" ] && [ "$NT7_TOTAL" -eq 4 ] && [ "$NT7_FIXME" -eq 1 ]; then
  ok "NT7 (R-15): genuine markers still fire — 4 MARKER records, FIXME classified correctly"
else
  bad "NT7 (R-15): vendored scan.sh absent, or found $NT7_TOTAL MARKER record(s) (want 4) / $NT7_FIXME FIXME record(s) (want 1)"
fi

# plant: NT8 | plugin/skills/project-tasks/SKILL.md | - **Never auto-close.** | - Auto-closing is fine now.
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

# plant: NT9 | plugin/skills/project-conductor/SKILL.md | Invoke the `project-tasks` skill in its full mode | Invoke the ledger skill in its full mode
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
# Task 4 (tester-owned) — the GitHub-read assertions, NT11..NT15. EVERY ONE IS EXPECTED RED at
# Batch C: gh-issues.sh is written by Task 5, at Batch D. Nothing here calls `gh`, touches the
# network or reads $HOME; every assertion drives the helper through --issues-json, the offline
# hook staging/plugin/scripts/roadmap-from-issues.sh already establishes.
# ===========================================================================================
GHISSUES="$SKILL/scripts/gh-issues.sh"

# gh_stub <dir> <mode> — build a fake `gh` on a private PATH so NT14b's three causes are each
# EXECUTED rather than text-pinned. mode: auth-fail | repo-fail. The absent case needs no stub,
# only a PATH without gh.
gh_stub() {
  mkdir -p "$1"
  cat > "$1/gh" <<STUB
#!/bin/bash
case "\$1 \$2" in
  "auth status") [ "$2" = auth-fail ] && { echo "not logged in" >&2; exit 1; } ; exit 0 ;;
  "repo view")   [ "$2" = repo-fail ] && { echo "no remote" >&2; exit 1; } ; echo '{"nameWithOwner":"o/n"}' ; exit 0 ;;
esac
exit 0
STUB
  chmod +x "$1/gh"
}

GH_TMP="$TMP/gh"
mkdir -p "$GH_TMP/nobin"

cat > "$GH_TMP/three.json" <<'JSON'
[{"number":401,"title":"first issue","state":"OPEN","labels":[{"name":"bug"},{"name":"p1"}]},{"number":402,"title":"second issue","state":"OPEN","labels":[]},{"number":403,"title":"third issue","state":"OPEN","labels":[{"name":"docs"}]}]
JSON
cat > "$GH_TMP/dup.json" <<'JSON'
[{"number":401,"title":"first issue","state":"OPEN","labels":[]},{"number":401,"title":"same number again","state":"OPEN","labels":[]}]
JSON
printf '[]\n' > "$GH_TMP/empty.json"

cat > "$GH_TMP/ledger-two.md" <<'MD'
<!-- project-tasks: prefix=VCS lastId=27 -->
# PROJECT TASKS

## GitHub Issues

- [ ] `#401` **P2** first issue <!-- src:github opened:2026-08-01 -->
- [ ] `#402` **P3** second issue <!-- src:github opened:2026-08-01 -->

## Open Issues

_none_
MD
cat > "$GH_TMP/ledger-empty.md" <<'MD'
<!-- project-tasks: prefix=VCS lastId=27 -->
# PROJECT TASKS

## GitHub Issues

_none_

## Open Issues

_none_
MD

# plant: NT11 | plugin/skills/project-tasks/scripts/gh-issues.sh | t = field(buf, "title");  gsub(/[\t\n]/, " ", t) | t = ""
# ===========================================================================================
# NT11 (R-04) — three open issues in, exactly three ISSUE records out, exit 0. Assert the FIELDS
# and not only the count: a helper emitting three records with an empty title or a dropped label
# set satisfies a count and loses the payload the ledger is built from.
# ===========================================================================================
NT11_OUT=""; NT11_RC=99
if [ -f "$GHISSUES" ]; then
  NT11_OUT=$(bash "$GHISSUES" --issues-json "$GH_TMP/three.json" 2>/dev/null); NT11_RC=$?
fi
NT11_N=$(printf '%s\n' "$NT11_OUT" | grep -c '^ISSUE'); [ -z "$NT11_N" ] && NT11_N=0
NT11_NUMS=$(printf '%s\n' "$NT11_OUT" | awk -F'\t' '/^ISSUE/{print $2}' | sort | tr '\n' ' ')
NT11_TITLE=$(printf '%s\n' "$NT11_OUT" | awk -F'\t' '/^ISSUE/ && $2==402 {print $4}')
NT11_LBL=$(printf '%s\n' "$NT11_OUT" | awk -F'\t' '/^ISSUE/ && $2==401 {print $5}')
NT11_STATE=$(printf '%s\n' "$NT11_OUT" | awk -F'\t' '/^ISSUE/ && $2==403 {print $3}')
if [ "$NT11_RC" -eq 0 ] && [ "$NT11_N" -eq 3 ] && [ "$NT11_NUMS" = "401 402 403 " ] \
   && [ "$NT11_TITLE" = "second issue" ] && [ -n "$NT11_LBL" ] && [ -n "$NT11_STATE" ]; then
  ok "NT11 (R-04): 3 issues in, 3 ISSUE records out with number, state, title and labels (rc=0)"
else
  bad "NT11 (R-04): rc=$NT11_RC records=$NT11_N nums='$NT11_NUMS' title402='$NT11_TITLE' labels401='$NT11_LBL' state403='$NT11_STATE'"
fi

# plant: NT12 | plugin/skills/project-tasks/scripts/gh-issues.sh | if [ -n "$DUPES" ]; then | if false; then
# ===========================================================================================
# NT12 (R-04) — a duplicated issue number is a DETECTABLE FAILURE, not a silent dedup. Exit 3 and
# the number named on stderr. R-04 says each issue appears exactly once; a helper that quietly
# collapses the pair satisfies that sentence while hiding that its input was wrong.
# plant: NT13b | plugin/skills/project-tasks/scripts/gh-issues.sh | [ -n "$PREV" ] || PREV=0 | PREV=1
# ===========================================================================================
NT12_ERR=""; NT12_RC=99
if [ -f "$GHISSUES" ]; then
  NT12_ERR=$(bash "$GHISSUES" --issues-json "$GH_TMP/dup.json" 2>&1 >/dev/null); NT12_RC=$?
fi
if [ "$NT12_RC" -eq 3 ] && printf '%s' "$NT12_ERR" | grep -q '401'; then
  ok "NT12 (R-04): a duplicated issue number exits 3 and names the number on stderr"
else
  bad "NT12 (R-04): rc=$NT12_RC (want 3), stderr names 401: $(printf '%s' "$NT12_ERR" | grep -c '401')"
fi

# plant: NT13 | plugin/skills/project-tasks/scripts/gh-issues.sh | if [ "$PREV" -gt 0 ]; then | if false; then
# ===========================================================================================
# NT13/NT13b (R-05) — the denominator guard, both directions (rule 7). Zero issues against a
# section that ALREADY held two is a broken derivation: exit 4 and a DIDNOTRUN record. Zero issues
# against an empty section is legitimate: exit 0. Assert the exit code AND the record — a
# non-zero exit with no record on stdout is indistinguishable from a crash.
#
# The exit code asserted here is the CONTRACT's 4 and not merely "non-zero", which is stricter
# than the plan's own wording for this assertion: the plan's Task 5 block reserves 3 for "could
# not evaluate" and 4 for "broken derivation", and collapsing them would let a helper that cannot
# read its input pass as one that read it and found a contradiction.
# ===========================================================================================
NT13_OUT=""; NT13_RC=99
if [ -f "$GHISSUES" ]; then
  NT13_OUT=$(bash "$GHISSUES" --issues-json "$GH_TMP/empty.json" --ledger "$GH_TMP/ledger-two.md" 2>/dev/null); NT13_RC=$?
fi
NT13_REC=$(printf '%s\n' "$NT13_OUT" | grep -c '^DIDNOTRUN'); [ -z "$NT13_REC" ] && NT13_REC=0
if [ "$NT13_RC" -eq 4 ] && [ "$NT13_REC" -ge 1 ]; then
  ok "NT13 (R-05): zero issues against a section holding two exits 4 with a DIDNOTRUN record"
else
  bad "NT13 (R-05): rc=$NT13_RC (want 4), DIDNOTRUN records=$NT13_REC (want >=1)"
fi

NT13B_OUT=""; NT13B_RC=99
if [ -f "$GHISSUES" ]; then
  NT13B_OUT=$(bash "$GHISSUES" --issues-json "$GH_TMP/empty.json" --ledger "$GH_TMP/ledger-empty.md" 2>/dev/null); NT13B_RC=$?
fi
NT13B_N=$(printf '%s\n' "$NT13B_OUT" | grep -c '^ISSUE'); [ -z "$NT13B_N" ] && NT13B_N=0
if [ "$NT13B_RC" -eq 0 ] && [ "$NT13B_N" -eq 0 ]; then
  ok "NT13b (R-05): zero issues against an empty section is exit 0 with no ISSUE records"
else
  bad "NT13b (R-05): rc=$NT13B_RC (want 0), ISSUE records=$NT13B_N (want 0)"
fi

# plant: NT14 | plugin/skills/project-tasks/scripts/gh-issues.sh | printf 'DIDNOTRUN\t%s\t%s\n' "$1" "$2" | printf 'DIDNOTRUN\t%s\n' "$1"
# ===========================================================================================
# NT14 (R-06) — `gh` absent. A DIDNOTRUN record naming BOTH a cause and a remedy, and the
# reserved did-not-run code 3, never 0. Rule 4: a check that could not run must not read as a
# check that found nothing. The PATH prefix is the idiom selftest.sh already uses.
# ===========================================================================================
NT14_OUT=""; NT14_RC=99
if [ -f "$GHISSUES" ]; then
  NT14_OUT=$(PATH="$GH_TMP/nobin:/usr/bin:/bin" bash "$GHISSUES" 2>/dev/null); NT14_RC=$?
fi
NT14_REM=$(printf '%s\n' "$NT14_OUT" | awk -F'\t' '/^DIDNOTRUN/{print $3}')
NT14_CAUSE=$(printf '%s\n' "$NT14_OUT" | awk -F'\t' '/^DIDNOTRUN/{print $2}')
if [ "$NT14_RC" -eq 3 ] && [ -n "$NT14_CAUSE" ] && [ -n "$NT14_REM" ]; then
  ok "NT14 (R-06): gh absent gives exit 3 and a DIDNOTRUN record carrying a cause and a remedy"
else
  bad "NT14 (R-06): rc=$NT14_RC (want 3), cause='$NT14_CAUSE' remedy='$NT14_REM' (both must be non-empty)"
fi

# plant: NT14b | plugin/skills/project-tasks/scripts/gh-issues.sh | didnotrun "gh-unauthenticated" | didnotrun "gh-absent"
# ===========================================================================================
# NT14b (R-06) — the three causes are DISTINGUISHABLE, and all three are EXECUTED, not text-pinned
# (rule 16). A fake `gh` on a private PATH produces the unauthenticated and no-remote branches
# without a network, so no branch here is asserted by its message string alone.
# ===========================================================================================
gh_stub "$GH_TMP/bin-auth" auth-fail
gh_stub "$GH_TMP/bin-repo" repo-fail
NT14B_ABSENT=""; NT14B_AUTH=""; NT14B_REPO=""
NT14B_RC_AUTH=99; NT14B_RC_REPO=99
if [ -f "$GHISSUES" ]; then
  NT14B_ABSENT=$(PATH="$GH_TMP/nobin:/usr/bin:/bin" bash "$GHISSUES" 2>/dev/null | awk -F'\t' '/^DIDNOTRUN/{print $2}')
  NT14B_AUTH=$(PATH="$GH_TMP/bin-auth:/usr/bin:/bin" bash "$GHISSUES" 2>/dev/null | awk -F'\t' '/^DIDNOTRUN/{print $2}')
  NT14B_RC_AUTH=$?
  NT14B_REPO=$(PATH="$GH_TMP/bin-repo:/usr/bin:/bin" bash "$GHISSUES" 2>/dev/null | awk -F'\t' '/^DIDNOTRUN/{print $2}')
  NT14B_RC_REPO=$?
fi
NT14B_UNIQ=$(printf '%s\n%s\n%s\n' "$NT14B_ABSENT" "$NT14B_AUTH" "$NT14B_REPO" | grep -v '^$' | sort -u | wc -l | tr -d ' ')
if [ "$NT14B_UNIQ" -eq 3 ]; then
  ok "NT14b (R-06): gh absent, unauthenticated and no-remote give three distinct causes, all executed"
else
  bad "NT14b (R-06): $NT14B_UNIQ distinct cause(s) (want 3) — absent='$NT14B_ABSENT' auth='$NT14B_AUTH' repo='$NT14B_REPO'"
fi

# plant: NT15 | plugin/skills/project-tasks/scripts/gh-issues.sh | # --- duplicate detection | [ -n "$LEDGER" ] && echo planted >> "$LEDGER"\n# --- duplicate detection
# ===========================================================================================
# NT15 (R-06) — the helper is a REPORTER of evidence and never a writer, exactly as scan.sh is.
# Assert the ledger file is byte-identical across every invocation shape above, including the two
# that fail. Compared by content, not by mtime: a rewrite with identical bytes is still a write
# this assertion is content to allow, and a mtime check would be flaky under a same-second run.
# ===========================================================================================
cp "$GH_TMP/ledger-two.md" "$GH_TMP/ledger-probe.md"
NT15_BEFORE=$(shasum "$GH_TMP/ledger-probe.md" | awk '{print $1}')
if [ -f "$GHISSUES" ]; then
  bash "$GHISSUES" --issues-json "$GH_TMP/three.json" --ledger "$GH_TMP/ledger-probe.md" >/dev/null 2>&1
  bash "$GHISSUES" --issues-json "$GH_TMP/empty.json" --ledger "$GH_TMP/ledger-probe.md" >/dev/null 2>&1
  bash "$GHISSUES" --issues-json "$GH_TMP/dup.json"   --ledger "$GH_TMP/ledger-probe.md" >/dev/null 2>&1
  PATH="$GH_TMP/nobin:/usr/bin:/bin" bash "$GHISSUES" --ledger "$GH_TMP/ledger-probe.md" >/dev/null 2>&1
fi
NT15_AFTER=$(shasum "$GH_TMP/ledger-probe.md" | awk '{print $1}')
if [ -f "$GHISSUES" ] && [ "$NT15_BEFORE" = "$NT15_AFTER" ]; then
  ok "NT15 (R-06): the ledger is byte-identical after four invocations, two of them failing"
else
  bad "NT15 (R-06): gh-issues.sh absent, or the ledger changed ($NT15_BEFORE -> $NT15_AFTER)"
fi

# ===========================================================================================
# Task 6 (tester-owned) — the ledger-merge assertions, NT16..NT30. EVERY ONE IS EXPECTED RED at
# Batch E except NT30, which is GREEN on arrival by design: Task 2 vendored the field it pins
# byte-identically, so NT30 is a regression pin aimed at Task 8 item 1 and its evidence is its
# plant at Task 9, not a red checkpoint (Amendment 1, batching table).
#
# NT28, NT29, NT29b and NT30 are Amendment 1's. They cover the lane the plan originally specified
# nowhere: the skill invoked outside the chain, where a manifest, a PROJECT.md and a GitHub remote
# all need not exist.
#
# ledger-merge.sh never writes, so every assertion below compares stdout against an expectation.
# ===========================================================================================
MERGE="$SKILL/scripts/ledger-merge.sh"
MG="$TMP/merge"
mkdir -p "$MG"

# lm_strip_regions <file> — everything the CONTRACT allows ledger-merge.sh to change, removed, so
# what survives is the region that must pass through untouched. Drops the GitHub Issues section
# body, drops any Steps header, and blanks every entry's provenance comment. NT16 diffs the input
# and the output through this filter; a non-empty diff is a line changed outside the contract.
lm_strip_regions() {
  awk '/^## GitHub Issues/{f=1; print; next} /^## /{f=0} f{next} {print}' "$1" \
    | sed -e '/^## Steps/d' -e 's/<!--[^>]*-->//g'
}

cat > "$MG/issues.tsv" <<'TSV'
ISSUE	401	OPEN	first issue	bug,p1
ISSUE	402	OPEN	second issue	
ISSUE	403	OPEN	third issue	docs
TSV

cat > "$MG/base.md" <<'MD'
<!-- project-tasks: prefix=VCS lastId=31 -->
# PROJECT TASKS

Updated: 2026-08-18 · Open: 3 (P1: 1)

Free prose that belongs to nobody and must survive a run unread.

## GitHub Issues

_none_

## Open Issues

- [ ] `VCS-028` **P1** a blocking thing — `src/a.sh:12` <!-- src:session opened:2026-08-01 -->
- [ ] `VCS-029` **P3** a small thing — `src/b.sh:4` <!-- src:session opened:2026-08-02 runs:1 -->
- [ ] `VCS-030` **P2** a reviewed thing — `src/c.sh:9` <!-- src:review opened:2026-08-03 -->
- [ ] `VCS-031` **P2** a survivor — `src/d.sh:1` <!-- src:session opened:2026-08-04 runs:2 -->
- [ ] `VCS-032` **P2** a declined one — `src/e.sh:2` <!-- src:session opened:2026-08-05 runs:3 promote:declined -->
- [ ] a hand-written entry with no id at all, which must never be renumbered

## Notes For Later

An unknown section the skill has never heard of. <!-- a stray comment -->

## Project Map

- **Entry point**: nothing here is derived.
MD

# plant: NT16 | plugin/skills/project-tasks/scripts/ledger-merge.sh | /^<!-- (github-read|steps|roadmap): / { next } | /<!--/ { next }
# ===========================================================================================
# NT16 (R-07) — THE PASS-THROUGH CONTRACT, and the assertion the whole safety argument of
# ADR-0153 §D2 rests on. Do not relax it later to accommodate a new section: the fixture carries
# an unknown section, free prose, a hand-written entry with no id and a stray HTML comment, and
# every one of them must survive a full run unread. Compared through lm_strip_regions, so the
# three regions the contract DOES allow to change are removed from both sides first.
# ===========================================================================================
NT16_OUT="$MG/out16.md"; NT16_RC=99
if [ -f "$MERGE" ]; then
  bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --mode full --today 2026-08-18 > "$NT16_OUT" 2>/dev/null
  NT16_RC=$?
fi
NT16_DIFF="n/a"
if [ -f "$MERGE" ] && [ -s "$NT16_OUT" ]; then
  lm_strip_regions "$MG/base.md" > "$MG/a16"; lm_strip_regions "$NT16_OUT" > "$MG/b16"
  NT16_DIFF=$(diff "$MG/a16" "$MG/b16" | wc -l | tr -d ' ')
fi
NT16_PROSE=$(grep -c 'Free prose that belongs to nobody' "$NT16_OUT" 2>/dev/null); [ -z "$NT16_PROSE" ] && NT16_PROSE=0
NT16_UNK=$(grep -c '^## Notes For Later' "$NT16_OUT" 2>/dev/null); [ -z "$NT16_UNK" ] && NT16_UNK=0
NT16_NOID=$(grep -c 'a hand-written entry with no id at all' "$NT16_OUT" 2>/dev/null); [ -z "$NT16_NOID" ] && NT16_NOID=0
NT16_STRAY=$(grep -c 'a stray comment' "$NT16_OUT" 2>/dev/null); [ -z "$NT16_STRAY" ] && NT16_STRAY=0
if [ "$NT16_RC" -eq 0 ] && [ "$NT16_DIFF" = "0" ] \
   && [ "$NT16_PROSE" -eq 1 ] && [ "$NT16_UNK" -eq 1 ] && [ "$NT16_NOID" -eq 1 ] && [ "$NT16_STRAY" -eq 1 ]; then
  ok "NT16 (R-07): everything outside the three contract regions passes through unread"
else
  bad "NT16 (R-07): rc=$NT16_RC diff-lines=$NT16_DIFF prose=$NT16_PROSE unknown-section=$NT16_UNK no-id-entry=$NT16_NOID stray-comment=$NT16_STRAY"
fi

# plant: NT17 | plugin/skills/project-tasks/scripts/ledger-merge.sh | sub(/[[:space:]]*-->/, " runs:1 -->", l) | sub(/opened:[0-9-]+/, "opened:2099-01-01", l)
# ===========================================================================================
# NT17 (R-07) — the field-ownership table, enforced. GitHub owns title, state and labels; TODO.md
# owns local priority, the file reference, src: and opened:. Feed a payload that changes the
# GitHub-owned fields of an entry and assert the locally-owned ones are byte-identical.
# ===========================================================================================
cat > "$MG/issues-changed.tsv" <<'TSV'
ISSUE	401	CLOSED	a completely different title	renamed,labels
TSV
NT17_LINE=""
if [ -f "$MERGE" ]; then
  NT17_LINE=$(bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues-changed.tsv" --mode full --today 2026-08-18 2>/dev/null \
              | grep 'VCS-030')
fi
NT17_OK=0
printf '%s' "$NT17_LINE" | grep -q '\*\*P2\*\*' && \
printf '%s' "$NT17_LINE" | grep -q 'src/c\.sh:9' && \
printf '%s' "$NT17_LINE" | grep -q 'src:review' && \
printf '%s' "$NT17_LINE" | grep -q 'opened:2026-08-03' && NT17_OK=1
if [ "$NT17_OK" -eq 1 ]; then
  ok "NT17 (R-07): local priority, file reference, src: and opened: survive a payload that rewrites the GitHub-owned fields"
else
  bad "NT17 (R-07): a locally-owned field was lost — line was: '$NT17_LINE'"
fi

# plant: NT18 | plugin/skills/project-tasks/scripts/ledger-merge.sh | n = substr(l, RSTART+5, RLENGTH-5) + 1 | n = substr(l, RSTART+5, RLENGTH-5) + 0
# ===========================================================================================
# NT18 (R-10) — runs: is DERIVED, absent -> 1 -> 2 across three successive --mode full runs, each
# fed the previous output. opened: byte-identical in all three, because it is never in the
# rewritten key set (ADR-0153 §D3).
# ===========================================================================================
NT18_SEQ=""; NT18_OPENED=""
if [ -f "$MERGE" ]; then
  cp "$MG/base.md" "$MG/r0.md"
  i=0
  while [ "$i" -lt 3 ]; do
    bash "$MERGE" --ledger "$MG/r$i.md" --issues "$MG/issues.tsv" --mode full --today 2026-08-18 > "$MG/r$((i+1)).md" 2>/dev/null
    i=$((i+1))
    _v=$(grep 'VCS-028' "$MG/r$i.md" | grep -oE 'runs:[0-9]+' | head -1)
    [ -z "$_v" ] && _v="runs:absent"
    NT18_SEQ="$NT18_SEQ $_v"
    NT18_OPENED="$NT18_OPENED $(grep 'VCS-028' "$MG/r$i.md" | grep -oE 'opened:[0-9-]+' | head -1)"
  done
fi
NT18_UNIQ_OPENED=$(printf '%s\n' $NT18_OPENED | sort -u | wc -l | tr -d ' ')
if [ "$NT18_SEQ" = " runs:1 runs:2 runs:3" ] && [ "$NT18_UNIQ_OPENED" -eq 1 ]; then
  ok "NT18 (R-10): runs: derives absent -> 1 -> 2 -> 3 across three full runs, opened: unchanged throughout"
else
  bad "NT18 (R-10): sequence was '$NT18_SEQ' (want ' runs:1 runs:2 runs:3'), distinct opened: values=$NT18_UNIQ_OPENED (want 1)"
fi

# plant: NT19a | plugin/skills/project-tasks/scripts/ledger-merge.sh | if (mode == "full") { | if (mode != "__never__") {
# ===========================================================================================
# NT19a..NT19d (R-10, R-08) — FOUR sub-assertions, one per cheap mode, which is what the plan asks
# for in these words: "a loop over one mode would pass with three modes unimplemented". Under
# quick, add, close and map, runs: is unchanged and no promotion proposal is rendered.
# ===========================================================================================
for _m in quick add close map; do
  case "$_m" in quick) _lbl=NT19a ;; add) _lbl=NT19b ;; close) _lbl=NT19c ;; map) _lbl=NT19d ;; esac
  _runs=""; _props=99; _rc=99
  if [ -f "$MERGE" ]; then
    bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --mode "$_m" --today 2026-08-18 \
      --proposals "$MG/prop-$_m" > "$MG/out-$_m.md" 2>/dev/null
    _rc=$?
    _runs=$(grep 'VCS-031' "$MG/out-$_m.md" 2>/dev/null | grep -oE 'runs:[0-9]+' | head -1)
    # rule 5: never `grep -c ... || echo 0` — on zero matches grep PRINTS 0 and exits 1, so the
    # fallback appends a second line and the comparison below dies on "0\n0". `|| true` only
    # neutralises the exit code.
    _props=0; [ -f "$MG/prop-$_m" ] && _props=$(grep -c . "$MG/prop-$_m" || true)
  fi
  if [ "$_rc" -eq 0 ] && [ "$_runs" = "runs:2" ] && [ "$_props" -eq 0 ]; then
    ok "$_lbl (R-10, R-08): --mode $_m leaves runs: at 2 and renders no proposal"
  else
    bad "$_lbl (R-10, R-08): --mode $_m rc=$_rc runs='$_runs' (want runs:2) proposals=$_props (want 0)"
  fi
done

# plant: NT20 | plugin/skills/project-tasks/scripts/ledger-merge.sh | if (line ~ /\*\*P1\*\*/ || line ~ /src:review/ || disk_runs(line) >= 2) { | if (1) {
# ===========================================================================================
# NT20 (R-08) — the proposal set under --mode full is EXACTLY: every P1, every src:review, and
# every entry at runs: >= 2. The negative case is what proves the predicate is a filter and not a
# pass-through: VCS-029 is P3, is not src:review and sits at runs:1, so it must be absent.
# ===========================================================================================
NT20_SET=""
if [ -f "$MERGE" ]; then
  bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --mode full --today 2026-08-18 \
    --proposals "$MG/prop-full" >/dev/null 2>&1
  NT20_SET=$(grep -oE 'VCS-0[0-9]+' "$MG/prop-full" 2>/dev/null | sort -u | tr '\n' ' ')
fi
if [ "$NT20_SET" = "VCS-028 VCS-030 VCS-031 " ]; then
  ok "NT20 (R-08): the proposal set is exactly the P1, the src:review and the runs:>=2 entry — the P3 at runs:1 is absent"
else
  bad "NT20 (R-08): proposal set was '$NT20_SET' (want 'VCS-028 VCS-030 VCS-031 ')"
fi

# plant: NT21 | plugin/skills/project-tasks/scripts/ledger-merge.sh | if (line !~ /promote:/) props | if (1) props
# ===========================================================================================
# NT21 (R-09) — promote:declined is never proposed AGAIN, which is a claim about subsequent runs
# and not about one. VCS-032 qualifies on every other condition (runs:3). Assert it is absent from
# the first run's proposals, then feed that run's output back and assert it is still absent.
# ===========================================================================================
NT21_FIRST=99; NT21_SECOND=99
if [ -f "$MERGE" ]; then
  bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --mode full --today 2026-08-18 \
    --proposals "$MG/prop-d1" > "$MG/out-d1.md" 2>/dev/null
  NT21_FIRST=$(grep -c 'VCS-032' "$MG/prop-d1" 2>/dev/null || true); [ -n "$NT21_FIRST" ] || NT21_FIRST=0
  bash "$MERGE" --ledger "$MG/out-d1.md" --issues "$MG/issues.tsv" --mode full --today 2026-08-19 \
    --proposals "$MG/prop-d2" > /dev/null 2>&1
  NT21_SECOND=$(grep -c 'VCS-032' "$MG/prop-d2" 2>/dev/null || true); [ -n "$NT21_SECOND" ] || NT21_SECOND=0
fi
if [ "$NT21_FIRST" -eq 0 ] && [ "$NT21_SECOND" -eq 0 ]; then
  ok "NT21 (R-09): a promote:declined entry is absent from the proposals on this run and on the next"
else
  bad "NT21 (R-09): declined entry proposed — run 1=$NT21_FIRST, run 2=$NT21_SECOND (both want 0)"
fi

# plant: NT22 | plugin/skills/project-tasks/scripts/ledger-merge.sh | /^## GitHub Issues/{print; print ins; next} | /^## GitHub Issues/{print; next}
# ===========================================================================================
# NT22 (R-11) — after promotion the entry is ONE line in GitHub Issues carrying both identifiers,
# and the local id appears exactly once in the WHOLE FILE. Assert the whole-file count and not
# merely the old section's absence: the entry MOVES section, it is not duplicated, and a copy left
# behind reads as two open things.
# ===========================================================================================
NT22_WHOLE=0; NT22_LINE=""
if [ -f "$MERGE" ]; then
  bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --mode full --today 2026-08-18 \
    --promote VCS-031=470 > "$MG/out22.md" 2>/dev/null
  NT22_WHOLE=$(grep -c 'VCS-031' "$MG/out22.md" 2>/dev/null || true); [ -n "$NT22_WHOLE" ] || NT22_WHOLE=0
  NT22_LINE=$(awk '/^## GitHub Issues/{f=1; next} /^## /{f=0} f' "$MG/out22.md" 2>/dev/null | grep 'VCS-031')
fi
NT22_BOTH=0
printf '%s' "$NT22_LINE" | grep -q 'VCS-031' && printf '%s' "$NT22_LINE" | grep -q '#470' && NT22_BOTH=1
if [ "$NT22_WHOLE" -eq 1 ] && [ "$NT22_BOTH" -eq 1 ]; then
  ok "NT22 (R-11): the promoted entry is one line in GitHub Issues carrying both VCS-031 and #470, and appears once in the whole file"
else
  bad "NT22 (R-11): whole-file occurrences=$NT22_WHOLE (want 1), section line carries both ids=$NT22_BOTH — line: '$NT22_LINE'"
fi

# plant: NT23 | plugin/skills/project-tasks/scripts/ledger-merge.sh | [ -z "$DUP_IDS" ] || SELF_ERR="$SELF_ERR local id(s) appearing more than once: $DUP_IDS" | :
# ===========================================================================================
# NT23 (R-04) — the self-check, exercised through its WHOLE-FILE UNIQUENESS half: a fixture whose
# input already carries VCS-031 twice must exit 3 naming the id, never render a file that repeats
# it. NO SEAM WAS ADDED to drive this. The other half of the self-check — an input ISSUE that the
# rendered section drops — cannot be driven from outside a correct renderer by construction, since
# a correct renderer produces no such input; the plan allowed a planted count comparison for it and
# that is Task 9's job, which is the mechanism rule 2 describes and not a gap in this assertion.
# ===========================================================================================
sed 's/^- \[ \] `VCS-030`/- [ ] `VCS-031`/' "$MG/base.md" > "$MG/dup-id.md"
NT23_RC=99; NT23_ERR=""
if [ -f "$MERGE" ]; then
  NT23_ERR=$(bash "$MERGE" --ledger "$MG/dup-id.md" --issues "$MG/issues.tsv" --mode full --today 2026-08-18 2>&1 >/dev/null)
  NT23_RC=$?
fi
if [ "$NT23_RC" -eq 3 ] && printf '%s' "$NT23_ERR" | grep -q 'VCS-031'; then
  ok "NT23 (R-04): the self-check exits 3 and names the id that appears twice"
else
  bad "NT23 (R-04): rc=$NT23_RC (want 3), stderr names VCS-031: $(printf '%s' "$NT23_ERR" | grep -c 'VCS-031')"
fi

# plant: NT24 | plugin/skills/project-tasks/scripts/ledger-merge.sh | '/^topic:/{print $2}' | '/^nosuchfield:/{print $2}'
# ===========================================================================================
# NT24 (R-12) — with exactly one non-terminal manifest the Steps header names it and the case
# token reads "derived". Non-terminal is current_step AND status both non-terminal, and
# status: aborted is terminal even when current_step is not (ADR-0113), which the fixture set
# below exercises rather than assumes.
# ===========================================================================================
MAN1="$MG/man-one"; mkdir -p "$MAN1"
# THE FIXTURE FILENAMES DELIBERATELY DO NOT CONTAIN THE SLUG. They did, and both NT24 and
# NT25 passed against a reader that was looking for a field name no manifest in the corpus
# uses (`topic_slug:` — 0 of 61 — where the real field is `topic:` — 61 of 61). Every
# manifest fell through to the basename, and the basename happened to carry the slug, so
# two green assertions were evidence about `basename` and not about the reader. Edited in
# place on 2026-08-18 for that reason (ADR-0073: an in-place assertion edit gets a sentence).
cat > "$MAN1/2026-08-17-one.manifest.yml" <<'YML'
topic: "alpha"
current_step: "step_5_implementation"
status: "in_progress"
YML
cat > "$MAN1/2026-08-01-two.manifest.yml" <<'YML'
topic: "beta"
current_step: "completed"
status: "completed"
YML
cat > "$MAN1/2026-08-02-three.manifest.yml" <<'YML'
topic: "gamma"
current_step: "step_2_architecture"
status: "aborted"
YML
NT24_HDR=""
if [ -f "$MERGE" ]; then
  NT24_HDR=$(bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --manifests "$MAN1" \
              --mode full --today 2026-08-18 2>/dev/null | grep '^## Steps')
fi
if printf '%s' "$NT24_HDR" | grep -q 'alpha' && printf '%s' "$NT24_HDR" | grep -qi 'derived'; then
  ok "NT24 (R-12): one non-terminal manifest — the Steps header names it and reads derived"
else
  bad "NT24 (R-12): Steps header was '$NT24_HDR' (want it to name alpha and read derived)"
fi

# plant: NT25 | plugin/skills/project-tasks/scripts/ledger-merge.sh | case "$MAN_N" in 0) MAN_STATE="zero" ;; 1) MAN_STATE="one" ;; *) MAN_STATE="many" ;; esac | MAN_STATE="one"
# ===========================================================================================
# NT25 (R-13) — zero non-terminal manifests omits the section AND states the reason; two name both
# candidates and derive nothing. Assert the STATED reason in the zero case: a silently absent
# section and a deliberately omitted one must not read alike (rule 4).
# ===========================================================================================
MAN0="$MG/man-zero"; mkdir -p "$MAN0"
cp "$MAN1/2026-08-01-two.manifest.yml" "$MAN0/"
MAN2="$MG/man-two"; mkdir -p "$MAN2"
cp "$MAN1/2026-08-17-one.manifest.yml" "$MAN2/"
cat > "$MAN2/2026-08-16-four.manifest.yml" <<'YML'
topic: "delta"
current_step: "step_3_project_memory"
status: "in_progress"
YML
NT25_ZERO_HDR="x"; NT25_ZERO_REASON=0; NT25_TWO=""
if [ -f "$MERGE" ]; then
  _z=$(bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --manifests "$MAN0" --mode full --today 2026-08-18 2>/dev/null)
  NT25_ZERO_HDR=$(printf '%s\n' "$_z" | grep -c '^## Steps')
  NT25_ZERO_REASON=$(printf '%s\n' "$_z" | grep -ci 'no non-terminal manifest')
  NT25_TWO=$(bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --manifests "$MAN2" --mode full --today 2026-08-18 2>/dev/null | grep -A2 '^## Steps')
fi
NT25_TWO_OK=0
printf '%s' "$NT25_TWO" | grep -q 'alpha' && printf '%s' "$NT25_TWO" | grep -q 'delta' && NT25_TWO_OK=1
if [ "$NT25_ZERO_HDR" = "0" ] && [ "$NT25_ZERO_REASON" -ge 1 ] && [ "$NT25_TWO_OK" -eq 1 ]; then
  ok "NT25 (R-13): zero manifests omits the section with a stated reason; two name both candidates"
else
  bad "NT25 (R-13): zero-case headers=$NT25_ZERO_HDR (want 0) reason-lines=$NT25_ZERO_REASON (want >=1); two-case names both=$NT25_TWO_OK"
fi

# plant: NT26 | plugin/skills/project-tasks/scripts/ledger-merge.sh | ptr = (n in phase && phase[n] != "") ? " — " phase[n] : "" | ptr = ""
# ===========================================================================================
# NT26 (R-14) — both directions inside one PROJECT.md fixture: an issue number that is also a
# roadmap row renders with a pointer to its phase, one that is not renders without.
# ===========================================================================================
cat > "$MG/PROJECT.md" <<'MD'
# ROADMAP

## Phase 11 — hardening

- [ ] first issue (issue #401)

## Phase 12 — later

- [x] something already done (issue #999)
MD
NT26_401=""; NT26_402=""
if [ -f "$MERGE" ]; then
  _o=$(bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --roadmap "$MG/PROJECT.md" --mode full --today 2026-08-18 2>/dev/null)
  NT26_401=$(printf '%s\n' "$_o" | grep '#401')
  NT26_402=$(printf '%s\n' "$_o" | grep '#402')
fi
NT26_OK=0
printf '%s' "$NT26_401" | grep -qi 'phase 11' && ! printf '%s' "$NT26_402" | grep -qi 'phase' && NT26_OK=1
if [ "$NT26_OK" -eq 1 ]; then
  ok "NT26 (R-14): the roadmap issue carries its phase pointer and the non-roadmap issue carries none"
else
  bad "NT26 (R-14): #401 line='$NT26_401' (want a Phase 11 pointer), #402 line='$NT26_402' (want no phase)"
fi

# plant: NT27 | plugin/skills/project-tasks/scripts/ledger-merge.sh | if (old != "") { print "P1-PRE\t" old; exit 5 } | if (old != "") { print "P1-PRE\t" old; exit 1 }
# ===========================================================================================
# NT27 (R-18) — --p1-gate is a CHECKER with three distinct exit codes so its caller in
# concept-to-code can branch (rule 5). A P1 opened after --since is NEW and blocks; one opened
# before is pre-existing and is reported without blocking. Assert both codes and both id lists.
# ===========================================================================================
NT27_NEW_RC=99; NT27_OLD_RC=99; NT27_NEW_IDS=""; NT27_OLD_IDS=""
if [ -f "$MERGE" ]; then
  NT27_NEW_IDS=$(bash "$MERGE" --ledger "$MG/base.md" --p1-gate --since 2026-07-01 2>/dev/null); NT27_NEW_RC=$?
  NT27_OLD_IDS=$(bash "$MERGE" --ledger "$MG/base.md" --p1-gate --since 2026-08-15 2>/dev/null); NT27_OLD_RC=$?
fi
if [ "$NT27_NEW_RC" -ne "$NT27_OLD_RC" ] \
   && printf '%s' "$NT27_NEW_IDS" | grep -q 'VCS-028' \
   && printf '%s' "$NT27_OLD_IDS" | grep -q 'VCS-028'; then
  ok "NT27 (R-18): --p1-gate separates a new P1 (rc=$NT27_NEW_RC) from a pre-existing one (rc=$NT27_OLD_RC), naming the id in both"
else
  bad "NT27 (R-18): new-rc=$NT27_NEW_RC old-rc=$NT27_OLD_RC (must differ); new-ids='$NT27_NEW_IDS' old-ids='$NT27_OLD_IDS'"
fi

# plant: NT28 | plugin/skills/project-tasks/scripts/ledger-merge.sh | if [ "$DIDNOTRUN_COUNT" -gt 0 ] && [ "$ISSUE_COUNT" -eq 0 ]; then | if false; then
# ===========================================================================================
# NT28 (R-06, R-13) — AMENDMENT 1. THE PRODUCER/CONSUMER MEETING POINT. NT14 and NT15 prove
# gh-issues.sh reports DIDNOTRUN and writes nothing; NT16..NT27 prove ledger-merge.sh behaves on
# well-formed input; nothing until here hands one's output to the other. A consumer that read
# DIDNOTRUN as an empty issue set would silently empty the section on every run without a network
# and every other assertion in this file would stay green while it did (rule 17). The record is
# taken from gh-issues.sh's ACTUAL output, not hand-written, so a change to its record shape
# breaks this assertion rather than sliding past it.
# ===========================================================================================
NT28_SECTION_IN=""; NT28_SECTION_OUT=""; NT28_REASON=0
if [ -f "$MERGE" ] && [ -f "$GHISSUES" ]; then
  PATH="$GH_TMP/nobin:/usr/bin:/bin" bash "$GHISSUES" > "$MG/didnotrun.tsv" 2>/dev/null
  _o=$(bash "$MERGE" --ledger "$GH_TMP/ledger-two.md" --issues "$MG/didnotrun.tsv" --mode full --today 2026-08-18 2>/dev/null)
  NT28_SECTION_IN=$(awk '/^## GitHub Issues/{f=1; next} /^## /{f=0} f' "$GH_TMP/ledger-two.md" | grep -c '#[0-9]')
  NT28_SECTION_OUT=$(printf '%s\n' "$_o" | awk '/^## GitHub Issues/{f=1; next} /^## /{f=0} f' | grep -c '#[0-9]')
  NT28_REASON=$(printf '%s\n' "$_o" | grep -ci 'did-not-run\|didnotrun')
fi
if [ -n "$NT28_SECTION_IN" ] && [ "$NT28_SECTION_IN" = "$NT28_SECTION_OUT" ] && [ "$NT28_SECTION_IN" -gt 0 ] && [ "$NT28_REASON" -ge 1 ]; then
  ok "NT28 (R-06, R-13): a DIDNOTRUN record from gh-issues.sh leaves the $NT28_SECTION_IN existing entries untouched and states the cause"
else
  bad "NT28 (R-06, R-13): entries before=$NT28_SECTION_IN after=$NT28_SECTION_OUT (must be equal and > 0), stated reason lines=$NT28_REASON (want >=1)"
fi

# plant: NT29 | plugin/skills/project-tasks/scripts/ledger-merge.sh | missing) echo "<!-- roadmap: no roadmap file at $ROADMAP | missing) echo "<!-- roadmap: quiet at $ROADMAP
# ===========================================================================================
# NT29 (R-14) — AMENDMENT 1. PROJECT.md ABSENT IS NOT PROJECT.md WITH NO MATCH. NT26 fixes both
# directions inside a fixture that exists. Zero matches can be correct; zero candidates is a broken
# derivation, and from the rendered section the two are identical (rule 7). This is the assertion
# that keeps the skill usable in a repository with no roadmap file, which is every repository
# except this one.
# ===========================================================================================
NT29_PHASES=99; NT29_REASON=0; NT29_RC=99
if [ -f "$MERGE" ]; then
  _o=$(bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --roadmap "$MG/NO-SUCH-PROJECT.md" \
        --mode full --today 2026-08-18 2>/dev/null); NT29_RC=$?
  NT29_PHASES=$(printf '%s\n' "$_o" | grep -ci 'phase [0-9]')
  NT29_REASON=$(printf '%s\n' "$_o" | grep -ci 'no roadmap file')
fi
if [ "$NT29_RC" -eq 0 ] && [ "$NT29_PHASES" -eq 0 ] && [ "$NT29_REASON" -ge 1 ]; then
  ok "NT29 (R-14): an absent roadmap file renders no phase pointer and says so in one line"
else
  bad "NT29 (R-14): rc=$NT29_RC phase-pointers=$NT29_PHASES (want 0) stated-reason=$NT29_REASON (want >=1)"
fi

# plant: NT29b | plugin/skills/project-tasks/scripts/ledger-merge.sh | missing) printf '<!-- steps: no manifests directory at %s — section omitted --> | missing) printf '<!-- steps: no non-terminal manifest under %s — section omitted -->
# ===========================================================================================
# NT29b (R-12, R-13) — AMENDMENT 1. The same third state on the other derived section: a
# --manifests root that DOES NOT EXIST is distinct from one holding zero non-terminal manifests
# (NT25). Assert the two reasons differ in text. ADR-0109 gives seven entry tokens for exactly
# this reason: "no file" and "unparseable" are inputs, not environments.
# ===========================================================================================
NT29B_MISSING=""; NT29B_EMPTY=""
if [ -f "$MERGE" ]; then
  NT29B_MISSING=$(bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --manifests "$MG/no-such-dir" \
                   --mode full --today 2026-08-18 2>/dev/null | grep -i 'manifest' | head -1)
  NT29B_EMPTY=$(bash "$MERGE" --ledger "$MG/base.md" --issues "$MG/issues.tsv" --manifests "$MAN0" \
                 --mode full --today 2026-08-18 2>/dev/null | grep -i 'manifest' | head -1)
fi
# Compare the REASON, not the line: each notice interpolates its own directory path, so two
# notices carrying the same words about different directories differ as strings while saying
# the same thing. Measured 2026-08-18 — a plant that made both wordings identical left this
# assertion green (rule 1 again, one level down).
NT29B_MISS_R=$(printf '%s' "$NT29B_MISSING" | sed -e "s|$MG/no-such-dir||" -e "s|$MAN0||")
NT29B_EMPT_R=$(printf '%s' "$NT29B_EMPTY"   | sed -e "s|$MG/no-such-dir||" -e "s|$MAN0||")
if [ -n "$NT29B_MISS_R" ] && [ -n "$NT29B_EMPT_R" ] && [ "$NT29B_MISS_R" != "$NT29B_EMPT_R" ]; then
  ok "NT29b (R-12, R-13): an absent manifests root and an empty one state two different reasons"
else
  bad "NT29b (R-12, R-13): missing='$NT29B_MISSING' empty='$NT29B_EMPTY' (both non-empty and different)"
fi

# plant: NT30 | plugin/skills/project-tasks/SKILL.md | "aggiorna il TODO", 
# ===========================================================================================
# NT30 (R-24) — AMENDMENT 1. The standalone triggers survive in the description: frontmatter.
# GREEN THE MOMENT IT IS WRITTEN, because Task 2 vendored the field byte-identically. It is a
# regression pin aimed at Task 8 item 1, which rewrites that same field, so its evidence is its
# plant at Task 9 and not a red checkpoint (rule 2). NT9 pins the other direction — that the
# description names both chains and both chains name it back — and the two must not be merged: a
# description naming only the chains would pass NT9 and leave the skill unreachable by hand.
# Matched against a flattened, undecorated, case-insensitive copy (rule 3).
# ===========================================================================================
NT30_DESC=""
[ -f "$SKILLMD" ] && NT30_DESC=$(flatten_prose "$SKILLMD")
NT30_MISSING=""
for _t in "/project-tasks" "aggiorna il todo" "cosa resta da fare" "update the task ledger" "track this issue"; do
  printf '%s' "$NT30_DESC" | grep -qF "$_t" || NT30_MISSING="$NT30_MISSING [$_t]"
done
if [ -f "$SKILLMD" ] && [ -z "$NT30_MISSING" ]; then
  ok "NT30 (R-24): the description keeps all five standalone trigger phrases"
else
  bad "NT30 (R-24): vendored SKILL.md absent, or trigger phrase(s) gone —$NT30_MISSING"
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
