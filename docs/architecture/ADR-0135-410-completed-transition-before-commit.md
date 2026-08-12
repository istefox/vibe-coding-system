# ADR-0135 — Order the manifest `completed` transition before the Step 7 commit

- **Status:** Accepted
- **Date:** 2026-08-12
- **Issues:** #410 (filed 2026-08-11), #357 (filed 2026-08-03 — the same defect, see §Context)
- **Supersedes / amends:** nothing. Extends ADR-0104 (Step 7.0), ADR-0106 (Step 7.0b) and
  ADR-0071 (Gate 4.0) by inserting one ordered step between them and the `commit` invocation.
- **SPEC:** `SPEC.md` (topic slug `410-order-the-manifest-completed-transit`)

---

## Context

`concept-to-code` Step 7 invokes the `commit` skill and only afterwards transitions the manifest to
`completed`. The manifest is committed while still `step_7_commit` / `in_progress`, and the
transition that follows is an uncommitted working-tree change that nothing ever commits.

`manifest-validate.sh` invariant 4 requires `project_root` to be an existing directory unless the
chain is terminal (ADR-0078, extended to both terminality axes by ADR-0113). `project_root` is an
absolute machine-specific path, so a committed non-terminal manifest validates on the machine that
produced it and fails everywhere else. `manifest-project-root-terminal.test.sh` `C1` validates the
whole corpus, so this reddens CI while staying green locally. Observed on PR #409:

```text
FAIL: C1: 2 of 56 still invalid — 2026-08-11-399-bound-phase-p-step-3-to-roadmap-stat.manifest.yml
                                  2026-08-11-a-per-file-budget-ceiling-is-parsed-and.manifest.yml
```

Both manifests were transitioned by hand and committed. The chain's own text still says to do it
the other way round.

### It was filed twice, eight days apart, and that is the first finding

Issue **#357** (2026-08-03) describes the same defect, names the same invariant, and is **already a
roadmap row** — item 3 of PROJECT.md's "Three attended items the waves cannot hold (2026-08-04)"
table, whose *done means* column reads: *"The manifest reaches a terminal state before the commit
that ships it, with the ordering asserted."* #410 rediscovered it from CI evidence, with no
awareness of #357.

Two things follow. The re-filing is not noise — #357 had no mechanism attached, so the defect was
recorded and then reintroduced by every subsequent run; a row in a table is not a guard. And this
ADR closes **both**. The remedy #357 asks for and the remedy #410 asks for are the same remedy, and
the *"with the ordering asserted"* half of #357's exit condition is what §D5 below is for.

Issue #357 also carries a measurement #410's SPEC does not: five of this repository's manifests record
`project_root: "/Users/stefer/developer/vibe-coding-system"` with a **lowercase `d`**. macOS
resolves that case-insensitively, so it validates locally; Linux does not. That is the mechanism by
which a locally-green corpus fails on the runner, and it is worth keeping because it explains why
the class stayed invisible for so long: on this machine every path resolves.

### Measurements taken before designing

