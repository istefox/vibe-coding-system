---
name: design-brainstorm
description: This skill should be used when requirements are known (SPEC exists or just
  written) and design APPROACHES and NEW APPLICATION IDEAS must be explored with the user
  BEFORE the architecture is fixed. Uses structured ideation techniques (first-principles,
  cross-domain analogy, inversion/pre-mortem, forced constraints, assumption-busting,
  genuinely-different alternatives, adjacent ideas, prior-art) via AskUserQuestion, one
  technique at a time. Produces a structured BRAINSTORM.md brief (2-4 alternatives with
  trade-offs). Does NOT extract requirements (that is interview-driver), does NOT write
  SPEC/plan, does NOT invoke writing-plans. Invokable from the concept-to-code chain
  (brainstorm-gate 1b) and standalone. Triggers include "let's explore approaches",
  "design brainstorm", "/skill design-brainstorm".
---

# `design-brainstorm` — Structured Ideation Skill

Explores — in structured dialogue with the user, with explicit ideation techniques — the
**application methodology** ("how" to solve the problem) and **new application ideas**
("what new things" are possible), BEFORE the architecture is fixed. Returns a
`BRAINSTORM.md` brief with 2-4 alternatives and trade-offs.

---

## 1. When to invoke

**Invoke this skill when:**
- Requirements are known (SPEC.md exists or was just written) and you want to explore
  alternative approaches BEFORE the architect fixes an ADR.
- The `concept-to-code` orchestrator reaches brainstorm-gate 1b and the user selects `[y]`.
- The user explicitly asks "let's explore approaches" or "design brainstorm" for a specific feature.

**Do NOT invoke for:**
- Requirements gathering (that is `interview-driver`).
- Writing SPEC, ADR, plan (that is the `concept-to-code` chain or the architect directly).
- Terminal brainstorming that produces spec+plan (that is `superpowers:brainstorming`).

---

## 2. Positioning relative to existing skills

| Skill | Answers | Output | Role |
|---|---|---|---|
| `interview-driver` | **What** — which requirements | `SPEC.md` (requirements, scope, DoD) | chain leaf, Step 1 |
| **`design-brainstorm`** | **How + What-new** — approaches, new ideas | `BRAINSTORM.md` (alternatives + trade-offs) | chain leaf, gate 1b |
| `architect` (agent) | **Decision** — which approach to adopt | ADR + plan | Step 2 |
| `superpowers:brainstorming` | spec + complete plan | writes spec, invokes writing-plans | **terminal state** |

**vs `interview-driver`:** the interview captures *what* the system must do (requirements,
scope, edge cases, DoD). `design-brainstorm` assumes requirements are already known and
explores *how* to implement them and *what new things* are enabled.

**vs `superpowers:brainstorming`:** that skill is designed as a *terminal* state (writes
spec and invokes `writing-plans`). Inside the concept-to-code chain this would conflict.
`design-brainstorm` is deliberately **non-terminal**: it does not write spec, does not
invoke plan, it only returns a structured brief to the orchestrator.

**vs `architect` (agent):** the architect *decides and formalizes* (chooses an approach,
writes the ADR). `design-brainstorm` *diverges and explores* (generates alternatives, does
not choose). The brainstorm feeds the architect with a discussed range of options.

---

## 3. The eight ideation techniques (methodological catalogue)

The skill **does not apply all techniques in every session**: it selects 3-4 based on the
nature of the problem (see §4 Routing). The three **core ★** techniques are always
considered first.

### 3.1 ★ First-principles decomposition

**Purpose:** break the problem down to its irreducible elements and reconstruct the solution
without inheriting assumptions about "how it's usually done". Fundamental anti-anchoring technique.

**When:** always first for problems where an "obvious/default solution" exists.

**Procedure:**
1. Reframe the problem as a purpose question: "what is the irreducible outcome that is actually needed?"
2. List the 3-5 facts/constraints that are *physically or logically true* (not conventions).
3. Reconstruct a solution starting only from those facts.

**Question-template (`AskUserQuestion`):**
```
Let's strip it down. What is the irreducible outcome of this problem?
  [A] <data-oriented reframe>
  [B] <user-action-oriented reframe>
  [C] <business-constraint-oriented reframe>
  [D] Other (write it)
```

