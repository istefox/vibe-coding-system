#!/bin/bash
# transition-pair-count.test.sh — offline, hermetic, no network, no $HOME dependency.
# Issue #289 / ADR-0120. Section TC.
#
# `transition-pair-count.sh` does not exist yet. Every assertion below except TC0 is RED right now
# by construction — `bash "$CHECKER" ...` on a missing file returns 127, which is outside the
# checker's own {0,1,2,3} contract (TC1), so every downstream comparison fails too. That is the
# deliverable of this file: it must go RED, not green, until Task 2 creates the checker.
#
# THE RULE UNDER TEST (ADR-0120 D1/D2): the derivation is BLOCK-BOUNDED (anchored between
# `PAIRS="$(mktemp)"` and `if ! grep -Fxq`) AND DISTINCT (`grep -Fxq` semantics — a duplicate line
# is a no-op). Three existing derivations each get one half right and one half wrong (M3); TC4/TC5
# isolate the two halves so a one-sided extractor cannot satisfy this file.
#
# Fixtures patch COPIES of the REAL manifest-transition.sh / SKILL.md (never hand-written minimal
# files — ADR-0078's lesson: a hand-written fixture trips unrelated structure and reports a failure
# about everything except the thing under test).
#
# Rule 12 (this file's own needles): a needle asserting a SITE is stale must belong to the anchor
# ADR-0120 D4 names for that site, never to the bare number — `45` occurs in ordinary prose all over
# this file's own comments.
#
# `grep -c … || echo 0` yields the two-line string `0\n0` on no match — `|| true` is used throughout.
# Bash 3.2 / BSD-tools clean. Run: bash transition-pair-count.test.sh
set -u

TESTS=$(cd "$(dirname "$0")" && pwd)
STAGING=$(cd "$TESTS/../../.." && pwd)
SKILL_DIR="$STAGING/plugin/skills/concept-to-code"
REAL_TR="$SKILL_DIR/scripts/manifest-transition.sh"
REAL_SKILL="$SKILL_DIR/SKILL.md"
CHECKER="$TESTS/transition-pair-count.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for _f in "$REAL_TR" "$REAL_SKILL"; do
  [ -r "$_f" ] || { echo "FATAL: missing/unreadable $_f"; exit 1; }
done

# ---------------------------------------------------------------------------------------------
# Fixture primitives — literal substring operations via awk index()/substr(), never a BRE, so a
# needle containing `$`, `(`, `)`, an em-dash or `§` needs no escaping.
# ---------------------------------------------------------------------------------------------
lit_replace() {  # src needle replacement -> stdout
  awk -v n="$2" -v r="$3" '
    { line=$0; out=""
      while ((i = index(line, n)) > 0) { out = out substr(line,1,i-1) r; line = substr(line, i+length(n)) }
      print out line
    }' "$1"
}
insert_after() {  # src needle newtext -> stdout
  awk -v n="$2" -v ins="$3" '{ print; if (index($0, n) > 0) print ins }' "$1"
}
insert_before() {  # src needle newtext -> stdout
  awk -v n="$2" -v ins="$3" '{ if (index($0, n) > 0) print ins; print }' "$1"
}

# ---------------------------------------------------------------------------------------------
# Fixture generation. M3's five-row table becomes four mutated copies of manifest-transition.sh
# (the real script is the table's fifth, unmutated row). Nine more copies isolate the literal
# sites (TC9-TC13).
# ---------------------------------------------------------------------------------------------
FX_DUP="$TMP/tr-dup.sh"
insert_after "$REAL_TR" 'echo "step_0_init,step_1_interview" > "$PAIRS"' \
  '  echo "step_0_init,step_1_interview" >> "$PAIRS"' >"$FX_DUP"

FX_OUTSIDE="$TMP/tr-outside.sh"
insert_after "$REAL_TR" 'set -u' 'echo "outside_pair,outside_target" >> "$PAIRS"' >"$FX_OUTSIDE"

