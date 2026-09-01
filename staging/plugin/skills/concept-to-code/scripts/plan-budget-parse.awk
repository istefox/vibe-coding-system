# plan-budget-parse.awk — THE definition of how a `Budget:` declaration parses (VCS-057/ADR-0185,
# issue #246, ADR-0052 §D6).
#
# Loaded as an additional awk program file, never copied:
#   awk -f plan-task-predicate.awk -f <this> -f <caller.awk> <plan>
#
# Extracted from diff-budget-check.sh (rule 6, ADR-0070 §D2's own lesson applied to itself: that
# script already carried the FOURTH private copy of the task-opener predicate before it loaded
# plan-task-predicate.awk instead of restating it — issue #246's PER-FILE-ceiling parser is exactly
# as expensive to fork, and VCS-057's `step5-brief.sh` is about to become the second real
# consumer). One producer of "what does a Budget: line mean", checked once, not two copies that
# could answer differently (rule 6's own test: would a bug in one silently diverge from the other).
#
# THIS FILE HOLDS ONLY THE TEXT FUNCTIONS — trim(), parse_budget(), looks_like_budget(),
# task_num(). It has no BEGIN/main block and touches no file: each caller drives its own iteration
# (diff-budget-check.sh writes BUDGET/MALFORMED/SCOPE tsv files; step5-brief.sh unions file lists
# for a brief). Merging the driver in here would force every caller into one script's I/O shape,
# which is the same reason is_task_opener() lives alone in plan-task-predicate.awk without a
# driver of its own.
#
# Byte-identical to the code that used to live inline in diff-budget-check.sh between
# `cat >"$TMPD/plan_parse.awk" <<'AWKEOF'` and the `function task_num` block — moving it changed
# nothing about what it matches. Verified against the full 79-plan corpus in
# docs/superpowers/plans/ post-extraction (see plan-budget-parse.test.sh): same BUDGET_FILE,
# MALFORMED_FILE and SCOPE_FILE output before and after.
#
# Bash 3.2 / POSIX awk clean: no gensub, no length(array), no --re-interval dependency.

function trim(s) { gsub(/^[ \t]+/,"",s); gsub(/[ \t]+$/,"",s); return s }

# parse_budget(rest) -> "<files>\t<total>", or "" when the declaration does not fully parse.
#
# A LEFT-TO-RIGHT WALK OVER PAREN GROUPS, which SUBSUMES the documented single-ceiling form rather
# than branching on it (issue #246). The old parser matched one paren group anchored at end of
# line, so a PER-FILE declaration —
#   Budget: a/SKILL.md (~165 lines, new), b/sync.sh (~1 line)
# — kept only the LAST ceiling (1 instead of 166) and left the first file plus the fragments
# `(~165 lines` and `new)` in the file list, producing a false SCOPE on a file the plan declares
# explicitly, an inflated file count, and no BUDGET line at all. Measured over the corpus: 16
# `Budget:` lines in 3 plans, 12 single-ceiling, 3 per-file — and every one of the three was
# mis-parsed in all three ways at once.
#
# The walk handles both, and mixed forms too: a group's preceding text may itself be a
# comma-separated list sharing that ceiling, which is exactly the documented form seen as one
# entry. Ceilings are SUMMED, because the downstream check compares per-task totals.
function parse_budget(rest,   s, pre, paren, inner, low, num, files, total, rem) {
  s = rest; files = ""; total = 0
  while (match(s, /\([^()]*\)/)) {
    pre   = substr(s, 1, RSTART - 1)
    paren = substr(s, RSTART, RLENGTH)
    s     = substr(s, RSTART + RLENGTH)
    sub(/^[ \t]*,[ \t]*/, "", pre)          # the separator left by the previous entry
    gsub(/`/, "", pre); pre = trim(pre)
    sub(/,[ \t]*$/, "", pre)
    inner = paren; gsub(/[()]/, "", inner); low = tolower(inner)
    # A note after the count is tolerated — `(~10 lines, comments only)` is in the corpus.
    if (pre == "" || !match(inner, /[0-9]+/) || index(low, "line") == 0) return ""
    num = substr(inner, RSTART, RLENGTH)
    total += num
    files = (files == "" ? pre : files ", " pre)
  }
  # Anything after the last group that is not a separator or markdown emphasis means the line did
  # NOT fully parse. Without this, `Budget: a.md (~50 lines), b.md` would silently drop b.md — the
  # half-read this function exists to stop.
  rem = s; gsub(/[ \t,*_`.]/, "", rem)
  if (files == "" || rem != "") return ""
  return files "\t" total
}

# looks_like_budget(rest) — is this a recognisable ATTEMPT at a declaration? Only then may a parse
# failure be REPORTED; otherwise it stays silent, exactly as before.
#
# The discriminator is measured, not chosen for tidiness. `Budget:` is matched as a case-insensitive
# SUBSTRING, so the corpus contains `# Performance budget: <10s typical, 8s per-harness timeout.` —
# a comment inside a fenced code block, never a declaration — and a legitimate prose escape,
# `Budget: none (verification only, no source files touched beyond what Tasks 1-6 already changed)`.
# A MALFORMED token firing on either would be this issue's own defect one level up: a detector
# reporting on text that was never a declaration.
function looks_like_budget(rest,   s, inner, low) {
  s = rest
  while (match(s, /\([^()]*\)/)) {
    inner = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    gsub(/[()]/, "", inner); low = tolower(inner)
    if (match(inner, /[0-9]+/) && index(low, "line") > 0) return 1
  }
  return 0
}
# task_num(l) -> the task's own designation, digits plus an optional single trailing letter
# (VCS-057/ADR-0185, step5-brief.sh). The corpus uses "Task 1b"/"Task 4d" for a genuinely
# distinct task sequenced between two integers, never as a sub-item of the integer task — measured
# across docs/superpowers/plans/: exactly two designators, both a single trailing letter, no
# multi-letter form. Digits-only used to be returned (gsub stripped the letter), which collapsed
# "Task 1b" onto "Task 1" — two different tasks reporting as one key, silently merging their
# Budget: totals and, in step5-brief.sh, corrupting its byte-exact slice (rule 6: one parser, fixed
# once here reaches every caller instead of leaving each to hit this independently).
function task_num(l,   t) {
  match(l, /Task[ \t]+[0-9]+[A-Za-z]?/)
  t = substr(l, RSTART, RLENGTH)
  gsub(/[^0-9A-Za-z]/, "", t)
  gsub(/^[A-Za-z]+/, "", t)
  return t
}
