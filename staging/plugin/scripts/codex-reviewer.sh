#!/bin/bash
# codex-reviewer.sh v1.0 — Codex CLI substitute for the `reviewer` agent (Codex-vs-Claude review
# gate, ADR pending). Bash 3.2-clean. Run: bash codex-reviewer.sh --mode ... --out <file>
#
# WHY THIS EXISTS. The chain's `reviewer` agent contract (taxonomy, confidence filter, output
# format — `staging/plugin/agents/reviewer.md`) spends Claude Code tokens at five dispatch sites
# (RTF Step 1, RTF advisor, RTF Step 4 re-review, Step 5 checkpoint x2). This script lets those
# same sites dispatch to Codex CLI instead, gated behind `manifest.use_codex_review` — a
# SUBSTITUTE, never a second opinion run alongside Claude's own reviewer.
#
# CONTRACT — a CHECKER, not a reporter (rule 5): the caller branches on the exit code, never on
# whether stdout is empty.
#   exit 0 — success. The markdown report is written to --out, in the SAME shape reviewer.md's own
#            Output Format produces, so a caller can consume it identically either way.
#   exit 2 — bad invocation (missing/unknown flag, missing required argument, unreadable
#            --carry-forward file). One line on stderr.
#   exit 3 — DID-NOT-RUN (rule 4). One line on stderr, "codex-reviewer: DID-NOT-RUN: <reason>" —
#            this is the ONE signal callers gate the fallback-to-Claude AskUserQuestion on
#            (Stefano's own policy: never a silent fallback). An empty diff is NOT exit 3 — it
#            mirrors reviewer.md's own "no detectable changes" edge case (exit 0, report says so).
#
# TWO MODES, matching the two shapes the Claude `reviewer` agent is used in today:
#   --mode review   --diff-scope uncommitted|base:<ref>|commit:<sha> [--carry-forward <file>] --out <file>
#   --mode diagnose --finding "<text>" --out <file>
#
# PROMPT DUPLICATION, DECLARED (rule 6/12). The review-mode prompt below is hand-ported from
# `staging/plugin/agents/reviewer.md`'s Quality Standards / Confidence Filter / Output Format /
# Edge Cases sections — a true single source is not mechanically possible here (one runtime is a
# Claude Code agent system prompt, the other a `codex exec` CLI prompt embedding its own diff).
# When reviewer.md's contract changes, re-check this file's REVIEW_PROMPT for drift.
#
# SANDBOX AS ENFORCEMENT (rule 16). `reviewer-write-scope.sh` is a Claude PreToolUse hook and
# cannot see this external process at all. `-s read-only` on `codex exec` is the real substitute:
# a runtime guarantee that Codex cannot write anywhere, not an instruction Codex is asked to obey.
#
# CODEX CLI SHAPE, VERIFIED LIVE (rule 13 — not assumed from --help alone):
#   `codex doctor --json` -> .checks["auth.credentials"].status == "ok" is the auth probe.
#   `codex exec --output-schema <file> -o <out-file> <prompt>` constrains and captures the final
#   message as JSON matching the schema; `--json` is a separate, unrelated JSONL event stream.
#   Exit-code semantics on a Codex-side failure (rate limit, quota) are UNDOCUMENTED — this script
#   treats any non-zero `codex exec` exit, or stderr matching rate-limit vocabulary, as exit 3.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

MODE=""
DIFF_SCOPE=""
CARRY_FORWARD=""
FINDING=""
OUT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --diff-scope) DIFF_SCOPE="${2:-}"; shift 2 ;;
    --carry-forward) CARRY_FORWARD="${2:-}"; shift 2 ;;
    --finding) FINDING="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    *) echo "codex-reviewer: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  review|diagnose) ;;
  *) echo "codex-reviewer: --mode must be 'review' or 'diagnose' (got '$MODE')" >&2; exit 2 ;;
esac

if [ -z "$OUT" ]; then
  echo "codex-reviewer: --out is required" >&2
  exit 2
fi

if [ "$MODE" = "review" ]; then
  case "$DIFF_SCOPE" in
    uncommitted|base:*|commit:*) ;;
    *) echo "codex-reviewer: --diff-scope must be 'uncommitted', 'base:<ref>', or 'commit:<sha>' (got '$DIFF_SCOPE')" >&2; exit 2 ;;
  esac
  if [ -n "$CARRY_FORWARD" ] && [ ! -r "$CARRY_FORWARD" ]; then
    echo "codex-reviewer: --carry-forward file not readable: $CARRY_FORWARD" >&2
    exit 2
  fi
fi

if [ "$MODE" = "diagnose" ] && [ -z "$FINDING" ]; then
  echo "codex-reviewer: --finding is required in diagnose mode" >&2
  exit 2
fi

# --- Availability cascade (steps 1-3), never silent (rule 4) ------------------------------------

if ! command -v codex >/dev/null 2>&1; then
  echo "codex-reviewer: DID-NOT-RUN: codex CLI not installed" >&2
  exit 3
fi

