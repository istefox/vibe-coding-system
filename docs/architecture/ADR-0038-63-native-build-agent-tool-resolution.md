# ADR-0038 — Native-build agent tool resolution: Grep/Glob absent when Bash is granted

**Status:** Accepted
**Date:** 2026-07-14
**Author:** istefox
**Supersedes:** none
**Amends:** ADR-0036 (reviewer Bash scope: adds `Bash(rg *), Bash(grep *)` to the deployed set)
**Related:**

- GitHub issue #63 (this ADR is its root-cause classification and fix of record)
- ADR-0036 (`40-agent-tool-scoping`) — the frontmatter reconciliation whose reviewer scope this ADR
  widens; the asymmetric-widening rationale (verification tools yes, mutation tools no) is reused
  unchanged
- Blueprint `docs/vibe-coding-system.md` sec. 3.3 deployment note and "Correction 2026-07-14
  (issue #63)" changelog entry — the two blueprint records this ADR is the reasoning for
- "Audit 2026-07-14 (CC 2.1.206–2.1.209)" blueprint entry — the post-upgrade smoke test that
  surfaced the finding

## 1. Context

The 2026-07-14 post-upgrade smoke test (one dispatch per custom agent, CC 2.1.209) found that all
six Bash-equipped agents (architect, coder, reviewer, tester, debugger, refactorer) launch without
the dedicated Grep and Glob tools declared in their frontmatter, while the two agents without Bash
(doc-writer, researcher) receive them as declared. A forced-call probe confirmed the drop is real,
not a self-report artifact: the debugger agent, asked to call Grep directly, reported "no tool
named Grep is registered for this agent". LSP (declared on coder, reviewer, debugger) and the
coder's `memory: local` Memory tool were absent on the same agents.

Root cause, classified from the changelog bundled with the installed CLI
(`~/.claude/cache/changelog.md`):

- **v2.1.117:** "Native builds on macOS and Linux: the `Glob` and `Grep` tools are replaced by
  embedded `bfs` and `ugrep` available through the Bash tool — faster searches without a separate
  tool round-trip (Windows and npm-installed builds unchanged)." This is the mechanism: Bash
  serves the search path, so the dedicated tools are not registered when Bash is available.
- **v2.1.119:** "Fixed Glob and Grep tools disappearing on native macOS/Linux builds when the Bash
  tool is denied via permissions." This is why the two Bash-less agents still get the dedicated
  tools.
- **v2.1.162:** "`--tools`: explicitly listing Grep/Glob now provides the dedicated search tools on
  native builds with embedded search (previously these names were silently ignored)." The fix
  covers the CLI flag only. Agent frontmatter was not covered; the 2026-07-14 probe shows a
  frontmatter listing is still silently ignored on a native build when Bash is present.

Verdict: **intentional platform behavior since v2.1.117, not a regression**, and not new in the
2.1.206–2.1.209 range. Two gaps remain upstream: the sub-agents docs page shows a Bash+Grep
example with no caveat (and documents ToolSearch deferral for MCP tools only), and CC 2.1.208's
new tools-list validation fires only when the list resolves to nothing, so this partial drop stays
silent by construction.

Practical impact is confined to reviewer. Every other Bash-equipped agent reaches `rg`/`grep`
through its Bash scope. Reviewer's ADR-0036 scope (`git diff*`, `git log*`, `bash *`, `awk *`,
`python3 *`) allows neither, leaving `bash -c 'grep …'` as its only search path on the build this
system actually runs on. Its body also mandates an "LSP first pass" that cannot execute in a
native-build subagent.

## 2. Decision

1. **Keep `Grep, Glob, LSP` in agent frontmatter.** The entries are honored on npm and Windows
   builds and are inert, not harmful, on native builds. Removing them would make the agent files
   build-specific for no gain.
2. **Widen reviewer's Bash scope with `Bash(rg *), Bash(grep *)`.** Read-only search commands,
   the same verify-by-execution category ADR-0036 already admitted (architect carries `Bash(rg *)`
   today). On native builds these are exactly the embedded ugrep/bfs path v2.1.117 introduced. The
   mutation exclusions (no `git add`/`commit`/`push`, no `npx`, no `shasum`) are unchanged.
3. **Make reviewer's LSP first pass conditional.** The step now starts by checking tool
   availability and skips to git inspection when LSP is absent, instead of instructing a call that
   cannot happen.
4. **Record the behavior in the blueprint** (sec. 3.3 deployment note plus a dated Correction
   entry) so sec. 3's frontmatter examples are read as build-dependent where Grep/Glob appear next
   to Bash.

## 3. Alternatives considered

- **Remove Grep/Glob/LSP from all Bash-equipped agents' frontmatter.** Rejected: correct on native
  builds only; the same files deploy unchanged to npm/Windows installs where the entries work.
- **Give reviewer unrestricted Bash instead of two scoped additions.** Rejected: reverses
  ADR-0036's threat-model decision (reviewer processes untrusted diff content) for a problem two
  read-only grants solve.
- **Rely on the `bash -c` escape hatch and change nothing.** Rejected: it works, but it routes
  every search through an interpreter wrapper the ADR-0036 Consequences already flag as an
  accidental-misuse risk, and it leaves the frontmatter telling a false story about how the agent
  searches.

## 4. Consequences

- Reviewer regains a direct, scoped search path on the build this system runs on; the change is
  two additive allowlist entries, no new tool classes.
- The `Bash(grep *)`/`Bash(rg *)` grants are read-only in intent but, like every scoped Bash grant,
  match on command prefix only; the residual interpreter-wrapper risk recorded in ADR-0036
  Consequences is unchanged by this ADR.
- Disclosed, deferred: coder and debugger bodies also reference LSP; coder's `memory: local`
  (pilot P1, 2026-05-29) is observed inert on this build. Each needs its own decision. A follow-up
  issue should either re-platform or retire the Memory pilot rather than leave it silently dead.
- Disclosed, not owned here: the upstream docs-page gap (Bash+Grep example without the native-build
  caveat) can be reported via `/feedback`; nothing in this repo depends on it.
- Deployment: agents reach `~/.claude/agents/` via the RUNBOOK bulk copy (`docs/RUNBOOK.md`
  Step 6), not sync-to-claude PAIRS. Until a human runs that copy, the deployed reviewer keeps the
  narrower scope, the same staging-first convention as ADR-0024 through ADR-0036.

## 5. References

- `~/.claude/cache/changelog.md` (bundled CC 2.1.209): v2.1.117, v2.1.119, v2.1.162 entries quoted
  in Context
- `code.claude.com/docs/en/sub-agents` and `/en/mcp` (fetched 2026-07-14): Bash+Grep example
  without caveat; ToolSearch deferral documented for MCP tools only
- Live verification 2026-07-14 (CC 2.1.209): 8-agent smoke dispatch plus forced-call probe on
  debugger
- GitHub issue #63; blueprint "Audit 2026-07-14 (CC 2.1.206–2.1.209)"; ADR-0036
