#!/bin/bash
# codex-coder.sh v1.0 — Codex CLI substitute for the `coder` agent (Codex-vs-Claude coder backend
# choice, ADR-0196). Bash 3.2-clean. Run: bash codex-coder.sh --worktree <dir> --brief <file>
# --out <file> --model <astra|sol> --effort <value>
#
# WHY THIS EXISTS. The chain's `coder` agent contract (`staging/plugin/agents/coder.md` — plan
# fidelity, never commit, TEST-AUTHORING SCOPE, PATTERN pre-flight, Output Format) spends Claude
# Code tokens at both Step 5 dispatch sites. This script lets those same sites dispatch to Codex
# CLI instead, gated behind `manifest.use_codex_coder` — a SUBSTITUTE for the Claude coder, never a
# second opinion run alongside it.
#
# CONTRACT — a CHECKER, not a reporter (rule 5): the caller branches on the exit code, never on
# whether stdout is empty.
#   exit 0 — success. The markdown report is written to --out, in the SAME Output Format shape
#            coder.md's own Output Format produces, so a caller can consume it identically either
#            way. Also covers the "Codex wrote nothing" edge case (empty touched-path set, a
#            distinct NOTE: line on stderr — a no-op run is not the same fact as a scope violation).
#   exit 2 — bad invocation (missing/unknown flag, missing required argument, unreadable --brief,
#            unrecognised --model). One line on stderr, "codex-coder: " prefixed.
#   exit 3 — DID-NOT-RUN (rule 4). One line on stderr, "codex-coder: DID-NOT-RUN: <reason>" — the
#            ONE signal callers gate the fallback-to-Claude AskUserQuestion on (Stefano's own
#            policy: never a silent fallback).
#   exit 4 — SCOPE-VIOLATION: Codex touched a path outside a coder's legitimate scope (a test file,
#            .claude/test-cmd, the memory index, more than one new memory shard, or a new commit
#            inside the worktree). The partial report is still written to --out (a partial report is
#            more useful than none); the caller asks the user to accept the write, fall back to
#            Claude, or halt.
#
# PROMPT DUPLICATION, DECLARED (rule 6/12). CODER_PROMPT below is hand-ported from
# `staging/plugin/agents/coder.md`'s Hard rules / Process / Quality Standards / Output Format /
# Edge Cases sections — a true single source is not mechanically possible here (one runtime is a
# Claude Code agent system prompt, the other a `codex exec` CLI prompt embedding its own brief).
# When coder.md's contract changes, re-check this file's CODER_PROMPT for drift. Three things
# cannot port at all, and are documented gaps rather than omissions (ADR-0196 §Refinements R10):
# the pre-flight PATTERN header (no per-tool-call hook exists on a `codex exec` run — replaced by
# the post-hoc, non-blocking `pattern_classification` field below), "a hook block is a signal, not
# an obstacle" (there are no Claude hooks in a Codex run to be blocked by), and the tool-conditional
# steps that depend on LSP, mcp__eslint__* and context7.
#
# CASCADE/REGEX DUPLICATION, DECLARED (rule 6/12; ADR-0196 §Refinements R9). The availability
# cascade (codex-on-PATH check, `codex doctor --json` auth probe) and the rate-limit vocabulary
# grep below are copied from `codex-reviewer.sh`/`codex-tester.sh` byte-for-byte rather than shared
# through a helper — extraction to a shared `codex-common.sh` is a named follow-up, not done here
# (changing the two existing scripts is out of this SPEC's scope, and a shared source that breaks
# disables three consumers at once). This is now the THIRD copy of the same cascade; ADR-0194 §R7
# could still call extraction "a named follow-up" for two copies, and at three that sentence is
# weaker than it was — recorded as such, not restated as though nothing changed. A harness
# assertion (CK10) pins the three copies' load-bearing needles identical so a future fix applied to
# one and not the others is caught.
#
# SANDBOX AS ENFORCEMENT (rule 16), AND WHAT IT STANDS IN FOR. The `workspace-write` sandbox mode,
# scoped with `-C "$WORKTREE"` below, on `codex exec` is what actually constrains Codex to write
# only inside the dispatch's own worktree — a runtime guarantee, not an instruction Codex is asked
# to obey. This script's own
# post-run scope check, below, is a SECOND, INDEPENDENT guard: the sandbox stops writes outside the
# worktree; the scope check catches a write that lands inside the worktree but outside a coder's
# legitimate scope, which workspace-write alone does not forbid. Together the two are standing in
# for four PreToolUse hooks that cannot fire here at all: `pre-flight-pattern-enforce.sh`,
# `write-scope-enforce.sh`, `test-write-scope.sh` and `coder-memory-scope.sh` all key off Claude's
# own Edit/Write/MultiEdit tool calls and an `agent_type` the orchestrator's dispatch carries — a
# `codex exec` subprocess is one opaque Bash call with neither (ADR-0196 documented gap 1). Neither
# the sandbox nor the scope check is a preventive block: by the time the check runs, the write has
# already happened inside the isolated worktree.
#
# CODEX CLI SHAPE, VERIFIED LIVE (rule 13, 2026-09-07 — not assumed from --help alone; see
# ADR-0196): `~/.codex/models_cache.json` lists both the astra and sol model slugs (mapped to their
# full names below) as valid, alongside `gpt-5.6-terra`, `gpt-5.6-luna` and others. `codex exec
# --help`'s flag shape
# (`-s/--sandbox <read-only|workspace-write|danger-full-access>`, `-C/--cd <DIR>`,
# `--output-schema <FILE>`, `-o/--output-last-message <FILE>`, `-c <key>=<value>`) is the one
# ADR-0194 verified live on 2026-09-06 and `codex-tester.sh` has used since. `--model` maps to
# `-c model=<slug>` (never `-m`, unlike `codex-reviewer.sh`'s hardcoded pin) because both model and
# effort are a live per-dispatch choice here, not a fixed config default (ADR-0196 §Refinements R2).
set -u

