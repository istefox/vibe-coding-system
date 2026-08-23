#!/bin/bash
# scope-file-read.sh v1.0 — report whether a preserved `scope` file is REUSABLE or SPENT at
# relaunch (issue #400, ADR-0167 §D6).
#
# IT IS A REPORTER (rule 5). It always exits 0 on every state of the FILE it was asked about, and
# signals through stdout key=value lines alone — never through the exit code. The CHECKER three
# lines above this script's call site in Phase S's calling fence is the OPPOSITE idiom
# (`scope-args-parse.sh`, whose own header names itself a parser, not a reporter): branched on by
# exit code. Do not read the two the same way.
#
# "I could not read the file" is a fact about the INPUT this script was asked to report on, not a
# failure to run (ADR-0076) — so UNREADABLE is a printed state, exit 0, same as every other state.
# This script never exits 3.
#
# USAGE
#   scope-file-read.sh <project-root>
#
# OUTPUT — five key=value lines, in this order:
#   state=ABSENT|REUSABLE|SPENT|NOT-REUSABLE|MALFORMED|UNREADABLE
#   source=<value from the file, or empty>
#   features=<validated non-negative integer, or empty>
#   only_count=<count of only= lines, 0 if none>
#   delivered=<count of non-blank lines in published, 0 if absent>
#
#   ABSENT is this reporter's CLEAN (rule 5): it prints state=ABSENT rather than nothing, so a
#   caller writing `[ -n "$out" ]` cannot mistake "no file" for "some state".
#
# STATE DEFINITIONS (ADR-0167 §D6). Three states for "the file could not be trusted", never two
# (rule 11, ADR-0076): ABSENT, MALFORMED and UNREADABLE stay distinct branches.
#   ABSENT        no scope file at all.
#   UNREADABLE    the file exists and `[ ! -r ]`.
#   MALFORMED     readable, but no `source=` line, or a `source=` value outside
#                 arguments|marker|none, or `source=arguments` with neither a usable `features=`
#                 nor any `only=` line.
#   REUSABLE      `source=arguments`, and the bound is not yet satisfied.
#   SPENT         `source=arguments`, and `delivered` already satisfies the bound.
#   NOT-REUSABLE  `source=marker` or `source=none`.
#
# SPENT/REUSABLE, EXACTLY AS conductor-scope-gate COMPUTES EXHAUSTION (rule 17). `features` is
# validated with `case "$_f" in ''|*[!0-9]*)`, byte-identical to conductor-scope-gate's own guard
# and to scope-args-parse.sh's neighbouring convention, so the differential test in
# autopilot-disarm-scope-preserve.test.sh's DP21 compares two implementations of ONE rule, not two
# different rules. `delivered` is `grep -c .` over `published`, 0 when absent. The bound is
# satisfied — SPENT — when `features` is usable and `delivered >= features`; when `features` is
# not usable but `only=` rows exist, it is satisfied when `delivered >= <count of only= rows>` —
# "every only= row already appears in published", restated as a count comparison because `only=`
# holds the roadmap row's exact TITLE text (ADR-0129 §D2) while `published` holds topic SLUGS, and
# the two strings are never comparable. These are TWO COPIES of one comparison
# (this script, and conductor-scope-gate's own fence body) — ADR-0167 §D6 keeps them separate on
# purpose and relies on DP21's differential test to keep them agreeing (rule 6). If a third copy of
# this comparison ever appears, extract it.
#
# EXIT CONTRACT
#   0  RAN. Every state above is reported on stdout. Never exit 3.
#   2  bad invocation: no root argument, or the given root is not a directory.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no [[ ]].
set -u

SELF="scope-file-read"

_root="${1:-}"
if [ -z "$_root" ] || [ ! -d "$_root" ]; then
  printf '%s: usage: scope-file-read.sh <project-root>\n' "$SELF" >&2
  exit 2
fi

_sf="$_root/.claude/autopilot-state/scope"
_pub="$_root/.claude/autopilot-state/published"

if [ -e "$_pub" ]; then
  _delivered=$(grep -c . "$_pub" 2>/dev/null) || true
  case "$_delivered" in
    ''|*[!0-9]*) _delivered=0 ;;
  esac
else
  _delivered=0
fi

_source=""
_features=""
_only_count=0

emit() {
  printf 'state=%s\n' "$1"
  printf 'source=%s\n' "$_source"
  printf 'features=%s\n' "$_features"
  printf 'only_count=%s\n' "$_only_count"
  printf 'delivered=%s\n' "$_delivered"
  exit 0
}

[ -e "$_sf" ] || emit "ABSENT"
[ -r "$_sf" ] || emit "UNREADABLE"

_source=$(grep '^source=' "$_sf" | sed 's/^source=//' | head -1)
_features=$(grep '^features=' "$_sf" | sed 's/^features=//' | head -1)
case "$_features" in
  ''|*[!0-9]*) _features="" ;;
esac
_only_count=$(grep -c '^only=' "$_sf" 2>/dev/null) || true
case "$_only_count" in
  ''|*[!0-9]*) _only_count=0 ;;
esac

case "$_source" in
  arguments|marker|none) ;;
  *) emit "MALFORMED" ;;
esac

[ "$_source" = "arguments" ] || emit "NOT-REUSABLE"

if [ -z "$_features" ] && [ "$_only_count" -eq 0 ]; then
  emit "MALFORMED"
fi

_exhausted=0
if [ -n "$_features" ]; then
  [ "$_delivered" -ge "$_features" ] && _exhausted=1
else
  [ "$_delivered" -ge "$_only_count" ] && _exhausted=1
fi

if [ "$_exhausted" = "1" ]; then
  emit "SPENT"
else
  emit "REUSABLE"
fi
