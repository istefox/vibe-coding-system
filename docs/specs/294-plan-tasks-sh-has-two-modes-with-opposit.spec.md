# SPEC — plan-tasks.sh has two modes with opposite failure directions and nothing stops a caller picking the wrong one

Source: GitHub issue #294

## Objectives

1. Make it impossible for a caller of `plan-tasks.sh` to silently pick the wrong mode, through a
   checkable mechanism rather than a sentence in the script header.
2. Assert that both existing call sites still resolve to the mode they use today.
3. Preserve the exit-3 "did not run" contract for both modes, kept distinct from a legitimate zero.

## Scope

In: `plan-tasks.sh`'s two modes (`--count`, `--count-openers`), the mechanism that binds a caller to
the mode matching the question it is asking, an enumeration of every current caller with its mode
and its question, and assertions per call site. The exit-3 contract for both modes.

Out: the predicate itself — `is_task_line()` and `is_task_opener()` in `plan-task-predicate.awk`
are two deliberately different predicates (ADR-0070) and this issue is not about changing either.
The batching arithmetic that consumes `--count-openers` (settled by ADR-0100). The identifier model
(#293).

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/scripts/plan-tasks.sh` — the two-mode entry point. Its
  header already states that the modes are not interchangeable in either direction; that statement
  is precisely what R-01 says is insufficient.
- `staging/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk` — the loaded predicate
  supplying both `is_task_line()` and `is_task_opener()`; the source of the two different answers.
- `staging/plugin/skills/concept-to-code/SKILL.md` — Step 5 call sites: the pre-dispatch plan
  structure validation (a `>= 1` guard) and the Agent-tool batch dispatch (arithmetic). Both are
  anchored by `fence-contract:` markers rather than by heading, per ADR-0083 §D3.
- `staging/plugin/skills/autopilot-build/SKILL.md` — check 5 of the unattended pre-flight ("Plan has
  tasks"), a guard.
- `staging/plugin/scripts/tests/plan-task-count.test.sh`,
  `staging/plugin/scripts/tests/batch-dispatch-openers.test.sh`, and
  `staging/plugin/scripts/tests/scope-guards.test.sh` — the harness files that already extract and
  execute these call sites; where the per-call-site assertions belong.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0100-242-batch-dispatch-openers.md` — the source, whose quoted line number
  will have moved; and `docs/architecture/ADR-0069-172-plan-task-form.md`, which established the
  shared predicate.

## Data model

Per caller, the tuple that must be recorded and checkable: call site (file plus fence id), mode
invoked, and the question being asked (guard versus arithmetic). The failure direction of each mode
is the property that binds the two: `--count` over-counts, safe for a guard and wrong for
arithmetic; `--count-openers` can legitimately return 0, safe for arithmetic that checks zero and
wrong for a guard.

## API / Interfaces

- `plan-tasks.sh --count <plan-file>` — one integer, task LINES, loose predicate.
- `plan-tasks.sh --count-openers <plan-file>` — one integer, task BLOCK OPENERS, strict predicate.
- Exit codes: 0 with an integer on stdout; exit 3 for "the check did not run" (predicate missing,
  awk failed, non-integer result). Exit 2 for bad invocation.

Whatever mechanism R-01 introduces becomes part of this interface and must not collapse exit 3 into
a zero result.

## UI flows

None.

## Edge cases

- A plan whose `--count-openers` is legitimately 0 (the two corpus plans using `### T1 —` and
  `### Step 0 —`) — a real zero, which must stay distinguishable from exit 3.
- A malformed plan a guard must reject: `--count-openers` would pass it, which is the silent
  failure in the first direction.
- Arithmetic fed by `--count`: 38 versus 7 on #222's plan, dispatching against tasks that do not
  exist — the silent failure in the second direction.
- A future third caller, which is the population the mechanism must actually cover; two call sites
  asserted is necessary and not sufficient.
- A new mode added later: whether the mechanism extends or has to be rewritten.
- Per the standing rules in the issue footer, the mechanism is a checker if it branches on an exit
  code, and must not adopt a reporter's always-exit-0 idiom by copying one.

## Success criteria

- [ ] R-01 — a caller cannot silently pick the wrong mode; the mechanism must be checkable, not a
      sentence in a header.
- [ ] R-02 — both existing call sites still resolve to the mode they use today, asserted.
- [ ] R-03 — the exit-3 "did not run" contract preserved for both modes, distinct from a legitimate
      zero.
