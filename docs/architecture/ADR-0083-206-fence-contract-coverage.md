# ADR-0083 — An abort-capable fence declares itself, and a contract is executed

- **Status:** Accepted
- **Date:** 2026-07-29
- **Issues:** #206 (closed), #218 (found by this work, fixed here)
- **Related:** ADR-0069 (#172, the first extract-and-run), ADR-0070 (#174, the receipt), ADR-0077
  (declared exemption in the file being guarded), ADR-0081 (false green), ADR-0082 (derive, then
  narrow by declaration)

## Context

Rule 11: a prose code block nobody has executed is unverified code. Across
`staging/plugin/skills/*/SKILL.md` there are 138 bash fences; a subset can **abort a run**, and
most of that subset had never been executed by anything.

The receipt is #174: `autopilot-build` check 5 read a leading dash as a getopt option, exited 2
without running, and aborted on **every** plan — with a message blaming the plan. That block had
sat in the file through several audits, read by humans, looking correct.

## Decision

### D1 — Recount before building on a count (§the issue's arithmetic)

Issue #206 reported **15** abort-capable fences of which **~6** covered. Measured here: **13**
abort-capable, **4** covered.

- The 15 came from matching `ABORT` as a **substring**, which also hits the word "aborted" in two
  fences that cannot abort anything.
- The 6 counted `extract_conductor_lookup`, whose fence is not abort-capable at all.

Both inputs were off by two in the same direction, so `15 − 6` and `13 − 4` agree on 9. **Two
wrong numbers subtracting to the right one is not a check.** `S5`/`S6`/`S7` pin the word-boundary
predicate, including the specific case that produced 15.

### D2 — `bash -n` is the contract-versus-illustration classifier

The issue calls the contract/illustration distinction "arguably the deeper finding" and asks for a
marker. A marker is a declaration; the question is what to declare. Of the 13, **exactly one** is
not syntactically valid bash: `concept-to-code`'s merge-back block, which carries `<base-fork
halt: …>` and `<conflict halt: …>` pseudo-code where the halt procedures go. It specifies a
protocol for the orchestrator, not a script.

So the split was measured, not settled by taste, and it produced one illustration and twelve
contracts. `F7` keeps it: a fence declared a contract must at minimum parse.

### D3 — The marker is the extraction anchor, and that is its second job

```
<!-- fence-contract: <id> -->            executed by a test; the id names the execution
<!-- fence-illustration: <reason> -->    deliberately not executable; one line, >= 40 chars
```

Every pre-existing extractor in this harness anchors on a **heading**. The issue warned that a
heading rewrite "turns extraction into a skipped section that passes quietly", and ADR-0069's
`CLAUDE.md` note says the same. **Measured, by rewording the anchor headings and re-running, both
descriptions are wrong, and the truth is worse in two different ways:**

| harness | before | after rewording the heading |
| --- | --- | --- |
| `plan-task-count.test.sh` | 43 passed, 0 failed | 35 passed, **2** failed |
| `scope-guards.test.sh` | 29 passed, 0 failed | 27 passed, **2** failed |

1. **Assertions vanish.** Six of `plan-task-count`'s left the run. A suite reporting "35 passed, 2
   failed" reads as two broken checks, not as six checks that no longer exist. Nobody watches the
   assertion count.
2. **`scope-guards` misattributes.** Its two failures read `A5: child CWD should ABORT` and
   `A6: sibling directory should ABORT` — they **blame the guard**. An empty extraction produces an
   empty script, an empty script exits 0, so every *positive* assertion in the section goes green
   and only the abort ones fail. A reader goes hunting for a bug in check 1 that does not exist.
   Same family as ADR-0081: half a section passing for the wrong reason.

Three fixes, all in this change:
- **Marker anchors** on all five pre-existing extractors, so a heading rewrite breaks nothing.
  Verified: rewording `**Check 1 —` now leaves `scope-guards` at 30/30.
- **Empty extraction returns 97**, outside the fence's own `0|1` contract, so no assertion can read
  it as pass or abort. Verified: deleting the marker now fails **all four** A-assertions, was two.
- **An assertion-count floor** (`Z1`) in each of the three files. A floor rather than an exact
  count: it catches a vanished assertion without needing a bump every time one is added.

### D4 — F4 accepts two needles, both of them executions

`run_fence "<id>"` (this file's helper) or the literal `fence-contract: <id> -->` (a bespoke
extractor anchoring on the marker). The second exists because four fences were already covered
elsewhere; those extractors were **re-anchored**, not reimplemented. A test cannot extract the
fence without naming its id, so coverage is verified rather than declared — a
`# covered elsewhere` comment would have been a claim, and that difference is the whole point of
the check.

### D5 — Both directions per contract

Twelve contracts, each asserted on a good fixture **and** on the bad input it exists to catch. A
negative-case assertion pins nothing without its positive twin (ADR-0039): a check that aborts on
everything satisfies the negative alone. This is exactly how #218 surfaced.

Fixtures patch a **real** manifest, and the base is chosen by *running* `manifest-validate.sh` over
the corpus rather than by picking one that looks complete — this repository's manifests carry a
`project_root` from another machine, and invariant 4 skips the existence check only for terminal
states (ADR-0078), so flipping `current_step` to a live value makes a valid manifest fail for a
reason unrelated to any fence.

## Consequences

- **#218: `autopilot-build` check 2 has never been able to pass.** `awk '{print $2}'` does not
  strip the quotes that `manifest-init.sh` and `manifest-transition.sh` both write, so the
  comparison was never true and the pre-flight aborted on every manifest the system has ever
  produced — printing `current_step is "ready_for_implementation", not ready_for_implementation`.
  A singleton, and that is the interesting part: `manifest-validate.sh` uses the correct `sed`
  idiom at 17 sites and check 1 uses a correct 3-sed chain twenty-five lines above. Check 2
  invented a third. Found by running the fence, not by reading it.
- **The commit fence's abort path is not forced.** `E17`–`E19` assert the branch-creation
  contract, the no-op-on-a-feature-branch half, and the slug guard that stops a subject of "main"
  producing `feat/main`. Making `git checkout -b` fail needs a corrupted ref namespace; the abort
  branch is uncovered and named here rather than implied.
- **`fence_is_abort_capable` is a lexical predicate.** A fence that aborts by calling a script that
  exits non-zero, with no `exit` of its own, is outside the population. Twelve contracts is a floor
  on the abort-capable set, not a proof of its size.
- **Two markers are inside fenced list items** (`nightly-autopilot`, `claude-md-slim`), so the
  parser must be indentation-tolerant — `S3` pins it. The issue's own first count said 101 instead
  of 138 for exactly this reason.
- **No synthetic pseudo-code fixture exists, and that is deliberate.** Two drafts were written and
  **both parsed as valid bash** — `foo <bar baz>` is a redirect plus a command, and
  `… || <base-fork halt: … stop>` followed by another line consumes that line's first token as the
  `>` target. The construct only fails when the pseudo-code closes the block. `S9` therefore runs
  the classifier over the real fence (rule 10).
- Seen RED before the fix: 23 of 37. `F5`, `F6`, `F7` passed on the empty declaration set and are
  forward guards, not fix evidence; `F3` listing all 13 unmarked fences is the red evidence.
