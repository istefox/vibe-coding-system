# ADR-0081 — A validation loop that could not fail, and two deployment remaps of which one was written down

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issues #213 and #212
- **Extends:** ADR-0016 and ADR-0024 (the flat vendoring this documents), ADR-0043 (the direction
  lesson), ADR-0077 §D3 (declared waivers in the file)
- **Reported as:** two findings from the skill-layer audit. Phase 6.1 of `PROJECT.md`.

Two unrelated defects, fixed together because both are small, independent, and both consist of a
correct-looking artifact that reports success without having checked anything.

## Part 1 — #213: the RUNBOOK's agent validation could not fail

### Context

`docs/RUNBOOK.md` Step 6 ("Zone 2: agents") is the full-install procedure — the only path that
reaches every agent and rule file, as ADR-0043 established when PR #90's one-line `architect.md` fix
turned out to have reached `~/.claude` **exclusively** through this bulk copy.

Its re-validation loop was:

```sh
V="$HOME/.claude/plugins/cache/claude-plugins-official/plugin-dev/unknown/skills/agent-development/scripts/validate-agent.sh"
for f in ~/.claude/agents/*.md; do bash "$V" "$f" >/tmp/v 2>&1; grep -q "Validation failed" /tmp/v && echo "FAIL $f" || echo "OK $f"; done
```

### D1 — The path is wrong, and the path is the lesser half

The validator is not under `plugins/cache/…/unknown/…`. It is at
`plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/skills/agent-development/scripts/validate-agent.sh`
— a different layer of the plugin system. Verified missing, then located.

**The real defect is that a missing validator reported success.** `bash` on a non-existent script
writes to stderr and exits **127**. The loop's only signal was `grep -q "Validation failed"`, which
finds nothing in that output, so the `||` branch fired and printed `OK` — for every file, every time.

Reproduced before fixing, verbatim from git history: **eight `OK` lines, and the validator had never
existed.** `/tmp/v` contained `No such file or directory`.

### D2 — Branch on the exit code, not on grepped output

`validate-agent.sh` exits `1` on failure and `0` on pass (read from its source, then confirmed live).
The exit code is both the reliable signal and the one a missing script cannot fake — 127 is not 0.
The grep was a strictly worse way of reading the same fact, and its failure mode was silent in the
direction that matters.

### D3 — Resolve the validator, and hard-fail when it is absent

`find "$HOME/.claude/plugins" -name validate-agent.sh -type f | head -1`, then
`[ -n "$V" ] && [ -r "$V" ] || { echo "validation DID NOT RUN"; exit 1; }`.

**The guard is the part that generalises and the block says so**: keep it even if the path is ever
pinned again. A future plugin-layout reorganisation — and the `cache`/`marketplaces` split is
evidence that they happen — then costs a failed step instead of a false pass.

### D4 — The fixed block was executed, not just written

Extracted from `RUNBOOK.md` and run: it resolves the validator, validates all eight agent files, and
reports `all agent files validated`. **This is the first time this step has validated anything.**
Rule 11, applied to the fix rather than only to the finding.

### D5 — The historical plans are not edited

The same dead path appears in `docs/superpowers/plans/2026-05-17-agents-improvement.md` (nine times),
`2026-05-18-vibe-coding-system.md` (twice) and carries a `/Users/stefanoferri/` prefix besides. Those
are completed plans, and this repository does not edit historical records in place (the ADR-0034
precedent). Only the living document is corrected.

## Part 2 — #212: two zone anomalies in `PAIRS`, one undeclared

### Context

`concept-to-code/SKILL.md` invokes `~/.claude/skills/concept-to-code/scripts/hook-verify-workflow.sh`.
That path exists when deployed. In staging the file is **flat**, at
`staging/plugin/scripts/hook-verify-workflow.sh`, and `PAIRS` remaps it on deploy. ADR-0016 vendored
it flat, ADR-0024 kept it flat rather than create a second source of truth.

Nothing said so at either location, and the audit of 2026-07-29 reported it as a **missing file**,
after which the conclusion had to be reconstructed from an ADR.

