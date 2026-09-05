# ADR-0191 — The coder agent gets a hard-rules block, memory read-before-write, bounded reconnaissance, verification hygiene and a definition-of-done pass

- **Status:** Accepted
- **Date:** 2026-09-04
- **Issues:** requested directly in chat ("a more performant coder": cleaner code, faster, fewer
  mistakes, fewer tokens); no GitHub issue filed for the rewrite. One issue is filed separately for
  the memory-curation gap this measurement surfaced (see §Consequences).
- **Related:** ADR-0001 (pre-flight pattern classifier and its enforce hook), ADR-0004 (worktree
  isolation for parallel coders), ADR-0038 (native builds: LSP and MCP tools do not register in
  subagents), ADR-0062 (litter discipline, the pinned Cleanup bullet), ADR-0068 §D11 (worktree
  guard rejects absolute paths into the shared checkout), ADR-0130 (model choice for coder stays
  Sonnet), ADR-0184 (coder memory shards and `coder-memory-scope.sh`)
- **Out of scope, deliberately:** the enforce hook's 20-block window, `maxTurns`, the model, and
  `experimental.cacheTtl` (each rejected below with its reason)

## Context

The request was "a more performant coder". Before designing anything the premise was measured
(rule 13) against this repository's own session transcripts: 69 coder dispatches over the last 60
days, Claude Code 2.1.259, identified by the `PATTERN:` text or the `TEST-AUTHORING SCOPE` brief
marker (transcript records carry no agent-type field, so the identification is heuristic and the
counts below are a lower bound, not a census).

| signal | value |
|---|---|
| turns per run, average / maximum | 107 / 892 |
| context per turn, average | ~159k tokens |
| cache-read share of a run's cost | ~69% (output tokens ~6%) |
| `PATTERN:` blocks by the enforce hook | 83 in 34 runs: 54 with no header emitted at all, 29 with the header scrolled out of the 20-block window |
| Edit rejected for an absolute path into the shared checkout | 23 |
| Reads from the shared checkout vs inside the worktree | 273 vs 464 |
| test executions per run, average / maximum | 11.9 / 76 (one run repeated 8 commands four or more times) |
| tool results over 20k characters | 135 |
| context7 / LSP / eslint MCP calls, total | 1 / 1 / 0 (no eslint MCP server is configured on this machine) |
| coder memory shards written / read back / indexes curated | 2 / 3 runs / 0 |
| `old_string` mismatches on Edit | 0 |

Four conclusions drive the design.

1. **Cost is turns times context, not the system prompt.** `coder.md` was ~2.6k tokens; the
   average turn carried ~159k. Shortening the prompt changes instruction salience, not spend. What
   changes spend is fewer turns and smaller tool results.
2. **The two largest self-inflicted turn losses are instruction-following failures.** A blocked
   Edit costs a full turn plus a retry; 54 of 83 blocks had no header at all, and 23 edits went
   to the wrong tree. Both instructions existed, deep inside a 750-token section and an Edge Cases
   list at the bottom of the file.
3. **Verification hygiene is the main context lever.** Twelve test executions per run on average,
   135 results over 20k characters, and the same command re-run unchanged, are the shape of a
   run that reaches 892 turns.
4. **Two instructions produced nothing.** Steps 2b/2c told the coder to call context7 and LSP on
   every task; across 69 runs they were called once each. The eslint clause was never exercised.
   Memory was write-only: shards were produced by dispatches and consumed by nothing (rule 17),
   and the orchestrator-side curation step in `step5-implementation.md` sub-step 7b never produced
   an index.

The user decided, through a structured prompt on 2026-09-04: prompt fix only, the hook is
unchanged; the coder reads its own `topics/` at start and the curation gap gets a GitHub issue;
all six quality levers below; deploy to `~/.claude` after green tests behind a HITL gate.

## Decision

### D1 — A `## Hard rules` block, first thing after the role line

Six one-line rules, each of which a hook or the orchestrator enforces: PATTERN header as plain
text in the same message as the tool call; `pwd` once and edits by relative path only, the plan
read by the absolute path in the brief; never commit or `git add`, never touch unassigned test
files or `.claude/test-cmd`; a hook block is a stop-and-report signal; a plan that contradicts
reality is a stop-and-report; never weaken a test. The Pre-flight Pattern Classifier keeps its
heading, its four-row table, the CREATE/NEW alias and the "enforce hook scans assistant text, not
tool calls" clause; it loses two of four examples and four of eight discipline bullets, which
restated the hard rules.

### D2 — Memory is read before it is written

Process step 1 lists `.claude/agent-memory/coder/topics/` and reads every shard whose name
matches the task's id, slug or files. The write scope is unchanged (ADR-0184: uniquely-named
shard, never `MEMORY.md`, `coder-memory-scope.sh` enforces). This closes the producer/consumer
gap on the coder's side only; the orchestrator's curation gap is filed as an issue, not fixed
here.

### D3 — Reconnaissance is bounded

The files the plan names plus at most two neighbours for style; symbols located with `grep -n`
rather than whole-file reads; `Read` with `offset` and `limit` above roughly 300 lines; more than
that before the first edit must be justified in the report.

