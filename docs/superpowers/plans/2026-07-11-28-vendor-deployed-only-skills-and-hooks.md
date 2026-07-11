# Plan — Vendor deployed-only skills and hooks into staging

**Date:** 2026-07-11
**ADR:** [ADR-0024](../../architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/28-vendor-deployed-only-skills-and-hooks-in.spec.md`, issue #28)
**Style:** TDD (red → green → checkpoint). Auto mode active, no intermediate HITL inside this plan; commit/push
stay HITL per repo `CLAUDE.md` invariant (see Risk register).

---

## Why "RED" means "self-test the checker," not "fail against the real table"

This feature is a vendoring/copy task: there is no application logic to drive with a failing assertion against
real data, because the "bug" this plan guards against (a PAIRS entry added without its file, or vice versa)
does not exist yet at the start of the work. Task 1 therefore proves the new checker is *correct* by making it
fail against a deliberately-broken synthetic fixture (real RED), then confirms it passes cleanly against the
current, unmodified 15-entry PAIRS table (trivially GREEN — 0 new entries yet). Tasks 2-6 are GREEN-only batches:
each one adds PAIRS entries and their files atomically, so the checker never observes an inconsistent state
between two task boundaries.

## Vendoring mechanics (read once, applies to every task below)

- **Direction:** `cp -p "$HOME/.claude/<deployed-relpath>" "staging/<staging-relpath>"` only. Never write under
  `~/.claude`. `-p` preserves the source's permission bits, so the executable bit on `.sh` files carries over
  automatically — no separate `chmod +x` step needed. `.md`/`.yaml`/`.png` etc. stay non-executable, matching
  the deployed source.
- **PAIRS transformation** (mechanical, apply identically to every new line, matching the existing 15 entries):
  - Hooks: `plugin/scripts/<name>.sh|hooks/<name>.sh`
  - Legacy hook tests: `plugin/scripts/tests/<name>|hooks/tests/<name>` (name unchanged, no `.test.sh` rename)
  - Skills: `plugin/skills/<skill>/<relpath>|skills/<skill>/<relpath>` (same relative path both sides)
- **Append-only:** new PAIRS lines go inside the existing `PAIRS="..."` block in
  `staging/sync-to-claude.sh` (currently lines 19-35). Do not reorder, edit, or remove any of the 15 existing
  lines.
- **Per-task checkpoint (two complementary checks, both must pass before moving to the next task):**
  1. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — structural, CI-safe: every PAIRS `src`
     exists under `staging/`.
  2. `bash staging/sync-to-claude.sh` (dry-run, default, local-only) — the new entries added this task must
     produce **no output** (no `== NEW:`, no `== CHANGED:`). Any `== NEW:` means a `dst` path was derived
     wrong (points at something not actually deployed there); any `== CHANGED:` means the copy does not match
     what is currently deployed (copy error, or the deployed file changed mid-session — re-copy and recheck).

## Pre-flight constraints

- Bash 3.2 clean applies to the one new file this plan authors from scratch
  (`pairs-completeness.test.sh`); vendored files are copied verbatim and inherit whatever bash-version
  compliance they already have in production (they are live, daily-used scripts on Stefano's bash-3.2 machine —
  not re-verified here, that is out of this issue's scope per SPEC's "no fixing defects" exclusion).
- Validate the new test with `bash -n staging/plugin/scripts/tests/pairs-completeness.test.sh` and
  `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/pairs-completeness.test.sh`
  (second grep must be empty) before considering Task 1 done.
- Reading `~/.claude` is authorized (copy source only). All writes stay inside the repository:
  `staging/`, `staging/sync-to-claude.sh`, `.github/workflows/docs-ci.yml`, possibly
  `.markdownlint-cli2.jsonc`, `SPEC.md` (checkbox updates in the final task).
- Do not touch: `staging/plugin/agents/`, `staging/plugin/hooks/hooks.json`, `staging/user/`, any of the 8
  repo-native skills already in `staging/plugin/skills/` not named below (`adr-writer`, `claude-md-generator`,
  `code-review-checklist`, `commit`, `fastapi-react-vibe`, `interview-driver`, `project-conductor`,
  `spec-from-issue`, `swift-vibe`), `goal-loop`, `research-prompt` — all reserved for issue #29.
- `staging/plugin/skills/vibe-status/INTEGRATION.md` and `staging/plugin/skills/vibe-status/scripts/chain-memory-section.sh`
  already exist and are out of scope (issue #37): add files alongside them, do not modify or reference them.

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` → PASS, exit 0.
- `bash staging/plugin/scripts/tests/prep.test.sh` → PASS, exit 0.
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` → PASS, exit 0.
- `bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh` → PASS, exit 0.
- `git status` shows changes only under `staging/`, `.github/workflows/docs-ci.yml`,
  `.markdownlint-cli2.jsonc` (conditional), `SPEC.md`, `docs/architecture/`, `docs/superpowers/plans/`. Nothing
  under `~/.claude` is ever touched (no tool call targets it for write, at any point).

---

## Task 1 — RED then GREEN: `pairs-completeness.test.sh` self-test + CI wiring

**Files created:**
- `staging/plugin/scripts/tests/pairs-completeness.test.sh`

**Files modified:**
- `.github/workflows/docs-ci.yml` — append `pairs-completeness` to the `for t in phase1 prep hook-probe
  hook-verify-workflow` list (line 44), so it becomes
  `for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness; do`.

**Contract:**
- Extract the PAIRS block from `staging/sync-to-claude.sh` without sourcing/executing the script. Recommended
  approach (matches the block's exact shape — opening line is literally `PAIRS="`, closing line is literally
  `"`): `awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' staging/sync-to-claude.sh`. Loop the result with
  `IFS='|' read -r src dst`, skipping blank lines (`[ -z "$src" ] && continue`, same guard
  `sync-to-claude.sh` itself uses).
