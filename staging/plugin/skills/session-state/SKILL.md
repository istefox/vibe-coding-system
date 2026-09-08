---
name: session-state
description: >
  Writes <project-root>/.claude/context.md, the single cross-session state file injected at every
  SessionStart. Two callers: automatic (commit skill Step 5.5, right after a successful commit) and
  manual (invoke anytime to snapshot in-progress work before ending a session — e.g. before a
  reboot, or when stepping away mid-task without committing). Triggers: "/skill session-state",
  "save the session state", "salva lo stato", "sto per riavviare", "snapshot before I go".
allowed-tools: Read, Write
---

# `session-state` — Cross-session state writer

Writes one file, `.claude/context.md`, read back automatically at the next `SessionStart` by
`session-context-inject.sh`. This is the single producer for that file — `commit` Step 5.5 and any
manual invocation both call this skill instead of writing the template themselves (ADR-0197).

## When to invoke

- Automatically: `commit` skill, Step 5.5, immediately after a successful `git commit`. Also
  reached transitively at the end of the `concept-to-code` chain, which invokes `commit` at its own
  Step 7.
- Manually: any time you want to snapshot state without committing — before closing the laptop,
  before a reboot, before switching to unrelated work mid-task, or simply on request.

## Procedure

1. **Always Read `<project-root>/.claude/context.md` first**, even if you expect it not to exist:
   the Write tool refuses to overwrite a file that was not read in the current session. If the Read
   errors (file absent), ignore it and proceed.

2. Determine the caller mode:
   - `after commit` — called from `commit` Step 5.5. `Last commit` is the commit that just landed.
   - `manual save` — called directly, by the user or on request. `Last commit` is the current
     `HEAD`, which may predate uncommitted work in the tree.

3. Collect facts:
   - `Branch`: current branch (`git branch --show-current`).
   - `Last commit`: short hash + subject of `HEAD`.
   - Working tree state: `git status --short`. If non-empty, `In progress` MUST state the count of
     modified/untracked files, not just the qualitative work in progress — this is the case a
     manual save exists for.
   - Open manifest: check `docs/manifests/` for one with `status: in_progress`; if found, its
     `current_step` feeds `Open decisions`.

4. Write or overwrite `<project-root>/.claude/context.md` (create `.claude/` if missing):

```
## Status (YYYY-MM-DD HH:MM) — <after commit | manual save>
**Branch:** <current-branch>
**Last commit:** <short-hash> — <commit subject>
**In progress:** <what's happening now; if the tree is dirty, name the file count — or "—">
**Next:** <1-3 actionable items, priority order — or "—">
**Open decisions:** <manifest current_step / recent ADR — or "none">
**Notes:** <non-obvious gotchas, blockers, deferred risks>
```

## Rules

- **Max 20 lines total.** Factual — no speculation beyond what context provides.
- **`Notes` is omitted entirely when there is nothing to say** — not written empty, not written
  with "—". A field that is always present and always blank teaches readers to skip it. This is
  the one field `context.md` lacked before ADR-0197: gotchas, blockers, and deferred risks used to
  get stuffed into `Next` for lack of anywhere else to go (`this file's own history is the
  example`).
- **Boundary with `Open decisions`**: that field is *only* what derives from a manifest at
  `status: in_progress`, or a recent ADR (ADR-0135). Anything that is not a formally open decision
  belongs in `Notes`, never in `Open decisions` — otherwise the two fields compete for the same
  content.
- **`Next` holds 1-3 items** in priority order, not a single line — real sessions routinely have
  more than one loose end.
- **This is an instruction, not an enforcement.** Nothing checks that `Notes` gets filled in when
  it should — the model writing this file is trusted to judge what is non-obvious enough to record.
- Emit one line after writing: `"Context → .claude/context.md"`.
- Wrap the whole invocation in `|| true` when called from `commit` — never abort the commit flow if
  this fails. A standalone manual invocation reports a normal error instead.
- Say nothing else when invoked manually beyond the confirmation line — this is a save action, not
  a conversation.
