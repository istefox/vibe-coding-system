# ADR-0184 — VCS-057: adopt native `memory: project` on `coder`, under a per-dispatch shard discipline

- **Status:** Accepted
- **Date:** 2026-08-31
- **Corrects:** ADR-0183's Phase 0 exclusion of `coder` (see the dated Correction appended there).
- **Related:** ADR-0068 (`isolation: worktree`, `baseRef: "head"`), ADR-0182 (the `reviewer`
  precedent this guard's shape and pilot methodology reuse), ADR-0183 (native memory rollout on
  the other agents).

## Context

ADR-0183 excluded `coder` from native persistent memory on the grounds that it runs inside a
fresh `isolation: worktree` on every dispatch, so a `memory:` injection would be destroyed before
the next dispatch could see it. That measurement was a bare dispatch: fresh worktree, one memory
write, nothing else. It never exercised Step 5's own merge-back mechanism
(`step5-implementation.md`, "Merge-back and base-fork audit"), which commits the worktree's
changes and `git merge`s them onto the feature branch before the next dispatch's worktree forks
from that same `HEAD`.

VCS-057 re-measured the real chain's path, live, in a throwaway scratch repo
(`~/Developer/_scratch/vcs057-coder-mergeback/`), six runs (M1-M6):

- **M1-M3 (persistence, artifact A):** a coder dispatch under `isolation: worktree` writes a fact
  to both `MEMORY.md` and a `topics/` shard. The merge-back's escape check passes clean, and
  `git ls-files` on the feature branch afterward shows both files tracked at `HEAD`.
- **M4 (re-injection, artifact B):** a second dispatch, fresh worktree forked from that new
  `HEAD`, reports the injected `MEMORY.md` content verbatim, including the M1 fact.
- **M5 (shard discipline, artifact C1):** two dispatches in one `parallel()` batch, each writing
  only to its own uniquely-named shard file, merge back with no conflict.
- **M6 (control, artifact C2):** the same two-dispatch setup, both writing `MEMORY.md` directly,
  produces a real merge conflict on the second merge — confirming the failure mode the shard
  discipline exists to avoid, not merely assuming it.

Five possible outcomes were distinguished going in (persists / rides the merge but is never
re-injected / does not persist / the merge-back's own escape check halts on it / did-not-run); the
measured outcome is the first.

## Decision

Add `memory: project` to `coder.md`. Add a new PreToolUse hook, `coder-memory-scope.sh`, that:

- allows any write outside `.claude/agent-memory/` unconditionally — writing source is coder's
  whole job, and this guard is not a whitelist the way `reviewer-write-scope.sh` is;
- allows a write to `.claude/agent-memory/coder/topics/*` (its own per-dispatch shard root);
- denies everything else under `.claude/agent-memory/`, in particular a direct write to
  `coder/MEMORY.md` or to another agent's memory directory.

`agent-memory-contract.test.sh`'s AM2 (an absolute ban on `memory:` + `isolation: worktree`
co-occurring on any agent) is rewritten as AM2′: the same ban, minus a one-line frozen allowlist
naming `coder` and this ADR (rule 19 — the deleted assertion's comment names where the old form
stood and why). A new AM6 asserts the producer/consumer meet: if `coder.md` carries `memory:`,
the guard must exist and be wired in `sync-to-claude.sh`'s PAIRS table and settings block.

Three points this decision fixes explicitly, per the brainstorm that produced it:

**(a) Memory scope is per-feature-branch by construction, not a design choice.**
`worktree.baseRef: "head"` (ADR-0068) means every coder worktree forks from the feature branch's
own `HEAD`, and the merge-back lands a shard back onto that same branch — never onto `main`
directly. A fact a coder writes therefore lives and dies with its feature branch: it is visible to
every later dispatch on that branch, and if the branch is abandoned without merging, the fact
never reaches any other branch. This is the correct scope for the facts coder actually writes
(task-local implementation notes, conventions discovered mid-batch) — nothing here claims or
needs cross-feature persistence.

