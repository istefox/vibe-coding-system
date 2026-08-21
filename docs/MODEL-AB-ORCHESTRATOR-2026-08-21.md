# Orchestrator model A/B — protocol (2026-08-21)

## The question

`~/.claude/settings.json` carries `model: "opusplan"`. Measured on this repo's session
`30ed7bf2` on 2026-08-21: **620 assistant turns, every one of them `claude-opus-5`**, 570,216
output tokens. The question is whether the orchestrator seat should default to Sonnet 5 instead.

It is not answerable from preference, and the two obvious instruments both lie. This file
records the method before either run, so the method cannot be chosen after seeing the results.

## Why the existing instrument cannot answer it

`review-triage-fix` already persists findings as TSV (`sev`, `loc`, `problem`) and
`triage-state.sh` derives each finding's identity as the first 8 hex of the sha256 of
`sev|loc|problem`, whitespace-normalised. **That identity includes the problem wording.**

`review-triage-fix/SKILL.md` states the consequence itself: paraphrasing changes the hash and
generates false RESOLVED+NEW pairs, which is why the re-reviewer is instructed to reuse the
previous cycle's wording verbatim. Across two different models that instruction cannot exist.
Every finding would hash differently in both directions, and the comparison would report 100%
NEW while measuring nothing.

## Why counting findings is the wrong metric even after fixing the hash

A weaker reviewer can emit **more** findings, because noise counts as a finding. A metric that
ranks by volume ranks noise first.

What separated the two on 2026-08-21 was not volume. It was four instances of *the artefact
asserts X, the file says Y*:

1. The approved plan, **and the harness's own header comment**, said `plant-check.sh` copies
   only `staging/` and `docs/` into its sandbox. `build_sandbox()` copies six things.
2. The plan said the index held 116 entries. It held 117.
3. The stale premise in (1) was written inside the file being edited, not only in the plan.
4. `CMC06` was declared unplantable rather than given a plant that would have passed silently
   (a `>= 90` floor absorbs its own plant).

None of those is a finding count. All four are premise checks. The metric must score those.

## Method

**Answer key first.** Before either leg runs, every factual claim in the input artefacts is
verified against the files, and each becomes one key item carrying the command that decides it.
A claim that turns out to be true is a key item too: a leg that "corrects" a true claim has
produced a false positive, and a protocol that only counts catches cannot see that.

**The key is frozen before the runs.** Its sha256 is recorded in this file below. A key edited
after seeing a leg's output is not a key.

**Both legs run in fresh sessions.** Neither leg may read session `30ed7bf2`, this file's key
section, or the other leg's transcript. The session that wrote this protocol takes part in
neither leg — it already knows the answers, so it is not a subject.

**Identical input.** Same issue, same scoped invocation, same working tree revision, recorded
below. The only intended difference between the legs is the orchestrator's model.

**Effort is pinned equal, and this is not optional.** Section 3.10 of `docs/vibe-coding-system.md`
already recommends effort over model, and Sonnet 5 exposes the `xhigh` tier. With effort left at
whatever each session happens to carry, the experiment measures effort and reports it as model.
Both legs run at the same declared tier. The live global value on 2026-08-21 is
`effortLevel: "medium"` — note that the blueprint's own text at the "Available effort levels by
model" block still says `high`, which is stale.

**The chain's own agents are already pinned and must stay pinned.** `concept-to-code` Step 5/6
pass an explicit `model` on every `agent()` call precisely because a Workflow subagent with no
`model` inherits the CLI session's model. That pinning is what keeps this experiment about the
orchestrator seat alone. If a leg is observed running coder or reviewer on the session model,
that leg is void.

## Scoring

Each key item gets exactly one of three verdicts per leg:

| verdict | meaning |
|---|---|
| `CAUGHT` | the leg checked the claim against the files and reported the discrepancy |
| `MISSED` | the leg reached the claim and proceeded on it without checking |
| `NOT-REACHED` | the leg never got to the claim (halted earlier, scoped it out, ran out) |

`NOT-REACHED` is not `MISSED`, for the same reason exit 3 is not exit 0 in this repo: a check
that could not run is not a check that found nothing. A leg with many `NOT-REACHED` items has not
been measured, it has been interrupted, and the comparison for those items is void rather than
favourable to the other leg.

False positives are counted separately and are not netted against catches: a leg that flags a
true claim as false is reported as `FALSE-ALARM` on that item.

## What this cannot say

- It compares two models on **one** task. It does not generalise to other repos, and this repo
  is unusually premise-dense.
- It says nothing about cost in currency. Output-token counts are recorded; pricing is not
  asserted here.
- A tie does not mean "switch, it is cheaper". It means the task did not discriminate, and a
  second task is needed before the seat is changed.

## Run record

| field | value |
|---|---|
| task | *not yet chosen — see Next step* |
| tree revision | *pending* |
| effort tier, both legs | *pending* |
| key sha256 | *pending — the key is not yet written* |
| leg A model | `claude-opus-5` |
| leg B model | `claude-sonnet-5` |

## Next step

Derive the answer key for the chosen task by verifying every factual claim in its body against
the files, and record its sha256 above. Nothing runs before that.

## Status

Protocol only. **No leg has run. No key has been written.** Any number quoted from this file as
a result is a misreading of it.
