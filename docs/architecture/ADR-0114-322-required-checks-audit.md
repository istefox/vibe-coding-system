# ADR-0114 — A pre-flight that verified a third of the merge gate, and verified it in prose

- **Status:** Accepted
- **Date:** 2026-08-01
- **Issues:** #322 (closes) — the last of the Phase 10.0 chain blockers
- **Amends:** ADR-0022 §D8 (pre-flight check 8) and the morning-report schema's `ci_status`
- **Related:** ADR-0076 (a fact about the INPUT is not a fact about the ENVIRONMENT), ADR-0083
  (a fence that can abort declares itself and is executed), ADR-0090 (inspect what a plant
  produced), ADR-0108 (the plant registry), ADR-0110 (a pre-flight refuses the unknown),
  ADR-0113 (the CI harness list, found in the same session)

## Context

`nightly-autopilot` pre-flight check 8 exists so a night of unattended work ends in PRs a human can
merge in the morning. Its text ended: *"If present, verify the `ci` check is required on `main`."*

`main` requires three contexts. `set-branch-protection.sh` unions exactly **one** into whatever is
already there, so the other two arrived by a route the pre-flight has never known about. A red
`markdownlint` — real, PR #317, this week — therefore surfaced only when the human tried to merge.

## What was measured, 2026-08-01

**M1 — the issue understates it: check 8 had no mechanism at all.** Checks 3 and 6 carry
`fence-contract` bash blocks. Check 8 was **prose**; grepping `staging/` for a protection API call
returns exactly one hit, inside `set-branch-protection.sh`. It did not verify one context out of
three — it verified nothing, and nothing had ever executed it.

**M2 — the live protection, confirmed:** `contexts: ["markdownlint","links","ci"]`, `strict: false`.

**M3 — every required context has a producer, and one producer is not required.** Check-runs
observed on `main` HEAD: `ci`, `links`, `markdownlint`, **`shell-tests`**. `shell-tests` is the job
that runs the whole harness and the plant registry, and it is **not a required check**: the merge
gate this repository's entire discipline rests on does not include the harness.

**M4 — the morning report's `ci_status` is a single value** (`ADR-0022-morning-report-schema.md`),
reconciled by one `gh pr checks` pass. With three required contexts, a red one has nowhere to appear.

## Decision

### D1 — The authority is the live required set, derived; never a list declared in the marker

The two options fail in opposite directions and the issue asked for a reason, not a preference.
**The live set is what actually blocks the morning merge**, so a declaration cannot lower it: a
declared list that disagrees with live is a stale declaration, not a lighter gate.

The declaration option's real value — *a silently-added required check should be a FINDING, not a
requirement the run adopts* — is preserved by answering it with **satisfiability** instead. A
required context nothing produces aborts pre-flight; one a workflow does produce is genuinely
satisfiable, and the run adopting it is correct. Nothing is lost and no configuration field is
added that can drift.

### D2 — `required-checks-audit.sh` is a CHECKER with five outcomes, and three of them mean
"nothing was found to be broken"

```
0  PASS                every required context has a producer
0  NO-PROTECTION       the branch has none — nothing blocks a merge (R-04)
0  NO-REQUIRED-CHECKS  protected, contexts list empty — a DISTINCT token (R-03)
1  UNSATISFIABLE       a required context nothing produces (R-02)
2  bad invocation
3  DID-NOT-RUN
```

*Every one was verified*, *there was nothing to verify*, and *nobody could look* are three
different sentences. Collapsing any pair reproduces this feature's own defect one level down —
ADR-0076's line between a fact about the INPUT and a fact about the ENVIRONMENT, drawn twice here
rather than once.

### D3 — Producer evidence is a union of two sources, and the reason is the failure direction

Check-run names observed on the branch HEAD (*it ran here*) unioned with job identifiers declared in
`.github/workflows/*.yml` (*it exists here*). Source 1 alone calls a `pull_request`-only workflow
unsatisfiable on a push-only history; source 2 alone cannot see a check produced by an app.

**Zero evidence from both is `DID-NOT-RUN`, never a verdict.** An empty producer set makes every
context look broken, and the asymmetry decides it: a false PASS costs what the system already had
(nothing verified), a false ABORT costs the whole night.

Step-level `name:` values are deliberately **not** collected — a required context called `Checkout`
must not be satisfied by every checkout step in the repo. Job ids, job display names and the
workflow name are.

### D4 — It reports the reverse direction, advisory, never a gate

