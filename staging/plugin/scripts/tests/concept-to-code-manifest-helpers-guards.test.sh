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
# match.
if grep -qF 'exit 0 (VERIFIED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified true`' "$SKILL_MD"; then
  ok "D2: SKILL.md:547 site uses the absolute PATH RULE prefix"
else
  bad "D2: SKILL.md:547 site still uses a bare/relative manifest-set-flag.sh path"
fi

# D3 (static, genuine RED now): SKILL.md:549 site, absolute-prefixed. Expected now (RED): no
# match.
if grep -qF 'exit 1 (REFUTED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified false`' "$SKILL_MD"; then
  ok "D3: SKILL.md:549 site uses the absolute PATH RULE prefix"
else
  bad "D3: SKILL.md:549 site still uses a bare/relative manifest-set-flag.sh path"
fi

# D4 (static, genuine RED now): SKILL.md:1175 site, absolute-prefixed. Expected now (RED): no
# match.
if grep -qF '`[y]` → set `manifest.anonymize = true` (via `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`); proceed.' "$SKILL_MD"; then
  ok "D4: SKILL.md:1175 site uses the absolute PATH RULE prefix"
else
  bad "D4: SKILL.md:1175 site still uses a bare/relative manifest-set-flag.sh path"
fi

# D5 (static, genuine RED now): SKILL.md:1352 site, absolute-prefixed. Expected now (RED): no
# match.
if grep -qF '`[yes]` → `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`; proceed.' "$SKILL_MD"; then
  ok "D5: SKILL.md:1352 site uses the absolute PATH RULE prefix"
else
  bad "D5: SKILL.md:1352 site still uses a bare/relative manifest-set-flag.sh path"
fi

# =====================================================================================
# Section E -- Finding 5: transition-pair-count reconciliation (SKILL.md + manifest-transition.sh)
# =====================================================================================

# E1 (static, genuine RED now): corrected header (48 total — 28 standard + 6 express + 14
# hybrid). Expected now (RED): no match (today: 44/26/12).
if grep -qF 'Legal transition pairs (48 total — 28 standard + 6 express + 14 hybrid, including Gate 0d routing and direct-close shortcuts):' "$SKILL_MD"; then
  ok "E1: SKILL.md pair-count header states 48 total (28+6+14)"
else
  bad "E1: SKILL.md pair-count header does not yet state 48 total (28+6+14)"
fi

# E2 (static, genuine RED now): corrected helper description (48 pairs). Expected now (RED): no
# match (today: 51).
if grep -qF 'performs legal state transitions atomically (48 pairs).' "$SKILL_MD"; then
  ok "E2: SKILL.md helper description states (48 pairs)"
else
  bad "E2: SKILL.md helper description does not yet state (48 pairs)"
fi

# E3 (static, genuine RED now): manifest-transition.sh's corrected line-50 comment. Expected
# now (RED): no match (today: 16).
if grep -qF '# Build legal transition pairs into temp file (spec §3.3, 48 transitions)' "$TRN"; then
  ok "E3: manifest-transition.sh comment states 48 transitions"
else
  bad "E3: manifest-transition.sh comment does not yet state 48 transitions"
fi

# E4 (static, genuine RED now): both new Hybrid gate_h1c items present, no-space compact-list
# anchor (does not collide with the differently-formatted, spaced prose sentences at
# SKILL.md:1020/:1025). Expected now (RED): neither matches.
if grep -qF '`gate_h1b_brainstorm→gate_h1c_macos_ux`' "$SKILL_MD" && grep -qF '`gate_h1c_macos_ux→step_h2_plan`' "$SKILL_MD"; then
  ok "E4: SKILL.md Hybrid enumeration includes both new gate_h1c_macos_ux pairs"
else
  bad "E4: SKILL.md Hybrid enumeration is missing one or both new gate_h1c_macos_ux pairs"
fi

# E5 (static, genuine RED now): corrected Standard-bullet count. Expected now (RED): no match
# (today: 21).
if grep -qF 'Standard (preserved): all 28 existing pairs unchanged' "$SKILL_MD"; then
  ok "E5: SKILL.md Standard bullet states 28 existing pairs"
else
  bad "E5: SKILL.md Standard bullet does not yet state 28 existing pairs"
fi

# E6 (static, genuine RED now): Express bullet gains its missing gate_e3_verify→completed pair.
# Expected now (RED): no match (today: enumeration ends at step_e4_commit→completed).
if grep -qF '`step_e4_commit→completed`, `gate_e3_verify→completed`' "$SKILL_MD"; then
  ok "E6: SKILL.md Express bullet includes the gate_e3_verify→completed pair"
else
  bad "E6: SKILL.md Express bullet is missing the gate_e3_verify→completed pair"
fi

# E7 (dynamic, mechanical proof, already passing today, independent of this task's own
# SKILL.md edits): live recount of manifest-transition.sh's actual PAIRS block equals exactly
# 48 -- a permanent drift-detector for the script itself, not a RED/GREEN pair for this task.
actual_pairs="$(awk '/PAIRS="\$\(mktemp\)"/,/if ! grep -Fxq/' "$TRN" | grep -Ec '^ *echo "[a-z_0-9]+,[a-z_0-9]+" >')"
if [ "$actual_pairs" -eq 48 ]; then
  ok "E7: manifest-transition.sh's actual PAIRS block has exactly 48 pairs (live recount)"
else
  bad "E7: manifest-transition.sh's actual PAIRS block has $actual_pairs pairs, expected 48"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
