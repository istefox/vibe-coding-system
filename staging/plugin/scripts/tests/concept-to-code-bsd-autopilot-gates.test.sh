#!/bin/bash
# concept-to-code-bsd-autopilot-gates test harness (ADR-0027) — Findings 1-5 from the
# concept-to-code audit (SPEC.md / issue #31). Four lettered sections:
#   Section A (Finding 1, 3 tests) — Step 1's "stamp slug marker" command must be BSD-safe
#     (awk + temp-file + mv, not GNU sed's a\ one-liner extension). A1/A2 are static text
#     anchors against SKILL.md. A3 is a live extract-and-execute test against a fixture
#     SPEC.md, disclosed as a forward-correctness/idempotency regression guard rather than a
#     RED-before/GREEN-after pair on ubuntu-latest CI specifically (GNU sed's a\ one-liner
#     extension is documented to accept this exact syntax, so the bug does not reproduce
#     there) — see ADR-0027 SS2.1/SS2.6. On a real BSD/macOS runner, by contrast, A3 DOES
#     reproduce the bug pre-fix (empirically confirmed during this implementation session,
#     Darwin/BSD sed): the old command exits 1 and never writes the marker, so A3 is
#     genuine RED here too until Task 2 lands, not merely a non-regression companion — this
#     is the platform-specific failure the P1 finding is about, observed directly rather
#     than assumed.
#   Section B (Findings 2+3, 4 tests) — autopilot must never grant TOFU trust unattended
#     (Gate 2b) and must never push unattended (Gate 0d + Step 7). Static anchors only.
#   Section C (Finding 5, 6 tests) — invariant 7 (manifest-validate.sh) must be conditional
#     on chain_path (Express: no artifacts required; Hybrid: spec only; Standard/legacy:
#     spec+adr+plan, unchanged); Gate E3's Abort must transition to aborted, not completed.
#   Section D (Finding 4, 4 tests) — Gate order: step_0_init -> gate_0d_scaffolding -> the
#     path-specific Step 1 state is the single documented routing transition for all three
#     chain_path values; the old direct Gate-0-bypassing fast path must be gone from SS2.
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... — that is the deployed copy, out of scope.
# Bash 3.2 clean. Run: bash concept-to-code-bsd-autopilot-gates.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
SKILL_DIR="$STAGING/plugin/skills/concept-to-code"
SKILL_MD="$SKILL_DIR/SKILL.md"
HITL_REF="$SKILL_DIR/references/hitl-gates.md"
INIT="$SKILL_DIR/scripts/manifest-init.sh"
VAL="$SKILL_DIR/scripts/manifest-validate.sh"
TRN="$SKILL_DIR/scripts/manifest-transition.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# extract_slug_stamp: pulls the fenced bash block under the "Stamp slug marker" heading,
# regardless of the block's list-item indentation (the heading anchor and fence markers are
# unique enough within this file; anchoring the fence regex to column 1 would miss the
# actual 3-space list-item indentation SKILL.md uses here).
extract_slug_stamp() {
  awk '
    /Stamp slug marker/ { grab=1 }
    grab && /```bash/ { infence=1; next }
    grab && infence && /```/ { exit }
    grab && infence { print }
  ' "$SKILL_MD"
}

# =====================================================================================
# Section A -- Finding 1: BSD-safe slug stamp
# =====================================================================================

# A1 (static, genuine RED now): old GNU sed a\ one-liner must be gone.
if grep -qF 'a\\n**Topic slug:**' "$SKILL_MD"; then
  bad "A1: old GNU-only sed a\\ one-liner slug stamp is still present in SKILL.md"
else
  ok "A1: old GNU-only sed a\\ one-liner slug stamp is gone from SKILL.md"
fi

# A2 (static, genuine RED now): new portable awk replacement must be present.
if grep -qF 'awk -v slug=' "$SKILL_MD"; then
  ok "A2: new awk -v slug= replacement is present in SKILL.md"
else
  bad "A2: new awk -v slug= replacement not found in SKILL.md"
fi

# A3 (dynamic): live extract-and-execute against a fixture SPEC.md. Forward-correctness and
# idempotency regression guard for whichever slug-stamp command is currently in SKILL.md —
# see file header for why this is not a uniform RED-before/GREEN-after pair across runners.
FIXTURE_DIR="$TMP/a3"
mkdir -p "$FIXTURE_DIR"
printf '# Some Feature Title\n\nBody text.\n' > "$FIXTURE_DIR/SPEC.md"

RAW="$(extract_slug_stamp)"
CMD="${RAW//<project-root>/$FIXTURE_DIR}"
CMD="${CMD//<topic-slug>/test-topic-slug}"
printf '%s\n' "$CMD" > "$TMP/stamp-cmd.sh"

if bash "$TMP/stamp-cmd.sh" && grep -q '\*\*Topic slug:\*\* test-topic-slug' "$FIXTURE_DIR/SPEC.md"; then
  EXPECTED="$TMP/a3-expected"
  printf '# Some Feature Title\n\n**Topic slug:** test-topic-slug\n' > "$EXPECTED"
  ACTUAL="$TMP/a3-actual"
  awk 'NR==1,NR==3' "$FIXTURE_DIR/SPEC.md" > "$ACTUAL"
  if diff -q "$EXPECTED" "$ACTUAL" >/dev/null 2>&1; then
    BEFORE_COPY="$TMP/a3-before-rerun"
    cp "$FIXTURE_DIR/SPEC.md" "$BEFORE_COPY"
    bash "$TMP/stamp-cmd.sh"
    if diff -q "$BEFORE_COPY" "$FIXTURE_DIR/SPEC.md" >/dev/null 2>&1; then
      ok "A3: slug stamp command inserts the marker correctly and is idempotent on re-run"
    else
      bad "A3: slug stamp command is not idempotent -- file changed on second run"
    fi
  else
    bad "A3: marker not inserted in the expected position (H1, blank line, marker)"
  fi
