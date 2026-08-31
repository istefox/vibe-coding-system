# ADR-0183 — `VCS-056`: roll out native `memory:` to every sub-agent that can carry it, retire ADR-0012 entirely

- **Status:** Accepted
- **Date:** 2026-08-31
- **Supersedes:** ADR-0012 (`docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` +
  `-implementation-plan.md`) — the mediated inject/harvest mechanism, in full. No agent remains on
  it after this decision.
- **Related:** ADR-0013 (2026-05-25 native-memory pilot, rejected after a measured failure),
  ADR-0182 (`VCS-055`, native memory adopted on `reviewer` only, the scoped precedent this ADR
  extends), ADR-0038 Correction 2026-08-30 (`memory-store-guard.sh`, the hook both pilots depend
  on).

## Context

Stefano's explicit directive: implement Anthropic's native persistent-memory sub-agent feature
(`code.claude.com/docs/en/sub-agents#enable-persistent-memory`) on **every** sub-agent, against
context rot, replacing the prior mechanism system-wide — not the single-agent scope ADR-0182
deliberately limited itself to.

### The mechanism, re-verified at the source (2026-08-31)

Frontmatter field `memory: user | project | local` → a **per-agent** directory
`.claude/agent-memory/<agent-name>/`. At dispatch it injects system instructions plus the first
**200 lines / 25KB** of `MEMORY.md`, with an instruction to curate the file past that threshold,
and auto-enables **Read/Write/Edit with no path restriction at the tool-schema level** (re-confirmed
this session, not assumed from ADR-0182's finding). Depends on `autoMemoryEnabled` (confirmed not
disabled on this machine).

