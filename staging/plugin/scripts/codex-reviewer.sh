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
# THREE MODES, matching the two shapes the Claude `reviewer` agent is used in today, plus the
# `deep-refactor` audit mode added by ADR-0193:
#   --mode review   --diff-scope uncommitted|base:<ref>|commit:<sha> [--carry-forward <file>] --out <file>
#   --mode diagnose --finding "<text>" --out <file>
#   --mode audit    --dimension dead-code|perf|structure|security
#                   [--diff-scope uncommitted|base:<ref>|commit:<sha>] --out <file>
#
# The exit contract above (0/2/3) is unchanged across all three modes. Audit-mode output at --out
# is FINDINGS_SCHEMA-shaped JSON — a JSON array of findings (ADR-0193 §D4) — never the markdown
# review and diagnose modes produce.
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
DIMENSION=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --diff-scope) DIFF_SCOPE="${2:-}"; shift 2 ;;
    --carry-forward) CARRY_FORWARD="${2:-}"; shift 2 ;;
    --finding) FINDING="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --dimension) DIMENSION="${2:-}"; shift 2 ;;
    *) echo "codex-reviewer: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  review|diagnose|audit) ;;
  *) echo "codex-reviewer: --mode must be 'review', 'diagnose', or 'audit' (got '$MODE')" >&2; exit 2 ;;
esac

if [ -z "$OUT" ]; then
  echo "codex-reviewer: --out is required" >&2
  exit 2
fi

# Shared by review mode (mandatory) and audit mode (optional) — rule 6: both call sites answer
# the SAME question, so they call the same validator rather than each carrying its own copy.
validate_diff_scope() {
  case "$1" in
    uncommitted|base:*|commit:*) ;;
    *) echo "codex-reviewer: --diff-scope must be 'uncommitted', 'base:<ref>', or 'commit:<sha>' (got '$1')" >&2; exit 2 ;;
  esac
}

if [ "$MODE" = "review" ]; then
  validate_diff_scope "$DIFF_SCOPE"
  if [ -n "$CARRY_FORWARD" ] && [ ! -r "$CARRY_FORWARD" ]; then
    echo "codex-reviewer: --carry-forward file not readable: $CARRY_FORWARD" >&2
    exit 2
  fi
fi

if [ "$MODE" = "diagnose" ] && [ -z "$FINDING" ]; then
  echo "codex-reviewer: --finding is required in diagnose mode" >&2
  exit 2
fi

if [ "$MODE" = "audit" ]; then
  case "$DIMENSION" in
    dead-code|perf|structure|security) ;;
    *) echo "codex-reviewer: --dimension must be 'dead-code', 'perf', 'structure', or 'security' (got '$DIMENSION')" >&2; exit 2 ;;
  esac
  # --diff-scope is OPTIONAL in audit mode (ADR-0193 §D2): empty means whole-tree, deep-refactor's
  # own documented scope. When given, it is validated by the same validator review mode uses.
  if [ -n "$DIFF_SCOPE" ]; then
    validate_diff_scope "$DIFF_SCOPE"
  fi
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

# Audit mode only (ADR-0193 §D3): the file list is derived from deep-refactor's own helper, never
# re-listed here (rule 6 — one question, one answer). Missing/unreadable is exit 3 DID-NOT-RUN,
# never a silent fall-back onto a duplicated exclusion list. The two existing modes gain no new
# failure path.
if [ "$MODE" = "audit" ]; then
  ENUM="$SCRIPT_DIR/../skills/deep-refactor/scripts/enumerate-sources.sh"
  if [ ! -r "$ENUM" ] || [ ! -x "$ENUM" ]; then
    echo "codex-reviewer: DID-NOT-RUN: enumerate-sources.sh not found or not executable at $ENUM" >&2
    exit 3
  fi
fi

if { [ "$MODE" = "review" ] || [ "$MODE" = "audit" ]; } && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "codex-reviewer: DID-NOT-RUN: not a git repository" >&2
  exit 3
fi

# --- Compute the diff (review mode), the finding text (diagnose mode), or the audit file list ---

