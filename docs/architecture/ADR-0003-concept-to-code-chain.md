# ADR-0003 — `concept-to-code` orchestrator skill for the concept->code chain

**Status:** Accepted  
**Date:** 2026-05-20  
**Author:** istefox  
**Supersedes:** none  
**Superseded by:** none  
**Related:**
- `docs/superpowers/specs/2026-05-20-concept-to-code-chain-design.md`
- `docs/superpowers/plans/2026-05-20-concept-to-code-chain.md`
- `docs/vibe-coding-system.md` (blueprint sec. 11 — concept->code workflow)
- `~/.claude/skills/interview-driver/SKILL.md` (custom user skill, reused)
- `~/.claude/skills/adr-writer/SKILL.md` (custom user skill, reused)
- `~/.claude/skills/claude-md-generator/SKILL.md` (custom user skill, reused)
- `~/.claude/agents/architect.md` (sub-agent dispatched in Step 2)
- `~/.claude/agents/coder.md` (sub-agent dispatched in Step 5, already has Pre-flight Pattern Classifier ADR-0001)
- `~/.claude/agents/reviewer.md` (item 5 Pattern-drift check, ADR-0001)
- `~/.claude/agents/refactorer.md` (Snapshot Harness Integration, ADR-0002)
- `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2 Add+Remove rule, optionally invoked in Step 6)
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (anchor harness target, PASS=45 baseline 2026-05-20)
- ADR-0001 (Pre-flight Pattern Classifier, Accepted 2026-05-20)
- ADR-0002 (Refactor Snapshot Harness, Accepted 2026-05-20)
- Memory `feedback_bash32-constraint.md`
- Memory `feedback_micropiano-refactor-cleanup.md`

---

## 1. Context

The multi-agent system blueprint (`docs/vibe-coding-system.md` sec. 11) describes the
concept->code workflow as a linear chain with implicit HITL gates:

```
interview -> SPEC.md -> ARCH.md (+ ADR) -> project CLAUDE.md ->
  fresh session -> scaffold in plan mode -> multi-agent impl -> review -> commit
