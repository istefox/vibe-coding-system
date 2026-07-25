# ADR-0045 — Deny mutating git to architect and reviewer, wrapper included

**Status:** Accepted
**Date:** 2026-07-25
**Issue:** #58 (gap 1; gap 2 shipped as ADR-0041)
**Completes:** ADR-0042, which closed architect's direct path and disclosed this one

---

## Context

ADR-0036 gave `architect` and `reviewer` interpreter grants for verification by execution:
`Bash(bash *)` and `Bash(python3 *)` for both, plus `Bash(awk *)` for reviewer. Those subsume every
command their git grants exclude. ADR-0042 narrowed architect's git grant to five read-only
subcommands and stated plainly that `bash -c "git commit …"` still reached git. Reviewer has had
read-only git grants since ADR-0036 §2.5 and a prompt-level "never run mutating git or shell
commands" that nothing enforced.

**This was deferred three times in one day, always for the same reason:** closing it means inspecting
command content, and a denylist on `git commit` blocks `rg "git commit" .`, a legitimate read-only
search. The objection was recorded in ADR-0041, in issue #91, and again in ADR-0042.

**The objection does not survive contact with the actual matching rule.** It is true of a substring
match and false of a **command-position** match. A verb inside quotes is data; it never sits at a
command position. Verified against real command strings before any code was written:

| command | verdict |
|---|---|
| `bash -c "git commit -m x"` | deny |
| `bash -c "cd docs && git commit -m x"` | deny |
| `rg 'git commit' .` | allow |
| `bash -c 'grep "git commit" docs/x.md'` | allow |
| `python3 -c "import yaml,sys; yaml.safe_load(...)"` | allow |
| `bash staging/plugin/scripts/tests/x.test.sh` | allow |

The case that blocked the fix for a day is not a false positive. It is section C of the test file,
and every assertion in it passes.

## Threat model

**This is a guardrail against an agent taking a shortcut, not a sandbox against an adversary.**

String inspection cannot be otherwise. `subprocess.run(["git","push"])` splits the verb across list
elements. `eval`, base64 and variable splicing defeat it outright. No regex closes that, and a
stronger claim would be false.

What it does deliver: the plausible accident stops, and deliberate evasion stops being a gray area.
An agent that wraps a command to get around a block it was told about is doing something
unmistakable, and the audit log records it.

Two known bypasses are pinned in the test file as **expected-allow** (section E). If a future change
closes one, that section fails and whoever closed it has to update this paragraph in the same commit
— the limitation is versioned with the code instead of drifting out of a document nobody re-reads.

Anyone who reads this hook as a security boundary will misuse it.

## Decision

`agent-command-scope.sh`, a `PreToolUse` hook on `Bash`, active only when `.agent_type` is
`architect` or `reviewer`. Inert for the orchestrator and every other agent; allow on every failure
mode (no `jq`, no `agent_type`, no command, malformed JSON). Same discipline and shape as
`agent-write-scope.sh` (ADR-0041).

**R1 — command position.** A mutating git verb at a shell command position: start of string, or
after `;`, `&&`, `||`, `|`, a brace, a backtick, `$(`, or an interpreter's `-c` and its opening
quote. This covers the wrapper case and, as cheap defence in depth, a direct call — which matters
because ADR-0036 §2.1 is exactly how a grant gets widened back without anyone noticing.

**R2 — interpreter shell-out.** An exec construct (`os.system`, `subprocess.*`, `system(`,
`execSync`, `popen`, `%x{`, `IO.popen`) **and** a mutating git verb anywhere in the command.
Compound by design: `os.system("git log")` passes on the verb, `print("git commit")` passes on the
construct, only the combination denies.

Read-only verbs are deliberately absent from the mutating set. Denying `git log` here would
contradict the frontmatter grant ADR-0042 left in place.

Both agents' files gain a **Command scope** bullet naming what is enforced and saying that the
interpreters are for verification, not for routing around the git scope. Test F pins prose and hook
together — the lesson ADR-0041 Finding A and ADR-0042 both landed on.

### Alternatives considered

**Remove the interpreter grants.** Rejected: ADR-0036 §2.1 evidenced both from real dispatches —
running the hermetic test harness, `python3` one-liners for YAML and frontmatter shape. Removing them
breaks documented, routine work to close a narrower hole.

**Deny inline code (`-c`) outright, keeping `bash <script>`.** Attractive because it needs no content
inspection at all, and rejected for the same reason as above: the evidenced `python3` use *is* inline
code. It would have blocked the legitimate case and left the illegitimate one only slightly harder.

**Do nothing and keep disclosing it.** The status quo for a day, and defensible — the hole requires a
deliberate wrap. Rejected once the false-positive objection turned out to be an artifact of substring
matching rather than a property of the problem.

## Consequences

### Positive

- The wrapper path is closed for both agents; reviewer's long-standing prompt-level invariant is
  enforced at the tool layer for the first time.
- The `rg "git commit"` case and ten other read-only realities are pinned as allow (section C), so a
  future tightening that breaks them fails loudly.
- The audit log records every decision with the rule and verb that fired.

### Negative / residual

- **The bypasses in the threat model are real and remain open.** Section E asserts they pass.
- **Second-order execution is invisible.** `bash x.test.sh` is allowed; if that script commits, the
  hook sees only the outer call. Following it would mean reading arbitrary files at hook time, which
  is a different design with its own cost.
- `fetch`, `pull`, `clone` and `init` are in the mutating set. They are network or working-tree
  operations neither agent has any reason to run, but they are not destructive, so this is stricter
  than "mutating" strictly requires. Deliberate: the failure direction is a denied read, recoverable
  by reporting it, against an unrequested network call.
- Deployed by `sync-to-claude.sh` but **wired by hand** — `settings.json` is not auto-synced. Until
  wired it is installed and never invoked; the sync script prints a conditional reminder that
  disappears once done.

## References

- ADR-0041 — `agent-write-scope.sh`, gap 2, whose shape this copies
- ADR-0042 — narrowed architect's git grant and disclosed this gap by name
- ADR-0036 §2.1, §2.5 — the interpreter grants and the evidence for them
- `staging/plugin/scripts/tests/agent-command-scope.test.sh` — 31 assertions, sections A–G
