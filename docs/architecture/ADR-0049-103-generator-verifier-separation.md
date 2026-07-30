# ADR-0049 — Generator/verifier separation: dispatch the tester, deny the coder test writes

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #103 (fourth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/103-generator-verifier-separation-dispat.spec.md`
- **Builds on:** ADR-0048 (#102) — the tester is briefed from the SPEC's `R-NN` identifiers that
  #102 introduced, via `spec-coverage.sh --list`. ADR-0041/ADR-0045 for the
  instruction-versus-enforcement distinction and the guardrail-not-sandbox threat model.
  ADR-0047 for the Step 5 gate placement idiom.
- **Supersedes:** nothing. **Amends:** ADR-0048 §D10 in one respect — `autopilot-build/SKILL.md` is
  edited here (§D5), where #102 left it untouched.
- **Closes:** gap **G-01** of `docs/books/INTEGRATION-REPORT-agentic-spec.md`, the highest-priority
  finding of that audit.

## Context

The external agentic-system spec calls generator/verifier separation "the single most important
structural decision" a multi-agent coding system makes: the agent that writes the implementation
must not be the agent that writes the test the implementation is judged by. Otherwise the accept
decision is made by the same process that produced the thing being accepted, and a green suite
means only that the generator agreed with itself.

This system does not have that separation, and the gap is not subtle. `staging/plugin/agents/`
contains a fully specified `tester.md`. `grep -rn "tester" staging/plugin/skills/concept-to-code/SKILL.md`
returns **exactly one hit** — a row in the Step 5 effort-pin table. The agent has never been
dispatched by any skill. Meanwhile `concept-to-code/SKILL.md` Step 5 instructs the coder to
"Execute tasks … following TDD (red → green → checkpoint)", which is precisely the coder writing
the tests it will be judged by.

Blueprint §2 lists `tester` in the agent roster. So the documented architecture and the executable
surface disagree, and have disagreed since the roster was written.

This is also the third instance of a pattern this repository keeps rediscovering: a capability that
exists as a file and is never wired into a dispatch path. ADR-0043 found it for `PAIRS`
(`architect.md` fixed on the repo side, never deployed, nothing reported it). ADR-0041 found it for
the architect's write scope (prose in a file, no enforcement). Here the artifact is an entire agent.

## Decision

### D1 — The tester runs BEFORE the coder, per task group, on both dispatch paths

SPEC objective 2 — brief the tester "from the specification, never from the implementation" — is
only *mechanically* true if the implementation does not exist yet. Tester-last was the close
alternative and is rejected: it reduces the objective to a request that an agent holding `Read` can
ignore at no cost and with no trace. Ordering makes it a property of the dispatch graph instead of a
property of an agent's good behaviour.

The tester is briefed from the SPEC's `R-NN` identifiers via `spec-coverage.sh --list` (ADR-0048
§D3 and §D6 exist for this consumer and no other). Two fallbacks apply when the SPEC declares no
IDs: brief from the success-criteria section verbatim, and if that is also absent, from the plan
task text — never from files the coder has written.

### D2 — Tester-first forces a worktree-isolation change, and that fixes a latent defect

`review-triage-fix/SKILL.md:158` already documents the constraint: *"The coder agent runs with
`isolation: worktree`, which forks from the last commit and does not see uncommitted changes."* A
tester that has just written failing tests has, by definition, left uncommitted changes. A worktree
coder would fork past them and make nothing green.

So c2c's "Pre-dispatch: worktree isolation check" gains a second condition, stated in RTF's own
idiom: `git diff HEAD --name-only` non-empty → `isolation: "none"`. This degrades gracefully — a
group whose tester wrote nothing keeps its worktree.

It also fixes a defect that predates this feature: a Step 5 dispatched into an already-dirty tree
has been silently forking stale worktrees all along, and nothing reported it.

### D3 — Enforcement is a hook, `test-write-scope.sh`, armed by a marker that is also the instruction

`PreToolUse` on `Edit|Write|MultiEdit`. Allow on every failure mode. `agent_type != "coder"` →
allow first, which is what lets the tester write tests at all. No main-session fallback, matching
`write-scope-enforce.sh`'s deliberate divergence (an orchestrator turn quoting the marker must not
bind the whole session).

The marker string, verbatim in the coder's brief on both paths:

```
TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.
```

ASCII hyphen, **not** an em dash, for the reason recorded in issue #87: the hook matches the
canonical form, and a typographic substitution makes it silently inert.

Keying on `agent_type == "coder"` alone was rejected. RTF Phase 3, `deep-refactor` and c2c Step 6 all
dispatch `agentType: "coder"`, and a fix agent repairing a genuinely broken test is legitimate work.
The marker is what distinguishes a Step 5 implementation coder from those.

