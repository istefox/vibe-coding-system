# ADR-0120 — the transition-pair count: one derivation, not three

- **Issue:** #289
- **Status:** Accepted
- **Date:** 2026-08-03
- **Supersedes:** nothing. **Amends:** ADR-0105 §GR3's "one detector" claim, and ADR-0028 §E's
  reconciliation, both of which were accurate for their moment and are not edited (ADR-0034
  precedent).

---

## Context

`manifest-transition.sh` builds a list of legal `<from>,<to>` transition pairs and refuses anything
absent from it. The total is written into prose in three shipping files and re-derived by the
harness. Issue #289 states the shape as *"stated in three files and derived in one"* and asks that
the count be derived wherever it is used, with a count guard, and that any surviving literal be
asserted against the derivation.

**Every number in that framing was re-measured before designing, per this repository's hardest rule.
Three of them do not reproduce.** What follows is what the files actually contain on 2026-08-03.

### M1 — the count is 45, confirmed five independent ways

| method | result |
| --- | --- |
| `grep -cE '^[[:space:]]*echo "[a-z0-9_]+,[a-z0-9_]+" >>? "\$PAIRS"'` | 45 |
| `GR3`'s awk extraction, deduped | 45 |
| the same awk, **not** deduped | 45 |
| **live execution** of the pair-building block into a real file | 45 lines, 45 distinct |
| per-block sum from the script's own section comments | 25 + 6 + 14 = 45 |

No duplicate pair exists today (`sort | uniq -d` is empty). The sub-counts are exactly the
`25 standard + 6 express + 14 hybrid` the SKILL.md header states. SKILL.md's Express bullet
enumerates 6 pairs and its Hybrid bullet 14 — both match the script. The Standard bullet does not
enumerate (it names 2 pairs illustratively).

### M2 — what the count EXCLUDES, decided and stated because the SPEC requires it

