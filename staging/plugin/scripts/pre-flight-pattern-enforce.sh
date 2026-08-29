#!/bin/bash
# pre-flight-pattern-enforce v1.6 — gate for coder agent: blocks Edit/Write/MultiEdit
# if PATTERN: header is missing in the sliding window (ADR-0004, ADR-0001 contract).
# Contract: exit 0 + empty stdout = allow; exit 0 + {"decision":"block",...} = block.
# Fail-open on any internal error (never exit non-zero, never crash visibly).
# Bash 3.2 clean: no assoc array, no mapfile, no ${v^^}, no process substitution.
#
# v1.1 fix (2026-05-21, debugger root-cause):
# - agent_type is in the PreToolUse payload directly (.agent_type), NOT in transcript.
#   The old code searched .subagent_type in the transcript jsonl — that field does not
#   exist; the correct field is .agent_type in stdin JSON.
# - The PATTERN: search must use the subagent's own jsonl
#   (<proj>/<SID>/subagents/agent-<agent_id>.jsonl), not the main session jsonl
#   (transcript_path in the payload points to the main jsonl which contains NO sub-agent
#   messages; sub-agent messages live in the separate subagent file).
#
# v1.2 fix (2026-05-22, debugger root-cause):
# - Path-encoding bug: the old code re-encoded cwd via tr '/' '-', but Claude Code also
#   converts '_' (and potentially other chars) to '-' when encoding project dirs. The
#   encoding rule is not stable across CC versions (both Obsidian-MCP and Obsidian_MCP
#   exist in ~/.claude/projects/). Fix: derive project dir from transcript_path field
#   in the payload (already correctly encoded by CC), never re-encode cwd.
# - Block message: removed bypass instructions from coder-visible reason; bypass is an
#   orchestrator/user decision, not a coder action.
#
# v1.3 fix (2026-05-29, smoke test 2026-05-29):
# - Workflow subagent path: Dynamic Workflows (v2.1.154+) store subagent transcripts
#   at <proj>/<SID>/subagents/workflows/<wf_id>/agent-<id>.jsonl, not at the regular
#   <proj>/<SID>/subagents/agent-<id>.jsonl path. Added a find-based fallback that
#   searches under workflows/ when the direct path is missing.
#
# v1.4 fix (2026-06-11, extended-thinking models):
# - Extended-thinking models (Fable 5) emit the PATTERN: header inside `.thinking`
#   content blocks rather than `.text` blocks — the old jq filter `.text? // empty`
#   never saw them, so every Write was blocked even with a correct header.
#   Fix: extract BOTH .text and .thinking content from assistant turns so the grep
#   finds the header regardless of which block type the model used.
#
# v1.5 fix (2026-07-11, issue #38):
# - permissionDecision was "block", outside the verified enum (allow/deny/ask/defer,
#   ADR-0009). Changed to "deny" in both the jq template and the printf fallback.
#   A future Claude Code update that starts strictly validating this enum would
#   otherwise silently fail-open on every coder Edit/Write/MultiEdit — the exact
#   opposite of what this guardrail exists to do.
#
# v1.6 (2026-07-29, issue #194 phase 1 — INSTRUMENTATION ONLY, no behaviour change):
# - Every coder-path decision now records WHICH transcript produced it, as `src=<token>`
#   inside the existing free-text reason column. Nothing about what is allowed or blocked
#   changed; only what the log says about it.
#
#   THE QUESTION THIS EXISTS TO ANSWER. The fallback below (line ~140) reads the MAIN
#   SESSION jsonl when the subagent's own transcript cannot be found. It then scans
#   assistant entries and ALLOWS on a match — so a subagent whose transcript is missing
#   inherits the ORCHESTRATOR's recent output, and a `PATTERN:` line the orchestrator
#   emitted (it edits files too) satisfies the check for an agent that declared nothing.
#   `write-scope-enforce.sh` refuses this exact fallback for itself and explains why in ITS
#   header, calling a missed check here acceptable. That is a judgement, never a
#   measurement: the log recorded `allow  PATTERN found in window` for both paths, so the
#   question was not answerable retrospectively at all.
#
#   HOW TO READ IT (the denominator is every coder decision, hence src= on fail-open too):
#     awk -F'\t' '$5 ~ /src=/' "$LOG" | grep -o 'src=[a-z-]*' | sort | uniq -c
#   `src=main-fallback` paired with action `allow` is the case in question.
#
#   THE NUMBER IS BUILD-SPECIFIC AND MUST BE STAMPED WITH THE CC VERSION IT WAS TAKEN ON.
#   v2.1.154 silently moved workflow subagent transcripts to subagents/workflows/<wf_id>/,
#   which is what v1.3 below exists to handle — the layout this measurement depends on has
#   already moved once (ADR-0016). A rate measured on one build says nothing about the next.
#
#   Column format is UNCHANGED (5 tab-separated fields): hook-verify-workflow.sh parses $1
#   and $2, so the token goes inside the prose field rather than into a sixth column.
#
#   Side effect worth knowing: `src=` also separates a workflow coder from an Agent-tool
#   coder, which hook-verify-workflow.sh documents as a known limit of this same log, in its
#   "an allow/block row cannot be matched on `agent_type=coder`" paragraph.
#   That limit is narrowed here as a by-product; hook-verify-workflow.sh itself is
#   deliberately NOT changed — phase 1 instruments, it does not decide.
#
# v1.7 (2026-08-29, VCS-044): extraction reorder only, no behaviour change. AGENT_TYPE is the
# field that decides the common-case early bail (non-coder / orchestrator); TOOL, CWD and
# AGENT_ID are only needed on the coder path. Extracting all four before the bail check spawned
# 3 unnecessary jq processes on every non-coder Edit/Write/MultiEdit, which is the overwhelming
# majority of calls into this hook. AGENT_TYPE now extracts and gates first; the rest extract
# only once the coder path is confirmed. agent-write-scope.sh already used this shape (its own
# header notes "the whole input" is exactly the fields the static per-type scope needs).
#
# v1.6 phase 2 (2026-07-29, issue #194 — THE DECISION, measured on CC 2.1.220).
# - VERDICT: the main-session fallback STAYS. Recorded here rather than in write-scope-enforce.sh's
#   header, which is where this hook's behaviour had been explained from until now.
#
#   WHAT WAS MEASURED, and it is a small sample stated as one. A controlled coder dispatch made
#   three Edit/Write calls: all three logged `src=subagent`, INCLUDING THE FIRST. That refutes the
#   one mechanism that would have made the fallback fire routinely — a flush race, where the
#   subagent's transcript does not exist yet when its first PreToolUse fires. It does exist: the
#   file was born at 19:15:58Z and the first decision was logged at 19:16:02Z, four seconds later.
#   Supporting evidence, 193 files: both transcript layouts are present on disk under this project
#   (137 regular, 56 under subagents/workflows/<wf_id>/) and both match the two lookups below.
#
#   WHY KEEP IT ANYWAY. Dropping it turns a rare false ALLOW into a rare chain-breaking DENY, and
#   fail-open on every internal error is this file's stated contract (its header's
#   "Fail-open on any internal error" line). The asymmetry with
#   write-scope-enforce.sh is real and is NOT an inconsistency: that hook's fallback would be
#   actively wrong — it would bind a write scope from the orchestrator's text — while this one is
#   merely permissive. Different failure, different correct answer.
#
#   THE RESIDUAL IS REAL AND UNMEASURED: n=3, Agent-tool path only. No Workflow dispatch was
#   probed, and that is the path v2.1.154 silently relocated.
#
#   PRE-REGISTERED, so the next reader does not re-litigate from scratch and so the outcome cannot
#   be rationalised after the fact:
#     - Count with the command above. If `src=main-fallback` is 0 across >= 50 coder decisions
#       spanning at least one Workflow dispatch, DROP the fallback: it is then dead code whose only
#       possible effect is to fail open.
#     - If it is non-zero, do NOT drop it. Find out why the lookup failed first — a fallback that
#       fires is evidence the lookup is broken, and removing it would hide that.
#     - Re-run the probe after any major CC bump. This verdict is build-stamped on purpose.

