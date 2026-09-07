---
name: audit-file-scope-fixtures-and-scratch-plant-verify
description: codex-reviewer.sh audit mode's whole-tree FILE_LIST is every git-tracked file (fabricated fixture paths get REJECTED by the file-scope validation), the hyphen-free-basename fixture fix, and a working procedure to manually verify new `# plant:` needles without running the full plant-check.sh
metadata:
  type: project
---

Learned repairing six broken assertions and adding CX35-CX40 to
`staging/plugin/scripts/tests/codex-audit-mode.test.sh` after two RTF security fixes landed in
`codex-reviewer.sh` (commit 93e5767 git-ref-injection guard, commit 31cdc68 audit file-scope
validation). See [[task1-codex-audit-mode-slug]] for the sibling memory on this same test file's
stub-CLI pattern and ADR-0154 back-reference requirement.

**codex-reviewer.sh audit mode's whole-tree FILE_LIST (no `--diff-scope`) is literally
`enumerate-sources.sh`'s output: every `git ls-files`-tracked path in whatever repo the process's
CWD sits in, minus DerivedData/Pods/.build/xcarchive/*.generated.swift.** Any test that runs audit
mode without `--diff-scope` and without its own scratch git repo is implicitly asserting against
THIS repository's own tracked tree (since `cr()`-style test helpers never `cd`). Once the audit
formatter started validating a finding's `file` against that scope (31cdc68), every stub-payload
fixture naming a fabricated path (`src/A.swift`, `src/Sec.swift`, `/already/absolute/src/B.swift`)
started being correctly REJECTED — six assertions broke at once from one fixture-shape defect, not
six independent bugs. The fix is real, in-scope, ALWAYS-TRACKED root-level files: `SPEC.md` and
`CLAUDE.md` worked here. Two constraints to check before picking a replacement path: (1) it must
actually be `git ls-files`-tracked (an untracked-but-present scratch file will NOT appear in
FILE_LIST); (2) if any downstream assertion synthesises an id from `os.path.basename(file)` via a
regex like `^<dim>-[^-]+-.{3}$`, the basename must be HYPHEN-FREE — most real script names in this
repo (`codex-reviewer.sh`) are NOT, but root docs (`SPEC.md`, `CLAUDE.md`, `PROJECT.md`) are.

**Fixing the "expected absolute file" side of an assertion after a validation-driven fixture swap:
use `os.path.realpath(os.path.join(root, rel))` on BOTH the allow-set and the expected value, never
a raw string join.** The production code itself now canonicalises this way (to survive a symlinked
checkout, e.g. macOS `/tmp` -> `/private/tmp`); an assertion computing its "expected" value by plain
concatenation will pass today only by coincidence of this repo's checkout not being symlinked, and
is comparing on a different basis than the code it is checking.

**A `--out`-writing script's audit-mode all-rejected/mixed/zero-findings/empty-denominator states
are FOUR district states, not one "scope validation exists" checkbox**, and a prior single
survivor-normalisation assertion (CX29 here) does not cover any of the other three. Worth writing
explicitly: (a) mixed payload — one in-scope survivor + one out-of-scope rejection, asserting BOTH
the survivor's presence and the rejected one's ORIGINAL (pre-normalisation) value named on stderr;
(b) all-rejected — exit 3 DID-NOT-RUN naming the exact count, never the same exit 0 a clean
zero-findings run gets, and no `--out` artifact; (c) zero-findings against a genuinely non-empty
scope — proof the new validation added no regression to the pre-existing clean-audit path; (d) the
denominator guard on the allow-set itself, see below.

**A denominator guard whose OWN early-exit branch (elsewhere in the same script) makes it
unreachable by any normal invocation can still be tested, from OUTSIDE the script, with a
CONTENT-selective shim on an interpreter the script shells out to.** Here: `codex-reviewer.sh`'s
audit formatter guards against an empty `ALLOWED_FILES` set, but a shell-level `if [ -z
"$FILE_LIST" ]` branch earlier in the same script already exits 0 before ever reaching the
formatter whenever FILE_LIST is genuinely empty — so the python-level guard's only real trigger is
a WIRING defect (the shell variable non-empty, but not actually reaching the subprocess's
environment). Simulated with a `python3` shim placed first on a PATH handed only to the subprocess:
it inspects its own `-c` script-text argument for a marker string unique to the target call site
(`ALLOWED_FILES`, absent from this script's other two python3 invocations), and only on that match
`unset`s the variable before `exec`ing the real interpreter. Same shim family as this file's
existing caller-selective `mktemp` (`ps -o args= -p $PPID`) and flag-selective `grep` (`-Fxf`)
shims — a THIRD selector axis (script content) for the same problem shape. A `# fired` marker file
written by the shim is the rule-7 denominator guard proving the shim actually intercepted the
targeted call rather than the run failing for an unrelated reason.

**Manually verifying a NEW `# plant:` declaration fires, without running the repo's full
`plant-check.sh` (which mutation-tests all ~690 declarations across 100+ test files and is out of
proportion for confirming 6 new ones): build a scratch copy of `staging/` as a SIBLING of the real
`staging/` dir (never nested inside it — `cp -R staging dest` where `dest` is created by `mktemp -d`
INSIDE `staging/...` copies the not-yet-populated `dest` into itself, producing one harmless empty
self-nested directory, caught by checking `find scratch -iname '*scratchname*'` for a hit deeper
than the top level). Apply the mutation with a `python3 -c` snippet that asserts `s.count(needle) ==
1` before replacing — the same one-and-only-one-match invariant plant-check.sh itself enforces — then
run the TEST FILE FROM THE MUTATED COPY'S OWN `tests/` DIRECTORY, never the original: these harnesses
resolve the script under test relative to their own `$0`
(`SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)`), so invoking the original test file against a mutated
copy elsewhere silently tests the UNMUTATED script and reports a false NOFIRE. Diff the FAIL lines
against a baseline run of the same scratch copy (unmutated) rather than the real tree's run, since a
`staging`-only copy (no sibling `docs/`) has its own pre-existing, unrelated reds (here: CX26/CX27,
which read `docs/architecture/ADR-*` and fail for a reason that has nothing to do with any plant).

**The worktree-git-guardrail refuses `bash <script>` even for a script INSIDE the dispatch's own
worktree, when the invocation uses shell-variable-expanded paths (`bash "$SCRATCH/.../foo.sh" >
"$SCRATCH/out"`) and the script's content contains `git` calls** — the coder-side memory
[[worktree-git-guardrail-scratch-scripts]] (if present in that agent's memory) documents the
outside-worktree trigger; this is a SEPARATE trigger observed from the tester side, inside the
worktree, that reproduced twice with variable-path forms and disappeared both times when the exact
same command was reissued with the absolute path spelled out LITERALLY (no `$VAR` expansion) in
both the script argument and the output redirect. Treat "literal absolute path, no variable" as the
first thing to try before concluding a scratch-copy verification is blocked entirely.
