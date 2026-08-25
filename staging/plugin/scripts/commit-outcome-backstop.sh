#!/bin/bash
# commit-outcome-backstop.sh v1.0 — PostToolUse hook (ADR-0168, SPEC.md R-03..R-07).
#
# WHAT THIS DOES. `concept-to-code`'s Step 7.1 classifies what the `commit` skill actually did by
# reading the manifest on disk (COMMIT_OK / COMMIT_UNCOMMITTED / COMMIT_NONTERMINAL /
# COMMIT_OUTCOME_NORUN, via commit-outcome-check.sh — ADR-0168 §D1). That check is a SKILL.md prose
# instruction with no structural enforcement. This hook is a stateless, mechanical backstop: on every
# `Skill` tool call whose `tool_input.skill == "commit"`, it re-derives the project root from the
# call's own `cwd`, finds manifests written in the last 24h that sit at a commit-stage-or-terminal
# `current_step`, re-runs the SAME commit-outcome-check.sh against each, and surfaces anything other
# than COMMIT_OK — independently of whether Step 7.1 was actually run.
#
# THIS HOOK NEVER BLOCKS, AND THAT IS NOT A MISSING FEATURE (ADR-0168 §D4/A1). A PostToolUse hook
# cannot replay Step 7.1's ADR-0078 absorbing-state reasoning or its "no rollback" instruction; that
# messaging stays exclusively in SKILL.md. This file is a REPORTER (rule 5): it always exits 0 and
# signals on stdout/the audit log, never on exit code. Do not add a `decision`/`block` field here —
# that duplicates a halt Step 7.1 already owns, badly, without the paragraph that tells the operator
# what to do about it.
#
# FAIL OPEN ON EVERY ERROR PATH: no docs/manifests/ found, jq absent, an unwritable audit-log
# directory, an unresolved commit-outcome-check.sh, an unreadable manifest. Every one of them exits 0.
# Where the hook can still say something useful it does — an unresolved checker is reported once, as
# its own NORUN condition, never silently folded into "found nothing" (rule 4).
#
# Contract: exit 0 on every path, no exceptions. Empty stdout on the clean/no-op paths. One audit
# line per examined manifest, plus one CLEAN line per invocation when nothing was in scope — the
# CLEAN line exists so a hook that fired and found nothing stays distinguishable from a hook that
# never fired at all (ADR-0127 §D2.1's wired-but-inert precedent; ADR-0168 §D6). State dir + audit
# log shape mirror precompact-guard.sh's (ADR-0058). Bash 3.2 clean: no associative arrays, no
# mapfile, no process substitution.
#
# transcript-scan-exempt: this hook reads only its own stdin JSON payload (tool_name, tool_input,
#   cwd, session_id). It never reads transcript_path and carries no such field.
set -u

DIR="${COMMIT_OUTCOME_BACKSTOP_DIR:-$HOME/.claude/state/commit-outcome-backstop}"
LOG="$DIR/audit.log"

# log_audit <session_id> <manifest-or-dash> <classification> <reason> — same tab-separated shape as
# precompact-guard.sh's own audit log: ts, session_id, manifest, classification, reason (ADR-0168
# §D9/D6). mkdir -p is lazy and best-effort: nothing in this file creates $DIR before the first line
# actually needs writing, so a payload that never matches the `commit` skill leaves no trace at all.
log_audit() {
  mkdir -p "$DIR" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" >>"$LOG" 2>/dev/null || true
}

INPUT=$(cat 2>/dev/null) || INPUT=""
[ -z "$INPUT" ] && exit 0

# Cheap pre-filter, BEFORE any jq/log/scan (ADR-0168 §D7 step 2). This hook is registered on the
# `Skill` matcher, so it runs on every skill call in every session on the machine — the common path
# must cost one grep and nothing else. This is R-03's no-op path, not the authority: it can
# over-match (a non-commit skill whose `args` string happens to quote the same literal) but it
# cannot under-match a real `commit` invocation, which is the direction that would matter.
printf '%s' "$INPUT" | grep -q '"skill"[[:space:]]*:[[:space:]]*"commit"' || exit 0

