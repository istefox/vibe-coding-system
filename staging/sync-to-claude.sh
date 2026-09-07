#!/bin/bash
# sync-to-claude v1.0 (ADR-0022 Phase 5) — copy the autopilot blueprint into ~/.claude.
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

# ---------------------------------------------------------------------------------------------
# ADR-0127 §D2.1 — legacy autopilot wiring gate. REFUSES --apply, it does not merely warn.
#
# The rename nightly-* -> autopilot-* moves two hooks that settings.json wires BY ABSOLUTE PATH,
# and settings.json is deliberately outside PAIRS (ADR-0025). The obvious reading of that risk is
# wrong in the direction that matters: this script NEVER DELETES. It copies PAIRS entries, so
# after --apply the deployed tree holds BOTH the stale nightly-guard.sh and the new
# autopilot-guard.sh, with settings.json still naming the stale one. That hook keys off
# .claude/nightly-state/active, which nothing writes any more — so it fires on every git push,
# finds no marker, and exits 0 INERT. A missing file would error; this produces no signal at all.
#
# So the remediation has two halves and both are printed: edit settings.json, and delete the stale
# deployed hooks by hand. The deletion cannot be automated here without giving this script a
# delete path it has never had, which is a larger decision than this ADR should take (the same
# by-hand precedent the file already sets for the dated settings.json backup below).
#
# Absent settings.json is NOT a refusal: that is a fresh install, and the wiring block near the
# end of this script already prints the MANUAL step for it. Unreadable is distinguished from
# clean — an unread file is not a clean file.
_legacy_wiring() {
  _s="$DEST/settings.json"
  [ -e "$_s" ] || { printf 'absent'; return; }
  [ -r "$_s" ] || { printf 'unreadable'; return; }
  if grep -q 'nightly-guard\|nightly-disarm' "$_s" 2>/dev/null; then printf 'legacy'; else printf 'clean'; fi
}
_LW=$(_legacy_wiring)
_STALE=""
[ -f "$DEST/hooks/nightly-guard.sh" ]  && _STALE="$_STALE $DEST/hooks/nightly-guard.sh"
[ -f "$DEST/hooks/nightly-disarm.sh" ] && _STALE="$_STALE $DEST/hooks/nightly-disarm.sh"

if [ "$_LW" = "legacy" ] || [ -n "$_STALE" ]; then
  printf '\n=== LEGACY AUTOPILOT WIRING DETECTED (ADR-0127) ===\n'
  [ "$_LW" = "legacy" ] && {
    printf '\n1. %s still wires a renamed hook. Replace the nightly-guard.sh command with:\n' "$DEST/settings.json"
    printf '     "command": "bash ~/.claude/hooks/autopilot-guard.sh"\n'
  }
  [ -n "$_STALE" ] && {
    printf '\n2. Stale deployed hooks remain. This script cannot delete them — remove by hand:\n'
    for _f in $_STALE; do printf '     rm %s\n' "$_f"; done
    printf '   Left in place AND still wired, the old guard runs, finds no nightly-state/active,\n'
    printf '   and exits 0 inert: a PreToolUse guardrail that stops guarding with no error.\n'
  }
  if [ "$APPLY" -eq 1 ]; then
    printf '\nREFUSING --apply. Deploying the rename while the old wiring stands would silently\n'
    printf 'disarm the push guard. Do the steps above, then re-run.\n'
    exit 1
  fi
  printf '\n(dry-run: the above must be resolved before --apply will proceed.)\n'
fi

if [ "$_LW" = "unreadable" ]; then
  printf '\n!! %s exists but could not be read — the legacy-wiring check DID NOT RUN.\n' "$DEST/settings.json"
  printf '   That is not the same as finding it clean.\n'
  [ "$APPLY" -eq 1 ] && { printf '   REFUSING --apply.\n'; exit 1; }
fi

