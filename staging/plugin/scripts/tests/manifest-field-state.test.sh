#!/bin/bash
# manifest-field-state.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash manifest-field-state.test.sh
#
# Covers issue #195 (ADR-0076): the one place that answers "is this field present on this manifest,
# and if not, what era is the manifest from".
#
# WHAT IT IS GUARDING. Fields reach manifest-init.sh as ADDITIVE — no schema bump, no migration —
# so a manifest written before a field simply does not carry it. Then a checker reads the field
# with `m.get(...)` and cannot tell ABSENT from null from UNPARSEABLE, because all three arrive as
# None or as an empty string with the traceback in /dev/null. Issue #123 is what that cost: a whole
# roadmap aborted on two long-completed chains that merely predate the field, reported as
# "corrupted or hand-edited".
#
# THE DESIGN UNDER TEST IS THE SEPARATION, not the parsing. The helper reports a FACT; both callers
# apply their own policy to it, and their policies for the SAME state are opposite and both correct.
# Section P asserts that asymmetry survives, because a later reader "reconciling" the two would
# reintroduce #123 on one side or break autopilot-build on the other.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
HELPER="$STAGING/plugin/skills/concept-to-code/scripts/manifest-field-state.sh"
NA_SKILL="$STAGING/plugin/skills/nightly-autopilot/SKILL.md"
AB_SKILL="$STAGING/plugin/skills/autopilot-build/SKILL.md"
SYNC="$STAGING/sync-to-claude.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

mk() { printf '%b' "$2" > "$TMP/$1.yml"; }
mk valid     'topic: "x"\ncurrent_step: "completed"\nhook_verified: false\n'
mk truthy    'topic: "x"\nhook_verified: true\n'
mk olddone   'topic: "x"\ncurrent_step: "completed"\n'
mk oldflight 'topic: "x"\ncurrent_step: "step_5_implementation"\n'
mk nostep    'topic: "x"\n'
mk garbage   'topic: "x"\ncurrent_step: "completed"\nhook_verified: maybe\n'
mk quoted    'topic: "x"\nhook_verified: "true"\n'
mk nullval   'topic: "x"\nhook_verified:\n'
mk broken    'topic: "x\n  bad: [unclosed\n'
mk scalar    'just a string, not a mapping\n'

st() { bash "$HELPER" "$TMP/$1.yml" "${2:-hook_verified}" 2>/dev/null; }

# =====================================================================================
# S. The states. Each is a different operator action, which is the whole reason they are separate.
[ "$(st valid)"     = "PRESENT|False" ]      && ok "S1: a present boolean reads PRESENT|False"      || bad "S1: got '$(st valid)'"
[ "$(st truthy)"    = "PRESENT|True" ]       && ok "S2: a present true reads PRESENT|True"          || bad "S2: got '$(st truthy)'"
[ "$(st olddone)"   = "ABSENT|completed" ]   && ok "S3: absent carries the manifest's current_step" || bad "S3: got '$(st olddone)'"
[ "$(st oldflight)" = "ABSENT|step_5_implementation" ] \
  && ok "S4: absent on an in-flight manifest carries the real step, not a placeholder" || bad "S4: got '$(st oldflight)'"
[ "$(st nostep)"    = "ABSENT|" ]            && ok "S5: absent with no current_step reads ABSENT| (empty, not None)" || bad "S5: got '$(st nostep)'"
[ "$(st garbage)"   = "PRESENT|maybe" ]      && ok "S6: an invalid value is PRESENT, not absent"    || bad "S6: got '$(st garbage)'"
[ "$(st broken)"    = "UNREADABLE" ]         && ok "S7: unparseable YAML reads UNREADABLE"          || bad "S7: got '$(st broken)'"
[ "$(st scalar)"    = "UNREADABLE" ]         && ok "S8: a non-mapping document reads UNREADABLE"    || bad "S8: got '$(st scalar)'"

