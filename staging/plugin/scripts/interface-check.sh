#!/bin/bash
# interface-check.sh v1.0 — interface immutability CHECKER (issue #107; ADR-0053).
#
# CONTRACT (ADR-0053 §D2/§D3). This is a CHECKER, unlike its two REPORTER neighbours in this
# directory (secret-scan.sh, dependency-scan.sh) and unlike weakening-scan.sh / diff-budget-
# check.sh over in the skill directories — the exit code IS the policy channel and the caller
# branches on it. Do not copy a reporter idiom here (`grep -q '^WEAKENED'`, a CLEAN sentinel,
# "always exits 0"); do not copy this script's exit-code branching onto a reporter either. See
# the contract table at the c2c Step 6 call site for all four scripts in this family side by side.
#   stdout  PROTECTED<TAB><entry><TAB><file>:<line><TAB>removed|changed   (one line per violation)
#   exit 0  no protected interface broken (including: nothing declared at all)
#   exit 2  bad invocation (missing/unreadable --root, unreadable declaration file, unknown flag)
#   exit 3  one or more protected interfaces broken — stdout carries the PROTECTED lines
#
# INERT WHEN ABSENT IS THE HARD GATE (ADR-0053 §D1/§D2 — "a project is only ever blocked by a
# protection it declared itself"). If <root>/.claude/protected-interfaces does not exist, OR
# exists but contains nothing but blank lines and whole-line `#` comments (the SPEC's own edge
# case: "a comment-only or blank-line file behaves as absent"), this script is COMPLETELY SILENT:
# exit 0, no stdout, no stderr. Not "0 entries declared, OK" — nothing at all, the same
# silent-by-construction shape ADR-0048 §D7/§D8 gave spec-coverage.sh's no-IDs path and ADR-0041
# gave write-scope-enforce.sh's no-scope-line path. This is what makes §D2's blocking defensible.
# Assert it against a fixture repo AND against this repository, which carries no such file.
#
# ENTRY GRAMMAR (§D1). One entry per line in the declaration file; blank lines and lines whose
# first non-blank character is `#` are ignored (no inline trailing-comment stripping — a `#`
# inside a real signature is left alone). Two independent kinds, told apart by one cheap,
# deterministic rule, not a prefix character a human has to remember:
#   - contains whitespace  -> a literal SIGNATURE: the exact (leading/trailing-trimmed) text of
#     one declaration line, protected wherever it appears, independent of file. A real
#     declaration line always has at least one space (keyword + name, a return type, a parameter
#     list); a bare path or glob never does. Moving this exact text to a different file is NOT a
#     violation (the SPEC's edge case: "a moved-but-identical signature should not be reported as
#     removed if the entry is a signature rather than a path" — "accrete, don't destroy" covers
#     relocation too, for this kind only).
#   - no whitespace        -> a PATH GLOB: every DECLARATION-SHAPED line found in the pre-image
#     of a file matching the glob is protected. "Declaration-shaped" reuses the same cheap,
#     multi-language heuristic ADR-0051's deleted-public-symbol detector already established in
#     weakening-scan.sh (def/func/export/public/route prefixes) — not a parser, a prefix check.
#     Unlike a signature, a glob entry is path-scoped: the identical text reappearing in a
#     DIFFERENT file is still a violation, because what is protected is "this declaration stays
#     in this file," not "this text exists somewhere in the tree."
#
# §D4 — TEXTUAL AND DELIBERATELY SHALLOW, two consequences accepted rather than fixed, pinned as
# *expected* by the harness's IF section (the ADR-0045 section-E pattern: closing either forces
# this paragraph to move with the code):
#   - MISS: a signature entry names exactly one line of text. A default-argument edit on a
#     CONTINUATION line of a multi-line signature never touches that one protected line, so it is
#     invisible here.
#   - OVER-FIRE: a pure reformat (reindent, line-wrap) of a protected declaration changes its
#     exact text, so it is reported even though the interface itself did not change. The remedy
#     is a one-line edit to a file the operator owns (ADR-0053 Consequences, negative).
#
# No language parser, no AST, no tool dependence (ADR-0039 §D4, applied again here — a verdict
# that depends on which parser is installed is not a verdict).
#
# CALLERS MUST PASS `git diff --no-renames` (or equivalent). Git's default rename detection
# collapses a same-content file move into a "rename from/to" record with NO `-`/`+` content lines
# at all when similarity is 100%, which would hide a path-glob relocation this script is designed
# to catch (§D1's path-scoped kind) behind a diff that looks empty. `--no-renames` makes a move
# show up as a plain delete-from-old-path plus add-at-new-path, which is what a purely textual,
# line-based check needs to see either kind of entry correctly.
#
# WHY THIS DIRECTORY, NOT `concept-to-code/scripts/` BESIDE spec-coverage.sh (ADR-0053 Task 2).
# This script's inputs are a project-level declaration file and a diff — never a chain artifact
# (no `manifest.artifacts.*`). ADR-0048 §A6 drew this exact line the other way for spec-
# coverage.sh, because ITS inputs (SPEC, plan) ARE chain artifacts. §D5 requires a standalone CI
# call site with no agent present — the same requirement that put secret-scan.sh and
# dependency-scan.sh here rather than in a skill's own scripts/ directory. Same reasoning,
# opposite of ADR-0048's, same conclusion as ADR-0046's.
#
# The "removed" vs "changed" label is a loose heuristic, not a claim of precision: "changed" means
# the violating line's file has at least one added line anywhere in this diff, "removed" means it
# does not. Both count identically toward the exit-3 decision — the label is descriptive only.
#
# Bash 3.2 clean: no assoc arrays (in the calling shell), no mapfile, no process substitution,
# no <<<.
set -u