# src|dst pairs (dst relative to ~/.claude). Scripts land in hooks/ (this deployment's convention).
# Exception: user/CLAUDE.md is the only non-plugin/ entry. user/settings.json stays out on
# purpose (ADR-0025: machine-local keys need a jq del() pass, not a straight copy).
#
# ZONE ANOMALIES (issue #212). Every entry maps its zone predictably —
# plugin/scripts/X -> hooks/X, plugin/skills/X -> skills/X, plugin/agents/X -> agents/X,
# user/X -> X — except the two declared below. They must be DECLARED here rather than merely
# tolerated, because an undeclared one costs adjudication time every time a path check runs over
# staging and reports it as a miss, and because the plausible "fix" is to repoint the reference at
# the staging path, which breaks the deployed invocation.
#
# pairs-zone-anomaly: plugin/scripts/hook-verify-workflow.sh plugin/scripts/usage-report.py
#
#   hook-verify-workflow.sh -> skills/concept-to-code/scripts/
#     Vendored FLAT in staging under ADR-0016 and kept there by ADR-0024, which refuses to create a
#     second source of truth. So staging/plugin/skills/concept-to-code/scripts/ does NOT contain it
#     and concept-to-code/SKILL.md references it at its DEPLOYED path. That is correct; do not
#     "normalise" either side.
#   usage-report.py -> scripts/
#     A plain script invoked by usage-daily-hint.sh at $HOME/.claude/scripts/usage-report.py, not a
#     hook entry point, so hooks/ would be the wrong zone.
#
# pairs-completeness.test.sh derives this set from PAIRS and requires each member to appear in the
# declaration line above — a THIRD anomaly fails there instead of being discovered by an audit.
#
# DEPLOYED-ONLY REGISTRY (issue #222, ADR-0087). Some skills exist in ~/.claude/skills/ and are
# deliberately NOT vendored into staging/ — not forgotten, declared. The count is deliberately not
# stated here: the registry grows, and a prose count that stops tracking its population has stopped
# measuring (ADR-0110's PMP2 re-anchoring, ADR-0120's RH2 lesson). DO1 below is the vacuity guard.
#
# ADR-0077's rule that a waiver
# travels with the file it excuses cannot apply here: the excused file is absent from staging/ by
# construction, so there is nothing for the waiver to travel with. The declaration lives here
# instead, beside the zone-anomaly block above, in the file that decides what reaches ~/.claude.
#
# pairs-completeness.test.sh derives this registry at run time (DO1-DO4): every declared name must
# be genuinely absent from staging/plugin/skills/, and every reason must be >= 40 characters. The
# separator between name and reason is an em dash ("—"), not a hyphen.
#
# deployed-only: agent-design — proprietary book-derived knowledge base; its own frontmatter `license:` field says so.
# deployed-only: auto-learning — symlink into a foreign repository (steve-skills/auto-learning) carrying its own git remote and history; same class as website-auditor below, and vendoring it would duplicate a project that is already versioned elsewhere (ADR-0024/0025's drift).
# deployed-only: daily-close — personal daily-routine skill bound to local connectors (Obsidian, NotePlan, DEVONthink, ms365).
# deployed-only: daily-open — personal daily-routine skill bound to local connectors (Obsidian, NotePlan, DEVONthink, ms365), same class as daily-close.
# deployed-only: impeccable — third-party skill installed as a static local copy (not a symlinked repo, not a plugin); cited in ADR-0172 as the reference-split scale proof, never vendored here.
# deployed-only: project-tasks — symlink into a foreign repository (Developer/Skills/tasks, github.com/istefox/Skills) carrying its own git remote, history and PR-based workflow; migrated out of this repo's vendored surface after ADR-0153, ratified by ADR-0191, same class as auto-learning/website-auditor above.
# deployed-only: vibiso-intake — front end of a different project's intake contract (vibiso-system ADR-002).
# deployed-only: website-auditor — symlink into a foreign repository (steve-skills/website_auditor); moves ADR-0024 section 2.1's exclusion out of prose.
PAIRS="
user/CLAUDE.md|CLAUDE.md
plugin/agents/architect.md|agents/architect.md
plugin/agents/coder.md|agents/coder.md
plugin/agents/debugger.md|agents/debugger.md
plugin/agents/doc-writer.md|agents/doc-writer.md
plugin/agents/refactorer.md|agents/refactorer.md
plugin/agents/researcher.md|agents/researcher.md
plugin/agents/reviewer.md|agents/reviewer.md
plugin/agents/tester.md|agents/tester.md
user/rules/parallelization.md|rules/parallelization.md
user/rules/python.md|rules/python.md
user/rules/shell.md|rules/shell.md
user/rules/sql-migrations.md|rules/sql-migrations.md
user/rules/tools.md|rules/tools.md
user/rules/swift.md|rules/swift.md
user/rules/typescript-react.md|rules/typescript-react.md
user/rules/web-vanilla.md|rules/web-vanilla.md
plugin/skills/adr-writer/SKILL.md|skills/adr-writer/SKILL.md
plugin/skills/code-review-checklist/SKILL.md|skills/code-review-checklist/SKILL.md
plugin/skills/fastapi-react-vibe/SKILL.md|skills/fastapi-react-vibe/SKILL.md
plugin/skills/interview-driver/SKILL.md|skills/interview-driver/SKILL.md
plugin/skills/brief-to-app/SKILL.md|skills/brief-to-app/SKILL.md
plugin/skills/swift-vibe/SKILL.md|skills/swift-vibe/SKILL.md
plugin/scripts/auto-format.sh|hooks/auto-format.sh
plugin/scripts/chain-memory-capture.sh|hooks/chain-memory-capture.sh
plugin/scripts/autopilot-guard.sh|hooks/autopilot-guard.sh
plugin/scripts/autopilot-disarm.sh|hooks/autopilot-disarm.sh
plugin/scripts/autopilot-migrate.sh|hooks/autopilot-migrate.sh
plugin/scripts/protect-files.sh|hooks/protect-files.sh
plugin/scripts/publish-feature.sh|hooks/publish-feature.sh
plugin/scripts/required-checks-audit.sh|hooks/required-checks-audit.sh
plugin/scripts/set-branch-protection.sh|hooks/set-branch-protection.sh
plugin/skills/autopilot/SKILL.md|skills/autopilot/SKILL.md
plugin/skills/autopilot/scripts/scope-args-parse.sh|skills/autopilot/scripts/scope-args-parse.sh
plugin/skills/autopilot/scripts/scope-file-read.sh|skills/autopilot/scripts/scope-file-read.sh
plugin/skills/autopilot/scripts/prep-row-select.sh|skills/autopilot/scripts/prep-row-select.sh
plugin/skills/autopilot/tests/run-tests.sh|skills/autopilot/tests/run-tests.sh
plugin/scripts/tests/phase1.test.sh|hooks/tests/phase1.test.sh
plugin/skills/project-conductor/SKILL.md|skills/project-conductor/SKILL.md
plugin/skills/project-conductor/references/steps-4-7-chain-execution.md|skills/project-conductor/references/steps-4-7-chain-execution.md
plugin/skills/project-conductor/scripts/conductor-args.sh|skills/project-conductor/scripts/conductor-args.sh
plugin/skills/project-conductor/scripts/h16-direction-check.sh|skills/project-conductor/scripts/h16-direction-check.sh
plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh|skills/project-conductor/scripts/mark-roadmap-skipped.sh
project-templates/ci/ci.yml|templates/ci.yml
plugin/scripts/detect-test-cmd.sh|hooks/detect-test-cmd.sh
plugin/scripts/roadmap-from-issues.sh|hooks/roadmap-from-issues.sh
plugin/scripts/spec-issue-gate.sh|hooks/spec-issue-gate.sh
plugin/scripts/untrusted-input-scan.sh|hooks/untrusted-input-scan.sh
plugin/scripts/tests/prep.test.sh|hooks/tests/prep.test.sh
plugin/scripts/hook-verify-workflow.sh|skills/concept-to-code/scripts/hook-verify-workflow.sh
plugin/scripts/tests/hook-verify-workflow.test.sh|hooks/tests/hook-verify-workflow.test.sh
plugin/skills/spec-from-issue/SKILL.md|skills/spec-from-issue/SKILL.md
plugin/scripts/stop-gate.sh|hooks/stop-gate.sh
plugin/scripts/pre-flight-pattern-enforce.sh|hooks/pre-flight-pattern-enforce.sh
plugin/scripts/write-scope-enforce.sh|hooks/write-scope-enforce.sh
plugin/scripts/memory-store-guard.sh|hooks/memory-store-guard.sh
plugin/scripts/reviewer-write-scope.sh|hooks/reviewer-write-scope.sh
plugin/scripts/coder-memory-scope.sh|hooks/coder-memory-scope.sh
plugin/scripts/agent-command-scope.sh|hooks/agent-command-scope.sh
plugin/scripts/test-write-scope.sh|hooks/test-write-scope.sh
plugin/scripts/db-backup-guardrail.sh|hooks/db-backup-guardrail.sh
plugin/scripts/worktree-git-guardrail.sh|hooks/worktree-git-guardrail.sh
plugin/scripts/approve-test-cmd.sh|hooks/approve-test-cmd.sh
plugin/scripts/approve-acceptance-cmd.sh|hooks/approve-acceptance-cmd.sh
plugin/scripts/acceptance-run.sh|hooks/acceptance-run.sh
plugin/scripts/acceptance-adapter-swift.sh|hooks/acceptance-adapter-swift.sh
plugin/scripts/acceptance-declare.sh|hooks/acceptance-declare.sh
plugin/scripts/session-context-inject.sh|hooks/session-context-inject.sh
plugin/scripts/ensure-state-dir.sh|hooks/ensure-state-dir.sh
plugin/scripts/mark-dirty.sh|hooks/mark-dirty.sh
plugin/scripts/post-write-check.sh|hooks/post-write-check.sh
plugin/scripts/dispatch-state.sh|hooks/dispatch-state.sh
plugin/scripts/secret-scan.sh|hooks/secret-scan.sh
plugin/scripts/dependency-scan.sh|hooks/dependency-scan.sh
plugin/scripts/ci-tier.sh|hooks/ci-tier.sh
plugin/scripts/external-dependency-check.sh|hooks/external-dependency-check.sh
plugin/scripts/interface-check.sh|hooks/interface-check.sh
plugin/scripts/vendor-checks.sh|hooks/vendor-checks.sh
plugin/scripts/prompt-en-prose-detect.sh|hooks/prompt-en-prose-detect.sh
plugin/scripts/reset-gate-counter.sh|hooks/reset-gate-counter.sh
plugin/scripts/usage-daily-hint.sh|hooks/usage-daily-hint.sh
plugin/scripts/codex-reviewer.sh|hooks/codex-reviewer.sh
plugin/scripts/codex-tester.sh|hooks/codex-tester.sh
plugin/scripts/usage-report.py|scripts/usage-report.py
plugin/scripts/precompact-guard.sh|hooks/precompact-guard.sh
plugin/scripts/commit-outcome-backstop.sh|hooks/commit-outcome-backstop.sh
plugin/scripts/instructions-loaded-canon.sh|hooks/instructions-loaded-canon.sh
plugin/scripts/instructions-loaded-log.sh|hooks/instructions-loaded-log.sh
plugin/scripts/instructions-loaded-verify.sh|hooks/instructions-loaded-verify.sh
plugin/scripts/context-occupancy.sh|hooks/context-occupancy.sh
plugin/scripts/migrate-trust-paths.sh|hooks/migrate-trust-paths.sh
plugin/scripts/tests/db-backup-guardrail.sh|hooks/tests/db-backup-guardrail.sh
plugin/scripts/tests/pre-flight-pattern-enforce.sh|hooks/tests/pre-flight-pattern-enforce.sh
plugin/scripts/tests/run-hook-tests.sh|hooks/tests/run-hook-tests.sh
plugin/skills/concept-to-code/SKILL.md|skills/concept-to-code/SKILL.md
plugin/skills/concept-to-code/references/step5-implementation.md|skills/concept-to-code/references/step5-implementation.md
plugin/skills/concept-to-code/references/hitl-gates.md|skills/concept-to-code/references/hitl-gates.md
plugin/skills/concept-to-code/scripts/agent-metrics.sh|skills/concept-to-code/scripts/agent-metrics.sh
plugin/skills/concept-to-code/scripts/commit-outcome-check.sh|skills/concept-to-code/scripts/commit-outcome-check.sh
plugin/skills/concept-to-code/scripts/detect-macos.sh|skills/concept-to-code/scripts/detect-macos.sh
plugin/skills/concept-to-code/scripts/ui-file-detect.sh|skills/concept-to-code/scripts/ui-file-detect.sh
plugin/skills/concept-to-code/scripts/diff-budget-check.sh|skills/concept-to-code/scripts/diff-budget-check.sh
plugin/skills/concept-to-code/scripts/gate0-detect.sh|skills/concept-to-code/scripts/gate0-detect.sh
plugin/skills/concept-to-code/scripts/manifest-init.sh|skills/concept-to-code/scripts/manifest-init.sh
plugin/skills/concept-to-code/scripts/manifest-set-artifact.sh|skills/concept-to-code/scripts/manifest-set-artifact.sh
plugin/skills/concept-to-code/scripts/manifest-set-flag.sh|skills/concept-to-code/scripts/manifest-set-flag.sh
plugin/skills/concept-to-code/scripts/manifest-field-state.sh|skills/concept-to-code/scripts/manifest-field-state.sh
plugin/skills/concept-to-code/scripts/manifest-entry-state.sh|skills/concept-to-code/scripts/manifest-entry-state.sh
plugin/skills/concept-to-code/scripts/permission-mode-state.sh|skills/concept-to-code/scripts/permission-mode-state.sh
plugin/skills/concept-to-code/scripts/manifest-set-gate.sh|skills/concept-to-code/scripts/manifest-set-gate.sh
plugin/skills/concept-to-code/scripts/manifest-transition.sh|skills/concept-to-code/scripts/manifest-transition.sh
plugin/skills/concept-to-code/scripts/manifest-validate.sh|skills/concept-to-code/scripts/manifest-validate.sh
plugin/skills/concept-to-code/scripts/plan-task-predicate.awk|skills/concept-to-code/scripts/plan-task-predicate.awk
plugin/skills/concept-to-code/scripts/plan-budget-parse.awk|skills/concept-to-code/scripts/plan-budget-parse.awk
plugin/skills/concept-to-code/scripts/spec-archive.sh|skills/concept-to-code/scripts/spec-archive.sh
plugin/skills/concept-to-code/scripts/spec-id-predicate.awk|skills/concept-to-code/scripts/spec-id-predicate.awk
plugin/skills/concept-to-code/scripts/spec-normalize-ids.sh|skills/concept-to-code/scripts/spec-normalize-ids.sh
plugin/skills/concept-to-code/scripts/plan-tasks.sh|skills/concept-to-code/scripts/plan-tasks.sh
plugin/skills/concept-to-code/scripts/step5-brief.sh|skills/concept-to-code/scripts/step5-brief.sh
plugin/skills/concept-to-code/scripts/repo-rel-path.sh|skills/concept-to-code/scripts/repo-rel-path.sh
plugin/skills/concept-to-code/scripts/spec-coverage.sh|skills/concept-to-code/scripts/spec-coverage.sh
plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh|skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh
plugin/skills/concept-to-code/scripts/design-coverage.sh|skills/concept-to-code/scripts/design-coverage.sh
plugin/skills/concept-to-code/scripts/design-url-check.sh|skills/concept-to-code/scripts/design-url-check.sh
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
plugin/skills/claude-design-brief/SKILL.md|skills/claude-design-brief/SKILL.md
plugin/skills/claude-design-brief/tests/run-tests.sh|skills/claude-design-brief/tests/run-tests.sh
plugin/skills/refactor-snapshot/SKILL.md|skills/refactor-snapshot/SKILL.md
plugin/skills/refactor-snapshot/scripts/capture.sh|skills/refactor-snapshot/scripts/capture.sh
plugin/skills/refactor-snapshot/scripts/diff.sh|skills/refactor-snapshot/scripts/diff.sh
plugin/skills/refactor-snapshot/scripts/pre-runs.sh|skills/refactor-snapshot/scripts/pre-runs.sh
plugin/skills/refactor-snapshot/tests/run-tests.sh|skills/refactor-snapshot/tests/run-tests.sh
plugin/skills/macos-ux/SKILL.md|skills/macos-ux/SKILL.md
plugin/skills/macos-ux/references/macos-hig.md|skills/macos-ux/references/macos-hig.md
plugin/skills/project-init/SKILL.md|skills/project-init/SKILL.md
plugin/skills/project-init/scripts/detect-stack.sh|skills/project-init/scripts/detect-stack.sh
plugin/skills/project-init/scripts/detect-canonical-mechanism.sh|skills/project-init/scripts/detect-canonical-mechanism.sh
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
plugin/skills/vibe-status/scripts/temp-branch-reconcile.sh|skills/vibe-status/scripts/temp-branch-reconcile.sh
plugin/skills/vibe-status/tests/run-tests.sh|skills/vibe-status/tests/run-tests.sh
plugin/skills/swiftui-pro/SKILL.md|skills/swiftui-pro/SKILL.md
plugin/skills/find-skills/SKILL.md|skills/find-skills/SKILL.md
plugin/skills/goal-loop/SKILL.md|skills/goal-loop/SKILL.md
plugin/skills/research-prompt/SKILL.md|skills/research-prompt/SKILL.md
plugin/skills/claude-md-generator/SKILL.md|skills/claude-md-generator/SKILL.md
plugin/skills/security-audit/SKILL.md|skills/security-audit/SKILL.md
plugin/skills/ui-layout-audit/SKILL.md|skills/ui-layout-audit/SKILL.md
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
  chmod +x "$DEST/hooks/precompact-guard.sh" "$DEST/hooks/commit-outcome-backstop.sh" "$DEST/hooks/autopilot-guard.sh" "$DEST/hooks/publish-feature.sh" "$DEST/hooks/test-write-scope.sh" \
    "$DEST/hooks/set-branch-protection.sh" "$DEST/hooks/detect-test-cmd.sh" \
    "$DEST/hooks/roadmap-from-issues.sh" "$DEST/hooks/spec-issue-gate.sh" \
    "$DEST/hooks/write-scope-enforce.sh" \
    "$DEST/hooks/agent-command-scope.sh" "$DEST/hooks/vendor-checks.sh" \
    "$DEST/hooks/autopilot-disarm.sh" "$DEST/hooks/autopilot-migrate.sh" \
    "$DEST/hooks/required-checks-audit.sh" "$DEST/hooks/dispatch-state.sh" 2>/dev/null || true
