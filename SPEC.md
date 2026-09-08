# SPEC — Migrate deep-refactor out of vendored PAIRS surface

**Topic slug:** migrate-deep-refactor-out-of-vendored-pa

## Objectives

`staging/sync-to-claude.sh` currently vendors the `deep-refactor` skill via 4 `PAIRS` entries
mapping into a copy at `staging/plugin/skills/deep-refactor/**`. The live skill actually lives at
`~/.claude/skills/deep-refactor`, which is a symlink into a separate, independently-versioned git
repository (`/Users/stefer/Developer/Skills/Deep_refactor`, remote `github.com/istefox/Skills`).
This repo does not own that content and should stop vendoring it, following the precedent already
set for `project-tasks`, `auto-learning` and `website-auditor` (see
`docs/architecture/ADR-0191-project-tasks-migrated-to-istefox-skills.md`).

Phase 0 of the deploy roadmap already added a defensive guard in `sync-to-claude.sh` that refuses
any `--apply` write whose destination resolves through a symlink into a foreign tree — this
protects against the worst outcome (silently overwriting the foreign repo) but does not remove the
root cause: this repo still claims ownership of content it does not maintain.

## Scope

In scope:
- Declare `deep-refactor` `deployed-only` in `staging/sync-to-claude.sh`'s registry.
- Remove the PAIRS entries that map into the vendored deep-refactor tree.
- Remove the vendored tree itself from `staging/plugin/skills/deep-refactor/`, except for the one
  file `codex-reviewer.sh` has a live runtime dependency on (see Architecture below).
- Update or remove the 3 CI harnesses and 5 planted assertions that read the vendored tree.
- Update `.github/workflows/docs-ci.yml`'s `shell-tests` job entries to match what remains on disk.
- Correct forward (never rewrite in place) every doc that describes the tree as still fully
  vendored.
- Produce an ADR settling the `enumerate-sources.sh` design question (see below).

Out of scope:
- Any change to the live `deep-refactor` skill itself, or to its foreign repo
  (`Developer/Skills/Deep_refactor`).
- Any change to Phase 0's symlink-clobber guard (it stays, as defense in depth for every future
  symlinked skill, not just this one).
- Re-litigating whether deep-refactor should be a symlinked skill at all — that decision already
  exists and is not being revisited.

## Stack

Bash 3.2 (macOS default), GitHub Actions (`docs-ci.yml`), the repo's own `plant-check.sh` /
`pairs-completeness.test.sh` testing conventions. No new runtime dependency.

## Architecture

**The core mechanism (`# deployed-only:` declaration + PAIRS removal + `git rm` of the vendored
tree) mirrors ADR-0191 exactly** — same shape, applied to a fourth skill.

**Design decision — `enumerate-sources.sh` (user-confirmed, deliberate vendored exception):**
`staging/plugin/scripts/codex-reviewer.sh:206` resolves
`ENUM="$SCRIPT_DIR/../skills/deep-refactor/scripts/enumerate-sources.sh"`. At deploy time
`$SCRIPT_DIR` is `~/.claude/hooks`, so this resolves to
`~/.claude/skills/deep-refactor/scripts/enumerate-sources.sh` — through the symlink into the
foreign repo, regardless of whether this repo vendors a copy or not.

**Consequence the ADR must state explicitly:** Phase 0's own guard means the vendored PAIRS entry
for `enumerate-sources.sh` is *already* a dead deploy target — any `--apply` refuses to write it,
because the destination directory resolves through the symlink. Vendoring it changes nothing about
what actually reaches `~/.claude` at deploy time. The ADR must decide, and record, ONE of:

1. Keep `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh` (and its test) in this
   repo NOT as a deploy source (the PAIRS entry is removed along with the rest), but as a
   **compatibility contract test**: this repo's own harness snapshot-compares its committed
   interface against the live foreign-repo script's interface (e.g. accepted flags, `$1` contract),
   so a breaking change in the foreign repo's `enumerate-sources.sh` is caught by this repo's CI
   before `codex-reviewer.sh` breaks silently. This is the option the user selected.
2. (Not selected) Change `codex-reviewer.sh`'s resolution to point somewhere else.
3. (Not selected) Remove the coupling entirely.

The architect must specify exactly how option 1 is implemented: what the retained file's role is
(reference/contract-test fixture, not a deploy source), whether it needs its own `deployed-only`-
style annotation or a different marker entirely (since it is deliberately NOT declared
`deployed-only` — it never deploys, by design), and how `pairs-completeness.test.sh`'s existing
assertions (which check that every vendored file either has a PAIRS entry or a `deployed-only`
waiver) are satisfied by a file that is neither.

