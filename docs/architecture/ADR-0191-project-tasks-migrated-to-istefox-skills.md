# ADR-0191 — `project-tasks` is retired from this repo's vendored surface; canonical source moved to `istefox/Skills`

- **Status:** Accepted
- **Date:** 2026-09-04
- **Supersedes:** ADR-0153 (`project-tasks` vendored as a chain member, `deployed-only` waiver
  removed). **Related:** ADR-0087 (`deployed-only` registry, the waiver this restores),
  ADR-0024 §3.4 (staging expected to run ahead of deployed until `--apply`), ADR-0187 (the
  Codex-review-gate deploy that surfaced this while auditing `staging/sync-to-claude.sh`'s dry run).

## Context

A dry run of `staging/sync-to-claude.sh`, done while checking whether ADR-0187's Codex review gate
was actually deployed, reported `project-tasks` as one of the files that would change — in the wrong
direction. Measured, not assumed (rule 13):

- `~/.claude/skills/project-tasks` is, today, a **symlink** to `/Users/stefer/Developer/Skills/tasks`
  (`readlink` confirms it), not a directory this repo's `sync-to-claude.sh --apply` ever wrote.
- `/Users/stefer/Developer/Skills` is its own git repository, remote
  `https://github.com/istefox/Skills.git`, with an active PR history reaching the day this ADR is
  written: `Merge pull request #13 ... chore(project-tasks): close SK-007, bump auto-learning
  pointer`, and four more merged PRs before it closing `SK-004` through `SK-013` — the same ledger
  ids this repo's stale copy of `scan.sh`/`ledger-merge.sh` still refers to in its own comments.
- This repo's `staging/plugin/skills/project-tasks/*` (9 files: `SKILL.md`, four scripts, three
  reference docs, one template) is the **pre-migration** copy ADR-0153 vendored on 2026-08-17. It
  has not moved since; the live `chain-integration.md` (edited directly, outside this repo) already
  documents the symlink install (`ln -s /Users/stefer/Developer/Skills/tasks
  ~/.claude/skills/project-tasks`) and states the reason a copy-based deploy was rejected: *"a `cp
  -R` diverges the moment either side changes and nothing detects the drift, which is exactly what
  happened before this line was rewritten — the live copy sat six days stale behind a merged PR with
  no error anywhere."*
- No ADR, no `chain-decisions.md` narrative, and no `sync-to-claude.sh` edit recorded this move in
  this repository. It happened entirely on the live side and in the destination repo.

The result: `sync-to-claude.sh`'s 9 PAIRS lines for `project-tasks` point at a fork nobody has
touched in this repo since the migration, and a plain `--apply` would try to overwrite the live
symlink's target — a different repository's actively-maintained files — with that stale fork.

This is not a new decision so much as a **ratification** of one already made and shipped live: the
skill now has one real home (`istefox/Skills`), it is versioned there with its own PRs, and this
repo's copy is dead weight that a rule-6 test (extract only when two copies answering the same
question would be a defect) says should never have been allowed to keep existing unsynced.

## Decision

**Restore the `deployed-only: project-tasks` waiver** in `staging/sync-to-claude.sh`'s declared-
waivers block (ADR-0087's registry), alphabetically between `daily-open` and `vibiso-intake`, same
class as the existing `auto-learning`/`website-auditor` entries: *"symlink into a foreign repository
... carrying its own git remote and history; vendoring it would duplicate a project that is already
versioned elsewhere."* `project-tasks`'s reason names the specific target
(`Developer/Skills/tasks`, `github.com/istefox/Skills`) and this ADR.

**Remove the 9 PAIRS lines** for `project-tasks` from `sync-to-claude.sh` — the same batch-together
requirement ADR-0153 §D6 stated for the opposite move (vendoring the waiver's removal), applied in
reverse: a batch that removes PAIRS without restoring the waiver, or vice versa, leaves
`pairs-completeness.test.sh`'s DO2 correctly red on a stale waiver or a stale PAIRS set for one
release.

**Delete the stale vendored tree** (`staging/plugin/skills/project-tasks/*`, 9 files) via `git rm`,
not overwritten or archived — the real, current files live in `istefox/Skills` and diverging further
serves no reader.

**Delete `staging/plugin/scripts/tests/project-tasks-ledger.test.sh`** (ADR-0153 §D7's dedicated
30-assertion harness) and its entry in `.github/workflows/docs-ci.yml`'s `shell-tests` list — the
harness exercised the vendored scripts directly; with no vendored scripts left in this repo, there
is nothing left for it to run against.

**What this repo keeps no opinion on:** whether `istefox/Skills` itself has adequate tests, ADRs or
review discipline for `project-tasks` going forward. That repository is now the one place those
questions are answered; this repo's job is only to stop claiming a copy it does not maintain.

## Consequences

### Positive

- `sync-to-claude.sh`'s dry run stops reporting a false regression on `project-tasks` — the next
  `--apply` (carrying ADR-0187's Codex review gate) no longer risks overwriting the live symlink's
  target with dead code.
- The `deployed-only` registry again correctly states which skills this repo does not own the
  source for, closing the gap ADR-0153 itself flagged as a risk in its own D6 if the two edits (waive
  + vendor) were ever separated — here applied to the reverse transition.
- One less stale fork to read past when auditing this repo's `staging/` tree.

### Negative

- ADR-0153's `scan.sh`/`ledger-merge.sh` design work (the bilateral GitHub ledger, the byte-
  identical-outside-three-regions filter contract, the `runs:`-as-derivation idempotency) is no
  longer reviewable from this repository. Anyone auditing that design now has to clone
  `istefox/Skills` — a real cost, accepted because the alternative (two repos both claiming to be
  canonical) is worse.
- This ADR cannot state exactly when the migration happened or why it was not recorded here at the
  time — only that it is complete and irreversible-in-practice given the target repo's independent
  PR history. The gap in this repo's own record between ADR-0153 and this ADR is real and is not
  backfilled.

### Neutral

- The `deployed-only` registry count returns to 7 (was 6 after ADR-0153 dropped it to 5, then rose to
  6 with `agent-registry`-class additions since — re-measured, not assumed, at edit time). DO1's
  floor (`>= 5`) is unaffected either way.
- `TODO.md`'s own ledger entries referencing `SK-0NN` ids are untouched by this ADR — they describe
  work now tracked in the other repo, not a claim this repo makes about its own tree.

## Verification

- `bash -n staging/sync-to-claude.sh` clean after the PAIRS/waiver edit.
- `pairs-completeness.test.sh` DO1-DO4 green: DO2 in particular confirms `project-tasks` is declared
  deployed-only and genuinely absent from `staging/plugin/skills/`.
- `bash staging/sync-to-claude.sh` (dry run) no longer reports any `project-tasks/*` or
  `rules/tools.md` target.
- `grep -rn "project-tasks-ledger" .github/ staging/` matches only this ADR's and
  `chain-decision-index.md`'s prose, not an executable list.

## References

- `staging/sync-to-claude.sh` — PAIRS removal, waiver restored
- `staging/plugin/skills/project-tasks/*` — deleted (was: ADR-0153's vendored tree)
- `staging/plugin/scripts/tests/project-tasks-ledger.test.sh` — deleted
- `.github/workflows/docs-ci.yml` — `shell-tests` list entry removed
- `docs/architecture/ADR-0153-project-tasks-vendored-bilateral-ledger.md` — superseded
- `docs/architecture/ADR-0087-222-deployed-only-skills.md` — the registry this restores an entry to
- `/Users/stefer/Developer/Skills/tasks` — the canonical source as of this ADR (`istefox/Skills`)
