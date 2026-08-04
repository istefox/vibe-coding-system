# SPEC — set-branch-protection.sh unions one context while the audit derives three

Source: GitHub issue #336

## Objectives

1. Reconcile the setter and the audit on what the required status-check set is, or state the
   divergence at both sites with its reason.
2. Make a repo bootstrapped by `set-branch-protection.sh` pass `required-checks-audit.sh` with no
   finding.
3. Never silently widen an existing protection: whatever ships names what it would add before
   adding it.

## Scope

In:

- `staging/plugin/scripts/set-branch-protection.sh` — the union-of-one behaviour.
- `staging/plugin/scripts/required-checks-audit.sh` as ADR-0114 shipped it, as the reference for
  what the live required set is.
- Where the required set belongs: the setter, or the nightly opt-in marker.

Out:

- The audit half. #322 fixed it: `required-checks-audit.sh` derives the live required set and
  verifies every context in it has a producer. It deliberately does not enforce.
- Making `shell-tests` required on `main`. That is a branch-protection action rather than a code
  change, named here as the obvious candidate for whatever set this issue decides on.

## Stack

Documentation and blueprint repository: bash 3.2 scripts plus GitHub Actions workflows under
`.github/workflows/`. Branch protection is manipulated through the `gh` CLI against the GitHub API.

## Architecture

- `set-branch-protection.sh` unions exactly **one** context into whatever is already required on
  the default branch.
- `required-checks-audit.sh` derives the **live** required set and checks each context has a
  producer, taking the union of observed check-runs on the branch HEAD and job identifiers in
  `.github/workflows/*.yml`.
- This repository's `main` requires **three** contexts — `markdownlint`, `links`, `ci`. The other
  two arrived by a route the setter has never known about, which is why pre-flight check 8 could
  name `ci` and be describing a third of the gate.
- `nightly-autopilot` Phase 0 check 8 is the caller that ties the two together.

## Data model

The required status-check context set: a list of context names, live on the branch and derivable
from workflow jobs.

## API / Interfaces

- `set-branch-protection.sh` — writes branch protection. Its callers and their expectations are
  part of what must be measured.
- `required-checks-audit.sh --root <dir>` — a checker; callers branch on its exit code, and its
  `required:` lines carry the live set.

## UI flows

None.

## Edge cases

- **Union-of-one may be deliberate for a brand-new repo with one workflow.** What the setter is
  actually called by, and whether any caller expects the single-context behaviour, must be measured
  before changing it.
- **Deriving the required set from the repo's own workflow jobs means a new job silently becomes a
  merge gate.** Declaring it means a declaration that can go stale. #322 already recorded that a
  declaration disagreeing with live is a stale declaration rather than a lighter gate.
- **The asymmetry may be correct and simply unstated.** R-01 admits "or the divergence is stated at
  both sites with its reason" as a valid outcome.
- **`shell-tests` — the job that runs the whole harness and the plant registry — is not required on
  `main`**, and the audit reports it as `not-required:` on every run.
- **A widening must be announced, not silent**: whatever ships names what it would add before
  adding it.
- **"Did not run" must stay distinguishable from "found nothing"** (exit 3).

## Success criteria

- [ ] R-01 — the setter and the audit agree on what the required set is, or the divergence is
  stated at both sites with its reason.
- [ ] R-02 — a repo bootstrapped by the setter passes `required-checks-audit.sh` with no finding.
- [ ] R-03 — no existing protection is silently widened: whatever ships names what it would add
  before adding it.
