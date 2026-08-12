# Implementation plan — bind Phase P step 3 to the roadmap state and the run scope

- **Issue:** #399 (`chain-blocker`), Phase 12 Wave 3 row 1
- **SPEC:** `SPEC.md` (topic slug `399-bound-phase-p-step-3-to-roadmap-stat`)
- **ADR:** `docs/architecture/ADR-0134-399-phase-p-roadmap-state.md`
- **Stack:** Bash 3.2 (macOS-portable). No new runtime dependency.

## Files this plan touches

| Path | Action |
|---|---|
| `staging/plugin/skills/autopilot/scripts/prep-row-select.sh` | **create** (production helper) |
| `staging/plugin/scripts/tests/prep-row-select.test.sh` | **create** (harness) |
| `staging/plugin/skills/autopilot/SKILL.md` | modify — §1.5 Phase P step 3 |
| `staging/sync-to-claude.sh` | modify — one `PAIRS` entry |
| `.github/workflows/docs-ci.yml` | modify — one name in the `shell-tests` list |
| `CLAUDE.md`, `PROJECT.md` | modify — the record |

**Not touched, deliberately:** `staging/plugin/scripts/roadmap-from-issues.sh`,
`staging/plugin/scripts/tests/prep.test.sh`, `staging/plugin/skills/spec-from-issue/SKILL.md`,
`docs/specs/_issue-map.tsv`, the morning-report schema. See ADR-0134 §D11/§D13.

## Batching and the expected reds (ADR-0101)

Rule 1 outranks rule 2: an assertion must not sit in the same batch as the task it depends on, even
though that leaves an intermediate checkpoint red. The reds below are **declared in advance** and
are of ADR-0101's first class — a red in this batch's own newly written assertions, which a named
later task greens. Anything else halts.

| Batch | Tasks | Agent | Expected checkpoint state |
|---|---|---|---|
| A | 1, 2 | architect verification, then **tester** (writes under `tests/`) | RED: `PRS02`–`PRS19` — the helper does not exist yet. Greens at Task 3 |
| B | 3 | **coder** | GREEN for `PRS01`–`PRS19` |
| C | 4 | **tester** | RED: `PRS20`–`PRS21b` — the fence does not exist yet. Greens at Task 5 |
| D | 5 | **coder** | GREEN for the whole file |
| E | 6, 7, 8 | coder | GREEN, plus `plant-check.sh` all-fired |

`test-write-scope.sh` (ADR-0088) denies a coder a write under a `tests/` path component. Tasks 2, 4
and the `PRS22` addition in Task 6 write `staging/plugin/scripts/tests/prep-row-select.test.sh` and
must be dispatched to the **tester**; Tasks 3 and 5 write production files and must be dispatched to
the **coder**. Task 6 therefore has two sub-steps with two owners — do not merge them.

---

### Task 1 — Re-derive every measured figure before building on it (R-09)

Verification only. No file is written. Re-run each measurement from ADR-0134 §Context and confirm
or correct it in the ADR before Task 3 encodes any of it.

- [ ] `wc -l docs/specs/_issue-map.tsv` — expect **74**.
- [ ] Per map row, `test -f "docs/specs/<slug>.spec.md"` — expect **4** absent (`363-…`, `364-…`,
      `365-a-nightly-run-cannot-be-scoped-to-a`, `366-…`). **Not a `<num>-*` glob** — the glob is
      what produced the SPEC's wrong figure of 3.
- [ ] For those four, the row-shaped state in `PROJECT.md` — expect **all `- [x]`**.
- [ ] Per map row, `grep -cE '^[[:space:]]*- \[.\][[:space:]].*\(issue #<num>\)' PROJECT.md` —
      expect **exactly 1 for all 74**.
- [ ] Per map row, `grep -cF "(issue #<num>)" PROJECT.md` — expect **2 for `#365` and `#366`**
      (a roadmap row plus a `#### Wave N — … (issue #N)` heading), 1 for the rest. This is the
      measurement that decides §D3; if it no longer reproduces, say so before proceeding.
- [ ] State histogram over the 74 rows — expect `[ ]` **27**, `[x]` **47**, `[~]` **0**.
- [ ] `roadmap-from-issues.sh` still queries `--state open` and still writes `- [ ]` rows.
- [ ] `prep.test.sh`'s failure emitter still prints `FAIL ` with **no** colon.

