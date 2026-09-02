# ADR-0187 — Codex-vs-Claude review gate for concept-to-code

- **Status:** Accepted
- **Date:** 2026-09-01
- **Related:** ADR-0011 (`anonymize`, the schema-bump-plus-Invariant template this reuses),
  `staging/plugin/agents/reviewer.md` (the contract this substitutes at five sites),
  `staging/plugin/skills/clean-public-repo/scripts/detect-public-remote.sh` (the fail-safe-cascade
  idiom this adapts to a never-silent variant), ADR-0139 (Workflow/Agent-tool background dispatch,
  the reason Site 4 cannot ask interactively).

## Context

Stefano is on a Claude Code plan with a real weekly token ceiling, and separately holds a Codex
CLI (ChatGPT-plan) subscription. His own words set the requirement: **"lo scopo è risparmiare
tokens in claude code, quindi codex deve sostituire e non affiancare per una seconda
valutazione"** — Codex must substitute Claude's `reviewer` dispatch at cost-heavy sites, never run
alongside it as a second opinion. Fallback policy, also his own words: **"fallback su claude code
ma un gate mi deve avvertire e io decido se proseguire o fermare la chain"** — falling back to
Claude is fine, but only after an explicit gate, never silently.

He then asked not to lose the chain's existing behaviour while adding this: could it be gated
rather than rewritten. Agreed shape: **one gate, once, at chain start** — not one gate per
dispatch site, which would add friction at every one of the five and work against the
token/time-saving goal the feature exists for. Default stays "No" (today's Claude-only behaviour,
byte-identical) unless the user opts in for that run.

Scope: the five dispatch sites sharing the `reviewer` agent's BLOCKER/MAJOR/MINOR/NIT contract —
RTF Step 1, RTF advisor pair, RTF Step 4 re-review, Step 5 checkpoint (Workflow path), Step 5
checkpoint (Agent-tool path). Gate 5.06 (`silent-failure-hunter`/`type-design-analyzer`),
`security-audit`, and `deep-refactor` use different output taxonomies
(CRITICAL/IMPORTANT/SUGGESTIONS; P1/P2/P3+risk_level+fix_type) and are explicitly deferred, not
folded in.

Three Explore agents mapped the chain's step-0 gate sequence and manifest-flag plumbing, the exact
contract of all five dispatch sites, and Codex CLI's real installed capabilities — findings below
are measured, not assumed (rule 13).

## Decision

### `AGENTS.md` rewritten clean (prerequisite)

The repo root's `AGENTS.md` — read by Codex on every invocation here — was a mechanical
`CLAUDE.md` mirror (wrong-case `~/.Codex/` paths, Claude-Code-only concepts like agent-teams and
`AskUserQuestion`) regenerated broken at least twice. Replaced with a short, hand-written file: this
repo's identity, its invariant behavioural rules, a pointer to `docs/vibe-coding-system.md` and to
this repo's own 20 numbered rules (for reviewing `staging/plugin/` itself), nothing
Claude-Code-specific. Committed tracked, so it stops being an untracked mystery file.

### Manifest field: `use_codex_review` (schema 1.3 → 1.4)

Same template as `anonymize` (ADR-0011, schema 1.2): `manifest-init.sh` seeds
`use_codex_review: false` right after `anonymize: false`; `manifest-validate.sh`'s Invariant 1
regex now accepts `"1.4"`, and a new Invariant 24 requires the field, when present, to be
`true`/`false` — absent is valid (retrocompat 1.0-1.3). Set via the existing generic
`manifest-set-flag.sh <manifest> use_codex_review true|false`; no change to that script was needed,
since it already handles any pre-seeded boolean key.

### Gate CDX (not "Gate 0c" — that name and list position are retired)

`SKILL.md:290` explicitly records: *"(Step 8b was Gate 0c, humanize — removed per ADR-0040.)"*
Both the list number `8b` and the name `Gate 0c` are retired identifiers this repo's own
convention says never to reuse. The new gate is inserted as **unnumbered prose** directly after
Gate 0b's block and its retirement note, before item `8c` (Gate 0d) — no existing list number is
claimed or renumbered, and `concept-to-code-bsd-autopilot-gates.test.sh`'s §G derivation (which
scans `references/hitl-gates.md`'s `**Gate <id> —` headings, not `SKILL.md`) never sees it, so it
needs no `autopilot-gate-exempt` marker — confirmed by reading the mechanism, not assumed.

