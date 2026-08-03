# ADR-0119 — The Express and Hybrid paths dispatch nobody, and the Italian guide said they do

**Issue:** #288
**Date:** 2026-08-02
**Status:** Accepted and fully implemented (2026-08-03, by hand — the chain was interrupted at
Step 2 and did not deliver it). §D1/§D2/§D7 are the guide's three corrected lines; §D6 is the
Express note; §D3–§D5 and §D8 are section L of
`staging/plugin/scripts/tests/worktree-isolation-contract.test.sh`. **Read the Correction below
before building on §D3 or §D8** — three of their measured claims did not reproduce.
**Supersedes:** nothing. **Amends:** nothing. Closes a disclosure ADR-0068 recorded and deliberately
did not act on.
**Related:** ADR-0017 (the three-path routing that created Express and Hybrid), ADR-0068 §D7 (both
*dispatch* paths pin isolation explicitly), ADR-0082 (a cross-reference names an anchor, never a
line number), ADR-0083 (assertion-count floors), ADR-0086 (the derived-guard pattern is copied, not
extracted), ADR-0093 (negation detection in prose was measured and rejected), ADR-0108 (the plant
registry).

---

## Context

`staging/plugin/skills/concept-to-code/SKILL.md` opens its Express section with:

> **No worktree isolation** — failures during E2 leave partial edits in the working tree. The user
> must `git status` and reset manually if needed. Known limitation (ADR-0017).

`docs/GUIDA-USO-IT.md`'s Express state-machine diagram says the opposite:

> `-> step_e2_execute   (dispatch coder, worktree isolation)`

ADR-0068 §Consequences disclosed the pair as contradictory in July, anchored both halves by line
number, and left them for a future issue. This is that issue.

### What was measured, on `main` at `14f8972`, 2026-08-02

Every claim below was re-derived rather than inherited, including the ones handed to this design in
the brief. Two of them changed under measurement.

| # | claim | verdict |
|---|---|---|
| 1 | `SKILL.md`'s Express note reads as quoted above | **true**, found by text anchor. Its line number has now been three different values (ADR-0068 recorded `:1849`, the SPEC measured `~2456`, it is `2637` today) — ADR-0082's rule, demonstrated on its own subject |
| 2 | Step E2 executes directly: *"Execute the approved plan directly with Edit/Write/Bash tool calls. No sub-agents."* | **true** |
| 3 | Step H3 carries that sentence **byte-identically** | **true** — both lines hash to `52fc1b2ac99ae64ec2bbb254b5a3f35e2a141103` |
| 4 | The E2 and H3 blocks pass no `isolation` value | **true** — zero `isolation:` occurrences in either block; Step 5's block carries **10** and Step 6's **1** |
| 5 | ADR-0017 decided this deliberately | **true**, and more explicitly than the SKILL note suggests: its three-path table records Express sub-agents as *"None (orchestrator executes directly)"* and Hybrid as *"None (plan mode + direct execution)"*; its E2 and H3 bullets both end *"No sub-agents."* |
| 6 | The guide's `step_e2_execute` line is false | **true, on two counts** — no dispatch, no isolation |
| 7 | The guide's `step_h3_execute` line is false in exactly the same way | **true** |
| 8 | The guide's `step_5_implementation` line is correct | **true** — Step 5 dispatches the coder and pins `isolation: "worktree"` |
| 9 | Those two are the only false sites | **FALSE.** There is a **third**: `# E2: dispatch coder`, in the Express usage example under *"Nuova feature piccola (Express)"* |

Claim 9 is the reason this ADR records its own measurement rather than citing the brief's. A
full-corpus sweep for `dispatch coder` and `worktree isolation` across `docs/` and `staging/`
(excluding ADRs, plans, specs and manifests, which are historical records) returns exactly three
false statements, all in `docs/GUIDA-USO-IT.md`, and every other hit is a Standard-path or
`autopilot-build` statement that is correct. The guide's own `:251`, `:275`, `:622` and the Standard
diagram line are among the correct ones and are not touched.