The SPEC asks whether the producer exemptions (issue #248, ADR-0095) are inside or outside the
count. **Outside**, and so is a second thing the SPEC does not mention:

- **Producer exemptions are outside.** They are `# transition-producer-exempt: <target> — <reason>`
  *comment* declarations asserting that a target has no producer; they are not pairs and emit
  nothing into `$PAIRS`. **There are currently zero of them** — `gate_5_review_decision` was the
  only candidate and ADR-0105 deleted the state instead. So the question is numerically moot today
  and must still be answered, because the day one is declared it must not silently move the total.
- **The unconditional `any → failed | aborted` wildcard is outside.** It is a separate `if` branch
  that short-circuits *before* `$PAIRS` is built. Counting it would mean counting one pair per
  reachable state, twice.

The count is therefore: **the number of DISTINCT `<from>,<to>` pairs emitted into `$PAIRS`**.

### M3 — "derived in one" is wrong. There are THREE derivations, and they disagree

| # | site | extraction | bounded to the block? | deduped? |
| --- | --- | --- | --- | --- |
| 1 | `gate5-state-removal.test.sh:89` (`GR3`) | `awk -F'"'` on any `echo "a,b"` line | **no** | **yes** |
| 2 | `concept-to-code-manifest-helpers-guards.test.sh:286` (`E7`) | awk range + `grep -Ec`, requires `>` | **yes** | **no** |
| 3 | `tracer-bullet-probe.test.sh:418` (`ACTUAL_PAIRS`) | `grep -cE`, requires `>>? "$PAIRS"` | **no** | **no** |

Run against five fixtures — the real script, plus four one-line mutations:

| fixture | GR3 | E7 | TBP | correct |
| --- | --- | --- | --- | --- |
| the script as it stands | 45 | 45 | 45 | 45 |
| a **duplicate** pair line added | 45 | **46** | **46** | 45 |
| a pair-shaped `echo` **outside** the block | **46** | 45 | 45 | 45 |
| one **genuinely new** pair | 46 | 46 | 46 | 46 |
| the block's opening marker renamed | 45 | **0** | 45 | **0** |

**Three answers to one question on three of five fixtures.** `GR3` is right about deduplication and
wrong about bounding; `E7` is right about bounding and wrong about deduplication; `ACTUAL_PAIRS` is
wrong about both. The operative semantics is `grep -Fxq "$current_step,$new_step" "$PAIRS"` — a
duplicate line adds no legal transition and a line outside the block never reaches the file — so the
correct derivation is **block-bounded AND distinct**, which is none of the three.

This is not a hypothetical. It is ADR-0086's criterion for extraction met exactly as that ADR words
it: *extract only when two copies giving different answers would be a defect.* Here three copies
give three answers, measured.

### M4 — the site inventory is four files and nine literals, not three files

**Shipping sites (3)** — the ones the SPEC names, and it is right about these:

1. `SKILL.md:404` — `Legal transition pairs (45 total — 25 standard + 6 express + 14 hybrid, …)`
2. `SKILL.md:433` — `performs legal state transitions atomically (45 pairs).`
3. `manifest-transition.sh:62` — `# Build legal transition pairs into temp file (spec §3.3, 45 transitions)`

**Harness literals (6)**, in two files, one of which the SPEC does not mention at all:

4. `gate5-state-removal.test.sh:90` — `[ "$ACTUAL" -eq 45 ]`
5. `gate5-state-removal.test.sh:96` — `GR3b`'s needle set `'45 total\|(45 pairs)\|§3.3, 45 transitions'`
6. `concept-to-code-manifest-helpers-guards.test.sh:237` — `E1`, the full header sentence
7. `…:244` — `E2`, `(45 pairs)`
8. `…:251` — `E3`, `§3.3, 45 transitions`
9. `…:287` — `E7`, `[ "$actual_pairs" -eq 45 ]`

### M5 — the SPEC's assertion IDs are misattributed

The SPEC names `GR3`, `GR4`, `GR5` as the count assertions. Measured, the count assertions are
**`GR3`, `GR3b`, `GR3c`**. `GR4` asserts Gate 5's `Trigger:` prose names `step_6_review`; `GR5`
asserts no live reference to the removed state survives. **Neither concerns the count.** Anyone
editing `GR4`/`GR5` expecting to touch this subject would change the wrong thing.

### M6 — R-02 is already two-thirds satisfied, and nobody recorded it

`tracer-bullet-probe.test.sh` already does what R-02 asks, for two of the three shipping literals:

- **`TBP2`** extracts the script comment's number and compares it against the derivation.
- **`TBP3`** extracts SKILL.md's header total and compares it against the derivation.

The uncovered one is **`SKILL.md:433`'s `(45 pairs)`** — pinned only as a frozen string by `E2` and
counted by `GR3b`'s floor, never compared to anything derived. So the design's job on R-02 is one
missing comparison and a consolidation, not three new ones.

### M7 — four live defects found while measuring, none of them reported by anything

- **D-A — SKILL.md contradicts itself.** The header says `25 standard`; the Standard bullet nine
  lines below says *"all 28 pre-existing pairs unchanged, plus 1 new pair for Step 4.5"* = **29**.
  The script measures 25. ADR-0105 moved the header from 29 to 25 and left the bullet. **`E5`
  actively pins the stale bullet as a frozen string**, so a passing test is holding the
  contradiction in place.
- **D-B — two stale assertion messages.** `E2`'s failure message reads *"does not state (49
  pairs)"* while the grep looks for 45; `E3`'s **success** message reads *"states 49 transitions"*
  while the grep looks for 45. A green run prints the wrong number. ADR-0105 updated the needles
  and left the messages — the same edit that created D-A.
- **D-C — `GR3b` is a `>= 3` floor over an OR'd needle set applied to two files.** It counts
  matching *lines*, cannot say which site moved, and passes if a fourth site appears while one of
  the three vanishes.
- **D-D — not one count assertion carries a plant.** `GR3`, `GR3b`, `GR3c`, `E1`, `E2`, `E3`, `E5`,
  `E7`, `TBP1`, `TBP2`, `TBP3`: zero declared plants. The only plant in `gate5-state-removal.test.sh`
  is on `GR4`. Under ADR-0108 these eleven assertions are unproven by construction.

### M8 — the substrate

All three harnesses are green at baseline (`gate5-state-removal` 15/0,
`concept-to-code-manifest-helpers-guards` 34/0, `tracer-bullet-probe` 38/0). `pairs-completeness`
reports `CI0: 72`, `CI0b: 72`, `CI1`/`CI2` green — the `docs-ci.yml` harness list is currently
complete, so a new harness file must be added to it and ADR-0113's guard will enforce that.

---

## Decision

### D1 — one shared checker, `staging/plugin/scripts/tests/transition-pair-count.sh`

The derivation moves into a single script that every consumer calls. It is the only place that
decides what a transition pair is, exactly as `plan-task-predicate.awk` is the only place that
decides what a plan task is (ADR-0069 §D1) and `manifest-field-state.sh` is the only place that
reads an additive manifest field (ADR-0076).

