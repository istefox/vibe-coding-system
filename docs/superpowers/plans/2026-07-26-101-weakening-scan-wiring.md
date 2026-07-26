# Plan — #101 Wire the anti-test-weakening detector into every unattended path

- **Issue:** #101 · **ADR:** `docs/architecture/ADR-0047-101-weakening-scan-wiring.md`
- **SPEC:** `SPEC.md`
- **Branch:** `feat/101-weakening-scan-wiring` (stacked on `feat/100-secret-scan-dependency-gate`)
- **Test command:** `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
- **Style:** TDD. Every assertion is seen RED before the edit that makes it GREEN, except the
  forward guards, which are labelled as such in the harness and are never fix evidence.

---

## Before you start — read these five things

1. **`review-triage-fix/` does not change.** Not `SKILL.md`, not `scripts/weakening-scan.sh`, not
   `tests/run-tests.sh`. If a task seems to need an edit there, it is the wrong task. Task 9 verifies
   this with `git status`.
2. **The detector prints `CLEAN` when it finds nothing.** Never gate on `[ -n "$out" ]` — it is
   always true. Gate on `printf '%s\n' "$out" | grep -q '^WEAKENED'`. ADR-0047 §D3.
3. **`grep -c` prints `0` AND exits 1 on no match.** `n=$(grep -c X f || echo 0)` yields the
   two-line string `0\n0`. Issue #100 hit this. Use `|| true`, never `|| echo 0`.
4. **Bash 3.2:** no associative arrays, no `mapfile`, no `${v^^}`, no process substitution.
5. **Assertion labels in the new harness are prefixed `W`** (`WA1`, `WC3`, …). `secret-dep-gate.test.sh`
   uses bare `F1`–`F6` and both print into the same CI job.

**Files this feature touches — nothing outside this list:**

| file | what |
|---|---|
| `staging/plugin/scripts/tests/weakening-wiring.test.sh` | new harness |
| `staging/plugin/skills/concept-to-code/SKILL.md` | Step 5 gate, schema, read contract |
| `staging/plugin/skills/autopilot-build/SKILL.md` | two circuit-breaker bullets, report field |
| `staging/plugin/skills/nightly-autopilot/SKILL.md` | marker-contract paragraph |
| `staging/plugin/skills/commit/SKILL.md` | Step 1 third reporter, Step 4 render phrase |
| `.github/workflows/docs-ci.yml` | one name appended to the explicit list |
| `CLAUDE.md`, `docs/vibe-coding-system.md`, `docs/GUIDA-USO-IT.md` | docs (Task 10) |

**Contract-staleness sweep, already run — these are the call sites of the things being changed.**
Do not go hunting; this is the complete list and each one is assigned to a task.

- `step5-report.json` readers: `concept-to-code/SKILL.md` (schema block + read contract, Task 3),
  `autopilot-build/SKILL.md:207-210` (circuit breaker, Task 5), `autopilot-build/SKILL.md:284`
  (`next_action` text — no change needed, it points at the file generically),
  `staging/plugin/scripts/tests/step5-checkpoint-review.test.sh` section D (asserts
  `checkpoint_reviews` only; an additive key cannot break it — **verify, do not assume**, Task 9),
  `staging/plugin/skills/concept-to-code/tests/run-tests.sh:326-329` (asserts the string
  `step5-report.json` is present; additive-safe), `docs/GUIDA-USO-IT.md:282` (describes the
  circuit-breaker condition list, now incomplete — Task 10).
- `commit/SKILL.md` Step 1 / Step 4 assertions: `secret-dep-gate.test.sh` F0–F4. F1/F2/F3 are
  positive greps over the Step-1 extract and stay green under an addition; F4 pins four filename
  patterns this feature must not touch. **The only negative assertion in that harness is G3**
  (no `PAIRS` entry for its own name) and nothing here can trip it.
- `weakening-scan.sh` callers: `review-triage-fix/SKILL.md:152,205` and its harness line 128 —
  untouched by design.
- Heading references into `concept-to-code/SKILL.md`: `workflow-dispatch-pins.test.sh` B4a/B4b/B5.
  **Rename no heading.** Adding a new unique heading is safe.

**Run the full suite after every task, not just the new file.** Four of the five edited files are
called by other skills; `.claude/test-cmd` globs the whole `tests/` directory for exactly this reason.

---

## Tasks

### Task 1 — RED: new harness, forward-guard sections and the registration self-assertion

- [ ] Create `staging/plugin/scripts/tests/weakening-wiring.test.sh`, `set -u`, bash 3.2, hermetic
      (`mktemp -d` + `trap`), no `$HOME` dependency, modelled on `secret-dep-gate.test.sh` lines
      1–52 (path resolution `SCRIPTS`/`STAGING`/`REPO`, `ok`/`bad`, `PASS`/`FAIL`, final
      `PASS=$PASS FAIL=$FAIL` + `[ "$FAIL" -eq 0 ]`).
- [ ] Header comment states: the detector is not modified by this feature; assertion labels are
      `W`-prefixed to stay distinguishable from `secret-dep-gate.test.sh` in the same CI log; the
      fixture diffs contain no key-shaped literal because `secret-dep-gate.test.sh` section D scans
      this file as part of the corpus.
- [ ] **Section WA — detector contract (FORWARD GUARDS, green on arrival, never fix evidence).**
      Resolve `W="$STAGING/plugin/skills/review-triage-fix/scripts/weakening-scan.sh"`.
      - `WA0`: the script exists at that path (the anchor every other WA/WB assertion reads).
      - `WA1`: empty stdin → output is exactly `CLEAN`, exit 0.
      - `WA2`: a non-test diff (`src/app.py`) → `CLEAN`.
      - `WA3`: a `deleted file mode` diff for `tests/test_y.py` → a line matching
        `^WEAKENED` and containing `deleted-test-file`; exit 0.
      - `WA4`: a diff adding `@pytest.mark.skip` to `tests/test_x.py` → `^WEAKENED` containing
        `skip/xfail-added`; exit 0.
      - `WA5`: exit code is 0 in the finding case as well as the clean case (pin the reporter
        contract explicitly — it is what §D3 depends on).
- [ ] **Section WB — the caller idiom, EXECUTED (contract evidence, green on arrival).**
      Using the outputs captured in WA:
      - `WB1`: `printf '%s\n' "$clean_out" | grep -q '^WEAKENED'` is FALSE.
      - `WB2`: `printf '%s\n' "$weak_out" | grep -q '^WEAKENED'` is TRUE.
      - `WB3`: **the trap** — `[ -n "$clean_out" ]` is TRUE even though there is no finding, so
        emptiness-gating would block every run. Assert it and say so in the failure message.
      - `WB4`: **the count trap** — `n=$(printf '%s\n' "$clean_out" | grep -c '^WEAKENED' || echo 0)`
        produces two lines, while `|| true` produces the single line `0`. Assert both.
- [ ] **Section WH — `review-triage-fix` untouched.** Behaviour + anchors, deliberately **not** a
      checksum: issue #105 will legitimately change the detector, and a hash would make that feature
      fight this test.
      - `WH1`: `review-triage-fix/SKILL.md` still contains `CIRCUIT BREAKER B — hard-fail anti-test-weakening.`
      - `WH2`: it still contains `scripts/weakening-scan.sh` (the string its own harness line 128 reads).
      - `WH3`: it contains **neither** `weakening_findings` **nor** `ADR-0047` — this feature's
        wiring did not leak into the skill it must not modify.
- [ ] **Section WG — registration.**
      - `WG1`: `docs-ci.yml`'s `for t in …` loop line contains `weakening-wiring`, matched with
        `grep -qE '[[:space:]]weakening-wiring[[:space:];]'` on the extracted loop line only (a
        match anywhere in the file would be satisfiable by a comment). **RED until Task 9.**
      - `WG2`: the `PAIRS` heredoc (extract with the same
        `awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f'` used by `pairs-completeness.test.sh`) still
        contains the exact line
        `plugin/skills/review-triage-fix/scripts/weakening-scan.sh|skills/review-triage-fix/scripts/weakening-scan.sh`.
        Forward guard: three more skills now depend on that one line deploying.
      - `WG3`: the `PAIRS` block does **not** contain `weakening-wiring` (the harness does not
        deploy — ADR-0047 §D10). Absence assertion.
