#!/bin/bash
# step5-brief.sh v1.0 — per-batch dispatch brief materializer/verifier (VCS-057/ADR-0185, L1).
#
# CONTRACT — a CHECKER, not a reporter (unlike diff-budget-check.sh at the same layer): both modes
# share one exit-code convention, and the CALLER's fallback depends on distinguishing them —
#   0 — write mode: brief written to --out.      verify mode: coverage is exact, no findings.
#   1 — (verify mode only) coverage problem(s) found — GAP / OVERLAP / BOUNDARY-MISMATCH lines on
#       stdout, one or more.
#   2 — bad invocation (missing/unreadable required argument, a requested task that does not exist
#       in the plan, or a requested task set that is not a contiguous run of existing task numbers).
#   3 — DID-NOT-RUN (rule 4): the plan has zero task openers (write mode: malformed plan, nothing
#       to slice; verify mode: same, OR zero briefs under --briefs match this plan at all — an
#       unrun verification must not read as a clean pass). On exit 3 in WRITE mode, the caller (a
#       Step 5 dispatch site) falls back to today's full-file-read prompt and DECLARES the
#       fallback happened — this script does not decide that on its own, it only says why.
#
# WHY THIS EXISTS (VCS-057 plan, Fase 2 §L1). Measured 2026-08-31: PROJECT.md alone is ~37,600
# tokens, injected unconditionally into the Workflow dispatch prompt; separately, every dispatched
# tester/coder is told to unconditionally "Read plan at X. Read ADR at Y. Read SPEC.md at Z. Read
# project CLAUDE.md at W." before opening a single source file — the FULL plan and FULL companion
# docs, for a batch that only ever touches 2-3 of the plan's tasks. This script materializes, once
# per batch, a small brief carrying ONLY: (1) the byte-exact, contiguous slice of the plan text for
# this batch's tasks — never a paraphrase, so it cannot lose a constraint the way a summary would;
# (2) the union of files declared by those tasks' `Budget:` lines (via plan-budget-parse.awk,
# loaded, not restated — rule 6); (3) which OTHER tasks exist and are excluded from this batch,
# plus the plan's own path, for recovery when a task's constraint was misattributed; (4) the
# context documents (ADR/SPEC/project CLAUDE.md/DESIGN) as PATHS with a reason, no longer read
# unconditionally — the dispatched agent still has Read and can open one if the brief or its own
# judgement says so (rule 16: this half is instruction, not enforcement, and says so).
#
# WHAT IS ENFORCEMENT vs INSTRUCTION HERE, STATED EXPLICITLY (rule 16). The slice, the file-map
# union and the --verify coverage check are enforcement: shell, exit-coded, testable. "Read the
# brief, open the ADR only when the brief says so" is instruction: nothing stops a dispatched agent
# from reading the ADR anyway — the failure shape changes (an agent that ignores the brief pays the
# preamble cost again, quietly) but no guard here can catch that, and this comment says so instead
# of implying otherwise.
#
# DANGEROUS FAILURE MODE, AND WHY --verify EXISTS (VCS-057 plan). A brief that verifies "clean" —
# every task assigned to exactly one brief — but whose SLICE boundary is off by a line (an
# opener's start_line miscomputed) is invisible to a set-only check. --verify additionally
# recomputes each brief's TRUE line span from the plan directly and compares it to the span the
# brief declared in its own header, catching a boundary error that a coverage-by-task-number check
# alone would miss.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="step5-brief"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PREDICATE="$SCRIPT_DIR/plan-task-predicate.awk"
BUDGET_PARSER="$SCRIPT_DIR/plan-budget-parse.awk"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage:
  step5-brief.sh --plan <file> --tasks <N|N-M> --out <file>
                  [--adr-path <p>] [--adr-reason <r>]
                  [--spec-path <p>] [--spec-reason <r>]
                  [--claude-md-path <p>] [--claude-md-reason <r>]
                  [--design-path <p>] [--design-reason <r>]
  step5-brief.sh --verify --plan <file> --briefs <dir>

