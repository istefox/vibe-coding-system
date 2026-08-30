# ADR-0182 — `VCS-055` Phase 2.3: adopt native `memory: project` on `reviewer`, retire ADR-0012 for it

- **Status:** Accepted
- **Date:** 2026-08-30
- **Supersedes (for `reviewer` only):** ADR-0012's mediated `PRIOR AGENT NOTES`/`DURABLE NOTES:`
  contract, as applied to `reviewer`. `architect` and `debugger` are unaffected — see Decision.
- **Related:** ADR-0012 (orchestrator-mediated agent memory, still active for `architect` and
  `debugger`), ADR-0013 (2026-05-25 native-memory pilot on `architect`, rejected after a measured
  failure), ADR-0038 Correction 2026-08-30 (`memory-store-guard.sh`, the hook this decision
  depends on).

## Context

ADR-0013 tried to replace ADR-0012's mediated mechanism system-wide with the native `memory:`
field and was rejected: the pilot agent (`architect`, `memory: local`) used the broad Write access
`memory:` grants to edit a file **outside** its own memory directory — the orchestrator's own
curated auto-memory. ADR-0012 stayed the active mechanism, with a standing re-evaluation clause
(`ADR-0012-agent-memory-orchestrator-mediated.md:319-321`): *"If the pilot showed that harvest is
systematically forgotten or that produced notes are valueless, the decision should be re-evaluated
towards A [gitignore] or C [removal]."*

VCS-055 closed the mechanism that made ADR-0013's failure possible in the first place and then
re-ran the pilot properly, guarded:

- **Phase 2.1** shipped `memory-store-guard.sh`, a PreToolUse hook denying any sub-agent
  (`.agent_id` set) a write into the orchestrator's curated store
  (`~/.claude/projects/*/memory/`) — the exact path ADR-0013's pilot agent reached. Live-verified:
  a dispatched probe was denied with this hook's reason string; an orchestrator write to the same
  path was allowed.
- **Phase 2.2** ran a guarded pilot of `memory: project` on `reviewer` only, from a throwaway
  scratch project, never this repo. Two trials plus a cross-dispatch persistence check gathered
  the evidence below.
- **This step (2.3)** presents that evidence and records the adoption decision.

### Pilot evidence

1. `.claude/agent-memory/reviewer/MEMORY.md` and a topic file were created and populated,
   following the documented native-memory save process — no orchestrator mediation involved.
2. Nothing was written outside the memory directory in either trial (`git status` clean both
   times).
3. `memory-store-guard.sh` itself was separately confirmed live (see Phase 2.1 above) — the
   ADR-0013 failure path is closed regardless of what any future `memory:` pilot does.
4. **Persistence across independent dispatches.** A second, independently-dispatched `reviewer`
   invocation — told nothing about memory, style, or the prior trial's specific finding —
   surfaced and applied a convention saved during the first dispatch, unprompted. Sub-agent
   dispatches do not inherit prior conversation; this can only be the native memory auto-load
   reading `MEMORY.md` at dispatch time, not conversational carry-over.

### The re-evaluation clause fired, in the opposite direction to the one it named

ADR-0012's clause anticipated harvest being *forgotten* or notes being *valueless* as the trigger
to move away from mediation. What the pilot actually showed is that native memory **replaced**
mediation outright and worked better: reviewer's ADR-0012 harvest never had to run during the
pilot, and the native mechanism produced durable, cross-dispatch-persistent notes without any
orchestrator involvement. This is a different observation than the clause's literal wording, but
the same underlying question — does mediation still earn its "recurring orchestrator burden and
harvest risk" (ADR-0012's own words) for this agent — and it resolves the same way: no, not for
`reviewer`, once the ADR-0013 failure mode is structurally closed.

### The scoping question this ADR had to resolve before deciding anything

ADR-0013's own closing `DURABLE NOTES:` recorded, as an accepted tradeoff: *"The native `memory:`
auto-enables Write/Edit even on read-only agents (e.g. reviewer): acceptable because confined to
the memory dir."* That "confined" claim was never verified at the time — it was an assumption.
This session verified it live, before touching anything else:

