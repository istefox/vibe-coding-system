#!/bin/bash
# proportional-audit-depth.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash proportional-audit-depth.test.sh
#
# Covers issue #109 / ADR-0055: two additive manifest fields (`risk`, `task_type`) that resolve
# to an audit profile governing gate DEPTH only, never gate EXISTENCE.
#
# ASSERTION LABELS ARE P-PREFIXED (PA1, PB2, PG3, ...) to stay distinguishable from every other
# harness printing into the same CI shell-tests job (B-, R-, H-, W-, I-, ...).
#
# THE THREE THINGS THIS HARNESS EXISTS TO CATCH (plan risk flags):
#   1. Defaulting to inert-like-the-last-three-features. ADR-0052/0053/0054 all default to
#      inert-when-absent; this feature must default to STRICT when absent, because it *removes*
#      a constraint rather than adding one (ADR-0055 §D2). Section PB is the guard, run against
#      the REAL corpus in docs/manifests/, not a fixture — a synthetic fixture cannot prove the
#      real installed base stays on the strict profile the moment this merges.
#   2. The profile becoming a bypass. Section PD pins that a `light` profile can never remove
#      spec-coverage.sh, the weakening scan, interface-check.sh, or the recovery-readiness
#      pre-flight (ADR-0055 §D4) — a `task_type: boilerplate` label on a payment change must not
#      disable the checks that exist for payment changes.
#   3. Two resolution sites drifting. Section PC pins there is exactly one documented place that
#      maps (risk, task_type) -> profile, `max()`, never averaged or weighted (ADR-0055 §D3).
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL and no fixture path contains "secret",
# "credential", ".env", ".pem", or ".key" — secret-dep-gate.test.sh section D scans this
# repository's tracked files as its false-positive corpus.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
REPO=$(cd "$STAGING/.." && pwd)
SKILL_DIR="$STAGING/plugin/skills/concept-to-code"
SKILL_MD="$SKILL_DIR/SKILL.md"
HITL_REF="$SKILL_DIR/references/hitl-gates.md"
INIT="$SKILL_DIR/scripts/manifest-init.sh"
VAL="$SKILL_DIR/scripts/manifest-validate.sh"
ARCHITECT="$STAGING/plugin/agents/architect.md"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# --- helper: create a fresh manifest fixture, return its path in FIX_MANIFEST ---
mk_manifest() {
  _slug="$1"
  _proj="$(mktemp -d "$TMP/proj-$_slug.XXXXXX")"
  FIX_MANIFEST="$(bash "$INIT" "$_slug" "Test $_slug" "$_proj" 2>"$TMP/init-err")"
  if [ -z "$FIX_MANIFEST" ] || [ ! -f "$FIX_MANIFEST" ]; then
    FIX_MANIFEST=""
  fi
}

# --- helper: extract the "Proportional audit depth" resolution subsection from SKILL.md, from
# its own header to the next "#### " or "### " header, into $TMP/resolution-section.md ---
extract_resolution_section() {
  awk '
    /^#### Proportional audit depth/ { f=1; print; next }
    f && /^#{3,4} / { exit }
    f { print }
  ' "$SKILL_MD" > "$TMP/resolution-section.md"
}

# --- helper: extract a named "#### <heading prefix>" subsection body from SKILL.md, from its
# own header (matched by fixed-string prefix) to the next "#### " or "### " header ---
extract_named_section() {
  _prefix="$1"; _outfile="$2"
  awk -v prefix="$_prefix" '
    index($0, prefix) == 1 { f=1; print; next }
    f && /^#{3,4} / { exit }
    f { print }
  ' "$SKILL_MD" > "$_outfile"
}

if [ -f "$SKILL_MD" ]; then
  ok "P0: concept-to-code/SKILL.md exists and is readable"
else
  bad "P0: $SKILL_MD not found — every SKILL.md-anchored assertion below is meaningless"
fi

# ==================================================================================================
# PA. Both fields validate as conditional-if-present, every enum value accepted.
# ==================================================================================================
mk_manifest pa1
if [ -n "$FIX_MANIFEST" ] && grep -q '^risk: null$' "$FIX_MANIFEST" && grep -q '^task_type: null$' "$FIX_MANIFEST"; then
  ok "PA1: manifest-init.sh writes risk: null and task_type: null on a fresh manifest"
else
  bad "PA1: manifest-init.sh did not write risk: null / task_type: null — got FIX_MANIFEST=[$FIX_MANIFEST]"
fi

