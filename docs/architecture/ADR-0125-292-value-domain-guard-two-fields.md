# ADR-0125 — The value-domain guard covers one field of three, and the other two are shaped differently on purpose

- **Status:** Accepted
- **Date:** 2026-08-04
- **Issues:** #292
- **Related:** ADR-0092 (#240, the guard being extended — its §Consequences names this gap),
  ADR-0076 (#195, whose §D2 sentence is the artefact under check), ADR-0086 (the derived-guard
  pattern — instance 12, and the criterion applied here in *both* directions), ADR-0085 (guard the
  denominator), ADR-0107 (the shape of a property that holds and is checked by nothing), ADR-0124
  (an assertion-count floor with slack absorbs its own plant), ADR-0034 (historical records
  corrected forward, not edited in place)

## Context

ADR-0092 closed #240 with section `V` of `manifest-field-state.test.sh`: derive the **written**
value set from the producers, derive the **documented** set from the helper's own header, compare in
**both** directions. Its own consequence bullet states the boundary — *"The guard covers
`step5_mode` only. `hook_verified` and `step5_review_mode` are named in the same sentence and are
**not** derived — their producers are shaped differently and would need their own extraction."*

Everything below was measured before anything was designed. **Five of the SPEC's premises did not
reproduce, and two of them change the design.**

### The corpus and the harness are both larger than stated

49 manifests, not 41. 73 harness files, not 68. Both numbers are quoted in the SPEC and both were
accurate for an earlier moment. Re-derive; do not cite.

### Neither field has a phantom today — this is a guard, not a fix

| field | written (producers) | documented (header) | corpus |
|---|---|---|---|
| `hook_verified` | `true`, `false` | **"a boolean"** | 45 `false`, 4 `true`, 0 absent |
| `step5_review_mode` | `none`, `checkpoint` | `none`, `checkpoint` | 31 `none`, **0 `checkpoint`**, 18 absent |

Both directions are clean on both fields. There is no `agent_fallback` here waiting to be found.
This is ADR-0107's shape rather than ADR-0092's: **the property holds and nothing checks it.**
A reader expecting a #240 repeat will hunt for one, find nothing, and wonder what was fixed. The
answer is that a correct property with no check is one edit from an incorrect property with no
check, and the last time that combination was left alone the wrong string stood for months.

`checkpoint` being written by nothing in 49 manifests is **not** the #240 shape. #240 was a value no
*producer* writes; `checkpoint` has a producer and simply has never been opted into. The reverse
check compares documented against **produced**, never against the corpus — that distinction is what
keeps an unexercised opt-in from reading as a phantom.

### Live defect 1 — `hook_verified`'s documented domain is a TYPE, not a value set

The header reads *"`hook_verified` is a boolean"*. Run ADR-0092's own documented-set derivation
against it and it yields the single token **`a`**. There is no enumeration to compare against, so
R-01 cannot be satisfied for this field without correcting the header.

It is also genuinely ambiguous, and the ambiguity is reachable. `yaml.safe_load` implements YAML 1.1
booleans, so `yes`/`no`/`on`/`off` parse as booleans — measured: a manifest carrying
`hook_verified: yes` reports `PRESENT|True`, and both real call sites (autopilot-build check 7,
nightly check 6) assert exactly `PRESENT|True`/`PRESENT|False` and would accept it. Meanwhile
`manifest-set-flag.sh`, the only writer, structurally refuses anything but the literals `true` and
`false`. "A boolean" therefore names a set strictly wider than what any producer can write, in the
one place ADR-0076 §D2 tells the next checker author to copy.

### Live defect 2 — R-02 is not satisfied by the existing flatten, and the SPEC assumes it is

The SPEC treats the wrap problem as solved by ADR-0092's flatten and asks only that the extension
inherit it. Measured against a fixture where the sentence re-flows so a value list is split
**inside** itself:

```
# ... step5_review_mode is none|
# checkpoint. There is no general "valid".
```

the existing derivation returns **`none|`** — the set `{none}`, with `checkpoint` silently dropped.
`tr '\n' ' '` followed by `sed 's/# //g'` leaves a space between `|` and the continuation, and the
`[a-z_|]+` character class stops at it. Today's header wraps *between* `is` and its list, which the
flatten does survive; the untested case is the one a routine re-flow produces.

The count guard would catch it (a 1-element set fails `>= 2`), so the failure is loud rather than
silent. That is the safe direction and it is not the same as surviving the wrap, which is what R-02
asks for.

### The producers are shaped differently, and the difference is measurable rather than stylistic

ADR-0092 asserts this without showing it. Applying `step5_mode`'s extraction idiom
(`<field>: [a-z_]+` over `skills/*/SKILL.md` and `skills/*/scripts/*.sh`) to each field:

- **`step5_review_mode`** — 7 matches, all clean: `{none, checkpoint}`.
- **`hook_verified`** — 11 matches yielding `{false, true, field, manifest, the, value}`. The four
  extra tokens are **English words** lifted out of operator-facing error messages that happen to use
  a colon: `echo "✗ hook_verified: field absent …"`, `"✗ hook_verified: value is …"`,
  `"✗ hook_verified: manifest-field-state.sh not found …"`, `"✗ hook_verified: the manifest could
  not be read …"` in `autopilot-build/SKILL.md` and `nightly-autopilot/SKILL.md`. A guard built on
  the shared idiom fails on a correct tree on its first run, reporting that producers write four
  values the domain omits.
- The obvious alternative idiom, `hook_verified=<word>`, is worse: it adds **`unchanged`** (8 hits),
  which is `hook-verify-workflow.sh`'s `RECOMMEND hook_verified=unchanged` token and means
  *do not write this field at all*. A recommendation not to write would enter the written set.

This is rule 12 one level up from where this repository normally meets it: not an assertion whose
needle matches the prose explaining it, but a **derivation** whose needle matches the prose
explaining the field.

### What actually bounds `hook_verified`

Its producers are `manifest-init.sh`'s bare-literal default (`hook_verified: false`) and the
`manifest-set-flag.sh <manifest> hook_verified true|false` call sites. That extraction yields
exactly `{true, false}`. Behind it sits a stronger fact: `manifest-set-flag.sh` validates
`[ "$VAL" != "true" ] && [ "$VAL" != "false" ]` and exits 1 otherwise, so the written domain is
enforced by code, not merely observed. **That validation is asserted nowhere in the CI harness** —
measured across all 73 files.

The symmetric fact for `step5_review_mode` is `manifest-validate.sh` invariant 14, whose
`^step5_review_mode: (none|checkpoint)$` is an enumerated enforcer. Its *behaviour* is covered
(`step5-checkpoint-review.test.sh` B1/B2/B3 accept `none`, accept `checkpoint`, reject
`aggressive`); its **agreement with the documented domain** is not. An enforcer and a document
disagreeing is #240's shape with a different pair of files.

### One more thing worth knowing about `checkpoint`

Its only real producer is a `sed` command sitting **inside a comment** at `manifest-init.sh:134`,
which every generated manifest carries so a human can find it (ADR-0039 §D8). `concept-to-code/SKILL.md`
also names `step5_review_mode: checkpoint` twice in prose. So a permissive extractor keeps reporting
`checkpoint` as written even if the sed line were deleted — prose sustaining a value whose producer
has gone. Narrowing the extractor to `scripts/*.sh` would fix that and would go blind to a future
genuine SKILL.md producer. The extractor stays permissive and the real producer is pinned separately.

### Existing state of the file

34 assertions, all green. `Z1`'s floor is 30 with 33 counted — **three units of slack**, which under
ADR-0124's finding means three assertions could vanish while `Z1` stays green. The file carries
**zero** declared plants, so ADR-0092's four verification plants exist only as a table in that ADR.

## Decision

### D1 — Per-field extractors, one shared documented-set derivation, one shared comparison

ADR-0086's criterion — *extract only when two copies giving different answers would be a defect* —
is applied here in both directions inside one file, which is the case that makes it legible.

- **The WRITTEN-set extractors are per-field and stay separate.** They answer three different
  questions about three differently-shaped producers, and the measurement above shows a shared idiom
  is not merely inelegant but wrong: it fails on a correct tree for `hook_verified`. Each extractor
  carries a comment naming the shape it reads and, for `hook_verified`, the four phantom words the
  shared idiom would have produced.
- **The DOCUMENTED-set derivation is ONE function taking the field name.** It asks a single question
  — *what does this header say the domain is* — of one sentence, three times. Three copies drifting
  is #240's own shape one level up: a source and its restatements disagreeing.
- **The comparison is ONE function**, called six times (three fields × two directions). It returns
  the offending list and **never reports**; each call site formats its own message, because V1's and
  V2's failure texts are deliberately different and are anchors.

`V0b`, `V1` and `V2` are refactored onto the two shared functions with their **assertion ids and
`ok`-line text preserved byte-for-byte**. This touches code the SPEC scopes out, and the reason is
that leaving a second implementation of one question inside one file is the defect ADR-0069,
ADR-0086 and ADR-0120 each recorded. The `V0b` *failure* message gains the second cause (see §D3);
that keeps message and mechanism in agreement, which is ADR-0120's lesson.

Nothing is extracted **across** test files. Instance 12 of the derived-guard pattern, deliberately
not shared (ADR-0086 §D1), and with **no waiver mechanism** (§D4).

### D2 — The header enumerates `hook_verified`, on the written-literal axis, and says which axis

`hook_verified is a boolean` becomes `hook_verified is true|false`, followed by a sentence naming
the axis: these are the **literals a producer writes**; the helper's own stdout renders a parsed
YAML boolean as `True`/`False` (`S1`/`S2`) and a quoted `"true"` as `true` (`S11`), which is a
different axis and must not be reconciled with this one.

That sentence is load-bearing. Someone reading `PRESENT|True` on stdout will want to "fix" the
header to `True|False`, and the axis note is the only thing at that site telling them not to. If
they do it anyway the derivation's `[a-z_|]+` class cannot match a capital and the count guard fails
loudly naming the cause — the safe direction, and a second reason to state the causes in that
message rather than only the wrap.

`CLAUDE.md`'s restatement of the same sentence is corrected in the same edit: it is live text a
reader acts on, exactly as ADR-0092 §D1 treated it. `ADR-0076`'s body is **not** edited
(ADR-0034 precedent) and needs no new `## Correction` — its "is a boolean" was never false, only
never an enumeration.

### D3 — The documented-set derivation collapses whitespace around `|`

`sed 's/[[:space:]]*|[[:space:]]*/|/g'` is added after the comment-marker strip. Verified against
three wrap shapes — no wrap, wrap after `is`, wrap **inside** a value list — all three now yield the
full correct set for all three fields. The regex stays anchored on `<field> is` plus its trailing
space, so collapsing pipes elsewhere in the header (`PRESENT|<value>`, `${st%%|*}`) cannot be
picked up.

This satisfies R-02 by **surviving** the wrap rather than by failing loudly on it. `WW1` runs the
derivation over a fixture copy of the helper whose sentence is re-flowed mid-list and requires the
full set back; removing the collapse turns it red.

### D4 — No waiver, asserted behaviourally rather than stated

ADR-0092 recorded "no waiver mechanism, deliberately" as prose. A prose claim about an absent
mechanism is unplantable and rule-12 exposed — a needle on it matches the sentence explaining it.

Instead: the comparison function takes two value lists and nothing else, and `WN1` runs the
documented-set derivation and the comparison against a fixture copy of the helper carrying a
`# value-domain-exempt: <phantom>` line, requiring that the mismatch is **still reported**. Planting
a marker-honouring branch into either function turns it red. That is a behavioural check that no
waiver exists, which is the strongest form the claim can take.

### D5 — Each field's enforcer is pinned, because it is what makes the narrow extractor trustworthy

- `WH6` — `manifest-set-flag.sh` refuses a value that is not `true`/`false`, run and asserted on its
  exit code and message. This is the reason `hook_verified`'s extractor may read only two call-site
  shapes without going blind: nothing else can write the field. Covered nowhere before this.
- `WR6` — `manifest-init.sh`'s `sed` flip line, `checkpoint`'s only real producer, still exists.
  The mitigation for the permissive extractor's blind spot: without it, SKILL.md prose alone would
  keep `checkpoint` in the written set after its producer had gone.
- `WR7` — invariant 14's enumeration equals the documented domain, derived from
  `manifest-validate.sh` at run time. This is the enforcer-versus-document agreement check;
  `step5-checkpoint-review.test.sh` B1/B2/B3 cover invariant 14's *behaviour* and this covers a
  different question, so it is not a duplicate.

### D6 — The corpus is swept on the LITERAL axis, which `R1` does not cover

`R1` already sweeps the corpus for `hook_verified`, on the **parsed-state** axis
(`PRESENT|True`/`PRESENT|False`/`ABSENT|completed`). `WH5` sweeps the same field on the
**written-literal** axis (`grep '^hook_verified:'`, compared against the written set). They are not
redundant, and the YAML 1.1 measurement is the proof: `hook_verified: yes` **passes `R1`** (it parses
to `True`) and **fails `WH5`** (the literal `yes` is written by no producer). Both sweeps are
count-guarded on their own denominator (ADR-0085): `>= 30` for `hook_verified`, `>= 20` for
`step5_review_mode`, which 49 and 31 clear with room and an empty glob does not.

### D7 — `Z1`'s floor moves to the exact executed count

Fifteen assertions are added; the floor stays at 30 unless it is moved, leaving eighteen units of
slack in the assertion that exists to notice assertions vanishing. ADR-0124 raised its own floor in
the same edit for exactly this and recorded the lesson as *the defect being removed, reintroduced by
the change that removes it*. The floor is set to the executed total, which the coder re-derives from
a real run rather than from this ADR. Every new assertion must call exactly one of `ok`/`bad` on
every path, including inside its count guards, so the total is deterministic.

## Alternatives considered

### Alt A — One shared extraction idiom for all three written sets

The obvious design, and the one the SPEC implies by describing the work as "extend the guard to both
fields". **Rejected on measurement.** The `<field>: [a-z_]+` idiom yields four English-word phantoms
on `hook_verified` (`field`, `manifest`, `the`, `value`), all from operator error messages, so the
forward comparison fails on a correct tree the first time it runs. The `hook_verified=<word>` variant
is worse, adding `unchanged` — a token whose meaning is *do not write*. Making one idiom work would
require an exclusion list of message-shaped lines, which is a waiver mechanism wearing a different
hat and is what §D4 refuses.

### Alt B — Keep "a boolean" and special-case the derivation to expand it

Leaves the header honest to its author's intent and avoids touching the live worked example.
**Rejected.** It puts a type-to-value-set mapping inside the guard, which means the guard now knows
something the header does not say — and the header is the artefact a checker author copies, so the
knowledge would be in the wrong file. It also leaves the YAML 1.1 ambiguity in place: "a boolean"
admits `yes`/`no`/`on`/`off` (measured: `hook_verified: yes` reads `PRESENT|True`) while
`manifest-set-flag.sh` refuses all four. A domain the writer cannot write is not a domain.

### Alt C — Accept the loud count-guard failure as R-02's satisfaction

The count guard does catch an in-list wrap: the derived set drops to one element and `>= 2` fails.
**Rejected.** R-02 asks the derivation to *survive* the wrap, and there is a real difference: a loud
failure on a header someone merely re-flowed is a red harness on a correct change, which trains
people to edit the guard. The collapse is one `sed` clause and was verified against three wrap
shapes; there is no cost to buy the stronger property with.

### Alt D — Derive the documented set from `CLAUDE.md` as well

`CLAUDE.md:1323` carries the same sentence, and #240's drift ran source → summary, so checking the
summary against the producers looks like closing the actual historical hole. **Rejected on two
grounds.** `plant-check.sh` copies only `staging/` and `docs/`, so any assertion reading a repo-root
file is unplantable and would silently pass in every sandbox (the class ADR-0122 recorded); and a
summary is by definition a restatement, so deriving from it makes two documented sets where §D1 has
just argued for one. The summary is corrected by hand in the same edit and its agreement with the
header is left unasserted — recorded as a consequence rather than hidden.

### Alt E — Extract the derivation into a shared script used by several test files

ADR-0086's standing question, asked again because this is instance 12. **Rejected**, on that ADR's
own criterion: the six guards that could share this ask six different questions about six
populations, each hermetic and independently runnable, and a defect in a shared source disables all
of them at once in the stay-green way this repository has watched three times. The extraction here
is strictly *within* one file, where the copies would answer one question, which is the case the
criterion says to extract.

### Alt F — Narrow the `step5_review_mode` extractor to `scripts/*.sh`

Would make `checkpoint`'s presence in the written set depend on its real producer rather than on
prose. **Rejected.** It goes blind to a genuine future producer written into a `SKILL.md`, which is
where `step5_mode`'s own producers live, so it trades a disclosed blind spot for an undisclosed one.
The permissive extractor is kept and the real producer is pinned by `WR6` instead — a check that
names the mechanism rather than a filter that hopes.

### Alt G — Add an invariant for `hook_verified` to `manifest-validate.sh`

Would make the domain enforced on read as well as on write. **Rejected as out of scope**: the SPEC
scopes out converting `manifest-validate.sh`'s invariants, ADR-0076 declined the same conversion,
and the field already has a structural enforcer at the only write path. Noted here so it is a
decision rather than an omission.

## Consequences

### Positive

- The value-domain guard covers all three additive fields named in the sentence it derives from,
  in both directions, with count guards on every derivation and on both corpus denominators.
- `hook_verified`'s documented domain becomes a value set instead of a type name, closing the
  YAML 1.1 ambiguity in the one place a future checker author is told to copy.
- The documented-set derivation survives a re-flow that splits a value list, which no wrap fixture
  had previously exercised — including for `step5_mode`, which inherits the fix.
- Two enforcers gain their first assertions: `manifest-set-flag.sh`'s `true|false` validation was
  covered by nothing in 73 harness files, and invariant 14's agreement with the documented domain
  was covered by nothing.
- The file gains its first 15 declared plants; ADR-0092's four verification plants existed only as a
  table in that ADR and could not be re-run.
- `Z1`'s three units of slack are removed before fifteen assertions are added to hide behind them.

### Negative

- The written-set extractors are three different greps with three different shapes, and only a
  comment at each site explains why they may not be unified. Someone tidying the file will be
  tempted, and the only thing stopping them is prose plus a forward comparison that will go red.
- `V0b`, `V1` and `V2` are re-implemented onto shared functions. Their ids and `ok` text are
  preserved byte-for-byte, but ADR-0092's assertions are no longer the code ADR-0092 describes.
- The `hook_verified` extractor reads a call-site shape that includes the literal string
  `manifest-set-flag.sh`. Renaming that helper makes the written set collapse to `{false}` — loud
  via the count guard, but a rename is a plausible future edit and this is a new coupling.
- `checkpoint` remains written by nothing in 49 manifests, so `WR5`'s corpus sweep has never
  exercised it and cannot. If the opt-in is ever taken, the first manifest carrying it is the first
  real test of that path.
- `CLAUDE.md`'s restatement is corrected by hand and checked by nothing, for the plantability reason
  in Alt D. The summary can drift from the header again, which is precisely #240's route.
- The plant registry grows from 171 to 186 declarations, roughly 12s of additional CI time.
  ADR-0108 already flagged that 100 plants would want their own job; this is not that, and it moves
  toward it.

### Neutral

- Nothing about either field's actual behaviour changes. No manifest is rewritten, no producer is
  altered, no call site's policy moves, and both fields' domains were already correct in substance.
  The only executable behaviour change outside the harness is `manifest-init.sh` and
  `manifest-set-flag.sh` remaining byte-identical while the helper's *comment* is corrected.
- The 18 manifests absent `step5_review_mode` and the 0 absent `hook_verified` are untouched, on
  ADR-0075's rule: a historical record is accurate for its moment.
- Whether YAML 1.1's `yes`/`no`/`on`/`off` should be rejected at read time is left open. Nothing
  writes them, `manifest-set-flag.sh` refuses them, and `WH5` now catches one if it appears in a
  manifest by hand. Making the two call sites reject them is a separate decision.
- The `manifest-field-state.sh` header grows by roughly four lines. It is already the longest
  comment block in the skill's `scripts/` directory and is read as documentation, not as prompt
  context, so the cost is not a token cost.

## References

- Issue #292 — the value-domain guard covers `step5_mode` only
- `SPEC.md` / `docs/specs/292-the-value-domain-guard-covers-step5-mode.spec.md` (R-01, R-02, R-03)
- `docs/architecture/ADR-0092-240-step5-mode-value-domain.md` — the guard extended here; its
  §Consequences names this gap
- `docs/architecture/ADR-0076-195-additive-field-state.md` §D2 — the sentence under check; body not
  edited, per ADR-0034
- `docs/architecture/ADR-0086-derived-guard-pattern-not-extracted.md` — the extraction criterion,
  applied in both directions here
- `docs/architecture/ADR-0085-208-derived-guard-boundaries.md` — denominator guards
- `docs/architecture/ADR-0107-281-fence-contract-population.md` — a property that holds and is
  checked by nothing
- `docs/architecture/ADR-0124-346-spec-pointer-baseline.md` — a floor with slack absorbs its own
  plant
- `docs/architecture/ADR-0039-early-coder-feedback.md` §D8 — `step5_review_mode`'s `sed` opt-in
- `docs/architecture/ADR-0016-dynamic-workflows-step5.md` — `hook_verified`'s origin, and `V4`'s pin
- `staging/plugin/skills/concept-to-code/scripts/manifest-field-state.sh` — the header under check
- `staging/plugin/skills/concept-to-code/scripts/manifest-set-flag.sh` — `hook_verified`'s enforcer
- `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` — invariant 14
- `staging/plugin/scripts/tests/manifest-field-state.test.sh` — section `V`, extended by `W`
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry (ADR-0108)
