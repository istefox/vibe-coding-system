# Implementation plan — the chain regenerates a generated Xcode project before it tests it

- **Issue:** #470
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md` (`R-01` … `R-08`)
- **ADR:** `docs/architecture/ADR-0165-470-chain-never-regenerates-xcode.md` (extends `ADR-0159`)
- **Stack:** Bash 3.2 (macOS-portable — no `[[ ]]`, no arrays, no `mapfile`, no `${var^^}`, no
  process substitution) plus BSD `sed`/`grep`/`awk`, matching the file being changed. One existing
  generator script, one existing harness, one existing registry comment. **No new file, no new
  helper, no new dependency, no PAIRS entry, no `docs-ci.yml` append** —
  `plugin/scripts/detect-test-cmd.sh|hooks/detect-test-cmd.sh` is already in `sync-to-claude.sh`'s
  PAIRS table and `prep` is already in the named `shell-tests` list.

TEST-CMD CANDIDATE: none

TEST-CMD MODE: brownfield

The project's existing trusted command —
`for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` — already runs the
harness this plan extends. Proposing a new one would change `.claude/test-cmd`'s SHA and force a
Gate 2b re-approval for no gain.

**This feature has no external dependency.** `tuist` and `xcodegen` are named throughout, and
neither is declared as an `EXTERNAL DEPENDENCY:` line, deliberately: this feature does not *need*
either tool — it exists to behave correctly when they are **absent**, which is this machine's state
and the state every assertion below runs in. Declaring `provisioned: false` would make G13
(`external-dependency-check.sh`) exit 1 and halt a feature whose whole subject is that absence.
Do not add one later.

---

## Read this first — the gate blocks this feature today, and no task below can clear it

Measured 2026-08-22, before a line was written, against `SPEC.md` and a stub plan:

```text
spec-coverage.sh --spec SPEC.md --plan <stub> --tests-root .
  UNCOVERED  R-07  tests
  UNCOVERED  R-08  tests
  exit 1
