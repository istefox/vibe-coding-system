# ADR-0141 — an acceptance criterion passes by being executed, not by being cited (issue #439, Wave 1)

- **Date:** 2026-08-15
- **Issue:** #439 — "the chain discards the conversation and never runs the product"
- **Scope:** Wave 1 of three. Wave 2 is the `brief-to-app` interview; Wave 3 is the lane's ADR, the
  scoped blueprint deviation and the wiring. **Amends:** nothing. **Extends:** ADR-0138.

## Status

Accepted.

## Context

Building an app through `concept-to-code` arrives with missing functionality and bugs, while the
same work driven by `/goal` lands close to the request. Issue #439 measured three causes; this wave
addresses the second, and it is the one with no partial mitigation anywhere in the system.

**Nothing verifies the product.** Measured repo-wide: zero hits for XCUITest, XCUIApplication or
`simctl`; Playwright only in prose, including `ADR-0010-web-e2e-test.md` where a real headless
harness is explicitly rejected; `smoke-e2e.sh` walks the manifest state machine, not a built
artifact. The single "does it build and run" is Step 4.5's tracer bullet, which is off by default
and covers one thin slice by construction.

What the gates do check is that tests are green, that requirement ids are cited, and that the diff
fits a budget. **ADR-0138 established three days ago that the id check measured citation, not
implementation** — a requirement passed by being named in a plan task and in a test file. At app
scale that is precisely the "missing functionality" symptom, and nothing in the pipeline is
positioned to notice it.

This wave builds the missing layer: an executed verdict per `R-NN`. It is deliberately first
because it is independently useful — it can be pointed at the current chain's output today, with
none of the lane around it.

### One premise inverted while planning

The operator confirmed that "performance decay" means **quality degrading over a long session**.
That partly inverts the lane's stated rationale: a single-session lane preserves intent by keeping
everything in context, and unbounded context is the mechanism that rots. The defence therefore
cannot be the conversation itself; it has to be durable artifacts re-read each turn. `ACCEPTANCE.md`
and a machine-checkable verdict sit on the durable side of that line, which raises Wave 1's
priority rather than lowering it. The tension belongs to Wave 3's ADR and is recorded here so that
ADR does not have to rediscover it.

## The measurement that shaped the design

The Xcode contract was read live on 2026-08-15 (Xcode 26.6, Swift 6.3.3):
`xcrun xcresulttool get test-results tests --path <bundle> --schema-version 0.1.0` emits a
`testNodes` tree whose `TestNode` carries `nodeType`, `name`, `result` and `children`, and
**`TestResult` is a five-value enum: `Passed`, `Failed`, `Skipped`, `Expected Failure`, `unknown`.**

The schema alone was not treated as sufficient. A throwaway Swift package with a passing, a failing
and a skipped test was built and its **actual emitted JSON** read. Three things only the real output
shows, each of which would have produced a wrong adapter:

1. **XCTest names arrive as `testR01_greetReturnsHello()`** — the id follows the mandatory `test`
   prefix. A plain word-boundary rule rejects the real convention. The plan's regex did exactly
   that and was corrected by the fixture, not by review.
2. **`testERROR6_boundaryProbe()` contains `R6`.** A rule without a left boundary binds a stranger.
   Both traps are permanent fixtures in the harness.
3. **A `Skipped` case still carries a `Failure Message` child** ("Test skipped - …"). Any heuristic
   keyed on that child reads a skip as a failure. `result` is the only authority.

`tags` was emitted on zero nodes, so name is the only binding channel available in XCTest.
`duration` is locale-formatted (`"0,00037s"`); `durationInSeconds` is the numeric field.

## Decision

### D1 — the contract, and why each field exists

`acceptance-run.sh` and `acceptance-adapter-swift.sh` are **reporters** in the `weakening-scan.sh`
family: exit 0 on any determined outcome, exit 2 only on a bad invocation, and the caller gates on
stdout. Per rule 5 both headers state the caller idiom and name the wrong one explicitly —
`[ -n "$out" ]` is true on a clean run, a total failure and a halt alike.

```text
ACCEPTANCE-RESULT pass=<n> fail=<m> skip=<k> total=<t> declared=<d|-> missing=<x|-> unbound=<u>
ACCEPTANCE-CASE <R-NN> PASS|FAIL|SKIP|MISSING
ACCEPTANCE-HALT <reason>
```

| field | the failure it makes visible |
|---|---|
| `skip` | a skipped criterion is not a passing one (rule 4) |
| `total` | `pass+fail+skip == total` is self-checked; a dropped verdict must not report a clean total |
| `declared` / `missing` | the reverse direction (rule 8). With no declaration both read `-`, so **"the reverse check did not run" is visible in the line** rather than absent from it |
| `unbound` | the denominator (rule 7). `total=0, unbound=300` and `total=0, unbound=0` are different defects and halt with different reasons |

**A halt emits no `ACCEPTANCE-RESULT`**, so a caller that greps only for the result line sees
nothing rather than a clean zero.

### D2 — the result mapping is a judgement, and is labelled as one

`Passed`→PASS, `Failed`→FAIL, `Skipped`→SKIP, and:

- **`Expected Failure`→FAIL.** For an acceptance criterion, "expected to fail" means not met. A
  team using `XCTExpectFailure` for known-broken behaviour will see red; that is the intended
  reading and it is documented rather than discovered.
- **`unknown` or an absent `result`→FAIL.** The key is not in the schema's `required` list.
  Indeterminate must never read as a pass, and FAIL is the loud direction.

A criterion is PASS only when at least one bound case exists **and** every bound case passed. FAIL
beats SKIP beats PASS. Duplicate bindings aggregate rather than overwrite.