#
# transcript-scan-exempt: reads ASSISTANT entries, not `user` entries, and ALLOWS on a match rather
#   than deriving a scope from one. Both halves matter. A tool result is a `user` entry, so a file
#   an agent READS cannot arm this hook at all — the #127 mechanism does not reach it. And because
#   a match allows, a spurious match is a MISSED CHECK, never the deadlock #127 produced. The
#   exemption is on DIRECTION, which is the weaker kind: this hook's real exposure is that the
#   main-session fallback lets the orchestrator's own PATTERN line satisfy the check for a subagent
#   that declared nothing. That is issue #194 — measured and decided in v1.6 phase 2 above (the
#   fallback stays, on a stated n=3 with a pre-registered condition for dropping it), NOT closed by
#   this exemption. Do not read this line as "audited and fine".

DIR="${PATTERN_ENFORCE_DIR:-$HOME/.claude/state/pattern-enforce}"
LOG="$DIR/audit.log"
DISABLED="$DIR/disabled"
WINDOW="${PATTERN_ENFORCE_WINDOW:-20}"

mkdir -p "$DIR" 2>/dev/null || true

# Audit log helper: $1=session $2=tool $3=action $4=reason
log_audit() {
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" >>"$LOG" 2>/dev/null || true
}

# --- Bypass mechanisms: HUMAN-ONLY (P4 contract) ---
# The bypasses below (PATTERN_ENFORCE=off env var, the `disabled` file flag) are
# EXPLICIT HUMAN decisions. Neither sub-agents nor the orchestrator may set/create them
# autonomously to get past a block. If this hook looks buggy: a sub-agent STOPS and
# reports; the orchestrator asks the user. Disabling a guardrail is the user's call only.
# (In auto mode the env var does not propagate from a shell subprocess and the file
# flag creation is denied by the classifier — both by design, not a defect to work around.)