fi

# DEPLOYED SKILL REPORT (issue #222, ADR-0087, R-06). Every directory (or symlink resolving to a
# directory — website-auditor's shape) under $DEST/skills/ that is neither vendored via PAIRS nor
# declared in the deployed-only registry above is reported here, once. This is a REPORT, distinct
# from the MANUAL STEP blocks below: it never sets MANUAL=1 and never affects the exit code — R-06
# says the report never blocks the sync. $HOME-dependent and unverifiable in CI by construction
# (ADR-0087 §D3), the same asymmetry ADR-0084 already accepted for the deployed-vs-staged check.
if [ -d "$DEST/skills" ]; then
  VENDORED_SKILLS=$(printf '%s\n' "$PAIRS" | awk -F'|' '$1 ~ /^plugin\/skills\/[^\/]+\/SKILL\.md$/ { n=$1; sub(/^plugin\/skills\//,"",n); sub(/\/SKILL\.md$/,"",n); print n }')
  DECLARED_SKILLS=$(grep "^# *deployed-only: " "$STAGING/sync-to-claude.sh" 2>/dev/null | sed 's/^# *deployed-only: *//' | cut -d' ' -f1)
  UNDECLARED=""
  for _skill_dir in "$DEST"/skills/*/; do
    [ -d "$_skill_dir" ] || continue
    _sname=$(basename "$_skill_dir")
    _sknown=0
    for _v in $VENDORED_SKILLS; do [ "$_v" = "$_sname" ] && _sknown=1; done
    for _r in $DECLARED_SKILLS; do [ "$_r" = "$_sname" ] && _sknown=1; done
    [ "$_sknown" -eq 0 ] && UNDECLARED="$UNDECLARED $_sname"
  done
  if [ -n "$UNDECLARED" ]; then
    printf '\n-- REPORT: deployed skill(s) neither vendored nor declared --\n'
    for _u in $UNDECLARED; do printf '%s\n' "$_u"; done
  fi
fi

# MANUAL STEP notices are gated on the state they describe. They used to print unconditionally,
# and on 2026-07-25 both were found already done — printing them every run made them fixed noise,
# which is what buries a notice that actually matters. Each block below fires only when its step
# is genuinely outstanding.
MANUAL=0

# Wiring: absent grep hit OR no settings.json at all. Fail-safe direction is to print — a state
# that cannot be confirmed must not read as "already wired". grep, not jq: the script has no jq
# dependency today and this check does not justify adding one.
if ! grep -q 'autopilot-guard' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this PreToolUse entry to ~/.claude/settings.json (alongside the Edit|Write protect-files entry):

  { "matcher": "Bash",
    "hooks": [ { "type": "command", "command": "\"$HOME\"/.claude/hooks/autopilot-guard.sh" } ] }

The staged reference version is staging/user/settings.json. Review the live file first — it may have
diverged. autopilot-guard is inert outside an autopilot run, so wiring it globally is safe.
NOTE
fi

if ! grep -q 'write-scope-enforce' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this PreToolUse entry to ~/.claude/settings.json (alongside the pre-flight-pattern-enforce entry):

  { "matcher": "Edit|Write|MultiEdit",
    "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/write-scope-enforce.sh" } ] }

write-scope-enforce (issue #87, ADR-0016 Addendum 2026-07-25d) denies a parallel fix agent any
write outside the file it was assigned. It is inert by construction: with no write-scope line in
an agent's transcript it allows and exits, so wiring it globally affects nothing but Step 6
Phase 3. Until this entry exists the hook is deployed but never invoked.
NOTE
fi

if ! grep -q 'memory-store-guard' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this PreToolUse entry to ~/.claude/settings.json (alongside the write-scope-enforce entry):

  { "matcher": "Edit|Write|MultiEdit",
    "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/memory-store-guard.sh" } ] }

memory-store-guard (VCS-055 Phase 2, ADR-0038 Correction 2026-08-30) denies a sub-agent (one with
.agent_id set) any write into the orchestrator's curated auto-memory store
(~/.claude/projects/*/memory/) — the exact failure mode ADR-0013's 2026-05-25 pilot hit. It is
inert by construction: no .agent_id, no gate, and a sub-agent writing to its OWN memory directory
is unaffected. Required BEFORE running the guarded native-memory re-pilot on `reviewer`
(VCS-055 Phase 2.2). Until this entry exists the hook is deployed but never invoked.
NOTE
fi

