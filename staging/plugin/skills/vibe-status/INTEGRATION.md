# vibe-status — Active chains section (ADR-0021 follow-up)

Read-only addition that surfaces in-progress `concept-to-code` chains in the vibe-status report,
reading the STATE OF FACT headers written by `chain-memory-capture.sh` (sec. 7.7 / ADR-0021).
Staged here because `vibe-status` lives in `~/.claude/skills/`, not in this blueprint repo.

## Files

- `scripts/chain-memory-section.sh` — standalone, read-only. Prints an `## Active chains` Markdown
  block (one line per non-terminal chain: topic, current_step, status, next_action). Prints
  nothing when there are no active chains or no store. Bash 3.2 compatible.

## Deploy (live, separate HITL step)

1. Copy the script into the live skill:
   ```
   cp staging/plugin/skills/vibe-status/scripts/chain-memory-section.sh \
      ~/.claude/skills/vibe-status/scripts/chain-memory-section.sh
   chmod +x ~/.claude/skills/vibe-status/scripts/chain-memory-section.sh
   ```
2. Wire it into `~/.claude/skills/vibe-status/scripts/aggregate.sh` where the report sections are
   emitted (after the Memory head section). aggregate.sh already resolves the per-cwd memory dir;
   pass it through so the encoding is computed once:
   ```bash
   # In aggregate.sh, MEM_DIR is the resolved ~/.claude/projects/<encoded-cwd>/memory path.
   bash "$HOME/.claude/skills/vibe-status/scripts/chain-memory-section.sh" "$MEM_DIR" || true
   ```
   If aggregate.sh does not expose `$MEM_DIR`, call the script with no argument — it derives the
   path from `$PWD` exactly as the existing "Memory head" line does (SKILL.md Discovery).

## SKILL.md edits

- Discovery → Locale: add
  `- Chain history: ~/.claude/projects/<encoded-cwd>/memory/chain-history/*.md (active chains)`
- Output sample: note the new `## Active chains` section appears when in-progress chains exist.

## Why read-only

Consistent with the ADR-0012 agent-notes watch (ADR-0005 / vibe-status): the report only reads the
store; it never writes. The single writer remains the `chain-memory-capture.sh` hook (ADR-0021 D6).
