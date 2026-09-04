#!/bin/bash
# spec-coverage v1.0 — SPEC/plan/tests requirement-ID coverage CHECKER (issue #102; ADR-0048).
#
# CONTRACT. This is a CHECKER: the exit code is the policy channel — unlike
# weakening-scan.sh at the same Step 5 → Step 6 gate, which is a REPORTER that always exits 0
# and signals through stdout. Do not copy one block's branching into the other.
#   exit 0  every declared ID covered, OR the SPEC declares no IDs (backward compatibility)
#   exit 1  at least one declared ID uncovered           stdout: UNCOVERED<TAB>R-NN<TAB>plan|tests|plan,tests
#                                                                 OR UNSCOPED<TAB>R-NN<TAB><scope-size> — the
#                                                                 id is mentioned in a discovered test file
#                                                                 that CLAIMS THIS FEATURE but that the
#                                                                 --plan does not name (ADR-0138 §D1/§D3,
#                                                                 issue #312; population corrected by
#                                                                 ADR-0157, issue #487); a different remedy,
#                                                                 the SAME exit, no new code
#
# THE SCOPE FILTER IS A CONJUNCTION (ADR-0154): a discovered test file the plan names (half 1) must
# ALSO name this feature back — the plan's own basename or one of the ADR-NNNN ids the plan cites
# (half 2) — or it is dropped as a precedent citation, never re-admitted. stderr gains a SECOND
# empty-scope token, told apart from the first: SCOPE-EMPTY (unchanged) means the plan names no
# discovered test file at all and falls back to the unscoped population; SCOPE-NO-BACKREF (new)
# means the plan names one or more discovered test files and NONE names this feature back — a
# finding, not a vacuity, so it does NOT fall back; the scope stays empty. No new exit code, no new
# stdout token — the affected ids report their ordinary UNSCOPED verdict either way.
#   exit 2  invalid invocation, unreadable file           stdout: nothing
#   exit 3  structural error in the SPEC or the plan       stdout: DUPLICATE / MALFORMED / ORPHAN lines
#                                                                 OR STALE-WAIVER<TAB>R-NN — a (no-test: …)
#                                                                 exemption whose id IS found in the scoped
#                                                                 test set (ADR-0138 §D4, issue #312, Task 5)
#
# TWO MORE POPULATIONS ARE BOUNDED BY OWNERSHIP (ADR-0157, issue #487). ADR-0154's half 2 applies to
# the SCOPED set alone, so the two questions asked of the UNFILTERED discovered population — "is this
# id mentioned anywhere?" (UNSCOPED vs UNCOVERED) and "what do we fall back to when the plan names no
# test file?" (SCOPE-EMPTY) — were both answered by a population that holds every OTHER feature's
# tests. Requirement ids restart per feature, so a stranger's `R-13` mislabelled an untested id as
# UNSCOPED in the first case and as COVERED in the second. Both now read the OWNED population: the
# discovered files that claim this feature, by $OWN_RE (its own key set, and the measurement that
# separates it from half 2's is at its definition). A third stderr empty-scope token follows,
# SCOPE-EMPTY-OWNED — the plan names no discovered test file AND some file claims this feature, so the
# fallback narrows to those instead of to everything. SCOPE-EMPTY keeps its name and its
# full-population fallback for the case where nothing claims this feature at all.
#
# THE ADR-NNNN BOUNDARY (ADR-0048 §D2), THE LOAD-BEARING DETAIL.
# `R-[0-9][0-9]` alone matches 30+ of the 34 SPECs in this repository, every hit coming from the
# letter run inside `ADR-0016`, `ADR-0047`, and so on. The token regex used everywhere in this
# script for TOKEN MENTIONS (plan citations, test mentions, ORPHAN extraction) is anchored on
# BOTH sides: (^|[^A-Za-z0-9_])R-[0-9][0-9]([^0-9]|$). Either anchor alone would clear ADR-NNNN;
# both are present because PR-01, VAR-01 and ISSUE-R-013 are each defeated by exactly one of them
# and not the other. DECLARATION (the ID at the start of a success-criteria checklist item) uses a
# narrower, position-based rule instead of this scan-anywhere regex — see D1 below.
#
# THE SILENT NO-IDS PATH (ADR-0048 §D7/§D8) IS DELIBERATE, not an oversight.
# A SPEC that declares zero requirement IDs produces NO output on either stream and exits 0. Not
# "0 IDs, OK" — nothing at all. This is what lets all 34 pre-existing SPECs (plus this feature's
# own SPEC, which mentions R-01/R-02 in prose but declares neither — position matters, see D1)
# keep passing without a single edit. This divergence from secret-scan.sh's "the summary always
# goes to stderr, on every run" convention is deliberate: a per-run warning on the universal normal
# case is how a check trains its readers to ignore it.
#
# D1 — DECLARATION vs MENTION. An ID is DECLARED only when it is the FIRST token of a checklist
# item's text (after the "- [ ] " / "- [x] " marker) inside a recognized section (Success criteria
# / Acceptance criteria / Definition of done, matched case-insensitively at ## or deeper, ending at
# the next line at heading level 1 or 2). A checklist item that merely MENTIONS an ID mid-sentence
# (e.g. this feature's own SPEC, whose "A SPEC with `R-01`,`R-02` and a plan covering only `R-01`"
# success criterion mentions two IDs mid-sentence) declares nothing. A well-formed ID at the start of a
# checklist item OUTSIDE every recognized section is the narrow escape hatch for a generator that
# emits IDs under an unrecognized heading: MALFORMED, exit 3 — never widened to "any R-NN anywhere"
# (that fires on prose, including this file's own header).
#
# D4 — `(no-test: <reason>)` (ADR-0138 §D4, issue #312, Task 5). A checklist item's own text may
# carry this exemption, matched on the SAME flattened text strip_emphasis()/strip_sep() already
# produce for the IDS_FILE column below (D1's parser) — no second parser, no third stripper
# (CLAUDE.md rule 6: a second answer to "what does this item say" is a defect, not a feature). It
# removes the id from the TEST axis only, both the scoped and unscoped halves; the PLAN axis still
# applies. Reason floor: >= 20 characters after the colon, else MALFORMED, exit 3. The reverse
# check (CLAUDE.md rule 9): an exempted id whose token IS found in the SCOPED test set anyway is a
# STALE-WAIVER, exit 3 — NOT auto-repaired, because deleting an author's prose clause is a
# different class of edit than ADR-0072's checkbox-marker repair.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="spec-coverage"
TAB=$(printf '\t')

# The plan-task predicate is LOADED, not restated (ADR-0069 §D2, issue #172). This file used to
# carry its own copy of heading_level/is_checklist_item/is_task_heading in each of its two awk
# programs — four definitions of two functions — and that duplication is what let three files
# drift into three different answers to "what is a plan task". Both programs below now compose
# with it via `awk -f <predicate> -f <program>`.
PREDICATE=$(cd "$(dirname "$0")" && pwd)/plan-task-predicate.awk
SPEC_PREDICATE=$(cd "$(dirname "$0")" && pwd)/spec-id-predicate.awk

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: spec-coverage.sh --spec <file> --plan <file> [--tests-root <dir>] [--list]

