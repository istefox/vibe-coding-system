# Implementation plan — a per-file budget ceiling survives to the comparison

- **Issue:** #296
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md` (R-01, R-02, R-03)
- **ADR:** `docs/architecture/ADR-0189-a-per-file-budget-ceiling-is-parsed-and.md`
- **ARCH:** n/a — a scoped change inside an already-documented mechanism
  (ADR-0052 → ADR-0070 → ADR-0091 → this).
- **Stack:** Bash 3.2 (macOS `/bin/bash`) plus POSIX `awk`/`sed`/`grep`/`sort`. No `mapfile`, no
  bash associative arrays, no `${var^^}`, no `[[ ]]`, no process substitution, no `<<<`. Awk
  associative arrays are fine and already used throughout this script. One awk library, one script,
  one reference doc, one existing harness. **No new file anywhere** — so no `PAIRS` entry, no
  `docs-ci.yml` shell-tests list entry, no plant-shard change.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`

TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: sonnet

---

## Read this first — state measured 2026-09-02 at `d2be4fa` (rule 13)

**Re-derive it; do not trust this block.** ADR-0091's own numbers (16 declarations, 3 per-file) are
a snapshot of 2026-07-31 and are wrong today by an order of magnitude.

```text
plans in docs/superpowers/plans/:                            79
plans carrying >= 1 parseable `Budget:` declaration:         23
parseable declarations (>= 1 qualifying paren group):       159
  MULTI (>= 2 qualifying groups — the per-file form):        24, in 7 plans
  SINGLE (one group — the documented form):                 135
declared file entries across all groups:                    205
  containing a glob character (`**`, `*.md`):                 2
diff-budget-scope.test.sh assertions executed today:         56  (55 + Z1)
Z1's current floor:                                          >= 55
assertion prefix BL:                                      FREE   (grep -rnoE '\bBL[0-9]+' staging/ -> 0)
existing B sections:            BA BB BC BD BE BF BG BH BJ BK BT
plants declared in this harness:                              6
`FILEBUDGET` occurrences anywhere in staging/:                0
parse_budget() call sites:      diff-budget-check.sh x1, step5-brief.sh x2, BK9's extracted copy x1
awk on this machine:                              awk version 20200816 (BWK); CI is ubuntu-latest
```

**The defect, reproduced before any code (do this first, it is the red evidence Task 1 pins):**

```text
$ printf ' staging/plugin/skills/ui-layout-audit/SKILL.md | 100 ++\n staging/sync-to-claude.sh | 60 ++\n' \
  | bash staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh \
      --plan docs/superpowers/plans/2026-07-30-222-vendor-deployed-only-skills.md --tasks 2
CLEAN
```

`sync-to-claude.sh` is declared at `(~1 line)` and carries 60. The task total (160) is under the
summed 166, so nothing reports. The control (same files at 100/100) still prints
`BUDGET<TAB>2<TAB>files=2/2<TAB>lines=166/200<TAB>margin=34`.

## Read this second — the observable contract change, and every call-site that asserts the old one

**Three observable contracts move.** Greps were run; the call-sites are listed, not left for the
coder to find.

1. **`parse_budget`'s signature** gains an optional second parameter. Its **return value does not
   change** (ADR-0189 §D1), which is why no call-site below needs an edit — but each was checked:
   - `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh`, in the heredoc'd
     `plan_parse.awk`: `parsed = parse_budget(rest)` — **this one Task 4 changes** (to pass the
     array).
   - `staging/plugin/skills/concept-to-code/scripts/step5-brief.sh`, twice (the read-mode
     `collect.awk` and the write-mode one): `parsed = parse_budget(rest)` — **unchanged, and must
     stay unchanged.** Its harness `step5-brief.test.sh` loads the same awk library directly.
   - `staging/plugin/scripts/tests/diff-budget-scope.test.sh` §BK9: extracts the function with
     `sed -n '/^function parse_budget/,/^}$/p'` and calls it with one argument — **unchanged, and
     `BK9a/b/c` must stay green untouched.** Do not rename the function, do not add a second
     function whose name begins with `parse_budget`, and keep the closing `}` at column 0 with
     nothing else on the line.
