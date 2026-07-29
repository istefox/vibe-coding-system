#!/bin/bash
# diff-budget-check.sh v1.0 — per-task diff budget and scope REPORTER (issue #106; ADR-0052).
#
# CONTRACT. This is a REPORTER, matching weakening-scan.sh at the same Step 5 checkpoint — NOT
# spec-coverage.sh in the same directory, which is a CHECKER (exit code is the policy channel).
# This script ALWAYS exits 0. It signals through stdout only, and prints the sentinel CLEAN when
# there is nothing to report. Do not copy one block's branching into the other (ADR-0048 §D7
# already had to write that sentence once; restated here for the third time in this directory).
#   BUDGET<TAB><tasks-label><TAB>files=<expected>/<actual><TAB>lines=<expected>/<actual><TAB>margin=<N>
#   SCOPE<TAB><file>
# Caller idiom: never `[ -n "$out" ]` to decide whether something was found — true even on a bare
# CLEAN. Never `n=$(... | grep -c '^BUDGET' || echo 0)` — grep -c prints 0 AND exits 1 on no
# match, so the fallback also fires and the substitution yields the two-line string "0\n0"; use
# `|| true` if a count is needed.
#
# BACKWARD COMPATIBILITY IS THE HARD GATE (ADR-0052 §D1, §D4). Thirty-plus plans in
# docs/superpowers/plans/ predate this feature and declare no budget on any task. Such a plan MUST
# be genuinely silent — not one BUDGET-free run that still emits SCOPE noise. The failure mode
# that matters: if the "declared scope" set were allowed to be empty while still being enforced,
# every file touched by every legacy plan would be reported out-of-scope. So the SCOPE check
# activates for a plan ONLY IF at least one task anywhere in the WHOLE PLAN declares a parseable
# budget. A plan with zero budgeted tasks is inert end to end — this is D1's "a plan task without
# one is not a defect" extended to the whole-plan level for D4's scope check.
#
# BUDGET SYNTAX (§D6 — lenient prose, not a rigid schema). Anywhere within a task's block (from a
# "- [ ] **Task N — ...**" line up to the next such line, or EOF, INCLUDING the heading line
# itself — the form this repository's own plans actually use is one dense bullet, not a separate
# sub-line), the first occurrence of the case-insensitive substring "Budget:" is parsed as:
#   Budget: <file>[, <file>...] (<~|±><N> line[s])
# The sign is optional and ignored; "line"/"lines" both accepted. BOTH halves — the file list AND
# the parenthesised line ceiling — must be present and well-formed TOGETHER. A "Budget:" line that
# does not fit this shape produces NO budget for that task (§D6/§C: unparseable is absent, never
# zero — a strict parser defaulting a missing count to 0 would flag every file the task touches as
# an overshoot on a simple formatting slip).
#
# PLAN-LEVEL SCOPE DECLARATION (§D4's exclusion for cross-cutting work). A line anywhere BEFORE
# the first task block, case-insensitive substring "Scope:":
#   Scope: <glob>[, <glob>...]
# A touched file matching one of these globs is treated as in-scope regardless of any single
# task's declared file list. Glob matching is a plain shell `case` pattern — `*` already matches
# across `/` there (no globstar needed), the same real-glob-semantics choice ADR-0031's
# enumerate-sources.sh made for the same reason.
#
# EXCLUSIONS (§D4), applied by basename before EITHER computation — files the chain itself
# writes, never a coder's own work: SPEC.md, step5-report.json, and any *.manifest.yml
# (docs/manifests/<date>-<slug>.manifest.yml, per manifest-init.sh's
# `docs/manifests/$today-$slug.manifest.yml` assignment).
#
# CHECKPOINT SEMANTICS (§D2). Step 5 has no commit boundary between task groups/batches — nothing
# is committed until Step 7 — so there is no git-level way to isolate "this batch's diff" from
# "everything since Step 5 began". The anti-test-weakening gate (ADR-0047) already resolved this
# by re-scanning the CUMULATIVE diff since the Step 5 baseline at every checkpoint; this script's
# caller does the same (git diff --stat "$_pre5"), and sums the budgets of every task DISPATCHED
# SO FAR (via --tasks), not just the tasks in the checkpoint that just closed. Documented at the
# call site in concept-to-code/SKILL.md, not just here.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="diff-budget-check"

