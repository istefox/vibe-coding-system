#!/bin/bash
# plan-tasks.sh v1.0 — count the tasks in an implementation plan (issue #172; ADR-0069 §D3).
#
# CONTRACT. This is a CHECKER: the caller branches on the printed count and on the exit code.
# It is NOT a reporter. The two scripts invoked beside it at the same Step 5 checkpoint —
# weakening-scan.sh (ADR-0047) and diff-budget-check.sh (ADR-0052) — always exit 0 and signal
# through stdout only, printing the sentinel CLEAN when they have nothing. Do not copy one
# block's branching into the other. ADR-0048 §D7 had to write that sentence once for
# spec-coverage.sh, which shares this script's contract; this is the second script in this
# directory to need it.
#
#   stdout: exactly one integer, the number of task lines found. Nothing else, ever.
#   stderr: nothing on success.
#   exit 0  the plan was read and counted (the count may legitimately be 0)
#   exit 2  bad invocation, or the plan file is missing/unreadable
#   exit 3  awk could not run the predicate — the check DID NOT RUN
#
# Exit 3 exists for the reason secret-scan.sh has one: a check that reports nothing must be
# distinguishable from a check that finds nothing. Without it a broken awk would print 0 and every
# caller would conclude "no tasks" and abort, blaming the plan — which is precisely the failure
# #172 was filed about, reproduced one level down.
#
# WHAT THE COUNT MEANS, AND WHAT IT DOES NOT. Nothing in the chain ever writes `[x]` back into a
# plan file (task completion lives in step5-report.json as tasks_completed), so this is NOT a count
# of PENDING work and the plan's checkboxes are always unchecked. It answers "does this file
# contain any task at all" — a malformed-plan guard. The predicate is deliberately loose and
# over-counts (see plan-task-predicate.awk): a `## Tasks` section heading counts, a checkbox
# sub-step inside a task counts. Use this for a `>= 1` guard. Do not use the number as a task
# count, and do not use it to delimit a task block — issue #184 is what that needs.
#
# --count-openers IS THAT SECOND ANSWER (issue #242, ADR-0100). It exposes is_task_opener(), which
# ADR-0070 added to the shared predicate for exactly this distinction: "is there a task here"
# versus "does a task BLOCK START here". Measured over the 62 plans in docs/superpowers/plans/
# (re-measured 2026-08-03, ADR-0121), the two answers differ on 53, and every one of those 53 is
# >= 6 and over-counted — so a caller that batches by ranges gets ranges over tasks that do not
# exist. On #222's plan: 38 lines, 7 openers.
#
# --count-openers returns 0 on two corpus plans, not three shapes — `deep-refactor-skill.md`
# (`### T1 —`) and `claude-md-slim.md` (`### Step N —`, whose first heading is `### Step 0 —`),
# exempted by name in ADR-0070 §PTG9 and ADR-0069 §PTE2. THE TWO MODES ARE NOT INTERCHANGEABLE IN
# EITHER DIRECTION — see the mode-contract table below for which question each one answers and why.
#
# THE TABLE BELOW IS THE BINDING, not this header's prose. The paragraphs above describe the two
# modes; the table decides which question each one answers, and mode-binding-check.sh compares
# every call site against these two lines only — never against this prose (issue #294, ADR-0131
# §D2). If you need this somewhere new, load the table: do not paste the answer, the same rule
# ADR-0069 §D2 already applies to the predicate itself.
# mode-contract: --count | guard | over-counts by design (a `## Tasks` heading and every checkbox sub-step match): safe for a `>= 1` malformed-plan guard, wrong for arithmetic.
# mode-contract: --count-openers | arithmetic | returns 0 on the two corpus plans naming tasks another word: safe for arithmetic that tests for zero, wrong for a guard.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="plan-tasks"
PRED_DIR=$(cd "$(dirname "$0")" && pwd)
PREDICATE="$PRED_DIR/plan-task-predicate.awk"
# task_num() is loaded for --count-openers only (VCS-057/ADR-0185, issue found while building
# step5-brief.sh) -- see the CORRECTION note above --count-openers's own header for why.
BUDGET_PARSER="$PRED_DIR/plan-budget-parse.awk"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: plan-tasks.sh --count <plan-file>
       plan-tasks.sh --count-openers <plan-file>