**Brief output:** the "Reframed problem" section and the list of assumptions.

---

### 3.2 Cross-domain analogies

**Purpose:** import proven patterns from distant domains to break functional fixedness.
"How would a completely different domain X solve this flow?"

**When:** when the problem is a flow/process (orchestration, state, queues, concurrency, trust).

**Reference domains to propose (choose 2-3 relevant ones):**
- **Video games:** game loop, state machine, optimism/rollback, event-driven systems.
- **Banking / finance:** append-only ledger, reconciliation, idempotency, audit trail.
- **Biological systems:** redundancy, graceful degradation, self-healing, swarms.
- **Logistics / postal:** routing, priority queues, tracking, dead-letter.
- **Publishing / editorial:** draft/review/publish, embargo, versioning.

**Question-template (`AskUserQuestion`):**
```
How would a different domain handle this flow?
  [A] Like a video game (game loop / optimistic state)
  [B] Like a bank (append-only ledger / idempotency)
  [C] Like a biological system (graceful degradation / redundancy)
  [D] Like logistics (routing / dead-letter queue)
```

**Brief output:** one or more of the "Approach alternatives" often originate here.

---

### 3.3 ★ Inversion (pre-mortem)

**Purpose:** instead of asking "how do we make it work?", ask "how would we guarantee TOTAL
FAILURE?" — then invert to obtain real risks and hidden non-functional requirements.

**When:** always before closing, as a safety net; especially with sensitive data, external
integrations, or destructive operations.

**Procedure:**
1. "List 3 sure ways to make this feature fail miserably in production."
2. Invert each → becomes a risk to mitigate and often an implicit requirement.

**Question-template (`AskUserQuestion`):**
```
Pre-mortem. It's six months after launch and the feature is a disaster. What went wrong?
  [A] It turned out too slow / not scalable under real load
  [B] An edge case corrupted data / lost user work
  [C] Nobody used it: it solved the wrong problem
  [D] It became impossible to maintain / extend
```

**Brief output:** "negative" trade-offs of the alternatives and a risks section.

---

### 3.4 Forced constraints (constraint injection)

**Purpose:** an extreme artificial constraint forces solutions that "comfortable" thinking
would never generate.

**When:** when the first alternative is "obvious and heavy" and a leaner path is suspected to exist.

**Question-template (`AskUserQuestion`):**
```
Let's inject an extreme constraint to find the lean version:
  [A] Half the development time — what stays?
  [B] No database — where does state live?
  [C] Must run offline — what changes?
  [D] Skip this technique
```

**Brief output:** often generates the "minimal/lean" alternative.

---

### 3.5 Assumption-busting

**Purpose:** make implicit assumptions explicit and challenge them one by one. Invisible
assumptions are the strongest and least justified constraint.

**When:** right after first-principles; produces the "Challenged assumptions" section of the brief.

**Procedure:**
1. The skill PROPOSES 3-5 implicit assumptions detected from the SPEC/context.
2. For each: "is this assumption a real constraint or just a habit?"

**Question-template (`AskUserQuestion`, one per assumption):**
```
Detected assumption: "<assumption>". Is it a real constraint?
  [A] Real and immutable (it is a genuine requirement)
  [B] Likely but unverified (needs to be confirmed with data)
  [C] Habit — we can challenge it
```

**Brief output:** "Challenged assumptions" section with outcome for each.

---

### 3.6 Genuinely different alternatives

**Purpose:** generate **2-4 genuinely different approaches** — not variants of the same thing.

**Quality rule:** two alternatives are "genuinely different" only if they differ in at least
one of: data model, concurrency/time model, responsibility boundary, deployment model. If they
share all four, they should be merged.

**Procedure:**
1. Synthesize what emerged from analogies + constraints + first-principles into 2-4 candidates.
2. For each: name, 2-3 line description, axis of difference.
3. Ask the user to weigh the trade-offs (the skill does not decide).

**Question-template (`AskUserQuestion`, for each alternative):**
```
Alternative <N> — "<name>". Which trade-off weighs most on you?
  [A] High initial complexity, but scales better
  [B] Simple now, but technical debt if it grows
  [C] External dependency (buy) vs control (build)
  [D] Other (write it)
```

