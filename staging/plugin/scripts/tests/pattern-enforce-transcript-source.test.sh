#!/bin/bash
# pattern-enforce-transcript-source.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash pattern-enforce-transcript-source.test.sh
#
# Covers issue #194 phase 1: pre-flight-pattern-enforce.sh now records WHICH transcript produced
# each coder-path decision, as `src=<token>` in the existing free-text reason column.
#
# WHY THE TOKEN MATTERS. The hook falls back to the MAIN SESSION jsonl when a subagent's own
# transcript cannot be found, then scans assistant entries and ALLOWS on a match. So a subagent
# whose transcript is missing inherits the orchestrator's recent output, and a `PATTERN:` line the
# orchestrator emitted satisfies the check for an agent that declared nothing. Before this change
# the log said `allow  PATTERN found in window` for BOTH paths — the two were indistinguishable,
# which is why the fallback has never been examined on its own terms. Phase 2 decides what to do
# about it; this file only makes the question answerable.
#
# THE MEASUREMENT IS ONLY AS GOOD AS THE TOKEN. If `src=` is ever wrong, the number phase 2 reads
# is wrong in a way nothing else would catch — the log would still look well-formed. That is what
# section S exists for.
#
# This is also the FIRST hermetic, CI-visible coverage of this hook. Its long-standing test file
# (`tests/pre-flight-pattern-enforce.sh`, deliberately outside the *.test.sh glob) tests the
# DEPLOYED copy under $HOME and is CI-dark by design — ADR-0024 recorded that as a known gap.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$SCRIPTS/pre-flight-pattern-enforce.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SID="sess-1"
PROJ="$TMP/proj"
TP="$PROJ/$SID.jsonl"
mkdir -p "$PROJ/$SID/subagents/workflows/wf_x"

pattern_entry() {
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"PATTERN: MODIFY | %s"}]}}\n' "$1"
}

# The MAIN session transcript carries a PATTERN line, exactly as an orchestrator that has been
# editing files would. This is the whole premise: it is legitimate output, not a plant.
pattern_entry "orchestrator/own-edit.md" > "$TP"

# aaa — a regular subagent with its own transcript and its own declaration.
pattern_entry "src/a.py:1 by the agent itself" > "$PROJ/$SID/subagents/agent-aaa.jsonl"
# bbb — a workflow subagent, transcript under the v2.1.154 workflows/<wf_id>/ layout.
pattern_entry "src/b.py:1 by the workflow agent" > "$PROJ/$SID/subagents/workflows/wf_x/agent-bbb.jsonl"
# ccc — a subagent that declared nothing at all.
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"just working"}]}}\n' \
  > "$PROJ/$SID/subagents/agent-ccc.jsonl"
# zzz — NO transcript file anywhere. This is the fallback case.

# payload <agent_id> [agent_type]
payload() {
  printf '{"session_id":"%s","tool_name":"Edit","cwd":"%s","agent_type":"%s","agent_id":"%s","transcript_path":"%s","tool_input":{"file_path":"%s/x.py"}}' \
    "$SID" "$TMP" "${2:-coder}" "$1" "$TP" "$TMP"
}
# run <agent_id> [agent_type] -> stdout of the hook; log goes to a per-call state dir
run() {
  STATE="$TMP/state-$1-${2:-coder}"
  printf '%s' "$(payload "$1" "${2:-}")" | PATTERN_ENFORCE_DIR="$STATE" bash "$HOOK" 2>/dev/null
}
logline() { tail -1 "$TMP/state-$1-${2:-coder}/audit.log" 2>/dev/null; }
src_of()  { logline "$@" | awk -F'\t' '{print $5}' | grep -o 'src=[a-z-]*' | head -1; }
act_of()  { logline "$@" | awk -F'\t' '{print $4}'; }

# =====================================================================================
# S. The three sources, each identified correctly. If any token is wrong the phase-2
# measurement is wrong, and nothing downstream would notice.
run aaa >/dev/null
[ "$(src_of aaa)" = "src=subagent" ] && ok "S1: a regular subagent transcript logs src=subagent" \
  || bad "S1: got '$(src_of aaa)' — expected src=subagent"

run bbb >/dev/null
[ "$(src_of bbb)" = "src=workflow" ] && ok "S2: the workflows/<wf_id>/ layout logs src=workflow" \
  || bad "S2: got '$(src_of bbb)' — expected src=workflow"

run zzz >/dev/null
[ "$(src_of zzz)" = "src=main-fallback" ] && ok "S3: no subagent transcript logs src=main-fallback" \
  || bad "S3: got '$(src_of zzz)' — expected src=main-fallback"