- [ ] **Checkpoint:** `bash staging/plugin/scripts/tests/weakening-wiring.test.sh` runs and reports
      **exactly one FAIL: `WG1`**. If WA/WB/WH are not all green, the detector or the RTF skill is
      not in the state this feature assumes — stop and report, do not adjust the assertions.

### Task 2 — RED: assertions for the `concept-to-code` Step 5 gate

- [ ] Add **section WC** to the harness. Extract Step 5 once:
      `awk '/^### Step 5 —/{f=1} /^### Step 6 —/{f=0} f' "$CC" > "$TMP/c2c_step5.txt"`, with a
      `WC0` assertion that the extract is non-empty (every WC assertion below is meaningless
      otherwise — the F0 pattern from `secret-dep-gate.test.sh`).
      - `WC1`: exactly one occurrence of the heading
        `#### Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)` in the whole file
        (`grep -c` with `|| true`, compare to `1`) — uniqueness, mirroring
        `workflow-dispatch-pins.test.sh`'s `check_unique_ref`, because `autopilot-build` will name it.
      - `WC2`: the Step 5 extract resolves the script under
        `skills/review-triage-fix/scripts/weakening-scan.sh` **and** mentions `CLAUDE_PLUGIN_ROOT`
        (both halves — a block that names only `$HOME` silently never resolves in a plugin install).
      - `WC3`: the extract contains the anchored idiom `grep -q '^WEAKENED'`.
      - `WC4`: the extract warns about the sentinel — it contains `CLEAN` and a phrase forbidding
        emptiness-gating (assert on the literal `never gate on empty output`).
      - `WC5`: the pre-dispatch mark is present: `_pre5=$(git rev-parse HEAD` and the scan input
        `git diff "$_pre5"`.
      - `WC6`: the attended policy — `do NOT transition to` and `step_6_review` in the gate block.
      - `WC7`: the unattended policy — the gate block mentions `autopilot` and `halt`.
      - `WC8`: the trust rule — the gate block contains `do not trust the agent's self-report`.
      - `WC9`: **both** dispatch paths reach the gate. Count the occurrences of the literal
        `Anti-test-weakening gate` inside the Step 5 extract and require `>= 3` (the heading, the
        Workflow-path pointer, the fallback-path checkpoint pointer). Fail message must name which
        count was found.
      - `WC10`: the fallback path runs it per batch — the extract contains
        `at every batch checkpoint`.
      - `WC11`: the unavailable state — the extract contains `weakening_scan` and `unavailable`.