WORKTREE=""
BRIEF=""
OUT=""
MODEL=""
EFFORT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --worktree) WORKTREE="${2:-}"; shift 2 ;;
    --brief) BRIEF="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --effort) EFFORT="${2:-}"; shift 2 ;;
    *) echo "codex-coder: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$WORKTREE" ]; then
  echo "codex-coder: --worktree is required" >&2
  exit 2
fi

if [ -z "$BRIEF" ]; then
  echo "codex-coder: --brief is required" >&2
  exit 2
fi

if [ ! -f "$BRIEF" ] || [ ! -r "$BRIEF" ]; then
  echo "codex-coder: --brief file not readable: $BRIEF" >&2
  exit 2
fi

if [ -z "$OUT" ]; then
  echo "codex-coder: --out is required" >&2
  exit 2
fi

if [ -z "$MODEL" ]; then
  echo "codex-coder: --model is required (astra|sol)" >&2
  exit 2
fi

if [ -z "$EFFORT" ]; then
  echo "codex-coder: --effort is required" >&2
  exit 2
fi

# --- Model mapping, explicit case, closed set (ADR-0196). No default value is assigned to MODEL
# or EFFORT anywhere in this script — both are required, live, per-dispatch choices. -------------
case "$MODEL" in
  astra) SLUG="gpt-6-astra" ;;
  sol) SLUG="gpt-5.6-sol" ;;
  *) echo "codex-coder: unknown --model value '$MODEL' (astra|sol)" >&2; exit 2 ;;
esac

# --- Availability cascade, never silent (rule 4) — byte-identical to codex-reviewer.sh's and
# codex-tester.sh's own (declared duplication above; CK10 pins the drift-sensitive substrings) ----

if ! command -v codex >/dev/null 2>&1; then
  echo "codex-coder: DID-NOT-RUN: codex CLI not installed" >&2
  exit 3
fi

DOCTOR_JSON=$(codex doctor --json 2>/dev/null)
if [ -z "$DOCTOR_JSON" ] || ! command -v python3 >/dev/null 2>&1; then
  echo "codex-coder: DID-NOT-RUN: codex doctor produced no output, or python3 unavailable to parse it" >&2
  exit 3
