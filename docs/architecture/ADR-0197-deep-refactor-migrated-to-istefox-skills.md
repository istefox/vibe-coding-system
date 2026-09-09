# ADR-0197 — `deep-refactor` is retired from this repo's vendored surface; one file is retained as a contract reference, never as a deploy source

- **Status:** Accepted
- **Date:** 2026-09-07
- **Related:** ADR-0191 (`project-tasks` migrated to `istefox/Skills` — the precedent this follows),
  ADR-0087 (the `deployed-only` registry this adds a tenth entry to), ADR-0018 (the `deep-refactor`
  skill's original design), ADR-0031 (the `enumerate-sources.sh` glob-override fix and the harness
  section that survives this migration as its contract test), ADR-0193 (`codex-reviewer.sh
  --mode audit`, whose §D3 created the runtime coupling this ADR has to keep alive), ADR-0194
  (Codex substitution explicitly *not* extended to `deep-refactor`), ADR-0077 (a waiver travels
  with the file it excuses — and the two reasons it cannot here).

## Context

`staging/sync-to-claude.sh` vendors `deep-refactor` through four `PAIRS` lines into
`staging/plugin/skills/deep-refactor/**`. The live skill is not that copy: `~/.claude/skills/deep-refactor`
is a symlink into `/Users/stefer/Developer/Skills/Deep_refactor`, a separate git repository
(`github.com/istefox/Skills`) with its own remote and history — structurally identical to the
`project-tasks` situation ADR-0191 settled three days ago, and to `auto-learning` and
`website-auditor` before it.

Phase 0 of the deploy roadmap already added a symlink-clobber guard to `sync-to-claude.sh`. Read
directly rather than assumed (rule 13), the guard resolves each destination's parent with
`cd "$_ddir" && pwd -P` and refuses anything outside `$DEST`:

```text
case "$_dreal" in
  "$DEST"|"$DEST"/*) ;;
  *) printf '\n!! REFUSED: %s resolves outside %s ...'; continue ;;
esac
```

For all four `deep-refactor` destinations the parent resolves into `Developer/Skills/Deep_refactor`,
so **every one of those four PAIRS entries is already a dead deploy target**. `--apply` refuses
them today. Vendoring the tree changes nothing about what reaches `~/.claude`; it only keeps this
repository claiming ownership of content it does not maintain, and keeps a stale fork on disk for
readers and harnesses to mistake for the real thing.

### The wrinkle `project-tasks` did not have

`staging/plugin/scripts/codex-reviewer.sh:206` resolves its audit file-list helper relatively:

```text
ENUM="$SCRIPT_DIR/../skills/deep-refactor/scripts/enumerate-sources.sh"
```

ADR-0193 §D3 chose that relative form deliberately, because it resolves correctly in *both* trees:
in `staging/`, `plugin/scripts/` + `../skills/deep-refactor/scripts/`; deployed, `~/.claude/hooks/`
+ `../skills/deep-refactor/scripts/`. Deployed, therefore, it resolves **through the symlink into
the foreign repository** — which is where it has always resolved, vendored copy or not.
`codex-reviewer.sh --mode audit` runs against the foreign repo's `enumerate-sources.sh` at runtime
and against this repo's copy under the harnesses. Two copies of one question ("which files are this
project's source"), and until now nothing compared them.

### What actually reads the vendored tree today, measured

The SPEC named three harnesses. Measured across `staging/plugin/scripts/tests/` at
`46cb127`, the real population is larger, and the difference matters because two of the extra
consumers fail in ways that do not look like this migration:

```text
codex-audit-mode.test.sh          S0 hard-exits 1 on a missing SKILL.md, killing all 44 CX
                                  assertions; CX10's finding-schema denominator, CX20-CX25 and
                                  five `# plant:` declarations all read the vendored SKILL.md.
                                  CX08 / CX09 / CX32 read the vendored enumerate-sources.sh.
refactor-snapshot-deep-refactor   Section B (B1-B6) runs the vendored enumerate-sources.sh
  .test.sh                        offline, hermetically, in CI. Section C (C1-C5) reads the
                                  vendored SKILL.md's Gate 2 block.