else
  bad "A3: slug stamp command failed to run or did not write the marker"
fi

# A4 (dynamic, issue #408/#376): a SPEC whose PROSE mentions the marker mid-line, rather than
# carrying it as a column-0 field, must still be stamped. The old `grep -q '\*\*Topic slug:\*\*'`
# guard was file-wide and unanchored (rule 12): a SPEC documenting this very defect satisfies its
# own explanation and is never stamped, which is what produces spec_topic_slug=unknown downstream.
FIXTURE_DIR_A4="$TMP/a4"
mkdir -p "$FIXTURE_DIR_A4"
printf '# A SPEC about the stamp guard\n\nSee the **Topic slug:** marker convention.\n' > "$FIXTURE_DIR_A4/SPEC.md"

RAW_A4="$(extract_slug_stamp)"
CMD_A4="${RAW_A4//<project-root>/$FIXTURE_DIR_A4}"
CMD_A4="${CMD_A4//<topic-slug>/test-topic-slug}"
printf '%s\n' "$CMD_A4" > "$TMP/stamp-cmd-a4.sh"

bash "$TMP/stamp-cmd-a4.sh"
if grep -qE '^\*\*Topic slug:\*\* test-topic-slug$' "$FIXTURE_DIR_A4/SPEC.md"; then
  ok "A4: a SPEC whose prose mentions the marker mid-line is still stamped (#408/#376)"
else
  bad "A4: the stamp guard's own prose mention satisfied it and the marker was never inserted"
fi

# =====================================================================================
# Section D -- Finding 4: Gate order (step_0_init -> gate_0d_scaffolding -> path Step 1)
# =====================================================================================

# mk_manifest_fixture <slug> <chain_path> -- fresh mktemp -d project dir, manifest-init.sh,
# then patches chain_path: null -> chain_path: "<chain_path>" via the exact sed shape
# SKILL.md's own Gate 0 click handler uses. Sets FIX_MANIFEST for the caller.
mk_manifest_fixture() {
  _slug="$1"; _cp="$2"
  _proj="$(mktemp -d "$TMP/proj-$_slug.XXXXXX")"
  FIX_MANIFEST="$(bash "$INIT" "$_slug" "Test $_slug" "$_proj")"
  sed -i.bak "s/^chain_path: null\$/chain_path: \"$_cp\"/" "$FIX_MANIFEST"
}

# D1 (dynamic, non-regression/mechanical proof -- expected already passing): standard.
mk_manifest_fixture "d1-standard" "standard"
MD1="$FIX_MANIFEST"
bash "$TRN" "$MD1" gate_0d_scaffolding; rc1=$?
bash "$TRN" "$MD1" step_1_interview; rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
  ok "D1: standard -- step_0_init -> gate_0d_scaffolding -> step_1_interview both legal (manifest-transition.sh unmodified)"
else
  bad "D1: standard routing sequence failed (gate_0d_scaffolding rc=$rc1, step_1_interview rc=$rc2)"
fi

# D2 (dynamic, same category): express.
mk_manifest_fixture "d2-express" "express"
MD2="$FIX_MANIFEST"
bash "$TRN" "$MD2" gate_0d_scaffolding; rc1=$?
bash "$TRN" "$MD2" step_e1_plan; rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
  ok "D2: express -- step_0_init -> gate_0d_scaffolding -> step_e1_plan both legal (manifest-transition.sh unmodified)"
else
  bad "D2: express routing sequence failed (gate_0d_scaffolding rc=$rc1, step_e1_plan rc=$rc2)"
fi

# D3 (dynamic, same category): hybrid.
mk_manifest_fixture "d3-hybrid" "hybrid"
MD3="$FIX_MANIFEST"
bash "$TRN" "$MD3" gate_0d_scaffolding; rc1=$?
bash "$TRN" "$MD3" step_h1_interview; rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
  ok "D3: hybrid -- step_0_init -> gate_0d_scaffolding -> step_h1_interview both legal (manifest-transition.sh unmodified)"
else
  bad "D3: hybrid routing sequence failed (gate_0d_scaffolding rc=$rc1, step_h1_interview rc=$rc2)"
fi

# D4 (static, genuine RED now): the old fast-path bypass phrase must be gone from SS2 Form A.
if grep -qF '`express` → transition `step_0_init → step_e1_plan`' "$SKILL_MD"; then
  bad "D4: old Gate-0-bypassing fast-path phrase is still present in SS2 Form A"
else
  ok "D4: old Gate-0-bypassing fast-path phrase is gone from SS2 Form A"
fi

# =====================================================================================
# Section B -- Findings 2+3: autopilot no-unattended-trust / no-unattended-push
# =====================================================================================
# All four are static text anchors against SKILL.md -- no subprocess execution.

# B1 (static, genuine RED now): Gate 2b's autopilot bracket must not call approve-test-cmd.sh
# unconditionally.
if grep -qF '"Approve" → run `approve-test-cmd.sh` and proceed' "$SKILL_MD"; then
  bad "B1: Gate 2b autopilot bracket still calls approve-test-cmd.sh unconditionally"
else
  ok "B1: Gate 2b autopilot bracket no longer calls approve-test-cmd.sh unconditionally"
fi

# B2 (static, genuine RED now): the TRUSTED/NOT_TRUSTED probe must be present.
# VCS-048/ADR-0175: Gate 2b moved into references/hitl-gates.md.
if grep -qF 'NOT_TRUSTED → autopilot must never establish trust unattended' "$HITL_REF"; then
  ok "B2: Gate 2b autopilot bracket probes pre-existing trust (TRUSTED/NOT_TRUSTED)"
