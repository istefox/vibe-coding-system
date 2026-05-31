# ADR-0008 — `concept-to-code` workflow v2: Gate 0, brownfield mode, brainstorm-gate + new `design-brainstorm` skill

**Status:** Accepted  
**Date:** 2026-05-21  
**Author:** istefox  
**Supersedes:** none (extends ADR-0003, does not replace it)  
**Superseded by:** none  
**Related:**
- `docs/architecture/ADR-0003-concept-to-code-chain.md` (Accepted 2026-05-20 — chain v1)
- `docs/architecture/ADR-0007-concept-to-code-e2e-smoke.md` (Accepted 2026-05-20 — smoke-e2e)
- `docs/superpowers/specs/2026-05-21-concept-to-code-workflow-v2-design.md`
- `docs/superpowers/specs/2026-05-21-design-brainstorm-skill-design.md`
- `docs/superpowers/plans/2026-05-21-concept-to-code-workflow-v2.md`
- `~/.claude/skills/concept-to-code/SKILL.md` (skill to patch)
- `~/.claude/skills/concept-to-code/scripts/manifest-{init,validate,transition}.sh`
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` (self-test, baseline PASS=13)
- `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` (smoke, ADR-0007)
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (anchor harness, baseline PASS=49)
- `~/.claude/skills/interview-driver/SKILL.md` (Step 1, produces SPEC)
- `~/.claude/skills/claude-md-generator/SKILL.md` (Step 3, produces CLAUDE.md)
- `~/.claude/agents/architect.md` (dispatched in Step 2)
- Memory `feedback_bash32-constraint.md`
- Memory `feedback_disable-model-invocation-strong.md`
- Memory `feedback_micropiano-refactor-cleanup.md`

---

## 1. Context

ADR-0003 transformed the concept->code workflow (blueprint §11) from prose to a deterministic
state machine with YAML manifest, 5 HITL gates, and pinned dispatch. ADR-0007 added the
smoke-e2e. The **first real use** of the chain (project `rempay`, 2026-05-21) validated it
end-to-end but exposed **three workflow gaps** that share the same intervention point
(`concept-to-code/SKILL.md` + the 3 helper bash scripts): fragmenting them into three separate
ADRs would produce coordination debt on the same file. They are addressed together.

### Gap #1 — Missing Gate 0 (chain-vs-lightweight decision)

The `## 1. When to invoke` section of SKILL.md lists criteria "Do NOT invoke for" (SPEC+ADR
already existing, micro-scope <3 files, iteration on ADR). Today the orchestrator, when it
detects these criteria, decides **silently** whether to run the full chain or fall back to
lightweight workflow. In the real test it fell back without asking; Stefano's manual
intervention was needed to force the chain. The process decision belongs to the user, not
the orchestrator: it is a cost/depth choice, not a technical one.

### Gap #2 — Missing "brownfield mode"

The v1 chain implicitly assumes greenfield: Step 1 interview writes `SPEC.md`, Step 3
`claude-md-generator` regenerates `CLAUDE.md` from scratch. On the rempay project (brownfield)
the orchestrator handled **well but ad-hoc** two cases:
- **Frozen existing SPEC:** it skipped Step 1 (the interview would have overwritten it)
  and pointed `artifacts.spec` to the existing SPEC.
- **Manually crafted CLAUDE.md (97 lines of gotchas):** it understood that `claude-md-generator`
  would regenerate from scratch, degrading the file; it instead produced an **additive** proposal.

These behaviors are correct but not codified -> they depend on the orchestrator's alertness
case by case (fragile, not reproducible, drift guaranteed on the next use).

### Gap #3 — Missing optional brainstorm-gate between SPEC and architecture

Today, once the SPEC is ready, Step 2 dispatches the architect directly who decides the
architecture **alone** (monological). Missing is a dialogical space to explore
alternatives of *application methodology* and *new ideas* WITH the user, before fixing
the ADR. This is the point where a structured exploration makes the most difference on the
final architecture.

### Direction

1. **Gate 0** at chain start: when it detects exclusion criteria, it stops and explicitly
   asks `[c] chain / [l] lightweight / [a] abort`. The decision returns to the user.
2. **Greenfield/brownfield distinction** codified: Steps 1 and 3 behave differently
   depending on the presence of SPEC.md / CLAUDE.md.
3. **Optional brainstorm-gate** between Steps 1 and 2, which invokes a **new
   `design-brainstorm` skill** that explores approach alternatives and produces a
   `BRAINSTORM.md` that feeds the architect dispatch.
4. **New `design-brainstorm` skill** of high methodological quality (see dedicated spec),
   invocable both standalone and from the chain.

