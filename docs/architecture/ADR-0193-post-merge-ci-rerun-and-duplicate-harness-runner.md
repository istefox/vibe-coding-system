# ADR-0193 — The post-merge CI re-run is deleted, and the harness suite runs in exactly one job

- **Status:** Partially Accepted — D1 (Phase 1, this commit) is accepted and implemented. D2-D4
  (Phase 2: deleting `ci.yml`, consolidating the duplicate 102-test run, updating the sixteen
  stale guards, the branch-protection change) are Proposed, pending separate HITL approval and
  execution.
- **Date:** 2026-09-06
- **Issues:** none filed yet; file one before accepting D2-D4
- **Related:** ADR-0180 (`ci-tier` selection — one Decision clause is amended forward by D2, not
  yet executed), ADR-0151 (sharding the plant registry — its §D8 topology is preserved unchanged;
  its §D10 cost trade-off is out of scope by instruction and is named as the dominant residual),
  ADR-0113 / issue #331 (`pairs-completeness.test.sh` CI1, the list-completeness check that makes
  the duplicate glob redundant), ADR-0127 §D4 (fork-from-prep, which amplifies the risk D1
  accepts), ADR-0022 §D8 (the CI template — untouched), ADR-0054 (the `ci` / `checks` posture
  split in the template — untouched)
- **Out of scope, deliberately:** `plant-check.sh`'s shard count, its per-leg baseline pass, and
  ADR-0151 §D10's sharded-vs-sequential trade-off. They are the largest single line item in the
  measurement below and they are not touched here.

## Context

GitHub billing reports **2727 of 3000** free Actions minutes consumed in the first six days of
September 2026 (91%), against **38 merges to `main`** in that window.

### Measured

