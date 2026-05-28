# ADR-0013 — Migrate cross-session agent memory to the NATIVE `memory:` feature (supersede ADR-0012, `local` scope)

**Status:** Rejected after pilot — 2026-05-25. The migration had been accepted (scope `local`, Write/Edit on reviewer OK) and Phase 1 enabled in coexistence, but the **pilot failed**: architect dispatch with `memory: local` -> the native dir `.claude/agent-memory-local/architect/` remained UNCHANGED while the agent autonomously edited the curated auto-memory (`reference_cc-capabilities-research-2026-05.md`), OUTSIDE its write-scope. The broad-Write auto-enabled by `memory:` materialized the downside of axes 4-5 of this ADR. The pilot-gate (blocking precondition) did NOT pass -> **ADR-0012 remains the active mechanism** (orchestrator mediation, sub-agents without Write on memory). `memory: local` removed from the 3 agents, seeded dirs cleaned (data intact in the central store). Caveat: 1 run, possible confounders (prompt + Sonnet + discoverable thematic file), but the risk is structural.

**Deciders:** architect (dispatch orchestrator), Stefano Ferri (final approval)

**Related:** ADR-0012 (`docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` +
`-implementation-plan.md` — the B-mediated solution deployed today, which this ADR proposes to
supersede); ADR-0004 (`docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` — source
of the project-dir encoding fragility that the native eliminates internally); ADR-0001
(`docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` — the mediated `DURABLE
NOTES:` contract reused its structured-report pattern, which the native makes superfluous);
ADR-0003 (`docs/architecture/ADR-0003-concept-to-code-chain.md` — the chain where the mediated
contract is inserted, to simplify); ADR-0005
(`docs/architecture/ADR-0005-vibe-status-skill.md` — the Section 7b read-only to re-point);
ADR-0011 (`docs/architecture/ADR-0011-clean-public-repo-anonymize.md` — constraint "outside the
tracked tree", which the native satisfies only with the right scope).

---

## Context

### What changed after ADR-0012

ADR-0012 was **Accepted and deployed on 2026-05-25** (B-mediated option): the cross-session
memory of `architect`/`debugger`/`reviewer` was moved from `docs/agent-notes/<agent>.md`
(inside the project tree) to the central store
`~/.claude/projects/<encoded>/memory/agent-notes/<agent>.md`, with access **mediated by the
orchestrator**: injection of the `PRIOR AGENT NOTES` block in the brief, harvest of the
terminal `DURABLE NOTES:` block from the report via helper
`~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh`. Sub-agents **never** touch
memory or resolve the encoded path. The live state is **green** (verified 2026-05-25): helper
present, store populated (`architect.md` ~25KB, `debugger.md` ~7KB, README), no agent uses the
native field; round-trip harness 7/7, concept-to-code 25, review-triage-fix 62, vibe-status 12.

Research on 2026-05-25 of the official docs (memory `reference_cc-capabilities-research-2026-05.md`)
then discovered that **Claude Code has a NATIVE feature** that covers the same need. ADR-0012
itself foresaw a **re-evaluation clause** (choice 5) towards simpler alternatives if the
assumptions did not hold: this ADR exercises it — not because of an operational failure, but
because a simpler and more robust path than B-mediated has emerged, which B-mediated had to build
by hand in the absence of native support.

### VERIFIED facts about the native feature (source: `code.claude.com/docs/en/sub-agents`, section "Enable persistent memory", read 2026-05-25)

Cited verbatim from the indicated line of the official doc:

- **Frontmatter field** `memory: user | project | local` (line 277 "Persistent memory scope …
  Enables cross-session learning"; line 433 "The `memory` field gives the subagent a persistent
  directory that survives across conversations").
- **Storage per scope** (lines 452-454, verbatim table):
  - `user` -> `~/.claude/agent-memory/<name-of-agent>/` — "remember learnings across all projects";
  - `project` -> `.claude/agent-memory/<name-of-agent>/` — "project-specific and **shareable via
    version control**";
  - `local` -> `.claude/agent-memory-local/<name-of-agent>/` — "project-specific but **should not
    be checked into version control**".
- **When active** (lines 456-460, verbatim):
  - the sub-agent system prompt includes read/write instructions for the memory dir;
  - includes the **first 200 lines or 25KB** of `MEMORY.md` of that dir (whichever is less), with
    instructions to curate it if it exceeds the limit;
  - **Read, Write, Edit are auto-enabled** "so the subagent can manage its memory files".
- **Who manages the memory:** the **sub-agent itself** ("update your agent memory…", line 444;
  "manage its memory files", line 460; tip 465-470 "consult its memory before starting / save what
  you learned"). The encoded path is **resolved internally** by Claude Code: the nominal scope
  (`user`/`project`/`local`) maps to the path without us doing `tr '/' '-'`.
- `memory` confirmed in **supported frontmatter fields** and in the JSON `--agents` (line 225) ->
  it is a first-class feature, documented, not gated.

### The connection to the lesson of ADR-0004 / ADR-0009 (PRIOR NOTE of this task)

The PRIOR NOTE is central: ADR-0004 (v1.0/v1.1) cost two fixes precisely because it derived the
encoded project-dir by hand (`_`->`-`, `cwd` re-encoded != real path). B-mediated of ADR-0012
**worked around** that trap by confining encoding to the sole orchestrator — but the fragile
encoding **persists** in the system: the helper `agent-notes-harvest.sh` (lines 43-44) and
`vibe-status/aggregate.sh` (Section 7/7b) still use `printf '%s' "$PWD" | tr '/' '-'`. The
comment in the helper itself acknowledges it ("the same fragile pattern noted in
feedback_pretooluse-payload-schema; acceptable HERE…"). The native **eliminates** that derivation,
does not confine it: it is exactly the application of the rule "prefer direct input/native
resolution over derived encoding when sufficient".

### The guiding rule

"Building Effective Agents" (Anthropic) and official best-practices (confirmed at ~85% aligned,
same research): **do not add complexity until the simple is enough**. ADR-0012 was explicitly
justified only because *no* native support existed and the system already had the infrastructure
to extend the pattern. That premise has fallen: now the simple (a frontmatter field) is enough.

### Explicit assumptions (NOT validated)

- It is assumed that the documented behavior of the native is stable in the Claude Code version
  in use by Stefano. No live test of the `memory:` field has been run on this environment (no
  agent uses it today — grep `^memory:` on `~/.claude/agents/*.md` = empty). **It must be
  validated in a pilot** before removing the mediated infrastructure (see teardown plan, ordered
  phase).
- It is assumed that agent memory **still has value** (same assumption as ADR-0012): if in the
  pilot it emerged that agents produce no useful notes, the simple option becomes "do not enable
  `memory:` at all" (= Alternative C of ADR-0012, reiterated here as fallback).
- It is assumed that `local` scope produces the dir `.claude/agent-memory-local/<agent>/`
  **inside the cwd of the target project** (working tree of the project the agent is working on),
  not inside `~/.claude`. It is the direct reading of the doc ("project-specific"); to be
  confirmed in pilot because it determines the scope choice (see axis 3).

---

## Decision

Adopt the **migration to the native `memory:` feature** for the 3 agents with memory, with scope
**`local`** (`.claude/agent-memory-local/<agent>/`, NOT checked-in), and **supersede ADR-0012**
(teardown of the mediated infrastructure: helper, inject/harvest in the two SKILL.md, `DURABLE
NOTES:`/`PRIOR AGENT NOTES` contract in the 3 agent definitions). The migration happens **after**
a native pilot validation, with a period in which existing data remains available.

### Summary (<10 lines)

The native does what B-mediated built by hand, with **zero our code** and **resolving the encoded
path internally** (eliminates the ADR-0004 trap, does not confine it). The `local` scope does not
dirty the tracked tree (original constraint of ADR-0012, and ADR-0011) because it is not
checked-in. The price — auto-enablement of Write/Edit even on `reviewer` (read-only) and loss of
orchestrator HITL control over what enters memory — is **acceptable**: writing is confined to the
agent's memory dir, not to project code, and agent notes are session scaffolding, not an artifact
that requires a human gate. The rule "prefer native, do not add complexity until the simple is
enough" applies.

### D1 — Scope: `local`

Use **`memory: local`** (`.claude/agent-memory-local/<agent>/`). Rationale per axis 3 (tree
pollution, original problem of ADR-0012):

- `project` -> `.claude/agent-memory/<agent>/` **checked-in**: would re-introduce exactly the
  conflict that ADR-0012 resolved (scaffolding files in the tracked tree, in tension with
  ADR-0011). **Excluded.**
- `user` -> `~/.claude/agent-memory/<agent>/`: outside any tree, never committed. But
  **cross-project**: notes from a debugger on one project would mix with those from another.
  For agents that learn patterns *specific to a project* (a recurring bug in THAT codebase) it
  is semantically wrong. Remains valid for truly universal patterns (see open points).
- `local` -> `.claude/agent-memory-local/<agent>/`: **not checked-in** (no tree pollution) **and**
  per-project (correct semantics of agent memory). It is the recommended default for this case.
  Requires a line `.claude/agent-memory-local/` in the `.gitignore` of the target project only
  if the project tracks `.claude/` — to verify in pilot; the doc explicitly says "should not be
  checked into version control", so Claude Code intends it as non-tracked by design.

### D2 — Enable `memory: local` on the 3 agent definitions

In `~/.claude/agents/{architect,debugger,reviewer}.md` add to the frontmatter `memory: local`
and, in the body, a brief proactive instruction to consult/update their own memory (doc pattern
lines 465-470), specific per role:

- `architect`: "Consult your memory for past architectural decisions/patterns on this project
  before designing; update it with durable decisions at end of task."
- `debugger`: "Consult your memory for already-seen bug patterns; save the pattern + resolution
  at end of fix."
- `reviewer`: "Consult your memory for recurring patterns; note newly observed patterns."

Read/Write/Edit are auto-enabled by the native for management of that dir only (see axis 4).

### D3 — Tear down the mediated infrastructure of ADR-0012 (REMOVE)

After pilot validation (D6), remove what B-mediated had set up:

1. From the 3 agent definitions: the `PRIOR AGENT NOTES` block (factor-in) and the terminal
   `DURABLE NOTES:` section (Output Format) introduced by ADR-0012 Tasks 3/4 -> replaced by the
   native instruction D2. (The old `docs/agent-notes/` had already been removed by ADR-0012
   Task 5; **do not** re-introduce it.)
2. From the `concept-to-code/SKILL.md` chain (Step 2): inject `PRIOR AGENT NOTES` + harvest
   `DURABLE NOTES:` for the architect (ADR-0012 Task 6). Dispatch returns to passing only the
   brief; the §6 note must be updated.
3. From `review-triage-fix/SKILL.md`: inject/harvest for reviewer and debugger (ADR-0012 Task 7).
4. The helper `~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh` -> **deletion**
   (HITL gate: permanent removal; backup before).
5. The round-trip harness `agent-notes-roundtrip.sh` -> deletion (tests a contract that no longer
   exists; HITL gate).
6. `vibe-status` Section 7b: re-point it from `~/.claude/projects/<encoded>/memory/agent-notes/`
   to `.claude/agent-memory-local/<agent>/` of the current project (or remove it entirely, see
   open point) — read-only, non-blocking; or remove the `tr '/' '-'` of that signal entirely.
7. `claude-md-generator` (ADR-0012 Task 8 guard line): if added, the update becomes "do not
   generate rules that prohibit `.claude/agent-memory-local/` in the tree" — but with non-checked-in
   `local` scope the risk is minor; evaluate if the guard is still needed.

### D4 — Existing data migration

Historical data lives in `~/.claude/projects/<encoded>/memory/agent-notes/{architect.md,debugger.md}`
(migrated by ADR-0012 Task 2). Options, in order of preference:

- **Seed native `MEMORY.md`:** copy the content of `architect.md`/`debugger.md` as initial
  `MEMORY.md` in the respective native dirs `.claude/agent-memory-local/<agent>/MEMORY.md` of the
  pilot project. Note: the native loads only the first 200 lines/25KB — `architect.md` is ~25KB ->
  must be **pruned/curated** at seed (the native itself instructs to curate `MEMORY.md` if it
  exceeds). This is additive: copy, not move.
- Source files in the central store **remain** until the pilot confirms (rollback guaranteed). Their
  eventual removal is a separate task with HITL gate, post-pilot.

Note: `architect`/`debugger` memory is per-blueprint-project; with `local` scope the native dir
is inside the project the agent works on each time. The seed makes sense only for projects where
that historical memory is relevant (here: the `vibe-coding-system` repo itself, if that's what
agents operate on). For new projects, native memory starts empty — correct behavior.

### D5 — Safe teardown order (no data loss, no broken mid-way)

1. **Native pilot** (D6) on a project, with `memory: local` enabled on the 3 agents **and** the
   mediated infrastructure still in place (the two mechanisms temporarily coexist: redundancy
   tolerated, no loss).
2. **Verification:** the sub-agent reads and writes its native dir; seeded data is consulted;
   no file ends up in the tracked tree (scope `local`).
3. Only at green pilot: **tear down** the mediated infrastructure (D3) — first the dispatchers
   (chain + review-triage-fix), then agent definitions (remove `DURABLE NOTES:` contract), then
   helper/harness (HITL gate on deletions).
4. **Last:** decide the fate of data in the central store `memory/agent-notes/` (keep as
   historical archive or remove — HITL gate). Do not remove before the verified seed (D4).

### D6 — Pilot and watch

The non-headless-testable risk of ADR-0012 was "orchestrator forgets the harvest". The native
**eliminates** that risk (no manual harvest: the agent writes by itself). The new risk to validate
in pilot is the opposite and more benign: **the agent does not update** its memory (omits
writing) — degrades to "empty memory", not to corruption or leak into the tree. Mitigation:
proactive instruction in the agent body (D2). Pilot: a real cycle (an architect dispatch + a
review-triage-fix cycle) on a project, verifying that `.claude/agent-memory-local/<agent>/MEMORY.md`
is created/updated and does NOT appear in `git status` of the project.

### Points requiring Stefano's decision (pending — Status: Proposed)

1. **Scope `local` vs `user`.** Recommended: `local` (per-project, no tree pollution). `user` only
   if Stefano wants cross-project shared memory (different semantics). **Decision.**
2. **Auto-enablement of Write/Edit on `reviewer`** (today read-only by design): acceptable given
   it is confined to the memory dir? Recommended: yes (axis 4). **Confirm or veto.**
3. **Fate of historical data** in `memory/agent-notes/` after the seed: archive or remove (HITL
   gate). **Post-pilot decision.**
4. **Deletion of helper + harness** (`agent-notes-harvest.sh`, `agent-notes-roundtrip.sh`):
   permanent deletion, **HITL gate**, backup before. **Confirm.**
5. **Seed of native architect memory** from the ~25KB historical data (must be pruned to
   <=25KB/200 lines): do it or start clean? **Decision.**

---

## Consequences

### Positive

- **Zero our code to maintain.** The helper `agent-notes-harvest.sh`, the round-trip harness,
  and the inject/harvest contract in the two SKILL.md + 3 agent definitions disappear. Less
  surface, less tests, fewer failure points.
- **Encoding fragility ELIMINATED (not confined).** The native resolves `local`/`user`/`project`
  -> path internally: no our `tr '/' '-'` either at inject/harvest phase or (by re-pointing or
  removing Section 7b) in `vibe-status`. It is the direct application of the PRIOR NOTE
  (ADR-0004/0009).
- **Harvest risk zeroed.** The TOP operational risk of ADR-0012 (orchestrator forgets to collect
  -> memory silently lost) disappears: the agent writes by itself, there is no orchestrator step
  to remember. Valid also for direct dispatches outside the chain — where B-mediated was weaker.
- **No tree pollution with `local` scope.** `.claude/agent-memory-local/` is not-checked-in by
  design (doc): the original constraint of ADR-0012 and ADR-0011 is satisfied without central
  store.
- **First-class feature, low dependency risk.** Unlike the Workflow tool (gated, closed thread),
  `memory:` is documented in supported frontmatter fields and in the JSON `--agents`.
- **Pattern consistent with official best-practices** ("subagent accumulating insights in its
  memory" is the doc example, line 444) and with the rule "prefer native".

### Negative

- **Expanded sub-agent tool surface.** Read/Write/Edit auto-enabled even on `reviewer` (today
  read-only). Confined to the memory dir, but it is a concession relative to ADR-0012 discipline
  (sub-agent sees only text in/out). See axis 4: acceptable, not free.
- **Loss of orchestrator/HITL control over what enters memory.** B-mediated curated the harvest;
  the native is agent autonomy. For session scaffolding it is the right trade-off; if memory
  ever contained sensitive data it would be a problem (but `local` scope not-checked-in and
  confinement to the dir limit exposure).
- **Teardown + data migration cost.** ADR-0012 is deployed and green: tearing it down is real
  work (remove contract, helper, harness; seed/migrate data; re-point vibe-status). Mitigated
  by the safe order (D5) and temporary coexistence.
- **Dependency on untested native behavior on this environment**: the pilot is a blocking
  precondition to the teardown.

### Neutral

- **Token cost:** substantially neutral/slightly better. The native loads <=200 lines/25KB of
  `MEMORY.md` in the agent system prompt (targeted and capped load); B-mediated injected the
  `PRIOR AGENT NOTES` block in the brief (`architect.md` historical is ~25KB -> same order of
  magnitude). The native 25KB cap is effectively a protection that B-mediated lacked (it injected
  everything).
- **Reversibility:** high while keeping temporary coexistence. If the native disappoints in the
  pilot, we revert to B-mediated (still in place) without data loss — or fall back to ADR-0012
  Alternative C (removal). Historical data remains in the central store until confirmed.
- **Historical `.bak`** (`refactorer.md.bak-2026-05-20`): unchanged, as in ADR-0012.
- **Repo `vibe-coding-system` NON-git:** the deliverable of this ADR is the sole markdown. The
  teardown of live artifacts (agent definitions, 2 SKILL.md, helper/harness, vibe-status) is a
  **separate task** (plan, **without commit step**), after approval and pilot.

---

## Alternatives considered

### A — Keep ADR-0012 (mediation) as is, ignore native

**Rejected.** Zero change cost (nothing to tear down) and preserves orchestrator HITL control.
But: (1) **violates the guiding rule** — we maintain by hand (helper + contract in 2 skills + 3
agents + harness) what an official feature does with a frontmatter field; (2) **preserves the
encoding fragility** `tr '/' '-'` in the helper and in vibe-status (the PRIOR NOTE explicitly says
to prefer native resolution); (3) **preserves the harvest risk** TOP (orchestrator that forgets to
collect, especially outside the chain). The HITL control that B-mediated offers is not really
needed for session scaffolding (axis 5): it is not an artifact that requires human approval over
what enters. Maintaining complexity for an unnecessary control is the exact case the rule
"do not add complexity until the simple is enough" prohibits.

### B — Hybrid: native for persistence, but orchestrator still curates/injects

**Rejected.** Would use the native for storage (path resolved by CC) but the orchestrator would
continue to inject/curate notes. **Incoherent:** the native already loads `MEMORY.md` in the agent
automatically — injecting it again in the brief is pure redundancy (double loading, double tokens).
And if the orchestrator curates, the helper and encoded path are still needed -> does not eliminate
the fragility or the code. The hybrid takes the cost of both and the benefit of neither. The only
justification would be HITL control over writing, already dismissed in A as unnecessary for
scaffolding.

### C — Scope `project` (checked-in) instead of `local`

**Rejected.** `project` (`.claude/agent-memory/<agent>/`) is "shareable via version control":
would re-introduce **exactly** the conflict that ADR-0012 resolved (scaffolding files in the
tracked tree, exposed in publication, in direct tension with ADR-0011). The original driver of
ADR-0012 was "no scaffolding in the tracked tree": choosing it now would undo that result. To be
excluded unless Stefano deliberately wants to version memory with the project (unlikely, given
existing rules).

### D — Scope `user` (cross-project) instead of `local`

**Rejected as default**, retained as conscious option. `user` (`~/.claude/agent-memory/<agent>/`)
is outside any tree (no pollution) — good. But it is **cross-project**: mixes notes from all
projects in a single per-agent dir. For *project-specific* memory (a bug-pattern of THAT codebase,
a decision of THAT system) it is semantically wrong and noisy. `local` gives the same absence of
pollution **and** per-project isolation. `user` remains sensible only for truly universal patterns
(e.g. a convention valid everywhere) — open point for Stefano.

### E — Remove agent memory entirely (= Alternative C of ADR-0012)

**Rejected today, but declared fallback.** The simplest of all: no field, no contract. Justified
only if the pilot showed agents produce no useful notes (same unvalidated assumption of ADR-0012).
As long as it is assumed memory has value, the native preserves it at near-zero cost, so removing
it would throw away value. If the pilot refuted the assumption, this becomes the correct choice —
even simpler than native.

### Why native (`local` scope) despite teardown cost

It is the only option that **respects the guiding rule** (replaces our code with an official
feature), **eliminates** (not confines) the encoding fragility of the PRIOR NOTE, **zeroes** the
TOP harvest risk of ADR-0012 even outside the chain, and **maintains** the absence of tree
pollution (`local` scope). The cost — expanded tool surface + loss of orchestrator HITL control —
is proportionate and acceptable for *session scaffolding* (not product artifacts). The teardown
cost is one-time and protected by the safe order + temporary coexistence. ADR-0012 was justified
"only because the native did not exist": that premise has fallen.

---

## References

- `code.claude.com/docs/en/sub-agents` — section "Enable persistent memory" (`memory:` field line
  277/433; storage per scope lines 452-454; behavior auto-enablement + MEMORY.md loading lines
  456-460; tip lines 465-470; `memory` in supported fields + JSON `--agents` line 225).
  **Primary source verified 2026-05-25.**
- ADR-0012 — `docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` +
  `ADR-0012-implementation-plan.md` (the B-mediated solution deployed, superseded by this ADR;
  Tasks 1-10 = exact list of what to tear down).
- `~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh` — mediated helper to delete
  (lines 43-44 = the fragile `tr '/' '-'` that the native makes superfluous).
- `~/.claude/skills/concept-to-code/SKILL.md` (Step 2 architect inject/harvest) and
  `~/.claude/skills/review-triage-fix/SKILL.md` (reviewer+debugger inject/harvest) — the two
  dispatchers to simplify.
- `~/.claude/agents/{architect,debugger,reviewer}.md` — add `memory: local`; remove
  `PRIOR AGENT NOTES`/`DURABLE NOTES:` contract.
- `~/.claude/skills/vibe-status/scripts/aggregate.sh` — Section 7b to re-point/remove
  (eliminates another `tr '/' '-'`).
- Historical data store: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/agent-notes/{architect.md,debugger.md}`
  — to seed into native memory, then post-pilot fate (HITL gate).
- ADR-0004 — `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` and
  `feedback_pretooluse-payload-schema` (the encoding fragility `_`->`-`/`cwd` that the native
  eliminates).
- ADR-0009 — `docs/architecture/ADR-0009-db-backup-guardrail.md` (the PRIOR NOTE "prefer direct
  input/native resolution over derived encoding when sufficient").
- ADR-0011 — `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` (constraint "outside the
  tracked tree": satisfied by non-checked-in `local` scope; `project` scope would violate it).
- Memory `reference_cc-capabilities-research-2026-05.md` (headline: native overlaps ADR-0012)
  and `adr0012-agent-memory-mediated.md` (deploy state + re-evaluation clause choice 5).

---

DURABLE NOTES:
- [pattern] When an official native feature covers a mechanism we built by hand, the rule "prefer native / do not add complexity until the simple is enough" prevails even over an already-deployed and green solution — provided temporary coexistence + pilot exist to avoid data loss (ADR-0013 supersedes ADR-0012).
- [decision] For non-checked-in agent memory use `memory: local` scope (.claude/agent-memory-local/), not `project` (checked-in -> re-introduces ADR-0012 tree pollution) nor `user` (cross-project -> semantically wrong for project-specific memory).
- [tradeoff] The native `memory:` auto-enables Write/Edit even on read-only agents (e.g. reviewer): acceptable because confined to the memory dir, but it is an explicit concession relative to ADR-0012 "sub-agent sees only text in/out" discipline.
- [robustness] The native resolves the encoded path internally (scope->path), eliminating the fragile `tr '/' '-'` (ADR-0004/0009 PRIOR NOTE) instead of confining it to the orchestrator as B-mediated did.