### D6 — There are two anomalies, not one, and the issue was right to insist

The first sweep for this compared src and dst tails and returned forty hits — because
`plugin/scripts/X → hooks/X` is the *normal* zone mapping, applied uniformly. The correct question is
which entry lands in a **different subtree from its peers**. Two do:

| entry | dest | status before this ADR |
| --- | --- | --- |
| `plugin/scripts/hook-verify-workflow.sh` | `skills/concept-to-code/scripts/` | **undeclared** |
| `plugin/scripts/usage-report.py` | `scripts/` | already documented at `sync-to-claude.sh:19` |

Issue #212 said "do not assume this is the only one — it is the only one *this sweep* surfaced, which is a
different claim." That was correct, and a crude first query would have missed the second.

### D7 — Declared in `sync-to-claude.sh`, derived and checked in the test

The declaration is a machine-readable `# pairs-zone-anomaly:` line plus a prose reason per entry, in
the file that performs the mapping. `pairs-completeness.test.sh` derives the anomaly set from `PAIRS`
and requires each member to appear in that line.

Direction, per rule 5: **a third anomaly fails at the moment it is introduced**, rather than being
rediscovered by an audit that then has to adjudicate whether it was deliberate. `ZA4` runs the check
backwards — a declaration for an anomaly that no longer exists is a stale waiver that would keep
`ZA3` green while describing an arrangement that had been normalised away. `ZA2` count-guards the
`PAIRS` parse itself, because a parse returning almost nothing makes an empty anomaly set look like
compliance. `ZA5` pins the flat source, which is the half that breaks if someone "fixes" the
reference.

Both `ZA3` and `ZA4` were verified failing: a planted third anomaly and a planted stale declaration
each produce the right message naming the right entry.

### D8 — Found on the way: this test file could not fail an added assertion

`pairs-completeness.test.sh` has no `ok()`/`bad()` helpers — its counters are touched only by its
`check_*` functions. The first draft of the `ZA` section called `ok`/`bad` anyway. The result:

```
line 188: ok: command not found     (×6)
PASS=244 FAIL=0
```

**Six assertions did not execute and the suite reported green and exited 0.** Nothing there runs
under `set -e`, so a call to an undefined helper is indistinguishable from a passing assertion.

`ok()`/`bad()` are now defined, with that history in a comment above them, because the next person to
add an assertion to this file would hit the same thing and might not notice. It is the same family as
this ADR's Part 1 — a check that cannot fail reports success — discovered inside the test written to
fix it.

## Consequences

### Positive

- The full-install procedure validates the agent files. It did not before, on any machine.
- A missing validator now stops the step instead of certifying it.
- Both deployment remaps are declared, derived and checked; a third fails loudly.
- Adding an assertion to `pairs-completeness.test.sh` can no longer silently do nothing.

### Negative

- **`find` picks the first match.** If two plugin installs each ship a `validate-agent.sh`, the block
  uses whichever `find` returns first and prints which one — visible, not chosen.
- The `# pairs-zone-anomaly:` declaration is a hand-maintained line. `ZA3`/`ZA4` keep it honest in
  both directions, but a *wrong reason* attached to a correctly-listed entry is not detectable.
- The stale path survives in three historical plan documents (§D5). Anyone copying a command out of a
  completed plan gets the dead path, and no guard covers that.
- `ZA1`, `ZA2` and `ZA5` pass before and after — forward guards. `ZA3`, `ZA4` and #213's whole block
  are the fix evidence.

### Neutral

- No behaviour change in any deployed script: #213 touches a repo document, #212 adds comments and a
  test section. `hook-verify-workflow.sh` gains a header block and nothing else.
- No new file, no `PAIRS` change, no registry change.

## References

- Issues #213 and #212, including the latter's warning against assuming a single anomaly
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md` — the flat-vendoring
  decision this documents rather than revisits
- `docs/architecture/ADR-0043-93-pairs-completeness.md` — the direction lesson, and why Step 6 of the
  RUNBOOK matters at all
- `staging/plugin/scripts/tests/pairs-completeness.test.sh` section `ZA`
