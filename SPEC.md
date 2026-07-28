# SPEC — Worktree isolation contract for the multi-agent chain

**Topic slug:** 176-worktree-isolation-contract

Source: GitHub issue #176 (plus #175, which this supersedes — see Scope).

## Objectives

1. Give the chain a single, measured, enforced contract for how a dispatched agent's working
   environment is created, what it contains, and how its output returns.
2. Remove every prescription of `isolation: "none"`, a value the Agent tool rejects.
3. Make worktree isolation actually work — fork from the checked-out branch, carry the previous
   stage's output, return the agent's work — rather than removing it.
4. Make the two Step 5 dispatch paths (Workflow, Agent-tool batch) behave identically, since their
   silent divergence is the structural cause of the defect, not a symptom of it.

## Measured facts

Every statement in this section was produced by a live probe on 2026-07-28, CC 2.1.220, in this
repository. Nothing here is inferred from documentation or from prior ADR text. The first three are
recorded at issue #176 comment 5103916596; P1–P5 were run during the Step 1 interview.

| # | Fact | How measured |
|---|---|---|
| F1 | The Agent tool's `isolation` enum is exactly `["worktree","remote"]`. Passing `"none"` returns `InputValidationError` and the dispatch **fails** — it is not ignored. | Direct dispatch |
| F2 | Omitting `isolation` leaves `coder.md:8`'s frontmatter `isolation: worktree` in force. | Direct dispatch |
| F3 | The worktree forks from the repository's **default branch**, not from `HEAD`, regardless of which branch is checked out when the session starts. | Two dispatches, the second from a session started on the feature branch |
| F4 | A **workflow**-dispatched agent with `agentType: 'coder'` gets **no worktree at all**: it runs in the main tree, on the checked-out branch. Frontmatter isolation does not apply on that path; isolation there is opt-in via `opts.isolation`. | P1 |
| F5 | `tester` and `reviewer`, which have no `isolation:` frontmatter, run in the main tree on the checked-out branch. | P2 |
| F6 | A file written by a worktree-isolated agent and left uncommitted never reaches the main tree. The worktree survives the agent's completion, unlocked, with the file untracked inside. A worktree with no changes is auto-removed. | P3 |
| F7 | Dispatching into a non-git CWD fails hard with: `Cannot create agent worktree: not in a git repository and no WorktreeCreate hooks are configured.` | P4 |
| F8 | `isolation: "worktree"` passed explicitly to an agent whose frontmatter lacks it (`tester`) works — a worktree is created. Isolation is addable per dispatch. | P5 |
| F9 | Work **committed** inside a worktree survives on branch `worktree-agent-<id>`, which is visible from the main repository. The main tree is untouched. No merge is automatic, and no skill in this repository performs one. | P5 |
| F10 | The Agent tool returns `worktreePath` and `worktreeBranch` to the orchestrator alongside the agent's report. | P3, P5 |
| F11 | `WorktreeCreate` is a documented CC hook event that **replaces default git worktree behavior**. Input: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `worktree_path`, `branch`, `base`, `agent_id`, `agent_type`. It prints the worktree path on stdout; non-zero exit fails creation. `WorktreeRemove` fires when a subagent finishes, **cannot block**, and its failures are logged in debug mode only. | `code.claude.com/docs/en/hooks` |
| F12 | Neither `WorktreeCreate` nor `WorktreeRemove` is mentioned anywhere in this repository or in the deployed `~/.claude/settings.json`. | `grep -rn` |

### The contradiction these facts expose

ADR-0050's Step 5 pre-flight requires `git status --porcelain` to be empty at Step 5 entry, so the
ADR and the plan must already be committed — on the feature branch. F3 says the worktree forks from
the default branch. **The two mechanisms cancel each other**: the pre-flight guarantees exactly the
condition that makes the worktree blind. This is not an edge case; it is every standard chain run.

F5 completes the account of the live failure in `vibiso-system`: the tester writes its red tests
into the main tree, uncommitted, and the Agent-tool coder looks for them inside a worktree forked
from the default branch.

### What is not verified

