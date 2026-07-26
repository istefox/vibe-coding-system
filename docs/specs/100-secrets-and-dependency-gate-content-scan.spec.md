# SPEC — Secrets and dependency gate: content scan, lockfile check, CI steps

Source: GitHub issue #100

## Objectives
1. Detect secrets by file **content**, not only by filename, before a commit is created.
2. Detect a newly added dependency that no plan or ADR authorised.
3. Make both checks runnable in a target project's CI with no agent present.

## Scope
In: a new content-scan script under `staging/plugin/scripts/`; a lockfile/dependency-diff check; wiring both into the `commit` skill Step 1; adding both as steps in `staging/project-templates/ci/ci.yml`; a new test file registered in both CI registries.
Out: rotating or managing real secrets; integrating a paid or hosted scanner; changing `protect-files.sh`, whose filename-based write block stays as it is.

## Stack
Bash 3.2 (macOS-portable, no assoc arrays, no `mapfile`, no `${v^^}`, no process substitution), consistent with every other script in `staging/plugin/scripts/`. Tests are `*.test.sh` harnesses, offline and hermetic.

## Architecture
- New: `staging/plugin/scripts/secret-scan.sh` — reads a file list or a diff, emits findings as `SECRET<TAB><file>:<line><TAB><rule>`; exit 0 always (reporter), caller decides.
- New: `staging/plugin/scripts/dependency-scan.sh` — compares dependency manifests/lockfiles in the diff against the authorised package list supplied by the caller.
- Modified: `staging/plugin/skills/commit/SKILL.md` Step 1, where the filename-based secrets check already runs over `staged ∪ tracked_modified ∪ untracked` (`commit/SKILL.md:70`).
- Modified: `staging/project-templates/ci/ci.yml`.
- New: `staging/plugin/scripts/tests/secrets-dep-gate.test.sh`, registered in `.github/workflows/ci.yml` (glob) and `.github/workflows/docs-ci.yml` (explicit list).

## Data model
None. Findings are TAB-separated lines on stdout.

## API / Interfaces
- `secret-scan.sh [--files <list-file> | --diff]` → `SECRET` lines or nothing.
- `dependency-scan.sh --diff [--allow <file>]` → `NEWDEP<TAB><package><TAB><manifest>` lines or nothing.
- Both are reporters: exit 0 even when they find something, matching the `weakening-scan.sh` contract already established in this repo.

## UI flows
The `commit` skill Step 4 approval gate renders any finding before the human clicks. A `SECRET` finding stops the commit per the existing invariant guardrail ("NEVER commit .env, secrets, API keys").

## Edge cases
- Base64 test fixtures and SHA digests already present in this repo's tests must not trigger — they are the documented false-positive corpus.
- A file matching the filename rule AND containing a key must be reported once, not twice.
- A lockfile reordered with no added packages must produce no `NEWDEP`.
- Binary files must be skipped, not scanned.
- No dependency manifest in the repo means the dependency check is inert.

## Success criteria
- [ ] A fixture containing a fake AWS secret key is detected and blocks the commit.
- [ ] A file caught only by the existing filename rule is still caught by that rule.
- [ ] The false-positive corpus (base64 fixtures, SHA hashes in existing tests) produces no finding.
- [ ] A lockfile gaining an unauthorised package produces a `NEWDEP` line naming it.
- [ ] The ci template carries both steps and they run standalone from a plain shell.
- [ ] `commit` skill invariant guardrails are unchanged.
- [ ] Every new assertion has been seen RED before being made green.
- [ ] The new test file is registered in BOTH CI registries.
