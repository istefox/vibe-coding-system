# Implementation plan — the chain bumps the baseline it enrols into

- **Issue:** #460 (PROJECT.md Phase 18)
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md` (R-01 … R-08)
- **ADR:** `docs/architecture/ADR-0166-460-spec-coverage-baseline-never-bumped.md`
- **Stack:** Bash 3.2 (macOS-portable — no `[[ ]]`, no arrays, no `mapfile`, no `${var^^}`, no
  process substitution) and POSIX `awk`/`sed`/`grep`, matching every file being changed. One new
  script, one new harness, one existing harness edited, one existing frozen baseline's header, one
  `SKILL.md` step, one PAIRS entry, one CI loop entry.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`

TEST-CMD MODE: brownfield

This feature has no external dependency: no third-party API, no consent flow, no cloud console, no
cloud resource. Everything it touches is a file in this repository.

---

## Read this first — the ADR is 0166, not 0165

`ADR-0165` is already allocated on branch `feat/470-chain-never-regenerates-xcode` (commit
`ae85b07`), together with a twentieth `CLAUDE.md` rule. Neither is on `main`. Do not renumber, and do
not add a twenty-first rule: this feature adds no new invariant.

`SPEC.md` line 50 forward-references "ADR-0165 §D8". That reference is correct and resolves when
#470 merges. Leave it.

## Read this second — the state of the corpus, measured before any work (rule 13)

Re-derived 2026-08-22 on `main` at `1fdd96f`, by running the harness's own derivation:

```text
16 (SPEC, plan) pairs        130 declared ids
baseline rows: 130           106 COVERED / 12 UNCOVERED / 12 UNSCOPED
                             106 three-column rows / 24 five-column drift rows
RS7 divergence: 0            RS8a orphans: 0        RS8b orphans: 0
spec-coverage.test.sh:       PASS=170 FAIL=0        43 plants declared
per-pair exit codes:         --list rc=0 on 16/16
                             --tests-root rc=1 on 9, rc=0 on 7, rc>=2 on NONE
```

**Zero rows may change in this feature.** Any row-count or verdict delta at the end of Task 8 halts
the feature and re-opens ADR-0166 §D3 — it means the extraction is not byte-identical to the inline
logic it replaced. The `--tests-root rc>=2 on NONE` line is what makes the new exit-3 refusal
(ADR-0166 §D4) free of row changes; re-derive it, do not trust this block.

The SPEC's R-08 parenthetical says "16 live pairs, 16 baseline rows". 16 is the pair count; the row
count is 130. Corrected forward in ADR-0166's M1 — **do not edit `SPEC.md`** (rule 14, and it is
outside both agents' write scope).

## Read this third — this feature's own gate is not evidence about this feature

`staging/plugin/scripts/tests/spec-coverage.test.sh` is this feature's harness and it is full of
requirement-id heredoc fixtures belonging to a dozen other features. Under ADR-0154's conjunction it
will name `ADR-0166` back (Task 3), so it scopes in and those fixture tokens report several of this
feature's own ids as `COVERED` before a line of it exists. That is ADR-0154 §D7 class 1 and this
feature does not fix it. **The evidence is each `NB` assertion going RED against its declared plant
(Task 8), not the gate's verdict.**

## Files this plan names, and the three it deliberately does not

**Named on purpose, and safe:**

- `staging/plugin/scripts/tests/spec-coverage.test.sh` — this feature's existing harness (above).
- `staging/plugin/scripts/tests/spec-coverage-baseline-bump.test.sh` — this feature's new harness.
  It must contain `ADR-0166` **and** this plan's basename in its header, or it descopes itself.
- `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv` — not a discovered test file (its
  basename matches no discovery pattern).
- `staging/plugin/scripts/tests/plant-check.sh` — **not discovered** either; verified 2026-08-18 in
  the ADR-0154 plan and unchanged since. Its own requirement-id tokens cannot reach this feature's
  gate.
- `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh`,
  `staging/plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh`,
  `staging/plugin/skills/concept-to-code/SKILL.md`, `staging/sync-to-claude.sh`,
  `.github/workflows/docs-ci.yml`, `docs/chain-decisions.md`, `docs/chain-decision-index.md`,
  `PROJECT.md` — none is a discovered test file.