SELF="interface-check"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: interface-check.sh --root <dir> < unified-diff-on-stdin
       (the diff MUST come from `git diff --no-renames` or equivalent — see header)

Reads <dir>/.claude/protected-interfaces (absent, or comment/blank-only -> silent, exit 0,
no stdout, no stderr).
stdout: PROTECTED<TAB><entry><TAB><file>:<line><TAB>removed|changed, one line per violation.
Exit: 0 clean (or nothing declared) | 2 bad invocation | 3 one or more protected interfaces broken.
EOF
}

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { usage "--root needs a directory argument"; exit 2; }
      ROOT="$2"; shift 2 ;;
    *)
      usage "unknown argument: $1"; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || { usage "--root is required"; exit 2; }
[ -d "$ROOT" ] || { usage "not a directory: $ROOT"; exit 2; }

DECL="$ROOT/.claude/protected-interfaces"

# --- the inert-by-absence hard gate (ADR-0053 §D1/§D2), first and totally silent ------------------
if [ ! -f "$DECL" ]; then
  exit 0
fi
[ -r "$DECL" ] || { usage "cannot read declaration file: $DECL"; exit 2; }

TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

# count_re() shape copied from secret-scan.sh:103 — never `grep -c X f || echo 0` (grep -c PRINTS 0
# AND EXITS 1 on no match, so the fallback also fires and the substitution yields the two-line
# string "0\n0", breaking arithmetic on every clean run).
count_re() { _c=$(grep -c "$1" "$2" 2>/dev/null); printf '%s' "${_c:-0}"; }

SIGS="$TMPD/sigs.txt"; : >"$SIGS"
GLOBS="$TMPD/globs.txt"; : >"$GLOBS"

# --- declaration-file parser: whole-line comments and blanks dropped, whitespace test classifies
#     the rest as a literal signature or a path glob (see ENTRY GRAMMAR above) ---------------------
awk -v SIGS_FILE="$SIGS" -v GLOBS_FILE="$GLOBS" '
function trim(s) { gsub(/^[ \t]+/,"",s); gsub(/[ \t]+$/,"",s); return s }
{
  line = trim($0)
  if (line == "") next
  if (substr(line, 1, 1) == "#") next
  if (line ~ /[ \t]/) print line >> SIGS_FILE
  else                 print line >> GLOBS_FILE
}
' "$DECL"

# --- comment-only / blank-only declaration file behaves as absent (SPEC edge case) — same silent
#     exit as a genuinely missing file, checked AFTER parsing since only the parse tells us -------
if [ ! -s "$SIGS" ] && [ ! -s "$GLOBS" ]; then
  exit 0
fi
TOTAL_ENTRIES=$(( $(count_re . "$SIGS") + $(count_re . "$GLOBS") ))

# --- consume the unified diff on stdin -------------------------------------------------------------
DIFF_IN="$TMPD/diff.txt"
cat >"$DIFF_IN"

REMOVED="$TMPD/removed.tsv"; : >"$REMOVED"
ADDED="$TMPD/added.tsv"; : >"$ADDED"
ADDEDFILES="$TMPD/added_files.txt"; : >"$ADDEDFILES"

