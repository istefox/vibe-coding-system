# SPEC — MALFORMED is dropped silently by any caller filtering BUDGET or SCOPE

Source: GitHub issue #295

## Objectives

1. Enumerate every consumer of `diff-budget-check.sh` output and record, per call site, exactly
   which tokens it reads today.
2. Make every consumer read `MALFORMED` and state what it means for that caller.
3. Add one assertion per call site, each needle proven by planting to belong to that block and to
   nothing else.

## Scope

In: the consumers of `diff-budget-check.sh`'s stdout across all skills; the `MALFORMED` token's
meaning at each of them; one assertion per call site with a declared plant.

Out: the emission of `MALFORMED` itself, which ADR-0091 settled — the token exists because a plan
whose only declarations are malformed otherwise returns `CLEAN`, indistinguishable from a plan with
nothing to report. The reporter contract (always exit 0, signal on stdout). The per-file summation
(#296) and the identifier model (#293).

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh` — the reporter emitting
  `BUDGET`, `SCOPE`, `MALFORMED` and `CLEAN`. Its own header documents the token grammar.
- `staging/plugin/skills/concept-to-code/SKILL.md` — the Step 5 call sites: the checkpoint block
  that pipes `git diff --stat=999` into the script and is instructed to parse `BUDGET`/`SCOPE`
  lines, and the later helper-resolution plus invocation block stating the reporter idiom. Both are
  in the same stretch as `spec-coverage.sh`, whose own `MALFORMED` token is emitted twenty lines up
  — the collision ADR-0091 records as having defeated one draft assertion.
- `staging/plugin/skills/project-conductor/scripts/h16-direction-check.sh` — reads
  `budget_findings` from `step5-report.json`, a JSON channel rather than the reporter's stdout;
  whether it is a consumer of the token is a question the enumeration must answer rather than
  assume.
- `staging/plugin/skills/concept-to-code/scripts/agent-metrics.sh` — references
  `diff-budget-check.sh` for its exclusion list and reporter idiom; the same question applies.
- `step5-report.json` — where a Step 5 finding is recorded; ADR-0091 specifies a malformed
  declaration records `{task, malformed}` with no `files_*`/`lines_*` keys.
- `staging/plugin/scripts/tests/diff-budget-scope.test.sh` — the harness file for this reporter;
  where the per-call-site assertions belong.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0091-246-per-file-budget-half-parse.md` — the source, whose quoted line
  number will have moved.

## Data model

The stdout token grammar of `diff-budget-check.sh`:

- `BUDGET<TAB>task <N><TAB>…`
- `SCOPE<TAB>…`
- `MALFORMED<TAB>task <N><TAB><declaration text>`
- `CLEAN` — the no-finding sentinel.

Per consumer, the record the enumeration must produce: call site, tokens read today, tokens dropped,
and what `MALFORMED` means for that caller.

## API / Interfaces

`diff-budget-check.sh --plan <file> --tasks <task-spec> < git-diff---stat-output`, a reporter:
always exits 0, signals on stdout. Consumers are `grep`/parse blocks inside SKILL.md files and shell
helpers, not functions — so the interface is the token grammar above.

## UI flows

None.

## Edge cases

- A caller filtering `^BUDGET`/`^SCOPE` — the exact silent drop the issue names.
- A plan whose only declarations are malformed: the budget set is empty, so without the token the
  reporter returns `CLEAN`, the common and legitimate case.
- `spec-coverage.sh` emits its own `MALFORMED` in the same Step 5 stretch, so an assertion counting
  the token across the file counts both — recorded in ADR-0091 as a draft that failed on a correct
  file.
- The token name appears in prose explaining the mechanism, so a needle that is the token name
  counts the explanation (rule 12, five instances) — R-02's "proven to belong to that block and to
  nothing else" is directed at exactly this.
- A consumer reading the JSON channel rather than stdout may need a different treatment from one
  parsing the reporter's output.
- Per the standing rules in the issue footer, both directions per contract: a plan producing a
  malformed declaration and one producing none.

## Success criteria

- [ ] R-01 — every consumer reads `MALFORMED` and says what it means for that caller.
- [ ] R-02 — one assertion per call site, each needle proven to belong to that block and to nothing
      else by planting.
