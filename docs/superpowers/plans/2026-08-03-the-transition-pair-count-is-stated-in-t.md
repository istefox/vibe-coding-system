# Implementation plan — the transition-pair count: one derivation, not three

- **Issue:** #289
- **ADR:** `docs/architecture/ADR-0120-289-transition-pair-count.md`
- **SPEC:** `SPEC.md` (topic slug `the-transition-pair-count-is-stated-in-t`)
- **Date:** 2026-08-03
- **Requirements:** R-01, R-02, R-03 (all three cited below; no other ID exists in the SPEC)

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield

---

## What was measured before this plan (do not re-litigate, do re-run)

Numbers the coder will need, and the three SPEC claims that did not reproduce. Full detail in the
ADR's Context section.

- **The count is 45.** Confirmed five ways including live execution of the pair block.
  Sub-counts `standard=25, express=6, hybrid=14`.
- **Three derivations exist, not one**, and they disagree: `GR3`
  (`gate5-state-removal.test.sh:89`, unbounded + deduped), `E7`
  (`concept-to-code-manifest-helpers-guards.test.sh:286`, block-bounded + not deduped),
  `ACTUAL_PAIRS` (`tracer-bullet-probe.test.sh:418`, unbounded + not deduped). The correct rule is
  **block-bounded AND distinct** — which is none of them.
- **The SPEC's assertion IDs are wrong.** The count assertions are `GR3`, `GR3b`, `GR3c` — not
  `GR3`/`GR4`/`GR5`. `GR4` is Gate 5's `Trigger:` prose; `GR5` is the live-reference check.
- **A fourth file the SPEC never names** holds four more literals and the second derivation:
  `concept-to-code-manifest-helpers-guards.test.sh` (`E1`, `E2`, `E3`, `E7`).
- **R-02 is already 2/3 done**: `TBP2` and `TBP3` in `tracer-bullet-probe.test.sh` already compare
  the script comment and the SKILL.md header total against a derivation. Only `SKILL.md:433`'s
  `(45 pairs)` is uncompared.
- **Four live defects**: D-A SKILL.md self-contradiction (header `25 standard` vs bullet
  `28 + 1 = 29`, with `E5` pinning the stale bullet); D-B stale messages in `E2`/`E3` naming 49
  while grepping 45; D-C `GR3b` is a `>= 3` line-floor; D-D zero plants on any count assertion.
- **Baseline is GREEN**: `gate5-state-removal` 15/0, `concept-to-code-manifest-helpers-guards` 34/0,
  `tracer-bullet-probe` 38/0, `pairs-completeness` 267/0 with `CI0/CI0b = 72`.

### Standing rules for every task below

- **Plants at column 1.** `# plant: <id> | <staging-relative-path> | <needle> | <replacement>`.
  ` | ` cannot appear inside a field (this silently truncated three plants in ADR-0114 — a shell
  pipeline in a needle is the trap). A replacement cannot contain a newline (ADR-0112). Exactly one
  match is required.
- **A plant that does not fire is a defect in the plant or the assertion.** Inspect what the plant
  actually produced before believing what it reports (ADR-0090).
- **Rule 12.** A needle must belong to the mechanism, never to the prose explaining it. Every file
  here legitimately *names* the number and the scripts while explaining them.