else
  bad "B2: Gate 2b autopilot bracket does not yet probe pre-existing trust"
fi

# B3 (static, genuine RED now): Gate 0d's autopilot bracket must not condition push on remote
# presence. Compound anchor deliberate -- see file header / ADR-0027 SS2.6 for why a bare
# 'initial_commit_push: "push"' substring would also match the legitimate interactive Q4
# option and never be satisfiable as an anchor.
if grep -qF '`_git_remote` non-empty → `initial_commit_push: "push"`' "$SKILL_MD"; then
  bad "B3: Gate 0d autopilot bracket still conditions push on remote presence"
else
  ok "B3: Gate 0d autopilot bracket no longer conditions push on remote presence"
fi

# B4 (static, genuine RED now): Step 7's push trigger must add the autopilot guard clause.
if grep -qF 'AND manifest.autopilot != true' "$SKILL_MD"; then
  ok "B4: Step 7 push trigger has the autopilot guard clause"
else
  bad "B4: Step 7 push trigger is missing the autopilot guard clause"
fi

# =====================================================================================
# Section C -- Finding 5: invariant 7 conditional on chain_path + Gate E3 Abort split
# =====================================================================================

# mk_c_fixture <slug> -- fresh mktemp -d project dir + manifest-init.sh, no field patches.
# Sets FIX_MANIFEST for the caller. chain_path/status/artifacts.spec patched separately by
# the caller via the patch_* helpers below, so each C-test can compose exactly the fields it
# needs (unlike Section D's mk_manifest_fixture, which always patches chain_path).
mk_c_fixture() {
  _slug="$1"
  _proj="$(mktemp -d "$TMP/proj-$_slug.XXXXXX")"
  FIX_MANIFEST="$(bash "$INIT" "$_slug" "Test $_slug" "$_proj")"
}
patch_chain_path() {
  sed -i.bak "s/^chain_path: null\$/chain_path: \"$2\"/" "$1"
}
patch_status_completed() {
  sed -i.bak 's/^status: .*/status: "completed"/' "$1"
}
patch_spec_artifact() {
  sed -i.bak 's|^  spec: null|  spec: "/tmp/SPEC.md"|' "$1"
}

# C1 (dynamic, genuine RED now): express + completed + null artifacts -- must validate PASS.
mk_c_fixture "c1-express"
M1="$FIX_MANIFEST"
patch_chain_path "$M1" "express"
patch_status_completed "$M1"
if bash "$VAL" "$M1"; then
  ok "C1: express + completed + null artifacts -- validate PASS (invariant 7 skips express)"
else
  bad "C1: express + completed + null artifacts -- validate FAILs (invariant 7 still unconditional)"
fi

# C2 (dynamic, non-regression companion -- expected already passing, must stay failing after
# Task 8 too): standard/legacy (chain_path stays null) + completed + null artifacts -- must
# still validate FAIL.
mk_c_fixture "c2-standard"
M2="$FIX_MANIFEST"
patch_status_completed "$M2"
if bash "$VAL" "$M2"; then
  bad "C2: standard/legacy + completed + null artifacts -- validate unexpectedly PASSed"
else
  ok "C2: standard/legacy + completed + null artifacts -- validate correctly FAILs (guard against Task 8 over-relaxing Standard)"
fi

# C3 (dynamic, genuine RED now): hybrid + completed + spec set (adr/plan null) -- must
# validate PASS (narrower carve-out than express's blanket skip).
mk_c_fixture "c3-hybrid"
M3="$FIX_MANIFEST"
patch_chain_path "$M3" "hybrid"
patch_status_completed "$M3"
patch_spec_artifact "$M3"
if bash "$VAL" "$M3"; then
  ok "C3: hybrid + completed + spec set (adr/plan null) -- validate PASS"
else
  bad "C3: hybrid + completed + spec set -- validate FAILs (invariant 7 still requires adr/plan)"
fi

# C4 (dynamic, non-regression companion -- expected already passing, must stay failing after
# Task 8 too): hybrid + completed + spec ALSO null -- must still validate FAIL (proves the
# hybrid carve-out is narrower than express's, not a second blanket skip).
mk_c_fixture "c4-hybrid-nospec"
M4="$FIX_MANIFEST"
patch_chain_path "$M4" "hybrid"
patch_status_completed "$M4"
if bash "$VAL" "$M4"; then
  bad "C4: hybrid + completed + spec also null -- validate unexpectedly PASSed"
else
  ok "C4: hybrid + completed + spec also null -- validate correctly FAILs (hybrid still requires spec)"
fi

# C5 (static, genuine RED now): Gate E3's Commit later / Abort must no longer share one
# transition block.
if grep -qF '`Commit later` / `Abort`:' "$SKILL_MD"; then
  bad "C5: Gate E3 still shares one label/transition block for Commit later and Abort"
else
  ok "C5: Gate E3's Commit later and Abort blocks are split"
fi

# C6 (dynamic, non-regression/mechanical proof -- expected already passing): fresh manifest,
# no chain_path/status patch needed, straight to aborted -- must be legal and validate clean.
mk_c_fixture "c6-abort"
M6="$FIX_MANIFEST"
if bash "$TRN" "$M6" aborted aborted \
  && grep -q '^status: "aborted"$' "$M6" \
  && bash "$VAL" "$M6"; then
  ok "C6: fresh manifest -> aborted transition is legal and validates clean (manifest-transition.sh unmodified)"
else
  bad "C6: aborted transition or the resulting manifest's validation failed"
fi