2. **`diff-budget-check.sh`'s stdout grammar** gains a fifth token, `FILEBUDGET`. Grep for
   consumers: `grep -rn "\^BUDGET\|MALFORMED\|CLEAN" staging/plugin/skills/*/SKILL.md
   staging/plugin/skills/*/references/*.md staging/plugin/skills/*/scripts/*.sh`. The consumers are
   `references/step5-implementation.md` (the "Diff budget and scope check" block — **Task 6
   extends it**) and `SKILL.md` Step 4.5's tracer-bullet block (**deliberately unchanged**, ADR-0189
   §D7). No script branches on the tokens.
3. **`step5-report.json`'s `budget_findings` array** gains a fourth entry shape. Its consumer is
   `staging/plugin/skills/project-conductor/scripts/h16-direction-check.sh`, which reads
   `(.budget_findings // []) | length` and triggers at `>= 2`. **No edit needed** — a per-file
   overrun is a budget overshoot and belongs in that count — but the sensitivity change is real and
   is recorded in ADR-0189's Consequences. Do not "fix" it by filtering.

**Run the FULL suite, not just `diff-budget-scope.test.sh`.** `step5-brief.test.sh` loads the same
awk library, and `plant-check.sh` sweeps the whole tree; a change to a shared producer can go red in
a harness that never mentions this feature.

## Read this third — two failures that are NOT this feature's, and must not be "fixed"

The harness carrying assertions `RS0`–`RS10` (its basename is deliberately not written here — see
the coverage warning below) went from green to **`PASS=174 FAIL=2`** the moment this plan file
landed on disk, before a line of source changed:

```text
FAIL: RS7:  3 of 201 live (spec, id) verdict(s) diverge from the frozen baseline
FAIL: RS8a: 3 live (spec, id) verdict(s) have NO baseline row — the baseline is short some rows
```

`docs/specs/296-a-per-file-budget-ceiling-is-parsed-and.spec.md` already exists, so writing
`docs/superpowers/plans/2026-09-02-a-per-file-budget-ceiling-is-parsed-and.md` resolved a new
(spec, plan) pair and added this feature's three ids to the live sweep. The frozen baseline
`staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv` carries 198 rows; the sweep now
finds 201. The pair count moved from 15 (measured 2026-08-14) to 23.

**This is the ordinary in-flight state of every chain since ADR-0166 / issue #460, and it has an
owner: Step 7.0b's `c2c-step7-baseline-bump` fence, which bumps this chain's own rows through
`spec-coverage-baseline-rows.sh --rows`.** Do not hand-edit a row into the `.tsv` — its own header
forbids it without re-running the derivation. Do not weaken `RS7`/`RS8a`. Do not add a task for it;
Step 7.0b already owns it. Expect exactly these two, with exactly `3` in both messages: a different
count means something else moved and is worth reading.

Every other harness was green with this plan on disk: `diff-budget-scope` 56/0, `step5-brief` 39/0,
`plan-task-count` 58/0, `cross-reference-form` 38/0, markdownlint 0 issues across 323 files.

## Read this fourth — the design in one paragraph, so no task has to re-derive it

`parse_budget(rest, groups, ...)` fills `groups[i] = "<files>\t<ceiling>"` per accepted paren group
and `groups[0]` with the count, returning the same string it always did. The driver writes one
`GROUPS_FILE` row per group: `<task><TAB><files><TAB><ceiling><TAB><group-count-of-that-task>`. For
the selected tasks only, each row is exploded into one `<file><TAB><ceiling><TAB><reportable>` row
per comma-separated entry, where `reportable` is `1` when that task's group count is `>= 2`. Awk
sums `ceiling` per file and ORs `reportable` per file. The candidate loop, in its already-existing
in-scope branch, appends `<resolved-path><TAB><count>` to an actuals file. A final awk joins the two
and emits `FILEBUDGET` for every file where `reportable` **and** `actual > ceiling`, `sort`ed for
deterministic output, gated on `BUDGET_LIVE`, emitted after the `BUDGET` line and before
`MALFORMED`.

