#!/bin/bash
# skill-fence-positional-tokens.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash skill-fence-positional-tokens.test.sh
#
# THE RULE — a bash fence in a staged SKILL.md must contain no positional-parameter token
# (a bare `$` followed by a digit). Claude Code whitespace-splits a skill's own argument list and
# substitutes it into every such token in the skill's rendered body, 0-indexed, BEFORE the model
# sees it — a bash fence is text, so it is rewritten too, silently, producing syntactically valid
# shell that does the wrong thing (ADR-0132, issue #385).
#
# THE WAIVER — a genuine prose mention of the idiom (never a real occurrence) is excused with:
#
#     # fence-dollar-exempt: <reason, at least 40 characters>
#
# on the offending line itself (as a trailing comment), or on its own line immediately above it.
# ONE LINE ONLY — a reason that wraps is a prose assertion depending on where the text breaks, the
# family this repository has been bitten by seven times (ADR-0073, ADR-0076, ADR-0080, ADR-0082,
# ADR-0098, ADR-0101, ADR-0111). The corpus holds ZERO waivers today (ADR-0132 §D7), so the
# reason-length and adjacency sub-checks below are exercised against a temp-directory fixture
# (SFP7), never a real SKILL.md — never write the literal marker string in prose to explain it;
# that would be rule 12 (a scan whose needle is a literal counts itself) one level up.
#
# THE PARTITION, NOT A GREP. Every line carrying a positional-parameter token in
# staging/plugin/skills/*/SKILL.md is split three ways — BASH (inside a bash fence) / NONBASH
# (inside a fence of another language) / PROSE (outside any fence) — and the three are asserted to
# SUM to the file-wide count (SFP3). A denominator guard (>= N files, >= N bash fences) catches a
# glob that stopped resolving wholesale; it cannot catch a fence predicate that has narrowed and
# now under-reports, which reads exactly like a clean corpus. The sum identity does (ADR-0132 §D6).
#
# population() TAKES FILE PATHS, NEVER A DIRECTORY (ADR-0085) — so the SFP7 temp-dir waiver fixture
# is classified by the exact code path the real corpus uses, rather than a second predicate that
# could disagree with the first.
#
# SFP4 IS EXPECTED RED (R-01) FROM THIS TASK UNTIL TASK 7. It is the guard the plan's later tasks
# turn green one occurrence at a time; a checkpoint review that sees it red must read ADR-0132's
# "Residual count per task" table, not treat it as a regression.
#
# skills/*/scripts/*.sh IS NOT IN THE POPULATION (SFP6). The scripts this feature's later tasks add
# are full of legitimate positional parameters, and a guard later widened to all of staging/ would
# fail on its own fix.
#
# DERIVED-GUARD PATTERN — instance 14 (ADR-0086). Derives: positional-parameter-token lines inside
# staging/plugin/skills/*/SKILL.md, partitioned by enclosing fence language. Waiver:
# `# fence-dollar-exempt: <reason>`, on the offending line or the line immediately above it.
# The pattern is deliberately COPIED, not shared: this file asks its own question about its own
# population, so a second copy giving a different answer would not be a defect (ADR-0086 §D1).
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
SKILLS="$STAGING/plugin/skills"
ADR_PATH="$REPO/docs/architecture/ADR-0132-385-skill-args-in-fences.md"
CLAUDE_MD="$REPO/CLAUDE.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# =====================================================================================
# Shared machinery.