Gate CDX asks once, via `AskUserQuestion`, whether to use Codex for review dispatch this run
(scoped explicitly to RTF review cycles and Step 5 checkpoint reviews — "coding and testing stay
on Claude"). "No" leaves `use_codex_review` at its seeded `false`, byte-identical to today for
every run that does not opt in. It does not fire under `--autopilot`: autopilot is unattended, and
this pass does not extend Codex substitution to unattended runs — `use_codex_review` stays `false`
for every autopilot run.

### `codex-reviewer.sh` — the shared wrapper

One script, `staging/plugin/scripts/codex-reviewer.sh` (deployed to `~/.claude/hooks/`, PAIRS
entry added), not duplicated per skill — both `review-triage-fix` and `concept-to-code` need it,
and the two questions it answers ("is Codex available", "format its output like `reviewer.md`")
would disagree if answered twice (rule 6). Two modes match the two shapes the Claude `reviewer`
agent is used in today:

- `--mode review --diff-scope uncommitted|base:<ref>|commit:<sha> [--carry-forward <file>] --out <file>`
- `--mode diagnose --finding "<text>" --out <file>` (the RTF advisor's <150-word diagnosis)

**Contract — a CHECKER, not a reporter (rule 5):** exit `0` on success (markdown written to
`--out`, in reviewer.md's own Output Format shape); exit `2` bad invocation; exit `3`
DID-NOT-RUN (rule 4), one named reason on stderr — the ONE signal every caller gates its
fallback-to-Claude question on. An empty diff is explicitly NOT exit 3: it mirrors reviewer.md's
own "no detectable changes" edge case (exit 0, the report says so).

**Availability cascade**, adapted from `detect-public-remote.sh`'s fail-safe shape into the
never-silent variant `commit/SKILL.md`'s Step 6b already uses for `gh`: CLI absent → exit 3;
`codex doctor --json` unparseable or `.checks["auth.credentials"].status != "ok"` → exit 3; not a
git work tree (review mode only) → exit 3; `codex exec` non-zero exit, or stderr matching
rate-limit vocabulary (`usage limit`, `rate limit`, `quota exceeded`, `429`), or the `--output-schema`
output missing/empty/unparseable → exit 3. Every exit-3 path names its specific reason.

**Codex CLI's real shape, verified live (rule 13), not assumed from `--help` alone:** installed
v0.152.0, ChatGPT-plan auth confirmed via `codex doctor --json`; `codex review` has no
`--output-schema`/`--json`/`-o` (only `codex exec` does), so structured output requires `codex exec`
with the diff embedded in the prompt, not the `review` subcommand; `codex exec --output-schema
<file> -o <out-file> <prompt>` constrains and captures the final message as JSON; `--json` is an
unrelated JSONL event stream. Exit-code semantics on a Codex-side failure are undocumented, which
is exactly why the rate-limit-vocabulary stderr match exists as a second signal alongside the exit
code.

**Sandbox as enforcement, not instruction (rule 16).** `reviewer-write-scope.sh` is a Claude
PreToolUse hook and cannot see this external process. `-s read-only` on `codex exec` is the real
substitute: a runtime guarantee Codex cannot write anywhere, independent of the prompt asking it
not to.

**Confidence filtering is enforced in the wrapper, not left to the prompt alone.** The review-mode
JSON schema carries a per-finding `confidence` field; the formatter (python3, matching this repo's
existing convention for JSON-shaped scripts) drops findings below 51, drops 51-74 unless severity
is BLOCKER (labeled `LOW CONFIDENCE`), and drops nothing at 75+ — the same threshold reviewer.md's
prompt states, but backed by code rather than only by model compliance. Hand-verified against a
canned schema-JSON fixture: a MAJOR@60 and a NIT@30 were correctly dropped, a BLOCKER@55 correctly
kept and labeled, a BLOCKER@90 kept unlabeled.

**Prompt duplication, declared (rule 6/12).** The review-mode prompt is hand-ported from
`reviewer.md`'s Quality Standards / Confidence Filter / Output Format / Edge Cases — a true single
source is not mechanically possible across a Claude Code agent system prompt and a `codex exec`
CLI prompt. When `reviewer.md`'s contract changes, `codex-reviewer.sh`'s embedded `PROMPT_EOF`
block needs a manual re-check for drift; there is no automated coupling check between them in this
pass.

### Site 4 (Step 5 checkpoint, Workflow path) cannot ask interactively — a real deviation from "the same gate everywhere"

Workflow scripts run in the background with a fixed hook surface (`agent`, `pipeline`, `parallel`,
`phase`, `log`, `args`, `budget`, `workflow`) — there is no `AskUserQuestion` hook, so the
per-call, ask-immediately gate used at every other site is structurally impossible inside a
running Workflow script. Checkpoint review is already documented as advisory-only ("A finding here
never halts the chain"), which makes a deferred design sound rather than a compromise:

- On Codex DID-NOT-RUN for one task's checkpoint, the script does **not** attempt to ask. It
  `log()`s the reason, records that task's `checkpoint_reviews` entry as
  `{status: "skipped_codex_unavailable", reason: "<reason>"}`, and continues the pipeline
  unblocked — no findings carried forward for that one task, the same effective outcome as
  today's "no detectable changes" case.
- **After `Workflow()` returns** to the orchestrator's own live turn, if any
  `skipped_codex_unavailable` entries exist, the orchestrator asks **once** (not once per skipped
  task): re-run the skipped checkpoints now via Claude's `reviewer`, or accept as-is. This keeps
  the "never silent" guarantee — the user is told and asked — without pretending a background
  script can pause for input it structurally cannot request.

Site 5 (the Agent-tool fallback path) runs inline in the orchestrator's own live turn between
batches, so it uses the same immediate per-call gate as Sites 1-3.

### Integration pattern at the five sites

Each site wraps its existing "Dispatch the `reviewer` agent…" text in an IF/ELSE on
`manifest.use_codex_review`, byte-preserving the ELSE branch (including exact capitalization —
`dispatch-completion.test.sh`'s DC24 backward check greps for `Dispatch the \`reviewer\`` etc., and
several existing `dispatch-site:` HTML-comment markers were left untouched). Site-specific notes:

- **Site 2 (RTF advisor)** keeps its existing silent per-finding fallback for a Claude advisor
  call that errors/times out/returns empty — the new Codex-unavailable gate is a *different* case
  (Codex never ran at all) and does not touch that existing clause.
- **Site 3 (RTF Step 4 re-review)** passes `--carry-forward <tsv>` so the hash-stability
  instruction (reuse unchanged findings' `problem` wording verbatim, or `triage-state.sh`'s
  `fid()` hash breaks convergence tracking) is embedded directly in the Codex prompt, not lost by
  the substitution.

## Consequences

### Positive

- A single, chain-wide opt-in (Gate CDX) lets Stefano trade Claude review-dispatch tokens for
  Codex quota on a run-by-run basis, with zero behavioural change for any run that does not opt in.
- Confidence filtering happens in code, not only in a prompt — arguably a small correctness
  improvement over `reviewer.md`'s own prompt-only filter, gained as a side effect of building the
  substitute.
- `AGENTS.md` stops being a broken, twice-regenerated mirror.

### Negative

- Two independent copies of the review contract now exist (`reviewer.md` prompt vs.
  `codex-reviewer.sh`'s embedded prompt) with no automated drift check — a future change to one
  can silently diverge from the other until someone reads both.
- Codex's real exit-code semantics on failure are undocumented; the rate-limit-vocabulary stderr
  match is a heuristic, not a contract, and could miss a failure mode phrased differently in a
  future Codex CLI version.
- Site 4's deferred-gate design means a run using Codex can complete several batches' worth of
  checkpoint reviews silently skipped before the user is asked — bounded by "advisory only, never
  blocking", but still a real latency between the underlying event and the user being told,
  unlike every other site.
- This pass does not extend Codex substitution to `coder`/`tester` dispatch, to Gate 5.06 /
  `security-audit` / `deep-refactor`, or to `--autopilot` runs — all explicitly deferred, not
  solved.

### Neutral

- Schema bump to 1.4 is additive only; every manifest at 1.0-1.3 continues to validate unchanged.
- No new `current_step` transition — Gate CDX is a set-once flag read many times later, the same
  shape `anonymize` already established.

## Verification

- `bash -n` on `manifest-init.sh`, `manifest-validate.sh`, `codex-reviewer.sh` — clean.
- New harness `staging/plugin/scripts/tests/use-codex-review-manifest-field.test.sh` (14
  assertions): manifest-init.sh's real output, schema-version bounds, Invariant 24 both
  directions. Four declared plants (schema-version-write, field-seed, schema-version-regex,
  Invariant-24-body) hand-verified RED before trusting them green (rule 2), each backed up and
  restored byte-identical afterward (`diff -q`).
- `codex-reviewer.sh`'s full availability cascade (CLI absent, unauthenticated, non-git-repo, exec
  failure, rate-limit stderr, malformed output) and both success paths (review with confidence
  filtering, diagnose) hand-exercised against a stub `codex` on an isolated `PATH` — never a live
  Codex call in this verification, matching the "never in CI" rule for anything that would spend
  real quota.
- Registered in `staging/sync-to-claude.sh`'s `PAIRS` list (else `pairs-completeness.test.sh`'s
  CI1 correctly flags edits as never deploying) and in `.github/workflows/docs-ci.yml`'s harness
  list (else the same suite's CI1 flags the new test as never running in CI).
- Regression suites re-run after every site edit and all green throughout: `pairs-completeness`
  (341/341), `concept-to-code-bsd-autopilot-gates` (39/39), `gate0-recommendation` (15/15),
  `concept-to-code-manifest-helpers-guards` (38/38), `dispatch-completion` (22/22),
  `fence-contract-coverage` (67/67), `skill-text-corrections` (38/38),
  `skill-coverage-perimeter` (17/17), `triage-state-gitignore` (21/21), `weakening-wiring`
  (63/63), `human-gate-coverage` (55/55), `step5-checkpoint-review` (23/23),
  `workflow-dispatch-pins` (10/10), `step6-effort-pin` (18/18), `batch-dispatch-openers` (19/19).
  Full repo-wide sweep of all 101 harnesses run once more after every site landed: zero failures.
- **Not yet done, and explicitly deferred to a manual pre-ship step (rule 13):** a live, hand-run
  probe of `codex-reviewer.sh --mode review` against a real diff in a scratch repo, to confirm
  `codex exec --output-schema`'s actual output shape matches this ADR's assumptions rather than
  only what `--help` and `codex doctor` could verify without spending real Codex quota.

## Correction (2026-09-02)

The live, hand-run probe deferred in the Verification section above (`codex-reviewer.sh --mode
review` against a real diff) has now been run, in an isolated scratch repo
(`~/Developer/_scratch/codex-reviewer-probe/`, outside this repository).

It found a genuine defect that no prior stub-based testing could have caught: OpenAI's
structured-output API (what `codex exec --output-schema` uses under the hood) requires
`"additionalProperties": false` on **every** object in the schema, root and nested alike, or the
call fails outright with a `400 invalid_json_schema` error (`'additionalProperties' is required to
be supplied and to be false. In context=()`) before the model ever runs. This was not documented
anywhere before this probe — the original schemas in `codex-reviewer.sh` (both the review-mode and
diagnose-mode `--output-schema` blocks) lacked the constraint, since a stub `codex` script on
`PATH` cannot enforce OpenAI's real API-side JSON Schema validation rules the way the live service
does.

Fixed: `"additionalProperties": false` added to every object in both schemas (review-mode: the
nested `findings[].items` object and the outer/root object; diagnose-mode: the single object).
Re-verified live, twice: `--mode review` against the scratch repo's diff returned exit 0 with
correct BLOCKER/MAJOR/MINOR/NIT markdown on the two planted bugs (a division-by-zero and an
unguarded index); `--mode diagnose` returned exit 0 with a correct free-text diagnosis.

A new offline, hermetic regression test, `staging/plugin/scripts/tests/codex-reviewer-schema.test.sh`,
extracts both `--output-schema` blocks from the real source file and asserts the constraint holds
on every object — so a future edit that drops it again fails fast in CI, without spending live
Codex quota. Registered in `.github/workflows/docs-ci.yml`'s harness list (no `sync-to-claude.sh`
PAIRS entry — this test file, like `use-codex-review-manifest-field.test.sh`, is not itself
deployed/used at runtime by a hook).

This finding validates the reason the original plan called for a live probe rather than trusting
stub-based testing alone (rule 13 — measure the premise): the premise here ("the schemas are
already OpenAI-structured-output-compliant") was untested and wrong.

## References

- `AGENTS.md` — rewritten
- `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh` — schema 1.4, `use_codex_review` seed
- `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` — Invariant 1 bump, Invariant 24
- `staging/plugin/skills/concept-to-code/SKILL.md` — Gate CDX
- `staging/plugin/scripts/codex-reviewer.sh` — the wrapper
- `staging/sync-to-claude.sh` — PAIRS entry
- `.github/workflows/docs-ci.yml` — harness list entry
- `staging/plugin/scripts/tests/use-codex-review-manifest-field.test.sh`
- `staging/plugin/skills/review-triage-fix/SKILL.md` — Sites 1, 2, 3
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` — Sites 4, 5
- `staging/plugin/agents/reviewer.md` — the contract this substitutes
- `/Users/stefer/.claude/plans/zippy-whistling-crescent.md` — the approved plan
