# ADR-0012 — Cross-session agent memory mediated by the orchestrator (removal of `docs/agent-notes/` from the project tree)

**Status:** Accepted  
**Date:** 2026-05-24  
**Author:** istefox  
**Supersedes:** none  
**Superseded by:** none  
**Related:** ADR-0003 (`concept-to-code` skill orchestrator of the chain — is the point where
the injection/collection agent-notes contract is inserted), ADR-0001 (Coder pre-flight pattern
classifier — precedent of the "structured report contract" pattern in the subagent report,
reused here for `DURABLE NOTES:`), ADR-0004 (Pre-flight Pattern Enforce Hook — source of the
project-dir encoding fragility that this decision avoids on the subagent side), ADR-0005
(Vibe-status skill — candidate read-only watch of the agent memory round-trip).

> **Remains the ACTIVE mechanism.** Confirmed by Stefano (2026-05-24): label `DURABLE NOTES:`, path `memory/agent-notes/<agent>.md` separate from `MEMORY.md`, manual harvest outside chain, read-only watch in vibe-status, re-evaluation clause.
>
> _(2026-05-25: ADR-0013 had attempted to replace it with the native `memory: local` feature, but the **pilot failed** — the agent with `memory:` wrote outside its sandbox, into the curated auto-memory; ADR-0012 mediation, in which sub-agents have no Write on memory, prevents that risk. Migration rejected, see ADR-0013 "Rejected after pilot".)_

---

## Context

### Today's mechanism: two parallel memory systems

The system has **two** cross-session memory mechanisms, independent and redundant:

1. **Central orchestrator auto-memory.** A per-project store under
   `~/.claude/projects/<encoded-project-dir>/memory/`, with a curated index `MEMORY.md`
   (sections Project/Feedback/Reference, links to per-topic files) and per-topic files with
   YAML frontmatter (`node_type: memory`, `type`, `originSessionId`). Managed exclusively by
   the **orchestrator** (main CLI session), which has access to the encoded path of the harness.
   Lives **outside** the tree of any target project.

2. **Per-project agent-notes.** Three active sub-agents have a separate mechanism: they
   read and **append** durable patterns/decisions to `docs/agent-notes/<agent>.md`
   *inside the tree of the project they are working on*. Exact points verified in the live
   definitions:
   - `~/.claude/agents/architect.md`: Process point 5 (line ~33) "Check
     `docs/agent-notes/architect.md` … After designing, append new durable
     decisions/patterns to it (create the file/dir if absent)"; Edge Cases "Write scope"
     (line ~64) includes `docs/agent-notes/architect.md`.
   - `~/.claude/agents/debugger.md`: Process point 2 (line ~28) "Check
     `docs/agent-notes/debugger.md` … for similar past issues" and point 6 (line ~32)
     "Append the bug pattern + resolution to `docs/agent-notes/debugger.md`".
   - `~/.claude/agents/reviewer.md`: Process point 3 (line ~29) "Check
     `docs/agent-notes/reviewer.md` … Append newly observed recurring patterns".

   (There is also `~/.claude/agents/refactorer.md.bak-2026-05-20` with the same pattern, but
   it is an **inactive** `.bak` — cited only as history; the live `refactorer.md` no longer
   has the mechanism.)

### The conflict, and why it recurs

A doc-discipline rule — "no session scaffolding in the tracked tree" — lives in the
**CLAUDE.md of target coding projects**, NOT in the shared config `~/.claude/`. Verified: a
grep of `agent-notes` on `~/.claude/agents` finds only the 3 definitions + the `.bak`; a grep
of the anti-scaffolding phrase ("session scaffold"/"tracked tree") on `~/.claude/agents` and
`~/.claude/skills` **finds nothing**; the `claude-md-generator` skill is not aware of the
agent-notes mechanism (does not generate it or make exceptions for it).

Consequence: every run of the architect (or debugger/reviewer) **recreates** an untracked file
`docs/agent-notes/<agent>.md` that **violates** the project's rule and must be removed before
the PR. Since the mechanism is **by-design** (the agents MUST append to that path), a one-off
deletion does not resolve it: the file **recurs** on every dispatch. The conflict is structural,
not an incident.

### Verified facts (2026-05-24)