fi
AUTH_STATUS=$(DOCTOR_JSON="$DOCTOR_JSON" python3 -c "
import json, os, sys
try:
    d = json.loads(os.environ['DOCTOR_JSON'])
    print(d.get('checks', {}).get('auth.credentials', {}).get('status', ''))
except Exception:
    print('')
" 2>/dev/null)
if [ "$AUTH_STATUS" != "ok" ]; then
  echo "codex-coder: DID-NOT-RUN: codex not authenticated (auth.credentials status: '${AUTH_STATUS:-unreadable}' — run 'codex doctor' for remediation)" >&2
  exit 3
fi

if ! git -C "$WORKTREE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "codex-coder: DID-NOT-RUN: worktree is not a git repository: $WORKTREE" >&2
  exit 3
fi

# --- Baseline capture, BEFORE any codex exec. Pre-existing dirt in the worktree must never be
# attributed to Codex. Union of git diff, git diff --cached, and untracked files, PLUS the current
# HEAD sha — the sha is what the NEW-COMMIT scope class compares against below. -------------------

BASELINE_FILE=$(mktemp)
AFTER_FILE=$(mktemp)
REMAINING_FILE=$(mktemp)
SCHEMA_FILE=$(mktemp)
PROMPT_FILE=$(mktemp)
RAW_OUT=$(mktemp)
trap 'rm -f "$BASELINE_FILE" "$AFTER_FILE" "$REMAINING_FILE" "$SCHEMA_FILE" "$PROMPT_FILE" "$RAW_OUT"' EXIT

# One question (rule 6): "what does the worktree's changed+untracked file set look like right
# now", asked twice at two different times (baseline, after). A shared function keeps the two
# answers from drifting apart instead of two copies of the same three git calls.
_snapshot_worktree_files() {
  git -C "$WORKTREE" diff --name-only 2>/dev/null
  git -C "$WORKTREE" diff --name-only --cached 2>/dev/null
  git -C "$WORKTREE" ls-files --others --exclude-standard 2>/dev/null
}

_snapshot_worktree_files | sort -u > "$BASELINE_FILE"

BASELINE_HEAD=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null)

# --- Schema (--output-schema): eight properties matching coder.md's Output Format plus the two
# additions ADR-0196 names (plan_deviations, pattern_classification). Every object, including
# nested ones and array items whose type is object, carries "additionalProperties": false — without
# it codex exec fails invalid_json_schema before the model ever runs (S_C pins this). -------------

cat > "$SCHEMA_FILE" <<'SCHEMA_EOF'
{
  "type": "object",
  "properties": {
    "files_modified": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "path": {"type": "string"},
          "purpose": {"type": "string"}
        },
        "required": ["path", "purpose"],
        "additionalProperties": false
      }
    },
    "sub_steps": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "step": {"type": "string"},
          "status": {"type": "string"},
          "reason": {"type": "string"}
        },
        "required": ["step", "status", "reason"],
        "additionalProperties": false
      }
    },
    "key_decisions": {
      "type": "array",
      "items": {"type": "string"}
    },
    "verification": {
      "type": "object",
      "properties": {
        "command": {"type": "string"},
        "exit_code": {"type": "integer"},
        "result": {"type": "string"}
      },
      "required": ["command", "exit_code", "result"],
      "additionalProperties": false
    },
    "drafted_commit": {
      "type": "object",
      "properties": {
        "subject": {"type": "string"},
        "body": {"type": "string"}
      },
      "required": ["subject", "body"],
      "additionalProperties": false
    },
    "cleanup": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "item": {"type": "string"},
          "disposition": {"type": "string"}
        },
        "required": ["item", "disposition"],
        "additionalProperties": false
      }
    },
    "plan_deviations": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "task": {"type": "string"},
          "constraint": {"type": "string"},
          "action": {"type": "string"},
          "why": {"type": "string"}
        },
        "required": ["task", "constraint", "action", "why"],
        "additionalProperties": false
      }
    },
    "pattern_classification": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "pattern": {"type": "string"},
          "path": {"type": "string"},
          "intent": {"type": "string"}
        },
        "required": ["pattern", "path", "intent"],
        "additionalProperties": false
      }
    }
  },
  "required": ["files_modified", "sub_steps", "key_decisions", "verification", "drafted_commit", "cleanup", "plan_deviations", "pattern_classification"],
  "additionalProperties": false
}
SCHEMA_EOF

# --- Prompt, hand-ported from coder.md (see header comment) — rule 6/12 cross-reference. ---------

