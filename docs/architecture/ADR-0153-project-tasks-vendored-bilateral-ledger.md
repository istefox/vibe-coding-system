# ADR-0153 — project-tasks becomes a vendored chain member with a bilateral GitHub issue ledger

- **Date:** 2026-08-17
- **Issue:** none. Tracked as ledger entries `VCS-022` and `VCS-023` in `TODO.md`.
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md` (R-01 … R-23)
- **Supersedes:** nothing. **Amends:** ADR-0087 (the `project-tasks` row leaves the deployed-only
  registry), ADR-0024 (one more skill enters the vendored surface).

## Status

Accepted.

## Context

`~/.claude/skills/project-tasks/` maintains `TODO.md`, the durable answer to *what is open on this
project*. It exists on one machine, in one directory, with no source in this repository, no PAIRS
entry, no harness and no ADR. It is the only skill in that position that is not a personal routine
or a foreign symlink, and its own ledger records the consequence: `VCS-023` describes a rule-12
defect inside `scan.sh` and states, in its own text, that the defect is *not fixable in-repo while
`VCS-022` stands*. A skill with no vendored copy has no place a fix can land.

Three obligations arrive together, and each is load-bearing for the others. The skill is vendored,
so it can be edited, tested and recorded. The ledger becomes bilateral with GitHub, so the 66 open
issues stop being invisible to a session reading `TODO.md`. The ledger describes the work in
flight, derived from the feature's own artifacts rather than copied from the roadmap.

### What was measured before this was designed, and what the measurement changed

Rule 13. Four premises were re-derived from the tree on 2026-08-17, and two of them did not
survive.

**Open issues: 66.** Confirmed against `gh issue list --state open --limit 300`. The ledger tracks
12 open items. It sees roughly 18% of what is open, and nothing in the file says so.

**The two `MARKER` false positives reproduce exactly.** Running the current `scan.sh` against this
repository yields five `MARKER` records, and the two the SPEC names are among them verbatim:
`staging/plugin/scripts/tests/untrusted-input.test.sh` line 246, whose text is
`THE SELF-COLLISION IS EXPECTED, NOT A BUG`, and
`staging/plugin/scripts/tests/recovery-preflight.test.sh` line 66, where the keyword sits inside a
plant declaration's replacement string as `NONEMPTY-BUG`. The other three are in `SPEC.md` itself,
in running prose describing this very narrowing — the scanner captures the document that specifies
its own repair, which is rule 12 stated as a joke it did not intend.

**`project-tasks` IS already declared deployed-only, and the SPEC's premise is stale.**
`VCS-022` says the skill is *"neither vendored nor declared"*, and the SPEC repeats it. Measured:
`staging/sync-to-claude.sh` carries `deployed-only: project-tasks` since commit `6e9cddf`, so the
registry holds six entries, not five, and `--apply` no longer reports the skill at all. This
inverts R-02's work. Nothing needs to be *added* to stop the report; the declaration needs to be
**removed**, because the moment the skill is vendored, `pairs-completeness.test.sh` DO2 classifies
that line as a stale waiver — declared deployed-only *and* present in `staging/plugin/skills/`.
ADR-0087 built DO2 for exactly this transition and it will fire on the first run.

**The superseded rule is not where the SPEC says it is.** R-16 asks that
`reference/file-format.md` stop stating that *an item with an issue number leaves the file*.
Measured: `file-format.md` does not state it. The rule lives in three other places —
`reference/chain-integration.md` line 79 (*"A roadmap feature is not duplicated as an entry"*),
`reference/capture-sources.md` line 122 (*"Work already tracked in `PROJECT.md` as a roadmap
feature — that file owns the roadmap"*), and this repository's own `TODO.md` header, lines 6 to 8.
R-16 aimed at the one file that is innocent. Taken literally it is satisfiable by deleting nothing,
which is the shape of a requirement that passes vacuously. The plan targets the measured sites and
keeps the citation.

**The litter is not gitignored where it would land.** `.gitignore` line 10 is `.claude/test-cmd`
and lines 32 to 38 are `.remember/…`. Both patterns contain an internal slash, so both are anchored
to the repository root. `git check-ignore` on
`staging/plugin/skills/project-tasks/.remember/now.md` and on the nested `.claude/test-cmd` returns
nothing: neither is ignored. A careless `cp -R` of the deployed tree would commit one project's
transient state into every project's deployment, and no existing guard would say so.

### The constraint that shapes the whole design

Two of this feature's promises are *field-level invariants over a file a language model rewrites*:
`opened:` is never rewritten, `runs:` is incremented once per full run, `promote:declined` is never
proposed again. A model asked in prose to preserve a comment key usually does. When it does not,
nothing observes the difference — the file still parses, the entry still renders, and the promotion
bar has silently moved. That is rule 16 with a data-loss consequence attached, and it is the reason
this ADR spends a script on what looks like a formatting concern.

## Decision

### D1 — the GitHub read is its own script, not a sixth `scan.sh` record type

`scripts/gh-issues.sh` is added beside `scan.sh`. It is a **checker**: the caller branches on its
exit code (rule 5). It emits TSV on stdout with two record types, `ISSUE` and `DIDNOTRUN`, and it
carries an offline test hook `--issues-json <file>` that reads the `gh` payload from a file instead
of calling `gh` — the same hook `staging/plugin/scripts/roadmap-from-issues.sh` already uses at its
line 21, and the reason its behaviour is testable in a hermetic harness.

`scan.sh` stays offline and hermetic. Its own header promises *"Never writes anything. Never
guesses: every record is an observation"*, and `selftest.sh` asserts *"two consecutive runs are
identical"*. A network call inside `scan.sh` breaks that assertion by construction: two runs
straddling an issue edit legitimately differ, so the assertion would have to be deleted or
weakened, and it is the assertion that makes every other `scan.sh` claim reproducible.

**What the split costs.** Two scripts where the skill had one, a second PAIRS entry, a second
invocation in the workflow, and a reader who must learn that evidence collection is now two calls.
Accepted: the cost is one line in `SKILL.md`, and the alternative spends the determinism guarantee
of the only deterministic thing the skill owns.

`gh-issues.sh` also owns R-05's derivation guard, because it is the only place both numbers are in
scope: it takes `--ledger <file>`, counts the `#NNN` references already in the `GitHub Issues`
section, and when `gh` returns zero issues against a previously non-empty section it emits a
`DIDNOTRUN` record naming a broken derivation and exits non-zero. Zero matches can be correct; zero
where there were some is a derivation that stopped resolving, and from outside the two are
identical (rule 7).