FX_NEWPAIR="$TMP/tr-newpair.sh"
insert_before "$REAL_TR" 'if ! grep -Fxq "$current_step,$new_step" "$PAIRS"' \
  '  echo "zzz_new_from,zzz_new_to" >> "$PAIRS"' >"$FX_NEWPAIR"

FX_RENAMED="$TMP/tr-renamed.sh"
lit_replace "$REAL_TR" 'PAIRS="$(mktemp)"' 'PAIRSX="$(mktemp)"' >"$FX_RENAMED"

FX_COMMENT_WRONG="$TMP/tr-comment-wrong.sh"
lit_replace "$REAL_TR" '45 transitions)' '46 transitions)' >"$FX_COMMENT_WRONG"

FX_HDR_WRONG="$TMP/skill-hdr-wrong.md"
lit_replace "$REAL_SKILL" '(45 total — 25 standard + 6 express + 14 hybrid' \
  '(46 total — 25 standard + 6 express + 14 hybrid' >"$FX_HDR_WRONG"

FX_HELPER_WRONG="$TMP/skill-helper-wrong.md"
lit_replace "$REAL_SKILL" 'atomically (45 pairs).' 'atomically (46 pairs).' >"$FX_HELPER_WRONG"

FX_SUM_WRONG="$TMP/skill-sum-wrong.md"
lit_replace "$REAL_SKILL" '(45 total — 25 standard + 6 express + 14 hybrid' \
  '(45 total — 20 standard + 6 express + 14 hybrid' >"$FX_SUM_WRONG"

FX_STD_WRONG="$TMP/skill-std-wrong.md"
lit_replace "$REAL_SKILL" '(45 total — 25 standard + 6 express + 14 hybrid' \
  '(45 total — 20 standard + 11 express + 14 hybrid' >"$FX_STD_WRONG"

# ===========================================================================
# TC0 — denominator guard (ADR-0085): every fixture actually differs from its unmutated source.
# A patch primitive that silently no-ops would make every downstream TC compare a real file
# against itself, which passes for the wrong reason.
# ===========================================================================
_fx_bad=0
for pair in "$FX_DUP:$REAL_TR" "$FX_OUTSIDE:$REAL_TR" "$FX_NEWPAIR:$REAL_TR" "$FX_RENAMED:$REAL_TR" \
            "$FX_COMMENT_WRONG:$REAL_TR" "$FX_HDR_WRONG:$REAL_SKILL" "$FX_HELPER_WRONG:$REAL_SKILL" \
            "$FX_SUM_WRONG:$REAL_SKILL" "$FX_STD_WRONG:$REAL_SKILL"; do
  _fx="${pair%%:*}"; _src="${pair#*:}"
  if [ ! -s "$_fx" ]; then _fx_bad=$((_fx_bad+1)); continue; fi
  cmp -s "$_fx" "$_src" && _fx_bad=$((_fx_bad+1))
done
if [ "$_fx_bad" -eq 0 ] && [ -r "$REAL_TR" ] && [ -r "$REAL_SKILL" ]; then
  ok "TC0 all 9 fixtures generated, each differs from its real source; real files readable"
else
  bad "TC0 $_fx_bad fixture(s) missing/unchanged/empty, or a real source is unreadable"
fi

# ---------------------------------------------------------------------------------------------
# Invocation helper. RC/OUT/ERR are set for the caller to inspect.
# ---------------------------------------------------------------------------------------------
run_checker() {  # tr_file skill_file
  _o="$TMP/o.$$.$RANDOM"; _e="$TMP/e.$$.$RANDOM"
  bash "$CHECKER" "$1" "$2" >"$_o" 2>"$_e"
  RC=$?
  OUT="$(cat "$_o")"
  ERR="$(cat "$_e")"
  rm -f "$_o" "$_e"
}
flat() { printf '%s' "$1" | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }

run_checker "$REAL_TR" "$REAL_SKILL"
REAL_RC=$RC; REAL_OUT="$OUT"; REAL_ERR="$ERR"

