# SPEC — Untrusted-input hardening for issue-driven design

Source: GitHub issue #113

## Objectives
1. Treat a GitHub issue body as data, never as instructions to the agent.
2. Restrict which authors can drive an unattended design run.
3. Record the residual risk honestly.

## Scope
In: prompt fencing for the issue body; an instruction-shaped-line pre-filter; an author allowlist configured in the opt-in marker; a new test file in both CI registries.
Out: defending against a compromised repo-owner account; sandboxing the agent runtime.

## Stack
Markdown skill instructions + bash 3.2 filter + `gh issue view --json author`.

## Architecture
- Modified: `spec-from-issue/SKILL.md` — fence the body with an explicit untrusted-content preamble.
- New: a pre-filter script neutralising instruction-shaped lines (imperative directives aimed at the agent, tool-call syntax, role-switch attempts, "ignore previous instructions" patterns).
- Modified: `nightly-autopilot/SKILL.md` Phase P — author allowlist check.
- Modified: `.claude/nightly-autopilot.yml` schema — `prep.allowed_authors`.
- New: test file in both CI registries.

## Data model
`prep.allowed_authors: [<handle>, ...]`. Absent means repo owner only.

## API / Interfaces
The filter is a reporter plus a transform: it returns the neutralised body and a list of what it neutralised, so the generated SPEC can carry a provenance note.

## UI flows
None; unattended.

## Edge cases
- A normal issue body must produce the same SPEC it produces today — this is the regression to protect.
- A non-allowlisted author is skipped with a `needs-human` note, not processed and not halting the whole roadmap.
- Code blocks in an issue body are legitimate content and must survive the filter.
- The ADR must state plainly that this is a mitigation, not a sandbox.

## Success criteria
- [ ] An issue from a non-allowlisted handle is skipped with a `needs-human` note.
- [ ] An injection attempt is neutralised and the neutralisation is visible in the SPEC's provenance note.
- [ ] A normal issue body produces the same SPEC as today.
- [ ] A fenced code block in a body is preserved.
- [ ] The new test file is registered in BOTH CI registries.
