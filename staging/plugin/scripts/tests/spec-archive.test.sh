#!/bin/bash
# spec-archive.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash spec-archive.test.sh
#
# Issue #228 / ADR-0096. Root SPEC.md is a single mutable slot every chain writes.
# `concept-to-code` Step 1's greenfield branch dispatches `interview-driver` with
# "Save output to <project-root>/SPEC.md" — and reaches that branch by TWO routes, only one of
# which is "no SPEC.md on disk". The other is a root SPEC.md belonging to a DIFFERENT topic:
# `gate0-detect.sh` reports `spec_topic_match=false` and flips the chain to greenfield, which
# "disowns" the SPEC for ROUTING and leaves the file exactly where the dispatch is about to write.
#
# The detection existed, was correct, fired, and protected nothing.
#
# TWO PREMISES OF THE ISSUE WERE STALE OR WRONG, both found by measuring:
#
#   1. "#176's SPEC is the only unarchived one" — already archived by #229 (`162b019`). The live
#      subject is whatever the slot currently holds.
#   2. "archive to docs/specs/<slug>.spec.md" — measured over the real corpus, only **3 of 41**
#      manifest topic slugs name an existing archive. Archive names come from the SPEC's title;
#      a topic slug is truncated to 40 chars (`100-secrets-and-dependency-gate-content` against
#      `100-secrets-and-dependency-gate-content-scan.spec.md`). A by-NAME "already archived?" check
#      would miss 38 existing archives and write a duplicate beside each. SA3 is that assertion.
#
# The archive is detected by CONTENT and written by NAME, which is the only combination that is
# both idempotent against the existing corpus and deterministic going forward.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: SA7 | plugin/skills/concept-to-code/scripts/spec-archive.sh | cp "$spec" "$dest" | mv "$spec" "$dest"
#
# --- issue #455, the guard order -----------------------------------------------------------------
# SA16 and SF5 assert the SAME correction at two levels, so they carry two different plants rather
# than one shared needle: SA16's removes the MECHANISM (the existence check that now runs before the
# slug is validated), SF5's removes the WIRING (the fence's argument passing). A single plant on the
# mechanism would leave SF5 unproven as an independent claim about SKILL.md.
# plant: SA16 | plugin/skills/concept-to-code/scripts/spec-archive.sh | [ -f "$spec" ] || { echo "NOSPEC"; exit 0; } | :
# plant: SA17 | plugin/skills/concept-to-code/scripts/spec-archive.sh | */*|.*|-*) | xxx-no-such-shape-xxx)
# plant: SF5 | plugin/skills/concept-to-code/SKILL.md | bash "$_sa" "$ROOT" "${OUT_SLUG:-unknown}" | bash "$_sa" "$ROOT/no-such-dir" "${OUT_SLUG:-unknown}"
# plant: SA9c | plugin/skills/concept-to-code/scripts/gate0-detect.sh | spec_owned="$spec" | spec_owned="yes"
# SA14b pins PROSE, and its plant says so honestly: removing the clause cannot break the ordering in
# spec-archive.sh, only the sentence that explains why the ordering is there (CLAUDE.md rule 16).
# plant: SA14b | plugin/skills/concept-to-code/SKILL.md | looks for the file before it | is magic and
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
SA="$STAGING/plugin/skills/concept-to-code/scripts/spec-archive.sh"
G0="$STAGING/plugin/skills/concept-to-code/scripts/gate0-detect.sh"
C2C="$STAGING/plugin/skills/concept-to-code/SKILL.md"
SYNC="$STAGING/sync-to-claude.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# mk_root [<spec-body>] — a throwaway project root; SPEC.md written only when a body is given.
#
# The directory comes from `mktemp -d`, NOT from a counter. `r=$(mk_root)` runs the function in a
# SUBSHELL, so a counter increments and is discarded: every call returned the same path and the
# fixtures accumulated into each other. Caught by inspecting what the fixture produced rather than
# what the assertion said — SA3 and SA4 both failed against a CORRECT script (ADR-0090's plant
# lesson, met here on a fixture).
mk_root() {
  _r=$(mktemp -d "$TMP/rXXXXXX")
  mkdir -p "$_r/docs/specs"
  if [ "$#" -ge 1 ]; then printf '%s\n' "$1" >"$_r/SPEC.md"; fi
  printf '%s' "$_r"
}