exit: 0 written / verify clean, 1 verify found gap|overlap|mismatch, 2 bad invocation,
3 did-not-run (malformed plan, or --verify found no briefs for this plan).
EOF
}

# --- real per-task (num, start_line) list, derived directly from the plan --------------------
# One shared derivation for both modes (rule 6): write mode uses it to slice and to validate the
# requested task set; verify mode uses it as the ground truth a brief's own header is checked
# against. Neither mode may recompute this differently from the other.
STARTS_AWK=$(mktemp) || { printf '%s: cannot create a temp file\n' "$SELF" >&2; exit 2; }
trap 'rm -f "$STARTS_AWK"' EXIT
cat >"$STARTS_AWK" <<'AWKEOF'
{ if (is_task_opener($0)) print task_num($0) "\t" NR }
AWKEOF

plan_task_starts() {
  # stdout: "<task_num>\t<start_line>", ONE ROW PER TASK NUMBER, ascending by start_line.
  # NEVER pass an inline awk PROGRAM STRING alongside -f: once -f is used, any further bare
  # argument is treated as a DATA FILE, not a program, and this call would silently process
  # nothing (measured live, VCS-057 -- this exact mistake cost a debugging round on the Fase 2 §1
  # corpus measurement earlier in this same effort). The one-line driver lives in its own -f file.
  #
  # A task number can legitimately open TWICE (VCS-057/ADR-0185, measured across the full corpus:
  # 66 of 672 opener lines). Every plan using the documented "Task checklist" index (a compact
  # `- [x] Task N -- ...` block near the top, scanned by concept-to-code/autopilot-build for
  # progress tracking) restates every task number there before its real `## Task N` heading
  # further down -- confirmed corpus-wide: the earlier occurrence is always within 5 lines of the
  # next task's earlier occurrence (the index block itself), never a genuine second block. The
  # LAST occurrence is therefore always the true content start; the dedup below keeps it and
  # discards the index restatement. This is distinct from a genuinely different task sharing a
  # numeric prefix ("Task 1b" vs "Task 1"), which plan-budget-parse.awk's task_num() now keeps as
  # its own key -- so this dedup never merges two real tasks, only an index line into its heading.
  awk -f "$PREDICATE" -f "$BUDGET_PARSER" -f "$STARTS_AWK" "$1" \
    | awk -F'\t' '{ln[$1]=$2} END{for (k in ln) print k "\t" ln[k]}' \
    | sort -t "$(printf '\t')" -k2,2n
}
plan_total_lines() { awk 'END{print NR}' "$1"; }

MODE="write"
PLAN=""; TASKS=""; OUT=""; BRIEFS_DIR=""
ADR_PATH=""; ADR_REASON=""; SPEC_PATH=""; SPEC_REASON=""
CLAUDE_MD_PATH=""; CLAUDE_MD_REASON=""; DESIGN_PATH=""; DESIGN_REASON=""

while [ $# -gt 0 ]; do
  case "$1" in
    --verify) MODE="verify"; shift ;;
    --plan) [ $# -ge 2 ] || { usage "--plan needs a file argument"; exit 2; }; PLAN="$2"; shift 2 ;;
    --tasks) [ $# -ge 2 ] || { usage "--tasks needs an argument"; exit 2; }; TASKS="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || { usage "--out needs a file argument"; exit 2; }; OUT="$2"; shift 2 ;;
    --briefs) [ $# -ge 2 ] || { usage "--briefs needs a directory argument"; exit 2; }; BRIEFS_DIR="$2"; shift 2 ;;
    --adr-path) ADR_PATH="${2:-}"; shift 2 ;;
    --adr-reason) ADR_REASON="${2:-}"; shift 2 ;;
    --spec-path) SPEC_PATH="${2:-}"; shift 2 ;;
    --spec-reason) SPEC_REASON="${2:-}"; shift 2 ;;
    --claude-md-path) CLAUDE_MD_PATH="${2:-}"; shift 2 ;;
    --claude-md-reason) CLAUDE_MD_REASON="${2:-}"; shift 2 ;;
    --design-path) DESIGN_PATH="${2:-}"; shift 2 ;;
    --design-reason) DESIGN_REASON="${2:-}"; shift 2 ;;
    *) usage "unknown argument: $1"; exit 2 ;;
  esac
