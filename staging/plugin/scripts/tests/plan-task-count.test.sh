#!/bin/bash
# plan-task-count.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash plan-task-count.test.sh
#
# Covers issue #174: `n=$(grep -c PATTERN FILE 2>/dev/null || echo 0)` at the two sites that count
# unchecked plan tasks. `grep -c` PRINTS `0` **and** EXITS 1 when there is no match, so the `||`
# fallback appends a SECOND line and the variable holds the two-line string `0\n0`. A numeric test
# on it does not evaluate — it errors with `integer expression expected` and returns 2.
#
# ASSERTION LABELS ARE PT-PREFIXED (PT0, PTA1, PTB2, ...) to stay distinguishable from every other
# harness printing into the same CI shell-tests job (B-, R-, W-, ...).
#
# WHAT IS AND IS NOT FIX EVIDENCE, stated per assertion below and summarised here, because this
# file's two behavioural fixtures fail in OPPOSITE directions:
#   - PTA*  is a live DEMONSTRATION of the bug's shape against `grep` itself. It passes before and
#           after the fix by construction. It is not evidence of anything having been fixed.
#   - PTB*, PTC1, PTC4, PTD*  were seen RED against the pre-fix tree. These are the fix evidence.
#   - PTC2, PTC3  pass before and after. PTC2 pins the intended EXIT behaviour (which the bug
#           reproduced by accident, via a failed comparison rather than a real one) and PTC3 is the
#           POSITIVE TWIN of PTC1: a check that fails on every input would satisfy a zero-task
#           assertion alone, so the two-task fixture is what makes PTC1 mean something. Rule (8)
#           of .claude/context.md, applied at the point where it bites.
#
# PTD is a repo-wide forward guard, and it deliberately scans only EXECUTABLE context. This
# repository documents the broken idiom verbatim in at least seven prose warnings
# (concept-to-code/SKILL.md, secret-scan.sh, interface-check.sh, untrusted-input-scan.sh,
# diff-budget-check.sh, weakening-wiring.test.sh, roadmap-from-issues.sh) and DEMONSTRATES it
# deliberately in three sibling harnesses, which must never trip their own guard. Three filters,
# each narrowing a distinct false-positive class:
#   1. comment lines are skipped, and in Markdown only ```bash fences are read at all;
#   2. the match must sit inside a command substitution (`$(` or a backtick) — that is what makes it
#      a captured VALUE rather than a message string or a `grep -qF` needle;
#   3. a line carrying the literal waiver `idiom-demo` is skipped as a declared demonstration.
# Filter 3 is a DECLARED exemption, not an identity exemption: this file is scanned like any other
# and its own PTA1 demonstration carries the marker. No file is trusted for being itself.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
AB="$STAGING/plugin/skills/autopilot-build/SKILL.md"

# ==================================================================================================
# PT0. Anchors. Every assertion below is meaningless without these.
# ==================================================================================================
[ -f "$CC" ] && [ -r "$CC" ] \
  && ok "PT0a: concept-to-code/SKILL.md exists and is readable" \
  || bad "PT0a: $CC not found or unreadable"
[ -f "$AB" ] && [ -r "$AB" ] \
  && ok "PT0b: autopilot-build/SKILL.md exists and is readable" \
  || bad "PT0b: $AB not found or unreadable"

