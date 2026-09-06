#!/bin/bash
# macos-detect.test.sh — offline, hermetic, no network, no $HOME dependency. Bash 3.2 clean.
# Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash macos-detect.test.sh
#
# Issue #232 / ADR-0093. `detect-macos.sh` gates Gate 1c, which offers a HIG design step for
# window types, navigation, Settings and menu bar. Measured over the 36 SPECs in this repository,
# it fired on SIX and NONE of them was a macOS UI target.
#
# TWO FALSE-POSITIVE CLASSES, and the issue named one of them:
#   1. the keyword inside a longer IDENTIFIER — `macos-ux`, and (found by measuring, not reported)
#      `swiftui-pro`. Both are skill names, so every meta-SPEC about this chain tripped the gate.
#      The second survives the narrowing #232 itself proposed.
#   2. the keyword naming the HOST, not the target — `Bash 3.2 (macOS-portable, …)` says which
#      shell, not which UI.
#
# WHY THIS FILE EXISTS AT ALL. Four detect-macos assertions already lived in
# `concept-to-code/tests/run-tests.sh`, which resolves `SKILL_DIR="$HOME/.claude/skills/…"` — the
# DEPLOYED copy. It is $HOME-coupled and CI-dark, the fourth instance of the class ADR-0032 named
# by name. Those four are re-homed here (section P) so they run in CI for the first time; the
# original file is byte-untouched, exactly as ADR-0032 handled the same situation.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
DET="$STAGING/plugin/skills/concept-to-code/scripts/detect-macos.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# run_det <text> — write the text to a throwaway SPEC and return the verdict, or the raw output
# when the script errored. An error must never read as NOT_MACOS: see M20.
DET_N=0
run_det() {
  DET_N=$((DET_N + 1))
  printf '%s\n' "$1" >"$TMP/spec_$DET_N.md"
  bash "$DET" "$TMP/spec_$DET_N.md" 2>&1
}

expect() {  # expect <want> <label> <text>
  _got=$(run_det "$3")
  if [ "$_got" = "$1" ]; then ok "$2"
  else bad "$2 — want=$1 got=[$_got]"; fi
}

# ==================================================================================================
# M0. Anchor.
# ==================================================================================================
if [ -f "$DET" ] && [ -r "$DET" ]; then
  ok "M0: detect-macos.sh exists and is readable"
else
  bad "M0: $DET not found — every assertion below is meaningless"
fi

# ==================================================================================================
# M1-M6. The TRUE-POSITIVE side. This repository contains no genuine macOS-app SPEC, so the corpus
# cannot supply it: without these, a rule that detects nothing at all would score perfectly on
# section M10 below. Both directions, per ADR-0039.
# ==================================================================================================
expect MACOS_DETECTED "M1: a SwiftUI stack line is a macOS UI target" \
  'Swift 6, SwiftUI, SwiftData. Target macOS 26.'
expect MACOS_DETECTED "M2: a menu bar utility is a macOS UI target" \
  'A macOS menu bar utility that shows the current build status.'
expect MACOS_DETECTED "M3: 'macOS app ... window, toolbar' is a macOS UI target" \
  'A macOS app for tracking invoices. Single window, standard toolbar.'
expect MACOS_DETECTED "M4: 'a small macOS utility' with NO framework named is still detected" \
  'A small macOS utility that syncs two folders on a schedule.'
expect MACOS_DETECTED "M5: an AppKit/NSWindow/HIG section is a macOS UI target" \
  'AppKit, NSWindow, a Settings scene and a HIG-compliant menu.'
# The UI noun BEFORE the platform name. The first draft of this fix missed it: the identifier
# boundary (which treats `-` as part of a word, correctly, for `macos-ux`) also swallowed
# `window-based`. The noun and the keyword therefore use DIFFERENT boundary sets.
expect MACOS_DETECTED "M6: a UI noun BEFORE the platform name still counts ('window-based macOS tool')" \
  'A window-based macOS tool for reviewing diffs.'