done

[ -n "$PLAN" ] && [ -r "$PLAN" ] || { usage "--plan (readable file) is required — got [$PLAN]"; exit 2; }

# ================================================================================================
# --verify mode
# ================================================================================================
if [ "$MODE" = "verify" ]; then
  [ -n "$BRIEFS_DIR" ] && [ -d "$BRIEFS_DIR" ] || { usage "--briefs (readable directory) is required for --verify — got [$BRIEFS_DIR]"; exit 2; }

  TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; exit 2; }
  trap 'rm -rf "$TMPD" "$STARTS_AWK"' EXIT

  REAL_TASKS="$TMPD/real_tasks.tsv"
  plan_task_starts "$PLAN" >"$REAL_TASKS"
  N_TASKS=$(grep -c . "$REAL_TASKS" 2>/dev/null || true); [ -n "$N_TASKS" ] || N_TASKS=0
  if [ "$N_TASKS" -eq 0 ]; then
    printf 'DID-NOT-RUN: %s has no task openers (rule 4 -- an unrun check is not a clean result)\n' "$PLAN"
    exit 3
  fi
  TOTAL_LINES=$(plan_total_lines "$PLAN")

  # end_line[task] = next task's start_line - 1, or TOTAL_LINES for the last task.
  END_LINES="$TMPD/end_lines.tsv"
  awk -v total="$TOTAL_LINES" -F'\t' '
    { t[NR]=$1; s[NR]=$2; n=NR }
    END {
      for (i = 1; i <= n; i++) {
        e = (i < n) ? s[i+1] - 1 : total
        print t[i] "\t" s[i] "\t" e
      }
    }
  ' "$REAL_TASKS" >"$END_LINES"

  PLAN_REAL=$(cd "$(dirname "$PLAN")" && pwd)/$(basename "$PLAN")

  # Collect every brief in the directory whose header names this plan (by realpath).
  MATCHES="$TMPD/matches.txt"
  : >"$MATCHES"
  for _b in "$BRIEFS_DIR"/*; do
    [ -f "$_b" ] || continue
    _hdr=$(grep -m1 '^<!-- step5-brief: ' "$_b" 2>/dev/null) || continue
    printf '%s\n' "$_hdr" | grep -qF "plan=$PLAN_REAL " && printf '%s\t%s\n' "$_b" "$_hdr" >>"$MATCHES"
  done

  N_MATCHES=$(grep -c . "$MATCHES" 2>/dev/null || true); [ -n "$N_MATCHES" ] || N_MATCHES=0
  if [ "$N_MATCHES" -eq 0 ]; then
    printf 'DID-NOT-RUN: no brief under %s carries a header naming %s\n' "$BRIEFS_DIR" "$PLAN_REAL"
    exit 3
  fi

  FINDINGS="$TMPD/findings.txt"; : >"$FINDINGS"
  ASSIGN="$TMPD/assign.tsv"; : >"$ASSIGN"   # task_num<TAB>brief_file, one row per (brief, task)

  while IFS="$(printf '\t')" read -r _brief _hdr; do
    [ -n "$_brief" ] || continue
    _tasks_field=$(printf '%s\n' "$_hdr" | sed -n 's/.* tasks=\([^ ]*\) .*/\1/p')
    _lines_field=$(printf '%s\n' "$_hdr" | sed -n 's/.* lines=\([0-9]*-[0-9]*\) -->.*/\1/p')
    if [ -z "$_tasks_field" ] || [ -z "$_lines_field" ]; then
      printf 'BOUNDARY-MISMATCH\t%s\tmalformed header (tasks= or lines= missing/unparseable)\n' "$_brief" >>"$FINDINGS"
      continue
    fi
    _decl_start="${_lines_field%-*}"; _decl_end="${_lines_field#*-}"
    _oldifs="$IFS"; IFS=','; _tmin=""; _tmax=""
    for _t in $_tasks_field; do
      [ -n "$_t" ] || continue
      printf '%s\t%s\n' "$_t" "$_brief" >>"$ASSIGN"
      [ -z "$_tmin" ] || [ "$_t" -lt "$_tmin" ] 2>/dev/null && _tmin="$_t"
      [ -z "$_tmax" ] || [ "$_t" -gt "$_tmax" ] 2>/dev/null && _tmax="$_t"
    done
    IFS="$_oldifs"
    # Recompute the TRUE span for this brief's own declared task set and compare (the dangerous
    # failure mode: a brief whose coverage-by-task-number is exact but whose slice boundary,
    # taken from the real per-task lines, does not match what it says it wrote).
    _true_start=$(awk -F'\t' -v t="$_tmin" '$1==t{print $2}' "$END_LINES")
    _true_end=$(awk -F'\t' -v t="$_tmax" '$1==t{print $3}' "$END_LINES")
    if [ -z "$_true_start" ] || [ -z "$_true_end" ]; then
      printf 'BOUNDARY-MISMATCH\t%s\tdeclares task(s) not present in the plan (tasks=%s)\n' "$_brief" "$_tasks_field" >>"$FINDINGS"
    elif [ "$_true_start" != "$_decl_start" ] || [ "$_true_end" != "$_decl_end" ]; then
      printf 'BOUNDARY-MISMATCH\t%s\tdeclared lines=%s-%s, true span for tasks=%s is %s-%s\n' \
        "$_brief" "$_decl_start" "$_decl_end" "$_tasks_field" "$_true_start" "$_true_end" >>"$FINDINGS"
    fi
  done <"$MATCHES"

  # Exact set coverage: every real task assigned to exactly one brief.
  while IFS="$(printf '\t')" read -r _t _s _e; do
    [ -n "$_t" ] || continue
    _hits=$(awk -F'\t' -v t="$_t" '$1==t' "$ASSIGN" | grep -c . || true)
    if [ "${_hits:-0}" -eq 0 ]; then
      printf 'GAP\ttask %s\tnot covered by any brief (plan lines %s-%s)\n' "$_t" "$_s" "$_e" >>"$FINDINGS"
    elif [ "${_hits:-0}" -gt 1 ]; then
      _who=$(awk -F'\t' -v t="$_t" '$1==t{print $2}' "$ASSIGN" | paste -sd, -)
      printf 'OVERLAP\ttask %s\tcovered by %s briefs: %s\n' "$_t" "$_hits" "$_who" >>"$FINDINGS"
    fi
  done <"$END_LINES"

  if [ -s "$FINDINGS" ]; then
    cat "$FINDINGS"
    exit 1
  fi
  FIRST_START=$(head -1 "$END_LINES" | cut -f2)
  LAST_END=$(tail -1 "$END_LINES" | cut -f3)
  printf 'CLEAN: %s brief(s) cover all %s task(s) (lines %s-%s), no gaps, no overlaps, no boundary mismatch\n' \
    "$N_MATCHES" "$N_TASKS" "$FIRST_START" "$LAST_END"
  exit 0
