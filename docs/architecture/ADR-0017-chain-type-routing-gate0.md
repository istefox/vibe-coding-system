# ADR-0017 — Chain-Type Routing at Gate 0

**Status:** Accepted  
**Date:** 2026-05-29  
**Context:** concept-to-code skill v2 (schema 1.2 → 1.3)

---

## Problem

The concept-to-code chain was designed for complex multi-layer features requiring an ADR,
a fresh implementation session, and parallel coder dispatch. For simple apps (<10–20 files,
single session of work), the chain's overhead — 13 gates, a fresh-session boundary, and
parallel sub-agent dispatch — degrades output quality compared to native plan mode:

1. **Context loss at the fresh session boundary.** The coder starts with only SPEC.md,
   ARCH.md, and CLAUDE.md. Interview nuance, user corrections, and tacit preferences are gone.
2. **Parallel dispatch creates integration blind spots.** Each coder implements its own
   component without owning the wiring layer.
3. **No iterative feedback during implementation.** In native plan mode the model adjusts
   as it discovers issues; the chain does not.

CleanKey and NotchDrop (2026-05-29 field test) confirmed this: both built correctly and both
built successfully, but the architecture and runtime behavior were harder to validate precisely
because the chain over-engineered the dispatch for the complexity involved.

## Decision

Replace the binary Gate 0 triage (chain / lightweight / abort) with a **three-path routing
choice** shown at every invocation. An auto-detect heuristic pre-selects a recommendation;
the user confirms or overrides.

### The three paths

| Path | Trigger | Session | Artifacts | Sub-agents |
|---|---|---|---|---|
| **Express** | <10 files, no prior spec/ADR | Single | Manifest only | None (orchestrator executes directly) |
| **Hybrid** | 5–20 files, 1–2 layers | Single | Manifest + SPEC.md | None (plan mode + direct execution) |
| **Standard** | Complex, multi-layer, ADR needed, or `spec_adr_exist=true` | Fresh session | Manifest + SPEC + ARCH + ADR + Plan | Parallel coders (Step 5) |

### Auto-detect heuristic (three signals, majority vote)

1. **File estimate** — `find <root>` excluding `.git/`, `node_modules/`, `.venv/`, `build/`,
   `DerivedData/`. Buckets: <10 → express, 10–19 → hybrid, ≥20 → standard.
2. **spec_adr_exist** — from existing `gate0-detect.sh`. If true → standard (forced; user
   still sees the Gate 0 question for confirmation).
3. **Keyword vote on topic title** — `architecture|migration|multi.layer|multi.service|
   api.design|adr` → standard; `app|feature|module|screen|endpoint|view|component` → hybrid;
   neither → express.

Majority vote of the three signals determines the recommendation. Ties involving standard → standard.
All three agree on express AND `spec_adr_exist=false` → Gate 0 can be shown with express pre-selected.

### Gate 0 new display (always shown, 4 options)

```
question: "Gate 0 — Chain routing\n\nRecommended: [<path>] — <auto_detect_reason>\n\nChoose the orchestration path for: <topic-full-title>"
header: "Gate 0 · Chain"
options:
  - label: "[e] Express — native plan, single session, no docs"
    description: "Best for: <10 files, prototype, script. Zero sub-agents."
  - label: "[h] Hybrid — interview → SPEC.md, then plan mode in same session"
    description: "Best for: 5–20 files, 1–2 layers, structured requirements without ADR overhead."
  - label: "[s] Standard — full chain: interview → ADR → plan → fresh session → agents"
    description: "Best for: complex features, multi-layer, ADR required, or spec_adr_exist=true."
  - label: "[a] Abort"
    description: "Terminate the chain."
```

Gate 0 now **always fires** (previously conditional). The old silent path (no Gate 0 shown)
is removed; the question takes <2 seconds to answer and eliminates the implicit standard default.

### Express path state machine

```
step_0_init → step_e1_plan → step_e2_execute → gate_e3_verify → step_e4_commit → completed
```

