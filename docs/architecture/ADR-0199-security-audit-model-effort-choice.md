# ADR-0199: Live Codex model/effort choice at `security-audit` Step 2

- **Status:** Accepted
- **Date:** 2026-09-09
- **Extends:** ADR-0195 (established the `--focus security` fixed pin, `gpt-5.6-sol`/`high`, that
  this ADR makes live-selectable while keeping as the default), ADR-0198 (gave `review-triage-fix`
  and `concept-to-code` Step 5 the same live sub-ask shape, deliberately left `security-audit`'s
  §R6 override arm unreachable pending this ADR)

## Context

ADR-0198 added a live `AskUserQuestion` model+effort sub-ask to two of `codex-reviewer.sh`'s three
chooser sites (RTF Step 0 item 6, `concept-to-code` Step 5 checkpoints), both defaulting
`sol`/`medium`. The third site, `security-audit` Step 2, was named in that ADR's own "out of
scope" section (§Consequences: Negative) as a deliberate follow-up, not a gap.

Stefano asked which agents currently offer a Codex choice; reviewing the answer, he asked to
extend the same live sub-ask here. Investigating first (rule 13, `behavior.md`): the existing pin
is not the same kind of thing as RTF's/Step 5's old pins. ADR-0195 §M6 chose `sol`/`high`
deliberately — `security-audit` is verified as the system's lowest-volume (on-demand only, wired
into no chain, zero autopilot path), highest-miss-cost review site, and Stefano personally capped
effort at `high` over `xhigh` on 2026-09-06. RTF's/Step 5's old `terra`/`medium` pin was pure cost
optimization; this one is a deliberate quality floor. Reusing ADR-0198's `sol`/`medium` default
here would be a silent downgrade at the highest-stakes site, not a neutral consistency move.
Asked and confirmed: **the sub-ask's default stays `sol`/`high`**. The operator can still choose
differently, but pressing Enter must keep buying today's elevated guarantee.

## Decision

**`security-audit` Step 2's `[codex]` branch gains the same `--model`/`--effort` sub-ask shape as
ADR-0198, with one deliberate divergence: the default is `sol`/`high`, not `sol`/`medium`.**

Fires only on `[codex]`, in the same gate turn as the existing backend-choice ask, before
dispatch — mirroring ADR-0198's RTF/Step 5 sub-asks exactly in mechanism, differing only in which
values are marked default/Recommended. The Step 2 invocation line is updated from

```
--focus security --out <tmp-review-file>
```

to

```
--focus security --model <chosen-model> --effort <chosen-effort> --out <tmp-review-file>
```

**`codex-reviewer.sh` itself needs no change.** ADR-0198 §R6 built the override-priority logic
this extension needed before this ADR existed: an explicit `--model`/`--effort` overrides
`--focus security`'s own pin, unconditionally, because a live operator choice is definitionally an
override of any pin. §R6 named this arm "presently unreachable in practice" for lack of a caller
that passes both — this ADR is that caller. §Consequences (Negative) flagged the override path as
"untested against a real caller" until `security-audit` reached it; this ADR closes that gap.

**No manifest field, no persistence design.** `security-audit` resolves no manifest at all
(ADR-0195 §D2, its own hard constraint: "No manifest field, no wiring into any chain"). Unlike
ADR-0198's RTF/Step 5 work — which needed two new manifest fields, `sed`-substitution persistence,
and a legacy-manifest HALT guard for a manifest predating the fields — this choice is asked fresh
every invocation, exactly as the existing backend ask already is. This is the simplest of the
three `codex-reviewer.sh` chooser sites to extend.

## Refinements folded in after the draft

**R1 — the default diverges from ADR-0198's `sol`/`medium`, and this is the point, not an
inconsistency.** ADR-0195 §M6's `sol`/`high` pin and ADR-0198's `sol`/`medium` pin answer
different questions: ADR-0195 asked "what does the highest-miss-cost, lowest-volume review site
need," ADR-0198 asked "what does routine, high-frequency review cost." Making both live does not
obligate them to converge on one default. The skill's own prose states the divergence explicitly
(`sol/medium default (ADR-0198), this sub-ask defaults to sol/high`) so an operator reading Step 2
in isolation, without cross-referencing RTF or Step 5, still sees it named rather than silently
inherits the wrong assumption.

**R2 — `--focus security` stays in the invocation line, unchanged position, flags appended.** The
sub-ask does not replace the security-focus scoping; it only makes the model/effort half of the
dispatch live. `--focus security` continues to select the security-only review brief (ADR-0195
§D3) independent of which model/effort backend serves it — this is the same separation of
concerns ADR-0198 §R6 already reasoned through, exercised for real here for the first time.

**R3 — no autopilot skip-clause needed.** RTF's item 6 and Step 5's checkpoint sub-ask each needed
explicit reasoning about resume/skip behavior (ADR-0198 §R2/§R3) because both are chain-wired,
multi-turn flows. `security-audit` has no autopilot path and no manifest to resume from (ADR-0195
§M6, unchanged) — the sub-ask simply fires every time `[codex]` is chosen, with nothing to gate or
skip.

## Alternatives considered

1. **Default `sol`/`medium`, matching RTF and Step 5 for uniformity.** Rejected: this is the
   silent downgrade identified during investigation and explicitly rejected by Stefano — trading
   uniformity for a real reduction in the guarantee ADR-0195 built this pin for, at the system's
   highest-miss-cost site.
2. **Leave `security-audit` on its fixed pin, out of scope permanently.** Rejected: ADR-0198 named
   this as a deliberate follow-up, not a closed decision, and Stefano explicitly asked to extend
   it once the divergence was surfaced and reasoned through.
3. **Give `security-audit` its own persistence (a lightweight per-invocation cache), rather than
   asking fresh every time.** Rejected: `security-audit` resolving no manifest is ADR-0195's own
   hard constraint (§D2); introducing persistence here would be new scope this ADR does not need
   and ADR-0195 did not ask for.

## Consequences

### Positive

- The `sol`/`astra`/`terra` × six-effort matrix is now directly selectable at all three
  `codex-reviewer.sh` chooser sites, closing the follow-up ADR-0198 named.
- `codex-reviewer.sh` required zero changes — concrete confirmation that ADR-0198 §R6's
  forward-looking override design was correct.
- ADR-0198's "untested against a real caller" note on the `--focus security` override path is
  closed: `security-audit` is now that caller, and the offline exit-2/override assertions extend
  to cover it (`sast-security-audit.test.sh` SG10-SG13).
- Today's elevated `sol`/`high` guarantee is preserved as the default, not silently traded away
  for cross-gate consistency.

### Negative

- **`security-audit` Step 2 now asks two questions instead of one on the `[codex]` branch**, same
  added-interaction cost ADR-0198 disclosed for RTF/Step 5, here on a low-volume site where the
  added friction is proportionally smaller.
- **An operator who chooses a lower effort than `high` is making an informed trade against
  ADR-0195's own stated rationale** for this site — the skill's prose states this explicitly at
  the point of choice, but nothing in the mechanism prevents choosing `low` on the system's
  highest-miss-cost review.
