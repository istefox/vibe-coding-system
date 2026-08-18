# ADR-0154 — a scoped test file must name the feature back

- **Topic slug:** `spec-coverage-scope-back-reference`
- **SPEC:** `SPEC.md` (R-01 … R-12), archived at completion to `docs/specs/`
- **Plan:** `docs/superpowers/plans/2026-08-18-spec-coverage-scope-back-reference.md`
- **Narrows:** ADR-0138 §D1–§D3. Supersedes nothing.

## Status

Accepted — 2026-08-18.

## Context

ADR-0138 narrowed `spec-coverage.sh`'s test axis from a repository-wide scan to the test files the
plan names. The narrowing was the right axis — it was chosen against a measured alternative that
would have failed the best-tested features — but it does not hold at the strength it was believed
to have. A plan names other harnesses for ordinary reasons: a precedent it copies, an idiom it
reuses, a verification step it prescribes, a staleness list at its end. Every one of those names
enters the scope carrying the whole of its own `R-NN` namespace.

This is CLAUDE.md rule 18 with a denominator that is smaller than the repository but still much
larger than the feature: *a scan is satisfied by the whole population it searches, not by the part
it meant.*

### Four measurements, three of them independent of each other

**M1 — the exposure on a real plan (design input, dated 2026-08-18).** On the ADR-0153 plan,
`spec-coverage.sh` reports 6 files in scope. Three are cited as precedents and carry seven ids of
their own: `pairs-completeness.test.sh` (`R-05`, `R-09`), `plant-check.sh` (`R-01`, `R-05`,
`R-12`), `recovery-preflight.test.sh` (`R-02`, `R-03`) — every one inside that feature's declared
`R-01 … R-24` range. Before its Task 6 landed, four of them reported `COVERED` while cited nowhere
in the feature's own harness.

*Re-derived here on 2026-08-18, after that feature's Task 6 landed (rule 13).* The same filter now
returns 7 files for that plan. Two of the three precedents are still there and still carry their
ids. `plant-check.sh` is **not** among them, and the reason is worth recording rather than
smoothing over: its basename matches none of the discovery predicate's patterns
(`*.test.*`, `test_*`, `*_test.*`, `*Test.*`, `*Tests.*`, `test-*.sh`, `run-tests.sh`,
`*.spec.js…`), so the id tokens inside it are invisible to the test axis entirely. M1's direction
is confirmed; one of its three files reaches the gate through a door that does not exist.

**M2 — an independent measurement from a different feature (dated 2026-08-17).** The architect's
own durable note from the ADR-0153 chain: *the spec-coverage gate is satisfied by foreign `R-NN`
mentions in any test file the plan names in prose, including the staleness list at the end;
measured 9 of 13 ids `COVERED` before implementation on this feature.* Different plan, different
measurer, same class, stronger number.

**M3 — this feature's own gate, run at design time before a line was written (new, 2026-08-18).**
`spec-coverage.sh --spec SPEC.md --plan <a stub naming only this feature's own harness>
--tests-root .` reports **8 of 12 ids `COVERED`**, with exactly one file in scope. Every one of the
eight is satisfied by a fixture token inside `spec-coverage.test.sh` — `- [ ] R-10 — a` and
`### Task 3 — GREEN: thing (R-10, R-11)` are heredoc fixtures for the plan-citation forms `RC3` and
`RC4` assert, and they mean nothing about this feature.

M3 is a different failure from M1 and M2 and **this ADR does not fix it**: the collision is inside
a file that legitimately belongs to the feature. It is recorded because it bounds what the gate can
be said to prove, and because this feature's harness is the worst case in the corpus — a harness
about requirement ids, whose fixtures are literally requirement ids. See §D7.

**M4 — the adopted design, measured across the plan corpus (design input, 2026-08-18).**

```
plans naming >= 1 discovered harness                 : 52
  of which >= 1 named harness names the plan back    : 52   (the denominator never collapses)
scoped files under today's filter                    : 263
scoped files naming the plan or one of its ADRs      : 169
dropped from scope                                   : 94   (36%)
ids flipping COVERED -> UNCOVERED under the new rule : 0
```

The 94 dropped are the precedent citations. No genuine coverage is lost on any of 52 plans.

### The proxy inside that zero, and why it is not carried forward as a caveat

