# Implementation plan — Codex CLI backend for the `coder` subagent

- **Topic slug:** codex-coder-backend-choice
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md` (R-01 … R-13; every id is cited by
  at least one task below, see §Requirement coverage)
- **ADR:** `docs/architecture/ADR-0196-codex-coder-choice.md` (Accepted 2026-09-07)
- **ARCH:** n/a — a scoped extension of an already-documented mechanism
  (ADR-0187 → ADR-0193 → ADR-0194 → this), not a new subsystem.
- **Stack:** Bash 3.2 (macOS `/bin/bash`) plus POSIX `grep`/`sed`/`awk`/`git`, and `python3` for
  JSON only. No `mapfile`, no bash associative arrays, no `${var^^}`, no `<<<`, no process
  substitution. Markdown reference docs and one YAML workflow file.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`

TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: sonnet

EXTERNAL DEPENDENCY: codex | binary | provisioned: true

---

## Read this first — state measured 2026-09-07 at `7dffb11` (rule 13)

**Re-derive it; do not trust this block.** Every count here is a snapshot of the moment it was
taken, and this repo has been wrong on its own numbers more than once.

```text
manifest schema version written by manifest-init.sh:   "1.4"  (the prose header at the top of
                                                               concept-to-code/SKILL.md still says
                                                               1.3 — pre-existing drift, OUT OF
                                                               SCOPE, do not "fix" it)
highest Invariant in manifest-validate.sh:              27    (use_codex_tester = 26,
                                                               step5_codex_tester_asked = 27)
assertion prefix CK across staging/:                    FREE  (grep -rhoE '\bCK[0-9]+' -> 0 hits)
assertion prefixes CX / CT / CD / CC across staging/:    TAKEN — do not use any of them
PAIRS entries under staging/sync-to-claude.sh:          codex-reviewer.sh and codex-tester.sh,
                                                        one line each, adjacent
docs-ci.yml shell-test loop ends with:                  ... codex-review-dispatch-gate
                                                        codex-tester-dispatch-gate; do
coder.md frontmatter:                                   model: sonnet, effort: xhigh — NOT TOUCHED
                                                        by this plan
codex model slugs, live in ~/.codex/models_cache.json:  gpt-6-astra and gpt-5.6-sol both present
                                                        (also gpt-5.6-terra, gpt-5.6-luna)
manifest-set-flag.sh:                                   value must be exactly true|false, exit 1
                                                        otherwise — BOOLEAN ONLY
markdownlint: docs/architecture IS linted (MD009 trailing space, MD010 tabs, MD001/MD003 headings,
              MD056 table columns); docs/superpowers is in the ignores list
plant-check.sh discovers harnesses by glob — a NEW harness needs NO registration there
docs-ci.yml's shell-test loop is a hand-maintained NAMED list — a new harness DOES need registering
```

The four PreToolUse gates documented gap 1 names were confirmed wired, not assumed:
`staging/user/settings.json` carries `pre-flight-pattern-enforce.sh`, `write-scope-enforce.sh` and
`test-write-scope.sh` on `Edit|Write|MultiEdit`; `sync-to-claude.sh` appends `coder-memory-scope.sh`
to the deployed `settings.json`. All four are PreToolUse; none is PostToolUse.
`test-write-scope.sh` reads `.agent_type` and denies only when it equals `coder` **and** the
TEST-AUTHORING SCOPE marker is in the first `user` entry of the dispatch transcript.

## Read this second — two harness basenames that must NEVER appear in this plan or in a test file

This is the trap that costs a blocking `exit 3` at the Step 5 → Step 6 gate, and it is the reason
two obvious cross-references are written descriptively below instead of by name.

`SPEC.md` waives **R-11** and **R-13** with `(no-test: …)`. `spec-coverage.sh` reports
`STALE-WAIVER` and **exits 3** the moment a waived id's token appears in a test file that is in this
feature's scope (ADR-0138 §D4). A test file is in scope when this plan names its basename **and**
that file names one of the ADR ids this plan cites (ADR-0154 §D1, both halves).

Census run 2026-09-07 (`grep -ohE '(^|[^A-Za-z0-9_])R-[0-9]+' <file>`):

```text
the tester's own dispatch-gate harness (prefix CX)   R-01 R-02 R-03 R-05 R-06 R-07 R-08 R-09
                                                     R-10 R-11 R-12 R-13   <- BLOCKING, and it
                                                                              names ADR-0194
the test-write-scope harness (prefix TG)             R-11                   <- BLOCKING, and it
                                                                              names ADR-0049/0068
codex-reviewer-schema.test.sh                        none                   <- safe to name
dispatch-completion.test.sh                          none                   <- safe to name
codex-review-dispatch-gate.test.sh                   none                   <- safe to name
plant-check.sh                                       R-01 R-05 R-12, but its basename matches NO
                                                     discovery pattern (not *.test.* / test-*.sh)
                                                     so it is never discovered — safe to name
the PAIRS-completeness harness                       R-05 R-09 — non-blocking foreign matches;
                                                     written descriptively below anyway
the human-gate-coverage harness                      R-04 — same, written descriptively
```

Two rules follow, and they are not optional:

1. **Never write the tokens `R-11` or `R-13` in any test file this plan creates or edits.** They are
   cited in Task 2 and Task 7 headings — the plan axis, which a `(no-test:)` marker never exempts
   (ADR-0138) — and nowhere else. No per-assertion bullet below carries either token, deliberately.
2. **Never write the two blocking basenames above.** Refer to the tester's harness as "the tester's
   own dispatch-gate harness (prefix `CX`)" and to the other as "the test-write-scope harness
   (prefix `TG`)". Naming either one imports its `R-11`/`R-13` and detonates the waiver check before
   a line of code exists.

Also expected, and not a defect: once the chain archives this SPEC to `docs/specs/`, the new
(spec, plan) pair makes the requirement-coverage baseline harness's `RS7`/`RS8a` diverge from the
frozen `spec-coverage-scope-baseline.tsv`. That baseline is bumped by Step 7.0b's
`c2c-step7-baseline-bump` fence (ADR-0166), **never by hand**, and `RS7` is never weakened.

## Read this third — the call-sites that assert contracts this change moves

The greps were run. Nothing here is left for the coder to discover.

**Two frozen populations that go RED if this change adds to them.** Both are in
`dispatch-completion.test.sh` (safe to name, census clean):

```text
$ grep -n 'EXPECTED=' -A 13 staging/plugin/scripts/tests/dispatch-completion.test.sh
DC21 freezes the declared dispatch-site set at exactly 13 ids, one of which is step5-batch-coder.
DC25 asserts step5-batch-coder carries NO `exempt:` clause.
```

