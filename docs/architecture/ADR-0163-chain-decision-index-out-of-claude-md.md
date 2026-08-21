# ADR-0163 — the chain decision index is looked up, not loaded

- **Topic slug:** `chain-decision-index-out-of-claude-md`
- **Issue:** none — measured live in the session of 2026-08-21, alongside ADR-0162
- **SPEC:** none — a bounded move with four named consumers and one producer, no requirement ids
- **Extends:** ADR-0136, which moved the 95 narrative blocks out of `CLAUDE.md` and left the index
  behind. This is the same split applied one level down, for the reason ADR-0136 §D2 already gives.
- **Deliberately does not touch:** `## Rules`. That is the instruction layer and it is loaded on
  purpose (rule 16). Also untouched: the 400-line ceiling guard, which stays measured on `CLAUDE.md`.

## Status

Accepted — 2026-08-21.

## Context

`CLAUDE.md` is re-created in full on the first turn after every compaction. Measured from this
session's own transcript, that first turn's `cache_creation_input_tokens` runs 48,456 to 54,945 and
drops to 546–2,008 on the turns after: roughly 50k of fixed preamble, paid once per compaction.

Of that preamble, the part this repository owns and can cut is `CLAUDE.md` itself. Measured on
`main` at `a6aaa9b`: 290 lines, 35,715 bytes, of which `## Chain decision index` is **117 entries
and 23,751 bytes — 66.5% of the file**. Estimated from bytes at ~4 bytes per token, that is ~5.9k
tokens per turn.

The index is not instruction. It is one line per ADR saying what that ADR decided and where it
lives — lookup data, read into context on every turn to answer a question nobody asked. ADR-0136
left it in place when it was 95 entries and plausibly part of the instruction layer. The
Consequences of that ADR are what made the difference visible: re-growth was measured at 55, 55, 49,
76, 61 and 56 lines per feature, and **one index line per feature accumulates while one Rules line
per feature does not** — most features establish no new rule at all.

## Decision

### D1 — the index moves to `docs/chain-decision-index.md`, verbatim

117 entries, extracted with `sed` and verified byte-identical against `git show HEAD:CLAUDE.md`
rather than against the working copy. Paths stay backticked code spans: the `links` job is blocking
and runs with `--include-fragments`, and a bare `docs/architecture/…` path in a file that itself
lives under `docs/` would start resolving one level too deep. One line of prose is added that the
original did not carry — *paths are relative to the repository root, not to this file* — because
moving the file is exactly what makes that ambiguous.

### D2 — the `## Chain decision index` heading STAYS in `CLAUDE.md`, and that is load-bearing

Not for tidiness. `CMC02` extracts the Rules population with
`sed -n '/^## Rules$/,/^## Chain decision index$/p'`, a literal terminator, and `CMC03` uses
`/^## Rules$/,/^## /p`, which stops at the next level-2 heading — which is this one. Delete the
heading and both assertions silently widen to end-of-file and stop meaning what they say. The
heading keeps a four-line pointer beneath it, so a reader of `CLAUDE.md` still learns the index
exists and where it went.

### D3 — `CMC04`, `CMC05` and `CMC06` leave the `CMD_PRESENT` guard, for the opposite reason to the one first written

The plan for this change said to move them out because *the plant sandbox copies only `../docs/`, so
a plant on a root file cannot be reached and reports `NOFIRE`, which reads as clean*. **That premise
is false and was false before this change.** `build_sandbox()` in `plant-check.sh` copies six
things — `staging/`, `docs/`, `.github/`, `.gitignore`, `CLAUDE.md` and `PROJECT.md` — and the
comment above it records the measurement that forced the last four: with only the first two, 26
harnesses fail and 58 (file, assertion-id) pairs are RED before any mutation.

The real reason is simpler and it points the same way. Those three no longer read `CLAUDE.md` at
all; their subject is now a file under `docs/`, which the sandbox copies and every real checkout
has. So there is no environment in which it is legitimately absent, and an absence is a **defect**:
they get their own presence guard that calls `bad`, where the old one called `skip`. That is rule 4
pointing the other way — "did not run" and "found nothing" must stay distinguishable, and here the
honest third state is not `SKIP` but `FAIL`.

