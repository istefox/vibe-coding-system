# ADR-0194 — Codex review substitution is not extended to `deep-refactor`, and `security-audit` is unbundled from the same deferral

- **Status:** Accepted
- **Date:** 2026-09-06
- **Related:** ADR-0187 (the Codex review gate, whose deferral clause this closes), ADR-0193 (moved
  the ask to dispatch time; also carries the corrected `~/.claude/hooks/codex-reviewer.sh` deploy
  path), ADR-0018 (`deep-refactor`'s design and its two non-negotiable guards), ADR-0056
  (`security-audit`), ADR-0016 (Workflow dispatch and `hook_verified`), ADR-0049
  (generator/verifier separation, the framing `security-audit`'s Step 2 reuses)
- **Out of scope, deliberately:** whether Codex should actually be wired into `security-audit` —
  named as the stronger candidate in D3, decided in its own ADR, not here; and reducing
  `deep-refactor`'s audit scope by subtree, recorded in D4 as a direction rather than a decision.

## Context

ADR-0187 introduced `manifest.use_codex_review` and substituted Codex for Claude's `reviewer` at
five dispatch sites, all sharing `reviewer.md`'s BLOCKER/MAJOR/MINOR/NIT contract. Its Consequences
list `deep-refactor` — together with `coder`/`tester` dispatch, Gate 5.06, `security-audit` and
`--autopilot` runs — as "explicitly deferred, not solved", and its Context gives the reason in one
clause: those sites "use different output taxonomies". ADR-0193 later moved *when* the choice is
made, from a chain-start gate to per-dispatch-site asks, but only inside `concept-to-code` and
`review-triage-fix` (RTF). `deep-refactor` was untouched by both.

Verified 2026-09-06: a case-insensitive `grep` for `codex` across the entire
`staging/plugin/skills/deep-refactor/` subtree — `SKILL.md`, `scripts/`, `tests/` — returns zero
matches. The skill is byte-for-byte as ADR-0187 left it: no option, no ask, no branch. It always
dispatches the built-in `reviewer`.

The cost argument for changing that is the strongest any site in the system offers. Phase 1
dispatches **four** `reviewer` dimension agents (dead-code, perf, structure, security), each pinned
at `model: "opus", effort: "high"`, over every file `enumerate-sources.sh` returns — the whole
source tree, not a changeset. RTF reviews one diff; Step 5's checkpoint reviews one task's files at
a time. Per invocation, `deep-refactor` is the largest Claude review spend in the system by a wide
margin. That is why this ADR exists at all, rather than a one-line restatement of the deferral.

Five premises were measured before deciding (rule 13). All five are from reading the files today,
not from ADR-0187's summary of them.

### P1 — `codex-reviewer.sh` is a `reviewer.md`-contract substitute, not a general Codex runner

Read directly from the script. `--mode review` accepts exactly three `--diff-scope` values —
`uncommitted`, `base:<ref>`, `commit:<sha>` — and each resolves to a `git diff` or `git show` whose
text is then interpolated into the prompt body. The `--output-schema` block enumerates `severity` as
BLOCKER/MAJOR/MINOR/NIT alongside `location`, `problem`, `fix` and `confidence`; the python3
formatter renders that into `reviewer.md`'s own markdown Output Format. The embedded prompt is a
single fixed five-item checklist (Security, Correctness, Performance, Consistency, Tests).

There is no whole-tree scope, no per-dimension parameter, and no second output shape. Every part of
the wrapper is diff-shaped by construction.

### P2 — `deep-refactor` does not use `reviewer.md`'s contract; it overrides it at the dispatch prompt

The skill's own "Finding schema" section requires each audit agent to return a JSON array whose
elements carry `id` (formed `<dimension>-<file_basename>-<hash3>`), `dimension`, `severity` as
P1/P2/P3, `risk_level`, `file`, `line`, `description`, `fix_type` (`coder`/`refactorer`/`debugger`/
`report-only`) and `suggested_fix`.

Against P1's schema, only `file`, `line` and a prose problem statement have counterparts.
`dimension`, `risk_level`, `fix_type` and `id` have none. The `reviewer` agent here is a vehicle,
not a contract: `deep-refactor` replaces both its input scope and its output format.

### P3 — the fields with no counterpart are exactly the ones that authorise source edits, and nothing downstream re-derives them

This is the decisive measurement. `deep-refactor` computes `ROUTABLE_TOTAL` as the count of
findings where `fix_type != "report-only"` AND `risk_level != "high"` AND `dimension != "security"`,
and its Phase 2 per-dimension loop selects the fix agent by reading `F.fix_type` and dispatches it
against production source under `isolation: worktree`.

The only re-classification anywhere in the skill is the security dimension, which is forced
report-only by an invariant regardless of what the agent returned. For dead-code, perf and
structure, `risk_level` and `fix_type` travel from the audit agent to the fix dispatch unmediated.
**There is no triage step between them.** The contrast with RTF is structural, not stylistic: RTF's
Step 2 classifies every finding against its own table before anything is routed, so a substituted
backend's output is re-judged locally by a mechanism this repo owns. `deep-refactor` has no
equivalent — the audit output *is* the routing decision.

What rests on those two fields is not incidental. ADR-0018 records two **mandatory guards** as part
of the initial design, derived from constraints it calls "physically true, not conventions":
symbols reachable only through reflection, `@objc`, `dynamic`, `#selector`, string-typed ObjC bridge
identifiers or protocol witnesses; and anything touching `async`/`await`/`actor`/`DispatchQueue`/
`Sendable`/`nonisolated`. Each guard is implemented as one instruction, given verbatim to the
reviewer, and its entire mechanical effect is to make the model set `risk_level: high` →
`fix_type: report-only`. The guard *is* that field. ADR-0018 names the failure the guards prevent as
the worst outcome available to this skill — a green test suite hiding a runtime crash or race that
the skill itself introduced.

### P4 — Branch A's fallback shape would be worse here than at ADR-0187's Site 4

A substitution would have to cover both dispatch branches, since the skill's own text forbids them
diverging. Branch A (Workflow `agent()` fan-out) is the default whenever no project manifest is
present or `hook_verified: true`; Branch B (sequential `Agent` tool) activates only on an explicit
`hook_verified: false` override.

A Workflow script has no `AskUserQuestion` hook, so the never-silent fallback gate used at every
other site cannot run inside it. ADR-0187 solved that at Site 4 with a deferred design — record the
skipped entry, continue, ask once after `Workflow()` returns — and justified it on the grounds that
checkpoint review is advisory-only and a skipped one never halts the chain.

That justification does not transfer. A Codex-unavailable *dimension* silently removes a quarter of
the audit, and `deep-refactor`'s Phase 3 writes `No security findings detected.` whenever the
security dimension yields nothing — a line that cannot distinguish a clean tree from a dimension
that never ran. That is this repo's rule 4 ("did not run" is not "found nothing") reappearing at a
new site, in the one dimension the system has three separate times decided must always be surfaced.

The Workflow-side Codex invocation is also an unverified premise in its own right. ADR-0193's live
check was a standalone RTF cycle; the Step 5 Workflow path — which describes running the wrapper
"via `agent()`'s own `Bash`-equivalent execution inside the stage callback" — is not among the paths
that correction exercised. Assumed, not verified.

### P5 — measured frequency does not match the per-invocation figure

`deep-refactor` is not a per-cycle step. `concept-to-code` lists it among the skills invokable
inside the chain "gate 5.1 only, conditional on user choice", and `hitl-gates.md` records the
autopilot default for Gate 5.1 as "Skip". The other path is a deliberate standalone invocation.

The five sites ADR-0187 did cover run on every RTF cycle, or on every checkpoint-enabled Step 5.
Expected saving here is per-invocation volume multiplied by an operator-chosen, low frequency;
engineering cost is paid once and maintained forever. The raw per-invocation number overstates the
case considerably.

## Decision

### D1 — Codex substitution is not extended to `deep-refactor`'s Phase 1 audit. Closed as decided, not deferred

In order of weight:

1. **The substituted output would be the fix authorisation, not a report (P3).** At all five
   ADR-0187 sites, a Codex finding is read by a human at a gate or by RTF's triage table before
   anything edits source. Here it routes a `coder`/`refactorer`/`debugger` dispatch directly. An
   adapter would have to *synthesise* `risk_level` and `fix_type` from a schema that has no field
   carrying them — which means synthesising ADR-0018's two non-negotiable guards, whose only
   expression is those fields. A guard reconstructed by a mapping table in a shell script is not
   the guard ADR-0018 specified; it is a heuristic standing where a judgement by the model that
   read the code used to be.
2. **The wrapper would have to be rebuilt, not extended (P1, P2).** A whole-tree scope where all
   three existing scopes resolve to a `git diff`; a fourfold prompt family where there is one
   checklist; a second `--output-schema`; a JSON formatter replacing the markdown one; and
   synthesis of an `id` no Codex output produces. That is a second script wearing the first one's
   name.
3. **The second-copy problem compounds.** ADR-0187 already records as a Negative that
   `reviewer.md`'s contract exists in two independent copies with no automated drift check. Serving
   `deep-refactor` adds four more prompt copies, two of which carry guard text ADR-0018 calls
   non-negotiable and a harness already pins as a structural anchor. Prose that must stay identical
   across a Claude dispatch prompt and a `codex exec` prompt, with nothing checking that it does, is
   rule 17's producer/consumer gap — the same class of defect that made every Codex choice in RTF
   fail with exit 127 until ADR-0193's 2026-09-06 correction, and the one place this skill can
   least afford it.
4. **The silent-failure shape is worse than at any covered site (P4).**
5. **Measured frequency does not carry the cost (P5).**

### D2 — Record the closure inside the skill, so its absence stops reading as an oversight

The gap is invisible from inside `deep-refactor/SKILL.md`: nothing there mentions Codex at all,
which is precisely how a future session re-derives this as an unfinished item. The artifact is a
short note in the skill, under its "Four dimensions" section, stating that Codex substitution is
deliberately not offered here and why — the audit output authorises fixes and is never re-triaged —
naming this ADR.

Prose only: no branch, no ask, no manifest read, no behavioural change of any kind.

**No harness assertion is added for it, deliberately.** Pinning the presence of a paragraph would
produce a green check proving the paragraph exists, not that a future designer read it — rule 16's
distinction between an instruction and an enforcement. The exposure this leaves is stated plainly
under Negative rather than papered over with an assertion that would not close it.

### D3 — `security-audit` is unbundled from ADR-0187's joint deferral; it is the stronger candidate, and it is not decided here

ADR-0187 deferred `security-audit` and `deep-refactor` in a single clause, which reads as one
reasoning covering both. Measured, they are opposite cases:

- **`security-audit`.** Its Step 2 dispatch exists to obtain a second opinion from a *genuinely
  different model*. The skill's own rule is explicitly not "always opus" but "always different from
  whatever model is doing the dispatching", and it states that a same-model self-review does not
  satisfy the step — ADR-0049's generator/verifier problem reappearing in the security domain. A
  different vendor's model is therefore not a cost substitution at that site; it is a closer
  implementation of what the step already demands, and it would make a rule currently expressed as
  a conditional pin ("opus unless the session is already opus") robust by construction. Per
  ADR-0056 §D4 the skill reports and never fixes, so no synthesised field would gate any edit —
  P3's objection is absent there.
- **`deep-refactor`.** The inverse: substitution feeding an auto-fix loop with no intervening
  triage.

The two must not be decided symmetrically, and that joint clause is the thing this ADR corrects.
Whether Codex should actually be wired into `security-audit`'s Step 2 — and whether an
ADR-0187-shaped *substitution* is even the right frame there, versus adding Codex as the preferred
backend for a step that already requires model diversity — belongs to its own ADR. Naming it here is
the point: a future session taking up ADR-0187's deferral list should pick up `security-audit`, not
`deep-refactor`.

Per rule 14, ADR-0187 is not edited. Its deferral clause was a correct record of what was decided on
its date; this ADR is the forward correction.

### D4 — At this site the cheaper lever is scope, not backend (recorded, not decided)

If the per-invocation cost of a `deep-refactor` run is the real problem, the mechanism that reduces
all four dispatches proportionally already exists and needs no new backend: `enumerate-sources.sh`
takes an optional path-override argument, Step 0.6 already passes it through, and
`SOURCE_FILE_COUNT` is already surfaced at Gate 0. Making that override reachable from Gate 0, or
surfacing a size estimate before the audit fans out, would cut the same spend without touching the
finding schema, the two mandatory guards, or either dispatch branch.

Recorded as the direction a future cost pass should take here. Not decided in this ADR, which
answers the backend question only.

## Alternatives considered

**A1 — Full substitution: add `--mode audit --dimension <d>` to `codex-reviewer.sh`, emitting
`deep-refactor`'s nine-field JSON schema, and branch at both Branch A and Branch B.** Rejected. It
needs a whole-tree scope the wrapper does not have (all three existing scopes resolve to a `git
diff`), a fourfold prompt family, a second output schema, a JSON formatter replacing the markdown
one, and synthesis of `id`, `dimension`, `risk_level` and `fix_type`. The last two are precisely the
fields that decide whether a fix agent may edit production source (P3), and the only place
ADR-0018's two non-negotiable guards are expressed. The result is a second script under the first
one's name, and a guard reduced to a mapping heuristic.

**A2 — Substitute only the security dimension, where the schema mismatch is inert.** The
best-shaped of the substitution options, and worth stating rather than dismissing: security is
forced report-only by an invariant this system has recorded three times, so every synthesised field
is discarded and only `file`, `line`, `severity`, `description` and `suggested_fix` reach the
report. Rejected on economics and on failure shape. It still requires the whole-tree scope mode, a
new schema and a new formatter — most of A1's engineering — to substitute one of four dispatches,
about a quarter of the spend. And it places Codex on the exact dimension where a silent skip is
least detectable, since Phase 3 prints `No security findings detected.` for an absent dimension and
an empty one alike (P4). Paying most of the cost for a quarter of the benefit, at the site with the
worst failure shape, is the wrong corner of the trade.

**A3 — Restrict substitution to Branch B, the sequential `Agent`-tool path, where an interactive
fallback gate is structurally possible.** Rejected. Branch B is not the default: it activates only
when a project manifest explicitly carries `hook_verified: false`, a manual override. A feature
reachable only through an override is a feature that will not be exercised, and it deliberately
reintroduces a branch asymmetry at the same site where `workflow-dispatch-pins.test.sh` was written
after Branch A silently ran on the session's model instead of the pinned one. Adding a second
asymmetry months after a harness was added to close the first is the wrong direction.

**A4 — Leave ADR-0187's deferral as it stands and write nothing.** Rejected. The deferral is
invisible from inside the skill, which contains no Codex mention at all, so the next reader
re-derives it as an oversight and repeats this analysis from scratch. It also leaves
`security-audit` bundled with `deep-refactor` under a single clause when measurement shows them to
be opposite cases (D3) — meaning the item most worth carrying forward stays mislabelled as
equivalent to the item that should not be.

## Consequences

### Positive

- The highest-volume review site keeps a single audit contract. `risk_level` and `fix_type` continue
  to be set by the same model that read the code, not synthesised by an adapter from a schema that
  never carried them.
- ADR-0187's deferral list shrinks by a *decided* item rather than an aged one, and the stronger of
  the two skills it bundled is named as the one to take up next.
- No third and fourth copies of review-contract prose are created, so ADR-0187's already-recorded
  drift exposure does not grow — and ADR-0018's two guards keep exactly one authoritative wording.
- Behaviour is unchanged: apart from D2's note, `deep-refactor` is untouched.

### Negative

- The strongest per-invocation token saving available anywhere in the system is left on the table,
  and this ADR does not replace it with anything that saves tokens. D4 names a cheaper lever but
  explicitly does not decide it.
- D2's note is documentation with nothing behind it. A future edit can delete it and restore exactly
  the "reads like an oversight" state this ADR exists to end. Accepted knowingly (rule 16), but it
  is a real exposure, not a closed one.
- The decision rests in part on a premise that was never measured: whether four whole-tree agentic
  `codex exec --sandbox read-only` runs would produce an audit of comparable quality, and at what
  Codex-quota cost. Building the mode was judged not worth it before measuring it. If that premise
  is wrong, it is wrong in the direction of this ADR being too conservative.
- Reasoning ordered by field ownership rather than by cost means an operator under real weekly-quota
  pressure may reasonably reopen this. D4 is where that pressure should be directed; reopening D1
  without a new answer to P3 would not be.

### Neutral

- No manifest field and no schema bump. `use_codex_review` stays exactly as ADR-0187 defined it and
  ADR-0193 re-timed it; `deep-refactor` never reads it, before or after this decision.
- No change to `codex-reviewer.sh` — its two modes, its availability cascade, its exit-code contract
  and its deployed location at `~/.claude/hooks/codex-reviewer.sh` are all untouched.
- No new HITL gate. `deep-refactor`'s Gate 0 / Gate 1 / Gate 2 sequence is unchanged, and Gate 5.1's
  autopilot "Skip" default is unaffected.
- The other items ADR-0187 deferred — `coder`/`tester` dispatch, Gate 5.06, and `--autopilot` runs —
  are not addressed here and remain open exactly as that ADR left them.

## Verification

This ADR changes no mechanism, so verification is about its premises rather than about a diff.

- **No harness is affected.** D1 alters nothing executable, so none of the suites pinning
  `deep-refactor`'s dispatch branches — `workflow-dispatch-pins`, `dispatch-completion`,
  `refactor-snapshot-deep-refactor` — has a new assertion to satisfy or a stale one to repair. D2's
  note, when written, is prose inside a `SKILL.md` subtree the markdown lint already excludes.
- **Verified 2026-09-06 by reading the files, not by trusting a prior summary of them (rule 13):**
  - zero case-insensitive `codex` matches anywhere under `staging/plugin/skills/deep-refactor/`
  - `codex-reviewer.sh`'s three `--diff-scope` values and their `git diff`/`git show` resolution;
    its BLOCKER/MAJOR/MINOR/NIT `--output-schema`; the absence of any whole-tree or dimension
    argument
  - `deep-refactor`'s nine-field finding schema, the `ROUTABLE_TOTAL` predicate, and the Phase 2
    dispatch keyed on `F.fix_type`, with no re-classification step between them
  - both mandatory verbatim guards, and that each acts solely by setting `risk_level`/`fix_type`
  - Gate 5.1's conditional invocation and its autopilot "Skip" default in `hitl-gates.md`
  - `security-audit`'s Step 2 "always different from whatever model is doing the dispatching" rule
    and its same-model-does-not-satisfy clause
- **Assumed, not verified:** that a Workflow stage can execute `codex-reviewer.sh` at all. ADR-0193's
  live check was a standalone RTF cycle; the Step 5 Workflow-path description of running it inside a
  stage callback has not been exercised live. This ADR does not depend on the answer — it declines
  to build on that path either way — but a future `security-audit` or Step 5 pass does, and should
  measure it rather than inherit the assumption.
- **Not measured, deliberately:** the Codex-quota cost and finding quality of four whole-tree
  agentic `codex exec` runs. Measuring either requires first building the `--mode audit` path that
  A1 rejects. The decision turns on contract ownership (P3), which does not depend on those numbers;
  the omission is disclosed under Negative rather than hidden.

## References

- `staging/plugin/skills/deep-refactor/SKILL.md` — the skill; unchanged except for D2's note
- `staging/plugin/scripts/codex-reviewer.sh` — the wrapper's two modes and diff-only scopes
- `staging/plugin/skills/security-audit/SKILL.md` — Step 2's different-model rule (D3)
- `staging/plugin/skills/review-triage-fix/SKILL.md` — Step 2 triage, the re-classification
  `deep-refactor` has no equivalent of
- `staging/plugin/skills/concept-to-code/references/hitl-gates.md` — Gate 5.1 and its autopilot
  default
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` — the Workflow-path
  Codex invocation this ADR declines to reuse
- `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh` — the path-override argument
  behind D4
- `staging/plugin/scripts/tests/workflow-dispatch-pins.test.sh` — the Branch A/Branch B divergence
  harness cited in A3
- `docs/architecture/ADR-0187-codex-review-gate.md` — the deferral this closes
- `docs/architecture/ADR-0193-codex-review-choice-at-dispatch.md` — dispatch-time ask; the corrected
  `~/.claude/hooks/codex-reviewer.sh` deploy path
- `docs/architecture/ADR-0018-deep-refactor-skill.md` — the two non-negotiable guards
- `docs/architecture/ADR-0056-110-sast-security-audit.md` — §D4, report-only
- `docs/architecture/ADR-0016-dynamic-workflows-step5.md` — Workflow dispatch and `hook_verified`
- `docs/architecture/ADR-0049-103-generator-verifier-separation.md` — the framing `security-audit`'s
  Step 2 reuses

## Correction (2026-09-08)

`staging/plugin/skills/deep-refactor/SKILL.md`, named above in References as "unchanged except for
D2's note", no longer exists — `deep-refactor` was migrated out of this repo's vendored surface
(`docs/architecture/ADR-0197-deep-refactor-migrated-to-istefox-skills.md`, Accepted 2026-09-07); the
skill's canonical source is now `github.com/istefox/Skills`. `enumerate-sources.sh`, also named
above (behind D4), is retained at its exact original path as a declared `contract-reference:`. This
migration made no decision about Codex substitution one way or the other — the deferral this ADR
records stands unchanged; this note only corrects the reference's target (rule 14).
