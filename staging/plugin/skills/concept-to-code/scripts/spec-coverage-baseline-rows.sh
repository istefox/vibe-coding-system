#!/bin/bash
# spec-coverage-baseline-rows.sh v1.0 — derives spec-coverage-scope-baseline.tsv rows for one
# (SPEC, plan) pair and, on request, appends the ones a completing chain introduces (issue #460;
# ADR-0166-460-spec-coverage-baseline-never-bumped.md).
#
# CONTRACT. This is a PRODUCER WITH A CHECKER'S EXIT-CODE CHANNEL (ADR-0166 §D4) — not the plain
# checker/reporter split spec-coverage.sh's own header describes (see that file's header before
# copying its branching shape into this one). --pair and --rows behave like producers: stdout is the
# payload, and empty/nothing is a valid, successful answer. --bump layers a checker's exit-code
# channel on top of that:
#   exit 0  success        BUMPED <n> row(s) for <spec-basename>   |   BUMP-NOOP: <reason>
#                           (--rows and --pair: rows / the resolved plan path, or nothing, on stdout)
#   exit 1  conflict       a computed row disagrees with an existing frozen row; NOTHING written
#   exit 2  invalid        bad invocation, unreadable --spec/--plan/--baseline
#   exit 3  did not run    spec-coverage.sh unresolvable, or it exited 2 or 3 for this pair
#
# This script NEVER re-interprets spec-coverage.sh's own COVERED/UNCOVERED/UNSCOPED tokens
# (ADR-0069/ADR-0072 — one source of truth for what "covered" means). --rows reads them straight off
# its stdout, using the exact two greps spec-coverage.test.sh's own inline derivation used before this
# script existed. Its consumers are spec-coverage.test.sh's RS7-RS10 block (ADR-0166 Task 3) and
# concept-to-code's Step 7.0b fence (ADR-0166 Task 5) — NEVER stop-gate.sh, whose fixed exit-code map
# is what makes exit 3 dangerous for a generated test-cmd line (CLAUDE.md rule 20, ADR-0166 §D4).
#
# --rows passes spec-coverage.sh's own stderr through UNCHANGED (ADR-0166 §D3): the --tests-root
# invocation below is never redirected, so it inherits this script's stderr and reaches the caller
# verbatim, byte-identical to invoking spec-coverage.sh directly with the same arguments. This
# script's OWN diagnostics go to stderr only on a failure path (an unresolvable checker, or the
# checker itself exiting 2/3), so a clean run never adds a byte spec-coverage.sh did not already
# write — the exact property RY10's SCOPE-NO-BACKREF/"N in scope" stderr reads depend on.
#
# --bump never rewrites, reorders or reformats an existing baseline line (CLAUDE.md rule 14): a row
# absent from the baseline is appended; a row present with an identical verdict is skipped; a row
# present with a DIFFERENT verdict fails the whole call before a single byte is written (two passes,
# never one — see do_bump() below). An absent --baseline file is a genuine no-op and is never created
# (ADR-0166 §D6): concept-to-code runs on arbitrary projects, most of which have no corpus baseline.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="spec-coverage-baseline-rows"
TAB=$(printf '\t')
SELFDIR=$(cd "$(dirname "$0")" && pwd)

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: spec-coverage-baseline-rows.sh --pair --spec <spec> --plans-dir <dir>
       spec-coverage-baseline-rows.sh --rows --spec <spec> --plan <plan> --tests-root <root> [--scov-override <path>]
       spec-coverage-baseline-rows.sh --bump --baseline <file> --spec <spec> --plan <plan> --tests-root <root>

stdout: --pair prints the resolved plan path, or nothing. --rows prints
<spec-basename><TAB><id><TAB><verdict> rows, one per declared id, or nothing for a SPEC declaring
none. --bump prints one summary line on success: "BUMPED <n> row(s) for <spec-basename>" or
"BUMP-NOOP: <reason>".
Exit: 0 success (including every genuine no-op) | 1 --bump conflict, nothing written |
2 invalid invocation, unreadable input | 3 did not run (spec-coverage.sh unresolvable, or itself
exited 2 or 3 for this pair).
EOF
}

