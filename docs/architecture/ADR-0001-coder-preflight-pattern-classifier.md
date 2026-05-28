# ADR-0001 — Coder pre-flight pattern classifier

**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-coder-preflight-pattern-classifier.md; harness PASS=43)
**Authors:** Adriano (architect agent) per Stefano Ferri
**Supersedes:** none
**Superseded by:** none
**Related:**
- `docs/superpowers/specs/2026-05-20-coder-preflight-pattern-classifier-design.md`
- `docs/superpowers/plans/2026-05-20-coder-preflight-pattern-classifier.md`
- `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2 Add+Remove rule — complementary safety net)
- `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/feedback_micropiano-refactor-cleanup.md` (RESOLVED 2026-05-20)

---

## 1. Context

The vibe-coding multi-agent system (sec. 2-3 of `docs/vibe-coding-system.md`) has a `coder`
sub-agent (Sonnet, `~/.claude/agents/coder.md`) that is plan-driven: it executes exactly what
it receives. The `review-triage-fix` skill v1.2 (2026-05-20) just introduced the **Add+Remove**
rule in Step 2 of triage, following the observation during cycle 2 of `pricing-markup-cli`: the
`coder` had received a micro-plan formulated as "add autouse fixture" without explicitly stating
"remove the pre-existing fixture that does the same work", and had acted conservatively leaving
the duplication in place — a MAJOR finding at re-review.

The v1.2 rule resolves **the specific substitution case** but the following issues remain:

1. **Reactive.** It acts during triage *after* the duplicated code has already been written.
   The coder has already passed, the live filesystem has 2 autouse fixtures.
2. **Single-pattern.** It covers only SUBSTITUTION. No equivalent lever for ADD (which might
   require "remember to write the test"), for REMOVE (which might require "verify orphan
   callers"), for MODIFY (which requires nothing specific but is useful to classify for
   clarity of intent).
3. **Not scalable.** Adding other analogous invariants in v1.3/v1.4 means accumulating
   prosaic rules on SKILL.md Step 2 without explicit taxonomy — entropy.

**Architectural problem:** the `coder` agent has no explicit contract that forces it to
**declare the intent of the imminent edit** before executing the tool call. The "micro-plan
= 2-3 lines" discipline covers the *what*; the *structural type of the operation* is missing.

**Direction:** introduce a **pre-flight pattern classifier** that the `coder` must emit
before every Edit/Write tool call. 4 exhaustive and mutually exclusive categories: `ADD`,
`REMOVE`, `REPLACE`, `MODIFY`. For `REPLACE` the declaration of the `Add:`/`Remove:` pair is
mandatory, promoting the v1.2 rule from a post-hoc safety net to a pre-edit contract.

### Inherited constraints

- **Anchor preservation harness `review-triage-fix`:** the harness in
  `~/.claude/skills/review-triage-fix/tests/run-tests.sh` must remain PASS=41/41 minimum
  (post-feature target: PASS=42/42 with 1 anchor added to `coder.md` structural sweep —
  see Decision §3.3).
- **Bash 3.2 compat** for any script live in `~/.claude/`.
- **No backwards-compat shim:** changes to the `coder` agent replace cleanly.
- **Coexistence with v1.2:** the Add+Remove rule in `review-triage-fix` Step 2 remains — it
  is the safety net for when the pattern classifier is declared incorrectly or absent
  (failure mode Q6).
- **Sub-agent identity unchanged:** `coder.md` remains Sonnet, tools unchanged
  (`Read, Edit, Write, Glob, Grep, Bash`), green color, plan-driven.

### Explicit assumptions (not empirically verified)

- The `coder` LLM (Sonnet) will follow a structured output contract of the type "before every Edit
  tool call, emit one line `PATTERN: <CATEGORY> | ...`" with the same fidelity with which it
  follows today the micro-plan discipline. Plausible (the v1.0-v1.2 micro-plan 2-3 line
  discipline works), but not verified for this exact output form.
- The granularity "1 pattern per Step of the plan" is the right trade-off (see Decision §3.3).
  Validatable only with an operational pilot.
- The reviewer agent can learn to perform the coherence check "declared pattern vs actual diff"
  by reading the coder transcript + git diff (or pre/post snapshot in non-git).
  Plausible given the current reviewer scan capability (cites `loc=path:line`), but it is a
  new invariant that requires addition to the `reviewer.md` system prompt.

---

## 2. Decision

Introduce the **Coder Pre-flight Pattern Classifier** as an output contract of the `coder`
agent, enforced via system prompt (`~/.claude/agents/coder.md`), with post-hoc validation in
the `reviewer` agent and unchanged v1.2 fallback.

### 2.1 The 4 categories

| Pattern | Meaning | Required invariant |
|---|---|---|
| `ADD` | New code, no prior pattern to remove (new test, new function, new file, missing validation, edge-case test). | No additional structure — `ADD: <path:line> <one-line-intent>`. |
| `REMOVE` | Pure deletion (dead code, unused file). | Declare `Callers checked: <list or "none">` to avoid orphans. |
| `REPLACE` | Substitution of existing pattern with new pattern (move import to top-level, extract magic number, consolidate duplicate fixtures, rename helper). | **`Add:` + `Remove:` pair mandatory.** Form: `REPLACE \| Add: <path:line> <new> \| Remove: <path:line> <old>`. |
| `MODIFY` | In-place edit without structural change (typo fix, rename var, internal refactor of a single function that remains logically the same, comment update). | `MODIFY: <path:line> <one-line-intent>`. |

The 4 categories are exhaustive and mutually exclusive by construction. Edge cases covered in
Decision §2.5.

### 2.2 Output form (Q1)

**Self-disciplined textual output of the coder, one line immediately BEFORE the Edit/Write tool
call.** Strict format:

```
PATTERN: <CATEGORY> | <category-specific payload>
```

Concrete examples:

```
PATTERN: ADD | tests/test_pricing.py:42 add failing test for negative markup
PATTERN: REPLACE | Add: tests/conftest.py:15 new _isolate_user_config autouse | Remove: tests/test_cli.py:8 old no_user_config autouse
PATTERN: MODIFY | src/pricing/markup.py:88 rename `mrg` to `margin` for clarity
PATTERN: REMOVE | src/legacy_util.py (full file) | Callers checked: grep returned 0 hits across src/ and tests/
```

One line = one tool call. If a Step in the plan has multiple independent Edits, multiple
`PATTERN:` headers, one for each Edit, each followed by its tool call. No JSON, no state files
— the classifier lives in the agent transcript and is directly inspectable by the orchestrator
and reviewer.

### 2.3 Enforcement (Q2)

**Three-layer defense, each individually optional, collectively robust:**

1. **`coder.md` agent system prompt (primary, mandatory in v1.0):** the classifier
   discipline is specified as a hard contract: "**before every Edit or Write tool call you
   MUST emit a single-line `PATTERN: ...` header**". Same status as the micro-plan
   discipline v1.0-v1.2.
2. **Reviewer post-hoc coherence check (secondary):** `reviewer.md` gains 1 invariant:
   "if the agent that generated the diff is `coder`, verify that the transcript contains
   `PATTERN:` headers coherent with the diff hunks; flag MINOR `pattern-drift` if the
   declared pattern does not match the actual diff (e.g. declared `ADD` but diff contains
   non-trivial removals)". Non-blocking, it is an informative MINOR.
3. **review-triage-fix v1.2 Add+Remove rule (tertiary, existing, unchanged):** if the pattern
   classifier fails (declared incorrectly or omitted) and the duplication-by-omission bug from
   cycle 2 returns, the v1.2 net catches it as before. Coexistence explicitly preserved.

**Hook PreToolUse bash as primary enforcement is explicitly rejected** (see Alternatives §3.1.c).

### 2.4 Granularity (Q3 + Q5)

**Granularity = 1 `PATTERN:` declaration per Edit/Write tool call.**

- Not per plan task (too coarse, loses multi-pattern).
- Not per "logical block" (ambiguous, subject to interpretation).
- Per individual tool call (deterministic, inspectable).

**Interaction with TDD plan with 5-7 tasks:** each `- [ ]` Step of the plan is an execution
block that typically contains 1-3 Edits. The dominant pattern is derivable from the Step (red
phase -> usually `ADD`; green phase -> `ADD` or `MODIFY`; sync deliverable -> `MODIFY`), but
the final classification is **run-time, by the coder, for each Edit**, because:

- The implementation reality may deviate from the plan (and in that case pre-plan cold
  classification lies).
- Multiple legitimate patterns in one Step (e.g. green phase requires ADD new function +
  MODIFY existing caller) must each be classified.

The **plan written by the architect MUST NOT pre-declare patterns per step**, because
it would force the coder into compliance that might hide legitimate drift. The architect remains
agnostic; the coder classifies.

### 2.5 Classification edge cases (Q4 expanded + edge case coverage)

- **REPLACE when the new file does not yet exist** (e.g. `Add:` points to newly created
  `tests/conftest.py`): the coder uses the filename + 1-line description of the pattern as
  identifier — `Add: tests/conftest.py (new file) _isolate_user_config autouse fixture`.
- **REPLACE that touches >1 Remove locations** (consolidate 3 duplicate fixtures into 1):
  `Remove:` is a comma-separated list of `path:line` — `Remove: tests/test_a.py:8,
  tests/test_b.py:12, tests/test_c.py:5`.
- **MODIFY that becomes REPLACE mid-stream** (e.g. rename var but coder realizes it is
  simultaneously removing the old name in 5 other files): emits an updated second `PATTERN:`
  before the next tool call. No penalty for re-classification: the transcript is the source of
  truth.
- **Edit to a doc/markdown file** (sync deliverable in plan): the same schema applies.
  `MODIFY` usually (sync ref number); `ADD` for new sections; `REPLACE` rare but plausible
  (e.g. policy change in CLAUDE.md project).
- **Bash tool call is NOT classified.** Only `Edit` and `Write` tool calls require
  a `PATTERN:` header. `Read`, `Grep`, `Glob`, `Bash` are read-only or execution-only and
  are excluded from classification (aligned with the fact that the discipline is about the
  intent of *mutation*).

### 2.6 Failure mode (Q6)

What happens if the coder declares `ADD` but the actual diff contains non-trivial removals?

1. **Reviewer post-hoc invariant (§2.3 layer 2)** flags it as MINOR `pattern-drift`.
   Routed to `coder` as a standard micro-plan "re-emit coherent classification; if the
   correct classification is REPLACE, apply Add+Remove rule (v1.2)".
2. **If the drift causes duplication-by-omission** (e.g. declared ADD but it was REPLACE and
   the old pattern remained): v1.2 Add+Remove rule catches it in the next cycle as MAJOR.

No auto-revert. No blocking hook. The philosophy is triple-layer detection with
human escalation (HITL) as the final gate (aligned with `~/.claude/CLAUDE.md` invariant "HITL
gate always before commit, deploy, schema modification").

### 2.7 Precise file changes

- **Modify `~/.claude/agents/coder.md`** — add a "Pre-flight Pattern Classifier" section
  with the 4-category table and output examples, inserted after "Core
  Responsibilities" and before "Process". Substitutive modification (no deprecated shim).
- **Modify `~/.claude/agents/reviewer.md`** — add "pattern-drift check" bullet to the
  "Core Responsibilities" or "Process" section, with MINOR severity and finding category
  `pattern-drift`.
- **Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh`** — add 1 structural
  anchor test that verifies the presence of the literal `Pattern Classifier` in
  `~/.claude/agents/coder.md`. Harness PASS=41 -> PASS=42.

  Architectural note: the `review-triage-fix` harness today is single-target (reads only
  `SKILL.md`). Extending it to read a second file (`coder.md`) is a **minor but explicit
  architectural decision**: the `review-triage-fix` skill has authority over the quality of
  its own stack (including the `coder` it dispatches). Alternatives rejected in §3.3.