### D4 — The path predicate is the broad union minus `.md`, and diverges from ADR-0048 §D3 on purpose

```sh
case "$P" in *.md) allow ;; esac                                   # FIRST, unconditional
case "$P" in */tests/*|tests/*|*/test/*|test/*|*/spec/*|spec/*) deny ;; esac
BN="${P##*/}"
case "$BN" in *.test.*|*.spec.*|test_*|*_test.*|*Test.*|*Tests.*|test-*.sh|run-tests.sh) deny ;; esac
```

ADR-0048 narrows `.spec.` to `js|ts|tsx|jsx`. This keeps it broad, and the two predicates must not
be "reconciled", because **their error directions are opposite**. A *discovery* predicate must not
over-match: a SPEC file that discovers itself makes the coverage gate pass falsely. A *denial*
predicate must not under-match: a missed test path means the separation silently did not happen. A
false deny costs one agent report; a false allow is invisible.

`.md` is excluded first and unconditionally, or `docs/specs/103-….spec.md` matches `*.spec.*` and
the coder cannot write SPECs at all — ADR-0048 hit the same collision from the other side.

Directory rules match a path **component**, so `~/dev/testing-app/` is not a test tree. No path
normalization: the predicate classifies rather than compares, and resolving would add a failure mode
for files that do not exist yet, which is the common case for a new test.

### D5 — `tests_written_by` is a record, never a gate

`step5-report.json` gains an additive `tests_written_by` array of `{task, agent}`. It is
**never a failure signal**: it is self-reported by the agents whose separation it describes, which
is exactly the class of claim ADR-0047 §A3 and ADR-0048 §A7 refuse to trust. A `"coder"` entry is
surfaced at Gate 5 for a human to read. Absent is not malformed.

`autopilot-build/SKILL.md:187–192` restates c2c's isolation check and is updated here. That diverges
from ADR-0048 §D10's "autopilot untouched" deliberately: #102's gap there was cosmetic, this one
would produce a false green on an unattended path.

### D6 — Both paths pin `model` and `effort` explicitly

The tester `agent()` call pins `model: "sonnet"`, `effort: "medium"`. The Step 5 effort table is
documentation, not a binding — an omitted `effort` takes the orchestrator's `high`. This is the
rule ADR-0018's addendum earned and it applies to every new dispatch site.

### D7 — No manifest field, on by default

Separation is not opt-in. It is skipped only when `test_cmd_placeholder` or `test_cmd_provisional`
is true, because there is no real suite for a tester to write against.

### D8 — `tester.md` gains four additive lines

Diverging from the SPEC's "Unchanged", on ADR-0035's finding that a contract belongs in the agent's
own file rather than only in the dispatching skill: a spec-first `When to invoke` bullet, a Process
step-1 branch, requirement-ID reporting in Output Format, and an anti-fabrication edge case.

### D9 — This hook must read only the FIRST `user` entry of the subagent transcript

Not a design preference — a live defect found by this feature's own design pass.
`write-scope-enforce.sh` scans **every** `user` entry for its marker, and tool results are recorded
as `user` entries. The architect dispatched to write this ADR was instructed to read that hook's
source; the hook's own grep pattern entered the transcript as a tool result, and the hook bound the
agent to the garbage scope `[^` and denied every subsequent write. Audit-log evidence:
`wanted=…/[^`, 2026-07-26 15:16:09.

**The hook self-arms on any agent that reads its own source.** The one-line fix (`| head -1` after
the `jq`) is applied to `write-scope-enforce.sh` on this branch and is **staging-only until a human
runs `sync-to-claude.sh --apply`** — the deployed copy at `~/.claude/hooks/` still carries the
defect, which is why a second dispatch of the same brief hit the identical wall. That is
ADR-0044's finding pointed the other way, and ADR-0026's "staging-only until human sync" and
ADR-0043's "a repo-side fix that never deployed and nothing reported it" for a third and fourth
time.