# =====================================================================================
# Section G -- issue #329 / ADR-0115: Gate 0's autopilot default, and the class guard
# =====================================================================================
#
# THE INSTANCE. SS5 opens with a contract -- "when autopilot = true, every gate listed below
# skips its AskUserQuestion and auto-selects the safe default ... listed inline as
# [Autopilot default: ...]" -- and Gate 0, the chain's FIRST gate, carried no such block. An
# unattended run raised a question nobody could answer at the first gate of every feature.
#
# THE CLASS. Nothing asserted that contract anywhere in the harness: grepping all of
# staging/plugin/scripts/tests for "Autopilot default" returned ZERO hits before this section,
# which is why one missing block survived fourteen present ones. G2 derives the gate population
# from SS5 at run time and requires each gate to carry a marker OR declare an exemption in
# SKILL.md itself. Instance 10 of the derived-guard pattern; deliberately NOT extracted into a
# shared helper (ADR-0086 -- its own population, its own question, and six copies giving six
# different answers is not a defect here because they are six different questions).
#
# TWO MARKER SPELLINGS, ON PURPOSE. Gate 4 uses "[Autopilot bypass:" because it skips the gate
# outright where the others auto-select an option inside it, AND because
# recovery-preflight.test.sh (assertions RH4 and RI1) uses "^\*\*\[Autopilot bypass" as an
# EXTRACTION BOUNDARY. Normalising the spelling would break two extractions in another file.
# G3b pins it.

CONDUCTOR_MD="$STAGING/plugin/skills/project-conductor/SKILL.md"
CONDUCTOR_REF="$STAGING/plugin/skills/project-conductor/references/steps-4-7-chain-execution.md"

# flat_skill: whitespace-flattened, undecorated, lowercased copy for PROSE needles only.
# A clause is the same clause whether it wraps, whether a word inside it is backticked or
# bolded, and whether it opens a sentence (ADR-0073 / ADR-0076 / ADR-0080 / ADR-0098 -- four
# recorded instances of an assertion failing on correct text because of decoration).
# STRUCTURAL markers stay line-based below: a marker split across two lines is a marker the
# derivation cannot see, and flattening would hide exactly the defect being guarded.
# VCS-048/ADR-0175: ## 5. HITL gates moved into references/hitl-gates.md — flatten both files,
# not just SKILL.md (population-glob coupling).
FLAT_SKILL="$TMP/skill-flat.txt"
cat "$SKILL_MD" "$HITL_REF" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | tr -d '`*' | tr '[:upper:]' '[:lower:]' > "$FLAT_SKILL"
FLAT_COND="$TMP/cond-flat.txt"
# VCS-049: Step 4 through Step 7 moved into references/steps-4-7-chain-execution.md — flatten
# both files, not just SKILL.md (same population-glob coupling class as FLAT_SKILL above).
cat "$CONDUCTOR_MD" "$CONDUCTOR_REF" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | tr -d '`*' | tr '[:upper:]' '[:lower:]' > "$FLAT_COND"

flat_has() { grep -qF "$1" "$FLAT_SKILL"; }

# gate_block <gate-id>: the SS5 text from this gate's heading to the next gate heading.
# VCS-048/ADR-0175: ## 5. HITL gates moved into references/hitl-gates.md; the reference file's
# body IS the block, so no awk range is needed any more.
GATES_TXT="$TMP/gates.txt"
cp "$HITL_REF" "$GATES_TXT" 2>/dev/null
gate_ids() {
  grep -E '^\*\*Gate [0-9A-Za-z.]+ *[—-]' "$GATES_TXT" \
    | sed -E 's/^\*\*Gate ([0-9A-Za-z.]+) *[—-].*/\1/'
}
gate_block() {
  awk -v want="$1" '
    /^\*\*Gate [0-9A-Za-z.]+ *[—-]/ {
      id=$0; sub(/^\*\*Gate /,"",id); sub(/ *[—-].*/,"",id)
      grab = (id == want) ? 1 : 0
      if (grab) next
    }
    grab { print }
  ' "$GATES_TXT"
}

GATE_IDS=$(gate_ids)
GATE_N=$(printf '%s\n' "$GATE_IDS" | sed '/^$/d' | wc -l | tr -d ' ')

# G0 (denominator guard): the derivation must resolve. A heading pattern that stops matching
# empties GATE_IDS, and an empty population makes G1/G2/G2b/G2c all pass vacuously -- which
# reads exactly like full coverage (pairs-completeness self-test-2's lesson, reapplied).
if [ "$GATE_N" -ge 15 ]; then
  ok "G0: SS5 gate derivation resolved $GATE_N gates (>= 15 expected)"
else
  bad "G0: SS5 gate derivation returned only $GATE_N gates -- the heading pattern stopped matching"
fi

# G1 (static, genuine RED now): Gate 0 must carry an autopilot marker naming standard.
G0_BLOCK=$(gate_block "0")
G0_MARKER=$(printf '%s\n' "$G0_BLOCK" | grep -E '\*\*\[Autopilot (default|bypass):')
# NOTE for whoever edits this: match "standard" against the marker LINE, never with a bounded
# `[^]]*` run after the colon. The marker opens with `[s]`, so a `]`-terminated run stops three
# characters in and reports a correct marker as missing its value -- seen RED here first.
if [ -n "$G0_MARKER" ]; then
# The needle is the ASSIGNMENT the marker instructs, not the bare word "standard": that word
# appears five times in this one marker line (the option label, the value, the "only standard is
# unattended-safe" argument), so mutating any single occurrence leaves the others and the plant
# does not fire. Seen here, on the first plant-check run.
# plant: G1 | plugin/skills/concept-to-code/references/hitl-gates.md | Set `chain_path: standard`, emit | Set `chain_path: hybrid`, emit
  if printf '%s\n' "$G0_MARKER" | grep -qF 'chain_path: standard'; then
    ok "G1: Gate 0's autopilot marker sets chain_path: standard"
  else
    bad "G1: Gate 0 has an autopilot marker but it does not set chain_path: standard"
  fi