command -v jq >/dev/null 2>&1 || { log_audit "?" "-" "-" "jq missing"; exit 0; }

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

# The grep above is a pre-filter, never the authority — re-decide precisely here.
[ "$TOOL_NAME" = "Skill" ] && [ "$SKILL" = "commit" ] || exit 0

# --- locate a project root: walk up from cwd looking for docs/manifests/ (mirrors
# precompact-guard.sh's own walk-up, ADR-0058). Resolved from the PAYLOAD's cwd, never from this
# process's own $PWD/PWD env — a commit invoked against a different worktree than the session's own
# cwd must resolve THAT tree, not wherever this hook process happens to be running (ADR-0168,
# Consequences/Negative). Most `commit` calls are not inside a concept-to-code project at all, so
# absence here is silent, not an error.
ROOT=""; d="$CWD"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -d "$d/docs/manifests" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done
[ -z "$ROOT" ] && exit 0

yval() { grep -aE "^$1:" "$2" 2>/dev/null | head -1 | sed -E "s/^$1:[[:space:]]*//; s/^\"//; s/\"\$//"; }

# is_commit_stage_state — the commit-stage-or-terminal current_step values, taken from
# manifest-transition.sh's own graph across the Standard / Express / Hybrid chain paths, plus
# `completed` itself. This DELIBERATELY EXCEEDS SPEC.md's two-disjunct sketch ("status: completed OR
# current_step: completed") per ADR-0168 §D5: that sketch drops SPEC.md's own R-04 fixture
# (current_step: step_7_commit, status: in_progress — the actual Adnota PR #36 state) before the
# classification below ever sees it. Three paths, not one, because a manifest sitting at ANY chain
# path's own commit step is exactly a manifest for which the answer to "did the commit that was just
# supposed to terminalise this actually get there" can be no.
is_commit_stage_state() {
  case "$1" in
    completed|step_7_commit|step_e4_commit|step_h5_commit) return 0 ;;
    *) return 1 ;;
  esac
}

# --- enumerate the 24h window (ADR-0168 §D5) --------------------------------------------------
# -mtime -1 is the one spelling BSD and GNU find agree on (-newermt is GNU-only, stat flags differ).
# Iterate line-wise via a temp file + `while IFS= read -r`, never over an unquoted expansion (the
# host shell is zsh; a filename could in principle contain whitespace).
_list=""
_kept=""
_list=$(mktemp 2>/dev/null) || _list="${TMPDIR:-/tmp}/commit-outcome-backstop-list.$$"
find "$ROOT/docs/manifests" -name '*.manifest.yml' -mtime -1 >"$_list" 2>/dev/null

_kept=$(mktemp 2>/dev/null) || _kept="${TMPDIR:-/tmp}/commit-outcome-backstop-kept.$$"
: >"$_kept" 2>/dev/null

while IFS= read -r _m; do
  [ -f "$_m" ] || continue
  _step=$(yval current_step "$_m")
  _status=$(yval status "$_m")
  if is_commit_stage_state "$_step" || [ "$_status" = "completed" ]; then
    printf '%s\n' "$_m" >>"$_kept"
  fi
done <"$_list"
rm -f "$_list" 2>/dev/null || true

# Population check BEFORE resolving the checker (deliberate ordering, ADR-0168 §D6): the
# overwhelmingly common invocation has nothing in scope at all, and resolving/reporting on the
# checker in that case would turn "nothing to check" into transcript noise on every unrelated commit
# on a machine where commit-outcome-check.sh simply is not deployed yet — exactly the noise D6 exists
# to avoid on the clean path. Nothing kept -> one CLEAN audit line, stdout stays empty.
if [ ! -s "$_kept" ]; then
  rm -f "$_kept" 2>/dev/null || true
  log_audit "$SID" "-" "CLEAN" "no in-scope manifest in the 24h window under $ROOT"
  exit 0
fi

