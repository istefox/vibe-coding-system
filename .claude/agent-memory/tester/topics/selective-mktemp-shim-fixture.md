---
name: selective-mktemp-shim-fixture
description: How to isolate a guard on the Nth call of a common utility (mktemp, git, curl) when earlier callers in the same run use it too — a caller-identifying PATH shim, its denominator guard, and the two-plants-one-id rule
metadata:
  type: project
---

Learned adding CX33 to `staging/plugin/scripts/tests/codex-audit-mode.test.sh` (2026-09-06), both
plants confirmed `fired`.

**The problem shape, which recurs whenever a script guards a call to a common utility.** A new guard
sits on the 3rd and 4th `mktemp` of a run, but calls 1 and 2 come from a helper the script invokes
first (`enumerate-sources.sh`, twice). Anything that breaks the utility process-wide — a broken
`TMPDIR`, a shim that always fails — trips the helper's own pre-existing guard and the run never
reaches the code under test. The naive fix, a global counter failing "the 3rd call", works but is
brittle in the direction that reads as coverage: the day the upstream helper allocates a third temp
file, the assertion silently starts driving a guard it does not name.

**Identify the CALLER, not the ordinal.** The shim reads `ps -o args= -p $PPID` and counts only the
invocations whose parent command line matches the script under test, failing on the Nth of *those*.
Measured, not assumed: bash forks for `$(mktemp)` but the child's argv is still the script's, so the
parent line reads `bash /…/codex-reviewer.sh --mode audit …`, while the helper's calls read
`/bin/bash /…/enumerate-sources.sh …`. Works unchanged inside plant-check's sandbox (the path still
ends in the script's basename) and is immune to the helper's own call count changing. Two details
worth copying: do NOT `exec` the real utility from the shim — capture its output, echo it, and append
it to a log file, which is what lets the assertion also check that a temp file created *before* the
failing call was cleaned up rather than leaked; and pass the shim's control variables as env-prefix
assignments on the subshell invocation rather than `export`ing them, so nothing leaks into later
assertions.

**The control pass is the denominator guard and the rule-8 direction at once.** Run the same fixture
with fail-nth=0 and require (a) exit 0 with the normal artifact and (b) the caller-scoped count equals
exactly the number of calls the guards under test represent. That single run proves the shim is really
being invoked by the script (not silently bypassed), proves "call 1"/"call 2" are the two guards named
and nothing further up, and blocks the cheap fix of making the whole block fail. Verified fail-loud by
disabling `ps` in a sandbox copy: the assertion goes RED with `control-…=0 (want 2)` and
`shim-never-fired` on both arms — never silently green — so a runner without `ps` reports a failure
rather than a pass.

**Two `# plant:` declarations may share one assertion id, and should when one assertion covers two
independent guards.** Already done in three harnesses here (`BK9b`, `RJ13b`, `RY12`); `plant-check.sh`
evaluates each declaration separately and credits both against `^FAIL: <id>`. Confirmed by running:
each mutation turned CX33 red *on its own arm only* (`[call-1: …]` vs `[call-2: …]`), which is
independent proof the fixture isolated the right call. Neutralise a whole guard with
`if [ … ] || [ … ]; then` → `if false; then`; mutating only the exit-code capture is absorbed by the
`[ -z "$VAR" ]` half of the same guard (the absorption class in
[[plant-sandbox-git-and-guard-absorption]]). A needle containing `||` is safe: `plant-check.sh` splits
fields on `" | "` (space-pipe-space) and `] || [` does not contain it — but check it with the real
`awk -F' \\| '` before trusting it.

**Current registry cost, re-derived 2026-09-06:** 686 declarations, ~30 min at 8 workers, ending
`PASS=692 FAIL=1` on the same standing `PC5 … spec-coverage.test.sh [RS7]` vacuous plant (RS7 fails at
HEAD: 8 of 201 frozen baseline rows diverge). See [[task1-codex-audit-mode-slug]] for the
stub-`codex`-on-isolated-PATH pattern this fixture layers on top of.
