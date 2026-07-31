#!/bin/bash
# gate2b-trust-probe.test.sh — offline, hermetic, no network, fixture $HOME only.
# Bash 3.2 clean. Run: bash gate2b-trust-probe.test.sh
#
# Issue #233 / ADR-0102. Gate 2b fires whenever `test_cmd_candidate` is present and not NONE, and
# had no branch for "this exact command is already trusted". On the Phase 7 shakedown run the
# architect reported the project's existing command unchanged, `.claude/test-cmd` was untouched, and
# the read-only probe the skill already documents returned TRUSTED — and the attended path still
# presented the AskUserQuestion, asking a human to authorise a command a human had already
# authorised, whose SHA was already pinned. Approving re-ran `approve-test-cmd.sh` on the same hash:
# a no-op.
#
# THE MECHANISM ALREADY EXISTED AND ONE PATH USED IT. The autopilot branch carries the same probe
# and the same reasoning — "reading existing trust is not granting it". The attended path never got
# the branch.
#
# WHY IT IS WORTH FIXING RATHER THAN TOLERATING, in the issue's own words and worth repeating here:
# the cost is not the click. A gate that fires with a foregone answer, every run, on every
# brownfield project, is a gate people learn to approve without reading — and this is the gate that
# guards arbitrary command execution. A safety gate that cries wolf is worse than one that fires
# rarely.
#
# NOT A BYPASS. "Trust is born only from explicit human SHA-pinned consent" is untouched: this reads
# trust that already exists and never grants any. G2B5 and G2B6 are the forward guards that keep it
# that way — approve-test-cmd.sh is still never called before a click, and a changed SHA still
# gates even when the command text looks identical, because the pin is on content.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: G2B3 | plugin/skills/concept-to-code/SKILL.md | already trusted, SHA unchanged | awaiting approval
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$CC" ] || { echo "FATAL: missing $CC"; exit 1; }

# --- the Gate 2b block, anchored on headings (rule 3) ----------------------------------------
A=$(grep -n '^\*\*Gate 2b — Test-cmd TOFU' "$CC" | head -1 | cut -d: -f1)
B=$(grep -n '^\*\*Gate 2c — External dependencies' "$CC" | head -1 | cut -d: -f1)
if [ -n "${A:-}" ] && [ -n "${B:-}" ] && [ "$B" -gt "$A" ]; then
  ok "G2B0 Gate 2b block anchors resolve ($A..$B)"
else
  bad "G2B0 Gate 2b anchors did not resolve — a heading was reworded, and every assertion below is vacuous"
fi
BLOCK=$(awk -v a="${A:-0}" -v b="${B:-0}" 'NR>=a && NR<b' "$CC")
BLOCK_N=$(printf '%s\n' "$BLOCK" | grep -c .)
if [ "$BLOCK_N" -ge 40 ]; then ok "G2B0b the extracted block is non-vacuous ($BLOCK_N lines)"
else bad "G2B0b the Gate 2b block extracted $BLOCK_N lines (expected >= 40)"; fi

# Prose flattened, undecorated and case-insensitive — a clause is the same clause however it wraps,
# is quoted, is bolded, or is capitalised (ADR-0098, ADR-0101).
FLAT=$(printf '%s\n' "$BLOCK" | tr '\n' ' ' | tr -d '`*' | tr -s ' ')

# ===========================================================================
# G2B1/G2B2 — ONE probe, above the branch split, so both paths read the same answer.
#
# There were two copies in the file before this change (Form B's resume guard and the autopilot
# branch's). A third would be a trust probe that can disagree with itself about whether a safety
# gate fires — ADR-0086's criterion applied to the one place it matters most. Hoisting it above the
# split REMOVES a copy rather than adding one.
# ===========================================================================
PROBE_N=$(printf '%s\n' "$BLOCK" | grep -c 'state/stop-gate/trust')
if [ "$PROBE_N" -eq 1 ]; then
  ok "G2B1 the trust probe appears exactly once in Gate 2b"
else
  bad "G2B1 the trust probe appears $PROBE_N times in Gate 2b; two copies can disagree about whether a safety gate fires (#233)"
fi

PROBE_LINE=$(printf '%s\n' "$BLOCK" | grep -n 'state/stop-gate/trust' | head -1 | cut -d: -f1)
ASK_LINE=$(printf '%s\n' "$BLOCK" | grep -n 'Use `AskUserQuestion`' | head -1 | cut -d: -f1)
if [ -n "${PROBE_LINE:-}" ] && [ -n "${ASK_LINE:-}" ] && [ "$PROBE_LINE" -lt "$ASK_LINE" ]; then
  ok "G2B2 the probe runs before the AskUserQuestion — the attended path can act on it"
else
  bad "G2B2 the probe is not above the gate (probe=${PROBE_LINE:-none} ask=${ASK_LINE:-none}); the attended path cannot skip a gate it has already shown"
fi

# ===========================================================================
# G2B3/G2B4 — the attended branches.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'already trusted, SHA unchanged'; then
  ok "G2B3 the attended TRUSTED branch exists and says why it is skipping"