**Not named anywhere in this plan or in any task below, on purpose.** Three harnesses are discovered,
carry requirement-id tokens of their own inside this feature's declared range, and cite
`ADR-0086`/`ADR-0101`/`ADR-0108`/`ADR-0124`, all of which this plan cites — so naming any of them by
basename would import foreign matches straight into this feature's gate. Measured 2026-08-22: five
such tokens in one, seven in another, one in the third. They are the fence-contract coverage harness,
the commit-transition-order harness, and the PAIRS completeness harness. **Refer to their assertions
(`F3`, `F4`, `check_complete`) if you must; never write their basenames here.**

## Files this plan touches

| File | Owner | What changes |
|---|---|---|
| `staging/plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh` | coder | **create** — `--pair`, `--rows`, `--bump` |
| `staging/plugin/skills/concept-to-code/SKILL.md` | coder | Step 7.0b: the bump fence, its three branches, the `--include` extension |
| `staging/sync-to-claude.sh` | coder | one PAIRS entry |
| `.github/workflows/docs-ci.yml` | coder | one name in the shell-tests loop |
| `staging/plugin/scripts/tests/spec-coverage-baseline-bump.test.sh` | **tester** | **create** — the `NB` section |
| `staging/plugin/scripts/tests/spec-coverage.test.sh` | **tester** | `RS0` anchor + the `RS7`–`RS10` block rewritten to call the script |
| `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv` | **tester** | header instruction rewritten forward, dated block appended, **zero rows changed** |
| `docs/chain-decisions.md`, `docs/chain-decision-index.md`, `PROJECT.md` | coder | the record |

Everything under `staging/plugin/scripts/tests/` is tester-owned — `test-write-scope.sh` denies the
coder any write there, and the `.tsv` baseline sits inside that directory, so its header edit is a
tester task. Files under `staging/` are mode 644: run them as `bash <path>`.

## Assertion ids and the harness contract

New assertions use the **`NB`** prefix. Verified free 2026-08-22 across all 96 harnesses
(`grep -rn '"NB[0-9]'` → no match). One new `RS0` goes into the existing `RS` section.

Every new block carries an id-mapping comment header — `# NB8/NB9 (R-01, R-03) — …` — the form the
corpus already uses. Both edited harness sections must name `ADR-0166` and this plan's basename
`2026-08-22-460-spec-coverage-baseline-never-bumped.md`, or ADR-0154's conjunction descopes them.

Fixtures are hermetic `mktemp` trees. **No fixture path or literal may contain a key-shaped string,
`secret`, `credential`, `.env`, `.pem` or `.key`** — `protect-files.sh` denies paths containing
`secrets`, and the secret/dependency gate harness scans this repository's tracked files as its
false-positive corpus.

## Ownership and batching, with the expected reds declared in advance (ADR-0101)

An assertion must not land in the same batch as the task that greens it. Every red below is
declared; anything else halts.

| Batch | Tasks | Agent | Expected checkpoint state |
|---|---|---|---|
| A | 1 | tester | RED — every `NB` assertion fails; the script does not exist yet. `NB1` (the anchor) red too |
| B | 2 | coder | `NB1`–`NB14` green. `NB15`–`NB21` still RED (`SKILL.md`, PAIRS, CI untouched). `spec-coverage.test.sh` unchanged and still `PASS=170 FAIL=0` |
| C | 3, 4 | tester | `RS0` added and green; `RS7`–`RS10` rewritten and green; baseline header updated with **zero row changes**; `NB15`–`NB21` still RED |
| D | 5, 6 | coder | `NB15`–`NB21` green; full suite green |
| E | 7 | coder | the record lands; full suite green |
| F | 8 | tester | plants declared, each seen RED once, registry green, full suite re-run |

**Batch C is the dangerous one.** It rewrites a live 130-row comparison. Run
`bash staging/plugin/scripts/tests/spec-coverage.test.sh` before and after and diff the two outputs:
the only permitted difference is the added `RS0` line.

