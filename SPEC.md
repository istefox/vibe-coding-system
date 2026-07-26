# SPEC — Context-occupancy instrumentation and PreCompact guard

Source: GitHub issue #112

## Objectives
1. Stop auto-compaction from firing in the middle of a chain step.
2. Make context occupancy visible.

## Scope
In: a `PreCompact` hook; an occupancy line in the Stop hint; a blueprint note recording the 50% finding; a new test file in both CI registries.
Out: changing the autocompact threshold; per-subagent occupancy, which is not locally observable (`usage-report.py:11-14`).

## Stack
Bash 3.2 hook + the existing `usage-daily-hint.sh`.

## Architecture
- New: `staging/plugin/scripts/pre-compact-guard.sh`, wired on `PreCompact`. The event is currently absent from the hooks block in `staging/user/settings.json` entirely.
- Modified: `usage-daily-hint.sh` — add occupancy alongside the daily usage line.
- Modified: the blueprint hooks section — record that the documented instruction violation occurred at 50% occupancy, below the configured 70% override, so the setting is a conscious choice rather than an inherited default.
- New: test file in both CI registries.

## Data model
None persisted beyond the existing state directory.

## API / Interfaces
The guard refuses to compact while a manifest's `current_step` is in a dispatch state and emits the handoff instruction first. It **fails open** on any internal error, like every other hook here — a wrongly-firing refusal would strand a session.

## UI flows
The refusal message instructs the externalisation sequence before compaction.

## Edge cases
- No manifest mid-flight → allow, exit 0.
- Malformed manifest → allow (fail open).
- Repeated refusal must not loop forever: refuse once, then allow.
- The hook must be inert in repos with no manifests.

## Success criteria
- [ ] With no manifest mid-flight, `PreCompact` allows and exits 0.
- [ ] With a manifest at a dispatch step, compaction is refused once and the handoff instruction is emitted.
- [ ] Any internal error allows.
- [ ] The Stop hint reports occupancy.
- [ ] The new test file is registered in BOTH CI registries.
