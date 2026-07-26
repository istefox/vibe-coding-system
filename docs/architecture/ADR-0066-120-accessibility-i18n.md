# ADR-0066 — Accessibility and i18n gates

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #120 (twenty-first and final feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/120-accessibility-i18n.spec.md`
- **Closes:** gap **G-26** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (PARTIAL, **P3**).

## Context

`ui-layout-audit` and `macos-ux` exist as review skills, and c2c Gate 5.05 auto-runs the UI layout
audit. `staging/project-templates/ios-swiftui/CLAUDE.md` carries an "Accessibility (required)"
section.

So accessibility is a **template instruction and a review skill, but not a gate**, and
internationalisation is absent entirely.

The spec names both as systematic AI omissions: accessibility appears in its demo-quality trap list
("accessibility completely overlooked"), and it records that training repositories skew Western and
English, so generated code tends to overlook Unicode and multibyte support and default to
English-centric examples.

The spec also states flatly that accessibility **"is a gate, not an aspiration"** (§15.3).

## Decision

### D1 — Gate 5.05 asserts a checklist RESULT, not merely that the audit ran

Today the gate runs `ui-layout-audit`. Running a review is not the same as recording what it found —
a step that always completes is indistinguishable from a step that always passes, which is the
failure ADR-0043 and ADR-0046 each hit in a different form.

So for UI-bearing chains the gate records a result against named items: labels on interactive
elements, contrast, dynamic-type or scaling, keyboard or assistive-technology reachability.

### D2 — It records an answer; it does not block

The spec calls accessibility a gate, and this ADR does not fully honour that. Recorded as a
divergence rather than glossed.

The reason is what a blocking gate would be blocking *on*. Every item on the checklist is a
judgement made by a model looking at code — "does this control have a meaningful label" is not
`interface-check.sh`'s "is this signature present". Blocking on a model's self-assessment of its own
UI work is the generator/verifier problem ADR-0049 exists to fix, and this roadmap has established
five times that heuristics report and mechanical facts gate.

**What changes is that an answer becomes mandatory.** Today nothing is recorded at all; after this,
a UI-bearing chain that ignores accessibility has to say so explicitly in the report, where a human
reviewing Gate 5 sees it. That is weaker than the spec asks for and stronger than what exists.

A genuinely blocking accessibility gate needs a real checker — an axe-core or accessibility-inspector
run — which is a larger piece of work and belongs to its own issue. Named here so the gap is visible.

### D3 — i18n is a checklist item, not a framework decision

Unicode and multibyte handling, no hardcoded English-centric assumptions in examples or test
fixtures, no locale-dependent formatting assumed.

Deliberately narrow. Introducing an i18n framework, a string-catalogue convention or a locale
strategy is a project's architectural choice, not something a chain gate should impose. What the
gate can usefully catch is the *systematic omission* the spec describes — code that assumes ASCII
and English because its training data did.

### D4 — Conditional on UI-bearing chains, and inert otherwise

Gate 5.05 is already conditional on UI files being present, and this inherits that condition. A
CLI-only or docs-only chain records nothing.

Consistent with ADR-0055 §D2's rule: this adds a constraint, so absent equals the pre-feature
behaviour.

### D5 — No detector

Contrast ratios need rendering; label meaningfulness needs judgement; "English-centric example" is
not a pattern. A grep-based accessibility checker would produce confident nonsense.

Fourth consecutive P3 feature to reach this conclusion (ADR-0062 §D4, ADR-0063 §D4, ADR-0065 §D2),
and the accumulation is itself worth noting: the remaining gaps in this roadmap are the ones where
mechanisation does not help, which is why they are P3.

## Alternatives rejected

- **A1 — Block the chain on a failed accessibility checklist.** Rejected under §D2, and recorded as
  a divergence from the spec rather than as agreement with it.
- **A2 — Keep running the audit without recording a result.** Rejected under §D1: a step that always
  completes looks exactly like a step that always passes.
- **A3 — Impose an i18n framework or string-catalogue convention.** Rejected under §D3: a project's
  architectural choice.
- **A4 — Build a grep-based accessibility detector.** Rejected under §D5.
- **A5 — Apply the gate to every chain.** Rejected under §D4: an accessibility question on a
  shell-script chain is noise, and noise is what gets gates ignored.

## Consequences

### Positive

- Accessibility moves from "a skill that ran" to "an answer that was recorded", which is the
  difference between an aspiration and something a human can review.
- i18n appears in the system for the first time.
- Inherits Gate 5.05's existing UI condition, so no new triggering logic and no new noise.

### Negative, stated plainly

- **This does not honour the spec's "gate, not aspiration" instruction**, and §D2 says so. It makes
  the answer mandatory, not the outcome. A real blocking gate needs a real checker and its own issue.
- **The answer is a model's self-assessment of its own UI work** — the weakest evidence class, and
  the one ADR-0049 was built to remove from the test path. Nothing removes it here.
- **The i18n item is narrow by design** (§D3) and will miss anything structural.
- Fourth P3 feature in a row whose mechanism is instruction rather than machinery, and the last
  feature of this roadmap. What remains after it is the work that mechanisation genuinely cannot do.
