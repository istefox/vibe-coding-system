# Project: vibe-coding-system

## Overview
Auto-generated roadmap from issues labeled `prep` (ADR-0023).

## Where this stands (2026-07-30, evening)

**Phases 1–7 are closed.** Phase 5 is superseded by Phase 6 and kept for its reasoning only.

**The shakedown ran, and it is the reason this file now has a Phase 8.** The
`concept-to-code` chain executed end to end on issue #222 — Step 1 through Step 7, seven worktree
dispatches, a full `review-triage-fix` cycle. It is **the first run in this system's history that
ever reached Step 5**; every earlier run stopped at an earlier gate, each time on a different
cause. #222 shipped in PR #251 with `sync-to-claude.sh --apply` run and a second dry run at zero
drift.

**It produced twenty-one findings. Three were fixed because they blocked; seventeen became Phase
8.** The count matters more than any single defect: everything from Phase 4 onward was preventive
work verified against planted defects, which proves a guard fires and proves nothing about the chain
it guards. One real run found more than four phases of inspection.

**Status as of 2026-07-31:** three of the seventeen have shipped, #234 (PR #255), #245 (PR #254)
and #239 (PR #257), and **#258 was added** by a class sweep run off #239's evidence rather than by
the chain, so **fifteen remain open**. The ordered plan is §8.7, regenerated after Wave A1.

**Two patterns account for most of them, each seen three or four times:**

1. *Consumer and producer specified in different places, with nothing checking the producer
   exists.* #173, #238, #248 — a pre-flight asserting a state nothing produced, a helper with no
   call site, a legal transition whose only producer sits behind a default-off flag.
2. *A form close enough to be partially read is worse than one rejected outright.* #171, #230,
   #235, #246. Rejection is visible; a partial read is a wrong answer delivered with a right
   answer's confidence.

**One standing rule, earned by this file three times.** A checkbox is ticked in the **same PR that
closes its item**, never in a later docs pass. On 2026-07-30 this file reported six open items when
two remained: 6.3's box was left unticked by the PR that recorded its outcome two lines below,
Phase 5's boxes still read as live after Phase 6 declared it superseded, and 6.5 named four call
sites when there were six. Every one of those was a roadmap that disagreed with GitHub, and nothing
made them agree.

## Phases