---

### Task 1 — the `NB` assertions, written RED before the script exists (R-01, R-02, R-03, R-04, R-05, R-06)

**Agent:** tester. **File:** `staging/plugin/scripts/tests/spec-coverage-baseline-bump.test.sh` only
(create).

Header in this repository's harness idiom: offline, hermetic, no network, no `$HOME` dependency,
Bash 3.2 clean, `set -u`, `SCRIPTS`/`STAGING`/`REPO` resolved from `$(dirname "$0")`, `ok()`/`bad()`
defined locally (never imported — ADR-0086 keeps these files self-contained), `TMP=$(mktemp -d)` with
a `trap ... EXIT`. The header must name `ADR-0166` and
`2026-08-22-460-spec-coverage-baseline-never-bumped.md`.

`ROWS="$STAGING/plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh"`.

**Anchor.**

- `NB1` — `$ROWS` exists and is readable at that exact path; otherwise every assertion below is
  meaningless. Existence check, **unplantable by class** (the `PT1`/`PT2`/`AIJ2` precedent) — declare
  that at the site so Task 8 does not go looking.

**`--rows` (R-02).**

- `NB2` — a fixture SPEC declaring two ids, with a plan citing both and a discovered test file naming
  the plan back: stdout is exactly two lines, `<spec-basename><TAB><id><TAB>COVERED` each. Assert the
  **basename**, not the path — a full path here is the whole defect.
- `NB3` — the three verdicts are read off the checker's stdout and never re-interpreted: one fixture
  producing `COVERED`, one `UNSCOPED`, one `UNCOVERED`, each asserted on its own row.
- `NB4` — a SPEC declaring zero ids: empty stdout, exit 0. Not "0 rows", nothing.
- `NB5` (also protects `RY10`) — stderr passthrough. A fixture whose plan names no discovered test
  file: the script's **own stderr** contains `SCOPE-EMPTY`, verbatim from the checker, and contains
  no line the script added itself. Assert both halves separately. Without this, ADR-0166 §M3's
  collapse is invisible until a floor trips.
- `NB6` (rule 4) — with `spec-coverage.sh` unresolvable (point the script at a `--scov-override` that
  does not exist, or run it from a stripped fixture tree): **exit 3**, empty stdout, a stderr line
  naming the missing script. A bump that could not compute must not read as one with nothing to do.

**`--pair` (R-01, R-02).**

- `NB7` — `460-foo.spec.md` against a plans dir holding `2026-08-22-460-foo.md` resolves to it;
  against a dir holding only `2026-08-22-foo.md` it falls back to the slug form; against a dir
  holding neither it prints nothing and exits 0. Three sub-cases, one assertion each is fine.

**`--bump` (R-01, R-03, R-04, R-06).**

- `NB8` (R-01) — a baseline fixture missing both rows: after the bump the two rows are present, in
  three-column form, stdout is `BUMPED 2 row(s) for <spec-basename>`, exit 0.
- `NB9` (R-03) — the fixture baseline also carries rows for a **different** spec, one of them
  carrying the **same** id and one in five-column form. After the bump those rows are byte-identical:
  diff the pre-existing region, do not spot-check one row.
- `NB10` (R-06) — a second identical bump exits 0, prints `BUMP-NOOP: already present`, and leaves
  the whole file byte-identical (`cmp` against a copy taken before the call).
- `NB11` (R-04) — a baseline whose row for this pair says `UNSCOPED` while the computed verdict is
  `COVERED`: **exit non-zero**, the file byte-identical, and the output names the id **and both
  verdicts**. Four separate checks; a single combined `if` here hides which half broke.
- `NB12` (R-01) — a SPEC declaring no ids: `BUMP-NOOP: SPEC declares no ids`, exit 0, file
  byte-identical.
- `NB13` (R-03, ADR-0166 §D6) — `--baseline` names a path that does not exist: `BUMP-NOOP: no
  baseline at <path>`, exit 0, and the path **still does not exist** afterwards. A foreign project
  has no corpus baseline and must not acquire one.