```

`R-07` and `R-08` both carry `(no-test: …)`, and both markers sit on a **continuation line** of a
wrapped checklist item. `spec-coverage.sh` parses the marker line-wise, from the `- [ ] R-NN —`
opener line only. Proven on a two-item fixture the same day: identical clause, same-line → honoured
(`COVERED`); on a continuation line → invisible (`UNCOVERED … tests`, exit 1).

**The fix is an edit to `SPEC.md`, and it belongs to no agent in this chain.** `SPEC.md` is outside
the architect's write scope, outside the coder's, and outside the tester's. It is the operator's
call at Gate 2:

> Reflow `R-07` and `R-08` in `SPEC.md` so the `(no-test: …)` clause **opens on the same physical
> line as the `- [ ] R-NN —` opener**. Nothing else about the two items needs to change.

Verified on a reflowed copy, same day: `8 declared, 8 covered, 0 uncovered, exit 0`.

The underlying blindness in `spec-coverage.sh` is a real defect against CLAUDE.md rule 3 — a clause
is the same clause whether it wraps — and is deliberately not fixed here (ADR-0165 §D8, alternative
A10). **It wants its own issue.**

## Read this second — what the gate scopes in, and the one file this plan will not name

- `staging/plugin/scripts/tests/prep.test.sh` — this feature's harness, and the **only** discovered
  test file this plan names on purpose. Measured with `spec-coverage.sh`'s own anchored token scan
  on 2026-08-22: it carries **zero** `R-NN` tokens, so it cannot contribute a foreign match to any
  verdict. It already names `ADR-0159`, which this plan cites, so ADR-0154's back-reference half is
  already satisfied; Task 1 adds `ADR-0165` and this plan's basename to the new section header
  anyway, so the scoping is deliberate rather than incidental.
- `staging/plugin/scripts/detect-test-cmd.sh`, `staging/plugin/scripts/tests/plant-check.sh`,
  `staging/plugin/scripts/stop-gate.sh` — verified 2026-08-22 against the live discovery predicate:
  none of the three is discovered as a test file. Naming them costs nothing.
- **ADR-0159's `M3` lives in a harness whose basename this plan never writes out.** That file
  carries nineteen `R-NN` tokens of its own feature's SPEC and already names `ADR-0159`, which this
  plan cites — so writing its basename anywhere here would satisfy both halves of ADR-0154's scope
  filter, pull all nineteen foreign requirement ids into this feature's scoped population, and
  report all eight of this feature's ids `COVERED` before any work exists (ADR-0165 §D7,
  alternative A7; ADR-0138, ADR-0157, CLAUDE.md rule 18). The instruction the coder needs from it
  is carried in Task 4 in full, without the filename.
- **This section deliberately does not spell out the discovery predicate's basename patterns.** An
  earlier draft did, and one of those literals is a real basename shared by eleven per-skill test
  runners: the plan's own gate run went from 1 scoped file to 12 candidates, of which 11 were saved
  only by the back-reference filter. Measured, then deleted. Describe the predicate, never quote it
  — a plan's prose scopes files just as effectively as its task list does.

## Read this third — every test below is fixture-only, and that is not a compromise

There is no Tuist install, no XcodeGen install and no Xcode project in this repository or its CI.
Every assertion runs against a `mktemp -d` root with `touch`ed manifest files, in the style
`prep.test.sh` already uses for its other branches. **No assertion invokes `tuist`, `xcodegen`,
`xcodebuild` or `git`.**

The one place this is *better* than an install would be: the DID-NOT-RUN path is defined by the
tool being absent, and absent is exactly what this machine is. `TU33` executes the real guard, on
the real generated line, and observes the real 127 — with no tool to install. What genuinely cannot
be executed here is the success path (a real `tuist generate` followed by a real `xcodebuild test`)
and `stop-gate.sh`'s routing of a 127 arriving from a real suite. ADR-0165 §D8 states the split;
`R-07` is that statement.

---

## Ownership

Everything under `staging/plugin/scripts/tests/` is **tester-owned**: the coder's test-file write
gate (ADR-0049) denies any create/edit on a path with a `tests/` component. Tasks 1, 2, 3, 5 and 6
are tester batches; Task 4 is the only coder batch. A plan that put a test-file edit in a coder task
would be refused at the hook, not at review.

---

### Task 1 — TESTER: make `prep.test.sh` able to carry evidence, and freeze today's behaviour (R-03, R-06)

- Budget: `staging/plugin/scripts/tests/prep.test.sh`, `staging/plugin/scripts/tests/plant-check.sh` (~75 lines)

**This batch produces no RED, by design.** Its assertions pass today and are forward guards: they
are what makes "the existing branches are unmodified in behavior" (`R-03`) and "an existing trusted
test-cmd is left untouched" (`R-06`) mean something once Task 4 lands. Declared here so the
all-green result is read as the intent and not as a batch that failed to test anything.

1. **Convert `no()` to the plantable form.** `prep.test.sh`'s failure helper — the one-line `no()`
   definition beside `ok()` near the top of the file — becomes
   `no() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }`, with the colon. (Named by its helper, not by a
   line number: this very task inserts lines above it — CLAUDE.md rule 12.) Without the colon,
   `plant-check.sh` refuses every plant declared in this file outright
   (`grep -qE "(printf|echo)[^#]*FAIL: "` → `BADPLANT`, "harness does not emit the 'FAIL: <id>'
   prefix"), so Task 5 would be impossible and CLAUDE.md rule 2 unsatisfiable here. Measured
   2026-08-22: three of 86 harnesses still lack the emitter — `hook-probe`,
   `hook-verify-workflow`, `prep`. `ok()` is left exactly as it is; the success idiom is
   deliberately not enforced by the registry. See ADR-0165 §D6, alternative A8.
2. **Record the conversion where the stale claim lives.** `plant-check.sh`'s attribution comment
   names five harnesses emitting `FAIL <label>` with no colon and already carries an inline forward
   correction ("`phase1` converted the same day"). Append the same shape — naming `prep`, this
   issue and the date — rather than rewriting the 2026-08-05 measurement, which was correct on its
   day (CLAUDE.md rule 14). Do not change any code in that file.
3. **Open the section.** A comment header introducing the whole `TU` block, naming `issue #470`,
   `ADR-0165` and `2026-08-22-470-chain-never-regenerates-xcode.md` (ADR-0154's back-reference,
   made deliberate) and stating that ids are fixed-width `TU01`…`TU99`. Cite `R-03` and `R-06` in
   **this block's own** comment header — the citation lives in the header introducing the
   assertions, not only inside message strings. **Never write `R-07` or `R-08` anywhere in this
   file**: their `(no-test: …)` exemptions would immediately read as stale waivers.