stdout (machine channel): COVERED / UNCOVERED / UNSCOPED / DUPLICATE / MALFORMED / ORPHAN / STALE-WAIVER,
TAB-separated. UNSCOPED and STALE-WAIVER: see the contract header at the top of this file.
stderr: one summary line per run, EXCEPT when the SPEC declares zero requirement IDs — that path
is silent on both streams (ADR-0048 §D7/§D8).
Exit: 0 covered (or no IDs) | 1 uncovered | 2 bad invocation | 3 structural error.
EOF
}

SPEC=""; PLAN=""; TROOT=""; DO_LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --spec)
      [ $# -ge 2 ] || { usage "--spec needs a file argument"; exit 2; }
      SPEC="$2"; shift 2 ;;
    --plan)
      [ $# -ge 2 ] || { usage "--plan needs a file argument"; exit 2; }
      PLAN="$2"; shift 2 ;;
    --tests-root)
      [ $# -ge 2 ] || { usage "--tests-root needs a directory argument"; exit 2; }
      TROOT="$2"; shift 2 ;;
    --list)
      DO_LIST=1; shift ;;
    *)
      usage "unknown argument: $1"; exit 2 ;;
  esac
done

[ -n "$SPEC" ] || { usage "--spec is required"; exit 2; }
[ -n "$PLAN" ] || { usage "--plan is required"; exit 2; }
[ -r "$SPEC" ] || { usage "cannot read --spec file: $SPEC"; exit 2; }
[ -r "$PLAN" ] || { usage "cannot read --plan file: $PLAN"; exit 2; }

TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

# count_re() shape copied from secret-scan.sh's own count_re() — never `grep -c X f || echo 0` (grep -c PRINTS 0
# AND EXITS 1 on no match, so the fallback also fires and the substitution yields the two-line
# string "0\n0", which breaks arithmetic on every clean run).
count_re() { _c=$(grep -c "$1" "$2" 2>/dev/null); printf '%s' "${_c:-0}"; }

IDS="$TMPD/ids.tsv";           : >"$IDS"
MALFORMED_IN="$TMPD/malformed_in.txt"; : >"$MALFORMED_IN"
OUTSIDE="$TMPD/outside.txt";   : >"$OUTSIDE"
NEARMISS="$TMPD/nearmiss.txt"; : >"$NEARMISS"
NOTEST="$TMPD/notest.txt";     : >"$NOTEST"

# --- SPEC parser: declaration extraction, malformed-in-section, out-of-section well-formed IDs ---
cat >"$TMPD/spec_parse.awk" <<'AWKEOF'
# heading_level() and is_checklist_item() come from plan-task-predicate.awk; is_spec_section_heading()
# and is_near_miss_bullet() from spec-id-predicate.awk. Both are loaded alongside this program — do
# not redefine any of them here (awk rejects a duplicate function definition). The section rule is
# shared with spec-normalize-ids.sh on purpose: a repair keyed on a different rule than the check
# would rewrite lines the check accepts, or miss the ones it rejects (ADR-0072 §D2).
# Separator stripping for --list text (ADR-0048 §D6): trim, strip ONE leading separator (em dash,
# en dash, or one of - : . )), trim again. Em/en dash are matched by literal sub() on the raw UTF-8
# bytes (octal escapes — \xNN is not POSIX-portable in awk string literals), never a bracket class
# (a 3-byte character inside [...] is not portable across BSD and GNU awk).
BEGIN { collecting = 0 }
{
  line = $0
  hl = heading_level(line)
  if (collecting && hl >= 1 && hl <= 2) collecting = 0
  if (is_spec_section_heading(line)) { collecting = 1; next }

  # NEAR-MISS (issue #171): a requirement declared as a plain bullet inside a recognised section.
  # Before ADR-0072 this line was examined by nothing — the parser only ever looked at checklist
  # items — so its token reached neither IDS nor MALFORMED nor OUTSIDE, DECL_N stayed 0, and the
  # whole SPEC took the silent no-IDs path. A SPEC declaring 17 requirements passed the gate.
  #
  # Site 2 of 3 (ADR-0122 §D4). A first prototype patched sites 1 and 3 only and produced the
  # worst reachable state: the repairer rewrote a bold plain bullet while the checker stayed
  # silent about it — repair without detection, the mirror image of the invariant this near-miss
  # branch exists to protect. strip_emphasis() here is what lets a bold plain bullet
  # (`- **R-01** — …`) be recognised as a near-miss at all. The match() is GUARDED: on no match it
  # must not write an empty line — an unguarded match() writes substr(nmt, 0, -1), an empty line,
  # which makes [ -s "$NEARMISS" ] true with no content and sets NEARMISS_FIRED=1 against an empty
  # STRUCT (the file is non-empty but every line is skipped by `[ -n "$id" ] || continue`).
  if (collecting && is_near_miss_bullet(line)) {
    nmt = line
    sub(/^[ \t]*[-*][ \t]+/, "", nmt)
    nmt = strip_emphasis(nmt)
    if (match(nmt, /^R-[0-9][0-9]/))
      printf "%s\n", substr(nmt, RSTART, RLENGTH) >> NEARMISS_FILE
    next
  }

  if (is_checklist_item(line)) {
    txt = strip_emphasis(item_text(line))
    if (match(txt, /^[Rr]-[0-9][0-9A-Za-z]*/)) {
      tok = substr(txt, RSTART, RLENGTH)
      strict_ok = (tok ~ /^R-[0-9][0-9]$/)
      if (collecting) {
        if (strict_ok) {
          rest = substr(txt, RLENGTH + 1)
          rest = strip_emphasis(rest)
          rest = strip_sep(rest)
          # D4 (ADR-0138 §D4, issue #312, Task 5): search REST — the SAME text just produced for
          # the IDS_FILE column two lines up — for a `(no-test: <reason>)` clause. tolower() only
          # supplies the case-fold CLAUDE.md rule 3 requires; a bold/backtick wrap around the WHOLE
          # clause (RX3) needs no further stripping to be FOUND, because the marker is located by a
          # substring search on "(no-test:" that skips over any decoration run on either side of
          # it, and the reason is bounded by the next ")", which sits INSIDE any trailing
          # decoration too.
          is_notest = 0; notest_ok = 1
          low = tolower(rest)
          if (match(low, /\(no-test:/)) {
            is_notest = 1
            after = substr(rest, RSTART + RLENGTH)
            reason = after
            if (match(after, /\)/)) reason = substr(after, 1, RSTART - 1)
            reason = strip_sep(reason)
            notest_ok = (length(reason) >= 20)
          }
          if (is_notest && !notest_ok) {
            # Reason floor unmet (RX4) — MALFORMED, exit 3, the SAME channel as every other
            # structural defect below. The id is NOT written to IDS_FILE: like every other
            # malformed declaration in this file, a defective one never reaches the coverage loop.
            printf "%s\n", tok >> MALFORMED_FILE
          } else {
            if (is_notest) printf "%s\n", tok >> NOTEST_FILE
            printf "%s\t%s\n", tok, rest >> IDS_FILE
          }
        } else {
          printf "%s\n", tok >> MALFORMED_FILE
        }
      } else {
        if (strict_ok) printf "%s\n", tok >> OUTSIDE_FILE
      }
    }
  }
}
AWKEOF

