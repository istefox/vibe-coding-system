# ADR-0131 — `plan-tasks.sh` mode binding: a declared question at every call site, derived and checked

- **Issue:** #294
- **SPEC:** `docs/specs/294-plan-tasks-sh-has-two-modes-with-opposit.spec.md`
- **Status:** Accepted
- **Date:** 2026-08-08
- **Supersedes / amends:** nothing. Extends ADR-0069 (§D2, §D3), ADR-0070 (§D1), ADR-0100 (§D1 and
  its closing disclosure, which is this issue's source).

---

## Context

`plan-tasks.sh` prints one integer and has two modes with **opposite failure directions**:

| Mode | Predicate | Failure direction | Safe for | Wrong for |
|---|---|---|---|---|
| `--count` | `is_task_line()` | **over-counts** — a `## Tasks` section heading matches, every checkbox sub-step matches | a `>= 1` malformed-plan guard | arithmetic |
| `--count-openers` | `is_task_opener()` | **legitimately returns 0** on two corpus plans that name their tasks with another word | arithmetic that tests for zero | a guard |

ADR-0100 closed issue #242 — Step 5's batch arithmetic was consuming the guard count — and ended
with the disclosure this issue is filed against:

> `plan-tasks.sh` now has two modes with opposite failure directions, and nothing prevents a future
> caller picking the wrong one.

Today the only thing standing between a caller and the wrong mode is a paragraph in the script's own
header (`THE TWO MODES ARE NOT INTERCHANGEABLE IN EITHER DIRECTION … A caller picks the one matching
its question and says which, at the call site`). R-01 says in terms that a sentence in a header is
not the mechanism.

That header sentence is not merely weak — it is **unenforceable in the direction that matters**. The
call sites are Markdown fences inside `SKILL.md` files, read by a model. Nothing has ever compared a
call site's flag against the question it is asking, so #242's shape — one number silently serving
two questions — reappears at the moment a third caller is written by someone who did not read the
header.

### What was measured, and which premises did not reproduce

Everything below was derived from the files before anything was designed. Six premises taken from
the SPEC, the issue and this repository's own prose did not survive contact with the tree.

**1. There are THREE invocations, not two.** R-02 says "both existing call sites". Measured — every
line under `staging/` that actually executes the script:

| # | File | Fence | Mode | Binds | Question |
|---|---|---|---|---|---|
| 1 | `concept-to-code/SKILL.md` | `concept-to-code-step5-plan-structure` | `--count` | `tasks` | guard |
| 2 | `concept-to-code/SKILL.md` | `concept-to-code-step5-plan-structure` | `--count-openers` | `openers` | arithmetic |
| 3 | `autopilot-build/SKILL.md` | `autopilot-build-check-5` | `--count` | `tasks` | guard |

**2. The batch dispatch is not a call site.** The SPEC's Architecture names "the Agent-tool batch
dispatch (arithmetic)" as a Step 5 call site. It invokes nothing. Both invocations sit in the *same*
pre-dispatch fence, and the batching policy consumes `$openers` as prose roughly nine hundred lines
further down the file. This changes the design: **a per-fence declaration cannot work**, because one
fence legitimately carries both modes. The unit of declaration has to be the invocation line.

**3. The rule-12 trap is live, at a real call site.** Inside the `autopilot-build-check-5` fence,
this **non-comment** line names the script:

```
[ "$rc" -eq 0 ] || { echo "✗ plan: task check did not run (plan-tasks.sh exit $rc)."; exit 1; }
```

A population defined as "an executable line naming `plan-tasks.sh`" reports that message string as
an unbound invocation. It is ADR-0108's `N9` shape — *a needle matching inside an `ok`/`bad` message
string, which is code and not commentary* — waiting at the first call site the checker reads.

**4. `--count` is a strict PREFIX of `--count-openers`.** Any extraction that matches the flag as a
substring attributes the arithmetic invocation to the guard mode and reports agreement. This is
ADR-0114's `ci`-inside-`cid` lesson with two live subjects rather than a hypothetical one.

**5. R-03 is currently satisfied for ONE mode only.** `batch-dispatch-openers.test.sh` `BO3c`
exercises `--count-openers` against a broken predicate and asserts exit 3. Grepping all 74 harness
files for the same assertion on `--count` returns **nothing**. The script's exit-3 branch is shared
by both modes, so `--count` is correct today by construction — but "preserved for both modes" is
asserted for one, and an asymmetric guard is how the surviving half stops being checked.

**6. Assorted counts have drifted.** The SPEC says a "68-file `*.test.sh` harness" — it is **74**.
`plan-tasks.sh` and `plan-task-predicate.awk` both say "the 62 plans in `docs/superpowers/plans/`
(re-measured 2026-08-03)" — there are now **65**. `scope-guards.test.sh` is listed in the SPEC as a
harness that "already extracts and executes these call sites"; it does not — it names
`plan-tasks.sh` once, in a comment about the checker/reporter distinction, and extracts no plan-task
call site at all.

### Two defects found on the way, both in the harness

- **`plan-task-count.test.sh` `Z1` tests `>= 48` and its own pass and fail messages both say
  "floor 43".** `batch-dispatch-openers.test.sh` `Z1` tests `>= 16` and says "floor 13". Both are
  ADR-0120's lesson exactly: *when you change a literal in an assertion, grep the message strings in
  the same edit — the message is not covered by the assertion it belongs to.* A **passing** `Z1`
  currently prints the wrong number, and the next person to raise the floor will read the message,
  not the test.
- **The derived-guard instance number has collided again.** ADR-0117 recorded that instance 10 was
  claimed twice and instance 7 carried no marker. Measured today, **instance 12 is claimed twice** —
  ADR-0119 §"instance 12" and ADR-0125 §"Instance 12". The next free number is **13**, derived from
  the files rather than from a brief, exactly as ADR-0117 instructs.

---

## Decision

### D1 — Each invocation declares the QUESTION it is asking, on its own line, and a derived checker compares that declaration against the flag

A trailing shell comment on the invocation line:

```
tasks=$(bash ~/.claude/skills/concept-to-code/scripts/plan-tasks.sh --count "<plan>")   # plan-tasks-question: guard
openers=$(bash ~/.claude/skills/concept-to-code/scripts/plan-tasks.sh --count-openers "<plan>")   # plan-tasks-question: arithmetic
```

The marker names the **question**, never the mode. Repeating the mode would add a field that can
drift from the flag two words to its left; naming only the question catches the same defects with
less to go stale:

- change the flag and leave the marker → the flag's question no longer equals the declared one → finding;
- change the marker and leave the flag → same finding, from the other side;
- write a new invocation with no marker → finding;
- copy a call site into a new file → the marker travels with the line it is on.

**Trailing on the same line, not on the line above.** The two `concept-to-code` invocations are two
lines apart with an `rc=$?` between them, so a preceding-line marker for the second would sit
between the first invocation's status capture and the second invocation and read as belonging to
neither. A same-line comment cannot be separated from its subject by an edit that does not also
touch the subject. It is inert shell: a comment does not run, and `$?` on the following line is
still the invocation's status.

### D2 — The mode → question binding lives in `plan-tasks.sh`, as `# mode-contract:` lines, and is the only thing that decides

```
# mode-contract: --count | guard | over-counts by design (a `## Tasks` heading and every checkbox sub-step match): safe for a `>= 1` malformed-plan guard, wrong for arithmetic.
# mode-contract: --count-openers | arithmetic | returns 0 on the two corpus plans naming tasks another word: safe for arithmetic that tests for zero, wrong for a guard.
```

Three fields: flag, question, failure direction. The third is not decoration — it is the reason the
binding is what it is, and it carries the repository's 40-character reason floor.

This is ADR-0069 §D2's own rule applied to the mode vocabulary rather than to the predicate: *if you
need this somewhere new, load this file — do not paste the answer.* The question vocabulary
(`guard`, `arithmetic`) is derived from field 2 of these lines and exists nowhere else, so a marker
naming a word no contract line binds is a finding rather than a silent third question.

### D3 — `mode-binding-check.sh`, a CHECKER, placed where it cannot deploy

`staging/plugin/scripts/tests/mode-binding-check.sh`, following `path-rule-check.sh` (ADR-0117) and
`transition-pair-count.sh` (ADR-0120) exactly:

- it does not end in `.test.sh`, so `.claude/test-cmd`'s glob does not run it directly and
  `.github/workflows/docs-ci.yml`'s **explicit named list needs no append**;
- it sits one directory below `plugin/scripts/`, whose `pairs-completeness.test.sh` population is a
  **non-recursive** `"$STAGING/plugin/scripts"/*.sh` glob — verified against the function, not
  against the ADR summary — so it needs no `PAIRS` entry and **has no inert-until-sync failure
  mode**, the class that has bitten six recent ADRs;
- it is outside `cross-reference-form.test.sh`'s population (`! -path '*/tests/*'`), so a line-number
  reference in it would be unguarded — which is why it carries none.

**Both arguments are arguments** (ADR-0117 §3.9): `mode-binding-check.sh <plan-tasks-script>
<population-root>`. A later issue can point it at another two-mode script or another root without
editing it.

**Exit contract, and it is a checker in every respect:**

| Exit | Meaning |
|---|---|
| 0 | ran; every invocation is bound and agrees. stdout EMPTY. |
| 1 | ran; one or more findings, one per line on stdout. |
| 2 | bad invocation of the checker itself (wrong argument count, unreadable script, missing root). |
| 3 | **DID NOT RUN** — zero modes derived from the parser, or zero invocations found in the population. |

It prints no `CLEAN` sentinel and must never grow one. `weakening-scan.sh` four blocks away in the
same Step 5 is a REPORTER (always exit 0, signals on stdout); the two idioms have been confused once
in this repository already (ADR-0048), and the header says so.

**Zero invocations is exit 3, not exit 0**, and this is the load-bearing half of the contract. A
population that stops resolving discovers nothing, reports nothing, and reads exactly like a tree
where every call site is correctly bound — ADR-0085's denominator lesson, which is also the shape
`plan-tasks.sh` itself has an exit 3 for. A checker whose subject has vanished must say so.

**Finding taxonomy** (one line each on stdout, each naming file, line and the offending token):

| Token | Condition |
|---|---|
| `UNBOUND` | an invocation with a recognised mode and no `# plan-tasks-question:` marker |
| `UNKNOWN-MODE` | the token after the script path is not a mode the parser accepts (covers a variable-held flag) |
| `MISMATCH` | the declared question is a real question, but not the one this mode's contract binds |
| `UNKNOWN-QUESTION` | the declared question is a word no contract line binds |
| `UNCOVERED-MODE` | the parser accepts a mode with no `# mode-contract:` line |
| `STALE-CONTRACT` | a `# mode-contract:` line names a mode the parser does not accept |
| `SHORT-REASON` | a contract line's failure-direction field is under 40 characters |

`MISMATCH` and `UNKNOWN-QUESTION` are kept distinct deliberately: a swapped mode and a drifted
vocabulary have different remedies, and collapsing them is the same error this feature exists to
correct one level down.

### D4 — Derivation: modes from the parser's own `case` arms, population from executable context only

**Modes** are derived at run time from `plan-tasks.sh`'s argument parser — the `--<word>)` arms of
its `case` — never from a hardcoded list. This is ADR-0085 `J0a`'s technique (derive the scoped-agent
list from the hook's own `case` arm) and it is what makes "a new mode added later" *extend* the
mechanism rather than require rewriting it: a mode added to the parser and not to the table is an
`UNCOVERED-MODE` finding on the next run, and a contract line for a mode the parser dropped is
`STALE-CONTRACT` — the ADR-0081 `ZA4` direction, both ways.

`-h|--help` is excluded by a **declared** exemption in the checker
(`# mode-exempt: --help — …`), with a reason, and the exemption is asserted live. It is a usage flag:
it exits 2 and produces no number any caller can consume. Excluding it silently would be the
undeclared waiver this repository keeps removing.

**Population** is every line in **executable context** under the given root that names
`plan-tasks.sh` **and** carries a mode token immediately after the path:

- `*.sh`, excluding `*/tests/*`: every line whose first non-blank character is not `#`;
- `*.md`: only lines inside a fenced bash block, with the opening fence matched
  **indentation-tolerantly** (optional leading whitespace before the three backticks and the word
  `bash`) because this repository already has fence markers inside indented list items — ADR-0083
  §S3, whose absence made that issue's own first count read 101 instead of 138 — and again
  excluding comment lines.

Three filters, each closing a measured false-positive class, and the reasoning is `PTD`'s in the
same harness file rather than a new invention:

1. **the comment filter** clears the two fences' own explanatory comments and the checker's own
   header, which legitimately name `plan-tasks.sh --count` while explaining it (rule 12);
2. **the mode-token requirement** clears the `echo "… (plan-tasks.sh exit $rc)"` message string
   measured at premise 3 above — it names the script and carries no flag;
3. **the `tests/` exclusion** clears the harness's `ok`/`bad` message strings, which are code and
   not commentary, and which a comment filter therefore cannot reach.

The `tests/` exclusion is a real boundary and is declared with its reason: a harness invoking the
script is exercising it, not asking the chain a question, and — measured — every harness invocation
holds the script path in a variable (`bash "$PT" --count "$REF"`), so the literal-path population
never sees them anyway while their message strings would flood it. **A third caller written inside
`tests/` is invisible to this mechanism.** Stated, not discovered later.

**The mode token is compared for EXACT equality against the derived set**, never by prefix. `--count`
is a strict prefix of `--count-openers`; a prefix match silently attributes invocation 2 to the guard
mode and reports agreement. The extractor takes the whitespace-delimited token immediately following
the script path — which is the only position the parser accepts a flag in, since
`plan-tasks.sh "$plan" --count` falls to the parser's `*)` arm and exits 2 — and a token that
matches no derived mode is `UNKNOWN-MODE`, a finding, never a skip. A variable-held flag therefore
fails loudly rather than passing invisibly, which is the safe direction.

### D5 — R-02 is per-call-site and EXACT, not a floor

The three known invocations are asserted per fence, by exact count and by bound variable:

- the `concept-to-code-step5-plan-structure` fence contains **exactly one** `--count` bound to
  `tasks` declaring `guard`, and **exactly one** `--count-openers` bound to `openers` declaring
  `arithmetic`;
- the `autopilot-build-check-5` fence contains **exactly one** `--count` bound to `tasks` declaring
  `guard`.

Exact, because ADR-0124's lesson is that **a floor absorbs its own plant**: with `>= 1`, removing one
invocation still passes and the assertion pins nothing. The checker's own `invocations >= 3`
denominator guard remains a floor and is *only* a vacuity guard — the division of labour is stated
at both sites so nobody later "consolidates" the exact assertions into the floor.

**The bound variable is asserted here and is not a checker rule.** Asserting the binding is what
makes the far-away prose *"the number is `$openers` … never `$tasks`"* resolve to something. It is
deliberately **not** expressed as "the batching paragraph must not contain `$tasks`" — that
paragraph legitimately contains `$tasks` twice while explaining why not to use it, and such an
assertion fails on correct text (rule 12, for the seventh recorded time). A future third caller may
bind no variable at all, so the rule stays a per-call-site fact rather than a checker predicate.

### D6 — This is instance 13 of the derived-guard pattern and stays a copy; the mode table is extracted

ADR-0086's criterion — *extract only when two copies giving different answers would be a DEFECT* —
is applied in **both directions in one feature**, which is ADR-0120's framing of it:

- **Extracted:** the mode → question binding. Two answers to "which question is `--count` for" is a
  defect by definition, so it lives in one place (D2) and is loaded, never restated.
- **Not extracted:** the guard machinery — population derivation, declared marker, denominator count
  guard, live-exemption check. This is its own population asking its own question, with its own
  marker syntax and its own thresholds. Two instances giving different answers would not be a
  defect; a shared source failing would disable thirteen guards at once, in the stay-green way this
  repository has already watched three times.

Instance **13**, derived from the files. The numbering has now collided twice (ADR-0117 recorded the
first; instance 12 is claimed by both ADR-0119 and ADR-0125). Recorded as a fact about the scheme,
not fixed here.

### D7 — R-03: the exit-3 contract is asserted for both modes, and the missing half is added

`--count` gains the broken-predicate assertion `--count-openers` has had since ADR-0100 (`BO3c`), and
each mode's **legitimate zero** is asserted beside it, distinct from exit 3. Measured, `--count`
passes this the day it is written — the script's exit-3 branch is shared — so it is labelled a
**forward guard, not fix evidence**, and its plant is the only thing that makes it mean anything.
An asymmetric guard on a shared branch is how the unasserted half stops being checked.

---

## Alternatives considered

**A. Strengthen the header prose and stop there.**
Rejected by R-01 in terms: the mechanism must be checkable, not a sentence in a header. Beyond the
requirement, the substantive objection is that the header is read once by whoever writes a call
site and never again by anything, so it cannot see a third caller — which the SPEC's own edge cases
name as the population that matters.

**B. Rename the flags so they name the question (`--guard-count`, `--block-count`).**
Rejected. Legibility is not checkability: a caller can still pick `--guard-count` for arithmetic, and
nothing detects it. It buys strictly less than a marker while costing strictly more — a synchronised
rename across two **deployed** `SKILL.md` fences and six harness call sites, with an abort-on-skew
window between the script reaching `~/.claude` and the fences reaching it, which is the
"worse than inert until sync" class recorded six times in this repository.

**C. A required `--for <question>` argument, validated by the script at run time.**
Rejected, and it is the closest alternative, so the reason matters. It looks stronger because the
running system reads it. But ask what the script could *do* with the value: it can only compare the
declared question against the flag — a purely static fact the checker already compares — because it
cannot see what the caller does with the number afterwards. **It buys zero detection power over the
comment marker.** Against that zero it charges a hard version coupling between a deployed script and
two deployed `SKILL.md` fences: whichever side syncs first, the other's invocation exits 2, and
every Step 5 dispatch plus every `autopilot-build` pre-flight aborts. Paying an abort-on-skew risk on
two unattended paths for no additional coverage is not a trade. The *declaration* half of this
alternative is what D1 keeps; only the *runtime requirement* half is dropped.

**D. A central registry mapping call sites to modes.**
Rejected by ADR-0077's rule — a declaration travels with the file it describes. A central list goes
stale on rename or move, and it lets an author register a call site without touching the call site,
which is ADR-0069 §PTD's identity waiver in a new costume. ADR-0087 used a central registry only
because the file being excused was **absent from staging by construction**, so nothing existed for
the waiver to travel with; here the call sites are real lines in real files and that exception does
not apply.

**E. Change `--count`'s output so it cannot be consumed as a bare number (e.g. print `GUARD:3`).**
Rejected. It breaks the numeric contract the SPEC pins as the interface (`one integer, nothing
else, ever`), breaks all three existing call sites and six harness assertions at once, and a caller
determined to do arithmetic simply strips the prefix. It also converts a static, harness-visible
defect into a runtime parse error on unattended paths.

**F. Extract the derived-guard machinery into a shared helper reused by all thirteen instances.**
Rejected per ADR-0086's criterion, restated at D6. The thirteen guards ask thirteen questions about
thirteen populations with three different marker syntaxes and thresholds that legitimately differ
(`>= 2`, `>= 3`, `>= 8`, `>= 100`); there is no shared answer that could diverge, and the guards are
worth having **because they fail independently**.

**G. Detect the semantic case — a mode whose number is consumed by the wrong kind of question.**
Rejected as not expressible. The consumer of `$openers` is prose nine hundred lines from its
binding, in a file read by a model; correct prose and incorrect prose that reference the same
variable are not separable by any rule over the text. The narrow, checkable slice of it — that each
mode binds a distinct, asserted variable name — is kept (D5). The rest is disclosed at the head of
the Consequences rather than approximated.

---

## Consequences

### Positive

- A third caller written tomorrow with no marker is a **finding on the next harness run**, naming
  file and line. That is the population the SPEC says the mechanism must actually cover, and it is
  the one no assertion could reach before.
- A **new mode** added to the parser extends the mechanism instead of requiring it to be rewritten:
  it must acquire a `# mode-contract:` line or fail as `UNCOVERED-MODE`, and its question word joins
  the vocabulary automatically because the vocabulary is derived from the table.
- The mode → question binding acquires a single home. It was previously stated in prose in four
  places — the script header, both call sites' surrounding paragraphs, and ADR-0100 — with nothing
  comparing them.
- R-03's asymmetry closes: `--count`'s exit-3 branch is asserted for the first time in a 74-file
  harness, alongside each mode's legitimate zero.
- **No deployment coupling is created.** The checker cannot deploy by construction (D3), and the
  only deployed change is three trailing shell comments, which cannot alter a fence's behaviour and
  are covered by `fence-contract-coverage.test.sh`'s existing `bash -n` on both declared fences.
- Two harness `Z1` floors stop printing a number that disagrees with the test beside them.

### Negative

- **The marker declares INTENT, and nothing verifies the intent is honest.** A call site that
  declares `guard`, invokes `--count`, and then feeds the number to arithmetic passes every check
  here. That is #242's exact shape, and this feature does **not** close it — see alternative G. The
  honest reading of a green run is *"every invocation declares its question and the declaration
  agrees with its flag"*, never *"no invocation is used for the wrong question"*. Anyone treating
  this as the semantic gate will be relying on something that does not exist.
- **A caller inside `staging/plugin/scripts/tests/` is outside the population by design** (D4). The
  reason is sound and the boundary is still a boundary.
- The population reads `staging/` only. `docs/` is out (ADR-0034: a historical ADR or plan quoting an
  invocation is a correct snapshot of its moment), and `~/.claude` is out (ADR-0024: the harness must
  not depend on deploy state). An invocation written directly into the deployed tree is invisible.
- Three more markers exist that a reflow, a re-indent or a "tidy the comments" pass can silently
  remove. The checker fires on removal, which is the point, but it is a new way for a harness to
  redden on a file nobody meant to change.
- The `40`-character reason floor on the contract lines checks that a reason is **long**, never that
  it is **true** — the same limit every declared waiver in this repository carries.

### Neutral

- `plan-tasks.sh`'s stdout, stderr and exit contract are **byte-identical**. The only change to the
  script is comments. No caller behaviour changes on any path, attended or unattended.
- No manifest field, no schema change, no state-machine pair, no migration.
- No new `*.test.sh` file, therefore **no `docs-ci.yml` append** — measured, the named list currently
  holds 74 entries against 74 files, and the new assertions land in `plan-task-count.test.sh`, which
  is already named there.
- The instance-numbering collision (12 claimed twice) is recorded, not repaired. Repairing it means
  editing two Accepted ADRs' bodies, which ADR-0034's precedent forbids.
- The drifted corpus counts in `plan-tasks.sh` and `plan-task-predicate.awk` headers (62 → 65 plans)
  are **disclosed and not updated**: re-dating a measurement requires re-measuring, and the plan
  corpus is not this issue's subject. `plan-shape-baseline.tsv` holds 62 rows against 65 plans, which
  is the decay ADR-0121 already disclosed.

---

## References

- Issue #294; `docs/specs/294-plan-tasks-sh-has-two-modes-with-opposit.spec.md`
- ADR-0069 (§D1 the predicate is loaded not pasted; §D2 one place decides; §D3 `plan-tasks.sh` as the
  single counting entry point; §PTE2 the named plan exemption)
- ADR-0070 (§D1 `is_task_opener()` as the second, different predicate; §PTG9 the second exemption)
- ADR-0100 (§D1 `--count-openers`; its closing disclosure is this issue's source)
- ADR-0086 (the extraction criterion, applied in both directions at §D6)
- ADR-0120 (the criterion read in two directions; the message-string lesson behind the `Z1` finding)
- ADR-0117 (`path-rule-check.sh`: a checker in `tests/` with no deployment path; arguments not
  hardcoded paths; derive the instance number from the files)
- ADR-0085 (`J0a` derive from the source's own `case` arm; `T0b` guard the denominator)
- ADR-0081 (`ZA4` a stale waiver reads as clean coverage)
- ADR-0083 (§D3 fence markers as extraction anchors; §S3 indented fences)
- ADR-0108 (the plant registry; the `N9` message-string shape at premise 3)
- ADR-0114 (the `ci`-in-`cid` substring lesson behind the `--count` prefix hazard)
- ADR-0124 (a floor absorbs its own plant)
- ADR-0048 / ADR-0047 (the checker versus reporter contract)
- ADR-0024 / ADR-0043 (why the harness must not depend on deploy state; `PAIRS` population)
