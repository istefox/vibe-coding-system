#!/bin/bash
# conductor-args.sh v1.0 — parse `project-conductor`'s own invocation arguments (issue #385,
# ADR-0132 §D2/§D5).
#
# WHY THIS IS A FILE AND NOT A FENCE, and why this one call site is different from the other
# three that issue moves. A skill's markdown body is RENDERED before the model sees it, and
# Claude Code whitespace-splits the skill's invocation arguments and substitutes them into every
# positional-parameter token in that body — bash fences included, because a fence is just text.
# Step 0's mode detection read the first positional parameter while its `--fork-from` scan walked
# the argument list and read its length. Those are not the same source: the first was filled in
# by the renderer, the second two belong to the shell that executes the fence, which has NO
# positional parameters at all and therefore an EMPTY list. So neither parse has ever worked as
# written — the mode check compared the renderer's substitution against a literal, and the scan
# iterated nothing (audit §F1). Repairing it necessarily changes the RENDERED behaviour, because
# the rendered behaviour is wrong; the designed semantics, which this file implements, are
# unchanged.
#
# A FILE is never rendered, so the parameters below are the ones the caller actually passed.
#
# USAGE
#   conductor-args.sh [<arg>…]
#
#   The caller passes the raw argument string UNQUOTED, so `autopilot --fork-from main` arrives
#   as three arguments and not as one opaque word. This is the pattern `autopilot` §1.3 Phase S
#   already uses for its own launch arguments.
#
# OUTPUT — exactly two lines, in this order:
#   autopilot=true|false   fork_from=<ref or empty>
#
#   The caller reads each with `sed -n 's/^<key>=//p'`. The two keys share no prefix.
#
# EXIT CONTRACT (ADR-0132 §D4, shared by the four scripts that issue adds)
#   0  RAN, and the two lines are on stdout. Every argument list is parseable: an unrecognised
#      token is ignored, exactly as Step 0 always ignored it.
#   2  bad invocation. NO INPUT REACHES IT — there is no argument list this script can refuse —
#      so the code is documented and unused rather than given an invented use. Do not repurpose.
#   3  COULD NOT RUN. Likewise unreachable from inside: nothing is read, nothing is called. The
#      only "did not run" state that exists is this file being absent, which only the CALLER can
#      observe, and Step 0's own resolution branch reports it there with exit 3. There is no safe
#      default it could take instead: `false` would prompt a human who is not present (the #329
#      class), `true` would run an entire roadmap unattended when nobody asked for that.
#
#   It never prints a `CLEAN` sentinel and must never grow one — it is a parser, not a reporter.
#   Nothing is written anywhere.
#
# TWO INHERITED BEHAVIOURS, PRESERVED DELIBERATELY. `--fork-from` as the last token leaves the
# ref EMPTY rather than failing: the fence read one past the end of an argument list, which in a
# shell without `set -u` is an empty string, so the `:-` defaults below reproduce that exactly
# rather than "hardening" it into a new refusal Step 0's callers have never had to handle. And
# the scan is independent of the first token, so a `--fork-from` passed in attended mode is still
# picked up — again as before.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no here-strings.
set -u

# Roadmap-autopilot mode (ADR-0022): set by the `autopilot` argument.
_autopilot=false
[ "${1:-}" = "autopilot" ] && _autopilot=true

# --fork-from <ref> (issue #364, ADR-0127 §D4): the base every feature branch is created from.
# Empty in attended mode and on any run that does not pass it, which is exactly today's behaviour.
_fork_from=""
_i=1; for _a in "$@"; do
  [ "$_a" = "--fork-from" ] && { _i=$((_i+1)); eval "_fork_from=\${$_i:-}"; break; }
  _i=$((_i+1))
done

printf 'autopilot=%s\n' "$_autopilot"
printf 'fork_from=%s\n' "$_fork_from"

exit 0
