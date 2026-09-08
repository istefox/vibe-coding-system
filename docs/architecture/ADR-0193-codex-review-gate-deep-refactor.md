# ADR-0193 — Codex-vs-Claude review gate extended to deep-refactor's audit dispatch

- **Status:** Accepted
- **Date:** 2026-09-05
- **Extends:** ADR-0187 (`docs/architecture/ADR-0187-codex-review-gate.md`) — the pattern this
  reuses: one opt-in flag, a `codex-reviewer.sh` mode per Claude-agent shape, IF/ELSE at the
  dispatch site with the Claude-only branch byte-preserved in the `ELSE`, exit `0`/`2`/`3` with
  `3` = DID-NOT-RUN as the single fallback signal.
- **Related:** ADR-0018 (the `deep-refactor` skill and its two mandatory report-only guards — the
  guards this ADR moves from prose-only to embedded-in-the-prompt), ADR-0011 (the flag-plus-
  Invariant template ADR-0187 itself reused), ADR-0139 (Workflow/Agent-tool dispatch, the reason
  deep-refactor has two branches to wrap and not one), ADR-0154 (the plan/ADR back-reference a new
  harness needs or `spec-coverage.sh` descopes it), ADR-0086 (extract-only-when-divergence-is-a-
  defect, the rule behind reusing `enumerate-sources.sh` instead of re-listing its exclusions).

## Context

ADR-0187 substituted Codex CLI for Claude's `reviewer` agent at five dispatch sites, all of them
sharing `reviewer.md`'s BLOCKER/MAJOR/MINOR/NIT contract. It closed by naming what it had not
done, and one of those things was this feature:

> This pass does not extend Codex substitution to `coder`/`tester` dispatch, to Gate 5.06 /
> `security-audit` / `deep-refactor`, or to `--autopilot` runs — all explicitly deferred, not
> solved.

**ADR-0187's text is not edited by this ADR, and must not be.** Rule 14: a completed ADR is a
correct snapshot of its day, and rewriting that sentence would falsify the record for no consumer.
The deferral was true on 2026-09-01. This ADR supersedes it *going forward* for the `deep-refactor`
half only — Gate 5.06, `security-audit` and `--autopilot` review substitution remain deferred
exactly as ADR-0187 left them. `docs/chain-decision-index.md` currently carries no entry for
ADR-0187 at all; the entry this feature adds for ADR-0193 is therefore the index's only pointer to
the Codex gate, and it names ADR-0187 so a reader arriving at the index for "Codex" lands on both.

The reason `deep-refactor` was deferred is a taxonomy mismatch, not an oversight.
`reviewer.md` answers "is this diff safe to merge" in BLOCKER/MAJOR/MINOR/NIT with a confidence
score. `deep-refactor`'s four audit dimensions answer "what in this codebase is dead / slow /
tangled / unsafe, and is a machine allowed to fix it" in `severity` P1/P2/P3 plus `risk_level`
low/high plus `fix_type` coder/refactorer/debugger/report-only. ADR-0187 refused to merge the two
(rule 6 — copies answering *different* questions stay copies), so extending the substitution here
means a third `codex-reviewer.sh` mode, not a reused one.

Three constraints shaped everything below, and all three come from the interview, not from the
existing code:

1. `deep-refactor` is invocable standalone. It has no `concept-to-code` manifest to read in that
   case, so `manifest.use_codex_review` cannot be the carrier — the flag has to be local to the
   skill.
2. Under `manifest.autopilot = true` there is no operator to ask. ADR-0187 resolved that case by
   pinning `use_codex_review` to `false` for every autopilot run. This feature instead *inherits*
   the manifest's value when a manifest exists, which is a deliberate divergence from ADR-0187 and
   is argued below.
3. Codex failing is per-dimension, not per-run. Four independent calls fan out; one hitting a
   quota ceiling says nothing about the other three.

## Decision

### D1 — A skill-local flag, `USE_CODEX_AUDIT`, resolved once per invocation

