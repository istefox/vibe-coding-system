# SPEC — the value-domain guard covers step5_mode only

Source: GitHub issue #292

## Objectives

1. For each of the two uncovered fields, `hook_verified` and `step5_review_mode`, find every
   producer (what writes it) and the documented domain (what `manifest-field-state.sh`'s header
   claims).
2. Compare the two sets in **both** directions over the 41 manifests in `docs/manifests/` — the
   reverse direction, a documented value nothing writes, is what caught #240.
3. Extend the value-domain guard to both fields with count guards on both derivations, and with no
   waiver mechanism.

## Scope

In: the written and documented value domains of `hook_verified` and `step5_review_mode`; the
derivation extending `manifest-field-state.test.sh` section `V`; the count guards on both
derivations; the wrap-tolerant reading of the helper's header.

Out: `step5_mode`, already covered by ADR-0092's section `V`. Out: rewriting historical manifests —
ADR-0092 left the 18 carrying `agent_batch` untouched because they are accurate. Out: converting
`manifest-validate.sh`'s 28 invariants, which ADR-0076 explicitly declined.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/scripts/manifest-field-state.sh` — the helper whose header
  documents the domains: "hook_verified is a boolean, step5_mode is workflow|agent_batch|null,
  step5_review_mode is none|checkpoint". That sentence **wraps across comment lines**, which is what
  R-02 is about.
- Producers of `hook_verified`, measured at spec time:
  `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh` (the `false` default),
  `staging/plugin/skills/concept-to-code/SKILL.md` (the `manifest-set-flag.sh … hook_verified
  true|false` call sites keyed on the hook-verify exit code),
  `staging/plugin/skills/autopilot-build/SKILL.md` and
  `staging/plugin/skills/nightly-autopilot/SKILL.md` (readers, and pre-flight consumers),
  `staging/plugin/skills/deep-refactor/SKILL.md`,
  `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh`.
- Producers of `step5_review_mode`: `manifest-init.sh` (the `none` default),
  `staging/plugin/skills/concept-to-code/SKILL.md` (the `sed` flip on the additive field —
  `manifest-set-flag.sh` cannot do it, being boolean-only), `manifest-validate.sh` invariant 14
  (conditional, "if present").
- `docs/manifests/` — the corpus, 41 manifests measured at spec time.
- `staging/plugin/scripts/tests/manifest-field-state.test.sh` — section `V` (`V0b` written-set count
  guard, `V1` forward, `V2` reverse, `V3` corpus, `V4` the source pin), the pattern to extend.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0092-240-step5-mode-value-domain.md` (the source; anchor on its "covers
  `step5_mode` only" sentence, not `:88`), `docs/architecture/ADR-0076-195-additive-field-state.md`,
  `docs/architecture/ADR-0016-dynamic-workflows-step5.md`.

## Data model

- `hook_verified` — documented as a boolean; `manifest-init.sh` defaults it to `false`.
- `step5_review_mode` — documented as `none|checkpoint`; `manifest-init.sh` defaults it to `none`.
- Both are **additive** fields: a manifest written before the field simply does not carry it, which
  is a distinct state from invalid and from unreadable (ADR-0076 §THE RULE).

## API / Interfaces

`manifest-field-state.sh <manifest> <field>` — reports `PRESENT|<value>`, `ABSENT|<current_step>`,
or `UNREADABLE`, with exit 3 for "could not run". It reports; it never decides. The value domain
stays the caller's, which is exactly why the documented domain in its header is the artefact that
must be checked against the producers.

## UI flows

None.

## Edge cases

- **The reverse direction is the one that catches the defect.** A documented value nothing writes is
  what #240 was; without `V2`'s shape the header could name anything and the forward check would
  still pass.
- **A wrapped sentence yields an empty documented set**, which makes the reverse assertion vacuously
  true — ADR-0092 records that the first line-based derivation returned nothing. R-02 requires the
  derivation to survive the wrap; the count guard is what makes a failed derivation loud.
- **A boolean domain is not shaped like an enum domain.** `hook_verified`'s producers write YAML
  booleans through `manifest-set-flag.sh`; ADR-0076 records that a **quoted** `"true"` reads `true`,
  not `True`, and that this strictness is deliberate. The derivation must not "fix" that.
- **`step5_review_mode` is written by `sed` on an additive field**, not by a helper, so its producer
  is prose in a SKILL.md rather than a script — a differently shaped producer, which is the stated
  reason ADR-0092 left both fields out.
- **No waiver mechanism** (R-03): a value domain with an exemption is not a domain. This diverges
  deliberately from the exemption-carrying derived guards elsewhere in the harness.
- **A manifest predating a field is not a domain violation.** The `ABSENT` state must not be fed
  into the written set, or every pre-field manifest reads as writing an undocumented value.
- **The wrong string sat in the live worked example for months.** #240 was latent because nothing
  checked, and the example is the one ADR-0076 tells the next author to follow.

## Success criteria

- [ ] R-01 — written set and documented set derived at run time for both fields and compared in both
      directions, with count guards on both derivations.
- [ ] R-02 — the derivation must survive a sentence that wraps across comment lines; ADR-0092
      records that the first line-based derivation returned nothing and would have been vacuously
      true.
- [ ] R-03 — no waiver mechanism: a value domain with an exemption is not a domain.
