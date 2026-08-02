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
# SP5 WAS AN EQUALITY AND THE EQUALITY WAS WRONG (issue #342, 2026-08-02). It asserted
# `SLOT -eq TOT`: every non-null pointer names the root slot. Step 7.0b, shipped by this same
# feature, repoints each COMPLETING chain at its own archive — so the assertion forbade exactly what
# the feature it guards performs. It survived because the window between the ADR shipping and the
# first chain completing after it contained no counter-example. Feature #286 was that first chain,
# and it left the harness red for a defect that did not exist.
#
# The cause is the proxy, not the arithmetic: "artifacts.spec is not null" stood in for "this
# manifest is historical", and that held only while the corpus had ONE legitimate shape. An
# assertion that stopped tracking its own population — ADR-0113's RH2, in the other direction.
#
# SP5 IS NOW A FLOOR on the historical set, which is the invariant it was written for. A completing
# chain never RAISES that set (it points at an archive), so the floor does not drift as the corpus
# grows; a chain between Step 1 and Step 7 sits at the slot and only ever raises SLOT, never lowers
# it. Both directions were measured on fixtures before the change: 41 slot pointers plus one
# archive pointer passes, and dropping one historical pointer to 40 fails.
#
# THE WEAKNESS, DISCLOSED RATHER THAN HIDDEN. A floor is masked by concurrency: a historical
# manifest rewritten WHILE another chain sits at the slot leaves SLOT unchanged. SP5c narrows that
# — a rewrite to an archive nobody wrote is still caught — but a rewrite from a slot pointer to some
# other manifest's real archive is invisible to any static scan of the corpus. Telling "a chain
# repointed its OWN record" from "a chain repointed SOMEONE ELSE'S" needs history, not a snapshot.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: SP1 | plugin/skills/concept-to-code/SKILL.md | bash ~/.claude/skills/concept-to-code/scripts/spec-archive.sh "<project-root>" "<topic-slug>" | true
# plant: SP5b | plugin/scripts/tests/spec-pointer-archive.test.sh | INFLIGHT=$((INFLIGHT + 1)); continue | :
# plant: SP5 | ../docs/manifests/2026-05-23-clean-public-repo-anonymize.manifest.yml | spec: "/Users/stefanoferri/Developer/vibe-coding-system/SPEC.md" | spec: "/x/docs/specs/100-secrets-and-dependency-gate-content-scan.spec.md"
# plant: SP5c | plugin/scripts/tests/spec-pointer-archive.test.sh | printf '# archived spec\n' >"$SPX/286-demo.spec.md" | true
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
SA="$STAGING/plugin/skills/concept-to-code/scripts/spec-archive.sh"
SETA="$STAGING/plugin/skills/concept-to-code/scripts/manifest-set-artifact.sh"
VA="$STAGING/plugin/skills/concept-to-code/scripts/manifest-validate.sh"

# The historical set, measured on origin/main 2026-08-02: 42 manifest files, one of them the
# 2026-07-31 orphan carrying `spec: null`, so 41 carried a slot pointer before any chain completed
# under ADR-0106. This number is a floor, not a count of the corpus: it may only be RAISED, and only
# by a deliberate decision recorded beside it.
HIST_FLOOR=41

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

# Matched by BASENAME against the specs directory, never by resolving the recorded path. A manifest
# records an ABSOLUTE, machine-specific project_root (ADR-0078's whole subject) — five of this
# repository's own name a machine nobody runs — so `[ -f "$_s" ]` on the stored string fails on CI
# for a perfectly correct manifest, and would report a defect that is not there. Twice over, since
# that is also the defect this file is being changed to remove.
archive_pointers_resolve() {   # $1 = manifests dir, $2 = specs dir. Sets ARCH_N, ARCH_BAD.
  ARCH_N=0; ARCH_BAD=0
  for m in "$1"/*.manifest.yml; do
    [ -f "$m" ] || continue
    _s=$(grep -E '^[[:space:]]+spec:' "$m" | head -1 | sed 's/.*spec:[[:space:]]*//; s/"//g')
    case "$_s" in
      null|""|*/SPEC.md) continue ;;
    esac
    ARCH_N=$((ARCH_N + 1))
    [ -f "$2/$(basename "$_s")" ] || ARCH_BAD=$((ARCH_BAD + 1))
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
elif [ "$SLOT" -ge "$HIST_FLOOR" ]; then
  ok "SP5 (forward guard) the historical set keeps its slot pointers — SLOT=$SLOT >= floor $HIST_FLOOR of $TOT ($INFLIGHT in-flight, excluded)"
else
  bad "SP5 SLOT fell to $SLOT, below the floor of $HIST_FLOOR — a historical manifest lost its slot pointer; ADR-0075 declined exactly that. A chain repointing its OWN record at Step 7.0b does not lower this number."
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
# SP5c/SP5d — the floor alone cannot see a repoint that goes somewhere wrong, so this does.
# ===========================================================================
# The floor counts what STAYED at the slot. It says nothing about where a pointer that LEFT the slot
# went, and Step 7.0b's failure branch (SP4) means "left the slot" is a legitimate state with a
# wrong-looking twin: an archive that was never written. SP5c runs both directions on fixtures,
# because the live corpus has at most one archive pointer and on `main` it has none — an assertion
# that can only be exercised on some branches is one that pins nothing on the others.
SPX="$TMP/specs"; mkdir -p "$SPX"
FX2="$TMP/mf2"; mkdir -p "$FX2"
printf 'artifacts:\n  spec: "/machine/does/not/exist/docs/specs/286-demo.spec.md"\n' >"$FX2/ok.manifest.yml"
printf '# archived spec\n' >"$SPX/286-demo.spec.md"
archive_pointers_resolve "$FX2" "$SPX"
_good_n=$ARCH_N; _good_bad=$ARCH_BAD

FX3="$TMP/mf3"; mkdir -p "$FX3"
printf 'artifacts:\n  spec: "/machine/does/not/exist/docs/specs/999-never-written.spec.md"\n' >"$FX3/bad.manifest.yml"
archive_pointers_resolve "$FX3" "$SPX"
_bad_n=$ARCH_N; _bad_bad=$ARCH_BAD

if [ "$_good_n" -eq 1 ] && [ "$_good_bad" -eq 0 ] && [ "$_bad_n" -eq 1 ] && [ "$_bad_bad" -eq 1 ]; then
  ok "SP5c an archive pointer is resolved by basename — a written archive passes, one that was never written fails"
else
  bad "SP5c fixtures returned good=$_good_n/$_good_bad bad=$_bad_n/$_bad_bad — expected 1/0 and 1/1; the check cannot tell a real archive from a missing one"
fi

# SP5d — the same rule on the live corpus. The count is IN the message on purpose: on `main` it is
# legitimately zero, and a silent pass over an empty population reads exactly like coverage.
archive_pointers_resolve "$REPO/docs/manifests" "$REPO/docs/specs"
if [ "$ARCH_BAD" -eq 0 ]; then
  ok "SP5d every repointed manifest names an archive that exists ($ARCH_N archive pointer(s) live)"
else
  bad "SP5d $ARCH_BAD of $ARCH_N repointed manifest(s) name an archive that is not under docs/specs/ — the pointer is worse than the slot it replaced"
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
if [ "$_total" -ge 13 ]; then ok "Z1 assertion-count floor ($_total >= 13)"
else bad "Z1 assertion count fell to $_total (floor 13) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