- **NO modify `~/.claude/skills/review-triage-fix/SKILL.md`** — the skill remains unchanged.
  The Add+Remove v1.2 rule in Step 2 is coherent by construction with the classifier (the
  classifier makes it pre-flight, but the post-hoc rule remains as safety net).

### 2.8 Language

System prompt of `coder.md` and `reviewer.md` in English (code/contract). Spec, plan and
memory in Italian. Category table and examples in English (they are interface contract). Aligned
with global rule "code and commits in English; text to user in Italian".

---

## 3. Alternatives considered

### 3.1 Where does the declaration live (Q1)

**a) Self-disciplined textual output of the coder (CHOSEN).** Zero infrastructure, readable in
orchestrator transcript, aligned with micro-plan discipline. Risk: LLM drift
(classifier declared incorrectly or omitted); mitigated by reviewer post-hoc layer + v1.2 safety
net.

**b) JSON state file `.claude/.pattern-classifier-current.json`** — *Rejected*. Requires
I/O scaffolding (lock file? cleanup between cycles? pre/post snapshot?), adds complexity to a
problem that is fundamentally declarative discipline. Does not resolve the real risk
(LLM drift): the LLM can write the JSON incorrectly just as it can write the `PATTERN: ...`
line incorrectly. State file adds a failure point (stale state, race with parallel dispatches)
without proportional benefit.