### D2 — `ledger-merge.sh` owns three named regions of `TODO.md` and passes the rest through byte-identical

The skill's Step 7 rewrites the whole file. Under this design the model no longer does that alone.
`scripts/ledger-merge.sh` is a pure filter — reads `TODO.md`, writes a **candidate** to stdout,
never touches disk — with a contract stated as an equality rather than as a list of good
intentions:

> The output is byte-identical to the input except inside three regions: the `GitHub Issues`
> section, the provenance comment of each entry, and the `Steps — <feature>` section header.

Everything else — unknown sections, free prose, hand-written entries without an id, every HTML
comment that is not the header — passes through unread. The preservation rules
`reference/file-format.md` already states stop being instructions and become the filter's
definition. The local sections keep their existing model-written behaviour: the helper does not
compose entry text, choose priorities or write the Project Map. It owns the mechanical half only.

Implementation is bash 3.2 driving `awk`, in one file. Not `python3`: `selftest.sh`'s header claims
*"No network, no dependency beyond git and the shell"*, and a merge that needs an interpreter the
skill does not already require makes that sentence false on a machine without the Xcode command
line tools. Not a separate `.awk` file either — ADR-0086's criterion asks whether two copies giving
different answers would be a defect, and there is exactly one consumer.

The helper self-checks its own output before exiting, because R-04 asks for a *detectable* failure
rather than a hoped-for absence: every `ISSUE` number in the input appears exactly once in the
rendered section, and every local id appears exactly once in the whole file. Either count off by
any amount is exit 3 with the offending ids named — never a silently short section.

