# ADR-0068 — Worktree isolation contract for the multi-agent chain

- **Issue:** #176 (supersedes #175)
- **Date:** 2026-07-28
- **Revised:** 2026-07-28, after the Task 1 probe. §D1, §D2, §D3, §D4 and the Consequences are
  rewritten; §D5 gains the audit record the deleted hook was carrying. See *Measured facts annex*.
- **Chain:** `176-worktree-isolation-contract`
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md`
- **Plan:** `docs/superpowers/plans/2026-07-28-176-worktree-isolation-contract.md`
- **Supersedes in part:** ADR-0016 (cross-repo `isolation: none`), ADR-0049 §D2 (dirty-tree
  isolation selection), ADR-0050 §D4 (the reconciliation paragraph that depends on it)

## Status

Proposed — **revised 2026-07-28**, re-entering Gate 2.

The first draft's §D1 rested on a two-layer contract whose second layer was a `WorktreeCreate`
hook. Task 1's probe refuted the two premises that layer needed (F13, F14). The hook is dropped,
the mechanism that survives is verified sufficient (F15), and the revision is recorded here rather
than absorbed silently — this ADR exists because three earlier ADRs absorbed an unchecked premise
silently.

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
no worktree unless `opts.isolation` is passed — frontmatter isolation does not reach that path
(F4, as corrected by F16). And work left uncommitted inside a worktree never reaches the main tree;
no skill in this repository merges one (F6, F9). So the chain has three different isolation
behaviours depending on which path and which agent type runs, and none of them returns work to the
feature branch.

### Three facts the SPEC did not have — one held, two did not (revised 2026-07-28)

Design work turned up three claims that bear directly on the SPEC's Architecture section. The first
draft recorded them as W1–W3. The probe kept one and destroyed two. Both outcomes are left in the
record, because the failure mode this ADR exists to correct is exactly "a design built on an
unchecked premise", and the first draft committed it twice while correcting it once.

**W1 — HELD. `worktree.baseRef` is the native cause of F3, and this system had it set to the wrong
value.** `code.claude.com/docs/en/worktrees` § *Isolate subagents with worktrees*: "Subagent
worktrees use the same base branch as `--worktree`, so they branch from your repository's default
branch **unless `worktree.baseRef` is set to `"head"`**." § *Choose the base branch*: `"head"`
means "branch from your current local `HEAD`, so the worktree carries your unpushed commits and
feature-branch state. **Use this when isolating subagents that need to operate on in-progress
work.**" The live `~/.claude/settings.json` and the staged `staging/user/settings.json` both carried
`"baseRef": "fresh"`. **F15 confirms W1 by direct measurement**: `"fresh"` produces a worktree at
the default branch's commit with this chain's own ADR absent from it, `"head"` produces one at the
session `HEAD` with the ADR present. `docs/vibe-coding-system.md:3207-3215` has documented the
correct value since the blueprint was written, and put it out of scope on the ground that "this
system doesn't rely on `EnterWorktree`'s implicit base" — true of `EnterWorktree` and irrelevant,
because subagent worktrees read the same key.

**W2 — REFUTED. There is no decline path.** The first draft asserted that
`code.claude.com/docs/en/hooks` documents `0` with empty stdout as *decline, fall through to Claude
Code's default git worktree behavior*. It does not. A re-read on 2026-07-28 (F18) finds the page
describing only success and failure: the command hook "must print the worktree path as the last
non-empty line of stdout", and no fall-through is described anywhere. **F14 measured the behaviour
directly**: exit 0 with empty stdout aborts the dispatch with `WorktreeCreate hook failed: hook
succeeded but returned no worktree path`. So the claim was not a stale doc — it was a doc reading
that invented a mechanism. The one part of W2 that held is the part that hurt: `WorktreeCreate`
has **no matcher support** and fires on every worktree creation on the machine.

**W3 — HALF-REFUTED, and the half that failed is the load-bearing one.** W3 correctly said the
SPEC's F11 field list was doc-sourced and untrustworthy. It then proposed a replacement schema
(`isolation_mode`, `base_branch`, `worktree_branch`, `worktree_path`) that is not in the
documentation either. The documented input is the common fields plus `name`, a slug identifier for
the worktree (F18). **F13 measured it**: `session_id`, `transcript_path`, `cwd`, `prompt_id`,
`hook_event_name`, `name`, and nothing else. Neither `agent_type` nor `agent_id` is present — the
field R-04's entire scoping predicate depended on, and the field the two hooks this repository
already runs (`agent-write-scope.sh` reads `.agent_type`; `write-scope-enforce.sh` reads
`.agent_id`) get for free from `PreToolUse` because that event fires *inside* the subagent.
`WorktreeCreate` fires *before* it exists.

W3 was written as the reason Task 1 exists. Task 1 then refuted W3's own replacement schema as
well as F11. That is the correct outcome for a measurement task and it is why the plan's fallback
ladder was written down in advance — see §D2.

## Decision

### D1 — The base contract is ONE layer: `worktree.baseRef: "head"` (amended 2026-07-28)

Every agent the chain dispatches to **modify** files runs in a git worktree forked from the
currently checked-out `HEAD`, never from the default branch. One mechanism makes that true:
**`worktree.baseRef: "head"`** in `settings.json`. Native, documented, one key, verified by direct
measurement to apply uniformly to both dispatch paths (F15, F16).

The first draft made this layer 1 of two and added `worktree-create.sh`, a `WorktreeCreate` hook,
as layer 2 — the scoped enforcement and the per-creation audit record. **Layer 2 is deleted.** F13
and F14 compound into a single disqualifying fact:

- F14: a registered `WorktreeCreate` hook must return a usable worktree path on **every**
  invocation. There is no decline, no fall-through, no advisory mode.
- F13 + F17: the payload identifies the *dispatching session*, never the agent about to run. There
  is no discriminator to scope on.
- The event has **no matcher** (W2's surviving half).

Together those three mean a registered hook does not "run on every worktree creation on the
machine" — the cost the first draft accepted — it **owns** every worktree creation on the machine.
Every `--worktree` session in every repository, every background session, every agent type, with
no way to say "not this one". Owning it means reimplementing naming, base resolution,
`.worktreeinclude` copying, non-git handling and background-session semantics, none of which is
fully documented, and any defect aborts an unrelated dispatch in an unrelated project.

What layer 2 was actually buying was one thing: a per-creation audit record of the resolved base.
**That record moves to §D5**, where the orchestrator already reads `worktreePath` after the
dispatch returns and can observe the fork point directly. Observed evidence is strictly better than
the hook's recorded intent, and it costs nothing outside the chain.

The residual weaknesses of a `settings.json` key are real and are answered rather than denied:

- **It is user-scope and global.** Accepted, and stated as a consequence: `"head"` changes
  `--worktree` and `EnterWorktree` behaviour for every project on this machine.
- **It can drift back to `"fresh"`, and the defect returns with no signal.** This is what the Step 5
  pre-flight assertion is for (R-05, §D2). Unlike a hook registration, the assertion checks the key
  that actually governs the behaviour, so it cannot pass while the mechanism is wrong.
- **Sync does not write it.** `sync-to-claude.sh` never edits `settings.json`. It gains a MANUAL
  STEP notice, the same channel the four hand-wired hooks already use, and the pre-flight assertion
  is what makes a skipped step visible at dispatch time rather than at the next post-mortem.

**There is no second mode.** `isolation: "none"` does not exist and is never named again.

### D2 — No `WorktreeCreate` hook is registered by this system; the measuring instrument is retained, unregistered (amended 2026-07-28)

The first draft's §D2 was the instruction to measure the payload before writing anything against
it. It has been executed; the result is F13–F18 in the annex. This section now records what the
measurement decided.

**`worktree-create.sh` is not written.** Its premise — a hook that can identify its caller and
decline for everyone else — does not exist on this platform (F13, F14). The plan's recorded fallback
ladder ran to its end:

1. `agent_type` absent → fall back to scoping on `isolation_mode` plus the `worktree_branch` naming
   convention. **Unavailable**: neither field is in the payload either (F13).
2. Neither discriminates → record R-04 as blocked, ship the hook unregistered, fall back to
   `baseRef` alone. **Partially applied**: `baseRef` alone is the answer, but "ship it unregistered"
   is itself rejected below, so nothing ships.

The instruction the ladder ended with — *do not invent a scoping predicate from a field that was
not measured* — is honoured literally: no predicate is invented, and the component that needed one
is deleted.

**`staging/plugin/scripts/worktree-capture.sh` is retained, unregistered, as the re-measurement
instrument.** It is not a guardrail and it is not deployed: it carries no `PAIRS` entry, on the same
terms as `hook-probe-sandbox.sh`, `hook-probe.sh` and `hook-probe-verify.sh`, which are likewise
staging-only tooling. `pairs-completeness.test.sh`'s reverse check covers `plugin/agents/*.md`,
`user/rules/*.md` and `plugin/skills/*/SKILL.md` only, so a script with no deployed counterpart is
not a completeness defect. (The first draft's plan asserted the opposite for `worktree-create.sh`
and was wrong about it — a claim about a check's behaviour, made without running the check.)

Retention has a specific justification and a specific hazard, and both are written into the file's
header:

- **Justification.** ADR-0016's own lesson is that platform evidence is build-specific: v2.1.154
  moved workflow subagent transcripts without notice. F13–F16 are true of CC 2.1.220 and of nothing
  else. The instrument that re-answers them after the next major bump is worth more than the twenty
  lines it costs.
- **Hazard.** Registering it aborts **every** worktree creation on the machine, because it returns
  no path (F14). The header must say that in its first lines, and the script is changed to exit
  non-zero with an explanatory stderr line rather than exit 0 with empty stdout: both abort, so it
  should abort with a message that names itself instead of the platform's generic one.

Anyone reconsidering a `WorktreeCreate` hook must re-run the probe first and record the result here.
The standing rule is not "hooks are bad"; it is that this event supplies no caller identity and no
way to abstain, and a design that needs either is not implementable until that changes.

### D3 — The fail-safe question is moot, and the rule that replaces it (amended 2026-07-28)

The first draft's §D3 chose DECLINE over non-zero as `worktree-create.sh`'s fail-safe, on W2's
strength, and wrote down the contingency: "If the measurement shows decline is not honoured, this
decision reverts to the SPEC's position: the hook fails closed, the departure is real." F14 showed
exactly that. The contingency is not taken, because the component it governed is deleted; a hook
that must fail closed on every failure mode, machine-wide, with no matcher, is precisely the hook
§D1 refuses to register.

What survives is a rule with a wider reach than the deleted hook had. **This repository's
allow-on-every-failure-mode convention is a property of `PreToolUse`-class hooks, which have an
allow path. `WorktreeCreate` has none.** Anyone who writes a hook for an event whose contract has
no abstain state must say so at the top of the file, because the convention every other hook here
follows will otherwise be assumed and will be wrong.

The one component that now fails **closed** is the Step 5 pre-flight assertion (R-05, §D1). It is
an assertion, not a hook: ADR-0050's other three refuse to dispatch on failure, and the fourth
behaves identically — an unreadable or absent `settings.json` counts as *not verified*, never as
verified-by-default. Stated explicitly because a reader who pattern-matches on this repository's
hook convention will guess the opposite.

### D4 — Scoping is achieved by registering nothing (amended 2026-07-28)

R-04's intent is that nothing this system installs changes worktree creation for sessions outside
the chain. The first draft achieved it by having the hook decline for every agent type outside
`coder`, `refactorer`, `debugger`, `tester`. F13 removes the predicate and F14 removes the decline,
so that construction is unavailable — and the intent is satisfied more completely by its absence:
**no `WorktreeCreate` registration ships at all**, so no session on the machine has its worktree
creation intercepted by this system.

Two properties the first draft had to engineer around now hold for free:

- **`.worktreeinclude` is not bypassed.** A hook that takes over creation is documented to skip
  `.worktreeinclude` processing, and `staging/project-templates/app-fastapi-react/.worktreeinclude`
  exists, so a project generated from this system's own template would have lost its `.env` in every
  intercepted worktree. The first draft answered this with a partial gitignore-syntax reimplementation
  in bash 3.2. That code is not written, and the risk it mitigated does not arise.
- **`--worktree` and background sessions are untouched**, except by the `baseRef` change, which is
  a documented native setting doing the thing it is documented to do.

The forward guard replaces the scoping test: a test asserts that **no file under `staging/`
registers a `WorktreeCreate` hook**, with a positive twin proving the detector fires on a fixture
that does register one. A detector that reports nothing must be distinguishable from a subject that
contains nothing (ADR-0043's direction lesson; ADR-0039's negative-case-needs-a-positive-twin
correction). The test carries the reason in its own header, so the next person to propose the hook
meets F13/F14 before writing it rather than after.

### D5 — Merge-back is orchestrator-driven, per stage, after the dispatch returns; it carries the base-fork audit record (amended 2026-07-28)

The Agent tool returns `worktreePath` and `worktreeBranch` alongside the agent's report (F10). On
return, the orchestrator — not the agent:

1. checks whether `worktreePath` still exists (CC auto-removes an unchanged worktree, F6) and
   whether `git -C "$worktreePath" status --porcelain` is non-empty;
2. **records the fork point before touching anything**: `git -C "$worktreePath" rev-parse HEAD`,
   which at this instant is still the commit the worktree was created from, because the agent does
   not commit (§A4, R-08);
3. if both checks in (1) hold, stages and commits inside the worktree onto `worktreeBranch`;
4. merges `worktreeBranch` into the feature branch from the main tree with `git merge --no-edit`;
5. records one `worktree_merges` entry — `{stage, agent_type, branch, base_sha, merge_result}` —
   and prunes the worktree.

Either check in (1) failing is **"nothing to merge"** — not an error, no empty commit, no
`worktree_merges` entry (R-14).

**Step 2 is the audit record the deleted hook was carrying, and it is better evidence.** The hook
could only log the base it *intended* to use, at creation time, from inside the mechanism being
audited. The orchestrator observes what the worktree *actually* forked from, from outside it,
after the fact. `base_sha` is compared against the feature branch's `HEAD` as it stood when the
stage was dispatched:

- **equal** → the `baseRef: "head"` mechanism was in force for this dispatch. Recorded.
- **not equal** → the worktree forked from somewhere else, which means the agent worked blind: the
  defect this ADR exists to fix, occurring after the pre-flight assertion passed (someone edited
  `settings.json` mid-run, or a future CC build changed the semantics). **Halt**, on the same path
  as the §D8 conflict halt, with its own message naming both shas.

Halting rather than reporting is deliberate and the false-positive analysis is short enough to
state: under the §D6 stage protocol the orchestrator serialises dispatch, merge, next dispatch, so
`HEAD` cannot legitimately move between the sha it captures at dispatch and the sha the worktree
reports; an auto-removed or empty worktree is already handled as nothing-to-merge before this
comparison is reached. A mismatch is therefore always the defect. ADR-0047 §D7's lesson applies —
a report nobody must act on is a report nobody reads — and this feature exists because that exact
drift was silent for months.

**`coder.md`'s "never commits" is preserved literally and is untouched by this ADR.** The coder does
not commit; the orchestrator snapshots the worktree the coder left behind, after it has returned.
Relaxing the invariant was rejected (§A4): it is cited across several ADRs as a deliberate control,
and the orchestrator snapshot reaches the same result without touching it (R-08).

### D6 — The tester runs in a worktree too, and merges before the coder's worktree exists

Stage order per task group is unchanged (tester → coder, ADR-0049 §D1). What changes is that the
tester is dispatched with explicit `isolation: worktree` — it has no frontmatter isolation (F5), and
F8 confirms isolation is addable per dispatch — and that its worktree is committed and merged into
the feature branch **before** the coder's worktree is created. The coder therefore forks from a
`HEAD` that already contains the red tests.

**`baseRef: "head"` does not make this step unnecessary, and the reason is the same one that saves
§D9.** `"head"` means the commit `HEAD` points at, not the working tree. A worktree forks from a
commit. The tester's output is uncommitted until the orchestrator commits it, so without step (3)
of §D5 the coder's worktree would fork from a `HEAD` that is correct and still contains no tests.
The base fix and the merge-back protocol solve two different halves of the same failure and neither
substitutes for the other.

**ADR-0049 §D2's dirty-tree condition is retired as a consequence, at every call site.** It existed
because the tester left uncommitted changes a worktree could not see. Under this protocol the
tester's output is a commit on the feature branch before the coder's worktree exists, so the
condition it tested for cannot arise. ADR-0050 §D4's reconciliation paragraph goes with it: it
reconciles this pre-flight against a condition that no longer exists.

Retirement is asserted, not assumed (R-11). The assertion is anchored on the **isolation-selection
compound phrase**, not on the bare string `git diff HEAD --name-only`, because
`review-triage-fix/SKILL.md:158` uses that same command for a different decision and must survive
(§D9).

### D7 — Both dispatch paths pass isolation explicitly

Every `coder` dispatch on the Workflow path passes `opts.isolation: 'worktree'` explicitly, in
`concept-to-code` Step 5 Stage 2 and in Step 6's fix-agent dispatches. Frontmatter does not reach
that path (F4), so the omission was not a stylistic inconsistency — it was the whole reason the two
paths behaved differently. On the Agent-tool path the same value is passed explicitly rather than
inherited from frontmatter, for the same reason `model` and `effort` are pinned explicitly there
(ADR-0018 addendum): a value that is correct only by inheritance is a value nobody notices when the
inheritance changes.

**F16 confirms this decision and corrects SPEC F4's wording.** F4 states that a workflow-dispatched
`coder` "gets no worktree at all". F16 measured a workflow dispatch with `opts.isolation: 'worktree'`
passed explicitly and got `.claude/worktrees/wf_<runid>-1` at the session `HEAD`. F4's true content
is *frontmatter isolation does not reach the Workflow path*; its stronger phrasing was an
observation made without passing the parameter, and is superseded here. Nothing in the design
depended on the stronger reading — but a future reader would have, which is why it is corrected
rather than left standing.

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
would catch. §D5's base-fork mismatch halts on the same path with its own message.

### D9 — `review-triage-fix`'s stale-worktree pre-check is NOT retired

`review-triage-fix/SKILL.md:158` runs `git -C <root> diff HEAD --name-only` and, on non-empty
output, applies the fix inline as orchestrator instead of dispatching a coder. It reads like the
condition §D6 retires and it is not:

- it selects **dispatch versus inline**, not one isolation value versus another;
- its premise still holds, and F15 does not touch it. A worktree forks from a **commit**. Forking
  from `HEAD` instead of the default branch does not make uncommitted work visible — only §D5's
  commit-then-merge protocol does that, and RTF has no such protocol;
- RTF is a fix cycle over a working tree the orchestrator is itself editing, not a staged
  tester→coder pipeline.

Removing it because it greps the same way would break a working control. This is recorded because
R-11 says "every call site" and a reader is entitled to ask why this one survived.

### D10 — Non-git CWD refuses; the directory-copy worktree is rejected

Every site that today drops to `isolation: "none"` because the CWD is not a git repository instead
**refuses with an actionable message** (R-13). A worktree cannot exist there and the contract has no
second mode.

The directory-copy worktree that `WorktreeCreate` would technically permit is rejected twice over.
It was already rejected on design grounds: without git there is no branch, so §D5's merge-back has
nothing to work with, and a second return channel would exist for one rare path that ADR-0050's
pre-flight already makes unreachable. It is now rejected on availability grounds as well, since
§D1 registers no `WorktreeCreate` hook at all and the mechanism that would implement it is not
present.

### D11 — Additive fields only, no schema bump

| Field | Where | Type | Meaning |
|---|---|---|---|
| `worktree_baseref_verified` | manifest | bool, default `false` | The Step 5 pre-flight found `worktree.baseRef: "head"` in the effective `settings.json` |
| `worktree_merges` | manifest and `step5-report.json` | array | One entry per merged stage: `{stage, agent_type, branch, base_sha, merge_result}` |

**The first field is renamed** from the draft's `worktree_hook_verified`: no hook is verified, or
exists. Nothing has shipped under the old name, so the rename is free, and leaving it would plant a
permanently misleading field name in every manifest the chain writes from now on.

Both are conditional-if-present in `manifest-validate.sh` (new invariants 20 and 21), on the same
terms as `step5_mode`, `hook_verified`, `step5_review_mode` and `recovery_baseline_sha`. Pre-existing
manifests stay valid with no migration. `manifest-set-flag.sh` sets `worktree_baseref_verified` (it
is boolean); `worktree_merges` is an array and is written by bash `sed` on the additive field, the
same route `step5_mode` and `recovery_baseline_sha` already take. An absent `worktree_merges` in a
`step5-report.json` means the run predates this feature; it is not malformed.

`worktree_hook_verified` and `hook_verified` are also easy to confuse: the latter is ADR-0016's
Dynamic-Workflows smoke-test flag and is unrelated to worktrees. The rename removes that collision
as a side benefit.

### D12 — Corrections to ADR-0016, ADR-0049 and ADR-0050 are forward-recorded

Per the ADR-0034 precedent, the three superseded decisions are not edited in place. Each receives a
dated correction block naming what this ADR supersedes and why.

**This ADR is not covered by that precedent and is edited in place**, which is why §D1–§D5 above
are rewritten rather than appended to. ADR-0034's rule governs ADRs that have already shipped and
that a reader may encounter alone; this one is the in-flight artefact of the chain currently at
Gate 2, and a forward-correction block on an unapproved ADR would present the operator with two
designs and no statement of which is being approved.

**`CLAUDE.md`'s ADR-0068 section already exists and describes the refuted design.** It was written
at Gate 3 of the first pass and names the two-layer contract, `worktree-create.sh`, and §D3's
decline fail-safe. It must be **revised, not appended to** — same reasoning as the paragraph above,
and it is the one place in this repository where a stale ADR-0068 summary would be read by every
future session in this project.

## Alternatives considered

**A1 — `worktree.baseRef: "head"` alone, no hook at all. ADOPTED (revised 2026-07-28).** One key in
`settings.json`, zero new code, zero new failure modes; F15 measured it fixing the base-branch half
of the defect on the Agent-tool path and F16 on the Workflow path.
The first draft rejected this *as the whole answer* on three counts, and each is now answered rather
than overridden:

- *It is user-scope and global.* True, and accepted as a stated consequence. The first draft's
  counter-example — a `--worktree` session that genuinely wants to start clean from the remote —
  survives as a real cost, and it is a smaller cost than a hook that owns every worktree creation
  on the machine.
- *It leaves no per-creation evidence.* Answered by §D5 step 2: the orchestrator observes the fork
  point after the dispatch returns, which is stronger evidence than the hook's own log of its own
  intent, and produces it only for the chain's own dispatches.
- *It cannot satisfy R-02, R-04 or R-17 as the SPEC declares them.* True, and those three
  requirements are amended in `SPEC.md` at this Gate 2 re-entry, with the amendment text stated in
  the plan's Task 1b rather than left to interpretation. Amending a requirement whose premise was
  measured false is the correct move; implementing it anyway is not.

**A2 — the hook alone, exactly as the SPEC's Component 1 writes it, with `baseRef` left at
`"fresh"`.** This is the SPEC's literal design.
*Rejected*, and now doubly. Its original rejection stands: it leaves the native path aimed at the
defect, so an unregistered or unwired hook reverts silently to the original bug. F13 and F14 add
that the hook cannot be written as Component 1 specifies at all — Component 1 requires reading a
supplied `base` (absent), ignoring it, and scoping by `agent_type` (absent).

**A3 — the hook takes over creation for every worktree, no decline path.** Simpler: one code path,
always exercised, nothing that can rot from disuse.
*Rejected*, and F14 changes its status rather than its verdict: this is no longer one option among
several, it is the **only** registerable form of a `WorktreeCreate` hook, because the decline path
the other forms assumed does not exist. Everything in the original rejection therefore applies with
no escape hatch: the hook replaces worktree creation machine-wide for `--worktree` and background
sessions, and bypasses `.worktreeinclude` for all of them, which
`staging/project-templates/app-fastapi-react/.worktreeinclude` proves is not hypothetical. The
first draft mitigated the disuse-rot risk by testing the decline path as a first-class case; there
is no decline path to test, so that mitigation is unavailable too.

**A4 — relax `coder.md`'s "never commits" and let each coder commit inside its own worktree.**
Removes an orchestrator step, and inside an isolated worktree a commit is harmless by construction —
it cannot touch the main tree.
*Rejected* because the invariant is cited across several ADRs as a deliberate control on what a
dispatched agent may do, and the orchestrator snapshot reaches an identical result without touching
it. Weakening a load-bearing invariant to save one `git commit` in the orchestrator is the wrong
direction, and R-08 forecloses it explicitly. §D5's audit record adds a second reason: the
orchestrator reads the worktree's fork point *because* the agent left `HEAD` where it found it, so
an agent that commits would destroy the evidence.

**A5 — automatic merge-conflict resolution (rebase, `-X ours`, or a dispatched resolver agent).**
Would keep an unattended run alive through a conflict instead of halting it, which matters for
`autopilot-build` and `nightly-autopilot`.
*Rejected* because an automatic rebase over agent-authored work can produce a syntactically valid,
semantically wrong result, and nothing in this repository's gate set would catch it: the test suite
runs against the merged tree and a plausible-but-wrong merge can be green. A halt with the branch
preserved is recoverable by hand; a bad silent merge is not distinguishable from a good one.

**A6 — directory-copy worktree for a non-git CWD, using `WorktreeCreate`'s documented non-git
support.** The mechanism exists and is documented for exactly this (SVN, Perforce, Mercurial).
*Rejected* because without git there is no branch, so §D5's merge-back — which is the entire return
channel — has nothing to work with. Supporting it would mean a second return channel existing solely
for a path ADR-0050's own pre-flight already makes unreachable. Under §D1 it is also now moot: no
`WorktreeCreate` hook is registered, so the mechanism it would be built on is not present.

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

**A9 — ship `worktree-create.sh` deployed but unregistered, wiring deferred until the event supplies
a discriminator (new, 2026-07-28).** This repository has four instances of the pattern already
(`write-scope-enforce.sh`, `agent-write-scope.sh`, `test-write-scope.sh`, `precompact-guard.sh`):
deployed by sync, wired by hand, inert until a `settings.json` entry exists.
*Rejected*, and the existing instances are the reason rather than the precedent. All four are
`PreToolUse`- or `PreCompact`-class hooks that fail open and are purely additive when wired: wiring
one wrong costs a missed guard. A `WorktreeCreate` hook has no allow path and no matcher (F14), so
wiring this one wrong costs **every worktree on the machine, in every project**. The pattern does
not transfer, and adding a fifth instance whose blast radius is categorically different from the
other four would teach exactly the wrong generalisation. There is a second, blunter problem: a
shipped file plus a MANUAL STEP notice *is* an instruction to wire it, and this plan cannot honestly
write "wire this" and "never wire this" in the same note. If the event later gains a caller
identity and an abstain state, the probe instrument (§D2) is what re-establishes the facts, and the
hook is written then against measurements rather than against hope.

**A10 — derive the agent type inside the hook from `transcript_path` + `prompt_id`, the technique
`write-scope-enforce.sh` and `agent-write-scope.sh` already use (new, 2026-07-28).** Both hooks
resolve a dispatched subagent's context from a hook payload today, so the capability exists in this
codebase.
*Rejected* on three measured grounds, in increasing order of finality:

- **It does not reduce the blast radius, which is the reason the hook was dropped.** F14 means a
  registered hook must return a path on every invocation regardless of what it derives. Derivation
  could change *how* a worktree is created, never *whether* this system creates it. The machine-wide
  take-over of A3 is unchanged, so the technique buys nothing against the disqualifying cost.
- **The technique does not transfer, and F17 is why.** Both existing hooks read identity the event
  hands them — `agent-write-scope.sh` reads `.agent_type` straight out of the `PreToolUse` payload,
  `write-scope-enforce.sh` reads `.agent_id` and finds the subagent's own transcript — because
  `PreToolUse` fires *inside* the running subagent. `WorktreeCreate` fires *before* the subagent
  exists; the worktree is being created in order to run it. The captured payload's `session_id` and
  `transcript_path` are the dispatching session's (F17), so there is no subagent transcript to read
  and no subagent id to read it with.
- **Scanning the parent transcript for a pending `Agent` tool call is ambiguous by construction in
  exactly the case this feature targets.** `concept-to-code` Step 5 dispatches up to four coders in
  one `parallel()` batch from a single prompt, so one `prompt_id` maps to N concurrent dispatches,
  and `name` is an opaque handle that cannot be matched back to any particular one of them. A
  heuristic that is racy in the general case and undefined in the primary case is not a predicate.

**A11 — scope on the `name` field's prefix (new, 2026-07-28).** F13 records `agent-a208432b04c69fff8`
on the Agent path and `wf_<runid>-1` on the Workflow path, and the documentation describes `name` as
a slug that may be user-specified or auto-generated (`bold-oak-a3f2`). So the prefix does appear to
separate subagent worktrees from `--worktree` sessions.
*Rejected.* It still cannot decline (F14), so the machine-wide take-over stands. It distinguishes
*dispatch path*, never agent type, so R-04's stated intent is inexpressible in it. And it depends on
an undocumented naming convention in a field the docs explicitly say a user may supply, so a user
naming a worktree `agent-anything` would be silently captured by this system's hook. Recorded rather
than passed over, because F13's two prefixes are visible in the annex and a reader will ask.

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
- **The implementation surface shrank by an entire hook.** No new `PreToolUse`-class code, no
  `.worktreeinclude` reimplementation in bash 3.2, no `PAIRS` entry, no fifth hand-wired hook, and
  nothing this system installs sits in any other session's worktree-creation path. The feature is
  now one settings key, one pre-flight assertion, one merge-back protocol and a text purge.
- **The audit record got stronger by moving.** §D5 observes the fork point the worktree actually
  used, from outside the mechanism, and halts on a mismatch. The deleted hook could only log the
  base it intended to use, from inside it.
- R-01's test runs in the direction that catches a value nobody has invented yet, rather than
  enumerating the two known-bad ones — the ADR-0043 direction lesson applied at the schema level.
  §D4's "no registration anywhere under `staging/`" test is the same shape.
- `WorktreeCreate` and `WorktreeRemove`, previously unmentioned anywhere in this repository (F12),
  are now measured, documented, and deliberately unused — with the instrument to re-measure them
  retained.

### Negative

- **`worktree.baseRef: "head"` is user-scope and global.** It changes `--worktree` and
  `EnterWorktree` behaviour for every project on this machine. A session that genuinely wants to
  start clean from the remote no longer gets that by default. This is the cost A1 was originally
  rejected for and it is now accepted rather than mitigated.
- **A settings key can drift, and nothing in the repository can stop it.** The Step 5 pre-flight
  assertion is the only detector, and it fires at dispatch time, not at edit time. §D5's per-stage
  base comparison narrows the window; it does not close it.
- **Both halves of the deployment are manual.** Sync never writes `settings.json`. The MANUAL STEP
  notice and the pre-flight assertion are what make a skipped step visible, and both are text a
  human or a model has to act on.
- **A merge conflict halts an unattended run**, and so does a base-fork mismatch. `autopilot-build`
  and `nightly-autopilot` inherit both by reference and will stop overnight where they previously
  proceeded — with wrong results, but they proceeded. This is the intended trade.
- **The stage protocol adds two git operations per stage per task group.** A ten-task plan in five
  groups goes from zero merges to ten commit-and-merge cycles, each a place a chain run can now stop
  that it could not stop before.
- **Every gate downstream of Step 5 now reads a tree assembled by merges** rather than one written
  directly. The anti-test-weakening scan, the requirement-ID coverage gate and the diff-budget check
  all diff against `_pre5`, which still holds, but their input is now merge output.
- **Three ADRs are superseded in part**, and the forward-recorded correction pattern means a reader
  of ADR-0016, ADR-0049 or ADR-0050 alone gets the old answer until they reach the correction block.
- **Five SPEC requirements change meaning mid-chain.** R-02, R-03, R-04, R-05 and R-17 are amended
  at this Gate 2 re-entry because the mechanism they named was measured not to exist. The IDs are
  kept and re-scoped rather than deleted, so `spec-coverage.sh` sees an unchanged ID set — but
  anyone reading the SPEC's git history will find two different meanings behind the same five
  labels on the same day.
- **`worktree-capture.sh` stays in the tree and is dangerous if wired.** Registering it aborts every
  worktree creation on the machine (F14). It is retained for re-measurement after a CC bump, with
  the warning in its header and a test pinning the warning, but the file exists and a reader who
  skips the header can wire it.
- **F13–F18 are true of CC 2.1.220 and of nothing else.** ADR-0016's v2.1.154 experience is the
  precedent: the substrate moves. A future build that adds `agent_type` and an abstain state to
  `WorktreeCreate` would reopen §D1 layer 2 on its merits, and this ADR should be re-read rather
  than cited.

### Neutral

- No manifest schema version bump. Two additive fields, two conditional invariants, no migration.
  One of the two is renamed relative to the first draft (§D11).
- `coder.md` is byte-unchanged. So is `review-triage-fix/SKILL.md:158` (§D9).
- `.worktreeinclude` behaviour is unchanged everywhere, because nothing intercepts creation. The
  first draft's partial gitignore-syntax replay in bash 3.2 is not written.
- The Express path's "No worktree isolation" note (`concept-to-code/SKILL.md:1849`, ADR-0017) is
  disclosed as contradicting `docs/GUIDA-USO-IT.md:117`, which says step E2 dispatches a coder with
  worktree isolation. Neither is in this SPEC's scope; recorded for a future issue rather than fixed
  here.
- Issue #175's subject — a dirty-tree check using `git diff HEAD --name-only`, which cannot see
  untracked files — becomes moot, because §D6 retires the check rather than correcting it. #175 is
  closed with that reason recorded, not by inference (R-18).
- SPEC F4's phrasing ("no worktree at all" on the Workflow path) is superseded by F16 and corrected
  in the SPEC at Task 1b, not silently reinterpreted.

## Measured facts annex (F13–F16)

Task 1 of the plan fills this table in the SPEC's own form. It is empty until then, deliberately:
**an empty row is the correct state before the probe runs, and a guessed row is not.**

**Measured 2026-07-28, CC 2.1.220, on branch `feat/176-worktree-isolation-contract` at `129d5e0`,
with `main` at `5518583` so the two are distinguishable.** Two of this ADR's own load-bearing
premises did not survive the probe. They are recorded here as measured, and D1/D2/D3/D4 are amended
above rather than quietly reinterpreted.

| # | Fact | How measured |
|---|---|---|
| F13 | The `WorktreeCreate` stdin payload carries exactly six fields: `session_id`, `transcript_path`, `cwd`, `prompt_id`, `hook_event_name`, `name`. **No `agent_type`. No `agent_id`. No `base_branch`/`worktree_branch`, and no `base`/`branch` either** — so SPEC F11's doc-sourced list and this ADR's assumed schema are *both* wrong. `name` is an opaque handle (`agent-a208432b04c69fff8`), not an agent type. | Capture hook + one `Agent(subagent_type="coder", isolation="worktree")` dispatch |
| F14 | **Exit 0 with empty stdout does NOT decline — it aborts the dispatch.** The error is `WorktreeCreate hook failed: hook succeeded but returned no worktree path`. A registered `WorktreeCreate` hook must return a path on every invocation; there is no fall-through to default git behaviour. | Same dispatch; capture hook returned empty stdout and the agent never started |
| F15 | **Confirmed, and it is the whole defect.** `baseRef: "fresh"` → worktree `HEAD` = `5518583` (the default branch) and `docs/architecture/ADR-0068-…md` is **absent** inside the worktree. `baseRef: "head"` → worktree `HEAD` = `129d5e0` (session `HEAD`) and the same file **exists**. | Two Agent-tool dispatches, `"fresh"` then `"head"`, reporting `git rev-parse HEAD` and a file-existence check |
| F16 | The Workflow path **does** create a worktree when `opts.isolation: 'worktree'` is passed explicitly (`.claude/worktrees/wf_<runid>-1`), and `worktree.baseRef` applies to it identically — `HEAD` = `129d5e0`, ADR present. Consistent with §D7/F4: frontmatter never reaches this path, so the value must be passed, and an earlier observation that "the Workflow path never creates a worktree" was made without passing it. | One `agent(prompt, { agentType: 'coder', isolation: 'worktree' })` Workflow dispatch |
| F19 | On the WORKFLOW dispatch path the orchestrator receives NO worktree identity: the run journal records only agentId, key, result and type, and the task notification carries no worktree block. Contrast the Agent-tool path, where F10's worktreePath/worktreeBranch are returned with every dispatch. The worktree IS created (F16) — only its identity is unreported. | Inspecting subagents/workflows/<run>/journal.jsonl after a Workflow dispatch |
| F20 | The Workflow worktree's path and branch follow a derivable convention — .claude/worktrees/<runId>-<n> and worktree-<runId>-<n>, with runId returned by the Workflow tool — but this is an observed naming convention, not a reported contract. | Probe C and the Task 9 evidence run |

**R-03 evidence, Agent-tool path (recorded 2026-07-28, Task 9 — evidence, not an assertion).**
Gathered from this feature's own implementation run rather than a synthetic demonstration, which
makes it stronger: roughly a dozen real `coder` and `tester` dispatches, every one of them
audited. In each case `git -C <worktreePath> rev-parse HEAD` equalled the feature branch's `HEAD`
at dispatch time — never the default branch's — and each worktree branch merged back cleanly with
no conflict. The tester → coder visibility property (R-09) was demonstrated end to end: Task 2's
tester wrote `worktree-isolation-contract.test.sh` in its own worktree, that branch was merged,
and Task 3's coder then read and executed that file from inside a *later* worktree. Before the
`baseRef` change this same probe forked from `5518583` with this chain's own ADR absent from the
worktree (F15), so the contrast is measured on the same repository within the same day.

**R-03 evidence, Workflow path (recorded 2026-07-28, Task 9).** One `agent()` dispatch with
`opts.isolation: 'worktree'` performing a real edit to this file. The worktree was created at
`.claude/worktrees/wf_339c4dca-fb6-1` on branch `worktree-wf_339c4dca-fb6-1`, forked from
`ad2b66c` — the feature branch's `HEAD` — and was located, committed and merged back by
`git worktree list` enumeration. The orchestrator learned the path only because the agent echoed
it in prose; nothing in the dispatch result carried it, which is F19 observed in practice rather
than only in the journal.

**Consequence for §D5 (measured 2026-07-28, Task 9).** The merge-back protocol reads
`worktreePath` and `worktreeBranch` "from the dispatch result (F10)", and that is true on the
Agent-tool path only. On the Workflow path the orchestrator must locate the worktree another way,
deriving it from the run id, or enumerating `git worktree list`, and relying on the naming
convention is exactly the kind of undocumented assumption this ADR exists to stop. This is a gap
in §D5 as written, found by Task 9's own evidence step.

**Consequences of F13 + F14, together (the two compound, and that is what matters).** R-04's
scoping predicate has no field to key on — not `agent_type`, not `isolation_mode`, not
`worktree_branch`, none of the fallbacks the plan's Task 1 wrote down. And because a registered
hook cannot decline, it cannot be scoped *by declining* either: it must create a worktree for
**every** worktree creation on the machine, and `WorktreeCreate` has no matcher. So §D1's two-layer
contract collapses to one layer for now: **`worktree.baseRef: "head"` is the mechanism, and it is
sufficient for the defect this ADR exists to fix (F15).** `worktree-create.sh` is blocked on a
discriminator that the event does not supply — see the amended §D2/§D3/§D4 and the plan's revised
Task 4.

### Annex addendum — F17, F18 (added 2026-07-28 during the revision)

Two further facts, established while ruling on the options F13/F14 left open. Their provenance is
labelled individually rather than assumed from the table above: **F17 is a re-read of the Task 1
capture artefact; F18 is a documentation read and is doc-sourced, not measured.** F18 is recorded
because the first draft's W2 and W3 both asserted documentation content that the documentation does
not contain, and the correction belongs next to the claims it corrects.

| # | Fact | How established |
|---|---|---|
| F17 | The `session_id` and `transcript_path` in the captured payload belong to the **dispatching (parent) session**, not to the subagent about to run: the id is this chain's own orchestrator session id, and the path is the top-level session transcript, not a `subagents/` path. The event therefore carries no handle on the agent being dispatched — which is what makes the `agent-write-scope.sh` / `write-scope-enforce.sh` identity-resolution technique inapplicable here (§A10). | Re-read of `~/.claude/state/worktree-probe/payloads.jsonl`, compared against the orchestrator session id |
| F18 | `code.claude.com/docs/en/hooks` § *WorktreeCreate* documents the input as the common fields plus **`name`**, a slug identifier for the worktree that "can be user-specified or auto-generated" (example: `bold-oak-a3f2`). It documents the output as: the command hook "must print the worktree path as the last non-empty line of stdout". **No `agent_type`, `agent_id`, `isolation_mode`, `base_branch` or `worktree_branch` field appears, and no decline / fall-through behaviour is described anywhere.** The event has no matcher support. Consistent with F13 and F14 on every point. | Documentation read, 2026-07-28, two independent retrievals of the same page |

## References

- `SPEC.md` — issue #176, measured facts F1–F12 (F4 superseded by F16; F11 superseded by F13)
- GitHub issue #176 (comment 5103916596 records F1–F3), issue #175
- `code.claude.com/docs/en/worktrees` — § *Isolate subagents with worktrees*, § *Choose the base
  branch*, § *Non-git version control*
- `code.claude.com/docs/en/hooks` — § *WorktreeCreate*, § *WorktreeRemove*
- `docs/vibe-coding-system.md:3207-3215` — blueprint sec. 12, `worktree.baseRef: "head"`
- `docs/vibe-coding-system.md:152` — the out-of-scope dismissal of `worktree.baseRef`, whose premise
  did not cover subagent worktrees
- ADR-0016 § *Cross-repo isolation constraint*, § *Probe findings* (superseded in part); § *Smoke
  Test Result* for the build-specific-evidence precedent
- ADR-0049 §D1, §D2, §D6 (§D2 superseded)
- ADR-0050 §D2, §D4, §D6 (§D4 superseded)
- ADR-0034 — forward-recorded correction precedent, and the reason it does not apply to this ADR
- ADR-0043 — check-direction lesson
- ADR-0039 correction 2026-07-27 — negative-case assertions need positive twins
- ADR-0041, ADR-0045 — instruction-versus-enforcement; `agent-write-scope.sh` reads `.agent_type`
  from the `PreToolUse` payload, which is the capability `WorktreeCreate` lacks
- ADR-0047 §D7 — a report nobody must act on is a report nobody reads
- ADR-0047 §A2, ADR-0048 — blast-radius rejection of `manifest-transition.sh` enforcement
