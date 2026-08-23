# SPEC — autopilot-disarm clears the run scope, so a relaunch after a pause is silently unbounded

**Topic slug:** 400-autopilot-disarm-scope-unbounded

## Objective

`autopilot-disarm.sh` clears the whole transient guard-state set — `active`, `build-status`, and
`scope` — as one operation. `active` and `build-status` are genuinely transient guard markers
(ADR-0112): a build left `RED` must halt `--check` regardless of the marker, so clearing them on
disarm is correct. `scope` is different: it holds the run's *configuration* (the resolved
`--features`/`--only` bound), not a guard condition, and ADR-0129 placed it in the same directory
after ADR-0112 had already defined "disarm clears everything in this directory" — without anyone
revisiting whether that rule should still apply to the new file.

The consequence: a human pauses a bounded autopilot run, disarms it (correctly, to stop safely),
then relaunches with `/skill autopilot`. Nothing — not the disarm output, not the RUNBOOK's
"Aborting a run" section, not the skill itself — tells them the bound is gone. The relaunch runs
unbounded over the entire pending roadmap.

This SPEC fixes that by moving `scope` (and `published`, which has the same exposure — it counts
delivered progress, not a guard condition) out of the set the disarm clears, so a relaunch reuses
the same bound by construction, with no message to read and no step to remember.

## Scope

**In scope:**
- `autopilot-disarm.sh`: stop clearing `scope` and `published`; update its printed output to
  reflect what it actually does (`removed:` only for `active`/`build-status`; a new line stating
  `scope` and `published` are preserved, naming the bound and the file paths).