### Inherited constraints (HARD)

- **Anchor preservation:** review-triage-fix harness PASS=49, concept-to-code self-test
  PASS=13 — never decrease. Anchor-only append.
- **Bash 3.2.57** for every script: no assoc array, no `mapfile`, no `${v^^}`, no `<()`,
  no here-string. temp-file + grep maps (memory `feedback_bash32-constraint.md`).
- **Coexistence:** the redesign MUST NOT break already completed chains (rempay manifest
  `status: completed` on schema 1.0). The new transitions must be retrocompatible with
  schema 1.0 or introduce schema 1.1 with documented migration.
- **`disable-model-invocation`:** the `design-brainstorm` skill MUST be invocable from
  the chain (brainstorm-gate) -> MUST NOT have `disable-model-invocation: true`
  (memory `feedback_disable-model-invocation-strong.md`).
- **Sub-agents do not spawn sub-agents:** the skill instructs the orchestrator (main CLI).
- **Blueprint repo NON-git:** no git steps in plans.

---

## 2. Decision

The seven architectural questions from the brief are resolved as follows. Each decision has
its rejected alternatives in sec. 3.

### 2.1 (Q1) Skill name: **`design-brainstorm`**

Chosen `design-brainstorm`. Communicates both the *when* (design phase, pre-architecture)
and the *what* (brainstorm of approaches). Frontmatter `name: design-brainstorm`, directory
`~/.claude/skills/design-brainstorm/`.

### 2.2 (Q2) Gate 0 — exclusion criteria detection: **deterministic checks via files + estimate from SPEC, decision to the user**

Gate 0 is part of Form A (start chain), executed right after `manifest-init.sh` (state
`step_0_init`), BEFORE the transition to `step_1_interview`. It detects two criteria with
deterministic checks:

- **Criterion A — "SPEC+ADR already existing":** file check. Does `<project-root>/SPEC.md`
  exist AND does at least one `<project-root>/docs/architecture/ADR-*.md` file exist? Both
  present -> criterion A active.
- **Criterion B — "micro-scope <3 files":** NOT reliably estimable before interview/architecture.
  Therefore Gate 0 does NOT count files: it presents criterion B as a **declarative flag**
  that the user can confirm ("is it a micro-scope?"). The user counts, not the orchestrator.
  This avoids false negatives/positives from fragile heuristics (lesson `swarm-testcmd`:
  better authoritative tier than heuristic).

If no criterion is active -> Gate 0 passes silently (UX unchanged for the common greenfield
case). If at least one criterion is active -> blocks and asks:

```
============================================================
concept-to-code · Gate 0 · TRIAGE CHAIN
============================================================
Exclusion criteria detected:
  [x] SPEC.md + ADR already existing in <project-root>
  [ ] Micro-scope (<3 files) — confirm yourself
Manifest: <manifest-path>
============================================================
HITL Gate 0: chain_triage
  [c] full chain (proceed with interview/architecture)
  [l] lightweight workflow (direct plan, no chain)
  [a] abort chain
> _
```

`[l]` -> `manifest-transition.sh <m> aborted aborted` with `next_action` documenting the
fallback to lightweight workflow (the user continues outside the chain). Not a failure:
it is a legitimate choice. `[a]` -> abort. `[c]` -> proceeds to Step 1.

The criteria detection is encapsulated in a new helper `scripts/gate0-detect.sh`
(bash 3.2-clean) for isolated testability and reuse.

### 2.3 (Q3) Brownfield detection: **automatic (file presence) + user confirmation at Gate 0**

Brownfield is derived deterministically from the presence of `<project-root>/SPEC.md`:

- **Greenfield** (no `SPEC.md`): Step 1 interview produces new SPEC; Step 3 generates
  `CLAUDE.md` (from scratch if absent, additive if present — see below).
- **Brownfield** (`SPEC.md` exists): Step 1 SKIPPED; `artifacts.spec` points to the
  existing SPEC; Gate 1 marked "pre-existing approved spec".

The detection is **automatic** (file check), but **confirmation is implicit at Gate 0**:
when `SPEC.md` exists, criterion A is already active and the user, by choosing `[c]`, is
implicitly confirming they want to proceed in brownfield mode. No separate gate is introduced
for the brownfield confirmation (avoids gate fatigue, known anti-pattern from ADR-0003 §1).

The flag `mode: greenfield|brownfield` is written to the manifest (new top-level field, see
2.6) to make it inspectable and to drive Step 1 and Step 3 behavior deterministically, not at
the orchestrator's discretion.

