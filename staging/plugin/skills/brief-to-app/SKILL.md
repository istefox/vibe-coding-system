---
name: brief-to-app
description: This skill should be used when the user wants to build an app or add a feature to an existing app from a brief, and wants the result to match what they asked for. Runs a single-session lane beside the concept-to-code chain - captures the brief verbatim, interviews in depth, composes design-brainstorm and macos-ux, and ends by printing a /goal contract that closes on an executed acceptance verdict. Triggers include "build me an app", "brief to app", "I want to build", "/skill brief-to-app".
---
<!-- No `disable-model-invocation`, deliberately (ADR-0067): this skill dispatches design-brainstorm
     and macos-ux through the Skill tool, and it is itself operator-invoked. -->

# brief-to-app — a build lane whose deliverable is a checked acceptance suite

The user wants to build: $ARGUMENTS

## Why this lane exists, in one paragraph you should read before running it

Building through `concept-to-code` arrives with missing functionality and a shape the operator did
not ask for. Three causes were measured (issue #439). The chain **discards the conversation by
design** — blueprint principle 11.1.3 puts a `/clear` between SPEC and implementation, so intent
travels through five lossy compressions and the `coder` reads the plan, never the operator.
**Nothing verified the product** until Wave 1: the gates checked that tests were green and that
requirement ids were *cited*, and ADR-0138 established that citation is not implementation. And
**integration was exercised by nothing**, because parallel coders rejoin by git merge.

This lane sets principle 11.1.3 aside **for itself only**. The existing chain is untouched.

## The one thing that makes this different from a long chat

**Quality degrades over a long session.** That is the operator's own report and it is the reason
this lane cannot defend intent by keeping the conversation in context — unbounded context is
exactly what rots. The defence is **artifacts on disk that every turn re-reads**:

- `BRIEF.md`, the operator's words, verbatim and never rewritten
- `ACCEPTANCE.md`, whose id set is machine-checked against `SPEC.md`

If you find yourself relying on something said twenty turns ago that is in none of the artifacts,
that is the failure mode, not a convenience. Put it in an artifact.

## Step 1 — `BRIEF.md`, verbatim, before anything else

Write the user's request to `BRIEF.md` **exactly as given**. Do not summarise it, do not tidy the
grammar, do not reorganise it into headings, do not translate it. If it is three words, `BRIEF.md`
is three words. If it contradicts itself, the contradiction is preserved and raised in Step 2.

Add nothing but a single first line `# Brief` and a final line recording the date.

**This is the highest-value instruction in the file.** Every rewrite is a compression, and the
compressions are what the issue measured. Later dispatch prompts name `BRIEF.md` as a read-first
artifact precisely so the original survives every summary between here and the finished app.

## Step 2 — interview

Interview with `AskUserQuestion`, one question at a time, at most four options each. Do not ask what
the brief already answers, and do not ask what has an obvious default — say the default and move on.

Cover these axes explicitly. `interview-driver` states them in a single line of prose; they are
enumerated here because a one-line list is what gets skipped:

1. **The job.** What does the user do today instead, and what makes that bad enough to build for?
2. **Scope boundary.** Name at least two things this will NOT do. A scope with no stated exclusions
   has not been bounded.
3. **Data.** What is stored, where, and what happens to it on upgrade and on deletion.
4. **The primary flow**, described as a sequence a person performs, not as a feature list.
5. **UI surface.** Platform, window or screen inventory, and whether it is a new app or a feature on
   an existing one. If macOS or SwiftUI, Step 4 will run.
6. **Failure behaviour.** What the app does when the network, the disk or the input is bad.
7. **Edge cases** the brief implies but does not state.
8. **Definition of done**, in the user's terms, before you translate it into criteria.
9. **Constraints** — deadline, dependencies that must not be added, conventions to follow.

Raise any contradiction in `BRIEF.md` here and record the resolution as an answer; do not edit the
brief to remove it.

Then write `SPEC.md`: objectives, scope with exclusions, stack, data model, primary flows, UI
surface, edge cases, and a success-criteria section in exactly this form (ADR-0048; the `- [ ]`
marker is what `spec-coverage.sh` and `acceptance-declare.sh` read, and `- R-01 — …` declares
nothing to either):

```markdown
## Success criteria

- [ ] R-01 — <the first requirement, stated so it can be checked>
- [ ] R-02 — <the second>
```

A criterion that is a documentation, process or deployment obligation rather than something a test
can assert carries `(no-test: <reason>)` in its own item text, reason at least 20 characters after
the colon (ADR-0138). Step 5 refuses an acceptance case for such a criterion, so mark them here or
the reconciliation will contradict you later.

## Step 3 — design alternatives, composed not reinvented

Invoke the `design-brainstorm` skill in-session. **In this lane it is not optional**, unlike chain
gate 1b: the whole complaint the lane answers is that the delivered shape was not the requested one,
and a single unexamined approach is how that happens.

```
Use the design-brainstorm skill.
Chain context: brief-to-app (step 3).
Read first: <project-root>/BRIEF.md — the operator's own words, unedited. It outranks any summary.
Requirements source: SPEC.md at <project-root>/SPEC.md.
Explore design approaches with structured ideation techniques. Write the structured brief to
<project-root>/BRAINSTORM.md.
Do NOT write SPEC, ADR, or plan.
Do NOT produce a closing summary or handoff message after writing BRAINSTORM.md.
Return silently — the brief-to-app orchestrator continues immediately after.
```

**CRITICAL — lane continuation (no stop):** the Skill tool has returned. Do NOT emit text, do NOT
summarise, do NOT wait for input. Your next output is a tool call. Any text here is a lane-stop bug.

Then present the alternatives to the user and record the chosen one in `SPEC.md`.

## Step 3.5 — Claude Design, optionally (VCS-052, ADR-0181)

Offer, do not force: not every brief needs a generated mockup, and unlike Steps 3/4 this one
leaves the session — the human goes to claude.ai/design and comes back. No manifest exists in
this lane, so what Gate 1d tracks via `current_step` and `artifacts.design`, this lane tracks by
writing `DESIGN.md` (same file, same template) and recording its path in `SPEC.md`, the way
Step 3 already records the chosen alternative.

Use `AskUserQuestion`:
```
question: "Generate a Claude Design (claude.ai/design) prompt for an initial visual mockup before macOS UX / the plan?\nThis requires a human in a browser on a Pro/Max/Team/Enterprise plan — there is no API."
header: "Claude Design"
options:
  - label: "Yes, generate a prompt"
    description: "Invoke claude-design-brief, write DESIGN-PROMPT.md, then bring back a shared URL"
  - label: "No, skip"
    description: "Proceed to Step 4 without one"
```

On "No": record nothing, proceed to Step 4.

On "Yes": invoke the `claude-design-brief` skill in-session:
```
Use the claude-design-brief skill.
Chain context: brief-to-app (step 3.5).
Read first: <project-root>/BRIEF.md — the operator's own words, unedited. It outranks any summary.
Requirements source: SPEC.md at <project-root>/SPEC.md.
If present, also read BRAINSTORM.md at <project-root>/BRAINSTORM.md for the adopted approach.
Compose a single copy-paste-ready Claude Design prompt and write it to
<project-root>/DESIGN-PROMPT.md.
Do NOT write SPEC, ADR, plan, or DESIGN.md.
Do NOT produce a closing summary or handoff message after writing DESIGN-PROMPT.md.
Return silently — the brief-to-app orchestrator continues immediately after.
```

**CRITICAL — lane continuation (no stop):** the Skill tool has returned. Do NOT emit text, do NOT
summarise, do NOT wait for input. Your next output is the message below.

Emit: "Prompt written ✓ — <project-root>/DESIGN-PROMPT.md. Go to claude.ai/design
(Pro/Max/Team/Enterprise plan required), paste the fenced block, ask for N screens, and share
with link access. Paste the shared URL back here when ready." Then wait for the operator to paste
the URL, in this same conversation.

On the pasted URL: run `bash ~/.claude/skills/concept-to-code/scripts/design-url-check.sh --url
<url>` (shape only, never fetched — see the checker's own contract; exit 3 means the check did
not run, record `did-not-run` rather than silently `valid`). Write `<project-root>/DESIGN.md`
with the same structure the chain's Gate 1d writes (Source / Shared URL / URL shape check /
Captured / Prompt / Local export / Handoff bundle / `## Screens` / `## Binding decisions` /
`## Not decided here`), filled from whatever the operator transcribes. Then add one line to
`SPEC.md` recording the path: `Design: DESIGN.md (from claude.ai/design)`.