Run-local, no persistent file, no new manifest field, no addition to the `concept-to-code` schema
(which stays at 1.4). Resolution happens exactly once, before Phase 1, in this order:

- **Unattended** (invoked from `concept-to-code` Gate 5.1 with `manifest.autopilot = true`): no
  question is asked. If a manifest is present, `USE_CODEX_AUDIT` takes `manifest.use_codex_review`'s
  value, read through `manifest-field-state.sh` and never a bare field read (rule 11 — ABSENT,
  INVALID and UNREADABLE are three states, not two). All three non-`true` states resolve to
  `false`, because this feature *adds* a constraint and absent must therefore equal the pre-feature
  behaviour — the same default-direction argument the manifest's own `external_dependencies`
  comment makes, and the inverse of the `risk`/`task_type` strict-on-null rule. ABSENT is also the
  pre-1.4 retrocompat case ADR-0187's Invariant 24 already treats as `false`.
- **Unattended with no manifest** (fully standalone autopilot): `false`. There is nothing to
  inherit and nobody to ask.
- **Attended** (standalone, or Gate 5.1 without autopilot): a new **Gate 0-CDX**, an
  `AskUserQuestion` placed after Gate 0's approve/abort and before Phase 1, asked once per
  invocation. Options, recommended first per the global convention: `"No — Claude only (current
  behaviour) (Recommended)"` / `"Yes — use Codex for the 4 audit dimensions, with per-dimension
  fallback"`. Default is No, so an operator who hits Enter gets today's behaviour byte-for-byte.

The gate is named `Gate 0-CDX` rather than `Gate 0c`: `Gate 0c` is a retired identifier in
`concept-to-code`'s namespace (ADR-0187 §"Gate CDX"), and even though this is a different skill's
namespace, reusing a name that repo convention says never to reuse would cost more in reader
confusion than the two characters save. `CDX` deliberately echoes Gate CDX so the lineage is
readable.

**The autopilot divergence from ADR-0187, stated plainly.** ADR-0187 kept `use_codex_review` at
`false` for every autopilot run — "this pass does not extend Codex substitution to unattended
runs". This ADR does extend it, for `deep-refactor` only. The reason the two can differ without
contradiction: ADR-0187's five sites are *blocking* review gates whose findings steer the chain,
so an unattended run silently switching engines changes what the chain does. `deep-refactor`'s
audit phase produces findings that are then shown at Gate 1 and, under autopilot, Gate 1's
autopilot default is a documented safe default — and, decisively, the per-dimension fallback in D5
means an unavailable Codex degrades to exactly ADR-0187's behaviour rather than to a skipped
review. The operator who set `use_codex_review: true` on the manifest expressed an engine
preference for the whole run; honouring it here is closer to their intent than overriding it. This
is a real, deliberate widening of ADR-0187's autopilot boundary and is called out again in
Consequences.

### D2 — `codex-reviewer.sh --mode audit`, a third mode beside `review` and `diagnose`

```text
--mode audit --dimension dead-code|perf|structure|security [--diff-scope uncommitted|base:<ref>|commit:<sha>] --out <file>
```

Same contract as the two existing modes and no change to either of them: exit `0` on success
(`--out` written), exit `2` on bad invocation (unknown flag, unknown `--dimension`, unknown
`--diff-scope` value, missing `--out`, missing `--dimension`), exit `3` DID-NOT-RUN with one named
reason on stderr. `--dimension` is required in audit mode and its four values are closed —
an unrecognised value is exit `2`, never a silently-defaulted dimension (a type is not a value
set, ADR-0125's rule as applied by `dispatch-completion.test.sh`'s DC22).

`--diff-scope` is accepted with **exactly** the three values the existing `review` mode validates,
reusing the same `case` arm rather than a second copy of the pattern (rule 6 — one question, one
answer). It is **optional in audit mode**, and that is the one place this design fills a gap the
interview left open rather than implementing a locked decision verbatim:

- Given → the audit is narrowed to the files that diff touches.
- Omitted → the audit covers the whole tracked source tree, which is `deep-refactor`'s own
  documented scope. Its `SKILL.md` frontmatter says outright *"deep-refactor is for the ENTIRE
  source tree, not a bounded changeset"*, and none of the three locked `--diff-scope` values
  expresses "whole tree".

Making the flag optional was chosen over adding a fourth value (`tree`), which would have changed
the signature the interview locked, and over making it required, which would have forced
`deep-refactor` to pass a scope that misdescribes what it audits. **This is the item to confirm at
Gate 2** — it is the only place the plan does not implement a locked decision literally.

### D3 — The audit file list is derived, never re-listed

The audit prompt embeds a list of file *paths* (not contents) and lets Codex read them under
`codex exec --sandbox read-only` — the same runtime-guarantee-not-instruction argument ADR-0187
makes for the sandbox flag (rule 16).

The list comes from `deep-refactor`'s own `enumerate-sources.sh`, invoked as
`$SCRIPT_DIR/../skills/deep-refactor/scripts/enumerate-sources.sh`. That relative path resolves
identically in both trees, which is why it is safe: in `staging/`, `plugin/scripts/` +
`../skills/deep-refactor/scripts/`; deployed, `~/.claude/hooks/` (where `sync-to-claude.sh`'s
PAIRS entry puts `codex-reviewer.sh`) + `../skills/deep-refactor/scripts/`, the exact path
`deep-refactor/SKILL.md` already documents. `SCRIPT_DIR` is already computed at the top of
`codex-reviewer.sh` and is currently unused; this is its first consumer.

Re-implementing the exclusion set (`*.xcarchive`, `DerivedData/`, `Pods/`, `.build/`,
`*.generated.swift`) inside `codex-reviewer.sh` was rejected under ADR-0086 §D1: two copies of
*one* question — "which files are this project's source" — giving different answers is a defect,
which is exactly the extract-don't-copy case. The helper missing or non-executable is exit `3`
DID-NOT-RUN with that reason named, never a silent fall-back onto a duplicated list (rule 4). An
empty file list is **not** exit `3`: it is exit `0` with an empty `findings` array, mirroring
ADR-0187's own explicit "an empty diff is not a failure" precedent.

### D4 — Output is `FINDINGS_SCHEMA`-shaped JSON, and three fields are wrapper-enforced

`--out` receives JSON, not markdown. The `--output-schema` block carries
`"additionalProperties": false` on **every** object, root and nested — the defect ADR-0187's
Correction of 2026-09-02 found live, where OpenAI's structured-output API rejects the call with
`invalid_json_schema` before the model runs.

**The emitted object carries all nine `FINDINGS_SCHEMA` fields, not the seven the SPEC's R-02
lists.** R-02 names `dimension`, `severity`, `file`, `line`, `description`, `risk_level`,
`fix_type`; `deep-refactor/SKILL.md`'s actual schema also declares `id` and `suggested_fix`, and
Phase 2's dispatch-brief template and Phase 4's report both read them. Emitting only R-02's seven
would satisfy the letter of the criterion and break the skill downstream. Nine is a superset, so
R-02 is satisfied; the two extra fields are stated here so nobody later "fixes" the schema down to
seven.

Three fields are set by the wrapper's `python3` post-process and never trusted from the Codex
response, on rule 16's reasoning — an instruction to an LLM is a changed failure shape, a
mechanical post-process is an enforcement:

1. `dimension` — forced to the `--dimension` argument on every finding. A dimension-tagging error
   would silently misroute a finding into another dimension's fix pass.
2. `fix_type` — forced to `report-only` on **every** finding when `--dimension security`,
   regardless of what Codex proposed, mirroring `SKILL.md`'s "All security findings are always
   `fix_type: report-only`" invariant. Not forced on the other three dimensions, and a test pins
   both directions so the forcing cannot quietly become global.
3. `id` — synthesised as `<dimension>-<file_basename>-<hash3>`, the form `SKILL.md` declares. A
   model-generated id is not reliably unique and the dedup/report stages key on it.

`risk_level` and `severity` stay as Codex returns them, constrained by the schema's enums. They are
judgment calls the guards in D6 exist to steer, not facts a wrapper can recompute.

