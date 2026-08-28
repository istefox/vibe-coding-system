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
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: TP6 | plugin/skills/concept-to-code/references/step5-implementation.md | bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh "<manifest>" step_5_implementation | true
# plant: TP1 | plugin/skills/concept-to-code/references/step5-implementation.md | → transition to `step_6_review`. | → stop.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
C2C="$SKILLS/concept-to-code/SKILL.md"
STEP5_REF="$SKILLS/concept-to-code/references/step5-implementation.md"
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
# VCS-047/ADR-0174: concept-to-code's Step 5 body (a real chunk of the producer population — the
# entry transition into step_5_implementation and the exit into step_6_review both live here)
# physically moved into references/step5-implementation.md. Add it, or every producer inside old
# Step 5 silently vanishes from the population and its targets read as producerless.
[ -f "$STEP5_REF" ] && cat "$STEP5_REF" >>"$PROD"
PROD_N=$(wc -l <"$PROD" | tr -d ' ')

# ---------------------------------------------------------------------------
# Derivation 2b — the population, flattened. Decoration stripped, `→` normalised to `->`, folded to
# lower case, runs of blanks collapsed. Rule 3: a clause is the same clause whether it is backticked,
# bolded or spaced differently, and the classifier below must not be able to tell.
#
# LINE-WISE, deliberately. Joining wrapped lines into paragraphs was measured (2026-08-16) and
# rejected: a paragraph carrying both a manifest-transition.sh call and an unrelated mention of a
# second state credits the second state with the first one's call, and it destroyed the arrow
# attribution on `step_e1_plan` that R-03 exists to protect. The one thing wrapping genuinely breaks
# — a negation split across two lines — is handled by a one-line lookback in the classifier instead.
# ---------------------------------------------------------------------------
FLAT="$TMP/producers-flat.txt"
sed 's/[`*]//g; s/→/->/g' "$PROD" | tr 'A-Z' 'a-z' | tr -s ' \t' ' ' >"$FLAT"

# ---------------------------------------------------------------------------
# Derivation 2c — the classifier. Issue #300.
#
# The predicate used to be `manifest-transition.sh` OR the bare word "transition" OR an arrow, over
# a line merely CONTAINING the target. The word "transition" is not a transition: measured over this
# population on 2026-08-16, `step_6_review` had ELEVEN lines counted as producers and exactly ONE was
# an instruction. The other ten were three negations (`do NOT transition to step_6_review`), one
# negation wrapped onto a second line, four narrations (`before transitioning to`, `it never blocks
# the transition to`), one narrative arrow (`block the Step 5 -> step_6_review`), and one line where
# the target is the SOURCE (`Transition step_6_review -> step_7_commit`).
#
# Nothing in the corpus was producerless under either predicate, so this fixes no live false green.
# What it fixes is that TP1 could not be PLANTED: with prose satisfying it, removing the one real
# producer left it green, and an assertion nobody can plant pins nothing (rule 2). Under the
# classifier `step_6_review` has exactly one producer and TP1 carries a plant on it.
#
# The target must be the DESTINATION, not a mention. First match wins:
#
#   CALL   — a manifest-transition.sh invocation naming the target as an argument.
#   NEG    — the line negates the transition, or continues a negation that wrapped.
#   PROSE  — the verb is preceded by a determiner or preposition, or the clause is quoted. ADR-0117's
#            lesson applied to a second predicate: the preceding word separates an instruction from
#            prose, and form cannot.
#   IMP    — `transition[s|ing|ed] [back] to|into <target>` at a clause boundary.
#   ARROW  — `<id> -> <target>` where `<id>,<target>` is a legal pair in the DERIVED table. This is
#            #355's right anchor in a second place: an arrow whose left operand is the target is the
#            target's SOURCE, and `block the Step 5 -> step_6_review` has no source at all.
#
# CALL, IMP and ARROW are producers. NEG, PROSE, BADSRC and OTHER are not.
#
# The Gate 0d arrow form ADR-0095 had to add — `chain_path = express` -> `gate_0d_scaffolding ->
# step_e1_plan`, verb on the PRECEDING line — survives as ARROW because its left operand is a legal
# source. Losing it is the regression R-03 names, and TP3b pins it explicitly.
# ---------------------------------------------------------------------------
CLASSIFY="$TMP/classify.awk"
cat >"$CLASSIFY" <<'AWKEOF'
NR==FNR { PAIRS[$0]=1; next }
{
  low = $0
  prev = prevlow
  prevlow = low
  if (index(low, T) == 0) next

  if (low ~ ("manifest-transition\\.sh.* " T "( |$)")) { print "CALL\t" $0; next }

  if (low ~ /do not (auto-)?transition|never transition/) { print "NEG\t" $0; next }
  # A negation that wrapped: the previous line ends in `do not` (optionally with one trailing word)
  # and this one opens with the verb. Without this the continuation reads as an imperative — which
  # is exactly what it looked like before the lookback existed.
  if (prev ~ /do not( [a-z-]+)?$/ && low ~ ("^ ?transition(s|ing|ed)?( back)? (to|into) " T)) {
    print "NEG\t" $0; next
  }

  if (low ~ ("(^|[^a-z0-9_])(the|a|an|any|this|that|every|no|before|after|during|without|block|blocks|blocking) (auto-)?transition(s|ing|ed)?( back)? (to|into) " T)) {
    print "PROSE\t" $0; next
  }
  if (low ~ ("\"transition(s|ing|ed)?( back)? (to|into) " T)) { print "PROSE\t" $0; next }

  if (low ~ ("(^|[^a-z])transition(s|ing|ed)?( back)? (to|into) " T "([^a-z0-9_]|$)")) {
    print "IMP\t" $0; next
  }

  if (match(low, ("[a-z0-9_]+ -> " T "([^a-z0-9_]|$)"))) {
    seg = substr(low, RSTART, RLENGTH)
    split(seg, a, " ")
    if ((a[1] "," T) in PAIRS) { print "ARROW\t" $0 } else { print "BADSRC\t" $0 }
    next
  }
  print "OTHER\t" $0
}
AWKEOF

