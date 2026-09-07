#!/bin/bash
# test-write-scope.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash test-write-scope.test.sh
#
# Covers issue #103 / ADR-0049: generator/verifier separation. The tester agent runs BEFORE the
# coder per task group and writes the failing tests; test-write-scope.sh, a PreToolUse gate on
# Edit|Write|MultiEdit, denies the CODER agent (never the tester) any create/edit of a test-file-
# shaped path, but ONLY when the coder's own dispatch prompt carries the literal marker
#   TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.
# ASCII hyphen (not an em dash — issue #87's lesson, restated verbatim in ADR-0049 §D3).
#
# ASSERTION LABELS ARE T-PREFIXED (TA1, TB3, ...) to stay distinguishable from every other
# harness's own letter run sharing the same CI shell-tests job.
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL and NO PATH CONTAINING secret / credential /
# .env / .pem / .key — protect-files.sh denies creating such paths and secret-dep-gate.test.sh
# section D scans this repository's tracked files (via git ls-files) as its false-positive corpus.
#
# NEVER emit write-scope-enforce.sh's own scope-marker phrase — not by reading that hook's source,
# not by reading concept-to-code/SKILL.md's Step 6 Phase 3 prompt block, and not by quoting it in a
# comment. It is a DIFFERENT string from the marker this feature introduces, and the currently
# deployed copy of that hook scans a subagent's WHOLE transcript for it, so merely writing it makes
# the hook bind the writing agent to a garbage scope and deny every later write. ADR-0049 §D9
# records this happening to the architect that designed this feature; it then happened a second
# time, to the coder that wrote this file, via a comment exactly like this one.
#
# SECTIONS TA-TL, per the plan. DoD: TA/TB/TC/TD/TE/TJ green after Tasks 2-3. TF/TG/TH/TI/TK/TL
# stay RED here — they cover Tasks 4-8 and are not this batch's job. Do not "fix" a RED that
# belongs to a later task.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
HOOK="$SCRIPTS/test-write-scope.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

ROOT="$TMP/proj"
mkdir -p "$ROOT"

MARKER='TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.'

# ------------------------------------------------------------------------------------------------
# Fixture helpers.
#
# setup_fixture <id> <marker-or-empty> <mode>
#   mode="" (default)   : marker (if any) is the FIRST and only `user` entry -> the dispatch prompt.
#   mode="later"        : first `user` entry carries NO marker; a LATER `user` entry (simulating a
#                          tool result) carries the marker. Regression pin for ADR-0049 §D9.
#   mode="none"         : no subagent transcript file is created at all (agent_id present but the
#                          file is missing) — main-session non-fallback case.
# Sets globals: SID AID TP TRANSCRIPT (TRANSCRIPT is "" for mode=none).
# ------------------------------------------------------------------------------------------------
setup_fixture() {
  id="$1"; mk="$2"; mode="${3:-}"
  SID="sid-$id"; AID="aid-$id"
  PROJ_DIR="$TMP/.claude/projects/enc-$id"
  mkdir -p "$PROJ_DIR/$SID/subagents"
  TP="$PROJ_DIR/$SID.jsonl"
  touch "$TP"
  if [ "$mode" = "none" ]; then
    TRANSCRIPT=""
    return
  fi
  TRANSCRIPT="$PROJ_DIR/$SID/subagents/agent-$AID.jsonl"
  : >"$TRANSCRIPT"
  if [ "$mode" = "later" ]; then
    printf '{"type":"user","message":{"content":[{"type":"text","text":"dispatch prompt, no marker here"}]}}\n' >>"$TRANSCRIPT"
    printf '{"type":"assistant","message":{"content":[{"text":"working"}]}}\n' >>"$TRANSCRIPT"
    printf '{"type":"user","message":{"content":[{"type":"tool_result","text":%s}]}}\n' "$(printf '%s' "$mk" | jq -R .)" >>"$TRANSCRIPT"
  else
    printf '{"type":"user","message":{"content":[{"type":"text","text":%s}]}}\n' "$(printf '%s' "$mk" | jq -R .)" >>"$TRANSCRIPT"
  fi
}

