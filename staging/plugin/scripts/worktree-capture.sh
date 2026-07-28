#!/bin/bash
# worktree-capture v1.0 — TEMPORARY probe hook for the WorktreeCreate event (issue #176, ADR-0068
# Task 1). NOT a shipped guardrail. It exists to MEASURE the event's real payload contract before
# worktree-create.sh is written against it, and it is unregistered as soon as F13-F16 are recorded.
#
# Why it exists at all: SPEC F11's field list (base, branch, agent_type) is DOC-SOURCED, and the
# current schema disagrees with it (base_branch, worktree_branch, and possibly no agent_type at
# all). ADR-0068 §D2 refuses to let a doc-sourced line sit in a "measured facts" table, and R-04's
# scoping predicate depends on which of those fields actually arrives. So: measure, then write.
#
# Contract exercised here on purpose — WorktreeCreate has THREE exit states, not two:
#   exit 0 + path on stdout  = this hook took over creation, that path is the worktree
#   exit 0 + EMPTY stdout    = DECLINE, fall through to default git behaviour
#   exit non-zero            = abort the worktree creation entirely
# This script always takes the middle one. It appends the payload and declines, so registering it
# must not change what any worktree does. Whether the decline is actually honoured is itself one
# of the things being measured (Probe A) — if it is not, ADR-0068 §D3's fail-safe direction has to
# be revisited before Task 4 starts.
#
# NO MATCHER EXISTS for WorktreeCreate. While registered, this fires on every worktree creation on
# this machine, including `--worktree` sessions and background agents. That is why it is passive
# (append + decline) and why the registration window is meant to be short.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution.

DIR="${WORKTREE_PROBE_DIR:-$HOME/.claude/state/worktree-probe}"
OUT="$DIR/payloads.jsonl"
mkdir -p "$DIR" 2>/dev/null || true

INPUT=$(cat)

# Verbatim, one line, no jq dependency and no reformatting: the point of the probe is to see the
# payload exactly as the event delivers it, including any field this repo does not expect.
printf '%s\n' "$INPUT" >>"$OUT" 2>/dev/null || true

# Decline. Empty stdout, exit 0.
exit 0