Any figure that has moved is corrected in ADR-0134 §Context **in this task**, with the new value
and how it was obtained. A figure that moved and was silently carried is the defect R-09 exists to
prevent.

---

### Task 2 — RED: the harness and the helper-contract assertions (R-01, R-02, R-03, R-05, R-06, R-08)

Create `staging/plugin/scripts/tests/prep-row-select.test.sh`. Hermetic, offline, no `$HOME`
dependency, targets `staging/` directly, bash 3.2 clean. Header states the file's subject, the
ADR, and the two rules below.

**Mandatory mechanics:**

- `bad()` prints **`FAIL: <id>`** — with the colon. `plant-check.sh` attributes on `^FAIL: <id>`,
  and `prep.test.sh` is the counter-example (R-08).
- Assertion ids are **fixed width**: `PRS01`…`PRS19` here, `PRS20`+ later, floor `PRS99`.
  Attribution is a **prefix** match, so `PRS1` would be satisfied by `PRS10` failing. Do not
  introduce a variable-width id anywhere in this file.
- A fixture builder `mk_root <name>` that is **not** a counter incremented inside `$(...)` — that
  runs in a subshell and every call returns the same directory (ADR-0096's bug, met three times
  since). Copy `autopilot-run-scope.test.sh`'s shape.
- Every fixture writes its own `PROJECT.md` and `docs/specs/_issue-map.tsv`; nothing reads this
  repository's real ones except `PRS19` (below), which is explicit about it.

**Assertions (all RED until Task 3, except the forward guards named):**

- [ ] `PRS01` — the helper file exists and is bash-3.2 parseable (`bash -n`). *Forward guard after
      Task 3; RED now.*
- [ ] `PRS02` — a `[x]` row whose `<slug>.spec.md` is absent is **not** in stdout. **(R-01)** This
      is R-04's RED-evidence assertion; it carries a plant in Task 7.
- [ ] `PRS03` — a `[~] … (skipped)` row whose SPEC is absent is **not** selected. **(R-01)** Use
      `mark-roadmap-skipped.sh`'s real output shape: `- [~] <title>  (skipped)`, marker intact.
- [ ] `PRS04` — a `[ ]` row whose SPEC is absent **is** selected, and stdout carries the full
      `slug<TAB>num<TAB>title` row. **(R-03)**
- [ ] `PRS05` — a `[ ]` row whose `<slug>.spec.md` exists is not selected (coverage rule unchanged).
- [ ] `PRS06` — a freshly-generated shape (every row `- [ ]`, no SPEC files, 3 rows) selects **all
      three**. **(R-03)** This is the auto-design path; it must hold with no special case in the
      helper.
- [ ] `PRS07` — `--only 42` on a two-row fixture selects only the `#42` row. **(R-02)** Carries a
      plant in Task 7.
- [ ] `PRS08` — `--only <exact map slug>` selects that row. **(R-02)** The token is compared
      against the map's own `slug` field; assert with a slug whose text could not be re-derived
      from the roadmap title (e.g. a truncated one), so a re-derivation would fail this.
- [ ] `PRS09` — `--only 9999` (matching no map row) → **exit 0**, the row list is unaffected, and
      stderr names the token. Never an abort. **(R-02, ADR-0134 §D6)**
- [ ] `PRS10` — a map row whose issue number appears in no row-shaped line **is** selected and
      stderr reports `ORPHAN`. **(R-05)** Carries a plant in Task 7.
- [ ] `PRS11` — a row-shaped line whose marker is outside ` xX~` (e.g. `- [?]`) → selected, stderr
      reports `UNRECOGNISED-STATE`. **(R-05)** This assertion is what keeps §D3's branch reachable
      rather than dead.
- [ ] `PRS12` — two row-shaped lines for one issue with **different** markers (`[x]` then `[ ]`) →
      the first wins (not selected) and stderr reports `DUPLICATE`. Different markers on purpose:
      identical ones cannot distinguish "first wins" from "last wins".
- [ ] `PRS13` — map absent, and map present-but-unreadable → **exit 3**, stdout empty. **(R-06)**
- [ ] `PRS14` — `PROJECT.md` absent, and present-but-unreadable → **exit 3**, stdout empty. **(R-06)**
- [ ] `PRS15` — non-empty map, `PROJECT.md` containing no row-shaped line at all → **exit 3**, not
      exit 0 with empty stdout, and stderr says the predicate matched nothing. **(R-06)** Carries a
      plant in Task 7.