- Whether the worktree base is the *default branch*, the literal name `main`, or `origin/HEAD`. All
  three coincide in this repository. Separating them needs a repository whose default branch is not
  `main`. The design below is unaffected: it forks from `HEAD` and never resolves a default branch.
- Whether a `WorktreeCreate` hook can serve a non-git CWD in practice (F11 says the mechanism exists
  for "other VCS systems"; nobody here has run one).
- Whether `opts.isolation: 'worktree'` on the Workflow path routes through `WorktreeCreate` the same
  way frontmatter isolation does. R-03 exists to measure this before the design depends on it.

## Scope

**In.** The `WorktreeCreate` hook and its registration; the Step 5 pre-flight assertion;
`concept-to-code` Step 5 and Step 6 (both dispatch paths); `autopilot-build`; `review-triage-fix`;
`deep-refactor`; `nightly-autopilot` (by reference only — it reuses c2c Steps 5–7 verbatim);
`coder.md`; `staging/user/rules/parallelization.md`; `docs/GUIDA-USO-IT.md`; forward-recorded
corrections to ADR-0016, ADR-0049 and ADR-0050.

**Also in: issue #175.** Its subject — the dirty-tree check using `git diff HEAD --name-only`, which
cannot see untracked files — becomes moot, because the dirty-tree condition itself is retired (see
Architecture, component 3). #175 is closed by this work with the reason recorded, not by inference:
R-11 requires the retirement to be asserted, not assumed.

**Out.** Changing which model or effort any agent runs at. Bumping the manifest schema version.
Issues #171, #172, #173, #174, #177, #178 — adjacent, independently scoped. Any merge strategy
beyond "halt on conflict". Non-git-CWD support via a directory-copy worktree (explicitly rejected —
see Edge cases).

## Stack

Bash 3.2 (macOS/BSD-safe), `jq` for hook input parsing, git ≥ 2.5 (`git worktree`), Markdown for the
skill and documentation surfaces, the repository's existing `*.test.sh` harness.

## Architecture

### The contract, stated once

Every agent the chain dispatches to **modify** files runs in a git worktree that:

1. is forked from the currently checked-out `HEAD`, never from the default branch;
2. is created through the project's `WorktreeCreate` hook, never through CC's default behavior;
3. returns its work to the feature branch through an orchestrator-driven merge after the dispatch
   returns.

There is no second mode. `isolation: "none"` does not exist and is never named again.

### Component 1 — `worktree-create.sh` (new hook)

A `WorktreeCreate` command hook. Reads the JSON input on stdin, **ignores the supplied `base`**, and
creates the worktree from `HEAD` of the invoking repository, printing the resulting path on stdout.

- Scoped by `agent_type`: applies to the agent types the chain dispatches for modification. For any
  other `agent_type` it reproduces CC's default behaviour (create from the supplied `base`), so
  nothing outside the chain changes.
- It cannot fail open. `WorktreeCreate` has no advisory mode (F11): a non-zero exit fails creation
  and therefore the dispatch. The hook must be small, dependency-light, and exit non-zero only when
  it genuinely cannot produce a usable worktree.
- It records the resolved base commit, so that the "default branch vs `HEAD`" question stays
  answerable from a log rather than from another probe.

### Component 2 — Step 5 pre-flight assertion

A fourth assertion joins ADR-0050's three (clean tree, feature branch, baseline sha): **the
`WorktreeCreate` entry is present in the effective `settings.json`**. Absent → refuse to dispatch,
print the literal remediation command.

This exists because of this repository's own history: `write-scope-enforce.sh` and
`agent-write-scope.sh` are both deployed by sync and **wired by hand**, inert until a `settings.json`
entry exists. Here inertness is not neutral — without the hook, CC silently reverts to the default
base branch and the defect returns with no signal. The assertion is what makes "not installed"
distinguishable from "installed and working": the ADR-0043 direction lesson, applied to deployment
rather than to a list.

### Component 3 — stage boundaries and merge-back

Both dispatch paths adopt the same stage protocol:

1. The stage's agent is dispatched with worktree isolation — `opts.isolation: 'worktree'` on the
   Workflow path (F4: frontmatter does not apply there), the frontmatter default plus an explicit
   parameter on the Agent-tool path.
2. On return, the orchestrator reads `worktreePath` and `worktreeBranch` from the dispatch result
   (F10), commits whatever the agent left in the worktree onto that branch, and merges it into the
   feature branch.
3. Only then is the next stage's worktree created, so it forks from a `HEAD` that already contains
   the previous stage's output.

**The coder invariant is preserved literally.** `coder.md`'s "never commits" is untouched: the coder
does not commit, the orchestrator snapshots its worktree. This was chosen over relaxing the
invariant precisely because the invariant is deliberate and cited across several ADRs.

**ADR-0049 §D2's dirty-tree condition is retired.** It existed because the tester left uncommitted
changes a worktree could not see. Under this protocol the tester's output is committed and merged
before the coder's worktree exists, so the condition it tested for cannot arise. Retiring it is a
consequence of the design and must be asserted rather than assumed (R-11).

### Component 4 — conflict policy

`concept-to-code`'s existing pre-dispatch file-conflict scan is promoted from advisory to binding:
task groups whose plan text names the same file are sequenced, never dispatched in the same parallel
batch. Merges are then clean by construction in the common case.

When a merge conflicts anyway — the scan reads the plan, not what the coder actually touched — the
chain **halts**, preserving the worktree branch, and never attempts an automatic resolution. An
automatic rebase over agent-authored work can produce a syntactically valid, semantically wrong
result that no gate in this repository would catch.

## Data model

No manifest schema version bump. Additive fields only, conditional-if-present in
`manifest-validate.sh`, so pre-existing manifests stay valid with no migration — the same terms as
`step5_mode`, `hook_verified` and `step5_review_mode`.

| Field | Type | Meaning |
|---|---|---|
| `worktree_hook_verified` | bool, default `false` | The Step 5 pre-flight found the `WorktreeCreate` registration |
| `worktree_merges` | array | One entry per merged stage: `{stage, agent_type, branch, base_sha, merge_result}` |

`step5-report.json` gains one additive array, `worktree_merges`, on the same additive terms as
`weakening_findings` and `requirement_coverage`. Its absence means the run predates this feature; it
is not malformed.

## API / Interfaces

`worktree-create.sh` — stdin: the `WorktreeCreate` JSON of F11. stdout: the absolute worktree path,
one line, on success. stderr: diagnostics. Exit 0 = created; non-zero = creation fails and the
dispatch fails with it. There is no advisory exit code, because the event has no advisory mode. This
makes it the first hook in this repository that is not allow-on-every-failure-mode, and that
departure is deliberate and forced by the event's contract.

## UI flows

**Standard Step 5, per task group.** Pre-flight (4 assertions) → tester dispatched into a worktree
forked from `HEAD` → orchestrator commits and merges the tester branch → coder dispatched into a
worktree forked from the new `HEAD`, which now contains the red tests → orchestrator commits and
merges the coder branch → the existing Step 5 → Step 6 gates run unchanged over the cumulative diff.

**Conflict.** Merge fails → halt, worktree branch preserved, branch name and conflicting paths
reported, no automatic resolution.

**Hook missing.** Pre-flight assertion 4 fails → no dispatch → remediation printed. Under autopilot,
recorded in the report rather than prompted, exactly as ADR-0050's other three assertions behave.

**Non-git CWD.** Refuse with an actionable message.

## Edge cases

- **Non-git CWD (F7).** Refuse. A worktree cannot exist and the contract has no second mode. The
  directory-copy alternative `WorktreeCreate` would technically allow is rejected: without git there
  is no branch, so the chosen merge-back mechanism has nothing to work with, and a second return
  channel would exist solely for this path. The case is rare — ADR-0050's pre-flight already
  requires a feature branch, hence a git repository.
- **Worktree survives a failed dispatch (F6).** Stale `.claude/worktrees/agent-*` directories
  accumulate. The orchestrator prunes after a successful merge and reports, never silently deletes,
  an unmerged one.
