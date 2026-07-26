# SPEC — Recovery-readiness pre-flight for concept-to-code Step 5

Source: GitHub issue #104

## Objectives
1. Refuse to dispatch coders until the work is recoverable.
2. Record the recovery baseline so a later step can name the rollback target.

## Scope
In: a pre-dispatch assertion block at the top of c2c Step 5; an additive manifest field for the baseline sha; a new test file in both CI registries.
Out: automatic stashing; automatic branch creation.

## Stack
Markdown skill instructions plus bash 3.2, copying the pattern already used at `deep-refactor/SKILL.md:118` (baseline commit hash) and `:173` (dirty-tree check) rather than inventing a second idiom.

## Architecture
- Modified: `concept-to-code/SKILL.md` Step 5, new pre-dispatch block.
- Modified: `manifest-init.sh` / the manifest schema — additive `recovery_baseline_sha`.
- Modified: `manifest-validate.sh` — a conditional invariant so pre-existing manifests stay valid.
- New: test file in both CI registries.

## Data model
`recovery_baseline_sha: <40-hex|null>` in the manifest. Additive, nullable.

## API / Interfaces
Assertions, in order: working tree clean or explicitly stashed; current branch is not the default branch; HEAD sha resolvable and recorded. Failure prints the exact remediation command and refuses dispatch.

## UI flows
None. In autopilot the refusal is recorded and halts the feature — autopilot bypasses human prompts, not safety checks.

## Edge cases
- A detached HEAD must be treated as a failure with a clear reason.
- A repo with no commits yet has no HEAD to record — fail with a named reason.
- The check must run before any dispatch, including on the Workflow path.
- Autopilot must not be able to skip it.

## Success criteria
- [ ] A dirty tree refuses dispatch with a named remediation command.
- [ ] Being on the default branch refuses dispatch.
- [ ] A clean feature branch dispatches and the manifest carries the baseline sha.
- [ ] Autopilot mode still honours the refusal.
- [ ] A manifest without the field still validates.
- [ ] The new test file is registered in BOTH CI registries.
