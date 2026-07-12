#!/bin/bash
# sync-to-claude v1.0 (ADR-0022 Phase 5) — copy the nightly-autopilot blueprint into ~/.claude.
#
# Dry-run by default: prints a diff for every target and changes nothing. Pass --apply to write.
# For an existing target, the diff is shown before it is overwritten (global safety rule). The live
# settings.json is NOT auto-edited; the script prints the hook wiring to add by hand.
#
# Bash 3.2 clean. Run from the repo root: bash staging/sync-to-claude.sh [--apply]

set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
STAGING="$REPO/staging"
DEST="$HOME/.claude"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# src|dst pairs (dst relative to ~/.claude). Scripts land in hooks/ (this deployment's convention).
PAIRS="
plugin/scripts/nightly-guard.sh|hooks/nightly-guard.sh
plugin/scripts/publish-feature.sh|hooks/publish-feature.sh
plugin/scripts/set-branch-protection.sh|hooks/set-branch-protection.sh
plugin/skills/nightly-autopilot/SKILL.md|skills/nightly-autopilot/SKILL.md
plugin/skills/nightly-autopilot/tests/run-tests.sh|skills/nightly-autopilot/tests/run-tests.sh
plugin/scripts/tests/phase1.test.sh|hooks/tests/phase1.test.sh
plugin/skills/project-conductor/SKILL.md|skills/project-conductor/SKILL.md
project-templates/ci/ci.yml|templates/ci.yml
plugin/scripts/detect-test-cmd.sh|hooks/detect-test-cmd.sh
plugin/scripts/roadmap-from-issues.sh|hooks/roadmap-from-issues.sh
plugin/scripts/spec-issue-gate.sh|hooks/spec-issue-gate.sh
plugin/scripts/tests/prep.test.sh|hooks/tests/prep.test.sh
plugin/scripts/hook-verify-workflow.sh|skills/concept-to-code/scripts/hook-verify-workflow.sh
plugin/scripts/tests/hook-verify-workflow.test.sh|hooks/tests/hook-verify-workflow.test.sh
plugin/skills/spec-from-issue/SKILL.md|skills/spec-from-issue/SKILL.md
plugin/scripts/stop-gate.sh|hooks/stop-gate.sh
plugin/scripts/pre-flight-pattern-enforce.sh|hooks/pre-flight-pattern-enforce.sh
plugin/scripts/db-backup-guardrail.sh|hooks/db-backup-guardrail.sh
plugin/scripts/approve-test-cmd.sh|hooks/approve-test-cmd.sh
plugin/scripts/session-context-inject.sh|hooks/session-context-inject.sh
plugin/scripts/ensure-state-dir.sh|hooks/ensure-state-dir.sh
plugin/scripts/mark-dirty.sh|hooks/mark-dirty.sh
plugin/scripts/post-md-tells-hint.sh|hooks/post-md-tells-hint.sh
plugin/scripts/prompt-en-prose-detect.sh|hooks/prompt-en-prose-detect.sh
plugin/scripts/reset-gate-counter.sh|hooks/reset-gate-counter.sh
plugin/scripts/usage-daily-hint.sh|hooks/usage-daily-hint.sh
plugin/scripts/migrate-trust-paths.sh|hooks/migrate-trust-paths.sh
plugin/scripts/tests/db-backup-guardrail.sh|hooks/tests/db-backup-guardrail.sh
plugin/scripts/tests/pre-flight-pattern-enforce.sh|hooks/tests/pre-flight-pattern-enforce.sh
plugin/scripts/tests/run-hook-tests.sh|hooks/tests/run-hook-tests.sh
plugin/skills/concept-to-code/SKILL.md|skills/concept-to-code/SKILL.md
plugin/skills/concept-to-code/scripts/agent-notes-harvest.sh|skills/concept-to-code/scripts/agent-notes-harvest.sh
plugin/skills/concept-to-code/scripts/detect-macos.sh|skills/concept-to-code/scripts/detect-macos.sh
plugin/skills/concept-to-code/scripts/gate0-detect.sh|skills/concept-to-code/scripts/gate0-detect.sh
plugin/skills/concept-to-code/scripts/manifest-init.sh|skills/concept-to-code/scripts/manifest-init.sh
plugin/skills/concept-to-code/scripts/manifest-set-artifact.sh|skills/concept-to-code/scripts/manifest-set-artifact.sh
plugin/skills/concept-to-code/scripts/manifest-set-flag.sh|skills/concept-to-code/scripts/manifest-set-flag.sh
plugin/skills/concept-to-code/scripts/manifest-set-gate.sh|skills/concept-to-code/scripts/manifest-set-gate.sh
plugin/skills/concept-to-code/scripts/manifest-set-humanize.sh|skills/concept-to-code/scripts/manifest-set-humanize.sh
plugin/skills/concept-to-code/scripts/manifest-transition.sh|skills/concept-to-code/scripts/manifest-transition.sh
plugin/skills/concept-to-code/scripts/manifest-validate.sh|skills/concept-to-code/scripts/manifest-validate.sh
plugin/skills/concept-to-code/tests/agent-notes-roundtrip.sh|skills/concept-to-code/tests/agent-notes-roundtrip.sh
plugin/skills/concept-to-code/tests/run-tests.sh|skills/concept-to-code/tests/run-tests.sh
plugin/skills/concept-to-code/tests/smoke-e2e.sh|skills/concept-to-code/tests/smoke-e2e.sh
plugin/skills/autopilot-build/SKILL.md|skills/autopilot-build/SKILL.md
plugin/skills/autopilot-build/tests/run-tests.sh|skills/autopilot-build/tests/run-tests.sh
plugin/skills/deep-refactor/SKILL.md|skills/deep-refactor/SKILL.md
plugin/skills/deep-refactor/scripts/enumerate-sources.sh|skills/deep-refactor/scripts/enumerate-sources.sh
plugin/skills/deep-refactor/tests/enumerate-sources.test.sh|skills/deep-refactor/tests/enumerate-sources.test.sh
plugin/skills/deep-refactor/tests/run-tests.sh|skills/deep-refactor/tests/run-tests.sh
plugin/skills/review-triage-fix/SKILL.md|skills/review-triage-fix/SKILL.md
plugin/skills/review-triage-fix/scripts/triage-state.sh|skills/review-triage-fix/scripts/triage-state.sh
plugin/skills/review-triage-fix/scripts/verify.sh|skills/review-triage-fix/scripts/verify.sh
plugin/skills/review-triage-fix/scripts/weakening-scan.sh|skills/review-triage-fix/scripts/weakening-scan.sh
plugin/skills/review-triage-fix/tests/run-tests.sh|skills/review-triage-fix/tests/run-tests.sh
plugin/skills/commit/SKILL.md|skills/commit/SKILL.md
plugin/skills/claude-md-slim/SKILL.md|skills/claude-md-slim/SKILL.md
plugin/skills/claude-md-slim/scripts/classify-sections.sh|skills/claude-md-slim/scripts/classify-sections.sh
plugin/skills/claude-md-slim/scripts/content-union-check.sh|skills/claude-md-slim/scripts/content-union-check.sh
plugin/skills/claude-md-slim/scripts/parse-sections.sh|skills/claude-md-slim/scripts/parse-sections.sh
plugin/skills/claude-md-slim/scripts/validate-frontmatter.sh|skills/claude-md-slim/scripts/validate-frontmatter.sh
plugin/skills/claude-md-slim/tests/fixtures/expected-shell-rules.md|skills/claude-md-slim/tests/fixtures/expected-shell-rules.md
plugin/skills/claude-md-slim/tests/fixtures/expected-trimmed.md|skills/claude-md-slim/tests/fixtures/expected-trimmed.md
plugin/skills/claude-md-slim/tests/fixtures/sample-claude-md.md|skills/claude-md-slim/tests/fixtures/sample-claude-md.md
plugin/skills/claude-md-slim/tests/fixtures/sample-global-claude-md.md|skills/claude-md-slim/tests/fixtures/sample-global-claude-md.md
plugin/skills/claude-md-slim/tests/run-tests.sh|skills/claude-md-slim/tests/run-tests.sh
plugin/skills/clean-public-repo/SKILL.md|skills/clean-public-repo/SKILL.md
plugin/skills/clean-public-repo/scripts/detect-public-remote.sh|skills/clean-public-repo/scripts/detect-public-remote.sh
plugin/skills/clean-public-repo/scripts/detect-tool-traces.sh|skills/clean-public-repo/scripts/detect-tool-traces.sh
plugin/skills/clean-public-repo/scripts/fresh-history-publish.sh|skills/clean-public-repo/scripts/fresh-history-publish.sh
plugin/skills/clean-public-repo/scripts/surgical-rewrite.sh|skills/clean-public-repo/scripts/surgical-rewrite.sh
plugin/skills/clean-public-repo/tests/run-tests.sh|skills/clean-public-repo/tests/run-tests.sh
plugin/skills/humanize-en/SKILL.md|skills/humanize-en/SKILL.md
plugin/skills/humanize-en/rules.md|skills/humanize-en/rules.md
plugin/skills/humanize-en/scripts/detect-ai-tells.sh|skills/humanize-en/scripts/detect-ai-tells.sh
plugin/skills/humanize-en/tests/fixture-ai-heavy.md|skills/humanize-en/tests/fixture-ai-heavy.md
plugin/skills/humanize-en/tests/fixture-clean.md|skills/humanize-en/tests/fixture-clean.md
plugin/skills/humanize-en/tests/run-tests.sh|skills/humanize-en/tests/run-tests.sh
plugin/skills/design-brainstorm/SKILL.md|skills/design-brainstorm/SKILL.md
plugin/skills/design-brainstorm/tests/run-tests.sh|skills/design-brainstorm/tests/run-tests.sh
plugin/skills/refactor-snapshot/SKILL.md|skills/refactor-snapshot/SKILL.md
plugin/skills/refactor-snapshot/scripts/capture.sh|skills/refactor-snapshot/scripts/capture.sh
plugin/skills/refactor-snapshot/scripts/diff.sh|skills/refactor-snapshot/scripts/diff.sh
plugin/skills/refactor-snapshot/scripts/pre-runs.sh|skills/refactor-snapshot/scripts/pre-runs.sh
plugin/skills/refactor-snapshot/tests/run-tests.sh|skills/refactor-snapshot/tests/run-tests.sh
plugin/skills/macos-ux/SKILL.md|skills/macos-ux/SKILL.md
plugin/skills/macos-ux/references/macos-hig.md|skills/macos-ux/references/macos-hig.md
plugin/skills/project-init/SKILL.md|skills/project-init/SKILL.md
plugin/skills/project-init/scripts/detect-stack.sh|skills/project-init/scripts/detect-stack.sh
plugin/skills/git-repo-init/SKILL.md|skills/git-repo-init/SKILL.md
plugin/skills/git-repo-init/assets/CLAUDE.template.md|skills/git-repo-init/assets/CLAUDE.template.md
plugin/skills/git-repo-init/assets/PROJECT_BRIEF.template.md|skills/git-repo-init/assets/PROJECT_BRIEF.template.md
plugin/skills/git-repo-init/references/git-conventions.md|skills/git-repo-init/references/git-conventions.md
plugin/skills/git-repo-init/references/question-catalog.md|skills/git-repo-init/references/question-catalog.md
plugin/skills/git-repo-init/references/swift-xcode-setup.md|skills/git-repo-init/references/swift-xcode-setup.md
plugin/skills/prompt-builder/SKILL.md|skills/prompt-builder/SKILL.md
plugin/skills/prompt-builder/references/rubric.md|skills/prompt-builder/references/rubric.md
plugin/skills/prompt-builder/references/techniques.md|skills/prompt-builder/references/techniques.md
plugin/skills/prompt-builder/references/templates.md|skills/prompt-builder/references/templates.md
plugin/skills/prompt-builder/references/vibrofer.md|skills/prompt-builder/references/vibrofer.md
plugin/skills/vibe-status/SKILL.md|skills/vibe-status/SKILL.md
plugin/skills/vibe-status/scripts/aggregate.sh|skills/vibe-status/scripts/aggregate.sh
plugin/skills/vibe-status/scripts/harness-runner.sh|skills/vibe-status/scripts/harness-runner.sh
plugin/skills/vibe-status/scripts/chain-memory-section.sh|skills/vibe-status/scripts/chain-memory-section.sh
plugin/skills/vibe-status/tests/run-tests.sh|skills/vibe-status/tests/run-tests.sh
plugin/skills/swiftui-pro/SKILL.md|skills/swiftui-pro/SKILL.md
plugin/skills/find-skills/SKILL.md|skills/find-skills/SKILL.md
plugin/skills/goal-loop/SKILL.md|skills/goal-loop/SKILL.md
plugin/skills/research-prompt/SKILL.md|skills/research-prompt/SKILL.md
plugin/skills/claude-md-generator/SKILL.md|skills/claude-md-generator/SKILL.md
"

