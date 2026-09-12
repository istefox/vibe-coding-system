#!/bin/bash
# prep-row-select.sh v1.0 — select which docs/specs/_issue-map.tsv rows Phase P step 3 should
# generate a SPEC for (issue #399, ADR-0134).
#
# WHY THIS IS A FILE AND NOT A FENCE. A skill's markdown body is RENDERED before the model sees
# it, and Claude Code whitespace-splits the skill's own invocation arguments and substitutes them
# into every positional-parameter token in that body — bash fences included, because a fence is
# just text. A three-column TSV parse wants awk field references, and an awk field reference
# ($1, $2, $3) is EXACTLY a positional-parameter token, so writing this parse inside a fence would
# reintroduce the defect ADR-0132 removed from this skill's other two helpers. A FILE is never
# rendered; this program runs exactly as written, whatever `autopilot` was invoked with.
#
# CONTRACT: a SELECTOR (ADR-0134 §D2) — neither a CHECKER (whose payload IS the verdict) nor a
# REPORTER (which always exits 0 and signals through stdout alone, ADR-0047 §D8). The caller does
# branch on the exit code, but on success the payload is the answer, a list of rows to generate.
#
#   exit 0  the selection RAN. Stdout carries zero or more map rows to generate, one per line, in
#           the map's own slug<TAB>num<TAB>title form. AN EMPTY LIST AT EXIT 0 IS A NORMAL, COMMON
#           RESULT — it means every row is already covered, already completed, or out of scope.
#   exit 2  bad invocation.
#   exit 3  the selection DID NOT RUN: the map or PROJECT.md could not be read, or the denominator
#           guard tripped (§D5 below).
#
# IT PRINTS NO "CLEAN" SENTINEL AND MUST NEVER GROW ONE — that idiom belongs to a REPORTER
# (weakening-scan.sh, ADR-0047), and this is not one.
#
# CHANNEL SEPARATION IS CONTRACT, NOT CONVENTION (ADR-0134 §D2). Stdout carries rows and NOTHING
# else; every note (ORPHAN, UNRECOGNISED-STATE, DUPLICATE, UNRESOLVED-TOKEN) and the PREP-SELECT
# summary go to stderr. Stdout here is consumed as DATA by the fence that calls this file, so a
# note on stdout would be a phantom row. This diverges from the two sibling Phase S/Phase 0 fences
# in this same skill, `autopilot-scope-args` and `autopilot-scope-resolve`, whose
# SCOPE-PARSE:/SCOPE-RESOLVE: lines go to STDOUT on purpose — their stdout is read by a human at
# an overnight-launch decision point, not consumed by a program. The divergence is deliberate and
# is written at both sites.
#
# USAGE
#   prep-row-select.sh --root <project-root> [--only <csv>]
#
# Derives <root>/docs/specs/_issue-map.tsv, <root>/PROJECT.md and <root>/docs/specs/ from --root.
# No --map/--roadmap override: fixtures build a root instead (this file has exactly one shape of
# input, the real one).
#
# Bash 3.2 clean: no associative arrays, no mapfile, no process substitution, no here-strings.
set -u

SELF="prep-row-select"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: prep-row-select.sh --root <project-root> [--only <csv>]

Selects the docs/specs/_issue-map.tsv rows Phase P step 3 should generate a SPEC for: a row is
selected when it is not already covered by a SPEC on disk and its state in PROJECT.md is pending
(or the row-to-state link is broken -- fail-open, reported), and it survives --only when given.

stdout: zero or more "<slug><TAB><num><TAB><title>" rows, one per line, in map order. Nothing else.
stderr: notes (ORPHAN, UNRECOGNISED-STATE, DUPLICATE, UNRESOLVED-TOKEN) and the PREP-SELECT summary.

Exit: 0 ran (an empty list is a normal result) | 2 bad invocation | 3 did not run
EOF
  exit 2
}

ROOT=""
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      case "${2:-}" in
        ''|-*) usage "--root requires a value" ;;
      esac
      ROOT="$2"
      shift 2
      ;;
    --only)
      case "${2:-}" in
        ''|-*) usage "--only requires a value" ;;
      esac
      ONLY="$2"
      shift 2
      ;;
    -h|--help)
      usage ""
      ;;
    *)
      usage "unknown argument: $1"
      ;;
  esac
done

[ -n "$ROOT" ] || usage "--root is required"

MAP="$ROOT/docs/specs/_issue-map.tsv"
PMD="$ROOT/PROJECT.md"
SPECDIR="$ROOT/docs/specs"

# Coverage predicate (issue #414 / ADR-0134 §D13): resolved once, up front, never re-derived per
# row. `SPEC_COVERAGE_LOOKUP_SH` lets a test point this at a fixture copy without touching the
# resolution order -- same override idiom as `CI_TIER_SH` in commit/SKILL.md Step 3.7.
SPEC_COVERAGE_LOOKUP_SH="${SPEC_COVERAGE_LOOKUP_SH:-}"
if [ -z "$SPEC_COVERAGE_LOOKUP_SH" ]; then
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/spec-coverage-lookup.sh" ]; then
    SPEC_COVERAGE_LOOKUP_SH="$CLAUDE_PLUGIN_ROOT/scripts/spec-coverage-lookup.sh"
  elif [ -f "$HOME/.claude/hooks/spec-coverage-lookup.sh" ]; then
    SPEC_COVERAGE_LOOKUP_SH="$HOME/.claude/hooks/spec-coverage-lookup.sh"
  fi
