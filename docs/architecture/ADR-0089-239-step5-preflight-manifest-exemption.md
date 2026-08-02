# ADR-0089 — Step 5.0.1 asserts a clean tree on the one file the chain must keep writing

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #239 (found by the Phase 7.1 shakedown run, at Step 5 entry on #222)
- **Related:** ADR-0050 (the pre-flight this amends — §D2's purpose survives, §D3 is untouched),
  ADR-0071 (Gate 4.0, the producer that made this reachable), ADR-0083 (the fence-contract rule
  applied here), ADR-0075 (hand-edited manifests, measured as real), ADR-0068 §D11 (the merge-back
  escape check, which shares this fix's `*.bak` premise), ADR-0043 (a check that did not run must
  not read as a check that found nothing)

## Context

ADR-0050 put four assertions at the top of Step 5. The first is that the working tree is clean, and
its stated purpose is that nothing of **unknown provenance** is in the tree when the first agent is
dispatched (§D2).

The Phase 7.1 shakedown was the first chain run ever to get past Gate 4.0 — #173/ADR-0071 had to
ship a producer before anything could, and #234 had to give that producer a way to stage untracked
artifacts. It reached Step 5.0.1 with a clean tree, a successful Gate 4.0 behind it at commit
`a7ebbc0`, and was refused.

The refusal was correct on its own terms and its message was false:

```
 M docs/manifests/2026-07-30-222-vendor-deployed-only-skills.manifest.yml
```

with a diff containing exactly `autopilot: false → true` and `current_step:
step_4_session_boundary → ready_for_implementation`. The manifest is a chain artifact, so it landed
in the first remediation branch — the one that prints *"the chain's own planning artifacts are
uncommitted. Gate 4.0 should have committed them."* Gate 4.0 had run, succeeded, and left a clean
tree. The two lines after it undid the state it exists to create.

### There is no ordering that fixes this

- **"Implement now"** runs `manifest-set-flag.sh <m> autopilot true`, then
  `manifest-transition.sh <m> ready_for_implementation`, then enters Step 5. Reordering Gate 4.0 to
  run after both would fix this branch.
- **"Confirmed — I will /clear and resume"** does not yield to reordering at all. Form B resume,
  step 3, updates `session_boundary.resumed_at` and `last_updated_at` unconditionally, in the fresh
  session, after any commit the old session could possibly have made, immediately before branching
  to Step 5. The manifest is dirty by construction on this path, every time.

And three assertions later, **5.0.3 writes `recovery_baseline_sha` into the same file on purpose**.
So even a hypothetically clean entry is dirty again inside the same pre-flight.

The shape of the thing: **"the working tree is clean" and "the manifest is written at every state
change" are flatly incompatible requirements on the same file.** The pre-flight asserts one; the
state machine implements the other. Neither is wrong on its own, which is why this survived design
review on both sides.

### Why it was invisible for as long as it was

Every earlier run stopped before this line, on a different cause, with a different message. And
`concept-to-code/SKILL.md` had no harness that executed this fence — because there was no fence.
5.0.1's classification was **prose**: *"decide by intersecting `git status --porcelain` with the
chain's own artifacts — `SPEC.md`, `manifest.artifacts.adr`, `manifest.artifacts.plan`, the manifest
itself, `CLAUDE.md`"*. Prose cannot be run, so it was not one of ADR-0083's declared contracts and
nothing checked it. This is rule 11 with the causality made explicit: the block was not merely
unexecuted, it was **unexecutable**, and that is what kept it out of the population ADR-0083 built a
guard for.

## Decision

### D1 — The manifest leaves the dirty set, and only the manifest

`git status --porcelain` is filtered for the manifest path before anything is classified.
`SPEC.md`, `manifest.artifacts.adr`, `manifest.artifacts.plan` and `CLAUDE.md` stay in, so the
check this assertion exists for is unchanged. ADR-0050 §D2's purpose survives intact: it refuses on
work of unknown provenance, and the manifest's provenance is the most known thing in the
repository, since the chain is its only writer.

Two alternatives were considered and rejected:

- **Commit the manifest as part of entering Step 5** (a second `commit --no-pr` after 5.0.3). A
  cleaner invariant on paper, one more commit per run, and it must not run before 5.0.3 or the
  problem reappears one line down. It also creates a new invariant to maintain, which D1 does not.
- **Take the manifest out of the working tree** (a gitignored state directory). Largest blast
  radius, touches every helper and every consumer, and loses the manifest from the PR — a real
  loss, since it is the audit record.

### D2 — The exemption is bounded by a validity check, not by trust

Excluding a file from the dirty set would otherwise let a hand-edited manifest through, and
ADR-0075 measured hand-edits as real rather than hypothetical (*"a quoted boolean in a
machine-generated manifest is a hand-edit"*). Step 5 therefore runs
`manifest-validate.sh` on both Gate 4 branches — Form B resume already did this at its step 1; the
in-session branch never did.

**What is exempt is the manifest's *dirtiness*, never its *content*.** Stated that way in the skill
because the exemption reads, at a glance, exactly like a weakened check.

### D3 — The classification becomes an executable, declared fence

`<!-- fence-contract: c2c-step5-preflight-dirty-classify -->`, with a token on stdout per branch
(`PREFLIGHT_CLEAN` / `_CHAIN` / `_OTHER` / `_BOTH`) and the remediation prose keyed to the token.
The existing three remediation branches are preserved verbatim, including ADR-0071 §D3's
never-advise-stash rule and its commit-then-stash ordering for the mixed case.

**Exit 3 means the check did not run** (`PREFLIGHT_NOREPO`, `PREFLIGHT_NOMANIFEST`), distinct from
exit 0. Same distinction `spec-coverage.sh`, `plan-tasks.sh` and `secret-scan.sh` already make, and
for the same reason: without it, an unrunnable classifier is indistinguishable from a clean tree,
which is #239 reproduced one level down.

Converting prose to a fence is not incidental to the fix — it is what makes the fix testable at
all, and it moves this block into the population ADR-0083's F3/F4 already guard. The corpus went
from 13 abort-capable fences to 14 and from 12 declared contracts to 13, all executed.

## What running it found, that reading it would not have

**The first draft was broken, and it failed in the direction that looks like success.**
`git rev-parse --show-toplevel` returns a **physical** path; the manifest path the chain carries is
whatever `$PWD` was at Gate 0. A raw prefix match therefore shortened nothing, every artifact
classified as `OTHER` — **including the manifest**, which made the exemption silently inert while
the fence still exited non-zero and still looked like it was doing its job. Eleven fixtures caught
it on the first execution; no amount of reading would have.

This is live on macOS rather than theoretical: `/tmp` is a symlink to `/private/tmp`, and this
machine reaches the same checkout through `/Users/<u>/Developer` and `/Users/<u>/developer` on a
case-insensitive filesystem. The fix resolves the argument (`cd "$(dirname …)" && pwd -P`), the
same normalisation the stop-gate TOFU probe already uses.

**Half of that normalisation is defence, not a tested property, and the fence says so.** Reverting
`ROOT` to the unresolved value fires **no assertion**, because git already returns a physical path
and no failing case could be constructed. Reverting the argument side fires five. Both halves are
in the code; only one is evidenced, and conflating them would be the kind of claim this repository
keeps catching.

**`*.bak` is gitignored, and that fact is load-bearing for two checks.** 5.0.3 writes the baseline
with `sed -i.bak`. If `*.bak` were not ignored, the debris would dirty the tree at this very
assertion **and** trip ADR-0068 §D11's merge-back escape check
(`git ls-files --others --exclude-standard`) on every stage of every Step 5. Verified against
`.gitignore` rather than assumed, and recorded in the skill so a future `.gitignore` edit does not
break two unrelated checks in silence.

## Consequences

- **A pre-flight assertion now passes on strictly more inputs.** Bounded to one file, with the
  validator covering that file's content, but it is a guard being relaxed and should be read as one.
- **The remediation branches were unreachable prose and now are not.** `PREFLIGHT_BOTH` in
  particular carries ADR-0071 §D3's ordering advice, which no run could previously reach.
- **The fence reads porcelain v1.** A **renamed** chain artifact arrives as `old -> new` and
  classifies as `OTHER`; a path containing a space or a quote is quoted by git and will not match.
  Neither shape occurs for the four artifacts classified here. Stated in the skill rather than left
  to be discovered.
- **`manifest-validate.sh` is now a hard dependency of the in-session Gate 4 branch.** An un-synced
  machine fails it closed, consistent with ADR-0076's rule that a gate's missing dependency fails
  closed rather than degrading.
- **This does not fix #248.** Step 5 can now be entered; leaving it for Step 6 is a separate
  missing producer, in the same stretch of the chain and the same class.
- **Inert until sync.** Both changed files are `staging/`-side.

## Verification

Sixty-seven assertions in `recovery-preflight.test.sh`, thirteen of them new (`RJ0`–`RJ12`), plus a
`Z1` assertion-count floor the file did not have.

**`RJ1` is the red evidence and it is derived, not hand-written.** The pre-#239 rule is
reconstructed from the shipped fence by `sed` — dropping the exclusion, putting the manifest back
in the chain-artifact set — so it cannot drift into testing some other script. On the
manifest-only fixture it must still produce the false `PREFLIGHT_CHAIN`.

Nine defects planted, each reverted from a checksummed backup:

| plant | fires |
|---|---|
| P1 fence marker deleted | RJ0 and every RJ that depends on the extraction |
| P2 exclusion line removed | RJ2, RJ9 |
| P3 full pre-fix state restored | RJ2, RJ9 |
| P4b `rel()` argument not resolved | RJ1, RJ2, RJ3, RJ5, RJ9 |
| P5 validator call removed | RJ10 |
| P6 exemption reason removed | RJ11 |
| P7 `*.bak` fact removed | RJ12 |
| P8 no-repo case exits 0 | RJ7 |
| P9 all chain artifacts exempted | RJ1, RJ3, RJ5 |

**P3-as-first-designed did not fire, and that was correct rather than a gap:** with the exclusion
upstream, putting the manifest back in the `case` is dead code. The plant was rewritten as the full
pre-fix state.

**P4 did not fire either, and that is what produced the honesty note in D3's discussion above** —
it planted the wrong half of the normalisation. Recorded rather than quietly re-planted, because a
plant that does not fire is evidence about the assertion, not a formality to get past.

Full harness 53/53. `fence-contract-coverage.test.sh` F3/F4/F6/F7 confirm the new contract is
declared, unique, parseable and executed.

## Correction 2026-08-02 (issue #344) — `pwd -P` closed the symlink half only

The body above is left unedited (ADR-0034 precedent). This records what was wrong with the fix it
describes, and what replaced it.

§D's `rel()` normalised both sides with `cd … && pwd -P` and compared string prefixes. **`pwd -P`
resolves symlinks; it does not normalise case.** On a case-insensitive, case-preserving filesystem
— APFS, which is where this chain runs — `cd /Users/x/developer/…` succeeds and reports the casing
the caller traversed, while `git rev-parse --show-toplevel` reports the casing git recorded. The
prefix match failed, `rel()` fell through to its absolute-path branch, and the manifest exemption
was **inert on every run from a differently-cased CWD**.

The failure shape is this ADR's own defect one level down. The fence did not crash and did not
report a check that had not run: it returned a confident, well-formed
`PREFLIGHT_OTHER docs/manifests/<manifest>` — **naming the one file it exists to exempt** — with the
`PREFLIGHT_OTHER` remediation attached, which advises `git stash push -u`. Following that advice
would stash the chain's own manifest. Found by running the 2026-08-02 nightly on feature #287, not
by reading the fence.

The comment this ADR shipped names the hazard by name (*"a checkout is reachable through
differently-cased paths on APFS"*) and `RJ9` pins only the symlink case. **A hazard named in a
comment and covered by no assertion is a hazard nobody is checking** — the same gap, in the same
paragraph, as the claim it makes.

`rel()` now takes the repo-relative path from `git -C "$_d" rev-parse --show-prefix`, so the
comparison is removed rather than corrected and there is no third normalisation left to miss. A
`-ef` device+inode guard keeps an artifact living in a different checkout from being handed that
checkout's prefix — identity, deliberately not a string compare, since a string compare here is how
this would return through the side door. `RJ13` (behavioural, case-insensitive filesystems only),
`RJ13b` (source-level, always runnable — ADR-0026's precedent for a platform-specific precondition)
and `RJ14` (foreign repo) pin the three properties; `RJ9` still pins the symlink half and still
passes, which is what shows the new mechanism did not trade one half for the other.

**`ROOT` is gone from the fence.** The body above describes it as belt-and-braces defence with no
constructible failing case; it is now unused, so it is removed rather than left as a variable a
reader would assume is load-bearing.