# Bypass 1: env var single-call
if [ "$PATTERN_ENFORCE" = "off" ]; then
  log_audit "?" "?" "bypass-env" "env PATTERN_ENFORCE=off"
  exit 0
fi

# Bypass 2: file flag global
if [ -f "$DISABLED" ]; then
  log_audit "?" "?" "bypass-file" "$DISABLED present"
  exit 0
fi

# Read stdin (consume once)
INPUT=$(cat)

# Require jq
command -v jq >/dev/null 2>&1 || { log_audit "?" "?" "fail-open" "jq missing"; exit 0; }

# Extract session_id (fail-open if missing or malformed JSON)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && { log_audit "?" "?" "fail-open" "no session_id (malformed or empty JSON)"; exit 0; }

# v1.1: agent_type is a first-class field in the PreToolUse payload (not in transcript).
# v1.7: extracted alone, first — it is the field that decides the bail below, and the common
# case (non-coder or orchestrator) never needs TOOL/CWD/AGENT_ID at all.
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)

# Discriminator: agent_type in payload (not subagent_type in transcript).
# Non-coder or orchestrator (agent_type absent or != coder) → bypass silent.
if [ "$AGENT_TYPE" != "coder" ]; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  log_audit "$SID" "$TOOL" "bypass-noncoder" "agent_type=$AGENT_TYPE"
  exit 0
fi

# Coder path confirmed: extract the remaining fields only now.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)

