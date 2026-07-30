# SPEC — Deployed-only skills: vendor what belongs, declare what does not

**Topic slug:** 222-vendor-deployed-only-skills

Source: GitHub issue #222, filed during the phase 6.4 measurement and sharpened by the Phase 7
shakedown run's own investigation.

## Objectives

Six skills exist in `~/.claude/skills/` and not in `staging/`. The issue framed this as a
vendoring gap. Measuring the six showed it is two separate questions that ADR-0024 could answer
together and this cannot:

- **Deployment** — must a fresh machine restoring from this repository receive this file?
- **Verification** — must the harness be able to read this file?

For `ui-layout-audit` both answers are yes: `concept-to-code` §25 declares it chain-invokable at
gate 5.05, Gate 5.05 invokes it by name, and `accessibility-i18n.test.sh` refers to it. It is
system infrastructure that happens to live on one machine.

For the other four both answers are no. `daily-open` and `daily-close` are a personal daily
routine bound to local connectors (Obsidian, NotePlan, DEVONthink, ms365). `vibiso-intake` is the
front end of a different project's intake contract (`vibiso-system` ADR-002). `agent-design`
carries `license: Proprietary internal knowledge base. Source attribution required.` over a
`reference/` tree distilled from a published book. A machine restoring from this blueprint should
receive none of them.

So the defect is not "four skills are unvendored". It is that **nothing distinguishes "not part of
the blueprint" from "forgotten"** — the same gap that has left `website-auditor`'s exclusion in
prose since ADR-0024 — and that `skill-text-corrections` F6 silently skips a chain-invokable skill
it cannot find.

## Scope

**In scope**

1. Vendor `ui-layout-audit` into `staging/`, with its `PAIRS` entry and the cross-file gate
   assertion its two sibling chain-invokable skills already have.
2. A declared registry of deployed-only skills, with a reason per entry, covering the four
   excluded here plus `website-auditor`.
3. Make F6's silent skip loud, distinguishing a token that is legitimately not a skill from a
   skill that is missing from staging.

**Out of scope, stated so it is not assumed**

- Vendoring `agent-design`, `daily-open`, `daily-close`, `vibiso-intake`. Each is declared, not
  copied.
