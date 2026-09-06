#!/bin/bash
# codex-tester.sh v1.0 — Codex CLI substitute for the `tester` agent (Codex-vs-Claude tester
# backend choice, ADR-0194). Bash 3.2-clean. Run: bash codex-tester.sh --worktree <dir> --brief
# <file> --out <file> [--effort <value>]
#
# WHY THIS EXISTS. The chain's `tester` agent contract (never touch production code, write failing
# tests from the SPEC/plan brief, run the suite, report the six-field Output Format —
# `staging/plugin/agents/tester.md`) spends Claude Code tokens at both Step 5 dispatch sites (the
# Workflow `pipeline()` Stage 1 and the Agent-tool Tester batch dispatch template). This script
# lets those same sites dispatch to Codex CLI instead, gated behind `manifest.use_codex_tester` —
# a SUBSTITUTE, never a second opinion run alongside Claude's own tester.
#
# CONTRACT — a CHECKER, not a reporter (rule 5): the caller branches on the exit code, never on
# whether stdout is empty.
#   exit 0 — success. The markdown report is written to --out, in the SAME six-field shape
#            tester.md's own Output Format produces, so a caller can consume it identically either
#            way. Also covers the "Codex wrote nothing" edge case (empty touched-path set, a
#            distinct NOTE: line on stderr — a no-op run is not the same fact as a scope violation).
#   exit 2 — bad invocation (missing/unknown flag, missing required argument, unreadable --brief).
#            One line on stderr, "codex-tester: " prefixed.
#   exit 3 — DID-NOT-RUN (rule 4). One line on stderr, "codex-tester: DID-NOT-RUN: <reason>" — the
#            ONE signal callers gate the fallback-to-Claude AskUserQuestion on (Stefano's own
#            policy: never a silent fallback).
#   exit 4 — SCOPE-VIOLATION: Codex touched a path outside test scope (a production file). The
#            partial report is still written to --out (a partial report is more useful than none);
#            the caller asks the user to accept the write, fall back to Claude, or halt.
#
# PROMPT DUPLICATION, DECLARED (rule 6/12). TESTER_PROMPT below is hand-ported from
# `staging/plugin/agents/tester.md`'s Core Responsibilities / Quality Standards / Output Format /
# Edge Cases sections — a true single source is not mechanically possible here (one runtime is a
# Claude Code agent system prompt, the other a `codex exec` CLI prompt embedding its own brief).
# When tester.md's contract changes, re-check this file's TESTER_PROMPT for drift.
#
# CASCADE/REGEX DUPLICATION, DECLARED (rule 6/12; ADR-0194 §Refinements R7). The availability
# cascade (codex-on-PATH check, `codex doctor --json` auth probe) and the rate-limit vocabulary
# grep below are copied from `codex-reviewer.sh` byte-for-byte rather than shared through a
# helper — extraction to a shared `codex-common.sh` is a named follow-up, not done here (changing
# codex-reviewer.sh is out of this SPEC's scope, and a shared source that breaks disables both
# consumers at once). A harness assertion (CX15) pins the two copies' load-bearing needles
# identical so a future fix applied to one and not the other is caught.
#
# SANDBOX AS ENFORCEMENT (rule 16). `-s workspace-write -C "$WORKTREE"` on `codex exec` is what
# actually constrains Codex to write only inside the dispatch's own worktree — a runtime guarantee,
# not an instruction Codex is asked to obey. This script's own post-run scope check, below, is a
# SECOND, INDEPENDENT guard: the sandbox stops writes outside the worktree; the scope check catches
# a write that lands inside the worktree but on a production path, which workspace-write alone does
# not forbid.
#
# CODEX CLI SHAPE, VERIFIED LIVE (rule 13, 2026-09-06 — not assumed from --help alone; see
# ADR-0194): `codex exec --help` lists `-s/--sandbox <read-only|workspace-write|
# danger-full-access>`, `-C/--cd <DIR>`, `--output-schema <FILE>`, `-o/--output-last-message
# <FILE>`. `codex doctor --json` -> .checks["auth.credentials"].status == "ok" is the auth probe.
# No `-m/--model` override here (ADR-0194 §Refinements R2 — the interactive config's model tier
# governs, a disclosed cost-inheritance risk, not a pin). `--effort` is passed through as a single
# `-c model_reasoning_effort=<value>` token so the drift-guard needle (CX15/CX12) matches it intact
# — see the invocation below.
set -u

