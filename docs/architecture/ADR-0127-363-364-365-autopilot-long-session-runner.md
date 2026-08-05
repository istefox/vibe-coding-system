# ADR-0127 — `nightly-autopilot` becomes `autopilot`: a scoped, bounded, long-session runner

- **Status:** Accepted
- **Date:** 2026-08-05
- **Issues:** #363, #364, #365 — plus one defect found while reading the runner for this ADR and
  filed nowhere before it
- **Supersedes in part:** ADR-0022's *overnight* framing (§1, §3.2) and the file, directory and
  status-token names it established. Its safety invariants are untouched and restated here.
- **Files:** `staging/plugin/skills/autopilot/SKILL.md`,
  `staging/plugin/skills/project-conductor/SKILL.md`, `staging/plugin/skills/commit/SKILL.md`,
  `staging/plugin/skills/concept-to-code/SKILL.md` (Gate 4.0 only),
  `staging/plugin/scripts/autopilot-guard.sh`, `autopilot-disarm.sh`, `autopilot-migrate.sh`,
  `publish-feature.sh`, `staging/sync-to-claude.sh`, `docs/RUNBOOK-autopilot.md`

## Context

`nightly-autopilot` was designed against one shape of run: an overnight window. **That framing is
not a label, it is a load-bearing assumption** — a night is a fixed, self-limiting budget, so
ADR-0022 never had to decide how much a run should attempt or what stops it. A long working session
is open-ended. Both questions become mandatory the moment the same runner is used while the human
is at lunch rather than asleep.

The 2026-08-04 run was the first to reach `NIGHTLY-PUBLISH` (feature #292, PR #362). It delivered
**one** feature and measured four defects. This ADR takes three of them, because all three are
consequences of the same assumption, and adds a fourth that reading for this design surfaced.

## The measurement, which changed two of the four remedies

### Finding 1 — two of the three run-level halts have never been able to fire

`autopilot-guard.sh` (then `nightly-guard.sh`) reads three run-level halt files. Measured across
all of `staging/`:

| halt file | read by | cleared by | **written by** |
|---|---|---|---|
| `needs-human` | guard | disarm | `project-conductor` Steps 4, 5 — real |
| `build-status` | guard | disarm | `project-conductor` Step 5A — real |
| `rtf-blocker` | guard | disarm | **nothing** |
| `token-budget` | guard | disarm | **nothing** |

`nightly-autopilot/SKILL.md:404` asserted both missing producers by name — *"written by the review
step and this skill's `/goal` overlay"*. Neither exists. The `token-budget` branch parses `limit=`
and `spent=` and halts every publish when `spent >= limit`; it is **the only budget-enforcement
mechanism in the system**, and it has been unreachable since ADR-0022 shipped.

This is the producer/consumer class this repository has now recorded six times, the previous five
being issues #173, #248, #319, #238 and #295. It matters more here than in any of those: what
issue #365 asks for was two-thirds built, and nobody could tell, because a halt that never fires
looks exactly like a run that never needed halting.

### Finding 2 — the fork point cannot be `main`, and the reason is already in the ledger

Issue #364 frames the fork point as a choice between `main` (the conductor re-picks the finished
feature, because `PROJECT.md` is marked `[x]` on the feature branch) and the previous feature's tip
(every PR stacks). Both are real. **Neither is the whole constraint.**

Phase P writes `PROJECT.md`, `docs/specs/*.spec.md` and `_issue-map.tsv` into the working tree
before any branch exists, so they land in whichever feature branch commits first. A second feature
forked from `main` therefore finds **no SPEC of its own**. That is not hypothetical: it is `VCS-003`
in this repository's own task ledger, observed on 2026-08-04, where five Phase-P SPECs existed only
on `feat/the-value-domain-guard-covers-step5-mode`.

So "fork from `main`" is not merely wrong about roadmap state — it is unimplementable as stated.
This changed the remedy from a choice between the issue's two options to a third.

### Finding 3 — the rename cannot be uniform, by an invariant this repository already holds