DIFF_CONTENT=""
FILE_LIST=""
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
elif [ "$MODE" = "audit" ]; then
  # Whole-tree by default (ADR-0193 §D2/§D3) — the file list is DERIVED, never re-listed: the same
  # question ("which files are this project's source") answered once, by enumerate-sources.sh.
  ALL_FILES=$("$ENUM" "$(git rev-parse --show-toplevel)")
  _enum_rc=$?
  # A non-zero helper exit is DID-NOT-RUN (rule 4), never an empty list: without this the derived
  # population collapses to zero and the run reports an empty findings array with exit 0 — a
  # broken derivation and a clean audit are indistinguishable from outside (rule 7).
  if [ "$_enum_rc" -ne 0 ]; then
    echo "codex-reviewer: DID-NOT-RUN: enumerate-sources.sh failed (exit $_enum_rc)" >&2
    exit 3
  fi

  if [ -n "$DIFF_SCOPE" ]; then
    CHANGED_FILES=""
    case "$DIFF_SCOPE" in
      uncommitted)
        CHANGED_FILES=$(git diff HEAD --name-only 2>/dev/null)
        ;;
      base:*)
        # An unresolvable ref is DID-NOT-RUN (rule 4): stderr is discarded, so a silent empty
        # CHANGED_FILES would intersect to nothing and report a clean audit of a scope that was
        # never evaluated. `uncommitted` above is left unguarded — `git diff HEAD` is not expected
        # to fail once the is-inside-work-tree check has passed.
        _ref="${DIFF_SCOPE#base:}"
        CHANGED_FILES=$(git diff "$_ref"...HEAD --name-only 2>/dev/null)
        _git_rc=$?
        if [ "$_git_rc" -ne 0 ]; then
          echo "codex-reviewer: DID-NOT-RUN: could not resolve diff-scope '$DIFF_SCOPE' (git exit $_git_rc)" >&2
          exit 3
        fi
        ;;
      commit:*)
        _sha="${DIFF_SCOPE#commit:}"
        CHANGED_FILES=$(git show --name-only --pretty=format: "$_sha" 2>/dev/null)
        _git_rc=$?
        if [ "$_git_rc" -ne 0 ]; then
          echo "codex-reviewer: DID-NOT-RUN: could not resolve diff-scope '$DIFF_SCOPE' (git exit $_git_rc)" >&2
          exit 3
        fi
        ;;
    esac
    ALL_FILES_FILE=$(mktemp)
    CHANGED_FILES_FILE=$(mktemp)
    printf '%s\n' "$ALL_FILES" > "$ALL_FILES_FILE"
    printf '%s\n' "$CHANGED_FILES" > "$CHANGED_FILES_FILE"
    FILE_LIST=$(grep -Fxf "$CHANGED_FILES_FILE" "$ALL_FILES_FILE" 2>/dev/null)
    rm -f "$ALL_FILES_FILE" "$CHANGED_FILES_FILE"
  else
    FILE_LIST="$ALL_FILES"
  fi

  # An empty result is exit 0 with an empty findings array written to --out, mirroring review
  # mode's own empty-diff precedent immediately above — never exit 3 (ADR-0193 §D3).
  if [ -z "$FILE_LIST" ]; then
    printf '[]\n' > "$OUT"
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
        "required": ["severity", "location", "problem", "fix", "confidence"],
        "additionalProperties": false
      }
    },
    "sampled": {"type": "boolean"},
    "verdict": {"type": "string"}
  },
  "required": ["findings", "sampled", "verdict"],
  "additionalProperties": false
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

elif [ "$MODE" = "diagnose" ]; then
  cat > "$SCHEMA_FILE" <<'SCHEMA_EOF'
{
  "type": "object",
  "properties": {
    "diagnosis": {"type": "string"}
  },
  "required": ["diagnosis"],
  "additionalProperties": false
}
SCHEMA_EOF

  cat > "$PROMPT_FILE" <<PROMPT_EOF