--count          one integer: task LINES, the loose predicate. For a `>= 1` malformed-plan guard.
--count-openers  one integer: task BLOCK OPENERS, the strict predicate. For anything that batches,
                 ranges or attributes content to a task. See ADR-0069 §D1 for the forms.

Exit: 0 counted | 2 bad invocation or unreadable plan | 3 awk could not run the predicate.
EOF
  exit 2
}

PLAN=""
MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --count) MODE="count"; shift; [ $# -gt 0 ] || usage "--count needs a plan file"; PLAN="$1"; shift ;;
    --count-openers) MODE="openers"; shift; [ $# -gt 0 ] || usage "--count-openers needs a plan file"; PLAN="$1"; shift ;;
    -h|--help) usage "" ;;
    *) usage "unknown argument: $1" ;;
  esac
done

[ "$MODE" = "count" ] || [ "$MODE" = "openers" ] || usage "missing --count or --count-openers <plan-file>"
[ -n "$PLAN" ] || usage "a plan file is required"
[ -f "$PLAN" ] && [ -r "$PLAN" ] || { printf '%s: plan not found or unreadable: %s\n' "$SELF" "$PLAN" >&2; exit 2; }
[ -f "$PREDICATE" ] && [ -r "$PREDICATE" ] || { printf '%s: predicate not found: %s\n' "$SELF" "$PREDICATE" >&2; exit 3; }
if [ "$MODE" = "openers" ]; then
  [ -f "$BUDGET_PARSER" ] && [ -r "$BUDGET_PARSER" ] || { printf '%s: budget parser not found: %s\n' "$SELF" "$BUDGET_PARSER" >&2; exit 3; }
fi

# The predicate is loaded, never restated (ADR-0069 §D2). `-f` composition is what lets
# spec-coverage.sh share this exact file without restructuring its heredoc-built program.
# The counting half goes to a temp file rather than /dev/stdin: spec-coverage.sh in this same
# directory builds its awk program the same way, and a named file works on every awk this repo
# targets.
TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; exit 3; }
trap 'rm -rf "$TMPD"' EXIT
if [ "$MODE" = "openers" ]; then
  # Counts DISTINCT task designations (task_num()), not opener LINES (VCS-057/ADR-0185
  # correction, dated 2026-08-31 -- see the header above, this does not rewrite the 2026-08-03
  # measurement, it corrects forward per rule 14). A plan using the documented "Task checklist"
  # index -- a compact `- [x] Task N -- ...` block restating every task before its real
  # `## Task N` heading -- satisfies is_task_opener() TWICE per task, once per form; a bare line
  # count reports 18 openers on a 9-task plan (hook-hardening.md, measured). seen[] collapses
  # that to one count per task_num(), which is what every arithmetic caller (the >=6-task batch
  # split, this script's own header) actually needs.
  cat >"$TMPD/count.awk" <<'AWKEOF'
{ if (is_task_opener($0)) seen[task_num($0)] = 1 }
END { n = 0; for (k in seen) n++; print n + 0 }
AWKEOF
  AWK_ARGS=(-f "$PREDICATE" -f "$BUDGET_PARSER" -f "$TMPD/count.awk")
else
  cat >"$TMPD/count.awk" <<'AWKEOF'
{ if (is_task_line($0)) n++ }
END { print n + 0 }
AWKEOF
  AWK_ARGS=(-f "$PREDICATE" -f "$TMPD/count.awk")
fi
# The awk-failed exit-3 branch is SHARED by both modes (one line, not two -- PTK9, rule 6): a
# second copy of this identical text broke PTK9's single-match plant contract when the openers
# mode's own extra -f argument was first added here (VCS-057/ADR-0185, dated 2026-08-31).
N=$(awk "${AWK_ARGS[@]}" "$PLAN" 2>/dev/null) \
  || { printf '%s: awk failed on %s — the check did not run\n' "$SELF" "$PLAN" >&2; exit 3; }

# A non-integer means awk produced something other than the count: treat as did-not-run rather
# than printing garbage a caller would compare numerically (the `0\n0` lesson, issue #174).
case "$N" in
  ''|*[!0-9]*) printf '%s: awk produced a non-integer result on %s — the check did not run\n' "$SELF" "$PLAN" >&2; exit 3 ;;
esac

printf '%s\n' "$N"
