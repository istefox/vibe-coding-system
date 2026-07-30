# Implementation plan — Deployed-only skills: vendor what belongs, declare what does not

- **Issue:** #222
- **ADR:** `docs/architecture/ADR-0087-222-deployed-only-skills.md`
- **SPEC:** `SPEC.md` (topic slug `222-vendor-deployed-only-skills`)
- **Date:** 2026-07-30
- **Style:** TDD — every assertion added by R-03, R-05, R-07 and R-08 is seen failing before the
  change that makes it pass (R-09). Task 1 is the sharpest instance: the fix lands *before* the gap
  it exposes is closed, so its first run fails against the real, unmodified repository — not a
  synthetic fixture — and that failure is the recorded evidence.

## Ground rules for this plan

- **Bash 3.2 clean.** No associative arrays, no `mapfile`, no process substitution, no `sed -i`
  without a suffix argument (macOS/BSD `sed`/`awk`/`grep`). This directory's harness convention:
  `set -u`, no `set -e`, `ok()`/`bad()` counters, `[ "$FAIL" -eq 0 ]` as the final exit.
- **Anchor-preserving, no new test file.** All three touched test files
  (`skill-coverage-perimeter.test.sh`, `pairs-completeness.test.sh`, `skill-text-corrections.test.sh`)
  already appear in `.github/workflows/docs-ci.yml`'s explicit `shell-tests` list and are matched by
  `ci.yml`'s glob and by `.claude/test-cmd`. **No task in this plan needs a CI registry edit** — this
  is a property of the plan, not an oversight, and it is worth stating because most prior plans in
  this repository had to add one.