### D3 — `runs:` is a pure function of the file on disk, so an abort and a retry are the same value

The failure the SPEC names is real in both directions: an increment applied before an aborted write
inflates the counter without evidence, and a retry after a partial run inflates it twice.

Both disappear when the increment is not an *accumulation* but a *derivation*. `ledger-merge.sh`
computes `runs:` as `<value read from disk> + 1` and emits it into a candidate that only reaches
disk if the operator approves at the gate and the model then writes the helper's output. An abort
discards the candidate and the on-disk value is untouched. A retry re-reads the same on-disk value
and derives the same number. There is no in-memory counter to desynchronise, so there is no state
to corrupt.

Two guards bound it. The increment happens only under `--mode full`; `quick`, `add`, `close` and
`map` pass provenance through unchanged, which is also what makes R-08's *full run only* rule
mechanical rather than remembered. And `opened:` is never in the rewritten set at all — the filter
regenerates `runs:` and `promote:` and copies every other key verbatim, so the date that makes
ageing answerable cannot be rewritten by a bug in the key it sits beside.

**The residual, stated rather than engineered away.** Two full runs on the same day increment
twice, and an entry can reach the `runs: 2` bar a day early. The SPEC's own wording is *"full runs
this entry has survived"*, so this is the stated semantics and not a defect. Adding a `lastrun:`
key to make the increment idempotent per day was rejected: it is a key the SPEC's data model does
not have, it needs its own preservation rule, and the cost it avoids is one promotion *proposal*
arriving early — which the operator declines at no cost, once, by the SPEC's own promotion design.

### D4 — what is executed, and what is a prose pin (rule 16, and R-23's subject)

The SPEC mixes behaviours a harness can run with claims about text a model is asked to follow.
Collapsing them would let a green harness read as proof that the chain invokes the skill, which it
cannot be. The split is stated here so the record carries it.

| Requirement | Evidence | Kind |
|---|---|---|
| R-01, R-02 | PAIRS entries present, deployed-only line absent | executed (structural) |
| R-03 | vendored tree enumerated, litter absent, backward self-test | executed (structural) |
| R-04, R-05, R-06 | `gh-issues.sh` run against JSON fixtures and against an absent hook | executed (behavioural) |
| R-07, R-09, R-10, R-11 | `ledger-merge.sh` run over ledger fixtures, diff asserted | executed (behavioural) |
| R-08 | `--mode` gating of the proposal render | executed (behavioural) |
| R-12, R-13 | `ledger-merge.sh --manifests` over 0, 1 and 2 non-terminal fixtures | executed (behavioural) |
| R-14 | phase pointer rendered from a `PROJECT.md` fixture | executed (behavioural) |
| R-15 | `scan.sh` run over a fixture holding both measured false positives and a genuine marker | executed (behavioural) |
| R-18 | `ledger-merge.sh --p1-gate` classifying new against pre-existing | executed (behavioural) |
| R-16, R-19, R-20 | the text says what it must | prose pin |
| R-17 | `concept-to-code` and `project-conductor` name the skill | prose pin |
| R-21 | every new assertion seen RED against a declared plant | executed (registry) |
| R-22, R-23 | the record exists | documentation obligation |