### D4 — Verification hygiene

Narrowest test first. Full suite at most twice: after the last edit, and once more only if that
run failed and something changed. Every verification command piped through `2>&1 | tail -n 40`
or counted with `grep -c '^FAIL'`; never a whole suite in context; never an unchanged command
re-run. The eslint instruction is conditional on `mcp__eslint__check_file` being present.

### D5 — Definition of done

`git diff` in the worktree read hunk by hunk against the plan's sub-steps; every sub-step maps
to a hunk or to an explicit "left out because"; no debug prints, no TODO added by the coder, no
unrelated hunk; the verification command and its exit code captured. The Output Format gains a
**Sub-steps** line; the Cleanup bullet (ADR-0062) is kept verbatim.

### D6 — Tooling instructions are conditional

The context7 and LSP step runs only when the plan introduces an external call and the tools are
in the tool list; when they are absent (native builds, ADR-0038) the step is skipped without
comment. An instruction to call an absent tool is a wasted turn on every dispatch.

### D7 — What is deliberately not changed

- **The enforce hook's 20-block window.** Widening it would let a single early header cover a
  batch of edits, which weakens the per-edit declaration ADR-0001 §2.4 was built for. The 29
  scrolled-out cases are addressed by D1's "same message" rule, not by a wider window.
- **`maxTurns`.** Step 5 has no handler for a partial result; a hard cap would turn an 892-turn
  run into a half-implemented plan with no report.
- **The model.** ADR-0130 measured Opus at +321% cost for the coder role; the failures above are
  instruction-following and hygiene, not capability.
- **`experimental.cacheTtl`.** The billing mode it depends on is not verifiable from this repo.

### D8 — Pinned by a planted harness

`coder-discipline.test.sh` (CD0 to CD10) pins each clause above by section-scoped, flattened
prose match (rule 3), with a `# plant:` per assertion (rule 2). CD8 is a size ceiling declared as
a vacuity guard (rule 10). CD10 (registration in `docs-ci.yml`) is unplantable because
`plant-check.sh` reaches `staging/` and `../docs/` only; the harness says so at the site.

## Alternatives considered

- **Widen the enforce hook window** to 40 or 60 blocks. Rejected: see D7; also, the majority
  failure (54 of 83) is a header never emitted, which no window catches.
- **A `maxTurns` cap** to bound the worst runs. Rejected: see D7.
- **Opus for the coder.** Rejected: ADR-0130.
- **Fix the orchestrator's memory curation step in the same change.** Rejected for scope: it is a
  Step 5 change in `concept-to-code`, with its own tests and its own measurement; the user chose
  the coder-side read plus an issue.
- **Shorten `coder.md` to under 1,600 tokens.** Attempted; the pinned Cleanup bullet
  (ADR-0062) and the classifier table are ~1,900 bytes on their own, and the new content (D1,
  D3, D4, D5) is the point of the change. The rewrite landed at 9,995 bytes against 10,469
  before, with the hard rules moved to the top; the size ceiling in CD8 is a vacuity guard, not a
  budget.

## Consequences

- **Instruction, not enforcement (rule 16).** D1 to D6 change the failure shape of the coder's
  prompt; they do not guarantee behaviour. The enforcement side is unchanged:
  `pre-flight-pattern-enforce.sh` for D1's first rule, the worktree guard for the second,
  `coder-memory-scope.sh` for the memory scope. A green `coder-discipline.test.sh` says the
  clauses are in the prompt, nothing more.
- **Pre-registered success criterion.** Over the next 30 or more coder dispatches, re-run the
  same transcript scan: the share of blocked edits with no header emitted should fall well below
  54 of 83, and absolute-path rejections should approach zero. If they do not, the failure is
  not salience and D1 should be revisited, not restated.
- **One live smoke dispatch** of the deployed coder on a throwaway one-file task, with the
  transcript read for three facts (first assistant text before the first Edit contains
  `PATTERN:`, all writes by relative path, test output piped through `tail`), is the acceptance
  check for the deployment. The coder's self-report is not evidence.
- **The memory-curation gap is filed as a GitHub issue** against `step5-implementation.md`
  sub-step 7b ("Memory shard curation") with the measured facts: 2 shards written, 0 indexes
  curated, 3 manual reads.
- **Sibling harnesses still pass**: `agent-memory-contract`, `cross-reference-form` (the
  `xref-exempt` line now lists the three example tokens that remain), `litter-discipline`,
  `worktree-isolation-contract`, `claude-md-condensation`, `pairs-completeness`,
  `coder-memory-scope`.
- **The blueprint** (`docs/vibe-coding-system.md` sec. 3.2) records the deployment in a dated
  note under the existing ones; the historical block above it is not corrected in place (rule 14).

## References

- `staging/plugin/agents/coder.md` (the rewrite)
- `staging/plugin/scripts/tests/coder-discipline.test.sh` (CD0 to CD10)
- `.github/workflows/docs-ci.yml` (shell-tests loop, `coder-discipline` appended)
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` sub-step 7b (the
  curation gap, not changed here)
- ADR-0001, ADR-0004, ADR-0038, ADR-0062, ADR-0068, ADR-0130, ADR-0184
