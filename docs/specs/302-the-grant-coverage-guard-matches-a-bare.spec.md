# SPEC — the grant-coverage guard matches a bare Bash token so an unrestricted grant in another form passes

Source: GitHub issue #302

## Objectives
1. Enumerate the forms an unrestricted Bash grant can take in agent frontmatter (bare `Bash`,
   `Bash(*)`, and any other form the enumeration finds) and check each against the current `J0c`
   assertion in `agent-command-scope.test.sh`.
2. Make the guard fail on an unrestricted grant in any of those forms, naming both the agent and the
   form that triggered it.
3. Preserve the run-time derivation that produced the finding: the scoped-agent list still comes
   from the hook's own `case` arm, and every derived name still resolves to a real agent file.

## Scope
In: section J of `staging/plugin/scripts/tests/agent-command-scope.test.sh` — specifically `J0a`
(the derivation and its count guard), `J0b` (name resolution), and `J0c` (the unrestricted-grant
check); the enumeration of unrestricted-grant forms; the agent frontmatter files the derivation
reads.

Out: the hook `staging/plugin/scripts/agent-command-scope.sh` itself is not widened by this feature
— the threat model (a guardrail against a shortcut, not a sandbox) is unchanged; no agent's grants
are narrowed or widened; `J1`–`J5` (the grant-coverage classification, the behavioural check and the
residual expected-ALLOW limit) keep their current meaning; the interpreter enumeration is issue
#303's subject, not this one.

## Stack
Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture
- `staging/plugin/scripts/tests/agent-command-scope.test.sh` — section J. `J0a` derives the scoped
  agents from the hook's `case` arm and count-guards the derivation; `J0b` resolves each derived
  name to a file under `staging/plugin/agents/`; `J0c` currently matches an exact bare `Bash` token
  and is the assertion this feature corrects. The line numbers in the issue's source quote will have
  moved.
- `staging/plugin/scripts/agent-command-scope.sh` — the hook whose `case` arm names the scoped
  agents (`architect`, `reviewer`) and whose `# grant-covered:` declaration `J1`/`J3` read. Read
  only; not modified.
- `staging/plugin/agents/*.md` — the frontmatter `tools:` lines the derivation parses. Measured
  today: `architect.md` and `reviewer.md` carry per-subcommand `Bash(<word> …)` grants;
  `coder.md`, `debugger.md`, `refactorer.md` and `tester.md` carry a bare, unrestricted `Bash`.
  `coder.md` is the hypothetical third scoped agent that produced the finding.
- `docs/architecture/ADR-0085-208-derived-guard-boundaries.md` — the source disclosure (`J0c`
  matches an exact bare `Bash` token, so `Bash(*)` would pass it).
- `docs/architecture/ADR-0079-196-grant-coverage-and-r2-boundary.md` §D1 — the argument this guard
  protects: an agent can only invoke what its frontmatter grants, and the granted executors are all
  covered.
- `docs/architecture/ADR-0042-91-architect-git-grant.md` — the precedent for narrowing a `Bash(git
  *)` grant, and the reason per-agent deny rules are unworkable.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry.

## Data model
None. The parsed artifact is the frontmatter `tools:` list in an agent Markdown file, whose grant
entries take the forms `Bash`, `Bash(<pattern>)` and `Bash(<word> <pattern>)`.

## API / Interfaces
- The `case` arm in `agent-command-scope.sh` that names the scoped agent types — the run-time source
  of the derived agent list (`J0a`).
- The frontmatter `tools:` field of each derived agent file — the run-time source of the grant words
  (`J2`, `J3`) and of the unrestricted-grant check (`J0c`).
- `J0c`'s match predicate, widened from an exact bare-token test to one covering every enumerated
  unrestricted form, and reporting the agent plus the form.

## UI flows
None. The feature surfaces only as `PASS`/`FAIL` lines in the harness output.

## Edge cases
- `Bash(*)` — a wildcard pattern that grants everything while presenting as a bounded grant. The
  named case the current exact-token match lets through.
- A bare `Bash` on an agent that is not currently scoped: today no scoped agent holds one, so `J0c`
  passes; `coder` is one line of the hook away from being in scope, and its silence would look
  exactly like coverage.
- An agent with zero `Bash(<word> …)` entries yields zero derived grant words, which `J3` reads as
  "nothing unclassified" — a vacuous pass. This is the failure mode `J0c` exists to prevent.
- A typo in the hook's `case` arm empties the derived file list, which empties the grant derivation;
  `J0b` is the guard against that and must survive (R-02).
- Whitespace and ordering variations inside the `tools:` list, and a `tools:` line that wraps.
- Per the repository's standing rules: the new assertion must be seen RED against a declared plant,
  and its needle must belong to the mechanism rather than to the prose that explains it.

## Success criteria
- [ ] R-01 — an unrestricted grant in any form fails the guard, naming the agent and the form.
- [ ] R-02 — the derived scoped-agent list still comes from the hook's own `case` arm at run time,
      and every derived name still resolves to a real agent file.