awk -v IDS_FILE="$IDS" -v MALFORMED_FILE="$MALFORMED_IN" -v OUTSIDE_FILE="$OUTSIDE" \
    -v NEARMISS_FILE="$NEARMISS" -v NOTEST_FILE="$NOTEST" \
    -f "$PREDICATE" -f "$SPEC_PREDICATE" -f "$TMPD/spec_parse.awk" "$SPEC"

# --- structural error accumulation ---
STRUCT="$TMPD/structural.out"; : >"$STRUCT"
GUARD_FIRED=0

if [ -s "$MALFORMED_IN" ]; then
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    printf 'MALFORMED\t%s\n' "$tok" >>"$STRUCT"
  done <"$MALFORMED_IN"
fi

DECL_N=$(count_re . "$IDS")
if [ "$DECL_N" -eq 0 ] && [ -s "$OUTSIDE" ]; then
  sort -u "$OUTSIDE" | while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf 'MALFORMED\t%s\n' "$id" >>"$STRUCT"
  done
  GUARD_FIRED=1
fi

# The same guard, on the other axis (ADR-0072 §D2, issue #171). Above: well-formed ids, right form,
# wrong PLACE (outside every recognised section). Here: well-formed ids, right place, wrong FORM
# (a plain bullet instead of a checklist item). Both mean the SPEC declares requirements the
# checker cannot read, and both must break the silent no-IDs path rather than take it.
# Distinguished on stderr, not by a new stdout token — the caller's contract is unchanged, and
# GUARD_FIRED vs NEARMISS_FIRED is what selects the sentence that names the actual cause.
#
# NOT conditioned on DECL_N, unlike the guard above, and the asymmetry is deliberate. A well-formed
# id outside every recognised section is only evidence of a problem when nothing was declared —
# otherwise it is most likely prose elsewhere in the document. A plain bullet INSIDE a recognised
# requirements section has no innocent reading. The MIXED spec is in fact the worse case, because
# it is only PARTIALLY silent: some requirements are gated and some vanish. Costs the corpus
# nothing — RN13b sweeps all 35 SPECs and none is affected.
NEARMISS_FIRED=0
if [ -s "$NEARMISS" ]; then
  sort -u "$NEARMISS" | while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf 'MALFORMED\t%s\n' "$id" >>"$STRUCT"
  done
  NEARMISS_FIRED=1
fi

DUPS="$TMPD/dups.txt"
cut -f1 "$IDS" 2>/dev/null | sort | uniq -d >"$DUPS"
if [ -s "$DUPS" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf 'DUPLICATE\t%s\n' "$id" >>"$STRUCT"
  done <"$DUPS"
fi

# --- plan task-line token extraction (used by ORPHAN and by plan coverage below) ---
PLAN_TOKENS_RAW="$TMPD/plan_tokens_raw.txt"; : >"$PLAN_TOKENS_RAW"
cat >"$TMPD/plan_parse.awk" <<'AWKEOF'
# heading_level(), is_checklist_item(), is_task_heading() and is_task_line() come from
# plan-task-predicate.awk, loaded alongside this program — do not redefine them here.
function extract_tokens(l,    i, p, pos, cb, leftok, d1, d2, after, rightok, tok) {
  i = 1
  while (1) {
    p = index(substr(l, i), "R-")
    if (p == 0) break
    pos = i + p - 1
    if (pos == 1) leftok = 1
    else {
      cb = substr(l, pos - 1, 1)
      leftok = (cb !~ /[A-Za-z0-9_]/)
    }
    d1 = substr(l, pos + 2, 1)
    d2 = substr(l, pos + 3, 1)
    if (leftok && d1 ~ /[0-9]/ && d2 ~ /[0-9]/) {
      after = substr(l, pos + 4, 1)
      rightok = (after == "" || after !~ /[0-9]/)
      if (rightok) {
        tok = substr(l, pos, 4)
        print tok >> TOKENS_FILE
      }
    }
    i = pos + 2
  }
}
{
  if (is_task_line($0)) extract_tokens($0)
}
AWKEOF
awk -v TOKENS_FILE="$PLAN_TOKENS_RAW" -f "$PREDICATE" -f "$TMPD/plan_parse.awk" "$PLAN"

PLAN_TOKENS="$TMPD/plan_tokens.txt"
sort -u "$PLAN_TOKENS_RAW" >"$PLAN_TOKENS" 2>/dev/null || : >"$PLAN_TOKENS"

IDS_ONLY="$TMPD/ids_only.txt"
cut -f1 "$IDS" 2>/dev/null | sort -u >"$IDS_ONLY"

# ORPHAN: a token cited on a plan task line that the SPEC does not declare. Skipped in --list mode
# — the SPEC's plan content is not examined at all there (ADR-0048 §D6: "--list does not require
# --plan to be coverage-checked but still requires it to be readable — one argument contract").
if [ "$DO_LIST" -ne 1 ] && [ -s "$PLAN_TOKENS" ]; then
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    if ! grep -qxF "$tok" "$IDS_ONLY" 2>/dev/null; then
      printf 'ORPHAN\t%s\n' "$tok" >>"$STRUCT"
    fi
  done <"$PLAN_TOKENS"
fi

if [ -s "$STRUCT" ]; then
  cat "$STRUCT"
  if [ "$NEARMISS_FIRED" -eq 1 ]; then
    printf '%s: requirement ids are declared as plain bullets, not checklist items — the checker reads only `- [ ] R-NN …`. Repair with: spec-normalize-ids.sh --spec %s --apply\n' "$SELF" "$SPEC" >&2
  elif [ "$GUARD_FIRED" -eq 1 ]; then
    printf '%s: a well-formed ID was found outside every recognized section — recognized headings are: Success criteria, Acceptance criteria, Definition of done\n' "$SELF" >&2
  fi
  exit 3
fi

# --- the silent no-IDs path (ADR-0048 §D7/§D8), first and explicit: no output on either stream ---
if [ "$DECL_N" -eq 0 ]; then
  exit 0
fi

if [ "$DO_LIST" -eq 1 ]; then
  while IFS="$TAB" read -r id text; do
    [ -n "$id" ] || continue
    printf '%s\t%s\n' "$id" "$text"
  done <"$IDS"
  exit 0
fi

# --- test discovery (ADR-0048 §D3): basename predicate, then an EXPLICIT, separate .md rejection
# step so the exclusion is visible rather than implied by the pattern list. Without it a project
# whose test-file basenames happen to end in .md would be silently exempt from nothing today, but
# the exclusion is what stops a SPEC (docs/specs/x.spec.md) from discovering and covering itself. ---
TESTFILES="$TMPD/testfiles.txt"; : >"$TESTFILES"
DISCOVERED_N=0
if [ -n "$TROOT" ]; then
  CANDIDATES="$TMPD/candidates.txt"; : >"$CANDIDATES"
  find "$TROOT" -type f 2>/dev/null | while IFS= read -r f; do
    case "$f" in
      */.git/*) continue ;;
    esac
    bn="${f##*/}"
    case "$bn" in
      *.test.*|test_*|*_test.*|*Test.*|*Tests.*|test-*.sh|run-tests.sh|*.spec.js|*.spec.ts|*.spec.tsx|*.spec.jsx)
        printf '%s\n' "$f" ;;
    esac
  done >"$CANDIDATES"
  # Explicit .md exclusion — a separate step on purpose, not folded into the pattern list above.
  while IFS= read -r f; do
    case "$f" in
      *.md) continue ;;
    esac
    printf '%s\n' "$f" >>"$TESTFILES"
  done <"$CANDIDATES"
  DISCOVERED_N=$(count_re . "$TESTFILES")
