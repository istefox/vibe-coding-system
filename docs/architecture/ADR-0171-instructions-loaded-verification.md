# ADR-0171 — `InstructionsLoaded` observability: measuring whether a correction actually loaded

- **Status:** Accepted
- **Date:** 2026-08-27
- **Builds on:** the `auto-learning` skill (writes corrections into `~/.claude/CLAUDE.md` and
  `~/.claude/rules/*.md`), ADR-0058 (context-occupancy `Stop` hint — the closest existing
  precedent for an observational, non-blocking hook), ADR-0168 (`commit-outcome-backstop.sh` —
  the closest precedent for a hook whose entire purpose is checking a claimed behaviour a second
  time, independently).

## Context

`auto-learning` promotes a lesson from a session transcript into a file every future session
loads. Whether that promotion actually closes the loop rests entirely on trusting Claude Code's
documented loading behaviour: that a file listed under a rule's scope, or under `CLAUDE.md`'s
hierarchy, is delivered into a session's context every time. Nothing in this repository measured
that claim.

Checked live, in the installed CLI binary (2.1.247, via `strings`) and against the current
`code.claude.com/docs` reference (WebFetch, 2026-08-27): an `InstructionsLoaded` hook event
exists, undocumented in this repo until now. It fires once per instruction file loaded, with
payload `session_id`, `hook_event_name`, `load_reason`, `file_path`, `cwd`. `load_reason` is one
of `session_start`, `nested_traversal`, `path_glob_match`, `include`, `compact`. Its exit code is
ignored — Claude Code cannot be blocked by this event, by design; the payload carries no way to
refuse a load.

A Plan-agent design review of the initial proposal found a structural defect before any code was
written (**C1**): a verification record keyed only on `file_path` can never return false. A load
that happened *before* a correction was written still satisfies a future query for the same path
forever. The tool would have been incapable of saying "no" — the definition of false comfort, and
worse than having no tool at all, since a green check would be read as proof.

## Decision

### D1 — Record file identity, not just path (closes C1)

`instructions-loaded-log.sh` (the writer, wired to the `InstructionsLoaded` event) reads the
target file's `mtime`/`size`/`sha256` at the moment the hook fires and writes them alongside
`file_path`/`file_path_canon` into the record. `instructions-loaded-verify.sh` (the reader)
compares **versions**, not paths: a match whose `file_mtime` is older than the file's current,
on-disk mtime is reported as `LOADED=stale`, distinct from `LOADED=true`. This is corroboration
of *which* version loaded, not proof — the hash/mtime describe the file's state when the hook
ran, not necessarily the exact bytes the loader consumed a moment earlier or later. Stated
plainly as a limit below, not hidden behind the mechanism's existence.

### D2 — Observational, never blocking

`instructions-loaded-log.sh` decides nothing and cannot: the event's exit code is already ignored
by Claude Code (verified above), so there is no decision to make even in principle.
`instructions-loaded-verify.sh` is a read-only REPORTER with a DID-NOT-RUN sentinel (repo rule 5),
not a checker — it always prints a verdict or an explicit INCONCLUSIVE/BADARG/UNREADABLE state,
never abstains silently, and a caller branches on its exit code first. Same posture as
`usage-daily-hint.sh` (ADR-0058 §D4): occupancy is reported, never gated, because a threshold gate
here would be a heuristic dressed as a decision — the same shape ADR-0051/0053/0054 already
rejected for other observational hooks.

### D3 — Count-based cap with amortised, receipted trim; no date-based rotation

No script in this repository does date-based log rotation — `chain-memory-capture.sh` is the only
existing precedent for volume control, and it uses a count cap (last 200 lines). This event's real
firing rate is **not measured** (the hook did not exist to measure it before this commit); the
cap (`INSTRUCTIONS_LOADED_CAP=20000` lines, `INSTRUCTIONS_LOADED_HIGH_WATER=12582912` bytes /
12 MiB) is sized to survive a wide margin of error, not tuned to a number, and that is stated here
rather than presented as measured.

The trim does not run per event: this event arrives in a burst at every session start, and
`tail -n $CAP` is O(file) — running it inside the startup path on every event was rejected as
putting a multi-MB rewrite where a session cannot afford one. It runs only when an O(1) `stat`
probe crosses the high-water mark, behind a non-blocking `mkdir` lock with stale-lock reclaim
(skipping a trim is free; the next event retries).

The trim **destroys evidence**, so it writes `trim-watermark` with the oldest surviving record's
`ts` before returning. Without it, a query whose answer was trimmed away would be
indistinguishable from a file that never loaded — exactly the collapse repo rule 4 (DID-NOT-RUN
is not FOUND-NOTHING) exists to prevent, here at the read side. `instructions-loaded-verify.sh`
checks the watermark and reports `INCONCLUSIVE reason=truncated` rather than a false `LOADED=false`
whenever the query's anchor predates it.

### D4 — Default anchor is the target file's own current mtime

