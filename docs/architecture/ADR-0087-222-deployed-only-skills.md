# ADR-0087 — Deployed-only skills: vendor what belongs, declare what does not

- **Status:** Accepted
- **Date:** 2026-07-30
- **Issues:** #222 (Phase 7.2, and the shakedown feature for Phase 7.1)
- **Related:** ADR-0024 (vendor scope, `website-auditor`'s exclusion first recorded in prose),
  ADR-0043 (a check that validates a list's entries cannot see what it omits),
  ADR-0077 (a waiver travels with the file it excuses),
  ADR-0081 (`# pairs-zone-anomaly:` — the declaration convention this reuses),
  ADR-0084 (`skill-coverage-perimeter.test.sh` C5/C6 — the gate-contract shape C7 copies),
  ADR-0086 (the derived-guard family this joins as instance 7, and stays a copy on purpose)

## Context

Six skills exist in `~/.claude/skills/` and not in `staging/`: `agent-design`, `daily-close`,
`daily-open`, `ui-layout-audit`, `vibiso-intake`, and `website-auditor`. Issue #222 framed this as
one vendoring gap. Measuring the six splits it into two questions ADR-0024 could answer together
and this cannot:

- **Deployment** — must a fresh machine restoring from this repository receive the file?
- **Verification** — must the harness be able to read it?

`ui-layout-audit` answers yes to both: `concept-to-code` §25 declares it chain-invokable at gate
5.05, Gate 5.05 invokes it by name, `accessibility-i18n.test.sh` refers to it, and its own text
(verified live) names neither `concept-to-code` nor any gate at all — the file the chain depends on
has never said so itself. The other four (`website-auditor` already excluded by ADR-0024, the
remaining three newly surfaced here) answer no to both: a proprietary knowledge base, two personal
routines bound to local connectors, and a different project's intake front end. None belongs on a
machine restoring from this blueprint.

The defect is not "four skills are unvendored" — that is correct. It is that **nothing distinguishes
"not part of the blueprint" from "forgotten"**, the same gap `website-auditor` has sat in since
ADR-0024 recorded its exclusion only as prose, and that `skill-text-corrections.test.sh` F6 silently
`continue`s past a token it cannot resolve — which is indistinguishable, from the harness's own
output, from a token that was never supposed to resolve.

## Decision

### D1 — Vendor `ui-layout-audit`, and make its own text carry the gate it is invoked under

Byte-copy `~/.claude/skills/ui-layout-audit/SKILL.md` into
`staging/plugin/skills/ui-layout-audit/SKILL.md`, add the `PAIRS` entry, and — in a **second**,
separate step — add one line to the *staged* copy naming "gate 5.05", so the file agrees with what
`concept-to-code` §25 already says about it. This is the same shape `skill-coverage-perimeter.test.sh`
C5/C6 already enforces for `design-brainstorm` (gate 1b) and `macos-ux` (gate 1c): two sides of one
contract, asserted independently, so a failure names which side moved.

The two steps are deliberately not one commit. R-01 ("byte-identical... at the moment of vendoring")
is a snapshot fact about the copy operation, not a standing invariant — `staging/` is expected to
move ahead of `~/.claude` the moment a fix lands in it, exactly as `pairs-completeness.test.sh`'s own
header says of every vendored file. The gate-naming edit is the first divergence, and it is the
divergence `sync-to-claude.sh --apply` (Task 7 / R-10) is what pushes back to the deployed copy.

**`C7`** in `skill-coverage-perimeter.test.sh` mirrors `check_gate_contract` verbatim for
`ui-layout-audit` / `"gate 5.05"`. No change is needed on the `concept-to-code` side: `SKILL.md:25`
already reads `` `ui-layout-audit` (gate 5.05 only, conditional on UI files present) ``, which
already satisfies the check's c2c-side half. Only the skill-side half is missing today.

### D2 — The registry lives beside `# pairs-zone-anomaly:`, in the file that decides deployment

`# deployed-only: <name> — <reason>` lines in `staging/sync-to-claude.sh`, one per excluded skill,
placed beside the existing zone-anomaly declaration. `sync-to-claude.sh` is what decides which files
reach `~/.claude`; a statement that a file deliberately does not is a fact about the same subject, in
the same place, following the exact precedent ADR-0081 set for zone anomalies: declared where the
norm is defined, derived by a test at run time.

ADR-0077's rule — a waiver travels with the file it excuses — cannot apply here: the excused file is
absent from `staging/` by construction, so there is nothing in this repository for the waiver to
travel with. The registry is the answer to the one shape ADR-0077 does not cover.

Five entries: `agent-design` (proprietary book-derived knowledge base, per its own frontmatter
`license:` field), `daily-close` and `daily-open` (personal routines bound to local connectors —
Obsidian, NotePlan, DEVONthink, ms365), `vibiso-intake` (front end of a different project's intake
contract, `vibiso-system` ADR-002), and `website-auditor` (a symlink into a foreign repository,
ADR-0024 §2.1's exclusion, moved here from prose-only).

### D3 — Two verification directions, two homes, and only one is machine-independent

| direction | catches | runs | why |
|---|---|---|---|
| every declared name is **absent** from `staging/` | a stale waiver — the skill was vendored and the declaration was not removed | CI, `pairs-completeness.test.sh` | reads only `staging/`, reproducible anywhere |
| every **deployed** skill is vendored or declared | a new undeclared skill | `sync-to-claude.sh`, at deploy time | needs `$HOME/.claude`, which ADR-0084's Consequences already refused to make CI depend on |

The second direction is a report, not a gate: `sync-to-claude.sh` already has a human reader at the
point it runs — the same person who can answer "what is this skill" — and R-06 says so explicitly
("it reports; it never blocks the sync"). This is the same asymmetry ADR-0081's ZA framework applies
to zone anomalies, one level up: the reproducible half is a CI assertion, the machine-dependent half
is a printed line a human reads once per sync.

### D4 — F6 resolves against skills **and** agents; an unresolved token is a failure, not a `continue`

`skill-text-corrections.test.sh` F6 derives chain-invokable names from `concept-to-code` §25 and
today silently skips any name that is not a staged `SKILL.md`. Measured, that line yields **nine**
backticked tokens: seven resolve as skills, `reviewer` is an **agent**, and `ui-layout-audit` is the
gap this feature closes. One `continue` was doing two jobs — "this token is a non-skill name that
belongs on this line" and "this skill is missing from staging" — and could not tell them apart.

A token resolving as **neither** a staged skill nor a staged agent is now a failure. `reviewer`
passes because `plugin/agents/reviewer.md` exists and needs no frontmatter-flag check (the
`disable-model-invocation` mechanism is Skill-only); `ui-layout-audit` fails until D1 lands. The
derivation stays inside `staging/`, so the check remains CI-runnable and no name list enters the
test — the identity waiver ADR-0069 §PTD already refused once.

A second, independent count guard sits underneath: the **raw token count** extracted from the §25
line, before resolution, must stay near 9. Without it, a heading rewrite or a lost backtick set could
collapse the line to zero tokens, and zero tokens produces zero unresolved names — a vacuous pass
that reads exactly like full coverage, the ADR-0043 direction lesson applied to this file's own
guard.

**Ordering matters and is deliberate.** The F6 fix (Task 1) lands *before* `ui-layout-audit` is
vendored (Task 2). Fixing F6 first means the very first run of the corrected check fails, citing
`ui-layout-audit` as unresolved — not a synthetic planted defect, but the real gap the whole feature
exists to close, observed directly. Vendoring in Task 2 is then what turns it green. This is stronger
evidence than a fixture, and it is the sequence R-09 asks for: seen failing before it is accepted.

### D5 — Instance 7 of the derived-guard family, and it stays a copy

ADR-0086 measured six existing instances of "derive a population, let a file declare its own waiver,
count-guard the derivation" and decided, on the criterion *would two copies giving different answers
be a defect?*, not to extract a shared helper. This feature adds a **seventh**: the deployed-only
registry (derive declarations from `sync-to-claude.sh`, count-guard, check the stale-waiver
direction) is its own population asking its own question, no more suited to a shared helper than the
other six were to each other. Recorded in the header of `pairs-completeness.test.sh`'s new section,
per ADR-0086 §D4's convention — a line naming the instance, no enforcing test, because an assertion
that a comment exists would itself be the pattern's eighth copy.

## Alternatives considered

1. **Vendor all six skills, including the four out of scope.** Rejected: it is what issue #222 asked
   for on its face and what the SPEC's own measurement refused. Copying `agent-design` would ship
   book-derived content under a licence this repository enforces nothing against (ADR-0065 shipped
   no detector, deliberately); copying `daily-open`/`daily-close` would ship connectors to services
   (Obsidian, NotePlan, DEVONthink, ms365) that exist on one machine and nowhere else this blueprint
   describes; copying `vibiso-intake` would pull a different project's intake contract into a
   blueprint that has no stake in it. "Vendor everything" optimizes for a number going to zero and
   ignores what the number means.

2. **Extend `pairs-completeness.test.sh`'s existing exemption mechanism (`check_complete`'s fourth
   argument) to cover deployed-only skills, instead of a new registry.** Rejected: that mechanism
   exempts a file that is *present in staging but has no deployed counterpart* (`hook-probe.sh`,
   `worktree-capture.sh`) — the opposite shape from a file that is *deployed and has no staging
   counterpart*. Reusing it would need the exemption list to name files that do not exist in the
   directory being swept, which `check_complete`'s glob-driven loop structurally cannot produce (it
   iterates `staging/$_dir/$_pat`, so a name absent from `staging/` is never a candidate to exempt in
   the first place). The registry has to live somewhere that is not driven by a `staging/` glob, and
   `sync-to-claude.sh` — the file that already declares zone anomalies the same way — is that place.

3. **A single test file dedicated to the deployed-only registry, instead of extending
   `pairs-completeness.test.sh`.** Rejected on the operator's explicit instruction and on the merits:
   the registry's forward/reverse-direction shape (count guard, stale-waiver check, reason-length
   floor) is structurally identical to the `ZA` zone-anomaly section already in that file, reads the
   same source file (`sync-to-claude.sh`), and both registries answer the same underlying question
   ("is this declared exception still true?"). A new file would duplicate the `ZA` section's harness
   scaffolding (mktemp, `ok`/`bad`, trap) for zero benefit.

