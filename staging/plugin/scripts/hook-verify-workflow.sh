#!/bin/bash
# hook-verify-workflow v1.0 — decide `hook_verified` from evidence instead of eyesight.
#
# WHERE THIS FILE LIVES, because the two locations do not match (issue #212).
#   staging:  staging/plugin/scripts/hook-verify-workflow.sh          <- here, FLAT
#   deployed: ~/.claude/skills/concept-to-code/scripts/hook-verify-workflow.sh
# It is vendored flat by ADR-0016 and kept flat by ADR-0024, which refuses to create a second source
# of truth. `sync-to-claude.sh`'s PAIRS performs the remap, and concept-to-code/SKILL.md invokes the
# DEPLOYED path. Both sides are correct — do NOT "normalise" either. Repointing SKILL.md at a
# staging-shaped path would make it read a file sync never writes there.
# Declared in sync-to-claude.sh's `pairs-zone-anomaly:` line and pinned by
# pairs-completeness.test.sh ZA3/ZA5.
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
# Known limit (issue #33): when CLAUDE_CODE_SESSION_ID is unset (older CLI, or invoked outside a
# Claude Code subprocess) and exactly one OTHER Claude Code session -- not this one -- writes the
# only post-marker row, this script cannot tell it apart from our own session and still reports
# VERIFIED on foreign evidence. Session scoping (below) only closes the gap when the env var is set,
# or when 2+ concurrent sessions are involved (ambiguity is then detectable without knowing which one
# is ours). No stronger guarantee is possible from a stateless, read-only script reading a global log.
#
# Usage:
#   MARK=$(hook-verify-workflow.sh --mark)
#   ... run a one-agent workflow, spawned with agentType: 'coder', that Edits a file ...
#   hook-verify-workflow.sh --check "$MARK"
#
# Exit codes:
#   0  verified   — the guard enforced inside a workflow subagent. Record hook_verified=true.
#   1  refuted    — hooks did not enforce, or only a different, concurrent Claude Code session did.
#                    Record hook_verified=false. The reason says which failure.
#   2  usage
#   3  INCONCLUSIVE — either the audit log is missing/unreadable, or CLAUDE_CODE_SESSION_ID is unset
#      and the post-marker window mixes rows from more than one Claude Code session with no way to
#      tell which one is ours (issue #33). Record NOTHING either way.
#
# Exit 3 is the one that matters. A missing audit log means the guard is not installed; an ambiguous
# multi-session window means the evidence exists but cannot be attributed to this session. Neither
# means hooks fail to fire. Collapsing exit 3 into exit 1 would repeat, in the opposite direction,
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
AFTER_RAW=$(awk -F'\t' -v m="$MARK" '$1 > m' "$LOG" 2>/dev/null)

# Session scoping (issue #33): when Claude Code exposes CLAUDE_CODE_SESSION_ID (Bash-tool subprocess
# env var, code.claude.com/docs/en/env-vars -- the same value as the session_id field in the audit
# log's own field 2), filter the AFTER window to this session and its subagents. Subagents dispatched
# within one session (Task/Agent tool, or a workflow agent()) share the parent's session_id --
# confirmed by pre-flight-pattern-enforce.sh's own subagent-transcript-path derivation, which nests
# under the SAME $SID a coder subagent's hook payload reports (ADR-0004). This is what actually
# distinguishes "my workflow's coder" from any other concurrent Claude Code session on this machine
# writing to the same global audit log.
#
# When the env var is unavailable, there is no reference id to compare rows against. If the window
# carries rows from more than one distinct session, refuse to guess (INCONCLUSIVE, exit 3) rather than
# pick a side. If exactly one session id appears, fall through to the original, session-blind logic --
# this is also what every pre-existing fixture in this test file exercises, since none of them set the
# env var or mix session ids (ADR-0029 Section 2.1).
#
# Known residual gap (ADR-0029 Section 4, Negative, disclosed and pinned by test S5): with the env var
# unavailable AND exactly one OTHER (not ours) concurrent session producing the only post-marker row,
# this script still cannot tell it apart from our own and reports VERIFIED on foreign evidence. No
# stronger guarantee is possible from a stateless, read-only script (see the script's own header).
SID_SELF="${CLAUDE_CODE_SESSION_ID:-}"
SESSION_SCOPE="none"

if [ -n "$SID_SELF" ]; then
  AFTER=$(printf '%s\n' "$AFTER_RAW" | awk -F'\t' -v sid="$SID_SELF" '$2 == sid')
  SESSION_SCOPE="$SID_SELF"
else
  DISTINCT_SIDS=$(printf '%s\n' "$AFTER_RAW" | awk -F'\t' 'NF>0{print $2}' | sort -u | wc -l | tr -d ' ')
  if [ "$DISTINCT_SIDS" -gt 1 ]; then
    printf 'HOOK_VERIFY status=INCONCLUSIVE\n'
    printf 'reason=%s\n' "CLAUDE_CODE_SESSION_ID is not set and $DISTINCT_SIDS different Claude Code sessions recorded pattern-enforce decisions after $MARK. Cannot tell which one ran this workflow's smoke test, so this is not evidence either way. Re-run when no other Claude Code session is active on this machine, or use a Claude Code CLI version that sets CLAUDE_CODE_SESSION_ID (code.claude.com/docs/en/env-vars)."
    printf 'RECOMMEND hook_verified=unchanged\n'
    exit 3
  fi
  AFTER="$AFTER_RAW"
fi

if [ -z "$AFTER" ]; then
  if [ -n "$SID_SELF" ] && [ -n "$AFTER_RAW" ]; then
    printf 'HOOK_VERIFY status=REFUTED\n'
    printf 'reason=%s\n' "no pattern-enforce decision recorded for this session (CLAUDE_CODE_SESSION_ID=$SID_SELF) after $MARK. Decisions were recorded after $MARK, but they belong to other, concurrent Claude Code session(s) and are not evidence for this session's workflow smoke test. Confirm the workflow in THIS session actually dispatched with agentType: 'coder', then re-run."
    printf 'RECOMMEND hook_verified=false\n'
    exit 1
  fi
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

printf 'HOOK_VERIFY decisions_after_mark=%s enforced_on_coder=%s bypassed_workflow_subagent=%s session_scope=%s\n' \
  "$TOTAL" "$ENFORCED" "$BYPASSED_WF" "$SESSION_SCOPE"

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
