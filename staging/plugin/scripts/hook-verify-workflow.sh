#!/bin/bash
# hook-verify-workflow v1.0 — decide `hook_verified` from evidence instead of eyesight.
#
# Replaces the ADR-0016 smoke test, whose step 4 told an operator to "watch the terminal ... look for
# a line beginning with PATTERN:". That procedure cannot produce a correct answer, because
# "the hook never fired" and "the hook fired and stood down" both print nothing.
#
# The discriminator was always being written, by the guard itself, to
#   ${PATTERN_ENFORCE_DIR:-$HOME/.claude/state/pattern-enforce}/audit.log
# whose tab-separated columns are: ts, session_id, tool, decision, detail
# and whose three decisions are: bypass-noncoder | allow | block
#
# The detail column is NOT uniform, and this cost a rewrite. Verified against 4,639 real rows:
#   allow            -> detail is "PATTERN found in window"
#   block            -> detail is "PATTERN missing in window=20"
#   bypass-noncoder  -> detail is "agent_type=<value>"   (the ONLY decision that records agent_type)
#
# So an allow/block row cannot be matched on `agent_type=coder`; no such row exists. The invariant is
# stronger anyway: `pre-flight-pattern-enforce.sh` returns early unless `agent_type == "coder"` (its
# lines 91-94), so REACHING allow or block already proves a coder was ruled on. That is what this
# script keys off.
#
#   allow | block                                  -> the guard resolved the transcript and ruled.
#                                                     `block` proves enforcement exactly as `allow` does.
#   bypass-noncoder with agent_type=workflow-subagent
#                                                  -> the workflow spawned DEFAULT subagents. The
#                                                     dispatch failed to pass agentType: 'coder'.
#   nothing at all                                 -> no hook fired after the marker.
#
# Known limit: the audit log does not distinguish a *workflow* coder from an Agent-tool coder, because
# neither records agent_type on an allow. The marker bounds the window to the smoke dispatch, so in
# practice the only coder running is the workflow's. Do not run this check while another coder agent
# is working in the same session.
#
# Usage:
#   MARK=$(hook-verify-workflow.sh --mark)
#   ... run a one-agent workflow, spawned with agentType: 'coder', that Edits a file ...
#   hook-verify-workflow.sh --check "$MARK"
#
# Exit codes:
#   0  verified   — the guard enforced inside a workflow subagent. Record hook_verified=true.
#   1  refuted    — hooks did not enforce. Record hook_verified=false. The reason says which failure.
#   2  usage
#   3  INCONCLUSIVE — the audit log is missing or unreadable. Record NOTHING.
#
# Exit 3 is the one that matters. A missing audit log means the guard is not installed; it does NOT
# mean hooks fail to fire. Collapsing exit 3 into exit 1 would repeat, in the opposite direction,
# precisely the mistake the old terminal-watching procedure made.
#
# Bash 3.2 clean. Read-only: never writes a manifest, never touches the audit log.

set -u

DIR="${PATTERN_ENFORCE_DIR:-$HOME/.claude/state/pattern-enforce}"
LOG="$DIR/audit.log"

usage() {
  printf 'usage: hook-verify-workflow.sh --mark\n' >&2
  printf '       hook-verify-workflow.sh --check <iso8601-marker>\n' >&2
  exit 2
}

[ "$#" -ge 1 ] || usage

case "$1" in
  --mark)
    [ "$#" -eq 1 ] || usage
    # ISO-8601 UTC. Lexical order matches chronological order for this format, so --check can
    # compare with a plain string test and never needs to parse a date.
    date -u +%Y-%m-%dT%H:%M:%SZ
    exit 0
    ;;
  --check)
    [ "$#" -eq 2 ] || usage
    MARK="$2"
    ;;
  *)
    usage
    ;;
esac

case "$MARK" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
  *) printf 'hook-verify-workflow: marker is not ISO-8601 UTC (got: %s)\n' "$MARK" >&2; usage ;;
esac

if [ ! -r "$LOG" ]; then
  printf 'HOOK_VERIFY status=INCONCLUSIVE\n'
  printf 'reason=%s\n' "audit log not readable: $LOG"
  printf 'note=%s\n' "pre-flight-pattern-enforce is not installed or has never run. This is NOT evidence that hooks fail to fire. Record nothing."
  printf 'RECOMMEND hook_verified=unchanged\n'
  exit 3
fi

# Lines strictly after the marker. Field 1 is the timestamp; a lexical > is chronologically correct.
AFTER=$(awk -F'\t' -v m="$MARK" '$1 > m' "$LOG" 2>/dev/null)

if [ -z "$AFTER" ]; then
  printf 'HOOK_VERIFY status=REFUTED\n'
  printf 'reason=%s\n' "no pattern-enforce decision recorded after $MARK. The guard never saw an Edit/Write. Either the workflow never dispatched, or hooks are disabled (check disableAllHooks, allowManagedHooksOnly, and the workspace trust dialog)."
  printf 'RECOMMEND hook_verified=false\n'
  exit 1
fi

# `allow` or `block`: the guard resolved the subagent transcript and made a real decision. It cannot
# reach either branch unless agent_type == "coder", so the decision itself is the evidence. Do not
# add an `agent_type=coder` match here: no such row is ever written.
ENFORCED=$(printf '%s\n' "$AFTER" \
  | awk -F'\t' '$4 == "allow" || $4 == "block"' | wc -l | tr -d ' ')

# The silent bypass: hooks fired, the guard ran, and it stood down on the agent_type check.
BYPASSED_WF=$(printf '%s\n' "$AFTER" \
  | awk -F'\t' '$4 == "bypass-noncoder" && $5 ~ /agent_type=workflow-subagent$/' | wc -l | tr -d ' ')

TOTAL=$(printf '%s\n' "$AFTER" | wc -l | tr -d ' ')

printf 'HOOK_VERIFY decisions_after_mark=%s enforced_on_coder=%s bypassed_workflow_subagent=%s\n' \
  "$TOTAL" "$ENFORCED" "$BYPASSED_WF"

if [ "$ENFORCED" -gt 0 ]; then
  printf 'HOOK_VERIFY status=VERIFIED\n'
  printf 'reason=%s\n' "pre-flight-pattern-enforce reached its allow/block branch, which it cannot do unless agent_type == 'coder'. It resolved the subagent's transcript and ruled on it. Hooks propagate and the guard enforces. The Step-5 workflow path may be used."
  printf 'RECOMMEND hook_verified=true\n'
  exit 0
fi

if [ "$BYPASSED_WF" -gt 0 ]; then
  printf 'HOOK_VERIFY status=REFUTED\n'
  printf 'reason=%s\n' "hooks fired, but every workflow agent reported agent_type=workflow-subagent, so the guard bypassed on its agent_type check and enforced nothing. The dispatch did not pass agentType: 'coder'. Fix the dispatch, then re-run: this is a workflow-script problem, not a platform limitation."
  printf 'RECOMMEND hook_verified=false\n'
  exit 1
fi

printf 'HOOK_VERIFY status=REFUTED\n'
printf 'reason=%s\n' "decisions were recorded after the marker, but none came from a workflow subagent. The smoke prompt probably ran in the main loop rather than dispatching a workflow. Re-run with an explicit one-agent workflow."
printf 'RECOMMEND hook_verified=false\n'
exit 1