### D5 — Per-dimension fallback, resolved once per dispatch, never mid-run

The engine choice is resolved once per *invocation* (D1). The *outcome* is per dimension: a
`3` from one dimension's call falls that dimension back to the existing Claude `reviewer` `agent()`
call for that dimension only; the other three stay on Codex. No question is asked mid-run — that is
ADR-0187's "gate once, not per site" decision read one level down, and it is what keeps Branch A's
parallel fan-out a fan-out. Exit `2` from a dimension call is **not** a fallback: it is a bug in
the dispatch site's own arguments and must surface, not be papered over by silently reverting to
Claude.

Both branches under `### Dispatch model` get the same wrap: Branch A (Workflow fan-out, the
default) and Branch B (sequential `Agent`-tool, `hook_verified: false` only), in Branch B's already
fixed order dead-code → perf → structure → security. The `ELSE` preserves today's text byte-for-
byte, including `model: "opus", effort: "high"` and the "inherit the session" sentence that
`workflow-dispatch-pins.test.sh` A2/A3 grep for literally, and including the existing
`<!-- dispatch-site: deep-refactor-reviewers … -->` marker. **No new `dispatch-site:` marker is
added**: `dispatch-completion.test.sh`'s DC21 freezes the declared set exactly (ADR-0124 — a floor
absorbs its own plant, so identity is frozen rather than counted), and a `codex-reviewer.sh` call
is a shell invocation, not a subagent dispatch, so it has nothing to declare.

### D6 — The two mandatory guards are embedded verbatim, and the embedding is drift-checked

`SKILL.md`'s Mandatory guard 1 (the `@objc`/`dynamic`/`#selector`/reflection carve-out for
dead-code) and Mandatory guard 2 (the `async`/`actor`/`DispatchQueue`/`Sendable` carve-out for
perf) are today enforced only as structural anchors on `SKILL.md` itself — the skill-local
`run-tests.sh` greps for the heading. Once Codex is the engine, an anchor on the skill file proves
nothing about the prompt Codex received. So both guard strings are embedded verbatim in
`codex-reviewer.sh`'s audit prompt construction, each in its own dimension's branch and not in the
other's.

The harness does not hard-code the guard text. It **extracts both strings from
`deep-refactor/SKILL.md`** and asserts each appears, whitespace-flattened (rule 3 — a clause is the
same clause whether it wraps), in `codex-reviewer.sh`, with a count guard failing hard if fewer
than two strings are extracted (rule 7 — zero candidates and zero matches look identical from
outside). That makes it a **drift check** between the two files, which is materially stronger than
what exists today: ADR-0187 shipped `reviewer.md`'s prompt hand-ported into `codex-reviewer.sh`
with, in its own words, "no automated coupling check between them". This is that check, for the
one pair where the repo already calls the text non-negotiable.

### D7 — `codex-reviewer-schema.test.sh`'s ordinal extraction is repaired in the same pass

`codex-reviewer-schema.test.sh` extracts its two schemas by **ordinal** — `extract_schema 1` is
review, `extract_schema 2` is diagnose. Adding a third `SCHEMA_EOF` block anywhere before the
diagnose block silently repoints `S2` at the audit schema while its label still reads
"diagnose-mode schema", and the diagnose schema stops being checked at all. Nothing fails; coverage
just quietly leaves. That is the rule-18 shape — a scan satisfied by the population it searches
rather than the part it meant.

The harness is therefore changed in this pass from ordinal to **all-blocks**: enumerate every
`SCHEMA_EOF` block, check each, and assert the block count equals the mode count exactly. The
count is an exact equality and not a `>= 2` floor, because a floor absorbs its own plant
(ADR-0124). This is an observable-contract change with a known call-site, listed in the plan
rather than left for the coder to discover.

### D8 — Gate 1 gains engine attribution, and `FINDINGS_SCHEMA` does not