workflow-dispatch-pins.test.sh    A2/A3 read the vendored SKILL.md. A1 is negative-shaped, so
                                  with the file gone it passes VACUOUSLY (rule 4).
dispatch-completion.test.sh       DC21 is a FROZEN EXACT baseline (ADR-0124) containing
                                  `deep-refactor-fix-agents` and `deep-refactor-reviewers`,
                                  both sourced from the vendored SKILL.md's dispatch-site markers.
                                  Not named by the SPEC; goes red on deletion.
skill-coverage-perimeter,         population floors (>= 25) over `skills/*/SKILL.md`; 32 today,
skill-fence-positional-tokens,    31 after. Headroom is ample, and all three skip a directory
worktree-isolation-contract       with no SKILL.md, so the retained residue is invisible to them.
```

### The premise the SPEC states about `pairs-completeness.test.sh`, corrected

R-11 asks that the retained file "must not be flagged as an orphaned vendored file with no PAIRS
entry and no `deployed-only` waiver". Measured, **no such check exists**. `check_complete` is
called for skills with `'*/SKILL.md'` and `'*/references/*.md'` only, and says so in its own
comment: *"Skills: SKILL.md only, not the scripts/ and tests/ files under each skill."* `DO2`
likewise tests only `staging/plugin/skills/<name>/SKILL.md`.

So a retained `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh`, in a directory
with no `SKILL.md`, passes the suite **today, by silence**. That is the worse outcome, not the
safe one: it is precisely the shape rule 8 names — a check that validates the entries of a list is
blind by construction to what the list omits — and `deep-refactor` would become the first skill
directory in `staging/plugin/skills/` with no `SKILL.md`, a novel state nothing declares and
nothing checks.

## Decision

**D1 — Declare `deep-refactor` `deployed-only`.** One line in `sync-to-claude.sh`'s ADR-0087
registry, alphabetically between `daily-open` and `impeccable`, em-dash separator, reason ≥ 40
characters, naming the specific target (`Developer/Skills/Deep_refactor`, `github.com/istefox/Skills`)
and this ADR — same class and same wording family as the `auto-learning` / `project-tasks` /
`website-auditor` entries.

**D2 — Remove the four PAIRS lines** for `deep-refactor`. Batched with D1 in one commit, for the
reason ADR-0153 §D6 stated and ADR-0191 restated: a batch that removes PAIRS without adding the
waiver, or the reverse, leaves `pairs-completeness.test.sh` DO2 correctly red on a stale registry
for one release.

**D3 — Delete `SKILL.md` and `tests/run-tests.sh`** via `git rm`. `run-tests.sh` already reads
`$HOME/.claude/skills/deep-refactor/SKILL.md`, never the vendored copy, so it has been asserting
against the foreign repo all along while sitting in this one; with the vendored `SKILL.md` gone it
would be a harness for a file this repo neither owns nor stores.

**D4 — Retain `scripts/enumerate-sources.sh` and `tests/enumerate-sources.test.sh`, at their exact
current paths, as a declared contract reference — never as a deploy source.** The path does not
move. Three assertions (`CX08`, `CX09`, `CX32`) pin the staging-side resolution of exactly
`../skills/deep-refactor/scripts/enumerate-sources.sh`, and that identical-in-both-trees property
is the whole reason ADR-0193 §D3 chose the relative form. Moving the file to a `fixtures/`
directory would break three assertions in a harness whose subject is a different feature, and would
break the property those assertions exist to protect.

**D5 — The retained files are declared, not tolerated.** A new declaration class in
`sync-to-claude.sh`, beside the existing `pairs-zone-anomaly:` and `deployed-only:` blocks:

```text
# contract-reference: plugin/skills/deep-refactor/scripts/enumerate-sources.sh — <reason>
# contract-reference: plugin/skills/deep-refactor/tests/enumerate-sources.test.sh — <reason>
```

`sync-to-claude.sh` is the correct home for it for the same reason ADR-0087 gave the `deployed-only`
registry that home: it is the file that decides what reaches `~/.claude`, and a
retained-but-never-deployed file is a statement about exactly that. ADR-0077's rule that a waiver
travels with the file it excuses cannot apply here, and for a **different reason** than in the
`deployed-only` case: there, the excused file is absent, so there is nothing to travel with. Here
the file exists — but its value is being a faithful copy of the foreign repo's script, and a marker
comment inserted into it would destroy the byte-identity D7's drift check is built on.

**D6 — The declaration comes with the check that reads it,** or it is a producer nothing consumes
(rule 17). Five assertions in `pairs-completeness.test.sh`, in the CR block, mirroring the shape of
the ZA and DO blocks already there:

- `CR1` — count guard on the derivation (rule 7): at least one `contract-reference:` line parsed.
- `CR2` — every declared path exists on disk. A declaration outliving its subject exempts nothing
  while still hiding whatever takes that path (rule 9, the same direction as `ZA4` and
  `check_exemptions_live`).
- `CR3` — no declared path appears as a PAIRS `src`. This is the substance: retained means
  *not deployed*, and a PAIRS entry re-added for one of these files would re-create the dead
  deploy target D2 removes.
- `CR4` — backward self-test for `CR3`, against a synthetic fixture declaring a path that *is* in
  PAIRS, run through `CR3`'s exact logic. Without it `CR3` is vacuously satisfiable, the lesson
  `DO4` and `self-test 2` already encode in this file.
- `CR5` — **the reverse direction, and the one that closes the measured blind spot** (rule 8): for
  every name declared `deployed-only`, every file under `staging/plugin/skills/<name>/` must carry
  a `contract-reference:` declaration. `DO2` asks "is a declared deployed-only name vendored?" and
  looks only at `SKILL.md`; `CR5` asks "does a deployed-only skill's directory hold anything at
  all, and is each such file declared?". It generalises to every future migration of this class,
  and it is what makes retaining `enumerate-sources.sh` a declaration rather than a silence.

**D7 — Staleness against the live foreign copy is detected by a byte-diff, reported at dry-run
time, and it is a REPORT.** `sync-to-claude.sh` gains a block in its existing report section (the
one ADR-0087 §D3 already established as `$HOME`-dependent and unverifiable in CI) that compares
each `contract-reference:` file against its counterpart under `$DEST/skills/`. Three states, all
distinct (rules 4 and 5):

- live counterpart **absent** → `DID-NOT-RUN`, naming the path. Not clean, not drift.
- present and **byte-identical** → `CLEAN`.
- present and **differing** → `DRIFT`, naming the file and the `diff` command to run.

It never sets `MANUAL=1` and never affects the exit code — same contract as the deployed-skill
report immediately above it. That is not only consistency: `sync-manual-steps.test.sh` asserts
(`A3`) that the all-clear line prints when nothing is outstanding, under a hermetic `$HOME` fixture
that contains no `skills/` tree at all. A drift block setting `MANUAL=1` on the absent case would
turn `A3` red in CI for a state that is not an outstanding manual step.

**D8 — The CI-runnable contract test already exists; it is kept and re-headed, not written.**
Section B of `refactor-snapshot-deep-refactor.test.sh` (B1-B6, ADR-0031) invokes the retained
`enumerate-sources.sh` against a disposable `mktemp` git fixture, with zero `$HOME` dependency, and
already runs in `docs-ci.yml`. It pins exactly the contract `codex-reviewer.sh` depends on: the
`<root> [<path-override>]` argument shape, both override forms, the exclusion set, and the empty
output on no match. Its B6 comment already states its role verbatim — *"included here purely for
CI-visible coverage, since the equivalent `$HOME`-coupled test never runs in CI."* Under this ADR
that stops being incidental coverage and becomes Section B's declared purpose. The file is **not
renamed**: the name is referenced by `docs-ci.yml`, ADR-0031 and ADR-0032, and renaming buys
nothing.

**D9 — The retained `enumerate-sources.test.sh` becomes the live-side behavioural probe,** run by
hand when D7 reports `DRIFT`. It already points at `$HOME/.claude/skills/deep-refactor/scripts/enumerate-sources.sh`,
it sits outside both the CI list and `plant-check.sh`'s glob (`staging/plugin/scripts/tests/*.test.sh`),
and `.claude/test-ignore` already records that boundary. It gains one thing: a rule-4 guard so an
absent live script is `DID-NOT-RUN` (exit 3) rather than thirteen `FAIL` lines that read as
thirteen contract breaks. Its role is not D7's: the diff says *that* the live copy changed, this
says *whether the contract still holds* — which is what decides whether `codex-reviewer.sh` is
broken or merely out of sync.

**D10 — Assertions removed leave a comment where they stood** (rule 19), naming this ADR and the
migration, in all four harnesses D3 orphans: `codex-audit-mode.test.sh` (S0's SKILL half, CX10's
denominator, CX20-CX25 and their five `# plant:` declarations), `refactor-snapshot-deep-refactor.test.sh`
Section C, `workflow-dispatch-pins.test.sh` Section A **including A1** — A1 is negative-shaped and
would otherwise survive as a vacuous pass — and `dispatch-completion.test.sh`'s DC21 frozen
baseline, which loses two entries.

**D11 — Nothing in `codex-reviewer.sh` changes.** SPEC options 2 (repoint the resolution) and 3
(remove the coupling) are rejected; see below.

**What this repo keeps no opinion on:** whether `istefox/Skills` has adequate tests, ADRs or review
discipline for `deep-refactor` going forward. Same boundary ADR-0191 drew.

## Alternatives considered

**A1 — Delete `enumerate-sources.sh` along with the rest of the tree, and let
`codex-reviewer.sh --mode audit` resolve only against the deployed symlink.** Rejected. It is the
cleanest-looking option and it loses the most: `CX32` fails outright (its fixture requires the file
to exist so it can clear the execute bit on a copy), `CX08` degrades to a vacuous pass (the guard
fires because the file is absent, not because the test moved it aside), Section B of
`refactor-snapshot-deep-refactor.test.sh` loses its subject, and this repository is left invoking a
foreign script whose interface nothing here checks. The coupling would then be exactly what
ADR-0193 §D3 argued against — one question answered in two places with nothing comparing them —
except with the second answer now invisible.

**A2 — Repoint `codex-reviewer.sh`'s `ENUM` at a path this repo owns** (SPEC option 2). Rejected,
and the SPEC records the user's rejection. It would break ADR-0193 §D3's resolves-identically-in-both-trees
property, break the `CX09` literal pin, and — the substantive objection — deploy a *second*
`enumerate-sources.sh` to `~/.claude`, so `deep-refactor/SKILL.md`'s own documented invocation
(`bash ~/.claude/skills/deep-refactor/scripts/enumerate-sources.sh`) and `codex-reviewer.sh`'s
would diverge silently the first time either side changed. That is the drift ADR-0191 quotes
`chain-integration.md` on, reintroduced deliberately.

**A3 — Remove the coupling entirely: re-implement the exclusion set inside `codex-reviewer.sh`**
(SPEC option 3). Rejected. ADR-0193 §D3 already rejected exactly this under ADR-0086 §D1 — two
copies of one question giving different answers is the extract-don't-copy case — and nothing about
this migration changes that argument. It would also make `codex-reviewer.sh`'s audit scope silently
diverge from what the `deep-refactor` skill itself audits.

**A4 — Move the retained files to `staging/plugin/scripts/tests/fixtures/`,** so their role is
legible from their path and `staging/plugin/skills/deep-refactor/` disappears entirely. Rejected.
It names the role better, which is a real benefit, but it breaks `CX08`/`CX09`/`CX32` — three
assertions in a harness whose subject is a different feature — and it destroys the
identical-relative-path property those assertions exist to pin. `CX09` in particular asserts that
`$SCRIPTS/../skills/deep-refactor/scripts/enumerate-sources.sh` resolves in the staging tree; that
assertion *is* the check that the deployed resolution is not a coincidence. D5's declaration buys
the legibility without the breakage.

**A5 — Put the retention marker inside the retained file's own header, per ADR-0077.** Rejected.
The file's entire value is being a byte-faithful copy of the foreign repo's script, and D7's
staleness detection is a byte-diff against it. A marker line makes the diff permanently non-empty,
so the mechanism reports `DRIFT` forever and is ignored within a week. ADR-0077's rule is right in
general and inapplicable here for a reason worth recording, not overridden by fiat.

**A6 — Pin a checksum of the live script in a test instead of a dry-run byte-diff.** Rejected. A
checksum constant is a second copy of the same fact, in a file with no reason to be edited when the
foreign repo moves, and it would go stale in exactly the direction that reads as clean. The `diff`
compares the two real artifacts and needs no constant to rot. It also cannot run in CI either way
(no `~/.claude` on the runner), so the checksum buys no CI coverage over the diff — only a number
to forget to update.

**A7 — Repoint `codex-audit-mode.test.sh`'s `SKILL_MD` at the live `$HOME` copy and declare the
harness `ci-dark-exempt`.** Rejected. Eight of its 44 assertions read `SKILL.md`; the other 36 are
about `codex-reviewer.sh`, which this repo *does* own. Making the whole file CI-dark to preserve
eight assertions would remove 36 running assertions from CI, and would additionally break the
`plant-shard` job, which runs every `staging/plugin/scripts/tests/*.test.sh` in a sandbox that
copies `staging/` and `docs/` only — a `$HOME`-reading harness has no `~/.claude` there either.
Splitting the eight into a separate `ci-dark-exempt` file was considered and rejected as well: it
creates a harness nothing runs, which is rule 17's failure with extra steps.

## Consequences

### Positive

- `sync-to-claude.sh --apply` stops carrying four entries that Phase 0's guard refuses anyway. The
  dry run stops reporting a `REFUSED` line for a file this repo has no business writing.
- The runtime coupling `codex-reviewer.sh` depends on gains, for the first time, something that
  compares its two ends: D8's Section B checks the contract in CI, D7's diff checks the bytes
  locally, D9's probe checks live behaviour when the diff moves. Before this ADR, a breaking change
  in the foreign repo's `enumerate-sources.sh` would have surfaced as an audit run that silently
  produced the wrong file list, or as exit 3 at 3am.
- `CR5` closes a blind spot that was real before this migration and would have stayed invisible:
  `DO2` only ever looked at `SKILL.md`, so any residue in a `deployed-only` skill's directory
  passed. Nothing had left residue there yet; this migration is the first, and it arrives declared.
- The `deployed-only` registry again states the truth about which skills this repo does not own
  the source for — 10 entries, re-measured at edit time, not carried forward from ADR-0191's 7.

### Negative

- ADR-0193's `deep-refactor/SKILL.md`-side design (Gate 0-CDX's placement and shape, both dispatch
  branches, the Claude-only ELSE's four frozen literals, Gate 1's per-dimension engine attribution)
  becomes unreviewable from this repository. Eight assertions and five plants are deleted for it.
  Auditing that design now means cloning `istefox/Skills`. A real cost, accepted for ADR-0191's
  reason: two repositories both claiming to be canonical is worse.
- `codex-audit-mode.test.sh` drops from 44 to roughly 36 assertions and from 38 plants across 33
  ids to 33 across 28 — the exact figures are to be re-derived at edit time, not trusted from this
  sentence (rule 13). Its header's own count claims must be corrected, and they are a live claim,
  not a historical record, so they are corrected in place rather than forward.
- `dispatch-completion.test.sh`'s DC21 baseline shrinks by two entries. A frozen baseline that
  shrinks is exactly the edit ADR-0124 warns is easy to make silently; the rule-19 comment left in
  its place is the only thing that will tell the next reader those two were removed on purpose.
- The `staging/plugin/skills/deep-refactor/` directory survives with no `SKILL.md` — the first such
  directory in the tree. It is declared and checked (D5, D6), but it will still read as an
  unfinished migration to anyone who greps for the skill name before reading the registry.

### Neutral

- `.github/workflows/docs-ci.yml` needs no change. No `staging/plugin/scripts/tests/*.test.sh` file
  is created or deleted by this migration, and the two deleted files
  (`skills/deep-refactor/SKILL.md`, `skills/deep-refactor/tests/run-tests.sh`) were never in the
  `shell-tests` list — that list only ever runs `staging/plugin/scripts/tests/`. R-08 is discharged
  by verifying CI1/CI2 stay green, not by editing the workflow.
- Population floors are unaffected: `skills/*/SKILL.md` goes 32 → 31 against `>= 25` guards;
  `DO1`'s `>= 5` floor rises 9 → 10; `ZA2`'s `>= 100` PAIRS count drops by 4 from ~180.
- `.claude/test-ignore`'s line about `staging/plugin/skills/deep-refactor/tests/` sitting outside
  the measured perimeter stays true after this migration and needs no correction. It is also a
  dated measurement record (2026-08-14) and is not edited in place either way (rule 14).
- `PROJECT.md:107` and `TODO.md:134,170` are completed ledger entries. Neither claims the tree is
  vendored; both remain accurate statements about the day they were written. They are not edited;
  the forward record is a new `TODO.md` entry and the `chain-decisions.md` / `chain-decision-index.md`
  additions this chain makes anyway.
- The SPEC's "ADR-0031 through ADR-0035" reads the filename `ADR-0031-35-...` as a range. Measured:
  ADR-0033, ADR-0034 and ADR-0035 contain zero `deep-refactor` mentions. Only ADR-0018, ADR-0031
  and ADR-0032 (two incidental mentions) are affected, and only their reference lists.
- No markdown link anywhere in the corpus targets a deleted file (checked with
  `grep -rn "](.*deep-refactor" --include="*.md"`), so the `links` CI job is unaffected.

## Verification

- `bash -n staging/sync-to-claude.sh` clean after the registry, PAIRS and report edits.
- `pairs-completeness.test.sh` green: `DO1`-`DO5` (the registry, now 10 entries, none vendored) and
  the new `CR1`-`CR5` (the retained files declared, present, and absent from PAIRS; `CR4`'s
  synthetic fixture flagged; `CR5` finding no undeclared residue under any `deployed-only` name).
- `bash staging/sync-to-claude.sh` (dry run) reports no `skills/deep-refactor/*` target and no
  `REFUSED` line for one, and prints exactly one contract-reference state line per declared file.
- `sync-manual-steps.test.sh` green, `A3` in particular — the all-clear line must still print under
  the hermetic `$HOME` fixture, proving D7's report never sets `MANUAL=1`.
- Every harness in `staging/plugin/scripts/tests/` passes, `codex-audit-mode.test.sh` and
  `dispatch-completion.test.sh` included.
- `plant-check.sh` full sweep: exit 0, zero `BADPLANT`, zero `NOFIRE`. The five CX20-CX24
  declarations must be gone, not merely orphaned — a needle matching zero times is `BADPLANT`.
- `grep -rn "deep-refactor/SKILL.md" staging/plugin/scripts/tests/` matches only rule-19 comments.

## References

- `staging/sync-to-claude.sh` — `deployed-only` entry added, 4 PAIRS lines removed,
  `contract-reference:` block and drift report added
- `staging/plugin/skills/deep-refactor/SKILL.md` — deleted
- `staging/plugin/skills/deep-refactor/tests/run-tests.sh` — deleted
- `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh` — retained, contract reference
- `staging/plugin/skills/deep-refactor/tests/enumerate-sources.test.sh` — retained, live-side probe
- `staging/plugin/scripts/codex-reviewer.sh` — unchanged; line 206 is the coupling this ADR keeps
- `staging/plugin/scripts/tests/pairs-completeness.test.sh` — `CR1`-`CR5`
- `staging/plugin/scripts/tests/sync-manual-steps.test.sh` — the drift-report section
- `staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh` — Section B re-headed,
  Section C removed
- `staging/plugin/scripts/tests/codex-audit-mode.test.sh` — SKILL.md-dependent assertions removed
- `staging/plugin/scripts/tests/workflow-dispatch-pins.test.sh` — Section A removed
- `staging/plugin/scripts/tests/dispatch-completion.test.sh` — DC21 baseline reduced
- `docs/architecture/ADR-0191-project-tasks-migrated-to-istefox-skills.md` — the precedent
- `docs/architecture/ADR-0087-222-deployed-only-skills.md` — the registry extended here
- `docs/architecture/ADR-0193-codex-review-gate-deep-refactor.md` — §D3, the coupling
- `/Users/stefer/Developer/Skills/Deep_refactor` — the canonical source as of this ADR
