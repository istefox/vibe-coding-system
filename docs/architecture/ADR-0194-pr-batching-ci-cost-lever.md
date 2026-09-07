# ADR-0194 — PR batching as a CI-cost lever: adopted in one narrow form, the general form specified and deferred

- **Status:** Proposed
- **Date:** 2026-09-06
- **Issues:** VCS-073 (plant-shard selective-plant scoping, filed by this ADR's §D5)
- **Supersedes forward (conditionally — only if §D3 is ever adopted):** ADR-0127 §D3 (per-topic branch identity) and §D4 (fork-from-prep, one PR per feature). Neither ADR is edited; rule 14. §D2 below supersedes nothing.
- **Related:** ADR-0193 (post-merge CI re-run + duplicate harness runner — this ADR's measurement is the re-derivation of its residual), ADR-0151 §D8/§D10 (plant sharding — named here as the dominant residual, still out of scope), ADR-0180 (`ci-tier` selection — its downgrade rate is measured here), ADR-0128 §D1/§D3 (`publish-feature.sh --issue`, one closing reference per PR), ADR-0186 (Step 5 "batch", a different thing; see §D1 on naming), ADR-0022 §D6 (`publish-feature.sh`, merge stays human), ADR-0071 §D3 (Gate 4.0 must use the `commit` skill, not raw git)
- **Out of scope, deliberately:** `plant-check.sh`'s per-run cost, its shard count, and any selective-plant design. Named in §D5 as the better lever; it needs its own ADR (VCS-073).
- **Numbering note:** two files currently claim `ADR-0193` (`ADR-0193-codex-review-choice-at-dispatch.md`, 2026-09-05, and `ADR-0193-post-merge-ci-rerun-and-duplicate-harness-runner.md`, 2026-09-06). That collision is pre-existing and is not resolved here; this ADR takes 0194 and the collision should be filed separately.

## Context

ADR-0193 removed 1152 of 2567 measured billed minutes and stated plainly that the result is still more than twice the free allowance. The plan that produced it flagged "batch fixes into fewer PRs" as a real but separate lever, and asserted that it "conflicts with ADR-0127 §D4". This ADR examines that claim, and both halves of it turn out to need correction.

### Re-derived 2026-09-06, after Phase 1 and Phase 2 landed (rule 13)

Every `Docs CI` `pull_request` run created since 2026-09-01, billed as `ceil(seconds/60)` per job, summed per run:

| | |
|---|---:|
| Docs CI `pull_request` runs | 28 |
| Total billed | 1677 min |
| Full-tier runs (25) | 1647 min, mean **65.9**, median **67** |
| Downgraded-tier runs (3) | 30 min (7, 11, 12) |
| Merged/open PRs behind those runs | 22 |
| Runs per PR | **1.27** |
| Merge commits on `main`, first-parent | 18 |

Projected forward: 1677 min over 5.8 elapsed days is **~289 min/day, ~8800 min/month**. ADR-0193 projected ~7100; that figure came from a 23-run window earlier the same day, and the fuller window is higher. The ADR is not corrected in place (rule 14) — this is the forward correction.

Two derived facts set the whole frame:

1. **The unit of cost is a validation run, and it costs ~66 minutes flat.** `plant-shard` is ~57 of those 66; `shell-tests` ~5; `markdownlint` + `links` ~2. The cost is almost entirely insensitive to the size of the change. **PR #560 changed one line and cost ~70 billed minutes** — 2.3% of the monthly allowance for a single-line edit.
2. **The budget is therefore ~45 full-tier runs per month** (3000 ÷ 65.9). Current rate: 25 full-tier runs in 5.8 days = **131/month**. The required reduction is **2.9×**, and it must come out of the *count of runs*, the *cost per run*, or the *price of a minute*. Batching can only touch the first.

`ci-tier` (ADR-0180) downgraded **3 of 28 runs (11%)**. The plant registry declares ~100 targets spanning essentially all of `staging/`, so `full` is the practical default; the tier gate is not a meaningful cost lever at this registry shape.

### The premise "batching conflicts with ADR-0127 §D4" is measurably wrong about the traffic that costs money

§D4 governs the **unattended autopilot path**: where a feature branch forks from during an autopilot run. Measured:

- **1 of 22 September PRs came from `publish-feature.sh`** (PR #550 — the only body carrying "Automated unattended run"). The other 21 are attended-path merges.
- **No `autopilot/prep-*` ref has ever existed**, locally or on origin — ADR-0188 measured this on 2026-09-02 and `git rev-parse` confirms it today. §D4's prep-branch topology has never once been in effect. Even PR #550 forked from the default branch, under ADR-0188 §D1.

So the one-fix-per-PR cadence burning 8800 minutes a month is **not set by §D4**. It is set by three attended mechanisms:

- `commit/SKILL.md` **Step 7's post-merge cleanup**, which runs `git checkout "$default_branch"` after every merge — so the next `/commit` starts on `main`, and Step 3.6's derived path creates a fresh branch from the next commit's subject.
- `concept-to-code` **Gate 4.0**, which invokes `commit` with `--branch feat/<manifest.topic>` — one branch per topic, by construction.
- Habit: `TODO.md` sequences work ticket by ticket, and each ticket becomes a chain run.

Step 3.6 is not the obstacle it looks like. Without `--branch`, its trigger is "current branch equals the default branch, or is empty" — **already on a feature branch, it no-ops**. And Step 6's idempotency check reuses an open PR for the same head branch rather than opening a second one. **Grouping several changes into one PR is already mechanically supported today**; what produces one-PR-per-fix is Step 7 returning to `main` and Gate 4.0 pinning the branch name to a single topic.

### The other half the plan got backwards: batching *reduces* the exposure ADR-0193 §D1 accepted

The plan says batching means "more amplification of Phase 1's accepted race-detection gap". The race ADR-0193 §D4 describes requires **two or more PRs merging close together, each validated against a base the other has not yet landed on**, with `strict: false` and post-merge validation now gated off. Measured on the 18 September merges:

- **2026-09-03T09:57 — PRs #549, #550, #551 merged in the same minute.**
- **2026-09-04T17:39 — PRs #555, #556 in the same minute.**
- **2026-09-02T10:22 — PRs #547, #548 in the same minute.**

**7 of 18 merges landed in three same-minute clusters.** Nothing validated any of those combinations, before or after — that is exactly the untested-combination shape §D1 knowingly accepted. Merging those clusters into one PR each would have produced **three runs against three actually-tested trees** instead of seven runs against seven trees none of which was the tree that landed. Batching by merge proximity does not amplify the gap; it closes it for the cases where it is real.

There is a countervailing effect and it is stated rather than hidden: a group PR stays open longer while it accumulates work, and with `strict: false` it is never rebased, so its own base goes staler. Fewer racing PRs, each staler. The net is genuinely ambiguous and is not claimed either way here.

### Cancellation refunds much less than it looks like

`concurrency.cancel-in-progress` is `true` for `pull_request`, so pushing to an open PR branch cancels the in-flight run. Measured, the two cancelled runs in the window cost **34 and 49 billed minutes** — `plant-shard` legs start immediately and had already burned 1568s and 2466s. Cancellation refunded ~50% and ~30%, not ~90%. **A grouping design that pushes each change as it is made saves nothing.** Commits must accumulate locally and push once. `commit`'s existing `--no-pr` flag is exactly that mechanism.

## Decision

### D1 — What "batching" means here, and the word this ADR does not use

**"Batch" is taken.** ADR-0186 and the Step 5 dispatch policy use it for a group of coder task blocks sized off `Budget:` lines. Reusing it for a group of changes sharing a pull request would put two unrelated meanings on one word in a repository whose CI is now gated by needle-precision assertions. This ADR uses **landing group**: *a set of independently-authored changes that share one feature branch and one pull request to `main`.*

Three candidate scopes for what constitutes a group were examined. The distinction is not cosmetic — it decides which existing decisions have to be superseded:

- **(a) Merge-proximity grouping.** Changes that were going to be merged within the same working session go into one PR. Requires no change to any skill contract, because it is a decision about when to return to `main`, not about branch identity.
- **(b) Subject grouping.** Independent fix tickets bundled by theme before a PR is opened. Requires Gate 4.0's `--branch feat/<topic>` to name a group rather than a topic.
- **(c) Run-scoped grouping.** One autopilot run's N features become one PR. Requires superseding §D4 outright and rebuilding `publish-feature.sh`'s per-slug branch and `--issue` contract.

**(a) is adopted (§D2). (b) and (c) are specified and deferred (§D3).**

### D2 — Adopted now: merge-proximity grouping, and it supersedes nothing

**Rule: a change that will be merged in the same working session as a change already on an open PR branch goes onto that branch, not onto a new one.** Concretely, three cases:

1. **A follow-up to a PR that is still open** — a review fix, a correction, a consequence discovered while the first PR was in flight — is a commit on that branch, not a new PR. PR #567 (`fix/required-checks-audit-post-adr0193`, 2 files, 84 lines) is the worked example: it is a direct consequence of #565 and cost a full ~67-minute run of its own.
2. **Mechanical ledger changes** (`chore/sync-todo-ledger` and its class) ride on the next substantive PR. They are not independently bisect-worthy: reverting a `TODO.md` regeneration in isolation has no meaning.
3. **A cluster that is about to be merged together anyway** is opened as one PR. The three 09-03T09:57 merges are the worked example.

**Operationally**, and this is the load-bearing half:

- Intermediate commits use `/commit … --no-pr`, which already exists and already suppresses Step 6/6b/6c/7 entirely. **Nothing is pushed until the group is complete** — see the 34-and-49-minute cancelled runs above.
- The final `/commit` on the branch runs the full Step 6 → 6b → 7 path once. Step 6's idempotency check makes a second invocation on the same branch reuse the open PR by construction, so this needs no new mechanism.
- The group's PR body carries one `Closes #N` line per issue it closes, each on its own line outside any list or fence — the constraint `publish-feature.sh` already documents at its `PR_BODY` construction.
- **Step 7's post-merge `git checkout "$default_branch"` is unchanged.** Returning to `main` after a merge is correct; the change is that fewer merges happen, not that the cleanup is skipped.

**This supersedes nothing.** §D4 governs the fork point on the unattended path and has never been in effect (§Context). §D3 governs the agreement between Gate 4.0's `--branch` and `publish-feature.sh`'s `BRANCH="feat/$SLUG"`, and merge-proximity grouping never puts two topics on one branch — it puts a topic and its own follow-ups there, which is what a feature branch is. The only thing that changes is when a human chooses to open a PR, and no ADR has ever governed that.

**This is an instruction, not an enforcement (rule 16).** Nothing mechanically prevents opening a second PR for a follow-up, and this ADR does not propose a check that would. A check that could tell "a legitimate second subject" from "a follow-up that should have ridden along" would have to read intent; the honest shape is a stated working rule whose failure mode is a wasted 67 minutes, not a broken invariant.

**Measured effect, stated so it is not oversold:** grouping the three observed clusters plus the mechanical-ledger class removes roughly 4 of 22 PRs per 5.8 days — **~270 min/5.8d, ~1400 min/month, from ~8800 to ~7400.** It does not close the gap and is not offered as closing it. It is free, it is safety-positive, and it should be done regardless of what else is decided.

### D3 — Specified, NOT adopted: general grouping, and exactly what it would supersede

Recorded in full so that a future reader facing the same bill does not have to re-derive it, and so the recommendation in §D4 is a choice between two described options rather than a preference.

**The arithmetic.** With 115 PRs/month at 1.27 runs each and a measured 18% per-PR re-run rate, a landing group of *k* independent changes costs approximately `(115/k) × (1 + (1 − 0.82^k))` runs per month at ~66 min each:

| group size *k* | runs/month | billed min/month |
|---:|---:|---:|
| 1 (today) | 146 | ~8800 |
| 2 | 76 | ~5100 |
| 3 | 56 | ~3700 |
| 4 | 45 | **~3000** |
| 6 | 33 | ~2200 |

**k = 4 lands exactly on the 3000-minute line with zero headroom.** Reliable headroom needs k ≈ 6 — roughly **three to five merges per week**, against a current cadence of about three per day.

**What would have to change.** This is where the plan's cost estimate is too low:

- **ADR-0127 §D3 must be superseded, not only §D4.** §D3's entire point is that the branch name agrees *by construction* between Gate 4.0's `--branch feat/<manifest.topic>` and `publish-feature.sh`'s `BRANCH="feat/$SLUG"`, both derived from one manifest field. A landing group has *n* topics and one branch, so that identity cannot hold. Gate 4.0 would need a group ref, `publish-feature.sh` a `--branch` that is not derived from `--slug`, and the two-sites-state-the-contract requirement (#363 R-02) restated for a one-to-many relation. This is the deepest structural obstacle and it is not mentioned anywhere in the plan.
- **ADR-0128 §D1's `--issue <N>` becomes `--issue <N>[,<N>…]`.** Its "the number is known upstream, one per feature" reasoning — and its explicit rejection of deriving the number by fuzzy-matching a slug — has to be restated for a list, along with the digits-only validation and the "malformed is a hard fail because a broken extraction breaks every feature" argument.
- **ADR-0127 §D4's forward supersession, stated precisely.** §D4 chose fork-from-prep as "the only arrangement that satisfies both halves at once — independent, individually reviewable feature PRs, *and* every feature's design inputs present in its own tree." Under D3 the first half is **given up on purpose**: a landing group is one PR containing *n* features, reviewed as a unit. The second half is unaffected — a group branch forked from the prep ref still carries Phase P's outputs, so Finding 2's objection to forking from `main` is untouched and stays true. What is superseded is one clause of §D4's *rationale*, for a reason §D4 did not have in front of it: at ~66 billed minutes per validation run, "independently reviewable" costs ~66 minutes per unit of independence, and the repository cannot afford 131 of them a month. §D4's own recorded cost line — "one extra PR per run" — was written when a PR was free.
- **`--features N` interacts.** Under §D5 the runner already resolves a concrete feature list before Phase 1. A group is a partition of that list, which is a new concept the runner does not have.
- **The `published` ledger** (§D4, ADR-0167 §D4) is per-slug and would need to record group membership, or a resumed run re-picks a feature already in an unmerged group.

**Why this is not adopted now is in §D4, not here.** If it is ever adopted, the supersession above is the text; it stands forward and neither ADR-0127 nor ADR-0128 is edited.

### D4 — Recommendation: adopt D2, defer D3, and spend the effort on §D5 instead

**Do not adopt general grouping as the remedy for the CI bill.** Three reasons, in order of weight:

1. **It buys at most a 3× reduction, and the gap is 2.9×.** Perfect execution at k = 4 lands on the line with no margin — one busy week puts the repo over. The lever is barely large enough to matter, and it is the only one of the four available levers that is.

2. **It degrades the one property this repository's entire method depends on.** This repo runs ~2993 assertions and 674 declared plants; rule 2 says an assertion nobody planted pins nothing, and rule 19 says a deleted assertion leaves a comment naming its issue. The whole culture is **per-change attribution of red**. A landing group of six subjects that goes red on `plant-check.sh` gives one failing leg and six candidate causes, and `commit` Step 6c's diagnosis — which reports the failing check and stops, never auto-fixing — has no way to attribute it. Bisectability is not a generic software virtue here; it is the mechanism by which this repository knows anything. Trading it for CI minutes is a worse trade in this repo than it would be in almost any other.

3. **The cost of building it is much higher than the plan assumed.** §D3 above requires superseding two ADRs (0127 §D3 and §D4), amending a third (0128 §D1/§D3), changing Gate 4.0, `publish-feature.sh`, the `published` ledger and the run-scope resolver — each with the harness assertions that pin them. That is a chain-sized feature, and every chain run it takes to build costs ~66 minutes of the thing it is trying to save.

**Adopt D2** — it is free, it removes ~1400 min/month, and it makes three measured untested-combination merges into tested ones.

**The two levers that actually close the gap are both outside this ADR**, and both are better than D3 on every axis:

- **Making the repository public** (the plan's point 3, in flight in parallel). Actions minutes are free and unlimited on public repos: the bill goes to **zero**, not to 3000. It requires no engineering, no supersession, and no loss of atomicity. Its only precondition is the `clean-public-repo` content audit, which is the right gate and already exists. **If this lands, D3 never needs to exist and neither does most of §D5.**
- **Cutting `plant-shard`'s per-run cost** (§D5).

**Recommended decision: D2 accepted; D3 deferred with the supersession text preserved above; §D5 filed as its own issue (VCS-073); the public-repo audit is the primary track.** Revisit D3 only if the repository must stay private *and* §D5 turns out to be unbuildable — a conjunction that is not currently expected.

### D5 — The dominant residual, named but not designed here

`plant-shard` is **~57 of every ~66 billed minutes — 86% of the cost of a PR**. It runs all 674 declared plants on every full-tier run, sharded four ways at ~850s per leg, regardless of what the PR changed. That is why a one-line docs edit costs 70 minutes.

The obvious shape — run only the plants whose target file, or whose declaring harness, is in the changed set, plus their shared-helper closure — would take a typical PR from 674 plants to a few dozen, i.e. **from ~66 min to roughly ~10–15 min per run**. At today's unchanged cadence of 131 runs/month that is **~1300–2000 min/month: under the allowance, with headroom, with no process change and no atomicity lost.** It is a strictly better lever than D3 on cost, on effort, and on what it gives up.

It is **not designed here**, and the reason is not scope alone. It has a real failure mode this repository has a rule for: **a plant that was not selected is not a plant that passed** (rule 4). Any such design must report unselected plants as a state distinct from a clean result, must guard the denominator of the selection (rule 7 — an empty selection and a clean selection look identical from outside), and needs a periodic full sweep on `schedule:` or `workflow_dispatch` to catch the couplings the closure misses. ADR-0151 §D10 already rejected a *narrower* version of this idea — restricting the baseline pass to the shard's slice — on the grounds that a second population derivation can drift from the first. That objection applies here with more force, not less, and answering it is an ADR's worth of work. **Filed as VCS-073.**

## Alternatives considered

**Do nothing beyond ADR-0193 and absorb the overage.** Rejected as a *silent* option, not as an option: at ~8800 min/month against 3000, the overage is ~5800 min/month at GitHub's published per-minute rate for private-repo Linux runners. That may well be an acceptable amount of money, and if it is, that is a legitimate decision — but it must be a decision someone takes with the number in front of them, not the default that happens because no lever was pulled. Named first because it is the honest baseline every other option is measured against.

**GitHub merge queue.** This is the mechanism that gives batching's CI economics without giving up anything: PRs stay individual and individually reviewable, the queue groups them and validates the combined tree once. It would be strictly better than D3 on every axis. **Rejected because it is unavailable here, verified not assumed:** merge queue requires an organization-owned repository — any public org repo, or a private org repo on GitHub Enterprise Cloud. `vibe-coding-system` is a **private repository owned by a personal account on GitHub Pro** (confirmed live 2026-09-06: `{"private": true, "owner.type": "User"}`, account plan `pro`). It remains unavailable even if the repo goes public, because public availability is also scoped to organization-owned repos. Transferring the repo to an organization to obtain it is a larger change than the problem justifies, and going public makes the minutes free anyway, which is the thing the queue was wanted for.

**`required_status_checks.strict: true` instead of grouping.** Would move integration-race detection before the merge, where it can block. Rejected on the same measurement ADR-0193 used and re-derived here: at 18 merges in 5.8 days every merge invalidates every open PR and forces a re-run, which at ~66 min per run is plainly more expensive than what it replaces. Recorded again because it becomes the right answer *if D3 is ever adopted* — at three to five merges per week, `strict: true` is cheap and would restore the pre-merge validation D3's larger blast radius makes more valuable. The two decisions are coupled and should be taken together if taken at all.

**Grouping by subject rather than by merge proximity (§D1 option b).** Rejected as the adopted form because it requires the Gate 4.0 / `publish-feature.sh` branch-identity supersession (§D3) for a saving that merge-proximity grouping gets for free, and because "same theme" is a judgment call whereas "about to be merged in the same session" is an observation. It remains available as the first increment of D3 if D3 is ever taken up.

**A weekly `schedule:` full validation on `main`, so PRs could run a cheaper subset.** Rejected here for the same reason ADR-0193 rejected it as a `workflow_dispatch` replacement, plus one more: it does not reduce the PR-run cost by itself. It is a necessary *component* of the §D5 selective-plant design (the periodic full sweep that catches what the closure misses), not an alternative to it, and should be decided there rather than here.

**Self-hosted runner, or a larger GitHub-hosted runner.** A self-hosted runner on Stefano's own machine makes Actions minutes free for private repos. Rejected: it moves ~57 minutes of compute per PR onto a laptop that is usually doing something else, it requires the runner to be up whenever a PR is opened (an unattended autopilot run at 03:00 would silently stall on a pending required check), and it introduces a security posture — a self-hosted runner executing PR code — that this repository has no need to take on. A larger hosted runner is worse than useless: it bills at a higher multiplier for the same work, and `plant-check.sh`'s cost is dominated by serialised mutate-run-restore cycles, not by core count.

**Reduce the shard count from 4 to 1 to remove per-leg setup overhead.** Rejected on measurement: per-leg setup is ~2 min of a ~14-min leg, so collapsing to one job saves roughly 6 of 57 minutes (~10%) and costs the wall-clock parallelism ADR-0151 §D8 was built for. The cost is in the 674 plants, not in the sharding. Named because "just unshard it" is the obvious first guess and it is wrong.

**Fold the `plant-shard` gate into `ci-tier` more aggressively — e.g. treat `docs/`-only changes as `docs` tier unconditionally.** Rejected: `ci-tier.sh`'s header already records why, measured — the plant registry declares 100 targets, 11 of them under `docs/`, including `docs/chain-decisions.md` and `docs/chain-decision-index.md`. A path heuristic would silently skip the registry's own verification targets. This is the failure ADR-0180 chose the registry-derived rule to avoid, and re-introducing it to save minutes would be the exact rule-4 collapse ("did not run" reading as "found nothing") the repository keeps recording.

## Consequences

### Positive

- **D2 is free and removes ~1400 min/month** (~8800 → ~7400) with no supersession, no mechanism change, and no new assertion to maintain. It uses `--no-pr` and Step 6's PR idempotency check exactly as they already exist.
- **D2 repairs, for its cases, the exposure ADR-0193 §D1 knowingly accepted.** Seven of eighteen September merges landed in three same-minute clusters that nothing validated in combination, before or after. Grouped, each cluster becomes one run against the tree that actually lands.
- **The premise is now measured rather than quoted.** The one-fix-per-PR cadence is set by `commit` Step 7 and Gate 4.0 on the attended path, not by ADR-0127 §D4 — which has never been in effect, since no `autopilot/prep-*` ref has ever existed and 21 of 22 September PRs were attended.
- **The cost model is now a single number anyone can reason with:** ~66 billed minutes per full-tier validation run, ~45 runs/month of budget, 131 today. Every future proposal can be evaluated against it in one line.
- **D3 is specified rather than merely refused.** If the bill has to come down and the repo must stay private, the supersession text, the affected call sites and the arithmetic are written down and do not have to be re-derived under pressure.
- **§D5 names where the money actually is** (86% of a PR's cost, in one job) with a sized estimate, filed as VCS-073, rather than left as a shrug.

### Negative

- **D2 does not close the gap and is not claimed to.** ~7400 min/month against 3000. Anyone reading only the Decision section could mistake an adopted item for a solved problem; it is adopted because it is free, not because it is sufficient.
- **D2 is an instruction, not an enforcement (rule 16).** Nothing prevents opening a separate PR for a follow-up, and no check is proposed, because a check that could distinguish a legitimate new subject from a follow-up would have to read intent. The failure mode is a wasted 67 minutes with no signal that it was wasted.
- **D2 makes some PRs mildly less atomic.** A ledger sync riding on a substantive PR is not separately revertible. Judged acceptable specifically because that class of change is not independently bisect-worthy; the judgement does not extend to the general case, which is why D3 is deferred.
- **Deferring D3 means the decision is deferred, not made.** If the public-repo audit comes back with a blocker and §D5 proves harder than estimated, this ADR will have spent effort specifying an option it did not take. That is the intended shape — the specification is the deliverable — but it is a cost.
- **The §D5 estimate (~10–15 min/run) is an estimate, not a measurement.** It is derived from plant counts and per-plant timing (674 plants, ~3400 leg-seconds, ~5s/plant), not from a built prototype. Its own ADR (VCS-073) must re-derive it before anything is designed on it (rule 13), and the closure it depends on — shared helpers coupling a harness to a plant whose target did not change — is precisely the part that could make the real number much worse.
- **This ADR's monthly projection (~8800) is higher than ADR-0193's (~7100)** for the same repository one day later, because the run count in the fuller window is higher. Two projections a day apart differing by 24% is a reminder that both are extrapolations from a six-day window containing an unusual amount of CI-related work. Neither is a forecast.

### Neutral

- **ADR-0127 is not edited.** §D3 and §D4 stand byte-unchanged; the supersession in §D3 above is conditional and forward, and takes effect only if D3 is ever adopted. Same for ADR-0128 §D1/§D3.
- **`commit`'s Step 7 post-merge `git checkout "$default_branch"` is unchanged** under D2. Returning to `main` after a merge is correct; what changes is how often a merge happens.
- **ADR-0151's sharding, its baseline pass and §D10's trade-off are untouched**, as in ADR-0193, and for the same reason: they need their own decision, not a clause in someone else's.
- **`ci-tier`'s 11% downgrade rate is recorded, not acted on.** ADR-0180's gate is working as specified; it is simply not a cost lever at a registry shape where ~100 targets span all of `staging/`. No change is proposed to it.
- **The `ADR-0193` filename collision** (two files, 2026-09-05 and 2026-09-06) is noted and left alone. Renaming a merged ADR is a cross-reference change across an unknown number of citing files and is its own small task.
- **The "38 merges to `main`" figure in ADR-0193's Context could not be reproduced** from git history: 18 merge commits are on `main` first-parent since 2026-09-01. The discrepancy is most likely a different denominator (all merged PRs across all base branches). It does not affect any billed-minutes figure in either ADR, and ADR-0193 is not corrected in place (rule 14).

## References

- Actions API measurement, 2026-09-06: 28 `Docs CI` `pull_request` runs created since 2026-09-01, billed `ceil(seconds/60)` per job — 1677 min total; full-tier subset (25 runs) 1647 min, mean 65.9, median 67; downgraded subset (3 runs) 7/11/12 min. Cancelled runs cost 34 and 49 min.
- `git log origin/main --since=2026-09-01 --first-parent`: 18 merges. `gh pr list --state merged`: 22 PRs merged since 2026-09-01; 9 of them changed ≤ 2 files; PR #560 changed 1 line and cost ~70 billed minutes.
- Same-minute merge clusters: #549/#550/#551 (2026-09-03T09:57Z), #555/#556 (2026-09-04T17:39Z), #547/#548 (2026-09-02T10:22Z).
- Autopilot-path share: `gh pr list --json body` — 1 of 22 PRs carries `publish-feature.sh`'s "Automated unattended run" body (#550). `git rev-parse origin/autopilot/prep-*` — no such ref, consistent with ADR-0188's 2026-09-02 measurement.
- Repository settings, live 2026-09-06: `{"private": true, "owner.type": "User", "allow_auto_merge": false, "allow_merge_commit": true, "allow_squash_merge": true}`; account plan `pro`. Branch protection: `{"contexts": ["markdownlint","links","shell-tests"], "strict": false, "linear": false}`.
- Merge-queue availability (verified 2026-09-06, not asserted from memory): organization-owned repositories only — any public org repo, private org repos on GitHub Enterprise Cloud. [Managing a merge queue — GitHub Docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue), [GitHub merge queue is generally available — GitHub Blog](https://github.blog/news-insights/product-news/github-merge-queue-is-generally-available/)
- Plant registry: 674 `# plant:` declarations across 103 harnesses; `plant-shard` matrix of 4 legs, ~850s per leg.
- `staging/plugin/skills/commit/SKILL.md` — Step 3.6 (branch trigger and `--branch` semantics), Step 6 (PR idempotency check), Step 6c (diagnose, never auto-fix), Step 7 (merge gate and post-merge `git checkout "$default_branch"`).
- `staging/plugin/skills/concept-to-code/references/hitl-gates.md` — Gate 4.0, `--no-pr --branch feat/<manifest.topic>`.
- `staging/plugin/scripts/publish-feature.sh` — `BRANCH="feat/$SLUG"` (lines 57–68), `--issue` validation (50–53), `PR_BODY` / `Closes #N` construction (123–134).
- `staging/plugin/scripts/ci-tier.sh` — the classification rule and the recorded reason a path heuristic was rejected.
- `.github/workflows/docs-ci.yml` — `concurrency.cancel-in-progress`, the ADR-0193 `if:` conditions, the `plant-shard` matrix.
- ADR-0193 §Context/§D1/§D4, ADR-0151 §D8/§D10, ADR-0180 §Decision, ADR-0188 §D1, ADR-0128 §D1/§D3, ADR-0127 §D3/§D4/Finding 2, ADR-0186 (the other meaning of "batch"), ADR-0022 §D6.
- Rules 1, 2, 4, 6, 7, 13, 14, 16, 17, 19 (CLAUDE.md).
