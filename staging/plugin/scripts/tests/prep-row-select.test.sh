#!/bin/bash
# prep-row-select.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash prep-row-select.test.sh
#
# Issue #399, ADR-0134. `autopilot` Phase P step 3 decided which features need a generated SPEC by
# reading one thing — whether `docs/specs/<slug>.spec.md` exists — so a completed feature whose SPEC
# was never archived was indistinguishable from a pending one, and a run bounded to `--only`/
# `--features` still paid design cost across the whole map. This file pins the contract of
# `prep-row-select.sh`, the selector helper that reads the two facts Phase P already has access to:
# the row's state in PROJECT.md, and the run scope.
#
# THIS FILE GROWS ACROSS TASKS 2, 4 AND 6 OF THE IMPLEMENTATION PLAN. Task 2 wrote PRS01 (a forward
# guard once Task 3 lands) and PRS02-PRS19 (RED until Task 3 creates the helper), plus the PRS99
# floor; Task 3 (a separate batch, IMPL only) turned PRS01-PRS19 GREEN with no change to this file.
# Task 4 wrote PRS20/PRS20b/PRS21/PRS21b/PRS21c/PRS21d, the fence-contract assertions for Phase P
# step 3's own fence (`autopilot-prep-row-select`), plus the PRS99 floor raised again; Task 5 (a
# separate batch, IMPL only) turned the PRS20-series GREEN with no change to this file.
# THIS BATCH IS TASK 6's TESTER SUB-STEP PLUS TASK 7: PRS22 (the PAIRS-entry pin for
# `prep-row-select.sh` in `sync-to-claude.sh`, matched on the FULL src|dst pair, never the filename
# alone — pairs-completeness.test.sh is structurally blind to a skill-private scripts/ file,
# ADR-0043) is RED until the coder's next batch adds that PAIRS entry; the tester does not add it
# here, since staging/sync-to-claude.sh is not a test file. PRS99's floor is raised again in the
# same edit. Task 7 adds five `# plant:` declarations (PRS02, PRS07, PRS10, PRS15, PRS20) beside the
# assertions they prove, at column 1 — see plant-check.sh for the mechanism and PC4 for why column 1
# is not cosmetic.
#
# MANDATORY MECHANICS (ADR-0134 §D12; the two rules Task 2 itself names, plus two Task 4 adds):
#   1. bad() prints "FAIL: <id>" — WITH THE COLON. `plant-check.sh` attributes a fired plant with
#      `grep -q "^FAIL: $aid"`. `prep.test.sh:11` prints `FAIL <label>` with no colon, which makes
#      every plant declared there unattributable (fact 10) — the counter-example this file must not
#      repeat (R-08).
#   2. Assertion ids are FIXED WIDTH: PRS01..PRS19, PRS20+ (this batch), floor PRS99. Attribution
#      above is a PREFIX match, so a variable-width id like PRS1 would be satisfied by PRS10
#      failing. No id in this file is a prefix of another EXCEPT PRS20/PRS20b, and that pair is
#      safe in practice: Task 7's only PRS20-series plant is an exit-code-only mutation on
#      `autopilot-prep-row-select`'s DID-NOT-RUN branch, which does not touch the echoed text
#      PRS20b's own check reads — verified by inspection of the plant's needle/replacement, not
#      assumed. No plant is declared for PRS21/PRS21b/PRS21c/PRS21d in Task 7, so their shared
#      "PRS21" prefix has no attribution to collide with. Flagged rather than silently renamed: the
#      exact ids PRS20/PRS20b/PRS21/PRS21b/PRS21c/PRS21d are named verbatim in the implementation
#      plan's Task 4.
#   3. Every inline fence invocation in the PRS20-series section below binds CLAUDE_PLUGIN_ROOT. An
#      unbound CLAUDE_PLUGIN_ROOT falls through to $HOME/.claude and can make an assertion pass
#      from the DEPLOYED copy while testing nothing — the exact defect found in this session's own
#      RJ14 (ADR-0132).
#   4. PRS20b matches a whitespace-flattened, decoration-stripped copy of the fence's output. A
#      prose assertion must not depend on where a line wraps, on backticks, on bold markers, or on
#      capitalisation (ADR-0073/0076/0080/0098, seven recorded instances of the same family).
#
# FIXTURES. Every fixture below writes its OWN PROJECT.md and docs/specs/_issue-map.tsv under a
# scratch root; nothing reads this repository's real ones except PRS19, which is explicit about it
# (the one case ADR-0134 §D3/Correction 2 needs live data — the #365/#366 heading collision — to be
# a meaningful regression guard rather than a fixture reproduction of a claim).
#
# mk_root <name> is copied from autopilot-run-scope.test.sh's shape: NOT a counter incremented
# inside $(...), which runs in a SUBSHELL so every call returns the same directory and fixtures
# accumulate into each other (ADR-0096's bug, met again in ADR-0110, ADR-0124 and ADR-0129). Each
# caller here passes its own name instead, so the bug class has no surface to reappear on.
#
# ROW-SHAPE, from ADR-0134 §D3, reproduced so fixtures match production exactly:
#   PROJECT.md pending row  : "- [ ] <title>  (issue #<num>)"           (roadmap-from-issues.sh:103)
#   PROJECT.md skipped row  : "- [~] <title>  (issue #<num>)  (skipped)" (mark-roadmap-skipped.sh)
#   map row                 : "<slug>\t<num>\t<title>"                   (roadmap-from-issues.sh)
# Two spaces before "(issue #N)"; the skipped form appends "  (skipped)" after that, since
# mark-roadmap-skipped.sh's <feature-title> argument is the roadmap line's text INCLUDING the issue
# marker, not the title alone.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
REPO=$(cd "$STAGING/.." && pwd)