`test-write-scope.sh` must not repeat the mechanism. Recorded as its own issue (#127), together with
an audit of `agent-write-scope.sh` and `agent-command-scope.sh` for the same pattern.

## Alternatives rejected

- **A1 — Tester after the coder.** Cheaper (no isolation change, no dirty tree) but reduces the
  central objective to an honour system. Rejected; see §D1.
- **A2 — Key the deny on `agent_type == "coder"` alone.** Would break RTF Phase 3, `deep-refactor`
  and c2c Step 6 fix agents, all of which legitimately repair tests. Rejected; see §D3.
- **A3 — Reconcile the deny predicate with ADR-0048's discovery predicate.** Rejected: opposite
  error directions (§D4). Left as a `[convention]` note so a future reader does not "fix" it.
- **A4 — Make `tests_written_by` a gate.** Rejected: a self-report by the audited party. §D5.
- **A5 — A manifest field to opt in.** Rejected: separation that is optional is separation that is
  off on the runs that most need it.
- **A6 — Extract the scan-everything transcript read into a shared helper.** Rejected on the
  evidence of §D9: the mechanism being shared is the mechanism that is wrong.

## Consequences

### Positive

- The audit's highest-priority structural gap closes; `tester.md` becomes reachable.
- Documentation and executable surface agree for the first time since the roster was written.
- The latent dirty-tree worktree defect (§D2) is fixed as a side effect, on all Step 5 paths.

### Negative, and not fully mitigated

1. **`isolation: "none"` returns for any group whose tester wrote something.** On the Workflow path
   task groups run in parallel, so parallel coders share the main tree for those groups. GAP E's
   conflict scan was advisory and becomes materially load-bearing. **This is the largest cost of the
   feature.** The SKILL.md text is strengthened to sequence conflicting groups — and an instruction
   is all it is.
2. **The Workflow path's marker is model-generated text.** The Agent-tool fallback copies a literal
   template; the Workflow path asks a model to emit the marker verbatim into each coder prompt, and
   a paraphrase makes the guard silently inert on the *default* path. The failure direction is
   today's behaviour rather than a regression, but "works on both paths" is true by instruction on
   one of them.
3. **Manual `settings.json` wiring.** The hook does nothing at all between merge and a human's edit,
   like every hook this system ships. `sync-manual-steps.test.sh`'s all-clear fixture enumerates
   every wired hook, so this is a contract change to an existing test, not only an addition.
4. **`pairs-completeness.test.sh` is blind to `plugin/scripts/*`** (ADR-0043 scoped it to agents,
   rules and `skills/*/SKILL.md`). Section TI of the new harness is the only thing preventing
   ADR-0043's exact defect for this hook.

### Neutral

- One new hook, one new test file, both CI registries updated (`ci.yml` glob is automatic;
  `docs-ci.yml`'s explicit list needs the manual append).

## Correction 2026-07-28 (ADR-0068 retires §D2)

**ADR-0068 (issue #176) supersedes §D2 in full and retires the dirty-tree isolation-selection
condition it added.** §D2's `git diff HEAD --name-only` non-empty check downgraded a task group to
`isolation: "none"` when the tester had left uncommitted changes — a value the Agent tool's
`isolation` enum does not accept at all (it is exactly `worktree` and `remote`), so the branch this
correction fixes was a live dispatch failure waiting for its condition to be met.

ADR-0068 §D6 removes the condition rather than fixing its target value: the tester is now dispatched
with its own `isolation: "worktree"`, committed, and merged into the feature branch by the
orchestrator *before* the coder's worktree is created (§D5). The coder therefore forks from a `HEAD`
that already contains the tester's tests, so the tree the coder would have been forking into dirty
never arises, and the check §D2 added has nothing left to detect.

`review-triage-fix/SKILL.md:158`'s own `git diff HEAD --name-only` check is a different decision
(dispatch versus inline, not one isolation value versus another) and is explicitly **not** retired
by this correction — see ADR-0068 §D9.

See `docs/architecture/ADR-0068-176-worktree-isolation-contract.md` §D5, §D6, §D9 for the full
account.

## Correction 2026-07-30 (ADR-0088 amends the DISPATCH, not the decision)

**ADR-0088 (issue #241) amends §D1's dispatch granularity. No decision in this ADR is reversed** —
§D3's marker, §D4's predicate, A2 and A5 all stand, and `test-write-scope.sh` is byte-untouched.

The split was dispatched at **task** granularity while a plan task is a **mixed** unit: some of its
sub-steps target test-shaped paths and some do not. Measured over `docs/superpowers/plans/`, 56 of
57 plans name both kinds of path, so this is the ordinary shape of a plan here rather than a
property of one feature. The tester's brief reads the plan only as a third fallback (§D1's chain:
`R-NN` ids, then Success Criteria, then plan text), so on a SPEC that declares ids — the ADR-0048
case — the tester was never told which of the batch's sub-steps were its own, and the coder was
denied them by the hook.

ADR-0088 leaves the fallback chain intact as the answer to *what* to assert, and adds an
unconditional instruction that the plan answers *where*: the batch's test-shaped sub-steps are the
tester's in every case. A5's argument survives untouched, because the separation turned out to be
preservable in the case that appeared to need an exemption.

See `docs/architecture/ADR-0088-241-test-authoring-split-granularity.md` §D1–§D4.