- The 3 agent definitions above contain read+append to `docs/agent-notes/<agent>.md`
  (including the explicit write-scope of `architect.md`). Live `refactorer.md`: clean; only
  the historical `.bak` retains the pattern.
- The anti-scaffolding rule is NOT in the shared config (empty grep on agents+skills).
- The auto-memory store exists and has the described structure (curated index `MEMORY.md` +
  per-topic files with frontmatter), under
  `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/`.
- The `concept-to-code` chain **already injects conditional directives via dispatch
  prompt-template** (Step 2 architect with brief; Step 5 coder; `[IF manifest.anonymize=true]`
  blocks) and already passes "a literal prompt template at dispatch time" without patching the
  agent SKILL.md (SKILL.md lines ~167-271, ~544). It is the natural insertion point for the
  injection/collection contract.
- The fragility of the project-dir encoding is documented (memory
  `feedback_pretooluse-payload-schema.md`): Claude Code converts `_`->`-` (and potentially
  other characters, rule not stable between versions); re-encoding `cwd` with `tr '/' '-'`
  produces incorrect paths; the robust way is to derive the dir from `dirname(transcript_path)`.
  A subagent that had to resolve the encoded store path by itself would fall into this trap (it
  has already cost a badly implemented ADR — ADR-0004 v1.0/v1.1).

### Explicit assumptions (NOT validated)

- It is assumed that **agent memory has sufficient value** to not simply be removed (see
  Alternative C): the design **preserves** it by moving it, not eliminating it. If in practice
  agents never produce useful durable notes, Alternative C would become the simplest choice.
- It is assumed that the recurring burden on the orchestrator (inject before, collect after each
  dispatch) is sustainable within the chain, where dispatch is already mediated by prompt-template.
  Outside the chain (direct dispatch to a subagent) the burden falls on the orchestrator's
  discipline: risk of **forgetting the harvest** -> see Consequences and the required watch.

---

## Decision

Adopt **Option B-mediated**: move cross-session agent memory **outside the project tree, into
the central auto-memory**, but with access **mediated by the orchestrator** — sub-agents
**never** directly access the store or resolve the encoded path. The `docs/agent-notes/`
mechanism in the tree is **removed**.

### D1 — Three-phase contract: injection -> collection -> persistence

1. **Injection (pre-dispatch).** The orchestrator — which has access to the auto-memory store
   — reads the relevant agent-notes for the agent it is about to dispatch and **injects them
   into the dispatch brief**, in a delimited block. Proposed form, to be inserted into existing
   templates (Step 2 for architect, and analogous for debugger/reviewer when dispatched from
   the chain or directly):

   ```
   PRIOR AGENT NOTES (read-only context — past durable decisions/patterns for this agent
   on this project; factor in, do not repeat work already settled):
   <content of agent-notes/<agent>.md from the store, or "none yet">
   ```

   If no notes exist, the block reports `none yet` (never omitted entirely: its presence
   signals to the agent that the channel exists).

2. **Collection (post-report).** The sub-agent **does not access the memory**. It returns
   durable notes in a **structured and terminal section of its report**, with a machine-greppable
   header (same spirit as the `PATTERN:` contract of ADR-0001, readable by both the orchestrator
   and a potential watch):

   ```
   DURABLE NOTES:
   - [<category>] <durable pattern/decision, 1-2 lines> (<optional context: file:line / ADR>)
   - ...
   (or the literal line "DURABLE NOTES: none" if there are no new notes)
   ```

   Format rules: exact header `DURABLE NOTES:` on its own line; each note is a bullet;
   explicit `none` if empty (so the orchestrator can distinguish "no notes" from "truncated
   report" — consistent with the lesson `feedback_subagent-truncation-transport.md`).

3. **Persistence (post-dispatch).** The orchestrator writes/updates those notes in a **dedicated
   subfolder** of the central store, **separate from the curated `MEMORY.md` index** to not
   pollute it:

   ```
   ~/.claude/projects/<encoded-project-dir>/memory/agent-notes/<agent>.md
   ```

   `MEMORY.md` remains the manually curated index of project topics; `agent-notes/` is the
   append-only namespace of agents' operational notes, not linked from the index. Resolution of
   the encoded path is **always and only** the orchestrator's responsibility (which already
   manages it for the rest of the auto-memory), never the subagent's.

