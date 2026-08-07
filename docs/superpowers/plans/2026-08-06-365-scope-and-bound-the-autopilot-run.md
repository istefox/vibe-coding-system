# Implementation plan — scope and bound the autopilot run

- **Issue:** #365
- **ADR:** `docs/architecture/ADR-0129-365-scope-and-bound-the-autopilot-run.md`
- **SPEC:** `SPEC.md` (topic slug `365-scope-and-bound-the-autopilot-run`)
- **Date:** 2026-08-06
- **Requirements:** R-01 … R-11 (every ID the SPEC declares is cited by at least one task below; the
  SPEC declares no others)

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield

---

## What was measured before this plan (do not re-litigate, do re-run)

Every number here came from running, not reading. Full reasoning in the ADR.

- **`PROJECT.md` has 31 unchecked rows, not 33**, and all 31 carry `(issue #N)`. Both the SPEC and
  `PROJECT.md` Phase 11 say 33. Re-derive before citing.
- **`roadmap-from-issues.sh:103` writes `- [ ] %s  (issue #%s)`** — two spaces before the marker.
- **`published` has exactly one writer** (`project-conductor/SKILL.md:490`) and one reader (`:179`),
  and `conductor-entry-failure-split.test.sh` FK7 already pins the writer. That is what makes
  `delivered = wc -l < published` safe (ADR §D4).
- **`token-budget` live sites — the complete list, and four of them are assertions:**

  | site | what it is | action |
  |---|---|---|
  | `staging/plugin/scripts/autopilot-guard.sh:152-160` | the read | delete (Task 2) |
  | `staging/plugin/scripts/autopilot-disarm.sh:168` | the clear | replace with `scope` (Task 2) |
  | `staging/plugin/skills/autopilot/SKILL.md:449-450` | the "written by … respectively" claim | rewrite (Task 3) |
  | `docs/RUNBOOK-autopilot.md:187,195` | "five ways to be stuck" + the table row | four ways, row deleted (Task 3) |
  | `staging/plugin/scripts/tests/phase1.test.sh:44-49` | two assertions | **delete both** (Task 2) |
  | `staging/plugin/scripts/tests/external-dependency-gate.test.sh:222-224` | `EE4` | **delete** (Task 2) |
  | `staging/plugin/scripts/tests/autopilot-guard-disarm.test.sh:343,348` | `D1` fixture + loop list | **swap to `scope`** (Task 2) |

  Nothing else reads or writes it. `staging/plugin/skills/autopilot/tests/run-tests.sh` does not.
  Historical ADRs (0022, 0111, 0112, 0127) are **not edited in place** (ADR-0034 precedent).

- **`D2` in `autopilot-guard-disarm.test.sh` asserts `>= 6` `removed:` lines** and its fixture
  creates exactly 6. Dropping `token-budget` without adding `scope` in the same change takes it to
  5 and turns `D2` red. **This is why the SPEC says the two move on one commit** — Task 2 does both
  or neither.
- **`permission-mode-state.test.sh` PMP2** greps the flattened `autopilot/SKILL.md` for
  `must not be added as a ninth`. Adding check 9 makes that sentence's count wrong, so PMP2 must be
  re-anchored count-free (Task 7). PMP2 currently carries **no declared plant**; it gets one.
  PMP3 pins the *precedent*: `autopilot-build`'s header says `nine checks, all read-only Bash`
  because ADR-0110 added check 1b and updated the count in the same edit.
- **`fence-contract-coverage.test.sh` F4** requires every `fence-contract:` id to appear in a
  `*.test.sh` as either `run_fence "<id>"` or the literal `fence-contract: <id> -->`. F10's floor is
  `>= 15` and only rises, so no bump. The three new fences must be run, not mentioned.
- **`.claude/test-cmd` is a glob** over `staging/plugin/scripts/tests/*.test.sh` and picks a new
  harness up automatically. **`.github/workflows/docs-ci.yml`'s `shell-tests` is a named list** and
  does not. Four harnesses have been CI-dark from exactly this (ADR-0113); Task 9 wires it.