### Why it survived

`staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` **already reads the guide** — its
J2 assertion checks a different claim in the same file. Its Task-8 EXPECTED header goes further and
names these lines explicitly:

> `lines 117, 136, 167 and 275 mention worktree isolation without this claim already`

The harness looked directly at the two false lines, judged them against the claim it was hunting
(the `isolation: none` fallback), found them clean of *that*, and recorded them as fine. No
assertion has ever read the diagram's per-step parentheticals as claims about behaviour.

---

## Decision

### D1 — `SKILL.md` is authoritative; the guide is corrected

`SKILL.md` is what the orchestrator executes; `docs/GUIDA-USO-IT.md` describes it to a human. When
they disagree the guide is wrong by default, and here it is wrong in fact: three independent
sources agree that Express and Hybrid dispatch nobody (ADR-0017's design table, ADR-0017's E2/H3
bullets, and the absence of any `isolation:` value in either block today).

Three lines change, all in the guide:

| site (anchored on text) | becomes |
|---|---|
| `-> step_e2_execute   (dispatch coder, worktree isolation)` | `-> step_e2_execute   (esecuzione diretta, nessun sub-agent: edit nel working tree)` |
| `-> step_h3_execute         (dispatch coder, worktree isolation, max 20 file)` | `-> step_h3_execute         (esecuzione diretta, nessun sub-agent: edit nel working tree, max 20 file)` |
| `# E2: dispatch coder` | `# E2: esecuzione diretta del piano (nessun sub-agent)` |

### D2 — the widening to Hybrid and to the third surface, recorded as a scope decision

The SPEC scopes out *"the Standard and Hybrid paths' isolation contracts, which ADR-0068 settled"*.
That excludes their **contracts**, not the guide's **descriptions** of them, and Gate 1 approved the
widening to the Hybrid diagram line explicitly. The argument, recorded rather than assumed:

- The H3 execute sentence is **byte-identical** to E2's, so the guide is false about Hybrid for the
  same reason and by the same words.
- Correcting one line of a diagram and leaving its identical neighbour false is not a defensible
  stopping point, and a cross-file assertion that covers one of two wrong lines is worth less than
  it looks: it would report GREEN over a file still carrying the defect it was built for.

The third site (claim 9) is inside the original Express scope and needs no widening argument at
all — it is the same false claim about the same step. It matters more than its size suggests: the
diagram is reference material, while the usage example is what a user reads while learning to run
Express for the first time.

**Not widened.** `SKILL.md`'s Hybrid opening block gains no isolation note (see §D6). Nothing
outside `docs/GUIDA-USO-IT.md` changes in `docs/`. The guide's stale `[Gate 5.5: humanize-en …]`
line — ADR-0040 removed that gate and replaced it with an action-free Gate 5.6 — is **disclosed and
not fixed**: it is a different defect that happens to live nearby, and bundling it would put an
unmeasured claim into a change whose whole point is that claims get measured.

### D3 — the cross-file assertion reads a MECHANISM on the `SKILL.md` side and a CLAIM on the guide side

The guide's parenthetical is a claim about behaviour. The thing that decides that behaviour is
whether the step's `SKILL.md` block dispatches an agent with an `isolation` value pinned on it.
That is a mechanism, and it is present ten times in Step 5's block and zero times in E2's and H3's.
So each `SKILL.md` step block is classified:

- **DISPATCH** — the block contains `isolation:` followed by `worktree`.
- **DIRECT** — no such pin, and the block contains the flattened phrase `no sub-agents`.
- **AMBIGUOUS** — both. A loud failure; it has never occurred.
- **NEITHER** — neither. Out of population: the block makes no isolation claim to check.

Measured today: DIRECT = {E2, H3}; DISPATCH = {5, 6}; NEITHER = the other eleven.