# --scov-override exists for the test harness's NB6 fixture (an unresolvable-checker exit-3 proof)
# and for nothing else — never documented as a normal-use flag above.
MODE=""
SPEC=""; PLAN=""; TROOT=""; PLANSDIR=""; BASELINE=""; SCOV_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pair) MODE="pair"; shift ;;
    --rows) MODE="rows"; shift ;;
    --bump) MODE="bump"; shift ;;
    --spec)
      [ $# -ge 2 ] || { usage "--spec needs a file argument"; exit 2; }
      SPEC="$2"; shift 2 ;;
    --plan)
      [ $# -ge 2 ] || { usage "--plan needs a file argument"; exit 2; }
      PLAN="$2"; shift 2 ;;
    --plans-dir)
      [ $# -ge 2 ] || { usage "--plans-dir needs a directory argument"; exit 2; }
      PLANSDIR="$2"; shift 2 ;;
    --tests-root)
      [ $# -ge 2 ] || { usage "--tests-root needs a directory argument"; exit 2; }
      TROOT="$2"; shift 2 ;;
    --baseline)
      [ $# -ge 2 ] || { usage "--baseline needs a file argument"; exit 2; }
      BASELINE="$2"; shift 2 ;;
    --scov-override)
      [ $# -ge 2 ] || { usage "--scov-override needs a file argument"; exit 2; }
      SCOV_OVERRIDE="$2"; shift 2 ;;
    *)
      usage "unknown argument: $1"; exit 2 ;;
  esac
done

[ -n "$MODE" ] || { usage "one of --pair, --rows, --bump is required"; exit 2; }

TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT

# --- spec-coverage.sh resolution: sibling of $0 first, then the deployed ~/.claude copy. -----------
resolve_scov() {
  if [ -n "$SCOV_OVERRIDE" ]; then
    if [ -f "$SCOV_OVERRIDE" ] && [ -r "$SCOV_OVERRIDE" ]; then
      SCOV="$SCOV_OVERRIDE"; return 0
    fi
    printf '%s: spec-coverage.sh unresolvable: %s\n' "$SELF" "$SCOV_OVERRIDE" >&2
    return 1
  fi
  _rs_cand="$SELFDIR/spec-coverage.sh"
  if [ -f "$_rs_cand" ] && [ -r "$_rs_cand" ]; then
    SCOV="$_rs_cand"; return 0
  fi
  _rs_cand="$HOME/.claude/skills/concept-to-code/scripts/spec-coverage.sh"
  if [ -f "$_rs_cand" ] && [ -r "$_rs_cand" ]; then
    SCOV="$_rs_cand"; return 0
  fi
  printf '%s: spec-coverage.sh unresolvable: tried %s and %s\n' \
    "$SELF" "$SELFDIR/spec-coverage.sh" "$_rs_cand" >&2
  return 1
}

# --- --pair: the harness's own per-spec plan resolution, moved verbatim (ADR-0166 §D2). ------------
# _n kept only when it is all digits; falls back to the slug-only form; prints nothing, exits 0, on
# no match either way. This is a producer, never a checker — absence of a pair is not an error.
do_pair() {
  _p_spec="$1"; _p_dir="$2"
  _p_bn=$(basename "$_p_spec")
  _p_n=${_p_bn%%-*}
  case "$_p_n" in ''|*[!0-9]*) _p_n="" ;; esac
  # VCS-034: the first hyphen-separated segment is stripped ONLY when it was actually the numeric
  # issue-number prefix. An issue-less SPEC (e.g. spec-coverage-scope-back-reference.spec.md) has
  # no such segment — _p_n is cleared above — and stripping "spec" anyway built the mutilated
  # fallback slug "coverage-scope-back-reference", which the glob below can never match against
  # the real plan (…-spec-coverage-scope-back-reference.md). The pair then resolved to nothing and
  # the SPEC left the RS_PAIRS corpus silently (spec-coverage.test.sh's own skip-on-empty).
  if [ -n "$_p_n" ]; then
    _p_rest=${_p_bn#*-}
  else
    _p_rest=$_p_bn
  fi
  _p_slug=${_p_rest%.spec.md}
  _p_plan=""
  if [ -n "$_p_n" ]; then
    _p_plan=$(ls "$_p_dir"/????-??-??-"${_p_n}"-*.md 2>/dev/null | head -1)
  fi
  if [ -z "$_p_plan" ]; then
    _p_plan=$(ls "$_p_dir"/????-??-??-"${_p_slug}".md 2>/dev/null | head -1)
  fi
  [ -n "$_p_plan" ] && printf '%s\n' "$_p_plan"
  return 0
}

