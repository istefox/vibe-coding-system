# Implementation plan — order the manifest `completed` transition before the Step 7 commit

- **Issue:** #410, and **#357** which it duplicates (PROJECT.md "Three attended items the waves
  cannot hold (2026-08-04)", item 3). Both close here.
- **SPEC:** `SPEC.md` (topic slug `410-order-the-manifest-completed-transit`)
- **ADR:** `docs/architecture/ADR-0135-410-completed-transition-before-commit.md`
- **Stack:** Markdown (`SKILL.md` instructions) + Bash 3.2 (harness). No runtime code, no new
  dependency, no schema change.

## Files this plan touches

| Path | Action |
|---|---|
| `staging/plugin/scripts/tests/commit-transition-order.test.sh` | **create** (harness, tester-owned) |
| `staging/plugin/skills/concept-to-code/SKILL.md` | modify — Step 7.0c, Step 7.1, E4, H5, Gate 4.0 waiver, five post-commit conditions |
| `.github/workflows/docs-ci.yml` | modify — one name in the `shell-tests` list |
| `staging/plugin/scripts/tests/step7-snapshot-collapse.test.sh` | modify — `SC1`'s window, **only if Task 3's checkpoint shows it red** |
| `CLAUDE.md` | modify — the record |
| `docs/architecture/ADR-0135-…md` | modify — one line, the follow-up issue number (Task 8) |

