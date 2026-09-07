# ADR-0194: Codex-vs-Claude choice for the `tester` subagent dispatch

- Status: Accepted
- Date: 2026-09-06 (drafted Proposed 2026-09-06, accepted the same day after the design interview
  below — the refinements in §Refinements are user-approved decisions, not open questions)
- Extends: ADR-0187 (`codex-reviewer.sh` contract, manifest field pattern, never-silent fallback),
  ADR-0193 (per-dispatch-site ask, not chain-start)

## Context

ADR-0187/ADR-0193 gave the `reviewer` agent a Codex backend: `codex-reviewer.sh` shells `codex exec
-s read-only` and writes a markdown report in `reviewer.md`'s own Output Format shape to `--out`.
Contract: exit 0 success, exit 2 bad invocation, exit 3 DID-NOT-RUN (the only signal a caller may
gate a fallback-to-Claude ask on — never a silent fallback). The ask itself lives per-dispatch-site
(`review-triage-fix` Step 0 item 6; the two Step 5 checkpoints in `concept-to-code/references/
step5-implementation.md`), not at chain start.

Stefano asked for the same choice on the `tester` subagent (`staging/plugin/agents/tester.md`).
Two real dispatch sites exist, both in `concept-to-code` Step 5, both unconditional, both always
before the paired coder (ADR-0049 §D1 generator/verifier separation — tester briefed from SPEC/
plan, never implementation):

- The Workflow (`pipeline()`) path's **Stage 1 — tester**, which pins `agentType: "tester"`,
  `model: "sonnet"`, `effort: "xhigh"`, `isolation: "worktree"` (around line 583 as of 2026-09-06).
- The **Tester batch dispatch template** on the Agent-tool batch path, which pins
  `subagent_type: "tester"` and `model: "sonnet"` only — the Agent tool has no `effort` parameter
  (ADR-0068 §D7) — around line 1770 as of 2026-09-06.

**The load-bearing difference from the reviewer case:** `codex-reviewer.sh` is read-only by
construction (`-s read-only`) because `reviewer` never writes anything. `tester` must create/edit
test files and run the suite — a read-only sandbox cannot do the job at all. Stefano's own framing
of the requirement: *"la cosa importantissima è che codex generi un report completo come quello di
claude code"* — parity of the **report** (`tester.md`'s Output Format: Tests added, Run result,
Coverage, Bugs found, Requirement IDs covered, Sub-steps) is the hard requirement; how Codex is
sandboxed while producing it is an implementation choice, not something he specified.

A second, unrelated request rides along: lower the tester's default Claude effort pin from `xhigh`
to `high`, unconditionally and regardless of backend, to cut the cost of every tester dispatch.
It is recorded here because it touches the same two dispatch sites, not because it is part of the
backend choice.

Verified live against the installed `codex` CLI (rule 13 — not assumed from `codex-reviewer.sh`'s
comments alone, since that script only ever used `-s read-only`):

```text
codex exec --help
  -s, --sandbox <SANDBOX_MODE>   [possible values: read-only, workspace-write, danger-full-access]
  -C, --cd <DIR>                 Tell the agent to use the specified directory as its working root
      --add-dir <DIR>            Additional directories that should be writable alongside the primary workspace
      --output-schema <FILE>     Path to a JSON Schema file describing the model's final response shape
  -o, --output-last-message <FILE>
```

`workspace-write` combined with `-C <worktree-dir>` exists and scopes writes to exactly the
directory Codex is told is its root — the same worktree isolation `tester`'s own dispatch already
requires (`isolation: "worktree"` on the Workflow path; the Agent-tool path briefs worktree
write-path rules explicitly per the batch-dispatch template).

Also verified live 2026-09-06, `~/.codex/config.toml`: `model = "gpt-5.6-terra"`,
`model_reasoning_effort = "medium"`. That is the same tier `codex-reviewer.sh` pins explicitly
(`-m gpt-5.6-terra -c model_reasoning_effort=medium`, VCS-064) — today the two coincide, but for
opposite reasons: the reviewer's is a pin, the tester's is an inheritance. See §Refinements R2.

## Decision