### D2 — Sub-agents never touch the store or the encoded path

HARD constraint: none of the 3 agent definitions must contain a path to the store or path
encoding resolution logic. This eliminates at the root the documented fragility (`_`->`-`,
`dirname(transcript_path)` vs `cwd`): the only component that knows the path is the
orchestrator. The subagent sees only text (brief in, report out).

### D3 — Migration of the 3 agent definitions

Remove from `architect.md`, `debugger.md`, `reviewer.md` (in `~/.claude/agents/`):

- The step "Check `docs/agent-notes/<agent>.md` … for past decisions/patterns" ->
  replaced by: "factor in the `PRIOR AGENT NOTES` block if present in your brief".
- The step "Append … to `docs/agent-notes/<agent>.md` (create file/dir if absent)" ->
  replaced by: "emit a terminal `DURABLE NOTES:` section in your report (format above);
  do NOT write any file for memory".
- In `architect.md`, remove `docs/agent-notes/architect.md` from the "Write scope" (leaving only
  `docs/architecture/**`).

The historical `.bak` (`refactorer.md.bak-2026-05-20`) must **not** be touched (it is inactive;
touching it would be noise). Live `refactorer.md` is already clean.

### D4 — The contract is explicit in the chain (and in the dispatch protocol in general)

The injection+collection step becomes a **contract of the `concept-to-code` chain** (ADR-0003):
the dispatch templates of Step 2 (architect) — and the points where the chain dispatches
debugger/reviewer (e.g. the review cycle at Step 6) — add the `PRIOR AGENT NOTES` block on
input and, after the report, the orchestrator performs the harvest of the `DURABLE NOTES:` block
towards `memory/agent-notes/<agent>.md`. For **direct dispatch** (outside chain), the rule
must be documented in the orchestrator's dispatch protocol as a standard step. Pattern already
in use (injection via prompt-template, zero patch to SKILL.md): this is additive and consistent.

### D5 — `claude-md-generator` no longer generates the conflicting rule

`claude-md-generator` must **stop being able to generate/inherit** a doc-discipline rule that
prohibits `docs/agent-notes/` in the tracked tree, because after this migration that path **is
no longer created** by any agent. Concrete verification during implementation: if the skill (or
its templates/examples) mentions `agent-notes` or an anti-scaffolding rule related to it, remove
the mention; the additive directive of Step 3 remains unchanged for the rest. (Note: the current
grep does not find `agent-notes` in the skills — the rule lives in the CLAUDE.md of generated
target projects; the action is to ensure the generator does not **re-introduce** it.)

### D6 — Round-trip watch (testability)

The central risk is **forgetting the harvest** (orchestrator does not collect `DURABLE NOTES:`
-> memory is silently lost). A **deterministic round-trip harness** on fixtures is recommended,
independent of a live session:

- injection: given a fixture store with `agent-notes/<agent>.md`, the dispatch template produces
  the `PRIOR AGENT NOTES` block with that content (or `none yet` if absent);
- collection: given a fixture report containing a well-formed `DURABLE NOTES:` section, the
  orchestrator parser extracts the bullets correctly, distinguishes `none`, and tolerates a
  truncated report (does not write ambiguous partial notes);
- persistence: the append ends up in `memory/agent-notes/<agent>.md`, **never** in `MEMORY.md`.

Moreover, `vibe-status` (ADR-0005) is a natural candidate for **signaling** in a read-only way
the presence/freshness of `memory/agent-notes/` as part of the health report (non-blocking).
What is NOT testable headless (that the orchestrator *remembers* to harvest in a real session)
remains an open question to validate in pilot — honesty consistent with
ADR-0008/0009/0010/0011.

---

## Consequences

### Positive

- **Conflict resolved at the root.** No agent creates files in the tracked tree anymore -> the
  anti-scaffolding rule of target projects is no longer violated; no recurring pre-PR cleanup,
  no per-project `.gitignore` to add.
- **Consolidated memory.** A single memory system (the central auto-memory), with a dedicated
  `agent-notes/` namespace separate from the curated index -> end of the redundancy of the two
  parallel systems.