M4's flip count approximated each feature's declared id set by the ids its **plan** cites, not by
parsing its SPEC. That approximation is retired by this feature's own deliverable rather than left
open: regenerating `spec-coverage-scope-baseline.tsv` — one row per (SPEC, declared id) pair, read
straight off the checker's stdout — *is* the re-derivation against the SPEC corpus. The baseline is
where the zero is proven or refuted, row by row, and §D5 makes a non-precedent flip a halt.

## Decision

### D1 — the scope filter becomes a conjunction, and half 2's key set is the plan's basename OR any `ADR-NNNN` the plan cites

A discovered test file enters the test axis when **both** hold:

1. its basename appears in `$PLAN` as a whole token — today's condition, byte-for-byte unchanged;
2. its own text names **the plan's basename** (including the `.md` extension) **or one of the
   `ADR-NNNN` ids `$PLAN` cites**, matched as a whole token with the same anchor pair the basename
   half already uses: `(^|[^A-Za-z0-9_])<needle>([^A-Za-z0-9_]|$)`.

The key set is built once per run, from `$PLAN`, into one alternation. The ADR ids are collected by
the same both-sides-anchored token scan the file already uses for `R-NN` — `ADR-` followed by
exactly four digits, left-anchored on a non-word character and right-anchored on a non-digit — not
from a designated header line. §A4 records why the narrower source was rejected for now and what
would license it later.

The OR is by measurement, not by preference: harnesses in this corpus name the ADR more often than
the plan, `plant-registry-parallel.test.sh` names `2026-08-17-447-shard-the-plant-registry` without
its extension and would be dropped by the plan half alone, and requiring the plan alone was never
measured.

One definition of "what is a test file" survives (rule 6, ADR-0086): half 2 filters the same
`$TESTFILES` half 1 filters, and never re-derives the discovery predicate. The `.md` exclusion
therefore stays closed for free.

### D2 — an empty scope now has two causes, and they get two different reports

Today's D2 guard fires on `[ ! -s "$TESTFILES_SCOPED" ]` and treats every empty scope as a possibly
broken derivation: it prints `SCOPE-EMPTY` on stderr and falls back to the unscoped population.
Under a conjunction that answer is wrong half the time, and it blames the wrong thing.

- **`SCOPE-EMPTY` (unchanged).** Half 1 matched nothing: the plan names no discovered test file at
  all. Zero candidates out of a non-empty discovered population is the rule-7 case — the derivation
  may be broken, and from outside a broken derivation and a clean zero look identical. Fails open
  and visible, exactly as before, falling back to the unscoped population.
- **`SCOPE-NO-BACKREF` (new).** Half 1 matched one or more files and half 2 dropped **all** of
  them. Nothing here is broken: the derivation resolved and its answer is that no file the plan
  names claims this feature. That is a finding, not a vacuity, so it **does not fall back**. The
  scope stays empty, ids mentioned only in the dropped files report `UNSCOPED`, and the run exits 1
  with the stderr line naming the dropped file(s) and the one-line remedy: add the plan's basename
  or its ADR id to one of them.

Collapsing the second into the first is what this decision refuses. "The plan names no test file"
and "the plan names test files that disown it" carry opposite remedies — write a citation into the
plan, versus write one line into a harness — and a gate that prints the wrong one costs more than a
gate that prints nothing.

### D3 — the new state is a stderr token; stdout's vocabulary and every exit code are unchanged

`SCOPE-NO-BACKREF` is a per-**run** state, exactly like `SCOPE-EMPTY`, and it lives on the same
channel for the same reason: stdout's vocabulary is per-**id**, and an id whose only mention now
sits in a dropped file already has the correct per-id verdict and the correct per-id remedy —
`UNSCOPED`, exit 1, "cite the id in the test file this feature actually wrote".

`COVERED`, `UNCOVERED`, `UNSCOPED`, `DUPLICATE`, `MALFORMED`, `ORPHAN` and `STALE-WAIVER` keep
their meanings, their columns and their exit codes. No new exit code. The stderr summary line gains
one trailing clause (the count dropped by half 2) and loses none of its existing fields.

### D4 — the derivation's denominator guard is corpus-level, lives in the harness, and is declared a vacuity guard