- **Baselines to record before touching anything** (Task 1 step 1): `phase1`,
  `external-dependency-gate`, `autopilot-guard-disarm` (Z1 floor 41), `permission-mode-state`
  (Z1 floor 26), `conductor-entry-failure-split`, `fence-contract-coverage` (Z1 floor 37),
  `plant-check.sh`.

### Standing rules for every task below

- **Bash 3.2, macOS.** `#!/bin/bash` + `set -u`. No `set -e`, no assoc arrays, no `mapfile`, no
  `<<<`, no process substitution. Every fence body must pass `bash -n`.
- **CHECKER vs REPORTER.** All three new fences are **CHECKERS**: the caller branches on the exit
  code. Say so in the block, and say it beside `weakening-scan.sh`'s reporter idiom wherever the two
  appear near each other, as `project-conductor` Step 4 already does.
- **Exit 3 is "the check DID NOT RUN"**, always distinguishable from "found nothing". Every new
  fence has one.
- **Plants at column 1.** `# plant: <id> | <staging-relative-path> | <needle> | <replacement>`. An
  indented declaration is silently skipped (`PC4`). The separator is literally ` | ` and **cannot
  appear inside a field** — no shell pipeline in a needle (ADR-0114 truncated three plants that
  way). Needle words join on `\s+`, it must match **exactly one** site, the replacement **cannot
  contain a newline** (ADR-0112). A `../docs/` prefix reaches the RUNBOOK; any other `..` is
  refused.
- **A plant that does not fire is a defect in the plant or in the assertion.** Inspect what the
  plant actually produced before believing what it reports (ADR-0090). A **negative** assertion
  cannot be planted by deleting a mechanism — the mutation must invert the condition or reintroduce
  the banned thing; where that is not expressible in one line, say so at the site rather than
  omitting the plant silently.
