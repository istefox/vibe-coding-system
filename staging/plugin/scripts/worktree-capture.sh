#!/bin/bash
# worktree-capture v2.0 — a measuring instrument, not a hook to wire (ADR-0068 §D2). It exists to
# re-answer F13/F14 after a future CC bump, never to run in production.
#
# WorktreeCreate has TWO outcomes, path-or-abort, with NO abstain state (F13, F14). Registering
# this script aborts every worktree creation on the machine, in every project, until it is
# unregistered — it never returns a worktree path, so every dispatch that goes through this event
# fails the moment the hook is active. Do not add it to any settings.json hooks object.
#
# What F13/F14 measured (issue #176, ADR-0068 Task 1): SPEC F11's field list (base, branch,
# agent_type) was doc-sourced and wrong. The real payload carries exactly six fields — session_id,
# transcript_path, cwd, prompt_id, hook_event_name, name — and none of them identifies the agent
# about to run (F13). A registered WorktreeCreate hook must return a usable worktree path on every
# invocation: exit 0 with empty stdout does NOT decline and fall through to default git behaviour,
# it ABORTS the dispatch with "WorktreeCreate hook failed: hook succeeded but returned no worktree
# path" (F14). Those two facts compound (ADR-0068 §D1/§D2): there is no discriminator to scope a
# hook on and no way for a hook to abstain, so worktree-create.sh is not written and this script is
# never registered anywhere. worktree.baseRef: "head" is the one mechanism this system actually
# uses (ADR-0068 §D1).
#
# Why this file is retained anyway: ADR-0016's own lesson is that platform evidence is
# build-specific (v2.1.154 silently moved workflow subagent transcripts). F13-F18 are true of CC
# 2.1.220 and of nothing else. Re-running this probe after a major CC bump is cheaper than
# re-deriving the payload contract from scratch — that is this script's only purpose.
#
# It is staging-only tooling with NO PAIRS entry (same terms as hook-probe-sandbox.sh,
# hook-probe.sh and hook-probe-verify.sh): a file deployed next to a wiring note reads like
# something to wire, and this one must never be wired.
#
# Exit behaviour (changed from v1.0): F14 established that both an empty-stdout decline and a
# non-zero exit abort the dispatch identically, so this script now exits non-zero with an
# explanatory stderr line naming itself, instead of exit 0 with empty stdout — an operator seeing
# the abort gets a message that identifies the cause, not the platform's generic "hook succeeded
# but returned no worktree path".
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution.

DIR="${WORKTREE_PROBE_DIR:-$HOME/.claude/state/worktree-probe}"
OUT="$DIR/payloads.jsonl"
mkdir -p "$DIR" 2>/dev/null || true

INPUT=$(cat)

# Verbatim, one line, no jq dependency and no reformatting: the point of the probe is to see the
# payload exactly as the event delivers it, including any field this repo does not expect.
printf '%s\n' "$INPUT" >>"$OUT" 2>/dev/null || true

# Abort, with a message naming the cause. Never register this hook (see header).
echo "worktree-capture.sh: this is a re-measurement instrument, not a hook to wire (ADR-0068 F13/F14). Aborting on purpose — unregister it in settings.json's hooks object." >&2
exit 1
