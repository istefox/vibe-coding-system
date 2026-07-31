# ADR-0099 — The HITL audit trail was written by nobody, and the gate that most needed it had no slot

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #238 (found by the Phase 7.1 shakedown run at Gate 4)
- **Related:** ADR-0028 (which gave `manifest-set-gate.sh` an exit-4 contract while it had no
  callers), ADR-0097 (#237, the same gate, a different defect), ADR-0022 (nightly roadmap mode, the
  reason `autopilot: true` is ambiguous), ADR-0078 (do not fail historical records for a change they
  predate), ADR-0076 (why a status invariant would be the same trap)

## Context

Two defects in one subject. Fixing either alone leaves the other making it useless.

**Part A — `manifest-set-gate.sh` had no instructed call site.** Measured across the whole of
`staging/`, the string appeared in five places: the helper declaration, the script, its `PAIRS`
entry, a hook that logs the call *if it ever happens*, and the harness. **No step, gate or branch of
the chain ever called it.** Correct, tested, deployed, unreachable — the third instance of that
shape this month, after #173 (a pre-flight asserting a state nothing produced) and #248 (a legal
transition whose only producer sat behind a default-off flag).

**Part B — the template had no Gate 4 slot.** Gates 1, 2, 3 and 5, so
`manifest-set-gate.sh <m> 4 approved` exited 3 with `gate '4' not present` — the script behaving
correctly on a template that does not describe the chain.

### The measurement, which is also the baseline

164 gate entries across 41 manifests: **39 approved, 125 pending**. The distribution is bimodal
rather than gradual — four manifests at 4/4, two at 2/4, thirteen at 1/4. **That is not gates being
answered differently. It is orchestrators remembering differently.**

`manifest-validate.sh` invariant 9 counts entries and never reads their status, so a manifest whose
entire audit trail is `pending` validates clean. The trail passed the check by existing.

### Why Gate 4 is the one that mattered most

Its answer can set `autopilot: true`, which drives five downstream gates to their safe defaults. And
**that flag is ambiguous by construction**: `project-conductor`'s nightly roadmap mode sets the
identical `true` with no human at Gate 4 at all (ADR-0022). Reading a manifest afterwards,
`autopilot: true` cannot distinguish a human choosing unattended implementation from a roadmap
pre-authorising the whole run. The field that disambiguates it is the one that had no slot.

## Decision

### D1 — A `gate: 4` slot labelled `implementation_mode`, and `notes` carries the chosen option

`implementation_mode` rather than `session_boundary`, because after ADR-0097 the gate asks two
things and what is worth recording is which cell was chosen. That option name in `notes` is the only
thing that separates the two readings of `autopilot: true` afterwards.

### D2 — The recording rule is defined once and referenced at each gate

Same shape as ADR-0071's Gate 4.0: one `#### Gate approval recording` block, referenced by gates
1–5. A rule stated in five places drifts in five places.

Exit 3 (no slot) is reported and the chain proceeds, rather than halting: a missing audit line is
not a reason to stop a chain a human is standing in front of, and every manifest created before this
ADR will return it for gate 4.

### D3 — No status invariant, and the reason is the issue's own

A chain legitimately sits at `pending` mid-run, and a completed chain with a pending Gate 5 is a
real state — the `step_6_review → completed` direct close skips it. Any status check would have to
be conditional on `current_step`, which is ADR-0076's rule and the same trap. `H7` pins the absence.

### D4 — Invariant 9's minimum stays 4 with five slots written

It is a **minimum**. Raising it to 5 fails all 41 historical manifests for a change they predate —
ADR-0078's rule, applied to a count instead of a path. That the template writes five is asserted
against **the template**, in the harness, not against every manifest ever produced.

## What planting found that reading did not

**`min_gates=4` was assigned twice, and the first assignment was dead.** A bare `min_gates=4` sat
above a `case` whose `*)` catch-all overwrote it on every path. Discovered by planting a raised
minimum on that line and watching **nothing change** — which is precisely how a future edit meaning
to raise it would fail: silently, and while looking correct. The dead line is removed and the
surviving arm carries a note saying which one to edit.

**Two plants did not fire on the first attempt, and neither was a weak assertion.** The
`min_gates` one is above. The other replaced the Gate 4 disambiguation sentence by literal string —
but the same sentence appears twice and one of them **wraps after the word "cannot"**, so the
literal matched one site and the surviving one still satisfied the assertion. Re-planted with a
wrap-tolerant pattern, it fires.

**The rule: a plant needle must be wrap-insensitive for the same reason an assertion needle must
be.** Otherwise a failed plant reads as a weak assertion and gets "fixed" in the wrong place. This
is the seventh member of the decoration family in this repository and the first on the plant side.

## Verification

14 assertions in `hitl-gate-audit-trail.test.sh`, plus a `Z1` floor. Harness 60/60. The manifest
under test is produced by **running** `manifest-init.sh`, not by a hand-written fixture.

Seen RED against the unmodified tree: **7 of 14** — `H1`, `H2`, `H3`, `H4` (reproducing
`manifest-set-gate: gate '4' not present` exactly), `H5`, `H6`, `H6b`. `H7`, `H8`, `H8b`, `H9` and
`H3b` pass before and after: they are the guards that the fix must not break, and `H9` derives the
39/164 baseline rather than quoting it.

| plant | fires |
|---|---|
| gate 4 slot removed from the template | `H1`, `H2`, `H3`, `H4` |
| gate 4 relabelled | `H3`, and `H4` on the label check |
| the recording rule defined twice | `H5` |
| the disambiguation removed from **both** sites | `H6b` |
| invariant 9's `*)` arm raised to 5 | `H8b`, naming a historical manifest |

## Consequences

- **This ships an instruction, not an enforcement** (ADR-0047 / ADR-0048's distinction). Nothing
  makes an orchestrator call the helper. What changes is that there is now something to call, at a
  named place, for every gate. The 39/164 baseline is on the record so a later run can say whether
  it worked.
- **Every manifest created before this ADR returns exit 3 for gate 4.** Expected, reported, not
  fatal.
- **The trail records what the orchestrator says happened**, which is a self-report — the same class
  of evidence ADR-0047 §A3 refuses to gate on. It is a record, never a gate, and nothing here
  changes that.
- Express and Hybrid have their own gates (`gate_e3_verify`, `gate_h1_spec_review`,
  `gate_h3_verify`) and the same question applies to them. Measured on the Standard path only, and
  left there deliberately: their slot counts are different and their branches are elsewhere.
- Removing the dead `min_gates=4` changes no behaviour today; it removes a line that would have
  absorbed a future edit.
- Inert until sync.