# S4: THE CASE. The fallback allowed a write on the strength of the ORCHESTRATOR's PATTERN line —
# agent zzz declared nothing and does not even have a transcript. The verdict is unchanged from
# before this instrumentation (that is phase 2's decision to make); what changed is that the log
# now says which transcript it came from.
if [ "$(act_of zzz)" = "allow" ] && [ "$(src_of zzz)" = "src=main-fallback" ]; then
  ok "S4: a main-fallback ALLOW is now distinguishable from a subagent ALLOW in the log"
else
  bad "S4: expected allow+main-fallback, got act='$(act_of zzz)' src='$(src_of zzz)'"
fi

# S5: the positive twin (rule 8). S1-S4 would all pass against a hook that printed a fixed token
# per code path while getting the DECISION wrong. The two must move together: same agent, same
# fallback, but with no PATTERN anywhere — it must block, and still say main-fallback.
NOPAT="$TMP/nopat"
mkdir -p "$NOPAT/$SID/subagents"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"no header here"}]}}\n' \
  > "$NOPAT/$SID.jsonl"
OUT=$(printf '{"session_id":"%s","tool_name":"Edit","cwd":"%s","agent_type":"coder","agent_id":"qqq","transcript_path":"%s","tool_input":{"file_path":"%s/x.py"}}' \
  "$SID" "$TMP" "$NOPAT/$SID.jsonl" "$TMP" \
  | PATTERN_ENFORCE_DIR="$TMP/state-nopat" bash "$HOOK" 2>/dev/null)
_act=$(tail -1 "$TMP/state-nopat/audit.log" | awk -F'\t' '{print $4}')
_src=$(tail -1 "$TMP/state-nopat/audit.log" | awk -F'\t' '{print $5}' | grep -o 'src=[a-z-]*')
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
   && [ "$_act" = "block" ] && [ "$_src" = "src=main-fallback" ]; then
  ok "S5: a fallback with no PATTERN still blocks, and still records the source"
else
  bad "S5: expected deny+block+main-fallback, got act='$_act' src='$_src' out='$OUT'"
fi

# S6: a coder whose own transcript has no PATTERN blocks, with src=subagent — the ordinary block.
run ccc >/dev/null
if [ "$(act_of ccc)" = "block" ] && [ "$(src_of ccc)" = "src=subagent" ]; then
  ok "S6: an ordinary block records src=subagent"
else
  bad "S6: got act='$(act_of ccc)' src='$(src_of ccc)'"
fi

# =====================================================================================
# B. The denominator. A rate needs both halves, so every coder-path decision carries the token —
# including fail-open, where the answer is `none`. Without this, "how often does lookup fail" is
# computable only against a total nobody records.
NOTP="$TMP/state-notp"
printf '{"session_id":"%s","tool_name":"Edit","cwd":"%s","agent_type":"coder","agent_id":"www","transcript_path":"%s/does-not-exist.jsonl","tool_input":{"file_path":"%s/x.py"}}' \
  "$SID" "$TMP" "$TMP" "$TMP" | PATTERN_ENFORCE_DIR="$NOTP" bash "$HOOK" >/dev/null 2>&1
_l=$(tail -1 "$NOTP/audit.log")
if printf '%s' "$_l" | awk -F'\t' '{print $4}' | grep -q 'fail-open' \
   && printf '%s' "$_l" | grep -q 'src=none'; then
  ok "B1: fail-open carries src=none, so the denominator is countable"
else
  bad "B1: fail-open should carry src=none — got: $_l"
fi

# B2: the non-coder bypass is NOT part of the coder-path denominator and must NOT carry the token.
# It is 7691 of the ~9962 rows in the live log; counting it would make the rate meaningless.
run aaa reviewer >/dev/null
if printf '%s' "$(logline aaa reviewer)" | grep -q 'src='; then
  bad "B2: the non-coder bypass carries src= — it would pollute the denominator"
else
  ok "B2: the non-coder bypass carries no src= token (not a coder-path decision)"
fi

# B3: the documented counting command, run against a log this test built. If the header's recipe
# and the emitted format ever drift, this is what says so.
CAT="$TMP/all.log"
cat "$TMP"/state-*/audit.log > "$CAT" 2>/dev/null
_counted=$(awk -F'\t' '$5 ~ /src=/' "$CAT" | grep -o 'src=[a-z-]*' | sort | uniq -c | wc -l | tr -d ' ')
[ "$_counted" -ge 3 ] && ok "B3: the header's counting command returns >= 3 distinct sources ($_counted)" \
  || bad "B3: the documented counting command found $_counted distinct sources, expected >= 3"

