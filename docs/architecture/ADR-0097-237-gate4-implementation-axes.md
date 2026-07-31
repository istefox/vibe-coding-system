# ADR-0097 — Gate 4 offered two cells of a four-cell decision, and contradicted itself in the same box

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #237 (found by the Phase 7.1 shakedown run at Gate 4)
- **Related:** #227 (the same family, one gate earlier — see §D4), ADR-0071 (Gate 4.0, the producer
  a fourth branch must not skip), ADR-0068 (why coder isolation does not depend on the session),
  ADR-0042 (a file whose prose disagrees with itself)

## Context

Gate 4 offered three options. They encode **two orthogonal axes**:

- **WHERE** Steps 5-7 run: this session, or a fresh one.
- **HOW** they run: attended, with Gates 5, 5.05, 5.06, 5.1 and 5.6 rendering and asking — or
  unattended, with `autopilot = true` driving each to its safe default.

Four cells. The gate offered two, on the diagonal:

|            | this session | fresh session |
|------------|--------------|---------------|
| unattended | option 1     | —             |
| attended   | **missing**  | option 2      |

So **choosing to stay in-session was choosing to forfeit every downstream HITL gate**, and nothing
at the gate said so — option 1's description mentioned "unattended" as if it were a property of the
session choice rather than a separate decision.

The two reasons are unrelated. Staying in-session preserves the design context the whole chain just
built; going unattended saves five clicks and means nobody reviews the review. An operator who
wanted the first and not the second had nothing to click, and the only route to an attended Step 5
was `/clear` plus `resume` — discarding the session that made every design decision.

It surfaced on a run whose explicit purpose was to exercise those gates: taking the offered
in-session option meant the gates under observation were the ones that stopped firing.

## What reading the issue does not give you

**The block contradicted itself in the same `AskUserQuestion`.**

- Option 1: *"Same-session context, mitigated since coders dispatch as isolated subagents."*
- Option 2: *"Resume … for the cleanest coder context."*

Both cannot be true, and the first is right. A dispatched coder is an isolated subagent running in
its own worktree (ADR-0068), so it never carried the orchestrator's conversation in either case.
What a fresh session actually buys is a clean **orchestrator** context: more headroom, briefs
written without the whole chain behind them. Real, and not what the text named.

This is ADR-0042's shape — a file whose two halves disagree with no way to tell which is
authoritative — and it matters here because "cleanest coder context" is the sentence that made the
fresh-session option look necessary, which is what kept the missing cell from being noticed.

**And Gate 4 followed no `(Recommended)` convention at all**, while every other gate in the chain
does and the global rule requires it. Found by the assertion, not by reading.

## Decision

### D1 — Add the fourth cell rather than document its absence

`Implement now (attended, this session)` transitions to `ready_for_implementation` and proceeds to
Step 5 **without** setting `autopilot`.

The issue offered documenting the exclusion instead. There is no reason to exclude it: the one
argument for forcing a fresh session was coder context pollution, and ADR-0068 settles that a coder
runs in its own worktree with its own context regardless. An option that gives up nothing should
not be unavailable.

Four options is exactly the `AskUserQuestion` maximum, so the matrix is spanned with no room left —
worth stating, because a fifth would force a redesign into two questions.

### D2 — The recommendation is the attended in-session option, and the reason is stated

It is the only one that forfeits nothing: the design context stays and every gate still asks. The
other three each trade something away — a fine trade made deliberately, a poor one made by default.

### D3 — The unattended-fresh-session cell stays unoffered, and is reachable

It is expressible by setting `autopilot` in the manifest before resuming, and the fresh-session
option's description says so. It is not a separate button because the gate has no room and the
combination has no distinct use: someone who wants unattended has no reason to pay for a `/clear`
first.

### D4 — The shared principle with #227, recorded here because this is the first of the two

**A gate must not present a choice whose options fail to span the decision, and must not present two
signals as if they were one.** #237 is the first failure (a four-cell decision offered on the
diagonal); #227 is the second (two "recommended" markers that can disagree, with no stated
precedence). Both were found at the chain's two entry gates by the same run, and both cost the
operator a decision they could not express or could not resolve.

Issue #227 is fixed separately: its answer is a precedence rule, not a missing option, so one edit
cannot serve both.

## Verification

14 assertions in `gate4-implementation-axes.test.sh`, plus a `Z1` floor. Prose is matched against a
whitespace-flattened copy; structural markers are matched line-wise (the ADR-0073/0076/0080/0082/0092
lesson family).

Seen RED against the unmodified tree: **9 of 14** — `G1`, `G2`, `G3`, `G3b`, `G5`, `G6`, `G7`,
`G7b`, `G8`. `G0`/`G0b`/`G4`/`G8b`/`Z1` are anchors and forward guards, labelled as such.

Five planted defects, all fired:

| plant | fires |
|---|---|
| the attended handler sets `autopilot true` | `G3b` — the one-line mistake that makes it the unattended path relabelled |
| the attended branch drops its `Gate 4.0` call | `G8`, and `recovery-preflight.test.sh` `RH2` |
| `cleanest coder context` restored | `G7`, `G7b` |
| `(Recommended)` marker removed | `G6` |
| Abort path given a `Gate 4.0` call | `G8b` |

**`RH2`'s floor was raised 3 → 4 in the same change.** Left at 3 it would have passed while
reporting "all three proceeding paths" — true before this ADR, false after — and would have
tolerated one of the four silently losing its reference. A floor that no longer tracks its
population is a floor that has stopped measuring.

## Consequences

- **A new default.** The recommended option changes from unattended to attended, so an operator who
  clicks the first option without reading now gets five gates they did not get yesterday. Correct
  direction, and still a behaviour change on the path most people take.
- **`AskUserQuestion` is at its four-option ceiling here.** Any further cell needs the gate split
  into two questions, which is a redesign rather than an addition.
- **Nothing enforces that the attended branch stays attended** beyond `G3b`. The two in-session
  handlers differ by one line, and that line is the whole contract.
- The unattended-fresh-session combination is documented rather than offered; someone who wants it
  edits the manifest, which is a step this gate does not walk them through.
- Inert until sync.
