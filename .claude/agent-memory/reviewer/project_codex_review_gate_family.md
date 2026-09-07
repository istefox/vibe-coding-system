---
name: project-codex-review-gate-family
description: ADR-0187/ADR-0193 Codex-substitution family in codex-reviewer.sh — fix/coverage state as of ADR-0193 cycle 2 re-review, and one live gap carried in --mode review
metadata:
  type: project
---

`staging/plugin/scripts/codex-reviewer.sh` implements the Codex-vs-Claude review-gate substitution
(ADR-0187, extended to `deep-refactor` audit dispatch by ADR-0193).

**RESOLVED as of cycle-2 re-review (2026-09-06), confirmed by direct code read AND independent
manual mutation (not just trusting the coder/tester's own claim):**

1. `--mode audit`'s `uncommitted` diff-scope arm now captures `git diff HEAD --name-only`'s exit
   status (codex-reviewer.sh:224-229) and returns exit 3 DID-NOT-RUN on failure — the unborn-repo
   case is covered. Regression test: `codex-audit-mode.test.sh` CX28 (unborn repo via `git init`,
   asserts exit 3 + message + no `--out` artifact). Plant declared and independently verified to
   fire: manually applying the plant's exact needle/replacement in a scratch `cp -R` sandbox turns
   CX28 RED (`rc=0` instead of 3) — did not just trust the `# plant:` declaration's presence.
2. The audit-mode `"file"` field is now joined onto `REPO_ROOT` (resolved via
   `git rev-parse --show-toplevel`) when relative, left alone when already absolute
   (codex-reviewer.sh:643-646), matching `deep-refactor/SKILL.md`'s `"file": "<absolute path>"`
   contract. Regression test: CX29, both directions in one assertion (rule 8). Also independently
   verified to fire on manual mutation (concatenation instead of `os.path.join` breaks both
   directions at once, exactly as the plant needle exploits).

**STILL OPEN, found during this same re-review — pre-existing, NOT introduced by ADR-0193, and
NOT covered by any test:**

3. `--mode review`'s diff-scope block (codex-reviewer.sh, the `case "$DIFF_SCOPE" in ... esac`
   right after `if [ "$MODE" = "review" ]`) has the IDENTICAL defect finding 1 above just fixed in
   audit mode, for ALL THREE arms (`uncommitted`, `base:*`, `commit:*|`), and it was never touched
   by ADR-0193's diff. `git diff`/`git show` failing (unborn repo, bad ref, bad sha) produces empty
   stdout with `2>/dev/null` discarding stderr and no exit-status capture; the empty-stdout result
   then falls into the same branch as a genuinely empty diff and is reported as exit 0 "no
   detectable changes... safe to merge" — DID-NOT-RUN silently reads as a clean review. Review mode
   is the one used at the 5 *blocking* RTF/concept-to-code review-gate dispatch sites (more
   consequential than audit mode's advisory findings). `base:<typo'd-ref>` / `commit:<bad-sha>` are
   realistic operator-error triggers, not just the unborn-repo edge case. ADR-0187 never called this
   out as accepted/deferred (checked: no mention of "unborn"/"is-inside-work-tree" there). No test
   anywhere in the repo exercises a failing git call in review mode's diff-scope arms.
4. Minor test-coverage gaps, not code defects (code read as correct both times): (a) no test drives
   the `base:*`/`commit:*` arms of AUDIT mode's diff-scope block through an actual failing git call
   (bad ref/sha) to confirm the cycle-1 exit-3 fix end-to-end — CX06 only exercises valid refs; (b)
   no test exercises enumerate-sources.sh present-but-not-executable (`chmod -x`, no `mv`) — CX08
   only covers "moved aside" (not found at all), leaving the `[ ! -x ]` half of that OR-guard
   structurally-verified-only.

How to apply: on any future review of a `codex-reviewer.sh` diff, check every diff-scope arm across
ALL THREE modes for a symmetric git-exit-status guard — a fix landing in one mode's copy of a
shared pattern does not imply the sibling mode's copy was checked. Re-verify current state at
review time rather than trusting a prior review's memory snapshot; this file's own history (items 1
and 2 were "still open" as of the previous cycle-2 entry, now resolved) is itself an example of
that drift.