if ! grep -q 'reviewer-write-scope' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this PreToolUse entry to ~/.claude/settings.json (alongside the memory-store-guard entry):

  { "matcher": "Edit|Write|MultiEdit",
    "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/reviewer-write-scope.sh" } ] }

reviewer-write-scope (VCS-055 Phase 2.3, ADR-0182) denies reviewer any write outside its own
.claude/agent-memory/reviewer/ directory. reviewer's `memory: project` grant carries Edit/Write
with no path restriction at the tool-schema level (confirmed live 2026-08-30) — this hook is the
enforcement, not the frontmatter grant, of the boundary review-triage-fix/SKILL.md's advisor call
relies on. It is inert by construction: gated on .agent_type == "reviewer", so no other agent or
the orchestrator is affected. Required for the reviewer native-memory adoption to be safe. Until
this entry exists the hook is deployed but never invoked.
NOTE
fi

if ! grep -q 'coder-memory-scope' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this PreToolUse entry to ~/.claude/settings.json (alongside the reviewer-write-scope entry):

  { "matcher": "Edit|Write|MultiEdit",
    "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/coder-memory-scope.sh" } ] }

coder-memory-scope (VCS-057, ADR-0184) confines coder's memory writes to its own per-dispatch
shard directory (.claude/agent-memory/coder/topics/), never MEMORY.md and never another agent's
memory dir. Measured live in a throwaway scratch repo: coder's `memory: project` write DOES
persist onto the feature branch via Step 5's merge-back and IS re-injected on the next dispatch —
but two parallel coder dispatches sharing one MEMORY.md produce a real merge conflict. This hook
is the enforcement of the per-dispatch shard discipline coder.md now instructs; unlike
reviewer-write-scope's whitelist shape, it is inert for everything coder writes OUTSIDE
.claude/agent-memory/ (ordinary source writes are coder's whole job). It is inert by construction:
gated on .agent_type == "coder", so no other agent or the orchestrator is affected. Required for
the coder native-memory adoption to be safe under a parallel fan-out. Until this entry exists the
hook is deployed but never invoked.
NOTE
fi

if grep -q 'agent-write-scope' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: stale hook wiring (not auto-removed) ---
~/.claude/settings.json still has a PreToolUse entry invoking hooks/agent-write-scope.sh:

  { "matcher": "Write|Edit|MultiEdit",
    "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/agent-write-scope.sh" } ] }

