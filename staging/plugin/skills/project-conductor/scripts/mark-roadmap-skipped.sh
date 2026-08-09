#!/bin/bash
# mark-roadmap-skipped.sh v1.0 — mark ONE PROJECT.md roadmap row as skipped (issue #385,
# ADR-0132 §D2).
#
# WHY THIS IS A FILE AND NOT A FENCE. A skill's markdown body is RENDERED before the model sees
# it, and Claude Code whitespace-splits the skill's own invocation arguments and substitutes them
# into every positional-parameter token in that body — bash fences included, because a fence is
# just text. An awk program written inside a fence therefore has its whole-record reference
# rewritten into whatever word the caller happened to pass, and what executes is syntactically
# valid awk that does the wrong thing, silently. A FILE is never rendered. That is the whole of
# the fix: the program below runs exactly as it is written here, whatever `project-conductor` was
# invoked with.
#
# THIS IS AN EXTRACTION (ADR-0069), NOT A DELIBERATE COPY (ADR-0086). The two call sites —
# `project-conductor` Step 4's no-generated-SPEC skip and Step 5 branch C's TERMINAL skip — ask
# ONE question: "mark this roadmap row skipped". Two answers to that question would be a roadmap
# disagreeing with itself, a row marked by one path and left unmarked by the other, so ADR-0086's
# criterion ("extract only when two copies giving different answers would be a DEFECT") answers
# yes here and both sites load this file instead of restating the program.
#
# EXACT WHOLE-LINE MATCH, NEVER A REGEX. Carried verbatim from the comment both original call
# sites wrote above the program: a feature title is arbitrary GitHub text and can carry any sed
# metacharacter or delimiter. `awk`'s `==` compares the entire record as a string, so a title
# containing `[`, `.`, `*` or `/` is matched literally and no other line can be caught by accident.
#
# IT IS A CHECKER, NOT A REPORTER. The caller branches on the exit code. It prints no `CLEAN`
# sentinel on stdout and must NEVER grow one — `weakening-scan.sh`, invoked from `commit` Step 1,
# is the reporter this idiom is routinely confused with (ADR-0048's "two adjacent gates, two
# opposite caller idioms"). Do not copy one block's branching into the other.
#
# USAGE
#   mark-roadmap-skipped.sh <project-md> <feature-title>
#
#   <feature-title> is the roadmap line's text WITHOUT the leading `- [ ] ` marker, exactly as the
#   conductor binds it. A row reading `- [ ] <feature-title>` becomes
#   `- [~] <feature-title>  (skipped)` — two spaces before the annotation, as both call sites
#   wrote it. Every other line in the file is copied through untouched.
#
# EXIT CONTRACT (ADR-0132 §D4, shared by the four scripts that issue adds)
#   0  RAN. A row matched and was marked, or none did. "Ran" is not "matched": a roadmap with no
#      matching row is a legitimate, ordinary outcome, and a caller that needs to know which
#      happened must compare the file. Nothing is printed on stdout in either case.
#   2  bad invocation: wrong argument count, or an empty argument.
#   3  COULD NOT RUN: the roadmap file is absent or unreadable, or the rewrite failed. Never
#      folded into 0 — a check that did not run must not read as a check that found nothing
#      (ADR-0076 §THE RULE, the distinction `spec-coverage.sh` and `plan-tasks.sh` also draw).
#
# IT WRITES ONLY <project-md> and its sibling temp file, and removes the temp file on every
# failure path.
#
# ONE BEHAVIOURAL NOTE, inherited unchanged from the inline form: `awk` terminates its last output
# record, so a roadmap file that did not end in a newline gains one. Both original call sites had
# that property and no consumer depends on its absence.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no here-strings.
set -u

SELF="mark-roadmap-skipped"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: mark-roadmap-skipped.sh <project-md> <feature-title>

Rewrites the roadmap row whose text matches <feature-title> exactly into the skipped form.
Exit: 0 ran (matched or not) | 2 bad invocation | 3 could not run
EOF
  exit 2
}

[ $# -eq 2 ] || usage "expected exactly 2 arguments, got $#"
MD="$1"
FEATURE="$2"
[ -n "$MD" ] || usage "the roadmap path is empty"
[ -n "$FEATURE" ] || usage "the feature title is empty"

[ -f "$MD" ] && [ -r "$MD" ] || {
  printf '%s: could not run — no readable roadmap file at %s\n' "$SELF" "$MD" >&2
  exit 3
}

TMP="$MD.tmp"

# The program, reproduced verbatim from the two call sites it replaces. The record reference below
# belongs to awk and to nothing else — it is precisely the token the renderer was rewriting, and
# in a file there is no renderer to rewrite it.
awk -v f="$FEATURE" '{ if ($0 == "- [ ] " f) print "- [~] " f "  (skipped)"; else print }' \
  "$MD" > "$TMP" || {
    rm -f "$TMP"
    printf '%s: could not run — awk failed while reading %s\n' "$SELF" "$MD" >&2
    exit 3
  }

mv "$TMP" "$MD" || {
  rm -f "$TMP"
  printf '%s: could not run — could not replace %s\n' "$SELF" "$MD" >&2
  exit 3
}

exit 0
