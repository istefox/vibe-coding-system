---
name: interview-driver
description: This skill should be used when starting a new project or non-trivial feature and a SPEC.md must be produced by interviewing the user in depth with the AskUserQuestion tool. Triggers include "interview me", "let's spec it", "new project from scratch", and invocation from the concept-to-code chain orchestrator (Step 1).
---
<!-- No `disable-model-invocation`, deliberately (ADR-0067): concept-to-code Step 1 / Step H1
     dispatch this skill through the Skill tool, which that flag blocks outright. -->

The user wants to build: $ARGUMENTS

Interview them in depth with the AskUserQuestion tool. Cover: technical implementation, UI/UX (if applicable), edge cases, trade-offs, operational constraints, Definition of Done.

Do not ask obvious questions: dig into the hard points. One question at a time, max 3-4 options per question. Continue until everything is covered.

Then write `SPEC.md` in the current directory with: objectives, scope, stack, architecture, data model, API, UI flows, edge cases, success criteria. No code at this stage.

Number every success-criteria checklist item `R-01`, `R-02`, ... at the start of the item text (ADR-0048).

The word "checklist" is load-bearing and prose alone was not enough — a SPEC written with plain
bullets passed the coverage gate silently with 17 requirements declared (issue #171). Write the
section literally like this, matching `spec-from-issue/SKILL.md`'s template:

```markdown
## Success criteria

- [ ] R-01 — <the first requirement, stated so it can be checked>
- [ ] R-02 — <the second>
```

The `- [ ]` marker is what `spec-coverage.sh` reads. `- R-01 — …` declares nothing to it. A SPEC
that reaches Step 5 in the plain-bullet form is repaired automatically by `spec-normalize-ids.sh`
(ADR-0072), but the repair exists for SPECs written before this template — not as licence to skip
it.

A criterion that is a documentation, process or deployment obligation — "the ADR records X", "the
issue is filed", "the harness is run" — rather than something a test can assert, carries
`(no-test: <reason>)` appended to its item text, reason at least 20 characters after the colon
(ADR-0138). This is an instruction to you as the generator, not an enforcement: nothing forces you
to write it, and no check in this skill confirms you did. What changes downstream is the failure
shape at Step 5 — an unmarked documentation requirement produces a halt naming the remedy, not a
silent false pass.
