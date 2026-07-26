# SPEC — Accessibility and i18n gates

Source: GitHub issue #120

## Objectives
1. Turn accessibility from a template instruction into a checked gate result.
2. Add internationalisation items to the review checklist.

## Scope
In: an accessibility checklist result at c2c Gate 5.05 for UI-bearing chains; i18n items in `reviewer.md`; a new test file in both CI registries.
Out: running an automated accessibility auditing tool; WCAG conformance certification.

## Stack
Markdown skill instructions + agent checklist.

## Architecture
- Modified: `concept-to-code/SKILL.md` Gate 5.05, which currently auto-runs the UI layout audit (`concept-to-code/SKILL.md:1745`) — it must now assert a checklist result.
- Modified: `staging/plugin/agents/reviewer.md` — i18n items.
- Modified: the `step5-report.json` schema — additive accessibility result.
- New: test file in both CI registries.

## Data model
`accessibility: [{item, status}]` where item covers labels on interactive elements, contrast, dynamic-type/scaling, keyboard or VoiceOver reachability, and focus order. Additive.

## API / Interfaces
The gate reports; it does not block an unattended run. A missing item is recorded in `step5-report.json` and in the morning report.

## UI flows
None beyond the gate output.

## Edge cases
- A chain touching no UI files must produce no accessibility section — the gate is inert otherwise.
- The i18n items must cover non-ASCII input handling, hardcoded English user-facing strings where a catalogue exists, and Latin-script assumptions in validation.
- The gate must not become blocking on the unattended path.

## Success criteria
- [ ] A chain touching no UI files produces no accessibility section.
- [ ] A chain touching UI files records a checklist result with each item marked.
- [ ] The reviewer checklist contains the i18n anchors.
- [ ] Nothing blocks on an unattended path.
- [ ] The new test file is registered in BOTH CI registries.