4. **`TU01` (R-03)** — fixture with only `Foo.xcodeproj/`, no manifest: candidate still contains
   `xcodebuild test -project` and `Foo`, and contains **neither** `tuist generate` **nor**
   `xcodegen generate`. Both directions in one assertion: presence of the old form and absence of a
   regeneration prefix on a project with nothing to regenerate.
5. **`TU02` (R-03)** — same shape for `Bar.xcworkspace/`: `-workspace`, `Bar`, no prefix.
6. **`TU03` (R-03)** — both fixtures still carry
   `-derivedDataPath "<abs-fixture-root>/.build/DerivedData"`, absolute and per-fixture (ADR-0159
   D1 unchanged for the branches it was written for).
7. **`TU04` (R-06)** — fixture carrying a pre-existing `.claude/test-cmd` with a distinctive line
   **and** a `Project.swift`: after the run the file is byte-identical, exit status is 0, and stdout
   contains `already present`. The manifest is what makes this a real guard after Task 4 — without
   it the fixture never reaches the new branch and the assertion proves nothing about it.
8. **`TU99`** — assertion-count floor for the file, which has none today. Set it from the count
   actually observed at the end of this batch, and re-derive it (never increment by feel) in every
   later task that adds assertions: a floor with slack absorbs its own plant (CLAUDE.md rule 10).

**Verify:** `bash staging/plugin/scripts/tests/prep.test.sh` — all green, including the nine
pre-existing assertions, whose only change is the `FAIL: ` prefix they emit on failure.

### Task 2 — TESTER: RED assertions for detection, branch ordering and the SwiftPM manifest (R-01, R-04)

- Budget: `staging/plugin/scripts/tests/prep.test.sh` (~110 lines)

Split from Task 3 on size, not on principle: the two batches together add ~30 assertions to one
file, and one batch that large is neither reviewable nor sensibly budgeted (ADR-0052). This batch
answers *which branch fires*; Task 3 answers *what that branch writes*. Every assertion here is RED
until Task 4. Cite `R-01` and `R-04` in this block's comment header.

1. **`TU10` (R-01)** — fixture with `Project.swift` **and** `Foo.xcodeproj/` **and**
   `Bar.xcworkspace/`: the candidate contains `tuist generate`. The two gitignored-in-real-life
   artifacts are present on purpose — this is the ordering assertion, and it is the only one that
   proves the new branch runs *ahead of* both existing globs rather than merely existing.
2. **`TU11` (R-01)** — `Tuist.swift` alone → `tuist generate`.
3. **`TU12` (R-01)** — `project.yml` alone → contains `xcodegen generate` and does **not** contain
   `tuist generate`. Both directions: `project.yml` is XcodeGen's manifest, and a `tuist` prefix on
   it is a command that could never succeed (ADR-0165 §D2).
4. **`TU13` (R-01)** — `project.yaml` alone → `xcodegen generate`.
5. **`TU14` (R-01)** — the run's stdout contains `stack=xcode-project-generated` for a
   `Project.swift` fixture. Pins the SPEC's own tool-neutral stack name against a later rename.
6. **`TU15` (R-04)** — fixture with `Tuist/Package.swift`, **no** root `Package.swift` and **no**
   Xcode manifest → candidate is exactly `swift test`. This is the worktree-visibility gap named in
   the issue.
7. **`TU16` (R-04)** — fixture with `Tuist/Package.swift` **and** `Project.swift` → the generated
   branch wins: contains `tuist generate`, is not `swift test`. The SPEC's stated edge case, and
   the reason `R-04` is a detection fix and not a command change.
