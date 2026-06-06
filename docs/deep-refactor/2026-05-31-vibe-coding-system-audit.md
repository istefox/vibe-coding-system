# deep-refactor audit — vibe-coding-system — 2026-05-31

## Summary

- Baseline: GREEN (PASS=43 FAIL=0 — `bash ~/.claude/skills/deep-refactor/tests/run-tests.sh`)
- Post-fix: GREEN (PASS=43 FAIL=0 — no regression)
- Dimensions completed: perf, structure
- Dimensions skipped: none
- Fixed: 3 findings (2 perf, 1 structure)
- Deferred (report-only / high-risk): 8 findings
- Regressions caught: 0
- Source files scanned: 105

## Per-dimension findings

### dead-code

- **P3** `docs/manifests/2026-05-23-clean-public-repo-anonymize.manifest.yml:12` — gate0 block entirely null/false in a completed manifest predating ADR-0017
  Status: Deferred — report-only
  Suggested fix: Leave as-is for schema consistency, or document gate0 as N/A for pre-ADR-0017 completed manifests.

- **P3** `docs/manifests/2026-05-30-deep-refactor-skill.manifest.yml.bak:null` — stray .bak backup file untracked in manifests directory
  Status: Deferred — report-only
  Suggested fix: Delete the stray .bak (requires HITL per safety rules) or add a `*.bak` ignore rule to `.gitignore`.

### perf

- **P3** `staging/plugin/scripts/auto-format.sh:4` — `echo "$INPUT" | jq` forks an extra subprocess per hook invocation
  Status: Fixed by coder agent — replaced `echo` with `printf '%s\n'` (bash 3.2-compatible, more robust with special chars). Commit: `baf8271`.

- **P3** `staging/plugin/scripts/protect-files.sh:4` — same `echo "$INPUT" | jq` pattern
  Status: Fixed by coder agent — same printf fix applied. Commit: `baf8271`.

### structure

- **P1** `docs/manifests/2026-05-29-dynamic-workflows-step5.manifest.yml:5` — `project_root` uses lowercase `/developer/` path (all other manifests use capitalized `/Developer/`); re-introduces the path-casing hazard documented in memory
  Status: Fixed — commit `8128a6d` normalized path casing (`/developer/` → `/Developer/`) across this manifest.
  Suggested fix: Normalize all paths in this manifest to `/Users/stefanoferri/Developer/vibe-coding-system`.

- **P2** `docs/architecture/ADR-0015-humanize-en-chain-integration.md:2` — ADR header format drift between ADR-0001..0014 (inline status) and ADR-0015..0018 (separate Status + Date lines)
  Status: Fixed by refactorer agent — all 18 ADRs normalized to Status/Date/Author/Supersedes/Superseded by/Related schema. Commit: `5b0849d`.

- **P2** `CLAUDE.md:81` — unbounded append-list of `## Decisions from <chain>` sections; duplicates ADR abstracts with copy-paste drift risk
  Status: Deferred — report-only (requires editorial judgment on desired structure)
  Suggested fix: Replace per-chain prose blocks with a compact decision index (ADR number + one-line status + link).

- **P2** `docs/architecture/ADR-0010-web-e2e-test.md:2` — ADR-0010 remains "Status: Proposed — 2026-05-22" while 8 later ADRs reached Accepted/Rejected; no superseding or closure note
  Status: Deferred — report-only
  Suggested fix: Mark ADR-0010 Accepted/Rejected/Deferred with a dated note, or add a "Status as of \<date\>" line.

- **P2** `docs/architecture/:null` — 18 ADRs with no index/README; blueprint references ADRs inconsistently; no authoritative ADR→file map
  Status: Deferred — report-only
  Suggested fix: Add `docs/architecture/README.md` indexing each ADR (number, title, status, supersedes/superseded-by).

- **P3** `docs/manifests/ + root:null` — backup artifacts in working tree: `*.manifest.yml.bak`, `CLAUDE.md.bak-2026-05-29`, `CLAUDE.md.bak-2026-05-30`
  Status: Deferred — report-only
  Suggested fix: Delete the .bak files (HITL required) or add `*.bak*` to `.gitignore`.

- **P3** `docs/manifests/2026-05-30-deep-refactor-skill.manifest.yml:12` — manifest in `step_6_review` / `in_progress` but ADR-0018 is already committed and CLAUDE.md already carries the decisions section
  Status: Deferred — report-only (state will be resolved when the c2c chain completes Step 7)

## Security findings

- **P2** `staging/plugin/.claude-plugin/plugin.json:5` — real personal email `stefano@stefer.it` hardcoded in a plugin manifest intended for public distribution
  ACTION REQUIRED — not auto-fixed
  Suggested remediation: Replace with a placeholder (e.g. `your@email.com`) or an environment variable reference. Personal email in a public-distribution artifact violates anonymization goals (ADR-0011).

- **P3** `docs/superpowers/plans/2026-05-18-vibe-coding-system.md:377` — real personal email embedded in a plan document as a plugin.json template example
  ACTION REQUIRED — not auto-fixed
  Suggested remediation: Replace with a placeholder in the example. Low risk (private repo, docs only), but inconsistent with ADR-0011 anonymization posture.

- **P3** `staging/project-templates/app-fastapi-react/gitignore-snippet.txt:2` — gitignore snippet ships only `CLAUDE.local.md`; missing common secrets patterns (`.env`, `*.pem`, `*.key`, `secrets/`)
  ACTION REQUIRED — not auto-fixed
  Suggested remediation: Expand the snippet to include standard secret-exclusion patterns before shipping this template to users.

- **P3** `staging/plugin/scripts/protect-files.sh:8` — unanchored substring match (`[[ "$FILE_PATH" == *"$p"* ]]`) — a path like `/foo/.env.backup` would match `.env.` but `/secrets/real.pem` might not match `secrets` if the pattern string differs
  ACTION REQUIRED — not auto-fixed
  Suggested remediation: Use anchored prefix matching or `grep -qF` on canonical path components; document the known limitation inline.

## Deferred findings (not auto-fixed)

| File | Description | Reason |
|------|-------------|--------|
| `docs/manifests/2026-05-23-clean-public-repo-anonymize.manifest.yml:12` | Null gate0 block in completed pre-ADR-0017 manifest | fix_type: report-only |
| `docs/manifests/2026-05-30-deep-refactor-skill.manifest.yml.bak` | Stray .bak file | fix_type: report-only |
| `CLAUDE.md:81` | Decision sections accumulate without index | fix_type: report-only |
| `docs/architecture/ADR-0010-web-e2e-test.md:2` | Stale Proposed status | fix_type: report-only |
| `docs/architecture/:null` | No ADR index/README | fix_type: report-only |
| `docs/manifests/ + root:null` | .bak backup artifacts in working tree | fix_level: report-only |
| `docs/manifests/2026-05-30-deep-refactor-skill.manifest.yml:12` | Manifest state inconsistency (in_progress, resolves at Step 7) | fix_type: report-only |
