# ADR-0041 — Hook-level Write-scope enforcement for the architect agent

**Status:** Accepted
**Date:** 2026-07-25
**Issue:** #58 (gap 2 of two; gap 1 split out — see Consequences)
**Amends:** ADR-0036 §3.3, which disclosed this gap and left it open

---

## Context

ADR-0036 scoped `architect.md`'s tool grants and recorded one gap it could not close:

> Unscoped `Write` on architect has no frontmatter-level fix — path patterns are documented for
> Read/Grep/Edit only.

So `architect.md`'s "you may only write under `docs/...`" line was prose. Nothing stopped the agent
from writing source, config, or tests, and the chain would not have noticed.

Issue #58 asked for a `PreToolUse` hook. Investigating it first surfaced two things the issue did
not know.

### Finding A — the declared scope was wrong, and enforcing it literally would have broken the chain

`architect.md:73` said `docs/architecture/**` only. But concept-to-code Step 2 instructs the
architect to write its plan to `docs/superpowers/plans/YYYY-MM-DD-<slug>.md` (`SKILL.md:357`) and
**hard-aborts** when that path is absent from the report (`SKILL.md:409`). A hook enforcing the
file's literal claim would have denied a write the chain requires, on every single run.

The agent file was wrong, not the chain. It now names both roots, and
`agent-write-scope.test.sh` section E keeps file and hook in agreement while B2 guards the plan
path specifically.

### Finding B — ADR-0036 §2.1 asserts an exclusion its own grant does not express

§2.1 states that "none of `rm`, `mv`, … `git commit`/`git push` … is in the allowlist" while
granting `Bash(git *)`. By that section's own word-boundary citation, `Bash(git *)` matches every
git subcommand, `commit` and `push` included. The global `permissions.deny` list catches
`git push --force`, `git reset --hard` and `git clean -f`, but not plain `git commit` or `git push`.

**Not resolved here.** `agent-tool-scoping.test.sh` A1 pins `Bash(git *)` as blueprint's text
reproduced byte-for-byte — a deliberate, reasoned choice. Narrowing it would supersede an Accepted
decision, which does not belong in a PR about Write scope. Recorded as its own issue.

## Decision

`agent-write-scope.sh`, a `PreToolUse` hook on `Write|Edit|MultiEdit`. When `.agent_type` is
`architect`, it allows `.tool_input.file_path` under `docs/architecture/` or
`docs/superpowers/plans/` and denies everything else, with a reason naming both roots and telling
the agent to report the needed change rather than route around the block.

**Deliberately simpler than `write-scope-enforce.sh` (ADR-0016 Addendum 25d).** That hook derives a
per-dispatch scope from the prompt and must read the calling subagent's transcript to find it.
Here the scope is static per agent type, so `.agent_type` and `.tool_input.file_path` are the whole
input — no transcript, no `agent_id`, no coupling to any prompt.

Path matching is a **substring** test on the two documentation segments, not a prefix test against
a project root. The payload's `cwd` is not a reliable stand-in for the project root when the
architect runs from a subdirectory, and a wrong root would deny legitimate writes. Substring
matching is looser but errs toward allowing — the correct direction for a guard whose false
positives break the chain.

Every failure mode allows: no `jq`, no `agent_type`, no `file_path`, malformed JSON. Inert for
every agent type other than `architect`.

## Consequences

### Positive

- The ADR-0036 §3.3 gap is closed with a control rather than a sentence.
- `Edit` and `MultiEdit` are covered alongside `Write`; constraining one and leaving the others
  open would have been enforcement in name only (pinned by D1/D2).
- Finding A is now caught by CI rather than by a chain failing at Step 2.

### Negative / residual

- **Gap 1 of #58 is not implemented.** The interpreter-wrapper bypass (`bash -c "git commit …"`)
  needs command-content inspection, and that has a false-positive surface worth its own design
  pass: `rg "git commit"` is a legitimate read-only search whose command string contains the
  denied pattern. For `architect` the gap also narrows substantially if Finding B is ever acted
  on; for `reviewer` it stays real, since `Bash(bash *)` and `Bash(python3 *)` subsume its
  deliberately read-only git grants. **#58 must not be closed on this ADR alone.**
- **Finding B is disclosed, not fixed.** The architect can `git commit` and `git push` today.
- The hook is deployed by `sync-to-claude.sh` but **wired by hand**, since `settings.json` is not
  auto-synced. Until wired it is installed and never invoked; the sync script prints a conditional
  reminder that disappears once done.
- Substring matching would also allow a write to an unrelated path that happens to contain
  `docs/architecture/` as a segment. Accepted: contrived, and the failure direction is permissive.

## References

- ADR-0036 §2.1, §3.3 — the scoping pass that disclosed this gap and contains Finding B
- ADR-0016 Addendum 2026-07-25d — `write-scope-enforce.sh`, the per-dispatch sibling
- ADR-0034 — the `permissionDecision` enum correction this hook's deny output relies on
- `staging/plugin/scripts/tests/agent-write-scope.test.sh` — 13 assertions