# ===========================================================================
# TC1 — the checker exists, is readable, and stays within its own {0,1,2,3} exit contract.
# ===========================================================================
if [ -r "$CHECKER" ] && { [ "$REAL_RC" -eq 0 ] || [ "$REAL_RC" -eq 1 ] || [ "$REAL_RC" -eq 2 ] || [ "$REAL_RC" -eq 3 ]; }; then
  ok "TC1 checker exists and exits within {0,1,2,3} (rc=$REAL_RC)"
else
  bad "TC1 checker missing or exits outside its own contract (rc=$REAL_RC) — expected the checker to exist"
fi

# ===========================================================================
# TC2 — on the real tree: exit 0 and stdout EMPTY. Emptiness is part of the contract.
# ===========================================================================
if [ "$REAL_RC" -eq 0 ] && [ -z "$REAL_OUT" ]; then
  ok "TC2 real tree: exit 0, stdout empty"
else
  bad "TC2 real tree: rc=$REAL_RC stdout=[$REAL_OUT] — expected rc=0 and empty stdout"
fi

# ===========================================================================
# TC3 — the stderr statistics line is printed on every run, naming pairs/standard/express/hybrid.
# ===========================================================================
_stats="$(flat "$REAL_ERR")"
if printf '%s' "$_stats" | grep -q 'pairs=45' \
   && printf '%s' "$_stats" | grep -q 'standard=25' \
   && printf '%s' "$_stats" | grep -q 'express=6' \
   && printf '%s' "$_stats" | grep -q 'hybrid=14'; then
  ok "TC3 stderr states pairs=45 standard=25 express=6 hybrid=14"
else
  bad "TC3 stderr does not state the expected statistics line: [$REAL_ERR]"
fi

# ===========================================================================
# TC4 — duplicate pair line: derived count stays 45 (DISTINCT), not 46.
# ===========================================================================
run_checker "$FX_DUP" "$REAL_SKILL"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "TC4 a duplicated pair line does not move the count (distinct)"
else
  bad "TC4 duplicate-line fixture: rc=$RC stdout=[$OUT] — expected rc=0/empty (dedup must hold)"
fi

# ===========================================================================
# TC5 — pair-shaped echo OUTSIDE the block: stays 45 (BOUNDED), not 46.
# ===========================================================================
run_checker "$FX_OUTSIDE" "$REAL_SKILL"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "TC5 a pair-shaped echo outside the block does not move the count (bounded)"
else
  bad "TC5 out-of-block fixture: rc=$RC stdout=[$OUT] — expected rc=0/empty (bounding must hold)"
fi

# ===========================================================================
# TC6 — one genuinely new pair: becomes 46; findings reported (exit 1) because the three
# literals still say 45.
# ===========================================================================
run_checker "$FX_NEWPAIR" "$REAL_SKILL"
if [ "$RC" -eq 1 ] && [ -n "$OUT" ]; then
  ok "TC6 a genuinely new pair moves the count to 46 and is reported as a finding"
else
  bad "TC6 new-pair fixture: rc=$RC stdout=[$OUT] — expected rc=1 with a non-empty finding"
fi

# ===========================================================================
# TC7 — block opening marker renamed: exit 3 (DID NOT RUN), never 0 or 1.
# ===========================================================================
run_checker "$FX_RENAMED" "$REAL_SKILL"
_err_flat="$(flat "$ERR")"
if [ "$RC" -eq 3 ] && printf '%s' "$_err_flat" | grep -q 'did not run'; then
  ok "TC7 a renamed block marker makes the derivation report DID NOT RUN (exit 3)"
else
  bad "TC7 renamed-marker fixture: rc=$RC stderr=[$ERR] — expected rc=3 naming 'did not run'"
fi

# ===========================================================================
# TC8 — wrong argument count -> exit 2.
# ===========================================================================
bash "$CHECKER" "$REAL_TR" >/dev/null 2>"$TMP/e8"
_rc8=$?
if [ "$_rc8" -eq 2 ]; then
  ok "TC8 wrong argument count exits 2"
else
  bad "TC8 wrong argument count exits $_rc8, expected 2"
fi

