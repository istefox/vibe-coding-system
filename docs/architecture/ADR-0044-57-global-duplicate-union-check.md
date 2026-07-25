# ADR-0044 — Verify `--global` DUPLICATE removals against the global file, don't widen the union

**Status:** Accepted
**Date:** 2026-07-25
**Issue:** #57
**Extends:** ADR-0019 D6 (the content-preservation invariant), ADR-0032 (whole-line matching)

---

## Context

`claude-md-slim --global` flags a section `DUPLICATE` when ≥60% of its lines already appear in
`~/.claude/CLAUDE.md`, deletes it from the trimmed CLAUDE.md, and leaves
`<!-- duplicate of ~/.claude/CLAUDE.md — removed -->` behind. Step 5.2 then runs
`content-union-check.sh` — the sole ADR-0019 hard gate — over the original and the *local* outputs.
The global file was never an input, so those lines had nowhere to be found.

**The issue's premise was stale, and the real behaviour was worse than it described.** #57 was
written while implementing #36 and says such a run "passes the content-preservation gate only by
accident (the removed lines happening to also appear as a substring of some unrelated line)". That
was true of the substring matching ADR-0032 then removed. Reproduced against the current script with
a minimal fixture — one `## Git` section removed as DUPLICATE, everything else preserved:

```
3 lines from original not found in any output file
EXIT=1
```

It did not pass by accident. **It aborted, every time.** `--global` was unusable the moment it found
a duplicate, which is the only thing it does. #36 did not cause that; it uncovered it by removing
the accidental matches that were hiding it. Test G1 pins the pre-fix behaviour so the direction of
this change stays legible to whoever reads it next.

## Decision

Two optional flags on `content-union-check.sh`, both together or neither:

```
content-union-check.sh [--duplicate-lines <file> --duplicate-source <path>] <original> <out1> [...]
```

A line is preserved if it is in the local union **or** if it is *both* listed in
`--duplicate-lines` *and* present whole-line in `--duplicate-source`. Lines resolved that way are
counted and reported separately on stderr, so an operator sees how much content left the local files
rather than having it silently absorbed.

Both conditions, in that order, and both flags required together: a declaration by the pipeline that
it removed a line is a claim, not evidence. One flag alone is a usage error naming the missing one —
an exemption that is declared and never verified is worse than no exemption.

SKILL.md Step 3/4 now collects the removed lines into a temp file, and Step 5.2 passes the flags only
when `--global` produced at least one DUPLICATE. Callers that do not opt in keep today's behaviour
byte for byte.

### Alternatives considered

**Pass `~/.claude/CLAUDE.md` as an extra union input (issue #57's Option 1).** Rejected on gate
strength, not on effort — it is the smaller change. Appending the global file to the union makes
*every* original line satisfiable by it, so a line genuinely lost through a botched extraction would
count as preserved merely because something identical happens to sit in the global CLAUDE.md. That
converts a false abort into a false pass on the project's own hard gate, which is the one place this
codebase should not accept a permissive failure direction. Test G4 exists specifically to fail under
Option 1: a lost line, absent from the duplicate set, present in the global file, must still abort.
Without that assertion the choice between the options would be a stated preference rather than an
enforced one.

**Exempt DUPLICATE lines from the check entirely.** Rejected: it is the same waiver with fewer steps,
and it trusts the 60% heuristic to be right about content it is deleting.

## Consequences

### Positive

- `--global` mode works. It has been unusable-on-success since #36 landed.
- The exemption is a verification: a line the pipeline *claims* it removed as a duplicate, but which
  is not actually in the global file, still fails (G3).
- Removed content is reported, not silently absorbed — the stderr line names how many lines left the
  local outputs and where they were found.

### Negative / residual

- **The 60% heuristic is untouched.** A section only *mostly* present in the global file is still
  flagged DUPLICATE and removed whole; its minority lines are not in the global file, so they now
  fail the gate loudly instead of vanishing quietly. That is the right direction, and it is not the
  same as solving it — the operator sees an abort whose cause is a threshold, not a bug. Tuning or
  splitting that heuristic is its own change.
- **The skill's own `tests/run-tests.sh` points at `$HOME/.claude/skills/…`,** so it exercises the
  *deployed* copy, not `staging/`. Its 19/19 green during this work validated the old script and says
  nothing about this change. It must be re-run after `sync-to-claude.sh --apply` for its result to
  mean anything here. ADR-0032 already recorded this file as `$HOME`-coupled and CI-dark; this is the
  first time that has actively misled a verification step, so it is worth its own line.
- The duplicate-lines file is produced by the same step that decides what to delete. If Step 3/4 is
  ever changed to remove content without appending it there, the gate goes back to aborting — loudly,
  which is the correct failure direction, but the coupling is real and lives in SKILL.md prose.

## References

- ADR-0019 D6 — the content-preservation invariant this gate implements
- ADR-0032 — whole-line matching; its D2 multiplicity exemption, which used to list `--global`
  duplicate-removal as an example and never accurately covered it
- `staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh` — section G, 8
  assertions (19 total)