fi
if [ -z "$SPEC_COVERAGE_LOOKUP_SH" ] || [ ! -f "$SPEC_COVERAGE_LOOKUP_SH" ]; then
  printf '%s: could not run -- spec-coverage-lookup.sh not resolvable (checked CLAUDE_PLUGIN_ROOT/scripts and ~/.claude/hooks)\n' "$SELF" >&2
  exit 3
fi

# Step 1: read the map. Unreadable -> exit 3. Empty -> exit 0 with empty stdout, guard skipped --
# PROJECT.md is deliberately not touched in that case (PRS16, the positive twin of the denominator
# guard below: a helper that always exits 3 must not satisfy that guard's own RED evidence).
if [ ! -f "$MAP" ] || [ ! -r "$MAP" ]; then
  printf '%s: could not run -- map not found or unreadable at %s\n' "$SELF" "$MAP" >&2
  exit 3
fi
if [ ! -s "$MAP" ]; then
  exit 0
fi

# Step 2: read PROJECT.md. Unreadable -> exit 3.
if [ ! -f "$PMD" ] || [ ! -r "$PMD" ]; then
  printf '%s: could not run -- PROJECT.md not found or unreadable at %s\n' "$SELF" "$PMD" >&2
  exit 3
fi

# Step 3: resolve state for EVERY map row before any filtering -- the guard's denominator is the
# full map, never the post-filter subset (ADR-0134 §D5). One awk pass over PROJECT.md builds an
# issue<TAB>marker<TAB>count index using the row-shaped predicate below, capturing the marker
# character rather than restricting it to " xX~" -- restricting it would make the
# UNRECOGNISED-STATE branch further down unreachable dead code (ADR-0134 §D3). "First wins" falls
# straight out of the index: the marker is recorded only the first time an issue number is seen,
# and the count of row-shaped lines for that issue is tracked separately for the DUPLICATE note.
IDXTMP=$(mktemp) || { printf '%s: could not run -- cannot create a temp file\n' "$SELF" >&2; exit 3; }
trap 'rm -f "$IDXTMP"' EXIT

