# ADR-0104 — Step 7's commit had nothing left to describe

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #249 (found by the Phase 7.1 shakedown run at Step 7 for #222)
- **Related:** ADR-0068 §D5 (the merge-back that commits each worktree), ADR-0049 §D1
  (tester-before-coder, which doubled the snapshots), ADR-0103 (#244 — the baseline this resets to,
  and the state it must refuse), ADR-0071 (Gate 4.0, the commit the baseline sits on)

## Context

When Step 7 runs, the branch looks like this:

```text
6e46246 chore(step5): snapshot tester worktree (tester)
6868644 chore(step5): snapshot coder worktree (coder)
…                                          (seven in total)
6e89087 chore(222): record Step 5 pre-flight result; run paused at #241
f1a1df0 chore(222): record Gate 4 autopilot mode and the Step 5 transition
c644b60 docs(222): SPEC, ADR-0087 and plan for deployed-only skills
```

Ten commits, 1260 insertions. **Not one of them describes the feature.**

By then the staged set is the manifest and `.gitignore`, so the `commit` skill's Step 2 reads
`git diff --staged` and composes a message describing a manifest state change. **The commit the
whole skill exists to produce has nothing left to describe.** The skill itself is fine — it
faithfully describes the diff it is given.

### Nobody chose this

ADR-0068 §D5 made the orchestrator the committer, with a fixed message, so the next stage's worktree
could fork from a `HEAD` containing the previous stage's output. ADR-0049 §D1 ordered
tester-before-coder, which took the snapshots from one per task group to two. **Two correct
decisions composing into a third behaviour neither considered.**

It is survivable here because this repository squash-merges. On a repo that merges with a merge
commit, or reads `git log` for a changelog, or bisects, the history is seven "snapshot worktree"
entries and no feature commit.

## Decision

### D1 — Step 7.0 collapses the Step 5 snapshots back into the index

`git reset --soft <recovery_baseline_sha>` before invoking `commit`, so the whole feature is staged
as one diff and the skill composes a real message.

**The snapshots exist so the NEXT stage can fork from them. Step 5 is over, so their purpose is
spent** — nothing forks from these commits again. That is the argument; without it this is just
rewriting history because the log looks untidy.

**A soft reset keeps the working tree and the index exactly as they are.** No content is created,
changed or deleted; only the branch tip moves, and the collapsed tips stay in the reflog. That is
why it needs no gate of its own — `commit`'s Step 4 gate still shows the resulting diff before
anything is written.

### D2 — The guards are the design, not caution

Four refusals, each returning `COLLAPSE_SKIP <reason>` and leaving `HEAD` untouched:

- **`foreignCommit`** — the range holds a commit whose message matches neither the merge-back's
  snapshot form nor the chain's own bookkeeping form. Folding it away would take **its message**
  with it. Nothing is lost, but a record is.
- **`notAncestor`** — #244's state. Resetting to a non-ancestor detaches the branch from its own
  history. This ADR **refuses** that state rather than inheriting it, which is why #249 depended on
  #244: the check ADR-0103 added reports, and this one acts on the same fact.
- **`baselineGone`**, **`noCommits`**, **`noBaseline`** — nothing to do.
- exit 3 outside a repository: did not run, never a silent success.

### D3 — The alternatives, and why they lose

Carrying the topic in the snapshot message makes the log legible and still leaves no commit
describing the whole. Documenting Step 7 as a bookkeeping commit with the PR body as the description
of record is honest and the least work — but it makes **squash-merge a hard requirement of the
chain**, which nothing currently says, and this chain is meant to run on repositories whose merge
policy it does not choose.

## Verification

12 assertions in `step7-snapshot-collapse.test.sh`, plus a `Z1` floor. Harness 65/65. The collapse
is **executed against real git history**, including a real `git rebase` for the `notAncestor` case.

Seen RED against the unmodified tree: **10 of 12** — `SC1` through `SC7`, `SC9`, `SC10`, `Z1`.
`SC0` and `SC8` are anchors and the cross-file forward guard.

Six planted defects, all fired:

| plant | fires |
|---|---|
| the foreign-commit guard removed | `SC4` — `COLLAPSED 3`, a human's commit folded away |
| the ancestry guard removed | `SC5` — `COLLAPSED 4` onto an orphaned object |
| the no-repo guard removed | `SC7` — reports `COLLAPSE_SKIP baselineGone` outside a repo |
| the empty-range guard removed | `SC6` — `COLLAPSED 0`, a reset to itself |
| the merge-back message reworded | `SC8` |
| the collapse moved after the invocation | `SC1` |

### The plant that did not fire, and what it was telling me

Removing the ancestry guard left `SC5` **passing**. The fixture's default-branch commit was
`git commit -qm c`, and after the rebase that commit sits in the range — where the
**foreign-commit** guard caught it first. So `SC5` passed for a reason it does not name, and the
plant aimed at the guard it does name hit nothing.

**An assertion covered by two guards isolates neither.** The fixture's commit now carries a
chain-shaped message, so only the ancestry guard can refuse, and the plant fires. ADR-0089's rule
applied again: a plant that does not fire is evidence about the assertion, not a formality.

## Consequences

- **The chain now rewrites its own branch history**, once, at Step 7, under four guards. It is a
  soft reset so nothing is destroyed, and it is the first place the chain moves a branch tip
  backwards.
- **`SC8` is a cross-file contract.** The collapse matches the literal message the merge-back
  writes; rewording that message makes the collapse stop recognising its own commits and refuse on
  every run — quietly, since `COLLAPSE_SKIP` is a normal outcome. The assertion is what makes that
  loud.
- The bookkeeping pattern (`chore(<scope>): record …`) is matched by shape, so a future chain commit
  worded differently reads as foreign and blocks the collapse. Safe direction, and it will look like
  a regression when it happens.
- **The collapsed commits remain in the reflog only**, so a `git gc` after Step 7 removes the
  intermediate history for good. That is the intent, and it is worth knowing before the first run.
- The fence is declared and `fence_is_abort_capable` cannot see it — no literal `exit 1`/`exit 2`,
  no "abort" — so F3/F4 do not reach it; executed by its own file instead. Fourth measured example
  outside ADR-0083's population, after ADR-0096, ADR-0102 and ADR-0103.
- Inert until sync.

## Correction 2026-07-31 (issue #281, ADR-0107)

The consequence above says this fence is outside `fence-contract-coverage.test.sh`'s `F3`/`F4` and
is "executed by its own file instead". The second half was true; the first is no longer.

`CONTRACT_IDS` was derived from the **abort-capable** subset rather than from the declarations, so
five declared contracts — this one among them — sat outside `F4`, `F6` and `F7`. ADR-0107 widened
the derivation to every declaration. The fence is now checked by the guard as well as by its own
file, and `F9` fails if that derivation ever narrows again.

Body unedited (ADR-0034 precedent).