**R-17 and R-18 are one requirement at two levels, and only one level is enforceable.** The
*classification* — which open `P1` this feature introduced, which was already there — is a checker
with an exit code, and it is tested. The *wiring* — that `concept-to-code` actually runs it before
its commit gate, and stops when it says stop — is a sentence in a markdown file a model reads. A
harness can pin that the sentence exists. Nothing here pins that it is obeyed. The chain wiring
ships as an instruction, and the failure shape it changes is *"the ledger silently went stale"*
into *"the ledger went stale and the transcript shows the step was skipped"*. That is worth having
and it is not a guarantee.

R-18's classification predicate is `opened:` on or after the in-flight manifest's `created` date.
It is cheap, it is derived from state that already exists, and it is wrong in one direction: an
entry recorded during this feature's session but describing pre-existing debt is classified as new
and blocks. Blocking on a false positive is the safe direction for a gate the operator can clear in
one sentence; the reverse would let the feature's own `P1` through.

### D5 — vendoring is byte-identical first, behaviour second, and the two are separate tasks

The move and the change are separated in time so each is reviewable on its own. The first coder
task copies the seven skill files into `staging/plugin/skills/project-tasks/` with no edit, adds
the seven PAIRS entries, and is verified by `diff -r` against the deployed tree excluding the
litter, plus a `sync-to-claude.sh` dry run reporting no difference for those paths. Every
behavioural change lands afterwards, against the vendored copy, where its diff is the change and
nothing else.

**R-01's second half is not CI-verifiable, and that is a property of the check, not a gap.** *"A
dry run after deployment reports no difference"* compares `staging/` against `$HOME/.claude/`. CI
has no `$HOME/.claude/`, and after the later tasks land, staging is *expected* to move ahead of
deployed until `--apply` runs — ADR-0024 §3.4 states that as intended. So R-01's deployment half is
a manual verification step recorded in the plan, the same asymmetry ADR-0087 §D3 already accepted
for the deployed-skill report and ADR-0084 for the deployed-versus-staged check. What CI *does*
verify is the vendored side: the files exist, they are in PAIRS, and
`pairs-completeness.test.sh` sees them in both directions.

### D6 — the deployed-only declaration is removed, not amended

`deployed-only: project-tasks` in `sync-to-claude.sh` is deleted by the same task that adds the
PAIRS entries, and the two must not be separated by a batch boundary. DO2 asserts that no declared
deployed-only name has a matching `staging/plugin/skills/<name>/SKILL.md`; a batch that vendors
without removing goes red on a stale waiver, which is DO2 working correctly and would still cost an
adjudication. DO1's floor is `>= 5` and the registry drops from six to five, so the floor holds
exactly — worth stating, because a floor that lands on its own boundary is one deletion away from a
red that has nothing to do with the deletion (rule 10, and DO1 is a declared vacuity guard rather
than a measurement).

### D7 — a new harness, and the CI append it forces

Assertions land in a new `staging/plugin/scripts/tests/project-tasks-ledger.test.sh` rather than
inside an existing file. No existing harness has this subject: `skill-coverage-perimeter.test.sh`
is a class guard over every skill, `litter-discipline.test.sh` is bound to ADR-0062's specific
clauses in three agent files, and `pairs-completeness.test.sh` is about PAIRS. Adding thirty
assertions about one skill to any of them breaks the single-subject shape those files state in
their own headers and collides with their assertion-id conventions.

**The cost is a manual append to `.github/workflows/docs-ci.yml`'s `shell-tests` list, and that
append is unplantable by construction.** `plant-check.sh` mutates an isolated copy of `staging/`
and `docs/`; `.github/` is copied into the sandbox so tests can read it, but no plant can target
it. So the assertion that the harness runs in CI carries a declared no-plant reason at its site,
exactly as `pairs-completeness.test.sh`'s `CI1` already does and for the same reason.

What makes the cost acceptable is that forgetting it is **self-detecting**: `CI1` derives every
staged harness and fails naming any that is neither in the list nor carrying a
`ci-dark-exempt` declaration. The omission this design risks is the one omission this repository
already guards.