## Files this plan touches

| File | Task | What |
| --- | --- | --- |
| `staging/plugin/skills/concept-to-code/scripts/plan-budget-parse.awk` | 2 | optional `groups` out-param |
| `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh` | 4 | groups table, attribution, `FILEBUDGET` |
| `staging/plugin/skills/concept-to-code/references/step5-implementation.md` | 6 | the consumer |
| `staging/plugin/scripts/tests/diff-budget-scope.test.sh` | 1, 3, 5, 7 | section `BL`, plants, `Z1` |

Nothing else. If a task seems to need `sync-to-claude.sh`, `docs-ci.yml`, `CLAUDE.md`, `PROJECT.md`
or a new file, stop and report — that is scope drift, not a discovery.

## Assertion ids and the harness contract

Section `BL`, ids `BL1`–`BL12`. Prefix verified free across `staging/`. Every `BL` assertion gets a
`# plant:` declaration at **column 1** beside it, in the form
`# plant: <id> | plugin/... | <needle> | <replacement>` (three fields deletes). Needles must belong
to the mechanism and to nothing else (rule 1) — never the word `FILEBUDGET` alone, which appears in
prose in three files by the end of this plan.

**ADR-0154 back-reference.** Task 1 adds to the harness header, verbatim, both literals:
`ADR-0189` and `docs/superpowers/plans/2026-09-02-a-per-file-budget-ceiling-is-parsed-and.md`.
Without one of them `spec-coverage.sh` descopes the file and R-01/R-02/R-03 report `UNSCOPED`.

**Coverage warning — `spec-coverage.sh` reports all three ids `COVERED` before any of this work
exists. Measured 2026-09-02, on this plan, against an unmodified tree:**

```text
first draft, which named one unrelated harness by basename in a throwaway aside:
  COVERED R-01 / COVERED R-02 / COVERED R-03 — 3 covered, 0 uncovered, 3 in scope   rc=0
with that one basename replaced by its assertion ids (this plan as it stands):
  COVERED R-01 / UNSCOPED R-02 / UNSCOPED R-03 — 1 covered, 2 unscoped, 2 in scope  rc=1
```

**`rc=1` before Task 1 runs is the correct state, not a defect.** `UNSCOPED` means the id is
mentioned somewhere in the tree but in no file this plan scopes — the honest verdict when the
assertions do not exist yet. It resolves when Task 1 writes `R-02` and `R-03` into the `BL`
assertion headers inside the scoped harness. If it is still `UNSCOPED` after Task 1, the ADR-0154
back-reference literals are missing from the harness header; do not chase it in `SPEC.md`.

One incidental prose mention of a harness this plan does not own was enough to flip all three ids
green. That is why the mention was removed, and it is worth remembering: naming a harness in a plan
imports its whole `R-NN` namespace.

Every remaining match is foreign, not evidence:

- `R-01` — eight fixture heredocs in `diff-budget-scope.test.sh` (`## Task 1 — Mixed (R-01)` and
  siblings) write the literal into synthetic plan files.
- `R-02` and `R-03` — the `BB2c` / `BB2d` failure messages, which cite **issue #358's** R-02 and
  R-03, a different feature's namespace entirely. Rule 18 exactly: an identifier whose namespace
  restarts per feature, matched against a repo-wide file set.

So the tool's verdict is uninformative for this feature in **both** directions and must not be read
as a gate. The real evidence is the plant registry (`plant-check.sh` — every `BL` seen RED) and the
requirement ids cited in the new assertions' own comment headers. Cite all three there anyway: they
are what a later reader greps, and what keeps the citation honest if the foreign matches are ever
removed.

## Batching

| Batch | Tasks | Expected state at the checkpoint |
| --- | --- | --- |
| A | 1 | `BL1`–`BL5` RED (the feature does not exist), `BL6`–`BL12` RED |
| B | 2, 3 | `BL6`–`BL8` GREEN (parser level), `BL1`–`BL5` still RED |
| C | 4, 5 | `BL1`–`BL5`, `BL9`–`BL11` GREEN |
| D | 6, 7 | `BL12` GREEN, `Z1` bumped, full suite green |
| E | 8 | plants fire, whole suite re-run |