agent-write-scope.sh no longer exists as a separate script (VCS-046): its architect-scope logic
(issue #58, gap 2) was merged into test-write-scope.sh, which already gates the architect too —
both hooks opened by extracting .agent_type via one jq call and bailing on a mismatch, so wiring
them as two separate PreToolUse entries cost a second bash+jq process spawn on every single
Edit/Write/MultiEdit for no agent-type-gated reason. A leftover entry invokes a deleted script and
fails file-not-found on every one of those calls. Remove this PreToolUse entry from
~/.claude/settings.json by hand; the test-write-scope entry below needs no change, it already does
this work.
NOTE
fi

if ! grep -q 'agent-command-scope' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this PreToolUse entry to ~/.claude/settings.json (alongside the agent-write-scope entry):

  { "matcher": "Bash",
    "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/agent-command-scope.sh" } ] }

agent-command-scope (issue #58, gap 1) denies architect and reviewer any mutating git command,
directly or wrapped in bash -c / python3 -c / awk. Their read-only git grants are otherwise
subsumed by the interpreters they hold for verification. Inert for every other agent type. It is a
guardrail against a shortcut, NOT a sandbox — see ADR-0045's threat model before relying on it.
Until this entry exists the hook is deployed but never invoked.
NOTE
fi

if ! grep -q 'test-write-scope' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this PreToolUse entry to ~/.claude/settings.json (alongside the agent-command-scope entry):

  { "matcher": "Edit|Write|MultiEdit",
    "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/test-write-scope.sh" } ] }

