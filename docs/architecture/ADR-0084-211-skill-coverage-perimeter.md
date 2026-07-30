# ADR-0084 — A skill is covered by name, or it declares why not

- **Status:** Accepted
- **Date:** 2026-07-30
- **Issues:** #211 (closed)
- **Related:** ADR-0043 (direction of a guard), ADR-0077 (declared exemption travels with the file),
  ADR-0081 (a stale waiver reads as a clean bill of health), ADR-0083 (the marker is the extraction
  anchor), ADR-0040 (the perimeter this closes the coverage gap on), ADR-0042 (prose and contract
  disagreeing with nothing to say which is authoritative)

## Context

Ten of twenty-nine staged skills had no test naming them. The gap is not that ten skills lack a
test — several are prompt templates whose entire content is instructions to a model, and inventing
an assertion to raise a number would be worse than the gap. The gap is that **nothing
distinguished "audited and deliberately uncovered" from "never looked at"**. Both sat in the same
bucket, and that bucket is indistinguishable from an oversight.

## Decision

### D1 — The issue's premise was wrong, and the correction is what shapes the check

Issue #211 said the ten were "read by no test at all". Measured: false. **Three** sweeps already
read every, or nearly every, `SKILL.md`.

| sweep | population | property |
|---|---|---|
| `worktree-isolation-contract.test.sh` | `skills/*/SKILL.md` + `agents/*.md` | `isolation:` values |
| `agent-tool-parameter-names.test.sh` | same corpus | Agent/Skill/EnterPlanMode call notation |
| `skill-text-corrections.test.sh` F6 | names derived from c2c §25 | `disable-model-invocation` |

Under the obvious predicate — "some test opens this file" — **all twenty-nine would pass**, the
count guard would stay green, and the perimeter would be exactly as unmeasured as before. That is
the ADR-0043 direction lesson one level up: a check satisfiable by a population other than the one
at risk is not guarding what it appears to guard.

The count itself was right (10 of 29, list identical), which is the more useful half of the
finding: **a right number can sit on a wrong premise**, and only the premise decides the design.

### D2 — The predicate is a literal name, because a sweep cannot produce one

A skill counts as covered when some file under `staging/plugin/scripts/tests/` contains the literal
string `<name>/SKILL.md`. A corpus sweep reaches a file through a glob (`skills/*/SKILL.md`) or a
variable (`skills/$_s/SKILL.md`) and **cannot** produce it; a test written for one skill must.

`S6` pins the distinction in the failing direction: the predicate is run against a fixture
containing only a glob-style sweep and must report zero coverage. Weaken `covered_by()` to
"any file opens a `SKILL.md`" and `S6` is what goes red. Without it the whole file is decoration.

The predicate immediately proved itself on its own author. The first draft of the `goal-loop` /
`research-prompt` assertions was a two-element `for` loop, and the perimeter check went on
reporting both skills as uncovered — correctly, since a hardcoded two-name loop is
indistinguishable from a sweep. They are now two named assertions, `F7` and `F8`, and the reason
is written at that site so nobody re-rolls the loop.

### D3 — The waiver travels with the skill, one line, in position

`<!-- skill-coverage-exempt: <reason, >= 40 chars> -->`, once, within three lines of the
frontmatter close. ADR-0077 §D3's pattern: an exemption list inside a test lets an author excuse a
file without touching it, and does not travel on rename.

The **one-line** requirement is not cosmetic. A reason wrapped across lines is a prose assertion
that depends on where the text breaks — the fifth recurrence of that lesson (ADR-0073 line wrap,
ADR-0076 comment marker, ADR-0080 backticks, ADR-0082 the marker line itself). `S4` measures the
marker line only, so a wrapped reason fails at the moment it is written rather than being grepped
around later.

`S2` count-guards the waiver population: with zero declarations, `S3`/`S4`/`S5`/`S7` all pass
vacuously and a green suite would say nothing about the mechanism.

### D4 — And it runs backwards

`S7`: a declaration on a skill that **is** covered is a stale waiver, invisible precisely because
everything around it stays green (ADR-0081 ZA4's direction). Verified on a planted case.

### D5 — Per-skill decisions, and what each one buys

**Declared deliberately uncovered** — `adr-writer` (14 lines), `code-review-checklist` (17),
`swift-vibe` (14). Prompt templates and snippet references with no path, script or cross-file
contract to pin. Asserting a Swift snippet's content would pin one API era, not a contract.

**Covered as genuine oversights:**

- `humanize-en` (`C1`/`C2`) — ADR-0040 moved the perimeter **into** the `description` frontmatter,
  arguing that field "is what the model reads when deciding to invoke, so it matters as much as the
  global rule". Nothing asserted the field. The load-bearing half of that ADR was the unverified
  half.
- `goal-loop`, `research-prompt` (`F7`/`F8`) — both carry `disable-model-invocation: true`, pinned
  until now only by a **sentence in the blueprint** (F5). If either file lost the flag, F5 would
  still pass (the sentence would still name it) and F6 would still pass (neither is chain-invokable,
  so neither is in its derivation).
- `refactor-snapshot`, `vibe-status` (`C3`/`C4`) — each has a sibling test that reads its
  `scripts/` and not its `SKILL.md`: partial coverage that reads as full from the test filename.
  Every `scripts/` path the skill tells an operator to run must exist. `tests/run-tests.sh` is
  deliberately outside the pattern — it is the skill's own self-test, not an entry point.
- `design-brainstorm`, `macos-ux` (`C5`/`C6`) — c2c §25 declares each chain-invokable **under a gate
  condition** (`gate 1b only`, `gate 1c only`) and nothing checked that the skill's own text agrees.
  The ADR-0042 shape: a file whose prose and its caller's contract disagree with no way to tell
  which is authoritative. Both sides are asserted, so the failure names which one moved.

## Consequences

- Three `SKILL.md` files gain an HTML comment. A real if small prompt cost, accepted on the same
  terms as ADR-0083's fence markers: a waiver that does not travel with the file is worse.
- **The check verifies that a skill is named, never that the assertion naming it is any good.** A
  test containing `foo/SKILL.md` in a comment satisfies the predicate. It measures the perimeter,
  not the quality of what is inside it.
- The population is `staging/` only, and that is a deliberate boundary rather than an oversight:
  **six skills are deployed in `~/.claude/skills/` and absent from `staging/`** —
  `agent-design`, `daily-close`, `daily-open`, `ui-layout-audit`, `vibiso-intake`, and
  `website-auditor` (the last excluded on purpose by ADR-0024). `ui-layout-audit` is the serious
  one: c2c §25 declares it chain-invokable at gate 5.05, and F6's `[ -f "$_sf" ] || continue`
  skips it in silence. No staging test can reach it, by construction. Widening this check to
  `~/.claude` would make the harness depend on the machine's deploy state, which is the opposite of
  what ADR-0024 decided. Filed separately.
- `S0`, `S6` and `Z1` pass before and after — forward guards, not fix evidence. `S1` and `S2` are
  the red evidence. All seventeen assertions were seen failing on a planted defect before being
  accepted (rule 6).
