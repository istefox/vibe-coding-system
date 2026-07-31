# ADR-0091 — A per-file budget line was half-parsed into a false SCOPE and a false BUDGET

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #246 (found by the Phase 7.1 shakedown run, at the Step 5 batch-1 checkpoint)
- **Related:** ADR-0052 (#106, the feature this corrects), ADR-0070 (#184, which woke the check up),
  ADR-0072 (the near-miss rule this is the fourth instance of), ADR-0035/#235 (membership by
  property), ADR-0064 §D3 (absent is not zero)

## Context

ADR-0070 woke `diff-budget-check.sh` up: it had produced no finding on any real plan since ADR-0052
shipped it in July. **The first real plan it ran on produced two findings, and both were false.**

The documented syntax is one ceiling for a file list:

```text
Budget: <file>[, <file>...] (<~|±><N> line[s])
```

The architect writes **per-file** ceilings:

```text
Budget: staging/plugin/skills/ui-layout-audit/SKILL.md (~165 lines, new), staging/sync-to-claude.sh (~1 line)
```

The parser matched one paren group anchored at end of line, so it kept only the **last** ceiling and
left everything before it in the file list. Three corruptions at once, reproduced on the real plan
before any code was written:

1. **A false `SCOPE`** on a file the plan declares explicitly, because the first file drops out of
   the declared set.
2. **No `BUDGET` line at all**, and when one does fire the ceiling is `1` instead of `166` — two
   orders of magnitude, so the overshoot that follows is fabricated.
3. **The file count inflates**, because the fragments `(~165 lines` and `new)` are counted as
   filenames beside the real one.

### The corpus, measured rather than assumed

16 `Budget:` lines across 3 plans: **12 single-ceiling** (parse correctly), **3 per-file** (all
mis-parsed, all three ways, all in the same plan), and one line that is not a declaration at all.

That last one matters more than its count suggests — see §D2.

### Why the harness could not see it

`BJ5`'s corpus sweep excludes budget-declaring plans by property (correctly — they legitimately
report). `BJ1`/`BJ2` read the **first** such plan. The second, written by the chain itself and doing
exactly what ADR-0052 asks, was asserted by nothing. Same shape as #235: the corpus grew a form the
harness had no eyes on.

## Decision

### D1 — One grammar, a left-to-right walk, which subsumes the documented form

Rather than branching on "documented versus per-file", the parser walks paren groups left to right:
each group's preceding text is the file (or comma list) that group's ceiling covers. Ceilings are
**summed** per task, because the downstream check compares per-task totals.

The documented form is this walk with one group, so there is no second code path to keep in
agreement — the failure mode ADR-0069 removed from the plan-task predicate, not reintroduced here.
Mixed forms work as a consequence rather than as a special case: `a.md, b.md (~50 lines), c.md
(~10 lines)` is three files and 60 lines.

Anything left after the last group that is not a separator or markdown emphasis means the line did
**not** fully parse. Without that, `Budget: a.md (~50 lines), b.md` would silently drop `b.md` —
the half-read this ADR exists to stop.

### D2 — `MALFORMED` fires only on a recognisable ATTEMPT, and the discriminator is measured

A new token, `MALFORMED<TAB>task <N><TAB><declaration text>`, reports a declaration the checker
could not read. ADR-0072's rule: **a form close enough to be partially read is worse than one
rejected outright.**

It fires only when at least one paren group carries **both** a digit and the word "line". That
discriminator is measured, not chosen for tidiness. `Budget:` is matched as a case-insensitive
**substring**, so the corpus contains:

- `# Performance budget: <10s typical, 8s per-harness timeout.` — a comment inside a fenced code
  block in a plan, never a declaration;
- `Budget: none (verification only, no source files touched beyond what Tasks 1-6 already changed)`
  — a deliberate prose escape for a task that touches no files. It carries digits and no "line".

