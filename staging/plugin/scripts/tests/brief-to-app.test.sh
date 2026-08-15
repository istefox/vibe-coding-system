#!/bin/bash
# brief-to-app.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash brief-to-app.test.sh
#
# Issue #439 Wave 2 / ADR-0142. Covers `brief-to-app/SKILL.md` and `acceptance-declare.sh`.
# The literal path above is what skill-coverage-perimeter.test.sh requires of a covering test: a
# corpus sweep reaches a file through a glob and cannot produce that string, so naming it is the
# distinction between "a test written for this skill" and "a sweep that happened to open it".
#
# WHAT IS ENFORCEMENT AND WHAT IS NOT (rule 16), because this file covers one of each.
#   B1-B18 execute `acceptance-declare.sh` and the adapter's declared-side pattern. Mechanical.
#   B19-B27 are STRUCTURAL pins over a SKILL.md — they assert a sentence is present. That is not
#   evidence a model obeys it, and no assertion here claims to be. The skill says the same thing
#   about itself in its closing section, which B27 is the assertion for.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# plant: B4 | plugin/scripts/acceptance-declare.sh | comm -12 "$TMP/acc.ids" "$TMP/notest.ids" > "$TMP/contradiction.ids" | : > "$TMP/contradiction.ids"
# plant: B3 | plugin/scripts/acceptance-declare.sh | comm -23 "$TMP/acc.ids" "$TMP/spec.ids" > "$TMP/orphan.ids" | : > "$TMP/orphan.ids"
# plant: B6 | plugin/scripts/acceptance-declare.sh | if (length(reason) >= 20) notest = 1 | notest = 1
# plant: B7 | plugin/scripts/acceptance-declare.sh | if [ "$SPEC_N" -eq 0 ]; then | if false; then
# plant: B8 | plugin/scripts/acceptance-declare.sh | if [ -n "$PREDIR" ]; then | if false; then
# plant: B9 | plugin/scripts/acceptance-declare.sh | [ "$UNDEC" -eq 1 ] && [ "$RC" -eq 0 ] && RC=1 | [ "$UNDEC" -eq 1 ] && RC=1
# plant: B15 | plugin/scripts/acceptance-adapter-swift.sh | DECLRE='(^|[^A-Za-z0-9_])(R-[0-9][0-9])(?![0-9])' | DECLRE='(^|[^A-Za-z0-9_])(R-[0-9][0-9]?[0-9]?)(?![0-9])'
# plant: B20 | plugin/skills/brief-to-app/SKILL.md | the block below and tell the user to paste it into the composer | the block below is set as the goal automatically
# plant: B21 | plugin/skills/brief-to-app/SKILL.md | **Read first:** BRIEF.md | **Read first:** SPEC.md
# plant: B29 | plugin/skills/brief-to-app/SKILL.md | 1) printf 'HALT: a testable criterion has no acceptance case (UNDECLARED above)\n'; exit 1 ;; | 1) printf 'tolerated\n' ;;
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
DECL="$SCRIPTS/acceptance-declare.sh"
ADAPTER="$SCRIPTS/acceptance-adapter-swift.sh"
SKILL="$STAGING/plugin/skills/brief-to-app/SKILL.md"
PREDIR="$STAGING/plugin/skills/concept-to-code/scripts"
COV="$PREDIR/spec-coverage.sh"
SPRED="$PREDIR/spec-id-predicate.awk"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

spec() { printf '## Success criteria\n\n%b\n' "$1" > "$T/SPEC.md"; }
acc()  { printf '## Acceptance criteria\n\n%b\n' "$1" > "$T/ACC.md"; }
# run_decl -> sets RC and OUT. The exit code is the policy channel here (a CHECKER), unlike the two
# acceptance reporters one directory away; branching on stdout instead would read every state as
# the same one.
run_decl() { OUT=$(bash "$DECL" --spec "$T/SPEC.md" --acceptance "$T/ACC.md" 2>/dev/null); RC=$?; }

