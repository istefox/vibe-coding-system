# ADR-0079 — The enumeration was not the risk, and the boundary fix had not been propagated

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #196
- **Extends:** ADR-0074 (#127, which fixed R1's trailing boundary and left R2's), ADR-0045 (the
  threat model, unchanged), ADR-0042 and ADR-0036 §2.1 (the grants this now checks against),
  ADR-0077 (the derive-the-premise instrument section J reuses)
- **Reported as:** a disclosed limit in ADR-0074's Consequences. Phase 4.3 of `PROJECT.md`.

## Context

Issue #127 qualified `agent-command-scope.sh`'s `-c` anchor by interpreter name, which closed a false
positive (`grep -c "git commit -m" f` was denied) and made the guard's reach a **fixed
enumeration**. ADR-0074 disclosed the consequence: an interpreter outside the list reaches `-c`
unguarded. Issue #196 asked whether the enumeration is the right instrument.

Two things came out of measuring rather than reasoning about it.

## Decision

### D1 — The enumeration is not the risk, because a layer above bounds it

An agent can only invoke what its frontmatter **grants**. The two scoped agents grant exactly three
executors:

| agent | executor grants |
| --- | --- |
| `architect` | `Bash(bash *)`, `Bash(python3 *)` |
| `reviewer` | `Bash(bash *)`, `Bash(python3 *)`, `Bash(awk *)` |

All three are covered — `bash` and `python3` by `INTERP_C` at a command position, `awk` through
`system()`, which `R2_EXEC` matches. **The intersection of "outside the enumeration" and "actually
invocable" is empty today.**

So option 2 from the issue (invert to a tool-exclusion list) buys nothing and costs the failure
direction: it would deny an unknown tool's `-c`, breaking legitimate work for a threat the
permission layer already closes.

### D2 — What is actually unguarded is WIDENING A GRANT, and that is now checked

Nothing would have noticed `Bash(deno *)` appearing on `reviewer.md`. The hook's header now
classifies every granted command word on both agents, in a machine-readable `# grant-covered:` line
plus a prose table, and test section J derives the words **from the agent files at run time** and
requires each to be classified.

Verified in the failing direction: adding `Bash(deno *)` to `reviewer.md` makes `J3` fail naming
`deno`. `J4` makes the classification behavioural rather than lexical — both granted interpreters
must be *caught in practice*, not merely listed. `J2` count-guards the derivation.

This is ADR-0077's instrument applied to a different pair of files: derive the population, check the
property, never hardcode today's answer.

### D3 — The real defect: R2's trailing boundary, the sibling of the one #127 fixed

Issue #127 widened `R1`'s trailing class to accept a closing quote, because `bash -c "git push"` escaped a
class of `([[:space:]]|$)`. `R2_GIT` already accepted a quote and was left alone. **It should not
have been.**

Inside a shell double-quoted string the inner quotes are **backslash-escaped**, so a verb-last call
ends `push\"` and the character after the verb is `\`:

```
python3 -c "import os; os.system(\"git push\")"         ->  ALLOWED
python3 -c "import os; os.system(\"git commit -m x\")"  ->  denied   (a space follows the verb)
```

Test `A6` passed throughout for exactly the accidental reason section A did before #127: every case
in it carries an argument after the verb.

The backslash is now in `R2_GIT`'s trailing class. Sections `H` and `I` pin both rules' boundaries
so the next reader sees them as a pair.

**Fixing a boundary in one rule and not its sibling is the lesson**, and it is the second time this
exact shape has appeared in this file. It was found by running the hook over the forms an
interpreter actually produces — not by reading it, and not by the harness, which was green.

### D4 — The compound guard still holds, and widening `R2_GIT` had to not break it

`R2` denies only when an exec construct **and** a mutating verb are both present.
`python3 -c "print(\"git commit\")"` now matches the verb half and must still be allowed. `C9`
covered the unescaped form; `I4` adds the escaped one, and `I5` keeps a read-only verb behind a real
exec construct allowed.

### D5 — The residual limit is real, bounded, and pinned as expected-ALLOW

An interpreter that is neither enumerated nor using an `R2_EXEC` construct escapes.
`lua -e "os.execute('git push')"` is the shape: `lua` is not in `INTERP_C` and `os.execute` is not in
`R2_EXEC`.

It is closed today **only by the permission layer** — a different mechanism, in a different file.
`J5` asserts it is not caught, beside `E1` and `E2`, so the limit is versioned with the code; if
someone closes it, the test fails and the threat model has to move with it.

**The threat model is unchanged:** a guardrail against an agent taking a shortcut, not a sandbox.

## Alternatives considered

### A — Invert the anchor to a tool-exclusion list (`grep`, `rg`, `sort`, `wc`, …)

Rejected per §D1. It trades one enumeration for another in the direction that denies legitimate
work, to close a gap the permission layer already closes.

### B — Anchor on the argument shape rather than the tool name

Rejected. An interpreter's `-c` is followed by code and a search tool's by a pattern plus a file
operand, but that is not reliably distinguishable, and the complexity is not worth it for a
guardrail whose threat model is a shortcut rather than an adversary.

### C — Leave it, pin the limit, change nothing else (the issue's option 1)

This is what §D5 does, and it is what the issue expected to be the whole answer. It became half of
it once §D3 surfaced.

## Consequences

### Positive

- A verb-last mutating call behind an interpreter's `system()` is denied. It was not.
- Widening a grant to a new executor fails a test instead of silently opening the `-c` path.
- The enumeration's bound is now stated with its evidence rather than as a worry.

### Negative

- **The hook denies strictly more than it did**, the second such widening in one day on a live
  guardrail. Correct direction, still a behaviour change on an unattended path.
- The grant-coverage check reads two specific agent files. A third scoped agent would need adding
  by hand — the derivation is over grants, not over agents.
- `J5`'s limit means the guard's completeness depends on `permissions`, which this hook cannot see.
  Anyone reading the coverage table as "these are the only executors" is reading a snapshot.
- `J2`, `J4`, `I4`, `I5` and every section-E assertion pass before and after. `I1`, `I2`, `I3`, `J1`
  and `J3` were the five that were RED.

### Neutral

- No new test file, no registry change, no `PAIRS` change.
- `INTERP_C` is untouched — the enumeration stays exactly as #127 left it.
- Inert until sync.

## References

- Issue #196, whose option 1 §D5 implements and whose premise §D1 corrects
- `docs/architecture/ADR-0074-127-self-arming-marker-class.md` §D4 — finding 2, whose fix this
  propagates to the sibling rule
- `docs/architecture/ADR-0045-58-interpreter-wrapper-bypass.md` — the threat model, unchanged
- `staging/plugin/scripts/tests/agent-command-scope.test.sh` sections H, I and J