- [ ] Add **section WD** (schema + read contract), reading the same `$CC`:
      - `WD1`: the documented JSON schema block contains `"weakening_findings"`.
      - `WD2`: the schema shows the record shape — a line containing both `"file"` and `"reason"`
        within the `weakening_findings` array.
      - `WD3`: the read contract states `weakening_findings` non-empty is a `failure signal`.
      - `WD4`: the read contract states the additive rule — a report **without** the key is not
        malformed (assert on `absent` + `weakening_findings` in one line, or on the literal
        sentence chosen in Task 3; keep assertion and prose in agreement).
      - `WD5`: the contrast with ADR-0039 is stated — the same block contains both
        `checkpoint_reviews` and `never a failure signal` **and** `weakening_findings` with
        `always`.
- [ ] **Checkpoint:** run the harness. Expect `1 + 12 + 5 = 18` FAILs (`WG1` plus all of WC and WD).
      Record the exact number in the task notes; Task 3 must drive it back to 1.

### Task 3 — GREEN: `concept-to-code/SKILL.md` Step 5

- [ ] In the **pre-dispatch block cluster** (after "Pre-dispatch: plan structure validation"), add
      the mark capture:
      ```bash
      _pre5=$(git rev-parse HEAD 2>/dev/null)   # anti-test-weakening gate baseline (ADR-0047)
      ```
      with one line saying an empty `_pre5` (no commits, or not a git repo) makes the later
      `git diff` empty, which the scan reports as `CLEAN` — never an error.
