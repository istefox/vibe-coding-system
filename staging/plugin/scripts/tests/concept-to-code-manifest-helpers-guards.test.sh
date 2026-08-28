#!/bin/bash
# concept-to-code-manifest-helpers-guards test harness (ADR-0028) — Findings 1-5 from the
# concept-to-code audit (SPEC.md / issue #32). Five lettered sections:
#   Section A (Finding 1, 2 tests) — manifest-validate.sh invariant 9's gate_count guard must
#     genuinely fire (non-zero exit, error message) when hitl_gates has zero `- gate:` entries,
#     instead of silently passing because of the stale `|| echo 0` two-line-capture bug.
#   Section B (Finding 2, 4 tests) — manifest-set-artifact.sh / manifest-set-gate.sh must exit
#     4 (not 0) when their write fails (containing directory chmod 555'd), mirroring
#     manifest-set-flag.sh's already-shipped exit-4 contract.
#   Section C (Finding 3, 3 tests) — manifest-init.sh must escape `"`/`\` in topic_full_title so
#     the resulting manifest always parses with yaml.safe_load.
#   Section D (Finding 4, 5 tests) — SKILL.md's own PATH RULE (absolute
#     ~/.claude/skills/concept-to-code/scripts/ prefix) must be honored at all five named
#     manifest-set-flag.sh call sites.
#   Section E (Finding 5, 7 tests) — SKILL.md's transition-pair-count paragraph and
#     manifest-transition.sh's line-50 comment must agree with the actual, mechanically-counted
#     48 legal transition pairs.
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... — that is the deployed copy, out of scope.
# Bash 3.2 clean. Run: bash concept-to-code-manifest-helpers-guards.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
SKILL_DIR="$STAGING/plugin/skills/concept-to-code"
SKILL_MD="$SKILL_DIR/SKILL.md"
STEP5_REF="$SKILL_DIR/references/step5-implementation.md"
HITL_REF="$SKILL_DIR/references/hitl-gates.md"
INIT="$SKILL_DIR/scripts/manifest-init.sh"
VAL="$SKILL_DIR/scripts/manifest-validate.sh"
SETART="$SKILL_DIR/scripts/manifest-set-artifact.sh"
SETGATE="$SKILL_DIR/scripts/manifest-set-gate.sh"
TRN="$SKILL_DIR/scripts/manifest-transition.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# mk_empty_gates_fixture: manifest-init.sh, then strip every "  - gate:" block from the
# hitl_gates: list via awk (key line retained, resumes normal printing at the following blank
# line). Sets FIX_MANIFEST.
mk_empty_gates_fixture() {
  _slug="$1"
  _proj="$(mktemp -d "$TMP/proj-$_slug.XXXXXX")"
  _m="$(bash "$INIT" "$_slug" "Test $_slug" "$_proj")"
  awk '
    /^hitl_gates:$/ { print; ingates=1; next }
    ingates && /^  - gate:/ { next }
    ingates && /^    (label|status|approved_at|notes):/ { next }
    ingates && /^$/ { ingates=0; print; next }
    { print }
  ' "$_m" > "$_m.tmp" && mv "$_m.tmp" "$_m"
  FIX_MANIFEST="$_m"
}

# =====================================================================================
# Section A -- Finding 1: manifest-validate.sh invariant 9 count guard
# =====================================================================================

# A1 (dynamic, genuine RED now): zero hitl_gates entries must fail validation with invariant
# 9's own message. Expected now (RED): exit 0 (invariant 9 silently skipped).
mk_empty_gates_fixture "a1-empty-gates"
a1_err="$(bash "$VAL" "$FIX_MANIFEST" 2>&1 >/dev/null)"
a1_rc=$?
if [ "$a1_rc" -ne 0 ] && echo "$a1_err" | grep -qF 'hitl_gates must have at least'; then
  ok "A1: invariant 9 fails validation on zero hitl_gates entries"
else
  bad "A1: invariant 9 did not fail validation on zero hitl_gates entries (rc=$a1_rc)"
fi

# A2 (dynamic, non-regression companion, already passing): a fresh, unmodified fixture (default
# 4 gate lines) must keep validating clean. Expected now: already passing.
A2_PROJ="$(mktemp -d "$TMP/proj-a2-default.XXXXXX")"
A2_M="$(bash "$INIT" "a2-default" "Test a2-default" "$A2_PROJ")"
if bash "$VAL" "$A2_M" >/dev/null 2>&1; then
  ok "A2: unmodified default fixture (4 gate lines) still validates clean"
else
  bad "A2: unmodified default fixture (4 gate lines) failed validation unexpectedly"
fi

# assert_unwritable_exit4: chmod 555 the manifest's containing directory, run the script, assert
# exit 4, then always restore 755 before the next assertion (the outer trap cannot remove a 555
# subdirectory's contents).
assert_unwritable_exit4() {
  _label="$1"; _script="$2"; _manifest="$3"; shift 3
  _dir="$(dirname "$_manifest")"
  chmod 555 "$_dir"
  bash "$_script" "$_manifest" "$@" >/dev/null 2>"$TMP/unwritable.err"
  _rc=$?
  chmod 755 "$_dir"
  if [ "$_rc" -eq 4 ]; then
    ok "$_label: exits 4 against an unwritable manifest directory"
  else
    bad "$_label: exits $_rc against an unwritable manifest directory, expected 4"
  fi
}

# =====================================================================================
# Section B -- Finding 2: manifest-set-artifact.sh / manifest-set-gate.sh exit-4 write-failure
# contract
# =====================================================================================

# B1 (dynamic, genuine RED now): manifest-set-artifact.sh against an unwritable directory.
# Expected now (RED): exits 0.
B1_PROJ="$(mktemp -d "$TMP/proj-b1-artifact-fail.XXXXXX")"
B1_M="$(bash "$INIT" "b1-artifact-fail" "Test b1-artifact-fail" "$B1_PROJ")"
assert_unwritable_exit4 "B1" "$SETART" "$B1_M" spec "/tmp/SPEC.md"

