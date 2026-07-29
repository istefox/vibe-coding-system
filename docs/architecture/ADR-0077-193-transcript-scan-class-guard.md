# ADR-0077 — The self-arming rule becomes a derived check, and the exemptions move into the source

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #193
- **Extends:** ADR-0074 (#127, the instance and the audit), ADR-0067 §F6 (the derived-population
  instrument this copies), ADR-0043 (the direction lesson), ADR-0049 §D9 (`test-write-scope.sh`,
  which took the lesson from the incident directly)
- **Reported as:** derived from the #127 audit, not from a failure. Phase 4.2 of `PROJECT.md`.

## Context

Issue #127 fixed one hook and audited three. Every guard it left behind is **instance-level**:

- `write-scope-enforce.test.sh` `E4` anchors `head -1` in *that* hook
- `test-write-scope.test.sh` `TB7`/`TB8` pin the same pair in *that* one
- `agent-write-scope.test.sh` `F1` asserts *that* one reads no transcript at all

Nothing asserted the **rule**. A new marker-driven hook, or an existing one that gains a transcript
read, reproduces #127 with every test in the repository still green.

ADR-0067 is the standing precedent for what happens next, and it is exact. "A skill invoked from a
chain must not carry `disable-model-invocation`" was recorded in three places and enforced by
negative anchors on two specific skills. Issue #56 violated it on a **third** anyway, because
nothing checked the class. `skill-text-corrections.test.sh` `F6` closed it by deriving the
population at run time.

## Decision

### D1 — The rule, stated once

> A hook that extracts a marker from a subagent transcript must read only the **first** `user`
> entry, or declare in its own source why it does not.

Tool results are `user` entries. A full scan cannot distinguish the dispatch prompt from a file the
agent read, and the population most likely to read a marker-bearing file is agents working on the
hook system itself.

### D2 — The derivation is broad on purpose, and narrowing happens in the source

The population is every `staging/plugin/scripts/*.sh` that so much as mentions `transcript_path` or
`.jsonl` — ten files today, including probes and hooks that only take a `dirname`. Each must either
**comply** or carry a **declared exemption**.

Asking which direction the guard runs in (rule 5) is what settles this. A narrow derivation — say,
only files that call `select(.type=="user")` — validates the files it names and is blind to a file
it does not, which is #127's own failure mode applied to its own guard. A broad derivation puts a
new file in the population by default and forces it to say something.

The cost is nine exemption declarations. They are not ceremony: each says what the file does with a
transcript, which is a fact a reader currently has to reconstruct.

### D3 — Exemptions live in the hook, never in a list inside the test

`# transcript-scan-exempt: <reason>`, line-anchored, in the file's own header.

A filename-keyed list in the test is the identity-based waiver ADR-0069's `PTD` refused: it does
not travel when the file is renamed or copied, and it lets a test author excuse a hook without
touching it. `T5` asserts this test carries no such list; `T4` requires every reason to be a reason
(≥ 40 characters, not a shrug); `Z3` requires the marker to be a line-anchored declaration, so a
file that merely mentions the phrase in prose is not excused.

### D4 — The two enforcing hooks must COMPLY, not merely declare

`T2` requires `write-scope-enforce.sh` and `test-write-scope.sh` to pass the positional check, and
`T3` requires neither to hold an exemption. A file that was both would let a later edit drop the
`head -1` and still satisfy `T1` on the strength of a stale waiver.

### D5 — `pre-flight-pattern-enforce.sh` is exempt on DIRECTION, and the declaration says so is not enough

It reads `assistant` entries, so a tool result cannot arm it at all, and it **allows** on a match,
so a spurious match is a missed check rather than a deadlock. Both halves are real and the
exemption is genuine.

It is also the weaker kind of exemption, and the declaration says so in its own words: this hook's
real exposure is that the main-session fallback lets the orchestrator's own `PATTERN:` line satisfy
the check for a subagent that declared nothing. **That is issue #194, open, instrumented in phase 1,
and not closed by this exemption.** The last line of the declaration is `Do not read this line as
"audited and fine"` — because a waiver that reads as a clean bill of health is worse than none.

### D6 — The predicate's own defect, found by the guard on its first run

`compliant()` first required `| head -1` on the line **after** the jq read. That is
`write-scope-enforce.sh`'s shape. `test-write-scope.sh` writes the same pipeline on **one line**,
and was reported non-compliant on its first sweep.

A predicate written against one syntactic shape — the same mistake one level up from the rule it
enforces, and the reason the class guard is worth having even before a new hook exists. It now
scans forward from the end of the jq **program** (whose own `|` in `select(...) | tostring` is not
a pipe) and requires the first real pipe stage to be `head -1`.

## Alternatives considered

### A — Three more instance pins, one per hook

Rejected: that is the arrangement that already exists and that #193 exists because of.

### B — A narrow derivation keyed on `select(.type=="user")`

Rejected per §D2. It would exclude every future hook that scans a transcript some other way, and
exclusion would be silent.

### C — Enforce the rule with a hook rather than a test

Rejected as disproportionate. The rule is about source code in this repository, which CI already
reads on every push; a runtime hook would police the wrong moment.

### D — Also cover `plugin/skills/*/scripts/*.sh`

Not done, and measured rather than assumed: **no skill script references a transcript today**
(`grep -rl 'transcript_path\|\.jsonl' staging/plugin/skills/*/scripts/*.sh` returns nothing). The
derivation would find nothing and `T0`'s count guard would be satisfied by the hooks alone, so a
future skill script reading a transcript would slip through. Recorded as a known edge rather than
a guard whose coverage nobody has checked.

## Consequences

### Positive

- The rule is enforced over whatever the population is, not over the three files someone remembered.
- Nine files now state what they do with a transcript, in one line, where a reader will find it.
- The `pre-flight-pattern-enforce.sh` exemption is now on record *with its open issue attached*,
  rather than living in a neighbouring hook's header as a judgement about a third file.

### Negative

- **The derivation stops at `plugin/scripts/`** (§D-D). A transcript-reading skill script would not
  be covered, and `T0`'s count guard would not notice because the hook population alone satisfies it.
- `compliant()` recognises two syntactic shapes because those are the two that exist. A third —
  a `python3` reader, a `grep`-based one — would be reported non-compliant and would need either a
  predicate extension or an honest exemption. That is the correct failure direction and it is still
  a false positive waiting for whoever writes the third shape.
- An exemption is a sentence a human wrote. `T4` checks that it is long; nothing checks that it is
  true.
- `T5`, `Z4` and both `T3` assertions pass before and after — forward guards, not fix evidence.

### Neutral

- No hook behaviour changes. Nine files gain one comment block each;
  `pre-flight-pattern-enforce.sh` gains a longer one.
- No `PAIRS` change (every edited file already has an entry); one new test file, registered in both
  registries.

## Verification

Seen RED against a reverted tree: `write-scope-enforce.sh` restored to its pre-#127 full scan
**and** `test-write-scope.sh` changed to `tail -1`. `T1` and both `T2` assertions fail, naming both
files; the remaining nine pass. `Z1`/`Z2` do the same on synthetic files inside the test, so the
discrimination is in CI rather than only in this paragraph.

## References

- Issue #193, including the design notes on exemption placement and the count guard
- `docs/architecture/ADR-0074-127-self-arming-marker-class.md` — the instance and the sibling audit
- `docs/architecture/ADR-0067-interview-driver-model-invocation.md` §F6 — the derived-population
  instrument, and the issue that proved instance pins do not generalise
- `staging/plugin/scripts/tests/transcript-scan-rule.test.sh`
