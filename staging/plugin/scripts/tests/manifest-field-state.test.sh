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
NA_SKILL="$STAGING/plugin/skills/autopilot/SKILL.md"
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
  ok "P1: autopilot check 6 still has an explicit ABSENT|completed tolerance branch"
else
  bad "P1: autopilot check 6 lost its ABSENT|completed branch — #123 reintroduced"
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
                    || bad "R1: $_bad of $_n manifests resolve to a state autopilot check 6 rejects"
else
  bad "R1: expected >= 30 manifests, found $_n — R1 would pass vacuously"
fi


# ==================================================================================================
# V. Issue #240 — the documented value domain named a value nothing has ever written.
#
# ADR-0076 §D2 says the value domain belongs to the CALLER, and offers `step5_mode` as its worked
# example: "workflow|agent_fallback|null". Nothing has ever written `agent_fallback`. Measured over
# the corpus: 18 `agent_batch`, 2 `workflow`, 19 `null`, 2 absent, 0 `agent_fallback`. Both
# producers write `agent_batch`.
#
# THE ISSUE'S OWN DESCRIPTION WAS WRONG ABOUT WHERE IT CAME FROM, and that is the useful part.
# ADR-0016 §Manifest fields had it right all along — `"workflow" | "agent_batch"`. The error entered
# in a SUMMARY of that ADR and spread from the summary. A source and its restatements drifted, and
# nothing compared them.
#
# SO THE FIX IS NOT FOUR CORRECTED STRINGS. It is this section: derive the WRITTEN set from the
# producers, derive the DOCUMENTED set from the helper's own header, and compare in BOTH
# directions. The reverse direction is the one that catches #240 — a documented value nothing
# writes — and it is the ADR-0043 direction lesson applied to a value domain.
#
# SEEN RED: reverting the header to the #240 wording fails V1 AND V2; dropping a written value
# fails V1; a producer writing an undocumented value fails V1; breaking the header derivation
# fails V0b. V3/V4 are forward guards, labelled as such.
#
# DERIVED-GUARD PATTERN — instance 8 (ADR-0086). Derives: the value set on both sides. Waiver: none,
# deliberately; a value domain with an exemption is not a domain. Copied, not shared, per §D1.
# ==================================================================================================
MFS_SH="$STAGING/plugin/skills/concept-to-code/scripts/manifest-field-state.sh"
INIT_SH="$STAGING/plugin/skills/concept-to-code/scripts/manifest-init.sh"

# _vd_doc_set <file> <field> — ONE documented-set derivation, shared by V/W (issue #292, ADR-0125
# §D1/§D3). Takes a FILE argument (not just a field) because WW1 and WN1 must run it against a
# $TMP fixture copy of the helper, never only against the deployed one.
#
# The extra `sed 's/[[:space:]]*|[[:space:]]*/|/g'` after the comment-marker strip is what makes
# this survive a wrap that splits a value list INSIDE itself (".. is none|" / newline /
# "# checkpoint."). Measured (ADR-0125 Live defect 2): without it, `tr -s ' '` leaves exactly one
# space between "|" and the continuation word, and `[a-z_|]+` stops there — the derivation returns
# "none|" alone, the set {none}, with "checkpoint" silently dropped. The collapse removes ALL
# whitespace immediately touching a pipe, wherever the line happened to break.
#
# The extraction regex stays anchored on "<field> is " on purpose: `manifest-field-state.sh`'s own
# header ALSO prints `PRESENT|<value>` example lines and `${st%%|*}`-shaped fragments elsewhere, and
# an unanchored pipe-collapsed scan would pick pipes out of those too. Anchoring on "<field> is "
# guarantees only the one domain sentence is read, never a fragment from elsewhere in the header.
_vd_doc_set() {
  tr '\n' ' ' <"$1" 2>/dev/null | tr -s ' ' | sed 's/# //g' \
    | sed 's/[[:space:]]*|[[:space:]]*/|/g' \
    | grep -oE "$2 is [a-z_|]+" | head -1 | sed "s/$2 is //" \
    | tr '|' '\n' | sed '/^$/d' | sort -u
}