# B2 (dynamic, non-regression companion, already passing): happy path still exits 0 and writes
# the target field. Expected now: already passing.
B2_PROJ="$(mktemp -d "$TMP/proj-b2-artifact-ok.XXXXXX")"
B2_M="$(bash "$INIT" "b2-artifact-ok" "Test b2-artifact-ok" "$B2_PROJ")"
if bash "$SETART" "$B2_M" spec "/tmp/SPEC.md" >/dev/null 2>&1 && grep -qF '  spec: "/tmp/SPEC.md"' "$B2_M"; then
  ok "B2: manifest-set-artifact.sh happy path exits 0 and writes the target field"
else
  bad "B2: manifest-set-artifact.sh happy path did not exit 0 / write the target field"
fi

# B3 (dynamic, genuine RED now): manifest-set-gate.sh against an unwritable directory.
# Expected now (RED): exits 0.
B3_PROJ="$(mktemp -d "$TMP/proj-b3-gate-fail.XXXXXX")"
B3_M="$(bash "$INIT" "b3-gate-fail" "Test b3-gate-fail" "$B3_PROJ")"
assert_unwritable_exit4 "B3" "$SETGATE" "$B3_M" 1 approved

# B4 (dynamic, non-regression companion, already passing): happy path still exits 0 and writes
# the target field. Expected now: already passing.
B4_PROJ="$(mktemp -d "$TMP/proj-b4-gate-ok.XXXXXX")"
B4_M="$(bash "$INIT" "b4-gate-ok" "Test b4-gate-ok" "$B4_PROJ")"
if bash "$SETGATE" "$B4_M" 1 approved >/dev/null 2>&1 && grep -qF '    status: "approved"' "$B4_M"; then
  ok "B4: manifest-set-gate.sh happy path exits 0 and writes the target field"
else
  bad "B4: manifest-set-gate.sh happy path did not exit 0 / write the target field"
fi

# yaml_roundtrip_ok: env-var-passed yaml.safe_load round-trip check for topic_full_title.
# Never inline-interpolate the expected value into the Python source (a title containing
# `"`/`\` breaks that the same way it breaks the underlying bug this finding is about).
yaml_roundtrip_ok() {
  _title="$1"; _manifest="$2"
  EXPECT_TITLE="$_title" MANIFEST_PATH="$_manifest" python3 -c "
import os, sys, yaml
d = yaml.safe_load(open(os.environ['MANIFEST_PATH']))
sys.exit(0 if d.get('topic_full_title') == os.environ['EXPECT_TITLE'] else 1)
" 2>"$TMP/yaml.err"
}

# =====================================================================================
# Section C -- Finding 3: manifest-init.sh topic_full_title YAML escaping
# =====================================================================================

# C1 (dynamic, genuine RED now): a title containing both `"` and `\` must produce a manifest
# whose topic_full_title round-trips through yaml.safe_load to the exact original string.
# Expected now (RED): yaml.safe_load raises ParserError, round-trip check exits non-zero.
C1_TITLE='Feature "Quoted" \Backslash\'
C1_PROJ="$(mktemp -d "$TMP/proj-c1-quoted.XXXXXX")"
C1_M="$(bash "$INIT" "c1-quoted" "$C1_TITLE" "$C1_PROJ")"
if yaml_roundtrip_ok "$C1_TITLE" "$C1_M"; then
  ok "C1: title with quote and backslash round-trips through yaml.safe_load"
else
  bad "C1: title with quote and backslash does not round-trip through yaml.safe_load"
fi

# C2 (static, genuine RED now): the old unescaped echo line is gone AND the new title_esc
# variable is present. Expected now (RED): old line still present, title_esc absent.
if ! grep -qF 'echo "topic_full_title: \"$title\"" >> "$T"' "$INIT" && grep -qF 'title_esc' "$INIT"; then
  ok "C2: manifest-init.sh uses escaped title_esc, old unescaped echo line is gone"
else
  bad "C2: manifest-init.sh still has the old unescaped echo line or is missing title_esc"
fi

# C3 (dynamic, non-regression companion, already passing): a title with no special characters
# keeps round-tripping correctly. Expected now: already passing.
C3_TITLE='Normal Title No Specials'
C3_PROJ="$(mktemp -d "$TMP/proj-c3-normal.XXXXXX")"
C3_M="$(bash "$INIT" "c3-normal" "$C3_TITLE" "$C3_PROJ")"
if yaml_roundtrip_ok "$C3_TITLE" "$C3_M"; then
  ok "C3: title with no special characters round-trips through yaml.safe_load"
else
  bad "C3: title with no special characters does not round-trip through yaml.safe_load"
fi

# =====================================================================================
# Section D -- Finding 4: SKILL.md PATH RULE violations (five manifest-set-flag.sh call sites)
# =====================================================================================

# D1 (static, genuine RED now): SKILL.md:120 site, absolute-prefixed. Expected now (RED): no
# match (bare `scripts/manifest-set-flag.sh` still present).
# Tail updated from "step 8b" to "step 8c" when Gate 0c was removed (ADR-0040). The assertion
# is unchanged: it still checks the absolute PATH RULE prefix at this call site.
if grep -qF 'in the manifest (via `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`); proceed to step 8c.' "$SKILL_MD"; then
  ok "D1: SKILL.md:120 site uses the absolute PATH RULE prefix"
else
  bad "D1: SKILL.md:120 site still uses a bare/relative manifest-set-flag.sh path"
fi

