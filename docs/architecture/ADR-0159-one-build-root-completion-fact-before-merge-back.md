# ADR-0159 — one build root per checkout, and the completion fact read before the merge-back

- **Topic slug:** `one-build-root-completion-fact-before-merge-back`
- **Issue:** #488 (concurrent builds share a root), #494 (the completion fact read at a removed path)
- **SPEC:** none — bounded changes to one generator, one pre-flight gate and one dispatch-ordering
  instruction, no requirement ids
- **Extends:** ADR-0068 (the worktree isolation contract — `isolation: worktree` bounds the working
  directory, not the filesystem), ADR-0139 (`dispatch-state.sh`, the completion-fact mechanism this
  ADR reorders around, unchanged in its own logic). Supersedes nothing.
- **Deliberately does not touch:** `dispatch-state.sh`'s own contract, or `_foreign`'s allowlist

## Status

Accepted — 2026-08-19.

## Context

Two defects from the same field run, both about a resource an `isolation: worktree` dispatch does
not actually isolate.

### #488 — the build root is not one of the things a worktree isolates

`isolation: worktree` gives each dispatch its own working directory (ADR-0068). It does not give a
compiled-language build its own build *output* directory. `detect-test-cmd.sh` wrote
`xcodebuild test -workspace … -scheme … -destination …` with no `-derivedDataPath`, so the build
location is whatever the machine's Xcode preference resolves to — and a custom absolute location is
the same one for every checkout on the machine, worktrees included.

Reported live: a tester's worktree was still building while the controller ran verification in the
main checkout. Observed cost was an unsigned framework and a false red. The direction that matters
is the opposite one — a stale product from a *different* build reporting green on a tree that is
actually broken — and nothing here would have distinguished it from a real pass.

`-derivedDataPath` verified present in the installed `man xcodebuild`, 2026-08-19.

### #494 — the completion fact is read at a path the chain itself just deleted

`dispatch-state.sh` (ADR-0139) exists because a non-teammate `Agent` dispatch returns before the
report arrives, so the controller cannot trust the transcript to say a batch finished; it reads a
file the agent wrote inside its own worktree instead. The SKILL.md text read that file **after**
running the coder's merge-back — whose own last step, on success, is `git worktree remove "$WT"`.

