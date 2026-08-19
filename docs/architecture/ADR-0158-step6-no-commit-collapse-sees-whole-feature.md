# ADR-0158 — the collapse sees the whole feature, and Step 6 stops committing

- **Topic slug:** `step6-no-commit-collapse-sees-whole-feature`
- **Issue:** #489, and #479 (the commit skill dropping review fixes, closed by removing the cause)
- **SPEC:** none — a bounded change to one fence and two paragraphs, no requirement ids
- **Extends:** ADR-0104 (the Step 7.0 collapse fence and its `_foreign` guard, unchanged here).
  Supersedes nothing.
- **Deliberately does not touch:** `_foreign`'s allowlist, or `commit`'s own staged/unstaged split

## Status

Accepted — 2026-08-19.

## Context

Step 7.0's collapse fence (ADR-0104) folds every Step 5 snapshot commit into one staged diff with
`git reset --soft "$_b"`, but only after `_foreign` confirms every commit in the range carries one of
two mechanical subjects: `chore(step5): snapshot … worktree (` or `chore(…): (record|snapshot)`
followed by a required trailing space. A commit outside that allowlist aborts the whole collapse —
by design, ADR-0104 §D2: folding a commit the chain did not make would take a human's message
with it.

Reported from the same field run as ADR-0157: a Step 6 review correction landed as a `test(...)`
commit mid-feature. `_foreign` did exactly what it is for — refused to fold a commit it could not
attribute — and the feature stayed scattered over nine snapshot commits, never collapsed, never
merged as one diff.

### The commit that should not have existed

`commit`'s own scope rule (`skills/commit/SKILL.md:89`) is unambiguous: something already staged →
included set is `staged` only, and unstaged tracked changes are *mentioned as not included*, never
silently added. After Step 7.0's soft reset the whole feature sits staged. A Gate 5.06 correction
made *after* that point and never re-staged is therefore not dropped by `commit` misbehaving —
`commit` is doing what it is told. It is dropped because nothing told it the correction existed.

The field run's actual failure mode was upstream of that: rather than leave the correction unstaged
for `commit` to warn about, the chain committed it directly, under a subject `_foreign` cannot
attribute. Two defects from one root cause: #479 (the fix silently dropped, when a correction stayed
uncommitted-but-unstaged) and #489 (the collapse aborted outright, when a correction was committed
under an unrecognised subject). Both disappear if Step 6 and Gate 5.06 never commit at all.

## Decision

### D1 — Step 6 and Gate 5.06 make no commit of their own

A controller-side correction — a fix the orchestrator applies directly, as opposed to a fix an
already-`chore(step5)`-committing worktree agent applies — is left as a plain tracked modification.
Nothing stages it, nothing commits it. It sits in the working tree until Step 7.0 runs.

This is the smaller change of the two available (see A1): it removes the reason the chain ever
produced a foreign-subject commit mid-Step-6, rather than teaching `_foreign` to recognise one more
shape.

### D2 — the collapse fence sweeps it up

After a successful `git reset --soft "$_b"`, the fence runs `git add -u` and reports how many paths
it staged:

```bash
git add -u
_staged_n=$(git diff --name-only --staged | wc -l | tr -d ' ')
echo "COLLAPSED $_n $_b staged=$_staged_n"
```

`git add -u` stages tracked modifications, deletions and renames — **never** untracked files. That is
the exact scope `commit`'s own Step 1 already applies, and it is deliberately not `git add -A` /
`git add .`, which would also stage whatever debris the chain's own worktree-escape check exists to
catch (ADR-0068 §D11). `COLLAPSED`'s reported `staged=<k>` is therefore `>= <n>`'s file count whenever
a post-snapshot correction existed to sweep in, and equal to it otherwise — the caller can tell the
two cases apart without re-deriving anything.

A soft reset changes nothing about the working tree or the index — only the branch tip moves, and
the collapsed tips survive in the reflog — so adding one more staging step ahead of `commit`'s own
Step 4 gate needs no new gate of its own; the diff `commit` shows before writing anything already
covers it.

### D3 — `_foreign`'s allowlist is untouched

The guard did the right thing when it refused to fold a commit it could not attribute. Widening the
allowlist to recognise a Step 6 correction's subject would have been the other fix (A1) and was
rejected: it grows the set of subjects the fence must trust are chain-made forever, for a case D1
removes at the source. `foreignCommit` keeps exactly its current behaviour, and the fence's `COLLAPSE_SKIP
<reason>` path still exists for the case that genuinely matters — a human's commit landed in the
range, and folding it away would be the real defect.

## Consequences

- A Gate 5.06 or Step 6 correction survives the collapse as part of the one staged feature diff,
  closing #479 without changing `commit`'s staged/unstaged contract.
- A Step 7.0 collapse no longer aborts on a correction the chain itself produced, closing #489.
- `COLLAPSED`'s `staged=<k>` count gives the operator a cheap signal — `<k>` above `<n>`'s tracked
  file count means a correction was swept in — without a second mechanism to keep in sync.
- **Not addressed.** A worktree fix agent still commits its own output under `chore(step5): snapshot
  … worktree (`, unaffected by D1 — that path was never the problem, and `_foreign` already
  recognises it.

## Alternatives considered

**A1 — widen `_foreign`'s allowlist to recognise a Step 6/Gate 5.06 commit subject.** Rejected: it
keeps producing a mid-feature commit that has to be specially recognised forever, growing the trusted
subject set on every future controller-side commit path. Removing the commit removes the need to
recognise it — the smaller, permanent fix.

**A2 — a ledger of controller-side corrections, read at collapse time.** Rejected on CLAUDE.md rule
6: a second record of the same fact the working tree already carries (which files changed) is a copy
that can disagree with its source, for no question the working tree cannot already answer.

**A3 — `git add -A` instead of `git add -u`.** Rejected: it would stage untracked debris the
worktree-escape check exists to catch, which is the exact boundary SC12 (below) pins.

## Test and plant obligations

`step7-snapshot-collapse.test.sh` — SC11, SC12 (window bumped to accommodate both, floor `Z1` bumped
11 → 13 for the two new assertions):

- **SC11** — a tracked file edited *after* its own snapshot commit and never re-committed is present,
  with its corrected content, in the collapse's staged diff. Plant: mutate `git add -u` /
  `_staged_n=...` away; SC11 goes red.
- **SC12** (forward guard, CLAUDE.md rule 6's boundary) — an untracked file is **not** staged by the
  collapse. Pins `git add -u` against a future `git add -A` regression.

## References

- Issue #489, and #479 (closed by the same fix)
- ADR-0104 — the Step 7.0 collapse fence and the `_foreign` guard this ADR leaves unchanged
- ADR-0068 §D11 — the worktree escape check `git add -A` would have bypassed
- `skills/commit/SKILL.md:89` — the staged/unstaged scope rule this ADR keeps intact
- CLAUDE.md rule 6 (A2), rule 17 (a producer and a consumer nothing checks meet — the shape of the
  underlying defect: Step 6 producing a commit fence 7.0 had no way to expect)