# D2 (static, genuine RED now): SKILL.md:547 site, absolute-prefixed. Expected now (RED): no
# match. VCS-047/ADR-0174: this site's content physically moved into
# references/step5-implementation.md with the rest of Step 5's body.
if grep -qF 'exit 0 (VERIFIED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified true`' "$STEP5_REF"; then
  ok "D2: SKILL.md:547 site uses the absolute PATH RULE prefix"
else
  bad "D2: SKILL.md:547 site still uses a bare/relative manifest-set-flag.sh path"
fi

# D3 (static, genuine RED now): SKILL.md:549 site, absolute-prefixed. Expected now (RED): no
# match. VCS-047/ADR-0174: same move as D2.
if grep -qF 'exit 1 (REFUTED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified false`' "$STEP5_REF"; then
  ok "D3: SKILL.md:549 site uses the absolute PATH RULE prefix"
else
  bad "D3: SKILL.md:549 site still uses a bare/relative manifest-set-flag.sh path"
fi

# D4 (static, genuine RED now): SKILL.md:1175 site, absolute-prefixed. Expected now (RED): no
# match.
if grep -qF '`[y]` → set `manifest.anonymize = true` (via `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`); proceed.' "$HITL_REF"; then
  ok "D4: SKILL.md:1175 site uses the absolute PATH RULE prefix"
else
  bad "D4: SKILL.md:1175 site still uses a bare/relative manifest-set-flag.sh path"
fi

# D5 (static, genuine RED now): SKILL.md:1352 site, absolute-prefixed. Expected now (RED): no
# match.
if grep -qF '`[yes]` → `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`; proceed.' "$HITL_REF"; then
  ok "D5: SKILL.md:1352 site uses the absolute PATH RULE prefix"
else
  bad "D5: SKILL.md:1352 site still uses a bare/relative manifest-set-flag.sh path"
fi

# =====================================================================================
# Section E -- Finding 5: transition-pair-count reconciliation (SKILL.md + manifest-transition.sh)
# =====================================================================================

# E1 (static, updated by issue #111 / ADR-0057, which legitimately added one new transition pair
# — Step 4.5's amber / "red -> reduce scope" route. Same reconciliation this section itself
# exists to enforce, applied again: 48 -> 49, 28 -> 29 standard. Then 49 -> 45, 29 -> 25 by
# issue #265 / ADR-0105, which deleted four unreachable gate_5_review_decision pairs).
if grep -qF 'Legal transition pairs (45 total — 25 standard + 6 express + 14 hybrid, including Gate 0d routing, Step 4.5 tracer-bullet routing, and direct-close shortcuts).' "$SKILL_MD"; then
  ok "E1: SKILL.md pair-count header states 45 total (25+6+14)"
else
  bad "E1: SKILL.md pair-count header does not state 45 total (25+6+14)"
fi

# E2 (static, updated by issue #111 / ADR-0057, same reconciliation as E1. Message corrected by
# issue #289 / ADR-0120 D-B: the needle already looked for 45 while the failure message still
# named 49 -- the needle was never wrong, only what it told a reader on failure).
# plant: E2 | plugin/skills/concept-to-code/SKILL.md | performs legal state transitions atomically (45 pairs). | performs legal state transitions atomically (46 pairs).
if grep -qF 'performs legal state transitions atomically (45 pairs).' "$SKILL_MD"; then
  ok "E2: SKILL.md helper description states (45 pairs)"
else
  bad "E2: SKILL.md helper description does not state (45 pairs)"
fi

# E3 (static, updated by issue #111 / ADR-0057, same reconciliation as E1. Message corrected by
# issue #289 / ADR-0120 D-B: the SUCCESS message named 49 while the grep looked for 45, so a green
# run printed the wrong number).
# plant: E3 | plugin/skills/concept-to-code/scripts/manifest-transition.sh | # Build legal transition pairs into temp file (spec §3.3, 45 transitions) | # Build legal transition pairs into temp file (spec §3.3, 46 transitions)
if grep -qF '# Build legal transition pairs into temp file (spec §3.3, 45 transitions)' "$TRN"; then
  ok "E3: manifest-transition.sh comment states 45 transitions"
else
  bad "E3: manifest-transition.sh comment does not state 45 transitions"
fi

# E4 (static, genuine RED now): both new Hybrid gate_h1c items present, no-space compact-list
# anchor (does not collide with the differently-formatted, spaced prose sentences at
# SKILL.md:1020/:1025). Expected now (RED): neither matches.
if grep -qF '`gate_h1b_brainstorm→gate_h1c_macos_ux`' "$SKILL_MD" && grep -qF '`gate_h1c_macos_ux→step_h2_plan`' "$SKILL_MD"; then
  ok "E4: SKILL.md Hybrid enumeration includes both new gate_h1c_macos_ux pairs"
else
  bad "E4: SKILL.md Hybrid enumeration is missing one or both new gate_h1c_macos_ux pairs"
fi

# E5 (static, issue #289 / ADR-0120 D-A / D5: the Standard bullet said "all 28 pre-existing pairs
# unchanged, plus 1 new pair for Step 4.5" = 29, while the header nine lines above and the script
# both say 25 -- ADR-0105 moved the header from 29 to 25 and left the bullet, so E5's old needle
# pinned the stale side of a self-contradiction as a frozen string (M7: "a passing test is holding
# the contradiction in place"). Only the count is reworded; the reasoning about WHY only the one
# Step 4.5 pair was needed (the ADR-0027 Gates-0c/0d lesson) sits unedited on the following lines
# and is not this needle's concern. EXPECTED RED until the coder's SKILL.md fix lands in this same
# batch -- that is the intended TDD sequence, not a defect in this assertion.)
# plant: E5 | plugin/skills/concept-to-code/SKILL.md | Standard (preserved): 25 pairs total | Standard (preserved): 29 pairs total
if grep -qF 'Standard (preserved): 25 pairs total — the 28 pre-existing pairs, minus the four `gate_5_review_decision` pairs removed by ADR-0105, plus 1 new pair for Step 4.5' "$SKILL_MD"; then
  ok "E5: SKILL.md Standard bullet states 25 pairs total, reconciled with the header and the script"