**(b) Shards are pruned by nothing, deliberately, until the branch merges to `main`.** No process
in this system deletes a `topics/*.md` shard file mid-feature: an over-eager prune could remove a
fact a not-yet-dispatched later batch on the same branch still needs, and nothing can safely tell
"no longer needed" from "not yet needed" from inside Step 5. Once the feature branch merges to
`main`, its shards are ordinary tracked files subject to the same fate as everything else the
feature added — no special-cased cleanup, no separate retention policy.

**(c) Shards stay tracked, not gitignored.** Untracking them would silently break the whole
mechanism: the merge-back's `git -C "$WT" add -A` / `git merge` only carries tracked content
across, so a gitignored shard would never survive to the next dispatch and re-injection (B above)
would never fire. Curation (folding `topics/*.md` into the `MEMORY.md` index) is run once by the
orchestrator, after the last merge-back of a Step 5 run, never inside the fan-out — the
orchestrator carries no `agent_type`, so `coder-memory-scope.sh` is inert for it and this is the
one write to `coder/MEMORY.md` that is not denied.

## Consequences

- `coder` gains cross-dispatch, cross-batch memory on its own feature branch, closing the
  cross-dispatch half of its context-rot problem (the in-dispatch half is addressed separately,
  by preamble reduction — out of scope for this ADR).
- A parallel fan-out of coder dispatches is safe against the one failure mode measured (shared
  `MEMORY.md` writes) because the guard structurally prevents it, not because agents are trusted
  to follow the shard-write instruction in `coder.md` (rule 16: that instruction is a changed
  failure shape, not an enforcement — the guard is the enforcement).
- The pre-existing tension between Step 5's parallel fan-out and its base-fork halt
  (`step5-implementation.md:476`, `BASE_SHA == $PRE`) is unaffected by this decision and remains
  out of scope, tracked separately.

## Out of scope

- Changing ADR-0068's isolation contract. Nothing here alters worktree creation or `baseRef`.
- A symlink-from-worktree approach to share memory live across parallel dispatches: incompatible
  by construction with the merge-back's escape check, which halts the whole batch if anything
  untracked appears in the shared checkout.
- Reintroducing ADR-0012's orchestrator-mediated mechanism, just retired.
- In-dispatch preamble reduction (the other half of coder's context-rot problem) — separate work,
  independent of whether this ADR's memory adoption shipped.

## References

- ADR-0068 — `docs/architecture/ADR-0068-...md` (`isolation: worktree`, `baseRef: "head"`, the
  merge-back mechanism this ADR's measurement depends on).
- ADR-0182 — `docs/architecture/ADR-0182-native-memory-adopted-on-reviewer.md` (pilot methodology
  and guard-shape precedent, inverted here rather than copied — see `coder-memory-scope.sh`'s own
  header for why the logic is inverted, not merged, with `reviewer-write-scope.sh`).
- ADR-0183 — `docs/architecture/ADR-0183-native-memory-rollout-all-agents.md` (the Phase 0
  exclusion this ADR corrects, and its dated Correction).
- `staging/plugin/agents/coder.md` — `memory: project` + "Memory write scope" section.
- `staging/plugin/scripts/coder-memory-scope.sh` + `tests/coder-memory-scope.test.sh` (CM1-CM8).
- `staging/plugin/scripts/tests/agent-memory-contract.test.sh` — AM2′, AM6.
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` — both coder prompt
  sites (Workflow Stage 2, Agent-tool Single batch dispatch template) plus the "Memory shard
  curation" sub-step and the ESCAPE CHECK comment addition.
- This session's live Phase 1 measurement on `coder` (2026-08-31, VCS-057), six runs (M1-M6) in
  `~/Developer/_scratch/vcs057-coder-mergeback/`, a throwaway scratch repo never part of this one.
