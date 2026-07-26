# SPEC — External-dependency feasibility gate

Source: GitHub issue #114

## Objectives
1. Refuse to dispatch an agent into a task it cannot finish because a credential or consent flow is missing.
2. Turn that condition into a clean skip rather than a token burn.

## Scope
In: an external-dependency declaration in the plan; gate G13 at c2c Gate 2 and in nightly Phase P; an additive manifest field; a new test file in both CI registries.
Out: provisioning credentials automatically; evaluating alternative pre-authenticated platforms.

## Stack
Markdown skill instructions + bash 3.2.

## Architecture
- Modified: the architect's plan template — declare third-party APIs, auth flows, cloud consoles, externally provisioned resources.
- Modified: `concept-to-code/SKILL.md` Gate 2 and `nightly-autopilot/SKILL.md` Phase P.
- Modified: manifest schema — additive `external_dependencies`.
- New: test file in both CI registries.

## Data model
`external_dependencies: [{name, kind, provisioned: true|false|unknown}]`. Additive.

## API / Interfaces
Checks, per the issue: credentials exist and are already provisioned; no interactive browser consent is required mid-task. On failure the chain does not dispatch.

## UI flows
Interactive: route to the human for provisioning. Phase P: mark the feature `[~]` with a `needs-human` note, reusing the skip path that already exists for thin issues — it must not halt the roadmap.

## Edge cases
- A plan declaring no external dependency dispatches unchanged (the common case; must stay zero-cost).
- `unknown` must be treated as not provisioned — default strict.
- The Phase P skip must not write the run-level halt marker.

## Success criteria
- [ ] A plan with no external dependency dispatches unchanged.
- [ ] A plan with an unprovisioned dependency refuses dispatch and names the missing item.
- [ ] In Phase P the feature is marked `[~]` with a `needs-human` note and the roadmap continues.
- [ ] A manifest without the field still validates.
- [ ] The new test file is registered in BOTH CI registries.