- **Never a bare `m.get()`-style silent skip.** The defect this feature closes twice (F6's `continue`,
  `website-auditor`'s prose-only exclusion) is exactly the class ADR-0076 names: an absent/unresolved
  case must be a distinguishable, checkable state, not silence.
- **Grep anchors use compound phrases**, never a bare substring that could match unrelated prose
  (ADR-0082's rule). `"gate 5.05"` and `` `ui-layout-audit` (gate 5.05 only`` are checked as literal,
  bounded strings, matching `check_gate_contract`'s existing idiom for C5/C6.
- **Marker constants are built at run time** (e.g. `DMARK="deployed""-only"`), matching the
  established idiom in this same file (`ZMARK="pairs-zone-""anomaly"`) so the test does not match its
  own explanatory prose (rule 12).
- **Never cite an ID the SPEC does not declare.** The SPEC declares R-01 through R-10 and nothing
  else; every task below cites only from that set, and every ID is cited by at least one task.
- **`docs/architecture/**` markdown is markdownlint-enforced**; `docs/superpowers/` is not.

## Enumerated state before this plan

- `~/.claude/skills/ui-layout-audit/SKILL.md` (8326 bytes, verified 2026-07-30): frontmatter +
  6-step audit skill. Contains **no** mention of `concept-to-code`, "gate", or "chain" anywhere in the
  file — the gate-5.05 contract exists only on the caller's side today.
- `concept-to-code/SKILL.md:25` already reads
  `` `ui-layout-audit` (gate 5.05 only, conditional on UI files present) `` — the c2c-side half of
  the C7 contract this plan adds is already correct and needs no edit.
- `concept-to-code/SKILL.md:25`'s invokable line yields exactly **9** unique backticked tokens today
  (verified by running the same extraction `skill-text-corrections.test.sh` F6 uses):
  `claude-md-generator`, `commit`, `deep-refactor`, `design-brainstorm`, `interview-driver`,
  `macos-ux`, `review-triage-fix`, `reviewer`, `ui-layout-audit`. Seven resolve as staged skills
  today, `reviewer` is a staged **agent** (`plugin/agents/reviewer.md` exists), `ui-layout-audit`
  resolves as neither — the exact gap F6's current `continue` hides.
- `staging/sync-to-claude.sh` carries no `# deployed-only:` declaration today; the four names beyond
  `ui-layout-audit` (`agent-design`, `daily-close`, `daily-open`, `vibiso-intake`) plus
  `website-auditor` are recorded nowhere machine-checkable.
- `pairs-completeness.test.sh` currently has 5 sections (self-tests, real `check_pairs`, real
  `check_complete` ×3, `scripts-exempt`, `ZA1`–`ZA5`) and no deployed-only registry check.

---

## Task 1 — F6 resolves skills and agents, fails on neither, and a raw-token count guard (R-07, R-08, R-09)

**File:** `staging/plugin/scripts/tests/skill-text-corrections.test.sh` (section F, around the
existing F6 block, lines ~345–376).

Budget: staging/plugin/scripts/tests/skill-text-corrections.test.sh (~40 lines)

- [ ] Add a raw-token count derived **before** resolution: the count of unique backticked tokens
      extracted from `concept-to-code/SKILL.md`'s invokable line (the same `tr '`' '\n' | sed -n
      'n;p' | sort -u` pipeline F6 already uses). Assert it is `>= 7` (floor with headroom below the
      measured 9, mirroring this file's own original `_F6_CHECKED -lt 5` margin against an actual 7).
      Name it `F9` (the next free ID in this file; F7/F8 already exist for `goal-loop`/
      `research-prompt`).
      This is the guard against the derivation collapsing to zero — the case an
      unresolved-token check alone cannot see, because zero tokens produces zero unresolved names
      (ADR-0087 §D4, ADR-0043's direction lesson applied to this file's own check).
- [ ] Rewrite F6's resolution loop: for each token, check `plugin/skills/<token>/SKILL.md` (existing
      behaviour) **and**, if that is absent, `plugin/agents/<token>.md`. A token resolving to a
      skill keeps the existing `disable-model-invocation` flag check. A token resolving to an agent
      needs no flag check (the mechanism is Skill-only) but counts as resolved. A token resolving to
      **neither** is collected into a new failure list.
- [ ] Add `F10`: fail if the neither-skill-nor-agent list is non-empty, naming every such token. This
      is a genuine, real RED on the unmodified repository today: `ui-layout-audit` resolves as
      neither, so `F10` fails citing it — recorded proof the check works, not a synthetic fixture.
      **Do not vendor `ui-layout-audit` in this task.** Confirm the RED, then stop.
- [ ] Keep `F6` itself (the flag-check assertion) reporting only over tokens that resolved as
      *skills* — its meaning (`disable-model-invocation` correctness) does not extend to agents.
- [ ] Run `bash staging/plugin/scripts/tests/skill-text-corrections.test.sh` standalone. Expect
      `F9` PASS, `F10` FAIL (citing `ui-layout-audit`), `F1`–`F8` unaffected. Record this FAIL/PASS
      split in the commit message — it is the R-09 evidence for R-07/R-08.

## Task 2 — Vendor `ui-layout-audit/SKILL.md` byte-identical, with its `PAIRS` entry (R-01, R-02)

**Files:** `staging/plugin/skills/ui-layout-audit/SKILL.md` (new),
`staging/sync-to-claude.sh` (PAIRS list).

Budget: staging/plugin/skills/ui-layout-audit/SKILL.md (~165 lines, new), staging/sync-to-claude.sh (~1 line)

- [ ] `cp ~/.claude/skills/ui-layout-audit/SKILL.md staging/plugin/skills/ui-layout-audit/SKILL.md`.
      Confirm `diff -q` reports no difference (R-01's "byte-identical at the moment of vendoring").
- [ ] Add one `PAIRS` line: `plugin/skills/ui-layout-audit/SKILL.md|skills/ui-layout-audit/SKILL.md`.
      Append it as the last skill entry, immediately before the closing `"` of the `PAIRS` heredoc —
      consistent with how the most recent single-skill additions (e.g. `security-audit`) were placed.
- [ ] Run `pairs-completeness.test.sh` standalone. `check_complete "plugin/skills" '*/SKILL.md'`
      (R-02) now includes `ui-layout-audit/SKILL.md` and passes because the new PAIRS line covers it.
- [ ] Re-run `skill-text-corrections.test.sh`. `F10` (Task 1) now passes — `ui-layout-audit` resolves
      as a staged skill. `F6` gains one more skill to check (still passes: the deployed copy carries
      no `disable-model-invocation` flag). This is the GREEN half of Task 1's R-09 evidence.

## Task 3 — `ui-layout-audit` names its own gate 5.05, and `C7` asserts the contract (R-03, R-09)

**Files:** `staging/plugin/skills/ui-layout-audit/SKILL.md` (edit, the staged copy only),
`staging/plugin/scripts/tests/skill-coverage-perimeter.test.sh` (new `C7`, beside `C5`/`C6`).

Budget: staging/plugin/skills/ui-layout-audit/SKILL.md (~2 lines), staging/plugin/scripts/tests/skill-coverage-perimeter.test.sh (~20 lines)

- [ ] Add `C7` to `skill-coverage-perimeter.test.sh`, calling the file's existing
      `check_gate_contract` helper exactly as `C5`/`C6` do:
      `check_gate_contract ui-layout-audit "gate 5.05"`. Confirm it fails first (`skill-side`,
      naming that `ui-layout-audit/SKILL.md` does not say "gate 5.05" — genuine RED against the copy
      Task 2 just vendored, before this task's edit).
- [ ] Edit the **staged** `ui-layout-audit/SKILL.md` (not the deployed copy) to add one line naming
      the gate, in the same style `design-brainstorm`/`macos-ux` use for their own gates — e.g. a
      bullet near "When to invoke": "Invoked by the `concept-to-code` chain at gate 5.05 (conditional
      on UI files present in the diff)." The literal substring `gate 5.05` (case-insensitive) is what
      `check_gate_contract`'s skill-side grep requires.
- [ ] Re-run `skill-coverage-perimeter.test.sh` standalone. `C7` now passes. Confirm `S1`/`S7` are
      unaffected (`ui-layout-audit` was not previously in `POP` as an uncovered/declared case one way
      or the other — it becomes part of `POP` for the first time this task, covered by `C7` itself
      naming it, so `S1` must still pass: a skill named by `C7` counts as covered by
      `covered_by()`'s literal-string predicate).
- [ ] This is the point at which `staging/`'s `ui-layout-audit/SKILL.md` first diverges from
      `~/.claude`'s deployed copy (ADR-0087 §D1's "second, separate step"). Expected and resolved by
      Task 7's `sync-to-claude.sh --apply`.

## Task 4 — Declare the deployed-only registry in `sync-to-claude.sh` (R-04)

**File:** `staging/sync-to-claude.sh` (comment block, beside `# pairs-zone-anomaly:`).

Budget: staging/sync-to-claude.sh (~10 lines, comments only)

- [ ] Add five `# deployed-only: <name> — <reason>` lines immediately after the existing
      `pairs-zone-anomaly` declaration block and before the `PAIRS="` line, each reason `>= 40`
      characters and stating the real, verifiable reason:
  - `agent-design` — proprietary book-derived knowledge base (its own frontmatter `license:` field
    says so).
  - `daily-close` — personal daily-routine skill bound to local connectors (Obsidian, NotePlan,
    DEVONthink, ms365).
  - `daily-open` — same reason as `daily-close`.
  - `vibiso-intake` — front end of a different project's intake contract (`vibiso-system` ADR-002).
  - `website-auditor` — symlink into a foreign repository (`steve-skills/website_auditor`),
    ADR-0024 §2.1's exclusion, moved here from prose-only.
- [ ] Confirm none of the five names collides with an existing `plugin/skills/<name>/SKILL.md` in
      `staging/` (all five are, by construction, absent — this is checked mechanically in Task 5).

## Task 5 — Derived-guard assertions for the registry in `pairs-completeness.test.sh` (R-05, R-09)

**File:** `staging/plugin/scripts/tests/pairs-completeness.test.sh` (new section, immediately after
`ZA5`, before the final `printf 'PASS=...'` summary).

Budget: staging/plugin/scripts/tests/pairs-completeness.test.sh (~55 lines)

- [ ] `DMARK` built at run time (`DMARK="deployed""-only"`, matching the file's own `ZMARK` idiom).
      Extract all `# deployed-only:` lines from `$SYNC` into a tmp file via **redirection** (`grep
      ... > "$tmp/deployed-only-decl"`), not a pipe into a `while read` loop — a piped `while` runs
      in a subshell in bash and would silently drop any counter/list built inside it, the same
      pitfall `check_pairs`/`check_complete` already avoid by reading `< "$_file"`.
- [ ] `DO1`: count guard, `>= 5` declarations (R-05's "fewer than five entries" floor). Bad if the
      derivation collapses.
- [ ] `DO2`: forward check on the **real** file — no declared name has a matching
      `staging/plugin/skills/<name>/SKILL.md` (the stale-waiver direction R-05 names). Expected to
      pass trivially against the real registry (none of the five is vendored, by construction); its
      value is regression protection, not a first RED.
- [ ] `DO3`: every declared reason is `>= 40` characters (same floor `S3`/ADR-0077 `T4` use
      elsewhere in this codebase).
- [ ] `DO4` (backward self-test, the R-09 evidence for R-05): build a synthetic one-line fixture
      declaring an existing staged skill (e.g. `commit`) as deployed-only, run the same stale-waiver
      logic against the fixture instead of `$SYNC`, and assert it is flagged. Confirm this fails
      first against a naive "just check the real file" implementation of `DO2` (i.e. write `DO4`
      before trusting `DO2`'s logic, exactly as `pairs-completeness.test.sh`'s own self-test-2
      exists to prove `check_complete` is not vacuously satisfied by an empty derivation).
- [ ] Run `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` standalone. All of `DO1`–
      `DO4` plus the pre-existing `ZA1`–`ZA5` and the two self-tests pass.

## Task 6 — `sync-to-claude.sh` reports undeclared deployed skills, never blocks (R-06)

**Files:** `staging/sync-to-claude.sh` (new report block, near the existing `MANUAL STEP` blocks),
`staging/plugin/scripts/tests/sync-manual-steps.test.sh` (new section, following its established
`HOME`-override pattern).

Budget: staging/sync-to-claude.sh (~25 lines), staging/plugin/scripts/tests/sync-manual-steps.test.sh (~45 lines)

- [ ] In `sync-to-claude.sh`, after the vendored-skills copy loop, derive: (a) the set of skill
      names already vendored via `PAIRS` (parse `plugin/skills/<name>/SKILL.md|skills/<name>/SKILL.md`
      entries), (b) the set of names in the Task 4 registry. For every directory (or symlink
      resolving to a directory — `website-auditor`'s shape) under `$DEST/skills/`, if its basename is
      in neither set, collect it.
- [ ] If the collected set is non-empty, print one report block, once, with a stable heading (e.g.
      `-- REPORT: deployed skill(s) neither vendored nor declared --`), one name per line. This block
      is a **report**, distinct from the existing `MANUAL STEP` blocks: it does not set `MANUAL=1`
      and does not affect the exit code (`exit 0` always, matching R-06's "it reports; it never
      blocks the sync").
- [ ] Guard on `[ -d "$DEST/skills" ]` so a fixture (or a fresh machine) with no `skills/` directory
      at all does not error.
- [ ] Extend `sync-manual-steps.test.sh` using its existing `build_home`/`HOME`-override pattern:
  - `G1`: a fixture `$HOME/.claude/skills/` containing one directory whose name is neither a
    vendored-skill name nor a Task 4 registry name → the report block appears, naming it.
  - `G2`: a fixture containing only vendored and/or declared names (e.g. `commit`, `agent-design`)
    → the report block does not appear at all.
  - Both fixtures otherwise reuse `build_home`'s fully-wired `settings.json` so the six existing
    `MANUAL STEP` notices stay silent and do not interfere with the new assertions.
- [ ] Run `bash staging/plugin/scripts/tests/sync-manual-steps.test.sh` standalone. `G1` fails first
      against no implementation (RED), then passes once Task 6's script change lands (GREEN); `G2`
      confirms the report never fires on a fully-accounted-for fixture.

## Task 7 — Full harness green, deploy, and confirm zero drift (R-10)

Budget: none (verification only, no source files touched beyond what Tasks 1–6 already changed)

- [ ] `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` — every file in
      the harness passes, including all three files this feature touched.
- [ ] `bash staging/sync-to-claude.sh` (dry run). Confirm the diff shown for
      `skills/ui-layout-audit/SKILL.md` is exactly Task 2 + Task 3's content (new file + the gate-5.05
      line), and that no unexpected `deployed skill(s) neither vendored nor declared` report line
      appears for any of the five Task 4 names or for `ui-layout-audit` itself (it is now vendored).
- [ ] `bash staging/sync-to-claude.sh --apply`. Confirm the deployed
      `~/.claude/skills/ui-layout-audit/SKILL.md` now matches the staged copy (post-Task-3 content,
      including the gate-5.05 line).
- [ ] `bash staging/sync-to-claude.sh` (dry run, second time). Confirm **zero drift**: no `NEW` or
      `CHANGED` lines for anything this feature touched. This is R-10's explicit success criterion.
- [ ] Grep the full test harness output for `FAIL:` — expect none. Report the final PASS/FAIL tallies
      for the three touched files in the chain's Step 5 summary.

---

## Risks

- **Task ordering is the design, not a convenience.** Task 1 must land before Task 2, or F6's fix
  is never seen failing against the real gap — it would only ever be tested against an
  already-fixed repository, which is the exact "assertion that passes is not evidence until seen
  RED" failure this plan's own header names. Do not reorder Tasks 1–2 to "vendor first, then fix
  the check" even though that reads as the more natural sequence.
- **`DO4`'s synthetic fixture (Task 5) must not be skipped in favour of trusting `DO2` against the
  real file alone.** The real registry, by construction, never contains a stale name — so `DO2`
  alone never exercises its own failure branch. Without `DO4`, this is the same vacuous-pass shape
  ADR-0043 named for `pairs-completeness.test.sh`'s original `check_pairs`.
- **Task 6 (R-06) has no CI coverage for its core logic beyond the hermetic `HOME`-override
  fixtures.** This is disclosed in the ADR (§Consequences) as an accepted, bounded gap, matching the
  same asymmetry ADR-0084 already accepted for deployed-vs-staged checks generally.
- **`ui-layout-audit`'s staged copy will diverge from the live deployed copy between Task 3 and
  Task 7.** If the chain halts between those two tasks, `staging/` is briefly ahead of `~/.claude` —
  acceptable and reversible (re-run `sync-to-claude.sh --apply` whenever the chain resumes), the
  same condition this repository's own `pairs-completeness.test.sh` header already documents as
  expected.
- **`agent-design`'s licence reason is disclosed, not enforced.** Nothing added by this feature
  checks that the licence claim stays true; a future edit to that skill's frontmatter would not be
  caught. Named in the ADR's Consequences, not silently accepted here.

## PROPOSED AUDIT PROFILE

- `risk: low` — internal deploy tooling and test-harness changes only; fully reversible via git;
  no production data, migration, secret, or external system is touched.
- `task_type: glue` — wiring an already-proven pattern (ADR-0086's six-instance derived-guard
  family) into three existing files, plus one byte-copy and one two-line prose edit. No novel
  algorithm, no regulated surface, no performance-sensitive path.

TEST-CMD CANDIDATE: for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: sonnet