8. **`TU17` (R-01)** — a fixture with none of the five manifests and no Xcode artifact still yields
   `NONE`. The negative direction: a branch that fires on everything would pass all of
   `TU10`–`TU16`.
9. Re-derive `TU99`.

**Verify:** `bash staging/plugin/scripts/tests/prep.test.sh` — `TU10`–`TU17` RED, everything from
Task 1 still green. Record which ids went red; Task 4 is done when exactly those flip.

### Task 3 — TESTER: RED assertions for the generated candidate's content and its DID-NOT-RUN contract (R-02, R-05)

- Budget: `staging/plugin/scripts/tests/prep.test.sh` (~140 lines)

Cite `R-02` and `R-05` in this block's comment header. All RED until Task 4.

1. **`TU20` (R-02)** — the candidate begins with `cd "<abs-fixture-root>" &&`. `stop-gate.sh` runs
   the line as `bash -c "$CMD"` with no `cd` of its own; both generators and `xcodebuild -scheme`
   resolve from the current directory (ADR-0165 §D3).
2. **`TU21` (R-02)** — contains `tuist generate --no-open`, matched with the flag. Without it
   `tuist generate` launches Xcode inside a Stop hook on an unattended machine. Match the flag
   specifically — `tuist generate` alone would pass with `--no-open` deleted.
3. **`TU22` (R-02)** — `Project.swift` containing `let projectName = "Ondum"` and
   `name: projectName` yields `-scheme "Ondum"`. This is `git-repo-init`'s own template idiom and
   the shape on which a derivation matching only `name: "X"` returns nothing.
4. **`TU23` (R-02)** — single-line `let project = Project(name: "Vibro", …)` yields
   `-scheme "Vibro"`.
5. **`TU24` (R-02)** — multi-line `Project(` … `name: "Ondum",` with a later
   `.target(name: "OndumApp"…)` yields `-scheme "Ondum"`, not `OndumApp`. The first-match rule,
   asserted against the shape that would break it.
6. **`TU25` (R-02)** — `project.yml` with `name: MyProject` at column 1 yields
   `-scheme "MyProject"`.
7. **`TU26` (R-02)** — a `Tuist.swift`-only fixture in a directory named `Zed` yields
   `-scheme "Zed"`: the documented `basename "$PWD"` fallback, asserted rather than left implicit.
8. **`TU27` (R-02)** — the generated candidate contains
   `-derivedDataPath "<abs-fixture-root>/.build/DerivedData"`. **This is the assertion that carries
   ADR-0159's build-root guarantee onto the third candidate** — behavioural, read off the artifact
   the script wrote, and strictly stronger than a source-text occurrence count (ADR-0165 §D7).
9. **`TU28` (R-02)** — a macOS `Project.swift` whose only iOS mention is a trailing comment
   (`destinations: .macOS,   // or [.iPhone, .iPad]`, verbatim from `git-repo-init`'s template)
   yields `-destination 'platform=macOS'` and does **not** contain `iOS Simulator`. Rule 12 inside a
   generator: without the comment strip, the comment explaining the macOS choice selects iOS.
10. **`TU29` (R-02)** — `destinations: [.iPhone, .iPad]` outside any comment yields
    `platform=iOS Simulator`.
11. **`TU30` (R-05)** — the candidate contains `command -v tuist` and the literal `exit 127`.
12. **`TU31` (R-05)** — the candidate contains `DID-NOT-RUN:`. The legible half of the contract: an
    exit code with no greppable string in the artifact is a convention that decays unobserved.
13. **`TU32` (R-02)** — the written `.claude/test-cmd` is exactly one line, and the line extracted
    by `stop-gate.sh`'s own `awk` idiom (first non-blank, non-`#` line, copied verbatim into the
    fixture) is byte-identical to it. A multi-line or comment-leading candidate would be silently
    truncated by the real consumer.
14. **`TU33` (R-05)** — **execute it.** Take the extracted line, run it under `bash -c` with `PATH`
    set to a non-existent directory, and assert: exit status is exactly 127, stderr contains
    `DID-NOT-RUN`, and no `xcodebuild` invocation trace appears. Hermetic — `cd`, `command`, `echo`
    and `exit` are all bash builtins, so an empty `PATH` removes the generator without removing the
    guard. This is the one part of the runtime contract this repository *can* execute, and it must
    not be left as prose because the rest of the path cannot be.
