#!/bin/bash
# transition-producer.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash transition-producer.test.sh
#
# Issue #248 / ADR-0095. At the end of Step 5 the orchestrator transitioned to `step_6_review`
# and the transition script correctly refused:
#
#     manifest-transition: illegal transition ready_for_implementation → step_6_review
#
# The graph is `ready_for_implementation → step_5_implementation → step_6_review`, and NOTHING on
# the default path performed the first hop. Every producer of `step_5_implementation` lives inside
# the Step 4.5 tracer-bullet block, which runs only when `tracer_bullet_mode = probe` — and
# `manifest-init.sh` writes `skip`. So a default run entered Step 5 from `ready_for_implementation`,
# did all of Step 5, and could not leave.
#
# THE CLASS — a consumer and a producer specified in different places, with nothing checking that
# the producer exists. Third instance when #248 was filed (#173 / ADR-0071: a pre-flight asserting
# a state nothing produced; #238: `manifest-set-gate.sh` correct, deployed, called from nowhere).
#
# WHAT THIS GUARD DOES AND DOES NOT CATCH, stated because the difference decided the design:
#
#   CATCHES  — a transition target with NO producer anywhere (the #238 shape). Section TP1.
#   MISSES   — a target whose only producers sit behind a default-off flag (the #248 shape).
#              `step_5_implementation` HAS two producers; both are in the Step 4.5 block. A
#              mechanical check cannot read conditionality out of prose, and pretending otherwise
#              would be worse than the honest boundary. #248 itself is pinned instance-level, by
#              TP6/TP7, not by the class guard.
#
# The class guard is worth shipping anyway because it found a NEW instance on its first run, before
# any of this was written: `gate_5_review_decision` is entered by nothing. See TP1's exemption.
#
# Derived-guard pattern, instance 9 (ADR-0086): population derived at run time, waiver declared in
# the file it excuses, count guard on the DENOMINATOR (ADR-0085). Not extracted into a helper —
# ADR-0086's criterion is "extract only when two copies giving different answers would be a
# defect", and this asks its own question about its own population.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
C2C="$SKILLS/concept-to-code/SKILL.md"
TRANS="$SKILLS/concept-to-code/scripts/manifest-transition.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$C2C" ]   || { echo "FATAL: missing $C2C"; exit 1; }
[ -f "$TRANS" ] || { echo "FATAL: missing $TRANS"; exit 1; }

# ---------------------------------------------------------------------------
# Derivation 1 — the legal pairs, from the transition script's own table.
# ---------------------------------------------------------------------------
PAIRS="$TMP/pairs.txt"
awk -F'"' '/^[[:space:]]*echo "[a-z0-9_]+,[a-z0-9_]+"/{print $2}' "$TRANS" | sort -u >"$PAIRS"
PAIR_N=$(wc -l <"$PAIRS" | tr -d ' ')

TARGETS="$TMP/targets.txt"
cut -d, -f2 "$PAIRS" | sort -u >"$TARGETS"
TARGET_N=$(wc -l <"$TARGETS" | tr -d ' ')

# ---------------------------------------------------------------------------
# Derivation 2 — the producer population: every staged SKILL.md, MINUS concept-to-code section 3.
#
# §3 is the state-machine summary. By construction it names every pair in the graph — a routing
# table, a legal-pairs list and an ASCII diagram — and none of it performs a transition. Including
# it would make every target trivially "covered" and the guard would assert nothing.
# ---------------------------------------------------------------------------
S3_START=$(grep -n '^## 3\. State machine summary' "$C2C" | head -1 | cut -d: -f1)
S3_END=$(grep -n '^## 4\. Step-by-step dispatch templates' "$C2C" | head -1 | cut -d: -f1)

PROD="$TMP/producers.txt"
: >"$PROD"
# The guard below FAILS CLOSED on purpose: if the range does not resolve, concept-to-code
# contributes NOTHING to the producer population and 26 targets are reported producerless — loud,
# and alongside TP0c naming the cause. The tempting simplification (drop the guard, include the
# file whole) fails OPEN: §3 names every pair, so every target would be trivially covered and this
# whole file would assert nothing. Do not "clean this up" in that direction.
if [ -n "${S3_START:-}" ] && [ -n "${S3_END:-}" ]; then
  awk -v a="$S3_START" -v b="$S3_END" 'NR<a || NR>b' "$C2C" >>"$PROD"