- [ ] Add the new block **after** `#### step5-report.json schema and orchestrator read contract`
      and **before** `#### Fallback — Agent-tool batch dispatch (…)`:

      `#### Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)`

      containing, in this order: the §D2 resolution block verbatim (including the
      `_wscan=""` else-branch comment); the §D3 idiom with all three traps written out
      (`grep -q '^WEAKENED'` / never `[ -n "$out" ]` / never `grep -c … || echo 0`), including
      the literal phrase **`never gate on empty output`**; the scan input `git diff "$_pre5"`;
      the sentence **`The orchestrator runs this scan itself — do not trust the agent's self-report
      for this gate`**; the policy (attended: present findings, **do NOT transition to**
      `step_6_review` without acknowledgment — autopilot: **halt**, do not transition, do not
      proceed to Gate 5); the unavailable case recording `weakening_scan: "unavailable"`.
- [ ] Wire **both** paths into it, so the literal `Anti-test-weakening gate` appears at least three
      times in Step 5:
      - Workflow path, in the numbered list after "After the workflow completes": a new item between
        the current 3 and 4 — run the `Anti-test-weakening gate` block once, before deciding the
        transition.
      - Fallback path, item 2 of the batch-dispatch policy (beside `verify.sh` and `git status`):
        run the `Anti-test-weakening gate` **at every batch checkpoint** and again after the last
        batch. Use that exact phrase (`WC10`).
- [ ] Extend the schema block with `"weakening_findings": [ { "file": …, "reason": … } ]` and
      `"weakening_scan": "ran | unavailable"`.
- [ ] Extend the **orchestrator read contract** with two bullets placed immediately next to the
      existing `checkpoint_reviews` bullet:
      - `weakening_findings` non-empty → **failure signal**, same handling as `tasks_failed`;
        absent means none and is **not** malformed.
      - one sentence naming the contrast: `checkpoint_reviews` is never a failure signal,
        `weakening_findings` always is.
- [ ] **Do not rename any heading** and do not touch the two headings
      `Workflow dispatch path — Step 5 implementation (hook_verified = true)` and
      `… Step 6 review cycle (hook_verified = true)`.
- [ ] **Checkpoint:** full suite. `weakening-wiring` back to **exactly one FAIL (`WG1`)`.
      `workflow-dispatch-pins.test.sh`, `step5-checkpoint-review.test.sh`, `secret-dep-gate.test.sh`
      all still green.

### Task 4 — RED: assertions for `autopilot-build` and `nightly-autopilot`

- [ ] Add **section WE**:
      - `WE1`: `autopilot-build/SKILL.md` Step 5 circuit-breaker list has a `weakening_findings`
        condition ending in `halt` and `status=partial`.
      - `WE2`: its `abort_reason` for that condition is the literal
        `test weakening detected in Step 5`.
      - `WE3`: `autopilot-build/SKILL.md` Step 6 halts on an RTF anti-weakening BLOCKER —
        assert the literal `test weakening flagged by review-triage-fix in Step 6`.
      - `WE4`: `autopilot-report.json`'s documented schema block contains `weakening_findings`.
      - `WE5`: `autopilot-build/SKILL.md` names the c2c block **by heading**, and that heading
        exists **exactly once** in `concept-to-code/SKILL.md` — the `check_unique_ref` shape, run
        against the string `Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)`.
      - `WE6`: `nightly-autopilot/SKILL.md` states the inherited-halt contract: it contains
        `weakening`, `needs-human`, and `run-level` within its Phase 1 section.
      - `WE7`: `nightly-autopilot/SKILL.md` does **not** resolve or invoke `weakening-scan.sh`
        itself — absence assertion, pinning ADR-0047 §D8's "no fourth call site" decision so a
        later well-meaning addition has to argue with a red test.
- [ ] **Checkpoint:** 1 + 7 = 8 FAILs.

### Task 5 — GREEN: `autopilot-build/SKILL.md` and `nightly-autopilot/SKILL.md`

- [ ] `autopilot-build/SKILL.md` → `#### Step 5 — Implementation dispatch`: add to the **Circuit
      breaker** list a fourth bullet —
      `weakening_findings non-empty, or the gate's own scan prints a WEAKENED line → halt,
      status=partial, abort_reason="test weakening detected in Step 5"`. Add one line above the
      list pointing at c2c's `Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)` block by
      heading name (never a line range — ADR-0018).