- **Prefix collisions (#355 is open).** `plant-check.sh` attributes a fired plant with
  `grep -q "^FAIL: $aid"`, a prefix match, within one file. In the new harness: keep each section's
  ids to a single digit (`KB1`…`KB9`), never create both `XX1` and `XX1b`, and never let a section
  reach `XX10`.
- **Prose assertions match a flattened, undecorated, case-insensitive copy** —
  `tr '\n' ' ' | tr -s ' ' | tr -d '\`*'` then `grep -qi`. A clause is the same clause whether it
  wraps, is bolded, is backticked, or opens a sentence. **Structural markers stay line-based**: a
  fence marker split across two lines is a marker the extractor cannot see, and flattening would
  hide exactly that.
- **Rule 12 — a needle must belong to the MECHANISM, not to the prose describing it.** Every file
  touched here legitimately names `token-budget`, `scope`, `--features` and `--only` while
  explaining them. Target a `printf`, a `case` arm, a path, an exit code — never the word.
- **Anchor-preserving.** Do not reword any heading or marker another harness extracts on. The known
  anchors in these files: `fence-contract: conductor-published-skip -->`,
  `fence-contract: conductor-fork-point -->`, `fence-contract: conductor-step4-nospec-skip -->`,
  `fence-contract: conductor-step4-init-guard -->`,
  `fence-contract: conductor-branch-c-entry-classify -->`, `fence-contract: autopilot-optin -->`,
  `fence-contract: autopilot-check-6 -->`, `fence-contract: autopilot-check-8 -->`,
  `fence-contract: autopilot-permission-posture -->`.
- **Test-vs-implementation split (ADR-0088).** Each task below names its sub-steps as **TEST** or
  **IMPL**. The tester dispatch owns the TEST sub-steps and confirms the RED; the coder owns the
  IMPL sub-steps and turns it GREEN. A task whose only sub-steps are TEST is a tester task; one
  with both is dispatched tester-first within the task.
- **Batch boundaries (ADR-0101).** Rule 1 outranks rule 2: never put an assertion in the same batch
  as the task it depends on. Tasks 1/2, 4/5 and 6/7 are RED/GREEN pairs and **must not share a
  batch**. Task 2's RED is a legitimate "the mechanism is not there yet"; Task 2's own stale-call-site
  edits go green in the same task because they are not evidence, they are maintenance.

---

## Task 1 — RED: the new harness, and what `token-budget`'s removal must look like (R-06, R-07)

**TEST only.** No implementation file is touched.

- [ ] Create `staging/plugin/scripts/tests/autopilot-run-scope.test.sh`. Header states: the issue,
      the three findings that killed `token-budget`, the ADR §D6 rule that its verdict is **not**
      transferred to `rtf-blocker`, and the derived-guard note (this file derives nothing at run
      time, so the count-guard idiom is deliberately absent — ADR-0086 §D1; `Z1` is an assertion
      floor, a different thing).
- [ ] Resolve paths the way its siblings do: `SCRIPTS`, `STAGING`, `SKILLS`, `REPO`, then `GUARD`,
      `DISARM`, `NA` (`autopilot/SKILL.md`), `PC` (`project-conductor/SKILL.md`), `RUNBOOK`, `SYNC`.
      `ok()`/`bad()` **must print `FAIL: `** with the colon — `plant-check.sh` attributes on
      `^FAIL: <id>` and a colon-less harness makes every plant read as "did not fire" (ADR-0128 §D4).
- [ ] Copy the `mk_root`, `run_fence`, `extract_fence`, `fence_body`, `subst_paths` and `out_of`
      helpers from `conductor-entry-failure-split.test.sh`. **`mk_root` must not increment a counter
      inside `$(...)`** — that runs in a subshell and every call returns the same directory
      (ADR-0096, met again in ADR-0110).
- [ ] **Section KB** — `KB1` the guard's `run_halt_checks` no longer reads `token-budget`, asserted
      **behaviourally**: a root carrying `limit=1\nspent=9` in `.claude/autopilot-state/token-budget`
      makes `autopilot-guard.sh --check` exit **0**. `KB2` a `RED` build-status still halts and
      `KB3` `rtf-blocker` still halts, from the same fixture shape — the positive twins, without
      which a guard that halts on nothing is indistinguishable from one that works (ADR-0039's
      correction). `KB4` the string `token-budget` no longer appears in `autopilot-guard.sh` at all.
- [ ] **Section KB, disarm half** — `KB5` a root carrying a `scope` file is cleared by
      `autopilot-disarm.sh` and the file is gone; `KB6` `token-budget` is not named in the disarm's
      cleared loop. Both from a foreign-session fixture so the recovery path is the one exercised.
- [ ] Declare a plant for each of `KB1`, `KB4`, `KB5`, `KB6`. **`KB2`/`KB3` are regression guards
      that pass before and after — label them as such in the file and give them no plant**, with the
      reason written at the site.
- [ ] Run it. Expect **RED on KB1, KB4, KB5, KB6** and green on KB2/KB3. Record the exact output in
      the task note; that output is this feature's only evidence that the assertions bite.

Budget: `staging/plugin/scripts/tests/autopilot-run-scope.test.sh` (~170 lines)

---

## Task 2 — GREEN: remove the read, swap the cleared set, repair the three stale call-sites (R-06, R-07)

**IMPL plus test maintenance.** The stale-call-site edits are not evidence; they are what stops a
correct change reading as a regression.

- [ ] **IMPL** `staging/plugin/scripts/autopilot-guard.sh`: delete the whole
      `if [ -f "$sdir/token-budget" ]` block from `run_halt_checks`. Add a `v1.5` header line
      recording that the halt is removed, naming finding 3 (a `PreToolUse` hook on the publish
      cannot stop the feature that breached the ceiling, only the one after) and stating that
      **`rtf-blocker`'s halt is deliberately kept** and why (ADR §D6). `rtf-blocker`'s read is
      byte-unchanged.
- [ ] **IMPL** `staging/plugin/scripts/autopilot-disarm.sh`: in the cleared loop, replace
      `"$SDIR/token-budget"` with `"$SDIR/scope"`. Extend the comment above the loop to say what
      `scope` is (the run-scoped bound written by `autopilot` Phase 0 check 9) and that carrying it
      into the next run would silently bound a run nobody bounded — the mirror of the sentence
      `published` already carries.
- [ ] **IMPL (stale)** `staging/plugin/scripts/tests/phase1.test.sh`: delete the two assertions at
      lines 44–49 (`guard: budget exceeded halts`, `guard: budget under limit allows`). Leave a
      one-line comment naming issue #365 where they were, so a reader diffing the file finds the
      reason rather than a gap. This file has no assertion floor.
- [ ] **IMPL (stale)** `staging/plugin/scripts/tests/external-dependency-gate.test.sh`: delete `EE4`
      and its fixture (lines 222–224), with the same one-line comment. `EE1`/`EE2`/`EE3`/`EE5` are
      untouched. This file has no assertion floor.
- [ ] **IMPL (stale)** `staging/plugin/scripts/tests/autopilot-guard-disarm.test.sh`: in `D1`'s
      fixture replace the `token-budget` write with a `scope` write, and replace `token-budget` with
      `scope` in the `for f in active build-status rtf-blocker … started-at` loop. `D2`'s `>= 6`
      holds — the fixture still creates six files. `Z1`'s floor of 41 is unaffected. Do **not** touch
      `D1`'s declared plant, which targets the loop's terminator, not the file list.
- [ ] Run `autopilot-run-scope.test.sh` — KB1, KB4, KB5, KB6 turn GREEN.
- [ ] **Run the FULL suite** (`.claude/test-cmd`), not just these files. A read removed from a hook
      that four harnesses exercise is exactly the contract change that breaks a test in a module
      nobody was looking at.

Budget: `staging/plugin/scripts/autopilot-guard.sh`, `staging/plugin/scripts/autopilot-disarm.sh`,
`staging/plugin/scripts/tests/phase1.test.sh`,
`staging/plugin/scripts/tests/external-dependency-gate.test.sh`,
`staging/plugin/scripts/tests/autopilot-guard-disarm.test.sh` (~60 lines)

---

## Task 3 — RED then GREEN: the `rtf-blocker` sentence and the RUNBOOK turn budget (R-08, R-10)

Both halves are prose in files nothing executes, so the assertions are flattened-text anchors on
mechanisms and claims, never on the names.

- [ ] **TEST** Section RB in the new harness. `RB1` `autopilot/SKILL.md` no longer claims a producer
      exists — the flattened copy must not contain the "written by the review step and this skill's
      `/goal` overlay respectively" claim. `RB2` it states `rtf-blocker` is **deliberately
      unproduced**. `RB3` it names the measured reason — that `concept-to-code` Gate 5's autopilot
      default is to skip review and `project-conductor` invokes `concept-to-code` on **both**
      branches, never `autopilot-build`. `RB4` the guard's read and the disarm's clear are both
      still present (the negative of the "tidy it away for consistency" failure), asserted against
      the two scripts, not against the prose.
- [ ] **TEST** Section TU. `TU1` the RUNBOOK's `/goal` template carries `N × 60` and not `200`.
      `TU2` it states the sample size (one measured chain, `n = 1`). `TU3` it calls the budget a
      fail-safe for a run that hangs rather than the bound. `TU4` it instructs re-derivation from
      the report's per-feature turns.
- [ ] **TEST** `KB7`/`KB8`: the RUNBOOK's stuck-table no longer carries a `token-budget` row, and
      its intro counts **four** ways to be stuck, not five. (Ids stay in section KB because the
      subject is the removal.)
- [ ] Run. Expect RED on RB1, RB2, RB3, TU1–TU4, KB7, KB8; RB4 green (forward guard, labelled).
- [ ] **IMPL** `staging/plugin/skills/autopilot/SKILL.md` §3.3 "Marker contract": rewrite the
      run-level halt bullet. `needs-human` and `rtf-blocker` are the two run-level halts;
      `token-budget` is gone; `rtf-blocker` carries the ADR §D6 paragraph verbatim, including the
      sentence that its verdict is **not** the same as `token-budget`'s and why.
- [ ] **IMPL** `docs/RUNBOOK-autopilot.md`: evening-launch step 2's `/goal` template becomes
      `Or stop after <N × 60> turns.` with the reasoning beside it (~50 measured, n = 1, plus
      margin; a fail-safe for a hung run, not the bound; re-derive from the report's
      `scope.turns_per_feature`). Delete the `token-budget` table row and correct "five ways" to
      "four ways".
- [ ] Run the new harness and `permission-mode-state.test.sh` (which also reads this RUNBOOK, via
      PMQ3 — verify it stays green).
- [ ] Declare plants for RB1, RB2, RB3, TU1, TU3, KB7. `RB4` and `TU2`/`TU4` take the plant that
      matches their mechanism where one is expressible; where the assertion is negative and a
      one-line mutation cannot reintroduce the banned claim, say so at the site.

Budget: `staging/plugin/skills/autopilot/SKILL.md`, `docs/RUNBOOK-autopilot.md`,
`staging/plugin/scripts/tests/autopilot-run-scope.test.sh` (~110 lines)

---

## Task 4 — RED: the `autopilot-scope-args` fence contract (R-01, R-02, R-11)

**TEST only.** The fence does not exist yet, so `run_fence` returns `EXTRACT_FAILED` — a RED for
exactly the right reason, which is what rule 1 of ADR-0101 protects.

- [ ] **TEST** Section AR in the new harness, driving `run_fence "autopilot-scope-args" "$NA" …`
      with a setup binding `_args` (the raw argument string) and `_root`.
      - `AR1` no arguments and no `scope:` block → exit 0, `SCOPE-PARSE: OK source=none features=`
        and no `only=`.
      - `AR2` `--features 2 --only 293,294` → exit 0, `source=arguments`, `features=2`,
        `only=293,294`.
      - `AR3` a `.claude/autopilot.yml` carrying `scope:` with `features: 3` and no arguments →
        `source=marker features=3`.
      - `AR4` the same marker **plus** `--features 2` → `source=arguments features=2` and the
        marker's `only:` list is **absent from the output**. This is the whole-block discard (R-02).
      - `AR5` `--features 0` → exit 2, message names the value.
      - `AR6` `--features x` → exit 2, message names the value.
      - `AR7` a `scope:` block that is present but empty → exit 2, message names the block. A
        malformed bound must not read as an absent one.
      - `AR8` `--dry-run` → exit 0, `dry_run=true`; without it, `dry_run=false`.
      - `AR9` an unreadable opt-in marker → exit 3, `DID-NOT-RUN`, distinct from AR7's exit 2.
- [ ] Declare a plant for each of AR1–AR9 that is positive. For `AR4` (a negative: the marker's
      `only:` must **not** survive) the mutation must **reintroduce** the merge, not delete the
      discard.
- [ ] Run. All nine RED with `EXTRACT_FAILED`. Record it.

Budget: `staging/plugin/scripts/tests/autopilot-run-scope.test.sh` (~150 lines)

---

## Task 5 — GREEN: Phase S in `autopilot/SKILL.md` (R-01, R-02, R-11)

- [ ] **IMPL** Add `## 1.3 Phase S — Resolve the run scope (issue #365, ADR-0129)` **above** §1.4
      Phase M. Prose states: it runs first because a `--features 0` typo must not cost a Phase P run
      and because a `--dry-run` must not trigger Phase P's writes; it reads the arguments and the
      opt-in marker and **nothing else**, because in auto-design mode `PROJECT.md` does not exist
      yet. This is a **CHECKER**.
- [ ] **IMPL** The `<!-- fence-contract: autopilot-scope-args -->` fence. Free variables `_args`,
      `_root`. Behaviour exactly as Task 4's cases. Emits one machine-readable line
      `SCOPE-PARSE: OK source=… features=… only=… dry_run=…` plus one human line naming the source
      in effect (R-02's "prints which source is in effect"). Exit 0 / 2 (bad invocation, naming the
      value or the block) / 3 (did not run).
- [ ] **IMPL** Update §1 "When to invoke" to `/skill autopilot [--features N] [--only <token>[,<token>]] [--dry-run]`
      and document each argument, including that **passing any scoping argument discards the whole
      `scope:` block** and why per-key override was rejected (a stale `only:` surviving a
      `--features 2` gives the operator one feature instead of two with nothing on screen).
- [ ] **IMPL** Document the `scope:` block shape in the opt-in marker, beside the existing `prep:`
      example.
- [ ] **IMPL** The `--dry-run` routing paragraph: on `dry_run=true`, skip Phase M, Phase P and Phase
      0 checks 1–8, run check 9's fence in read-only mode, print, and **stop** — no arming, no Phase
      1. State that checks 1–8 are deliberately skipped (they answer "may this run start" and two of
      them hit the network) and that a dry run **requires an existing `PROJECT.md`**.
- [ ] Run the new harness — AR1–AR9 GREEN. Run `fence-contract-coverage.test.sh`: F4 must find
      `run_fence "autopilot-scope-args"`.

Budget: `staging/plugin/skills/autopilot/SKILL.md` (~130 lines)

---

## Task 6 — RED: the `autopilot-scope-resolve` fence contract (R-05, R-06, R-11)

**TEST only.**

- [ ] **TEST** Section RS, driving `run_fence "autopilot-scope-resolve" "$NA" …` with a setup
      binding `_root`, `_scope_features`, `_scope_only`, `_scope_source`, `_dry_run`, against a
      fixture `PROJECT.md` carrying at least: a row with `(issue #293)`, a row with `(issue #29)`
      (the prefix-collision case), a hand-written row with **no** issue marker, and a `- [x]` row.
      - `RS1` an issue-number token resolves, and the scope file's `only=` line is the **exact
        roadmap line text** — not a slug.
      - `RS2` `--only 29` does **not** resolve to the `(issue #293)` row. The needle includes the
        closing parenthesis.
      - `RS3` a full topic-slug token resolves against the hand-written row.
      - `RS4` an unknown token → exit 1, the message **names the token**, and **no scope file is
        written**.
      - `RS5` a token matching two rows → exit 1, naming the token and both rows.
      - `RS6` a token naming a `- [x]` row **resolves** (checkbox state is not part of resolution)
        and the run is expected to deliver nothing — the SPEC's deliberate edge case.
      - `RS7` the written file carries `source=`, `features=` and one `only=` per resolved row, at
        `<root>/.claude/autopilot-state/scope`.
      - `RS8` `_dry_run=true` → exit 0, the list and the source are printed, and **no file exists**
        afterwards.
      - `RS9` no `PROJECT.md` → exit 3 `DID-NOT-RUN` naming the file, distinct from RS4's exit 1.
- [ ] Plants for RS1–RS3 and RS5–RS9. `RS4`'s "no file is written" half and `RS8` are negatives:
      the mutation must make the write happen, not delete a guard.
- [ ] Run. All RED with `EXTRACT_FAILED`.

Budget: `staging/plugin/scripts/tests/autopilot-run-scope.test.sh` (~180 lines)

---

## Task 7 — GREEN: Phase 0 check 9, and the count that had to stop being a count (R-05, R-06, R-11)

- [ ] **IMPL** `staging/plugin/skills/autopilot/SKILL.md` §2: add **check 9 — Run scope resolves**,
      after check 8. Prose states it is not the permission posture and that ADR-0110's prohibition
      is about *that* check having two answers, not about the section's length. It resolves against
      the `PROJECT.md` check 4 has just asserted exists.
- [ ] **IMPL** The `<!-- fence-contract: autopilot-scope-resolve -->` fence, behaviour exactly as
      Task 6's cases. **CHECKER.** Include, as comments at the site:
      - the closing-parenthesis rule for issue-number matching, with `#29` vs `#293` named;
      - that the slug derivation is **match-only** and what is stored is the exact line text, so a
        derivation disagreeing with the conductor's can only produce a loud unresolved token, never
        a wrong selection (ADR §D3);
      - that an empty `only` list means **every row is in scope**, never none.
- [ ] **IMPL** Reword §2's header sentence count-free: the permission posture "is not one of the
      checks in this section, and must not be added as one". Keep the rest of that paragraph and its
      ADR-0110 pointer byte-identical.
- [ ] **IMPL (stale)** `staging/plugin/scripts/tests/permission-mode-state.test.sh` PMP2: re-anchor
      on the count-free clause and keep the `ok`/`bad` message text meaningful (a needle on a count
      rots at every subsequent addition — ADR-0067 §F5). **Update the `bad()` message in the same
      edit**: a passing assertion whose message names a stale fact is a message nobody can trust
      (ADR-0120). Add the `# plant: PMP2 …` declaration this assertion has never had. `Z1`'s floor
      of 26 is unaffected.
- [ ] Run the new harness (RS1–RS9 GREEN), `permission-mode-state.test.sh` (PMP1–PMP4 green),
      `fence-contract-coverage.test.sh` (F4 finds `run_fence "autopilot-scope-resolve"`).

Budget: `staging/plugin/skills/autopilot/SKILL.md`,
`staging/plugin/scripts/tests/permission-mode-state.test.sh` (~140 lines)

---

## Task 8 — RED then GREEN: the conductor consumes the scope, and running out is quiet (R-01, R-03, R-04)

- [ ] **TEST** Section CG, driving `run_fence "conductor-scope-gate" "$PC" …` with a setup binding
      `_root`, `_feature`, `_autopilot`.
      - `CG1` `_autopilot=false` → exit 0, `SCOPE-GATE: INACTIVE`, byte-identical attended
        behaviour.
      - `CG2` no scope file → exit 0, `SCOPE-GATE: NONE`. Distinct from unreadable.
      - `CG3` the candidate's exact line text is in the `only=` list → exit 0, `IN-SCOPE`.
      - `CG4` it is not → exit 1, `OUT-OF-SCOPE`; the caller advances to the next `- [ ]`.
      - `CG5` an empty `only` list with a `features=` cap → `IN-SCOPE` (every row is in scope).
      - `CG6` `published` holds `features=` lines → exit 2, `EXHAUSTED`, **and the fixture asserts
        `PROJECT.md` is byte-unchanged and no `skipped-features` file was created**. This is R-04's
        whole content and it is asserted on the filesystem, not on a sentence.
      - `CG7` an unreadable scope file → exit 3, `DID-NOT-RUN`.
      - `CG8` a feature title that is a **prefix** of another does not collide (`grep -qxF`).
      - `CG9` the publish site names its `published` append as the delivered counter — a
        behavioural-adjacent prose assertion on the SKILL.md, so a future "optimisation" of the
        ledger cannot silently remove the bound.
- [ ] Run. All RED with `EXTRACT_FAILED` except `CG9`.
- [ ] **IMPL** `staging/plugin/skills/project-conductor/SKILL.md` Step 2: add the
      `<!-- fence-contract: conductor-scope-gate -->` fence **immediately before** the
      `conductor-published-skip` block, with a sentence saying why that order (an exhausted run ends
      regardless of which candidate is next, and both checks read the same ledger). **CHECKER.**
      Read `delivered` with `grep -c .` plus a `case` on non-digits — never `grep -c … || echo 0`,
      which yields a two-line `0\n0` on no match (issue #174).
- [ ] **IMPL** Branch table under the fence: `0` proceed; `1` skip this line and take the next
      `- [ ]`, exactly as `ALREADY`; `2` emit `project-conductor · SCOPE EXHAUSTED · <delivered>/<requested>`
      and go to **Step 6B**, writing **no** `[~]`, **no** `skipped-features` entry and **no**
      `needs-human`; `3` write `needs-human` and halt. The `2` branch carries the ADR §D5 paragraph:
      why ADR-0127 §D7's `[~]` is superseded (Step 2 selects the first `- [ ]`, so `[~]` is
      permanent), and that the rest of §D7 — never write `needs-human`, running out must be the
      least alarming ending — still stands.
- [ ] **IMPL** Step 5 branch A, at the `published` append: one paragraph stating that this append
      **is** the delivered counter Step 2's scope gate reads, that there is deliberately no second
      counter, and what breaks if the ledger is "optimised".
- [ ] Run the new harness and `conductor-entry-failure-split.test.sh` (FK1–FK10 must stay green —
      the new fence sits beside theirs and must not disturb the extraction).

Budget: `staging/plugin/skills/project-conductor/SKILL.md`,
`staging/plugin/scripts/tests/autopilot-run-scope.test.sh` (~200 lines)

---

## Task 9 — RED then GREEN: the report block, the wiring, and the record (R-09)

- [ ] **TEST** Section RP. `RP1` §4 documents an additive `scope` block with `source`, `requested`
      (`features`, `only`), `delivered`, `remaining_in_roadmap` and `turns_per_feature`. `RP2` it
      states that `published` and `scope` are read **before** the disarm, which deletes both.
      `RP3` `remaining_in_roadmap` is defined as the count of `- [ ]` rows at report time. `RP4`
      `turns_per_feature` is labelled an orchestrator self-report, derived by counting turns between
      `AUTOPILOT-PUBLISH` lines, and is stated never to be read by a gate. `RP5` no schema version
      bump is claimed (the block is additive on v2.2).
- [ ] Run. RP1–RP5 RED.
- [ ] **IMPL** `staging/plugin/skills/autopilot/SKILL.md` §4: add the `scope` block with a JSON
      example, the read-before-disarm sentence, and the self-report label with its ADR-0073
      justification (a disclosure feeding a human decision can only add information; ADR-0047 §A3's
      rule is about gates).
- [ ] **IMPL** `.github/workflows/docs-ci.yml`: append `autopilot-run-scope` to the `shell-tests`
      named list. **This is not a glob** and four harnesses have been CI-dark from exactly this
      omission (ADR-0113). Verify by reading the list back, not by assuming.
- [ ] **IMPL** Add `Z1` to the new harness — an assertion **floor**, not an exact count, set at the
      measured total minus a small margin, with the ADR-0083 §D3 reasoning at the site. Do not leave
      slack that could absorb a vanished assertion (ADR-0124's `Z1` lesson).
- [ ] **IMPL** Validate every declared plant one at a time with `plant-check.sh`. For each: confirm
      it matched exactly one site, confirm what it actually produced, and confirm the reported
      failing id is the intended one and not a **prefix** neighbour (#355). Any plant that does not
      fire is a defect in the plant or the assertion — fix the right one.
- [ ] **IMPL** `docs/architecture/ADR-0127-363-364-365-autopilot-long-session-runner.md`: append a
      dated `## Correction` naming §D5's `--budget` argument, §D6 (superseded in full), §D7's
      `[~]`/`skipped-features` clause (superseded in part, the rest standing) and §D8's "the token
      bound is the primary one". **Do not edit the body** (ADR-0034 precedent).
- [ ] **IMPL** `TODO.md`: close `VCS-010` with a pointer to ADR-0129 §D6 — the answer is neither a
      producer nor removal but the third option, a mechanism kept with its unreachability documented
      and measured.
- [ ] **IMPL** `CLAUDE.md`: add the ADR-0129 decisions section, following the existing form.
- [ ] Run the **full** `.claude/test-cmd` suite and then `plant-check.sh`. Both must be clean before
      this task closes.

Budget: `staging/plugin/skills/autopilot/SKILL.md`, `.github/workflows/docs-ci.yml`,
`staging/plugin/scripts/tests/autopilot-run-scope.test.sh`,
`docs/architecture/ADR-0127-363-364-365-autopilot-long-session-runner.md`, `TODO.md`, `CLAUDE.md`
(~180 lines)

---

## Requirement → task map

| ID | tasks |
|---|---|
| R-01 | 4, 5, 8 |
| R-02 | 4, 5 |
| R-03 | 8 |
| R-04 | 8 |
| R-05 | 6, 7 |
| R-06 | 1, 2, 6, 7 |
| R-07 | 1, 2 |
| R-08 | 3 |
| R-09 | 9 |
| R-10 | 3 |
| R-11 | 4, 5, 6, 7 |

## What is deliberately NOT in this plan

- **The three findings in the SPEC's *Findings recorded, not fixed* section.** No unattended review
  (finding 1), the unmarked leftover `SPEC.md` routing both ways wrong (finding 2), and the Step 1
  slug stamp skipping itself on a SPEC that mentions the marker (finding 3). Each needs its own
  issue. Do not open any of them here.
- **A shared `topic-slug` derivation** (ADR §A7). Named as a known gap, bounded by §D3's loud
  failure direction.
- **Session-marking the `scope` file** (ADR §D9/§A10). The question belongs to `autopilot-state`
  as a whole.
- **Any spend ceiling.** ADR §A1. If one is ever wanted it starts at the transcript, not at
  `task_metrics`.
