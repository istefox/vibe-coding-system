# Project: vibe-coding-system

## Overview
Auto-generated roadmap from issues labeled `prep` (ADR-0023).

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

- [ ] **#194 phase 2 — read the measurement, then decide** keep / drop / accept, and record the
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
#197 (PR #202, ADR-0078), #196 (PR #203, ADR-0079).

**#194 phase 2 is blocked on data, by design.** The `src=` instrumentation deployed at ~20:15 CEST
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