- The consumer(s) of `scope` at launch time (the entry point(s) that read `--features`/`--only` and
  the file — at minimum Phase 0 check 9 and `conductor-scope-gate`, per the issue's own "what to
  measure" list): confirm/implement that an explicit `--features`/`--only` argument at relaunch
  always overrides a surviving `scope` file, and that a relaunch with no argument reuses the
  surviving file as the bound.
- Corrupt/unreadable `scope` file handling at read time: fail-safe to unbounded, with an explicit
  warning — never a silent unbounded run, never a halt.
- RUNBOOK "Aborting a run" section: state plainly that `scope` (and `published`) survive disarm,
  and how to override them (pass `--features`/`--only` again).
- ADR recording the decision: `scope`/`published` move out of the transient set, `active`/
  `build-status` keep the current whole-clear behaviour unchanged (R-03), and the reasoning for
  treating configuration/progress data differently from guard state.

**Out of scope:**
- Any change to `active`/`build-status` semantics or to when a build-status `RED` halts a
  `--check` — ADR-0112's behaviour for those two files is preserved exactly (R-03).
- A dedicated `--clear-scope` command — explicit `--features`/`--only` at relaunch is the
  overwrite mechanism; no new command surface.
- Migrating `scope`/`published` to a new directory — they stay at their current paths inside
  `.claude/autopilot-state/`; only `autopilot-disarm.sh`'s clear list changes.
- Any other file in `.claude/autopilot-state/` not named above.

## Stack

Bash 3.2-clean (macOS default `/bin/bash`), consistent with every other script in
`staging/plugin/scripts/`. No new language or runtime dependency.

## Architecture

- `autopilot-disarm.sh` currently treats `.claude/autopilot-state/` as one undifferentiated
  transient set and removes every file in it. This SPEC introduces a second category inside the
  same directory: **configuration/progress files** (`scope`, `published`) that disarm does not
  touch, versus **guard-state files** (`active`, `build-status`) that it still clears
  unconditionally.
- The disarm output changes shape: it still lists `removed:` entries for the guard-state files,
  and adds a `preserved:` block naming each surviving file and, for `scope`, the bound it encodes
  (e.g. `preserved: .claude/autopilot-state/scope (--features 458,398,482)`).
- At relaunch, the entry point that resolves the effective bound reads: explicit
  `--features`/`--only` on the command line (if given) → wins outright, overwriting the file.
  Otherwise → read the surviving `scope` file, if present and parseable, as the bound. Otherwise
  (file absent, or present but unreadable/malformed) → unbounded, with a warning printed in the
  malformed case only (an absent file is the ordinary "never had a bound" case and needs no
  warning).
- `published` follows the file-preservation rule but has no read-time consumer logic to change
  beyond "disarm no longer deletes it" — it is a counter, not a bound, and this SPEC does not add
  new behaviour around it beyond ceasing to clear it.

## Data model

No new files. Existing `.claude/autopilot-state/scope` and `.claude/autopilot-state/published`
keep their current format; only their lifecycle (what deletes them) changes.

## API / CLI surface

- `autopilot-disarm.sh`: same invocation, changed output text, changed set of files removed.
- The autopilot launch path (skill / entry script covering Phase 0 check 9 and
  `conductor-scope-gate`): unchanged CLI surface (`--features`, `--only` unchanged); changed
  internal precedence — explicit arg overrides file, absent arg reads file if present and valid.

## UI flows

N/A — CLI/skill only, no graphical UI. The "flow" is: pause → disarm → (read disarm output,
optional) → relaunch with or without `--features`/`--only`.

## Edge cases

- **First-ever run, no `scope` file exists at all:** unchanged — unbounded, no warning (today's
  behaviour when there is genuinely nothing to bound to).
- **`scope` file survives disarm, relaunch passes no `--features`/`--only`:** reuse the file's
  bound. Not silent — the launch path states which bound it is applying (from the preserved
  file), so the operator can see what they are about to run without having read the disarm output
  earlier.
- **`scope` file survives disarm, relaunch passes `--features`/`--only` explicitly:** the explicit
  argument wins; the file is overwritten with the new bound.
- **`scope` file present but corrupted/unreadable at relaunch:** fail-safe to unbounded, with an
  explicit warning naming the file and stating it could not be read — never a silent unbounded
  run and never a halt (issue's own R-01 wording: a bound loss must always be announced, whichever
  form it takes).
- **`published` present:** disarm preserves it unconditionally; no read-time branching added.
- **A run that was never bounded (no `--features`/`--only` at the original launch) gets
  disarmed:** no `scope` file exists to preserve; behaviour is unchanged (still nothing to
  preserve, still unbounded on relaunch, exactly as today).

## Success criteria

- [ ] R-01 — a disarm that clears a bound says so, naming the bound it cleared and the exact
      relaunch command that restores it. (Satisfied by construction under R-02's chosen fork:
      `scope` is no longer cleared, so there is no bound-loss to announce in the normal case; the
      disarm output instead states which bound is *preserved*. The corrupted-file edge case still
      needs an explicit, visible warning at relaunch time — that is where "a bound was lost" can
      still genuinely happen.)
- [ ] R-02 — `scope` (and `published`, same exposure) move out of the transient set that
      `autopilot-disarm.sh` clears; the reason is recorded in the ADR: they are run
      configuration/progress data, not guard state, and `active`/`build-status` are the ones
      ADR-0112 defined the whole-clear behaviour for.
- [ ] R-03 — `autopilot-disarm.sh`'s clearing of `active` and `build-status` is byte-for-byte
      unchanged: same files removed, same output lines for those two, same
      `--check`-halts-on-RED behaviour from ADR-0112. This must not become a partial disarm of
      those two.
- [ ] R-04 — the RUNBOOK's "Aborting a run" section states plainly, after this fix, that `scope`
      (and `published`) survive disarm, that a relaunch with no `--features`/`--only` reuses the
      preserved bound, and that passing `--features`/`--only` again overrides it.
- [ ] R-05 — an explicit `--features`/`--only` argument at relaunch always overwrites a surviving
      `scope` file with the new bound; never merges, never appends.
- [ ] R-06 — a corrupted or unreadable `scope` file at relaunch fails safe to an unbounded run
      with an explicit, visible warning naming the file — never a silent unbounded run, never a
      halt.
- [ ] R-07 — every consumer of `scope` in the codebase is accounted for (at minimum Phase 0 check
      9 and `conductor-scope-gate`, per the issue's own "what to measure" list); each either reads
      the preserved-file/explicit-arg precedence correctly or is confirmed out of scope with a
      one-line reason. (no-test: this is a codebase inventory/audit step verified by reading the
      implementation, not something a single assertion can check)
- [ ] R-08 — the disarm output for a run that had a bound no longer prints `removed:` for
      `scope`/`published`; it prints `preserved: <path> (<bound>)` for each instead.