```

Today this workflow is **prose**, not executable. Every deployed feature follows the chain
from the orchestrator's memory. Three converging pieces of evidence motivate the intervention.

### Evidence

1. **Repeated pattern in the 2026-05-20 session.** Two manual dispatches of
   `architect` -> `coder` were done in the same day (ADR-0001 + ADR-0002) with
   nearly identical prompt templates. Manual repetition is the signature of missing automation.
   Potential drift between dispatches (e.g. brief variants, manually copied HARD constraints).

2. **Workflow blueprint sec. 11 is a recommendation, not a skill.** The gap between
   blueprint and practice translates into inconsistency between consecutive features: ADR-0001
   generated 8 TDD tasks, ADR-0002 generated 8 with similar but not identical structure. The
   drift is invisible until two plans are compared side-by-side.

3. **The 3 features deployed 2026-05-20** (ADR-0001 coder pre-flight + ADR-0002
   refactor-snapshot + review-triage-fix v1.2 Add+Remove) share the *same* flow
   `architect produces 3 deliverables -> coder implements 6-8 TDD tasks`. A single
   orchestrator skill would have reduced 3 manual dispatches to 1, with drift zeroed
   by construction.

### Architectural problem

The concept->code workflow is a *deterministic state machine* (Steps 1..6, HITL gates,
fresh session checkpoint, cross-session manifest) but today is codified as descriptive prose.
Four consequences:

- **Cross-feature drift:** every architect->coder dispatch reinvents the prompt template.
- **State loss at Step 4 (fresh session):** when the orchestrator opens a new session it loses
  all the interview/ADR/CLAUDE.md context. Today it re-anchors by re-reading the files, but
  without guarantee it resumes from the right point.
- **Implicit HITL gates:** the user does not know in advance how many gates there are or what
  they approve. Today "concept-to-code" *seems* atomic but involves 3-4 HITL turns.
- **Fragile coexistence with 2026-05-20 deployed features:** Pre-flight Pattern Classifier
  (coder), Pattern-drift check (reviewer), Snapshot Harness (refactorer) are active but not
  orchestrated. A manual dispatch can skip them without error.

### Direction

Introduce a **callable markdown skill** `concept-to-code` in
`~/.claude/skills/concept-to-code/` that codifies the blueprint sec. 11 chain as an
executable state machine with:

- **Persistent YAML manifest** in `docs/manifests/YYYY-MM-DD-<topic>.manifest.yml`
  of the target project, preserving chain state across fresh-session boundaries.
- **Explicit HITL gates** (3 blocking + 1 informative fresh-session checkpoint).
- **Resume semantics** via `/concept-to-code resume <manifest-path>` after fresh session.
- **Pinned dispatch** to existing agents (`architect`, `coder`) with prompt templates
  versioned inside the skill (no drift by construction).
- **Reuse** of the 3 existing custom skills: `interview-driver` (NOT
  `superpowers:brainstorming`), `adr-writer`, `claude-md-generator`.
- **Orthogonal coexistence** with ADR-0001 / ADR-0002 / v1.2: the skill *invokes* the
  deployed features, not replaces them.

The objective: transform the concept->code chain from "recommended prose" to "skill with
deterministic state machine and guardrails", reducing drift and HITL fatigue.

### Inherited constraints (HARD)

- **Anchor preservation `review-triage-fix` harness:** PASS=45 post ADR-0002
  (2026-05-20). Never decrease. Post-feature target: **PASS=47** (+2 structural anchors
  in `review-triage-fix/tests/run-tests.sh` on skill `concept-to-code` existence and
  reference to manifest schema — see Decision §2.10).
- **Skill self-test target:** the `concept-to-code` skill has its own harness in
  `tests/run-tests.sh`. Target **PASS=10** (10 assertions: manifest schema validation,
  step-state transitions, resume semantics, override safe-to-restart, contract invariants).
- **Bash 3.2.57** for every skill helper script (manifest parser/validator). No
  assoc array, no `mapfile`, no `${v^^}`, no `<()` process substitution, no
  here-string. Pattern already consolidated by the 45 anchors of the review-triage-fix
  harness and by the 11 refactor-snapshot self-tests.
- **Sub-agents do not spawn sub-agents** (blueprint sec. 2). The skill is an instruction
  for the **orchestrator** (main CLI agent), not for sub-agents. Dispatches of
  `architect`/`coder` originate from the orchestrator (main CLI session), NEVER from
  a sub-agent. The markdown skill clarifies this invariant explicitly in its body.
- **Fresh session caveat (blueprint sec. 11):** the skill MUST respect the "fresh
  session" between interview/architecture (Steps 1-3) and implementation (Step 5) because
  the orchestrator's context window fills up with interview Q&A. The YAML manifest is
  the cross-session state-passing mechanism.
- **Coexistence with 2026-05-20 deployed features:** Pre-flight Pattern Classifier
  (coder, ADR-0001), Pattern-drift check (reviewer, ADR-0001), Snapshot Harness
  (refactorer, ADR-0002), Add+Remove rule v1.2 — **all remain active and unchanged**.
  The skill USES these features, it does not edit them.
- **No backwards-compat shim:** if the skill modifies `coder.md` to support
  `--manifest` input, it is a clean substitution (no legacy parallel flag). BUT: the
  current decision (see §2.9) is to **not modify coder.md**: the skill passes the manifest
  content in the dispatch prompt, not as an external argument.
- **Language:** SKILL.md in English (contract), ADR/spec/plan/memory in Italian,
  manifest YAML field names in English, commits/code in English.
- **Blueprint repo NON-git:** vibe-coding-system has no git initialized. The plan does not
  propose git operations for doc deliverables. The skill itself, when executed on a
  git-tracked target project, does NOT propose a commit in Step 6: the commit remains
  a manual HITL gate for the user (consistent with global CLAUDE.md).
- **Auto mode for this architect dispatch:** no HITL during design. However,
  the skill design includes HITL at runtime (see §2.4).

### Explicit assumptions (not empirically verified)

- The orchestrator (main CLI agent) honors the instructions of a markdown skill with
  `disable-model-invocation: false`. Verified from the usage pattern of
  `interview-driver`, `adr-writer`, `claude-md-generator`. Not verified for skills
  with multi-step state machine and resume.
- The `docs/manifests/` directory can be created in the target project without
  conflict with existing conventions. For current pilot projects (e.g.
  `pricing-markup-cli`, `swarm-testcmd`) verified as safe (free path).
- The user accepts 3 synchronous HITL gates in the base flow (Steps 1-3) as a trade-off
  against drift. Rationalized by the memory `feedback_hitl-and-security-discipline.md`
  ("security warnings must be taken seriously, conservative rewrite") — the user prefers
  explicit gates to silent dispatches.
- The fresh session in Step 4 is actually opened by the user in a new shell CLI Claude
  Code. Not automatable from the skill side (the skill cannot `exec claude --new-session`).
  Resolved via explicit instruction + manifest pickup.

---

## 2. Decision

Deploy the skill `~/.claude/skills/concept-to-code/` as orchestrator of the concept->code
chain, decomposed into the 10 decisions that follow. Each corresponds to one of the 10
architectural questions from the brief.

### 2.1 — Component form (Q1)

**Decision:** callable markdown skill in `~/.claude/skills/concept-to-code/SKILL.md`
+ 3 bash 3.2 helpers in `scripts/` (manifest validator, step-state transition,
resume detector) + self-test in `tests/run-tests.sh`. NO dedicated slash command,
NO dedicated agent.

**Rationale:** the skill is the native primitive of Claude Code for instructing the
main agent (see pattern of `interview-driver`, `adr-writer`, `claude-md-generator`
already in use). Slash commands would be a duplicate layer on top of the skill. A
dedicated `orchestrator-chain` agent would violate the HARD constraint from blueprint sec. 2
("sub-agents do not spawn sub-agents"): the orchestrator is already the main session,
not a sub-agent. The skill is invoked via user prompt
(`/skill concept-to-code <topic>` or natural pattern "do the concept->code chain
for <topic>") and dispatches agents from the orchestrator.

### 2.2 — State persistence (Q2)

**Decision:** manifest YAML in
`<project-root>/docs/manifests/YYYY-MM-DD-<topic-slug>.manifest.yml`. State
machine fields: `version`, `topic`, `created_at`, `current_step`, `status`,
`artifacts.{spec,arch,adr,plan,project_claude_md}` with absolute paths, `hitl_gates`
list with approval timestamps, `session_boundary` flag (true after Step 4), `next_action`
hint string.

**Rationale:** manifest YAML is user-readable (debug), versionable in
git with the target project, persists cross-session by design (Step 4 fresh
session opens the manifest, does not reconstruct state from prompt). JSON was
a candidate but YAML is more human-readable for the use case (the user *must* be able to
read the manifest to manually unblock a stall). State inline in the prompt fails at the
Step 4 boundary (context window lost). No persistence fails at resume (no anchor for
where to continue). Path under `docs/manifests/` follows existing convention (`docs/architecture/`,
`docs/superpowers/specs|plans/`).

### 2.3 — Resume/restart semantics (Q3)

**Decision:** explicit command invoked by the user in a fresh session:
`/skill concept-to-code resume <manifest-path>`. Auto-detection NO (too
implicit, risk of picking up the wrong manifest). The skill, receiving the
`resume` invocation, reads the manifest, validates the structure via
`scripts/manifest-validate.sh`, checks the `current_step` field, and proceeds
from Step 5 if `current_step == "ready_for_implementation"`. If the manifest
has `current_step` prior to Step 4, fails with error: "resume not
necessary, continue from existing session". If the manifest has
`status: completed`, fails with error: "chain already complete".

**Rationale:** explicit invocation avoids ambiguity (the user chooses which
manifest to resume; coexistence with in-flight manifests of other projects).
Auto-detection rejected: with multiple open projects the risk of picking the
wrong one is high. Pre-resume validation via bash helper is cheap and blocks
corrupted manifests (e.g. incorrect manual editing).

### 2.4 — HITL gate count + type (Q4)

**Decision:** **3 blocking HITL gates** + 1 informative fresh-session checkpoint + 1 optional
review gate.

| Gate    | Type          | After Step | What it shows                                       | What it waits for                     |
| ------- | ------------- | --------- | --------------------------------------------------- | ------------------------------------- |
| Gate 1  | blocking      | Step 1    | path SPEC.md + 5-line summary                       | confirm "spec ok" / edit request     |
| Gate 2  | blocking      | Step 2    | path ADR + ARCH + plan + key decisions              | confirm "architecture ok" / edit     |
| Gate 3  | blocking      | Step 3    | path CLAUDE.md generated + diff if overwrite        | confirm "project memory ok" / skip   |
| Gate 4  | checkpoint    | Step 4    | manifest path + resume command                      | no wait (informative)                |
| Gate 5  | optional      | Step 6    | review report + propose review-triage-fix cycle     | "run review" / "skip review"         |

**Rationale:** 3 synchronous gates map the 3 "promise" boundaries of the workflow
blueprint (spec->arch, arch->memory, memory->impl). Step 4 is NOT a gate: the skill
cannot force the fresh session, it can only instruct. Step 5 is NOT a gate: once the
coder is dispatched, the sub-agent manages its own flow (with Pre-flight Pattern
Classifier ADR-0001 which is itself a form of self-gate). Step 6 review is optional
because the review-triage-fix v1.2 cycle has a non-trivial cost and is not always
justified. Blocking > informative because the memory `feedback_hitl-and-security-discipline.md`
reinforces the user preference for explicit gates over silent drift. Future auto mode
(not in scope of this ADR) can bypass Gate 1 and Gate 3, NEVER Gate 2 (architecture
decisions are practically irreversible).

### 2.5 — Interview skill choice (Q5)

**Decision:** **use the existing custom skill `interview-driver`**
(`~/.claude/skills/interview-driver/SKILL.md`). NOT `superpowers:brainstorming`.
NOT create a new skill.

**Rationale:** `interview-driver` is already custom-tuned for the user's workflow:
uses `AskUserQuestion` tool, one question at a time, outputs SPEC.md in the current
folder with standard sections. `superpowers:brainstorming` is an official superpowers
skill but not guaranteed for stability over time (depends on the superpowers package);
moreover its output might not be strict-SPEC. Creating a new `interview-driver-v2`
would introduce gratuitous drift (3 parallel custom interview skills). Maintaining a
single custom source reduces maintenance surface. The `concept-to-code` skill invokes
`interview-driver` as Step 1 and expects `SPEC.md` in the cwd (path captured in the
manifest).

### 2.6 — CLAUDE.md handling (Q6)

**Decision:** **diff-aware with HITL gate**. If `CLAUDE.md` does not exist at
the target project root, generate it (via `claude-md-generator` skill) and
show it to the user at Gate 3. If it already exists, run `diff CLAUDE.md
CLAUDE.md.proposed` and show the diff at Gate 3 with options:
`overwrite` / `merge manual` / `skip`. Default: `skip` (conservative).

**Rationale:** blind overwrite risks destroying carefully crafted CLAUDE.md files
from the user (e.g. the `vibe-coding-system` project itself has a CLAUDE.md of
~80 lines with specific references to the authoritative spec). Diff-aware is the
safe-by-default option. Skip-by-default respects the user preference "never overwrite
an existing file without first showing the diff" (global CLAUDE.md, Security & Guardrails
section). Append-only rejected: CLAUDE.md is usually reorganized semantically, blind
append breaks the structure. Manual merge is the explicit solution for the ambiguous
case (the user reads the diff, decides manually, then re-invokes the skill).

### 2.7 — Sub-agent dispatch enforcement (Q7)

**Decision:** **structural anchor test in the review-triage-fix harness**
(+2 anchors on existence of `~/.claude/skills/concept-to-code/SKILL.md` and
reference to `manifest_schema_version` in the SKILL.md). Strict skill template:
the body of SKILL.md contains the literal prompt template (triple-backtick block)
that the orchestrator MUST copy into the dispatch to architect/coder. No "describe
what you want", only "execute exactly this prompt".

**Rationale:** guaranteeing that the orchestrator actually follows the skill
and does not improvise is impossible in absolute terms (the orchestrator is an LLM,
it can always diverge). Mitigation in layers:
1. SKILL.md with literal prompt template (reduces variability in dispatch).
2. Skill self-test harness that validates the manifest schema (detects
   corrupted manifests due to improvisation).
3. Structural anchor test in the review-triage-fix harness (detects
   removal/breakage of the skill).
4. HITL gates at runtime (the user can catch divergence at Gate 1/2/3).

There is no bullet-proof guarantee; there is defense-in-depth.

### 2.8 — Failure mode (Q8)

**Decision:** **state machine "abort, no auto-retry"**. If the architect
dispatch fails mid-way (API overload, tool error, agent timeout), the skill
marks `manifest.current_step.status = failed` with a `failure_reason` field,
writes the last available output (partial ADR/plan/spec if it exists) to
paths as `*.partial`, and stops. The user decides manually: re-invoke the skill
with the same topic (restart from last green Step) or abandon (manual delete of
the manifest). No auto-retry, no skip-to-next.

**Rationale:** auto-retry risks amplifying the problem (rate limit loop). Skip-to-next
breaks the dependency chain (Step 3 without a green Step 2 generates CLAUDE.md on
an inconsistent architecture). Manual resume preserves user control. The `failure_reason`
field is a diagnostic hint (e.g. `"architect_timeout_60s"`, `"api_overload_529"`,
`"file_write_permission_denied"`). Consistent with global CLAUDE.md "If you cannot verify
a result, report it — do not assume it works".

### 2.9 — Coexistence with manual dispatches (Q9)

**Decision:** **the skill becomes "default" but NOT "mandatory"**.
Manual dispatches of `architect` and `coder` remain possible and valid.
The `concept-to-code` skill does not modify `architect.md` or `coder.md`.
The blueprint repo README (dedicated section in `docs/vibe-coding-system.md`
or GUIDA-CREARE-PROGETTO.md — future, not in scope of this plan) mentions
the skill as the preferred entry point.

**Rationale:** strict mandatoriness would violate the "power-user override always
available" principle. Legitimate bypass examples: critical hotline fix (no time for
complete chain), iteration on existing ADR (no new interview), micro-scope feature
(skip Step 3 CLAUDE.md). The skill wins if the user chooses it for natural fit,
not because it is forced.

### 2.10 — Final output (Q10)

**Decision:** triple output. (a) **Markdown report** printed in chat at the end
of Step 6 with: files generated, total duration, HITL gates passed, harness
deltas, link to manifest. (b) **Manifest update** to `status: completed` +
`completed_at` timestamp. (c) **Memory entry** auto-suggested but NOT auto-written:
the skill composes the text of an entry for `MEMORY.md` (line `## Project`) and
shows it to the user at Gate 5 with options `append` / `skip`. No OS-level notification.

