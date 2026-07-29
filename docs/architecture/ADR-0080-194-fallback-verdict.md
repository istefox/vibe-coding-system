# ADR-0080 — The pattern-enforce fallback stays, on a small sample, with the condition for changing it written down first

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #194
- **Extends:** ADR-0016 (the v2.1.154 transcript relocation this measurement depends on),
  ADR-0074 (#127, the audit that found this), ADR-0077 (the direction exemption that pointed here)
- **Measured on:** Claude Code **2.1.220**, macOS. The verdict is build-stamped on purpose.

## Context

`pre-flight-pattern-enforce.sh` reads the **main session** jsonl when a subagent's own transcript
cannot be found, then scans assistant entries and **allows** on a match. A subagent whose transcript
is missing therefore inherits the orchestrator's recent output, and a `PATTERN:` line the
orchestrator emitted — it edits files too — satisfies the check for an agent that declared nothing.

`write-scope-enforce.sh` refuses this exact fallback for itself and explains why **in its own
header**, calling a missed check here acceptable. That was a judgement about a third file, never a
measurement, and the log could not settle it: it recorded `allow  PATTERN found in window` for both
paths. Phase 1 (PR #199) made the two distinguishable with `src=`. This is phase 2.

## Decision

### D1 — The fallback stays

### D2 — What was measured, stated as the small sample it is

A **controlled coder dispatch** made three `Edit`/`Write` calls. All three logged `src=subagent`,
**including the first**.

That refutes the one mechanism that would have made the fallback fire routinely: a **flush race**,
where the subagent's transcript does not exist yet when its first `PreToolUse` fires. It does exist
— the file was born at `19:15:58Z` and the first decision was logged at `19:16:02Z`, four seconds
later. The refutation is a timestamp, not an outcome, which is why one dispatch is enough for that
specific claim.

Supporting evidence, 193 files: both transcript layouts are present on disk under this project —
**137** regular (`subagents/agent-<id>.jsonl`) and **56** under `subagents/workflows/<wf_id>/` — and
both match the hook's two lookups.

**n = 3, Agent-tool path only.** No Workflow dispatch was probed, and that is the path v2.1.154
silently relocated. The residual is real and is stated in the hook's header rather than left to a
reader's inference.

### D3 — Why keep it, given the evidence points to it being dead code

Dropping it converts a rare false **allow** into a rare chain-breaking **deny**, and *fail-open on
every internal error* is this file's stated contract, on line 5, since before any of this.

**The asymmetry with `write-scope-enforce.sh` is real and is not an inconsistency.** That hook's
fallback would be *actively wrong*: it would derive a write scope from the orchestrator's text and
bind every subsequent edit in the session. This one is merely *permissive*. Different failure,
different correct answer — and that sentence now lives in this hook's header, at the site it
describes.

### D4 — The condition for dropping it is PRE-REGISTERED

Written before more data arrives, so the outcome cannot be rationalised afterwards:

- If `src=main-fallback` is **0** across **≥ 50** coder decisions spanning **at least one Workflow
  dispatch** → drop the fallback. It is then dead code whose only possible effect is to fail open.
- If it is **non-zero** → **do not drop it.** Find out why the lookup failed first. A fallback that
  fires is evidence the lookup is broken, and removing it would hide the breakage rather than fix
  it.
- Re-run the probe after any major CC bump.

The second branch is the one worth stating explicitly, because the intuitive reading runs the other
way: "it fires, so it matters, so keep it" and "it never fires, so remove it" are both right here,
but only if the first is treated as a *symptom* rather than as a feature earning its place.

### D5 — The verdict is pinned by assertions, since the number cannot pin it

A verdict reached on n=3 is protected by its reasoning being legible, not by its sample. Section D
of `pattern-enforce-transcript-source.test.sh` asserts the header states the sample size (`D1`),
carries the pre-registered drop condition (`D2`), states the do-not-drop branch (`D3`), and explains
the sibling asymmetry at this hook's own site (`D4`). All four fail against the phase-1 header.

## Alternatives considered

### A — Drop the fallback now

Rejected per §D3. The evidence points that way and does not reach it: one path, n=3, on a substrate
that has moved before. Dropping a fail-open on that basis inverts the failure direction of a live
guardrail.

### B — Keep it and change nothing

Rejected. That is where the question started, with the reasoning living in a neighbouring hook's
header and no way to revisit it. The instrumentation, the verdict, the sample size and the exit
condition are the deliverable — not the word "keep".

### C — Wait for organic data before deciding

Rejected as an indefinite stall. Nothing in the chain was scheduled to dispatch a coder, and the
question had been open since #127's audit. A controlled probe answered the mechanism question in one
dispatch; the rate question stays open under §D4, which is an honest split rather than a delay.

## Consequences

### Positive

- The hook's behaviour is explained at the hook, with a measurement behind it.
- The flush-race hypothesis — the only mechanism that would have made this urgent — is dead, with a
  timestamp.
- The next reader has a rule to apply rather than a judgement to re-form.

### Negative

- **n = 3.** Anyone treating this as "the fallback does not fire" is over-reading it. The header
  says so; this line says so again.
- **The Workflow path is unmeasured**, and it is the one with a history of moving.
- The verdict is protected by prose assertions. `D1`–`D4` check that the reasoning is *present*,
  never that it is *true*.
- No behaviour changed, so nothing here is verifiable by running the hook differently.

### Neutral

- No code change: the header and the test grew, the logic did not.
- No new file, no registry change, no `PAIRS` change.
- `ADR-0077`'s `transcript-scan-exempt` declaration on this hook is updated to point at the decision
  rather than at an open issue. It still ends `Do not read this line as "audited and fine"`.

## Lesson recorded, third of its family

`D2` first failed because the header wraps across comment lines **and** marks `src=main-fallback` as
code, so a needle written in plain prose missed it. The matcher now strips comment markers *and*
backticks before flattening.

ADR-0073 hit the line-wrap form, ADR-0076 the comment-marker form, this one the backtick form. The
general rule: **a prose assertion must not depend on how the text is decorated any more than on
where it breaks.**

## References

- Issue #194, whose four acceptance criteria this closes
- `docs/architecture/ADR-0074-127-self-arming-marker-class.md` §D5 — the audit that surfaced it
- `docs/architecture/ADR-0077-193-transcript-scan-class-guard.md` §D5 — the direction exemption
  that named this as its open residual
- `staging/plugin/scripts/tests/pattern-enforce-transcript-source.test.sh` section D