**c) Hook PreToolUse bash intercepts the Edit/Write tool call** — *Rejected*. Three reasons:
(i) Claude Code PreToolUse hooks receive `tool_input` JSON, not the text of the preceding
response — the bash hook cannot "see" the `PATTERN: ...` header without a side-channel state
file (re-introduces 3.1.b); (ii) would violate the bash 3.2 constraint with robust JSON
writing/reading; (iii) a hook that blocks an Edit because the pattern is missing violates the
philosophy "primary enforcement is discipline + reviewer post-hoc, not hard gate at filesystem"
(aligned with the fact that even v1.2 is prose-discipline, not hook-enforcement).

### 3.2 Who enforces (Q2)

**a) Self-discipline via system prompt (CHOSEN, primary layer).** The same mechanism
already works for micro-plan discipline v1.0-v1.2. The plan-driven `coder` follows textual
contracts with high fidelity if the contract is clear and has examples.

**b) Hook PreToolUse bash blocks Edit if pattern is missing** — *Rejected* (see §3.1.c).

**c) Only reviewer post-hoc, without system prompt** — *Rejected*. Shifts all the load to the
reviewer (which already does a lot), and loses the proactive lever: the coder *before* writing
the code benefits cognitively from classifying intent (especially REPLACE -> forced to think
about the pair). Reviewer post-hoc remains as secondary layer, not primary.