- Any licence or provenance enforcement. ADR-0065 (#119) deliberately shipped **no detector** —
  only an opt-in CI job for generated projects and a human procedure in `clean-public-repo`.
  `agent-design`'s licence is recorded as a reason; nothing in this repository checks it.
- Directory-level sync. ADR-0024 requires its own ADR for that and the reason still holds.
- Deciding what happens to a deployed skill that later disappears from the machine.

## Stack

Bash 3.2 (macOS `/bin/bash`), markdown, GitHub Actions. No new dependency. Existing mechanisms
reused rather than invented: `sync-to-claude.sh`'s `PAIRS` list and its `# pairs-zone-anomaly:`
declaration convention (ADR-0081), `pairs-completeness.test.sh`'s `check_complete`, and
`skill-coverage-perimeter.test.sh`'s `C5`/`C6` gate-contract assertions (ADR-0084).

## Architecture

### The registry lives where the norm is defined

`# deployed-only: <name> — <reason>` declarations in `staging/sync-to-claude.sh`, beside the
existing `# pairs-zone-anomaly:` lines. That file is what decides which files reach `~/.claude`, so
a declaration that a file deliberately does not is a statement about the same subject, in the same
place. ADR-0081's precedent is exact: the deviation is declared where the norm is defined and
derived by a test at run time.

ADR-0077's rule — a waiver travels with the file it excuses — cannot apply here. The excused file
is absent from `staging/` by construction, so there is nothing for the waiver to travel with. This
is the one shape that rule does not cover, and the registry is the answer to it.

### Two verification directions, two homes, and the split is the point

The registry can be checked from both ends, and only one end is machine-independent:

| direction | what it catches | where it runs | why |
|---|---|---|---|
| every entry names a skill **absent** from `staging/` | a stale waiver — someone vendored the skill and left the declaration | CI, `pairs-completeness.test.sh` | reads only `staging/`, so it is reproducible on any machine |
| every **deployed** skill is vendored or declared | a new skill nobody recorded | `sync-to-claude.sh`, at deploy time | needs `$HOME/.claude`, which ADR-0084 refused to make CI depend on |

The second direction is a report, not a block: `sync-to-claude.sh` is a deploy tool and its output
is already read by a human, who is exactly the person who can answer "what is this skill".

### F6 resolves against skills **and** agents

`skill-text-corrections.test.sh` F6 derives chain-invokable skill names from `concept-to-code` §25
and skips any that does not resolve to a staged `SKILL.md`. Measured, that line yields nine
backticked tokens: seven staged skills, `reviewer` (an **agent**, not a skill), and
`ui-layout-audit` (the gap). One `continue` does two jobs and cannot tell them apart.

A token that resolves as neither a staged skill nor a staged agent is a failure. `reviewer` passes
because `plugin/agents/reviewer.md` exists; `ui-layout-audit` fails until it is vendored. The
derivation stays inside `staging/`, so the check remains CI-runnable, and no list of names enters
the test — the identity waiver ADR-0069 §PTD refused.

## Data model

Not applicable — no persisted state. The registry is comment lines parsed at run time; nothing is
serialised.

## API

Not applicable — no interface is exposed. The three artifacts are a vendored markdown file, comment
declarations in a shell script, and test assertions.

## UI flows

Not applicable. The only human-facing surface is `sync-to-claude.sh`'s existing deploy report,
which gains one line per undeclared deployed skill.

## Edge cases

- **A declared skill is later vendored.** The declaration becomes a stale waiver reading as a
  deliberate exclusion. Caught in CI by the absent-from-staging direction.
- **A `§25` token that is neither skill nor agent.** F6 fails, correctly: either the token should
  not be backticked on that line, or the thing it names should exist in `staging/`. Today the set
  is exactly skills plus agents; a future gate label in backticks would trip it, and that is the
  intended failure rather than a false positive to suppress.
- **`website-auditor` is a symlink into another repository.** It must be declared and must not be
  vendored. Its reason records the symlink, so the structural exclusion of ADR-0024 §2.1 stops
  being reachable only through prose.
- **A skill deployed tomorrow and never declared.** Invisible to CI by design; reported by
  `sync-to-claude.sh` at the next deploy. Anyone reading a green CI run as "the deployed set is
  fully accounted for" is reading something this feature does not claim.
- **`ui-layout-audit` lands and the perimeter check fails.** ADR-0084's `S1` requires every staged
  skill to be covered by name or declared. It is covered by the new gate-contract assertion, not by
  a waiver — consistent with `design-brainstorm` and `macos-ux`, the other two chain-invokable
  skills, which already carry exactly that assertion.
- **`agent-design`'s licence.** Recorded as a reason, enforced by nothing. This is disclosed, not
  solved: there is no mechanism here that would notice book-derived content entering the tree.
- **The registry's own reason quality.** A minimum length is checkable; truth is not. A reason is
  a sentence a human wrote.

## Success criteria

- [ ] R-01 — `staging/plugin/skills/ui-layout-audit/SKILL.md` exists and is byte-identical to
  `~/.claude/skills/ui-layout-audit/SKILL.md` at the moment of vendoring.
- [ ] R-02 — `sync-to-claude.sh` carries one `PAIRS` entry for it, and
  `pairs-completeness.test.sh`'s `check_complete "plugin/skills" '*/SKILL.md'` passes with the new
  file present.
- [ ] R-03 — `skill-coverage-perimeter.test.sh` gains a `C7` assertion of the same shape as
  `C5`/`C6`: `concept-to-code` §25 restricts `ui-layout-audit` to gate 5.05, and the skill's own
  text names that gate. It fails when either side stops saying so, and the failure names which one
  moved.
- [ ] R-04 — `staging/sync-to-claude.sh` carries a `# deployed-only: <name> — <reason>` declaration
  for each of `agent-design`, `daily-close`, `daily-open`, `vibiso-intake` and `website-auditor`,
  and for no skill that is present in `staging/`.
- [ ] R-05 — a CI-runnable assertion derives those declarations at run time and fails when a
  declared name is present in `staging/` (a stale waiver), when a reason is shorter than 40
  characters, or when the derivation yields fewer than five entries.
- [ ] R-06 — `sync-to-claude.sh` reports, once per run, every directory under `$HOME/.claude/skills/`
  that is neither vendored in `staging/plugin/skills/` nor declared. It reports; it never blocks
  the sync.
- [ ] R-07 — `skill-text-corrections.test.sh` F6 resolves each backticked `§25` token against
  staged skills **and** staged agents, and fails when a token resolves as neither. `reviewer`
  passes; a token naming nothing fails.
- [ ] R-08 — F6 keeps a count guard over its derivation, so a `§25` line that stops yielding tokens
  fails loudly instead of passing with an empty set.
- [ ] R-09 — every assertion added by R-03, R-05, R-07 and R-08 is seen failing against a planted
  defect before it is accepted, and the planted case is recorded.
- [ ] R-10 — the full harness passes, `staging/sync-to-claude.sh --apply` is run, and the
  subsequent dry run reports zero drift.