- [ ] `PRS16` — an **empty** map → exit **0**, empty stdout, guard not applied. The positive twin of
      `PRS15`: without it, a helper that always exits 3 satisfies `PRS15`.
- [ ] `PRS17` — bad invocation (no `--root`, and an unknown flag) → **exit 2**, distinct from 3.
- [ ] `PRS18` — on a fixture that triggers `ORPHAN` **and** selects a row, **stdout contains only
      row lines** (every line has exactly two tab characters) and every note is on stderr. Channel
      separation is contract, not convention (§D2).
- [ ] `PRS19` — the row-shaped predicate ignores a heading. Fixture reproduces the live shape
      measured in Task 1: a `- [x] … (issue #365)` row **and** a `#### Wave 1 — bound the run
      (issue #365)` heading in the same file → exactly one match, classified `[x]`, no `DUPLICATE`
      note. Assert the note's **absence** as well as the verdict, or a duplicate-then-first-wins
      implementation passes for the wrong reason.
- [ ] `PRS99` — assertion floor for this file (`>= 19` after this task; raised in Tasks 4 and 6).
      A floor, not an exact count — but **raise it in the same edit that adds assertions**, or it
      carries slack and an assertion can vanish while it stays green (ADR-0124).

**Do not write `PRS20`+ in this task.** They belong to Task 4's batch.

Budget: `staging/plugin/scripts/tests/prep-row-select.test.sh` (~430 lines)

---

### Task 3 — GREEN: `prep-row-select.sh` (R-01, R-02, R-03, R-05, R-06)

Create `staging/plugin/skills/autopilot/scripts/prep-row-select.sh`. Bash 3.2 clean: no associative
arrays, no `mapfile`, no process substitution, no here-strings.

**Header must state**, in this order: why it is a file and not a fence (awk field references are
positional-parameter tokens in a rendered document — ADR-0132); the SELECTOR contract with all
three exit codes; that an empty list at exit 0 is a normal result; that it prints no `CLEAN`
sentinel and must never grow one; that stdout is rows only and every note goes to stderr, and why
that diverges from the two sibling fences.

**Interface:** `prep-row-select.sh --root <project-root> [--only <csv>]`. Derives
`<root>/docs/specs/_issue-map.tsv`, `<root>/PROJECT.md`, `<root>/docs/specs/`. Unknown flag or
missing `--root` → exit 2.

**Algorithm, in this order:**

- [ ] Read the map. Unreadable → exit 3. Empty → exit 0 with empty stdout, guard skipped.
- [ ] Read `PROJECT.md`. Unreadable → exit 3.
- [ ] **Resolve state for every map row** — the guard's denominator is the full map, never the
      post-filter subset (§D5). One awk pass over `PROJECT.md` building an
      `issue<TAB>marker<TAB>count` index using the row-shaped predicate
      `^[[:space:]]*- \[.\][[:space:]].*\(issue #<num>\)`, capturing the marker character rather
      than restricting it.
- [ ] **Denominator guard:** map non-empty and zero rows matched → exit 3, naming the predicate.
- [ ] Filter each row: `--only` (token equals `num` or equals `slug`, both exact — **never**
      re-derive a slug from a title) → coverage (`docs/specs/<slug>.spec.md` exists) → state
      (`x`/`X`/`~` suppress; space continues; anything else selects + `UNRECOGNISED-STATE`; no match
      selects + `ORPHAN`; count > 1 uses the first + `DUPLICATE`).
- [ ] Report each `--only` token that matched no map row as `UNRESOLVED-TOKEN` on stderr, and
      **continue** — check 9 is the sole authority for aborting on it (§D6). Write that reason as a
      comment at the branch.
- [ ] Emit selected rows to stdout, one `slug<TAB>num<TAB>title` per line, in map order.
- [ ] Emit the `PREP-SELECT: map_rows=… matched=… selected=… covered=… completed=… skipped=…
      out_of_scope=… orphan=… unrecognised=… duplicate=…` summary to **stderr**.

