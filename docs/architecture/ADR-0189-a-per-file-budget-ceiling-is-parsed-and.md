# ADR-0189 — A per-file budget ceiling survives to the comparison instead of being summed away

- **Status:** Accepted
- **Date:** 2026-09-02
- **Issues:** #296 (derived from ADR-0091's own Verification section)
- **Related:** ADR-0091 (#246, which taught the parser to READ the per-file form), ADR-0052 (#106,
  the feature both correct), ADR-0070 (#184, which woke the check up and fixed the `--stat` defects
  this attribution depends on), ADR-0185 (VCS-057, which extracted `plan-budget-parse.awk` and made
  the parser a shared producer), ADR-0072 (a form close enough to be partially read is worse than
  one rejected outright), ADR-0064 §D3 (absent is not zero)
- **Out of scope, deliberately:** #295 (the `MALFORMED` token's consumers), #293 (the identifier
  model), #294 (mode selection)

## Context

ADR-0091 fixed the *parse*. `Budget: a/x.md (~165 lines, new), b/y.sh (~1 line)` is now read as two
paren groups walked left to right. Then `parse_budget` returns `<files>\t<total>`, the ceilings are
added together, and the per-file granularity is gone before anything compares it to a diff.

**The point of a per-file declaration is per-file accountability. Summing gives the answer a single
total would have given, so the finer syntax buys nothing while looking like it does.**

### The defect, reproduced on a real corpus plan before any design (rule 13)

Not argued from the issue's text. `docs/superpowers/plans/2026-07-30-222-vendor-deployed-only-skills.md`
task 2 declares `staging/plugin/skills/ui-layout-audit/SKILL.md (~165 lines, new),
staging/sync-to-claude.sh (~1 line)`. Piping a synthetic `git diff --stat` in which
`sync-to-claude.sh` carries **60** changed lines against its declared **1**, while the task total
(160) stays under the summed 166:

```text
$ printf ' staging/plugin/skills/ui-layout-audit/SKILL.md | 100 ++\n staging/sync-to-claude.sh | 60 ++\n' \
    | bash diff-budget-check.sh --plan <that plan> --tasks 2
CLEAN
```

A file at **sixty times** its own declared ceiling reports as nothing to report. The control — the
same two files at 100/100, so the total overshoots — still produces
`BUDGET<TAB>2<TAB>files=2/2<TAB>lines=166/200<TAB>margin=34`, so the existing check is alive and
this is the specific blindness, not a dead check.

### The corpus, re-derived 2026-09-02 (rule 13 — ADR-0091's numbers are a snapshot of 2026-07-31)

ADR-0091 measured 16 declarations in 3 plans, 3 of them per-file. That is no longer the population:

```text
plans in docs/superpowers/plans/:                            79
plans carrying >= 1 parseable `Budget:` declaration:         23
parseable declarations (>= 1 qualifying paren group):       159
  of those, MULTI (>= 2 qualifying groups — the per-file form): 24, in 7 plans
  of those, SINGLE (one group — the documented form):          135
declared file entries across all groups:                    205
  of those, containing a glob character (`**`, `*.md`):         2
```

The per-file form went from 3 declarations to 24 in thirteen months while nothing downstream read
it. That growth is the argument for fixing it now rather than the reverse: 24 declarations are 24
places where an architect wrote a finer number than the tool can act on.

### What the check is, and what that constrains

`diff-budget-check.sh` is a **REPORTER** (rule 5): always exit 0, signal on stdout, `CLEAN` when
there is nothing. `budget_findings` is advisory and never a failure signal (ADR-0052 §D3). Two
things follow and they set the whole design's direction:

1. **A false positive is the expensive failure here, not a false negative.** An advisory reporter
   that cries wolf stops being read — which is exactly what the `auto-learning` declaration
   recorded about a report that fires every run. Every ambiguity below resolves toward leniency.
2. **The cumulative-diff semantics are fixed and not up for revision here.** Step 5 has no commit
   boundary, so every checkpoint re-scans the whole diff since `$_pre5` and passes `--tasks` as
   every task dispatched so far (ADR-0052 §D2). Per-file attribution has to be correct under that,
   not under a per-task diff that does not exist.

## Decision

### D1 — The per-file detail reaches the driver through an optional awk array parameter, and `parse_budget`'s return value does not change at all

