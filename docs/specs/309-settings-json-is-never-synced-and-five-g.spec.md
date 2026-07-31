# SPEC — settings.json is never synced and five guardrail hooks are wired by hand

Source: GitHub issue #309

## Objectives

1. Derive the real list of hooks and settings keys the system depends on, and for each one determine
   what happens on a machine where the manual wiring step was skipped — silently inert, or loudly
   broken. The five names the issue supplies (`agent-write-scope.sh`, `agent-command-scope.sh`,
   `write-scope-enforce.sh`, `test-write-scope.sh`, `precompact-guard.sh`) are to be verified, not
   copied.
2. Ship a check that detects and reports missing wiring rather than assuming it, distinguishing
   "not wired" from "could not tell".
3. Decide explicitly whether `sync-to-claude.sh` should write `settings.json`, stating the blast
   radius, and split the verification between CI and deploy time per the ADR-0087 precedent.

## Scope

In: the wiring status of every hook and settings key the system depends on; the decision on whether
`staging/sync-to-claude.sh` writes `settings.json`; a CI-runnable check over `staging/`; a
deploy-time report for the `$HOME`-dependent half; the `worktree.baseRef` user-scope settings key
recorded in ADR-0068 §D2.

Out: changing what any guardrail hook enforces; owning a global Claude Code event (ADR-0068 §D2
rejected owning `WorktreeCreate` for exactly the blast-radius reason this issue must re-state);
making CI depend on the deploy state of `~/.claude` (ADR-0084 refused that, ADR-0087 established the
split instead).

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/sync-to-claude.sh` — the `PAIRS` list plus the `pairs-zone-anomaly:` declarations; its
  header states that `user/settings.json` stays out of `PAIRS` on purpose (ADR-0025: machine-local
  keys need a `jq del()` pass, not a straight copy) and that the script prints hook wiring to add by
  hand. This is the file the R-02 decision lands in.
- `staging/user/settings.json` — the staged settings file, carrying the `hooks` block and the
  `worktree.baseRef` key. Not synced today.
- The named guardrail hooks under `staging/plugin/scripts/`: `agent-write-scope.sh`,
  `agent-command-scope.sh`, `write-scope-enforce.sh`, `test-write-scope.sh`, `precompact-guard.sh`,
  alongside the already-wired `pre-flight-pattern-enforce.sh`, `protect-files.sh`,
  `db-backup-guardrail.sh`, `nightly-guard.sh`, `post-write-check.sh`, `auto-format.sh`,
  `mark-dirty.sh`, `chain-memory-capture.sh`, `ensure-state-dir.sh`. The population must be derived
  from `staging/plugin/scripts/` and `staging/user/settings.json` rather than from this list.
- `staging/plugin/scripts/tests/sync-manual-steps.test.sh` — the existing hermetic `$HOME`-override
  harness for `sync-to-claude.sh`'s MANUAL STEP notices, including section F for the
  `worktree.baseRef` settings-key notice. The natural home for the CI-runnable half.
- `staging/plugin/scripts/tests/pairs-completeness.test.sh` — the existing completeness check over
  `PAIRS` (ADR-0043), and the precedent for a check that runs in the direction that catches an
  omission.
- ADR anchors: `docs/architecture/ADR-0041-58-agent-write-scope.md`,
  `docs/architecture/ADR-0045-58-interpreter-wrapper-bypass.md`,
  `docs/architecture/ADR-0049-103-generator-verifier-separation.md`,
  `docs/architecture/ADR-0068-176-worktree-isolation-contract.md` (§D2),
  `docs/architecture/ADR-0087-222-deployed-only-skills.md` (the CI / deploy-time split). The issue
  cites line numbers in the first four; those line numbers will have moved and the "deployed by
  sync, **wired by hand**" phrasing is the anchor to search for instead.
- `staging/plugin/scripts/tests/plant-check.sh` and the plant registry (ADR-0108) — every new
  assertion declares its plant beside it.

## Data model

None. The wiring state is read from `settings.json` (a `hooks` block keyed by event, each entry
carrying a `command` string) and from the presence of the hook file under `~/.claude/hooks/`; no new
persistent record is proposed by the issue.

## API / Interfaces

- A check over the wiring, with the repository's standing contract: if it is a checker it branches
  on an exit code and distinguishes "did not run" (exit 3) from "found nothing"; if it is a reporter
  it always exits 0 and signals on stdout. R-01's "could not tell" state is what makes that
  distinction load-bearing here.
- `staging/sync-to-claude.sh` — existing CLI: dry-run by default, `--apply` to write. Its MANUAL STEP
  notices are the existing deploy-time reporting channel and are gated on the state they describe.
- Assertions in `staging/plugin/scripts/tests/` for the CI-runnable half.

## UI flows

None. The deploy-time half surfaces as text printed by `bash staging/sync-to-claude.sh` (dry-run or
`--apply`) and read by the operator performing the sync.

## Edge cases

- A machine where the hook file exists under `~/.claude/hooks/` but no `settings.json` entry
  references it: installed but inert, the class the issue names as the residual that silently
  disarms the other residuals.
- A `settings.json` that cannot be read or parsed: this is the "could not tell" state R-01 requires,
  and must not be reported as "not wired".
- `worktree.baseRef` drifting back from `"head"` to `"fresh"`: a user-scope key with no signal other
  than the per-dispatch check ADR-0068 §D2 records.
- A hook wired under an event or matcher that never fires: present in `settings.json` yet still
  inert.
- The `$HOME`-dependent half cannot run in CI. The existing hermetic `$HOME`-override fixture in
  `sync-manual-steps.test.sh` is the pattern for whatever part can be made CI-runnable without
  reading the real `~/.claude`.
- A hook staged under `staging/plugin/scripts/` that is a probe and must never be wired
  (`worktree-capture.sh`, `hook-probe*.sh`): a naive "every script should be wired" derivation would
  report these as missing wiring.

## Success criteria

- [ ] R-01 — missing wiring is detected and reported, rather than assumed; the check must
      distinguish "not wired" from "could not tell".
- [ ] R-02 — whether `sync-to-claude.sh` should write `settings.json` is decided explicitly, with
      the blast radius stated: ADR-0068 §D2 rejected owning a global event for exactly this reason.
- [ ] R-03 — the CI-runnable half runs in CI; the `$HOME`-dependent half is a deploy-time report,
      per the split ADR-0087 established.