# ==================================================================================================
# M7. The deliberate non-detection. A headless daemon has no window, navigation or menu, so Gate
# 1c has nothing to offer it. This is the cost of the proximity rule, stated as an assertion
# rather than left to be discovered as a bug report.
# ==================================================================================================
expect NOT_MACOS "M7 (deliberate cost): a headless 'macOS daemon' is NOT detected — Gate 1c offers window/menu design a daemon cannot use" \
  'A macOS daemon that watches a directory and writes a log.'

# ==================================================================================================
# M8-M11. The FALSE-POSITIVE side. M8 and M11 are real corpus lines, reproduced verbatim.
# ==================================================================================================
expect NOT_MACOS "M8 (class 2, real corpus line): 'Bash 3.2 (macOS-portable, …)' names the host, not a UI target" \
  'Bash 3.2 (macOS-portable, no assoc arrays), consistent with every other script.'
expect NOT_MACOS "M9 (class 1): a list of skill names containing macos-ux and swiftui-pro is not a UI target" \
  'Vendor the skills: concept-to-code, macos-ux, swiftui-pro, find-skills.'
expect NOT_MACOS "M10 (class 1, the one #232 did NOT report): swiftui-pro alone in prose is not a UI target" \
  'The swiftui-pro skill is SKILL.md only, not the full directory.'
expect NOT_MACOS "M11 (class 2, real corpus line): 'Bash 3.2 (macOS /bin/bash)' names the shell's host" \
  'Bash 3.2 (macOS /bin/bash), markdown, GitHub Actions.'

# ==================================================================================================
# M12. Missing file — unchanged contract.
# ==================================================================================================
M12_OUT=$(bash "$DET" "$TMP/does-not-exist.md" 2>&1); M12_RC=$?
if [ "$M12_OUT" = "NOT_MACOS" ] && [ "$M12_RC" -eq 0 ]; then
  ok "M12: a missing SPEC yields NOT_MACOS and exit 0"
else
  bad "M12: missing SPEC gave out=[$M12_OUT] rc=$M12_RC"
fi

# ==================================================================================================
# P. The four assertions re-homed from the $HOME-coupled, CI-dark skill-private harness. Parity
# with the pre-#232 behaviour is the point: this change must not have moved them.
# ==================================================================================================
expect NOT_MACOS "P1 (parity, pre-existing): SwiftUI only in a table row and a backtick span -> NOT_MACOS" \
  '| Stack | Swift 6, SwiftUI |'
P2_SPEC="$TMP/p2.md"
printf 'Prose here.\n```swift\nimport SwiftUI\nlet w = NSWindow()\n```\nMore prose.\n' >"$P2_SPEC"
if [ "$(bash "$DET" "$P2_SPEC" 2>&1)" = "NOT_MACOS" ]; then
  ok "P2 (parity, pre-existing): keywords inside a fenced code block -> NOT_MACOS"
else
  bad "P2: a fenced code block leaked its keywords into the scan"
fi
expect MACOS_DETECTED "P3 (parity, pre-existing): prose 'macOS menu bar app' -> MACOS_DETECTED" \
  'A macOS menu bar app for tracking time.'
expect NOT_MACOS "P4 (parity, pre-existing): a backtick span alone does not trigger detection" \
  'See the `SwiftUI` docs for details.'