HELPER="$SKILLS/autopilot/scripts/prep-row-select.sh"
NA="$SKILLS/autopilot/SKILL.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# mk_root <name> — a scratch project root. NOT a counter incremented inside $(...) (see header).
mk_root() {
  _r="$TMPROOT/$1"
  mkdir -p "$_r/docs/specs"
  printf '%s' "$_r"
}

# run_helper <arg>... — invoke prep-row-select.sh directly with whatever arguments the caller
# passes (no implicit --root injection, so PRS17's no-root case can call it bare). Captures stdout
# to HOUT, stderr to HERR, exit code to HRC; the underlying files persist at $TMPROOT/hout and
# $TMPROOT/herr so a caller needing per-line inspection (PRS18) can read them directly instead of
# re-splitting an already newline-joined variable.
run_helper() {
  bash "$HELPER" "$@" >"$TMPROOT/hout" 2>"$TMPROOT/herr"
  HRC=$?
  HOUT=$(cat "$TMPROOT/hout")
  HERR=$(cat "$TMPROOT/herr")
}

# =====================================================================================
# EXIST. PRS01 is a FORWARD GUARD once Task 3 lands (a basic existence/parseability check, not
# behavioural RED evidence) — RED now because the helper does not exist yet.

if [ -f "$HELPER" ] && bash -n "$HELPER" 2>/dev/null; then
  ok "PRS01: prep-row-select.sh exists and is bash-3.2 parseable (forward guard once Task 3 lands)"
else
  bad "PRS01: prep-row-select.sh is missing or fails bash -n (forward guard once Task 3 lands)"
fi

# =====================================================================================
# R1. A completed ([x]) or permanently-skipped ([~]) row is never selected, even with no SPEC on
# disk (ADR-0134 §D3/§D4, R-01). PRS02 carries a plant in Task 7.

R=$(mk_root prs02)
printf '%s\t%s\t%s\n' "prs02-alpha" "5001" "Alpha widget" > "$R/docs/specs/_issue-map.tsv"
printf -- '- [x] Alpha widget  (issue #5001)\n' > "$R/PROJECT.md"
run_helper --root "$R"
if [ "$HRC" = "0" ] && [ -z "$HOUT" ]; then
  ok "PRS02: a [x] row whose SPEC is absent is not selected (R-01, carries a plant in Task 7)"
else
  bad "PRS02: rc=$HRC out=[$HOUT]"
fi
# plant: PRS02 | plugin/skills/autopilot/scripts/prep-row-select.sh | x|X) _verdict=completed ;; | x|X) _verdict=pending ;;

R=$(mk_root prs03)
printf '%s\t%s\t%s\n' "prs03-beta" "5002" "Beta widget" > "$R/docs/specs/_issue-map.tsv"
printf -- '- [~] Beta widget  (issue #5002)  (skipped)\n' > "$R/PROJECT.md"
run_helper --root "$R"
if [ "$HRC" = "0" ] && [ -z "$HOUT" ]; then
  ok "PRS03: a [~] ... (skipped) row whose SPEC is absent is not selected — mark-roadmap-skipped.sh's real output shape, marker intact (R-01)"
else
  bad "PRS03: rc=$HRC out=[$HOUT]"
fi

# =====================================================================================
# R3. A pending ([ ]) row is selected exactly when its SPEC is absent — today's coverage rule,
# narrowed by state rather than replaced (ADR-0134 §D4, R-03).

R=$(mk_root prs04)
printf '%s\t%s\t%s\n' "prs04-gamma" "5003" "Gamma widget" > "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] Gamma widget  (issue #5003)\n' > "$R/PROJECT.md"
run_helper --root "$R"
EXP=$(printf 'prs04-gamma\t5003\tGamma widget')
if [ "$HRC" = "0" ] && [ "$HOUT" = "$EXP" ]; then
  ok "PRS04: a [ ] row whose SPEC is absent is selected, full slug<TAB>num<TAB>title row on stdout (R-03)"
else
  bad "PRS04: rc=$HRC out=[$HOUT]"
fi

R=$(mk_root prs05)
printf '%s\t%s\t%s\n' "prs05-delta" "5004" "Delta widget" > "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] Delta widget  (issue #5004)\n' > "$R/PROJECT.md"
: > "$R/docs/specs/prs05-delta.spec.md"
run_helper --root "$R"
if [ "$HRC" = "0" ] && [ -z "$HOUT" ]; then
  ok "PRS05: a [ ] row whose SPEC exists is not selected (coverage rule unchanged)"
else
  bad "PRS05: rc=$HRC out=[$HOUT]"
fi

# PRS06: the auto-design shape — step 2 has just generated the roadmap, every row is [ ], no SPEC
# exists yet. Must hold with no special case in the helper (ADR-0134 §Context, R-03).
R=$(mk_root prs06)
printf '%s\t%s\t%s\n' "prs06-a" "7001" "Feature A" > "$R/docs/specs/_issue-map.tsv"
printf '%s\t%s\t%s\n' "prs06-b" "7002" "Feature B" >> "$R/docs/specs/_issue-map.tsv"
printf '%s\t%s\t%s\n' "prs06-c" "7003" "Feature C" >> "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] Feature A  (issue #7001)\n- [ ] Feature B  (issue #7002)\n- [ ] Feature C  (issue #7003)\n' > "$R/PROJECT.md"
run_helper --root "$R"
EXP=$(printf 'prs06-a\t7001\tFeature A\nprs06-b\t7002\tFeature B\nprs06-c\t7003\tFeature C')
if [ "$HRC" = "0" ] && [ "$HOUT" = "$EXP" ]; then
  ok "PRS06: a freshly-generated shape (every row [ ], no SPECs, 3 rows) selects all three (R-03)"