Orthogonally, Step 3 behavior on existing `CLAUDE.md` becomes **always additive** (never
degrading), regardless of greenfield/brownfield: if `CLAUDE.md` exists, `claude-md-generator`
produces `CLAUDE.md.proposed` in **additive mode** (current CLAUDE.md preserved + section
"## Decisions from chain <topic>" referencing the new ADR), and Gate 3 shows the diff. This
codifies the rempay ad-hoc move.

### 2.4 (Q4) Where `BRAINSTORM.md` lives: **project root + `artifacts.brainstorm` field in manifest**

`BRAINSTORM.md` lives in `<project-root>/BRAINSTORM.md` (same level as SPEC.md/ARCH.md
— positional consistency with the other design artifacts of the chain). The manifest tracks
it with the new field `artifacts.brainstorm` (absent=null, populated when the brainstorm-gate
produces the file). It lives next to SPEC.md and ARCH.md, not in `docs/`, because it is a
high-level artifact (like SPEC/ARCH) and not an archive document.

### 2.5 (Q5 + Q7) State machine: **schema 1.1 with new optional fields; no new mandatory `current_step` state for Gate 0/brownfield; a single new state for the brainstorm-gate**

Guiding principle: minimize new states in the `current_step` enum (every new state =
new legal transitions + risk of breaking smoke-e2e). **Manifest flags** are used where
possible, **new states** only where a cross-session resume point is needed.

- **Gate 0:** is NOT a state. It is a check executed in `step_0_init` before the transition
  to `step_1_interview`. Outcome recorded in the `gate0` field of the manifest. The transition
  `step_0_init -> step_1_interview` remains legal and unchanged. `[l]`/`[a]` use the
  wildcard transition `* -> aborted` already supported.
- **Brownfield:** is NOT a state. It is the flag `mode: brownfield`. In brownfield, Step 1
  is skipped -> the **existing** transition `step_1_interview -> gate_1_spec_review` is used,
  but we need to reach it without a real interview. Solution: in brownfield the orchestrator
  still transitions `step_0_init -> step_1_interview` (the "interview" state exists but is a
  no-op: it points `artifacts.spec` to the existing one) -> `step_1_interview -> gate_1_spec_review`.
  No new transition required. Gate 1 marked "pre-existing spec".
- **Brainstorm-gate:** requires ONE new state `gate_1b_brainstorm_decision` between
  `gate_1_spec_review` and `step_2_architecture`, because it is a point where a potentially
  long brainstorming session can begin and the user can choose y/n. New legal transitions:
  - `gate_1_spec_review -> gate_1b_brainstorm_decision` (effectively replaces the direct path;
    but the direct path `gate_1_spec_review -> step_2_architecture` REMAINS legal for
    retrocompat with v1.0 manifests and existing smoke-e2e).
  - `gate_1b_brainstorm_decision -> step_2_architecture` (outcome n, or completed outcome y).

  Brainstorm-gate `n` -> direct transition to `step_2_architecture` (identical behavior to
  today: direct architect). Brainstorm-gate `y` -> the `design-brainstorm` skill is invoked
  in-session, writes `BRAINSTORM.md`, populates `artifacts.brainstorm`, then transitions to
  `step_2_architecture` with the brief included in the architect dispatch.

- **Schema version:** moved to `manifest_schema_version: "1.1"`. The validator accepts
  **both 1.0 and 1.1** (retrocompat: the completed rempay manifests remain valid). New fields
  (`mode`, `gate0`, `artifacts.brainstorm`) are **optional** in 1.1: `manifest-validate.sh`
  does not require them, but if present validates their values. Documented migration: a 1.0
  manifest is a valid 1.1 manifest without the new fields (additive, forward-only).
  `manifest-init.sh` writes 1.1 with new fields populated.

### 2.6 (Q6) Who writes the manifest: **the `design-brainstorm` skill writes ONLY `BRAINSTORM.md`; the orchestrator (concept-to-code) updates `artifacts.brainstorm`**

Separation of responsibilities consistent with ADR-0003: leaf skills (interview-driver,
claude-md-generator) produce artifacts, the orchestrator (concept-to-code) owns the manifest.
`design-brainstorm` does not know the manifest or the schema -> remains reusable standalone
outside the chain. After `design-brainstorm` returns, the orchestrator writes
`artifacts.brainstorm = <project-root>/BRAINSTORM.md` with the same YAML edit pattern already
used for `artifacts.spec`/`adr`/`plan`.

### 2.7 New bash helper and changes to existing scripts

