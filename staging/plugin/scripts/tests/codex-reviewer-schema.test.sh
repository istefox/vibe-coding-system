#!/bin/bash
# codex-reviewer-schema.test.sh — offline, hermetic, no network, no $HOME dependency, no live
# codex call (this repo's own convention: never spend real Codex quota in CI).
# Bash 3.2 clean. Run: bash codex-reviewer-schema.test.sh
#
# Regression lock for a defect the deferred live probe (ADR-0187) actually found: OpenAI's
# structured-output mode (what `codex exec --output-schema` uses under the hood) requires
# "additionalProperties": false on EVERY object in the schema, or the call fails outright with
# `invalid_json_schema` before the model ever runs — confirmed live, 2026-09-02, against a real
# scratch diff. codex-reviewer.sh's embedded --output-schema blocks (one per mode: review,
# diagnose, audit) are extracted here from the real source file and checked structurally, so a
# future edit that drops the constraint again fails fast in CI instead of only at the next live
# probe.
#
# Extraction was ordinal until 2026-09-05 (`extract_schema <ordinal>`, review=1, diagnose=2).
# ADR-0193 §D7 records why that changed: a new SCHEMA_EOF block inserted anywhere before an
# existing one silently repoints its ordinal at the wrong schema while the label still names the
# old one, so coverage of the shadowed block quietly disappears with nothing failing. A
# position-dependent extractor rots the same way a line-number cross-reference does (rule 12) —
# it rots silently, and fastest in a file being actively extended. This file now enumerates every
# SCHEMA_EOF block instead (S1, S2, S3, ...) and asserts the block count exactly, so the next mode
# added cannot silently uncover an existing one.
#
# S4 (ADR-0194, Task 1) extends this same walk to codex-tester.sh's own --output-schema block —
# the same invalid_json_schema trap, this time for the write-sandboxed tester script.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
CR="$SCRIPTS/codex-reviewer.sh"
CT="$SCRIPTS/codex-tester.sh"
CC="$SCRIPTS/codex-coder.sh"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

if [ ! -f "$CR" ]; then
  bad "S0: codex-reviewer.sh not found at $CR — nothing else in this file can run"
  echo "----"; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
ok "S0: codex-reviewer.sh found"

extract_schema() {
  # $1 = file to extract from, $2 = 1-based ordinal of the SCHEMA_EOF block to extract, counted
  # by position in the file. Used generically below to walk every block in turn (S1, S2, S3, ...)
  # — never to pin a specific ordinal to a specific mode. Pinning an ordinal to a mode name is
  # exactly the defect ADR-0193 §D7 repairs here: see the comment below for what stood at this
  # call site before. The file parameter (ADR-0194) lets the same walk cover codex-tester.sh's
  # own block without a second copy of this function.
  awk -v n="$2" '
    /<<.SCHEMA_EOF.$/ { count++; if (count==n) { capturing=1; next } }
    capturing && /^SCHEMA_EOF$/ { capturing=0; next }
    capturing { print }
  ' "$1"
}

check_schema() {
  # $1 = label, $2 = schema text, $3 = source file (used only in the not-found message)
  local label="$1" schema="$2" src="${3:-$CR}"
  if [ -z "$schema" ]; then
    bad "$label: schema block not found in $src"
    return
  fi
  local verdict
  verdict=$(SCHEMA_JSON="$schema" python3 -c '
import json, os, sys

s = os.environ["SCHEMA_JSON"]
try:
    doc = json.loads(s)
except Exception as e:
    print("PARSE-ERROR: %s" % e)
    sys.exit(0)

missing = []

def walk(node, path):
    if isinstance(node, dict):
        if node.get("type") == "object" or "properties" in node:
            if node.get("additionalProperties", None) is not False:
                missing.append(path or "<root>")
        for k, v in node.get("properties", {}).items():
            walk(v, (path + "." if path else "") + k)
        if "items" in node:
            walk(node["items"], (path + "[]" if path else "[]"))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, "%s[%d]" % (path, i))

walk(doc, "")

if missing:
    print("MISSING: " + ", ".join(missing))
else:
    print("OK")
')
  case "$verdict" in
    OK) ok "$label: valid JSON, additionalProperties:false on every object" ;;
    PARSE-ERROR:*) bad "$label: not valid JSON — $verdict" ;;
    MISSING:*) bad "$label: additionalProperties:false missing at — ${verdict#MISSING: }" ;;
    *) bad "$label: unexpected checker output — $verdict" ;;
  esac
}

