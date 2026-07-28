#!/bin/bash
# worktree-isolation-contract.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash worktree-isolation-contract.test.sh
#
# Covers issue #176 / ADR-0068, Task 2 only (R-01, R-11, R-19). This file grows further with
# Tasks 4, 5, 6, 7 and 8 of the same plan; sections C onward do not exist yet.
#
# Task 2's EXPECTED result, seen once and recorded here so a future reader does not mistake a
# checkpoint for fix evidence: sections A and B are RED (the two bad `isolation: "none"` /
# `isolation: none` prescriptions and the dirty-tree condition blocks still exist in this
# codebase — Task 3 removes them). Sections A2, A3 and B2 are GREEN from the start: they are
# forward guards proving the detectors themselves work, not proof that the defect is fixed.
#
# Section A is an ALLOWLIST over discovered `isolation` values (worktree|remote), never a
# denylist of `none` — a denylist cannot see the next invented value (the ADR-0043 direction
# lesson, applied at the schema level). Section B anchors on the compound phrase surrounding
# each dirty-tree isolation-selection block, never on the bare `git diff HEAD --name-only`,
# which legitimately survives in review-triage-fix/SKILL.md (ADR-0068 §D9) for an unrelated
# reason (stale-worktree pre-check, not isolation selection) — section B2 is the positive twin
# proving that survival is intentional, not an oversight this file failed to notice.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
AB="$STAGING/plugin/skills/autopilot-build/SKILL.md"
RTF="$STAGING/plugin/skills/review-triage-fix/SKILL.md"

# ==============================================================================================
# Shared extractor for section A. Matches `isolation:` followed (after optional space and an
# optional `"` or `<`) by an alpha token — this single pattern reaches every prescription form
# seen in this codebase: `isolation: worktree`, `isolation: "none"`, `isolation:none` (a heading),
# and the templated `isolation: <none if ISOLATION_MODE=none, else worktree>`. It is deliberately
# NOT anchored on `none` anywhere — see the module docstring above.
# ==============================================================================================
extract_isolation_values() {
  grep -ohE 'isolation:[[:space:]]*["<]?[A-Za-z_]+' "$1" 2>/dev/null \
    | sed -E 's/^isolation:[[:space:]]*["<]?//'
}