fi

# ================================================================================================
# write mode
# ================================================================================================
[ -n "$TASKS" ] || { usage "--tasks is required"; exit 2; }
[ -n "$OUT" ] || { usage "--out is required"; exit 2; }

TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; exit 2; }
trap 'rm -rf "$TMPD" "$STARTS_AWK"' EXIT

REAL_TASKS="$TMPD/real_tasks.tsv"
plan_task_starts "$PLAN" >"$REAL_TASKS"
N_TASKS=$(grep -c . "$REAL_TASKS" 2>/dev/null || true); [ -n "$N_TASKS" ] || N_TASKS=0
if [ "$N_TASKS" -eq 0 ]; then
  printf 'DID-NOT-RUN: %s has no task openers -- falling back to the full-plan prompt\n' "$PLAN" >&2
  exit 3
fi
TOTAL_LINES=$(plan_total_lines "$PLAN")

END_LINES="$TMPD/end_lines.tsv"
awk -v total="$TOTAL_LINES" -F'\t' '
  { t[NR]=$1; s[NR]=$2; n=NR }
  END {
    for (i = 1; i <= n; i++) {
      e = (i < n) ? s[i+1] - 1 : total
      print t[i] "\t" s[i] "\t" e
    }
  }
' "$REAL_TASKS" >"$END_LINES"