`shell-tests` is a **required context** on `main` as of 2026-08-17, alongside `markdownlint`,
`links` and `ci`. `PROJECT.md`'s Phase 10.0 table says otherwise; that line is a correct
2026-08-04 snapshot and is not corrected in place (rule 14).

### D8 — R-03's absence check carries a denominator guard and a backward self-test

*"`.remember/` and `.claude/test-cmd` are absent from the vendored copy"* is an absence assertion,
and an absence assertion over a directory that does not exist reads exactly like a clean one. Three
parts, in order:

1. **Denominator.** The vendored tree contains the seven expected files, named individually, and
   the enumeration finds at least seven entries. A misspelled directory fails here, loudly, before
   any absence is asserted (rule 7).
2. **Absence.** No path component `.remember` and no `.claude/test-cmd` anywhere under the vendored
   skill.
3. **Backward self-test.** The same detection predicate is run against a fixture directory
   deliberately containing both, and is asserted to flag them. Without it, part 2 is satisfiable by
   a predicate that detects nothing — the `DO4`/`DO5` shape, applied here.

Part 2 carries **no plant**, and that is a decision rather than an oversight: a plant substitutes a
needle inside an existing file, so it cannot create litter that is not there. Part 3 carries one, a
self-targeting plant on the harness's own predicate, which `plant-check.sh` supports because it
masks `# plant:` lines out before matching.

### D9 — the marker narrowing is a two-part predicate, verified in both directions

A marker registers only when it is in **declaration form** — the keyword immediately followed by a
colon — **and** a comment leader appears earlier on the same line. Both halves are required, and
each is required by a different one of the measured cases:

- `NONEMPTY-BUG` at end of line is on a `# plant:` line, so the comment-leader half admits it; the
  colon half rejects it.
- `NOT A BUG (ADR-0059 …)` is inside a `# UF.` comment, so again the leader half admits it; the
  colon half rejects it.
- The three `SPEC.md` hits are `` `TODO:` `` and `` `XXX:` `` in flowing markdown prose, in
  declaration form with the colon, so the colon half admits them; the comment-leader half rejects
  them.

The leader is checked as *appearing before the marker on the line* rather than *at the start of the
line*, because `foo(); // TODO: fix` is the common real shape and a start-anchored predicate would
drop it. Verification runs in both directions, as the SPEC requires: the two false positives no
longer fire, and `selftest.sh`'s existing three genuine markers still do, along with a fixture case
for the trailing-comment shape.

Retiring the detector outright was the alternative, and it is what ADR-0144 did for a detector at
comparable precision. Rejected here on the difference in failure mode: that detector produced a
finding a human dismissed, this one produces a durable ledger entry, and the form separating a real
marker from prose is mechanical and two greps long.

## Alternatives considered

1. **A sixth `MARKER`-style record type inside `scan.sh` for the GitHub read.** Rejected: it makes
   the only hermetic, deterministic component of the skill depend on the network. `selftest.sh`'s
   *"two consecutive runs are identical"* assertion would have to be deleted or scoped away, and
   that assertion is what makes every other `scan.sh` claim reproducible. Every failure of `gh`
   would also arrive as a failure of evidence collection, conflating a missing remote with a
   directory that is not a project root — the exit-3 signal `scan.sh` already spends on the latter.

2. **The bilateral section rewritten by the model, guided by prose in `SKILL.md`.** Rejected: the
   contract is field-level (`opened:` never rewritten, `runs:` once per run, `promote:declined`
   never re-proposed) and a model that violates it leaves a file that still parses, still renders,
   and reports nothing. That is rule 16 with silent data loss attached. This is the alternative the
   skill uses today for its local sections, and it is kept there deliberately — the difference is
   that a mis-worded entry is visible to the operator at the next gate, while a dropped `runs:` key
   is not.