else
  bad "PRS06: rc=$HRC out=[$HOUT]"
fi

# =====================================================================================
# R2. --only bounds selection when present (ADR-0134 §D6, R-02).

# PRS07: --only 42 on a two-row fixture selects only the #42 row. Carries a plant in Task 7.
R=$(mk_root prs07)
printf '%s\t%s\t%s\n' "prs07-alpha" "42" "Alpha feature" > "$R/docs/specs/_issue-map.tsv"
printf '%s\t%s\t%s\n' "prs07-beta" "43" "Beta feature" >> "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] Alpha feature  (issue #42)\n- [ ] Beta feature  (issue #43)\n' > "$R/PROJECT.md"
run_helper --root "$R" --only 42
EXP=$(printf 'prs07-alpha\t42\tAlpha feature')
if [ "$HRC" = "0" ] && [ "$HOUT" = "$EXP" ]; then
  ok "PRS07: --only 42 on a two-row fixture selects only the #42 row (R-02, carries a plant in Task 7)"
else
  bad "PRS07: rc=$HRC out=[$HOUT]"
fi
# plant: PRS07 | plugin/skills/autopilot/scripts/prep-row-select.sh | if [ "$_tok" = "$num" ] || [ "$_tok" = "$slug" ]; then _in_scope=1; fi | _in_scope=1

# PRS08: --only <exact map slug> selects that row. The slug is deliberately NOT what slugify(title)
# would produce, so a helper that re-derives a slug from the title instead of reading the map's own
# slug field would fail to match (ADR-0134 §D6: "never re-derive a slug from a title").
R=$(mk_root prs08)
SLUG08="not-the-slugified-title-at-all"
TITLE08="A title that would slugify very differently indeed"
printf '%s\t%s\t%s\n' "$SLUG08" "5551" "$TITLE08" > "$R/docs/specs/_issue-map.tsv"
printf '%s\t%s\t%s\n' "prs08-other" "5552" "Other feature" >> "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] %s  (issue #5551)\n- [ ] Other feature  (issue #5552)\n' "$TITLE08" > "$R/PROJECT.md"
run_helper --root "$R" --only "$SLUG08"
EXP=$(printf '%s\t5551\t%s' "$SLUG08" "$TITLE08")
if [ "$HRC" = "0" ] && [ "$HOUT" = "$EXP" ]; then
  ok "PRS08: --only <exact map slug> selects that row, matched against the map's own slug field, never re-derived (R-02)"
else
  bad "PRS08: rc=$HRC out=[$HOUT]"
fi

# PRS09: --only 9999 (matching no map row) -> exit 0, never an abort, stderr names the token as
# UNRESOLVED-TOKEN — the exact literal ADR-0134 §D4/D6 name for this case — and the selection the
# real (resolving) --only semantics would produce is unaffected: since 9999 matches nothing, the
# fixture's own row is excluded exactly as ordinary --only filtering dictates, not because of a
# crash or an abort (ADR-0134 §D6).
R=$(mk_root prs09)
printf '%s\t%s\t%s\n' "prs09-solo" "50" "Solo feature" > "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] Solo feature  (issue #50)\n' > "$R/PROJECT.md"
run_helper --root "$R" --only 9999
if [ "$HRC" = "0" ] && [ -z "$HOUT" ] \
   && printf '%s' "$HERR" | grep -q "UNRESOLVED-TOKEN" \
   && printf '%s' "$HERR" | grep -q "9999"; then
  ok "PRS09: --only 9999 matching no map row -> exit 0, row list unaffected, stderr reports UNRESOLVED-TOKEN naming the token, never an abort (R-02, ADR-0134 §D6)"
else
  bad "PRS09: rc=$HRC out=[$HOUT] err=$(printf '%s' "$HERR" | head -1)"
fi

# =====================================================================================
# R5. Fail-open on a broken row-to-state link: an orphan issue number or an unrecognised marker is
# SELECTED and reported, never silently dropped (ADR-0134 §D3/§D4, R-05).

# PRS10: a map row whose issue number appears in no PROJECT.md line is selected anyway and reported
# ORPHAN. A second map row (matched normally) keeps the denominator guard from tripping (matched=1,
# not 0). Carries a plant in Task 7.
R=$(mk_root prs10)
printf '%s\t%s\t%s\n' "prs10-orphan" "8001" "Orphan feature" > "$R/docs/specs/_issue-map.tsv"
printf '%s\t%s\t%s\n' "prs10-matched" "8002" "Matched feature" >> "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] Matched feature  (issue #8002)\n' > "$R/PROJECT.md"
run_helper --root "$R"
if [ "$HRC" = "0" ] && printf '%s' "$HOUT" | grep -qF "prs10-orphan" \
   && printf '%s' "$HERR" | grep -q "ORPHAN"; then
  ok "PRS10: a map row whose issue number appears in no PROJECT.md line is selected and stderr reports ORPHAN (R-05, carries a plant in Task 7)"
else
  bad "PRS10: rc=$HRC out=[$HOUT] err=$(printf '%s' "$HERR" | head -1)"
fi
# plant: PRS10 | plugin/skills/autopilot/scripts/prep-row-select.sh | _verdict=orphan | continue

# PRS11: a row-shaped line whose marker is outside ' xX~' (e.g. "- [?]") is selected and reported
# UNRECOGNISED-STATE. This is what keeps ADR-0134 §D3's branch reachable rather than dead — a
# predicate restricted to ' xX~' would send "- [?]" to the ORPHAN branch instead.
R=$(mk_root prs11)
printf '%s\t%s\t%s\n' "prs11-weird" "9001" "Weird feature" > "$R/docs/specs/_issue-map.tsv"
printf -- '- [?] Weird feature  (issue #9001)\n' > "$R/PROJECT.md"
run_helper --root "$R"
if [ "$HRC" = "0" ] && printf '%s' "$HOUT" | grep -qF "prs11-weird" \
   && printf '%s' "$HERR" | grep -q "UNRECOGNISED-STATE"; then
  ok "PRS11: a marker outside ' xX~' (e.g. [?]) is selected and reported UNRECOGNISED-STATE (R-05)"