# --- diff parser: same @@ hunk-header line tracking as weakening-scan.sh and secret-scan.sh's
#     --diff mode, so a deletion (+++ /dev/null) keeps the OLD path from the --- line rather than
#     losing it -----------------------------------------------------------------------------------
awk -v REMOVED_FILE="$REMOVED" -v ADDED_FILE="$ADDED" -v ADDEDFILES_FILE="$ADDEDFILES" '
/^diff --git / { file=""; oldln=0; newln=0; next }
/^--- /        { if (file=="") { p=$2; sub(/^a\//,"",p); if (p!="/dev/null") file=p } next }
/^\+\+\+ /     { p=$2; sub(/^b\//,"",p); if (p!="/dev/null") file=p; next }
/^@@ /         {
  if (match($0, /-[0-9]+/)) oldln = substr($0, RSTART+1, RLENGTH-1) + 0
  if (match($0, /\+[0-9]+/)) newln = substr($0, RSTART+1, RLENGTH-1) + 0
  next
}
{
  if (file == "") next
  c = substr($0, 1, 1)
  if (c == "-" && substr($0,1,3) != "---") {
    printf "%s\t%d\t%s\n", file, oldln, substr($0,2) >> REMOVED_FILE
    oldln++
  } else if (c == "+" && substr($0,1,3) != "+++") {
    printf "%s\t%d\t%s\n", file, newln, substr($0,2) >> ADDED_FILE
    print file >> ADDEDFILES_FILE
    newln++
  } else if (c == "\\") {
    # "\ No newline at end of file" — no counter change
  } else {
    oldln++; newln++
  }
}
' "$DIFF_IN"

OUT="$TMPD/out.txt"; : >"$OUT"

# --- signature matching (path-independent, "moved" exemption applies) — one awk pass, exact-text
#     keyed associative arrays, no shell loop needed -----------------------------------------------
if [ -s "$SIGS" ]; then
  awk -v SIGS_FILE="$SIGS" -v ADDED_FILE="$ADDED" -v ADDEDFILES_FILE="$ADDEDFILES" '
  function trim(s) { gsub(/^[ \t]+/,"",s); gsub(/[ \t]+$/,"",s); return s }
  BEGIN {
    while ((getline l < SIGS_FILE) > 0) if (l != "") sig[l] = 1
    close(SIGS_FILE)
    while ((getline l < ADDEDFILES_FILE) > 0) if (l != "") addedfile[l] = 1
    close(ADDEDFILES_FILE)
    while ((getline rec < ADDED_FILE) > 0) {
      i = index(rec, "\t"); if (i == 0) continue
      rest = substr(rec, i+1)
      j = index(rest, "\t"); if (j == 0) continue
      t = trim(substr(rest, j+1))
      addedtext[t] = 1
    }
    close(ADDED_FILE)
  }
  {
    i = index($0, "\t"); if (i == 0) next
    f = substr($0, 1, i-1); rest = substr($0, i+1)
    j = index(rest, "\t"); if (j == 0) next
    ln = substr(rest, 1, j-1); t = trim(substr(rest, j+1))
    if (!(t in sig)) next
    if (t in addedtext) next
    label = (f in addedfile) ? "changed" : "removed"
    printf "PROTECTED\t%s\t%s:%s\t%s\n", t, f, ln, label
  }
  ' "$REMOVED" >>"$OUT"
fi

# --- path-glob matching (path-scoped, no "moved" exemption). First filter REMOVED lines down to
#     declaration-shaped ones (the shared multi-language heuristic), then match glob patterns via a
#     plain shell `case` — the same real-glob-semantics choice ADR-0031/ADR-0052 made, `*` already
#     matching across `/` with no globstar needed -----------------------------------------------
if [ -s "$GLOBS" ]; then
  REMOVED_DECLS="$TMPD/removed_decls.tsv"; : >"$REMOVED_DECLS"
  awk -v OUT_FILE="$REMOVED_DECLS" '
  function is_decl(s) {
    gsub(/^[ \t]+/, "", s)
    if (s ~ /^export[ \t]+(function|const|class|default[ \t]+function)[ \t]+/) return 1
    if (s ~ /^public[ \t]+(class|struct|func|static)[ \t]+/) return 1
    if (s ~ /^def[ \t]+[A-Za-z_][A-Za-z0-9_]*\(/) return 1
    if (s ~ /^func[ \t]+[A-Za-z_][A-Za-z0-9_]*\(/) return 1
    if (s ~ /^(app|router)\.(get|post|put|delete|patch)\(/) return 1
    return 0
  }
  {
    i = index($0, "\t"); if (i == 0) next
    f = substr($0, 1, i-1); rest = substr($0, i+1)
    j = index(rest, "\t"); if (j == 0) next
    ln = substr(rest, 1, j-1); t = substr(rest, j+1)
    if (is_decl(t)) printf "%s\t%s\t%s\n", f, ln, t >> OUT_FILE
  }
  ' "$REMOVED"

  TAB=$(printf '\t')
  if [ -s "$REMOVED_DECLS" ]; then
    while IFS= read -r _g; do
      [ -n "$_g" ] || continue
      while IFS="$TAB" read -r _f _ln _txt; do
        [ -n "$_f" ] || continue
        case "$_f" in
          $_g) : ;;
          *) continue ;;
        esac
        _label="removed"
        grep -qxF "$_f" "$ADDEDFILES" 2>/dev/null && _label="changed"
        printf 'PROTECTED\t%s\t%s:%s\t%s\n' "$_g" "$_f" "$_ln" "$_label" >>"$OUT"
      done <"$REMOVED_DECLS"
    done <"$GLOBS"
  fi
fi

if [ -s "$OUT" ]; then
  DEDUP="$TMPD/dedup.txt"
  sort -u "$OUT" >"$DEDUP" 2>/dev/null || cp "$OUT" "$DEDUP"
  N=$(count_re . "$DEDUP")
  if [ "$N" -gt 0 ]; then
    cat "$DEDUP"
    printf '%s: %d protected entry(s) declared, %d violation(s)\n' "$SELF" "$TOTAL_ENTRIES" "$N" >&2
    exit 3
  fi
fi

printf '%s: %d protected entry(s) declared, 0 violation(s)\n' "$SELF" "$TOTAL_ENTRIES" >&2
exit 0
