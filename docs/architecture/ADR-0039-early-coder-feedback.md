# ADR-0039 — Early feedback on coder output: deterministic per-write checks plus per-task checkpoint review

**Status:** Implemented (D1-D4 and D5-D9 shipped; D5/D7/D8/D9 amended during implementation)
**Date:** 2026-07-24
**Author:** istefox
**Supersedes:** none
**Amends:** ADR-0016 (concept-to-code Step 5 dispatch: adds a review stage inside the step)
**Related:**

- ADR-0016 (`dynamic-workflows-step5`) — the Step 5 dispatch mechanics this ADR extends, and the
  source of the unresolved `hook_verified` blocker that shapes decision D5
- ADR-0020 (`autopilot-build`) and ADR-0022 (`nightly-autopilot`) — the unattended paths that must
  keep working without a human answering review findings
- `review-triage-fix` skill — the review→fix→re-review loop whose triage logic is reused, not
  reimplemented
- Blueprint `docs/vibe-coding-system.md` sec. 7 (hooks) and sec. 11 (concept→code workflow)

## 1. Context

Today the chain reviews code once the coder is finished. `reviewer` runs at Step 6 over the whole
implementation diff, and `review-triage-fix` runs afterwards over a bounded changeset. Both work,
and both fire late.

The cost of firing late is propagation. When a coder agent picks the wrong pattern in the first
file of an eight-file task, Step 6 sees that pattern eight times and the fix is eight edits instead
of one. On a multi-task plan the same mistake can cross task boundaries, because nothing between
tasks says "this was wrong".

A pattern circulating in the community answers this with a reviewer agent triggered on every write.
The idea is right about the problem and wrong about the granularity. Two things break at per-write
scope:

- **Cost.** An LLM review per Write/Edit multiplies the token bill of Step 5 by the number of file
  touches, on top of an orchestrator already running Opus 5.
- **False positives.** Mid-implementation code is legitimately incomplete. A helper written before
  its caller reads as dead code. A branch left for the next edit reads as a missing case. A gate
  that is wrong often enough gets ignored, and an ignored gate is worse than no gate.

So the useful split is by what the check can decide without context. Syntax, formatting, and
lint-level errors are decidable from one file and are always true. Design and correctness questions
need the whole task and are only answerable once a task is coherent.

The system already has the machinery for both halves. `auto-format.sh` is a PostToolUse hook on
`Edit|Write` that dispatches on file extension, so a sibling hook is a small addition rather than a
new subsystem. `reviewer` plus the RTF triage table already produce and route findings, so a
per-task review is a scheduling change rather than a ninth agent.

One constraint sits across both halves. ADR-0016 left hook propagation into workflow subagents
unverified, and that blocker is still open. Any design that puts the semantic check in a hook would
inherit it. Putting the semantic check on the orchestrator side avoids it.

## 2. Decision

**D1. Add `post-write-check.sh`, a deterministic PostToolUse hook on `Edit|Write`.** It runs a
fast, file-scoped check on the file just written and reports errors back to the model. Zero LLM
tokens. It sits after `auto-format.sh` in the hook order, so formatting noise is already gone by
the time it looks at the file.

**D2. The hook is advisory, never blocking.** It never fails the write and never stops the agent.
Mid-implementation incompleteness is normal, and blocking on it would stall the coder on code it
was about to finish. The feedback reaches the model as PostToolUse context, and the coder decides what to do with it.

**D3. The hook checks one file, never the project.** Per-file syntax check and per-file linter,
dispatched on extension the way `auto-format.sh` dispatches:

| Extension | Check |
| --- | --- |
| `*.py` | `ruff check` (errors only) |
| `*.ts`, `*.tsx`, `*.js`, `*.jsx` | `eslint` on the single file, no project type check |
| `*.swift` | `swiftlint lint --quiet` on the single file |
| `*.sh` | `shellcheck -S error` |
| `*.json`, `*.yml`, `*.yaml` | parse check |

Whole-project type checking is excluded by decision, not by omission. It is too slow to run on
every write and its output on a half-finished tree is mostly noise about symbols that do not exist
yet. Type checking stays where it is, at the end of the task.

**D4. Only error severity is reported.** The hook drops warnings and style suggestions. The hook's
value is that everything it says is true, and warning-level output on in-progress code is where
that property breaks. Every check above is pinned to its error-only flag.

**D5. Add a per-task checkpoint review to Step 5, on the orchestrator side.** When a coder agent
finishes a plan task, the orchestrator dispatches `reviewer` scoped to that task's diff alone,
before the next task starts. The orchestrator triages the findings with the existing RTF severity table. This lives
in the orchestrator rather than in a hook precisely because of the ADR-0016 blocker: dispatch is
something the orchestrator controls and can verify, hook propagation into workflow subagents is
not.