`parse_budget(rest, groups,   s, pre, ...)`. The second parameter is filled with one entry per
accepted paren group, `groups[i] = "<files>\t<ceiling>"`, and `groups[0]` carries the count. The
return value stays byte-identical: `"<files>\t<total>"`, or `""` on a parse failure.

This is the standard POSIX-awk idiom for an out-parameter: a caller that passes one argument gets
an uninitialised local array it never looks at. **Verified rather than assumed** on this machine's
`awk version 20200816` — a one-argument call returns the same string and discards the array; a
two-argument call returns the same string and fills it.

The consequence is the cheapest possible proof of R-02: the two existing callers
(`diff-budget-check.sh`'s own driver and `step5-brief.sh`'s two call sites) and the frozen
comparison inside `diff-budget-scope.test.sh` §BK9 need **no edit at all**, and cannot observe the
change. ADR-0185 made this parser a shared producer precisely so one answer serves every consumer;
widening the answer without moving it is what keeps that true.

`groups[0]` is set to `0` on entry and to the real count only immediately before the successful
return, so a failed parse can never leave the previous line's count visible. Nothing is ever
deleted from the array — the driver reads indices `1..groups[0]` and stale higher indices are
unreachable. That avoids `delete groups`, whose whole-array form is a near-universal extension
rather than POSIX.

### D2 — The unit of accountability is the paren GROUP, and a file's ceiling is the SUM of every selected group naming it

A group is what the architect actually wrote: `a.md, b.md (~50 lines)` is one ceiling over two
files, `c.md (~10 lines)` is a second group. Splitting 50 evenly across `a.md` and `b.md` would
invent a number nobody declared.

So attribution is defined at the file level by summing:

> **ceiling(f)** = the sum of `ceiling(g)` over every group `g` belonging to a **selected** task
> with `f` in `files(g)`.
> **actual(f)** = the changed-line count of `f` in the diff, after the existing exclusions and
> after the scope partition.

Summing is what makes this correct under D2's cumulative diff. The `--tasks` set grows at every
checkpoint, and a file named by three tasks accumulates all three ceilings — measured in the
corpus, `staging/sync-to-claude.sh` is declared with `(~1 line)` in three separate tasks of the
same plan. A per-task rule would fire three times on one file and be wrong three ways; the sum is
**monotone** in the task set, so adding a task can only raise a ceiling and never manufacture a
finding.

A file in a multi-file group therefore gets that group's whole ceiling as its own. That is lenient
by construction, and deliberately: the group-level overshoot is already the existing task-total
check's job, and leniency is the direction §Context point 1 demands.

### D3 — A finding is emitted only for a file at least one of whose groups came from a task that declared TWO OR MORE groups

This is the gate that makes R-02 true end to end rather than only at the parser.

If every task in a plan declares one group, no file is reportable, and the script's stdout is
**byte-identical to today** for every task selection and every diff. Not by a special case, not by
a coincidence in the corpus — as a property of the gate. 135 of the 159 declarations, and 16 of the
23 budget-declaring plans, are inert by construction.

Note carefully that reportability and the ceiling are computed from **different** populations, and
that asymmetry is the whole point. Reportability looks only at multi-group tasks; the ceiling sums
over **every** selected group, single-group ones included. Without that, a file declared
`sync.sh (~1 line)` by a per-file task and `sync.sh (~50 lines)` by a single-ceiling task would be
checked against 1 while carrying 51 lines of legitimate work — a false positive built into the
mechanism. With it, the ceiling is 51 and nothing fires.

### D4 — A NEW token, `FILEBUDGET`, never a variant of `BUDGET`

```text
FILEBUDGET<TAB><tasks-label><TAB><file><TAB>lines=<expected>/<actual><TAB>margin=<N>
```

The grammar becomes `BUDGET`, `FILEBUDGET`, `SCOPE`, `MALFORMED`, `CLEAN`.

`BUDGET`'s field 2 is a task label and every consumer reads it that way; the Step 5 block records
`files=<exp>/<act>` and `lines=<exp>/<act>` from it, and the harness pins the exact five-field shape
with an anchored regex. A per-file variant of `BUDGET` would put a **path** where a task label
belongs, and every un-updated `grep '^BUDGET'` would half-read it — ADR-0072's rule, which ADR-0091
already invoked for `MALFORMED` in this same script. A distinct token fails safe instead: an
un-updated consumer's `^BUDGET` match simply does not fire, and the name does not begin with
`BUDGET`, so an anchored grep cannot pick it up by accident.

