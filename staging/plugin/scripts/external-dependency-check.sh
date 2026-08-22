#!/bin/bash
# external-dependency-check v1.1 (issue #114, ADR-0060; issue #473, ADR-0164) — G13, the
# external-dependency feasibility gate.
#
# CONTRACT. This is a CHECKER, exactly like spec-coverage.sh (ADR-0048): the exit code is the
# policy channel — unlike weakening-scan.sh / dependency-scan.sh at the commit-time gates, which
# are REPORTERS that always exit 0 and signal through stdout only. Do not copy one idiom into the
# other.
#   exit 0  every declared dependency is provisioned: true AND (verified true, OR its kind is
#           unverifiable), OR none were declared at all
#           (ADR-0060 §D5 — absent means nobody said, not that none exist; the gate is inert)
#   exit 1  at least one declared dependency is not provisioned, OR is declared true but a
#           verifiable kind's probe finds it absent    stdout: UNMET/UNVERIFIED lines below,
#           stderr: one human-readable action line per unmet dependency
#   exit 2  invalid invocation                                    stdout: nothing
#
# INPUT. Lines matching:
#   EXTERNAL DEPENDENCY: <name> | <kind> | provisioned: <true|false|unknown>
# read from --file <path> or stdin. Every other line is ignored — this lets the caller pipe an
# architect's whole report or plan file through unfiltered. `unknown` and any unrecognised
# PROVISIONED value are treated as NOT provisioned (default strict, per the SPEC's own edge case):
# a gate that can usefully answer "is it already provisioned" (ADR-0060 §D2) cannot treat "I don't
# know" as yes.
#
# VERIFICATION (issue #473). A dependency declared `provisioned: true` is no longer trusted on the
# strength of the sentence alone for a KIND this script knows how to probe. `<kind>` is a dispatch
# key:
#   env     <name> is an environment variable name — checked with `printenv <name>`
#   binary  <name> is a command name — checked with `command -v`
#   file    <name> is a path — checked with `[ -e ]`
#   port    <name> is a TCP port number on localhost — checked with `lsof` if available
# Any other kind — including `oauth-consent` and `vendor-account`, the two ADR-0060 §D2 names as
# genuinely unattainable unattended — is UNVERIFIABLE: the declaration is trusted, and that trust
# is reported on stdout as an `UNVERIFIED` line rather than silently folded into a clean exit 0.
# A dependency already declared NOT provisioned (`false`/`unknown`/anything else) is unmet
# regardless of kind and is never probed — there is nothing to verify about a claim not made.
#
# WHAT THIS DOES NOT DO. It never checks whether a credential COULD be provisioned, never attempts
# a provisioning flow, and never retries — ADR-0060 §D2 is explicit that an unattended agent
# cannot complete a consent flow, so the remedy this script names on stderr is always a human
# action, never "try again". For a VERIFIABLE kind it now does check whether the declared state
# matches the world; for an unverifiable kind it still does not, and says so on stdout rather than
# leaving that silence indistinguishable from a verified pass.
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
TMP_UNVERIFIED="$(mktemp)"
trap 'rm -f "$TMP_UNMET" "$TMP_UNVERIFIED"' EXIT

# probe_kind <kind> <name> — issue #473. Called ONLY when the declaration itself says `true`; a
# dependency already declared false/unknown is unmet regardless and there is nothing to verify
# about a claim not made. Returns 0 = verified present, 1 = verifiable kind, probe found it absent,
# 2 = this kind is not one this script knows how to probe (unverifiable, trust the declaration).
probe_kind() {
  case "$1" in
    env)    printenv "$2" >/dev/null 2>&1 ;;
    binary) command -v "$2" >/dev/null 2>&1 ;;
    file)   [ -e "$2" ] ;;
    port)
      if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$2" -sTCP:LISTEN >/dev/null 2>&1
      else
        return 2   # lsof absent — cannot probe on THIS machine; do not report a false absence
      fi
      ;;
    *) return 2 ;;
  esac
  _rc=$?
  [ "$_rc" -eq 0 ] && return 0
  return 1
}

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
  else
    # Declared true — verify it, for a kind this script knows how to probe (issue #473).
    if probe_kind "$_kind" "$_name"; then
      : # verified present — clean, nothing to report
    else
      _probe_rc=$?
      if [ "$_probe_rc" -eq 2 ]; then
        printf 'UNVERIFIED\t%s\t%s\tdeclared-true\n' "$_name" "$_kind" >> "$TMP_UNVERIFIED"
      else
        printf 'UNMET\t%s\t%s\tdeclared-true-absent\n' "$_name" "$_kind" >> "$TMP_UNMET"
      fi
    fi
  fi
  IFS='
'
done
IFS="$OLDIFS"

_rc_final=0
if [ -s "$TMP_UNVERIFIED" ]; then
  sort "$TMP_UNVERIFIED"
fi
if [ -s "$TMP_UNMET" ]; then
  TMP_SORTED="$(mktemp)"
  sort "$TMP_UNMET" > "$TMP_SORTED"
  cat "$TMP_SORTED"
  while IFS="$(printf '\t')" read -r _tag _name _kind _state; do
    [ "$_tag" = "UNMET" ] || continue
    if [ "$_state" = "declared-true-absent" ]; then
      printf 'external-dependency-check: %s (%s) was declared provisioned: true but the probe finds\n' \
        "$_name" "$_kind" >&2
      printf '  it absent — the declaration and the world disagree. Provision it, or correct the\n' >&2
      printf '  declaration if it was written in error. Not a retry — ADR-0060 §D2.\n' >&2
    else
      printf 'external-dependency-check: %s (%s) is not provisioned (state: %s) — this requires a\n' \
        "$_name" "$_kind" "$_state" >&2
      printf '  human action (create the credential, complete the consent flow, provision the\n' >&2
      printf '  resource) before this feature can be dispatched unattended. Not a retry — ADR-0060 §D2.\n' >&2
    fi
  done < "$TMP_SORTED"
  rm -f "$TMP_SORTED"
  _rc_final=1
fi

exit "$_rc_final"