**D6. Checkpoint review does not serialize parallel work.** In workflow mode it is a `pipeline()`
stage, so task B is still being implemented while task A is under review. It is never a barrier.
In the Agent-tool fallback path it fires per agent completion, not per batch completion.

**D7. Severity governs what blocks.** P1 and P2 findings are fixed before the next task begins. P3
findings go on the record and defer to Step 6, where they join the whole-diff review. This keeps the
checkpoint cheap and leaves the broad pass in place.

**D8. Manifest field `step5_review_mode`, values `checkpoint` or `none`.** Default is `checkpoint`
when the plan has three or more tasks and `none` below that, where the whole diff is small enough
that Step 6 alone is adequate. Additive field, no schema version bump, same treatment as
`step5_mode` under ADR-0016.

**D9. On unattended paths the checkpoint runs in fix-or-halt mode.** `autopilot-build` and
`nightly-autopilot` have no human to answer findings. A P1 finding that the fixing agent cannot
resolve in one cycle trips the existing circuit breaker and halts with a partial report. It never
prompts and never silently continues.

## 3. Alternatives considered

**LLM reviewer on every write (the community pattern as stated).** Rejected on the two grounds in
section 1: token cost proportional to file touches, and false positives on incomplete code that
train the coder to ignore the channel. D1 plus D5 covers the same ground, because the cases a
per-write reviewer catches reliably are exactly the deterministic ones.

**Blocking hook instead of advisory.** Rejected. A blocking check on partial code stops legitimate
work, and the failure mode is a coder that cannot proceed rather than a coder that produced a bug.

**Checkpoint review as a hook rather than an orchestrator dispatch.** Rejected while the ADR-0016
blocker is open. A hook that may or may not fire inside workflow subagents is a review stage whose
coverage cannot be stated.

**Status quo, Step 6 review only.** Rejected as the thing being fixed, but it stays the fallback:
if `step5_review_mode` is `none`, the chain behaves exactly as it does today.

**Whole-project type check in the hook.** Rejected per D3. Correct signal, wrong moment.

## 4. Consequences

**Positive.**

- Deterministic errors surface within a second of the write, at no token cost.
- A wrong pattern is caught at the end of the task that introduced it rather than after seven more
  files inherited it.
- Step 6 receives a cleaner diff, so the whole-diff review spends its budget on design rather than
  on lint.
- This invents nothing new. D1 is a sibling of `auto-format.sh`, D5 reuses `reviewer` and the RTF
  triage table.

**Negative and accepted.**

- Step 5 token cost rises by roughly one reviewer dispatch per plan task. D8's threshold and D7's
  P3 deferral bound it, but the increase is real and should be measured with `usage-report.py`
  before the default in D8 is considered settled.
- Wall-clock per task grows by the review dispatch. D6 keeps this off the critical path when tasks
  run in parallel, but a strictly sequential plan pays it in full.
- The hook depends on whichever linters happen to be installed. Like `auto-format.sh`, a missing
  tool means the check is skipped silently, so coverage is best-effort and must not be described as
  a guarantee.

**Open, to be resolved during implementation.**

- ~~The exact PostToolUse feedback channel needs a live check.~~ **Resolved, see the addendum.**
- Whether P2 should block the next task or defer alongside P3 is a judgment call that wants data
  from the first few runs.

## 4b. Addendum 2026-07-24 — what implementing D1-D4 changed

D1-D4 shipped as `staging/plugin/scripts/post-write-check.sh` with a 12-case harness. Three things
the decision section got wrong or left open are corrected here. D5-D9 are not implemented yet and
ship separately.

**The feedback channel is `hookSpecificOutput.additionalContext`, and only that.** Verified against
`code.claude.com/docs/en/hooks`. Exit-2-with-stderr does reach the model, but the tool has already
run, so it presents as a hook failure — the wrong signal for a check that is deliberately
non-blocking under D2. Plain stdout on exit 0 was never a candidate: for every event except
`UserPromptSubmit`, `UserPromptExpansion` and `SessionStart` it goes to the debug log and the model
never sees it. That is the bug that made `post-md-tells-hint.sh` a no-op for its entire life
(ADR-0040). The hook emits only the nested envelope, not the dual form
`prompt-en-prose-detect.sh` uses — that dual form exists for `UserPromptSubmit` for a historical
reason (ADR-0034 D4), and for `PostToolUse` the nested shape is the only documented one.

**D3's engine table and D4's severity rule were both wrong, and they were wrong together.** The
table named `ruff`, `eslint`, `swiftlint` and `shellcheck`. D4 said "error severity only", assuming
that a linter's severity tracks correctness. It does not: it tracks configuration.

