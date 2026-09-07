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
#   --mode review   --diff-scope uncommitted|base:<ref>|commit:<sha> [--carry-forward <file>] [--focus security] --out <file>
#   --mode diagnose --finding "<text>" --out <file>
#   --mode audit    --dimension dead-code|perf|structure|security
#                   [--diff-scope uncommitted|base:<ref>|commit:<sha>] --out <file>
#
# The exit contract above (0/2/3) is unchanged across all three modes. Audit-mode output at --out
# is FINDINGS_SCHEMA-shaped JSON — a JSON array of findings (ADR-0193 §D4) — never the markdown
# review and diagnose modes produce.
#
# --focus security (ADR-0195 D3, review mode only, enumerated — no free-text focus is accepted):
# swaps the fixed five-item checklist for a security-only one naming the same seven vulnerability
# classes `security-audit/SKILL.md` Step 2's brief names verbatim (injection, auth bypass,
# hardcoded secrets, path traversal, insecure deserialization, unguarded URL construction, missing
# input validation) — everything else (--output-schema, the BLOCKER/MAJOR/MINOR/NIT taxonomy, the
# confidence filter, the availability cascade, the exit-code contract, --carry-forward) is
# untouched. Absent --focus, output is byte-identical to before this flag existed.
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
FOCUS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --diff-scope) DIFF_SCOPE="${2:-}"; shift 2 ;;
    --carry-forward) CARRY_FORWARD="${2:-}"; shift 2 ;;
    --finding) FINDING="${2:-}"; shift 2 ;;
    --focus) FOCUS="${2:-}"; shift 2 ;;
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
#
# `base:` and `commit:` with NOTHING after the colon are rejected here, before any git call. The
# documented grammar is `base:<ref>` / `commit:<sha>`, so an absent value is a malformed scope, the
# same class the fall-through arm below already rejects — but the two prefixes fail DIFFERENTLY
# when left to git, and only one of the two failures is visible. Measured on git 2.50.1 (Apple
# Git-155) against this script's own four arms:
#   git diff ""...HEAD  -> exit 0, EMPTY diff. The shell collapses the quoted empty ref and the
#     suffix into the single token `...HEAD`, and gitrevisions specifies an omitted side of
#     `..`/`...` as defaulting to HEAD — so the range is `HEAD...HEAD`, legitimately empty.
#     Measured end to end before this guard: `--diff-scope base:` exited 0 with "safe to merge
#     (nothing to review)" in review mode and 0 with `[]` in audit mode. A FALSE CLEAN, byte-
#     identical to a genuinely reviewed empty diff — the caller cannot tell it never ran.
#   git show --end-of-options ""  -> exit 128 ("ambiguous argument ''"), which the commit: arms
#     turn into exit 3 DID-NOT-RUN. Not a false clean, but the wrong CLASS: exit 3 is the ONE
#     signal callers gate the fallback-to-Claude AskUserQuestion on, spent on a caller error. A
#     malformed argument is exit 2 (rule 20 — the code belongs to this script's own caller
#     contract), the same code and voice validate_ref_no_leading_dash uses for the sibling defect.
# Both prefixes are rejected on one line because "does this scope name a ref at all" is ONE
# question (rule 6), not because git treats them alike — measured, it does not.
validate_diff_scope() {
  case "$1" in
    # Must precede the pattern arm below: `*` matches the empty string, so `base:*` would swallow
    # a bare `base:` and this arm would never be reached.
    base:|commit:) echo "codex-reviewer: --diff-scope ref/sha must not be empty (got '$1')" >&2; exit 2 ;;
    uncommitted|base:*|commit:*) ;;
    *) echo "codex-reviewer: --diff-scope must be 'uncommitted', 'base:<ref>', or 'commit:<sha>' (got '$1')" >&2; exit 2 ;;
  esac
}