### D3 — `NONE` halts, unlike `.claude/test-cmd`

`.claude/test-cmd` treats `NONE` as a quiet opt-out that exits 0. `.claude/acceptance-cmd` does
not: an opt-out emits `ACCEPTANCE-HALT opted-out` and no result line. A silent acceptance opt-out
would read as "every criterion passed" to any caller. An empty or comment-only file is a **third**
state (`acceptance-cmd-empty`), because "someone deleted the command" and "someone declared no
acceptance suite" have different repairs.

### D4 — the id pattern is defined once, not guarded as three copies

Three consumers ask what an id is: the binding pass, the bound-case count, and the reverse check.
That is one question, so under rule 6 it is one `IDRE=` definition passed into jq with `--arg`.
Two literals that drifted would make the reverse check match nothing and report a clean
`missing=0` — the quietest way this feature could fail.

The plan proposed keeping three literals and asserting they were identical. Writing the plant
exposed why that was wrong: the needle would have matched three sites and the plant was
inexpressible. **A registry that cannot express the plant is evidence about the design, not an
obstacle to route around.**

### D5 — the trust format is copied and guarded, not extracted

`.claude/acceptance-cmd` is TOFU-gated through the **same** registry and the same
`<sha256>\t<normalized-root>` line as `.claude/test-cmd`, resolved by the same upward walk.

Rule 6 argues for extraction — a writer and a reader that disagree produce a check that silently
trusts nothing. But extraction means editing `stop-gate.sh`, the armed hook that runs every turn,
for a wave that otherwise does not touch it. So this follows **ADR-0086's precedent**: keep the
copies, add the guard. `A32` builds one root holding both files with identical content, runs both
approvers, and asserts the two registry lines are byte-identical — and fails loudly, naming both,
if either approver writes nothing at all.

**Declared consequence:** the line is (content-hash, root), so identical content yields an
identical line and approving one file approves the other. TOFU reviews the command, not the
filename. That is the intended reading; assuming per-file approval is not.

### D6 — what is enforcement and what is instruction

- **Enforcement:** the result mapping, the binding rule, both denominators, the reverse check, the
  arithmetic self-check, the trust gate. All are executed by the harness, and the trust gate is
  proven by an **absent side effect** — an untrusted command that would `touch` a file, and the
  file is not there.
- **Instruction:** the acceptance command is expected to write its bundle to
  `$ACCEPTANCE_RESULT_BUNDLE`. That cannot be enforced (rule 16). The enforcement half is that a
  missing bundle halts loudly instead of reporting an empty pass — detection after the fact, not
  prevention, and the header says so.
- **Not proven at all:** the arithmetic self-check's halt branch. Its trigger is an internal
  counting bug and cannot be reached from outside, so `A25` pins that the identity *holds* and no
  assertion claims the halt fires. Stated rather than left as an apparent gap.

An acceptance suite is itself gameable, and `weakening-scan.sh` documents that an **in-place**
assertion edit is invisible to every detector, so `CLEAN` does not mean "not weakened". Wave 1 ships
the contract; the case-count pin that turns "do not weaken the suite" from instruction into
enforcement belongs with the `ACCEPTANCE.md` that Wave 2 produces.

## Consequences

- **Two assertions were vacuous until their own plants ran**, and both were the author's:
  `A8` asserted an absence over an output that the mutation had emptied — an absence over nothing
  reads as true — and `A35` matched the prose in the adapter's header explaining the very regex it
  was checking (rule 12, inside the file that documents rule 12's lesson). Neither would have been
  found by review, and both are recorded at their site.
- **The wrong file predicate shipped twice, and neither instance was caught by review.** The
  adapter resolver tested `-x` for a file it invokes as `bash <path>`, where only `-r` matters, and
  `staging/` is inconsistent about the execute bit (`stop-gate.sh` 755, `dispatch-state.sh` 644):
  the probe resolved nothing in a source checkout and would have worked after deployment. Then
  `--json-file` tested `-f`, which excludes pipes — true for a heredoc on macOS, where bash
  materialises one as a temp file, and **false on Linux**, where bash 5 gives it a pipe. The
  harness was green locally and red on CI with 25 assertions producing empty output.

  The class is *asking about the wrong property of a file*, and both instances share a signature:
  the check agreed with itself on the machine it was written on. `A36` now drives `--json-file`
  through process substitution so the pipe case is executed rather than assumed.
- **A single-platform green is not a green.** Every local run here is macOS; the CI runner is
  Linux. The heredoc defect was invisible to 81 green harnesses and one real end-to-end run, and
  visible immediately to the first CI execution. Worth remembering the next time a local suite is
  offered as sufficient evidence.
- The CI harness list grows to 81. Nothing here runs per turn, so the stop-gate's measured 159s is
  unchanged; the cost lands only when the lane calls it.
- This wave is **attended**. It introduces a new TOFU surface, and arming it unattended is not in
  scope.
- Issue #439 cites its full plan at `~/.claude/plans/humming-crunching-micali.md`. That file was
  reused for a different issue the next day and the plan is gone — plan filenames are randomly
  assigned and recycled, so rule 12 applies to them too, on a horizon of under 24 hours. The issue
  body was the surviving source. Wave 3 should re-point the reference.

## References

- Issue #439; ADR-0138 (citation is not implementation), ADR-0086 (guard rather than extract),
  ADR-0047/ADR-0048 (reporter versus checker), ADR-0010 (the rejected web e2e harness, still
  `Proposed` and still referenced by `clean-public-repo`).
- CLAUDE.md rules 2, 4, 5, 6, 7, 8, 9, 12 and 16.