Verifying "was the current version of this file loaded" needs an anchor to compare against.
Defaulting it to a timestamp the human must remember to supply would silently reopen C1 by
omission instead of by design — the exact failure this feature exists to close, just moved from
the mechanism into the calling convention. `instructions-loaded-verify.sh` defaults the anchor to
the target file's own mtime; `--since <ISO8601>` overrides it for a caller who wants to check
against an older reference point. The freshness comparison (`LOADED=true` vs `LOADED=stale`) is
always against the file's *live* current mtime, independent of the anchor used to gate the search
window — the two collapse to the same value in the default case, so this only matters for
`--since`-driven queries.

### D5 — Exact-match on the canonical path, never substring

`instructions-loaded-verify.sh`'s match predicate is `jq --arg p "$CANON" '.file_path_canon == $p'`
— never `contains`, `startswith`, or a glob (repo rule 18: a scan is satisfied by the whole
population it searches, not the part it meant; a needle must belong to the mechanism it asserts
about and to nothing else, repo rule 1/12). A record for `tools-extended.md` must never satisfy a
query for `tools`, and a shared basename across two directories must never cross-match.
`instructions-loaded-canon.sh` is the single shared path-canonicalisation source between the
writer and the reader — extracted rather than duplicated (repo rule 6): a divergence between how
the writer and the reader answer "what path is this, really?" would produce a query that can
never match a record it should, exactly the failure this feature exists to prevent, and exactly
the shape `sync-manual-steps.test.sh`'s `build_home_skills` fixture drift already demonstrated for
a different pair of copies in this repo (fixed the same day as this ADR).

## Alternatives rejected

- **Path-only records (the original proposal).** Rejected outright by the design review (C1):
  structurally incapable of ever returning false.
- **A `SessionStart` liveness heartbeat, to distinguish "the hook stopped firing" (e.g. a Claude
  Code upgrade silently changed the event) from "no session has run since."** A real gap, strongly
  recommended by the design review. Rejected for this ADR as a second hook, second file, second
  test surface — out of scope here, recorded as a follow-up.
- **Hooking this verification into the `concept-to-code` chain's `[FRESH SESSION]` boundary
  automatically** (e.g. blocking Gate 4 if a recent correction does not show up as loaded).
  Rejected here: touches the skill's existing gate and needs a new legal transition pair in the
  manifest state machine, not just the observability primitive. Recorded as `VCS-041` in
  `TODO.md`, not attempted in this ADR.
- **Date-based log rotation**, mirrored from a convention that does not actually exist anywhere in
  this repository. Rejected in favour of the count-cap-with-receipt already used by
  `chain-memory-capture.sh`, adapted for a query-driven consumer instead of a human reader (D3).

## Consequences

### Positive

- A specific claim — "did file X, as it exists right now, actually enter a session's context" —
  has a measured answer for the first time, instead of resting on documented behaviour taken on
  faith.
- The C1 defect (a check that can never return false) was caught and fixed before any code shipped,
  by an explicit design-review pass ahead of implementation.
- A second, independent defect — the `LOADED=stale` verdict being structurally unreachable in the
  first draft, because the window filter and the freshness comparison shared one anchor value —
  was caught by manual smoke-testing each planned state before writing the formal test harness,
  and fixed the same way.

### Negative, stated plainly

1. **`LOADED=true` means the bytes entered the model's context. It does not mean the correction
   was obeyed.** The verify script prints this distinction on every verdict line, not only here —
   repo rule 16 (an instruction is not an enforcement) applies to this tool's own output as much as
   to any `SKILL.md` prose it might one day be used to check.
2. **The hash/mtime describe the file's state when the hook fired, not necessarily the exact bytes
   the loader read.** A write racing the hook in the same instant is not distinguished. This is
   corroboration, not proof.
3. **No `InstructionsUnloaded` event exists.** A file loaded at `session_start`, followed by a
   `compact` that does not reload it, leaves a permanent positive record and no trace of the loss.
   A verdict only ever answers "was it loaded at some point in the anchor window," not "is it in
   context right now."
4. **Subagent coverage is unknown.** The payload carries no `agent_id`/`agent_type`, and whether
   this event fires at all inside a Workflow subagent is an open question — the same ADR-0016
   blocker `hook-probe.sh`'s C3 check exists to measure for a different hook family. Every verdict
   prints `subagent_coverage=unknown` rather than implying coverage it has not measured.
5. **A record proves *some* session loaded the file, not necessarily the one a caller has in
   mind.** Every verdict prints the matching `session_id` set so a caller can check by hand; the
   tool does not resolve "was it loaded into *my current* session" on its own.
6. **Files loaded lazily via `paths:` scoping make absence ambiguous by design.** A `LOADED=false`
   for a path-scoped rules file and a `LOADED=false` for a file that is supposed to load every
   session look identical in this tool's output. Declared here as unhandled, not silently
   resolved.

Related: `docs/chain-decision-index.md` / `docs/chain-decisions.md` carry the paired index entry
and narrative block, per `claude-md-condensation.test.sh`'s CMC05 check.
