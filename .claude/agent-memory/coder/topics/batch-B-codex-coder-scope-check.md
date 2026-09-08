---
name: batch-B-codex-coder-scope-check
description: Non-obvious facts from writing staging/plugin/scripts/codex-coder.sh (ADR-0196, plan tasks 2-3) — plant markers never live in the production script, and cross-file CK assertions can stay red for reasons outside the file you touched.
metadata:
  type: project
---

**Fact 1 — a `# plant: CKxx | ...` comment declared in a `.test.sh` file for a target production
script must NOT also be copied into that production script.** The plant declaration lives once, at
column 1, in the test file next to the assertion it pins (confirmed by grepping
`codex-tester.sh`/`codex-reviewer.sh`/`manifest-init.sh`/`manifest-validate.sh` — none carries a
`# plant:` line itself, even though the test files declare plants against all four). Copying the
test file's plant comment into the production file (e.g. next to the exact code line it targets,
as a "helpful" cross-reference) is wrong and was caught only by grepping sibling production scripts
before finishing. Do not do this for future `codex-*.sh` or `manifest-*.sh` edits.

**Fact 2 — `codex-coder-dispatch-gate.test.sh`'s CK ids span two plan tasks, and a CK id number
does not tell you which task owns it.** CK01-CK18 and CK25-CK27 test `codex-coder.sh` and the two
manifest scripts (plan tasks 2-3); CK19-CK24 and CK28-CK33 test
`skills/concept-to-code/references/step5-implementation.md` (plan tasks 4-5, the Step 5 gate and
exit-code sections). CK27 straddles both: it checks `manifest-validate.sh`'s Invariant 29 effort
vocabulary AND the step5 gate's own effort vocabulary agree — so it stays RED until task 4 lands
the gate text, even though task 3's half of it (the validator regex) is already correct. Do not
read a partial CK27 failure as a defect in the manifest script without first checking whether the
other half of what it compares even exists yet.

**Fact 3 — the `-c key=value` codex CLI arg must be ONE array element (a single shell word with an
embedded space), never `-c` and `key=value` as two elements**, for the SAME reason recorded in
[[codex-tester-cx12-argv-token-and-empty-array-nounset]]: the stub harness logs one argv element
per line and `grep -qFx` matches a whole line. `codex-coder.sh`'s CK08/CK09 assert
`-c model=gpt-6-astra` and `-c model_reasoning_effort=high` each as one exact line — built as
`CODEX_MODEL_ARG=("-c model=$SLUG")` / `CODEX_EFFORT_ARG=("-c model_reasoning_effort=$EFFORT")`,
not two-element arrays. Since both `--model` and `--effort` are REQUIRED here (unlike
`codex-tester.sh`'s optional `--effort`), no `${ARR[@]+"${ARR[@]}"}` empty-array guard was needed
for these two — but `VIOLATION_MSGS` (the scope-check accumulator, genuinely optional) still needed
it, and `"${#VIOLATION_MSGS[@]}"` (length, not element expansion) was confirmed empirically safe on
a declared-but-empty array under `set -u` without the `+` idiom.