- `reviewer.md`'s declared `tools:` frontmatter (undisturbed) carries **no** `Edit`/`Write` at
  all — the agent reports findings, it does not apply them (ADR-0045, issue #58).
- With `memory: project` added temporarily, a diagnostic-only probe dispatch of `reviewer`
  reported both `Edit` and `Write` present, with **no path restriction in the tool schema
  itself** — `file_path` is an unconstrained absolute-path string, in principle reachable to any
  file, not just `.claude/agent-memory/reviewer/`.

So ADR-0013's "confined" assumption was false: `memory:` grants broad, unscoped Write/Edit, the
same shape as its own 2026-05-25 failure — it is only reviewer's *own choice not to write
elsewhere*, observed across two pilot trials, that kept it inside its memory directory. Observed
good behavior is not a structural guarantee, and `review-triage-fix/SKILL.md`'s advisor-call
dispatch explicitly relies on reviewer being unable to make changes even if asked — a claim that
would become false the moment `memory: project` is made permanent, unless something enforces it.

## Decision

**Adopt `memory: project` on `reviewer` permanently. Retire the ADR-0012 mediated mechanism
(`PRIOR AGENT NOTES` inject / `DURABLE NOTES:` harvest) for `reviewer` specifically.**
`architect` and `debugger` are unaffected — this is not a system-wide supersession of ADR-0012,
only a per-agent exception now that the pilot has demonstrated it is safe for this one agent
under this one guard.

`project` scope (checked-in, versioned in git) rather than `local` (gitignored, per-machine) is
deliberate: review conventions and recurring-issue notes are project knowledge that should follow
the repo and be visible to every session and machine that runs `reviewer` on it, not private
per-machine state. This differs from Phase 1's `coder` cleanup, which retired a broken, effectively
dead `memory: local` pilot for an unrelated reason — that removal is not evidence against `project`
scope here.

**New enforcement, closing the gap ADR-0013 left open:** `reviewer-write-scope.sh`, a PreToolUse
hook gated on `.agent_type == "reviewer"`, denies any `Edit`/`Write` outside
`.claude/agent-memory/reviewer/`. This makes the "reviewer cannot make changes even if asked"
claim structurally true again — enforced by a hook, not by the agent's own restraint — closing
exactly the gap this ADR's Context section found in ADR-0013's assumption.

### Consequences

- `review-triage-fix/SKILL.md`'s reviewer-specific ADR-0012 inject/harvest paragraph is removed;
  its advisor-call clause is reworded to describe the guard-enforced boundary instead of "no
  Edit/Write in its tool grant" (no longer true at the schema level, now true at the enforced
  level). The debugger-specific block is untouched — debugger stays on ADR-0012 without change.
- The two memory mechanisms (ADR-0012 mediated, native `memory:`) no longer coexist on
  `reviewer` — they did coexist briefly during the Phase 2.2 pilot trial, which ran with both
  wired, precisely so the pilot could be compared against the mediated mechanism's absence.
- Any pre-existing `memory/agent-notes/reviewer.md` (the old mediated store, if it has content)
  becomes historical. It is **not** migrated into native memory and **not** deleted by this
  decision — deletion requires its own explicit confirmation per the standing "never delete files
  without explicit confirmation" rule. It is disclosed here as orphaned, nothing more.
- `agent-notes-harvest.sh` needs no code change — it was already fully generic, parameterized by
  agent name, with no reviewer-specific logic. Only its two callers changed.

## Alternatives considered

- **Keep ADR-0012 for reviewer, do nothing.** Rejected: the pilot evidence shows native memory
  works better for this agent with no measured downside once the write-scope gap is closed, and
  ADR-0012's own clause invites re-evaluation on exactly this kind of evidence.
- **Adopt native memory for architect and debugger too, in the same pass.** Rejected as
  out-of-scope for this decision: those agents were not piloted this round, and folding them in
  would extend a scoped, guarded decision into an unverified one. Nothing here forecloses a future
  ADR doing the same analysis for them.
- **`memory: local` instead of `project`.** Rejected: review conventions are shared project
  knowledge, not per-machine state; `local` would silently lose them on every new machine/session.

## References

- ADR-0012 — `docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` (re-evaluation
  clause, lines 319-321).
- ADR-0013 — `docs/architecture/ADR-0013-native-subagent-memory-supersede-mediated.md` (the
  rejected pilot, the "confined to memory dir" assumption this ADR verified false; see its
  Correction 2026-08-30 below).
- `staging/plugin/scripts/memory-store-guard.sh` (Phase 2.1, the guard this pilot depended on).
- `staging/plugin/scripts/reviewer-write-scope.sh` (new, this ADR's own enforcement).
- `staging/plugin/agents/reviewer.md` (frontmatter + Process/Output Format edits).
- `staging/plugin/skills/review-triage-fix/SKILL.md` (Step 1 — Review and advisor-call clause
  edits; debugger block untouched).
- This session's live pilot evidence (2026-08-30): two `reviewer` dispatches from
  `~/Developer/_scratch/memory-pilot-reviewer-test`, plus one diagnostic-only tool-grant probe.
