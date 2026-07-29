# plan-task-predicate.awk — THE definition of a plan task line (ADR-0069 §D1/§D2, issue #172).
#
# Loaded as an additional awk program file, never copied:
#   awk -f <this> -f <caller.awk> <plan>
#
# THIS IS THE ONLY PLACE THAT DECIDES WHAT A PLAN TASK LOOKS LIKE. #172's defect was three files
# each holding their own answer; making them agree would have left three answers that agree today.
# If you need this predicate somewhere new, load this file — do not paste the regex.
#
# The two forms are the two `architect.md` Output Format documents and that the corpus contains:
#
#   ### Task 3 — … (R-02, R-05)      a heading, H2 through H4, containing the word "Task"
#   - [ ] **Task 3** — … (R-02)      a checklist item, checked or not
#
# Measured 2026-07-29 over the 57 plans in docs/superpowers/plans/: this predicate matches all 57.
# `any - [ ]` matches 50 (seven plans carry no checkbox at all); `- [ ] **Task N` matches 18.
#
# DELIBERATELY LOOSE, and the callers depend on the direction. `## Tasks` as a section heading
# matches; a checkbox SUB-STEP inside a task matches. Both over-count. Every current caller asks
# only "is there at least one", where over-counting fails toward dispatching a good plan rather
# than rejecting one — the correct direction for a malformed-plan guard. A caller that needs a
# true task COUNT, or a task BLOCK boundary, needs a stricter predicate and its own decision
# (see issue #184 for exactly that case).
#
# Bash 3.2 / POSIX awk clean: no gensub, no length(array), no --re-interval dependency.

function heading_level(l,   m) {
  if (match(l, /^#+[ \t]/)) return RLENGTH - 1
  return 0
}
function is_checklist_item(l) {
  return l ~ /^[ \t]*[-*][ \t]\[[ xX]\]/
}
function is_task_heading(l,   lvl) {
  lvl = heading_level(l)
  return (lvl >= 2 && lvl <= 4) && (l ~ /Task/)
}
function is_task_line(l) {
  return is_checklist_item(l) || is_task_heading(l)
}

# ------------------------------------------------------------------------------------------------
# is_task_opener() — THE SECOND QUESTION, and it is not the same one (ADR-0070, issue #184).
#
# is_task_line() answers "is there a task here", for a `>= 1` malformed-plan guard where
# over-counting is the safe direction. is_task_opener() answers "does a task BLOCK START on this
# line", for a consumer that attributes content — a `Budget:`, a file list — to the task it belongs
# to. There, over-counting is not safe: a checkbox SUB-STEP reading `- [ ] Re-run Task 2. Sections
# A and B green.` satisfies is_task_line(), and using it as a boundary would close task 1's block
# early and attribute its budget to task 2. Measured on the real corpus, not hypothesised.
#
# The rule: the task designation must be at the START of the line's own content, after the heading
# marker or the checkbox marker, and after an optional `**`. That admits both documented forms
#
#   ## Task 1 — …            ### Task 3 — … (R-02, R-05)
#   - [ ] **Task 1 — …**     - [ ] Task 1 — …
#
# and rejects a sub-step that merely mentions a task, which is the whole point.
#
# Measured 2026-07-29 over the 57 plans in docs/superpowers/plans/: 55 match. The two that do not
# use a different word for a task entirely — `### Step 0 —` and `### T1 —` — and both predate the
# `architect.md` contract that names the `Task N` form. See ADR-0070 §D3: exempted by name, not
# absorbed, because widening to `Step|T[0-9]` would make `## The T1 approach` a task boundary.
function is_task_opener(l,   lvl, rest) {
  rest = l
  lvl = heading_level(l)
  if (lvl >= 2 && lvl <= 4) {
    sub(/^#+[ \t]+/, "", rest)
  } else if (is_checklist_item(l)) {
    sub(/^[ \t]*[-*][ \t]\[[ xX]\][ \t]*/, "", rest)
  } else {
    return 0
  }
  sub(/^\*\*[ \t]*/, "", rest)
  return rest ~ /^[Tt]ask[ \t]+[0-9]+/
}