- **`grep -c … || echo 0` yields `0\n0`.** Use `|| true`.
- **Prose assertions** match a flattened, undecorated, case-insensitive copy.
- **Bash 3.2 / BSD tools.** No GNU-only `sed a\`, no `grep -P`, no empty ERE alternative `(a|)`
  (BSD grep rejects it and the sweep silently reads clean — ADR-0093).

---

### Task 1 — RED: the checker's contract and the divergence matrix (R-01, R-03)

Create `staging/plugin/scripts/tests/transition-pair-count.test.sh`, section `TC`, hermetic, no
`$HOME`, no network. It must be RED at the end of this task because the checker does not yet exist
(invocation returns 127, which is neither 0 nor 1 nor 2 nor 3 — assert the *contract*, so 127 fails
it).

Assertions to write:

- `TC0` — denominator guard: the fixture generator produced all five fixtures and the real
  transition script is readable. Guard the denominator, not the matches (ADR-0085).
- `TC1` — the checker exists, is readable, and exits within its own contract `{0,1,2,3}`.
- `TC2` — on the real tree: exit 0 and **stdout empty**. Emptiness is part of the contract.
- `TC3` — the stderr statistics line is printed on every run regardless of exit code, and names
  `pairs=45 standard=25 express=6 hybrid=14`.
- `TC4` — fixture **duplicate pair line**: the derived count stays **45** (distinct), not 46.
- `TC5` — fixture **pair-shaped `echo` outside the block**: stays **45** (bounded), not 46.
- `TC6` — fixture **one genuinely new pair**: becomes **46**, and the run reports findings (exit 1)
  because the three literals still say 45.
- `TC7` — fixture **block opening marker renamed**: exit **3**, and stderr names the derivation as
  not having run. Must NOT be exit 0 and must NOT be exit 1.
- `TC8` — wrong argument count → exit 2; unreadable target file → exit 2. Exit 2 is distinct from 3.
- `TC9` — a fixture whose SKILL.md header states a wrong total → exit 1 with a finding naming the
  **header** site.
- `TC10` — a fixture whose SKILL.md `(45 pairs)` helper line states a wrong total → exit 1 with a
  finding naming **that** site. This is the site nothing covered before (M6).
- `TC11` — a fixture whose script comment states a wrong total → exit 1 naming the **comment** site.
- `TC12` — a fixture whose header sub-counts do not sum to the total → exit 1 naming the sub-count.
- `TC13` — a fixture whose `standard` sub-count is wrong while the total is right → exit 1. This is
  D-A's shape and must be caught mechanically.
- `Z1` — assertion-count floor, `>= 14`, a floor and never an exact count (ADR-0083 §D3).

Fixtures are built by **patching a copy of the real script and the real SKILL.md**, never
hand-written minimal files. A hand-written fixture trips unrelated structure and reports a failure
about everything except the thing under test (ADR-0078's lesson).

`Budget: staging/plugin/scripts/tests/transition-pair-count.test.sh (~230 lines)`

**Checkpoint:** the file runs and reports RED on `TC1`–`TC13`. `TC0` passes. If everything is green,
the checker was accidentally created — stop.

---

### Task 2 — GREEN: `transition-pair-count.sh`, the single derivation (R-01)

Create `staging/plugin/scripts/tests/transition-pair-count.sh`.

- **Usage:** `transition-pair-count.sh <transition-script> <skill-md>`. Both are arguments, so a
  later issue can point it elsewhere without editing it (ADR-0117 §3.9).
- **Derivation:** block-bounded (open `PAIRS="$(mktemp)"`, close `if ! grep -Fxq`) **AND** distinct.
  Both halves load-bearing — `TC4` and `TC5` each isolate one.
- **Sub-counts** per block, from the script's own `# Express path transitions` /
  `# Hybrid path transitions` section comments; everything before the first is `standard`.
- **Literal extraction**, one distinctive anchor per shipping site, never a bare `45`:
  `Legal transition pairs (<n> total`, `atomically (<n> pairs)`, `§3.3, <n> transitions`.
  Also the header's `<n> standard + <n> express + <n> hybrid` triple.
- **Exit contract exactly as ADR-0120 §D2**: 0 clean / 1 findings / 2 bad invocation / 3 did not
  run. Zero derived pairs → **3**, never 0.
- **stderr statistics line on every run**, all exit codes included.
- Header must state: this is a CHECKER, it must never grow a `CLEAN` sentinel, and *why* — the
  reporter/checker confusion (ADR-0048, ADR-0117). Also state what the count **excludes**: producer
  exemptions (ADR-0095; currently zero) and the unconditional `any → failed|aborted` wildcard.

**Do not** touch `manifest-transition.sh` in this task. The script is byte-unchanged by this whole
chain except for Task 5's comment message fix, and that is in a different file.

`Budget: staging/plugin/scripts/tests/transition-pair-count.sh (~200 lines)`

**Checkpoint:** `transition-pair-count.test.sh` is fully GREEN. Run the checker by hand against the
real tree and confirm exit 0 with empty stdout and the stderr line reading
`pairs=45 standard=25 express=6 hybrid=14`.

---

### Task 3 — Fix D-A: SKILL.md's self-contradiction, and the test pinning it (R-02)

The header says `25 standard`; the Standard bullet says *"all 28 pre-existing pairs unchanged, plus
1 new pair for Step 4.5"* = 29. The script measures 25.

- Rewrite the Standard bullet in `staging/plugin/skills/concept-to-code/SKILL.md` to state **25**,
  preserving everything it says about *why* the Step 4.5 pair was the only one needed and about the
  ADR-0027 Gates-0c/0d lesson. Reword the count, not the reasoning.
- Update `E5` in `concept-to-code-manifest-helpers-guards.test.sh`: needle **and** message.
- Confirm `TC13` (Task 1) now genuinely covers this class — run the checker against the pre-fix
  SKILL.md and confirm it reported the sub-count finding. If it did not, `TC13` is wrong, not the
  file.