# Shared by all four arms that hand a caller-supplied ref/sha to git as its own argument (rule 6:
# one question, one copy). Git parses an argument beginning with `-` as an OPTION, not a revision,
# so an untrusted --diff-scope value turns this read-only review into an arbitrary file write.
# Measured on git 2.50.1 against all four shapes, none excepted:
#   git diff "--output=/tmp/P"...HEAD                       -> exit 0, creates /tmp/P...HEAD
#   git show "--output=/tmp/P"                              -> exit 0, creates /tmp/P
#   git show --name-only --pretty=format: "--output=/tmp/P" -> exit 0, creates /tmp/P
# The `...HEAD` suffix does NOT bind the ref into a safe single token: git absorbs it into the
# option's VALUE, so the diff arms are exactly as injectable as the show arms. This guard, not the
# range syntax, is what closes them. Exit 2, not 3 (rule 20 — the code belongs to this script's own
# caller contract): a malformed value is a caller error, the same class and code validate_diff_scope
# already uses for a malformed scope keyword.
validate_ref_no_leading_dash() {
  case "$1" in
    -*) echo "codex-reviewer: --diff-scope ref/sha must not start with '-' (got '$1')" >&2; exit 2 ;;
  esac
}

if [ "$MODE" = "review" ]; then
  validate_diff_scope "$DIFF_SCOPE"
  if [ -n "$CARRY_FORWARD" ] && [ ! -r "$CARRY_FORWARD" ]; then
    echo "codex-reviewer: --carry-forward file not readable: $CARRY_FORWARD" >&2
    exit 2
  fi
  case "$FOCUS" in
    ""|security) ;;
    *) echo "codex-reviewer: --focus must be 'security' (got '$FOCUS')" >&2; exit 2 ;;
  esac
fi