- For each `src`, assert `[ -f "staging/$src" ]`. Track PASS/FAIL counts, print `PASS: <src>` / `FAIL: <src>`,
  final line `PASS=$PASS FAIL=$FAIL`, exit 0 if `FAIL=0` else exit 1 — same idiom as the existing four harnesses.
- **Self-test first (proves the checker works):** before checking the real table, build a small synthetic
  fixture in a tempdir with one `src|dst` line pointing at a file that does not exist, run the same
  check-function against it, and assert it reports exactly one FAIL. Then `rm -rf` the tempdir and run the real
  check against `staging/sync-to-claude.sh`'s actual PAIRS block.
- Do **not** add any deployed-`~/.claude`-comparison logic (see ADR-0024 §3.4 — this would produce false
  failures once future issues intentionally get staging ahead of deployed, and cannot run in CI at all).

**Expected (RED then GREEN in one run):** self-test fixture reports FAIL=1 (proves detection works) → real-table
check reports `PASS=15 FAIL=0` (the current, unmodified table; nothing new yet).

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/pairs-completeness.test.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/pairs-completeness.test.sh   # must be empty
bash staging/plugin/scripts/tests/pairs-completeness.test.sh    # PASS=15 FAIL=0
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # all 5 green (4 existing + new)
```

---

## Task 2 — GREEN: vendor the 12 hooks + 3 legacy hook tests

**Files created (12, all `staging/plugin/scripts/<name>`, source `~/.claude/hooks/<name>`):**
`stop-gate.sh`, `pre-flight-pattern-enforce.sh`, `db-backup-guardrail.sh`, `approve-test-cmd.sh`,
`session-context-inject.sh`, `ensure-state-dir.sh`, `mark-dirty.sh`, `post-md-tells-hint.sh`,
`prompt-en-prose-detect.sh`, `reset-gate-counter.sh`, `usage-daily-hint.sh`, `migrate-trust-paths.sh`.

**Files created (3, all `staging/plugin/scripts/tests/<name>`, source `~/.claude/hooks/tests/<name>`, name
unchanged — see ADR-0024 §2.3):** `db-backup-guardrail.sh`, `pre-flight-pattern-enforce.sh`, `run-hook-tests.sh`.

Note: `plugin/scripts/db-backup-guardrail.sh` (hook) and `plugin/scripts/tests/db-backup-guardrail.sh` (its
legacy test) share a basename in sibling directories — expected, mirrors the deployed layout, not a mistake.
Same for `pre-flight-pattern-enforce.sh`.

**Files modified:**
- `staging/sync-to-claude.sh` — append 15 PAIRS lines (12 hooks + 3 legacy tests) per the transformation rule
  above.

**Verify none of the 12 hook names already exist in `staging/plugin/scripts/`** before copying (they should
not — confirmed during planning, listing this as a pre-copy sanity check, not an expected finding):
`ls staging/plugin/scripts/*.sh | xargs -n1 basename` and cross-check against the 12 names above.

**Checkpoint:** run the two-check sequence from "Vendoring mechanics" above. Then:
```
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # 5 green, unchanged from Task 1
```

---

## Task 3 — GREEN: vendor the chain-workflow skills batch

**concept-to-code** (14 files copied; 3 excluded — see ADR-0024 §2.1/§3.3):
```
SKILL.md
scripts/agent-notes-harvest.sh
scripts/detect-macos.sh
scripts/gate0-detect.sh
scripts/manifest-init.sh
scripts/manifest-set-artifact.sh
scripts/manifest-set-flag.sh
scripts/manifest-set-gate.sh
scripts/manifest-set-humanize.sh
scripts/manifest-transition.sh
scripts/manifest-validate.sh
tests/agent-notes-roundtrip.sh
tests/run-tests.sh
tests/smoke-e2e.sh
```
EXCLUDED (do not copy): `SKILL.md.bak-2026-07-10`, `scripts/hook-verify-workflow.sh` (dup, already vendored),
`memory/agent-notes/architect.md` (runtime state).

**autopilot-build** (2): `SKILL.md`, `tests/run-tests.sh`.

**deep-refactor** (4): `SKILL.md`, `scripts/enumerate-sources.sh`, `tests/enumerate-sources.test.sh`,
`tests/run-tests.sh`. (`tests/enumerate-sources.test.sh` is this skill's own internal test, invoked by its
`tests/run-tests.sh` — unrelated to the top-level `staging/plugin/scripts/tests/*.test.sh` CI glob, different
directory prefix, no interaction.)

**review-triage-fix** (5): `SKILL.md`, `scripts/triage-state.sh`, `scripts/verify.sh`,
`scripts/weakening-scan.sh`, `tests/run-tests.sh`.

**Files modified:**
- `staging/sync-to-claude.sh` — append 25 PAIRS lines (14 + 2 + 4 + 5) under `plugin/skills/<skill>/<relpath>|skills/<skill>/<relpath>`.

**Checkpoint:** two-check sequence, then full existing suite (5 tests) green.

---

## Task 4 — GREEN: vendor the quality/hygiene skills batch

**claude-md-slim** (10): `SKILL.md`, `scripts/classify-sections.sh`, `scripts/content-union-check.sh`,
`scripts/parse-sections.sh`, `scripts/validate-frontmatter.sh`, `tests/fixtures/expected-shell-rules.md`,
`tests/fixtures/expected-trimmed.md`, `tests/fixtures/sample-claude-md.md`,
`tests/fixtures/sample-global-claude-md.md`, `tests/run-tests.sh`.

**clean-public-repo** (6): `SKILL.md`, `scripts/detect-public-remote.sh`, `scripts/detect-tool-traces.sh`,
`scripts/fresh-history-publish.sh`, `scripts/surgical-rewrite.sh`, `tests/run-tests.sh`.

**humanize-en** (6): `SKILL.md`, `rules.md`, `scripts/detect-ai-tells.sh`, `tests/fixture-ai-heavy.md`,
`tests/fixture-clean.md`, `tests/run-tests.sh`.

**Files modified:**
- `staging/sync-to-claude.sh` — append 22 PAIRS lines (10 + 6 + 6).

**Checkpoint:** two-check sequence, then full existing suite (5 tests) green.

---

## Task 5 — GREEN: vendor the planning/utility skills batch

**design-brainstorm** (2): `SKILL.md`, `tests/run-tests.sh`.
**refactor-snapshot** (5): `SKILL.md`, `scripts/capture.sh`, `scripts/diff.sh`, `scripts/pre-runs.sh`,
`tests/run-tests.sh`.
**macos-ux** (2): `SKILL.md`, `references/macos-hig.md`.
**project-init** (2): `SKILL.md`, `scripts/detect-stack.sh`.
**git-repo-init** (6): `SKILL.md`, `assets/CLAUDE.template.md`, `assets/PROJECT_BRIEF.template.md`,
`references/git-conventions.md`, `references/question-catalog.md`, `references/swift-xcode-setup.md`.
**prompt-builder** (5): `SKILL.md`, `references/rubric.md`, `references/techniques.md`,
`references/templates.md`, `references/vibrofer.md` (Vibrofer domain content — vendor as-is, byte-identical,
no terminology edits; this is a copy of existing shipped content, not new authored prose).

**Files modified:**
- `staging/sync-to-claude.sh` — append 22 PAIRS lines (2 + 5 + 2 + 2 + 6 + 5).

**Checkpoint:** two-check sequence, then full existing suite (5 tests) green.

---

## Task 6 — GREEN: vendor the partial-scope skills batch

**vibe-status** (4, added into the existing directory alongside pre-existing, untouched `INTEGRATION.md` +
`scripts/chain-memory-section.sh`): `SKILL.md`, `scripts/aggregate.sh`, `scripts/harness-runner.sh`,
`tests/run-tests.sh`.
**swiftui-pro** (1, SKILL.md only — do not copy `agents/`, `assets/` (binary icons), or `references/`):
`SKILL.md`.
**find-skills** (1): `SKILL.md`.

**Files modified:**
- `staging/sync-to-claude.sh` — append 6 PAIRS lines (4 + 1 + 1).

**Expected running total after this task:** 15 (existing) + 15 (Task 2) + 25 (Task 3) + 22 (Task 4) + 22
(Task 5) + 6 (Task 6) = **105 PAIRS entries**; 90 newly vendored files.

**Checkpoint:** two-check sequence, then `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` →
`PASS=105 FAIL=0`. Full existing suite (5 tests) green.

---

## Task 7 — GREEN: markdownlint verification, conditional scoped ignore

**Files modified (conditional — only if the lint run below reports failures):**
- `.markdownlint-cli2.jsonc` — add `"staging/plugin/skills"` as a new element of the `ignores` array (same
  bare-path style already used for `"docs/superpowers"` in that file), with a one-line comment explaining why
  (vendored content, not hand-authored, content fidelity takes precedence over lint compliance for this subtree).

**Verify:**
```
npx --yes markdownlint-cli2 "staging/plugin/skills/**/*.md"
```
If exit 0: no config change, done — vendored `SKILL.md`/reference/fixture Markdown already complies with the
repo's enabled rule subset (`MD001, MD003, MD009, MD010, MD018, MD019, MD023, MD037, MD038, MD039, MD042,
MD051, MD056` — see `.markdownlint-cli2.jsonc`).
If non-zero: apply the conditional edit above, then re-run the same command scoped to confirm the ignore takes
effect, and separately run `npx --yes markdownlint-cli2 "**/*.md"` (repo-wide, matching the CI job's own glob)
to confirm nothing outside `staging/plugin/skills/` regressed.

**Checkpoint:** `npx --yes markdownlint-cli2 "**/*.md"` exit 0 (repo-wide, matching what CI's `markdownlint`
job runs).

---

## Task 8 — Final verification, SPEC checkbox update, report

**Files modified:**
- `SPEC.md` — check off the 4 success-criteria boxes (only the ones genuinely satisfied; leave unchecked and
  explain in the report if any is not).

**Verify (full, repo-wide):**
```
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # local test-cmd, must be 5/5 green
bash staging/sync-to-claude.sh                                                   # dry-run: zero output expected
                                                                                   # for every one of the 90 new
                                                                                   # entries (byte-identical to
                                                                                   # currently-deployed)