Measured in a scratch repo, git 2.50.1: a worktree whose only dirty content is gitignored (exactly
`.claude/dispatch/*.done`'s situation — `.gitignore:20`) is not "dirty" as far as `git worktree
remove` is concerned. It succeeds, rc 0, and deletes the entire tree, marker included:

```
-- status in worktree --
(nothing — .claude/ is ignored, not tracked-modified)
-- status ignored --
!! .claude/
-- remove attempt --
rc=0
-- ls wt after --
wt dir gone
-- ls done file after --
done file gone
```

`dispatch-state.sh`'s own contract resolves a missing directory to `NONE` before anything else
(`[ ! -d "$DIR" ]` → `NONE`, ahead of even the unsearchable-directory check) — correctly, for the
question it is actually asked. The question asked here was wrong: **on a healthy batch that completed
and merged cleanly, the completion-fact read reports `NONE`, and `NONE` is wired to `HALT`.** Rule 13
settles which of the two possible manifestations this is — a spurious halt on every healthy batch, not
a silent stale-read pass. The measurement is the finding; nothing here was assumed.

## Decision

### D1 — every generated `xcodebuild` candidate names its own build root

Both candidates in `detect-test-cmd.sh` gain `-derivedDataPath "$PWD/.build/DerivedData"`. `$PWD` is
`$ROOT` at detection time (the script already `cd`s into it), so the value written to
`.claude/test-cmd` is absolute and per-checkout from the moment it is generated — it does not depend
on the invoker's cwd matching `$ROOT` again when the command runs later, only on `$ROOT` itself not
moving.

### D2 — a trusted `xcodebuild` test-cmd without it refuses to dispatch

New pre-flight assertion, Step 5.0.4b, alongside ADR-0050's original four (now five, run once at
Step 5 entry): a `.claude/test-cmd` whose first non-comment line contains `xcodebuild` and does not
also contain `-derivedDataPath` fails closed, with the literal remediation naming
`approve-test-cmd.sh`. This is for the **existing-project** case D1 cannot reach — a `.claude/test-cmd`
approved before this ADR, never regenerated. One edit, once, and Step 5 does not start.

### D3 — the completion fact is read from the coder's worktree BEFORE that worktree's own merge-back

The resolution site splits into the order the plan called for: (a) `$WT`/`$WB` are already known at
this point, from the dispatch result (F10) or by enumeration (F19/F20) — nothing new to resolve; (b)
read the completion fact immediately, against that untouched worktree; (c) only on a `DONE` verdict
does the **Merge-back and base-fork audit** block (ADR-0068) run, ending in the same
`git worktree remove "$WT"` it always has.

Three sites carry the reordering, each independently readable rather than depending on the others to
be right:

- The coder-dispatch instruction (Step 5's numbered batch procedure, item 2): states the fact is read
  **BEFORE** the merge-back, and names why — the merge-back's own last step deletes the root.
- The completion-gate fence's lead-in prose: `$WT` is described as bound at dispatch/enumeration, not
  by the merge-back block, which "runs AFTER this fence."
- The post-fence branch: a `HALT` line explicitly forbids running the merge-back — the worktree is
  left exactly as it is, not merged, not removed — and only the `complete` line authorizes it.

No change to `dispatch-state.sh` itself (D-none): its `NONE`-for-missing-directory answer is correct
for the question; the question was being asked at the wrong point in the sequence, and that is what
moved.

### D4 — what is enforcement and what is not (rule 16)

D1/D2 are mechanical: a generated flag, a grep-and-refuse pre-flight. D3 is a sequencing instruction
in prose — the orchestrator is *told* to read before removing, the same class of enforcement ADR-0104
and ADR-0139's own completion-fact reads already are. Nothing here adds a mechanical guard preventing
the wrong order; none of `dispatch-state.sh`'s existing tokens can detect "was this the WT that just
got removed" versus "was this WT never populated" — both read as a missing directory.

## Consequences

- Two concurrent `xcodebuild` runs — a worktree's tester and a worktree's coder, or a worktree and the
  main checkout's controller-side verification — no longer share one build root, closing the false-red
  case observed and, more importantly, the false-green case that was never observed but was always
  possible.
- A pre-existing project's approved `.claude/test-cmd` is caught once, at Step 5 entry, rather than
  silently continuing to share a root forever.
- A healthy Step 5 batch no longer spuriously halts on `NONE` — closing #494 — because the fact is
  read while the worktree that holds it still exists.
- **Not addressed.** D3 has no mechanical guard against a future edit re-introducing the wrong order;
  it is three independently-worded prose statements, not one shared assertion, because the fact being
  guarded (WT still exists at read time) has no cheap runtime check available to `dispatch-state.sh`
  itself — it already answers correctly for the directory it is handed. A future editor who reorders
  these three sites back would not be caught by any of the assertions below; they pin the WORDING, not
  the sequencing enforced.

## Alternatives considered

**A1 — a fixed, machine-wide `DerivedData` path outside every checkout, keyed by checkout path
hash.** Rejected: it reintroduces exactly the shared-root problem one layer down, and it requires a
new piece of global state (the hash → path mapping) for no benefit over a path already scoped to
`$ROOT`.

**A2 — teach `dispatch-state.sh` to distinguish "never existed" from "existed and was removed."**
Rejected: it would need the helper to remember state across invocations — a second record of a fact
the filesystem itself is supposed to be the source of, which is the shape rule 6 forbids when the two
copies could disagree. The cheaper fix is to never ask the question after the answer has been erased.

**A3 — merge back the coder's worktree without removing it; remove separately, later.** Rejected: it
keeps a stale worktree on disk for every batch until some other cleanup step, which is a new leak for
a very old defect. Reading before removing is strictly smaller.

## Test and plant obligations

`worktree-isolation-contract.test.sh`, Section M (issue #488) and its extension for #494:

- **M1/M2** — Step 5.0.4b's assertion body checks specifically for `-derivedDataPath` inside
  `.claude/test-cmd`, and the gate names `xcodebuild` so it does not fire on every stack.
- **M3** — `detect-test-cmd.sh` writes `-derivedDataPath` on both the `.xcworkspace` and
  `.xcodeproj` candidates, counted on the `CMD=` lines only (the surrounding comment also names the
  flag in prose, which a bare count would over-count).
- **M4** — the coder-dispatch instruction states the completion fact is read `BEFORE running its own
  merge-back`.
- **M5** — the post-fence branch states a `HALT` explicitly forbids running the merge-back.
- **Z1** (assertion-count floor) bumped 98 → 101 → 103 as Section M grew, each bump re-derived rather
  than assumed (rule 10 — a floor absorbs its own plant, so the margin is recomputed at each addition,
  not incremented by feel).

All five new assertions are individually plant-verified `FIRED` against an isolated copy.

## References

- Issue #488, issue #494
- ADR-0068 — the worktree isolation contract; `isolation: worktree` bounds cwd, not the filesystem
- ADR-0139 — `dispatch-state.sh` and why the completion fact exists at all
- ADR-0104 — the Step 7.0 collapse and merge-back mechanics this ADR reorders around, not rewrites
- CLAUDE.md rule 6 (A2), rule 10 (Z1's re-derivation), rule 13 (the scratch-repo measurement), rule 16
  (D4), rule 17 (a producer — the coder's `.done` write — and a consumer — the completion-fact read —
  that nothing checked meet at the same moment the root still existed)