# S9: `ABSENT|` for a missing current_step must NOT be the string "None". The old one-liner printed
# str(None) and the caller then matched a step literally named None — the same conflation one level
# down, and the exact bug class this helper exists to end.
st nostep | grep -q 'None' && bad "S9: a missing current_step still leaks the literal None" \
                           || ok "S9: a missing current_step is empty, never the literal None"

# S10: a YAML null VALUE is PRESENT, not ABSENT. Someone wrote the key; that is a different fact
# from nobody having written it, and it is the distinction `m.get()` destroyed.
case "$(st nullval)" in
  PRESENT\|*) ok "S10: an explicit null value is PRESENT (someone wrote the key)" ;;
  *) bad "S10: an explicit null was reported as '$(st nullval)' — the #123 conflation" ;;
esac

# S11: a quoted "true" must not read as the boolean. It stays strict, exactly as the one-liners
# this replaces were strict, so a caller asserting True/False still rejects it.
[ "$(st quoted)" = "PRESENT|true" ] && ok "S11: a quoted \"true\" stays a string, not the boolean" \
                                    || bad "S11: got '$(st quoted)' — strictness was lost"

# S12: it answers about ANY field, not just hook_verified. A helper hardcoded to one field would
# not prevent the next additive field from repeating #123.
[ "$(st valid step5_review_mode)" = "ABSENT|completed" ] \
  && ok "S12: works for any field name (step5_review_mode absent here)" \
  || bad "S12: got '$(st valid step5_review_mode)'"

# =====================================================================================
# X. Exit codes. "Did not run" is a third answer, distinct from both a state and a bad value.
bash "$HELPER" "$TMP/valid.yml" hook_verified >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "X1: a determined state exits 0" || bad "X1: a determined state should exit 0"

bash "$HELPER" "$TMP/broken.yml" hook_verified >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "X2: UNREADABLE is a DETERMINATION and exits 0 (the caller reads stdout)" \
               || bad "X2: UNREADABLE should exit 0 — the file was read, and the answer is known"

bash "$HELPER" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "X3: no arguments exits 2" || bad "X3: no arguments should exit 2"

bash "$HELPER" "$TMP/valid.yml" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "X4: one argument exits 2" || bad "X4: one argument should exit 2"

bash "$HELPER" "$TMP/does-not-exist.yml" hook_verified >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "X5: a missing FILE exits 2, distinct from an unparseable one" \
               || bad "X5: a missing file should exit 2"

# X6: exit 3 is the environment, not the input. Simulated by hiding python3 from PATH — the same
# condition a machine without it would present.
# Invoked through an absolute bash, because emptying PATH also hides bash itself and the failure
# then reads as exit 127 from the harness rather than exit 3 from the helper. A first draft did
# exactly that and "failed" for a reason that had nothing to do with the helper.
mkdir -p "$TMP/emptybin"
OUT=$(PATH="$TMP/emptybin" /bin/bash "$HELPER" "$TMP/valid.yml" hook_verified 2>&1); _rc=$?
if [ "$_rc" -eq 3 ] && printf '%s' "$OUT" | grep -q 'DID NOT RUN'; then
  ok "X6: no python3 exits 3 and says DID NOT RUN (an environment fact, not a data fact)"
else
  bad "X6: expected exit 3 + DID NOT RUN, got rc=$_rc out='$OUT'"
fi

# X7: and exit 3 prints NO state on stdout. A caller that reads stdout without checking the code
# must not receive something that looks like an answer.
OUT=$(PATH="$TMP/emptybin" /bin/bash "$HELPER" "$TMP/valid.yml" hook_verified 2>/dev/null)
[ -z "$OUT" ] && ok "X7: a did-not-run produces empty stdout, never a state-shaped line" \
              || bad "X7: exit 3 printed '$OUT' on stdout"

# =====================================================================================
# P. The policy asymmetry. This is the design, and it is the thing most at risk from a later
# reader who notices two call sites treating one state differently and "fixes" it.
if grep -q 'ABSENT|completed' "$NA_SKILL"; then
  ok "P1: nightly check 6 still has an explicit ABSENT|completed tolerance branch"
else
  bad "P1: nightly check 6 lost its ABSENT|completed branch — #123 reintroduced"
fi