# --tasks: a single number ("3") or a range ("3-5"). No comma lists -- a brief is one contiguous
# slice by construction (VCS-057 plan: "byte-esatta e contigua"), and a non-contiguous request
# would either force a multi-slice brief (defeating the single-slice invariant --verify checks)
# or silently include an unrequested task's text in the gap. Refused, not worked around.
case "$TASKS" in
  *,*)
    usage "--tasks must be a single number or a contiguous range (N or N-M), not a comma list: $TASKS"
    exit 2 ;;
  *-*)
    REQ_LO="${TASKS%%-*}"; REQ_HI="${TASKS##*-}"
    case "$REQ_LO" in ''|*[!0-9]*) usage "--tasks range must be numeric: $TASKS"; exit 2 ;; esac
    case "$REQ_HI" in ''|*[!0-9]*) usage "--tasks range must be numeric: $TASKS"; exit 2 ;; esac
    [ "$REQ_LO" -le "$REQ_HI" ] || { usage "--tasks range is backwards: $TASKS"; exit 2; } ;;
  *)
    case "$TASKS" in ''|*[!0-9]*) usage "--tasks must be numeric: $TASKS"; exit 2 ;; esac
    REQ_LO="$TASKS"; REQ_HI="$TASKS" ;;
esac

# Every requested task number must exist in the plan, and the two boundary numbers must both
# resolve -- existence of every integer in between is then guaranteed by construction (the slice
# is built from REQ_LO's start_line to REQ_HI's end_line, which by definition spans exactly the
# tasks the plan itself places between them; a plan with a genuinely missing task number in that
# span would silently pull in unrequested text, which is why REQ_LO and REQ_HI resolving is the
# gate, not merely "the plan is well-formed" -- see step5-brief.test.sh SB-gap for the case where
# this matters).
START_LINE=$(awk -F'\t' -v t="$REQ_LO" '$1==t{print $2}' "$END_LINES")
END_LINE=$(awk -F'\t' -v t="$REQ_HI" '$1==t{print $3}' "$END_LINES")
if [ -z "$START_LINE" ]; then usage "task $REQ_LO does not exist in $PLAN"; exit 2; fi
if [ -z "$END_LINE" ]; then usage "task $REQ_HI does not exist in $PLAN"; exit 2; fi