if [ "$MODE" = "diagnose" ]; then
  if [ -z "$FINDING" ]; then
    echo "codex-reviewer: --finding is required in diagnose mode" >&2
    exit 2
  fi
  if [ -n "$FOCUS" ]; then
    echo "codex-reviewer: --focus is only valid with --mode review" >&2
    exit 2
  fi
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
# The directory the `codex exec` subprocess is run FROM, further down. Default: the caller's own
# cwd, which is exactly what that process inherits today — review and diagnose mode keep it and are
# byte-identical to before, since neither hands codex a PATH to resolve (review embeds the diff
# text, diagnose the finding text). Audit mode overwrites it, for the reason recorded at that
# assignment.
CODEX_CWD="$PWD"
if [ "$MODE" = "review" ]; then
  # Every arm captures its git exit status, none excepted. An unresolvable scope is DID-NOT-RUN
  # (rule 4): stderr is discarded here, so a failing git call — unborn repository, unknown base ref,
  # unknown sha — leaves DIFF_CONTENT empty, which is indistinguishable from a genuinely empty diff
  # and falls into the "nothing to review, safe to merge" branch below with exit 0. Measured: in an
  # unborn repository `git diff HEAD` exits 128 while `git rev-parse --is-inside-work-tree` above
  # still exits 0, so the "not a git repository" guard does not catch it. Audit mode's arms below
  # carry the identical guard; review mode was never updated to match until ADR-0193's cycle-3
  # review found the gap.
  case "$DIFF_SCOPE" in
    uncommitted)
      DIFF_CONTENT=$(git diff HEAD 2>/dev/null)
      _git_rc=$?
      if [ "$_git_rc" -ne 0 ]; then
        echo "codex-reviewer: DID-NOT-RUN: could not resolve diff-scope '$DIFF_SCOPE' (git exit $_git_rc)" >&2
        exit 3
      fi
      ;;
    base:*)
      _ref="${DIFF_SCOPE#base:}"
      validate_ref_no_leading_dash "$_ref"
      DIFF_CONTENT=$(git diff "$_ref"...HEAD 2>/dev/null)
      _git_rc=$?
      if [ "$_git_rc" -ne 0 ]; then
        echo "codex-reviewer: DID-NOT-RUN: could not resolve diff-scope '$DIFF_SCOPE' (git exit $_git_rc)" >&2
        exit 3
      fi
      ;;
    commit:*)
      _sha="${DIFF_SCOPE#commit:}"
      validate_ref_no_leading_dash "$_sha"
      # --end-of-options is defense in depth BEHIND the guard above (git >= 2.24), for a future
      # caller path that reaches this line without validating. Placement is not free: it must sit
      # after every option and immediately before the operand, because git reads anything following
      # it as a non-option (measured: `--end-of-options --name-only` exits 128 on a valid sha).
      DIFF_CONTENT=$(git show --end-of-options "$_sha" 2>/dev/null)
      _git_rc=$?
      if [ "$_git_rc" -ne 0 ]; then
        echo "codex-reviewer: DID-NOT-RUN: could not resolve diff-scope '$DIFF_SCOPE' (git exit $_git_rc)" >&2
        exit 3
      fi
      ;;
  esac

  # Step 4: empty diff is NOT a failure (mirrors reviewer.md's own "no detectable changes" edge
  # case) — exit 0, report says so, in the same markdown shape as every other outcome. Reached only
  # when the git call above exited 0, so an empty DIFF_CONTENT here really is an empty diff.
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
  # Resolved once and used twice on purpose: as enumerate-sources.sh's root (so every path it emits
  # is relative to it) and, in the formatter below, as the prefix those paths are joined back onto.
  # Two independent derivations could disagree about which tree the paths belong to (rule 6).
  # Measured: in a BARE repository `git rev-parse --is-inside-work-tree` above prints "false" and
  # exits 0, so the guard passes and this can still fail — a failure is DID-NOT-RUN (rule 4), never
  # an empty root silently handed on.
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
  _root_rc=$?
  if [ "$_root_rc" -ne 0 ] || [ -z "$REPO_ROOT" ]; then
    echo "codex-reviewer: DID-NOT-RUN: could not resolve the repository root (git exit $_root_rc)" >&2
    exit 3
  fi
  # Used a THIRD time, for the same one-answer reason: as the directory `codex exec` itself is run
  # from. Every path this mode puts in the prompt is REPO-RELATIVE (enumerate-sources.sh emits
  # `git ls-files` output), so the base directory they resolve against is part of the prompt's
  # meaning and has to travel with it. Nothing made it travel: `codex exec` inherits the CALLER'S
  # cwd, and this script is reached from a nested subdirectory as a matter of course —
  # deep-refactor/SKILL.md dispatches it as `bash ~/.claude/hooks/codex-reviewer.sh` from wherever
  # the session happens to sit, never necessarily the repository root. Measured 2026-09-06 on
  # codex-cli 0.153.4: with cwd outside a git repository `codex exec` refuses with "Not inside a
  # trusted directory", so its working root IS derived from the process cwd. Measured on this
  # script before the fix, from `<repo>/sub/deep` with a two-file tracked tree: 2 of 2 audited paths
  # resolved to files that do not exist, and the run still exited 0 with an empty findings array —
  # a FALSE CLEAN audit, indistinguishable from a genuinely clean dimension, which is worse than a
  # DID-NOT-RUN because deep-refactor/SKILL.md records the dimension as audited.
  CODEX_CWD="$REPO_ROOT"

  # Whole-tree by default (ADR-0193 §D2/§D3) — the file list is DERIVED, never re-listed: the same
  # question ("which files are this project's source") answered once, by enumerate-sources.sh.
  ALL_FILES=$("$ENUM" "$REPO_ROOT")
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
    # Every arm captures its git exit status, none excepted. An unresolvable scope is DID-NOT-RUN
    # (rule 4): stderr is discarded here, so a silent empty CHANGED_FILES would intersect to nothing
    # and report a clean audit of a scope that was never evaluated. `uncommitted` is no exception —
    # measured: in an unborn repository (no commits, HEAD unresolvable) `git diff HEAD` exits 128
    # while `git rev-parse --is-inside-work-tree` above still exits 0.
    case "$DIFF_SCOPE" in
      uncommitted)
        CHANGED_FILES=$(git diff HEAD --name-only 2>/dev/null)
        _git_rc=$?
        if [ "$_git_rc" -ne 0 ]; then
          echo "codex-reviewer: DID-NOT-RUN: could not resolve diff-scope '$DIFF_SCOPE' (git exit $_git_rc)" >&2
          exit 3
        fi
        ;;
      base:*)
        _ref="${DIFF_SCOPE#base:}"
        validate_ref_no_leading_dash "$_ref"
        CHANGED_FILES=$(git diff "$_ref"...HEAD --name-only 2>/dev/null)
        _git_rc=$?
        if [ "$_git_rc" -ne 0 ]; then
          echo "codex-reviewer: DID-NOT-RUN: could not resolve diff-scope '$DIFF_SCOPE' (git exit $_git_rc)" >&2
          exit 3
        fi
        ;;
      commit:*)
        _sha="${DIFF_SCOPE#commit:}"
        validate_ref_no_leading_dash "$_sha"
        # --end-of-options goes LAST here, after --name-only and --pretty=format:, for the placement
        # reason spelled out on the review-mode arm above — putting it first breaks the happy path.
        CHANGED_FILES=$(git show --name-only --pretty=format: --end-of-options "$_sha" 2>/dev/null)
        _git_rc=$?
        if [ "$_git_rc" -ne 0 ]; then
          echo "codex-reviewer: DID-NOT-RUN: could not resolve diff-scope '$DIFF_SCOPE' (git exit $_git_rc)" >&2
          exit 3
        fi
        ;;
    esac
    # mktemp is a derivation like any other and is captured like one (rule 4). If it fails the
    # variable is empty, the printf below writes nowhere, and `grep -Fxf` — whose stderr is already
    # discarded — yields an empty FILE_LIST, which the empty-result branch below reports as a clean
    # audit with exit 0. A broken intersection and a genuinely empty diff must not be
    # indistinguishable from outside (rule 7). stderr is deliberately NOT discarded here: mktemp's
    # own diagnostic is the only thing that says why the temp file could not be created.
    ALL_FILES_FILE=$(mktemp)
    _mktemp_rc=$?
    if [ "$_mktemp_rc" -ne 0 ] || [ -z "$ALL_FILES_FILE" ]; then
      echo "codex-reviewer: DID-NOT-RUN: could not create the temporary file for the whole-tree list (mktemp exit $_mktemp_rc)" >&2
      exit 3
    fi
    CHANGED_FILES_FILE=$(mktemp)
    _mktemp_rc=$?
    if [ "$_mktemp_rc" -ne 0 ] || [ -z "$CHANGED_FILES_FILE" ]; then
      echo "codex-reviewer: DID-NOT-RUN: could not create the temporary file for the changed-paths list (mktemp exit $_mktemp_rc)" >&2
      rm -f "$ALL_FILES_FILE"
      exit 3
    fi
    # The two writes and the intersection itself are captured for the same reason the mktemp calls
    # above are (rule 4): a printf that fails AFTER a successful mktemp — a filesystem that fills
    # between the two writes — and a grep that fails for any reason other than "no match" both leave
    # FILE_LIST empty, and the empty-result branch below reports that as a clean audit with exit 0.
    # A broken intersection and a genuinely empty diff must not be indistinguishable from outside
    # (rule 7). grep's own contract makes exit 0 (matched) and exit 1 (no match) both legitimate and
    # silent, so only a status ABOVE 1 — typically an I/O error — is a failure here; its stderr is
    # discarded on the line itself, which leaves the status as the only evidence the intersection
    # was never computed. Every one of these paths removes both temp files: this block runs before
    # the EXIT trap installed further down, so nothing else would clean them up.
    printf '%s\n' "$ALL_FILES" > "$ALL_FILES_FILE"
    _write_rc=$?
    if [ "$_write_rc" -ne 0 ]; then
      echo "codex-reviewer: DID-NOT-RUN: could not write the whole-tree list to its temporary file (printf exit $_write_rc)" >&2
      rm -f "$ALL_FILES_FILE" "$CHANGED_FILES_FILE"
      exit 3
    fi
    printf '%s\n' "$CHANGED_FILES" > "$CHANGED_FILES_FILE"
    _write_rc=$?
    if [ "$_write_rc" -ne 0 ]; then
      echo "codex-reviewer: DID-NOT-RUN: could not write the changed-paths list to its temporary file (printf exit $_write_rc)" >&2
      rm -f "$ALL_FILES_FILE" "$CHANGED_FILES_FILE"
      exit 3
    fi
    FILE_LIST=$(grep -Fxf "$CHANGED_FILES_FILE" "$ALL_FILES_FILE" 2>/dev/null)
    _grep_rc=$?
    if [ "$_grep_rc" -gt 1 ]; then
      echo "codex-reviewer: DID-NOT-RUN: could not intersect the whole-tree and changed-paths lists (grep exit $_grep_rc)" >&2
      rm -f "$ALL_FILES_FILE" "$CHANGED_FILES_FILE"
      exit 3
    fi
    rm -f "$ALL_FILES_FILE" "$CHANGED_FILES_FILE"
  else
    FILE_LIST="$ALL_FILES"
  fi

  # An empty result is exit 0 with an empty findings array written to --out, mirroring review
  # mode's own empty-diff precedent immediately above — never exit 3 (ADR-0193 §D3). That contract
  # is about the empty RESULT, not about the write that carries it: exit 0 PROMISES the caller a
  # parseable --out artifact, so a write that fails still owes it a DID-NOT-RUN (rule 4), captured
  # exactly like the two intersection writes above. Measured before this guard existed: an
  # unwritable --out on this path exited 0 having created no file at all, with bash's own
  # "Permission denied" redirection diagnostic as the only evidence — on stderr, which this file's
  # CHECKER contract says callers never branch on. deep-refactor/SKILL.md's audit dispatch then
  # does what it is told for exit 0, "parse <tmp-<d>.json> as the FINDINGS_SCHEMA array", against
  # a file that is not there: a write failure reads as a clean, zero-finding dimension.
  if [ -z "$FILE_LIST" ]; then
    printf '[]\n' > "$OUT"
    _write_rc=$?
    if [ "$_write_rc" -ne 0 ]; then
      echo "codex-reviewer: DID-NOT-RUN: could not write the empty findings array to the --out file '$OUT' (printf exit $_write_rc)" >&2
      exit 3
    fi
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

  # Hand-ported from reviewer.md (see header comment) — rule 6/12 cross-reference. The security
  # checklist below is hand-ported the same way from `security-audit/SKILL.md` Step 2's brief
  # (ADR-0195 D3) — its seven vulnerability classes are named verbatim so a harness can pin the
  # two lists against each other.
  if [ "$FOCUS" = "security" ]; then
    REVIEW_INTRO="You are a senior security reviewer. Review the diff below for security findings
