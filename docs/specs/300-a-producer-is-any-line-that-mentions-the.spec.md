# SPEC — a producer is any line that mentions the target so a target only talked about looks produced

Source: GitHub issue #300

## Objectives

1. Run the current derivation and classify every match: which are real calls to
   `manifest-transition.sh` and which are prose.
2. Report a target mentioned only in prose as producerless.
3. Keep the section-3 exclusion failing closed, with the "did not resolve" cause named in the
   failure message, and keep the arrow-form producer recognised.

## Scope

In: `has_producer()` in `transition-producer.test.sh` — the predicate that accepts a line naming a
transition target in a transition context, and the classification of every match it currently
returns across the staged `SKILL.md` population.

Out: the state machine itself and its legal pairs (`manifest-transition.sh`). The exemption syntax
(`# transition-producer-exempt:`) and its stale-waiver reverse check. The guard's stated boundary,
which ADR-0095 records: it catches a target with no producer anywhere (the #238 shape) and misses a
target whose only producers sit behind a default-off flag (the #248 shape).

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/scripts/tests/transition-producer.test.sh` — the whole change. It builds the
  target population from `manifest-transition.sh`'s legal pairs and the producer population from
  every staged `SKILL.md` minus `concept-to-code`'s section 3, then applies `has_producer()`, which
  today accepts an explicit `manifest-transition.sh` call, the word "transition", or an arrow
  pointing at the state. `TP0c` names the section-3 range resolution as the failure cause; `TP0d`
  count-guards the producer population; `TP1` and `TP2` are the two directions; `TP6`/`TP7` pin
  #248 instance-level. It is an instance of the derived-guard pattern (ADR-0086) and stays a copy.
- `staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh` — the legal-pairs table
  the target population derives from, and the file carrying the exemption declarations.
- `staging/plugin/skills/concept-to-code/SKILL.md` — the largest producer population member, and
  the source of both special cases: section 3 is the state-machine summary that names every pair
  and performs none (hence the exclusion), and Gate 0d's routing block puts the transition verb on
  the line *preceding* the arrow list (hence the arrow form).
- `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/skills/project-conductor/SKILL.md`
  and the other staged `SKILL.md` files — the rest of the producer population.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0095-248-transition-producer.md` — the source, whose quoted line number
  will have moved.

## Data model

- Target: a `current_step` value appearing as the destination of a legal pair.
- Producer: today, a line naming the target in a transition context. The classification R-01 asks
  for splits these into real calls to `manifest-transition.sh` and prose, which is the distinction
  the tightened predicate must encode.
- Exemption: `# transition-producer-exempt: <target> — <reason, >= 40 chars, ONE line>`, declared in
  `manifest-transition.sh`.

## API / Interfaces

`has_producer <target>` — an internal harness function returning 0 or 1. The section-3 exclusion is
a heading-anchored line range; `TP0c` is its resolution check. The producer population is a glob
over staged `SKILL.md` files, count-guarded by `TP0d`.

## UI flows

None.

## Edge cases

- A target named only in prose — R-01's case, and the one that would pass #248 itself if the prose
  had been worded differently.
- Gate 0d's arrow form, where the verb is on the preceding line. ADR-0095 records that an
  arrow-blind predicate reported `step_e1_plan` as producerless, so this is a known false-positive
  the predicate must keep avoiding; R-03 makes losing it a regression.
- Section 3 naming every pair: including it makes every target trivially covered, so the exclusion
  must fail closed — if the range does not resolve, `concept-to-code` contributes nothing, 26
  targets report producerless, and `TP0c` names the cause. Dropping the guard and including the file
  whole fails open.
- A producer inside a skill-private `scripts/` helper rather than a `SKILL.md`, which is outside the
  population by construction (ADR-0095 discloses this).
- A producer behind a default-off flag — the #248 shape, which this guard misses by design and which
  stays pinned instance-level.
- A stale exemption covering a target that now has a producer — `TP2`'s reverse direction, which
  must survive any narrowing.
- Per the standing rules in the issue footer, a needle that is the target's own name counts the
  prose explaining it, which is the defect class this issue is about, one level up.

## Success criteria

- [ ] R-01 — a target mentioned only in prose is reported producerless.
- [ ] R-02 — the §3 exclusion still fails closed, with the "did not resolve" cause named in the
      failure message.
- [ ] R-03 — the arrow-form producer that ADR-0095 had to add (Gate 0d puts the verb on the
      preceding line) is still recognised; a narrowing that loses it is a regression.
