# vibe-status — Active chains section (ADR-0021 follow-up)

**Status:** staging-side wiring executed 2026-07-11 (issue #37, ADR-0033). The Deploy section below
is the remaining, separate human step.

Read-only addition that surfaces in-progress `concept-to-code` chains in the vibe-status report,
reading the STATE OF FACT headers written by `chain-memory-capture.sh` (sec. 7.7 / ADR-0021).
Staged here because `vibe-status` lives in `~/.claude/skills/`, not in this blueprint repo.

## Files

- `scripts/chain-memory-section.sh` — standalone, read-only. Prints an `## Active chains` Markdown
  block (one line per non-terminal chain: topic, current_step, status, next_action). Prints
  nothing when there are no active chains or no store. Bash 3.2 compatible.

## Deploy (live, separate HITL step)

Run the standard sync: `bash staging/sync-to-claude.sh --apply` (dry-run first, no `--apply`, to review
the diff). The PAIRS entry added by ADR-0033 covers `chain-memory-section.sh` alongside the other four
vibe-status files already synced (`SKILL.md`, `aggregate.sh`, `harness-runner.sh`, `tests/run-tests.sh`)
— no manual `cp`/`chmod` step is needed anymore.

## Testing the staging tree before sync

`tests/run-tests.sh` targets the deployed skill by default (`$HOME/.claude/skills/vibe-status`), by
design (CI-dark, `$HOME`-coupled — ADR-0033 §Neutral). To exercise the staging tree's own fixes
directly, without touching `~/.claude`, set `VIBE_STATUS_SKILL_DIR` to the staging skill directory:
```bash
VIBE_STATUS_SKILL_DIR="$PWD/staging/plugin/skills/vibe-status" \
  bash staging/plugin/skills/vibe-status/tests/run-tests.sh
```

## SKILL.md edits

- Discovery → Locale: add
  `- Chain history: ~/.claude/projects/<encoded-cwd>/memory/chain-history/*.md (active chains)`
- Output sample: note the new `## Active chains` section appears when in-progress chains exist.

## Why read-only

Consistent with the native agent-memory watch (VCS-056, ADR-0183; ADR-0005 / vibe-status): the report only reads the
store; it never writes. The single writer remains the `chain-memory-capture.sh` hook (ADR-0021 D6).
