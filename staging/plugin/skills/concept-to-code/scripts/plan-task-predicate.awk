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