if [ -n "$FIX_MANIFEST" ]; then
  if bash "$VAL" "$FIX_MANIFEST" >"$TMP/pa2out" 2>&1; then
    ok "PA2: a freshly-init'd manifest (risk: null, task_type: null) validates OK"
  else
    bad "PA2: a freshly-init'd manifest failed to validate — $(cat "$TMP/pa2out")"
  fi
fi

for v in low high; do
  mk_manifest "pa3-$v"
  [ -z "$FIX_MANIFEST" ] && { bad "PA3: fixture init failed for risk=$v"; continue; }
  sed -i.bak "s/^risk: null\$/risk: \"$v\"/" "$FIX_MANIFEST"
  if bash "$VAL" "$FIX_MANIFEST" >"$TMP/pa3out" 2>&1; then
    ok "PA3: risk: \"$v\" validates OK"
  else
    bad "PA3: risk: \"$v\" failed to validate — $(cat "$TMP/pa3out")"
  fi
done

mk_manifest pa4
if [ -n "$FIX_MANIFEST" ]; then
  sed -i.bak 's/^risk: null$/risk: "medium"/' "$FIX_MANIFEST"
  if bash "$VAL" "$FIX_MANIFEST" >"$TMP/pa4out" 2>&1; then
    bad "PA4: risk: \"medium\" (not in low|high) should have failed validation but exited 0"
  else
    ok "PA4: risk: \"medium\" correctly rejected by manifest-validate.sh"
  fi
fi

for v in boilerplate glue novel-algorithm regulated legacy-integration perf-critical; do
  mk_manifest "pa5-$v"
  [ -z "$FIX_MANIFEST" ] && { bad "PA5: fixture init failed for task_type=$v"; continue; }
  sed -i.bak "s/^task_type: null\$/task_type: \"$v\"/" "$FIX_MANIFEST"
  if bash "$VAL" "$FIX_MANIFEST" >"$TMP/pa5out" 2>&1; then
    ok "PA5: task_type: \"$v\" validates OK"
  else
    bad "PA5: task_type: \"$v\" failed to validate — $(cat "$TMP/pa5out")"
  fi
done

mk_manifest pa6
if [ -n "$FIX_MANIFEST" ]; then
  sed -i.bak 's/^task_type: null$/task_type: "rewrite-everything"/' "$FIX_MANIFEST"
  if bash "$VAL" "$FIX_MANIFEST" >"$TMP/pa6out" 2>&1; then
    bad "PA6: an invalid task_type should have failed validation but exited 0"
  else
    ok "PA6: an invalid task_type correctly rejected by manifest-validate.sh"
  fi
fi

mk_manifest pa7
if [ -n "$FIX_MANIFEST" ]; then
  sed -i.bak '/^risk: null$/d' "$FIX_MANIFEST"
  if bash "$VAL" "$FIX_MANIFEST" >"$TMP/pa7out" 2>&1; then
    ok "PA7: a manifest with NO risk: line at all (pre-ADR-0055 retrocompat) still validates OK"
  else
    bad "PA7: absent risk: field must be valid (conditional-if-present) — $(cat "$TMP/pa7out")"
  fi
fi

mk_manifest pa8
if [ -n "$FIX_MANIFEST" ]; then
  sed -i.bak '/^task_type: null$/d' "$FIX_MANIFEST"
  if bash "$VAL" "$FIX_MANIFEST" >"$TMP/pa8out" 2>&1; then
    ok "PA8: a manifest with NO task_type: line at all (pre-ADR-0055 retrocompat) still validates OK"
  else
    bad "PA8: absent task_type: field must be valid (conditional-if-present) — $(cat "$TMP/pa8out")"
  fi
fi

# ==================================================================================================
# PB. The default-strict rule (ADR-0055 §D2), asserted against the REAL corpus in docs/manifests/.
# ==================================================================================================
extract_resolution_section
if [ -s "$TMP/resolution-section.md" ]; then
  ok "PB0: the '#### Proportional audit depth' resolution section exists in SKILL.md"
else
  bad "PB0: no '#### Proportional audit depth' section found in SKILL.md — every PB/PC/PD assertion below reads an empty file"
fi

if grep -qi 'absent means strict' "$TMP/resolution-section.md" 2>/dev/null; then
  ok "PB1: the resolution section states the default-strict rule in those words (ADR-0055 §D2)"
else
  bad "PB1: 'absent means STRICT' rule not found in the resolution section"
fi