## Step 4 — macOS UX, conditionally

Run the detector rather than judging by eye — it strips code spans and table rows first, which is
what stops a SPEC that merely mentions SwiftUI from triggering it (ADR-0093):

```bash
bash ~/.claude/skills/concept-to-code/scripts/detect-macos.sh "<project-root>/SPEC.md"
```

On `MACOS_DETECTED`, invoke `macos-ux` in design mode with the same read-first line, producing
`UX-BLUEPRINT.md`. On `NOT_MACOS`, skip to Step 5 without comment.

## Step 5 — `ACCEPTANCE.md`, and the check that makes it real

Write `ACCEPTANCE.md` with one section headed `## Acceptance criteria` — a heading
`spec-id-predicate.awk` already recognises — and one checklist item per **testable** criterion:

```markdown
## Acceptance criteria

- [ ] R-01 — <the observable a test asserts: what is done, and what is then true>
```

State an observable, not a restatement of the requirement. "R-01 — archiving works" is a
restatement. "R-01 — archive a note, then assert it is absent from the active list and present in
the archive" is an observable.

Then run the reconciliation. It reads both documents through the same predicate the chain's own
coverage gate uses, and it runs in **both directions**:

<!-- fence-contract: brief-to-app-acceptance-declare -->

```bash
bash <<'FENCE_BASH'
set -u
DECL="$HOME/.claude/hooks/acceptance-declare.sh"
[ -r "$DECL" ] || { printf 'HALT: acceptance-declare.sh not found at %s\n' "$DECL"; exit 1; }
out=$(bash "$DECL" --spec "$PROJECT_ROOT/SPEC.md" --acceptance "$PROJECT_ROOT/ACCEPTANCE.md" 2>&1)
rc=$?
printf '%s\n' "$out"
case "$rc" in
  0) printf 'ACCEPTANCE-DECLARE: reconciled\n' ;;
  1) printf 'HALT: a testable criterion has no acceptance case (UNDECLARED above)\n'; exit 1 ;;
  3) printf 'HALT: structural — ORPHAN, CONTRADICTION, NO-IDS or NO-PREDICATE above\n'; exit 1 ;;
  *) printf 'HALT: acceptance-declare could not run (exit %s)\n' "$rc"; exit 1 ;;
esac
FENCE_BASH
```