The back-reference derivation is a population, so rule 7 applies: a bug that made every file fail
half 2 would collapse the scope everywhere, and 187 changed baseline rows read as a rewrite rather
than as a collapse.

The guard cannot live inside the script: per run, zero files passing half 2 is a **legitimate**
answer — it is precisely §D2's new state — so an in-script floor would have to fire on the state
the script exists to report. It is therefore corpus-level, in `spec-coverage.test.sh`, asserting
that the pairing still resolves at least one back-referencing scoped file on at least 15 of the
corpus's (SPEC, plan) pairs.

It is declared **at its site** as a vacuity guard and not as the evidence, because a floor absorbs
its own plant (rule 10, ADR-0124): `>= 15` against 16 pairs still passes when one pair is removed.
The regenerated per-row baseline is where a plant actually bites.

### D5 — the baseline is regenerated under the new rule, and rule 14 is honoured in the header, not by freezing wrong rows

`spec-coverage-scope-baseline.tsv` keeps its shape: one row per (SPEC, declared id) pair,
`COVERED` rows in three columns, `UNSCOPED` rows in five (`<class>`, `<reason>`).

Its rows record a measurement **under a rule**. When the rule changes, a row that keeps the old
verdict is not a preserved historical record, it is a red assertion: `RS7` compares each row
against the live checker on every run. So the rows are regenerated, and rule 14 is honoured where
it can be — in the file's header, by a dated block that states what was regenerated, on what date,
under which ADR, with the row-count delta and the per-row accounting. The 2026-08-14 measurement
sentence already in that header is not rewritten.

**A `COVERED` → `UNSCOPED` flip that is not a precedent citation halts the feature.** M4 predicts
zero flips of any kind; a flip whose dropped file genuinely belonged to that feature would mean
half 2's key set is too narrow, and the correct response is to re-open §D1, never to re-freeze the
row.

### D6 — the producer-side convention is stated once, in the architect's own output contract

A plan names the harness it creates, and that harness names the plan or its ADR back. That belongs
in `staging/plugin/agents/architect.md`, beside the requirement-id citation contract it extends —
one place, on the producer side. It is deliberately **not** also written into the concept-to-code
Step 2 dispatch brief: two copies of one convention diverge, and the extraction criterion
(ADR-0086) says copies that must answer the same question get one home.

That line is an **instruction, not an enforcement** (rule 16). Nothing checks that a plan obeys it,
and the harness assertion that pins it proves only that the sentence is present. What *is* enforced
is the consequence, and it is unusually direct for an instruction of this kind: a harness that does
not name its feature back descopes itself, its feature's ids report `UNSCOPED`, and the Step 5 gate
exits 1 with the remedy. The instruction is advice; the gate is the teacher.

### D7 — what this decision does not fix, stated rather than implied

Two residual classes survive, both narrower than today's exposure and both measured:

1. **The same-file namespace collision (M3).** A file that legitimately back-references still
   carries every `R-NN` token in its own fixture and label namespace. On this feature's own SPEC
   that supplies 8 of 12 ids before any work exists. Narrowing it further means requiring the
   mention to sit somewhere structural — an assertion line, an id-mapping comment header — and
   that is the candidate ADR-0138 measured and refused (§A2). Left open, deliberately.
2. **Precedent ADR citations as back-reference keys.** A plan citing `ADR-0108` admits any
   back-referencing harness that also discusses `ADR-0108`. Measured 2026-08-18: 7 of 74 plans cite
   `ADR-0108`, and 9 test files carrying `R-NN` ids name it, one of which (`plant-check.sh`) is not
   discovered as a test file at all. The exposure requires **both** halves — the plan must name the
   file *and* the file must cite that same ADR — which is why it is narrower than what it replaces
   rather than a new door.

Pre-registered narrowing for class 2, so the next measurement has something to answer: if a
baseline regeneration or a Step 5 run ever shows a `COVERED` verdict resting only on a file whose
back-reference is a **precedent** ADR the plan cites (not the plan's own ADR, not the plan's
basename), narrow the key set to the plan basename plus the ADR named in the plan's own
`- **ADR:**` header bullet, and re-run the baseline. Not done now because it is unmeasured and
would risk flips the adopted rule demonstrably does not have.

