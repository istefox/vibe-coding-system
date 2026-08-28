#!/bin/bash
# gate4-implementation-axes.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash gate4-implementation-axes.test.sh
#
# Issue #237 / ADR-0097. Gate 4 offered three options encoding TWO ORTHOGONAL AXES:
#
#   WHERE Steps 5-7 run   — this session, or a fresh one
#   HOW they run          — unattended (autopilot=true, every downstream gate takes its safe
#                           default) or attended (Gates 5, 5.05, 5.06, 5.1, 5.6 render and ask)
#
# The matrix has four cells and the gate offered two, on the diagonal:
#
#              | this session | fresh session
#   unattended | option 1     | —
#   attended   | MISSING      | option 2
#
# So choosing to stay in-session was choosing to give up every downstream HITL gate, and nothing at
# the gate said so. Found by a run whose explicit purpose was to exercise those gates: taking the
# offered option meant the gates under observation were the ones that stopped firing.
#
# THE FILE ALSO CONTRADICTED ITSELF IN THE SAME BOX, which is the part reading the issue does not
# give you. Option 1's description said the context risk is "mitigated since coders dispatch as
# isolated subagents"; option 2 sold itself on "the cleanest coder context". Both cannot be true.
# The first is right — a dispatched coder is an isolated subagent in its own worktree (ADR-0068),
# so its context does not carry the orchestrator's session either way. What a fresh session
# actually buys is a clean ORCHESTRATOR context: better briefs, more headroom. Real, and not what
# the text said. Same shape as ADR-0042: a file whose prose disagrees with itself, with no way to
# tell which half is authoritative.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: G7 | plugin/skills/concept-to-code/references/hitl-gates.md | It does not change coder isolation | It gives the cleanest coder context
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
HITL_REF="$STAGING/plugin/skills/concept-to-code/references/hitl-gates.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

[ -f "$CC" ] || { echo "FATAL: missing $CC"; exit 1; }
[ -f "$HITL_REF" ] || { echo "FATAL: missing $HITL_REF"; exit 1; }

# --- the Gate 4 block, anchored on headings, never on line numbers (rule 3) ------------------
# VCS-048/ADR-0175: ## 5. HITL gates moved into references/hitl-gates.md.
G_A=$(grep -n '^\*\*Gate 4 — Session boundary (BLOCKING)\*\*' "$HITL_REF" | head -1 | cut -d: -f1)
G_B=$(grep -n '^\*\*Gate 4\.5 — Tracer-bullet red decision' "$HITL_REF" | head -1 | cut -d: -f1)

if [ -n "${G_A:-}" ] && [ -n "${G_B:-}" ] && [ "$G_B" -gt "$G_A" ]; then
  ok "G0 Gate 4 block anchors resolve ($G_A..$G_B)"
else
  bad "G0 Gate 4 block anchors did not resolve — a heading was reworded, and every assertion below is vacuous"
fi

BLOCK=$(awk -v a="${G_A:-0}" -v b="${G_B:-0}" 'NR>=a && NR<b' "$HITL_REF")
BLOCK_N=$(printf '%s\n' "$BLOCK" | grep -c .)
if [ "$BLOCK_N" -ge 60 ]; then ok "G0b the extracted block is non-vacuous ($BLOCK_N lines)"
else bad "G0b the Gate 4 block extracted $BLOCK_N lines (expected >= 60) — extraction is broken"; fi

# Whitespace-flattened copy for prose assertions. A clause that wraps across two lines is still the
# same clause; this repository has now been bitten by that five times (ADR-0073 / 0076 / 0080 /
# 0082 / 0092), so prose is matched flat and only structural markers are matched line-wise.
FLAT=$(printf '%s\n' "$BLOCK" | tr '\n' ' ' | tr -s ' ')

# ===========================================================================
# G1..G3 — the missing cell.
# ===========================================================================
OPT_N=$(printf '%s\n' "$BLOCK" | grep -c '^  - label: ')
if [ "$OPT_N" -eq 4 ]; then
  ok "G1 Gate 4 offers four options — both axes spanned, plus Abort ($OPT_N)"
else
  bad "G1 Gate 4 offers $OPT_N options; the four cells are attended-now, autopilot-now, fresh session, abort (#237)"
fi