fi

# --- back-reference key set (ADR-0154 §D1). Built ONCE per run, BEFORE the scope loop below: the
# plan's own basename (WITH its .md extension, escaped exactly like the basename half below escapes
# its own candidate) OR every ADR-NNNN id $PLAN cites — exactly four digits, found with the SAME
# both-sides-anchored token scan this file already uses for R-NN (left (^|[^A-Za-z0-9_]), right
# ([^0-9]|$)) — not read from a designated header line. De-duplicated, assembled into ONE ERE
# alternation anchored (^|[^A-Za-z0-9_])(…)([^A-Za-z0-9_]|$) — the SAME word-boundary anchor pair the
# basename half below already uses. This is what half 2 of the scope filter tests a candidate file's
# OWN text against — see the disclosure at the filter's own site below.
PLAN_BN="${PLAN##*/}"
PLAN_BN_ESC=$(printf '%s' "$PLAN_BN" | sed 's/[][\.^$*+?(){}|]/\\&/g')
BACKREF_ADRS="$TMPD/backref_adrs.txt"; : >"$BACKREF_ADRS"
cat >"$TMPD/backref_adr_scan.awk" <<'AWKEOF'
# Same scan-anywhere shape as extract_tokens() below for R-NN, applied to ADR-NNNN (four digits, not
# two) and to the WHOLE $PLAN — not gated by is_task_line(), because half 2's key set is drawn from
# every ADR citation in the plan's prose, not only its task lines (ADR-0154 §D1).
function extract_adr_ids(l,    i, p, pos, cb, leftok, d1, d2, d3, d4, after, rightok) {
  i = 1
  while (1) {
    p = index(substr(l, i), "ADR-")
    if (p == 0) break
    pos = i + p - 1
    if (pos == 1) leftok = 1
    else {
      cb = substr(l, pos - 1, 1)
      leftok = (cb !~ /[A-Za-z0-9_]/)
    }
    d1 = substr(l, pos + 4, 1); d2 = substr(l, pos + 5, 1)
    d3 = substr(l, pos + 6, 1); d4 = substr(l, pos + 7, 1)
    if (leftok && d1 ~ /[0-9]/ && d2 ~ /[0-9]/ && d3 ~ /[0-9]/ && d4 ~ /[0-9]/) {
      after = substr(l, pos + 8, 1)
      rightok = (after == "" || after !~ /[0-9]/)
      if (rightok) print substr(l, pos, 8) >> ADR_FILE
    }
    i = pos + 4
  }
}
{ extract_adr_ids($0) }
AWKEOF
awk -v ADR_FILE="$BACKREF_ADRS" -f "$TMPD/backref_adr_scan.awk" "$PLAN"
BACKREF_ADRS_UNIQ="$TMPD/backref_adrs_uniq.txt"
sort -u "$BACKREF_ADRS" >"$BACKREF_ADRS_UNIQ" 2>/dev/null || : >"$BACKREF_ADRS_UNIQ"

BACKREF_KEYS="$PLAN_BN_ESC"
if [ -s "$BACKREF_ADRS_UNIQ" ]; then
  while IFS= read -r _adr; do
    [ -n "$_adr" ] || continue
    BACKREF_KEYS="${BACKREF_KEYS}|${_adr}"
  done <"$BACKREF_ADRS_UNIQ"
fi
BACKREF_RE="(^|[^A-Za-z0-9_])(${BACKREF_KEYS})([^A-Za-z0-9_]|\$)"

# --- the OWNERSHIP key set (ADR-0157 §D1, issue #487) — a SECOND key set, for a SECOND question, and
# the measurement is why it is not the one above.
#
# $BACKREF_RE answers "may this plan-named file be counted as coverage?" and it is a CONJUNCT: half 1
# (the plan names the file) does the discriminating, so half 2 can afford to be generous. The question
# below has no conjunct to lean on — "does this file, which the plan does NOT name, nevertheless
# belong to this feature?" — so its key set must carry the discrimination alone.
#
# MEASURED on this repository's 15-pair corpus (98 discovered test files, 2026-08-19), which is what
# ruled out reusing $BACKREF_RE here: it admits 39-61 files per feature, a median of 47 of 98, because
# harnesses identify themselves by ADR id and a plan cites its precedents' ADRs as well as its own.
# Half the repository "names any feature back". The plan basename ALONE is the opposite failure: 6
# hits across all 15 pairs, since a harness essentially never cites its plan's filename. The feature's
# own ISSUE NUMBER as a `#N` token lands between them at 1-11 files per feature, and it is the token
# the house form already uses ("issue #404") to say which feature a harness belongs to.
#
# Derived from the filenames, never from a header line: the plan's `YYYY-MM-DD-<N>-` prefix first,
# then the SPEC's leading `<N>-`. Absent from both, the key set is the plan basename alone — the
# narrow direction, and the fallback below declares what that costs.
OWN_KEYS="$PLAN_BN_ESC"
OWN_NUM=$(printf '%s' "$PLAN_BN" | sed -n 's/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-\([0-9][0-9]*\)-.*/\1/p')
if [ -z "$OWN_NUM" ]; then
  OWN_NUM=$(printf '%s' "${SPEC##*/}" | sed -n 's/^\([0-9][0-9]*\)-.*/\1/p')
fi
[ -n "$OWN_NUM" ] && OWN_KEYS="${OWN_KEYS}|#${OWN_NUM}"
OWN_RE="(^|[^A-Za-z0-9_])(${OWN_KEYS})([^A-Za-z0-9_]|\$)"