awk '
  $0 ~ /^[[:space:]]*- \[.\][[:space:]].*\(issue #[0-9]+\)/ {
    line = $0
    if (!match(line, /\[.\]/)) next
    mk = substr(line, RSTART + 1, RLENGTH - 2)
    if (!match(line, /\(issue #[0-9]+\)/)) next
    numpart = substr(line, RSTART, RLENGTH)
    gsub(/[^0-9]/, "", numpart)
    if (numpart in first) {
      cnt[numpart]++
    } else {
      first[numpart] = mk
      cnt[numpart] = 1
    }
  }
  END {
    for (n in first) printf "%s\t%s\t%s\n", n, first[n], cnt[n]
  }
' "$PMD" > "$IDXTMP" 2>/dev/null || {
  printf '%s: could not run -- awk failed while reading %s\n' "$SELF" "$PMD" >&2
  exit 3
}

MATCHED=$(awk -F'\t' '{s += $3} END{print s + 0}' "$IDXTMP")

# Step 4: denominator guard. A SINGLE row that fails to match falls open and is reported (ORPHAN,
# below); if EVERY row-shaped scan of PROJECT.md finds nothing at all, that is not 74 verdicts
# about 74 rows, it is one broken predicate, and this exits 3 -- never 0 with empty stdout, which
# would read as "ran and found nothing" (ADR-0134 §D4/§D5, PRS15; PRS16 above is its positive twin).
if [ "$MATCHED" -eq 0 ]; then
  printf '%s: could not run -- zero PROJECT.md lines matched the row-shaped predicate\n' "$SELF" >&2
  exit 3   # PRS15: zero matches means a broken predicate, not "found nothing" (R-06, ADR-0134 §D5)
fi

_toks=""
[ -n "$ONLY" ] && _toks=$(printf '%s' "$ONLY" | tr ',' ' ')

_map_rows=0
_selected=0
_covered=0
_completed=0
_skipped=0
_out_of_scope=0
_orphan=0
_unrecognised=0
_duplicate=0
_all_nums=""
_all_slugs=""

# Step 5: filter each row, in order -- --only, then coverage, then state (ADR-0134 §D4/§Decision).
# Read via file redirection on the loop's own `done`, never through a pipe: a piped `while` runs in
# a subshell and every counter below would be lost the moment the loop ends.
while IFS=$(printf '\t') read -r slug num title; do
  [ -n "$slug" ] || continue

  _map_rows=$((_map_rows + 1))
  # Accumulated for EVERY row, before any filter, so an --only token resolves against the whole
  # map regardless of scope or state (PRS19: --only 365 must resolve even though #365 is [x] and
  # selects nothing).
  _all_nums="$_all_nums $num"
  _all_slugs="$_all_slugs $slug"

  # --only FIRST (R-02, ADR-0134 §D6). A token matches this row's own num or slug field, exact --
  # never a re-derived slug (ADR-0069's rule: a second derivation of one value is a defect waiting
  # to disagree with the first).
  _in_scope=1
  if [ -n "$ONLY" ]; then
    _in_scope=0
    for _tok in $_toks; do
      [ -n "$_tok" ] || continue
      if [ "$_tok" = "$num" ] || [ "$_tok" = "$slug" ]; then _in_scope=1; fi   # PRS07: --only membership test (R-02)
    done
  fi
  if [ "$_in_scope" -eq 0 ]; then
    _out_of_scope=$((_out_of_scope + 1))
    continue
  fi

  # coverage SECOND (issue #414: the issue-NUMBER glob is now authoritative, matching
  # project-conductor's own predicate, not the map's own slug -- see spec-coverage-lookup.sh's
  # header for why a SPEC archived under a different slug for this same issue still counts).
  _covering_spec=$(bash "$SPEC_COVERAGE_LOOKUP_SH" "$SPECDIR" "$num")
  if [ -n "$_covering_spec" ]; then
    _covered=$((_covered + 1))
    continue
  fi

  # state THIRD (R-01, R-05, ADR-0134 §D3/§D4). Look up this issue number in the index built in
  # Step 3. An empty lookup means no row-shaped PROJECT.md line named this issue at all.
  _marker=$(awk -F'\t' -v n="$num" '$1 == n { print $2; exit }' "$IDXTMP")
  if [ -z "$_marker" ]; then
    _verdict=orphan   # PRS10: an unmatched issue number selects (fail-open), never drops (R-05)
  else
    _count=$(awk -F'\t' -v n="$num" '$1 == n { print $3; exit }' "$IDXTMP")
    if [ "$_count" -gt 1 ]; then
      _duplicate=$((_duplicate + 1))
      printf '%s: DUPLICATE row-shaped lines for issue #%s (%s) -- using the first marker "%s"\n' \
        "$SELF" "$num" "$slug" "$_marker" >&2
    fi
    case "$_marker" in
      x|X) _verdict=completed ;;   # PRS02: a completed marker suppresses selection (R-01)
      '~') _verdict=skipped ;;
      ' ') _verdict=pending ;;
      *)   _verdict=unrecognised ;;
    esac
  fi

  case "$_verdict" in
    completed)
      _completed=$((_completed + 1))
      ;;
    skipped)
      _skipped=$((_skipped + 1))
      ;;
    pending)
      _selected=$((_selected + 1))
      printf '%s\t%s\t%s\n' "$slug" "$num" "$title"
      ;;
    orphan)
      _orphan=$((_orphan + 1))
      _selected=$((_selected + 1))
      printf '%s\t%s\t%s\n' "$slug" "$num" "$title"
      printf '%s: ORPHAN issue #%s (%s) matched no PROJECT.md row-shaped line -- selecting\n' \
        "$SELF" "$num" "$slug" >&2
      ;;
    unrecognised)
      _unrecognised=$((_unrecognised + 1))
      _selected=$((_selected + 1))
      printf '%s\t%s\t%s\n' "$slug" "$num" "$title"
      printf '%s: UNRECOGNISED-STATE marker "%s" for issue #%s (%s) -- selecting\n' \
        "$SELF" "$_marker" "$num" "$slug" >&2
      ;;
  esac
done < "$MAP"

# Step 6: report every --only token that matched no map row as UNRESOLVED-TOKEN on stderr, and
# CONTINUE -- never an abort here. Phase 0 check 9 is the sole authority for aborting a launch on
# an unresolvable token, and it resolves against PROJECT.md while this helper resolves against the
# map; two authorities answering "is this token resolvable" from two different populations would
# be two answers that can disagree (ADR-0134 §D6, ADR-0086's criterion).
if [ -n "$ONLY" ]; then
  for _tok in $_toks; do
    [ -n "$_tok" ] || continue
    _resolved=0
    for _n in $_all_nums; do [ "$_n" = "$_tok" ] && _resolved=1; done
    for _s in $_all_slugs; do [ "$_s" = "$_tok" ] && _resolved=1; done
    if [ "$_resolved" -eq 0 ]; then
      printf '%s: UNRESOLVED-TOKEN "%s" matched no map row -- continuing, never an abort here\n' \
        "$SELF" "$_tok" >&2
    fi
  done
fi

# Step 7 (selected rows) already happened above, inline, in map order.
# Step 8: the PREP-SELECT summary, stderr only (ADR-0134 §D2 field order).
printf 'PREP-SELECT: map_rows=%s matched=%s selected=%s covered=%s completed=%s skipped=%s out_of_scope=%s orphan=%s unrecognised=%s duplicate=%s\n' \
  "$_map_rows" "$MATCHED" "$_selected" "$_covered" "$_completed" "$_skipped" \
  "$_out_of_scope" "$_orphan" "$_unrecognised" "$_duplicate" >&2

exit 0