printf '%s\n' "$PAIRS" | while IFS='|' read -r src dst; do
  [ -z "$src" ] && continue
  s="$STAGING/$src"; d="$DEST/$dst"
  [ -f "$s" ] || { printf '!! source missing: %s\n' "$src"; continue; }
  if [ ! -f "$d" ]; then
    printf '\n== NEW: %s\n' "$dst"
    [ "$APPLY" -eq 1 ] && { mkdir -p "$(dirname "$d")"; cp "$s" "$d"; printf '   written\n'; }
  elif ! diff -q "$s" "$d" >/dev/null 2>&1; then
    printf '\n== CHANGED: %s\n' "$dst"
    diff -u "$d" "$s" | sed 's/^/   /'
    [ "$APPLY" -eq 1 ] && { cp "$s" "$d"; printf '   overwritten\n'; }
  fi
done

# Preserve executable bit on the shell helpers.
if [ "$APPLY" -eq 1 ]; then
  chmod +x "$DEST/hooks/nightly-guard.sh" "$DEST/hooks/publish-feature.sh" \
    "$DEST/hooks/set-branch-protection.sh" "$DEST/hooks/detect-test-cmd.sh" \
    "$DEST/hooks/roadmap-from-issues.sh" "$DEST/hooks/spec-issue-gate.sh" 2>/dev/null || true
fi

cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this PreToolUse entry to ~/.claude/settings.json (alongside the Edit|Write protect-files entry):

  { "matcher": "Bash",
    "hooks": [ { "type": "command", "command": "\"$HOME\"/.claude/hooks/nightly-guard.sh" } ] }

The staged reference version is staging/user/settings.json. Review the live file first — it may have
diverged. nightly-guard is inert outside a nightly run, so wiring it globally is safe.

--- MANUAL STEP: retired hook cleanup (not auto-applied) ---
backup-before-deploy.sh is retired (issue #38, ADR-0034): never vendored into staging/, so this
sync script has no PAIRS entry and no way to remove it from a deployed tree. If a deployed
~/.claude/hooks/backup-before-deploy.sh still exists, review it (it is wired to no hook event in
settings.json and its body is a hardcoded one-shot backup dated 2026-05-19) and delete it by hand
after confirming you no longer need that specific historical backup snapshot.
NOTE

[ "$APPLY" -eq 0 ] && printf '\n(dry-run — no files written. Re-run with --apply after reviewing.)\n'
exit 0
