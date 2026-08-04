# Implementation plan — the value-domain guard covers all three additive fields

- **Issue:** #292
- **ADR:** `docs/architecture/ADR-0125-292-value-domain-guard-two-fields.md`
- **SPEC:** `SPEC.md` (topic slug `the-value-domain-guard-covers-step5-mode`)
- **Date:** 2026-08-04
- **Requirements:** R-01, R-02, R-03 (all three cited below; the SPEC declares no other ID)

TEST-CMD CANDIDATE: none
TEST-CMD MODE: brownfield

---

## What was measured before this plan (do not re-litigate, do re-run)

Every number here was produced by running, not by reading. Five SPEC premises did not reproduce.
Full detail in the ADR's Context section.

- **Corpus is 49 manifests, harness is 73 files** — not the 41 and 68 the SPEC states.
- **Neither field has a phantom.** Written vs documented is clean in both directions on both fields
  today. This is a guard, not a fix (ADR-0107's shape). Do not go hunting for an `agent_fallback`
  here; there is not one.

  | field | written | documented | corpus |
  |---|---|---|---|
  | `hook_verified` | `true`, `false` | **"a boolean"** (a TYPE) | 45 `false`, 4 `true`, 0 absent |
  | `step5_review_mode` | `none`, `checkpoint` | `none`, `checkpoint` | 31 `none`, **0 `checkpoint`**, 18 absent |

- **`hook_verified`'s documented set derives to the single token `a`.** ADR-0092's derivation run
  against `hook_verified is a boolean` yields `a`, count 1. There is no enumeration to compare.
- **R-02 is NOT satisfied by the existing flatten.** With the sentence re-flowed so a value list is
  split inside itself (`… is none|` / newline / `# checkpoint.`), the current derivation returns
  **`none|`** — the set `{none}`, `checkpoint` silently dropped. Verified. `sed
  's/[[:space:]]*|[[:space:]]*/|/g'` after the comment-marker strip fixes it; verified against three
  wrap shapes (none, after `is`, inside the list) for all three fields.
- **The shared idiom fails on `hook_verified`.** `grep -rhoE 'hook_verified: [a-z_]+'` over
  `skills/*/SKILL.md` + `skills/*/scripts/*.sh` returns
  `{false, true, field, manifest, the, value}` — four English words out of operator error messages
  in `autopilot-build/SKILL.md:257,272,273,274` and `nightly-autopilot/SKILL.md:235`. The
  `hook_verified=<word>` variant adds `unchanged` (8 hits), `hook-verify-workflow.sh`'s RECOMMEND
  token meaning *do not write*.
- **The working `hook_verified` extractor** is `manifest-set-flag.sh … hook_verified (true|false)`
  call sites ∪ `manifest-init.sh`'s `^echo "hook_verified: false"` default → exactly `{false, true}`.
- **`step5_review_mode`'s colon idiom is clean** — 7 matches, `{none, checkpoint}`. `checkpoint`'s
  only real producer is the `sed` flip **inside a comment** at `manifest-init.sh:134`; SKILL.md:769
  and 2059 also name it in prose, so prose alone would sustain it.
- **`manifest-set-flag.sh`'s `true|false` validation is asserted NOWHERE** across all 73 harness
  files. **Invariant 14's behaviour** is covered (`step5-checkpoint-review.test.sh` B1/B2/B3); its
  **agreement with the documented domain** is not.
- **`hook_verified: yes` reads `PRESENT|True`** (YAML 1.1). It passes `R1` and must fail `WH5` —
  that is what makes the literal-axis sweep non-redundant with the parsed-axis one.
- **Baseline:** `manifest-field-state.test.sh` = `PASS=34 FAIL=0`, `Z1` floor 30 with 33 counted
  (**3 units of slack**). **Zero** declared plants in this file. Registry-wide: 171 declarations.
- **CI is already wired** — `manifest-field-state` is in `docs-ci.yml`'s `shell-tests` list (the
  list uses bare names, no `.test.sh` suffix). No workflow edit is needed.

### Standing rules for every task below