- `NB14` (R-03) — a baseline fixture whose last line carries **no trailing newline**: after the bump
  the previously-last row is still its own line. Build the fixture with `printf` without a final
  `\n`; this is the append bug that corrupts two rows into one.

**The `SKILL.md` wiring (R-01, R-05).**

- `NB15` (R-05) — Step 7.0b of `staging/plugin/skills/concept-to-code/SKILL.md` carries a fence
  declared `<!-- fence-contract: c2c-step7-baseline-bump -->`, positioned **after** the
  `spec-archive.sh` invocation and **before** the Step 7.0c transition. Assert the ordering by line
  number of the three anchors, not by their presence.
- `NB16` (R-05) — **the executed proof.** Extract that fence by its marker literal
  (`fence-contract: c2c-step7-baseline-bump -->` — this is also `F4`'s second accepted coverage form,
  so the literal must appear in this file) and run it three times against fixture trees with
  `CLAUDE_PLUGIN_ROOT` exported at `$STAGING/plugin`: (a) a bumpable baseline → exit 0; (b) a
  conflicting baseline → non-zero; (c) `CLAUDE_PLUGIN_ROOT` pointing at a tree with no script and no
  `$HOME/.claude` copy → non-zero. Write your own small extractor anchored on the marker; do **not**
  import a helper from another harness (ADR-0086).
- `NB17` (R-05, rule 3) — Step 7.0b's prose states that a non-zero bump halts before the `commit`
  invocation. Match on a **flattened, undecorated, case-insensitive** copy of the file so a re-wrap
  or a bolding cannot break it, and choose a needle that cannot be satisfied by the prose explaining
  the mechanism (rule 1).
- `NB18` (R-01, rule 3) — Step 7.0b's `commit` invocation line names the baseline path in its
  `--include` list alongside the archived SPEC and the manifest. Same flattened match.
- `NB19` (R-01, rule 17) — **the producer and the consumer meet.** The baseline path the Step 7.0b
  fence passes to `--baseline`, resolved against the repo root, is exactly
  `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv`, **and that file exists**. This is
  the assertion that stops ADR-0166 §D6's absent-baseline no-op from swallowing a typo.

**Deployment and CI (R-01).**

- `NB20` — `staging/sync-to-claude.sh`'s `PAIRS` block contains the exact line
  `plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh|skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh`.
  Extract the `PAIRS` block first (`awk '/^PAIRS="$/{f=1;next} /^"$/{f=0} f'`) and match with
  `grep -qxF`, the form `RG2` already uses. Nothing else in CI can catch a missing entry here: the
  PAIRS completeness harness's `check_complete` does not cover `plugin/skills/*/scripts/`.
- `NB21` — `.github/workflows/docs-ci.yml`'s shell-tests `for t in ...` list contains
  `spec-coverage-baseline-bump` as a whole token. Use the anchored form `RG1` uses
  (`grep -qE '[[:space:]]spec-coverage-baseline-bump[[:space:];]'`) — an unanchored match is
  satisfied by `spec-coverage` alone.

Budget: staging/plugin/scripts/tests/spec-coverage-baseline-bump.test.sh (~430 lines)

### Task 2 — the extracted script (R-01, R-02, R-03, R-04, R-06)

**Agent:** coder. **File:**
`staging/plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh` only (create).

Bash 3.2 clean, `set -u`, mode 644, invoked as `bash <path>`. Resolve `spec-coverage.sh` as a sibling
of `$0` first, then `$HOME/.claude/skills/concept-to-code/scripts/spec-coverage.sh`; a
`--scov-override <path>` argument exists for the harness's `NB6` fixture and for nothing else.

Header contract block, in the idiom `spec-coverage.sh`'s own header uses, stating: this is a
**producer with a checker's exit-code channel**, the four exit codes, that it never re-interprets the
checker's tokens, and that its consumers are the harness and Step 7.0b — never `stop-gate.sh` (rule
20).

**Exit codes (ADR-0166 §D4).** `0` success · `1` conflict, nothing written · `2` invalid invocation
or unreadable input · `3` did not run (checker unresolvable, or the checker itself exited 2 or 3).

