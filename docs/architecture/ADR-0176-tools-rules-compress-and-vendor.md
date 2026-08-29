# ADR-0176 — Vendor and compress `~/.claude/rules/tools.md`

- **Status:** Accepted
- **Date:** 2026-08-29
- **Builds on:** repo rules 4 (did-not-run distinct from clean), 7 (guard the denominator), 8 (ask
  which direction the check runs), 12 (a cross-reference names a distinctive anchor, not a line
  number), 14 (a historical record is not corrected in place), 17 (a producer/consumer pair needs
  something checking they meet); the `CLAUDE.md`/`docs/chain-decisions.md` split (ADR-0136,
  ADR-0163) as the direct precedent for a loaded-instruction / looked-up-archive pair.

## Context

`~/.claude/rules/tools.md` was **264 lines / 20,757 bytes**, one of only two rules files with no
`paths:` key (the other, `writing-style.md`, is 19 lines). Every other rules file
(`shell.md`, `python.md`, `swift.md`, …) is path-scoped and loads only for matching file types, so
`tools.md` was ~87% of the always-loaded rules cost, paid in every session in every project — the
second-highest per-session token cost measured in the 2026-08-28 audit, after
`concept-to-code/SKILL.md` (closed by `VCS-047`/`VCS-048`, ADR-0174/ADR-0175).

Its 31 entries averaged **8.5 lines each**. Measured against this repo's own proven density,
`CLAUDE.md`'s 20-rule section runs **77 lines = 3.9 lines/rule**: bolded rule, one-clause reason,
`→ ADR-NNNN` pointer, narrative held separately in `docs/chain-decisions.md`. `tools.md` carried
that narrative *inline* instead — 16 of 31 entries embedded dated incident forensics. The longest
(18 lines, the `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` entry) was ~4 lines of actionable rule wrapped in
~14 lines of 2026-08-25 measurement detail.

A second problem surfaced while scoping this work: **`tools.md` was not tracked in this repo at
all.** It was neither vendored under `staging/user/rules/` (the mechanism every other rules file
uses) nor declared in `sync-to-claude.sh`'s deployed-only registry (which covers only
`plugin/skills/`). It was invisible to the blueprint — edits to it had no review path and no test
coverage, and `staging/sync-to-claude.sh`'s `PAIRS` is an explicit hand-maintained list with no
glob, so a file simply absent from it silently never deploys even once vendored.

## Decision

### D1 — Vendor first, rewrite second

`staging/user/rules/tools.md` was created by copying the live file **verbatim**, then the
compression was applied as a tracked, reviewable diff on top — rather than landing the compressed
version pre-cooked with no prior state to diff against.

### D2 — Compress every entry, archive nothing