- **Plants at column 1.** `# plant: <id> | <staging-relative-path> | <needle> | <replacement>`.
  An indented declaration is silently skipped (`PC4`). The separator is literally ` | `
  (space-pipe-space, `awk -F' \\| '`) and cannot appear inside a field — **a bare `true|false` with
  no spaces is safe**, a shell pipeline in a needle is not (ADR-0114 truncated three plants this
  way). Needle words are joined on `\s+`; it must match **exactly one** site; the replacement
  cannot contain a newline (ADR-0112).
- **A plant that does not fire is a defect in the plant or in the assertion.** Inspect what the
  plant actually produced before believing what it reports (ADR-0090).
- **Prefix collisions (#355 is open).** `plant-check.sh` decides a plant fired with
  `grep -q "^FAIL: $aid"` against the output of **that one test file**, so collisions are
  within-file. This file already contains `S1`…`S12` and `V0`/`V0b`. **No new id may be a prefix of
  another id in this file, and none may have one as a prefix.** `WH1`–`WH6`, `WR1`–`WR7`, `WN1`,
  `WW1` satisfy this: verify with `grep -oE '^(ok|bad) "[A-Za-z0-9]+' ` before declaring plants, and
  do not add a `b`/`c` suffix to any new id.
- **Rule 12.** A needle must belong to the mechanism, never to the prose explaining it. This file,
  the helper header and both call-site SKILL.md files all legitimately *name* these fields and
  values while explaining them.
- **`grep -c … || echo 0` yields `0\n0`.** Use `|| true`.
- **Prose assertions** match a flattened, undecorated, case-insensitive copy.
- **Bash 3.2 / BSD tools.** No associative arrays, no `${var^^}`, no GNU-only `sed a\`, no `grep -P`,
  no empty ERE alternative `(a|)` (BSD grep rejects it and the sweep reads clean — ADR-0093).
- **Every new assertion calls exactly one of `ok`/`bad` on every path**, count guards included, so
  `Z1`'s total is deterministic (required by Task 9).

### Batch boundaries (ADR-0101)

Rule 1 outranks rule 2: **an assertion must not share a batch with the task it depends on**, because
a RED that fires for the wrong reason is not evidence. Task 1 is RED by construction and Task 2 and
Task 3 are what green it, so **Task 1 must close its batch**. Tasks 2–3 may batch together. Task 8
(plants) must come after every assertion exists.

---

### Task 1 — RED: section `W` skeleton, the two count guards, and the wrap fixture (R-01, R-02)

Add section `W` to `staging/plugin/scripts/tests/manifest-field-state.test.sh`, after section `V`
and before `Z1`. Write only what must be RED now.

- [ ] Section header comment stating: what this covers (the two fields ADR-0092's consequence
      bullet names), that **neither field has a phantom today so this is a guard and not a fix**,
      and that the written-set extractors are per-field **on measurement** — quote the four phantom
      words `field`, `manifest`, `the`, `value` and where they come from, and `unchanged` from the
      `=` variant. Mark it **derived-guard pattern instance 12 (ADR-0086), waiver: none**.
- [ ] `WH2` — count guard on `hook_verified`'s documented set, `>= 2`. **RED now**: the header says
      "a boolean" and the derivation yields the single token `a`. The failure message must name
      **both** causes: a sentence wrapping across comment lines, and a header stating a *type* or a
      capitalised form (`True|False` cannot match `[a-z_|]+` at all).
- [ ] `WR2` — count guard on `step5_review_mode`'s documented set, `>= 2`. Green now; a forward
      guard, labelled as such.
- [ ] `WW1` — R-02's direct evidence. Copy the helper to `$TMP`, re-flow its domain sentence with
      `sed` so **a value list is split inside itself** (`… is none|` newline `# checkpoint.`), run
      the documented-set derivation over the copy for `step5_review_mode`, require the full set
      `{none, checkpoint}` back. **RED now** — the current flatten returns `{none}`.
- Budget: `staging/plugin/scripts/tests/manifest-field-state.test.sh` (~70 lines)

**Checkpoint:** run the file. `WH2` and `WW1` must be the only new failures, and `WW1`'s failure
must report `none` alone — if it reports something else, the fixture is wrong, not the derivation.
Record the observed output; it is the RED evidence for Tasks 2 and 3.

---

### Task 2 — GREEN: enumerate `hook_verified`'s documented domain (R-01)

- [ ] `staging/plugin/skills/concept-to-code/scripts/manifest-field-state.sh` — in the domain
      sentence, replace `hook_verified is a boolean` with `hook_verified is true|false`. Leave
      `step5_mode` and `step5_review_mode` byte-unchanged.
- [ ] Immediately after that sentence, add the **axis note**: these are the literals a producer
      writes; the helper's own stdout renders a parsed YAML boolean as `True`/`False` (pinned by
      `S1`/`S2`) and a quoted `"true"` as `true` (pinned by `S11`), a different axis; **do not
      "fix" this to `True|False`**. Mention that `manifest-set-flag.sh` structurally refuses
      anything else, and that YAML 1.1's `yes`/`no`/`on`/`off` parse as booleans but are written by
      nothing — measured `PRESENT|True`.
