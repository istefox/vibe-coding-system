---
name: rtf4-audit-mktemp-guard
description: Measured behaviour of audit mode's unguarded mktemp in codex-reviewer.sh (exit 0 with an empty findings array), the mktemp call-order recipe a failure fixture needs, and the residual write/grep gap left unfixed
metadata:
  type: project
---

Measured on 2026-09-06 fixing the RTF cycle-4 MAJOR finding on
`staging/plugin/scripts/codex-reviewer.sh` audit mode: the two `mktemp` calls that build the
whole-tree/changed-paths intersection under `--diff-scope` were uncaptured. Same defect class as the
cycle-2 and cycle-3 fixes — see [[codex-audit-git-preconditions-and-path-shape]] and
[[review-mode-diff-scope-exit-capture]].

**The unguarded failure was measured, not reasoned about.** Against a copy of the script with the
new guards stripped, a `mktemp` failure on the `ALL_FILES_FILE` call produced **exit 0 with `[]`
written to `--out`** plus one line of bash noise on stderr (`line 276: : No such file or
directory`). Nothing downstream distinguishes that from a genuinely empty diff: the empty-`FILE_LIST`
branch is a legitimate exit-0 path (ADR-0193 §D3). The guarded script exits 3 on the same fixture and
writes no artifact.

**How to make `mktemp` fail for codex-reviewer only.** A broken `TMPDIR` is useless as a fixture: the
first `mktemp` calls in the process tree belong to `enumerate-sources.sh` (two of them, lines 36 and
42; a third only with a path-override), so a global failure trips the pre-existing
`enumerate-sources.sh failed` guard and never reaches the code under test. Shadow `mktemp` on PATH
with a stub that counts invocations in a shared file and fails on call N: **call 3 is
`ALL_FILES_FILE`, call 4 is `CHANGED_FILES_FILE`**, and a healthy end-to-end audit run makes 8 calls
in total (3-4 here, then `SCHEMA_FILE`/`PROMPT_FILE`/`RAW_OUT`/`CODEX_STDERR`). The call count is
itself a useful assertion: an audit that stops at 3 calls proves the run exited before the codex
call. The stub must `exec` or forward to `/usr/bin/mktemp` for the calls it lets through.

**Residual, deliberately left unfixed (bounded scope, reported to the orchestrator):** the
intersection line still discards both stderr and status —
`FILE_LIST=$(grep -Fxf "$CHANGED_FILES_FILE" "$ALL_FILES_FILE" 2>/dev/null)`. `grep` exit 1 (no
match) is legitimately silent, but exit 2 (I/O error), and a `printf` that fails *after* a successful
`mktemp` (filesystem full between the two), both still read as a clean empty audit. The mktemp guard
removes the likeliest causes (missing/unreadable pattern file) but not the class. A future fix is
`_grep_rc=$?` plus `if [ "$_grep_rc" -gt 1 ]`, which is the same four-line shape as every other guard
in this file — not the one-liner the finding allowed as an in-scope extension.

**Consumer checked, not assumed (rule 20):** `deep-refactor/SKILL.md` maps audit-mode exit 3 to
per-dimension Claude fallback ("Exit `3` (DID-NOT-RUN) → that one dimension only falls back"), so
these are new occasions in an existing documented bucket, not a new exit code.
