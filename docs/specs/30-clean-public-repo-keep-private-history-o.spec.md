# SPEC — clean-public-repo: keep private history out of the public branch

Source: GitHub issue #30

## Objectives
1. Stop prepare mode from staging the private-history backup tarball into the branch destined for the public repo (audit finding 1.2, P1).
2. Make surgical-rewrite's rollback story truthful: the tar is the sole rollback; verification and push instructions must work (finding 2.7).
3. Fix detect-tool-traces SHA matching so findings carry correct commit SHAs with abbreviated hashes of 8+ chars (finding 3.12).

## Scope
In (paths relative to `staging/plugin/skills/clean-public-repo/`, vendored by issue #28):
- `scripts/fresh-history-publish.sh` (line 133 area): backup tarball `.git-backup-<TS>.tar.gz` currently created INSIDE the work tree (line 105) then swept up by `git add -A` on the orphan branch. Create it OUTSIDE the work tree; prepare mode must hard-fail if any `.git-backup-*` path is staged before printing the HITL instructions. Mirror the change in SKILL.md lines 249–262.
- `scripts/surgical-rewrite.sh` (line 185 area): git-filter-repo rewrites ALL refs including `pre-rewrite-backup-<TS>` and deletes the origin remote; the `git diff <backup> --stat` verification (line 219) always prints nothing; the suggested push (line 226) fails. Document the tar as the sole rollback, base verification on the tar or on filter-repo's commit-map, re-add the origin remote in the push instructions, write the tar outside ROOT. Refresh the stale claim at SKILL.md line 355 that git-filter-repo is installed.
- `scripts/detect-tool-traces.sh:198`: SHA matched as exactly 7 hex chars plus space; match 7–40 hex chars, or switch to a sentinel log format.

Out:
- Any file under `~/.claude` (edits land in staging only).
- Behavioral changes beyond the three findings.

## Stack
Bash 3.2-compatible, BSD-safe shell scripts; Markdown SKILL.md; harness tests under the skill's tests directory run by docs-ci.

## Architecture
Three scripts plus SKILL.md inside `staging/plugin/skills/clean-public-repo/`. Harness tests build fixture repos to assert the new behavior.

## Data model
None.

## API / Interfaces
Script CLI contracts unchanged; prepare mode gains a hard-fail path when `.git-backup-*` is staged.

## UI flows
None (HITL instructions printed by prepare mode are updated to match the new tarball location).

## Edge cases
- Repos with `core.abbrev=8` (or auto-abbreviated 8+ char `%h`): findings must carry the correct SHA.
- A `.git-backup-*` path staged by any means before the HITL instructions: prepare mode must hard-fail, not proceed.
- filter-repo rewriting the backup branch: verification must not rely on the rewritten branch.
- Missing origin remote after filter-repo: push instructions must re-add it.

## Success criteria
- [ ] A harness test builds a fixture repo, runs prepare mode, and asserts no `.git-backup-*` path is staged and the tarball lives outside the work tree
- [ ] A harness test with `core.abbrev=8` asserts findings carry the correct SHA
- [ ] Scripts stay bash 3.2 clean and BSD safe
- [ ] No file under `~/.claude` modified; edits land in staging only