fi
for _f in "$SKILLS"/*/SKILL.md; do
  [ "$_f" = "$C2C" ] && continue
  cat "$_f" >>"$PROD"
done
PROD_N=$(wc -l <"$PROD" | tr -d ' ')

# has_producer <target> — a line naming the target in a transition context: an explicit
# manifest-transition.sh call, the word "transition", or an arrow pointing at the state (the Gate 0d
# routing block writes `chain_path = express` → `gate_0d_scaffolding → step_e1_plan`, with the verb
# on the PRECEDING line — an arrow-blind predicate reported it as producerless, which is why the
# arrow form is in here and was not guessed at).
has_producer() {
  grep -- "$1" "$PROD" 2>/dev/null \
    | grep -qE "manifest-transition\.sh|[Tt]ransition|(→|->)[[:space:]]*\`?$1"
}

# ---------------------------------------------------------------------------
# Derivation 3 — declared exemptions, in the file they excuse (ADR-0077's rule).
#   # transition-producer-exempt: <target> — <reason, >= 40 chars, ONE line>
# ---------------------------------------------------------------------------
EXEMPT="$TMP/exempt.txt"
grep -n '^# transition-producer-exempt:' "$TRANS" >"$EXEMPT" 2>/dev/null || : >"$EXEMPT"
EXEMPT_N=$(wc -l <"$EXEMPT" | tr -d ' ')

exempt_targets() { sed 's/^[0-9]*:# transition-producer-exempt:[[:space:]]*//; s/[[:space:]].*$//' "$EXEMPT"; }

is_exempt() { exempt_targets | grep -qxF "$1"; }

# ===========================================================================
# TP0 — the derivations are not vacuous. A glob or an awk that quietly stops matching reports an
# empty population, and an empty population reads exactly like full coverage (ADR-0085's lesson:
# guard the DENOMINATOR, not the matches).
# ===========================================================================
if [ "$PAIR_N" -ge 40 ]; then ok "TP0 legal-pair derivation non-vacuous ($PAIR_N pairs)"
else bad "TP0 legal-pair derivation returned $PAIR_N pairs (expected >= 40) — the table parse broke"; fi

if [ "$TARGET_N" -ge 25 ]; then ok "TP0b distinct-target derivation non-vacuous ($TARGET_N targets)"
else bad "TP0b distinct-target derivation returned $TARGET_N (expected >= 25)"; fi

if [ -n "${S3_START:-}" ] && [ -n "${S3_END:-}" ] && [ "$S3_END" -gt "$S3_START" ]; then
  ok "TP0c section-3 exclusion range resolves ($S3_START..$S3_END)"
else
  bad "TP0c section-3 exclusion range did not resolve — heading renamed? Without it every target is trivially covered"
fi

if [ "$PROD_N" -ge 3000 ]; then ok "TP0d producer population non-vacuous ($PROD_N lines)"
else bad "TP0d producer population is $PROD_N lines (expected >= 3000) — the SKILL.md glob stopped resolving"; fi

# ===========================================================================
# TP1 — every transition target has a producer, or a declared exemption.
# ===========================================================================
_miss=""
while IFS= read -r _t; do
  [ -n "$_t" ] || continue
  if has_producer "$_t"; then continue; fi
  if is_exempt "$_t"; then continue; fi
  _miss="$_miss $_t"
done <"$TARGETS"
if [ -z "$_miss" ]; then
  ok "TP1 every transition target has a producer or a declared exemption"
else
  bad "TP1 transition target(s) nothing ever enters, and undeclared:$_miss"
fi

# ===========================================================================
# TP2 — the reverse direction. A waiver for a target that DOES have a producer is stale, and a
# stale waiver reads as a clean bill of health (ADR-0081 ZA4). Zero exemptions passes correctly
# here: nothing declared is nothing to go stale.
# ===========================================================================
_stale=""
for _e in $(exempt_targets); do
  has_producer "$_e" && _stale="$_stale $_e"
done
if [ -z "$_stale" ]; then
  ok "TP2 no stale exemption (each declared target genuinely has no producer)"
else
  bad "TP2 exemption(s) covering a target that now HAS a producer — remove them:$_stale"
fi

# ===========================================================================
# TP3 — a waiver must name a real transition target. A typo yields an exemption covering nothing,
# which silently stops excusing the target it was written for.
# ===========================================================================
_ghost=""
for _e in $(exempt_targets); do
  grep -qxF "$_e" "$TARGETS" || _ghost="$_ghost $_e"
done
if [ -z "$_ghost" ]; then
  ok "TP3 every exemption names a target in the legal-pair table"
else
  bad "TP3 exemption(s) naming a state that is not a transition target:$_ghost"
fi