# --- --rows: one TSV row per declared id, verdicts read straight off spec-coverage.sh's own stdout. -
# Returns (never `exit`s — --bump calls this too) 0 on success, including the silent zero-ids path,
# or 3 when the checker is unresolvable or itself exited 2 or 3 for this pair (ADR-0166 §D4).
compute_rows() {
  _cr_spec="$1"; _cr_plan="$2"; _cr_troot="$3"
  resolve_scov || return 3
  # Step 1 (ADR-0166 Task 2): --list's stderr stays discarded, exactly as the harness's inline
  # derivation already did. Empty stdout is the silent no-ids path (ADR-0048 §D7/§D8) — not "0
  # rows", nothing at all, and this wrapper does not second-guess it.
  _cr_list=$(bash "$SCOV" --spec "$_cr_spec" --plan "$_cr_plan" --list 2>/dev/null)
  [ -n "$_cr_list" ] || return 0
  # Step 2: the --tests-root invocation's stderr is NOT redirected here — it inherits this
  # function's (and so this script's) own stderr and reaches the caller verbatim (ADR-0166 §D3).
  _cr_run=$(bash "$SCOV" --spec "$_cr_spec" --plan "$_cr_plan" --tests-root "$_cr_troot")
  _cr_rc=$?
  # Step 3: rc 0 or 1 is normal and carries verdicts; rc >= 2 is "did not run" and must not read as
  # a producer that found nothing (CLAUDE.md rule 4) — no stdout, a prefixed stderr diagnostic.
  if [ "$_cr_rc" -ge 2 ]; then
    printf '%s: spec-coverage.sh did not run cleanly (exit %s) for --spec %s --plan %s\n' \
      "$SELF" "$_cr_rc" "$_cr_spec" "$_cr_plan" >&2
    return 3
  fi
  _cr_bn=$(basename "$_cr_spec")
  # Step 4: exactly the two greps the harness used inline, same anchors, same order — never a
  # subshell pipeline here, so a caller capturing this function's whole stdout gets every row.
  _cr_listfile="$TMPD/cr-list.txt"
  printf '%s\n' "$_cr_list" >"$_cr_listfile"
  while IFS="$TAB" read -r _cr_id _cr_text; do
    [ -n "$_cr_id" ] || continue
    _cr_verdict="UNCOVERED"
    printf '%s\n' "$_cr_run" | grep -q "^COVERED${TAB}${_cr_id}\$" && _cr_verdict="COVERED"
    printf '%s\n' "$_cr_run" | grep -q "^UNSCOPED${TAB}${_cr_id}${TAB}" && _cr_verdict="UNSCOPED"
    printf '%s\t%s\t%s\n' "$_cr_bn" "$_cr_id" "$_cr_verdict"
  done <"$_cr_listfile"
  return 0
}