# enumerate_fences <file> — one record per bash fence: "<opener-line>\t<marker-or-NONE>".
# COPIED VERBATIM from fence-contract-coverage.test.sh:71 (ADR-0086 — do not source that file).
# Indentation-tolerant: `autopilot` indents fences inside numbered list items, and a column-0
# anchor undercounts (the "101 instead of 138" lesson).
enumerate_fences() {
  awk '
    function flush_marker() { last_marker = "NONE" }
    {
      line = $0
      stripped = line; sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^<!--[[:space:]]*fence-(contract|illustration):/) { pending = stripped; next }
      if (stripped == "") { next }                     # blank lines do not clear a pending marker
      if (infence) {
        if (stripped == "```") { infence = 0 }
        next
      }
      if (stripped ~ /^```bash[[:space:]]*$/) {
        printf "%d\t%s\n", NR, (pending == "" ? "NONE" : pending)
        pending = ""; infence = 1; next
      }
      pending = ""                                     # any other content clears it
    }
  ' "$1"
}

# classify_file <file> — one record per positional-parameter-token line:
#   "<file>\t<line>\t<bucket>\t<waived:0|1>\t<reason-length>"
# bucket is BASH / NONBASH / PROSE. This tracks EVERY fence (any language), independent of
# enumerate_fences above (which only recognises ```bash) — a line outside all fences still
# classifies as PROSE. Indentation-tolerant, same technique as enumerate_fences.
#
# Waiver recognition is substring, not anchored-at-start: the marker may sit as a trailing comment
# on the offending line itself, or as its own comment line directly above it (ADR-0132 §D7).
classify_file() {
  awk -v file="$1" '
    function is_waiver(s) { return (s ~ /fence-dollar-exempt:[[:space:]]*.+/) }
    function reason_len(s,   r) {
      r = s
      sub(/.*fence-dollar-exempt:[[:space:]]*/, "", r)
      return length(r)
    }
    function emit(bucket,   w, rl) {
      w = 0; rl = 0
      if (is_waiver(stripped))          { w = 1; rl = reason_len(stripped) }
      else if (is_waiver(prevstripped)) { w = 1; rl = reason_len(prevstripped) }
      printf "%s\t%d\t%s\t%d\t%d\n", file, NR, bucket, w, rl
    }
    {
      line = $0
      stripped = line; sub(/^[[:space:]]+/, "", stripped)
      if (infence) {
        if (stripped == "```") { infence = 0; lang = ""; prevstripped = stripped; next }
        if (line ~ /\$[0-9]/) { emit((lang == "bash") ? "BASH" : "NONBASH") }
        prevstripped = stripped
        next
      }
      if (stripped ~ /^```/) {
        lang = stripped; sub(/^```/, "", lang)
        infence = 1
        prevstripped = stripped
        next
      }
      if (line ~ /\$[0-9]/) { emit("PROSE") }
      prevstripped = stripped
    }
  ' "$1"
}

# population <file>... — TSV records over every positional-parameter-token line in the given files.
# FILE PATHS, never a directory (ADR-0085), so the SFP7 temp-dir fixture is classified by the exact
# code path the real corpus uses.
population() {
  for _f in "$@"; do
    [ -f "$_f" ] || continue
    classify_file "$_f"
  done
}

# =====================================================================================
# The derivation itself.

SKILL_FILES="$TMPROOT/skill_files"; : >"$SKILL_FILES"
for f in "$SKILLS"/*/SKILL.md; do
  [ -f "$f" ] && printf '%s\n' "$f" >>"$SKILL_FILES"
done
SKILL_N=$(grep -c . "$SKILL_FILES")

# SFP1: denominator count guard on the SKILL.md glob (ADR-0085 — guard the denominator, not just
# the matches). A glob that stops resolving reports zero candidates, which reads exactly like a
# corpus with nothing to check.
if [ "$SKILL_N" -ge 25 ]; then
  ok "SFP1: SKILL.md population non-vacuous ($SKILL_N files)"
else
  bad "SFP1: only $SKILL_N SKILL.md files found — expected >= 25; the glob is broken, not clean"
fi

FENCE_N=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  _n=$(enumerate_fences "$f" | grep -c .)
  FENCE_N=$((FENCE_N + _n))
done <"$SKILL_FILES"

# SFP2: second denominator count guard, on the bash-fence population specifically. A fence parser
# that stops matching wholesale reports zero candidates, indistinguishable from a clean corpus.
if [ "$FENCE_N" -ge 100 ]; then
  ok "SFP2: bash fence population non-vacuous ($FENCE_N bash fences)"
else
  bad "SFP2: only $FENCE_N bash fences enumerated — expected >= 100; the parser is broken, not clean"
fi

POP_FILE="$TMPROOT/pop"
population "$SKILLS"/*/SKILL.md >"$POP_FILE"