else
  bad "E5: SKILL.md Standard bullet does not yet state 25 pairs total (still self-contradicts the header) -- EXPECTED RED until the coder's SKILL.md fix lands"
fi

# E6 (static, genuine RED now): Express bullet gains its missing gate_e3_verify→completed pair.
# Expected now (RED): no match (today: enumeration ends at step_e4_commit→completed).
if grep -qF '`step_e4_commit→completed`, `gate_e3_verify→completed`' "$SKILL_MD"; then
  ok "E6: SKILL.md Express bullet includes the gate_e3_verify→completed pair"
else
  bad "E6: SKILL.md Express bullet is missing the gate_e3_verify→completed pair"
fi

# E7 (dynamic, mechanical proof): issue #289 / ADR-0120 D4 retires this assertion's own local
# recount into a call on the single shared checker, transition-pair-count.sh -- the derivation is
# NOT local to this file any more. ADR-0120 M3 measured three ad-hoc derivations (this was one:
# bounded to the block, but NOT deduplicated) disagreeing with each other on three of five
# mutation fixtures; the checker alone is block-bounded AND distinct, matching
# manifest-transition.sh's own `grep -Fxq` runtime semantics. 48 -> 49 by issue #111 / ADR-0057
# (Step 4.5's amber route), 49 -> 45 by issue #265 / ADR-0105 (four unreachable
# gate_5_review_decision pairs deleted).
# plant: E7 | plugin/scripts/tests/transition-pair-count.sh | STATS_TOTAL="$TOTAL_D" | STATS_TOTAL="999"
PTC="$(dirname "$0")/transition-pair-count.sh"
e7_stats="$(bash "$PTC" "$TRN" "$SKILL_MD" 2>&1 >/dev/null)"
e7_rc=$?
actual_pairs="$(printf '%s\n' "$e7_stats" | grep -o 'pairs=[0-9]*' | head -1 | cut -d= -f2)"
actual_pairs="${actual_pairs:-0}"
if [ "$e7_rc" -eq 0 ] && [ "$actual_pairs" -eq 45 ]; then
  ok "E7: transition-pair-count.sh (the shared derivation, not a local recount) reports 45 distinct pairs and zero findings"
else
  bad "E7: transition-pair-count.sh reports rc=$e7_rc pairs=$actual_pairs, expected rc=0 pairs=45"
fi

# =====================================================================================
# Section F -- issue #286 / ADR-0117: path-rule-check.sh, a derived guard for concept-to-code's
# own stated PATH RULE.
# DERIVED-GUARD PATTERN — instance 11 (ADR-0086). Derives: helper basenames from a scripts
# directory, occurrences inside one file. Waiver: a same-line path-rule-exempt HTML comment,
# which the scanner must TRUNCATE at.
#
# Disclosures (Task 8, ADR-0117 §4 Negative/Neutral) -- what a green run here does and does not mean:
#
# - RESIDUAL BLIND SPOT: the verb set is a judgement encoded as data. A call site written with an
#   invocation verb outside that set is invisible to the checker -- e.g. a helper named only in
#   prose beside `<helper>.sh` with no recognised verb attached. Read a green run as "no recognised
#   invocation shape is bare", never as "no bare call site exists".
# - COMMENT-LINE EXEMPTION BREADTH: any line whose first non-blank character is `#` is skipped
#   entirely, which includes markdown headings, not only fenced code. Harmless today because no
#   heading names a helper; a hole the day one does.
# - POPULATION BOUNDARY: this checker reads concept-to-code/SKILL.md only, by design, not by
#   oversight -- it takes the file as an argument precisely so a later issue can point it at one of
#   the others without editing it. autopilot-build (9 bare of 15), project-conductor (8 of 8),
#   autopilot (5 of 7), commit (1) and deep-refactor (1) sit outside it. A green run here
#   says nothing about any of them.
# - DERIVED-GUARD NUMBERING, reported not fixed: instance 10 is claimed twice, once by
#   conductor-entry-failure-split.test.sh and once in prose by
#   concept-to-code-bsd-autopilot-gates.test.sh; instance 7 (ADR-0087) carries no marker at all.
#   This section is instance 11 regardless of how that collision is eventually resolved.
# - DURABLE RECORD: five of the ten converted call sites were created by ADR-0099 (issue #238)
#   three weeks after ADR-0028 counted the population -- that gap, not the one call site ADR-0028
#   deferred, is why the SPEC's instruction was to re-derive the population rather than confirm the
#   old count. The population has since grown again: 8 helpers / 63 occurrences at the time this
#   section was written, up from the SPEC's own snapshot of 7/62 (manifest-entry-state.sh,
#   ADR-0109, entered already in compliant form) -- which is why every count guard below is a
#   `>=` floor and never an exact number.
# =====================================================================================

PRC="$(dirname "$0")/path-rule-check.sh"

# F1 (static/dynamic): the checker exists and is invocable by bash -- not just present, actually
# runnable, returning one of its own contract's exit codes rather than a bash execution error.
if [ -f "$PRC" ] && [ -r "$PRC" ]; then
  bash "$PRC" "$SKILL_MD" "$SKILL_DIR/scripts" >/dev/null 2>&1
  f1_rc=$?
  case "$f1_rc" in
    0|1|2|3) ok "F1: path-rule-check.sh exists and is invocable by bash (rc=$f1_rc)" ;;
    *) bad "F1: path-rule-check.sh exists but exited unexpectedly (rc=$f1_rc)" ;;
  esac
