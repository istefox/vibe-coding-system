# ADR-0196: Codex-vs-Claude choice for the `coder` subagent dispatch

- Status: Accepted
- Date: 2026-09-07
- Extends: ADR-0187 (`codex-reviewer.sh` contract, manifest field pattern, never-silent fallback),
  ADR-0193 (per-dispatch-site ask, not chain-start), ADR-0194 (`codex-tester.sh`: the
  `workspace-write` sandbox, the touched-path scope check, exit 4, and the Workflow-path
  structural fix this ADR reuses)

## Context

The Codex backend has been extended one agent at a time. ADR-0187 gave `reviewer` a
`codex-reviewer.sh` running `codex exec -s read-only`; ADR-0193 moved the ask from chain start to
each dispatch site; ADR-0194 gave `tester` a `codex-tester.sh` running `codex exec -s
workspace-write -C <worktree>`, a post-run scope check, and a new exit 4. Stefano asked for the
same choice on the `coder` subagent (`staging/plugin/agents/coder.md`).

Two real dispatch sites exist, both in `concept-to-code` Step 5, both unconditional, both after
that task group's tester (ADR-0049 §D1). They are named here by their headings, never by line
number (rule 12):

- The Workflow (`pipeline()`) path's **Stage 2 — coder**, which pins `agentType: "coder"`, an
  explicit `model` (from `manifest.coder_model`), an explicit `effort` (`xhigh` per the effort
  table) and `isolation: "worktree"`.
- The **Single batch dispatch template** on the Agent-tool batch path, dispatched at item 2 of the
  numbered batch list, which pins `subagent_type: "coder"` and `isolation: "worktree"`; `model`
  only when `manifest.coder_model = "opus"`. The Agent tool has no `effort` parameter at all
  (ADR-0068 §D7).