**Docs to correct forward (rule 14 — never rewritten in place):** ADR-0193 (lines ~131-140 and
~400-401), ADR-0018, ADR-0031 through ADR-0035, ADR-0194, ADR-0195, `docs/chain-decisions.md`,
`docs/chain-decision-index.md`, `.claude/test-ignore:34`, `PROJECT.md:107`, `TODO.md:134,170`.

## Data model

Not applicable — this is a repository-structure migration, not an application feature.

## API

Not applicable.

## UI flows

Not applicable.

## Edge cases

- A future harness or plant unknowingly re-adds a needle against the deleted vendored tree: guarded
  by the existing `plant-check.sh` sweep, which must report zero `BADPLANT` after this migration.
- The compatibility contract test (if implemented per the selected design) itself goes stale if the
  foreign repo's `enumerate-sources.sh` changes and nobody re-syncs the reference copy: the ADR
  must state how staleness is detected (a checksum comparison, or a copy-and-diff step run
  periodically or on demand) rather than leaving the reference silently unreferenced.
- `docs-ci.yml`'s `shell-tests` job must not list a harness path that no longer exists on disk
  (CI2) and must not omit a harness path that does exist.

## Success criteria

- [ ] R-01 — `staging/sync-to-claude.sh` declares `# deployed-only: deep-refactor — <reason>` in
  its registry, alphabetically placed, reason ≥ 40 characters, em-dash separator.
- [ ] R-02 — The 4 PAIRS entries mapping into `staging/plugin/skills/deep-refactor/**` are removed
  from `staging/sync-to-claude.sh`.
- [ ] R-03 — `staging/plugin/skills/deep-refactor/SKILL.md`,
  `staging/plugin/skills/deep-refactor/tests/run-tests.sh` are removed from the repo (`git rm`).
- [ ] R-04 — `enumerate-sources.sh` and its test are retained in the repo per the selected design
  (compatibility contract test, not a deploy source), with the ADR stating exactly how they are
  now used and validated.
- [ ] R-05 — `codex-audit-mode.test.sh`'s CX20-CX24 planted assertions (lines ~789/800/833/843/852)
  are removed or updated so they no longer assert against a file this repo no longer vendors as a
  deploy target; each deletion/change leaves a comment naming the issue and the ADR (rule 19).
- [ ] R-06 — `refactor-snapshot-deep-refactor.test.sh` sections B and C are removed or updated
  consistently with R-05.
- [ ] R-07 — `workflow-dispatch-pins.test.sh` A2/A3 are removed or updated consistently with R-05.
- [ ] R-08 — `.github/workflows/docs-ci.yml`'s `shell-tests` job entries match exactly what exists
  on disk after R-05/R-06/R-07 (no listed-but-absent entry, per this repo's CI2 check).
- [ ] R-09 — Every doc listed in the Architecture section's "Docs to correct forward" is updated
  with a dated correction reflecting the new state, without altering the historical narrative text
  that predates this migration (rule 14). (no-test: this is a documentation-correctness
  requirement verified by manual review of each listed file, not by an automated assertion)
- [ ] R-10 — An ADR is produced (parallel structure to ADR-0191) documenting: the migration itself,
  the `deployed-only` registry addition, and the `enumerate-sources.sh` design decision with full
  rationale (option 1 selected, options 2/3 explicitly rejected and why).
- [ ] R-11 — `pairs-completeness.test.sh`'s DO1-DO4 assertions pass, and the suite's handling of
  the retained-but-not-deployed `enumerate-sources.sh` file is explicitly accounted for (it must
  not be flagged as an orphaned vendored file with no PAIRS entry and no `deployed-only` waiver).
- [ ] R-12 — The full `staging/plugin/scripts/tests/` suite passes with zero failures.
- [ ] R-13 — `plant-check.sh` reports no `BADPLANT` across the full sweep. (no-test: verified by running the sweep locally and in CI, not by a spec-coverage assertion)
- [ ] R-14 — CI is green on all 7 checks on the resulting PR before merge. (no-test: verified by observing the PR's CI status directly, not by a repository-local assertion)

## Precedent

`docs/architecture/ADR-0191-project-tasks-migrated-to-istefox-skills.md` — the prior migration of a
structurally identical symlinked-skill vendoring problem (`project-tasks`), whose Decision section
this migration follows, adapted for deep-refactor's additional wrinkle (the `enumerate-sources.sh`
runtime coupling, which `project-tasks` did not have).