else
  bad "PRS11: rc=$HRC out=[$HOUT] err=$(printf '%s' "$HERR" | head -1)"
fi

# PRS12: two row-shaped lines for one issue with DIFFERENT markers ([x] then [ ]) -> the first wins
# (not selected) and stderr reports DUPLICATE. Different markers on purpose: identical markers
# cannot distinguish "first wins" from "last wins" (ADR-0134 §D4/edge cases).
R=$(mk_root prs12)
printf '%s\t%s\t%s\n' "prs12-dup" "9101" "Dup feature" > "$R/docs/specs/_issue-map.tsv"
printf -- '- [x] Dup feature  (issue #9101)\n- [ ] Dup feature  (issue #9101)\n' > "$R/PROJECT.md"
run_helper --root "$R"
if [ "$HRC" = "0" ] && [ -z "$HOUT" ] && printf '%s' "$HERR" | grep -q "DUPLICATE"; then
  ok "PRS12: two row-shaped lines for one issue with DIFFERENT markers ([x] then [ ]) -> first wins (not selected), stderr reports DUPLICATE"
else
  bad "PRS12: rc=$HRC out=[$HOUT] err=$(printf '%s' "$HERR" | head -1)"
fi

# =====================================================================================
# R6. The selection DID NOT RUN (exit 3) is distinguishable from "ran and found nothing" (exit 0
# empty) — ADR-0134 §D2/§D4/§D5, R-06. Sub-cases guarded per ADR-0028's caveat (CI may run as root,
# where a chmod 000 file is still readable — the unreadable state cannot be expressed there).

# PRS13: map absent, and map present-but-unreadable -> exit 3, stdout empty.
R=$(mk_root prs13a)
printf -- '- [ ] Whatever  (issue #1)\n' > "$R/PROJECT.md"
run_helper --root "$R"
P13A_OK=0
[ "$HRC" = "3" ] && [ -z "$HOUT" ] && P13A_OK=1

R=$(mk_root prs13b)
printf -- '- [ ] Whatever  (issue #1)\n' > "$R/PROJECT.md"
printf '%s\t%s\t%s\n' "prs13b-x" "1" "Whatever" > "$R/docs/specs/_issue-map.tsv"
chmod 000 "$R/docs/specs/_issue-map.tsv" 2>/dev/null
if [ -r "$R/docs/specs/_issue-map.tsv" ]; then
  P13B_OK=1
  P13B_NOTE=" (unreadable sub-case not expressible for this user — ADR-0028's root caveat — skipped)"
else
  run_helper --root "$R"
  P13B_OK=0
  [ "$HRC" = "3" ] && [ -z "$HOUT" ] && P13B_OK=1
  P13B_NOTE=""
fi

if [ "$P13A_OK" = "1" ] && [ "$P13B_OK" = "1" ]; then
  ok "PRS13: an absent map and an unreadable map both exit 3 with empty stdout$P13B_NOTE (R-06)"
else
  bad "PRS13: absent_ok=$P13A_OK unreadable_ok=$P13B_OK"
fi

# PRS14: PROJECT.md absent, and PROJECT.md present-but-unreadable -> exit 3, stdout empty.
R=$(mk_root prs14a)
printf '%s\t%s\t%s\n' "prs14a-x" "1" "Whatever" > "$R/docs/specs/_issue-map.tsv"
run_helper --root "$R"
P14A_OK=0
[ "$HRC" = "3" ] && [ -z "$HOUT" ] && P14A_OK=1

R=$(mk_root prs14b)
printf '%s\t%s\t%s\n' "prs14b-x" "1" "Whatever" > "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] Whatever  (issue #1)\n' > "$R/PROJECT.md"
chmod 000 "$R/PROJECT.md" 2>/dev/null
if [ -r "$R/PROJECT.md" ]; then
  P14B_OK=1
  P14B_NOTE=" (unreadable sub-case not expressible for this user — ADR-0028's root caveat — skipped)"
else
  run_helper --root "$R"
  P14B_OK=0
  [ "$HRC" = "3" ] && [ -z "$HOUT" ] && P14B_OK=1
  P14B_NOTE=""
fi

if [ "$P14A_OK" = "1" ] && [ "$P14B_OK" = "1" ]; then
  ok "PRS14: an absent PROJECT.md and an unreadable PROJECT.md both exit 3 with empty stdout$P14B_NOTE (R-06)"
else
  bad "PRS14: absent_ok=$P14A_OK unreadable_ok=$P14B_OK"
fi

# PRS15: non-empty map, PROJECT.md carrying no row-shaped line at all -> exit 3, NOT exit 0 with
# empty stdout, and stderr names the predicate (the denominator guard, ADR-0134 §D5). Carries a
# plant in Task 7.
R=$(mk_root prs15)
printf '%s\t%s\t%s\n' "prs15-x" "1" "X feature" > "$R/docs/specs/_issue-map.tsv"
printf 'Just some prose, no checklist rows here.\n' > "$R/PROJECT.md"
run_helper --root "$R"
if [ "$HRC" = "3" ] && [ -z "$HOUT" ] && printf '%s' "$HERR" | grep -qi "predicate"; then
  ok "PRS15: non-empty map, PROJECT.md with no row-shaped line at all -> exit 3 (not 0 with empty stdout), stderr names the predicate (R-06, carries a plant in Task 7)"
