---
name: project-codex-review-gate-family
description: ADR-0187/ADR-0193 Codex-substitution family in codex-reviewer.sh — where its rule-4/rule-6 guarantees still have gaps as of ADR-0193 cycle 2
metadata:
  type: project
---

`staging/plugin/scripts/codex-reviewer.sh` implements the Codex-vs-Claude review-gate substitution
(ADR-0187, extended to `deep-refactor` audit dispatch by ADR-0193). Two gaps were open as of
ADR-0193 cycle-2 review (2026-09-06), both confirmed still present by direct code read (not
carried over from a stale prior review):

1. `--mode audit`'s `uncommitted` diff-scope arm (`git diff HEAD --name-only`) has no exit-status
   check, unlike its `base:*`/`commit:*` siblings — an unborn repo (no HEAD) fails there silently,
   collapsing to an empty file list read as "clean audit" instead of DID-NOT-RUN (exit 3). This is
   this repo's own rule 4 ("DID-NOT-RUN masked as a clean empty result").
2. The audit-mode `"file"` field in emitted findings carries whatever path enumerate-sources.sh /
   git diff produced (repo-relative, since enumerate-sources.sh wraps `git ls-files`), but
   `staging/plugin/skills/deep-refactor/SKILL.md`'s Finding schema (around line 78) documents the
   contract as `"file": "<absolute path>"`. The audit prompt even tells Codex to return "the path,
   as given below" — i.e. relative — so Codex-sourced findings and Claude-reviewer-sourced findings
   (which are told to give absolute paths) will disagree in format inside the same merged/deduped
   findings list.

**Why this matters for future review passes on this family:** neither gap is covered by
`codex-audit-mode.test.sh` (27 CX assertions, none targeting unborn-repo `uncommitted` or
path-format). Don't assume a green, well-plant-annotated test suite here means these two are
covered — check the assertion list directly. See [[feedback_confirm_before_recommend]] for the
general practice this instantiates.

How to apply: on any future review of a `codex-reviewer.sh` diff (new mode, new diff-scope value,
schema change), explicitly check (a) every diff-scope arm for a git-exit-status guard, symmetrical
across all modes that share the case block, and (b) whether the "file" field's format is actually
enforced/converted anywhere, not just documented in a SKILL.md schema block. Re-verify at review
time — a later commit may have already fixed one or both.
