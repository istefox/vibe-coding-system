# plant-check.sh mechanics

- Splits declarations on the literal ` | ` (`awk -F' \\| '`); a no-space `true|false` inside a
  needle/replacement is safe, a shell pipeline is not. A plant replacement may not contain ` | ` —
  that makes the declaration five fields and `BADPLANT` (ADR-0149).
- Decides "fired" with `grep -q "^FAIL: <id>"` against that one test file's output — a **prefix**
  match. Choose fixed-width, two-digit assertion ids from the start (`XX01`…`XX99`, never `XX1`
  beside `XX10`). Collisions matter within a file, not across the corpus.
- Its sandbox copies only `staging/` and `docs/` (plus the `../docs/` escape hatch, ADR-0116) —
  `.github/`, `PROJECT.md`, `CLAUDE.md`, `.git`, and any other repo-root file cannot be targeted by
  a plant. A live-content assertion against one of those is disclosed explicitly, never silently
  added or worked around (precedent: `pairs-completeness.test.sh`'s `CI1`).
- Everything under `staging/plugin/scripts/tests/` is tester-owned — `test-write-scope.sh` denies
  the coder any write under a `tests/` path component. `plant-check.sh` itself lives there despite
  not being a `*.test.sh`.
- Knob idiom: **env configures, flags select a mode.** `PLANT_JOBS`/`PLANT_WORKROOT`/
  `PLANT_SHARDS`/`PLANT_SHARD`/`PLANT_ARTIFACT` are env; `--worker`/`--baseline`/`--union`/
  `--require-legs` are re-entry modes. Do not invent a third idiom.
- Before removing a mechanism, grep its name across `staging/plugin/scripts/tests/` as well as
  source — a name-grep alone under-reports blast radius when an assertion fails from a *count*
  rather than from naming the thing.
- Before changing an observable contract, grep `# plant:` declarations for needles containing the
  code about to be deleted. A needle matching zero times is `BADPLANT`, not a pass.
