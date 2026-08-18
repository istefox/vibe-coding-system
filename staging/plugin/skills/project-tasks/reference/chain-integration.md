# Chain integration and cadence

## Contents

- Installation
- When to run it
- Hook into concept-to-code
- Hook into project-conductor
- Relationship to the other skills
- Optional: automatic capture

## Installation

```bash
cp -R /Users/stefer/Developer/steve-skills/tasks ~/.claude/skills/project-tasks
chmod +x ~/.claude/skills/project-tasks/scripts/scan.sh
```

Then `/project-tasks` from any project session. The skill is global, the ledger is per-project.

## When to run it

The session capture only sees what is still in context, so the cadence is driven by context
loss, not by the clock.

| Moment | Why |
|---|---|
| **Before `/clear` or `/compact`** | The only irreversible one. Everything the session observed and never wrote down dies here. |
| **Before `/commit`** | So the ledger and the history tell the same story, and an open P1 is visible before the commit gate, not after. |
| **After review-triage-fix or deep-refactor** | Deferred findings land in the ledger instead of evaporating. |
| **At the end of a chain feature** | Closes the loop on what the feature left behind. |
| **Session close** | Same reason as `/clear`. |

Roughly every 45 to 90 minutes of active work, or whenever the context indicator drops below a
quarter. Running it more often re-reads the same state and adds nothing.

Running it *less* often has one specific cost: entries sourced from the session degrade first.
A compacted session yields vague entries, and vague entries are the ones that never get fixed.

## Hook into concept-to-code

Paste into `~/.claude/skills/concept-to-code/SKILL.md`, in the implementation step, immediately
before the commit gate:

```markdown
### Step 7b — Update the task ledger

Before the commit gate, invoke the `project-tasks` skill.

It captures what this feature left open: deferred review findings, temporary workarounds,
cut scope, unanswered decisions. Its approval gate is separate from and prior to the commit
gate.

If it reports an open **P1** that this feature introduced, stop and surface it to the user
before proposing the commit.
```

## Hook into project-conductor

Paste into `~/.claude/skills/project-conductor/SKILL.md`, in the loop that advances from one
feature to the next, right after a feature is marked `[x]` in `PROJECT.md`:

```markdown
Before starting the next feature, invoke the `project-tasks` skill.

The session boundary between features is where issues are lost. Running the ledger here means
the next feature starts from a written state rather than from what survived compaction.

An open P1 in the ledger is a reason to raise it with the user before starting new work, not
a reason to stop autonomously.
```

## Relationship to the other skills

| Skill | Boundary |
|---|---|
| `review-triage-fix`, `deep-refactor` | They find and fix. This one records what they chose not to fix. |
| `security-audit` | Report-only by design. This one imports its unfixed findings; it never fixes them either. |
| `project-conductor` | Owns `PROJECT.md`, the planned roadmap. This one owns `TODO.md`, what is open. An issue that is also a roadmap row appears here **with a pointer to its phase**, rather than being excluded: the ledger stays complete, and the pointer is what stops it becoming a second roadmap. |
| `commit` | Runs after this one. The ledger update and the code change belong in the same commit. |
| `vibe-status` | Reports on the vibe-coding system itself. This one reports on the project being built. |
| TaskCreate / TaskUpdate tools | Ephemeral, one session, execution tracking. This skill is durable, cross-session, state tracking. They do not overlap. |

## Optional: automatic capture

The rejected design was a `Stop` hook appending every issue at the end of each turn. It was
rejected for a reason worth keeping written down: automatic capture with no gate fills the
ledger with low-confidence entries, and a noisy ledger stops being read. Manual invocation at
the four moments above catches the same issues while the context still holds the evidence.

If it is ever added, gate it: append to a staging block inside `TODO.md`, never straight into
`Open Issues`, and have the next full run triage that block through the normal gate.