Task 1 must not sit in the same batch as Task 2 or 4 (ADR-0101 rule 1 — an assertion must not share
a batch with the task it depends on).

---

## Task 1 — TEST: section `BL`, every assertion RED (R-01, R-02, R-03)

Owner: **tester**. Edit `staging/plugin/scripts/tests/diff-budget-scope.test.sh` only. Add section
`BL` after `BK10` and before `Z1`. Do not touch `BK9a/b/c` — their staying green untouched is
itself evidence (ADR-0189 §Verification).

Header block for the section states: the ADR-0154 literals (`ADR-0189` and this plan's full path),
that the section covers SPEC **R-01, R-02, R-03**, that the prefix `BL` was verified free on
2026-09-02, and that `BL1`–`BL12` are RED by construction until Tasks 2/4 (a red assertion at the
Batch A checkpoint is the deliverable, not a defect).

- [ ] `BL1` (R-01) — **the red evidence, on the real corpus plan.** `2026-07-30-222-vendor-deployed-only-skills.md`
      task 2, diff `ui-layout-audit/SKILL.md | 100` + `sync-to-claude.sh | 60`. Expect a
      `FILEBUDGET` line naming `staging/sync-to-claude.sh` with `lines=1/60` and `margin=59`, and
      **no** `BUDGET` line (the total 160 is under 166). Anchored `^FILEBUDGET${TAB}` match on the
      full five-field shape, not a bare word.
- [ ] `BL2` (R-01) — **the boundary, both sides.** Synthetic two-group plan `a.md (~10 lines),
      b.md (~10 lines)`. At `a.md | 10` → no `FILEBUDGET` for `a.md` (equal is not over, matching
      `BA1`'s own boundary rule). At `a.md | 11` → `FILEBUDGET` with `lines=10/11 margin=1`.
- [ ] `BL3` (R-01) — **a declared file with zero changed lines produces nothing.** Same plan,
      diff carries only `a.md`; `b.md` must not appear in any output line. An undershoot is not a
      finding.
- [ ] `BL4` (R-01) — **a shared-ceiling group is checked as a unit, and leniently** (ADR-0189 §D2).
      Plan `a.md, b.md (~50 lines), c.md (~10 lines)` — the `BK4` mixed form. Diff `a.md | 40`,
      `b.md | 5`, `c.md | 5`: no `FILEBUDGET` (each member's ceiling is the group's 50). Second
      run, `c.md | 11`: exactly one `FILEBUDGET`, for `c.md`.
- [ ] `BL5` (R-01) — **the ceiling sums across selected tasks, and reportability does not**
      (ADR-0189 §D3's asymmetry, the false positive the gate exists to prevent). Plan: task 1
      multi-group `a.sh (~5 lines), sync.sh (~1 line)`; task 3 single-group `sync.sh (~50 lines)`.
      `--tasks 1,3`, diff `sync.sh | 40`: **no** `FILEBUDGET` — the ceiling is 51, not 1. Then
      `sync.sh | 60`: one `FILEBUDGET` with `lines=51/60`.
- [ ] `BL6` (R-02) — **function-level corpus comparison against a FROZEN pre-#296 `parse_budget`**,
      embedded in the harness as a heredoc, `BK9`'s own device for `BK9`'s own stated reason. Run
      both over `"$REPO"/docs/superpowers/plans/*.md`; **every** declaration must return an
      identical string, single-ceiling and per-file alike. Emit the mismatch count in the failure
      message.
- [ ] `BL7` (R-02, rule 7) — **count guard on `BL6`'s derivation.** At least 100 declarations
      compared (measured 159; a floor with real slack, not a tripwire). Zero comparisons and a clean
      corpus are indistinguishable from outside.
- [ ] `BL8` (R-02, rule 9) — **`BL6` is not vacuous.** For the known corpus declaration
      `ui-layout-audit/SKILL.md (~165 lines, new), staging/sync-to-claude.sh (~1 line)`, calling
      `parse_budget(rest, g)` yields `g[0] == 2`, `g[1]` ending `<TAB>165` and `g[2]` ending
      `<TAB>1`. Without this, `BL6` stays green with the whole feature deleted.
- [ ] `BL9` (R-02) — **script-level whole-corpus sweep, set equality in both directions**
      (ADR-0189 §D8, `BK9b`'s device rather than a count). For each of the 79 plans: derive its
      declared file set, build a synthetic `--stat` giving every declared file a large count, run
      the real script over every declared task, and record whether any `FILEBUDGET` appeared. The
      set of plans that produced one must **equal** the set carrying a multi-group declaration —
      a multi-group plan that produced none and a single-group plan that produced one are both
      violations and both counted. Carry a count guard (>= 15 budget-declaring plans; measured 23).
- [ ] `BL10` (R-02) — **the single-ceiling population is byte-inert.** A synthetic plan whose every
      task declares exactly one group, run over a diff that blows one file wide open: stdout must
      contain a `BUDGET` line and **no** `FILEBUDGET` line, whatever the task selection.
- [ ] `BL11` (R-03) — **the reporter contract.** `FILEBUDGET`-producing runs still exit **0**; a
      run producing nothing still prints the sentinel `CLEAN`; and a plan whose only declaration is
      malformed still emits `MALFORMED` and no `FILEBUDGET` (the inert path is untouched). Assert
      the exit code explicitly — a reporter never branches on one, and this is the assertion that
      says so.
- [ ] `BL12` (R-01) — **the token has a consumer** (rule 17, `BK10`'s pattern). Against the
      flattened `$STEP5` copy, four needles each belonging to one block and to nothing else:
      the grammar line `FILEBUDGET<TAB><tasks-label><TAB><file><TAB>lines=<expected>/<actual><TAB>margin=<N>`,
      the recording instruction naming `{task, file, lines_expected, lines_actual}`, the sentence
      stating a per-file finding can fire with no `BUDGET` line, and the sentence stating no
      `files_*` keys are written. **Never a bare `grep -qF 'FILEBUDGET'`** — by Task 6 the word is
      in three files, which is `BK10`'s own recorded first-draft failure.

Plants (all declared at column 1 beside their assertion): `BL1`–`BL5`, `BL9`–`BL11` target
`plugin/skills/concept-to-code/scripts/diff-budget-check.sh` (invert the comparison, drop the
reportability conjunct, remove the `sort`, delete the `BUDGET_LIVE` gate — one distinct mutation
each); `BL6`/`BL8` target `plugin/skills/concept-to-code/scripts/plan-budget-parse.awk`;
`BL7` and the `BL9` guard self-target; `BL12` targets
`plugin/skills/concept-to-code/references/step5-implementation.md`.

Budget: `staging/plugin/scripts/tests/diff-budget-scope.test.sh` (~230 lines)

## Task 2 — CODE: `parse_budget` gains an optional `groups` out-parameter (R-02)

Owner: **coder**. Edit `staging/plugin/skills/concept-to-code/scripts/plan-budget-parse.awk` only.
Turns `BL6`, `BL7`, `BL8` green.

- Signature becomes `function parse_budget(rest, groups,   s, pre, paren, inner, low, num, files,
  total, rem, ng)`. `groups` goes **second**, before the locals, so a one-argument call still works
  and gets a discarded local array.
- `groups[0] = 0` and `ng = 0` as the **first** statements. Increment `ng` and set
  `groups[ng] = pre "\t" num` as each group is accepted, inside the existing walk. Set
  `groups[0] = ng` only immediately before the successful `return files "\t" total`.
- **Never `delete groups`** — the whole-array form is an extension, not POSIX, and the driver reads
  only `1..groups[0]`, so stale higher indices are unreachable.
- **Change nothing else in the function.** The return value, the `return ""` paths, the
  `looks_like_budget` discriminator and `task_num` are untouched. Keep the closing `}` at column 0
  on its own line — `BK9` extracts this function with a `sed` range that ends there.
- Extend the file header: state that `groups` is an optional out-parameter, that the return value is
  deliberately unchanged so the two existing consumers and `BK9`'s frozen comparison need no edit
  (rule 6 — one producer, widened, not forked), and cite ADR-0189 §D1 and issue #296.

Budget: `staging/plugin/skills/concept-to-code/scripts/plan-budget-parse.awk` (~30 lines)

## Task 3 — TEST: the two untouched consumers still get the identical answer (R-02)

Owner: **tester**. Verification only, no new source. Confirms Task 2 is invisible where it must be.

- [ ] Run `bash staging/plugin/scripts/tests/step5-brief.test.sh` and
      `bash staging/plugin/scripts/tests/diff-budget-scope.test.sh`. `step5-brief.test.sh` must be
      **fully green** and `BK9a/b/c` must be green — they load or extract the function Task 2 just
      edited and neither passes a second argument.
- [ ] If either moves, the return value changed and Task 2 is wrong. Do not adjust the harnesses to
      match; report it.

Budget: none (verification only, no files touched)

## Task 4 — CODE: attribution and the `FILEBUDGET` emission (R-01, R-03)

Owner: **coder**. Edit `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh` only.
Turns `BL1`–`BL5`, `BL9`–`BL11` green.

- Add `GROUPS_FILE="$TMPD/groups.tsv"; : >"$GROUPS_FILE"` beside the existing temp files, and pass
  it to the awk run as `-v GROUPS_FILE=...`.
- In the heredoc'd `plan_parse.awk`, on the successful-parse branch only, call
  `parse_budget(rest, g)` and after the existing `print cur "\t" parsed >> BUDGET_FILE`, loop
  `for (i = 1; i <= g[0]; i++) print cur "\t" g[i] "\t" g[0] >> GROUPS_FILE`. `g[i]` already carries
  `<files>\t<ceiling>`, so the row is `<task><TAB><files><TAB><ceiling><TAB><group-count>`. Nothing
  on the `MALFORMED` or no-match branches changes.
- After `TASK_SET` is expanded and the existing summing loop, build
  `CEIL_RAW="$TMPD/ceil_raw.tsv"`: read `GROUPS_FILE` with `IFS=<TAB> read -r _t _files _ceil _ng`,
  skip rows whose `_t` is not in `TASK_SET` (`grep -qxF`, the existing idiom), then split `_files` on
  `IFS=','` — the same trim-with-awk loop `MASTER_SCOPE` already uses, **copied in shape from it**,
  not re-invented — and emit `<file><TAB><_ceil><TAB><reportable>` where `reportable` is `1` if
  `_ng` is `>= 2`, else `0`.
- In the existing candidate loop's **in-scope branch only** (the one that increments
  `FILES_ACTUAL`), append `printf '%s\t%s\n' "$_lookup" "$_cnt" >>"$ACTUAL_FILE"`. `$_lookup`, not
  `$_path` — the elision-resolved name (ADR-0189 §D6). Out-of-scope files, which take the `SCOPE`
  branch, contribute nothing.
- Emit, inside the existing `if [ "$BUDGET_LIVE" -eq 1 ]` block, **after** the `BUDGET` line and
  before `emit_malformed`:

  ```sh
  awk -F'\t' -v TASKS="$TASKS" '
    FNR == NR { ceil[$1] += $2; if ($3 == "1") rep[$1] = 1; next }
    { act[$1] += $2 }
    END {
      for (f in act)
        if ((f in rep) && act[f] > ceil[f])
          printf "FILEBUDGET\t%s\t%s\tlines=%d/%d\tmargin=%d\n", TASKS, f, ceil[f], act[f], act[f] - ceil[f]
    }
  ' "$CEIL_RAW" "$ACTUAL_FILE" | sort >>"$OUT"
  ```

  The `sort` is not cosmetic: `for (f in act)` has no defined order and a harness cannot assert on
  a non-deterministic line order. Guard both input files with `[ -s ... ]` so awk is not handed a
  missing path.
- **Do not touch** `MASTER_SCOPE`, the `SCOPE` partition, the exclusion `awk`, the whole-plan inert
  check, `emit_malformed`, or the `BUDGET` line's own shape. This change adds; it removes nothing.
- Extend the script's header contract block: add `FILEBUDGET<TAB><tasks-label><TAB><file><TAB>lines=<expected>/<actual><TAB>margin=<N>`
  to the token list, state the ADR-0189 §D2 ceiling-sum rule and the §D3 reportability gate in two
  sentences, and note that the name deliberately does not begin with `BUDGET` so an anchored
  `^BUDGET` grep in an un-updated consumer cannot half-read it.

Budget: `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh` (~70 lines)

## Task 5 — TEST: run section `BL` and confirm the expected greens, and only those (R-01, R-02)

Owner: **tester**. Verification only.

- [ ] `BL1`–`BL11` green. `BL12` still RED (Task 6 has not run).
- [ ] `BA1`–`BA3`, `BB*`, `BD2`, `BE1`, `BJ*`, `BK1`–`BK10` all still green and **unedited** — this
      feature must not have moved any existing answer.
- [ ] Run the FULL suite (`.claude/test-cmd`), not just this harness. A shared awk producer changed;
      `step5-brief.test.sh` and `plant-check.sh` sweep populations that never name this feature.

Budget: none (verification only, no files touched)

## Task 6 — CODE: the Step 5 consumer reads the token (R-01)

Owner: **coder**. Edit `staging/plugin/skills/concept-to-code/references/step5-implementation.md`
only, inside the `#### Diff budget and scope check — Step 5 checkpoints (ADR-0052)` block. Turns
`BL12` green.

- Add a bullet beside the existing `MALFORMED` one, in the same voice: **a fourth token exists**,
  `FILEBUDGET<TAB><tasks-label><TAB><file><TAB>lines=<expected>/<actual><TAB>margin=<N>`. State
  plainly that it means one declared file exceeded **its own** ceiling, that it **can fire with no
  `BUDGET` line present** — that is the case it exists for — and that an un-updated `grep '^BUDGET'`
  does not match it.
- Add a recording paragraph beside the existing `{task, malformed}` one: **record every
  `FILEBUDGET` line as its own entry in the same `budget_findings` array**, shape
  `{task, file, lines_expected, lines_actual}`. State that **no `files_expected` / `files_actual`
  keys are written**, because a per-file finding measures lines only and a zero there would read as
  a task that touched no files (ADR-0064 §D3, the same reasoning `{task, malformed}` used).
  Additive, no schema bump.
- Surface it at Gate 5 with the file name and both numbers, alongside the existing findings. It is
  advisory and never a failure signal, exactly like every other `budget_findings` entry — do not
  add a blocking clause.
- Do **not** edit `SKILL.md`'s Step 4.5 tracer-bullet verdict derivation. Its inputs stay `SCOPE`
  and `BUDGET` (ADR-0189 §D7 — a decision, not an omission).
- Do **not** create a seventh advisory array; the Gate 5 roll-up stays at six (ADR-0189 §A5).

Budget: `staging/plugin/skills/concept-to-code/references/step5-implementation.md` (~25 lines)

## Task 7 — CODE: bump `Z1`'s vacuity floor (R-01, R-02, R-03)

Owner: **coder**. Edit `staging/plugin/scripts/tests/diff-budget-scope.test.sh`, the `Z1` block
only.

- Count what the suite actually executes now, then set the floor a little below it. Measured before
  this plan: 55 executed, floor `>= 55`. With twelve `BL` assertions the expected count is 67, so
  the floor becomes `>= 66`.
- Keep the existing comment's framing intact: it is a **floor, not an exact count**, and it is a
  vacuity guard only. Rule 10 — a floor absorbs its own plant, so `Z1` is evidence that assertions
  have not silently vanished and evidence of nothing else. Do not convert it to an exact count and
  do not add a plant for it.

Budget: `staging/plugin/scripts/tests/diff-budget-scope.test.sh` (~5 lines)

## Task 8 — Verify: plants fire, the suite is green, the corpus behaves (R-01, R-02, R-03)

Owner: **tester**. Verification only, no source edits.

- [ ] `bash staging/plugin/scripts/tests/plant-check.sh` — every `BL` plant fires. A `NOFIRE` is
      evidence about the assertion, not a formality (rule 2): fix the assertion, never the plant.
- [ ] Full suite green via `.claude/test-cmd`.
- [ ] Re-run the §"Read this first" reproduction. It must now print a `FILEBUDGET` line naming
      `staging/sync-to-claude.sh` with `lines=1/60`, and still no `BUDGET` line.
- [ ] Sweep the whole live corpus for noise: for each of the 23 budget-declaring plans, run the real
      script over its declared tasks with a diff giving each declared file its declared count exactly.
      **Zero `FILEBUDGET` lines expected** — every file at its ceiling, none over. A finding here is
      an off-by-one at the boundary, which `BL2` should have caught.
- [ ] `bash staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh --spec SPEC.md --plan
      docs/superpowers/plans/2026-09-02-a-per-file-budget-ceiling-is-parsed-and.md --tests-root .`
      prints `COVERED` for R-01, R-02 and R-03. Remember R-01 is uninformative here (§"Assertion ids"):
      confirm R-02 and R-03 by reading the assertion headers, not the tool's verdict.

Budget: none (verification only, no files touched)

## Risks, dependencies and HITL gates

- **The awk out-parameter idiom must hold on CI's awk, not only this machine's.** Verified on
  `awk version 20200816` (BWK, macOS); CI is `ubuntu-latest`, whose `awk` is `mawk`. The idiom is
  POSIX (an unsupplied extra parameter may be used as an array) and works in mawk, gawk and BWK awk,
  but it is the one thing here that could pass locally and fail in CI. **Task 3's green
  `step5-brief.test.sh` on CI is the confirmation**; if it fails there and passes locally, this is
  the cause, not the logic.
- **`BK9`'s `sed` extraction is fragile against Task 2's edit.** The range
  `/^function parse_budget/,/^}$/` ends at the first column-0 `}`. Adding a second function whose
  name begins with `parse_budget`, or reformatting the closing brace, silently changes what `BK9`
  compares. `BK9a/b/c` staying green untouched is the check for this, which is why Task 3 exists as
  its own task rather than a line in Task 2.
- **`h16-direction-check.sh` gets more sensitive** — `budget_findings` grows a fourth entry shape
  and its `budget-overshoot` trigger counts entries at `>= 2`. Accepted and recorded (ADR-0189
  §Consequences); a per-file overrun genuinely is a budget overshoot. Do not filter it out.
- **False positives are the expensive failure**, not false negatives. This is an advisory reporter
  at every Step 5 checkpoint; one that fires spuriously stops being read. `BL5` is the assertion
  guarding the specific mechanism (§D3's ceiling/reportability asymmetry) that prevents the obvious
  false positive, and Task 8's corpus sweep is the empirical check.
- **Two declared corpus entries are globs and can never be attributed.** Known, stated in ADR-0189
  §D6, deliberately unguarded — the failure direction is a missing claim, not a wrong one. Do not
  add glob expansion; that is a separate decision with its own noise profile.
- **The `R-01` literal already lives in eight fixture heredocs in the target harness**, so
  `spec-coverage.sh` will report it `COVERED` regardless. Do not read that as evidence.
- **`docs/superpowers/` is markdownlint-ignored; `docs/architecture/` is not.** MD010 (hard tabs) is
  on — the ADR uses `<TAB>` placeholders and any further ADR edit must too.
- **HITL gates:** Gate 2 (this ADR and plan), the Step 5 checkpoints, Gate 5, and the commit/push
  gate at Step 7. No schema migration, no deletion, no external service, no deploy. `sync-to-claude.sh
  --apply` is the usual post-merge deploy step and is the human's call, not this plan's.

## Requirement coverage

| ID | Tasks |
| --- | --- |
| R-01 | 1, 4, 5, 6, 7, 8 |
| R-02 | 1, 2, 3, 5, 7, 8 |
| R-03 | 1, 4, 7, 8 |