The false premise was also written into the harness's own header comment, which is where the plan
inherited it. It is corrected there in the same change, because prose asserting something untrue at
the exact spot the next reader will look is worse than no prose.

### D4 — the producer switches on the destination file's presence, the way the archive already does

`concept-to-code` Step 3 appends the index line to `docs/chain-decision-index.md` when that file
exists, and falls back to `CLAUDE.md.proposed` when it does not. This is byte-for-byte the switch
ADR-0136 §D1 already established for the archive — *the file's presence is the switch, so no project
is broken by this change* — and it is why no other repository generated from this blueprint needs to
do anything. Without this, the next chain run appends the index line back into `CLAUDE.md` and the
condensation undoes itself one feature at a time (rule 17).

`CMC13` is the assertion that the producer and the new consumer meet. It is planted.

### D5 — three new plants, and one assertion declared unplantable with its reason

`CMC04` (an index entry pointing at a file that is not there), `CMC05` (an index line that stops
being an index line, so the index and the archive disagree) and `RY12`'s new second leg all carry a
plant against `../docs/chain-decision-index.md`. `RY12` now has two declarations, which is a form
already in use — `BK9b` and `RJ13b` do the same.

**`CMC06` carries no plant, and that is a property of the assertion.** It is `>= 90` over 117
entries: no single-line mutation this grammar can express takes it RED, because a floor absorbs its
own plant (rule 10). It is kept as a vacuity guard on the derivation, the site says so, and `CMC05`'s
exact equality is where a plant actually bites. Saying this beats leaving a silently unplanted
assertion in a file whose whole subject is assertions that pin nothing.

Both plant needles avoid a trailing space at end of line. The three-field delete form makes that
easy, and ADR-0149 already records why the alternative spelling — four fields with an empty
fourth — is not offered: any editor strips the space it depends on.

## Consequences

- `CLAUDE.md`: 290 → **173 lines**, 35,715 → **12,368 bytes**. ~5.9k tokens per turn removed from
  the fixed preamble, estimated from bytes; the measurement that settles it is the first-turn
  `cache_creation_input_tokens` in the next session, not this diff.
- Zero rules touched, zero index entries lost. Preservation is checked whole-line
  (`comm -23` against the pre-move slice from `git show`), which is ADR-0032's semantics: a prefix
  match is not preservation.
- The plant registry goes from 509 to **513 declarations**.
- `CMCZ1`'s floor moves 12 → 13 for `CMC13`, and the sandbox skip list drops from eight assertions
  to five.
- Looking up an ADR now costs one file read that used to be free. That is the trade, and it is the
  right way round: the lookup happens on the rare turn that needs it, the load happened on all of
  them.
- ADR-0136 is corrected **forward**, in a dated `## Correction`, never in place (rule 14). Its D1
  bullet describes a shape that no longer exists and was correct on its day.

## Verified vs assumed

**Verified.** The 117/23,751/66.5% figures, re-derived from the files on 2026-08-21 rather than
taken from the plan, which said 116/23,470 and was one merge out of date (rule 13). The
byte-identity of the moved entries. `build_sandbox()`'s six copies, read from `plant-check.sh`. That
`CMC01–CMC12` and `CMCZ1` pass at 14/14 with 0 skipped, and `spec-coverage.test.sh` at 170/170.
That the three new plants fire.

**Assumed.** The ~5.9k tokens-per-turn figure is bytes divided by a nominal 4 bytes per token, not a
tokenizer measurement. The direction is certain; the magnitude is an estimate until the next
session's first-turn cache figure is read.

**Explicitly not claimed.** Nothing here says anything about what governs the autocompact threshold.
ADR-0162 §D4 refuses that claim and this ADR inherits the refusal: a smaller preamble is more working
room whatever the trigger turns out to be.
