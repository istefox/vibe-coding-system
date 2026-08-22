# ADR-0165 — the chain regenerates a generated Xcode project before it tests it, and says so when it cannot

- **Topic slug:** `470-chain-never-regenerates-xcode`
- **Issue:** #470 (the chain never regenerates a generated Xcode project)
- **SPEC:** `SPEC.md`, requirement ids `R-01` … `R-08`
- **Extends:** ADR-0159 (`-derivedDataPath` on every generated `xcodebuild` candidate; one build
  root per checkout) — this ADR adds a third candidate to the same generator and keeps ADR-0159's
  D1 property (every path written is absolute at DETECTION time). ADR-0014/ADR-0020 (TOFU trust is
  per-file-SHA and stays human) are relied on unchanged.
- **Deliberately does not touch:** `stop-gate.sh`, `approve-test-cmd.sh`, the trust registry's
  shape, `concept-to-code`'s Step 5.0.4b pre-flight gate, `git-repo-init`, `xcodebuild`, Tuist,
  XcodeGen, and `spec-coverage.sh` (see §D8 for the last one — it blocks this feature today and is
  still not fixed here).

## Status

Accepted — 2026-08-22.

## Context

`git-repo-init`'s Swift/Tuist scaffold gitignores the build artifact and says so in its own words:

```gitignore
# Tuist
Derived/
*.xcodeproj
*.xcworkspace
.tuist-version
Tuist/.build/
```

> The `.xcodeproj` is a build artifact under Tuist: anyone (including CI) regenerates it with
> `tuist generate`.
> — `staging/plugin/skills/git-repo-init/references/swift-xcode-setup.md`

That is correct on its own. What was missing is the second half: **nothing in the chain is the
"anyone" who regenerates it.** `detect-test-cmd.sh` detects the stack by globbing for the artifact
(`*.xcworkspace`, then `*.xcodeproj`) and writes a bare `xcodebuild test` candidate. Three
consequences, each of which was live:

1. **A worktree detects nothing at all.** `isolation: worktree` forks from a commit (ADR-0068,
   and the `worktree.baseRef: "head"` fact harvested 2026-07-28), so a fresh worktree contains the
   tracked tree and nothing else. `*.xcodeproj` is gitignored, `.claude/test-cmd` is gitignored,
   and under Tuist even the SwiftPM manifest sits at `Tuist/Package.swift` rather than at root.
   `detect-test-cmd.sh` falls through every branch to `STACK="unknown"`, `CMD="NONE"` — the
   documented opt-out from the stop gate. The worktree runs no tests and reports no problem.
2. **The main checkout tests a stale project.** Where a `.xcodeproj` *does* exist on disk from some
   earlier manual `tuist generate`, the glob finds it and `xcodebuild test` builds it. Source files
   that arrived by merge, checkout or merge-back are not in that target's file list, so their tests
   are not compiled and not run. The suite passes.
3. **Every `tests_after` figure downstream of (2) was measured against a project that does not
   reflect the tree it claims to describe.** The issue flags the retroactive effect as
   informational; correcting past run reports is out of scope (SPEC §Scope) and this ADR does not
   attempt it.

The direction that matters is the same one ADR-0159 named for the shared build root: not the false
red, which someone investigates, but the **false green**, which nobody does.

### What was measured before designing (rule 13)

Everything below was re-derived from the files on 2026-08-22, not taken from the issue.

- **`project.yml` is not a Tuist manifest.** The SPEC's manifest glob lists `Project.swift`,
  `Tuist.swift` *or* `project.yml`. Checked against the upstream docs via Context7 on 2026-08-22:
  Tuist's own XcodeGen-migration guide contrasts the two directory shapes explicitly — XcodeGen
  uses `project.yaml`/`project.yml`, Tuist uses `Tuist.swift` + `Project.swift` (+ optional
  `Workspace.swift`). XcodeGen's regenerator is `xcodegen generate`, not `tuist generate`; its
  `GenerateCommand.swift` writes `projectDirectory + "\(project.name).xcodeproj"`, so the top-level
  YAML `name:` key *is* the produced project's basename. Emitting a `tuist generate` prefix for a
  `project.yml` project would have produced a candidate that can only ever fail. See §D2.
- **`tuist generate` opens Xcode unless told not to.** `--no-open` is a documented flag whose
  entire purpose is suppressing that (Context7, tuist/tuist `main`, 2026-08-22). An unattended
  chain must never omit it. `git-repo-init`'s own recipe already writes `tuist generate --no-open`.
