# Implementation plan — spec-coverage's test axis is tightened by SCOPE, not by assertion shape

- **Issue:** #312.
- **SPEC:** `docs/specs/312-spec-coverage-measures-citation-not-impl.spec.md` (R-01, R-02, R-03)
- **ADR:** `docs/architecture/ADR-0138-312-spec-coverage-scope-not-assertion-shape.md`
- **Stack:** Bash 3.2 (macOS-portable) + POSIX awk, the existing `staging/plugin/scripts/tests/*.test.sh`
  harness run by `.claude/test-cmd`, plants per ADR-0108. No runtime code, no new dependency, no
  schema version bump.

## Read this first — the plan deviates from the SPEC's stated mechanism

The corpus measurement (ADR-0138, Findings 1–3) refuted SPEC objective 2. Requiring a `R-NN` mention
to sit on an assertion line rather than a comment line changes the verdict of **0 of 199** ids in
this repository, and combined with scoping it would newly fail **49 of the 93** ids that are
genuinely covered by their own feature's tests — including 14 of 14 for issue #404, whose 45 in-scope
`R-NN` mentions are *all* comments, because the comment header is where this harness idiomatically
records which requirement a block of assertions answers.

**Nothing in this plan implements a comment-versus-assertion distinction. Do not add one.** The
tightening is scope: whose test file the mention is in. R-01 is satisfied in objective and deviated
from in mechanism, and that deviation is disclosed here, in the ADR, and at the call site in
`spec-coverage.sh`. If a task below seems to be missing the comment check, it is not an oversight.

## Files this plan touches

| Path | Action |
|---|---|
| `staging/plugin/scripts/tests/spec-coverage.test.sh` | modify — new `RS`/`RX` sections + plants (tester-owned) |
| `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv` | **create** — the frozen R-03 proof (tester-owned) |
| `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` | modify — scope filter, `UNSCOPED`, `no-test:`, `STALE-WAIVER` |
| `staging/plugin/skills/concept-to-code/SKILL.md` | modify — `_rc = 1` prose, `requirement_coverage.unscoped` |
| `staging/plugin/agents/architect.md` | modify — the `(no-test: …)` authoring instruction |
| `staging/plugin/skills/spec-from-issue/SKILL.md` | modify — same instruction, generator side |
| `staging/plugin/skills/interview-driver/SKILL.md` | modify — same instruction, generator side |

**Not touched, deliberately.**
`spec-id-predicate.awk` and `plan-task-predicate.awk` — the scope filter is a shell filter over an
already-derived population, not a fourth answer to "what is a plan task" or "what is a declaration"
(ADR-0138 §A8, CLAUDE.md rule 6).
`staging/sync-to-claude.sh` — `spec-coverage.sh` already carries a `PAIRS` entry;
`staging/plugin/scripts/tests/` is **not** a `PAIRS`-covered subtree except for four named legacy
files, so the new `.tsv` needs no entry. **Verify this, do not assume it** (Task 8).
`.github/workflows/docs-ci.yml` — `spec-coverage` is already in the `shell-tests` list. This plan
adds no new `*.test.sh` file, which is the whole reason the new assertions extend the existing
harness instead of getting their own. A new `*.test.sh` *would* have needed a manual append.
`spec-normalize-ids.sh` — no new mechanical repair ships (ADR-0138 §D4: deleting an author's prose
is not the same class of edit as adding a checkbox marker).
`RE3`/`RE4`'s `>= 30` floor — kept as a vacuity guard, permitted by CLAUDE.md rule 10 when the site
says so; Task 2 adds the one clause that says so. The id-less corpus grows with every feature, so an
exact count would break on each one.
Issues #313 (unrecognised-heading inertness) and #314 (literal-assertion-added) — out of scope, and
they must stay out.

## Ownership

`test-write-scope.sh` (ADR-0088) denies a **coder** any write under a path component named `tests/`.
Tasks 1, 2, 6 and 7 write under `staging/plugin/scripts/tests/` and must be dispatched to the
**tester**. Tasks 3, 4, 5 and 9 write the checker, the SKILL.md and the agent/generator instruction
text — **coder**. Task 8 is verification plus one SKILL.md edit — coder. Do not merge owners inside a
task.