- **New `scripts/gate0-detect.sh`** (bash 3.2): args `<project-root>`, prints active
  criteria to stdout (`spec_adr_exist` if SPEC.md+ADR present; `mode=greenfield` or
  `mode=brownfield`). Always exit 0 (it is a detector, not a validator). Independently
  testable.
- **`manifest-init.sh`:** writes `manifest_schema_version: "1.1"`, adds fields
  `mode`, `gate0`, and `artifacts.brainstorm: null`. The value of `mode` is passed as
  4th optional argument (default `greenfield`); `init` can call `gate0-detect.sh` to
  derive it, or receive it from the orchestrator.
- **`manifest-validate.sh`:** accepts schema 1.0 OR 1.1; adds `gate_1b_brainstorm_decision`
  to the enum of valid states; if `mode` present, validates it is in {greenfield, brownfield};
  hitl_gates invariant changed from `== 4` to `>= 4` (relaxed to admit a gate0/gate1b in
  the audit trail without breaking manifests with 4 gates). See 3.5.
- **`manifest-transition.sh`:** adds the 2 new legal pairs (see 2.5), preserving the 16
  existing ones.

### 2.8 The `design-brainstorm` skill (summary; detail in dedicated spec)

Explores **application methodology** and **new ideas** BEFORE the architecture is fixed.
Does NOT extract requirements (interview-driver), does NOT write SPEC/plan (rest of chain),
does NOT invoke writing-plans (key difference from `superpowers:brainstorming`, which is a
terminal state and would conflict with the chain). Uses `AskUserQuestion` in a multi-choice
dialogical flow, one technique at a time. Core techniques: first-principles, cross-domain
analogies, inversion, forced constraints, assumption-busting, genuinely different alternatives
(2-4), adjacent ideas. Output: structured `BRAINSTORM.md` (restated problem, challenged
assumptions, 2-4 alternatives with trade-offs, adjacent ideas, preliminary recommendation).
Language: communication in Italian, template in English. No `disable-model-invocation`.

---

## 3. Alternatives considered and rejected

### 3.1 (Q1) Skill name — alternatives

- **`brainstorm-explore`** — rejected: redundant (brainstorm already implies exploration)
  and does not communicate the design phase. Confusable with a generic exploration tool.
- **`design-explore`** — rejected: too generic, semantically overlaps with `interview-driver`
  (the interview also "explores").
- **`approach-brainstorm`** — rejected: "approach" is precise but not idiomatic; `design-`
  as prefix is more readable in the skill namespace.
- **Chosen `design-brainstorm`:** prefix `design-` anchors the phase, `-brainstorm` the
  method. Distinct from `interview-driver` (requirements) and from `superpowers:brainstorming`
  (which writes spec).

### 3.2 (Q2) Gate 0 — alternatives

- **Automatic file count for micro-scope** — rejected: impossible to estimate files to touch
  before interview/architecture without fragile heuristics (number of existing files !=
  files to touch). False positives/negatives would undermine trust in the gate. Lesson from
  `swarm-testcmd`: prefer authoritative tier (the user) over heuristic.
- **Automatic orchestrator decision (status quo)** — rejected: it is exactly Gap #1. The
  choice is a process/cost decision, belongs to the user.
- **Gate 0 always shown even in clean greenfield** — rejected: unnecessary gate fatigue on
  the common case (new project without SPEC/ADR). Gate 0 is silent when no criterion is active.
- **Chosen:** deterministic checks (file presence) for criterion A; user-confirmed declarative
  flag for criterion B; gate shown only if at least one criterion is active.

### 3.3 (Q3) Brownfield detection — alternatives

- **Explicit via CLI flag** (`/concept-to-code --brownfield <topic>`) — rejected: the user
  should not need to know if it is greenfield/brownfield; the presence of SPEC.md is the
  authoritative signal. Manual flag = forgettable = drift.
- **Only automatic, without confirmation** — rejected: would risk skipping the interview on
  a project where the user WANTED to regenerate the SPEC. The implicit confirmation at Gate 0
  covers the case without a dedicated gate.
- **Dedicated brownfield gate separate from Gate 0** — rejected: two consecutive gates at
  startup = fatigue. Merged into the `[c]` choice of Gate 0.
- **Chosen:** automatic (SPEC.md presence) + implicit confirmation in the `[c]` choice of
  Gate 0 + `mode` flag in manifest for determinism.

### 3.4 (Q4) Position of BRAINSTORM.md — alternatives

- **Section of the YAML manifest** — rejected: the brief is long and dialogical prose;
  it would pollute the manifest (which must remain parsable via grep in bash 3.2) and
  violate the "manifest = state, file = artifact" separation of ADR-0003.