else
  bad "G1: Gate 0 carries NO autopilot marker -- issue #329, the unattended chain stalls here"
fi

# G1b (static): the default must NOT be "take the auto-detect vote". hybrid reaches Step H1,
# which invokes interview-driver UNCONDITIONALLY (unlike standard Step 1, it has no brownfield
# skip), and express reaches plan mode. Only standard is unattended-safe, which is what the
# [auto] option's own label already said ("brownfield only").
# plant: G1b | plugin/skills/concept-to-code/references/hitl-gates.md | It is NOT the auto-detect vote | It is exactly the auto-detect vote
if flat_has 'it is not the auto-detect vote'; then
  ok "G1b: Gate 0's default states it is not the auto-detect vote, with the reason"
else
  bad "G1b: Gate 0's default does not rule out the auto-detect vote"
fi

# G2 (class guard, derived): every SS5 gate carries a marker or declares an exemption.
G2_MISSING=""
for _g in $GATE_IDS; do
  _blk=$(gate_block "$_g")
  printf '%s\n' "$_blk" | grep -qE '\*\*\[Autopilot (default|bypass):' && continue
  printf '%s\n' "$_blk" | grep -qF '<!-- autopilot-gate-exempt:' && continue
  G2_MISSING="$G2_MISSING $_g"
done
# The plant must remove the MARKER, not reword the reason: replacing prose inside an exemption
# leaves the exemption standing and G2 keeps passing. The mechanism is the marker (rule 12).
# plant: G2 | plugin/skills/concept-to-code/references/hitl-gates.md | <!-- autopilot-gate-exempt: raises no AskUserQuestion at all | <!-- note: raises no AskUserQuestion at all
if [ -z "$G2_MISSING" ]; then
  ok "G2: all $GATE_N SS5 gates carry an autopilot marker or a declared exemption"
else
  bad "G2: SS5 gate(s) with neither an autopilot marker nor an exemption:$G2_MISSING"
fi

# G2b (reverse direction): an exemption on a gate that ALSO has a marker is stale, and stale
# reads as clean (ADR-0081 ZA4). Run the check backwards or a waiver outlives its subject.
G2B_STALE=""
for _g in $GATE_IDS; do
  _blk=$(gate_block "$_g")
  printf '%s\n' "$_blk" | grep -qF '<!-- autopilot-gate-exempt:' || continue
  printf '%s\n' "$_blk" | grep -qE '\*\*\[Autopilot (default|bypass):' \
    && G2B_STALE="$G2B_STALE $_g"
done
# A NEGATIVE assertion: deleting a mechanism cannot break "X must not happen", so the plant has
# to REINTRODUCE the banned thing rather than remove something (ADR-0112 -- five of fifteen
# plants there did not fire for exactly this reason). Here that means bolting an exemption onto
# a gate that already has a marker, on one line, since a replacement cannot contain a newline.
# plant: G2b | plugin/skills/concept-to-code/references/hitl-gates.md | "Gate 1b: autopilot — skip brainstorm ✓"]** | "Gate 1b: autopilot — skip brainstorm ✓"]** <!-- autopilot-gate-exempt: a deliberately stale waiver planted to prove G2b runs backwards -->
if [ -z "$G2B_STALE" ]; then
  ok "G2b: no gate carries both a marker and an exemption (no stale waiver)"
else
  bad "G2b: gate(s) carrying BOTH a marker and an exemption -- the waiver is stale:$G2B_STALE"
fi

# G2c: every exemption reason is >= 40 chars and lives on ONE line. A reason wrapped across
# lines is a prose assertion that depends on where the text breaks -- the same family as the
# four decoration failures cited above, met on the waiver side.
# The declarations are collected PER GATE, not by grepping SS5 whole. The contract paragraph
# above the first gate documents the marker with a literal `<reason>` placeholder, and a flat
# grep counts that template as a declaration -- rule 12, the needle matching the prose that
# describes the mechanism. Deriving per gate excludes it structurally instead of blacklisting
# the placeholder string, which would only work until someone reworded the contract.
G2C_DECLS="$TMP/exempt-decls.txt"
: > "$G2C_DECLS"
for _g in $GATE_IDS; do
  gate_block "$_g" | grep -F '<!-- autopilot-gate-exempt:' >> "$G2C_DECLS"
done
G2C_SHORT=""
G2C_N=0
while IFS= read -r _line; do
  [ -n "$_line" ] || continue
  G2C_N=$((G2C_N+1))
  _reason=$(printf '%s' "$_line" | sed -E 's/.*<!-- autopilot-gate-exempt:[[:space:]]*//; s/[[:space:]]*-->.*//')
  [ "${#_reason}" -ge 40 ] || G2C_SHORT="$G2C_SHORT [${_reason}]"
done < "$G2C_DECLS"
# plant: G2c | plugin/skills/concept-to-code/references/hitl-gates.md | a container heading only — sub-gates 2a, 2b and 2c are what actually prompt, and each carries its own autopilot default | too short
if [ "$G2C_N" -eq 0 ]; then
  bad "G2c: no autopilot-gate-exempt declaration found -- G2/G2b are vacuous on the waiver side"
elif [ -z "$G2C_SHORT" ]; then
  ok "G2c: all $G2C_N exemption reasons are >= 40 chars on one line"
else
  bad "G2c: exemption reason(s) shorter than 40 chars or wrapped:$G2C_SHORT"
fi