BASE_SPEC='- [ ] R-01 — the user can archive a note\n- [ ] R-02 — archiving is undoable\n- [ ] R-03 — the ADR records it (no-test: a documentation obligation that nothing executes)'

# ================================================================================================
# acceptance-declare.sh — the one enforcing mechanism in this wave.
# ================================================================================================
spec "$BASE_SPEC"
acc '- [ ] R-01 — archive, then assert absent from the active list\n- [ ] R-02 — archive then undo, assert the note returns'
run_decl
{ [ "$RC" -eq 0 ] && [ -z "$OUT" ]; } && ok "B1: a reconciled pair exits 0 and prints nothing" || bad "B1: rc=$RC out=[$OUT]"
[ -n "$OUT" ] && bad "B1b: a clean run printed on stdout, so a caller greping stdout cannot tell clean from dirty" || ok "B1b: a clean run is silent on stdout"

acc '- [ ] R-01 — archive, then assert absent'
run_decl
{ [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q '^UNDECLARED	R-02$'; } \
  && ok "B2: a testable criterion with no case exits 1 and names it" || bad "B2: rc=$RC out=[$OUT]"

acc '- [ ] R-01 — a\n- [ ] R-02 — b\n- [ ] R-09 — a case for a criterion the SPEC does not declare'
run_decl
{ [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q '^ORPHAN	R-09$'; } \
  && ok "B3: the REVERSE direction — a case naming an undeclared id is ORPHAN, exit 3" || bad "B3: rc=$RC out=[$OUT]"

acc '- [ ] R-01 — a\n- [ ] R-02 — b\n- [ ] R-03 — a case for a criterion marked no-test'
run_decl
{ [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q '^CONTRADICTION	R-03$'; } \
  && ok "B4: an exempt criterion given a case is CONTRADICTION, exit 3" || bad "B4: rc=$RC out=[$OUT]"

acc '- [ ] R-01 — a\n- [ ] R-02 — b'
run_decl
[ "$RC" -eq 0 ] && ok "B5: a (no-test:) criterion with NO case reconciles — the exemption is honoured" || bad "B5: rc=$RC out=[$OUT]"

# The 20-character reason floor is spec-coverage.sh's rule. A shorter reason is NOT an exemption
# there, so it must not become one here — two documents disagreeing about what exempts what is the
# whole failure this reconciliation exists to prevent.
spec '- [ ] R-01 — a\n- [ ] R-02 — doc (no-test: too short)'
acc '- [ ] R-01 — a'
run_decl
{ [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q '^UNDECLARED	R-02$'; } \
  && ok "B6: a (no-test:) reason under 20 chars does NOT exempt — the floor matches spec-coverage.sh" || bad "B6: rc=$RC out=[$OUT]"

spec '- a bullet with no identifier at all'
acc '- [ ] R-01 — a'
run_decl
{ [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q '^NO-IDS$'; } \
  && ok "B7: a SPEC declaring nothing is exit 3 NO-IDS — a reconciliation with no subject is not clean (rule 9)" || bad "B7: rc=$RC out=[$OUT]"

spec "$BASE_SPEC"
acc '- [ ] R-01 — a\n- [ ] R-02 — b'
OUT=$(bash "$DECL" --spec "$T/SPEC.md" --acceptance "$T/ACC.md" --predicates "$T/no-such-dir" 2>/dev/null); RC=$?
{ [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q '^NO-PREDICATE$'; } \
  && ok "B8: an explicit --predicates that resolves nothing is exit 3 NO-PREDICATE, never a silent fallback" || bad "B8: rc=$RC out=[$OUT]"

acc '- [ ] R-01 — a\n- [ ] R-09 — orphan'
run_decl
{ [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q '^ORPHAN' && printf '%s\n' "$OUT" | grep -q '^UNDECLARED'; } \
  && ok "B9: structural outranks undeclared — both reported, exit 3, so the reader is sent to the harder repair" || bad "B9: rc=$RC out=[$OUT]"

bash "$DECL" --nonsense >/dev/null 2>&1
[ $? -eq 2 ] && ok "B10: a bad invocation exits 2 — distinct from every measured state" || bad "B10: a bad invocation did not exit 2"
bash "$DECL" --spec "$T/does-not-exist.md" --acceptance "$T/ACC.md" >/dev/null 2>&1
[ $? -eq 2 ] && ok "B11: an unreadable --spec exits 2, not 0 and not 3" || bad "B11: an unreadable --spec did not exit 2"

# Section scoping and decoration both come from the SHARED predicate. B12/B13 exist because a
# private re-implementation would plausibly get either wrong, and the symptom would be a criterion
# silently absent from the subject set.
printf '## Notes\n\n- [ ] R-07 — outside any requirements section\n\n## Success criteria\n\n- [ ] R-01 — a\n' > "$T/SPEC.md"
acc '- [ ] R-01 — a'
run_decl
[ "$RC" -eq 0 ] && ok "B12: an id outside a recognised requirements heading is not declared" || bad "B12: rc=$RC out=[$OUT] — an out-of-section id leaked into the subject set"

spec '- [ ] **R-01** — a bold-wrapped identifier'
acc '- [ ] R-01 — a'
run_decl
[ "$RC" -eq 0 ] && ok "B13: a bold-wrapped id is read (ADR-0122) — decoration is not structure" || bad "B13: rc=$RC out=[$OUT]"

# B14 — the extraction is real, not a copy sitting beside the original. awk REJECTS a duplicate
# function definition, so a re-added local copy breaks the chain's own checker at load time; this
# asserts the move rather than trusting it.
n_shared=$(grep -c '^function item_text\|^function strip_sep' "$SPRED" 2>/dev/null || true)
n_local=$(grep -c '^function item_text\|^function strip_sep' "$COV" 2>/dev/null || true)
case "${n_shared:-}${n_local:-}" in *[!0-9]*) n_shared=0; n_local=0 ;; esac
{ [ "$n_shared" -eq 2 ] && [ "$n_local" -eq 0 ]; } \
  && ok "B14: item_text/strip_sep live ONCE in the shared predicate and not in spec-coverage.sh" \
  || bad "B14: shared=$n_shared local=$n_local — expected 2 and 0; two definitions cannot both load"

# ================================================================================================
# The adapter's declared-side pattern (D3). The declared side reads MARKDOWN, so it must recognise
# what the rest of the system recognises — measured against ADR-0048's own counterexamples.
# ================================================================================================
DECLRE=$(grep -m1 "^DECLRE=" "$ADAPTER" 2>/dev/null | sed "s/^DECLRE='//; s/'$//")
if [ -z "$DECLRE" ] || ! command -v jq >/dev/null 2>&1; then
  bad "B15: DECLRE or jq unavailable, so the declared-pattern assertions DID NOT RUN (declre=[$DECLRE])"
  bad "B16: same — did not run"
  bad "B17: same — did not run"
else
  extract() { printf '%s\n' "$1" | jq -Rr --arg re "$DECLRE" '[ match($re;"g")|.captures[1].string ]|.[]' 2>/dev/null | sort -u | tr '\n' ' '; }
  # The fixture carries the trap and NOTHING else: an earlier probe put a real `R-01` in the same
  # sentence, so a rejected ISSUE-R-013 and an accepted one produced identical output.
  got=$(extract 'the string ISSUE-R-013 is not an identifier here')
  [ -z "$got" ] && ok "B15: ISSUE-R-013 yields nothing — the right boundary rejects a third digit" || bad "B15: ISSUE-R-013 yielded [$got]"
  got=$(extract 'VAR-01 PR-01 ADR-0016 FOO_R-04')
  [ -z "$got" ] && ok "B16: VAR-01, PR-01, ADR-0016 and FOO_R-04 all yield nothing" || bad "B16: yielded [$got]"
  got=$(extract '- [ ] R-01 and R-02 side by side')
  [ "$got" = "R-01 R-02 " ] && ok "B17: two ADJACENT ids are both extracted — the consuming right anchor would drop the second" || bad "B17: adjacent ids yielded [$got], expected both"
fi

nid=$(grep -c "^IDRE=" "$ADAPTER" 2>/dev/null || true); ndl=$(grep -c "^DECLRE=" "$ADAPTER" 2>/dev/null || true)
case "${nid:-}${ndl:-}" in *[!0-9]*) nid=0; ndl=0 ;; esac
{ [ "$nid" -eq 1 ] && [ "$ndl" -eq 1 ]; } \
  && ok "B18: the test-name and declaration patterns are TWO named constants — collapsing them would apply one domain's looseness to the other" \
  || bad "B18: IDRE=$nid DECLRE=$ndl, expected exactly one of each"

# ================================================================================================
# brief-to-app/SKILL.md — structural pins. Present, not obeyed. See the header.
# ================================================================================================
[ -r "$SKILL" ] || bad "B19: brief-to-app/SKILL.md is not readable, so every structural pin below DID NOT RUN"
if [ -r "$SKILL" ]; then
  # Flattened AND undecorated (rule 3): the skill bolds several of these clauses, and a clause is
  # the same clause whether or not it is wrapped in asterisks or backticks.
  flat=$(tr '\n' ' ' < "$SKILL" | tr -d '*`' | tr -s ' ')
  case "$flat" in *'Write the user'?'s request to BRIEF.md exactly as given'*) ok "B19: the skill instructs that BRIEF.md is written verbatim" ;; *) bad "B19: the verbatim-brief instruction is missing or reworded" ;; esac
  case "$flat" in *'the block below and tell the user to paste it into the composer'*) ok "B20: the /goal contract is PRINTED, not invoked" ;; *) bad "B20: the skill no longer says the contract is printed — goal-loop carries disable-model-invocation and cannot be dispatched" ;; esac
  grep -q "Use the goal-loop skill" "$SKILL" && bad "B20b: the skill dispatches goal-loop, which disable-model-invocation blocks outright" || ok "B20b: the skill never dispatches goal-loop"
  grep -q '^\*\*Read first:\*\* BRIEF.md' "$SKILL" && ok "B21: the contract's Read first names BRIEF.md first — the durable channel against context rot" || bad "B21: Read first does not lead with BRIEF.md"
  case "$flat" in *'ACCEPTANCE-RESULT with fail=0 and missing=0'*) ok "B22: Stop when closes on the acceptance line, which is provable from the transcript" ;; *) bad "B22: the stop condition does not close on ACCEPTANCE-RESULT fail=0/missing=0" ;; esac
  grep -q '<!-- fence-contract: brief-to-app-acceptance-declare -->' "$SKILL" && ok "B23: the abort-capable fence declares a contract (ADR-0083)" || bad "B23: the fence carries no fence-contract declaration"
  grep -qE '\$[0-9]' "$SKILL" && bad "B24: the skill carries a \$<digit> token, which skill-argument substitution rewrites before the model sees it (ADR-0132)" || ok "B24: no \$<digit> token anywhere in the skill"
  fmflag=$(awk 'NR==1&&/^---/{inb=1;next} inb&&/^---/{exit} inb{print}' "$SKILL" | grep -c "disable-model-invocation" || true)
  case "${fmflag:-}" in ''|*[!0-9]*) fmflag=9 ;; esac
  [ "$fmflag" -eq 0 ] && ok "B25: the skill does NOT set disable-model-invocation — it dispatches design-brainstorm and macos-ux" || bad "B25: the frontmatter sets disable-model-invocation, which blocks its own Skill dispatches"
  grep -q "detect-macos.sh" "$SKILL" && ok "B26: the macOS branch calls detect-macos.sh rather than judging by eye (ADR-0093)" || bad "B26: the skill does not call detect-macos.sh"
  case "$flat" in *'Enforced: exactly one thing'*) ok "B27: the skill states which of its instructions is enforced and which is not (rule 16)" ;; *) bad "B27: the enforcement-versus-instruction statement is missing" ;; esac
