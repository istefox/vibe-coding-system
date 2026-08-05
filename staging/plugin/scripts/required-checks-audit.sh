#!/usr/bin/env bash
# required-checks-audit.sh v1.0 — is every status check `main` REQUIRES something this repo can
# actually produce? Issue #322, ADR-0114. Bash 3.2 clean: no assoc array, no mapfile, no ${v^^}.
#
# WHY THIS EXISTS. `autopilot` pre-flight check 8 exists so a night of work ends in PRs a
# human can merge in the morning. Its text said *"verify the `ci` check is required on main"* — and
# it was PROSE, with no mechanism at all: grepping `staging/` for a protection API call returned
# exactly one hit, inside `set-branch-protection.sh`. Meanwhile this repository's `main` requires
# THREE contexts (markdownlint, links, ci), because `set-branch-protection.sh` unions exactly one
# into whatever is already there and the other two arrived by another route. So the pre-flight could
# pass while two thirds of the merge gate was unknown to it, and a red `markdownlint` — real, PR
# #317 — surfaced only when the human tried to merge.
#
# IT IS A CHECKER. The caller branches on the EXIT CODE.
#   0  PASS                every required context has a producer
#   0  NO-PROTECTION       the branch has none — nothing blocks a merge, today's behaviour (R-04)
#   0  NO-REQUIRED-CHECKS  protection exists, contexts list empty — a DISTINCT token (R-03)
#   1  UNSATISFIABLE       a required context nothing produces — the caller aborts (R-02)
#   2  bad invocation
#   3  the check DID NOT RUN
#
# WHY 3 IS SEPARATE FROM 0, AND WHY NO-REQUIRED-CHECKS IS SEPARATE FROM PASS. Three situations
# report "no required context was found to be broken" and they are not the same sentence: every one
# was verified; there was nothing to verify; nobody could look. Collapsing any pair reproduces the
# defect this script exists to close, one level down (ADR-0076's line between a fact about the INPUT
# and a fact about the ENVIRONMENT).
#
# AUTHORITY: THE LIVE REQUIRED SET, DERIVED, NEVER DECLARED. A list declared in the opt-in marker
# cannot lower what GitHub actually enforces, so a declaration that disagrees with live is a stale
# declaration and not a lighter gate. The "a silently-added required check should be a FINDING"
# concern is answered by SATISFIABILITY instead: a required context nothing produces aborts, and one
# a workflow does produce is genuinely satisfiable, so the run adopting it is correct.
#
# PRODUCER EVIDENCE IS A UNION OF TWO SOURCES, so a false abort needs both to miss:
#   1. check-run names observed on the branch HEAD  (empirical: it ran here)
#   2. job identifiers declared in .github/workflows/*.yml  (declarative: it exists here)
# Source 1 alone would call a `pull_request`-only workflow unsatisfiable on a push-only history.
# Source 2 alone cannot see a check produced by an app or an external service. Zero evidence from
# BOTH is `DID-NOT-RUN`, never a verdict — an empty producer set makes every context look broken,
# and the failure direction that matters here is the false ABORT: it costs a whole night.
#
# SATISFIABLE NEVER MEANS "WILL BE GREEN". Nothing at 21:00 can know whether tomorrow's markdown
# lints. That half belongs to the morning report's per-context reconciliation, not to a pre-flight.

set -u

SELF="required-checks-audit"
REPO=""; BRANCH="main"; ROOT="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   REPO="${2:-}";   shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --root)   ROOT="${2:-}";   shift 2 ;;
    *) printf '%s: unknown arg %s\n' "$SELF" "$1" >&2; exit 2 ;;
  esac
done

[ -n "$BRANCH" ] || { printf '%s: --branch requires a value\n' "$SELF" >&2; exit 2; }
[ -d "$ROOT" ]   || { printf '%s: --root is not a directory: %s\n' "$SELF" "$ROOT" >&2; exit 2; }

command -v gh >/dev/null 2>&1 \
  || { printf '%s: DID-NOT-RUN — gh CLI not found\n' "$SELF" >&2; exit 3; }
gh auth status >/dev/null 2>&1 \
  || { printf '%s: DID-NOT-RUN — gh is not authenticated\n' "$SELF" >&2; exit 3; }

if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
  [ -n "$REPO" ] || { printf '%s: DID-NOT-RUN — could not resolve the repo; pass --repo owner/name\n' "$SELF" >&2; exit 3; }
fi

# --- the required set ----------------------------------------------------------------------------
# 404 is a FACT ABOUT THE INPUT (this branch is not protected), not an error. Anything else that
# fails to parse is a fact about the environment and takes the DID-NOT-RUN path.
PROT=$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null)
PROT_RC=$?
if [ "$PROT_RC" != 0 ] || [ -z "$PROT" ]; then
  if gh api "repos/$REPO/branches/$BRANCH" >/dev/null 2>&1; then
    printf 'AUDIT: NO-PROTECTION — %s@%s has no branch protection; no status check blocks a merge\n' "$REPO" "$BRANCH"
    exit 0
  fi
  printf '%s: DID-NOT-RUN — could not read %s@%s (no such branch, or no permission)\n' "$SELF" "$REPO" "$BRANCH" >&2
  exit 3
fi

# Parse with jq — the same dependency set-branch-protection.sh already declares hard, for the same
# reason: a hand-rolled reader of this response is a second parser that can disagree with the one
# that WRITES the protection.
#
# `.contexts` is the legacy shape and `.checks[].context` the current one; GitHub returns both
# today, and reading only one would go silently empty the day it stops. An empty result from a
# PARSEABLE response is a real state (NO-REQUIRED-CHECKS); an unparseable response is not a state
# at all and must not reach the same branch.
command -v jq >/dev/null 2>&1 \
  || { printf '%s: DID-NOT-RUN — jq not found, and the protection response cannot be read without it\n' "$SELF" >&2; exit 3; }
