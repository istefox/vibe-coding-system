---
name: interview-driver
description: This skill should be used when starting a new project or non-trivial feature and a SPEC.md must be produced by interviewing the user in depth with the AskUserQuestion tool. Triggers include "interview me", "let's spec it", "new project from scratch", and invocation from the concept-to-code chain orchestrator (Step 1).
disable-model-invocation: true
---

The user wants to build: $ARGUMENTS

Interview them in depth with the AskUserQuestion tool. Cover: technical implementation, UI/UX (if applicable), edge cases, trade-offs, operational constraints, Definition of Done.

Do not ask obvious questions: dig into the hard points. One question at a time, max 3-4 options per question. Continue until everything is covered.

Then write `SPEC.md` in the current directory with: objectives, scope, stack, architecture, data model, API, UI flows, edge cases, success criteria. No code at this stage.