When `USE_CODEX_AUDIT` was true for the run, HITL Gate 1's findings summary gains one line per
dimension naming the engine that served it (`Codex` / `Claude (fallback)`), so a per-dimension
fallback is visible before the operator approves the fix loop. When it was false, the block does
not render at all and Gate 1 is byte-identical to today.

No field is added to `FINDINGS_SCHEMA`. Phase 2's fix loop and Phase 4's report never branch on
provenance, so persisting it would be a field with no consumer — and a schema change would ripple
into the dedup rule, the report template and the skill-local harness for a display concern that
lives and dies inside one `AskUserQuestion`.

### D9 — Scope boundary, unchanged from ADR-0187's own

Phases 2, 3 and 4 are untouched. `coder`/`refactorer`/`debugger` are fix agents that write to
source; ADR-0187 substituted only review-role dispatches and this ADR holds that line exactly.
Nothing in `review-triage-fix` or `concept-to-code`'s five ADR-0187 sites is edited.

## Alternatives considered

**A1 — Reuse `manifest.use_codex_review` directly as the flag, with no skill-local gate.**
Rejected: `deep-refactor` runs standalone with no manifest at all, which is its documented Branch A
condition ("No project manifest present (standalone invocation)"). A flag that can only be read
from a file that need not exist would leave the majority of standalone invocations with no way to
opt in, and would make the feature reachable only through `concept-to-code` — the opposite of the
skill's own positioning.

**A2 — Add a `use_codex_audit` field to the `concept-to-code` manifest (schema 1.4 → 1.5).**
Rejected for the same reason as A1 plus a cost: a schema bump drags in `manifest-init.sh`'s seed,
`manifest-validate.sh`'s Invariant 1 regex, a new Invariant, and a retrocompat story, all to carry
a boolean that is meaningless for the standalone case the feature must support. The interview
locked this out explicitly, and the mechanics agree with the lock.

**A3 — Extend `--mode review` with a `--dimension` flag instead of adding `--mode audit`.**
Rejected: the two produce different output shapes (markdown in `reviewer.md`'s Output Format vs.
`FINDINGS_SCHEMA` JSON), different schemas, different filtering (confidence threshold vs.
risk/fix-type tagging) and different scopes (a diff vs. a source tree). Overloading one mode would
put four `if MODE=review && DIMENSION` branches through a function that today has a clean two-way
split, and would put the audit path's failure modes on the code path five shipped dispatch sites
already depend on. A third mode leaves both existing modes provably untouched, which is what R-11's
no-regression criterion actually needs.

**A4 — Merge the two taxonomies (BLOCKER/MAJOR/MINOR/NIT and P1/P2/P3 + risk_level + fix_type)
into one, so a single Codex mode serves everything.** Rejected, and not by this ADR: ADR-0187
already rejected it under rule 6, because the two answer different questions — "is this diff safe
to merge" versus "may a machine fix this without a human". The SPEC lists the merge as explicitly
out of scope. Revisiting it here would also make every one of ADR-0187's five sites a caller of a
changed contract, turning a scoped extension into a rewrite.

**A5 — Make `--diff-scope` required in audit mode, exactly as the signature was locked.**
Rejected: `deep-refactor` audits the entire tracked source tree by its own definition, and none of
the three locked values expresses that. Requiring the flag forces the dispatch site to pass a scope
that misdescribes what is being audited — most likely `uncommitted`, which on a clean tree is empty
and would produce four empty audits that look like a clean codebase. That is a false negative
dressed as a pass, the worst available outcome. Optional-and-validated keeps every locked value
legal and adds no new one.

**A6 — Add a fourth `--diff-scope` value, `tree`, for the whole-tree case.** Rejected: it changes
the signature the interview locked, for no behaviour the optional form does not already give. It
would also make "scope" mean two different kinds of thing in one flag (a diff selector and a
not-a-diff sentinel), which is the shape that produces "unknown value silently treated as default"
bugs later.