# --- VCS-035 — a NEGATIVE, LINE-granular filter inside grep_boundary_test() below. The file-level
# scope classification above ($OWN_RE, $FOREIGN_CLAIMED, $TESTFILES_UNCLAIMED) is UNCHANGED — a file
# is still admitted to scope as a WHOLE (ADR-0138/0154/0157). What changes is which MATCHING LINE
# inside an in-scope file may be read as coverage of THIS feature's R-NN: a file that legitimately
# belongs to this feature can still carry an isolated comment about a DIFFERENT feature (its own
# issue number, or, for an issue-less feature, its own ADR — measured 2026-08-24: 63% of discovered
# test files cite more than one feature's `#<n>`).
#
# Token of claim on a line: "#<n>" (the same marker used for file-level classification above) OR
# "ADR-NNNN" — an issue-less feature has no "#<n>" to sign a line with, and its only possible
# signature in a comment is its own ADR.
CLAIM_LINE_RE='(^|[^A-Za-z0-9_])(#[0-9][0-9]*|ADR-[0-9][0-9][0-9][0-9])([^0-9]|$)'

# Own-key set, EXTENDED, for the line filter ONLY: on top of $OWN_KEYS (plan basename, #<issue>),
# also every ADR-NNNN THIS FEATURE'S OWN PLAN cites ($BACKREF_ADRS_UNIQ, already computed above for
# $BACKREF_RE). Deliberately a SEPARATE variable from $OWN_RE: $OWN_RE governs the file-level
# classification above and must NOT be widened there — measured (comment above $OWN_KEYS) that an
# ADR-based key set there would admit 39-61 files per feature instead of 1-11. $OWN_LINE_RE is
# consumed ONLY by grep_boundary_test() below.
OWN_LINE_KEYS="$OWN_KEYS"
if [ -s "$BACKREF_ADRS_UNIQ" ]; then
  while IFS= read -r _own_adr; do
    [ -n "$_own_adr" ] || continue
    OWN_LINE_KEYS="${OWN_LINE_KEYS}|${_own_adr}"
  done <"$BACKREF_ADRS_UNIQ"
fi
OWN_LINE_RE="(^|[^A-Za-z0-9_])(${OWN_LINE_KEYS})([^A-Za-z0-9_]|\$)"