else
  bad "F1: path-rule-check.sh is missing or unreadable at $PRC"
fi
# plant: F1 | plugin/scripts/tests/path-rule-check.sh | if [ "$#" -ne 2 ]; then | exit 42; if [ "$#" -ne 2 ]; then

# F2 (dynamic, EXPECTED RED until Task 4): the real SKILL.md must be clean under
# path-rule-check.sh -- exit 0, empty stdout. Task 3 converts the ten call sites and Task 4
# declares the six prose occurrences; until then this stays red with findings=16, and that is
# this task's declared deliverable (ADR-0101 case 1), not a defect to fix here.
#
# VCS-047/ADR-0174 + VCS-048/ADR-0175: path-rule-check.sh only scans the ONE file passed as its
# first argument, and Step 5's and ## 5. HITL gates' content now live in
# references/step5-implementation.md and references/hitl-gates.md, not in $SKILL_MD. Scan all
# three, separately (the checker takes one file per invocation, not a list) — a violation in any
# is a real F2 finding.
f2_out="$(bash "$PRC" "$SKILL_MD" "$SKILL_DIR/scripts" 2>/dev/null)"
f2_rc=$?
f2_ref_out="$(bash "$PRC" "$SKILL_DIR/references/step5-implementation.md" "$SKILL_DIR/scripts" 2>/dev/null)"
f2_ref_rc=$?
f2_hitl_out="$(bash "$PRC" "$SKILL_DIR/references/hitl-gates.md" "$SKILL_DIR/scripts" 2>/dev/null)"
f2_hitl_rc=$?
if [ "$f2_rc" -eq 0 ] && [ -z "$f2_out" ] && [ "$f2_ref_rc" -eq 0 ] && [ -z "$f2_ref_out" ] \
  && [ "$f2_hitl_rc" -eq 0 ] && [ -z "$f2_hitl_out" ]; then
  ok "F2: the real SKILL.md, references/step5-implementation.md and references/hitl-gates.md are clean under path-rule-check.sh (exit 0, empty stdout)"
else
  bad "F2: SKILL.md and/or references/step5-implementation.md and/or references/hitl-gates.md are not yet clean under path-rule-check.sh (rc=$f2_rc, ref_rc=$f2_ref_rc, hitl_rc=$f2_hitl_rc) -- EXPECTED RED until Task 4"
fi
# plant: F2 | plugin/skills/concept-to-code/references/step5-implementation.md | hook_verified = false` via `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh` and take the Agent-tool fallback. | hook_verified = false` via `manifest-set-flag.sh` and take the Agent-tool fallback.

# F4/F5 (dynamic, count guards on the DENOMINATOR, not the matches -- ADR-0085): read the
# stderr summary from a run against the real corpus. An empty derivation must not silently
# read as full coverage.
#
# VCS-048/ADR-0175: occurrences now split across three files (SKILL.md, step5-implementation.md,
# hitl-gates.md) since path-rule-check.sh scans one file per invocation -- sum across all three,
# same reasoning as F2's split check above. f_helpers is a per-directory derivation (constant
# across invocations), read once from the SKILL_MD run.
f45_err="$(bash "$PRC" "$SKILL_MD" "$SKILL_DIR/scripts" 2>&1 >/dev/null)"
f_helpers="$(printf '%s\n' "$f45_err" | grep -o 'helpers=[0-9]*' | head -1 | cut -d= -f2)"
f_occ_skill="$(printf '%s\n' "$f45_err" | grep -o 'occurrences=[0-9]*' | head -1 | cut -d= -f2)"
f45_step5_err="$(bash "$PRC" "$SKILL_DIR/references/step5-implementation.md" "$SKILL_DIR/scripts" 2>&1 >/dev/null)"
f_occ_step5="$(printf '%s\n' "$f45_step5_err" | grep -o 'occurrences=[0-9]*' | head -1 | cut -d= -f2)"
f45_hitl_err="$(bash "$PRC" "$SKILL_DIR/references/hitl-gates.md" "$SKILL_DIR/scripts" 2>&1 >/dev/null)"
f_occ_hitl="$(printf '%s\n' "$f45_hitl_err" | grep -o 'occurrences=[0-9]*' | head -1 | cut -d= -f2)"
f_occurrences="$(( ${f_occ_skill:-0} + ${f_occ_step5:-0} + ${f_occ_hitl:-0} ))"

if [ -n "$f_helpers" ] && [ "$f_helpers" -ge 7 ]; then
  ok "F4: helper derivation is >= 7 (got $f_helpers)"
else
  bad "F4: helper derivation is '$f_helpers', expected >= 7"
fi
# plant: F4 | plugin/scripts/tests/path-rule-check.sh | for f in "$HELPER_DIR"/manifest-*.sh; do | for f in "$HELPER_DIR"/manifest-ZZZ-*.sh; do

if [ -n "$f_occurrences" ] && [ "$f_occurrences" -ge 50 ]; then
  ok "F5: occurrence count is >= 50 (got $f_occurrences)"
else
  bad "F5: occurrence count is '$f_occurrences', expected >= 50"
fi
# plant: F5 | plugin/scripts/tests/path-rule-check.sh | p = index(search, bn) | p = 0

# Shared minimal helper dir for the fixture-based assertions below (F3, F6-F9, F12). Only one
# derived helper basename is needed to exercise the predicate in isolation from the real corpus.
PRC_HELPERS="$TMP/prc-helpers"
mkdir -p "$PRC_HELPERS"
: > "$PRC_HELPERS/manifest-foo.sh"