# Coder path: find the subagent's own jsonl for PATTERN: search.
# v1.2: derive project dir from transcript_path in the payload (already CC-encoded).
# Never re-encode cwd — Claude Code's encoding is not stable (e.g. '_' may become '-').
# transcript_path points to the main session jsonl: <proj_dir>/<SID>.jsonl
# Regular subagent jsonl:  <proj_dir>/<SID>/subagents/agent-<id>.jsonl
# Workflow subagent jsonl: <proj_dir>/<SID>/subagents/workflows/<wf_id>/agent-<id>.jsonl
TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
TRANSCRIPT=""
# v1.6: which of the three lookups won. Never used for a decision — only logged.
TSRC="none"
if [ -n "$AGENT_ID" ] && [ -n "$TP" ]; then
  PROJ_DIR=$(dirname "$TP")
  SUBAGENT_CANDIDATE="$PROJ_DIR/$SID/subagents/agent-$AGENT_ID.jsonl"
  [ -f "$SUBAGENT_CANDIDATE" ] && { TRANSCRIPT="$SUBAGENT_CANDIDATE"; TSRC="subagent"; }
fi

# v1.3: workflow subagent path — search under subagents/workflows/*/
if [ -z "$TRANSCRIPT" ] && [ -n "$AGENT_ID" ] && [ -n "$TP" ]; then
  PROJ_DIR=$(dirname "$TP")
  WORKFLOWS_DIR="$PROJ_DIR/$SID/subagents/workflows"
  if [ -d "$WORKFLOWS_DIR" ]; then
    WF_CANDIDATE=$(find "$WORKFLOWS_DIR" -name "agent-$AGENT_ID.jsonl" 2>/dev/null | head -1)
    [ -n "$WF_CANDIDATE" ] && [ -f "$WF_CANDIDATE" ] && { TRANSCRIPT="$WF_CANDIDATE"; TSRC="workflow"; }
  fi
fi

# Fallback: main session jsonl from transcript_path (already correctly encoded).
# Do NOT fall back to re-encoding cwd — that is the source of the path-encoding bug.
if [ -z "$TRANSCRIPT" ]; then
  if [ -n "$TP" ] && [ -f "$TP" ]; then
    TRANSCRIPT="$TP"
    TSRC="main-fallback"
  fi
fi

# Fail-open if transcript still not found
if [ ! -f "$TRANSCRIPT" ]; then
  log_audit "$SID" "$TOOL" "fail-open" "transcript not found (agent_id=$AGENT_ID) src=$TSRC"
  exit 0
fi

# Coder path: extract WINDOW most recent assistant message texts from subagent transcript
# v1.4: include .thinking blocks — extended-thinking models emit the header there.
RECENT=$(tail -n 200 "$TRANSCRIPT" 2>/dev/null \
  | jq -r 'select(.type=="assistant") | .message.content[]? | (.text? // empty), (.thinking? // empty)' 2>/dev/null \
  | tail -n "$WINDOW")

# Match PATTERN: header. Canonical categories: ADD|REMOVE|REPLACE|MODIFY.
# CREATE|NEW are tolerated aliases of ADD (the model emits them naturally for new
# files); the hook enforces the *presence* of a declarative header, not the exact
# taxonomy word — fine-grained category validation is the reviewer's pattern-drift job.
if printf '%s\n' "$RECENT" | grep -E '^PATTERN: (ADD|REMOVE|REPLACE|MODIFY|CREATE|NEW) \|' >/dev/null 2>&1; then
  log_audit "$SID" "$TOOL" "allow" "PATTERN found in window src=$TSRC"
  exit 0
fi

# xref-exempt: file.py:42 — an illustrative path inside the deny message's own PATTERN example
# below, shown to the coder so it can format its header. Not a reference into another file.
# Block: PATTERN missing
log_audit "$SID" "$TOOL" "block" "PATTERN missing in window=$WINDOW src=$TSRC"
jq -nc --arg r "pre-flight-pattern-enforce: PATTERN: header missing in sliding window. ADR-0001 requires emitting \`PATTERN: <CATEGORY> | <payload>\` before every Edit/Write/MultiEdit. Example: \`PATTERN: MODIFY | path/file.py:42 rename var\`. Emit the header and retry. If the block persists, STOP and report to the orchestrator — do NOT attempt to bypass or disable this guardrail." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"missing PATTERN header (see ADR-0001)"}}\n'
exit 0
