# Implementation plan — Codex-vs-Claude backend choice for the tester subagent

- **Topic slug:** codex-claude-choice-for-tester
- **SPEC:** `/Users/stefer/emdash/worktrees/vibe-coding-system-19f4e0e7/emdash-tangy-queens-study-04d7g/SPEC.md`
  (R-01 … R-15; every id is cited by at least one task below, see §Requirement coverage)
- **ADR:** `docs/architecture/ADR-0194-codex-tester-choice.md` (Accepted 2026-09-06)
- **ARCH:** n/a — a scoped extension of an already-documented mechanism
  (ADR-0187 → ADR-0193 → this), not a new subsystem.
- **Stack:** Bash 3.2 (macOS `/bin/bash`) plus POSIX `grep`/`sed`/`awk`/`git`, and `python3` for
  JSON only. No `mapfile`, no bash associative arrays, no `${var^^}`, no `<<<`, no process
  substitution. Markdown reference docs and one YAML workflow file.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`

TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: sonnet

---

## Read this first — state measured 2026-09-06 at `fc2194c` (rule 13)

**Re-derive it; do not trust this block.** Every count here is a snapshot of the moment it was
taken, and this repo has been wrong on its own numbers more than once.

```text
manifest schema version written by manifest-init.sh:        "1.4"   (NOT 1.3 — the prose header
                                                                     at the top of concept-to-code/
                                                                     SKILL.md says 1.3; that is a
                                                                     pre-existing drift, OUT OF
                                                                     SCOPE, do not "fix" it)
highest Invariant in manifest-validate.sh:                   25      (use_codex_review = 24,
                                                                     step5_codex_review_asked = 25)
assertion prefix CX across staging/:                         FREE    (grep -rnoE '\bCX[0-9]+' -> 0)
assertion prefix CT across staging/:                         TAKEN   (13 hits — do not use it)
`effort: "xhigh"` in step5-implementation.md:                1 occurrence (the Workflow tester pin)
`| architect, coder, tester | xhigh |` effort-table row:     1 occurrence, same file
`effort: xhigh` in staging/plugin/agents/:                   3 files (architect.md, coder.md,
                                                                     tester.md) — only tester.md moves
PAIRS entries naming codex-reviewer.sh:                      1  (plugin/scripts/codex-reviewer.sh|
                                                                 hooks/codex-reviewer.sh)
codex CLI, verified live 2026-09-06:  `-s/--sandbox {read-only,workspace-write,danger-full-access}`,
                                      `-C/--cd <DIR>`, `--output-schema <FILE>`, `-o <FILE>` all exist
