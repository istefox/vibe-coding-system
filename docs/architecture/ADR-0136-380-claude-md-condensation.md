# ADR-0136 — Condense CLAUDE.md to rules and an index, and stop the producer re-growing it

- **Status:** Accepted
- **Date:** 2026-08-13
- **Issue:** #380
- **Supersedes in part:** the `CLAUDE.md` write step of `concept-to-code` Step 3 Branch A
- **Related:** ADR-0019 / ADR-0032 / ADR-0044 (the content-preservation gate this reuses),
  ADR-0034 (historical records are corrected forward), ADR-0086 (the extraction criterion),
  ADR-0102 (a gate that cries wolf)

## Context

`CLAUDE.md` is loaded in full into every orchestrator turn and re-injected after every `/compact`.
Sub-agents do not load it. It had become an append-only log: one narrative block per merged
feature.

Re-measured on 2026-08-13, because #380's figures are from 2026-08-06 and this repository adds
ADRs continuously:

| | #380 (08-06) | at implementation (08-13) |
|---|---:|---:|
| lines / bytes | 3,592 / 274 KB | **3,895 / 300 KB** |
| `## Decisions from` blocks | 90 | **95** |
| ADR files on disk | 132 | **138** |
| non-block content | 80 lines | **80 lines** |
| ~tokens at 4 B/token | 68,528 | **74,966** |

Issue #380 costs the re-reads at ~$1,616 over 42 orchestrator sessions, 21.5% of the
orchestrator's 5.01B cache reads, against ~$343 for the entire `coder` agent across 51 runs.

### Two of the issue's premises did not reproduce, and both changed the design

**1. The blocks are not duplicates of the ADRs.** #380 says *"98% of it is 90 ADR summary blocks
duplicating 132 files that already exist on disk."* Measured across all 95 blocks against the ADR
each one points at:

| | |
|---|---:|
| substantive block lines | 3,132 |
| …appearing verbatim as a whole line in the ADR | **6 (0%)** |
| distinctive 6-word phrases in the blocks | 45,765 |
| …also present in the ADR | **2,501 (5%)** |

Four of six distinctive claims spot-checked are absent from their ADR entirely: ADR-0135's
alternating-anchor lesson, the #410-duplicates-#357 finding, ADR-0086's extraction criterion
verbatim, and ADR-0080's naming of the "decoration family". And **eleven blocks carry an explicit
cross-ADR synthesis** — *"third of its family"*, *"fourth of its family"* — which by construction
cannot live in any single ADR, because it is a statement about the relationship between them.

So deleting a block does not leave its content on disk. `CLAUDE.md` was the only home of the
cross-ADR synthesis, which is exactly the material worth keeping and exactly what the literal
proposal would have destroyed.

**2. "Every rule preserved, verified mechanically" is not achievable as stated.** Re-deriving
the recurring-rule table in #380 produced different counts in both directions — decoration 17
against its 44, derived-guard 10 against its 19 — because the needles behind it are recorded
nowhere. An unenumerable set cannot be mechanically checked for preservation. §D5 says what is
checked instead, and §Consequences/Negative says plainly what is not.

### It was found once before, with the right remedy and the wrong reason

`docs/deep-refactor/2026-05-31-vibe-coding-system-audit.md:43` filed it as P2 two and a half months
before #380, and proposed almost exactly what shipped here: *"Replace per-chain prose blocks with a
compact decision index (ADR number + one-line status + link)."* It was deferred as *"requires
editorial judgment on desired structure"*.

Its diagnosis was the same one #380 inherited — *"duplicates ADR abstracts with copy-paste drift
risk"* — and it is the wrong half. The blocks do not duplicate the abstracts (measured above), and
**it is the wrong diagnosis that made the remedy look safe**: an index replacing a duplicate loses
nothing, an index replacing an original loses the original. Two independent findings, the same
correct remedy, the same incorrect reason, and neither shipped until the reason was checked.

### Three mechanisms were checked against the live docs before designing

`code.claude.com/docs/en/memory`, read 2026-08-13:

| mechanism | when it loads | verdict |
|---|---|---|
| `@path` import | at launch, expanded | *"imported files still load and enter the context window at launch"*, and *"doesn't reduce context"*. Buys nothing |
| `.claude/rules/` without `paths:` | at launch | *"loaded unconditionally"*. Same |
| `.claude/rules/` with `paths:` | on matching file reads | already rejected by #380: ADR summaries are not domain-scoped, and this project has no `.claude/rules/` |
| skill | on invocation only | the one genuinely lazy mechanism, and over-engineered for a ~2k-token index |

### Found while reading the producer, not in the issue

`concept-to-code/SKILL.md` carried a line-count guard warning above **180** lines and recommending
`claude-md-slim`. The file was 3,895 lines, so it fired on **every run for months**, and its remedy
is the one #380 rejected with a measured 3.0% yield on this exact file. A warning that always fires
and points at a dead remedy is the cry-wolf shape ADR-0102 removed from Gate 2b.