### D8 — this feature's own SPEC blocks its own gate today, and the fix is the operator's at Gate 2

Verified 2026-08-18 by running the gate against `SPEC.md` and a stub plan:

```
STALE-WAIVER  R-10
STALE-WAIVER  R-11
STALE-WAIVER  R-12
exit 3
```

`R-10`, `R-11` and `R-12` carry `(no-test: …)`, and all three tokens appear inside
`spec-coverage.test.sh` as `RC3`/`RC4` fixtures. ADR-0138 §D4's reverse check reads that as an
exemption that no longer protects anything and reports a structural error, so the Step 5 → Step 6
gate exits 3 **before any of this feature's code exists**, and no code change in this feature can
clear it: the tokens are already there, and the fallback path finds them too.

The remedy the checker itself prints is the right one, with one addition. Drop the three
`(no-test: …)` clauses from `SPEC.md`, **and** give the three ids real existence-level assertions —
the ADR exists and records both refused designs with their numbers; the `docs/chain-decisions.md`
block, the `CLAUDE.md` index line and the `PROJECT.md` row exist. Dropping the clause alone would
leave three ids reading `COVERED` off a fixture collision, which is the defect wearing the remedy's
clothes.

`SPEC.md` is outside the architect's write scope, so this is the operator's edit at Gate 2. It is
recorded here because a chain that reaches Step 5 without it halts on an exit code that looks like
a defect in the work and is not.

## Alternatives considered

### A1 — scope to the files a plan's `Budget:` lines name

**Rejected on measurement.** Only 11 of 53 plans name a test file in a `Budget:` line, so 42 of 53
would resolve to an empty scope and the §D2 denominator guard would refuse them. A rule that
refuses four fifths of the corpus is not a narrowing, it is a disablement with extra steps.

### A2 — require the id mention to sit in an id-mapping comment header

`# NT7/NT8 (R-07, R-10) — …`. **Rejected on measurement, twice over.** 87 of 893 `R-NN` mentions in
`staging/plugin/scripts/tests/*.sh` have that form and 22 of 31 files carrying ids have none, so
most genuine coverage would flip to uncovered. This is the same wall ADR-0138 hit with its own
candidate, which measured 49 of 93 genuinely-covered ids as comment-only, and the architect's
durable note of 2026-08-14 states the general form: *any future rule treating a comment mention as
non-evidence will fail the best-tested features.*

### A3 — match the plan's basename without its `.md` extension

**Rejected on measurement.** The stem is not a token boundary under this anchor pair: `-` and `.`
are both non-word characters, so `2026-05-23-clean-public-repo-anonymize` matches
`2026-05-23-clean-public-repo-anonymize.manifest.yml` (3 mentions in the corpus) and would match a
hypothetical sibling plan whose name merely extends another's. Requiring the extension closes both.
The single corpus file that names a plan without the extension is covered by the ADR half of the
OR, which is one of the reasons the OR exists.

### A4 — restrict the ADR key to the plan's own ADR, read from its header bullet

Both sampled plans carry `- **ADR:** docs/architecture/ADR-NNNN-….md` above every task, so this is
implementable. **Rejected for now**: it was not the rule M4 measured, it strictly shrinks the key
set, and every file it removes from scope is a candidate flip that M4's zero does not cover. Kept
as the pre-registered narrowing in §D7 with a stated trigger, rather than adopted on the strength
of an argument.

### A5 — treat `SCOPE-NO-BACKREF` like `SCOPE-EMPTY` and fall back to the unscoped population

**Rejected.** It re-opens the exact defect this ADR closes, and does so in the quietest possible
way: an unattended Step 5 would see exit 0 and a stderr line, and the feature would ship with the
pre-ADR-0138 repository-wide scan silently restored for that run. The cost of the alternative is
one line in a harness, written by the agent that owns that file anyway.

### A6 — give the new state its own per-id stdout token

**Rejected.** The state is per run, not per id. The per-id verdict for the ids affected is already
correct (`UNSCOPED`) and already carries the remedy that fits. A second per-id token would add a
value to a stdout vocabulary that four consumers read, to say something none of them can act on
differently.

### A7 — put the back-reference denominator guard inside `spec-coverage.sh`