~/.codex/config.toml, live 2026-09-06:  model = "gpt-5.6-terra", model_reasoning_effort = "medium"
plant-check.sh discovers harnesses by glob (`"$TESTS"/*.test.sh`) — a NEW harness needs NO registration
docs-ci.yml's shell-test loop is a hand-maintained NAMED list — a new harness DOES need registering
markdownlint: docs/architecture IS linted (MD009/MD010 on); docs/superpowers is ignored
```

## Read this second — the observable contract that moves, and the call-site that asserts the old one

**One observable contract moves in an already-green test.** The grep was run; the call-site is
listed here, not left for the coder to discover.

```text
$ grep -rn 'effort: "xhigh"' staging/plugin/scripts/tests/
staging/plugin/scripts/tests/test-write-scope.test.sh:293:   && grep -qF 'effort: "xhigh"' "$STEP5" ...
```

`test-write-scope.test.sh`'s `TG1(workflow)` asserts the literal string `effort: "xhigh"` is present
somewhere in `step5-implementation.md`. There is exactly **one** such occurrence in that file (the
Workflow tester pin), so lowering it to `high` (R-14) turns `TG1` RED. Updating that needle is part
of this change, not collateral damage — it is the call-site that asserts the old contract.
**Task 1 owns that edit** (it is a test file; the coder is denied it by `test-write-scope.sh`), and
`TG1` is then legitimately RED from Task 1 until Task 6 lands the pin.

Two greps that came back **clean**, recorded so nobody re-runs them:

```text
$ grep -rn 'use_codex_tester\|step5_codex_tester_asked\|codex-tester' staging/ .github/   -> 0 hits
$ grep -rln 'agents/tester.md' staging/plugin/scripts/tests/
    test-write-scope.test.sh   agent-memory-contract.test.sh   run-hook-tests.sh
    (none of the three asserts tester.md's `effort:` line — only architect.md's is pinned, by
     agent-tool-scoping.test.sh's A8, and architect.md is not touched here)
```

**Run the FULL harness suite after Task 6, not just the new file.** A contract change in a file this
central can break assertions in modules that share it; `TG1` is the one we found, and the sweep is
what proves there is no second one.

## Read this third — two things that are NOT this feature's failures, and must not be "fixed"

1. **`concept-to-code/SKILL.md`'s prose header says schema `1.3` while `manifest-init.sh` writes
   `"1.4"`.** Pre-existing drift, confirmed live. Out of scope (SPEC "Out of scope" is silent on it,
   and correcting it here would put an unrelated diff in front of Gate 5). Leave it.
2. **`spec-coverage.sh` will report `R-11` as `COVERED` no matter what this plan does.**
   `test-write-scope.test.sh` carries its own unrelated `R-11` token and names ADR-0049/ADR-0068,
   which this plan also cites — so that file is in scope and its `R-11` is a foreign match
   (CLAUDE.md rule 18, ADR-0138). Our own `R-11` coverage is real (Task 1's `CX16`–`CX18`), but
   **do not read the tool's `COVERED` verdict as the evidence for it.**

Also expected, and not a defect: once the chain archives this SPEC to `docs/specs/`, the new
(spec, plan) pair makes `spec-coverage.test.sh`'s `RS7`/`RS8a` diverge from the frozen
`spec-coverage-scope-baseline.tsv`. That baseline is bumped by Step 7.0b's `c2c-step7-baseline-bump`
fence (ADR-0166), **never by hand**, and `RS7` is never weakened to accommodate it.

## Read this fourth — the design in one paragraph, so no task re-derives it

A new Bash script `codex-tester.sh` shells `codex exec -s workspace-write -C <worktree>` with a
prompt hand-ported from `tester.md`, constrains the reply with `--output-schema`, formats it into
`tester.md`'s six-field markdown at `--out`, and is a CHECKER: exit 0 success / 2 bad invocation /
3 DID-NOT-RUN / **4 wrote outside test scope**. Exit 4 comes from a post-run comparison of the
worktree's touched-path set (diff ∪ staged ∪ untracked, minus a pre-run baseline) against a
test-file name/path heuristic. One `AskUserQuestion` in Step 5, before the Workflow/Agent-tool
branch, chooses `claude-sonnet` (default) / `codex` / `claude-opus`, gated once per manifest on a
new `step5_codex_tester_asked` field and recording `use_codex_tester`. On the `codex` branch **both**
dispatch paths run the script in the orchestrator's own live turn — the Workflow path drops its
tester stage from `pipeline()` entirely, because a Workflow stage cannot `AskUserQuestion` and a
tester, unlike a reviewer, cannot be skipped (ADR-0194 §Refinements R5). Independently of all of
that, the tester's Claude effort pin drops `xhigh` → `high` at three sites.

## Files this plan touches

| File | Task | Owner |
| --- | --- | --- |
| `staging/plugin/scripts/tests/codex-tester-dispatch-gate.test.sh` (NEW) | 1, 7 | tester |
| `staging/plugin/scripts/tests/codex-reviewer-schema.test.sh` | 1, 7 | tester |
| `staging/plugin/scripts/tests/test-write-scope.test.sh` | 1 | tester |
| `staging/plugin/scripts/codex-tester.sh` (NEW) | 2 | coder |
| `staging/sync-to-claude.sh` | 2 | coder |
| `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh` | 3 | coder |
| `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` | 3 | coder |
| `staging/plugin/skills/concept-to-code/references/step5-implementation.md` | 4, 5, 6 | coder |
| `staging/plugin/agents/tester.md` | 6 | coder |
| `.github/workflows/docs-ci.yml` | 7 | coder |
| `docs/architecture/ADR-0194-codex-tester-choice.md` | 8 | doc-writer |

Tasks 4, 5 and 6 all edit `step5-implementation.md`. They are deliberately in **one batch** so a
single coder applies them in order — never split across a `parallel()` batch (Step 5's own
file-conflict scan would sequence them anyway; this just makes the intent explicit).

## Assertion ids and the harness contract

New harness: `staging/plugin/scripts/tests/codex-tester-dispatch-gate.test.sh`, prefix **`CX`**
(verified free 2026-09-06), ids **fixed-width two digits** `CX01`…`CX30` — never `CX1` beside
`CX10`, because `plant-check.sh` decides "fired" with a `^FAIL: <id>` **prefix** match.

The header block states, verbatim and in this order: `ADR-0194`; this plan's full path
(`docs/superpowers/plans/2026-09-06-codex-claude-choice-for-tester.md`) — both literals are what
keeps `spec-coverage.sh` from descoping the file (ADR-0154); that the section covers SPEC
**R-01, R-02, R-03, R-05, R-06, R-07, R-08, R-09, R-10, R-11, R-12, R-13, R-14**; that the prefix
`CX` was verified free on 2026-09-06; and that every assertion is RED by construction until Tasks
2–6, so a red at the Batch A checkpoint is the deliverable.

**Never write the tokens `R-04` or `R-15` anywhere in any test file.** Both carry a
`(no-test: …)` waiver in SPEC.md, and `spec-coverage.sh` reports `STALE-WAIVER` and **exits 3**
— blocking Step 5 → Step 6 — the moment a waived id's token appears in a scoped test file. They are
covered by plan tasks (2 and 8) and by nothing else, which is exactly what the waiver means.

Hermeticity, non-negotiable: **no assertion may invoke the real `codex` CLI.** Behavioural
assertions run the script against a **stub `codex`** written into a scratch `PATH` directory, inside
a scratch `git init` repository under `mktemp -d`. This repo never spends Codex quota in CI
(`codex-reviewer-schema.test.sh` header states the same rule).

## Batching

| Batch | Tasks | Expected state at the checkpoint |
| --- | --- | --- |
| A | 1 | every `CX*` RED; `TG1` RED (needle updated, pin not yet lowered) |
| B | 2, 3 | `CX01`–`CX18` GREEN; `CX19`–`CX30` still RED; `TG1` still RED |
| C | 4, 5, 6 | `CX19`–`CX30` GREEN; `TG1` GREEN; full harness suite green |
| D | 7 | harness registered in CI, `Z1` floors bumped, plants all seen RED |
| E | 8 | ADR verified/appended, `spec-coverage.sh` clean |

Task 1 must not share a batch with Tasks 2–6 (ADR-0101 rule 1 — an assertion must not share a batch
with the task it depends on).

---

## Task 1 — TEST: the whole `CX` section RED, plus the one stale call-site (R-01, R-02, R-03, R-05, R-06, R-07, R-08, R-09, R-10, R-11, R-12, R-13, R-14)

Owner: **tester**. Three test files, all tester-owned. Anchor-preserving: `codex-reviewer-schema.test.sh`
and `test-write-scope.test.sh` are **extended in place**, never rewritten — do not renumber or
reflow their existing assertions, several of which are pinned by name elsewhere.

**1a. New harness `staging/plugin/scripts/tests/codex-tester-dispatch-gate.test.sh`.** Shape it on
`codex-review-dispatch-gate.test.sh`: `#!/bin/bash`, `set -u`, `SCRIPTS=$(cd "$(dirname "$0")/.." &&
pwd)`, `ok()`/`bad()` counters, a `FATAL:` guard for missing input files, a trailing
`PASS=$PASS FAIL=$FAIL` line, a `Z1` vacuity floor, `[ "$FAIL" -eq 0 ]` as the last line.

Helper both behavioural sections use, defined once (rule 6):

```bash
# make_stub_codex <dir> <auth-status> <exec-behaviour-script>
# Writes an executable `codex` into <dir> that answers `doctor --json` with the given
# auth.credentials status and, on `exec`, runs <exec-behaviour-script> with the parsed
# -C/-o values in $CT_CD/$CT_OUT and records its own argv to <dir>/argv.txt.
```

Assertions, grouped. Every count guard is an **exact** count, never a floor (rule 10) — the
populations here are frozen at 1 or 2 and a floor would absorb its own plant:

- [ ] `CX01` (R-01) — `staging/plugin/scripts/codex-tester.sh` exists and is a readable file.
- [ ] `CX02` (R-01) — `staging/sync-to-claude.sh` carries the exact PAIRS line
      `plugin/scripts/codex-tester.sh|hooks/codex-tester.sh`, exactly once (rule 17: a script no
      PAIRS line deploys is a script the dispatch sites name and nobody installs — the VCS-063
      lesson, found live on `codex-reviewer.sh`'s own call sites).
- [ ] `CX03` (R-02) — the script's `codex exec` invocation carries **both** `-s workspace-write` and
      `-C "$WORKTREE"`. Extract the invocation (the `codex exec` line plus its `\`-continuations)
      with awk and match inside that slice only — a needle matched against the whole file would be
      satisfied by the header comment that *explains* the flag (rule 1).
- [ ] `CX04` (R-02) — that same extracted slice contains neither `danger-full-access` nor
      `read-only`. Scoped to the slice for the same reason: the header comment legitimately names
      `read-only` when contrasting with `codex-reviewer.sh`.
- [ ] `CX05` (R-03) — **behavioural.** With `PATH` set to a directory containing no `codex`, running
      the script exits **3** and prints a line matching `^codex-tester: DID-NOT-RUN:` on stderr.
      Precondition guard first (rule 4): assert `command -v codex` really is unresolvable under that
      `PATH`; if it resolves, report the assertion as DID-NOT-RUN rather than as a pass. Build the
      `PATH` as `<stub-dir>:/usr/bin:/bin` (never an empty `PATH` — the script needs `dirname` and
      `git`), and capture the interpreter's absolute path first
      (`real_bash=$(command -v bash)`) so the `VAR=value cmd` form does not resolve `bash` through
      the `PATH` being replaced.
- [ ] `CX06` (R-03) — **behavioural.** Stub `codex` answering `doctor --json` with
      `auth.credentials.status = "error"` → exit **3**, stderr names the status.
- [ ] `CX07` (R-05) — **behavioural, the assertion R-05 exists for.** Stub whose `exec` creates a
      **new, untracked** `src/prod.py` and a `tests/test_a.py` inside the scratch worktree and
      writes a valid schema JSON to `-o` → exit **4**, and `src/prod.py` appears on stderr.
      A `git diff --name-only`-only implementation passes `CX08` and fails here, which is the point.
- [ ] `CX08` (R-05) — **behavioural.** Same stub writing only `tests/test_a.py` → exit **0**, and
      `--out` exists and is non-empty.
- [ ] `CX09` (R-05) — **count guard on the derived population** (rule 7). In the `CX07` fixture,
      assert the touched-path set the script computes has exactly 2 members before believing the
      exit-4 verdict; in the `CX08` fixture, exactly 1. Zero candidates and "all candidates are test
      files" are indistinguishable from the exit code alone. Read the set from the script's own
      stderr summary line, not by re-deriving it in the harness (two derivations that could
      disagree are the defect).
- [ ] `CX10` (R-05) — **behavioural.** Stub that *modifies an already-tracked* `src/prod.py` (the
      `git diff` half of the union) → exit **4**. Pairs with `CX07` so neither half of the union can
      be dropped without a red.
- [ ] `CX11` (R-05) — **behavioural.** Stub that writes nothing at all → exit **0** plus a
      `codex-tester: NOTE:` line on stderr naming the empty touched-path set. "Wrote nothing" and
      "wrote only tests" must not collapse into one signal (rule 4).
- [ ] `CX12` (R-06) — **behavioural.** Invoked with `--effort high`, the stub's recorded argv
      contains `-c model_reasoning_effort=high`.
- [ ] `CX13` (R-06) — **behavioural.** Invoked with no `--effort`, the recorded argv contains no
      `model_reasoning_effort` substring at all (omitted entirely, so `~/.codex/config.toml`
      governs — not passed as an empty value).
- [ ] `CX14` (R-03) — **behavioural.** Bad invocations exit **2**, one case each: unknown flag,
      missing `--worktree`, missing `--out`, unreadable `--brief`. Four sub-checks, one assertion id.
- [ ] `CX15` (R-03) — **drift guard, ADR-0194 §Refinements R7.** The rate-limit vocabulary regex and
      the `[ -s "$RAW_OUT" ]` precedence check appear in **both** `codex-reviewer.sh` and
      `codex-tester.sh`, byte-identical on the regex. This is the VCS-064 correction, and it is
      exactly the kind of fix that gets applied to one copy and not the other.
- [ ] `CX16` (R-10) — `manifest-init.sh` contains `echo "use_codex_tester: false" >> "$T"`.
- [ ] `CX17` (R-10) — `manifest-init.sh` contains
      `echo "step5_codex_tester_asked: false" >> "$T"`.
- [ ] `CX18` (R-11) — **behavioural, end to end.** Run `manifest-init.sh` into a temp dir; assert
      `manifest-validate.sh` accepts it; assert the file still carries
      `manifest_schema_version: "1.4"` (no version bump); flip each field to `true` via
      `manifest-set-flag.sh` and re-validate; then set each to `maybe` and assert validation fails
      **naming the offending field** (Invariants 26 and 27, one sub-check each).
- [ ] `CX19` (R-07, R-08) — `step5-implementation.md` carries the heading
      `#### Codex tester backend for Step 5 dispatch (ADR-0194, both paths)`, matched **line-wise**
      (a heading is a structural marker — rule 3 keeps those line-wise).
