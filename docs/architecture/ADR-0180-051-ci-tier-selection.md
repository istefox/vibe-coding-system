# ADR-0180 — `VCS-051`: plant-registry-derived CI tier selection

- **Status:** Accepted
- **Date:** 2026-08-29
- **Builds on:** ADR-0108 (the plant registry, and rule 16's "an instruction is not an
  enforcement" — the reason this classification lives in shell, not in a workflow `if:`),
  ADR-0151 (sharding the plant registry across matrix jobs, the job whose cost this change makes
  conditional), ADR-0037's "skip CI entirely and let the user check manually" rejected
  alternative (the shape this change explicitly does not repeat).

## Context

`docs-ci.yml`'s `plant-shard` job runs the full plant registry — four matrix legs, ~10-15 minutes
each — on every pull request and every push to `main`, including a pull request that touches
nothing but prose. `ci.yml`'s `ci` job runs the entire harness suite the same way. Neither
distinguishes a documentation-only change from one touching code the registry actually verifies.

**Why a hand-written path filter (`docs/` is prose, skip the heavy jobs) was rejected before it
was written.** Measured against this repository directly: the plant registry declares **100**
distinct targets, of which **11 live under `docs/`** — including `docs/chain-decisions.md` and
`docs/chain-decision-index.md`, the two files this very ADR is about to edit. A path-prefix rule
would silently skip the registry's own verification targets the moment a docs-only PR touched one
of them, which is exactly the failure mode rule 7 (guard the denominator) and rule 18 (a scan
satisfied by the wrong population) both name.

**Why this cannot live only in the workflow YAML.** `plant-check.sh`'s own `--require-legs` block
states why `.github/` is copied into the plant-check sandbox for tests to read but is "not a
legal plant TARGET": rule 16 — "logic that lives only in yaml can be asserted to exist and never
to work." A tier-selection rule expressed purely as a workflow `if:` condition could be documented
and could rot silently; nothing would ever prove it still classifies correctly. The rule therefore
has to live as ordinary, plantable shell — `staging/plugin/scripts/ci-tier.sh` — with the workflow
YAML doing only what YAML can safely do: read the script's output and gate steps on it.

## Decision

**Add `ci-tier.sh`, a CHECKER (rule 5) with two subcommands, derived from the plant registry
itself, never from a hand-written path heuristic:**

- `--classify <changed-files-file>` — one repo-relative path per line. Prints `TIER:
  docs|standard|full` and one `PLANT-MATCH: <path>` line per changed file that is a declared
  plant target. The rule, applied to the changed-file set:

  ```
  changed intersect plant-targets                               != {} -> full
  else changed intersect (staging/** union .github/** union .claude/**) != {} -> standard
  else                                                                        -> docs
  ```

  Exit 0 on success, 2 on bad invocation, **3 on DID-NOT-RUN** — an unreadable registry
  directory, an empty derived plant-target set, or a declared plant-target path that fails to
  resolve on disk. Rule 4: "did not run" is not "found nothing." Callers MUST treat exit 3 as
  tier `full`, never silently as `docs` or `standard`.

- `--resolve <requested-tier> <computed-tier>` — always exits 0, prints the stricter of the two
  tiers as `TIER: <effective>`, and notes `DOWNGRADED-BY-REQUEST` on stderr when the request
  asked for something cheaper than the computed floor. A human (or a `CI: <tier>` commit trailer)
  can ask for more than the computed floor, never for less.

**Gate STEPS, never whole jobs**, in both workflows, via the `id:`/`outputs:` opt-in pattern
`staging/project-templates/ci/ci.yml`'s security-audit/licence-scan jobs already use:

- `docs-ci.yml`'s `plant-shard` job gains a `Decide CI tier` step; its `Run the plant registry`
  step is gated `if: steps.decide.outputs.tier == 'full'`.
- `docs-ci.yml`'s `shell-tests` job gains its own, independently-computed `Decide CI tier` step
  (not a `needs: decide` dependency — `plant-registry-parallel.test.sh`'s PS11 pins this job's
  `needs: [plant-shard]` line byte-for-byte and it must not gain a second entry); its harness-loop
  body is wrapped `if [ "$TIER" != "docs" ]`, and the three plant-union steps (Download/Require/
  Evaluate) are gated `if: steps.decide.outputs.tier == 'full'`, with a new step printing an
  explicit `::notice::` when they are skipped.
- `ci.yml`'s `ci` job gets the same `Decide CI tier` step and the same `if [ "$TIER" != "docs" ]`
  wrap around its test loop, preserving the literal glob line
  `for t in staging/plugin/scripts/tests/*.test.sh` that `precompact-occupancy.test.sh`'s XH2
  pins.

Each `Decide CI tier` step independently re-derives the changed-file set from the event's own
base/head SHAs (a targeted, bounded `git fetch` against the default shallow checkout — the same
pattern `project-templates/ci/ci.yml`'s dependency-scan step already uses), calls
`ci-tier.sh --classify`, reads a `CI: <tier>` trailer from the actually-authored commit message
(`HEAD^2` for a `pull_request` event, since the checked-out HEAD is a synthetic merge commit whose
own message is never the human-authored one), and calls `ci-tier.sh --resolve` to combine the two.
Every failure path — an unresolved base SHA, a `--classify` exit 3, a missing trailer — resolves
toward `full`, never toward `docs`.

**`commit/SKILL.md` gains `### Step 3.7 — Recommend CI tier`**, between the existing Step 3.6 and
Step 4, using the same `ci-tier.sh --classify` call (via a `CI_TIER_SH`-overridable, testable
fence) to compute the tier before Step 4's approval gate. Attended: `AskUserQuestion` with the
computed tier first, labelled `(Recommended)`. Under `--autopilot`: auto-applied, one line printed
("CI tier: `<tier>` (autopilot — auto-applied)"). Either way the `CI: <tier>` trailer is appended
to the commit message Step 3 already drafted, so the human approves the trailer they will get,
never one added silently after Step 4's click.

## Alternatives considered

- **Skip CI entirely on a docs-only diff (job-level `if:`).** Rejected on the same grounds
  ADR-0037 already rejected "skip CI entirely and let the user check manually": a check that does
  not run must never look, from the outside, like a check that ran and found nothing. Gating at
  the STEP level (not the job) means the job still reports, with an explicit `::notice::` stating
  why the heavy work was skipped — the job never silently vanishes from the required-checks list.
- **A hand-written path-prefix heuristic (`docs/**` -> skip).** Rejected — the 11-of-100 measured
  overlap above. `docs/` is not uniformly prose from the registry's own point of view.
- **A shared `decide` job with `needs: decide` fanning out to the other jobs.** Rejected because
  `plant-registry-parallel.test.sh`'s PS11 pins `shell-tests`' `needs: [plant-shard]` line
  byte-for-byte; adding a second dependency would break a passing, deliberately narrow assertion
  for a cost (a handful of duplicated git commands per job) that is not worth the churn. Computed
  independently per job instead — cheap, and every job reads the same commit so every job lands
  on the same tier regardless.
- **Trusting the computed tier over an explicit request, or vice versa, unconditionally.**
  Rejected in favor of a floor: `--resolve` always returns the stricter of computed and requested.
  A human can ask for more scrutiny than the registry computed; nothing can ask for less than what
  the registry says is required.

## Consequences

### Positive

- A documentation-only PR no longer pays for four ~10-15-minute plant-shard legs it cannot
  possibly need, without a hand-maintained path list that would drift from the actual registry.
- The classification rule is ordinary, plantable shell (`ci-tier.sh`), covered by
  `ci-tier.test.sh` and by the CT-DENOM plant declared there — the exit-3 denominator guard is
  proven to fire, not merely documented to exist.
- The human sees and approves the tier at commit time, via Step 3.7's `AskUserQuestion`, before
  Step 4's gate — never a silent CI behavior change discovered only from the Actions tab.

### Negative, stated plainly

- Three near-duplicated `Decide CI tier` step bodies now exist (`docs-ci.yml` x2, `ci.yml` x1) —
  accepted per rule 6 (extract only when two copies answering the SAME question would be a
  defect): these read the same commit and must reach the same tier, but PS11's pinned
  `needs: [plant-shard]` substring rules out sharing via a `needs:` job, and GitHub Actions has no
  cross-workflow step-body include.
- The base-SHA/merge-base resolution inside each `Decide CI tier` step could not be exercised
  against a live GitHub Actions runner in this change — verified by careful reasoning through the
  shallow-clone and synthetic-merge-commit mechanics, and every unresolvable-base path was built
  to fail toward `full`, but this specific piece needs a live PR run to confirm empirically.
- `--paths`/`--paths-ignore` trigger-level filtering, the markdownlint/links jobs, `VCS-029`
  (stacked-PR base-branch check gap), and `docs-ci.yml:46`'s shard-count comment are explicitly
  out of scope for this change.

## Correction (2026-08-30)

The trailer-read half of each `Decide CI tier` step shipped with a latent bug on `pull_request`
events: `HEAD^2` (meant to reach the real PR head commit past the synthetic merge commit
`actions/checkout` produces) cannot resolve under the default shallow checkout (`fetch-depth` 1,
no parent commits fetched), so the read silently failed and fell back to the merge commit's own
auto-generated message — `REQUESTED` was always empty, `full` on every PR regardless of the
declared trailer. Confirmed live on PR #533 and #534 (`computed=docs requested=full
effective=full`); the trailer itself was written correctly both times. Filed as VCS-053, fixed by
reading `git log -1 --format=%B "$PR_HEAD_SHA"` instead of `HEAD^2` — the same absolute SHA the
step already fetches and validates earlier in its own body for the changed-file diff, so no
checkout-depth or fetch-pattern change was needed. New `ci-tier-workflow-decide.test.sh` extracts
and executes each of the three call sites' `run:` bodies against fixture git sandboxes rather than
grepping their text, closing the test-class gap this ADR's own "Negative, stated plainly" section
flagged only generically (as unverified base-SHA/merge-base resolution, never naming the trailer
read specifically as sharing the same shallow-checkout exposure).
