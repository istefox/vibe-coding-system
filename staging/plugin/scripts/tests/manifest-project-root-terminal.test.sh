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
# The base is chosen by PATCHING each candidate and testing the result, never by looking for one
# whose project_root happens to exist on this machine. A first draft did the latter and passed
# locally while failing in CI, where the checkout path differs and NO manifest has a live root —
# a machine-dependent assumption inside the test for the issue about machine-dependent assumptions.
BASE=""
for _c in "$REPO"/docs/manifests/*.manifest.yml; do
  sed -e 's|^current_step: .*|current_step: "completed"|' \
      -e "s|^project_root: .*|project_root: \"$TMP\"|" "$_c" > "$TMP/base-probe.yml"
  if bash "$VALIDATE" "$TMP/base-probe.yml" >/dev/null 2>&1; then BASE="$_c"; break; fi
done
[ -n "$BASE" ] || { echo "FAIL: no manifest validates even with a live project_root — fixtures cannot be built"; exit 1; }

# mk <name> <current_step> <root | __NONE__ | __EMPTY__> [<status>]
#
# The 4th argument arrived with issue #331 and is not cosmetic: before it, every fixture inherited
# BASE's `status: "completed"` while patching `current_step` alone, so a fixture *named* in-flight
# was terminal on the axis nothing was reading yet. B4 caught that the moment invariant 4 started
# reading both fields — the assertion was right, the fixture was under-specified, and the coupling
# it relied on was never stated. Pass the status explicitly whenever the fixture's name makes a
# claim about the chain's state.
mk() {
  sed -e "s|^current_step: .*|current_step: \"$2\"|" "$BASE" > "$TMP/$1.yml"
  case "$3" in
    __NONE__)  sed -i.bak '/^project_root:/d' "$TMP/$1.yml" ;;
    __EMPTY__) sed -i.bak 's|^project_root: .*|project_root: ""|' "$TMP/$1.yml" ;;
    *)         sed -i.bak "s|^project_root: .*|project_root: \"$3\"|" "$TMP/$1.yml" ;;
  esac
  if [ "$#" -ge 4 ]; then
    sed -i.bak "s|^status: .*|status: \"$4\"|" "$TMP/$1.yml"
  fi
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
#
# `s/).*//` and not `s/)//`: since #331 the arm carries its body on the same line
# (`completed|failed|aborted) project_root_terminal=1 ;;`), and dropping only the paren left the
# body glued to the last state name — three assertions then compared a state list against a list
# containing `abortedproject_root_terminal=1;;` and reported a disagreement that did not exist.
EXEMPT=$(sed -n '/Invariant 4:/,/^fi$/p' "$VALIDATE" \
  | grep -E '^[[:space:]]*(completed|failed|aborted)[a-z|]*\)' | head -1 \
  | sed 's/[[:space:]]*//g; s/).*//' | tr '|' ' ')
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

# --- The SECOND axis (issue #331, ADR-0113) ------------------------------------------------------
#
# Invariant 4 now exempts on `current_step` OR `status`. A2 above proves the axis-1 list is
# absorbing against the pair table; that proof DOES NOT COVER axis 2 and must not be restated over
# it — `status` appears nowhere in the pair table, because manifest-transition.sh validates a NEW
# status passed as an argument and never reads the one on disk. Deriving axis 2's soundness from
# the same table would certify a premise that does not apply to it, which is the failure this
# section exists to prevent one level up.
#
# So axis 2 is checked two ways instead: the two case arms must agree (A4), and the source must
# state axis 2's own, different premise (A5).
STATUS_EXEMPT=$(sed -n '/case "\$project_root_status" in/,/esac/p' "$VALIDATE" \
  | grep -oE '(^|[[:space:]])(completed|failed|aborted)[a-z|]*\)' | head -1 \
  | sed 's/[[:space:]]//g; s/)//' | tr '|' ' ')
_ns=$(printf '%s\n' $STATUS_EXEMPT | sed '/^$/d' | wc -l | tr -d ' ')

if [ "$_ns" -lt 1 ]; then
  bad "A4: could not read a second exempt-state list out of invariant 4 — the derivation is broken"
elif [ "$(printf '%s\n' $EXEMPT | sort | tr '\n' ' ')" = "$(printf '%s\n' $STATUS_EXEMPT | sort | tr '\n' ' ')" ]; then
  ok "A4: both invariant-4 axes exempt the same $_ns states ($STATUS_EXEMPT)"
else
  bad "A4: the two axes disagree — current_step exempts [$EXEMPT], status exempts [$STATUS_EXEMPT]"
fi
# plant: A4 | plugin/skills/concept-to-code/scripts/manifest-validate.sh | case "$project_root_status" in completed|failed|aborted) project_root_terminal=1 | case "$project_root_status" in completed) project_root_terminal=1

# A5: axis 2's premise is stated, and stated as DIFFERENT from axis 1's. The needle is the fact
# that makes the axis-1 proof inapplicable — that manifest-transition.sh never reads the current
# status — not the word "terminal", which the axis-1 paragraph is full of (rule 12). Matched
# against a flattened copy so a line wrap or a backticked word cannot fail a correct file.
_flat_v=$(tr '\n' ' ' < "$VALIDATE" | tr -s ' ' | tr -d '`*')
if printf '%s' "$_flat_v" | grep -q 'never inspects the one on disk'; then
  ok "A5: invariant 4 states why the axis-1 absorbing proof does not cover the status axis"
else
  bad "A5: the status axis carries no premise of its own — it is inheriting a proof that is not true of it"
fi
# plant: A5 | plugin/skills/concept-to-code/scripts/manifest-validate.sh | and never inspects the one on disk | and reads the one on disk too

