# ADR-0142 — the lane's defence against context rot is an artifact, not the conversation (issue #439, Wave 2)

- **Date:** 2026-08-15
- **Issue:** #439 — "the chain discards the conversation and never runs the product"
- **Scope:** Wave 2 of three. Wave 1 shipped the executed acceptance verdict (ADR-0141, `722a01a`);
  Wave 3 is the lane ADR, the scoped blueprint deviation and the remaining wiring.
- **Extends:** ADR-0141. **Amends:** nothing. **Moves code out of** `spec-coverage.sh` (see D4).

## Status

Accepted.

## Context

Wave 1 built the layer where an `R-NN` passes only by being executed. It answers *did the product do
it*. Nothing produced the criteria it reads, and no `ACCEPTANCE.md` existed anywhere.

Wave 2 is the producer: brief → interview → `SPEC.md`, `BRAINSTORM.md`, optional `UX-BLUEPRINT.md`,
`ACCEPTANCE.md` → a printed `/goal` contract that closes on Wave 1's output.

### The premise that inverted

Issue #439's original reasoning was that the chain loses intent because it **discards the
conversation** — five lossy compressions between the operator and the `coder`, which reads the plan
and never the operator. The proposed remedy was a single-session lane that keeps everything in
context.

The operator then confirmed that "performance decay" means **quality degrading over a long
session**. That is the same mechanism seen from the other end: unbounded context is exactly what
rots. A single-session lane that defends intent *by holding the conversation* would trade one
failure for the other.

So the lane's defence is **artifacts on disk that every turn re-reads**, not the transcript:
`BRIEF.md` verbatim, and an `ACCEPTANCE.md` whose id set is machine-checked. Writing the brief
unedited is the highest-value instruction in the skill for that reason, and the `/goal` contract's
`Read first:` line is load-bearing rather than decorative.

## Measured before designing

- **`interview-driver` states the SPEC axes in one line of prose** in a 40-line skill. It already
  carries the `- [ ] R-NN` template and ADR-0138's `(no-test: <reason>)` marker, so this wave
  inherits the id scheme rather than inventing one. The nine axes are enumerated in `brief-to-app`
  because a one-line list is what gets skipped.
- **Only three skills actually set `disable-model-invocation`** — `goal-loop`,
  `fastapi-react-vibe`, `research-prompt`. Three more mention it in prose, and a plain grep says
  six. Checked in the frontmatter: `design-brainstorm` and `macos-ux` can be dispatched; `goal-loop`
  cannot, so the contract is **printed**.
- **No SPEC in this repository uses `(no-test:)` yet** — ADR-0138 is two days old. The exemption
  path therefore has fixtures as its only evidence, which is stated here rather than implied away.
- **`spec-coverage.sh --list` still requires `--plan`**, so it cannot serve as a "list this SPEC's
  ids" utility for a lane that produces no plan.

## Decision

### D1 — `acceptance-declare.sh` is a CHECKER, and it runs in both directions

Exit code is the policy channel — `spec-coverage.sh`'s idiom, and deliberately **not** the reporter
contract of the two acceptance scripts one directory away.

| exit | meaning | stdout |
|---|---|---|
| 0 | reconciled | nothing |
| 1 | a testable criterion has no case | `UNDECLARED<TAB>R-NN` |
| 2 | bad invocation | nothing |
| 3 | structural / could-not-run | `ORPHAN`, `CONTRADICTION`, `NO-IDS`, `NO-PREDICATE` |

Checking only that every criterion has a case is blind by construction to a case naming an id the
SPEC never declared — a criterion deleted from the SPEC leaves its case behind and the forward check
reports clean (rule 8). Structural outranks undeclared so the reader is sent to the harder repair.

### D2 — `NO-IDS` is exit 3, diverging from `spec-coverage.sh` on purpose

`spec-coverage.sh` exits 0 silently on a SPEC with no ids, for backward compatibility with SPECs
written before ids existed (ADR-0048 §D7/§D8). This script has no legacy corpus, and a
reconciliation whose subject set is empty covers nothing while reading as clean — rule 9. The
divergence is stated at both ends so the next reader does not "fix" the two into agreement.

### D3 — the adapter's declared side gets its own pattern, because it reads a different document

`--declared` reads **markdown**; `IDRE` reads **Swift method names** and is necessarily loose,
because a Swift identifier cannot contain a hyphen. Measured across the 48 files in this repo
carrying an `R-NN` checklist, the two diverge on exactly one string: `ISSUE-R-013`, in ADR-0048 —
the counterexample that ADR itself names. Zero divergence across the 47 real SPECs.