**Plantability requirement:** each branch that Task 7 plants (`PRS02`, `PRS07`, `PRS10`, `PRS15`)
must be expressible as a **single-line, uniquely-matching** mutation. A replacement cannot contain a
newline, so a `printf …` / `exit N` pair collapsed onto one line makes the exit two more arguments
to `printf` and the plant is silently inert (ADR-0112). Write those four branches so one line
carries the decision.

Do not add a `--map`/`--roadmap` override pair "for testability" — fixtures build a root.

Budget: `staging/plugin/skills/autopilot/scripts/prep-row-select.sh` (~210 lines)

---

### Task 4 — RED: the Phase P step 3 fence assertions (R-02, R-06, R-07)

Extend `staging/plugin/scripts/tests/prep-row-select.test.sh` with the fence machinery and the
fence assertions. Copy `enumerate_fences` / `fence_body` / `extract_fence` / `subst_paths` /
`run_fence` / `out_of` from `autopilot-run-scope.test.sh` **verbatim**, including `fence_body`'s
`strip = (lw < ind) ? lw : ind` clause — this fence is indented inside a numbered list item and its
column-0 `FENCE_BASH` terminator extracts as `CE_BASH` without it (ADR-0133). This is a deliberate
copy, not a shared import (ADR-0086: three private `fence_body`s already answer this question
independently, and each file must fail independently). Say so in a comment.

The setup script **must bind `CLAUDE_PLUGIN_ROOT` to the staging copy.** An unbound
`CLAUDE_PLUGIN_ROOT` falls through to `$HOME/.claude` and can make an assertion pass from the
deployed copy while testing nothing — the exact defect found in `RJ14` (ADR-0132).

- [ ] `PRS20` — helper **not** deployed (setup points `CLAUDE_PLUGIN_ROOT` at an empty tree and
      `subst_paths` at a directory with no helper) → fence **exit 3**, output names
      `sync-to-claude.sh --apply`, and output contains no selected row. **(R-07)** Carries a plant
      in Task 7.
- [ ] `PRS20b` — the same case: the output states that Phase P **halts** and does not fall back.
      Match against a whitespace-flattened, decoration-stripped copy of the output — a prose
      assertion must not depend on where the line wraps or on backticks (ADR-0073/0076/0080/0098).
- [ ] `PRS21` — happy path with `_scope_only` empty → rc 0, one `PREP-SELECT-ROW:` line per selected
      row and none for a suppressed one. **(R-07)**
- [ ] `PRS21b` — `_scope_only=42` → rc 0, `PREP-SELECT-ROW:` for the `#42` row only. **(R-02)**
- [ ] `PRS21c` — helper present but returning 3 (fixture with an unreadable `PROJECT.md`) → fence
      **exit 3**, and the message says the selection did not run. **(R-06)**
- [ ] `PRS21d` — helper returning 2 (bad invocation forced by a fixture) → fence **exit 2**,
      distinct from 3. Without this, one code stands for two states and the vocabulary §D8 declares
      is unasserted.
- [ ] Raise `PRS99`'s floor in the same edit.

Budget: `staging/plugin/scripts/tests/prep-row-select.test.sh` (~170 lines)

---

### Task 5 — GREEN: rewrite Phase P step 3 in `autopilot/SKILL.md` (R-02, R-07)

Rewrite step 3 of §1.5. Prose first, then the fence, then the instruction half.

**Prose must say:**

- What the step now reads: the map, the row's state in `PROJECT.md`, and Phase S's resolved
  `--only`.
- That **ADR-0129 §D7's exclusion does not extend to this step**, and why: §D7 keeps Phase S away
  from `PROJECT.md` because in auto-design mode the roadmap does not exist yet at Phase S time;
  step 3 runs after step 2 has generated it, so `PROJECT.md` exists on every path. Written here so
  a later reader does not read §D7 as covering this step (**R-02**).
