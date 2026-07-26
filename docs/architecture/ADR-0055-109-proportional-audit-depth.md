# ADR-0055 — Proportional audit depth: risk and task_type axes

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #109 (tenth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/109-proportional-audit-depth.spec.md`
- **Builds on:** ADR-0052 / ADR-0053 / ADR-0054 for the additive-field and absent-means-X pattern —
  and §D2 is where this feature has to invert it.
- **Closes:** gaps **G-12** and **G-22** of `docs/books/INTEGRATION-REPORT-agentic-spec.md`
  (ABSENT, P2).

## Context

Gate 0 routes on `chain_path` (express / hybrid / standard), and its stated criteria are file count
and layer count — a **size** axis and nothing else. `deep-refactor` tags findings
`risk_level: high|low`, but that governs whether a finding may be auto-fixed, not how deeply the
change is audited. No task or manifest field carries risk, familiarity, or task type anywhere in the
system.

The consequence is concrete: **a three-file change to payment code and a three-file change to a
README route identically.** The agentic spec (§5.9, §15.2) makes the gate profile a function of
risk, of how well the operator knows the stack, and of task type, with the strictest axis winning.

Grove's five delegation factors (§4.5) are the same information under different names. They are
folded into this feature rather than built separately, so the system does not end up with two
scoring schemes that drift apart.

## Decision

### D1 — Two additive manifest fields: `risk` and `task_type`

`risk: low|high`. `task_type: boilerplate|glue|novel-algorithm|regulated|legacy-integration|perf-critical`.

Additive, conditional-if-present in `manifest-validate.sh`, no schema bump — the same terms as
`recovery_baseline_sha` (ADR-0050 §D3) and every additive field before it. Pre-ADR-0055 manifests
stay valid with no migration.

### D2 — Absent means STRICTEST, which inverts the pattern of the last three features

ADR-0052 (budgets), ADR-0053 (protected interfaces) and ADR-0054 (vendored CI checks) all default
to **inert when absent**. The reflex here is to do the same. It would be wrong, and the distinction
is worth stating precisely because three consecutive precedents point the other way.

The difference is the direction of the constraint:

- Those three features **add** a constraint. An absent budget, an undeclared interface, an
  unvendored script — each means "no new restriction applies", which is exactly the pre-feature
  behaviour. Inert is safe because inert equals the status quo.
- This feature **removes** constraints: a `low` risk `boilerplate` task gets a lighter gate profile
  than the chain runs today. If an unset field meant "no profile applies", every existing manifest
  would silently downgrade to the lightest audit the moment this merged.

So an unset field resolves to the strict profile, which is what the chain already does. The status
quo is preserved by defaulting to strict, not by defaulting to absent. The spec instructs the same
thing and the reasoning is worth having independently of the instruction.

**Stated as a rule for whoever adds the next axis: default to whatever preserves current behaviour.
For an added constraint that is off; for a removed constraint that is on.**

### D3 — The strictest axis wins, and the axes are never averaged

`risk: high` with `task_type: boilerplate` resolves to the **high** profile. Two axes, `max()`, not a
weighted score.

Averaging was rejected because a numeric score invites tuning, and tuning a safety profile toward
"faster" is a one-way ratchet — nobody ever tunes it back toward stricter after a quiet month. `max()`
has no dial.

### D4 — The profile governs gate depth only, never gate existence

A lighter profile may reduce review passes, skip an optional reviewer lens, or shrink the checkpoint
cadence. It may **not** remove the blocking gates: `spec-coverage.sh`, the weakening scan,
`interface-check.sh`, or the recovery-readiness pre-flight.

Otherwise the field becomes a bypass with a friendly name — a `task_type: boilerplate` label on a
payment change would disable the checks that exist for payment changes, and the label is set by the
same process being checked.

### D5 — Gate 2 is where the axes are set, by a human

The architect proposes `risk` and `task_type` from the plan's content; Gate 2 is where the operator
confirms. Not auto-derived and applied silently, for the §D4 reason: a self-assigned label that
lowers your own audit depth is not a control.

### D6 — Grove's five factors are folded in, not built separately

They map onto the same two axes rather than becoming a third field. Two scoring schemes for the same
judgment would drift, and the one that is easier to satisfy would win.

## Alternatives rejected

- **A1 — Default to inert/absent like the last three features.** Rejected under §D2. This is the
  alternative most likely to be chosen by pattern-matching, and it silently downgrades every
  existing chain.
- **A2 — A numeric risk score with weights.** Rejected under §D3: invites tuning, and safety
  profiles only ever get tuned one direction.
- **A3 — Let a light profile skip blocking gates.** Rejected under §D4: turns the field into a
  self-served bypass.
- **A4 — Auto-derive risk from file paths** (e.g. anything under `payments/` is high). Rejected as a
  *sole* mechanism — a useful proposal input, but path heuristics miss risk that lives in logic
  rather than location. It informs §D5's proposal, it does not replace the confirmation.
- **A5 — A separate Grove-factor field.** Rejected under §D6.

## Consequences

### Positive

- The chain stops treating a README edit and a payment change identically.
- Effort concentrates where the spec says it should, without weakening any blocking gate (§D4).
- No migration; every existing manifest keeps its current behaviour exactly (§D2).

### Negative, stated plainly

- **Self-assessed risk is weak evidence.** The operator setting `risk: low` is the person who wants
  the run to go faster. §D5's human confirmation is a check on the architect, not on the operator;
  nothing checks the operator. This is a real limitation and the honest mitigation is §D4 — the
  gates that matter most cannot be lowered at all.
- **A third pattern to remember.** Absent means inert in three recent ADRs and strict in this one.
  §D2's rule ("default to whatever preserves current behaviour") is prose, and prose has not
  successfully prevented the reporter/checker confusion across four ADRs either.
- **Inert in practice until architects set the fields** — like its three predecessors, the value
  arrives after the merge.
- Instruction, not enforcement: the harness pins that the fields, the resolution rule and the §D4
  floor exist; nothing pins that a model applies the right profile.