# ==============================================================================================
# Section A — schema conformance (R-01). Allowlist over discovered values, count-guarded.
# ==============================================================================================
ALL_VALUES="$TMP/all-isolation-values.txt"
: > "$ALL_VALUES"
for f in "$STAGING"/plugin/skills/*/SKILL.md "$STAGING"/plugin/agents/*.md; do
  [ -f "$f" ] || continue
  extract_isolation_values "$f" >> "$ALL_VALUES"
done

VALUE_COUNT=$(grep -c . "$ALL_VALUES" 2>/dev/null || true)
case "$VALUE_COUNT" in ''|*[!0-9]*) VALUE_COUNT=0 ;; esac
if [ "$VALUE_COUNT" -ge 1 ]; then
  ok "A0: at least one isolation value was discovered across staging/ (count=$VALUE_COUNT) — the extractor is not vacuous"
else
  bad "A0: zero isolation values discovered — the extractor is broken and every assertion below is meaningless"
fi

BAD_VALUES=$(grep -vE '^(worktree|remote)$' "$ALL_VALUES" 2>/dev/null | sort -u)
if [ -z "$BAD_VALUES" ]; then
  ok "A1: every discovered isolation value is one of worktree|remote"
else
  bad "A1: non-conforming isolation value(s) found (Agent tool rejects these): $(printf '%s' "$BAD_VALUES" | tr '\n' ' ')"
fi

# ==============================================================================================
# Section A2 — positive twin (forward guard, green from the start). Without this, a regex that
# matches nothing would pass section A for the wrong reason (the cfile=/dev/null lesson).
# ==============================================================================================
CODER_MD="$STAGING/plugin/agents/coder.md"
CODER_VALUES=$(extract_isolation_values "$CODER_MD")
if printf '%s\n' "$CODER_VALUES" | grep -qx 'worktree'; then
  ok "A2 (forward guard): the extractor actually finds 'worktree' on agents/coder.md:8"
else
  bad "A2 (forward guard): the extractor found no 'worktree' value on agents/coder.md — it is not extracting real prescriptions"
fi

# ==============================================================================================
# Section A3 — synthetic invented value (forward guard, green from the start). Proves section A
# is a forward guard against the NEXT invented value, not merely a record of today's two bad
# ones (`none`, and its `<none if ...>` templated form).
# ==============================================================================================
FIXTURE_A3="$TMP/fixture-a3.md"
printf 'fixture frontmatter\nisolation: sandbox\nend fixture\n\nSome prose that never says the word.\n' > "$FIXTURE_A3"
A3_VALUES=$(extract_isolation_values "$FIXTURE_A3")
A3_BAD=$(printf '%s\n' "$A3_VALUES" | grep -vE '^(worktree|remote)$' 2>/dev/null)
if [ -n "$A3_BAD" ]; then
  ok "A3 (forward guard): a fixture naming 'isolation: sandbox' is correctly flagged as non-conforming"
else
  bad "A3 (forward guard): the invented value 'sandbox' was NOT flagged — section A cannot see a future invented value"
fi

# ==============================================================================================
# Section B — dirty-tree retirement (R-11). Anchored on the compound phrase surrounding each
# isolation-selection block, never on the bare `git diff HEAD --name-only` (ADR-0068 §D9).
# Three call sites: concept-to-code's Workflow-path block, concept-to-code's Agent-tool-fallback
# block, and autopilot-build's restatement.
# ==============================================================================================
if grep -qF 'Non-empty output → dispatch that task group'"'"'s coder **with** `isolation: "none"`' "$CC" 2>/dev/null; then
  bad "B1: concept-to-code Workflow-path dirty-tree isolation-selection block still present"
else
  ok "B1: concept-to-code Workflow-path dirty-tree isolation-selection block is gone"
fi

if grep -qF 'Non-empty output → dispatch this batch'"'"'s coder **with** `isolation: "none"`' "$CC" 2>/dev/null; then
  bad "B1b: concept-to-code Agent-tool-fallback dirty-tree isolation-selection block still present"
else
  ok "B1b: concept-to-code Agent-tool-fallback dirty-tree isolation-selection block is gone"
fi

if grep -qF 'dispatch that group'"'"'s coder with `isolation: "none"`' "$AB" 2>/dev/null; then
  bad "B1c: autopilot-build dirty-tree isolation-selection block still present"
else
  ok "B1c: autopilot-build dirty-tree isolation-selection block is gone"
fi

# ==============================================================================================
# Section B2 — D9 guard (forward guard, green from the start). review-triage-fix's stale-worktree
# pre-check greps the identical `git diff HEAD --name-only` command but selects dispatch-versus-
# inline, not one isolation value versus another (ADR-0068 §D9), and must SURVIVE. A test that
# removes too much is the failure mode this section exists to catch.
# ==============================================================================================
if grep -qF 'Stale-worktree pre-check' "$RTF" 2>/dev/null && grep -qF 'git -C <root> diff HEAD --name-only' "$RTF" 2>/dev/null; then
  ok "B2 (forward guard / D9): review-triage-fix's stale-worktree pre-check still contains its git diff HEAD --name-only check"
else
  bad "B2 (forward guard / D9): review-triage-fix's stale-worktree pre-check is missing or its git diff HEAD --name-only check is gone — ADR-0068 §D9 requires this block to survive"
fi

# ==============================================================================================
# CI registration (R-19): both registries.
# ==============================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
CIYML="$REPO/.github/workflows/ci.yml"

DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]worktree-isolation-contract[[:space:];]'; then
  ok "CI1: docs-ci.yml's shell-tests loop list runs worktree-isolation-contract"
else
  bad "CI1: worktree-isolation-contract is not in docs-ci.yml's explicit harness list"
fi

if grep -qF 'staging/plugin/scripts/tests/*.test.sh' "$CIYML" 2>/dev/null; then
  ok "CI2: ci.yml still runs the automatic glob over staging/plugin/scripts/tests/*.test.sh (forward guard — no manual edit needed there)"
else
  bad "CI2: ci.yml no longer uses the automatic *.test.sh glob"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