- **`git-repo-init` documents the invocation this fix should generate, and it has no `-project`.**
  Its verified recipe is `tuist generate --no-open` followed by
  `xcodebuild -scheme <ProjectName> -destination 'platform=macOS' test`. The SPEC offered "a fixed
  convention documented by `git-repo-init`" as one way to derive the `-project`/`-scheme` values;
  the convention, read rather than assumed, turns out to *drop* `-project`. See §D3.
- **`git-repo-init`'s own `Project.swift` template never writes the name as a literal at `name:`.**
  It writes `let projectName = "<ProjectName>"` and then `name: projectName`. A derivation matching
  only `Project(name: "X"` or `name: "X"` returns nothing on the template this chain itself
  scaffolds. See §D4.
- **The same template carries the iOS spelling inside a trailing `//` comment**
  (`destinations: .macOS,                    // or [.iPhone, .iPad]`). Any platform heuristic that
  greps the raw manifest classifies a macOS project as iOS off the comment that explains the macOS
  choice — CLAUDE.md rule 12, met in a generator rather than in an assertion. See §D4.
- **`stop-gate.sh`'s exit-code map has exactly one bucket that is neither clean nor a test
  failure**, and it is `125|126|127`: `echo "stop-gate: test timeout/not executable — fail-open"`,
  `$OUT` removed, exit 0, and — decisively — `$DIRTY` **not** removed, so the gate stays armed.
  `0` clears the dirty marker; every other non-zero value reaches
  `emit_block "Tests failed (exit $RC)"`. `3`, this repository's convention for its own checkers,
  lands in that last bucket. See §D5.
- **`worktree-isolation-contract.test.sh`'s `M3` cannot see a third candidate.** Its population is
  `grep -F 'CMD="xcodebuild'`, which the new branch's `CMD="cd \"…\" && command -v tuist …` line
  does not match. `M3` therefore stays at its expected count of 2 and stays green, correctly, over
  a population that no longer means "every generated `xcodebuild` candidate". See §D7.
- **Naming that file in the plan would falsely cover this entire feature.** Measured with the
  anchored token scan `spec-coverage.sh` itself uses: `worktree-isolation-contract.test.sh` carries
  `R-01` … `R-19`, and it already names `ADR-0159`, which the plan cites — so ADR-0154's
  back-reference half is already satisfied for it. Naming its basename anywhere in the plan
  satisfies half 1 too, scoping it in and reporting all eight of this feature's ids `COVERED`
  before a line is written. `prep.test.sh`, by the same scan, carries **zero** `R-NN` tokens. See
  §D7.
- **`plant-check.sh` mechanically refuses a plant declared in `prep.test.sh` as it stands.**
  `if ! grep -qE "(printf|echo)[^#]*FAIL: " "$TESTS/$tfile"` → `BADPLANT`. `prep.test.sh`'s `no()`
  prints `FAIL <label>` with no colon. Measured across all 86 harnesses on 2026-08-22, three still
  lack the emitter — `hook-probe`, `hook-verify-workflow`, `prep` — not the five `plant-check.sh`'s
  own comment names (`external-dependency-gate` was converted on 2026-08-21, commit `73241e5`;
  `phase1` earlier). See §D6.
- **`spec-coverage.sh` cannot see a `(no-test: …)` marker on a wrapped checklist item.** Measured
  on a two-item fixture, 2026-08-22: the marker on the `- [ ] R-NN —` opener line is honoured
  (`COVERED`); the identical marker on a continuation line of the same item is invisible
  (`UNCOVERED … tests`, exit 1). Both of this SPEC's markers are on continuation lines. See §D8.

## Decision

### D1 — a new first branch: the stack is read from the tracked manifest, never from the artifact

`detect-test-cmd.sh`'s `if`/`elif` chain gains one branch **ahead of** the `*.xcworkspace` and
`*.xcodeproj` globs:

```
Project.swift | Tuist.swift | project.yml | project.yaml   at $ROOT
        →  STACK="xcode-project-generated"
```

Ordering is the point, not an implementation detail. The two existing globs match artifacts that
are gitignored on exactly the projects this branch is for, so on a fresh worktree they match
nothing, and on a stale checkout they match the wrong thing. A tracked manifest is present in every
worktree of every checkout, always, which is the only property that closes context item 1 above.

"Tracked" here is descriptive, not a check performed: no `git ls-files` call is added. The detector
is pure filesystem inspection today and stays that way, so it behaves identically inside and
outside a git repository (see A4).

