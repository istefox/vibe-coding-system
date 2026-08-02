# ADR-0116 — the posture check told the operator no prompt would fire, and for one of its two accepted modes that was false

- **Status:** Accepted
- **Date:** 2026-08-02
- **Issue:** #339 (`chain-blocker`)
- **Amends:** ADR-0110 (issue #320), whose "known consequences" recorded this as *unmeasured*.

## Context

ADR-0110 built `permission-mode-state.sh` because `nightly-autopilot` stated its first launch
precondition in prose and verified it nowhere. The classifier accepts two modes as `NONBLOCKING`:
`acceptEdits` and `bypassPermissions`. Every caller then printed **one** message for both:

```
✓ permission posture: acceptEdits — no per-tool prompt will fire.
```

**That is true of `bypassPermissions` and false of `acceptEdits`.** ADR-0110 itself named the gap —
*"whether `acceptEdits` is sufficient is unmeasured — Bash outside the allowlist still prompts, so
a green posture check is not 'no prompt is possible'"* — and then the operator-facing text went on
asserting the opposite.

**Found by the operator, not by the harness.** Cycling this session to `acceptEdits` and running the
chain: every Bash command outside `permissions.allow` raised a prompt.

## What was measured

**M1 — insufficient in concrete, not in principle.** This machine's `permissions.allow` holds
**16** Bash entries: `git status`, `git diff*`, `git log*`, `git add*`, `git commit*`,
`pip install*`, `pytest*`, `python3 -m pytest*`, `ruff*`, `black*`, `mypy*`, `npm run*`,
`npm test*`, `rg*`, `fd*`, `gh issue *`. The chain's own Bash surface — `bash
~/.claude/skills/*/scripts/manifest-*.sh`, `sed`, `awk`, `mkdir`, `cp`, `git push`, `gh pr create`,
the project's `test-cmd` — is **not among them**. So on the machine this system runs on,
`acceptEdits` cannot carry an unattended run.

**M2 — six sites, and the ordering is as much the defect as the wording.**

| file | what it said |
|---|---|
| `nightly-autopilot/SKILL.md` :37 | *"(`acceptEdits` or bypass) so no per-tool prompt fires"* |
| :42 | `claude --permission-mode acceptEdits` — the only launch example |
| :86 | `✓ … no per-tool prompt will fire` |
| :93 | remedy names `acceptEdits`; `bypassPermissions` appears nowhere in it |
| `autopilot-build/SKILL.md` :111 | the same success message |
| :117 | the same remedy, `acceptEdits` only |

An operator following the instruction lands on the mode that does not work.

**M3 — a second wrong instruction in the same paragraph, already known wrong.**
`docs/RUNBOOK-nightly-autopilot.md:74` still read `/permissions   # choose acceptEdits`. ADR-0110
established against the CC 2.1.220 binary that `/permissions` does **not** set the mode, and
`nightly-autopilot/SKILL.md:38` says so in terms. The correction never reached the RUNBOOK — which
is the document a human actually opens at launch.

## Decision

### D1 — `acceptEdits` stays `NONBLOCKING`; the MESSAGE changes

Demoting it was considered and rejected. A repository whose `permissions.allow` genuinely covers its
chain's Bash surface makes `acceptEdits` sufficient, and deciding that is the **caller's** job:
`manifest-field-state.sh`'s sibling rule applies here too — the reporter reports, the caller
decides (ADR-0076 §D2). Narrowing the value domain would move a policy into a script whose whole
design is to hold none.

What the caller owes the operator is a message that **distinguishes** the two. Both pre-flights now
branch inside `NONBLOCKING`:

- `bypassPermissions` → *"no per-tool prompt can fire"*.
- `acceptEdits` → *"edits are auto-accepted, but a Bash command outside `permissions.allow` STILL
  PROMPTS, and there is nobody to answer it"*, proceeding on the stated assumption that the operator
  has checked their allowlist.

### D2 — every remedy names `bypassPermissions` first

Launch order, `BLOCKING` remedy, `UNCLASSIFIED` remedy, and the RUNBOOK. `acceptEdits` is still
offered, described by what it actually guarantees rather than by what one wishes it did.

**The Shift+Tab press-count is removed.** The old text said *"from `auto`, two presses"*, which
lands on `acceptEdits` — the wrong mode, stated as a recipe. Counting presses is also a claim about
a cycle order this repository has never verified. The instruction is now to read the mode off the
status line.

### D3 — the safety argument is written where the decision is made

`bypassPermissions` removes the prompt layer and nothing else. `stop-gate`,
`pre-flight-pattern-enforce`, `protect-files`, `db-backup-guardrail`, `write-scope-enforce`,
`agent-write-scope`, `agent-command-scope` and `nightly-guard` all still fire, and a hook deny
overrides any permission mode. That is ADR-0022's stated design — *autopilot bypasses the
human-decision layer, never the safety layer* — and it belongs next to the instruction telling
someone to turn the prompts off, not three documents away.

### D4 — the guard is derived, and `docs/architecture/` is out of its population

Section `PMQ` of `permission-mode-state.test.sh`, over `staging/plugin/skills/*/SKILL.md`,
`staging/plugin/skills/*/scripts/*.sh` and `docs/RUNBOOK-*.md` (73 files, count-guarded):
**every line claiming no per-tool prompt must name `bypassPermissions` on that same line.** A
seventh site added with the old wording fails.

`ADR-0022:179` still carries the old phrasing and stays **byte-unchanged** (ADR-0034 precedent: a
historical ADR records its moment). It gains a dated `## Correction` instead. The guard is about
**living instructions** — what an operator reads at launch time.

## The registry's second boundary, found the same day as its first

`PMQ3` asserts the RUNBOOK. Its plant could not be declared: `plant-check.sh` resolves every target
under `staging/`, so a claim living in `docs/` was **unplantable by construction** — even though the
sandbox has copied `docs/` all along, precisely so tests could read it.

`plant-check.sh` now accepts a literal `../docs/` prefix, refusing any other `..` and any `..`
inside the remainder, so the widening cannot walk out of the sandbox. Together with `PC4` (ADR-0115,
found hours earlier) that is two boundaries of the registry closed in one day, both of the same
shape: *a plant that cannot exist looks exactly like a file that needs none.*

## Consequences

- **The pre-flight now passes on the same inputs and says something different on one of them.** No
  run is newly blocked; an operator in `acceptEdits` is newly told what they are actually getting.
- **It is still an instruction, not an enforcement.** Nothing verifies that a given repo's
  `permissions.allow` covers its chain's Bash surface. Building that check means enumerating the
  chain's Bash surface, which is prose spread over several SKILL.md files — a real feature, not a
  line. Named here rather than half-built.
- **The `acceptEdits` branch proceeds.** It warns and continues, because refusing it would demote
  the mode by the back door after D1 decided not to.
- `dontAsk` is still `UNCLASSIFIED` and still refused (ADR-0110 §D4, untouched).
- The RUNBOOK now names a mode this repository has not yet run a full night in. The first launch is
  the measurement.