only: injection, auth bypass, hardcoded secrets, path traversal, insecure deserialization,
unguarded URL construction, missing input validation. Ignore style, structure, and performance —
those are out of scope for this review. You are reporting only — you make no changes."
    CHECKLIST="Checklist (security only):
- Injection: SQL/command/template/log injection, unsanitized input reaching an interpreter, shell,
  or query.
- Auth bypass: missing or incorrect authentication/authorization checks, privilege escalation.
- Hardcoded secrets: API keys, tokens, passwords, credentials committed to source.
- Path traversal: unsanitized file paths, directory-escape sequences, unchecked user-controlled
  paths.
- Insecure deserialization: untrusted data deserialized into objects without validation.
- Unguarded URL construction: user input concatenated into URLs without validation or encoding,
  SSRF-prone constructs.
- Missing input validation: unchecked or untyped external input reaching a sensitive operation."
  else
    REVIEW_INTRO="You are a senior code reviewer. Review the diff below for security, correctness, performance, and
consistency. You are reporting only — you make no changes."
    CHECKLIST="Checklist:
- Security: input validation, injection, hardcoded secrets, auth/authz flow.
- Correctness: logic bugs, edge cases, error handling, race conditions.
- Performance: N+1 queries, needless loops, blocking calls on async paths.
- Consistency: matches existing patterns in this repository; no unjustified deviation from its
  own documented conventions or ADRs.
