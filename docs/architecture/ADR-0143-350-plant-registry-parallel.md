# ADR-0143 — the plant registry already paid for isolation and was spending it one core at a time (issue #350)

- **Date:** 2026-08-15
- **Issue:** #350 — "plant-check.sh cost scales as (plants x target-file runtime), not as their sum"
- **Supersedes:** nothing. **Amends:** ADR-0108 (the mutation phase gains workers), ADR-0140 (the
  baseline pass gains a sandbox per harness instead of one shared).

## Status

Accepted.

## Context

### What the registry costs, and where it is paid

`plant-check.sh` runs each `# plant:` declaration against an isolated `cp -R` of the tree and then
executes **the whole declaring test file**. The issue filed this as a cost problem at 166 plants and
asked for four things to be measured before anything was designed.

### R-01 — measured 2026-08-15 at `0622930`

**The registry is 381 declarations across 41 files**, up 129% from the 166 the issue was written
against. The count is from the `feat/439-wave2-brief-to-app` tree, which carries
`brief-to-app.test.sh`'s 10 plants; on `main` at that hour it was 371.

**Where the cost is actually paid — CI, two runs on the day:**

| run | branch | all 79 harnesses | the plant registry | registry share of the job |
|---|---|---|---|---|
| 31892356085 | `docs/439-wave1-complete` | 2m22s | **20m07s** | 89% |
| 31890908877 | `main` | 3m04s | **25m51s** | 89% |

**`shell-tests` is a required check on `main`** — the live required set is
`markdownlint, links, ci, shell-tests` — so every merge waits for it. ADR-0124's note that the job
is *not* required was true when written and is stale; that is recorded here rather than corrected
there (rule 14).

**Per-file cost, ranked**, modelled as `plants × (0.50s sandbox + the file's own runtime)`:

| file | plants | runtime | cost | cumulative |
|---|---|---|---|---|
| `spec-coverage.test.sh` | 18 | 28.1s | 515s | 24% |
| `worktree-isolation-contract.test.sh` | 11 | 39.9s | 445s | 45% |
| `conductor-entry-failure-split.test.sh` | 42 | 3.3s | 159s | 52% |
| `autopilot-run-scope.test.sh` | 58 | 2.0s | 144s | 59% |
| `fence-contract-coverage.test.sh` | 9 | 11.0s | 104s | 64% |
| `plan-task-count.test.sh` | 14 | 6.4s | 97s | 69% |

The issue's central claim holds and is now a number: **the dominant term is the target file's
runtime, not the plant count.** `autopilot-run-scope` carries 58 plants and costs less than
`worktree-isolation-contract`'s 11. Two files are 45% of the total; eleven are 87%.

Two of the issue's open questions are answered against its own expectation:

- **The sandbox copy is not the problem.** 0.499s × 381 = 190s, **9%** of the mutation phase.
- **The distribution is not unknown and not worse elsewhere.** It is more concentrated than
  supposed, in the two files the issue already named.

**One thing nobody had looked at**: a full run measures `755s user, 1148s system, 89% cpu`. More
time in the kernel — copying trees, forking — than in the tests, and **one core out of eighteen**.

## The measurement that decided the design

Every mutation run **is already isolated**: its own sandbox, its own process, `mktemp` in 78 of the
81 harnesses. The three fixed `/tmp` paths in declaring harnesses (`/tmp/SPEC.md` ×3, `/tmp/proj`)
were checked one by one and are **string values** written into manifests and synthetic JSON, never
files created or read. The design had therefore already paid for concurrency and was not using it.

That is the whole decision. The three levers the issue proposed were each measured and each
rejected, and the reasons are in *Alternatives considered*.

## Decision

### D1 — the mutation phase is dispatched to `$JOBS` workers, and there is only one copy of it

`plant-check.sh --worker <idx> <workdir>` is the file re-entering itself, carrying the sequential
loop body unchanged. The sequential path **is** this path with one worker.

ADR-0086's criterion decided the shape: a parallel implementation kept beside a sequential one is
two copies answering the same question, and on the day they disagree nobody can say which verdict
is the registry's.

### D2 — every failure in the worker-count resolution lands on 1