# --- extract the body of the first ```-fenced block that follows a marker line. The marker is
# matched with index(), not as a regex: the markers here carry `**` and an em-dash, and awk's -v
# processes escape sequences before the regex engine ever sees them. ---
extract_fence() {
  awk -v m="$2" '
    !found && index($0, m) { found=1; next }
    found && /^```/  { infence = !infence; if (!infence) exit; next }
    found && infence { print }
  ' "$1"
}

# ==================================================================================================
# PTA. Live demonstration of the bug's shape, against `grep` itself.
#      NOT FIX EVIDENCE — passes before and after by construction.
# ==================================================================================================
: > "$TMP/nomatch.txt"

pta_wrong=$(grep -c 'NEEDLE' "$TMP/nomatch.txt" 2>/dev/null || echo 0)   # idiom-demo (PTD filter 3)
pta_wrong_lines=$(printf '%s\n' "$pta_wrong" | grep -c .)
[ "$pta_wrong_lines" = "2" ] \
  && ok "PTA1 (demonstration): grep -c … || echo 0 yields TWO lines on no match" \
  || bad "PTA1 (demonstration): expected 2 lines from the broken idiom, got $pta_wrong_lines"

pta_err=$( { [ "$pta_wrong" -ge 1 ]; } 2>&1 >/dev/null )
case "$pta_err" in
  *"integer expression expected"*)
    ok "PTA2 (demonstration): a numeric test on the two-line value errors, it does not compare" ;;
  *)
    bad "PTA2 (demonstration): expected 'integer expression expected', got [$pta_err]" ;;
esac

pta_c=$(grep -c 'NEEDLE' "$TMP/nomatch.txt" 2>/dev/null); pta_right=${pta_c:-0}
pta_right_lines=$(printf '%s\n' "$pta_right" | grep -c .)
{ [ "$pta_right_lines" = "1" ] && [ "$pta_right" = "0" ]; } \
  && ok "PTA3 (demonstration): the canonical idiom (secret-scan.sh:103 shape) yields the single line 0" \
  || bad "PTA3 (demonstration): canonical idiom gave [$pta_right] over $pta_right_lines line(s)"

printf '# Plan\n\nAll done.\n\n- [x] Task 1 — done\n' > "$TMP/plan-zero.md"
printf '# Plan\n\n- [ ] Task 1 — pending\n- [x] Task 2 — done\n- [ ] Task 3 — pending\n' > "$TMP/plan-two.md"

pta_guarded=$(grep -c -e '- \[ \]' "$TMP/plan-two.md" 2>/dev/null)
pta_unguarded_rc=0
grep -c '- \[ \]' "$TMP/plan-two.md" >/dev/null 2>&1 || pta_unguarded_rc=$?
[ "${pta_guarded:-x}" = "2" ] \
  && ok "PTA4 (demonstration): -e counts both unchecked tasks; the unguarded form exits $pta_unguarded_rc because grep reads the leading dash as an option" \
  || bad "PTA4 (demonstration): grep -c -e '- \\[ \\]' returned [${pta_guarded:-}] on a 2-task plan, expected 2"

# ==================================================================================================
# PTB. Static: both counting sites are guarded against BOTH defects. SEEN RED before the fix.
#      Defect 1 (the one #174 names): the `|| echo 0` fallback and its two-line value.
#      Defect 2 (found while writing PTC): the pattern `'- \[ \]'` STARTS WITH A DASH, so grep
#      consumes it as an option, exits 2 without running, and the site reports nothing for EVERY
#      plan — not only for the heading-form plans of the sibling issue #172.
# ==================================================================================================
ptb_line_cc=$(grep -n "grep -c" "$CC" | grep "\[ ")
ptb_line_ab=$(grep -n "grep -c" "$AB" | grep "\[ ")

printf '%s\n' "$ptb_line_cc" | grep -q '|| echo 0' \
  && bad "PTB1: concept-to-code/SKILL.md still counts plan tasks with || echo 0" \
  || ok "PTB1: concept-to-code plan-structure count carries no || echo 0 fallback"

printf '%s\n' "$ptb_line_ab" | grep -q '|| echo 0' \
  && bad "PTB2: autopilot-build/SKILL.md still counts plan tasks with || echo 0" \
  || ok "PTB2: autopilot-build check 5 count carries no || echo 0 fallback"

printf '%s\n' "$ptb_line_cc" | grep -qE "grep -c (-e|--) " \
  && ok "PTB3: concept-to-code plan count guards the leading dash (-e or --)" \
  || bad "PTB3: concept-to-code plan count passes a dash-leading pattern unguarded: $ptb_line_cc"

printf '%s\n' "$ptb_line_ab" | grep -qE "grep -c (-e|--) " \
  && ok "PTB4: autopilot-build check 5 guards the leading dash (-e or --)" \
  || bad "PTB4: autopilot-build check 5 passes a dash-leading pattern unguarded: $ptb_line_ab"

# ==================================================================================================
# PTC. Behavioural: the check-5 block is EXTRACTED FROM THE SKILL FILE and executed against two
#      fixtures. Executing the real text is what stops this file from drifting away from the block
#      it claims to pin.
# ==================================================================================================
AB_BLOCK=$(extract_fence "$AB" '**Check 5 — Plan has unchecked work:**')
if [ -z "$AB_BLOCK" ]; then
  bad "PTC0: could not extract the 'Check 5 — Plan has unchecked work' block from autopilot-build/SKILL.md — PTC1..PTC3 skipped"
else
  ok "PTC0: check-5 block extracted from autopilot-build/SKILL.md"

  run_check5() {
    { printf 'plan=%s\n' "$1"; printf '%s\n' "$AB_BLOCK"; } > "$TMP/check5.sh"
    bash "$TMP/check5.sh" >"$TMP/c5.out" 2>"$TMP/c5.err"
    printf '%s' "$?"
  }

  ptc1_rc=$(run_check5 "$TMP/plan-zero.md")
  if grep -q 'integer expression' "$TMP/c5.err"; then
    bad "PTC1: check 5 on a zero-task plan errors instead of comparing: $(cat "$TMP/c5.err")"
  else
    ok "PTC1: check 5 on a zero-task plan compares a real integer (no shell error on stderr)"
  fi

  { [ "$ptc1_rc" = "1" ] && grep -q 'no unchecked tasks' "$TMP/c5.out"; } \
    && ok "PTC2 (forward guard, green before and after): zero-task plan aborts with the intended message" \
    || bad "PTC2: zero-task plan gave rc=$ptc1_rc, stdout=[$(cat "$TMP/c5.out")]"

  ptc3_rc=$(run_check5 "$TMP/plan-two.md")
  { [ "$ptc3_rc" = "0" ] && [ ! -s "$TMP/c5.err" ] && [ ! -s "$TMP/c5.out" ]; } \
    && ok "PTC3 (positive twin of PTC1): two-task plan passes check 5 silently" \
    || bad "PTC3: two-task plan gave rc=$ptc3_rc, stdout=[$(cat "$TMP/c5.out")], stderr=[$(cat "$TMP/c5.err")]"
fi

CC_BLOCK=$(extract_fence "$CC" '**Pre-dispatch: plan structure validation')
if [ -z "$CC_BLOCK" ]; then
  bad "PTC4: could not extract the plan-structure-validation block from concept-to-code/SKILL.md"
else
  # The c2c site has no numeric test — its value is consumed by prose ("If `unchecked = 0`"), so the
  # failure mode is a MODEL reading `0\n0` and concluding zero for the wrong reason. Assert the
  # shape of the value, which is the only thing that site can be wrong about.
  printf '%s\n' "$CC_BLOCK" | sed "s|<manifest.artifacts.plan>|$TMP/plan-zero.md|" > "$TMP/ccblock.sh"
  printf 'printf "%%s" "$unchecked" | grep -c .\n' >> "$TMP/ccblock.sh"
  ptc4_lines=$(bash "$TMP/ccblock.sh" 2>/dev/null)
  [ "$ptc4_lines" = "1" ] \
    && ok "PTC4: concept-to-code plan count yields a single-line value on a zero-task plan" \
    || bad "PTC4: concept-to-code plan count yielded $ptc4_lines line(s) — the model would read '0\\n0'"
fi

# ==================================================================================================
# PTD. Repo-wide forward guard. #174's root cause is that every past instance was fixed only where a
#      comment happened to be written, so this scans staging/ as a whole rather than the two sites.
#      Executable context only — see the header note on the seven prose warnings.
# ==================================================================================================
# filters 2 and 3, applied identically to both scans
ptd_narrow() { grep '|| echo 0' | grep -e '\$(' -e '`' | grep -v 'idiom-demo'; }

# --- shell sources: every non-comment line ---
PTD_SH_FILES=0
: > "$TMP/ptd-hits.txt"
while IFS= read -r f; do
  PTD_SH_FILES=$((PTD_SH_FILES+1))
  grep -n 'grep -c' "$f" 2>/dev/null \
    | grep -v '^[0-9]*:[[:space:]]*#' \
    | ptd_narrow \
    | sed "s|^|${f}:|" >> "$TMP/ptd-hits.txt"
done <<EOF
$(find "$STAGING" -type f -name '*.sh')
EOF

# --- Markdown: only inside ```bash fences, and not on a comment line ---
PTD_MD_FILES=0
while IFS= read -r f; do
  PTD_MD_FILES=$((PTD_MD_FILES+1))
  awk '
    /^```bash/     { infence=1; next }
    infence && /^```/ { infence=0; next }
    infence        { print FILENAME ":" FNR ":" $0 }
  ' "$f" 2>/dev/null \
    | grep -v ':[[:space:]]*#' \
    | grep 'grep -c' \
    | ptd_narrow >> "$TMP/ptd-hits.txt"
done <<EOF
$(find "$STAGING" -type f -name '*.md')
EOF

# Count guard against a vacuous scan: a find that matches nothing reports nothing, and a silent
# zero-hit result reads exactly like full coverage (pairs-completeness.test.sh self-test-2 lesson).
{ [ "$PTD_SH_FILES" -ge 20 ] && [ "$PTD_MD_FILES" -ge 10 ]; } \
  && ok "PTD0 (count guard): scan covered $PTD_SH_FILES shell files and $PTD_MD_FILES markdown files" \
  || bad "PTD0 (count guard): scan covered only $PTD_SH_FILES shell / $PTD_MD_FILES markdown files — the loop is vacuous, PTD1 proves nothing"

PTD_HITS=$(grep -c . "$TMP/ptd-hits.txt" 2>/dev/null); PTD_HITS=${PTD_HITS:-0}
if [ "$PTD_HITS" = "0" ]; then
  ok "PTD1: no executable use of grep -c … || echo 0 anywhere under staging/"
else
  bad "PTD1: $PTD_HITS executable use(s) of grep -c … || echo 0 remain under staging/:"
  while IFS= read -r h; do echo "        $h"; done < "$TMP/ptd-hits.txt"
fi

# --- self-checks: PTD1's green is worthless unless the same filter chain still FIRES on a real
# instance (PTD2) and still SUPPRESSES only what it is meant to (PTD3). A guard narrowed by three
# filters can be narrowed into inertness, and an inert guard reports exactly what a clean tree does.
mkdir -p "$TMP/selfcheck"
{ printf '#!/bin/bash\n'
  printf 'n=$(grep -c X f 2>/dev/null || echo 0)\n'                                  # idiom-demo
  printf '# n=$(grep -c X f || echo 0)  <- a comment, must not count\n'              # idiom-demo
  printf 'ok "message: grep -c ... || echo 0 is wrong"  <- a string, must not count\n'
  printf 'w=$(grep -c X f || echo 0)  # idiom-demo declared\n'
} > "$TMP/selfcheck/planted.sh"
PTD_SELF=$(grep -n 'grep -c' "$TMP/selfcheck/planted.sh" | grep -v '^[0-9]*:[[:space:]]*#' | ptd_narrow | grep -c .)
[ "$PTD_SELF" = "1" ] \
  && ok "PTD2 (self-check): the guard flags the one real instance among a comment, a message string and a declared demo" \
  || bad "PTD2 (self-check): guard found $PTD_SELF hit(s) on the 4-line fixture, expected exactly 1"

PTD_SELF3=$(printf 'w=$(grep -c X f || echo 0)  # idiom-demo declared\n' | ptd_narrow | grep -c .)
[ "$PTD_SELF3" = "0" ] \
  && ok "PTD3 (self-check, positive twin of PTD2): the idiom-demo waiver suppresses a real instance" \
  || bad "PTD3 (self-check): the idiom-demo waiver did not suppress ($PTD_SELF3 hit(s)) — filter 3 is dead"

echo
echo "plan-task-count: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