Two linters, two false positives, found one after the other.

- `swiftlint` fails `let x = 1` with `identifier_name` at severity `error`, because the name is
  under three characters. Caught by the local harness.
- `shellcheck` fails `echo ok` with `SC2148` at severity `error`, because the fragment has no
  shebang. Invisible locally, where shellcheck is not installed, and red on the CI runner, where it
  is. The CI found the second instance of the same class after the first had already been fixed.

So external linters are removed from the hook entirely, not tuned. Every engine now answers one
question, does this file parse: `bash -n`, `py_compile` with `cfile=/dev/null`, `jq empty`,
`yaml.safe_load`, `swiftc -parse`. Style belongs to `auto-format.sh` and to the reviewer.

A second property falls out of this. The hook's verdict no longer depends on which tools happen to
be installed, so it behaves identically on the author's machine and on CI. The shellcheck case is
precisely what that divergence costs when it is not closed.

Two smaller implementation notes. `py_compile` writes `__pycache__` next to the source unless
`cfile` is redirected, so the check would have littered every tree it inspected; a test asserts
nothing is left behind. And the eslint branch resolves `package.json` upward from the edited file
rather than reading `$PWD`, because the hook's working directory is the session's and need not be
the edited file's project.

## 4c. Addendum 2026-07-25 — what implementing D5-D9 changed

D5-D9 shipped as a `step5_review_mode` manifest field plus a conditional block in both Step 5
dispatch paths, with a 13-case harness. Four decisions were amended before writing any of it.

**D5 is review-only. The checkpoint does not fix.** The original text had the checkpoint review,
triage and fix before the next task began, reusing `review-triage-fix`. That turned out not to be
buildable as written: RTF reviews "over the recent changes" with no per-task scope, and its state
file is per-branch. Invoking it at each checkpoint on a shared tree means the second checkpoint
re-reviews the first task's diff. It was never designed to run N times inside one Step 5.

The alternatives were reimplementing RTF's triage-and-fix core inside `concept-to-code`, leaving
two fix paths to drift apart, or changing RTF itself, which is its own ADR. Neither is worth it
for the benefit at stake. So the checkpoint reviews and stops there: BLOCKER and MAJOR findings go
into the next task's coder brief as "found in task N, do not repeat this", MINOR and NIT wait for
Step 6, where RTF runs the full cycle exactly as it does today.

This still delivers what section 1 asked for. The complaint was that "nothing between tasks says
this was wrong". Now something does.

**D7 used a severity scale that does not exist on this path.** P1/P2/P3 comes from `deep-refactor`
(ADR-0018). The `reviewer` agent emits BLOCKER/MAJOR/MINOR/NIT and RTF's triage table consumes
those. BLOCKER and MAJOR are the actionable pair at the checkpoint; MINOR and NIT defer.

**D8 defaults to `none`.** Not `checkpoint` on plans with three or more tasks. D8 itself calls that
threshold an unmeasured guess, and turning on a per-task reviewer dispatch by default is a token
cost nobody has measured yet. It is opt-in with no new gate in the chain,
flipped by a `sed` substitution on the additive field — the same mechanism `step5_mode` already
uses, and for the same reason: `manifest-set-flag.sh` accepts only `true|false`, and widening a
shared helper to take arbitrary values would drop the guard that protects every boolean flag it
sets. The generated manifest carries the exact command as a comment; with no gate, that comment is
the only place a human finds it. `usage-report.py` supplies the data before the default is revisited.

**D9 collapses.** "Fix-or-halt on unattended paths" presupposed a fix cycle. With review-only there
is nothing that can remain unresolved, so nothing can halt; findings land in the report. And since
`autopilot-build` and `nightly-autopilot` reuse Step 5 by reference rather than duplicating it,
a `none` default means neither skill needed a single edit.

One implementation note worth keeping. Both dispatch paths gate on the same field and state the
review-only contract independently, and a test asserts both sites exist. If only one carried it, a
chain would behave differently depending on whether `hook_verified` had flipped the Workflow path
on — a difference nobody would think to look for.

## 5. References

- ADR-0016 `docs/architecture/ADR-0016-dynamic-workflows-step5.md`
- ADR-0020 `docs/architecture/ADR-0020-autopilot-build-skill.md`
- ADR-0022 `docs/architecture/ADR-0022-nightly-autopilot-goal.md`
- `staging/plugin/scripts/auto-format.sh` — the hook pattern D1 follows
- `staging/user/settings.json` — PostToolUse `Edit|Write` chain D1 joins
- `~/.claude/skills/review-triage-fix/SKILL.md` — triage severity table reused by D7