if grep -qE 'ABSENT\\\|\*\)' "$AB_SKILL"; then
  ok "P2: autopilot-build check 7 still aborts on ABSENT (opposite policy, same helper)"
else
  bad "P2: autopilot-build check 7 lost its ABSENT abort branch"
fi

# P3: each call site must SAY the asymmetry is deliberate, at its own site. A reader who finds it
# by diffing two files without the note will assume one of them is a bug.
_np=0
for _f in "$NA_SKILL" "$AB_SKILL"; do
  # Flattened AND stripped of comment markers: the phrase legitimately wraps across two comment
  # lines in one of the files, so a plain flatten leaves a `#` inside it. Same family as ADR-0073's
  # line-wrap lesson — a prose assertion must not depend on where the text happens to break.
  sed 's/^[[:space:]]*#[[:space:]]*//' "$_f" | tr '\n' ' ' \
    | grep -q 'Do not "reconcile" the two' && _np=$((_np+1))
done
[ "$_np" -eq 2 ] && ok "P3: both call sites document that the opposite policies are deliberate" \
                 || bad "P3: only $_np of 2 call sites carry the do-not-reconcile note"

# P4: neither call site may still carry its own copy of the extraction. The point of the helper is
# that there is ONE parser, not two that agree today.
_dup=0
for _f in "$NA_SKILL" "$AB_SKILL"; do
  # Comment lines excluded: both files legitimately QUOTE the old one-liner while explaining why
  # it was replaced, and a needle that cannot tell prose from code counts the explanation as the
  # defect (rule 12, and #127's own failure mode in miniature).
  grep -v '^[[:space:]]*#' "$_f" | grep -q "m.get('hook_verified')" && _dup=$((_dup+1))
done
[ "$_dup" -eq 0 ] && ok "P4: neither call site still parses the field itself" \
                  || bad "P4: $_dup call site(s) kept a private copy of the extraction"

# =====================================================================================
# D. Deployment. The call sites invoke the helper by path; without a PAIRS entry it never reaches
# ~/.claude and both gates fail closed on every run. pairs-completeness.test.sh cannot see this —
# skill scripts/ are outside its scope (ADR-0043) — so it is pinned here, as ADR-0069's PTB7 does.
if grep -q 'skills/concept-to-code/scripts/manifest-field-state.sh' "$SYNC"; then
  ok "D1: manifest-field-state.sh has a PAIRS entry in sync-to-claude.sh"
else
  bad "D1: no PAIRS entry — the helper never deploys and both pre-flights fail closed"
fi

# D2: the fail-closed branch itself. An infrastructure gap must be loud and actionable, never
# absorbed by a fallback copy of the logic — that would recreate the duplication on the one path
# where nobody is watching.
for _f in "$NA_SKILL" "$AB_SKILL"; do
  _n=$(basename "$(dirname "$_f")")
  if grep -q 'manifest-field-state.sh not found in either location' "$_f"; then
    ok "D2: $_n fails closed with the sync remedy when the helper is missing"
  else
    bad "D2: $_n has no fail-closed branch for a missing helper"
  fi
done

# =====================================================================================
# R. The real corpus, the population #123 was found in. Count-guarded so an empty glob cannot
# pass vacuously (the pairs-completeness self-test lesson).
_n=$(ls "$REPO"/docs/manifests/*.manifest.yml 2>/dev/null | wc -l | tr -d ' ')
if [ "$_n" -ge 30 ]; then
  _bad=0
  for _m in "$REPO"/docs/manifests/*.manifest.yml; do
    case "$(bash "$HELPER" "$_m" hook_verified 2>/dev/null)" in
      PRESENT\|True|PRESENT\|False|ABSENT\|completed) : ;;
      *) _bad=$((_bad+1)) ;;
    esac
  done
  [ "$_bad" -eq 0 ] && ok "R1: all $_n manifests in this repository resolve to an accepted state" \
                    || bad "R1: $_bad of $_n manifests resolve to a state nightly check 6 rejects"
else
  bad "R1: expected >= 30 manifests, found $_n — R1 would pass vacuously"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