- That `--features` does **not** bound this step, and why (one number, two questions — issue #242).
- That a row suppressed as completed or out of scope is counted in **neither**
  `features_generated` nor `features_skipped_thin`; the counts are on the helper's `PREP-SELECT:`
  stderr line (§D11).

**The fence** — `<!-- fence-contract: autopilot-prep-row-select -->`, and it must carry:

- [ ] The ADR-0133 §D1 wrapper: `export _root _scope_only CLAUDE_PLUGIN_ROOT`, then
      `bash <<'FENCE_BASH'`, body, then `FENCE_BASH` **at column 0** even though the fence is
      indented inside a numbered list item. The comment above it says the terminator's column is not
      a formatting slip.
- [ ] **No positional-parameter token anywhere in the body** (`$1`…`$9`, `$@`, `$#`, or an awk
      field reference) — ADR-0132, guarded by `skill-fence-positional-tokens.test.sh`.
- [ ] Two-tier helper resolution (`CLAUDE_PLUGIN_ROOT` first, `$HOME/.claude` second), and on
      failure a **halt** carrying, on one uniquely-matching line, the exit that Task 7 plants:
      `exit 3   # DID-NOT-RUN: never fall back to generating every uncovered row`. The message names
      `bash <repo>/staging/sync-to-claude.sh --apply` and states that a fallback would restore the
      unbounded behaviour this step removes.
- [ ] A branch on `[ -n "$_scope_only" ]` rather than always passing `--only "$_scope_only"`,
      mirroring `autopilot-scope-resolve` and citing its reason: the two readings of "empty" are the
      difference between an unscoped run and a run that does nothing.
- [ ] Exit-code mapping: helper 0 → continue; helper 2 → fence exit 2; anything else → fence exit 3.
      A comment stating that Phase S's and Phase M's fences use different codes for the same state
      and that **the three must not be reconciled** (ADR-0132 §D4).
- [ ] Output: `PREP-SELECT-ROW: <slug>\t<num>\t<title>` per selected row, or one line saying zero
      rows were selected and that this is a normal result.

**The instruction half**, immediately after the fence, and labelled as such:

- [ ] "For each `PREP-SELECT-ROW:` line, invoke `Skill(skill="spec-from-issue", args="<issue#>
      --slug <slug>")`. A thin or vague issue is SKIPPED (`[~]` in `PROJECT.md` plus a
      `needs-human` note), never fabricated." — unchanged behaviour.
- [ ] One sentence saying plainly that **this loop is an instruction, not an enforcement**: nothing
      stops a model from generating for a row the fence did not print. What the fence changes is
      that the list is computed by code with a stated contract, so a divergence is visible on
      screen (§D10).

Budget: `staging/plugin/skills/autopilot/SKILL.md` (~100 lines)

---

### Task 6 — Deploy wiring: `PAIRS` entry and the CI name (R-08)

Two sub-steps, two owners — see the batching table.

- [ ] **(coder)** Add to `staging/sync-to-claude.sh` `PAIRS`, immediately after the
      `scope-args-parse.sh` entry:
      `plugin/skills/autopilot/scripts/prep-row-select.sh|skills/autopilot/scripts/prep-row-select.sh`.
      Before adding it, confirm the file has no entry at a different staging path — a second entry
      is a second source of truth. No `chmod` line: the fence invokes it as `bash "$_prs"`, exactly
      as Phase S invokes `scope-args-parse.sh`.
- [ ] **(coder)** Append `prep-row-select` to the `for t in …` list in
      `.github/workflows/docs-ci.yml`'s `shell-tests` job. That job **enumerates** and does not
      glob; `.claude/test-cmd` globs and picks the file up with no edit. Four harnesses have drifted
      out of that list once already (ADR-0113).
- [ ] **(tester)** Add `PRS22` to the harness: the `PAIRS` entry exists in
      `staging/sync-to-claude.sh`, matched on the **full `src|dst` pair**, not on the filename —
      `pairs-completeness.test.sh` is structurally blind to a skill-private `scripts/` file
      (ADR-0043), so this is the only guard for it. Raise `PRS99`.
- [ ] **Do not** add an assertion that the harness is named in `docs-ci.yml`.
      `pairs-completeness.test.sh` `CI1` already derives every staged harness and requires exactly
      that; a second one would be two answers to one question, and it would fail in every
      `plant-check.sh` sandbox because `.github/` is in neither copied tree (ADR-0122). Verify
      instead by running `pairs-completeness.test.sh` **before** the append and confirming `CI1`
      goes red naming `prep-row-select` — that is the evidence the append was needed.

Budget: `staging/sync-to-claude.sh`, `.github/workflows/docs-ci.yml`,
`staging/plugin/scripts/tests/prep-row-select.test.sh` (~25 lines)

---

### Task 7 — Declare the plants and validate every one of them (R-04)