# The plan-task predicate is LOADED, not restated (ADR-0069 §D2, ADR-0070 §D2). This script carried
# the fourth private copy in the repository and the strictest of them: `- [ ] **Task N`, which
# matched 18 of 57 real plans and none of the heading-form ones, so this check had never produced a
# finding on a real plan.
PREDICATE=$(cd "$(dirname "$0")" && pwd)/plan-task-predicate.awk

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: diff-budget-check.sh --plan <file> --tasks <task-spec> < git-diff---stat-output

task-spec: a single task number ("3"), a comma list ("1,2,3"), or a range ("1-3").
stdout: CLEAN, or one or more BUDGET / SCOPE lines (TAB-separated). Always exits 0 — this is a
REPORTER, not a checker. A bad invocation still exits 0 and prints CLEAN (fail-open).
EOF
}

PLAN=""; TASKS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plan)
      [ $# -ge 2 ] || { usage "--plan needs a file argument"; echo CLEAN; exit 0; }
      PLAN="$2"; shift 2 ;;
    --tasks)
      [ $# -ge 2 ] || { usage "--tasks needs an argument"; echo CLEAN; exit 0; }
      TASKS="$2"; shift 2 ;;
    *)
      usage "unknown argument: $1"; echo CLEAN; exit 0 ;;
  esac
done

if [ -z "$PLAN" ] || [ -z "$TASKS" ] || [ ! -r "$PLAN" ]; then
  usage "--plan (readable file) and --tasks are both required — got PLAN=[$PLAN] TASKS=[$TASKS]"
  echo CLEAN
  exit 0
fi

TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; echo CLEAN; exit 0; }
trap 'rm -rf "$TMPD"' EXIT

BUDGET_FILE="$TMPD/budget.tsv";  : >"$BUDGET_FILE"
SCOPE_GLOBS="$TMPD/scope_globs.txt"; : >"$SCOPE_GLOBS"