**`--pair --spec <spec> --plans-dir <dir>`** — `_bn=$(basename "$spec")`, `_n=${_bn%%-*}` kept only
when it is all digits, `_rest=${_bn#*-}`, `_slug=${_rest%.spec.md}`. Try
`ls "$dir"/????-??-??-"$_n"-*.md 2>/dev/null | head -1`, then `ls "$dir"/????-??-??-"$_slug".md
2>/dev/null | head -1`. Print the resolved path, or nothing. Exit 0 either way. This is the harness's
existing per-spec logic **moved**, not rewritten — copy it line for line and change only the variable
names it needs.

**`--rows --spec <spec> --plan <plan> --tests-root <root>`** —

1. `_list=$(bash "$scov" --spec "$spec" --plan "$plan" --list 2>/dev/null)`. Empty → exit 0, no
   output.
2. `_run=$(bash "$scov" --spec "$spec" --plan "$plan" --tests-root "$root")` with **stderr not
   redirected** — it inherits the script's own stderr and reaches the caller verbatim (ADR-0166 §D3).
   Capture the checker's `rc`.
3. `rc >= 2` → exit 3 with a prefixed diagnostic on stderr and **no stdout**. `rc` of 0 or 1 is
   normal and carries verdicts.
4. Per id from `_list`: default `UNCOVERED`; a `grep -q` for the checker's own `COVERED` line →
   `COVERED`; a `grep -q` for its `UNSCOPED` line → `UNSCOPED`. **Exactly the two greps the harness
   uses today**, same anchors, same order. Emit `<basename spec><TAB><id><TAB><verdict>`.

The `while read` over `_list` must not run in a pipeline subshell if it accumulates anything — use a
temp file and `done <"$file"`.

**`--bump --baseline <file> --spec <spec> --plan <plan> --tests-root <root>`** —

1. `--baseline` absent from disk → `BUMP-NOOP: no baseline at <path>`, exit 0, create nothing.
2. Resolve the pair with the `--pair` logic against the directory holding `<plan>`. No resolution →
   `BUMP-NOOP: pair not in the harness population`, exit 0. Resolution that is **not** `<plan>` →
   exit 1 naming both paths, write nothing.
3. Compute rows with the `--rows` logic. Empty → `BUMP-NOOP: SPEC declares no ids`, exit 0.
4. **Two passes, never one.** First pass: for every computed row, look up the existing verdict with
   `awk -F<TAB> '$1==s && $2==i {print $3; exit}'`. If any present row's verdict differs → exit 1,
   name the SPEC, the id and **both** verdicts, write nothing at all. Only if the first pass is clean
   does the second pass write.
5. Second pass: copy the baseline to a temp file, add a trailing newline first if the last byte is
   not one (`tail -c 1`), append the absent rows in `--rows` order, `mv` the temp over the baseline.
   All rows already present → `BUMP-NOOP: already present`, exit 0, **do not rewrite the file**.
   Otherwise `BUMPED <n> row(s) for <spec-basename>`, exit 0.

Never rewrite, reorder or reformat an existing line. Never emit a five-column row.

Budget: staging/plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh (~240 lines)

### Task 3 — rewrite the `RS7`–`RS10` derivation to read the script (R-02, R-07)

**Agent:** tester. **File:** `staging/plugin/scripts/tests/spec-coverage.test.sh` only.

The block at the `RS7-RS10` banner. Add `ADR-0166` and this plan's basename to that banner, plus one
paragraph stating what moved and what did not.

- Add `RS0`, immediately after the banner: `$STAGING/plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh`
  exists and is readable, otherwise `RS7`/`RS8a`/`RS8b`/`RS9` below are meaningless. Existence check,
  unplantable by class — say so at the site.
- `RS_PAIRS` loop: keep the corpus sweep, `spec_declares_ids` and the `RS_SELF_PLAN` exclusion exactly
  as they are. Replace **only** the two-glob plan resolution with one call to the script's `--pair`.
