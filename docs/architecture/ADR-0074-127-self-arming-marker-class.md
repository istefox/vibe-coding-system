# ADR-0074 — A marker that is both instruction and trigger: the self-arming class, and what the sibling audit found

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #127
- **Extends:** ADR-0016 Addendum 2026-07-25d (`write-scope-enforce.sh`), ADR-0045
  (`agent-command-scope.sh`), ADR-0049 §D9 (`test-write-scope.sh`, which already carries the fix)
- **Reported as:** a live chain deadlock on 2026-07-26, fixed in flight; the issue exists to have
  the class reviewed on its own terms and the siblings audited.

## Context

`write-scope-enforce.sh` extracted a fix agent's assigned file from its transcript with

```sh
jq -r 'select(.type=="user") | tostring' "$TRANSCRIPT" | grep -o 'you may edit ONLY [^ "\\]*' | head -1
```

**Tool results are `user` entries.** An architect briefed to read the hook's own source pulled the
literal grep pattern into its transcript, and the hook bound it to the scope `[^`. Writes before
the read were allowed; every write after was denied. The audit log recorded
`deny  Write out of scope: wanted=/users/stefer/developer/vibe-coding-system/[^`.

The same arming happens for any agent that reads `concept-to-code/SKILL.md`'s Phase 3 prompt, which
carries the marker verbatim. The blast radius is therefore *every agent working on the hook system
itself* — the population most likely to be told to read these files.

The one-line fix (read only the FIRST `user` entry — the dispatch prompt is structurally first, a
tool result never is) was applied on 2026-07-26. It shipped with **no regression test**, which is
the gap this ADR closes along with the audit the issue asked for.

## Decision

### D1 — The fix is structural, not a smarter pattern

No refinement of the marker can distinguish a dispatch prompt from a file that quotes it: the two
are byte-identical by construction, because the marker's purpose is to appear in both. Position is
the only discriminator available, and it is exact rather than heuristic — the dispatch prompt is the
first `user` entry in a subagent transcript, and a tool result cannot be.

### D2 — The regression test must prove the fixture is discriminating, not merely that the hook allows

`write-scope-enforce.test.sh` section E. **E0 runs the PRE-FIX extraction inline** over the fixture
and requires it to come back armed with the live incident's own value, `[^`. Without E0, E1 ("a
marker in a tool result does not arm the hook") passes against a hook that reads nothing at all, and
against a fixture that stopped reproducing the bug — rule 6 of `.claude/context.md`.

**E2/E3 are the positive twin** (rule 8): the dispatch prompt must still bind, and must still bind
to *its* path when a later tool result names a different one. E3 passes before and after the fix —
a forward guard, labelled as such, not fix evidence.

**E4 anchors the `head -1` by POSITION.** The extraction's grep stage ends in a second, unrelated
`head -1`, so a check that merely greps the neighbourhood matches a pre-fix hook too. A first draft
did exactly that and passed against a reconstructed pre-fix copy, pinning nothing.

Verified by rebuilding the pre-#127 hook and running the new section against it: **E1 and E4 fail,
everything else stays green.** That is the shape of the original invisibility.

### D3 — Sibling audit: `agent-write-scope.sh` is immune, and the reason is worth an assertion

It derives nothing from a transcript. Its scope is a constant in its own source; `.agent_type` and
`.tool_input.file_path` are its whole input. There is no text an agent can cause to be *read* that
changes what it enforces.

Recorded as assertion `F1` rather than as prose, because the property that makes it immune is
exactly the property a future "make the roots configurable per dispatch" change would remove — and
that change would look like an improvement.

### D4 — Sibling audit: `agent-command-scope.sh` had the same class of defect, reached through the command string

It reads no transcript either, so the #127 mechanism does not apply. The **class** does: a guard
that arms on text *about* the thing it guards. Here the text is the command itself.

**Finding 1 — a legitimate search was denied.** R1's command-position anchor included
`-c[[:space:]]*['"]?`, intended for `bash -c` and `python3 -c`. It is unqualified, and every search
tool spells "count matches" the same way, so `grep -c "git commit -m" f` and `rg -c "git push
origin" docs/` matched at a command position and were denied. The hook's own header says "an
**interpreter's** -c" — the prose was right and the regex was not. A reviewer auditing
`commit/SKILL.md` with the one search tool it is granted is doing in-scope work.

**Finding 2 — the headline case escaped, and it is the worse of the two.** R1's trailing boundary
was `([[:space:]]|$)`. The character after the verb in `bash -c "git push"` is the closing quote, so
the form ADR-0042 and ADR-0045 both name as *the* case this hook exists to close was **allowed**.
Section A stayed green throughout because every assertion in it happens to carry an argument after
the verb: `-m x`, `origin main`, `.`. `R2_GIT` already accepted a quote; `R1` did not.