`DECLRE` therefore takes `spec-coverage.sh`'s **boundary** (`_` excluded on the left, hyphen
required, exactly two digits) but **not** its right anchor `([^0-9]|$)`, which consumes the
following character. That is correct for the `grep -q` membership tests it serves there and wrong
for a global extraction, where it would swallow the separator and miss the second id in
`R-01 R-02`. A lookahead is the same rule without the consumption, so the harness pins **behaviour**
on both files' counterexamples rather than pinning two strings to be equal.

### D4 — `item_text()` and `strip_sep()` move into the shared predicate

They were local to `spec-coverage.sh` while it was the only consumer. `acceptance-declare.sh` is the
second, and two copies deciding what a checklist item's *text* is would disagree exactly where it
matters: the reconciliation would report a criterion undeclared because one side kept a leading
separator the other stripped.

`spec-id-predicate.awk` exists for this — it already says "two consumers, and they must never
disagree" — so this is the file's own rule applied on its own terms rather than a copy added beside
it (rule 6, and ADR-0122's precedent of one `strip_emphasis()` shared by reader and repairer). awk
rejects a duplicate function definition, so a re-added local copy breaks the chain's checker at load
time; `B14` asserts the move rather than trusting it. `spec-coverage.test.sh` stayed at 144 PASS / 0
FAIL across the move.

### D5 — what this wave enforces, said once and plainly

**Enforced:** one mechanism. `acceptance-declare.sh`, run by a declared fence that halts the lane on
any non-zero exit. Wave 1's `acceptance-run.sh` is the second, and it runs inside the `/goal` loop
rather than in the skill.

**Instruction only:** everything else in a 190-line SKILL.md — that the brief is verbatim, that the
interview covers nine axes, that alternatives are explored, that a case states an observable rather
than a restatement. A green Step 5 means the two documents agree about which ids exist. It does not
mean the criteria are good. The skill says this about itself in its closing section, and `B27` is
the assertion that the statement is still there.

## Consequences

- **Two assertions were wrong in ways only execution showed**, and both were the author's.
  `B15`'s fixture contained a real `R-01` in its own prose, so a rejected `ISSUE-R-013` and an
  accepted one produced identical output — an earlier probe had "confirmed" the rejection on exactly
  that ambiguity. `B20` matched an undecorated clause against a bolded one, which is rule 3 in the
  file that cites rule 3.
- **`--predicates` had to become authoritative rather than a first preference.** The first probe
  returned exit 1 where `NO-PREDICATE` was expected, because the resolver fell through to the next
  directory: a caller naming one predicate and silently getting another, and an exit-3 branch
  unreachable from outside — a state nothing can produce (rule 17).
- **`F4` accepted this wave's fence as covered while it had never been executed once.**
  `fence-contract-coverage.test.sh`'s F4 counts a contract as run when a test file contains the
  literal `fence-contract: <id> -->`, reasoning that a bespoke extractor cannot pull a fence out
  without naming its id. True for an extractor; false for `B23`, which greps for the marker to
  assert the declaration exists. F4 went green on a fence nothing had run — rule 18, a scan
  satisfied by the whole population it searches rather than the part it meant, in the guard whose
  own ADR (ADR-0107) records the previous instance of that.

  `B28`/`B29` now extract the fence and execute it under a fake deployed `$HOME`, so this contract
  is covered for the right reason. **The general exposure is measured but not resolved:** of 40
  declared contracts, 22 are covered by an actual `run_fence "<id>"` call and **18 by the marker
  form alone**. One of the 18 was this wave's and was a mention only; the other 17 may well be
  genuine extractors, and this ADR does not claim otherwise — it records that F4 cannot tell the
  two apart, which is a separate issue from #439.
- The `(no-test:)` exemption path is covered by fixtures only, because no real SPEC uses it yet.
  When one does, re-run the reconciliation against it before trusting the exemption in anger
  (rule 13).
- The lane **inherits two skills it does not own**. If `design-brainstorm` or `macos-ux` changes,
  the lane changes, and nothing guards that. Accepted, not solved.
- `ACCEPTANCE.md` remains gameable in the way `weakening-scan.sh` documents: an **in-place**
  assertion edit is invisible to every detector. This wave pins the id set, which is the count half;
  it cannot pin that a case still asserts something real.
- The CI harness list grows to 82.

## References

- Issue #439; ADR-0141 (Wave 1), ADR-0138 (citation is not implementation and the `no-test:`
  marker), ADR-0048 (the `ADR-NNNN` boundary and its counterexamples), ADR-0122 (one predicate
  shared by reader and repairer), ADR-0086 (guard rather than extract — and D4 is the case where
  extraction won), ADR-0067 (`disable-model-invocation` and chain dispatch), ADR-0093
  (`detect-macos.sh`), ADR-0083 (fence contracts).
- CLAUDE.md rules 3, 4, 6, 8, 9, 13, 16, 17.