# ===========================================================================
# TP4 — the reason is substantive and on ONE line. A reason wrapped across lines is a prose
# assertion that depends on where the text breaks, which this repository has now been bitten by
# five times (ADR-0073 line wrap, ADR-0076 comment marker, ADR-0080 backticks, ADR-0082 one-line
# marker, ADR-0092 a derivation reading its own source). Measuring only the marker line makes a
# wrapped reason fail at the moment it is written.
# ===========================================================================
_short=""
while IFS= read -r _line; do
  [ -n "$_line" ] || continue
  _payload=$(printf '%s' "$_line" | sed 's/^[0-9]*:# transition-producer-exempt:[[:space:]]*//')
  _tgt=$(printf '%s' "$_payload" | sed 's/[[:space:]].*$//')
  _reason=$(printf '%s' "$_payload" | sed "s/^$_tgt[[:space:]]*//; s/^[—-][[:space:]]*//")
  [ "${#_reason}" -ge 40 ] || _short="$_short $_tgt"
done <"$EXEMPT"
if [ -z "$_short" ]; then
  ok "TP4 every exemption reason is >= 40 chars on the marker line ($EXEMPT_N declared)"
else
  bad "TP4 exemption reason too short or wrapped onto a second line:$_short"
fi

# ===========================================================================
# #248 INSTANCE PINS — TP6/TP7. The class guard above cannot see this defect (see the header);
# these are what fail against the pre-#248 tree.
# ===========================================================================
PRE_A=$(grep -n '^#### Recovery-readiness pre-flight' "$C2C" | head -1 | cut -d: -f1)
PRE_B=$(grep -n '^#### Pattern seed handoff' "$C2C" | head -1 | cut -d: -f1)
T45_A=$(grep -n '^### Step 4\.5 — Tracer-bullet probe' "$C2C" | head -1 | cut -d: -f1)
T45_B=$(grep -n '^### Step 5 — Implementation' "$C2C" | head -1 | cut -d: -f1)

if [ -n "${PRE_A:-}" ] && [ -n "${PRE_B:-}" ] && [ "$PRE_B" -gt "$PRE_A" ] \
   && [ -n "${T45_A:-}" ] && [ -n "${T45_B:-}" ] && [ "$T45_B" -gt "$T45_A" ]; then
  ok "TP5 both region anchors resolve (pre-flight $PRE_A..$PRE_B, Step 4.5 $T45_A..$T45_B)"
else
  bad "TP5 a region anchor did not resolve — a heading was reworded; TP6/TP8 assert nothing without it"
fi

_pre=$(awk -v a="${PRE_A:-0}" -v b="${PRE_B:-0}" 'NR>a && NR<b' "$C2C")
if printf '%s\n' "$_pre" | grep -qE "manifest-transition\.sh|[Tt]ransition" \
   && printf '%s\n' "$_pre" | grep -q 'step_5_implementation'; then
  ok "TP6 Step 5's recovery-readiness pre-flight produces ready_for_implementation → step_5_implementation"
else
  bad "TP6 Step 5's entry does not transition into step_5_implementation — the default path cannot reach step_6_review (#248)"
fi

_formb=$(awk '/^2\. Read `current_step`\. Branch:/{f=1} f{print} /^3\. Update `session_boundary\.resumed_at`/{if(f) exit}' "$C2C")
if printf '%s\n' "$_formb" | grep -q 'step_5_implementation'; then
  ok "TP7 Form B's resume branch accepts step_5_implementation as a resumable state"
else
  bad "TP7 Form B's resume branch does not name step_5_implementation — after #248's fix an interrupted Step 5 falls through every branch"
fi

# ===========================================================================
# TP8/TP9 — forward guards, green before and after. Labelled so they are not read as fix evidence.
# ===========================================================================
_t45=$(awk -v a="${T45_A:-0}" -v b="${T45_B:-0}" 'NR>a && NR<b' "$C2C")
if printf '%s\n' "$_t45" | grep -q 'ready_for_implementation → step_5_implementation'; then
  ok "TP8 (forward guard) Step 4.5's own producer survives the fix"
else
  bad "TP8 Step 4.5's green branch no longer produces step_5_implementation"
fi

if grep -q 'Idempotent: same → same is a no-op' "$TRANS"; then
  ok "TP9 (forward guard) same-to-same is still a no-op — what makes Step 4.5's and Step 5's double transition safe"
else
  bad "TP9 manifest-transition.sh lost its same-to-same no-op; Step 4.5 followed by Step 5 now errors"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3: a suite reporting FEWER assertions does not read as
# broken, and nobody watches the count). Floor, not an exact count.
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 12 ]; then ok "Z1 assertion-count floor ($_total >= 12)"
else bad "Z1 assertion count fell to $_total (floor 12) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