**Chosen layer-stack:** primary = system prompt; secondary = reviewer pattern-drift check;
tertiary = v1.2 Add+Remove rule as duplicate-catch safety net.

### 3.3 Granularity (Q3 + Q5)

**a) Per tool call (CHOSEN).** Deterministic, inspectable, follows the "natural rhythm" of
the coder's work. Multiple patterns per Step of the plan = multiple headers, normal.

**b) Per plan task** — *Rejected*. Too coarse: a TDD red+green+sync task
contains 3-5 Edits with potentially different patterns (e.g. red ADD, green ADD+MODIFY, sync
MODIFY). A single pattern per task would force the "dominant pattern" and mask sub-patterns,
losing precisely the value of the classification.

**c) Per logical block (3-5 correlated Edits)** — *Rejected*. "Logical block" is ambiguous,
not testable, not inspectable. It would leave room for interpretation that the classification
should instead close. Design anti-pattern.

### 3.3 (sub-question) Harness extension cross-file (for anchor test on `coder.md`)

**a) Extend `review-triage-fix` harness to assert anchor on `coder.md` (CHOSEN).** The
`review-triage-fix` skill already has authority over the quality of the coder agent it dispatches
(`debugger`, `refactorer`, `coder` are its dispatch targets). The harness adds 1 helper function
`g_file(file, str, label)` (generalization of the existing `g()`) and 1 final assertion.
Cost: ~5 bash lines. Benefit: 1 additional anchor that protects the "Pattern Classifier" section
of coder.md from accidental future removal. PASS=41 -> PASS=42.

**b) Create a separate harness dedicated to `coder.md`** — *Rejected*. Redundant:
would duplicate the same logic `grep -q literal in file`. Would add a new deployment point
in `~/.claude/agents/` or similar, contrary to the "minimal moving parts" principle.

**c) No structural anchor test** — *Rejected*. Without an anchor, an accidental refactor of
coder.md (e.g. consolidating sections, rewriting) could silently lose the classifier
discipline, without alert. Anchor is the standard safety net of the system (same
philosophy as v1.0-v1.2 of review-triage-fix harness).

### 3.4 What REPLACE does (Q4)

**a) Explicit mandatory `Add:` + `Remove:` pair (CHOSEN).** Promotes the v1.2 rule from
post-hoc to pre-flight. Strict format `REPLACE | Add: <loc> | Remove: <loc>`. Forces the coder
to *think* about the removal while thinking about the addition — the cognitive leverage is the
key of the intervention.

**b) Reminder flag "remember Add+Remove" without strict format** — *Rejected*. Reintroduces the
v1.1 failure mode (the coder can "remember" without being explicit and then not act). The v1.2
rule just resolved this; it would be a semantic regression.

**c) Auto-generated checklist from the system** — *Rejected*. Requires infrastructure (see
§3.1.b state file). Does not scale (who populates the checklist? in what language?).

### 3.5 Interaction with TDD plan (Q5)

**a) Run-time per-tool-call (CHOSEN, already motivated in §2.4).** The architect/plan does not
pre-declare patterns; the coder classifies at runtime.

**b) Plan pre-declares the pattern for each Step** — *Rejected*. Would force compliance with a
contract written cold by the architect. The implementation reality can legitimately deviate, and
in that case the coder should be able to re-classify without requesting an amendment to the plan.