BASH_N=$(awk -F'\t' '$3=="BASH"'    "$POP_FILE" | grep -c .)
NONBASH_N=$(awk -F'\t' '$3=="NONBASH"' "$POP_FILE" | grep -c .)
PROSE_N=$(awk -F'\t' '$3=="PROSE"'   "$POP_FILE" | grep -c .)

# Independent cross-check for SFP3: a plain per-file grep, entirely separate from the fence-tracking
# state machine in classify_file. If the two disagree, the partition — not the plain count — has
# narrowed or widened.
FILEWIDE_N=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  _n=$(grep -cE '\$[0-9]' "$f")
  FILEWIDE_N=$((FILEWIDE_N + _n))
done <"$SKILL_FILES"

# SFP3 (partition identity, ADR-0132 §D6): BASH + NONBASH + PROSE must equal the file-wide count.
# This is what catches a fence predicate that has narrowed and now under-reports — a denominator
# guard alone cannot, because a narrowed predicate still reports a non-zero, plausible-looking
# count.
# plant: SFP3 | plugin/scripts/tests/skill-fence-positional-tokens.test.sh | if (line ~ /\$[0-9]/) { emit((lang == "bash") ? "BASH" : "NONBASH") } | if (line ~ /\$[1-9]/) { emit((lang == "bash") ? "BASH" : "NONBASH") }
SUM_N=$((BASH_N + NONBASH_N + PROSE_N))
if [ "$SUM_N" -eq "$FILEWIDE_N" ]; then
  ok "SFP3: partition identity holds (BASH=$BASH_N + NONBASH=$NONBASH_N + PROSE=$PROSE_N = $SUM_N = file-wide $FILEWIDE_N)"
else
  bad "SFP3: partition identity broken — BASH+NONBASH+PROSE=$SUM_N but the independent file-wide count is $FILEWIDE_N; the fence predicate has narrowed or widened"
fi

# SFP4 (R-01, EXPECTED RED from Task 1 until Task 7 — ADR-0132 "Residual count per task" table):
# every BASH-bucket occurrence, minus a validly declared waiver, must be gone. On failure, every
# offender is printed as <skill>:<line>.
#
# PLANT DECLARED HERE, NOT AT TASK 1 (R-02's failing-direction verification — ADR-0132 §Task 7's
# checkpoint). Before Task 7, SFP4 was expected-RED on its own, so plant-check.sh could not tell a
# plant firing from an assertion that was already red — a plant declared then would have been
# worthless evidence. Now that SFP4 is green, the plant is the whole point of the guard: it
# reintroduces exactly one positional-parameter token into a real bash fence — git-repo-init's
# Fase 0 prerequisites check, the corpus's smallest bash fence (one line, no fence-contract marker,
# untouched by any other harness) — and requires SFP4 to go red naming that exact occurrence.
# Manually verified against an isolated copy before declaring: SFP4 fails printing exactly
# "git-repo-init:28", with SFP1/SFP2/SFP3/SFP5/SFP6/SFP7/SFP8/SFP9/SFP10/Z1 all still green.
# plant: SFP4 | plugin/skills/git-repo-init/SKILL.md | git --version && gh --version && gh auth status | git --version && gh --version "$1" && gh auth status
UNWAIVED=""
while IFS="$(printf '\t')" read -r f ln bucket waived rlen; do
  [ -n "$f" ] || continue
  [ "$bucket" = "BASH" ] || continue
  if [ "$waived" = "1" ] && [ "$rlen" -ge 40 ]; then
    continue   # validly excused
  fi
  _skill=$(basename "$(dirname "$f")")
  UNWAIVED="$UNWAIVED