- **Survives clean-public-repo / git clean / clone.** The notes live outside the repo: a
  `clean-public-repo` (ADR-0011), a `git clean`, a fresh clone or publication does not touch
  them and does not expose them. (Previously, living in the tree, they were both a risk of
  exposure and a target of removal.)
- **Encoding fragility eliminated on the subagent side.** Only the orchestrator resolves the
  encoded path; sub-agents never fall into the `_`->`-` / `cwd` vs
  `dirname(transcript_path)` trap (ADR-0004, `feedback_pretooluse-payload-schema.md`).
- **Pattern consistent with the system.** Injection via prompt-template (already used) +
  structured report (`DURABLE NOTES:`, sister of `PATTERN:` from ADR-0001): no new paradigm.

### Negative

- **Recurring burden on the orchestrator.** Every dispatch of the 3 agents requires two extra
  steps: inject notes before, collect `DURABLE NOTES:` after. In the chain it is automated by
  templates; in direct dispatch it is the orchestrator's discipline.
- **Risk of forgetting the harvest.** If the orchestrator does not collect, memory is silently
  lost. Mitigation: explicit contract in the chain (D4) + round-trip harness + read-only signal
  in vibe-status (D6). Remains an operational risk for dispatch outside the chain.
- **Loss of portability with the project.** Notes no longer travel with the repo: someone who
  clones the project on another machine/account does not inherit the agent memory (previously,
  living in the tree, it was — improperly — portable). Trade-off accepted: those notes are
  session scaffolding, not artifacts to share with the project.
- **Coupling to the internal harness path.** The design couples persistence to the
  `~/.claude/projects/<encoded>/memory/` layout — but the coupling is confined to the
  orchestrator (which already manages it), not propagated to sub-agents.

### Neutral

- **New namespace `memory/agent-notes/<agent>.md`** in the store, separate from `MEMORY.md`.
  Append-only, not linked from the curated index.
- **Historical `.bak` unchanged** (`refactorer.md.bak-2026-05-20`): stays as is, cited only as
  history.
- **Repo `vibe-coding-system` NON-git:** the deliverable of this ADR is the sole markdown.
  The deploy of live artifacts (patch to 3 agent definitions, chain `concept-to-code` patch,
  possible `claude-md-generator` patch, new harness) is a **separate task** (TDD plan), **without
  commit step**, after Stefano's approval.
- **Manifest schema unchanged.** The injection/collection contract is conveyed via prompt-template
  and dispatch protocol; does not require new manifest fields or new state machine states.

---

## Alternatives considered

### A — Keep `docs/agent-notes/` but gitignore it (per-project)

Minimal, near-zero risk (agents do not change). By adding `docs/agent-notes/` to the
`.gitignore` of the target project, the file never ends up in the tracked tree and does not
violate the anti-scaffolding rule. **Rejected** because: (1) leaves **two parallel memory
systems** (consolidates nothing — the redundancy problem remains); (2) requires a line of
`.gitignore` in **every** target project (per-project recurring burden, easy to forget on a
new repo -> falls back into the conflict); (3) notes remain inside the working tree -> still at
risk in publication/cleanup scenarios, even if not tracked. Resolves the symptom (tracking) but
not the cause (memory in the wrong place).

### B-naive — Sub-agent writes directly to the encoded store path

Would eliminate the orchestrator burden (no collection). **Rejected** because **fragile and
coupled to the harness encoding**: the sub-agent would have to resolve `<encoded-project-dir>`
by itself, and the encoding rule is unstable between Claude Code versions (`_`->`-` and more;
`cwd` re-encoded != real path). It is exactly the trap that has already produced blocking bugs
(ADR-0004 v1.0/v1.1, `feedback_pretooluse-payload-schema.md`). Concentrating path knowledge in
the **sole** orchestrator is the robustness principle that B-mediated adopts.

### C — Remove the agent-notes mechanism entirely

The simplest: remove the read/append steps from the 3 definitions and nothing else, without
replacing them. **Rejected** because it **loses cross-session agent memory** — the value that
the mechanism, even if poorly located, provided (a debugger that remembers a recurring bug
pattern, an architect that remembers a past decision). If in pilot it emerged that agents never
produce useful durable notes, C would become the most economical choice; today the assumption
is that the memory is worth its cost (see Assumptions).

### D — Commit notes in the tracked tree (change the rule)

