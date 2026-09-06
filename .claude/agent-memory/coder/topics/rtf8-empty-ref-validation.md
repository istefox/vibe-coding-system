---
name: rtf8-empty-ref-validation
description: Measured git behaviour on an EMPTY ref/sha in codex-reviewer.sh's four diff-scope arms — why `base:` was a silent false clean while `commit:` was not, where the one-line fix belongs, and the plant-needle pipe detail
metadata:
  type: project
---

Measured on 2026-09-06 (git 2.50.1, Apple Git-155) fixing the Codex re-review MAJOR finding on
`staging/plugin/scripts/codex-reviewer.sh` `validate_diff_scope`.

**`base:` and `commit:` with an empty value fail in OPPOSITE, non-obvious ways — the finding named
only `base:` and was right to, but the sibling still needed fixing for a different reason.**
Measured in a scratch repo, exactly as the script builds each argument:

| arm | command | exit | result |
|---|---|---|---|
| review `base:` | `git diff ""...HEAD` | **0** | empty diff |
| audit `base:` | `git diff ""...HEAD --name-only` | **0** | empty list |
| review `commit:` | `git show --end-of-options ""` | 128 | `ambiguous argument ''` |
| audit `commit:` | `git show --name-only --pretty=format: --end-of-options ""` | 128 | same |

The `base:` exit 0 is not a git quirk to route around, it is specified behaviour: the shell
collapses `""` and the `...HEAD` suffix into the single token `...HEAD`, and gitrevisions states
that an omitted side of `..`/`...` **defaults to HEAD** — so git faithfully diffs `HEAD...HEAD`.
Verified independently: `git diff ...HEAD~2 --name-only` and `git diff HEAD...HEAD~2 --name-only`
produce byte-identical output, and `git rev-parse ...HEAD~2` prints HEAD's sha as the excluded side.
Do not expect a degenerate range to error — it resolves.

**End-to-end, pre-fix, through the real script with the suite's own stub `codex`:**
`--diff-scope base:` returned exit 0 with `**Verdict:** safe to merge (nothing to review)` in review
mode and exit 0 with `[]` in audit mode. A FALSE CLEAN in both, byte-identical to a genuinely
reviewed empty diff. `commit:` returned exit 3 DID-NOT-RUN — not a false clean, but the wrong CLASS:
exit 3 is the single signal callers gate the fallback-to-Claude AskUserQuestion on, spent on what is
plainly a caller error. So the two halves needed the same fix for two different reasons, and an
assertion checking merely "non-zero" would have been satisfied by the `commit:` half of the defect
itself. Both assertions therefore pin the exit-code CLASS (rc == 2 AND stderr free of `DID-NOT-RUN`)
and use `[ ! -e "$out" ]` rather than `! -s`, which is what separates "rejected before git ran" from
the `base:` half's written-report false clean.

**The fix belongs in `validate_diff_scope`, not in the four arms.** One added `case` arm rejects
both prefixes before any git call; the four `validate_ref_no_leading_dash` sites are untouched. The
arms are unreachable without passing the validator (review calls it unconditionally, audit calls it
whenever `DIFF_SCOPE` is non-empty and gates the arms on the same condition), so two layers would be
a second copy of one question (rule 6) rather than defense in depth. Emptiness is a GRAMMAR question
(`base:<ref>` requires `<ref>`), which is what `validate_diff_scope` already owns; leading-dash
safety is a git-argument question, which is what
[[rtf6-git-ref-argument-injection]]'s guard owns. **Ordering is load-bearing**: `base:|commit:)` must
precede `uncommitted|base:*|commit:*)` because `*` matches the empty string and would swallow it.

**A `|` inside a `# plant:` field is fine; ` | ` is not.** `plant-check.sh` splits on
`awk -F' \\| '` — space-pipe-space. A needle containing `base:|commit:)` parses to the required 4
fields untouched. Verified before relying on it: the declaration split to `NF=4` and the needle
matched exactly once. The pattern alone is NOT unique enough — the needle must span the arm's whole
message and `exit 2` to avoid colliding with the pattern arm one line below.

**No caller in the repo is affected.** Surveyed `staging/plugin/skills|agents|commands`: every
`--diff-scope` occurrence is the literal `uncommitted` (review-triage-fix ×2,
concept-to-code step5 ×2). Nothing constructs `base:$var`, so no existing call site changes
behaviour — the previously-silent exit 0 could only ever be reached by hand.

Scratch harnesses for all of the above had to live at relative paths inside the worktree, per
[[worktree-git-guardrail-scratch-scripts]]; `plant-check.sh` has no per-id filter, so firing the two
new plants was verified by replicating its sandbox (`staging` + `docs` + `.github` + `.gitignore` +
`CLAUDE.md` + `PROJECT.md`, no `.git`) and its `\s+`-joined needle substitution by hand. Useful
byproduct: that sandbox runs `codex-audit-mode.test.sh` fully green without a `.git`, so a `.git`-
less scratch copy is a legitimate way to bisect this suite.