$_skill:$ln"
done <"$POP_FILE"
UNWAIVED=$(printf '%s\n' "$UNWAIVED" | grep -v '^$')
if [ -z "$UNWAIVED" ]; then
  ok "SFP4 (R-01): no unwaived positional-parameter token remains inside a bash fence"
else
  _n_off=$(printf '%s\n' "$UNWAIVED" | grep -c .)
  bad "SFP4 (R-01, EXPECTED RED — see ADR-0132 'Residual count per task'): $_n_off unwaived occurrence(s) inside a bash fence:"
  printf '%s\n' "$UNWAIVED" | sed 's/^/        /'
fi

# SFP5 (R-03): the NONBASH bucket must be non-empty AND contain swiftui-pro's occurrence — the
# language filter is exercised by a real corpus member, not by an exclusion list. If that Swift
# line is ever rewritten this must fail, not silently pass (ADR-0081 ZA4).
# plant: SFP5 | plugin/scripts/tests/skill-fence-positional-tokens.test.sh | case "$f" in */swiftui-pro/SKILL.md) _has_swiftui=1 ;; esac | case "$f" in */nomatch-swiftui/SKILL.md) _has_swiftui=1 ;; esac
_has_swiftui=0
while IFS="$(printf '\t')" read -r f ln bucket waived rlen; do
  [ -n "$f" ] || continue
  [ "$bucket" = "NONBASH" ] || continue
  case "$f" in */swiftui-pro/SKILL.md) _has_swiftui=1 ;; esac
done <"$POP_FILE"
if [ "$NONBASH_N" -ge 1 ] && [ "$_has_swiftui" = "1" ]; then
  ok "SFP5 (R-03): NONBASH bucket is non-empty ($NONBASH_N) and contains swiftui-pro's occurrence"
else
  bad "SFP5 (R-03): NONBASH bucket empty or missing swiftui-pro's occurrence (N=$NONBASH_N, has_swiftui=$_has_swiftui) — if that Swift line was rewritten this must fail, not silently pass"
fi

# SFP6 (R-03): skills/*/scripts/*.sh must never enter the population. The scripts this feature's
# later tasks add are full of legitimate positional parameters, and a guard widened to all of
# staging/ would fail on its own fix.
# plant: SFP6 | plugin/scripts/tests/skill-fence-positional-tokens.test.sh | grep -q '/scripts/' | grep -qv '/scripts/'
if awk -F'\t' '{print $1}' "$POP_FILE" | grep -q '/scripts/'; then
  bad "SFP6 (R-03): population includes a path under /scripts/ — a helper script's own positional-parameter token would trip this guard"
else
  ok "SFP6 (R-03): population contains no path under /scripts/ (skills/*/scripts/*.sh helpers stay out of scope by design)"
fi

# =====================================================================================
# SFP7: the waiver parser, both directions, against a temp-dir fixture (ADR-0132 §D7). The corpus
# holds zero waivers today, so this is exercised synthetically rather than against a real SKILL.md.

WV="$TMPROOT/waiver"; mkdir -p "$WV"

# Case A: trailing comment on the offending line itself, reason >= 40 chars -> excused.
cat >"$WV/a.md" <<'EOF'
# t

```bash
echo "$1"  # fence-dollar-exempt: kept for illustration of the legacy call form in migration docs
```
EOF

# Case B: comment on its own line, directly above the offending line, reason >= 40 chars -> excused.
cat >"$WV/b.md" <<'EOF'
# t

```bash
# fence-dollar-exempt: kept for illustration of the legacy call form in migration docs only
echo "$1"
```
EOF

# Case C: trailing comment, reason < 40 chars -> detected but NOT excused.
cat >"$WV/c.md" <<'EOF'
# t