**It existed twice** — Step 3 Branch A and the §5 Gate 3 block — with the same threshold and the
same dead remedy. Found by `CMC11` going red after only the first was corrected, which is the
assertion doing its job rather than a false positive.

### Re-growth is faster than the issue states

The last six features added **55, 55, 49, 76, 61 and 56** lines — ~58 lines ≈ 1,100 tokens each,
not the 39-line historical mean, because recent blocks are longer. A file condensed to ~250 lines
**doubles in four features**. The producer change is not an accessory to this work; it is what
decides whether the work lasts.

## Decision

### D1 — Three artefacts replace one

- **`docs/chain-decisions.md`** — all 95 narrative blocks, moved **verbatim** (`diff` against the
  original range is empty). Costs nothing at launch, is greppable, and needs no version-dependent
  runtime behaviour.
- **`CLAUDE.md`** — the existing 80 base lines byte-unchanged, plus `## Rules` and
  `## Chain decision index`. 3,895 → **257 lines**, ~74,966 → **~6,984 tokens (−91%)**.
- **`concept-to-code/SKILL.md` Step 3 Branch A** — the producer, rewritten.

### D2 — The archive is a file, not an HTML comment

Block-level HTML comments in `CLAUDE.md` are documented as stripped before injection and visible to
`Read`, so the blocks could have stayed in the file at zero token cost. Rejected: it makes the
condensation depend on a runtime behaviour that can change with no signal, and if it changed the
file silently returns to ~75,000 tokens per turn. ADR-0016's v2.1.154 experience is the precedent —
the substrate moves. A plain documentation file has no such dependency.

### D3 — The archive is a historical record and is not corrected in place

Its header says so. A count inside a block is a correct snapshot of the day it was written, and
several are stale today — including the six false numeric claims recorded on #380. Rewriting 95
historical blocks falsifies the record for no consumer (ADR-0034, applied again by ADR-0075 and
ADR-0078). The new rule is that **`CLAUDE.md` itself carries no bare count**, which the split
achieves as a side effect: every count left the file with the narrative.

### D4 — The Rules section is hand-curated, and says so

Seventeen invariants, each with the one-clause reason and the establishing ADR. The reason is not
optional: #380 is right that the narratives are what make a rule persuasive rather than a slogan,
so the counterexample travels with the rule in one clause and the full account stays one `Read`
away in the archive.

The list is hand-curated because premise 2 above makes it unavoidable, and the section declares
that in its own text rather than letting a reader take it as exhaustive. `CMC12` asserts the
declaration is present.

### D5 — What is verified, and what is not

Mechanical, and these are #380's DoD:

1. **No line lost.** `content-union-check.sh <original> CLAUDE.md docs/chain-decisions.md` — the
   whole-line union semantics of ADR-0032, reused unchanged because its interface is literally
   `<original> <output1> [<output2>…]`. Run at implementation: **rc=0**. Proven able to fail in
   both directions — archive alone `rc=1, 62 lines missing`; new `CLAUDE.md` alone `rc=1, 3,322
   lines missing`. A silent pass is not evidence that a check ran.
2. **Every Rules entry cites an ADR that exists on disk** (`CMC02`), count-guarded (`CMC03`).
3. **Every index entry points at a file that exists** (`CMC04`), count-guarded (`CMC06`).
4. **Index entries == archive blocks** (`CMC05`) — the producer appends one of each, so a
   difference means one of the two writes was skipped.
5. **`CLAUDE.md` under a 400-line ceiling** (`CMC01`), and carries no narrative block (`CMC07`).
6. **Producer assertions** (`CMC09`, `CMC10`, `CMC11`), matched flattened, undecorated and
   case-insensitive.

**Not verifiable, stated rather than implied:** *every rule worth promoting was promoted*. Check 1
guarantees nothing was **lost**; it cannot guarantee everything worth promoting was **promoted**.

**Not yet measured, and #380 asks for it explicitly.** Its DoD says *"re-measure the orchestrator
initial context after the change; the claim is falsifiable and should be falsified if it does not
hold."* The file-level delta is measured above and is a fact: 299,866 → 27,937 bytes. The
**session-level** figure is not, because the initial context is assembled at session start and this
work happened inside a session that had already loaded the old file. The confirmation is one
`/context` in the next session, compared against #380's measured median of 74,196 tokens of which
`CLAUDE.md` was ~89%. If that number does not move by roughly the file delta, this ADR is wrong
about its own effect and should be corrected forward.

### D6 — The producer writes one index line always, and a Rules line only sometimes

- narrative block → `docs/chain-decisions.md`, **never** `CLAUDE.md`
- index line → `CLAUDE.md`, **always**
- Rules line → `CLAUDE.md`, **only when the ADR establishes an invariant not already listed**

The conditional half is the one that matters. An unconditional Rules line reintroduces exactly the
restatement #380 measured at over two hundred occurrences, one feature at a time.