# --- --bump: compute rows for one pair, refuse on conflict, append what is absent (ADR-0166 §D7). --
do_bump() {
  # D6 — an absent baseline is a genuine no-op and is never created: concept-to-code runs on
  # projects with no corpus baseline at all, and creating one would halt every such chain at Step
  # 7.0b for a file that was never supposed to exist there.
  if [ ! -f "$BASELINE" ]; then
    printf 'BUMP-NOOP: no baseline at %s\n' "$BASELINE"
    return 0
  fi

  # D2 — cross-check the pair the harness's own --pair sweep would resolve for this SPEC against
  # the plan this call was invoked with, in the directory that holds it. A genuine DISAGREEMENT
  # (the harness resolves a DIFFERENT plan) means this call would write rows for a pair RS8b can
  # never match on its own — refused before anything is written. An UNRESOLVED pair (no dated plan
  # matching this SPEC's issue number or slug in that directory — the ordinary shape of a purely
  # hand-tested SPEC with no issue-number prefix) has nothing to disagree with, so it does not by
  # itself block the bump; only a positive, differing resolution does (ADR-0166 §D2's own stated
  # purpose is "refuses when the manifest's plan is not the one the harness will use" — silence is
  # not that).
  _b_plandir=$(dirname "$PLAN")
  _b_resolved=$(do_pair "$SPEC" "$_b_plandir")
  if [ -n "$_b_resolved" ] && [ "$_b_resolved" != "$PLAN" ]; then
    printf '%s: pair mismatch for --spec %s: the harness resolves %s, invoked with %s — nothing written\n' \
      "$SELF" "$SPEC" "$_b_resolved" "$PLAN" >&2
    return 1
  fi

  # D2/D5 — compute this pair's rows with the same --rows logic, --tests-root always passed
  # unconditionally (unlike Gate 4.x's conditional omission): the baseline's rows are defined by
  # what the harness computes, and the harness always passes --tests-root.
  _b_rowsfile="$TMPD/bump-rows.tsv"
  compute_rows "$SPEC" "$PLAN" "$TROOT" >"$_b_rowsfile"
  _b_rc=$?
  if [ "$_b_rc" -ne 0 ]; then
    return 3
  fi
  if [ ! -s "$_b_rowsfile" ]; then
    printf 'BUMP-NOOP: SPEC declares no ids\n'
    return 0
  fi

  # D7 — TWO PASSES, NEVER ONE. Pass 1 (read-only): any computed row that disagrees with an
  # existing frozen row halts the WHOLE call before a single byte is written — a frozen row is
  # never silently corrected (CLAUDE.md rule 14).
  _b_conflict=0
  while IFS="$TAB" read -r _b_bn _b_id _b_verdict; do
    [ -n "$_b_bn" ] || continue
    _b_existing=$(awk -F"$TAB" -v s="$_b_bn" -v i="$_b_id" '$1==s && $2==i {print $3; exit}' "$BASELINE")
    if [ -n "$_b_existing" ] && [ "$_b_existing" != "$_b_verdict" ]; then
      printf '%s: conflict for %s %s: baseline has %s, computed %s — nothing written\n' \
        "$SELF" "$_b_bn" "$_b_id" "$_b_existing" "$_b_verdict" >&2
      _b_conflict=1
    fi
  done <"$_b_rowsfile"
  if [ "$_b_conflict" -eq 1 ]; then
    return 1
  fi

  # Pass 2 (write): every computed row absent from the baseline is appended, in --rows order.
  # A row present with an identical verdict is skipped silently — the idempotent, resumed-chain
  # case. Never rewrites, reorders or reformats an existing line.
  _b_appendfile="$TMPD/bump-append.tsv"; : >"$_b_appendfile"
  _b_n=0
  while IFS="$TAB" read -r _b_bn _b_id _b_verdict; do
    [ -n "$_b_bn" ] || continue
    _b_existing=$(awk -F"$TAB" -v s="$_b_bn" -v i="$_b_id" '$1==s && $2==i {print $3; exit}' "$BASELINE")
    if [ -z "$_b_existing" ]; then
      printf '%s\t%s\t%s\n' "$_b_bn" "$_b_id" "$_b_verdict" >>"$_b_appendfile"
      _b_n=$((_b_n + 1))
    fi
  done <"$_b_rowsfile"

  if [ "$_b_n" -eq 0 ]; then
    printf 'BUMP-NOOP: already present\n'
    return 0
  fi

  # Write to a temp file, then mv over the baseline — a killed run cannot leave a half-written
  # corpus file. A baseline whose last byte is not a newline gets one before the first append
  # (`tail -c 1`, never assumed); today's file already ends with one.
  _b_newfile="$TMPD/baseline-new.tsv"
  cp "$BASELINE" "$_b_newfile"
  _b_lastbyte=$(tail -c 1 "$_b_newfile" 2>/dev/null)
  if [ -n "$_b_lastbyte" ]; then
    printf '\n' >>"$_b_newfile"
  fi
  cat "$_b_appendfile" >>"$_b_newfile"
  mv "$_b_newfile" "$BASELINE"

  _b_spec_bn=$(basename "$SPEC")
  printf 'BUMPED %s row(s) for %s\n' "$_b_n" "$_b_spec_bn"
  return 0
}

# ================================================== mode dispatch ==================================
case "$MODE" in
  pair)
    [ -n "$SPEC" ] || { usage "--spec is required"; exit 2; }
    [ -n "$PLANSDIR" ] || { usage "--plans-dir is required"; exit 2; }
    do_pair "$SPEC" "$PLANSDIR"
    exit 0
    ;;
  rows)
    [ -n "$SPEC" ] || { usage "--spec is required"; exit 2; }
    [ -n "$PLAN" ] || { usage "--plan is required"; exit 2; }
    [ -n "$TROOT" ] || { usage "--tests-root is required"; exit 2; }
    [ -r "$SPEC" ] || { usage "cannot read --spec file: $SPEC"; exit 2; }
    [ -r "$PLAN" ] || { usage "cannot read --plan file: $PLAN"; exit 2; }
    compute_rows "$SPEC" "$PLAN" "$TROOT"
    exit $?
    ;;
  bump)
    [ -n "$BASELINE" ] || { usage "--baseline is required"; exit 2; }
    [ -n "$SPEC" ] || { usage "--spec is required"; exit 2; }
    [ -n "$PLAN" ] || { usage "--plan is required"; exit 2; }
    [ -n "$TROOT" ] || { usage "--tests-root is required"; exit 2; }
    [ -r "$SPEC" ] || { usage "cannot read --spec file: $SPEC"; exit 2; }
    [ -r "$PLAN" ] || { usage "cannot read --plan file: $PLAN"; exit 2; }
    do_bump
    exit $?
    ;;
esac