`PROJECT_ROOT` must be exported before this fence runs. **Do not proceed to Step 6 on any HALT.**
Fix the documents and run it again — the four outcomes have four different repairs, and the script
names which one applies.

## Step 6 — print the `/goal` contract. Do not invoke it.

`goal-loop` carries `disable-model-invocation`, so the Skill tool cannot reach it and a skill must
not set the goal on the user's behalf (ADR-0022). **Print** the block below and tell the user to
paste it into the composer prefixed with `/goal`.

`Stop when:` closes on the line `acceptance-run.sh` prints, which is what makes it provable from the
transcript — the binding requirement, since the evaluator cannot call tools and judges only what
was surfaced.

```text
**Objective:** implement the app described in SPEC.md until every acceptance criterion passes.
**Read first:** BRIEF.md (the operator's own words — it outranks any summary in this conversation),
SPEC.md, ACCEPTANCE.md, and BRAINSTORM.md for the chosen approach.
**Constraints:** do not edit BRIEF.md. Do not delete, skip, weaken or narrow any acceptance case or
test. Do not remove an R-NN from ACCEPTANCE.md. Do not add dependencies. Do not refactor unrelated
code. Never create an ADR.
**Validate:** `bash ~/.claude/hooks/acceptance-run.sh --declared ACCEPTANCE.md` after each change.
**Stop when:** that command prints a line beginning `ACCEPTANCE-RESULT` with `fail=0` and
`missing=0` and no `ACCEPTANCE-HALT` line, OR when further progress requires human input, OR after
30 turns.
```

Re-read `BRIEF.md` at the start of every turn of that loop. It is on disk for that reason.

## What this file enforces, and what it only instructs

Rule 16 applies to the whole document and is stated once here rather than hedged in every section.

**Enforced:** exactly one thing — Step 5's reconciliation. `acceptance-declare.sh` runs, it exits
non-zero on a real mismatch, and the fence halts the lane. Wave 1's `acceptance-run.sh` is the
second enforcement, and it runs inside the `/goal` loop rather than here.

**Instruction only:** everything else. That the brief is written verbatim, that the interview covers
nine axes, that alternatives are explored, that an acceptance case states an observable rather than
a restatement — no mechanism checks any of it. A green Step 5 means the two documents agree about
which ids exist. It does not mean the criteria are good, and nothing in this lane claims otherwise.