**Rationale:** markdown report is auditable and copy-paste-able. Manifest update is
already implicit in the state machine, but making it explicit in the contract avoids
stale manifest. Auto-suggested memory entry resolves the pattern observed in the current
MEMORY.md (manual entries always written in the same format by the user: "[topic](project_<slug>.md)
— DEPLOYED YYYY-MM-DD description"); auto-write would violate the "no unrequested side effects"
principle (the brief itself cites the `agent-notes/architect.md` case as an unwanted
preceding side effect).

### Summary of 10 decisions

| Q  | Decision                                                                 |
| -- | ------------------------------------------------------------------------- |
| Q1 | Markdown skill `concept-to-code` + 3 bash helpers + self-test            |
| Q2 | Manifest YAML in `docs/manifests/YYYY-MM-DD-<topic>.manifest.yml`         |
| Q3 | Explicit resume: `/skill concept-to-code resume <manifest-path>`          |
| Q4 | 3 blocking HITL + 1 checkpoint + 1 optional review                       |
| Q5 | Reuse existing `interview-driver`, NOT `brainstorming`, NOT new skill     |
| Q6 | CLAUDE.md diff-aware, default `skip` if it exists                         |
| Q7 | Defense-in-depth: literal prompt template + self-test + anchor + HITL     |
| Q8 | Abort no-retry, `failure_reason` field, manual user resume                |
| Q9 | Default but not mandatory; manual dispatches remain valid                 |
| Q10 | MD report + manifest `completed` + HITL auto-suggested memory entry      |

---

## 3. Alternatives considered

For each of the 10 questions, at least one rejected alternative with the reason for
rejection. Summary tables for readability.

### Q1 — Component form

- **Dedicated slash command `/concept-to-code`** — *rejected*: duplicate layer
  on top of the skill. Custom slash commands require `.claude/commands/` setup
  (per-repo) or framework override. The markdown skill is invocable both
  via natural language ("do the concept->code chain for X") and via the official
  prefix (`/skill concept-to-code`), covering both cases without extra files.
- **Dedicated agent `orchestrator-chain`** — *rejected*: would violate blueprint
  sec. 2 ("sub-agents do not spawn sub-agents"). The orchestrator is the main agent
  of the CLI session, not a sub-agent. A new `orchestrator-chain` agent would be a
  sub-agent calling other sub-agents — not supported.
- **Combination skill + dedicated agent** — *rejected*: superfluous complexity.
  The skill alone is sufficient; adding an agent introduces duplicate intent (both
  the skill and the agent would define the same state machine).

### Q2 — State persistence

- **JSON file in `.claude/state/concept-to-code-<topic>.json`** — *rejected*:
  JSON is less human-readable. The user *must* be able to read/edit the manifest in
  case of a stall (e.g. correct a stale path). YAML wins for readability.
- **Inline in the prompt (pure functional state machine)** — *rejected*:
  fails at the Step 4 fresh session boundary. The context window of the new session
  does not contain the previous state.
- **No persistence (re-derivable from files)** — *rejected*: re-deriving state
  from SPEC.md/existing ADRs is heuristic (file timestamps? last modification?)
  and fragile. Explicit manifest is deterministic.

### Q3 — Resume semantics

- **Auto-detection of in-flight manifest** — *rejected*: risk of picking up the
  wrong manifest in the presence of multiple open projects. The user might have 3
  pending manifests in 3 projects; auto-pickup of the "most recent" is heuristic,
  not deterministic.
- **Override safe-to-restart (force resume even if completed)** — *rejected*:
  silent overwrite of already consolidated state. If completed, the skill fails and
  suggests the user create a NEW manifest (no `resume --force`).

### Q4 — HITL gate count + type

- **All gates informative (show and proceed)** — *rejected*: violates the explicit
  user preference for HITL gates (memory `feedback_hitl-and-security-discipline.md` +
  global CLAUDE.md sec. HITL).
- **All gates blocking including Step 4 and Step 5** — *rejected*: Step 4 CANNOT
  be a synchronous gate (skill cannot force opening a new session). Step 5 coder
  dispatch is itself an autonomous sub-process; adding HITL before dispatch is
  redundant (Gate 2 already covers it).
- **Only 1 final HITL (mega-gate)** — *rejected*: 1 final gate = user approves or
  rejects the entire chain as a block. Granular edits become impossible (e.g. "spec
  ok but ADR needs revision" requires 2 independent gates).

### Q5 — Interview skill choice

- **Official `superpowers:brainstorming`** — *rejected*: external dependency
  (superpowers package), uncontrolled evolution, output not strict-SPEC.
  The custom `interview-driver` skill is already authoritative for the user.
- **New `interview-driver-v2`** — *rejected*: 2 parallel custom interview skills
  create maintenance drift. Refining the existing `interview-driver`, if needed,
  is preferable.
- **Mix (brainstorming for draft, interview-driver for refinement)** —
  *rejected*: 2 invocations for Step 1 double the duration and introduce
  variability between draft and refinement.

### Q6 — CLAUDE.md handling

- **Always overwrite** — *rejected*: would destroy manually crafted CLAUDE.md files
  (e.g. the one in the `vibe-coding-system` repo with references to the spec). Violates
  global CLAUDE.md guardrail.
- **Only if it does not exist (silent skip)** — *rejected*: user does not learn
  that a potential update would have occurred. Diff-aware with HITL is more transparent.
- **Append-only** — *rejected*: CLAUDE.md has semantic structure; blind append breaks
  it (duplicate sections, chaotic ordering).

### Q7 — Sub-agent dispatch enforcement

- **Strict template + hook validator** — *rejected*: hooks that inspect the orchestrator
  prompt pre-dispatch are not the pattern used today (hooks in `~/.claude/hooks/` are for
  test-cmd and stop-gate, not for prompt inspection). Adding a new hook for this is scope
  creep.
- **Only strict skill template (without anchor harness)** — *rejected*: the skill can
  be accidentally modified or deleted; without anchor in `review-triage-fix/tests/run-tests.sh`
  the regression passes silently.
- **Only HITL gates (no defense-in-depth)** — *rejected*: HITL fatigue is a real risk
  (see memory). More layers = less dependence on a single gate.

### Q8 — Failure mode

- **Auto-retry with backoff** — *rejected*: rate limit / API overload loop becomes
  pernicious. The user prefers explicit abort (decides retry manually).
- **Skip-to-next with `--continue` flag** — *rejected*: Step N+1 depends on
  Step N (CLAUDE.md generated requires valid ARCH.md). Skip breaks the dependency
  invariant.
- **Automatic rollback to previous checkpoint** — *rejected*: intermediately generated
  files (partial SPEC.md) are manually recoverable; auto-delete is destructive without
  clear benefit.

### Q9 — Coexistence with manual dispatches

- **Forced via hook (disable manual dispatch)** — *rejected*: power-user override is
  explicitly preserved (global CLAUDE.md "Proactivity" implies expert user chooses
  the flow). A hook blocking manual dispatches would be hostile.
- **Soft warning on manual dispatch ("consider concept-to-code")** — *rejected*: noise
  in the recurring dispatch pattern. User memory remembers the skill, no inline nudge
  is needed.

### Q10 — Final output

- **Only markdown report (no manifest update)** — *rejected*: stale manifest remains
  in flight, falsifies future auto-detection (if ever implemented). State machine
  consistency requires an explicit terminal status.
- **Auto-write to MEMORY.md** — *rejected*: unrequested side effect. The brief itself
  cites the `agent-notes/architect.md` case as an unwanted preceding side effect.
  Auto-suggest + HITL append is the correct line.
- **OS-level notification (Hammerspoon/AppleScript)** — *rejected*: scope creep,
  platform dependency, outside the contract of a markdown skill.

---

## 4. Consequences

### Positive

- **Cross-feature drift zeroed:** prompt template versioned inside the skill, every
  architect/coder dispatch is byte-faithful identical by construction. ADR-0004 + ADR-0005
  + ADR-NNN will use the same flow.
- **Deterministic state machine:** YAML manifest is inspectable, debuggable,
  versionable. Stall mid-chain = user-readable manifest that decides how to proceed.
- **Explicit HITL gates:** the user knows in advance there are 3 blocking gates.
  No surprises like "I thought it was atomic but it asks 4 confirmations".
- **Fresh session boundary cleanly resolved:** Step 4 + manifest YAML + Step
  5 resume = cross-session transition without state loss, without re-prompting the user.
- **Orthogonal coexistence with ADR-0001/ADR-0002/v1.2:** Pre-flight Pattern
  Classifier (coder), Pattern-drift check (reviewer), Snapshot Harness (refactorer)
  remain active and naturally invoked in Step 5 (impl) and Step 6 (review). Triple-angle
  drift coverage "code change vs intent" + new chain orchestration = quadruple-angle.
- **Existing custom skills reused:** `interview-driver`, `adr-writer`,
  `claude-md-generator` finally orchestrated in a unified chain.
- **Sub-agent constraint respected:** the skill instructs the orchestrator
  (main agent), no sub-agent spawning. Blueprint sec. 2 unchanged.
- **Complete auditability:** manifest + final report + auto-suggested memory entry
  = 3 levels of trace.

### Negative

- **Increased maintenance surface:** 1 new skill + 3 bash helpers + 1 self-test harness.
  Estimate ~250 lines markdown + ~250 lines bash. Future changes to `interview-driver`/`adr-writer`/`claude-md-generator`
  API require skill alignment.
- **HITL fatigue risk:** 3 synchronous gates in the base flow. If the user does 5 concept-to-code
  cycles in a week, that is 15 confirmations. Future mitigation: auto-mode flag to skip Gate 1
  and Gate 3 (NOT Gate 2). Not in scope of this ADR.
- **Stale manifest as silent failure mode:** if the user abandons a chain mid-way without
  marking the manifest, the file stays in flight. No auto-cleanup. Mitigation: updated
  `MEMORY.md` and the fact that the manifest is inspectable reduce the risk of confusion.
- **Initial learning curve:** the skill has 6 steps, 3 gates, 1 resume command. More complex
  than a manual architect dispatch (1 step, 0 gates). Mitigation: dedicated doc + final report
  that explains what happened.
- **Implicit dependency on `interview-driver`:** if the user decommissions
  `interview-driver`, the `concept-to-code` skill breaks. Hard-coded path in the SKILL.md
  body. Mitigation: anchor harness on existence of `~/.claude/skills/interview-driver/SKILL.md`
  (out of scope for this plan, candidate for future plan).

### Neutral

- **No edit to `architect.md` or `coder.md`:** decision §2.9. The skill passes the
  manifest content in the dispatch prompt, no external flag. Consistent with "no
  backwards-compat shim" because there is no pre-existing feature to shim.
- **No hook modification:** the skill is pure markdown + bash userland. No
  `settings.json` / `.mcp.json` / hook touch.
- **No superpowers skill dependency:** the `concept-to-code` skill does not import
  `superpowers:brainstorming` or other superpowers skills. Autonomy from external packages.
- **Manifest schema versioning:** field `manifest_schema_version: "1.0"` mandatory.
  Future schema changes via version bump. No migration tool in v1.0 (manual refactoring of
  existing manifests if schema changes).
- **Absolute vs relative path in manifest:** choice of absolute paths
  (`/Users/stefanoferri/...`) for consistency with existing MEMORY.md pattern. Constraint:
  manifest not portable between machines. Accepted: the manifest is local state, not a
  shared artifact.

---

## 5. References

- Blueprint: `docs/vibe-coding-system.md` sec. 11 (concept->code workflow)
- Spec design: `docs/superpowers/specs/2026-05-20-concept-to-code-chain-design.md`
- Implementation plan: `docs/superpowers/plans/2026-05-20-concept-to-code-chain.md`
- Orchestrated skill (interview): `~/.claude/skills/interview-driver/SKILL.md`
- Orchestrated skill (ADR): `~/.claude/skills/adr-writer/SKILL.md`
- Orchestrated skill (CLAUDE.md): `~/.claude/skills/claude-md-generator/SKILL.md`
- Sub-agents dispatched in chain: `~/.claude/agents/architect.md`, `~/.claude/agents/coder.md`
- Features deployed 2026-05-20 (coexistence):
  - ADR-0001 `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md`
  - ADR-0002 `docs/architecture/ADR-0002-refactor-snapshot-harness.md`
  - review-triage-fix v1.2 `~/.claude/skills/review-triage-fix/SKILL.md`
- Anchor harness baseline: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` PASS=45 (2026-05-20)
- Memory: `feedback_bash32-constraint.md`, `feedback_hitl-and-security-discipline.md`,
  `feedback_micropiano-refactor-cleanup.md`