### D2 — the branch is generator-agnostic; the tool is chosen by which manifest is present

`STACK` is `xcode-project-generated`, the SPEC's own tool-neutral name, and the branch resolves a
regeneration tool from the manifest it found:

| manifest at `$ROOT` | tool | regeneration command |
|---|---|---|
| `Project.swift` or `Tuist.swift` | `tuist` | `tuist generate --no-open` |
| `project.yml` or `project.yaml` | `xcodegen` | `xcodegen generate` |

This is the one place this ADR knowingly reads the SPEC's *intent* over its letter. The SPEC lists
`project.yml` inside a branch it calls the "Tuist-managed" one and asks for a `tuist generate &&`
prefix; `project.yml` is XcodeGen's manifest (measured above), and a `tuist generate` prefix on an
XcodeGen project is a command that cannot ever succeed. Both declared requirements survive intact:
`R-01` asks that a tracked manifest from that list is detected ahead of the `*.xcodeproj` glob — it
is, by one branch — and `R-02` asks that **a detected Tuist-managed project** carries a
`tuist generate &&` prefix — it does, because `Project.swift`/`Tuist.swift` resolve to `tuist`. The
`project.yml` case is not a Tuist-managed project and `R-02` says nothing about it.

`--no-open` is not optional. Without it `tuist generate` launches Xcode, inside a Stop hook, on a
machine nobody is watching.

### D3 — the candidate is `cd`-anchored and names a scheme, not a project

The generated line, in full, for a Tuist project named `Ondum` rooted at `/abs/root`:

```
cd "/abs/root" && command -v tuist >/dev/null 2>&1 || { echo 'DID-NOT-RUN: tuist absent from PATH — the generated Xcode project was NOT regenerated and xcodebuild was NOT run (issue #470, ADR-0165)' >&2; exit 127; }; tuist generate --no-open && xcodebuild test -scheme "Ondum" -destination 'platform=macOS' -derivedDataPath "/abs/root/.build/DerivedData"
```

Three choices in there, each with a reason:

- **`cd "<abs-root>" &&` at the front.** `stop-gate.sh` runs the command as `bash -c "$CMD"` with no
  `cd` of its own, from whatever cwd the hook process happens to hold. Both generators default to
  the current directory, and `xcodebuild -scheme` resolves its project or workspace from the current
  directory. Anchoring cwd once, absolutely, at detection time, is the same property ADR-0159 D1
  established for `-derivedDataPath` and the same reason: the value written must not depend on where
  a later invocation is standing.