```bash
echo "$1"  # fence-dollar-exempt: too short
```
EOF

# Case D: the marker sits TWO lines above the offending line (a continuation comment intervenes) ->
# not recognised as a waiver at all. One line only, and it must be directly adjacent.
cat >"$WV/d.md" <<'EOF'
# t

```bash
# fence-dollar-exempt: this reason deliberately continues
# onto a second physical line and must not be honoured
echo "$1"
```
EOF

_sfp7_fail=""
# plant: SFP7 | plugin/scripts/tests/skill-fence-positional-tokens.test.sh | function is_waiver(s) { return (s ~ /fence-dollar-exempt:[[:space:]]*.+/) } | function is_waiver(s) { return (s ~ /fence-dollar-exemptZ:[[:space:]]*.+/) }

_rec=$(population "$WV/a.md" | awk -F'\t' '$3=="BASH"')
_w=$(printf '%s' "$_rec" | cut -f4); _rl=$(printf '%s' "$_rec" | cut -f5)
if [ "$_w" = "1" ] && [ -n "$_rl" ] && [ "$_rl" -ge 40 ]; then :; else
  _sfp7_fail="$_sfp7_fail
    case A (trailing same-line marker, long reason) should be excused: waived=$_w reasonlen=$_rl"
fi

_rec=$(population "$WV/b.md" | awk -F'\t' '$3=="BASH"')
_w=$(printf '%s' "$_rec" | cut -f4); _rl=$(printf '%s' "$_rec" | cut -f5)
if [ "$_w" = "1" ] && [ -n "$_rl" ] && [ "$_rl" -ge 40 ]; then :; else
  _sfp7_fail="$_sfp7_fail
    case B (marker on the line above, long reason) should be excused: waived=$_w reasonlen=$_rl"
fi

_rec=$(population "$WV/c.md" | awk -F'\t' '$3=="BASH"')
_w=$(printf '%s' "$_rec" | cut -f4); _rl=$(printf '%s' "$_rec" | cut -f5)
if [ "$_w" = "1" ] && [ -n "$_rl" ] && [ "$_rl" -lt 40 ]; then :; else
  _sfp7_fail="$_sfp7_fail
    case C (trailing same-line marker, short reason) should be detected but too short: waived=$_w reasonlen=$_rl"
fi

_rec=$(population "$WV/d.md" | awk -F'\t' '$3=="BASH"')
_w=$(printf '%s' "$_rec" | cut -f4)
if [ "$_w" = "0" ]; then :; else
  _sfp7_fail="$_sfp7_fail
    case D (marker two lines above, not adjacent) should NOT be recognised as a waiver at all: waived=$_w"
fi

if [ -z "$_sfp7_fail" ]; then
  ok "SFP7: waiver parser correct in both directions against a temp-dir fixture (excuses a long adjacent reason, refuses a short or non-adjacent one)"
else
  bad "SFP7: waiver parser incorrect:$_sfp7_fail"
fi

# =====================================================================================
# SFP8: waiver count guard. Reports the number of declared waivers in the REAL corpus (as opposed
# to the SFP7 fixture) and distinguishes "genuinely zero" from "the counting pipeline broke" —
# ADR-0076's line, drawn again: a check that did not run must not read as a check that found
# nothing.
# plant: SFP8 | plugin/scripts/tests/skill-fence-positional-tokens.test.sh | '$3=="BASH" && $4==1' | '$3=="BASH" && $4==1 {'
_sfp8_err="$TMPROOT/sfp8.err"
WAIVER_N=$(awk -F'\t' '$3=="BASH" && $4==1' "$POP_FILE" 2>"$_sfp8_err" | grep -c .)
if [ -s "$_sfp8_err" ]; then
  bad "SFP8: waiver count guard — the counting pipeline reported an error, not zero: $(head -1 "$_sfp8_err")"