Add `# plant:` declarations at **column 1** in the harness — an indented declaration is silently
skipped (`PC4`). Syntax: `# plant: <id> | <path-relative-to-staging> | <needle> | <replacement>`.
A ` | ` sequence cannot appear inside a field; the needle's words are joined on `\s+`, so a wrapped
clause still matches; **exactly one match is required**.

- [ ] `PRS02` — target `plugin/skills/autopilot/scripts/prep-row-select.sh`; mutate the single line
      that suppresses a `x|X|~` row so it selects instead. **This is R-04's required RED evidence:
      a fixture map containing a completed row with no SPEC, an assertion that goes RED, and a
      declared plant that attributes.**
- [ ] `PRS07` — mutate the `--only` membership test so a non-member passes.
- [ ] `PRS10` — mutate the orphan branch so an unmatched row is dropped instead of selected.
- [ ] `PRS15` — mutate the denominator guard so zero matches exits 0.
- [ ] `PRS20` — target `plugin/skills/autopilot/SKILL.md`; needle is the single distinctive line
      `exit 3   # DID-NOT-RUN: never fall back to generating every uncovered row`, replacement
      `exit 0`. A multi-line replacement is impossible here — the plain `exit 3` string appears
      elsewhere in this file, which is why Task 5 puts the comment on the same line.
- [ ] Run `bash staging/plugin/scripts/tests/plant-check.sh` and confirm all five report **fired**.
- [ ] **For each plant, inspect what the mutation actually produced before believing the verdict**
      (ADR-0090). A plant that reports "fired" from a mutation that was not the one it describes is
      worth nothing; a plant that does not fire is evidence about the assertion, not a step to get
      past.
- [ ] If a plant does not fire, the fix is in the **assertion**, not in the plant — unless the plant
      itself is malformed, in which case say which of the two it was.

Budget: `staging/plugin/scripts/tests/prep-row-select.test.sh` (~15 lines)

---

### Task 8 — Full suite, and the record (R-09)

- [ ] Run the **full** suite, not just the new file:
      `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`. This change
      adds a fence contract and a harness, so `fence-contract-coverage.test.sh` (F3/F4/F7/F9/F10,
      WS0–WS9), `skill-fence-positional-tokens.test.sh` and `pairs-completeness.test.sh`
      (CI0–CI2) are all in the blast radius and none of them is the new file.
- [ ] Run `plant-check.sh` once more over the whole registry, after the suite is green.
- [ ] Confirm ADR-0134 §Context carries Task 1's figures, with any correction made there rather
      than left in a commit message.
- [ ] Add a `## Decisions from the Phase P roadmap-state chain (ADR-0134)` section to `CLAUDE.md`,
      in the house style: what was measured, what the decision is, and the known consequences —
      including the two disclosed-not-fixed defects (the coverage-predicate divergence with
      `project-conductor`'s `<num>-*` glob, and check 9's file-wide matcher that makes
      `--only 365`/`--only 366` abort this repository's own launches today).
- [ ] Mark the Phase 12 Wave 3 row *"Phase P step 3 honours the resolved scope"* as **done — #399,
      ADR-0134** in `PROJECT.md`. Do not touch any other row.
- [ ] File the two follow-up issues named in ADR-0134 §D13. If issue creation is not available in
      this session, list them in the final report with title and body so the operator can file them
      — do not leave them only in the ADR.

Budget: `CLAUDE.md`, `PROJECT.md`, `docs/architecture/ADR-0134-399-phase-p-roadmap-state.md`
(~50 lines)

---

## Risks

- **Phase P is worse than inert until sync.** The fence halts on an unresolved helper by design, so
  between merge and `bash staging/sync-to-claude.sh --apply` every auto-design run stops at step 3.
  Named in ADR-0134 §Consequences; it will read as a regression the first time.
- **The generating half is fixture-only on this repository.** All 74 rows are covered or completed,
  so a green run proves suppression and not generation.
- **`fence_body`'s dedent clause is load-bearing and easy to omit** when copying the machinery: the
  new fence is indented inside a numbered list item, and without the clause the column-0 terminator
  extracts as `CE_BASH` and the assertions test a corrupted body.
- **Task 5 edits the file `skill-fence-positional-tokens.test.sh` guards.** A `$1` written into the
  new fence out of habit fails that harness, not this one.

TEST-CMD CANDIDATE: for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done
TEST-CMD MODE: brownfield