**A7 — Ask the operator, mid-run, when a dimension's Codex call returns `3`.** Rejected on two
grounds. Mechanically, Branch A is a Workflow script and has no `AskUserQuestion` hook — ADR-0187
hit this exact wall at its Site 4 and had to defer the question to after `Workflow()` returns.
Behaviourally, four dimensions could produce four questions in a phase whose entire value is
unattended fan-out, which works against the token- and time-saving goal the feature exists for.
Falling back silently *within the run* and reporting it at Gate 1 (D8) keeps the never-silent
guarantee — the operator is told, before they approve anything — without pausing a fan-out that
structurally cannot pause.

**A8 — Trust Codex's `fix_type` for the security dimension and only validate it, failing the run
on a mismatch.** Rejected: validation converts a model's stylistic drift into a hard failure of a
review that otherwise succeeded, and the correct value is known unconditionally — every security
finding is `report-only`, with no exceptions in `SKILL.md`. Forcing is strictly more robust than
validating when the right answer is a constant, and rule 16 says the mechanical step is the
enforcement while the prompt sentence is not.

**A9 — Hard-code the two guard strings in the new harness rather than extracting them from
`SKILL.md`.** Rejected: a hard-coded copy is a third copy of a string the repo calls
non-negotiable, and it would pass forever after someone edits the guard in `SKILL.md` and forgets
`codex-reviewer.sh` — the precise drift ADR-0187 admitted it had no check for. Extraction makes the
assertion a coupling between the two real files. The cost is a derived population, which is why it
carries the count guard rule 7 requires.

**A10 — Add a new `dispatch-site:` marker for the Codex path.** Rejected: `dispatch-completion`'s
DC21 freezes the declared set byte-exactly, so a new marker is a deliberate baseline bump; and the
thing being declared is a shell-script invocation, not a subagent dispatch, so the marker would
assert something untrue about the population it belongs to.

**A11 — Leave `codex-reviewer-schema.test.sh` alone and simply append the audit schema after the
diagnose block, preserving ordinals 1 and 2.** Rejected: it works exactly once. The next block
added anywhere re-breaks it, and nothing in the file says the ordering is load-bearing. Position-
dependent extraction is the same class of defect as a line-number cross-reference (rule 12) — it
rots silently, and it rots fastest in a file being actively extended.

## Consequences

### Positive

- `deep-refactor`, the most token-expensive review dispatch in the system (four `opus` reviewers at
  `effort: high` over an entire source tree), becomes an opt-in Codex substitution — the largest
  single token saving available under ADR-0187's own substitute-not-second-opinion contract.
- The two mandatory guards stop being prose-only. Today they are enforced by an anchor on the file
  that *states* them; after this they are embedded in the actual prompt and drift-checked against
  their source of truth. That is a real strengthening of ADR-0018's guarantee, and it applies to
  the Codex path and the `SKILL.md` text alike.
- The first automated drift check between a Claude-side contract and its `codex-reviewer.sh`
  hand-port. ADR-0187 shipped that duplication with a written admission that nothing checked it;
  this establishes the pattern that could later cover `reviewer.md`'s prompt too.
- `codex-reviewer-schema.test.sh` stops being position-dependent, so the *next* mode added does not
  silently uncover an existing one.
- Security's `report-only` invariant is now enforced at a second, mechanical point rather than
  resting entirely on the model's compliance with a sentence.

### Negative

- **This widens ADR-0187's autopilot boundary** (D1). An unattended run whose manifest carries
  `use_codex_review: true` will now silently route `deep-refactor`'s audit to Codex, where before
  no autopilot run used Codex anywhere. The blast radius is bounded — findings are advisory until
  Gate 1, and an unavailable Codex degrades per-dimension to today's behaviour — but the boundary
  did move, and it moved without a per-run confirmation.
- A third prompt is now hand-ported into `codex-reviewer.sh`, so the file carries three
  independently-drifting copies of Claude-side contracts. Only one of the three (the guards) is
  drift-checked. The audit prompt's *other* content — the dimension scopes, the P1/P2/P3 rubric,
  the risk-tagging judgment — is duplicated with no coupling check, exactly the debt ADR-0187
  recorded and this pass only partially repays.