cat > "$PROMPT_FILE" <<PROMPT_EOF
You are a senior implementation engineer working against a single isolated worktree. You turn an
approved plan or ADR into minimal, idiomatic production code. You never commit and never
\`git add\` — your changes ride the orchestrator's merge-back.

TEST-AUTHORING SCOPE: never create or edit a test file — the tester owns them for this batch. Never
read, write or modify \`.claude/test-cmd\` (orchestrator-managed, HITL gate).

Every path you write is relative to the worktree root; never write through an absolute path into a
shared checkout outside it. If the plan contradicts what you find in the repository, stop and
report the gap rather than redesigning or improvising a different shape. Never weaken or disable a
test to make it pass — a red test is a finding to report, not a target to edit.

Implement the smallest viable change that satisfies the brief, matching the surrounding code's
existing style and conventions. Do not introduce a new dependency the plan did not call for. Run
the narrowest relevant test first, then the full project suite at most twice.

If you write a durable fact worth keeping for a future dispatch, save it to exactly ONE new,
uniquely-named file under \`.claude/agent-memory/coder/topics/\` — never to
\`.claude/agent-memory/coder/MEMORY.md\`, which is a curated index you must not touch.

Return all eight of:
- files_modified: path and one-line purpose for each file you changed.
- sub_steps: each plan sub-step, its status (done/left_out), and the reason for anything left out.
- key_decisions: anything not fully specified by the plan and how you resolved it.
- verification: the exact command you ran, its exit code, and the pass/fail result.
- drafted_commit: a Conventional Commits subject and body, for the orchestrator to use.
- cleanup: every temporary file or scratch script you created this task, and its disposition.
- plan_deviations: one entry per plan constraint you declined or altered — task, constraint,
  action taken, and why. Empty array when there are none; never a silent omission.
- pattern_classification: one entry per hunk in your diff, using the ADD/REMOVE/REPLACE/MODIFY
  vocabulary — pattern, path, and a one-line intent.

BRIEF:
$(cat "$BRIEF")
PROMPT_EOF

# --- Invocation. --model and --effort are both required (no default, no optional-array handling
# needed) and each -c pair is built as ONE array element carrying the whole token (bash 3.2:
# indexed arrays are fine, associative are not), never by string-splitting a variable — the same
# shape codex-tester.sh uses so the drift-guard needle matches intact. ----------------------------

CODEX_MODEL_ARG=("-c model=$SLUG")
CODEX_EFFORT_ARG=("-c model_reasoning_effort=$EFFORT")

CODEX_STDERR=$(mktemp)
codex exec -s workspace-write -C "$WORKTREE" \
  "${CODEX_MODEL_ARG[@]}" \
  "${CODEX_EFFORT_ARG[@]}" \
  --output-schema "$SCHEMA_FILE" -o "$RAW_OUT" \
  "$(cat "$PROMPT_FILE")" >/dev/null 2>"$CODEX_STDERR"
CODEX_RC=$?
CODEX_ERR_TEXT=$(cat "$CODEX_STDERR" 2>/dev/null)
rm -f "$CODEX_STDERR"

# --- Failure classification (VCS-064 fix, order load-bearing, CK10 pins it byte-for-byte against
# codex-reviewer.sh/codex-tester.sh): a non-empty $RAW_OUT means codex exec actually wrote a result
# and wins REGARDLESS of exit code — a real rate/quota rejection produces no output, so a valid
# file here outranks the rate-limit grep below. Only when $RAW_OUT is empty does the grep decide. -

if [ -s "$RAW_OUT" ]; then
  : # completed — fall through to the scope check and formatting below
elif printf '%s' "$CODEX_ERR_TEXT" | grep -Eqi 'usage limit|rate limit|quota exceeded|\b429\b'; then
  echo "codex-coder: DID-NOT-RUN: codex exec reported a rate/quota limit — $(printf '%s' "$CODEX_ERR_TEXT" | head -1)" >&2
  exit 3
else
  echo "codex-coder: DID-NOT-RUN: codex exec produced no output at $RAW_OUT (exit $CODEX_RC)" >&2
  exit 3
fi

# --- Scope check. Recompute the touched-path union, subtract the baseline, then evaluate the five
# classes (ADR-0196). Reuse codex-tester.sh's is_test_path() predicate verbatim — same question
# about a path, opposite conclusion (rule 6): there, a non-test path is the violation; here, a test
# path is. --------------------------------------------------------------------------------------

_snapshot_worktree_files | sort -u > "$AFTER_FILE"

comm -13 "$BASELINE_FILE" "$AFTER_FILE" > "$REMAINING_FILE"

AFTER_HEAD=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null)

TOUCHED_N=$(awk 'END{print NR}' "$REMAINING_FILE")
TOUCHED_CSV=$(paste -sd, "$REMAINING_FILE" 2>/dev/null)

is_test_path() {
  _p="$1"
  _base="${_p##*/}"
  case "$_base" in
    test_*|*_test.*|*.test.*|*.spec.*|*Tests.swift|*Test.java|conftest.py) return 0 ;;
  esac
  _oldifs="$IFS"
  IFS='/'
  set -- $_p
  IFS="$_oldifs"
  for _c in "$@"; do
    case "$_c" in
      tests|test|spec|__tests__|Tests) return 0 ;;
    esac
  done
  return 1
}

VIOLATION_MSGS=()

if grep -qFx '.claude/test-cmd' "$REMAINING_FILE" 2>/dev/null; then
  VIOLATION_MSGS+=("codex-coder: SCOPE-VIOLATION: TEST-CMD: .claude/test-cmd")
fi

TEST_FILE_LIST=""
while IFS= read -r _p; do
  [ -z "$_p" ] && continue
  if is_test_path "$_p"; then
    if [ -z "$TEST_FILE_LIST" ]; then
      TEST_FILE_LIST="$_p"
    else
      TEST_FILE_LIST="$TEST_FILE_LIST, $_p"
    fi
  fi
done < "$REMAINING_FILE"
if [ -n "$TEST_FILE_LIST" ]; then
  VIOLATION_MSGS+=("codex-coder: SCOPE-VIOLATION: TEST-FILE: $TEST_FILE_LIST")
fi

if grep -qFx '.claude/agent-memory/coder/MEMORY.md' "$REMAINING_FILE" 2>/dev/null; then
  VIOLATION_MSGS+=("codex-coder: SCOPE-VIOLATION: MEMORY-INDEX: .claude/agent-memory/coder/MEMORY.md")
fi

SHARD_COUNT=$(grep -cF '.claude/agent-memory/coder/topics/' "$REMAINING_FILE" 2>/dev/null)
case "$SHARD_COUNT" in ''|*[!0-9]*) SHARD_COUNT=0 ;; esac
if [ "$SHARD_COUNT" -gt 1 ]; then
  SHARD_CSV=$(grep -F '.claude/agent-memory/coder/topics/' "$REMAINING_FILE" 2>/dev/null | paste -sd, -)
  VIOLATION_MSGS+=("codex-coder: SCOPE-VIOLATION: MEMORY-SHARDS: $SHARD_CSV")
fi

if [ "$AFTER_HEAD" != "$BASELINE_HEAD" ]; then
  VIOLATION_MSGS+=("codex-coder: SCOPE-VIOLATION: NEW-COMMIT: $BASELINE_HEAD -> $AFTER_HEAD")
fi

# --- Format the schema JSON into coder.md's Output Format markdown at --out, unconditionally — a
# partial report is still useful even on a scope violation (ADR-0196). Same shape as
# codex-tester.sh's own formatter. ------------------------------------------------------------

RAW_OUT="$RAW_OUT" CC_MD_OUT="$OUT" python3 -c "
import json, os, sys

path = os.environ['RAW_OUT']
try:
    with open(path) as f:
        data = json.load(f)
except Exception as e:
    sys.stderr.write('codex-coder: DID-NOT-RUN: output at %s did not parse against the schema (%s)\n' % (path, e))
    sys.exit(3)

files_modified = data.get('files_modified', [])
sub_steps = data.get('sub_steps', [])
key_decisions = data.get('key_decisions', [])
verification = data.get('verification', {})
drafted_commit = data.get('drafted_commit', {})
cleanup = data.get('cleanup', [])
plan_deviations = data.get('plan_deviations', [])
pattern_classification = data.get('pattern_classification', [])

lines = ['## Coder Report', '']

lines.append('### Files modified')
if isinstance(files_modified, list) and files_modified and all(isinstance(f, dict) for f in files_modified):
    for f in files_modified:
        lines.append('- \`%s\` — %s' % (f.get('path', '?'), f.get('purpose', '')))
elif files_modified:
    lines.append('- %s' % files_modified)
else:
    lines.append('(none)')
lines.append('')

lines.append('### Sub-steps')
if isinstance(sub_steps, list) and sub_steps and all(isinstance(s, dict) for s in sub_steps):
    for s in sub_steps:
        lines.append('- %s: %s — %s' % (s.get('step', '?'), s.get('status', ''), s.get('reason', '')))
elif sub_steps:
    lines.append('- %s' % sub_steps)
else:
    lines.append('(none)')
lines.append('')

lines.append('### Key decisions')
if isinstance(key_decisions, list) and key_decisions:
    for d in key_decisions:
        lines.append('- %s' % d)
elif key_decisions:
    lines.append('- %s' % key_decisions)
else:
    lines.append('(none)')
lines.append('')

lines.append('### Verification')
if isinstance(verification, dict) and verification:
    lines.append('- command: \`%s\`' % verification.get('command', ''))
    lines.append('- exit_code: %s' % verification.get('exit_code', ''))
    lines.append('- result: %s' % verification.get('result', ''))
elif verification:
    lines.append('- %s' % verification)
else:
    lines.append('(no verification reported)')
lines.append('')

lines.append('### Drafted commit')
if isinstance(drafted_commit, dict) and drafted_commit:
    lines.append('- subject: %s' % drafted_commit.get('subject', ''))
    lines.append('- body: %s' % drafted_commit.get('body', ''))
elif drafted_commit:
    lines.append('- %s' % drafted_commit)
else:
    lines.append('(none)')
lines.append('')

lines.append('### Cleanup')
if isinstance(cleanup, list) and cleanup and all(isinstance(c, dict) for c in cleanup):
    for c in cleanup:
        lines.append('- %s — %s' % (c.get('item', '?'), c.get('disposition', '')))
elif cleanup:
    lines.append('- %s' % cleanup)
else:
    lines.append('(none)')
lines.append('')

lines.append('### Plan deviations')
if isinstance(plan_deviations, list) and plan_deviations and all(isinstance(p, dict) for p in plan_deviations):
    for p in plan_deviations:
        lines.append('- task %s: %s — %s (%s)' % (p.get('task', '?'), p.get('constraint', ''), p.get('action', ''), p.get('why', '')))
elif plan_deviations:
    lines.append('- %s' % plan_deviations)
else:
    lines.append('(none)')
lines.append('')

lines.append('### Pattern classification')
if isinstance(pattern_classification, list) and pattern_classification and all(isinstance(p, dict) for p in pattern_classification):
    for p in pattern_classification:
        lines.append('- %s | %s | %s' % (p.get('pattern', '?'), p.get('path', ''), p.get('intent', '')))
elif pattern_classification:
    lines.append('- %s' % pattern_classification)
else:
    lines.append('(none)')

with open(os.environ['CC_MD_OUT'], 'w') as out:
    out.write('\n'.join(lines) + '\n')
" 2>&1
FORMAT_RC=$?
if [ "$FORMAT_RC" -eq 3 ]; then
  exit 3
elif [ "$FORMAT_RC" -ne 0 ]; then
  echo "codex-coder: DID-NOT-RUN: formatting the coder output failed (exit $FORMAT_RC)" >&2
  exit 3
fi

# --- Verdict. Print the touched-path summary on stderr in EVERY case (CK17 reads it rather than
# re-deriving the set), then decide the exit code. -------------------------------------------------

echo "codex-coder: touched-paths=$TOUCHED_N: ${TOUCHED_CSV:-(none)}" >&2

if [ "$TOUCHED_N" -eq 0 ]; then
  echo "codex-coder: NOTE: no file changes detected in $WORKTREE" >&2
fi

for _msg in "${VIOLATION_MSGS[@]+"${VIOLATION_MSGS[@]}"}"; do
  echo "$_msg" >&2
done

if [ "${#VIOLATION_MSGS[@]}" -gt 0 ]; then
  exit 4
fi

exit 0
