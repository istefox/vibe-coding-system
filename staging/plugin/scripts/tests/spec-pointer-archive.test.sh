#!/bin/bash
# spec-pointer-archive.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash spec-pointer-archive.test.sh
#
# Issue #267 / ADR-0106. All 41 manifests record `artifacts.spec: <project-root>/SPEC.md`, and root
# SPEC.md is a single mutable slot every chain overwrites. So the pointer resolves, for all of them,
# to whatever the slot holds today — right for at most one, and that one only by coincidence.
#
# AND THERE IS A SECOND GAP THE ISSUE DOES NOT NAME. ADR-0096 archives the OUTGOING SPEC when a new
# chain is about to overwrite it — archive-on-DISPLACEMENT. So a chain's SPEC is archived only if a
# LATER chain happens to displace it. **The most recent chain's SPEC is never archived**, and this
# repository proves it: #222's and #176's were archived by hand (today, and by #229), and
# `120-accessibility-i18n` is still archived only under a title-derived name.
#
# Step 7 therefore archives the chain's OWN SPEC on completion and repoints the manifest at it. The
# two triggers compose: `spec-archive.sh` compares by content, so calling it twice on the same SPEC
# reports ALREADY and writes nothing.
#
# HISTORICAL MANIFESTS ARE NOT REWRITTEN. ADR-0075 declined exactly that for the five dead
# `project_root` paths, on the ground that falsifying a record for no consumer is worse than leaving
# it accurate-for-its-moment. SP5 is the forward guard: the corpus keeps its slot pointers.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: SP1 | plugin/skills/concept-to-code/SKILL.md | bash ~/.claude/skills/concept-to-code/scripts/spec-archive.sh "<project-root>" "<topic-slug>" | true
# plant: SP5b | plugin/scripts/tests/spec-pointer-archive.test.sh | INFLIGHT=$((INFLIGHT + 1)); continue | :
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
SA="$STAGING/plugin/skills/concept-to-code/scripts/spec-archive.sh"
SETA="$STAGING/plugin/skills/concept-to-code/scripts/manifest-set-artifact.sh"
VA="$STAGING/plugin/skills/concept-to-code/scripts/manifest-validate.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for _f in "$CC" "$SA" "$SETA" "$VA"; do
  [ -f "$_f" ] || { echo "FATAL: missing $_f"; exit 1; }
done
FLAT=$(tr '\n' ' ' <"$CC" | tr -d '`*' | tr -s ' ')

# ===========================================================================
# SP0 — the premise, derived. Both halves: the pointers, and the archive gap.
# ===========================================================================
# An IN-FLIGHT manifest carries `spec: null`: manifest-init.sh writes null and Step 1's
# manifest-set-artifact.sh is what fills it. It is neither historical nor repointed — it has no
# pointer yet. Counting it made SP5 report a repoint that never happened, and it did so for ANY
# feature of ANY chain in the window between manifest-init.sh and Step 1. Latent from the day
# ADR-0106 shipped and found by the first chain run after it, which created a manifest and left
# the harness red at 67/68 while nothing had been rewritten. The exclusion below is what makes
# SP5's message true of the thing SP5 counts.
count_pointers() {   # $1 = manifests dir. Sets TOT, SLOT, INFLIGHT.
  TOT=0; SLOT=0; INFLIGHT=0
  for m in "$1"/*.manifest.yml; do
    [ -f "$m" ] || continue
    _s=$(grep -E '^[[:space:]]+spec:' "$m" | head -1 | sed 's/.*spec:[[:space:]]*//; s/"//g')
    case "$_s" in
      null|"") INFLIGHT=$((INFLIGHT + 1)); continue ;;
    esac
    TOT=$((TOT + 1))
    case "$_s" in */SPEC.md) SLOT=$((SLOT + 1)) ;; esac
  done
}
count_pointers "$REPO/docs/manifests"
if [ "$TOT" -ge 30 ] && [ "$SLOT" -ge 30 ]; then
  ok "SP0 $SLOT of $TOT manifests point artifacts.spec at the root slot ($INFLIGHT in-flight, excluded)"
else
  bad "SP0 derivation returned $SLOT of $TOT — the premise moved, re-measure before trusting ADR-0106"
fi

# ===========================================================================
# SP1..SP4 — the Step 7 wiring.
# ===========================================================================
S7=$(grep -n '^### Step 7 — Commit' "$CC" | head -1 | cut -d: -f1)
S7BLK=$(awk -v a="${S7:-0}" 'NR>=a && NR<a+200' "$CC")
S7FLAT=$(printf '%s\n' "$S7BLK" | tr '\n' ' ' | tr -d '`*' | tr -s ' ')

# The needle is the INVOCATION, not the name. Step 7 legitimately names the script in prose while
# explaining how the two archive triggers compose, and a bare `grep -q 'spec-archive.sh'` matched
# that sentence — the plant that deleted the actual call walked straight through. Rule 12, fifth
# instance today.
if printf '%s\n' "$S7BLK" | grep -qE '^bash .*/spec-archive\.sh "<project-root>"'; then
  ok "SP1 Step 7 archives this chain's own SPEC"