### Phase 1 — prep
- [x] Vendor deployed-only skills and hooks into staging  (issue #28)  (completed: 2026-07-11)
- [x] Refresh stale staging copies from the deployed tree  (issue #29)  (completed: 2026-07-11)
- [x] clean-public-repo: keep private history out of the public branch  (issue #30)  (completed: 2026-07-11)
- [x] concept-to-code: BSD-safe slug stamp and autopilot gate fixes  (issue #31)  (completed: 2026-07-11)
- [x] Manifest helpers: count guards, exit codes, YAML escaping  (issue #32)  (completed: 2026-07-11)
- [x] hook-verify-workflow: filter the audit window by session  (issue #33)  (completed: 2026-07-11)
- [x] Scope guards: autopilot CWD check, conductor glob, nightly check 6  (issue #34)  (completed: 2026-07-11)
- [x] refactor-snapshot filter append and deep-refactor scope glob  (issue #35)  (completed: 2026-07-11)
- [x] claude-md-slim: whole-line content union check  (issue #36)  (completed: 2026-07-11)
- [x] vibe-status: recursion guard and active-chains wiring  (issue #37)  (completed: 2026-07-11)
- [x] Hook hardening: enum value, lock ownership, trust hash  (issue #38)  (completed: 2026-07-11)
- [x] Skill text corrections across five standalone skills  (issue #39)  (completed: 2026-07-11)
- [x] Agent tool scoping per blueprint section 3  (issue #40)  (completed: 2026-07-11)

### Phase 2 — agentic-spec integration (report: docs/books/INTEGRATION-REPORT-agentic-spec.md)
- [x] Secrets and dependency gate: content scan, lockfile check, CI steps  (issue #100)  (completed: 2026-07-26)
- [x] Wire the anti-test-weakening detector into every unattended path  (issue #101)  (completed: 2026-07-26)
- [x] Requirement IDs in SPEC and a coverage check  (issue #102)  (completed: 2026-07-26)
- [x] Generator/verifier separation: dispatch the tester, deny coder test writes  (issue #103)  (completed: 2026-07-26)
- [x] Recovery-readiness pre-flight for concept-to-code Step 5  (issue #104)  (completed: 2026-07-26)
- [x] Reward-hacking detectors: literal assertions, deleted symbols, swallowed errors  (issue #105)  (completed: 2026-07-26)
- [x] Per-task diff budget and scope check  (issue #106)  (completed: 2026-07-26)
- [x] Interface immutability gate  (issue #107)  (completed: 2026-07-26)
- [x] Run the deterministic checks in the target project CI  (issue #108)  (completed: 2026-07-26)
- [x] Proportional audit depth: risk and task_type axes  (issue #109)  (completed: 2026-07-26)
- [x] SAST job and a security-audit skill  (issue #110)  (completed: 2026-07-26)
- [x] Tracer-bullet probe step  (issue #111)  (completed: 2026-07-26)
- [x] Context-occupancy instrumentation and PreCompact guard  (issue #112)  (completed: 2026-07-26)
- [x] Untrusted-input hardening for issue-driven design  (issue #113)  (completed: 2026-07-26)
- [x] External-dependency feasibility gate  (issue #114)  (completed: 2026-07-26)
- [x] Human-gate coverage: test diff and direction check  (issue #115)  (completed: 2026-07-26)
- [x] Litter and debris discipline across agents  (issue #116)  (completed: 2026-07-26)
- [x] Canonical-mechanism conformance  (issue #117)  (completed: 2026-07-26)
- [x] Agent-level instrumentation metrics  (issue #118)  (completed: 2026-07-26)
- [x] Licence and provenance scanning  (issue #119)  (completed: 2026-07-26)
- [x] Accessibility and i18n gates  (issue #120)  (completed: 2026-07-26)

### Phase 3 — publish, deploy, reconcile (Phase 2 was coded, not shipped)
Phase 2 items above mean "implemented on a branch," not "merged, deployed, or closed."
Audited 2026-07-27: 21 stacked PRs open (#124→#145, `main ← 100 ← 101 ← ... ← 120`), only the
bottom PR had CI (workflows trigger on `pull_request: branches: [main]` only); none of the 21
features exist yet in the deployed `~/.claude` tree; issues #100-120 still open (PR bodies carry
no closing keyword); stray non-canonical branches/worktrees from parallel agent runs litter the
repo. This phase is operational (merge/deploy/cleanup), not a new concept-to-code chain per item —
project-conductor's per-item SPEC→ADR→plan→impl cycle does not apply here.

- [x] Merge train: PR #124→#145 bottom-up  (completed: 2026-07-27). Correction found live: this
  repo does NOT auto-retarget a stacked PR after its base branch is deleted — it auto-CLOSES the
  next PR instead, and a closed PR with a deleted base cannot be reopened or re-edited. Fixed by
  recreating each PR fresh against `main` (the feature branch itself survives; only the PR wrapper
  was lost). Circuit breaker fired once for real: PR #147 (#102) had a genuine pre-existing
  `markdownlint` MD010 hard-tab violation in ADR-0048 that had never run CI before (stacked PRs
  never got CI until this train gave each one a real `main` base) — fixed with `<TAB>` placeholders
  matching ADR-0046/0047's own convention, then the train resumed.
- [x] Close issues #100-120  (completed: 2026-07-27). Done inline by the merge-train script per PR.
- [x] Deploy: `staging/sync-to-claude.sh --apply`  (completed: 2026-07-27). 27 changed + 16 new
  files. Two hooks needed the documented manual `settings.json` wiring (`test-write-scope.sh` on
  `PreToolUse Edit|Write|MultiEdit`, `precompact-guard.sh` on the new `PreCompact` key) — added by
  hand per the sync script's own "MANUAL STEP" output.
- [x] Debris: reported and removed  (completed: 2026-07-27). All 10 non-canonical
  branches/worktrees (`local-102-work`, `my-101-work`, 8 `worktree-agent-*`) verified at
  zero unique commits vs `main` before removal — explicit human confirmation obtained first.
- [x] Final verification  (completed: 2026-07-27). 43/43 shell-test files green on `main`;
  docs-ci registry parity confirmed 43/43 (glob vs the explicit `shell-tests` job list).
- [x] Unplanned: fixed a live Stop-hook infinite loop  (completed: 2026-07-27, PR #166). The #112
  rewrite of `usage-daily-hint.sh` never checked `stop_hook_active`, so its own
  `additionalContext` triggered a Stop re-invocation that re-emitted the same context forever —
  hit live in production immediately after this deploy, 9 consecutive re-invocations before Claude
  Code's own hard cap forced the turn to end. Fixed in both the deployed copy and this staging
  source so a future sync does not reintroduce it.

### Phase 4 — the class behind the fix (issues #193–#197, derived from ADR-0074/ADR-0075)

Group C closed #127 and #123, and both turned out to be **instances of a rule nobody enforces**.
Three of these five issues are that rule; two are concrete gaps the same audit disclosed. None is
urgent — nothing here is failing today — which is exactly the condition under which this class of
work gets skipped and then rediscovered as a live incident, twice, as #127 and #123 both were.

**Sequencing rationale.** The order below is driven by one hard constraint and two soft ones.
The hard one: **#194 needs elapsed time**, so its instrumentation goes first to start the clock.
The soft ones: #195's helper should absorb the duplication #123 created *while both copies are
still understood by the same reader*, and #197 is a consumer of the boundary rule #195 defines.

#### 4.1 — Start the clock, consolidate what is fresh

- [x] **#194 phase 1 — instrument only, decide nothing.** Make the audit log distinguish a
  main-session-fallback allow from a subagent-transcript allow. No behaviour change, no risk, and
  it converts "how often does transcript lookup fail" from an argument into a number. Today the
  log cannot answer it retrospectively, which is why the fallback has survived unexamined since it
  was written. Build-stamp the result: ADR-0016's v2.1.154 experience is the standing evidence
  that the transcript layout moves underneath us.
- [x] **#195 — the additive-field rule, and the helper if that is the chosen shape.** #123 wrote
  the same five-state logic twice in one pass, in two skills, with **opposite and both-correct**
  defaults for absence. That asymmetry is load-bearing and a helper must preserve it rather than
  flatten it — which is the argument for building it now, while one reader still holds both
  halves, and against building it in six months from the source.

#### 4.2 — The class guards

- [x] **#193 — derived guard for the self-arming marker pattern.** The highest-value item here:
  it prevents recurrence of the only bug in this group that actually deadlocked a chain. Model it
  on `skill-text-corrections.test.sh` F6 — derive the population at run time, count-guard the
  derivation, and put exemptions in the hook source rather than in a filename list.
  **Ask which direction the guard runs in before writing it** (rule 5): it must fail on a file the
  list omits, not merely validate the files it names. That was #127's own failure mode.
- [x] **#197 — apply #195's boundary rule to `manifest-validate.sh` invariant 4.** Ordered after
  #195 on purpose: on its own it is five files and a judgement call, but with the boundary rule
  already stated it becomes one conditional and a test. The five files stay byte-unchanged.

#### 4.3 — Decide on evidence, and the cheap one

- [x] **#194 phase 2 — read the measurement, then decide** (2026-07-29, PR pending, ADR-0080) keep / drop / accept, and record the
  decision in `pre-flight-pattern-enforce.sh`'s own header. Two hooks currently explain each
  other's opposite choices about the same fallback, and only one of them has ever been examined
  on its own terms.
- [x] **#196 — the interpreter enumeration** (2026-07-29, PR #203, ADR-0079). Landed larger
  than scoped: the enumeration turned out to be bounded by the permission layer, and the real
  defect was `R2_GIT`'s trailing boundary — the sibling of the one #127 fixed, unpropagated. Smallest, and mostly a decision with its failure
  direction stated. Option 1 (pin the limit in test section E) changes no behaviour and is the
  low-risk default; option 2 (invert to a tool exclusion list) fails toward denying, which is
  safer for a guardrail and more disruptive for a chain. `agent-command-scope.sh` took a live
  behaviour change in #127 — spacing a second one behind everything else is deliberate.

#### Risks

- **#193 and #195 both ship a derived, class-level check**, and both can pass vacuously if the
  derivation matches nothing. Same failure shape, same mitigation (count guard), and they must not
  land in the same PR — a vacuous pass in one would be masked by a real pass in the other.
- **#196 and #194 both alter a live guardrail on an unattended path.** Neither is failing today;
  both have a fail-direction choice that deserves its own gate rather than a batch approval.
- **The whole phase is preventive**, so nothing in it produces a visible improvement. That is the
  same condition that kept the ADR-0043 `PAIRS` gap invisible for months: the work whose success
  looks identical to never having done it.

#### Phase 4 status (2026-07-29)

Four of five shipped: #194 phase 1 (PR #199), #195 (PR #200, ADR-0076), #193 (PR #201, ADR-0077),
plus #197 (PR #202, ADR-0078) and #196 (PR #203, ADR-0079).

**#194 phase 2 closed 2026-07-29 (ADR-0080).** A controlled coder dispatch settled the mechanism
question in one probe: all three writes logged `src=subagent`, including the first, and the
transcript file predated the first hook decision by four seconds. The flush-race hypothesis is dead
and the fallback stays, on a stated n=3 with a pre-registered condition for dropping it. The
paragraph below is kept as the record of why the phase was sequenced this way.

**Why it was blocked, as written before the probe:** The `src=` instrumentation deployed at ~20:15 CEST
and the audit log carries **zero** coder-path rows since — no `coder` subagent has run. The
hard constraint named at the top of this phase was that #194 needs elapsed time; that is what is
now being waited on, not a missing decision. Reporting a keep/drop/accept verdict on an empty
sample is the failure mode this whole phase exists to guard against.

Two ways forward, neither started:
- **Organic:** any `concept-to-code` Step 5 run dispatches coders and produces rows.
- **Controlled probe:** dispatch a coder deliberately and read the `src=` SEQUENCE across its
  writes. This tests a specific hypothesis rather than sampling a rate — if the subagent transcript
  file is not yet flushed when the first `PreToolUse` fires, the fallback would fire on nearly every
  coder's FIRST write, which one dispatch would show. Requires human authorisation to dispatch.

### Phase 5 — make the shakedown run survivable (issues #206–#208)

> **Superseded by Phase 6**, which was written after #210–#213 existed and after the seven issues
> were read against each other. The items below are kept for their reasoning; their checkboxes are
> marked done where Phase 6 closed them, so a reader grepping `- [ ]` sees the work that is actually
> outstanding. Corrected 2026-07-30, having read as six open items when two remained.

Phase 4 emptied the backlog, so this phase comes from an **audit of the skill and agent layer**, the
surface the previous phases did not touch. Its purpose is narrower than "find defects": the next
step after it is a **shakedown run of the chain on a real feature**, and this phase exists so that
run tests the chain rather than testing today's edits.

That framing is what orders it. Four live guardrails changed on 2026-07-29 — `agent-command-scope`
twice, `manifest-validate`, `pre-flight-pattern-enforce` — and two pre-flight gates gained a
dependency that **fails closed**. The first real run is where all of that lands.

#### What the audit found clean, so nobody re-checks it

Stated because a negative result nobody records gets re-derived:

- **No missing script path.** Every `~/.claude/…`, `$HOME/…` and `$CLAUDE_PLUGIN_ROOT/…` reference
  in every `SKILL.md` resolves. The one apparent miss — `hook-verify-workflow.sh` under the skill —
  is ADR-0024's deliberate flat-vendoring remap, present in `PAIRS`.
- **Every skill script has a `PAIRS` entry**, 40 examined with a count guard. ADR-0043's blind spot
  is not currently costing anything.
- **The `grep -c … || echo 0` idiom appears nowhere as a use.** All ten hits are *warnings against
  it*, in ten different files. The #174 lesson propagated further than the fix did.
- **No unguarded leading-dash grep pattern** survives.
- **The agent layer is consistent.** Frontmatter carries `model` and `effort` on all eight, no agent
  claims a tool in prose that its frontmatter withholds. The single sweep hit — `researcher`
  "mentions Write" — is the sentence "Write the brief." ADR-0036/0042's work holds.

#### 5.1 — Before anything else

- [x] **#206 — nine abort-capable fences that nothing executes.** DONE (ADR-0083, PR #219), and it found #218. 138 bash fences in the skill
  layer, 15 can stop a run, ~6 are covered. **Five of the nine uncovered are in `autopilot-build`**,
  the unattended path. This is the one that decides whether the shakedown run fails on the chain or
  on an unrun pre-flight check, so it goes first and `autopilot-build` goes first within it.
  The deeper half — nothing marks which fences are contracts and which are illustrations — is worth
  solving here rather than counting by hand again.

#### 5.2 — Cheap, and it removes a live wrong pointer

- [x] **#207 — a stale line-number cross-reference, and the unchecked class.** *(closed in 6.2, ADR-0082)*
  `concept-to-code/SKILL.md:129` points at `SKILL.md:1355-1358` "for the exact transition block";
  those lines now hold the weakening-scan `CLEAN` warning. It does not point at nothing — it points
  at *other plausible technical prose*, which is worse. The named-heading instrument already exists
  (ADR-0018 addendum, `workflow-dispatch-pins.test.sh`) and was applied to one file.

#### 5.3 — Preventive, and therefore the one at risk of being skipped

- [x] **#208 — the three derived class guards each stop at a boundary nobody checks.** *(closed in 6.4, ADR-0085)* One question
  asked three times: what is outside this derivation, and would we notice? The sharpest of the three
  is that `transcript-scan-rule`'s count guard can be satisfied by a different population than the
  one at risk — a guard that appears to cover something it does not.

#### Then, and only then

- [x] **Shakedown run.** *(carried to 6.5, still outstanding — tracked there, not here.)* A small, real, low-stakes feature, chosen as much to exercise 2026-07-29's
  changes as to build the thing. Expect three things and do not mistake them for regressions:
  `diff-budget-check.sh` is active for the first time since July and may report `BUDGET`/`SCOPE` on
  work in flight against budgets written when nothing read them; the two new `manifest-field-state.sh`
  dependencies abort the pre-flight on an un-synced machine; and Step 5's Workflow dispatch is what
  finally produces the **Workflow-path** data ADR-0080's pre-registered condition is waiting on.

#### Risks

- **#206 is the largest item and the one most likely to grow.** Nine fences, each needing a fixture
  and a substitution contract, on top of a classification decision. If it has to be split, split by
  skill and do `autopilot-build` alone first — it carries the whole unattended-path argument.
- **The extraction anchors are headings**, and a heading rewrite turns extraction into a *skipped
  section* rather than a failure. `plan-task-count.test.sh` already carries that hazard; anything
  #206 adds inherits it. A skipped extraction must fail.
- **This phase is preventive in the same way phase 4 was**, and carries the same property: nothing
  in it produces a visible improvement. The difference is that this one has a deadline — the
  shakedown run — and an unrun pre-flight check is exactly what that run would trip over.

### Phase 6 — fix the seven open issues (#206, #207, #208, #210, #211, #212, #213)

Supersedes the Phase 5 sketch, which was written before #210–#213 existed and before the seven were
read against each other. Reading them together changes the plan in three ways that no single issue
could state.

#### Three cross-issue facts that drive the order

**1. #210 is not a separate fix from #207 — it is the same fix on a second surface.** #210 says so
in its own body: #207's scope, as written, covers references *inside* `SKILL.md` files, and #210's
two verified-stale references live in a **hook source's header**. Building #207's derived check first
and #210's second means either building the instrument twice or building it wrong once. They are one
work item that closes two issues.

**2. #206, #211 and two thirds of #208 want the SAME instrument, not similar ones.** Each asks for:
derive a population at run time, let a file **declare its own waiver** rather than keeping a list in
the test, and count-guard the derivation. #206 derives fences and asks which are contracts; #211
derives skills and asks which are deliberately uncovered; #208 (1) needs a count guard that is
per-population instead of global; #208 (3) needs the agent list derived from the hook's own `case`
arm. That is one pattern, four applications.

The repository has already built it three times — `skill-text-corrections` F6, `transcript-scan-rule`,
`agent-command-scope` section J — **each time slightly differently.**

**The decision here is deliberate and worth stating: do NOT extract a shared helper up front.**
ADR-0069 is the precedent and it cuts the other way from the instinct. The plan-task predicate was
correctly extracted *after* three divergent copies existed and could be compared; extracting on the
strength of a pattern nobody has applied twice in the same shape is the speculative version of the
same move. So #206 establishes the shape knowingly, #211 and #208 reuse it, and the extraction
question gets asked at the end **with four call sites of evidence** instead of a guess. Accepting a
fourth copy on purpose is the point, not an oversight.

**3. #207's stale pointer is inside the file #206 has to work in.** `concept-to-code/SKILL.md` is
both the subject of #207's confirmed defect and the largest source of fences #206 must extract.
Fixing the pointers first means #206's author is not reading wrong ones. Weak as dependencies go,
free to honour.

#### 6.1 — Remove active misinformation (small, independent, do first)

- [x] **#213 — the RUNBOOK validator path.** DONE (ADR-0081, PR #215). The path fix is trivial; **the defect is the false
  green.** `bash` on a missing script exits 127, the loop greps for "Validation failed", never
  matches, and reports `OK` for every agent file. An operator following the full-install procedure
  gets a clean validation pass having validated nothing. Fix the guard (`[ -x "$V" ] || exit 1`)
  before, or independently of, fixing the path — the guard is the part that generalises.
- [x] **#212 — the `hook-verify-workflow.sh` layout remap.** DONE (ADR-0081, PR #215) — there were **two** anomalies, not one. Nothing is broken; it cost adjudication
  time once in this very audit and the plausible failure mode is someone "fixing" the reference and
  breaking a deployed path. A note at both sites plus an assertion that the remap still exists.
  Also answer the open sub-question rather than assuming: **is it the only shape-remapping `PAIRS`
  entry?** The issue is explicit that "the only one this sweep surfaced" is a different claim.

#### 6.2 — One derived reference check, two issues closed

- [x] **#207 + #210 together.** DONE (ADR-0082, PR #216). Repoint three stale/drifting references to **named headings**
  (`SKILL.md:129`, and `agent-write-scope.sh`'s two), then build one check whose population spans
  **both** `staging/plugin/skills/*/SKILL.md` and `staging/plugin/scripts/*.sh` headers.
  - Direction first (rule 5): it must fail on a reference the derivation **omits**, not merely
    validate the ones it finds. That is the ADR-0043 lesson and #207 names it.
  - **Check heading collisions before converting.** `concept-to-code`'s Step 5 and Step 6 workflow
    blocks share a heading verbatim — ADR-0018's fix had to name the step as well. A non-distinctive
    heading reference is not an improvement over a line number, it is the same fragility wearing
    better clothes.
  - `SKILL.md:2684 → 152-158` is drifted, not yet wrong. Convert it in the same pass; it is the next
    one to break.

  **Outcome — the plan under-counted by a factor of two, and the derivation is why.** The three
  references the roadmap named were the three the issues had verified. Deriving over all of
  `staging/` (not just `skills/*/SKILL.md` + `scripts/*.sh`) found **six wrong, one drifted, eight
  accurate-but-numeric** — fifteen in all. Three of the six were named by **no issue**, and two of
  those live in **skill-private `scripts/`**, a surface neither #207 nor #210 mentions and the
  subtree ADR-0043 recorded `pairs-completeness.test.sh` as blind to. Rule 5, demonstrated a third
  time on one defect.

  The heading-collision warning turned out to be already spent: ADR-0018's own rename resolved the
  Step 5 / Step 6 duplicate, and `workflow-dispatch-pins.test.sh` B4a/B4b/B5 hold it open. All nine
  anchors resolve uniquely — checked before converting, as the plan required.

  **`hook-verify-workflow.sh`'s pointer rotted the day before, in ADR-0080's own commit** — the one
  that grew `pre-flight-pattern-enforce.sh`'s header by ~50 lines while fixing a neighbouring defect
  in the same file. The population needing this check is not "old files someone forgot".

  Mechanism for 6.3/6.4 to reuse: derive the population, extract tokens, require each to be
  converted **or declared in the file that carries it** on ONE line
  (`xref-exempt: <tok>|<tok> — <reason ≥ 40 chars>`). The extractor **skips declaration lines**, or
  a waiver for a token present nowhere else looks live (rule 12); `U2` runs it backwards so a
  declared-but-absent token is flagged. The one-line rule is load-bearing: a wrapped reason is a
  prose assertion that depends on where the text breaks — fourth instance of that family after
  ADR-0073, ADR-0076 and ADR-0080, and it caught the first three declarations written for this fix.

#### 6.3 — The big one, and the pattern the rest reuse

- [x] **#206 — nine abort-capable fences that nothing executes.** Five in `autopilot-build`, and
  **that subset carries most of the value**: it is the unattended path, where an aborting pre-flight
  is the only thing between a manifest and a silent bad run.
  - **Order within: `autopilot-build`'s five first.** If this item has to be cut short, cutting after
    those five leaves the argument intact.
  - **Fix the inherited hazard, do not just avoid it.** `plan-task-count.test.sh` PTC/PTF already
    extract by heading anchor, and a heading rewrite turns extraction into a *skipped section* that
    passes quietly. Whatever #206 adds inherits that; the existing two should be corrected in the
    same pass, or the phase ships new code that is safer than the old code beside it.
  - **The extractor must tolerate indented fences.** `nightly-autopilot` indents them inside numbered
    lists, and a column-0 anchor undercounts — this issue's own first measurement said 101 instead of
    138 for exactly that reason.
  - Decide the contract-vs-illustration marker here, since #211 will reuse it.

  **Outcome — it found a P1, and the roadmap's own two warnings were both wrong.**

  **#218: `autopilot-build` check 2 has never been able to pass.** `awk '{print $2}'` does not strip
  the quotes that `manifest-init.sh:73` and `manifest-transition.sh:133` both write, so the
  comparison was never true and the unattended pre-flight aborted on every manifest the system has
  ever produced, printing `current_step is "ready_for_implementation", not
  ready_for_implementation`. A singleton: `manifest-validate.sh` uses the correct `sed` idiom at 17
  sites and check 1 uses a correct 3-sed chain **twenty-five lines above**. Check 2 invented a
  third. Found by running the fence. This is the entire argument for the phase, delivered.

  **The counts were wrong.** 13 abort-capable, not 15; 4 covered, not ~6. The 15 came from matching
  `ABORT` as a substring, which hits "aborted"; the 6 counted a fence that is not abort-capable.
  Both off by two the same way, so `15-6` and `13-4` agree on 9 — two wrong numbers subtracting to
  the right one is not a check.

  **The heading-anchor hazard was mischaracterised here and in `CLAUDE.md`.** Measured by rewording
  the anchors: `plan-task-count` 43/0 → **35 passed/2 failed**, `scope-guards` 29/0 → **27/2**. Not
  a quiet pass. Two worse things: six assertions **vanished** from one (a suite reporting fewer
  assertions does not read as broken), and the other **misattributes** — an empty extraction is an
  empty script, an empty script exits 0, so positive assertions go green and only the abort ones
  fail, blaming the guard. Fixed three ways, each verified failing: marker anchors on all five
  extractors, empty extraction returns 97, and an assertion-count **floor** in three files.

  **Mechanism for 6.4:** `<!-- fence-contract: <id> -->` / `<!-- fence-illustration: <reason ≥ 40
  chars> -->`, one line, immediately above the fence, doubling as the extraction anchor. `bash -n`
  is the contract-vs-illustration classifier and it isolated exactly one illustration among the 13 —
  the decision was measured, not settled by taste. `F4` accepts only needles that are real
  executions; a `# covered elsewhere` comment would have been a claim.

#### 6.4 — Reuse the pattern

- [x] **#211 — ten skills read by no test.** Not "test all ten": decide per skill whether it is
  deliberately uncovered or an oversight, and record the first case **in the skill file itself**.
  Should be substantially smaller once 6.3 has settled the declaration mechanism.
- [x] **#208 — three derived guards stopping at unchecked boundaries.** (1) per-population count
  guard, (3) derive the agent list from `agent-command-scope.sh`'s own `case` arm. (2) may be
  correct to leave — if so, **say it in the test**, so the next author meets a decision instead of
  inventing an exemption that would be wrong.

  **Outcome — the mechanism transferred, and both issues' premises needed correcting first.**

  **#211's count was right and its premise was wrong** (ADR-0084, PR #221). It said the ten were
  "read by no test at all". Measured: false — **three** derived sweeps already read the whole corpus
  (`worktree-isolation-contract`, `agent-tool-parameter-names`, `skill-text-corrections` F6). Under
  the obvious predicate "some test opens this file", **all 29 would pass** with the count guard
  green. So the predicate is the literal string `<name>/SKILL.md`, which a glob or a variable cannot
  produce, and `S6` pins that against a glob-only fixture. **A right number can sit on a wrong
  premise, and only the premise decides the design.**

  **The predicate proved itself on its own author.** The first draft of the `goal-loop` /
  `research-prompt` assertions was a two-element `for` loop, and the perimeter check went on
  reporting both skills as uncovered — correctly, since a hardcoded two-name loop is
  indistinguishable from a sweep. They are now `F7`/`F8`, named, with the reason at that site.

  Five skills covered as real oversights (`humanize-en` was ADR-0040's own unverified half;
  `goal-loop`/`research-prompt` were pinned only by a blueprint sentence; `refactor-snapshot` and
  `vibe-status` had sibling tests reading their `scripts/` and not their `SKILL.md`), two given the
  cross-file gate contract with c2c §25, three declared deliberately uncovered.

  **#208 had three boundaries and there was a fourth** (ADR-0085, PR #223). The premise held —
  0 of 38 skill scripts read a transcript — so the guard went on the **denominator**: `T0b` counts
  38 candidates, not 0 matches, because zero matches is the correct answer today while zero
  candidates is a broken glob and from outside they are identical. `Z5` makes the `compliant()`
  decision executable rather than a comment: a rule-abiding python3 reader is pinned as
  reported-non-compliant, with the instruction to extend the predicate and **never** exempt the hook.

  **The fourth boundary came from running the third-agent case, not from reading it.** The probe was
  meant to confirm section J extends itself when an agent is added to the hook's `case` arm. It does
  — and `coder.md` grants a bare, unrestricted `Bash`, yielding zero `Bash(<word> …)` entries, so
  ADR-0079 §D1's whole argument does not hold for it and its silence would look exactly like
  coverage. `J0c` asserts no scoped agent holds one. `coder` is one line of the hook away from being
  in scope.

  **Found on the way, filed as #222:** five skills are deployed in `~/.claude/skills/` and absent
  from `staging/`. `ui-layout-audit` is the serious one — c2c §25 declares it chain-invokable at gate
  5.05, and F6's `[ -f "$_sf" ] || continue` skips it in silence, so the one chain-invokable skill
  that is not vendored is the one skill F6 cannot check. It does not carry the flag today; the
  structural hole is what was filed. Widening #211's check to `~/.claude` was rejected — it would
  make the harness depend on the machine's deploy state, the opposite of ADR-0024.

#### 6.5 — Close the loop

- [x] Ask the extraction question with four call sites in hand: is there one derivation+waiver+
  count-guard helper here, or five deliberate copies? Either answer is fine; an unasked question is
  not.

  **Answered: six deliberate copies, no shared helper** (ADR-0086). The count was wrong here too —
  re-derived from the files rather than from this list, there are **six** instances, not four, and
  this paragraph named the wrong four. They split into two shapes: four carry the full triad
  (`transcript-scan-rule`, `fence-contract-coverage`, `cross-reference-form`,
  `skill-coverage-perimeter`), two derive and count but hold no waiver because they need none
  (`skill-text-corrections` F6, `agent-command-scope` J).

  **The criterion is the reusable part, not the verdict: extract only when two copies giving
  different answers would be a DEFECT.** For ADR-0069's plan-task predicate, yes — three consumers
  asking ONE question and getting three answers, which is what issue #172 cost. Here, no: six
  questions about six populations, where `>= 8`, `>= 25`, `>= 100` and `>= 2` are legitimately
  different numbers about legitimately different things.

  Two differences a single helper cannot reconcile, both measured: `fence-contract`'s marker **is**
  the extraction anchor and must be found, while `xref`'s must be **excluded** or a declaration
  satisfies itself — contradictory requirements on the same field. And the marker's syntax follows
  the file's language (shell comment vs HTML comment), not the pattern. Six parameters for six
  callers is a configuration file with an extra indirection, not a helper.

  Recorded in each of the six headers, one line naming the instance, because the seventh will be
  written by **copying one of the six**. No test asserts those lines exist: an assertion that a
  comment is present cannot be seen meaningfully RED, and it would be the seventh instance of the
  pattern under review.
- [x] Then the **shakedown run** — *moved to Phase 7, where it is the whole phase rather than the
  tail of one.* It was written here as a closing step and it is not one: it is the first time any of
  Phases 4–6 gets executed instead of asserted.

#### Risks

- **#206 is the item most likely to grow past its estimate.** Nine fences, each needing a fixture and
  a substitution contract (`run_check1` and `run_check6` already show two different shapes), plus a
  classification decision. Split by skill if needed; `autopilot-build` alone is a defensible landing
  point.
- **6.4 is sized on an assumption** — that 6.3's mechanism transfers. If it does not, #211 and #208
  are full-size items and the phase is longer than it looks.
- **Nothing in this phase produces a visible improvement**, the same property Phase 4 had. The
  difference remains that an unrun pre-flight check is exactly what the shakedown run would trip on.
- **Seven issues is the most that has been open at once since the audit-fix roadmap.** The temptation
  is to batch them into fewer PRs; #206 and #211 in particular must not share a PR, for the same
  reason #193 and #195 could not — two derived checks that can each pass vacuously would mask each
  other.

### Phase 7 — execute the chain instead of asserting it (the shakedown run)

Phases 4, 5 and 6 shipped 18 ADRs and roughly 250 assertions, and **not one line of any of it has
been exercised by a real `concept-to-code` run**. Every guard was verified against a planted defect,
which proves the guard fires and proves nothing about the chain it guards. This phase is the first
time the system is run rather than inspected.

Promoted out of 6.5, where it sat as a closing step. It is not a closing step: it is the only item
on this roadmap whose output is evidence rather than more assertions.

#### 7.1 — The run

- [x] **Pick the feature, then commit to it.** Small, real, low-stakes, and preferably something the
  repository actually wants. **Recommended: issue #222**, which is the other outstanding item — it
  has a bounded requirement set (decide per skill: vendor or record as deployed-only), a plan that
  decomposes into tasks, tests worth writing, and no way to damage anything. Running it through the
  chain closes both remaining items in one pass.
  - The trade: if the chain halts mid-run, #222 halts with it. Acceptable — #222 is not urgent, and a
    halt **is** the phase's product.
  - The alternative is a throwaway feature, which costs a second run to get the real one done and
    tests the chain on work nobody cares about, where a wrong answer is easy to wave through.
- [x] **Run it end to end**, attended, with no shortcuts around a gate. A gate that is inconvenient
  is the finding.
- [x] **Record every finding as an issue, one per finding, filtering none.** That rule produced #218,
  #222 and the four defects of #184. A run that reports "went fine" has told us nothing we did not
  already believe.

#### Three expected non-regressions — do not mistake them for breakage

Carried unchanged from Phase 5, plus what 6.1–6.5 added:

- **`diff-budget-check.sh` is active for the first time since July** (ADR-0070). It may report
  `BUDGET`/`SCOPE` on work in flight, against budgets written when nothing read them. Advisory by
  contract; the first one will still look like a regression.
- **The `manifest-field-state.sh` dependencies fail CLOSED on an un-synced machine** (ADR-0076). If
  the pre-flight aborts asking for a sync, that is the design working.
- **Step 5's Workflow dispatch finally produces Workflow-path data** for ADR-0080's pre-registered
  condition. `src=main-fallback` non-zero means investigate the lookup, **not** drop the fallback —
  the branch that reads counter-intuitively, written down before the data arrives so the outcome
  cannot be rationalised afterwards.

#### What has never run, and is therefore what this tests

Listed so a halt can be read against the right ADR instead of debugged from scratch: Gate 4.0's
branch-and-commit producer (ADR-0071), the Step 5 gate that can now **edit `SPEC.md`** (ADR-0072),
the heading-form plan predicate (ADR-0069), the worktree base-fork comparison at merge-back
(ADR-0068), the three Step 5 → Step 6 gates and their two opposite caller idioms (ADR-0046/0047/0048),
and every `PreToolUse` scope hook firing against real dispatches rather than synthetic payloads.

#### 7.2 — Issue #222, if the run does not absorb it

- [x] Five skills deployed in `~/.claude/skills/` and absent from `staging/`: `agent-design`,
  `daily-close`, `daily-open`, `ui-layout-audit`, `vibiso-intake`. Decide per skill — vendor with a
  `PAIRS` entry, or record as deployed-only the way ADR-0024 recorded `website-auditor`.
- [x] **`ui-layout-audit` does not admit the second option.** `concept-to-code` §25 declares it
  chain-invokable at gate 5.05, so either vendor it or remove it from §25. A chain that names a skill
  it cannot verify is the ADR-0042 disagreement in a new place.
- [x] Make `skill-text-corrections` F6's silent skip loud, or count-guard it against the §25 list
  length rather than against what resolved. Today `_F6_CHECKED >= 5` is satisfied by the seven that
  do resolve.

#### Risks

- **The temptation will be to fix findings mid-run.** Do not: the run's value is the unbroken record
  of what the chain does today. Note, file, continue — unless the chain cannot proceed at all.
- **A clean run is the outcome most likely to be misread.** Every guard added since Phase 4 is
  preventive, so a run touching none of them proves the feature was small, not that the system is
  sound. Say which gates fired and which were never reached.
- **The three non-regressions above will look like breakage in the moment.** They are written down
  here precisely because they will be met while tired and mid-run.

#### 7.3 — Outcome (2026-07-30)

The run completed. #222 shipped as PR #251; `--apply` ran; the second dry run reported zero drift.
**Twenty-one findings**, three fixed because they blocked (#230, #235, and #241 via PR #243 /
ADR-0088), seventeen open and carried into Phase 8.

**The three expected non-regressions, against what actually happened:**

- **`diff-budget-check.sh` fired for the first time since July** — and both findings were **false**,
  from a cause nobody predicted: the architect writes per-file budget ceilings
  (`file (~165 lines), file2 (~1 line)`), and the parser half-reads that form into a wrong file set
  and a wrong ceiling (#246). The prediction was right that the first one would look like a
  regression, and wrong about why.
- **`manifest-field-state.sh`'s fail-closed dependency never fired.** The machine was synced. The
  branch remains unexercised.
- **Step 5's Workflow dispatch never happened.** `hook_verified` is `false`, so the run took the
  Agent-tool fallback throughout. **ADR-0080's pre-registered condition is still unfed** — no
  Workflow-path `src=` data was produced, and the fallback verdict stands on n=3 exactly as before.
  A future run that flips `hook_verified` is what closes it.

**Of "what has never run", what ran:**

| ADR | outcome |
|---|---|
| ADR-0071 Gate 4.0 producer | Ran, and **could not produce** — #234, then #239 |
| ADR-0068 base-fork comparison at merge-back | Ran **seven times, matched every time**. First live confirmation of `worktree.baseRef: "head"` |
| ADR-0046/0047/0048 the three Step 5 → Step 6 gates | All three ran; coverage 10/10 exit 0, weakening `CLEAN`, budget false-positive above |
| ADR-0069 heading-form plan predicate | Correct, but its output is consumed by a caller that needs a different predicate (#242) |
| ADR-0072 the gate that can edit `SPEC.md` | **Never fired** — the SPEC was written with proper checklist ids |
| `PreToolUse` scope hooks against real dispatches | `test-write-scope.sh` fired, correctly, and that is how #241 was found |

**And the risk this file named came true in the useful direction.** "A clean run is the outcome most
likely to be misread" — the run was not clean, and the twenty-one findings are the phase's product.
The other risk, "the temptation will be to fix findings mid-run", was honoured except once: #241
blocked Step 5 outright, so it was fixed first, in its own PR, before the run resumed.

### Phase 8 — the seventeen the shakedown found

Grouped by dependency, not by number. **8.1 and 8.2 run together as one phase with a PR per issue** —
a deliberate choice, made knowing the cost: five issues in flight across three areas of the chain is
the overlap that produced #247 during the shakedown itself (a correction to a rule written hours
earlier). Mitigated by the ordering **inside** the phase, not by splitting it.

#### 8.1 — The chain cannot complete a run

- [x] **#239 — Step 5.0.1 can never pass.** The chain writes the manifest after Gate 4.0 commits it,
  on both Gate 4 branches; the fresh-session branch is worse, because Form B resume writes it
  unconditionally. "The working tree is clean" and "the manifest is written at every state change"
  are flatly incompatible requirements on the same file. The structural one — do it first.
  **Shipped, PR #257** (ADR-0089): the manifest leaves the dirty set and only the manifest, bounded
  by `manifest-validate.sh`; 5.0.1's classification stopped being prose and became a declared,
  executed fence.
- [x] **#248 — `step_5_implementation` has no producer on the default path.** Every occurrence of the
  transition lives inside Step 4.5's tracer-bullet block, which is off by default, so Step 5 cannot
  reach Step 6. Same class as #239 and the same stretch of the chain: one pass over Gate 4 → Step 6.
- [x] **#234 — Gate 4.0 cannot stage untracked artifacts.** Upstream of #239: without it Gate 4.0
  produces nothing for #239's fix to preserve. **Shipped, PR #255** — `commit --include`.

#### 8.2 — The chain can destroy work

- [x] **#245 — `isolation: worktree` is a CWD convention, not a sandbox.** An absolute path writes
  into the shared checkout; the three scope hooks all constrain *which files*, never *which tree*.
  The coder's dispatch brief hands it four absolute paths in its first four lines. Three candidate
  fixes with very different blast radii — do not bundle it with anything. **Shipped, PR #254**
  (ADR-0068 §D11): a merge-back escape check plus a WORKING ROOT clause at all four dispatch sites.
  A hook was measured and rejected — the observed escape came through `mkdir`/`cp`, which carry no
  `file_path` for a `PreToolUse` matcher to read.
- [x] **#228 — Step 1 overwrites a root `SPEC.md` belonging to another topic.** `gate0-detect.sh`
  already reports `spec_topic_match=false` and the detection protects nothing. Destroys a
  human-reviewed artifact.

#### 8.3 — What a gate shows, and what it records

- [x] **#237 — Gate 4 conflates *where* with *how*.** Four cells, two offered, and no attended
  same-session path.
- [x] **#227 — Gate 0 shows two contradictory `Recommended` markers.** Same defect class as #237 in a
  different gate; #227's own body says the two may want one answer. Design them together.
- [x] **#238 — the `hitl_gates` trail is written by nobody and has no slot for Gate 4.** Depends on
  #237: the slot's shape follows what Gate 4 becomes.

#### 8.4 — Batching

- [x] **#242 — the `>=6` threshold consumes a count ADR-0069 documents as not a task count.** 38
  versus 7 on the shakedown's own plan.
- [x] **#247 — the two batch-boundary rules can conflict, and a checkpoint can be legitimately RED.**
  A correction to ADR-0088 §D5, written during the run. If its fix introduces a plan-declared
  "expected red", it consumes the same parsing #242 needs — so pair them.

#### 8.5 — Recovery and history

- [x] **#244 — `recovery_baseline_sha` is not rebase-safe**, and a paused chain all but forces a
  rebase. Do this first: it is #249's target.
- [x] **#249 — Step 7's commit describes nothing.** The merge-back already committed the feature as
  `chore(step5): snapshot … worktree`. The cheapest fix is a soft-reset to the baseline, which is
  why #244 comes first.

#### 8.6 — Half-read forms and stale records

Independent of each other and of everything above; no ordering constraint.

- [x] **#246 — a per-file `Budget:` line is half-parsed** into a false SCOPE and a false BUDGET
  instead of being treated as absent. Fourth instance of the near-miss class.
- [x] **#240 — `step5_mode` documents `agent_fallback`**, which nothing has ever written; 17
  manifests carry `agent_batch`.
- [x] **#232 — `detect-macos.sh` fires on the skill name `macos-ux`** and on a Stack line naming the
  host platform, so every meta-SPEC in this repository trips Gate 1c.
- [x] **#233 — Gate 2b asks to authorise a test-cmd that is already SHA-pinned.** The autopilot
  branch has the read-only probe; the attended one does not.
- [x] **#250 — RTF gitignores its state file by branch name**, so `.gitignore` grows one dead line
  per branch. One glob fixes it permanently.
#### 8.7 — Execution roadmap

> **Superseded by §8.8 (2026-07-31).** Every issue below is closed. This section is kept as the
> planning record — the order it chose and the reasons it gave are what §8.8's outcome is measured
> against — not as a list of open work.

The grouping above says *what*. This says *in which order* and *which fix*, one direction chosen per
issue. **Regenerated 2026-07-31 after Wave A1 shipped** (#239, ADR-0089, PR #257) — four measurements
from that wave changed the plan, and one of them added a sixteenth issue.

##### What Wave A1 measured, and what it changed

1. **Ten of the fifteen remaining fixes land in one file.** `concept-to-code/SKILL.md` is the fix
   site for #248, #228, #237, #227, #238, #242, #247, #244, #249 and #233. Only #246, #240, #232,
   #250 and #258 are outside it. So "one PR per issue" is **ten serial PRs on one file plus five
   independent ones**, not fifteen parallel ones. Wave E was written last and is the only genuinely
   conflict-free set — **it moves first**, so that five issues close while the serial queue drains.
2. **Rewriting an abort-capable block is no longer optional work.** ADR-0083's `F3` fails CI on any
   abort-capable fence with no declaration, and `F4` on any declared contract no test runs. A1 took
   the corpus from 12 declared contracts to 13. Every remaining wave that touches a bash block that
   can stop a run now owes a `fence-contract:` marker **and** an execution — that is enforcement,
   not a suggestion, and it should be costed into each PR rather than discovered at the CI run.
3. **The path/symlink class was measured and is closed. No issue.** A1's first draft compared a
   git-resolved path against a caller-carried one and every artifact misclassified. Swept the rest:
   `stop-gate.sh` and `triage-state.sh` carry explicit `/var → /private/var` comments,
   `write-scope-enforce.sh` normalises, and `agent-write-scope.sh` / `test-write-scope.sh` are
   immune by construction (they match `*/docs/architecture/*`-style globs, not root prefixes).
   The new code was the only wrong site. Recorded so nobody re-derives it.
4. **A sweep for "which fences can tell did-not-run from found-nothing" produced #258 — and a
   correction to its own first number.** The sweep reported *11 of 12 declared contracts have no
   `exit 3`*. Right number, wrong premise (the ADR-0084 lesson, on my own measurement): an `exit 3`
   **code** is only needed where a caller branches on it, and eleven of twelve already fail closed
   by whichever idiom suits them. Classifying all eight `autopilot-build` checks found exactly one
   that does not.

**Carried forward from the first draft of this roadmap, still true: there are TWO derived guards,
not one.** 8.1's closing note and the "What Phase 8 must not become" block below both propose a
single check closing #239, #248 and #238 together. ADR-0086's criterion says otherwise — the
populations differ (transition pairs against call sites; helper scripts against call sites), so two
copies giving different answers would **not** be a defect. A2 builds the first; #238 builds the
second. Deliberately not extracted.

##### The sixteenth issue

- [x] **#258 — `autopilot-build` check 6 reads `test_cmd_placeholder` with a bare `m.get()` and
  fails OPEN.** `2>/dev/null` turns an unparseable manifest, or a missing PyYAML, into an empty
  string that is not `"True"`, so the unattended pre-flight proceeds. Reproduced both ways. It is
  the exact pattern ADR-0076 §THE RULE forbids, four lines above check 7 which ADR-0075 fixed for
  the same reason — and a **singleton**, like #218 in the same file: five checks read state, four
  fail closed by four correct idioms, one invented a fifth with the direction reversed.

##### Wave E — the conflict-free set (five PRs, no ordering, **now first**)

Nothing here touches `concept-to-code/SKILL.md`, so these can land in any order, at any time, and
alongside the serial queue below.

- [x] **#258.** Replace the one-liner with `manifest-field-state.sh` (check 7 next door already
  resolves and calls it, so the dependency and its fail-closed-on-missing-helper handling exist in
  this file). Value domain stays the caller's; `ABSENT` needs a stated decision, since a manifest
  predating the placeholder mechanism cannot be carrying one. Both directions executed: a valid
  `false` proceeds, an unparseable manifest aborts. The second is what fails today.
- [x] **#246.** Extend the grammar to accept per-file ceilings, the form architects actually write,
  and add a distinct `MALFORMED` token for anything that still does not parse. ADR-0072's rule: **a
  form close enough to be partially read is worse than one rejected outright.**
- [x] **#240.** Correct `agent_fallback` → `agent_batch` in three places. The 17 historical
  manifests are **not** rewritten (ADR-0034/ADR-0078 precedent).
- [x] **#232.** Drop bare `macos|mac os` from the trigger set, keep `swiftui|appkit|mac app|menu
  bar` — all UI-target declarations, where "macOS" alone names the host. One narrowing kills both
  false positives, including the skill name `macos-ux` that every meta-SPEC here cites.
- [x] **#250.** `triage-state.sh commit` appends the glob `.claude/.triage-fix-last-*.json`, skips
  when a line already covers the file, plus a one-time sweep of the dead entry.

##### Wave A — the chain cannot complete a run (two PRs, serial)

- [x] **A1 — #239.** Shipped, PR #257, ADR-0089. The manifest leaves the dirty set and only the
  manifest; the exemption is bounded by `manifest-validate.sh`; 5.0.1's classification stopped being
  prose and became a declared, executed fence. **Its own lesson: the block was not merely
  unexecuted, it was UNEXECUTABLE**, which is what kept it outside the population ADR-0083 guards.
- [x] **A2 — #248, plus derived-guard instance 8.** Now genuinely reachable for the first time —
  until A1, nothing got past 5.0.1 to discover Step 5 could not leave. Step 5's entry performs
  `ready_for_implementation → step_5_implementation`, immediately after the pre-flight A1 just made
  passable. Step 4.5's **green branch drops its own transition**, or Step 5 retries a same-to-same
  pair that is not legal; the amber and red-reduce branches keep theirs, which go elsewhere. Then
  the guard: every legal pair in `manifest-transition.sh` has at least one producer in a `SKILL.md`,
  exemptions declared in the transition script, count guard on the **denominator** (ADR-0085).
  Lands in the block A1 just rewrote, so it should follow immediately rather than after a queue.

##### Wave B — the chain can destroy work (one PR)

- [x] **#228.** Archive and proceed; heal only what is recoverable. A root `SPEC.md` whose
  `**Topic slug:**` names another topic is copied to `docs/specs/<its-own-slug>.spec.md` and the
  chain proceeds; if that file is dirty or uncommitted, halt with the exact command. Correct Step
  1's `mode=greenfield` comment, which reads "SPEC.md does not exist" when two different states
  reach that branch. One-time cleanup: archive #176's SPEC, the only unarchived one of the 35.

##### Wave C — what a gate shows, and what it records (three PRs, serial)

- [x] **#237.** Four cells, four options. `AskUserQuestion` accepts exactly four:
  attended-this-session, unattended-this-session, fresh-session, abort. The missing cell is added
  rather than documented as excluded.
- [x] **#227.** The auto-detect line becomes explicitly advisory (`Auto-detect suggests:`), the
  orchestrator's `(Recommended)` marker is the single recommendation, and a divergence is **stated
  in the gate text**. Separately, rename `file_estimate`: it counts files in the repository, not in
  the feature.
- [x] **#238.** Depends on #237: the slot's shape follows what Gate 4 becomes. `manifest-init.sh`
  gains `- gate: 4`; each gate's post-click branch calls `manifest-set-gate.sh`. Invariant 9 **does
  not** read status — any status invariant would have to be conditional on `current_step`, which is
  ADR-0076's rule and the same trap.

##### Wave D — batching (two PRs, serial)

- [x] **#242.** `plan-tasks.sh --count-openers` exposing `is_task_opener()`; the `≥6` threshold and
  the batch ranges consume it, the `≥1` guard keeps `--count`. State at the call site which count
  answers which question. The defect is one number silently serving two questions: 38 against 7.
- [x] **#247.** Minimum first, and it is documentation: ADR-0088 §D5 states that rule 1 outranks
  rule 2 when they conflict, and why. Then the cheapest mechanism: the checkpoint compares the
  failing set against the **previous checkpoint's** and reports only new failures. No plan syntax —
  and #246 has already landed by now, so its half-parsed-declaration warning is evidence rather
  than a forecast.

##### Wave F — recovery and history (two PRs, serial)

- [x] **#244.** Step 5.0.3 gains a resume-time validity check (`git merge-base --is-ancestor`) that
  **reports** rather than halts. The merge-not-rebase rule is stated at 5.0.3 and in the paused-run
  remediation, where today it exists nowhere. ADR-0050 §D3 gains a clause on "orphaned, not moved".
  **Evidence-driven addition:** 5.0.3 is still prose wrapped around a `sed -i.bak`, the same shape
  A1 found at 5.0.1 — declare and execute it in the same pass rather than leaving the neighbour of
  a fixed block unfixed.
- [x] **#249.** Step 7 soft-resets to `recovery_baseline_sha` before invoking `commit`. The reset
  refuses to run when the baseline is not an ancestor, which is #244's check.

##### Wave G — the last c2c gate (one PR)

- [x] **#233.** The attended Gate 2b gets the same read-only probe the autopilot branch documents.
  On `TRUSTED`, one line and proceed; on a changed SHA the gate stands. The invariant is untouched:
  this reads trust that exists, it never grants any. Its probe block is abort-capable, so point 2
  above applies: it needs a `fence-contract:` and an execution.

##### Wave H — verification

- [~] **A second end-to-end shakedown.** Phase 8's product is verified by nothing else.
- [~] **Half of every Step 5 fix stays unexercised until `hook_verified` is true.** No run has ever
  taken the Workflow dispatch path, so each fix above lands on one of two paths with the other
  unmeasured. A green second shakedown must not be read as covering both.

##### Rules earned in Wave A1, carried forward

- **A plant that does not fire is evidence about the assertion, not a formality to get past.** Two
  of nine did not fire. One targeted dead code; the other targeted the untested half of a
  normalisation, and that is what produced ADR-0089's note distinguishing the evidenced half from
  the defensive one. Both are recorded rather than quietly re-planted.
- **Prose is not merely unexecuted, it is unexecutable** — and that is what keeps a block outside
  every guard built for the executable population. When a fix rewrites a rule, ask whether the rule
  can be run at all before asking whether it is right.

#### 8.8 — Outcome (2026-07-31)

**The Phase 8 fix roadmap is closed.** Twelve issues shipped in one session, each with its own PR,
CI green, squash merge, and a verified `--apply` sync. Harness 53 → 67 files.

| wave | issues | ADRs |
|---|---|---|
| A2 | #248 | ADR-0095 |
| B | #228 | ADR-0096 |
| C | #237, #227, #238 | ADR-0097, ADR-0098, ADR-0099 |
| D | #242, #247 | ADR-0100, ADR-0101 |
| G | #233 | ADR-0102 |
| F | #244, #249 | ADR-0103, ADR-0104 |
| — | #265, #267 (found by this phase's own guards) | ADR-0105, ADR-0106 |

**One issue is open: #273**, split out of #247 and deferred with measured reasons — a plan-side
expected-red syntax has the shape ADR-0091 has just shown is expensive to get wrong, and the cheaper
alternative separates *new* from *carried-over*, not *intended* from *unintended*.

##### What the roadmap got wrong about itself

§8.7 planned sixteen issues and named the fix direction for each. Measuring changed the direction or
the premise on **seven** of them:

- **#227** said `file_vote` degenerates "past a few hundred files". The threshold is **20**, so
  `express` can never be auto-recommended on any real repository.
- **#228** named #176's SPEC as the only unarchived one; it had been archived by #229. And the
  archive is **not** named by the topic slug — 3 of 41 — so the by-name check the issue proposed
  would have written a duplicate beside 38 existing archives.
- **#240** blamed ADR-0016, which was correct all along; the error entered in a *summary* of it.
- **#242** called the case "benign on this plan by luck". The two counts diverge on **51 of 58**
  plans, all over-counted.
- **#247** predicted an unattended halt. `autopilot-build`'s breaker reads the report **after
  dispatch**, once, so the run in question would not have halted.
- **#248**'s own suggested guard does not catch #248 — it catches the #238 shape. It found #265
  instead, on its first run.
- **#267** named one defect; there were two, and the second (the last chain's SPEC is never
  archived) is the one with a live consequence.

**The lesson §8.7 could not have written: an issue's measurement is a hypothesis.** Re-deriving it
before designing changed the design seven times out of twelve.

##### What remains

- **A second end-to-end shakedown.** Phase 8's product is verified only by another run, and that run
  is also what feeds ADR-0080's still-unfed condition — `hook_verified` is still `false`, so no run
  has ever taken the Workflow dispatch path and **half of every Step 5 fix in this table is
  unexercised**. A green second shakedown must not be read as covering both paths.
- **#273**, whenever the checkpoint needs to decide rather than the reader.

#### What Phase 8 must not become

- **A second inspection phase.** Sixteen of these seventeen were found by running the chain, not by
  reading it. Each fix needs the same treatment: an assertion seen RED, and where the fix is prose,
  an executed premise rather than a claim.
- **A phase that re-derives the same guard six times.** #239, #248 and #238 share a shape — a
  consumer and a producer specified in different places, with nothing checking the producer exists.
  **Superseded in part by §8.7:** applying ADR-0086's criterion to them gives **two** guards, not
  one, because the populations differ (transition pairs against call sites for #248; helper scripts
  against call sites for #238). They would be instances eight and nine of the derived-guard pattern.
  #239 needed neither — its producer existed, and what was missing was that the consumer could be
  satisfied at all.
- **A run of its own without a second shakedown.** Phase 8's own product is only verified by another
  end-to-end run, which is also what feeds ADR-0080's still-unfed condition.

### Phase 9 — what Phase 8 left, and the class it kept re-finding

Phase 8 closed with one GitHub issue open and a handful of consequences the ADRs recorded
deliberately. Those live as bullets at the end of eight documents, which is where they stay
invisible. This phase collects them, and builds the one mechanism the measurement says can close the
defect class that recurred five times while the others were being fixed.

| item | source | state |
|---|---|---|
| 9.1 Executable plant registry | this phase | **done** — #284, ADR-0108, shipped at `83bad6a` |
| 9.2 Fence-contract population | ADR-0096/0102/0103/0104 | **done** — #281, ADR-0107 |
| 9.3 Expected-red mechanism | **#273**, deferred by ADR-0101 | open → Phase 10, wave 3 |
| 9.4 Second end-to-end shakedown | §8.8 | blocked, see below — **not** a Phase 10 feature |
| 9.5 Instruction-not-enforcement cluster | ADR-0097 `G3b`, ADR-0098, ADR-0099, ADR-0103 | open → Phase 10, wave 3 |
| 9.6 Count stated in 3 files, derived in 1 | ADR-0105 | open → Phase 10, wave 1 |

#### 9.1 — Executable plant registry, and what the measurement rules out

Rule 12 — *a scan whose needle is a literal counts itself* — bit **five times in one day**: `SA10`,
`N9`, `GR1`, `GR5`, `SP1`. Each was an assertion whose needle was the **name** of the thing it
asserted about, matching a file that legitimately names it while explaining it. All five were caught
by planting a defect and watching the assertion fail to fail. **The plants worked; nothing made them
durable** — a plant is typed into a shell, watched, and thrown away.

Three root fixes were measured before choosing:

- **A static detector on multi-match needles.** 77 of 181 statically resolvable assertions (43%)
  have a needle matching its target more than once, dominated by legitimate cases (`ADR-0049`,
  `ADR-0063` cross-references). It would flag nearly half the corpus, almost all falsely — and only
  181 of 543 assertions are resolvable at all, a 67% blind spot on top.
- **A code-only projection** (strip comments for shell, keep only fences for markdown). Catches
  **4 of the 5**: `SA10` and `GR1` matched comments, `GR5` and `SP1` matched markdown prose. **`N9`
  matched inside `ok`/`bad` message strings** — code, not commentary — so it misses the sneakiest.
  It also collides with ADR-0086: a shared helper breaks 67 files' hermeticity, and duplicating it
  67 times is what that ADR refused.
- **What actually distinguishes a rule-12 defect is behavioural**: the assertion still passes when
  the mechanism is removed. That is mutation testing and nothing else.

So: a plant declared beside its assertion, `# plant: <id> | <path> | <needle> | <replacement>`, run
by `plant-check.sh` against an isolated copy of the tree. The needle is joined on `\s+`, which puts
today's wrap-insensitivity lesson **into the mechanism**; the runner requires **exactly one match**,
because a plant matching zero or many is itself a defect and both happened today. A plant that does
not fire is reported by name: that assertion pins nothing.

**Scope is the plants already run**, across this session's eight test files — known-good cases whose
answers are recorded in the ADRs. **No retroactive sweep of the other 543 assertions.** Runtime is a
risk to measure, not assume: if the total is too slow for the main CI job it gets its own.

#### 9.4 — The shakedown, and the precondition that must not be buried

`hook_verified` is still `false`, so **no run has ever taken the Workflow dispatch path**. Half of
every Step 5 fix from Phase 8 is unexercised, and a green second shakedown **must not be read as
covering both paths**. It is also the only thing that can feed ADR-0080's still-unfed drop
condition.

#### 9.5 — One decision, not four

ADR-0097's two in-session branches differing by one line, ADR-0098's divergence line, ADR-0099's
gate recording, ADR-0103's merge-not-rebase rule: all prose nothing enforces. Worth deciding once
whether any deserve a mechanism, rather than re-disclosing each time.

#### What Phase 9 must not become

- **A phase that trusts its own issues.** Phase 8's record is that measuring changed the direction
  or the premise on **seven of twelve**. #281 continued it: four ADRs disclosed a gap none of them
  had counted, and the count found a fifth entry older than all four.
- **A registry that only ever reports success.** The plant runner has to be proven against an
  assertion known to be weak, or it becomes the thing it exists to detect.

---

### Phase 10.0 — the blockers that stop Phase 10 from starting (attended, issues #319–#324)

Phase 10's inputs were prepared and verified, and the launch on 2026-07-31 still did not produce a
single implemented feature. It reached the chain's **first Gate 0 write** and stopped. Everything
below was found by trying to run the chain, not by reading it — which is the only reason none of it
appears in the 191-item ADR sweep Phase 10 is built on. A residual is something an author wrote
down; these are things nobody knew.

**Why this phase is attended, and why it is a table rather than a checklist.**
`project-conductor` takes the first `- [ ]` line in this file. Every item here lives inside the
runner's own machinery, and the first two are precisely what prevents the runner from starting, so
the unattended runner cannot be the thing that fixes them. A table is invisible to the conductor by
construction — the same device §9 already uses.

| # | Issue | The measurement | Done means |
|---|---|---|---|
| 1 | #319 — a chain interrupted before Step 4 is unreachable by both entry points | `manifest-init.sh` exits **2** saying *use resume*; the Form B branch table refuses any step before `step_4_session_boundary`. Script-enforced at both ends. A live orphan is on disk. | One documented entry point reaches it; the other's error names it. Nothing is silently overwritten. |
| 2 | #320 — the launch precondition that killed the run is the one Phase 0 does not check | `nightly-autopilot/SKILL.md:37` states it; grepping the skill for `permissionMode\|defaultMode\|acceptEdits\|bypass` returns that one line. Phase 0's eight checks verify it nowhere. `defaultMode` is `auto`. | A blocking mode aborts pre-flight before the guard arms, naming `/permissions` as the remedy. |
| 3 | #324 — a feature that fails at chain entry halts the whole roadmap | Branch C writes the **run-level** `needs-human` for any unexpected state. ADR-0060 §D3 already split known-and-contained from run-level, for a different set of writers. | A known per-feature entry failure marks `[~]` and continues; a genuinely unknown state still halts. Both directions tested. |
| 4 | #321 — an interrupted run leaves the guard armed and nothing documents how to disarm it | `active` is removed only in Phase 2, which a dead session never reaches. The RUNBOOK has no recovery section. This blocked a legitimate push on 2026-07-31. | A stale marker is distinguishable from a live one, and a one-command disarm exists where a blocked human will look for it. |
| 5 | #323 — the guard's push-to-main rule reads the whole command, not the push segment | Probed live: `git push -u origin feat/x` allows, `gh pr create --base main` allows, the two joined by `&&` **halts as push-to-main**. The sibling force-flag rule two lines above is already segment-scoped, with a comment explaining why. | The rule is scoped like its sibling; every genuine push-to-main form still halts, seen RED first. |
| 6 | #322 — pre-flight check 8 verifies one of the three checks `main` actually requires | `main` requires `markdownlint`, `links`, `ci`; check 8 verifies `ci`. PR #317 failed `markdownlint` on three real errors this week. | Pre-flight covers what `main` requires, or states which subset it covers and why. Count-guarded. |

**The order is not by severity.** 1 and 2 are what stopped the run. 3 comes third because until it
lands, one wedged feature in a twelve-feature wave still costs the eleven behind it — fixing the
blast radius is worth more than fixing any single cause. 4 makes an overnight failure cheap to clean
up in the morning. 5 and 6 are correctness of the gate rather than ability to run at all.

**One manual act is not an issue.** The orphaned manifest
`docs/manifests/2026-07-31-the-sixth-bare-manifest-set-flag-sh-ment.manifest.yml` has to be cleared
before any run starts. #319 is about the mechanism; this one file predates it and needs a human.

**Exit criterion.** Not "six PRs merged" — a launch that reaches at least one `NIGHTLY-PUBLISH`
line. Phase 10 wave 1 does not start before that, because a wave that halts on feature 1 costs a
night and teaches nothing.

#### 10.0 — Outcome (2026-08-02), and the fix roadmap that is left

**All six table rows shipped.** Each as its own PR, CI green, squash merge, and a verified `--apply`
sync reporting zero drift. Harness 67 → 72 files, plant registry 32 → 78 plants.

| # | issue | PR | ADR |
|---|---|---|---|
| 1 | #319 | #326 | ADR-0109 |
| 2 | #320 | #327 | ADR-0110 |
| 3 | #324 | #330 | ADR-0111 |
| 4, 5 | #321 and #323, shipped in one PR — neither explains the incident alone | #332 | ADR-0112 |
| 6 | #322 | #334 | ADR-0114 |

Two more landed that the table never named. **#331** — invariant 4 reads terminality from one field
where the state lives in two (PR #333, ADR-0113); found because the manual act above, committed
as #328, made a manifest that validates locally and fails on CI. **#329** — Gate 0 has no
`[Autopilot default: …]`; found while tracing #324's second cause, filed rather than bundled because
what the safe default *is* needs its own decision. The orphan manifest is a committed record now, so
the corpus is 42.

##### What the table got wrong about itself

Three of six, the same rate §8.8 measured:

- **#322** said check 8 verifies one of three required contexts. It verified **nothing**: check 8 was
  prose with no mechanism, and grepping `staging/` for a protection API call returns one hit, inside
  `set-branch-protection.sh`.
- **#321** proposes recording a pid so a stale marker can be told from a live one. The marker is
  written from a Bash tool call whose subprocess exits in milliseconds, so a recorded `$$` is
  **always dead** — the one signal that cannot work. Session id and timestamp are the two real ones.
- **#324** carried a premise from `project-conductor`'s own comment: the c2c autopilot pre-flight
  "hard-aborts at Gate 0 for a missing SPEC.md". It does not. That measurement is what produced #329.

##### The path to the launch, in order

Not a checklist. `project-conductor` takes the first `- [ ]` line in this file and none of the four
rows below are its work — the same device the table above uses.

| # | what | why it is here | done means |
|---|---|---|---|
| 1 | **#329** — Gate 0's autopilot default | The only `chain-blocker` left, and it sits on the unattended path at the **first gate of every feature**. A stall there costs the whole night and produces nothing to read in the morning. | The unattended path reaches a deterministic routing decision with no `AskUserQuestion`, pinned by a test; and `project-conductor`'s "hard-aborts at Gate 0" comment and the code agree, whichever way the decision goes. |
| 2 | **Set the permission mode** | Measured live 2026-08-02: `permission-mode-state.sh` returns `BLOCKING\|auto`. #320's Phase M fence aborts the run before Phase P writes anything. Human keystroke, not a code change — `/permissions` does **not** set it. | Two Shift+Tab to `acceptEdits`, or launch with `--permission-mode acceptEdits`. Phase M returns non-blocking. |
| 3 | **File the two disclosed follow-ups** — done 2026-08-02, **#335** and **#336** | Both were recorded in an ADR's own "recorded, not fixed" section and neither had an issue, which is precisely the shape §10 exists to close — a backlog at the end of a document is an invisible backlog. | #335: `manifest-transition.sh` does not refuse a manifest terminal by `status` (ADR-0113). #336: `set-branch-protection.sh` still unions exactly one context, so the audit derives what it cannot enforce (ADR-0114). Both `prep`, appended to wave 2. |
| 4 | **The launch** | The exit criterion is a run, not a PR. Everything above is a precondition for it and none of it is evidence about it. | At least one `NIGHTLY-PUBLISH` line. Phase 10 wave 1 does not start before that. |

**One repo-admin action is not on the path, and is worth doing anyway.** `shell-tests` — the job that
runs the whole harness and the plant registry — is **not a required check on `main`**. The new audit
reports it as `not-required:` on every run, and `main` requires `markdownlint`, `links` and `ci`
without it. Making it required is a click in branch protection, not a code change, and until it
happens the merge gate this repository's whole discipline rests on does not include the harness.

**What is deliberately not on this path.** The second shakedown (§9.4) stays a separate run:
`hook_verified` is still `false`, so nothing has ever taken the Workflow dispatch path, and a green
Phase 10 exercises the Agent-batch path only. Do not read the launch above as covering it.

### Phase 10 — total review closure, executed unattended

Phase 9 left one open GitHub issue. The repository's actual backlog was somewhere else: a sweep of
all 111 ADRs found **191 genuinely-open residual items** — 68 SAFETY, 72 CORRECTNESS, 51 DOC —
recorded deliberately under headings like *"Known consequences, recorded rather than fixed"*,
*"disclosed, not fixed"*, *"instruction, not an enforcement"*. Fourteen more turned out to have been
closed by a later ADR without the earlier one being updated. That backlog lives at the end of a
hundred documents, which is exactly where it stays invisible — the same shape as §9's own finding
about four ADRs disclosing a gap none of them had counted.

This phase turns the actionable part into GitHub issues labelled `prep` and runs them unattended
through `nightly-autopilot` → `project-conductor nightly` → `concept-to-code`, one feature per
issue, each ending in a pushed branch and an open PR. **The remainder is closed by one decision ADR,
not by pretending it will be fixed.**

#### What is deliberately NOT a feature

Named here so a green run is not read as covering it.

- **§9.4, the second shakedown.** `hook_verified` is still `false`; no run has ever taken the
  Workflow dispatch path. It is a run, not a feature, and a green Phase 10 exercises the Agent-batch
  path only.
- **Items whose own ADR argues the fix is worse than the residual.** The threat-model bypasses in
  ADR-0045/0074/0079 are pinned as *expected-ALLOW* by their own tests: `subprocess.run(["git",
  "push"])`, `lua -e "os.execute(…)"` and variable splicing defeat a command-position guard by
  construction. Closing them means building a sandbox, which is a different system.
- **The 51 DOC-class items** — stale counts, prose-vs-tree drift, cost notes. Wave 3's decision ADR
  disposes of them in one place.
- **The run's own machinery** — `project-conductor`, `nightly-autopilot`, `publish-feature.sh`,
  `nightly-guard.sh`. Nothing in this roadmap edits what is executing it.

#### Ordering, and why it is load-bearing

**7 of 9 failure conditions halt the ENTIRE roadmap** — a weakening-scan finding, a RED suite, an
RTF BLOCKER, a merge conflict or base-fork mismatch, a spec-coverage `MALFORMED`, a Step 1
spec-archive `COLLISION`, a manifest that does not resolve. Only a thin issue body and an
injection-shaped title skip one feature and continue. So the roadmap runs **low-risk first**: a
night that halts has already produced PRs.

- **Wave 1 — LOW.** Single file, mechanical, no live-guardrail behaviour change.
- **Wave 2 — MED.** Shared scripts with multiple live callers, and the guard populations.
- **Wave 3 — HIGH.** Detector precision (needs measurement before design) and the decisions.

#### Two facts about the run, measured rather than assumed

- **Branches stack.** `publish-feature.sh:73` cuts each branch from current HEAD and nothing returns
  to `main`; `commit/SKILL.md:369` reuses the branch it is on. This is known behaviour, not a
  defect — the 2026-07-10 run's own report states it in its merge instructions and 13 features
  merged in order without incident. It is why waves are capped at ~12 with a morning merge between
  them, and it composes badly with §8.8's finding that ten of Phase 8's fifteen fixes landed in
  `concept-to-code/SKILL.md` alone.
- **The run never waits for CI.** `publish-feature.sh:110` hardcodes `CI=pending` and Phase 2 does a
  single `gh pr checks` pass after the whole roadmap. `main` requires three checks while pre-flight
  check 8 verifies one. Morning verification is human, and no harness executes `SKILL.md` prose at
  all.

#### Features

Generated from the `prep`-labelled issues by `roadmap-from-issues.sh`. One issue, one feature, in
wave order.
##### Wave 1 — LOW: single file, mechanical, no live-guardrail behaviour change

- [x] the sixth bare manifest-set-flag.sh mention was left when the other five were fixed  (issue #286)  (completed: 2026-08-02)
- [x] RTF's gitignore glob and this repo's own entry differ by a dash  (issue #287)  (completed: 2026-08-02)
- [ ] the Express path says No worktree isolation and the Italian guide says the opposite  (issue #288)
- [ ] the transition-pair count is stated in three files and derived in one  (issue #289)
- [ ] one real plan shape is recognised by no task predicate  (issue #290)
- [ ] a bold-wrapped requirement id is invisible to both the checker and the repairer  (issue #291)
- [ ] the value-domain guard covers step5_mode only  (issue #292)
- [ ] task_num extracts digits only so a lettered task collides with its sibling  (issue #293)
- [ ] plan-tasks.sh has two modes with opposite failure directions and nothing stops a caller picking the wrong one  (issue #294)
- [ ] MALFORMED is dropped silently by any caller filtering BUDGET or SCOPE  (issue #295)
- [ ] a per-file budget ceiling is parsed and then summed so one file can exceed its own  (issue #296)
- [ ] the dirty-classify fence reads porcelain v1 so a renamed artifact classifies as OTHER  (issue #297)

##### Wave 2 — MED: shared scripts with multiple live callers, and the guard populations

- [ ] the collapsed snapshot commits live in the reflog only and a git gc destroys them  (issue #298)
- [ ] fence_is_abort_capable is lexical and four measured fences abort from outside it  (issue #299)
- [ ] a producer is any line that mentions the target so a target only talked about looks produced  (issue #300)
- [ ] the transcript-scan population stops at two roots  (issue #301)
- [ ] the grant-coverage guard matches a bare Bash token so an unrestricted grant in another form passes  (issue #302)
- [ ] the interpreter enumeration is a fixed list and the escapes are pinned nowhere  (issue #303)
- [ ] the reason floor is duplicated in seven derived guards and nothing stops one drifting  (issue #304)
- [ ] the plant registry cannot express an insertion  (issue #305)
- [ ] the deployed-only registry's reasons are true today and checked by nothing  (issue #306)
- [ ] hooks.json is outside PAIRS completeness by a deferred decision  (issue #307)
- [ ] thirteen skill-private test runners exercise the deployed copy and are dark to CI  (issue #308)
- [ ] settings.json is never synced and five guardrail hooks are wired by hand  (issue #309)
- [ ] an undefined assertion helper is indistinguishable from a passing assertion  (issue #310)
- [ ] a manifest terminal by status is exempt from invariant 4 and the state machine still lets it transition  (issue #335)
- [ ] set-branch-protection.sh unions one context while the audit derives three  (issue #336)

##### Wave 3 — HIGH: detector precision, and the decisions

- [ ] the weakening scan is blind to an in-place assertion edit  (issue #311)
- [ ] spec-coverage measures citation not implementation  (issue #312)
- [ ] spec-coverage is wholly inert for a SPEC whose criteria sit under an unrecognised heading  (issue #313)
- [ ] literal-assertion-added shipped disabled at 25 percent precision and nothing has re-measured it  (issue #314)
- [ ] The Step 5 checkpoint has no mechanism to tell an expected red from a real one  (issue #273)
- [ ] seventeen ADRs carry the same instruction-not-an-enforcement paragraph and the class is undecided  (issue #315)