- **`docs/brainstorm/<date>-<topic>.md`** — rejected: too hidden for an artifact the user
  must read before approving the architecture; inconsistent with SPEC.md/ARCH.md at project
  root.
- **`docs/superpowers/specs/`** — rejected: that folder is for design specs of the *system*,
  not for brainstorming briefs of *target projects*.
- **Chosen:** `<project-root>/BRAINSTORM.md` + `artifacts.brainstorm` in the manifest.

### 3.5 (Q5) State machine — alternatives

- **No new states, everything as flags** — rejected for the brainstorm-gate: the brainstorm
  can be a long session; a named resume point and an inspectable outcome are needed. For Gate 0
  and brownfield, flags suffice (no long work to resume).
- **Three new states (gate_0, brownfield_skip, gate_1b)** — rejected: gate_0 and brownfield
  do not need a cross-session resume point (they are instantaneous at startup); adding states
  = more legal transitions = more breakage surface for smoke-e2e and validate. Only
  `gate_1b_brainstorm_decision` is added.
- **Rewrite schema from scratch to 2.0** — rejected: would break the completed rempay
  manifests. Additive schema 1.1 is retrocompatible.
- **Strict `hitl_gates == 4` invariant maintained** — rejected: would block the possible
  Gate 0/1b audit trail. Relaxed to `>= 4` (additive: existing manifests with 4 gates
  remain valid).
- **Chosen:** additive schema 1.1; 1 new state (`gate_1b_brainstorm_decision`); 2 new pairs;
  direct path `gate_1_spec_review -> step_2_architecture` preserved for retrocompat;
  `hitl_gates >= 4`.

### 3.6 (Q6) Who writes the manifest — alternatives

- **`design-brainstorm` also writes `artifacts.brainstorm`** — rejected: would couple the
  skill to the manifest schema, breaking its standalone reusability and violating the
  separation of responsibilities of ADR-0003 (leaf skills do not know the manifest).
- **Chosen:** `design-brainstorm` writes only `BRAINSTORM.md`; concept-to-code updates
  `artifacts.brainstorm`.

### 3.7 (Q7) Brainstorm-gate=n fallback — alternatives

- **Different behavior from today (e.g. mini-prompt)** — rejected: the brief explicitly
  requires that `n` be identical to the current behavior (direct architect). Zero regressions
  for users who do not use the brainstorm.
- **Chosen:** `n` -> transition to `step_2_architecture`, identical architect dispatch to
  ADR-0003 (no `BRAINSTORM.md`, `artifacts.brainstorm` remains null).

---

## 4. Consequences

### Positive

- Gaps #1/#2/#3 resolved together at a single intervention point -> zero coordination debt
  on SKILL.md.
- The chain-vs-lightweight and greenfield-vs-brownfield decisions become **deterministic and
  reproducible**, no longer dependent on the orchestrator's alertness.
- The brainstorm-gate adds high-quality dialogical exploration without altering the default
  path (n = current behavior).
- Total retrocompat: additive schema 1.1, direct path preserved, completed rempay manifests
  remain valid.
- `design-brainstorm` is reusable standalone and from the chain (no `disable-model-invocation`).

### Negative

- Increases the surface of SKILL.md (Gate 0 + 1b + brownfield branching) -> more complex
  to read. Mitigated by the updated State machine section and a clear schema diagram.
- Schema 1.1 introduces a dual version check (1.0 OR 1.1) in the validator -> slightly more
  complexity.
- New skill = new harness to keep green (maintenance debt).
- The `mode` flag adds a point where the orchestrator must act correctly; mitigated by the
  fact that `gate0-detect.sh` derives it deterministically.

### Neutral

- `BRAINSTORM.md` is optional: absent when the brainstorm-gate is `n`.
- The lightweight workflow chosen at Gate 0 exits the chain (manifest `aborted` with
  `next_action` documented); it is not managed by the chain beyond that point.
- Number of HITL gates variable (4 without brainstorm, 5+ with) — consistent with the
  optional nature of the brainstorm-gate.

---

## 5. References

- ADR-0003 (chain v1), ADR-0007 (smoke-e2e).
- Spec workflow v2: `docs/superpowers/specs/2026-05-21-concept-to-code-workflow-v2-design.md`.
- Spec skill: `docs/superpowers/specs/2026-05-21-design-brainstorm-skill-design.md`.
- Plan: `docs/superpowers/plans/2026-05-21-concept-to-code-workflow-v2.md`.
- Blueprint §11 (concept->code workflow), §8 (skill).
- Memory: `feedback_bash32-constraint.md`, `feedback_disable-model-invocation-strong.md`,
  `feedback_micropiano-refactor-cleanup.md`.