## Batching and the expected reds (ADR-0101)

An assertion must not sit in the same batch as the task that greens it, even though that leaves an
intermediate checkpoint red. Every red below is **declared in advance**; anything else halts.

| Batch | Tasks | Agent | Expected checkpoint state |
|---|---|---|---|
| A | 1, 2 | tester | RED — `RS1`–`RS8`, `RX1`–`RX6` fail; the mechanisms do not exist yet |
| B | 3, 4 | coder | `RS1`–`RS6` green; `RS7`/`RS8` and `RX1`–`RX6` still RED |
| C | 5 | coder | `RX1`–`RX6` green |
| D | 6 | tester | the frozen baseline lands; `RS7`/`RS8` green against real data; full suite green |
| E | 7 | tester | plants declared; `plant-check.sh` green |
| F | 8, 9 | coder | full suite + plant registry green; consumer and instruction text landed |

## Assertion ids

`RS1`–`RS10` — the scope filter, the denominator guards, the `UNSCOPED` token, the frozen baseline.
`RX1`–`RX6` — the `no-test:` exemption, its reason floor, its stale-waiver reverse check.
Prefixes `RA RB RC RD RE RF RG RH RI RM RN RT` are already in use in this file. `RS` and `RX` are
free — **verify before writing**, because an id collision makes two assertions indistinguishable in
the harness output.

---

### Task 1 — The scope-filter and `UNSCOPED` assertions, written against the pre-fix checker (R-01, R-03)

Tester-owned. Extend `staging/plugin/scripts/tests/spec-coverage.test.sh` with section `RS`, using
the existing `run_scov` helper and `$TMP` fixture idiom already established in sections `RA`–`RE`.

- `RS1` — a fixture SPEC declaring `R-01`, a plan naming `alpha.test.sh`, and a `--tests-root` tree
  holding **both** `alpha.test.sh` (no `R-01`) and `beta.test.sh` (containing `R-01`): expect
  `UNSCOPED<TAB>R-01<TAB>1` on stdout and exit 1. This is the whole defect in one fixture — today it
  is `COVERED` and exit 0.
- `RS2` — the positive twin (CLAUDE.md rule 8): same tree, `R-01` moved into `alpha.test.sh`: expect
  `COVERED`, exit 0, no `UNSCOPED` line. Without `RS2`, `RS1` is satisfied by a checker that fails
  everything.
- `RS3` — the id absent from **every** file in the tree: expect `UNCOVERED<TAB>R-01<TAB>tests` and
  exit 1, **not** `UNSCOPED`. The two tokens must stay distinguishable; they carry different remedies.
- `RS4` — the plan names the test file by **full path**
  (`staging/plugin/scripts/tests/alpha.test.sh`), not bare basename: still in scope. The corpus uses
  both forms and the match must be on basename.
- `RS5` — the `.md` exclusion stays closed: a `--tests-root` containing `docs/specs/x.spec.md` whose
  own filename is named by the plan does not put that `.md` into scope, so a SPEC cannot cover
  itself. Assert on the absence of self-coverage, not on the presence of a filter.
- `RS6` — **the denominator guard** (CLAUDE.md rule 7): a plan naming no discovered test file at all,
  with a non-empty discovered population. Expect `SCOPE-EMPTY` on **stderr**, the unscoped fallback
  verdict on stdout, and **not** a wall of `UNSCOPED` lines. Zero candidates is a broken derivation,
  not a clean zero.

Each assertion states the expected exit code AND the expected stdout token separately — never a
combined `[ "$RC" -eq 1 ]` alone, which passes for the wrong reason.

Budget: `staging/plugin/scripts/tests/spec-coverage.test.sh` (~200 lines)

**Expected RED on arrival.** All six fail against the current checker. That is the evidence.

---

### Task 2 — The corpus-proof assertions and the derivation's own guards (R-02, R-03)

Tester-owned, same file, section `RS` continued. This is where R-03 stops being an argument.