### 3.6 Failure mode (Q6)

**a) Reviewer post-hoc invariant + v1.2 safety net (CHOSEN).** Triple-layer
(system-prompt -> reviewer -> v1.2). No hard gate, HITL escalation as last resort.

**b) Hook that diff-checks declared-vs-actual** — *Rejected* (see §3.1.c).

**c) Only v1.2 safety net without reviewer invariant** — *Rejected*. v1.2 catches
duplication-by-omission for substitution, but does NOT catch other pattern-drift (e.g. declared
ADD but diff is non-trivial REMOVE). Reviewer invariant handles the general case.

---

## 4. Consequences

### 4.1 Positive

- **Proactive cognitive leverage.** The coder, forced to classify before writing, thinks better
  about intent. Especially REPLACE -> forces the Add+Remove pair at the *right point*
  (pre-edit), moving v1.2 from safety net to contract.
- **Model scalability.** If in v1.3 we want to add "REMOVE must declare caller-check",
  "ADD must declare paired test", etc., we add rows to the 4-category table without
  rewriting the framework.
- **Transparency for orchestrator + reviewer.** The coder transcript is self-documented:
  scrolling the `PATTERN: ...` lines produces an audit log of intent.
- **Three layers of defense against duplication-by-omission.** v1.2 alone catches only at
  re-review post-fix; classifier pre-flight catches *before* the edit; reviewer pattern-drift
  catches mid-cycle.
- **Anchor preserved.** PASS=41 -> PASS=42 (additive, no regression).
- **Zero new dependencies.** Only system prompt edits + 1 anchor test bash 3.2-clean.

### 4.2 Negative

- **Textual overhead in the coder transcript.** Each Edit/Write is preceded by 1
  `PATTERN: ...` line. For tasks with 10 Edits, +10 lines. Not blocking (cheap tokens), but
  noisy.
- **Risk of LLM drift.** The coder might omit the pattern header under stress
  conditions (full context window, long prompt). Mitigated by reviewer post-hoc, but not
  eliminated.
- **Dependency on the reviewer agent for the secondary check.** If review-triage-fix is not
  invoked in a cycle, the pattern-drift check is bypassed. Mitigated by the v1.2 safety net
  (which remains active in subsequent review-triage-fix invocations).
- **Minor coupling between `review-triage-fix/tests/run-tests.sh` and `~/.claude/agents/coder.md`.**
  The harness now reads 2 files. If in the future we split or rename coder.md, the anchor needs
  to be updated. Acceptable cost (1 path string to update).

### 4.3 Neutral

- The TDD plan written by the architect remains agnostic to the classifier — no workflow change
  for the architect agent.
- The memory `feedback_micropiano-refactor-cleanup.md` remains RESOLVED (v1.2 closes the cause,
  the classifier is additive).
- The orchestrator does not change: dispatches `coder` as before, receives summary, inspects
  transcript as before — except that now the transcript has `PATTERN:` headers.

### 4.4 Open questions (validation pending)

- **Does the LLM follow the `PATTERN: ...` contract with the same fidelity as the micro-plan?**
  Validatable only with an operational pilot (e.g. invoke the coder on a realistic task, count
  the header hit-rate). Initial confidence: medium — the contract is similar to the micro-plan
  but more structured.
- **How many drifts does the reviewer pattern-drift check actually catch?** Validatable with a
  pilot of 3-5 review-triage-fix cycles after deployment.
- **Does "1 pattern per tool call" granularity produce too many headers in large plans?**
  Validatable with metrics from the pilot.

---

## 5. References

- `~/.claude/agents/coder.md` (primary modification target)
- `~/.claude/agents/reviewer.md` (secondary modification target)
- `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2, complement; not modified)
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (target +1 anchor)
- `docs/vibe-coding-system.md` sec. 3.x (8 sub-agents) and sec. 11 (workflow concept->code)
- `docs/superpowers/specs/2026-05-19-review-triage-fix-design.md` (v1.0 -> v1.2 history)
- `docs/superpowers/specs/2026-05-20-review-triage-fix-v1.2-addremove-design.md`
- `docs/superpowers/plans/2026-05-20-review-triage-fix-v1.2-addremove.md`
- Memory `feedback_micropiano-refactor-cleanup.md` (RESOLVED 2026-05-20)
- Memory `feedback_bash32-constraint.md` (constraint for harness)
- Field test `docs/field-test-2026-05-18.md` (pilot history)