`Budget: staging/plugin/skills/concept-to-code/SKILL.md, staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh (~30 lines)`

**Checkpoint:** the checker exits 0 against the corrected SKILL.md; `helpers-guards` is green.

---

### Task 4 — Fix D-B: the two stale assertion messages (R-02)

`E2`'s failure message says *"does not state (49 pairs)"* while its grep looks for 45. `E3`'s
**success** message says *"states 49 transitions"* while its grep looks for 45 — a green run prints
a wrong number.

- Correct both messages to name what the assertion actually checks.
- Do **not** change the needles in this task; they are correct.

`Budget: staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh (~10 lines)`

**Checkpoint:** `helpers-guards` green; grep the file for `49` and confirm every survivor is
deliberate historical narrative in a comment, not an assertion message.

---

### Task 5 — Retire the three ad-hoc derivations into calls (R-01, R-02)

Each consumer stops re-deriving and calls `transition-pair-count.sh`.

- `GR3` (`gate5-state-removal.test.sh`) — consume the checker's derived count.
- `GR3b` — **replace, do not tune.** The `>= 3` line-floor over an OR'd needle set becomes an
  assertion that the checker reports **zero findings**, which is the per-site check. Its message
  must say a finding names the stale site.
- `GR3c` — keep the stale-49 ban as a cheap forward guard and **label it in the harness as passing
  before and after**, so it is not mistaken for fix evidence.
- `E7` (`concept-to-code-manifest-helpers-guards.test.sh`) — consume the checker.
- `ACTUAL_PAIRS` (`tracer-bullet-probe.test.sh:418`) — consume the checker.
  **`TBP1` keeps its `>= 40` floor and keeps asserting the PAIR, not the count.** ADR-0105 changed
  that assertion in kind on purpose; this chain must not undo it. `TBP2`/`TBP3` keep their
  comparisons, with the checker as their derivation input.
- Every rewritten assertion states, at its own site, that the derivation is **not** local and points
  at `transition-pair-count.sh` by name (an anchor, never a line number — ADR-0082).
- Raise `gate5-state-removal.test.sh`'s `Z1` floor if and only if the assertion count actually rose.
  **A floor that no longer tracks its population has stopped measuring** (ADR-0097 `RH2`).

`Budget: staging/plugin/scripts/tests/gate5-state-removal.test.sh, staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh, staging/plugin/scripts/tests/tracer-bullet-probe.test.sh (~90 lines)`

**Checkpoint:** all three harnesses green. Confirm by grep that no `awk`/`grep` pair-counting
expression survives in any of the three — if one does, a fourth derivation has been created.

---

### Task 6 — CI wiring (R-01)

- Add `transition-pair-count` to the `for t in …` list in `.github/workflows/docs-ci.yml`
  (`shell-tests` job).
- Run `pairs-completeness.test.sh` and confirm `CI0`/`CI0b` now report **73** and `CI1`/`CI2` are
  green. ADR-0113 added those four assertions precisely to catch a harness that never runs in CI.
- Confirm `transition-pair-count.sh` needs **no** `PAIRS` entry: it is not `*.test.sh` and
  `plugin/scripts/*.sh` is non-recursive, so `tests/` is outside the population. Verify by running
  `pairs-completeness.test.sh` and seeing no new FAIL, exactly as `path-rule-check.sh` behaves.

`Budget: .github/workflows/docs-ci.yml (~2 lines)`

**Checkpoint:** `pairs-completeness` green at 73/73.

---

### Task 7 — Plants for every new and rewritten assertion (R-03)

D-D: not one count assertion carried a plant before this chain. Close that for everything touched.

- Declare a plant at **column 1** beside each of `TC1`–`TC13`, and beside the rewritten `GR3`,
  `GR3b`, `E7`, `E5`, `E2`, `E3`, and the retargeted `ACTUAL_PAIRS` consumers.
- **The R-03 plant is a planted extra pair**: insert one additional
  `echo "<from>,<to>" >> "$PAIRS"` line into `manifest-transition.sh` and require the suite to go
  RED. This is the SPEC's literal wording and must be one of the declared plants.
- Watch each plant fire and **inspect what it produced**, not just that it reported (ADR-0090).
  Expect at least one non-firing plant on the first run — that is the mechanism working.
- Two traps that have each cost a session: a needle containing ` | ` is silently truncated
  (ADR-0114), and a replacement containing a newline collapses into nonsense (ADR-0112). A negative
  assertion cannot be planted by deleting a mechanism — the mutation must reintroduce the banned
  thing (ADR-0112).

`Budget: staging/plugin/scripts/tests/transition-pair-count.test.sh, staging/plugin/scripts/tests/gate5-state-removal.test.sh, staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh, staging/plugin/scripts/tests/tracer-bullet-probe.test.sh (~40 lines)`

