---
name: plant-sandbox-git-and-guard-absorption
description: How a git-dependent end-to-end assertion still works inside plant-check.sh's .git-less sandbox, the two ways a plant gets absorbed (os.path.join over an isabs guard; a second exit-3 path over a deleted guard), and the standing RS7 red
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

**A DID-NOT-RUN assertion that reads only the exit code can be absorbed the same way.** Second
instance of the absorption class, found adding CX32 (2026-09-06): deleting the `[ ! -x "$ENUM" ]`
half of a guard does not change the exit code, because execution then reaches the non-executable
helper and fails *later* with a different exit-3 DID-NOT-RUN ("… failed (exit 126)" instead of
"… not found or not executable"). Whenever a script has several exit-3 paths, an `rc -eq 3` check
alone pins nothing — assert the MESSAGE, quoted from the source, not paraphrased. Verify by running
the plant, not by reasoning: the probe printed `rc=3 (want 3) message-ok=0`, which is the whole
argument in one line.

**Known pre-existing red, re-confirmed 2026-09-06:** a full `plant-check.sh` run (now 684
declarations, ~25 min at 8 workers) ends `PASS=690 FAIL=1` on `FAIL: PC5 ... spec-coverage.test.sh
[RS7] — already RED in the unmutated sandbox`, because `RS7` itself fails at HEAD (8 of 201 frozen
baseline rows diverge — the `spec-coverage-scope-baseline.tsv` bump lag this repo has hit before).
Cheapest confirmation that it is not yours: run `spec-coverage.test.sh` directly and read the
`FAIL: RS7` line; it is a different harness from the one you edited. For a same-harness suspicion,
`cp -R` staging+docs to a sandbox, overwrite your edited file with `git show HEAD:<path>`, re-run,
and compare the exact failure line. See [[task1-codex-audit-mode-slug]] for the
stub-`codex`-on-isolated-PATH pattern these assertions reuse.