# --- scope filter (ADR-0138 §D1-§D3, issue #312; ADR-0154 §D1 narrows it further): the test axis is
# narrowed to the test files the PLAN itself names, not the whole discovered population above.
#
# THE DEVIATION FROM SPEC OBJECTIVE 2, DISCLOSED HERE (CLAUDE.md rule 12 — a later assertion about
# this filter must anchor on the TESTFILES_SCOPED code below, never on this prose alone, which a
# needle would also match). The corpus measurement (ADR-0138 Findings 1-3) found that requiring an
# R-NN mention to sit on an assertion line rather than a comment line is a no-op on the pre-existing
# repo-wide scan (0 of 199 declared ids flip) and a regression once scoped: of the 93 ids genuinely
# covered by their own feature's tests, 49 (53%) have every mention on a comment line, and issue
# #404's 45 in-scope mentions are ALL comments (45 of 45) — the comment header is this harness's
# idiomatic requirement-to-assertion map. No comment-versus-assertion distinction is implemented
# here, by decision. What tightens the gate instead is SCOPE: a discovered test file counts only
# when its own basename is a whole token somewhere in $PLAN — AND (ADR-0154 §D1, half 2 below) its
# own text names this feature back. Half 2 is a CONJUNCT on the candidates half 1 already admitted,
# never a second, independent discovery rule (CLAUDE.md rule 6, ADR-0086) — a file half 1 rejects is
# never reached by half 2 at all, and $TESTFILES_SCOPED is still the ONE definition of "in scope".
#
# ONE definition of "what is a test file" (CLAUDE.md rule 6, ADR-0086): this FILTERS $TESTFILES, it
# never re-derives the discovery predicate above. The .md exclusion stays closed for free — $TESTFILES
# is already post-exclusion, so no .md can enter scope through this filter (RS5).
TESTFILES_SCOPED="$TMPD/testfiles_scoped.txt"; : >"$TESTFILES_SCOPED"
HALF2_DROPPED="$TMPD/half2_dropped.txt"; : >"$HALF2_DROPPED"
# THE OWNED POPULATION (ADR-0157 §D1, issue #487) — the discovered files that claim THIS feature by
# $OWN_RE, whether or not the plan names them. It is what tells UNSCOPED from UNCOVERED below, and it
# exists because asking that question of the unfiltered population was rule 18 in its second form: a
# requirement-id namespace restarts per feature, so a STRANGER'S committed `R-13` made this feature's
# untested `R-13` report UNSCOPED ("name the file in your plan") instead of UNCOVERED ("write the
# test") — measured in the field, where the only remedies left were renumbering a released SPEC or
# writing a waiver for a requirement that was simply untested. Measured again on this repository's own
# corpus afterwards: the class is here too, and the count is in ADR-0157.
TESTFILES_OWNED="$TMPD/testfiles_owned.txt"; : >"$TESTFILES_OWNED"
HALF1_FILES="$TMPD/half1_files.txt"; : >"$HALF1_FILES"
FOREIGN_CLAIMED="$TMPD/foreign_claimed.txt"; : >"$FOREIGN_CLAIMED"
TESTFILES_UNCLAIMED="$TMPD/testfiles_unclaimed.txt"; : >"$TESTFILES_UNCLAIMED"
# Declared out here, beside the populations they are derived from, because the summary line and the
# UNSCOPED predicate read them on EVERY path — including a run with no --tests-root, where the loop
# that fills them never executes. Under `set -u` a declaration left inside that loop is a fatal error
# on exactly the invocation that skips it.
UNSCOPED_POP="$TMPD/unscoped_pop.txt"; : >"$UNSCOPED_POP"
FOREIGN_CLAIMED_N=0
HALF1_N=0
if [ -n "$TROOT" ] && [ -s "$TESTFILES" ]; then
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    _bn="${_f##*/}"
    # The ownership test, evaluated for EVERY discovered file — including the ones half 1 rejects,
    # which is the whole point: those are where an unlisted test of this feature hides. $BACKREF_RE
    # (half 2) is evaluated where it always was, inside the half-1 branch below, and neither predicate
    # reads the other's population.
    #
    # THREE STATES, NOT TWO, and the third is why this is not a default (ADR-0157 §D1). A file that
    # does not claim THIS feature may still be nobody's: the original UNSCOPED state (ADR-0138 §D3)
    # was "mentioned in the discovered population but not in a file the plan names", and its remedy
    # — cite the file from your plan — is right for a test that claims nothing. Turning every such
    # file into evidence of UNCOVERED would have been a guess dressed as a rule; two assertions
    # written for ADR-0138 (RS1, RX6) said so before this comment was written.
    #   owned           carries $OWN_RE           -> in the unscoped-question population
    #   foreign-claimed carries some OTHER #<n>    -> OUT of it: its R-NN belongs to that feature's
    #                                                own numbering, which restarts at R-01
    #   unclaimed       carries no #<n> at all     -> in it, unchanged from ADR-0138
    # The claim token is the bare `#<digits>` the house form already writes ("issue #404", "(#487)").
    # BOUND, stated rather than discovered later: a six-digit colour literal (`#404040`) reads as a
    # foreign claim. It excludes that file from the population, which makes a verdict STRICTER, never
    # laxer, and a colour literal in a test file is not a requirement-id mention either way.
    if grep -qE "$OWN_RE" "$_f" 2>/dev/null; then
      printf '%s\n' "$_f" >>"$TESTFILES_OWNED"
    elif grep -qE "(^|[^A-Za-z0-9_])#[0-9][0-9]*([^0-9]|\$)" "$_f" 2>/dev/null; then
      printf '%s\n' "$_f" >>"$FOREIGN_CLAIMED"
    else
      printf '%s\n' "$_f" >>"$TESTFILES_UNCLAIMED"
    fi
    # Whole-token basename match, both sides anchored the SAME way the R-NN token regex is
    # (grep_boundary_test() below): (^|[^A-Za-z0-9_]) … ([^A-Za-z0-9_]|$). A basename contains "."
    # and "-", so a bare `grep -F` on it also matches a longer basename that merely CONTAINS it as a
    # substring (RS1's beta.test.sh would then wrongly scope-in on an unrelated alpha.test.sh
    # mention) — the basename is regex-escaped and searched with the anchor pair instead.
    _esc=$(printf '%s' "$_bn" | sed 's/[][\.^$*+?(){}|]/\\&/g')
    if grep -qE "(^|[^A-Za-z0-9_])${_esc}([^A-Za-z0-9_]|\$)" "$PLAN" 2>/dev/null; then
      HALF1_N=$((HALF1_N + 1))
      # Half 1's members are recorded as their own list, not recovered later by concatenating
      # $TESTFILES_SCOPED and $HALF2_DROPPED: the fallback below OVERWRITES $TESTFILES_SCOPED, so a
      # union taken after it would silently pick up the fallback population instead of half 1.
      printf '%s\n' "$_f" >>"$HALF1_FILES"
      # Half 2 (ADR-0154 §D1): the file half 1 just admitted must ALSO name this feature back — its
      # OWN text names the plan's basename or one of the ADR ids the plan cites ($BACKREF_RE, built
      # above). A precedent citation (a harness the plan names for an unrelated reason) fails this
      # and is dropped — it was discovered and it passed half 1, it just does not claim this feature.
      if grep -qE "$BACKREF_RE" "$_f" 2>/dev/null; then
        printf '%s\n' "$_f" >>"$TESTFILES_SCOPED"
      else
        printf '%s\n' "$_f" >>"$HALF2_DROPPED"
      fi
    fi
  done <"$TESTFILES"
  # THE POPULATION THE UNSCOPED-VS-UNCOVERED QUESTION IS ASKED OF (ADR-0157 §D1): half 1 UNION owned.
  # Not "owned" alone, which is where this fix first went and where six assertions caught it. The two
  # members answer the same question from opposite ends, and either one alone loses a real state:
  #
  #   half 1 (the PLAN names the file) — ADR-0154 drops such a file from SCOPE when it does not name the
  #   feature back, and UNSCOPED's remedy, "add the plan basename or a cited ADR id to it", is exactly
  #   right for it. Reading only the owned population would tell that author to write a test that is
  #   already written, two lines from where the plan points.
  #
  #   owned ($OWN_RE) — a test of this feature the plan simply never names. Half 1 cannot see it.
  #
  #   unclaimed — a test file that claims no feature at all. ADR-0138's state, kept as it was.
  #
  # What falls OUTSIDE the union is the whole defect, and it is identified by POSITIVE evidence rather
  # than by absence: a file that the plan does not name, that does not claim this feature, and that DOES
  # claim another one. Its matching `R-13` belongs to that feature's numbering, which restarts at R-01
  # exactly like this one's.
  cat "$HALF1_FILES" "$TESTFILES_OWNED" "$TESTFILES_UNCLAIMED" 2>/dev/null | sort -u >"$UNSCOPED_POP"
  FOREIGN_CLAIMED_N=$(count_re . "$FOREIGN_CLAIMED")

  # D2 — the denominator guard (CLAUDE.md rule 7, ADR-0085), now TWO causes, told apart (ADR-0154
  # §D2). Zero MATCHES can be a correct scope (RS3: the id is absent everywhere); zero CANDIDATES out
  # of a non-empty discovered population is a broken derivation, and from outside the two look
  # identical. Fail open and visible, matching the gate's existing exit-2 philosophy (CLAUDE.md rule
  # 4) — never a silent wall of UNSCOPED lines.
  if [ ! -s "$TESTFILES_SCOPED" ]; then
    if [ "$HALF1_N" -gt 0 ]; then
      # SCOPE-NO-BACKREF (new, ADR-0154 §D2): half 1 matched one or more files and half 2 dropped
      # ALL of them. Nothing here is broken — the derivation resolved and its answer is that no file
      # the plan names claims this feature. A finding, not a vacuity: unlike SCOPE-EMPTY below, this
      # does NOT fall back — the scope stays empty and ids mentioned only in the dropped file(s)
      # report their ordinary UNSCOPED verdict.
      _dropped_bns=$(sed -n '1,3p' "$HALF2_DROPPED" 2>/dev/null | while IFS= read -r _d; do printf '%s ' "${_d##*/}"; done)
      _dropped_bns=${_dropped_bns% }
      if [ -s "$BACKREF_ADRS_UNIQ" ]; then
        _adr_list=$(tr '\n' ',' <"$BACKREF_ADRS_UNIQ" | sed 's/,$//; s/,/, /g')
        printf '%s: SCOPE-NO-BACKREF — the plan names %d discovered test file(s) but none names this feature back (tests-root=%s, %d file(s) discovered); dropped: %s; remedy: add %s or one of %s to one of them\n' \
          "$SELF" "$HALF1_N" "$TROOT" "$DISCOVERED_N" "$_dropped_bns" "$PLAN_BN" "$_adr_list" >&2
      else
        printf '%s: SCOPE-NO-BACKREF — the plan names %d discovered test file(s) but none names this feature back (tests-root=%s, %d file(s) discovered); dropped: %s; remedy: add %s to one of them\n' \
          "$SELF" "$HALF1_N" "$TROOT" "$DISCOVERED_N" "$_dropped_bns" "$PLAN_BN" >&2
      fi
    elif [ ! -s "$UNSCOPED_POP" ] && [ -s "$FOREIGN_CLAIMED" ]; then
      # SCOPE-FOREIGN-ONLY (ADR-0157 §D2, issue #487) — the plan names no discovered test file AND
      # every discovered file claims a DIFFERENT feature. This is the state the old unconditional
      # fallback got dangerously wrong: it copied the whole population into scope, so a stranger's
      # `R-13` reported COVERED. A false green — and unlike the mislabelled UNSCOPED, nobody reported
      # this one, because nothing looks at a green. A finding, not a vacuity, so it does NOT fall
      # back; the scope stays empty and the ids report UNCOVERED. Its own token, not a SCOPE-EMPTY
      # suffix: a token that is a PREFIX of another is indistinguishable to every `grep -q` already
      # written against the shorter one.
      printf '%s: SCOPE-FOREIGN-ONLY — the plan names no discovered test file and all %d discovered file(s) claim another feature; NOT falling back (tests-root=%s)\n' \
        "$SELF" "$FOREIGN_CLAIMED_N" "$TROOT" >&2
    else
      # SCOPE-EMPTY (ADR-0138 §D2) keeps its name, its exit path and its fallback. What ADR-0157
      # changes is WHICH population it falls back to: the files that could belong to this feature
      # (half 1, plus the ones claiming it, plus the ones claiming nobody) instead of every test file
      # in the tree. On a project where no file claims anything — the common case outside this
      # repository — the two are the same set, which is why no existing assertion moves.
      printf '%s: SCOPE-EMPTY — the plan names no discovered test file at all (tests-root=%s, %d file(s) discovered); falling back to the %d file(s) that could belong to this feature for this invocation\n' \
        "$SELF" "$TROOT" "$DISCOVERED_N" "$(count_re . "$UNSCOPED_POP")" >&2
      cat "$UNSCOPED_POP" >"$TESTFILES_SCOPED"
    fi
  fi
