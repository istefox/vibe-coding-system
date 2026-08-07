# SPEC — Scope and bound the autopilot run

**Topic slug:** 365-scope-and-bound-the-autopilot-run

Source: GitHub issue #365, plus the decision comment of 2026-08-06 on that issue and
`PROJECT.md` Phase 11 Wave 1, which is the authoritative scope.

## Objectives

1. Give `autopilot` a real bound: `--features N` and `--only <token>[,<token>]`, plus an optional
   durable `scope:` block in `.claude/autopilot.yml`. Today the skill takes **no arguments**, so a
   launch attempts every unchecked row of `PROJECT.md` — 33 of them at the time of writing — and
   the only brakes are the `/goal` turn budget and a human hand.
2. Remove `token-budget` outright rather than wiring it, and correct the two places that assert
   producers exist for it and for `rtf-blocker`.
3. Restate the RUNBOOK turn budget as what it now is — a fail-safe for a run that hangs, not the
   primary bound — sized from a measurement that carries its own sample size.

## Non-objectives

- **No spend ceiling.** Removing `token-budget` removes the only mechanism that gestured at one.
  Accepted deliberately; see *Decisions carried in* below.
- **No change to what a feature does.** This feature bounds *how many* features a run attempts. It
  does not touch `concept-to-code`, the per-feature gates, or the publish mechanics.
- **No two-feature validation run.** That is Phase 11 Wave 2 and measures more than this feature.
  See *Success criteria* R-11 for what stands in for it here.
- **No fix for the unattended review gap** found while writing this SPEC (see *Findings recorded,
  not fixed*).

## Decisions carried in (settled before the interview, not re-opened)

**The bound is `--features N` / `--only`, and `token-budget` is removed.** Three findings, and only
the third settles it:

1. The producer ADR-0127 Part 4 proposed cannot produce what the consumer reads. It accumulates
   `spent=` from `step5-report.json`'s `task_metrics`, citing ADR-0064 — whose four fields are
   `test_count_delta`, `deleted_lines`, `iteration_count` and `elapsed_wall_seconds`. No token
   count appears in any of them.
2. That block does not exist anyway. The only real `step5-report.json` on disk carries no
   `task_metrics` at all; `agent-metrics.test.sh` GA1/GA2 assert the field name appears in the
   **schema block inside SKILL.md**, never that a produced report contains it.
3. The halt is structurally unable to do its job. `autopilot-guard.sh` is a `PreToolUse` hook on
   `git push` / `gh pr create`, so it gets a turn only at publish — once per feature, at the end.
   A ceiling evaluated afterwards **cannot stop the feature that exceeds it, only the one after**.
   That is cumulative drift, which `--features N` already bounds deterministically.

**If a spend ceiling is ever wanted it does not come from `task_metrics`.** The only place in this
system that knows about tokens is the transcript — `usage-report.py` and `context-occupancy.sh`
read `input_tokens`, `output_tokens` and `cache_*` from it. Any future bound starts there, is
per-session rather than per-feature, and still cannot stop a feature already in flight.

## Scope

Four files carry the change, plus the RUNBOOK:

| file | what changes |
|---|---|
| `staging/plugin/skills/autopilot/SKILL.md` | argument parsing, scope resolution, a new Phase before the roadmap starts, the `token-budget` claim removed, the `rtf-blocker` claim corrected, report schema |
| `staging/plugin/skills/project-conductor/SKILL.md` | the feature-selection loop consumes the resolved scope; the publish path increments the delivered count |
| `staging/plugin/scripts/autopilot-guard.sh` | the `token-budget` read removed |
| `staging/plugin/scripts/autopilot-disarm.sh` | `token-budget` leaves the cleared set; the new scope file joins it |
| `docs/RUNBOOK-autopilot.md` | turn budget restated |

## Architecture

### Where the count lives

`project-conductor` owns the loop — it is what finds the first `- [ ]` line and advances. So the
resolved scope has to be readable by the conductor **at every re-invocation**, not resolved once in
the runner's memory.

