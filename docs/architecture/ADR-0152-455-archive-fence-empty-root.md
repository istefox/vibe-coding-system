# ADR-0152 — the archive fence looks for the file before it validates the slug (issue #455)

- **Date:** 2026-08-17
- **Issue:** #455 — "the Step 1 archive fence is documented as a no-op on an empty root and is a halt"
- **Supersedes:** nothing. **Amends:** ADR-0096 (its guard order in `spec-archive.sh`, and one
  sentence in its Consequences, corrected forward under rule 14).

## Status

Accepted.

## Context

ADR-0096 put an archive fence in front of `concept-to-code` Step 1's greenfield dispatch, because
the root `SPEC.md` is a single mutable slot and `interview-driver` writes straight into it. The
fence is documented in two places as running on both greenfield states and being **a no-op on the
genuinely-empty one**.

It was a halt. On a root with no `SPEC.md`, `gate0-detect.sh` reports `spec_topic_slug=unknown`, the
fence passes `${OUT_SLUG:-unknown}` through, and `spec-archive.sh` refused an empty-or-`unknown`
slug *before* it ever looked for a file:

```
spec-archive.sh <empty-root> unknown          → rc 3   "refusing to name an archive"
spec-archive.sh <empty-root> 111-alpha-topic  → rc 0   NOSPEC
```

The caller's contract on rc 3 is HALT — correct as a contract, since a check that could not run is
not a check that found nothing. Wrong as an outcome here: there was genuinely nothing to archive and
the script never got far enough to discover that. The blast radius is the bootstrap path, a
brand-new project with an empty root, which is the case Gate 0d's whole scaffolding survey exists to
serve.

This is rule 17's shape. Both producers are individually defensible — a detector that reports
`unknown` when it cannot name a topic, a writer that refuses to invent an archive name — and nothing
checked that they meet.

### Measured before designing, and two of the issue's premises did not survive

**The two states ARE distinguishable, so `gate0-detect.sh` is not touched.** The issue's R-02 says
they are not. `spec_owned` is `no` only when the file is absent, so `mode` separates them:

| state | `mode` | `spec_topic_match` | `spec_topic_slug` |
|---|---|---|---|
| no `SPEC.md` | `greenfield` | `unknown` | `unknown` |
| `SPEC.md`, no marker | `brownfield` | `unknown` | `unknown` |
| `SPEC.md`, foreign marker | `greenfield` | `false` | `<the slug>` |

Neither field distinguishes alone; the pair `mode` + `spec_topic_slug` does, uniquely. R-02 closes
with an assertion (`SA9c`) over output that already exists. This also keeps #455 clear of #454,
which is a different consumer of the same token.

**The fence can see exactly two pairs, and one of them was untested.** It runs on the greenfield
branch only, so:

- `(no SPEC.md, unknown)` — the only way to be greenfield with no file. **This is the halt, and no
  assertion covered it.**
- `(SPEC.md present, valid slug)` — the foreign marker, covered by SA2/SA3/SA4.

`(SPEC.md present, unknown)` is the markerless SPEC, which routes to brownfield and never reaches
the script. That is `SA5`, deliberate defence-in-depth, and the script's own comment says so. But
`SA1` is then *also* an unproducible pair — `(no SPEC.md, 111-alpha-topic)` — and unlike SA5 it did
not declare itself as one. **A green assertion over an input the caller cannot generate is not
coverage of that caller**, and here it was the thing that made the empty-root case look tested for
two months.

**Zero live instances.** 60 manifests, 13 `greenfield`. Twelve have a root `SPEC.md` present in the
tree at their date and one predates the first commit on `main`. `SPEC.md` was archived out of the
slot on 2026-07-30 at 14:44 and rewritten at 22:37, but that day's greenfield chain started at
14:09, before the deletion, and the fence did not exist yet — it landed on 2026-07-31 at 15:38
(`61a84e9`). **The fence has never met an empty root.** The defect is latent, reachable, and invisible
to this repository by construction, because its root slot is never empty.

## Decision

### D1 — split the guard, and keep the shape check above the existence check

`spec-archive.sh` held two unrelated refusals in one `case`. They are now two, with the existence
check between them:

```
1. arg count                       → 3
2. [ -d "$root" ]                  → 3
3. slug SHAPE guard  (*/*|.*|-*)   → 3
4. [ -f "$spec" ] → NOSPEC, exit 0
5. slug EMPTY/UNKNOWN guard        → 3
6. …content compare, collision, copy
```

The order in step 3 is the part that is easy to get wrong in the other direction. Sinking the whole
`case` below the existence check would also make `spec-archive.sh <empty-root> ../../etc/passwd`
return `NOSPEC`/0, turning a malformed call into a silent success. The split preserves every refusal
the script makes today and changes exactly the one that was wrong. `SA17` pins that half.

Nothing can be written under a name nobody chose by this reorder: with the file absent the script
writes nothing under any name, and the slug guard still fires on `(present, unknown)` — `SA5`.

The comment at the slug guard was rewritten rather than kept. It claimed that `unknown` reaching the
script means the caller is confused, which is now false for one of its two producers.

### D2 — SF5 and SA16 are the same claim at two levels, and carry two plants

`SA16` asserts the script; `SF5` runs the fence body extracted from `SKILL.md` by its
`fence-contract` marker, so it is the orchestrator's own code receiving the orchestrator's own pair.
They get different plants on purpose: SA16's removes the mechanism (the existence check), SF5's
removes the wiring (the fence's argument passing). One shared plant would have left SF5 unproven as
an independent claim about `SKILL.md`.

### D3 — SA14b pins prose, and the ADR says so

The corrected sentence in `SKILL.md` now names the ordering it depends on instead of only its
outcome, and `SA14b` matches that clause on the flattened branch text (rule 3). **This is an
instruction, not an enforcement** (rule 16): it cannot make the guard order correct — SA16 and SF5
do that — it only stops the sentence quietly reverting to the short form that was false. Its plant
says the same thing at the declaration.

### D4 — no `R-NN` tokens in the new test comments

`spec-coverage.sh` matches a bare `R-01` on word boundaries, and its repo-wide fallback would let
this file satisfy a stranger SPEC's requirement id (rule 18, ADR-0138). The issue's criteria are
referred to in words instead. There is no SPEC for #455 in the corpus, so nothing is owed the
coverage gate either way.

## Consequences

- A chain can be started in a repository with no root `SPEC.md`. Step 1's fence reports `NOSPEC` and
  proceeds, which is what its documentation has claimed since 2026-07-31.
- `spec-archive.test.sh` goes from 23 to 28 assertions, 5 of them planted; the file previously
  declared one plant. Z1's floor stays at 20 as a vacuity guard (rule 10).
- `SA1` and `SA5` keep their verdicts and gain comments recording that both describe pairs the
  orchestrator cannot produce. Neither was removed: defence-in-depth over a guard is worth having,
  and what was wrong was reading them as coverage of the caller.
- The fix lands in `staging/`. A live chain runs the copy under `~/.claude/`, so it is not in effect
  on this machine until `staging/sync-to-claude.sh --apply` is run — a separate, operator-owned step.

## References

- Issue #455; ADR-0096 (the fence), ADR-0106 (the other `spec-archive.sh` caller, Step 7.0b,
  unaffected: a completed chain always has both a SPEC and a real slug).
- CLAUDE.md rule 13 (measure the premise), rule 16 (an instruction is not an enforcement),
  rule 17 (a producer and a consumer need something checking they meet), rule 18 (scope).
- ADR-0138 for the requirement-id scope rule behind D4.