Re-derived on 2026-08-12 from this checkout, not inherited from either issue. A count in a prior
document is a snapshot of its moment (ADR-0107's lesson, applied to the two issues above).

| Fact | Value |
|---|---|
| Manifests in `docs/manifests/` | 57 on disk, 56 tracked (the 57th is this chain's own, untracked) |
| `chain_path` distribution | 36 `standard`, 19 `null` (legacy), **0 `express`, 0 `hybrid`** |
| `current_step` distribution | 52 `completed`, 3 `aborted`, 1 `step_0_init`, 1 `step_2_architecture` |
| `project_root` distribution | 47 correctly-cased, 5 lowercase-`d`, 5 from another machine |
| Commit-invoking steps in `concept-to-code/SKILL.md` | 3 — Step 7 (Standard), E4 (Express), H5 (Hybrid) |
| Standard Step 7 transition | `SKILL.md:2796`, **prose only** — *"Transition to `completed`. Write final report."* |
| Express E4 transition | `SKILL.md:2881`, a command, **after** the commit invocation |
| Hybrid H5 transition | `SKILL.md:2986`, **prose only**, on the same line as and after the invocation |
| Manifest passed to `commit --include` | Standard Step 7 only (`SKILL.md:2729`) |
| Lines naming a `manifest-*.sh` helper | 61 |
| Lines matching `manifest-transition.sh … completed completed` | 3 — `:458` (a §4 usage sample), `:2866` (Gate E3 "Commit later"), `:2881` (E4) |
| `manifest-set-artifact.sh` terminal guard | **none** — it writes to a terminal manifest without complaint |
| `manifest-transition.sh` same-to-same | returns 0, a documented no-op (`:41`) |
| Legal transition pairs | 45 (`transition-pair-count.sh`), unchanged by this feature |

Four consequences of that table shaped the scope.

1. **The Standard path's transition is not a command at all.** It cannot be ordered relative to an
   invocation because it is prose, 69 lines below it. This is the PATH-RULE class ADR-0028 and
   ADR-0117 already fixed twice in this same file, and it is plausibly *why* the ordering drifted:
   there was no instruction to order. H5 is the same, in one clause on the invocation's own line.
2. **E4 and H5 have never run here** — zero Express and zero Hybrid manifests exist. Fixing them is
   a forward guard, not a repair of observed damage.
3. **On E4 and H5 the manifest is never committed at all.** No Gate 4.0, no `--include`, and
   `commit` never stages untracked files. So the reported defect cannot currently manifest there; a
   different gap sits in its place, and it is filed rather than fixed (§D7).
4. **The corpus is green today by an accident worth naming.** The one tracked manifest whose
   `current_step` is non-terminal (`2026-07-31-the-sixth-bare-manifest-set-flag-sh-ment`, at
   `step_0_init`) carries `status: "aborted"`, so ADR-0113's second terminality axis exempts it.
   Without that widening — shipped nine days before #410 — `C1` would already have been red on CI
   for an unrelated file. #410 is the case where **neither** axis is terminal.

---

## Decision

### D1 — The transition moves before the `commit` invocation at all three commit-invoking steps

Step 7's sequence becomes, in this order:

1. **7.0** — collapse the Step 5 snapshots (ADR-0104). Unchanged.
2. **7.0b** — archive this chain's SPEC and repoint `artifacts.spec` (ADR-0106). Unchanged.
3. **7.0c** — *new*: transition to `completed`.
4. The `commit` invocation with `--include <archived-spec-path>,<manifest-path>`. Unchanged.
5. **7.1** — *new*: classify what `commit` did (§D3).
6. Post-commit actions — conditional push, PROJECT.md update, cost snapshot, final report — now
   gated on 7.1's verdict.

**7.0c must follow 7.0b, and that ordering is load-bearing rather than tidy.**
`manifest-set-artifact.sh` has no terminal guard: a repoint after the transition would succeed
silently and land outside the commit — the same defect one write over, in a file whose whole
subject is that defect. §D5's guard enforces this mechanically rather than asserting it in prose.

E4 and H5 get the same ordering. H5's prose clause and Step 7's prose sentence both become explicit
`manifest-transition.sh` invocations carrying the absolute
`~/.claude/skills/concept-to-code/scripts/` prefix, per the PATH-RULE convention ADR-0028 and
ADR-0117 established for this file.

### D2 — The invariant is stated once, and it is about writes, not about steps

Step 7 carries one line at 7.0c:

> **Every manifest write in this step precedes the `commit` invocation, and this transition is the
> last of them.** A manifest write after `commit` is an uncommitted change nothing ever commits.

It is deliberately phrased over *manifest writes* rather than over the numbered sub-steps. A
restatement of the step list ages the moment a sub-step is inserted, and inserting a sub-step is
exactly how this defect would return. Phrased this way it also covers the write nobody has thought
of yet, which is the only kind that matters.

Verified rather than assumed: none of the post-commit actions writes the manifest. The push block
runs `git remote`/`git push`, the PROJECT.md block seds `PROJECT.md`, the cost snapshot runs
`usage-snapshot.py`, and the final report is chat output. That is what makes the manifest *final*
at commit time rather than merely usually-final.

### D3 — Declined commit: stop and report; and the check is on the manifest, not on the skill

Once the transition precedes it, declining `commit`'s own HITL gate leaves a terminal manifest over
an uncommitted tree. Terminal states are absorbing (ADR-0078's exemption rests on exactly that), so
there is no legal way back. The chain **stops and reports it** — no rollback, no invented
transition pair, no post-commit actions. An edge case reported loudly beats a state machine
weakened to accommodate it.

The classification is a declared, wrapped fence contract, `c2c-step7-commit-outcome`, and it reads
**the manifest**, never the skill's prose:

- `COMMIT_OK` — the manifest on disk is terminal on both axes, tracked, and clean with respect to
  `HEAD`. Proceed.
- `COMMIT_UNCOMMITTED untracked|modified` — terminal on disk, not in the commit. Stop and report.
- `COMMIT_NONTERMINAL current_step|status` — committed but not terminal. Stop and report: 7.0c did
  not take effect, which is #410 itself.
- exit 3, `COMMIT_OUTCOME_NORUN <reason>` — no repo, no manifest. Report as **did not run**, not as
  a pass, and do not proceed.

Three properties earned that shape rather than the obvious one.

**It needs no pre-captured state.** The alternative — snapshot `HEAD` and the dirty set before the
invocation, compare after — needs two fences straddling a `Skill` call, and a fence borrowing a
variable bound in an earlier fence stops being independently executable (ADR-0090 §D). This reads
one file and one `git status` pathspec, after the fact, from outside.

**R-07 falls out instead of being special-cased.** On a resumed or already-committed run,
`manifest-transition.sh` is a same-to-same no-op, `commit` reports nothing to commit, and the
manifest is already committed and terminal — so the verdict is `COMMIT_OK`. "Nothing to commit" and
"declined" are not distinguished by asking the skill what happened; they are distinguished because
in one case the manifest is committed and in the other it is not. That is the same
absent-versus-invalid-versus-did-not-run discipline ADR-0076 states as a rule, applied to an
outcome rather than to a field.

**Terminality is read from the working-tree copy plus cleanliness, not from `git show HEAD:<path>`.**
Resolving a repo-relative path from an absolute one is ADR-0089's trap and ADR-0132's
`repo-rel-path.sh` dependency; a clean file is byte-identical to its committed copy, so the
question is answered without ever resolving a path.

### D4 — The outcome fence is Standard-path only, and that boundary is stated at E4 and H5

Its verdict is derived from the manifest's committedness, and on E4/H5 the manifest is **never**
committed (§Context, consequence 3). Applying it there would stop every Express and Hybrid run, for
a gap that is out of scope. Both steps therefore carry the ordering fix and one line saying the
Step 7 outcome check does not apply to them, naming the follow-up issue. That is honest; silently
omitting it would read as an oversight the next time someone compares the three steps.

### D5 — The guard is anchored on the two mechanisms and pairs by *nearest preceding manifest write*

A new harness, `commit-transition-order.test.sh`, derives its population from
`concept-to-code/SKILL.md` at run time. No heading, no block delimiter, no line number.
ADR-0083 §D3 measured heading-anchored extractors going silently vacuous — `plan-task-count` 43/0
→ 35 passed **and six assertions simply gone**, `scope-guards` misattributing its failure to the
guard it was checking. Anchoring on the mechanism removes the failure mode by construction: a
rename that breaks the guard is the same rename that breaks the thing being guarded.

Three predicates, all measured against the live file before being chosen:

| predicate | matches | note |
|---|---|---|
| commit invocation: line begins `Invoke` or `Use`, optional `the`, then `commit` (bare or backticked), then the word `skill` | 4 | Step 7, E4, H5, Gate 4.0 |
| manifest write: any line naming `manifest-<word>.sh` | 61 | deliberately broad, see below |
| terminal transition: `manifest-transition.sh` … `completed completed` | 3 pre-fix, 6 post-fix | |

**The pairing rule is: for each non-exempt commit invocation, the nearest *preceding* manifest write
must be a `completed completed` transition.** Not proximity, not adjacency in a two-kind stream, not
a region between successive commit invocations. Each of those was tried against the real file and
each **passes the pre-fix text**, which is disqualifying — an assertion that cannot go RED on the
defect it was commissioned for pins nothing:

- *nearest preceding terminal transition, within N lines*: Gate E3's "Commit later" transition sits
  **13 lines** above E4's invocation, so any threshold generous enough for a real pair swallows it.
- *adjacency in the {transition, commit} stream*: the pre-fix anchors already alternate
  `T,C,T,C,T,C`. No purely order-based rule over two kinds can separate the two files.
- *a region bounded by successive commit invocations*: every region contains some terminal
  transition pre-fix, including the §4 usage sample at `:458`. Vacuous.

Introducing the third anchor kind — *any* manifest write, not just a terminal transition — is what
breaks the alternation, and it makes the guard **literally the invariant of §D2** rather than a
proxy for it. Pre-fix the nearest preceding write is `manifest-set-artifact.sh:2712` for Step 7,
the `aborted aborted` transition at `:2872` for E4, and the helper mention at `:2957` for H5: three
violations, all three the real defect. Post-fix all three are the new transitions.

Four further decisions inside that rule:

**The write predicate is broad on purpose, and its failure direction is stated.** It matches a line
that merely *names* a helper as well as one that invokes it. A prose mention landing between a
transition and its invocation produces a false RED, never a false green — and it is arguably not
false, since §D2's invariant is that the transition is the *last* thing touching the manifest. There
is no waiver mechanism for it: an unused waiver is an untested waiver (ADR-0084 `S2`), and the
remedy if one is ever needed is to move the sentence.

**The commit predicate is narrow, and its failure direction is loud.** A file-wide grep for
"commit skill" matches 12 lines, mostly prose *about* the skill — the heading, two
`AskUserQuestion` option descriptions, two "No commit skill invoked" disclaimers. A case-insensitive
`invoke.*commit.*skill` matches five, the fifth being H4's `review-triage-fix` invocation, whose
line contains `step_h5_commit`. Rule 12, twice, in one predicate. Requiring the line to *begin* with
the invocation verb and name the commit skill immediately after resolves to exactly the four real
invocations. The cost is that a future *"Now invoke the `commit` skill"* is invisible — and the
count guard is what makes that loud rather than silent: fewer than three resolved pairs is a
failure, so a step dropping out of the population fails instead of quietly shrinking it.

**Gate 4.0 is exempt, by a declared line-scoped waiver.** It commits an in-flight manifest on
purpose (ADR-0071), and the rule is about writes inside a *commit-invoking step*, not a ban on ever
committing a non-terminal manifest. The waiver is
`<!-- commit-order-exempt: <reason ≥ 40 chars> -->` on the invocation line itself — ADR-0077's
principle that a waiver travels with what it excuses — and the guard runs it in reverse: a declared
exemption that no longer sits on a matching line is a stale waiver, and a stale waiver reads exactly
like a clean bill of health (ADR-0081 `ZA4`).

**A terminal transition with no invocation after it is never examined.** The guard iterates over
invocations, so Gate E3's "Commit later", the abort branches and the §4 usage sample are outside it
structurally rather than by exclusion. That is asserted positively — at least one terminal
transition must remain unpaired — so the property is pinned rather than merely true.

### D6 — A new harness file, not an extension of an existing one

Three existing files touch this region: `step7-snapshot-collapse.test.sh` (7.0),
`spec-pointer-archive.test.sh` (7.0b), `transition-producer.test.sh` (the graph). None of them owns
the question *"is the terminal transition ordered before the commit that ships the manifest"*, which
spans three steps in two paths. It is its own population asking its own question — ADR-0086's
criterion for keeping a copy rather than extracting — and this is instance **14** of the
derived-guard pattern. The instance number is re-derived from the files: it has collided twice
before (ADR-0117 recorded the first at 10, ADR-0131 the second at 12), so do not take it from a
brief.

The consequence is a `docs-ci.yml` `shell-tests` append: that list is explicit, not a glob, and a
missing append is caught by `pairs-completeness.test.sh` `CI1`.

### D7 — The E4/H5 uncommitted-manifest gap is filed, not fixed and not left unrecorded

On Express and Hybrid the manifest is written to disk and committed by nothing, in any state. It has
damaged nothing — zero Express and zero Hybrid manifests exist — and closing it is a design question
with at least three answers (give those steps a `--include`, give them a Gate-4.0-equivalent
producer, or declare the single-session paths as deliberately not committing the manifest). Bundling
a design question into an ordering fix is how a bounded change becomes an unbounded one. It is filed
as its own issue and referenced from §D4's note in the file itself, so a reader meeting the
asymmetry finds the reason at the site rather than in an ADR they may not open.

### D8 — Nothing else moves

The legal-pair table is untouched: no `completed → step_7_commit` rollback pair is added, because
ADR-0078's invariant-4 exemption rests on the terminal states being **absorbing** in
`manifest-transition.sh`, and adding an edge out of `completed` would silently invalidate an
Accepted decision three ADRs deep. The shared manifest helpers are untouched: making them refuse a
write once terminal would reach every step and `autopilot-build`, a blast radius far wider than the
issue (ADR-0047 §A2's standing argument). The 57 existing manifests stay byte-unchanged
(ADR-0075's principle: a historical record is accurate for its moment). Gate 4.0 keeps committing an
in-flight manifest.

---

## Alternatives considered

**A1 — Add `step_7_commit` to invariant 4's exempt set.** Rejected, and #410 rejected it during
triage for the right reason: ADR-0078 rests the exemption on the exempt states being absorbing in
`manifest-transition.sh`, which `step_7_commit` is not. It widens a guard to accommodate an ordering
defect, and it would leave every future in-flight state one argument away from the same request.

**A2 — Rewrite the five lowercase-`d` `project_root` values so the corpus validates on Linux.**
Rejected. They are accurate for the machines that produced them; ADR-0075 declined exactly this, and
`manifest-project-root-terminal.test.sh` `C2` exists to fail the day someone does it — it asserts at
least one manifest still carries a dead root, so "fixing" them would leave `C1` green while testing
nothing. It also fixes only the corpus, not the chain that keeps producing the state.

**A3 — Leave the ordering and transition the manifest by hand after each commit.** This is what
happened on PR #409 and, per #357, after the #287 run before it. Rejected: it is the *absence* of a
fix presented as one. Twice-manual is the evidence the instruction is wrong, not that the workaround
works, and #357 sat on the roadmap for eight days while the manual step was reapplied.

**A4 — Order the transition but make it a bare instruction with no guard.** Rejected because #357 is
the experiment: the defect was recorded, correctly, with a remedy, and nothing prevented its
recurrence. Its own exit condition says *"with the ordering asserted"*.

**A5 — Pair the guard's anchors by proximity (within N lines).** Rejected on measurement. Gate E3's
terminal transition is 13 lines above E4's commit invocation, closer than any threshold that
tolerates a real pair with an explanatory sentence in it. It passes the pre-fix file for E4, which
means it would have shipped green against the defect.

**A6 — Pair by adjacency in the {terminal transition, commit invocation} stream.** Rejected on
measurement. Both the pre-fix and post-fix files present an alternating `T,C,T,C,T,C` stream, so an
order-only rule over two anchor kinds returns the same verdict for both. It is the tightest-looking
rule that pins nothing.

**A7 — Bound each step by the region between successive commit invocations.** Rejected on
measurement. Pre-fix every region already contains a terminal transition — Step 7's region contains
the §4 usage sample at `:458`, E4's contains Gate E3's, H5's contains E4's own post-commit one — so
all three pass. Vacuous in the worst way: it looks like a containment rule.

**A8 — Bind each transition to its step with an explicit paired marker (`<!-- step: 7 -->` on both
lines).** Rejected. It introduces a third source of truth that can disagree with the two mechanisms,
which is the ADR-0042 shape and the reason ADR-0133 §D refused a marker for the wrapper: *its
presence in the body is the evidence*. The nearest-preceding-write rule needs no key at all.

**A9 — Capture `HEAD` and the dirty set before the invocation and diff after, to classify the
outcome.** Rejected. It requires two fences straddling a `Skill` call and either a free variable
crossing a process boundary or a second substituted placeholder — and a fence that borrows a
variable bound in an earlier fence stops being independently executable, which is the property
ADR-0083 `F4`/`F7` rest on. Reading the manifest after the fact needs one placeholder and no
sequencing.

**A10 — Detect a declined commit by reading what the `commit` skill said.** Rejected. The skill
emits no machine-readable outcome token, and adding one changes a skill three unattended callers
depend on for a problem solvable by looking at git. It is also an agent self-report used as a gate,
which ADR-0047 §A3 rules out by name.

**A11 — Apply the outcome fence to E4 and H5 as well.** Rejected: it would stop every Express and
Hybrid run, because those paths never commit the manifest at all, so the fence would report
`COMMIT_UNCOMMITTED` correctly and halt on a gap that is out of scope. §D4 states the boundary at
the two sites instead.

**A12 — Fold the ordering fix into `step7-snapshot-collapse.test.sh`.** Rejected. That file's
question is ADR-0104's collapse; this one spans Step 7, E4 and H5. Sharing would give one file two
populations and two questions, and a defect in the shared derivation would disable both at once — the
correlated-failure argument ADR-0086 §D3 makes for keeping hermetic guards separate.

---

## Consequences

### Positive

- The committed manifest is terminal on both axes at every step that commits one, so ADR-0078's
  invariant-4 exemption applies to it and `C1` stops depending on which machine runs it.
- Two issues close, one of which had been an open roadmap row for eight days with a manual
  workaround reapplied at least twice.
- The Standard and Hybrid transitions stop being prose. That is independently valuable: the PATH-RULE
  class exists because a prose instruction has no path, no exit code and nothing to assert against,
  and this file has now produced the same defect three times (ADR-0028, ADR-0117, here).
- The PROJECT.md-update and push blocks stop keying on a model's judgement (*"completed successfully
  (not aborted)"*) and key on a token instead.
- `commit`'s "nothing to commit" and a declined gate become structurally distinguishable, at the one
  place in the chain where confusing them is expensive.
- §D5's write predicate makes §D1's 7.0b-then-7.0c ordering enforced rather than merely written
  down: a repoint moved below the transition produces a violation naming the line.

### Negative

- **A new failure mode on the attended Standard path.** A human who declines the commit gate now
  ends the run with a terminal manifest over an uncommitted tree, and the chain stops rather than
  continuing to the post-commit actions. That state is unreachable today and it is not reversible
  through the state machine; the report is the whole remedy.
- **The write predicate is broad**, so a prose sentence naming a `manifest-*.sh` helper inserted
  between 7.0c and the invocation reddens the guard. Correct direction, still a false positive, and
  there is deliberately no waiver for it.
- **The commit predicate is narrow**, so an invocation phrased without a leading `Invoke`/`Use` is
  invisible to the population. The count guard turns that into a loud failure rather than a silent
  one, but it does not turn it into a correct answer.
- **One more declared fence contract and one more hard `~/.claude` dependency at Step 7.** Neither
  is new in kind, and the outcome fence fails closed, but Step 7 now has one more thing that is
  worse than inert until `staging/sync-to-claude.sh --apply`.
- **`commit` Step 5.5's `.claude/context.md` changes on this path.** Its *"Open decisions"* line
  looks for a manifest with `status: in_progress`; after 7.0c there is none, so it writes `none`
  instead of naming `step_7_commit`, and *"In progress"* derives from `completed`. Correct after the
  fact and skipped in autopilot mode entirely — but it is a real behaviour change, and it is the
  answer to the open question #357 raised (*"check whether any consumer reads `current_step` during
  Step 7"*). The other consumer, `commit` Step 2 item 3, reads topic and ADR path only and is
  unaffected. Measured, not assumed.
- **`step7-snapshot-collapse.test.sh` `SC1` reads a 120-line window from the Step 7 heading** and
  the invocation currently sits at offset 90. This feature adds roughly eight lines above it. The
  margin is real but no longer comfortable, and the next addition to Step 7 will have to widen that
  window or move the block.

### Neutral

- Instance 14 of the derived-guard pattern, kept as a copy rather than extracted (ADR-0086). Its own
  population, its own question, its own count-guard thresholds.
- The declared-fence-contract count goes 32 → 33 and the wrapper population 32 → 33. Both floors
  (`F10` at 15, `WS0` at 32) still hold; neither is bumped, because both guard the *derivation*
  breaking rather than a member vanishing, which is `F4`/`WS1`'s job.
- The two new bare transition fences carry no ADR-0133 wrapper and need none: they contain no
  parameter expansion, so `fence-shell-divergence-scan.sh` does not flag them and they are outside
  the wrapper population — the same shape as E4's three existing transition fences.
- Nothing changes for `autopilot-build`, `project-conductor` or `nightly-autopilot`: none of them
  reimplements Step 7, and the chain hands back after it.
- The #357 roadmap row is left unticked. Marking it is not one of R-01..R-17 and this feature has no
  roadmap row of its own for Step 7's PROJECT.md block to find.

---

## References

- `SPEC.md` — topic slug `410-order-the-manifest-completed-transit`
- `docs/superpowers/plans/2026-08-12-410-order-the-manifest-completed-transit.md`
- Issue #410, issue #357, PROJECT.md "Three attended items the waves cannot hold (2026-08-04)" item 3
- `docs/architecture/ADR-0078-197-project-root-terminal.md` — invariant 4's terminal exemption and
  its absorbing-state premise
- `docs/architecture/ADR-0113-331-invariant-4-two-field-terminal.md` — the second terminality axis
- `docs/architecture/ADR-0071-173-step5-preflight-producer.md` — Gate 4.0, `--include`, `--no-pr`
- `docs/architecture/ADR-0104-249-step7-snapshot-collapse.md` — Step 7.0
- `docs/architecture/ADR-0106-267-spec-pointer-archive.md` — Step 7.0b
- `docs/architecture/ADR-0083-206-fence-contract-coverage.md` — fence contracts, `F3`/`F4`/`F7`, and
  the heading-anchor measurement §D3
- `docs/architecture/ADR-0133-394-fence-execution-shell.md` — the wrapper and its population
- `docs/architecture/ADR-0086-derived-guard-pattern-not-extracted.md` — the extract-or-copy criterion
- `docs/architecture/ADR-0117-286-path-rule-bare-mentions.md` — the PATH-RULE convention
- `docs/architecture/ADR-0108-284-plant-registry.md` — plants
