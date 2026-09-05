# Deploy the Codex review gate, after cleaning up sync-to-claude.sh's stale PAIRS entries

## Context

The user asked to verify whether the "Codex as reviewer" gate (ADR-0187, Gate CDX) is actually
active. It is fully designed, coded, tested and merged into `main` (`9dde153`, `3d16517`,
`55e3aee`), but never deployed: `~/.claude/skills/concept-to-code/SKILL.md` and
`~/.claude/skills/review-triage-fix/SKILL.md` predate the feature, and
`~/.claude/hooks/codex-reviewer.sh` (the wrapper) was never copied out at all.

A `bash staging/sync-to-claude.sh` dry-run (no `--apply`, nothing written) confirmed the Codex-gate
files are ready to deploy, but also surfaced two pre-existing hazards that a blind `--apply` would
have hit, since the script has no per-file selection — it writes all 16 differing PAIRS targets at
once:

1. **`rules/tools.md`** — the live file has 2 rules (`github-raw-default-branch`,
   `agent-registry-snapshot-mid-session`) added directly via auto-learning, never backported to this
   repo's `staging/user/rules/tools.md`. Applying as-is would delete them from the live file.

2. **`project-tasks`** — bigger, structural. ADR-0153 (2026-08-17) vendored this skill into this
   repo and removed its `deployed-only` waiver. Measured just now: `~/.claude/skills/project-tasks`
   is today a **symlink** to `/Users/stefer/Developer/Skills/tasks`, which is its own git repo
   (`origin` = `github.com/istefox/Skills`) with an active PR history through today (`chore(project-
   tasks): close SK-007...` merged, `Sep 4`). The skill was migrated out of this repo into its own
   dedicated repo at some point after ADR-0153, but that migration was never recorded here: no
   ADR, no PAIRS cleanup, no waiver restored. This repo's `staging/plugin/skills/project-tasks/*` is
   the pre-migration fork, now dead code, and `sync-to-claude.sh`'s 9 PAIRS lines for it (163-171)
   still point at it. Applying would try to overwrite the live symlink's target with this stale
   fork.

The user chose the full fix: write a superseding ADR recording the migration, retire the dead
vendored copy and its test harness, restore the `deployed-only` waiver, then re-run the dry-run
clean before deploying.

## Part 1 — `rules/tools.md` catch-up

Copy the live file over the stale staging copy (verified: the only diff is the 2 trailing rules
missing from staging; nothing else differs):

```bash
cp ~/.claude/rules/tools.md staging/user/rules/tools.md
```

## Part 2 — Retire the dead `project-tasks` vendored fork

**New ADR-0191** (next free number after ADR-0190) under `docs/architecture/`, `Supersedes:
ADR-0153`. Content: records the measured facts above (live symlink target, its independent repo and
PR history, the fact the migration predates this ADR and was never documented), restores the
`deployed-only: project-tasks` waiver (same class as `auto-learning`/`website-auditor`, which already
document "symlink into a foreign repository carrying its own git remote and history"), and states
the removal of the vendored tree and its harness as a consequence. Follow this repo's own ADR
template/tone (see ADR-0153 and ADR-0187 for shape: Status, Context, Decision, Consequences,
References). Add its one-line entry to `docs/chain-decision-index.md`, matching the existing
ADR-0153 entry's format (that ADR already has a line there, so its supersession should too).

**Remove the stale vendored tree** (9 files, `git rm`, not raw `rm`, so it stays reversible via git
history):
```
staging/plugin/skills/project-tasks/SKILL.md
staging/plugin/skills/project-tasks/scripts/{scan,selftest,ledger-merge,gh-issues}.sh
staging/plugin/skills/project-tasks/reference/{file-format,capture-sources,chain-integration}.md
staging/plugin/skills/project-tasks/templates/TODO.template.md
```

**Remove its harness**: `git rm staging/plugin/scripts/tests/project-tasks-ledger.test.sh` (ADR-0153
§D7's dedicated 30-assertion file; no other harness references `project-tasks`, confirmed by grep).

**`staging/sync-to-claude.sh` edits:**
- Delete the 9 PAIRS lines for `project-tasks` (lines 163-171).
- Add one `# deployed-only: project-tasks — …` line in the declared-waivers comment block, in
  alphabetical order between `daily-open` and `vibiso-intake` (matching the existing block's
  ordering), reason ≥ 40 chars, citing the migration to `istefox/Skills` and ADR-0191.

**`.github/workflows/docs-ci.yml` edit:** remove the `project-tasks-ledger` token from the
`shell-tests` step's `for t in ...` list (line 267), since the harness it named no longer exists.

## Part 3 — Verify before touching live state

- `bash -n staging/sync-to-claude.sh`
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — expect DO1 count to rise from 6
  to 7 (still `>= 5`, no floor change needed), DO2/DO3/DO4 green (project-tasks now genuinely absent
  from `staging/plugin/skills/`).
- `bash staging/sync-to-claude.sh` (dry-run again) — confirm the diff now shows **only** the
  Codex-gate files (Part A) and the other already-merged, staging-ahead fixes (spec-coverage.sh,
  plan-budget-parse.awk, autopilot/SKILL.md, project-conductor reference) — no `rules/tools.md`, no
  `project-tasks/*`.
- Spot-check no dangling reference to the removed test file: `grep -rn "project-tasks-ledger"
  .github/ staging/` should only hit the ADR/docs prose, not an executable list.

## Part 4 — Deploy (gated)

Show the clean dry-run output, then, only on explicit go-ahead, run
`bash staging/sync-to-claude.sh --apply`. This writes the Codex-gate files (SKILL.md x2,
manifest-init/validate.sh, codex-reviewer.sh, step5-implementation.md) plus the other already-ahead
fixes to `~/.claude/`. It does **not** touch `~/.claude/skills/project-tasks` (no longer in PAIRS,
and the script never deletes deployed targets it doesn't own).

## Part 5 — Commit

Use the `commit` skill (never a raw `git commit`) to commit the repo-side changes on the current
branch (`worktree/feat-codex-chain`): the new ADR-0191, the chain-decision-index line, the two
`git rm` deletions, the `sync-to-claude.sh` PAIRS/waiver edit, the `docs-ci.yml` edit, and the
`rules/tools.md` catch-up. Deploy (Part 4) is a separate, non-git action and stays gated
independently — it can happen before or after the commit, but each gate (commit, and `--apply`) is
asked for explicitly, never bundled.

## Verification summary

- `bash -n` clean on every edited script.
- `pairs-completeness.test.sh` green (DO1-DO4).
- Second dry-run shows only the intended Codex-gate + already-known-ahead diffs.
- After `--apply`, confirm live: `grep -n "Gate CDX" ~/.claude/skills/concept-to-code/SKILL.md` and
  `test -x ~/.claude/hooks/codex-reviewer.sh` both succeed.