- [ ] `autopilot-build/SKILL.md` → `#### Step 6 — Review + fix`: add a bullet beside the RED/GREEN
      pair — an anti-test-weakening BLOCKER in the review-triage-fix recap → `halt, status=partial,
      abort_reason="test weakening flagged by review-triage-fix in Step 6"`. Add the one-sentence
      reason: breaker B flags and never reverts, so without this the fix cycle's weakening reaches
      the commit.
- [ ] `autopilot-build/SKILL.md` → Phase 2 report schema: add `"weakening_findings": []`. Do **not**
      bump `"schema": "1.0"` (additive, ADR-0047 §D7).
- [ ] `nightly-autopilot/SKILL.md` → §3.3, after the existing marker-contract paragraph: state that
      a Step 5 anti-test-weakening halt means the feature never reaches `completed`, so the
      conductor writes the run-level `needs-human` marker and the guard blocks that publish and
      every subsequent one; the reason is recorded in `guard_halts[]`. State explicitly that this
      skill runs no scan of its own.
- [ ] **Do not modify `project-conductor/SKILL.md`** (ADR-0047 §D8).
- [ ] **Checkpoint:** full suite. Back to exactly one FAIL (`WG1`).

### Task 6 — RED: assertions for `commit` Step 1 and Step 4

