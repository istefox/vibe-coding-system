---
name: review-mode-diff-scope-exit-capture
description: Review mode's diff-scope arms in codex-reviewer.sh now capture git exit status (RTF cycle 3, ADR-0193) — measured exit codes, the empty-diff branch that must stay reachable, and why the new guards do not collide with CX28's plant needle
metadata:
  type: project
---

Measured on 2026-09-06 fixing the RTF cycle-3 MAJOR finding on
`staging/plugin/scripts/codex-reviewer.sh`: review mode's three `--diff-scope` arms discarded the
git exit status, so a failing git call produced an empty `DIFF_CONTENT` and fell into the
"safe to merge (nothing to review)" branch with exit 0. Same defect class as the audit-mode one
fixed in cycle 2 — see [[codex-audit-git-preconditions-and-path-shape]] for the precondition table
behind both.

**Measured exit codes for the three review-mode failure fixtures** (scratch repos, stub `codex`):

| fixture | command | exit |
|---|---|---|
| unborn repo (`git init`, no commits) | `git diff HEAD` | 128 |
| healthy repo, unknown base ref | `git diff nosuchref...HEAD` | 128 |
| healthy repo, unknown sha | `git show deadbeef…` | 128 |

All three now exit 3 naming the scope. A healthy repo with no changes still exits 0 with the
markdown "safe to merge (nothing to review)" report, and a healthy repo WITH a staged change gets
past the guard entirely (it then fails later, on the stub's empty codex output — which is the proof
the guard does not misfire on the happy path).

**The new guards do not collide with `codex-audit-mode.test.sh` CX28's plant needle**, and a tester
adding review-mode coverage must keep it that way. CX28 plants on the literal
`CHANGED_FILES=$(git diff HEAD --name-only 2>/dev/null)` + `_git_rc=$?` pair at 8-space indent in
the AUDIT arm; the review arm's pair is `DIFF_CONTENT=$(git diff HEAD 2>/dev/null)` at 6-space
indent. The distinguishing token is `--name-only`, not the variable name and not `_git_rc=$?` —
a review-mode plant needle written as just `git diff HEAD 2>/dev/null` would be ambiguous the moment
either arm is reindented. Rule 1 applies: the needle must belong to the arm it asserts about.

**The DID-NOT-RUN message string is now emitted from six sites** (three audit arms, three review
arms), identical text in all six. Nothing counts them, but a future exact-count assertion on
`could not resolve diff-scope` would have to say 6, not 3.

**Consumer side needs no change:** `review-triage-fix/SKILL.md` already documents exit 3 for review
mode in three places ("stop and ask, never silently fall back to Claude"), and review mode already
had exit-3 paths (no codex, auth, not a git repository) — this adds occasions, not a new code
(rule 20 checked, not assumed).
