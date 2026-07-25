# Integration report — external agentic spec vs. this vibe-coding system

Audit of `docs/books/20260725_VibeCoding_AgenticSystemSpec_v1_1.md` (3767 lines, sections 0–15)
against the system described in `CLAUDE.md`, `docs/vibe-coding-system.md`, ADR-0001…ADR-0045 and
the executable surface under `staging/plugin/`.

---

## 1. Scope and method

Read in full: the spec, sections 0–15, in sequential chunks. Read in full: `CLAUDE.md`,
`.claude/context.md`, all 8 agent files, all hook scripts under `staging/plugin/scripts/`,
`staging/user/settings.json` (hook wiring), `staging/user/rules/`, and the SKILL.md of
`review-triage-fix`, `refactor-snapshot`, `deep-refactor`, `code-review-checklist`,
`interview-driver`, `spec-from-issue`, `commit`, plus the dispatch and gate sections of
`concept-to-code`. Read partially: `docs/vibe-coding-system.md` (§1, §2, §7), ADR titles plus the
Decision block of ADR-0009/0012/0013/0014/0021/0037 and the CLAUDE.md decision log for the rest.
Not read: the two source books; the full text of the 20 skills not listed above; the `tests/`
harnesses beyond their CI registration.

Where documentation and executable surface disagree, the entry says so and treats the executable
surface as what exists.

### Terminology mapping (stated once)

| Spec term | This system |
|---|---|
| Orchestrator agent | the main CLI session ("orchestrator") |
| Generator | `coder` agent |
| Verifier | `tester` agent (defined, never dispatched — see G-01) |
| Spec agent | `interview-driver` skill / `spec-from-issue` |
| Architect agent | `architect` agent |
| Cleanup agent | `auto-format.sh` + `refactorer` + `deep-refactor` |
| Gate G0…G13, detector D1…D12 | no equivalent naming; hooks + skill steps |
| Human gate H1…H20 | HITL gates: c2c Gate 0…5.6, `commit` Step 4 / Step 7 |
| `AGENTS.md` / `ai-rules/` tiers | `~/.claude/CLAUDE.md` + project `CLAUDE.md` + `.claude/rules/` |
| Task graph node | plan task in `docs/superpowers/plans/` + manifest |
| Fleet command post | `vibe-status` skill + `nightly-report.json` |

---

## 2. Coverage ledger

One row per spec sub-section. `no actionable delta` means the capability is either already covered,
or is a framing statement with nothing to implement.