The plan this ADR implements (`VCS-043`'s original `TODO.md` note) proposed two levers: archive
stale/resolved entries into a not-loaded file, and compress the rest. Measuring the file falsified
the archival premise: almost nothing in it is genuinely obsolete. The entries are permanent machine
facts (bash 3.2, zsh word-splitting, BSD `cat`, `ugrep -G`'s parse quirks, the `rm -rf`/
`git checkout --` permission denials) that remain true regardless of when they were written.
Selective archiving would require proving, per entry, that a lesson can no longer fire — and if one
mis-archived entry does recur, the lesson is not loaded when it is needed.

Compressing all 31 keeps every lesson inline, requires no staleness judgment, and produced a larger,
more certain cut than partial archival would have: **264 → 152 lines, a 42% reduction**, with all
31 entries surviving as a rule statement (verified by count, not by eyeballing the diff — see
Verification item 6).

### D3 — Split narrative into a paired, not-loaded evidence file

Each entry's dated forensics (exact transcripts, byte counts, measurement methodology) moved to a
matching `## <anchor>` section in new `docs/tools-evidence.md`. This is the `CLAUDE.md` /
`docs/chain-decisions.md` pattern (ADR-0136/ADR-0163) applied to a second always-loaded file:
`docs/` is outside `sync-to-claude.sh`'s `PAIRS` list entirely, so the evidence file needs no sync
entry and never deploys — it is looked up, not loaded.

The pointer is a bare anchor (`→ #bash-32`), not a path, because `tools.md` is user-global and
loads identically in every project; a repo-relative path would not resolve from elsewhere. The
evidence file's location is stated once, in `tools.md`'s own header.

### D4 — Guard the split (rule 17), in both directions (rule 8)

A pointer specified in one file and consumed in another, with nothing checking they meet, is
exactly rule 17's failure shape. New
`staging/plugin/scripts/tests/tools-rule-evidence-anchors.test.sh`:

- **TE1 (forward)**: every `→ #anchor` in `tools.md` resolves to a real `##` heading in
  `tools-evidence.md`.
- **TE2 (backward, rule 8)**: every heading in `tools-evidence.md` has at least one referring
  anchor in `tools.md`, so an orphaned narrative block cannot accumulate unnoticed — a check that
  only validates the list's own entries is blind to what the list omits.
- **TE3 (denominator guard, rule 7)**: anchor count and heading count are each non-zero and equal.
  A zero-anchor population would make TE1's forward loop vacuously pass; TE3 catches that shape
  directly, and asserts exact parity rather than a floor — the population is closed (every anchor
  names exactly one heading and vice versa), so a floor with slack would absorb its own plant
  (rule 10), while parity cannot.
- Missing input file → exit 3, not a false clean pass (rule 4).
- All three assertions are `# plant:`-declared and confirmed RED via `plant-check.sh` (needle
  uniqueness checked manually before the full run: each of TE1/TE2/TE3's needles matches exactly
  once in its target file).

### D5 — PAIRS entry, no exemption needed

`user/rules/tools.md|rules/tools.md` added to `sync-to-claude.sh`'s `PAIRS` block, alphabetically
between `sql-migrations.md` and `swift.md`. `user/X → X` is the mapping `pairs-completeness.test.sh`
already treats as conforming (no `pairs-zone-anomaly:` declaration needed), and its `ZA2` floor
(`>= 100` total entries) only rises.

## Verification

1. `pairs-completeness.test.sh`: PASS=326 FAIL=0 (up from 324, consistent with one new staged file
   plus one new PAIRS line).
2. `tools-rule-evidence-anchors.test.sh` (new): PASS=4 FAIL=0 — TE1/TE2/TE3 clean, Z1 floor met.
3. `worktree-isolation-contract.test.sh`: 104/104 — its J5 sweep (scans `staging/user/rules/*.md`
   and `docs/*.md` for an affirmative `WorktreeCreate` promise) found no `WorktreeCreate` mention
   in either new file; the floor rose from its prior value, nothing else changed.
4. Full local suite (91 files, background): confirmed clean, `SUITE_DONE FAIL_COUNT=0`.
5. `plant-check.sh` (background, full run): confirmed clean, PASS=634 FAIL=0, `DONE rc=0`. PC1
   (626 of 626 declarations fired), PC2, PC3 (59 files), PC4, PC5, PC5b all clean, including the
   three new TE1/TE2/TE3 plants firing individually. Z1 floor: 633 >= 14.
6. No lesson lost: `staging/user/rules/tools.md` carries exactly 31 `- **` entries and 31 `→ #`
   anchors, matching the original 31 top-level bullets, checked by direct count
   (`grep -c '^- \*\*'`), not by inspection.
7. `sync-to-claude.sh` dry-run: reports `rules/tools.md` as `CHANGED` with the intended diff
   (verbose narrative → compressed rules against the anchor headers); no `--apply` run as part of
   this change — deploying to `~/.claude/` is a separate explicit step after merge.

## Alternatives rejected

- **Archive stale entries, compress the rest.** Rejected per D2 — the staleness premise measured
  false; almost every entry is a permanent machine fact, not a resolved incident.
- **Leave `tools.md` untracked and edit the live file directly.** Rejected: no review path, no test
  coverage, and every other rules file already uses the vendor-then-sync mechanism — this file
  should not be the exception.
- **Fold the evidence into `docs/chain-decisions.md`.** Rejected: that file's own header states its
  scope is chain-decision ADR narratives specifically; `tools.md`'s entries are machine/tool facts
  with no ADR of their own until this one, and a second unrelated topic inside one archive file
  would blur what each is a lookup index *for*.

## Consequences

### Positive

- `tools.md` drops from 264 to 152 lines (42% reduction) on every session in every project, with
  no lesson lost — every entry survives as an inline rule, verified by count.
- `tools.md` is now tracked, reviewable, and deployed through the same vendor/sync/test path every
  other rules file uses, closing the second invisibility gap this repo had (`writing-style.md`,
  out of scope here, is the first — noted, not fixed).
- The anchor-integrity guard (D4) is a directly reusable pattern for any future always-loaded file
  that needs the same loaded-instruction / looked-up-archive split.

### Negative, stated plainly

- The evidence file (`docs/tools-evidence.md`) is a second archive alongside `docs/chain-decisions.md`,
  with its own anchor convention rather than the ADR-number convention the chain-decisions index
  uses — a reader who knows one does not automatically know the other's lookup shape. Justified
  here because `tools.md`'s entries are not chain-decision ADRs and forcing them into that index
  would misrepresent what they are.
- `writing-style.md` (19 lines, same untracked/always-loaded shape) remains out of scope — noted
  in the plan's scope boundary, not fixed by this change. It is not currently a token problem, so
  vendoring it is deferred as a separate, cheap follow-up.