if ! printf '%s' "$PROT" | jq -e . >/dev/null 2>&1; then
  printf '%s: DID-NOT-RUN — the protection response for %s@%s is not parseable JSON\n' "$SELF" "$REPO" "$BRANCH" >&2
  exit 3
fi
REQUIRED=$(printf '%s' "$PROT" | jq -r '
  (.required_status_checks // {}) as $r
  | (($r.contexts // []) + [ ($r.checks // [])[].context ])
  | map(select(. != null and . != ""))
  | unique
  | .[]' 2>/dev/null)

REQ_N=$(printf '%s\n' "$REQUIRED" | sed '/^$/d' | wc -l | tr -d ' ')
if [ "$REQ_N" -eq 0 ]; then
  printf 'AUDIT: NO-REQUIRED-CHECKS — %s@%s is protected but requires no status check\n' "$REPO" "$BRANCH"
  printf '  Nothing was verified. This is NOT "all satisfied": no context exists to satisfy.\n'
  exit 0
fi

# --- producer evidence, source 1: what actually ran on the branch HEAD ----------------------------
OBSERVED=$(gh api "repos/$REPO/commits/$BRANCH/check-runs" --jq '.check_runs[].name' 2>/dev/null \
           | sed '/^$/d' | sort -u)

# --- producer evidence, source 2: what the workflows declare --------------------------------------
# Job ids (a bare key at 2-space indent), job display names (`name:` at 4-space indent) and the
# workflow name itself. Step names sit at 6 spaces behind a dash and are deliberately NOT collected:
# a required context called `Checkout` must not be satisfied by every checkout step in the repo.
DECLARED=""
WF_DIR="$ROOT/.github/workflows"
if [ -d "$WF_DIR" ]; then
  for _wf in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do
    [ -f "$_wf" ] || continue
    DECLARED="$DECLARED
$(grep -E '^  [A-Za-z0-9][A-Za-z0-9_.-]*:[[:space:]]*$' "$_wf" 2>/dev/null | sed 's/^ *//; s/:[[:space:]]*$//')
$(grep -E '^    name:[[:space:]]*' "$_wf" 2>/dev/null | sed 's/^ *name:[[:space:]]*//; s/^"//; s/"$//')
$(grep -E '^name:[[:space:]]*' "$_wf" 2>/dev/null | sed 's/^name:[[:space:]]*//; s/^"//; s/"$//')"
  done
fi
DECLARED=$(printf '%s\n' "$DECLARED" | sed '/^$/d' | sort -u)

OBS_N=$(printf '%s\n' "$OBSERVED" | sed '/^$/d' | wc -l | tr -d ' ')
DEC_N=$(printf '%s\n' "$DECLARED" | sed '/^$/d' | wc -l | tr -d ' ')
if [ "$OBS_N" -eq 0 ] && [ "$DEC_N" -eq 0 ]; then
  printf '%s: DID-NOT-RUN — no producer evidence at all for %s@%s (no check-runs on HEAD, no\n' "$SELF" "$REPO" "$BRANCH" >&2
  printf '  workflow jobs under %s). Reporting every required context as unsatisfiable from an\n' "$WF_DIR" >&2
  printf '  empty producer set would abort a whole run on the strength of having looked nowhere.\n' >&2
  exit 3
fi

PRODUCERS=$(printf '%s\n%s\n' "$OBSERVED" "$DECLARED" | sed '/^$/d' | sort -u)

# --- the verdict ----------------------------------------------------------------------------------
MISSING=""
for _c in $(printf '%s\n' "$REQUIRED" | sed '/^$/d' | tr ' ' '\037'); do
  _ctx=$(printf '%s' "$_c" | tr '\037' ' ')
  printf '%s\n' "$PRODUCERS" | grep -qxF "$_ctx" || MISSING="$MISSING
$_ctx"
done
MISSING=$(printf '%s\n' "$MISSING" | sed '/^$/d')

# Advisory, never a gate: a producer that runs but is NOT required. The pre-flight's job is that
# PRs are mergeable, not that the gate is as strict as someone would like — but a human deciding
# what to require should be told, and this is the only place that knows both sets.
EXTRA=""
for _p in $(printf '%s\n' "$OBSERVED" | sed '/^$/d' | tr ' ' '\037'); do
  _pn=$(printf '%s' "$_p" | tr '\037' ' ')
  printf '%s\n' "$REQUIRED" | grep -qxF "$_pn" || EXTRA="$EXTRA
$_pn"
done
EXTRA=$(printf '%s\n' "$EXTRA" | sed '/^$/d')

if [ -n "$MISSING" ]; then
  printf 'AUDIT: UNSATISFIABLE — %s@%s requires %s context(s); these have no producer:\n' "$REPO" "$BRANCH" "$REQ_N"
  printf '%s\n' "$MISSING" | sed 's/^/  missing-producer: /'
  printf '  A PR will sit pending on these forever and cannot be merged. Evidence searched:\n'
  printf '    %s check-run(s) observed on %s HEAD, %s job identifier(s) in %s\n' "$OBS_N" "$BRANCH" "$DEC_N" "$WF_DIR"
  exit 1
fi

printf 'AUDIT: PASS — all %s required context(s) on %s@%s have a producer\n' "$REQ_N" "$REPO" "$BRANCH"
printf '%s\n' "$REQUIRED" | sed '/^$/d' | sed 's/^/  required: /'
if [ -n "$EXTRA" ]; then
  printf '  note: produced but NOT required (advisory, not a finding):\n'
  printf '%s\n' "$EXTRA" | sed 's/^/    not-required: /'
fi
exit 0