fi

# ================================================================================================
# B28/B29 — the fence is EXECUTED, not merely named.
#
# WHY THIS BLOCK EXISTS, and it is a finding about an existing guard rather than a formality.
# fence-contract-coverage.test.sh's F4 accepts a contract as covered when a test file contains the
# literal `fence-contract: <id> -->`, on the reasoning that "a test cannot extract the fence without
# naming its id". That holds for a test that extracts and RUNS it. It does not hold for B23 above,
# which asserts only that the marker exists — and B23 satisfied F4 while the fence had never been
# executed once. A scan is satisfied by the whole population it searches, not by the part it meant
# (rule 18). These two assertions are what make the coverage real for this fence.
#
# The fence is driven under a FAKE HOME laid out like a deployed tree, because it resolves
# acceptance-declare.sh at $HOME/.claude/hooks and the harness declares no $HOME dependency. That
# also exercises the deployed-path resolution, which no other assertion here reaches.
extract_fence() {
  awk -v id="$1" '
    $0 ~ ("fence-contract: " id " -->") { f=1; next }
    f && /^```bash$/ { g=1; next }
    g && /^```$/ { exit }
    g { print }
  ' "$2"
}
FH="$T/fakehome"
mkdir -p "$FH/.claude/hooks" "$FH/.claude/skills/concept-to-code/scripts"
cp "$DECL" "$FH/.claude/hooks/" 2>/dev/null
cp "$PREDIR/plan-task-predicate.awk" "$PREDIR/spec-id-predicate.awk" "$FH/.claude/skills/concept-to-code/scripts/" 2>/dev/null
BODY=$(extract_fence "brief-to-app-acceptance-declare" "$SKILL")
if [ -z "$BODY" ]; then
  bad "B28: the fence body could not be extracted, so B28/B29 DID NOT RUN"
  bad "B29: same — did not run"