# G3 (static): the contract paragraph must name BOTH marker spellings, or the class guard
# above is enforcing a rule the contract does not state.
# plant: G3 | plugin/skills/concept-to-code/references/hitl-gates.md | **[Autopilot bypass: ...]** — the gate is skipped outright | **[Autopilot skip]** — the gate is skipped outright
if flat_has '[autopilot default: ...]' && flat_has '[autopilot bypass: ...]'; then
  ok "G3: the SS5 autopilot contract names both marker spellings"
else
  bad "G3: the SS5 autopilot contract does not name both [Autopilot default:] and [Autopilot bypass:]"
fi

# G3b (cross-file coupling): Gate 4's marker must stay byte-identical as "**[Autopilot bypass".
# recovery-preflight.test.sh assertions RH4 and RI1 use it as an awk extraction boundary --
# named by ANCHOR, never by line number (ADR-0082).
# Scoped to GATE 4's OWN BLOCK, never to the file: the contract paragraph above now also
# contains the literal `**[Autopilot bypass:` while documenting the form, so a whole-file grep
# stays green after the marker is renamed at the one site that matters. Rule 12, caught by the
# plant below rather than by reading.
# plant: G3b | plugin/skills/concept-to-code/references/hitl-gates.md | **[Autopilot bypass: if `manifest.autopilot = true`, skip AskUserQuestion entirely | **[Autopilot default: if `manifest.autopilot = true`, skip AskUserQuestion entirely
if gate_block "4" | grep -qF '**[Autopilot bypass:' \
  && grep -qF 'Autopilot bypass' "$SCRIPTS/tests/recovery-preflight.test.sh"; then
  ok "G3b: Gate 4's '**[Autopilot bypass' marker is intact (recovery-preflight RH4/RI1 extract on it)"
else
  bad "G3b: Gate 4's marker or recovery-preflight.test.sh's extraction boundary has moved"
fi

# --- The step 7b pre-flight fence: extracted by its marker, and EXECUTED (ADR-0083) ---------
#
# It is a CHECKER: the caller branches on the exit code. 0 = proceed (attended, or autopilot
# with a routing that can complete unattended), 1 = ABORT the chain, 3 = the check DID NOT RUN.
# 3 is separate from 1 for the reason this repository keeps rediscovering: a check that could
# not look must not read as a check that found nothing.
PREFLIGHT_ID="c2c-autopilot-routing-preflight"
# The anchor is written out LITERALLY here, not assembled from $PREFLIGHT_ID: that literal is
# what `fence-contract-coverage.test.sh` F4 accepts as proof a contract is actually RUN rather
# than merely mentioned, and a string built at run time satisfies no needle. Keep the two in
# agreement — G4 fails loudly if the marker and this anchor diverge.
PREFLIGHT_ANCHOR="fence-contract: c2c-autopilot-routing-preflight -->"
extract_preflight() {
  awk -v anchor="$PREFLIGHT_ANCHOR" '
    # The closing " -->" is part of the anchor on purpose: a bare substring test still matches a
    # marker that has been RENAMED by appending to the id, so the G4 plant would not fire.
    index($0, anchor) { grab=1; next }
    grab && /```bash/ { infence=1; next }
    grab && infence && /```/ { exit }
    grab && infence { print }
  ' "$SKILL_MD"
}
PF_RAW=$(extract_preflight)
PF_SH="$TMP/preflight.sh"
# Point the fence's own script-root assignment at staging instead of the deployed ~/.claude
# copy: this harness must never read $HOME (see the file header).
#
# THE ANCHOR IS INDENTATION-TOLERANT ON PURPOSE. The fence sits inside a numbered list item, so
# every line carries three leading spaces, and a `^_c2c=` anchor silently matches nothing --
# leaving the fence pointed at the DEPLOYED copy while G5..G8 still went green, which is exactly
# the $HOME dependency this file's header forbids. Seen here first, on the first run.
rewrite_c2c() { sed -E "s#^([[:space:]]*)_c2c=.*#\\1_c2c=\"$1\"#"; }
printf '%s\n' "$PF_RAW" | rewrite_c2c "$SKILL_DIR/scripts" > "$PF_SH"

# G4b: the rewrite must actually have landed, or every execution below tests ~/.claude.
# plant: G4b | plugin/skills/concept-to-code/SKILL.md | _c2c="$HOME/.claude/skills/concept-to-code/scripts" | export _c2c="$HOME/.claude/skills/concept-to-code/scripts"
if grep -qF "_c2c=\"$SKILL_DIR/scripts\"" "$PF_SH" && ! grep -qF 'HOME/.claude' "$PF_SH"; then
  ok "G4b: the fence's script root was redirected to staging (no \$HOME left in the extract)"
else
  bad "G4b: the fence still points at \$HOME/.claude -- G5..G9 would test the deployed copy"
fi

# run_preflight <manifest> <project-root> [<script-root-override>]
run_preflight() {
  _pf_run="$TMP/pf-run-$$.sh"
  if [ -n "${3:-}" ]; then
    rewrite_c2c "$3" < "$PF_SH" > "$_pf_run"
  else
    cp "$PF_SH" "$_pf_run"
  fi
  {
    printf '_man=%s\n_root=%s\n' "'$1'" "'$2'"
    cat "$_pf_run"
  } > "$_pf_run.final"
  PF_OUT=$(bash "$_pf_run.final" 2>&1); PF_RC=$?
}

if [ -z "$PF_RAW" ]; then
  bad "G4: the '$PREFLIGHT_ID' fence is absent from SKILL.md -- G4..G9 cannot run"
  bad "G5: (skipped -- no fence)"
  bad "G6: (skipped -- no fence)"
  bad "G7: (skipped -- no fence)"
  bad "G8: (skipped -- no fence)"
  bad "G9: (skipped -- no fence)"