Re-derived 2026-09-06 from the Actions API — every run created since 2026-09-01, every job in
each run, billed as `ceil(seconds / 60)` (GitHub's own per-job rounding). Rule 13: the premise is
measured, not quoted.

| Workflow | Event | Job | Jobs | Billed min | Avg |
|---|---|---|---:|---:|---:|
| Docs CI | pull_request | markdownlint | 23 | 23 | 1.0 |
| Docs CI | pull_request | links | 23 | 23 | 1.0 |
| Docs CI | pull_request | plant-shard | 92 | 1218 | 13.2 |
| Docs CI | pull_request | shell-tests | 23 | 119 | 5.2 |
| Docs CI | push | markdownlint | 16 | 16 | 1.0 |
| Docs CI | push | links | 16 | 16 | 1.0 |
| Docs CI | push | plant-shard | 60 | 891 | 14.8 |
| Docs CI | push | shell-tests | 15 | 79 | 5.3 |
| ci | pull_request | ci | 23 | 106 | 4.6 |
| ci | push | ci | 15 | 76 | 5.1 |
| **TOTAL** | | | **306** | **2567** | |

- By event: `pull_request` **1489** (58%), `push` **1078** (42%).
- Every one of the 23 `pull_request` runs resolved to tier `full` (92 plant-shard legs / 23 runs =
  4 legs each). ADR-0180's tier gate is downgrading almost nothing in practice.

Two structural facts behind those numbers:

1. **Both workflows trigger on `pull_request: [main]` AND `push: [main]`.** Branch protection has
   `required_status_checks.strict: false` and `required_linear_history: false`, so a merge creates
   a genuinely new SHA and the whole heavy validation runs a second time — after the merge has
   already landed, where it can block nothing. 1078 minutes in six days, purely diagnostic.
2. **The same 102 harness files execute twice per `pull_request` event, in two workflows.**
   `ci.yml`'s `Run tests` step globs `staging/plugin/scripts/tests/*.test.sh`; `docs-ci.yml`'s
   `shell-tests` job names ~102 harnesses by hand and runs each. Re-derived 2026-09-06: **102 in
   the named list, 102 on disk, 0 unique to either side.** Rule 6 is exactly on point — two copies
   answering *one* question, whose disagreement would be a defect. (`plant-shard`'s mutation run
   is a third pass and is **not** a duplicate: it re-runs declaring harnesses under mutation to
   prove their assertions fire. Different question, stays.) This half (D2-D4) is not yet
   implemented — see Status.

### What made the duplicate survive review

Sixteen assertions across sixteen harnesses pin "`ci.yml` still globs the tests directory", each
worded as a *forward guard* — "no manual registration needed there". They read as the automatic
backstop protecting the hand-maintained `docs-ci.yml` list from drift. **They are not.**
`pairs-completeness.test.sh`'s CI0/CI0b/CI1/CI2 (ADR-0113, issue #331) already enforce that list's
completeness in both directions, with count guards on both denominators. The glob has been
redundant since #331 landed, and sixteen assertions describing it as load-bearing is what kept
anyone from noticing.

Worse, and measured: **nine of those sixteen use the needle
`grep -qE 'tests/\*\.test\.sh|scripts/tests'`.** The `scripts/tests` alternation matches any
mention of the path — including a comment. Nine of the sixteen guards protecting the mechanism
would pass against a `ci.yml` with the mechanism deleted. Rule 1, in the assertions written to
enforce rule 1. (Fixed in D3, not yet implemented.)

## Decision

### D1 — The heavy jobs stop running on `push: [main]`; the cheap ones stay — ACCEPTED, IMPLEMENTED

In `.github/workflows/docs-ci.yml`:

- `on:` keeps `pull_request: branches: [main]` and `push: branches: [main]`, and **gains
  `workflow_dispatch:`**.
- `plant-shard` and `shell-tests` each gain a job-level `if: github.event_name != 'push'`.
- `markdownlint` and `links` are unchanged and keep running on every merge.

`markdownlint` and `links` cost **32 minutes per six days** together. `links` is the only check in
this repository that is genuinely cross-PR: PR A deletes a file, PR B adds a relative link to it,
both green, `main` red. Keeping a one-minute repo-wide link check on the merged tree for 1/34th of
the push cost is the right ratio; dropping it to save 32 minutes is not.

**The two `if:` conditions must be identical, and this is load-bearing, not tidiness.**
`shell-tests` declares `needs: [plant-shard]` with `if: always()`, and its `--require-legs` step
treats a `skipped` shard result as a failure (`plant-check.sh --require-legs skipped` → exit 1). A
`plant-shard` skipped while `shell-tests` runs is a red `shell-tests` on every merge. Producer and
consumer, stated at both sites (rule 17).

**`workflow_dispatch` is the escape hatch, and it composes correctly**: a manual dispatch has
`github.event_name == 'workflow_dispatch'`, so the `!= 'push'` guard lets the heavy jobs run. After
a suspicious merge, a human runs the full validation on `main` on demand, at zero standing cost.

Verified locally 2026-09-06: full 102-file harness suite green after this change (no test asserts
on the trigger/condition blocks touched here).

### D2 — `.github/workflows/ci.yml` is deleted; `shell-tests` is the sole harness runner — PROPOSED

This **amends ADR-0180's Decision**, which states that `ci.yml`'s `ci` job keeps its `Decide CI
tier` step and its test loop, "preserving the literal glob line `for t in
staging/plugin/scripts/tests/*.test.sh` that `precompact-occupancy.test.sh`'s XH2 pins". That
clause was correct on 2026-08-29 and is not edited (rule 14). It is superseded here, forward, for a
reason ADR-0180 did not have in front of it: the line it preserves is the duplicate half of a
rule-6 violation.

**Which copy survives is not a free choice.** `shell-tests` keeps the loop because four independent
mechanisms pin it there: ADR-0151 §D8's topology and its explicit "keeps its harness loop";
`plant-registry-parallel.test.sh`'s PS11, which pins "the unchanged harness-loop line";
`pairs-completeness.test.sh`'s CI0/CI0b/CI1/CI2 over the named list; and ~35 per-harness "my name
is in the `docs-ci.yml` list" assertions. Moving the loop the other way breaks all four.

**`ci` therefore has nothing left to do**, and the file should be deleted rather than emptied:

- There is no non-duplicating content available. `.claude/test-cmd` does not exist in this
  repository and there is no test command other than the harness loop. A required status check
  that runs no check is worse than no check.
- A gutted-but-present `ci.yml` leaves **nine of the sixteen** guards passing vacuously (§Context).
  Deleting the file makes all sixteen fail loudly, which is the signal a maintainer needs.
- The file has not been a faithful instantiation of `staging/project-templates/ci/ci.yml` for a
  long time: the template has four jobs (`ci`, `checks`, `security-audit`, `licence-scan`) and its
  `ci` runs `__TEST_CMD__`; this repository's has one job running a glob loop, and no
  `.claude/test-cmd` to substitute from. Its header comment claims otherwise. Deleting it removes
  a false claim, not a working check.

The template `staging/project-templates/ci/ci.yml` is **unchanged**. It is the artifact ADR-0022
§D8 specifies and it remains the deliverable for target repos; only this repository's own
divergent copy goes.

`ci` is removed from `main`'s required status checks, leaving `markdownlint`, `links`,
`shell-tests` — all three still produced by `docs-ci.yml`. This is a change to repository settings
on GitHub and is a human gate, not an agent action.

### D3 — Sixteen weak guards become one canonical assertion — PROPOSED

The sixteen per-file guards are to be **deleted**, each leaving the rule-19 comment where it stood
naming this ADR and the issue. They are not rewritten in place: sixteen rewrites are sixteen fresh
opportunities to write a needle that pins nothing, and nine of the current sixteen already are one.

They are replaced by **one** assertion, `CI3`, in `pairs-completeness.test.sh` — the file that
already owns the CI-registration question (CI0/CI0b/CI1/CI2, ADR-0113):

> **CI3 — exactly one job across `.github/workflows/*.yml` executes the harness suite.**

with a count guard on the workflow-file denominator (rule 7: zero candidate workflow files and
zero duplicate runners are indistinguishable from outside). CI3 is the assertion that would have
caught this duplication when it was introduced, and it is the assertion that stops it returning.
It carries the same declared no-plant note CI1 already carries in that file: `plant-check.sh`
mutates copies of `staging/` and `docs/` only, so `.github/` cannot be reached by a plant, and the
honest substitute is live red evidence at first run (ADR-0108 §PC1) — exactly how CI1 earned its
place.

### D4 — What is knowingly given up, and what this does not fix

**Given up (D1, already in effect): post-merge detection of an integration race.** With
`strict: false`, two PRs each green against a base several merges old can break `main` together.
ADR-0127 §D4 amplifies this: under autopilot every feature branch forks from the run-scoped prep
branch, so N feature PRs are all validated against a base stale by up to N-1 merges.

Detection is **delayed and misattributed, not lost**: a `pull_request` run executes against
`refs/pull/N/merge` — the PR head merged with *current* `main` — so the next PR after a bad merge
goes red, blamed on the wrong change. `workflow_dispatch` (D1) restores on-demand detection with
correct attribution. **This trade is the human's to accept; it is not assumed here.** (Accepted by
Stefano 2026-09-06 for D1.)

**Not fixed even once D2-D4 land, and stated so the 45% is not mistaken for a solution.** D1 alone
(implemented) removes 970 of 2567 measured minutes (37.8%). D1+D2+D3 together would remove **1152
of 2567 minutes (44.9%)** — projected ~12 800 → ~7 100 min/month. **That is still more than twice
the 3000-minute allowance.** The dominant residual is `plant-shard` on `pull_request`: **1218 min
in six days, 47% of the pre-fix total**, with all 23 runs at tier `full`. That is ADR-0151 §D10 and
ADR-0180 territory and is out of scope here by instruction. A separate issue should carry it. The
repository's remaining levers (batching fixes into fewer PRs — conflicts with ADR-0127 §D4;
making the repository public, which makes Actions minutes free and unlimited) are tracked outside
this ADR.

## Alternatives considered

**Remove `push: branches: [main]` from `docs-ci.yml` entirely.** Saves 32 more minutes per six
days. Rejected on ratio: it also removes `links`, the one repo-wide check whose failure mode is
genuinely cross-PR (a link in PR B to a file PR A deleted), for 3% of the push cost. A one-minute
job that catches a class of failure nothing else can see is the last thing to cut.

**Enable `required_status_checks.strict: true`.** Moves integration-race detection *before* the
merge, where it can actually block — strictly better than the post-merge diagnostic it would
replace. Rejected on the measurement: at 38 merges in six days, every merge invalidates every open
PR and forces a re-run. Against 23 PR runs already costing 1489 minutes, this is plainly more
expensive than the 1078 minutes it removes. It becomes the right answer if merge cadence drops
sharply; recorded here so the next reader does not have to re-derive it.

**Gate the heavy work at STEP level on `push`, keeping the jobs reporting (ADR-0180's stated
preference).** Rejected on cost: checkout + `zsh` install + `Decide CI tier` is ~2 minutes, times
five jobs (four `plant-shard` legs plus `shell-tests`), times 17 pushes ≈ **170 minutes per six
days spent printing `::notice::` lines nothing consults**. ADR-0180's step-level rule was reasoned
about the *tier* gate on `pull_request`, where the job is a required context that must report or
leave the PR pending forever; on a `push` event branch protection evaluates nothing at all. This is
a narrow departure with a stated reason, recorded rather than silent — and rule 4's actual concern
is unaffected: a skipped job renders as *skipped*, never as a passing check.

**Add a weekly `schedule:` full run on `main` instead of / alongside `workflow_dispatch`.** ~4 runs
per month ≈ 264 minutes. Rejected as the *default* because `workflow_dispatch` answers the same
need at zero standing cost and with better timing (right after a suspicious merge, not up to seven
days later). Offered as an option if the human prefers an unattended cadence — the mechanism is one
`schedule:` key and no other change.

**Keep `ci.yml` but reduce the `ci` job to a thin tier-decision plus a pointer notice.** Avoids the
branch-protection change and preserves `ci-tier-workflow-decide.test.sh`'s three call sites.
Rejected on two counts: (a) it makes `ci` a required status check that verifies nothing — the
"green harness pinning that an instruction exists" shape rule 16 warns about, now wired into branch
protection; (b) it leaves the `Decide CI tier` step producing an output no step consumes, the
producer-without-consumer defect rule 17 records this repository shipping three times. It also
leaves nine of sixteen guards green against a file with no mechanism in it.

**Move the loop the other way: `ci.yml` keeps the glob, `shell-tests` becomes union-only.** This is
superficially attractive — the glob needs no hand-maintained list, so ~35 registration assertions
and CI1 itself become unnecessary. Rejected: it breaks ADR-0151 §D8's stated topology, PS11's
byte-for-byte pin, `pairs-completeness.test.sh`'s CI0/CI0b/CI1/CI2, and ~35 per-harness
registration assertions — roughly 40 assertions against D3's 16, to reach the same single-runner
end state. And it discards ADR-0113's completeness check, which is the mechanism that made the
redundancy visible in the first place.

**Rewrite the sixteen guards in place to assert the new contract.** Rejected: sixteen new needles
is sixteen new chances to pin nothing, and the current set demonstrates the hazard is real (nine of
sixteen already match a comment). One assertion in the file that owns the question, with a
denominator guard, is strictly stronger and is checkable by reading one block.

**Deduplicate by having `ci.yml` run only harnesses absent from `docs-ci.yml`'s list.** Rejected: by
CI1 the sets are identical by construction, so the job would be permanently empty — a check that
runs nothing, dressed as a check that runs something.

## Consequences

### Positive

- **D1 alone: 970 of 2567 measured billed minutes removed (37.8%), already in effect.** D2+D3
  would remove a further 182 (7.1%), for 1152/2567 (44.9%) total — projected ~12 800 → ~7 100
  min/month.
- (Once D2-D4 land) The harness suite runs in exactly one place, and CI3 keeps it that way. A
  future duplicate is a red assertion, not a billing surprise six weeks later.
- (Once D2-D4 land) Sixteen assertions that read as load-bearing and were not are gone, with a
  comment at each site saying so. Nine of them could not have failed against a broken mechanism;
  that class is removed rather than relocated.
- (Once D2-D4 land) A false claim is deleted: this repository's `ci.yml` documented itself as an
  instantiation of a template it stopped matching, parameterised by a `.claude/test-cmd` that does
  not exist.
- `workflow_dispatch` (D1, in effect) gives on-demand full validation of `main` — a capability the
  repository did not have before, at zero standing cost.
- (Once D2-D4 land) The required-context set shrinks to three checks that all verify something.

### Negative

- **`main` is no longer validated end-to-end after a merge (D1, in effect).** With `strict: false`
  and ADR-0127 §D4's fork-from-prep topology this is a real exposure, not a theoretical one.
  Detection moves to the next PR's run, where it is attributed to the wrong change. The mitigation
  is a manual `workflow_dispatch`, which someone has to remember to run.
- **This does not bring the repository under the free allowance**, even with D2-D4. ~7100
  projected min/month against 3000. The residual is named in §D4 and needs its own issue.
- **A branch-protection change is required (D2)** and cannot be scripted away as part of the code
  change. Between merging that PR and updating protection, `ci` is a required context with no
  producer and every PR is unmergeable. The ordering is a human gate with a stated sequence, not a
  detail.
- **`ci-tier-workflow-decide.test.sh` would lose a third of its population (D2).** It executed the
  `Decide CI tier` body from three real call sites; two would remain. The coverage is genuinely
  reduced, and its CTW0 message must stop saying "all three" — a wording that would otherwise be a
  lie in a passing assertion.
- **The `push` arm of the `Decide CI tier` bodies is already dead in production after D1.** No
  Decide-carrying job runs on `push` after D1. Its test coverage (CTW2) still executes it, so the
  code stays tested but nothing reaches it live — a producer/consumer asymmetry (rule 17) that is
  retained deliberately, with a comment, because `workflow_dispatch` and any future re-enabling of
  `push` both need it and because deleting it would fail CTW2 for no gain.

### Neutral

- `staging/project-templates/ci/ci.yml` is untouched (D2, when implemented); ADR-0022 §D8's
  contract for target repos is unaffected, as are `secret-dep-gate.test.sh`'s F5/F6, which assert
  against the template.
- ADR-0151's sharding, its baseline pass and §D10's cost trade-off are untouched by instruction.
- `required-checks-audit.test.sh`'s R-block fixture would be re-recorded, not corrected, when D2
  lands: the 2026-08-01 snapshot stays as the historical record and a dated 2026-09-06 snapshot is
  added beside it (rule 14).
- TODO.md's VCS-029 (a stacked PR whose base is not `main` runs zero checks) is neither fixed nor
  worsened by D1; it is a different consequence of the same `branches: [main]` filter and is named
  here only so the two are not read as one.

## References

- Actions API measurement, 2026-09-06: 306 jobs across 80 runs created since 2026-09-01, billed at
  `ceil(seconds/60)` per job.
- Branch protection, live 2026-09-06:
  `{"contexts":["markdownlint","links","ci","shell-tests"],"strict":false,"linear":false}`.
- Harness-set derivation, 2026-09-06: 102 names in `docs-ci.yml`, 102 files on disk, 0 unique
  either side.
- ADR-0180 §Decision (the clause D2 amends), ADR-0151 §D8/§D10, ADR-0127 §D4, ADR-0113 / issue
  #331, ADR-0022 §D8, ADR-0054, ADR-0108 §PC1 (live red evidence in place of an unreachable plant).
- Rules 1, 4, 6, 7, 13, 14, 16, 17, 19 (CLAUDE.md).