**A correction to the standing directive's premise, made explicit and accepted:** native memory is
per-agent and siloed, not a cross-agent handoff channel. It cannot replace how data moves between
chain steps. That handoff already exists, entirely via files (`SPEC.md`, ADR, plan, `manifest.yml`,
`step5-report.json`, `.claude/dispatch/*.done` markers) or orchestrator-retyped text in a dispatch
prompt — no sub-agent ever reads another sub-agent's output directly
(`concept-to-code/SKILL.md`: "Sub-agents dispatched by the orchestrator... do NOT spawn further
sub-agents"). This migration does not touch that mechanism and does not need to: it is unrelated to
context rot within a single agent's own memory.

### Why this replaces the prior mechanism — measured, not argued

`agent-notes-harvest.sh`'s `inject` mode fed its central store to the dispatch brief with a bare
`cat`, no cap, ever:

| ADR-0012 store | size | lines | harvest sections |
|---|---|---|---|
| `architect.md` | 52,063 B | 229 | 29, since 2026-07-11 |
| `reviewer.md` | 14,677 B | 70 | orphaned (ADR-0182) |
| `debugger.md` | **absent** | — | 0, never produced |

Every `architect` dispatch paid 52KB of append-only, never-curated context. Native memory replaces
this with a store capped at 25KB and self-curating by construction — the central context-rot gain,
and the reason this project exists.

### Coverage: 6 of 8 agents migrate or adopt; 1 excluded on measurement, 2 on structural safety

| agent | outcome | reason |
|---|---|---|
| `reviewer` | already done | ADR-0182, guarded by `reviewer-write-scope.sh` |
| `architect` | migrates | 52KB store, the largest case |
| `debugger` | migrates | ADR-0012 store never populated — zero-cost migration |
| `tester` | adopts | net-new: recurring test conventions across sessions |
| `refactorer` | adopts | net-new: structural patterns already seen |
| `doc-writer` | adopts | net-new: project documentation conventions |
| `coder` | **excluded** | measured (see Phase 0 below): `memory:` resolves inside `isolation: worktree` and is destroyed with it |
| `researcher`, `lesson-extractor` | **excluded** | neither has `Write`/`Edit` — that absence is their only safety guarantee, and `memory:` silently erases it |

`coder` rejoins scope only if it ever loses `isolation: worktree` — a change that would sacrifice
the guarantee ADR-0068 depends on entirely, and is not part of this decision.

### Phase 0 — the `coder` measurement, including a disclosed operational mishap

The user pushed back directly on excluding `coder`: it has the longest-running sessions and is the
most exposed candidate to context rot. That concern is real; the exclusion rests on a different,
narrower, measured fact, not a judgment that `coder`'s context rot doesn't matter.

**Measurement:** `memory: project` was added temporarily to the deployed `coder.md` (backed up
first) and a diagnostic-only probe dispatch was run. Its worktree-scoped write to
`.claude/agent-memory/coder/MEMORY.md` resolved inside the ephemeral worktree copy — the same
mechanics ADR-0038's July measurement found with `local` scope. Removing the worktree destroys the
write; it never reaches the project root. `coder.md` was reverted afterward (diff-confirmed
byte-identical to the backup).

**Disclosed mishap:** the dispatch that ran this probe executed with the wrong working directory —
against `vibe-coding-system` itself instead of the dedicated scratch project prepared for it
(`~/Developer/_scratch/vcs056-coder-memory-probe`). This was caught immediately (`git worktree
list` plus a git-log comparison confirmed the worktree's history was this repo's own) and does not
affect the measurement's validity — worktree-isolation mechanics do not depend on which repository
they run inside. Cleanup performed with explicit user approval: the stray worktree and its branch
were removed, a stray empty `.claude/agent-memory/coder/` directory at the repo root was removed,
and an unrelated untracked file discovered during that cleanup (`AGENTS.md`, a Claude→Codex rename
mirror of this repo's own `CLAUDE.md`) was deleted only after a separate, explicit instruction to
do so.

**Why the concern is still addressed, without changing the technical conclusion:** `coder` is
dispatched per-task or per-batch, with a fresh worktree each time — not once per feature. Native
memory's single-injection-at-dispatch-start model would not address in-dispatch context growth
even if it could persist, because the growth that matters for `coder`'s long sessions happens
*within* one dispatch, not *across* dispatches. The orchestrator (this session) is what accumulates
cross-step history for `coder`'s work, not `coder` itself. The actual applicable remedies for an
oversized `coder` task are already in the chain and unrelated to this migration: task decomposition
in the plan, ADR-0052's diff budgets, and the tracer-bullet pattern. Out of scope here.

### Write-scope: where `memory:` grants a genuinely new privilege

Only where the agent did not already have `Write`/`Edit`:

- **`architect`** — has `Write`, but confined by `test-write-scope.sh` to two roots
  (`docs/architecture/**`, `docs/superpowers/plans/**`). Memory is a **third root**, added there —
  otherwise the agent's own guard would block it from writing its own memory.
- **`debugger`, `tester`, `refactorer`, `doc-writer`** — already have unrestricted `Edit`/`Write`
  with no gating hook. `memory:` grants nothing new for these four: **no new guard added**. This
  surfaces a pre-existing gap (no path restriction on any of the four) that is real, but is neither
  caused nor fixed by this migration — it merits its own issue.

## Decision

Add `memory: project` to `architect`, `debugger`, `tester`, `refactorer`, `doc-writer`. Extend
`test-write-scope.sh`'s existing `architect` guard with a third permitted root
(`.claude/agent-memory/architect/**`) rather than writing a second guard mechanism — two guards
answering the same question ("can architect write here") is exactly what this repo's rule 6 says to
unify. Retire the ADR-0012 mediated mechanism everywhere: no agent depends on it after this change.

### Retirement inventory

- `staging/plugin/agents/{architect,debugger}.md` — removed the `PRIOR AGENT NOTES` factor-in step
  and the terminal `DURABLE NOTES:` Output Format contract; replaced with a native-memory
  instruction specific to each role.
- `staging/plugin/skills/concept-to-code/SKILL.md` — removed the inject/harvest paragraph, the
  `PRIOR AGENT NOTES:` placeholder, the harvest-after-return paragraph, and the `DURABLE NOTES:` row
  from the field-detection table; the Coexistence Invariants section now describes `architect` and
  `reviewer`/`debugger` as carrying native memory instead of the ADR-0012 contract.
- `staging/plugin/skills/review-triage-fix/SKILL.md` — removed the debugger-specific ADR-0012
  inject/harvest paragraph (the reviewer-specific one was already removed by ADR-0182); the Step 1
  native-memory note now covers both agents.
- `staging/plugin/skills/concept-to-code/scripts/agent-notes-harvest.sh` and
  `staging/plugin/skills/concept-to-code/tests/agent-notes-roundtrip.sh` — deleted (`git rm`,
  recoverable via history); neither carried a `# plant:` marker, so no plant-check assertion was
  lost. `tests/run-tests.sh`'s round-trip assertion removed with a rule-19 comment naming this ADR
  in its place.
- `staging/plugin/skills/vibe-status/scripts/aggregate.sh` — Section 7b re-pointed from the retired
  central store (`~/.claude/projects/<enc>/memory/agent-notes/`, which would now render
  `(no agent-notes)` forever) to the native per-agent stores
  (`<project-root>/.claude/agent-memory/*/MEMORY.md`); header renamed "Agent memory (native)", JSON
  field renamed `agent_memory`. `chain-memory-section.sh` and `INTEGRATION.md` comments updated to
  match. `tests/run-tests.sh` Test 12 rewritten against the new fixture shape and re-verified
  passing (16/17, the one pre-existing unrelated failure is a timing flake — see Verification).
- `staging/sync-to-claude.sh` — removed the two PAIRS entries for the deleted scripts; added a
  MANUAL STEP block (matching the existing `backup-before-deploy.sh` precedent) naming the two
  deployed files at `~/.claude/skills/concept-to-code/{scripts/agent-notes-harvest.sh,
  tests/agent-notes-roundtrip.sh}` that this script has no PAIRS entry to remove automatically.
- `staging/plugin/scripts/memory-store-guard.sh`, `chain-memory-capture.sh` — **unchanged**.
  `memory-store-guard.sh` protects the orchestrator's curated store from every sub-agent regardless
  of which memory mechanism it uses; `chain-memory-capture.sh`'s two ADR-0012 mentions are
  historical rationale for why it avoids the same encoding fragility, not a live dependency.
- `staging/plugin/scripts/tests/agent-memory-contract.test.sh` — AM2's assertion is unchanged but
  its comment now cites this session's `project`-scope measurement alongside ADR-0038's `local`-scope
  one. New **AM5**: `researcher` never carries `memory:` (machine-checked, not just prose); its
  sibling `lesson-extractor` carries the same guarantee but is out of scope for this file — it is
  never vendored into `staging/plugin/agents/` (deployed-only, owned by the `auto-learning` skill),
  so this repo's harness has no file to check it against. 6/6 assertions pass.

### Seed data

`architect`'s new `.claude/agent-memory/architect/MEMORY.md` (21 lines, an index into 5 topic
files) was hand-curated from the 229-line ADR-0012 store, condensing durable facts (plant-check
mechanics, spec-coverage/plan-tool traps, write/command-scope rules, CI/shell-portability
divergences, documentation conventions) under the 200-line/25KB native limit. The old store at
`~/.claude/projects/<enc>/memory/agent-notes/architect.md` is left intact as historical record —
declared superseded here, not migrated away, per rule 14 and the standing "never delete without
confirmation" rule. Its fate, and that of the orphaned `reviewer.md`/`debugger.md` siblings, is
explicitly out of scope for this decision (see Out of scope in the working plan).

### Consequences

- **Positive:** the 52KB, never-curated `architect` context load is gone, replaced by a bounded,
  self-curating store. The harvest-omission risk ADR-0012 always carried (an orchestrator step that
  could be forgotten) disappears for every migrated agent — there is no orchestrator step left to
  forget. `tester`, `refactorer`, `doc-writer` gain cross-session memory they never had.
- **Negative:** `debugger`, `tester`, `refactorer`, `doc-writer` already had unrestricted
  `Edit`/`Write` before this change; `memory:` does not narrow that, and this migration does not
  close that pre-existing gap (flagged above as its own issue). `vibe-status`'s Section 7b needed a
  live re-point rather than a passive removal, or it would have silently degraded to "always empty"
  — a different failure than "legitimately empty," per rule 4.
- **Neutral:** the cross-agent data-handoff mechanism used by the chain is entirely unaffected —
  native memory was never a candidate to replace it, and this ADR does not attempt to.

## Alternatives considered

- **Keep ADR-0012 for `architect`/`debugger`, adopt native only for the three net-new agents.**
  Rejected: it does not act on the measured 52KB `architect` evidence, the strongest case for
  migration in the entire fleet, and contradicts the explicit "all sub-agents" directive without a
  technical reason specific to those two agents.
- **Extend coverage to `coder` by dropping `isolation: worktree`.** Rejected: sacrifices the
  guarantee ADR-0068 depends on entirely, to solve a problem (`coder`'s long-session context rot)
  that native memory's single-injection model would not actually address for a per-task, fresh-
  worktree dispatch pattern (see Phase 0 analysis above).
- **Enable `memory:` on `researcher`/`lesson-extractor` for symmetry.** Rejected: their only safety
  property is having no Write/Edit tool at all; `memory:` silently grants both, at the tool-schema
  level, with no path restriction — the exact failure ADR-0013's rejected pilot demonstrated on
  `architect` in 2026-05. Now machine-checked (AM5) rather than left to prose.
- **Treat native memory as a cross-agent handoff channel**, per a literal reading of the initial
  directive. Rejected on verification: the feature is per-agent and siloed by design: it cannot
  serve that purpose. The existing file-mediated chain handoff is unaffected and unbroken by this
  decision.

## Verification

- `agent-memory-contract.test.sh`: 6/6 (AM0–AM5).
- `test-write-scope.test.sh`: 55/55, including new TN5 (architect writing its own memory: allowed)
  and TN6 (architect writing into another agent's memory dir: denied).
- `vibe-status/tests/run-tests.sh` (run against the staging tree via `VIBE_STATUS_SKILL_DIR`):
  16/17 — the one failure (Test 5, "`--skip-harness` too slow") is a pre-existing timing flake
  unrelated to this change, reproduced against the unmodified deployed copy as well.
- `plant-check.sh` full sweep: **654/654, 0 failures**, all 646 declared plants fired. The first run
  caught two real defects in TN5/TN6 before they shipped: both plant targets were declared
  staging-relative (`scripts/test-write-scope.sh`) instead of the required `plugin/scripts/...`
  (BADPLANT, caught by PC2), and after fixing that, TN6's needle targeted the relative-path case arm
  (line 140) while the test harness's payloads are always absolute paths, so the mutation never
  reached the code path the test actually exercises (NOFIRE, caught by PC1) — retargeted to the
  absolute-path arm (line 136, the one with the `*/` prefix) and reconfirmed green.
- **Live re-dispatch, from a fresh session, after `sync-to-claude.sh --apply` deployed this change**
  (2026-08-31): (1) `architect` dispatched to save a durable observation — wrote only inside
  `.claude/agent-memory/architect/` (`MEMORY.md` + a topic file), no ADR/plan file created; (2)
  `architect` dispatched with an explicit instruction to write `src/scratch-test.txt` directly — the
  file was never created, confirming `test-write-scope.sh`'s guard denies the write; (3) a second,
  independent `architect` dispatch with zero conversation context found and reported its own memory
  store unprompted, including flagging that some saved facts describe in-flight branch work needing
  re-verification — confirms native memory auto-injection at dispatch time, not conversational
  carry-over; (4) `debugger` (representative of the four agents with no dedicated write-scope guard)
  dispatched on a made-up bug — populated `.claude/agent-memory/debugger/` (`MEMORY.md` index +
  topic file) exactly as designed. `tester`/`refactorer`/`doc-writer` not individually re-tested:
  identical frontmatter mechanism to `debugger`, same class of agent (no dedicated guard), residual
  risk judged negligible.
- The two now-orphaned deployed files (`~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh`,
  `.../tests/agent-notes-roundtrip.sh`) were backed up to
  `~/.claude/.retired-adr0012-backup-20260831/` and removed, per the sync script's new MANUAL STEP
  note.

## Out of scope

- `coder` — excluded on measurement, not opinion; rejoins only by losing `isolation: worktree`.
- `researcher`, `lesson-extractor` — excluded on structural safety, now machine-checked for the one
  of the two vendored in this repo.
- Deleting the orphaned ADR-0012 stores (`memory/agent-notes/{architect,reviewer}.md`) — declared
  historical, never removed without separate explicit confirmation.
- A shared cross-agent handoff channel — native memory is per-agent by design; the existing
  file-mediated chain handoff already serves this need and is unaffected.
- The pre-existing write-scope gap on `debugger`/`doc-writer`/`tester`/`refactorer`
  (unrestricted `Edit`/`Write`, no gating hook) — real, flagged, not caused or fixed here.

## References

- ADR-0012 — `docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` (the mechanism
  retired in full by this decision).
- ADR-0013 — `docs/architecture/ADR-0013-native-subagent-memory-supersede-mediated.md` (the
  rejected 2026-05-25 pilot; its Correction already points forward to ADR-0182, which this ADR
  extends).
- ADR-0182 — `docs/architecture/ADR-0182-native-memory-adopted-on-reviewer.md` (the scoped
  precedent: guard design, pilot methodology, and the "confined to memory dir" assumption it found
  false — reused here rather than re-derived).
- `staging/plugin/agents/{architect,debugger,tester,refactorer,doc-writer}.md` — frontmatter +
  body edits.
- `staging/plugin/scripts/test-write-scope.sh` + `tests/test-write-scope.test.sh` (TN5/TN6) — the
  extended architect guard.
- `staging/plugin/scripts/tests/agent-memory-contract.test.sh` — AM2 citation update, new AM5.
- `staging/plugin/skills/concept-to-code/SKILL.md`, `review-triage-fix/SKILL.md`,
  `vibe-status/{scripts/aggregate.sh,scripts/chain-memory-section.sh,INTEGRATION.md,
  tests/run-tests.sh}`, `sync-to-claude.sh` — retirement edits listed above.
- This session's live Phase 0 measurement on `coder` (2026-08-31), including the disclosed
  wrong-repository dispatch mishap and its cleanup.
