# ADR-0161 — do not re-run a suite on a tree that has not moved

- **Topic slug:** `stop-gate-fingerprint-cache`
- **Issue:** #491
- **SPEC:** none — a bounded change to one hook, no requirement ids, no coverage gate
- **Extends:** ADR-0137 §D4/§D5 (the ceiling and the shared budget), ADR-0156 (the distinct-failure
  budget this ADR's cache sits in front of — unchanged, still runs on every cache miss). Supersedes
  nothing.
- **Deliberately does not touch:** ADR-0156's signature de-dup, or the timeout path

## Status

Accepted — 2026-08-19.

## Context

`stop-gate.sh` runs the project's `test-cmd` at the end of any turn that wrote a file. ADR-0156
taught it to spend its anti-loop budget on distinct failures rather than repeats — but that de-dup
happens *after* the suite has already run to completion. Every repeat still pays the full `$TMO`
wall-clock cost to *learn* the output is a repeat; only the budget is spared.

Reported live: a Stop fires on every turn spent waiting on a dispatch, not only at a batch boundary.
Across a five-batch chain run with an async `Agent`-tool dispatch, that is several Stops per batch
while the controller is doing nothing but waiting for a notification — and each one re-ran the whole
suite against a tree nothing had touched since the previous run, at this repository's own 300s
`.claude/test-timeout` ceiling.

## Decision

### D1 — a tree fingerprint, checked before the suite runs

`FP_CUR` is `sha256` of `git status --porcelain` (what changed) plus `git diff HEAD` (what it
changed *to*), both read at `$ROOT` — the same root the trust lookup and the command itself already
use. **Not** the `$DIRTY` marker alone: `mark-dirty.sh` only appends, never truncates, so it cannot
tell "touched again with no new content" from "touched with new content" on its own.

- **Cache hit** (`$FP_CUR` matches the stored `$FP`, and a recorded rc exists): the suite does not
  run. The stored rc is reused, a throwaway copy of the last output stands in for `$OUT`, and a
  stderr line says so explicitly — `rule 4`: a skip must be visible, not merely fast.
- **Cache miss**: the suite runs exactly as before. On a **124** (timeout) or an ordinary
  **non-zero, non-125/126/127** failure, the fingerprint, the rc and a copy of the output are
  recorded for the next call to potentially reuse. 125/126/127 are deliberately never cached — the
  file's own existing comment already states why: an instantly-failing exec has nothing a cache
  would save, so caching them buys complexity for zero wall-clock.
- **Not git → not cached**, and the direction is fail-toward-running (ADR-0055 §D2's strict-unknown
  convention, applied here): an unreadable git state leaves `$FP_CUR` empty, which can never equal a
  stored non-empty fingerprint, so the branch is always a miss and the suite always runs. There is no
  path through an empty fingerprint to a skipped suite — the dangerous direction has no entry point.

### D2 — a green run clears the cache along with everything else it already clears

ADR-0156 §D3 already clears `$DIRTY`, `$OUT`, `$CF`, `$SF` on a green run. `$FP`, `$RCF` and
`$LASTOUT` join that same line. Left behind, they would describe a now-stale red cycle: a later
dirty state that happens to hash identically — the same edit made twice across a session — would
replay a verdict from a cycle the green run just closed.

### D3 — what the cache skips, and what it does not

The cache skips the **re-run**, never the **decision**. A cache hit still emits the same block
verdict the original run produced — ADR-0156's signature-based budget accounting still applies to
it exactly as if the suite had run again and produced the same output, because from the budget's
perspective it did: the fingerprint match *is* proof the output would be identical. Skipping the
re-run without also skipping the decision would be silent tolerance; this skips only the redundant
work.

## Consequences

- A turn spent waiting on an async dispatch, with no file touched since the last Stop, pays nothing
  — no suite run, one stderr line.
- A turn where the tree genuinely changed since the last run is unaffected: the suite runs, exactly
  as before D1 existed.
- The disclosed limit ADR-0156 already stated for signature equality — a suite whose own output
  varies run to run (a timestamp, a random seed) never repeats identically — applies here identically
  and in the same direction: such a tree would still hash the same (the fingerprint is over the
  *tree*, not the suite's output), so a cache hit on an unstable suite reuses a stale rc. This is the
  same class of limit ADR-0156 already accepted for its own signature, not a new one introduced here,
  and it is stated rather than discovered later.
- **Not addressed.** The cache is keyed on `$ROOT`'s git state alone; a test suite whose result
  depends on something outside the working tree — network state, a service's clock, an external
  fixture — is not modeled and was never modeled by anything in this file.

## Alternatives considered

**A1 — cache on `$DIRTY`'s mtime instead of a content hash.** Rejected: `mark-dirty.sh` only
appends, so its mtime advances on every touch regardless of whether the touch changed anything —
exactly the ambiguity D1's own comment names as the reason a content hash was chosen instead.

**A2 — cache the suite's stdout/stderr content, not the tree's fingerprint.** Rejected: it inverts
the causality the cache needs. The question is "has the input changed", answerable cheaply from git
state; hashing the suite's own prior output to detect a repeat would still require having run the
suite once to have something to hash, which is the cost this ADR removes.

**A3 — cache 125/126/127 (bad invocation, missing binary, permission denied) too, for uniformity
with 124 and ordinary failures.** Rejected: these fail instantly by construction (the file's own
prior comment already establishes this), so there is no wall-clock cost to save by caching them —
only bookkeeping to maintain for a case that never benefits from it.

## Test and plant obligations

`stop-gate-path-predicate.test.sh`, SGP31-35 — a real git repo fixture (`gate_new_git_proj`), not
SGP01-30's touch-only sentinel, because the fingerprint reads `git status --porcelain` + `git diff
HEAD` and a counting test-cmd is needed to distinguish "ran once" from "ran twice":

- **SGP31** — a second Stop on a tree unchanged since the first block does not re-run the suite
  (`runcount` stays 1).
- **SGP32** — the cache-hit run states "fingerprint match" on stderr.
- **SGP33** — the cache-hit run still emits the same block decision — skipping the re-run does not
  silently allow.
- **SGP34** (forward guard) — a tree that did change since the last run is not served from cache;
  `runcount` advances.
- **SGP35** (extends ADR-0156 §D3) — a green run clears `.fp`/`.lastrc` along with the budget it
  already clears.

`FLOOR` raised 30 → 35 for the five new assertions, re-derived rather than incremented by feel
(rule 10). SGP31's plant individually verified `FIRED`.

## References

- Issue #491
- ADR-0137 §D4/§D5 — the ceiling and the shared budget this cache sits in front of
- ADR-0156 — the distinct-failure budget and its §D3 green-run clear, extended by D2 here
- ADR-0055 §D2 — the strict-unknown, fail-toward-running convention D1 applies to an unreadable git
  state
- CLAUDE.md rule 4 (a skip must be visible), rule 10 (the FLOOR re-derivation)
