#!/bin/bash
# spec-coverage v1.0 — SPEC/plan/tests requirement-ID coverage CHECKER (issue #102; ADR-0048).
#
# CONTRACT. This is a CHECKER: the exit code is the policy channel — unlike
# weakening-scan.sh at the same Step 5 → Step 6 gate, which is a REPORTER that always exits 0
# and signals through stdout. Do not copy one block's branching into the other.
#   exit 0  every declared ID covered, OR the SPEC declares no IDs (backward compatibility)
#   exit 1  at least one declared ID uncovered           stdout: UNCOVERED<TAB>R-NN<TAB>plan|tests|plan,tests
#   exit 2  invalid invocation, unreadable file           stdout: nothing
#   exit 3  structural error in the SPEC or the plan       stdout: DUPLICATE / MALFORMED / ORPHAN lines
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
# (e.g. this feature's own SPEC line 43) declares nothing. A well-formed ID at the start of a
# checklist item OUTSIDE every recognized section is the narrow escape hatch for a generator that
# emits IDs under an unrecognized heading: MALFORMED, exit 3 — never widened to "any R-NN anywhere"
# (that fires on prose, including this file's own header).
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

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: spec-coverage.sh --spec <file> --plan <file> [--tests-root <dir>] [--list]

stdout (machine channel): COVERED / UNCOVERED / DUPLICATE / MALFORMED / ORPHAN, TAB-separated.
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

# count_re() shape copied from secret-scan.sh:103 — never `grep -c X f || echo 0` (grep -c PRINTS 0
# AND EXITS 1 on no match, so the fallback also fires and the substitution yields the two-line
# string "0\n0", which breaks arithmetic on every clean run).
count_re() { _c=$(grep -c "$1" "$2" 2>/dev/null); printf '%s' "${_c:-0}"; }

IDS="$TMPD/ids.tsv";           : >"$IDS"
MALFORMED_IN="$TMPD/malformed_in.txt"; : >"$MALFORMED_IN"
OUTSIDE="$TMPD/outside.txt";   : >"$OUTSIDE"

# --- SPEC parser: declaration extraction, malformed-in-section, out-of-section well-formed IDs ---
cat >"$TMPD/spec_parse.awk" <<'AWKEOF'
# heading_level() and is_checklist_item() come from plan-task-predicate.awk, loaded alongside
# this program — do not redefine them here (awk rejects a duplicate function definition).
function is_start_heading(l,   lvl, rest, ll) {
  lvl = heading_level(l)
  if (lvl < 2) return 0
  rest = l
  sub(/^#+[ \t]+/, "", rest)
  ll = tolower(rest)
  return (ll ~ /^success criteria/) || (ll ~ /^acceptance criteria/) || (ll ~ /^definition of done/)
}
function item_text(l,   t) {
  t = l
  sub(/^[ \t]*[-*][ \t]\[[ xX]\][ \t]*/, "", t)
  return t
}
# Separator stripping for --list text (ADR-0048 §D6): trim, strip ONE leading separator (em dash,
# en dash, or one of - : . )), trim again. Em/en dash are matched by literal sub() on the raw UTF-8
# bytes (octal escapes — \xNN is not POSIX-portable in awk string literals), never a bracket class
# (a 3-byte character inside [...] is not portable across BSD and GNU awk).
function strip_sep(s,   EM, EN, c) {
  sub(/^[ \t]+/, "", s)
  EM = "\342\200\224"
  EN = "\342\200\223"
  if (sub("^" EM, "", s)) { }
  else if (sub("^" EN, "", s)) { }
  else {
    c = substr(s, 1, 1)
    if (c == "-" || c == ":" || c == "." || c == ")") s = substr(s, 2)
  }
  sub(/^[ \t]+/, "", s)
  return s
}
BEGIN { collecting = 0 }
{
  line = $0
  hl = heading_level(line)
  if (collecting && hl >= 1 && hl <= 2) collecting = 0
  if (is_start_heading(line)) { collecting = 1; next }

  if (is_checklist_item(line)) {
    txt = item_text(line)
    if (match(txt, /^[Rr]-[0-9][0-9A-Za-z]*/)) {
      tok = substr(txt, RSTART, RLENGTH)
      strict_ok = (tok ~ /^R-[0-9][0-9]$/)
      if (collecting) {
        if (strict_ok) {
          rest = substr(txt, RLENGTH + 1)
          rest = strip_sep(rest)
          printf "%s\t%s\n", tok, rest >> IDS_FILE
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
    -f "$PREDICATE" -f "$TMPD/spec_parse.awk" "$SPEC"

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
  if [ "$GUARD_FIRED" -eq 1 ]; then
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

grep_boundary_test() {
  _id="$1"
  [ -s "$TESTFILES" ] || return 1
  tr '\n' '\0' <"$TESTFILES" | xargs -0 grep -qE "(^|[^A-Za-z0-9_])${_id}([^0-9]|\$)" 2>/dev/null
}

OUT="$TMPD/out.txt"; : >"$OUT"
COV_N=0; UNCOV_N=0
while IFS="$TAB" read -r id _text; do
  [ -n "$id" ] || continue
  miss=""
  if grep -qxF "$id" "$PLAN_TOKENS" 2>/dev/null; then
    :
  else
    miss="plan"
  fi
  if [ -n "$TROOT" ]; then
    if grep_boundary_test "$id"; then
      :
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

cat "$OUT"

TROOT_DESC="not-checked"
[ -n "$TROOT" ] && TROOT_DESC="$TROOT"
if [ -n "$TROOT" ]; then
  printf '%s: %d id(s) declared, %d covered, %d uncovered, tests-root=%s, %d test file(s) discovered\n' \
    "$SELF" "$DECL_N" "$COV_N" "$UNCOV_N" "$TROOT_DESC" "$DISCOVERED_N" >&2
else
  printf '%s: %d id(s) declared, %d covered, %d uncovered, tests-root=%s\n' \
    "$SELF" "$DECL_N" "$COV_N" "$UNCOV_N" "$TROOT_DESC" >&2
fi

if [ "$UNCOV_N" -gt 0 ]; then
  exit 1
fi
exit 0