# Reject a requested span containing a gap in the plan's own task numbering (rare, but a silent
# over-include is worse than a refusal -- rule 7's denominator discipline applied to a range).
#
# A letter-suffixed task ("Task 1b", "Task 4d" -- measured: 2 of 79 corpus plans) sits BETWEEN two
# integers and awk's numeric coercion of its string key ("1b" -> 1) puts it inside any range
# straddling it, inflating _gap past _expected. This is the SAME refusal as a real numbering hole
# in the plan -- neither case may silently mis-slice -- but the two causes read very differently to
# whoever gets this message, so the letter-suffixed case is named explicitly instead of reported as
# an undifferentiated "not contiguous" (rule 3: a clause must say what it means, not make the reader
# re-derive it).
_present=$(awk -F'\t' -v lo="$REQ_LO" -v hi="$REQ_HI" '$1>=lo && $1<=hi {print $1}' "$REAL_TASKS")
_gap=$(printf '%s\n' "$_present" | grep -c . || true)
_expected=$((REQ_HI - REQ_LO + 1))
if [ "$_gap" -ne "$_expected" ]; then
  _lettered=$(printf '%s\n' "$_present" | awk '/[A-Za-z]$/{print}' | paste -sd, -)
  if [ -n "$_lettered" ]; then
    usage "tasks $REQ_LO-$REQ_HI in $PLAN also span task(s) $_lettered, which sit between $REQ_LO and $REQ_HI but are not integers -- a single --tasks N|N-M request cannot include or skip them; request $REQ_LO, $_lettered and $REQ_HI as separate briefs"
  else
    usage "tasks $REQ_LO-$REQ_HI are not a contiguous run in $PLAN ($_gap of $_expected task numbers present)"
  fi
  exit 2
fi

PLAN_REAL=$(cd "$(dirname "$PLAN")" && pwd)/$(basename "$PLAN")

# --- (1) byte-exact, contiguous slice --------------------------------------------------------
SLICE=$(sed -n "${START_LINE},${END_LINE}p" "$PLAN")

# --- (2) union of Budget: files declared by the requested tasks, via the loaded parser -------
BUDGET_FILE="$TMPD/budget.tsv"; : >"$BUDGET_FILE"
MALFORMED_FILE="$TMPD/malformed.tsv"; : >"$MALFORMED_FILE"
cat >"$TMPD/collect.awk" <<'AWKEOF'
BEGIN { in_task = 0; cur = ""; got = 0 }
{
  line = $0
  if (is_task_opener(line)) {
    cur = task_num(line)
    got = 0
    in_task = (cur + 0 >= LO && cur + 0 <= HI)
    next
  }
  if (in_task && !got) {
    if (match(line, /[Bb]udget:/)) {
      rest = trim(substr(line, RSTART + RLENGTH))
      parsed = parse_budget(rest)
      if (parsed != "") {
        print cur "\t" parsed >> BUDGET_FILE
        got = 1
      } else if (looks_like_budget(rest)) {
        print cur "\t" rest >> MALFORMED_FILE
        got = 1
      }
    }
  }
}
AWKEOF
awk -v BUDGET_FILE="$BUDGET_FILE" -v MALFORMED_FILE="$MALFORMED_FILE" -v LO="$REQ_LO" -v HI="$REQ_HI" \
    -f "$PREDICATE" -f "$BUDGET_PARSER" -f "$TMPD/collect.awk" "$PLAN"

FILE_MAP="$TMPD/file_map.txt"; : >"$FILE_MAP"
while IFS="$(printf '\t')" read -r _t _files _lines; do
  [ -n "$_files" ] || continue
  _oldifs="$IFS"; IFS=','
  for _f in $_files; do
    _f=$(printf '%s' "$_f" | awk '{gsub(/^[ \t]+|[ \t]+$/,""); print}')
    [ -n "$_f" ] && printf '%s\n' "$_f" >>"$FILE_MAP"
  done
  IFS="$_oldifs"
done <"$BUDGET_FILE"
FILE_MAP_UNIQ=$(sort -u "$FILE_MAP" 2>/dev/null)

# Which requested tasks declared no parseable budget (informational -- absent is never zero, §D6).
BUDGETED_NUMS="$TMPD/budgeted_nums.txt"
cut -f1 "$BUDGET_FILE" >"$BUDGETED_NUMS" 2>/dev/null || : >"$BUDGETED_NUMS"
NO_BUDGET=""
_t="$REQ_LO"
while [ "$_t" -le "$REQ_HI" ]; do
  grep -qxF "$_t" "$BUDGETED_NUMS" 2>/dev/null || NO_BUDGET="$NO_BUDGET $_t"
  _t=$((_t + 1))