ADR-0086 refused to extract the derived-guard pattern across six harnesses, on the stated criterion
that six copies answering six *different* questions cannot drift into a defect. That criterion
points the other way here and M3 is the proof: three copies, one question, three answers, in two
opposite directions. This is the ADR-0069 case, not the ADR-0086 case.

**Derivation rule: block-bounded AND distinct.** Bounded because a pair-shaped `echo` outside the
block never reaches `$PAIRS`; distinct because `grep -Fxq` makes a duplicate line a no-op. Both
halves are load-bearing and the fixtures in D6 exercise each one alone, so neither can be dropped
as redundant.

### D2 — it is a CHECKER, and it distinguishes "did not run" from "found nothing"

```
0  clean. stdout EMPTY.
1  one or more findings, one per line on stdout.
2  bad invocation: wrong argument count, unreadable target file.
3  DID NOT RUN: the pair derivation produced zero pairs.
```

Exit 3 is the count guard R-01 asks for, and M3's fifth fixture is why it is not optional: renaming
the block's opening marker makes the bounded extraction return **0**, which is indistinguishable
from a clean parse of an empty machine. A zero-pair derivation compared against a literal that also
failed to parse is the SPEC's own stated hazard, and it is the shape this repository has now met in
`spec-coverage.sh`, `plan-tasks.sh`, `secret-scan.sh`, `manifest-field-state.sh` and
`path-rule-check.sh`.

The header must state, in its own words, that this is a checker and must never grow a `CLEAN`
sentinel — the reporter/checker confusion ADR-0048 recorded at a single call site and ADR-0117
restated. A statistics line goes to **stderr on every run regardless of exit code**, mirroring
`path-rule-check.sh`:

```
transition-pair-count: pairs=<n> standard=<n> express=<n> hybrid=<n> literals=<n> findings=<n>
```

### D3 — the targets are ARGUMENTS, and the checker lives outside every deployment path

`transition-pair-count.sh <transition-script> <skill-md>`. Taking the files as arguments follows
ADR-0117 §3.9 exactly: a later issue can point the mechanism at another skill without editing it.

Placing it in `staging/plugin/scripts/tests/` is deliberate and load-bearing. That directory sits
outside `pairs-completeness.test.sh`'s **non-recursive** `plugin/scripts/*.sh` population (verified:
`check_complete` globs `"$STAGING/$_dir"/$_pat`, one level), and the file does not end in `.test.sh`
so `.claude/test-cmd` does not execute it directly. Consequence: **no `PAIRS` entry, no sync
dependency, and therefore no "inert until sync" failure mode** — the class that has bitten six
recent ADRs. `path-rule-check.sh` established this placement three days ago and is the precedent
being followed rather than re-litigated.

### D4 — the three ad-hoc derivations are retired into calls, and the literals are asserted

- `GR3` stops re-deriving and consumes the checker.
- `E7` stops re-deriving and consumes the checker.
- `ACTUAL_PAIRS` in `tracer-bullet-probe.test.sh` stops re-deriving and consumes the checker.
  **`TBP1` keeps its `>= 40` floor and keeps asserting the PAIR, not the count** — ADR-0105 changed
  that assertion in kind for a reason that still holds, and this ADR must not quietly undo it.
- `TBP2`/`TBP3` keep their comparisons; their derivation input becomes the checker's.
- **`GR3b` is replaced, not tuned.** A `>= 3` line-floor over an OR'd needle set becomes a
  per-site check inside the checker: each of the three shipping literals is located by its own
  distinctive anchor and compared against the derived number, so a finding names *which* site is
  stale. This is where `SKILL.md:433`'s uncovered `(45 pairs)` gains its comparison (M6).
- `GR3c`'s stale-49 ban is subsumed: a literal that disagrees with the derivation is a finding
  whatever its value, so a hardcoded ban on one specific historical number stops being the
  mechanism. It is kept as a cheap forward guard and labelled as one.

**The sub-counts are literals too and are derived per block**, from the script's own
`# Express path transitions` / `# Hybrid path transitions` section comments. This is what catches
D-A mechanically rather than by a human noticing.

### D5 — D-A and D-B are fixed in this chain

The Standard bullet is corrected from *"all 28 pre-existing pairs unchanged, plus 1 new pair"* to
state 25, and `E5`'s needle and message move with it. `E2`'s and `E3`'s stale messages are
corrected. These are in scope because R-02 is about literals being true, and a test pinning a false
literal is the strongest possible form of the problem: it makes the contradiction load-bearing.

`docs/`-side historical ADRs and plans recording 48 or 49 are **not** edited (ADR-0034 precedent);
they were accurate for their moment. `CLAUDE.md:388`/`:830` likewise.

