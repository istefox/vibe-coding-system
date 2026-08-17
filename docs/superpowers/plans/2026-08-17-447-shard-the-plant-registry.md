# Implementation plan — shard the plant registry across jobs, and assert the union exactly once

- **Issue:** #447.
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md` (R-01 … R-13)
- **ADR:** `docs/architecture/ADR-0151-447-shard-the-plant-registry.md`
- **Stack:** Bash 3.2 (macOS-portable — no `[[ ]]`, no arrays, no `${var^^}`), POSIX `awk`/`sed`,
  the existing `staging/plugin/scripts/tests/*.test.sh` harnesses run by `.claude/test-cmd`, plants
  per ADR-0108. GitHub Actions yaml. No new dependency, no new harness file, no schema bump.

## Read this first — three facts that decide half the tasks

1. **`plant-check.sh` is both the file under test and the file being changed.** The recursion is
   answered by the two devices ADR-0143 §D6 established and this ADR carries forward: a byte-identical
   whole-corpus verdict diff outside CI (Task 9), and a sharded arm on the fixture inside CI (Tasks 1,
   2, 6). Neither is sufficient alone; do not drop one because the other is green.
2. **Everything under `staging/plugin/scripts/tests/` is TESTER-owned.** `test-write-scope.sh` denies
   the coder any write under a path component named `tests/`, and `plant-check.sh` lives there. Tasks
   1–6 are tester tasks. Only Tasks 7 and 8 are coder work.
3. **R-05 is a byte-for-byte claim and it constrains the refactor, not just the feature.** Extracting
   `assert_pc0`/`assert_pc3`/`assert_pc5b`/`assert_z1` and `collect_decls` must not change one
   character of emitted text. `PS1` compares two post-change runs and cannot see a message that moved;
   the check that can is Task 9's diff against `git show HEAD:…`. Do not skip it.

## Files this plan touches

| Path | Action | Owner |
|---|---|---|
| `staging/plugin/scripts/tests/plant-registry-parallel.test.sh` | modify — 13 new `PS*` assertions + 12 plants, `PP3`'s needle | tester |
| `staging/plugin/scripts/tests/plant-check.sh` | modify — slice knobs, artifact, `--union`, `--require-legs` | tester |
| `.github/workflows/docs-ci.yml` | modify — `plant-shard` matrix job, `shell-tests` union wiring | coder |
| `docs/chain-decisions.md` | modify — one narrative block | coder |
| `CLAUDE.md` | modify — one line in the Chain decision index | coder |
| `PROJECT.md` | modify — one Wave 2 checkbox row | coder |
| `docs/architecture/ADR-0151-447-shard-the-plant-registry.md` | **already written** by the architect | — |

**Not touched, deliberately.**

- `staging/plugin/scripts/set-branch-protection.sh` and branch protection itself — the topology
  creates no new required context, so #336 stays where it is (SPEC *Out*).
- `.github/workflows/ci.yml` — it globs the harness directory but does not run the registry.
- The plant declaration grammar, the fired predicate, `build_sandbox` — SPEC *Out*. In particular
  **do not widen the plant target grammar to reach `.github/`**; `PS11` carries a declared no-plant
  reason instead, and that is the decision, not a gap.
- No new `*.test.sh` file, which is why the assertions extend `plant-registry-parallel.test.sh`.
  `docs-ci.yml` names harnesses one by one and a new file would need a manual append there.
- No PAIRS entry: `staging/plugin/scripts/tests/` is not a PAIRS-covered subtree except for four
  named legacy files, and no file is created. **Verify, do not assume** (Task 9).

## Ownership and batching, with the expected reds declared in advance (ADR-0101)

An assertion must not sit in the same batch as the task that greens it, so intermediate checkpoints
are RED **by design**. Every red below is declared here; anything else halts.

| Batch | Tasks | Agent | Expected checkpoint state |
|---|---|---|---|
| A | 1, 2 | tester | RED — `PS0`–`PS11` all fail; none of the mechanisms exist yet |
| B | 3 | tester | `PS1`, `PS3`, `PS3b`, `PS4` green; the rest still RED |
| C | 4, 5 | tester | `PS0`, `PS2`, `PS5`–`PS10` green; only `PS11` RED; full suite otherwise green |
| D | 6 | tester | 12 plants declared, each seen RED once; `plant-check.sh` green |
| E | 7 | coder | `PS11` green; the first sharded CI run happens here |
| F | 8 | coder | docs land; full suite + registry green |
| G | 9 | tester | the two measurements recorded; no code change expected |

## Assertion ids

`PS0`–`PS11` (with `PS3b`) in `plant-registry-parallel.test.sh`. The file already uses `PP0`–`PP10`,
`PP6b` and `PPZ`; `PS` is unused **anywhere in the corpus** (checked 2026-08-17) — re-check before
writing, because an id collision makes two assertions indistinguishable in the harness output.

`PC6` and `PC7` are new assertions **inside** `plant-check.sh --union`. They carry no plant of their
own: the registry's own `PC*` assertions have never been self-planted, they are pinned by the `PS*`
assertions in the harness, and that is the existing arrangement rather than a new exemption.

## The Step 5 → 6 coverage gate is already 9-of-13 green, and none of it is this feature's work

Run at design time, 2026-08-17, before a line was written:

```text
spec-coverage.sh --spec SPEC.md --plan <this file> --tests-root staging/plugin/scripts/tests
  -> 13 declared, 9 COVERED, 0 UNCOVERED, 4 UNSCOPED (R-01, R-08, R-11, R-12), 4 files in scope
```

**Nine ids report COVERED against an unimplemented feature.** `R-02` is satisfied by `PP10`'s own
`(R-02)` label, left from issue #305's requirement namespace; the other seven are satisfied by
`R-NN` mentions inside the harnesses this plan names in prose (the staleness list at the end), which
the scope filter therefore admits. Requirement ids restart per feature, so a stranger's file
satisfies them — CLAUDE.md rule 18 and ADR-0138's stated residual, live in this feature rather than
hypothetically.

Two consequences for whoever implements this:

- **Do not read a green gate as coverage.** It cannot tell this feature's `R-05` from #350's. The
  evidence that a requirement is met is its `PS*` assertion going RED against a plant, never the
  gate's verdict.
- **Label each new assertion block with the ids it answers**, in its comment header, the way this
  corpus already does (`# PS3/PS3b (R-06) — …`). That is what makes the four currently UNSCOPED ids
  genuinely covered, and the only thing that makes the other nine honest.

---

### Task 1 — The shard-mode, default-equivalence and refusal assertions, written RED (R-02, R-05, R-06, R-08)

Tester-owned. Extend `staging/plugin/scripts/tests/plant-registry-parallel.test.sh`, re-using the
existing `FIX` fixture (13 plants, 5 harnesses) and the `$TMP` idiom already established there. Do
not build a third fixture.

- `PS1` (R-05) — run the fixture registry twice: once with **no** shard variables in the environment,
  once with `PLANT_SHARDS=1 PLANT_SHARD=1`. `diff -q` the two stdout captures: identical, byte for
  byte. Assert the diff, and separately assert that both captures contain `PASS: PC0` — otherwise two
  runs that both crashed satisfy it.
- `PS3` (R-06) — a `PLANT_SHARDS=4 PLANT_SHARD=2` run prints exactly one line matching
  `PC-DEFERRED shard 2/4` and that line names all four of `PC0`, `PC3`, `PC5b`, `Z1`. Assert the
  token AND the four names; a token that stopped naming what it defers is a token that stopped being
  a report.
- `PS3b` (R-02, R-06) — the negative twin and the positive twin together (rule 8): in the shard run
  none of `PASS: PC0`, `PASS: PC3`, `PASS: PC5b`, `PASS: Z1` (nor their `FAIL:` forms) appears; in the
  `PLANT_SHARDS=1` run all four do, and `PC-DEFERRED` does not. Without the second half this is
  satisfied by a registry that prints nothing.
- `PS4` (R-08) — five malformed slice specifications, each asserted on **exit code AND stdout
  separately**, never a combined condition that can pass for the wrong reason:
  `PLANT_SHARDS=0`, `PLANT_SHARDS=abc`, `PLANT_SHARD=0`, `PLANT_SHARD=5 PLANT_SHARDS=4`,
  `PLANT_SHARD=abc`. Each: exit **2**, a `PC-REFUSED` line on stderr, and **no** line matching
  `plant .* fired` — the refusal must select neither the whole population nor none of it silently.

Every assertion states its expected exit code and its expected token separately. Use
`PLANT_JOBS=1` on the shard runs: the fixture is tiny and a second variable in flight makes a
failure harder to attribute.

Budget: `staging/plugin/scripts/tests/plant-registry-parallel.test.sh` (~130 lines)

**Expected RED on arrival.** All five fail against today's `plant-check.sh`, which has no shard mode.
That is the evidence.

---

### Task 2 — The artifact, union and leg-gate assertions, still RED (R-01, R-02, R-07, R-09, R-10)

Tester-owned, same file. This is the sharded arm R-10 asks for. Build the four shard artifacts
**once** and derive every negative case by editing copies — the union builds no sandboxes, so each
extra case costs milliseconds.

- `PS0` — **the denominator for everything below** (rule 7). Four shard runs
  (`PLANT_SHARDS=4 PLANT_SHARD=k PLANT_ARTIFACT=$ART/plant-shard-k.tsv`) plus the **existing**
  one-worker run, which is re-used as the sequential arm by adding `PLANT_ARTIFACT` to it rather than
  paying for a sixth registry invocation. Assert: four artifact files exist, each carries exactly one
  `M shard k` record, the four `V` record sets total **13**, and the sequential artifact carries 13.
  A fixture that stopped producing artifacts would make every assertion below compare nothing to
  nothing.
- `PS2` (R-05, and R-12's in-CI counterpart) — concatenate the four shards' `V` records, sort by
  declaration index, and compare **byte for byte** against the sequential artifact's `V` records.
  This is the equivalence proof reduced to a `diff`.
- `PS5` (R-09, R-10) — delete **one** `V` record from one artifact, leaving all four files present.
  `--union` must exit **1** and name the missing declaration index. This is the case a `needs`-only
  design cannot see.
- `PS6` (R-02, R-10) — two states, asserted separately because they are two readings:
  (i) remove one artifact file entirely: exit **3** with a `PC-UNION-NORUN` line naming the absent
  shard; (ii) replace one artifact with one carrying its `M` records and **zero** `V` records: exit
  **1** via the coverage check. Neither is exit 0, and the two do not collapse into each other.
- `PS7` (R-02) — over the unmodified four artifacts: `--union` exits 0, and its stdout carries
  **exactly one** each of `PC0`, `PC3`, `PC5b` and `Z1` (`grep -c`, compared to 1 — never
  `grep -q`, which cannot see a duplicate). Assert also that no shard's stdout carries any of the
  four, so "exactly once" holds across the whole topology and not just inside the union.
- `PS8` (R-07) — `--require-legs success` exits 0; `failure`, `cancelled`, `skipped`, the empty
  string and `Success` (wrong case) each exit 1 and print the observed state. Five rejects and one
  accept, because a gate that rejects everything passes a one-sided test.
- `PS9` (R-01) — the union prints one `PC-IMBALANCE` line carrying a slice size per shard and a
  max/min ratio, **and** `PC7` goes RED when an artifact's `M slice` disagrees with the number of `V`
  records it actually carries. Assert the printed line's presence on the clean run and the RED on the
  doctored one.
- `PS10` (R-09, R-10) — mis-assignment: copy a `V` record from shard 3's artifact into shard 2's,
  keeping its index. `--union` exits 1 and names the **duplicated** index. Distinct from `PS5`'s
  missing index: two states, two messages, two repairs.
- `PS11` (R-03, R-07) — the `docs-ci.yml` topology, read as text from
  `$STAGING/../.github/workflows/docs-ci.yml`: a `plant-shard:` job with `fail-fast: false` and a
  four-value matrix; `shell-tests` still named `shell-tests`, carrying `needs: [plant-shard]` and
  `if: always()`; the `for t in ` harness-loop line still present and unchanged; a `zsh` install step
  inside the **shard** job; and the union job invoking both `--require-legs` and `--union`.
  **This assertion carries no plant, and the reason goes on the line above it**, in the form
  `pairs-completeness.test.sh`'s `CI1` already uses: `.github/` is copied into the sandbox for tests
  to read but is not a legal plant target, and widening the target grammar is out of scope for this
  change (ADR-0151 §D11). Its live evidence is that it is RED until Task 7.

Budget: `staging/plugin/scripts/tests/plant-registry-parallel.test.sh` (~260 lines)

**Expected RED on arrival**, all of them.

---

### Task 3 — The slice knobs: one code path, and a refusal where `PLANT_JOBS` resolves downwards (R-02, R-05, R-06, R-08)

Tester-owned, `staging/plugin/scripts/tests/plant-check.sh`. Bash 3.2 only.

- Resolve beside the existing `JOBS` block: `SHARDS="${PLANT_SHARDS:-1}"`, `SHARD="${PLANT_SHARD:-1}"`.
- Validate with `case` globs, then range: `case "$SHARDS" in ''|*[!0-9]*) refuse ;; esac`, same for
  `SHARD`, then `[ "$SHARDS" -ge 1 ]` and `[ "$SHARD" -ge 1 ] && [ "$SHARD" -le "$SHARDS" ]`. One
  `_slice_refuse()` helper: a `PC-REFUSED …` line on **stderr** and `exit 2`.
  **Write the comment that says why this direction is the opposite of `PLANT_JOBS`'s** — a
  performance knob resolves downwards, a correctness knob refuses, and without the note the next
  reader "fixes" the asymmetry (ADR-0151 §D4).
- One stride, two call sites, no shard-mode branch around either:
  dispatch becomes `seq "$SHARD" "$SHARDS" "$DECL_N" | xargs -P "$JOBS" -I{} bash "$SELF" --worker {} "$WORK"`,
  aggregation becomes `for _i in $(seq "$SHARD" "$SHARDS" "$DECL_N"); do`. At the defaults this is
  `seq 1 1 N`, which is `seq 1 N`.
- `SHARDED=0; [ "$SHARDS" -gt 1 ] && SHARDED=1` — **one** predicate variable, referenced at all four
  deferral sites. Four inline copies of the same test is four things to keep in step.
- Extract `assert_pc0`, `assert_pc3`, `assert_pc5b`, `assert_z1` as functions taking their inputs as
  arguments (`assert_z1` takes the floor too, since the union's floor is its own). The orchestrator
  calls them only when `SHARDED` is 0; the union calls them unconditionally. **The emitted strings
  must not change by one character** — R-05, and Task 9's diff is what proves it.
- The deferral token, printed once when `SHARDED` is 1:
  `PC-DEFERRED shard <k>/<S> — PC0 PC3 PC5b Z1 are population assertions and are evaluated once by
  the union (plant-check.sh --union); this shard's exit code covers only its own <n> declaration(s)`.

Header comment: add the shard paragraph to the `COST AND CONCURRENCY` block, stating that a shard
that discovers nothing exits 0 and that the union's coverage check is what makes that safe.

Budget: `staging/plugin/scripts/tests/plant-check.sh` (~90 lines)

Greens `PS1`, `PS3`, `PS3b`, `PS4`.

---

### Task 4 — One collector, and the verdict stream on disk (R-02, R-09)

Tester-owned, same file.

- Extract the declaration collector into `collect_decls <outfile>` — the loop over `"$TESTS"/*.test.sh`
  greping `^# plant:` — and call it from the orchestrator. It gets a second consumer in Task 5, and
  two collectors giving different answers would be *the* defect this feature exists to prevent
  (ADR-0086, rule 6). Do not inline a second copy in the union.
- `write_artifact <path>`, called once at the end of the orchestrator when `PLANT_ARTIFACT` is set,
  **before** the `[ "$FAIL" -eq 0 ] || exit 1` line so a red shard still produces its evidence.
  Tab-separated, one record per line, in this fixed order — `M`, then `B` sorted by harness, then `V`
  in declaration-index order:

  | record | fields |
  |---|---|
  | `M` | `M`, key, value — keys `shard`, `shards`, `decls`, `slice`, `asserts` |
  | `B` | `B`, harness, state (`ok`, or the miss string the baseline already writes) |
  | `V` | `V`, declaration index, harness, assertion id, token |

  `asserts` is `PASS + FAIL` for this shard, which is what makes the union's `Z1` a sum rather than a
  guess. The token for a declaration whose worker left no verdict is `BADPLANT` — the state the
  aggregation loop already assigns it, so **no new token is introduced**; its assertion id is `?`,
  written by the same `${aid:-?}` rule the worker's message already uses.
- The worker writes a third file beside `.kind`/`.msg` carrying the canonical `V` payload, because it
  is the only place where the harness name, the assertion id and the token are all in scope. Do not
  re-parse the declaration in the orchestrator — that would be a third parser.
- With `PLANT_ARTIFACT` unset nothing is written and nothing changes (R-05). Shard mode without an
  artifact path is **allowed**, not refused: it is the legitimate local "run just my slice", and in CI
  the union's exit 3 is what catches a shard whose artifact never arrived. Say so at the site
  (rule 17 — the producer and the consumer are checked to meet, by the union's exit 3).
- **Update `PP3`'s declaration**: its needle names the aggregation loop, which Task 3 changed. New
  needle `for _i in $(seq "$SHARD" "$SHARDS" "$DECL_N"); do`; the replacement stays
  `for _i in $(seq "$DECL_N" -1 1); do` — it must **not** gain a ` | sort -rn`, because ` | ` inside a
  field makes the declaration five fields and `BADPLANT` (#305, ADR-0149).

Budget: `staging/plugin/scripts/tests/plant-check.sh` (~110 lines)

---

### Task 5 — `--union` and `--require-legs` (R-01, R-02, R-07, R-09)

Tester-owned, same file. Two new modes, both re-entry points on the same script, both checkers whose
callers branch on the exit code (rule 5).

**`--require-legs <result>`** — exit 0 on exactly `success`; on anything else print the observed state
and exit 1. Compare against the ONE allowed value; never enumerate `failure|cancelled|skipped`, which
is blind to whatever state GitHub adds next (rule 8). Six lines, and it exists as code rather than as
a yaml `if:` because yaml cannot be planted (ADR-0151 §D7).

**`--union <dir>`** — exit **0** clean, **1** a defect found, **2** bad invocation (no directory, or
not a directory), **3** could not evaluate. Order of operations:

1. Read every regular file under `<dir>` (one `find … -type f`). **Zero files, or a file that carries
   no `M shard` record, is exit 3** via one `_union_norun()` helper — "did not run" never reads as a
   clean union (rule 4).
2. Establish the population: all artifacts must agree on `M shards`. Disagreement, or fewer present
   than that number, is exit 3 naming which shard is absent. **The expected count comes from the
   artifacts**, so the yaml carries `4` in exactly one place.
3. Re-derive the declarations with `collect_decls` and evaluate `assert_pc0` and `assert_pc3` on that
   re-derivation.
4. `PC6` — the coverage check, and the reason this design is artifacts rather than `needs`. Every
   declaration index must appear **exactly once** across the artifacts, with a matching harness and
   assertion id, and each artifact's own `M decls` must equal the re-derived count. Accumulate three
   independent lists — `_cov_missing`, `_cov_dup`, `_cov_mismatch` — and report all three in the
   failure message. They are three defects with three repairs; do not collapse them into a boolean.
5. `PC5b` via `assert_pc5b` over the union of the `B` records: every declaring harness present, none
   reporting a miss. Guard the denominator here too — zero `B` records is not a clean baseline.
6. `PC7` — the imbalance. Print one `PC-IMBALANCE` line carrying each shard's slice size and the
   max/min ratio, and assert that the `M slice` values sum to the re-derived declaration count.
   The ratio is **reported, never gated**: a threshold would be an arbitrary number that goes red on a
   legitimately skewed corpus (R-01).
7. `assert_z1` over the summed `M asserts` plus the union's own, with the union's own floor. State at
   the site that it is a vacuity guard and carries no plant, because a floor absorbs its own plant
   (rule 10) — the same sentence `PPZ` already carries.

Budget: `staging/plugin/scripts/tests/plant-check.sh` (~200 lines)

Greens `PS0`, `PS2`, `PS5`–`PS10`.

---

### Task 6 — Declare the twelve plants and see each one RED (R-11)

Tester-owned, `plant-registry-parallel.test.sh`, in the existing `--- plants ---` block at column 1.
Twelve declarations; `PS11` gets a reason line instead, per Task 2.

```text
# plant: PS0  | plugin/scripts/tests/plant-check.sh | write_artifact "$PLANT_ARTIFACT" | :
# plant: PS1  | plugin/scripts/tests/plant-check.sh | SHARDS="${PLANT_SHARDS:-1}" | SHARDS="${PLANT_SHARDS:-2}"
# plant: PS2  | plugin/scripts/tests/plant-check.sh | <the dispatch stride, see the note> | <shard forced to 1>
# plant: PS3  | plugin/scripts/tests/plant-check.sh | printf 'PC-DEFERRED shard %s/%s | printf 'PC-QUIET shard %s/%s
# plant: PS3b | plugin/scripts/tests/plant-check.sh | [ "$SHARDS" -gt 1 ] && SHARDED=1 | [ "$SHARDS" -gt 99 ] && SHARDED=1
# plant: PS4  | plugin/scripts/tests/plant-check.sh | <the body of _slice_refuse> | :
# plant: PS5  | plugin/scripts/tests/plant-check.sh | _cov_missing="$_cov_missing $_i" | :
# plant: PS6  | plugin/scripts/tests/plant-check.sh | <the _union_norun body, exit 3> | <the same body, exit 0>
# plant: PS7  | plugin/scripts/tests/plant-check.sh | assert_pc3 "$U_FILES_N" | :
# plant: PS8  | plugin/scripts/tests/plant-check.sh | [ "${2:-}" = "success" ] | [ "${2:-}" != "nonesuch" ]
# plant: PS9  | plugin/scripts/tests/plant-check.sh | [ "$_sum" -eq "$U_DECL_N" ] | true
# plant: PS10 | plugin/scripts/tests/plant-check.sh | _cov_dup="$_cov_dup $_i" | :
```

**`PS2`'s needle cannot contain the dispatch line's pipe.** A ` | ` inside a field makes the
declaration five fields and `BADPLANT`, and the bare stride `seq "$SHARD" "$SHARDS" "$DECL_N"` occurs
twice (dispatch and aggregation), which is `needle matched 2 times`. Resolve it with a longer,
site-specific needle that stops before the pipe, or by naming the stride once in a variable. Decide
it with the file in front of you; the constraint is exactly-one-match and the registry says which way
you got it wrong.

Then run `bash staging/plugin/scripts/tests/plant-check.sh` and confirm **each of the twelve fires**,
attributed to the named id and to no sibling. A plant that reports `NOFIRE` names an assertion that
pins nothing — repair the assertion, never the plant. A plant that reports `BADPLANT` is a rotted
needle — repair the declaration.

**Re-measure the file's own cost here** and record it in the batch report: it was 9.47s with 10
plants on 2026-08-17. The ADR estimates ~13.5s with 22 plants. If it lands materially above ~15s, cut
the number of fixture *registry invocations* (the negative cases are file edits and cost nothing);
never cut plants.

Budget: `staging/plugin/scripts/tests/plant-registry-parallel.test.sh` (~30 lines)

---

### Task 7 — The workflow: a four-leg matrix and `shell-tests` as the union (R-03, R-07)

Coder-owned, `.github/workflows/docs-ci.yml`. Actions pinned to commit SHAs, as the file's own header
requires. The pins below were resolved from the GitHub API on 2026-08-17 — **matched majors,
deliberately**: `download-artifact` v8 changed decompression behaviour, and introducing that on the
same day as a new artifact round-trip is two unknowns at once.

New job, before `shell-tests`:

```yaml
  plant-shard:
    name: plant-shard
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false          # one broken plant must not cancel the other three and hide the rest
      matrix:
        shard: [1, 2, 3, 4]     # THE shard count lives here and nowhere else
    steps:
      - name: Checkout
        uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd # v5
      - name: Install zsh (a dependency of the harnesses this job re-runs under mutation)
        run: |
          set -e
          if ! command -v zsh >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y zsh
          fi
          zsh --version
      - name: Run the plant registry (shard ${{ matrix.shard }})
        env:
          PLANT_SHARD: ${{ matrix.shard }}
          PLANT_SHARDS: ${{ strategy.job-total }}
          PLANT_ARTIFACT: ${{ runner.temp }}/plant-shard-${{ matrix.shard }}.tsv
        run: |
          echo "runner cores: $(nproc)"
          bash staging/plugin/scripts/tests/plant-check.sh
      - name: Upload this shard's verdict stream
        if: always()            # a RED shard's evidence is the evidence the union needs most
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: plant-shard-${{ matrix.shard }}
          path: ${{ runner.temp }}/plant-shard-${{ matrix.shard }}.tsv
```

**The `zsh` step is not copied for symmetry.** The registry re-runs `fence-contract-coverage.test.sh`
under mutation; with `zsh` absent its `WSA`/`WSB` fail by design, the baseline for that harness is
red, and every plant declared in it becomes `VACUOUS`. It is a build dependency of this job as much as
of the harness loop, and nothing but this comment says so.

`shell-tests` gains `needs: [plant-shard]` and `if: always()` — **without `always()` a failed shard
skips the job, and a required context that never reports leaves the pull request pending forever.**
Its `Run the plant registry` step is replaced by three steps placed **after** the harness loop, so a
shard failure does not cost the loop's independent evidence (ADR-0101):

```yaml
      - name: Download every shard's verdict stream
        continue-on-error: true   # a total absence must reach the union, which reports exit 3
        uses: actions/download-artifact@37930b1c2abaa49bbe596cd826c3c89aef350131 # v7.0.0
        with:
          pattern: plant-shard-*
          merge-multiple: true
          path: ${{ runner.temp }}/plant-shards
      - name: Require every plant-shard leg to have succeeded
        env:
          SHARD_RESULT: ${{ needs.plant-shard.result }}
        run: bash staging/plugin/scripts/tests/plant-check.sh --require-legs "$SHARD_RESULT"
      - name: Evaluate the union
        run: bash staging/plugin/scripts/tests/plant-check.sh --union "${{ runner.temp }}/plant-shards"
```

**Do not write `if: failure()` or `if: success()` on a step here.** Measured on probe run
`32023759765`: status functions in a step `if` read the previous steps of the **same job**, not
`needs` — a union written that way reported green with two of four dependencies failed. The leg
result reaches bash through `env:` and the decision is made in tested code.

Rewrite the `COST:` comment block above the old registry step to describe the new topology, keeping
the line that tells the reader to **re-derive the pair from a run** rather than trust the comment. It
has gone stale twice now.

Budget: `.github/workflows/docs-ci.yml` (~90 lines)

Greens `PS11`. This is where the first sharded CI run happens; expect to iterate on it.

---

### Task 8 — The record: narrative, index line, roadmap row, and the rule decision (R-13)

Coder-owned. Two edits, none of them code.

**NARROWED at Gate 3, 2026-08-17, by the orchestrator with the operator's approval.** Two of this
task's original four edits were **already made by the chain's own Step 3**, which is the canonical
producer for both files (ADR-0136): the narrative block is appended to `docs/chain-decisions.md` and
the index line to `CLAUDE.md`, and the operator reviewed the diff at Gate 3. Redoing them here would
overwrite a reviewed artifact with a second, differently-worded one. What remains for this task:

- `docs/chain-decisions.md` and `CLAUDE.md` — **VERIFY ONLY, do not write.** Confirm the block
  `## Decisions from the shard-the-plant-registry chain (ADR-0151)` sits after the ADR-0150 block and
  that exactly one matching `- **ADR-0151** —` line closes the *Chain decision index*. The two must
  stay the same size: one block appended, one index line appended. If either is missing, say so and
  stop rather than writing a second copy.
- `PROJECT.md` — add one `- [ ]` row in **Phase 10, Wave 2**, immediately after the #350 row
  (`plant-check.sh cost scales as (plants x target-file runtime)`), whose follow-on this is:
  `- [ ] the plant registry's ceiling is 2 cores and the only lever left is sharding across jobs  (issue #447)`
  **Then confirm it is ticked to `- [x]` with a completion note before the PR is opened.**
  `project-conductor` takes the first `- [ ]` line in the file; a row left open for work that just
  shipped is a feature slot a nightly run will spend rediscovering that nothing is wrong
  (PROJECT.md §10.1 records exactly this happening twice).
- **The rule decision, recorded either way:** no new numbered rule. This is rules 4 and 7 applied to
  a new topology, plus rule 5's checker/reporter split on the union's exit codes. State that in the
  narrative block so the next reader does not re-open it. The ADR's *Consequences* already says it.

**R-13 is satisfied by the ADR's §D9**, which records that a matrix leg cannot be a required context
together with the measurement that established it. Verify that section survived; do not restate the
measurement in the narrative block.

Budget: `docs/chain-decisions.md`, `CLAUDE.md`, `PROJECT.md` (~60 lines)

---

### Task 9 — The two measurements, and the verifications the harness cannot make (R-03, R-04, R-12)

Tester-owned. No code change is expected here; a finding is a finding, not a silent fix.

- **R-12 — the whole-corpus verdict diff, outside CI.** On the current corpus (399 plants):
  one `PLANT_SHARDS=1 PLANT_ARTIFACT=…` run, then four `PLANT_SHARDS=4 PLANT_SHARD=k` runs. The four
  `V` streams, ordered by declaration index, must equal the one **byte for byte**, and the `B`
  streams must agree. Record the line count and the wall clock of each arm in the batch report. This
  costs roughly half an hour; it is the device #350 established and it cannot be a test.
- **The restructure itself must change nothing** — the check R-05's assertion cannot make.
  `git show HEAD:staging/plugin/scripts/tests/plant-check.sh` into a scratch path, run it over the
  corpus, and diff its stdout against the new file's `PLANT_SHARDS=1` stdout. `assert_pc0` and
  friends were extracted in Task 3 and a moved character would be invisible to `PS1`.
- **R-04 — the before/after, and its limit stated rather than smoothed.** #350's device held the
  machine constant; sharding cannot, because separate machines are the point. Use the closest
  available: a **temporary** sequential job in the same `docs-ci.yml`, no `needs`, running
  `PLANT_SHARDS=1`, so both arms run in one workflow run, from one commit, on one image, started
  together. Everything is equal except the machine draw, which is precisely what is not controlled —
  so take **three runs and report the spread**, never one number against one number: the sequential
  step alone measured 20m07s, 23m32s and 25m51s. **Delete the temporary job before the PR merges**
  and say so in the report.
- **R-03 — the required set is unchanged.** Run `bash staging/plugin/scripts/required-checks-audit.sh`
  against the changed workflows and record the output: `plant-shard` must appear as an advisory
  `not-required:` line and **never** as `missing-producer`, and the required set must still resolve to
  the four contexts read from branch protection on 2026-08-17 (`markdownlint`, `links`, `ci`,
  `shell-tests`). Confirm `required-checks-audit.test.sh` section `R` (`R1`/`R2`/`R3`) is still green:
  it reads recorded 2026-08-01 responses against the **live** workflows, so a new job passes through
  it, but that is a prediction until it is run.
- **Confirm the PAIRS assumption** (`pairs-completeness.test.sh` green) and that `.claude/test-cmd`
  and `ci.yml`'s glob still pick up `plant-registry-parallel.test.sh`.

Budget: no source files — measurements and a report (~0 lines)

---

## Verification before Gate 5

- `.claude/test-cmd` green — **the whole suite, all 85 harnesses**, not just the two files this plan
  touches. A contract change breaks assertions in modules that share the contract, and ~25 harnesses
  read `docs-ci.yml`.
- `bash staging/plugin/scripts/tests/plant-check.sh` — green, every declared plant firing exactly
  once, `PC0`–`PC5b` and `Z1` present.
- `bash staging/plugin/scripts/tests/plant-check.sh --union <dir>` over the four real artifacts —
  exit 0, `PC6` and `PC7` green, the `PC-IMBALANCE` line recorded in the batch report.
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` and
  `bash staging/plugin/scripts/tests/required-checks-audit.test.sh` — green.

**An observable contract changed here, and the call-sites were greped at design time (2026-08-17).**
`plant-check.sh` gains two env knobs, two modes and an exit-code vocabulary; `docs-ci.yml` gains a
job and loses a step. What reads them:

- **`docs-ci.yml`'s `for t in …` harness-loop line** is read by ~25 harnesses —
  `spec-coverage`, `secret-dep-gate`, `weakening-wiring`, `recovery-preflight`, `macos-detect`,
  `interface-immutability`, `worktree-isolation-contract`, `precompact-occupancy`,
  `reward-hack-detectors`, `litter-discipline`, `canonical-mechanism`, `diff-budget-scope`,
  `sast-security-audit`, `agent-metrics`, `test-write-scope`, `external-dependency-gate`,
  `tracer-bullet-probe`, `untrusted-input`, `proportional-audit-depth`, `project-ci-checks`,
  `human-gate-coverage`, `accessibility-i18n`, `licence-provenance`, `triage-state-gitignore`, and
  `pairs-completeness`'s `CI0`/`CI1`/`CI2`. **Task 7 must not touch that line.** Two of them
  (`litter-discipline` `LG1`, `canonical-mechanism` `MF1`) additionally assert *adjacency* inside it.
- **`pairs-completeness.test.sh` `CI0`** requires `>= 40` names parsed from that line — unchanged.
- **`required-checks-audit.test.sh` section `R`** runs the real `.github/workflows`; see Task 9.
- **`plant-registry-parallel.test.sh` `PP3`** asserts declaration order and its needle names the
  aggregation loop Task 3 rewrites. Task 4 updates the declaration. **Updating it is not weakening
  it**: state the reason in the batch report so the weakening scan's finding is answered rather than
  ignored (ADR-0073).
- **`PROJECT.md`'s Phase 10.0 table** records that `shell-tests` is *not* a required check on `main`.
  That was true on 2026-08-04 and is false today (read from the branch-protection API on 2026-08-17).
  **Do not correct it in place** — a number inside a completed record is a correct snapshot of its
  day (rule 14, ADR-0034). The current state is recorded forward, in ADR-0151 §D8.

**Run the full suite, not just the changed files.**

TEST-CMD CANDIDATE: none
TEST-CMD MODE: brownfield

EXTERNAL DEPENDENCY: GitHub Actions artifact storage (`actions/upload-artifact`, `actions/download-artifact`) | cloud service | provisioned: true
