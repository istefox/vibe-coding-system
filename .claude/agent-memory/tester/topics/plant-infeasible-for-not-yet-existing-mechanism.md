---
name: plant-infeasible-for-not-yet-existing-mechanism
description: why a Batch-A (tester-first) RED assertion targeting a coder task's not-yet-written code cannot get a real `# plant:`, and the two concrete constructions that DO work
metadata:
  type: feedback
---

Writing tests before the coder task that implements them (ADR-0049/plan "Batch A: tester-first,
red"), a plan may instruct "declare a plant for assertion X" where X's mechanism is code the coder
task hasn't written yet (only a plan/ADR paragraph describing it exists). Two genuinely different
situations look identical at first read and need different handling:

1. **The assertion checks REAL, already-existing data** (e.g. a reverse/cross-check against a
   PAIRS block, an existing registry, files already on disk) — a plant IS constructible: mutate the
   EXISTING file via a stable, already-present anchor line, using the `\n`-escaped insertion form
   (`<existing line>\n<new line>`) to inject a synthetic instance of the not-yet-existing
   declaration's *shape* (same idiom `DO4`/`self-test 2` already use, just applied through a real
   plant instead of a synthetic fixture). Verified working: reintroducing a PAIRS `src|dst` line via
   an untouched neighboring PAIRS entry as the needle; injecting a synthetic
   `# deployed-only: <name> — ...` line via the last untouched registry entry as the needle.

2. **The assertion is a bare count/floor guard on a population that does not exist yet** (e.g.
   `>= 1 <marker>: line found`) — genuinely NOT plantable with a single exactly-once literal needle,
   because (a) the population is small and fixed (often exactly 2), so removing one entry never
   crosses the floor, and (b) removing ALL entries in one substitution requires literally quoting
   each entry's free-text reason, which the future coder task hasn't authored yet — the regex
   engine only joins needle WORDS on `\s+`, it does not skip over unknown intervening text. **This
   is not a gap in effort**; it is the same reason the file's OWN pre-existing floor assertions
   (`DO1`, `ZA1`, `ZA2`, `CI0`, `CI0b` in `pairs-completeness.test.sh`) carry zero plants of their
   own — floors are rule-10 vacuity guards, stated as such at the site, never individually planted.
   Verified live: `pairs-completeness.test.sh`'s `XR1` (2026-09-08, ADR-0197 migration).

**Also unplantable for a related but distinct reason**: an assertion checking real behavior that
literally does not exist as CODE yet (e.g. a whole new report block a future task adds) has no
needle to mutate at all — not a floor problem, just nothing there. The file's own precedent
(`sync-manual-steps.test.sh` sections G/H/I, each "RED until Task N lands") likewise carries zero
plants for these; a plant belongs there only once the future task's code exists to target.

**How to apply:** when a plan instructs "declare a plant for" an assertion in this situation,
check the file's OWN existing convention for the same shape (RED-until-future-task assertions,
bare floors) before inventing a plant. If the established convention is "no plant, comment
instead," follow it and say so explicitly at the assertion site (which id, which future task
supplies the mechanism) — do not fabricate a plant whose needle targets an unrelated comment line
just to satisfy the letter of the instruction; that plant would be provably a no-op (mutates text
that isn't the mechanism) and worse than an honest exemption comment. Report the deviation from the
plan's literal wording, with the reasoning, in the tester's final report.

See also [[task1-codex-audit-mode-slug]] for the sibling ADR-0154 back-reference gotcha in the
same file family.
