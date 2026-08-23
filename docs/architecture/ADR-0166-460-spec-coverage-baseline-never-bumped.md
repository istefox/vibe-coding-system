# ADR-0166 — the chain that enrols a SPEC in the corpus bumps the baseline it enrols into

- **Topic slug:** `460-spec-coverage-baseline-never-bumped`
- **Issue:** #460 (PROJECT.md Phase 18)
- **SPEC:** `SPEC.md` (R-01 … R-08), archived at completion to `docs/specs/`
- **Plan:** `docs/superpowers/plans/2026-08-22-460-spec-coverage-baseline-never-bumped.md`
- **Extends:** ADR-0138 §D5 (the frozen per-item baseline), ADR-0106 (Step 7.0b, archive on
  completion), ADR-0086 (extract only when two copies giving different answers would be a defect).
  Supersedes nothing.

## Status

Accepted — 2026-08-22.

**Numbering, stated because it is not obvious from `main`.** ADR-0165 is already allocated: commit
`ae85b07` on branch `feat/470-chain-never-regenerates-xcode` carries
`ADR-0165-470-chain-never-regenerates-xcode.md` and a twentieth `CLAUDE.md` rule. Neither is merged
to `main`, where the highest ADR is 0164 and `CLAUDE.md` still lists nineteen rules. This ADR is
therefore **0166**, not 0165, and the SPEC's forward reference to "ADR-0165 §D8" resolves once #470
merges.

## Context

`spec-coverage.test.sh`'s `RS7` compares the live `(SPEC, requirement id)` population against
`spec-coverage-scope-baseline.tsv`, a **frozen per-item** baseline rather than a floor — deliberately,
because a floor absorbs its own plant (CLAUDE.md rule 10, ADR-0124). `RS8a` and `RS8b` run the same
comparison in both directions (rule 8).

The population is derived from `docs/specs/*.spec.md` paired with `docs/superpowers/plans/`. Step
7.0b of `concept-to-code` archives every completing chain's SPEC into `docs/specs/` (ADR-0106). So
**a chain completing is exactly the event that enrols a new member into the population `RS7`/`RS8a`
check**, and nothing in the chain writes the corresponding baseline rows. The enrolling chain's own
commit leaves the harness red for whoever runs it next: a failure they did not cause, attributable
only by reading a `WHEN TO REGENERATE` paragraph that lives inside the baseline file's own header
and is referenced from nowhere else.

That paragraph is the whole of the current mechanism. It is a producer specified in one place and
consumed in another with nothing checking they meet — CLAUDE.md rule 17, in the file whose subject
is measuring coverage.

Hit live twice: by the #447 chain on 2026-08-17, and reproduced by the #470 chain on 2026-08-22
while this SPEC was being interviewed.

### Measurements, all re-derived for this ADR rather than carried from the issue (rule 13)

**M1 — the corpus today.** Re-derived 2026-08-22 on `main` at `1fdd96f`, by executing the harness's
own `RS_PAIRS`/`RS_LIVE` derivation against the working tree: **16 `(SPEC, plan)` pairs, 130 declared
ids.** The baseline carries **130 rows** — 106 `COVERED`, 12 `UNCOVERED`, 12 `UNSCOPED`; 106 in the
three-column form, 24 in the five-column form ADR-0157 and ADR-0154 used to record historical drift.
`RS7` reports zero divergence, `RS8a` and `RS8b` report zero orphans in either direction. The whole
harness runs `PASS=170 FAIL=0` and declares 43 plants.

