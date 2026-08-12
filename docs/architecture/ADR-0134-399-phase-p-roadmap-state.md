# ADR-0134 — Bind Phase P step 3 to the roadmap state and the run scope

- **Status:** Accepted
- **Date:** 2026-08-11
- **Issue:** #399 (`chain-blocker`), Phase 12 Wave 3 row 1
- **Supersedes / amends:** ADR-0023 (Phase P step 3's selection rule), ADR-0129 §D7 **in part** —
  only the clause keeping the scope away from `PROJECT.md`, and only for Phase P step 3. The rest
  of §D7 stands.
- **Related:** ADR-0129 (run scope), ADR-0132 (skill-argument substitution), ADR-0133 (fence
  execution shell), ADR-0106 (SPEC archive namespace), ADR-0086 (extract-or-copy criterion),
  ADR-0085 (guard the denominator), ADR-0113 (the CI named list).

---

## Context

`autopilot` Phase P step 3 decides which features get a generated SPEC by reading exactly one
thing — whether `docs/specs/<slug>.spec.md` exists — for every row of `docs/specs/_issue-map.tsv`.
It reads neither the row's state in `PROJECT.md` nor the run scope Phase S resolved minutes
earlier. Two consequences, both observed on the 2026-08-07 run (`docs/AUTOPILOT-RUN-AUDIT-2026-08-08.md`):

- a **completed** feature whose SPEC was never archived under the map's slug is indistinguishable
  from a pending feature that needs one, and gets a fresh SPEC describing work already shipped,
  written into the same `docs/specs/` namespace ADR-0106 uses as the archive;
- a run launched `--features 1 --only 294` still paid prep across the whole map. **ADR-0129 bounded
  what a run implements and left what it designs unbounded.**

### Measured facts, re-derived 2026-08-11 (R-09)

Every figure below was re-derived from this repository rather than carried over from the SPEC or
the issue. **Four of them moved, and two of the four change the design.**

| # | Fact | Value | How |
|---|---|---|---|
| 1 | Map rows | **74** | `wc -l docs/specs/_issue-map.tsv` |
| 2 | Map rows with no `docs/specs/<slug>.spec.md` | **4** — `#363`, `#364`, `#365`, `#366` | per-row `test -f` over the map's own slug field |
| 3 | State of those four in `PROJECT.md` | **all four `- [x]`** | row-shaped grep on `(issue #N)` |
| 4 | Map rows matching a **row-shaped** `PROJECT.md` line | **74 of 74**, exactly one each | `grep -cE '^[[:space:]]*- \[.\].*\(issue #N\)'` |
| 5 | Map rows matching a **file-wide** `grep -F "(issue #N)"` | **72 unique, 2 with two hits** — `#365`, `#366` | `grep -cF` per row |
| 6 | State histogram over the 74 map rows | `[ ]` **27**, `[x]` **47**, `[~]` **0** | row-shaped grep |
| 7 | Pending (`[ ]`) rows with no SPEC | **0** | facts 2 and 3 combined |
| 8 | `roadmap-from-issues.sh` issue query | `--state open` (`:57`) | read |
| 9 | `roadmap-from-issues.sh` roadmap row form | `- [ ] <title>  (issue #N)` (`:103`) — every row pending | read |
| 10 | `prep.test.sh:11` `no()` emitter | `echo "FAIL $1"`, **no colon** | read |

**Correction 1 (fact 2) — it is 4, not 3.** The SPEC states 3, on the ground that `#365` "has since
gained `docs/specs/365-*.spec.md`". A file matching that glob does exist —
`365-scope-and-bound-the-autopilot-run.spec.md` — but step 3's predicate is not a glob. The map's
slug for that issue is `365-a-nightly-run-cannot-be-scoped-to-a`, and
`docs/specs/365-a-nightly-run-cannot-be-scoped-to-a.spec.md` does not exist. **The SPEC's figure
was measured with a predicate the step does not use.** The `4` matches the audit's own count for
the 2026-08-07 run, independently.

**Correction 2 (facts 4 and 5) — the duplicate case is live, and a file-wide matcher gets the two
rows that matter most exactly wrong.** `PROJECT.md` carries section headings of the form
`#### Wave 1 — bound the run (issue #365)` alongside the roadmap rows. A file-wide
`grep -F "(issue #365)"` therefore returns **two** lines: one roadmap row and one heading. Under a
file-wide matcher, `#365` and `#366` would take either the duplicate branch or — worse — the
heading has no `[ ]` marker at all, so the "unrecognised state" branch, which this ADR resolves
**fail-open**, i.e. *selected*. The two rows a state check most needs to suppress would be the two
it fails to suppress. Under a row-shaped matcher every one of the 74 rows matches exactly once.

**Correction 3 — the SPEC's edge case "Phase S already aborts the launch for an unresolvable
`--only` token before Phase P runs" does not reproduce, and it contradicts the SPEC's own measured
phase order.** Phase S *parses* the tokens (`scope-args-parse.sh`); it resolves nothing. Resolution
is Phase 0 **check 9** (`autopilot-scope-resolve`), and the phase order is S → M → P → 0, so check
9 runs **after** Phase P. An unresolvable token therefore *can* reach the helper. §D6 below settles
what it does there.

**Correction 4 — the SPEC's "All 27 open `prep`-labelled issues already have a SPEC" is confirmed
only in the form measurable offline.** All 27 `[ ]` map rows are covered (facts 6 and 7). Whether
the 27 open `prep`-labelled issues are the same 27 rows needs `gh` and was not verified; the map is
stale by construction (see below), so the two sets are not guaranteed equal. The design does not
depend on it.

### Two facts that are the mechanism, not background

- **The map is stale by construction.** Phase P step 2 is conditioned on `PROJECT.md` being
  *absent*; `PROJECT.md` has existed here for months, so step 2 always skips, so
  `docs/specs/_issue-map.tsv` is never regenerated and keeps rows for issues closed long ago. A
  regenerated map would not contain them (fact 8).
- **The auto-design path is safe by construction, not by a special case.** Where step 2 *does* run,
  it generates the roadmap moments before step 3 reads it, and every generated row is `- [ ]` (fact
  9). A state check passes all of them. R-03 needs no branch.

### What this repository looks like after the change

R-01 alone takes this repository's generation count from **4 to 0** (facts 2 and 3). There is no
row here where a state check would wrongly suppress a SPEC that is genuinely needed. R-02's cost
saving is likewise invisible here and visible only on a fresh backlog. **That is worth stating
plainly: a green run of this feature on this repository proves the suppression, not the
generation** — the generating half is exercised by fixtures only.

---

## Decision

### D1 — The decision lives in a skill-private helper, not in the fence

`staging/plugin/skills/autopilot/scripts/prep-row-select.sh`, deployed to
`~/.claude/skills/autopilot/scripts/` through a `PAIRS` entry. Direct precedent in this same skill:
`scope-args-parse.sh` (ADR-0132 §D2).

The reason is not length. **A TSV parse is written with awk field references, and an awk field
reference is a positional-parameter token in a rendered document** — `$1`, `$2`, `$3` are exactly
the tokens Claude Code substitutes the skill's own invocation arguments into before the body
reaches the model (ADR-0132). A three-column map cannot be parsed inside a rendered fence without
either reintroducing that defect or writing a field-free contortion. A file is never rendered.

The fence that consumes it stays in `SKILL.md` — resolution, exit-code branching and the operator-
facing halt message — because ADR-0132 §D2's rule is *excise the case, not the fence*: a human
approving an overnight launch reads the mechanism at the point of decision.

### D2 — Contract: a SELECTOR

Stated in the helper's own header, because the two neighbouring contracts in this tree are
different things:

```
prep-row-select.sh --root <project-root> [--only <csv>]
```

- **exit 0** — the selection RAN. Stdout carries zero or more map rows to generate, one per line,
  in the map's own `slug<TAB>num<TAB>title` form. **An empty list at exit 0 is a normal, common
  result** and means every row is already covered, already completed, or out of scope.
- **exit 2** — bad invocation.
- **exit 3** — the selection DID NOT RUN: the map or `PROJECT.md` could not be read, or the
  denominator guard tripped.

It is not a CHECKER (the caller does branch on the exit code, but the payload is the answer, not
the verdict) and not a REPORTER (it does not always exit 0, and it prints no `CLEAN` sentinel — it
must never grow one).

**Channel separation is part of the contract: stdout carries rows and nothing else; every note and
the summary line go to stderr.** Stdout is consumed as data by the fence, so a note on stdout is a
phantom row. This diverges from the sibling fences `autopilot-scope-args` and
`autopilot-scope-resolve`, whose `SCOPE-PARSE:`/`SCOPE-RESOLVE:` lines go to stdout — their stdout
is read by a human, not by a program. The divergence is deliberate and is written at both sites.

The summary line is `PREP-SELECT: map_rows=… matched=… selected=… covered=… completed=… skipped=…
out_of_scope=… orphan=… unrecognised=… duplicate=…` on stderr.

### D3 — The state predicate is ROW-SHAPED, and the marker character is captured, not assumed

A `PROJECT.md` line counts as this map row's state line only if it matches

```
^[[:space:]]*- \[.\][[:space:]].*\(issue #<num>\)
```

— a checklist row, with the marker character captured as *whatever it is* rather than restricted to
`[ xX~]`. Two consequences, both deliberate:

1. The `#### Wave N — … (issue #N)` headings that produce fact 5's two-hit rows are excluded, so
   `#365` and `#366` classify correctly.
2. **The "unrecognised state" branch is reachable.** Had the predicate been restricted to `[ xX~]`, a
   row marked `- [?]` would simply not match and would take the *orphan* branch instead — and the
   unrecognised branch the SPEC names would be dead code. A branch a specification names and no
   input can reach is worse than no branch: it reads as covered.

Classification: `x`/`X` and `~` → **not selected**. Space → pending, continue. Anything else →
**selected**, reported as `UNRECOGNISED-STATE`.

### D4 — Failure direction, per case

| Case | Behaviour | Reason |
|---|---|---|
| Row `[x]` or `[~]` | not selected | a completed or permanently-skipped feature is never implemented again; a SPEC generated for it describes shipped work, into the ADR-0106 archive namespace |
| Row `[ ]`, SPEC absent | **selected** | today's behaviour, unchanged |
| Row `[ ]`, SPEC present | not selected | today's coverage rule, unchanged |
| Issue number in no row-shaped line | **selected**, reported `ORPHAN` | fail-open: generating for an unplanned feature costs a file; suppressing one that was needed loses it invisibly |
| Marker character outside `[ xX~]` | **selected**, reported `UNRECOGNISED-STATE` | same direction, same reason |
| Two row-shaped lines, same issue | first wins, reported `DUPLICATE` | silently picking one of two conflicting states is how a wrong answer looks correct |
| `--only` present, row outside it | not selected | R-02 |
| `--only` token matching no map row | reported `UNRESOLVED-TOKEN`, **never an abort** | §D6 |
| Map or `PROJECT.md` unreadable | exit 3 | the selection did not run |
| Map non-empty, **zero** rows matched | exit 3 | broken predicate, not an empty result |
| Map empty | exit 0, empty stdout, guard not applied | an empty map is an empty result |
| Helper not deployed | **Phase P halts**, printing the sync command | §D8 |

**The partial/total split is the design, and it is worth reading as one thing.** A *single* row that
fails to match falls open and is reported; if *every* row fails to match, that is not 74 verdicts
about 74 rows, it is one broken predicate, and the helper exits 3. That is ADR-0085's rule applied
to a new population: guard the denominator, because zero matches and zero generations print the
same thing otherwise.

### D5 — The denominator is EVERY map row, not the rows that survive the filters

State is resolved for all 74 rows before any filtering, and the guard's denominator is that full
set. The alternative — resolve state only for rows that passed `--only` and the coverage check —
was rejected because it makes the guard's strength depend on how much of the map happens to be
covered: on this repository today only 4 rows would reach the state step, and a `--only 294` run
would leave a single row as the entire denominator. A guard that can be reduced to n=1 by an
unrelated argument is not a guard. Resolving all 74 costs one awk pass over `PROJECT.md`.

### D6 — `--only` matches the MAP's own fields; it never re-derives a slug, and it never aborts

A token selects a map row when it equals that row's `num` field or its `slug` field, both exact.
**No slug is recomputed from a title anywhere in this helper** (ADR-0069's rule: a second
derivation of one value is a defect waiting for the two to disagree).

An `--only` token matching no map row is reported on stderr and the run continues. It is **not** an
abort, for a reason that is structural rather than lenient: **Phase 0 check 9 is the sole authority
for aborting a launch on an unresolvable token**, and it resolves against `PROJECT.md` while this
helper resolves against the map. Two authorities answering "is this token resolvable" from two
different populations would be two answers that can disagree (ADR-0086's criterion). The two
populations legitimately differ — a hand-written roadmap row carrying no issue marker resolves by
slug in check 9 and has no map row at all, which is correct, because Phase P has nothing to
generate for it.

Note that check 9 runs *after* Phase P (correction 3), so a genuinely bad token costs one Phase P
before the launch stops. That is the pre-existing phase order and this ADR does not change it.

**`--features` does not bound step 3.** That argument counts publishes; using one number for two
questions is the defect class issue #242 already cost this repository.

### D7 — ADR-0129 §D7's exclusion is lifted for this one step, and the distinction is written at the step

§D7 keeps Phase S away from `PROJECT.md` because in auto-design mode the roadmap does not exist at
Phase S time. **That reason does not extend to Phase P step 3**, which runs after step 2 has
generated the roadmap: `PROJECT.md` exists there on every path. The step carries a sentence saying
so, and saying that §D7 is not being contradicted, so a later reader does not read §D7 as covering
it and "fix" the reference back.

### D8 — An unresolved helper HALTS Phase P; there is no fallback

The fence resolves the helper two-tier (`CLAUDE_PLUGIN_ROOT` first, then `$HOME/.claude`) and, on
failure, prints the sync command and exits non-zero. **It does not fall back to today's
generate-every-uncovered-row behaviour**, and the message says why: a fallback would restore
exactly the unbounded behaviour the step exists to remove, on the machine least likely to notice.

Exit vocabulary, mirroring the helper so the fence is a transparent conduit: **3** = did not run
(helper absent, or helper rc 3), **2** = bad invocation (helper rc 2), **0** otherwise. Phase S's
fence uses 3 for did-not-run and Phase M's uses 1 for the same state. **The three are not
reconciled and must not be** (ADR-0132 §D4): each fence carries its own exit vocabulary and its own
tests assert it, and a consistency pass that renumbers any of them changes a contract.

### D9 — The fence carries the ADR-0133 §D1 wrapper and no positional-parameter token

The body sits between `bash <<'FENCE_BASH'` and a **column-0** `FENCE_BASH` terminator, with an
`export _root _scope_only CLAUDE_PLUGIN_ROOT` prologue for its free variables. This is not style:
the Bash tool executes a fence under the host shell (zsh 5.9 here), and the fence branches on
`[ -n "$_scope_only" ]` and reads command substitution exit codes — and, more to the point, a
declared fence contract that lacks the wrapper is a `fence-contract-coverage.test.sh` WS failure by
construction. The terminator's column-0 position survives the fence being indented inside a
numbered list item; an indented terminator is swallowed into the here-document and destroys the
fence's exit code silently.

The fence branches on `[ -n "$_scope_only" ]` rather than always passing `--only "$_scope_only"`,
mirroring `autopilot-scope-resolve`'s own branch and for its stated reason: the two readings of
"empty" are the difference between an unscoped run and a run that does nothing.

### D10 — Which half is code and which half is instruction

**Code, enforced:** the helper selects the rows; the fence resolves it, branches on its exit code
and prints the selected rows as `PREP-SELECT-ROW:` lines.

**Instruction, NOT enforced:** the per-row `Skill(skill="spec-from-issue", args="<issue#> --slug
<slug>")` invocation stays prose in `SKILL.md`. A model reads the fence's output and issues one
`Skill()` call per line. Nothing stops it from issuing a call for a row the fence did not print, or
from skipping one it did. What changes is that the list is now computed by code with a stated
contract instead of derived ad hoc from a glob — the failure shape moves from *silently wrong list*
to *a list on screen that a reader can compare against what was generated*. This ships an
instruction, not an enforcement, and the ADR says so rather than letting a green harness imply
otherwise.

### D11 — The morning report gains no field, and a suppressed row is counted in neither existing one

`features_generated` counts what was generated; `features_skipped_thin` means `spec-issue-gate.sh`
refused a thin issue. A row suppressed because it is completed or out of scope is **neither**.
Overloading `features_skipped_thin` would make a morning report state that issues were thin when
they were finished. Adding a field means a schema v2.1 bump and touching its consumers, for a
number that is already on screen in the helper's `PREP-SELECT:` summary line. No schema change.

### D12 — The assertions live in a new harness, `prep-row-select.test.sh`

`staging/plugin/scripts/tests/prep-row-select.test.sh`, hermetic, offline, targeting `staging/`
directly. Its `bad()` prints **`FAIL: <id>`** with the colon `plant-check.sh` attributes on —
`prep.test.sh:11` prints `FAIL <label>` without it (fact 10), which makes every plant declared there
unattributable, and is why the SPEC forbids putting these assertions in that file.

Assertion ids are **fixed-width** (`PRS01`…`PRS23`, floor `PRS99`), so no id is a prefix of another.
`plant-check.sh` attributes a fired plant with `grep -q "^FAIL: $aid"` — a prefix match — so a
plant for `PRS1` would be satisfied by `PRS10` failing.

**R-08's CI half is guarded by an existing assertion, and a second one is refused.**
`pairs-completeness.test.sh` `CI1` already derives every staged harness and requires it to be named
in `docs-ci.yml`'s `shell-tests` list or to carry a `# ci-dark-exempt:` declaration. Adding the new
file without the CI append turns `CI1` red on its own. A second guard inside the new harness would
be two answers to one question (ADR-0086) — and it would fail in every `plant-check.sh` sandbox
anyway, since the sandbox copies `staging/` and `docs/` and `.github/workflows/` is in neither
(ADR-0122's `RG1` class).

**`pairs-completeness.test.sh` is structurally blind to a skill-private `scripts/` file** (ADR-0043:
its population is the non-recursive `plugin/scripts/*.sh` glob), so the helper's `PAIRS` entry is
pinned by a direct assertion in the new harness (`PRS22`) instead.

### D13 — Out of scope, stated as decisions

- **Refreshing the stale map.** After D3/D4 its staleness is harmless — the state check suppresses
  every closed row — and regenerating it means running `roadmap-from-issues.sh`, which rewrites
  `PROJECT.md` as well. This repository's `PROJECT.md` is a hand-curated 14-phase roadmap.
- **Fixing `prep.test.sh`'s colon-less `FAIL`.** One of four such files, with its own ledger entry.
  Converting one of the four here leaves the class open and looks closed.
- **The coverage-predicate divergence (found on the way, not asked for).** Step 3 tests
  `docs/specs/<slug>.spec.md` exactly; its downstream consumer `project-conductor` globs
  `docs/specs/<issue>-*.spec.md` and takes `head -1` (`project-conductor/SKILL.md:574`). The two
  disagree whenever a SPEC exists for an issue under a slug other than the map's — which is exactly
  what produced correction 1. Generating under the map slug when a differently-named SPEC already
  exists would give the conductor two candidates and an arbitrary `head -1`. **Not fixed here:** it
  is a coverage question, not the state-and-scope question this feature asks; today's rule is
  preserved deliberately (the SPEC's own "today's behaviour, unchanged"); after D4 it is moot on
  this repository, since all four uncovered rows are `[x]` and suppressed by state under either
  predicate. Filed as a follow-up.
- **Check 9's file-wide matcher (found on the way, not asked for).**
  `autopilot-scope-resolve` resolves `--only` with a file-wide `grep -F "(issue #N)"` and counts
  lines, so on this repository **`--only 365` and `--only 366` abort the launch as "ambiguous"**
  (fact 5). Real, reproducible, and in a different phase with a different contract; its failure
  direction is the loud one. **Not fixed here** and deliberately **not pinned by an assertion** —
  an assertion recording a defect as expected is what ADR-0070 had to unwind in `BB2`. Filed as a
  follow-up.
- **Phase P step 4's missing "nothing generated" branch.** The second Wave 3 row; its own issue.

---

## Alternatives considered

**A1 — Read the state inside the fence, no helper.** Rejected. A three-column TSV parse wants awk
field references, which are positional-parameter tokens in a rendered document and are precisely
what ADR-0132 removed from this file. A field-free contortion would be a second, worse copy of a
parse the tree already knows how to write in a script. `skill-fence-positional-tokens.test.sh`
would reject it outright.

**A2 — Write the state into `_issue-map.tsv` as a fourth column at generation time.** Rejected on
staleness: the map is written once and never regenerated (the mechanism above), so a state column
would be frozen at generation and would answer the question with a snapshot months old — the exact
defect being fixed, cached. It also puts the answer in the artifact rather than in the reader,
which means every later consumer inherits the snapshot.

**A3 — Suppress by "the issue is closed on GitHub" instead of by roadmap state.** Rejected. It adds
a network call to a phase that has none, fails differently when `gh` is unauthenticated (and the
gh-auth wall is Phase 0, *after* Phase P), and asks a different question: `[~]` means *a human
decided to skip this*, which no issue state expresses. `PROJECT.md` is the roadmap this run is
driving; it is the right authority.

**A4 — Have the helper abort on an unresolvable `--only` token, matching check 9.** Rejected: two
authorities resolving one question against two different populations (§D6). It would also abort
correctly-scoped runs on hand-written rows that have no map entry, which is a legitimate shape.

**A5 — Read the on-disk `.claude/autopilot-state/scope` file instead of Phase S's parsed values.**
Rejected on ordering, measured: that file is written by Phase 0 **check 9**, which runs after
Phase P. At Phase P time it either does not exist or holds the *previous* run's scope — the second
being the dangerous half, since it reads as a present, valid bound. Phase S's in-session values are
the only correct source at this point.

**A6 — Bound step 3 by `--features N` as well as `--only`.** Rejected: `--features` counts
publishes, not rows, and ADR-0129 §D4 defines a slot as consumed by a publish. Using it to cap
design work is one number answering two questions — issue #242's class, which this repository has
already paid for once.

**A7 — Fail CLOSED on an orphan or unrecognised state (do not select, report).** Rejected as the
wrong direction for this step, though it is the right direction for a pre-flight. A wrongly
generated SPEC is a file in a directory, visible in the prep commit and deletable. A wrongly
suppressed SPEC is a feature whose chain later finds no design input, at 3am, with the reason
several phases upstream. The total-breakage case is caught by the denominator guard (§D4), so
fail-open here is bounded rather than unconditional.

**A8 — Put the new assertions in `prep.test.sh`, which already covers Phase P's other steps.**
Rejected: it prints `FAIL <label>` without the colon, so every plant declared in it is
unattributable — `plant-check.sh` classifies that as a `BADPLANT`, i.e. *the registry could not
run*. R-04 requires the RED to be produced by an attributing plant, which that file structurally
cannot do. Converting it is D13's out-of-scope item.

**A9 — Add a `features_skipped_completed` field to the morning report.** Rejected: schema v2.1
bump plus consumer changes, for a number already printed on the `PREP-SELECT:` summary line. See
§D11.

---

## Consequences

### Positive

- Phase P stops writing SPECs for shipped features. On this repository the count goes 4 → 0
  immediately, with no case where a needed SPEC is suppressed (facts 2, 3, 7).
- A bounded run is bounded end to end. `--only` now governs what the run *designs* as well as what
  it *implements*, closing the half ADR-0129 left open.
- The selection becomes a stated contract with an exit vocabulary, executed by a test, instead of a
  glob evaluated in prose. "Did not run" is distinguishable from "found nothing".
- The row-shaped predicate makes `#365` and `#366` classify correctly today, where a file-wide
  matcher — the obvious implementation, and the one check 9 uses — gets both wrong.
- The unrecognised-state branch is reachable and tested, rather than named and dead.

### Negative

- **Two new hard dependencies on a deployed file, and Phase P is worse than inert until sync.**
  Until `bash staging/sync-to-claude.sh --apply`, the fence exits 3 and **halts Phase P** on every
  auto-design run. That is the chosen direction (§D8) and it will read as a regression the first
  time.
- **A green run of this feature on this repository proves the suppressing half only.** Every row
  here is either covered or completed; the generating half is exercised by fixtures. Anyone reading
  a green Phase P as evidence that generation works is reading something this change does not
  claim.
- The `Skill()` loop stays an instruction (§D10). A model that ignores the printed list produces
  exactly today's behaviour, and nothing detects it.
- Two known defects are disclosed and left open (§D13): the coverage-predicate divergence with
  `project-conductor`'s glob, and check 9's file-wide matcher, which makes `--only 365`/`--only 366`
  abort this repository's own launches today.
- One more fence contract to keep wrapped, executed and marker-anchored; the population
  `fence-contract-coverage.test.sh` guards grows by one.

### Neutral

- No manifest field, no `step5-report.json` change, no morning-report schema change (§D11).
- `docs/specs/_issue-map.tsv` is untouched; `roadmap-from-issues.sh` is untouched;
  `spec-from-issue` is untouched.
- `prep.test.sh` is byte-unchanged, including its colon-less `FAIL` (§D13).
- The helper needs no `chmod +x`: the fence invokes it as `bash "$_prs"`, the same way Phase S
  invokes `scope-args-parse.sh`.
- One `PAIRS` entry, one `docs-ci.yml` name. Both are hand edits by construction —
  `pairs-completeness.test.sh` cannot see a skill-private `scripts/` file, and `docs-ci.yml`
  enumerates rather than globs (ADR-0113).

---

## References

- Issue #399; `PROJECT.md` Phase 12 Wave 3, row 1.
- `docs/AUTOPILOT-RUN-AUDIT-2026-08-08.md` — the run that exposed this.
- ADR-0023 (Phase P), ADR-0129 (run scope; §D1/§D3/§D4/§D7), ADR-0132 (skill-argument substitution
  in fences), ADR-0133 (fence execution shell), ADR-0106 (SPEC archive namespace),
  ADR-0086 (extract-or-copy criterion), ADR-0085 (guard the denominator), ADR-0069 (one derivation
  of one value), ADR-0043 / ADR-0113 (`PAIRS` and CI-list blindness), ADR-0122 (the plant sandbox's
  `staging/` + `docs/` boundary), ADR-0108 (`plant-check.sh`), ADR-0070 §BB2 (why a defect is not
  pinned as expected).
- `staging/plugin/skills/autopilot/SKILL.md` §1.3 Phase S, §1.5 Phase P, §2 check 9.
- `staging/plugin/skills/autopilot/scripts/scope-args-parse.sh` — the precedent for §D1.
- `staging/plugin/scripts/roadmap-from-issues.sh:57`, `:103`.
- `staging/plugin/skills/project-conductor/SKILL.md:574` — the consumer glob behind §D13.