- Tests: coverage of the changed behavior; missing edge-case tests."
  fi

  cat > "$PROMPT_FILE" <<PROMPT_EOF
$REVIEW_INTRO

$CHECKLIST

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
if [ "$FOCUS" = "security" ]; then
  # ADR-0195 D3 point 3: --focus security does not inherit the high-volume cost pin below —
  # this is the lowest-volume, highest-miss-cost review site in the system (security-audit is
  # on-demand only, wired into no chain). gpt-5.6-sol is the config's own baseline model
  # (`~/.codex/config.toml`); effort is elevated to `high`, not `xhigh` — Stefano's explicit cap
  # on this pin (2026-09-06) — since `xhigh` was confirmed to work but judged too expensive for
  # this dispatch.
  CODEX_MODEL="gpt-5.6-sol"
  CODEX_EFFORT="high"
else
  # Cost pin (2026-09-05): review dispatch is automated and high-volume, unlike Stefano's
  # interactive Codex sessions — it does not need his global config's top-tier
  # model/effort (gpt-5.6-sol, xhigh). Pinned here, not in ~/.codex/config.toml, so the
  # interactive default is untouched. -m/-c override the global config for this call only.
  CODEX_MODEL="gpt-5.6-terra"
  CODEX_EFFORT="medium"