**So R-08's claim holds and its number does not.** There is no pre-existing population-vs-baseline
debt for this feature to close — that part is confirmed. The SPEC's parenthetical "16 live pairs, 16
baseline rows" understates the row count by an order of magnitude: 16 is the pair count, the row
count is 130. Corrected forward here rather than edited into the SPEC (rule 14, and the SPEC is
outside the architect's write scope in any case).

**M2 — every pair's exit code, because the extraction has to preserve them.** For all 16 pairs,
`spec-coverage.sh --list` exits 0. `spec-coverage.sh --tests-root <repo>` exits **1 on nine pairs and
0 on seven**; **no pair exits 2 or 3**. The harness today ignores that exit code entirely and reads
verdicts off stdout. This matters for D4: introducing a "did not run" refusal for `rc >= 2` changes
**zero** of the 130 rows as the corpus stands, so the stricter contract can ship without a single
baseline edit.

**M3 — one invocation feeds two consumers, and only one of them is obvious.** The `RS_LIVE` loop's
single `spec-coverage.sh --tests-root` call feeds `RS_LIVE` from **stdout** and, since ADR-0154 Task
4, `RS_SCOPE` from **stderr** — the `SCOPE-NO-BACKREF` token and the `N in scope` count that `RY10`'s
corpus denominator guard reads. An extraction that captured stdout and dropped stderr would collapse
`RY10` from 16 to 0 while every other assertion stayed green until the floor tripped. This is the
single sharpest hazard in the refactor and D3 exists for it.

**M4 — where a new script may live without a deployment anomaly.** `sync-to-claude.sh` maps zones
predictably: `plugin/scripts/X -> hooks/X`, `plugin/skills/X -> skills/X`. Two anomalies are declared
on a `pairs-zone-anomaly:` line and `pairs-completeness.test.sh` fails a third one that is not
declared there. The SPEC's Architecture section puts the new script at
`staging/plugin/scripts/spec-coverage-baseline-rows.sh` while its own Definition of Done requires it
deployed to `~/.claude/skills/concept-to-code/scripts/` — that combination is a third zone anomaly.
The SPEC's DoD already leaves the door open ("or wherever the deployed shape places it, per the
existing PAIRS table"). See D1.

**M5 — the SPEC's own worked example is from the other branch.** `docs/specs/` on `main` contains no
`470-*.spec.md`; the parenthetical describing a hand bump of `docs/specs/470-…` describes the state
of the `feat/470-…` branch. No effect on the design, recorded so the next reader does not go looking
for a file that is not there.

## Decision

### D1 — one script, beside `spec-coverage.sh`, not under `plugin/scripts/`

`staging/plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh`, deploying via a
single ordinary PAIRS entry to `skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh` — the
exact deployed path the SPEC's DoD names, reached with **no zone anomaly** and resolved by the same
two-tier `CLAUDE_PLUGIN_ROOT`-then-`$HOME/.claude` block `SKILL.md` already uses 27 times.

This is a deliberate deviation from the SPEC's Architecture path, taken under the DoD's own escape
clause (M4). `pairs-completeness.test.sh`'s `check_complete` does not cover
`plugin/skills/*/scripts/`, so the PAIRS entry gets its own assertion, exactly as `RG2` already does
for `spec-coverage.sh`.

### D2 — three modes, not the SPEC's two

`--pair`, `--rows`, `--bump`. The third mode is required by CLAUDE.md rule 6 and by rule 8, and its
absence is a real failure the two-mode design cannot see.

- **`--pair --spec <spec> --plans-dir <dir>`** — prints the plan path the harness's population
  derivation would pair with `<spec>`, or nothing. This is the per-spec half of `RS_PAIRS`: the
  issue-number glob `????-??-??-<N>-*.md`, falling back to `????-??-??-<slug>.md`, `head -1`.
  The corpus **sweep** (iterating `docs/specs/*.spec.md`, applying `spec_declares_ids`, excluding the
  in-flight self-pair) stays in the harness, which is what the SPEC's "a many-pairs concern the chain
  never needs" is actually about.
- **`--rows --spec <spec> --plan <plan> --tests-root <root>`** — one TSV row per declared id,
  `<spec-basename><TAB><id><TAB><verdict>`, verdicts read straight off `spec-coverage.sh`'s own
  stdout and never re-interpreted. Empty stdout, exit 0, when the SPEC declares no ids.
- **`--bump --baseline <file> --spec <spec> --plan <plan> --tests-root <root>`** — computes the same
  rows and appends the absent ones.

**Why `--pair` is not optional.** The chain knows its plan from `manifest.artifacts.plan`; the
harness derives its plan by globbing. If those two disagree, `--bump` writes rows for a pair the
harness will never resolve and `RS8b` goes red on a baseline-side orphan — the same mystery red this
feature exists to remove, arriving from the other direction. Two answers to the one question *which
plan belongs to this SPEC* is precisely ADR-0086's defect condition. So `--bump` resolves the pair
through `--pair` and refuses when the manifest's plan is not the one the harness will use.

### D3 — `--rows` passes the checker's stderr through verbatim

The extracted script performs the same two invocations the harness performs today: `--list` (stderr
discarded, as today) and `--tests-root` (stderr **forwarded unchanged to the script's own stderr**).
On its success path the script writes nothing of its own to stderr, so `RY10`'s
`grep 'SCOPE-NO-BACKREF'` and `grep -oE '[0-9]+ in scope'` keep reading exactly the bytes they read
today, from exactly one invocation per pair. The harness's `RS_SCOPE` derivation is not edited at all.

Its own diagnostics go to stderr only on a failure path, and are prefixed so they cannot be mistaken
for the checker's tokens.

### D4 — the exit-code contract mirrors `spec-coverage.sh`'s, and the consumer is named

```
0   success        BUMPED <n> row(s) for <spec>   |  BUMP-NOOP: <reason>  |  rows on stdout
1   conflict       a computed row disagrees with a frozen row; NOTHING written
2   invalid        bad invocation, unreadable --spec/--plan/--baseline
3   did not run    spec-coverage.sh unresolvable, or it exited 2 or 3
```

Exit 3 is this repo's DID-NOT-RUN convention (rule 4): a bump that could not compute must not read as
a bump that found nothing to do. **Rule 20 requires naming the consumer before choosing the value**,
so: the consumers are the new harness (which branches on all four) and `concept-to-code`'s Step 7.0b
prose (which branches on zero / non-zero). Neither is `stop-gate.sh`, whose fixed exit-code map is
what makes 3 dangerous for a generated `test-cmd` line; nothing here reaches it.

M2 is what makes the `rc >= 2 → exit 3` rule free: no pair in the corpus exits 2 or 3 today, so no
row moves.

### D5 — `--bump` always passes `--tests-root`, unconditionally

Gate 4.x omits `--tests-root` when `manifest.test_cmd_placeholder` or `test_cmd_provisional` is
true. **The bump does not copy that.** The baseline's rows are defined by what the harness computes,
and the harness always passes `--tests-root "$REPO"`. A bump that omitted it would write scope-free
verdicts into a file compared against scoped ones — 100% row divergence on the next run. The two
call sites ask different questions (*should this feature be blocked* vs *what will the harness
compute*), which is why they legitimately diverge; stating it here is the rule 6 obligation to say
which kind of copy this is.

### D6 — an absent baseline file is a genuine no-op, and the typo it hides is guarded separately

`concept-to-code` runs on arbitrary projects. `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv`
exists only in this repository. `--bump` against a `--baseline` path that does not exist prints
`BUMP-NOOP: no baseline at <path>`, exits 0, and **does not create the file** — otherwise every
foreign-project chain would halt at Step 7.0b, and the loud-failure policy R-05 asks for would fire
on every run that has nothing to do.

The obvious cost is that a **typo** in the path `SKILL.md` passes reads as that same clean no-op.
That is rule 17 exactly, so it gets its own assertion rather than a comment: the harness asserts the
path `SKILL.md` passes is the repo-relative path of the real baseline file and that the file exists,
and a plant changes the path in `SKILL.md` to prove the assertion bites.

### D7 — append-only, refuse on conflict, never rewrite

Per computed row: absent → append; present with an identical verdict → skip; present with a
**different** verdict → fail, exit 1, name the SPEC, the id and both verdicts, and write **nothing at
all** (not even the rows that would have succeeded). Writes go to a temp file that is `mv`-ed over the
baseline, so a killed run cannot leave a half-written corpus file. A baseline whose last byte is not a
newline gets one before the first append; today's file ends with a newline, and relying on that is
the kind of premise that stops being true silently.

Refusing a conflict rather than correcting it is CLAUDE.md rule 14. The only realistic triggers are a
hand-edited baseline and a chain resumed after the code underneath moved, and both want a human
reading the file.

### D8 — the bump sits inside Step 7.0b, and its output rides the same commit

Order inside Step 7.0b: `spec-archive.sh` → `manifest-set-artifact.sh spec <archived path>` → **the
bump** → Step 7.0c's transition to `completed` → the `commit` invocation. The bump reads the
**archived** SPEC path, because the harness's population is keyed on `basename docs/specs/*.spec.md`.

The baseline file is tracked, and Step 7.0's collapse has already run `git add -u` (ADR-0158), so a
post-collapse modification is tracked-modified-after-staging — the exact case `--include` exists for
(ADR-0071 §D2). Step 7.0b's `commit` invocation therefore extends its `--include` list with the
baseline path **when and only when the bump reported `BUMPED`**. `BUMP-NOOP` adds nothing.

A non-zero exit halts before `commit` is invoked, printing the script's stderr verbatim.

### D9 — what is enforced and what is an instruction (rule 16)

**Enforced, by execution:** every behaviour of the script (all three modes, both no-op paths, the
conflict refusal, the four exit codes, the stderr passthrough), and the Step 7.0b fence's own exit
code — the new harness extracts that fence by its `<!-- fence-contract: c2c-step7-baseline-bump -->`
marker and runs it against fixture trees, which is also `F4`'s second accepted coverage form.

**Instructions, pinned only by declaration assertions:** that the orchestrator halts before invoking
`commit` on a non-zero exit, and that it extends `--include` with the baseline path. Both are prose a
model is asked to follow. The declaration assertions prove the sentence exists; they prove nothing
about obedience, and saying so is the point of rule 16.

### D10 — the new assertions live in a new harness, not in `spec-coverage.test.sh`

`spec-coverage.test.sh` is 1952 lines, runs the full 16-pair corpus twice per invocation, and already
carries 43 plants. Every plant costs one full run of the file it is declared in, and ADR-0143 §D7
measured that the registry's total is dominated by target-file runtime rather than plant count.
Adding ~18 plants there would be the single most expensive place in the repository to put them.

So: `staging/plugin/scripts/tests/spec-coverage-baseline-bump.test.sh`, hermetic `mktemp` fixtures,
no corpus sweep, `NB` prefix (verified unused across all 96 harnesses). `spec-coverage.test.sh` gains
only the `RS7`–`RS10` rewrite and one `RS0` anchor assertion for the extracted script — an existence
check, unplantable by class, the `PT1`/`PT2`/`AIJ2` precedent.

This is ADR-0086 applied in the direction it usually is not: the six derived-guard harnesses are
deliberately copies because they answer six questions, and these two files likewise answer two
(*does the corpus match the baseline* / *does the bump behave*).

### D11 — the baseline file's header instruction is rewritten forward

The header currently states *"The exact derivation lives in `spec-coverage.test.sh`, section RS7-RS8
(RS_PAIRS / RS_LIVE) — that shell IS the regeneration procedure"*. After D1 that is false, and it is
an **instruction**, not a record, so it is corrected in place. The dated `MEASURED 2026-08-14`,
`2026-08-18` and ADR-0157 blocks below it are records and are **not** touched (rule 14); a new dated
`2026-08-22` block states what moved, that zero rows changed, and that the chain now bumps its own.

## Alternatives considered

**A1 — do nothing at the chain; let the next author re-run the derivation from the header.** This is
today's design. Rejected because it has now failed twice in five days on real chains (#447, #470),
and because the failure lands on the wrong person: the author who inherits the red neither caused it
nor has any pointer to the paragraph that explains it. The measured cost of the status quo is not
"someone re-reads a header", it is an unattributable red that stops an unrelated run.

**A2 — bump the WHOLE corpus at Step 7.0b (regenerate every row).** Rejected on three counts. It
rewrites frozen rows belonging to other features, which is rule 14 and ADR-0138 §D5's whole premise;
it converts a genuine drift signal (a later feature renaming a test file and flipping an existing
pair's verdict) into a silent re-freeze, which is the one outcome the baseline exists to prevent; and
it costs 32 `spec-coverage.sh` invocations inside the chain's commit path for a benefit that belongs
to an operator running the script by hand.

**A3 — leave the derivation inline in the harness and give the chain its own copy of it.** Rejected
by ADR-0086 / CLAUDE.md rule 6 in its strictest form: two copies answering the **one** question *what
verdict does this (spec, id) have* is the defect condition, not a tolerated duplication. The two
copies would drift on the next change to `spec-coverage.sh`'s output, and the symptom would be 130
red rows attributed to the coverage checker rather than to the copy.

**A4 — make `RS7`/`RS8a` tolerate an un-baselined SPEC (skip pairs with no baseline rows).** Rejected.
It disables the guard for exactly the rows nobody has ever looked at, which is rule 9's stale-waiver
shape (an exemption that covers everything reads as clean) and rule 10's floor problem restated. It
also makes `RS8b` — the reverse direction — the only remaining evidence, and `RS8b` is blind by
construction to what the baseline omits, which is rule 8.

**A5 — put the script at `staging/plugin/scripts/` as the SPEC's Architecture section writes it.**
Rejected on M4: it deploys to a different zone than its staging location, so it needs a third
`pairs-zone-anomaly:` declaration, which must then be adjudicated by every future path check forever
— and the sibling location under `plugin/skills/concept-to-code/scripts/` produces the identical
deployed path with no anomaly at all. The SPEC's DoD explicitly permits this.

**A6 — two modes only; trust `manifest.artifacts.plan` and skip the pairing check.** Rejected on the
D2 argument: a plan filename the harness's glob does not resolve produces a baseline-side orphan and
`RS8b` red, which is the same class of unattributable failure the feature is removing. The cost of
`--pair` is roughly fifteen lines of globbing that already exist in the harness and are being moved
rather than written.

**A7 — have the script stage the baseline itself (`git add`), so `--include` cannot be forgotten.**
Rejected. A chain helper that mutates the index collides directly with Step 7.0's collapse
discipline (ADR-0158's `git add -u` after a soft reset, with an allowlist that aborts on any subject
it cannot attribute), and it puts a git write behind a step whose whole contract is that the human
sees the diff at `commit`'s Step 4 gate. The residual risk — an orchestrator that forgets the
`--include` — is bounded: the file stays modified in the working tree, `commit`'s own gate shows it,
and the very next run of the harness reports it.

**A8 — put a HITL gate on the bump.** Rejected. The operation is append-only, never rewrites a row,
and its entire output is already shown in the diff at `commit`'s Step 4 gate two steps later. A gate
that fires on every chain completion for a mechanical append is ADR-0047 §D7's *a report nobody must
act on is a report nobody reads*, and it would make unattended completion impossible for a change
that cannot destroy anything.

**A9 — a `--check` mode wired into CI that reports the drift instead of a chain-side bump.**
Rejected as insufficient rather than wrong: `RS8a`/`RS8b` already report exactly that drift, in CI,
today. Reporting is not the gap. The gap is that the report lands after the enrolling chain has
finished and on someone else's branch, which only a producer inside the enrolling chain closes.
Nothing here prevents adding such a mode later.

## Consequences

### Positive

- A chain that enrols a corpus member ships its own baseline rows in the same commit. The
  `RS7`/`RS8a`/`RS8b` red that #447 and #470 both hit stops being reachable by ordinary chain
  completion.
- The per-pair verdict derivation and the per-spec plan pairing each have exactly one implementation,
  read by both the harness and the chain. A change to `spec-coverage.sh`'s stdout shape now breaks
  one caller, visibly, instead of silently desynchronising two.
- The failure is loud and early: an unbumpable baseline stops the chain **before** the commit gate,
  in front of the person running it, instead of surfacing as CI red on an unrelated branch.
- `--rows` and `--pair` give an operator a supported way to regenerate rows by hand for pairs the
  chain never touches — the operation the baseline's header currently describes as "re-run the shell
  inside the harness".
- The plants for the new mechanism sit in a fast hermetic harness rather than in the slowest file in
  the suite, so the registry's total cost barely moves.

### Negative

- `concept-to-code`'s Step 7.0b gains a fence and three exit-code branches. That step now carries
  four sequential obligations before the commit, each able to halt the chain — more surface on the
  path with the least slack.
- Two of this feature's requirements (halt-before-commit, the `--include` extension) are instructions
  a model must follow, not enforcements. The declaration assertions pin the sentence, nothing pins
  the behaviour, and a run that ignores both leaves an uncommitted baseline exactly as today.
- The absent-baseline no-op (D6) means a mistyped path is silent by construction on foreign projects.
  The guard is a single assertion about this repository's own `SKILL.md`; it cannot see a typo
  introduced downstream.
- Row derivation now costs an extra process per pair (the wrapper), on top of the two
  `spec-coverage.sh` invocations it already made. Measured impact is expected to be small against the
  16-pair sweep, but the harness is already among the slower ones.
- The script duplicates none of `spec-coverage.sh`'s logic but does depend on its **stdout shape**
  (`^COVERED<TAB><id>$`, `^UNSCOPED<TAB><id><TAB>`). That coupling existed before, inside the
  harness; it is now in a file that ships to `~/.claude`, where it is easier to forget.

### Neutral

- Zero baseline rows change. The 130 existing rows, their 106/12/12 verdict split and the 24
  five-column drift rows are untouched; only the header's instruction paragraph is rewritten and a
  dated block appended.
- No new external dependency, no new hook, no `settings.json` change, no new HITL gate.
- The `312-spec-coverage-measures-citation-not-impl` pair stays self-excluded by the harness's
  existing `RS_SELF_PLAN` guard. That guard is a harness concern and is not moved into the script.
- `spec-coverage.sh` itself is not modified: not its logic, not its exit codes, not its
  `COVERED`/`UNCOVERED`/`UNSCOPED` tokens. Its unrelated continuation-line blindness to
  `(no-test: …)` markers stays out of scope, tracked with #470's ADR.

## References

- Issue #460; `PROJECT.md` Phase 18 ("one answer to which SPEC is this feature's").
- ADR-0138 §D5 — the frozen per-item baseline and why it is not a floor.
- ADR-0154, ADR-0157 — the two regenerations of that baseline, and `RY10`'s stderr-derived
  denominator guard (M3).
- ADR-0106 — Step 7.0b, archive on completion, the enrolment event.
- ADR-0086 — extract only when two copies giving different answers would be a defect (D2, D5, D10).
- ADR-0143 §D7, ADR-0151 — plant cost is dominated by target-file runtime (D10).
- ADR-0158, ADR-0071 §D2 — the Step 7.0 collapse and why `--include` exists (D8).
- ADR-0135 — Step 7.0c ordering; every manifest write precedes the commit.
- ADR-0047 §D7 — a report nobody must act on is a report nobody reads (A8).
- `CLAUDE.md` rules 2, 4, 6, 8, 9, 10, 13, 14, 16, 17, 20.