else
  bad "G2B3 no attended TRUSTED branch — the gate still asks a human to re-authorise an already-pinned command (#233)"
fi

if printf '%s\n' "$FLAT" | grep -qi 'reading existing trust is not granting it'; then
  ok "G2B3b the reasoning is stated where the skip happens, not only in the autopilot branch"
else
  bad "G2B3b the skip is asserted without the reason that makes it safe"
fi

if printf '%s\n' "$FLAT" | grep -qi 'NOT_TRUSTED'; then
  ok "G2B4 (forward guard) the NOT_TRUSTED path still presents the gate"
else
  bad "G2B4 the NOT_TRUSTED branch is gone; the gate would never fire"
fi

# ===========================================================================
# G2B5/G2B6 — the invariants this must not touch. Both forward guards.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'NEVER call approve-test-cmd.sh before'; then
  ok "G2B5 (forward guard) approve-test-cmd.sh is still never called before a click"
else
  bad "G2B5 the never-before-the-click invariant is gone — this fix reads trust, it must never grant it"
fi

if printf '%s\n' "$FLAT" | grep -qi 'a changed file is a new authorisation'; then
  ok "G2B6 a differing SHA still gates, even when the command text looks identical"
else
  bad "G2B6 nothing says the pin is on CONTENT — a command that looks the same with a different SHA must still gate (#233)"
fi

if printf '%s\n' "$FLAT" | grep -qi 'autopilot must never establish trust unattended'; then
  ok "G2B7 (forward guard) the autopilot branch keeps its own refusal"
else
  bad "G2B7 the autopilot branch lost its never-establish-trust rule"
fi

# ===========================================================================
# G2B8 — the probe is EXECUTED, both directions, against a fixture trust registry. A probe nobody
# ran is the class this repository keeps finding; here it decides whether a safety gate fires.
# ===========================================================================
FBODY="$TMP/probe.sh"
awk '/fence-contract: c2c-gate2b-trust-probe -->/{m=1; next}
     m && /^```bash$/{f=1; next}
     f && /^```$/{exit}
     f{print}' "$CC" >"$FBODY"

if [ -s "$FBODY" ] && grep -q 'stop-gate/trust' "$FBODY"; then
  ok "G2B8 the probe extracts as a declared fence-contract: c2c-gate2b-trust-probe -->"
else
  bad "G2B8 the probe carries no fence-contract marker or did not extract; G2B9/G2B10 assert nothing"
fi

PROOT="$TMP/proj"; mkdir -p "$PROOT/.claude"
printf '%s\n' 'make test' >"$PROOT/.claude/test-cmd"
FHOME="$TMP/fhome"; mkdir -p "$FHOME/.claude/state/stop-gate"
_h=$(shasum -a 256 "$PROOT/.claude/test-cmd" | awk '{print $1}')
_rn=$(cd "$PROOT" && pwd -P | tr '[:upper:]' '[:lower:]')

# The substituted body goes to a FILE and `HOME` is set on the `bash` that runs it.
#
# The first draft was `HOME="$1" sed … "$FBODY" | bash`, and an environment prefix binds to the
# FIRST command of a pipeline only — so `sed` got the fixture HOME and `bash` inherited the real
# one, reading the machine's actual trust registry. G2B9 and G2B11 passed against it (that registry
# happens to hold neither entry) while pinning nothing at all; **G2B10, the positive twin, is the
# only thing that failed.** Rule 8, executed: a negative assertion pins nothing without its positive
# twin, and here the twin was the difference between a working fixture and a decorative one.
run_probe() {
  sed "s|<project-root>|$PROOT|g" "$FBODY" >"$TMP/probe.run.sh"
  HOME="$1" bash "$TMP/probe.run.sh" 2>/dev/null
}

: >"$FHOME/.claude/state/stop-gate/trust"
if [ "$(run_probe "$FHOME")" = "NOT_TRUSTED" ]; then
  ok "G2B9 an empty trust registry reports NOT_TRUSTED"
else
  bad "G2B9 the probe did not report NOT_TRUSTED on an empty registry — it would skip the gate on an unapproved command"
fi

printf '%s\t%s\n' "$_h" "$_rn" >"$FHOME/.claude/state/stop-gate/trust"
if [ "$(run_probe "$FHOME")" = "TRUSTED" ]; then
  ok "G2B10 a matching (hash, normalized-root) pair reports TRUSTED"
else
  bad "G2B10 the probe did not report TRUSTED on a matching pair — the gate would still cry wolf"
fi

# The positive twin's twin: change the FILE, keep the registry, and the answer must flip back.
printf '%s\n' 'make test && rm -rf /' >"$PROOT/.claude/test-cmd"
if [ "$(run_probe "$FHOME")" = "NOT_TRUSTED" ]; then
  ok "G2B11 editing the file flips the answer back — the pin is on content, not on the command text"
else
  bad "G2B11 the probe still reported TRUSTED after the file changed; that is a trust bypass, not a skipped gate"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 13 ]; then ok "Z1 assertion-count floor ($_total >= 13)"
else bad "Z1 assertion count fell to $_total (floor 13) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
