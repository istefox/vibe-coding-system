# Implementation plan — 385, skill arguments substituted into `$<digit>` inside bash fences

- **SPEC:** `SPEC.md` (topic slug `385-skill-args-substituted-in-fences`), requirements R-01…R-05
- **ADR:** `docs/architecture/ADR-0132-385-skill-args-in-fences.md`
- **Evidence:** `docs/AUTOPILOT-RUN-AUDIT-2026-08-08.md` §F1 · `PROJECT.md` Phase 12 Wave 1
- **Style:** TDD. The tester writes the assertion and confirms its RED; the coder makes the change
  that greens it (ADR-0088 §generator/verifier).

---

## Read before starting

1. **Re-derive the population with your own parser before touching anything.** The brief's counts
   were wrong twice (13 vs the measured 14 in declared contracts; "7 awk" vs the measured 8). The
   ADR's §Context table is the current measurement — confirm it, do not assume it.
2. **Never write a literal positional token in prose or in a comment.** Write `$<digit>` or "a
   positional-parameter token". `autopilot-build:149` is the existing instance of that exact
   mistake — a comment banning an idiom by spelling it (rule 12).
3. **Expected reds.** The guard's R-01 assertion (`SFP4`) is RED from Task 1 until **Task 7** greens
   it. The residual count is predicted per task below. A checkpoint review that sees it must read
   this line, not treat it as a regression. It is safe because `autopilot-build`'s circuit breaker
   reads `step5-report.json` once at the END of Step 5 (ADR-0101 §BP6) and Task 7 is inside Step 5.
   This is ADR-0101 rule 1 outranking rule 2, applied deliberately: the guard must exist before the
   fixes so each fix has an unambiguous measurement, and the price is one assertion carrying a
   predicted red across six tasks.