Therefore: **add no new `<!-- dispatch-site: … -->` marker** for the codex branch (ADR-0194 added
none for `codex-tester.sh`, for the same reason: a `Bash` call to a script is not a subagent
dispatch), and leave the existing `<!-- dispatch-site: step5-batch-coder class=isolated -->` marker
byte-identical and un-exempted where it stands. Task 5 wraps prose *around* it, never through it.

**Two greps that came back clean, recorded so nobody re-runs them:**

```text
$ grep -rn 'use_codex_coder\|step5_codex_coder\|codex-coder' staging/ .github/    -> 0 hits
$ grep -c 'Codex coder' staging/plugin/skills/concept-to-code/references/step5-implementation.md
  0
```

**No existing assertion asserts an old contract that this change replaces.** Unlike the tester
feature — which lowered an `effort` pin and had to re-point an assertion at the new value — this
plan only adds. `coder.md` is not touched, no pin moves, no heading is renamed. The full harness
suite must still be run after Task 5 (see Task 7): a contract change in a file as central as
`step5-implementation.md` can break assertions in modules that merely share it, and the sweep is
what proves there is no second one.

**One reverse-direction guard fires by design.** The PAIRS-completeness harness checks the direction
a declared list cannot check itself (rule 8, ADR-0043): every file in a covered `staging/` subtree
must appear as a PAIRS source. Creating `codex-coder.sh` without its PAIRS line turns it RED. The
line is part of Task 2, in the same batch as the script.

## Read this fourth — the design in one paragraph, so no task re-derives it

A new Bash script `codex-coder.sh` shells `codex exec -s workspace-write -C <worktree> -c
model=<slug> -c model_reasoning_effort=<level>` with a prompt hand-ported from `coder.md`,
constrains the reply with `--output-schema` (eight fields), formats it into `coder.md`'s Output
Format markdown at `--out`, and is a CHECKER: exit 0 success / 2 bad invocation / 3 DID-NOT-RUN /
**4 scope violation**. `--model` (`astra` → `gpt-6-astra`, `sol` → `gpt-5.6-sol`) and `--effort` are
both **required** — the deliberate inverse of the tester script's config inheritance. Exit 4 comes
from a post-run comparison of the worktree's touched-path set (diff ∪ staged ∪ untracked, minus a
pre-run baseline) against a **blocklist of five named classes**, plus a separate HEAD-sha comparison
for a new commit; the script names the class it fired on. One `AskUserQuestion` in Step 5, before
the Workflow/Agent-tool branch, chooses `claude-sonnet` (default) / `codex`, and on `codex` asks
model and effort in the same turn. **It re-fires on every Step 5 entry, fresh or resumed** — no
manifest field is read to skip it. On the `codex` branch both dispatch paths run the script in the
orchestrator's own live turn; the Workflow path drops its coder stage from `pipeline()` entirely,
and the Agent-tool path skips the completion-fact fence because a synchronous exit code already is
the completion fact.

## Files this plan touches

| File | Task | Owner |
| --- | --- | --- |
| `staging/plugin/scripts/tests/codex-coder-dispatch-gate.test.sh` (NEW) | 1, 6 | tester |
| `staging/plugin/scripts/tests/codex-reviewer-schema.test.sh` | 1 | tester |
| `staging/plugin/scripts/codex-coder.sh` (NEW) | 2 | coder |
| `staging/sync-to-claude.sh` | 2 | coder |
| `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh` | 3 | coder |
| `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` | 3 | coder |
| `staging/plugin/skills/concept-to-code/references/step5-implementation.md` | 4, 5 | coder |
| `.github/workflows/docs-ci.yml` | 6 | coder |
| `docs/architecture/ADR-0196-codex-coder-choice.md` | 7 | doc-writer |

Tasks 4 and 5 both edit `step5-implementation.md`. They are deliberately in **one batch** so a
single coder applies them in order — never split across a `parallel()` batch.