**Not touched, deliberately:** `manifest-transition.sh` (no new pair — ADR-0135 §D8), any
`manifest-set-*.sh` helper, `commit/SKILL.md`, the 57 files under `docs/manifests/`,
`staging/sync-to-claude.sh` (`concept-to-code/SKILL.md` already has PAIRS entry `:195`; the new
harness is a test and does not deploy), `PROJECT.md` (#410 has no roadmap row and #357's row is the
operator's to tick — ADR-0135 §Consequences).

## Batching and the expected reds (ADR-0101)

Rule 1 outranks rule 2: an assertion must not sit in the same batch as the task it depends on, even
though that leaves an intermediate checkpoint red. Every red below is **declared in advance** and is
ADR-0101's first class — a red in this batch's own newly written assertions, greened by a named
later task. Anything else halts.

| Batch | Tasks | Agent | Expected checkpoint state |
|---|---|---|---|
| A | 1 | **tester** (writes under `tests/`) + a **coder** sub-step for `docs-ci.yml` | RED: `CTO03`, `CTO04`, `CTO05`, `CTO11`, `CTO14`. Greens at Tasks 2–3 |
| B | 2, 3 | **coder** | GREEN for `CTO01`–`CTO11`, `CTO14`, `CTOZ1` |
| C | 4 | **tester** | RED: `CTO12`, `CTO13` — the outcome fence does not exist yet. Greens at Task 5 |
| D | 5 | **coder** | GREEN for the whole file |
| E | 6, 7, 8 | **tester** (Task 6) then **coder** (Tasks 7–8) | GREEN, plus `plant-check.sh` all-fired |

`test-write-scope.sh` (ADR-0088) denies a **coder** any write under a path component named `tests/`.
Tasks 1, 4 and 6 write `staging/plugin/scripts/tests/commit-transition-order.test.sh` and must be
dispatched to the **tester**. Task 1 also appends one name to `.github/workflows/docs-ci.yml`, which
is *not* under `tests/` — that is a **coder** sub-step in the same task. Do not merge the two
owners; do not let the tester attempt the yml.

## Assertion ids

`CTO01`…`CTO14` plus `CTOZ1`. **Two digits from the start, deliberately:** `plant-check.sh` decides
a plant fired with `grep -q "^FAIL: $aid"`, a **prefix** match, so `CTO1` would be satisfied by
`CTO10` failing. Do not introduce `CTO1b`-style suffixes into this file for the same reason. The
harness must emit `FAIL: <id>` with the colon, or every plant in it is unattributable
(`plant-check.sh` rejects such a harness outright).

---

### Task 1 — The ordering guard, written against the pre-fix file (R-09, R-10, R-11, R-12, R-16)

Create `staging/plugin/scripts/tests/commit-transition-order.test.sh`. Hermetic, no `$HOME`
dependency, bash 3.2, `set -u`, `ok`/`bad` emitting `PASS: <id>` / `FAIL: <id>`. Resolve the repo
from `$(dirname "$0")` so a `plant-check.sh` sandbox copy redirects with no change.

**Header** — state the rule, the three predicates, and that this is instance **14** of the
derived-guard pattern kept as a copy (ADR-0086). Re-derive the instance number from the files
before writing it: it has collided twice (ADR-0117 at 10, ADR-0131 at 12).

**Derivation** (all at run time, over `staging/plugin/skills/concept-to-code/SKILL.md`; no heading,
no block delimiter, no line number):

- `commit_lines` — lines matching a commit invocation: the line **begins** with `Invoke` or `Use`,
  optionally `the`, then `commit` bare or backticked, then ` skill`. Measured: exactly 4 today
  (Step 7 `:2727`, E4 `:2879`, H5 `:2986`, Gate 4.0 `:3699`).
- `exempt_lines` — the subset carrying `commit-order-exempt:` on the same line.
- `write_lines` — any line naming a `manifest-<word>.sh` helper. Measured: 61 today. Broad on
  purpose (ADR-0135 §D5).
- `term_lines` — the subset matching `manifest-transition.sh` … `completed completed`.
- `order_check <file>` — for each **non-exempt** commit invocation at line `n`, take the greatest
  `write_lines` entry `< n`; PASS iff it is in `term_lines`. Sets `OC_N` (non-exempt invocations),
  `OC_OK`, `OC_BAD`, `OC_WHY` (line numbers and the offending write, for the message).

**Assertions:**

- [ ] `CTO01` — denominator: `write_lines` ≥ 25 on the live file. Fewer means the write predicate
      stopped matching, which empties `CTO04` and reads as clean.
- [ ] `CTO02` — denominator: `commit_lines` ≥ 4 on the live file.
- [ ] `CTO03` — the waiver runs in reverse: `exempt_lines` ≥ 1, and **every** declared exemption sits
      on a line `commit_lines` matches, with a reason ≥ 40 characters. A stale waiver reads exactly
      like a clean bill of health (ADR-0081 `ZA4`). **RED until Task 2.**
- [ ] `CTO04` — live: `OC_BAD == 0`, message naming each offending invocation line and the write that
      preceded it. **RED until Task 3** (3 violations at Task 1; 4 before Task 2 adds the Gate 4.0
      waiver — the fourth is Gate 4.0 awaiting its declared exemption, not a fourth defect. Say so
      in the task note; do not read it as evidence of anything). (R-03, R-09)
- [ ] `CTO05` — live: `OC_OK >= 3`. A count guard, not a floor for convenience: a step dropping out
      of the population must fail loudly rather than shrink the denominator silently. **RED until
      Task 3.** (R-11)
- [ ] `CTO06` — fixture, wrong order (a commit invocation with a terminal transition **after** it):
      exactly 1 violation. This is the RED direction, permanently. (R-16)
- [ ] `CTO07` — fixture, right order: 0 violations, 1 resolved. The positive twin — a negative
      assertion pins nothing without it (ADR-0039's rule).
- [ ] `CTO08` — fixture, a `manifest-set-artifact.sh` line **between** the transition and the
      invocation: 1 violation. This is what makes §D1's 7.0b-then-7.0c ordering enforced rather than
      written down. (R-04)
- [ ] `CTO09` — fixture, a terminal transition with **no** invocation after it: 0 violations, 0
      resolved. Gate E3's "Commit later" and the abort branches, in isolation. (R-12)
- [ ] `CTO10` — live: at least one terminal transition remains unpaired, message naming Gate E3's
      "Commit later" branch as the reason it must stay that way. Green before and after — a forward
      guard; its plant is its only evidence. (R-12)
- [ ] `CTO11` — live: Step 7 states the §D2 invariant. Match against a copy that is **flattened,
      undecorated (backticks and asterisks stripped) and case-insensitive** — a clause is the same
      clause whether it wraps, is code-quoted, is bolded or opens a sentence (ADR-0073, ADR-0076,
      ADR-0080, ADR-0098, ADR-0101). **RED until Task 2.** (R-05)
- [ ] `CTO14` — live: the Standard and Hybrid terminal transitions are `manifest-transition.sh`
      invocations carrying the absolute `~/.claude/skills/concept-to-code/scripts/` prefix, not
      prose. Assert the **invocation shape**, never the helper's name — Step 7 will legitimately name
      the helper in prose while explaining the ordering, and a name-needle walks straight through a
      plant that deletes the call (rule 12; `SP1`'s exact history). **RED until Tasks 2–3.**
      (R-01, R-02)
- [ ] `CTOZ1` — assertion-count floor: this file ran ≥ 15 assertions. A vanished assertion does not
      read as a failure and nobody watches the count (ADR-0083).

**Fixtures use the real anchor strings**, copied verbatim out of `SKILL.md`, not paraphrases.

**Coder sub-step (not the tester):** append `commit-transition-order` to the `for t in …` list in
`.github/workflows/docs-ci.yml`'s `shell-tests` job. The list is explicit, not a glob;
`pairs-completeness.test.sh` `CI1` fails without it and `CI2` fails if the name does not resolve.

**Record in the task note:** the exact `CTO04` failure line. It is R-16's evidence and it is
unrecoverable after Task 3.

Budget: `staging/plugin/scripts/tests/commit-transition-order.test.sh`, `.github/workflows/docs-ci.yml` (~300 lines)

---

### Task 2 — Standard Step 7: the transition, the invariant, and Gate 4.0's waiver (R-01, R-03, R-04, R-05, R-08)

Edit `staging/plugin/skills/concept-to-code/SKILL.md` only.

- [ ] Insert **Step 7.0c** after 7.0b's `NOSPEC`/`COLLISION` bullet and **before** the "Both new
      paths must be passed to `commit` explicitly" paragraph. It carries, in this order: the
      invariant of ADR-0135 §D2 as one bold sentence over *manifest writes* (not over the sub-step
      list — a restatement of the list ages the moment a sub-step is inserted); one sentence saying
      it runs after 7.0b because `manifest-set-artifact.sh` has no terminal guard; a plain bash
      fence containing exactly one comment line and one command:

      ```text
      # Standard path: terminal before the commit invocation below (issue #410, ADR-0135).
      bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh "<manifest-path>" completed completed
      ```

      The placeholder is **quoted** here and unquoted at E4/H5 — that is what makes each of the three
      plant needles resolve to exactly one site, and `plant-check.sh` rejects a needle matching more
      than once. Then one line: a non-zero exit means the manifest is not terminal — report and
      stop, do not invoke `commit`; Step 7.1 is the backstop, not the primary guard. (R-01, R-04,
      R-05)
- [ ] Delete the prose transition at the end of Step 7 (`Transition to \`completed\`. Write final
      report.`) and replace it with the final-report instruction plus an explicit note that the
      transition already happened at 7.0c and must not be repeated. Leaving it would contradict
      7.0c in the same step. (R-03)
- [ ] Append the waiver to Gate 4.0's invocation line — `<!-- commit-order-exempt: … -->`, one line,
      reason ≥ 40 characters, naming ADR-0071's producer role and that the rule is about writes
      inside a commit-invoking step rather than a ban on committing a non-terminal manifest. The
      invocation itself is byte-unchanged. (R-08)
- [ ] **Do not** add the wrapper (`bash <<'FENCE_BASH'`) to the 7.0c fence. It contains no parameter
      expansion, so `fence-shell-divergence-scan.sh` does not flag it and it is outside ADR-0133's
      wrapper population — the same shape as E4's three existing transition fences. Adding one would
      put it in `WS1`'s population for no reason.

**Checkpoint:** `CTO03`, `CTO11` green; `CTO04` down to 2 violations (E4, H5); `CTO05` still red.

Budget: `staging/plugin/skills/concept-to-code/SKILL.md` (~35 lines)

---

### Task 3 — Express E4 and Hybrid H5: same ordering, stated boundary (R-02, R-03)

Edit `staging/plugin/skills/concept-to-code/SKILL.md` only.

- [ ] **Step E4** — move the existing `completed completed` fence **above** the invocation, prefixed
      by a unique comment line `# Express path: terminal before the commit invocation below (issue
      #410, ADR-0135).`, and drop the now-false trailing clause `After the commit skill returns:`
      from the invocation line. (R-03)
- [ ] **Step H5** — replace the prose clause `Transition \`step_h5_commit → completed\`.` with an
      explicit fence carrying the absolute helper path and a unique comment line `# Hybrid path:
      terminal before the commit invocation below (issue #410, ADR-0135).`, placed **above** the
      invocation. (R-02, R-03)
- [ ] Both steps gain one sentence saying Step 7.1's outcome check does **not** apply on this path,
      because it passes no `--include` and the manifest is never committed at all, so the check
      would halt every run — and naming the follow-up issue. Leave the issue number as the literal
      token `#TBD-410-FOLLOWUP`; Task 8 substitutes it. A reader meeting the asymmetry must find the
      reason at the site, not in an ADR they may not open (ADR-0135 §D4).
- [ ] Neither step's fence gets the ADR-0133 wrapper, for Task 2's reason.

**Checkpoint:** `CTO01`–`CTO11`, `CTO14`, `CTOZ1` all green. Run the **full** harness here, not just
this file: `SC1` in `step7-snapshot-collapse.test.sh` reads a 120-line window from the Step 7
heading and the invocation sat at offset 90 before this change. If `SC1` is red, widen its window to
200 — the value its sibling `spec-pointer-archive.test.sh:247` already uses on the same heading —
in one line, with the reason in a comment above it. **Do not widen it pre-emptively:** a relaxation
applied without evidence it was needed is indistinguishable from a relaxation applied to hide
something (ADR-0073), and `weakening-scan.sh` will flag the diff either way.

Budget: `staging/plugin/skills/concept-to-code/SKILL.md` (~30 lines)

---

### Task 4 — Assertions for the commit-outcome fence (R-06, R-07)

Extend `staging/plugin/scripts/tests/commit-transition-order.test.sh`. Tester-owned.

- [ ] `CTO12` — extract the fence declared `c2c-step7-commit-outcome` from `SKILL.md` **by its
      marker**, unwrap the ADR-0133 here-document body, and run it against four fixture repositories
      built with real `git init` + commits, substituting `<manifest-path>`:
      - a terminal manifest, committed and clean → `COMMIT_OK`, exit 0 (this is also the resumed /
        already-committed / nothing-to-commit case — assert it under that name in the message, since
        R-07 is what it proves);
      - a terminal manifest, tracked but modified → `COMMIT_UNCOMMITTED modified`, exit 1;
      - a terminal manifest, untracked → `COMMIT_UNCOMMITTED untracked`, exit 1;
      - a **non**-terminal manifest, committed and clean → `COMMIT_NONTERMINAL`, exit 1;
      - a path outside any repository → `COMMIT_OUTCOME_NORUN`, exit 3.
      The literal string `fence-contract: c2c-step7-commit-outcome -->` must appear in this file:
      that is one of the two needles `fence-contract-coverage.test.sh` `F4` accepts as proof a
      declared contract is executed. **RED until Task 5.** (R-06, R-07)
- [ ] `CTO13` — `SKILL.md` routes `COMMIT_UNCOMMITTED` to stop-and-report and states that no
      rollback is attempted and no transition is added. Choose the needle by **planting**, not by
      guessing: it must belong to the routing block and to nothing else. `MALFORMED`-style tokens
      and phrases like `not measured` have each been matched by three unrelated sites in this file
      before (ADR-0091). Verify the needle resolves to exactly one site before writing the assertion.
      **RED until Task 5.** (R-06)
- [ ] Raise `CTOZ1`'s floor to the new assertion count in the same edit. Left where it was it carries
      slack, and slack is what lets an assertion vanish while the floor stays green — the exact
      defect ADR-0124 removed from `SP5` and reintroduced in the same file by the change that
      removed it.

Budget: `staging/plugin/scripts/tests/commit-transition-order.test.sh` (~140 lines)

---

### Task 5 — Step 7.1: the commit-outcome fence and the post-commit gating (R-06, R-07)

Edit `staging/plugin/skills/concept-to-code/SKILL.md` only.

- [ ] Insert **Step 7.1** immediately after the invocation block's closing paragraph and **before**
      the post-commit push block. It carries: two sentences on why the verdict is read off the
      manifest rather than off the skill (a self-report is not a gate, ADR-0047 §A3; "nothing to
      commit" and "declined" are told apart by whether the manifest is committed); the declared,
      **wrapped** fence `c2c-step7-commit-outcome`; and the four outcome bullets.
- [ ] The fence body reads only `<manifest-path>`, substituted by the orchestrator — no `export`
      prologue, terminator at **column 0**. An indented terminator is swallowed into the
      here-document and destroys the exit code silently (ADR-0133). It emits `COMMIT_OK` (exit 0),
      `COMMIT_UNCOMMITTED untracked|modified` (exit 1), `COMMIT_NONTERMINAL current_step|status`
      (exit 1), `COMMIT_OUTCOME_NORUN <reason>` (exit 3). Terminality is read from the working-tree
      copy **plus** `git status --porcelain -- <path>` being empty; do not resolve a repo-relative
      path and do not use `git show HEAD:<path>` (ADR-0089's trap, ADR-0132's helper dependency —
      both avoided by construction). Use `git -C "$(dirname "$_m")"` so cwd cannot decide the answer.
- [ ] `COMMIT_OK` → proceed. Say in the bullet that this is also the verdict on a resumed or
      already-committed run, and that it is a **pass, not a decline**. (R-07)
- [ ] `COMMIT_UNCOMMITTED` / `COMMIT_NONTERMINAL` → stop and report, in the terms of ADR-0135 §D3:
      name the manifest path, say the tree is uncommitted, say no rollback is attempted and no
      transition is added because `completed` is absorbing (ADR-0078), and say the post-commit push,
      the PROJECT.md update and the cost snapshot do **not** run. (R-06)
- [ ] exit 3 → report **did not run**, naming the reason; not a pass, and the post-commit actions do
      not run. Absent, invalid and did-not-run are three states, not two (ADR-0076).
- [ ] Re-gate the four downstream conditions on `COMMIT_OK`: the push block's condition, the "After
      the commit skill completes successfully" line, the PROJECT.md block's "(not aborted)" clause,
      and the cost-snapshot block's "whether commit was made or aborted by user" line. That last one
      currently runs on **both** outcomes and must not.

**Checkpoint:** the whole harness green, including `fence-contract-coverage.test.sh` (`F3`/`F4`/`F7`
and `WS0`/`WS1` — the new contract makes 33; neither floor needs bumping, both guard the derivation
rather than a member).

Budget: `staging/plugin/skills/concept-to-code/SKILL.md` (~55 lines)

---

### Task 6 — Plants for every new assertion (R-15)

Declare one plant per new assertion in `commit-transition-order.test.sh`, at **column 1**
(`plant-check.sh` anchors on `^# plant:` and silently skips an indented one — `PC4`), four fields
separated by ` | `, which **cannot appear inside a field** (three plants were silently truncated by
this in ADR-0114). The replacement **cannot contain a newline**: collapsing a
`printf … >&2` / `exit N` pair onto one line makes the exit two more arguments to `printf`, so the
plant is inert while reporting as fired (ADR-0112, twice more in ADR-0132). Tester-owned.

- [ ] `CTO04`, `CTO05`, `CTO11`, `CTO14` — target `SKILL.md`. The needle for each transition is its
      **unique comment line joined to its command**; the bare command matches two or three sites and
      is rejected. `CTO11`'s needle is the invariant clause. `CTO14`'s must be the invocation shape,
      not the helper name.
- [ ] `CTO01`, `CTO02`, `CTO03`, `CTO06`–`CTO10`, `CTO12`, `CTO13`, `CTOZ1` — target this test file
      itself (self-targeting plants are expressible: `plant-check.sh` masks `# plant:` lines before
      matching). Mutate the **predicate or the fixture**, never the `ok`/`bad` message: a needle that
      lives in a message string satisfies itself and the plant walks through (`N9`'s history).
- [ ] Negative assertions (`CTO09`, `CTO10`) cannot be planted by deleting a mechanism — deleting
      something cannot break "X must not happen". Invert the condition or reintroduce the banned
      thing. If an assertion still cannot be planted, say so in a comment beside it naming why,
      rather than leaving a silent gap (`T12`'s precedent).
- [ ] Run `bash staging/plugin/scripts/tests/plant-check.sh`. Every plant must fire, and
      `PC0`/`PC1`/`PC2`/`PC3` must be green. **Inspect what each plant actually produced** — a plant
      that fires is not evidence until you have read the mutated file (ADR-0090, earned three times
      in ADR-0114). A plant that does not fire is evidence about the assertion, not a step to get
      past (ADR-0089).

Budget: `staging/plugin/scripts/tests/commit-transition-order.test.sh` (~40 lines)

---

### Task 7 — Full verification and the untouched invariants (R-08, R-13, R-14, R-16)

No file is written unless a check fails. Coder-owned.

- [ ] Full suite: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`.
      Green, 77 harnesses. Not just the new file: a contract change can break tests in unrelated
      modules that share the contract. (R-16)
- [ ] `bash staging/plugin/scripts/tests/transition-pair-count.sh` — **45**, unchanged. No pair was
      added and none was removed. (R-13)
- [ ] `git status --porcelain docs/manifests/` — only this chain's own manifest appears. The other
      57 files are byte-unchanged. (R-14)
- [ ] `bash staging/plugin/scripts/tests/manifest-project-root-terminal.test.sh` — `C1` and `C2`
      green. This is the assertion #410 was found by.
- [ ] `bash staging/plugin/scripts/tests/recovery-preflight.test.sh` and
      `gate4-implementation-axes.test.sh` — `RH1`, `RH2`, `RH4`, `RH4b`, `G8`, `G8b` green: Gate 4.0
      still delegates to the `commit` skill, still hand-rolls no git, and is still referenced by
      exactly the four proceeding branches. (R-08)
- [ ] `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — `CI0`, `CI0b`, `CI1`, `CI2`
      green: the new harness is in the `docs-ci.yml` list and the list still resolves.
- [ ] `npx markdownlint-cli2` (or the repo's configured invocation) — the ADR is under
      `docs/architecture/`, which the config does **not** ignore.

---

### Task 8 — File the E4/H5 follow-up and close the loop (R-17)

Coder-owned. Requires network and a HITL gate for the issue creation.

- [ ] Search for a duplicate first (`gh issue list --state open --search "manifest express hybrid
      commit"`). #357 and #410 are the same defect filed twice eight days apart; do not make it three.
- [ ] File the issue. Title: *"Express E4 and Hybrid H5 never commit the chain manifest at all"*.
      Body: those two paths have no Gate 4.0 producer and pass no `--include`, and `commit` never
      stages untracked files — so the manifest is written to disk and committed by nothing, in any
      state. Measured 2026-08-12: 0 Express and 0 Hybrid manifests exist, so nothing has been
      damaged; it is a forward gap. It is also why ADR-0135 §D4 scopes the Step 7.1 outcome fence to
      the Standard path: its verdict is the manifest's committedness, which on those paths is always
      "uncommitted", so applying it there would halt every run. Closing it is a design question with
      at least three answers — give E4/H5 an `--include`, give them a Gate-4.0-equivalent producer,
      or declare the single-session paths as deliberately not committing the manifest — which is why
      it is not bundled into an ordering fix.
- [ ] Replace the two `#TBD-410-FOLLOWUP` tokens in `SKILL.md` and the one reference in
      `docs/architecture/ADR-0135-…md` §D7 with the real number. Grep for the token afterwards: zero
      hits. (R-17)
- [ ] Update `CLAUDE.md` with a "Decisions from …" section for ADR-0135, in the established form.
      Include the twice-filed finding, the pairing rule and why the three obvious alternatives pass
      the pre-fix file, and the `commit` Step 5.5 `context.md` consequence.

---

## Verification checkpoints that are not tasks

- **Do not commit between Tasks 2 and 3.** Between them E4 and H5 still carry the defect while Step 7
  does not, and the guard is red. That is a declared intermediate state, not a shippable one.
- **The guard is an instruction's guard, not the instruction.** It asserts that the ordering is
  written correctly. Nothing asserts a model followed it — the only check that reads the actual
  behaviour is this chain's own Step 7, which is the first run of the new ordering and its own
  evidence.
- **Re-derive, do not trust.** The counts in the ADR (57 manifests, 61 write lines, 4 commit
  invocations, 3 terminal transitions, 45 pairs, 32 fence contracts) are measurements of 2026-08-12.
  If any differs at implementation time, correct the ADR in the same edit rather than coding against
  the stale number.

## Risks

- **A predicate that reads the file it guards.** Both new predicates match strings that `SKILL.md`
  legitimately contains while *explaining* them. Rule 12 has bitten this repository at least seven
  recorded times. Every `SKILL.md`-facing assertion here must be planted before it is believed.
- **The broad write predicate produces false REDs.** A sentence naming a `manifest-*.sh` helper
  inserted between 7.0c and the invocation reddens `CTO04`. Correct direction, deliberately no
  waiver, and the remedy is to move the sentence.
- **`SC1`'s 120-line window.** Task 3's checkpoint is where this surfaces. Do not widen it before
  seeing it red.
- **Four hard `~/.claude` dependencies at Step 7, now five.** The outcome fence fails closed; Step 7
  is worse than inert until `staging/sync-to-claude.sh --apply`.

## HITL gates

- Task 8's `gh issue create` — a write to a shared external system.
- Step 7's `commit` gate, as always. This chain is the first run of the new ordering: if the gate is
  declined, Step 7.1's `COMMIT_UNCOMMITTED` path fires for real, on its own feature.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