**Prose-to-prose was rejected**, and this is the substantive alternative. Comparing the guide's
claim against `SKILL.md`'s *"No worktree isolation"* note would verify that two sentences agree, not
that either is true — and the note is precisely the artifact under repair, so an assertion keyed on
it goes green the moment either side is reworded. It also cannot cover Hybrid at all: the Hybrid
section has no such note and this ADR does not add one (§D6). Reading the mechanism instead makes
the check independent of how anyone phrases it, and makes Hybrid covered without writing a sentence
for the check to read.

**Mechanism-to-mechanism was rejected** as unavailable rather than inferior: a state-machine diagram
is prose by construction. There is no second mechanism to compare against.

### D4 — three verdicts, three messages, each naming a side

A cross-file check cannot know which file an editor touched. It can know which side disagrees with
the mechanism, and say so:

| condition | message names |
|---|---|
| a guide line claims a dispatch or worktree isolation for a **DIRECT** step | **the guide**. It quotes the guide line and reports that `SKILL.md`'s block pins no isolation value and says *"No sub-agents"* — so the claim contradicts the mechanism, and `SKILL.md` is authoritative because it is what the orchestrator executes. If the step genuinely gained a dispatch, this ADR's premise has changed and the ADR is what must move. |
| a guide line claims worktree isolation for a step whose block is **NEITHER** | **`SKILL.md`**. The block lost its `isolation` pin, or a heading rewrite moved its boundary. The guide may be describing yesterday's behaviour correctly. |
| **no** guide line claims worktree isolation for a **DISPATCH** step | **the positive twin failed** — either the Standard diagram line lost its claim or Step 5 lost its pin. Without this, the first check passes trivially on a guide with no parentheticals at all. |

### D5 — the claim predicate forbids the phrase outright, negations included

A claim is the flattened, case-insensitive presence of `dispatch coder` or `worktree isolation` on a
line referencing a step token. It does **not** attempt to distinguish an assertion from a denial:
`nessuna worktree isolation` would fire it.

This is deliberate and has precedent in the same file — J1's predicate rejects any occurrence of
`falls back` / `fallback` regardless of polarity. Negation detection in prose was measured and
rejected once already (ADR-0093, on `detect-macos.sh`), and this repository does not do it. The
consequence is a real editing constraint, so it is written where an editor stands: **at the guide's
three corrected sites and in the check's own failure message — state the absence positively
(direct execution, edits landing in the working tree), never by negating the claim phrase.**

### D6 — R-03: the reason is stated where an Express reader is standing, and only there

The `SKILL.md` Express note becomes a statement of a deliberate property with its cause and its
price, replacing *"Known limitation"*:

> **No worktree isolation, by design** — Step E2 dispatches no sub-agent: the orchestrator executes
> the approved plan directly in this session, so there is no worktree to isolate. ADR-0068 §D7
> requires every *dispatch* to pin `isolation: "worktree"` explicitly; a path with no dispatch is
> outside it. The consequence is real and is the price of the single-session design (ADR-0017): a
> failure during E2 leaves partial edits in the working tree, so recovery is `git status` and a
> manual reset, not discarding a worktree.

**Hybrid gets no equivalent note**, deliberately. The SPEC scopes out Hybrid's isolation contract
statement; the widening Gate 1 approved was to the guide's descriptions. More usefully: the
protection does not depend on such a note existing, because §D3 reads H3 as a mechanism rather than
as prose. Adding one would create a fourth sentence to keep true in exchange for nothing the
assertion needs. Recorded as a decision so the next reader does not read the asymmetry as an
oversight.

### D7 — the guide says something useful where the false claim was, rather than nothing

Deleting the parenthetical would satisfy the correctness requirement and lose the reader. What a
reader of a state diagram most needs about these two steps is exactly what the false claim was
hiding: **the orchestrator writes into the working tree directly**, so a failure mid-step is
recovered with `git status` and a reset, not by discarding a worktree. That fact is now in the
parenthetical, and an assertion pins that it survives — otherwise a later editor "simplifies" the
line back to silence and every other check still passes.

### D8 — home, and the assertion-count floor