4. **Have F6 hard-code the two extra names (`reviewer`, `ui-layout-audit`) as a known-good exception
   list, instead of a general skill-or-agent resolution.** Rejected: this is exactly the "identity
   waiver" ADR-0069 §PTD refused for the plan-task predicate, for the same reason — a hardcoded name
   list does not travel when §25 gains an eighth invocation, and a corpus glob or a two-element loop
   is what `ADR-0084` §D2's `S6` self-test exists to catch as indistinguishable from a sweep. Deriving
   against `plugin/agents/*.md` generalizes to any future agent named on that line; a name list does
   not.

5. **Do not add a raw-token count guard to F6 (D4's second half); rely on the unresolved-token check
   alone.** Rejected: an unresolved-token check only fires when a token resolves to nothing, which is
   silent (zero output) precisely when the *entire derivation* collapses to zero tokens — a heading
   rename or a lost backtick pair. That is the same vacuous-pass shape `pairs-completeness.test.sh`
   self-test-2 exists to catch for `check_complete`, and the reason this feature adds a floor rather
   than trusting the resolution check to cover both failure modes.

## Consequences

**Positive**

- `ui-layout-audit` — the one chain-invokable skill this repository could not verify — is now
  reachable by the harness, closing the specific hole ADR-0084's Consequences section named by
  number.
- `website-auditor`'s exclusion, prose-only since ADR-0024, is now a machine-checkable declaration
  with a stale-waiver guard, the same protection ADR-0081 gave zone anomalies.
- F6 stops being a check that can pass by silently discarding the one case that mattered — the defect
  this ADR's own D4 measured is now a failure, not a `continue`.
- No new test file, no new CI registry entry: all three assertions (`C7`, the `DO` series, F6's
  rewrite) extend files already named in `docs-ci.yml`'s explicit `shell-tests` list.

**Negative**

- `sync-to-claude.sh` gains a `$HOME`-dependent report block (R-06) that is, by design, unverifiable
  in CI — the same boundary ADR-0084 already accepted for the deployed-vs-staged asymmetry. Its only
  test coverage is the hermetic `HOME`-override pattern `sync-manual-steps.test.sh` already uses for
  every other notice in that file; a defect in the report's *logic* (as opposed to its *wiring*) is
  no more visible than any other notice in that file was before this feature.
- The deployed-only registry names five reasons that are true today and unenforced going forward
  (`agent-design`'s licence, in particular) — the same disclosed, unsolved gap ADR-0065 already
  recorded for provenance in general. Nothing here checks that a reason stays true.
- `ui-layout-audit`'s staged copy diverges from its deployed counterpart the moment D1's second step
  lands, until a human runs `sync-to-claude.sh --apply` (Task 7). Between those two points, a
  completeness check reading only `staging/` would see the gate-mention line; the live `~/.claude`
  copy would not yet have it. Bounded to the span of this feature's own implementation.

**Neutral**

- This is the seventh instance of the derived-guard family ADR-0086 examined and chose not to
  collapse into a helper. Nothing here revisits that call; the registry's header names itself as
  instance 7 per that ADR's own convention (§D4), and no test enforces that the header line exists,
  for the same reason ADR-0086 gave for the other six.
- `agent-design`, `daily-open`, `daily-close`, and `vibiso-intake` remain exactly as reachable (or
  unreachable) from this repository as they were before — declaring them does not change what they
  do, only what a reader is told about why they are absent.

## References

- Issue #222 (source), `docs/specs/222-vendor-deployed-only-skills.spec.md` (SPEC, all ten
  requirement IDs)
- ADR-0024 §2.1 (original, prose-only `website-auditor` exclusion)
- ADR-0043 (the direction lesson: a check validating a list's entries cannot see what it omits)
- ADR-0077 §D3 (the waiver-travels-with-the-file rule this registry is the one exception to)
- ADR-0081 (`# pairs-zone-anomaly:` — the declaration + derived-check convention this reuses
  verbatim)
- ADR-0084 (`skill-coverage-perimeter.test.sh` C5/C6 — the gate-contract shape `C7` copies; its
  Consequences section is where the six-skills gap was first named)
- ADR-0086 (the derived-guard family verdict: six copies, no shared helper — this is the seventh)
- ADR-0069 §PTD (the identity-waiver refusal this feature's F6 fix follows for a second predicate)
