#!/bin/bash
# manifest-entry-state.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Run: bash manifest-entry-state.test.sh
#
# Issue #319 / ADR-0109. The chain had two entry points and they refused each other in a loop:
# Form A exits 2 saying *use resume*, Form B answers *resume not necessary, continue in current
# session* — naming a command that does not exist, because the in-session entry point IS Form A.
#
# MEASURED BEFORE DESIGNING (this repository's standing rule), and the issue was true and
# UNDER-STATED in four ways. Each is pinned below rather than left in the ADR:
#   M1  Form A's guard is on FILE EXISTENCE, never state (`manifest-init.sh` `[ -f "$manifest" ]`),
#       so no transition can unblock it and Form C (abort) preserves the file, so it does not
#       either. -> MES8 is the assertion that keeps the Form C case from reading as adoptable.
#   M2  Form B resolved 2 of 13 standard states.
#   M3  THREE states matched no branch at all: `step_4_session_boundary`, `step_6_review`,
#       `step_7_commit`. ADR-0095 disclosed only the second. -> MESB1, MESB2.
#   M4  The boundary state is the one that mattered and was disclosed nowhere: Gate 4's own "Abort
#       chain" message tells the operator to resume from it, and `project-conductor` Step 3 and
#       Step 5 branch B both act on it by invoking Form B. -> MES4, MESB1.
#   M5  Express/Hybrid can never resume at all. -> MES6, MESB4.
#   M6  A COMPLETED chain is deadlocked too: "use resume" <-> "create a new manifest", which Form A
#       refuses. -> MES7.
#
# THE CORPUS CANNOT VALIDATE THIS VALUE DOMAIN, and saying so is better than running the sweep and
# implying it did. ADR-0092 derives a domain by comparing what producers WRITE against what the
# documentation claims. Here the producers are transient chain states: classifying all 42 manifests
# on disk yields 41 TERMINAL and 1 ADOPTABLE, because a STORED manifest corpus is terminal by
# nature. Six tokens are therefore justified by a named state in `manifest-validate.sh`'s enum plus
# a route in `SKILL.md`, and pinned by the fixtures below — never by a corpus frequency.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing.
# plant: MES2 | plugin/skills/concept-to-code/scripts/manifest-entry-state.sh | printf 'ADOPTABLE|%s | printf 'RESUMABLE|%s
# plant: MES4 | plugin/skills/concept-to-code/scripts/manifest-entry-state.sh | printf 'BOUNDARY|%s | printf 'ADOPTABLE|%s
# plant: MES8 | plugin/skills/concept-to-code/scripts/manifest-entry-state.sh | case "$STATUS" in | case "$STEP" in
# plant: MESF2 | plugin/skills/concept-to-code/SKILL.md | manifest-entry-state.sh "$_man" 2>&1 | manifest-entry-state.sh /dev/null 2>&1
# plant: MESB1 | plugin/skills/concept-to-code/SKILL.md | nothing before it needs redoing | it is fine
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
REPO=$(cd "$STAGING/.." && pwd)

ES="$SKILLS/concept-to-code/scripts/manifest-entry-state.sh"
CC="$SKILLS/concept-to-code/SKILL.md"
SYNC="$STAGING/sync-to-claude.sh"
ORPHAN_SLUG="the-sixth-bare-manifest-set-flag-sh-ment"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$ES" ] || { echo "FATAL: missing $ES"; exit 1; }
[ -f "$CC" ] || { echo "FATAL: missing $CC"; exit 1; }

TODAY=$(date +%Y-%m-%d)

# --- fixture base: a REAL manifest that validates -------------------------------------------
# A hand-written minimal manifest trips five unrelated invariants and reports a failure about
# everything except the thing under test (ADR-0078's lesson, learned the same way twice).
BASE=""
for _m in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_m" ] || continue
  if bash "$SKILLS/concept-to-code/scripts/manifest-validate.sh" "$_m" >/dev/null 2>&1; then
    BASE="$_m"; break
  fi