**Rejected as self-contradictory.** Per run, zero files passing half 2 is a legitimate, meaningful
answer — it is §D2's new state. An in-script floor would fire on the very state the script exists
to report. The guard belongs where a *population* exists, which is the corpus loop in the harness
(§D4).

### A8 — extract the back-reference matcher into a shared helper

**Rejected by the extraction criterion (ADR-0086).** One consumer means one file. A shared source
that fails disables every consumer at once, and there is no second consumer here to disagree with
the first.

### A9 — fix the same-file namespace collision (M3) in this feature

**Rejected as out of scope and unmeasured.** The SPEC's Out list excludes the discovery predicate
and the waiver mechanism, and the only candidate mechanisms for distinguishing a feature's own
mention from a fixture token inside the same file are the ones §A2 refuses. Recorded in §D7,
recommended as its own issue with M3 as its opening measurement.

### A10 — write the convention into the Step 2 dispatch brief as well as the architect contract

**Rejected.** Two copies of one convention answer one question, which is exactly the case ADR-0086
says must be extracted rather than duplicated, and this repository has three separate ADRs written
because two copies drifted. The architect's output contract is the producer side; the dispatch
brief consumes it.

## Consequences

### Positive

- The precedent-citation door closes: 94 of 263 scoped files across 52 plans leave the test axis,
  with zero measured loss of genuine coverage.
- The two empty-scope causes stop being one state, so the gate's remedy names the actual defect.
  The new one is a one-line fix in a file the tester already owns.
- A harness that does not name its feature back now descopes itself and blocks, which turns the
  §D6 instruction into a self-enforcing convention without adding an enforcement mechanism.
- The M4 proxy is retired by the deliverable rather than carried as an open caveat: the regenerated
  baseline is the SPEC-parsed re-derivation the flip measurement approximated.
- This feature applies its own rule to itself. Its plan names its harness; its harness names this
  ADR back; if either stops being true, its own gate says so.

### Negative

- The gate can now block on a state that is not a defect in the work: a feature extending a shared
  harness sees `SCOPE-NO-BACKREF` until one line is added. This is the intended trade (§A5) and it
  costs a round trip the first time an author meets it.
- The same-file collision (M3) is untouched, and this feature's own gate demonstrates it at 8 of 12
  ids. A green `COVERED` remains a statement about a citation's *origin*, not about an assertion's
  existence — ADR-0138's title-level lesson survives this ADR intact.
- Precedent ADR citations remain back-reference keys (§D7 class 2). The exposure is measurably
  narrower, not gone.
- The baseline's rows are rewritten under a new rule, which is the one place this feature bends
  rule 14. The bend is bounded to the rows, disclosed in a dated header block, and forced by the
  fact that a stale row is a red assertion rather than a preserved record.
- One more `grep` per plan-named test file per run. Bounded by the number of files half 1 already
  admits — 6 to 7 on a real plan — and unmeasurable next to the `find` over the repository that
  precedes it.

### Neutral

- No new file, no new helper, no new dependency, no manifest field, no PAIRS entry, no CI append:
  `spec-coverage` is already in the `docs-ci.yml` shell-tests list and `spec-coverage.sh` is
  already deployed by PAIRS.
- The plan axis, the discovery predicate, the `--list` mode, the silent no-ids path and the
  `(no-test: …)` waiver behave exactly as before.
- `staging/plugin/agents/architect.md` changes, so `staging/sync-to-claude.sh --apply` must run
  before the deployed agent carries the new contract line. Until then the dry run reports drift —
  the ordinary vendored-file consequence, not a defect.

## References

- ADR-0138 — the test axis is tightened by scope, not by assertion shape (the decision this narrows)
- ADR-0048 — requirement-id coverage as a blocking Step 5 → Step 6 gate
- ADR-0086 — the extraction criterion: extract only when two copies giving different answers would be a defect
- ADR-0085 — guard the denominator, not only the matches
- ADR-0124 — a floor absorbs its own plant; prefer a frozen per-item baseline
- ADR-0108, ADR-0149 — the plant registry and its declaration grammar
- ADR-0088 — test authoring splits at sub-task granularity
- ADR-0101 — batch-boundary precedence: evidence quality beats checkpoint tidiness
- ADR-0153 — the plan M1 was measured on
- CLAUDE.md rules 6, 7, 8, 10, 12, 13, 14, 16, 18