**The archive's existence is the switch.** If `<project-root>/docs/chain-decisions.md` does not
exist, the producer appends to `CLAUDE.md` exactly as before. No project that has not adopted the
split is changed by this.

### D7b — Three existing harnesses asserted into the narrative blocks, and are repointed

Found by running the suite, not by reading it. `cross-reference-form.test.sh` `R1`,
`skill-fence-positional-tokens.test.sh` `SFP11` and `worktree-isolation-contract.test.sh` `J6` all
reached into `CLAUDE.md` for content that now lives in the archive.

Each is repointed, not relaxed — the needles are byte-identical:

- **`SFP11` and `J6`** read the archive first and fall back to `CLAUDE.md`, because a project that
  has not adopted the split still appends there (§D6). An OR over two files cannot be driven red by
  mutating one arm, so neither carries a plant; both say so at the site.
- **`R1` is answered differently, and deliberately.** Its message is *"the rule is enforced but
  unwritten"*, so its intent is that the rule be written **where it is read**. The `xref-exempt`
  marker's syntax moves into Rules entry 12 rather than the assertion moving to the archive. It is
  now in the always-loaded part of the file instead of buried in the 48th of 95 blocks, which is
  what `R1` wanted in the first place.

### D7 — The ceiling guard is repaired, and defined once

400 lines, a ceiling this file can actually meet, with a message naming the two real causes
(something other than an index line is being appended; near-duplicates in Rules). The §5 Gate 3
copy is replaced by a reference to the Step 3 definition — ADR-0086's criterion, since the two were
one question with two answers and had already diverged.

## Alternatives considered

- **Delete the narrative**, #380's literal proposal. Rejected on the measurement in §Context: it
  loses content that exists nowhere else.
- **`claude-md-slim` / path-scoped rules.** Rejected by #380 with a measured 3.0% yield, and
  re-confirmed here: ADR summaries are not domain-scoped, so there is no `paths:` glob that would
  load one when it is relevant.
- **`@path` imports.** Docs-verified as eager; they buy organisation, not context.
- **A skill holding the index.** The only truly lazy mechanism, and disproportionate for ~2k
  tokens. Worth revisiting only if the index itself becomes large.
- **Merging each block into its own ADR.** Rejected on ADR-0034: it rewrites 95 historical records,
  and the eleven cross-ADR syntheses have no single ADR to merge into.

## Consequences

### Positive

- ~68,000 fewer tokens in every orchestrator turn and after every `/compact`; on #380's own
  measurement that is ~20% of the orchestrator's cache-read volume.
- Each rule is now stated once, at the top, instead of buried in the 47th of 95 blocks. Chroma's
  *Context Rot* finding — Claude shows the largest focused-vs-full gap of the families tested, and
  fails by omission rather than invention — predicts this is a quality improvement, not merely a
  cheaper one. That prediction is not measured here and should not be reported as if it were.
- The six false numeric claims recorded on #380 leave `CLAUDE.md` with the narrative and land in a
  file that declares itself a historical record, where a stale count is legitimate.

### Negative

- **The archive is not loaded, so the model must choose to `Read` it.** The Rules section and the
  index both point at it, but a lesson nobody opens is a lesson nobody applies. This is the real
  cost of the change and it is not mitigated by anything mechanical.
- **Nothing verifies that every rule was promoted.** A rule that lived only in a narrative block
  and was not curated into `## Rules` is now one `Read` further away than it was.
- The Rules list is hand-maintained; a future feature adding a near-duplicate is caught by nothing
  but `CMC01`'s ceiling, and only in aggregate.
- **`CMC01`–`CMC07` and `CMC12` carry no declared plant.** They read `CLAUDE.md` at the repo root
  and `plant-check.sh` sandboxes only `staging/` and `docs/`, so a root file is unplantable by
  construction — the limit ADR-0122 recorded for `.github/workflows/` and ADR-0118 for
  `.gitignore`. Eight of thirteen assertions here are therefore unmutated.

### Neutral

- The union check is run at implementation time and is not re-runnable from the harness: the
  original exists only in git history. `CMC05` and `CMC07` are the standing proxies.
- `claude-md-slim` is untouched and still correct for the projects it was designed for; what is
  retired is the recommendation to run it on **this** file.
- Instance number for the derived-guard pattern: not claimed. This harness derives populations and
  count-guards them, but declares no waiver mechanism, so it is not an instance of the pattern
  ADR-0086 governs.

## References

- Issue #380, and its 2026-08-12 comment recording the six false numeric claims and the
  *Context Rot* evidence.
- `code.claude.com/docs/en/memory` — import eagerness, rules loading, skills as the lazy mechanism.
- Chroma, *Context Rot* — <https://www.trychroma.com/research/context-rot>. Diagnostic, not
  prescriptive: it publishes no token threshold and none is inferred here.
- `staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh` — reused unchanged.
- `staging/plugin/scripts/tests/claude-md-condensation.test.sh` — the harness.
