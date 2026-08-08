# SPEC — Skill arguments are substituted into $<digit> inside the skill body, so 19 bash-fence lines render as code the file does not hold

**Topic slug:** 385-skill-args-substituted-in-fences

Source: GitHub issue #385

## Objectives

1. Remove every `$<digit>` token from every `bash` fence in every staged `SKILL.md`, so the text a
   model executes is the text the file holds.
2. Add a derived guard that fails on any new occurrence, with a count-guarded denominator.
3. Record the substitution mechanism, which is documented nowhere today.

## Scope

**In:** the 19 `$<digit>` occurrences inside `bash` fences across five staged `SKILL.md` files
(`concept-to-code` 9, `autopilot` 4, `project-conductor` 3, `autopilot-build` 2, `commit` 1); the
new guard; the ADR and the `CLAUDE.md` record; any new `scripts/*.sh` or `*.awk` files the fix
requires, plus their `PAIRS` entries in `staging/sync-to-claude.sh`.

**Out:** `swiftui-pro:84`, which is `$0` in a `swift` fence — a `SwiftUI` binding closure, legitimate,
and outside a bash-fence population by construction. Out too: changing what any fence *does*. This
feature moves logic out of a rendered document and must not alter its behaviour. Deployment to
`~/.claude` is a separate human step (`staging/sync-to-claude.sh --apply`).

## Stack

Bash 3.2 (macOS-portable), awk, POSIX shell. Markdown for the skill documents. No build, no package
manager. Harness: `staging/plugin/scripts/tests/*.test.sh`, plus the plant registry
(`plant-check.sh`).

## Architecture

Files this feature touches, from the issue's measured population:

| file | lines | shape |
|---|---|---|
| `staging/plugin/skills/concept-to-code/SKILL.md` | 338, 935–939, 2031, 2032, 3303 | `rel()` positional params; two `awk -F'\t'` metric readers; two `shasum … awk '{print $1}'` |
| `staging/plugin/skills/autopilot/SKILL.md` | 121, 132, 140, 184 | argument parser (`case "$1"`, two `$2` reads); `scope:` block extractor (`$0 ~ …`) |
| `staging/plugin/skills/project-conductor/SKILL.md` | 43, 435, 682 | mode detection (`[ "$1" = "autopilot" ]`); two `[~]` markers (`$0 == "- [ ] " f`) |
| `staging/plugin/skills/autopilot-build/SKILL.md` | 149, 243 | one comment quoting `awk '{print $2}'`; one `shasum … awk '{print $1}'` |
| `staging/plugin/skills/commit/SKILL.md` | 233 | `is_test_path()` positional param |

Thirteen of the nineteen sit inside declared fence contracts: `autopilot-scope-args`,
`c2c-step5-preflight-dirty-classify`, `c2c-gate2b-trust-probe`, `autopilot-build-check-2`,
`autopilot-build-check-6`, `conductor-step4-nospec-skip`, `conductor-branch-c-entry-classify`.

New artifacts the fix implies: external `.sh` files for the six shell-positional cases and `.awk`
files (or field-reference-free rewrites) for the seven awk cases, each with a `PAIRS` entry; one
new test file for the derived guard; one ADR.

## Data model

None. No manifest field, no schema change, no new state file.

## API / Interfaces

- Any new script is invoked from the fence that used to hold the logic, with the same inputs and
  the same outputs. Existing exit-code contracts are preserved: a CHECKER branches on its exit
  code, a REPORTER always exits 0 and prints `CLEAN`, and exit 3 means the check did not run.
- The derived guard is a new harness file under `staging/plugin/scripts/tests/`.
- Waiver syntax for a genuine prose mention: one declared line, following the repository's existing
  one-line marker convention.

## UI flows

None. No user-facing surface changes.

## Edge cases

- **A comment that quotes the defect.** `autopilot-build:149` names `awk '{print $2}'` while
  instructing readers not to use it. Harmless at runtime and flagged by any guard — rule 12 applied
  to the guard itself. It is reworded or waived, never silently excluded.
- **The `swift` fence.** `swiftui-pro:84` must be excluded by the guard's population predicate and
  that exclusion asserted, so it cannot later read as an oversight.
- **An unmatched glob.** A population that stops resolving yields zero candidates, which reads
  exactly like full coverage. The denominator is count-guarded.
- **A fence whose body changes must still pass its fence-contract test.** Seven declared contracts
  are in the population; a fix that satisfies the guard and breaks an extraction has traded one
  defect for another.
- **A function's `$1` cannot be removed in shell.** The six shell-positional cases are not fixable
  in place; they require external files. A fix that merely renames them has not moved them out of
  the rendered document.
- **The harness cannot see this defect.** A test extracts from the file; the model executes the
  rendered text. A green run is not evidence, and the verification below is the only check that
  reads the failing quantity.

## Success criteria

- [ ] R-01 — No `$<digit>` remains inside a `bash` fence in any staged `SKILL.md`, or carries a
  declared one-line waiver.
- [ ] R-02 — A derived guard over `staging/plugin/skills/*/SKILL.md` fails on any new occurrence.
  The denominator is count-guarded: an unmatched glob must fail loudly, never read as full
  coverage.
- [ ] R-03 — The guard's population is bash fences only, and the `swift` exclusion is asserted
  rather than incidental.
- [ ] R-04 — The mechanism is recorded in an ADR and in `CLAUDE.md`. It is documented nowhere
  today, so the next author writes `$1` into a fence for the same good reasons the current 19 were
  written.
- [ ] R-05 — Every fence whose contents change still passes its existing fence-contract test.

## Verification

A green harness proves nothing here, because the harness reads files. The only check that tests the
actual failure is to invoke a skill with arguments and compare the rendered fence against the file
byte for byte — for example `/skill autopilot --dry-run --only <n>`.