The assertions extend `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` as a new
section K, per the SPEC's Architecture. It already reads both files, it already derives over the
staged corpus, and it is already in `docs-ci.yml`'s named harness list, so ADR-0113's CI-dark gap
cannot reopen here. A new sibling file would split one subject across two harnesses for no gain.

That file carries **no assertion-count floor**: ADR-0083 §D3 gave floors to three harnesses and this
was not one of them, so the vanishing-assertion class it exists to catch is open here. A `Z1` floor
is added in the same change at the file's new total, **96** (87 today, plus eight section-K
assertions, plus `Z1` itself).

This is instance 12 of the derived-guard pattern and is **not** extracted into a shared helper —
ADR-0086's criterion: two copies giving different answers would have to be a defect, and here the
populations, questions and thresholds are all its own.

---

## Alternatives considered

**A1 — Correct the guide and add no assertion.** Rejected. The two statements have contradicted each
other since ADR-0017 created the Express path, survived ADR-0068 noticing them, and survived a
harness that reads the very lines and recorded them as fine. A correction with nothing behind it is
a correction that lasts until the next person edits a diagram.

**A2 — Assert prose against prose: compare the guide's claim to `SKILL.md`'s "No worktree isolation"
note.** Rejected on two independent grounds. It verifies agreement between two sentences rather than
the truth of either, and the note is the artifact under repair, so any rewording of either side
silently satisfies it. It also cannot reach Hybrid, which has no such note and gets none (§D6) —
leaving the check covering one of the two identical defects, which is the failure mode §D2 rejects.

**A3 — Change the code instead: give Express a coder dispatch with `isolation: worktree`, making the
guide true.** Rejected, and it is worth stating why rather than dismissing it. ADR-0017 chose direct
execution for Express and Hybrid as the whole point of those paths — *"the chain's overhead … 13
gates, a fresh-session boundary, and parallel sub-agent dispatch — degrades output quality"* for
work of this size. The SPEC scopes this out except if the measurement showed the behaviour
contradicting ADR-0068 §D7; it does not. §D7 governs *dispatch* paths, and a path with no dispatch
is outside its subject, not in violation of it.

**A4 — A whole-file predicate on the guide: no line anywhere may pair `dispatch coder` with an
Express/Hybrid word.** Rejected. It needs no derivation and would have caught all three sites today,
but it is keyed on the guide alone: it can never notice that `SKILL.md` moved, which is half of
R-02's requirement to name which side changed. It also has no positive twin available — nothing in
it would fail if the Standard path lost its isolation pin.