else
  bad "PRS15: rc=$HRC out=[$HOUT] err=$(printf '%s' "$HERR" | head -1)"
fi
# plant: PRS15 | plugin/skills/autopilot/scripts/prep-row-select.sh | if [ "$MATCHED" -eq 0 ]; then | if false; then

# PRS16 (positive twin of PRS15): an EMPTY map -> exit 0, empty stdout, guard not applied. Without
# this, a helper that always exits 3 would satisfy PRS15. PROJECT.md is deliberately ABSENT here —
# the algorithm reads the map first and, if empty, short-circuits before reading PROJECT.md at all
# (ADR-0134 §D2/Task 3 step order); a helper that reads PROJECT.md before checking map emptiness
# would wrongly exit 3 here instead of 0.
R=$(mk_root prs16)
: > "$R/docs/specs/_issue-map.tsv"
run_helper --root "$R"
if [ "$HRC" = "0" ] && [ -z "$HOUT" ]; then
  ok "PRS16: an empty map -> exit 0, empty stdout, guard not applied — the positive twin of PRS15"
else
  bad "PRS16: rc=$HRC out=[$HOUT]"
fi

# =====================================================================================
# INVOCATION. Bad invocation is exit 2, distinct from exit 3 (ADR-0134 §D2).

# PRS17: no --root at all, and an unknown flag -> both exit 2.
bash "$HELPER" >"$TMPROOT/hout17a" 2>"$TMPROOT/herr17a"; RC17A=$?
R=$(mk_root prs17)
bash "$HELPER" --root "$R" --bogus-flag >"$TMPROOT/hout17b" 2>"$TMPROOT/herr17b"; RC17B=$?
if [ "$RC17A" = "2" ] && [ "$RC17B" = "2" ]; then
  ok "PRS17: no --root, and an unknown flag, both exit 2, distinct from exit 3"
else
  bad "PRS17: no-root rc=$RC17A unknown-flag rc=$RC17B"
fi

# =====================================================================================
# CHANNEL. Stdout carries rows and NOTHING else; every note and the summary go to stderr
# (ADR-0134 §D2, channel separation is contract not convention).

# PRS18: a fixture that triggers ORPHAN and also selects a normal pending row. Every stdout line
# must have exactly two tab characters (three fields) and stdout must carry no note text; every
# note (ORPHAN, the PREP-SELECT summary, etc.) must be on stderr instead.
R=$(mk_root prs18)
printf '%s\t%s\t%s\n' "prs18-orphan" "9301" "Orphan row" > "$R/docs/specs/_issue-map.tsv"
printf '%s\t%s\t%s\n' "prs18-pending" "9302" "Pending row" >> "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] Pending row  (issue #9302)\n' > "$R/PROJECT.md"
run_helper --root "$R"
LINES_OK=1
SAW_LINE=0
while IFS= read -r _line; do
  [ -z "$_line" ] && continue
  SAW_LINE=1
  _tabs=$(printf '%s' "$_line" | tr -cd '\t' | wc -c | tr -d ' ')
  [ "$_tabs" = "2" ] || LINES_OK=0
done < "$TMPROOT/hout"
NOTES_LEAKED=0
# Anchored on the real note shapes, case-sensitive, never a bare "ORPHAN"/"PREP-SELECT" substring:
# this fixture's own map row is named "prs18-orphan" / "Orphan row" and is correctly selected and
# echoed to stdout, so a case-insensitive substring match fires on the fixture's own data. Do not
# simplify this back to a bare substring match.
printf '%s' "$HOUT" | grep -qE "ORPHAN issue #|PREP-SELECT:" && NOTES_LEAKED=1
if [ "$HRC" = "0" ] && [ "$SAW_LINE" = "1" ] && [ "$LINES_OK" = "1" ] && [ "$NOTES_LEAKED" = "0" ] \
   && printf '%s' "$HERR" | grep -q "ORPHAN"; then
  ok "PRS18: stdout carries only row lines (exactly two tabs each), every note is on stderr (§D2 channel separation)"
else
  bad "PRS18: rc=$HRC saw_line=$SAW_LINE lines_ok=$LINES_OK notes_leaked=$NOTES_LEAKED err=$(printf '%s' "$HERR" | head -1)"
fi

# =====================================================================================
# REAL. PRS19 is the ONE assertion in this file that reads this repository's own real PROJECT.md
# and docs/specs/_issue-map.tsv (see header). It reproduces the live shape Task 1 re-measured:
# PROJECT.md carries both a "- [x] ... (issue #365)" row AND a "#### Wave 1 — bound the run
# (issue #365)" heading. A file-wide match would see two hits and either take the DUPLICATE branch
# or, worse, misclassify the heading (no "[.]" marker at all). The row-shaped predicate must match
# exactly once: the row, never the heading. Assert the DUPLICATE note's ABSENCE as well as the
# verdict — a duplicate-then-first-wins implementation would print the right verdict for the wrong
# reason (ADR-0134 §D3/Correction 2).
run_helper --root "$REPO" --only 365
NOTE_ABSENT=1
# Anchored on the real note prefix, case-sensitive: the PREP-SELECT summary line's own "duplicate=0"
# field label (ADR-0134 §D2) satisfies a case-insensitive bare "DUPLICATE" substring on EVERY run,
# which made this assertion unsatisfiable by construction. Do not simplify this back to a bare
# substring match.
printf '%s' "$HERR" | grep -q "DUPLICATE row-shaped" && NOTE_ABSENT=0
TOKEN_RESOLVED=1
printf '%s' "$HERR" | grep -q "UNRESOLVED-TOKEN" && TOKEN_RESOLVED=0
if [ "$HRC" = "0" ] && [ -z "$HOUT" ] && [ "$NOTE_ABSENT" = "1" ] && [ "$TOKEN_RESOLVED" = "1" ]; then
  ok "PRS19: against this repository's real PROJECT.md/map, the #365 row+heading collision classifies as exactly one match ([x], not selected), no DUPLICATE note (R-01, ADR-0134 §D3)"
