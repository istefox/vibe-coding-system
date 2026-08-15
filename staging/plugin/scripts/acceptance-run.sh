#!/bin/bash
# acceptance-run v1.0 (issue #439, ADR-0141). Runs a project's acceptance suite and reports one
# verdict per requirement id. This is the layer the chain never had: the gates check that tests are
# green, that ids are CITED and that the diff fits a budget, and ADR-0138 established that citation
# is not implementation. Here an `R-NN` passes only by being EXECUTED and observed.
#
# Usage: acceptance-run.sh [--root <dir>] [--declared <ACCEPTANCE.md>] [--adapter <path>]
#
# THIS IS A REPORTER, NOT A CHECKER, exactly like acceptance-adapter-swift.sh: exit 0 on any
# determined outcome, exit 2 only when the invocation itself was wrong. See that file's header for
# the full contract and the caller idiom. A failing suite is a RESULT, not an error — it is the
# whole point — so the process exit code of the acceptance command is deliberately NOT propagated.
#
#   THE CALLER IDIOM:
#     out=$(acceptance-run.sh --declared ACCEPTANCE.md) || { bad invocation; }
#     case "$out" in *'ACCEPTANCE-HALT'*) halt the caller ;; esac    # HALT FIRST
#     printf '%s\n' "$out" | grep '^ACCEPTANCE-RESULT '
#   NEVER `[ -n "$out" ]`.
#
# THE RESULT BUNDLE. This script exports ACCEPTANCE_RESULT_BUNDLE and the acceptance command is
# expected to write its Xcode result bundle there, e.g.
#     xcodebuild test -scheme MyApp-Package -destination 'platform=macOS' \
#       -resultBundlePath "$ACCEPTANCE_RESULT_BUNDLE"
# That expectation is an INSTRUCTION and cannot be enforced (rule 16). The ENFORCEMENT half is that
# a missing bundle halts loudly instead of reporting an empty pass — a command that ignores the
# variable is detected, it is simply detected after the fact rather than prevented.
#
# TRUST. `.claude/acceptance-cmd` is TOFU-gated through the SAME registry and the same
# `<sha256>\t<normalized-root>` line as `.claude/test-cmd`, resolved by the same upward walk.
# CONSEQUENCE, declared rather than left to be discovered: two files with IDENTICAL CONTENT produce
# an IDENTICAL trust line, so approving one approves the other. What TOFU reviews is the command,
# not the filename, and that is the intended reading — but a reader assuming per-file approval
# would be wrong. `approve-acceptance-cmd.sh` registers; this script only ever reads.
#
# `NONE` in the file is an opt-out, and an opt-out HALTS rather than reporting a clean run. That is
# the deliberate difference from `.claude/test-cmd`, where NONE exits 0 quietly: a silent acceptance
# opt-out would read as "every criterion passed" to any caller that only greps ACCEPTANCE-RESULT.
#
# Bash 3.2 clean.
set -u

SELF="acceptance-run"
ROOT_ARG=""; DECLARED=""; ADAPTER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root)     ROOT_ARG="${2:-}"; shift 2 ;;
    --declared) DECLARED="${2:-}"; shift 2 ;;
    --adapter)  ADAPTER="${2:-}";  shift 2 ;;
    -h|--help)
      printf 'usage: %s [--root <dir>] [--declared <ACCEPTANCE.md>] [--adapter <path>]\n' "$SELF"
      exit 0 ;;
    *) printf '%s: unknown argument: %s\n' "$SELF" "$1" >&2; exit 2 ;;
  esac
done

halt() { printf 'ACCEPTANCE-HALT %s\n' "$1"; exit 0; }

CWD="${ROOT_ARG:-$PWD}"
[ -d "$CWD" ] || { printf '%s: not a directory: %s\n' "$SELF" "$CWD" >&2; exit 2; }
CWD=$(cd "$CWD" 2>/dev/null && pwd) || { printf '%s: cd failed\n' "$SELF" >&2; exit 2; }

# Same walk as stop-gate.sh, and deliberately the same shape: one walk finds the file, so a monorepo
# cannot resolve the command at one root and the trust at another.
ROOT=""; d="$CWD"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -f "$d/.claude/acceptance-cmd" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done
[ -z "$ROOT" ] && halt "no-acceptance-cmd — no .claude/acceptance-cmd found ascending from $CWD"

