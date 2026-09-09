---
name: harness-blast-radius
description: Deleting a vendored file breaks more harnesses than a SPEC lists; the shapes that get missed are frozen exact baselines, negative-shaped assertions and population count guards
metadata:
  type: project
---

# Blast radius of deleting a file the harness corpus reads

A SPEC's list of affected harnesses is systematically incomplete here, and the misses are not
random — they cluster in three shapes a name-grep does not surface.

**Why:** measured 2026-09-07 on the `deep-refactor` de-vendoring (ADR-0196). The SPEC named three
harnesses; the real set was six, and the two extras were the two that would have turned CI red
after the "complete" change landed. My own `plant-check-mechanics` note already warned that "a
name-grep alone under-reports blast radius when an assertion fails from a *count* rather than from
naming the thing" — this is the worked example.

**How to apply:** before planning any deletion of a file under `staging/`, run all four probes, not
just the first.

1. **Name grep** — `grep -rn "<path>" staging/plugin/scripts/tests/`. Finds the obvious consumers.
2. **Frozen exact baselines (ADR-0124).** Grep for the *content* the file contributes, not its
   path. `dispatch-completion.test.sh`'s `DC21` holds a literal `EXPECTED=` block listing every
   `dispatch-site:` marker found by a `find "$SKILLS"` sweep; deleting a `SKILL.md` silently drops
   two entries and the exact-match assertion fails. Nothing in the file mentions the deleted path.
3. **Negative-shaped assertions.** `if grep -q <needle> "$F"; then bad; else ok` passes *vacuously*
   when `$F` is gone — a rule-4 failure that reads green. `workflow-dispatch-pins.test.sh`'s `A1` is
   the example: `A2`/`A3` go red and get noticed, `A1` survives as a lie. A negative assertion must
   be deleted together with its positive siblings, never left behind.
4. **Population count guards.** Harnesses globbing `skills/*/SKILL.md` carry `>= N` floors
   (`skill-coverage-perimeter` S0, `skill-fence-positional-tokens` SFP1, `worktree-isolation-contract`).
   Check the headroom explicitly; 32 → 31 against `>= 25` is fine, but the check is one command and
   the alternative is discovering it in CI.

Also: a `# plant:` declaration whose target file is deleted becomes `BADPLANT`, not a pass — the
declarations must be removed with their assertions. And a harness whose `S0`-style preflight guard
hard-exits 1 on a missing file takes *every* assertion in that file down with it, so one deletion
can silence 44 assertions while reporting a single failure.

Related: [[plant-check-mechanics]], [[spec-coverage-and-plan-tools]].
