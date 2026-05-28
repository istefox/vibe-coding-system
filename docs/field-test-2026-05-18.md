# Field test 2026-05-18 — pricing-markup-cli

Field validation of skill/agent trigger phrases and `description` fields in the deployed
vibe coding system. Runbook: `docs/superpowers/plans/2026-05-18-pilot-field-test.md`.
Spec: `docs/superpowers/specs/2026-05-18-pilot-field-test-design.md`.

Status: **IN PROGRESS** — started 2026-05-18.

## Trigger table (filled in progressively from user observations)

| Skill/Agent | Expected trigger | Actual trigger | Auto/Manual OK | Outcome | Notes/mis-fires |
|---|---|---|---|---|---|
| interview-driver | manual only (/), produces SPEC.md | activated only on explicit `/interview-driver`; produced SPEC.md | OK (manual, consistent with disable-model-invocation) | ✅ excellent | High-quality questions: surfaced real, non-obvious domain conflicts (markup vs margin; charm rounding vs guaranteed margin; VAT scope; decimal separator; invalid thresholds). Flagged a residual assumption (`--ending`) with declared confidence. Offered "direct TDD" as an option that would bypass the architect (not a mis-fire, scope choice). |
| architect | @agent, ADR, no prod code | ADR-001-pricing-core.md created, Status Accepted, correct structure; flagged SPEC risks/inconsistencies and HITL gate; compliant with SPEC (no half-up/markup regression) | OK (no productive code) | ✅ good | Also wrote `docs/agent-notes/architect.md` (by-design from its system prompt = memory-intent), despite the ad-hoc prompt saying "only the ADR" → prioritized system prompt. NOT a mis-fire, but unexpected for the user → clarity tweak candidate. sequential-thinking MCP: not reported (to confirm). Excellent: flagged the §6/§5.2 inconsistency on built-in defaults (correct architect behavior: surfacing risks). |
| claude-md-generator | manual, graceful degradation outside template | generic CLI Python CLAUDE.md, 68 lines, inherits global without duplicating, uses ADR in place of missing ARCH.md | OK (manual) | ✅ excellent | Excellent out-of-template degradation (no forced React/iOS template); graceful handling of missing ARCH.md via ADR; lean Anthropic-compliant. Positive tweak candidate: codify in the description/body "if none of the 3 templates match, generate a lean generic CLAUDE.md" — currently correct emergent behavior, better to make it intentional-by-spec. |
| coder | @agent, Decimal, no commit | _to observe_ | | | |
| rule python.md | loaded on *.py | _to observe_ | n/a | | |
| hook auto-format | reformats after .py edit | _to observe_ | n/a | | |
| hook protect-files | blocks protected files if touched | _to observe_ | n/a | | |
| tester | @agent, pytest edge, no prod code | _to observe_ | | | |
| debugger | @agent, true root cause, minimum fix | _to observe_ | | | |
| reviewer | @agent, severity, read-only | _to observe_ | | | |
| auto mode | no false block on legitimate action | _to observe_ | n/a | | |

## Mis-fires / no-fires observed

- T1 interview-driver: **no mis-fire**. Correct manual trigger, high quality.
- Minor note: `interview-driver` offers among its next-steps a "direct TDD" path that would skip the `architect` agent. Not a defect, but for someone who wants the full concept→code flow it might induce skipping the ADR.
- T2 architect: no functional mis-fire. Tension "ad-hoc prompt vs system prompt": the invocation said "only the ADR" but the agent (correctly) also wrote `docs/agent-notes/architect.md` as per its system prompt. Tweak candidate: in the architect system prompt clarify that writing agent-notes is a *memory/meta* action distinct from "design output", so it does not surprise users who constrain the ad-hoc output.
- T2: the pilot session spontaneously proposes its own flow (writing-plans / Plan agent / TDD on feature branch) different from the field-test runbook (next expected step = `/claude-md-generator`). Observation: the pilot orchestrator tends to re-plan rather than follow the concept→code sequence of the blueprint.
- T3 (workflow, not skill): decisions made in conversation (default `ending=0.99` / `margin` mandatory) do NOT automatically flow back into SPEC/ADR/CLAUDE.md → the generated CLAUDE.md still reports "empty defaults / open decision". Real risk: the `coder` would read the docs and implement `ending` as mandatory (wrong vs decision). Mitigation adopted: pass the decision explicitly in the `coder` prompt (Task 4). Tweak/process candidate: a "sync decision → SPEC/ADR" step before implementation, or have decision skills update the docs.

## Proposed tweaks (description/prompt) — to apply in a separate cycle

### PRIORITY — friction "plan mode vs agent delegation" (observed 3× at T1/T2/T4)
The orchestrator re-plans instead of delegating to `@coder`, because it follows
the global rule `~/.claude/CLAUDE.md` "plan mode required for >1 file".
Correct-by-design but creates friction with the architect→coder flow. Proposed tweaks
(choose one or combine):
1. In `~/.claude/CLAUDE.md` (Workflow invariants): add that **an Accepted ADR
   with architecture decomposition/mapping satisfies the plan mode requirement**
   → the orchestrator can delegate to `coder` without re-planning.
2. In the `description`/system prompt of the `coder` agent: make explicit that the
   coder executes the plan in the ADR (the ADR IS the plan for small/medium features).
3. In the `description` of the `architect` agent: clarify that its output
   (ADR + 3-8 steps) is the deliverable that fulfills plan-mode, so the orchestrator
   does not also invoke `writing-plans`.

_(other tweaks to be filled in at the end of the test)_
