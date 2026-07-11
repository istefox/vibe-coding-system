# SPEC — Refresh stale staging copies from the deployed tree

Source: GitHub issue #29

## Objectives
1. Refresh every stale `staging/` file that has a deployed counterpart, treating the deployed tree (`~/.claude`, read-only source) as authoritative (audit findings 1.5, 2.21–2.26, 3.33–3.37, 3.39).
2. Remove the retired `project-bootstrap` skill from staging and reconcile its two blueprint references.
3. Extend sync PAIRS so `goal-loop` and `research-prompt` can reach deployment.

## Scope
In:
- All 8 files in `staging/plugin/agents/` from `~/.claude/agents/` (staged copies pre-date ADR-0001/0004 PATTERN classifier, ADR-0012 agent-notes removal, ADR-0014 architect output blocks, ADR-0015 English prose).
- `staging/plugin/skills/{commit,interview-driver,adr-writer,claude-md-generator,code-review-checklist,swift-vibe,fastapi-react-vibe}/SKILL.md` (staged commit lacks `--autopilot`; staged interview-driver and fastapi-react-vibe keep `disable-model-invocation: true`).
- `staging/plugin/scripts/{protect-files.sh,auto-format.sh}` (deployed fail-open jq handling is deliberate, keep it).
- `staging/user/CLAUDE.md` and `staging/user/rules/swift.md`; add `staging/user/rules/parallelization.md` (deployed-only today).
- `staging/user/settings.json`: mirror the live hooks wiring, deny list, and plugin set, but strip machine-local keys (model, theme, tui, editorMode, statusLine, cleanupPeriodDays) and replace the `mcp__*` wildcard with the narrowed allow set.
- Delete `staging/plugin/skills/project-bootstrap/` and reconcile docs/vibe-coding-system.md lines 2282 and 2297, keeping section numbering and changelog conventions.
- Add `staging/plugin/skills/{goal-loop,research-prompt}/SKILL.md` to sync PAIRS.

Out:
- Any write under `~/.claude`.
- Fixing defects inside the refreshed files (later roadmap issues).

## Stack
Bash scripts, Markdown, JSON settings, GitHub Actions docs-ci.

## Architecture
`staging/plugin/agents/`, `staging/plugin/skills/`, `staging/plugin/scripts/`, `staging/user/`, `staging/sync-to-claude.sh` PAIRS, `docs/vibe-coding-system.md` (two reference lines). RUNBOOK.md Step 6 restores from these files, so staleness is an active hazard, not an archive.

## Data model
None.

## API / Interfaces
`sync-to-claude.sh` PAIRS contract; settings.json schema (machine-local keys stripped as documented).

## UI flows
None.

## Edge cases
- settings.json is NOT byte-identical by design: documented exclusions (model, theme, tui, editorMode, statusLine, cleanupPeriodDays) and the narrowed `mcp__*` allow set.
- project-bootstrap removal touches blueprint prose: keep section numbering and the "Changes from…" changelog conventions intact.
- Deployed fail-open jq handling in protect-files.sh/auto-format.sh is deliberate; do not "fix" it during refresh.

## Success criteria
- [ ] Zero diff between each refreshed staged file and its deployed counterpart (minus the documented settings.json exclusions)
- [ ] `grep -c PATTERN staging/plugin/agents/coder.md` returns nonzero; `grep docs/agent-notes staging/plugin/agents/*.md` returns nothing
- [ ] staged commit SKILL.md contains `--autopilot`; staged interview-driver has no `disable-model-invocation`
- [ ] project-bootstrap gone from staging and from the two blueprint lines; PAIRS covers goal-loop and research-prompt
- [ ] No file under `~/.claude` modified
