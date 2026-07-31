# ADR-0108 — The plants worked; nothing made them durable

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #284
- **Related:** ADR-0090 (inspect what the plant produced), ADR-0099 (a plant needle must be
  wrap-insensitive), ADR-0104 (an assertion covered by two guards isolates neither), ADR-0086 (why
  a shared helper was refused), ADR-0085 (guard the denominator)

## Context

Rule 12 — *a scan whose needle is a literal counts itself* — bit **five times in one day**: `SA10`,
`N9`, `GR1`, `GR5`, `SP1`. Each was an assertion whose needle was the **name** of the thing it
asserted about, matching a file that legitimately names it while explaining it.

Every one was caught the same way: plant a defect, watch the assertion fail to fail. **The plants
worked. Nothing made them durable** — a plant is typed into a shell, watched, and thrown away, and
the next reader cannot tell a pinned assertion from a decorative one.

## What the measurement ruled out

Three root fixes were measured before one was chosen.

- **A static detector on multi-match needles** flags **77 of 181** statically resolvable assertions
  (43%), dominated by legitimate cross-references. And only **181 of 543** assertions are
  statically resolvable at all — a 67% blind spot on top of a 43% false-positive rate.
- **A code-only projection** catches **4 of the 5**. `N9` matched inside `ok`/`bad` **message
  strings**, which is code and not commentary, so the projection misses the sneakiest of them. It
  also collides with ADR-0086: a shared helper breaks 67 hermetic files, and duplicating it 67
  times is what that ADR refused.
- **What distinguishes a rule-12 defect is behavioural**: the assertion still passes when the
  mechanism is removed. That is mutation testing and nothing else.

## Decision

### D1 — The plant is declared beside its assertion and executed by the harness

```text
# plant: <assertion-id> | <path-relative-to-staging> | <needle> | <replacement>
```

ADR-0077's principle: a waiver travels with the file it excuses, and so does a plant.

### D2 — Three properties of the runner, each earned by a past failure

- **The needle's words are joined on `\s+`**, so a clause that wraps is still matched. ADR-0099's
  lesson, put into the mechanism rather than left to the author's memory.
- **Exactly one match is required.** Zero means the needle rotted; more than one means the plant
  hits sites it did not intend. Both are defects in the **plant**, and both happened the day this
  was designed (ADR-0099 `P4`/`P5`, ADR-0104 `P2`). A plant nobody validated is worth as much as an
  assertion nobody planted.
- **Each plant runs against an isolated `cp -R`** of `staging/` and `docs/` — measured at 0.21s — so
  nothing here can touch the real tree. Tests resolve their root from `$(dirname "$0")`, so a copied
  tree redirects with no change to any test.

### D3 — Scope is the plants already run, not a sweep

Fifteen plants across twelve test files, all from this session, whose outcomes were recorded in
ADRs 0095-0106. **No retroactive sweep of the other 543 assertions** — the convention becomes
available for new ones, and existing assertions gain plants when they are next touched.

### D4 — Replacement only, in v1

A plant substitutes; it cannot insert. Two of this session's plants were insertions (restoring a
deleted pair, restoring a `VALID_STEPS` entry) and are not expressible. Named as a limit rather than
worked around, because the substitution form covers removing or altering a mechanism, which is what
a rule-12 defect is tested with.

## Verification

**The registry found a real defect on its first run**, which is the whole argument for it existing.

14 of 15 plants fired. **`TP6` did not.** `transition-producer.test.sh`'s `TP6` checked that Step 5's
pre-flight region contains a transition-ish word *and* the string `step_5_implementation` — and the
prose introducing the block satisfies both on its own ("Step 5.0.5 — enter `step_5_implementation`",
"the chain's only unconditional producer of that state"). Replacing the actual `bash
…manifest-transition.sh` call with `true` left it green.

**Rule 12's sixth instance, caught by the mechanism built for the first five**, on a file written
earlier the same day and reviewed twice. `TP6` now requires the invocation line.

The plan for this work called for manufacturing a deliberately weak assertion to prove the runner
reports a non-firing plant. **That fixture was not needed**: the runner did it live, on a real
assertion, and `PC1` named it. Live evidence beats a synthetic case built to pass.

20 assertions in `plant-check.sh`. Runtime 12s for 15 plants. Harness 67/67 plus the registry.

## Consequences

- **CI gains a step that re-runs other harnesses against mutated copies.** A failure there means an
  assertion pins nothing — a different signal from a harness going red, and the step is separate so
  the two are not confused.
- **~0.8s per plant.** At 100 plants that is 80s, which would want its own job. Recorded so the
  scaling question is asked before it hurts rather than after.
- **A plant can rot silently in one direction only.** If the needle stops matching, `PC2` fails
  loudly; if the assertion id is renamed, `PC1` reports it as not firing. Neither is quiet.
- **The registry is itself an assertion corpus with no plants of its own.** `PC0`/`PC3` guard its
  denominator, but nothing plants a defect in `plant-check.sh`. Stated rather than solved — the
  regress has to stop somewhere, and it stops one level higher than it did yesterday.
- Twelve test files gain a comment block. No skill file changed, so nothing to deploy.