**Checkpoint:** `bash staging/plugin/scripts/tests/plant-check.sh` green, `PC0`/`PC4` included, and
every declared plant fired. A plant that will not fire is fixed or its assertion is rewritten —
never waived.

---

### Task 8 — Full suite, disclosures, and the anti-regression sweep (R-01, R-02, R-03)

- Run the **full** test suite, not just the touched harnesses:
  `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`, then
  `bash staging/plugin/scripts/tests/plant-check.sh`. A contract change can break tests in unrelated
  modules that share the contract; three harnesses here read `manifest-transition.sh` and
  `SKILL.md`.
- Grep the whole of `staging/` for a surviving hardcoded pair total and confirm every survivor is
  either compared against the derivation or is deliberate historical narrative.
- Write the disclosure block into `transition-pair-count.sh`'s header, stating what a green run does
  **not** mean:
  - the extractor is coupled to the script's current shell idiom; a heredoc or array rewrite makes
    it exit 3;
  - the block boundary strings are now anchors in a file nobody previously had to treat as anchored;
  - the sub-count derivation rests on **section comments**, a weaker anchor than code — deleting one
    merges its pairs into the preceding block and yields a wrong sub-count with a right total;
  - producer exemptions and the `any → failed|aborted` wildcard are outside the count, by decision.
- Confirm `manifest-transition.sh` is **byte-unchanged** by this chain (`git diff --stat` on it must
  be empty). The pair graph is out of scope per the SPEC.

**Checkpoint:** whole suite green, plant registry green, `manifest-transition.sh` unmodified.

---

## Files created / modified

| file | action |
| --- | --- |
| `staging/plugin/scripts/tests/transition-pair-count.sh` | **create** — the single derivation, a checker |
| `staging/plugin/scripts/tests/transition-pair-count.test.sh` | **create** — section `TC`, the contract + divergence fixtures |
| `staging/plugin/skills/concept-to-code/SKILL.md` | modify — Standard bullet 28+1 → 25 (D-A) |
| `staging/plugin/scripts/tests/gate5-state-removal.test.sh` | modify — `GR3`/`GR3b`/`GR3c` consume the checker |
| `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` | modify — `E2`/`E3` messages, `E5` needle, `E7` consumes the checker |
| `staging/plugin/scripts/tests/tracer-bullet-probe.test.sh` | modify — `ACTUAL_PAIRS` consumes the checker; `TBP1` untouched in kind |
| `.github/workflows/docs-ci.yml` | modify — one harness name |
| `staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh` | **unchanged** — asserted in Task 8 |

## Contract changes

No observable runtime contract changes. `manifest-transition.sh`'s CLI, exit codes and pair graph
are untouched; the chain's behaviour is identical. The only new interface is
`transition-pair-count.sh`, consumed by the harness alone and by nothing that deploys.

**No grep for changed call-sites is required** for a runtime symbol, because none changes. The
call-site sweep that *is* required is the derivation sweep in Task 5's checkpoint and Task 8's
literal sweep — the three files that re-derive the count today are enumerated above and were found
by grepping `staging/` for pair-counting expressions, not left for the coder to discover.

## Risks & HITL gates

- **R1 — the extractor couples to a shell idiom.** Rewriting `manifest-transition.sh`'s pair block
  in another form silently becomes exit 3. Loud, but a new coupling. Mitigated by stating it in the
  header and by `TC7`.
- **R2 — `TBP1` must not be converted.** ADR-0105 changed it in kind on purpose. A coder
  "consolidating" it into an equality assertion would reverse an Accepted decision. Called out in
  Task 5.
- **R3 — a fourth derivation gets created by accident.** The mitigation is Task 5's grep checkpoint,
  not the harness, because a new correct-today derivation passes every assertion.
- **R4 — the sub-count anchors are comments.** Named in the disclosures rather than solved; solving
  it means restructuring the script, which the SPEC puts out of scope.
- **R5 — plants that will not fire.** Expected on first run. The failure mode is "fix the plant
  until it reports fired" without inspecting what it produced (ADR-0114 lost three that way).
- **R6 — CI list drift.** Adding a harness without the `docs-ci.yml` entry leaves it CI-dark.
  `CI1` catches it; Task 6 makes it explicit.
- **HITL gates:** commit (Gate 4.0 / Step 7), push, PR. No schema change, no migration, no deletion,
  no destructive command. `manifest-transition.sh` is a live state machine and is deliberately
  byte-unchanged — any diff to it is a red flag at review.

CODER-MODEL CANDIDATE: sonnet