**New script `codex-tester.sh`**, structurally mirroring `codex-reviewer.sh` (same flag-parsing
shape, same availability cascade via `codex doctor --json` → `auth.credentials.status == "ok"`,
same exit 0/2/3 contract, same "DID-NOT-RUN is the only fallback signal" rule):

```text
codex-tester.sh --worktree <dir> --brief <file> --out <file> [--effort <value>]
```

- `--worktree <dir>` is required and is passed to `codex exec` as `-C <dir> -s workspace-write`
  (never `-s read-only`, never `danger-full-access`). This is the mitigation for the new
  read-write risk: Codex's own sandbox, not an instruction it is asked to obey (rule 16 —
  "an instruction is not an enforcement," the same reasoning `codex-reviewer.sh`'s own header
  already states for its read-only choice). Codex cannot touch anything outside the dispatch's own
  worktree, exactly as `isolation: "worktree"` already constrains the Claude-side tester.
- `--brief <file>` carries the same brief content the Claude `tester` agent receives at both
  dispatch sites — the `step5-brief.sh` output already materialized for that task group (SPEC
  requirement IDs / Success Criteria / plan task text per ADR-0049 §D1 and ADR-0088; never
  implementation files, same generator/verifier separation applies to Codex too).
- `--effort <value>` is optional and passed through verbatim as `-c model_reasoning_effort=<value>`.
  Omitted entirely when not given, so `~/.codex/config.toml`'s own value governs. No `-m/--model`
  override is exposed — see §Refinements R2 for the reason and the disclosed risk.
- The prompt embedded in the script is hand-ported from `tester.md`'s Core Responsibilities /
  Process / Quality Standards / Output Format / Edge Cases (rule 6/12 duplication, declared here as
  `codex-reviewer.sh` already declares its own reviewer.md port) and explicitly instructs Codex:
  never modify production code (only test files), run the suite and report the exact command and
  pass/fail counts, and produce the six-field Output Format `tester.md` defines — Tests added, Run
  result, Coverage, Bugs found, Requirement IDs covered, Sub-steps — written verbatim to `--out` so
  either backend's report is consumable identically by the dispatch site.
- **Post-run verification, the one piece with no reviewer-side precedent to copy:** after `codex
  exec` returns 0, `codex-tester.sh` re-derives the set of paths Codex touched inside the worktree
  and fails the invocation (a new exit 4, "codex wrote outside test scope") if any of them is not a
  test file by the project's own test-file convention (file name/path pattern, the same way
  `tester.md`'s framework detection already works). This is a second, independent check on top of
  the sandbox, not a replacement for it — the sandbox prevents writes outside the worktree; this
  catches a write inside the worktree that lands on production code, which `workspace-write` alone
  does not forbid. Exit 4 is a new caller-visible state distinct from 2/3, surfaced to the user
  rather than silently discarded (rule 4/5 — a checker call site must branch on it, not just log
  it). How the touched-path set is derived is §Refinements R4, and it is not the draft's original
  `git diff --name-only` alone.