- [ ] `CLAUDE.md` — correct the same phrase in the ADR-0076 summary (search for
      `` `hook_verified` is a `` in the §ADR-0076 block). Live text, corrected in place, ADR-0092
      §D1's precedent. **Do not** edit `docs/architecture/ADR-0076-…`'s body (ADR-0034).
- Budget: `staging/plugin/skills/concept-to-code/scripts/manifest-field-state.sh`, `CLAUDE.md`
      (~10 lines)

**Checkpoint:** `WH2` goes green. `WW1` must still be RED — if it went green here, the fixture is
not splitting the list and Task 3 will pass for the wrong reason.

---

### Task 3 — GREEN: one documented-set derivation, wrap-surviving, shared with `V0b` (R-01, R-02)

- [ ] Add a local function `_vd_doc_set <field>` (or `<file> <field>` — `WW1` and `WN1` need to run
      it against a `$TMP` copy) to the test file. Pipeline: read → `tr '\n' ' '` → `tr -s ' '` →
      `sed 's/# //g'` → **`sed 's/[[:space:]]*|[[:space:]]*/|/g'`** → `grep -oE "<field> is
      [a-z_|]+"` → `head -1` → strip prefix → `tr '|' '\n'` → drop blanks → `sort -u`. Comment at
      the site: why the collapse exists (a re-flow splitting a list yields `{none}` — measured) and
      why the regex stays anchored on `<field> is ` (so `PRESENT|<value>` and `${st%%|*}` elsewhere
      in the header cannot be picked up).
- [ ] Refactor `V_DOC` to call it. **`V0b`'s id and its `ok`-line text stay byte-identical**;
      extend only its *failure* message with the second cause (a list split across the wrap).
- [ ] Wire `WH2`/`WR2`/`WW1` onto it.
- Budget: `staging/plugin/scripts/tests/manifest-field-state.test.sh` (~30 lines)

**Checkpoint:** `WW1`, `WH2`, `WR2`, `V0b` all green; `V0`, `V1`–`V4` unchanged. Diff the `PASS:`
lines against Task 1's recorded output to confirm no existing `ok` text moved.

---

### Task 4 — `hook_verified`'s written set, the shared comparison, and both directions (R-01)

- [ ] Add a local function `_vd_diff <listA> <listB>` returning the members of A absent from B
      (`grep -qxF`). It **computes and never reports** — each call site formats its own message,
      because `V1`'s and `V2`'s failure texts differ deliberately and are anchors.
- [ ] Refactor `V1` and `V2` onto it, **ids and `ok`-line text byte-identical**.
- [ ] `WH_WRITTEN` — `manifest-set-flag.sh … hook_verified (true|false)` call sites over
      `skills/*/SKILL.md` and `skills/*/scripts/*.sh`, ∪ `manifest-init.sh`'s
      `^echo "hook_verified: (true|false)"` default. Comment at the site: **why the colon idiom is
      not used here**, naming the four phantom words and the two files they come from; and that
      the extractor couples to the literal helper name, so a rename collapses the set to `{false}`
      and `WH1` is what says so.
