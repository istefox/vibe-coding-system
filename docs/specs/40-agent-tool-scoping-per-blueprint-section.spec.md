# SPEC — Agent tool scoping per blueprint section 3

Source: GitHub issue #40

## Objectives
1. Reconcile the agent definitions in `staging/plugin/agents/` with blueprint section 3 where tool scoping drifted without a recorded reason (audit findings 2.19, 2.20, 3.29, 3.30).
2. Where blueprint and deployed file disagree, this feature's ADR decides which side wins and records why.

## Scope
In (`staging/plugin/agents/`, refreshed from deployed by issue #29; the defects exist in the deployed copies too — the fix lands in staging and reaches deployment at the next human sync):
1. `architect.md` (P2): unrestricted Bash and unscoped Write, `permissionMode: plan` dropped. Blueprint 3.1 pins `Bash(git *), Bash(rg *)` plus `permissionMode: plan`; the docs/architecture write scope is prose-only; ADR-0013's pilot recorded an architect editing outside its declared scope. Nothing at the tool layer stops a mutating command today.
2. `reviewer.md` (P2): unrestricted Bash where blueprint line 674 scopes it to `Bash(git diff*), Bash(git log*)`. The reviewer processes untrusted diff content, and the live allow list pre-approves git add and git commit, so an injected mutating command would not even prompt.
3. `architect.md` effort pin (P3): deployed says max, blueprint 3.10 pins xhigh, no note records the change.
4. `researcher.md` (P3): relies on the global context7 plugin tools with no inline mcpServers block, while blueprint 3.8 claims the inline server makes it self-contained.

Default expectation, absent a stronger argument: restore the blueprint frontmatter (scoped Bash for architect and reviewer, effort xhigh, inline mcpServers for researcher), because each widening removed a structural guard without a recorded reason. The alternative on any item is an ADR-recorded deliberate divergence with a compensating control, plus a blueprint deployment note.

Out:
- Any file under `~/.claude` (deployment at the next human sync).
- Agents not named (coder, tester, debugger, refactorer, doc-writer) beyond incidental consistency.

## Stack
Markdown agent definitions (YAML frontmatter), blueprint `docs/vibe-coding-system.md`, ADR under `docs/architecture/`.

## Architecture
`staging/plugin/agents/{architect,reviewer,researcher}.md` frontmatter; blueprint section 3 deployment notes where a divergence is kept; this feature's ADR as the decision record.

## Data model
None.

## API / Interfaces
Agent frontmatter contract: `tools` scoping entries, `permissionMode`, effort pin, optional inline `mcpServers` block.

## UI flows
None.

## Edge cases
- A divergence judged deliberate: ADR records it with a compensating control and the blueprint gains a deployment note instead of a frontmatter revert.
- Blueprint edits must preserve section numbering and the changes-log conventions.

## Success criteria
- [x] architect and reviewer frontmatter carry scoped Bash entries, or the ADR records the deliberate widening with a compensating control
- [x] The effort pin matches blueprint 3.10, or a deployment note in the blueprint records the divergence
- [x] researcher matches blueprint 3.8, or the 3.8 deployment note is corrected to describe plugin-tool reliance
- [x] Blueprint edits preserve section numbering and the changes-log conventions
- [x] No file under `~/.claude` modified