done
if [ -n "$BASE" ]; then ok "MES-BASE fixture base resolved ($(basename "$BASE"))"
else bad "MES-BASE no manifest in the corpus validates — every fixture below is built on nothing"; fi

# mk <name> <current_step> <status> <chain_path> -> echoes the fixture path
mk() {
  _p="$TMP/$1.yml"
  sed -e "s|^current_step:.*|current_step: \"$2\"|" \
      -e "s|^status:.*|status: \"$3\"|" \
      -e "s|^chain_path:.*|chain_path: $4|" "$BASE" >"$_p"
  printf '%s\n' "$_p"
}

# tok <fixture> -> echoes "<rc> <token>"
tok() {
  _o=$(bash "$ES" "$1" 2>/dev/null); _r=$?
  printf '%s %s\n' "$_r" "${_o%%|*}"
}
# full <fixture> -> echoes "<rc> <whole line>"
full() {
  _o=$(bash "$ES" "$1" 2>/dev/null); _r=$?
  printf '%s %s\n' "$_r" "$_o"
}

# ===========================================================================
# Section MES — the classifier, one assertion per token plus its negative twin.
# ===========================================================================
bash -n "$ES" 2>/dev/null && ok "MES0 the classifier parses" \
  || bad "MES0 the classifier does not parse"

if grep -qF 'plugin/skills/concept-to-code/scripts/manifest-entry-state.sh|skills/concept-to-code/scripts/manifest-entry-state.sh' "$SYNC"; then
  ok "MES0b the PAIRS entry exists"
else
  bad "MES0b no PAIRS entry — both call sites invoke ~/.claude/…, so without it the fence exits 127 and the DID-NOT-RUN branch fires on every chain start. pairs-completeness.test.sh cannot see a skill scripts/ file (ADR-0043), so this is the only guard"
fi

R=$(tok "$TMP/definitely-absent.yml")
[ "$R" = "0 NONE" ] && ok "MES1 an absent path is NONE, exit 0 (not exit 3 — see the header)" \
  || bad "MES1 absent path gave '$R', expected '0 NONE'"

# R-03 — the orphan, resolved by the mechanism rather than by hand.
#
# MES2 pins the SHAPE, not the file, and the split is deliberate. The orphan is an untracked file
# whose state is expected to change — Form C sets `status: aborted` on it — and an assertion that
# reads a mutable file as its oracle passes today and fails tomorrow for a CORRECT reason. That is
# a test coupled to housekeeping, which is worse than no test: the next reader cannot tell the
# failure from a regression.
F=$(mk orphan-shape step_0_init in_progress null)
R=$(full "$F")
[ "$R" = "0 ADOPTABLE|step_0_init" ] \
  && ok "MES2 R-03: the orphan's recorded shape classifies ADOPTABLE|step_0_init" \
  || bad "MES2 R-03: the orphan shape gave '$R', expected '0 ADOPTABLE|step_0_init'"

