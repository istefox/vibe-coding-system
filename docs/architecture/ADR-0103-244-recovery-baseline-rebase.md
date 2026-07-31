# ADR-0103 — The baseline did not move; the history under it did

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #244 (found by the Phase 7.1 shakedown run while resuming the paused #222 chain — the
  first finding the run *produced* rather than encountered)
- **Related:** ADR-0050 §D3 (the invariant this clarifies), ADR-0089 (#239, why a paused Step 5 is
  the normal state), ADR-0034 (bodies not edited in place), ADR-0083 (fence contracts)

## Context

ADR-0050 §D3 writes `recovery_baseline_sha` once at Step 5 entry and never rewrites it — *"a
baseline that moves is not a baseline"*. Correct as far as it goes, **and it assumes the history
under the sha does not move either.**

Observed while resuming #222:

```text
baseline recorded: dfa9a6ff0ce1a3c65d2ed2034ac5ff84e2b0d0fe
git cat-file -e                                  → object still exists (reflog only)
git merge-base --is-ancestor <baseline> HEAD     → FALSE
equivalent commit after rebase                   → f1a1df072fcb172a01605824e43bcdc45f89b5b9
```

The recorded baseline is no longer an ancestor of the branch it describes. It survives only in the
reflog, so it is one `git gc` from disappearing, and a recovery that reset to it would detach from
the feature branch's actual history.

**The sha is still the right *state* and no longer the right *object*, and §D3 has no answer for
that.** It reads as if it did.

### Measured: one of two, and it is the one that was paused

```text
2026-07-30-222-…  dfa9a6ff…  object exists  ORPHANED   (paused across a rebase)
2026-07-28-176-…  129d5e09…  object exists  ancestor   (never paused)
```

The sequence is not exotic — it is the paused-run workflow. Step 5 records the baseline, something
halts the run, fixing the blocker means a PR to `main`, resuming means bringing the branch up to
date, and a rebase is the obvious way to do that. ADR-0089 already establishes a paused Step 5 as
the normal state rather than the exception.

## Decision

### D1 — An ancestry check on the resumed-run branch, which REPORTS and never halts

Three states, each needing a different sentence to a human:

- `BASELINE_OK` — say nothing.
- `BASELINE_ORPHANED` — the object exists but is not an ancestor: rebased away, reflog-only, one
  `git gc` from unrecoverable, and a reset to it would detach.
- `BASELINE_GONE` — the object does not exist at all; there is nothing to reset to.

`RB9` pins the second and third apart. Collapsing them tells a human "gone" when the commit is
recoverable, or the reverse.

**Reporting rather than halting is the decision, not a default.** The run is not damaged, only its
recovery path is, so a halt would trade a working run for a hypothetical one. That is the opposite
call from the four pre-flight assertions above it, which fail closed — and the reason differs: those
guard *entry* to a state the chain cannot safely be in; this describes a *contingency* that may never
be exercised.

### D2 — Exit 3 for "did not run", and it is load-bearing here

Outside a git repository, or with an empty baseline, the check exits 3 and the caller says so.
Without it, `git cat-file -e` fails and the check reports **`BASELINE_GONE`** — a definite, alarming
verdict produced by a check that never ran. `RB10` pins it, and the plant that removes the guard
produces exactly that output.

### D3 — The operational rule, stated where the baseline is written

**Merge `main` into the feature branch; do not rebase it, once `recovery_baseline_sha` is set.** A
merge preserves the recorded commit as an ancestor; a rebase orphans it. Nothing in
`concept-to-code/SKILL.md`, ADR-0050 or the pre-flight said this — verified by search before writing
it — and nothing checked it.

### D4 — The field is never corrected, including when the check says it is orphaned

§D3's write-once rule is worth more than any single record, and a baseline that gets "fixed"
whenever it looks wrong is a baseline again only in name. `RB5` is the forward guard.

The #222 manifest keeps `dfa9a6ff…`; the equivalent post-rebase commit is `f1a1df07…`, recorded in
issue #244 and here — where a human looking for it will be, rather than in a field an ADR says
must not move.

### D5 — The structural option is deferred, with its reason

Recording something rebase-stable — a tag, or the tree hash rather than the commit — is a bigger
change and needs its own argument about **what recovery actually resets to**. A tree hash is stable
across a rebase and is not a commit, so `git reset` to it is not the same operation; a tag is a new
object the chain would have to create, name, and clean up. Neither is a drop-in for a sha, and
choosing without answering the reset question would be inventing a mechanism to avoid writing a
sentence.

## Verification

13 assertions in `recovery-baseline-rebase.test.sh`, plus a `Z1` floor. Harness 64/64. The check is
**executed against real git history** — including an actual `git rebase` that reproduces #222's
state — not asserted to exist.

Seen RED against the unmodified tree: **9 of 13** — `RB1`, `RB2`, `RB3`, `RB4`, `RB6`, `RB7`, `RB8`,
`RB9`, `RB10`. `RB0`, `RB5`, `RB11` and `Z1` pass before and after; `RB5` is the write-once forward
guard and `RB11` re-derives the corpus measurement rather than trusting the number in this ADR.

Six planted defects, all fired:

| plant | fires |
|---|---|
| the merge-not-rebase rule removed | `RB1` |
| "report, not a halt" turned into a halt | `RB3` |
| `GONE` and `ORPHANED` collapsed into one token | `RB9` |
| the no-repo guard dropped | `RB10`, reporting `BASELINE_GONE` outside a repo |
| the write-once invariant removed | `RB5` |
| the ADR-0050 correction removed | `RB4` |

## Consequences

- **A resumed Step 5 now prints a warning that did not exist**, and on this repository's own #222
  manifest it would fire immediately. Correct, and it will look like a new problem the first time.
- **The rule is an instruction with no enforcement.** Nothing stops a human rebasing; the check
  reports afterwards. Enforcing it would mean policing git operations outside the chain's turn,
  which is not a boundary this system has anywhere.
- **The check is declared and `fence_is_abort_capable` cannot see it** — no literal `exit 1`/`exit 2`
  and no "abort", by design, since it never halts — so `fence-contract-coverage.test.sh` F3/F4 do
  not reach it. Executed by its own file instead. Third measured example of what sits outside
  ADR-0083's population, after ADR-0096 and ADR-0102.
- `RB11` couples this ADR to a corpus of two. A third baseline changes the ratio and not the
  argument, but the number in the prose will drift from the number in the run.
- Inert until sync.
