# SPEC — the deployed-only registry's reasons are true today and checked by nothing

Source: GitHub issue #306

## Objectives
1. For each declared `# deployed-only:` entry, determine whether its reason is mechanically
   checkable at all, and separate the two classes before designing anything.
2. Check the reasons that are mechanically checkable, and mark the rest explicitly as human claims,
   so a reader cannot mistake partial coverage for full coverage.
3. Preserve the stale-waiver direction: an entry naming a skill that is now present in `staging/`
   must fail, not pass quietly.

## Scope
In: the five `# deployed-only:` declarations in `staging/sync-to-claude.sh` and the assertions that
read them (`DO1`–`DO5` in `pairs-completeness.test.sh`); the classification of each reason as
mechanically checkable or a human claim; the checks for the checkable half; the marking of the rest.

Out: enforcing licence or provenance — ADR-0065 (#119) deliberately shipped no detector, and this
feature does not become one. The CI/`$HOME` split ADR-0087 established stands: CI-runnable checks
read only `staging/`, and the `$HOME`-dependent direction (every deployed skill is vendored or
declared) stays a deploy-time report in `sync-to-claude.sh`. No skill is vendored or unvendored
here, and `PAIRS` is not restructured.

## Stack
Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture
- `staging/sync-to-claude.sh` — the registry's home, chosen because that file decides which files
  reach `~/.claude`, and because the excused file is absent from `staging/` by construction so
  ADR-0077's "a waiver travels with the file" rule cannot apply. Holds the five declarations, the
  `# pairs-zone-anomaly:` declarations beside them, `PAIRS`, and the deploy-time report that reads
  `$HOME/.claude/skills` and prints any deployed skill neither vendored nor declared. The line
  number in the issue's source quote will have moved.
- The five entries as measured today: `agent-design` (proprietary book-derived knowledge base, its
  own frontmatter `license:` field says so), `daily-close` and `daily-open` (personal daily-routine
  skills bound to local connectors), `vibiso-intake` (front end of a different project's intake
  contract), `website-auditor` (symlink into a foreign repository).
- `staging/plugin/scripts/tests/pairs-completeness.test.sh` — the CI-runnable direction. `DO1`–`DO5`
  extract the declarations, assert the stale-waiver property, apply the 40-character reason floor
  (`DO3`) and self-test the extraction (`DO5`). Also holds `check_complete` and the `hooks.json`
  exclusion comment (issue #307's subject).
- `staging/plugin/skills/concept-to-code/SKILL.md` §25 — the chain-invokable skill list, the one
  reason class that is mechanically checkable from inside `staging/`. `ui-layout-audit` is the entry
  ADR-0087 moved out of the deployed-only class for exactly this reason.
- `staging/plugin/scripts/tests/skill-coverage-perimeter.test.sh` — the sibling perimeter guard, for
  its waiver conventions (one line, reason floor, position constraint, stale-waiver direction `S7`).
- `docs/architecture/ADR-0087-222-deployed-only-skills.md` — the source; the deployment-versus-
  verification split and the two directions.
- `docs/architecture/ADR-0065-119-licence-provenance.md` — why a licence claim has no detector.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry.

## Data model
The declaration, one line in `sync-to-claude.sh`:

`# deployed-only: <skill-name> — <reason>`

Parsed today by stripping the `# deployed-only: ` prefix and taking the first whitespace-delimited
field as the skill name, with the remainder as the reason. This feature adds a way to distinguish a
mechanically-checkable reason from a human claim; whether that is a new field, a marker within the
reason, or a separate declaration form is an implementation decision.

## API / Interfaces
- The `# deployed-only:` declaration line — the authoring interface, read by both directions.
- `DO1`–`DO5` in `pairs-completeness.test.sh` — the CI-runnable direction, reading only `staging/`.
- The deploy-time report in `sync-to-claude.sh` — the `$HOME`-dependent direction, read by the one
  person who can answer "what is this skill".
- `concept-to-code/SKILL.md` §25 — the run-time source for the chain-invokability reason class.

## UI flows
None. The CI direction surfaces as harness `PASS`/`FAIL` lines; the deploy-time direction surfaces
as a report printed by `sync-to-claude.sh` during a sync.

## Edge cases
- A reason that is a licence claim (`agent-design`) cannot be verified by any check in this
  repository; a check that verifies only the easy half while reading as though it covered both is
  the specific failure the issue names.
- A reason that is a claim about another project (`vibiso-intake`) is equally unverifiable from
  here.
- `website-auditor` is a symlink into a foreign repository, so its presence is a filesystem fact
  rather than a `staging/` fact — outside the CI-runnable direction by construction.
- A skill named in a declaration that later appears under `staging/` is a stale waiver and must fail
  (R-02); a stale waiver that passes quietly reads exactly like clean coverage.
- A declaration for a skill that has never been deployed and no longer exists anywhere is invisible
  to the CI direction, since that direction only reads `staging/`.
- A reason wrapped across lines is a prose assertion that depends on where the text breaks; the
  one-line marker requirement in the sibling guards exists for that reason.
- Per the repository's standing rules: any new assertion must be seen RED against a declared plant,
  and a needle must belong to the mechanism rather than to the prose explaining it — the registry's
  own comment block legitimately names every skill it declares.

## Success criteria
- [ ] R-01 — reasons that are mechanically checkable are checked; the rest are marked as human
      claims so a reader cannot mistake the coverage.
- [ ] R-02 — the stale-waiver direction still runs: an entry naming a skill that is now staged must
      fail, not pass quietly.
