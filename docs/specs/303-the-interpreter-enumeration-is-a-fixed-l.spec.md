# SPEC — the interpreter enumeration is a fixed list and the escapes are pinned nowhere

Source: GitHub issue #303

## Objectives
1. Re-measure the intersection ADR-0079 §D1 measured: commands that are outside
   `agent-command-scope.sh`'s fixed interpreter enumeration AND actually invocable by a scoped
   agent. If the intersection is still empty, the correct output may be a pin plus a coverage
   statement rather than a widening of the enumeration.
2. Classify or pin every named escape — `busybox`, an `env`-wrapped shell, a renamed script, and
   `lua -e "os.execute('git push')"` — as expected-ALLOW with its reason, so that closing one fails
   a test and forces the threat-model paragraph to move with the code.
3. Leave the compound R2 guard intact: a read-only verb behind a real exec construct and a verb
   inside a print statement both stay allowed.

## Scope
In: the escape shapes named by ADR-0074 and ADR-0079 §D5; assertions pinning each as expected-ALLOW
with a stated reason in `agent-command-scope.test.sh`; the coverage statement in the hook's own
header; the re-measurement of the outside-the-enumeration / actually-invocable intersection.

Out: turning the hook into a sandbox. The threat model — a guardrail against a shortcut — is
explicitly preserved, and the existing expected-ALLOW pins in section E (the list-form
`subprocess.run` and the variable-splicing bypass) are not closed. Agent grants are not widened or
narrowed here (that is #302's and ADR-0042's territory). The permission layer itself is not
modified.

## Stack
Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture
- `staging/plugin/scripts/agent-command-scope.sh` — the `PreToolUse` hook on `Bash`. Holds
  `INTERP_C` (the fixed interpreter enumeration: `bash|sh|zsh|ksh|dash|python|python3|perl|ruby|
  node|env`), `MUTATING`, `TRAIL`, `R1` (mutating verb at a shell command position) and the compound
  `R2` (`R2_EXEC` and `R2_GIT` together). Its header already carries the grant-coverage table and
  the threat-model paragraph; the line numbers in the issue's source quotes will have moved.
- `staging/plugin/scripts/tests/agent-command-scope.test.sh` — section C (command-position vs
  substring), section E (the expected-ALLOW bypasses that pin the threat model), section I (the R2
  boundary and the compound guard, including `I4` — a verb inside a print statement stays allowed —
  and `I5` — a read-only verb behind a real exec construct stays allowed), section J (`J5`, the
  residual limit: an interpreter neither enumerated nor using an `R2_EXEC` construct escapes).
- `staging/plugin/agents/architect.md` and `staging/plugin/agents/reviewer.md` — the two scoped
  agents whose `tools:` grants bound what is actually invocable. Measured today: `bash` and
  `python3` on both, `awk` on reviewer.
- `docs/architecture/ADR-0074-127-self-arming-marker-class.md` — the source disclosure (fixed
  enumeration; `busybox`, `env`-wrapped shell, renamed script named and pinned nowhere).
- `docs/architecture/ADR-0079-196-grant-coverage-and-r2-boundary.md` §D1 and §D5 — the measured
  intersection argument and the `lua -e` shape.
- `docs/architecture/ADR-0045-58-interpreter-wrapper-bypass.md` — where the two rules and the
  expected-ALLOW discipline originate.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry.

## Data model
None. The artifacts are regular-expression constants (`INTERP_C`, `MUTATING`, `TRAIL`, `R1`,
`R2_EXEC`, `R2_GIT`) and the header's `# grant-covered:` classification lines.

## API / Interfaces
- The hook's stdin/stdout `PreToolUse` contract: it reads the tool payload and emits a deny decision
  or allows; it is inert for every agent outside its `case` arm and allows on every failure mode.
- `INTERP_C` — the enumeration under review.
- The `# grant-covered:` declaration and the threat-model paragraph in the hook header, which the
  new pins must keep in agreement with the code.
- Section E / I / J assertions in the test file, each pinning one shape as expected-ALLOW with its
  reason.

## UI flows
None. A denial surfaces as a `PreToolUse` deny message to the dispatched agent; everything else is
harness output.

## Edge cases
- `busybox sh -c "git push"` — an executor reached through a multiplexer binary that is not in the
  enumeration.
- `env bash -c "git push"` and `env -i sh -c …` — `env` is in the enumeration as a leading token,
  but the wrapped-executor form and additional `env` options need checking against `INTERP_C`'s
  option-skipping group.
- A renamed script (a copy of an interpreter under another name) — outside any enumeration by
  construction.
- `lua -e "os.execute('git push')"` — neither enumerated nor using an `R2_EXEC` construct; closed
  today only by the permission layer, a different mechanism in a different file.
- The compound guard must not regress: `print("git commit")` and `os.system("git log")` both stay
  allowed (R-02). A widening that catches either is a false positive on the exact class ADR-0045 and
  ADR-0079 built the compound rule for.
- A read-only verb (`git log`, `git diff`, `git show`, `git status`, `git rev-parse`) is never
  mutating and must stay allowed regardless of the construct around it.
- If a future grant makes one of these escapes reachable, the pin is what makes it visible; a
  closed-but-unpinned escape leaves the threat-model paragraph stating something untrue.
- Per the repository's standing rules: each new assertion must be seen RED against a declared plant,
  and both directions per contract (the good fixture and the bad input).

## Success criteria
- [ ] R-01 — each named escape is either classified or pinned as expected-ALLOW with its reason, so
      closing one fails a test and forces the threat-model paragraph to move with the code.
- [ ] R-02 — the existing compound guard survives: a read-only verb behind a real exec construct and
      a verb inside a print statement must both stay allowed.