# F3 (dynamic): a fixture with one planted bare mention (an invocation verb, no marker) must
# exit 1 and the finding line must name the planted line specifically.
F3_FIX="$TMP/f3-fixture.md"
cat > "$F3_FIX" <<'EOF'
# F3 fixture -- one planted bare call site, no marker
5. Invoke `manifest-foo.sh <manifest-path>` directly here. F3_PLANT_TOKEN_UNIQUE
EOF
f3_out="$(bash "$PRC" "$F3_FIX" "$PRC_HELPERS" 2>/dev/null)"
f3_rc=$?
if [ "$f3_rc" -eq 1 ] && printf '%s\n' "$f3_out" | grep -qF 'F3_PLANT_TOKEN_UNIQUE'; then
  ok "F3: fixture with one planted bare mention exits 1 and names the planted line"
else
  bad "F3: fixture with one planted bare mention did not exit 1 naming the planted line (rc=$f3_rc)"
fi
# plant: F3 | plugin/scripts/tests/path-rule-check.sh | is_finding = 0 if (ends_with(pre, "scripts/")) is_finding = 1 if (before_char != "`") is_finding = 1 if (after_char != "`") is_finding = 1 if (before_char == "`") { word_text = substr(pre, 1, length(pre) - 1) sub(/[ \t]+$/, "", word_text) w = normalise_word(last_field(word_text)) if (w in verbset) is_finding = 1 } | is_finding = 0

# F6 (dynamic, count guard on the waiver population -- ADR-0084 §S2): a fixture with one
# legitimate waiver must report waived >= 1, or F7/F8/F9 below would be vacuous.
F6_FIX="$TMP/f6-fixture.md"
cat > "$F6_FIX" <<'EOF'
# F6 fixture -- a legitimate waiver
Call it via `manifest-foo.sh <manifest-path>` when needed. <!-- path-rule-exempt: prose demonstrating what a real call would look like, not an instruction -->
EOF
f6_err="$(bash "$PRC" "$F6_FIX" "$PRC_HELPERS" 2>&1 >/dev/null)"
f6_waived="$(printf '%s\n' "$f6_err" | grep -o 'waived=[0-9]*' | head -1 | cut -d= -f2)"
if [ -n "$f6_waived" ] && [ "$f6_waived" -ge 1 ]; then
  ok "F6: count guard waived >= 1 on a fixture with a legitimate waiver (got $f6_waived)"
else
  bad "F6: waived count is '$f6_waived', expected >= 1"
fi
# plant: F6 | plugin/scripts/tests/path-rule-check.sh | marker_pos = index(line, "<!-- path-rule-exempt:") | marker_pos = index(line, "<!-- path-rule-exemptXXX:")

# F7 (reverse direction -- ADR-0081 §ZA4: a stale waiver reads exactly like clean coverage): a
# marked line whose only occurrence is compliant/prose (nothing invocation-shaped to waive) must
# report STALE-WAIVER and exit 1.
F7_FIX="$TMP/f7-fixture.md"
cat > "$F7_FIX" <<'EOF'
# F7 fixture -- marker with no invocation-shaped occurrence to waive
Documentation references `manifest-foo.sh` without any verb nearby. <!-- path-rule-exempt: kept only to test that a marker with an existing but non-invocation occurrence still stale-waivers -->
EOF
f7_out="$(bash "$PRC" "$F7_FIX" "$PRC_HELPERS" 2>/dev/null)"
f7_rc=$?
if [ "$f7_rc" -eq 1 ] && printf '%s\n' "$f7_out" | grep -q 'STALE-WAIVER'; then
  ok "F7: a marked line with no invocation-shaped occurrence reports STALE-WAIVER and exits 1"
else
  bad "F7: marked line with no invocation-shaped occurrence did not report STALE-WAIVER (rc=$f7_rc)"
fi
# plant: F7 | plugin/scripts/tests/path-rule-check.sh | if (line_waived_count == 0) { | if (line_waived_count == 999) {

# F8 (rule 12): a reason that names a helper, on a line with no real occurrence before the
# marker, must not self-waive -- the truncation at the marker (ADR-0082) means the reason's own
# mention of the helper contributes ZERO to the occurrence count.
F8_FIX="$TMP/f8-fixture.md"
cat > "$F8_FIX" <<'EOF'
# F8 fixture -- reason names a helper, no real occurrence before the marker
This sentence names no helper at all before the marker. <!-- path-rule-exempt: the word manifest-foo.sh only appears in this explanatory reason text, never as a real occurrence -->
EOF
f8_err="$(bash "$PRC" "$F8_FIX" "$PRC_HELPERS" 2>&1 >/dev/null)"
f8_occ="$(printf '%s\n' "$f8_err" | grep -o 'occurrences=[0-9]*' | head -1 | cut -d= -f2)"
if [ -n "$f8_occ" ] && [ "$f8_occ" -eq 0 ]; then
  ok "F8: a reason naming a helper does not self-waive -- the marker's own text contributes zero occurrences"
else
  bad "F8: occurrences='$f8_occ', expected 0 -- the reason's mention of the helper leaked into the scan"
fi
# plant: F8 | plugin/scripts/tests/path-rule-check.sh | scan_text = substr(line, 1, marker_pos - 1) | scan_text = line

# F9 (dynamic): a genuine waived occurrence with a reason under 40 characters must report
# SHORT-REASON and exit 1.
F9_FIX="$TMP/f9-fixture.md"
cat > "$F9_FIX" <<'EOF'
# F9 fixture -- a genuine waived occurrence with a too-short reason
Please run `manifest-foo.sh <manifest-path>` today. <!-- path-rule-exempt: too short -->
EOF
f9_out="$(bash "$PRC" "$F9_FIX" "$PRC_HELPERS" 2>/dev/null)"
f9_rc=$?
if [ "$f9_rc" -eq 1 ] && printf '%s\n' "$f9_out" | grep -q 'SHORT-REASON'; then
  ok "F9: a reason under 40 characters reports SHORT-REASON and exits 1"
else
  bad "F9: reason under 40 characters did not report SHORT-REASON (rc=$f9_rc)"
