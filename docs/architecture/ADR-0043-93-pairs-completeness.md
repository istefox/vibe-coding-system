# ADR-0043 — PAIRS completeness: check the list covers staging, not only that its entries resolve

**Status:** Accepted
**Date:** 2026-07-25
**Issue:** #93
**Extends:** ADR-0024 (the `PAIRS` mechanism and its one-entry-per-file rule)

---

## Context

PR #90 corrected `architect.md`'s write-scope line. The correction never reached `~/.claude`. Nothing
failed, no check went red, and the deployed agent kept the stale line for half a day while the repo,
CI and the ADR all recorded it as fixed. It surfaced only because PR #92's sync dry-run happened to
print the diff.

The cause was not a bug in `sync-to-claude.sh`. `PAIRS` did not mention `agents/` at all, so the file
was never in the incremental path. Agent and rule files do reach `~/.claude`, but only through
`docs/RUNBOOK.md` Step 6's `cp staging/plugin/agents/*.md ~/.claude/agents/` — part of a full-install
procedure nobody runs to ship a one-line frontmatter fix.

`pairs-completeness.test.sh` could not have caught it. It asserts every PAIRS **src** exists under
`staging/`: it validates the list's own entries and cannot see a file the list omits. **That
asymmetry is the defect.** The fourteen missing entries are its first visible symptom, not the
problem itself — which is why this ADR is about the check, and the entries are the smaller half.

## Decision

**1. Fourteen `PAIRS` entries** — seven agents (`architect` landed in #92) and seven rules. Additive,
one entry per file, exactly ADR-0024's rule. The copy loop already `mkdir -p`s a new destination
directory, so `rules/` needed no code change.

**2. The reverse check, in the same test file.** `check_complete <pairs-file> <dir> <pattern>`
asserts every matching file under a covered staging subtree appears as a PAIRS src. It compares the
staging-relative path exactly as `PAIRS` spells it, so a typo'd entry counts as missing rather than
as coverage. Extended in place rather than added as a new file: same subject, and the file is
already registered in both CI registries.

**3. A second self-test, mirroring the existing one.** The reverse check is run against a real,
non-empty subtree with an empty PAIRS list and must report every file. Without it the check could
pass vacuously — a glob matching nothing reports nothing, and a silent zero-file result reads
exactly like full coverage. That is the same shape of failure this ADR exists to prevent, so leaving
it unguarded would have been an unusually poor joke.

### Alternatives considered

**Directory-level sync for `agents/` and `rules/` (issue #93's Option B).** Deferred, not rejected.
It closes the class rather than the instance and would cover any file added later with nobody
remembering. ADR-0024 states directory sync needs its own ADR, and the reason is real: it has to
decide what happens to a deployed file that disappears from staging, which per-file `PAIRS` never
has to answer. The completeness check delivers most of B's protection — a new uncovered file fails
CI — without settling that question. If B is later adopted, the check becomes the assertion that the
directory rule is actually wired.

**Leave it and rely on the RUNBOOK bulk copy.** Rejected: that is the status quo that already failed
once, undetected.

## Consequences

### Positive

- An agent or rule file added without a `PAIRS` entry now fails CI instead of quietly never
  deploying. The failure message says what actually goes wrong: "in staging but not in PAIRS (edits
  will never deploy)".
- Confirmed RED before the entries were added: exactly the fourteen expected files, no others.
- Deploys nothing today — all fourteen were byte-identical to their deployed copies. Purely
  preventive, which is also the condition that kept the gap invisible.

### Negative / residual

- **`staging/plugin/hooks/hooks.json` is deliberately not covered.** It has no deployed counterpart
  at all: `~/.claude/hooks/hooks.json` does not exist. A `PAIRS` entry would *create* a file that has
  never been there, and whether Claude Code reads a `hooks.json` outside a plugin directory is
  unverified. That is a deployment change wearing a completeness fix's clothes, and it needs its own
  decision. Named here so the exclusion is a choice rather than an oversight — the exact failure mode
  this ADR is about.
- Coverage is per-subtree and enumerated by hand. A future `staging/` subtree gets no protection
  until someone adds a `check_complete` line for it. Bounded by design: the alternative is scanning
  all of `staging/`, which would demand entries for files that are not meant to deploy.
- The check compares paths literally, so it cannot tell a wrong destination from a right one. It
  proves a file is listed, not that it lands where it should.

## References

- ADR-0024 — the `PAIRS` mechanism, its additive one-entry-per-file rule, and the deferral of
  directory-level sync
- ADR-0041 / ADR-0042, issues #58 and #91 — the edit that silently did not deploy, and the dry-run
  that exposed it
- `docs/RUNBOOK.md` Step 6 — the bulk copy that was the only path for these fourteen files
- `staging/plugin/scripts/tests/pairs-completeness.test.sh` — both directions, two self-tests