# TC8b — unreadable/nonexistent target file -> exit 2, distinct from 3.
bash "$CHECKER" "$REAL_TR" "$TMP/does-not-exist.md" >/dev/null 2>"$TMP/e8b"
_rc8b=$?
if [ "$_rc8b" -eq 2 ]; then
  ok "TC8b an unreadable/nonexistent target file exits 2"
else
  bad "TC8b unreadable target file exits $_rc8b, expected 2"
fi

# ===========================================================================
# TC9 — SKILL.md header states a wrong TOTAL (46) while the script still builds 45 -> finding
# naming the header site (`Legal transition pairs (<n> total`, ADR-0120 D4).
# ===========================================================================
run_checker "$REAL_TR" "$FX_HDR_WRONG"
_o9="$(flat "$OUT")"
if [ "$RC" -eq 1 ] && printf '%s' "$_o9" | grep -q 'legal transition pairs'; then
  ok "TC9 a wrong header total is reported, naming the header site"
else
  bad "TC9 wrong-header-total fixture: rc=$RC stdout=[$OUT] — expected rc=1 naming the header"
fi

# ===========================================================================
# TC10 — SKILL.md's `(45 pairs)` helper-description line states a wrong total -> finding naming
# THAT site (`atomically (<n> pairs)`), the site nothing covered before this chain (M6).
# ===========================================================================
run_checker "$REAL_TR" "$FX_HELPER_WRONG"
_o10="$(flat "$OUT")"
if [ "$RC" -eq 1 ] && printf '%s' "$_o10" | grep -q 'atomically'; then
  ok "TC10 a wrong (45 pairs) helper line is reported, naming that site"
else
  bad "TC10 wrong-helper-line fixture: rc=$RC stdout=[$OUT] — expected rc=1 naming 'atomically'"
fi

# ===========================================================================
# TC11 — manifest-transition.sh's own comment states a wrong total -> finding naming the
# comment site (`§3.3, <n> transitions`).
# ===========================================================================
run_checker "$FX_COMMENT_WRONG" "$REAL_SKILL"
_o11="$(flat "$OUT")"
if [ "$RC" -eq 1 ] && printf '%s' "$_o11" | grep -q 'transitions)'; then
  ok "TC11 a wrong script-comment total is reported, naming the comment site"
else
  bad "TC11 wrong-comment fixture: rc=$RC stdout=[$OUT] — expected rc=1 naming the comment"
fi

# ===========================================================================
# TC12 — the header's own <n> standard + <n> express + <n> hybrid triple does not sum to the
# stated total -> finding naming the sub-count (structurally malformed, before any comparison
# to the script).
# ===========================================================================
run_checker "$REAL_TR" "$FX_SUM_WRONG"
_o12="$(flat "$OUT")"
if [ "$RC" -eq 1 ] && printf '%s' "$_o12" | grep -q 'standard'; then
  ok "TC12 a header triple that does not sum to its own total is reported, naming the sub-count"
else
  bad "TC12 non-summing-triple fixture: rc=$RC stdout=[$OUT] — expected rc=1 naming 'standard'"
fi

# ===========================================================================
# TC13 — the header's `standard` sub-count disagrees with the script's own derived per-block
# count while the stated TOTAL is right (D-A's own shape: SKILL.md's header/bullet
# contradiction) -> finding, caught mechanically rather than by a human noticing.
# ===========================================================================
run_checker "$REAL_TR" "$FX_STD_WRONG"
_o13="$(flat "$OUT")"
if [ "$RC" -eq 1 ] && printf '%s' "$_o13" | grep -q 'standard'; then
  ok "TC13 a wrong standard sub-count is reported even though the stated total is right"
else
  bad "TC13 wrong-standard-subcount fixture: rc=$RC stdout=[$OUT] — expected rc=1 naming 'standard'"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3), a floor and never an exact count.
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 14 ]; then
  ok "Z1 assertion-count floor ($_total >= 14)"
else
  bad "Z1 assertion count fell to $_total (floor 14) — assertions vanished from this file"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