Found by running the regex over the forms the ADRs quote, not by reading it — the same lesson as
ADR-0070's fourth defect and rule 11: a check nobody has executed against its own documented
example is unverified.

Both corrected in one pass: the `-c` anchor is qualified by an interpreter name and tolerates
combined and intervening flags (`bash -lc`, `python3 -u -c`), and the trailing class accepts a
closing quote, backtick, paren or shell separator. Pinned by sections C12–C15 (the false positives)
and H (the escapes), all ten seen RED first.

### D5 — Sibling audit: the other two transcript readers, recorded and unchanged

`test-write-scope.sh` (ADR-0049 §D9) already reads only the first `user` entry, and `TB7`/`TB8`
already pin the negative and positive cases. It learned this from the #127 incident directly; the
audit confirms it and changes nothing.

`pre-flight-pattern-enforce.sh` scans **assistant** entries for `^PATTERN: <CATEGORY> |`. Its
direction is the opposite: a match ALLOWS. A tool result therefore cannot arm it at all (it reads
no `user` entries), and a spurious match would be a **missed check, never a deadlock**. Its
main-session fallback is a wider version of the same fail-open, and is already documented as a
deliberate divergence in `write-scope-enforce.sh`'s own header. No change.

## Alternatives considered

### A — Escape or obfuscate the marker in the hook source so reading it cannot arm the hook

Rejected. It moves the problem rather than removing it: `concept-to-code`'s Phase 3 prompt must
contain the marker in plain text, because the agent has to read it as an instruction. Any scheme
that makes the *hook* unquotable leaves the *skill* quotable.

### B — Detect and skip transcript entries that look like tool results

Rejected. It is a heuristic over an encoding that has already changed once under this system's feet
(the `subagents/workflows/<wf_id>/` relocation in CC v2.1.154). Position is exact and survives an
encoding change; a tool-result shape does not.

### C — Narrow `agent-command-scope.sh`'s finding 1 by removing the `-c` anchor entirely

Rejected: it is load-bearing. Nothing else in R1's alternation matches `bash -c "git commit …"`,
which is the entire reason the hook exists. Qualifying the anchor keeps the case and drops the
false positive.

## Consequences

### Positive

- The deadlock that took a chain down is a regression test rather than institutional memory.
- The one hook whose immunity is structural now says so in CI, at the point where a future change
  would silently remove it.
- `agent-command-scope.sh` denies the case both its ADRs claim it denies. It did not before.
- Its false-positive class — read-only counting — is closed, which is what section C of its test
  file has claimed since it was written.

### Negative

- **`agent-command-scope.sh` now denies strictly more than it did**, and the newly-denied forms are
  ones the architect and reviewer may have been using successfully. That is the correct direction
  and it is still a behaviour change on a live guardrail.
- The interpreter list is a fixed enumeration. An interpreter outside it (`busybox`, an
  `env`-wrapped exotic shell, a script named for none of them) takes the `-c` path unguarded.
  Bounded by the threat model below and pinned nowhere — named here so it is not mistaken for
  covered.
- **The threat model is unchanged and still bounds all of this**: a guardrail against a shortcut,
  not a sandbox. Sections E1/E2 still pin `subprocess.run(["git","push"])` and variable splicing as
  expected-ALLOW.
- E3 and F1 pass before and after the fix. Forward guards, not evidence.

### Neutral

- No manifest field, no schema change, no new file, no `PAIRS` entry (all four scripts and all
  three test files already have theirs), no CI registry change (`ci.yml` globs the directory,
  `docs-ci.yml` already lists all three).
- `write-scope-enforce.sh` changes by comment only; its behaviour is byte-identical.
- Inert until sync for `agent-command-scope.sh`.

## References

- Issue #127, including the acceptance criteria this ADR answers point for point
- `docs/architecture/ADR-0045-58-interpreter-wrapper-bypass.md` — the threat model that still holds,
  and the header sentence finding 1 shows the regex never implemented
- `docs/architecture/ADR-0042-91-architect-git-grant.md` — where `bash -c "git commit …"` is named
  as the surviving path this hook was built to close
- `docs/architecture/ADR-0049-103-generator-verifier-separation.md` §D9 — `test-write-scope.sh`,
  which took this lesson from the incident directly
- `staging/plugin/scripts/tests/write-scope-enforce.test.sh` section E,
  `staging/plugin/scripts/tests/agent-command-scope.test.sh` sections C12–C15 and H,
  `staging/plugin/scripts/tests/agent-write-scope.test.sh` section F
