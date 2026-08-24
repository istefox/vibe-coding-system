# Proposal C4 — PostToolUse backstop hook for Step 7.1 (commit outcome)

Status: proposal, not yet implemented. Written 2026-08-23 after a live incident in the Adnota
project. Target for implementation: this repo (vibe-coding-system), since `concept-to-code`'s
`SKILL.md` and the hook layer live here, not in the consuming project.

## Context

`~/.claude/skills/concept-to-code/SKILL.md`, Step 7.1 (around line 3147, "classify what `commit`
did", issue #410, ADR-0135 §D3) is an inline bash fence the orchestrator is instructed to run
right after invoking the `commit` skill. It reads the manifest on disk (never the skill's own
self-report — ADR-0047 §A3) and classifies the outcome:

- `COMMIT_OK` — manifest is `current_step: completed`, `status: completed`, and clean in git.
  Proceed to post-commit actions (push, PROJECT.md update, cost snapshot).
- `COMMIT_UNCOMMITTED untracked|modified` — manifest still dirty in git. Stop, report, no
  rollback (`completed` is absorbing per ADR-0078).
- `COMMIT_NONTERMINAL current_step|status` — manifest itself isn't in the terminal state. Stop,
  report that Step 7.0c didn't take effect.
- `COMMIT_OUTCOME_NORUN <reason>` (exit 3) — manifest or repo missing entirely. Did not run.

This check exists **only as an instruction inside the skill markdown**. It has no structural
enforcement: nothing prevents the orchestrator from skipping it, especially deep into a long
chain run where thousands of lines of prior instructions have already been processed.

### Precedent: this already happened

Adnota repo, PR #36 (`344b7772`, 2026-08-23, "chore(kindle-sync): correct manifest completion
status"), fixing the merge of PR #35 (`kindle-sync-orchestration` chain):

> The Step 7 collapse staged the manifest before the SPEC archive repoint and the completed
> transition ran, and neither follow-up write was re-staged before the commit — the merged
> manifest still reads `current_step: step_7_commit`, `status: in_progress`, and
> `artifacts.spec` pointing at the mutable SPEC.md slot instead of the archived copy. The
> feature itself shipped complete and correct; only this bookkeeping file was stale.

That is exactly the `COMMIT_NONTERMINAL status` condition Step 7.1 exists to catch. Had Step 7.1
actually run and been honored on that commit, the bad manifest state would have been caught
before merge instead of discovered afterward and patched with a second commit.

### Why this matters beyond bookkeeping hygiene

If `COMMIT_NONTERMINAL` / `COMMIT_UNCOMMITTED` goes unnoticed, the chain today proceeds anyway to:
- post-commit push,
- PROJECT.md update marking the feature `[x]` completed,
- cost snapshot.

`project-conductor` and `autopilot` read PROJECT.md checkboxes to decide what feature to work on
next. A false-positive "completed" checkbox on work that isn't actually in a clean, terminal,
committed state can make an unattended run skip real work believing it's already done.

## Proposed solution (C4)

A `PostToolUse` hook matched on the `Skill` tool, filtered to invocations of the `commit` skill,
that re-runs the same manifest classification as a stateless backstop — independent of whether
the orchestrator remembered to run Step 7.1 inline.

### Design

1. **Extract the check into a shared script.**
   Currently the classification logic lives only as an inline heredoc in `SKILL.md` (the
   `<!-- fence-contract: c2c-step7-commit-outcome -->` fence, lines ~3161-3176). Move it to:

   ```
   ~/.claude/skills/concept-to-code/scripts/commit-outcome-check.sh <manifest-path>
   ```

   Same stdout/exit-code contract as today (`COMMIT_OK` / `COMMIT_UNCOMMITTED ...` /
   `COMMIT_NONTERMINAL ...` / `COMMIT_OUTCOME_NORUN ...`, exit 0/1/3). Step 7.1 in `SKILL.md`
   then calls this script instead of inlining the heredoc — single source of truth, so the hook
   and the orchestrator can never diverge.

2. **New hook script**: `~/.claude/hooks/commit-outcome-backstop.sh`.
   Registered as `PostToolUse`, matcher `Skill`, fires after every `Skill` tool call.
   - No-ops immediately unless the tool input's skill name is `commit`.
   - Stateless discovery, no dependency on "is a concept-to-code chain active": scans
     `docs/manifests/*.manifest.yml` (or wherever the project's manifests live — same lookup
     `manifest-transition.sh` already uses) for any manifest with `status: completed` or
     `current_step: completed`, and runs `commit-outcome-check.sh` against each.
   - Any manifest that classifies as `COMMIT_UNCOMMITTED` or `COMMIT_NONTERMINAL` after a
     `commit` invocation gets surfaced as hook output (visible to the orchestrator/user in the
     transcript). It is a **warn/report backstop, not a blocking gate**: PostToolUse hooks can
     inject text but cannot replay the rich stop/no-rollback messaging (ADR-0078 references,
     exact remediation steps) that the inline Step 7.1 instruction produces. That richer
     messaging stays in `SKILL.md`; the hook's job is only to guarantee *something* fires even
     when the orchestrator's inline instruction gets skipped.
   - Exit 0 always (report-only); do not block the tool result on a stale, unrelated manifest
     that happens to also be lying around in `completed` state from an earlier, already-handled
     run.

3. **Registration** (`~/.claude/settings.json`, same shape as the existing `PostToolUse` entries
   for `Edit|Write` → `auto-format.sh` / `post-write-check.sh`):

   ```json
   {
     "matcher": "Skill",
     "hooks": [
       { "type": "command", "command": "\"$HOME\"/.claude/hooks/commit-outcome-backstop.sh" }
     ]
   }
   ```

### Open questions / risks to settle before implementing

- **Manifest discovery path is project-relative.** The hook needs the project root to find
  `docs/manifests/`. `PostToolUse` hook payloads include `cwd`; confirm this resolves correctly
  when the `commit` skill is invoked from inside a chain running in a subagent/worktree, not just
  the main session.
- **False positives from stale manifests.** A manifest left in `completed`/dirty state from a
  run that was deliberately abandoned or handled out-of-band would re-trigger the warning on
  every unrelated future `commit` invocation in that project until someone fixes or archives it.
  Decide whether the hook should only look at manifests touched (mtime) since the current
  session/tool-call, not all matching manifests in the tree.
- **Scope of the `Skill` matcher.** Firing on every `Skill` call and filtering internally (skill
  name == `commit`) is simpler to register but runs the discovery scan on every skill invocation
  in the session, not just commit-related ones. Confirm the hook's own cost is negligible before
  accepting that tradeoff, or investigate whether the matcher can filter by skill name directly.

## Next step

Implement in this repo (`vibe-coding-system`) under plan mode: extract the script, write the
hook, register it, then dry-run against the Adnota PR #36 scenario (reconstruct the pre-fix
manifest state and confirm the hook actually flags it) before considering this closed.