fi
# Run from CODEX_CWD, never from wherever the caller happened to stand: in audit mode that is
# REPO_ROOT, the base the prompt's repo-relative paths are meant to resolve against (the assignment
# above records what a nested cwd measurably does); in review and diagnose mode it is the caller's
# own cwd, so those two modes gain no new behaviour and no new failure path. The subshell is what
# keeps the change local — every path this command touches ($SCHEMA_FILE, $RAW_OUT, $PROMPT_FILE)
# is an absolute mktemp path, while --out and the formatters below stay resolved against the
# caller's cwd exactly as before. A `cd` that fails short-circuits the &&, so the subshell's
# non-zero status lands in the DID-NOT-RUN branch below with bash's own cd diagnostic captured in
# CODEX_STDERR and quoted in the message: never a run that silently proceeds in the wrong tree.
# CODEX_MODEL/CODEX_EFFORT are resolved OUTSIDE this subshell (above) so they stay visible to the
# CR_MODEL/CR_EFFORT provenance line further down — a subshell assignment would not survive it.
( cd "$CODEX_CWD" && codex exec -m "$CODEX_MODEL" -c model_reasoning_effort="$CODEX_EFFORT" \
  --sandbox read-only --output-schema "$SCHEMA_FILE" -o "$RAW_OUT" \
  "$(cat "$PROMPT_FILE")" ) >/dev/null 2>"$CODEX_STDERR"
CODEX_RC=$?
CODEX_ERR_TEXT=$(cat "$CODEX_STDERR" 2>/dev/null)
rm -f "$CODEX_STDERR"

if [ "$CODEX_RC" -ne 0 ]; then
  echo "codex-reviewer: DID-NOT-RUN: codex exec exited $CODEX_RC — $(printf '%s' "$CODEX_ERR_TEXT" | head -1)" >&2
  exit 3
fi

# A non-empty $RAW_OUT means codex exec actually completed and wrote a result — a real
# rate/quota rejection produces no output, so a valid file here outranks anything the
# rate-limit-vocabulary grep below might match. That grep runs on the FULL stderr, which
# includes codex's own echo of the prompt it was given; when the reviewed diff itself
# contains one of the matched words (e.g. editing this file's own rate-limit check), the
# echoed prompt satisfies the grep and a completed, paid-for review was discarded as
# DID-NOT-RUN (found during the 2026-09-05 dry run). Checking for real output first closes
# that false positive without weakening the real rate-limit detection below.
if [ -s "$RAW_OUT" ]; then
  : # completed successfully — fall through to formatting below
elif printf '%s' "$CODEX_ERR_TEXT" | grep -Eqi 'usage limit|rate limit|quota exceeded|\b429\b'; then
  echo "codex-reviewer: DID-NOT-RUN: codex exec reported a rate/quota limit — $(printf '%s' "$CODEX_ERR_TEXT" | head -1)" >&2
  exit 3
else
  echo "codex-reviewer: DID-NOT-RUN: codex exec produced no output at $RAW_OUT" >&2
  exit 3
fi

# --- Format the schema JSON into reviewer.md's exact markdown shape ------------------------------

if [ "$MODE" = "review" ]; then
  RAW_OUT="$RAW_OUT" CR_OUT="$OUT" CR_MODEL="$CODEX_MODEL" CR_EFFORT="$CODEX_EFFORT" python3 -c "
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