**Brief output:** "Approach alternatives" section — the most important one.

---

### 3.7 Adjacent ideas (adjacent possible)

**Purpose:** identify use cases/features naturally adjacent to the problem — to make them
explicit or flag scope creep to exclude.

**When:** near the end, after the alternatives; brief.

**Question-template (`AskUserQuestion`):**
```
Solving this naturally opens adjacent doors. Which one do you want to note?
  [A] <adjacent feature 1 detected from context>
  [B] <adjacent feature 2>
  [C] None for now — note them only as "out of scope, future"
```

**Brief output:** "Adjacent ideas emerged" section (with in-scope / future / explicitly-excluded tagging).

---

### 3.8 Prior-art / state of the art

**Purpose:** while cross-domain analogies (3.2) import patterns from *distant* domains,
prior-art looks at the *near* domain: what do competing products/solutions that face the same
problem actually do? Used to generate **new application ideas** for differentiation and to
avoid reinventing something that already exists poorly.

**When:** when the feature has known equivalents in the market or domain, or when the user
wants to position relative to existing solutions. Support technique, not core.

**Caveat:** `design-brainstorm` is dialogic — **it does not do web research**. Prior-art
is based on what the user already knows. If a documented competitive analysis is needed, the
skill flags this and recommends delegating to the `researcher` agent — it does NOT attempt
searches it cannot do.

**Procedure:**
1. Ask the user which existing solutions/products they know for this problem.
2. For each: what it does well, what it does poorly, what is missing.
3. Extract "empty spaces" (what nobody does well = differentiation opportunity).

**Question-template (`AskUserQuestion`):**
```
Do you know existing solutions/products that address this problem?
  [A] Yes, and I know what they do well/poorly (describe them)
  [B] Yes, but I want a deeper competitive analysis → delegate to researcher
  [C] No / not relevant — skip this technique
```

**Brief output:** "Prior-art and differentiation spaces" section — what exists, what is
missing, opportunity to do it differently/better. Often feeds "Approach alternatives" (3.6)
and "Adjacent ideas" (3.7).

---

## 4. Dialogue flow (technique orchestration)

### 4.1 Routing — which 3-4 techniques to select

The skill does NOT apply all eight. It chooses based on the nature of the problem:

- **Always included (core ★):** first-principles (3.1) → assumption-busting (3.5) →
  inversion/pre-mortem (3.3) as the final safety net.
- **Add cross-domain analogies (3.2)** if the problem is a *flow/process*
  (orchestration, state, concurrency, trust, queues).
- **Add forced constraints (3.4)** if the first solution that emerged is "obvious and heavy" or
  there are declared cost/time constraints.
- **Add prior-art (3.8)** if the feature has known equivalents in the market/domain or
  the user wants to differentiate from existing solutions.
- **Adjacent ideas (3.7)** always as the second-to-last step, brief.
- **Alternatives (3.6)** always as the mandatory synthesis step before the brief.

Typical sequence (5-6 dialogue steps): first-principles → assumption-busting →
[analogies | constraints | prior-art, based on routing] → alternatives (synthesis) →
inversion (pre-mortem on alternatives) → adjacent ideas → brief writing.

### 4.2 Dialogue conduct rules

- **One question at a time** with `AskUserQuestion`, max 4 options, always with an
  "Other/write it" or "skip" option where it makes sense.
- **Synthesize after each answer** in 1-2 lines before the next question.
- **Provide a motivated recommendation** per the global convention (first in list,
  " (Recommended)" label suffix): the skill analyzes trade-offs and marks the option
  it judges best given the context. The preference choice stays with the user — the
  recommendation is preliminary, not binding.
- **Implicit time-box:** if after ~6-7 exchanges the range of options is clear, converge
  to the brief. Do not drag it out.
- **No requirements phase:** if new requirements emerge (not "how" but "what"), annotate
  them in the brief as "to report back to SPEC" and do NOT derail the interview.

### 4.3 Dialogue edge cases

- **The user cannot answer a technique:** offer the "skip" option and move to the next;
  annotate the gap in the brief.