**Not touched, deliberately:** `staging/plugin/agents/coder.md` (no frontmatter change, no pin
change — the backend choice does not alter the Claude coder), `codex-reviewer.sh`,
`codex-tester.sh`, and the three other places `step5-implementation.md` names a coder (the workflow
smoke-test probe agent, the tracer-bullet coder, and Step 6's fix agents). The ask governs exactly
two dispatch sites.

## Assertion ids and the harness contract

New harness: `staging/plugin/scripts/tests/codex-coder-dispatch-gate.test.sh`, prefix **`CK`**
(verified free 2026-09-07), ids **fixed-width two digits** `CK01`…`CK33` — never `CK1` beside
`CK10`, because `plant-check.sh` decides "fired" with a `^FAIL: <id>` **prefix** match.

The header block states, verbatim and in this order: `ADR-0196`; this plan's full path
(`docs/superpowers/plans/2026-09-07-codex-coder-backend-choice.md`) — both literals are what keeps
`spec-coverage.sh` from descoping the file (ADR-0154); that the file covers SPEC
**R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-08, R-09, R-10, R-12** — and **not** the two waived
ids; that the prefix `CK` was verified free on 2026-09-07; and that every assertion is RED by
construction until Tasks 2–5, so a red at the Batch A checkpoint is the deliverable.

Hermeticity, non-negotiable: **no assertion may invoke the real `codex` CLI.** Behavioural
assertions run the script against a **stub `codex`** written into a scratch `PATH` directory, inside
a scratch `git init` repository under `mktemp -d`. This repo never spends Codex quota in CI.

## Batching

| Batch | Tasks | Expected state at the checkpoint |
| --- | --- | --- |
| A | 1 | every `CK*` RED; the schema harness's new assertion RED |
| B | 2, 3 | `CK01`–`CK18` and `CK25`–`CK27` GREEN; `CK19`–`CK24`, `CK28`–`CK33` still RED |
| C | 4, 5 | all `CK*` GREEN; full harness suite green |
| D | 6 | harness registered in CI, `Z1` floor confirmed, plants all seen RED |
| E | 7 | ADR verified, `spec-coverage.sh` clean, deployment checked |

Task 1 must not share a batch with Tasks 2–5 (ADR-0101 rule 1 — an assertion must not share a batch
with the task it depends on).

---

## Task 1 — TEST: the whole `CK` section RED (R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-08, R-09, R-10, R-12)

Owner: **tester**. Two test files, both tester-owned. `codex-reviewer-schema.test.sh` is
**extended in place**, never rewritten — do not renumber or reflow its existing assertions, several
of which are pinned by name elsewhere.

**1a. New harness `staging/plugin/scripts/tests/codex-coder-dispatch-gate.test.sh`.** Shape it on
`codex-review-dispatch-gate.test.sh`: `#!/bin/bash`, `set -u`, `SCRIPTS=$(cd "$(dirname "$0")/.." &&
pwd)`, `ok()`/`bad()` counters, a `FATAL:` guard for every input file that already exists (never for
`codex-coder.sh` itself — `CK01` is the assertion that covers its absence, and a FATAL exit would
stop every other id from reporting), a trailing `PASS=$PASS FAIL=$FAIL` line, a `Z1` vacuity floor,
`[ "$FAIL" -eq 0 ]` as the last line.

Helper both behavioural sections use, defined once (rule 6):

```bash
# make_stub_codex <dir> <auth-status> <exec-behaviour-script>
# Writes an executable `codex` into <dir> that answers `doctor --json` with the given
# auth.credentials status and, on `exec`, runs <exec-behaviour-script> with the parsed
# -C/-o values in $CC_CD/$CC_OUT and records its own argv to <dir>/argv.txt.
```

Assertions, grouped. Every count guard is an **exact** count, never a floor (rule 10) — these
populations are frozen at 1 or 2 and a floor would absorb its own plant.

Script existence, sandbox and invocation:

- [ ] `CK01` (R-04) — `staging/plugin/scripts/codex-coder.sh` exists and is a readable file.
- [ ] `CK02` (no requirement id, deliberately) — `staging/sync-to-claude.sh` carries the exact PAIRS
      line `plugin/scripts/codex-coder.sh|hooks/codex-coder.sh`, exactly once. Rule 17: a script no
      PAIRS line deploys is a script the dispatch sites name and nobody installs — the defect found
      live on the RTF sites on 2026-09-06. **This assertion carries no `R-NN` citation in its
      comment**; the requirement it serves is waived from the test axis, and writing that token here
      is the STALE-WAIVER trap.
- [ ] `CK03` (R-05) — the script's `codex exec` invocation carries **both** `-s workspace-write` and
      `-C "$WORKTREE"`. Extract the invocation (the `codex exec` line plus its `\`-continuations)
      with awk and match inside that slice only — a needle matched against the whole file would be
      satisfied by the header comment that *explains* the flag (rule 1).
- [ ] `CK04` (R-05) — that same slice contains neither `danger-full-access` nor `read-only`. Scoped
      to the slice for the same reason: the header comment legitimately names `read-only` when
      contrasting with `codex-reviewer.sh`.

Availability cascade and invocation contract:

- [ ] `CK05` (R-04) — **behavioural.** With `PATH` set to a directory containing no `codex`, the
      script exits **3** and prints a line matching `^codex-coder: DID-NOT-RUN:` on stderr.
      Precondition guard first (rule 4): assert `command -v codex` really is unresolvable under that
      `PATH`; if it resolves, report DID-NOT-RUN rather than a pass. Build the `PATH` as
      `<stub-dir>:/usr/bin:/bin` (never empty — the script needs `dirname` and `git`), and capture
      the interpreter's absolute path first (`real_bash=$(command -v bash)`) so the `VAR=value cmd`
      form does not resolve `bash` through the `PATH` being replaced.
- [ ] `CK06` (R-04) — **behavioural.** Stub answering `doctor --json` with
      `auth.credentials.status = "error"` → exit **3**, stderr names the status.
- [ ] `CK07` (R-04) — **behavioural, the assertion the required-flags decision exists for.** Six
      sub-checks, one id, each exiting **2**: unknown flag; missing `--worktree`; missing `--out`;
      unreadable `--brief`; **missing `--model`**; **missing `--effort`**; plus `--model terra`
      (a real slug that is not in this script's closed set) → exit 2. A default silently governing
      either flag is exactly what this feature exists to prevent.
- [ ] `CK08` (R-04) — **behavioural.** Invoked `--model astra --effort high`, the stub's recorded
      argv contains both `-c model=gpt-6-astra` and `-c model_reasoning_effort=high`.
- [ ] `CK09` (R-04) — **behavioural.** Invoked `--model sol`, the recorded argv contains
      `-c model=gpt-5.6-sol`. Pairs with `CK08` so neither half of the mapping can be dropped.
- [ ] `CK10` (R-04) — **drift guard, ADR-0196 §R9.** The rate-limit vocabulary regex and the
      `[ -s "$RAW_OUT" ]` precedence check appear in **all three** codex scripts, byte-identical on
      the regex. This is the VCS-064 correction, and it is exactly the kind of fix that gets applied
      to one copy and not the other two.

Scope check — the five violation classes plus the polarity that inverts (each behavioural, each
asserting both the exit code **and** the class token on stderr):

- [ ] `CK11` (R-06) — stub touches `.claude/test-cmd` → exit **4**, stderr names `TEST-CMD`.
- [ ] `CK12` (R-06) — stub creates a **new, untracked** `tests/test_a.py` → exit **4**, stderr names
      `TEST-FILE` and the path. A `git diff --name-only`-only implementation passes `CK13` and fails
      here, which is the point.
- [ ] `CK13` (R-06) — stub modifies an already-tracked `src/prod.py` and nothing else → exit **0**.
      **This is the polarity inversion**: the same fixture is a violation for the tester script and
      the expected output here. Pairs with `CK12` so neither the union's `git diff` half nor the
      inverted classification can be dropped without a red.
- [ ] `CK14` (R-06) — stub writes `.claude/agent-memory/coder/MEMORY.md` → exit **4**, stderr names
      `MEMORY-INDEX`.
- [ ] `CK15` (R-06) — the shard boundary, two sub-checks, one id: **two** new files under
      `.claude/agent-memory/coder/topics/` → exit **4** naming `MEMORY-SHARDS`; exactly **one** new
      file there → exit **0**. The boundary is the assertion; either sub-check alone passes a
      wrong implementation.
- [ ] `CK16` (R-06) — stub runs `git commit` inside the worktree → exit **4**, stderr names
      `NEW-COMMIT`. Not a path-based check: it compares the worktree's `HEAD` sha against the
      pre-run baseline, and a path-only implementation cannot see it at all.
- [ ] `CK17` (R-06) — **count guard on the derived population** (rule 7). In the `CK12` fixture,
      assert the touched-path set the script reports on its own stderr summary has exactly the
      expected number of members before believing the exit-4 verdict; in the `CK13` fixture, exactly
      1. Zero candidates and "no candidate matched a violation class" are indistinguishable from the
      exit code alone. Read the set from the script's own stderr, never by re-deriving it in the
      harness — two derivations that could disagree are the defect.
- [ ] `CK18` (R-08) — **behavioural.** Stub that writes nothing at all → exit **0** plus a
      `codex-coder: NOTE:` line on stderr naming the empty touched-path set. "Wrote nothing" and
      "wrote only in-scope files" must not collapse into one signal (rule 4).

The Step 5 gate block (each sliced from its own heading to the next `^#### ` with awk — the
`D_BLOCK` idiom `codex-review-dispatch-gate.test.sh` already uses; a 2000-line file contains these
words elsewhere and the slice is what makes the assertion about this block):

- [ ] `CK19` (R-01) — `step5-implementation.md` carries the heading
      `#### Codex coder backend for Step 5 dispatch (ADR-0196, both paths)`, matched **line-wise**,
      exactly once (a heading is a structural marker — rule 3 keeps those line-wise).
- [ ] `CK20` (R-01) — inside the slice: the ask offers both `claude-sonnet` and `codex`, and marks
      `claude-sonnet` as the default.
- [ ] `CK21` (R-01) — inside the slice: the ask fires once, **before** the Workflow/Agent-tool
      branch, so one ask covers both dispatch paths. Match the flattened, undecorated, lower-cased
      clause (rule 3), not a physical line.
- [ ] `CK22` (R-02) — inside the slice: on `codex`, the same gate turn also asks for the model
      (`astra` default, `sol`) and the effort, with all six effort tokens present
      (`low`, `medium`, `high`, `xhigh`, `max`, `ultra`) and `medium` marked default.
- [ ] `CK23` (R-03) — inside the slice: an explicit clause stating the gate re-fires on **every**
      Step 5 entry, fresh or resumed. Flattened match (rule 3).
- [ ] `CK24` (R-03) — **the negative direction, and the assertion that makes R-03 real.** The token
      `step5_codex_coder_asked` appears **nowhere** in `step5-implementation.md`, in
      `manifest-init.sh` or in `manifest-validate.sh` (exact count 0), **and** the gate slice
      carries no skip clause of the "if the field is true, skip straight to dispatch" shape. The
      positive assertion above passes a file that also grew a skip; this is the one that does not.

Manifest fields:

- [ ] `CK25` (R-10) — `manifest-init.sh` contains all three seed lines exactly:
      `echo "use_codex_coder: false" >> "$T"`, `echo "step5_codex_coder_model: null" >> "$T"`,
      `echo "step5_codex_coder_effort: null" >> "$T"`. Three sub-checks, one id.
- [ ] `CK26` (R-10) — **behavioural, end to end.** Run `manifest-init.sh` into a temp dir; assert
      `manifest-validate.sh` accepts it; assert the file still carries
      `manifest_schema_version: "1.4"` (no version bump); flip `use_codex_coder` to `true` via
      `manifest-set-flag.sh` and re-validate; `sed` the two string fields to `astra` and `medium`
      and re-validate; then set `use_codex_coder` to `maybe`, `step5_codex_coder_model` to `terra`
      and `step5_codex_coder_effort` to `banana` in turn, asserting validation fails each time
      **naming the offending field** (Invariants 28 and 29, three sub-checks).
- [ ] `CK27` (R-10) — the declared vocabulary duplication, drift-checked (ADR-0196 §R2): the six
      effort tokens in Invariant 29's `grep -Eq` alternation are exactly the six the gate block
      offers. Two producers of one vocabulary, in two files, with nothing else checking they agree.

The exit-code resolution site and the two dispatch sites:

- [ ] `CK28` (R-07) — the heading `#### Codex coder exit-code handling (ADR-0196)` exists
      **exactly once**, line-wise, and its slice names all four of exit `0`, `2`, `3`, `4`.
- [ ] `CK29` (R-07) — the slice's exit-3 and exit-4 branches each carry an `AskUserQuestion`; the
      exit-4 branch offers all three of fallback / accept / halt; and the slice carries the
      `NEW-COMMIT` qualification (accepting that class walks into the base-fork halt one step
      later). A silent fallback is the one outcome the contract forbids and this is where it would
      be introduced.
- [ ] `CK30` (R-09) — **exactly 2** places carry the pointer literal
      ``branch per `#### Codex coder exit-code handling` above (ADR-0196)``. Exact count: the
      population is frozen at 2 (Workflow path, Agent-tool path) and a dropped site would still show
      a non-zero count.
- [ ] `CK31` (R-09) — **exactly 2** lines name the deployed path `~/.claude/hooks/codex-coder.sh`
      together with `--worktree` (rule 17: the path PAIRS actually deploys to, never a plausible
      `~/.claude/scripts/` one — the exact defect found live on the RTF sites on 2026-09-06).
- [ ] `CK32` (R-09) — the Workflow branch states that **no coder stage is put in `pipeline()` at
      all** on the codex branch and that the script runs in the orchestrator's own live turn,
      sequentially; and it names the degenerate case where the tester is also codex and checkpoint
      review is off, leaving no stages and therefore no workflow script.
- [ ] `CK33` (R-09) — the Agent-tool branch states that the completion-fact fence is **not** run on
      the codex branch (the exit code is the completion fact), **and** the marker
      `<!-- dispatch-site: step5-batch-coder class=isolated -->` is still present exactly once with
      no `exempt:` clause. The second half is what stops the wrapping edit from moving or exempting
      a marker two frozen populations elsewhere depend on.
- [ ] `Z1` — vacuity floor, `>= 33`.

**Plants** (`# plant: <id> | <staging-relative path> | <needle> | <replacement>`, column 1, declared
beside the assertion they belong to). Every one must be seen RED before it is trusted;
`plant-check.sh` reports `NOFIRE` for a declaration whose assertion stays green. Minimum set:

```text
CK02  sync-to-claude.sh (NOT under plugin/ — target it directly, relative to staging/)
CK03  plugin/scripts/codex-coder.sh | -s workspace-write | -s read-only
CK08  plugin/scripts/codex-coder.sh | gpt-6-astra | gpt-6-astro
CK12  plugin/scripts/codex-coder.sh | ls-files --others --exclude-standard | ls-files --cached
CK16  plugin/scripts/codex-coder.sh | (the HEAD-sha comparison) | (a comparison that is never true)
CK19  plugin/skills/concept-to-code/references/step5-implementation.md | #### Codex coder backend for Step 5 dispatch (ADR-0196, both paths) | #### REMOVED FOR PLANT
CK24  plugin/skills/concept-to-code/references/step5-implementation.md | (the re-fires clause) | (a skip clause naming step5_codex_coder_asked)
CK25  plugin/skills/concept-to-code/scripts/manifest-init.sh | echo "use_codex_coder: false" >> "$T" | :
CK26  plugin/skills/concept-to-code/scripts/manifest-validate.sh | fail "use_codex_coder field present but value is not 'true' or 'false'" | :
CK30  plugin/skills/concept-to-code/references/step5-implementation.md | (one of the two pointer literals) | (the same line with the pointer removed)
```

A plant replacement may not contain the literal ` | ` — `plant-check.sh` splits declarations on it
and a five-field line is `BADPLANT`, not a plant. `.github/` is not a legal plant target
(ADR-0151 §D11), which is why no assertion here reads `docs-ci.yml`.

**1b. `codex-reviewer-schema.test.sh` — one new assertion, in place.** Add an assertion parallel to
the existing `S_T` (which walks `codex-tester.sh`'s schema): extract `codex-coder.sh`'s
`SCHEMA_EOF` heredoc with the file's existing parameterised `extract_schema` and run it through the
existing `check_schema` walker (rule 6 — reuse the walker, do not copy it into the new harness).
Bump that file's `Z1` floor from `>= 6` to `>= 7`. Plant:
`plugin/scripts/codex-coder.sh | "additionalProperties": false | "additionalProperties": true`.
This is the `invalid_json_schema` trap that cost ADR-0187 a live probe. That file's own `R-NN`
census is zero — keep it that way: cite ADR-0196 in the new assertion's comment, never a bare
requirement id.

Budget: `staging/plugin/scripts/tests/codex-coder-dispatch-gate.test.sh`,
`staging/plugin/scripts/tests/codex-reviewer-schema.test.sh` (~540 lines)

## Task 2 — CODE: `codex-coder.sh` and its PAIRS entry (R-04, R-05, R-06, R-08, R-13)

Owner: **coder**. New file `staging/plugin/scripts/codex-coder.sh`, plus exactly one line added to
`staging/sync-to-claude.sh`'s PAIRS block.

Structure it on `codex-tester.sh` and keep its conventions even where they differ from the global
shell rule: `#!/bin/bash` and `set -u`, **not** `set -euo pipefail`. That is deliberate and
load-bearing — this script's whole contract is classifying a non-zero `codex exec` exit into 3
versus 4, and `set -e` would abort before the classification runs.

- Header comment states, in this order: what it is and why it exists; the CHECKER contract
  (exit 0/2/3/**4**, "the caller branches on the exit code, never on whether stdout is empty",
  rule 5); the declared prompt duplication from `coder.md` with the drift warning; the declared
  cascade duplication, now across **three** scripts, with a pointer to ADR-0196 §R9 and the note
  that extraction to a shared helper is a named follow-up whose case is now stronger than it was;
  "sandbox as enforcement" (rule 16) **and** the fact that the sandbox plus this check are standing
  in for four PreToolUse hooks that cannot fire here (ADR-0196 documented gap 1); and the
  live-verified model slugs with their 2026-09-07 date (rule 13).
- Flags: `--worktree <dir>` (required), `--brief <file>` (required, must be readable),
  `--out <file>` (required), `--model <astra|sol>` (**required**, closed set),
  `--effort <value>` (**required**, passthrough — no client-side allowlist, per ADR-0196 §R2).
  Anything else, or a missing required flag, → exit 2 with one line on stderr, `codex-coder: `
  prefixed. No default value is assigned to `MODEL` or `EFFORT` anywhere in the script.
- Model mapping, in the script, as an explicit `case`: `astra` → `gpt-6-astra`, `sol` →
  `gpt-5.6-sol`, `*` → exit 2 naming the value received.
- Availability cascade, in order, each exiting 3 with `codex-coder: DID-NOT-RUN: <reason>`:
  `command -v codex`; `codex doctor --json` produced output and `python3` exists to parse it;
  `.checks["auth.credentials"].status == "ok"`; `git -C "$WORKTREE" rev-parse --is-inside-work-tree`.
  Copy `codex-tester.sh`'s wording byte-for-byte (`CK10` pins the load-bearing needles).
- **Baseline capture, before any `codex exec`:** the sorted union of `git -C "$WT" diff
  --name-only`, `git -C "$WT" diff --name-only --cached` and `git -C "$WT" ls-files --others
  --exclude-standard` into a temp file, **plus** `git -C "$WT" rev-parse HEAD` into a variable.
  Pre-existing dirt must never be attributed to Codex, and the sha is what the `NEW-COMMIT` class
  compares against.
- Schema (`--output-schema`) with eight properties matching `coder.md`'s Output Format plus the two
  additions ADR-0196 names: `files_modified` (array of objects: `path`, `purpose`), `sub_steps`
  (array of objects: `step`, `status`, `reason`), `key_decisions` (array of strings),
  `verification` (object: `command`, `exit_code`, `result`), `drafted_commit` (object: `subject`,
  `body`), `cleanup` (array of objects: `item`, `disposition`), `plan_deviations` (array of
  objects: `task`, `constraint`, `action`, `why`), `pattern_classification` (array of objects:
  `pattern`, `path`, `intent`). **`"additionalProperties": false` on every object** including
  nested ones and array `items` — without it the call fails `invalid_json_schema` before the model
  runs.
- Prompt, hand-ported from `coder.md`, embedding the `--brief` file's contents. It must state:
  never commit and never `git add`; never create or edit a test file (the tester owns them for this
  batch) and never read, write or modify `.claude/test-cmd`; relative paths only, writes stay under
  the worktree; follow the plan and stop-and-report on a contradiction rather than redesigning;
  never weaken or disable a test to make it pass; smallest viable change in the surrounding style,
  no new dependencies the plan did not call for; memory goes to ONE new uniquely-named file under
  `.claude/agent-memory/coder/topics/` and never to `MEMORY.md`; run the narrowest relevant test
  first and the full suite at most twice; and return all eight fields, including one
  `pattern_classification` entry per hunk using the ADD/REMOVE/REPLACE/MODIFY vocabulary and one
  `plan_deviations` entry per declined or altered plan constraint (empty array when there are none,
  never a silent omission).
- Invocation: `codex exec -s workspace-write -C "$WORKTREE" -c model="$SLUG" -c
  model_reasoning_effort="$EFFORT" --output-schema "$SCHEMA_FILE" -o "$RAW_OUT" "$(cat
  "$PROMPT_FILE")"`. Build each `-c` pair as one array element carrying the whole token (bash 3.2:
  indexed arrays are fine, associative are not), never by string-splitting a variable — the same
  shape `codex-tester.sh` uses so the drift-guard needle matches intact.
- Failure classification after `codex exec`, in this order — **the order is the VCS-064 fix and must
  not be rearranged**: a non-empty `$RAW_OUT` wins first; only if it is empty does the rate-limit
  vocabulary grep on stderr run; otherwise "produced no output". Copy the regex byte-for-byte.
- **Scope check.** Recompute the touched-path union, subtract the baseline, then evaluate the five
  classes. Reuse `codex-tester.sh`'s `is_test_path()` predicate verbatim (same question about a
  path, opposite conclusion — rule 6):
  - `TEST-CMD` — `.claude/test-cmd` in the remaining set.
  - `TEST-FILE` — any remaining path for which `is_test_path()` is true.
  - `MEMORY-INDEX` — `.claude/agent-memory/coder/MEMORY.md` in the remaining set.
  - `MEMORY-SHARDS` — more than one remaining path under `.claude/agent-memory/coder/topics/`.
  - `NEW-COMMIT` — `git -C "$WT" rev-parse HEAD` differs from the captured baseline sha.
  Any of these → write `--out` anyway (a partial report is more useful than none), print
  `codex-coder: SCOPE-VIOLATION: <CLASS>: <subject>` on stderr, exit **4**. Multiple classes print
  multiple lines and still exit 4 once.
  - Empty remaining set → print `codex-coder: NOTE: no file changes detected in <worktree>` and
    continue to exit 0. Not a fifth exit code; the contract is fixed at 0/2/3/4.
  - Print a one-line summary of the touched-path set on stderr in **every** case — `CK17` reads it
    rather than re-deriving the set, so the harness and the script cannot disagree about the
    denominator.
- Format the schema JSON into `coder.md`'s Output Format markdown at `--out` with a `python3 -c`
  block, same shape as `codex-tester.sh`'s formatter, and exit 0.
- PAIRS: add `plugin/scripts/codex-coder.sh|hooks/codex-coder.sh` immediately after the
  `codex-tester.sh` line. Without it the reverse-direction PAIRS guard goes RED and the script the
  Step 5 sites name would never be installed. `sync-to-claude.sh` refuses to write through a
  symlink since PR #575 — the new entry must be a plain PAIRS line in the same block, not a
  hand-placed symlink.

Budget: `staging/plugin/scripts/codex-coder.sh`, `staging/sync-to-claude.sh` (~340 lines)

## Task 3 — CODE: the three manifest fields (R-10)

Owner: **coder**. `manifest-init.sh` and `manifest-validate.sh`, in lockstep (rule 17).

- `manifest-init.sh`: three `echo` lines seeding `use_codex_coder: false`,
  `step5_codex_coder_model: null` and `step5_codex_coder_effort: null`, placed immediately after the
  existing `step5_codex_tester_asked` line. Do not touch `manifest_schema_version: "1.4"` — the
  fields are additive and conditional, exactly as the reviewer's and tester's pairs were.
- `manifest-validate.sh`: **Invariant 28** (`use_codex_coder` present → must be `true`/`false`),
  appended after Invariant 27, copying Invariants 24/26's structure line for line including the
  `grep -q` presence test before the `grep -Eq` value test. **Invariant 29** covers both string
  fields: `step5_codex_coder_model` present → `^step5_codex_coder_model: (null|astra|sol)$`;
  `step5_codex_coder_effort` present → `^step5_codex_coder_effort: (null|low|medium|high|xhigh|max|ultra)$`.
  Each failure message must **name the field**, because `CK26` asserts the field name appears in the
  rejection text.
- Invariant 28's comment states, in one sentence, why there is no fourth field: the `_asked` shape
  the two earlier features use exists solely to skip a re-ask, and this gate never skips
  (ADR-0196 §R7). Invariant 29's comment names the vocabulary duplication `CK27` pins.
- **Write no `step5_codex_coder_asked` field anywhere.** `CK24` asserts the token appears in neither
  script.

Budget: `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh`,
`staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` (~55 lines)

## Task 4 — CODE: the Step 5 backend gate, once, covering both paths (R-01, R-02, R-03)

Owner: **coder**. `step5-implementation.md` only. Insert a new `#### ` block immediately after the
existing `#### Codex tester backend for Step 5 dispatch (ADR-0194, both paths)` block and before
`#### Workflow dispatch path`. Anchor-preserving: do not reflow or renumber the review or tester
blocks — assertions elsewhere slice both by heading.

Heading, exactly: `#### Codex coder backend for Step 5 dispatch (ADR-0196, both paths)`

The block states:

- Like the tester ask and unlike the review ask, this one is **not** conditional on
  `step5_review_mode` — the coder dispatch is unconditional on both paths, so the ask is too.
- **This ask has no `_asked` gate and re-fires on every Step 5 entry, fresh or resumed.** State the
  divergence explicitly and name its reason (a fresh model/effort choice every time; an inherited
  `ultra` on a run nobody re-approved is a silent cost decision — ADR-0196 §R7). State that
  `manifest.use_codex_coder` may already hold a value from a prior partial run and that this value
  is **display-only context**, never authoritative and never a reason to skip.
- The ask fires once, in the orchestrator's own live turn, **before the Workflow/Agent-tool branch
  below, so one ask covers both dispatch paths** — the same placement the tester ask uses.
- `AskUserQuestion` options: `[claude-sonnet]` "Claude coder at sonnet (current behaviour)
  (Recommended)" / `[codex]` "Codex CLI, sandboxed to the worktree, with a gate if it is
  unavailable".
- On `[codex]`, **in the same gate turn**, two further selections: model — `[astra]` "Astra
  (gpt-6-astra) (Recommended)" / `[sol]` "Sol (gpt-5.6-sol)"; and effort — `[medium]` "(Recommended)"
  / `[low]` / `[high]` / `[xhigh]` / `[max]` / `[ultra]`.
- Persistence: `[codex]` → `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest>
  use_codex_coder true`; `[claude-sonnet]` → the same helper with `false` (explicitly, because the
  field may hold `true` from a previous entry and this gate never skips). The two string fields are
  written by **bash `sed` substitution on the additive field** — `manifest-set-flag.sh` validates
  its value as exactly `true`/`false` and cannot write them. Write that sentence in the negated form
  the file already uses for `step5_mode` and `BASELINE_COMMIT`, and carry the same-line
  `<!-- path-rule-exempt: negated -- … -->` marker, or the path-rule checker reads a helper
  named-but-not-invoked as a broken reference.
- On `[claude-sonnet]`, set both string fields back to `null` by the same `sed` mechanism, so a
  later reader never sees a model/effort pair beside `use_codex_coder: false`.
- The ask does not fire under `--autopilot`; unattended runs keep `use_codex_coder` at `false` and
  both string fields at `null`. This is an instruction, not an enforcement (rule 16) — say so
  rather than implying a guarantee that is not there.

Budget: `staging/plugin/skills/concept-to-code/references/step5-implementation.md` (~65 lines)

## Task 5 — CODE: the codex branch at both dispatch sites, and the exit contract stated once (R-07, R-09)

Owner: **coder**. `step5-implementation.md` only. Anchor-preserving throughout: the existing Claude
dispatch text is wrapped in an `Otherwise (default …)` branch **byte-preserved**, exactly the way
ADR-0187 wrapped the five reviewer sites and ADR-0194 wrapped the two tester sites. Do not rewrite
it, do not move the `<!-- dispatch-site: step5-batch-coder class=isolated -->` marker, and do not
add an `exempt:` clause to it.

**5a. One resolution site for the exit contract** (rule 6 — the same "stated once, referenced twice"
idiom as `#### Merge-back and base-fork audit` and the tester's own exit-code block). New section,
heading exactly `#### Codex coder exit-code handling (ADR-0196)`, placed immediately after the
tester's equivalent block:

- exit `0` → read `--out` as the coder's report, exactly as if the Claude `coder` had produced it.
- exit `2` → bad invocation. Report the stderr line and halt this dispatch; it is a defect in the
  orchestrator's own arguments, never a reason to fall back.
- exit `3` → DID-NOT-RUN. `AskUserQuestion`: "Fallback to the Claude `coder` (Recommended)" /
  "Halt the chain". **Never a silent fallback.**
- exit `4` → scope violation. Name the class and the subject from stderr, then `AskUserQuestion`:
  "Fallback to the Claude `coder`, discarding Codex's work (Recommended)" / "Accept the write and
  continue" / "Halt the chain". The check is a heuristic and the operator decides, not the script.
  **For the `NEW-COMMIT` class specifically, "accept and continue" is not safe and the block says
  so**: the merge-back's base-fork check compares the worktree's `HEAD` against `$PRE` and will halt
  one step later with a cause that is wrong ("the worktree forked from somewhere other than the
  feature branch"). Halting here, or resetting the worktree by hand, is the honest resolution.
- State that a Workflow `pipeline()` stage has no `AskUserQuestion` hook at all, which is **why**
  both branches below run in the orchestrator's live turn.

**5b. Workflow path — `**Stage 2 — coder.**`.** Add, before the existing Stage 2 text:

> **If the Step 5 coder backend ask above resolved to `codex`:** do **not** put a coder stage in
> `pipeline()` at all. For each task group in turn, in this same live turn: materialize the brief
> with `step5-brief.sh` exactly as below; `git worktree add` a worktree for the group; run
> ``~/.claude/hooks/codex-coder.sh --worktree <wt> --brief <brief> --out <report> --model
> <manifest.step5_codex_coder_model> --effort <manifest.step5_codex_coder_effort>``; branch per
> `#### Codex coder exit-code handling` above (ADR-0196); then run `#### Merge-back and base-fork
> audit` with `$WT`/`$WB` taken from the `git worktree add` you just issued — known by construction
> here, not enumerated out of `git worktree list` (F19). This is sequential where the Claude branch
> is parallel: a real wall-clock cost, larger than the tester's because the coder is the long stage,
> taken deliberately because a coder that cannot report its own failure leaves nothing to review,
> nothing for Gate 5 to approve and nothing to commit (ADR-0196 §R5).
>
> **If the tester backend also resolved to `codex` and `manifest.step5_review_mode` is not
> `checkpoint`, `pipeline()` has no stages left at all.** Write no workflow script and make no
> `Workflow()` call: the whole of Step 5 runs as a sequence of orchestrator-turn subprocess calls
> with a merge-back between each. This is a legal state, not an error.

Then `**Otherwise (default — `use_codex_coder` absent or `false`):**` and the existing Stage 2 text
unchanged, including the `manifest.coder_model` override rule, the effort table reference and the
verbatim TEST-AUTHORING SCOPE marker block (ASCII hyphen, ADR-0049 §D3 — a paraphrase or an em dash
leaves the guard silently inert).

**5c. Agent-tool batch path — `**Single batch dispatch template**` and its numbered item 2.** Same
wrap, and it is shorter because this path already runs in the live turn: create the batch worktree
with `git worktree add`, run the same command with the same four flags, branch per the exit-code
block, merge back via the same audit block with `$WT`/`$WB` from the `git worktree add`.

Add, in the codex branch only: **the completion-fact fence is not run.** `codex-coder.sh` is
synchronous and its exit code is the completion fact; `dispatch-state.sh` would report `NONE` and
HALT every successful Codex run (ADR-0196 §R6, and rule 17 — a consumer reading a producer that no
longer exists on this branch). The `Otherwise` branch keeps the fence exactly as it is today, and
the `<!-- dispatch-site: step5-batch-coder class=isolated -->` marker stays outside both branches,
unmodified and un-exempted.

Both branches carry the same brief the Claude coder receives, including the TEST-AUTHORING SCOPE
contract and the memory-shard write rule — on the codex branch those travel inside
`codex-coder.sh`'s own prompt (Task 2) and are checked post-hoc by the scope check, never by a hook.

Budget: `staging/plugin/skills/concept-to-code/references/step5-implementation.md` (~100 lines)

## Task 6 — CODE: register the harness in CI and confirm the plants fire (R-12)

Owner: **coder** for the registration; the plant sweep is verification.

- `.github/workflows/docs-ci.yml`: append `codex-coder-dispatch-gate` to the `for t in …`
  shell-test list, at the **end**, after `codex-tester-dispatch-gate`. One token, one line, nothing
  else in that file. Do not splice it earlier: `coder-discipline`'s own `CD10` pins its adjacency to
  `codex-reviewer-schema` and a name inserted between them turns it RED. **No harness asserts this
  registration** — `.github/` is not a legal plant target (ADR-0151 §D11) — so it is verified by
  grep and by the next CI run, and its absence is a known blind spot rather than a covered one.
  This is the same defect class that shipped twice before on this feature's predecessors (VCS-058:
  a new harness unregistered in `docs-ci.yml`, a new script unregistered in PAIRS).
- Run the full plant sweep: `bash staging/plugin/scripts/tests/plant-check.sh`. Every declared
  `CK*` plant and the new schema plant must fire; a `NOFIRE` means the assertion pins nothing
  (rule 2) and a `BADPLANT` means the declaration itself is malformed. **Inspect what the sweep
  actually printed** — do not trust the exit code alone (rule 2, ADR-0090).
- Bump `Z1` in `codex-coder-dispatch-gate.test.sh` only if the final assertion count differs from
  the `>= 33` written in Task 1; never lower it.

Budget: `.github/workflows/docs-ci.yml` (~1 line)

## Task 7 — DOC + verify: ADR-0196 final state, the five gaps, and the deployment check (R-11, R-13)

Owner: **doc-writer** for the ADR; verification is the orchestrator's.

- Confirm `docs/architecture/ADR-0196-codex-coder-choice.md` reads `Status: Accepted` and that its
  Consequences (negative) section still names **all five** documented gaps explicitly — the four
  non-firing PreToolUse hooks, the PATTERN classifier downgrade, the permanent LSP gap, the
  unresolved eslint MCP situation, and the partially-wired unauthenticated context7 entry. It was
  written to that state before this plan; this task is the check that it still is, and the place to
  record divergence.
- If the implementation diverged from any refinement, append a dated `## Correction` section —
  **never edit the decision text above it** (rule 14).
- Confirm the ADR's deferred live dry run is still recorded as outstanding. It is **not** run here:
  it spends real Codex quota and writes files, so it is a manual, attended step, and the codex
  branch is not trusted in a real chain run until it has happened. Its first check is the cheapest
  one to have got wrong: that `codex exec` accepts `-c model=<slug>` in the same form it already
  accepts `-c model_reasoning_effort=<value>`.
- **Deployment check:** run `bash staging/sync-to-claude.sh --dry-run` (or the repo's equivalent
  non-applying mode) and confirm the new PAIRS entry resolves to `hooks/codex-coder.sh` and does not
  trip the post-PR #575 symlink-write refusal. `sync-to-claude.sh --apply` itself is the human's
  call after merge, not part of this plan.
- Run, and read the output of, in this order: the full harness suite
  (`for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`) — **the whole
  suite, not just the new file**; `bash staging/plugin/scripts/tests/plant-check.sh`;
  `npx markdownlint-cli2` (the ADR is under `docs/architecture/`, which **is** linted — MD009/MD010
  are on; this plan under `docs/superpowers/` is not);
  `spec-coverage.sh --spec SPEC.md --plan docs/superpowers/plans/2026-09-07-codex-coder-backend-choice.md --tests-root .`.
- `spec-coverage.sh` must not report `STALE-WAIVER`. If it does, a test file has acquired the token
  `R-11` or `R-13` — remove it from the test file; never delete the waiver from `SPEC.md` to silence
  the checker.

Budget: none (documentation check and verification only)

## Risks, dependencies and HITL gates

- **The live dry run is deferred and the feature is not trustworthy until it happens.** ADR-0187's
  own deferred probe found a real defect (`additionalProperties`) that no offline harness caught,
  and ADR-0193's found a second (a deployed-path mismatch producing exit 127, which is not the
  exit 3 the fallback keys off, so the graceful fallback never fired). Three specific things this
  plan cannot verify offline: whether `-c model=<slug>` is accepted in that form; whether `codex
  exec -s workspace-write` can run a project's test suite inside a worktree (the sandbox restricts
  network, and a suite that installs dependencies will fail); and whether the eight-field report
  survives a real round trip. **Do not enable the codex branch on a real chain run before this.**
- **This substitution removes an enforcement layer, and the replacement is post-hoc.** Four
  PreToolUse hooks that gate the Claude coder cannot fire on a `codex exec` subprocess. The sandbox
  is real enforcement; the scope check is a safety net that runs after the write has landed inside
  the worktree. That is a deliberate, disclosed trade (ADR-0196 gap 1) and it is the single most
  important thing for the Gate 2 reviewer to agree with before any of this is built.
- **The scope check is a blocklist and will miss things.** A coder that rewrites an unrelated
  production file, deletes something, or edits a file no task named is not a scope violation by this
  script's definition — `diff-budget-check.sh` at the batch checkpoint and the human at Gate 5
  remain the checks for that, exactly as they are for the Claude coder.
- **The gate asks on every Step 5 entry, including resumed ones.** This is the requirement and it is
  also friction: it is the third Codex ask in the chain and the only one that does not fire once per
  manifest. Expect it to feel wrong to anyone who learned the other two first.
- **The Workflow path loses per-group coder parallelism on the codex branch**, and the coder is the
  long stage. If Step 5 wall-clock becomes the complaint, this is the cause.
- **The availability cascade now exists in three scripts** (ADR-0196 §R9). `CK10` makes drift
  detectable, not impossible. Extraction to a shared `codex-common.sh` is a real follow-up, blocked
  here only by the SPEC's "no changes to the two existing scripts" boundary — **worth a Gate 2
  decision**, because the argument for deferring is weaker at three copies than it was at two.
- **Two registration failures are the historically likely ones here**, and they are asymmetric: the
  PAIRS entry (Task 2) is guarded by the reverse-direction PAIRS check, and the `docs-ci.yml` entry
  (Task 6) is **unguarded** because `.github/` cannot be planted. Check the CI run.
- **HITL gates:** Gate 2 (this plan and ADR-0196, including the two Gate-2 decisions flagged above);
  the Step 5 batch checkpoints; Gate 5 before commit; the commit/push gate at Step 7.
  `sync-to-claude.sh --apply` — the step that actually installs `codex-coder.sh` to
  `~/.claude/hooks/` — is the human's call after merge. No DB schema change, no deletion, no deploy.
- **External dependency:** the Codex CLI is required at run time for the `codex` branch only; every
  other path is unaffected, and the availability cascade is exactly the mechanism that makes its
  absence a named exit 3 rather than a crash. `codex-coder.sh` additionally needs an authenticated
  Codex session — an unattended run cannot complete that flow, which is why the autopilot path never
  selects this branch.

## Requirement coverage

| ID | Tasks |
| --- | --- |
| R-01 | 1, 4 |
| R-02 | 1, 4 |
| R-03 | 1, 4 |
| R-04 | 1, 2 |
| R-05 | 1, 2 |
| R-06 | 1, 2 |
| R-07 | 1, 5 |
| R-08 | 1, 2 |
| R-09 | 1, 5 |
| R-10 | 1, 3 |
| R-11 | 7 |
| R-12 | 1, 6 |
| R-13 | 2, 7 |