else
  bad "PRS19: rc=$HRC out=[$HOUT] note_absent=$NOTE_ABSENT token_resolved=$TOKEN_RESOLVED err=$(printf '%s' "$HERR" | head -3)"
fi

# =====================================================================================
# FENCE MACHINERY (Task 4, ADR-0134 §D9). Copied VERBATIM from autopilot-run-scope.test.sh's
# enumerate_fences / fence_body / extract_fence / subst_paths / run_fence / out_of — a DELIBERATE
# copy, not a shared import (ADR-0086: three private fence_body copies already answer this file's
# own question independently, and each harness must be able to fail independently of the others).
# fence_body's `strip = (lw < ind) ? lw : ind` clause is load-bearing here specifically: the
# `autopilot-prep-row-select` fence sits inside Phase P step 3, a numbered-list item indented like
# `autopilot-optin` above it in this same file (Phase 0 check 3), and its column-0 `FENCE_BASH`
# terminator would extract as `CE_BASH` without that clause (issue #394, ADR-0133) — the assertions
# below would then test a corrupted body and pass or fail for reasons that have nothing to do with
# prep-row-select.sh.

# enumerate_fences <file> — "<opener-line>\t<marker-or-NONE>", indentation-tolerant.
enumerate_fences() {
  awk '
    {
      line = $0
      stripped = line; sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^<!--[[:space:]]*fence-(contract|illustration):/) { pending = stripped; next }
      if (stripped == "") { next }
      if (infence) { if (stripped == "```") { infence = 0 } ; next }
      if (stripped ~ /^```bash[[:space:]]*$/) {
        printf "%d\t%s\n", NR, (pending == "" ? "NONE" : pending)
        pending = ""; infence = 1; next
      }
      pending = ""
    }
  ' "$1"
}

# fence_body <file> <opener-line> — strips AT MOST the opener's own indentation (`ind`), never more
# than a given line's OWN leading whitespace (`lw`) — see the header note above.
fence_body() {
  awk -v want="$2" '
    NR == want { match($0, /^[[:space:]]*/); ind = RLENGTH; infence = 1; next }
    infence {
      s = $0; sub(/^[[:space:]]+/, "", s)
      if (s == "```") { exit }
      match($0, /^[[:space:]]*/); lw = RLENGTH
      strip = (lw < ind) ? lw : ind
      print substr($0, strip + 1)
    }
  ' "$1"
}

# extract_fence <file> <id> — anchored on the MARKER, never a heading (ADR-0083 §D3).
extract_fence() {
  _ln=$(enumerate_fences "$1" | grep -F "fence-contract: ${2} -->" | head -1 | cut -f1)
  [ -n "$_ln" ] || return 1
  fence_body "$1" "$_ln"
}

# The substitution contract: a SKILL.md names the DEPLOYED path; this harness exercises staging/.
subst_paths() { sed -e "s|\$HOME/.claude/skills/|$SKILLS/|g" -e "s|~/.claude/skills/|$SKILLS/|g"; }

# run_fence <contract-id> <skill-md> <setup-script> — extract, substitute, prepend the setup that
# binds the fence's free variables, execute, print the exit code.
run_fence() {
  _id="$1"; _f="$2"; _setup="$3"
  _body=$(extract_fence "$_f" "$_id") || { echo "EXTRACT_FAILED"; return; }
  if [ -z "$_body" ]; then echo "EXTRACT_EMPTY"; return; fi
  _s="$TMPROOT/run-$_id.sh"
  { cat "$_setup"; printf '\n'; } >"$_s"
  printf '%s\n' "$_body" | subst_paths >>"$_s"
  ( bash "$_s" >"$TMPROOT/out-$_id" 2>&1 ); echo "$?"
}

out_of() { cat "$TMPROOT/out-$1" 2>/dev/null; }

# =====================================================================================
# R7. Phase P step 3's own fence (Task 4, ADR-0134 §D1/§D2/§D8/§D9, R-02/R-06/R-07). TEST ONLY — the
# fence does not exist yet (Task 5, a later batch, adds `<!-- fence-contract:
# autopilot-prep-row-select -->` to autopilot/SKILL.md above step 3), so every case below is RED via
# EXTRACT_FAILED right now: run_fence's own contract is "echo EXTRACT_FAILED and return" when
# enumerate_fences/extract_fence find no matching marker in autopilot/SKILL.md — exactly the RED
# ADR-0101 rule 1 calls for, for the right reason, not a broken harness.

# setup_prs <root> <scope_only> — binds the fence's three free variables (ADR-0134 §D9: "export
# _root _scope_only CLAUDE_PLUGIN_ROOT"). CLAUDE_PLUGIN_ROOT is bound to the STAGING copy, never
# left unbound — an unbound CLAUDE_PLUGIN_ROOT falls through to $HOME/.claude and can make an
# assertion pass from the DEPLOYED copy while testing nothing, the exact defect found in this
# session's own RJ14 (ADR-0132). Every inline fence invocation in this section binds it.
setup_prs() {
  cat >"$TMPROOT/setup-prs.sh" <<SETUP_EOF
_root='$1'
_scope_only='$2'
CLAUDE_PLUGIN_ROOT='$STAGING/plugin'
SETUP_EOF
  printf '%s' "$TMPROOT/setup-prs.sh"
}