# A6: the two files that decide terminality must agree, and neither may be derived from the other.
# manifest-entry-state.sh already reads both fields, but it DERIVES its state enum from
# manifest-validate.sh — a dependency the other way closes a loop, so ADR-0113 keeps two copies and
# pins them here instead (ADR-0086's criterion answered by a cycle, ADR-0092 §V's shape).
ENTRY="$CC/manifest-entry-state.sh"
if [ ! -f "$ENTRY" ]; then
  bad "A6: manifest-entry-state.sh not found — the cross-file agreement check DID NOT RUN"
else
  ENTRY_TERMINAL=$(grep -E "^[[:space:]]*(completed|failed|aborted)[a-z|]*\)[[:space:]]*printf 'TERMINAL" "$ENTRY" \
    | head -1 | sed 's/[[:space:]]*//g; s/).*//' | tr '|' ' ')
  _nt=$(printf '%s\n' $ENTRY_TERMINAL | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$_nt" -lt 1 ]; then
    bad "A6: could not derive the TERMINAL set from manifest-entry-state.sh — A6 would pass vacuously"
  elif [ "$(printf '%s\n' $EXEMPT | sort | tr '\n' ' ')" = "$(printf '%s\n' $ENTRY_TERMINAL | sort | tr '\n' ' ')" ]; then
    ok "A6: invariant 4 and manifest-entry-state.sh agree on the terminal set ($ENTRY_TERMINAL)"
  else
    bad "A6: they disagree — invariant 4 exempts [$EXEMPT], the classifier calls terminal [$ENTRY_TERMINAL]"
  fi
fi

# =====================================================================================
# B. The verdicts.
mk done_dead    completed             "$DEAD"
mk failed_dead  failed                "$DEAD"
mk abort_dead   aborted               "$DEAD"
mk flight_dead  step_5_implementation "$DEAD" in_progress
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

# =====================================================================================
# D. The second axis, both directions (issue #331, ADR-0113).
#
# Form C (abort) sets `status: aborted` and leaves `current_step` untouched, so a manifest can be
# terminal on one axis and live on the other. Reading `current_step` alone made the exemption miss
# exactly that shape — the orphan of 2026-07-31 validated on the machine that produced it and
# failed on CI, which is the machine-dependence ADR-0078 exists to remove.
mk formc_dead     step_0_init           "$DEAD" aborted
mk formc_live     step_0_init           "$TMP"  aborted
mk formc_missing  step_0_init           __NONE__ aborted
mk formc_empty    step_0_init           __EMPTY__ aborted
mk statusdone     step_5_implementation "$DEAD" completed
mk inflight       step_1_interview      "$DEAD" in_progress

# D1: the live orphan's exact shape. This is the assertion the issue was filed for.
valid formc_dead && ok "D1: terminal by status, live by current_step, dead root — VALID (#331)" \
                 || bad "D1: still invalid — $(why formc_dead)"
# plant: D1 | plugin/skills/concept-to-code/scripts/manifest-validate.sh | case "$project_root_status" in completed|failed|aborted) project_root_terminal=1 ;; esac | :

# D2: THE OTHER DIRECTION, and it is what keeps this from being a weakening. A manifest live on
# BOTH axes with a dead root still fails, naming the field. B4 covers the same property from the
# current_step side; this one moves the status field off its BASE value so neither axis can excuse
# it, which is the combination the widening could have opened.
if valid inflight; then
  bad "D2: an in-flight manifest (both axes live) with a dead project_root now passes — weakened"
else
  printf '%s' "$(why inflight)" | grep -q 'not an existing directory' \
    && ok "D2: both axes live + dead root still FAILS, naming project_root" \
    || bad "D2: it fails, but not on project_root — $(why inflight)"
fi
# plant: D2 | plugin/skills/concept-to-code/scripts/manifest-validate.sh | elif [ ! -d "$project_root_val" ] && [ "$project_root_terminal" -eq 0 ]; then | elif false; then

# D3: the status axis carries the exemption on its own, with a live current_step. Without this,
# D1 would also pass under a rule that merely added `step_0_init` to the exempt list.
valid statusdone && ok "D3: terminal by status alone (live current_step) exempts the dead root" \
                 || bad "D3: the status axis does not carry the exemption — $(why statusdone)"

# D4/D5: PRESENCE is unconditional on the new axis too. A widened exemption must relax existence
# and nothing else.
if valid formc_missing; then
  bad "D4: a status-terminal manifest with NO project_root passes — presence stopped being required"
else
  printf '%s' "$(why formc_missing)" | grep -q 'missing or empty' \
    && ok "D4: a missing project_root still fails on the status axis" \
    || bad "D4: fails for the wrong reason — $(why formc_missing)"
fi
valid formc_empty && bad "D5: an EMPTY project_root passes when terminal by status" \
                  || ok "D5: an empty project_root still fails on the status axis"

# D6: and the ordinary case is not broken — a status-terminal manifest with a real directory.
valid formc_live && ok "D6: terminal by status with a real project_root is still valid" \
                 || bad "D6: broke the ordinary case — $(why formc_live)"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
# Z1: assertion-count floor. A file that silently stops running six assertions reports fewer of
# them and nothing reads the total (ADR-0083 §D3) — a floor, not an exact count, so an addition
# does not need a bump.
_total=$((PASS + FAIL))
if [ "$_total" -ge 21 ]; then
  echo "PASS: Z1: $_total assertions ran (floor: 21)"
  PASS=$((PASS+1))
else
  echo "FAIL: Z1: only $_total assertions ran — expected >= 21; assertions vanished"
  FAIL=$((FAIL+1))
fi
[ "$FAIL" -eq 0 ]