else
# plant: G4 | plugin/skills/concept-to-code/SKILL.md | fence-contract: c2c-autopilot-routing-preflight | fence-contract: c2c-autopilot-routing-preflight-renamed
  if bash -n "$PF_SH" 2>/dev/null; then
    ok "G4: the '$PREFLIGHT_ID' fence is declared and parses"
  else
    bad "G4: the '$PREFLIGHT_ID' fence does not parse under bash -n"
  fi

  # G5 (attended, the byte-unchanged path): autopilot false -> silent proceed, exit 0.
  mk_c_fixture "g5-attended"
  G5M="$FIX_MANIFEST"; G5R=$(dirname "$(dirname "$(dirname "$G5M")")")
  : > "$G5R/SPEC.md"
  run_preflight "$G5M" "$G5R"
# plant: G5 | plugin/skills/concept-to-code/SKILL.md | echo "AUTOPILOT-PREFLIGHT: NOT-AUTOPILOT — attended run, nothing to check."; exit 0 ;; | exit 1 ;;
  if [ "$PF_RC" -eq 0 ] && printf '%s' "$PF_OUT" | grep -q 'NOT-AUTOPILOT'; then
    ok "G5: autopilot false -> exit 0, reported as an attended run (no behaviour change)"
  else
    bad "G5: autopilot false did not take the no-op branch (rc=$PF_RC): $PF_OUT"
  fi

  # G6 (the autopilot shape): autopilot true + SPEC present + chain_path null -> proceed.
  # null is TOLERATED and the reason is measured: 18 of 41 corpus manifests carry
  # autopilot:true with chain_path:null, all brownfield, all completed. Refusing it would
  # fail the dominant historical shape over a bookkeeping gap, not a routing one.
  mk_c_fixture "g6-autopilot"
  G6M="$FIX_MANIFEST"; G6R=$(dirname "$(dirname "$(dirname "$G6M")")")
  sed -i.bak 's/^autopilot: false$/autopilot: true/' "$G6M"
  : > "$G6R/SPEC.md"
  run_preflight "$G6M" "$G6R"
# plant: G6 | plugin/skills/concept-to-code/SKILL.md | express|hybrid) | express|hybrid|None)
  if [ "$PF_RC" -eq 0 ]; then
    ok "G6: autopilot true + SPEC.md + chain_path null -> exit 0 (null is tolerated)"
  else
    bad "G6: autopilot true with a SPEC and a null chain_path was refused (rc=$PF_RC): $PF_OUT"
  fi

  # G7 (the bad input this exists to catch): autopilot true, no SPEC -> abort naming SPEC.md.
  # Without a SPEC the chain routes greenfield and Step 1 dispatches interview-driver, which
  # is interactive, on a path with nobody to answer it.
  mk_c_fixture "g7-nospec"
  G7M="$FIX_MANIFEST"; G7R=$(dirname "$(dirname "$(dirname "$G7M")")")
  sed -i.bak 's/^autopilot: false$/autopilot: true/' "$G7M"
  rm -f "$G7R/SPEC.md"
  run_preflight "$G7M" "$G7R"
# plant: G7 | plugin/skills/concept-to-code/SKILL.md | if [ ! -f "$_root/SPEC.md" ]; then | if false; then
  if [ "$PF_RC" -eq 1 ] && printf '%s' "$PF_OUT" | grep -q 'SPEC.md'; then
    ok "G7: autopilot true with no SPEC.md -> exit 1, message names SPEC.md"
  else
    bad "G7: autopilot true with no SPEC.md did not abort naming the file (rc=$PF_RC): $PF_OUT"
  fi

  # G7b: the same abort must leave the manifest TERMINAL, not in flight. An in-flight manifest
  # reads ADOPTABLE at project-conductor Step 5 branch C -> RUN-LEVEL HALT, reintroducing the
  # blast radius ADR-0111 (issue #324) had just removed. aborted reads TERMINAL -> contained.
  # The two transition calls in the fence are byte-identical, so the needle carries the line
  # ABOVE it to stay unique -- an exact-one-match requirement the declaration syntax enforces.
# plant: G7b | plugin/skills/concept-to-code/SKILL.md | if [ ! -f "$_root/SPEC.md" ]; then bash "$_c2c/manifest-transition.sh" "$_man" aborted aborted | if [ ! -f "$_root/SPEC.md" ]; then :
  if grep -q '^status: "aborted"$' "$G7M" && bash "$VAL" "$G7M"; then
    ok "G7b: the abort transitioned the manifest to aborted and it still validates"
  else
    bad "G7b: the abort left the manifest in flight -- branch C would halt the whole roadmap"
  fi

  # G8 (interactive routing): autopilot true + chain_path hybrid -> abort naming the path.
  # Corpus impact measured: zero manifests carry autopilot:true with express or hybrid.
  mk_c_fixture "g8-hybrid"
  G8M="$FIX_MANIFEST"; G8R=$(dirname "$(dirname "$(dirname "$G8M")")")
  sed -i.bak 's/^autopilot: false$/autopilot: true/' "$G8M"
  patch_chain_path "$G8M" "hybrid"
  : > "$G8R/SPEC.md"
  run_preflight "$G8M" "$G8R"
# plant: G8 | plugin/skills/concept-to-code/SKILL.md | case "$_cpv" in express|hybrid) | case "$_cpv" in express)
  if [ "$PF_RC" -eq 1 ] && printf '%s' "$PF_OUT" | grep -q 'hybrid'; then
    ok "G8: autopilot true + chain_path hybrid -> exit 1, message names the path"
  else
    bad "G8: autopilot + hybrid was not refused (rc=$PF_RC): $PF_OUT"
  fi

  # G9 (did-not-run, distinct from abort): the field reader is unresolvable -> exit 3, and the
  # message must say the check did not run rather than reporting a verdict it never reached.
  mk_c_fixture "g9-noreader"
  G9M="$FIX_MANIFEST"; G9R=$(dirname "$(dirname "$(dirname "$G9M")")")
  sed -i.bak 's/^autopilot: false$/autopilot: true/' "$G9M"
  : > "$G9R/SPEC.md"
  run_preflight "$G9M" "$G9R" "$TMP/no-such-scripts-dir"
