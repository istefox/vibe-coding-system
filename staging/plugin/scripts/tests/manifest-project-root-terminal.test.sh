#!/bin/bash
# manifest-project-root-terminal.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash manifest-project-root-terminal.test.sh
#
# Covers issue #197 (ADR-0078): manifest-validate.sh invariant 4 required project_root to be an
# existing directory in every state, which asserts that every manifest is validated on the machine
# that produced it. Five of this repository's own manifests carry a path from a different machine
# and failed for that reason alone.
#
# THE PREMISE IS THE THING TO PIN, NOT THE CONCLUSION. The exemption is sound only because the
# states it names are ABSORBING — a manifest in one of them can never move again, so its
# project_root is a historical record rather than a live precondition. Section A derives the
# absorbing set from manifest-transition.sh at run time and checks the validator's exempt list
# against it. Hardcoding "completed, failed, aborted" here would pin today's answer, not the reason
# for it, and a future transition out of `failed` would silently make the exemption wrong.
#
# That derive-the-premise shape is ADR-0067 F6's, and ADR-0077's, applied to a state machine.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/scripts"
VALIDATE="$CC/manifest-validate.sh"
TRANSITION="$CC/manifest-transition.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

DEAD="/nonexistent-machine-root/Developer/whatever"

# Fixtures are built from a REAL manifest, patching only current_step and project_root. A
# hand-written minimal one trips five unrelated invariants (artifacts on a completed status,
# hitl_gates count, chain_path), and every verdict below would then be about those instead — a
# first draft did exactly that and reported "still invalid" with an empty project_root reason.
BASE=""
for _c in "$REPO"/docs/manifests/*.manifest.yml; do
  _r=$(grep -m1 '^project_root:' "$_c" | sed 's/^project_root:[[:space:]]*//; s/"//g')
  [ -n "$_r" ] && [ -d "$_r" ] && { BASE="$_c"; break; }
done
[ -n "$BASE" ] || { echo "FAIL: no usable base manifest with a live project_root"; exit 1; }

# mk <name> <current_step> <root | __NONE__ | __EMPTY__>
mk() {
  sed -e "s|^current_step: .*|current_step: \"$2\"|" "$BASE" > "$TMP/$1.yml"
  case "$3" in
    __NONE__)  sed -i.bak '/^project_root:/d' "$TMP/$1.yml" ;;
    __EMPTY__) sed -i.bak 's|^project_root: .*|project_root: ""|' "$TMP/$1.yml" ;;
    *)         sed -i.bak "s|^project_root: .*|project_root: \"$3\"|" "$TMP/$1.yml" ;;
  esac
  rm -f "$TMP/$1.yml.bak"
}

valid() { bash "$VALIDATE" "$TMP/$1.yml" >/dev/null 2>&1; }
why()   { bash "$VALIDATE" "$TMP/$1.yml" 2>&1 | grep project_root; }

# =====================================================================================
# A. The premise, derived. If this section is wrong, every verdict below is unsound.
#
# A state is absorbing when it never appears as a SOURCE in the transition pair table. The
# unconditional `any state -> failed|aborted` branch creates edges INTO those two and none out, so
# it does not make them sources.
SOURCES="$TMP/sources.txt"
grep -oE 'echo "[a-z0-9_]+,[a-z0-9_]+"' "$TRANSITION" | sed 's/echo "//; s/"//' \
  | cut -d, -f1 | sort -u > "$SOURCES"
_np=$(wc -l < "$SOURCES" | tr -d ' ')

# A0: count guard on the derivation. An empty pair table would make every state look absorbing,
# and the section would certify the exemption on the strength of having parsed nothing.
[ "$_np" -ge 10 ] && ok "A0: derived $_np distinct transition sources (count guard: >= 10)" \
                  || bad "A0: only $_np sources parsed — section A would pass vacuously"

# The states invariant 4 exempts, read out of the validator rather than typed here. A fourth state
# added to that case arm is automatically checked by A2.
EXEMPT=$(sed -n '/Invariant 4:/,/^fi$/p' "$VALIDATE" \
  | grep -E '^[[:space:]]*(completed|failed|aborted)[a-z|]*\)' | head -1 \
  | sed 's/[[:space:]]*//g; s/)//' | tr '|' ' ')
_ne=$(printf '%s\n' $EXEMPT | sed '/^$/d' | wc -l | tr -d ' ')
[ "$_ne" -ge 1 ] && ok "A1: invariant 4 declares $_ne exempt state(s): $EXEMPT" \
                 || bad "A1: could not read the exempt states out of the validator"

_live=""
for _s in $EXEMPT; do
  grep -Fxq "$_s" "$SOURCES" && _live="$_live $_s"
