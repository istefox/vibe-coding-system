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

**It produced twenty-one findings. Three were fixed because they blocked; seventeen are open and
are Phase 8.** The count matters more than any single defect: everything from Phase 4 onward was
preventive work verified against planted defects, which proves a guard fires and proves nothing
about the chain it guards. One real run found more than four phases of inspection.

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

- [ ] **#239 — Step 5.0.1 can never pass.** The chain writes the manifest after Gate 4.0 commits it,
  on both Gate 4 branches; the fresh-session branch is worse, because Form B resume writes it
  unconditionally. "The working tree is clean" and "the manifest is written at every state change"
  are flatly incompatible requirements on the same file. The structural one — do it first.
- [ ] **#248 — `step_5_implementation` has no producer on the default path.** Every occurrence of the
  transition lives inside Step 4.5's tracer-bullet block, which is off by default, so Step 5 cannot
  reach Step 6. Same class as #239 and the same stretch of the chain: one pass over Gate 4 → Step 6.
- [ ] **#234 — Gate 4.0 cannot stage untracked artifacts.** Upstream of #239: without it Gate 4.0
  produces nothing for #239's fix to preserve.

#### 8.2 — The chain can destroy work

- [ ] **#245 — `isolation: worktree` is a CWD convention, not a sandbox.** An absolute path writes
  into the shared checkout; the three scope hooks all constrain *which files*, never *which tree*.
  The coder's dispatch brief hands it four absolute paths in its first four lines. Three candidate
  fixes with very different blast radii — do not bundle it with anything.
- [ ] **#228 — Step 1 overwrites a root `SPEC.md` belonging to another topic.** `gate0-detect.sh`
  already reports `spec_topic_match=false` and the detection protects nothing. Destroys a
  human-reviewed artifact.

#### 8.3 — What a gate shows, and what it records

- [ ] **#237 — Gate 4 conflates *where* with *how*.** Four cells, two offered, and no attended
  same-session path.
- [ ] **#227 — Gate 0 shows two contradictory `Recommended` markers.** Same defect class as #237 in a
  different gate; #227's own body says the two may want one answer. Design them together.
- [ ] **#238 — the `hitl_gates` trail is written by nobody and has no slot for Gate 4.** Depends on
  #237: the slot's shape follows what Gate 4 becomes.

#### 8.4 — Batching

- [ ] **#242 — the `>=6` threshold consumes a count ADR-0069 documents as not a task count.** 38
  versus 7 on the shakedown's own plan.
- [ ] **#247 — the two batch-boundary rules can conflict, and a checkpoint can be legitimately RED.**
  A correction to ADR-0088 §D5, written during the run. If its fix introduces a plan-declared
  "expected red", it consumes the same parsing #242 needs — so pair them.

#### 8.5 — Recovery and history

- [ ] **#244 — `recovery_baseline_sha` is not rebase-safe**, and a paused chain all but forces a
  rebase. Do this first: it is #249's target.
- [ ] **#249 — Step 7's commit describes nothing.** The merge-back already committed the feature as
  `chore(step5): snapshot … worktree`. The cheapest fix is a soft-reset to the baseline, which is
  why #244 comes first.

#### 8.6 — Half-read forms and stale records

Independent of each other and of everything above; no ordering constraint.

- [ ] **#246 — a per-file `Budget:` line is half-parsed** into a false SCOPE and a false BUDGET
  instead of being treated as absent. Fourth instance of the near-miss class.
- [ ] **#240 — `step5_mode` documents `agent_fallback`**, which nothing has ever written; 17
  manifests carry `agent_batch`.
- [ ] **#232 — `detect-macos.sh` fires on the skill name `macos-ux`** and on a Stack line naming the
  host platform, so every meta-SPEC in this repository trips Gate 1c.
- [ ] **#233 — Gate 2b asks to authorise a test-cmd that is already SHA-pinned.** The autopilot
  branch has the read-only probe; the attended one does not.
- [ ] **#250 — RTF gitignores its state file by branch name**, so `.gitignore` grows one dead line
  per branch. One glob fixes it permanently.

#### What Phase 8 must not become

- **A second inspection phase.** Sixteen of these seventeen were found by running the chain, not by
  reading it. Each fix needs the same treatment: an assertion seen RED, and where the fix is prose,
  an executed premise rather than a claim.
- **A phase that re-derives the same guard six times.** #239, #248 and #238 are one class
  (ADR-0086's criterion applies: would two copies giving different answers be a defect?). A derived
  check over `manifest-transition.sh`'s legal pairs against their call sites would close it once —
  and would be instance eight of the derived-guard pattern.
- **A run of its own without a second shakedown.** Phase 8's own product is only verified by another
  end-to-end run, which is also what feeds ADR-0080's still-unfed condition.