`PLANT_JOBS`, else the machine's own count (`nproc`, `sysctl -n hw.ncpu`, `getconf`), else 1.
Anything non-numeric or `< 1` resolves to **1**, which is the behaviour this file had before it was
parallel. An unreadable core count must not become an unbounded fan-out on a runner nobody has
measured.

The ceiling is **8 because 8 is what was measured**. Above it the copies contend for I/O and no
number exists, so the file does not invent one; an explicit `PLANT_JOBS` is not capped, because
someone setting it is someone about to record what they got.

`PLANT_WORKROOT` names where the sandboxes are built, and it exists because **BSD `mktemp -d`
ignores `TMPDIR`** — verified 2026-08-15 on macOS 26, including with `-t`. GNU coreutils honours it.
That asymmetry is not a footnote: `PP4` has to watch sandboxes appear and disappear, and the first
version of it was written against `TMPDIR`, observed nothing on the machine it was written on, and
would have observed everything on the Linux runner. A check that is inert on one platform and live
on the other is the "did not run reads as found nothing" class wearing a portability costume.

### D3 — aggregation is in DECLARATION order, never completion order

An output that reshuffles between runs cannot be diffed against anything — and the diff is the only
evidence that parallelising a validator did not change what it validates. This is the property that
makes D6 possible, so it is a decision and not a detail.

### D4 — a declaration whose worker left no verdict is `BADPLANT`, never silence

Rule 4 applied to this file's own workers: a declaration that did not run must not be counted as a
declaration that ran and found nothing. It reports
`declaration N produced no verdict — the worker did not run`, and an unrecognised verdict token is
refused the same way rather than falling through a `case`.

### D5 — sandboxes are freed at verdict time, and the baseline gets one each

The worker frees its sandbox as soon as its verdict is written. The file previously kept all 381
alive until the `EXIT` trap: at 22 MB apiece, **~8.4 GB of peak disk** that nothing ever reads back.
Peak is now bounded by the worker count.

ADR-0140's baseline pass shared ONE sandbox across all declaring harnesses, which was safe while the
runs were serial. Run concurrently, a harness that writes anywhere inside the tree it was handed
would corrupt another harness's baseline, and the symptom would be a vacuous-plant verdict nobody
could reproduce. Each baseline run now builds its own — 41 copies, about 20s spread across the
workers, and the cheapest guarantee available.

### D6 — how a change to the thing that validates plants is itself verified

The issue's standing rules demand this be stated. Two pieces of evidence, because neither is
sufficient alone and only one of them can live in CI.

**Outside the registry — the corpus diff.** The full 381-plant run, same tree, same machine:

| binary | workers | wall clock | verdicts |
|---|---|---|---|
| the file before this change | sequential | 30m54s (machine shared with another run) | **baseline**, 391 lines |
| the parallel restructure | 1 | **29m20s** | identical |
| the parallel restructure | 4 | **9m41s** | identical |
| the parallel restructure | 8 | **7m35s** | identical |
| **the file as shipped** | 8 (default) | **8m20s** | identical |

"Identical" is `diff` over the whole output with the timestamps stripped: **391 lines, byte for
byte, in the same order**, `PASS=389 FAIL=0`, every one of the 381 plants firing in every run.

Two readings beyond the headline. The one-worker run lands within 5% of the pre-change file, so the
restructure itself costs nothing — the speedup is concurrency and not a rewrite that happened to be
faster. And the shipped file is ~45s slower at eight workers than the restructure measured the same
way; **that difference is not attributed here.** The candidates are D5's per-harness baseline
sandboxes and ordinary run-to-run variance, neither was isolated, and naming one without measuring
it is what this repository keeps writing ADRs about.

This evidence cannot be a test. It costs half an hour.

**Inside the registry — `plant-registry-parallel.test.sh`.** A fixture: a miniature staging tree
with four harnesses, twelve plants, and the real `plant-check.sh` pointed at it three times. Its
harnesses sleep for descending intervals so completion order is not declaration order, and one of
its plants is built so that it **cannot fire** — because an equivalence check between two runs that
both found nothing is satisfied by a registry that does nothing. Six assertions, six plants:
`PP0` the fixture population, `PP1` one worker equals four, `PP2` the non-firing plant is reported
in both, `PP3` declaration order under concurrency, `PP4` the sandbox is freed, `PP5` an unusable
`PLANT_JOBS` reproduces the one-worker run exactly.