SPEC_A='# SPEC — alpha

**Topic slug:** 111-alpha-topic

Body A.'
SPEC_B='# SPEC — beta

**Topic slug:** 222-beta-topic

Body B.'

# ===========================================================================
# SA0 — the corpus premise, derived at run time. If this number collapses, SA3 is asserting
# something about a convention that no longer exists (denominator guard, ADR-0085).
# ===========================================================================
CORPUS_N=$(ls "$REPO"/docs/specs/*.spec.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$CORPUS_N" -ge 30 ]; then ok "SA0 archive corpus non-vacuous ($CORPUS_N specs)"
else bad "SA0 archive corpus is $CORPUS_N (expected >= 30) — docs/specs/ moved or emptied"; fi

BY_SLUG=0; MANIFEST_N=0
for _m in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_m" ] || continue
  MANIFEST_N=$((MANIFEST_N + 1))
  _t=$(grep '^topic:' "$_m" | head -1 | sed 's/.*: *//; s/"//g')
  [ -n "$_t" ] || continue
  [ -f "$REPO/docs/specs/$_t.spec.md" ] && BY_SLUG=$((BY_SLUG + 1))
done
if [ "$MANIFEST_N" -ge 30 ] && [ "$BY_SLUG" -lt "$MANIFEST_N" ]; then
  ok "SA0b by-name lookup is measurably insufficient ($BY_SLUG of $MANIFEST_N slugs name an archive)"
else
  bad "SA0b by-name premise no longer holds ($BY_SLUG of $MANIFEST_N) — SA3's rationale needs re-measuring"
fi

[ -f "$SA" ] || { echo "FATAL: missing $SA"; echo "PASS=$PASS FAIL=$((FAIL+1))"; exit 1; }

# ===========================================================================
# SA1..SA7 — the script's contract, both directions per ADR-0039.
# ===========================================================================
# SA1 covers a pair the ORCHESTRATOR CANNOT PRODUCE, and that is now recorded rather than left to
# read as coverage of the caller (issue #455). The fence runs on the greenfield branch only, and
# there are exactly two ways to be greenfield: no SPEC.md at all, which makes `spec_topic_slug`
# `unknown`; or a SPEC.md carrying a FOREIGN marker, which makes it that marker's value. A valid
# slug with no SPEC.md on disk is neither. SA16 below is the pair that actually arrives here.
# SA5 declares its own unproducible pair the same way; SA1 did not, which is why it looked like the
# empty-root case was tested for two months while the case that halts was untested.
r=$(mk_root)
out=$(bash "$SA" "$r" 111-alpha-topic 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "NOSPEC" ]; then ok "SA1 no root SPEC.md → NOSPEC, exit 0"
else bad "SA1 expected NOSPEC/0, got rc=$rc out=$out"; fi

# SA16 — THE assertion issue #455 exists for. `(no SPEC.md, unknown)` is the one pair Step 1's
# greenfield fence can produce with an empty root, and until #455 it returned exit 3, whose caller
# contract is HALT. A brand-new project therefore could not get through Step 1 at all — the
# bootstrap path, which is exactly what Gate 0d's scaffolding survey exists to serve.
r=$(mk_root)
out=$(bash "$SA" "$r" unknown 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "NOSPEC" ]; then
  ok "SA16 no root SPEC.md + the unknown slug gate0-detect.sh emits for it → NOSPEC, exit 0"
else bad "SA16 the empty-root bootstrap pair is a halt again: expected NOSPEC/0, got rc=$rc out=$out"; fi

# SA17 — the other direction of the same reorder. The existence check was moved ABOVE the
# empty-or-unknown guard and deliberately BELOW the shape guard: a slug carrying a path is a
# malformed CALL whether or not the root holds a file, so it must still be refused on an empty root.
# Sinking the whole guard below the check would have turned this into a silent 0.
r=$(mk_root)
out=$(bash "$SA" "$r" "../../etc/passwd" 2>&1); rc=$?
if [ "$rc" -eq 3 ]; then ok "SA17 no root SPEC.md + a path-shaped slug → still exit 3, not NOSPEC"
else bad "SA17 the shape guard sank below the existence check; a malformed call now returns rc=$rc out=$out"; fi

r=$(mk_root "$SPEC_A")
out=$(bash "$SA" "$r" 111-alpha-topic 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "ARCHIVED" ] \
   && [ -f "$r/docs/specs/111-alpha-topic.spec.md" ] \
   && cmp -s "$r/SPEC.md" "$r/docs/specs/111-alpha-topic.spec.md"; then
  ok "SA2 outgoing SPEC archived byte-identical, exit 0"
else bad "SA2 expected ARCHIVED/0 with an identical copy, got rc=$rc out=$out"; fi

# SA3 — THE assertion the corpus measurement earned: identical content already archived under a
# DIFFERENT filename must be recognised, and no duplicate written.
r=$(mk_root "$SPEC_A")
printf '%s\n' "$SPEC_A" >"$r/docs/specs/111-alpha-topic-with-a-longer-title.spec.md"
out=$(bash "$SA" "$r" 111-alpha-topic 2>&1); rc=$?
_n=$(ls "$r"/docs/specs/*.spec.md | wc -l | tr -d ' ')
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "ALREADY" ] && [ "$_n" -eq 1 ]; then
  ok "SA3 identical content archived under another name → ALREADY, no duplicate written"
else bad "SA3 expected ALREADY/0 and 1 archive file, got rc=$rc out=$out files=$_n"; fi

# SA4 — the destination name is taken, by DIFFERENT content. Refuse; do not overwrite an archive.
r=$(mk_root "$SPEC_A")
printf '%s\n' "$SPEC_B" >"$r/docs/specs/111-alpha-topic.spec.md"
out=$(bash "$SA" "$r" 111-alpha-topic 2>&1); rc=$?
if [ "$rc" -eq 1 ] && [ "${out%% *}" = "COLLISION" ] \
   && grep -q "222-beta-topic" "$r/docs/specs/111-alpha-topic.spec.md"; then
  ok "SA4 destination taken by different content → COLLISION, exit 1, archive untouched"
else bad "SA4 expected COLLISION/1 with the archive intact, got rc=$rc out=$out"; fi

# SA5 is the empty-or-unknown guard IN ITS NEW POSITION (issue #455), and the fixture is what makes
# it mean something different from SA16: the root HOLDS a SPEC.md that is NOT already archived under
# any name. That is the case where `unknown` is a genuinely confused caller — a file exists, it is
# not a no-op, and there is no slug to name its archive — and it is still refused. SA16 is the same
# slug with no file, and is now a no-op. One guard, two inputs, opposite correct answers.
#
# CORRECTION (2026-08-22, issue #408, ADR-0164): this comment used to justify the assertion as
# "defence-in-depth: a markerless SPEC routes to brownfield and never reaches this script" (rule 14
# — recorded forward, not rewritten in place, since the assertion below did not change, only its
# rationale). That premise is false: `unknown` also reaches this script whenever `OUT_SLUG` is not
# carried forward, independently of the SPEC's own marker, and 69 of 75 archived SPECs in this
# repository carry no marker at all. SA5 is correct only because its fixture is UNARCHIVED. SA5b
# below is the pair that #408 was actually about — the same unknown slug, on content that IS already
# archived — and that pair is now a no-op, not a halt.
r=$(mk_root "$SPEC_A")
out=$(bash "$SA" "$r" unknown 2>&1); rc=$?
if [ "$rc" -eq 3 ]; then ok "SA5 a SPEC.md that EXISTS, is NOT already archived, with an unknown slug → exit 3 (did not run), distinct from 0"
else bad "SA5 expected exit 3 for an unarchived SPEC with an unknown slug, got rc=$rc out=$out"; fi

# SA5b — THE assertion issue #408 exists for. Same fixture as SA5, except the content is already
# sitting in the archive under a DIFFERENT name — the common case (69/75 archived SPECs carry no
# `**Topic slug:**` marker, so `spec_topic_slug=unknown` for them too). Until #408 this returned
# exit 3, because the slug was validated before the content was ever compared.
# plant: SA5b | plugin/skills/concept-to-code/scripts/spec-archive.sh | if [ -d "$archive_dir" ]; then | if false; then
r=$(mk_root "$SPEC_A")
mkdir -p "$r/docs/specs"
printf '%s\n' "$SPEC_A" >"$r/docs/specs/already-archived-under-this-name.spec.md"
out=$(bash "$SA" "$r" unknown 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "ALREADY" ]; then
  ok "SA5b a SPEC.md that EXISTS and IS already archived byte-identically, unknown slug → ALREADY, exit 0 (#408)"
else bad "SA5b expected ALREADY/0 regardless of slug for already-archived content, got rc=$rc out=$out"; fi

out=$(bash "$SA" 2>&1); rc=$?
if [ "$rc" -eq 3 ]; then ok "SA6 bad invocation → exit 3"
else bad "SA6 expected exit 3 on no arguments, got rc=$rc"; fi

r=$(mk_root "$SPEC_A")
bash "$SA" "$r" 111-alpha-topic >/dev/null 2>&1
if [ -f "$r/SPEC.md" ]; then ok "SA7 it copies and never moves — the root slot survives"
else bad "SA7 the root SPEC.md was removed; the script must copy, never move"; fi

r=$(mk_root "$SPEC_A")
out=$(bash "$SA" "$r" "../../etc/passwd" 2>&1); rc=$?
if [ "$rc" -eq 3 ]; then ok "SA8 a slug that is not a bare name → exit 3"
else bad "SA8 expected exit 3 for a path-shaped slug, got rc=$rc out=$out"; fi

# ===========================================================================
# SA9/SA10 — one extractor, one answer. The slug comes FROM gate0-detect.sh.
# ===========================================================================
r=$(mk_root "$SPEC_B")
out=$(bash "$G0" "$r" "some title" 111-alpha-topic 2>&1)
if printf '%s\n' "$out" | grep -qx "spec_topic_slug=222-beta-topic"; then
  ok "SA9 gate0-detect.sh emits spec_topic_slug taken from the existing SPEC's marker"
else bad "SA9 gate0-detect.sh did not emit spec_topic_slug=222-beta-topic; got: $(printf '%s' "$out" | tr '\n' ' ')"; fi

r=$(mk_root "# SPEC with no marker at all")
out=$(bash "$G0" "$r" "some title" 111-alpha-topic 2>&1)
if printf '%s\n' "$out" | grep -qx "spec_topic_slug=unknown"; then
  ok "SA9b a SPEC with no marker reports spec_topic_slug=unknown"
else bad "SA9b expected spec_topic_slug=unknown for a markerless SPEC"; fi

# SA9c — issue #455 claimed the two states that both report `spec_topic_slug=unknown` are
# indistinguishable in this script's output. MEASURED, THEY ARE NOT, and that is why gate0-detect.sh
# is untouched by #455: `spec_owned` is "no" only when the file is ABSENT, so `mode` separates them.
# Neither field distinguishes alone — the PAIR does, uniquely:
#
#     no SPEC.md         → mode=greenfield  spec_topic_slug=unknown
#     SPEC.md, no marker → mode=brownfield  spec_topic_slug=unknown
#
# Asserted in BOTH directions, because a check that only confirms the greenfield row would pass on a
# gate0-detect.sh that reported greenfield for everything. This also keeps #455 clear of #454, which
# is about a different consumer of the same token.
r=$(mk_root)                                   # no SPEC.md at all
_abs=$(bash "$G0" "$r" "some title" 111-alpha-topic 2>&1)
r=$(mk_root "# SPEC with no marker at all")    # a file, but nothing naming a topic
_nom=$(bash "$G0" "$r" "some title" 111-alpha-topic 2>&1)
if printf '%s\n' "$_abs" | grep -qx "mode=greenfield" \
   && printf '%s\n' "$_abs" | grep -qx "spec_topic_slug=unknown" \
   && printf '%s\n' "$_nom" | grep -qx "mode=brownfield" \
   && printf '%s\n' "$_nom" | grep -qx "spec_topic_slug=unknown"; then
  ok "SA9c an absent SPEC and a markerless SPEC are distinguishable by (mode, spec_topic_slug)"
else
  bad "SA9c the two unknown-slug states collapsed: absent=[$(printf '%s' "$_abs" | tr '\n' ' ')] markerless=[$(printf '%s' "$_nom" | tr '\n' ' ')]"
fi

# SA10 — the argument wins over the marker, asserted by RUNNING it rather than by grepping for the
# words. The first draft was lexical (`grep -iE 'topic[[:space:]]+slug'`) and failed on a CORRECT
# script: it matched the comment EXPLAINING why the slug is not re-derived. Rule 12, third instance
# in this repository — a scan whose needle is a literal counts its own explanation. A behavioural
# check cannot be satisfied by prose.
r=$(mk_root "$SPEC_B")                       # marker says 222-beta-topic
bash "$SA" "$r" 111-alpha-topic >/dev/null 2>&1
if [ -f "$r/docs/specs/111-alpha-topic.spec.md" ] && [ ! -f "$r/docs/specs/222-beta-topic.spec.md" ]; then
  ok "SA10 the archive is named from the ARGUMENT, not from the SPEC's own marker (one extractor)"
else
  bad "SA10 spec-archive.sh named the archive from the SPEC's marker — a second extractor that can disagree with gate0-detect.sh (ADR-0086)"
fi

# ===========================================================================
# SA11..SA14 — the wiring. A correct script nothing calls is issue #238's shape.
# ===========================================================================
G_A=$(grep -n '^\*\*Greenfield\*\*' "$C2C" | head -1 | cut -d: -f1)
G_B=$(grep -n '^\*\*Brownfield\*\*' "$C2C" | head -1 | cut -d: -f1)
if [ -n "${G_A:-}" ] && [ -n "${G_B:-}" ] && [ "$G_B" -gt "$G_A" ]; then
  ok "SA11 Step 1 branch anchors resolve ($G_A..$G_B)"
else
  bad "SA11 Step 1 branch anchors did not resolve — SA12/SA13/SA14 assert nothing without them"
fi
_green=$(awk -v a="${G_A:-0}" -v b="${G_B:-0}" 'NR>=a && NR<b' "$C2C")
_green_flat=$(printf '%s\n' "$_green" | tr '\n' ' ' | tr -s ' ')

if printf '%s\n' "$_green" | grep -q 'spec-archive.sh'; then
  ok "SA12 Step 1's greenfield branch invokes spec-archive.sh before the dispatch"
else
  bad "SA12 Step 1's greenfield branch does not call spec-archive.sh — the guard exists and nothing runs it (#228)"
fi

if printf '%s\n' "$_green" | grep -qF 'fence-contract: c2c-step1-spec-archive'; then
  ok "SA13 the archive block is a declared fence-contract (ADR-0083)"
else
  bad "SA13 the archive block can abort and carries no fence-contract marker"
fi

# The comment that was true of only one of the two states reaching this branch.
if printf '%s\n' "$_green_flat" | grep -q 'two different states reach this branch' \
   && printf '%s\n' "$_green_flat" | grep -q 'spec_topic_match=false'; then
  ok "SA14 the greenfield branch states both routes into it, not just 'SPEC.md does not exist'"
else
  bad "SA14 the greenfield branch still describes only the empty-slot route"
fi

# SA14b — the corrected no-op claim (issue #455). THIS ASSERTION PINS PROSE, and prose is an
# instruction, not an enforcement (CLAUDE.md rule 16): it cannot make the ordering in
# spec-archive.sh correct, and SA16/SF5 are what do that. What it buys is that the sentence which
# was false for two months cannot quietly return to its short form — the branch would then claim a
# no-op again while the mechanism behind it is the only thing making the claim true.
# Matched on the FLATTENED copy (rule 3): the clause wraps across lines in the source.
if printf '%s\n' "$_green_flat" | grep -q 'looks for the file before it validates the slug'; then
  ok "SA14b the no-op claim names the ordering it depends on, not just the outcome"
else
  bad "SA14b the greenfield branch claims a no-op on the empty root without naming what makes it one (#455)"
fi

if grep -qF 'plugin/skills/concept-to-code/scripts/spec-archive.sh|skills/concept-to-code/scripts/spec-archive.sh' "$SYNC"; then
  ok "SA15 spec-archive.sh has a PAIRS entry — without it the fence exits 3 and halts every chain"
else
  bad "SA15 spec-archive.sh is missing from PAIRS; it would never deploy and Step 1 would abort"
fi

# ===========================================================================
# SF — the fence is EXECUTED, not merely declared.
#
# `fence-contract-coverage.test.sh` F4 does not reach it: `fence_is_abort_capable` is lexical and
# looks for `exit 1`/`exit 2` or the word "abort", while this fence ends `exit "$_rc"` and its abort
# is the CALLER's, on rc 1 or 3. So the fence aborts a chain in practice and is invisible to the
# classifier — a real boundary of ADR-0083's population, recorded rather than worked around.
#
# Bespoke marker-anchored extractor, the pattern ADR-0083 §D3 established for the four fences
# `scope-guards.test.sh` and `plan-task-count.test.sh` already owned. Naming the id in the anchor is
# what makes the coverage claim verified rather than declared: fence-contract: c2c-step1-spec-archive -->
# ===========================================================================
FBODY="$TMP/fence.sh"
awk '/fence-contract: c2c-step1-spec-archive -->/{m=1; next}
     m && /^```bash$/{f=1; next}
     f && /^```$/{exit}
     f{print}' "$C2C" >"$FBODY"

if [ -s "$FBODY" ] && grep -q 'spec-archive.sh' "$FBODY"; then
  ok "SF1 the fence body extracts by marker and is non-empty"
else
  bad "SF1 the fence body did not extract — the marker moved, and SF2..SF4 assert nothing"
fi

# A fixture HOME holding the deployed script, since the fence resolves through $HOME.
FHOME="$TMP/fhome"
mkdir -p "$FHOME/.claude/skills/concept-to-code/scripts"
cp "$SA" "$FHOME/.claude/skills/concept-to-code/scripts/spec-archive.sh"

run_fence_body() {  # <root> <out-slug> <home>
  HOME="$3" ROOT="$1" OUT_SLUG="$2" bash "$FBODY" 2>&1
}

r=$(mk_root "$SPEC_A")
out=$(run_fence_body "$r" 111-alpha-topic "$FHOME"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^ARCHIVED '; then
  ok "SF2 the fence archives and returns 0"
else bad "SF2 expected rc=0 and an ARCHIVED line, got rc=$rc out=$out"; fi

r=$(mk_root "$SPEC_A")
printf '%s\n' "$SPEC_B" >"$r/docs/specs/111-alpha-topic.spec.md"
out=$(run_fence_body "$r" 111-alpha-topic "$FHOME"); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^COLLISION '; then
  ok "SF3 the fence propagates COLLISION as rc=1 — the caller's halt branch"
else bad "SF3 expected rc=1 and a COLLISION line, got rc=$rc out=$out"; fi

r=$(mk_root "$SPEC_A")
out=$(run_fence_body "$r" 111-alpha-topic "$TMP/empty-home"); rc=$?
if [ "$rc" -eq 3 ] && printf '%s\n' "$out" | grep -q 'SPECARCHIVE_NOSCRIPT'; then
  ok "SF4 an unsynced machine returns 3 (did not run), never a silent 0"
else bad "SF4 expected rc=3 and SPECARCHIVE_NOSCRIPT, got rc=$rc out=$out"; fi

# SF5 — the bootstrap path, end to end, through the REAL fence (issue #455). This is the strongest
# form of the SA16 claim and the reason it is worth a second assertion: the body under test is
# extracted from SKILL.md by its fence-contract marker, so what runs here is the orchestrator's own
# code receiving the orchestrator's own pair — an empty root and the `unknown` that gate0-detect.sh
# emits for it. SA16 proves the script; this proves the wiring, including the `${OUT_SLUG:-unknown}`
# default that turns an unset variable into the very slug the guard used to refuse.
# rc 0 is the assertion. Under the pre-#455 ordering this returned 3, and the caller's contract on
# 3 is HALT, so a brand-new project stopped here with the message that a check did not run.
r=$(mk_root)
out=$(run_fence_body "$r" unknown "$FHOME"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^NOSPEC$'; then
  ok "SF5 the fence is a genuine no-op on an empty root — the documented claim, now true"
else bad "SF5 the empty-root bootstrap halts at the fence again: expected rc=0 and NOSPEC, got rc=$rc out=$out"; fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 20 ]; then ok "Z1 assertion-count floor ($_total >= 20)"
else bad "Z1 assertion count fell to $_total (floor 20) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