WORKTREE=""
BRIEF=""
OUT=""
EFFORT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --worktree) WORKTREE="${2:-}"; shift 2 ;;
    --brief) BRIEF="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --effort) EFFORT="${2:-}"; shift 2 ;;
    *) echo "codex-tester: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$WORKTREE" ]; then
  echo "codex-tester: --worktree is required" >&2
  exit 2
fi

if [ -z "$BRIEF" ]; then
  echo "codex-tester: --brief is required" >&2
  exit 2
fi

if [ ! -f "$BRIEF" ] || [ ! -r "$BRIEF" ]; then
  echo "codex-tester: --brief file not readable: $BRIEF" >&2
  exit 2
fi

if [ -z "$OUT" ]; then
  echo "codex-tester: --out is required" >&2
  exit 2
fi

# --- Availability cascade, never silent (rule 4) — byte-identical to codex-reviewer.sh's own
# (declared duplication above; CX15 pins the drift-sensitive substrings) --------------------------

if ! command -v codex >/dev/null 2>&1; then
  echo "codex-tester: DID-NOT-RUN: codex CLI not installed" >&2
  exit 3
fi

DOCTOR_JSON=$(codex doctor --json 2>/dev/null)
if [ -z "$DOCTOR_JSON" ] || ! command -v python3 >/dev/null 2>&1; then
  echo "codex-tester: DID-NOT-RUN: codex doctor produced no output, or python3 unavailable to parse it" >&2
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
  echo "codex-tester: DID-NOT-RUN: codex not authenticated (auth.credentials status: '${AUTH_STATUS:-unreadable}' — run 'codex doctor' for remediation)" >&2
  exit 3
fi

if ! git -C "$WORKTREE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "codex-tester: DID-NOT-RUN: worktree is not a git repository: $WORKTREE" >&2
  exit 3
fi

# --- Baseline capture, BEFORE any codex exec (ADR-0194 §Refinements R4). Pre-existing dirt in the
# worktree must never be attributed to Codex. Union of git diff, git diff --cached, and untracked
# files — git diff --name-only alone would miss a brand-new production file entirely. ------------

BASELINE_FILE=$(mktemp)
AFTER_FILE=$(mktemp)
REMAINING_FILE=$(mktemp)
SCHEMA_FILE=$(mktemp)
PROMPT_FILE=$(mktemp)
RAW_OUT=$(mktemp)
trap 'rm -f "$BASELINE_FILE" "$AFTER_FILE" "$REMAINING_FILE" "$SCHEMA_FILE" "$PROMPT_FILE" "$RAW_OUT"' EXIT

{
  git -C "$WORKTREE" diff --name-only 2>/dev/null
  git -C "$WORKTREE" diff --name-only --cached 2>/dev/null
  git -C "$WORKTREE" ls-files --others --exclude-standard 2>/dev/null
} | sort -u > "$BASELINE_FILE"

# --- Schema (--output-schema): six properties matching tester.md's Output Format. Every object,
# including nested ones and array items whose type is object, carries "additionalProperties":
# false — without it codex exec fails invalid_json_schema before the model ever runs (S3 pins
# this, the same defect ADR-0187 found live for codex-reviewer.sh). --------------------------------

cat > "$SCHEMA_FILE" <<'SCHEMA_EOF'
{
  "type": "object",
  "properties": {
    "tests_added": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "path": {"type": "string"},
          "covers": {"type": "string"}
        },
        "required": ["path", "covers"],
        "additionalProperties": false
      }
    },
    "run_result": {
      "type": "object",
      "properties": {
        "command": {"type": "string"},
        "passed": {"type": "integer"},
        "failed": {"type": "integer"}
      },
      "required": ["command", "passed", "failed"],
      "additionalProperties": false
    },
    "coverage": {"type": "string"},
    "bugs_found": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "description": {"type": "string"},
          "reproduction": {"type": "string"}
        },
        "required": ["description", "reproduction"],
        "additionalProperties": false
      }
    },
    "requirement_ids_covered": {
      "type": "array",
      "items": {"type": "string"}
    },
    "sub_steps": {
      "type": "object",
      "properties": {
        "executed": {
          "type": "array",
          "items": {"type": "string"}
        },
        "left_to_coder": {
          "type": "array",
          "items": {"type": "string"}
        }
      },
      "required": ["executed", "left_to_coder"],
      "additionalProperties": false
    }
  },
  "required": ["tests_added", "run_result", "coverage", "bugs_found", "requirement_ids_covered", "sub_steps"],
  "additionalProperties": false
}
SCHEMA_EOF