A producer that runs and is not required (M3's `shell-tests`). The pre-flight's job is that PRs are
mergeable, not that the gate is as strict as someone would like — but this is the only place that
knows both sets, and a human deciding what to require should be told.

### D5 — Check 8 becomes an executed fence, and `rc=3` aborts

A `fence-contract: nightly-autopilot-check-8` block, in the shape checks 3 and 6 already use,
branching on the exit code. `rc=3` aborts rather than proceeding: distinguishing "could not look"
from "found nothing wrong" exists precisely so this branch can exist, and a pre-flight that starts a
roadmap on an unknown merge gate has verified nothing while printing `PASSED` (ADR-0110's posture).

### D6 — `ci_status` becomes the aggregate over the required set

`red` if any required context is red, `pending` if any is pending, `green` only when all are.
**Byte-identical to today on a repo requiring one check**; correct rather than misleading on one
requiring three. The per-context detail goes in an additive `required_checks` object — no schema
bump, absent entirely on older reports. The set comes from the branch protection, never from
`gh pr checks` output, which lists every check that ran whether required or not: aggregating over
those would let a non-blocking red check report a mergeable PR as unmergeable.

## What the plant registry found, three times, all in the plants rather than the assertions

**`A2`'s plant aimed one line off.** It removed the `note:` header; `A2` greps for
`not-required: shell-tests`, produced by the *next* line. The assertion was fine, and only looking
at the mutated file showed it (ADR-0090). **A plant must remove the thing the assertion READS.**

**`A4`'s fixture ran the wrong way round.** It required `cid` and produced `ci`, and dropping the
`-x` from `grep -qxF` changes nothing there — no producer line contains `cid`. The danger is the
reverse: a required context that is a **substring of a producer**. Required `ci`, produced only
`cid`. Fixture corrected, plant fires.

**Three plants were silently truncated by the declaration syntax.** ` | ` is the field separator
and *"cannot appear inside a field"* — which every shell pipeline contains. `A3` and `C3` reported
as **fired**, from a mutation that was not the one they described: the needle was cut at the pipe
and the replacement became the tail of the needle, producing a nonsense edit that happened to break
the script. **A plant that fires is not evidence until you have seen what it produced.** All three
rewritten with pipe-free needles.

## Consequences

- **The pre-flight aborts on strictly more inputs.** Bounded to a required context with no producer
  and to the audit failing to run — both cases where the run would otherwise open PRs nobody can
  merge, or start on a gate nobody read.
- **A new hard dependency at launch.** The fence executes `~/.claude/hooks/required-checks-audit.sh`
  and aborts if it is absent, naming the sync command. Inert **and worse than inert** until sync —
  the same shape as ADR-0112's, and the correct fail direction for a gate.
- **`ci_status` changes meaning on multi-check repos**, which is where the old value was wrong. A
  reader comparing two reports across this change will see a `green` become a `red` for the same
  PR, and that is the fix, not a regression.

## Recorded, not fixed

- **`shell-tests` is not a required check on `main`.** The audit now reports it every run; making it
  required is a repo-admin action and a human decision, not a code change. It is worth doing.
- **Satisfiable never means "will be green".** Nothing at 21:00 can know whether tomorrow's markdown
  lints; that half is D6's job, at report time. Anyone reading `PASS` as "CI will be green" is
  reading something this feature does not claim.
- **`set-branch-protection.sh` still unions exactly one context.** This audits; it does not enforce.
  Deriving what a repo *should* require is a different feature.
- **The context form `Workflow / job`** that GitHub uses for reusable workflows is not decomposed —
  it would be reported as unsatisfiable unless a check-run of that exact name has been observed.
  No workflow here uses it; a repo that does will see one false abort and a clear message.
- **The `gh` stub in the harness stands in for `gh`'s own `--jq`.** Nothing tests that jq expression;
  the boundary is stated in the test header rather than left for a reader to discover.

## Verification

Live, read-only, against this repository — the script's whole subject is a live API answer, so a
fixture-only verdict would prove nothing about it (ADR-0081's rule applied to the fix):

```
AUDIT: PASS — all 3 required context(s) on istefox/vibe-coding-system@main have a producer
  required: ci
  required: links
  required: markdownlint
  note: produced but NOT required (advisory, not a finding):
    not-required: shell-tests
```

`required-checks-audit.test.sh` 33/33 with a `Z1` floor, nine plants all firing after the three
corrections above, check 8's fence extracted and **executed** in four states.

## References

- Issue #322
- `staging/plugin/scripts/required-checks-audit.sh`
- `staging/plugin/skills/nightly-autopilot/SKILL.md` pre-flight check 8, §4 CI reconciliation
- `docs/architecture/ADR-0022-morning-report-schema.md` — `ci_status`, `required_checks`
- `staging/plugin/scripts/tests/required-checks-audit.test.sh`
