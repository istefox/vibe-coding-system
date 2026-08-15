# ADR-0139 — a dispatched agent's completion is a filesystem fact, not a line in the transcript (issue #435)

- **Date:** 2026-08-15
- **Issue:** #435 — "Agent() returns before the agent runs, so Step 4.5 measures the working tree
  mid-dispatch and Step 5 checks PATTERN: DONE against metadata that can never carry it"
- **Supersedes:** nothing. **Amends:** ADR-0016 (the Workflow path is primary in name only),
  ADR-0057 §D3 (the tracer-bullet verdict gains a precondition).

## Status

Accepted.

## Context

### What changed under us

CC **2.1.232**: *"non-teammate agent spawns in interactive sessions now run in the background by
default"*. Measured here 2026-08-14, two `Agent()` dispatches issued in one message returned
immediately carrying only `Async agent launched successfully`, an internal id and an output-file
path. The agents' answers arrived afterwards as separate notifications, 4778 ms and 5224 ms later.

The measurement adds one fact the changelog line does not state: **it applies to this project's own
subagent types.** The probe used `general-purpose` and `doc-writer`, one of the eight agents in
`staging/plugin/agents/`, and they behaved identically.

### The three sites that break, and how they differ

| site | file | what it does after dispatch |
|---|---|---|
| A6, Step 5 batch coder | `concept-to-code/SKILL.md` | greps *the agent report text* for `PATTERN: DONE tasks=<N> files=<M>` |
| A1, Step 4.5 tracer bullet | `concept-to-code/SKILL.md` | runs `git diff --stat=999` and pipes it to `diff-budget-check.sh` |
| A2/A3, Gate 5.06 | `concept-to-code/SKILL.md` | "Wait for both agents", then merges two finding lists |

A6 fails **loudly**: the tool result never contains that line, so a healthy dispatch reads as
truncated and the chain halts every batch. A1 fails **silently and is the worst of the three**:
measured early the diff is smaller than the truth and the budget check returns `CLEAN`. No assertion
downstream can see it, because every assertion measures the right thing at the wrong moment. A2/A3
fail **cosmetically**: a finding may be missing from a report that gates nothing.

### The measurement that decided the design

**The Workflow path is immune, and it is not the path that runs.** A one-agent workflow probe
returned `resolved_type: "string"`, `contains_probe_token: true`, `contains_async_metadata: false` —
inside a workflow script `agent()` resolves to the agent's real return value.

But of this repository's 59 manifests, **52 carry `hook_verified: false`** and 7 carry true; of the
`step5_mode` values actually recorded, **32 are `agent_batch` against 2 `workflow`**. And
`concept-to-code/SKILL.md` makes it structural for unattended runs: the autopilot default records
`hook_verified = false` and takes the Agent-tool fallback, *"never takes the Workflow path unless
hooks were already verified true"*.

So ADR-0016 designates Dynamic Workflows as Step 5's primary dispatch; measured, that path ran twice
in thirty-four, and an autopilot run cannot reach it at all. **The defect lands on the path that
actually runs, by construction.**

### The Workflow path had already solved this

Its final subagent writes `.claude/step5-report.json` and the controller reads the **file**, with a
declared branch for absent: *"If the file is absent → fall back to `git diff + test run` directly
(do NOT re-dispatch)"*. A filesystem fact with an explicit absent-case. The Agent-tool path signals
through transcript text instead. This ADR carries the Workflow path's own answer across rather than
inventing a second one.

### The population resisted three mechanical derivations

`Agent({` finds 5 sites. `subagent_type` finds 8. Reading the files finds **15**, because most sites
are prose: `**Dispatch architect:**`, ``Dispatch `reviewer` again over the new state``. A harness
keyed on any of those needles would have reported coverage over a third of the population and looked
green doing it — rule 12 on the needle, rule 7 on the denominator, both in one place. That is a
design input and not a footnote: **the population cannot be derived from notation, so it is
declared.**

## Decision

### D1 — completion is a fact on disk, read through a checker

`staging/plugin/scripts/dispatch-state.sh <root> <dispatch-id>` prints exactly one
`<TOKEN>|<detail>` line: `NONE|`, `PENDING|`, `DONE|tasks=<N> files=<M>`, `PARTIAL|<raw>`,
`UNREADABLE|`. Exit `0` a token was determined, `2` bad invocation, `3` the check did not run.

It is a **checker** — the caller branches on the exit code, then on the token — deliberately unlike
`weakening-scan.sh` and `diff-budget-check.sh`, which are reporters invoked a few lines away in the
same Step 5 checkpoint. It **reports and does not decide**: A6 and A1 apply opposite policies to
`PENDING` (A6 must not advance, A1 must emit no verdict at all), the same argument
`manifest-field-state.sh` makes for refusing a verdict. It **never writes**, because a checker that
creates what it checks answers its own question.

### D2 — the agent always writes the fact; the class decides which root holds it

- `class=inline` — no worktree. The agent writes `<project_root>/.claude/dispatch/<id>.done`.
- `class=isolated` — `isolation: worktree`. The agent writes into its own worktree, and the caller
  passes `<project_root>/.claude/worktrees/agent-<id>/`, a path the orchestrator reads directly.

