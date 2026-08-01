# ADR-0111 — A contained entry failure must cost one feature, not the roadmap

- **Status:** Accepted
- **Date:** 2026-08-01
- **Issues:** #324 (closes), #329 (opened by this investigation)
- **Related:** ADR-0060 (#114 — the marker split this reuses as it stands), ADR-0109 (#319 — built
  the classifier and deferred this policy by name), ADR-0047 §D5 (the weakening halt must stay
  run-level), ADR-0083 (fence contracts), ADR-0086 (extract only when two answers would be a
  defect), ADR-0104 (an assertion covered by two guards isolates neither), ADR-0108 (the plant
  registry, which found the gap this ADR's own harness had)

## Context

`project-conductor` Step 5 branch C wrote the **run-level** `.claude/needs-human` marker whenever a
feature's manifest was missing or in an unexpected state, and `nightly-guard` blocks that publish
and **every subsequent one**. Its stated justification is *"unknown state"* — but the branch never
asked whether the state was actually unknown. One wedged feature in a twelve-feature wave cost the
eleven behind it.

ADR-0060 §D3 drew this exact line eleven days earlier, for a different set of writers: a **known,
contained, per-feature** problem appends to `.claude/nightly-state/skipped-features`, marks the
feature `[~]` in PROJECT.md, and the roadmap continues; a **run-level** problem writes `needs-human`
and everything stops. Before that fix one thin issue silently halted nineteen others. **The same
blast radius survived through a second door**, and #324 is that door.

## What was measured, 2026-08-01

The issue asks for its own claims to be measured first. Seven findings; four moved the design.

**M1 — #319 had already built the classifier this needs, and deferred the policy here by name.**
`concept-to-code/scripts/manifest-entry-state.sh` (ADR-0109, merged and deployed the same day)
carries in its header: *"what an unattended run then does with a non-`ADOPTABLE` answer — per-feature
skip versus run-level halt — is issue #324's subject and is deliberately not decided here."*
`concept-to-code/SKILL.md` step 4b repeated it. So the issue's central question — *can branch C tell
the causes apart from where it stands?* — answers **yes, for the manifest-shaped causes**, and the
token vocabulary already existed. Verified live: the 2026-07-31 orphan classifies
`TERMINAL|step_0_init`; today's path for the same slug classifies `NONE|`.

**M2 — the issue's cause 1 is stale in its stated form.** `manifest-init.sh` exit 2 is no longer how
a same-day collision reaches branch C from inside `concept-to-code`: step 4b intercepts *before*
manifest-init runs, and the collision now surfaces as `ENTRY-ROUTE: TERMINAL` → exit 1. The cause is
real and still reaches branch C. The door changed, and the new door carries a token.

**M3 — but `project-conductor` calls `manifest-init.sh` itself**, in Step 4's `_autopilot=true`
branch, outside #319's guard. That path still returned a bare exit 2 with no token. Cause 1's
remaining door, and the reason `conductor-step4-init-guard` exists.

**M4 — cause 2's evidence is NOT at branch C, so it cannot be classified there.** The conductor's own
comment asserted *"the c2c autopilot pre-flight hard-aborts at Gate 0 for a missing SPEC.md"*.
Measured: it does not. With no SPEC, `gate0-detect.sh` reports `spec_adr_exist=false`, the chain
routes greenfield, and Step 1 dispatches `interview-driver` — **interactive**, on a path with nobody
to answer. The manifest is left at `step_0_init`/`in_progress`, which the classifier reads as
`ADOPTABLE`, indistinguishable from any other mid-flight state. So this cause is settled at Step 4,
where the conductor already knows and already printed a log line about it. That is the issue's own
instruction — *move the classification to where the evidence is* — applied rather than quoted.

**M5 — a third contained cause the issue does not name.** Gate 4.5's autopilot default is
*"Hand-code (abort)"* on a red tracer probe, transitioning `aborted aborted` with the reason recorded
in `tracer_bullet_abort_reason`. Express Gate E3's Abort does the same. Both halted the whole roadmap.
A chain that recorded exactly why it stopped is the clearest possible case of *known and contained*.

**M6 — branch C's own message was wrong on the live case.** It read `current_step` only, so the
committed 2026-07-31 orphan (`status: aborted`, `current_step: step_0_init`) reported *"manifest
state: step_0_init"* — a terminal chain described as early-init. ADR-0109 built the classifier to read
**both** fields for precisely this; ADR-0076 §THE RULE forbids the bare read that produced it.

**M7 — the split preserves ADR-0047 §D5 with no special case.** A weakening halt never transitions,
so it stays `step_5_implementation`/`in_progress` → non-terminal → still a run-level halt. The token
rule gives that for free, which is a property of the rule rather than a carve-out in it.

## Decision

### D1 — Branch C classifies before deciding, and the token alone decides

Read the state through `manifest-entry-state.sh`, never a bare `grep current_step`:

- **exit 3** → `needs-human`, halt. A check that did not run is not a clean result.
- **`TERMINAL`** → contained: append the reason to `skipped-features`, mark `[~]`, continue to Step 2.
- **everything else** (`NONE`, `ADOPTABLE`, `BOUNDARY`, `RESUMABLE`, `LATE`, `UNRESUMABLE`,
  `UNKNOWN`, `UNREADABLE`) → `needs-human`, halt, exactly as before.

`completed` never reaches branch C — branch A takes it first — so `TERMINAL` here means `failed` or
`aborted`, by either field.

### D2 — No timestamp discriminator, and that is a decision rather than an omission

A first draft compared the manifest's age against the `nightly-state/active` marker, to separate *a
previous run's terminal manifest* from *this run's chain aborted*. Rejected: both are **decided ends**
with the reason recorded in the manifest, and neither leaves half-written state. What leaves an
undecided state is a crash, and a crash leaves a **non-terminal** manifest, which D1 already halts on.
So the extra comparison buys nothing and costs a new failure mode — `git checkout` rewrites mtimes.

**Residual risk, stated rather than hidden:** a chain that aborts because something is wrong with the
*run* rather than the feature would now be skipped instead of halting. Bounded, because every
run-level condition `nightly-guard` reads (`needs-human`, `rtf-blocker`, `token-budget`) is written by
its own writer, independently of branch C, so a genuine run-level problem still halts through its own
door.

### D3 — The missing-SPEC case is settled at Step 4 and never reaches the chain

Per M4. The conductor writes the skip note, marks `[~]`, and **does not invoke `concept-to-code`**.
Running a chain you already know will not complete, in order to classify the wreckage afterwards, is
strictly worse than not running it — and after M4 the wreckage is not even classifiable.

The sentence *"treat that as a feature-level skip in Step 5C"* is deleted. It routed a decision to a
branch that had no mechanism to act on it, which is the producer/consumer shape #173, #248 and #319
each recorded in turn.

### D4 — The conductor's own `manifest-init.sh` call is guarded with the same classifier

Per M3. Same script, same tokens, one step earlier. `ADOPT` means update the existing manifest in
place; calling `manifest-init.sh` there is the bare exit 2 the guard exists to stop.

### D5 — No new marker file, no new script (R-04)

ADR-0060 §D3's mechanism is reused byte-for-byte: same file, same append-only shape, same `[~]`
convention, and `nightly-guard.sh` goes on never reading it. `features_skipped[]` in the morning
report picks the new entries up with no schema change (**R-03**), because the report reads the file
rather than a list of writers.

The `[~]` mark is written with an **exact-match `awk`**, never a `sed` regex: a feature title is
arbitrary GitHub text and can carry any metacharacter or delimiter.

### D6 — Three declared fence contracts, all executed

`conductor-step4-nospec-skip`, `conductor-step4-init-guard`, `conductor-branch-c-entry-classify`.
All three are abort-capable in the sense that matters — they decide whether a roadmap continues — and
under ADR-0083 a declared contract must be run by a test, not described by one. `bash -n` on each is
section A; F4 of `fence-contract-coverage.test.sh` now counts 24 contracts, all executed.

## What the plant registry found

Seventeen plants were declared and **sixteen fired**. `B9` — *a missing classifier is exit 3 and
writes neither marker* — did not.

Inspecting what the plant actually produced (ADR-0090's rule) showed why: the fence guards
"did not run" **twice**, once on the file being absent and once on the classifier exiting non-zero,
and B9's fixture deleted the file, so the first guard exited before the line the plant had modified
could run. The assertion was real and the plant was aimed at a path it could not reach — **an
assertion covered by two guards isolates neither** (ADR-0104, met again). Fixed by splitting into
`B9` (missing file, planted against the file guard) and `B9b` (a classifier that exists and fails,
planted against the exit-code guard). Eighteen plants, all firing.

`W8` was corrected before planting, and it is the more embarrassing one: its needle was
`manifest-entry-state.sh`, the script's **name**, which also appears in the `_mes=` assignment — so
deleting the invocation would have left it green. Rule 12, in the assertion written to guard the very
mechanism it names, on the same day this repository recorded five instances of it.

## Consequences

- **A run-level guard now passes on strictly more inputs**, bounded to one token. The first nightly
  run after this deploys may continue past a feature it would previously have halted on, which will
  look like a regression the first time.
- **This ships an instruction, not an enforcement.** Every gate here is prose in a SKILL.md a model is
  asked to follow. The harness pins that the fences exist, parse, and behave; nothing pins that the
  orchestrator runs them.
- **Inert until sync, and worse than inert for branch C**, whose fence exits 3 when the classifier
  does not resolve — so an un-synced machine halts rather than mis-routing. All five changed files
  carry `PAIRS` entries.
- `plan-tasks.sh`-style value-domain drift is not possible here: the tokens are derived from
  `manifest-entry-state.sh` at run time by that script, not copied into the conductor.

## Recorded, not fixed

- **Gate 0 has no `[Autopilot default: …]` block** (only Gate 0d does among the Gate-0 family), so on
  an unattended path it raises an `AskUserQuestion` nobody can answer, and the `[auto]` option's
  SPEC.md pre-flight — the check the conductor's own comment claimed fires — is never reached. Found
  while tracing M4. Filed as **#329**: what the safe default *is* needs its own decision, and changing
  it moves the behaviour of every unattended chain at its first gate.
- **The conductor's manifest lookup globs `????-??-??-<slug>` across all dates** and takes
  `ls -t | head -1`, so a manifest from a previous day can be read as this run's outcome. Pre-existing
  and orthogonal; Step 0's reconciliation absorbs the most dangerous instance (a stale `completed`)
  before Step 5 is reached, which is why it has not bitten yet.
- `B3` asserts a contained skip leaves `build-status` alone. That matters because `publish-feature.sh`
  reads it, and a skip that wrote `RED` would poison the next feature's publish while `needs-human`
  stayed absent — a halt with no marker naming it. Nothing else in the system asserts that coupling.
