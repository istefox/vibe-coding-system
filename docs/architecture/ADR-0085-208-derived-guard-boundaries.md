# ADR-0085 — A derived guard states where its derivation stops, and fails when the boundary moves

- **Status:** Accepted
- **Date:** 2026-07-30
- **Issues:** #208 (closed)
- **Related:** ADR-0077 (#193, the transcript-scan class guard), ADR-0079 (#196, grant coverage),
  ADR-0043 (a check that validates its own list is blind to what the list omits), ADR-0084 (the
  sibling half of phase 6.4)

## Context

Three guards shipped in the last days derive their population at run time, deliberately, because
instance-level pins do not generalise. Each stops at a boundary, each boundary is disclosed in its
ADR, and nothing checked any of them. One question asked three times: **what is outside this
derivation, and would we notice?**

## Decision

### D1 — The guard goes on the DENOMINATOR, not on the matches

`transcript-scan-rule.test.sh` derived over `plugin/scripts/*.sh` only. Measured again today, the
premise still holds: **no skill script reads a transcript** (0 of 38 candidates).

So the risk is not what the sweep would miss if widened — `T1` catches a non-compliant reader in
either root, verified by planting one under `skills/vibe-status/scripts/`. The risk is the **glob
silently ceasing to resolve**. `T0`'s single `N >= 8` is satisfied by the hooks alone, so a renamed
subtree would leave the skills root uncovered with the count still green. A count guard satisfiable
by a different population than the one at risk is not guarding what it appears to guard.

`T0b` therefore counts **candidates**, not matches: 38 `.sh` files resolved, 0 of them
transcript-touching. Zero matches is the expected and correct result; zero candidates is a broken
derivation, and from the outside those two look identical.

`population()` now takes file paths instead of a directory, because the two roots sit at different
depths and a second dir-shaped function would be two predicates that agree today — the failure this
file exists to guard, one level up.

### D2 — The `compliant()` false positive is left in place, and the decision is executable

The predicate starts from the jq read of `user` entries, so a hook reading the transcript any other
way returns "non-compliant" at the first step. That verdict is **indistinguishable** from the
verdict on a bash hook that scans every entry: a genuinely compliant third shape and the exact
defect the file exists to catch produce the same output.

Extending the predicate for a shape nobody has written is speculative, and the failure direction is
loud rather than silent, so it stays. What #208 asked for is that the next author meet the decision
instead of inventing an exemption — and a comment is a claim, so `Z5` makes it an assertion: a
python3 reader that **does** obey the rule is pinned as reported-non-compliant, with the instruction
that the correct response is to extend `compliant()` and **never** to exempt the hook. An exemption
there would be false: the hook complies, and the waiver would record the opposite for every later
reader.

### D3 — The scoped-agent list is derived from the hook's own `case` arm

Section J derived grant words from two agent files named by hand, while the set of scoped agents is
decided in `agent-command-scope.sh`'s `case "$AGENT_TYPE" in` arm. Two places that had to agree with
nothing making them agree: a third scoped agent would have had its grants unchecked while `J3`
stayed green. `J0a` derives the names from the arm, `J0b` requires each to resolve to a real agent
file — a typo yields an empty file list, an empty file list yields zero grant words, and `J3` reads
that as "nothing unclassified". Third time in this issue that a derivation needs its own guard.

### D4 — Running the third-agent case found a fourth boundary nobody had named

The probe was meant to confirm `J3` extends by itself. It did — and `coder.md` grants a **bare
`Bash`**, unrestricted, which yields zero `Bash(<word> …)` entries. Section J's entire argument is
that an agent can only invoke what its frontmatter grants and that the granted executors are all
covered (ADR-0079 §D1). For an agent with an unrestricted grant that argument does not hold at all,
and its silence would look exactly like coverage.

`J0c` asserts no scoped agent holds one. It is not hypothetical: `coder` is a real agent, one line
of the hook away from being in scope.

Found by running the derivation against a hypothetical, not by reading it — the same route that
found ADR-0079's R2 boundary and ADR-0083's #218.

## Consequences

- Three guards now fail loudly where they used to stop quietly. None of them changes an executable
  file: `agent-command-scope.sh` and the two enforcing hooks are byte-untouched.
- **`compliant()`'s false positive is still there**, now with an assertion pinning it as expected.
  Whoever writes a python3-shaped transcript reader will see a failure naming their file. That is
  the intended cost of the decision, not an accident of it.
- The transcript population still stops at two roots. A reader living anywhere else —
  `staging/user/`, a hook outside `plugin/scripts/` — is outside both globs and outside `T0b`'s
  denominator guard. The boundary moved; it did not disappear.
- `J0c` reads the `tools:` line for an exact bare `Bash` token. An agent granting `Bash(*)` or any
  other spelling of "everything" would pass it.
- `T0a`, `J0a` and `J0b` pass before and after on the current tree — forward guards, not fix
  evidence. All five new assertions were seen RED on a planted defect: subtree renamed (`T0b`),
  rogue reader planted under a skill (`T1`, the proof the widening is real), predicate widened
  (`Z5`), arm removed (`J0a`), arm typo (`J0b`), and `J0c` firing on a real third agent.