### D6 — a new hermetic harness, and the divergence matrix becomes the fixtures

`staging/plugin/scripts/tests/transition-pair-count.test.sh`, section `TC`, added to `docs-ci.yml`.
M3's five fixtures become assertions in both directions, per ADR-0039's rule: the good input and the
bad input it exists to catch. The duplicate-line and out-of-block fixtures each isolate one half of
D1's rule, so a coder cannot satisfy the suite with a one-sided extraction.

A new file rather than an extension of `gate5-state-removal.test.sh`: that harness is about the
*state removal*, and this subject now demonstrably spans four files and three derivations. ADR-0028
set the one-file-per-issue precedent for exactly this.

### D7 — every new assertion is planted, and the eleven existing ones stop being unproven

D-D means eleven count assertions currently pin nothing that anyone has verified. Every assertion
this chain writes or rewrites gets a `# plant:` declaration at column 1 beside it (ADR-0108;
column 1 because `PC4` exists — ADR-0115 lost eight declarations to indentation). A plant that does
not fire is evidence about the assertion and is fixed, not waived.

Two syntax limits from `plant-check.sh`'s header bind the plan and are called out in it: **` | `
cannot appear inside a field**, which every shell pipeline contains and which silently truncated
three plants in ADR-0114; and **a replacement cannot contain a newline**, which collapsed a plant
into nonsense in ADR-0112.

---

## Alternatives considered

### Alt A — fix the three derivations in place, leave them separate (ADR-0086's default)

Make `GR3`, `E7` and `ACTUAL_PAIRS` each block-bounded and distinct, and leave three copies.

**Rejected.** ADR-0086's criterion is explicit: extract when two copies giving different answers
would be a defect. M3 measures three copies giving three answers in two opposite directions — this
is the criterion being met, not an exception to it. Making them agree today leaves three answers
that agree today, which is the exact sentence ADR-0069 used when it refused the same option for
`plan-task-predicate.awk` and was later vindicated by issue #184. The correlated-failure argument
that protects the six derived guards does not apply: those six ask six questions about six
populations, and a defect in a shared source would disable six independent checks. Here a defect in
a shared source disables one check that is currently implemented three times, badly.

### Alt B — delete the literals from SKILL.md and the script comment entirely

No stated total anywhere; the number lives only in the code that builds the list.

**Rejected.** The SKILL.md paragraph is instruction a model reads while routing a chain, and the
total plus its `25 + 6 + 14` split is genuinely orienting there; the script comment tells a reader
of a 165-line state machine what they are looking at. R-02 exists precisely because a literal is
sometimes worth having. Deleting the statements also deletes the only thing that would ever
disagree with the derivation, which converts a detectable drift into an undetectable silence — the
failure direction this repository has recorded repeatedly (ADR-0043's direction lesson, ADR-0081's
stale-waiver-reads-as-clean).

### Alt C — have `manifest-transition.sh` emit the count at runtime

`wc -l < "$PAIRS"` in the illegal-transition error message, so the number is never written down.

**Rejected on blast radius, the ADR-0047 §A2 precedent.** This modifies a live state machine that
every chain transition passes through, to solve a documentation-drift problem. It also does not
solve it: SKILL.md's prose and the script's own header comment would still be unchecked literals,
and the harness would still need a derivation to compare them against. It buys nothing and risks a
path with 48 legal pairs and no tolerance for a new failure mode.

### Alt D — a single assertion comparing the three existing derivations to each other

Keep all three, add a fourth assertion requiring `GR3 == E7 == ACTUAL_PAIRS`.

**Rejected.** It pins the three to agree without deciding which is *correct*, and on today's tree
all three return 45, so the assertion is green while every one of them is wrong about something.
Worse, it makes the wrong answers load-bearing: correcting `E7`'s deduplication would then require
correcting the other two in the same commit or the new assertion fails. It converts three
independent defects into one coupled defect.

### Alt E — extend `gate5-state-removal.test.sh` instead of adding a harness

**Rejected**, mildly. That file's subject is issue #265's state removal and its header is a
narrative about four unreachable pairs; the count assertions live there by proximity, not by
belonging. Since the population is now four files, hosting the checker's contract tests in a file
named for a different issue makes the next reader look in the wrong place. The cost of rejecting it
is one `docs-ci.yml` entry, which ADR-0113's `CI1` enforces anyway.

---

## Consequences

### Positive

- One derivation with one answer, and it is the semantically correct one — matching `grep -Fxq`'s
  behaviour rather than approximating it three different ways.