- [ ] `CX20` (R-07, R-08) — slice that block with awk (from its heading to the next `^#### `, the
      same idiom `codex-review-dispatch-gate.test.sh`'s `D_BLOCK` uses) and assert the ask offers
      all three of `claude-sonnet`, `codex`, `claude-opus` **inside the slice**. A 1800-line file
      contains those words elsewhere; the slice is what makes the assertion about this block.
- [ ] `CX21` (R-07, R-08) — same slice: the ask fires once, **before** the Workflow/Agent-tool
      branch, so one ask covers both dispatch paths. Match the flattened, undecorated clause
      (rule 3), not a physical line.
- [ ] `CX22` (R-07, R-08) — same slice: an autopilot-skip clause is present.
- [ ] `CX23` (R-12) — same slice: gates on `manifest.step5_codex_tester_asked`, not on
      `use_codex_tester` alone, **and** the write of `step5_codex_tester_asked true` is stated as
      unconditional on the answer. Two sub-checks, one id — the second is what R-12 actually asks
      for and the first alone would pass without it.
- [ ] `CX24` (R-09) — the exit-code handling section
      `#### Codex tester exit-code handling (ADR-0194)` exists **exactly once**, line-wise, and its
      slice names all four of exit `0`, `2`, `3`, `4`.
- [ ] `CX25` (R-09) — the slice's exit-3 and exit-4 branches each carry an `AskUserQuestion`, and
      the exit-4 branch offers the three-way fallback / accept / halt. A silent fallback is the one
      outcome the reviewer contract forbids and this is where it would be introduced.
- [ ] `CX26` (R-09) — **exactly 2** dispatch sites carry the pointer literal
      `branch per \`#### Codex tester exit-code handling\` above (ADR-0194)`. Exact count: the
      population is frozen at 2 (Workflow path, Agent-tool path) and a dropped site would still
      show a non-zero count.
- [ ] `CX27` (R-09, R-01) — **exactly 2** lines name the deployed path
      `~/.claude/hooks/codex-tester.sh` together with `--worktree` (rule 17: the path PAIRS actually
      deploys to, not a plausible `~/.claude/scripts/` one — the exact defect found live on the RTF
      sites on 2026-09-06).
- [ ] `CX28` (R-13) — `staging/plugin/agents/tester.md` frontmatter line reads exactly
      `effort: high`, matched line-wise against the frontmatter block (not a substring search:
      `effort: high` is a substring of nothing else here, but the frontmatter is structure).
- [ ] `CX29` (R-14) — in `step5-implementation.md`: the Workflow tester pin reads `effort: "high"`,
      **and** the count of `effort: "xhigh"` in that file is exactly **0**. The second half is what
      makes this assertion about the change rather than about an addition.
- [ ] `CX30` (R-14) — the effort table no longer lists `tester` on its `xhigh` row, **and** the
      Tester batch dispatch template still states that no `effort` is pinned there (the Agent-tool
      path is deliberately unchanged — an over-eager edit adding `effort` to it is a real risk,
      because the Agent tool has no such parameter at all).
- [ ] `Z1` — vacuity floor, `>= 30`.

**Plants** (`# plant: <id> | <staging-relative path> | <needle> | <replacement>`, column 1, declared
beside the assertion they belong to). Every one of these must be seen RED before it is trusted;
`plant-check.sh` reports `NOFIRE` for a declaration whose assertion stays green. Minimum set:

```text
CX02  plugin/../sync-to-claude.sh is NOT under staging/plugin — target `sync-to-claude.sh` directly
CX03  plugin/scripts/codex-tester.sh   | -s workspace-write | -s read-only
CX07  plugin/scripts/codex-tester.sh   | ls-files --others --exclude-standard | ls-files --cached
CX15  plugin/scripts/codex-tester.sh   | (the rate-limit regex)      | (a shortened regex)
CX16  plugin/skills/concept-to-code/scripts/manifest-init.sh     | echo "use_codex_tester: false" >> "$T" | :
CX18  plugin/skills/concept-to-code/scripts/manifest-validate.sh | fail "use_codex_tester field present but value is not 'true' or 'false'" | :
CX19  plugin/skills/concept-to-code/references/step5-implementation.md | #### Codex tester backend for Step 5 dispatch (ADR-0194, both paths) | #### REMOVED FOR PLANT
CX26  plugin/skills/concept-to-code/references/step5-implementation.md | (one of the two pointer literals) | (the same line with the pointer removed)
CX29  plugin/skills/concept-to-code/references/step5-implementation.md | effort: "high" | effort: "xhigh"
```

A plant replacement may not contain the literal ` | ` — `plant-check.sh` splits declarations on it
and a five-field line is `BADPLANT`, not a plant. `.github/` is not a legal plant target
(ADR-0151 §D11), which is why no assertion here reads `docs-ci.yml`.

**1b. `codex-reviewer-schema.test.sh` — one new assertion, in place.** Add `S3`: extract
`codex-tester.sh`'s `SCHEMA_EOF` heredoc with the file's existing `extract_schema`-shaped awk and
run it through the existing `check_schema` walker (rule 6 — reuse the walker, do not copy it into
the new harness). Parameterise `extract_schema` to take a file path, keeping `S1`/`S2`'s behaviour
byte-identical. Bump that file's `Z1` floor from `>= 2` to `>= 3`. Plant for `S3`:
`plugin/scripts/codex-tester.sh | "additionalProperties": false | "additionalProperties": true`.
This is the `invalid_json_schema` trap that cost ADR-0187 a live probe.

**1c. `test-write-scope.test.sh` — the stale call-site.** Change `TG1(workflow)`'s needle from
`effort: "xhigh"` to `effort: "high"` and update the assertion's message text to match. Change
nothing else in that file. This is not disabling a test: it is re-pointing an assertion at the
contract that replaces the one it was written for, and it is RED from this task until Task 6.

Budget: `staging/plugin/scripts/tests/codex-tester-dispatch-gate.test.sh`, `staging/plugin/scripts/tests/codex-reviewer-schema.test.sh`, `staging/plugin/scripts/tests/test-write-scope.test.sh` (~470 lines)

## Task 2 — CODE: `codex-tester.sh` and its PAIRS entry (R-01, R-02, R-03, R-04, R-05, R-06)

Owner: **coder**. New file `staging/plugin/scripts/codex-tester.sh`, plus exactly one line added to
`staging/sync-to-claude.sh`'s PAIRS block.

Structure it on `codex-reviewer.sh` and keep its conventions even where they differ from the global
shell rule: `#!/bin/bash` and `set -u`, **not** `set -euo pipefail`. That is deliberate and
load-bearing — this script's whole contract is classifying a non-zero `codex exec` exit into 3
versus 4, and `set -e` would abort before the classification runs.

- Header comment states, in this order: what it is and why it exists; the CHECKER contract
  (exit 0/2/3/**4**, "the caller branches on the exit code, never on whether stdout is empty",
  rule 5); the declared prompt duplication from `tester.md` with the drift warning; the declared
  cascade duplication from `codex-reviewer.sh` with a pointer to ADR-0194 §Refinements R7 and the
  note that extraction to a shared helper is a named follow-up; "sandbox as enforcement" (rule 16);
  and the live-verified `codex exec` flag shape with its 2026-09-06 date (rule 13).
- Flags: `--worktree <dir>` (required), `--brief <file>` (required, must be readable),
  `--out <file>` (required), `--effort <value>` (optional). Anything else → exit 2 with one line on
  stderr, `codex-tester: ` prefixed.
- Availability cascade, in order, each exiting 3 with `codex-tester: DID-NOT-RUN: <reason>`:
  `command -v codex`; `codex doctor --json` produced output and `python3` exists to parse it;
  `.checks["auth.credentials"].status == "ok"`; `git -C "$WORKTREE" rev-parse --is-inside-work-tree`.
- **Baseline capture, before any `codex exec`:** write the worktree's current touched-path set to a
  temp file. The set is the sorted union of `git -C "$WT" diff --name-only`,
  `git -C "$WT" diff --name-only --cached`, and
  `git -C "$WT" ls-files --others --exclude-standard`. Pre-existing dirt must never be attributed
  to Codex.
- Schema (`--output-schema`) with six properties matching `tester.md`'s Output Format:
  `tests_added` (array of objects: `path`, `covers`), `run_result` (object: `command`, `passed`,
  `failed`), `coverage` (string), `bugs_found` (array of objects: `description`, `reproduction`),
  `requirement_ids_covered` (array of strings), `sub_steps` (object: `executed`,
  `left_to_coder`, both arrays of strings). **`"additionalProperties": false` on every object**
  including nested ones and array `items` — without it the call fails `invalid_json_schema` before
  the model runs.
- Prompt, hand-ported from `tester.md`, embedding the `--brief` file's contents. It must state:
  never modify production code, only test files; write failing tests for the requirement IDs /
  Success Criteria / plan task text the brief carries, never from implementation files; detect the
  project's test framework and run the suite; report the exact command and pass/fail counts; return
  all six fields. **This is R-04, and it is verified by reading this prompt text, not by a parser —
  no validator asserts the six sections in the emitted markdown, deliberately (ADR-0194 §R1).**
- Invocation: `codex exec -s workspace-write -C "$WORKTREE" [ -c model_reasoning_effort="$EFFORT" ]
  --output-schema "$SCHEMA_FILE" -o "$RAW_OUT" "$(cat "$PROMPT_FILE")"`. Build the optional
  `-c` pair as two positional arguments appended to a plain array (bash 3.2: indexed arrays are
  fine, associative are not), never by string-splitting a variable. No `-m` — see ADR-0194 §R2.
- Failure classification after `codex exec`, in this order — **the order is the VCS-064 fix and must
  not be rearranged**: a non-empty `$RAW_OUT` wins first; only if it is empty does the rate-limit
  vocabulary grep on stderr run; otherwise "produced no output". Copy `codex-reviewer.sh`'s regex
  byte-for-byte (`CX15` pins this).
- **Scope check.** Recompute the touched-path union, subtract the baseline, and classify each
  remaining path. A path is a **test file** if any path component is `tests`, `test`, `spec`,
  `__tests__` or `Tests`, or its basename matches `test_*`, `*_test.*`, `*.test.*`, `*.spec.*`,
  `*Tests.swift`, `*Test.java`, or is `conftest.py`. Everything else is production.
  - Any production path → write `--out` anyway (a partial report is more useful than none), print
    `codex-tester: SCOPE-VIOLATION: <paths>` on stderr, exit **4**.
  - Empty set → print `codex-tester: NOTE: no file changes detected in <worktree>` and continue to
    exit 0. Not a fifth exit code; the contract is fixed at 0/2/3/4.
  - Print a one-line summary of the touched-path set on stderr in every case — `CX09` reads it
    rather than re-deriving the set, so that the harness and the script cannot disagree about the
    denominator.
- Format the schema JSON into `tester.md`'s six-field markdown at `--out` with a `python3 -c`
  block, same shape as `codex-reviewer.sh`'s formatter, and exit 0.
- PAIRS: add `plugin/scripts/codex-tester.sh|hooks/codex-tester.sh` immediately after the
  `codex-reviewer.sh` line. **Without it `pairs-completeness.test.sh` goes RED in the reverse
  direction** (ADR-0043: every file in a covered staging subtree must appear as a PAIRS src) — and
  the script the Step 5 sites name would never be installed.

Budget: `staging/plugin/scripts/codex-tester.sh`, `staging/sync-to-claude.sh` (~290 lines)

## Task 3 — CODE: the two manifest fields (R-10, R-11)

Owner: **coder**. `manifest-init.sh` and `manifest-validate.sh`, in lockstep (rule 17).

- `manifest-init.sh`: two `echo` lines seeding `use_codex_tester: false` and
  `step5_codex_tester_asked: false`, placed immediately after the existing
  `step5_codex_review_asked` line. Do not touch `manifest_schema_version: "1.4"` — the fields are
  additive and conditional, exactly as the reviewer's pair was (ADR-0194 §R3).
- `manifest-validate.sh`: **Invariant 26** (`use_codex_tester` present → must be `true`/`false`) and
  **Invariant 27** (`step5_codex_tester_asked` present → must be `true`/`false`), appended after
  Invariant 25, copying Invariants 24/25's structure line for line including the `grep -q` presence
  test before the `grep -Eq` value test. The failure message must **name the field**, because
  `CX18` asserts the field name appears in the rejection text.
- Invariant 27's comment carries the same three-state reasoning as 25: seeded-false and
  declined-false are indistinguishable, which is why a second field exists at all.

Budget: `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh`, `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` (~40 lines)

## Task 4 — CODE: the Step 5 backend ask, once, covering both paths (R-07, R-08, R-12)

Owner: **coder**. `step5-implementation.md` only. Insert a new `#### ` block immediately after the
existing `#### Codex review backend for Step 5 checkpoints (ADR-0193, conditional…)` block and
before `#### Workflow dispatch path`. Anchor-preserving: do not reflow or renumber the review
block — `codex-review-dispatch-gate.test.sh`'s `D1`/`D2`/`D3` slice it by heading.

Heading, exactly: `#### Codex tester backend for Step 5 dispatch (ADR-0194, both paths)`

The block states:

- **Unlike the review ask, this one is not conditional on `step5_review_mode`** — the tester
  dispatch is unconditional on both paths, so the ask is too.
- Gate on `manifest.step5_codex_tester_asked`, not on `use_codex_tester` itself, with the same
  three-state reasoning spelled out (seeded-false and declined-false are the same value).
- The ask fires once, in the orchestrator's own live turn, **before the Workflow/Agent-tool branch
  below, so one ask covers both dispatch paths** — the same placement the review ask uses.
- `AskUserQuestion` options: `[claude-sonnet]` "Claude tester at sonnet (current behaviour)
  (Recommended)" / `[codex]` "Codex CLI, sandboxed to the worktree, with a gate if it is
  unavailable" / `[claude-opus]` "Claude tester at opus".
- `[codex]` → `manifest-set-flag.sh <manifest> use_codex_tester true`. The other two leave it at its
  seeded `false`.
- **Either way**, then `manifest-set-flag.sh <manifest> step5_codex_tester_asked true` — stated
  explicitly as unconditional on the answer, which is what makes the gate fire ONCE per manifest
  rather than once per decline (R-12).
- The Claude model choice is **turn-local**: it governs this Step 5 run only, is not persisted, and
  a later resumed run on the same manifest does not re-ask and dispatches at `sonnet`. State this
  as a disclosed limit with its remedy named (a `step5_tester_model` field, ADR-0194 §R8) — do not
  add the field.
- The ask does not fire under `--autopilot`; unattended runs keep `use_codex_tester` at `false` and
  leave `step5_codex_tester_asked` at `false` too, so a later attended run still gets asked once.
  This is an instruction, not an enforcement (rule 16) — say so.

Budget: `staging/plugin/skills/concept-to-code/references/step5-implementation.md` (~55 lines)

## Task 5 — CODE: the codex branch at both dispatch sites, and the exit contract stated once (R-09)

Owner: **coder**. `step5-implementation.md` only. Anchor-preserving throughout: the existing Claude
dispatch text is wrapped in an `Otherwise (default …)` branch **byte-preserved**, exactly the way
ADR-0187 wrapped the five reviewer sites. Do not rewrite it.

**5a. One resolution site for the exit contract** (rule 6 — the same "stated once, referenced
twice" idiom as `#### Merge-back and base-fork audit`). New section, heading exactly
`#### Codex tester exit-code handling (ADR-0194)`, placed near the merge-back block:

- exit `0` → read `--out` as the tester's report, exactly as if the Claude `tester` had produced it.
- exit `2` → bad invocation. Report the stderr line and halt this dispatch; it is a defect in the
  orchestrator's own arguments, never a reason to fall back.
- exit `3` → DID-NOT-RUN. `AskUserQuestion`: "Fallback to the Claude `tester` at `sonnet`
  (Recommended)" / "Halt the chain". **Never a silent fallback.**
- exit `4` → wrote outside test scope. Name the offending paths from stderr, then
  `AskUserQuestion`: "Fallback to the Claude `tester`, discarding Codex's work (Recommended)" /
  "Accept the out-of-scope write and continue" / "Halt the chain". The heuristic can false-positive
  on a shared fixture; the operator decides, not the script.
- State that a Workflow `pipeline()` stage has no `AskUserQuestion` hook at all, which is **why**
  both branches below run in the orchestrator's live turn.

**5b. Workflow path — `**Stage 1 — tester.**`.** Add, before the existing Stage 1 text:

> **If the Step 5 tester backend ask above resolved to `codex` (`manifest.use_codex_tester = true`,
> ADR-0194):** do **not** put a tester stage in `pipeline()` at all. Before writing the workflow
> script, for each task group in turn, in this same live turn: materialize the brief with
> `step5-brief.sh` exactly as below; `git worktree add` a worktree for the group; run
> `~/.claude/hooks/codex-tester.sh --worktree <wt> --brief <brief> --out <report>`;
> branch per `#### Codex tester exit-code handling` above (ADR-0194); then run
> `#### Merge-back and base-fork audit` with `$WT`/`$WB` taken from the `git worktree add` you just
> issued — known by construction here, not enumerated out of `git worktree list` (F19). Only then
> write the workflow script, with stages **coder** (plus the optional reviewer), one fewer stage
> than the default. This is sequential where the Claude branch is parallel: a real wall-clock cost,
> taken deliberately, because a tester that cannot report its own failure is worse than a slow one
> (ADR-0194 §Refinements R5).

Then `**Otherwise (default — `use_codex_tester` absent or `false`):**` and the existing Stage 1 text
unchanged apart from Task 6's effort edit.

**5c. Agent-tool batch path — `**Tester batch dispatch template**`.** Same wrap. The codex branch
already runs in the live turn, so it is shorter: create the batch worktree with `git worktree add`,
run the same command, `branch per \`#### Codex tester exit-code handling\` above (ADR-0194)`, merge
back via the same block with `$WT`/`$WB` from the `git worktree add`. The `Otherwise` branch is
today's Agent dispatch template, byte-preserved — **including its "no `effort` pin" note**, which
stays true and must not be edited.

Both branches carry the same brief the Claude tester receives, and neither passes implementation
files (ADR-0049 §D1, ADR-0088 — generator/verifier separation applies to Codex identically).

Budget: `staging/plugin/skills/concept-to-code/references/step5-implementation.md` (~90 lines)

## Task 6 — CODE: lower the tester's Claude effort pin, all three sites (R-13, R-14)

Owner: **coder**. Unconditional — this applies whether or not the ask in Task 4 ever fires, and on
every backend.

- `staging/plugin/agents/tester.md` frontmatter: `effort: xhigh` → `effort: high` (R-13). Touch
  nothing else in that file; `architect.md` and `coder.md` keep `xhigh`.
- `step5-implementation.md`, Workflow Stage 1 pin: `effort: "xhigh"` → `effort: "high"` (R-14).
  After this edit the string `effort: "xhigh"` must not occur anywhere in the file — `CX29` checks
  the count is 0.
- `step5-implementation.md`, the effort table: move `tester` off the `xhigh` row.
  `| architect, coder, tester | xhigh |` becomes `| architect, coder | xhigh |`, and `tester` joins
  the `high` row: `| reviewer, debugger, tester | high |`. **The SPEC enumerates only the first two
  sites; this third one is required anyway** — the table's own adjacent sentence says it is "the
  second place to update… a mismatch here silently overrides the file", so leaving it would make
  the change self-cancelling (ADR-0194 §Refinements R6). Nothing asserts this row today, which is
  precisely why it was about to be missed.
- The Agent-tool batch path is **left alone**: it already omits `effort` because the Agent tool has
  no such parameter (ADR-0068 §D7). Do not add one.

After this task `TG1` in `test-write-scope.test.sh` goes green, and the **full** harness suite must
be re-run — not just the new file (see §Read this second).

Budget: `staging/plugin/agents/tester.md`, `staging/plugin/skills/concept-to-code/references/step5-implementation.md` (~12 lines)

## Task 7 — CODE: register the harness in CI and confirm the plants fire (R-01, R-05, R-09, R-11, R-14)

Owner: **coder** for the registration; the plant sweep is verification.

- `.github/workflows/docs-ci.yml`: append `codex-tester-dispatch-gate` to the `for t in …` shell-test
  list, after `codex-review-dispatch-gate`. One token, one line, nothing else in that file. **No
  harness asserts this registration** — `.github/` is not a legal plant target (ADR-0151 §D11), the
  same exemption `pairs-completeness.test.sh`'s `CI1` already declares — so it is verified by grep
  and by the next CI run, and its absence is a known blind spot rather than a covered one. This is
  the same defect class that shipped twice before on this feature's own predecessors (VCS-058: a new
  harness unregistered in `docs-ci.yml`, a new script unregistered in PAIRS).
- Run the full plant sweep: `bash staging/plugin/scripts/tests/plant-check.sh`. Every declared
  `CX*` plant and the new `S3` plant must fire; a `NOFIRE` means the assertion pins nothing (rule 2)
  and a `BADPLANT` means the declaration itself is malformed. **Inspect what the sweep actually
  printed** — do not trust the exit code alone (rule 2, ADR-0090).
- Bump `Z1` in `codex-tester-dispatch-gate.test.sh` only if the final assertion count differs from
  the `>= 30` written in Task 1; never lower it.

Budget: `.github/workflows/docs-ci.yml` (~1 line)

## Task 8 — DOC + verify: ADR-0194 final state and the whole-suite sweep (R-15)

Owner: **doc-writer** for the ADR; verification is the orchestrator's.

- Confirm `docs/architecture/ADR-0194-codex-tester-choice.md` reads `Status: Accepted` and carries
  the eight refinements R1–R8 and the six alternatives. It was written to that state before this
  plan; this task is the check that it still is, and the place to record divergence.
- If the implementation diverged from any refinement, append a dated `## Correction` section —
  **never edit the decision text above it** (rule 14). The ADR is not yet committed history until
  Step 7, but the habit is the rule.
- Confirm the ADR's deferred live dry run is still recorded as outstanding. It is **not** run here:
  it spends real Codex quota and writes files, so it is a manual, attended step, and the codex
  branch is not trusted in a real chain run until it has happened.
- Run, and read the output of, in this order: the full harness suite
  (`for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`);
  `bash staging/plugin/scripts/tests/plant-check.sh`; `npx markdownlint-cli2` (the ADR is under
  `docs/architecture/`, which **is** linted — MD009/MD010 are on; this plan under
  `docs/superpowers/` is not);
  `spec-coverage.sh --spec SPEC.md --plan docs/superpowers/plans/2026-09-06-codex-claude-choice-for-tester.md --tests-root .`.
- `spec-coverage.sh` must not report `STALE-WAIVER`. If it does, a test file has acquired the token
  `R-04` or `R-15` — remove it from the test file; never delete the waiver from SPEC.md to silence
  the checker.

Budget: none (documentation check and verification only)

## Risks, dependencies and HITL gates

- **The live dry run is deferred and the feature is not trustworthy until it happens.** ADR-0187's
  own deferred probe found a real defect (`additionalProperties`) that no offline harness caught.
  Two specific things this plan cannot verify offline: whether `codex exec -s workspace-write` can
  actually run a project's test suite inside a worktree (the sandbox restricts network, and a suite
  that installs dependencies will fail), and whether the six-field report survives a real round trip.
  **Do not enable the codex branch on a real chain run before this.**
- **Cost inheritance, not a cost pin.** With no `-m` and no default `--effort`, this script follows
  `~/.codex/config.toml`. Today that is `gpt-5.6-terra`/`medium`; on 2026-09-05 it was
  `gpt-5.6-sol`/`xhigh`, the top-cost combination, and a tester run costs strictly more than a
  review run. The SPEC scopes the model override out, so this is disclosed rather than fixed
  (ADR-0194 §R2). **Worth a Gate 2 decision:** one line (`-m gpt-5.6-terra`, or the dispatch sites
  passing `--effort medium`) closes it, and both are inside R-06's existing surface.
- **The Workflow path loses per-group tester parallelism on the codex branch** (ADR-0194 §R5).
  Accepted deliberately; it is the price of being able to ask when Codex fails. If Step 5 wall-clock
  becomes the complaint, this is the cause, not the script.
- **A `claude-opus` answer does not survive a resumed Step 5 run** (ADR-0194 §R8). Bounded — it
  reverts to `sonnet`, never the reverse — and disclosed in the block Task 4 writes.
- **The test-file heuristic will false-positive somewhere.** A shared fixture, a `testdata/`
  directory under a name not in the list, a project that puts tests beside sources. The failure mode
  is a caller-visible exit 4 with an operator decision attached, not a silent pass — which is the
  right direction, but it will be seen.
- **The availability cascade now exists in two scripts** (ADR-0194 §R7). `CX15` makes drift
  detectable, not impossible. Extraction to a shared `codex-common.sh` is a real follow-up, blocked
  here only by the SPEC's "no changes to `codex-reviewer.sh`" boundary.
- **`effort: xhigh` → `high` on the tester is an unmeasured quality/cost trade.** It is Stefano's
  explicit cost decision. If Step 5 test quality visibly drops, this pin is the first thing to
  reconsider — and it is one line in two places.
- **Two registration failures are the historically likely ones here** and both are unguarded by
  design: the PAIRS entry (Task 2, guarded — `pairs-completeness.test.sh` catches it) and the
  `docs-ci.yml` entry (Task 7, **unguarded**, `.github/` cannot be planted). Check the CI run.
- **HITL gates:** Gate 2 (this plan and ADR-0194, including the two Gate-2 decisions flagged above);
  the Step 5 batch checkpoints; Gate 5 before commit; the commit/push gate at Step 7. No DB schema
  change, no deletion, no deploy. `sync-to-claude.sh --apply` — the step that actually installs
  `codex-tester.sh` to `~/.claude/hooks/` — is the human's call after merge, not part of this plan.
- **External dependency:** the Codex CLI is required at run time for the `codex` branch only; every
  other path is unaffected, and the availability cascade is exactly the mechanism that makes its
  absence a named exit 3 rather than a crash.

EXTERNAL DEPENDENCY: codex | binary | provisioned: true

## Requirement coverage

| ID | Tasks |
| --- | --- |
| R-01 | 1, 2, 7 |
| R-02 | 1, 2 |
| R-03 | 1, 2 |
| R-04 | 2 |
| R-05 | 1, 2, 7 |
| R-06 | 1, 2 |
| R-07 | 1, 4 |
| R-08 | 1, 4 |
| R-09 | 1, 5, 7 |
| R-10 | 1, 3 |
| R-11 | 1, 3, 7 |
| R-12 | 1, 4 |
| R-13 | 1, 6 |
| R-14 | 1, 6, 7 |
| R-15 | 8 |