ACF="$ROOT/.claude/acceptance-cmd"
[ -r "$ACF" ] || halt "acceptance-cmd-unreadable — $ACF exists and cannot be read"
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$ACF" 2>/dev/null)

[ -z "$CMD" ] && halt "acceptance-cmd-empty — $ACF has no command line, which is not the same as an opt-out"
[ "$CMD" = "NONE" ] && halt "opted-out — $ACF declares NONE, so no criterion was measured"

# --- TOFU -----------------------------------------------------------------------------------------
# norm_path and the hash order mirror approve-test-cmd.sh exactly: hash the case-PRESERVING path
# that actually resolves on disk, normalise only for the case-invariant registry lookup (issue #38).
norm_path() {
  p=$(cd "$1" 2>/dev/null && pwd -P) || { printf '%s' "$1"; return 0; }
  sys="${STOP_GATE_UNAME:-$(uname)}"
  [ "$sys" = "Darwin" ] && p=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$p"
}
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else return 1; fi
}
TRUST="${STOP_GATE_TRUST_FILE:-${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}/trust}"

H=$(sha256_of "$ACF") || halt "no-sha256-tool — trust cannot be established, so the command is not run"
[ -z "$H" ] && halt "hash-failed — empty digest for $ACF, so the command is not run"
LINE=$(printf '%s\t%s' "$H" "$(norm_path "$ROOT")")
if ! { [ -f "$TRUST" ] && grep -F -x -q -- "$LINE" "$TRUST" 2>/dev/null; }; then
  halt "untrusted — review $ACF then run: bash ~/.claude/hooks/approve-acceptance-cmd.sh \"$ROOT\""
fi

# --- run ------------------------------------------------------------------------------------------
command -v xcrun >/dev/null 2>&1 || halt "xcrun-absent — this adapter needs Xcode command line tools"

TMP=$(mktemp -d) || { printf '%s: mktemp failed\n' "$SELF" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
BUNDLE="$TMP/acceptance.xcresult"
ACCEPTANCE_RESULT_BUNDLE="$BUNDLE"; export ACCEPTANCE_RESULT_BUNDLE

( cd "$ROOT" && eval "$CMD" ) >"$TMP/cmd.out" 2>&1
# Exit status intentionally unused: a red suite is a RESULT. Its output is kept for the halt paths
# below, where the operator needs to see why nothing could be measured.

[ -e "$BUNDLE" ] || halt "no-result-bundle — the command did not write \$ACCEPTANCE_RESULT_BUNDLE; last output: $(tail -3 "$TMP/cmd.out" 2>/dev/null | tr '\n' ' ' | cut -c1-160)"

# --schema-version is PINNED. A future Xcode that bumps its default must fail here, visibly, rather
# than hand the adapter a shape it will silently misread.
xcrun xcresulttool get test-results tests --path "$BUNDLE" --schema-version 0.1.0 \
  >"$TMP/tests.json" 2>"$TMP/xcr.err" \
  || halt "xcresulttool-failed — $(tr '\n' ' ' <"$TMP/xcr.err" | cut -c1-160)"

# READABLE, not executable. The adapter is invoked as `bash <path>`, so the execute bit is not the
# thing that governs whether it can run — and staging/ is inconsistent about it (stop-gate.sh is
# 755, dispatch-state.sh is 644), so an -x probe here resolves nothing in a source checkout while
# working fine after sync-to-claude.sh chmods the deployed copy. Found by the first end-to-end run,
# not reasoned about: testing for the wrong permission bit is a check that agrees with itself.
if [ -z "$ADAPTER" ]; then
  _here=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
  for c in "$_here/acceptance-adapter-swift.sh" "$HOME/.claude/hooks/acceptance-adapter-swift.sh"; do
    [ -r "$c" ] && { ADAPTER="$c"; break; }
  done
fi
[ -n "$ADAPTER" ] && [ -r "$ADAPTER" ] || halt "adapter-not-found — acceptance-adapter-swift.sh is not resolvable"

if [ -n "$DECLARED" ]; then
  bash "$ADAPTER" --json-file "$TMP/tests.json" --declared "$DECLARED"
else
  bash "$ADAPTER" --json-file "$TMP/tests.json"
fi
exit 0