# --- plan parser: per-task Budget: (files, line ceiling), whole-plan Scope: globs -----------------
cat >"$TMPD/plan_parse.awk" <<'AWKEOF'
# is_task_opener() comes from plan-task-predicate.awk, loaded alongside this program (ADR-0070
# §D2) — do not redefine it here. This parser needs the BLOCK-OPENER question, not the looser
# is_task_line() in the same file: a checkbox sub-step mentioning a task must not close the
# previous task's block and steal its Budget.
function trim(s) { gsub(/^[ \t]+/,"",s); gsub(/[ \t]+$/,"",s); return s }
function task_num(l,   t) {
  match(l, /Task[ \t]+[0-9]+/)
  t = substr(l, RSTART, RLENGTH)
  gsub(/[^0-9]/, "", t)
  return t
}
BEGIN { in_task = 0; cur = ""; got = 0 }
{
  line = $0
  if (is_task_opener(line)) {
    cur = task_num(line)
    got = 0
    in_task = 1
  } else if (!in_task) {
    if (match(line, /[Ss]cope:/)) {
      sc = trim(substr(line, RSTART + RLENGTH))
      n = split(sc, parts, ",")
      for (i = 1; i <= n; i++) {
        p = trim(parts[i])
        gsub(/`/, "", p)
        if (p != "") print p >> SCOPE_FILE
      }
    }
    next
  }
  if (in_task && !got) {
    if (match(line, /[Bb]udget:/)) {
      rest = trim(substr(line, RSTART + RLENGTH))
      # Trailing markdown emphasis is tolerated: a real plan writes the whole declaration in
      # italics — `*Budget: `SPEC.md` (~90 lines)*` — and requiring the paren group at strict
      # end-of-line rejected every declaration in the only plan in the corpus that has any
      # (ADR-0070 §D4). §D6 of ADR-0052 already calls this syntax "lenient prose, not a rigid
      # schema"; this is that intent applied, not a widening of it.
      if (match(rest, /\([^()]*\)[ \t]*[*_`]*[ \t]*$/)) {
        parenraw = substr(rest, RSTART, RLENGTH)
        filespart = trim(substr(rest, 1, RSTART - 1))
        sub(/,[ \t]*$/, "", filespart)
        gsub(/`/, "", filespart)
        inner = parenraw
        gsub(/[()]/, "", inner)
        lowinner = tolower(inner)
        if (filespart != "" && match(inner, /[0-9]+/) && index(lowinner, "line") > 0) {
          numval = substr(inner, RSTART, RLENGTH)
          print cur "\t" filespart "\t" numval >> BUDGET_FILE
          got = 1
        }
      }
    }
  }
}
AWKEOF

awk -v BUDGET_FILE="$BUDGET_FILE" -v SCOPE_FILE="$SCOPE_GLOBS" \
    -f "$PREDICATE" -f "$TMPD/plan_parse.awk" "$PLAN"

# --- whole-plan inert check (§D1/§D4): no task anywhere declared a parseable budget --------------
if [ ! -s "$BUDGET_FILE" ]; then
  echo CLEAN
  exit 0
fi

# --- master declared-scope file set (union of every task's declared file list) -------------------
MASTER_SCOPE="$TMPD/master_scope.txt"; : >"$MASTER_SCOPE"
while IFS="$(printf '\t')" read -r _t _files _lines; do
  [ -n "$_files" ] || continue
  _oldifs="$IFS"; IFS=','
  for _f in $_files; do
    _f=$(printf '%s' "$_f" | awk '{gsub(/^[ \t]+|[ \t]+$/,""); print}')
    [ -n "$_f" ] && printf '%s\n' "$_f" >>"$MASTER_SCOPE"
  done
  IFS="$_oldifs"
done <"$BUDGET_FILE"

# --- expand --tasks into an explicit task-number set, and sum the declared budgets in it ---------
expand_tasks() {
  _arg="$1"
  _oldifs="$IFS"; IFS=','
  for _part in $_arg; do
    case "$_part" in
      *-*)
        _lo="${_part%%-*}"; _hi="${_part##*-}"
        _i="$_lo"
        while [ "$_i" -le "$_hi" ] 2>/dev/null; do
          printf '%s\n' "$_i"
          _i=$((_i + 1))
        done
        ;;
      *)
        printf '%s\n' "$_part"
        ;;
    esac
  done
  IFS="$_oldifs"
}

TASK_SET="$TMPD/task_set.txt"
expand_tasks "$TASKS" >"$TASK_SET"

FILES_EXPECTED=0
LINES_EXPECTED=0
BUDGET_LIVE=0
while IFS="$(printf '\t')" read -r _t _files _lines; do
  [ -n "$_t" ] || continue
  grep -qxF "$_t" "$TASK_SET" 2>/dev/null || continue
  BUDGET_LIVE=1
  _n=$(printf '%s' "$_files" | awk -F',' '{print NF}')
  FILES_EXPECTED=$((FILES_EXPECTED + _n))
  LINES_EXPECTED=$((LINES_EXPECTED + _lines))
done <"$BUDGET_FILE"

# --- consume stdin (git diff --stat output), excluding chain-owned files by basename -------------
STAT_IN="$TMPD/stat_in.txt"
cat >"$STAT_IN"

CANDIDATES="$TMPD/candidates.tsv"
awk '
function basename(p,   n, a) { n = split(p, a, "/"); return a[n] }
{
  line = $0
  p = index(line, " | ")
  if (p <= 1) next
  path = substr(line, 2, p - 2)
  gsub(/[ \t]+$/, "", path)  # git pads the path column to align "|" across differently-named files
  rest = substr(line, p + 3)
  # git RIGHT-ALIGNS the count column, so every file whose count has fewer digits than the widest
  # one in the diff carries leading spaces here. Without this strip the `^[0-9]+` match fails and
  # the file is dropped from the candidate set entirely — no SCOPE finding, and its lines missing
  # from the BUDGET total. Silently, and for most files in any diff with a mixed range of sizes
  # (ADR-0070 §D6). Found by running the checker on a real two-file diff, not by reading it.
  sub(/^[ \t]+/, "", rest)
  if (!match(rest, /^[0-9]+/)) next
  cnt = substr(rest, RSTART, RLENGTH)
  bn = basename(path)
  if (bn == "SPEC.md" || bn == "step5-report.json") next
  if (bn ~ /\.manifest\.yml$/) next
  print path "\t" cnt
}
' "$STAT_IN" >"$CANDIDATES"

# --- SCOPE partition FIRST (§D4): an out-of-scope file is its own finding type and must never
# also inflate the BUDGET totals below — conflating the soft (overshoot) signal with the firm
# (undeclared file) one degrades the firm one, the same reasoning ADR-0051 §D2 used to keep
# SUSPECT out of WEAKENED. So files_actual/lines_actual for the BUDGET check are computed ONLY
# from files that pass the scope check (declared by some task, or matched by a plan-level Scope:
# glob) — an out-of-scope file is reported once, as SCOPE, and never double-counted as overshoot.
glob_match() {
  _path="$1"
  [ -s "$SCOPE_GLOBS" ] || return 1
  while IFS= read -r _g; do
    [ -n "$_g" ] || continue
    case "$_path" in
      $_g) return 0 ;;
    esac
  done <"$SCOPE_GLOBS"
  return 1
}

OUT="$TMPD/out.txt"; : >"$OUT"

FILES_ACTUAL=0
LINES_ACTUAL=0
while IFS="$(printf '\t')" read -r _path _cnt; do
  [ -n "$_path" ] || continue
  # `git diff --stat` ELIDES a long path to `.../tail/of/it` when the stat table exceeds its width
  # (80 columns in a pipe). Measured on this repository: a 63-character path is truncated as soon as
  # a second file shares the table. An elided name matches nothing, so it would be reported
  # out-of-scope AND its lines would go uncounted — wrong in both directions at once (ADR-0070 §D5).
  # Callers are fixed to pass `--stat=999`; this recovers the case where one does not, by resolving
  # the tail against the declared set. Ambiguous tails are left elided and reported, because a
  # guess here would be worse than the finding.
  _lookup="$_path"
  case "$_path" in
    .../*)
      _sfx="${_path#.../}"
      # sort -u, not a raw count: MASTER_SCOPE is the union of EVERY task's declared list, so one
      # file declared by five tasks appears five times. Counting raw lines reads that as ambiguity
      # and refuses to resolve a path that is not ambiguous at all.
      _hits=$(grep -F -- "/$_sfx" "$MASTER_SCOPE" 2>/dev/null | sort -u)
      _nhit=$(printf '%s\n' "$_hits" | grep -c . )
      [ "$_nhit" = "1" ] && _lookup="$_hits"
      ;;
  esac
  if grep -qxF "$_lookup" "$MASTER_SCOPE" 2>/dev/null || glob_match "$_lookup"; then
    FILES_ACTUAL=$((FILES_ACTUAL + 1))
    LINES_ACTUAL=$((LINES_ACTUAL + _cnt))
  else
    printf 'SCOPE\t%s\n' "$_path" >>"$OUT"
  fi
done <"$CANDIDATES"

# --- BUDGET: only when at least one requested task carries a live budget -------------------------
if [ "$BUDGET_LIVE" -eq 1 ]; then
  if [ "$LINES_ACTUAL" -gt "$LINES_EXPECTED" ] || [ "$FILES_ACTUAL" -gt "$FILES_EXPECTED" ]; then
    MARGIN=$((LINES_ACTUAL - LINES_EXPECTED))
    [ "$MARGIN" -lt 0 ] && MARGIN=0
    printf 'BUDGET\t%s\tfiles=%s/%s\tlines=%s/%s\tmargin=%s\n' \
      "$TASKS" "$FILES_EXPECTED" "$FILES_ACTUAL" "$LINES_EXPECTED" "$LINES_ACTUAL" "$MARGIN" >>"$OUT"
  fi
fi

if [ -s "$OUT" ]; then
  cat "$OUT"
else
  echo CLEAN
fi
exit 0
