#!/bin/bash
# run-tests.sh — structural-anchor harness for deep-refactor SKILL.md
# Bash 3.2-clean: no assoc arrays, no mapfile, no ${v^^}, no <<<, no process substitution
# Uses ok/bad reporter idiom (same as enumerate-sources.test.sh and concept-to-code harness)
set -u

SKILL="$HOME/.claude/skills/deep-refactor/SKILL.md"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# Guard: SKILL.md must exist
if [ ! -f "$SKILL" ]; then
  printf 'FAIL: SKILL.md not found at %s\n' "$SKILL"
  FAIL=$((FAIL+1))
  printf -- '----\n'
  printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
  exit 1
fi

# ---------------------------------------------------------------------------
# (a) Four dimensions named
# ---------------------------------------------------------------------------
grep -q 'dead-code' "$SKILL" \
  && ok "dimensions: dead-code present" \
  || bad "dimensions: dead-code missing"

grep -qF '| `perf` | reviewer |' "$SKILL" \
  && ok "dimensions: perf present" \
  || bad "dimensions: perf missing"

grep -qF '| `structure` | reviewer |' "$SKILL" \
  && ok "dimensions: structure present" \
  || bad "dimensions: structure missing"

grep -q '"security"' "$SKILL" \
  && ok "dimensions: security present" \
  || bad "dimensions: security missing"

# ---------------------------------------------------------------------------
# (b) MANDATORY GUARD 1: @objc, dynamic, protocol-witness, report-only
# ---------------------------------------------------------------------------
grep -q '@objc' "$SKILL" \
  && ok "mandatory-guard-1: @objc present" \
  || bad "mandatory-guard-1: @objc missing"

grep -q 'dynamic' "$SKILL" \
  && ok "mandatory-guard-1: dynamic present" \
  || bad "mandatory-guard-1: dynamic missing"

grep -q 'protocol-witness\|protocol witness\|protocol_witness' "$SKILL" \
  && ok "mandatory-guard-1: protocol-witness present" \
  || bad "mandatory-guard-1: protocol-witness missing"

# report-only appears in guard 1 context (grep for the guard section)
grep -q 'Mandatory guard 1\|MANDATORY GUARD 1\|mandatory guard 1' "$SKILL" \
  && ok "mandatory-guard-1: guard 1 section present" \
  || bad "mandatory-guard-1: guard 1 section missing"

# ---------------------------------------------------------------------------
# (c) MANDATORY GUARD 2: async, DispatchQueue, Sendable, report-only
# ---------------------------------------------------------------------------
grep -q 'async' "$SKILL" \
  && ok "mandatory-guard-2: async present" \
  || bad "mandatory-guard-2: async missing"

grep -q 'DispatchQueue' "$SKILL" \
  && ok "mandatory-guard-2: DispatchQueue present" \
  || bad "mandatory-guard-2: DispatchQueue missing"

grep -q 'Sendable' "$SKILL" \
  && ok "mandatory-guard-2: Sendable present" \
  || bad "mandatory-guard-2: Sendable missing"

grep -q 'Mandatory guard 2\|MANDATORY GUARD 2\|mandatory guard 2' "$SKILL" \
  && ok "mandatory-guard-2: guard 2 section present" \
  || bad "mandatory-guard-2: guard 2 section missing"

# ---------------------------------------------------------------------------
# (d) Global circuit-breaker tag verbatim
# ---------------------------------------------------------------------------
grep -qF 'CIRCUIT BREAKER FIRED AT:' "$SKILL" \
  && ok "circuit-breaker: tag 'CIRCUIT BREAKER FIRED AT:' present verbatim" \
  || bad "circuit-breaker: tag 'CIRCUIT BREAKER FIRED AT:' missing"

# ---------------------------------------------------------------------------
# (e) Report-only fallback phrase for absent/RED baseline
# ---------------------------------------------------------------------------
grep -Eq 'report-only mode|report-only fallback' "$SKILL" \
  && ok "report-only-fallback: 'report-only mode' or 'report-only fallback' present" \
  || bad "report-only-fallback: phrase missing"

# ---------------------------------------------------------------------------
# (f) Dispatch split: hook_verified, Workflow, Agent-tool all appear
# ---------------------------------------------------------------------------
grep -q 'hook_verified' "$SKILL" \
  && ok "dispatch-split: hook_verified present" \
  || bad "dispatch-split: hook_verified missing"

grep -q 'Workflow' "$SKILL" \
  && ok "dispatch-split: Workflow present" \
  || bad "dispatch-split: Workflow missing"

grep -q 'Agent-tool' "$SKILL" \
  && ok "dispatch-split: Agent-tool present" \
  || bad "dispatch-split: Agent-tool missing"

# ---------------------------------------------------------------------------
# (g) Security always report-only — security AND report-only AND never/NEVER
# ---------------------------------------------------------------------------
grep -qi 'security' "$SKILL" \
  && ok "security-report-only: security dimension present" \
  || bad "security-report-only: security dimension missing"