# --- resolve commit-outcome-check.sh, two-tier, same convention as every other concept-to-code
# helper in this codebase (ADR-0168 §D1/D9): CLAUDE_PLUGIN_ROOT first, $HOME/.claude second, a
# distinct did-not-run condition third. No fallback copy of the classification (D3): an unresolved
# script is reported, never silently treated as a clean result.
CHECKER=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/commit-outcome-check.sh" ]; then
  CHECKER="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/commit-outcome-check.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/commit-outcome-check.sh" ]; then
  CHECKER="$HOME/.claude/skills/concept-to-code/scripts/commit-outcome-check.sh"
fi

if [ -z "$CHECKER" ]; then
  rm -f "$_kept" 2>/dev/null || true
  log_audit "$SID" "-" "NORUN" "noScript checker unresolved (checked CLAUDE_PLUGIN_ROOT and HOME/.claude)"
  printf 'commit-outcome-backstop: COMMIT_OUTCOME_NORUN noScript -- commit-outcome-check.sh is not deployed (checked CLAUDE_PLUGIN_ROOT and HOME/.claude); run sync-to-claude.sh to deploy it. See concept-to-code SKILL.md Step 7.1.\n'
  exit 0
fi

# --- run the checker per kept manifest. COMMIT_OK -> audit line only, no stdout (the common,
# expected outcome of a healthy commit). Anything else -> one stdout report line (manifest path,
# token, a pointer to Step 7.1 — never restating Step 7.1's own remediation, ADR-0168 §D4) plus one
# audit line, per manifest.
#
# commit-outcome-check.sh is a CHECKER, and this is its call site (rule 5, ADR-0168 §D4, and the
# checker's own header): the CLASSIFICATION IS DRIVEN BY ITS EXIT CODE — 0 COMMIT_OK, 1 not-OK,
# 3 did-not-run — never by whether its stdout happens to start with a matching prefix. Its stdout is
# read for two things only, both of them human-readable text: the qualifier that distinguishes
# UNCOMMITTED from NONTERMINAL within the single exit-1 bucket, and the trailing reason string. A
# checker whose stdout is mangled or empty still classifies correctly here; one whose exit code and
# stdout disagree is classified by the exit code, which is the authority. The other caller (the
# `c2c-step7-commit-outcome` fence in SKILL.md) does the same thing in its own idiom: `bash "$_check"
# <manifest>; exit $?`.
while IFS= read -r _m; do
  [ -f "$_m" ] || continue
  _out=$(bash "$CHECKER" "$_m" 2>/dev/null); _rc=$?
  # Flattened copy, for the two off-contract paths below that quote the raw stdout into what must
  # stay ONE tab-separated audit line: a checker printing a newline or a tab must not forge a second
  # record or shift the fields of this one.
  _flat=$(printf '%s' "$_out" | tr '\n\t' '  ')
  _token=$(printf '%s' "$_out" | awk '{print $1}')
  _reason=$(printf '%s' "$_out" | awk '{ $1=""; sub(/^ /,""); print }')
  case "$_rc" in
    0) _verdict="COMMIT_OK" ;;
    1) case "$_token" in
         COMMIT_UNCOMMITTED|COMMIT_NONTERMINAL) _verdict="$_token" ;;
         # Exit 1 with an unreadable qualifier: the check RAN and said not-OK, so it must not be
         # folded into NORUN (rule 4, in the other direction) and must not be guessed into one of the
         # two real qualifiers either — that would invent a cause. Report the bucket, carry the raw
         # stdout as the reason.
         *) _verdict="COMMIT_NOT_OK"; _reason="unqualified checker output: ${_flat:-(empty)}" ;;
       esac ;;
    3) _verdict="COMMIT_OUTCOME_NORUN" ;;
    *) _verdict="COMMIT_OUTCOME_NORUN"; _reason="checker exited $_rc: ${_flat:-(empty)}" ;;
  esac
  [ -z "$_reason" ] && _reason="-"
  log_audit "$SID" "$_m" "$_verdict" "$_reason"
  if [ "$_verdict" != "COMMIT_OK" ]; then
    printf 'commit-outcome-backstop: %s -> %s %s (see concept-to-code SKILL.md Step 7.1)\n' "$_m" "$_verdict" "$_reason"
  fi
done <"$_kept"
rm -f "$_kept" 2>/dev/null || true
exit 0
