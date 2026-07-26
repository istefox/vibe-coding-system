# ADR-0051 — Reward-hacking detectors: literal assertions, zero-assertion tests, deleted symbols, swallowed errors

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #105 (sixth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/105-reward-hacking-detectors.spec.md`
- **Builds on:** ADR-0047 (#101), which wired `weakening-scan.sh` into every unattended path. This
  issue adds detectors to a scanner that is *already being called everywhere* — which is the whole
  reason it runs second.
- **Closes:** gaps **G-03**, **G-07**, **G-08** of
  `docs/books/INTEGRATION-REPORT-agentic-spec.md` (ABSENT, P2/P3).

## Context

`weakening-scan.sh` reports only **net-negative** deltas: a deleted test file, an added skip, more
assertions removed than added, a removed test body. Those catch an agent that takes something away.
They do not catch an agent that *adds* something worthless, which is the more common and more
dangerous shape.

The agentic spec documents the canonical case: of nine tests forced green in its worked example,
**four** were forced by editing the implementation and the test's expected value in the same commit
so a literal now matches a literal. The scan sees an assertion added, not removed, and reports
`CLEAN`. It also documents a deleted public symbol that went unnoticed for four days.

`post-write-check.sh` is syntax-only by decision (ADR-0039 §D4 removed linters for determinism), and
`reviewer.md` covers this by eye behind a 75-confidence filter. So nothing in the system flags any of
it mechanically.

## Decision

### D1 — Four detectors, all on the existing awk pipeline

- `SUSPECT literal-assertion-added` — an implementation file and a test file change in the same
  diff **and** a literal-valued assertion is introduced.
- `SUSPECT zero-assertion-test` — an added test function whose body contains no assertion token.
- `SUSPECT deleted-public-symbol` — a removed exported function / route / public class.
- `SUSPECT swallowed-error` — an empty catch block, or a catch with neither a log nor a rethrow.

### D2 — `SUSPECT` is a new sentinel, and it deliberately does NOT trip the existing gates

This is the central decision and it cuts against the instinct.

Every caller wired by ADR-0047 uses the idiom `printf '%s\n' "$out" | grep -q '^WEAKENED'`. A new
line prefixed `SUSPECT` is therefore **invisible to all of them** — c2c's Step 5 → Step 6 gate,
`autopilot-build`, `nightly-autopilot`, `commit` Step 1 — and that is intended.

The reason is the difference in evidence quality. A `WEAKENED` finding is close to mechanical: a
test file was deleted, a skip was added. A `SUSPECT` finding is a **heuristic over a diff with no
type information and no test execution**. `literal-assertion-added` in particular will fire on
entirely legitimate work — adding a test for a new constant is exactly the shape it matches. Wiring
a heuristic that noisy into a gate that halts unattended runs would train every future operator to
route around the gate, and would take `WEAKENED`'s credibility down with it.

**The honest cost, stated because ADR-0047 §D7 taught this codebase the lesson directly: a report
nobody must act on is a report nobody reads.** §D3 is what stops this from being that report.

### D3 — Advisory findings must be *surfaced*, not merely emitted

An advisory that only appears in a script's stdout is an advisory that dies in a log. So:

- `SUSPECT` counts land in `step5-report.json` as an additive `suspect_findings` array
  (`{file, detector, line}`) — the sixth additive extension of that schema, same terms as
  `tests_written_by`.
- The Gate 5 summary prints the count and the per-detector breakdown **explicitly**, so a human
  making the review decision sees it.
- `commit` Step 1 prints them attended. It does not abort on them, even with `--autopilot`.

### D4 — The reporter contract is preserved exactly

`weakening-scan.sh` still **always exits 0** and still prints the `CLEAN` sentinel when there is
nothing at all. `CLEAN` means no `WEAKENED` *and* no `SUSPECT`.

The caller trap ADR-0047 wrote out stays true and must stay written at every call site: never
`[ -n "$out" ]` (true even on `CLEAN`) and never `grep -c … || echo 0` (two-line `0\n0` on no
match — issue #100 hit this exact bug; `|| true` is the fix). A caller that wants only hard findings
greps `^WEAKENED`; a caller that wants everything greps `^WEAKENED\|^SUSPECT`.

### D5 — Exclusions are declared per detector, and measured against this repo before shipping

Each detector carries explicit exclusions, and the harness proves the false-positive rate against
the **real corpus** rather than a fixture — the method ADR-0046 §D1 established when it cleared
eleven secret rules against all 350 tracked files, and ADR-0048 §RE repeated against all 34 SPECs.

- `deleted-public-symbol`: excluded when the symbol is named in the task scope, and when the removal
  is a pure rename detected as an adjacent add of the same signature.
- `zero-assertion-test`: excluded for a test whose body is a single call to a shared helper that
  itself asserts — the common table-driven shape.
- `swallowed-error`: excluded when the catch body contains a comment explaining the intentional
  swallow, matching the existing house convention for deliberate no-ops.
- `literal-assertion-added`: the noisiest by construction. Requires **both** halves of the
  condition (implementation *and* test changed in the same diff); a test-only diff never fires it.

A detector whose measured false-positive rate on this repo's own history is high enough to be
useless ships **disabled with the measurement recorded**, rather than shipping noisy. Say which, and
why, in the report.

### D6 — No new script, no second source of truth

The detectors go **into** `weakening-scan.sh`, which stays at its existing path
(`review-triage-fix/scripts/`) and stays the one copy the other four skills call by reference. ADR-0047
§A1 accepted the cross-skill script dependency precisely so a new detector reaches all call sites
with no second edit. This is that payoff being collected; a sibling script would forfeit it.

## Alternatives rejected

- **A1 — Emit the new findings as `WEAKENED` so existing gates halt on them.** Rejected under §D2:
  a noisy heuristic in a halting gate destroys the credible signal's credibility. This is the
  alternative most likely to be re-proposed.
- **A2 — A separate `reward-hack-scan.sh`.** Rejected under §D6: forfeits ADR-0047 §A1's single
  source of truth and would need its own wiring into four skills.
- **A3 — Use a linter or type information.** Rejected: ADR-0039 §D4 removed linters from the write
  path for determinism, and the reason holds here — a verdict that depends on which tools are
  installed is not a verdict.
- **A4 — Ship all four regardless of measured false-positive rate.** Rejected under §D5.

## Consequences

### Positive

- The system gains detection for *added worthlessness*, not only removed value — the shape the
  spec's own worked example was dominated by.
- Every call site ADR-0047 wired inherits the detectors with no second edit.

### Negative, stated plainly

- **These findings block nothing.** By construction (§D2). The mitigation is surfacing (§D3), and
  surfacing is weaker than blocking. If the Gate 5 summary is skimmed, a real reward-hack passes.
- **Heuristics over a diff, with no execution and no types.** False positives are certain; the
  question §D5 answers is only whether the rate is tolerable.
- **`literal-assertion-added` cannot distinguish** a legitimate new constant test from a
  cardboard-muffin edit. It reports the co-change shape and leaves the judgment to a human.
- Instruction, not enforcement, for the surfacing half: the harness pins that the Gate 5 text and
  the schema field exist, never that a human reads them.

## Addendum 2026-07-26 (Task 4 measurement — `literal-assertion-added` ships disabled)

Measured per §D5, against this repository's own history rather than a fixture (the ADR-0046 §D1 /
ADR-0048 §RE method): `weakening-scan.sh` (post-implementation) was run over the diff of each of
this repo's last 153 non-merge commits.

| detector | real-history hits (153 commits) | verdict |
|---|---|---|
| `zero-assertion-test` | 1 (before a fix described below) → 0 after | true positive avoided, not a real finding |
| `deleted-public-symbol` | 0 | no evidence either way (see below) |
| `swallowed-error` | 6, all in one file (`usage-report.py`) | 6/6 true positives by the rule as written (`except …: continue/pass`, no log, no rethrow, no comment) |
| `literal-assertion-added` | 0 | no evidence either way (see below) |

**One real false positive was found and fixed during measurement, not merely observed.** Commit
`a5e891b`'s test fixture `def test_sneaky(): assert True` — a one-line def with an inline assert —
was flagged `zero-assertion-test` because the state machine that opens a test body on a `def
test_*` line never checked that same line for an assertion token before falling through to the
next line. Fixed by checking the opening line itself; the corpus run above is post-fix and the
one-liner case is now a permanent fixture in `reward-hack-detectors.test.sh` (implicit in the
one-line-def coverage, guarding the regression).

**`swallowed-error`'s 6 hits are all true positives by the literal rule** (empty or no
log/no-rethrow catch), and none carry an explaining comment, so none are excluded. Whether
`except json.JSONDecodeError: continue` is *bad* is a judgment call a human reviewer makes cheaply
at Gate 5 — the detector's job is only to surface the shape, and it did, with no noise. Ships
**enabled**.