done

# --- (3) excluded tasks: every OTHER task the plan declares -----------------------------------
EXCLUDED=$(awk -F'\t' -v lo="$REQ_LO" -v hi="$REQ_HI" '!(($1+0)>=lo && ($1+0)<=hi){print $1}' "$REAL_TASKS")

# --- write the brief ---------------------------------------------------------------------------
{
  # NEVER `seq -s,`: BSD seq (macOS) appends a TRAILING separator ("1,2," not "1,2"), which would
  # corrupt this machine-readable header's tasks= field for every --verify parse downstream. The
  # awk loop is the only form that has been checked on both BSD and GNU seq's actual output.
  printf '<!-- step5-brief: plan=%s tasks=%s lines=%s-%s -->\n' \
    "$PLAN_REAL" "$(awk -v lo="$REQ_LO" -v hi="$REQ_HI" 'BEGIN{s="";for(i=lo;i<=hi;i++) s=(s==""?i:s","i); print s}')" \
    "$START_LINE" "$END_LINE"
  printf '# Step 5 Batch Brief -- %s -- tasks %s-%s\n\n' "$(basename "$PLAN")" "$REQ_LO" "$REQ_HI"

  printf '## Task text (verbatim, plan lines %s-%s)\n\n' "$START_LINE" "$END_LINE"
  printf '%s\n\n' "$SLICE"

  printf '## File map (from Budget: declarations, tasks %s-%s)\n\n' "$REQ_LO" "$REQ_HI"
  if [ -n "$FILE_MAP_UNIQ" ]; then
    printf '%s\n' "$FILE_MAP_UNIQ" | while IFS= read -r _f; do [ -n "$_f" ] && printf -- '- %s\n' "$_f"; done
  else
    printf -- '- (none declared -- no task in this range carries a parseable Budget:)\n'
  fi
  if [ -n "$NO_BUDGET" ]; then
    printf '\nNo parseable Budget: for task(s):%s (absent is not zero -- consult the task text above)\n' "$NO_BUDGET"
  fi
  printf '\n'

  printf '## Excluded tasks (not in this batch)\n\n'
  if [ -n "$EXCLUDED" ]; then
    printf '%s\n' "$EXCLUDED" | while IFS= read -r _e; do [ -n "$_e" ] && printf -- '- Task %s -- see %s\n' "$_e" "$PLAN_REAL"; done
  else
    printf -- '- (none -- this batch is the whole plan)\n'
  fi
  printf '\nFull plan: %s\n\n' "$PLAN_REAL"

  printf '## Context documents (open only for the reason stated -- not read unconditionally)\n\n'
  [ -n "$ADR_PATH" ] && printf -- '- ADR: %s -- %s\n' "$ADR_PATH" "${ADR_REASON:-(no reason given)}"
  [ -n "$SPEC_PATH" ] && printf -- '- SPEC: %s -- %s\n' "$SPEC_PATH" "${SPEC_REASON:-(no reason given)}"
  [ -n "$CLAUDE_MD_PATH" ] && printf -- '- CLAUDE.md: %s -- %s\n' "$CLAUDE_MD_PATH" "${CLAUDE_MD_REASON:-(no reason given)}"
  [ -n "$DESIGN_PATH" ] && printf -- '- DESIGN: %s -- %s\n' "$DESIGN_PATH" "${DESIGN_REASON:-(no reason given)}"
  if [ -z "$ADR_PATH$SPEC_PATH$CLAUDE_MD_PATH$DESIGN_PATH" ]; then
    printf -- '- (none passed to this brief)\n'
  fi
} >"$OUT"

exit 0