It travels as a **file**, `<root>/.claude/autopilot-state/scope`, on exactly the terms
`autopilot-state/published` already established (issue #364, ADR-0127 §D4): run-scoped, written by
the runner, read by the conductor through a declared fence, and cleared by `autopilot-disarm.sh`.
The symmetry is worth stating: that file joins the disarm's cleared set on the same commit that
`token-budget` leaves it.

The alternative — an argument threaded through every `Skill(skill="project-conductor", …)`
invocation — is rejected on the failure mode rather than on elegance: a call site that forgets to
re-pass it loses the scope **silently**, which is the producer/consumer class this repository has
now recorded three times (#173, #248, #319).

### What consumes a slot

**A publish.** A feature that is skipped for a known contained reason — a thin issue, an unmet
external dependency, an entry-state token the conductor cannot route — produces no PR and consumes
no slot. `--features 2` therefore promises *two PRs or an exhausted roadmap*, not *two rows
examined*.

Stated cost: on a roadmap that skips heavily the run lasts longer than the number suggests. The
alternative — counting attempts — is predictable in cost and can deliver zero PRs while reporting
success, which reads as a broken runner.

### What happens when the slots run out

**The first unreached feature stays `- [ ]` and the run ends.** No marker, no `skipped-features`
entry, nothing to undo.

**This corrects ADR-0127 Part 4 R-04**, which says the run "marks the next feature `[~]` and
appends to `skipped-features` — a contained skip". Measured: `project-conductor` Step 2 finds the
first `- [ ]` line, so `[~]` is invisible to it **permanently**. Under the ADR's text every bounded
run would leave behind a feature no later run picks up without a human editing the roadmap by hand.

The framing was inherited from a token bound, which *can* be reached mid-feature. A feature count
cannot: it is checked between features, so the next one is simply never started, and there is
nothing to skip.

### `--only` resolution

The roadmap line is `- [ ] <title>  (issue #N)`. `--only` accepts, in order:

1. **An issue number** (`--only 293,294`) — the primary form. The number is already on the roadmap
   line, it is what a human reads on GitHub, and it is the same source `publish-feature.sh --issue`
   was just made authoritative for (issue #370, ADR-0128).
2. **A full topic-slug** — for roadmaps written by hand, which carry no `(issue #N)` marker.

A token that resolves as neither **aborts in Phase 0 pre-flight, naming the token**, before
anything is written. On an unattended runner a typo costs a whole night; failing fast and loudly is
the safe direction and is what the other pre-flight checks already do.

### Marker versus arguments

`.claude/autopilot.yml` may carry a `scope:` block as a durable default. **Passing any scoping
argument discards the whole block**, and the run prints one line saying which source is in effect.

Per-key override is rejected on a concrete failure: a `only:` list left in the marker from last
week survives a `--features 2` that meant something else entirely, and the operator gets one
feature instead of two with nothing on screen explaining why. One source at a time, never a
combination nobody wrote.

### `token-budget` and `rtf-blocker`

`token-budget` is removed from all three sites: the read in `autopilot-guard.sh`, the clear in
`autopilot-disarm.sh`, and the claim in `autopilot/SKILL.md`.

**`rtf-blocker` keeps its mechanism** — the guard's read and the disarm's clear both stay. What
changes is the sentence: `autopilot/SKILL.md` currently states that `rtf-blocker` and
`token-budget` are *"written by the review step and this skill's `/goal` overlay respectively"*.
Neither is. The file will instead state that `rtf-blocker` is deliberately unproduced, **and why**,
which is a measured reason rather than a deferral:

> `concept-to-code` Gate 5's autopilot default is "Skip review", and `project-conductor` invokes
> `concept-to-code` for every feature on both branches — never `autopilot-build`. So no review
> cycle runs during an unattended roadmap run, and a producer inside `review-triage-fix` could
> never fire on the one path where the guard that reads this file exists.

`token-budget`'s verdict is deliberately **not** transferred to `rtf-blocker`: that halt was
structurally unable to work, this one would work correctly the moment something wrote it.

### Turn budget

The RUNBOOK's `stop after 200 turns` was written for 13 features at ~15 turns each. Measured: a
full standard chain costs roughly **50 orchestrator turns**, n=1, and a 110-turn budget delivered
one feature.

The RUNBOOK restates it as `stop after N × 60 turns`, with the reasoning beside the number: 60
comes from a single measurement of ~50 plus margin; the budget is now a **fail-safe for a run that
hangs**, not the bound; and the report records actual per-feature turns so the figure is
re-derived rather than re-estimated. A bare corrected number would repeat the error that
caused #365 — a figure with no reasoning next to it ages and nobody knows why it was that.

### Report

The morning report gains an additive `scope` block: what was requested (`features`, `only`, and
which source it came from), what was delivered, how many rows remain in the roadmap, and actual
turns per feature. Additive, on the same terms as every prior extension of that schema, no version
bump.

**Its durability is a known gap, not this feature's to close:** `.claude/autopilot-report.json` is
gitignored, so the figure survives only on the machine that produced it. That is Phase 11 Wave 5,
and Wave 1's "re-derive rather than re-estimate" depends on it.

## Edge cases

- **`--features N` where N exceeds the roadmap.** Not an error: the run exhausts the roadmap and
  reports `delivered < requested` with `remaining_in_roadmap: 0`.
- **`--features 0` or a non-numeric N.** Abort in pre-flight, naming the value. A zero-feature run
  is a request nobody means.
- **`--only` naming a feature already `[x]`.** The token resolves against roadmap rows regardless
  of checkbox state, so it resolves — and then the conductor never selects it, because Step 2 only
  considers `- [ ]`. The run ends having delivered nothing, with `delivered: 0` and the resolved
  list in the report. Deliberate: an already-done feature is not a typo, and aborting would be
  wrong.
- **A stale `scope` file from a dead run.** Accepted risk, same exposure `published` already
  carries and mitigated the same way: `autopilot-disarm.sh` clears it. A session-marked file was
  considered and not taken. This is ADR-0112's stale-marker class, recorded rather than solved.
- **Both `--features` and `--only` passed.** `--only` names the candidate set, `--features` caps
  how many of them publish. They compose; neither is ignored.
- **`scope:` block present but empty or malformed.** Abort in pre-flight naming the block — a
  malformed bound must not read as an absent one.

## Success criteria

- [ ] R-01 — `autopilot` accepts `--features N` and `--only <token>[,<token>]`, and the mechanism
  that honours them lives in the runner and the conductor, never in prose.
- [ ] R-02 — `.claude/autopilot.yml` may carry a `scope:` block; passing any scoping argument
  discards that block whole, and the run prints which source is in effect.
- [ ] R-03 — a slot is consumed when a feature publishes, never when one is merely attempted; a
  contained skip does not decrement the remaining count.
- [ ] R-04 — a run that exhausts its slots leaves the first unreached feature as `- [ ]`, writes no
  `[~]` marker and no `skipped-features` entry, and ends. ADR-0127 Part 4 R-04 is superseded, and
  the reason is recorded where the old text was.
- [ ] R-05 — `--only` resolves an issue number or a full topic-slug; a token that resolves as
  neither aborts in Phase 0 pre-flight naming the token, before anything is written.
- [ ] R-06 — the resolved scope reaches the conductor through `<root>/.claude/autopilot-state/scope`
  and is cleared by `autopilot-disarm.sh`, on the same terms as `published`.
- [ ] R-07 — `token-budget` is removed from `autopilot-guard.sh`, from `autopilot-disarm.sh` and
  from `autopilot/SKILL.md`, with no remaining reference asserting it has a producer.
- [ ] R-08 — `autopilot/SKILL.md` states that `rtf-blocker` is deliberately unproduced and names
  the measured reason (no review cycle runs unattended); its read in the guard and its clear in the
  disarm are unchanged.
- [ ] R-09 — the morning report carries an additive `scope` block with requested, source, delivered,
  remaining, and per-feature turns.
- [ ] R-10 — `docs/RUNBOOK-autopilot.md` states the turn budget as `N × 60` with its sample size,
  its role as a fail-safe rather than the bound, and the instruction to re-derive it from the
  report.
- [ ] R-11 — a `--dry-run` resolves the scope, prints the exact feature list the run would drive
  and its source, and exits without arming the guard or touching the roadmap.

## Definition of done

R-01 through R-11 green, each with a declared plant, plus every abort-capable fence declared and
executed by a test (ADR-0083). The `--dry-run` of R-11 is what stands in for a real run here: it
proves the resolution is right without spending a roadmap.

**The real validation is Phase 11 Wave 2** — a scoped run delivering two independent PRs, each
forked from the prep branch, each based on `main`, with the conductor never re-picking feature 1.
That is a separate item because it also measures the fork point, the publish path and the ledger,
none of which this feature touches.

## Findings recorded, not fixed

Both were measured while writing this SPEC and belong to `PROJECT.md` Phase 11, not here:

1. **No unattended run performs a review.** `concept-to-code` Gate 5's autopilot default is "Skip
   review" and `project-conductor` invokes `concept-to-code` for every feature on both branches.
   Every PR an unattended roadmap opens has passed no review cycle. This is the reason `rtf-blocker`
   has no producer, and it is a larger question than the marker it explains.
2. **An unmarked leftover `SPEC.md` is mishandled in both directions.** `gate0-detect.sh` reports
   `spec_topic_match=unknown` when the root SPEC carries no `**Topic slug:**` marker, and `unknown`
   routes **brownfield** — so the chain silently adopts another feature's SPEC. On the greenfield
   branch the same missing marker makes Step 1's archive fence exit 3, which **halts the chain**.
   One missing marker, two wrong outcomes. Observed on this very chain: the root SPEC held issue
   #292's, byte-identical to its own archive.
3. **The Step 1 slug stamp skips itself on any SPEC that mentions the marker in prose.** Its
   idempotence guard is an unanchored `grep -q` for the marker string, so a SPEC discussing the
   marker — finding 2 above, four lines up — satisfies it and the stamp never runs. Observed on this
   file: it was written without its own marker for exactly that reason, and the marker had to be
   added by hand. Rule 12, in the chain's own machinery: the needle matched the prose describing the
   mechanism rather than the mechanism. The fix is a column-anchored `^\*\*Topic slug:\*\*`, which
   prose cannot satisfy because prose indents or quotes it. The consequence compounds with finding 2
   — a SPEC that skips its own stamp is the next chain's unmarked leftover.