340 occurrences of `nightly-autopilot`: **134 in `staging/`, 202 in `docs/`**. ADR-0034's precedent
— reaffirmed by ADR-0040, ADR-0076, ADR-0082 and ADR-0092 — is that historical ADRs and plans are
not edited in place; a correction is recorded forward. A global rename would rewrite 202 accurate
records of what the system was called when those decisions were taken.

## Decision

### D1 — The rename is full-depth inside `staging/`, and a hard cut

Every operator-facing and internal name moves together: skill directory, both hook scripts, the
opt-in marker, the state directory, the report, the two status tokens, the conductor's mode
argument and its `_nightly` variable, and the RUNBOOK. No compatibility shim and no dual-read.

A shim was rejected on this repository's own terms: a dual-read opt-in marker means two files can
disagree about whether a repo has opted into unattended `git push`, and the failure is silent in
the permissive direction. The cut is cheap here because the live surface is three artefacts and
`.claude/nightly-state/` is empty.

`docs/` is not edited (Finding 3). Each affected ADR gains a dated `## Correction` pointing here.

### D2 — Three ways a rename fails silently, three mechanisms

A rename is a refactor whose failures are all silent, which is the opposite of every other change
this system makes. Each is closed where it happens, not in prose:

1. **The guard goes inert — and measuring it found the failure is worse than "the file is gone".**
   `~/.claude/settings.json:201` wires `bash ~/.claude/hooks/nightly-guard.sh` by absolute path, and
   `settings.json` is deliberately outside `sync-to-claude.sh` (ADR-0025).

   The first draft of this ADR said the wired path would point at a file that no longer exists. It
   would not. **`sync-to-claude.sh` never deletes**: it copies `PAIRS` entries and nothing else, so
   after `--apply` the deployed tree holds *both* the stale `nightly-guard.sh` and the new
   `autopilot-guard.sh`, and `settings.json` still names the stale one. That hook keys off
   `.claude/nightly-state/active`, which the renamed runner never writes again — so it fires on
   every `git push`, finds no marker, and **exits 0 inert**. A missing file would at least error;
   this produces no signal whatsoever. A `PreToolUse` guardrail that stops guarding while still
   appearing wired is the worst shape available, and it is the shape the obvious reading misses.

   → `sync-to-claude.sh` **refuses to apply** while `settings.json` names the old hook, printing
   both the settings edit and the `rm` for the two stale deployed hooks — the deletion has to be
   named because sync structurally cannot perform it. The deploy tool is the only place that sees
   both halves.

2. **A stale `/goal` condition can never be satisfied.** The condition text is pasted by a human and
   names `NIGHTLY-PUBLISH`. Renamed, the evaluator waits for a line nothing prints and the loop
   burns its whole turn budget having published nothing — a failure that looks like slowness.
   → Phase 1 prints the template with the new token; the RUNBOOK names the old one once, as the
   symptom.

3. **Legacy local state is ignored rather than noticed.** A repo still carrying
   `.claude/nightly-autopilot.yml` silently stops opting in, and `publish-feature.sh` refuses for a
   reason that is true but not the cause.
   → The opt-in check and the guard **detect the legacy names and abort naming the migration**.
   They never fall back to them. `autopilot-migrate.sh` performs the one-time rename. A check that
   did not run must be distinguishable from a check that found nothing; this is the same rule
   applied to a check that read the wrong file.

### D3 — Branch identity: `commit` gains `--branch <name>` (#363)

`commit` Step 3.6 derives a branch name from the commit **subject**. Gate 4.0's commit is a
planning-artifacts commit, so its type is `docs`, so the name is `chore/<subject-slug>` — while
`publish-feature.sh`'s `BRANCH="feat/$SLUG"` line pushes a name from the topic slug. They never
coincide, and the one
successful run published only because a human created the branch first.

