#!/bin/bash
# external-dependency-check v1.0 (issue #114, ADR-0060) — G13, the external-dependency
# feasibility gate.
#
# CONTRACT. This is a CHECKER, exactly like spec-coverage.sh (ADR-0048): the exit code is the
# policy channel — unlike weakening-scan.sh / dependency-scan.sh at the commit-time gates, which
# are REPORTERS that always exit 0 and signal through stdout only. Do not copy one idiom into the
# other.
#   exit 0  every declared dependency is provisioned: true, OR none were declared at all
#           (ADR-0060 §D5 — absent means nobody said, not that none exist; the gate is inert)
#   exit 1  at least one declared dependency is not provisioned   stdout: UNCOVERED lines below,
#           stderr: one human-readable action line per unmet dependency
#   exit 2  invalid invocation                                    stdout: nothing
#
# INPUT. Lines matching:
#   EXTERNAL DEPENDENCY: <name> | <kind> | provisioned: <true|false|unknown>
# read from --file <path> or stdin. Every other line is ignored — this lets the caller pipe an
# architect's whole report or plan file through unfiltered. `unknown` and any unrecognised value
# are treated as NOT provisioned (default strict, per the SPEC's own edge case): a gate that can
# usefully answer "is it already provisioned" (ADR-0060 §D2) cannot treat "I don't know" as yes.
#
# WHAT THIS DOES NOT DO. It never checks whether a credential COULD be provisioned, never attempts
# a provisioning flow, and never retries — ADR-0060 §D2 is explicit that an unattended agent
# cannot complete a consent flow, so the remedy this script names on stderr is always a human
# action, never "try again".
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    *) echo "external-dependency-check: unknown arg $1" >&2; exit 2 ;;
  esac
done

if [ -n "$FILE" ]; then
  [ -f "$FILE" ] || { echo "external-dependency-check: no such file: $FILE" >&2; exit 2; }
  INPUT="$(cat "$FILE")"
else
  INPUT="$(cat)"
fi

LINES="$(printf '%s\n' "$INPUT" | grep '^EXTERNAL DEPENDENCY: ')"

# No declarations at all: inert (§D5). Silent on both streams — an absent declaration is the
# pre-feature behaviour, not a finding.
if [ -z "$LINES" ]; then
  exit 0
fi

TMP_UNMET="$(mktemp)"
trap 'rm -f "$TMP_UNMET"' EXIT

OLDIFS="$IFS"
IFS='
'
for _line in $LINES; do
  IFS="$OLDIFS"
  # Strip the leading literal, then split on ' | '.
  _rest="${_line#EXTERNAL DEPENDENCY: }"
  _name="$(printf '%s' "$_rest" | awk -F' \\| ' '{print $1}' | sed 's/^ *//;s/ *$//')"
  _kind="$(printf '%s' "$_rest" | awk -F' \\| ' '{print $2}' | sed 's/^ *//;s/ *$//')"
  _prov_raw="$(printf '%s' "$_rest" | awk -F' \\| ' '{print $3}' | sed 's/^ *//;s/ *$//')"
  # Third field is "provisioned: <state>" — take whatever follows the colon, lowercased.
  _state="$(printf '%s' "$_prov_raw" | sed 's/^provisioned: *//' | tr '[:upper:]' '[:lower:]' | sed 's/^ *//;s/ *$//')"

  [ -z "$_name" ] && _name="(unnamed)"
  [ -z "$_kind" ] && _kind="(unspecified)"

  if [ "$_state" != "true" ]; then
    [ -z "$_state" ] && _state="unknown"
    printf 'UNMET\t%s\t%s\t%s\n' "$_name" "$_kind" "$_state" >> "$TMP_UNMET"
  fi
  IFS='
'
done
IFS="$OLDIFS"

if [ -s "$TMP_UNMET" ]; then
  TMP_SORTED="$(mktemp)"
  sort "$TMP_UNMET" > "$TMP_SORTED"
  cat "$TMP_SORTED"
  while IFS="$(printf '\t')" read -r _tag _name _kind _state; do
    [ "$_tag" = "UNMET" ] || continue
    printf 'external-dependency-check: %s (%s) is not provisioned (state: %s) — this requires a\n' \
      "$_name" "$_kind" "$_state" >&2
    printf '  human action (create the credential, complete the consent flow, provision the\n' >&2
    printf '  resource) before this feature can be dispatched unattended. Not a retry — ADR-0060 §D2.\n' >&2
  done < "$TMP_SORTED"
  rm -f "$TMP_SORTED"
  exit 1
fi

exit 0
