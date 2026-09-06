---
name: rtf6-git-ref-argument-injection
description: Measured behaviour of a leading-dash ref passed to git diff/show in codex-reviewer.sh (the `...HEAD` range does NOT bind it safely), the strict placement rule for --end-of-options, and the CX31 plant needle that pins the audit diff line verbatim
metadata:
  type: project
---

Measured on 2026-09-06 (git 2.50.1, Apple Git-155) fixing the RTF cycle-6 MAJOR finding
`4487f2c3` on `staging/plugin/scripts/codex-reviewer.sh`.

**`git diff "$_ref"...HEAD` gives a leading-dash ref NO protection.** The briefing's premise was
that `...` binds `_ref` into a single token that cannot be misparsed. Measured, it is false: git
matches the token against `--output=<value>` and simply absorbs `...HEAD` into the option's VALUE.

| command | exit | effect |
|---|---|---|
| `git diff "--output=/tmp/P"...HEAD` | 0 | creates `/tmp/P...HEAD` |
| `git show "--output=/tmp/P"` | 0 | creates `/tmp/P` |
| `git show --name-only --pretty=format: "--output=/tmp/P"` | 0 | creates `/tmp/P` |

An attacker-chosen path with a fixed `...HEAD` suffix is still an arbitrary file write. Never
reason that a suffix, a range operator or surrounding quotes makes a `-`-prefixed value safe —
only an explicit guard or `--end-of-options` does.

**`--end-of-options` placement is load-bearing and asymmetric to normal option order.** It must sit
after every option and immediately BEFORE the operand, because git reads everything following it as
a non-option:

- `git show --end-of-options --name-only --pretty=format: "$sha"` -> **exit 128** on a VALID sha
  (`fatal: option '--name-only' must come before non-option arguments`). This is the form the
  briefing proposed; it is broken and would have shipped a permanently-failing audit commit arm.
- `git show --name-only --pretty=format: --end-of-options "$sha"` -> exit 0. Correct.
- `git diff --end-of-options "$base"...HEAD --name-only` -> exit 128; the trailing `--name-only`
  has the same problem. `git diff --name-only --end-of-options "$base"...HEAD` -> exit 0.

**The audit `base:*` diff line cannot be reshaped without touching a test.** `codex-audit-mode.
test.sh` CX31 plants on the literal `CHANGED_FILES=$(git diff "$_ref"...HEAD --name-only
2>/dev/null)`. Adding `--end-of-options` there requires moving `--name-only` to the front, which
breaks the needle and turns the plant into NOFIRE (rule 2). A coder dispatch that is not assigned
the test file must leave that line alone. The review-mode diff line
(`DIFF_CONTENT=$(git diff "$_ref"...HEAD ...)`) is NOT pinned by any plant, so it is free.

**Resulting defense asymmetry, verified with a guard-stripped control build.** With the four
`validate_ref_no_leading_dash` calls removed, the two `git show` arms still refused the injection
(exit 3, no file) because `--end-of-options` caught it, while BOTH `git diff` arms wrote the file
and exited 0. So the show arms carry two independent layers and the diff arms carry exactly one
(the explicit guard). If a future change ever moves or drops that guard, the diff arms are live
again with no backstop — that is the place to look first.

**Verification shape that works here:** copy `staging/plugin` twice into a scratch dir, strip the
guard calls from one copy with `grep -v`, and run both against the same scratch repo and stub
`codex` (the stub shape is in `codex-audit-mode.test.sh:218`, `build_stub_codex`). The control
copy is what proves the guard is load-bearing rather than something else incidentally blocking the
attack. See [[worktree-git-guardrail-scratch-scripts]] for why the harness must live at a relative
path inside the worktree.