You are advising on a single code-review finding that a human or another reviewer has flagged.
Give a diagnosis in under 150 words: is this finding real, what is the actual risk or impact, and
what is the smallest fix. Be direct — no filler, no restating the finding back verbatim.

FINDING:
$FINDING
PROMPT_EOF

else
  # MODE = audit. FINDINGS_SCHEMA-shaped JSON (ADR-0193 §D4) — nine fields, additionalProperties
  # false on root AND item, every property also in required (OpenAI structured-output has no
  # optional properties; nullability on "line" is how "may be absent" is expressed).
  #
  # NOTE for the next mode added after this one: codex-reviewer-schema.test.sh reads every
  # SCHEMA_EOF block in this file and pins the block count against the mode count (ADR-0193 §D7).
  # Adding a fourth mode means bumping that count deliberately, not by accident.
  cat > "$SCHEMA_FILE" <<'SCHEMA_EOF'
{
  "type": "object",
  "properties": {
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": {"type": "string"},
          "dimension": {"type": "string", "enum": ["dead-code", "perf", "structure", "security"]},
          "severity": {"type": "string", "enum": ["P1", "P2", "P3"]},
          "risk_level": {"type": "string", "enum": ["low", "high"]},
          "file": {"type": "string"},
          "line": {"type": ["integer", "null"]},
          "description": {"type": "string"},
          "fix_type": {"type": "string", "enum": ["coder", "refactorer", "debugger", "report-only"]},
          "suggested_fix": {"type": "string"}
        },
        "required": ["id", "dimension", "severity", "risk_level", "file", "line", "description", "fix_type", "suggested_fix"],
        "additionalProperties": false
      }
    }
  },
  "required": ["findings"],
  "additionalProperties": false
}
SCHEMA_EOF

  DIM_SCOPE=""
  case "$DIMENSION" in
    dead-code) DIM_SCOPE="Unused functions, imports, variables, unreachable branches, dead #if blocks" ;;
    perf) DIM_SCOPE="Unnecessary allocations, redundant recomputations, inefficient collection patterns, force-casts, sync I/O on main thread" ;;
    structure) DIM_SCOPE="Oversized files (>400 lines), oversized functions (>60 lines), tangled dependencies, duplicated logic blocks" ;;
    security) DIM_SCOPE="Hardcoded secrets/tokens, unsafe API usage, missing input validation, unguarded URL construction" ;;
  esac

  # The two mandatory guards (SKILL.md's own text, embedded verbatim — ADR-0193 §D6). Each in its
  # own dimension's branch, never the other's; structure/security carry no guard.
  GUARD_BLOCK=""
  if [ "$DIMENSION" = "dead-code" ]; then
    GUARD_BLOCK='Tag as risk_level: high → fix_type: report-only any @objc, dynamic var/func, protocol conformances used only in as? casts, #selector(...), NSNotification.Name/string-typed ObjC bridge identifiers, reflection-reachable, protocol-witness symbols.'
  fi
  if [ "$DIMENSION" = "perf" ]; then
    GUARD_BLOCK='Tag as risk_level: high → fix_type: report-only any finding touching async/await/actor/DispatchQueue/Sendable/nonisolated. Auto-fix only synchronous perf patterns.'
  fi

  SECURITY_NOTE=""
  if [ "$DIMENSION" = "security" ]; then
    SECURITY_NOTE="Every finding for this dimension is fix_type: report-only, regardless of risk_level or severity — security findings are never auto-fixed."
  fi

  cat > "$PROMPT_FILE" <<PROMPT_EOF
You are auditing a codebase for the "$DIMENSION" dimension of a whole-codebase health audit. You
are reporting only — you make no changes. You are sandboxed to read-only; read each file below by
its path, do not assume its contents from the path alone.

Scope for this dimension: $DIM_SCOPE.

Severity rubric:
- P1: a definite bug, security issue, or explicit rule violation with clear, verifiable impact.
- P2: a real issue, but of moderate impact or lower certainty.
- P3: a minor issue or nitpick, backed by a project convention.