3. **`python3` for the merge, following `plant-check.sh`'s embedded-heredoc form.** Rejected: it
   would make `selftest.sh`'s *"no dependency beyond git and the shell"* header false, and this
   skill is deployed to every project including ones on machines without the Xcode command line
   tools. `awk` is sufficient for a line-oriented splice with regex key extraction, and this
   repository already puts line predicates in `awk` (`plan-task-predicate.awk`,
   `spec-id-predicate.awk`).

4. **A separate `.awk` file for the merge predicate, matching the two existing ones.** Rejected on
   ADR-0086's criterion: extract only when two copies giving different answers would be a defect.
   There is one consumer, and a shared file that fails disables it entirely for no gain in
   agreement.

5. **A separate promotion-state file (`.claude/project-tasks-promotions`).** Rejected: the SPEC
   already chose the entry's own provenance comment, and it chose correctly. A second file can
   diverge from the ledger it describes, needs its own preservation and archiving rules, and is
   invisible to the operator reading the entry that it governs. One file, no second source.

6. **A `lastrun:<date>` key making the `runs:` increment idempotent per calendar day.** Rejected:
   the key is not in the SPEC's data model, it needs its own preservation rule and its own
   assertion, and what it buys is avoiding one promotion *proposal* arriving a day early. A
   proposal is declined at no cost, once, by the SPEC's own promotion design. Recording the
   residual (D3) is cheaper than engineering it away.

7. **Extending an existing harness instead of adding `project-tasks-ledger.test.sh`.** Rejected: no
   existing harness has this subject, each states its own single subject in its header, and each
   carries an assertion-id convention that thirty foreign assertions would break. The saving would
   be one line in `docs-ci.yml`, and forgetting that line is already self-detecting through `CI1`.

8. **Keeping the `deployed-only: project-tasks` declaration and vendoring alongside it.** Rejected:
   `pairs-completeness.test.sh` DO2 exists to flag exactly a name declared deployed-only that is
   also vendored, and it would be right to flag it. The registry means *deliberately not part of
   the blueprint*; once the skill is in the blueprint the line is a stale waiver, and a stale
   waiver reading as a clean bill of health is the failure ADR-0081 `ZA4` was built to catch.

9. **Excluding `.md` from the marker scan entirely, instead of the two-part predicate.** Rejected:
   it is a cheaper fix that removes the three `SPEC.md` hits and both real false positives, and it
   also removes every genuine marker a documentation file carries. The two-part predicate is
   measured against both real cases and costs two greps.

10. **Deriving the `Steps` section content mechanically from the SPEC, the plan and the ADRs.**
    Rejected as out of the enforceable perimeter: *"one line describing what it is, not merely its
    title"* is a summarisation task, not a text transform. The helper derives the **case** — which
    manifest is in flight, or that zero or several are — and emits the section header with that
    case named; the model writes the described lines. Splitting there is what lets R-13's three
    branches be executed assertions while R-12's content stays a prose pin.

11. **An automatic `Stop`-hook capture feeding the ledger.** Rejected without revisiting:
    `reference/chain-integration.md` already rejected it, on the argument that automatic capture
    with no gate fills the ledger with low-confidence entries and a noisy ledger stops being read.
    The SPEC places it out of scope and this ADR does not reopen it.

12. **Excluding roadmap rows from the issues section, as the ledger's current header rule does.**
    Rejected: an excluded issue is an issue the ledger does not see, and the file's whole claim is
    to be the complete answer to *what is open*. The phase pointer is what stops completeness from
    becoming a second roadmap — the row appears, and it points at the file that orders it.

## Consequences

**Positive.**

- `VCS-022` and `VCS-023` are both resolved by the same change, and the second stops being
  unfixable: `scan.sh` has a vendored copy, so its rule-12 defect has a place to be repaired and a
  harness to prove the repair.
- The ledger stops under-reporting by a factor of five. 66 open issues become visible to a session
  that reads one file, with the full text one `gh issue view` away.