- `RS7` — derive the (spec, plan) population by **issue-number prefix**: for each
  `$REPO/docs/specs/<N>-*.spec.md` that declares ids (reuse the existing `spec_declares_ids()` helper
  from section `RE`; do not write a second declaration parser), find
  `$REPO/docs/superpowers/plans/<date>-<N>-*.md`. For every (spec, id), compute the scoped verdict
  and compare it **exactly** against `spec-coverage-scope-baseline.tsv`.
- `RS8` — **both directions** (CLAUDE.md rule 8): a live verdict with no baseline row is RED, and a
  baseline row with no live counterpart is RED. Assert them as two separate outcomes with two
  separate messages, so the failure says which direction broke.
- `RS9` — **the denominator guard on the derivation** (CLAUDE.md rule 7): the pairing must resolve
  and yield `>= 15` pairs and `>= 100` ids. Measured 2026-08-14: **15 pairs, 117 ids**. State at the
  site that these are vacuity guards on the derivation, and that the per-item baseline compared in
  `RS7` is where a plant bites — a floor absorbs its own plant (CLAUDE.md rule 10, ADR-0124), and
  `RS7`'s exact comparison is what does not.
- **R-02, the silent-pass property.** Sections `RE3`/`RE4` already sweep every id-less SPEC asserting
  exit 0, empty stdout, empty stderr, with a count guard. Measured: 34 id-less SPECs against a floor
  of 30. Do **not** rewrite them. Add one clause to `RE4`'s message recording that the floor is
  deliberately a vacuity guard (CLAUDE.md rule 10's stated exception), and add `RS10`: a SPEC
  declaring zero ids invoked **with** `--tests-root` reaches neither the scope filter nor
  `SCOPE-EMPTY` — the new code must be unreachable on the silent path, asserted on all three streams.

Budget: `staging/plugin/scripts/tests/spec-coverage.test.sh` (~180 lines)

**Expected RED on arrival** for `RS7`/`RS8` — the baseline file does not exist until Task 6, and the
scope filter does not exist until Task 3. `RS9` and `RS10` are forward guards, green on arrival.

---

### Task 3 — The scope filter and the denominator guard in `spec-coverage.sh` (R-01, R-02, R-03)

Coder-owned. `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh`, between test discovery
and `grep_boundary_test()`.

- Build `TESTFILES_SCOPED` by **filtering `$TESTFILES`** — never by re-deriving the discovery
  predicate. A discovered file is in scope when its basename appears as a whole token anywhere in
  `$PLAN`. One derivation of "what is a test file", by construction (ADR-0138 §D1, CLAUDE.md rule 6);
  the `.md` exclusion is closed for free because `$TESTFILES` is already post-exclusion.
- Whole-token basename match, both sides anchored the way the id regex is. A basename contains `.`
  and `-`, so a bare `grep -F` on it also matches a longer name that contains it as a substring.
- `grep_boundary_test()` reads `$TESTFILES_SCOPED`. **The token regex is unchanged** — same
  `(^|[^A-Za-z0-9_])R-NN([^0-9]|$)`, same whole-file match. No comment/assertion distinction.
- The denominator guard: `$TESTFILES` non-empty and `$TESTFILES_SCOPED` empty ⇒ print the
  `SCOPE-EMPTY` sentence to stderr and fall back to `$TESTFILES` for this invocation. Fail-open and
  visible, matching the gate's existing `_rc = 2` philosophy (CLAUDE.md rule 4).
- Both new paths sit **behind** `[ -n "$TROOT" ]` and the `DECL_N -eq 0` early return, so the silent
  no-IDs path (ADR-0048 §D7/§D8) is untouched by construction.
- Bash 3.2: no assoc arrays, no `mapfile`, no process substitution, no `<<<`. The file's own header
  says so; keep it true.
- A comment block at the site recording the deviation from SPEC objective 2 and the measurement that
  forced it (53% of in-scope-covered ids are comment-only; #404 is 45 of 45). **Rule 12 applies to
  this comment**: any needle over this file matches prose that explains the mechanism, so a later
  assertion about the scope filter must anchor on a code line, never on the words describing it.

Budget: `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` (~70 lines)

---

### Task 4 — The `UNSCOPED` token, on the existing exit-1 channel (R-01, R-03)

Coder-owned, same file, in the per-id verdict loop.

- An id found in `$TESTFILES` but not in `$TESTFILES_SCOPED` emits
  `UNSCOPED<TAB>R-NN<TAB><scope-size>` and counts toward the exit-1 population.
- An id found in neither keeps emitting `UNCOVERED<TAB>R-NN<TAB>…tests`, byte-for-byte unchanged.
  Measured 0 of 117 ids fail this today and 0 will after — that is the zero-regression claim, and it
  is the reason the blocking channel is left alone.
- **No new exit code.** 0/1/2/3 stands. Update the file's contract header to describe `UNSCOPED`
  under exit 1 and `STALE-WAIVER` under exit 3 (Task 5).
- Update the stderr summary line to report the scoped and unscoped counts alongside the existing
  declared/covered/uncovered/discovered numbers.

Budget: `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` (~50 lines)

---

### Task 5 — `no-test:`, its reason floor, and the stale-waiver reverse check (R-03)

Coder-owned. This is the mechanism that keeps R-03 true for the 4 measured requirements that are not
test-assertable at all (`222 R-10`, `394 R-11`, `404 R-14`, `410 R-17`).

- Recognise `(no-test: <reason>)` in a success-criteria item's text, matched on a **flattened,
  undecorated, case-insensitive** copy so a backticked or bolded marker is the same marker
  (CLAUDE.md rule 3). Parse it where the item text is already being stripped — reuse
  `strip_emphasis()`/`strip_sep()`, do not add a third stripper.
- Effect: the id is exempt from the **test axis entirely**, both halves. **The plan axis still
  applies** — a non-testable requirement must still be cited by a plan task.
- Reason floor: `>= 20` characters after the colon. Shorter ⇒ `MALFORMED<TAB>R-NN`, exit 3.
- The reverse check (CLAUDE.md rule 9): an id carrying `no-test:` whose token **is** found in the
  scoped test set emits `STALE-WAIVER<TAB>R-NN`, exit 3, with a stderr sentence naming the remedy
  (delete the clause). **Not auto-repaired** — ADR-0072's self-repair is licensed only because adding
  a checkbox marker changes no content.

The matching assertions are written by the tester in Task 1's file *before* this task runs; they are
`RX1`–`RX6` and were declared RED in Batches A and B:
`RX1` marker recognised, id skipped on the test axis, exit 0 — `RX2` the same id still fails the
**plan** axis when no task cites it — `RX3` a bolded or backticked marker is recognised identically —
`RX4` a 5-character reason ⇒ `MALFORMED`, exit 3 — `RX5` a marker whose id **is** in the scoped tests
⇒ `STALE-WAIVER`, exit 3 — `RX6` the negative twin: no marker, same fixture, `UNSCOPED` as normal.

Budget: `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` (~90 lines)

---

### Task 6 — Freeze the baseline, with every `UNSCOPED` row classified (R-03)

Tester-owned. Create `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv`:

```
<spec-basename><TAB><R-NN><TAB>COVERED|UNSCOPED<TAB><class><TAB><reason>
```

117 rows over 15 SPECs. Measured 2026-08-14: **93 `COVERED`, 24 `UNSCOPED`.** Re-derive the numbers
from the files rather than copying them from here — this line is a snapshot of its moment
(CLAUDE.md rule 13), and Task 3's basename matching may differ from the measurement's at the edges.

The 24 `UNSCOPED` rows carry a `class` and a one-line reason. From the authoring-time review:

- **`not-test-assertable` (4):** `222 R-10` (a process step: the harness is run and `--apply` is run),
  `394 R-11` (the ADR records a fact), `404 R-14` (the ceiling decision is recorded in an ADR),
  `410 R-17` (a gap is filed as its own issue).
- **`testable` (20):** the rest — genuine drift the gate was silently passing. `176 R-13`;
  `222 R-01 R-02 R-03 R-04 R-07 R-08`; `287 R-01 R-02`; `289 R-01 R-02`; `292 R-01`;
  `365 R-08 R-09`; `394 R-08 R-09 R-12`; `404 R-04`; `410 R-08 R-14`.

**No archived SPEC is edited.** Retro-fitting `(no-test: …)` into four completed SPECs would correct
a historical record in place (CLAUDE.md rule 14, ADR-0034/0075/0078). The baseline is a new record
written forward; `no-test:` governs SPECs written from now on.

Add a header comment stating what regenerates this file and when — it must be regenerated whenever a
chain completes and adds a 16th pair, and a reader at 3am needs to learn that from the file itself.

Budget: `staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv` (~130 lines)

---

### Task 7 — Plants: every new assertion seen RED against a declared defect (R-01, R-03)

Tester-owned. CLAUDE.md rule 2 — an assertion nobody planted pins nothing. `# plant:` at **column 1**
(an indented one is silently skipped), format
`# plant: <assertion-id> | <staging-relative-path> | <needle> | <replacement>`, **exactly one match**
per needle.

Minimum set, one per distinct mechanism (a plant on one mechanism is not evidence for another,
ADR-0086):

- `RS1` — plant the scope-filter line so `grep_boundary_test()` reads the full population again.
  Proves `RS1` fires on the *scope*, not on the fixture layout.
- `RS6` — plant the `SCOPE-EMPTY` guard's condition. Proves the denominator guard is what reports.
- `RS7` — plant one row of the baseline `.tsv`. Proves the comparison is exact, not a count.
- `RX1` — plant the `no-test:` recognition. `RX4` — plant the reason-floor comparison.
- `RX5` — plant the stale-waiver reverse check. It is a *different mechanism* from `RX1`.

**CLAUDE.md rule 1 governs every needle here.** The needle must belong to the mechanism it asserts
about and to nothing else. Do **not** use `UNSCOPED`, `no-test`, `SCOPE-EMPTY` or `STALE-WAIVER` as
needles — each appears in the contract header, in the deviation comment Task 3 adds, in this plan and
in the ADR. Needle the **code line**. Inspect what each plant actually produced before believing what
it reports (CLAUDE.md rule 2, ADR-0090).

Budget: `staging/plugin/scripts/tests/spec-coverage.test.sh` (~40 lines)

---

### Task 8 — Wire the new token to a consumer, and verify the deployment surface (R-01)

Coder-owned. A token nothing reads is the ADR-0091 defect (CLAUDE.md rule 17). Every site below is
located by a distinctive anchor, never a line number (CLAUDE.md rule 12).

- `staging/plugin/skills/concept-to-code/SKILL.md`, the Requirement-ID coverage gate block: the
  `_rc = 1` sentence reading "`_out` names the ID and the missing half (`plan`, `tests`, or
  `plan,tests`)". Extend it to name `UNSCOPED` and its **distinct remedy** — cite the id in the test
  file this feature wrote, rather than write a new test — and `STALE-WAIVER` under `_rc = 3`.
- **Do not touch the checker/reporter distinction.** `spec-coverage.sh` stays a CHECKER branched on
  exit code; `weakening-scan.sh` a few lines above stays a REPORTER. The paragraph beginning
  "**This gate branches on the exit code.**" and the line "**Do not copy one block's branching into
  the other.**" are untouched (ADR-0047, ADR-0048).
- `step5-report.json`'s `requirement_coverage` gains an additive `unscoped` array beside
  `ids_declared`, `uncovered`, `status`. Additive per ADR-0076: absent means the gate did not write
  one, never "none found". No schema version bump. Two sites, both by anchor: the JSON block
  containing `"status": "pass | fail | no-ids | unavailable"`, and the orchestrator read-contract
  bullet beginning "`requirement_coverage.uncovered` non-empty → **failure signal**", which today
  keys the failure signal on `uncovered` alone.
- The Gate 5 advisory roll-up: the sentence claiming `weakening_findings` and
  `requirement_coverage.uncovered` "are structurally near-always empty by the time Gate 5 renders"
  stays **true as written** — it is about `uncovered`. `unscoped` is measured at 24 of 117 and will
  **not** be near-always empty, so decide explicitly whether it renders at Gate 5 and say which. Do
  not let it inherit `uncovered`'s sentence by adjacency. Note also that the roll-up enumerates
  "**this specific roll-up's six** advisory-schema arrays" — `unscoped` is a sub-field of
  `requirement_coverage`, not a seventh array, so that count is unaffected. Confirm that, do not
  assume it.
- **Verify, do not assume:** run `pairs-completeness.test.sh` and confirm the new `.tsv` under
  `staging/plugin/scripts/tests/` needs no `PAIRS` entry, and that `spec-coverage` is already in
  `docs-ci.yml`'s `shell-tests` list so no CI append is needed. If either turns out otherwise, that is
  a finding to disclose, not a silent fix.

Budget: `staging/plugin/skills/concept-to-code/SKILL.md` (~60 lines)

---

### Task 9 — The `(no-test: …)` authoring instruction, declared as an instruction (R-03)

Coder-owned. Three files, the same short block in each:
`staging/plugin/agents/architect.md`, `staging/plugin/skills/spec-from-issue/SKILL.md`,
`staging/plugin/skills/interview-driver/SKILL.md`.

Content: a requirement that is a documentation, process or deployment obligation — "the ADR records
X", "the issue is filed", "the harness is run" — carries `(no-test: <reason ≥ 20 chars>)` in its
success-criteria item. Measured at 4 of 117 ids, roughly one requirement in thirty.

**State plainly, in the text, that this is an instruction and not an enforcement** (CLAUDE.md rule 16,
ADR-0047/0088). Nothing forces an author to write the marker. What changes is the failure shape: an
unmarked documentation requirement now produces a halt naming a remedy instead of a silent false pass.
An assertion that merely pins the existence of this instruction is not evidence it is obeyed — if one
is added, say so at its site.

Check `RI1`/`RI3`/`RI4` in `spec-coverage.test.sh` for the existing generator-instruction assertions
and follow their shape; do not invent a fourth idiom.

Budget: `staging/plugin/agents/architect.md`, `staging/plugin/skills/spec-from-issue/SKILL.md`, `staging/plugin/skills/interview-driver/SKILL.md` (~60 lines)

---

## Verification before Gate 5

- `.claude/test-cmd` green, **whole suite, all 79 files** — not just `spec-coverage.test.sh`.
- `bash staging/plugin/scripts/tests/plant-check.sh` — every declared plant fired exactly once,
  `PC0`–`PC4` green.
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — green, confirming Task 8's
  deployment-surface finding.

**An observable contract changed here, and the call-sites were greped at design time.**
`spec-coverage.sh`'s stdout vocabulary gains `UNSCOPED` and `STALE-WAIVER`, and
`requirement_coverage` gains a field. Consumers found across the whole tree, named by anchor:

- `staging/plugin/skills/concept-to-code/SKILL.md` — nine sites mention `spec-coverage`: the
  helper-inventory bullet, the Step 5.0.5 resolution note, the tester-dispatch `--list` reference, the
  gate block itself (resolution, invocation fence, self-repair fence, exit-code prose, policy), the
  checker/reporter table row, the Gate 5 `--list` reference, and the ADR-0052 advisory roll-up. Read
  every one before editing any.
- `staging/plugin/scripts/tests/spec-coverage.test.sh` — sections `RF` (the SKILL.md gate block) and
  `RH` (the `step5-report.json` schema and read contract) assert on the old text. They will need
  updating, and **updating them is not weakening them**: state the reason in the batch report so the
  weakening scan's finding is answered rather than ignored (ADR-0073).
- `staging/plugin/skills/concept-to-code/scripts/spec-normalize-ids.sh` — shares the section
  predicate; confirm it is unaffected, do not edit it.

**Run the full suite, not just the changed module** — a contract change can break assertions in
unrelated modules that share it.

TEST-CMD CANDIDATE: for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done
TEST-CMD MODE: brownfield