npx --yes markdownlint-cli2 "**/*.md"                                            # repo-wide, matches CI
git status                                                                        # confirm change set matches
                                                                                   # the allow-list in Pre-flight
                                                                                   # constraints; nothing under
                                                                                   # ~/.claude
```

**Report to dispatcher:**
- ADR path, spec path, plan path.
- Final PAIRS entry count (expect 105) and new-file count (expect 90).
- `pairs-completeness.test.sh` PASS/FAIL count.
- `sync-to-claude.sh` dry-run output verbatim (expect empty for all new entries — paste it even if empty, so
  the human reviewer sees the check was actually run).
- markdownlint outcome (clean, or which files needed the scoped ignore).
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted during this session.
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — live-tree race.** `~/.claude` is Stefano's actively-used Claude Code state directory; a hook or
  skill could change mid-session (manual edit, or a concurrent nightly-autopilot run) between when this plan
  was written and when a task actually copies a file. **Mitigation:** the per-task dry-run checkpoint
  (`sync-to-claude.sh`, zero-output expectation) catches this immediately as a `== CHANGED:` line — if one
  appears, re-copy that specific file and recheck before moving on; do not proceed with a task showing any
  `== CHANGED:` output.
- **Risk B — accidental scope creep into `~/.claude/skills/concept-to-code/scripts/hook-verify-workflow.sh`.**
  Easy to copy by reflex when doing "cp the whole directory." **Mitigation:** the exclusion list is called out
  explicitly in Task 3 and in ADR-0024 §2.1/§3.3; `pairs-completeness.test.sh` will not catch a wrongly-added
  duplicate (it only checks existence, not uniqueness) — a manual `find staging/plugin/skills/concept-to-code
  -name hook-verify-workflow.sh` returning empty is the actual guard, worth running once at the end of Task 3.
- **Risk C — silently widening scope to issue #29's or #37's territory.** `staging/plugin/skills/vibe-status/`
  already contains files this issue must not touch; several other skill directories in `staging/plugin/skills/`
  belong to issue #29 entirely. **Mitigation:** the Pre-flight constraints "do not touch" list is explicit;
  `git status` in Task 8's final verification is the backstop.
- **Risk D — `.markdownlint-cli2.jsonc` edited pre-emptively.** Tempting to add the scoped ignore proactively
  "since SPEC mentions it might be needed." **Mitigation:** Task 7 is explicit that the edit is conditional on
  an observed lint failure; do not edit the config without running the lint command first and pasting its output
  in the report.
- **Risk E — `run-hook-tests.sh`'s Task 7 references `backup-before-deploy.sh`, which this issue does not
  vendor.** This is expected and does not block anything (the file is vendored as an inert reference copy, never
  executed by this repo's tooling — see ADR-0024 §2.3) but a future reader might mistake the dangling reference
  for a vendoring mistake. **Mitigation:** already documented in ADR-0024 and this plan; no action needed, flag
  it in the final report so it is not re-discovered as a "bug" later.

## HITL gates

- No HITL gate inside this plan itself (auto mode, additive-only changes, no destructive operations, nothing
  under `~/.claude` touched).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push remain
  human-gated. This plan produces a working tree ready for review; the commit/push/PR step that follows is a
  separate, standard chain gate, not a task in this plan.
- If Task 7's lint run requires the config edit, that edit is small and additive (one array element) but still
  part of the normal review before commit — no separate gate beyond the standard one.