DOCTOR_JSON=$(codex doctor --json 2>/dev/null)
if [ -z "$DOCTOR_JSON" ] || ! command -v python3 >/dev/null 2>&1; then
  echo "codex-reviewer: DID-NOT-RUN: codex doctor produced no output, or python3 unavailable to parse it" >&2
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
  echo "codex-reviewer: DID-NOT-RUN: codex not authenticated (auth.credentials status: '${AUTH_STATUS:-unreadable}' — run 'codex doctor' for remediation)" >&2
  exit 3
fi

if [ "$MODE" = "review" ] && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "codex-reviewer: DID-NOT-RUN: not a git repository" >&2
  exit 3
fi

# --- Compute the diff (review mode) or use the finding text (diagnose mode) ---------------------

DIFF_CONTENT=""
if [ "$MODE" = "review" ]; then
  case "$DIFF_SCOPE" in
    uncommitted)
      DIFF_CONTENT=$(git diff HEAD 2>/dev/null)
      ;;
    base:*)
      _ref="${DIFF_SCOPE#base:}"
      DIFF_CONTENT=$(git diff "$_ref"...HEAD 2>/dev/null)
      ;;
    commit:*)
      _sha="${DIFF_SCOPE#commit:}"
      DIFF_CONTENT=$(git show "$_sha" 2>/dev/null)
      ;;
  esac

  # Step 4: empty diff is NOT a failure (mirrors reviewer.md's own "no detectable changes" edge
  # case) — exit 0, report says so, in the same markdown shape as every other outcome.
  if [ -z "$DIFF_CONTENT" ]; then
    {
      echo "## Review"
      echo ""
      echo "No detectable changes for scope '$DIFF_SCOPE'."
      echo ""
      echo "**Verdict:** safe to merge (nothing to review)."
    } > "$OUT"
    exit 0
  fi
fi

# --- Build the prompt and schema -----------------------------------------------------------------

SCHEMA_FILE=$(mktemp)
PROMPT_FILE=$(mktemp)
RAW_OUT=$(mktemp)
trap 'rm -f "$SCHEMA_FILE" "$PROMPT_FILE" "$RAW_OUT"' EXIT

if [ "$MODE" = "review" ]; then
  cat > "$SCHEMA_FILE" <<'SCHEMA_EOF'
{
  "type": "object",
  "properties": {
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "severity": {"type": "string", "enum": ["BLOCKER", "MAJOR", "MINOR", "NIT"]},
          "location": {"type": "string"},
          "problem": {"type": "string"},
          "fix": {"type": "string"},
          "confidence": {"type": "integer"}
        },
        "required": ["severity", "location", "problem", "fix", "confidence"]
      }
    },
    "sampled": {"type": "boolean"},
    "verdict": {"type": "string"}
  },
  "required": ["findings", "sampled", "verdict"]
}
SCHEMA_EOF

  CARRY_BLOCK=""
  if [ -n "$CARRY_FORWARD" ]; then
    CARRY_BLOCK="

PREVIOUS CYCLE'S FINDINGS (severity<TAB>location<TAB>problem), for wording stability. For any
finding here that is still present and unresolved, reuse its 'problem' text VERBATIM in your
output — even a single-word rewording changes the hash a downstream tool uses to track whether
this finding is the same one across review cycles, and a changed hash reads as a resolved finding
plus a brand-new one that happens to look identical. Only change the wording if the finding
itself has genuinely changed.
$(cat "$CARRY_FORWARD")"
  fi

  # Hand-ported from reviewer.md (see header comment) — rule 6/12 cross-reference.
  cat > "$PROMPT_FILE" <<PROMPT_EOF
You are a senior code reviewer. Review the diff below for security, correctness, performance, and
consistency. You are reporting only — you make no changes.

Checklist:
- Security: input validation, injection, hardcoded secrets, auth/authz flow.
- Correctness: logic bugs, edge cases, error handling, race conditions.
- Performance: N+1 queries, needless loops, blocking calls on async paths.
- Consistency: matches existing patterns in this repository; no unjustified deviation from its
  own documented conventions or ADRs.
- Tests: coverage of the changed behavior; missing edge-case tests.

Confidence filter: rate every candidate finding 0-100 before including it.
- 0-25: likely false positive or pre-existing issue unrelated to this diff — DO NOT report.
- 26-50: nitpick not backed by a project rule — DO NOT report.
- 51-74: plausible but low-impact or unverified — DO NOT report, UNLESS severity is BLOCKER.
- 75-100: verified, or a definite bug / explicit rule violation — report.
Only include findings with confidence >= 75, except a BLOCKER-severity finding at 51-74 may be
included. Quality over quantity — do not invent issues to fill out the report.

Output: for each finding, give severity (BLOCKER/MAJOR/MINOR/NIT), a location (path:line if
determinable from the diff, else a short description), a one-line problem statement, a suggested
fix, and your confidence (0-100). Set "sampled" true only if the diff was too large to review in
full and you prioritized BLOCKER/MAJOR. End with a one-line overall verdict (safe to merge / not,
and why) in the "verdict" field. If there is nothing worth reporting, return an empty findings
array and a verdict saying so — never invent an issue to have something to report.
$CARRY_BLOCK