risk_level: high is a hard skip in the automated fix loop, regardless of fix_type. Tag a finding
risk_level: high whenever you are not confident an automated fix is safe — it is always routed to
a report-only section for a human, never auto-fixed.
$GUARD_BLOCK
$SECURITY_NOTE

For each finding, give: dimension ("$DIMENSION"), severity (P1/P2/P3), risk_level (low/high), file
(the path, as given below), line (an integer, or null when the finding is not line-specific), a
concise one-line description, fix_type (coder/refactorer/debugger/report-only), and a 1-2 line
suggested_fix. If there is nothing worth reporting, return an empty findings array — never invent
an issue to have something to report.

FILES TO AUDIT (read each by path; nothing else is in scope):
$FILE_LIST
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
elif [ "$MODE" = "diagnose" ]; then
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
else
  # MODE = audit. Writes --out as a JSON ARRAY (not the schema's {"findings": ...} wrapper — the
  # deep-refactor skill merges the four dimensions' arrays). Three fields are wrapper-enforced and
  # never trusted from the model (ADR-0193 §D4, rule 16): dimension, id, and fix_type-for-security.
  RAW_OUT="$RAW_OUT" CR_OUT="$OUT" DIMENSION="$DIMENSION" python3 -c "
import hashlib
import json, os, sys

path = os.environ['RAW_OUT']
try:
    with open(path) as f:
        data = json.load(f)
except Exception as e:
    sys.stderr.write('codex-reviewer: DID-NOT-RUN: output at %s did not parse against the schema (%s)\n' % (path, e))
    sys.exit(3)

DIMENSION = os.environ.get('DIMENSION', '')
findings = data.get('findings', [])
if not isinstance(findings, list):
    findings = []

VALID_FIX_TYPES = ('coder', 'refactorer', 'debugger', 'report-only')
VALID_SEVERITIES = ('P1', 'P2', 'P3')
VALID_RISK_LEVELS = ('low', 'high')

result = []
for f in findings:
    if not isinstance(f, dict):
        continue

    # 1. dimension is forced to the --dimension argument, unconditionally — never the model's own.
    dimension = DIMENSION

    file_val = f.get('file') or ''
    line_val = f.get('line', None)
    description_val = f.get('description') or ''

    # 2. id is synthesised, never trusted from the model's own 'id' — deterministic across runs on
    # the same input, since the dedup and report stages key on it.
    digest = hashlib.sha256((file_val + str(line_val) + description_val).encode('utf-8')).hexdigest()
    hash3 = digest[:3]
    basename = os.path.basename(file_val) if file_val else 'unknown'
    fid = '%s-%s-%s' % (dimension, basename, hash3)

    # 3. fix_type: security forces report-only on every finding, unconditionally. Otherwise the
    # model's value passes through, defaulted to report-only if not one of the four legal values —
    # an unrecognised value must never route a fix agent.
    fix_type = f.get('fix_type')
    if fix_type not in VALID_FIX_TYPES:
        fix_type = 'report-only'
    if dimension == 'security':
        fix_type = 'report-only'

    # 4. everything else passes through, each with a safe default so a partial object cannot crash
    # the formatter.
    severity = f.get('severity')
    if severity not in VALID_SEVERITIES:
        severity = 'P3'
    risk_level = f.get('risk_level')
    if risk_level not in VALID_RISK_LEVELS:
        risk_level = 'low'
    suggested_fix = f.get('suggested_fix') or ''

    result.append({
        'id': fid,
        'dimension': dimension,
        'severity': severity,
        'risk_level': risk_level,
        'file': file_val,
        'line': line_val,
        'description': description_val,
        'fix_type': fix_type,
        'suggested_fix': suggested_fix,
    })

with open(os.environ['CR_OUT'], 'w') as out:
    json.dump(result, out, indent=2)
    out.write('\n')
" 2>&1
  FORMAT_RC=$?
  if [ "$FORMAT_RC" -eq 3 ]; then
    exit 3
  elif [ "$FORMAT_RC" -ne 0 ]; then
    echo "codex-reviewer: DID-NOT-RUN: formatting the audit output failed (exit $FORMAT_RC)" >&2
    exit 3
  fi
fi

exit 0
