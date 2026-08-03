# Plan — a bold-wrapped requirement id is invisible to both the checker and the repairer

- **Issue:** #291
- **ADR:** `docs/architecture/ADR-0122-291-bold-wrapped-requirement-id.md`
- **SPEC:** `SPEC.md` (archived copy: `docs/specs/291-a-bold-wrapped-requirement-id-is-invisib.spec.md`)
- **Style:** TDD — assertions first and seen RED, then the mechanism, then the plants.

## Requirements

- **R-01** — a bold-wrapped id either reads as declared or is reported `MALFORMED`; silence is the
  one outcome that must not remain.
- **R-02** — if it is made readable, the repairer must be able to normalise it, per ADR-0072 §D4's
  invariant that a flagged line must become readable once repaired.
- **R-03** — every existing SPEC in `docs/specs/` still produces the same verdict as before, proven
  by running the checker over the whole corpus with a count guard against a vacuous loop.

## Measurements carried in from the ADR (do not re-derive, do re-check if a task disagrees)

| # | fact | value |
|---|---|---|
| M1 | corpus | 67 `docs/specs/*.spec.md` + root `SPEC.md` = **68** (SPEC says 36 — stale since PR #317) |
| M2 | harness | **73** `*.test.sh` (SPEC says 68 — stale) |
| M3 | bold ids in declaration position | **0 of 68** — hypothetical in the corpus, not live |
| M4 | the damaging shape | mixed SPEC: `- [ ] R-01` plain + `- [ ] **R-02** ` bold, plan cites `R-01` → `rc=0`, `COVERED R-01`, **R-02 vanishes** |
| M8 | baseline | `spec-coverage.test.sh` on the real tree: **PASS=114 FAIL=0**; full suite green |

## The three checker call sites (ADR-0122 §D4 — the detail a first prototype got wrong)

`spec-coverage.sh` extracts a token in **three** places, not one. Patching two of three produces a
repairer that rewrites a line the checker said nothing about.

1. declaration match — `txt = item_text(line)` → `txt = strip_emphasis(item_text(line))`
2. near-miss token — `nmt` in the near-miss branch → `nmt = strip_emphasis(nmt)`, and its
   `match()` must become **guarded** (`if (match(...)) printf …`) so a failed match stops writing an
   empty line into `$NEARMISS`
3. declaration text — `rest = substr(txt, RLENGTH + 1)` → followed by `rest = strip_emphasis(rest)`

All three call the shared function, so ADR-0122 §D2's "both sides call the same function" is
literally true at every site.

## Cross-file contracts this plan must not break

- **`declared as plain bullets`** is produced by `spec-coverage.sh`'s near-miss stderr sentence,
  **consumed** by `concept-to-code/SKILL.md`'s Step 5 gate as the auto-repair trigger, and asserted
  by `RN3`. Preserve the substring byte-for-byte.
- **`RN15`** pins the literal `- [ ] R-01` in both SPEC producers. Do not touch either producer.
- **`test-write-scope.sh`** and `plan-task-predicate.awk` are byte-untouched by this feature.
- This plan file itself must keep the `### Task N — …` heading form, or `PTE2`/`PTG9` in
  `plan-task-count.test.sh` redden on the new corpus member. Verified: `--count` = 9,
  `--count-openers` = 8 (one per task).
- **`BB2b` in `diff-budget-scope.test.sh` reddens the moment this plan lands**, because this plan
  declares per-task budgets and `BB2b` bounds the budget-declaring exclusion at an absolute
  ceiling. Measured on the real tree with this plan present: the **full suite is green except this
  one assertion**, reporting `8 plan(s) excluded`. Task 8 handles it — **do not** resolve it by
  deleting the budgets.

## Assertion ids

`RM01`–`RM12`, checked mechanically against all 79 ids in `spec-coverage.test.sh`: **no collision
in either direction**, and mutually non-prefixing because all are fixed-width (ADR-0122 §D10).
`RB` was the intuitive prefix and is already taken. `RN12` is reused deliberately and is a sound
plant target — no id extends it.

---

## Tasks

### Task 1 — RED: section RM and the inverted RN12 (R-01, R-02, R-03)

Add section `RM` to `staging/plugin/scripts/tests/spec-coverage.test.sh`, after section `RN`, and
change `RN12` in kind. Declare every plant at **column 1** (`plant-check.sh` anchors on
`^# plant:`; an indented declaration is silently skipped — `PC4`).

Fixtures (all under `$TMP`, all inside a `## Success criteria` section):

| fixture | line |
|---|---|
| `rm-bold-item` | `- [ ] **R-01** — bold checklist id` |
| `rm-bold-bullet` | `- **R-01** — bold plain bullet` |
| `rm-mixed` | `- [ ] R-01 — plain` and `- [ ] **R-02** — bold mixed` |
| `rm-mention` | `- [ ] **Note** R-01 is mentioned mid-sentence` |
| `rm-underscore` | `- [ ] __R-01__ — underscore` and `- [ ] *R-01* — italic` |

Assertions:

- `RM01` — `rm-bold-item` declares `R-01` (`--list` non-empty, exit 0). **R-01**
- `RM02` — its `--list` text is exactly `bold checklist id` — no leading or trailing `**`. Proves
  the closing-run trim, which `RM01` alone does not. **R-01**
- `RM03` — `rm-bold-bullet` exits **3** with `MALFORMED<TAB>R-01` on stdout. **R-01**
- `RM04` — its stderr names the plain-bullet cause **and** the repair command. Needle the two
  substrings `declared as plain bullets` and `spec-normalize-ids.sh`, not the word "bold". **R-01**
- `RM05` — round trip: after `spec-normalize-ids.sh --apply`, `rm-bold-bullet` exits 0 and
  `--list` reports `R-01<TAB>bold plain bullet`. **R-02**
- `RM06` — the repaired line is exactly `- [ ] **R-01** — bold plain bullet`; the `**` survives.
  The repair adds a marker and touches no content. **R-02**
- `RM07` — a second normalise run on the repaired file reports `CLEAN`. **R-02**
- `RM08` — `rm-mixed` declares **both** `R-01` and `R-02`. This is M4, the shape that passed the
  gate while losing a requirement. **R-01**
- `RM09` — negative twin: `rm-mention` declares **nothing** (`--list` empty, exit 0). The widening
  changes decoration tolerance, never the position rule. **R-01**
- `RM10` — `rm-underscore` declares `R-01` from `__R-01__` and `*R-01*`. **R-01**
- `RM11` — corpus differential: across `docs/specs/*.spec.md` plus the root `SPEC.md`, **zero**
  lines match `^[ \t]*[-*][ \t]+(\[[ xX]\][ \t]*)?[*_]+R-[0-9][0-9]`. Count-guard the sweep at
  `>= 50` (68 today, 36 before #317). If this set is empty the parse is byte-identical to the
  pre-change parse, so no verdict can differ. **R-03**
- `RM12` — corpus outcome: no SPEC in the same swept set reports `MALFORMED`, same count guard.
  **R-03**

`RN12` changes in kind, on its existing `rn-bold.spec.md` fixture: from *"a bold-wrapped id is not
detected"* to *"the repairer rewrites `- **R-01** —` into `- [ ] **R-01** —` and the checker then
declares it"*. Rewrite both the `ok` and the `bad` message so neither asserts the retired contract.

Both count guards use `grep -c … || true`, never `|| echo 0` (which yields `0\n0`).

Plant declarations to add (13). Needle uniqueness was verified against the post-change files; three
declarations share the function-definition needle with different replacements, which is legal —
each runs in its own sandbox.

```
# plant: RM01 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | txt = strip_emphasis(item_text(line)) | txt = item_text(line)
# plant: RM02 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | rest = strip_emphasis(rest) | rest = rest
# plant: RM03 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | t = strip_emphasis(t) | t = t
# plant: RM04 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | nmt = strip_emphasis(nmt) | nmt = nmt
# plant: RM05 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | function strip_emphasis(s) { sub(/^[*_]+/, "", s); return s } | function strip_emphasis(s) { return s }
# plant: RM06 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | return indent "- [ ] " rest | sub(/^[*_]+/, "", rest); return indent "- [ ] " rest
# plant: RM07 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | if (is_checklist_item(l)) return 0 | if (0) return 0
# plant: RM08 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | txt = strip_emphasis(item_text(line)) | txt = item_text(line)
# plant: RM09 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | function strip_emphasis(s) { sub(/^[*_]+/, "", s); return s } | function strip_emphasis(s) { sub(/^[^R]+/, "", s); return s }
# plant: RM10 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | function strip_emphasis(s) { sub(/^[*_]+/, "", s); return s } | function strip_emphasis(s) { sub(/^\*\*/, "", s); return s }
# plant: RM11 | ../docs/specs/287-rtf-s-gitignore-glob-and-this-repo-s-own.spec.md | - [ ] R-01 — one rule, covering | - [ ] **R-01** — one rule, covering
# plant: RM12 | ../docs/specs/287-rtf-s-gitignore-glob-and-this-repo-s-own.spec.md | - [ ] R-02 — an assertion that seeds | - **R-02** — an assertion that seeds
# plant: RN12 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | t = strip_emphasis(t) | t = t
```

Notes on three of them, because their direction is not the obvious one:

- `RM09` is a **negative** assertion. Deleting a mechanism cannot break "X must not happen"
  (ADR-0112), so its plant *widens* the strip to `^[^R]+`, which makes the mid-sentence mention
  parse as a declaration. Confirm `RM01` still passes under it — if `RM01` also fails the plant is
  too blunt to isolate `RM09`.
- `RM10`'s plant narrows the strip to the literal `**`, which is the naive implementation this
  design rejects (ADR-0122 §D3). `RM01` must survive it.
- `RM11`/`RM12` target the docs copy through the literal `../docs/` prefix. Both needles were
  verified to match exactly once in that file.

**Do not run `plant-check.sh` in this task.** Every RM assertion is RED here, and a plant that
"fires" against an already-red assertion proves nothing. Plants are validated in Task 7.

Gate: run `bash staging/plugin/scripts/tests/spec-coverage.test.sh`. Expect `RM01`–`RM12` and
`RN12` RED, everything else GREEN (baseline was 114/0).

- Budget: `staging/plugin/scripts/tests/spec-coverage.test.sh` (~170 lines)

### Task 2 — GREEN: the shared predicate (R-01, R-02)

In `staging/plugin/skills/concept-to-code/scripts/spec-id-predicate.awk`:

1. Add, beside `is_near_miss_bullet`:
   ```awk
   function strip_emphasis(s) { sub(/^[*_]+/, "", s); return s }
   ```
   A character-class **run**, never a `**`-then-`*` ladder: a literal implementation must try the
   two-character form first or `**R-01**` loses one asterisk and stops matching (ADR-0122 §D3).
2. In `is_near_miss_bullet`, insert `t = strip_emphasis(t)` after the bullet-marker `sub()` and
   before the `R-NN` test.
3. Rewrite the header paragraph that currently begins "That is why a bold-wrapped id … is NOT
   matched here". It states a limit this task removes. Replace it with the reason the exclusion
   ended: the invariant forbade detecting a form the checker could not read *after repair*, and the
   checker now reads it — both sides call `strip_emphasis`, so the round trip closes by
   construction. Keep the "THE INVARIANT THIS PREDICATE IS BOUND BY (ADR-0072 §D4)" paragraph; it
   is still the governing rule and is now satisfied rather than avoided. Cite ADR-0122 by name, not
   by line number.

`to_checklist_item` is **not** changed — it prepends a marker and must keep leaving content alone.

Gate: `RM03`, `RM07`, `RN12` and part of `RM05` should move; `RM01`/`RM02`/`RM08`/`RM10` stay RED
until Task 3. Record which went green — a task that greens more than expected means the widening
reached further than designed.

- Budget: `staging/plugin/skills/concept-to-code/scripts/spec-id-predicate.awk` (~40 lines)

### Task 3 — GREEN: the three checker call sites (R-01, R-02)

In `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh`, apply all three edits from
"The three checker call sites" above. Guard the near-miss `match()`:

```awk
    nmt = strip_emphasis(nmt)
    if (match(nmt, /^R-[0-9][0-9]/))
      printf "%s\n", substr(nmt, RSTART, RLENGTH) >> NEARMISS_FILE
```

Without the guard a failed match writes `substr(nmt, 0, -1)` — an empty line — which makes
`[ -s "$NEARMISS" ]` true with no content and sets `NEARMISS_FIRED=1` against an empty `STRUCT`.

Leave the stderr sentence's `declared as plain bullets` substring byte-identical (cross-file
contract). Its trailing clause "the checker reads only `- [ ] R-NN …`" may be adjusted to stay
true, provided the load-bearing substring and `RN3` survive.

Add a comment at site 2 recording why it exists: a first prototype patched sites 1 and 3 only and
produced a repairer that rewrote a line the checker had said nothing about.

Gate: all of `RM01`–`RM10` and `RN12` GREEN. `RM11`/`RM12` should already be GREEN — they assert a
property of the corpus, and if either is RED here the widening reached a real SPEC and the corpus
measurement must be re-derived before going further.

- Budget: `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` (~25 lines)

### Task 4 — The repairer's header, and proof it needed no code (R-02)

`staging/plugin/skills/concept-to-code/scripts/spec-normalize-ids.sh` gets **no executable
change** — it composes the shared predicate, so the widening reaches it for free. Confirm that by
running the round trip by hand before editing anything, and record the result in the commit body.

Correct its header, which describes the old reach: the "WHAT IT WILL NOT DO" paragraph says a line
is rewritten only when "its text begins with a well-formed R-NN token". It now also accepts a
leading emphasis run. Say so, and say that the emphasis is **preserved** in the rewrite.

Gate: `RM05`, `RM06`, `RM07`, `RN12` GREEN. If any needed a code change here, stop — the predicate
is not actually shared and ADR-0122 §D2 is wrong.

- Budget: `staging/plugin/skills/concept-to-code/scripts/spec-normalize-ids.sh` (~12 lines)

### Task 5 — The Step 5 gate paragraph (R-01, R-02)

In `staging/plugin/skills/concept-to-code/SKILL.md`, anchor on the paragraph beginning "If the
re-run still returns 3, stop as before". It contains "**A bold-wrapped id (`- **R-01** — …`) is one
of those** — the checker cannot read it in either form, so it is not detected as a near-miss and
not repaired (ADR-0072 §D4)." That sentence is false after Task 3.

Replace it with the new behaviour: a bold-wrapped id in a checklist item reads as declared; as a
plain bullet it is a near-miss and is repaired by the same automatic path, with the emphasis
preserved. Keep the surrounding contract intact — "Never loop: the repair runs at most once per
gate invocation" and the checker-vs-reporter paragraph below it are unrelated and must survive.

**Do not touch** the `grep -q 'declared as plain bullets'` trigger line.

Gate: `grep -c 'declared as plain bullets' staging/plugin/skills/concept-to-code/SKILL.md` still
returns 1; the full harness stays green.

- Budget: `staging/plugin/skills/concept-to-code/SKILL.md` (~14 lines)

### Task 6 — Corpus regression and the full suite (R-03)

1. Re-run the corpus differential by hand over all 68 SPECs: for each, compare `(exit code, stdout)`
   from the changed checker against the same from a pristine copy of the four scripts restored from
   `git show HEAD:<path>` into a scratch directory. Expect **0 differences**. This is the check the
   ADR performed against a prototype; repeat it against what actually shipped.
2. Confirm `RM11` reports `>= 50` swept and 0 emphasis-sensitive lines, and `RM12` reports 0
   `MALFORMED`. A count below the guard means the glob stopped resolving, which reads exactly like
   a clean corpus.
3. Run the **full** suite: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`.
   Not just this harness — a contract change can redden a test in an unrelated module.
   `spec-coverage.test.sh` is already in `docs-ci.yml`'s named list (`RG1` proves it), so no CI
   change is needed; if `RG1` fails, that is a sandbox artifact only when `.github/` is absent.

If any corpus verdict differs, stop and re-derive M3 before touching code — a difference means a
real SPEC reaches the changed path and the "no-op on the corpus" claim in the ADR is wrong.

### Task 7 — Validate every plant (R-01, R-02, R-03)

Run `bash staging/plugin/scripts/tests/plant-check.sh`. All 13 new declarations must fire.

For each one, **inspect what the plant actually produced** before believing the result (ADR-0090):
a plant that reports as fired from a mutation that is not the mutation it describes is worth
nothing. Specifically check:

- `RM09` and `RM10` fire while `RM01` still passes under each — otherwise the plant is too blunt to
  isolate the assertion it names.
- No replacement contains a newline (`plant-check.sh` cannot express one, and a collapsed
  multi-line replacement silently changes meaning — ADR-0112).
- No field contains a ` | ` sequence.
- `RM11`/`RM12` resolve under the sandbox's `docs/` copy and each needle matched exactly once.

A plant that does not fire is evidence about the **assertion**, not a step to get past: fix the
assertion, not the plant, unless inspection shows the mutation was wrong.

Also confirm `PC0`'s count guard still passes and that the new declarations did not introduce a
`^FAIL:` prefix collision with an existing id in this file.

### Task 8 — Raise `BB2b`'s ceiling, and record the third firing (R-03)

This plan declares per-task budgets, which puts it in `BB2`'s budget-declaring exclusion set and
takes `bb2_skipped` from 7 to 8. `BB2b` in `staging/plugin/scripts/tests/diff-budget-scope.test.sh`
bounds that set at an absolute ceiling and goes red. Measured on the real tree with this plan
present: **the full suite is green except this single assertion.**

Cited against R-03 because R-03's proof is "run the suite over the whole corpus and show no
regression", and this is what makes that run completable. It is not a defect this feature
introduced.

1. Raise the `BB2b` upper bound from 7 to 8, following the two dated comment blocks already in that
   file rather than inventing a new form.
2. Append a comment recording that this is the **third** firing in the same session, on the third
   consecutive healthy feature. The existing comment already says "two firings in a day is evidence
   against that choice" about the absolute bound; a third is worth writing down next to it.
3. Do **not** change the mechanism here. The file itself says converting to a proportional bound is
   a design decision and not something to slip into a red-fixing edit, and that reasoning still
   holds. Raise the number, record the evidence, and leave the redesign to its own issue.

Recommend opening a follow-up issue: *`BB2b`'s absolute ceiling fires on every plan that declares a
budget — the behaviour the budget feature exists to encourage.* Three consecutive features have now
had to hand-edit it.

Gate: full suite green, including `diff-budget-scope.test.sh`.

- Budget: `staging/plugin/scripts/tests/diff-budget-scope.test.sh` (~12 lines)

---

## Risks

- **The corpus cannot validate the feature.** 0 of 68 SPECs exercise the new path, so every bold
  assertion rests on fixtures. A green corpus sweep is evidence the change is a no-op, never that
  it works.
- **`RG1` fails inside a plant sandbox** because `.github/` is outside the copied `staging/` and
  `docs/`. Pre-existing, harmless for prefix-distinct ids, and it will appear in every plant run's
  output.
- **Three declarations share one needle** with different replacements. If `plant-check.sh` is ever
  changed to deduplicate declarations by needle, `RM05`/`RM09`/`RM10` silently lose coverage.
- **Task order is load-bearing.** Widening the near-miss predicate (Task 2) before the checker
  (Task 3) leaves a window where the repairer rewrites a line the checker cannot read — ADR-0072
  §D4's failure exactly. Do not commit between Task 2 and Task 3.
- **`BB2b` is a recurring tax, not a one-off.** Task 8 raises it for the third time in one session.
  Anyone reading a green suite should know the number was hand-edited to get there.