4. **Plants.** Every new assertion gets a declared plant at column 1 (`plant-check.sh` anchors on
   `^# plant:` — ADR-0115 `PC4`). `plant-check.sh` decides a plant fired with a **prefix** match on
   `^FAIL: <id>` (open defect #355): choose ids that prefix no existing id, and verify each new id
   against the whole harness before declaring. A plant that fires is not evidence until you have
   looked at what it produced (ADR-0090).
5. **Bash 3.2 / BSD.** No GNU-only `sed -i` without a suffix, no `grep -P`, no `awk` interval
   dependence, no empty ERE alternative `(a|)` — BSD grep rejects it and the failure is silent in
   the worst direction (ADR-0093).
6. **`grep -c … || echo 0` yields a two-line `0\n0`** on no match. Use `|| true` (issue #174).

### Residual `$<digit>`-in-bash-fence count, per task

| after task | residual | what left |
|---|---|---|
| 1 (guard exists) | **19** | nothing — the guard is written, red |
| 2 | **12** | 3 shasum, 2 metric readers, 1 scope-block awk, 1 comment |
| 3 | **10** | the two `[~]` markers |
| 4 | **5** | `rel()`, 5 lines |
| 5 | **2** | `autopilot`'s parser, 3 lines |
| 6 | **1** | `project-conductor` Step 0, 1 line |
| 7 | **0** | `commit`'s `is_test_path()`, 1 line — **guard goes GREEN** |

---

### Task 1 — the derived guard, written RED (R-02, R-03)

**Files:** create `staging/plugin/scripts/tests/skill-fence-positional-tokens.test.sh`; edit
`.github/workflows/docs-ci.yml`.
*Budget: staging/plugin/scripts/tests/skill-fence-positional-tokens.test.sh (~330 lines), .github/workflows/docs-ci.yml (~1 line)*

- [ ] Copy the **indentation-tolerant** fence enumerator from
      `fence-contract-coverage.test.sh:71` (`enumerate_fences`) — `autopilot` indents fences inside
      numbered list items and a column-0 anchor undercounts (the "101 instead of 138" lesson).
      Keep it a copy; do not source the other file (ADR-0086 §D1, ADR-0132 §A6). Header note:
      *derived-guard instance 14* — derive the free number by sweeping
      `grep -rn 'DERIVED-GUARD PATTERN — instance' staging/plugin/scripts/tests/*.sh` plus
      `CLAUDE.md`; 10 and 12 are each already claimed twice and are not this feature's to fix.
- [ ] `population()` takes **file paths**, never a directory (ADR-0085), so the waiver fixture in a
      temp dir can be fed to the same code that reads the corpus.
- [ ] Partition every `$<digit>` line in `staging/plugin/skills/*/SKILL.md` into three buckets:
      **BASH**, **NONBASH**, **PROSE** (outside any fence).
- [ ] Assertions (ids chosen to prefix nothing existing — verify with a grep over all
      `staging/plugin/scripts/tests/*.test.sh` before declaring plants):
  - `SFP1` denominator: `SKILL_N >= 25` (measured 30). Fail loudly on an unmatched glob.
  - `SFP2` denominator: bash fences `>= 100` (measured 160 by this parser, 138 by
      `fence-contract-coverage`'s narrower one — the divergence is expected, both floors hold).
  - `SFP3` **partition identity**: `BASH + NONBASH + PROSE` equals the file-wide `$<digit>` line
      count. This is what catches a fence predicate that has narrowed and now under-reports, which
      a denominator guard cannot (ADR-0132 §D6).
  - `SFP4` **(R-01, expected RED until Task 8)**: the BASH bucket, minus declared waivers, is empty.
      On failure print every offender as `<skill>:<line>`.
  - `SFP5` (R-03): the NONBASH bucket is **non-empty** and contains `swiftui-pro`'s occurrence — the
      language filter is exercised by a real member, not by an exclusion list. If that Swift line is
      ever rewritten this must fail, not silently pass (ADR-0081 `ZA4`).
  - `SFP6` (R-03): a `$1` in `staging/plugin/skills/*/scripts/*.sh` is **not** in the population.
      Assert against a real helper once Task 3 creates one; until then assert the population's file
      list contains no path under `/scripts/`.
  - `SFP7` waiver parser, both directions, against a temp-dir fixture: a line carrying
      `# fence-dollar-exempt: <reason>` with a reason `>= 40` chars is excused; a shorter reason is
      not; a reason wrapped onto a second line is not (one line only — ADR-0082 `U3`).
  - `SFP8` waiver count guard: report the number of declared waivers and say **in the passing
      message** that at 0 the reason-length and staleness sub-assertions are vacuous.
  - `SFP9` informational: print the PROSE bucket count. Never fails (ADR-0132 §D8, SPEC scope).
  - `Z1` assertion-count floor, set to the actual total (ADR-0124: a floor with slack absorbs its
      own plant — set it at the real number, not below it).
- [ ] Append the new harness name to `.github/workflows/docs-ci.yml`'s named `for t in …` list.
      `pairs-completeness.test.sh` `CI1` fails without it (ADR-0113).
- [ ] Declare plants for `SFP3`, `SFP5`, `SFP6`, `SFP7`, `SFP8`. **No plant for `SFP4` yet** — it
      is expected-RED until Task 7, and `plant-check.sh` cannot distinguish a plant firing from an
      assertion that was already red. Its plant is declared at Task 7's checkpoint, the moment it
      first goes green.
- [ ] **Checkpoint:** run the file. Expect `SFP4` RED naming **19** offenders and everything else
      GREEN. If `SFP4` names a different number, the parser disagrees with the ADR's map — resolve
      that before proceeding, do not adjust the expectation.

---

### Task 2 — the eight in-place rewrites (R-01, R-05)

**Files:** `staging/plugin/skills/concept-to-code/SKILL.md` (338, 2031–2032, 3303),
`staging/plugin/skills/autopilot-build/SKILL.md` (149, 243),
`staging/plugin/skills/autopilot/SKILL.md` (184).
*Budget: staging/plugin/skills/concept-to-code/SKILL.md (~10 lines), staging/plugin/skills/autopilot-build/SKILL.md (~8 lines), staging/plugin/skills/autopilot/SKILL.md (~8 lines)*

- [ ] 3 × `shasum -a 256 X | awk '{print $1}'` → `shasum -a 256 X | cut -d' ' -f1`. Verify against
      real `shasum` output on this machine (`<hash>` + two spaces + `<file>`) before committing.
- [ ] 2 × `awk -F'\t' '$1=="TOKEN"{print $2}'` → `sed -n 's/^TOKEN[[:space:]][[:space:]]*//p'`.
      **Require at least one whitespace** after the token so `DELETED_LINES_X` cannot match.
      `agent-metrics.test.sh:119` confirms the producer emits `^TOKEN<TAB><value>$`; a negative
      `TEST_COUNT_DELTA` must survive.
- [ ] `autopilot:184` → field-free awk. A bare `/re/` pattern *is* `$0 ~ /re/`:
      `found && /^[[:space:]]+/ { print; next }` then `found { exit }`. Same program, record not
      named.
- [ ] `autopilot-build:149` — reword the comment so it describes the banned idiom without spelling
      it. This is the rule-12 instance the ADR names; the replacement must contain no literal token.
- [ ] **R-05 gates — these four contracts must still pass, unchanged:**
      `autopilot-build-check-2` and `autopilot-build-check-6` (both run by
      `fence-contract-coverage.test.sh` `E1`/`E2`/`E7`–`E9`/`E7b`–`E7f`),
      `c2c-gate2b-trust-probe` (`gate2b-trust-probe.test.sh`),
      `autopilot-scope-args` (`autopilot-run-scope.test.sh` `AR*`/`AV*`/`RS*`).
      Run all four files before and after.
- [ ] **Checkpoint:** `SFP4` RED naming **12**.

---

### Task 3 — `mark-roadmap-skipped.sh`, the two `[~]` sites (R-01, R-05)

**Files:** create `staging/plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh`; edit
`staging/plugin/skills/project-conductor/SKILL.md` (435, 682), `staging/sync-to-claude.sh`,
`staging/plugin/scripts/tests/conductor-entry-failure-split.test.sh`.
*Budget: staging/plugin/skills/project-conductor/scripts/mark-roadmap-skipped.sh (~60 lines), staging/plugin/skills/project-conductor/SKILL.md (~12 lines), staging/sync-to-claude.sh (~1 line), staging/plugin/scripts/tests/conductor-entry-failure-split.test.sh (~60 lines)*

- [ ] `mark-roadmap-skipped.sh <project-md> <feature-title>` reproduces the awk program **verbatim**
      inside the script, where `$0` is legal. Exact whole-line match, never a regex — a feature
      title is arbitrary GitHub text and can carry any sed metacharacter (the comment at both sites
      says so; carry it into the script).
- [ ] Contract: `0` = ran (whether or not a row matched), `2` = bad invocation, `3` = could not run.
      No `CLEAN` sentinel, ever.
- [ ] This is an ADR-0069-style extraction, not an ADR-0086 copy: the two sites are **one** question
      and two answers would be a roadmap disagreeing with itself. Say so in the script header.
- [ ] Both call sites resolve two-tier (`$CLAUDE_PLUGIN_ROOT/skills/project-conductor/scripts/…`
      then `$HOME/.claude/skills/…`) and on failure take each fence's **existing** `DID-NOT-RUN`
      exit-3 branch — `SPEC-COPY: DID-NOT-RUN — …` and `BRANCH-C: DID-NOT-RUN — …` — printing the
      `staging/sync-to-claude.sh --apply` remedy.
- [ ] `PAIRS` entry in `staging/sync-to-claude.sh`. **`pairs-completeness.test.sh` cannot see a
      skill `scripts/` file** (its `check_complete` covers `plugin/skills` with `*/SKILL.md` only),
      so assert the entry directly in the test file, ADR-0109 `MES0b` / ADR-0069 `PTB7` precedent.
- [ ] New assertions in `conductor-entry-failure-split.test.sh`: the script marks a matching row,
      leaves a non-matching file byte-identical, tolerates a title containing `[`, `.`, `*` and `/`,
      and both fences take the DID-NOT-RUN branch with an unresolvable helper. Declare plants.
- [ ] **R-05 gates:** `conductor-step4-nospec-skip` (`S1`–`S5`) and
      `conductor-branch-c-entry-classify` (`B*`) must still pass. Bind
      `CLAUDE_PLUGIN_ROOT="$STAGING/plugin"` in their setup (the pattern at
      `scope-guards.test.sh:231` and `fence-contract-coverage.test.sh:538`).
- [ ] **Checkpoint:** `SFP4` RED naming **10**.

---

### Task 4 — `repo-rel-path.sh`, c2c Step 5.0.1 (R-01, R-05)

**Files:** create `staging/plugin/skills/concept-to-code/scripts/repo-rel-path.sh`; edit
`staging/plugin/skills/concept-to-code/SKILL.md` (935–939 and the remediation list below the
fence), `staging/sync-to-claude.sh`,
`staging/plugin/scripts/tests/recovery-preflight.test.sh`.
*Budget: staging/plugin/skills/concept-to-code/scripts/repo-rel-path.sh (~70 lines), staging/plugin/skills/concept-to-code/SKILL.md (~30 lines), staging/sync-to-claude.sh (~1 line), staging/plugin/scripts/tests/recovery-preflight.test.sh (~40 lines)*

**The highest-risk task in this plan.** Step 5.0.1 guards entry to every Step 5 the chain runs.

- [ ] `repo-rel-path.sh <toplevel> <path>` reproduces `rel()` **verbatim**: the `dirname` guard, the
      `git -C … rev-parse --show-toplevel` read, the `-ef` device+inode identity guard, and
      `--show-prefix` + `basename`. Do not "simplify" any of the four — each is a fix for a measured
      defect (#239 symlinks, #344 case-insensitive APFS, and the foreign-repo case `RJ14` pins).
      Copy the fence's explanatory comment block into the script header.
- [ ] Empty path → print nothing, exit 0 (today's `[ -n "${1:-}" ] || return 0`).
- [ ] The fence keeps its classification logic and calls the helper four times. Resolve two-tier
      once, above the first call.
- [ ] Unresolved helper → new token **`PREFLIGHT_NOHELPER`**, exit 3, with the sync remedy. Add it
      to the fence's **Remediation** list beside `PREFLIGHT_NOREPO` / `PREFLIGHT_NOMANIFEST`, in the
      same words: *the check did not run; do not report it as a clean tree*.
- [ ] `PAIRS` entry + a direct assertion of it (same reason as Task 3).
- [ ] **Re-anchor `RJ13b`, do not delete it.** It greps `rev-parse --show-prefix` in the extracted
      fence and would take its third branch once the call moves. Point both halves — the
      banned string-prefix-strip check and the `--show-prefix` check — at `repo-rel-path.sh`, and
      keep the message that says *the mechanism changed to something unreviewed; re-read #344*.
      Record at the site that the assertion previously read the fence.
- [ ] `rj_run` must bind `CLAUDE_PLUGIN_ROOT="$STAGING/plugin"`. `RJ1`'s pre-#239 reconstruction
      (`sed -e 's#^DIRTY=.*#…#'` at `recovery-preflight.test.sh:531`) transforms the fence text and
      still references `rel` — verify it still produces `PREFLIGHT_CHAIN` on the fixture. **`RJ1` is
      red evidence for ADR-0089; if it stops reproducing the defect, stop and fix the reconstruction
      rather than the assertion.**
- [ ] Add assertions for the helper in isolation: symlinked root, differently-cased root, a path in
      a foreign checkout (`-ef` guard), a path whose directory does not exist, and exit 3 outside a
      repo. These are the first direct tests `rel()` has ever had.
- [ ] **R-05 gate:** `c2c-step5-preflight-dirty-classify` — `RJ0`, `RJ0b`, `RJ1`–`RJ9`, `RJ13`,
      `RJ13b`, `RJ14` all pass.
- [ ] **Checkpoint:** `SFP4` RED naming **5**.

---

### Task 5 — `scope-args-parse.sh`, `autopilot` Phase S (R-01, R-05)

**Files:** create `staging/plugin/skills/autopilot/scripts/scope-args-parse.sh`; edit
`staging/plugin/skills/autopilot/SKILL.md` (112–151), `staging/sync-to-claude.sh`,
`staging/plugin/scripts/tests/autopilot-run-scope.test.sh`.
*Budget: staging/plugin/skills/autopilot/scripts/scope-args-parse.sh (~80 lines), staging/plugin/skills/autopilot/SKILL.md (~35 lines), staging/sync-to-claude.sh (~1 line), staging/plugin/scripts/tests/autopilot-run-scope.test.sh (~30 lines)*

- [ ] Move the **initialisers and the parse loop only** (`_cli_features` … `_seen_only`,
      `set -- $_args`, the `while`/`case`). Everything below — the marker branch, the
      positive-integer guard, the `SCOPE-PARSE:` line — stays in the fence. The narrow excision is
      deliberate: it moves 4 plants instead of 12 (ADR-0132 §A3, measured).
- [ ] `scope-args-parse.sh <arg>…` prints exactly six `key=value` lines:
      `has_scoping_arg`, `seen_features`, `seen_only`, `cli_features`, `cli_only`, `dry_run`.
      The fence reads each with `sed -n 's/^key=//p'` — no field references.
- [ ] Preserve the unquoted word split: the fence invokes `bash "$_sap" $_args`, matching today's
      `set -- $_args`. Keep the comment explaining that an absent or flag-shaped value counts as
      NOT SUPPLIED (ADR-0129 A4) — move it into the script beside the code it explains.
- [ ] Unresolved helper → **exit 3**, the code Phase S already documents as "the check DID NOT RUN",
      plus the sync remedy. **Do not reconcile with Phase M's exit 1 thirty lines below** — say so
      at the site (ADR-0132 §D4).
- [ ] `PAIRS` entry + a direct assertion of it.
- [ ] **Retarget four plants** — `AR8` (`_dry_run=false`), `AV1`, `AV2`, `AV3` — from
      `plugin/skills/autopilot/SKILL.md` to `plugin/skills/autopilot/scripts/scope-args-parse.sh`.
      Verify each needle matches **exactly once** in the new file (`plant-check.sh` `PC2` rejects 0
      or many). `AR1`–`AR7`, `AR9` stay: their needles are in the marker/validation/output section
      that does not move — confirm that by re-running the registry, not by reading.
- [ ] Bind `CLAUDE_PLUGIN_ROOT="$STAGING/plugin"` in `setup_ar` (and any other Phase S setup).
- [ ] Add assertions for the script in isolation: no args, `--features 2 --only 293,294`,
      `--features` with no value, `--features` followed by a flag, `--dry-run`, and an unknown flag
      being skipped.
- [ ] **R-05 gate:** `autopilot-scope-args` — every `AR*`, `AV*` and `RS*` assertion passes with its
      expected exit code and message unchanged. Only the environment binding may change; no
      assertion text, no expected outcome.
- [ ] **Checkpoint:** `SFP4` RED naming **2**.

---

### Task 6 — `conductor-args.sh`, `project-conductor` Step 0 (R-01, R-05)

**Files:** create `staging/plugin/skills/project-conductor/scripts/conductor-args.sh`; edit
`staging/plugin/skills/project-conductor/SKILL.md` (39–56), `staging/sync-to-claude.sh`,
`staging/plugin/scripts/tests/conductor-entry-failure-split.test.sh`.
*Budget: staging/plugin/skills/project-conductor/scripts/conductor-args.sh (~70 lines), staging/plugin/skills/project-conductor/SKILL.md (~30 lines), staging/sync-to-claude.sh (~1 line), staging/plugin/scripts/tests/conductor-entry-failure-split.test.sh (~70 lines)*

- [ ] `conductor-args.sh <arg>…` prints two lines: `autopilot=<true|false>` and
      `fork_from=<ref-or-empty>`. Reproduces both parses — the `autopilot` first-token check and the
      `--fork-from <ref>` scan — with real positional parameters.
- [ ] The fence declares a **free variable `_args`**, bound by the orchestrator from the skill's
      argument string, and passes it unquoted: `bash "$_ca" $_args`. State the binding in prose
      above the fence, exactly as `autopilot` §1.3 states its own. **This changes rendered
      behaviour, because the rendered behaviour is wrong** — `$1` was filled by the substituter
      while `$@`/`$#` were the executing shell's (empty), so neither parse worked. Record that in
      one sentence at the site, citing audit §F1.
- [ ] Unresolved helper → `CONDUCTOR-ARGS: DID-NOT-RUN — …`, exit 3, sync remedy. There is **no safe
      default**: `false` prompts with nobody present (#329 class), `true` runs unattended when
      nobody asked. Write that reason at the site.
- [ ] The fence becomes abort-capable, so ADR-0083 §F3 requires a declaration and §F4 an execution.
      Add `<!-- fence-contract: conductor-step0-args -->` and execute it via `run_fence` in
      `conductor-entry-failure-split.test.sh` (which already has the machinery pointed at this
      file). Verify `fence-contract-coverage.test.sh` `F3`/`F4`/`F6`/`F7`/`F9` all stay green.
- [ ] `PAIRS` entry + a direct assertion of it.
- [ ] Assertions: bare `autopilot` → `autopilot=true`; `autopilot --fork-from main` →
      `autopilot=true fork_from=main`; no args → `autopilot=false fork_from=`;
      `--fork-from` with nothing after it; a first token that is not `autopilot`; unresolved helper
      → exit 3. Declare plants.
- [ ] **Checkpoint:** `SFP4` RED naming **1**.

---

### Task 7 — `commit`'s `is_test_path()` eliminated (R-01, R-05)

**Files:** `staging/plugin/skills/commit/SKILL.md` (228–240),
`staging/plugin/scripts/tests/human-gate-coverage.test.sh`.
*Budget: staging/plugin/skills/commit/SKILL.md (~12 lines), staging/plugin/scripts/tests/human-gate-coverage.test.sh (~15 lines)*

- [ ] Delete the function and inline its `grep -qE` at its **single** call site in the
      `for _f in $staged $tracked_modified $untracked` loop. Confirm the single call site first
      (measured: 3 occurrences — a prose mention, the definition, one call).
- [ ] The ERE is byte-unchanged. It replicates `weakening-scan.sh`'s `is_test()` on purpose
      (ADR-0048 §D3), and `HIA7b` asserts that; keep the explanatory prose above the fence intact.
- [ ] **Re-anchor `HIA6c`, do not delete it.** It greps the identifier `is_test_path` in
      `commit/SKILL.md` and would go red on a correct file. Re-point it at the **mechanism** — the
      ERE applied to each file inside the classification loop — and record at the site that it
      previously asserted a helper's name rather than its behaviour. Give the re-anchored assertion
      a declared plant, since a name-grep passing a mechanism-less file is exactly what a plant
      exposes.
- [ ] **No new file, no `PAIRS` entry, no deployment dependency** — this is ADR-0132 §D3's declared
      divergence from the SPEC's edge-case sentence. State the reason in one line at the site so it
      reads as a decision and not an oversight.
- [ ] **R-05 gate:** `human-gate-coverage.test.sh` `HIB0` and every `HIB*` dynamic
      extract-and-execute assertion passes. `HIB`'s extractor anchors on the heading
      `Test diff (H4, issue #115` — leave that heading alone.
- [ ] **Checkpoint:** `SFP4` **GREEN**, 0 offenders. Now add `SFP4`'s declared plant: reintroduce
      one positional token into a bash fence and confirm the assertion goes red naming that exact
      line. This is R-02's failing-direction verification and it is the point of the whole guard.

---

### Task 8 — record the mechanism (R-04)

**Files:** `CLAUDE.md`, `staging/plugin/scripts/tests/skill-fence-positional-tokens.test.sh`.
*Budget: CLAUDE.md (~35 lines), PROJECT.md (~4 lines), staging/plugin/scripts/tests/skill-fence-positional-tokens.test.sh (~25 lines)*

- [ ] Add a `## Decisions from the …` section to `CLAUDE.md` in this repository's house style:
      what the mechanism is (whitespace-split, 0-indexed, applied to the markdown body before the
      model sees it), that it is build-stamped to CC 2.1.226, the measured population, the two
      corrected counts, and the rule — *a bash fence in a `SKILL.md` must contain no
      positional-parameter token; logic that needs one lives in a `scripts/` file, because a file is
      never rendered*. Name the four new scripts and the guard.
- [ ] `SFP10`: the ADR exists at `docs/architecture/ADR-0132-385-skill-args-in-fences.md` and names
      the mechanism. `docs/` **is** copied into the plant sandbox, so this one is plantable.
- [ ] `SFP11`: `CLAUDE.md` carries the record. **This assertion always fails inside a plant
      sandbox**, because `plant-check.sh` copies only `staging/` and `docs/` (ADR-0122's `RG1`
      class). Declare **no plant** for it, label it at its own site as a known non-chaseable
      failure, and confirm its id prefixes no other id in the file (open defect #355).
- [ ] Update `PROJECT.md` Phase 12 Wave 1's three rows to done, with the ADR path.
- [ ] Raise `Z1`'s floor to the new actual total.

---

### Task 9 — full-suite verification and the check the harness cannot make (R-05)

**Files:** none (verification only).

- [ ] Run the **full** harness, not just the touched files:
      `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`.
      A contract change can redden a file nobody touched — six harness files are in scope here and
      the fence-contract population check reads all of them.
- [ ] Run `bash staging/plugin/scripts/tests/plant-check.sh`. Budget **> 25 minutes** (audit §F13)
      — run it in the background, do not time it out. Every plant must fire; a plant that does not
      fire names an assertion pinning nothing (ADR-0090: inspect what the plant produced, not the
      word "fired").
- [ ] Run `bash staging/sync-to-claude.sh` (dry run) and confirm the four new scripts appear.
- [ ] **HITL — the only check that reads the failing quantity.** After a human approves
      `bash staging/sync-to-claude.sh --apply`:
      1. `/skill autopilot --dry-run --only <n>` — safe by construction (Phase S resolves, prints,
         stops; nothing armed, nothing written).
      2. Compare every `bash` fence in the rendered body against
         `~/.claude/skills/autopilot/SKILL.md`. **Byte-identical is the pass condition.**
      3. Record the result and the CC build in ADR-0132 §Verification.
      A green harness is not evidence here: the harness reads files, and this defect is about
      rendered text differing from file text.

---

## Risks

- **R1 — c2c Step 5.0.1 (Task 4) is the chain's most load-bearing pre-flight.** A wrong edit refuses
  every Step 5. Mitigated by a verbatim move, `RJ0`–`RJ14` as the gate, and fail-closed on an
  unresolved helper. Do this task with the full `recovery-preflight.test.sh` green before and after.
- **R2 — four gates are worse than inert until sync.** An un-synced machine refuses rather than
  mis-classifies, which is the right direction and still a new failure. Every message prints the
  `staging/sync-to-claude.sh --apply` remedy; an instruction whose remedy names no runnable command
  is the defect ADR-0109 closed.
- **R3 — plant retargeting is silent when wrong.** A needle matching 0 or 2 sites is rejected as
  malformed (`PC2`), but a needle matching once *in the wrong place* fires for the wrong reason.
  Re-run the registry after Task 5 and read what each plant produced.
- **R4 — `RJ13b` and `HIA6c` are assertions on a name and a location, not on a behaviour.** Both
  break by design. Re-anchor them; deleting either loses ADR-0089 / ADR-0048 coverage.
- **R5 — the guard's own fence parser can drift from `fence-contract-coverage`'s.** Accepted
  (ADR-0086); `SFP3`'s partition identity is the mitigation, inside this file, without needing the
  other to agree.
- **R6 — `weakening-scan.sh` will flag Task 7** (a function deleted from a block the H4 gate uses)
  and possibly Task 4. No rule over a diff separates a correct removal from a relaxation
  (ADR-0073); expect the finding, explain it in `plan_deviations`, do not suppress the scan.
- **R7 — the counts in this plan are a 2026-08-08 snapshot.** Re-derive before citing.

## HITL gates

- **Gate A — before commit** (global rule; nothing here is committed unattended without it).
- **Gate B — `staging/sync-to-claude.sh --apply`.** Overwrites deployed files; shows a diff first.
  Required before Task 9's live verification, and it is what un-inerts the four new dependencies.
- **Gate C — push / PR.**
- No DB change, no migration, no deletion of user data. Nothing outside `staging/`, `docs/`,
  `CLAUDE.md`, `PROJECT.md` and `.github/workflows/docs-ci.yml` is touched.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