| § | Topic | Outcome |
|---|---|---|
| 0.1 | Purpose | no actionable delta |
| 0.2 | Citation convention (verified vs assumed) | no actionable delta — same discipline in `CLAUDE.md` |
| 0.3 | Deterministic layer before agent layer | G-11 |
| 0.4 | Source inventory | no actionable delta |
| 1.1 | Definitions | no actionable delta |
| 1.2 | FAAFO, optionality, NK/t | no actionable delta |
| 1.3 | Four governing laws | G-02 (Law 4), G-17 (Law 2) |
| 1.4 | Prevent → Detect → Correct, recovery-first ordering | G-13 |
| 1.5 | Three loops | no actionable delta |
| 1.6 | Three-layer wiring model | no actionable delta |
| 1.7 | Three pillars | no actionable delta |
| 2.1 | Topology | no actionable delta |
| 2.2 | Agent roster and role contracts | G-01 |
| 2.3 | Generator/verifier separation | G-01 |
| 2.4 | Multi-model routing policy | NOT adopted #1 |
| 2.5 | Isolation and workspace partitioning | no actionable delta (worktree); NOT adopted #5 (containers) |
| 2.6 | Concurrency model and supervision span | no actionable delta (cap 4, blueprint §2.3); G-23 for the metrics half |
| 2.7 | The human gates H1–H20 | G-24 |
| 3.1 | Context physics | G-19 |
| 3.2 | Derived requirements C1–C6 | G-19 |
| 3.3 | Rules hierarchy, three tiers | no actionable delta (`claude-md-slim`, `.claude/rules/`) |
| 3.4 | Durable memory / Memento method | no actionable delta (`session-context-inject.sh`, manifests, ADR-0021) |
| 3.5 | Focused vs comprehensive context | no actionable delta |
| 3.6 | Payload manifest | no actionable delta |
| 3.7 | Retrieval — RAG vs agentic search | NOT adopted #6 |
| 3.8 | Design for AI manufacturing | G-09 |
| 4.1 | Capability envelope, the 70% problem | G-12 |
| 4.2 | Prompt pattern catalog + prompt library | no actionable delta (`prompt-builder`, skills-as-library) |
| 4.3 | Iterative refinement loop | no actionable delta |
| 4.4 | Task graph, leaf sizing, tracer bullets | G-18 |
| 4.5 | Delegation framework (Grove's five factors) | G-22 |
| 4.6 | Watching, interrogating, taking back the wheel | G-23 |
| 4.7 | Tool access as capability multiplier | no actionable delta (MCP set, blueprint §9) |
| 4.8 | Tool-selection policy | no actionable delta |
| 5.1 | Why the deterministic layer exists | G-11 |
| 5.2 | Gate catalog G0–G12 | G-06, G-09, G-10, G-13, G-14 |
| 5.3 | Reward-hacking detectors D1–D12 | G-02, G-03, G-07, G-08, G-15, G-16, G-19 |
| 5.4 | Security vulnerability register | G-14 |
| 5.5 | Performance and resource gates | no actionable delta (`deep-refactor` perf dimension) |
| 5.6 | Checkpoint, rollback, recovery | G-13 |
| 5.7 | Minimality and anti-sprawl | G-09 |
| 5.8 | Workflow automation as a subsystem | no actionable delta (this repo is that subsystem) |
| 5.9 | Audit depth proportional (risk × familiarity) | G-12 |
| 5.10 | Determinism boundary table | G-05, G-11 |
| 6.1 | P0 intake and product validation | NOT adopted #3 |
| 6.2 | P1 architecture and ADR | no actionable delta (c2c Step 2, `adr-writer`) |
| 6.3 | P2 specification and test plan | G-04 |
| 6.4 | P3 tracer bullet | G-18 |
| 6.5 | P4 build (inner loop) | G-01, G-17 |
| 6.6 | P5 review | no actionable delta (`review-triage-fix`) |
| 6.7 | P6 prototype→production promotion | no actionable delta — Gate 0 `chain_path` picks the mode up front; promotion is a manual re-run |
| 6.8 | P7 security audit | G-14 |
| 6.9 | P8 integration (middle loop) | no actionable delta |
| 6.10 | P9 release | no actionable delta (`commit` Step 6–7, `set-branch-protection.sh`) |
| 6.11 | P10 operate | NOT adopted #7 |
| 6.12 | P11 GTM and feedback | NOT adopted #3 |
| 6.13 | Phase-to-loop mapping | no actionable delta |
| 7 | Failure mode register (cases 1–14 + pattern register) | G-02, G-07, G-19, G-20, G-21 |
| 8.1 | The DORA anomaly | no actionable delta — it is the rationale, already honoured |
| 8.2 | DORA definitions and targets | NOT adopted #8 |
| 8.3 | Enterprise evidence | NOT-APPLICABLE — single operator |
| 8.4 | Constraint tracking | G-23 |
| 8.5 | Agent-level instrumentation | G-23 |
| 8.6 | Productivity claims | no actionable delta — the spec's own instruction is "don't" |
| 9.1 | The collaborative cookbook | no actionable delta |
| 9.2 | The twelve golden rules | no actionable delta (`~/.claude/CLAUDE.md`) |
| 9.3 | Five named agent practices | G-22 |
| 9.4 | Loop conclusion checklists | no actionable delta |
| 9.5 | Ownership contract | NOT adopted #2 |
| 9.6 | IP, licence, attribution, bias | G-25 |
| 9.7 | Roles and skills | NOT-APPLICABLE — team-scale |
| 9.8 | Adoption | NOT-APPLICABLE — team-scale |

### §§10–15 (read, folded in)

| § | Topic | Outcome |
|---|---|---|
| 10.1–10.7 | Claude Code binding (layout, CLAUDE.md, subagents, hooks, commands, MCP, worktrees) | binding layer — compared against ours throughout; NOT adopted #9 for `AGENTS.md`; G-11 for the two hook design rules |
| 11.1–11.15 | Prompt library | no actionable delta |
| 12 | Build order | no actionable delta — informs the shortlist ordering in §6 |
| 13 | Declared gaps G-1…G-14 | G-20 (prompt injection), G-23 (productivity), rest NOT-APPLICABLE |
| 14 | Source index | no actionable delta |
| 15.1 | Operator persona / reviewer authority | NOT-APPLICABLE — single operator, single authority level |
| 15.2 | `task_type` as third gate axis | G-12 |
| 15.3 | Design/visual input, accessibility and i18n gates | G-26 |
| 15.4 | External dependency feasibility (G13) | G-21 |
| 15.5 | AI-assisted project management | NOT adopted #10 |
| 15.6 | Autonomous maintenance behaviours | NOT adopted #11 |
| 15.7 | Per-action approval granularity L0/L1/L2 | no actionable delta — permission modes + `autopilot` flag already span L1/L2 |
| 15.8 | Integration standards beyond MCP | no actionable delta |
| 15.9 | Hidden innovators | NOT-APPLICABLE |
| 15.10 | Evidence for the black-box quadrant | G-12 |
| 15.11 | Prototyping tool registry | no actionable delta |
| 15.12 | Concrete full-stack build sequence | no actionable delta |
| 15.13 | Changes from v1.0 | no actionable delta |

---

## 3. Deterministic debugging and failure containment

Three structural weaknesses, in the order I would defend them.

**First: the entity that writes the code is the entity that certifies it.** The spec calls
generator/verifier separation "the single most important structural decision" (§2.3) and gives the
mechanism: an agent asked to both implement and prove its implementation optimises for the
appearance of proof. We have a `tester` agent file, and no orchestration skill ever dispatches it —
`concept-to-code`, `review-triage-fix`, `deep-refactor` and `autopilot-build` mention `tester`
exactly once between them, in an effort-pinning table. The coder writes the tests it will be judged
by, under a TDD instruction. Every detector the spec places downstream of that split is therefore
guarding a split we do not have.

**Second: a green test suite is our accept decision.** `stop-gate.sh` runs the project test command
itself and unblocks on exit 0. That is the spec's D6 (claim verification) implemented properly and
it is genuinely good. But §5.3 exists precisely for what passes tests: disabled tests, hardcoded
expectations, zero-assertion tests, silently omitted requirements. Of detectors D1–D12 we have one,
`weakening-scan.sh`, and it fires only inside `review-triage-fix`, which a human invokes by hand.
The unattended paths — `autopilot-build`, `nightly-autopilot` — run to a commit and a pushed PR
with no detector between the green suite and the branch.

**Third: our gates are fail-open hooks that live inside the agent harness.** The spec's two hook
design rules (§10.4) are "every hook must work with no agent present" and "fail closed". We do the
opposite on both, deliberately in the second case and by omission in the first: the guardrails are
`~/.claude/hooks/*` wired in `settings.json`, none of them runs in a target project's CI, and each
one exits 0 on internal error. That is defensible for a guardrail; it means the deterministic layer
is advisory the moment anything runs outside a Claude Code session.

---

### G-01 — Generator/verifier separation (spec §2.3, §2.2.5, §6.5 step 2)
**Status:** ABSENT
**Our evidence:** `staging/plugin/agents/tester.md:1` defines the agent; its only mention across the four dispatching skills
is `concept-to-code/SKILL.md:625`, an effort-table row. The coder does its own TDD (`concept-to-code/SKILL.md:754`) and
nothing forbids it writing under a test directory.
**Gap:** the generator certifies itself. Blueprint §2 lists `tester` in the roster, so documentation and executable surface
disagree — the roster is aspirational, the dispatch graph is what runs.
**Proposal:** in c2c Step 5, dispatch `tester` per task group *before* the coder, briefed from the SPEC and not the
implementation; deny `coder` writes under test paths with a `PreToolUse` hook modelled on `write-scope-enforce.sh`, which
already reads `agent_type` and a scope line from the dispatch.
**Enforcement layer:** skill (c2c Step 5 + fallback path) + hook (PreToolUse `Edit|Write`) + CI test in both registries
**Priority:** P1 | **Effort:** L | **Risk:** medium — doubles dispatches per task, extends the `step5-report.json` schema,
and a tester blind to the implementation writes weaker tests before better ones
**Conflicts with:** none — ADR-0039 D5 already put a review stage at this insertion point, so nothing is superseded
**Candidate artifact:** new ADR + issue

### G-02 — Test-inventory delta and anti-weakening outside RTF (spec §5.3 D1, §7 case 1)
**Status:** PARTIAL
**Our evidence:** `staging/plugin/skills/review-triage-fix/scripts/weakening-scan.sh:1-10` detects deleted test files, added
skip/xfail, and net assertion removal; wired only at `review-triage-fix/SKILL.md:205`, enforced by CIRCUIT BREAKER B at
`:215`, and called by no other skill — not `concept-to-code`, `autopilot-build`, `nightly-autopilot` or `deep-refactor`.
**Gap:** the detector covers the failure the spec names first, and every unattended path bypasses it. `~/.claude/CLAUDE.md`
forbids disabling a test at prompt level only.
**Proposal:** call `weakening-scan.sh` over the cumulative diff at the end of c2c Step 5, at every `autopilot-build` and
`nightly-autopilot` checkpoint, and in `commit` Step 1 beside the secrets check; a `WEAKENED` line becomes a blocking
finding, not a note.
**Enforcement layer:** skill (c2c Step 5, autopilot, commit Step 1) + CI test in both registries
**Priority:** P1 | **Effort:** M | **Risk:** low — the script is report-only and already tested; false positives on a
legitimate test deletion are surfaced, not acted on
**Conflicts with:** none
**Candidate artifact:** issue (no new ADR — ADR-0018's report-only philosophy already covers it)

### G-03 — Hardcoded-value and assertion-meaningfulness detectors (spec §5.3 D3, D4)
**Status:** ABSENT
**Our evidence:** `staging/plugin/scripts/post-write-check.sh:14` is syntax-only by decision; `weakening-scan.sh` counts
assertions but only net-negative deltas; `reviewer.md` covers test quality by eye under "Tests: coverage of the changed
behavior".
**Gap:** nothing flags a diff changing implementation and test expectation in the same commit, a test whose only assertion
is a mock call-count, or a zero-assertion test — the "cardboard muffin" class the spec documents with a 4-of-9 hit rate.
**Proposal:** two new report lines in `weakening-scan.sh` — `SUSPECT literal-assertion-added` when a test and its
implementation change together and a literal-valued assertion appears, and `SUSPECT zero-assertion-test` for an added test
function with no assertion token. Report-only, same contract.
**Enforcement layer:** CI test in both registries + skill (same call sites as G-02)
**Priority:** P2 | **Effort:** M | **Risk:** medium — heuristic, and parameterised tests will false-positive; report-only
keeps that cheap
**Conflicts with:** none
**Candidate artifact:** issue

### G-04 — Requirement IDs and the completion check (spec §5.3 D7, §6.3)
**Status:** ABSENT
**Our evidence:** `staging/plugin/skills/interview-driver/SKILL.md:13` names the SPEC sections (objectives, scope, stack, …,
success criteria) with no requirement identifiers, and `spec-from-issue/SKILL.md:15` inherits that structure.
`manifest-validate.sh` invariants 0–14 check schema and gate counts, never requirement coverage.
**Gap:** with no enumerated requirement list, nothing can assert every requested item was delivered and tested; the spec's
"counting your babies" gate is unimplementable here, and a silent omission in an unattended run reaches a PR unremarked.
**Proposal:** require `R-01…R-nn` IDs in the SPEC's success-criteria section (both generators); plan tasks cite the IDs they
satisfy; a `spec-coverage.sh` asserts every ID reaches at least one plan task and one test name before Step 6 closes.
**Enforcement layer:** skill (interview-driver, spec-from-issue, c2c Step 5 exit) + CI test
**Priority:** P1 | **Effort:** L | **Risk:** medium — retrofits a SPEC contract four skills depend on; the check must be
conditional on IDs being present so old SPECs stay valid
**Conflicts with:** none — `spec-issue-gate.sh` (ADR-0023) refuses to fabricate requirements; IDs make that refusal
checkable
**Candidate artifact:** new ADR + issue

### G-05 — Claim verification (spec §5.3 D6, §5.10)
**Status:** PRESENT
**Our evidence:** `staging/plugin/scripts/stop-gate.sh:113` blocks the Stop event on a real, harness-executed test run with
the failing output fed back as context; `review-triage-fix/SKILL.md:201` ("do not trust the agent's self-report for the
breakers") and its no-op detection at `:199`; `deep-refactor/SKILL.md:410` records agent no-ops rather than believing the
report.
**Gap:** none material. The one residue is that `stop-gate.sh` fails open on a missing/timed-out test command, so a project
with a broken `test-cmd` silently loses the check.
**Proposal:** none — keep as is. The fail-open residue is covered by G-11.
**Enforcement layer:** already hook (Stop) + skill (RTF, deep-refactor)
**Priority:** — (no action) | **Effort:** — | **Risk:** —
**Conflicts with:** none
**Candidate artifact:** none

### G-06 — Secrets, dependencies and supply chain (spec §5.2 G9, §5.4)
**Status:** PARTIAL
**Our evidence:** `staging/plugin/scripts/protect-files.sh:6` blocks writes to paths matching `.env`, `secrets`, `.pem`,
`.key`, `credentials`; `commit/SKILL.md:70` runs a secrets check over staged ∪ modified ∪ untracked — both
**filename-based**. `clean-public-repo/SKILL.md:150` uses `gitleaks` when installed, on the publish path only.
**Gap:** a key hardcoded inside a `.py` or `.ts` file passes every check we have. No dependency audit, no lockfile-diff gate
for a new dependency, no package-existence check against the registry — the spec's named supply-chain surface, attackers
squatting hallucinated package names.
**Proposal:** content-based secret scan (entropy + provider key patterns) in `commit` Step 1 as a blocking finding, reusing
the `clean-public-repo` rules; a lockfile-diff check that any new dependency was named in the plan; ship both as steps in
the `ci.yml` project template.
**Enforcement layer:** skill (commit Step 1) + CI test in both registries + blueprint text (ci template)
**Priority:** P1 | **Effort:** M | **Risk:** low — additive, report-then-block, detection rules already vendored
**Conflicts with:** none
**Candidate artifact:** new ADR + issue

### G-07 — Deleted-symbol watch (spec §5.3 D2, §7 case 1)
**Status:** ABSENT
**Our evidence:** `staging/plugin/agents/coder.md:39` requires `PATTERN: REMOVE | <path> | Callers checked: <list>`;
`pre-flight-pattern-enforce.sh` validates that the header exists in canonical form and nothing about its truth.
`reviewer.md` reads the diff afterwards.
**Gap:** a coder can delete an exported function and satisfy the hook by asserting callers were checked. The spec's case is
a silent deletion found four days later.
**Proposal:** a diff-level check that any removed public symbol (exported function, route, public class) is either named in
the plan task or accompanied by a zero-hit `rg` result in the report; same call sites as G-02.
**Enforcement layer:** CI test + skill (same call sites as G-02)
**Priority:** P2 | **Effort:** M | **Risk:** medium — "public symbol" is language-specific and the check will be shallow
outside Python/TS/Swift
**Conflicts with:** ADR-0001 §PATTERN classifier — this does not supersede it; it verifies the claim the classifier makes
**Candidate artifact:** issue

### G-08 — Swallowed errors and happy-path-only code (spec §5.3 D5)
**Status:** ABSENT
**Our evidence:** `post-write-check.sh:14` is syntax-only; `reviewer.md` lists "error handling" under Correctness, by eye,
subject to its confidence filter (≥75 to report).
**Gap:** no mechanical detection of an empty catch block, a catch with neither log nor rethrow, or a new public function
with no error path. The spec's third pillar of real verification is "ensure that error handling handles errors".
**Proposal:** add an `EMPTY-CATCH` / `SWALLOWED-ERROR` pass to the same diff scanner as G-03, report-only, language-gated to
the four stacks in `staging/user/rules/`.
**Enforcement layer:** CI test + skill (same call sites as G-02)
**Priority:** P3 | **Effort:** S | **Risk:** low
**Conflicts with:** ADR-0039 D4 — that decision removed *linters* from the write-time hook for determinism; a diff-scoped
grep in the review path is a different layer and does not reopen it
**Candidate artifact:** issue

### G-09 — Diff sprawl, line budget, new files and new dependencies (spec §5.2 G7, §5.7, §3.8)
**Status:** PARTIAL
**Our evidence:** `deep-refactor/SKILL.md:46` treats files >400 lines and functions >60 lines as *findings* of a
whole-codebase audit, not gates on a diff; `write-scope-enforce.sh` bounds Step 6 Phase 3 fix agents to one assigned file;
`review-triage-fix/SKILL.md:156` caps coder dispatches at 4 per cycle; `coder.md:75` says "no new dependencies unless the
plan calls for them", at prompt level.
**Gap:** nothing bounds a single coder's diff — files touched, lines changed, files created — against the plan's declared
scope. The spec makes microscopic batch size non-negotiable because it is what keeps human review physically possible.
**Proposal:** a per-task budget in the plan (files, ±lines), asserted at each c2c Step 5 checkpoint against `git diff
--stat`; over-budget surfaces to the user rather than blocking.
**Enforcement layer:** skill (c2c Step 5 checkpoint) + manifest field
**Priority:** P2 | **Effort:** M | **Risk:** medium — a budget that is wrong more often than the coder is will get ignored,
which is worse than not having it
**Conflicts with:** none
**Candidate artifact:** issue

### G-10 — Interface immutability / API non-destruction (spec §5.2 G8)
**Status:** ABSENT
**Our evidence:** no `protected-interfaces` list anywhere in `staging/`; the closest is `goal-loop/SKILL.md:59`, which
offers "public API" as a free-text constraint in a prompt template. `agent-write-scope.sh` and `write-scope-enforce.sh`
restrict *paths*, never signatures.
**Gap:** the spec ranks API breakage first in the outer-loop Prevent ordering. We have no declared protected surface and no
check that a diff preserves it. For a docs-and-scripts repo this is near-theoretical; for the target projects the system
builds it is not.
**Proposal:** an optional `.claude/protected-interfaces` file (one signature or path glob per line), checked against the
diff before Step 6 closes; absent file means the check is inert.
**Enforcement layer:** skill (c2c Step 6) + CI test
**Priority:** P2 | **Effort:** M | **Risk:** low — inert by construction when the file is absent, the same design that keeps
`write-scope-enforce.sh` harmless outside its one call site
**Conflicts with:** none
**Candidate artifact:** issue

### G-11 — Fail-open gates that only exist inside the agent harness (spec §10.4, §5.1, §0.3)
**Status:** DIVERGENT-BY-DECISION (fail-open) + PARTIAL (harness-only)
**Our evidence:** `stop-gate.sh:4` ("never block on internal error (fail-open)"); `pre-flight-pattern-enforce.sh:5` and
`:135`; `agent-command-scope.sh:11` ("a guardrail … NOT a sandbox"); `db-backup-guardrail.sh:5` fails open on infra error,
closed only after a match. CI runs the harnesses (`.github/workflows/docs-ci.yml:44`), never the gates against a diff, and
`staging/project-templates/ci/ci.yml` contains one step, `__TEST_CMD__`.
**Gap:** the spec's rule is fail-closed and agent-independent. Our fail-open posture is a recorded decision (ADR-0004,
ADR-0034, ADR-0045) worth keeping; the harness-only half is not a decision — a target project inherits no gate in its own CI.
**Proposal:** keep fail-open; extend the `ci.yml` template with the diff-scoped checks from G-02/G-03/G-06 as ordinary
scripts, so a target repo's CI enforces them with no agent present.
**Enforcement layer:** blueprint text (`staging/project-templates/ci/ci.yml`) + CI test
**Priority:** P2 | **Effort:** M | **Risk:** low
**Conflicts with:** ADR-0034 and ADR-0045 set the fail-open contract deliberately; this supersedes neither — it adds a
second, fail-closed copy in CI where blocking is safe
**Candidate artifact:** new ADR + issue

### G-12 — Proportional audit depth: risk × familiarity × task_type (spec §5.9, §15.2, §15.10)
**Status:** ABSENT
**Our evidence:** Gate 0 routes on `chain_path` (express / hybrid / standard / autopilot),
`concept-to-code/SKILL.md:1216-1223`, whose stated criteria are file count and layer count — a *size* axis. `deep-refactor`
tags findings `risk_level: high|low`, which governs fixability, not audit depth. No task or manifest field carries risk,
familiarity, or task type.
**Gap:** a 3-file change to payment code and a 3-file change to a README route identically. The spec makes the gate profile
a function of risk, of how well the operator knows the stack, and (§15.2) of task type, strictest axis winning.
**Proposal:** add `risk` and `task_type` to the manifest (additive, defaulting to the strict profile when unset, as the spec
instructs); Gate 2 sets them; Step 5/6 pick review depth from `max()` of the axes.
**Enforcement layer:** manifest field + skill (c2c Gate 2, Step 6) + CI test
**Priority:** P2 | **Effort:** L | **Risk:** medium — a third routing axis on top of `chain_path` risks a combinatorial gate
matrix nobody can hold in their head
**Conflicts with:** ADR-0017 owns chain routing; this extends it and must be reconciled there
**Candidate artifact:** new ADR + issue

### G-13 — Recovery-readiness pre-flight (spec §5.2 G0, §5.6, §1.4)
**Status:** PARTIAL
**Our evidence:** `deep-refactor/SKILL.md:118` records a baseline commit hash and `:173` checks for a dirty tree;
`review-triage-fix/SKILL.md:158` has the stale-worktree pre-check; `autopilot-build` runs eight pre-flight checks including
git-repo presence.
**Gap:** c2c standard Step 5 has no G0 equivalent — no assertion that the tree is clean, that a checkpoint exists, or that
the branch is pushed, before dispatching coders. The spec puts recovery readiness *first* in the Prevent ordering: "you need
to be sure you can recover before taking risks".
**Proposal:** one pre-dispatch block in c2c Step 5 asserting clean-or-stashed tree, feature branch checked out, and a
recorded baseline commit; refuse to dispatch otherwise.
**Enforcement layer:** skill (c2c Step 5) + CI test
**Priority:** P2 | **Effort:** S | **Risk:** low — `deep-refactor` Step 0.3/0.7 is the pattern to copy
**Conflicts with:** none
**Candidate artifact:** issue

### G-14 — SAST and a dedicated security audit phase (spec §5.2 G10, §5.4, §6.8)
**Status:** PARTIAL
**Our evidence:** `reviewer.md` lists Security first in its checklist (input validation, injection, secrets, auth);
`deep-refactor/SKILL.md:47` runs a security dimension and `:272` makes every finding report-only;
`review-triage-fix/SKILL.md:104` routes all security findings to REPORT-ONLY (breaker C).
**Gap:** all of it is LLM judgement. No scanner runs anywhere — no Semgrep, CodeQL, Bandit or equivalent — and there is no
P7-style audit phase before a release. The spec's base rate for the class, 25–33% of generated code carrying a weakness, is
what justifies the cost.
**Proposal:** an opt-in `security-audit` job in the `ci.yml` template (Semgrep default rules) plus a `/skill` wrapper
running the spec's ten-step protocol on demand, all findings report-only per ADR-0018.
**Enforcement layer:** blueprint text (ci template) + skill
**Priority:** P2 | **Effort:** M | **Risk:** low — report-only, and the ten-step protocol is already written out in the spec
**Conflicts with:** ADR-0018 mandates security findings stay report-only; this proposal preserves that
**Candidate artifact:** new ADR + issue

### G-15 — Debris and litter scan (spec §5.3 D8, §2.2.8)
**Status:** PARTIAL
**Our evidence:** `commit/SKILL.md:56-59` never auto-stages untracked files and lists them separately in the approval gate,
which surfaces most debris to the human; `auto-format.sh:6-16` handles formatting. `coder.md` has no cleanup instruction;
the spec's "leave it cleaner than you found it" standing instruction is absent from every agent file.
**Gap:** leftover debug logging, one-off verification scripts, and abandoned commented blocks are caught only if a human
reads the diff. Temp branches are not registered or reconciled at all.
**Proposal:** add the cleanup clause to `coder.md`'s Output Format ("list every temp file, branch and debug statement you
created and its disposition"); `commit` Step 1 flags scratch-looking untracked paths distinctly.
**Enforcement layer:** agent frontmatter (`coder.md` body) + skill (commit Step 1)
**Priority:** P3 | **Effort:** S | **Risk:** low
**Conflicts with:** none
**Candidate artifact:** issue

### G-16 — Canonical-mechanism conformance (spec §5.3 D9)
**Status:** ABSENT
**Our evidence:** `staging/user/rules/python.md`, `typescript-react.md`, `swift.md` and `shell.md` carry conventions as
prose with `paths:` frontmatter; `coder.md:66` says stack tooling comes from the project CLAUDE.md. No project declares its
one true HTTP client, logger, or config accessor, and nothing checks conformance.
**Gap:** the spec's failure is an agent hand-rolling an HTTP call while a canonical helper exists in a hundred other places.
Our rules files carry taste, not mechanism identity.
**Proposal:** a `.claude/rules/canonical-mechanisms.md` convention (one line per mechanism: name → import path), generated
by `project-init` from the existing code, and cited in the reviewer's Consistency check.
**Enforcement layer:** skill (`project-init`) + agent frontmatter (`reviewer.md` checklist)
**Priority:** P3 | **Effort:** M | **Risk:** low
**Conflicts with:** ADR-0019 governs what lives in `.claude/rules/` — this adds a file type, not a new tier
**Candidate artifact:** issue

### G-17 — Per-write test feedback (spec §5.1 latency requirement, §5.2 G4, Law 2)
**Status:** DIVERGENT-BY-DECISION
**Our evidence:** `post-write-check.sh:9` is advisory and never blocks; `:14` is syntax-only by decision; tests run once per
task, at the Stop event (`stop-gate.sh:113`).
**Gap:** the spec wants unit tests on every file save ("turn it red, flash a warning") and quotes a 0%→70% fix-rate
difference between issue-tracker reporting and IDE-time surfacing. We are one feedback cycle slower by design.
**Proposal:** none. ADR-0039 D2/D3 decided this: mid-implementation code is legitimately incomplete, and a per-write project
check is slow and mostly noise about symbols that do not exist yet. Revisit only if a project ships a fast, file-scoped test
selector.
**Enforcement layer:** already hook (PostToolUse) + hook (Stop)
**Priority:** P3 | **Effort:** — | **Risk:** —
**Conflicts with:** ADR-0039 D2/D3 settled this in the other direction; the proposal is to keep it
**Candidate artifact:** none

---

## 4. System and agentic management

### G-18 — Tracer-bullet phase (spec §4.4.3, §6.4)
**Status:** ABSENT
**Our evidence:** no occurrence of "tracer" anywhere under `staging/`. c2c goes Gate 2 (architecture) → Gate 3 (project
memory) → Gate 4 (session boundary) → Step 5 (full implementation), `concept-to-code/SKILL.md:1539-1663`.
**Gap:** no cheap thin-slice probe sits between "plan approved" and "implement everything", so nothing returns the spec's
most valuable outcome — Red, the agent cannot do this class of work, take manual control. Today that verdict arrives after a
full Step 5.
**Proposal:** an optional Step 4.5 dispatching one coder on the thinnest end-to-end slice, reporting green/amber/red; red
routes to a gate asking whether to continue, reduce scope, or hand-code. Skipped on `express`, offered on `standard`.
**Enforcement layer:** skill (c2c Step 4.5 + new gate) + manifest field
**Priority:** P2 | **Effort:** M | **Risk:** medium — adds a gate to a chain that already has fifteen; must be genuinely
optional or it becomes ceremony
**Conflicts with:** none
**Candidate artifact:** new ADR + issue

### G-19 — Context-occupancy instrumentation and PreCompact (spec §3.1, §3.2 C1–C3, §5.3 D11)
**Status:** PARTIAL
**Our evidence:** `staging/user/settings.json:4` sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: 70` — a threshold, not a
measurement; no `PreCompact` hook is wired (the event is absent from the hooks block); `session-context-inject.sh` and the
manifests implement the externalisation half of the Memento method well.
**Gap:** occupancy is not observable per agent or per turn, so it cannot be a gate input, and auto-compaction can fire
mid-operation. The spec's documented instruction violation happened at 50% occupancy — below our 70% threshold.
**Proposal:** a `PreCompact` hook refusing to compact while a chain step is mid-flight (manifest `current_step` in a
dispatch state), forcing the handoff write first; report occupancy in the `Stop` hint beside the existing daily usage line.
**Enforcement layer:** hook (PreCompact) + hook (Stop, extend `usage-daily-hint.sh`)
**Priority:** P2 | **Effort:** M | **Risk:** medium — a PreCompact refusal that fires wrongly strands a session; must fail
open like every other hook here
**Conflicts with:** none
**Candidate artifact:** issue

### G-20 — Untrusted input reaching an unattended design chain (spec §2.5 `[GAP]`, §13 G-1)
**Status:** ABSENT
**Our evidence:** `spec-from-issue/SKILL.md:12` turns a GitHub issue title and body into a SPEC with no `AskUserQuestion`;
`nightly-autopilot/SKILL.md:46` drives Phase P from a label (`issues_label`, `:57`); `roadmap-from-issues.sh` builds the
roadmap from the same source. The only filter is `spec-issue-gate.sh`, a thinness/vagueness check — a quality gate, not a
trust boundary.
**Gap:** an issue body is attacker-controllable text that becomes an unattended agent's instructions, overnight, on a
machine with commit and push authority. The repo is private and single-author today, so exposure is low — but that is a
property of the account, not of the design. Both books are silent; the spec tells you to design it yourself.
**Proposal:** treat issue bodies as data — fence them in the prompt, strip instruction-shaped lines before they reach
`spec-from-issue`, and accept only issues authored by the repo owner (`gh issue view --json author`).
**Enforcement layer:** skill (spec-from-issue, nightly Phase P) + CI test
**Priority:** P2 | **Effort:** M | **Risk:** low — an author allowlist is one API field
**Conflicts with:** none. ADR-0023's "refuses to fabricate" gate is adjacent but orthogonal
**Candidate artifact:** new ADR + issue

### G-21 — External-dependency feasibility gate (spec §15.4, gate G13)
**Status:** ABSENT
**Our evidence:** `nightly-autopilot/SKILL.md:94-99` pre-flight covers roadmap presence, TOFU trust, and gh auth; nothing
checks whether the *feature about to be built* needs a credential, an OAuth consent screen, or a cloud console that does not
yet exist.
**Gap:** the spec's case is two expert authors failing the same task on authentication alone. For us the failure is specific
and expensive: an unattended overnight agent blocked in a consent flow cannot self-unblock and burns tokens until the budget
stops it.
**Proposal:** in c2c Gate 2 and nightly Phase P, require the plan to declare external dependencies; if any is declared,
assert credentials are already provisioned and no interactive flow is needed, otherwise mark the feature `needs-human` and
skip it (the mechanism Phase P already has).
**Enforcement layer:** skill (c2c Gate 2, nightly Phase P) + manifest field
**Priority:** P2 | **Effort:** S | **Risk:** low — reuses the existing `needs-human` skip path
**Conflicts with:** none
**Candidate artifact:** issue

### G-22 — Delegation scoring and supervision level (spec §4.5, §9.3)
**Status:** ABSENT
**Our evidence:** the orchestrator's parallelisation logic is three criteria — file independence, test state, task type —
`docs/vibe-coding-system.md:1388-1390`, with a cap of 4. Nothing scores a task for novelty, prior success, or blast radius
before dispatching.
**Gap:** supervision level is uniform. The spec's five factors exist to prevent over-delegation *before* it manifests, and
their output is the oversight level for that task.
**Proposal:** fold this into G-12 rather than building it separately — `risk` and `task_type` on the task node are the same
information under different names, and two scoring schemes would drift.
**Enforcement layer:** manifest field (via G-12)
**Priority:** P3 | **Effort:** S | **Risk:** low
**Conflicts with:** none — subsumed by G-12
**Candidate artifact:** none (rolled into G-12's ADR)

### G-23 — Agent-level instrumentation and constraint tracking (spec §8.4, §8.5, §4.6)
**Status:** PARTIAL
**Our evidence:** `staging/plugin/scripts/usage-report.py:11-14` gives daily tokens, cache hit rate and agent dispatch
counts, and states plainly that sub-agent token cost is not locally observable; `usage-snapshot.py` diffs are logged per
chain (`concept-to-code/SKILL.md:96`, `:991`); `vibe-status` aggregates system health.
**Gap:** none of the spec's control metrics exist — test-count delta, deleted lines per task, claim-vs-reality mismatch per
agent, iteration count, session duration — and those are the inputs to rut detection and a per-agent trust score. Wait time
per phase boundary, the constraint, is unmeasured too.
**Proposal:** emit the four cheap ones (test delta, deleted lines, iteration count, elapsed) into `step5-report.json` and
`nightly-report.json`, which both already have a schema and a reader.
**Enforcement layer:** skill (c2c Step 5, nightly) + manifest field
**Priority:** P3 | **Effort:** M | **Risk:** low
**Conflicts with:** none. ADR-0039 D8 stays `none` until per-task reviewer cost is observable — this is the missing input
for that, not a replacement decision
**Candidate artifact:** issue

### G-24 — Human-gate coverage against H1–H20 (spec §2.7)
**Status:** PARTIAL
**Our evidence:** covered — H1/H2/H3 by c2c Gates 2/1/2, H5/H6/H7 by `commit/SKILL.md:174-207` (message, included files,
excluded untracked all shown before the click), H8 by the deny list in `staging/user/settings.json:72-85` plus
`agent-command-scope.sh`, H12 by RTF, H14 by `db-backup-guardrail.sh`.
**Gap:** H4 (test eyeballing — nobody is asked to read the tests), H10 (interface changes — see G-10), H11 (dependency
additions — no gate, prompt only, see G-06), H16 (the periodic direction check — no equivalent in any long-running chain),
H18/H19 unrepresented.
**Proposal:** add the two cheap ones: surface the test diff explicitly in the `commit` Step 4 gate (H4), and add a
direction-check prompt at the c2c Step 5 mid-point on chains above N tasks (H16).
**Enforcement layer:** skill (commit Step 4, c2c Step 5)
**Priority:** P2 | **Effort:** S | **Risk:** low
**Conflicts with:** none
**Candidate artifact:** issue

### G-25 — Licence and provenance scanning (spec §9.6)
**Status:** ABSENT
**Our evidence:** `clean-public-repo` handles anonymisation and tool-trace removal (ADR-0011, ADR-0026) and explicitly
refuses to falsify authorship; nothing scans for licence contamination or verbatim reproduction of licensed snippets.
**Gap:** the spec's default posture is "treat AI-generated code as if it's under an ambiguous licence" and it names the
concrete risk: a GPL-derived snippet in a proprietary tree, undetectable without a scanner.
**Proposal:** an optional licence-scan step in the `ci.yml` template for repos that publish; keep it opt-in, since it is
irrelevant to a private single-author repo.
**Enforcement layer:** blueprint text (ci template)
**Priority:** P3 | **Effort:** S | **Risk:** low
**Conflicts with:** none
**Candidate artifact:** issue

### G-26 — Accessibility and i18n as gates (spec §15.3)
**Status:** PARTIAL
**Our evidence:** `ui-layout-audit` and `macos-ux` exist as review skills, and c2c Gate 5.05 auto-runs the UI layout audit
(`concept-to-code/SKILL.md:1745`); `staging/project-templates/ios-swiftui/CLAUDE.md` carries an "Accessibility (required)"
section (blueprint §6, `docs/vibe-coding-system.md:1988`).
**Gap:** accessibility is a template instruction and a review skill, not a gate; i18n is absent entirely. The spec names
both as systematic AI omissions and says explicitly that accessibility "is a gate, not an aspiration".
**Proposal:** make Gate 5.05 assert an accessibility checklist result rather than only running the layout audit, for
UI-bearing chains; leave i18n as a documented reviewer checklist item.
**Enforcement layer:** skill (c2c Gate 5.05) + agent frontmatter (`reviewer.md` checklist)
**Priority:** P3 | **Effort:** M | **Risk:** low
**Conflicts with:** none
**Candidate artifact:** issue

---

## 5. What NOT to adopt

1. **Cross-model reviewer on a different model family (§2.2.7, §2.4).** The spec's own binding
   section concedes Claude Code cannot dispatch a non-Anthropic model and routes it through an MCP
   gateway or an external CI step. For a single operator that buys a second provider account, a new
   supply-chain surface, and a second set of quirks, to hedge a risk our `reviewer` + RTF + the
   deterministic checks already attack from three angles. Revisit only if a gap analysis shows
   correlated blind spots, which we have no data for.
2. **`Owner:` field and a CI check rejecting an empty value (§9.5, H15).** NOT-APPLICABLE: one
   human, every repo, every commit. The pager test is satisfied trivially and a field that is always
   the same value is noise.
3. **Product Agent, P0 intake and P11 GTM (§2.2.10, §6.1, §6.12).** Out of scope for a personal
   development system; the spec itself declares commercial GTM a gap (G-9) and limits §6.12 to
   product-quality feedback loops. The validation question is answered by the operator before the
   chain starts.
4. **Org-scale adoption programme: leaderboards, token-burn KPI, mavens/connectors, hiring rubric
   (§8.3, §8.6, §9.7, §9.8).** NOT-APPLICABLE at N=1.
5. **Container isolation per agent (§2.5, tier 4).** `isolation: worktree` is tier 2 of the spec's
   own ladder and is the recorded choice (blueprint §12, ADR-0016 and the coder frontmatter).
   Containers buy exfiltration containment we do not need locally and cost per-agent startup on
   every dispatch.
6. **RAG / codebase index (§3.7).** The spec records the Claude Code team's own finding that agentic
   search outperformed RAG "by a lot" and states plainly that nobody knows which wins. Building an
   index would be adopting the contested side of a documented `[GAP]` with no measurement.
7. **Ops Agent and production telemetry loop (§2.2.9, §6.11).** This system builds software; it does
   not operate a production service. Adopting P10 would mean inventing the thing it monitors.
8. **DORA four as tracked metrics (§8.2).** There is no deployment pipeline to measure — the outer
   loop ends at a merged PR by design (ADR-0022 forbids unattended merge). Deployment frequency and
   failure rate would be measuring a stage we do not own.
9. **`AGENTS.md` alongside `CLAUDE.md` (§10.1).** The spec keeps the book's filename for
   portability. We have deliberately consolidated on `CLAUDE.md` + path-scoped `.claude/rules/`
   (ADR-0019, ADR-0043), and `claude-md-slim` enforces a single source of truth with a
   content-preservation gate. Adding a second always-loaded rules file would reintroduce exactly the
   duplication that skill exists to remove.
10. **AI-assisted project management over the task graph (§15.5).** Task allocation and duration
    prediction assume a team and a velocity history. `PROJECT.md` + the roadmap already carry what a
    single operator needs.
11. **A scheduled Maintenance Agent (§15.6).** `nightly-autopilot` already converts a labelled
    backlog into PRs unattended (ADR-0022, ADR-0023); a second scheduled actor generating its own
    backlog would compete with it for the same branches and the same review capacity.

---

## 6. Sequenced shortlist (P1, in execution order)

1. **G-06 — secrets and dependency gate.** No dependencies. Independent of everything else, and the
   only P1 whose failure mode is irreversible once a key is pushed. Detection rules already exist in
   the vendored `clean-public-repo` skill.
2. **G-02 — wire `weakening-scan.sh` into the unattended paths.** No dependencies. The detector is
   built and tested; this is call sites plus a blocking rule. Doing it before G-01 matters: it is
   what makes a coder that still writes its own tests survivable in the meantime.
3. **G-04 — requirement IDs in the SPEC + coverage check.** Depends on nothing, but is a
   **precondition for G-01**: a verifier briefed "from the spec, not the implementation" needs the
   spec to enumerate what it is testing. Also unlocks G-03's stronger form and G-23's test-delta metric.
4. **G-01 — generator/verifier separation.** Depends on G-04 (spec IDs to test against) and on G-02
   (the test-write ban shares the scope-hook machinery and the anti-weakening check becomes the
   verifier's backstop). Last because it is the largest and because the two before it reduce the cost
   of getting it wrong.

P2 work that would follow, in dependency order: G-12 (absorbs G-22) → G-09 and G-13 (both cheap once
Step 5 has a checkpoint block) → G-11 (needs G-02/G-03/G-06 to exist as standalone scripts before it
can put them in the CI template) → G-10, G-14, G-18, G-19, G-20, G-21, G-24.
