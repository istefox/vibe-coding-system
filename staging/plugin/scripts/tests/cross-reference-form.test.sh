#!/bin/bash
# cross-reference-form.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash cross-reference-form.test.sh
#
# THE RULE — a cross-reference from one file into another (or into a distant part of the same
# file) must name a DISTINCTIVE ANCHOR, never a line number. Issues #207 and #210.
#
# Rule 3 of this repository's earned-rules list: references by line number rot. ADR-0018's
# addendum already fixed this once, on autopilot-build's four `§<line-range>` delegations into
# concept-to-code, and `workflow-dispatch-pins.test.sh` section B keeps those honest. That
# instrument was applied to ONE FILE. Nothing checked the class, so the same defect kept being
# written elsewhere — including by the very commits that were fixing neighbouring instances.
#
# WHY THE POPULATION IS DERIVED, NOT LISTED (rule 5 — ask which direction a guard runs in).
# #207 filed an inventory of five sites. #210 then verified two of them and added a whole
# surface the inventory had excluded by construction (hook source -> SKILL.md). Deriving the
# population over all of staging/ found THREE MORE WRONG references in a third surface neither
# issue named — skill-private `scripts/` directories, the same subtree ADR-0043 recorded
# `pairs-completeness.test.sh` as blind to. A check that validates the entries of a list cannot
# see what the list omits, and this rule has now been demonstrated three times on one defect.
#
# HOW A FALSE POSITIVE IS HANDLED. Some `<file>:<digits>` and `line <digits>` strings are not
# cross-references at all: illustrative paths in an Output Format example, a detector's own
# sample output, a script's stdout contract ("`public` (line 1)"). Those are declared IN THE FILE
# that carries them:
#
#     xref-exempt: <token>|<token>|... — <reason, at least 40 characters>
#
# in a shell comment or an HTML comment, ON ONE LINE. The one-line requirement is not cosmetic:
# a reason wrapped across lines is a prose assertion that depends on where the text breaks, and
# this repository has now been bitten by that three times (ADR-0073's line wrap, ADR-0076's
# comment marker, ADR-0080's backticks). U3 measures only the marker line, so a wrapped reason
# reads as too short — loudly, at the moment it is written, rather than silently later.
# Never a filename list inside this test: that is the
# identity waiver ADR-0069 PTD rejected — it does not travel on rename, and it lets a test author
# excuse a file without touching it. A declaration must also be LIVE (section S): a waiver for a
# token that no longer appears is flagged, or a stale exemption would keep a file green while
# quietly covering something new.
#
# The extractor SKIPS `xref-exempt:` lines. Without that, a declaration would satisfy itself:
# the tokens it names appear on the declaration line, so a waiver for a token present nowhere
# else would look live. Rule 12 — a scan whose needle is a literal counts itself.
#
# WHAT THIS DOES NOT DO. `docs/` is out of the population on purpose: ADRs and plans are
# historical records, not edited in place (the ADR-0034 precedent), so a line number in one is a
# correct snapshot of its own moment. And the check verifies that an anchor EXISTS in its target
# file, never that the anchor is the right place for the claim — that stays a reading task.
#
# DERIVED-GUARD PATTERN — instance 3 of 6 (ADR-0086). Derives: token occurrences inside a file. Waiver: `xref-exempt: <token>|<token> — <reason>`, which the extractor must SKIP.
# The pattern is deliberately COPIED across the six, not shared. Before writing a seventh by
# copying this file, read ADR-0086 §D1: extract only when two copies giving different answers
# would be a DEFECT. Here they would not — the six ask six questions about six populations.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
CC="$SKILLS/concept-to-code/SKILL.md"
HITL_REF="$SKILLS/concept-to-code/references/hitl-gates.md"
# VCS-048/ADR-0175: ## 5. HITL gates moved out of SKILL.md into references/hitl-gates.md, and
# C1/C2 (Gate 0d transition block, Step 2b TOFU guard) are boundary-straddling same-file
# references whose anchor and target now sit on opposite sides of that move — one occurrence
# stayed in SKILL.md, the other moved. Concatenate for the "same file" checks below (ADR-0174 D2
# pattern 3).
CC_TMP=$(mktemp)
cat "$CC" "$HITL_REF" >"$CC_TMP" 2>/dev/null
CC_MERGED="$CC_TMP"
RTF="$SKILLS/review-triage-fix/SKILL.md"
AB="$SKILLS/autopilot-build/SKILL.md"
COMMIT="$SKILLS/commit/SKILL.md"
MINIT="$SKILLS/concept-to-code/scripts/manifest-init.sh"
PFE="$SCRIPTS/pre-flight-pattern-enforce.sh"
HVW="$SCRIPTS/hook-verify-workflow.sh"
AWS="$SCRIPTS/agent-write-scope.sh"
SSCAN="$SCRIPTS/secret-scan.sh"
ICHK="$SCRIPTS/interface-check.sh"
CODER="$STAGING/plugin/agents/coder.md"
REPO=$(cd "$STAGING/.." && pwd)

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# The two forms. FORM1 is the file:line convention; FORM3 is the prose form ("line 30",
# "lines 91-94"). FORM2 — a bare `§<digits>` — is deliberately absent: in this repository that
# is overwhelmingly an ADR section reference (`ADR-0047 §D2`), and the one place it was ever a
# line range is already pinned by workflow-dispatch-pins.test.sh B1.
XREF_RE='([A-Za-z0-9_.-]+\.(md|sh|awk|py|json|yml|yaml):[0-9]+(-[0-9]+)?|[Ll]ines? [0-9]+([–-][0-9]+)?)'

