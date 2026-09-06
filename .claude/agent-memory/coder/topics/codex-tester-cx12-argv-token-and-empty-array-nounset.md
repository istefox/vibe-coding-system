---
name: codex-tester-cx12-argv-token-and-empty-array-nounset
description: Two non-obvious bash 3.2 facts found implementing codex-tester.sh (ADR-0194) — required for any future edit to codex-tester.sh or a similarly-structured optional-flag script.
metadata:
  type: project
---

**Fact 1 — `codex-tester-dispatch-gate.test.sh`'s CX12/CX13 check the stub's recorded argv
LINE BY LINE, not as a joined blob.** The stub logs one argv element per line
(`for _a in "$@"; do printf '%s\n' "$_a" >> argv.txt; done`). `grep -qF -- '-c
model_reasoning_effort=high'` therefore only matches if `-c` and the value are ONE combined
shell word (`CODEX_EFFORT_ARGS=("-c model_reasoning_effort=$EFFORT")`, single array element with
an embedded space) — passing them as two separate array elements (`-c`, `"model_reasoning_effort=$EFFORT"`),
which is the more conventional CLI-argv-correct shape and is what `codex-reviewer.sh`'s own
hardcoded `-m ... -c model_reasoning_effort=medium` line does when interpolated literally, puts
them on two separate lines in the stub's argv.txt and the test goes RED. Confirmed empirically
(not assumed) by writing both variants into a scratch file and `grep -qF` against them.

Why: nobody has live-verified whether Codex's actual CLI parser accepts `-c model_reasoning_effort=high`
as a single OS-level argv string (ADR-0194 disclosed this as an explicit "not yet measured live"
gap). If a live dry run later finds this breaks real `codex exec`, the fix is presumably to change
BOTH the script (splitting `-c` and its value into two real array elements again) AND this
harness's CX12 expectation (joining what it greps for), together — not just one side.

How to apply: before touching `codex-tester.sh`'s `--effort` passthrough again, re-derive whether
CX12 still expects a single joined token; do not assume the "two array elements" wording in the
plan/ADR prose is what the harness actually checks — it is not, as written on 2026-09-06.

**Fact 2 — `"${ARR[@]}"` on a declared-but-empty bash array throws "unbound variable" under
`set -u`,** in the bash actually running this repo's harnesses (reproduced empirically, not just
theorized from the macOS-bash-3.2 rule in `~/.claude/rules/tools.md`). The fix is the
`"${ARR[@]+"${ARR[@]}"}"` idiom (parameter-expansion `+` alternate-value form), which is safe for
both empty and non-empty arrays and was verified working in this environment. Plain
`"${ARR[@]:-}"` was NOT tried/needed once this idiom worked; use the `+` form directly for any
future optional-array-append pattern in a `set -u` script in this repo (e.g. a hypothetical
`codex-common.sh` extraction per ADR-0194 §Refinements R7).