`--branch <name>` is orthogonal to `--autopilot` and `--no-pr` exactly as those two are to each
other. Absent, behaviour is byte-identical (#363 R-03).

**It ENSURES the branch, it does not merely name it — and this decision's own first draft got that
wrong.** The draft said Step 3.6 "uses it instead of deriving" and "still no-ops when a feature
branch is already checked out". The second clause is false under §D4: each feature forks from
`autopilot/prep-<date>`, which is feature-shaped and **not** the default branch, so a trigger
conditioned on "am I on the default branch" would no-op and commit the feature onto the shared prep
base. The trigger is therefore *not already on `<name>`*, with three outcomes — already there →
no-op, exists → check out, absent → create from the current HEAD. Found by writing the fixture for
the prep-branch case, not by re-reading the paragraph.

**An existing `<name>` is reused, never suffixed.** The derived path appends `-2`, `-3` … on
collision, which is right for an accidental slug clash and wrong here: `publish-feature.sh` expects
exactly `feat/<slug>`, so a suffixed branch is one nothing will ever push. A pre-existing `<name>`
is a resumed feature. `<name>` naming the default branch is refused outright — an argument must not
be able to override the invariant Step 3.6 exists to enforce.

**Chosen over "Gate 4.0 creates the branch itself" for a reason that is not style:**
`recovery-preflight.test.sh` **RH4b** forbids raw `git checkout -b` / `commit` / `add` inside the
Gate 4.0 block (ADR-0071 §D3, which exists because a second branch-and-commit path drifts from the
first). The flag satisfies #363 without superseding an Accepted decision.

The contract is stated at both sites (#363 R-02): Gate 4.0 says which name it passes and why;
`publish-feature.sh` says which name it expects and who produces it.

### D4 — Fork point: a run-scoped prep branch (#364)

Phase P's outputs are committed once on `autopilot/prep-<YYYY-MM-DD>`, pushed, and opened as their
own documentation-only PR. **Every feature branch forks from that ref; every feature PR targets
`main`.**

This is the only arrangement that satisfies both halves at once — independent, individually
reviewable feature PRs, *and* every feature's design inputs present in its own tree. Forking from
`main` is unimplementable (Finding 2); forking from the previous tip makes PR *N* contain features
1..*N*.

**What is done in a run is decided by the run's own ledger, not by `PROJECT.md`.** Each publish
appends its slug to `.claude/autopilot-state/published`; the conductor's next-feature pick skips
any slug listed there. So the conductor cannot re-pick a feature that published in the same run
(#364 R-02) without depending on committed checkbox state that lives on a branch it is not on.
`PROJECT.md` remains the durable roadmap and keeps being marked on feature branches.

`publish-feature.sh`'s `--base` is the **PR base**, not the fork point. The two were being
conflated; both are now named at that site.

**Who performs the fork had to be decided, and the first draft did not say.** Nothing downstream
chooses a base: `commit --branch` (§D3) creates from whatever `HEAD` is when Gate 4.0 runs, so the
fork point is decided in `project-conductor` Step 4 or it is decided by accident — and by accident
it is the previous feature's tip, which is the stacking this section exists to remove. The
mechanism is `project-conductor autopilot --fork-from <ref>`, checked out before the chain is
invoked. Writing `--fork-from` into the caller without a consumer would have been the
producer/consumer defect recorded six times in this repository, committed while fixing its cousin.

Both new fences distinguish **did not run** from **found nothing**: an unresolvable fork ref is
exit 3 rather than a silent fall back to `HEAD`, and an absent ledger (exit 0, nothing published
yet — the common legitimate case) is distinct from an unreadable one (exit 3). A dirty tree refuses
the base switch at exit 2 rather than dragging uncommitted work across branches.

Cost, recorded rather than discovered later: one extra PR per run, and every feature PR carries the
prep commit until prep is merged. The report records `base` per feature (#364 R-03).

### D5 — Scope: the runner takes arguments (#365 R-01)

`/skill autopilot [--features N] [--only <slug>[,<slug>]]`, with an optional `scope:` block in
`.claude/autopilot.yml` as the durable per-repo default. Arguments override the marker. The runner
resolves a concrete feature list **before** Phase 1 and drives exactly that list.

`PROJECT.md`'s `~12 features per wave` cap was prose with nothing able to honour it. It is now a
default the runner reads, and the cap moves out of §10's prose into the marker.

Editing checkbox state to fake a boundary stays forbidden: `PROJECT.md` is the roadmap's own record
and falsifying it to bound a run is the same class of error as rewriting a historical manifest.

### D6 — The bound: `token-budget` gets the producer it never had (#365 R-02)

`project-conductor` writes `.claude/autopilot-state/token-budget` after each feature. `limit=` comes
from `--budget` or the marker. `spent=` accumulates that feature's `step5-report.json`
`task_metrics` (ADR-0064).

**When a feature's metrics are absent it writes nothing and says so — never `0`.** A zero there
reads as "this feature spent nothing", which is ADR-0064 §D3's rule and the reason the metrics are
absent-not-zero in the morning report already. The guard's read is untouched; it simply becomes
reachable for the first time.

`rtf-blocker` is left without a producer **deliberately and is now documented as such**, rather than
being claimed to have one. Giving it a producer means deciding when a review blocker is run-level
rather than feature-level, which is ADR-0111's territory and needs its own issue. What changes today
is that the file's status is honest.

### D7 — The bound is checked between features, never mid-feature (#365 R-04)

A run that reaches its limit marks the next feature `[~]`, appends to `skipped-features`, and stops.
It must never write `needs-human`, which halts every subsequent publish — ADR-0111's contained-skip
versus run-level-halt split, preserved. Running out of budget is the most *expected* way for a
long session to end and must be the least alarming.

### D8 — The turn budget is corrected and thereafter recorded, not estimated (#365 R-03)

The RUNBOOK's `stop after 200 turns` was calibrated at ~15 orchestrator turns per feature, from
ADR-0022's 13-feature roadmap. Measured on the 2026-08-04 run: **~50 turns for one standard chain**.
A 110-turn budget delivered one feature.

The RUNBOOK is corrected to the measured figure **carrying its `n=1` caveat**, and the report
records actual per-feature turns so the next correction is a re-derivation rather than a second
estimate. Turns remain a poor proxy — they count orchestrator turns, so a 75-minute dispatch costs
one and six cheap bash checks cost six — which is why D6's token bound is the primary one and this
is the backstop.

## Known consequences

- **The guard is hand-wired and this rename moves it.** Until the `settings.json` line is edited,
  `sync-to-claude.sh` refuses to apply — chosen so the failure is a blocked deploy rather than a
  disarmed guardrail. This joins the five hooks CLAUDE.md already tracks as wired by hand.
- **`docs/` keeps saying `nightly`** — 202 occurrences, correct for their moment. Any future derived
  guard counting the retired tokens must scope itself to `staging/` or it will report 202 findings
  for ever.
- **Only two ADRs carry a `## Correction`, not every one that mentions the old names.** Measured:
  ADR-0022 (50 mentions) and ADR-0023 (11) *define* the capability; **32 further ADRs mention it
  incidentally, 1–5 times each**. Thirty-four near-identical notes would bury the two that say
  something. The narrowing is recorded here rather than left to look like an oversight; an
  incidental mention in a historical record needs no annotation to stay true.
- **One extra PR per run** (D4), and feature PRs carry the prep commit until prep merges.
- **`--features N` is a count over pending features, not a wave identity.** A roadmap reordered
  between runs changes what `N` selects. `--only` exists for the case where that matters.
- **`spent=` measures what `task_metrics` measures**, which is per-task implementation cost, not the
  orchestrator's own consumption. It undercounts a run whose cost is in gates rather than dispatches.
  Stated here because a budget that silently undercounts is worse than none.
- **This ships instructions as well as mechanisms.** D4's ledger, D5's resolution and D6's producer
  are steps in `SKILL.md` files a model is asked to follow; the harness pins that they exist, nothing
  pins that they are obeyed. Same standing limitation as ADR-0047 and ADR-0048.
- **#366 is not addressed here.** Its R-02 asks whether all 138 fences must be shell-portable or
  constrained to `bash`, which governs every skill rather than this runner. Separate chain.
