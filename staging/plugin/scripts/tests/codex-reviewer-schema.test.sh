#!/bin/bash
# codex-reviewer-schema.test.sh — offline, hermetic, no network, no $HOME dependency, no live
# codex call (this repo's own convention: never spend real Codex quota in CI).
# Bash 3.2 clean. Run: bash codex-reviewer-schema.test.sh
#
# Regression lock for a defect the deferred live probe (ADR-0187) actually found: OpenAI's
# structured-output mode (what `codex exec --output-schema` uses under the hood) requires
# "additionalProperties": false on EVERY object in the schema, or the call fails outright with
# `invalid_json_schema` before the model ever runs — confirmed live, 2026-09-02, against a real
# scratch diff. codex-reviewer.sh's two embedded --output-schema blocks (review mode, diagnose
# mode) are extracted here from the real source file and checked structurally, so a future edit
# that drops the constraint again fails fast in CI instead of only at the next live probe.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
CR="$SCRIPTS/codex-reviewer.sh"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

if [ ! -f "$CR" ]; then
  bad "S0: codex-reviewer.sh not found at $CR — nothing else in this file can run"
  echo "----"; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
ok "S0: codex-reviewer.sh found"

extract_schema() {
  # $1 = 1-based ordinal of the SCHEMA_EOF block to extract (1 = review mode, 2 = diagnose mode)
  awk -v n="$1" '
    /<<.SCHEMA_EOF.$/ { count++; if (count==n) { capturing=1; next } }
    capturing && /^SCHEMA_EOF$/ { capturing=0; next }
    capturing { print }
  ' "$CR"
}

check_schema() {
  # $1 = label, $2 = schema text
  local label="$1" schema="$2"
  if [ -z "$schema" ]; then
    bad "$label: schema block not found in codex-reviewer.sh"
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

REVIEW_SCHEMA=$(extract_schema 1)
DIAGNOSE_SCHEMA=$(extract_schema 2)

check_schema "S1 review-mode schema" "$REVIEW_SCHEMA"
check_schema "S2 diagnose-mode schema" "$DIAGNOSE_SCHEMA"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
_total=$((PASS + FAIL))
if [ "$_total" -ge 2 ]; then
  echo "PASS: Z1: $_total assertions ran (floor: 2)"
  PASS=$((PASS+1))
else
  echo "FAIL: Z1: only $_total assertions ran (floor: 2)"
  FAIL=$((FAIL+1))
fi
[ "$FAIL" -eq 0 ]