**Ask placement, both Step 5 sites, per-dispatch-site (ADR-0193's pattern, not a chain-start
gate):** one `AskUserQuestion` immediately before the Step 5 tester dispatch, in the orchestrator's
own live turn and before the Workflow/Agent-tool branch, so one ask covers both paths — the same
placement the reviewer's own Step 5 ask already uses. Options: `claude-sonnet` (default) / `codex` /
`claude-opus` — backend and Claude model only, never a Claude *effort* choice (kept pinned, matching
the reviewer's Step 5 precedent, which never exposed effort either). New manifest fields, **additive
under the existing schema `1.4`, no version bump** (the same treatment ADR-0193 gave the reviewer's
own two fields):

- `use_codex_tester` (bool, default `false`) — parallel to `use_codex_review`.
- `step5_codex_tester_asked` (bool, default `false`) — parallel to `step5_codex_review_asked`,
  same three-state reasoning ADR-0193 already established (seeded-false and declined-false are
  indistinguishable without a dedicated field).

Both seeded in `manifest-init.sh`, both validated in `manifest-validate.sh` as new conditional
**Invariants 26 and 27** (the current highest is 25). The ask is skipped under `--autopilot`, same
disclosed limit as the reviewer ask (instruction, not enforcement — rule 16).

On Codex exit 3 (DID-NOT-RUN) or exit 4 (wrote outside test scope), the caller asks the user:
fallback to Claude `tester`, or halt — never a silent fallback, identical to the reviewer contract.
Exit 4 additionally offers "accept the write and continue", because a false positive from the
file-classification heuristic is a real possibility and the operator, not the script, decides.

**Effort pin lowering (independent of the backend choice, applies unconditionally):** `xhigh` →
`high` at **three** sites, not the two the SPEC enumerates — `staging/plugin/agents/tester.md`
frontmatter, the Workflow path's explicit `effort: "xhigh"` pin, and the effort table in
`step5-implementation.md` whose own adjacent note says *"If an agent's frontmatter changes, this
table is the second place to update — they are not linked, and a mismatch here silently overrides
the file."* Leaving the table at `xhigh` would make the change self-cancelling. See §Refinements R6.
The Agent-tool batch path is untouched: it already omits `effort` because the tool has no such
parameter (ADR-0068 §D7).

## Refinements folded in after the draft

Each of these was settled in the design interview after this ADR was first written as Proposed, or
found while reading the code the plan touches. They are decisions, not options.

**R1 — Report-format parity is prompt-instructed and schema-constrained, never validated.** The
script constrains `codex exec` with `--output-schema` (six fields matching `tester.md`'s Output
Format) and formats the returned JSON into markdown in the script, exactly as `codex-reviewer.sh`
already does. There is **no** post-hoc parser asserting the six sections are present in the emitted
markdown, and none will be added: that is the same trust level `codex-reviewer.sh` has for its own
`reviewer.md` parity, and inventing a structural validator here would be a mechanism neither backend
is held to. Every object in the schema carries `"additionalProperties": false` — without it
`codex exec --output-schema` fails with `invalid_json_schema` before the model runs (found live
2026-09-02, ADR-0187 Correction; regression-locked by `codex-reviewer-schema.test.sh`, extended here
to walk this script's schema too).

**R2 — `--effort` is exposed; `-m/--model` is not; the resulting cost drift is disclosed, not
solved.** `model_reasoning_effort` is a free-text passthrough with no client-side allowlist: an
invalid value makes `codex exec` itself fail non-zero, which the script reports as exit 3 with the
reason, so the failure is visible rather than silently ignored. A model override is deliberately out
of scope because the capability ranking of the `Sol`/`Terra`/`Luna` family was not verified live.
**The disclosed consequence, which the SPEC's own out-of-scope note does not state:** with no `-m`
and no default `--effort`, this script inherits whatever `~/.codex/config.toml` holds at run time,
while `codex-reviewer.sh` pins its tier explicitly. Today both resolve to `gpt-5.6-terra`/`medium`,
so nothing differs. On 2026-09-05 that same config held `gpt-5.6-sol`/`xhigh` — the top-cost
combination, and the exact defect VCS-064 fixed for the reviewer by pinning. A tester run is
multi-turn and writes files, so it costs strictly more than a review run: if the interactive config
moves back, this script silently follows it. The remedy is one line (`-m gpt-5.6-terra` in the
`codex exec` call, or the dispatch sites passing `--effort medium`) and is deliberately **not**
taken here, because the SPEC scopes it out. It is recorded as a named follow-up rather than left to
be rediscovered from a quota bill.

**R3 — Schema stays `1.4`; the draft's "schema bump" wording was wrong.** Both new fields are
additive and conditional; an older manifest without them still validates, exactly as
`use_codex_review` was added under 1.4 without a bump. Invariants 26 and 27 are conditional on the
field being present, matching Invariants 24/25 line for line.

**R4 — The scope check reads untracked files, not only `git diff --name-only`.** The draft named
`git diff --name-only` alone. That would have missed the single most likely violation: a tester's
primary output is *new* files, and a brand-new production file is untracked, so `git diff` does not
list it at all. The check therefore takes the union of `git diff --name-only`,
`git diff --name-only --cached` and `git ls-files --others --exclude-standard`, computed against a
baseline captured immediately before `codex exec` runs so that pre-existing dirt in the worktree is
never attributed to Codex. A path in the post-run set and not in the baseline set is a path Codex
touched. Zero touched paths is **not** exit 4 — it is exit 0 with a distinct `NOTE:` line on stderr,
because "Codex wrote nothing" and "Codex wrote only test files" are different facts and collapsing
them would let an empty run read as a clean one (rule 4).

**R5 — On the `codex` branch, the tester runs in the orchestrator's live turn on BOTH paths; the
Workflow path drops its tester stage.** A Workflow script has no `AskUserQuestion` hook. For the
*reviewer*, ADR-0193 could live with that: a skipped checkpoint review is advisory and the chain
continues. For the *tester* it is unlivable — a tester that did not run leaves the coder dispatched
next with no red tests, which is the one thing the whole Step 5 ordering exists to prevent, and
"never a silent fallback" (R-09) cannot be honoured from inside a stage that structurally cannot
ask. So when the chosen backend is `codex`, the Workflow path does **not** put a tester stage in
`pipeline()`: the orchestrator runs `codex-tester.sh` per task group in its own turn, creating the
worktree itself with `git worktree add`, resolving exit 3/4 through the ask while asking is still
possible, running the existing merge-back block, and only then writing a workflow script whose
stages are coder (plus the optional reviewer). This also removes the Workflow path's usual worktree
problem: identity is known by construction instead of enumerated out of `git worktree list` (F19).
The Agent-tool batch path already runs in the live turn, so it needs no equivalent change. The
consequence is uniform and worth stating plainly: **the codex branch is sequential where the Claude
branch is parallel** — a real wall-clock cost, accepted because a tester that cannot report failure
is worse than a slow one.

**R6 — The effort-pin lowering touches three sites, not two.** See the Decision above. Nothing
asserts the effort table's contents today, so the third site is invisible to CI and would have
drifted silently.

**R7 — The availability cascade is duplicated, declared, and drift-checked; extraction is
deferred.** `codex-tester.sh`'s cascade answers the *same* question as `codex-reviewer.sh`'s, and
rule 6 says two copies that could give different answers are the defect. The correct end state is a
shared `codex-common.sh` sourced by both. It is not done here because changing `codex-reviewer.sh`
is explicitly out of the SPEC's scope, and because a shared source that breaks disables both
consumers at once. Instead the duplication is declared in the new script's header and a harness
assertion pins the two copies' load-bearing needles as identical — in particular the check-ordering
fix from VCS-064 (a non-empty output file outranks the rate-limit stderr grep), which is exactly the
kind of correction that gets applied to one copy and not the other. Extraction is a named follow-up.

**R8 — The Claude model chosen at the ask is turn-local and not persisted.** The SPEC declares two
manifest fields, and neither can carry `sonnet` versus `opus`. So a `claude-opus` answer governs the
Step 5 run in which it was given; a later resumed Step 5 run on the same manifest sees
`step5_codex_tester_asked: true`, does not re-ask (R-12, deliberately), and dispatches at the
default `sonnet`. This is a real hole of the same class as the re-prompt bug ADR-0193 fixed, it is
disclosed rather than hidden, and the remedy is a third field (`step5_tester_model`, idiomatic
alongside the existing `coder_model`). Not taken here: the SPEC fixes the field set at two.

## Alternatives considered

1. **Codex generates test content only; a wrapper script writes the files.** Rejected: this still
   needs Codex to *run* the suite to produce accurate pass/fail counts and coverage (a static
   content-only response cannot know if a test it wrote actually passes), so the wrapper would need
   write+execute access anyway — it just relocates the write from Codex's own tool calls to a
   second script, adding a translation step (structured-content parsing) with no sandboxing
   benefit over `workspace-write` and a new failure mode (malformed content the wrapper can't
   parse). `workspace-write` scoped to the worktree gives the same safety guarantee more directly.
2. **Reuse `codex-reviewer.sh` unmodified, with `--mode test` added and `-s read-only` made
   conditional on mode.** Rejected: `codex-reviewer.sh`'s docstring states its contract is
   specifically "a CHECKER... in the SAME shape reviewer.md's own Output Format produces" — folding
   in an entirely different agent contract (`tester.md`'s Output Format, different Quality
   Standards, different Edge Cases, a different production-code-safety invariant to enforce) into
   one script would violate rule 6 ("extract only when two copies answering the same question
   would be a defect" — reviewer and tester answer different questions) and make the read-only
   guarantee mode-conditional in a script whose whole design leans on it being unconditional.
3. **Skip the post-run scope check; trust the prompt instruction alone.** Rejected outright by
   rule 16: an instruction is not an enforcement. The sandbox stops writes outside the worktree;
   nothing but a check stops a write to production code inside it.
4. **Run `codex-tester.sh` inside the Workflow `pipeline()` stage, mirroring how Stage 3 runs
   `codex-reviewer.sh` there today, and handle exit 3/4 by failing the stage and asking once after
   `Workflow()` returns.** Rejected (§Refinements R5): it preserves per-group parallelism, which is
   its one real advantage, but it puts the never-silent-fallback guarantee somewhere it cannot be
   honoured. The reviewer can be skipped; the tester cannot, and a failed tester stage strands the
   whole task group with no red tests and a coder that must not be dispatched. It would also
   require inventing `git worktree add` management inside a generated JS workflow script, whose
   only current worktree mechanism is the `agent()` call's own `isolation: "worktree"` — new
   machinery in the most fragile place in the chain, for a wall-clock saving.
5. **Persist the Claude model choice in a third manifest field (`step5_tester_model`).** Rejected
   for this pass only, and reluctantly (§Refinements R8): the SPEC fixes the field set at two, and
   the miss is bounded (a resumed Step 5 run silently reverts opus to sonnet, never the reverse,
   and never affects correctness). Recorded as a named follow-up rather than a silent limitation.
6. **Add `-m gpt-5.6-terra` to the `codex exec` call, matching `codex-reviewer.sh`'s own pin.**
   Rejected for this pass only (§Refinements R2): the SPEC scopes model override out on the grounds
   that valid model names were not verified live. That reason is weaker than it looks —
   `codex-reviewer.sh:261` already pins that exact name and was live-verified on 2026-09-05 and
   again 2026-09-06 — so the rejection here is deference to an approved scope boundary, not
   agreement with its stated reason. The cost exposure it leaves open is stated in R2.

## Consequences

### Positive

- Functional parity requirement Stefano stated is met structurally: same six-field Output Format,
  same never-fix-production-code rule, same generator/verifier separation, regardless of backend.
- Sandbox (`workspace-write` + `-C <worktree>`) reuses a guarantee the tester dispatch already
  relies on (`isolation: "worktree"`), rather than inventing a new isolation boundary.
- The scope check is a real, independent safety net Codex's own sandbox does not provide, and after
  R4 it catches the case that actually matters (a new, untracked production file) rather than only
  the case `git diff` can see.
- The effort-pin lowering cuts the cost of every tester dispatch on the Claude branch too, so the
  change pays for itself even on runs that never choose Codex.
- On the codex branch the Workflow path's worktree identity stops being guessed from
  `git worktree list` (F19's documented weak spot) and becomes known by construction.

### Negative

- New exit code (4) the caller must branch on, on top of 0/2/3 — one more state to keep in sync
  across `codex-tester.sh` and its two call sites, same maintenance shape ADR-0193's own two-field
  correction already showed is easy to get wrong (the RTF path-mismatch correction, 2026-09-06).
- Two more manifest fields — `manifest-init.sh` and `manifest-validate.sh` must be updated in
  lockstep (rule 17: a producer and a consumer that must agree).
- **The codex branch is sequential where the Claude branch is parallel** (§Refinements R5). On a
  plan with several task groups this is a real wall-clock regression, taken deliberately.
- **Cost inheritance instead of a cost pin** (§Refinements R2): this script follows
  `~/.codex/config.toml` wherever it goes, unlike `codex-reviewer.sh`, which pins.
- **The Claude model choice does not survive a resumed Step 5 run** (§Refinements R8).
- The availability cascade now exists in two places (§Refinements R7). The drift assertion makes
  divergence detectable, not impossible.
- `effort` cannot be passed through the Agent-tool batch path regardless of backend (ADR-0068 §D7,
  pre-existing limit, unchanged by this ADR).
- Lowering the tester's effort from `xhigh` to `high` is a quality/cost trade whose effect on test
  quality is **not measured** — it is Stefano's explicit cost decision, recorded as such. If test
  quality visibly drops at Step 5 checkpoints, this pin is the first thing to reconsider.
- Not yet measured live (rule 13 disclosed limit): whether `codex exec -s workspace-write` runs a
  test-suite invocation cleanly inside a worktree with no further permission friction (the
  `workspace-write` sandbox restricts network, which a dependency-installing suite may need), and
  whether Codex's own tool-use loop reliably stops at test files without the scope check ever
  firing in practice. Both are what the deferred dry run in §Verification must confirm.

### Neutral

- `codex-reviewer.sh` itself is untouched; `codex-tester.sh` is a new, separate script, not a mode
  flag on the existing one (per Alternative 2 above).
- `review-triage-fix` and its own Codex dispatch sites are out of scope and unchanged.
- Status is `Accepted` while the live dry run is still outstanding, matching ADR-0187's own
  precedent (accepted with an explicitly deferred live probe, later run and recorded as a dated
  Correction). Accepted describes the decision, not the verification.

## Verification

A harness parallel to `codex-review-dispatch-gate.test.sh`, named
`staging/plugin/scripts/tests/codex-tester-dispatch-gate.test.sh`, assertion prefix `CX`
(verified free across `staging/` on 2026-09-06). It is offline and hermetic: the exit 0/3/4 paths
are exercised against a **stub `codex` on `PATH`** in a scratch git repository, never against the
real CLI, because this repo's convention is never to spend Codex quota in CI. It covers: the
exit 0/2/3/4 contract; the untracked-file case R4 exists for; the `--effort` passthrough, present
and absent; the manifest field pair through `manifest-init.sh` → `manifest-validate.sh` →
`manifest-set-flag.sh`; the single ask and the exactly-two dispatch sites that point back at it
(exact counts, not floors — rule 10); the deployed `hooks/` path both sites name (rule 17, the
VCS-063 lesson); and the three effort-pin sites. `codex-reviewer-schema.test.sh` is extended with
one assertion walking `codex-tester.sh`'s own `--output-schema` block, rather than copying its JSON
walker into the new file (rule 6).

`test-write-scope.test.sh`'s `TG1` asserts the literal `effort: "xhigh"` is present in
`step5-implementation.md` and goes RED the moment the pin is lowered. Updating that needle is part
of the change, not collateral damage — it is the one call-site that asserts the old contract.

**Deferred, named, and required before the codex branch is trusted in a real chain run:** a live
dry run against a real worktree — confirm `workspace-write` + `-C` actually constrains Codex as
expected, that a test suite runs inside that sandbox, and that the six-field report shape survives a
real `codex exec` round trip without prompt drift (rule 6/12 risk, the same one
`codex-reviewer.sh`'s own REVIEW_PROMPT declares). ADR-0187's live probe found a real defect
(`additionalProperties`) that no offline harness had caught; there is no reason to expect this one
to be cleaner. Record the outcome as a dated `## Correction` here (rule 14), never by editing the
sections above.

## References

- `staging/plugin/agents/tester.md` — the Output Format, Quality Standards, and Edge Cases this
  ADR requires Codex to match
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` — the two dispatch
  sites (`**Stage 1 — tester.**` on the Workflow path, `**Tester batch dispatch template**` on the
  Agent-tool path) and the effort table whose note names itself "the second place to update"
- `docs/architecture/ADR-0187-codex-review-gate.md` — `codex-reviewer.sh` contract and manifest
  field pattern, extended here
- `docs/architecture/ADR-0193-codex-review-choice-at-dispatch.md` — per-dispatch-site ask pattern,
  reused here for the single Step 5 ask covering both paths
- `staging/plugin/scripts/codex-reviewer.sh` — structural precedent for `codex-tester.sh`, and the
  source of the check-ordering fix R7 pins against drift
- ADR-0049 §D1, ADR-0088 — generator/verifier separation and plan-scope rules the brief must
  preserve regardless of backend
- ADR-0068 §D7 (issue #180) — `effort` not passable through the Agent tool, pre-existing limit
- ADR-0068 §D5, §D6, §D9 — the merge-back and base-fork audit block the codex branch reuses
- ADR-0151 §D11 — `.github/` is not a legal plant target, which is why the harness's own CI
  registration carries no assertion