classify() { awk -v T="$1" -f "$CLASSIFY" "$PAIRS" "$FLAT"; }

has_producer() {
  classify "$1" | awk -F'\t' '$1=="CALL"||$1=="IMP"||$1=="ARROW"{f=1} END{exit !f}'
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
# TP1b — the classifier itself, both directions, against a fixture rather than the corpus. The
# corpus can only show that nothing is producerless today; it cannot show that a NON-producer is
# refused, because there is no producerless target in it to look at. Every line below is a shape
# measured in the real population on 2026-08-16.
# ===========================================================================
FIXTURE="$TMP/fixture.txt"
cat >"$FIXTURE" <<'FIXEOF'
- attended: present the findings and do not transition to step_6_review without user acknowledgment.
- attended: present the uncovered ids and do not
 transition to step_6_review without user acknowledgment.
it never blocks the transition to step_6_review. findings are carried into budget_findings
but never left: every "transition to step_6_review" further down needs step_5_implementation as
transition step_6_review -> step_7_commit. that is the source state whether rtf ran or not
the time gate 5 renders -- both are failure signals that block the step 5 -> step_6_review
weakened line, and the coverage gate exit code is 0 -> transition to step_6_review.
FIXEOF
# Eight fixture lines, SEVEN verdicts: line 2 is the first half of the wrapped negation and does not
# name the target at all, so the classifier never reaches it. It is in the fixture because line 3 is
# only classifiable with it present — the lookback is the mechanism under test, not decoration.
_got=$(awk -v T="step_6_review" -f "$CLASSIFY" "$PAIRS" "$FIXTURE" | cut -f1 | tr '\n' ' ')
_want="NEG NEG PROSE PROSE OTHER BADSRC IMP "
if [ "$_got" = "$_want" ]; then
  ok "TP1b the classifier separates the seven measured shapes (only the imperative counts)"
else
  bad "TP1b classifier verdicts changed — want [$_want] got [$_got]"
fi

# ===========================================================================
# TP1c — count guards on BOTH sides of the classification (ADR-0085: guard the denominator).
#
# A producer count of zero would already fail TP1 loudly. A REJECTED count of zero would not: it
# reads exactly like a corpus with no prose in it, which is what the corpus looked like before
# anyone measured. If the classifier stops classifying — a regex that no longer compiles, a
# flattening step that no longer strips — every line falls through to OTHER and both counts move.
#
# These are FLOORS and rule 10 applies: a floor absorbs its own plant, so neither is evidence about
# any individual verdict. They are vacuity guards and nothing more; TP1b is what pins the verdicts.
# Measured 2026-08-16: 62 producers, 13 rejected.
# ===========================================================================
TALLY="$TMP/tally.txt"
: >"$TALLY"
while IFS= read -r _t; do
  [ -n "$_t" ] || continue
  classify "$_t" | cut -f1 >>"$TALLY"
done <"$TARGETS"
PRODUCER_N=$(grep -cE '^(CALL|IMP|ARROW)$' "$TALLY" || true)
REJECT_N=$(grep -cE '^(NEG|PROSE|BADSRC)$' "$TALLY" || true)

if [ "$PRODUCER_N" -ge 40 ]; then
  ok "TP1c (vacuity floor) the classifier still finds producers ($PRODUCER_N >= 40)"
else
  bad "TP1c the classifier found only $PRODUCER_N producer line(s) across $TARGET_N targets — it has stopped matching, not the corpus"
fi

if [ "$REJECT_N" -ge 8 ]; then
  ok "TP1c2 (vacuity floor) the classifier still REJECTS lines ($REJECT_N >= 8) — a zero here reads like a corpus with no prose"
else
  bad "TP1c2 the classifier rejected only $REJECT_N line(s) — the negation/prose/bad-source arms are no longer firing"
fi

# ===========================================================================
# TP1d — R-03, named as a regression rather than left to TP1. ADR-0095 had to ADD the arrow form
# because Gate 0d puts the verb on the PRECEDING line and an arrow-blind predicate reported
# `step_e1_plan` producerless. Any narrowing that loses it is that defect returning, and TP1 would
# not say so: `step_e1_plan` would simply join the TP1 failure list with no hint of the cause.
#
# The assertion is on the CLASS, not on TP1's boolean, so a second producer appearing elsewhere
# cannot mask the loss. `or -> step_e1_plan` on the neighbouring line is the counter-case the source
# validation exists for and it must NOT be an ARROW — `or` is not a state.
# ===========================================================================
_e1=$(classify step_e1_plan)
if printf '%s\n' "$_e1" | grep -q '^ARROW.*gate_0d_scaffolding -> step_e1_plan'; then
  ok "TP1d (R-03) Gate 0d's arrow form still classifies as a producer of step_e1_plan"
else
  bad "TP1d (R-03) the Gate 0d arrow producer is gone — ADR-0095's added form was narrowed away; classify output:
$_e1"
fi

if printf '%s\n' "$_e1" | grep -q '^BADSRC'; then
  ok "TP1d2 an arrow whose left operand is not a legal source is refused (the source anchor is live)"
else
  bad "TP1d2 no BADSRC verdict for step_e1_plan — the arrow's left operand is no longer checked against the pair table"
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
# VCS-047/ADR-0174: both anchors now live in references/step5-implementation.md.
PRE_A=$(grep -n '^#### Recovery-readiness pre-flight' "$STEP5_REF" | head -1 | cut -d: -f1)
PRE_B=$(grep -n '^#### Pattern seed handoff' "$STEP5_REF" | head -1 | cut -d: -f1)
T45_A=$(grep -n '^### Step 4\.5 — Tracer-bullet probe' "$C2C" | head -1 | cut -d: -f1)
T45_B=$(grep -n '^### Step 5 — Implementation' "$C2C" | head -1 | cut -d: -f1)

if [ -n "${PRE_A:-}" ] && [ -n "${PRE_B:-}" ] && [ "$PRE_B" -gt "$PRE_A" ] \
   && [ -n "${T45_A:-}" ] && [ -n "${T45_B:-}" ] && [ "$T45_B" -gt "$T45_A" ]; then
  ok "TP5 both region anchors resolve (pre-flight $PRE_A..$PRE_B, Step 4.5 $T45_A..$T45_B)"
else
  bad "TP5 a region anchor did not resolve — a heading was reworded; TP6/TP8 assert nothing without it"
fi

_pre=$(awk -v a="${PRE_A:-0}" -v b="${PRE_B:-0}" 'NR>a && NR<b' "$STEP5_REF")
# The needle is the INVOCATION, not the two words around it.
#
# The first form was `grep -E "manifest-transition\.sh|[Tt]ransition"` AND `grep 'step_5_implementation'`,
# which the prose introducing the block satisfies on its own — "Step 5.0.5 — enter
# `step_5_implementation`", "the chain's only unconditional producer of that state". Replacing the
# actual `bash …manifest-transition.sh` call with `true` left it GREEN.
#
# Found by `plant-check.sh` on its FIRST run, which is the whole argument for that file existing:
# rule 12's sixth instance, caught by the mechanism built for the first five.
if printf '%s\n' "$_pre" | grep -qE '^bash .*manifest-transition\.sh .*step_5_implementation'; then
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