15. **`TU34` (R-05)** — the same line, with a stub `tuist` on `PATH` that exits 0 and a stub
    `xcodebuild` that exits 65, returns 65 and not 127: DID-NOT-RUN is distinguishable from an
    ordinary test failure, which is the second half of what `R-05` asks. Stubs are two three-line
    scripts in the fixture's own `bin/` — no real tool, no network.
16. Re-derive `TU99`.

**Verify:** `bash staging/plugin/scripts/tests/prep.test.sh` — `TU20`–`TU34` RED, Tasks 1 and 2
unchanged.

### Task 4 — CODER: the generated-Xcode-project branch and the SwiftPM manifest fix in `detect-test-cmd.sh` (R-01, R-02, R-04, R-05)

- Budget: `staging/plugin/scripts/detect-test-cmd.sh` (~70 lines)

One file, one batch. Do not touch any file under a `tests/` path — the write gate will refuse it,
and every assertion this task must turn green already exists.

1. **Insert the new branch first in the chain**, ahead of `if has "*.xcworkspace"`. It fires on
   `Project.swift`, `Tuist.swift`, `project.yml` or `project.yaml` at `$ROOT` (plain `[ -f ]`
   tests, not globs — these are exact names). `STACK="xcode-project-generated"`.
2. **Resolve the tool from the manifest:** `Project.swift`/`Tuist.swift` → `tuist`, regeneration
   `tuist generate --no-open`; `project.yml`/`project.yaml` → `xcodegen`, regeneration
   `xcodegen generate`.
3. **Derive the scheme name**, first match wins, all `sed`/`head -1`, no tool executed:
   `let projectName = "X"` → `Project(name: "X"` → `^\s*name: "X"` (Swift manifests) →
   `^name: X` (`project.yml`) → `basename "$PWD"`.