- `RS_LIVE` loop: replace the `--list` + `--tests-root` pair of calls and the per-id classification
  with one call to `--rows`, capturing stderr into the same `$TMP/rs-live-err.txt` the loop already
  uses. `_errtxt`, `_no_backref`, `_scope_n` and the `RS_SCOPE` append are **not edited** — they read
  the passthrough (ADR-0166 §D3). Preserve today's ordering exactly: skip the pair when the rows are
  empty, **before** appending to `RS_SCOPE`, so `RY10`'s denominator is unchanged.
- `RS7`, `RS8a`, `RS8b`, `RS9a`, `RS9b`, `RY10`, `RS10`: **not one character changes** — not a
  predicate, not a floor, not a message. Only where `RS_LIVE`'s rows come from moves.
- Leave a comment where the inline derivation stood, naming issue #460 and ADR-0166 (rule 19).

`RS7`'s existing plant, which mutates a baseline row, must still fire after this — it is the proof
that `--rows` produces what the frozen rows say. Verify by hand before finishing:
`bash staging/plugin/scripts/tests/plant-check.sh` filtered to `RS7`.

Run the harness before and after and diff the two outputs. **The only permitted difference is the
added `RS0` line**: `PASS` goes 170 → 171, `FAIL` stays 0, and no `RS`/`RY` message text changes. Any
other delta means the extraction is not faithful — halt, do not adjust the baseline.

Budget: staging/plugin/scripts/tests/spec-coverage.test.sh (~90 lines)

### Task 4 — the baseline's header, corrected forward (R-07, R-08)

**Agent:** tester. **File:** `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv` only.
**Zero rows change.**

- Rewrite the `HOW IT IS PRODUCED` sentence that names `spec-coverage.test.sh`, section `RS7-RS8`
  (`RS_PAIRS` / `RS_LIVE`) as "the regeneration procedure". After Task 3 that is false: the
  regeneration procedure is `spec-coverage-baseline-rows.sh --rows`, and the harness's sweep is the
  loop around it. This is an **instruction**, so it is corrected in place.