# --- Prompt, hand-ported from tester.md (see header comment) — rule 6/12 cross-reference. --------

cat > "$PROMPT_FILE" <<PROMPT_EOF
You are a pragmatic test engineer working against a single isolated worktree. You write and run
tests for business-critical logic. You NEVER modify production code — only test files. If a test
reveals a bug, you report it; you do not fix it yourself.

Write failing tests for the requirement IDs, Success Criteria, or plan task text given in the brief
below — never from implementation files; the brief is your only source of what to test. Detect
this project's test framework (by stack: Python -> pytest, TypeScript -> Vitest, Swift -> Swift
Testing) and run its suite. Report the exact command you ran and the pass/fail counts.

Cover happy path, edge cases, error paths, and boundary values on business-critical logic
(calculations, parsing, endpoints, security-sensitive code). Skip pure UI presentation, trivial
getters/setters, glue, and configuration. Tests must be deterministic and independent.

Return all six of:
- tests_added: the file paths you wrote, and what each one covers.
- run_result: the exact command you ran, and the pass/failed counts.
- coverage: on the modules you touched.
- bugs_found: a precise description and reproduction for any production bug a test revealed — you
  do not fix it.
- requirement_ids_covered: the R-NN identifiers each test addresses, or state the SPEC declared
  none for this task.
- sub_steps: which of the brief's sub-steps you executed, and which you leave to the coder.

BRIEF:
$(cat "$BRIEF")
PROMPT_EOF

# --- Invocation. The optional --effort passthrough is built as a single array element carrying
# the whole "-c model_reasoning_effort=<value>" token (bash 3.2: indexed arrays are fine,
# associative are not) — never string-split from a variable — so it stays intact end to end and is
# omitted entirely (never an empty value) when --effort is not given. No -m — ADR-0194 §R2. -------

CODEX_EFFORT_ARGS=()
if [ -n "$EFFORT" ]; then
  CODEX_EFFORT_ARGS=("-c model_reasoning_effort=$EFFORT")
fi

CODEX_STDERR=$(mktemp)
codex exec -s workspace-write -C "$WORKTREE" \
  "${CODEX_EFFORT_ARGS[@]+"${CODEX_EFFORT_ARGS[@]}"}" \
  --output-schema "$SCHEMA_FILE" -o "$RAW_OUT" \
  "$(cat "$PROMPT_FILE")" >/dev/null 2>"$CODEX_STDERR"
CODEX_RC=$?
CODEX_ERR_TEXT=$(cat "$CODEX_STDERR" 2>/dev/null)
rm -f "$CODEX_STDERR"

# --- Failure classification (VCS-064 fix, order load-bearing, CX15 pins it byte-for-byte against
# codex-reviewer.sh): a non-empty $RAW_OUT means codex exec actually wrote a result and wins
# REGARDLESS of exit code — a real rate/quota rejection produces no output, so a valid file here
# outranks the rate-limit grep below. Only when $RAW_OUT is empty does the grep decide. -----------

if [ -s "$RAW_OUT" ]; then
  : # completed — fall through to the scope check and formatting below
elif printf '%s' "$CODEX_ERR_TEXT" | grep -Eqi 'usage limit|rate limit|quota exceeded|\b429\b'; then
  echo "codex-tester: DID-NOT-RUN: codex exec reported a rate/quota limit — $(printf '%s' "$CODEX_ERR_TEXT" | head -1)" >&2
  exit 3
else
  echo "codex-tester: DID-NOT-RUN: codex exec produced no output at $RAW_OUT (exit $CODEX_RC)" >&2
  exit 3
fi

# --- Scope check (ADR-0194 §Refinements R4). Recompute the touched-path union, subtract the
# baseline, classify what remains. ------------------------------------------------------------

{
  git -C "$WORKTREE" diff --name-only 2>/dev/null
  git -C "$WORKTREE" diff --name-only --cached 2>/dev/null
  git -C "$WORKTREE" ls-files --others --exclude-standard 2>/dev/null
} | sort -u > "$AFTER_FILE"

