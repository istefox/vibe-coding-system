# Implementation plan — a bash fence executes under bash (issue #394)

- **ADR:** `docs/architecture/ADR-0133-394-fence-execution-shell.md`
- **SPEC:** `SPEC.md` (topic slug `394-skill-fences-rely-on-word-splitting`)
- **Requirements:** R-01 (audit measured and recorded), R-02 (population executes under bash,
  verified by execution), R-03 (population = declared ∪ divergent; `commit` fences marked),
  R-04 (stdout-and-exit-code contract), R-05 (structural guard, derived, denominator-guarded),
  R-06 (guard in CI with firing plants), R-07 (executed proof on the host shell),
  R-08 (end-to-end acceptance of the original symptom), R-09 (exit codes and tokens unchanged),
  R-10 (no positional token; ADR-0132 guard stays green), R-11 (the defect predates #385),
  R-12 (shell-agnostic fences untouched, boundary stated), R-13 (no inert-until-sync failure mode).

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield

---

## Measured facts the tasks depend on

Re-derived from the tree by **execution** on 2026-08-09 (zsh 5.9, bash 3.2.57, macOS, CC 2.1.226).
Several differ from the SPEC. **Do not re-trust the SPEC's numbers over these.**

1. **The corpus:** 30 staged `SKILL.md`, **162** bash fences, **32** `fence-contract`, **1**
   `fence-illustration`, **129** unmarked. (ADR-0107's 18 declarations is a stale snapshot.)
2. **14 divergent findings across 13 distinct fences** — 4 already declared, 9 unmarked. Full table
   in the ADR's *Measured facts*. **Four sites the issue's scanner could not see:**
   `conductor-step0-args`, `claude-md-slim`@169 (`$DUP_ARGS`), and `concept-to-code`@1865 / @1887
   (`${_troot:+--tests-root "$_troot"}`).
3. **Population = 32 + 9 = 41 fences.**
4. **`bash -n` is blind to a wrapped body.** A wrapper containing `if [ ; then` passes `bash -n`.
   `F7` goes vacuous the moment the wrapper lands unless the inner body is parsed separately.
5. **`fence_body`'s dedent corrupts a column-0 line inside an indented fence.** `substr($0, ind+1)`
   turns `FENCE_BASH` into `CE_BASH` for a 3-space-indented fence. Nine declared fences are indented
   (`autopilot` ×4 at 3, `claude-md-slim` at 3, `concept-to-code` ×2 at 3, `project-conductor` at 3
   and at 2). `commit`@100 is indented 2; `commit`@228 and @479 are at column 0.
6. **An indented terminator destroys the exit code silently.** Probe: body ran, the terminator line
   was swallowed into the here-document, and the following `printf "rc=…"` never executed.
7. **`export <name>` before the wrapper forwards a caller-bound plain variable** and is a no-op on
   an unset one, in both shells. **24 of the 32 declared fences have at least one free variable.**
8. **The only here-document delimiter inside any declared fence is `DIRTY_EOF`.** No `SKILL.md`
   contains a column-0 line reading `FENCE_BASH`. No declared fence reads the caller's stdin.
9. **`fence-contract-coverage.test.sh` currently reports `PASS=45 FAIL=0`, and its `Z1` floor is
   37** — eight units of slack, which ADR-0124 says absorbs a plant.
10. **It carries zero declared plants today.** Its ids are `F1`–`F10`, `S1`–`S9`, `E1`–`E20`, `Z1`.
    Note the pre-existing `F1`/`F10` prefix collision (issue #355) — do not add ids that prefix
    each other.
11. **`docs-ci.yml`'s named list holds 75 entries and the harness holds 75 `*.test.sh` files** —
    complete. `fence-contract-coverage` is already named, so **no list edit is needed** as long as
    no new `*.test.sh` file is created.
12. **The free-variable analyser used at design time misses assignments that are not at line
    start** — `*) OTHER="$OTHER$f " ;;` inside a `case` arm was reported as a free variable of
    `c2c-step5-preflight-dirty-classify`. Match `(^|[;&|(]|[[:space:]])NAME=` before trusting a
    generated `export` list.

## Standing constraints for every task

- **Bash 3.2 / BSD-tools clean.** No assoc arrays, no `mapfile`, no process substitution, no `<<<`,
  no GNU-only `sed`/`grep`/`awk` flags. Write an awk program to a temp file rather than using
  `/dev/stdin` (the convention `plan-tasks.sh` and `spec-coverage.sh` already follow).
- **Never `grep -c … || echo 0`** — it yields the two-line string `0\n0` (issue #174). Use
  `n=$(grep -c . f 2>/dev/null || true); n=${n:-0}`.
- **No `<file>:<digits>` or `line <digits>` cross-references** in anything under
  `staging/plugin/skills/` or `staging/plugin/skills/*/scripts/` — `cross-reference-form.test.sh`
  derives over that population. Name a distinctive anchor.
- **No new `*.test.sh` file.** New assertions go into `fence-contract-coverage.test.sh`, already
  named in `docs-ci.yml`.
- **New assertion ids are `WS1`…`WS9`** (and `WSA`, `WSB`… if more are needed). No id may prefix
  another: `plant-check.sh` credits a plant on a `^FAIL: <id>` **prefix** match, so a `WS1b` beside
  a `WS1` makes both plants unfalsifiable. Do not introduce one.
- **Plant declarations** sit at column 1, split on the literal ` | `, so **no needle or replacement
  may contain a shell pipeline**, and a replacement may not contain a newline. A `printf … >&2`
  followed by `exit N` collapsed onto one line makes the exit two arguments to `printf`
  (ADR-0112) — never write that mutation.
- **The wrapper's exact form** (ADR-0133 §D1), reproduced once so no task re-invents it:

  ```text
  export <free vars>          # omitted entirely when the body has none
  bash <<'FENCE_BASH'
  …body verbatim…
  FENCE_BASH
  ```

  Quoted opener. Terminator at **column 0**, even inside an indented fence. No positional token.

---

## Batch boundaries (ADR-0088 §D5, ADR-0101 §D1)

Rule 1 — an assertion must not share a batch with the task it depends on — **outranks** rule 2.

| Batch | Tasks | End-of-batch state |
|---|---|---|
| 1 | Task 1, Task 2 | fully green |
| 2 | Task 3 | **RED by design** — see below |
| 3 | Task 4, Task 5 | partially green |
| 4 | Task 6, Task 7 | `WS` fully green |
| 5 | Task 8, Task 9 | fully green |

**Declared expected red, batches 2–3.** Task 3's `WS1`/`WS3`/`WS4` assert that every population
fence carries the wrapper. They are written before any fence is wrapped, so they fail at
checkpoints 2 and 3 naming the unwrapped fences, and go green in batch 4. This is ADR-0101's
case (a) — *a red a later task in the same Step 5 restores* — and it is the reason Task 3 is not
merged into Task 4: an assertion sharing a batch with the task that satisfies it records a RED that
proves nothing. **Any red at checkpoint 4 or 5, or any red not on this list, stops the run.**

---

## Task 1 — The divergence audit: a committed scanner and the measured table (R-01, R-12)

**Files:** create `staging/plugin/scripts/tests/fence-shell-divergence-scan.sh`; edit
`docs/architecture/ADR-0133-394-fence-execution-shell.md`.
Budget: staging/plugin/scripts/tests/fence-shell-divergence-scan.sh, docs/architecture/ADR-0133-394-fence-execution-shell.md (~200 lines)

The scanner is a **REPORTER**: it always exits 0 with findings on stdout, and exits **3** when awk
cannot express its rules (every rule uses `{n}` interval syntax; a pre-2019 awk treats the braces
literally and every rule goes silently inert — ADR-0046's receipt). It prints no `CLEAN` sentinel
and must never grow one. State the reporter/checker contrast in its header, and state that the
**consumer in Task 3 is a checker** — do not copy one block's branching into the other.

- [ ] Reads **one fence body on stdin** and enumerates nothing. This is deliberate: the single
      enumerator is `fence-contract-coverage.test.sh`'s `enumerate_fences`, and a second copy would
      be two answers to *what is a fence body* — ADR-0086 §D1's criterion answered yes.
- [ ] Emits one `<class>\t<body-line>\t<text>` record per finding. Classes: `W-for`, `W-set`,
      `W-arg` (word splitting), `G-glob` (a path glob as a command word — zsh `nomatch`),
      `E-echo` (`echo` with a backslash escape), plus the cheap bash-only probes `B-builtin`
      (`shopt`/`mapfile`/`readarray`), `B-var` (`BASH_*`), `B-declare`, `A-array`.
- [ ] Blanks single-quoted and double-quoted spans **tracking `$( )` depth inside double quotes**,
      so `"$(cmd "x")"` counts as fully quoted; skips here-document bodies as data; skips comment
      lines; drops `$(( ))` and `[[ ]]` before the word-split rules; excludes `case`-arm-shaped
      lines from `G-glob`.
- [ ] **Its header declares its blind spots verbatim from ADR-0133 §Consequences/Negative** — the
      multi-line quoted string, here-document bodies, the `case`-arm heuristic, the unmodelled
      divergences (`MULTIOS`, `KSH_ARRAYS`, `$0`, `[[ =~ ]]` captures, `printf %q`, `local`
      scoping), and staged-`SKILL.md`-only scope. A sweep whose limits are unstated reads as
      complete. **The header must say a green scan means no modelled idiom was found, never that no
      divergence exists.**
- [ ] Drive it over all 162 fences with the existing enumerator, and **write the resulting total,
      per-class breakdown and per-site list into the ADR's *Measured facts* section, replacing the
      design-time table if the numbers differ.** Reconcile any difference explicitly rather than
      silently overwriting. The design-time run found 14 findings / 13 fences / 2 false positives.
- [ ] **Measure the outbound direction too** and record it in the ADR: for each population fence,
      the variables it binds that a later fence in the same step references. This is what R-04's
      rewrite work in Tasks 4/6/7 is scoped from. The design-time analysis covered the *inbound*
      direction only.
- [ ] Record the R-12 boundary as a number: how many of the 162 fences stay outside the population.

## Task 2 — Harness machinery: a guarded dedent, and an inner-body parse (R-02, R-05)

**Files:** `staging/plugin/scripts/tests/fence-contract-coverage.test.sh`.
Budget: staging/plugin/scripts/tests/fence-contract-coverage.test.sh (~60 lines)

Nothing can extract or execute a wrapped fence until this lands, and `F7` starts lying the moment
one does. Both halves are TDD pairs that go red before the fix and green after — **run them and see
them red before writing the fix.**

- [ ] **RED first:** a fixture — a 3-space-indented fence whose body carries a column-0 line — and
      an assertion (`WS8`) that `fence_body` returns that line intact. Measured to fail today,
      returning `CE_BASH` for `FENCE_BASH`.
- [ ] Fix `fence_body` to strip **at most** the opener's indentation in leading blank characters,
      never `substr` past the start of a shorter line. `enumerate_fences` is untouched.
- [ ] **RED first:** a fixture — a wrapper whose body contains `if [ ; then` — and an assertion
      (`WS9`) that the harness's syntax check rejects it. Measured to pass `bash -n` today.
- [ ] Add an `unwrap_body` helper: given a fence body, return the here-document body when the
      wrapper is present and the body unchanged otherwise. Extend `F7` to parse the **inner** body
      for every declared contract. `F7`'s existing message and id are preserved.
- [ ] Confirm the suite is fully green at the end of this task, and that `F1`/`F2`/`F10`'s counts
      have not moved.

## Task 3 — The structural guard: section `WS` (R-05, R-06, R-10, R-13)

**Files:** `staging/plugin/scripts/tests/fence-contract-coverage.test.sh`.
Budget: staging/plugin/scripts/tests/fence-contract-coverage.test.sh (~160 lines)

**This task is expected to end RED.** See the batch table. Write the assertions, run them, record
which fences they name, and stop — do not wrap anything here.

- [ ] `WS0` — **denominator guard.** The population (declarations ∪ scanner-divergent) is
      non-vacuous: `>= 32`. A marker parse or a scanner that has stopped matching empties every
      other `WS` assertion at once, and four silent passes read as coverage (ADR-0085).
- [ ] `WS1` — every fence in the population carries the wrapper: a line matching the quoted opener
      and a terminator line.
- [ ] `WS2` — **the terminator sits at column 0** in every population fence. Measured hazard: an
      indented terminator swallows the rest of the script and destroys the exit code, and it looks
      like correct formatting.
- [ ] `WS3` — every population fence's **inner** body parses as bash (reuses Task 2's `unwrap_body`;
      this is what stops `F7` going vacuous).
- [ ] `WS4` — the scanner's flagged set is a **subset** of the population. A divergent fence outside
      the population fails loudly here rather than being repaired once and left unguarded.
- [ ] `WS5` — **scanner denominator guard.** The scanner returns a non-vacuous classification on a
      known-divergent fixture, and returns `exit 3` on an awk that cannot express its rules. A
      scanner reporting nothing must be distinguishable from a corpus with nothing to report.
- [ ] `WS6` — no population fence body contains a positional-parameter token (ADR-0132 cross-check,
      independent of `skill-fence-positional-tokens.test.sh`, cheap here because the bodies are
      already in hand).
- [ ] `WS7` — **the no-marker decision is pinned as prose** (ADR-0133 §D2): the guard's own comment
      block states that the wrapper carries no declaration marker and why. The next reader meeting an
      unmarked convention in a marker-rich repository will otherwise add one.
- [ ] Raise `Z1`'s floor to the **new actual assertion total**. Left at 37 it carries enough slack to
      absorb a vanished assertion — the defect ADR-0124 removed from `SP5`, reintroduced by the
      change that adds assertions. Update the floor value in **both** `ok` and `bad` message strings:
      a passing assertion printing the wrong number is a live defect this repository has shipped
      twice.
- [ ] Declare a plant for `WS1`, `WS2`, `WS3`, `WS4`, `WS6` and `WS8`. **Inspect what each plant
      actually produced** before believing the word "fired" (ADR-0090). `WS0`, `WS5` and `WS7` are
      denominator/prose guards — if a plant for one cannot be expressed as a single-line replacement,
      say so at the site rather than omitting it silently.
- [ ] Record which fences `WS1` names when it fails. That list is the work order for Tasks 4–7 and
      must match the ADR's population count of 41.

## Task 4 — Wrap the two argument fences that fail OPEN (R-02, R-04, R-08, R-09)

**Files:** `staging/plugin/skills/autopilot/SKILL.md`,
`staging/plugin/skills/project-conductor/SKILL.md`.
Budget: staging/plugin/skills/autopilot/SKILL.md, staging/plugin/skills/project-conductor/SKILL.md (~40 lines)

`autopilot-scope-args` and `conductor-step0-args` are the only two sites that fail **open**. They go
first because everything else fails closed and is therefore already visible.

- [ ] Wrap both bodies per ADR-0133 §D1. `autopilot-scope-args` has free variables `_args` and
      `_root`; `conductor-step0-args` has `_args`. Both are at column 0, so the terminator is
      naturally at column 0 — assert it anyway via `WS2`.
- [ ] **Rewrite the "UNQUOTED on purpose" comment.** It currently claims the unquoted expansion
      *"reproduces the word split the moved `set --` performed"*. Under zsh it reproduces nothing.
      The corrected comment must say the split is now guaranteed **by the wrapper**, and that the
      expansion stays unquoted for that reason. A comment asserting a mechanism that does not run is
      what let this survive from ADR-0129's first run.
- [ ] `SCOPE-PARSE:` and the exit vocabulary (`3` = did not run) are unchanged. Assert both fences'
      existing executions still pass with the same exit codes.
- [ ] Add an execution for `conductor-step0-args` if none exists, so `F4` stays satisfied and the
      second fail-open site is covered rather than merely repaired.

## Task 5 — Mark, wrap and execute the three `commit` fences (R-03, R-09)

**Files:** `staging/plugin/skills/commit/SKILL.md`,
`staging/plugin/scripts/tests/fence-contract-coverage.test.sh`.
Budget: staging/plugin/skills/commit/SKILL.md, staging/plugin/scripts/tests/fence-contract-coverage.test.sh (~120 lines)

- [ ] Add `<!-- fence-contract: … -->` markers to the three fences: the two `include_paths` loops
      and the H4 test-diff gate. Ids must be distinct and descriptive.
- [ ] Wrap all three. The first is indented 2 — **its terminator still goes to column 0.**
- [ ] Add one execution per new contract, **both directions** (a good fixture and the bad input the
      block exists to catch), or `F4` fails and the markers are a claim rather than a coverage.
- [ ] The H4 gate's execution must include the case this feature exists to fix: a changed set
      containing one test file and one non-test file, asserted to classify as **one of each**.
      Under the old shell it classified every file as a test file.
- [ ] `commit/SKILL.md` had no harness of its own before ADR-0071; these are among its first
      executed assertions. Do not assume a fixture helper exists — check.

## Task 6 — Wrap the remaining declared contracts (R-02, R-04, R-09)

**Files:** the declared contracts not covered by Tasks 4–5, across
`staging/plugin/skills/*/SKILL.md`.
Budget: staging/plugin/skills/autopilot-build/SKILL.md, staging/plugin/skills/autopilot/SKILL.md, staging/plugin/skills/concept-to-code/SKILL.md, staging/plugin/skills/project-conductor/SKILL.md, staging/plugin/skills/claude-md-slim/SKILL.md (~200 lines)

- [ ] Wrap each, with an `export` line derived from the body's free variables. **Use the corrected
      analyser** (measured fact 12): the design-time one missed `case`-arm assignments and
      over-reported five names on `c2c-step5-preflight-dirty-classify`. Over-listing a name is
      harmless; omitting one silently empties a variable inside the body.
- [ ] The nine indented fences take a column-0 terminator. Do not "tidy" it.
- [ ] Apply Task 1's outbound measurement: any fence binding a variable a later fence in the same
      step reads is rewritten to **print** it, and the consumer receives it as a placeholder the way
      `<manifest-path>` already is. Record each such rewrite in the ADR — it removes an implicit
      inter-block dependency nothing documented.
- [ ] The single `fence-illustration` stays an illustration and stays **unwrapped**.
- [ ] After each fence, re-run its existing execution and confirm the exit code and stdout token are
      byte-identical to before (R-09). This is the one place a wrapper can silently change a
      contract, and the whole-suite run at the end is not a substitute for the per-fence check.

## Task 7 — Wrap the six unmarked divergent fences (R-02, R-12)

**Files:** `staging/plugin/skills/claude-md-slim/SKILL.md`,
`staging/plugin/skills/concept-to-code/SKILL.md`,
`staging/plugin/skills/project-conductor/SKILL.md`.
Budget: staging/plugin/skills/claude-md-slim/SKILL.md, staging/plugin/skills/concept-to-code/SKILL.md, staging/plugin/skills/project-conductor/SKILL.md (~90 lines)

`claude-md-slim`@169 (`$DUP_ARGS`), `concept-to-code`@1865 and @1887 (`${_troot:+…}`), and
`project-conductor`@97/@324/@558 (the three copies of the date-anchored manifest glob).

- [ ] Wrap each. **They acquire no `fence-contract` marker** — they enter the population through the
      scanner, none of them is abort-capable (`F3` is green today, which is the proof), and marking
      them would create an execution obligation this feature did not budget. State that decision at
      the guard so the next reader does not read the absence as an oversight.
- [ ] `claude-md-slim`'s fix must be verified against its real consumer: `$DUP_ARGS` splitting into
      four words is what stops `content-union-check.sh` reading the whole string as its `<original>`
      positional (ADR-0044's usage error, produced by the shell rather than by a caller).
- [ ] The three `project-conductor` glob sites are **divergent in mechanism and equivalent in outcome
      today** — zsh declines to run `ls`, bash runs it against a literal pattern, both leave `_cand`
      empty behind `2>/dev/null`. Wrap them anyway and say so at the site, so nobody later reads the
      wrapper as fixing a symptom that was never observed.
- [ ] At the end of this task `WS1`–`WS4` go green. Confirm the population count matches 41 (or the
      number Task 1 measured) and that `WS4` reports an empty out-of-population set.

## Task 8 — The executed proof under the host shell, and its CI wiring (R-06, R-07)

**Files:** `staging/plugin/scripts/tests/fence-contract-coverage.test.sh`,
`.github/workflows/docs-ci.yml`.
Budget: staging/plugin/scripts/tests/fence-contract-coverage.test.sh, .github/workflows/docs-ci.yml (~70 lines)

A structural check proves a shape, not a behaviour. This is the behaviour.

- [ ] `WSA` — take one wrapped population fence, run it under **zsh** and under **bash** with the
      same fixture, and assert the stdout token and exit code are identical. Pick a fence whose body
      contains a measured divergence (`autopilot-scope-args` or `autopilot-check-6`), not an
      arbitrary one — a shell-agnostic fence would pass under any shell and pin nothing.
- [ ] `WSB` — the **negative twin**: the same body **unwrapped** must diverge between the two shells.
      Without it, `WSA` cannot distinguish a working wrapper from a fence that never diverged.
      A negative-case assertion pins nothing without its positive twin, and here the twin runs the
      other way round.
- [ ] If `zsh` is absent, report an explicit **`ZSH-ABSENT`** outcome and fail the assertion — never
      a silent skip. A check that did not run must never read as a check that found nothing; this is
      the CI-dark class ADR-0032 named and the SPEC's own edge case.
- [ ] Add a `zsh` install step to the `shell-tests` job in `.github/workflows/docs-ci.yml`, before
      the harness loop, so `ZSH-ABSENT` never fires in CI. **This is the only `docs-ci.yml` edit in
      this plan** — no harness name is added, because no new `*.test.sh` file is created.
- [ ] Record the live result — token and exit code, under both shells — in the ADR's *Verification*
      section, which currently carries a placeholder for it.

## Task 9 — End-to-end acceptance and the ADR's closing record (R-08, R-11)

**Files:** `docs/architecture/ADR-0133-394-fence-execution-shell.md`.
Budget: docs/architecture/ADR-0133-394-fence-execution-shell.md (~50 lines)

- [ ] Run `autopilot --features 1 --only 293 --dry-run` and assert the resolution is
      `source=arguments`, `features=1` and **exactly one** roadmap row. This is the symptom that
      opened the issue; a green guard is not a substitute for reproducing its absence.
- [ ] Record the observed output verbatim in the ADR's *Verification* section.
- [ ] Record R-11 as a finding rather than a footnote: the pre-#385 `set -- $_args` fails identically
      under zsh (`argc=1`), so **`--features` has never bounded a run on this machine**, from
      ADR-0129's first run onward. Any prior claim that a run was bounded is a claim about a
      mechanism that was not running, and the roadmap's Phase 11 notes should be read against it.
- [ ] Re-run the full suite plus `plant-check.sh` and confirm: every harness green, every declared
      plant fired, `skill-fence-positional-tokens.test.sh` green (R-10), and the assertion totals of
      `fence-contract-coverage.test.sh` and the three files whose floors were touched all match their
      stated floors.

---

## Risks

- **A wrapped fence that needs the caller's environment beyond its `export` list** silently reads an
  empty variable. The audit found none, and the audit is a floor. Mitigation: Task 6's per-fence
  re-run of the existing execution, and the corrected free-variable analyser.
- **The column-0 terminator reads as a formatting error** inside an indented fence. `WS2` is the
  only thing between it and a tidying pass that destroys an exit code.
- **`zsh` on the CI runner is an added dependency.** If the install step is removed, `WSA`/`WSB` fail
  with `ZSH-ABSENT` rather than passing quietly — the correct direction, but it will read as a
  regression the first time.
- **`F7`'s repair and the wrapper must land in the right order.** Task 2 before Task 4; reversing
  them opens a window where every contract passes its parse check unconditionally.
- **`commit/SKILL.md` is invoked by `concept-to-code` Step 7, `project-init` and
  `autopilot-build`.** Task 5 changes a file on three unattended paths; the H4 gate's behaviour
  change (from "everything is a test file" to a correct classification) will alter what those runs
  report on their first pass after this lands.