# =====================================================================================
# C. Contract guards. Phase 1 instruments and decides nothing; these pin that.
# C1: the log is still five tab-separated fields. hook-verify-workflow.sh parses $1 and $2, so a
# sixth column would break a consumer one file over — which is why the token lives in the prose.
_fields=$(tail -1 "$TMP/state-aaa-coder/audit.log" | awk -F'\t' '{print NF}')
[ "$_fields" -eq 5 ] && ok "C1: the audit log is still 5 tab-separated fields" \
  || bad "C1: field count changed to $_fields — hook-verify-workflow.sh parses this log"

# C2: the fallback still exists. Phase 1 must not have quietly removed it — that is phase 2's
# decision, on evidence this instrumentation has not gathered yet. A guard against the fix
# arriving before the measurement it is supposed to be based on.
# The needle is the fallback ASSIGNMENT, not the instrumentation variable beside it: keyed on
# `TSRC="main-fallback"` this fires against any pre-instrumentation hook too, reporting "the
# fallback was removed" about a hook that still has it. A guard has to name the thing it guards.
if grep -q 'TRANSCRIPT="\$TP"' "$HOOK"; then
  ok "C2: the main-session fallback is still present (phase 1 instruments, it does not decide)"
else
  bad "C2: the fallback was removed — that is issue #194 phase 2, and it needs the measurement first"
fi

# C3: the header must carry the counting recipe. The number gets read by whoever opens this hook
# months from now, not by whoever wrote it.
if grep -q "uniq -c" "$HOOK" && grep -q 'src=' "$HOOK"; then
  ok "C3: the hook header documents how to read the measurement"
else
  bad "C3: the hook header should carry the counting command"
fi

# C4: and it must say the number is build-specific. ADR-0016's v2.1.154 experience is the reason:
# the transcript layout this rate depends on has already moved once, silently.
if grep -qi 'build-specific\|BUILD-SPECIFIC' "$HOOK"; then
  ok "C4: the header states the measurement is build-specific"
else
  bad "C4: the header should state that the rate must be stamped with the CC version"
fi

# =====================================================================================
# D. The phase-2 DECISION (issue #194, ADR-0080). The verdict was "keep the fallback", reached on a
# small sample, so what protects it is not the number — it is that the reasoning, the sample size
# and the condition for revisiting all live in this hook's own header. Before #194 this hook's
# behaviour was explained from write-scope-enforce.sh's header, about a third file.
# Flattened, and stripped of BOTH comment markers and backticks: the header wraps across comment
# lines and marks `src=main-fallback` as code, so a needle written in plain prose misses it. Third
# time this family has bitten (ADR-0073 line wrap, ADR-0076 comment marker) — a prose assertion
# must not depend on how the text is decorated any more than on where it breaks.
_flat=$(tr '\n' ' ' < "$HOOK" | sed 's/#//g; s/`//g')

# D1: the sample size is stated, not implied. A verdict on n=3 that does not say n=3 is the thing
# a later reader would take as settled.
printf '%s' "$_flat" | grep -q 'n=3' \
  && ok "D1: the header states the sample size the verdict rests on" \
  || bad "D1: the verdict must state its own sample size"

# D2: the pre-registered condition for dropping the fallback. Written BEFORE more data arrives so
# the outcome cannot be rationalised afterwards — that is the whole value of pre-registering.
if printf '%s' "$_flat" | grep -qi 'pre-registered' \
   && printf '%s' "$_flat" | grep -q 'src=main-fallback is 0 across'; then
  ok "D2: a pre-registered condition for dropping the fallback is recorded"
else
  bad "D2: the header must carry the condition under which the fallback gets dropped"
fi

# D3: and the opposite branch. "If it fires, drop it" would be exactly backwards — a fallback that
# fires is evidence the lookup is broken, and removing it would hide the breakage.
printf '%s' "$_flat" | grep -qi 'do NOT drop it' \
  && ok "D3: the header says a firing fallback means investigate, not remove" \
  || bad "D3: the non-zero branch must say do not drop"

# D4: the asymmetry with write-scope-enforce.sh is named as deliberate. Two hooks taking opposite
# decisions about the same fallback is exactly what a later reader would try to reconcile.
printf '%s' "$_flat" | grep -q 'actively wrong' \
  && ok "D4: the asymmetry with write-scope-enforce.sh is explained at this hook's own site" \
  || bad "D4: the header must say why the sibling hook refuses the same fallback"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