- Three field-level invariants that were previously hopes become properties of a filter, and each
  has an assertion that goes red when the filter stops holding it.
- The skill joins the surface every other component is held to: a source under `staging/`, a PAIRS
  entry, a harness, planted assertions, an ADR, a chain-decisions block and a roadmap row.
- `scan.sh` becomes usable on this repository. Two of its five findings today are false, and a
  scanner whose findings are 40% noise is a scanner whose findings get skimmed.
- The `DID-NOT-RUN` path means a project with no remote keeps a working ledger minus one section,
  rather than a ledger that silently renders an empty section that reads like good news.

**Negative.**

- The skill grows from two scripts to four files of executable content, and a reader learning it
  now meets a scanner, a GitHub reader and a merge filter instead of one scanner.
- `ledger-merge.sh` is the most intricate thing in the skill and it edits the user's file. Its
  byte-identical-outside-three-regions contract is the whole safety argument, and if that contract
  is ever weakened by an edit the failure is silent damage to a durable record. The assertion that
  guards it must not be relaxed to accommodate a future section.
- The chain wiring is an instruction, not an enforcement. A green harness will pin that
  `concept-to-code` and `project-conductor` name the skill, and will say nothing about whether they
  invoke it. Anyone reading the suite as coverage of R-17 is reading it wrong, which is why the
  table in D4 exists.
- One more required manual step at deployment: `sync-to-claude.sh --apply` must run before the
  vendored fixes reach the machine, and until it does the deployed skill keeps the old scanner. The
  gap is expected and visible in the dry run; it is still a gap.
- `docs-ci.yml`'s harness list grows by one, and that list is the thing ADR-0113 already found
  drifting four entries behind reality.
- The `runs:` counter can advance twice in one day, which can propose a promotion one run early.
  Stated in D3 and accepted.

**Neutral.**

- The deployed-only registry drops from six entries to five and lands exactly on DO1's floor. The
  floor is a declared vacuity guard, not a measurement, so this changes nothing about what DO1
  means — but the next removal turns it red, and whoever makes it should lower the floor in the
  same change rather than treat the red as a defect.
- `TODO.md`'s header rule inverts: issue-numbered items become the largest section rather than the
  excluded one. Every existing entry keeps its id, and `lastId` is untouched by the reshape.
- `VCS-027`, which recorded a deliberate exception to the old rule, stops being an exception and
  becomes an ordinary entry. It is not deleted; the rule around it changed.
- The `Steps` section is conditional and will be absent on most projects most of the time. Its
  absence always carries a stated reason, which makes an omitted section distinguishable from a
  section that failed to derive (rule 4).

## References

- `/Users/stefer/Developer/vibe-coding-system/SPEC.md` — R-01 … R-23.
- `docs/superpowers/plans/2026-08-17-project-tasks-vendored-bilateral-ledger.md` — the plan.
- ADR-0024 — what the vendored surface is and why `staging/` is the source of truth.
- ADR-0087 — the deployed-only registry, and the DO1 … DO5 checks this feature moves an entry out
  of.
- ADR-0043 — the direction lesson; `check_complete`'s reverse pass is what sees the new files.
- ADR-0108, ADR-0149, ADR-0151 — the plant registry, the declaration grammar, the sharded run.
- ADR-0113 — `CI1`, and the four harnesses that had never run in CI.
- ADR-0138 — the requirement-coverage scope filter, and why the new assertions must cite these ids
  in their own comment headers.
- ADR-0144 — a detector retired on measured precision, and the reason this one is narrowed instead.
- ADR-0086 — the extraction criterion applied to the merge predicate.
- ADR-0062 — litter and debris discipline, the class the vendoring exclusion belongs to.
- `TODO.md` — entries `VCS-022`, `VCS-023`, `VCS-027`.
- `staging/plugin/scripts/roadmap-from-issues.sh` — the `--issues-json` offline hook this design
  copies.
