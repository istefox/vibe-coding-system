# ADR-0130 — Agent effort recalibration: coder and tester to `xhigh`

- **Status:** Accepted
- **Date:** 2026-08-06
- **Supersedes:** the ADR-0016 addendum of 2026-07-25 **in part** — only the `coder` and `tester`
  rows of its per-agent effort calibration. Every other row, and the addendum's whole argument for
  why effort must be pinned rather than inherited, stands unchanged.

## Context

The question asked was whether to raise the coder's effort or move it to Opus, on the observation
that recent sessions spend more time repairing findings than producing features. It was answered by
measuring rather than by judgement, against this project's own transcripts: 238 sub-agent
transcripts, 42 orchestrator sessions, 49 manifests, 29 recorded reviewer findings.

Three measurements decided it.

### 1. The coder is 3.9% of the bill

| population | cost share |
|---|---:|
| orchestrator (main sessions, Opus) | 89.9% |
| all sub-agents | 10.1% |
| of which `coder` (51 Sonnet runs + 3 Opus) | **3.9%** |

Volumes measured; prices are published tier ratios, so the absolute figures carry medium
confidence and the ratios high.

### 2. Inside a coder run, effort moves 4.7% of the cost and the model moves all of it

| line | share of one run |
|---|---:|
| cache read | 62.2% |
| cache write | 32.6% |
| **output** (where thinking lands) | **4.7%** |
| input | 0.5% |

So `high` → `xhigh` costs about **+4.7% per run in the worst case**, and is cost-*negative* if it
saves even 5% of the turns. A model change multiplies every line by the price ratio, including the
cache-read term that is 62% of it: measured against the three Opus coder runs on record, +321%.

This is also why "Opus at a lower effort" is not a cheaper middle path. The effort dial moves 5% of
the bill; the model dial moves 100% of it.

### 3. The defects were not mostly the coder's, and the agent they point at is the tester

Of the 15 MAJOR/BLOCKER reviewer findings on record, **10 are in SPEC, ADR, plan, `CLAUDE.md`,
`PROJECT.md`, agent frontmatter or `SKILL.md`** and 4 in scripts. The named lessons in `CLAUDE.md`
are dominated by a single class — assertions that pass for the wrong reason, plants that do not
fire, fixtures that are wrong — roughly 12 of 20.

That class is test authoring, which ADR-0049 assigns to the `tester`. The `tester` was the only
operational agent at `medium`, the lowest of the three, while carrying the highest context per turn
of any agent measured:

| agent | model | runs | turns/run | output/run | context/turn |
|---|---|---:|---:|---:|---:|
| `coder` | sonnet-5 | 51 | 93.0 | 21,148 | 150,002 |
| `tester` | sonnet-5 | 36 | 68.6 | 19,952 | **193,114** |
| `reviewer` | sonnet-5 | 18 | 53.2 | 15,868 | 59,452 |

## Decision

**D1. `coder` moves `high` → `xhigh`. `tester` moves `medium` → `xhigh`.**

`xhigh` is the ceiling on this path, and the two halves of that claim have different strength.
ADR-0036 §2.4 cites `code.claude.com/docs/en/model-config` directly — *"'max' and 'ultracode'
levels are restricted to session-only use"* — so the session-only half is documented. That a
`max` sitting in agent frontmatter is therefore **inert** is an inference, and §2.4 marks it *"very
likely"* rather than verified. Nothing has measured it since. `xhigh` is chosen because it is the
highest value known to work in a file, not because `max` is known to fail.

**D2. Neither agent changes model.** Not because Opus would not help, but because the measurement
puts the defect density upstream of the coder, and the same spend buys more elsewhere (see D4).

**D3. The change is stated in five places that are not linked to each other**, which is the hazard
the ADR-0016 addendum named and this ADR inherits: the two agent frontmatter files, the effort
table in `concept-to-code/SKILL.md`, the Stage 1 tester pin in the same file, the Step 6
`FIX_EFFORT` map, and the prose restatement in `CLAUDE.md`.

Only one of those disagreements is caught mechanically. `step6-effort-pin.test.sh` **C3** derives
the expected values from the agent frontmatter at run time and compares them against the
`FIX_EFFORT` literal. It was verified live in the failing direction for this change: reverting
`coder.md` alone produces `FAIL: C3: FIX_EFFORT disagrees with agent frontmatter:
coder(frontmatter=high,skill=xhigh)`. The other three sites are pinned by literal-matching
assertions (`C1`, `TG1`) that had to be updated with the contract rather than derived from it.

**D4. The larger lever is recorded, not taken here.** `CLAUDE.md` is ~66k tokens loaded into every
turn of every agent, about 44% of the coder's 150k-token turn. Roughly 335M of the coder's 763M
cache-read tokens are re-reads of it. That is tracked as ledger entry `VCS-006` and is a bigger
win on cost and on quality than any model choice, because an agent reading 66k tokens of ADR
history per turn is reading mostly material irrelevant to its task.

## Consequences

- **The raise is not scoped to Step 5.** Frontmatter is the only effort lever on the Agent-tool
  path, which takes no `effort` parameter at all (ADR-0068 §D7), and that path is the default while
  `hook_verified` stays `false` — 24 of 49 manifests. So the coder now runs at `xhigh` wherever it
  is dispatched: Step 5, the Step 6 fix cycle, `autopilot-build`, `review-triage-fix` (which pins
  model and deliberately no effort, so it inherits), `deep-refactor`.
- **Inert until sync.** Both agent files carry `PAIRS` entries (ADR-0043), so
  `sync-to-claude.sh --apply` deploys them — but a chain resumed before that sync runs against the
  deployed copies and gets the old values. The `#365` chain paused at Gate 4 is the immediate case.
- **The cost claim is a prediction, not a measurement.** +4.7% worst case assumes thinking tokens
  roughly double and turns do not fall. The falsifiable form: after the next chain, compare
  `turns/run` and `output/run` for both agents against the baselines in the table above. If turns
  do not fall, the change costs about $16 per 51 coder runs and must be judged on defect rate
  alone.
- **The tester jumps two levels, not one.** That is a deliberate choice by the operator over this
  ADR's own recommendation of `high`, taken because the measured defect density sits in exactly the
  artefacts the tester produces. It is the more aggressive half of the change and the one to
  re-examine first if the prediction above fails.
- **No mechanism enforces that a sixth site does not appear.** `C3` covers the `FIX_EFFORT` map
  and nothing else. A future call site that pins an effort literal for either agent will not be
  caught.

## Alternatives rejected

- **`coder` to Opus 5.** +321% on the measured profile, on the 3.9% of spend where the evidence
  says the defects are not. Reconsider with data if the finding rate does not move after D1 and
  `VCS-006`.
- **`tester` to `high` rather than `xhigh`.** This ADR's own recommendation, overridden by the
  operator. Recorded so the two positions are both on file.
- **Leaving `refactorer` at `medium`.** Kept: it is dispatched only by the Step 6 fix cycle on
  structural findings, and the ADR-0016 addendum's reasoning for it is untouched by this
  measurement.
