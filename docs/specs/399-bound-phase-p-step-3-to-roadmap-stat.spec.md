# SPEC — Phase P step 3 generates SPECs for completed features and ignores the run scope

**Topic slug:** 399-bound-phase-p-step-3-to-roadmap-stat

Source: GitHub issue #399 (label `chain-blocker`)

## Objective

`autopilot` Phase P step 3 decides which features need a generated SPEC by reading one thing —
whether `docs/specs/<slug>.spec.md` exists — and nothing else. It reads neither the row's state in
`PROJECT.md` nor the run scope, so a completed feature whose SPEC was never archived is
indistinguishable from a pending feature that needs one, and a run bounded to a single feature
still pays prep across the whole map.

Make the two facts it already has access to actually govern the decision: the roadmap state of the
row, and the `--only` list Phase S has already parsed.

## Measured facts (2026-08-11, this repository)

Every figure below was re-derived rather than carried over; the issue's own "What to measure"
section asks for exactly this, and two of its numbers had already moved.

- **The map holds 74 rows and 3 of them have no SPEC**, not 4: `#363`, `#364`, `#366`. The issue
  named `#365` as a fourth; it has since gained `docs/specs/365-*.spec.md`.
- **All three are `[x]` completed in `PROJECT.md`.** So R-01 alone takes this repository's
  generation count from 3 to 0. There is no case here where a state check would wrongly suppress a
  SPEC that is genuinely needed.
- **All 74 map rows match a `(issue #N)` line in `PROJECT.md`.** The orphan case is empty today, so
  its handling is a decision about failure direction rather than about present behaviour.
- **All 27 open `prep`-labelled issues already have a SPEC.** After R-01, Phase P on this
  repository generates nothing at all; the cost R-02 addresses is visible only on a fresh backlog.
- **The map is stale by construction, and that is the mechanism.** Phase P step 2 is conditioned on
  `PROJECT.md` being *absent*. `PROJECT.md` has existed for months, so step 2 always skips, so
  `docs/specs/_issue-map.tsv` is never regenerated and keeps rows for issues closed long ago.
  `roadmap-from-issues.sh:57` queries `--state open`, so a regenerated map would not contain them.
- **`roadmap-from-issues.sh:103` writes every row as `- [ ]`.** On the auto-design path the roadmap
  is generated in the same phase, moments earlier, so every row is pending and a state check passes
  all of them. R-03 therefore holds by construction rather than by a special case.
- **Phase order is S → M → P → 0.** `--only` and `--features` are parsed by Phase S and are
  available to Phase P; the on-disk `.claude/autopilot-state/scope` file is written by Phase 0
  check 9, which runs *after* Phase P. Scoping Phase P means consuming Phase S's parsed values, not
  reading that file.
- **`prep.test.sh:11` prints `FAIL <label>`**, without the colon `plant-check.sh` attributes on
  (`^FAIL: <id>`). An assertion placed there could be seen RED by hand but never verified by the
  plant registry.

## Scope

### In scope

- A roadmap-state filter for Phase P step 3, as an executable helper plus the fence that consumes
  it.
- `--only` bounding Phase P step 3 when the argument is present.
- A new CI-runnable harness file carrying the assertions, including the RED evidence R-04 requires.

### Out of scope, and stated so it is a decision rather than an omission

- **Refreshing the stale map.** After R-01 its staleness is harmless — the state check catches
  every closed row — and regenerating it would mean running `roadmap-from-issues.sh`, which
  rewrites `PROJECT.md` as well. This repository's `PROJECT.md` is a hand-curated 14-phase roadmap.
- **Fixing `prep.test.sh`'s `FAIL` form.** It is one of four such files and has its own ledger
  entry; converting one of the four inside this feature is scope creep that leaves the class open
  anyway.
- **Two unrelated defects found while opening this chain**, both real, both filed separately rather
  than bundled: `concept-to-code` Gate 0d's git auto-detect assigns `_git_ok` the two-line string
  `true\nyes` (because `git rev-parse --is-inside-work-tree` prints `true` on stdout and the
  snippet appends `yes`), so its documented `_git_ok=yes` comparison can never hold and Outcomes A
  and B are structurally unreachable; and `spec-archive.sh:49` refuses an `unknown` outgoing slug
  *before* comparing content, so Step 1's greenfield archive fence halts on any SPEC lacking the
  `**Topic slug:**` marker — 69 of 75 archived SPECs lack it, and `spec-from-issue` never writes it.

## Stack

Bash 3.2 (macOS-portable), consistent with every other helper in this tree. No new runtime
dependency. `python3` is already a hard dependency of neighbouring pre-flight checks and may be
used if a parse genuinely warrants it.

## Architecture

### Where the decision lives

A skill-private helper under `staging/plugin/skills/autopilot/scripts/`, deployed to
`~/.claude/skills/autopilot/scripts/` through a `PAIRS` entry. Direct precedent in this same skill:
`scope-args-parse.sh`, placed there by ADR-0132 for the same reason — logic that must not live in a
rendered markdown fence.

The helper is a **selector**, not a checker and not a reporter, and its contract says so at its own
header because the two neighbouring contracts in this tree are different:

- exit `0` — the selection ran. Stdout carries zero or more rows to generate, one per line. **An
  empty list at exit 0 is a normal, common result** and means every row is already covered or
  already excluded.
- exit `2` — bad invocation.
- exit `3` — the selection **did not run**: the map or `PROJECT.md` could not be read, or the
  denominator guard tripped.

### Why the denominator guard exists

The match is keyed on the `(issue #N)` marker in `PROJECT.md`. If that marker's form ever changes,
every row becomes unmatched at once. Under a per-row rule alone that reads as a specific verdict
about each row rather than as a broken predicate. So: if the map is non-empty and **zero** rows
match, the helper exits 3. Zero matches is a broken predicate; zero *generations* is a normal
outcome, and the two must not print the same thing (ADR-0085's rule applied to a new population).

### Failure direction, per case

| Case | Behaviour | Reason |
|---|---|---|
| Row `[x]` or `[~]` in `PROJECT.md` | not selected | a completed or permanently-skipped feature is never implemented again, so a SPEC generated for it describes work already shipped, into the namespace ADR-0106 uses as the archive |
| Row `- [ ]` pending | selected if its SPEC is absent | today's behaviour, unchanged |
| Row's issue number in no `PROJECT.md` line | **selected**, and reported | fail-open. Generating for an unplanned feature costs a file; skipping silently loses a SPEC that was needed, invisibly |
| `--only` present and row not in it | not selected | R-02 |
| Map or `PROJECT.md` unreadable | exit 3 | the selection did not run |
| Zero rows matched, map non-empty | exit 3 | broken predicate, not an empty result |
| Helper not deployed | **Phase P halts**, printing the sync command | consistent with all four ADR-0132 helpers and with c2c Step 5.0.1 |

### `--only` and Phase P

ADR-0129 §D7 keeps Phase S away from `PROJECT.md` because in auto-design mode the roadmap does not
exist at Phase S time. **That reason does not extend to Phase P step 3**, which runs after step 2
has generated the roadmap: `PROJECT.md` exists there on every path. The exclusion is therefore
lifted for this one step, deliberately and with the distinction written at the step, so a later
reader does not read §D7 as covering it.

`--only` bounds step 3 when present; absent, step 3 considers every pending row exactly as today.
`--features` does **not** bound it: that argument counts publishes, and using one number for two
different questions is the defect class issue #242 already cost this repository.

### Data model, API, UI flows

Not applicable. This feature adds no persisted schema, no service interface and no user interface.
`step5-report.json` and the manifest are untouched. The `prep` block of the morning report
(`features_generated`, `features_skipped_thin`) is unchanged in shape; whether a skipped-because-
completed row is counted there is an implementation detail for the ADR to settle.

## Edge cases

- **A `[~]` row that a human later un-skips** by editing it back to `- [ ]`: the next Phase P
  selects it normally. Nothing needs to remember that it was once skipped.
- **A pending row whose SPEC exists**: unchanged, still skipped — that is step 3's original
  skip-if-present rule and it is not being replaced, only narrowed.
- **An empty map**: exit 0, empty list, no denominator guard (the guard is conditioned on the map
  being non-empty). Distinct from an unreadable map, which is exit 3.
- **`--only` naming a token that resolves to no map row**: Phase S already aborts the launch for an
  unresolvable token before Phase P runs, so this cannot reach the helper. The helper does not
  re-derive that resolution.
- **A `PROJECT.md` row marked with something other than `[ ]`, `[x]`, `[~]`**: treated as
  unrecognised, not as pending. Report it and select the row — the fail-open direction, matching the
  orphan case above.
- **Two `PROJECT.md` rows carrying the same issue number**: match on the first, and report the
  duplicate. Silently picking one of two conflicting states is how a wrong answer looks correct.

## Success criteria

- [ ] R-01 — a map row whose `PROJECT.md` state is `[x]` or `[~]` does not get a SPEC generated.
- [ ] R-02 — `--only` bounds Phase P step 3 when present: a row outside the list is not selected.
      The decision and the reason §D7 does not extend to this step are written at the step itself.
- [ ] R-03 — the auto-design path, where the roadmap is generated by step 2 in the same phase,
      keeps its current behaviour exactly: every freshly generated row is `- [ ]` and is selected.
- [ ] R-04 — an assertion is seen RED against a fixture map containing a completed row with no
      SPEC, and the plant that produces that RED is declared in the registry and attributes.
- [ ] R-05 — a map row whose issue number appears in no `PROJECT.md` line is selected anyway and
      reported, rather than silently dropped.
- [ ] R-06 — the helper exits 3, not 0-with-an-empty-list, when the map is non-empty and zero rows
      match `PROJECT.md`; and exits 3 when either input cannot be read.
- [ ] R-07 — Phase P halts, printing the sync command, when the helper is not deployed; it never
      falls back to generating every row.
- [ ] R-08 — the assertions live in a new harness file that prints `FAIL: <label>` with the colon
      `plant-check.sh` attributes on, and that file is added to `docs-ci.yml`'s named job list.
- [ ] R-09 — the measured figures in this SPEC are re-derived at implementation time rather than
      trusted, and any that have moved are corrected in the ADR.
