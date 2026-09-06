---
name: plant-sandbox-git-and-guard-absorption
description: How a git-dependent end-to-end assertion still works inside plant-check.sh's .git-less sandbox, and the class of plant that a library call silently absorbs (os.path.join vs an isabs guard)
metadata:
  type: project
---

Learned adding CX28/CX29 to `staging/plugin/scripts/tests/codex-audit-mode.test.sh` (2026-09-06),
both plant-backed and both confirmed `fired`.

**`plant-check.sh` builds each sandbox WITHOUT `.git` — but the harness under mutation inherits
plant-check's own process CWD, which is the real repository.** So a harness assertion that shells
out to a script issuing bare `git ...` still resolves the REAL repo root while the *script* it runs
is the mutated sandbox copy. That combination is what makes git-driven end-to-end assertions
plantable here at all; the sandbox header's "`.git` is deliberately NOT supplied" reads as if they
are not, and it is only true of paths derived from `$(dirname "$0")`. Two consequences when writing
one: derive the expected repository root by running the same git command from the harness's own CWD
(`git rev-parse --show-toplevel`), never hard-code a checkout path — the worktree path differs per
emdash worktree and a hard-coded one passes only where it was written; and treat "CWD is not inside
a git checkout" as a distinct, FAILING verdict string rather than letting it fall through as a pass
(rule 4). A script that uses `git -C <root>` instead of bare `git` does not have this property —
check which before deciding whether a fixture needs a `cd`.

**A scratch git repo made with `git init` and no commits ("unborn") is the fixture for the gap
between `git rev-parse --is-inside-work-tree` (succeeds, exit 0) and `git diff HEAD` (exits 128).**
Any wrapper that guards only with the former and then discards git's stderr will hand on an empty
file list that intersects to nothing and reports a clean result — rule 7 one level down. Guard the
fixture itself (assert `rev-parse --verify HEAD` really fails) or the assertion can pass for the
wrong reason. When the script under test takes its repo from CWD, run it as
`( cd "$FIXTURE" && PATH=... bash "$CR" ... ) >/dev/null 2>"$err"` and read `$?` after the subshell:
the suite's own CWD is untouched, which later assertions depend on, and the existing `cr()` helper
cannot be reused because it never changes directory.

**A plant that deletes a guard can be ABSORBED by the library call the guard protects, and then it
does not fire.** Concretely: `os.path.join(ROOT, p)` returns `p` unchanged when `p` is already
absolute, so mutating `if p and not os.path.isabs(p):` into `if p:` changes nothing observable and
the "already-absolute values are not prefixed twice" assertion stays green with its guard removed.
To make that half go red the plant has to replace the *join* with concatenation
(`file_out = ROOT + file_val`), which breaks both directions at once. Same shape as CLAUDE.md rule
10 ("a floor absorbs its own plant"), one layer down: before writing a plant, ask whether the
mutated code still produces the same output by accident — and confirm by applying it in a scratch
`cp -R` sandbox and reading the actual FAIL line, which costs one harness run and is much faster
than the ~30 min full `plant-check.sh` sweep (681 declarations at 8 workers).

**Known pre-existing red as of 2026-09-06, verify before blaming your change:** a full
`plant-check.sh` run ends `PASS=687 FAIL=1` on `FAIL: PC5 ... spec-coverage.test.sh [RS7] — already
RED in the unmutated sandbox`, because `RS7` itself fails at HEAD (8 of 201 frozen baseline rows
diverge — the `spec-coverage-scope-baseline.tsv` bump lag this repo has hit before). Confirm
independence the cheap way rather than assuming: `cp -R` staging+docs to a sandbox, overwrite your
edited file with `git show HEAD:<path>`, re-run the harness, and compare the exact failure line.
Identical output on both sides is the evidence. See [[task1-codex-audit-mode-slug]] for the
stub-`codex`-on-isolated-PATH pattern these assertions reuse.