- A zero-pair parse can no longer read as agreement: exit 3 separates "did not run" from "found
  nothing", the distinction this repository has now had to make in six scripts.
- Each of the three shipping literals is compared against the derivation individually, so a finding
  names the stale site instead of reporting a floor that moved. `SKILL.md:433` gains its first
  comparison.
- The `25 + 6 + 14` sub-counts become mechanically checked, which is what catches D-A. SKILL.md
  stops contradicting itself nine lines apart, and a test stops holding the contradiction in place.
- Eleven previously unplanted count assertions become planted or replaced by planted ones.
- No `PAIRS` entry and no sync dependency, so nothing here is inert until deploy — unlike six recent
  features that were.
- The next graph change moves one number in one place. ADR-0105 had to correct five assertions
  across three files; ADR-0057 before it had to correct the same class.

### Negative

- **The checker parses a shell script with awk, and that coupling is real.** Rewriting the pair
  block in a different idiom — a heredoc, an array, a loop — makes the derivation return 0 and the
  checker exit 3. That is the loud direction and it is deliberate, but it is a maintenance coupling
  that did not exist before, and anyone restructuring `manifest-transition.sh` must update the
  extractor in the same commit.
- **The block boundary is now load-bearing in a way it was not.** The opening marker
  (`PAIRS="$(mktemp)"`) and closing marker (`if ! grep -Fxq`) become anchors. They are distinctive
  strings rather than line numbers (ADR-0082), but they are anchors in a file nobody previously had
  to treat as anchored.
- One more file in `staging/plugin/scripts/tests/` that is not a `*.test.sh` and is invoked only by
  a harness — the second of its kind after `path-rule-check.sh`. A reader scanning the directory
  sees two files that the test-cmd glob deliberately skips.
- The sub-count derivation depends on the script's **section comments** (`# Express path
  transitions`, `# Hybrid path transitions`). A comment is a weaker anchor than code. Deleting one
  merges its pairs into the preceding block and produces a wrong sub-count with a right total — a
  finding, but one whose message will point at the wrong block.
- `GR3c`'s stale-49 ban is demoted to a forward guard that passes before and after. It is labelled
  as such in the harness so it is not mistaken for fix evidence.

### Neutral

- The total does not change. 45 before, 45 after. No pair is added or removed by this issue, per
  the SPEC's Out clause.
- Producer exemptions stay outside the count and there are still zero of them. The decision is
  recorded so the first one declared cannot silently move the total.
- The `any → failed | aborted` wildcard stays outside the count and stays undocumented in the
  totals — it is a wildcard, not a pair list, and enumerating it would mean one entry per reachable
  state.
- Historical ADRs, plans, and `CLAUDE.md` keep 48 and 49 where they record a past moment accurately
  (ADR-0034 precedent).
- `TBP1` keeps its `>= 40` floor and its pair-not-count assertion, unchanged. ADR-0105's "changed in
  kind" decision is preserved rather than reversed.

---

## References

- Issue #289; `SPEC.md` (topic slug `the-transition-pair-count-is-stated-in-t`).
- `docs/architecture/ADR-0105-265-gate5-state-removal.md` — the source; the 49 → 45 move and the
  record that `TBP1` was **changed in kind** because a total moves whenever any unrelated pair does.
- `docs/architecture/ADR-0028-32-manifest-helpers-guards.md` — §E, the 48/213/229 reconciliation and
  the one-file-per-issue harness precedent.
- `docs/architecture/ADR-0086-derived-guard-pattern-not-extracted.md` — the extraction criterion,
  applied here in the opposite direction and for the reason that ADR states.
- `docs/architecture/ADR-0069-172-plan-task-form.md` — `plan-task-predicate.awk`, the precedent for
  one loaded predicate replacing N pasted copies.
- `docs/architecture/ADR-0117-286-path-rule-bare-mentions.md` — `path-rule-check.sh`: checker
  placement outside every deployment path, exit contract, target-as-argument.
- `docs/architecture/ADR-0108-284-plant-registry.md` — the plant contract; `PC4` (column 1).
- `docs/architecture/ADR-0113-331-invariant-4-two-field-terminal.md` — `CI0`/`CI1`/`CI2`, the
  `docs-ci.yml` completeness guard a new harness must satisfy.
- `docs/architecture/ADR-0095-248-transition-producer.md` — the producer exemptions this ADR places
  outside the count.
- `staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh` — §"Build legal transition
  pairs into temp file".
- `staging/plugin/skills/concept-to-code/SKILL.md` — §"Legal transition pairs".
