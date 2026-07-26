# ADR-0058 — Context-occupancy instrumentation and a `PreCompact` guard

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #112 (thirteenth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/112-context-occupancy-precompact.spec.md`
- **Builds on:** ADR-0021 (chain-memory hook) and `session-context-inject.sh` for the
  externalisation half, which is already done well.
- **Closes:** gap **G-19** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (PARTIAL, P2).

## Context

`staging/user/settings.json:4` sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: 70`. That is a compaction
**threshold**, not a measurement. No `PreCompact` hook is wired; the event does not appear in the
hooks block at all.

The externalisation half of the Memento method is in good shape — `session-context-inject.sh`, the
manifests, the ADR-0021 chain-memory hook. What is missing is measurement and a guard. Occupancy is
not observable per agent or per turn, so it cannot be a gate input, and auto-compaction can fire in
the middle of a tricky operation.

**The threshold is not the protection, and the spec's own evidence says so:** its documented
instruction violation happened at **50%** occupancy — comfortably below our 70% setting. Lowering
the number would not have prevented it. That is why this feature adds measurement and a guard rather
than tuning the threshold.

## Decision

### D1 — A `PreCompact` hook that forces the handoff write before compaction

When the manifest's `current_step` is in a dispatch state, the hook writes (or forces the write of)
the handoff record first, so a compaction that proceeds cannot lose mid-flight chain state. That is
the spec's requirement C3.

### D2 — The refusal is ONE-SHOT, and this is the decision that keeps the hook from being harmful

A `PreCompact` hook that can refuse repeatedly is worse than no hook at all. Compaction exists
because the context is full; refusing it indefinitely does not preserve the session, it strands it —
the window fills, nothing can be evicted, and the run dies holding the state it was trying to
protect.

So: **refuse at most once per compaction cycle.** The first refusal buys exactly enough time to
force the handoff write (§D1). The second attempt proceeds regardless of manifest state. State for
the one-shot lives in a state dir alongside the other hooks' audit logs.

The failure this prevents is the one this codebase should expect by now — a guard whose success
condition is "block" and which therefore blocks forever when something upstream is wrong.

### D3 — Fail open on every error, as every hook here does

No manifest, unreadable manifest, missing `jq`, unwritable state dir, malformed JSON → allow the
compaction. Same posture as `stop-gate.sh`, `pre-flight-pattern-enforce.sh`,
`agent-command-scope.sh` and `db-backup-guardrail.sh`, and for the same reason: a wrongly-firing
refusal strands a session, which is a worse outcome than a compaction that loses recoverable state.

Note the interaction with §D2: fail-open covers *errors*, one-shot covers *correct operation*. Both
are needed. A hook that only failed open would still hang a healthy session in a refusal loop.

### D4 — Occupancy is measured and reported, not gated on

The `Stop` hint is extended to report occupancy, and the figure lands where a human and a later gate
can read it. It does **not** become a blocking condition.

The reason is the 50% evidence above: occupancy correlates with instruction-following degradation
but does not determine it, so a threshold gate would be a heuristic — and this roadmap has now
established three times (ADR-0051 §D2, ADR-0053 §D2, ADR-0054 §D5) that heuristics report and
mechanical facts gate. Occupancy is a heuristic. It reports.

### D5 — Measurement must not itself be a second source of truth

The occupancy figure comes from what the runtime already exposes, not from a parallel token count
maintained by this system. A second counter would drift from the real one, and a drifting number
that looks authoritative is worse than no number.

## Alternatives rejected

- **A1 — Refuse compaction until the chain step completes.** Rejected under §D2: strands the
  session. This is the naive reading of the requirement and it is actively harmful.
- **A2 — Lower `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`.** Rejected: the documented violation happened at
  50%. Tuning the threshold treats a symptom the evidence says is not the cause.
- **A3 — Gate on occupancy.** Rejected under §D4 — it is a heuristic, and heuristics do not gate
  here.
- **A4 — Maintain an independent token counter.** Rejected under §D5.
- **A5 — Fail closed, since the spec's §10.4 says hooks should.** Rejected: ADR-0054 §D1 already
  established that the posture belongs to the caller, and this caller is a hook with an agent
  present, which is the fail-open side of that split.

## Consequences

### Positive

- Mid-flight chain state survives an auto-compaction that fires at an inopportune moment.
- Occupancy becomes observable, which is the precondition for any later decision about it.
- No threshold tuning, so no false confidence from a number the evidence does not support.

### Negative, stated plainly

- **One-shot means the guard can be defeated by timing.** A compaction that fires twice in quick
  succession gets through on the second attempt by design. That is the correct trade against
  stranding, and it is a real hole.
- **Occupancy reported and not gated** means nothing acts on it automatically. Like ADR-0051's
  advisory findings, its value depends on being read — and ADR-0052 §D5 already recorded that Gate
  5's advisory load is the live risk. This adds to it.
- **`PreCompact` behaviour is runtime-defined** and could change under us, exactly as the workflow
  subagent transcript layout did at CC v2.1.154 (ADR-0016). The hook should be re-verified after a
  major Claude Code bump rather than trusted indefinitely.
- Fail-open (§D3) means a broken hook is a silent no-op, which is the standing trade for every hook
  in this system.