The token carries the `--tasks` label because a `FILEBUDGET` line can be emitted when **no**
`BUDGET` line fires — that is the entire point of R-01 — so the caller cannot recover the label from
a neighbouring line.

Emission is gated on the same `BUDGET_LIVE` condition as the `BUDGET` line: no selected task carries
a live budget, no per-file finding. The whole-plan inert path (`CLEAN`, or `MALFORMED` alone) is
untouched.

### D5 — Recorded in the EXISTING `budget_findings` array as `{task, file, lines_expected, lines_actual}`

Additive, no schema bump, no seventh array — the same terms as every prior extension of
`step5-report.json`, and the same shape as ADR-0091 §D3's `{task, malformed}` entry.

No `files_expected` / `files_actual` keys. A per-file finding measures lines only; writing zeros
there would read as a task that touched no files, which is ADR-0064 §D3's rule and the identical
reasoning `{task, malformed}` used.

**A reporter line no caller reads is a producer with no consumer** (rule 17, the #238 class). The
Step 5 block in `references/step5-implementation.md` is extended to read the token, name the file
and its two numbers at Gate 5, and record the entry — and the harness pins that call site with
needles belonging to this block and nothing else, the way §BK10 already pins `MALFORMED`'s.

### D6 — Attribution uses the elision-resolved path and only files that passed the scope partition

`actual(f)` is taken inside the existing candidate loop, from `$_lookup` — the path **after** the
`.../tail` elision recovery — not from the raw `--stat` column. ADR-0070 §D5/§D6 are named in the
SPEC's edge cases as the two defects that corrupt per-file attribution, and they corrupt it harder
here than they did the total: an unresolved elided name would silently carry zero lines against a
real ceiling, and a right-aligned count would drop the file out of the candidate set entirely. Both
call sites already pass `--stat=999`; this rides on the recovery rather than duplicating it.

Only in-scope files contribute. An out-of-scope file is a `SCOPE` finding and is excluded from the
budget totals (ADR-0052 §D4, so the firm signal is not degraded by the soft one); it has no declared
ceiling either, so there is nothing for it to overrun. `MASTER_SCOPE` and the `SCOPE` partition are
not touched by this change.

Two consequences are accepted and stated rather than worked around:

- **A declared entry containing a glob (`**`, `*.md`) can never be attributed.** Membership is the
  exact `grep -qxF` test the scope check already uses; a glob string equals no real path. Two of the
  205 declared entries in the corpus are globs. They silently carry no finding — the honest failure
  direction (no claim) rather than expanding a glob and inventing an attribution.
- **A file that is in scope only via a plan-level `Scope:` glob has no ceiling and cannot fire.** A
  `Scope:` glob declares reach, not a budget.

### D7 — Step 4.5's tracer-bullet verdict is deliberately NOT extended

The tracer-bullet block derives `green|amber|red` from "no `SCOPE` finding, no `BUDGET` overshoot".
It is left exactly as it is. This is a decision, not an omission: the tracer plan fragment is a
one-task synthetic file the chain writes itself, widening the verdict's inputs changes a routing
decision that gates a human interaction, and neither R-01 nor R-03 asks for it. The token still has
a consumer (D5), so rule 17 is satisfied without it.

### D8 — R-02's proof is TWO comparisons, and neither alone would be evidence

R-02 asks for a whole-corpus both-parsers comparison "as ADR-0091 §BK9 did". §BK9 stated its own
boundary: it compares the `parse_budget` **function** and is blind to a script that defines it
correctly and never calls it. This feature's change is mostly *in the call site*, which is precisely
that blind spot, so repeating §BK9's method alone would be repeating a check that cannot see the
change.

1. **Function level.** A frozen pre-#296 copy of `parse_budget` is embedded in the harness — §BK9's
   own device, for §BK9's own stated reason: the test must be able to disagree with the script it
   checks — and every declaration in the corpus is parsed by both. All 159 must return an identical
   string, single-ceiling and per-file alike, because D1 changes no return value.
2. **Script level.** Every plan in the corpus is run through the real script against a synthetic
   diff derived from that plan's own declared files, and the set of plans producing a `FILEBUDGET`
   line must equal exactly the set carrying a multi-group declaration. Set equality in both
   directions, §BK9b's device rather than a count, and for §BK9b's reason: the corpus grows, and a
   number fixed today goes red on a healthy feature tomorrow (this file's own §BB2 disease).

Comparison 1 is green if the whole feature is deleted, so it is paired, not standalone (rule 9): an
assertion that `groups` is populated with the right count for a known declaration, and comparison 2,
which is red if `FILEBUDGET` is never emitted. Both directions per contract, in both comparisons.

## Alternatives considered

### A1 — Append a third tab-separated field to `parse_budget`'s return

`"<files>\t<total>\t<file1>:<n1>;<file2>:<n2>"`. **Rejected.** Three shell read sites consume that
return positionally (`while IFS=TAB read -r _t _files _lines`), and a fourth field lands silently in
the last variable, turning `LINES_EXPECTED=$((LINES_EXPECTED + _lines))` into an arithmetic error on
a two-word string. `step5-brief.sh` reads it twice more, once through `split(parsed, pb, "\t")`. And
§BK9's comparison does `sub(/\t/, "|", r)` on the first tab only, so all 159 corpus rows would change
shape and R-02's own proof harness would have to be rewritten to stay green — weakening the exact
assertion R-02 is asking for. It also forces an in-band separator (`;`, `:`) over strings that are
file paths, with no way to reject a path containing one.

### A2 — A second function, `budget_groups(rest)`, walking the paren groups again

**Rejected on rule 6 and on ADR-0091 §D1's own words.** §D1's entire argument for the left-to-right
walk was that the documented form is the walk with one group, "so there is no second code path to
keep in agreement". A second walk of the same grammar in the same file is two copies answering one
question, able to disagree, with nothing forcing them to meet. It would also be picked up by §BK9's
`sed -n '/^function parse_budget/,/^}$/p'` extraction if it were named with that prefix — a second
way for the same mistake to hide.

### A3 — Overload `BUDGET` with a per-file variant

Reuse the token, distinguishing per-file lines by whether field 2 looks like a path. **Rejected.**
Every consumer's `grep '^BUDGET'` would match, and every one of them would read field 2 as a task
label and the `files=` field as a count that is not there. That is a form close enough to be
partially read — ADR-0072's rule, four instances in this repository, and the specific one ADR-0091
cited when it chose a new `MALFORMED` token over widening `BUDGET` in this same script. Rejection is
visible; a partial read is a wrong answer with a right answer's confidence.

### A4 — Apply per-file ceilings to every declaration, single-ceiling ones included

Drop D3's reportability gate: sum each file's ceilings across the selected tasks and check every
file. **Rejected for this issue, and it is worth a separate one.** It would change reported output
on 135 of 159 declarations and on every multi-task checkpoint, which is a blast radius R-02 cannot
absorb and which nothing in #296 asks for. The class it would catch is real and different: **a task
blowing its own budget while another selected task's slack absorbs it**, invisible today because
`--tasks` sums across the whole dispatched set. That is the `--tasks` accumulation ADR-0052 §D2
designed on purpose, and revising it is mode-selection territory (#294, explicitly out of scope
here). Recorded as a follow-up candidate rather than refused: an absent ADR clause is not a reason
to leave a class unnamed.

### A5 — A new `file_budget_findings` array in `step5-report.json`

**Rejected.** The Gate 5 roll-up is pinned to "six advisory arrays" in `references/hitl-gates.md`
and asserted by §BG1 and §BG4; a seventh array means a Gate 5 rewrite, a roll-up wording change and
two harness edits, for a finding the SPEC's own Data model already places "alongside the existing
`budget_findings` entries". It would also hide the finding from `h16-direction-check.sh`, whose
`budget-overshoot` trigger reads `.budget_findings | length` — a per-file overrun *is* a budget
overshoot and belongs in that count.

### A6 — Split a shared group ceiling evenly across its member files

`a.md, b.md (~50 lines)` becomes 25 each. **Rejected.** It invents a number the architect did not
write, and it converts a lenient rule into a strict one in exactly the population where the
declaration is least specific — the direction §Context point 1 rules out. D2's whole-ceiling-per-
member reading is what the declaration actually says.

### A7 — Make an unattributable declared entry (a glob) a `MALFORMED` finding

**Rejected.** `MALFORMED` means "the checker could not read this declaration", and it reads a glob
entry fine — it simply cannot attribute a diff to it. Widening that token's population is #295's
subject, which this issue's Scope puts out of bounds, and it would fire on two corpus entries that
are doing nothing wrong.

## Consequences

### Positive

- **R-01 is satisfied at the case that produced the issue**, reproduced above: a file at 60x its own
  declared ceiling stops reporting `CLEAN`.
- **The per-file syntax finally buys something.** 24 declarations across 7 plans gain the
  accountability their author was already writing by hand.
- **`parse_budget`'s return is byte-unchanged**, so `step5-brief.sh` (ADR-0185's second consumer)
  and §BK9's frozen comparison need no edit and cannot be broken by this change. R-02 at the parser
  level is proven by construction, not by inspection.
- **The single-ceiling population is inert by property, not by luck** — D3's gate makes "no
  multi-group task, no per-file finding" a mechanical fact about 135 of 159 declarations.
- **The ceiling sum is monotone in the task set**, so the growing `--tasks` list at successive Step 5
  checkpoints can never manufacture a per-file finding out of pooling.

### Negative

- **The token grammar grows from four to five.** Every consumer #295 will enumerate now has one more
  token to account for, and #295's own scope grows accordingly. The mitigation is that `FILEBUDGET`
  fails safe against an un-updated consumer (D4), not that the cost is zero.
- **`h16-direction-check.sh` becomes more sensitive.** Its `budget-overshoot` TRIGGER fires at
  `>= 2` entries in `budget_findings`, and per-file entries now count toward that threshold. This is
  semantically right — a per-file overrun is a budget overshoot — but it is a real behaviour change
  in a different skill, and it is stated here rather than discovered there (rule 17).
- **Two declared entries in the corpus are globs and silently carry no finding** (D6). The failure
  direction is a missing claim rather than a wrong one, but it is a hole and it is not guarded.
- **Under the cumulative diff, attribution is still coarse.** Lines a coder wrote into a file while
  working on a task that did not declare it are attributed to whatever ceilings do name it. D2's sum
  makes this lenient rather than false-positive-prone; it does not make it exact, and exactness is
  not available without a per-task commit boundary the chain does not have.
- **A group whose files are declared by two tasks with overlapping-but-unequal file sets** can have
  one member's lines counted against both groups' ceilings. Leniency (D2's sum) absorbs the common
  case; the pathological one would over-report, and nothing detects it.

### Neutral

- **The reporter contract is untouched** (R-03): always exit 0, signal on stdout, `CLEAN` when there
  is nothing. No exit code is added and no caller idiom changes.
- **`MASTER_SCOPE`, the `SCOPE` partition, the exclusion list and the whole-plan inert check are
  byte-unchanged.** The change adds a parallel table and one emission block; it removes nothing.
- **Step 4.5's tracer-bullet verdict is unchanged** (D7).
- **No new script and no new harness file.** The work lands in one awk library, one script, one
  reference doc and one existing harness — so `sync-to-claude.sh`'s `PAIRS`, the `docs-ci.yml`
  shell-tests list and the plant shards need no new entries.

## Verification

- New section `BL` in `staging/plugin/scripts/tests/diff-budget-scope.test.sh` (prefix verified free
  across `staging/` on 2026-09-02), roughly twelve assertions, each seen RED against a declared
  plant in the registry beside it (`# plant:` at column 1, ADR-0108).
- Both directions per contract in each: the per-file overrun that must fire, and the single-ceiling
  and under-ceiling cases that must not.
- D8's two comparisons, each with its count guard (rule 7) — a corpus sweep that derives zero
  declarations is a broken derivation, not a clean corpus, and the two look identical from outside.
- `Z1`'s assertion-count floor is bumped. It stays a floor and stays labelled a vacuity guard, per
  rule 10: it absorbs its own plant and is not the evidence for anything.
- The existing `BK9a/b/c` must remain green **untouched**. That is itself evidence: they compare the
  pre-#246 parser against the current one, and this feature must not move that answer.

## References

- Issue #296; `docs/architecture/ADR-0091-246-per-file-budget-half-parse.md` §D1, §D2, §D3, §BK9
- `docs/architecture/ADR-0052-106-diff-budget-scope-check.md` §D1–§D6
- `docs/architecture/ADR-0070-184-diff-budget-task-predicate.md` §D5, §D6
- `docs/architecture/ADR-0185-step5-task-brief.md` (the parser extraction)
- `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh`,
  `staging/plugin/skills/concept-to-code/scripts/plan-budget-parse.awk`
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md`, the
  "Diff budget and scope check" block
- `staging/plugin/skills/project-conductor/scripts/h16-direction-check.sh`, the `budget-overshoot`
  trigger
- CLAUDE.md rules 5, 6, 7, 9, 10, 12, 13, 17