**`PP0` shipped wrong and its own plant is what said so**, which is the entire argument of this
mechanism reproduced inside the change that speeds it up. `PP0` first asserted that the fixture
*counted* 12 plants over 4 files. Its plant removes three harnesses from the builder — and the
assertion stayed green, because the declarations are appended with `>>`, so the three files were
recreated containing nothing but `# plant:` lines. Counted, that degenerate corpus is identical to
the real one. The needle did not belong to the mechanism the assertion was about (rule 12), and no
amount of reading would have shown it: five plants fired and this one did not. `PP0` now requires
the four harnesses to RUN.

### D7 — what this does NOT fix

- **The per-file cost is untouched.** Each plant still runs the whole declaring file, so the
  registry still grows linearly with a term nobody bounds. This decision buys a constant factor of
  about 3.9, not a change of shape. When `spec-coverage.test.sh` doubles again, this comes back.
- **#355 is untouched.** The fired predicate is still a prefix match, and the vacuity guard still
  inherits its looseness — deliberately, so both halves agree.
- **The ceiling on CI is unknown until CI says so.** The runner's core count is printed by the
  workflow rather than assumed, and the before/after pair from the PR's own run is recorded below.

## Alternatives considered

**Filter each harness to the single assertion under test** — the issue's own first suggestion.
Rejected on the measurement. In `worktree-isolation-contract` it would work perfectly: all 11 plants
sit at lines 1510–1637, after the git fixture at line 1404 that costs the 40 seconds. In
`spec-coverage` the 18 plants span lines 849–1343 and the sections declare in-place dependencies on
each other — `RM05/RM06/RM07` mutate a SPEC *after* `RM03/RM04` have run against it. Sliceability is
a property of each hermetic file, provable 41 times and not once, and ADR-0086 refuses the shared
helper that would make it uniform.

**Group plants by target file and reuse a sandbox.** Rejected: 190s, 9% of the phase. The issue
suspected this might be the dominant term; it is not.

**A separate CI job.** Rejected for now, and this is the one the issue leaned toward. It costs a
**new required context** on `main` — ADR-0114's rule that a context must be made satisfiable or the
change aborts, with #336 still open on `set-branch-protection.sh` — to save roughly three minutes of
critical path, which D1 makes irrelevant. If the registry ever outgrows the job again, this is the
next lever and the reasoning above is what to re-read.

**Trim plants off the slow files.** Ruled out by the issue itself, and the ruling stands: #349's
`L4` plant did not fire on its first run, which is exactly the evidence the registry exists to
produce. A plant removed is evidence removed.

## Consequences

- The registry's local wall clock falls from 29.34 min to 7.59 min at eight workers, 3.87×. The CI
  figure is the one that decides whether this worked, and it is measured on the PR, not predicted
  here.
- Peak disk during a run falls from ~8.4 GB to the worker count times 22 MB.
- **The `COST:` comment in `docs-ci.yml` will go stale again.** It already did once — "~12s for 15
  plants", true at 15 — and the fix is not a better comment but the line beside it telling the
  reader to re-derive the pair from a run.
- `PP1`'s plant collapses the per-declaration sandbox path to a shared one and relies on the
  fixture's workers actually overlapping to produce divergence. The fixture's sleeps make that
  overlap certain rather than likely, but it is a probabilistic plant in a file full of
  deterministic ones, and it is disclosed here rather than discovered later.
- The four-worker run is the one to reach for when reproducing locally: 9.69 min, and it leaves the
  machine usable.

## References

- Issue #350, and its own correction comment: this repository has **zero** metered Actions minutes,
  so the constraint was always wall clock and feedback latency, never billed minutes.
- `docs/specs/350-plant-check-sh-cost-scales-as-plants-x-t.spec.md` — R-01 measured above, R-02
  decided in *Decision*, R-03 evidenced in D6.
- ADR-0108 (the plant registry), ADR-0140 (the baseline), ADR-0086 (the extraction criterion),
  ADR-0114 (required contexts), ADR-0124 (the note about `shell-tests` that has since gone stale).
- CLAUDE.md rules 2, 4, 6, 7, 13.