# Before 2026-09-05 this file called `extract_schema 1` / `extract_schema 2` here, labelling the
# results "review-mode schema" / "diagnose-mode schema" by fixed ordinal. ADR-0193 §D7 records why
# that was removed: a third SCHEMA_EOF block (audit mode) landed and, depending on where in the
# file it was inserted, would either shift under an existing ordinal (silently checking the wrong
# schema under an unchanged, now-wrong label) or simply go unchecked. Ordinal selection is gone;
# every block found in codex-reviewer.sh is enumerated and checked below instead.
BLOCK_COUNT=$(grep -c '<<.SCHEMA_EOF.$' "$CR")

_n=1
while [ "$_n" -le "$BLOCK_COUNT" ]; do
  SCHEMA=$(extract_schema "$CR" "$_n")
  check_schema "S$_n schema block $_n of $BLOCK_COUNT" "$SCHEMA" "$CR"
  _n=$((_n + 1))
done

# SC1: the block count itself is pinned to exactly 3 — one per mode (review, diagnose, audit).
# Deliberate exact equality, not a ">= 3" floor: a floor absorbs its own plant (rule 10 /
# ADR-0124) and would not notice a block silently disappearing as long as 3 others remained.
# Adding a fourth mode's SCHEMA_EOF block means bumping this literal "3" to "4" on purpose, in the
# same commit that adds the mode — it is not meant to pass unattended.
if [ "$BLOCK_COUNT" -eq 3 ]; then
  ok "SC1: SCHEMA_EOF block count is exactly 3 (one per mode: review, diagnose, audit)"
else
  bad "SC1: SCHEMA_EOF block count is $BLOCK_COUNT, expected exactly 3 (bump this check on purpose if a mode was added or removed)"
fi

# S_T (ADR-0194, Task 1) — codex-tester.sh's own --output-schema block, a separate script from
# codex-reviewer.sh (rule 6: reviewer is read-only by construction, tester writes files, so they
# stay two scripts, not one mode flag) with its own single SCHEMA_EOF block.
if [ ! -f "$CT" ]; then
  bad "S_T: codex-tester.sh not found at $CT"
else
  TESTER_SCHEMA=$(extract_schema "$CT" 1)
  check_schema "S_T tester schema" "$TESTER_SCHEMA" "$CT"
fi
# plant: S_T | plugin/scripts/codex-tester.sh | "additionalProperties": false } SCHEMA_EOF | "additionalProperties": true } SCHEMA_EOF

# S_C (ADR-0196, Task 1) — codex-coder.sh's own output schema is walked by the same
# parameterised extractor and structural checker as the reviewer and tester schemas.
if [ ! -f "$CC" ]; then
  bad "S_C: codex-coder.sh not found at $CC"
else
  CODER_SCHEMA=$(extract_schema "$CC" 1)
  check_schema "S_C coder schema" "$CODER_SCHEMA" "$CC"
fi
# plant: S_C | plugin/scripts/codex-coder.sh | "additionalProperties": false } SCHEMA_EOF | "additionalProperties": true } SCHEMA_EOF

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
_total=$((PASS + FAIL))
if [ "$_total" -ge 7 ]; then
  echo "PASS: Z1: $_total assertions ran (floor: 7)"
  PASS=$((PASS+1))
else
  echo "FAIL: Z1: only $_total assertions ran (floor: 7)"
  FAIL=$((FAIL+1))
fi
[ "$FAIL" -eq 0 ]