# WRITTEN set: every literal a producer assigns, plus manifest-init.sh's default.
V_WRITTEN=$(grep -rhoE 'step5_mode: "[a-z_]+"' "$STAGING"/plugin/skills/*/SKILL.md \
              "$STAGING"/plugin/skills/*/scripts/*.sh 2>/dev/null \
            | sed 's/.*: "//; s/"//' | sort -u)
if grep -q 'step5_mode: null' "$INIT_SH" 2>/dev/null; then
  V_WRITTEN=$(printf '%s\nnull\n' "$V_WRITTEN" | sed '/^$/d' | sort -u)
fi
V_WRITTEN_N=$(printf '%s\n' "$V_WRITTEN" | grep -c . || true); [ -n "${V_WRITTEN_N:-}" ] || V_WRITTEN_N=0

# DOCUMENTED set: from the helper's own header, via the shared _vd_doc_set (Task 3, issue #292).
# The sentence wraps across two comment lines, so a line-based grep returns nothing — and an empty
# documented set would make V2 below vacuously true. Fourth appearance of this lesson family
# (ADR-0073 line wrap, ADR-0076 comment marker, ADR-0080 backticks, ADR-0082 one-line marker), met
# here while deriving it.
V_DOC=$(_vd_doc_set "$MFS_SH" step5_mode)
V_DOC_N=$(printf '%s\n' "$V_DOC" | grep -c . || true); [ -n "${V_DOC_N:-}" ] || V_DOC_N=0

# V0/V0b — count guards on BOTH derivations. Either one silently returning nothing makes the
# comparison below pass while measuring nothing; that is this repository's most-repeated defect.
if [ "$V_WRITTEN_N" -ge 2 ]; then
  ok "V0 (count guard): $V_WRITTEN_N step5_mode value(s) derived from the producers"
else
  bad "V0 (count guard): only $V_WRITTEN_N value(s) derived from the producers — the grep has stopped matching, the producers have not stopped writing"
fi
if [ "$V_DOC_N" -ge 2 ]; then
  ok "V0b (count guard): $V_DOC_N step5_mode value(s) derived from the helper header"
else
  bad "V0b (count guard): only $V_DOC_N value(s) derived from $MFS_SH — the header derivation is broken (it wraps across comment lines and needs flattening, or a value list splits inside the wrap and needs the pipe-whitespace collapse), not the header clean"
fi

# _vd_diff <listA> <listB> — members of A (newline/space-separated) absent from B, one per line
# (issue #292, ADR-0125 §D1). It COMPUTES and never REPORTS: V1's and V2's failure messages differ
# deliberately and are anchors, and so do W's later in this file, so formatting stays at each call
# site rather than moving into this function.
_vd_diff() {
  _vdd_item=""
  for _vdd_item in $1; do
    printf '%s\n' "$2" | grep -qxF "$_vdd_item" || printf '%s\n' "$_vdd_item"
  done
}

# V1 — forward: every value a producer writes must be documented.
V1_MISSING=""
for _v in $(_vd_diff "$V_WRITTEN" "$V_DOC"); do V1_MISSING="$V1_MISSING $_v"; done
if [ -z "$V1_MISSING" ]; then
  ok "V1: every step5_mode value a producer writes is named in the documented domain"
else
  bad "V1: producers write value(s) the documented domain omits:$V1_MISSING — a checker built on that header would reject real manifests (ADR-0075/#123 replayed)"
fi

# V2 — REVERSE, and this is the assertion that catches #240: a documented value nothing writes.
# Without it, the header could name anything at all and V1 would still pass.
V2_PHANTOM=""
for _v in $(_vd_diff "$V_DOC" "$V_WRITTEN"); do V2_PHANTOM="$V2_PHANTOM $_v"; done
if [ -z "$V2_PHANTOM" ]; then
  ok "V2: the documented domain names no value that no producer writes"
else
  bad "V2: the documented domain names phantom value(s):$V2_PHANTOM — nothing writes them, and the next author of a step5_mode checker will assert them (issue #240)"
fi

# V3 — the corpus agrees with the producers. A value in a real manifest that no producer writes
# means either an undiscovered writer or a hand-edit; either way the domain above is incomplete.
V3_UNKNOWN=""
V3_N=0
for _m in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_m" ] || continue
  _val=$(grep -m1 '^step5_mode:' "$_m" 2>/dev/null | sed 's/^step5_mode:[[:space:]]*//; s/"//g')
  [ -n "$_val" ] || continue
  V3_N=$((V3_N + 1))
  printf '%s\n' "$V_WRITTEN" | grep -qxF "$_val" || V3_UNKNOWN="$V3_UNKNOWN $_val"
done
if [ "$V3_N" -ge 10 ] && [ -z "$V3_UNKNOWN" ]; then
  ok "V3 (forward guard, green before and after): all $V3_N corpus manifests carrying step5_mode hold a value some producer writes"
elif [ "$V3_N" -lt 10 ]; then
  bad "V3 (count guard): only $V3_N manifest(s) carry step5_mode — the corpus sweep is not measuring anything"
else
  bad "V3: corpus manifests hold value(s) no producer writes:$V3_UNKNOWN"
fi

# V4 — ADR-0016 is the SOURCE and it was never wrong. Pinned because the drift ran source -> summary,
# so a future "correction" applied to the source would be fixing the wrong file.
ADR16="$REPO/docs/architecture/ADR-0016-dynamic-workflows-step5.md"
if [ -f "$ADR16" ] && grep -q 'agent_batch' "$ADR16" && ! grep -q 'agent_fallback' "$ADR16"; then
  ok "V4 (forward guard, green before and after): ADR-0016, the source, names agent_batch and never agent_fallback — the drift was in the summaries"
else
  bad "V4: ADR-0016 no longer reads as the correct source — check before 'fixing' it; the error entered in a summary of it (#240)"
fi

# ==================================================================================================
# W. Issue #292 — the value-domain guard (section V) covered step5_mode only. hook_verified and
# step5_review_mode, ADR-0092's own consequence bullet names both as out of scope, had no
# equivalent. Neither field has a phantom today: written vs documented is clean in both directions
# on both fields, measured. So THIS IS A GUARD, NOT A FIX (ADR-0107's shape) — do not go hunting for
# an agent_fallback-shaped defect here, there is not one.
#
# The written-set extractors below are PER-FIELD, on measurement, not by elegance. Applying
# step5_mode's shared colon idiom (`<field>: [a-z_]+` over skills/*/SKILL.md and
# skills/*/scripts/*.sh) to hook_verified yields {false, true, field, manifest, the, value}: four
# English words lifted out of operator-facing error messages that happen to use a colon —
# "hook_verified: field absent", "hook_verified: value is …", "hook_verified:
# manifest-field-state.sh not found …", "hook_verified: the manifest could not be read …" in
# autopilot-build/SKILL.md and autopilot/SKILL.md. The `hook_verified=<word>` variant is
# worse: it adds `unchanged`, hook-verify-workflow.sh's RECOMMEND token meaning DO NOT WRITE THIS
# FIELD — a recommendation not to write would enter the written set. step5_review_mode's colon idiom
# stays clean (7 matches, {none, checkpoint}) and needs none of this per-field care.
#
# DERIVED-GUARD PATTERN — instance 12 (ADR-0086). Derives: the value set on both sides, for two
# additional fields. Waiver: none, deliberately; a value domain with an exemption is not a domain.
# ==================================================================================================

# WH2 — count guard on hook_verified's documented set. RED now: the header says "hook_verified is a
# boolean" — a TYPE, not an enumeration — and the derivation below yields the single token "a".
# Two distinct causes could produce a failure here and the message names both, because either one
# alone would send the next reader hunting the wrong file: (1) the domain sentence wrapping across
# comment lines so the flatten loses part of it, or (2) the header naming a type or a capitalised
# form (True|False cannot match [a-z_|]+ at all — the derivation must not be "fixed" to expect that;
# it is a different axis, S1/S2/S11's, not this one). Task 2 corrects cause 2 here.
# plant: WH2 | plugin/skills/concept-to-code/scripts/manifest-field-state.sh | hook_verified is true|false | hook_verified is a boolean
WH_DOC=$(_vd_doc_set "$MFS_SH" hook_verified)
WH_DOC_N=$(printf '%s\n' "$WH_DOC" | grep -c . || true); [ -n "${WH_DOC_N:-}" ] || WH_DOC_N=0
if [ "$WH_DOC_N" -ge 2 ]; then
  ok "WH2 (count guard): $WH_DOC_N hook_verified value(s) derived from the helper header"
else
  bad "WH2 (count guard): only $WH_DOC_N value(s) derived from the header — either (a) the domain sentence wraps across comment lines and needs flattening, or (b) the header states a type or a capitalised form rather than an enumeration ('hook_verified is a boolean' yields the single token 'a')"
fi

# WR2 — count guard on step5_review_mode's documented set. Green today: FORWARD GUARD, labelled as
# such. The sentence does not wrap mid-list in the shipped header, so the flatten already returns
# the full {none, checkpoint}. Task 3's shared derivation must keep this green while it fixes WW1's
# wrap fixture below — a regression here would mean the shared function broke the common case while
# fixing the wrapped one.
# plant: WR2 | plugin/skills/concept-to-code/scripts/manifest-field-state.sh | step5_review_mode is none|checkpoint | step5_review_mode is unspecified
WR_DOC=$(_vd_doc_set "$MFS_SH" step5_review_mode)
WR_DOC_N=$(printf '%s\n' "$WR_DOC" | grep -c . || true); [ -n "${WR_DOC_N:-}" ] || WR_DOC_N=0
if [ "$WR_DOC_N" -ge 2 ]; then
  ok "WR2 (count guard, forward guard — green before and after): $WR_DOC_N step5_review_mode value(s) derived from the helper header"
else
  bad "WR2 (count guard): only $WR_DOC_N value(s) derived from the header — the domain sentence has stopped resolving to an enumeration"
fi

# WW1 — R-02's direct evidence: the derivation must SURVIVE a sentence that wraps across comment
# lines, not merely fail loudly on it (V0b and WR2 above already do the latter, on a different
# wrap shape). Fixture: copy the helper and re-flow its domain sentence with sed so the value list
# is split INSIDE itself — "... is none|" / newline / "# checkpoint. There is no general "valid"." —
# reproducing a routine re-flow, not the wrap the shipped header already survives (between `is` and
# its list).
# RED now, measured: today's flatten strips the leading "# " on the continuation line but leaves
# the space `tr -s ' '` collapses in between "|" and "checkpoint", and [a-z_|]+ stops at it — the
# derivation returns "none|" alone, the set {none}, with checkpoint silently dropped. That is the
# untested case ADR-0125 Live defect 2 measured; the count guard above (WR2) would catch a
# one-element set, which is the safe direction and not the same as surviving the wrap.
# plant: WW1 | plugin/scripts/tests/manifest-field-state.test.sh | | sed 's/[[:space:]]*|[[:space:]]*/|/g' | | cat
cp "$MFS_SH" "$TMP/ww1-helper.sh"
sed 's/is none|checkpoint\./is none|\
# checkpoint./' "$TMP/ww1-helper.sh" > "$TMP/ww1-helper2.sh"
WW1_DOC=$(_vd_doc_set "$TMP/ww1-helper2.sh" step5_review_mode)
WW1_SORTED=$(printf '%s\n' "$WW1_DOC" | tr '\n' ',' | sed 's/,$//')
if [ "$WW1_SORTED" = "checkpoint,none" ]; then
  ok "WW1: the derivation survives a value list split inside the wrap ({checkpoint,none} back)"
else
  bad "WW1: expected the full set {checkpoint,none} back from a mid-list wrap, got '$WW1_SORTED' — 'none' alone means the derivation has not been fixed yet (expected before Task 3); anything else means the fixture itself is wrong, not the derivation"
fi

# ==================================================================================================
# WH — hook_verified's WRITTEN set, both directions (Task 4, issue #292, ADR-0125 §D1/§D5).
#
# WHY THE COLON IDIOM ("hook_verified: [a-z_]+") IS NOT USED HERE, unlike step5_mode's V_WRITTEN and
# step5_review_mode's WR_WRITTEN below. Measured (ADR-0125): applying it to hook_verified yields
# {false, true, field, manifest, the, value} — four ENGLISH WORDS lifted out of operator-facing
# error messages that happen to use a colon: "hook_verified: field absent …", "hook_verified: value
# is …", "hook_verified: manifest-field-state.sh not found …", "hook_verified: the manifest could
# not be read …" in autopilot-build/SKILL.md and autopilot/SKILL.md. A guard built on that
# idiom would fail on a correct tree on its first run. Instead this reads the actual write shapes:
# manifest-set-flag.sh's two call-site literals, plus manifest-init.sh's bare-literal default.
#
# THE EXTRACTOR COUPLES TO THE LITERAL HELPER NAME "manifest-set-flag.sh". Renaming that helper
# collapses this set to {false} (the init.sh default alone survives) — loud, via WH1's count guard,
# but a real coupling and a plausible future edit.
# plant: WH1 | plugin/scripts/tests/manifest-field-state.test.sh | manifest-set-flag\.sh.* hook_verified (true|false) | manifest-set-flag\.sh.* hook_verified_ZZZ (true|false)
WH_WRITTEN=$( { grep -rhoE 'manifest-set-flag\.sh.* hook_verified (true|false)' \
    "$STAGING"/plugin/skills/*/SKILL.md "$STAGING"/plugin/skills/*/scripts/*.sh 2>/dev/null \
    | sed -E 's/.*hook_verified (true|false).*/\1/'
  grep -oE '^echo "hook_verified: (true|false)"' "$INIT_SH" 2>/dev/null \
    | sed -E 's/^echo "hook_verified: (true|false)".*/\1/'
  } | sort -u )
WH_WRITTEN_N=$(printf '%s\n' "$WH_WRITTEN" | grep -c . || true); [ -n "${WH_WRITTEN_N:-}" ] || WH_WRITTEN_N=0

# WH1 — count guard on the written set.
if [ "$WH_WRITTEN_N" -ge 2 ]; then
  ok "WH1 (count guard): $WH_WRITTEN_N hook_verified value(s) derived from the producers"
else
  bad "WH1 (count guard): only $WH_WRITTEN_N value(s) derived from the producers — the extractor couples to the literal string 'manifest-set-flag.sh'; a rename of that helper collapses this set to {false} alone"
fi

# plant: WH3 | plugin/skills/concept-to-code/scripts/manifest-field-state.sh | hook_verified is true|false | hook_verified is true
# WH3 — forward: every value a producer writes must be documented.
WH3_MISSING=""
for _v in $(_vd_diff "$WH_WRITTEN" "$WH_DOC"); do WH3_MISSING="$WH3_MISSING $_v"; done
if [ -z "$WH3_MISSING" ]; then
  ok "WH3: every hook_verified value a producer writes is named in the documented domain"
else
  bad "WH3: producers write hook_verified value(s) the documented domain omits:$WH3_MISSING"
fi

# plant: WH4 | plugin/skills/concept-to-code/scripts/manifest-field-state.sh | hook_verified is true|false | hook_verified is true|false|ghost
# WH4 — REVERSE: the documented domain names no value no producer writes. This is the direction
# that catches #240's shape.
WH4_PHANTOM=""
for _v in $(_vd_diff "$WH_DOC" "$WH_WRITTEN"); do WH4_PHANTOM="$WH4_PHANTOM $_v"; done
if [ -z "$WH4_PHANTOM" ]; then
  ok "WH4: the documented hook_verified domain names no value that no producer writes"
else
  bad "WH4: the documented hook_verified domain names phantom value(s):$WH4_PHANTOM — nothing writes them (#240's shape)"
fi

# ==================================================================================================
# WR — step5_review_mode's WRITTEN set, both directions (Task 5, issue #292, ADR-0125 §D1).
#
# The colon idiom IS clean for this field (7 matches, measured), and is deliberately NOT shared with
# hook_verified's extractor above — a shared idiom fails on hook_verified for the measured reason.
# It is also permissive: SKILL.md prose alone would sustain "checkpoint" in this set even if its
# real producer (manifest-init.sh's sed flip line) vanished. WR6 (Task 7) pins that real producer
# separately, which is what makes this permissiveness safe rather than blind.
# plant: WR1 | plugin/scripts/tests/manifest-field-state.test.sh | step5_review_mode: [a-z_]+ | step5_review_mode_ZZZ: [a-z_]+
WR_WRITTEN=$(grep -rhoE 'step5_review_mode: [a-z_]+' \
    "$STAGING"/plugin/skills/*/SKILL.md "$STAGING"/plugin/skills/*/scripts/*.sh 2>/dev/null \
    | sed 's/.*: //' | sort -u)
WR_WRITTEN_N=$(printf '%s\n' "$WR_WRITTEN" | grep -c . || true); [ -n "${WR_WRITTEN_N:-}" ] || WR_WRITTEN_N=0

# WR1 — count guard on the written set.
if [ "$WR_WRITTEN_N" -ge 2 ]; then
  ok "WR1 (count guard): $WR_WRITTEN_N step5_review_mode value(s) derived from the producers"
else
  bad "WR1 (count guard): only $WR_WRITTEN_N value(s) derived from the producers — the colon idiom has stopped matching"
fi

# plant: WR3 | plugin/skills/concept-to-code/scripts/manifest-field-state.sh | step5_review_mode is none|checkpoint | step5_review_mode is none
# WR3 — forward.
WR3_MISSING=""
for _v in $(_vd_diff "$WR_WRITTEN" "$WR_DOC"); do WR3_MISSING="$WR3_MISSING $_v"; done
if [ -z "$WR3_MISSING" ]; then
  ok "WR3: every step5_review_mode value a producer writes is named in the documented domain"
else
  bad "WR3: producers write step5_review_mode value(s) the documented domain omits:$WR3_MISSING"
fi

# plant: WR4 | plugin/skills/concept-to-code/scripts/manifest-field-state.sh | step5_review_mode is none|checkpoint | step5_review_mode is none|checkpoint|ghost
# WR4 — reverse.
WR4_PHANTOM=""
for _v in $(_vd_diff "$WR_DOC" "$WR_WRITTEN"); do WR4_PHANTOM="$WR4_PHANTOM $_v"; done
if [ -z "$WR4_PHANTOM" ]; then
  ok "WR4: the documented step5_review_mode domain names no value that no producer writes"
else
  bad "WR4: the documented step5_review_mode domain names phantom value(s):$WR4_PHANTOM"
fi

# ==================================================================================================
# Corpus sweeps on the LITERAL axis (Task 6, issue #292, ADR-0125 §D6). Count-guarded on their own
# denominator, each with its own 'bad' branch on shortfall (ADR-0085).
#
# plant: WH5 | ../docs/manifests/2026-05-23-clean-public-repo-anonymize.manifest.yml | hook_verified: false | hook_verified: nottrue
# WH5 is NOT redundant with R1 above. R1 sweeps the PARSED-STATE axis (PRESENT|True/PRESENT|False/
# ABSENT|completed): hook_verified: yes PASSES R1 because YAML 1.1 parses it to True. WH5 sweeps the
# same field on the WRITTEN-LITERAL axis (the raw text after the colon) and that same manifest FAILS
# it, because the literal "yes" is written by no producer. Two different axes, two different sweeps.
WH5_BAD=0
WH5_N=0
for _m in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_m" ] || continue
  _lit=$(grep -m1 '^hook_verified:' "$_m" 2>/dev/null | sed 's/^hook_verified:[[:space:]]*//; s/"//g')
  [ -n "$_lit" ] || continue
  WH5_N=$((WH5_N + 1))
  printf '%s\n' "$WH_WRITTEN" | grep -qxF "$_lit" || WH5_BAD=$((WH5_BAD + 1))
done
if [ "$WH5_N" -lt 30 ]; then
  bad "WH5 (count guard): only $WH5_N manifest(s) carry hook_verified — expected >= 30, the corpus sweep is not measuring anything"
elif [ "$WH5_BAD" -eq 0 ]; then
  ok "WH5: all $WH5_N corpus manifests' hook_verified LITERAL is a value some producer writes"
else
  bad "WH5: $WH5_BAD of $WH5_N corpus manifests carry a hook_verified literal no producer writes"
fi

# plant: WR5 | ../docs/manifests/2026-07-26-100-secrets-and-dependency-gate-content.manifest.yml | step5_review_mode: none # Scaffolding | step5_review_mode: strangeval
# WR5 — same sweep for step5_review_mode. 0 manifests carry "checkpoint" in the corpus, so this
# sweep has never exercised that value and cannot until the opt-in is taken — that is NOT a phantom,
# because the reverse check (WR4) compares documented against PRODUCERS, never against the corpus.
WR5_BAD=0
WR5_N=0
for _m in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_m" ] || continue
  _lit=$(grep -m1 '^step5_review_mode:' "$_m" 2>/dev/null | sed 's/^step5_review_mode:[[:space:]]*//; s/"//g')
  [ -n "$_lit" ] || continue
  WR5_N=$((WR5_N + 1))
  printf '%s\n' "$WR_WRITTEN" | grep -qxF "$_lit" || WR5_BAD=$((WR5_BAD + 1))
done
if [ "$WR5_N" -lt 20 ]; then
  bad "WR5 (count guard): only $WR5_N manifest(s) carry step5_review_mode — expected >= 20, the corpus sweep is not measuring anything"
elif [ "$WR5_BAD" -eq 0 ]; then
  ok "WR5: all $WR5_N corpus manifests' step5_review_mode LITERAL is a value some producer writes"
else
  bad "WR5: $WR5_BAD of $WR5_N corpus manifests carry a step5_review_mode literal no producer writes"
fi

# ==================================================================================================
# E. The enforcers, and the no-waiver check (Task 7, issue #292, ADR-0125 §D5/§D4).
#
# Each field's WRITTEN-set extractor above reads only the shapes its real producers use. That is
# trustworthy only because something else ENFORCES nobody can write a third shape — WH6 and WR7 pin
# those enforcers; WR6 pins step5_review_mode's one real (non-manifest-set-flag.sh) producer, the
# mitigation for its permissive colon-idiom extractor's blind spot (WR_WRITTEN's own comment).
# ==================================================================================================
SETFLAG_SH="$STAGING/plugin/skills/concept-to-code/scripts/manifest-set-flag.sh"
VALIDATE_SH="$STAGING/plugin/skills/concept-to-code/scripts/manifest-validate.sh"

# WH6 — manifest-set-flag.sh structurally refuses anything but true/false. This is what lets
# WH_WRITTEN read only two call-site shapes without going blind: nothing else can write the field.
# Covered by nothing in 73 harness files before this (ADR-0125 §D5).
mk hvflag 'topic: "x"\nhook_verified: false\n'
# plant: WH6 | plugin/skills/concept-to-code/scripts/manifest-set-flag.sh | [ "$VAL" != "true" ] && [ "$VAL" != "false" ] | [ "$VAL" != "true" ] && [ "$VAL" != "false" ] && [ "$VAL" != "maybe" ]
WH6_OUT=$(bash "$SETFLAG_SH" "$TMP/hvflag.yml" hook_verified maybe 2>&1)
WH6_RC=$?
if [ "$WH6_RC" -ne 0 ] && printf '%s' "$WH6_OUT" | grep -q "value must be 'true' or 'false'"; then
  ok "WH6: manifest-set-flag.sh refuses a hook_verified value that is not true/false"
else
  bad "WH6: expected non-zero exit + the true/false constraint message, got rc=$WH6_RC out='$WH6_OUT'"
fi

# WR6 — manifest-init.sh still carries the sed flip that is checkpoint's only real producer. Needle
# is the COMMAND itself, not the field name (rule 12: SKILL.md and this file's own header both name
# "step5_review_mode: checkpoint" in prose).
# plant: WR6 | plugin/skills/concept-to-code/scripts/manifest-init.sh | sed -i '' 's/^step5_review_mode: none/step5_review_mode: checkpoint/' | sed -i '' 's/^step5_review_mode: zzz/step5_review_mode: checkpoint/'
if grep -qF "sed -i '' 's/^step5_review_mode: none/step5_review_mode: checkpoint/'" "$INIT_SH"; then
  ok "WR6: manifest-init.sh still carries the sed flip that is checkpoint's only real producer"
else
  bad "WR6: the sed flip line for step5_review_mode is gone — checkpoint has no real producer left, only prose"
fi

# WR7 — invariant 14's enumeration equals the documented domain. step5-checkpoint-review.test.sh
# B1/B2/B3 cover invariant 14's BEHAVIOUR (accepts none, accepts checkpoint, rejects aggressive);
# this covers ENFORCER-VERSUS-DOCUMENT AGREEMENT, a different question — #240's shape with a
# different pair of files.
# plant: WR7 | plugin/skills/concept-to-code/scripts/manifest-validate.sh | step5_review_mode: (none|checkpoint) | step5_review_mode: (none|checkpoint|aggressive)
WR7_ENUM=$(grep -oE 'step5_review_mode: \([a-z_|]+\)' "$VALIDATE_SH" | head -1 \
  | sed -E 's/step5_review_mode: \(//; s/\)$//' | tr '|' '\n' | sed '/^$/d' | sort -u)
WR7_ENUM_N=$(printf '%s\n' "$WR7_ENUM" | grep -c . || true); [ -n "${WR7_ENUM_N:-}" ] || WR7_ENUM_N=0
if [ "$WR7_ENUM_N" -lt 2 ]; then
  bad "WR7 (count guard): only $WR7_ENUM_N value(s) derived from invariant 14 — the alternation has stopped resolving"
elif [ "$WR7_ENUM" = "$WR_DOC" ]; then
  ok "WR7: invariant 14's enumeration ($WR7_ENUM_N values) agrees with the documented domain"
else
  bad "WR7: invariant 14's enumeration ($WR7_ENUM) disagrees with the documented domain ($WR_DOC) — an enforcer and a document disagreeing is #240's shape"
fi

# WN1 — R-03, BEHAVIOURAL. ADR-0092 recorded "no waiver mechanism, deliberately" as prose; a prose
# claim about an absent mechanism is unplantable and rule-12 exposed (a needle on it matches the
# sentence explaining it). Asserted instead by BEHAVIOUR: plant a value-domain-exempt marker into a
# fixture copy of the helper's documented sentence, and require the mismatch is STILL reported —
# because neither _vd_doc_set nor _vd_diff has any branch that would honour such a marker.
# _vd_diff takes two lists and nothing else, by construction (ADR-0125 §D4).
cp "$MFS_SH" "$TMP/wn1-helper.sh"
sed 's/hook_verified is true|false/hook_verified is true|false|maybe\
# value-domain-exempt: maybe/' "$TMP/wn1-helper.sh" > "$TMP/wn1-helper2.sh"
WN1_DOC=$(_vd_doc_set "$TMP/wn1-helper2.sh" hook_verified)
# plant: WN1 | plugin/scripts/tests/manifest-field-state.test.sh | grep -qxF "$_vdd_item" || printf | grep -qxF "$_vdd_item" || [ "$_vdd_item" = "maybe" ] || printf
WN1_PHANTOM=$(_vd_diff "$WN1_DOC" "$WH_WRITTEN")
if printf '%s\n' "$WN1_PHANTOM" | grep -qxF "maybe"; then
  ok "WN1: a value-domain-exempt marker does not suppress a phantom value — no waiver mechanism exists (R-03)"
else
  bad "WN1: the exempt marker suppressed 'maybe' from the mismatch — a waiver mechanism has been introduced, violating R-03"
fi

# Z1 — assertion-count floor (ADR-0083 §D3). Raised to the exact executed total (48) rather than
# left at the old 30: a floor with slack absorbs its own plant (ADR-0124) — left at 30 here it would
# have carried 18 units of slack, and up to 18 of the assertions added in this feature could vanish
# while Z1 stayed green. No slack is required going forward: this floor is bumped by hand whenever an
# assertion is added or removed, exactly as ADR-0124 bumped SP8's file the day it made the same point.
Z1_TOTAL=$((PASS + FAIL))
if [ "$Z1_TOTAL" -ge 48 ]; then
  ok "Z1: assertion-count floor met ($Z1_TOTAL executed)"
else
  bad "Z1: only $Z1_TOTAL assertions executed — expected >= 48; assertions have gone missing, not passed"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