if printf '%s\n' "$BLOCK" | grep -q '^  - label: "Implement now (attended, this session)'; then
  ok "G2 the attended in-session option exists"
else
  bad "G2 no 'Implement now (attended, this session)' option — staying in-session still forfeits every downstream gate (#237)"
fi

# Its handler must NOT set the autopilot flag. That is the whole difference between the two
# in-session options, and it is one line away from being identical to the wrong one.
ATT=$(printf '%s\n' "$BLOCK" \
  | awk '/^\*\*After the user clicks "Implement now \(attended, this session\)/{f=1; next} f&&/^\*\*After the user clicks/{exit} f{print}')
if [ -n "$ATT" ]; then
  ok "G3 the attended option has its own handler block"
  if printf '%s\n' "$ATT" | grep -q 'manifest-set-flag.sh <manifest-path> autopilot true'; then
    bad "G3b the attended handler sets autopilot true — it is the unattended path wearing another label"
  else
    ok "G3b the attended handler does not set autopilot"
  fi
else
  bad "G3 the attended option has no handler block; G3b asserts nothing"
  bad "G3b (not evaluated — no handler block to read)"
fi

# Forward guard: the unattended handler must still set it.
AUTO=$(printf '%s\n' "$BLOCK" \
  | awk '/^\*\*After the user clicks "Implement now \(autopilot, this session\)/{f=1; next} f&&/^\*\*After the user clicks/{exit} f{print}')
if printf '%s\n' "$AUTO" | grep -q 'autopilot true'; then
  ok "G4 (forward guard) the autopilot handler still sets the flag"
else
  bad "G4 the autopilot handler no longer sets autopilot true"
fi

# ===========================================================================
# G5..G7 — the gate must SAY what it is asking.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -q 'Two independent choices'; then
  ok "G5 the question names the two axes rather than presenting one blended choice"
else
  bad "G5 the question does not state that where-to-run and how-to-run are independent (#237)"
fi

FIRST=$(printf '%s\n' "$BLOCK" | grep '^  - label: ' | head -1)
if printf '%s\n' "$FIRST" | grep -q '(Recommended)'; then
  ok "G6 the recommended option is first and marked, per the global convention"
else
  bad "G6 the first option carries no (Recommended) marker: $FIRST"
fi

# ===========================================================================
# G7 — the self-contradiction. `cleanest coder context` is the claim that made the fresh session
# look necessary, and it is the one the file's own option-1 description already refutes.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -q 'cleanest coder context'; then
  bad "G7 an option still claims a fresh session gives the cleanest CODER context — a dispatched coder is an isolated subagent either way; what a fresh session buys is orchestrator context"
else
  ok "G7 no option claims a fresh session gives a cleaner coder context"
fi

if printf '%s\n' "$FLAT" | grep -q 'orchestrator context'; then
  ok "G7b the fresh-session option names what it actually buys — orchestrator context"
else
  bad "G7b the fresh-session option does not say what a fresh session actually buys"
fi

# ===========================================================================
# G8 — ADR-0071's producer invariant survives a fourth branch: every proceeding path runs Gate 4.0,
# and Abort still does not. Asserted here as well as in recovery-preflight.test.sh RH2/RH3, because
# the failure this change could introduce is a NEW branch that forgets it.
# ===========================================================================
REFS=$(printf '%s\n' "$BLOCK" | grep -c 'Run \*\*Gate 4.0\*\*')
if [ "$REFS" -ge 4 ]; then
  ok "G8 all four proceeding paths run Gate 4.0 ($REFS references)"
else
  bad "G8 only $REFS path(s) run Gate 4.0 — the new attended branch must produce the committed state Step 5 asserts (ADR-0071)"
fi

ABORT=$(printf '%s\n' "$BLOCK" | awk '/^\*\*After the user clicks "Abort chain":\*\*/{f=1} f{print}')
if printf '%s\n' "$ABORT" | grep -q 'Gate 4.0'; then
  bad "G8b the Abort path runs Gate 4.0 — an aborted chain must not leave a commit behind (ADR-0071 RH3)"
else
  ok "G8b (forward guard) the Abort path does not run Gate 4.0"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 12 ]; then ok "Z1 assertion-count floor ($_total >= 12)"
else bad "Z1 assertion count fell to $_total (floor 12) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