comm -13 "$BASELINE_FILE" "$AFTER_FILE" > "$REMAINING_FILE"

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

PROD_LIST=""
while IFS= read -r _p; do
  [ -z "$_p" ] && continue
  if ! is_test_path "$_p"; then
    if [ -z "$PROD_LIST" ]; then
      PROD_LIST="$_p"
    else
      PROD_LIST="$PROD_LIST, $_p"
    fi
  fi
done < "$REMAINING_FILE"

# --- Format the schema JSON into tester.md's six-field markdown at --out, same shape as
# codex-reviewer.sh's own formatter — written unconditionally, even on a scope violation, because a
# partial report is more useful than none. -------------------------------------------------------

RAW_OUT="$RAW_OUT" CT_MD_OUT="$OUT" python3 -c "
import json, os, sys

path = os.environ['RAW_OUT']
try:
    with open(path) as f:
        data = json.load(f)
except Exception as e:
    sys.stderr.write('codex-tester: DID-NOT-RUN: output at %s did not parse against the schema (%s)\n' % (path, e))
    sys.exit(3)

tests_added = data.get('tests_added', [])
run_result = data.get('run_result', {})
coverage = data.get('coverage', '')
bugs_found = data.get('bugs_found', [])
req_ids = data.get('requirement_ids_covered', [])
sub_steps = data.get('sub_steps', {})

lines = ['## Tester Report', '']

lines.append('### Tests added')
if isinstance(tests_added, list) and tests_added and all(isinstance(t, dict) for t in tests_added):
    for t in tests_added:
        lines.append('- \`%s\` — %s' % (t.get('path', '?'), t.get('covers', '')))
elif tests_added:
    lines.append('- %s' % tests_added)
else:
    lines.append('(none)')
lines.append('')

lines.append('### Run result')
if isinstance(run_result, dict) and run_result:
    lines.append('- command: \`%s\`' % run_result.get('command', ''))
    lines.append('- passed: %s' % run_result.get('passed', ''))
    lines.append('- failed: %s' % run_result.get('failed', ''))
elif run_result:
    lines.append('- %s' % run_result)
else:
    lines.append('(no run result)')
lines.append('')

lines.append('### Coverage')
lines.append(coverage if coverage else '(not reported)')
lines.append('')

lines.append('### Bugs found')
if isinstance(bugs_found, list) and bugs_found and all(isinstance(b, dict) for b in bugs_found):
    for b in bugs_found:
        lines.append('- %s — repro: %s' % (b.get('description', ''), b.get('reproduction', '')))
elif bugs_found:
    lines.append('- %s' % bugs_found)
else:
    lines.append('(none)')
lines.append('')

lines.append('### Requirement IDs covered')
if isinstance(req_ids, list) and req_ids:
    lines.append(', '.join(str(r) for r in req_ids))
elif req_ids:
    lines.append(str(req_ids))
else:
    lines.append('(none declared)')
lines.append('')

lines.append('### Sub-steps')
if isinstance(sub_steps, dict) and sub_steps:
    lines.append('- executed: %s' % ', '.join(sub_steps.get('executed', []) or []))
    lines.append('- left to coder: %s' % ', '.join(sub_steps.get('left_to_coder', []) or []))
elif sub_steps:
    lines.append('- %s' % sub_steps)
else:
    lines.append('(none)')

with open(os.environ['CT_MD_OUT'], 'w') as out:
    out.write('\n'.join(lines) + '\n')
" 2>&1
FORMAT_RC=$?
if [ "$FORMAT_RC" -eq 3 ]; then
  exit 3
elif [ "$FORMAT_RC" -ne 0 ]; then
  echo "codex-tester: DID-NOT-RUN: formatting the tester output failed (exit $FORMAT_RC)" >&2
  exit 3
fi

# --- Verdict. Print the touched-path summary on stderr in EVERY case (CX09/CX11 read it rather
# than re-deriving the set), then decide the exit code. --------------------------------------------

echo "codex-tester: touched-paths=$TOUCHED_N: ${TOUCHED_CSV:-(none)}" >&2

if [ "$TOUCHED_N" -eq 0 ]; then
  echo "codex-tester: NOTE: no file changes detected in $WORKTREE" >&2
fi

if [ -n "$PROD_LIST" ]; then
  echo "codex-tester: SCOPE-VIOLATION: $PROD_LIST" >&2
  exit 4
fi

exit 0