fi
# plant: F9 | plugin/scripts/tests/path-rule-check.sh | if (length(rl) < 40) { | if (length(rl) < 0) {

# F10 (dynamic): an empty helper directory (zero derived basenames) must exit 3 and the message
# must state that the check did not run -- distinct from exit 0, which would read as a clean
# file (ADR-0085).
F10_EMPTY="$TMP/f10-empty-helpers"
mkdir -p "$F10_EMPTY"
f10_all="$(bash "$PRC" "$SKILL_MD" "$F10_EMPTY" 2>&1)"
f10_rc=$?
if [ "$f10_rc" -eq 3 ] && printf '%s\n' "$f10_all" | grep -qi 'did not run'; then
  ok "F10: an empty helper directory exits 3 and states the check did not run"
else
  bad "F10: empty helper directory did not exit 3 with a DID NOT RUN message (rc=$f10_rc)"
fi
# plant: F10 | plugin/scripts/tests/path-rule-check.sh | if [ "$HCOUNT" -eq 0 ]; then | if [ "$HCOUNT" -eq 999 ]; then

# F11 (dynamic): bad invocation (no arguments) must exit 2.
bash "$PRC" >/dev/null 2>&1
f11_rc=$?
if [ "$f11_rc" -eq 2 ]; then
  ok "F11: invoking path-rule-check.sh with no arguments exits 2"
else
  bad "F11: invoking path-rule-check.sh with no arguments exited $f11_rc, expected 2"
fi
# plant: F11 | plugin/scripts/tests/path-rule-check.sh | echo "path-rule-check: usage: path-rule-check.sh <skill-md> <helper-scripts-dir>" >&2 echo "path-rule-check: helpers=0 occurrences=0 compliant=0 waived=0 findings=0" >&2 exit 2 | echo "path-rule-check: usage: path-rule-check.sh <skill-md> <helper-scripts-dir>" >&2; echo "path-rule-check: helpers=0 occurrences=0 compliant=0 waived=0 findings=0" >&2; exit 55

# F12 (static + dynamic): path-rule-check.sh is a CHECKER, not a REPORTER -- its source must
# contain no `CLEAN` sentinel EMISSION (weakening-scan.sh's idiom is `echo "CLEAN"`, a
# double-quoted literal; ADR-0048's "two adjacent gates, two opposite caller idioms" already
# confused once). The needle targets the emission shape, not the word: the header prose above
# legitimately explains "prints no `CLEAN` sentinel" with backticks, and a bare substring match
# on CLEAN would count that explanation as a violation (rule 12). A fully compliant fixture must
# exit 0 with EMPTY stdout, never a printed sentinel.
F12_CLEAN="$TMP/f12-clean.md"
cat > "$F12_CLEAN" <<'EOF'
# F12 fixture -- fully compliant, no findings
See `manifest-foo.sh` for background. Absolute call:
~/.claude/skills/concept-to-code/scripts/manifest-foo.sh <manifest-path>
EOF
f12_out="$(bash "$PRC" "$F12_CLEAN" "$PRC_HELPERS" 2>/dev/null)"
f12_rc=$?
if ! grep -qF '"CLEAN"' "$PRC" && [ "$f12_rc" -eq 0 ] && [ -z "$f12_out" ]; then
  ok "F12: path-rule-check.sh is a checker (no CLEAN sentinel emission) and exits 0 with empty stdout on a clean fixture"
else
  bad "F12: checker-vs-reporter property violated (CLEAN sentinel emission present, or non-empty/non-zero on a clean fixture)"
fi
# plant: F12 | plugin/scripts/tests/path-rule-check.sh | exit 0 | echo "CLEAN"; exit 0


# F13 (static): the PATH RULE blockquote's new paragraph (Task 5) is present in the real
# SKILL.md. Matched against a FLATTENED, UNDECORATED, case-insensitive copy of the file --
# leading `>` blockquote markers stripped per line, line breaks collapsed to single spaces,
# backticks and asterisks stripped -- so this assertion does not depend on where the prose
# wraps, how a word is decorated, or whether the paragraph sits inside a blockquote (ADR-0073
# line wrap, ADR-0076 comment marker, ADR-0080 backticks, ADR-0082 one-line marker,
# ADR-0098 sentence-opening capitalisation, ADR-0101, and the blockquote-marker case found
# while this section was written: without stripping `>`, a needle phrase wrapped across two
# `> ` lines read as "...prefix > and no path prefix..." and the assertion depended on the
# paragraph staying on one physical line -- eight instances and counting). The needle is a
# phrase distinctive to the paragraph's own content (a bare-code-span helper mention carries
# neither arguments nor a path prefix) rather than to prose describing the rule in general --
# "path prefix" alone already occurs elsewhere in SKILL.md (Gate 0's unrelated
# `express|hybrid|standard` title prefix), so the needle requires both halves together
# (rule 12).
f13_flat="$(sed -E 's/^>[[:space:]]*//' "$SKILL_MD" | tr '\n' ' ' | tr -d '`*' | tr -s ' ' | tr '[:upper:]' '[:lower:]')"
if printf '%s' "$f13_flat" | grep -qF 'no arguments and no path prefix'; then
  ok "F13: SKILL.md's PATH RULE block carries the new paragraph (flattened, undecorated match)"
else
  bad "F13: PATH RULE block does not yet carry the new paragraph -- EXPECTED RED until Task 5's SKILL.md half lands"
fi
# plant: F13 | plugin/skills/concept-to-code/SKILL.md | no arguments and no path prefix | no arguments and no path suffix

# =====================================================================================
# Section G -- gate-audit-trail-check: manifest-transition.sh must refuse a gate-advancing
# transition whose hitl_gates entry is not "approved", instead of relying only on Invariant 9's
# entry COUNT (which manifest-init.sh's unconditional five-slot template satisfies by
# construction, on every chain_path, whether or not any gate was ever approved).
# =====================================================================================

