# ADR-0082 — Cross-references name anchors, and the population is derived

- **Status:** Accepted
- **Date:** 2026-07-29
- **Issues:** #207, #210 (closed together)
- **Supersedes / amends:** extends the ADR-0018 addendum's named-heading instrument from one file
  to the whole `staging/` tree
- **Related:** ADR-0018 (the first instance), ADR-0043 (guard direction), ADR-0067 §F6 (derived
  class guard), ADR-0069 §PTD (declared waiver, not identity waiver), ADR-0077 (exemption in the
  file being guarded), ADR-0081 (declared anomaly + derived check)

## Context

Rule 3 of this repository's earned-rules list: a cross-reference by line number rots. ADR-0018's
addendum fixed it once — `autopilot-build`'s four `§<line-range>` delegations into
`concept-to-code` became named headings, and `workflow-dispatch-pins.test.sh` section B asserts
each named heading still exists in the file it points into, "a reference that fails loudly instead
of rotting quietly."

That instrument was applied to **one file**. Nothing checked the class.

Issue #207 filed an inventory of five sites, one confirmed stale. #210 verified two of those five as
wrong and, more importantly, named a **surface the inventory excluded by construction**: the
inventory was about references *inside* `SKILL.md` files, and `agent-write-scope.sh`'s two
references are hook-source → `SKILL.md`.

## Decision

### D1 — The population is derived over all of `staging/`, not listed

Deriving it found **three more wrong references** in a **third surface neither issue named**:
skill-private `scripts/` directories — the same subtree ADR-0043 recorded
`pairs-completeness.test.sh` as blind to.

| # | site | it said | what is actually there | named by |
| --- | --- | --- | --- | --- |
| 1 | `concept-to-code/SKILL.md` | `SKILL.md:1355-1358` | the weakening-scan `CLEAN` warning | #207 |
| 2 | `agent-write-scope.sh` | `SKILL.md:357` | a bare code-fence delimiter | #210 |
| 3 | `agent-write-scope.sh` | `SKILL.md:409` | a blank line | #210 |
| 4 | `hook-verify-workflow.sh` | pre-flight `lines 91-94` | the ADR-0080 phase-2 verdict prose | **nobody** |
| 5 | `secret-scan.sh` | `commit/SKILL.md:70` | the ADR-0062 debris bullet | **nobody** |
| 6 | `h16-direction-check.sh` | `manifest-init.sh:125` | the `step5_review_mode` comment | **nobody** |

Six wrong, one drifted-but-nearly-right (`SKILL.md:152-158`, converted in the same pass because
issue #207 asked for it and it is the next to break), eight accurate-but-numeric — all fifteen converted
to anchors.

This is rule 5 (*ask which direction a guard runs in*) demonstrated three times on one defect: a
list, a list plus one surface, and a derivation. A check that validates a list's entries cannot
see what the list omits.

**Defect 4 is the one to remember.** It rotted the day ADR-0080 grew
`pre-flight-pattern-enforce.sh`'s header by ~50 lines and pushed the `agent_type` discriminator
down — *the same commit that was fixing a neighbouring defect in the same file, yesterday*. The
population that must be checked is not "old files someone forgot"; it is every file, including the
ones being actively corrected.

### D2 — A false positive is DECLARED in the file that carries it, on one line

Some `<file>:<digits>` and `line <digits>` strings are not cross-references: illustrative paths in
an Output Format example, a detector's sample output, a script's stdout contract
(`` `public` (line 1) ``). Seven files carry such tokens. Each declares them itself:

```
xref-exempt: <token>|<token>|… — <reason, at least 40 characters>
```

Never a filename list inside the test — that is ADR-0069 §PTD's identity waiver: it does not
travel on rename, and it lets a test author excuse a file without touching it. ADR-0077's
`transcript-scan-exempt` precedent, same shape.

**The one-line requirement is not cosmetic.** A reason wrapped across lines is a prose assertion
that depends on where the text breaks, and this repository has been bitten by that three times
already — ADR-0073's line wrap, ADR-0076's comment marker, ADR-0080's backticks. `U3` measures
only the marker line, so a wrapped reason reads as too short and fails at the moment it is
written. Found the honest way: my first three declarations were wrapped and `U3` caught all three.

### D3 — The extractor skips `xref-exempt:` lines, and the waiver must be live

A declaration names the tokens it exempts, so the tokens appear **on the declaration line**.
Without the skip, a waiver for a token present nowhere else would look live. Rule 12 — a scan
whose needle is a literal counts itself.

`U2` runs the check backwards: a declared token that no longer appears anywhere is a stale
exemption now covering nothing. ADR-0081 §ZA4's direction, reapplied. `S3` is the fixture that
proves the skip works: it declares `gone.sh:9`, which appears only on the declaration line, and
requires the extracted set to come back **empty**.

### D4 — Self-references assert a count of 2, not "at least 1"

Three references point into a distant part of their own file. The anchor therefore appears twice:
once at the target, once in the reference naming it. Asserting exactly 2 fails on either half
disappearing, which is the failure this whole change exists to make loud. `C1b`/`C2b` additionally
pin the **marker form** (`**Gate 0d transition block:**`) at exactly 1, or "2 occurrences" could be
two references and no anchor at all.

Distinctiveness was checked before converting, as #207 required: all nine anchors resolve to
exactly one occurrence in their target. The Step 5 / Step 6 collision ADR-0018 had to work around
was already resolved by that ADR's own rename, and `workflow-dispatch-pins.test.sh` B4a/B4b/B5
still hold it open.

### D5 — `docs/` is out of the population, as a decision

ADRs and plans are historical records, not edited in place (the ADR-0034 precedent), so a line
number in one is a correct snapshot of its own moment. Stated in the harness header and asserted
by `R3`, so it reads as a choice rather than an oversight.

## Consequences

- **Three markdown agent/skill prompts gain an HTML comment** (`coder.md`, `swiftui-pro/SKILL.md`,
  `clean-public-repo/SKILL.md`). That is prompt text a model reads, a real if small cost, accepted
  because the alternative is a waiver that does not travel with the file.
- **The check verifies an anchor EXISTS in its target, never that it is the right place for the
  claim.** All six wrong references had *true* claims and *wrong* pointers; this instrument would
  not have caught a false claim with a valid anchor. Reading stays a human task.
- **`spec-coverage.sh`'s reference into `docs/specs/…` is converted but unverifiable** — its target
  is outside the population by D5. Named here rather than left implicit.
- `C10`, `C11`, `C14` and `C15`'s target side pass before this change as well as after: those
  anchors already existed. They are forward guards, labelled as such in the harness. `U1` is what
  was red for those four.
- The `§<digits>` form is deliberately **not** in the extractor: in this repository it is
  overwhelmingly an ADR section reference (`ADR-0047 §D2`), and the one place it was ever a line
  range is already pinned by `workflow-dispatch-pins.test.sh` B1. A future `§<line-range>` outside
  `autopilot-build` would escape.
- Seen RED before the fix: 23 of the 37 assertions present at that point failed, including all
  seven `W` assertions and nine of the `C` conversions. `C15` was added afterwards, when `U1`
  reported a fifteenth reference the manual sweep had missed — the derivation catching one the
  author did not.