**A5 — Match the step token by heading text alone (`Step E2` → the guide's `E2`), skipping the
`step_<tok>_` state-name form.** Rejected after measurement: the bare token is unusable for numeric
steps (`5` matches everywhere), while the state-name form is unusable for the usage example, which
writes `# E2:`. Both forms are needed and the bare form is restricted to tokens matching
`[EH][0-9]+`, which is exactly the set where it is unambiguous — measured at 3 lines in the whole
guide, of which 2 are true positives and 1 is inert prose.

**A6 — Extract the derivation into a shared helper alongside the other eleven derived guards.**
Rejected under ADR-0086's criterion, applied rather than cited: the six-and-counting derived guards
ask different questions about different populations with different thresholds, and two copies
answering differently here would not be a defect. Correlated failure across guards is a worse
outcome than duplication.

**A7 — Give the guide a declared waiver marker so a legitimate negation can be exempted from §D5's
predicate.** Rejected as disproportionate. The population is three lines; a waiver mechanism is a
new syntax, a new parser and a new stale-waiver check for a hazard that a one-sentence editing rule
at the three sites removes. If a fourth site ever needs to deny the claim in prose, that is the
moment to reconsider — not before.

---

## Consequences

### Positive

- The chain's own documentation stops telling a user that Express and Hybrid dispatch a coder into
  an isolated worktree, which is the single most consequential thing it could be wrong about for
  those paths: it changes what recovery after a failed step looks like.
- Three false statements are corrected, not two. The third lives in the surface a first-time Express
  user actually reads.
- The two files can no longer drift apart silently: a claim added to the guide for a direct-execution
  step fails, and a dispatch step losing its `isolation` pin fails from the other direction.
- The guide now carries the recovery-relevant fact where the false claim was, and an assertion keeps
  it there.
- `worktree-isolation-contract.test.sh` gains its first assertion-count floor, closing the
  vanishing-assertion class on the harness that had the most assertions to lose.
- ADR-0068's disclosure is closed with a measurement rather than by inference, and ADR-0017's
  decision is cited for what it actually says instead of being paraphrased.

### Negative

- **The claim predicate is a fixed two-phrase list** (`dispatch coder`, `worktree isolation`),
  measured against today's corpus. A future editor writing *"il coder viene dispatchato in una
  worktree"* states the same falsehood in words the check does not know. The honest reading of a
  green run is *"no recognised claim phrase sits on a line naming a direct-execution step"*.
- **A negation fires the check** (§D5). `nessuna worktree isolation` is indistinguishable from the
  claim. The editing rule is written at the three sites and in the failure message; nothing enforces
  that anyone reads it.
- **Bare-token matching covers only `[EH][0-9]+`.** If a numeric Standard step ever became
  direct-execution, prose about it would be outside the check; only its `step_N_*` state name would
  be read.
- **The block boundary set is `^###` or `^#{2,4} (Step|Gate)`, each with a trailing space**, chosen because it is measured
  fence-safe on this file today (22 and 9 matches, none inside a fenced code block) after a
  fence-tracking parser proved *unreliable* on it — the file's fence parity is broken somewhere, so
  a naive toggle reports prose lines as fenced and fenced bash comments as headings. A fenced `###`
  heading line added tomorrow would truncate a block and misclassify its step.
- **The `H5` block runs past the Hybrid section to the next level-3 heading.** Harmless — it
  classifies NEITHER either way and the guide makes no claim about it — but it is a boundary that is
  wrong and currently invisible.
- **Nothing verifies that the corrected guide text is *good*,** only that the marker phrase survives
  and no claim phrase appears. A parenthetical rewritten into something true and useless passes.
- The harness's Task-8 EXPECTED header still records the two false lines as *"without this claim
  already"*. Left byte-unchanged (ADR-0034 precedent — an EXPECTED block is a record of its moment);
  the new section's header names it so a reader does not take it as a current verdict.
- The guide's stale `Gate 5.5` diagram line is disclosed and not fixed.

### Neutral

- No executable behaviour changes. `SKILL.md`'s Express and Hybrid steps are untouched apart from
  the opening note's wording; no script, hook or dispatch is modified.
- No `PAIRS` entry, no `docs-ci.yml` edit, no `.claude/test-cmd` change. The harness is already in
  CI's named list and the guide is documentation.
- Nine plants are added to the registry, taking it from 114 to 123. Three of the nine mutate the
  test file's own derivation and will therefore fire alongside the assertions that depend on it —
  correct, since a denominator guard's whole job is to fire when the derivation collapses.
- The three denominator guards are not decoration: the first two derivations written during design
  were **both wrong**, in opposite directions — one swallowed the path-opening headings and
  classified Step 7 and E4 as direct-execution, the next truncated Step 5's block to two lines and
  classified it as NEITHER. The `|DISPATCH| >= 2` guard fires on the second and the `|DIRECT| >= 2`
  bound is what makes the first visible. They were validated against real broken derivations, not
  hypothetical ones.

---

## References

- `SPEC.md` (repo root) and `docs/specs/288-the-express-path-says-no-worktree-isolat.spec.md` —
  R-01, R-02, R-03.
- `docs/architecture/ADR-0017-chain-type-routing-gate0.md` — the three-path table (Express and
  Hybrid sub-agents: *"None"*), the E2/H3 bullets, and *"Express: no worktree isolation … Documented
  limitation; not a blocker."*
- `docs/architecture/ADR-0068-176-worktree-isolation-contract.md` — §D7 (both dispatch paths pin
  isolation explicitly), §D1 (`worktree.baseRef: "head"`), and the Consequences bullet disclosing
  this contradiction.
- `docs/architecture/ADR-0082-207-210-cross-reference-form.md` — anchor on distinctive text, never a
  line number.
- `docs/architecture/ADR-0083-206-fence-contract-coverage.md` §D3 — assertion-count floors.
- `docs/architecture/ADR-0086-derived-guard-pattern-not-extracted.md` — the extraction criterion.
- `docs/architecture/ADR-0093-232-macos-detection-false-positives.md` — negation and proximity in
  prose, measured and rejected.
- `docs/architecture/ADR-0108-284-plant-registry.md` — the plant declaration grammar; ADR-0116
  added the `../docs/` target prefix.
- `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` — J1/J2's
  forbid-the-phrase-outright predicate idiom, and the Task-8 EXPECTED header that inspected the
  false lines and recorded them as fine.
- Implementation plan: **none was ever written** — see the Correction below, finding 4.

---

## Correction (2026-08-03) — four claims of this ADR that did not reproduce

The body above is left byte-unchanged (ADR-0034's precedent: an ADR records its moment). This
section records what re-measuring found when §D3–§D6 and §D8 were finally built, three days later
and by a different route. Every one of the four was found by *running* something rather than by
reading, which is the only reason they were found at all.

**1. §D8 prescribes "a new section K". Section K already exists in this file.** The letters in use
are A B C D G H I J K W; the first free one is **L**, and that is where the assertions live. A
section-K assertion would have been interleaved with an unrelated section's, which is not a
cosmetic problem: the EXPECTED headers in this file are per-section and a reader would have been
sent to the wrong one.

**2. §D8 computes the floor as 96 (87 + eight assertions + Z1). Ten assertions were needed, so the
floor is 98.** Two more than planned, and both additions are load-bearing rather than padding —
see finding 3 and `L9`. ADR-0083's rule applied to this ADR's own arithmetic: recount before
building on a count.

**3. §D3's classification is right only on a population §D3 never defines, and the four states are
not enough.** Classifying every block the boundary set produces gives `DIRECT` = 4 and 24 blocks
total, not `DIRECT` = {E2, H3} with eleven others: the two section-opener blocks (`Express path —
Steps E1–E4`, `Hybrid path — Steps H1–H5`) also carry `no sub-agents`. §D3's numbers hold on the
**mappable** population — the blocks a guide step token can actually reach — which is 16 tokens,
14 mapped, 2 not (`step_0_init` and `step_4_session_boundary` have no `Step 0`/`Step 4` heading).

The consequence is the fifth state. A first draft let an unmapped token fall through to `NEITHER`,
because an awk that never enters a block reaches `END` with an empty buffer and an empty buffer
contains no mechanism. `UNMAPPED` and `NEITHER` were then indistinguishable, so renaming
`#### Step E2 — Execute` would have removed E2 from the population **silently** — the check stays
green while it stops looking. `L5` pins the distinction, `L0` guards the denominator.

**4. §D6's prescribed note quotes the mechanism string that classifies it** — ``pin `isolation:
"worktree"` explicitly`` is the `DISPATCH` predicate verbatim. It is harmless only while the note
sits in the unmappable section-opener block; moved a few lines down into `Step E2` it would
classify that block `AMBIGUOUS`, and the guard would fire on the text written to satisfy it. Rule
12, inside the wording an ADR prescribed to close a rule-12-adjacent defect. The shipped note says
*"to pin that value explicitly"* instead, and `L9` makes the constraint structural rather than a
sentence someone has to remember.

**Also corrected:** the References entry above pointed at an implementation plan under
`docs/superpowers/plans/`. No such file exists and none was ever written — the chain was
interrupted at Step 2, before the architect produced one, which is precisely why §D3's numbers
were never checked against a second reader.
