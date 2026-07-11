---
name: vibe-status
description: Aggregate health report of the vibe-coding system. Runs harness in parallel, lists ADRs, manifests, skills, hooks, memory. Read-only, <10s typical. Title in report: Vibe-Coding System Status.
---

# vibe-status

Single command to render the full health status of the vibe-coding system. Read-only,
<10s typical, fail-graceful per section.

## When to invoke

- Before a complex multi-agent dispatch — verify system is HEALTHY.
- After deploy of a new skill/hook/agent — confirm harness regression is clean.
- Periodic check — discover skills/hooks added recently.

## Process

1. Run `bash ~/.claude/skills/vibe-status/scripts/aggregate.sh [--json|--plain|--skip-harness]`.
2. Default output is Markdown to stdout. The orchestrator/LLM can render directly in chat.
3. Interpret overall status header: HEALTHY (all green) | DEGRADED (1+ issue) | CRITICAL (2+ harness fails or all harness errors).

## Flags

- `--json` — emit JSON for programmatic consumption (future skill chaining).
- `--plain` — plain text output (no Markdown tables).
- `--skip-harness` — metadata-only, <1s (no harness execution).

## Discovery

Globale (always):
- Harness: `~/.claude/skills/*/tests/run-tests.sh`
- Skills: `~/.claude/skills/*/`
- Agents: `~/.claude/agents/*.md`
- Hooks: parsed from `~/.claude/settings.json`

Locale (cwd-relative, conditional on existence):
- ADR: `$PWD/docs/architecture/ADR-*.md`
- Manifests: `$PWD/docs/manifests/*.yaml`
- Triage state: `$PWD/.triage-fix-last.json`
- Memory head: `~/.claude/projects/<encoded-cwd>/memory/MEMORY.md`
- Chain history: `~/.claude/projects/<encoded-cwd>/memory/chain-history/*.md` (active chains)

## Defaults

- Per-harness timeout: 12s (env `VIBE_STATUS_HARNESS_TIMEOUT`).
- Window: cwd-aware. Degrades gracefully on missing dirs/files.

## Title

The report header is: `# Vibe-Coding System Status — <ISO-timestamp>`.

## Output sample

See `~/.claude/skills/vibe-status/tests/run-tests.sh` for fixtures and expected output
shape.
The `## Active chains` section appears when the memory store has one or more non-terminal
`concept-to-code` chains recorded (ADR-0021); it is omitted entirely when there are none.

## Reference

- ADR: `docs/architecture/ADR-0005-vibe-status-skill.md`
- Spec: `docs/superpowers/specs/2026-05-20-vibe-status-skill-design.md`
- Plan: `docs/superpowers/plans/2026-05-20-vibe-status-skill.md`