- **`-scheme` with no `-project`.** This is `git-repo-init`'s documented, verified recipe, read
  rather than assumed. It is also the more robust form: `tuist generate` emits a `.xcworkspace`
  alongside the `.xcodeproj` (both appear in the scaffold's `.gitignore`), and `xcodebuild -scheme`
  in that directory resolves the workspace, which is what a project with SPM dependencies needs.
  Naming `-project "<name>.xcodeproj"` explicitly would have picked the weaker of the two artifacts
  on exactly the projects this branch exists for.
- **`-derivedDataPath "<abs-root>/.build/DerivedData"`.** ADR-0159 D1, unchanged and extended to
  the third candidate. The guarantee it states — *every* generated `xcodebuild` candidate names its
  own build root — is preserved here by construction; what does not extend automatically is the
  assertion that checks it (§D7).

### D4 — the scheme name and the platform are derived from the manifest, with a documented fallback

Both values are resolved at detection time, by text, with no tool executed and no command
substitution left in the written line. A command substitution in a TOFU-approved string is a review
surface at Gate 2b that buys nothing here.

**Scheme name**, first match wins:

1. `let projectName = "X"` — `git-repo-init`'s own template idiom, and therefore the first thing to
   try on a project this chain scaffolded.
2. `Project(name: "X"` — the single-line manifest form.
3. `^\s*name: "X"` — the multi-line manifest form, first occurrence.
4. `^name: X` — `project.yml`'s top-level key, which XcodeGen's own source confirms is the produced
   project's basename.
5. `basename "$PWD"` — the fallback, and the answer for a `Tuist.swift`-only root, which carries no
   project name at all.

**Platform**, and the comment-stripping is the load-bearing part: `//` (Swift) or `#` (YAML) to end
of line is removed *before* the scan, then an iOS signal (`.iOS`, `.iPhone`, `.iPad` on a
`destinations:`/`deploymentTargets:`/`platform:` key) selects
`platform=iOS Simulator,name=iPhone 17`; absent that, `platform=macOS`. Without the strip, the
scaffold template's own `// or [.iPhone, .iPad]` classifies every macOS project as iOS — rule 12
inside a generator.

The two existing branches keep their hardcoded iOS destination and are not harmonised with this
one. That is rule 6 read in the direction it actually points: they answer a *different* question,
"what destination for a project I cannot introspect", because a bare `.xcodeproj` glob has no
manifest to read. This branch has the manifest open in its hand; declining to read it for the sake
of looking like its neighbours would be consistency bought with correctness.

Every one of these is a heuristic, and none of them needs to be perfect, because the artifact is a
**candidate**: it is written untrusted, shown to a human at Gate 2b, and can only ever run after
that human approves it. That is the entire reason a heuristic is acceptable here and would not be
acceptable in something auto-trusted.

### D5 — the DID-NOT-RUN exit code is `127`, and it is `127` because of the consumer

When the regeneration tool is absent from `PATH` at run time, the command emits one line on stderr
beginning `DID-NOT-RUN:` and exits **127**, before `xcodebuild` is reached.

This repository's stated convention for a check that could not execute is exit 3 (CLAUDE.md rule 4),
and this decision does not use it. The reason is that **an exit-code convention belongs to the
consumer, not to the producer**, and this producer has a consumer with a fixed, pre-existing map:

| value | what `stop-gate.sh` does |
|---|---|
| `0` | clears `$DIRTY`, `$CF`, `$SF`, the fingerprint cache — a verified tree |
| `124` | timeout, fail-open, increments the distinct-failure counter |
| `125` `126` `127` | *"test timeout/not executable — fail-open"*, `$OUT` removed, **`$DIRTY` kept** |
| anything else non-zero | `emit_block "Tests failed (exit $RC)"` — armed, reported as a regression |

Exit 3 lands in the last row: the chain would report a missing build tool as a test failure in the
code under test, which is precisely the misreading `R-05` exists to prevent. Exit 127 lands in the
third row, which is already, in behaviour, a genuine third state — no green, no block, and the
dirty marker deliberately preserved so the next Stop asks again. Rule 4 asks for a state distinct
from a clean result; in this consumer, 127 is that state and 3 is not.

Two further properties made 127 the choice rather than an arbitrary unused code:

- **The explicit guard and the implicit fall-through agree.** 127 is the shell's own
  command-not-found status, so if a future edit deletes the `command -v` guard, `bash -c` still
  returns 127 for the same condition. Two paths, one answer, no silent divergence.
- **`xcodebuild` does not produce it.** Its failure statuses (65, 66, 70, 1) are disjoint from the
  shell's reserved 126/127, so DID-NOT-RUN can never be confused with a real test failure.

The explicit `command -v` guard is kept even though the implicit path yields the same code, because
the guard is what puts a legible `DID-NOT-RUN:` string into the output and into the written
candidate — the implicit path leaves nothing in the artifact to assert against, and an
exit-code convention nobody can grep for is a convention that decays unobserved.

### D6 — `prep.test.sh` is made able to carry evidence before any evidence is put in it

`prep.test.sh`'s `no()` prints `FAIL <label>`. `plant-check.sh` refuses outright to run a plant
declared in a harness lacking a `FAIL: ` emitter, so as it stands **every assertion added to this
file would be unplantable by construction** — CLAUDE.md rule 2 with no path to satisfying it. Its
`-derivedDataPath` assertions already carry a written disclosure of exactly this, and pushed the
real evidence into the worktree-isolation contract harness instead; §D7 explains why that escape
route is closed this time.

`no()` is therefore converted to `echo "FAIL: $1"` and the new assertions take fixed-width ids
(`TU01` …, floor `TU99`). Nothing parses this harness's stdout — CI branches on its exit status,
`plant-check.sh` greps `^FAIL: ` — so the blast radius is nine output lines changing prefix. This
is the established direction of travel, not a new idea: `phase1` and `external-dependency-gate`
were converted the same way, leaving three files with the old form of which this is one.

One residual is recorded rather than fixed: the nine pre-existing labels have no ids, so
`red_re()`'s anchored match would credit a hypothetical plant with assertion id `detect` to
`FAIL: detect: swift package`. No such plant exists, none is declared here, and giving nine
unrelated assertions ids is a rewrite this feature has no reason to make.

### D7 — `M3` is left alone, and the guarantee it stands for is re-pinned behaviourally instead

ADR-0159's `M3` counts `-derivedDataPath` across lines matching `grep -F 'CMD="xcodebuild'` and
expects exactly 2. The new candidate's line begins `CMD="cd \"…\" && command -v tuist …`, so it is
outside that population: `M3` stays at 2, stays green, and its message ("BOTH xcodebuild
candidates, xcworkspace and xcodeproj") stays literally true. Nothing it says becomes false. What
becomes false is the *impression* that it covers every generated `xcodebuild` candidate — rule 8,
a check blind by construction to what its list omits.

The obvious repair — widen `M3` to count 3 — is refused, and the reason is measured, not
aesthetic. `worktree-isolation-contract.test.sh` carries `R-01` … `R-19` from its own feature's
SPEC and already names `ADR-0159`, which the implementation plan cites. Naming its basename in the
plan satisfies both halves of ADR-0154's scope filter, pulling it into this feature's scoped test
population, where its 19 foreign ids satisfy all eight of this feature's requirement ids by token
collision (ADR-0157, ADR-0138, CLAUDE.md rule 18). The feature's own gate would report `8 covered`
against work that does not exist. The plan therefore never writes that basename out, and says so.

So the guarantee moves to a better home rather than being dropped. `prep.test.sh` gains a fixture
assertion that the **generated** candidate contains
`-derivedDataPath "<abs-fixture-root>/.build/DerivedData"` — behavioural evidence read off the
artifact the script actually wrote, which is strictly stronger than `M3`'s count of source-text
occurrences, and which a future restructuring of the branch cannot pass by accident.

The two existing `CMD="xcodebuild` lines are consequently **byte-frozen**. `M3`'s plant declaration
names the `-project` line verbatim as its needle, and `plant-check.sh` requires a needle to match
exactly one site: reformatting that line, or factoring a shared suffix out of the two, turns a live
plant into a `BADPLANT` in a file this feature never touches.

### D8 — what is enforced, what is documented, and what blocks the feature before it starts

**Enforced by an executed assertion** (fixture-based, `mktemp -d` roots, no Tuist or XcodeGen
binary, no network, no real Xcode project, no `git`):

- Branch ordering ahead of the `*.xcworkspace`/`*.xcodeproj` globs, asserted against a fixture that
  carries both artifacts *and* a manifest.
- Each manifest shape resolving to the right tool, including `project.yml` resolving to `xcodegen`
  and **not** to `tuist`.
- Present in the written candidate: the regeneration prefix, `--no-open`, the `cd` anchor, the
  derived scheme across all five derivation branches, the derived platform including the
  comment-strip case, `-derivedDataPath` at an absolute per-fixture path, the `DID-NOT-RUN:` string
  and the literal `exit 127`.
- The candidate being exactly one line and surviving `stop-gate.sh`'s own first-non-comment-line
  `awk` read byte-identically.
- **The guard's own runtime behaviour, executed.** The extracted line is run under `bash -c` with a
  `PATH` pointing nowhere: exit status 127, `DID-NOT-RUN` on stderr, `xcodebuild` never reached.
  This works precisely *because* the tool is absent — absence is the condition under test and this
  machine's actual state, so no install could make the assertion more real. A companion run with
  stub `tuist`/`xcodebuild` scripts on `PATH` returns the stub's 65, pinning DID-NOT-RUN as
  distinguishable from an ordinary test failure rather than merely asserting that it is.
- `Tuist/Package.swift` reaching the `swift-package` branch; the existing branches unchanged; an
  existing `.claude/test-cmd` left untouched.

**Documented instruction only, no assertion (`R-07`, rule 16).** This repository has no Tuist
install, no XcodeGen install, no Xcode project and no CI runner with any of them, so exactly two
things go unexecuted and they are named rather than gestured at:

1. **The success path.** A real `tuist generate --no-open` followed by a real `xcodebuild test`.
   That the generator in fact emits a scheme of the derived name, and that `xcodebuild -scheme`
   resolves the workspace it emits, rest on `git-repo-init`'s documented recipe and on upstream
   documentation read 2026-08-22 — not on an execution here.
2. **`stop-gate.sh`'s routing of a 127 arriving from a real suite.** That routing is pre-existing
   and separately covered by that hook's own harness; nothing in this feature re-asserts it.

Note what is *not* on that list: the DID-NOT-RUN exit path itself is executed (above). An earlier
draft of this ADR assumed it could not be, on the reasoning that testing anything about the tool
required having the tool. The opposite is true for this branch, and overstating what is untested is
the same defect as overstating what is tested.

**Out of scope by decision, not by omission.** No Step 5.0.4c pre-flight gate is added. ADR-0159
paired its generator fix (D1) with a pre-flight refusal (D2) for already-trusted commands, and the
asymmetry here is deliberate: the SPEC lists "migrating already-trusted `.claude/test-cmd` files on
existing Tuist projects to the new prefix form" as explicitly out of scope, and a pre-flight refusal
*is* that migration, imposed at the point of maximum inconvenience. An existing trusted command
keeps working; it picks up the prefix the next time its candidate is regenerated from scratch and
re-approved. `R-08`'s subjects — `git-repo-init`'s `.gitignore` authoring at `swift-xcode-setup.md`,
`xcodebuild`, Tuist — are untouched; the scaffold's gitignore is correct as written and this fix is
the missing counterpart to it, not a replacement.

**A blocker no task in the plan can clear.** Measured 2026-08-22: `spec-coverage.sh` parses
`(no-test: …)` line-wise, from the `- [ ] R-NN —` opener line only. Both of this SPEC's markers sit
on continuation lines of wrapped items, so `R-07` and `R-08` report `UNCOVERED … tests` and the
gate exits 1 before any work exists. The fix is an edit to `SPEC.md` — reflow `R-07` and `R-08` so
the `(no-test: …)` clause opens on the opener line — which is outside the architect's write scope,
outside the coder's, and outside the tester's. It is the operator's call at Gate 2. Verified on a
reflowed copy: 8 declared, 8 covered, 0 uncovered, exit 0. The underlying blindness in
`spec-coverage.sh` is a real defect against CLAUDE.md rule 3 (a clause is the same clause whether it
wraps) and is deliberately **not** fixed here: it is the gate that measures this feature, its own
harness carries a colliding `R-NN` namespace, and changing the instrument in the same batch as the
measurement is not a trade this feature should make. It wants its own issue.

## Alternatives considered

**A1 — run `tuist generate` at candidate-write time to discover the produced artifact's real
name.** The SPEC offers this as one of two suggested derivations. Rejected on three counts.
`detect-test-cmd.sh` executes nothing today — it is pure filesystem inspection, which is why it is
hermetically testable and why it behaves identically on every machine; adding a side-effecting
build tool to a detector inverts that. It would produce *different candidates depending on whether
the tool is installed on the detecting machine*, so the machine least able to run the tests writes
the most degraded command. And the whole apparatus exists to survive the tool's absence, which the
approach cannot do at the very moment it matters.

**A2 — a run-time glob, `-project "$(ls -d *.xcodeproj | head -1)"`, evaluated after generation.**
Rejected: it puts a command substitution inside a string the TOFU mechanism pins by SHA and a human
approves by reading. Gate 2b's reviewer would be approving something whose effect is not visible in
what they are shown. It also re-introduces the cwd dependency D3 exists to remove, and it is
unnecessary once `-scheme` alone is used.

**A3 — keep `-project "<derived>.xcodeproj"` exactly as the SPEC's architecture section spells
it.** Rejected in favour of `git-repo-init`'s documented recipe, which the SPEC itself named as the
alternative source of truth. `tuist generate` emits a `.xcworkspace` next to the `.xcodeproj` — both
are in the scaffold's `.gitignore` — and `-project` selects the one that cannot resolve SPM
dependencies. The SPEC's letter would have generated the weaker command on precisely the projects
this branch was written for.

**A4 — verify the manifest is git-tracked before trusting it, with `git ls-files --error-unmatch`.**
Rejected: "tracked" in the SPEC is a description of why a manifest survives a worktree fork, not a
predicate to evaluate. Executing it would make the detector fail differently outside a repository,
inside a submodule, and during `git-repo-init`'s own pre-first-commit bootstrap — where an untracked
`Project.swift` is exactly the correct thing to detect.

**A5 — exit 3 for DID-NOT-RUN, matching this repository's convention.** Rejected, and this is the
decision most likely to be re-litigated, so §D5 states the reasoning at length. The short form:
exit 3 is the convention for scripts whose *caller is this repository's own fence code*, which
branches on 3 explicitly. The generated test-cmd's caller is `stop-gate.sh`, whose map predates
this fix and routes 3 into `emit_block "Tests failed (exit 3)"` — a missing build tool reported as a
regression in the code under test, the exact misreading `R-05` forbids.

**A6 — a novel, unused exit code (e.g. 111) reserved for this convention.** Rejected: it lands in
the same "anything else non-zero" bucket as 3 and buys nothing, while breaking the agreement
between the explicit guard and the implicit `command not found` fall-through that makes 127 robust
to the guard being deleted.

**A7 — widen `M3` in the worktree-isolation contract harness to expect 3 candidates.** Rejected on
measurement: naming that file in the plan scopes in its 19 foreign `R-NN` tokens and reports all
eight of this feature's ids covered before any work exists (§D7). The guarantee is re-pinned
behaviourally in `prep.test.sh` instead, which is a stronger check than the one being declined.

**A8 — add a `nof()` second reporter to `prep.test.sh` so only the new assertions emit `FAIL: `.**
Rejected: it satisfies `plant-check.sh`'s file-level grep while leaving two reporters in one file
with no guard against a future assertion picking the wrong one and becoming silently
unattributable. Converting `no()` outright leaves no such state to get wrong, and the measured blast
radius is nine output lines nothing parses (§D6).

**A9 — add a Step 5.0.4c pre-flight gate refusing a trusted `xcodebuild` test-cmd on a repository
that has a Tuist manifest and no regeneration prefix**, mirroring ADR-0159 D2. Rejected: that gate
*is* the forced migration the SPEC places out of scope, and it would halt Step 5 on every existing
Tuist project until its operator re-approves a command that works today. Recorded here because the
asymmetry with ADR-0159 is deliberate and a future reader will otherwise read it as an oversight.

**A10 — fix `spec-coverage.sh`'s continuation-line blindness in this feature.** Rejected: it is the
instrument measuring this feature, its harness carries a colliding requirement-id namespace, and
the SPEC's scope does not include it. Recorded as a defect wanting its own issue (§D8).

**A11 — a fixed `-destination` literal on the new branch, copied from the two sibling branches.**
Rejected: `git-repo-init`'s Tuist scaffold is macOS-first and the sibling literal is iOS, so a copy
generates the wrong destination for the projects this branch exists to serve. Rule 6 does not apply
— the siblings answer a different question, having no manifest to read (§D4).

## Consequences

**Positive.**

- A worktree forked with `baseRef: head` on a generated-Xcode-project repository now detects a
  stack at all. The tracked manifest is present in every worktree by construction, which the
  gitignored artifact never was.
- The project under test is regenerated from the manifest immediately before `xcodebuild` reads it,
  so a source file that arrived by merge, checkout or merge-back is in the target that runs. The
  false-green class described in context item 2 is closed for every project detected by this branch.
- A missing regeneration tool is reported as a missing regeneration tool. In `stop-gate.sh`'s own
  behaviour that is a third state — no green, no block, dirty marker preserved — rather than a
  fabricated regression in someone's code, and that guard's runtime behaviour is executed by an
  assertion rather than asserted in prose.
- `tuist generate --no-open` will not launch Xcode inside a Stop hook on an unattended machine.
- XcodeGen projects get a working regeneration prefix rather than a `tuist` invocation that could
  never have succeeded — a defect the SPEC would have shipped, caught by reading the upstream docs
  rather than the issue.
- ADR-0159's build-root guarantee now has behavioural evidence (read off a generated candidate)
  where it previously had only a source-text count, and that evidence extends to candidates the
  count cannot see.
- `prep.test.sh` becomes plant-capable, closing one of the three remaining harnesses in this
  repository where rule 2 could not be satisfied at all.

**Negative.**

- **The success path is unverified here and cannot be verified here.** No Tuist, no XcodeGen, no
  Xcode project, no CI runner with any of them. Whether `tuist generate --no-open` in fact produces
  a scheme matching the derived name, and whether `xcodebuild -scheme` resolves the generated
  workspace as `git-repo-init`'s recipe says it does, rest on that skill's documented recipe and on
  upstream documentation read on 2026-08-22 — not on an execution. This is `R-07`'s subject and it
  is the largest single risk in the change.
- **The scheme-name derivation is a heuristic with five branches and a fallback.** A manifest that
  computes its name, interpolates it, or declares targets before the project will resolve to the
  directory basename. The mitigation is Gate 2b, where a human reads the command before it can run
  — which is a real mitigation and also an admission that the derivation is not authoritative.
- **A Tuist project with a `Workspace.swift` is not specially handled.** `-scheme` alone happens to
  do the right thing there, but by inheritance from `xcodebuild`'s resolution rules rather than by
  anything this fix decided. Not in the SPEC, not implemented, recorded so the silence is not later
  read as coverage.
- **`tuist generate` failing for a reason other than absence** (a manifest that does not compile, a
  dependency that will not resolve) exits with the tool's own status, which lands in
  `stop-gate.sh`'s ordinary-failure bucket and is reported as a test failure. Defensible — a project
  whose manifest does not compile is genuinely broken — but it is not the DID-NOT-RUN state, and the
  distinction is not drawn.
- **`M3`'s population silently narrows** relative to what its name suggests. It remains true and
  green; a reader who assumes it covers every generated `xcodebuild` candidate is now wrong. §D7 is
  the only thing recording that, and prose is not enforcement (rule 16).
- **An already-trusted `.claude/test-cmd` on an existing Tuist project keeps testing a stale
  project** until someone regenerates and re-approves its candidate. This is the SPEC's explicit
  out-of-scope choice (`R-06` asserts the non-interference), and A9 records why no pre-flight gate
  forces the issue.
- **The feature is blocked at its own gate until `SPEC.md` is reflowed by hand** (§D8) — an
  operator action at Gate 2, with no code path to it.

**Neutral.**

- No new file, no new helper, no new dependency, no `sync-to-claude.sh` PAIRS entry
  (`plugin/scripts/detect-test-cmd.sh|hooks/detect-test-cmd.sh` already exists), no `docs-ci.yml`
  append (`prep` is already in the named `shell-tests` list, and `ci.yml` globs `*.test.sh`).
- `detect-test-cmd.sh`'s own interface is unchanged: `--root <dir> [--dry-run]`, exit 0 on success,
  exit 2 on bad invocation. The new surface is the *generated command's* exit-code contract, which
  had no prior definition.
- The trust registry's shape, `approve-test-cmd.sh`, and the per-SHA trust model are untouched. A
  regenerated candidate hashes differently from any prior trusted candidate for the same root, which
  is what forces a fresh Gate 2b approval — an existing mechanism doing what it already does, not a
  new one.
- Step 5.0.4b keeps passing on the new candidate without modification: it fires on a test-cmd naming
  `xcodebuild` and requires `-derivedDataPath`, both of which the new line carries.
- The iOS destination spelled here (`iPhone 17`) differs from `git-repo-init`'s reference
  (`iPhone 16`). Kept consistent with the two sibling branches inside the file being edited rather
  than with the reference document; cosmetic, and not reconciled by this change.
- No external dependency is declared for this feature. `tuist` and `xcodegen` are tools it detects
  the *absence* of, not resources it needs provisioned; an `EXTERNAL DEPENDENCY: … provisioned:
  false` line would make ADR-0060's G13 gate exit 1 and halt a feature whose subject is that
  absence.

## References

- Issue #470
- SPEC.md — `R-01` … `R-08`
- ADR-0159 — `-derivedDataPath`, one build root per checkout; the generator this ADR extends, and
  the source of `M3`
- ADR-0068 — the worktree isolation contract; `isolation: worktree` bounds cwd, not the filesystem
- ADR-0014, ADR-0020 — TOFU trust is per-file-SHA and stays human; the chain proposes, it never
  trusts
- ADR-0023 — `detect-test-cmd.sh` D3, the script's original contract
- ADR-0049 — generator/verifier separation; why every test-file edit in the plan belongs to the
  tester
- ADR-0060 — the external-dependency declaration and G13, and why this feature declares none
- ADR-0108, ADR-0145 — the plant registry, the anchored fired-predicate, and the `FAIL: <id>`
  emitter requirement that gates §D6
- ADR-0138, ADR-0154, ADR-0157 — requirement-id scope, the back-reference filter and the
  cross-feature id collision that decides §D7
- `staging/plugin/skills/git-repo-init/references/swift-xcode-setup.md` — the `.gitignore` block,
  the `Project.swift` template, and the `tuist generate --no-open` + `xcodebuild -scheme` recipe
- Tuist documentation via Context7 (`/tuist/tuist`, `main`), read 2026-08-22 — `tuist generate
  --no-open`; the XcodeGen-vs-Tuist directory-shape contrast
- XcodeGen documentation and `Sources/XcodeGenCLI/Commands/GenerateCommand.swift` via Context7
  (`/yonaskolb/xcodegen`, `master`), read 2026-08-22 — `xcodegen generate` reads `project.yml` from
  cwd; the produced path is `projectDirectory + "\(project.name).xcodeproj"`
- CLAUDE.md rule 2 (§D6), rule 4 (§D5), rule 6 (§D4), rule 8 (§D7), rule 12 (§D4's comment strip),
  rule 13 (every premise above re-derived on 2026-08-22), rule 16 (§D8), rule 18 (§D7)