**Not the merge-back.** The first design made the orchestrator write the fact once the merge-back
block succeeded, reasoning that the merge-back is what makes isolated work visible. It does not
prove completion: the merge-back runs `git -C "$WT" status --porcelain` and `git merge`, and a
worktree caught mid-write merges cleanly and succeeds. It would have certified a half-finished batch
as `DONE` — the same false green in a new place.

### D3 — an unfinished tracer bullet produces no verdict, not a failing one

Gate 4.5 leaves `tracer_bullet_verdict` at `null` and halts. The value domain stays `green|amber|red`
and gains no fourth member: `h16-direction-check.sh` matches `^tracer_bullet_verdict: "(amber|red)"$`
and a new value would have to reach it and the value-domain guards. `null` is already the pre-verdict
state and is the honest one — an unfinished probe is not evidence about the slice in either
direction.

### D4 — the population is declared at the site, and checked in both directions

Each site carries `<!-- dispatch-site: <id> class=isolated|inline [exempt: <reason ≥ 40 chars>] -->`.
Thirteen are declared. ADR-0107's lesson — a declared population is a subset unless something checks
the complement — is answered by `DC24`, which runs backwards over every skill that dispatches at all
and fails on one that declares nothing. `DC21` freezes the declared set by identity rather than by a
floor, because ADR-0124 established that a floor with slack absorbs its own plant.

### D5 — two sites are converted, eleven are exempted, and the reason is per-site

Only A6 and A1 gate on the helper. **The `reviewer` agent's grant carries no `Write` tool**
(`staging/plugin/agents/reviewer.md`), so every reviewer dispatch is structurally incapable of
producing a completion fact. That is why Gate 5.06 keeps a wait *instruction* and says so in its own
text rather than pretending otherwise. The fix agents in `review-triage-fix` and `deep-refactor` are
exempt for a different reason: each is already followed by a `git diff` no-op detection, so an
unfinished agent is recorded as *no-op* rather than as *fixed* — the failure is conservative.

### D6 — which half is enforcement (rule 16)

The helper's answer and the fences' non-zero exits are mechanical. **That the orchestrator then stops
rather than pressing on is an instruction, exactly as it was before.** What changed is that the check
no longer consults a channel that cannot carry the answer. No assertion in
`dispatch-completion.test.sh` claims an orchestrator obeys a `HALT` line, and none should.

## Alternatives considered

**Add wait instructions at every site and change nothing else.** Cheapest, and it is rule 16 in its
purest form: a changed failure shape, not a guarantee. Rejected because #374 records that no
unattended run performs a review, so there is no second reader to catch a turn where the wait did not
happen.

**Force the Workflow path, which is immune.** Attractive — it deletes the broken path rather than
repairing it. Rejected for now because `hook_verified` is false on 52 of 59 manifests and the
autopilot default sets it false deliberately; forcing the path means fixing the smoke gate first,
which is a larger change than the one the defect requires. Recorded as the strategic direction.

**Convert all fifteen sites.** Rejected on the reviewer-grant fact in D5: eleven of them cannot
produce a completion fact at all, so "converting" them would mean adding prose and calling it
enforcement.

## Consequences

- `.claude/dispatch/` joins the gitignored transient state, as one permanent glob verified with
  `git check-ignore` rather than a literal grep (ADR-0094).
- The isolated class couples this to the merge-back's own correctness for path resolution, and #391
  (the merge-back escape check reads untracked files only) remains open and is **not** addressed
  here.
- **The plants for the five new assertions were verified in an isolated sandbox rather than through
  `plant-check.sh`**, because #433 reports 58 assertions already red in an unmutated sandbox, which
  would make a registry run say nothing about these. Each of DC7, DC10, DC11, DC21 and DC22 was seen
  RED against its declared substitution, on a clean baseline of `PASS=22 FAIL=0`. When #433 closes,
  the registry run should reproduce that and nothing here needs changing.
- One plant was wrong when first written and is worth recording: `DC7`'s needle was the *text of the
  error message*, which a substitution can change without changing the exit code, so the assertion
  would have stayed green. It now names the guard itself. An assertion whose plant cannot fail is
  the thing the plant registry exists to catch, and it caught this one.
- The first draft of `dispatch-state.sh` reproduced the defect it was written to prevent: it resolved
  `NONE` before anything that could exit 3, copying `manifest-entry-state.sh`, and with the state
  directory at `chmod 000` it reported "nothing was ever dispatched" for a batch that had been.
  A check that could not run reported a clean result. `DC7` pins the corrected ordering.

## References

- Issue #435; CC 2.1.232 changelog.
- ADR-0016 (Dynamic Workflows as Step 5's dispatch), ADR-0046/ADR-0076 (the exit-3 line),
  ADR-0057 §D3 (the tracer verdict is computed), ADR-0068 (worktree isolation),
  ADR-0083 (fence contracts), ADR-0094 (gitignore globs), ADR-0107 (a declared population is a
  subset), ADR-0108 (the plant registry), ADR-0124 (a floor absorbs its own plant).
- Open and depended upon: #391 (merge-back escape check), #433 (plant-check sandbox).
