# ADR-0181 — `VCS-052`: Claude Design at Gate 1d of the concept-to-code chain

- **Status:** Accepted
- **Date:** 2026-08-30
- **Builds on:** ADR-0093 (macOS-detector false positives — the reason Gate 1d ships with **no**
  detector at all), ADR-0099 (`hitl_gates` approval enforcement — Gate 1d/H1d's six new transition
  pairs are confirmed outside its six-pair whitelist, so this change cannot weaken it), ADR-0108
  (the plant registry — CD1-CD7's mechanism, rule 1 and rule 4 applied throughout), ADR-0164 (Gate
  2c's external-dependency pause, the resumable "Not yet" shape Gate 1d-B reuses).

## Context

Apps and webapps produced by this system come out looking alike. The reason is structural, not
stylistic: nothing in the standard chain is an artifact representing the chosen visual design.
Measured against the files before this change — `interview-driver` treats UI as one free-prose axis
in `SPEC.md`; Gate 1b's `BRAINSTORM.md` is about approach, not appearance, and says so in its own
text; Gate 1c's `UX-BLUEPRINT.md` is structure only (windows, navigation, menus) and macOS-only;
Gate 5.05's `ui-layout-audit` runs *after* implementation, fixing layout mechanically. Both design
artifacts are read once, by the architect at Step 2, and never again — `grep` found zero occurrences
of `BRAINSTORM.md` or `UX-BLUEPRINT.md` in `references/step5-implementation.md` and none in
`agents/coder.md` before this change. Appearance reached implementation only as whatever the
architect happened to paraphrase into an ADR, which is exactly why every output looked like the same
default.

Claude Design (claude.ai/design) is a human-mediated web product with no public API: a human pastes
a prompt in and copies a result out. The integration is therefore a two-phase, resumable gate —
generate a prompt, pause, accept what comes back — modeled on Gate 2c's external-dependency pause
("Not yet, I will provision now" leaves `current_step` unchanged, chain stays resumable).

**The honest constraint that shapes the design:** a shared Claude Design URL is organization-scoped
and login-walled. No subagent in a worktree has a browser or an org session, so the URL alone cannot
reach the coder. The URL is provenance; transcribed text plus any local export is content.

## Decision

**Gate 1d — unconditional, optional, two-phase, inserted after Gate 1b/1c and before
`step_2_architecture`** (hybrid mirror Gate H1d, before `step_h2_plan`). New manifest states
`gate_1d_claude_design_decision` / `gate_h1d_claude_design`. Placed last of the pre-architecture
gates on purpose: the generated prompt can quote the adopted approach from `BRAINSTORM.md` and the
HIG skeleton from `UX-BLUEPRINT.md`, not only `SPEC.md`.

**No detector — deliberate, and the inverse of Gate 1c's mistake.** ADR-0093 recorded that Gate 1c's
macOS detector fired on meta-SPECs in this very repo and never on a real macOS app. Here the
dangerous direction is inverted: a false negative would hide the very gate the user asked for. An
always-offered gate defaulting to "No" costs one click and makes no claim about the SPEC, so there is
nothing about it to be wrong. Any recommendation belongs on option ordering, never on whether the
gate fires.

- **1d-A** (`AskUserQuestion`): Yes, generate a Claude Design prompt / No, skip / Abort. On Yes:
  invoke `claude-design-brief`, which writes `DESIGN-PROMPT.md`; emit the path and the claude.ai
  instructions. Do not transition.
- **1d-B** (`AskUserQuestion`): Paste the shared URL (`Other` → URL, optionally appending
  `+ export:<path>` or `+ bundle:<path>` to declare a higher fidelity tier) / Not yet, still
  designing / Skip after all. "Not yet" leaves `current_step` unchanged — Gate 2c's resumable shape,
  surviving a pause of days.
- On URL: run `design-url-check.sh`, write `DESIGN.md`, set `artifacts.design`, transition.

**Autopilot default is always "No", stated as structural, not a preference**, same family as Gate
2b's TOFU and Gate 2c's provisioning pause: `Gate 1d: autopilot — Claude Design needs a human in a
browser, skipped ✓`.

**`claude-design-brief`, a new skill**, matching the `design-brainstorm`/`macos-ux` precedent
exactly — one file out (`<project-root>/DESIGN-PROMPT.md`), manifest write owned by the
orchestrator, its own `tests/` and its own perimeter assertion. A file rather than chat output
because chat cannot be re-read after Gate 4's `/clear`, cannot be committed, and cannot survive the
1d-B pause.

**`DESIGN.md`, written by the orchestrator**, the same shape Gate 2c already uses for
`external_dependencies`: source, shared URL, URL-shape-check result, capture timestamp, prompt
pointer, local-export pointer, handoff-bundle pointer (marked `UNVERIFIED` — see Negative
consequences), a `## Screens` table (Screen / Purpose / SPEC ids / Notes), `## Binding decisions`,
`## Not decided here`. Three fidelity tiers, named at the gate so the choice is explicit: URL only
(the stated minimum); URL + standalone-HTML export (recommended, labelled so — a file the coder can
actually read); URL + handoff bundle (accepted as an opaque directory; no mechanism may depend on its
shape).

**Reaching the coder — the crux, and the exact bug class that made Gates 1b/1c invisible past Step
2.** Three parts, all required:

- (a) **Architect dispatch** (`SKILL.md` Step 2 and Hybrid H2): read `<manifest.artifacts.design>`
  and any declared local export; its Binding decisions are a constraint on the plan, not an input to
  weigh; every screen its table names must be cited by a plan task or the ADR must state why it is
  not being built. INSTRUCTION, not enforced by a script.
- (b) **Coder dispatch** (`references/step5-implementation.md`), at **both** dispatch templates —
  the workflow-path preamble and the Agent-tool fallback template. Editing only one is precisely the
  omission that left Gates 1b/1c's artifacts unread past Step 2; this is the single structural
  change that makes Gate 1d different from its predecessors.
- (c) **`design-coverage.sh` — the actual enforcement**, modeled on `spec-coverage.sh`, a CHECKER
  (rule 5): every row of `DESIGN.md`'s `## Screens` table must be cited by at least one plan task.
  Exit 0 clean, 1 uncovered screens on stdout (`UNCOVERED<TAB><screen>`), 2 bad invocation, 3
  DID-NOT-RUN. Denominator guard (rule 7): a table parsing to zero rows is exit 3, never a clean
  pass. Population guard (rule 18): matches against the `--plan` file only, never a repo-wide sweep.
  Run at Gate 2, so the human reads "N of M designed screens have no plan task" before approving the
  architecture.

**`design-url-check.sh`, a shape-only CHECKER that never fetches the URL.** The resource is
org-scoped and login-walled: a fetch returns 401/404 for a perfectly valid link, and a 200 would
prove nothing about the design's content either way. Exit 0 shape valid (`^https://claude\.ai/`), 1
non-empty and non-matching (the gate re-prompts, does not proceed), 2 bad invocation, 3 DID-NOT-RUN —
the gate still records the pasted URL and writes `URL shape check: did-not-run`, never silently
"valid". The broad prefix ships now; a narrower regex waits for a confirmed real share-URL shape,
since a guessed narrow one fails closed on every valid link.

**A latent pre-existing defect had to be fixed first.** `references/step5-implementation.md`'s 5.0.1
pre-flight fence classified a dirty tree via the arm `"$SPEC_REL"|"$ADR_REL"|"$PLAN_REL"|CLAUDE.md)`
— `BRAINSTORM.md` and `UX-BLUEPRINT.md` were in neither that arm nor Gate 4.0's `--include` list, so
a chain that had run Gate 1b/1c left a root artifact classified `PREFLIGHT_OTHER`, whose printed
remediation (`git stash push -u`) would have stashed the design brief. `DESIGN.md`/`DESIGN-PROMPT.md`
would have inherited the same defect on their first real run. Fixed by widening the fence's `export`
prologue and `case` arm to all four artifacts (verified an empty `_REL` cannot spuriously match a
non-empty `$f`), and Gate 4.0's `--include` correspondingly, dropping null bracketed entries as an
INSTRUCTION (not mechanically enforced — see Negative consequences).

**`brief-to-app`** (the no-manifest lane) gained a parallel Step 3.5 between Step 3 and Step 4,
writing `DESIGN.md` directly plus a one-line `SPEC.md` note, since that lane has no manifest to carry
`artifacts.design` and no cross-session resumability to speak of.

## Alternatives considered

- **A macOS-style detector deciding whether to offer Gate 1d.** Rejected on ADR-0093's own evidence:
  a detector here would risk false negatives hiding a gate the user explicitly wants available, the
  opposite failure direction from Gate 1c's false positives. An always-offered, "No"-defaulted gate
  costs one click and is never wrong about the SPEC because it makes no claim about it.
- **A third `AskUserQuestion` phase to declare the fidelity tier separately.** Rejected in favor of
  folding tier declaration into 1d-B's existing `Other`-free-text URL-paste option
  (`+ export:<path>` / `+ bundle:<path>`), keeping the gate at exactly two phases while still naming
  all three tiers explicitly, since the dispatch scope fixed the two-phase structure.
- **Fetching or programmatically validating the pasted Claude Design URL's content.** Rejected: the
  resource is login-walled and org-scoped, so a fetch proves nothing a human's own eyes did not
  already confirm, and would give a false sense of automated verification over a link a script
  cannot actually interpret.
- **Enforcing architect/coder Binding-decisions compliance mechanically**, e.g. failing the plan if a
  screen's binding decision is contradicted. Rejected as out of scope: `design-coverage.sh` enforces
  *presence* (a screen is cited by some task), never *fidelity* to the decision's content, which
  would require a semantic diff this system has no primitive for.

## Consequences

### Positive

- Appearance now has a durable, coder-visible artifact chain: `DESIGN-PROMPT.md` (a human's
  starting point) → `DESIGN.md` (what came back, transcribed) → both dispatch templates (so the
  coder actually reads it, unlike Gates 1b/1c) → `design-coverage.sh` at Gate 2 (so an uncited
  screen is visible before implementation starts, not discovered after).
- The gate is unconditional, so there is no detector to be wrong about — the class of failure
  ADR-0093 recorded for Gate 1c cannot recur here by construction.
- Fixed, as a side effect required to ship this safely, a pre-existing defect that would have
  misclassified `BRAINSTORM.md`/`UX-BLUEPRINT.md` dirty-tree state and risked stashing a design
  brief on `git stash push -u` remediation.
- Six new transition pairs, two new manifest states, and 41 assertions in
  `claude-design-gate.test.sh` (CD1-CD7 individually planted and confirmed firing RED against their
  declared mutations via `plant-check.sh`) all land in the same change, so nothing here ships with an
  unverified enforcement path.

### Negative, stated plainly

- **No mechanism verifies the implemented UI resembles the Claude Design mockup.**
  `design-coverage.sh` checks that a screen is *cited*, never that the built screen *matches* the
  design — coverage is not fidelity. The retained skills (`macos-ux`, `ui-layout-audit`,
  `swiftui-pro`) are the only, partial, post-hoc mitigation this system has for that gap; it is not
  closed by this change.
- **`design-url-check.sh`'s shape validity is neither existence nor correctness.** A URL matching
  `^https://claude\.ai/` proves only that a human pasted something shaped like a claude.ai link — not
  that the link resolves, not that it points at a real design, not that the design matches the SPEC.
  The real validation is the human who pasted it, and the checker says so in its own header comment.
- **Handoff-bundle composition is unverified.** The primary source (Claude Design's own product
  surface) does not document what a "handoff bundle" actually contains. `DESIGN.md`'s template
  carries the bundle pointer marked `UNVERIFIED`, and no mechanism in this system depends on its
  internal shape — accepted as an opaque directory only.
- **Architect and coder compliance with Binding decisions is an INSTRUCTION, not an enforcement**
  (rule 16): a plan or an implementation can silently ignore a binding decision and nothing in this
  chain will catch it. `design-coverage.sh` only proves a screen was *cited*.
- **Gate 4.0's `--include` null-entry dropping is an INSTRUCTION**, not mechanically verified for
  every possible combination of absent artifacts; the widened 5.0.1 fence's `case`-arm widening is
  the one piece that is test-executed (`recovery-preflight.test.sh`), the `--include` construction
  itself is not.
- **Gate 1d always runs after Gate 1c even on non-macOS SPECs**, where `UX-BLUEPRINT.md` does not
  exist and the generated prompt falls back to `SPEC.md`'s UI-flows section alone — accepted per the
  plan's own note as probably fine, not measured against a real non-macOS run.