fi
SCOPE_N=$(count_re . "$TESTFILES_SCOPED")
HALF2_DROPPED_N=$(count_re . "$HALF2_DROPPED")
# The owned population's own count, on the summary line below rather than only inside a branch: zero
# of it with a non-empty discovered population is a legitimate state (a feature whose tests never name
# it) but it is also the state in which every id can only ever report UNCOVERED, so it must be
# readable without reproducing the run (CLAUDE.md rule 7's visibility half).
OWNED_N=$(count_re . "$TESTFILES_OWNED")
UNSCOPED_POP_N=$(count_re . "$UNSCOPED_POP")

# PERFORMANCE — a ONE-TIME, single-pass precompute of the two boundary predicates below, replacing
# what used to be two functions (grep_boundary_test / grep_boundary_test_claimed) that each forked
# `xargs -0 grep -hE "<id-anchored-pattern>"` over the WHOLE scoped/unscoped test-file population,
# called ONCE PER DECLARED ID inside the main loop below — O(ids x population) forks, measured as
# the dominant cost of a 3-15 minute Step 5 -> Step 6 gate on a real project. The MEANING of both
# predicates is UNCHANGED (see each population's own comment below); only how often the underlying
# scan runs. The main loop now reads $COVERED_IDS / $CLAIMED_IDS with the SAME `grep -qxF`
# fixed-string idiom this file already uses for $PLAN_TOKENS/$NOTEST.
#
# extract_tokens() — loaded as its own awk program below, composed the same way $PREDICATE is — is a
# COPY of plan_parse.awk's function of the same name above. It implements the exact scan-anywhere,
# exactly-two-digit R-NN shape that matches $IDS's own strict_ok predicate. Kept in lockstep by
# hand: a divergence here would silently disagree with what $IDS actually contains.
cat >"$TMPD/extract_tokens.awk" <<'AWKEOF'
function extract_tokens(l,    i, p, pos, cb, leftok, d1, d2, after, rightok, tok) {
  i = 1
  while (1) {
    p = index(substr(l, i), "R-")
    if (p == 0) break
    pos = i + p - 1
    if (pos == 1) leftok = 1
    else {
      cb = substr(l, pos - 1, 1)
      leftok = (cb !~ /[A-Za-z0-9_]/)
    }
    d1 = substr(l, pos + 2, 1)
    d2 = substr(l, pos + 3, 1)
    if (leftok && d1 ~ /[0-9]/ && d2 ~ /[0-9]/) {
      after = substr(l, pos + 4, 1)
      rightok = (after == "" || after !~ /[0-9]/)
      if (rightok) {
        tok = substr(l, pos, 4)
        print tok >> TOKENS_FILE
      }
    }
    i = pos + 2
  }
}
AWKEOF

COVERED_IDS="$TMPD/covered_ids.txt"; : >"$COVERED_IDS"
CLAIMED_IDS="$TMPD/claimed_ids.txt"; : >"$CLAIMED_IDS"
if [ -n "$TROOT" ]; then
  # COVERED_IDS (replaces grep_boundary_test()). A file is admitted to scope as a WHOLE
  # (ADR-0138/0154) but a single R-NN token inside it is not automatically this feature's
  # (VCS-035). A LINE qualifies as coverage evidence exactly when it carries no foreign-claim token
  # ($CLAIM_LINE_RE — "#<n>" or "ADR-NNNN") at all, OR it carries one AND also carries this
  # feature's own-key ($OWN_LINE_RE) on that SAME line — the exact OR of grep_boundary_test()'s two
  # former branches (a line carrying BOTH, the RZ2 shape: "carried over from issue #999, now this
  # feature's own harness, see <plan-basename>", qualifies: ownership beats a foreign claim at line
  # granularity exactly as it already does at file granularity), now evaluated once per LINE instead
  # of once per (line x id). A line carrying no claim token at all is KEPT unconditionally — the
  # ordinary case, 864 of 972 R-NN mentions in this repo (measured 2026-08-24), which is why a
  # same-line-STRICT design (require an own-key on every covering line) was rejected: it would have
  # discarded that majority. Every id-shaped token on a qualifying line is covered; a line that does
  # not qualify contributes nothing — the id may still be covered via a different, qualifying line
  # elsewhere in scope.
  if [ -s "$TESTFILES_SCOPED" ]; then
    COVERED_IDS_RAW="$TMPD/covered_ids_raw.txt"; : >"$COVERED_IDS_RAW"
    # $CLAIM_LINE_RE/$OWN_LINE_RE reach awk via ENVIRON, NOT `-v`: $OWN_LINE_RE can carry a
    # backslash-escaped literal (PLAN_BN_ESC's `\.` etc, folded into its key set) and POSIX
    # `-v var=value` processes backslash escapes the same way a string literal does — measured on
    # this machine's BWK awk, `-v RE='a\.b'` silently drops the backslash and the `.` becomes a
    # wildcard, not a literal dot. `ENVIRON[]` is a plain, unprocessed copy of the value.
    cat >"$TMPD/covered_ids_scan.awk" <<'AWKEOF'
{
  is_claim = ($0 ~ ENVIRON["CLAIM_LINE_RE"])
  if (!is_claim || (is_claim && ($0 ~ ENVIRON["OWN_LINE_RE"]))) extract_tokens($0)
}
AWKEOF
    tr '\n' '\0' <"$TESTFILES_SCOPED" \
      | CLAIM_LINE_RE="$CLAIM_LINE_RE" OWN_LINE_RE="$OWN_LINE_RE" \
        xargs -0 awk -v TOKENS_FILE="$COVERED_IDS_RAW" \
          -f "$TMPD/extract_tokens.awk" -f "$TMPD/covered_ids_scan.awk" 2>/dev/null
    sort -u "$COVERED_IDS_RAW" >"$COVERED_IDS" 2>/dev/null || : >"$COVERED_IDS"
  fi

  # CLAIMED_IDS (replaces grep_boundary_test_claimed()) — reads $UNSCOPED_POP, the half-1 ∪ owned
  # union built above: every discovered file that either the plan names or that claims this
  # feature. Used only to tell UNCOVERED apart from UNSCOPED — ADR-0138 §D3's two-row table, with
  # ADR-0157 §D1's correction to WHICH population that question is asked of.
  #
  # UNFILTERED, deliberately — VCS-035 does NOT apply here, unchanged from the function this
  # replaces. Two reasons. First, membership: RZ3 pins that half-1 (the plan names the file) is
  # UNCONDITIONAL — filtering here would drop a file from $UNSCOPED_POP for a line-level reason,
  # which changes MEMBERSHIP, not just a verdict, and breaks that guarantee. Second, harm: this
  # predicate only decides UNSCOPED vs. UNCOVERED, and both already mean "not proven" — there is no
  # false-COVERED here to correct, so filtering buys no correctness on the axis VCS-035 exists to
  # fix, only a smaller blast radius to manage for no gain.
  if [ -s "$UNSCOPED_POP" ]; then
    CLAIMED_IDS_RAW="$TMPD/claimed_ids_raw.txt"; : >"$CLAIMED_IDS_RAW"
    cat >"$TMPD/claimed_ids_scan.awk" <<'AWKEOF'
{ extract_tokens($0) }
AWKEOF
    tr '\n' '\0' <"$UNSCOPED_POP" \
      | xargs -0 awk -v TOKENS_FILE="$CLAIMED_IDS_RAW" \
          -f "$TMPD/extract_tokens.awk" -f "$TMPD/claimed_ids_scan.awk" 2>/dev/null
    sort -u "$CLAIMED_IDS_RAW" >"$CLAIMED_IDS" 2>/dev/null || : >"$CLAIMED_IDS"
  fi