**A token firing on either would be this issue's own defect one level up:** a detector reporting on
text that was never a declaration. Both are pinned as fixtures.

### D3 — `MALFORMED` is emitted before the whole-plan inert check, and it has a consumer

A plan whose **only** budget lines are malformed produces an empty budget set, so the inert check
would return `CLEAN` — the common, documented, legitimate case, and indistinguishable from it. That
is precisely the invisibility ADR-0070 spent months inside. The token is emitted on that path too.

And the Step 5 call site was extended to read it: the operator is told the task's budget was **not
measured**, and the finding is recorded as `{task, malformed}` in `budget_findings` — no `files_*`
or `lines_*` keys, because writing zeros there would read as a task that spent nothing (ADR-0064
§D3's rule). **A reporter line no caller reads is a producer with no consumer**, which is the defect
class #238 records; inventing a new instance while the roadmap is closing that class would have been
a poor trade.

## Verification

53 assertions in `diff-budget-scope.test.sh`, 14 new (`BK0`–`BK10`, plus `BK9a/b/c`) and a `Z1`
floor.

**`BK9` is the backward-compatibility gate and it embeds the pre-#246 parser as the specification of
what must not change.** Every declaration in the corpus is parsed by both and compared:

- `BK9a` — 16 declarations to compare (count guard: a broken derivation must not read as a clean
  corpus);
- `BK9b` — **exactly 3 of 16 parse differently**, and they are the per-file ones. A large number
  would mean the rewrite moved the single-ceiling population too;
- `BK9c` — **nothing the old parser could read has become unreadable.** The widening never narrowed.

Seen RED against the restored pre-#246 call site: `BK1`, `BK2`, `BK3`, `BK4`, `BK5`, `BK8`.
`BK6`/`BK7` are forward guards (no `MALFORMED` token existed to misfire).

**`BK9`'s boundary is stated rather than left implicit:** it extracts and compares the
`parse_budget` **function**, so it is blind to a script that defines it correctly and never calls
it. Verified, not assumed — restoring the pre-#246 call site while leaving the function in place
leaves `BK9a/b/c` green, and `BK1`/`BK2`/`BK3` are what fail there. The two must be read as a pair.

### Three drafts of one assertion, all wrong, all worth recording

`BK10` asserts the `MALFORMED` consumer exists at the call site.

1. A bare `grep -qF 'MALFORMED'` — the token is named twice, so deleting one site left the other
   satisfying it and the plant walked straight through. `recovery-preflight.test.sh` `RI1`'s defect,
   reproduced by the same hand three days later.
2. An exact count of 2 — which **failed on the correct file**, because `spec-coverage.sh`, a
   different checker twenty lines up in the same step, emits a `MALFORMED` token of its own.
   Counting a bare word across a whole step conflates two checkers that happen to share it.
3. Four distinctive needles, of which `not measured` still did not fire: that phrase appears twice
   more in Step 5 for the absent-field rule. Scoped to its own sentence.

The general form: **a needle must belong to the block it is asserting about and to nothing else**,
and the only way to know it does is to plant it.

## Consequences

- **A dormant-then-noisy feature becomes accurate.** ADR-0070 warned the first Step 5 after it might
  look like a regression; this removes the false findings that would have been most of that noise.
- **Per-file granularity is parsed and then summed.** The check compares totals, so a single file
  can exceed its own declared ceiling while the task total stays under. Known, and not what this
  check measures.
- **`MALFORMED` is new output on a reporter three skills consume by reference.** It is advisory and
  cannot block, but a caller filtering strictly on `^BUDGET`/`^SCOPE` will drop it silently — which
  is why the c2c call site was changed in the same PR rather than left for later.
- The walk accepts a group whose preceding text is a comma list, so a genuinely ambiguous line like
  `a.md, b.md (~50 lines), c.md (~10 lines)` resolves as 50-for-two-files plus 10-for-one. That is
  the only reading consistent with the documented form, and it is stated rather than discovered.
