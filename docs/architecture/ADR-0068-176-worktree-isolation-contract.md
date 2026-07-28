# ADR-0068 — Worktree isolation contract for the multi-agent chain

- **Issue:** #176 (supersedes #175)
- **Date:** 2026-07-28
- **Chain:** `176-worktree-isolation-contract`
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md`
- **Plan:** `docs/superpowers/plans/2026-07-28-176-worktree-isolation-contract.md`
- **Supersedes in part:** ADR-0016 (cross-repo `isolation: none`), ADR-0049 §D2 (dirty-tree
  isolation selection), ADR-0050 §D4 (the reconciliation paragraph that depends on it)

## Status

Proposed.

## Context

`isolation: "none"` is prescribed at eleven places under `staging/`. The Agent tool's `isolation`
enum is exactly `["worktree","remote"]` (SPEC F1): passing `"none"` returns `InputValidationError`
and the **dispatch fails**. Every one of those eleven prescriptions is a live failure waiting for
its branch to be taken.

The deeper defect is why they were written. ADR-0016 recorded `isolation: none` as a pre-existing
fact of the system without ever checking it against the tool schema. ADR-0049 §D2 then built a
dirty-tree condition on top of it, and ADR-0050 §D4 wrote a careful paragraph reconciling the two.
Three ADRs, each internally consistent, resting on a value the platform rejects.

The chain's second problem is orthogonal and worse, because it fails silently rather than loudly.
A subagent worktree forks from the repository's **default branch**, not from `HEAD` (SPEC F3). But
ADR-0050's Step 5 pre-flight requires a clean tree and a feature branch at Step 5 entry — so the
ADR and the plan are committed on the feature branch, and the worktree the coder gets cannot see
them. The pre-flight guarantees precisely the condition that makes the worktree blind. That is not
an edge case; it is every standard chain run.

Two further facts complete the account. On the Workflow dispatch path a `coder`-typed agent gets
**no worktree at all** — frontmatter isolation does not apply there (F4). And work left uncommitted
inside a worktree never reaches the main tree; no skill in this repository merges one (F6, F9).
So the chain has three different isolation behaviours depending on which path and which agent type
runs, and none of them returns work to the feature branch.

### Two facts the SPEC did not have

Design work turned up two documented facts that bear directly on the SPEC's Architecture section.
Both are recorded here rather than folded in silently, because the failure mode this ADR exists to
correct is exactly "a design built on an unchecked premise".

**W1 — `worktree.baseRef` is the native cause of F3, and this system has it set to the wrong
value.** `code.claude.com/docs/en/worktrees` § *Isolate subagents with worktrees*: "Subagent
worktrees use the same base branch as `--worktree`, so they branch from your repository's default
branch **unless `worktree.baseRef` is set to `"head"`**." § *Choose the base branch*: `"head"`
means "branch from your current local `HEAD`, so the worktree carries your unpushed commits and
feature-branch state. **Use this when isolating subagents that need to operate on in-progress
work.**" The live `~/.claude/settings.json:318-320` and the staged
`staging/user/settings.json:299-301` both carry `"baseRef": "fresh"`. F3 is therefore not a
platform limitation to be routed around with a hook — it is this system's own configuration, and
`docs/vibe-coding-system.md:3207-3215` has documented the correct value since the blueprint was
written. The SPEC's Component 1 rests on the unstated premise that a hook is the only way to fork
from `HEAD`. That premise is false.

**W2 — `WorktreeCreate` has a documented decline path, so it is not forced to fail closed.**
`code.claude.com/docs/en/hooks` § *WorktreeCreate*, exit-code table: `0` with a path on stdout =
success; **`0` with empty stdout = decline, fall through to Claude Code's default git worktree
behavior**; any non-zero = creation aborts entirely. The same section states the event has **no
matcher support** — it fires on every worktree creation, including `--worktree` sessions and
background sessions. The SPEC's API section says the hook "is the first hook in this repository
that is not allow-on-every-failure-mode, and that departure is deliberate and forced by the event's
contract". The departure is real for *non-zero*, but the contract also provides a fall-through, and
a hook that declines instead of failing is allow-on-every-failure-mode in the sense that matters.

**W3 — the SPEC's F11 field list disagrees with the current docs.** F11 was doc-sourced, not
probe-measured. It names `worktree_path`, `branch`, `base`, `agent_id`, `agent_type`. The current
`WorktreeCreate` schema names `isolation_mode`, `base_branch`, `worktree_branch`, `worktree_path`
plus the common fields (`session_id`, `transcript_path`, `cwd`, `hook_event_name`) — and does
**not** list `agent_id` or `agent_type`. Field names differ (`base` vs `base_branch`, `branch` vs
`worktree_branch`) and the field R-04's agent-type scoping depends on may not exist at all. One of
the two sources is stale. This is not resolvable from documentation, and the design must not guess:
Task 1 of the plan measures the real payload before any code is written against it.

W3 is the same failure shape as the one this ADR corrects, caught one layer up. It is why Task 1
exists.

## Decision

### D1 — The base contract is two-layer: `worktree.baseRef: "head"` is the mechanism, `worktree-create.sh` is the scoped enforcement and the audit record

Every agent the chain dispatches to **modify** files runs in a git worktree forked from the
currently checked-out `HEAD`, never from the default branch. Two independent things make that true:

1. **`worktree.baseRef: "head"`** in `settings.json`. Native, documented, one key, and it applies
   uniformly to both dispatch paths, every agent type, and `--worktree` sessions. This is the
   mechanism.
2. **`worktree-create.sh`**, a `WorktreeCreate` hook, scoped to the chain's modification set, which
   creates the worktree from `HEAD` explicitly and records the resolved base sha. This is the
   enforcement and the evidence.

Neither alone is sufficient, and the reason each needs the other is specific.

`baseRef` alone is insufficient because it lives in user-scope `~/.claude/settings.json`, is global
to every repository on the machine, leaves no per-creation evidence, and can drift back to
`"fresh"` — at which point the defect returns with no signal at dispatch time. It also cannot be
scoped: `"head"` is the wrong default for a `--worktree` session that genuinely wants to start
clean from the remote.

The hook alone is insufficient because `WorktreeCreate` has no matcher (W2) and this design has it
decline for everything outside the chain's modification set (D3). A declined creation falls through
to the native path — and if `baseRef` is still `"fresh"`, that native path is the bug. Setting
`baseRef: "head"` is what makes the fall-through **correct but unaudited** rather than **wrong and
silent**. That is a direct answer to the hazard R-05 exists for: `write-scope-enforce.sh`,
`agent-write-scope.sh`, `test-write-scope.sh` and `precompact-guard.sh` are all deployed by sync
and wired by hand, and each was inert until someone edited `settings.json`. Under this design an
unwired hook costs the audit trail, not the correctness.

**There is no second mode.** `isolation: "none"` does not exist and is never named again.

### D2 — Measure the `WorktreeCreate` payload before writing anything against it

Task 1 of the plan registers a capture-only hook, dispatches one agent on each path, and records
the real payload. Four questions, all currently unanswerable from documentation:

- the actual field names (`base_branch` or `base`? `worktree_branch` or `branch`?);
- whether `agent_type` is present at all — R-04's scoping predicate depends on it;
- whether exit 0 with empty stdout really declines to the default (W2);
- whether the Workflow path's `opts.isolation: 'worktree'` routes through the hook the way
  frontmatter isolation does (the SPEC's own third unverified item).

The measured answers are appended to this ADR as **F13–F16** in the Measured facts annex below,
in the SPEC's own table form. Every later task is written against F13–F16, never against F11.

**If `agent_type` is absent from the payload, R-04 cannot be satisfied as written.** The recorded
fallback, in order: scope on `isolation_mode` (`"worktree"` vs `"background"`) plus the
`worktree_branch` naming convention; failing that, record R-04 as blocked, leave the hook
unregistered, and fall back to D1 layer 1 alone with the pre-flight assertion checking `baseRef`
only. Do not invent a scoping predicate from a field that was not measured.

### D3 — The hook's fail-safe is DECLINE, never non-zero

`worktree-create.sh` emits a non-zero exit in no reachable path. Every failure mode — `jq` absent,
unparseable stdin, `cwd` not a git repository, agent type outside the modification set, a
`git worktree add` that fails after a best-effort cleanup of its own partial state — exits 0 with
empty stdout, which the platform reads as *decline* and which falls through to native creation
(W2). The repository's allow-on-every-failure-mode convention is preserved, not departed from.

This **amends the SPEC's API section**, which states the departure as forced by the event's
contract. It is forced only if the fall-through does not exist. Task 1 measures whether it does. If
the measurement shows decline is not honoured, this decision reverts to the SPEC's position: the
hook fails closed, the departure is real, and it is recorded as such in the hook header and in this
ADR's Consequences before any further task proceeds.

The take-over path itself is small and its preconditions are checked before anything is mutated:
`worktree_path` must not exist, `worktree_branch` must not already resolve, and `cwd` must be
inside a work tree. Only then does the hook run
`git -C "$cwd" worktree add -b "$worktree_branch" "$worktree_path" "$head_sha"`, append one audit
line recording `agent_type`, `base_branch` as supplied, `head_sha` as resolved and used, and print
the path.

### D4 — The hook declines for every agent type outside the chain's modification set

The modification set is `coder`, `refactorer`, `debugger`, `tester`. Everything else — `reviewer`,
`architect`, `doc-writer`, `researcher`, `--worktree` sessions, background sessions, and any agent
type this repository does not define — declines to native behaviour. This satisfies R-04, and
because `WorktreeCreate` has no matcher (W2), it is the only thing standing between this hook and
replacing worktree creation machine-wide.

Declining is not merely narrower, it is **safer in a specific measurable way**: a hook that takes
over creation is documented to bypass `.worktreeinclude` processing entirely, and
`staging/project-templates/app-fastapi-react/.worktreeinclude` exists, so a project generated from
this system's own template would lose its `.env` in every worktree the hook created. Under D4 that
loss is confined to the four modification agent types, and the plan carries an explicit
`.worktreeinclude` replay inside the take-over path to close even that.

### D5 — Merge-back is orchestrator-driven, per stage, after the dispatch returns

The Agent tool returns `worktreePath` and `worktreeBranch` alongside the agent's report (F10). On
return, the orchestrator — not the agent:

1. checks whether `worktreePath` still exists (CC auto-removes an unchanged worktree, F6) and
   whether `git -C "$worktreePath" status --porcelain` is non-empty;
2. if both hold, stages and commits inside the worktree onto `worktreeBranch`;
3. merges `worktreeBranch` into the feature branch from the main tree with `git merge --no-edit`;
4. records one `worktree_merges` entry and prunes the worktree.

Either check failing is **"nothing to merge"** — not an error, no empty commit, no
`worktree_merges` entry (R-14).

**`coder.md`'s "never commits" is preserved literally and is untouched by this ADR.** The coder does
not commit; the orchestrator snapshots the worktree the coder left behind, after it has returned.
Relaxing the invariant was rejected: it is cited across several ADRs as a deliberate control, and
the orchestrator snapshot reaches the same result without touching it (R-08).

### D6 — The tester runs in a worktree too, and merges before the coder's worktree exists

Stage order per task group is unchanged (tester → coder, ADR-0049 §D1). What changes is that the
tester is dispatched with explicit `isolation: worktree` — it has no frontmatter isolation (F5), and
F8 confirms isolation is addable per dispatch — and that its worktree is committed and merged into
the feature branch **before** the coder's worktree is created. The coder therefore forks from a
`HEAD` that already contains the red tests.

**ADR-0049 §D2's dirty-tree condition is retired as a consequence, at every call site.** It existed
because the tester left uncommitted changes a worktree could not see. Under this protocol the
tester's output is a commit on the feature branch before the coder's worktree exists, so the
condition it tested for cannot arise. ADR-0050 §D4's reconciliation paragraph goes with it: it
reconciles this pre-flight against a condition that no longer exists.

Retirement is asserted, not assumed (R-11). The assertion is anchored on the **isolation-selection
compound phrase**, not on the bare string `git diff HEAD --name-only`, because
`review-triage-fix/SKILL.md:158` uses that same command for a different decision and must survive
(D9).

### D7 — Both dispatch paths pass isolation explicitly

Every `coder` dispatch on the Workflow path passes `opts.isolation: 'worktree'` explicitly, in
`concept-to-code` Step 5 Stage 2 and in Step 6's fix-agent dispatches. Frontmatter does not reach
that path (F4), so the omission was not a stylistic inconsistency — it was the whole reason the two
paths behaved differently. On the Agent-tool path the same value is passed explicitly rather than
inherited from frontmatter, for the same reason `model` and `effort` are pinned explicitly there
(ADR-0018 addendum): a value that is correct only by inheritance is a value nobody notices when the
inheritance changes.

**The Agent tool has no `effort` parameter.** `opts.effort` exists on the Workflow path only. No
part of this design adds one.

### D8 — The file-conflict scan becomes binding; a merge conflict halts

The existing pre-dispatch file-conflict scan is promoted from advisory to binding: task groups whose
plan text names the same file are **sequenced**, never dispatched in the same parallel batch
(R-10). Its old "advisory when everyone keeps `isolation: worktree`, load-bearing when someone drops
to `none`" clause is deleted along with `none` itself.

The scan reads the plan, not what the coder actually touched, so a merge can still conflict. When it
does the chain **halts**: `git merge --abort`, the worktree branch is preserved, the branch name and
the conflicting paths (`git diff --name-only --diff-filter=U`, captured before the abort) are
reported, and no automatic resolution is attempted (R-12). An automatic rebase over agent-authored
work can produce a syntactically valid, semantically wrong result that no gate in this repository
would catch.

### D9 — `review-triage-fix`'s stale-worktree pre-check is NOT retired

`review-triage-fix/SKILL.md:158` runs `git -C <root> diff HEAD --name-only` and, on non-empty
output, applies the fix inline as orchestrator instead of dispatching a coder. It reads like the
condition D6 retires and it is not:

- it selects **dispatch versus inline**, not one isolation value versus another;
- its premise still holds. A worktree forks from a **commit**. Forking from `HEAD` instead of the
  default branch does not make uncommitted work visible — only D5's commit-then-merge protocol does
  that, and RTF has no such protocol;
- RTF is a fix cycle over a working tree the orchestrator is itself editing, not a staged
  tester→coder pipeline.

Removing it because it greps the same way would break a working control. This is recorded because
R-11 says "every call site" and a reader is entitled to ask why this one survived.

### D10 — Non-git CWD refuses; the directory-copy worktree is rejected

Every site that today drops to `isolation: "none"` because the CWD is not a git repository instead
**refuses with an actionable message** (R-13). A worktree cannot exist there and the contract has no
second mode.

The directory-copy worktree that `WorktreeCreate` would technically permit is rejected: without git
there is no branch, so D5's merge-back has nothing to work with, and a second return channel would
exist for one rare path. ADR-0050's pre-flight already requires a feature branch, hence a git
repository, so the case is unreachable from a standard chain run.

### D11 — Additive fields only, no schema bump

| Field | Where | Type | Meaning |
|---|---|---|---|
| `worktree_hook_verified` | manifest | bool, default `false` | The Step 5 pre-flight found the `WorktreeCreate` registration and `baseRef: "head"` |
| `worktree_merges` | manifest and `step5-report.json` | array | One entry per merged stage: `{stage, agent_type, branch, base_sha, merge_result}` |

Both are conditional-if-present in `manifest-validate.sh` (new invariants 20 and 21), on the same
terms as `step5_mode`, `hook_verified`, `step5_review_mode` and `recovery_baseline_sha`. Pre-existing
manifests stay valid with no migration. `manifest-set-flag.sh` sets `worktree_hook_verified` (it is
boolean); `worktree_merges` is an array and is written by bash `sed` on the additive field, the same
route `step5_mode` and `recovery_baseline_sha` already take. An absent `worktree_merges` in a
`step5-report.json` means the run predates this feature; it is not malformed.

### D12 — Corrections to ADR-0016, ADR-0049 and ADR-0050 are forward-recorded

Per the ADR-0034 precedent, the three superseded decisions are not edited in place. Each receives a
dated correction block naming what this ADR supersedes and why. `CLAUDE.md` gains a section for this
chain, as every chain since #28 has.

## Alternatives considered

**A1 — `worktree.baseRef: "head"` alone, no hook at all.** One key in `settings.json`, zero new
code, zero new failure modes, and it fixes F3 for both dispatch paths and every agent type at once.
Genuinely the cheapest correct fix for the base-branch half of the defect, and it is adopted as
layer 1 of D1.
*Rejected as the whole answer* on three counts. It is user-scope and global: flipping it changes
every repository on the machine, including `--worktree` sessions where `"fresh"` is the right
default. It leaves no per-creation evidence, so the SPEC's "default branch vs `HEAD`" question stays
answerable only by running another probe — the exact situation that produced this issue. And it
cannot satisfy R-02, R-04 or R-17, which the SPEC declares.

**A2 — the hook alone, exactly as the SPEC's Component 1 writes it, with `baseRef` left at
`"fresh"`.** This is the SPEC's literal design and it would work while the hook is registered.
*Rejected* because it leaves the native path aimed at the defect. `WorktreeCreate` declines for
every agent type outside the modification set (D4), and an unregistered or unwired hook declines for
all of them — so under A2 the common failure mode is a silent, complete reversion to the original
bug, which is precisely the outcome R-05's assertion exists to make visible. It also ignores a
documented native mechanism that this repository's own blueprint has recorded since
`docs/vibe-coding-system.md:3207`, which is the same class of error as ADR-0016 asserting an enum
value without checking the schema.

**A3 — the hook takes over creation for every worktree, no decline path.** Simpler: one code path,
always exercised, nothing that can rot from disuse. That last point is a real argument here — this
repository has learned twice that a rarely-taken branch is a branch nobody notices is broken.
*Rejected* because `WorktreeCreate` has no matcher and fires on every creation, so A3 replaces
worktree creation machine-wide, for `--worktree` sessions and background sessions included. It
would also bypass `.worktreeinclude` processing for all of them, and
`staging/project-templates/app-fastapi-react/.worktreeinclude` proves that is not hypothetical: a
project generated from this system's own template would silently lose its `.env` in every worktree.
The rot risk is mitigated instead by testing the decline path as a first-class case rather than as
an afterthought (plan Task 4, sections C and D).

**A4 — relax `coder.md`'s "never commits" and let each coder commit inside its own worktree.**
Removes an orchestrator step, and inside an isolated worktree a commit is harmless by construction —
it cannot touch the main tree.
*Rejected* because the invariant is cited across several ADRs as a deliberate control on what a
dispatched agent may do, and the orchestrator snapshot reaches an identical result without touching
it. Weakening a load-bearing invariant to save one `git commit` in the orchestrator is the wrong
direction, and R-08 forecloses it explicitly.

**A5 — automatic merge-conflict resolution (rebase, `-X ours`, or a dispatched resolver agent).**
Would keep an unattended run alive through a conflict instead of halting it, which matters for
`autopilot-build` and `nightly-autopilot`.
*Rejected* because an automatic rebase over agent-authored work can produce a syntactically valid,
semantically wrong result, and nothing in this repository's gate set would catch it: the test suite
runs against the merged tree and a plausible-but-wrong merge can be green. A halt with the branch
preserved is recoverable by hand; a bad silent merge is not distinguishable from a good one.

**A6 — directory-copy worktree for a non-git CWD, using `WorktreeCreate`'s documented non-git
support.** The mechanism exists and is documented for exactly this (SVN, Perforce, Mercurial).
*Rejected* because without git there is no branch, so D5's merge-back — which is the entire return
channel — has nothing to work with. Supporting it would mean a second return channel existing solely
for a path ADR-0050's own pre-flight already makes unreachable, since that pre-flight requires a
feature branch and therefore a git repository.

**A7 — enforce the stage protocol in `manifest-transition.sh` rather than in SKILL.md prose.** Would
make the merge-back a machine-checked state transition instead of an instruction a model is asked to
follow — the ADR-0041/ADR-0045 instruction-versus-enforcement distinction, applied here.
*Rejected* on blast radius, the same ground as ADR-0047 A2 and ADR-0048. `manifest-transition.sh` is
a 48-pair state machine that touches no git today; teaching it to run merges would give every
transition in the chain a new failure mode. The harness pins that the instruction exists; nothing
pins that it is obeyed, and that limit is stated rather than papered over.

**A8 — keep `isolation: "none"` and simply stop passing it to the Agent tool, treating it as an
internal marker for "no worktree".** Minimal diff: the eleven sites keep their structure and only
the dispatch call changes.
*Rejected* because the value's meaning was never "no worktree" — it was "the platform will honour
this", which it does not. Keeping the name preserves the exact confusion that produced three ADRs
built on it, and R-01's test is specifically designed to fail CI on the next invented value.

## Consequences

### Positive

- The three isolation behaviours collapse to one contract. Both dispatch paths, all four
  modification agent types, and both pre-flight surfaces describe the same thing.
- Work returns to the feature branch. Today a worktree coder's output is stranded in
  `.claude/worktrees/agent-*/` and no skill merges it — the chain's implementation step can complete
  successfully and produce nothing.
- The coder can see the tester's red tests, which is what ADR-0049's generator/verifier separation
  needed all along and got only by dropping isolation entirely.
- Eleven latent hard failures are removed. Any of them, once its branch is taken, fails the dispatch
  outright.
- Two mutually-cancelling mechanisms are reconciled: ADR-0050's clean-tree pre-flight and worktree
  isolation stop working against each other.
- An unwired hook now degrades to *correct but unaudited* rather than to the original defect (D1),
  which is a materially better failure mode than every other hand-wired hook in this repository has.
- R-01's test runs in the direction that catches a value nobody has invented yet, rather than
  enumerating the two known-bad ones — the ADR-0043 direction lesson applied at the schema level.
- `WorktreeCreate` and `WorktreeRemove`, previously unmentioned anywhere in this repository (F12),
  become a known and tested part of the surface.

### Negative

- **A hook now sits in the worktree-creation path for every session on the machine.** It has no
  matcher (W2). D3 and D4 confine it to declining for everything outside the modification set, and
  D3 makes every failure mode a decline, but the code runs on every creation regardless.
- **`.worktreeinclude` is bypassed inside the take-over path** and must be replayed by the hook. The
  replay is a partial reimplementation of gitignore-syntax matching in bash 3.2 and will not be
  exactly faithful; the plan restricts it to literal path entries and reports anything it skips.
- **A merge conflict halts an unattended run.** `autopilot-build` and `nightly-autopilot` inherit
  the halt by reference and will stop overnight where they previously proceeded — with wrong
  results, but they proceeded. This is the intended trade.
- **The stage protocol adds two git operations per stage per task group.** A ten-task plan in
  five groups goes from zero merges to ten commit-and-merge cycles, each a place a chain run can now
  stop that it could not stop before.
- **Every gate downstream of Step 5 now reads a tree assembled by merges** rather than one written
  directly. The anti-test-weakening scan, the requirement-ID coverage gate and the diff-budget check
  all diff against `_pre5`, which still holds, but their input is now merge output.
- **Three ADRs are superseded in part**, and the forward-recorded correction pattern means a reader
  of ADR-0016, ADR-0049 or ADR-0050 alone gets the old answer until they reach the correction block.
- **The design is contingent on Task 1's measurement.** If `agent_type` is absent from the payload,
  R-04 is blocked and the hook ships unregistered (D2). If decline is not honoured, D3 reverts to
  fail-closed. Both contingencies are written down; neither is resolved yet.

### Neutral

- No manifest schema version bump. Two additive fields, two conditional invariants, no migration.
- `coder.md` is byte-unchanged. So is `review-triage-fix/SKILL.md:158` (D9).
- The Express path's "No worktree isolation" note (`concept-to-code/SKILL.md:1849`, ADR-0017) is
  disclosed as contradicting `docs/GUIDA-USO-IT.md:117`, which says step E2 dispatches a coder with
  worktree isolation. Neither is in this SPEC's scope; recorded for a future issue rather than fixed
  here.
- Issue #175's subject — a dirty-tree check using `git diff HEAD --name-only`, which cannot see
  untracked files — becomes moot, because D6 retires the check rather than correcting it. #175 is
  closed with that reason recorded, not by inference (R-18).
- `worktree.baseRef` moving to `"head"` also changes `--worktree` and `EnterWorktree` behaviour for
  every project on this machine. Intentional and stated, not a side effect nobody noticed.

## Measured facts annex (F13–F16)

Task 1 of the plan fills this table in the SPEC's own form. It is empty until then, deliberately:
**an empty row is the correct state before the probe runs, and a guessed row is not.**

| # | Fact | How measured |
|---|---|---|
| F13 | *(pending Task 1)* The real `WorktreeCreate` stdin payload: exact field names, and whether `agent_type` / `agent_id` are present. | Capture hook + one Agent-tool dispatch |
| F14 | *(pending Task 1)* Whether exit 0 with empty stdout declines to Claude Code's default git worktree behaviour. | Capture hook returning empty stdout |
| F15 | *(pending Task 1)* Whether `worktree.baseRef: "head"` makes a subagent worktree fork from the feature branch's `HEAD`. | Two dispatches, `"fresh"` then `"head"` |
| F16 | *(pending Task 1)* Whether the Workflow path's `opts.isolation: 'worktree'` fires `WorktreeCreate` the way frontmatter isolation does. | Capture hook + one Workflow dispatch |

## References

- `SPEC.md` — issue #176, measured facts F1–F12
- GitHub issue #176 (comment 5103916596 records F1–F3), issue #175
- `code.claude.com/docs/en/worktrees` — § *Isolate subagents with worktrees*, § *Choose the base
  branch*, § *Non-git version control*
- `code.claude.com/docs/en/hooks` — § *WorktreeCreate*, § *WorktreeRemove*
- `docs/vibe-coding-system.md:3207-3215` — blueprint sec. 12, `worktree.baseRef: "head"`
- ADR-0016 § *Cross-repo isolation constraint*, § *Probe findings* (superseded in part)
- ADR-0049 §D1, §D2, §D6 (§D2 superseded)
- ADR-0050 §D2, §D4, §D6 (§D4 superseded)
- ADR-0034 — forward-recorded correction precedent
- ADR-0043 — check-direction lesson
- ADR-0039 correction 2026-07-27 — negative-case assertions need positive twins
- ADR-0047 §A2, ADR-0048 — instruction-versus-enforcement, blast-radius rejection of
  `manifest-transition.sh` enforcement
