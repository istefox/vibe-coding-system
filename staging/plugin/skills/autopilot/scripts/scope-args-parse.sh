#!/bin/bash
# scope-args-parse.sh v1.0 — parse `autopilot`'s launch arguments (issue #385, ADR-0132 §D2).
#
# WHY THIS IS A FILE AND NOT A FENCE. A skill's markdown body is RENDERED before the model sees
# it, and Claude Code whitespace-splits the skill's own invocation arguments and substitutes them
# into every positional-parameter token in that body — bash fences included, because a fence is
# just text. The loop below is the argument parser itself, so it was the first thing that
# rendering corrupted: launching with `--features 1 --only 294` rewrote the loop's own dispatch
# into the operator's own words, and what executed was syntactically valid shell that parsed
# nothing. The bound ADR-0129 exists to enforce would not have been enforced. A FILE is never
# rendered; the program below runs exactly as written, whatever `autopilot` was invoked with.
#
# ONLY THE INITIALISERS AND THE LOOP LIVE HERE, byte-for-byte as Phase S wrote them. The marker
# branch, the positive-integer guard and the `SCOPE-PARSE:` line deliberately STAY in the fence,
# where a human approving an overnight launch can read the mechanism at the point of decision
# (ADR-0132 §D2: excise the case, not the fence). Do not migrate the rest of Phase S into this
# file for tidiness — the narrow excision is the decision, and it was measured.
#
# THIS IS A DELIBERATE COPY OF NOTHING. Unlike mark-roadmap-skipped.sh (an ADR-0069 extraction
# serving two call sites), this file has exactly ONE caller: `autopilot` §1.3 Phase S. It exists
# because a positional parameter is illegal in a rendered document, not because two sites were
# disagreeing.
#
# USAGE
#   scope-args-parse.sh [<arg>…]
#
#   The caller passes the raw argument string UNQUOTED, reproducing the word split the fence's
#   own `set --` used to perform: `--features 2 --only 293,294` must arrive as five arguments and
#   never as one opaque word.
#
# OUTPUT — exactly six lines, in this order, one `key=value` each:
#   has_scoping_arg=0|1   seen_features=0|1   seen_only=0|1
#   cli_features=<value or empty>   cli_only=<value or empty>   dry_run=false|true
#
#   The caller reads each with `sed -n 's/^<key>=//p'`. Every key is a distinct anchored prefix,
#   so no extraction can capture a sibling's line. A value is a single whitespace-free token by
#   construction (the arguments were word-split before they got here), so no line can wrap.
#
# EXIT CONTRACT (ADR-0132 §D4, shared by the four scripts that issue adds)
#   0  RAN, and the six lines are on stdout. Every argument list is parseable: an unrecognised
#      token is skipped, never rejected, which is what the fence's `*)` arm always did.
#   2  bad invocation. NO INPUT REACHES IT — there is no argument list this script can refuse —
#      so the code is documented and unused rather than invented a use for. Do not repurpose it.
#   3  COULD NOT RUN. Likewise unreachable from inside: this script reads no file, calls no other
#      program and depends on nothing that can be missing. The only "did not run" state that
#      exists is this file being absent, which only the CALLER can observe, and Phase S's own
#      resolution branch reports it with exit 3 there.
#
#   It never prints a `CLEAN` sentinel and must never grow one — it is a parser, not a reporter
#   (ADR-0048's "two adjacent gates, two opposite caller idioms"). Nothing is written anywhere.
#
# VALIDATION IS THE CALLER'S, ON PURPOSE. `--features x` is reported here as
# `cli_features=x`, not rejected: the positive-integer guard has to name the SOURCE in its message
# ("from arguments" versus "from marker"), and the marker branch does not pass through this file
# at all. Moving the guard here would give it only half its inputs.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no here-strings.
set -u

_cli_features=""
_cli_only=""
_dry_run=false
_has_scoping_arg=0
_seen_features=0
_seen_only=0

while [ $# -gt 0 ]; do
  case "$1" in
    # A value that is absent, or that is itself a flag, counts as NOT SUPPLIED — never as an
    # empty value silently accepted. `--features` with nothing after it used to set
    # _has_scoping_arg=1 (discarding the marker's scope: block) while leaving _cli_features
    # empty, so the caller's positive-integer guard never ran and the run came out UNBOUNDED.
    # A one-token operator typo defeated the whole feature with nothing on screen.
    --features)
      _seen_features=1
      _has_scoping_arg=1
      case "${2:-}" in
        ''|-*) _cli_features=""; shift ;;
        *) _cli_features="$2"; shift 2 ;;
      esac
      ;;
    --only)
      _seen_only=1
      _has_scoping_arg=1
      case "${2:-}" in
        ''|-*) _cli_only=""; shift ;;
        *) _cli_only="$2"; shift 2 ;;
      esac
      ;;
    --dry-run)
      _dry_run=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

printf 'has_scoping_arg=%s\n' "$_has_scoping_arg"
printf 'seen_features=%s\n' "$_seen_features"
printf 'seen_only=%s\n' "$_seen_only"
printf 'cli_features=%s\n' "$_cli_features"
printf 'cli_only=%s\n' "$_cli_only"
printf 'dry_run=%s\n' "$_dry_run"

exit 0