mk_gate_fixture() {
  _slug="$1"
  _proj="$(mktemp -d "$TMP/proj-$_slug.XXXXXX")"
  _m="$(bash "$INIT" "$_slug" "Test $_slug" "$_proj")"
  sed -i.bak 's/^chain_path: null$/chain_path: "standard"/' "$_m"
  printf '%s' "$_m"
}

# G1 (dynamic, genuine RED before this fix): a fresh manifest, gate 1 left at the manifest-init.sh
# default ("pending"), must be refused when advancing gate_1_spec_review -> step_2_architecture.
# plant: G1 | plugin/skills/concept-to-code/scripts/manifest-transition.sh | "gate_1_spec_review,step_2_architecture") _gate_num=1 ;; | "gate_1_spec_review,step_2_architecture") _gate_num=0 ;;
G1_M="$(mk_gate_fixture g1-unapproved)"
bash "$TRN" "$G1_M" gate_0d_scaffolding >/dev/null 2>&1
bash "$TRN" "$G1_M" step_1_interview >/dev/null 2>&1
bash "$TRN" "$G1_M" gate_1_spec_review >/dev/null 2>&1
g1_out="$(bash "$TRN" "$G1_M" step_2_architecture 2>&1)"; g1_rc=$?
if [ "$g1_rc" -ne 0 ] && printf '%s' "$g1_out" | grep -qF 'gate 1 is not approved'; then
  ok "G1: gate_1_spec_review -> step_2_architecture is refused while gate 1 is still 'pending'"
else
  bad "G1: expected refusal citing 'gate 1 is not approved', got rc=$g1_rc out='$g1_out'"
fi

# G2 (dynamic): the same transition succeeds once gate 1 is recorded as approved via
# manifest-set-gate.sh -- the sanctioned writer, not a raw sed edit.
G2_M="$(mk_gate_fixture g2-approved)"
bash "$TRN" "$G2_M" gate_0d_scaffolding >/dev/null 2>&1
bash "$TRN" "$G2_M" step_1_interview >/dev/null 2>&1
bash "$TRN" "$G2_M" gate_1_spec_review >/dev/null 2>&1
bash "$SETGATE" "$G2_M" 1 approved >/dev/null 2>&1
g2_rc=0
bash "$TRN" "$G2_M" step_2_architecture >/dev/null 2>&1 || g2_rc=$?
if [ "$g2_rc" -eq 0 ] && [ "$(grep '^current_step:' "$G2_M" | sed 's/^current_step: *//;s/"//g')" = "step_2_architecture" ]; then
  ok "G2: gate_1_spec_review -> step_2_architecture succeeds once gate 1 is approved"
else
  bad "G2: expected success once gate 1 is approved, got rc=$g2_rc"
fi

# G3 (dynamic): the REJECT direction (gate says no, redo the interview) must NOT require the
# gate to be approved -- rule 8's "run the check backwards": a guard that only ever blocks the
# forward path but is silently inert on every other edge would be indistinguishable from one that
# never checked direction at all.
G3_M="$(mk_gate_fixture g3-reject-path)"
bash "$TRN" "$G3_M" gate_0d_scaffolding >/dev/null 2>&1
bash "$TRN" "$G3_M" step_1_interview >/dev/null 2>&1
bash "$TRN" "$G3_M" gate_1_spec_review >/dev/null 2>&1
g3_rc=0
bash "$TRN" "$G3_M" step_1_interview >/dev/null 2>&1 || g3_rc=$?
if [ "$g3_rc" -eq 0 ]; then
  ok "G3: gate_1_spec_review -> step_1_interview (reject path) is unaffected by gate 1's 'pending' status"
else
  bad "G3: reject path was blocked (rc=$g3_rc) -- the gate-approval check must not cover the backward edge"
fi

# G4 (dynamic): Gate 4 (implementation_mode) has no current_step of its own (ADR-0099) -- it sits
# inline between ready_for_implementation and step_5_implementation. The check is keyed by the
# (from,to) PAIR for exactly this reason; G4 proves that keying actually reaches an inline gate,
# not only the gates that own a dedicated current_step.
G4_M="$(mk_gate_fixture g4-inline-gate)"
for s in gate_0d_scaffolding step_1_interview gate_1_spec_review; do bash "$TRN" "$G4_M" "$s" >/dev/null 2>&1; done
bash "$SETGATE" "$G4_M" 1 approved >/dev/null 2>&1
bash "$TRN" "$G4_M" step_2_architecture >/dev/null 2>&1
bash "$TRN" "$G4_M" gate_2_architecture_review >/dev/null 2>&1
bash "$SETGATE" "$G4_M" 2 approved >/dev/null 2>&1
bash "$TRN" "$G4_M" step_3_project_memory >/dev/null 2>&1
bash "$TRN" "$G4_M" gate_3_project_memory_review >/dev/null 2>&1
bash "$SETGATE" "$G4_M" 3 approved >/dev/null 2>&1
bash "$TRN" "$G4_M" step_4_session_boundary >/dev/null 2>&1
bash "$TRN" "$G4_M" ready_for_implementation >/dev/null 2>&1
g4_out="$(bash "$TRN" "$G4_M" step_5_implementation 2>&1)"; g4_rc=$?
if [ "$g4_rc" -ne 0 ] && printf '%s' "$g4_out" | grep -qF 'gate 4 is not approved'; then
  ok "G4: the inline Gate 4 (no current_step of its own) is still enforced on ready_for_implementation -> step_5_implementation"
else
  bad "G4: expected refusal citing 'gate 4 is not approved' on the inline gate, got rc=$g4_rc out='$g4_out'"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