# TWO independent guards produce exit 3 here — the explicit `[ ! -f "$_mfs" ]` test, and the
# `|| { ...; exit 3; }` on the helper call itself. An assertion covered by two guards isolates
# neither (ADR-0104), so this one asserts the MESSAGE the first guard prints: break it and the
# second still exits 3, but says something else. The plant stays on ONE line for the reason
# ADR-0112 records — a replacement cannot contain a newline, and collapsing
# `echo "..."` + `exit 0` into one line makes `exit 0` two arguments to echo, so the branch
# falls through and the plant reports fired without having changed the behaviour it described.
# plant: G9 | plugin/skills/concept-to-code/SKILL.md | if [ ! -f "$_mfs" ]; then | if [ -f "$_mfs" ]; then
  if [ "$PF_RC" -eq 3 ] && printf '%s' "$PF_OUT" | grep -q 'field reader missing'; then
    ok "G9: an unresolvable field reader -> exit 3, named as a missing reader (not as a verdict)"
  else
    bad "G9: an unresolvable field reader did not fail closed as exit 3 (rc=$PF_RC): $PF_OUT"
  fi
fi

# G10 (consolidation): exactly ONE SPEC-existence check may survive on the routing path. The
# check used to live inside the [auto] option, where the fast path and the unattended caller
# both bypass it; two copies of one safety question is the worst available shape, because they
# can disagree about whether the gate fires (ADR-0086's criterion, applied).
# plant: G10 | plugin/skills/concept-to-code/references/hitl-gates.md | **The SPEC.md pre-flight is not here.** | **Autopilot requires an existing SPEC.md (brownfield).**
G10_N=$(grep -cF 'Autopilot requires an existing SPEC.md' "$SKILL_MD" "$HITL_REF" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
if [ "$G10_N" -eq 0 ]; then
  ok "G10: the [auto] option's inline SPEC pre-flight is gone (one check, at step 7b)"
else
  bad "G10: the [auto] option still carries its own SPEC pre-flight ($G10_N occurrence(s))"
fi

# G10b: the [auto] option's description must stop claiming the failure surfaces at Gate 1. It
# aborts at Gate 0's own step, and on a greenfield route Gate 1 is a different gate entirely.
# plant: G10b | plugin/skills/concept-to-code/references/hitl-gates.md | if absent the routing pre-flight at §2 step 7b aborts the chain | if absent the chain errors at Gate 1
if flat_has 'if absent the chain errors at gate 1'; then
  bad "G10b: the [auto] option still claims a missing SPEC 'errors at Gate 1'"
else
  ok "G10b: the [auto] option no longer claims a missing SPEC errors at Gate 1"
fi

# G11 (cross-file, R-03): project-conductor's ADR-0111 paragraph asserted the c2c pre-flight
# does NOT hard-abort at Gate 0. After this feature it does. The paragraph and the code have
# to agree whichever way the decision goes -- that is the issue's own success criterion.
#
# ASSERTED POSITIVELY, not by banning the old sentence. A ban pins yesterday's exact wrong
# wording and passes the moment anyone rewrites it, correctly or not -- ADR-0067's F5 lesson,
# where a guard written against one past error would have fired on the corrected text. Both
# halves are checked: the old claim must be gone AND the new behaviour must be named.
cond_flat_has() { grep -qF "$1" "$FLAT_COND"; }
# plant: G11 | plugin/skills/project-conductor/references/steps-4-7-chain-execution.md | As of issue #329 / ADR-0115 the chain does abort | As of some later work the behaviour changed
if cond_flat_has 'as of issue #329' && cond_flat_has 'the chain does abort'; then
  if grep -qF 'Measured: it does not' "$CONDUCTOR_MD" "$CONDUCTOR_REF" 2>/dev/null; then
    bad "G11: project-conductor names the new behaviour but still carries the old 'it does not' claim"
  else
    ok "G11: project-conductor's hard-abort paragraph agrees with the shipped behaviour"
  fi
else
  bad "G11: project-conductor does not state that the c2c pre-flight now aborts on a missing SPEC"
fi

# G11b: and the SPEC-COPY guard must stay named as the PRIMARY defence. It never creates a
# manifest at all; the c2c abort creates one and then aborts it. Both are contained, one is
# cheaper, and a reader must not conclude the conductor guard is now redundant.
# plant: G11b | plugin/skills/project-conductor/references/steps-4-7-chain-execution.md | this block still runs first and stays primary | this block is now redundant
if cond_flat_has 'stays primary' && cond_flat_has 'do not remove it'; then
  ok "G11b: the conductor's SPEC-COPY guard is stated to stay primary, with a do-not-remove line"
else
  bad "G11b: nothing states that the conductor's SPEC-COPY guard stays primary"
fi

# Z1 (assertion floor): a suite reporting FEWER assertions does not read as broken, and nobody
# watches the count (ADR-0083 SSD3 measured exactly this: six assertions vanished from a
# neighbouring harness and it reported 35 passed / 2 failed, not an error). A floor, not an
# exact count, so adding an assertion needs no bump.
Z1_MIN=30
Z1_TOTAL=$((PASS+FAIL))
if [ "$Z1_TOTAL" -ge "$Z1_MIN" ]; then
  ok "Z1: assertion count $Z1_TOTAL >= floor $Z1_MIN"
else
  bad "Z1: assertion count $Z1_TOTAL is below the floor $Z1_MIN -- assertions have gone missing"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
