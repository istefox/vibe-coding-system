# Implementation plan — a scoped test file must name the feature back

- **Issue:** none. Tracked as this chain's SPEC.
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md` (R-01 … R-12)
- **ADR:** `docs/architecture/ADR-0154-spec-coverage-scope-back-reference.md`
- **Stack:** Bash 3.2 (macOS-portable — no `[[ ]]`, no arrays, no `mapfile`, no `${var^^}`) and
  POSIX `awk`/`sed`/`grep`, matching the file being changed. One existing script, one existing
  harness, one existing frozen baseline, one agent contract file. **No new file, no new helper, no
  new dependency, no PAIRS entry, no `docs-ci.yml` append** — `spec-coverage` is already in the
  shell-tests loop and `spec-coverage.sh` is already deployed by PAIRS.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`

TEST-CMD MODE: brownfield

This feature has no external dependency: no third-party API, no consent flow, no cloud console.
Everything it touches is a file in this repository.

---

## Read this first — the gate blocks this feature today, and the fix is not the coder's

Measured 2026-08-18, before a line was written, against `SPEC.md` and a stub plan:

```text
spec-coverage.sh --spec SPEC.md --plan <stub naming only this feature's harness> --tests-root .
  -> STALE-WAIVER  R-10
     STALE-WAIVER  R-11
     STALE-WAIVER  R-12
     exit 3
```

`R-10`, `R-11` and `R-12` carry `(no-test: …)`, and all three tokens already exist inside
`staging/plugin/scripts/tests/spec-coverage.test.sh` as heredoc fixtures for the plan-citation
forms `RC3` and `RC4` assert (`- [ ] R-10 — a`, `### Task 3 — GREEN: thing (R-10, R-11)`). ADR-0138
§D4's reverse check reads that as an exemption protecting nothing and reports a structural error.

**No code in this plan can clear it.** The tokens are already there, and the `SCOPE-EMPTY` fallback
path finds them too. The fix is an edit to `SPEC.md` — outside the architect's write scope and
outside the coder's, so it is the operator's call at Gate 2 (ADR-0154 §D8):

1. delete the three `(no-test: …)` clauses from `R-10`, `R-11`, `R-12`;
2. keep Task 1's `RY11`/`RY12` assertions, which give those three ids real existence-level
   coverage.

Doing only (1) would leave three ids reading `COVERED` off a fixture collision — the defect wearing
the remedy's clothes. Doing neither halts the chain at Step 5 on an exit code that looks like a
defect in the work and is not.

## Read this second — 8 of this feature's 12 ids report COVERED before any work exists

Same run, with the three waivers stripped so the rest of the verdicts are visible:

```text
COVERED R-01   COVERED R-02   COVERED R-03   UNSCOPED R-04 1
COVERED R-05   UNSCOPED R-06 1   UNSCOPED R-07 1   UNSCOPED R-08 1
COVERED R-09   COVERED R-10   COVERED R-11   COVERED R-12
12 declared, 8 covered, 0 uncovered, 4 unscoped, 98 discovered, 1 in scope
```

Every one of the eight is a fixture token inside this feature's own harness, meaning something else
entirely. **A green gate on this feature is not evidence.** The evidence is each assertion going RED
against its declared plant (Task 7). This is ADR-0154 §D7 class 1 — the same-file namespace
collision — and this feature deliberately does not fix it.

## The files this plan names, and the two it deliberately does not

This feature's own rule applied to itself, which is the sharpest available test of the design.

**Named on purpose, and safe:**

- `staging/plugin/scripts/tests/spec-coverage.test.sh` — this feature's harness. It must name this
  plan's basename or `ADR-0154` back, or it descopes itself and the feature's own gate says so.
  Task 1 puts `ADR-0154` and this plan's basename in the new section header. Self-enforcing.
- `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv` — not discovered as a test file
  (its basename matches none of the discovery patterns).
- `staging/plugin/scripts/tests/plant-check.sh` — **not discovered** either, verified 2026-08-18:
  its basename matches no family in the discovery predicate (the `.test.`, `_test`, `Test`,
  `Tests` basename families, the `test-` prefixed shell scripts, and the per-skill all-tests
  runner). Its `R-01`/`R-05`/`R-12` tokens cannot reach this feature's gate.
