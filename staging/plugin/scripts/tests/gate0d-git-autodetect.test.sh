#!/bin/bash
# gate0d-git-autodetect.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Run: bash gate0d-git-autodetect.test.sh
#
# Issue #407. Gate 0d's Step 0 (`concept-to-code/references/hitl-gates.md`) probes the project's
# git state with `_git_ok=$(git ... rev-parse --is-inside-work-tree ... && echo "yes" || echo
# "no")`. `rev-parse --is-inside-work-tree` prints `true` on its OWN stdout on success — without a
# stdout redirect on the probed command, the substitution captured "true\nyes", never the bare
# "yes" every downstream branch compares against. So Outcome C (`_git_ok=no`) was reachable and
# Outcomes A/B (`_git_ok=yes`) were not: every chain run inside a git repo fell through to the full
# four-question survey, even with a remote already configured.
#
# This harness extracts the exact two-line probe out of hitl-gates.md (never re-typed — a copy
# that drifts from the real fence would pass while the real fence stays broken) and runs it against
# three fixture directories, one per outcome.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
GATES="$STAGING/plugin/skills/concept-to-code/references/hitl-gates.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

git_init() {
  ( cd "$1" && git init -q && git -c user.email=a@b.c -c user.name=t commit -q --allow-empty -m init ) >/dev/null 2>&1
}

# Extract the exact probe body: everything between "Step 0 — Git auto-detect" and the closing
# ``` fence, minus the ```bash opener/closer and comment lines — a real extraction of the shipped
# fence, not a hand-typed copy of it (rule 1: the needle belongs to the mechanism it asserts about).
extract_probe() {
  awk '
    /^Run the following bash to probe the project.?s existing git state:/ { armed=1; next }
    armed && /^```bash/ { infence=1; next }
    infence && /^```/ { exit }
    infence && $0 !~ /^#/ && $0 !~ /^_git_root=/ { print }
  ' "$GATES"
}

PROBE=$(extract_probe)
if [ -z "$PROBE" ]; then
  echo "DID NOT RUN: could not extract the git auto-detect probe from hitl-gates.md — extraction anchor may have drifted"
  exit 3
fi
if ! printf '%s\n' "$PROBE" | grep -q '_git_ok='; then
  echo "DID NOT RUN: extracted body does not contain _git_ok= — extraction anchor may have drifted"
  exit 3
fi

run_probe() {
  # run_probe <root> -> prints "_git_ok=<v>|_git_remote=<v>"
  _r="$1"
  _s="$TMP/run.sh"
  { printf '_git_root=%s\n' "$(printf '%q' "$_r")"; printf '%s\n' "$PROBE"; \
    printf 'printf "%%s|%%s" "$_git_ok" "$_git_remote"\n'; } >"$_s"
  bash "$_s"
}

# ==================================================================================================
# GA1 — Outcome A: git repo with a remote configured -> _git_ok=yes, _git_remote populated.
# ==================================================================================================
A_DIR="$TMP/a"; mkdir -p "$A_DIR"; git_init "$A_DIR"
( cd "$A_DIR" && git remote add origin https://example.invalid/repo.git ) >/dev/null 2>&1
_out=$(run_probe "$A_DIR")
if [ "$_out" = "yes|https://example.invalid/repo.git" ]; then
  ok "GA1: git repo with remote -> _git_ok=yes, _git_remote populated (Outcome A reachable)"
else
  bad "GA1: expected 'yes|https://example.invalid/repo.git', got '$_out'"
fi

# ==================================================================================================
# GA2 — Outcome B: git repo, no remote -> _git_ok=yes, _git_remote empty.
# ==================================================================================================
B_DIR="$TMP/b"; mkdir -p "$B_DIR"; git_init "$B_DIR"
_out=$(run_probe "$B_DIR")
if [ "$_out" = "yes|" ]; then
  ok "GA2: git repo, no remote -> _git_ok=yes, _git_remote empty (Outcome B reachable)"
else
  bad "GA2: expected 'yes|', got '$_out'"
fi

# ==================================================================================================
# GA3 — Outcome C: no git repo at all -> _git_ok=no.
# ==================================================================================================
C_DIR="$TMP/c"; mkdir -p "$C_DIR"
_out=$(run_probe "$C_DIR")
if [ "$_out" = "no|" ]; then
  ok "GA3: no git repo -> _git_ok=no (Outcome C still reachable, R-03)"
else
  bad "GA3: expected 'no|', got '$_out'"
fi

# ==================================================================================================
# GA4 — THE BUG (issue #407, R-04): the un-redirected form of the probe never equals 'yes', even
# inside a real git repo with a remote — this is what made Outcome A/B unreachable.
# plant: GA4 | plugin/skills/concept-to-code/references/hitl-gates.md | rev-parse --is-inside-work-tree >/dev/null 2>&1 | rev-parse --is-inside-work-tree 2>/dev/null
# ==================================================================================================
_out=$(run_probe "$A_DIR")
_ok="${_out%%|*}"
if [ "$_ok" = "yes" ]; then
  ok "GA4: the live probe reads _git_ok=yes inside a real git+remote repo (issue #407 regression pin)"
else
  bad "GA4: expected _git_ok=yes, got '$_ok' — the stdout-leak bug (issue #407) has returned"
fi

# ==================================================================================================
# Z1 — assertion-count floor (rule 10: a vacuity guard, not the primary check).
# ==================================================================================================
Z1_FLOOR=4
if [ "$((PASS + FAIL))" -ge "$Z1_FLOOR" ]; then
  ok "Z1: assertion count $((PASS + FAIL)) >= floor $Z1_FLOOR"
else
  bad "Z1: assertion count $((PASS + FAIL)) < floor $Z1_FLOOR — assertions vanished"
fi

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