test-write-scope (issue #103, ADR-0049 generator/verifier separation) denies the coder agent any
Edit/Write/MultiEdit into a path the test-file predicate matches, since test files are now the
tester stage's responsibility, not the coder's. It reads only the first user entry of the
dispatched agent's transcript, closing the self-arming defect ADR-0049 found in
write-scope-enforce.sh (a full-transcript scan can bind on its own grep pattern). Inert for every
other agent type and for a transcript carrying no scope marker. Guardrail against a shortcut, NOT a
sandbox — same threat model as agent-command-scope (ADR-0045). Until this entry exists the hook is
deployed but never invoked.
NOTE
fi

if ! grep -q 'precompact-guard' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
PreCompact is not currently in the hooks block at all — this adds a NEW event key, not an entry
alongside an existing one. Add this to ~/.claude/settings.json's top-level "hooks" object:

  "PreCompact": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/precompact-guard.sh" } ] }
  ]

precompact-guard (issue #112, ADR-0058) forces a chain-history handoff write when a manifest's
current_step is a dispatch state, and refuses the FIRST PreCompact of a compaction cycle so that
write has landed before compaction proceeds. The refusal is ONE-SHOT BY DESIGN — the second
PreCompact in the same cycle always proceeds, regardless of manifest state (§D2: an unbounded
refusal would strand the session instead of protecting it, since PreCompact fires because the
context window is already full). Fails open on every error. Until this entry exists the hook is
deployed but never invoked, and the session-preservation half of this feature does nothing.
NOTE
fi

if ! grep -q 'usage-daily-hint' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this Stop entry to ~/.claude/settings.json (alongside the stop-gate entry):

  { "hooks": [ { "type": "command", "command": "\"$HOME\"/.claude/hooks/usage-daily-hint.sh" } ] }

usage-daily-hint (issue #112, ADR-0058 §D4) is the measurement half of the context-occupancy
feature: it reports approximate context-window occupancy (via context-occupancy.sh) plus the daily
usage diff, through additionalContext, and never emits a decision field — it cannot block, unlike
stop-gate.sh which shares this event. Occupancy is reported, never gated (§D4: it correlates with
instruction-following degradation but does not determine it, so a threshold gate would be a
heuristic deciding to block, the exact shape ADR-0051/0053/0054 already rejected). Until this entry
exists the hook is deployed but never invoked, and occupancy is never observable to a human or a
later gate — precompact-guard.sh (above) still protects mid-flight chain state either way; only the
reporting half is silent.
NOTE
fi

if ! grep -q 'commit-outcome-backstop' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this PostToolUse entry to ~/.claude/settings.json (alongside the chain-memory-capture / agentwake
heartbeat entries):

  { "matcher": "Skill",
    "hooks": [ { "type": "command", "command": "\"$HOME\"/.claude/hooks/commit-outcome-backstop.sh" } ] }

commit-outcome-backstop (2026-08-23-commit-outcome-backstop-hook, ADR-0168) reads Step 7.1's
classification of a manifest's commit outcome a second time, independent of the orchestrator
following the SKILL.md instruction to run it. It is report-only — it never blocks — and inert
outside a project with docs/manifests/: a manifest more than 24h old, or not sitting at a
commit-stage current_step, never triggers a report. Until this entry exists the hook is deployed
but never invoked.
NOTE
fi

if ! grep -q 'InstructionsLoaded' "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this InstructionsLoaded entry to ~/.claude/settings.json's top-level "hooks" object:

  "InstructionsLoaded": [
    { "matcher": "session_start|nested_traversal|path_glob_match|include|compact",
      "hooks": [ { "type": "command", "command": "\"$HOME\"/.claude/hooks/instructions-loaded-log.sh" } ] }
  ]

instructions-loaded-log (ADR-0171) records one JSONL line per instruction file loaded into a
session's context, so a later query (instructions-loaded-verify.sh) can measure whether a specific
correction actually landed instead of trusting Claude Code's documented loading behaviour on faith.
Observational only — the event's own exit code is ignored by Claude Code, so this hook has no
decision to make even in principle. Until this entry exists the hook is deployed but never invoked,
and instructions-loaded-verify.sh has nothing to read.
NOTE
fi

# baseRef: gated on the parsed JSON value, not a key-presence grep — a present-but-wrong value
# ("fresh") must fire exactly like an absent key, so a grep for the key name alone would silently
# pass the case that matters most (ADR-0068 §D1, issue #176). Fail-safe direction is to print: a
# missing or unparseable settings.json must not read as "already correct".
if ! python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if d.get('worktree', {}).get('baseRef') == 'head' else 1)
" "$DEST/settings.json" 2>/dev/null; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: settings key (not auto-applied) ---
Add this to ~/.claude/settings.json's top-level object (or correct its value if already present):

  "worktree": { "baseRef": "head" }

Native, documented mechanism (code.claude.com/docs/en/worktrees): a subagent worktree forks from
the default branch unless this key is set to "head" (ADR-0068 §D1). sync-to-claude.sh never edits
settings.json (ADR-0025), so this key reaches the live file only by hand. Until this key is set, every modification agent's worktree forks from the default branch and the chain's Step 5 pre-flight will refuse to dispatch.
NOTE
fi

if [ -f "$DEST/hooks/backup-before-deploy.sh" ]; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: retired hook cleanup (not auto-applied) ---
backup-before-deploy.sh is retired (issue #38, ADR-0034): never vendored into staging/, so this
sync script has no PAIRS entry and no way to remove it from a deployed tree. The deployed
~/.claude/hooks/backup-before-deploy.sh still exists — review it (it is wired to no hook event in
settings.json and its body is a hardcoded one-shot backup dated 2026-05-19) and delete it by hand
after confirming you no longer need that specific historical backup snapshot.
NOTE
fi

if [ -f "$DEST/skills/concept-to-code/scripts/agent-notes-harvest.sh" ] || [ -f "$DEST/skills/concept-to-code/tests/agent-notes-roundtrip.sh" ]; then
  MANUAL=1
  cat <<'NOTE'

--- MANUAL STEP: retired ADR-0012 memory helper cleanup (not auto-applied) ---
agent-notes-harvest.sh and its round-trip harness agent-notes-roundtrip.sh are retired (VCS-056,
ADR-0183): every agent that used the mediated inject/harvest mechanism they implemented
(architect, debugger, reviewer) now carries native `memory:` persistence instead. Both were
removed from staging/, so this sync script has no PAIRS entry and no way to remove them from a
deployed tree. Delete the deployed
~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh and
~/.claude/skills/concept-to-code/tests/agent-notes-roundtrip.sh by hand.
NOTE
fi

# Say so explicitly. Printing nothing would be indistinguishable from having skipped the checks.
[ "$MANUAL" -eq 0 ] && printf '\nno manual steps outstanding (hook wiring present, worktree.baseRef set to "head", no retired hook to remove).\n'

[ "$APPLY" -eq 0 ] && printf '\n(dry-run — no files written. Re-run with --apply after reviewing.)\n'
exit 0