# ADR-0195 D5: producer-emitted provenance, not consumer-recalled — a caller copies this line
# verbatim into its own report rather than restating what it thinks it pinned.
lines.append('')
lines.append('_Reviewed by: \`%s\` (effort: %s)_' % (os.environ['CR_MODEL'], os.environ['CR_EFFORT']))

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
  # deep-refactor skill merges the four dimensions' arrays). FOUR fields are wrapper-enforced and
  # never trusted from the model (ADR-0193 §D4, rule 16): dimension, id, fix_type-for-security, and
  # `file` — normalised from the repo-relative form the prompt handed the model into the absolute
  # path deep-refactor/SKILL.md's finding schema declares, AND validated against the audited scope.
  # FILE_LIST is passed in for that validation and for no other purpose: deep-refactor/SKILL.md
  # hands a finding's `file` straight into an edit-capable coder/refactorer dispatch prompt without
  # re-validating it, so a hallucinated, prompt-injected or malicious path accepted here becomes an
  # autonomous edit to an arbitrary path on disk. The model's `file` is an untrusted input like any
  # other model output, and the only authority on what was in scope is the list this script itself
  # enumerated and put in the prompt.
  RAW_OUT="$RAW_OUT" CR_OUT="$OUT" DIMENSION="$DIMENSION" REPO_ROOT="$REPO_ROOT" FILE_LIST="$FILE_LIST" python3 -c "
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
# Non-empty by construction: the audit branch exits 3 above if the repository root does not resolve.
REPO_ROOT = os.environ.get('REPO_ROOT', '')
findings = data.get('findings', [])
if not isinstance(findings, list):
    findings = []

VALID_FIX_TYPES = ('coder', 'refactorer', 'debugger', 'report-only')
VALID_SEVERITIES = ('P1', 'P2', 'P3')
VALID_RISK_LEVELS = ('low', 'high')

# The audited scope, canonicalised once: exactly the paths the prompt offered the model, joined
# onto REPO_ROOT and resolved with realpath so the membership test below compares like with like
# (a '..' segment or a symlinked directory must not let two spellings of one path disagree).
# FILE_LIST covers BOTH audit shapes with no branch here — the --diff-scope intersection and the
# whole-tree list are the same variable by the time the prompt is built.
#
# AND EVERY RESOLVED PATH IS CHECKED BACK AGAINST THE ROOT before it is admitted, because realpath
# follows symlinks all the way through and FILE_LIST is git ls-files output, which lists TRACKED
# SYMLINKS beside regular files. A tracked 'evil.py -> ../../outside/secret.py' resolves to a path
# outside the tree; admitting it here admits it to the membership test below, so a finding naming
# 'evil.py' passes the scope check BY CONSTRUCTION and is emitted with an absolute file value
# pointing anywhere on the filesystem — which deep-refactor/SKILL.md forwards to an edit-capable
# agent unchecked. Measured against this loop without the check, on a scratch repo carrying such a
# symlink: exit 0, nothing rejected, the out-of-tree target emitted as the finding's file.
# The separator is load-bearing, not defensive dressing: a bare startswith(_repo_root_real) also
# admits a SIBLING directory named <root>-other, measured with the same fixture, so the test is
# equality with the root or a prefix that ends at a path boundary.
# (No backticks anywhere above: this whole formatter is a double-quoted python3 -c body, so a
# backtick in a COMMENT is still command substitution run by the shell before python sees it.)
_repo_root_real = os.path.realpath(REPO_ROOT)
_root_prefix = _repo_root_real + os.sep
ALLOWED_FILES = set()
for _rel in os.environ.get('FILE_LIST', '').split('\n'):
    if not _rel:
        continue
    _abs = os.path.realpath(os.path.join(REPO_ROOT, _rel))
    if _abs != _repo_root_real and not _abs.startswith(_root_prefix):
        # Informational, never fatal: a tracked symlink leaving the tree is a hygiene defect in the
        # repository being audited, not a reason to abandon the audit of every other file. It is
        # named because a path silently dropped from the audited scope is otherwise
        # indistinguishable from one that was never tracked at all (rule 7 — the denominator moved).
        sys.stderr.write('codex-reviewer: EXCLUDED from the audited scope: \'%s\' resolves outside the repository root (tracked symlink?)\n' % _rel)
        continue
    ALLOWED_FILES.add(_abs)

# Denominator guard (rule 7): the audit branch exits 0 early on an empty FILE_LIST, so an empty
# allow-set HERE means the list never reached this formatter — a wiring defect in this script, not
# an untrustworthy model. Without this, every finding would be rejected below and the run would
# report the model as entirely bogus, which is the wrong diagnosis and sends the caller to a
# fallback engine that will hit the same wiring defect.
if not ALLOWED_FILES:
    sys.stderr.write('codex-reviewer: DID-NOT-RUN: the in-scope file list did not reach the audit formatter, so no finding could be validated against it\n')
    sys.exit(3)

