# SPEC — Litter and debris discipline across agents

Source: GitHub issue #116

## Objectives
1. Make every writing agent account for the debris it creates.
2. Distinguish scratch artifacts from real new files at the commit gate.

## Scope
In: a cleanup clause in `coder.md`, `debugger.md`, `refactorer.md`; scratch-path classification in `commit` Step 1; a new test file in both CI registries.
Out: a dedicated cleanup agent running the six sequential elegance passes — `auto-format.sh`, the reviewer and `deep-refactor` already cover that ground and a per-task dispatch is disproportionate.

## Stack
Markdown agent bodies + bash 3.2 classification.

## Architecture
- Modified: `staging/plugin/agents/coder.md`, `debugger.md`, `refactorer.md` — a cleanup clause in the Output Format: list every temporary file, scratch script, debug log statement and temp branch created, and its disposition, before reporting done.
- Modified: `commit/SKILL.md` Step 1 — classify scratch-looking untracked paths into their own group.
- New: test file in both CI registries asserting the prose anchors and the classification.

## Data model
Scratch patterns, from the failure modes the source names: `tmp`, `scratch`, `debug`, `backup`, `*.log`, `interim_*`, `*_just_in_case`.

## API / Interfaces
Classification only; nothing is deleted automatically. Deletion stays a human decision.

## UI flows
The commit gate renders scratch-looking untracked files as a distinct group from ordinary new files.

## Edge cases
- An ordinary new source file must not be misclassified.
- A legitimate file named e.g. `debug.py` in a project that ships a debugger is a false positive — classification is advisory and never blocks.
- The agent-file anchors must be exact strings a test can assert.

## Success criteria
- [ ] Each of the three agent files contains the cleanup anchor.
- [ ] A scratch-named untracked file is rendered in its own group in the commit gate.
- [ ] An ordinary new source file is not misclassified.
- [ ] Nothing is deleted automatically.
- [ ] The new test file is registered in BOTH CI registries.