# flat_out <text> — whitespace-flattened, decoration-stripped: a prose assertion must not depend on
# where the fence's output wraps, or on backticks/asterisks (ADR-0073/0076/0080/0098, seven
# recorded instances of the same family). Used only by PRS20b below.
flat_out() { printf '%s' "$1" | tr '\n' ' ' | tr -s ' ' | tr -d '`*'; }

# --- PRS20/PRS20b fixture: the helper is NOT deployed on EITHER resolution tier -----------------
# CLAUDE_PLUGIN_ROOT points at an empty tree (no skills/autopilot/scripts/prep-row-select.sh under
# it); the fallback tier is redirected — via a LOCAL substitution, never the shared subst_paths,
# which targets the real staging skills/ that already carries prep-row-select.sh since Task 3 — to
# a second, separate empty directory. subst_paths alone cannot express "not deployed" here: Task 3
# already landed the real helper in staging/, so the shared substitution would resolve it on the
# fallback tier and the fixture would pass for the wrong reason.
EMPTY_PLUGIN_ROOT="$TMPROOT/empty-plugin-root"
mkdir -p "$EMPTY_PLUGIN_ROOT/skills"
EMPTY_HOME_SKILLS="$TMPROOT/empty-home-skills"
mkdir -p "$EMPTY_HOME_SKILLS"

setup_prs20() {
  cat >"$TMPROOT/setup-prs20.sh" <<SETUP_EOF
_root='$1'
_scope_only=''
CLAUDE_PLUGIN_ROOT='$EMPTY_PLUGIN_ROOT'
SETUP_EOF
  printf '%s' "$TMPROOT/setup-prs20.sh"
}

subst_paths_missing() {
  sed -e "s|\$HOME/.claude/skills/|$EMPTY_HOME_SKILLS/|g" -e "s|~/.claude/skills/|$EMPTY_HOME_SKILLS/|g"
}

run_fence_prs20() {
  _id="$1"; _f="$2"; _setup="$3"
  _body=$(extract_fence "$_f" "$_id") || { echo "EXTRACT_FAILED"; return; }
  if [ -z "$_body" ]; then echo "EXTRACT_EMPTY"; return; fi
  _s="$TMPROOT/run-$_id-prs20.sh"
  { cat "$_setup"; printf '\n'; } >"$_s"
  printf '%s\n' "$_body" | subst_paths_missing >>"$_s"
  ( bash "$_s" >"$TMPROOT/out-$_id-prs20" 2>&1 ); echo "$?"
}
out_of_prs20() { cat "$TMPROOT/out-$1-prs20" 2>/dev/null; }

R=$(mk_root prs20)
printf '%s\t%s\t%s\n' "prs20-x" "6001" "X feature" > "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] X feature  (issue #6001)\n' > "$R/PROJECT.md"
PRS20_RC=$(run_fence_prs20 "autopilot-prep-row-select" "$NA" "$(setup_prs20 "$R")")
PRS20_OUT=$(out_of_prs20 "autopilot-prep-row-select")

# PRS20: the fence exits 3, names the sync command, and prints no selected row.
if [ "$PRS20_RC" = "3" ] && printf '%s' "$PRS20_OUT" | grep -qF "sync-to-claude.sh --apply" \
   && ! printf '%s' "$PRS20_OUT" | grep -q "PREP-SELECT-ROW:"; then
  ok "PRS20: prep-row-select.sh not deployed on either tier -> fence exit 3, names sync-to-claude.sh --apply, no selected row (R-07)"
else
  bad "PRS20: rc=$PRS20_RC out=$(printf '%s' "$PRS20_OUT" | head -2)"
fi
# plant: PRS20 | plugin/skills/autopilot/SKILL.md | exit 3   # DID-NOT-RUN: never fall back to generating every uncovered row | exit 0

# PRS20b: the SAME case — the output states Phase P halts and does not fall back. Matched against a
# whitespace-flattened, decoration-stripped copy (see flat_out above).
PRS20_FLAT=$(flat_out "$PRS20_OUT")
PRS20B_OK=1
printf '%s' "$PRS20_FLAT" | grep -qi "halt" || PRS20B_OK=0
printf '%s' "$PRS20_FLAT" | grep -qi "never" || PRS20B_OK=0
printf '%s' "$PRS20_FLAT" | grep -qiE 'fall.back|fallback' || PRS20B_OK=0
if [ "$PRS20B_OK" = "1" ]; then
  ok "PRS20b: the same case states Phase P halts and never falls back (flattened, decoration-stripped match)"
else
  bad "PRS20b: flattened output does not state halt+never-fall-back — $(printf '%s' "$PRS20_FLAT" | head -c 200)"
fi

# --- PRS21/PRS21b/PRS21c/PRS21d fixtures: the helper IS deployed (CLAUDE_PLUGIN_ROOT -> staging,
# where Task 3 already landed prep-row-select.sh) — plain run_fence resolves it on the first tier.

# PRS21: happy path, _scope_only empty -> rc 0, one PREP-SELECT-ROW: line for the selected row and
# none for the suppressed one.
R=$(mk_root prs21)
printf '%s\t%s\t%s\n' "prs21-a" "6101" "A feature" > "$R/docs/specs/_issue-map.tsv"
printf '%s\t%s\t%s\n' "prs21-b" "6102" "B feature" >> "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] A feature  (issue #6101)\n- [x] B feature  (issue #6102)\n' > "$R/PROJECT.md"
RC=$(run_fence "autopilot-prep-row-select" "$NA" "$(setup_prs "$R" "")")
OUT=$(out_of "autopilot-prep-row-select")
SEL_COUNT=$(printf '%s\n' "$OUT" | grep -c '^PREP-SELECT-ROW:')
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qF 'PREP-SELECT-ROW: prs21-a' \
   && ! printf '%s' "$OUT" | grep -qF 'PREP-SELECT-ROW: prs21-b' \
   && [ "$SEL_COUNT" = "1" ]; then
  ok "PRS21: happy path, _scope_only empty -> rc 0, one PREP-SELECT-ROW: line for the selected row, none for the suppressed one (R-07)"