result = []
rejected = 0
for f in findings:
    if not isinstance(f, dict):
        continue

    # 1. dimension is forced to the --dimension argument, unconditionally — never the model's own.
    dimension = DIMENSION

    file_val = f.get('file') or ''
    line_val = f.get('line', None)
    description_val = f.get('description') or ''

    # 2. id is synthesised, never trusted from the model's own 'id' — deterministic across runs on
    # the same input, since the dedup and report stages key on it. Keyed on the REPO-RELATIVE path,
    # not the absolute one built below, so the same tree audited from a different checkout or
    # worktree yields the same ids.
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

    # 5. file is emitted ABSOLUTE. deep-refactor/SKILL.md's finding schema declares 'file' as
    # '<absolute path>', and Gate 1 merges this array with the Claude-reviewer-sourced findings that
    # already honour it, deduping on file + line + description — a repo-relative value here would
    # never match its Claude-side twin. FILE_LIST is relative to REPO_ROOT (both come from
    # enumerate-sources.sh's git ls-files), so join it back on. A value that is already absolute is
    # left alone rather than prefixed twice, in case a future caller supplies one.
    if file_val and not os.path.isabs(file_val):
        file_out = os.path.join(REPO_ROOT, file_val)
    else:
        file_out = file_val

    # 6. and then it is CHECKED against the audited scope, because normalising a path is not
    # validating it: '../../etc/passwd' and an arbitrary absolute path both normalise perfectly.
    # realpath collapses '..' traversal and symlinks so the comparison cannot be defeated by
    # spelling; a finding that lands outside the enumerated set is DROPPED, never emitted, since
    # deep-refactor/SKILL.md forwards this value to an edit-capable agent unchecked. The rejection
    # is reported on stderr with the ORIGINAL value the model gave, not the resolved one — what the
    # model actually said is what a human debugging a rejection needs to see.
    file_out = os.path.realpath(file_out)
    if file_out not in ALLOWED_FILES:
        sys.stderr.write('codex-reviewer: REJECTED finding: file \'%s\' resolves outside the audited scope (FILE_LIST/REPO_ROOT)\n' % file_val)
        rejected += 1
        continue

    result.append({
        'id': fid,
        'dimension': dimension,
        'severity': severity,
        'risk_level': risk_level,
        'file': file_out,
        'line': line_val,
        'description': description_val,
        'fix_type': fix_type,
        'suggested_fix': suggested_fix,
    })

# An empty result has two causes that must NOT collapse into one exit code (rule 4, rule 7).
# rejected == 0: the model genuinely found nothing — unchanged, exit 0 with an empty array, the
# same clean-audit answer the empty-FILE_LIST branch gives. rejected > 0 with nothing surviving:
# every single thing the model said pointed outside the tree it was asked to audit, so the output
# is not a clean audit but an untrustworthy one, and no --out artifact is written. The caller
# (deep-refactor/SKILL.md) routes exit 3 to the Claude reviewer for that dimension; exit 0 would
# instead record a dimension audited and clean, which is the failure this whole branch exists to
# prevent. A PARTIAL rejection is deliberately NOT this case: one surviving finding means the run
# produced real results, and the stderr lines above are how a caller sees what was dropped.
if not result and rejected:
    sys.stderr.write('codex-reviewer: DID-NOT-RUN: all %d finding(s) resolved outside the audited scope; audit output is not trustworthy\n' % rejected)
    sys.exit(3)

with open(os.environ['CR_OUT'], 'w') as out:
    json.dump(result, out, indent=2)
    out.write('\n')
"
  # No `2>&1` here, unlike the review and diagnose invocations above: this formatter's stderr is
  # now load-bearing (the REJECTED lines and the two DID-NOT-RUN lines), and merging it into stdout
  # sends it to a stream this script's own CHECKER contract says it never uses — the exit code is
  # the signal, --out is the artifact, and every diagnostic in this file goes to stderr. Restoring
  # the merge would silently make a rejected finding invisible to any caller reading stderr.
  FORMAT_RC=$?
  if [ "$FORMAT_RC" -eq 3 ]; then
    exit 3
  elif [ "$FORMAT_RC" -ne 0 ]; then
    echo "codex-reviewer: DID-NOT-RUN: formatting the audit output failed (exit $FORMAT_RC)" >&2
    exit 3
  fi
fi

exit 0