extract_tokens() {   # $1 = file -> deduped tokens, one per line
  grep -v 'xref-exempt:' "$1" 2>/dev/null | grep -oE "$XREF_RE" 2>/dev/null | sort -u
}

declared_tokens() {  # $1 = file -> deduped declared tokens, one per line
  grep 'xref-exempt:' "$1" 2>/dev/null \
    | sed -e 's/.*xref-exempt:[[:space:]]*//' -e 's/[[:space:]]*—.*//' \
    | tr '|' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v '^$' | sort -u
}

declared_reasons() { # $1 = file -> one reason per declaration line
  grep 'xref-exempt:' "$1" 2>/dev/null | sed -e 's/^[^—]*—[[:space:]]*//'
}

population() {       # every staging file that can carry a cross-reference
  find "$STAGING" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.awk' \) \
    ! -path '*/tests/*' ! -name '*.test.sh' 2>/dev/null | sort
}

# =====================================================================================
# X. The derivation itself. A guard built on a population is worth exactly what the
# population is worth, and a glob that matches nothing reports success.

POP_FILE=$(mktemp); population >"$POP_FILE"
POP_N=$(grep -c . "$POP_FILE")

# Threshold set from the measured corpus (140 files at the time of writing), with headroom for
# deletion. A number picked without measuring first is a guard that passes on a broken glob.
if [ "$POP_N" -ge 100 ]; then
  ok "X1: population non-vacuous ($POP_N files)"
else
  bad "X1: population is $POP_N files — expected >= 100; the derivation is broken, not clean"
fi

# X2: the exclusion must hold, not be assumed. Every test file under tests/ quotes the stale
# tokens this change removes — including this one — so a population that reached them would
# count its own needles and could never go green.
if grep -q '/tests/' "$POP_FILE"; then
  bad "X2: population includes a path under tests/ — the harness would scan its own needles"
else
  ok "X2: no tests/ path in the population"
fi

# X3: both forms must actually be exercised by the corpus. If the regex stopped matching, every
# per-file check below would pass on an empty token set — the ADR-0039 lesson (a check that
# fails on everything and a check that works are told apart only by their positive twin).
TOK_TOTAL=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  _n=$(extract_tokens "$f" | grep -c . )
  TOK_TOTAL=$((TOK_TOTAL + _n))
done <"$POP_FILE"
if [ "$TOK_TOTAL" -ge 15 ]; then
  ok "X3: extractor matches a live corpus ($TOK_TOTAL tokens across the population)"
else
  bad "X3: only $TOK_TOTAL tokens extracted — expected >= 15; the regex has stopped matching"
fi

# =====================================================================================
# U. Every remaining token must be declared, in its own file, with a reason.

UNDECLARED=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  _toks=$(extract_tokens "$f")
  [ -n "$_toks" ] || continue
  _decl=$(declared_tokens "$f")
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if ! printf '%s\n' "$_decl" | grep -qxF "$t"; then
      UNDECLARED="$UNDECLARED
${f#$REPO/}: $t"
    fi
  done <<TOKS_EOF
$_toks
TOKS_EOF
done <"$POP_FILE"
UNDECLARED=$(printf '%s\n' "$UNDECLARED" | grep -v '^$')

if [ -z "$UNDECLARED" ]; then
  ok "U1: every line-number token in staging/ is either converted to an anchor or declared"
else
  bad "U1: undeclared line-number reference(s):"
  printf '%s\n' "$UNDECLARED" | sed 's/^/        /'
fi

# U2: a waiver must be live. A token declared but no longer present means the exemption has
# outlived its subject and is now covering nothing — the ZA4 direction, run backwards.
STALE_WAIVER=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  _decl=$(declared_tokens "$f")
  [ -n "$_decl" ] || continue
  _toks=$(extract_tokens "$f")
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if ! printf '%s\n' "$_toks" | grep -qxF "$t"; then
      STALE_WAIVER="$STALE_WAIVER
${f#$REPO/}: $t"
    fi
  done <<DECL_EOF
$_decl
DECL_EOF
done <"$POP_FILE"
STALE_WAIVER=$(printf '%s\n' "$STALE_WAIVER" | grep -v '^$')

if [ -z "$STALE_WAIVER" ]; then
  ok "U2: no exemption declares a token that no longer appears"
else
  bad "U2: stale exemption(s) — declared but absent:"
  printf '%s\n' "$STALE_WAIVER" | sed 's/^/        /'
fi

# U3: a reason is a sentence a human wrote. This checks it is present and substantial, never
# that it is true — the honest limit of the ADR-0077 T4 pattern, restated.
SHORT_REASON=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  _r=$(declared_reasons "$f")
  [ -n "$_r" ] || continue
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    if [ "${#r}" -lt 40 ]; then
      SHORT_REASON="$SHORT_REASON
${f#$REPO/}: ${#r} chars"
    fi
  done <<REASON_EOF
$_r
REASON_EOF
done <"$POP_FILE"
SHORT_REASON=$(printf '%s\n' "$SHORT_REASON" | grep -v '^$')

if [ -z "$SHORT_REASON" ]; then
  ok "U3: every exemption carries a reason of at least 40 characters"
else
  bad "U3: exemption reason too short (a bare waiver excuses nothing):"
  printf '%s\n' "$SHORT_REASON" | sed 's/^/        /'
fi

# U4: at least one exemption must exist, or U2/U3 are vacuous and the marker mechanism is
# untested by the real corpus.
DECL_FILES=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -q 'xref-exempt:' "$f" 2>/dev/null && DECL_FILES=$((DECL_FILES + 1))
done <"$POP_FILE"
if [ "$DECL_FILES" -ge 5 ]; then
  ok "U4: $DECL_FILES files carry a declaration — U2/U3 are exercised"
else
  bad "U4: only $DECL_FILES files carry a declaration — expected >= 5, U2/U3 near-vacuous"
fi

# =====================================================================================
# S. Self-tests. The checks above pass on a clean tree; these prove they can fail, and fail
# for the right cause. Run against fixtures, through the same functions.

FIX=$(mktemp -d)
trap 'rm -rf "$FIX" "$POP_FILE" "$CC_TMP"' EXIT

printf '#!/bin/bash\n# see other.sh:42 for the contract\n' >"$FIX/undeclared.sh"
printf '#!/bin/bash\n# xref-exempt: other.sh:42 — illustrative path in this fixture, not a real cross-reference at all\n# see other.sh:42 for the contract\n' >"$FIX/declared.sh"
printf '#!/bin/bash\n# xref-exempt: gone.sh:9 — illustrative path in this fixture, not a real cross-reference at all\n# nothing here now\n' >"$FIX/stale.sh"
printf '#!/bin/bash\n# xref-exempt: other.sh:42 — too short\n# see other.sh:42\n' >"$FIX/shortreason.sh"

_und=$(extract_tokens "$FIX/undeclared.sh")
_dec=$(declared_tokens "$FIX/undeclared.sh")
if [ "$_und" = "other.sh:42" ] && [ -z "$_dec" ]; then
  ok "S1: an undeclared token is extracted and matches no declaration"
else
  bad "S1: extraction/declaration disagree on the undeclared fixture (tok='$_und' decl='$_dec')"
fi

_und=$(extract_tokens "$FIX/declared.sh")
_dec=$(declared_tokens "$FIX/declared.sh")
if [ "$_und" = "other.sh:42" ] && [ "$_dec" = "other.sh:42" ]; then
  ok "S2: a declared token is extracted once and matched by its declaration"
else
  bad "S2: declared fixture mismatch (tok='$_und' decl='$_dec')"
fi

# S3 is the one that matters most: the declaration line itself contains the token, so an
# extractor that did not skip `xref-exempt:` lines would report it as live and this fixture
# would pass while covering nothing.
_und=$(extract_tokens "$FIX/stale.sh")
_dec=$(declared_tokens "$FIX/stale.sh")
if [ -z "$_und" ] && [ "$_dec" = "gone.sh:9" ]; then
  ok "S3: a stale waiver is visible — declared token present, extracted set empty"
else
  bad "S3: stale fixture not detected (tok='$_und' decl='$_dec') — is the extractor skipping declaration lines?"
fi

_r=$(declared_reasons "$FIX/shortreason.sh")
if [ "${#_r}" -lt 40 ]; then
  ok "S4: a short reason measures short (${#_r} chars)"
else
  bad "S4: short-reason fixture measured ${#_r} chars — the reason split is wrong"
fi

# =====================================================================================
# C. The conversions. Each reference must NAME its anchor, and the anchor must EXIST in the
# target file exactly as many times as expected.
#
# Cross-file: expected 1 in the target. Same-file (a reference into a distant part of its own
# file): expected 2 — the anchor at the target plus the reference that names it. Asserting 2
# rather than ">= 1" fails on either half going missing, which is the failure this whole change
# exists to make loud.

xref() {  # label, referring-file, anchor, target-file, expected-count-in-target
  _l="$1"; _from="$2"; _a="$3"; _to="$4"; _exp="$5"
  if ! grep -qF "$_a" "$_from"; then
    bad "$_l: $(basename "$_from") does not name the anchor \"$_a\""
    return
  fi
  _n=$(grep -cF "$_a" "$_to")
  if [ "$_n" -eq "$_exp" ]; then
    ok "$_l: anchor named in $(basename "$_from"), $_n occurrence(s) in $(basename "$_to")"
  else
    bad "$_l: expected $_exp occurrence(s) of \"$_a\" in $(basename "$_to"), found $_n"
  fi
}

# C1/C2/C3 — same-file references (expected 2).
xref "C1" "$CC_MERGED"  'Gate 0d transition block'                        "$CC_MERGED"  2
xref "C2" "$CC_MERGED"  'Step 2b — TOFU guard (resume path only)'         "$CC_MERGED"  2
xref "C3" "$PFE" 'Fail-open on any internal error'                 "$PFE" 2

# C1b/C2b — the marker form must be unique at the target, or "2 occurrences" could be two
# references and no anchor at all.
for spec in "C1b|**Gate 0d transition block:**" "C2b|**Step 2b — TOFU guard (resume path only):**"; do
  _lbl=${spec%%|*}; _mk=${spec#*|}
  _n=$(grep -cF "$_mk" "$CC_MERGED")
  if [ "$_n" -eq 1 ]; then
    ok "$_lbl: exactly one marker \"$_mk\" in concept-to-code/SKILL.md"
  else
    bad "$_lbl: expected exactly 1 marker \"$_mk\", found $_n"
  fi
done

# C4..C14 — cross-file references (expected 1).
xref "C4"  "$CC"    '**Model override — branches on the variant declared in Step 0, item 5:**' "$RTF"    1
xref "C5"  "$AWS"   '**Dispatch architect:**'                                                  "$CC"     1
xref "C6"  "$AWS"   '**Validate architect output fields (before populating artifacts):**'      "$CC"     1
xref "C7"  "$HVW"   'if [ "$AGENT_TYPE" != "coder" ]'                                          "$PFE"    1
xref "C8"  "$SSCAN" '`.env`, `*secret*`, `*credential*`, `*.pem`'                              "$COMMIT" 1
xref "C9"  "$SKILLS/project-conductor/scripts/h16-direction-check.sh" 'tracer_bullet_verdict: null' "$MINIT" 1
xref "C10" "$ICHK"  'count_re()'                                                               "$SSCAN"  1
xref "C11" "$SKILLS/concept-to-code/scripts/spec-coverage.sh" 'count_re()'                     "$SSCAN"  1
xref "C12" "$SKILLS/concept-to-code/scripts/diff-budget-check.sh" 'docs/manifests/$today-$slug.manifest.yml' "$MINIT" 1
xref "C13" "$AB"    'Step 6 (PR) is also skipped in autopilot mode'                             "$COMMIT" 1
xref "C14" "$RTF"   'isolation: worktree'                                                       "$CODER"  1
xref "C15" "$PFE"   'an allow/block row cannot be matched on `agent_type=coder`'                 "$HVW"    1

# C10, C11, C14 and C15's target side pass before this change as well as after: their anchors
# already existed in the target files. They are FORWARD GUARDS on references that were merely
# numeric rather than wrong, not evidence that anything was fixed. U1 is what was red for them.

# =====================================================================================
# W. The six that were VERIFIED WRONG, named individually. U1 already covers them, but U1's
# message says "undeclared", not "this pointer sent a reader to a fence delimiter". Three of
# these six were named by no issue and were found only by deriving the population.

wrong_gone() {  # label, file, stale-token, what-it-actually-pointed-at
  if grep -qF "$3" "$2"; then
    bad "$1: $(basename "$2") still carries the wrong reference \"$3\" (it pointed at: $4)"
  else
    ok "$1: the wrong reference \"$3\" is gone from $(basename "$2")"
  fi
}
wrong_gone "W1" "$CC"    'SKILL.md:1355-1358' "the weakening-scan CLEAN warning; the transition block is near 2481"
wrong_gone "W2" "$AWS"   'SKILL.md:357'       "a bare code-fence delimiter; the plan-path order is near 372"
wrong_gone "W3" "$AWS"   'SKILL.md:409'       "a blank line; the HARD ABORT row is near 427"
wrong_gone "W4" "$HVW"   'lines 91-94'        "the ADR-0080 phase-2 verdict prose; the coder early return is near 169"
wrong_gone "W5" "$SSCAN" 'SKILL.md:70'        "the ADR-0062 debris bullet; the filename patterns are near 81"
wrong_gone "W6" "$SKILLS/project-conductor/scripts/h16-direction-check.sh" 'manifest-init.sh:125' \
  "the step5_review_mode comment; tracer_bullet_verdict is written near 136"

# W7: the drifted-but-nearly-right one. Converted in the same pass because it is the next to
# break, exactly as #207 asked.
wrong_gone "W7" "$CC" 'SKILL.md:152-158' "the Form-B branch list; the TOFU guard block starts at 156"

# =====================================================================================
# R. The rule must be written down where the next author looks, not only enforced here. A
# guard whose reasoning lives only in the guard gets deleted by whoever finds it inconvenient
# (the ADR-0080 D-section pattern: assert the reasoning is PRESENT, never that it is true).

CLAUDEMD="$REPO/CLAUDE.md"
if grep -q 'xref-exempt' "$CLAUDEMD"; then
  ok "R1: the exemption marker is documented in CLAUDE.md"
else
  bad "R1: CLAUDE.md does not mention the xref-exempt marker — the rule is enforced but unwritten"
fi

# R2: this file's own header must state why the population is derived rather than listed. That
# sentence is the whole argument for the shape of this test.
if grep -q 'WHY THE POPULATION IS DERIVED, NOT LISTED' "$0"; then
  ok "R2: this harness states why its population is derived"
else
  bad "R2: the derivation rationale has been removed from this harness's header"
fi

# R3: the docs/ exclusion is a decision, not an oversight, and must read as one.
if grep -q 'historical records, not edited in place' "$0"; then
  ok "R3: the docs/ exclusion is stated as a decision"
else
  bad "R3: the docs/ exclusion rationale is missing from this harness's header"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