# ==================================================================================================
# M20. THE CORPUS SWEEP, and it counts THREE outcomes, not two.
#
# An ERROR must never be counted as NOT_MACOS. That is not a hypothetical: while building this fix
# the rule was briefly written with an empty ERE alternative `(…|)`, which BSD grep rejects
# outright — and the corpus sweep then reported ZERO false positives while the rule was not running
# at all. A check that did not run reading as a check that found nothing, in the measurement built
# to verify the fix. M21 pins the construct out of the script directly.
# ==================================================================================================
M20_N=0; M20_HIT=0; M20_ERR=0; M20_HITS=""
for _s in "$REPO"/SPEC.md "$REPO"/docs/specs/*.spec.md; do
  [ -f "$_s" ] || continue
  M20_N=$((M20_N + 1))
  _o=$(bash "$DET" "$_s" 2>&1)
  case "$_o" in
    MACOS_DETECTED) M20_HIT=$((M20_HIT + 1)); M20_HITS="$M20_HITS $(basename "$_s")" ;;
    NOT_MACOS)      : ;;
    *)              M20_ERR=$((M20_ERR + 1)) ;;
  esac
done
if [ "$M20_N" -ge 20 ]; then
  ok "M20a (count guard): the corpus sweep visited $M20_N SPEC(s) — not a vacuous pass"
else
  bad "M20a (count guard): only $M20_N SPEC(s) visited — the glob is broken, not the corpus clean"
fi
if [ "$M20_ERR" -eq 0 ]; then
  ok "M20b: no SPEC produced an error — an unrunnable rule must not be counted as a clean one"
else
  bad "M20b: $M20_ERR SPEC(s) made detect-macos.sh error; every one of them silently reads as NOT_MACOS"
fi
if [ "$M20_HIT" -eq 0 ]; then
  ok "M20c: none of this repository's $M20_N SPECs trips Gate 1c (six did before #232)"
else
  bad "M20c: $M20_HIT SPEC(s) still trip Gate 1c:$M20_HITS"
fi

# M21 — the BSD-grep construct, pinned out of the source. `bash -n` cannot see it: the pattern is a
# string until grep reads it, so the script parses fine and fails only at run time.
#
# COMMENT LINES ARE EXCLUDED, because the script's own header explains why not to use the
# construct — and the first draft of this assertion matched that explanation and failed on a
# correct file. Rule 12: a scan whose needle is a literal counts itself.
if grep -v '^[[:space:]]*#' "$DET" | grep -q '|)' 2>/dev/null; then
  bad "M21: detect-macos.sh contains an empty ERE alternative '(…|)' — BSD grep rejects it and every SPEC then reads as NOT_MACOS"
else
  ok "M21: no empty ERE alternative in detect-macos.sh (BSD grep rejects it, silently in the wrong direction)"
fi

# M22 — both boundary sets must still exist. They are different on purpose (see M6), and collapsing
# them into one looks like a tidy-up.
if grep -q "^WB=" "$DET" && grep -q "^NB=" "$DET" && ! grep -q "^NB=\"\\\$WB\"" "$DET"; then
  ok "M22: the keyword boundary (WB, '-' inside a word) and the noun boundary (NB, '-' a separator) are still distinct"
else
  bad "M22: the two boundary sets have been merged — that re-breaks 'window-based macOS tool' (M6) or re-breaks 'macos-ux' (M9)"
fi

# ==================================================================================================
# M30. Registration in both CI registries (rule 2: a new test needs BOTH).
# ==================================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
if grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1 | grep -qE '[[:space:]]macos-detect[[:space:];]'; then
  ok "M30: docs-ci.yml's explicit shell-tests list runs macos-detect"
else
  bad "M30: macos-detect is not in docs-ci.yml's explicit harness list — a new test needs BOTH registries"
fi
# M31 removed (ADR-0193): ci.yml, the second registry this pinned, was deleted — docs-ci.yml's
# shell-tests list above (M30) is now the only harness runner, and pairs-completeness.test.sh's
# CI3 asserts exactly one workflow executes the suite.

# Z1 — assertion-count floor (ADR-0083 §D3).
Z1_TOTAL=$((PASS + FAIL))
if [ "$Z1_TOTAL" -ge 20 ]; then
  ok "Z1: assertion-count floor met ($Z1_TOTAL executed)"
else
  bad "Z1: only $Z1_TOTAL assertions executed — expected >= 20; assertions have gone missing, not passed"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
