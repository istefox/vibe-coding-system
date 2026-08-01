# ADR-0112 — An armed guard with no owning session, and the rule that made it hurt

- **Status:** Accepted
- **Date:** 2026-08-01
- **Issues:** #321 (closes), #323 (closes)
- **Related:** ADR-0022 (the guard and the marker contract), ADR-0060 (the two-marker split),
  ADR-0074 / ADR-0079 (the same fix-one-boundary-not-its-sibling shape, twice before), ADR-0076
  (absent, foreign and unreadable are three states), ADR-0082 (a line-number cross-reference rots),
  ADR-0090 (inspect what a plant produced), ADR-0108 (the plant registry)

## Context

`nightly-autopilot` arms `nightly-guard` by creating `.claude/nightly-state/active` in Phase 1 and
removes it **only** in Phase 2. A session that dies — context exhaustion, a crash, the human pressing
stop — never reaches Phase 2, so the marker outlives the run and the guard stays live in the human's
own later sessions.

The guard is right to fail closed. What was missing is an exit.

The two issues ship together because measuring showed **neither explains the 2026-07-31 incident
alone**. A stale marker on its own blocks only *forbidden* publishes — merge, force, `--no-verify`,
push-to-main; an ordinary `git push` still passes the halt checks. What turned an ordinary publish
into a forbidden one is #323.

## What was measured, 2026-08-01

Both issues' claims hold. Six things they do not say.

**V1 — #321's `nightly-guard.sh:166` reference rotted the same day it was written, by the ADR-0111
commit.** `git show 4c63f64:…| sed -n '166p'` returns the active-marker check exactly; that commit
added 8 header lines and the check is now at `:174`. A live instance of ADR-0082's rule, eight hours
old, in an issue filed by the same hand that moved it.

**V2 — the marker sites are exactly one and one.** `touch` at §3.1, `rm -f` at §4, and nothing else
in `staging/` or `docs/` writes or removes it. §4 says the report is written *"on every exit path"*,
which is true only of paths the model reaches — a killed session executes nothing.

**V3 — the RUNBOOK is worse than "one grep hit".** The single hit sits inside `## Aborting a run`,
the section a human lands on *after stopping a run*, and it reads: *"The working tree and whatever
was already committed and pushed are intact."* That is not a missing section. It is the right
section giving false reassurance at the exact moment the marker is being left behind.

**V4 — `.claude/nightly-state/started-at` exists in this repository and nothing in the codebase
writes it.** It holds `2026-07-31T21:03:40Z`. §3.1 said *"Record `started_at` via `date -u`"* without
naming a location, so an orchestrator invented one. **A value with no specified home gets one
anyway, chosen by whoever runs the step** — which is the whole reason this ADR specifies the marker's
format rather than saying "record the session id".

**V5 — the mechanism already exists, and a pid would have been actively wrong.** `.session_id` is a
top-level field on PreToolUse payloads, read today by `agent-write-scope.sh`,
`agent-command-scope.sh` and `db-backup-guardrail.sh`; `CLAUDE_CODE_SESSION_ID` carries the same
value in Bash tool calls (ADR-0029, reused by ADR-0110). #321 proposes "pid, session id, timestamp".
**The pid is the one that cannot work**: the marker is written from a Bash tool call whose subprocess
exits within milliseconds, so a recorded `$$` is always dead and a liveness check on it would report
every live run as stale.

