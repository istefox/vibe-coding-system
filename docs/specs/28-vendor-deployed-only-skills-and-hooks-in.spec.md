# SPEC — Vendor deployed-only skills and hooks into staging

Source: GitHub issue #28

## Objectives
1. Vendor the deployed-only executable surface (16 skills, 12 hooks plus their tests) from `~/.claude` into `staging/`, byte-identical at vendoring time.
2. Extend `staging/sync-to-claude.sh` PAIRS with one entry per vendored file so repo-side fixes can reach deployment.
3. Give the rest of the audit-fix roadmap a versioned source to patch (audit finding 3.38: today only 15 files are covered; a machine loss loses the core chain with no recovery copy).

## Scope
In:
- Copy skills into `staging/plugin/skills/<name>/` (full directory: SKILL.md, scripts/, tests/, references/, assets/; skip binary assets and any `*.bak-*` file): concept-to-code, autopilot-build, deep-refactor, review-triage-fix, claude-md-slim, clean-public-repo, humanize-en, design-brainstorm, refactor-snapshot, macos-ux, project-init, vibe-status (SKILL.md, aggregate.sh, harness-runner.sh, tests), git-repo-init, prompt-builder, swiftui-pro (SKILL.md only), find-skills.
- Copy hooks from `~/.claude/hooks/` into `staging/plugin/scripts/`: stop-gate.sh, pre-flight-pattern-enforce.sh, db-backup-guardrail.sh, approve-test-cmd.sh, session-context-inject.sh, ensure-state-dir.sh, mark-dirty.sh, post-md-tells-hint.sh, prompt-en-prose-detect.sh, reset-gate-counter.sh, usage-daily-hint.sh, migrate-trust-paths.sh, plus `~/.claude/hooks/tests/`.
- PAIRS extension in `sync-to-claude.sh`; a dry run right after vendoring reports zero diffs.

Out:
- backup-before-deploy.sh (retired by the hook-hardening issue #38) — do NOT vendor.
- website-auditor — a symlink into a different repository, entirely out of scope.
- Any write under `~/.claude` (reading `~/.claude` as copy source is authorized for this feature; all writes stay inside this repository).
- Fixing defects in the vendored files (that is the rest of the roadmap).

## Stack
Bash (3.2-compatible, BSD-safe) scripts, Markdown skill files, GitHub Actions docs-ci (markdownlint + link check + shell test harnesses).

## Architecture
- `staging/plugin/skills/<name>/` — one directory per vendored skill.
- `staging/plugin/scripts/` — vendored hook scripts; `staging/plugin/scripts/tests/` gains the hooks test suites where applicable.
- `staging/sync-to-claude.sh` — PAIRS list extended; remains the single deploy path.
- Linter config may gain a scoped ignore for `staging/plugin/skills/` if vendored SKILL.md files fail markdownlint.

## Data model
None.

## API / Interfaces
`staging/sync-to-claude.sh` dry-run/apply contract unchanged; only the PAIRS table grows.

## UI flows
None.

## Edge cases
- Binary assets and `*.bak-*` files inside skill directories must be skipped, not copied.
- swiftui-pro is SKILL.md only, not the full directory.
- vibe-status vendors a named subset (SKILL.md, aggregate.sh, harness-runner.sh, tests).
- website-auditor symlink must not be followed.
- Vendored SKILL.md files may violate markdownlint: either they pass or the config gains a scoped ignore for `staging/plugin/skills/`.

## Success criteria
- [ ] Every listed file exists under `staging/` byte-identical to its deployed copy at vendoring time
- [ ] `sync-to-claude.sh` PAIRS extended with one entry per vendored file; a dry run right after vendoring must report zero diffs
- [ ] No file under `~/.claude` is created, modified, or deleted
- [ ] Existing docs-ci harnesses stay green; markdownlint passes on vendored SKILL.md files or the linter config gains a scoped ignore for `staging/plugin/skills/`
