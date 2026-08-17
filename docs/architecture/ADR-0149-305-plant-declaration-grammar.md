# ADR-0149 — the plant declaration grammar is enforced, and then widened to express an insertion (issue #305)

- **Date:** 2026-08-16
- **Issue:** #305 — "the plant registry cannot express an insertion"
- **Supersedes:** nothing. **Amends:** ADR-0108 (the declaration format it defined).

## Status

Accepted.

## Context

ADR-0108 shipped the plant registry and named its own limit: *"Replacement only in v1. Two of the
session's plants were insertions and are not expressible. Named as a limit rather than worked
around."*

### R-01, measured before designing: half the premise is already false

383 plants across 43 files, 2026-08-16.

- **Deletion is already expressible.** 30 of the 383 neutralise with `true`, `:` or
  `if false; then`. The issue's R-01 — "a deletion-shaped defect is expressible as a plant" — is
  satisfied today, and was on the day it was written.
- **A same-line insertion is already expressible too.** One plant replaces a guard's opening with
  `exit 42; if [ "$#" -ne 2 ]; then`, which is a prepend spelled as a replacement.
- **What is genuinely inexpressible is adding a LINE.** A declaration is one line and the
  replacement is applied through a lambda, so a `\n` in it stays two literal characters. The shapes
  that need it are the ones an exhaustiveness assertion guards: an extra row in a table the check
  says has N, a duplicated transition pair, a second heading where the scan counts one.

### What measuring found instead: the stated grammar was enforced nowhere

The header states that a ` | ` sequence cannot appear inside a field. The malformed check says
`need 4 fields separated by ' | '`. The test beside it asked only that fields 1–3 be non-empty and
**never looked at the count**.

One declaration had shipped through that hole. `A25`, in `acceptance-contract.test.sh`, declared

```text
A25 | plugin/scripts/acceptance-adapter-swift.sh | P=$(awk -F'\t' '$2=="PASS"' "$TMP/verdicts.tsv" | wc -l | tr -d ' ') | P=0
```

which is **six** fields. `$3` stopped at the first inner ` | ` and `$4` became `wc -l`, so the
registry substituted

```text
P=$(awk -F'\t' '$2=="PASS"' "$TMP/verdicts.tsv" | wc -l | tr -d ' ')
  ->  wc -l | wc -l | tr -d ' ')
```

a syntax error rather than the intended `P=0`. The adapter died of it, the harness went red, and
A25 was credited as fired. A plant that pins nothing, inside the mechanism built to find assertions
that pin nothing — and it is rule 17 exactly: a contract stated in one place and enforced in none.

## Decision

### D1 — enforce the field count first, widen second

`nfd < 3` or `nfd > 4` is `BADPLANT`, and the message names all three cases. This had to come first:
a `\n` escape in a field that can be silently truncated is a widening built on a hole.

**Three fields is legal and means delete the needle.** That is what the code already did by
accident — awk yields `""` for a field that does not exist — and the choice is between declaring it
and letting the next reader "fix" it. The alternative spelling, four fields with an empty fourth,
needs a trailing space after the last ` | ` that any editor will strip, so it is not offered.

`A25` is rewritten to a needle that stops short of the first pipe (`'$2=="PASS"'` → `'1==0'`), which
still forces `P=0` and now trips the adapter's own arithmetic self-check rather than a parse error.

### D2 — two escapes in the replacement, and only two

`\n` becomes a newline, `\\` becomes one backslash, every other backslash stays as written. That is
enough to express an insertion: `<the existing line>\n<the added line>`.

Backward compatible **by measurement, not by hope** — zero of the 383 existing replacements contains
a backslash, so no declaration changes meaning. `PP9` pins `\\` so the first plant that needs a
literal backslash has a spelling.

### D3 — the assertions are measured against a SECOND fixture, and each distinguishes

The existing fixture's plant and file counts are `PP0`'s subject, so the grammar cases get their
own miniature tree and their own registry run. Each of the four assertions can fail:

- `PP7` — a six-field declaration is `BADPLANT`. Its plant removes the count check and `PP7` goes
  red.
- `PP8` — the deletion and insertion forms both fire. A `\n` left literal keeps the added text on
  the existing line, `grep -c` still counts one row, and the plant reports `NOFIRE` — so the
  assertion distinguishes a real newline from a written one.
- `PP9` — `G3` says "no double backslash anywhere" and stays GREEN under a correct mutation, so the
  registry must report it **not fired**. `G4` carries the same mutation and must fire, which is what
  stops `PP9` from being satisfied by a mutation that never landed. Both directions, one mutation.
- `PP10` — R-02: the exactly-one-match rule is untouched, because the match is on the NEEDLE and the
  two forms differ only in the replacement. An insertion whose needle hits twice is refused.

R-03 needs nothing new: every plant already runs against an isolated `cp -R`, and neither change
touches sandbox construction.

## Consequences

- Three files changed: `plant-check.sh` (the parse and the substitution),
  `plant-registry-parallel.test.sh` (+6 assertions, +3 plants), `acceptance-contract.test.sh` (A25).
- The registry goes from 383 to 386 declarations. `PP7`, `PP8` and `PP9` were each seen RED.
- **The malformed message now names the assertion id.** It said only the file, so two malformed
  declarations in one harness were indistinguishable in the report.
- **`\n` inside a NEEDLE is still literal.** Only the replacement is unescaped. A needle spanning
  two lines is already handled by the `\s+` word join, which is the older and better mechanism for
  that direction.
- The ` | `-inside-a-field limit stands. Enforcing it is what made `A25` visible; relaxing it would
  need an escape in three more fields and a reason nobody has yet.

## References

- ADR-0108 (the registry and the limit it named), ADR-0143 (the parallel mutation phase),
  ADR-0145 (#355, the anchored fired predicate these verdicts rely on), ADR-0099/ADR-0104 (the
  exactly-one-match rule and the two ways it was first broken), CLAUDE.md rules 2, 7, 17.