if grep -qE 'risk.*(absent|null).*strict|(absent|null).*risk.*strict' "$TMP/resolution-section.md" 2>/dev/null \
   || (grep -qi 'risk' "$TMP/resolution-section.md" && grep -qi 'absent, `null`, or a pre-adr-0055 manifest' "$TMP/resolution-section.md"); then
  ok "PB2: the risk axis explicitly states absent/null/pre-ADR-0055 resolves to strict"
else
  bad "PB2: risk axis default-strict wording not found"
fi

if grep -qi 'task_type' "$TMP/resolution-section.md" && grep -ci 'absent, `null`, or a pre-adr-0055 manifest' "$TMP/resolution-section.md" | grep -qE '^[2-9][0-9]*$'; then
  ok "PB3: the task_type axis explicitly states absent/null/pre-ADR-0055 resolves to strict (independently of the risk axis statement)"
else
  bad "PB3: task_type axis default-strict wording not found (or not stated independently from the risk axis)"
fi

pb_count=0; pb_missing_fields=0
for f in "$REPO"/docs/manifests/*.manifest.yml; do
  pb_count=$((pb_count + 1))
  if grep -q '^risk:' "$f" || grep -q '^task_type:' "$f"; then
    : # a manifest that already declares the fields is fine too, just not what PB5 exercises
  else
    pb_missing_fields=$((pb_missing_fields + 1))
  fi
done
if [ "$pb_count" -ge 5 ]; then
  ok "PB4: the real docs/manifests/ corpus loop visited $pb_count files (>= 5) — not a vacuous pass"
else
  bad "PB4: the real docs/manifests/ corpus loop visited only $pb_count files (< 5) — a glob matching almost nothing would read as full coverage"
fi
if [ "$pb_missing_fields" -ge 5 ]; then
  ok "PB5: $pb_missing_fields of $pb_count real manifests predate ADR-0055 (no risk:/task_type: field) — the default-strict rule is what actually governs today's installed base, not a hypothetical"
else
  bad "PB5: expected the large majority of the real corpus to predate ADR-0055 — got only $pb_missing_fields/$pb_count without the fields"
fi

pb_val_bad=0
for f in "$REPO"/docs/manifests/*.manifest.yml; do
  _proj="$(mktemp -d "$TMP/pbproj.XXXXXX")"
  _copy="$TMP/$(basename "$f")"
  sed "s#^project_root:.*\$#project_root: \"$_proj\"#" "$f" > "$_copy"
  if ! bash "$VAL" "$_copy" >"$TMP/pb-val-err" 2>&1; then
    # Only count it as a regression if the failure mentions risk/task_type — other invariants
    # (e.g. a pre-existing status/gate-count issue) are out of this feature's scope.
    if grep -qi 'risk\|task_type' "$TMP/pb-val-err"; then
      pb_val_bad=$((pb_val_bad + 1))
      bad "PB6: $f — manifest-validate.sh now rejects a real manifest over risk/task_type: $(cat "$TMP/pb-val-err")"
    fi
  fi
done
if [ "$pb_val_bad" -eq 0 ]; then
  ok "PB6: manifest-validate.sh's new risk/task_type invariants reject none of the real docs/manifests/ corpus"
fi

# ==================================================================================================
# PC. max() resolution — high + boilerplate -> high — and the absence of a weights table.
# ==================================================================================================
if grep -q 'max(' "$TMP/resolution-section.md" 2>/dev/null; then
  ok "PC1: the resolution section names max() as the combining rule"
else
  bad "PC1: no max( reference found in the resolution section"
fi

if grep -qi 'risk: high' "$TMP/resolution-section.md" 2>/dev/null && grep -qi 'task_type: boilerplate' "$TMP/resolution-section.md" 2>/dev/null && grep -qi 'strict' "$TMP/resolution-section.md" 2>/dev/null; then
  ok "PC2: the worked example (risk: high + task_type: boilerplate -> strict/high) is stated"
else
  bad "PC2: the high + boilerplate -> strict worked example is missing"
fi

if grep -qE '^\|.*[Ww]eight' "$TMP/resolution-section.md" 2>/dev/null; then
  bad "PC3: a markdown table with a weight column exists in the resolution section — ADR-0055 §D3 rejects a numeric weighted score"
else
  ok "PC3: no weights table exists in the resolution section"
fi

if grep -qE '[0-9]\.[0-9]+ *[\*x]' "$TMP/resolution-section.md" 2>/dev/null; then
  bad "PC4: a numeric weight multiplier pattern (e.g. 0.7 *) exists in the resolution section"
else
  ok "PC4: no numeric weight multiplier pattern exists in the resolution section"
fi

if grep -qi 'no weighted score\|no averaging\|no numeric dial' "$TMP/resolution-section.md" 2>/dev/null; then
  ok "PC5: the resolution section states the absence of a weighted score explicitly (guards against §D3 being reopened)"
else
  bad "PC5: the resolution section does not explicitly disclaim a weighted score"
fi

# ==================================================================================================
# PD. The §D4 floor — a light profile never removes a blocking gate.
# ==================================================================================================
FLOOR_NAMES="spec-coverage.sh weakening-scan.sh interface-check.sh"
pd_floor_bad=0
for n in $FLOOR_NAMES; do
  if ! grep -qF "$n" "$TMP/resolution-section.md" 2>/dev/null; then
    pd_floor_bad=$((pd_floor_bad + 1))
    bad "PD1: floor list in the resolution section is missing $n"
  fi
done
if ! grep -qi 'recovery-readiness pre-flight' "$TMP/resolution-section.md" 2>/dev/null; then
  pd_floor_bad=$((pd_floor_bad + 1))
  bad "PD1: floor list in the resolution section is missing the recovery-readiness pre-flight"
fi
if [ "$pd_floor_bad" -eq 0 ]; then
  ok "PD1: the resolution section names all four floor gates (spec-coverage.sh, weakening-scan.sh, interface-check.sh, recovery-readiness pre-flight)"
fi

if grep -qi 'never.*remove\|may not remove\|cannot remove\|never removes' "$TMP/resolution-section.md" 2>/dev/null; then
  ok "PD2: the resolution section states the floor as a 'never removes' rule, not merely a list"
else
  bad "PD2: the floor is not stated as a hard 'never removes' rule"
fi

extract_named_section '#### Recovery-readiness pre-flight' "$TMP/sec-recovery.md"
extract_named_section '#### Anti-test-weakening gate' "$TMP/sec-weakening.md"
extract_named_section '#### Requirement-ID coverage gate' "$TMP/sec-speccov.md"
extract_named_section '#### Interface immutability gate' "$TMP/sec-interface.md"

pd_leak=0
for sec in sec-recovery sec-weakening sec-speccov sec-interface; do
  if [ -s "$TMP/$sec.md" ] && grep -qi 'task_type\|audit profile\|proportional audit' "$TMP/$sec.md"; then
    pd_leak=1
    bad "PD3: $sec's own section text now conditions the gate on the audit profile — the floor must stay unconditional at the gate's own call site"
  fi
done
if [ "$pd_leak" -eq 0 ]; then
  ok "PD3: none of the four floor gates' own SKILL.md sections condition themselves on risk/task_type/the audit profile"
fi

# ==================================================================================================
# PE. Gate 2 proposes and a human confirms (§D5) — the architect proposes, never writes silently.
# ==================================================================================================
if [ -f "$ARCHITECT" ] && grep -qi 'PROPOSED AUDIT PROFILE' "$ARCHITECT"; then
  ok "PE1: architect.md documents a PROPOSED AUDIT PROFILE: report block"
else
  bad "PE1: architect.md has no PROPOSED AUDIT PROFILE: block"
fi

if [ -f "$ARCHITECT" ] && grep -qi 'propose, never write' "$ARCHITECT"; then
  ok "PE2: architect.md states the propose-never-write contract for the audit profile (same as the protected-interface proposal)"
else
  bad "PE2: architect.md does not state 'propose, never write' near the audit-profile bullet"
fi

if [ -f "$ARCHITECT" ]; then
  wscope_line="$(grep -i 'write scope' "$ARCHITECT" | tail -1)"
  if printf '%s' "$wscope_line" | grep -qi 'manifest'; then
    bad "PE3: architect.md's write-scope line now mentions the manifest — the architect must not be able to write it"
  else
    ok "PE3: architect.md's write-scope line still excludes the manifest (docs/architecture, docs/superpowers/plans only)"
  fi
fi

# VCS-048/ADR-0175: ## 5. HITL gates (Gate 2's audit-profile block) moved into
# references/hitl-gates.md.
if grep -qi 'PROPOSED AUDIT PROFILE' "$HITL_REF" 2>/dev/null; then
  ok "PE4: SKILL.md's Gate 2 block references the architect's PROPOSED AUDIT PROFILE: block"
else
  bad "PE4: SKILL.md's Gate 2 section does not reference PROPOSED AUDIT PROFILE:"
fi

if grep -qi 'ADR-0055 §D5\|ADR-0055 §D5)' "$HITL_REF" 2>/dev/null; then
  ok "PE5: SKILL.md's Gate 2 section cites ADR-0055 §D5 (operator confirms, not auto-derived)"
else
  bad "PE5: SKILL.md does not cite ADR-0055 §D5 near the Gate 2 audit-profile block"
fi

gate2_section="$(awk '/^\*\*Gate 2 — Architecture review/{f=1} f{print} f && /^\*\*Gate 3/{exit}' "$HITL_REF" 2>/dev/null)"
if printf '%s' "$gate2_section" | grep -qi 'risk: null\|task_type: null'; then
  ok "PE6: Gate 2's own block shows the sed substitution that writes risk/task_type into the manifest ONLY after the gate's approval"
else
  bad "PE6: Gate 2's block does not show the orchestrator writing risk/task_type after confirmation"
fi

# ==================================================================================================
# PF. Grove's five delegation factors map onto the two axes, no third field (§D6).
# ==================================================================================================
GROVE_TERMS="reversibility novelty regulatory"
pf_bad=0
for t in $GROVE_TERMS; do
  if ! grep -qi "$t" "$ARCHITECT" 2>/dev/null; then
    pf_bad=$((pf_bad + 1))
    bad "PF1: architect.md's audit-profile bullet is missing the Grove factor '$t'"
  fi
done
if [ "$pf_bad" -eq 0 ]; then
  ok "PF1: architect.md's audit-profile bullet names Grove's delegation factors (risk of harm, reversibility, novelty/familiarity, regulatory exposure, performance sensitivity)"
fi

if grep -qi 'no third field\|never a third field' "$ARCHITECT" 2>/dev/null; then
  ok "PF2: architect.md states explicitly that Grove's factors fold onto the two axes, not a third field"
else
  bad "PF2: 'no third field' statement not found in architect.md"
fi

# PF3 originally pinned to the raw invariant number 18 as a proxy for "no third field". That
# proxy broke on the first unrelated feature to need the next sequential invariant number
# (issue #111 / ADR-0057's Invariant 18, for tracer_bullet_mode — nothing to do with ADR-0055).
# Corrected to check what this test actually means: exactly two invariants tagged ADR-0055.
adr55_invariant_count=$(grep -c '(conditional, ADR-0055)' "$VAL" 2>/dev/null)
if [ "$adr55_invariant_count" -eq 2 ]; then
  ok "PF3: manifest-validate.sh has exactly two ADR-0055-tagged invariants (risk, task_type) — no third field introduced"
else
  bad "PF3: manifest-validate.sh has $adr55_invariant_count ADR-0055-tagged invariants, expected exactly 2"
fi

if grep -qE '^echo "[a-z_]+: null" >> "\$T"$' "$INIT" 2>/dev/null; then
  third_field_count=$(grep -cE '^echo "(risk|task_type): null" >> "\$T"$' "$INIT" 2>/dev/null)
  if [ "$third_field_count" -eq 2 ]; then
    ok "PF4: manifest-init.sh writes exactly two new null-default fields (risk, task_type)"
  else
    bad "PF4: expected exactly 2 new risk/task_type null-default lines in manifest-init.sh, found $third_field_count"
  fi
else
  bad "PF4: manifest-init.sh has no null-default field lines matching the risk/task_type pattern at all"
fi

# ==================================================================================================
# PG. Registration in both CI registries (Task 6).
# ==================================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]proportional-audit-depth[[:space:];]'; then
  ok "PG1: docs-ci.yml's shell-tests loop list runs proportional-audit-depth"
else
  bad "PG1: proportional-audit-depth is not in docs-ci.yml's explicit harness list — append it after project-ci-checks"
fi
REMAINDER=$(printf '%s' "$DOCSCI_LOOP" | sed 's/.*project-ci-checks//')
if printf '%s' "$REMAINDER" | grep -qE '[[:space:]]proportional-audit-depth[[:space:];]'; then
  ok "PG2: proportional-audit-depth is registered AFTER project-ci-checks, as the DoD specifies"
else
  bad "PG2: proportional-audit-depth is not positioned after project-ci-checks in docs-ci.yml's list"
fi

# PG3 removed (ADR-0193): ci.yml, the second registry this pinned, was deleted — docs-ci.yml's
# shell-tests list above (PG1/PG2) is now the only harness runner, and pairs-completeness.test.sh's
# CI3 asserts exactly one workflow executes the suite.

# ==================================================================================================
echo "----------------------------------------"
echo "proportional-audit-depth.test.sh: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