DIFF TO REVIEW:
$DIFF_CONTENT
PROMPT_EOF

else
  cat > "$SCHEMA_FILE" <<'SCHEMA_EOF'
{
  "type": "object",
  "properties": {
    "diagnosis": {"type": "string"}
  },
  "required": ["diagnosis"]
}
SCHEMA_EOF

  cat > "$PROMPT_FILE" <<PROMPT_EOF
You are advising on a single code-review finding that a human or another reviewer has flagged.
Give a diagnosis in under 150 words: is this finding real, what is the actual risk or impact, and
what is the smallest fix. Be direct — no filler, no restating the finding back verbatim.

FINDING:
$FINDING
PROMPT_EOF
fi

# --- Execute --------------------------------------------------------------------------------------

CODEX_STDERR=$(mktemp)
codex exec --sandbox read-only --output-schema "$SCHEMA_FILE" -o "$RAW_OUT" \
  "$(cat "$PROMPT_FILE")" >/dev/null 2>"$CODEX_STDERR"
CODEX_RC=$?
CODEX_ERR_TEXT=$(cat "$CODEX_STDERR" 2>/dev/null)
rm -f "$CODEX_STDERR"

if [ "$CODEX_RC" -ne 0 ]; then
  echo "codex-reviewer: DID-NOT-RUN: codex exec exited $CODEX_RC — $(printf '%s' "$CODEX_ERR_TEXT" | head -1)" >&2
  exit 3
fi

if printf '%s' "$CODEX_ERR_TEXT" | grep -Eqi 'usage limit|rate limit|quota exceeded|\b429\b'; then
  echo "codex-reviewer: DID-NOT-RUN: codex exec reported a rate/quota limit — $(printf '%s' "$CODEX_ERR_TEXT" | head -1)" >&2
  exit 3
fi

if [ ! -s "$RAW_OUT" ]; then
  echo "codex-reviewer: DID-NOT-RUN: codex exec produced no output at $RAW_OUT" >&2
  exit 3
fi

# --- Format the schema JSON into reviewer.md's exact markdown shape ------------------------------

if [ "$MODE" = "review" ]; then
  RAW_OUT="$RAW_OUT" CR_OUT="$OUT" python3 -c "
import json, os, sys

path = os.environ['RAW_OUT']
try:
    with open(path) as f:
        data = json.load(f)
except Exception as e:
    sys.stderr.write('codex-reviewer: DID-NOT-RUN: output at %s did not parse against the schema (%s)\n' % (path, e))
    sys.exit(3)

findings = data.get('findings', [])
sampled = bool(data.get('sampled', False))
verdict = data.get('verdict', '(no verdict given)')

order = ['BLOCKER', 'MAJOR', 'MINOR', 'NIT']
by_sev = dict((s, []) for s in order)
for f in findings:
    sev = f.get('severity', 'NIT')
    conf = f.get('confidence', 0)
    if conf < 51:
        continue
    if conf < 75 and sev != 'BLOCKER':
        continue
    label = ' **[LOW CONFIDENCE]**' if conf < 75 else ''
    by_sev.setdefault(sev, []).append((f, label))

lines = ['## Review', '']
any_findings = False
for sev in order:
    items = by_sev.get(sev, [])
    if not items:
        continue
    any_findings = True
    lines.append('**%s**' % sev)
    for f, label in items:
        loc = f.get('location', '(location unknown)')
        problem = f.get('problem', '')
        fix = f.get('fix', '')
        lines.append('- \`%s\`%s — %s. Fix: %s' % (loc, label, problem, fix))
    lines.append('')

if not any_findings:
    lines.append('No findings at or above the confidence threshold.')
    lines.append('')

if sampled:
    lines.append('_Diff was large — lower-severity review was sampled, not exhaustive._')
    lines.append('')

lines.append('**Verdict:** %s' % verdict)

with open(os.environ['CR_OUT'], 'w') as out:
    out.write('\n'.join(lines) + '\n')
" 2>&1
  FORMAT_RC=$?
  if [ "$FORMAT_RC" -eq 3 ]; then
    exit 3
  elif [ "$FORMAT_RC" -ne 0 ]; then
    echo "codex-reviewer: DID-NOT-RUN: formatting the review output failed (exit $FORMAT_RC)" >&2
    exit 3
  fi
else
  RAW_OUT="$RAW_OUT" CR_OUT="$OUT" python3 -c "
import json, os, sys

path = os.environ['RAW_OUT']
try:
    with open(path) as f:
        data = json.load(f)
except Exception as e:
    sys.stderr.write('codex-reviewer: DID-NOT-RUN: output at %s did not parse against the schema (%s)\n' % (path, e))
    sys.exit(3)

diagnosis = data.get('diagnosis', '').strip()
with open(os.environ['CR_OUT'], 'w') as out:
    out.write(diagnosis + '\n')
" 2>&1
  FORMAT_RC=$?
  if [ "$FORMAT_RC" -ne 0 ]; then
    exit 3
  fi
fi

exit 0