# MES2b reads the REAL file, and asserts the property R-03 actually cares about: whatever state it
# is in, the mechanism REACHES it. Before Form C that is ADOPTABLE (adopt and continue); after Form
# C it is TERMINAL (stop, a second chain is an explicit decision). Both are resolutions. What #319
# produced was neither — a file no entry point could act on at all.
ORPHAN=$(ls "$REPO"/docs/manifests/*-"$ORPHAN_SLUG".manifest.yml 2>/dev/null | head -1)
if [ -n "$ORPHAN" ] && [ -f "$ORPHAN" ]; then
  R=$(tok "$ORPHAN")
  case "$R" in
    "0 ADOPTABLE"|"0 TERMINAL")
      ok "MES2b R-03: the real orphan is reachable, not wedged (${R#0 })" ;;
    *)
      bad "MES2b the real orphan gave '$R'; it must classify to a routed token, exit 0 — a file no entry point can act on is #319 itself" ;;
  esac
else
  ok "MES2b the orphan file is gone; MES2 carries R-03 on its own (the shape, not the file)"
fi

F=$(mk pre-boundary gate_1_spec_review in_progress null)
R=$(tok "$F"); [ "$R" = "0 ADOPTABLE" ] && ok "MES3 a pre-boundary state is ADOPTABLE" \
  || bad "MES3 gate_1_spec_review gave '$R', expected '0 ADOPTABLE'"

F=$(mk boundary step_4_session_boundary in_progress null)
R=$(tok "$F"); [ "$R" = "0 BOUNDARY" ] && ok "MES4 the boundary state is BOUNDARY, not ADOPTABLE (M3/M4)" \
  || bad "MES4 step_4_session_boundary gave '$R', expected '0 BOUNDARY'"

F=$(mk resumable ready_for_implementation in_progress null)
R=$(tok "$F"); [ "$R" = "0 RESUMABLE" ] && ok "MES5 ready_for_implementation is RESUMABLE" \
  || bad "MES5 ready_for_implementation gave '$R', expected '0 RESUMABLE'"
F=$(mk resumable5 step_5_implementation in_progress null)
R=$(tok "$F"); [ "$R" = "0 RESUMABLE" ] && ok "MES5b step_5_implementation is RESUMABLE" \
  || bad "MES5b step_5_implementation gave '$R', expected '0 RESUMABLE'"

F=$(mk late6 step_6_review in_progress null)
R=$(tok "$F"); [ "$R" = "0 LATE" ] && ok "MES6 step_6_review is LATE (the gap ADR-0095 disclosed)" \
  || bad "MES6 step_6_review gave '$R', expected '0 LATE'"
F=$(mk late7 step_7_commit in_progress null)
R=$(tok "$F"); [ "$R" = "0 LATE" ] && ok "MES6b step_7_commit is LATE (the gap nobody disclosed)" \
  || bad "MES6b step_7_commit gave '$R', expected '0 LATE'"

F=$(mk express step_e2_execute in_progress '"express"')
R=$(tok "$F"); [ "$R" = "0 UNRESUMABLE" ] && ok "MES7 an express chain is UNRESUMABLE (M5)" \
  || bad "MES7 express gave '$R', expected '0 UNRESUMABLE'"
# The state prefix alone must be enough: chain_path is additive and a manifest may not carry it.
F=$(mk hybrid-null step_h3_execute in_progress null)
R=$(tok "$F"); [ "$R" = "0 UNRESUMABLE" ] && ok "MES7b a hybrid STATE with chain_path null is still UNRESUMABLE" \
  || bad "MES7b hybrid state with null chain_path gave '$R', expected '0 UNRESUMABLE'"

F=$(mk terminal completed completed null)
R=$(tok "$F"); [ "$R" = "0 TERMINAL" ] && ok "MES8a a completed chain is TERMINAL (M6)" \
  || bad "MES8a completed gave '$R', expected '0 TERMINAL'"

# MES8 — the negative twin of MES2, and the reason `status` is read at all.
# Form C sets `status: aborted` and leaves `current_step` exactly where it was. Reading only
# current_step would route an aborted step_0_init chain as ADOPTABLE and quietly restart it.
F=$(mk formc-aborted step_0_init aborted null)
R=$(tok "$F"); [ "$R" = "0 TERMINAL" ] \
  && ok "MES8 an aborted step_0_init (the Form C shape) is TERMINAL, not ADOPTABLE" \
  || bad "MES8 aborted step_0_init gave '$R', expected '0 TERMINAL' — status is not being read, so Form C's abort would be silently restarted"

F=$(mk bogus step_0_init in_progress null)
sed -i.bak 's|^current_step:.*|current_step: "step_99_nonsense"|' "$F" && rm -f "$F.bak"
R=$(tok "$F"); [ "$R" = "0 UNKNOWN" ] \
  && ok "MES9 an unrecognised current_step is UNKNOWN, never routed as adoptable" \
  || bad "MES9 a bogus state gave '$R', expected '0 UNKNOWN'"

printf 'this is not: yaml: [ at all\n' >"$TMP/broken.yml"
R=$(tok "$TMP/broken.yml"); [ "$R" = "0 UNREADABLE" ] \
  && ok "MES10 an unparseable file is UNREADABLE, exit 0 (a fact about the INPUT)" \
  || bad "MES10 an unparseable file gave '$R', expected '0 UNREADABLE'"

# ===========================================================================
# Section MESX — exit 3 in three shapes, each asserted DISTINCT from every token.
# Asserting only "non-zero" pins nothing when every failure looks alike (ADR-0090 E9).
# ===========================================================================
F=$(mk env-probe gate_1_spec_review in_progress null)
FAKEBIN="$TMP/nopy"; mkdir -p "$FAKEBIN"
# PATH must still carry a shell; emptying it hides bash too (ADR-0076 X6's lesson).
for _need in bash sed grep awk wc tr cut sort head date printf; do
  _p=$(command -v "$_need" 2>/dev/null) && ln -sf "$_p" "$FAKEBIN/$_need" 2>/dev/null
done
OUT=$(PATH="$FAKEBIN" bash "$ES" "$F" 2>&1); RC=$?
if [ "$RC" -eq 3 ] && ! printf '%s' "$OUT" | grep -qE '^(NONE|ADOPTABLE|BOUNDARY|RESUMABLE|LATE|UNRESUMABLE|TERMINAL|UNKNOWN|UNREADABLE)\|'; then
  ok "MESX1 no python3 -> exit 3 and NO token on stdout"
else
  bad "MESX1 no python3 gave rc=$RC out='$OUT'; expected exit 3 with no token"
fi

CLONE="$TMP/clone"; mkdir -p "$CLONE"
cp "$ES" "$CLONE/" && cp "$SKILLS/concept-to-code/scripts/manifest-validate.sh" "$CLONE/"
OUT=$(bash "$CLONE/manifest-entry-state.sh" "$F" 2>&1); RC=$?
if [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'manifest-field-state.sh'; then
  ok "MESX2 a missing sibling helper -> exit 3, naming the helper and the sync remedy"
else
  bad "MESX2 missing helper gave rc=$RC out='$OUT'; expected exit 3 naming manifest-field-state.sh"
fi

# The enum derivation's own denominator guard: a validator whose construction stops matching must
# report DID NOT RUN, never an empty known-set that reads as "every state is unknown".
CLONE2="$TMP/clone2"; mkdir -p "$CLONE2"
cp "$ES" "$CLONE2/"
cp "$SKILLS/concept-to-code/scripts/manifest-field-state.sh" "$CLONE2/"
printf '#!/bin/bash\n# a validator that no longer builds its enum the old way\nexit 0\n' >"$CLONE2/manifest-validate.sh"
OUT=$(bash "$CLONE2/manifest-entry-state.sh" "$F" 2>&1); RC=$?
if [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'expected >= 25'; then
  ok "MESX3 an enum derivation that stops matching -> exit 3, not a silently empty set"
else
  bad "MESX3 broken enum derivation gave rc=$RC out='$OUT'; expected exit 3 naming the count guard"
fi

bash "$ES" >/dev/null 2>&1; [ "$?" -eq 2 ] && ok "MESX4 no argument -> exit 2 (bad invocation, distinct from 3)" \
  || bad "MESX4 no argument did not exit 2"

# ===========================================================================
# MESW — it never writes. R-02 held by construction, and asserted anyway.
# ===========================================================================
WDIR="$TMP/wtest"; mkdir -p "$WDIR"
cp "$BASE" "$WDIR/m.yml"
BEFORE=$(cksum "$WDIR/m.yml" | awk '{print $1 $2}')
NB=$(ls -1 "$WDIR" | wc -l | tr -d ' ')
bash "$ES" "$WDIR/m.yml" >/dev/null 2>&1
AFTER=$(cksum "$WDIR/m.yml" | awk '{print $1 $2}')
NA=$(ls -1 "$WDIR" | wc -l | tr -d ' ')
if [ "$BEFORE" = "$AFTER" ] && [ "$NB" = "$NA" ]; then
  ok "MESW the classifier leaves the manifest and its directory byte-identical (R-02)"
else
  bad "MESW the classifier modified the manifest or its directory — it must only read"
fi

# ===========================================================================
# Section MESF — the Form A fence, EXTRACTED AND EXECUTED.
# The marker is the extraction anchor (ADR-0083); it is indented inside a list item, so the
# parser has to be indentation-tolerant — the issue's own first count was wrong for that reason.
# ===========================================================================
extract_fence() {
  # The literal marker, not a built-up string: `fence-contract-coverage.test.sh` F4 counts a
  # contract as covered only when a test NAMES it, and a name assembled at run time is exactly the
  # claim-versus-execution distinction that check exists to refuse.
  awk '
    index($0, "fence-contract: c2c-form-a-existing-manifest -->") { seek=1; next }
    seek && $0 ~ /^[[:space:]]*```bash[[:space:]]*$/ { inb=1; seek=0; next }
    inb && $0 ~ /^[[:space:]]*```[[:space:]]*$/ { exit }
    inb { print }
  ' "$CC"
}
BODY=$(extract_fence)
BODY_N=$(printf '%s\n' "$BODY" | grep -c .)
if [ "$BODY_N" -ge 20 ]; then ok "MESF0 the fence is declared and extracts $BODY_N lines"
else bad "MESF0 the fence extracted $BODY_N lines (expected >= 20) — an empty extraction is a FAILURE, never a skip"; fi

# run_fence <root> <slug> -> echoes "<rc>::<stdout first line>"
run_fence() {
  _s="$TMP/fence-$$.sh"
  printf '%s\n' "$BODY" \
    | sed -e "s|~/.claude/skills/|$SKILLS/|g" \
          -e "s|<project-root>|$1|g" \
          -e "s|<topic-slug>|$2|g" >"$_s"
  _o=$(bash "$_s" 2>&1); _r=$?
  printf '%s::%s\n' "$_r" "$(printf '%s\n' "$_o" | head -1)"
}

bash -n "$TMP/parse-check.sh" 2>/dev/null
printf '%s\n' "$BODY" | sed -e "s|~/.claude/skills/|$SKILLS/|g" >"$TMP/parse-check.sh"
bash -n "$TMP/parse-check.sh" 2>/dev/null && ok "MESF1 the fence parses as bash" \
  || bad "MESF1 the fence does not parse — a declared contract must at minimum parse (ADR-0083 F7)"

FR="$TMP/froot"; mkdir -p "$FR/docs/manifests"
R=$(run_fence "$FR" "nothing-here")
case "$R" in 0::*NONE*) ok "MESF2a no manifest today -> the fence reports NONE and exits 0" ;;
  *) bad "MESF2a empty root gave '$R', expected exit 0 with NONE" ;; esac

# R-03's second half: the fence routes the real orphan's SHAPE to the in-session continue.
cp "${ORPHAN:-$BASE}" "$FR/docs/manifests/$TODAY-orphan-shape.manifest.yml" 2>/dev/null
sed -i.bak -e 's|^current_step:.*|current_step: "step_0_init"|' -e 's|^status:.*|status: "in_progress"|' \
  "$FR/docs/manifests/$TODAY-orphan-shape.manifest.yml" && rm -f "$FR/docs/manifests/$TODAY-orphan-shape.manifest.yml.bak"
R=$(run_fence "$FR" "orphan-shape")
case "$R" in 0::*ADOPTABLE*) ok "MESF2 R-03: the fence routes the orphan's state to ADOPTABLE, in session, exit 0" ;;
  *) bad "MESF2 the orphan shape gave '$R', expected exit 0 with ADOPTABLE" ;; esac

cp "$BASE" "$FR/docs/manifests/$TODAY-done-topic.manifest.yml"
sed -i.bak -e 's|^current_step:.*|current_step: "completed"|' -e 's|^status:.*|status: "completed"|' \
  "$FR/docs/manifests/$TODAY-done-topic.manifest.yml" && rm -f "$FR/docs/manifests/$TODAY-done-topic.manifest.yml.bak"
R=$(run_fence "$FR" "done-topic")
case "$R" in 1::*TERMINAL*) ok "MESF3 a terminal topic STOPS the fence (exit 1) instead of overwriting the record" ;;
  *) bad "MESF3 terminal gave '$R', expected exit 1 with TERMINAL" ;; esac

# The fence's own DID-NOT-RUN branch: an un-synced machine must stop, not guess.
_s="$TMP/fence-nocls.sh"
printf '%s\n' "$BODY" | sed -e "s|~/.claude/skills/|$TMP/void/|g" -e "s|<project-root>|$FR|g" -e "s|<topic-slug>|orphan-shape|g" >"$_s"
OUT=$(bash "$_s" 2>&1); RC=$?
if [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'DID-NOT-RUN'; then
  ok "MESF4 a missing classifier -> the fence exits 3 and says DID-NOT-RUN (an unrun check is not a clean result)"
else
  bad "MESF4 missing classifier gave rc=$RC out='$OUT'; expected exit 3 with DID-NOT-RUN"
fi

# ===========================================================================
# Section MESB — the Form B branch table. Prose is the mechanism in an instruction file, but the
# needle must still be the INSTRUCTION, never the paragraph explaining it (rule 12).
# ===========================================================================
FB_A=$(grep -n '^2\. Read `current_step`\. Branch:' "$CC" | head -1 | cut -d: -f1)
FB_B=$(grep -n '^3\. Update `session_boundary.resumed_at`' "$CC" | head -1 | cut -d: -f1)
if [ -n "${FB_A:-}" ] && [ -n "${FB_B:-}" ] && [ "$FB_B" -gt "$FB_A" ]; then
  ok "MESB0 the Form B branch table anchors resolve ($FB_A..$FB_B)"
else
  bad "MESB0 the Form B anchors did not resolve — every assertion below is vacuous"
fi
TABLE=$(awk -v a="${FB_A:-0}" -v b="${FB_B:-0}" 'NR>=a && NR<b' "$CC")
TFLAT=$(printf '%s\n' "$TABLE" | tr '\n' ' ' | tr -d '`*' | tr -s ' ')

printf '%s' "$TFLAT" | grep -qi 'nothing before it needs redoing' \
  && ok "MESB1 the table has a step_4_session_boundary branch (M3/M4 — it had none)" \
  || bad "MESB1 no boundary branch in the Form B table; Gate 4's abort message and project-conductor both send chains to a state with no branch"

printf '%s' "$TFLAT" | grep -qi 'implementation is past review entry' \
  && ok "MESB2 the table has a step_6_review / step_7_commit branch" \
  || bad "MESB2 no late-state branch in the Form B table"

printf '%s' "$TFLAT" | grep -qi 'skill concept-to-code <topic-full-title>' \
  && ok "MESB3 the pre-boundary refusal names a command that EXISTS (the whole of #319)" \
  || bad "MESB3 the pre-boundary refusal still names no runnable command — 'continue in current session' with no way to do it is the deadlock itself"

printf '%s' "$TFLAT" | grep -qi 'never cross a session boundary' \
  && ok "MESB4 the table has an express/hybrid branch (M5)" \
  || bad "MESB4 no express/hybrid branch in the Form B table"

# The #324 boundary, stated at the call site so two fixes cannot disagree in one block.
grep -qi 'issue #324' "$CC" \
  && ok "MESB5 the unattended policy is explicitly deferred to #324 at the call site" \
  || bad "MESB5 the Form A block does not name #324; without it the unattended policy gets invented twice"

# ===========================================================================
# Z1 — assertion floor. A suite reporting FEWER assertions does not read as broken, and nobody
# watches the count (ADR-0083 §D3).
# ===========================================================================
TOTAL=$((PASS+FAIL))
[ "$TOTAL" -ge 28 ] && ok "Z1 assertion floor met ($TOTAL)" \
  || bad "Z1 only $TOTAL assertions ran (floor 28) — assertions vanished rather than failed"

echo
echo "manifest-entry-state.test.sh — PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