- **Agent produced nothing.** CC auto-removes an unchanged worktree (F6), so `worktreePath` may name
  a directory that no longer exists. The merge step treats this as "nothing to merge", not an error.
- **Merge of an empty diff.** A stage whose agent changed nothing must not create an empty commit or
  a spurious `worktree_merges` entry.
- **Duplicate registration.** A `WorktreeCreate` entry already present from another source must not
  be silently overwritten by the sync step.
- **Worktree name collision.** Two dispatches whose `agent_id` prefixes collide, or a leftover
  branch from a previous run bearing the same name.
- **Non-default default branch.** The hook must not hardcode `main` anywhere; it forks from `HEAD`
  and never resolves a default branch, which is what makes the unverified item above harmless here.

## Success criteria

- [ ] R-01 No file under `staging/` prescribes an `isolation` value the Agent tool does not accept;
      a test asserts every `isolation:` value named in `staging/plugin/skills/*/SKILL.md` and
      `staging/plugin/agents/*.md` is one of `worktree` or `remote`, so the next invented value
      fails CI rather than a live run.
- [ ] R-02 `worktree-create.sh` exists, reads the `WorktreeCreate` JSON on stdin, ignores the
      supplied `base`, creates the worktree from `HEAD`, and prints its path on stdout with exit 0.
- [ ] R-03 A live dispatch confirms that a worktree created under the hook reports the feature
      branch's `HEAD` commit, not the default branch's, on both the Agent-tool path and the Workflow
      path — recorded as evidence, not asserted.
- [ ] R-04 `worktree-create.sh` is scoped by `agent_type`: for an agent type outside the chain's
      modification set it reproduces the default behaviour, verified by a test.
- [ ] R-05 The Step 5 pre-flight gains a fourth assertion for the `WorktreeCreate` registration;
      an absent registration refuses the dispatch and prints the literal remediation command.
- [ ] R-06 Every `coder` dispatch on the Workflow path passes `opts.isolation: 'worktree'`
      explicitly, in both `concept-to-code` Step 5 and Step 6.
- [ ] R-07 The orchestrator commits and merges each stage's worktree branch into the feature branch
      after the dispatch returns, using `worktreePath`/`worktreeBranch` from the dispatch result.
- [ ] R-08 `coder.md`'s "never commits" instruction is unchanged, and no dispatch prompt asks any
      coder to commit.
- [ ] R-09 The tester stage is dispatched into its own worktree and its output is merged before the
      coder's worktree is created.
- [ ] R-10 The file-conflict scan is binding: groups naming the same file are sequenced, never
      dispatched in one parallel batch.
- [ ] R-11 ADR-0049 §D2's dirty-tree condition is removed from every call site, and a test asserts
      that no `git diff HEAD --name-only` isolation-selection block survives.
- [ ] R-12 A merge conflict halts the chain, preserves the worktree branch, reports the branch name
      and the conflicting paths, and attempts no automatic resolution.
- [ ] R-13 A non-git CWD refuses with an actionable message at every call site that today prescribes
      `isolation: "none"` for it.
- [ ] R-14 A worktree CC auto-removed, or one whose diff is empty, is handled as "nothing to merge"
      and produces neither an error nor an empty commit.
- [ ] R-15 `staging/user/rules/parallelization.md` and `docs/GUIDA-USO-IT.md:633` state the contract
      as measured; neither promises behaviour that does not exist.
- [ ] R-16 ADR-0016, ADR-0049 and ADR-0050 receive forward-recorded corrections (ADR-0034
      precedent), not in-place edits.
- [ ] R-17 The `WorktreeCreate` registration reaches `~/.claude/settings.json` through the documented
      sync path, and `PAIRS` covers every new file (ADR-0043).
- [ ] R-18 Issue #175 is closed with the reason recorded: its dirty-tree check is retired by R-11,
      not merely rewritten.
- [ ] R-19 Every new assertion is seen RED before green, and every new test file is registered in
      BOTH CI registries (`ci.yml` glob and `docs-ci.yml` explicit list).
