# ADR-0122 — A bold-wrapped requirement id is invisible to both the checker and the repairer

- **Issue:** #291
- **Status:** Accepted
- **Date:** 2026-08-03
- **Supersedes in part:** ADR-0072 §D4 (the bold-wrapped exclusion, and only that)
- **Related:** ADR-0048 (requirement-ID coverage), ADR-0069 (one shared predicate), ADR-0072
  (near-miss self-repair), ADR-0086 (when to extract), ADR-0108 (plant registry)

---

## Context

`spec-coverage.sh` reads a requirement declaration only in one shape: an `R-NN` token as the
**first** token of a checklist item's text, inside a recognised requirements section. ADR-0072
closed the case where the checklist marker is missing (`- R-01 — …`) by adding a near-miss
detector plus a repairer, and it recorded — in §D4, in the shared predicate's own header, in
`concept-to-code/SKILL.md`, and pinned by `RN12` — that a **bold-wrapped** id stays invisible in
both forms. That disclosure is this ADR's subject.

### What was measured, before anything was designed

Every number below was produced by running the shipped scripts on 2026-08-03, on this branch
(`feat/one-real-plan-shape-is-recognised-by-no`, with #289 and #290 in history).

**M1 — the SPEC's corpus number is stale.** The SPEC says "36 SPECs measured at spec time".
`docs/specs/` holds **67** `.spec.md` files, **68** counting the root `SPEC.md`. It was 36 until
PR #317 (`4cacc76`) generated 31 Phase 10 SPECs in one commit. The SPEC was right when written.

**M2 — the harness number is stale.** The SPEC says "a 68-file `*.test.sh` harness". It is **73**.

**M3 — this is a HYPOTHETICAL defect in the corpus, not a live one.** Bold-wrapped ids in
*declaration position* across all 68 SPECs: **0**. There are three `**R-01**` occurrences in the
corpus — three in this feature's own SPEC and one in `313-spec-coverage-is-wholly-inert-for-a-spec`
— and **every one is inside backticks in prose**, describing the defect. Both producers'
templates emit the literal `- [ ] R-01 — …` (pinned by `RN15`). Separately, **61** corpus bullets
begin with `**`; not one carries an `R-NN`. So the shape "bullet then bold" is ordinary in this
corpus and the id-carrying variant has never occurred.

**M4 — the SPEC's Objective 1 does not reproduce as stated, and the true shape is worse.**
Objective 1 asserts that running the checker over a SPEC declaring `- [ ] **R-01** — …` shows the
id reaching neither the declared nor the malformed set — "the silence". Measured, the silence is
**conditional on the plan**:

| fixture | plan | result |
|---|---|---|
| all ids bold | cites nothing | `rc=0`, empty stdout, empty stderr — **silent, as claimed** |
| all ids bold | cites `R-01` | `rc=3`, `ORPHAN R-01` — **noisy, and misleading**: it blames the plan for citing an id the SPEC does declare |
| `R-01` plain + `R-02` bold | cites `R-01` | `rc=0`, `COVERED R-01` — **`R-02` vanishes and the gate passes** |

The third row is the damaging one, and it is the case the SPEC's own edge-case section calls "the
worse case": a *mixed* SPEC is only partially silent, so the run looks healthy while an entire
requirement is ungated. The first row's silence needs a plan that cites nothing, which a real
Step 5 plan rarely is.

**M5 — the exclusion's stated cause is correct, and it is the whole design.** The predicate header
says bold is excluded because "the checker's `item_text()` strips the checklist marker and then
requires `R-` immediately, so `- [ ] **R-01**` is invisible to it too and **normalising the marker
would not help**". That is exactly right. ADR-0072 §D4's invariant — *every line the detection
flags must become readable once the repair runs* — is what forbade detecting bold. **The exclusion
was never about bold being unrepairable. It was about the checker being unable to read the
REPAIRED line.** Fix the reader and the exclusion's own reason evaporates.

**M6 — three living sites state the limit and must move together**: the predicate header, the
`concept-to-code/SKILL.md` Step 5 gate block ("**A bold-wrapped id … is one of those**"), and
`RN12`. A disclosure that outlives its subject is the rot this repository has already paid for
once (the ADR-0016 hook-propagation note, which sent one investigation down a closed question).

**M7 — `declared as plain bullets` is a three-way cross-file contract.** It is produced by
`spec-coverage.sh`'s near-miss stderr sentence, **consumed** by the Step 5 gate block in
`concept-to-code/SKILL.md` as the trigger for the automatic repair, and asserted by `RN3`.
Rewording the sentence disables the auto-repair silently. (Checked, and a suspicion did not
survive: the gate captures with `2>&1`, so grepping stdout for a stderr sentence does work.)

**M8 — baseline.** `spec-coverage.test.sh` on the real tree: **PASS=114 FAIL=0**.

---

## Decision

### D1 — A bold-wrapped id READS AS DECLARED. It is not reported `MALFORMED`.

R-01 permits either outcome and forbids only silence. Declared is chosen because the id **is**
declared: the author wrote a well-formed `R-NN` as the first token of a success-criteria checklist
item and decorated it. The document renders correctly, means exactly what it says, and would be
refused by a gate for a cosmetic reason.

The supporting argument is this repository's own history. *A clause is the same clause whether it
wraps, whether a word inside it is code-quoted, whether it is bolded, and whether it opens a
sentence* — learned at ADR-0073 (line wrap), ADR-0076 (comment marker), ADR-0080 (backticks),
ADR-0082 (one-line marker), ADR-0098 (asterisks), ADR-0101 (capitalisation). **Seven instances, all
about this system's own assertions, and none of it was ever applied to the SPEC parser the system
ships.** #291 is that rule meeting the parser.

### D2 — One shared `strip_emphasis()`, in `spec-id-predicate.awk`, called by both consumers.

```awk
function strip_emphasis(s) { sub(/^[*_]+/, "", s); return s }
```

`spec-id-predicate.awk` is already "the one place that decides what counts as a requirement id"
(ADR-0069's rule, applied by ADR-0072). The reader and the writer must not disagree, and here that
is not a style preference — **it is what preserves ADR-0072 §D4's invariant by construction**:

- flagged: `- **R-01** — x` — a bullet whose emphasis-stripped text starts with `R-NN`
- repaired: `to_checklist_item()` prepends the marker → `- [ ] **R-01** — x`
- read: `item_text()` strips the marker → `**R-01** — x` → the **same** `strip_emphasis()` →
  `R-01** — x` → declared.

The repaired line is readable *because both sides call the same function*. If the two ever key on
different rules the invariant breaks in the direction §D4 warns about: the gate reports a problem,
rewrites the file, and still fails.

### D3 — Strip a RUN of `*` and `_`, never the literal `**`.

`sub(/^[*_]+/, "", s)` rather than a `**`-first-then-`*` ladder. Two reasons, one of them a trap.

The trap: a literal implementation **must** try the two-character form before the one-character
form, or `**R-01**` loses a single asterisk, becomes `*R-01**`, and stops matching `^R-`. A
character-class run has no ordering to get wrong.

The consequence, measured: `__R-01__`, `*R-01*` and `***R-01***` become readable for free. This is
tolerance, not endorsement — see D7.

### D4 — There are THREE extraction sites in `spec-coverage.sh`, not one.

Found by prototyping rather than by reading, and this is the load-bearing implementation detail:

1. the declaration match — `txt = item_text(line)`
2. the **near-miss token extraction** — `match(nmt, /^R-[0-9][0-9]/)` in the near-miss branch
3. the declaration's trailing text — `rest = substr(txt, RLENGTH + 1)`, which must also drop the
   closing emphasis run or `--list` reports `R-01` with the text `** — does X`

A first prototype patched 1 and 3 and missed 2. The result was the worst reachable state: **the
repairer rewrote a bold plain bullet while the checker stayed silent about it** — repair without
detection, the mirror image of the invariant §D4 exists to protect. Site 2 additionally carries an
**unguarded** `match()`: on no match it writes `substr(nmt, 0, -1)`, an empty line, which makes
`[ -s "$NEARMISS" ]` true with no content and sets `NEARMISS_FIRED=1` against an empty `STRUCT`.
The match is now guarded, so the file is written only when there is a token to write.

### D5 — The POSITION rule is untouched. Only decoration tolerance changes.

`- [ ] **Note** R-01 is mentioned mid-sentence` declares nothing, before and after: the emphasis
run is stripped, `Note** R-01 …` does not start with `R-`, and the line is a mention. Verified.

The widening also creates no new over-match class. `- **R-01 is important** — x` is flagged exactly
as the already-shipped `- R-01 is important — x` is flagged today; the tolerance for a loose tail
after the token is pre-existing behaviour that the decoration now travels through, not a new
behaviour introduced here.

### D6 — No new stdout token, and the stderr sentence keeps its load-bearing substring verbatim.

The exit-code contract is unchanged: bold-in-a-checklist-item is `COVERED`/`UNCOVERED` like any
declaration; bold-in-a-plain-bullet is `MALFORMED` + exit 3 with the near-miss stderr sentence, as
ADR-0072 already shaped it. The substring `declared as plain bullets` is preserved byte-for-byte
because of M7 — it is the Step 5 gate's auto-repair trigger, and it is the kind of coupling that
breaks silently.

### D7 — The canonical form does not change, and the producers are not touched.

`interview-driver` and `spec-from-issue` keep emitting `- [ ] R-01 — …`, and `RN15` keeps pinning
it. Tolerating a form is not endorsing it: the checker becomes forgiving about decoration, the
templates stay exact. This also keeps the diff off the two generators entirely.

### D8 — `RN12` inverts and is changed in kind, on the same fixture.

From *"the disclosed limit is pinned so the exclusion is a decision on record"* to *"the round trip
holds for the bold plain-bullet form"*: `- **R-01** — bold id` must now be rewritten to
`- [ ] **R-01** — bold id` and then read as declared. Same fixture, opposite contract. Deleting it
would lose the only assertion that has ever pointed at this shape; leaving it green would leave a
test asserting the opposite of the shipped behaviour.

### D9 — R-03 is proven at the MECHANISM level, not by a golden file.

Two assertions, sweeping the corpus, both count-guarded at `>= 50` (68 today, 36 before #317):

- **the differential** — no line anywhere in the corpus is emphasis-sensitive, i.e. no bullet, with
  or without a checklist marker, has text matching `^[*_]+R-[0-9][0-9]`. If that set is empty the
  parse is byte-identical to the pre-change parse and the verdicts *cannot* differ.
- **the outcome** — no corpus SPEC reports `MALFORMED` under the widened checker.

Measured with the prototype: **68 files compared, 0 verdict differences, 0 emphasis-sensitive
lines.** Under the prototype the whole harness moves 114/0 → **RN12 as the single casualty**
(a second failure, `RG1`, appears only in a sandbox that lacks `.github/` and passes on the real
tree).

Both sweeps include the root `SPEC.md`, unlike `RE3`, and the reason is specific: `RE3` had to drop
it because `RE3` demands the *silent pass* of its members, which an id-declaring SPEC legitimately
fails (issue #230). Neither of these two assertions demands anything an id-declaring SPEC fails, so
the #230 coupling does not arise. Including it is worth doing because the root `SPEC.md` is the
adversarial file — it carries three `**R-01**` occurrences in prose.

### D10 — Assertion ids: `RM01`–`RM12`, checked against the collision the plant runner has.

`plant-check.sh` decides a plant fired with `grep -q "^FAIL: $aid"`, a **prefix** match, and 41 of
the 148 existing plants sit on a collision. Checked mechanically over all **79** assertion ids in
`spec-coverage.test.sh`: `RM01`–`RM12` collide with **nothing** in either direction, and are
mutually non-prefixing because all are fixed-width. `RB` was the intuitive prefix and is already
taken (`RB1`, `RB2a`–`RB2c`, `RB3`–`RB5`).

`RN12` is reused deliberately (D8) and is a **sound plant target**: no id extends it. It does sit
on a pre-existing collision in the harmless direction — `RN1` is a prefix of it — so a plant on
`RN1` would be satisfied by `RN12` failing. No plant on `RN1` is added, so this feature contributes
no new collision.

---

## Alternatives considered

### Alt A — Report a bold-wrapped id as `MALFORMED` and let a human fix it. **Rejected.**

R-01 explicitly permits this, so it is a live option rather than a straw man, and it has a real
merit: exactly one canonical declaration form survives, which is easier to teach and impossible to
drift.

Rejected for three reasons. First, the prescribed heal would be *stripping decoration from a
human-reviewed artifact* — a content edit for cosmetic reasons, where ADR-0072's repair could
honestly claim to add a marker and change nothing. Second, it turns a SPEC that is correct in
substance and renders correctly into a structural error that halts Step 5, including on the
unattended paths where nobody can answer. Third, it declines to use the shared-predicate design
ADR-0072 built for exactly this: the machinery to make the form readable already exists and would
be left unused in favour of a refusal.

### Alt B — Widen only the near-miss predicate, leaving the checker as it is. **Rejected, and it is the trap.**

This is the smallest possible diff and it looks like it addresses the issue: bold plain bullets
would be detected and reported.

It violates ADR-0072 §D4's invariant outright. The repaired line `- [ ] **R-01** — x` would still
be unreadable, so the gate would report a problem, rewrite the SPEC, re-run, and fail again with
the file now modified. This is not a theoretical objection — the first prototype was accidentally
half of this shape (D4) and produced exactly the predicted state: a repairer rewriting a line the
checker had said nothing about.

### Alt C — Regenerate the SPEC through its producer instead of repairing it. **Rejected.**

ADR-0072 §D1 already rejected this for the plain-bullet case and the argument is unchanged and not
worth relitigating: `interview-driver` would redo the interview, `spec-from-issue` would rebuild
from the issue and discard human edits, and the SPEC has already passed Gate 1, so regeneration
destroys an approved review to fix a decoration.

### Alt D — Prove R-03 with a checked-in golden baseline of per-SPEC verdicts. **Rejected.**

The most literal reading of R-03 ("the same verdict as before") is a stored baseline compared
before and after.

Rejected because it rots by construction. PR #317 added 31 SPECs in a single commit; every corpus
addition would require regenerating the golden file, and a regenerated baseline records whatever
the code does *now*, which is precisely the thing it was supposed to be independent of. The
mechanism-level differential in D9 proves a stronger statement — that no input in the corpus can
reach the changed code path at all — and cannot rot, because it is derived at run time.

### Alt E — Also teach the two SPEC producers that bold is acceptable. **Rejected.**

Rejected as scope the issue does not ask for and as actively undesirable: it would weaken the one
canonical form `RN15` exists to pin, on the two files where exactness is cheapest. Tolerance
belongs in the reader (D7).

---

## Consequences

### Positive

- The mixed SPEC — the case where some requirements are gated and some vanish while the run looks
  healthy — is closed. That is the shape M4 measured as genuinely damaging.
- The round trip holds for the bold plain-bullet form, so ADR-0072's self-repair now covers both
  decorations rather than one, with the invariant preserved by construction rather than by care.
- `__R-01__`, `*R-01*` and `***R-01***` become readable at no extra cost (D3).
- `--list` text is cleaner: the closing emphasis run no longer leaks into the requirement text that
  the Step 5 tester brief consumes.
- Three sites that stated a limit which no longer exists are corrected together, so the next reader
  is not sent down a closed question.
- The change is provably a no-op on every SPEC that exists: 68 files, 0 verdict differences.

### Negative

- **A checker becomes more permissive.** It now accepts a form neither producer emits and neither
  template teaches. The canonical form is unchanged and pinned, but the gate no longer enforces it,
  and "the checker accepts it" will eventually be read as "it is the house style".
- **The corpus cannot validate any of this.** Zero of 68 SPECs exercise the new path (M3), so
  every bold assertion rests on fixtures. ADR-0092's technique — derive the value domain from the
  real corpus — does not apply here, and a future reader should not mistake a green corpus sweep
  for evidence that the feature works.
- **The whole-item-bolded form declares with a cosmetic tail.** `- [ ] **R-01 — does X**` becomes
  declared with text `does X**`. Better than silent, not clean. Left as-is: trimming a trailing run
  that does not immediately follow the token would mean parsing emphasis spans, which is a markdown
  parser, not a predicate.
- **Fixing this feature is now four files that must agree**: the predicate, the checker, the
  repairer's header, and the SKILL.md gate paragraph. M6's coupling is reduced, not removed.
- Inert until sync, as always. All four scripts already carry `PAIRS` entries (verified), so no new
  deployment gap is created — but the deployed copy keeps the blind spot until
  `sync-to-claude.sh --apply`.

### Neutral

- No new stdout token, no change to the exit-code contract, no manifest field, no schema bump.
- No `PAIRS` change, no `docs-ci.yml` change (`spec-coverage.test.sh` is already in the named list;
  `RG1` confirms it).
- `spec-normalize-ids.sh` gains **no executable change at all** — it composes the shared predicate,
  so the widening reaches it for free. Its header is corrected because it describes the old reach.
- The producers, `RN15`, and `test-write-scope.sh` are untouched.
- `plan-task-predicate.awk` is untouched; #290 changed only its comments, and the two functions
  this design depends on (`heading_level`, `is_checklist_item`) are unchanged.

---

## References

- `docs/architecture/ADR-0072-171-spec-id-near-miss-self-repair.md` — anchor on the
  "**D4 — The detection is bound by the repair's reach**" section and on the consequence bullet
  "Bold-wrapped ids remain invisible to the checker in both forms".
- `docs/architecture/ADR-0048-102-requirement-ids-coverage.md` — the `ADR-NNNN` boundary rule,
  deliberately out of scope here.
- `docs/architecture/ADR-0069-172-plan-task-form.md` — the loaded-not-pasted predicate rule.
- `docs/architecture/ADR-0108-284-plant-registry.md` — the plant declaration contract.
- `staging/plugin/skills/concept-to-code/scripts/spec-id-predicate.awk` — anchor on the
  `is_near_miss_bullet` function and on the header paragraph beginning "THE INVARIANT THIS
  PREDICATE IS BOUND BY".
- `staging/plugin/skills/concept-to-code/SKILL.md` — anchor on the paragraph beginning "If the
  re-run still returns 3, stop as before".
- `staging/plugin/scripts/tests/spec-coverage.test.sh` — section `RN`, assertion `RN12`.
