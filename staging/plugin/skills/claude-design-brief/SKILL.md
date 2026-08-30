---
name: claude-design-brief
description: This skill should be used when the concept-to-code chain reaches Gate 1d
  (optional, after Gate 1b/1c, gate 1d only) and the user chooses to generate a Claude
  Design prompt. Reads SPEC.md (required) plus BRAINSTORM.md and UX-BLUEPRINT.md when
  present, and composes a single copy-paste-ready prompt into DESIGN-PROMPT.md for
  claude.ai/design (a human-mediated, login-walled web product with no public API).
  Does NOT call any API, does NOT fetch claude.ai, does NOT write DESIGN.md (that is
  the orchestrator's job, once a human pastes back a shared URL). Invokable from the
  concept-to-code chain (gate 1d only) and standalone. Triggers include "claude design
  brief", "generate a claude design prompt", "/skill claude-design-brief".
---

# `claude-design-brief` — Claude Design Prompt Skill

Composes a single, copy-paste-ready prompt for **Claude Design** (claude.ai/design) from
whatever design context the chain has already produced — SPEC.md's UI flows,
`BRAINSTORM.md`'s adopted approach, `UX-BLUEPRINT.md`'s platform constraints — and writes
it to `DESIGN-PROMPT.md`. It does not talk to Claude Design: that product is human-mediated
and login-walled, with no public API, and this skill produces text only.

---

## 1. When to invoke

**Invoke this skill when:**
- The `concept-to-code` orchestrator reaches Gate 1d and the user selects "Yes, generate a
  Claude Design prompt".
- The user explicitly asks "claude design brief" or "generate a claude design prompt" for a
  specific feature that already has a SPEC.

**Do NOT invoke for:**
- Requirements gathering (`interview-driver`) or approach exploration (`design-brainstorm`)
  — this skill assumes both are already settled, or absent, and works with what exists.
- Talking to claude.ai/design directly — there is no public API; a human does that step
  by hand, outside this repo.
- Writing `DESIGN.md` — that is the orchestrator's job, once the human pastes back a shared
  URL at Gate 1d-B, never this skill's.

---

## 2. Positioning relative to existing skills

| Skill | Reads | Writes | Role |
|---|---|---|---|
| `interview-driver` | user dialogue | `SPEC.md` | chain leaf, Step 1 |
| `design-brainstorm` | `SPEC.md` | `BRAINSTORM.md` | chain leaf, gate 1b |
| `macos-ux` | `SPEC.md`, `BRAINSTORM.md` | `UX-BLUEPRINT.md` | chain leaf, gate 1c |
| **`claude-design-brief`** | `SPEC.md`, `BRAINSTORM.md`?, `UX-BLUEPRINT.md`? | `DESIGN-PROMPT.md` | chain leaf, gate 1d |
| *(human, off-chain)* | `DESIGN-PROMPT.md` | shared Claude Design URL | outside this repo |
| `concept-to-code` orchestrator | the pasted URL | `DESIGN.md` | gate 1d-B |

**vs `design-brainstorm` / `macos-ux`:** those skills interview the user and produce a
structured brief through dialogue. `claude-design-brief` does not interview: by the time
Gate 1d fires, SPEC/BRAINSTORM/UX-BLUEPRINT already hold the answers it needs. It reads,
composes, writes — no `AskUserQuestion` loop, unless SPEC's UI-flows section is missing
entirely, in which case it asks the one blocking question (§3.1).

**vs the orchestrator:** this skill never writes `DESIGN.md` and never touches the manifest.
It produces the prompt; a human takes it to claude.ai/design and brings back a shared URL;
the orchestrator (not this skill) records that URL into `DESIGN.md` and `artifacts.design`.

---

## 3. Procedure

### 3.1 Gather inputs

1. Read `SPEC.md` at the project root (required). Extract:
   - The product one-liner (from the SPEC's opening description).
   - The target platform(s).
   - The UI-flows / screen inventory section, one line per screen/flow.
   - The requirement ids (`R-NN`) as **labels only** — cite them as identifiers next to the
     flow they belong to; never re-derive or re-validate them against anything outside this
     SPEC (rule 18: requirement ids are feature-scoped, matching them against a repo-wide
     file set would be a category error).
   - Explicit non-goals / out-of-scope notes, if the SPEC states them.

   If `SPEC.md` has no UI-flows section at all, ask the user once: "SPEC.md doesn't have a
   UI-flows section — list the screens/flows to design (one line each), or point me at where
   they live." Do not proceed on a guess.

2. If `BRAINSTORM.md` exists at the project root, read it and extract the **adopted
   approach** — the alternative the SPEC or the user actually chose, not the full list of
   alternatives considered.

3. If `UX-BLUEPRINT.md` exists at the project root, read it and extract platform constraints
   **verbatim** — window inventory, navigation structure, Settings layout: quote, do not
   paraphrase. A paraphrased HIG skeleton is a different skeleton.

### 3.2 Compose the prompt

Assemble the single fenced block described in §4 from the gathered inputs. Do not add
content the inputs don't support — an omitted input (e.g. no `BRAINSTORM.md` found) means
an omitted subsection, never an invented one.

### 3.3 Write and stop

Write `DESIGN-PROMPT.md` (§4) and return control per §5/§6. This skill does not open a
browser, does not call any API, and does not wait for the human to come back with a URL —
that is Gate 1d-B's job, after this skill has already ended silently.

---

## 4. Output contract — `DESIGN-PROMPT.md`

### 4.1 Position and responsibility

`<project-root>/DESIGN-PROMPT.md`. The skill writes **only this file**. It does NOT touch
the manifest (the `concept-to-code` orchestrator updates it, writing
`artifacts.design_prompt`). It does NOT write `DESIGN.md`, SPEC, ADR, or plan.

### 4.2 Mandatory structure

`````markdown
# Claude Design Prompt — <topic>

Go to claude.ai/design (Pro/Max/Team/Enterprise plan required — no free-tier access, no
public API). Paste the fenced block below whole. Ask for N screens and share the result
with link access; bring the shared URL back to this chain.

```
<product one-liner> — <platform>

Screens / flows:
- <screen 1> (R-NN)
- <screen 2> (R-NN, R-NN)
...

Adopted approach: <from BRAINSTORM.md, verbatim summary — omitted if BRAINSTORM.md is absent>

Platform constraints (verbatim from UX-BLUEPRINT.md — omitted if UX-BLUEPRINT.md is absent):
<window inventory / navigation / Settings excerpt>

Non-goals:
- <non-goal 1>
...

Produce <N> screens and share with link access.
```
`````

### 4.3 Quality invariants

- The fenced block is a single block the human can copy whole — no instructions inside the
  fence itself.
- Every screen/flow line cites its SPEC requirement ids as labels only (§3.1).
- Platform constraints, when present, are quoted verbatim from `UX-BLUEPRINT.md`, never
  paraphrased.
- Outside the fence: where to go (claude.ai/design), the plan-tier requirement, and exactly
  what to bring back (a shared URL with link access).

---

## 5. Coexistence

- Does NOT modify `interview-driver`, `design-brainstorm`, `macos-ux`, `ui-layout-audit`,
  `swiftui-pro`. Those are retained for requirements, approach, platform structure, and
  post-implementation audit/refinement respectively — Claude Design produces the initial
  mockup, nothing is replaced.
- Does NOT talk to claude.ai/design: no public API exists. This skill only prepares the
  text a human pastes there by hand.
- Does NOT write `DESIGN.md`: that is the `concept-to-code` orchestrator's job at Gate 1d-B,
  once the human pastes back a shared URL.
- Is invoked by the `concept-to-code` chain at gate 1d; updates ONLY `DESIGN-PROMPT.md`, the
  orchestrator updates `artifacts.design_prompt`.
- Sub-agent constraint: this skill instructs the **orchestrator** (main CLI). Do not spawn
  sub-agents inside this skill.

## 6. Chain invocation — return contract

When the invocation contains `Chain context: concept-to-code (gate 1d)`:
- Execute §3 (gather inputs, compose, write `DESIGN-PROMPT.md`).
- **Do NOT produce any closing response, summary, or handoff message** after writing the
  file. The line "Take this to claude.ai/design" (or equivalent) must NOT be emitted here —
  Gate 1d itself emits the path and the instructions right after this skill returns.
- End execution silently: the concept-to-code orchestrator continues immediately with Gate
  1d-B (the URL-paste pause) and handles the manifest update.
- Emitting a closing message breaks the chain (ends the turn; orchestrator never resumes).
  End silently.
