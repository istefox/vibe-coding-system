#!/bin/bash
# use-codex-review-manifest-field.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash use-codex-review-manifest-field.test.sh
#
# Covers the Codex-vs-Claude review gate's manifest plumbing: schema 1.3 -> 1.4, the new
# `use_codex_review` field (default false, set via manifest-set-flag.sh, same shape as
# `anonymize` at schema 1.2), and manifest-validate.sh's Invariant 24. See the ADR for the
# Codex-vs-Claude review gate.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
CC="$SCRIPTS/../skills/concept-to-code/scripts"
INIT="$CC/manifest-init.sh"
VALIDATE="$CC/manifest-validate.sh"
SETFLAG="$CC/manifest-set-flag.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

valid() { bash "$VALIDATE" "$TMP/$1.yml" >/dev/null 2>&1; }
why()   { bash "$VALIDATE" "$TMP/$1.yml" 2>&1 | grep -i 'codex\|schema_version'; }

# =====================================================================================
# A. manifest-init.sh: the real producer, not a hand-written fixture.
mkdir -p "$TMP/root"
bash "$INIT" "codex-gate-probe" "Codex gate probe" "$TMP/root" >/dev/null 2>&1
INITED="$TMP/root/docs/manifests"/*-codex-gate-probe.manifest.yml

A1_FILE=""
for _f in $INITED; do [ -f "$_f" ] && A1_FILE="$_f"; done
if [ -n "$A1_FILE" ]; then
  ok "A1: manifest-init.sh produced a manifest"
else
  bad "A1: manifest-init.sh did not produce a manifest — the rest of section A cannot run"
fi

if [ -n "$A1_FILE" ] && grep -q '^manifest_schema_version: "1.4"$' "$A1_FILE"; then
  ok "A2: manifest-init.sh writes schema_version 1.4"
else
  bad "A2: schema_version is not 1.4 — $(grep '^manifest_schema_version:' "$A1_FILE" 2>/dev/null)"
fi
# plant: A2 | plugin/skills/concept-to-code/scripts/manifest-init.sh | echo "manifest_schema_version: \"1.4\"" > "$T" | echo "manifest_schema_version: \"1.3\"" > "$T"

if [ -n "$A1_FILE" ] && grep -q '^use_codex_review: false$' "$A1_FILE"; then
  ok "A3: manifest-init.sh seeds use_codex_review: false"
else
  bad "A3: use_codex_review not seeded false — $(grep '^use_codex_review:' "$A1_FILE" 2>/dev/null)"
fi
# plant: A3 | plugin/skills/concept-to-code/scripts/manifest-init.sh | echo "use_codex_review: false" >> "$T" | :

if [ -n "$A1_FILE" ] && bash "$VALIDATE" "$A1_FILE" >/dev/null 2>&1; then
  ok "A4: the freshly-init'd manifest validates"
else
  bad "A4: the freshly-init'd manifest does not validate — $(bash "$VALIDATE" "$A1_FILE" 2>&1)"
fi

# A5: manifest-set-flag.sh — the generic boolean setter already handles this key since it is
# pre-seeded at column 0 (no code change to manifest-set-flag.sh was needed or made).
if [ -n "$A1_FILE" ] && bash "$SETFLAG" "$A1_FILE" use_codex_review true >/dev/null 2>&1 \
   && grep -q '^use_codex_review: true$' "$A1_FILE"; then
  ok "A5: manifest-set-flag.sh flips use_codex_review to true"
else
  bad "A5: manifest-set-flag.sh did not flip use_codex_review — $(grep '^use_codex_review:' "$A1_FILE" 2>/dev/null)"
fi

if [ -n "$A1_FILE" ] && bash "$VALIDATE" "$A1_FILE" >/dev/null 2>&1; then
  ok "A6: the manifest still validates with use_codex_review: true"
else
  bad "A6: flipping the flag broke validation — $(bash "$VALIDATE" "$A1_FILE" 2>&1)"
fi

# =====================================================================================
# B. manifest-validate.sh Invariant 1 (schema version) and Invariant 24 (use_codex_review),
# built from a real, currently-passing manifest so unrelated invariants are not tripped
# (same fixture-construction discipline as manifest-project-root-terminal.test.sh).
BASE=""
for _c in "$A1_FILE"; do [ -f "$_c" ] && BASE="$_c"; done
if [ -z "$BASE" ]; then
  bad "B0: no base fixture available — section B cannot run"
else
  ok "B0: base fixture available for section B"
fi

mk() {
  # mk <name> <schema-version | __KEEP__> <use_codex_review value | __ABSENT__ | __KEEP__>
  cp "$BASE" "$TMP/$1.yml"
  if [ "$2" != "__KEEP__" ]; then
    sed -i.bak "s|^manifest_schema_version: .*|manifest_schema_version: \"$2\"|" "$TMP/$1.yml"
  fi
  case "$3" in
    __KEEP__) ;;
    __ABSENT__) sed -i.bak '/^use_codex_review:/d' "$TMP/$1.yml" ;;
    *) sed -i.bak "s|^use_codex_review: .*|use_codex_review: $3|" "$TMP/$1.yml" ;;
  esac
  rm -f "$TMP/$1.yml.bak"
}

if [ -n "$BASE" ]; then
  mk schema14      "1.4" __KEEP__
  mk schema13      "1.3" __ABSENT__
  mk schema_bad    "1.5" __KEEP__
  mk absent_field  __KEEP__ __ABSENT__
  mk true_field    __KEEP__ true
  mk false_field   __KEEP__ false
  mk bad_field     __KEEP__ maybe

  valid schema14 && ok "B1: schema_version 1.4 is accepted" \
                 || bad "B1: schema 1.4 rejected — $(why schema14)"
  valid schema13 && ok "B2: schema_version 1.3 (no use_codex_review) still accepted — retrocompat" \
                 || bad "B2: schema 1.3 rejected — $(why schema13)"
  if valid schema_bad; then
    bad "B3: schema_version 1.5 (unknown) was accepted — Invariant 1 no longer bounds the range"
  else
    ok "B3: an unknown schema_version (1.5) is rejected"
  fi
# plant: B3 | plugin/skills/concept-to-code/scripts/manifest-validate.sh | if ! grep -Eq '^manifest_schema_version: "(1\.0|1\.1|1\.2|1\.3|1\.4)"$' "$MANIFEST"; then | if false; then

  valid absent_field && ok "B4: use_codex_review absent is valid (retrocompat 1.0-1.3)" \
                      || bad "B4: absent field now fails validation — $(why absent_field)"
  valid true_field && ok "B5: use_codex_review: true is valid" \
                    || bad "B5: 'true' rejected — $(why true_field)"
  valid false_field && ok "B6: use_codex_review: false is valid" \
                     || bad "B6: 'false' rejected — $(why false_field)"
  if valid bad_field; then
    bad "B7: use_codex_review: maybe was accepted — Invariant 24 does not enforce true|false"
  else
    printf '%s' "$(why bad_field)" | grep -qi 'use_codex_review' \
      && ok "B7: an invalid use_codex_review value is rejected, naming the field" \
      || bad "B7: rejected, but not naming use_codex_review — $(why bad_field)"
  fi
# plant: B7 | plugin/skills/concept-to-code/scripts/manifest-validate.sh | if ! grep -Eq '^use_codex_review: (true|false)$' "$MANIFEST"; then | if false; then
else
  bad "B1-B7: skipped — no base fixture"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
_total=$((PASS + FAIL))
if [ "$_total" -ge 13 ]; then
  echo "PASS: Z1: $_total assertions ran (floor: 13)"
  PASS=$((PASS+1))
else
  echo "FAIL: Z1: only $_total assertions ran — expected >= 13; assertions vanished"
  FAIL=$((FAIL+1))
fi
[ "$FAIL" -eq 0 ]