- **E1**: `EnterPlanMode` — read project files, propose a 3–6 task plan, wait for plan approval.
- **E2**: `ExitPlanMode` — execute the plan with direct tool calls (Edit/Write/Bash). No sub-agents.
- **Gate E3**: `AskUserQuestion` — show files modified, test result (if test-cmd exists), three options: commit now / commit later / abort.
- **E4**: invoke `commit` skill.

### Hybrid path state machine

```
step_0_init → step_h1_interview → gate_h1_spec_review
  → [gate_h1b_brainstorm →] step_h2_plan → step_h3_execute → gate_h3_verify
  → [step_h4_review →] step_h5_commit → completed
```

- **H1**: `interview-driver` skill → SPEC.md (identical to standard Step 1).
- **Gate H1**: spec review (identical to standard Gate 1).
- **Gate H1b**: optional brainstorm (identical to standard Gate 1b).
- **H2**: `EnterPlanMode` — read SPEC.md + project files, propose 4–8 task plan.
- **H3**: `ExitPlanMode` — execute in-session with direct tool calls. No sub-agents.
- **Gate H3**: verify + review decision (commit now / run review-triage-fix / abort).
- **H4**: conditional `review-triage-fix`.
- **H5**: `commit` skill (with optional Gate 5.5 humanize if `manifest.humanize=true`).

## Manifest schema 1.3 changes

New top-level field (additive, null-defaulted, backward-compatible with 1.0–1.2):
```yaml
chain_path: null         # express | hybrid | standard | null (legacy)
```

New fields inside `gate0:` block:
```yaml
gate0:
  decision: null
  chain_path: null           # mirrors top-level for gate audit trail
  auto_detect_reason: null   # e.g. "file_estimate=7,keyword=hybrid,spec_adr=false → hybrid"
  criteria_spec_adr_exist: false
  decided_at: null
```

`manifest-validate.sh` additions:
- Invariant 1: accepts 1.3.
- Invariant 9: gate count check becomes conditional — standard requires ≥4, hybrid ≥3, express ≥2.
- Invariant 13: if `chain_path` present and non-null, must be `express|hybrid|standard`.
- VALID_STEPS expanded with 8 Express states + 8 Hybrid states.

## Constraints and risks

**Plan-mode isolation rule exception.** SKILL.md section "Skill isolation" prohibits `EnterPlanMode`.
This must be explicitly carved out for Express step E1 and Hybrid step H2. The carve-out is
scoped to these two steps only; the prohibition remains for all standard-path steps.

**Hybrid context window limit.** The hybrid path keeps the full interview context alive through
planning and execution. Hard limit: 20 files. Above this, context compaction during step H3 can
lose the plan. Use the standard path for projects above 20 files.

**Express: no worktree isolation.** Failures during step E2 leave partial edits in the working
tree. The user must run `git status` and reset manually. Documented limitation; not a blocker.

**Resume semantics.** Express and hybrid chains do not cross session boundaries. Form B resume
(`/skill concept-to-code resume <manifest>`) is valid only for `chain_path=standard` or
`chain_path=null` (legacy). Attempting to resume an express or hybrid manifest emits an error.

## Alternatives considered

**Keep the binary gate 0 and improve the standard chain for simple apps.** Rejected: the
structural problem (fresh-session context loss + parallel dispatch silos) cannot be fixed inside
the standard path without making it a different path. The routing gate is the correct abstraction.

**Auto-select with no user confirmation.** Rejected: auto-selection is a recommendation, not
a decision. The user's knowledge of intent always overrides heuristics. The Gate 0 question
takes <2 seconds and prevents systematic mis-routing.

## Confidence

High. The three paths map cleanly to three distinct complexity tiers observed in the field.
The auto-detect heuristic is intentionally conservative (it recommends, not decides). The
standard path is fully backward-compatible when `chain_path=null` or `chain_path=standard`.
