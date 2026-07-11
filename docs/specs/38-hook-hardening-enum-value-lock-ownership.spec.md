# SPEC — Hook hardening: enum value, lock ownership, trust hash

Source: GitHub issue #38

## Objectives
1. Replace the out-of-enum `permissionDecision:"block"` with `deny` before a strictly validating Claude Code update turns the coder gate fail-open (audit finding 3.24).
2. Fix lock ownership in chain-memory-capture.sh so a timeout never releases another process's lock (finding 3.25).
3. Harden approve-test-cmd.sh hashing, retire the dead backup-before-deploy.sh, and emit dual-form JSON from prompt-en-prose-detect.sh (findings 3.26–3.28).

## Scope
In (hooks vendored into `staging/plugin/scripts/` by issue #28):
- `pre-flight-pattern-enforce.sh:152` (and fallback on 153): emits `permissionDecision:"block"`, outside the enum ADR-0009 documents as verified (allow, deny, ask, defer). Change block to deny and update the two greps in the pattern-enforce test.
- `chain-memory-capture.sh:147-150`: on lock-acquisition timeout the hook proceeds without the lock AND its EXIT trap removes a lock directory it never acquired. Track ownership: set the trap only after mkdir succeeds; on timeout, skip the event rather than proceed unlocked.
- `approve-test-cmd.sh:26`: ROOT is lowercased before hashing; on a case-sensitive volume the shasum input path does not exist, H comes back empty without aborting, and a hash-less trust line is written while the stop-gate test gate goes silently inert. Hash the pre-normalization path and abort with an error if the hash is empty before writing the trust line.
- `backup-before-deploy.sh`: wired to no hook event, body is a hardcoded one-shot backup from 2026-05-19, yet ADR-0005 line 201 and the blueprint (about line 1419) list it as active. Retire: exclude from vendoring, note the deployed-side deletion in the sync checklist, correct the two doc references (keep blueprint changelog conventions).
- `prompt-en-prose-detect.sh:42` (PLAUSIBLE): emits `additionalContext` as a top-level JSON key instead of the documented hookSpecificOutput envelope. Emit BOTH forms in one JSON object (top-level key plus the envelope) — safe under both interpretations, no runtime probe needed.

Out:
- Any file under `~/.claude` (deployed-side deletion of backup-before-deploy.sh is a sync-checklist note, not an action here).
- Hook wiring changes in settings.json.

## Stack
Bash 3.2-compatible shell hooks, JSON hook-output contracts (ADR-0009), Markdown docs (ADR-0005, blueprint), harness tests in docs-ci.

## Architecture
Four hook scripts under `staging/plugin/scripts/`, their tests, plus two doc references (ADR-0005 line 201, blueprint ~line 1419) and the sync checklist.

## Data model
None.

## API / Interfaces
Hook JSON contracts: `permissionDecision` limited to the verified enum; prose-detect emits both the top-level `additionalContext` key and the hookSpecificOutput envelope in one object.

## UI flows
None.

## Edge cases
- Strictly validating CC update: deny is in-enum, gate stays fail-closed.
- Lock timeout with a foreign lock present: foreign lock left in place, event skipped.
- Case-sensitive volume: hash computed on the pre-normalization path; empty hash aborts before writing the trust line.
- Either JSON parser (top-level or envelope): the prose-detect reminder survives.

## Success criteria
- [x] Harness tests cover: deny emission, lock timeout leaves the foreign lock in place, approve-test-cmd aborts on empty hash, prose-detect output parses and carries both keys
- [x] No documentation still lists backup-before-deploy.sh as an active hook
- [x] Scripts stay bash 3.2 clean
- [x] No file under `~/.claude` modified