else
  mkdir -p "$T/proj"
  printf '## Success criteria\n\n- [ ] R-01 — a\n- [ ] R-02 — b\n' > "$T/proj/SPEC.md"
  printf '## Acceptance criteria\n\n- [ ] R-01 — a\n- [ ] R-02 — b\n' > "$T/proj/ACCEPTANCE.md"
  printf '%s\n' "$BODY" > "$T/fence.sh"
  OUT=$(HOME="$FH" PROJECT_ROOT="$T/proj" bash "$T/fence.sh" 2>&1); RC=$?
  { [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q 'ACCEPTANCE-DECLARE: reconciled'; } \
    && ok "B28: the fence RUNS and reports reconciled on agreeing documents" || bad "B28: rc=$RC out=[$OUT]"

  printf '## Acceptance criteria\n\n- [ ] R-01 — a\n' > "$T/proj/ACCEPTANCE.md"
  OUT=$(HOME="$FH" PROJECT_ROOT="$T/proj" bash "$T/fence.sh" 2>&1); RC=$?
  { [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q '^HALT:'; } \
    && ok "B29: the fence HALTS on a real mismatch — the lane cannot proceed past a disagreement" || bad "B29: rc=$RC out=[$OUT]"
fi

Z1_TOTAL=$((PASS + FAIL))
if [ "$Z1_TOTAL" -ge 24 ]; then ok "Z1: assertion-count floor ($Z1_TOTAL >= 24)"
else bad "Z1: only $Z1_TOTAL assertions ran, expected >= 24 — assertions were lost, not fixed"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
