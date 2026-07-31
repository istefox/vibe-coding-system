# ADR-0092 — The documented value domain named a value nothing has ever written

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #240 (found by the Phase 7.1 shakedown run, at Step 5's dispatch-mode selection)
- **Related:** ADR-0076 (#195, whose §D2 worked example this corrects), ADR-0016 (the source, which
  was right), ADR-0075 (#123, the failure this would have caused), ADR-0086 (the derived-guard
  pattern, instance 8), ADR-0034 (historical records corrected forward, not edited in place)

## Context

ADR-0076 §D2 makes the value domain the **caller's**, not the helper's, and offers `step5_mode` as
its worked example: `workflow|agent_fallback|null`.

Nothing has ever written `agent_fallback`. Measured over the 41-manifest corpus: **18
`agent_batch`, 2 `workflow`, 19 `null`, 2 without the field, 0 `agent_fallback`.** Both producers
write `agent_batch` — `concept-to-code/SKILL.md` at the Workflow-refusal branch and at the fallback
activation.

Latent today, because `manifest-validate.sh` has no invariant for the field. That is what makes it a
trap rather than a bug: the wrong string sits in `manifest-field-state.sh`'s header, the live worked
example ADR-0076 tells the next author to follow. A checker built on it would assert
`workflow|agent_fallback|null`, pass on a fresh manifest (`null`), and reject all 18 historical
`agent_batch` manifests the first time it met one. That is ADR-0075/#123 replayed exactly.

### The issue was wrong about where it came from, and that is the useful part

Issue #240 named ADR-0016 as one of three carriers. **ADR-0016 is correct** and always was — §Manifest
fields reads `"workflow" | "agent_batch"`. The error entered in a **summary** of that ADR, in
`CLAUDE.md`, and spread from the summary into ADR-0076 and from there into the helper header.

So there were four wrong sites, not three, and the source was not among them. A source and its
restatements drifted, and nothing compared them.

## Decision

### D1 — Correct the live sites, record the historical one forward

`manifest-field-state.sh`'s header and both `CLAUDE.md` summaries are corrected in place: they are
live text a reader acts on. ADR-0076's body is **not** edited — ADR-0034's precedent for historical
records — and receives a dated `## Correction` section instead, naming the measurement and pointing
at what was corrected forward.

The 18 historical manifests are untouched. They are accurate.

### D2 — The fix is not four corrected strings, it is a derived guard

Correcting the strings leaves the same drift free to happen again, from any of the four sites, to
any field. Section `V` of `manifest-field-state.test.sh` derives the **written** set from the
producers (plus `manifest-init.sh`'s default) and the **documented** set from the helper's own
header, and compares them **in both directions**.

The reverse direction is what catches this defect: a documented value no producer writes. Without
it, the header could name anything at all and the forward check would still pass — the ADR-0043
direction lesson applied to a value domain rather than to a file list.

`V3` extends the comparison to the corpus: a real manifest holding a value no producer writes means
either an undiscovered writer or a hand-edit, and either way the domain is incomplete. `V4` pins
ADR-0016 as the correct source, because the drift ran source → summary and a future "correction"
applied to the source would be fixing the wrong file.

**No waiver mechanism, deliberately.** Every other instance of this pattern lets a file declare an
exemption; a value domain with an exemption is not a domain.

## Verification

Four defects planted, each reverted:

| plant | fires |
|---|---|
| header reverted to the #240 wording | **V1 and V2** |
| a value producers write dropped from the header | V1 |
| a producer made to write an undocumented value | V1 |
| the header derivation broken | V0b, V1 |

`V3`/`V4` pass before and after and are labelled as forward guards.

**Both derivations are count-guarded**, and the second one earned it: the helper's sentence wraps
across two comment lines, so the first line-based derivation returned **nothing** — which would have
made `V2` vacuously true, the exact shape it exists to catch. Fourth appearance of that lesson
family (ADR-0073 line wrap, ADR-0076 comment marker, ADR-0080 backticks, ADR-0082 one-line marker),
met while deriving a guard against a different kind of drift.

Full harness 53/53.

## Consequences

- The guard covers `step5_mode` only. `hook_verified` and `step5_review_mode` are named in the same
  sentence and are **not** derived — their producers are shaped differently and would need their own
  extraction. Stated rather than implied by the section's presence.
- `PROJECT.md` still quotes the old wording inside its own description of this issue. That is a
  record of what was reported, not a live claim, and the guard does not read it.