Keep `docs/agent-notes/` and **change** the doc-discipline rule to allow it (versioning notes
with the project). **Rejected** because notes are **session scaffolding**, not product artifacts
to share: committing them bloats history, exposes them in a public repo (in direct tension with
ADR-0011), and makes noise in PRs. The anti-scaffolding rule exists for a reason; changing it
to accommodate a misplaced mechanism is resolving the conflict from the wrong side.

### Why B-mediated despite the cost

B-mediated is the only option that **consolidates** the memory (a single system), **resolves
the conflict at the root** (no file in the tree), **avoids the encoding fragility** (only the
orchestrator knows the path), and **preserves the value** of agent memory (unlike C). The price
is the recurring orchestrator burden and the harvest risk, both mitigatable (contract in chain
+ harness + vibe-status signal).

**Explicit tension with "Building Effective Agents" (Anthropic):** the principle "do not add
complexity until the simple fails" would push towards Alternative A (git-ignore) or C (removal).
The choice of B-mediated is justified only because **the simple has already failed in a recurring
way** (one-off deletion cannot hold a by-design mechanism) **and** because the system already
has the infrastructure (auto-memory + dispatch via prompt-template) that makes B-mediated an
extension of existing patterns, not a new paradigm. If the pilot showed that harvest is
systematically forgotten or that produced notes are valueless, the decision should be
re-evaluated towards A or C — this tension remains a declared open question.

---

## References

- `~/.claude/agents/architect.md` (Process p.5 ~line 33; Write scope ~line 64) — read+append
  and write-scope towards `docs/agent-notes/architect.md` to remove.
- `~/.claude/agents/debugger.md` (Process p.2 ~line 28, p.6 ~line 32) — read+append to remove.
- `~/.claude/agents/reviewer.md` (Process p.3 ~line 29) — read+append to remove.
- `~/.claude/agents/refactorer.md.bak-2026-05-20` — inactive `.bak` with same pattern
  (historical; do not touch).
- `~/.claude/skills/concept-to-code/SKILL.md` — dispatch via prompt-template (Step 2 architect
  ~167-202, Step 5 coder ~259-271, note "not patched / literal prompt template" ~544); insertion
  point for the injection/collection contract.
- `~/.claude/skills/claude-md-generator/SKILL.md` — must not re-introduce the conflicting rule
  (D5).
- Auto-memory store: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/`
  (`MEMORY.md` curated index + per-topic files with frontmatter) — model for the `agent-notes/`
  namespace separate.
- `feedback_pretooluse-payload-schema.md` (same store) — project-dir encoding fragility
  (`_`->`-`, `dirname(transcript_path)` vs `cwd`) avoided on subagent side (D2).
- `feedback_subagent-truncation-transport.md` (same store) — why explicit `DURABLE NOTES: none`
  is needed to distinguish "no notes" from "truncated report".
- ADR-0003 — `docs/architecture/ADR-0003-concept-to-code-chain.md` (chain where the contract is
  inserted).
- ADR-0001 — `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (precedent of
  the machine-greppable structured report, sister of `DURABLE NOTES:`).
- ADR-0004 — `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` (source of the
  encoding fragility).
- ADR-0005 — `docs/architecture/ADR-0005-vibe-status-skill.md` (candidate read-only watch of
  the round-trip).
- ADR-0011 — `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` (notes outside the
  tree survive clean-public-repo / fresh-history publish).

## Correction (2026-08-31)

This ADR's mediated mechanism is now retired in full. `reviewer` moved off it first
(ADR-0182, VCS-055); `architect`, `debugger`, and the newly-covered `tester`/`refactorer`/
`doc-writer` moved onto native `memory:` persistence together in **ADR-0183**
(`docs/architecture/ADR-0183-native-memory-rollout-all-agents.md`, VCS-056). No agent depends on
`agent-notes-harvest.sh` or the `PRIOR AGENT NOTES`/`DURABLE NOTES:` contract described above after
that decision; the helper and its round-trip harness were deleted. `coder` was never subject to
this mechanism and remains excluded from native memory too, on a separate, measured basis (ADR-0183
Phase 0). This note records the outcome going forward; the ADR's original text above is left as the
correct snapshot of its own day (rule 14).