fi

OUT="$TMPD/out.txt"; : >"$OUT"
STALEWAIVER="$TMPD/stalewaiver.txt"; : >"$STALEWAIVER"
COV_N=0; UNCOV_N=0; UNSCOPED_N=0
while IFS="$TAB" read -r id _text; do
  [ -n "$id" ] || continue
  miss=""
  if grep -qxF "$id" "$PLAN_TOKENS" 2>/dev/null; then
    :
  else
    miss="plan"
  fi
  # D4 (ADR-0138 §D4, issue #312, Task 5) — a `(no-test: ...)` exemption removes this id from the
  # TEST axis entirely, both halves (RX1). It NEVER touches `miss` above — the PLAN axis still
  # applies (RX2), which is why this branch COMPOSES rather than `continue`s the way UNSCOPED does
  # below: an exempted id that is ALSO plan-missing must still surface
  # `UNCOVERED<TAB>R-NN<TAB>plan`, never read as covered by omission.
  if grep -qxF "$id" "$NOTEST" 2>/dev/null; then
    if [ -n "$TROOT" ] && grep -qxF "$id" "$COVERED_IDS" 2>/dev/null; then
      # The reverse check (CLAUDE.md rule 9, ADR-0081/0084, RX5) — an exemption whose id IS found
      # in the SCOPED test set protects nothing; it is a stale waiver, not a documentation
      # requirement. Structural, exit 3, and deliberately NOT auto-repaired (ADR-0072's
      # self-repair is licensed only because adding a checkbox marker changes no content —
      # deleting an author's prose clause is a different class of edit).
      printf 'STALE-WAIVER\t%s\n' "$id" >>"$STALEWAIVER"
      continue
    fi
  elif [ -n "$TROOT" ]; then
    if grep -qxF "$id" "$COVERED_IDS" 2>/dev/null; then
      :
    elif grep -qxF "$id" "$CLAIMED_IDS" 2>/dev/null; then
      # D3: mentioned somewhere in the discovered population, but not in scope. A distinct token on
      # the SAME exit-1 channel (no new exit code) — the remedy differs from UNCOVERED's ("write a
      # test") because a test already exists; it just isn't cited from the file this feature wrote.
      printf 'UNSCOPED\t%s\t%s\n' "$id" "$SCOPE_N" >>"$OUT"
      UNSCOPED_N=$((UNSCOPED_N + 1))
      continue
    else
      if [ -n "$miss" ]; then miss="$miss,tests"; else miss="tests"; fi
    fi
  fi
  if [ -z "$miss" ]; then
    printf 'COVERED\t%s\n' "$id" >>"$OUT"
    COV_N=$((COV_N + 1))
  else
    printf 'UNCOVERED\t%s\t%s\n' "$id" "$miss" >>"$OUT"
    UNCOV_N=$((UNCOV_N + 1))
  fi
done <"$IDS"

# A stale waiver is a structural defect discovered only once test data exists, but it is reported
# like every other one (STRUCT above): its own lines only, exit 3, no COVERED/UNCOVERED/UNSCOPED
# bleed-through from the same run — the exit-3 stdout vocabulary stays exactly what the contract
# header names (ADR-0138 §D4).
if [ -s "$STALEWAIVER" ]; then
  cat "$STALEWAIVER"
  printf '%s: STALE-WAIVER — a (no-test: ...) exemption is stale: the id IS mentioned in a test file the plan scopes in, so the exemption no longer protects anything. Remedy: delete the (no-test: ...) clause from the SPEC (ADR-0138 §D4) — this is NOT auto-repaired.\n' "$SELF" >&2
  exit 3
fi

cat "$OUT"

TROOT_DESC="not-checked"
[ -n "$TROOT" ] && TROOT_DESC="$TROOT"
if [ -n "$TROOT" ]; then
  printf '%s: %d id(s) declared, %d covered, %d uncovered, %d unscoped, tests-root=%s, %d test file(s) discovered, %d in scope, %d dropped by back-reference filter (ADR-0154), %d claim this feature, %d in the unscoped-question population, %d claimed by another feature (ADR-0157)\n' \
    "$SELF" "$DECL_N" "$COV_N" "$UNCOV_N" "$UNSCOPED_N" "$TROOT_DESC" "$DISCOVERED_N" "$SCOPE_N" "$HALF2_DROPPED_N" "$OWNED_N" "$UNSCOPED_POP_N" "$FOREIGN_CLAIMED_N" >&2
else
  printf '%s: %d id(s) declared, %d covered, %d uncovered, tests-root=%s\n' \
    "$SELF" "$DECL_N" "$COV_N" "$UNCOV_N" "$TROOT_DESC" >&2
fi

if [ "$UNCOV_N" -gt 0 ] || [ "$UNSCOPED_N" -gt 0 ]; then
  exit 1
fi
exit 0