- [ ] Add **section WF**. Extract Step 1 with the **same awk range** `secret-dep-gate.test.sh` uses
      (`/^### Step 1 —/` … `/^### Step 2 —/`) so both harnesses read the same region, plus a `WF0`
      non-empty anchor.
      - `WF1`: the Step 1 extract names `weakening-scan.sh`.
      - `WF2`: it resolves it under `skills/review-triage-fix/scripts/` (**not** under
        `hooks/` — the #100 path shape does not apply, ADR-0047 §D2) and mentions
        `CLAUDE_PLUGIN_ROOT`.
      - `WF3`: it reuses `git diff HEAD` as the input.
      - `WF4`: the attended policy is advisory — the extract states `WEAKENED` lines render in the
        Step 4 gate and stop nothing (assert `WEAKENED` and `advisory` in one line).
      - `WF5`: the `--autopilot` policy — a line containing `autopilot`, `WEAKENED`, and `abort`.
      - `WF6`: Step 4's rendering phrase now names three reporters: assert the literal
        `the SECRET, NEWDEP and WEAKENED lines from Step 1, verbatim`.
      - `WF7`: **forward guard, never fix evidence** — the four filename patterns
        (`` `.env` ``, `` `*secret*` ``, `` `*credential*` ``, `` `*.pem` ``) are still in the
        Step 1 extract. Duplicates `secret-dep-gate` F4 on purpose: this feature edits that region
        and the cheapest way to break #100 is to reflow the block.
- [ ] **Checkpoint:** 1 + 8 = 9 FAILs.

### Task 7 — GREEN: `commit/SKILL.md`

- [ ] Step 1, inside the existing **"Content scan and dependency gate (ADR-0046)"** block: add
      `_wscan` resolution (§D2 path shape — `skills/review-triage-fix/scripts/`, **not** `hooks/`)
      and `weakening_findings=$(git diff HEAD 2>/dev/null | bash "$_wscan" 2>/dev/null)` guarded on
      `[ -n "$_wscan" ]`. Retitle the block to name all three reporters.
- [ ] In the "Reading the result" list, add two bullets: `WEAKENED` lines are **advisory**
      attended and render in Step 4; in `--autopilot` mode a `WEAKENED` finding **aborts** the
      commit and prints the findings. Keep the existing `SECRET`/`NEWDEP` bullets byte-identical.
- [ ] Step 4: change the `Pre-commit findings` template line to
      `<the SECRET, NEWDEP and WEAKENED lines from Step 1, verbatim, …>`.
- [ ] Update the note under the Step 4 gate that currently reads "Issue #101 appends `WEAKENED`
      lines to this same block and adds its call beside the other two in Step 1" — it is now done;
      rewrite to past tense with the ADR-0047 reference. Keep the surrounding paragraph's meaning.
- [ ] Touch **nothing** in the "Invariant guardrails" section and none of the four filename
      patterns.
- [ ] **Checkpoint:** full suite, with attention to `secret-dep-gate.test.sh` F0–F4 — they read the
      same Step 1 region and must stay green. Back to exactly one FAIL (`WG1`).

### Task 8 — GREEN: register the harness in the second registry

- [ ] `.github/workflows/docs-ci.yml`: append `weakening-wiring` to the `for t in …` list in the
      `shell-tests` job (the last entry today is `secret-dep-gate`). `ci.yml` needs nothing — it
      globs.
- [ ] **Checkpoint:** the harness reports **FAIL=0**. This is the first run where it is fully green.

### Task 9 — Verification sweep

- [ ] `git status --short` shows **no** change under `staging/plugin/skills/review-triage-fix/`.
      If it does, revert it — ADR-0047's hard constraint.
- [ ] Run the full suite from a clean shell and confirm every harness is green, in particular
      `secret-dep-gate` (section D scans the new harness file as part of the corpus — a key-shaped
      literal in a fixture turns it red), `step5-checkpoint-review`, `workflow-dispatch-pins`,
      `pairs-completeness`.
- [ ] Confirm the shell is 3.2-safe: `bash --version` is 5.x on macOS via the default `bash`, so
      grep the new harness for the four forbidden constructs (`declare -A`, `mapfile`, `^^`, `<(`)
      and confirm none appear.
- [ ] Re-read `staging/sync-to-claude.sh` `PAIRS` and confirm all four edited SKILL.md files are
      covered (they are: nightly-autopilot, concept-to-code, autopilot-build, commit). **No PAIRS
      edit is expected in this feature** — if you find yourself adding one, stop and report.

### Task 10 — Docs

- [ ] `CLAUDE.md`: add a `## Decisions from the weakening-scan wiring chain (ADR-0047)` section
      after the ADR-0044 block, in the established shape (3–6 bullets: the in-place invocation and
      its coupling, the `CLEAN`-sentinel/`grep -c` caller traps, blocking-is-the-caller's-job,
      the autopilot Step 6 gap found on the way, instruction-not-enforcement).
- [ ] `docs/vibe-coding-system.md`: new changelog entry
      `### Addition 2026-07-26 (issue #101, anti-test-weakening detector wired into the unattended
      paths, ADR-0047)` inserted **immediately after** the `### Addition 2026-07-26 (issue #100 …)`
      block and before `### Update 2026-06-23 (workflow model pinning)`.
- [ ] `docs/GUIDA-USO-IT.md` line ~282: the Italian circuit-breaker sentence lists
      `test_result=RED`, task falliti, report mancante — add the weakening condition. Italian, one
      clause, matching the surrounding register.
- [ ] **Checkpoint:** full suite green; markdown links in the new/edited docs resolve (docs-ci runs
      lychee on `**/*.md`, and internal links are blocking).

---

## Definition of done

- [ ] `weakening-wiring.test.sh` is green and registered in **both** registries.
- [ ] The full suite is green, including every harness this feature did not write.
- [ ] `staging/plugin/skills/review-triage-fix/` is byte-identical to its state at branch point.
- [ ] The four SPEC success criteria that can be evidenced statically are pinned by an assertion,
      and the two that cannot (a real chain run blocking at the transition) are named as such in
      the report — this ships an instruction, not an enforcement (ADR-0047 A2).
- [ ] No new script, no new `PAIRS` entry, no `settings.json` change, no manifest schema change.