**`zero-assertion-test` and `deleted-public-symbol` had zero real-history hits and ship enabled
anyway**, on the strength of the synthetic true-positive/exclusion battery in
`reward-hack-detectors.test.sh` (sections HA/HB) and the absence of any false-alarm evidence — a
silent corpus is not a damning one when the fixtures independently confirm correct behavior.

**`literal-assertion-added` ships DISABLED BY DEFAULT**, opt-in via
`WEAKENING_SCAN_LITERAL_ASSERTION=1`. Real history gave *no* signal either way: this repository's
own tests are bash `[ … ]`/`-eq` idiom, never `assert`/`expect(`-style tokens, so the detector was
never exercised by any of the 153 commits — silence, not vindication. What settled it was a
5-diff synthetic sample of realistic co-changes (3 ordinary legitimate, 1 deliberately malicious,
1 a Jest `toBe()` case the detector's quoted-literal pattern does not reach): **4 of 5 fired, and
3 of those 4 were the legitimate cases** — exactly the failure mode §D5 and the Alternatives
section predicted in advance ("adding a test for a new constant is exactly the shape it matches").
The malicious case was also caught (recall is fine); precision on this small sample is 25%. The
code stays wired, tested (HA4/HB4/HG1-5 all exercise it via the opt-in), and disabled by default —
an operator with review capacity for a majority-false-alarm advisory signal can turn it on.

Both corpora are reproducible (`git log --no-merges` over this repo; the fixture diffs are inline
in the harness). The 5-diff synthetic sample is small by construction — enough to confirm the
structural argument in §D2/§D5, not a statistically powered estimate — and a team whose tests are
mostly pytest/Jest-style literal comparisons may see a different (still expected to be low, per
that same structural argument) precision if they opt in.