- `staging/plugin/scripts/test-write-scope.sh` — discovered (`test-*.sh`) and it names `ADR-0048`,
  which this plan cites, so it will scope in. Verified 2026-08-18 to carry **zero** `R-NN` tokens,
  so it contributes nothing to any verdict. Named because the coder must know it exists.
- `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh`, `staging/plugin/agents/architect.md`,
  `docs/chain-decisions.md`, `CLAUDE.md`, `PROJECT.md` — none is a discovered test file (`.md` is
  excluded outright, and the script's basename matches no pattern).

**Measured while writing this file, and left in as the cheapest possible lesson.** An earlier
draft of the bullet above spelled the predicate's patterns literally, one of which is a real
basename shared by 11 per-skill test runners. Naming it in prose pulled all 11 into this feature's
scope — 13 files instead of 2. None carries an `R-NN` token, so nothing changed a verdict, but it
is rule 1 in one paragraph: a needle whose name is the mechanism matches the prose explaining it.
**Do not reintroduce that enumeration.**

**Not named anywhere in this plan, on purpose:** the sharded plant-registry harness and the PAIRS
completeness harness. Both are discovered, both carry `R-NN` tokens overlapping `R-01 … R-12`, and
both name ADRs this plan cites — so naming either would import foreign matches into this feature's
own gate. The registry is run through `plant-check.sh` (not discovered) and no PAIRS change is
needed. **Do not add a mention of them to this plan or to any task below.**

## Files this plan touches

| File | Owner | What changes |
|---|---|---|
| `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` | coder | the scope filter becomes a conjunction; the empty-scope guard splits into two states |
| `staging/plugin/agents/architect.md` | coder | one clause in the Output Format plan bullet |
| `staging/plugin/scripts/tests/spec-coverage.test.sh` | **tester** | new section `RY`, a new `RI7`, one additive extension to the `RS_LIVE` loop |
| `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv` | **tester** | rows regenerated under the new rule, dated header block accounting for the delta |
| `docs/chain-decisions.md`, `CLAUDE.md`, `PROJECT.md` | coder | the record |

Everything under `staging/plugin/scripts/tests/` is tester-owned: `test-write-scope.sh` denies the
coder any write there, and the `.tsv` baseline is inside that directory, so its regeneration is a
tester task and not a coder task. Files under `staging/` are mode 644 — run them as `bash <path>`.

## Assertion ids and the harness contract

New assertions use the `RY` prefix (free in this file — `RA`, `RB`, `RC`, `RD`, `RE`, `RF`, `RG`,
`RH`, `RI`, `RM`, `RN`, `RS`, `RT`, `RX` are taken), plus one `RI7` in the existing architect-contract
section. Every new block carries an id-mapping comment header — `# RY1/RY2 (R-01, R-03) — …` — the
form the corpus already uses. That is what makes coverage legible here; it is not what makes it
true (see "Read this second").

The new section header must contain both `ADR-0154` and `2026-08-18-spec-coverage-scope-back-reference.md`.

## Ownership and batching, with the expected reds declared in advance (ADR-0101)

An assertion must not land in the same batch as the task that greens it. Every red below is
declared; anything else halts.

| Batch | Tasks | Agent | Expected checkpoint state |
|---|---|---|---|
| A | 1 | tester | RED — `RY1`–`RY9`, `RY12`, `RI7` fail. **`RY11` GREEN on arrival** (the ADR already exists) — declared, not a defect |
| B | 2, 3 | coder | `RY1`–`RY9` and `RI7` green; `RY12` still red; `RS7`/`RS8a` RED until Batch C if any row flips |
| C | 4, 5 | tester | `RY10` added (**GREEN on arrival**, see Task 4); baseline regenerated; whole file green except `RY12` |
| D | 6 | coder | the record lands; `RY12` greens; full suite green |
| E | 7 | tester | plants declared, each seen RED once, registry green |

---

### Task 1 — The `RY` assertions and `RI7`, written RED (R-01, R-02, R-03, R-04, R-05, R-08, R-10, R-11, R-12)

**Agent:** tester. **File:** `staging/plugin/scripts/tests/spec-coverage.test.sh` only.

Add section `RY` after the existing `RX` section, header naming `ADR-0154` and this plan's basename,
and one `RI7` inside the existing architect-contract section. Fixtures are hermetic `$TMP` trees in
the idiom the file already uses; no fixture may contain a key-shaped literal.

- `RY1` (R-01, R-03) — the plan names **two** discovered harnesses; `alpha.test.sh` names the plan
  back and carries no id, `beta.test.sh` carries `R-01` and names nothing back. Expect
  `UNSCOPED<TAB>R-01<TAB>1`, exit 1. The two-file shape is load-bearing: with one file the run
  would take the new empty-scope state instead and prove something else.
- `RY2` (R-01, R-02) — positive twin: the same tree with `beta.test.sh` naming the plan's basename
  (with its `.md`) → `COVERED`, exit 0, no `UNSCOPED` line.
- `RY3` (R-02) — the OR's second branch: `beta.test.sh` names an `ADR-NNNN` the plan cites (and not
  the plan's basename) → `COVERED`, exit 0.
- `RY4` (R-02) — the negative twin of `RY3`: `beta.test.sh` names an `ADR-NNNN` the plan does **not**
  cite → `UNSCOPED`. Without this, `RY3` is satisfied by a rule that accepts any ADR id at all.
- `RY5` (R-02) — whole-token: `beta.test.sh` names only `<plan-stem>.manifest.yml` → not a
  back-reference → `UNSCOPED`. Pins the escaping and the anchor pair, and pins the refusal of a
  stem-only match (ADR-0154 §A3).
- `RY6` (R-05) — the new state: the plan names exactly one discovered harness, it carries `R-01`,
  it names nothing back. Assert all four separately: stderr contains `SCOPE-NO-BACKREF`; stderr
  names the dropped file's basename; stderr does **not** contain `SCOPE-EMPTY`; stdout is
  `UNSCOPED<TAB>R-01<TAB>0` with exit 1.
- `RY7` (R-05) — the other direction (rule 8): the plan names **no** discovered test file → stderr
  contains `SCOPE-EMPTY`, does **not** contain `SCOPE-NO-BACKREF`, stdout falls back to
  `COVERED<TAB>R-01`, exit 0. Together with `RY6` this is what "told apart" means.
- `RY8` (R-04) — forward guard: a `.md` file that names the plan back and whose basename the plan
  names is still excluded → `UNCOVERED<TAB>R-01<TAB>tests`. Half 2 cannot re-admit a `.md`.
- `RY9` (R-01) — forward guard, the other half of "either half alone is not enough": a file that
  names the plan back but whose basename the plan never names stays out of scope → `UNSCOPED`.
- `RY11` (R-11, R-12) — **green on arrival, declared.** `docs/architecture/ADR-0154-spec-coverage-scope-back-reference.md`
  exists and contains, matched on a flattened undecorated case-insensitive copy (rule 3): the two
  refused designs with their numbers (`11 of 53`, `87 of 893`), and a clause naming
  `architect.md`'s contract line as an instruction rather than an enforcement.
- `RY12` (R-10) — RED until Task 6: a `docs/chain-decisions.md` heading naming `ADR-0154`, one
  `CLAUDE.md` chain-decision index line naming `ADR-0154`, and a `PROJECT.md` row naming it.
- `RI7` (R-08) — RED until Task 3: `staging/plugin/agents/architect.md` states that a plan names the
  harness it creates and that the harness names the plan or its ADR back. Matched on the flattened
  copy, needle chosen so it cannot be satisfied by the surrounding prose (rule 1).

R-04's wider claim — no verdict changes meaning — is carried by `RY8` plus the 145 pre-existing
assertions in this file staying green, not by a new assertion of its own.

Budget: staging/plugin/scripts/tests/spec-coverage.test.sh (~230 lines)

### Task 2 — The conjunction and the two-state empty-scope guard (R-01, R-02, R-03, R-04, R-05)

**Agent:** coder. **File:** `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` only.

Build the back-reference key set once per run, before the existing scope loop: the plan's basename
including its `.md`, plus every `ADR-` followed by exactly four digits found in `$PLAN` with the
both-sides anchor the file already uses for `R-NN` (left `(^|[^A-Za-z0-9_])`, right `([^0-9]|$)`),
de-duplicated. Regex-escape the basename exactly as the existing half does. Assemble one ERE
alternation, anchored `(^|[^A-Za-z0-9_])(…)([^A-Za-z0-9_]|$)`.

Extend the existing loop so a file enters `$TESTFILES_SCOPED` only when half 1 matches **and** the
file's own text matches that alternation. Count the files half 1 admitted and record those half 2
dropped (path list, for the message). The loop must keep its `done <"$FILE"` redirect form — a pipe
would put the counters in a subshell.

Split the guard:

```text
scope empty?
  half-1 count > 0  ->  SCOPE-NO-BACKREF on stderr, naming up to 3 dropped files and the one-line
                        remedy ("add <plan basename> or one of <ADR ids> to one of them").
                        NO fallback. Scope stays empty.
  half-1 count == 0 ->  SCOPE-EMPTY on stderr, unchanged wording, unchanged fallback to $TESTFILES.
```

Append one trailing clause to the `--tests-root` summary line naming the count dropped by half 2.
Verified safe: the only assertion reading that line does a substring match on
`0 test file(s) discovered`.

Nothing else changes: not the discovery predicate, not the `.md` exclusion, not `--list`, not the
silent no-ids path, not the `(no-test: …)` waiver, not `grep_boundary_test_all`, not one exit code.
Update the contract header at the top of the file to name the new stderr token and ADR-0154, and
disclose at the filter's own site that half 2 is a conjunct and not a second discovery rule.

Budget: staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh (~75 lines)

### Task 3 — The producer-side convention, in the architect's output contract (R-08)

**Agent:** coder. **File:** `staging/plugin/agents/architect.md` only.

One clause in the **Implementation plan** bullet of Output Format, beside the requirement-id
citation contract it extends: a plan names the harness it creates, and that harness names the plan's
basename or one of the ADRs the plan cites back, or `spec-coverage.sh` descopes it and the feature's
ids report `UNSCOPED`. State in the same breath that this is an instruction and not an enforcement
(rule 16) — what is enforced is the consequence at the gate.

Do not add the same sentence to the concept-to-code Step 2 dispatch brief. One home, on the producer
side (ADR-0154 §D6, §A10).

Budget: staging/plugin/agents/architect.md (~6 lines)

### Task 4 — The corpus denominator guard for the back-reference derivation (R-06)

**Agent:** tester. **File:** `staging/plugin/scripts/tests/spec-coverage.test.sh` only.

Extend the existing `RS_LIVE` corpus loop **additively** to capture each pair's stderr alongside the
stdout it already reads, and record whether that run reported `SCOPE-NO-BACKREF`. No existing
assertion's inputs or predicate change; say so in one sentence at the edit site, because an in-place
edit inside a live assertion block is invisible to every gate this repo has.

`RY10` (R-06) — the number of resolved (SPEC, plan) pairs whose run does **not** report
`SCOPE-NO-BACKREF` and whose scope is non-empty is `>= 15`. Measured 2026-08-18: 16 pairs resolve,
and across the plan corpus 52 of 52 plans naming a harness have at least one that names back.

Declare **at the site**, not only here: this is a vacuity guard, not the evidence. A floor absorbs
its own plant (rule 10, ADR-0124) — `>= 15` against 16 still passes when one pair is removed. Task
5's regenerated per-row baseline is where a plant bites. `RY10` is **green on arrival** and stays
green after Task 2; the plant in Task 7 (collapse half 2 for every file) is what pins it.

Budget: staging/plugin/scripts/tests/spec-coverage.test.sh (~55 lines)

### Task 5 — Regenerate the frozen baseline and account for the delta row by row (R-07)

**Agent:** tester. **File:** `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv` only.

The `RS7`/`RS8` derivation in the harness **is** the regeneration procedure — do not hand-edit a
row. Run it against the current tree with Task 2 in place, diff the result against the committed
rows, and write the new rows.

State of the file before this task, re-derived 2026-08-18 (rule 13 — the header's own
`15 pairs / 117 ids` sentence is a dated snapshot of 2026-08-14, not today): **16 pairs, 130 rows,
106 `COVERED`, 24 `UNSCOPED`**, and the harness green.

Rules for the delta:

- Expected: **zero** verdict changes (ADR-0154 M4). Any change must be accounted for, row by row, in
  the header block.
- A `COVERED` → `UNSCOPED` flip whose dropped file is a **precedent citation** is expected and is
  recorded with class `testable` and the reason *"the only in-population mention sat in a file the
  plan names but which does not name the feature back (ADR-0154)"*.
- A `COVERED` → `UNSCOPED` flip whose dropped file genuinely belongs to that feature **halts the
  feature**. It means half 2's key set is too narrow; re-open ADR-0154 §D1. Never re-freeze the row.
- Any flip in the other direction (`UNSCOPED` → `COVERED`) also halts: this feature can only remove
  files from scope.

Add a dated `2026-08-18` block to the file's header stating what was regenerated, under which ADR,
the row-count delta, and the per-row accounting. **Do not rewrite the 2026-08-14 measurement
sentence** — a historical record is corrected forward (rule 14, ADR-0154 §D5).

Budget: staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv (~45 lines)

### Task 6 — The record (R-10, R-11, R-12)

**Agent:** coder. **Files:** `docs/chain-decisions.md`, `CLAUDE.md`, `PROJECT.md`.

- A `docs/chain-decisions.md` block, appended after the ADR-0153 one, in the file's established
  narrative shape: what was measured, what it changed, the two designs refused on measurement and
  the numbers that refused them, and the two residual classes ADR-0154 §D7 leaves open — including
  the 8-of-12 self-measurement, which is the honest headline.
- One `CLAUDE.md` chain-decision index line for ADR-0154, in the existing one-line form. **Do not**
  add a twentieth rule: this feature adds no new invariant, it narrows an existing mechanism.
- A `PROJECT.md` phase row. This feature is not yet on the roadmap; it belongs as **Phase 15 — the
  scope that was a list of names becomes a mutual one**, after Phase 14, with the three-checkbox
  shape the recent phases use and a closing italic paragraph naming what stayed an instruction
  (the architect contract line) and what the gate enforces.

R-11 and R-12 are satisfied by ADR-0154 as already written; this task's obligation for them is that
the chain-decisions block does not contradict it.

Budget: docs/chain-decisions.md (~45 lines), CLAUDE.md (~1 line), PROJECT.md (~16 lines).

### Task 7 — A plant for every new assertion, and the registry run (R-09)

**Agent:** tester. **File:** `staging/plugin/scripts/tests/spec-coverage.test.sh` only.

One `# plant:` declaration at column 1 beside each new assertion, four fields, no ` | ` inside a
field, target paths staging-relative (`plugin/…`) except the docs exception (`../docs/…`). Each
needle must match its target **exactly once** — validate before declaring, a needle that matches
zero or twice is a defect in the plant.

| Assertion | Plant target | Shape of the mutation |
|---|---|---|
| `RY1`, `RY9` | `plugin/skills/concept-to-code/scripts/spec-coverage.sh` | neutralise the half-2 test so every named file scopes in |
| `RY2` | same | drop the plan basename from the key set |
| `RY3`, `RY4` | same | drop the ADR ids from the key set |
| `RY5` | same | replace the anchored back-reference match with an unanchored one |
| `RY6` | same | force the half-1 count branch to the `SCOPE-EMPTY` side |
| `RY7` | same | force it to the `SCOPE-NO-BACKREF` side |
| `RY8` | same | neutralise the `.md` exclusion |
| `RY10` | same | collapse half 2 for every file (`if false`) — a total collapse is what bites a floor |
| `RY11` | `../docs/architecture/ADR-0154-spec-coverage-scope-back-reference.md` | remove one of the two refused-design measurements |
| `RY12` | `../docs/chain-decisions.md` | rename the ADR-0154 heading |
| `RI7` | `plugin/agents/architect.md` | delete the new clause |

Then run the registry: `bash staging/plugin/scripts/tests/plant-check.sh`. Every new plant must
report `FIRED`. A `NOFIRE`, `BADPLANT` or `VACUOUS` convicts the assertion or the plant, not the
run — fix it, do not delete it. If an assertion cannot be planted honestly, record why beside it
rather than inventing a plant that fires for the wrong reason.

Budget: staging/plugin/scripts/tests/spec-coverage.test.sh (~20 lines)

---

## Staleness — what asserts the old behaviour, and what does not

Grepped 2026-08-18 across the repository for the changed contract.

- `SCOPE-EMPTY` is asserted in exactly one place: `staging/plugin/scripts/tests/spec-coverage.test.sh`
  (`RS6`, and a fixture comment in `RS10`). Its meaning and wording are unchanged, and `RY7` re-pins
  it against the new sibling state. **No edit required.**
- The stderr summary line is read by one assertion (`RD5`), by substring, on
  `0 test file(s) discovered`. Appending a trailing clause is safe. **No edit required.**
- `SCOPE-EMPTY` also appears in `docs/architecture/ADR-0138-312-…`, `docs/chain-decisions.md` and the
  2026-08-14 plan. Those are historical records: they described the state correctly on their date and
  are **not** edited (rule 14). ADR-0154 is the forward correction.
- Every other consumer of `spec-coverage.sh` — the concept-to-code Step 5 gate block, `commit`,
  `project-conductor`, `interface-check.sh`, `external-dependency-check.sh` — branches on the exit
  code, and no exit code changes. **No edit required.**
- The frozen baseline is the one artifact that does assert the old behaviour row by row, and Task 5
  regenerates it deliberately.

**Run the full suite, not just this harness**, after Task 2 and again after Task 5: a scope change in
this script moves verdicts that other harnesses read through the corpus derivation.

## Risks and HITL gates

- **The SPEC edit is a precondition, not a nicety.** Without it the Step 5 → Step 6 gate exits 3 on
  three `STALE-WAIVER` lines. Operator action at Gate 2. See "Read this first".
- **A flip in Task 5 halts the feature.** That is the designed safety valve for M4's zero, and the
  correct response is to re-open ADR-0154 §D1, never to re-freeze the row.
- **`RY10` and `RY11` are green on arrival.** Declared here in advance so a green checkpoint is not
  mistaken for evidence; their plants are what pin them.
- **`staging/plugin/agents/architect.md` changes**, so `staging/sync-to-claude.sh --apply` must run
  before the deployed agent carries the clause. Until then the dry run reports drift. Operator
  action at Step 7, not a task here.
- **The residual exposures are accepted, not fixed** (ADR-0154 §D7): the same-file namespace
  collision, measured at 8 of 12 on this feature's own SPEC, and precedent ADR citations as
  back-reference keys. Recommend filing the first as its own issue with M3 as its opening
  measurement.
- **HITL gates:** commit and push at the end of Step 7 as usual; the `SPEC.md` edit at Gate 2; no
  deletion, no schema change, no migration, nothing outside this repository.

## Requirement coverage map

| ID | Task(s) | Evidence |
|---|---|---|
| R-01 | 1, 2 | `RY1`, `RY2`, `RY9` |
| R-02 | 1, 2 | `RY2`, `RY3`, `RY4`, `RY5` |
| R-03 | 1, 2 | `RY1` |
| R-04 | 1, 2 | `RY8` + the 145 pre-existing assertions staying green |
| R-05 | 1, 2 | `RY6`, `RY7` |
| R-06 | 4 | `RY10`, declared a vacuity guard at its site |
| R-07 | 5 | the regenerated baseline, compared row by row by `RS7`/`RS8a`/`RS8b` |
| R-08 | 1, 3 | `RI7` |
| R-09 | 7 | the plant table, and `plant-check.sh` reporting `FIRED` for each |
| R-10 | 1, 6 | `RY12` |
| R-11 | 1, 6 | `RY11` |
| R-12 | 1, 6 | `RY11` |

CODER-MODEL CANDIDATE: sonnet