else
  bad "PRS21: rc=$RC sel_count=$SEL_COUNT out=$(printf '%s' "$OUT" | head -3)"
fi

# PRS21b: _scope_only=42 -> rc 0, PREP-SELECT-ROW: for the #42 row only.
R=$(mk_root prs21b)
printf '%s\t%s\t%s\n' "prs21b-a" "42" "A feature" > "$R/docs/specs/_issue-map.tsv"
printf '%s\t%s\t%s\n' "prs21b-b" "43" "B feature" >> "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] A feature  (issue #42)\n- [ ] B feature  (issue #43)\n' > "$R/PROJECT.md"
RC=$(run_fence "autopilot-prep-row-select" "$NA" "$(setup_prs "$R" "42")")
OUT=$(out_of "autopilot-prep-row-select")
SEL_COUNT=$(printf '%s\n' "$OUT" | grep -c '^PREP-SELECT-ROW:')
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qF 'PREP-SELECT-ROW: prs21b-a' \
   && ! printf '%s' "$OUT" | grep -qF 'PREP-SELECT-ROW: prs21b-b' \
   && [ "$SEL_COUNT" = "1" ]; then
  ok "PRS21b: _scope_only=42 -> rc 0, PREP-SELECT-ROW: for the #42 row only (R-02)"
else
  bad "PRS21b: rc=$RC sel_count=$SEL_COUNT out=$(printf '%s' "$OUT" | head -3)"
fi

# PRS21c: helper present but returning 3 (an unreadable PROJECT.md) -> fence exit 3, message says
# the selection did not run. Guarded per ADR-0028's CI-root caveat (a chmod 000 file may still be
# readable there, expressing nothing).
R=$(mk_root prs21c)
printf '%s\t%s\t%s\n' "prs21c-x" "6201" "X feature" > "$R/docs/specs/_issue-map.tsv"
printf -- '- [ ] X feature  (issue #6201)\n' > "$R/PROJECT.md"
chmod 000 "$R/PROJECT.md" 2>/dev/null
if [ -r "$R/PROJECT.md" ]; then
  ok "PRS21c (skipped, not asserted): this user can read a chmod-000 file — the unreadable-PROJECT.md case is not expressible here (ADR-0028 root caveat)"
else
  RC=$(run_fence "autopilot-prep-row-select" "$NA" "$(setup_prs "$R" "")")
  OUT=$(out_of "autopilot-prep-row-select")
  FLAT=$(flat_out "$OUT")
  if [ "$RC" = "3" ] && printf '%s' "$FLAT" | grep -qi "did.not.run"; then
    ok "PRS21c: helper rc=3 (unreadable PROJECT.md) -> fence exit 3, message says the selection did not run (R-06)"
  else
    bad "PRS21c: rc=$RC out=$(printf '%s' "$OUT" | head -2)"
  fi
fi

# PRS21d: helper returning 2 (bad invocation forced by an empty _root, so the fence's own
# `--root "$_root"` call passes the helper an empty value) -> fence exit 2, distinct from exit 3.
# Without this, one code stands for two states and the vocabulary ADR-0134 §D8 declares is
# unasserted.
RC=$(run_fence "autopilot-prep-row-select" "$NA" "$(setup_prs "" "")")
OUT=$(out_of "autopilot-prep-row-select")
if [ "$RC" = "2" ]; then
  ok "PRS21d: helper rc=2 (bad invocation, empty --root) -> fence exit 2, distinct from exit 3 (ADR-0134 §D8)"
else
  bad "PRS21d: rc=$RC out=$(printf '%s' "$OUT" | head -2)"
fi

# =====================================================================================
# PAIRS. PRS22 (Task 6, R-08): the PAIRS entry for prep-row-select.sh exists in sync-to-claude.sh,
# matched on the FULL src|dst pair -- never on the filename alone. pairs-completeness.test.sh only
# validates that every PAIRS src exists under staging/; it is structurally blind to a skill-private
# scripts/ file that PAIRS never mentions at all (ADR-0043), so this is the ONLY guard for the entry.
# RED right now: the coder's next batch (Task 6's own sub-step) adds the entry to
# staging/sync-to-claude.sh. Do not add the entry here -- that file is not a test file and is not
# the tester's to write.
SYNC="$STAGING/sync-to-claude.sh"
if [ -f "$SYNC" ] && grep -qxF \
  'plugin/skills/autopilot/scripts/prep-row-select.sh|skills/autopilot/scripts/prep-row-select.sh' \
  "$SYNC"; then
  ok "PRS22: the PAIRS entry for prep-row-select.sh exists in sync-to-claude.sh, matched on the full src|dst pair (ADR-0043, R-08)"
else
  bad "PRS22: no PAIRS entry (full src|dst pair) for prep-row-select.sh found in sync-to-claude.sh"
fi

# =====================================================================================
# PRS99 — assertion floor for this file (ADR-0124: a floor, not an exact count, raised in the same
# edit that adds assertions, or it carries slack and an assertion can vanish while it stays green).
# >= 26 after this task (PRS01-PRS19 plus PRS20/PRS20b/PRS21/PRS21b/PRS21c/PRS21d plus PRS22).
_prs99_total=$((PASS + FAIL))
if [ "$_prs99_total" -ge 26 ]; then
  ok "PRS99: assertion-count floor ($_prs99_total >= 26)"
else
  bad "PRS99: only $_prs99_total assertions ran (floor 26) — assertions vanished from this file"
fi

echo
echo "prep-row-select.test.sh — PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
