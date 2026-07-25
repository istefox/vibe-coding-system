# ADR-0042 — Narrow the architect's git grant to read-only subcommands

**Status:** Accepted
**Date:** 2026-07-25
**Issue:** #91
**Supersedes:** ADR-0036 §2.1, in part — the `Bash(git *)` entry only. The rest of §2.1 (the five
other entries, the widening rationale, the evidence base) stands unchanged.

---

## Context

ADR-0036 §2.1 replaced architect's bare `Bash` with six scoped entries and justified the set with:

> None of `rm`, `mv`, `chmod`, `curl`/`wget`, `sed -i`, `dd`, `git commit`/`git push`, or any
> package-install command … is in the allowlist.

The entry it chose was `Bash(git *)`. By that same section's own citation of
`code.claude.com/docs/en/permissions` — "using a space before a wildcard … enforces a word
boundary" — the space stops `gitfoo` from matching and does nothing else. `Bash(git *)` matches
**every** git subcommand. §2.1 lists `git log`, `git diff`, `git show` as the intended matches and
then asserts an exclusion its own pattern does not express.

`permissions.deny` is not a backstop either: it covers `git push --force`, `git push -f`,
`git reset --hard`, `git clean -f/-x/-d`, `git checkout --`, `git restore`, `git stash drop`, and
neither plain `git commit` nor plain `git push`. **The architect could commit and push**, and the
session allow list pre-approves `Bash(git commit*)` for the orchestrator, so it would not even have
prompted.

Two details make this a correction rather than a reversal:

- **Issue #40's own SPEC already named the symptom.** `SPEC.md:11`: "Nothing at the tool layer stops
  a mutating command today." The intent was on record before ADR-0036 was written; only the pattern
  diverged from the reasoning.
- **It was found by accident.** Issue #58 asked for a hook against a *wrapped* mutating command
  (`bash -c "git commit …"`). Reading the grants to size that work turned up the direct path sitting
  open next to it — a bigger hole than the one being fixed, requiring no wrapper at all. Disclosed in
  ADR-0041 Finding B and deliberately left there, because closing it supersedes an Accepted decision.

## Decision

`architect.md`'s `tools:` line replaces `Bash(git *)` with:

```
Bash(git log*), Bash(git diff*), Bash(git show*), Bash(git status*), Bash(git rev-parse*)
```

**No-space form, deliberately.** The ADR-0036 implementation plan's Risk B warned against a coder
"correcting" blueprint's space/no-space inconsistency by accident, since the two forms differ in
matching semantics. This normalises it on purpose, toward sec. 3.3's blueprint-native
`Bash(git diff*)` for reviewer. The looser prefix match reaches plumbing variants
(`git diff-index`, `git show-ref`); every one of them is read-only, and no mutating git subcommand
begins with `log`, `diff`, `show`, `status`, or `rev-parse`.

`architect.md` gains a **Command scope** bullet in Edge Cases, beside the existing Write-scope
bullet, naming the same five subcommands and telling the agent not to route around them. Test A14
asserts every subcommand granted on the `tools:` line appears in that bullet.

### Alternatives considered

**Add `Bash(git commit*)`/`Bash(git push*)` to `permissions.deny` (issue #91's Option B).**
Rejected — and the issue was wrong to offer it as the cheap path. `permissions.deny` is
session-global with no per-agent scoping, and `staging/user/settings.json`'s *allow* list carries
`Bash(git add*)` and `Bash(git commit*)` because the `commit` skill needs them. Deny overrides allow,
so the rule would block the orchestrator's own commit flow at every HITL gate in the chain. There is
no agent-scoped deny mechanism: agent frontmatter has a `tools` field and nothing else. This is not
a trade-off, it is unworkable, which is what leaves Option A as the only enforcement path.

**Correct the prose only (Option C).** Rejected. It grants a capability by inertia: the architect
would keep commit and push not because anyone decided it should, but because a wildcard was written
one way in 2026-07-11. The whole point of §2.1's paragraph was that the grant should be materially
narrower than bare `Bash`.

**Keep blueprint fidelity.** ADR-0036 valued `Bash(git *)` explicitly as blueprint's text reproduced
byte-for-byte, and `agent-tool-scoping.test.sh` A1 pinned it. That value is real and is why this
needed an ADR rather than a quiet edit — but it cannot outrank a grant that contradicts its own
stated purpose. Blueprint sec. 3.1's code block is **not** edited (historical illustration,
ADR-0034 precedent); the divergence is recorded in the stacked correction beside it, which is the
mechanism sec. 3.1 already uses for exactly this.

**Extend the hook instead.** Rejected: `agent-write-scope.sh` (ADR-0041) governs writes. Denying
mutating git through a `PreToolUse` hook on `Bash` means inspecting command content, which is gap 1
of issue #58 and carries a genuine false-positive surface (`rg "git commit"` is a legitimate
read-only search containing the denied string). A frontmatter fix needs none of that machinery.

## Consequences

### Positive

- The direct mutation path is gone. Grant and rationale agree for the first time.
- The prose/grant divergence that produced this defect is now a CI assertion (A14), not a habit.
- A13 forward-guards against anyone spelling out a mutating entry by hand. It passes before the fix
  as well as after — it is a guard, not evidence that anything was repaired.

### Negative / residual

- **Issue #58 gap 1 is untouched and this ADR does not close it.** `Bash(bash *)` and
  `Bash(python3 *)` remain, so `bash -c "git commit …"` still reaches git. What changes is that
  reaching it now requires deliberately wrapping the command, which no legitimate architect task
  does. **Reviewer** was checked in the same pass and is unchanged: its git grants were already
  read-only per ADR-0036 §2.5, and its exposure is the same wrapper class, so nothing here applies
  to it beyond the disclosure.
- **Command forms that no longer match:** `git -C <path> log`, `git --no-pager log`, and any other
  option placed before the subcommand. Architect's git use is optional context-gathering — no chain
  brief asks it for git, and `Read`/`Grep` do the real work — so a denied variant degrades rather
  than breaks. It is still a behaviour change, named here rather than discovered later.
- `architect.md` now has a `PAIRS` entry in `sync-to-claude.sh`. It is the first agent file to get
  one: the sync script did not touch `agents/` at all, so without it this fix would have reached
  `staging/` and never the agent that is actually dispatched.

## References

- ADR-0036 §2.1, §2.5 — the decision superseded in part, and reviewer's parallel grant
- ADR-0041 Finding B — where this was found and disclosed
- ADR-0034 — the precedent for correcting a blueprint illustration forward rather than in place
- `docs/superpowers/plans/2026-07-11-40-agent-tool-scoping.md` Risk B — the space/no-space semantics
- `staging/plugin/scripts/tests/agent-tool-scoping.test.sh` — A1, A12–A15 (39 assertions total)
