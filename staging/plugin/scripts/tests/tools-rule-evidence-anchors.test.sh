#!/bin/bash
# tools-rule-evidence-anchors.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash tools-rule-evidence-anchors.test.sh
#
# VCS-043 / ADR-0176. staging/user/rules/tools.md (loaded every session, no `paths:` key) was
# compressed from 264 to ~152 lines by moving each entry's incident narrative into
# docs/tools-evidence.md (not loaded, looked up via a `→ #anchor` pointer). A pointer specified in
# one file and consumed in another needs something checking they meet (repo rule 17) — nothing
# else in this suite reads either file, so a rewrite of tools.md that drops an anchor, or a rewrite
# of tools-evidence.md that drops or renames a heading, would silently orphan the narrative on one
# side or leave a dead pointer on the other.
#
# Checked in both directions, per repo rule 8 (a check that validates a list's entries is blind to
# what the list omits): TE1 is forward (every anchor in tools.md resolves to a real heading in
# tools-evidence.md); TE2 is backward (every heading in tools-evidence.md has at least one
# referring anchor, so an orphaned narrative block cannot accumulate unnoticed). TE3 guards the
# denominator (repo rule 7): a zero-anchor or zero-heading population must not read as "all
# anchors valid" by vacuous truth, so both counts must be positive and must agree with each other
# — the exact-parity shape CMC05 already established for chain-decision-index.md vs
# chain-decisions.md.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
REPO=$(cd "$STAGING/.." && pwd)
RULES_TOOLS="$STAGING/user/rules/tools.md"
EVIDENCE="$REPO/docs/tools-evidence.md"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# Did-not-run must be distinguishable from a clean result (repo rule 4): a missing input here is a
# defect in the vendoring step (VCS-043 §1/§2), not "zero anchors, all fine".
if [ ! -f "$RULES_TOOLS" ]; then
  printf 'DID NOT RUN: %s missing\n' "$RULES_TOOLS"
  exit 3
fi
if [ ! -f "$EVIDENCE" ]; then
  printf 'DID NOT RUN: %s missing\n' "$EVIDENCE"
  exit 3
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ANCHORS="$TMP/anchors.txt"
HEADINGS="$TMP/headings.txt"
JOINED="$TMP/joined.txt"
# An entry's pointer is a `→ #anchor` chain, and one entry (the tag-quirks block) wraps a
# trailing anchor onto its own continuation line with no `→` of its own — a bare run of
# `#token #token…`. Fold that continuation back onto its parent line first, so a single pass
# below can pull every anchor out of the chain, not just the one immediately after `→`.
awk '
  /^[[:space:]]*#[a-zA-Z0-9-]+([[:space:]]+#[a-zA-Z0-9-]+)*[[:space:]]*$/ && prev != "" {
    prev = prev " " $0
    next
  }
  { if (prev != "") print prev; prev = $0 }
  END { if (prev != "") print prev }
' "$RULES_TOOLS" > "$JOINED"
grep '→ #' "$JOINED" | grep -oE '#[a-zA-Z0-9-]+' | sed 's/^#//' | sort -u > "$ANCHORS"
grep '^## ' "$EVIDENCE" | sed 's/^## //' | sort -u > "$HEADINGS"

# TE3 — denominator guard, rule 7: a zero population on either side must not read as "checked, all
# match" (an empty forward loop and an empty backward loop would both pass vacuously). Exact
# parity, not a floor, because the population is closed: every anchor names exactly one heading
# and vice versa, so the counts must be identical, not merely "big enough" (rule 10 — a floor with
# slack absorbs its own plant; parity does not).
# plant: TE3 | ../docs/tools-evidence.md | ## cd-not-persisted | ### cd-not-persisted
_anchor_n=$(wc -l < "$ANCHORS" | tr -d ' ')
_heading_n=$(wc -l < "$HEADINGS" | tr -d ' ')
if [ "$_anchor_n" -gt 0 ] && [ "$_heading_n" -gt 0 ] && [ "$_anchor_n" -eq "$_heading_n" ]; then
  ok "TE3: anchor/heading population is non-zero and in parity ($_anchor_n anchors, $_heading_n headings)"
else
  bad "TE3: anchor/heading population mismatch (anchors=$_anchor_n headings=$_heading_n) — a zero or drifted count on either side"
fi

# TE1 — forward: every anchor in tools.md resolves to a real heading in tools-evidence.md.
# plant: TE1 | ../docs/tools-evidence.md | ## yt-dlp-transcripts | ## yt-dlp-transcripts-x
_te1_missing=""
while IFS= read -r _a; do
  [ -z "$_a" ] && continue
  grep -qxF "$_a" "$HEADINGS" || _te1_missing="$_te1_missing $_a"
done < "$ANCHORS"
if [ -z "$_te1_missing" ]; then
  ok "TE1: every → #anchor in tools.md resolves to a heading in tools-evidence.md"
else
  bad "TE1: dead anchor(s) in tools.md, no matching heading in tools-evidence.md:$_te1_missing"
fi

# TE2 — backward (rule 8): every heading in tools-evidence.md has at least one referring anchor in
# tools.md, so a heading can't quietly stop being pointed at and pile up as dead narrative.
# plant: TE2 | user/rules/tools.md | → #notarytool-401-apple-id | → #notarytool-401-apple-id-x
_te2_orphaned=""
while IFS= read -r _h; do
  [ -z "$_h" ] && continue
  grep -qxF "$_h" "$ANCHORS" || _te2_orphaned="$_te2_orphaned $_h"
done < "$HEADINGS"
if [ -z "$_te2_orphaned" ]; then
  ok "TE2: every heading in tools-evidence.md has at least one referring anchor in tools.md"
else
  bad "TE2: orphaned heading(s) in tools-evidence.md, no referring anchor in tools.md:$_te2_orphaned"
fi

# Z1 — assertion-count floor (repo rule 10: a floor is a vacuity guard here, not the primary
# check — TE1/TE2/TE3 are exact-shaped; this only catches the whole file failing to run its
# assertions at all).
Z1_FLOOR=3
if [ "$((PASS + FAIL))" -ge "$Z1_FLOOR" ]; then
  ok "Z1: assertion count $((PASS + FAIL)) >= floor $Z1_FLOOR"
else
  bad "Z1: assertion count $((PASS + FAIL)) < floor $Z1_FLOOR — assertions vanished"
fi

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