- [ ] `WH1` — count guard on that set, `>= 2`, message naming the coupling.
- [ ] `WH3` — forward: every written value is documented.
- [ ] `WH4` — reverse: the documented domain names no value no producer writes. This is the
      direction that catches #240's shape.
- Budget: `staging/plugin/scripts/tests/manifest-field-state.test.sh` (~55 lines)

---

### Task 5 — `step5_review_mode`'s written set and both directions (R-01)

- [ ] `WR_WRITTEN` — `grep -rhoE 'step5_review_mode: [a-z_]+'` over `skills/*/SKILL.md` and
      `skills/*/scripts/*.sh`. Comment at the site: this idiom is clean for **this** field (7
      matches, measured) and is deliberately **not** shared with `hook_verified`; and the extractor
      is permissive, so `SKILL.md` prose alone would sustain `checkpoint` if its producer vanished —
      which is what `WR6` exists for.
- [ ] `WR1` — count guard, `>= 2`.
- [ ] `WR3` — forward.
- [ ] `WR4` — reverse.
- Budget: `staging/plugin/scripts/tests/manifest-field-state.test.sh` (~40 lines)

---

### Task 6 — Corpus sweeps on the literal axis, count-guarded (R-01)

- [ ] `WH5` — for every `docs/manifests/*.manifest.yml`, read the **literal** with
      `grep -m1 '^hook_verified:'` and require it in `WH_WRITTEN`. Denominator guard `>= 30`
      (49 today) with its own `bad` branch (ADR-0085). Comment: this is **not** redundant with
      `R1` — `R1` sweeps the parsed-state axis, and `hook_verified: yes` **passes `R1`** (YAML 1.1
      parses it to `True`, measured) while failing here.
- [ ] `WR5` — same on `step5_review_mode`, denominator guard `>= 20` (31 today). Comment: 0
      manifests carry `checkpoint`, so this sweep has never exercised that value and cannot until
      the opt-in is taken; that is not a phantom, because the reverse check compares against
      **producers**, never against the corpus.
- Budget: `staging/plugin/scripts/tests/manifest-field-state.test.sh` (~35 lines)

---

### Task 7 — The enforcers, and the no-waiver check (R-01, R-03)

- [ ] `WH6` — run `manifest-set-flag.sh` on a `$TMP` manifest with a value that is neither `true`
      nor `false`; require non-zero exit **and** a message naming the constraint. Comment: this is
      what lets `WH_WRITTEN` read only two call-site shapes without going blind — nothing else can
      write the field. Covered by nothing in 73 harness files before this.
- [ ] `WR6` — `manifest-init.sh` still carries the `sed` flip line that is `checkpoint`'s only real
      producer. Needle must be the **command itself**, not the field name (rule 12: SKILL.md and the
      header both name `step5_review_mode: checkpoint` in prose).
- [ ] `WR7` — derive invariant 14's alternation from `manifest-validate.sh`
      (`step5_review_mode: (none|checkpoint)`), count-guard it `>= 2`, and require **set equality**
      with the documented set. Comment: `step5-checkpoint-review.test.sh` B1/B2/B3 cover invariant
      14's *behaviour*; this covers enforcer-versus-document *agreement*, a different question and
      #240's shape with a different pair of files.
- [ ] `WN1` — **R-03, behavioural.** Copy the helper to `$TMP`, insert a
      `# value-domain-exempt: <phantom>` line into its header, add that phantom to the documented
      sentence, run `_vd_doc_set` + `_vd_diff` against a written set that omits it, and require the
      mismatch **still reported**. Comment: ADR-0092 recorded "no waiver" as prose; a prose claim
      about an absent mechanism is unplantable and rule-12 exposed, so it is asserted by behaviour
      instead. `_vd_diff` takes two lists and nothing else, by construction.
- Budget: `staging/plugin/scripts/tests/manifest-field-state.test.sh` (~55 lines)

---

### Task 8 — Declare and run all 15 plants (R-01, R-02, R-03)

One `# plant:` declaration beside each new assertion, column 1. Suggested targets — verify each
needle matches **exactly one** site in its target before running:

- [ ] `WH1` → the test file, mutate the `WH_WRITTEN` extractor so it matches nothing.
- [ ] `WH2` → the helper, revert the enumeration to the type name.
- [ ] `WH3` → the helper, drop one written value from the documented list.
- [ ] `WH4` → the helper, add a value no producer writes to the documented list.
- [ ] `WH5` → `../docs/manifests/<one>.manifest.yml`, change `hook_verified: false` to a literal no
      producer writes (the `../docs/` prefix is the one permitted escape, ADR-0116).
- [ ] `WH6` → `manifest-set-flag.sh`, widen the validator.
- [ ] `WR1` → the test file, break the `WR_WRITTEN` extractor.
- [ ] `WR2` → the helper, remove `step5_review_mode`'s documented list.
- [ ] `WR3` / `WR4` → the helper, drop / add a value on that field's list.
- [ ] `WR5` → `../docs/manifests/<one>.manifest.yml`, change `step5_review_mode: none`.
- [ ] `WR6` → `manifest-init.sh`, alter the `sed` flip line.
- [ ] `WR7` → `manifest-validate.sh`, widen invariant 14's alternation.
- [ ] `WW1` → the test file, remove the pipe-collapse `sed` clause from `_vd_doc_set`.
- [ ] `WN1` → the test file, add a marker-honouring skip to `_vd_doc_set` or `_vd_diff`.
- [ ] Run `bash staging/plugin/scripts/tests/plant-check.sh`. All 15 must fire. **For each, inspect
      what the plant actually produced** — a plant that fires from a mutation other than the one it
      describes is not evidence (ADR-0090, ADR-0114). Any plant that does not fire is a defect in
      the plant *or* in the assertion; fix whichever, do not delete the plant.
- Budget: `staging/plugin/scripts/tests/manifest-field-state.test.sh` (~20 lines)

---

### Task 9 — `Z1`'s floor, full harness, roadmap (R-01)

- [ ] Raise `Z1`'s floor to the **exact executed total** from a real run (34 + 15 = 49 expected;
      re-derive, do not trust this number). Comment above it: a floor with slack absorbs its own
      plant, and three units of slack existed here before fifteen assertions were added to hide
      behind them (ADR-0124). Extend the failure message so it still names what a shortfall means.
- [ ] Confirm every new assertion executes exactly one of `ok`/`bad` on every path, count-guard
      branches included, so the total is deterministic.
- [ ] Run the full suite:
      `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`, then
      `bash staging/plugin/scripts/tests/plant-check.sh`. `step5-checkpoint-review.test.sh` and
      `concept-to-code-manifest-helpers-guards.test.sh` read the same files edited here — check them
      by name.
- [ ] `PROJECT.md` — tick `- [ ] the value-domain guard covers step5_mode only  (issue #292)`.
- Budget: `staging/plugin/scripts/tests/manifest-field-state.test.sh`, `PROJECT.md` (~10 lines)

---

## Files touched

| file | change |
|---|---|
| `staging/plugin/scripts/tests/manifest-field-state.test.sh` | section `W` (15 assertions), two shared local functions, `V0b`/`V1`/`V2` refactored onto them, `Z1` floor, 15 plant declarations |
| `staging/plugin/skills/concept-to-code/scripts/manifest-field-state.sh` | domain sentence enumerates `hook_verified`; axis note added |
| `CLAUDE.md` | the same phrase in the ADR-0076 summary |
| `PROJECT.md` | roadmap checkbox |
| `docs/architecture/ADR-0125-292-value-domain-guard-two-fields.md` | new |
| `docs/superpowers/plans/2026-08-04-…md` | this file |

**Not touched, deliberately:** `manifest-init.sh` and `manifest-set-flag.sh` stay byte-identical
(they are read, not edited); `docs/architecture/ADR-0076-…`'s body (ADR-0034); the 49 manifests
(ADR-0075); `manifest-validate.sh`'s invariants (SPEC scopes it out); `.github/workflows/docs-ci.yml`
(this file is already in the list).

## Contract changes

`manifest-field-state.sh`'s **stdout contract is unchanged**. Only its header comment changes, and
only the `hook_verified` clause. No call site, no exit code, no state token moves. No grep across
the repository targets the phrase `hook_verified is a boolean` — verified — so no call-site update
task is needed.