**Three other places in the same file name a "coder" and are deliberately NOT in scope**, because
conflating them is the obvious way to get this wrong: the workflow smoke test's single probe agent
(`agentType: 'coder'`, whose entire purpose is to prove the Workflow tool dispatches subagents at
all), the tracer-bullet coder (`dispatch-site: tracer-bullet-coder`), and Step 6's fix agents,
which are dispatched with `agentType: "coder"` to repair tests and are distinguished from a Step 5
implementation coder by the TEST-AUTHORING SCOPE marker, not by the agent type
(`test-write-scope.sh`'s own comment says so). The ask this ADR introduces governs exactly two
sites.

**The first load-bearing difference from the tester case: the scope check's polarity inverts.**
`codex-tester.sh` can classify *every* touched path, because a tester legitimately touches test
files and nothing else — an allowlist with a definable population. A coder legitimately touches
arbitrary production paths, so no allowlist exists. What replaces it is a blocklist of five named
classes, which is weaker by construction and is disclosed as such (§Refinements R4).

**The second: `coder` is the only Step 5 agent whose discipline is hook-enforced rather than
prompt-instructed.** Measured 2026-09-07, not assumed — `staging/user/settings.json` wires three
`PreToolUse` hooks on `Edit|Write|MultiEdit` (`pre-flight-pattern-enforce.sh`,
`write-scope-enforce.sh`, `test-write-scope.sh`) and `sync-to-claude.sh` appends a fourth
(`coder-memory-scope.sh`) to the deployed `settings.json`. All four are PreToolUse gates; none is
PostToolUse. `test-write-scope.sh` keys its deny on `.agent_type == "coder"` **plus** the
TEST-AUTHORING SCOPE marker read from the first `user` entry of the dispatch transcript. A `codex
exec` subprocess satisfies neither condition: it is one opaque `Bash` tool call made by the
orchestrator, which carries no `agent_type` at all. Substituting the backend therefore does not
merely change which model writes the code — it removes an enforcement layer. That is the whole
reason this ADR carries five explicitly documented gaps rather than a parity claim.

**The third: Stefano's requirement is a live choice every time.** Model and reasoning effort are to
be chosen at each Step 5 entry, fresh and resumed alike. ADR-0193 and ADR-0194 both spent a
dedicated `*_asked` manifest field to make their gate fire exactly once per manifest; this feature
deliberately rejects that shape (§Refinements R7).

Verified live 2026-09-07 (rule 13), `~/.codex/models_cache.json`: both `gpt-6-astra` and
`gpt-5.6-sol` are present as model slugs, alongside `gpt-5.6-terra`, `gpt-5.6-luna` and others.
The `codex exec` flag shape (`-s/--sandbox`, `-C/--cd`, `--output-schema`, `-o/--output-last-message`,
`-c <key>=<value>`) is the one ADR-0194 verified live on 2026-09-06 and `codex-tester.sh` has used
since.

## Decision

**New script `codex-coder.sh`**, structurally mirroring `codex-tester.sh` (same flag-parsing shape,
same availability cascade via `codex doctor --json` → `.checks["auth.credentials"].status == "ok"`,
same "DID-NOT-RUN is the only fallback signal" rule, same `set -u` rather than `set -euo pipefail`
because the whole contract is classifying a non-zero `codex exec` exit):

```text
codex-coder.sh --worktree <dir> --brief <file> --out <file> --model <astra|sol> --effort <level>
```

- `--worktree <dir>` is required and passed as `-C <dir> -s workspace-write`. Never `-s read-only`
  (a coder that cannot write cannot work), never `danger-full-access`. This is the mitigation for
  the read-write risk: Codex's own sandbox, a runtime guarantee rather than an instruction it is
  asked to obey (rule 16).
- `--brief <file>` carries the same `step5-brief.sh` output the Claude coder receives at the same
  dispatch site — the batch's task text byte-exact, the `Budget:` file-map union, and
  ADR/SPEC/CLAUDE.md/DESIGN as paths with a stated reason.
- `--out <file>` receives the markdown report in `coder.md`'s own Output Format shape, so either
  backend's report is consumable identically by the dispatch site.
- **`--model` and `--effort` are both REQUIRED.** `--model` takes `astra` or `sol` and the script
  maps them to the slugs `gpt-6-astra` and `gpt-5.6-sol` respectively, passed as `-c model=<slug>`;
  anything else is exit 2. `--effort` is passed through verbatim as `-c model_reasoning_effort=<value>`.
  Omitting either is exit 2 — there is no default and no `~/.codex/config.toml` inheritance. This
  is a deliberate divergence from ADR-0194 §R2, and the reason is in §Refinements R2.
- The prompt embedded in the script is hand-ported from `coder.md`'s Hard rules / Process / Quality
  Standards / Output Format / Edge Cases (rule 6/12 duplication, declared in the script header
  exactly as `codex-reviewer.sh` and `codex-tester.sh` already declare their own ports).
- The reply is constrained with `--output-schema`, whose object carries **eight** properties:
  `files_modified`, `sub_steps`, `key_decisions`, `verification`, `drafted_commit`, `cleanup` (the
  six `coder.md` states), plus `plan_deviations` (the `PLAN DEVIATIONS:` disclosure ADR-0073 §D1
  requires of every Step 5 coder prompt) and `pattern_classification` (the post-hoc substitute for
  the pre-flight PATTERN header, §Refinements R10 and documented gap 2). Every object, including
  nested objects and array `items` whose type is object, carries `"additionalProperties": false` —
  without it `codex exec --output-schema` fails `invalid_json_schema` before the model runs
  (ADR-0187's live probe found this; the schema-walking harness pins it).

**Exit contract — a CHECKER, not a reporter (rule 5): the caller branches on the exit code, never
on whether stdout is empty.**

| Exit | Meaning |
| --- | --- |
| 0 | success; the report is at `--out`. Also covers "Codex wrote nothing" (a distinct `NOTE:` on stderr). |
| 2 | bad invocation: missing or unknown flag, missing required argument, unreadable `--brief`, unrecognised `--model`. |
| 3 | DID-NOT-RUN (rule 4). One line on stderr, `codex-coder: DID-NOT-RUN: <reason>`. The only signal a fallback ask may be gated on. |
| 4 | SCOPE-VIOLATION. The partial report is still written to `--out`; stderr names the violation CLASS and its subject. |

**Ask placement, both Step 5 sites, per-dispatch-site (ADR-0193's pattern):** one
`AskUserQuestion` in the orchestrator's own live turn, immediately before the Workflow/Agent-tool
branch, so one ask covers both paths — the same placement the reviewer and tester asks already use.
Options: `claude-sonnet` (default, today's behaviour) / `codex`. On `codex`, the **same gate turn**
additionally asks for the Codex model (`Astra` default / `Sol`) and the reasoning effort (`medium`
default / `low` / `high` / `xhigh` / `max` / `ultra`).

**The gate re-fires on every Step 5 entry, fresh and resumed alike.** No manifest field is read to
skip it. This is the one deliberate divergence from ADR-0194 §R8 and ADR-0193's
`step5_codex_review_asked` shape, and the reason is in §Refinements R7.

**Three new manifest fields, additive under the existing schema `1.4`, no version bump** (the same
treatment ADR-0193 and ADR-0194 gave their own fields):

- `use_codex_coder` (bool, default `false`) — records the LAST choice made. Informational only:
  because the gate always re-asks, this field is never read to skip the ask.
- `step5_codex_coder_model` (string, nullable; `astra` | `sol`).
- `step5_codex_coder_effort` (string, nullable; `low` | `medium` | `high` | `xhigh` | `max` | `ultra`).

There is deliberately **no** `step5_codex_coder_asked` field. Its entire purpose in the tester's
design is to skip a re-ask, which this feature rejects.

All three are seeded in `manifest-init.sh` and validated in `manifest-validate.sh` as new
conditional **Invariants 28 and 29** (the current highest is 27, measured 2026-09-07): Invariant 28
covers `use_codex_coder`'s boolean domain, copying Invariants 24/26 line for line; Invariant 29
covers the two string fields together, because they are one fact — the dispatch parameters of a
single choice, always written together — and its failure message names the offending field.

**On the `codex` branch the Workflow path drops the coder stage from `pipeline()` entirely** and the
orchestrator runs `codex-coder.sh` per task group in its own live turn, sequentially: creating the
worktree itself with `git worktree add`, resolving exit 3/4 through the ask while asking is still
possible, then running the existing merge-back and base-fork audit with `$WT`/`$WB` known by
construction. This is ADR-0194 §R5's fix applied unchanged, for a reason that is strictly stronger
here: a Workflow stage has no `AskUserQuestion` hook, and a coder that silently did not run leaves
nothing for the reviewer to review, nothing for Gate 5 to approve and nothing to commit.

**One resolution site for the exit contract, referenced twice** (`#### Codex coder exit-code
handling (ADR-0196)`), the same "stated once, referenced twice" idiom as `#### Merge-back and
base-fork audit` and `#### Codex tester exit-code handling`. On exit 3 or exit 4 the caller asks the
user: fall back to the Claude `coder`, or halt — never a silent fallback. Exit 4 additionally offers
"accept the write and continue", because the check is a heuristic and the operator, not the script,
decides. The accept option is qualified for one violation class (§Refinements R6).

## Refinements folded in after the draft

Each of these was settled while reading the code the plan touches, or follows from a decision the
SPEC fixed. They are decisions, not options.

**R1 — Report-format parity is prompt-instructed and schema-constrained, never validated.** The
script formats the returned JSON into `coder.md`'s Output Format markdown at `--out`, exactly as
`codex-reviewer.sh` and `codex-tester.sh` already do. There is no post-hoc parser asserting the
sections are present in the emitted markdown, and none will be added: that is the same trust level
both existing scripts have, and inventing a structural validator here would hold one backend to a
mechanism the other is not held to.

**R2 — `--model` and `--effort` are both required; this is the deliberate inverse of ADR-0194 §R2.**
ADR-0194 exposed `--effort` as optional and no `-m` at all, and disclosed the consequence: the
tester script silently follows `~/.codex/config.toml` wherever it goes, which on 2026-09-05 was the
top-cost `gpt-5.6-sol`/`xhigh` pair. A coder run is longer and writes more than a tester run, so
that exposure is strictly worse here. Requiring both flags converts a silent inheritance into an
explicit decision taken at the moment the gate fires. The allowlist policy is deliberately
asymmetric: `--model` is a **closed set** (`astra` | `sol`), because the script owns the
name-to-slug mapping and an unmapped name is a defect in the caller; `--effort` is a
**passthrough**, because `model_reasoning_effort` is Codex's vocabulary, not this repo's, and an
invalid value makes `codex exec` itself fail, which the script reports as exit 3 with the reason
rather than swallowing. Invariant 29 does close the effort set, because the manifest records what
the *gate* offered, which is a different question from what the *CLI* accepts (rule 6). Those two
vocabularies are therefore a declared duplication: the gate's six options and Invariant 29's
alternation must hold the same six tokens, and one harness assertion pins that they do.

**R3 — Schema stays `1.4`; three fields, and no fourth.** All three are additive and conditional; an
older manifest without them still validates, exactly as `use_codex_review` and `use_codex_tester`
were added under 1.4 without a bump. `manifest_schema_version` is not touched.

**R4 — The scope check is a blocklist of five named classes, not the tester's allowlist, and it
names the class it fired on.** The touched-path derivation is ADR-0194 §R4's method verbatim — the
union of `git diff --name-only`, `git diff --name-only --cached` and `git ls-files --others
--exclude-standard`, computed against a baseline captured immediately before `codex exec` runs, so
pre-existing dirt is never attributed to Codex. What changes is the classification. A coder's
legitimate output is production code at arbitrary paths, so "is every touched path allowed?" has no
answer; the question becomes "did any touched path fall into one of the classes the Claude coder is
mechanically prevented from touching?":

| Class | Subject | Which hook it stands in for |
| --- | --- | --- |
| `TEST-CMD` | `.claude/test-cmd` appears in the touched set | `coder.md` Hard rule 3 (orchestrator-managed, HITL gate) |
| `TEST-FILE` | any test-shaped path appears in the touched set | `test-write-scope.sh` |
| `MEMORY-INDEX` | `.claude/agent-memory/coder/MEMORY.md` appears | `coder-memory-scope.sh` |
| `MEMORY-SHARDS` | more than one NEW file under `.claude/agent-memory/coder/topics/` | `coder-memory-scope.sh` |
| `NEW-COMMIT` | the worktree's `HEAD` sha differs from the pre-run baseline | `coder.md` Hard rule 3 ("never commit") |

`NEW-COMMIT` is not a path-based check and is computed separately, from `git -C <worktree>
rev-parse HEAD` before and after. The test-shaped predicate is `codex-tester.sh`'s
`is_test_path()` reused unchanged (a path component of `tests`/`test`/`spec`/`__tests__`/`Tests`,
or a basename matching `test_*`/`*_test.*`/`*.test.*`/`*.spec.*`/`*Tests.swift`/`*Test.java`/
`conftest.py`) — the two scripts ask the *same* question of a path and disagreeing would be the
defect (rule 6), even though they draw the opposite conclusion from the answer.

"A test file not assigned to this coder's batch" resolves, for a Step 5 implementation coder, to
**any** test-shaped path: the tester owns every test file for the batch and `test-write-scope.sh`
denies the Claude coder all of them unconditionally when the marker is present. No `--allow-test`
flag is added; if a future caller genuinely assigns a test file to a Codex coder (a Step 6 fix
agent, say), that is a new flag on a new dispatch site and a named follow-up, not a default.

Zero touched paths is **not** exit 4 and not a fifth exit code: it is exit 0 with a distinct `NOTE:`
line on stderr, because "Codex wrote nothing" and "Codex wrote only in-scope files" are different
facts and collapsing them would let an empty run read as a clean one (rule 4). The touched-path
summary is printed on stderr in every case, so the harness reads the script's own derivation rather
than re-deriving it (two derivations that could disagree are the defect).

**R5 — On the `codex` branch the coder runs in the orchestrator's live turn on BOTH paths; the
Workflow path drops its coder stage.** ADR-0194 §R5, applied unchanged. Two consequences follow that
ADR-0194 did not have to state:

- **The `codex` branch is sequential where the Claude branch is parallel.** For the tester this cost
  wall-clock; for the coder it costs more of it, because the coder stage is the long one. Taken
  deliberately, for the same reason: a coder that cannot report its own failure is worse than a slow
  one.
- **The pipeline can degenerate to empty.** If the tester backend is also `codex` (ADR-0194 §R5
  already drops that stage) and `manifest.step5_review_mode` is not `checkpoint`, `pipeline()` has
  no stages left at all. In that case no workflow script is written and no `Workflow()` call is
  made: the whole of Step 5 runs as a sequence of orchestrator-turn subprocess calls with merge-backs
  between them. This is a legal state, not an error, and the dispatch site must say so — a
  half-written workflow script with zero stages is the failure mode of not saying it.

**R6 — The completion-fact fence is not run on the `codex` branch, and the `dispatch-site` marker
stays exactly where it is.** The Agent-tool path's coder dispatch is followed by the
`step5-batch-completion-gate` fence, which reads `.claude/dispatch/step5-batch-<B>.done` out of the
coder's worktree via `dispatch-state.sh` and HALTs on `NONE`. That fence exists because a non-teammate
`Agent` dispatch returns metadata only and the report arrives later as a notification (issue #435,
ADR-0139) — the tool result cannot carry the answer. A synchronous subprocess's exit code *is* the
answer, so on the codex branch the fence is skipped and the exit code is the completion fact.
Running it anyway would HALT every successful Codex run on a `NONE` token: a producer/consumer
mismatch (rule 17) that would look exactly like a broken coder. Two structural details follow:

- The `<!-- dispatch-site: step5-batch-coder class=isolated -->` marker is preserved verbatim, in
  place, and **without** an `exempt:` clause. `dispatch-completion.test.sh`'s `DC21` freezes the
  declared dispatch-site population against an exact baseline and its `DC25` asserts that this
  particular site carries no exemption; the Claude branch still gates on the helper, which is what
  `DC25` is about.
- No new `dispatch-site:` marker is added for the codex branch. ADR-0194 added none for
  `codex-tester.sh` and for the same reason: a `Bash` call to a script is not a subagent dispatch.
  Adding one turns `DC21` red.

The `NEW-COMMIT` violation class interacts with the merge-back block, and the exit-4 ask must say
so: the merge-back captures `BASE_SHA = git -C "$WT" rev-parse HEAD` and halts when it differs from
`$PRE`. A commit Codex made inside the worktree changes that sha, so choosing "accept and continue"
on a `NEW-COMMIT` violation walks straight into the base-fork halt one step later, reported with a
cause that is wrong ("the worktree forked from somewhere other than the feature branch"). The
exit-4 block therefore names the class and recommends halting for `NEW-COMMIT` specifically, while
leaving the operator the decision on the other four.

**R7 — The gate re-fires on every Step 5 entry, and `use_codex_coder` is a writer with no gating
reader — deliberately.** ADR-0193 added `step5_codex_review_asked` precisely because a seeded-false
field cannot be told apart from a declined-false one, and ADR-0194 copied the shape. Both were
solving "ask once per manifest". This feature's requirement is the opposite: a fresh choice at every
entry. The three-state problem therefore does not arise — nothing is ever skipped, so nothing needs
to distinguish "never asked" from "asked and declined". The cost is one extra prompt per resumed
Step 5 entry, which is the price of the model and effort choice being live rather than inherited;
an inherited `ultra` on a run nobody re-approved is a silent cost decision, which is the exact
defect ADR-0194 §R2 disclosed and this ADR exists partly to avoid. `use_codex_coder` is written and
never read as a skip condition, which is rule 17's shape and must therefore have its purpose stated
rather than left implicit: it is the audit record of the last choice, and the value the gate shows
back to the operator as context ("last run used Codex/Astra/high"). A harness assertion pins that
the gate block contains no skip clause keyed on it — the negative direction, because the positive
one is what would silently reappear if someone "fixed" the re-prompt.

**R8 — The autopilot skip is an instruction, not an enforcement (rule 16).** Under `--autopilot`
the ask does not fire and `use_codex_coder` stays at its seeded `false`, so an unattended run uses
the Claude coder exactly as today. Nothing enforces this — it is prose in the dispatch site, the
same disclosed limit ADR-0193 and ADR-0194 already carry for their own asks. Because no field
records that the ask was skipped, an autopilot run leaves no state behind at all, which is
consistent with a gate that never skips.

**R9 — The availability cascade now exists in three scripts; extraction is still deferred, and the
deferral is now more expensive.** `codex-coder.sh`'s cascade answers the *same* question as
`codex-reviewer.sh`'s and `codex-tester.sh`'s, and rule 6 says copies that could give different
answers are the defect. The correct end state is a shared `codex-common.sh`. It is not done here
because changing the two existing scripts is explicitly out of the SPEC's scope, and because a
shared source that breaks disables three consumers at once. Instead the duplication is declared in
the new script's header and a harness assertion pins the load-bearing needles — the rate-limit
vocabulary regex and the check-ordering fix from VCS-064, where a non-empty output file outranks the
rate-limit stderr grep — identical across all three copies. ADR-0194 §R7 made this argument for two
copies; at three, "extraction is a named follow-up" is a weaker sentence than it was, and it is
recorded as such rather than restated as though nothing changed.

**R10 — What ports from `coder.md`, and what cannot.** The prompt carries: the plan-fidelity rule
(Hard rule 5 — plan contradicts reality, stop and report), the never-weaken-a-test rule (Hard rule
6), relative-paths-only (Hard rule 2), never commit and never `git add` (Hard rule 3), the
TEST-AUTHORING SCOPE contract, the bounded-reconnaissance and verification-hygiene Process steps,
the Quality Standards, the memory shard write rule (one uniquely-named file under
`.claude/agent-memory/coder/topics/`, never `MEMORY.md`), and the Output Format. Three things
cannot port, and are documented gaps rather than omissions: the pre-flight `PATTERN:` header
(no per-tool-call hook exists on a `codex exec` run — replaced by the post-hoc
`pattern_classification` field, non-blocking), "a hook block is a signal, not an obstacle" (there
are no Claude hooks in a Codex run to be blocked by), and the tool-conditional steps that depend on
`LSP`, `mcp__eslint__*` and context7 (see Consequences).

**R11 — The two string manifest fields cannot be written with `manifest-set-flag.sh`.** That helper
validates its value as exactly `true` or `false` and exits 1 otherwise; it is boolean-only by
construction. `use_codex_coder` uses it as usual. `step5_codex_coder_model` and
`step5_codex_coder_effort` are written by bash `sed` substitution on the additive field — the
established precedent in this same file for `step5_mode`, `risk`/`task_type` and
`BASELINE_COMMIT`, and never with the `Edit` tool (which fights the manifest's read/write cycle).
The dispatch site states this in the negative form the repo already uses, which requires the
accompanying `path-rule-exempt: negated` comment so the path-rule checker does not read a helper
named-but-not-invoked as a broken reference.

## Alternatives considered

1. **Add a `--mode coder` flag to `codex-tester.sh` instead of writing a third script.** Rejected.
   The two answer different questions (rule 6): the tester's scope check is an allowlist over a
   definable population, the coder's is a blocklist over an undefinable one, and the two draw
   opposite conclusions from the same `is_test_path()` predicate — a test file is the tester's only
   legal output and the coder's canonical violation. Folding in `coder.md`'s contract would also
   make the "only test files" guarantee mode-conditional inside a script whose design leans on it
   being unconditional, which is the same reason ADR-0194 rejected folding the tester into
   `codex-reviewer.sh`.
2. **Persist the choice with a `step5_codex_coder_asked` field, mirroring the tester and the
   reviewer.** Rejected: it contradicts the requirement directly. It would also have to inherit the
   model and effort silently on a resumed run, which is exactly the cost-inheritance defect
   ADR-0194 §R2 disclosed and could not fix within its own scope. Consistency with the two earlier
   asks is a real cost of the rejection and is recorded as such — three Codex asks now exist and
   one of them behaves differently from the other two.
3. **Inherit model and effort from `~/.codex/config.toml`, as `codex-tester.sh` does.** Rejected
   (§Refinements R2). It is one line cheaper in the script and it silently binds the cost of the
   longest, most write-heavy dispatch in the chain to an interactive config file that nobody
   re-reads before a chain run. The tester carries this exposure by an approved scope boundary;
   propagating it to the coder would be choosing it.
4. **Run `codex-coder.sh` inside the Workflow `pipeline()` stage, preserving per-group parallelism,
   and resolve exit 3/4 by failing the stage and asking once after `Workflow()` returns.**
   Rejected (§Refinements R5). It keeps the one real advantage — parallelism — and puts the
   never-silent-fallback guarantee somewhere it cannot be honoured. A failed coder stage strands the
   task group with red tests, no implementation, an unmerged worktree and a reviewer stage with
   nothing to review. It would also require inventing `git worktree add` management inside a
   generated JS workflow script, whose only current worktree mechanism is `isolation: "worktree"` on
   the `agent()` call.
5. **Classify every touched path (an allowlist), as `codex-tester.sh` does.** Rejected: there is no
   population to allowlist. A coder's legitimate output is whatever the plan's `Budget:` lines and
   the task text imply, which the script cannot know without re-implementing `diff-budget-check.sh`
   inside it. The blocklist catches the five things the Claude coder is mechanically prevented from
   doing, and nothing else — weaker, bounded, and disclosed.
6. **Have Codex write the `.claude/dispatch/step5-batch-<B>.done` completion fact so the existing
   fence runs unchanged on both branches.** Rejected (§Refinements R6): the fence exists because an
   async `Agent` dispatch cannot carry its own report; a synchronous subprocess exit code can.
   Asking Codex to write the file would convert a mechanical check into a check on Codex's own
   self-report — an instruction wearing a gate's clothes (rule 16) — and it would add a sixth thing
   the scope check must then tolerate as a legitimate write.
7. **Extract `codex-common.sh` now, since this is the third copy of the availability cascade.**
   Rejected for this pass (§Refinements R9): the SPEC scopes changes to `codex-reviewer.sh` and
   `codex-tester.sh` out, and extraction cannot be done without touching both. The rejection is
   deference to an approved scope boundary, not agreement that a third copy is fine.
8. **Wire an `eslint` MCP server and authenticate Codex's `context7` entry as part of this
   feature.** Rejected: the eslint side has no source to wire (no server definition exists anywhere
   on this machine — see gap 4), and the context7 side needs an interactive login flow that an
   unattended feature branch cannot perform. Both are named follow-ups rather than silent gaps.

## Consequences

### Positive

- The choice is made where the information is: at Step 5 dispatch, with the plan written, the tests
  red and the batch size known — not at chain start on faith.
- Model and reasoning effort are chosen explicitly, every time. This is the first Codex dispatch
  site in the chain whose cost is a decision rather than an inheritance, and it closes, for the
  coder, the exposure ADR-0194 §R2 had to disclose for the tester.
- The sandbox (`workspace-write` + `-C <worktree>`) reuses a guarantee the coder dispatch already
  relies on (`isolation: "worktree"`), rather than inventing a new isolation boundary.
- The scope check gives the five hook-enforced coder rules a post-hoc mechanical successor. It is
  weaker than a PreToolUse deny, but it is a check, not an instruction — and it names the class it
  fired on, so the operator's exit-4 decision is informed rather than blind.
- On the codex branch the Workflow path's worktree identity stops being enumerated out of `git
  worktree list` (F19's documented weak spot) and becomes known by construction.
- `plan_deviations` survives the backend swap: the ADR-0073 §D1 disclosure that a human reads at
  Gate 5 is a schema field, not a prose convention Codex might drop.

### Negative

- **Documented gap 1 — three hook-enforced controls do not fire on Codex's internal edits.**
  `pre-flight-pattern-enforce.sh`, `write-scope-enforce.sh`/`test-write-scope.sh` and
  `coder-memory-scope.sh` are Claude `PreToolUse` gates on `Edit|Write|MultiEdit`; a `codex exec`
  subprocess's own edits are invisible to them, because the whole run is one opaque `Bash` tool call
  made by the orchestrator, which carries no `agent_type`. Mitigation: sandbox containment (real
  enforcement) plus the post-hoc scope check (a safety net). Neither is a preventive block — by the
  time the check runs, the write has already happened inside the isolated worktree.
- **Documented gap 2 — the PATTERN pre-flight classifier has no per-call equivalent.** Codex
  produces one final diff from a non-interactive run, not a sequence of hookable Edit/Write calls.
  It is downgraded to a post-hoc, self-reported, non-blocking per-hunk classification
  (`pattern_classification`) in the structured output. A self-report is not a gate, and this ADR
  does not pretend otherwise (rule 16).
- **Documented gap 3 — LSP has no Codex-side equivalent at all, permanently.** Live-checked:
  `codex mcp list` and `codex exec --help` expose no hover / find-references capable server, and
  Claude's own `LSP` tool is a native Claude Code capability, not an MCP server — so there is
  nothing to wire into `codex mcp add` even in principle. A Codex coder cannot do `coder.md`'s
  Process step 3 symbol check the way a Claude coder can. This is a hard gap, not a deferred one.
- **Documented gap 4 — `eslint` MCP parity is unresolved, not confirmed either way.** Live-checked
  this session: no `eslint` MCP server definition was found anywhere on this machine — not in
  `~/.claude/settings.json`, not in any installed plugin's catalog entry, not in `~/.claude.json`,
  not in a project `.mcp.json` (none exists). `coder.md`'s own Process step 3 already tolerates this
  class of absence ("If those tools are absent from your tool list … skip this step without
  comment"), so a Codex coder without eslint degrades exactly as a Claude coder already does in an
  environment where eslint MCP is not configured. Not a new failure mode; named because "we checked
  and could not find it" is a different fact from "it works".
- **Documented gap 5 — `context7` parity is partially wired, unauthenticated and unverified.**
  Live-checked: `codex mcp list` already shows a `context7` remote server registered
  (`https://mcp.context7.com/mcp`, `streamable_http`), `enabled` but `Not logged in`. Whether
  `codex exec` can reach it from inside a sandboxed non-interactive run, and whether an OAuth-style
  login is even possible in that context, was not tested — it needs an interactive login step
  outside this feature's boundary. Recorded as a named follow-up, not solved here.
- **The `codex` branch is sequential where the Claude branch is parallel** (§Refinements R5), and
  the coder is the long stage. On a plan with several task groups this is a real wall-clock
  regression, larger than the one ADR-0194 accepted for the tester.
- **Three more manifest fields**, two of which are strings that `manifest-set-flag.sh` cannot write
  (§Refinements R11). `manifest-init.sh` and `manifest-validate.sh` must move in lockstep (rule 17).
- **The gate asks on every Step 5 entry**, including resumed ones. This is the requirement, and it
  is also friction; it is the third Codex ask in the chain and the only one that does not fire once
  per manifest. An operator who reads the other two as the pattern will find this one surprising.
- **`use_codex_coder` has a writer and no gating reader** (§Refinements R7). Its purpose is stated
  rather than obvious, which is the weaker of the two ways to avoid a dead field.
- **The availability cascade now exists in three places** (§Refinements R9). The drift assertion
  makes divergence detectable, not impossible.
- **The scope check is a blocklist and will miss things an allowlist would catch** — a coder that
  rewrites an unrelated production file, deletes something, or edits a file no task named is not a
  scope violation by this script's definition. `diff-budget-check.sh` at the batch checkpoint and
  the human at Gate 5 remain the checks for that, exactly as they are for the Claude coder.
- **Not yet measured live** (rule 13, disclosed): whether `codex exec -s workspace-write` runs a
  project's test suite cleanly inside a worktree (the sandbox restricts network, which a
  dependency-installing suite may need), whether the eight-field report survives a real round trip
  without prompt drift, and whether `-c model=gpt-6-astra` is accepted by `codex exec` in the same
  form `-c model_reasoning_effort=` already is. The last of these is the cheapest to get wrong and
  the deferred dry run must check it first.

### Neutral

- `codex-reviewer.sh` and `codex-tester.sh` are untouched; `codex-coder.sh` is a new, separate
  script rather than a mode flag on either (Alternative 1).
- `manifest.coder_model` and the Workflow effort table keep governing the Claude branch and are
  simply not read on the codex branch. Neither is changed.
- `debugger`, `refactorer` and `researcher` keep having no backend choice (VCS-074, undecided).
- Status is `Accepted` while the live dry run is still outstanding, matching ADR-0187's and
  ADR-0194's own precedent. `Accepted` describes the decision, not the verification.

## Verification

A new harness parallel to the reviewer's and tester's own dispatch-gate harnesses, at
`staging/plugin/scripts/tests/codex-coder-dispatch-gate.test.sh`, assertion prefix `CK` (verified
free across `staging/` on 2026-09-07 — zero matches for `\bCK[0-9]+`). It is offline and hermetic:
every behavioural path is exercised against a **stub `codex` on `PATH`** inside a scratch `git init`
repository under `mktemp -d`, never against the real CLI, because this repo's convention is never to
spend Codex quota in CI. It covers the exit 0/2/3/4 contract; each of the five scope-violation
classes plus the zero-touch `NOTE:` case; the required-flag behaviour of `--model` and `--effort`
and the `astra`/`sol` → slug mapping; the three manifest fields end to end through `manifest-init.sh`
→ `manifest-validate.sh` → `manifest-set-flag.sh`; the single ask and the exactly-two dispatch sites
that point back at it (exact counts, never floors — rule 10); the deployed `hooks/` path both sites
name (rule 17, the VCS-063 lesson); and the negative assertion that the gate block carries no
manifest-driven skip clause. `codex-reviewer-schema.test.sh` is extended with one assertion walking
`codex-coder.sh`'s own `--output-schema` block, rather than copying its JSON walker into the new
file (rule 6).

Every assertion is declared with a `# plant:` line and must be seen RED before it is trusted;
`plant-check.sh` reports `NOFIRE` for a declaration whose assertion stays green (rule 2). `.github/`
is not a legal plant target (ADR-0151 §D11), which is why the harness's own CI registration carries
no assertion and is verified by grep and by the next CI run instead.

**Deferred, named, and required before the codex branch is trusted in a real chain run:** a live dry
run against a real worktree — confirm `-c model=<slug>` is accepted in that form, that
`workspace-write` + `-C` constrains Codex as expected, that a test suite runs inside that sandbox,
and that the eight-field report survives a real `codex exec` round trip. ADR-0187's live probe found
a real defect (`additionalProperties`) that no offline harness had caught, and ADR-0193's found a
second (a deployed-path mismatch that made every Codex branch fail with exit 127, which is not the
exit 3 the fallback keys off); there is no reason to expect this one to be cleaner. Record the
outcome as a dated `## Correction` here (rule 14), never by editing the sections above.

## References

- `staging/plugin/agents/coder.md` — the Hard rules, Process, Quality Standards, Output Format,
  Edge Cases and memory write scope this ADR requires Codex to match, and the source of the
  four hook-enforced controls gap 1 names
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` — the two dispatch
  sites (`**Stage 2 — coder.**` on the Workflow path, `**Single batch dispatch template**` on the
  Agent-tool path), the merge-back and base-fork audit block, and the completion-fact fence
- `docs/architecture/ADR-0194-codex-tester-choice.md` — the sandbox choice, the touched-path scope
  check (§R4), exit 4, and the Workflow-path structural fix (§R5) this ADR reuses; also §R2 and §R8,
  the two refinements this ADR deliberately inverts
- `docs/architecture/ADR-0193-codex-review-choice-at-dispatch.md` — the per-dispatch-site ask
  pattern, and the 2026-09-06 Correction recording what a wrong deployed path costs
- `docs/architecture/ADR-0187-codex-review-gate.md` — `codex-reviewer.sh` contract, manifest field
  pattern, and the `additionalProperties` defect its live probe found
- `staging/plugin/scripts/codex-tester.sh` — structural precedent for `codex-coder.sh`, and the
  source of the check-ordering fix §R9 pins against drift
- `staging/plugin/scripts/test-write-scope.sh` — the `agent_type == "coder"` plus marker deny whose
  absence on a Codex run is documented gap 1
- `staging/plugin/scripts/coder-memory-scope.sh` — the shard discipline the `MEMORY-INDEX` and
  `MEMORY-SHARDS` violation classes stand in for
- ADR-0049 §D1, §D3, ADR-0088 — generator/verifier separation, the TEST-AUTHORING SCOPE marker
- ADR-0068 §D5, §D6, §D9, §D11 — the merge-back and base-fork audit block the codex branch reuses
- ADR-0073 §D1 — the `PLAN DEVIATIONS:` disclosure carried into the output schema
- ADR-0139, issue #435, ADR-0159, issue #494 — why the completion-fact fence exists and why it does
  not apply to a synchronous dispatch
- ADR-0184, VCS-057 — coder memory shards
- ADR-0138, ADR-0154 — requirement-id scoping and the `(no-test:)` waiver, which govern how this
  feature's own SPEC ids may appear in test files