grep -Eq 'Security.*report-only|security.*report-only|SECURITY.*report-only' "$SKILL" \
  && ok "security-report-only: security+report-only linkage present" \
  || bad "security-report-only: security+report-only linkage missing"

grep -Eq 'security.*[Nn][Ee][Vv][Ee][Rr]|Security.*[Nn][Ee][Vv][Ee][Rr]|[Nn][Ee][Vv][Ee][Rr].*security|[Nn][Ee][Vv][Ee][Rr].*auto-fix.*security|Security.*never auto-fix' "$SKILL" \
  && ok "security-report-only: never/NEVER + security present" \
  || bad "security-report-only: never/NEVER + security linkage missing"

# ---------------------------------------------------------------------------
# (h) Gate 0: AskUserQuestion present
# ---------------------------------------------------------------------------
grep -q 'Gate 0' "$SKILL" \
  && ok "gate-0: Gate 0 present" \
  || bad "gate-0: Gate 0 missing"

grep -q 'AskUserQuestion' "$SKILL" \
  && ok "gate-0: AskUserQuestion present in SKILL.md" \
  || bad "gate-0: AskUserQuestion missing"

# ---------------------------------------------------------------------------
# (i) Gate 1: AskUserQuestion present
# ---------------------------------------------------------------------------
grep -q 'Gate 1' "$SKILL" \
  && ok "gate-1: Gate 1 present" \
  || bad "gate-1: Gate 1 missing"

# AskUserQuestion verified above; confirm Gate 1 has its own AskUserQuestion block
# (search for Gate 1 then AskUserQuestion within a 30-line window via awk)
awk '/Gate 1/{found=1; count=0} found{count++; if(/AskUserQuestion/ && count<=30){print; exit}} count>30{found=0}' "$SKILL" \
  | grep -q 'AskUserQuestion' \
  && ok "gate-1: AskUserQuestion block within Gate 1 section" \
  || bad "gate-1: AskUserQuestion not found near Gate 1"

# ---------------------------------------------------------------------------
# (j) Gate 2 (commit gate): AskUserQuestion AND (commit OR Approve)
# ---------------------------------------------------------------------------
grep -q 'Gate 2' "$SKILL" \
  && ok "gate-2: Gate 2 present" \
  || bad "gate-2: Gate 2 missing"

awk '/Gate 2/{found=1; count=0} found{count++; if(/AskUserQuestion/ && count<=30){print; exit}} count>30{found=0}' "$SKILL" \
  | grep -q 'AskUserQuestion' \
  && ok "gate-2: AskUserQuestion present near Gate 2" \
  || bad "gate-2: AskUserQuestion not found near Gate 2"

grep -Eq 'Gate 2.*[Cc]ommit|Gate 2.*[Aa]pprove|[Cc]ommit.*[Aa]pproval|[Aa]pprove and commit' "$SKILL" \
  && ok "gate-2: commit or Approve linkage at Gate 2" \
  || bad "gate-2: commit/Approve linkage missing at Gate 2"

# ---------------------------------------------------------------------------
# (k) Commit-skill-only: "commit skill" appears (no self-commit)
# ---------------------------------------------------------------------------
grep -Eq 'commit skill|commit.*skill|the.*commit.*skill' "$SKILL" \
  && ok "commit-skill-only: 'commit skill' reference present" \
  || bad "commit-skill-only: 'commit skill' reference missing"

grep -qF 'never self-commits' "$SKILL" \
  && ok "commit-skill-only: no-self-commit guardrail present" \
  || bad "commit-skill-only: no-self-commit guardrail missing"

# ---------------------------------------------------------------------------
# (l) Report path: docs/deep-refactor/ present
# ---------------------------------------------------------------------------
grep -q 'docs/deep-refactor/' "$SKILL" \
  && ok "report-path: 'docs/deep-refactor/' present" \
  || bad "report-path: 'docs/deep-refactor/' missing"

# ---------------------------------------------------------------------------
# Run enumerate-sources tests (T6 — runs before summary)
# Run as a subprocess so its EXIT trap and locals do not bleed into this shell;
# parse its PASS=/FAIL= summary line and add into the running totals.
# ---------------------------------------------------------------------------
printf -- '----\n'
printf 'Running enumerate-sources.test.sh...\n'
SUB_OUT=$(bash "$(dirname "$0")/enumerate-sources.test.sh" 2>&1)
SUB_SUMMARY=$(printf '%s\n' "$SUB_OUT" | grep -E '^PASS=[0-9]+ FAIL=[0-9]+' | tail -1)
SUB_PASS=$(printf '%s\n' "$SUB_SUMMARY" | sed -E 's/^PASS=([0-9]+).*/\1/')
SUB_FAIL=$(printf '%s\n' "$SUB_SUMMARY" | sed -E 's/.*FAIL=([0-9]+).*/\1/')
PASS=$((PASS + ${SUB_PASS:-0}))
FAIL=$((FAIL + ${SUB_FAIL:-0}))

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
printf -- '----\n'
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