- **The user already has a strong idea:** do not immediately go along with it; use
  inversion + assumption-busting to stress-test it, then generate at least 1 comparison
  alternative. A single alternative in the brief is a quality failure.
- **Trivial problem:** flag it honestly ("this problem has a clear canonical solution, the
  brainstorm adds little — do you want to proceed anyway or go straight to the architect?")
  and let the user decide.

---

## 5. Output contract — `BRAINSTORM.md`

### 5.1 Position and responsibility

`<project-root>/BRAINSTORM.md`. The skill writes **only this file**. It does NOT touch the
manifest (the `concept-to-code` orchestrator updates it, writing `artifacts.brainstorm`).
It does NOT write SPEC, ADR, plan.

### 5.2 Mandatory structure

```markdown
# BRAINSTORM — <topic>

**Date:** YYYY-MM-DD
**Requirements source:** <path to SPEC.md, or "requirements discussed in session">
**Techniques applied:** <list of the 3-4 techniques used>

## Reframed problem (first-principles)
<2-4 lines: the irreducible need, not the solution>

## Challenged assumptions
- <assumption 1> — outcome: [retained | to verify | dropped] — <why>
- <assumption 2> — ...
(3-5 entries)

## Approach alternatives
### Alternative A — <name>
- **Idea:** <2-3 lines>
- **Axis of difference:** <data | concurrency | boundaries | deployment>
- **Pros:** <bullet>
- **Cons:** <bullet>
- **Indicative cost/time:** <low | medium | high>

### Alternative B — <name>
...
(2-4 alternatives, genuinely different per rule §3.6)

## Risks emerged (inversion / pre-mortem)
- <risk 1> → possible mitigation: <...>

## Adjacent ideas emerged
- <idea> — [in-scope now | future | explicitly excluded]

## Preliminary recommendation
<2-4 lines: which alternative seems most promising and why — DECLARED as
preliminary, to be validated by the architect. NOT a binding decision.>

## Notes for the architect
<what the architect should investigate/decide; any new requirements to
report back to SPEC>
```

### 5.3 Brief quality invariants

- Contains at least 2 alternatives (`### Alternative` recurs >= 2 times).
- Contains the "Challenged assumptions" section, non-empty.
- Contains "Preliminary recommendation" with "preliminary" label.
- Does NOT contain implementation code blocks.
- Is NOT a SPEC or plan: if needed, redirects to the chain.

### 5.4 How the brief feeds the architect (Step 2)

The `concept-to-code` orchestrator includes `BRAINSTORM.md` in the architect dispatch as
additional context (alongside SPEC.md). The architect reads the alternatives and the
preliminary recommendation, and in the ADR documents which one was chosen and why (the
brainstorm alternatives become the ADR alternatives).

---

## 6. Coexistence

- Does NOT modify `interview-driver` (distinct role: requirements vs approaches).
- Does NOT modify `claude-md-generator`, `review-triage-fix`, `refactor-snapshot`, `vibe-status`.
- Does NOT patch agents (`architect.md` etc.): the brief is passed as context to the
  dispatch, it does not patch the agent.
- Does NOT invoke `superpowers:brainstorming` (conflict: terminal state, writes spec/plan).
- Is invoked by the `concept-to-code` chain at gate 1b; updates ONLY `BRAINSTORM.md`,
  the orchestrator updates `artifacts.brainstorm`.
- Skill `using-superpowers`: explicitly out of scope for this task.
- Sub-agent constraint: this skill instructs the **orchestrator** (main CLI). Do not spawn
  sub-agents inside this skill.

## 7. Chain invocation — return contract

When the invocation contains `Chain context: concept-to-code (gate 1b)`:
- Execute the full brainstorm (sections 3–5), write `BRAINSTORM.md`.
- **Do NOT produce any closing response, summary, or handoff message** after writing the file.
  The line "The architect receives this brief to fix the ADR" (or equivalent) must NOT be emitted.
- End execution silently: the concept-to-code orchestrator continues immediately and handles
  manifest update, state transition, and architect dispatch.
- Emitting a closing message breaks the chain (ends the turn; orchestrator never resumes).