- `codex-reviewer.sh`, a shared wrapper, now depends on one specific skill's helper script
  (`enumerate-sources.sh`) through a relative path. The path resolves in both trees and a test
  pins that, but the coupling is real: moving or renaming that helper breaks a script in a
  different subtree, and the failure surfaces as exit `3` on an audit rather than as a missing
  file at the obvious place.
- A whole-tree audit gives Codex a large agentic reading task under `-s read-only`. Latency and
  quota consumption per dimension are unmeasured at design time and could be materially worse than
  the diff-scoped review mode ADR-0187 measured. The realistic failure mode is a rate-limit exit
  `3` on later dimensions, which the per-dimension fallback handles — meaning a run can degrade to
  a Codex/Claude mixture whose cost profile is neither of the two clean cases.
- `--diff-scope` now means two things depending on presence (narrow the audit / whole tree). That
  is a real asymmetry with `--mode review`, where the flag is required, and a reader comparing the
  two modes' argument handling will find them inconsistent.

### Neutral

- No manifest schema change. `concept-to-code` stays at 1.4 and every existing manifest continues
  to validate unchanged.
- No `FINDINGS_SCHEMA` change, so Phases 2/3/4, the dedup rule, the report template and the
  skill-local `run-tests.sh` anchors are all untouched.
- No `PAIRS` entry is needed: `codex-reviewer.sh` already has one, and `pairs-completeness.test.sh`
  covers only `plugin/agents/*.md`, `user/rules/*.md` and `plugin/skills/*/SKILL.md`. The new
  `*.test.sh` file does need a manual append to `.github/workflows/docs-ci.yml`'s named harness
  list, which is a glob-versus-named-list gap that has bitten four times before (ADR-0113) and is a
  plan task here, not a footnote.
- Both existing `codex-reviewer.sh` modes keep their contracts byte-for-byte. R-11's no-regression
  criterion covers the `deep-refactor` side; the `review`/`diagnose` side is protected by the
  existing harness plus the all-blocks schema check from D7.
- The new fence in `deep-refactor/SKILL.md` uses ` ```sh `, matching that file's existing
  convention throughout. `fence-contract-coverage.test.sh`'s population is ` ```bash ` fences only,
  so the new fence falls outside it — stated here rather than left silent, because it is a
  coverage boundary a reader could reasonably mistake for an exemption.

## References

- `docs/architecture/ADR-0187-codex-review-gate.md` — the pattern extended; **not edited by this
  ADR** (rule 14)
- `docs/architecture/ADR-0018-deep-refactor-skill.md` — the two mandatory guards
- `staging/plugin/scripts/codex-reviewer.sh` — `--mode audit`
- `staging/plugin/skills/deep-refactor/SKILL.md` — Gate 0-CDX, both dispatch branches, Gate 1
- `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh` — the file-list source
- `staging/plugin/skills/concept-to-code/references/hitl-gates.md` — Gate 5.1, the unattended entry
- `staging/plugin/scripts/tests/codex-reviewer-schema.test.sh` — ordinal to all-blocks
- `.github/workflows/docs-ci.yml` — harness list entry for the new test
- `docs/chain-decision-index.md` — the index entry this feature adds
- `docs/superpowers/plans/2026-09-05-codex-review-gate-deep-refactor.md` — the implementation plan

## Correction (2026-09-08)

`staging/plugin/skills/deep-refactor/SKILL.md`, named above in References and in §D3's description
of the staging-side resolution, no longer exists — `deep-refactor` was migrated out of this repo's
vendored surface (`docs/architecture/ADR-0197-deep-refactor-migrated-to-istefox-skills.md`, Accepted
2026-09-07). `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh`, also named above, is
retained at its exact original path as a declared `contract-reference:` (never a deploy source);
§D3's resolves-identically-in-both-trees argument for `codex-reviewer.sh:206`'s relative-path lookup
still holds unchanged. Nothing in `codex-reviewer.sh` itself was edited by ADR-0197 (its own D11).
This note does not alter the decision recorded above (rule 14) — read ADR-0197 for the current state
of the vendored tree.