- Rewrite the `WHEN TO REGENERATE` paragraph: a completing chain now bumps its own rows at Step 7.0b,
  so the manual procedure applies only to pairs no chain enrolled (a hand-placed SPEC) and to a real
  drift signal (a later feature renaming a test file and flipping an existing pair's verdict). Name
  the two operator commands: `--rows` to see a pair's rows, `--bump` to append them.
- Append a dated `2026-08-22` block: what moved (the derivation, not the rows), the re-derived state
  (16 pairs, 130 ids, 130 rows, 106/12/12, zero divergence), that **0 of 130 rows changed**, and
  ADR-0166 as the reference.
- **Do not touch** the `MEASURED 2026-08-14`, `2026-08-18` or ADR-0157 blocks. Those are records, not
  instructions (rule 14).

R-08's obligation here is the dated block; the number itself is recorded in ADR-0166 §M1, including
the correction to the SPEC's "16 baseline rows".

Budget: staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv (~30 lines, all comments)

### Task 5 — Step 7.0b calls the bump, and the rows ride the same commit (R-01, R-05)

**Agent:** coder. **File:** `staging/plugin/skills/concept-to-code/SKILL.md` only.

Insert between the existing `spec-archive.sh` / `manifest-set-artifact.sh` block and the **Step 7.0c**
heading. Nothing above or below moves.

Prose lead-in, two sentences: Step 7.0b's archive is the event that enrols this chain's SPEC into the
frozen corpus baseline, so this is where its rows are written; the rows must land in **this** commit
or the next unrelated author inherits the red (issue #460, ADR-0166).

Then a fence carrying `<!-- fence-contract: c2c-step7-baseline-bump -->` on the nearest non-blank line
above it. Inside, the established shape: an `export` prologue for the caller-bound free variables, a
`bash <<'FENCE_BASH'` wrapper, **terminator at column 0**, no positional-parameter token (rule 15,
ADR-0133). The body:

1. Two-tier resolution of `spec-coverage-baseline-rows.sh` — `$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/`
   then `$HOME/.claude/skills/concept-to-code/scripts/` — copied from the block at the Requirement-ID
   coverage gate, which resolves the sibling `spec-coverage.sh` the same way. Unresolvable → print
   `BASELINE_BUMP_NORUN noScript` with the `sync-to-claude.sh --apply` remedy, exit 3.
2. `_baseline="$ROOT/staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv"`.
3. Invoke `--bump --baseline "$_baseline" --spec "$ARCHIVED_SPEC" --plan "$PLAN" --tests-root
   "$ROOT"`. Print its stdout, exit with its rc.

`--tests-root` is passed **unconditionally** — not conditioned on `test_cmd_placeholder` or
`test_cmd_provisional` the way the Gate 4.x call is. State the reason at the site in one sentence
(ADR-0166 §D5): the baseline's rows are defined by what the harness computes, and the harness always
passes it.

Branch table below the fence, as a **checker** (rule 5):

- `0` with `BUMP-NOOP: …` → proceed silently. Nothing was written.
- `0` with `BUMPED <n> row(s)` → the baseline is modified on disk. Emit one line naming the path and
  the count, and **add that path to the `--include` list of the `commit` invocation below**.
- non-zero (`1` conflict, `2` invalid, `3` did not run) → **HALT. Do not invoke `commit`.** Print the
  script's stderr verbatim and name the file a human must look at. Say, in the same breath, that this
  is deliberate: an unbumpable baseline stops the chain that would have caused the drift, at the
  point someone can still act on it.

Then extend the existing `commit` invocation:
`Arguments: --include <archived-spec-path>,<manifest-path>[,<baseline-path> — only when the bump reported BUMPED]`.

Add one sentence stating that the halt and the `--include` extension are **instructions and not
enforcements** (rule 16): what is enforced is the fence's own exit code, executed by
`spec-coverage-baseline-bump.test.sh`.

Budget: staging/plugin/skills/concept-to-code/SKILL.md (~70 lines)

### Task 6 — deploy it and run it in CI (R-01)

**Agent:** coder. **Files:** `staging/sync-to-claude.sh`, `.github/workflows/docs-ci.yml`.

- One `PAIRS` line, in the `plugin/skills/concept-to-code/scripts/` group beside `spec-coverage.sh`:
  `plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh|skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh`.
  Zones match on both sides, so **do not** add a `pairs-zone-anomaly:` entry — a third anomaly there
  would fail its own guard, and this is not one (ADR-0166 §D1).
- Append `spec-coverage-baseline-bump` to the shell-tests `for t in ...` list. One token, no other
  edit to that workflow.

Verify with `bash staging/sync-to-claude.sh` (dry run) that the new pair resolves and that no
deployed-only or zone warning appears.

Budget: staging/sync-to-claude.sh (~1 line), .github/workflows/docs-ci.yml (~1 line)

### Task 7 — the record (R-08)

**Agent:** coder. **Files:** `docs/chain-decisions.md`, `docs/chain-decision-index.md`, `PROJECT.md`.

- A `docs/chain-decisions.md` block appended after the ADR-0163 one, heading in the established form
  (`## Decisions from the … chain (ADR-0166)`): what was measured (16 pairs / 130 rows / zero
  pre-existing gap, and the SPEC's own row-count slip corrected forward), the one hazard the design
  turns on (a single checker invocation feeding both `RS_LIVE` and `RY10`'s stderr-derived
  denominator), and the two obligations that stayed instructions.
- One `docs/chain-decision-index.md` line for ADR-0166, in the existing one-line form ending in the
  ADR path. **Do not** add a twentieth `CLAUDE.md` rule — #470 is already adding one on its own
  branch, and this feature adds no new invariant.
- Tick the Phase 18 row `- [ ] Step 7.0b enrols a SPEC in the scope-baseline corpus and nothing bumps
  the baseline  (issue #460)` in `PROJECT.md`, with the completion note the recent rows use: the
  date, ADR-0166, the extracted script and its three modes, the assertion and plant counts, and the
  fact that 0 of 130 rows changed. A checkbox is ticked in the same commit that closes its item.

Budget: docs/chain-decisions.md (~34 lines), docs/chain-decision-index.md (~1 line), PROJECT.md (~1 line)

### Task 8 — a plant for every new assertion, and the registry run (R-07)

**Agent:** tester. **Files:** `staging/plugin/scripts/tests/spec-coverage-baseline-bump.test.sh`
(plant declarations only), `staging/plugin/scripts/tests/spec-coverage.test.sh` (nothing new).

One `# plant:` declaration at column 1 beside each of `NB2`–`NB21`, three or four fields, staging-
relative target path. `NB1` and `RS0` are existence checks and are **unplantable by class** — record
that in a comment at each site rather than leaving a gap someone has to re-adjudicate.

Suggested targets, one per assertion, each mutating the mechanism and not the message:

- `NB2`–`NB4`, `NB7`–`NB14` → the corresponding branch inside `spec-coverage-baseline-rows.sh`
  (`basename` → `echo`, the `UNSCOPED` grep → a never-matching one, the conflict `exit 1` → `exit 0`,
  the trailing-newline check → `if false; then`, the two-pass ordering collapsed into one).
- `NB5` → remove the stderr passthrough (add `2>/dev/null` to the `--tests-root` invocation). This
  plant is the one that proves ADR-0166 §M3's hazard is actually guarded.
- `NB6` → make the unresolvable-checker branch `exit 0`.
- `NB15`–`NB19` → the corresponding line in `SKILL.md` (delete the marker; move the fence after the
  7.0c heading; delete the halt sentence; drop the baseline path from `--include`; change the
  baseline path to a neighbouring one).
- `NB20` → break the PAIRS destination. `NB21` → remove the token from the CI loop.

Run `bash staging/plugin/scripts/tests/plant-check.sh` and require **`FIRED` on every one**. A
`NOFIRE` convicts the assertion, not the plant — repair the assertion, never the plant, and never
delete either.

Then run the **full suite**, not just the two harnesses this feature touches:
`for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`. The `RS7`–`RS10`
rewrite changes a contract several harnesses read indirectly through the deployed skill tree, and a
green pair of files is not evidence about the other 94.

Budget: staging/plugin/scripts/tests/spec-coverage-baseline-bump.test.sh (~40 lines)

---

## Staleness — the call sites of the changed contract, already grepped

Grepped 2026-08-22 for `spec-coverage-scope-baseline`, `RS_PAIRS` and `RS_LIVE` across the whole
repository, excluding `.git`:

| Site | Action |
|---|---|
| `staging/plugin/scripts/tests/spec-coverage.test.sh` — the `RS7`–`RS10` block, plus the `RS7` plant line | Task 3 |
| `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv` — header, twice | Task 4 |
| `staging/plugin/scripts/tests/spec-coverage.test.sh` — two later comments naming the baseline (the R-07 explanation of the ADR-0154 feature, and the ADR-0157 note) | leave; they are records of their own features |
| `staging/plugin/skills/concept-to-code/SKILL.md` — a prose mention of the baseline with stale `24 of 117` numbers | leave; dated prose about ADR-0138, not a call site |
| `SPEC.md`, `docs/specs/*.spec.md`, `docs/architecture/ADR-0138/0154/0157`, `docs/superpowers/plans/2026-08-14-*`, `2026-08-18-*`, `docs/chain-decisions.md` | leave — historical records, corrected forward only (rule 14) |

No source call site outside the two files Tasks 3 and 4 own reads the baseline or the derivation. The
one behavioural contract that changes shape — where `RS_LIVE`'s rows come from — has exactly one
consumer, and it is the file that produced them.

## Risks

- **The `RY10` collapse (ADR-0166 §M3).** One checker invocation feeds two consumers. `NB5` and the
  unchanged `RS_SCOPE` block are the guard; if `RY10` drops from 16 in Batch C, stop.
- **A silent verdict shift.** If `--rows` classifies even one id differently, all 130 rows are
  suspect. The before/after diff in Task 3 is not optional.
- **Foreign-project chains.** Step 7.0b runs everywhere. `NB13`'s absent-baseline no-op is what keeps
  every non-vibe-coding-system chain from halting at 7.0b.
- **`main`.** The measurements above were taken on `main` at `1fdd96f`. This work must not be
  committed there.