4. **Derive the platform** from a **comment-stripped** copy of the manifest (`//` to end of line
   for Swift, `#` for YAML), scanning `destinations:`/`deploymentTargets:`/`platform:` for
   `.iOS`/`.iPhone`/`.iPad`/`iOS`. Hit → `platform=iOS Simulator,name=iPhone 17` (matching the two
   sibling branches in this file, not `git-repo-init`'s `iPhone 16`). No hit → `platform=macOS`.
   **The strip is not optional**: `git-repo-init`'s own template carries `// or [.iPhone, .iPad]`
   on the line that selects macOS.
5. **Compose the candidate as one line**, in this order — `cd "$PWD" &&`, the `command -v <tool>`
   guard emitting a `DID-NOT-RUN:` line on stderr and `exit 127`, the regeneration command, then
   `&& xcodebuild test -scheme "<name>" -destination '<derived>' -derivedDataPath "$PWD/.build/DerivedData"`.
   `$PWD` is `$ROOT` here (the script has already `cd`-ed into it), so every path written is
   absolute at detection time — ADR-0159 D1's property, extended, not re-derived. **No `-project`
   and no `-workspace`**: `git-repo-init`'s documented recipe uses `-scheme` alone, and it is the
   form that resolves the workspace `tuist generate` emits alongside the project (ADR-0165 §D3, A3).
   **No command substitution anywhere in the written line** — the string is SHA-pinned by TOFU and
   read by a human at Gate 2b (A2).
6. **Fix the `swift-package` branch:** `[ -f "Package.swift" ]` becomes
   `[ -f "Package.swift" ] || [ -f "Tuist/Package.swift" ]`. `CMD="swift test"` is unchanged — this
   is a detection fix only.
7. **Do not modify the two existing `CMD="xcodebuild` lines, in any way, including whitespace.**
   ADR-0159's `M3` declares a plant whose needle is the `-project` line **verbatim**, and
   `plant-check.sh` requires a needle to match exactly one site: reformatting that line, or
   factoring a shared suffix out of the pair, turns a live plant into a `BADPLANT` in a harness
   this feature never touches. Its counting assertion (`grep -F 'CMD="xcodebuild'`, expects 2) is
   correct as written and stays at 2 — the new line begins `CMD="cd \"…`, outside that population
   by construction (ADR-0165 §D7).
8. **Bash 3.2 only.** No `[[ ]]`, no arrays, no `mapfile`, no `${var,,}`, no `<<<`, no process
   substitution. The file's header states the constraint; `bash -n` will not catch a violation that
   only fails at run time.

**Verify:** `bash staging/plugin/scripts/tests/prep.test.sh` — every `TU` id from Tasks 1–3 green,
and no assertion outside the `TU` block changed state. Then the full suite:
`for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`. **Run the whole
suite, not just this harness** — this task changes a generator whose output other harnesses read,
and a contract change is exactly the case where an unrelated module breaks silently.

### Task 5 — TESTER: plant every new mechanism, one declaration per assertion (R-01, R-02, R-04, R-05)

- Budget: `staging/plugin/scripts/tests/prep.test.sh` (~25 lines)

An assertion nobody planted pins nothing (CLAUDE.md rule 2). Declarations sit at **column 1**, in
`prep.test.sh`, beside the assertion each proves — an indented one is silently skipped. Three or
four ` | `-separated fields, never more; the needle must match **exactly one** site in
`plugin/scripts/detect-test-cmd.sh`. Every plant here must be added **after** Task 4, never before:
a plant on an already-red assertion is `VACUOUS`, not evidence.

Declare one plant for each distinct mechanism, at minimum:

| id | mechanism the plant removes |
|---|---|
| `TU10` (R-01) | the new branch's manifest condition — neutralised, so the `*.xcodeproj` glob wins again |
| `TU12` (R-01) | the `project.yml` → `xcodegen` tool selection, forced to `tuist` |
| `TU15` (R-04) | the `[ -f "Tuist/Package.swift" ]` disjunct in the `swift-package` branch |
| `TU21` (R-02) | `--no-open` |
| `TU27` (R-02) | `-derivedDataPath …` on the **new** `CMD=` line only — the needle must be a substring unique to that line, since the flag also appears in the file's header comment and on the two frozen candidates |
| `TU28` (R-02) | the comment strip in the platform scan |
| `TU30` (R-05) | `exit 127` → `exit 3`, the alternative ADR-0165 §D5 rejects |

**Verify:** `bash staging/plugin/scripts/tests/plant-check.sh` — every new declaration reports
`FIRED`. A `NOFIRE` means the assertion pins nothing; a `BADPLANT` means the registry could not run
it (needle matching zero or many sites, or the harness still not emitting `FAIL: `); a `VACUOUS`
means the assertion was already red. **Read the registry's own output before believing the count** —
three different verdicts, three different repairs.

### Task 6 — TESTER: verification sweep and the record check (R-03, R-05, R-06, R-07, R-08)

- No file writes. Reports only; any defect found returns to the owning task rather than being
  patched here.

1. **Full suite:** `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`.
   Not this harness alone — Task 4 changed an observable contract (the shape of the string written
   to `.claude/test-cmd`), and a contract change is the case where a test in an unrelated module
   fails silently. Grep the whole repository for other readers of that artifact before declaring
   this clean: `stop-gate.sh` and `approve-test-cmd.sh` both read the first non-comment line, and
   `concept-to-code`'s Step 5.0.4b greps it for `-derivedDataPath` — all three are expected to be
   unaffected, and "expected" is not "checked".
2. **`R-03` / `R-06` re-read.** Confirm `TU01`–`TU04` are still green and still meaningful:
   `TU04`'s fixture must still contain a `Project.swift`, or it no longer guards the "already
   present" short-circuit against the new branch at all.
3. **Plant registry:** `bash staging/plugin/scripts/tests/plant-check.sh`, all `FIRED`, no
   `BADPLANT` anywhere in the file — including the ones Task 1's `no()` conversion newly made
   possible.
4. **Requirement coverage:**
   `bash staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh --spec SPEC.md --plan docs/superpowers/plans/2026-08-22-470-chain-never-regenerates-xcode.md --tests-root .`
   Expect `8 declared, 8 covered, 0 uncovered, 0 unscoped, 1 in scope`, exit 0 — **only after the
   operator's `SPEC.md` reflow described at the top of this file.** Without it the run exits 1 on
   `R-07`/`R-08` and that is not a defect in the work.
5. **`R-05` record check.** Confirm ADR-0165 §D5 states the DID-NOT-RUN value, states it is
   distinguishable from both a clean pass and an ordinary `xcodebuild` failure, and gives the
   reason the repository's usual exit 3 is wrong for this producer. Confirm `TU30`/`TU33`/`TU34`
   are the executed half of that claim.
6. **`R-07` record check.** Confirm ADR-0165 §D8 splits enforced from documented accurately **as
   built** — in particular that it credits `TU33`/`TU34` as executed rather than claiming the whole
   DID-NOT-RUN path is untestable here, and that what remains instruction-only is named exactly:
   the real `tuist generate` + `xcodebuild test` success path, and `stop-gate.sh`'s routing of a 127
   arriving from a real suite. An ADR that overstates what is untested is the same defect as one
   that overstates what is tested.
7. **`R-08` record check.** Confirm the diff touches only
   `staging/plugin/scripts/detect-test-cmd.sh`, `staging/plugin/scripts/tests/prep.test.sh` and
   `staging/plugin/scripts/tests/plant-check.sh`'s comment. `git diff --stat` must show nothing
   under `staging/plugin/skills/git-repo-init/`, and no change to any `.gitignore` authoring.
8. **Report, do not commit.** Committing is the human's decision at a HITL gate.

---

## Risks and HITL gates

- **HITL — Gate 2 (architect review):** the `SPEC.md` reflow of `R-07`/`R-08` is an operator edit,
  required before the feature's own gate can pass. Nothing downstream can substitute for it.
- **HITL — Gate 2b (TOFU):** not exercised by this feature. `TEST-CMD CANDIDATE: none` leaves
  `.claude/test-cmd` untouched, so its SHA does not change and no re-approval is triggered.
- **HITL — commit / push:** end of chain, human only.
- **Risk — the success path is unverified and unverifiable here.** No Tuist, no XcodeGen, no Xcode
  project. That `tuist generate --no-open` produces a scheme of the derived name, and that
  `xcodebuild -scheme` resolves the generated workspace, rest on `git-repo-init`'s documented recipe
  and on upstream docs read 2026-08-22 — not on an execution. This is `R-07`'s subject and the
  largest risk in the change.
- **Risk — the scheme-name derivation is a five-branch heuristic with a fallback.** A manifest that
  computes or interpolates its name lands on `basename "$PWD"`. Mitigated by Gate 2b, where a human
  reads the command before it can ever run — a real mitigation and an honest admission that the
  derivation is not authoritative.
- **Risk — `no()`'s conversion changes nine existing output lines.** Nothing parses them (CI
  branches on exit status; the registry greps `^FAIL: `), and the nine carry no ids, so a
  hypothetical plant with assertion id `detect` could be over-credited. No such plant exists and
  none is declared. Recorded rather than fixed (ADR-0165 §D6).
- **Risk — the two frozen `CMD="xcodebuild` lines.** A tidy-up in Task 4 breaks a plant in a harness
  outside this feature's diff, and the failure surfaces in the plant registry, not in the suite.
- **Risk — a `tuist generate` failure that is not an absence** (a manifest that does not compile)
  exits with the tool's own status and is reported as a test failure. Defensible, documented, and
  not the DID-NOT-RUN state.
- **Dependency — none external.** See the note at the top of this file, and do not add an
  `EXTERNAL DEPENDENCY:` line for `tuist` or `xcodegen`.

## Not in this plan

- A `docs/chain-decisions.md` narrative block and a `docs/chain-decision-index.md` entry for
  ADR-0165. Both files are outside the architect's write scope; 118 of 167 ADRs carry an index
  entry and nothing enforces the ratio. Operator's call.
- Archiving `SPEC.md` to `docs/specs/`. Chain step, not a task here.
- An issue for `spec-coverage.sh`'s continuation-line blindness to `(no-test: …)`, with the
  2026-08-22 fixture measurement. Recommended, operator's call.