**V6 (#323) — reproduced live, and the fix probed before it was proposed.** Extracting
`is_forbidden_publish` and running it reproduces the issue's three cases exactly. The segment-scoped
candidate also gets right two cases the issue does not name:
`gh pr create --base main && git push origin feat/x` → ALLOW (a PR *to* main is fine; only *pushing
to* main is forbidden) and `git push origin feat/main-thing` → ALLOW. Every genuine push-to-main form
still halts, including `:refs/heads/main`, `+main`, `master`, and a `main` destination reached after
an unrelated leading command.

## Decision

### D1 — The marker records its owner, and the format is specified

```
session_id=<CLAUDE_CODE_SESSION_ID>
started_at=<ISO-8601>
```

*Presence* still arms the guard, so `[ -f active ]` is untouched and **a legacy bare-touch marker
still arms it**. `started_at` for the morning report is read back from here; §3.1 now forbids
inventing a separate file for it, naming V4 as the reason.

### D2 — `nightly-disarm.sh` refuses the owning session, and that is what holds R-04

It refuses when the marker's recorded `session_id` equals `CLAUDE_CODE_SESSION_ID`. R-04 —
*nothing lets an active run disarm itself* — is then a property of the mechanism rather than a
sentence in a SKILL.md.

**It claims no liveness oracle, deliberately.** A different session id is not proof the owner is
dead. A transcript-mtime threshold would look like proof and would be a heuristic. It reports what it
found and lets the human decide, which is what a blocked human actually needs.

**A legacy marker disarms with a note.** Absent `session_id` is not foreign and not corrupt
(ADR-0076); refusing there would strand exactly the people this exists for — the ones whose marker
predates the fix. Same for an unknown *current* session id: **the recovery path never fails closed**,
which is the opposite of the guard's own posture and correct for the same reason the guard's is.

### D3 — The disarm clears the whole transient state

`active`, `build-status`, `rtf-blocker`, `token-budget`, `started-at`, and the root `needs-human`,
naming each removal. The marker is one of five ways to be stuck: a stale `build-status` reading `RED`
halts the in-script `--check` gate **regardless of the marker**. Clearing only `active` would leave
the command looking like it worked while the human stayed blocked — a disarm that lies is worse than
no disarm.

Exit codes: `0` cleared or nothing armed, `1` refused (owner), `2` bad invocation, `3` did not run.
**`3` is separate from `0` because a blocked human reads `0` as "you are free now"**; if that came
from an unreadable state directory they are still blocked and now believe otherwise.

### D4 — The guard names the exit, and only when it is not the owner

The halt message gains the owner, the time and the disarm command **only** when the marker's
`session_id` differs from the event's. When they match — a live run halting normally — the message is
byte-identical to before: inviting a running roadmap to disarm itself is the one thing R-04 forbids.
Same silence when either id is unreadable; saying nothing beats guessing an owner.

### D5 — #323 is one segment scope, and the pattern is what generalises

The destination rule gains `git push[^|;&]*`, matching the comment its neighbour already carries. The
`(^|` alternative is **deleted, not left unused**: under segment scoping a command beginning with
`main` is unreachable, and dead pattern reads as coverage.

This is the **third recorded instance of fixing a boundary in one rule and not its sibling** —
ADR-0074 on `agent-command-scope.sh` R1, ADR-0079 on R2, this. The rule now says so at the site:
*if you add a fourth rule here, scope it to the segment too.*

## What the plant registry found, twice

**Six of fifteen plants did not fire on the first run, and five shared one cause: they were negative
assertions.** `F6`, `O5`, `G2`, `G3` and `S2` assert something must *not* happen — a command must not
be refused, a live run must not be told to disarm, a bare `touch` must be gone. **Deleting the
mechanism leaves every one of them trivially satisfied.** The mutation has to invert the condition
(`!=` → `=`) or reintroduce the banned thing. Recorded in the test file, because the next author will
write a negative assertion and copy a deletion-shaped plant.

**`O5` survived that fix and needed the ADR-0090 rule applied literally.** Its replacement was
`echo "..." >&2 exit 0`, which matched exactly one site and passed `PC2`'s well-formedness check —
and did something else entirely. **A replacement cannot contain a newline**, so collapsed onto one
line `exit 0` becomes two *arguments* to `echo`; no exit happened, control fell through to the next
branch, and that branch still exits 2, so the assertion went on passing. Reproduced by hand with a
real newline, the assertion failed correctly. `PC2` cannot see this class at all: the needle matched
once, the mutation was simply not the mutation it described.

`F3` and `F6` are pinned by the **same** mutation, recorded rather than papered over: both are cases
of one property, and the only mutation that breaks `F6` is the whole-command revert that also breaks
`F3`. `F6` earns its place as a case, not as independent evidence.

## Consequences

- **The guard denies strictly less than it did**, on one rule, in the direction the probe table pins.
  Every genuine push-to-main form is asserted to still halt, and `phase1.test.sh`'s 30 existing
  assertions cover `run_halt_checks`, which this does not touch.
- **A new hard dependency at recovery time.** `nightly-disarm.sh` reaches `~/.claude` only through
  its new `PAIRS` entry; before sync, the RUNBOOK names a command that does not exist. The irony is
  noted — an instruction whose remedy names no runnable command is the defect ADR-0109 closed.
- **This ships an instruction for the arming half.** Nothing enforces that §3.1's marker is written
  in the new format; a run that writes a bare `touch` still arms the guard and simply cannot be
  attributed. That is why the legacy path is a first-class tested state rather than an afterthought.
- The disarm is **destructive by design** — it removes six files. It is bounded to the transient
  set, never touches `docs/manifests/`, the working tree, or any commit, and reports every removal.

## Recorded, not fixed

- **Nothing detects a stale marker proactively.** A human still has to be blocked once before they
  learn the command exists. A `SessionStart` check that reported an armed marker with a foreign owner
  would close that, and it is a different feature with its own noise budget.
- **`is_forbidden_publish` is still a substring matcher over a command string**, not a parser. It
  cannot see through `eval`, a variable holding the branch name, or a script that pushes. Same threat
  model ADR-0045 states for `agent-command-scope.sh`: a guardrail against a shortcut, not a sandbox.
- This repository's own `.claude/nightly-state/` still holds `build-status` and `started-at` from the
  2026-07-31 run. Running the disarm here is the end-to-end check, and clearing that debris is a real
  outcome rather than a fixture.