else
  bad "SP1 Step 7 does not call spec-archive.sh — the last chain's SPEC is archived only if a later chain displaces it (#267)"
fi

if printf '%s\n' "$S7BLK" | grep -q 'manifest-set-artifact.sh'; then
  ok "SP2 Step 7 repoints artifacts.spec"
else
  bad "SP2 Step 7 does not repoint artifacts.spec; the manifest keeps naming a slot someone else will overwrite (#267)"
fi

if printf '%s\n' "$S7FLAT" | grep -qi 'archive-on-completion'; then
  ok "SP3 the two archive triggers are named and distinguished"
else
  bad "SP3 nothing distinguishes this from ADR-0096's archive-on-displacement; a reader cannot tell why both exist"
fi

if printf '%s\n' "$S7FLAT" | grep -qi 'leave the pointer as it is'; then
  ok "SP4 a failed archive leaves the pointer alone, and says so"
else
  bad "SP4 no failure branch — on COLLISION the manifest would point at an archive that was never written"
fi

# ===========================================================================
# SP5 — forward guard: no historical manifest is rewritten (ADR-0075's rule).
# ===========================================================================
if [ "$TOT" -lt 30 ]; then
  bad "SP5 the population collapsed to $TOT manifest(s) — an empty or tiny corpus must not read as agreement"
elif [ "$SLOT" -eq "$TOT" ]; then
  ok "SP5 (forward guard) every historical manifest keeps its slot pointer — none was rewritten ($INFLIGHT in-flight, excluded)"
else
  bad "SP5 $((TOT - SLOT)) historical manifest(s) were repointed; ADR-0075 declined exactly that, and this ADR follows it"
fi

# SP5b — the exclusion itself, on a fixture, in both directions. SP5 above reads the LIVE corpus,
# so it cannot demonstrate the exclusion once no chain is in flight; this can, on every run.
FX="$TMP/mf"; mkdir -p "$FX"
printf 'artifacts:\n  spec: "/x/SPEC.md"\n' > "$FX/2026-01-01-done.manifest.yml"
printf 'artifacts:\n  spec: null\n'         > "$FX/2026-01-02-inflight.manifest.yml"
count_pointers "$FX"
if [ "$TOT" -eq 1 ] && [ "$SLOT" -eq 1 ] && [ "$INFLIGHT" -eq 1 ]; then
  ok "SP5b an in-flight manifest (spec: null) is excluded from the population, never counted as a repoint"
else
  bad "SP5b fixture returned TOT=$TOT SLOT=$SLOT INFLIGHT=$INFLIGHT — expected 1/1/1"
fi
count_pointers "$REPO/docs/manifests"   # restore the live counts for anything downstream

# ===========================================================================
# SP6 — executed end to end: archive the chain's own SPEC, repoint, and the manifest still validates.
# ===========================================================================
ROOT="$TMP/proj"; mkdir -p "$ROOT/docs/manifests" "$ROOT/docs/specs"
printf '%s\n' '# SPEC — demo' '' '**Topic slug:** 999-demo-topic' '' 'Body.' >"$ROOT/SPEC.md"
_src=$(ls "$REPO"/docs/manifests/*.manifest.yml | head -1)
M="$ROOT/docs/manifests/t.manifest.yml"
sed "s|^project_root: .*|project_root: \"$ROOT\"|" "$_src" >"$M"

out=$(bash "$SA" "$ROOT" 999-demo-topic 2>&1); rc=$?
ARCH="$ROOT/docs/specs/999-demo-topic.spec.md"
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "ARCHIVED" ] && [ -f "$ARCH" ]; then
  ok "SP6 the chain's own SPEC archives on completion"
else
  bad "SP6 archiving the chain's own SPEC failed: rc=$rc out=$out"
fi

if bash "$SETA" "$M" spec "$ARCH" >/dev/null 2>&1 && grep -qF "$ARCH" "$M"; then
  ok "SP6b manifest-set-artifact repoints artifacts.spec at the archive"
else
  bad "SP6b repointing artifacts.spec failed"
fi

if bash "$VA" "$M" >/dev/null 2>&1; then
  ok "SP6c the repointed manifest still validates"
else
  bad "SP6c the repointed manifest no longer validates — the new path breaks an invariant"
fi

out=$(bash "$SA" "$ROOT" 999-demo-topic 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "ALREADY" ]; then
  ok "SP6d the two archive triggers compose — a second call writes nothing"
else
  bad "SP6d a second archive call did not report ALREADY (rc=$rc out=$out); displacement and completion would duplicate"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 10 ]; then ok "Z1 assertion-count floor ($_total >= 10)"
else bad "Z1 assertion count fell to $_total (floor 10) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