done
if [ -z "$_live" ]; then
  ok "A2: every exempted state is ABSORBING — none is a transition source"
else
  bad "A2: exempted but still resumable —$_live. The exemption is unsound for those states."
fi

# A3: the reverse direction. `step_5_implementation` is a live state and must NOT be exempt — a
# guard that only checks the exempt list against the machine would also pass if the list were empty.
case " $EXEMPT " in
  *" step_5_implementation "*) bad "A3: a live state is exempt from the project_root check" ;;
  *) ok "A3: a live state (step_5_implementation) is not in the exempt list" ;;
esac

# =====================================================================================
# B. The verdicts.
mk done_dead    completed             "$DEAD"
mk failed_dead  failed                "$DEAD"
mk abort_dead   aborted               "$DEAD"
mk flight_dead  step_5_implementation "$DEAD"
mk done_live    completed             "$TMP"
mk done_missing completed             __NONE__
mk done_empty   completed             __EMPTY__

valid done_dead   && ok "B1: a completed manifest with a dead project_root is VALID (#197)" \
                  || bad "B1: still invalid — $(why done_dead)"
valid failed_dead && ok "B2: a failed manifest with a dead project_root is VALID" \
                  || bad "B2: still invalid — $(why failed_dead)"
valid abort_dead  && ok "B3: an aborted manifest with a dead project_root is VALID" \
                  || bad "B3: still invalid — $(why abort_dead)"

# B4: THE LIVE PATH IS UNCHANGED, and this is what makes the relaxation safe rather than merely
# convenient. Every consumer reads an in-flight manifest: manifest-transition.sh validates
# pre-transition and a terminal manifest never transitions; autopilot-build check 2 requires
# ready_for_implementation immediately after validating.
if valid flight_dead; then
  bad "B4: an IN-FLIGHT manifest with a dead project_root now passes — the check was weakened"
else
  printf '%s' "$(why flight_dead)" | grep -q 'not an existing directory' \
    && ok "B4: an in-flight manifest with a dead project_root still FAILS, naming project_root" \
    || bad "B4: it fails, but not on project_root — $(why flight_dead)"
fi

# B5/B6: PRESENCE is still required in every state. A missing or empty field is corruption at any
# point in the chain, and relaxing existence must not relax that.
if valid done_missing; then
  bad "B5: a completed manifest with NO project_root passes — presence stopped being required"
else
  printf '%s' "$(why done_missing)" | grep -q 'missing or empty' \
    && ok "B5: a missing project_root still fails, even when terminal" \
    || bad "B5: fails for the wrong reason — $(why done_missing)"
fi
valid done_empty && bad "B6: an EMPTY project_root passes when terminal" \
                 || ok "B6: an empty project_root still fails, even when terminal"

# B7: and a terminal manifest with a real directory is still valid — the case that must not have
# been broken while making the dead-path case pass.
valid done_live && ok "B7: a completed manifest with a real project_root is still valid" \
                || bad "B7: broke the ordinary terminal case — $(why done_live)"

# =====================================================================================
# C. The population the issue was found in. Asserted against the files, count-guarded so an empty
# glob cannot pass vacuously.
_n=$(ls "$REPO"/docs/manifests/*.manifest.yml 2>/dev/null | wc -l | tr -d ' ')
if [ "$_n" -ge 30 ]; then
  _bad=0; _names=""
  for _m in "$REPO"/docs/manifests/*.manifest.yml; do
    bash "$VALIDATE" "$_m" >/dev/null 2>&1 || { _bad=$((_bad+1)); _names="$_names $(basename "$_m")"; }
  done
  [ "$_bad" -eq 0 ] && ok "C1: all $_n manifests in this repository validate" \
                    || bad "C1: $_bad of $_n still invalid —$_names"
else
  bad "C1: expected >= 30 manifests, found $_n — C1 would pass vacuously"
fi

# C2: and at least one of them is actually exercising the exemption. Without this, C1 would go
# green the day someone "fixed" the five by rewriting their project_root — which ADR-0078 rejects —
# and the exemption would be untested against a real file while looking covered.
_hist=0
for _m in "$REPO"/docs/manifests/*.manifest.yml; do
  _p=$(grep -m1 '^project_root:' "$_m" | sed 's/^project_root:[[:space:]]*//; s/"//g')
  [ -n "$_p" ] && [ ! -d "$_p" ] && _hist=$((_hist+1))
done
[ "$_hist" -ge 1 ] && ok "C2: $_hist manifest(s) carry a historical project_root — C1 is exercising the exemption" \
                   || bad "C2: no manifest has a dead project_root; C1 no longer tests anything (were the five rewritten?)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