elif [ "$WAIVER_N" -eq 0 ]; then
  ok "SFP8: 0 declared waivers in the corpus today (ADR-0132 §D7) — SFP7's reason-length and adjacency checks run only against the temp-dir fixture, not a real SKILL.md; the sub-assertions there are vacuous by design on this corpus, not a bug"
else
  ok "SFP8: $WAIVER_N declared waiver(s) present in the corpus"
fi

# SFP9 (informational, ADR-0132 §D8): the PROSE bucket is reported, never gated — R-01/R-02 scope
# to bash fences only, and the corpus has zero prose occurrences today. Widening to prose is a
# named follow-up, not this feature's job.
ok "SFP9 (informational): $PROSE_N positional-parameter-token line(s) found outside any fence (prose) — reported per ADR-0132 §D8, never gated"

# =====================================================================================
# SFP10 (R-04): the ADR exists and names the mechanism (whitespace-split, 0-indexed substitution
# of a skill's argument list into every positional-parameter token in the skill's rendered body,
# before the model sees it). docs/ IS copied into the plant sandbox via the ../docs/ hatch
# (ADR-0116), so this one is plantable.
# plant: SFP10 | ../docs/architecture/ADR-0132-385-skill-args-in-fences.md | 0-indexed | 9-indexed
if [ -f "$ADR_PATH" ] && grep -qi 'whitespace-split' "$ADR_PATH" && grep -qi '0-indexed' "$ADR_PATH"; then
  ok "SFP10 (R-04): ADR-0132 exists and names the mechanism (whitespace-split, 0-indexed substitution)"
else
  bad "SFP10 (R-04): ADR-0132 missing, or does not name the mechanism (whitespace-split / 0-indexed substitution)"
fi

# =====================================================================================
# SFP11 (R-04): CLAUDE.md carries the record — a '## Decisions from the …' section naming
# ADR-0132, the four new scripts, and this guard file. NO PLANT DECLARED: plant-check.sh's
# sandbox copies only staging/ and docs/ (the ../docs/ hatch reaches docs/ only), so a repo-root
# CLAUDE.md target is unreachable by construction — ADR-0122's RG1 class. THIS ASSERTION ALWAYS
# FAILS INSIDE A PLANT SANDBOX. KNOWN NON-CHASEABLE FAILURE — if plant-check.sh ever reports
# SFP11 as not firing, that is this boundary, not a new defect; do not spend time hunting it
# there. SFP11 is RED until the coder writes the CLAUDE.md section (Task 8) — expected, not a
# regression.
if [ -f "$CLAUDE_MD" ] \
  && grep -qE '^## Decisions from the .*\(ADR-0132\)' "$CLAUDE_MD" \
  && grep -qF 'ADR-0132-385-skill-args-in-fences.md' "$CLAUDE_MD" \
  && grep -qF 'scope-args-parse.sh' "$CLAUDE_MD" \
  && grep -qF 'conductor-args.sh' "$CLAUDE_MD" \
  && grep -qF 'mark-roadmap-skipped.sh' "$CLAUDE_MD" \
  && grep -qF 'repo-rel-path.sh' "$CLAUDE_MD" \
  && grep -qF 'skill-fence-positional-tokens.test.sh' "$CLAUDE_MD"; then
  ok "SFP11 (R-04): CLAUDE.md carries a '## Decisions from the …' section naming ADR-0132, the four new scripts, and this guard"
else
  bad "SFP11 (R-04): CLAUDE.md has no '## Decisions from the …' section naming ADR-0132 with the four new scripts and this guard"
fi

# =====================================================================================
# Z1: assertion-count floor, set to the actual total (ADR-0124 — a floor with slack absorbs its own
# plant; set it at the real number, not below it).
_TOTAL=$((PASS + FAIL))
if [ "$_TOTAL" -ge 11 ]; then
  ok "Z1: $_TOTAL assertions ran (floor 11) — none silently vanished"
else
  bad "Z1: only $_TOTAL assertions ran, floor 11 — assertions disappeared, they did not fail"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