# payload <agent_type> <file_path> [tool] [agent_id] [session_id] [transcript_path]
payload() {
  printf '{"session_id":"%s","tool_name":"%s","cwd":"%s","agent_type":"%s","agent_id":"%s","transcript_path":"%s","tool_input":{"file_path":"%s"}}' \
    "${5:-s1}" "${3:-Edit}" "$ROOT" "$1" "${4:-}" "${6:-}" "$2"
}
payload_bash() {
  # $1 agent_type $2 command $3 agent_id $4 session_id $5 transcript_path
  printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","agent_type":"%s","agent_id":"%s","transcript_path":"%s","tool_input":{"command":"%s"}}' \
    "${4:-s1}" "$ROOT" "$1" "${3:-}" "${5:-}" "$2"
}
run() { printf '%s' "$1" | TEST_WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

# ==================================================================================================
# T0. Anchor.
# ==================================================================================================
if [ -f "$HOOK" ]; then
  ok "T0: test-write-scope.sh exists at the expected path"
else
  bad "T0: $HOOK not found — every TA/TB/TC/TD/TE assertion below is meaningless"
fi

# ==================================================================================================
# TA. The two decisions (§D1 ordering, §D3 marker).
# ==================================================================================================
setup_fixture ta1 ""
OUT=$(run "$(payload tester "$ROOT/tests/test_x.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TA1: agent_type=tester writing a test path, no transcript marker at all -> allow (§D1: the agent_type gate runs FIRST, before any marker lookup)" \
             || bad "TA1: tester was denied without a marker present — got: $OUT"

setup_fixture ta2 "$MARKER"
OUT=$(run "$(payload coder "$ROOT/tests/test_x.py" Edit "$AID" "$SID" "$TP")")
denied "$OUT" && ok "TA2: coder + marker present + test path -> deny" \
             || bad "TA2: coder with the marker on a test path was allowed — got: $OUT"

setup_fixture ta3 ""
OUT=$(run "$(payload coder "$ROOT/tests/test_x.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TA3: coder + marker ABSENT + test path -> allow (§D3, A2 rejected: agent_type alone is not the key — RTF/deep-refactor/c2c Step6 fix agents legitimately repair tests as agent_type coder)" \
             || bad "TA3: coder without the marker was denied on a test path — got: $OUT"

setup_fixture ta4 "$MARKER"
OUT=$(run "$(payload refactorer "$ROOT/tests/test_x.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TA4: agent_type=refactorer + marker present (hypothetically) + test path -> allow (ordering protects every non-coder type)" \
             || bad "TA4: refactorer was denied — got: $OUT"

# ==================================================================================================
# TB. Fail-open modes: no marker, no agent_id, no transcript, malformed JSON, jq missing,
# main-session non-fallback. Every one of these MUST allow.
# ==================================================================================================
setup_fixture tb1 ""
OUT=$(run "$(payload coder "$ROOT/tests/test_y.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TB1: coder, valid transcript, no marker in it -> allow" \
             || bad "TB1: no-marker transcript still denied — got: $OUT"

setup_fixture tb2 "$MARKER"
# no agent_id at all; TP (main session jsonl) is untouched (empty) — the marker never even goes near it.
OUT=$(run "$(payload coder "$ROOT/tests/test_y.py" Edit "" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TB2: coder, empty agent_id -> allow (no main-session fallback; absent agent_id is decided before any transcript is even opened)" \
             || bad "TB2: empty agent_id was still evaluated — got: $OUT"

setup_fixture tb3 "$MARKER" none
# agent_id IS present but the subagent-specific transcript file was never created. Plant the
# marker directly in the MAIN session jsonl (TP) to prove the hook does not fall back to it.
printf '{"type":"user","message":{"content":[{"type":"text","text":%s}]}}\n' "$(printf '%s' "$MARKER" | jq -R .)" >>"$TP"
OUT=$(run "$(payload coder "$ROOT/tests/test_y.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TB3: agent_id present but subagent transcript missing, marker sits in the MAIN session jsonl instead -> allow (main-session non-fallback, distinct from TB2's no-agent_id case)" \
             || bad "TB3: hook fell back to the main session transcript — got: $OUT"

OUT=$(printf 'not { json' | TEST_WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "TB4: malformed top-level JSON on stdin -> allow" \
             || bad "TB4: malformed JSON was not allowed — got: $OUT"

STUBDIR="$TMP/nojq"; mkdir -p "$STUBDIR"
for b in bash cat mkdir dirname find head grep printf date rm; do
  [ -x "/bin/$b" ] && ln -sf "/bin/$b" "$STUBDIR/$b" 2>/dev/null
  [ -x "/usr/bin/$b" ] && ln -sf "/usr/bin/$b" "$STUBDIR/$b" 2>/dev/null
done
setup_fixture tb5 "$MARKER"
OUT=$(printf '%s' "$(payload coder "$ROOT/tests/test_y.py" Edit "$AID" "$SID" "$TP")" | PATH="$STUBDIR" TEST_WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "TB5: jq missing from PATH -> allow" \
             || bad "TB5: jq-missing path did not allow — got: $OUT"

setup_fixture tb6 ""
printf 'this is not valid jsonl at all {{{\n' >"$TRANSCRIPT"
OUT=$(run "$(payload coder "$ROOT/tests/test_y.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TB6: subagent transcript file exists but its content is not valid JSONL -> allow" \
             || bad "TB6: malformed transcript content was not allowed — got: $OUT"

setup_fixture tb7 "$MARKER" later
OUT=$(run "$(payload coder "$ROOT/tests/test_y.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TB7: the marker sits in a LATER user entry (simulating a tool result), the FIRST user entry has none -> allow (ADR-0049 §D9 — scanning every user entry is the live defect that self-armed write-scope-enforce.sh)" \
             || bad "TB7: hook scanned beyond the first user entry — got: $OUT"

setup_fixture tb8 "$MARKER"
OUT=$(run "$(payload coder "$ROOT/tests/test_y.py" Edit "$AID" "$SID" "$TP")")
denied "$OUT" && ok "TB8: contrast pin for TB7 — the SAME marker as the FIRST user entry does deny, proving the hook actually reads that entry" \
             || bad "TB8: first-entry marker was not honored — got: $OUT"

# ==================================================================================================
# TC. Agent-type discrimination (tester/refactorer/orchestrator allowed).
# ==================================================================================================
setup_fixture tc1 "$MARKER"
OUT=$(run "$(payload tester "$ROOT/tests/test_z.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TC1: agent_type=tester, marker present, test path -> allow" \
             || bad "TC1: tester was denied — got: $OUT"

setup_fixture tc2 "$MARKER"
OUT=$(run "$(payload refactorer "$ROOT/tests/test_z.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TC2: agent_type=refactorer, marker present, test path -> allow" \
             || bad "TC2: refactorer was denied — got: $OUT"

OUT=$(printf '{"session_id":"s1","tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s"}}' "$ROOT" "$ROOT/tests/test_z.py" | TEST_WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "TC3: no agent_type at all (the orchestrator) -> allow" \
             || bad "TC3: orchestrator write was denied — got: $OUT"

setup_fixture tc4 "$MARKER"
OUT=$(run "$(payload debugger "$ROOT/tests/test_z.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TC4: agent_type=debugger, marker present, test path -> allow" \
             || bad "TC4: debugger was denied — got: $OUT"

# ==================================================================================================
# TD. The predicate table (ADR-0049 §D4), incl. the literal docs/specs/103-....spec.md case and a
# testing-app/ component. All under coder + marker present.
# ==================================================================================================
setup_fixture td_deny "$MARKER"
deny_paths="
tests/test_foo.py
src/tests/helpers.py
test/helper.py
spec/foo_spec.rb
src/foo.test.js
src/foo.spec.ts
src/test_foo.py
src/foo_test.py
src/FooTest.java
src/FooTests.swift
src/test-write-scope.sh
scripts/run-tests.sh
"
printf '%s\n' "$deny_paths" | while IFS= read -r p; do
  [ -n "$p" ] || continue
  OUT=$(run "$(payload coder "$ROOT/$p" Edit "$AID" "$SID" "$TP")")
  denied "$OUT" && ok "TD-deny: $p -> deny" || bad "TD-deny: $p was allowed — got: $OUT"
done

setup_fixture td_allow "$MARKER"
allow_paths="
docs/specs/103-generator-verifier-separation-dispat.spec.md
testing-app/src/main.py
src/utils.py
docs/architecture/ADR-0049-x.md
"
printf '%s\n' "$allow_paths" | while IFS= read -r p; do
  [ -n "$p" ] || continue
  OUT=$(run "$(payload coder "$ROOT/$p" Edit "$AID" "$SID" "$TP")")
  [ -z "$OUT" ] && ok "TD-allow: $p -> allow" || bad "TD-allow: $p was denied — got: $OUT"
done

# ==================================================================================================
# TE. Expected-ALLOW bypasses (Bash heredoc, test content in a non-test filename). Documented
# limits of a guardrail, not a sandbox — mirrors agent-command-scope.test.sh section E.
# ==================================================================================================
setup_fixture te1 "$MARKER"
OUT=$(run "$(payload_bash coder "cat > tests/test_sneaky.py <<EOF
def test_sneaky(): assert True
EOF" "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TE1: a coder writing a test file via Bash heredoc is not seen by this hook (tool_input has no .file_path) — a guardrail against a shortcut, not a sandbox" \
             || bad "TE1: Bash heredoc path unexpectedly denied — got: $OUT"

setup_fixture te2 "$MARKER"
OUT=$(run "$(payload coder "$ROOT/src/utils.py" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TE2: test-shaped CONTENT written to a non-test-shaped PATH (src/utils.py) is allowed — the predicate is path-only, content is never inspected" \
             || bad "TE2: a non-test path was denied — got: $OUT"

# ==================================================================================================
# TF. Marker coupling hook<->SKILL.md and the deny reason's recovery path. EXPECTED RED until
# Tasks 4-5 add the marker to concept-to-code/SKILL.md's Step 5 dispatch prompts. Reads only the
# Step 5 extract (never Step 6, which is where write-scope-enforce.sh's OWN marker lives).
# ==================================================================================================
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
STEP5_REF="$STAGING/plugin/skills/concept-to-code/references/step5-implementation.md"
STEP5="$TMP/c2c_step5.txt"
# The Step 5 range moved to references/step5-implementation.md (VCS-047, ADR-0174); the
# reference file's body IS the block, so no awk range is needed any more.
cp "$STEP5_REF" "$STEP5" 2>/dev/null

if [ -s "$STEP5" ]; then
  ok "TF0: concept-to-code Step 5 (references/step5-implementation.md) is extractable (TF1/TF2 below read)"
else
  bad "TF0: could not read references/step5-implementation.md — TF1/TF2 below would pass vacuously (empty extract, negative-shaped risk)"
fi

HOOK_HAS_MARKER=0
grep -qF 'TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.' "$HOOK" 2>/dev/null && HOOK_HAS_MARKER=1
STEP5_HAS_MARKER=0
grep -qF 'TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.' "$STEP5" 2>/dev/null && STEP5_HAS_MARKER=1
if [ "$HOOK_HAS_MARKER" -eq 1 ] && [ "$STEP5_HAS_MARKER" -eq 1 ]; then
  ok "TF1: the exact TEST-AUTHORING SCOPE marker is present verbatim in both the hook and Step 5 (Tasks 4-5)"
else
  bad "TF1: marker not present in both hook and Step 5 yet (hook=$HOOK_HAS_MARKER step5=$STEP5_HAS_MARKER) — Tasks 4-5"
fi

if grep -qF 'the tester agent owns test files for this task' "$STEP5" 2>/dev/null; then
  ok "TF2: Step 5 states the deny reason's recovery path (the tester owns test files) so a denied coder reads a consistent story"
else
  bad "TF2: Step 5 does not yet state the recovery-path phrase — Tasks 4-5"
fi

# ==================================================================================================
# TG. Both-paths pins — Workflow pipeline() AND Agent-tool fallback both stage tester before coder
# with model/effort pinned. EXPECTED RED until Tasks 4-5.
# ==================================================================================================
if grep -qF 'pipeline(' "$STEP5" 2>/dev/null && grep -qi 'tester' "$STEP5" 2>/dev/null \
   && grep -qF 'model: "sonnet"' "$STEP5" 2>/dev/null && grep -qF 'effort: "high"' "$STEP5" 2>/dev/null; then
  ok "TG1(workflow): Step 5's pipeline() stages a pinned tester(model sonnet, effort high) call"
else
  bad "TG1(workflow): Step 5 pipeline() does not yet pin a tester stage — Task 4"
fi

TESTER_N=$(grep -ci 'tester' "$STEP5" 2>/dev/null || true)
case "$TESTER_N" in ''|*[!0-9]*) TESTER_N=0 ;; esac
if [ "$TESTER_N" -ge 4 ]; then
  ok "TG2(fallback): Step 5 mentions 'tester' >= 4 times (found $TESTER_N) — both the Workflow stage and the Agent-tool per-batch dispatch name it"
else
  bad "TG2(fallback): Step 5 mentions 'tester' only $TESTER_N time(s) (< 4) — Task 5 batch dispatch not wired yet"
fi

# ==================================================================================================
# TH. step5-report.json schema + read contract (§D5). EXPECTED RED until Task 6, except the
# forward guard sub-assertion (already true today, per spec-coverage.test.sh's RH5 precedent).
# ==================================================================================================
if grep -qF '"tests_written_by"' "$STEP5" 2>/dev/null; then
  ok "TH1: the documented schema block contains \"tests_written_by\""
else
  bad "TH1: \"tests_written_by\" missing from the schema block — Task 6"
fi

if grep -F -A5 '"tests_written_by"' "$STEP5" 2>/dev/null | grep -q '"task"' \
   && grep -F -A5 '"tests_written_by"' "$STEP5" 2>/dev/null | grep -q '"agent"'; then
  ok "TH2: the schema shows the {task, agent} shape near tests_written_by"
else
  bad "TH2: the {task, agent} shape is not shown near tests_written_by — Task 6"
fi

if grep -qF 'tests_written_by' "$STEP5" 2>/dev/null && grep -qF 'never a failure signal' "$STEP5" 2>/dev/null \
   && grep -qF '"coder"' "$STEP5" 2>/dev/null; then
  ok "TH3: the read contract states tests_written_by is never a failure signal and a \"coder\" entry is surfaced at Gate 5"
else
  bad "TH3: the read contract does not yet state the tests_written_by policy — Task 6"
fi

if grep -qF 'weakening_findings' "$STEP5" 2>/dev/null && grep -qF 'checkpoint_reviews' "$STEP5" 2>/dev/null \
   && grep -qF 'requirement_coverage' "$STEP5" 2>/dev/null; then
  ok "TH4: forward guard — weakening_findings, checkpoint_reviews and requirement_coverage are still all in the schema block (appending tests_written_by must not disturb them; this is not fix evidence for this feature)"
else
  bad "TH4: one of weakening_findings / checkpoint_reviews / requirement_coverage regressed out of the schema block — forward guard failure, not this feature's fix"
fi

# ==================================================================================================
# TI. Registration (PAIRS, chmod, docs-ci.yml, settings.json reference). EXPECTED RED until
# Task 8. pairs-completeness.test.sh is blind to plugin/scripts/*, so this is the only thing
# preventing ADR-0043's exact defect for this hook (ADR-0049 negative-consequence #4).
# ==================================================================================================
SYNCSH="$STAGING/sync-to-claude.sh"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
SETTINGSJSON="$STAGING/user/settings.json"

awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" >"$TMP/pairs" 2>/dev/null
if grep -qxF 'plugin/scripts/test-write-scope.sh|hooks/test-write-scope.sh' "$TMP/pairs" 2>/dev/null; then
  ok "TI1: PAIRS deploys test-write-scope.sh to ~/.claude/hooks/"
else
  bad "TI1: the test-write-scope.sh PAIRS entry is missing — Task 8"
fi

if grep -F 'chmod +x' "$SYNCSH" 2>/dev/null | grep -qF 'test-write-scope.sh'; then
  ok "TI2: the executable-bit preservation block includes test-write-scope.sh"
else
  bad "TI2: test-write-scope.sh is not in the chmod +x list — Task 8"
fi

DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]test-write-scope[[:space:];]'; then
  ok "TI3: docs-ci.yml's shell-tests loop list runs test-write-scope"
else
  bad "TI3: test-write-scope is not in docs-ci.yml's explicit harness list — Task 8"
fi

if grep -qF 'test-write-scope' "$SETTINGSJSON" 2>/dev/null; then
  ok "TI4: staging/user/settings.json carries a test-write-scope reference entry"
else
  bad "TI4: staging/user/settings.json does not reference test-write-scope yet — Task 8"
fi

# ==================================================================================================
# TJ. tester.md contract (four additive edits, §D8). EXPECTED GREEN after Task 3.
# ==================================================================================================
TESTER_AGENT="$STAGING/plugin/agents/tester.md"
WHEN="$TMP/tester_when.txt"
awk '/^## When to invoke/{f=1} /^## Core Responsibilities/{f=0} f' "$TESTER_AGENT" >"$WHEN" 2>/dev/null
if grep -qF 'ADR-0049' "$WHEN" 2>/dev/null && grep -qi 'spec' "$WHEN" 2>/dev/null && grep -qi 'before the coder' "$WHEN" 2>/dev/null; then
  ok "TJ1: tester.md 'When to invoke' gains a spec-first, before-the-coder bullet naming ADR-0049"
else
  bad "TJ1: tester.md is missing the spec-first / before-the-coder / ADR-0049 bullet — Task 3"
fi

PROCESS="$TMP/tester_process.txt"
awk '/^## Process/{f=1} /^## Quality Standards/{f=0} f' "$TESTER_AGENT" >"$PROCESS" 2>/dev/null
if grep -qF 'spec-coverage.sh --list' "$PROCESS" 2>/dev/null && grep -qi 'success criteria' "$PROCESS" 2>/dev/null \
   && grep -qi 'plan' "$PROCESS" 2>/dev/null && grep -qi 'never' "$PROCESS" 2>/dev/null \
   && grep -qi 'implementation' "$PROCESS" 2>/dev/null; then
  ok "TJ2: tester.md Process step 1 branches from spec-coverage.sh --list, falls back to Success criteria then plan task text, never from implementation files"
else
  bad "TJ2: tester.md Process is missing the spec-coverage.sh --list branch with its two fallbacks — Task 3"
fi

OUTFMT="$TMP/tester_output.txt"
awk '/^## Output Format/{f=1} /^## Edge Cases/{f=0} f' "$TESTER_AGENT" >"$OUTFMT" 2>/dev/null
if grep -qi 'requirement' "$OUTFMT" 2>/dev/null && grep -qE 'R-NN|R-[0-9][0-9]' "$OUTFMT" 2>/dev/null; then
  ok "TJ3: tester.md Output Format gains a requirement-ID reporting bullet"
else
  bad "TJ3: tester.md Output Format is missing requirement-ID reporting — Task 3"
fi

EDGE="$TMP/tester_edge.txt"
awk '/^## Edge Cases/{f=1} f' "$TESTER_AGENT" >"$EDGE" 2>/dev/null
if grep -qi 'spec' "$EDGE" 2>/dev/null && grep -qi 'invent' "$EDGE" 2>/dev/null && grep -qi 'report the gap' "$EDGE" 2>/dev/null; then
  ok "TJ4: tester.md Edge Cases gains the anti-fabrication rule — report a SPEC gap, do not invent a test"
else
  bad "TJ4: tester.md Edge Cases is missing the anti-fabrication rule — Task 3"
fi

# ==================================================================================================
# TK. #### heading uniqueness and placement. EXPECTED RED until Task 4.
# ==================================================================================================
# VCS-047/ADR-0174: TK1's uniqueness check is whole-file, so it must count across both SKILL.md
# and references/step5-implementation.md — the heading itself moved into the latter.
GEN_N=$(cat "$CC" "$STEP5_REF" 2>/dev/null | grep -c '^#### Generator/verifier separation — tester stage and coder test-write deny (ADR-0049)$' || true)
case "$GEN_N" in ''|*[!0-9]*) GEN_N=0 ;; esac
if [ "$GEN_N" -eq 1 ]; then
  ok "TK1: exactly one occurrence of the Generator/verifier separation heading in the whole file"
else
  bad "TK1: expected exactly 1 occurrence of the heading, found $GEN_N — Task 4"
fi

# TK2's placement check: all three anchors moved together into references/step5-implementation.md.
GENLINE=$(grep -n '^#### Generator/verifier separation — tester stage and coder test-write deny (ADR-0049)$' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
SCHEMALINE=$(grep -n '^#### step5-report.json schema' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
WORKFLOWLINE=$(grep -n '^#### Workflow dispatch' "$STEP5_REF" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$GENLINE" ] && [ -n "$SCHEMALINE" ] && [ -n "$WORKFLOWLINE" ] \
   && [ "$GENLINE" -gt "$WORKFLOWLINE" ] && [ "$GENLINE" -lt "$SCHEMALINE" ]; then
  ok "TK2: the heading sits after the Workflow dispatch block and before the step5-report.json schema block"
else
  bad "TK2: heading placement not yet correct (or heading absent) — Task 4"
fi

# ==================================================================================================
# TL. autopilot-build isolation restatement (§D5). FORWARD GUARD (ADR-0068 §D1 / R-11).
#
# ADR-0049 §D2's dirty-tree isolation-selection condition (checking `git diff HEAD --name-only`
# and choosing `isolation: "none"` vs `isolation: worktree` accordingly) is retired at every call
# site by ADR-0068, whose own header records that it supersedes ADR-0049 §D2 in part (R-11:
# `isolation: worktree` unconditionally, no second mode). TL1 used to assert the restatement was
# present; that premise was revoked by an approved ADR, so the assertion is inverted here rather
# than deleted, to stand as a forward guard against the condition being reintroduced — mirroring
# section B1c of worktree-isolation-contract.test.sh (same file, same retired condition, opposite
# historical direction).
# ==================================================================================================
AB="$STAGING/plugin/skills/autopilot-build/SKILL.md"
ABSTEP5="$TMP/ab_step5.txt"
awk '/^#### Step 5 —/{f=1} /^#### Step 6/{f=0} f' "$AB" >"$ABSTEP5" 2>/dev/null

if [ -s "$ABSTEP5" ]; then
  ok "TL0: autopilot-build/SKILL.md's Step 5 is extractable (the anchor TL1 below reads)"
else
  bad "TL0: could not extract Step 5 from $AB — TL1 below would pass vacuously (empty extract, negative-shaped assertion)"
fi

if [ ! -s "$ABSTEP5" ]; then
  bad "TL1: cannot evaluate — Step 5 extraction is empty (see TL0)"
elif grep -qF 'git diff HEAD --name-only' "$ABSTEP5" 2>/dev/null && grep -qi 'isolation.*none\|none.*isolation' "$ABSTEP5" 2>/dev/null; then
  bad "TL1: autopilot-build/SKILL.md's Step 5 still restates the dirty-tree isolation condition — ADR-0068 §D1/R-11 requires it retired (supersedes ADR-0049 §D2 in part)"
else
  ok "TL1: autopilot-build/SKILL.md's Step 5 no longer restates the dirty-tree isolation condition (ADR-0068 §D1 / R-11, supersedes ADR-0049 §D2 in part)"
fi

# ==================================================================================================
# TM. Dispatch granularity (issue #241, ADR-0088). ADR-0049 split test authoring from
# implementation and dispatched the split at TASK granularity — but a plan task is a MIXED unit:
# some of its sub-steps target test-shaped paths and some do not. The tester's brief reads the plan
# only as a third fallback (SPEC R-NN ids first, Success Criteria second), so on a SPEC that
# declares ids — the ADR-0048 case, i.e. the normal one — the tester is never told which of the
# batch's sub-steps are its own, and the coder is denied them by the hook this file tests.
#
# Nothing here changes the hook, the marker, or ADR-0049's decision. TM5 is the guard that says so:
# a "fix" for #241 that weakens the marker is the failure mode, not the remedy.
#
# Counting occurrences over the WHOLE file is deliberate, and it is why this section adds no sixth
# heading-anchored extraction: ADR-0083 §D3 measured what a reworded heading does to an awk
# extractor (assertions vanish, or an empty extract turns positive assertions green while only the
# abort ones fail). An exact count over the file is immune to both and still pins each dispatch
# path independently — a clause present once means one path is uncovered (ADR-0039's rule).
# ==================================================================================================
TMCC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
TMTESTER="$STAGING/plugin/agents/tester.md"
# VCS-047/ADR-0174: TM1-TM3/TM5's dispatch-site clauses physically moved into
# references/step5-implementation.md with the rest of Step 5's body. TM_CC_ALL concatenates both
# files so the whole-file occurrence counts below keep reading their real content.
TM_CC_ALL="$TMP/tm_cc_all.txt"
cat "$TMCC" "$STEP5_REF" >"$TM_CC_ALL" 2>/dev/null

# count_lit <literal> <file> — LINE count for a literal that must live on one line. Never a
# `grep -c || echo 0` (that prints "0\n0" on no match, because grep -c prints 0 AND exits 1; issue
# #100 shipped that bug once). Used ONLY by TM5, where being one line is the property under test:
# the hook greps a single line, so a marker split across two is a marker the hook cannot see.
count_lit() {
  _n=$(grep -cF -- "$1" "$2" 2>/dev/null || true)
  [ -n "${_n:-}" ] || _n=0
  printf '%s' "$_n"
}

# count_flat <literal> <file> — OCCURRENCE count against a whitespace-flattened copy. Every prose
# clause below uses this, because a prose assertion must not depend on where markdown wraps the
# text (ADR-0073's lesson, and its relatives in ADR-0076, ADR-0080 and ADR-0082 — comment markers,
# backticks, decoration). This section reproduced it on its first run: TM2 and TM3 reported 0
# against clauses that were present and correct, purely because they wrapped across two lines.
# `grep -c` cannot serve here: on a one-line flattened file it counts the line, so two occurrences
# would report 1.
count_flat() {
  _n=$(tr '\n' ' ' <"$2" 2>/dev/null | tr -s ' ' | grep -oF -- "$1" 2>/dev/null | wc -l | tr -d ' ')
  [ -n "${_n:-}" ] || _n=0
  printf '%s' "$_n"
}

# Person-neutral on purpose: Workflow Stage 1 states this as orchestrator prose, the Agent-tool
# template states it as a second-person brief. A second-person literal would fit one and not the
# other, and the assertion would then be pinning voice rather than content.
TM_TESTER_CLAUSE='a skipped sub-step is a sub-step nobody can do'
TM_CODER_CLAUSE='were executed by the tester before this dispatch and are NOT yours'
TM_GREEN_CLAUSE='an assertion the plan defers to a later task stays red'
TM_AGENT_CLAUSE='test-shaped sub-steps in the range are yours in every case'

n=$(count_flat "$TM_TESTER_CLAUSE" "$TM_CC_ALL")
if [ "$n" -eq 2 ]; then
  ok "TM1: the tester brief's plan-is-read-always clause appears in exactly 2 dispatch sites (Workflow Stage 1 + Agent-tool Tester batch template)"
else
  bad "TM1: expected the tester plan-scope clause at exactly 2 dispatch sites, found $n — one path is uncovered (#241, ADR-0088)"
fi

n=$(count_flat "$TM_CODER_CLAUSE" "$TM_CC_ALL")
if [ "$n" -eq 2 ]; then
  ok "TM2: the coder brief's test-sub-steps-are-not-yours clause appears in exactly 2 dispatch sites (Workflow Stage 2 + Agent-tool Single batch template)"
else
  bad "TM2: expected the coder test-sub-step clause at exactly 2 dispatch sites, found $n — one path is uncovered (#241, ADR-0088)"
fi

n=$(count_flat "$TM_GREEN_CLAUSE" "$TM_CC_ALL")
if [ "$n" -eq 2 ]; then
  ok "TM3: 'make them green' is qualified at both coder dispatch sites — a red assertion the plan defers stays red"
else
  bad "TM3: expected the deferred-red qualification at exactly 2 coder dispatch sites, found $n (#241, ADR-0088)"
fi

if [ "$(count_flat "$TM_AGENT_CLAUSE" "$TMTESTER")" -ge 1 ]; then
  ok "TM4: tester.md states the sub-step ownership contract in the agent's own file (ADR-0035: a contract belongs with the agent, not only in the dispatching skill)"
else
  bad "TM4: tester.md does not state the test-shaped sub-step ownership contract — a contract that lives only in the caller (ADR-0035, #241)"
fi

# TM5 — the regression guard this whole change is measured against. The hook greps ONE literal
# line; an em dash, a paraphrase or a dropped site makes it silently inert (issue #87).
hookn=$(count_lit "$MARKER" "$HOOK")
ccn=$(count_lit "$MARKER" "$TM_CC_ALL")
if [ "$hookn" -eq 1 ] && [ "$ccn" -eq 3 ]; then
  ok "TM5: the TEST-AUTHORING SCOPE marker is byte-identical, ASCII hyphen, at 1 hook site and 3 concept-to-code sites (2 dispatch templates + the mechanism prose)"
else
  bad "TM5: marker site count changed — hook=$hookn (want 1) concept-to-code=$ccn (want 3). #241's fix must not weaken the marker; that is the failure mode, not the remedy"
fi

# TM6 — the premise of ADR-0088, measured rather than asserted. A mixed task is not a property of
# one feature: it is the shape of essentially every plan this repository has produced. The guard is
# on the DENOMINATOR (ADR-0085): zero mixed plans out of zero plans reads exactly like "no problem".
tm_test_shaped() {
  case "$1" in *.md) return 1 ;; esac
  case "$1" in */tests/*|tests/*|*/test/*|test/*|*/spec/*|spec/*) return 0 ;; esac
  _b="${1##*/}"
  case "$_b" in *.test.*|*.spec.*|test_*|*_test.*|*Test.*|*Tests.*|test-*.sh|run-tests.sh) return 0 ;; esac
  return 1
}
PLANDIR="${TM_PLAN_DIR:-$REPO/docs/superpowers/plans}"
tm_total=0; tm_mixed=0
for _p in "$PLANDIR"/*.md; do
  [ -f "$_p" ] || continue
  tm_total=$((tm_total + 1))
  _ht=0; _hi=0
  for _f in $(grep -oE '[A-Za-z0-9._/-]+\.(sh|py|swift|ts|tsx|js|yml|yaml|json|awk|md)' "$_p" 2>/dev/null | sort -u); do
    if tm_test_shaped "$_f"; then _ht=1; else _hi=1; fi
  done
  [ "$_ht" -eq 1 ] && [ "$_hi" -eq 1 ] && tm_mixed=$((tm_mixed + 1))
done
if [ "$tm_total" -lt 50 ]; then
  bad "TM6: plan corpus derivation yielded only $tm_total plans (>= 50 expected) — the derivation is broken, and a broken derivation reports zero mixed plans exactly like a clean one"
elif [ "$tm_mixed" -ge 40 ]; then
  ok "TM6: $tm_mixed of $tm_total plans name both test-shaped and implementation paths — a mixed task is the normal shape, not one feature's quirk (ADR-0088 premise)"
else
  bad "TM6: only $tm_mixed of $tm_total plans are mixed (>= 40 expected) — ADR-0088's premise no longer holds and its reasoning needs revisiting"
fi

# TM7/TM8 — EXECUTED PREMISE, NOT FIX EVIDENCE. Both pass before and after this change: the hook is
# byte-untouched by #241. They exist because ADR-0088's whole design rests on "the tester can write
# these files and the coder cannot", and rule 11 says a claim nobody ran is unverified. The path is
# a real file in this repository, not a synthetic fixture.
TMREAL="$REPO/staging/plugin/scripts/tests/pairs-completeness.test.sh"
setup_fixture tm7 "$MARKER"
OUT=$(run "$(payload coder "$TMREAL" Edit "$AID" "$SID" "$TP")")
denied "$OUT" && ok "TM7 (premise, passes before and after): a marker-carrying coder is DENIED a real staging test file — the half of ADR-0088 that makes a per-task dispatch impossible" \
              || bad "TM7: a marker-carrying coder was allowed to write $TMREAL — ADR-0088's premise is wrong; got: $OUT"

setup_fixture tm8 "$MARKER"
OUT=$(run "$(payload tester "$TMREAL" Edit "$AID" "$SID" "$TP")")
[ -z "$OUT" ] && ok "TM8 (premise, passes before and after): the tester is ALLOWED the same real file — the work is doable in-role, which is why #241 needs no marker change" \
             || bad "TM8: the tester was denied $TMREAL — ADR-0088's remedy is not available; got: $OUT"

# ==================================================================================================
# TN. Architect branch coverage (VCS-046, ADR-0041/issue #58). agent-write-scope.sh was merged
# into this file — universal per-Edit/Write process-spawn overhead, not agent-type-gated — and its
# architect-scope logic now lives in the ARCHITECT BRANCH section of $HOOK. This section is a
# minimal mirror of agent-write-scope.test.sh's sections A/B, enough to make THIS file alone a
# complete regression suite for the merged hook even if agent-write-scope.test.sh were ever
# deleted. The fuller architect-scope surface (Edit/MultiEdit coverage, malformed JSON, a
# marker-shaped path, the architect.md coupling check, the #127 self-arming audit) stays owned by
# agent-write-scope.test.sh, not duplicated here.
# ==================================================================================================
run_arch() { printf '%s' "$1" | AGENT_WRITE_SCOPE_DIR="$TMP/state-arch" TEST_WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }

OUT=$(run_arch "$(payload architect "$ROOT/src/main.py" Write)")
denied "$OUT" && ok "TN1: architect writing outside both doc roots is denied (ADR-0041, ex agent-write-scope.sh)" \
             || bad "TN1: out-of-scope architect Write was allowed — got: $OUT"

OUT=$(run_arch "$(payload architect "$ROOT/docs/architecture/ADR-0099-x.md" Write)")
[ -z "$OUT" ] && ok "TN2: architect writing an ADR is allowed" \
             || bad "TN2: legitimate ADR write was denied — got: $OUT"

OUT=$(run_arch "$(payload architect "$ROOT/docs/superpowers/plans/2026-07-25-x.md" Write)")
[ -z "$OUT" ] && ok "TN3: architect writing a PLAN is allowed (c2c Step 2 requires this path, the two-roots regression guard)" \
             || bad "TN3: plan write denied — this would HARD ABORT every chain at Step 2: $OUT"

OUT=$(run_arch "$(payload coder "$ROOT/src/main.py" Write)")
[ -z "$OUT" ] && ok "TN4: the architect branch is inert for agent_type=coder (falls through to the coder path, which allows here since no agent_id is set)" \
             || bad "TN4: architect branch fired on a non-architect agent_type — got: $OUT"

# VCS-056/ADR-0183: memory: project added a third allowed root, .claude/agent-memory/architect/.
# plant: TN5 | plugin/scripts/test-write-scope.sh | */.claude/agent-memory/architect/*) | */.claude/agent-memory/architect-disabled/*)
OUT=$(run_arch "$(payload architect "$ROOT/.claude/agent-memory/architect/MEMORY.md" Write)")
[ -z "$OUT" ] && ok "TN5: architect writing its own persistent memory is allowed (VCS-056, ADR-0183)" \
             || bad "TN5: legitimate architect memory write was denied — got: $OUT"

# plant: TN6 | plugin/scripts/test-write-scope.sh | */docs/architecture/*|*/docs/superpowers/plans/*|*/.claude/agent-memory/architect/*) | */docs/architecture/*|*/docs/superpowers/plans/*|*/.claude/agent-memory/*)
OUT=$(run_arch "$(payload architect "$ROOT/.claude/agent-memory/coder/MEMORY.md" Write)")
denied "$OUT" && ok "TN6: architect writing into ANOTHER agent's memory dir is denied — the third root is scoped to architect/, not agent-memory/ at large" \
             || bad "TN6: architect was allowed to write outside its own memory dir — got: $OUT"

# ==================================================================================================
# Z. Assertion-count floor (ADR-0083 §D3). A suite reporting FEWER assertions does not read as
# broken and nobody watches the count — six of plan-task-count's assertions once vanished that way.
# A floor, not an exact count, so adding an assertion does not require bumping it.
# ==================================================================================================
Z_FLOOR=50
if [ "$((PASS + FAIL))" -ge "$Z_FLOOR" ]; then
  ok "Z1: assertion count $((PASS + FAIL)) is at or above the floor of $Z_FLOOR"
else
  bad "Z1: assertion count $((PASS + FAIL)) fell below the floor of $Z_FLOOR — assertions disappeared rather than failed"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
