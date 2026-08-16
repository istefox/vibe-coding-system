# ADR-0145 — the registry stops crediting a plant to its sibling's failure (issue #355)

- **Date:** 2026-08-16
- **Issue:** #355 — "plant-check.sh decides a plant fired with a PREFIX match"
- **Supersedes:** nothing. **Amends:** ADR-0108 (the fired predicate), ADR-0140 (the vacuity guard
  that was deliberately built to inherit the same looseness), ADR-0143 (the harness that pins it).

## Status

Accepted.

## Context

`plant-check.sh` decided a plant had fired with `grep -q "^FAIL: $aid"` — a **prefix** match with no
right anchor. So a plant declared for `SP5` was credited when `SP5b`, `SP5c` or `SP5d` failed
instead: a different assertion, possibly for an unrelated reason, in the direction that reads as
coverage. That is the failure mode ADR-0108 exists to remove, reproduced inside the mechanism that
removes it.

### The issue said this needed its own cycle. Measurement said otherwise.

The issue's own text: *"Anchoring the match is easy. Re-verifying **166** plants afterwards is not, and it
will likely expose a population of plants that were only ever credited to a sibling. That is the
work."*

Measured 2026-08-16 at `090a154`, in two stages, before anything was changed.

**Stage 1 — the exposure.** The emitted id set of each declaring harness was derived by **running
it** and reading the `PASS:`/`FAIL:` prefixes (1400 ids), because what matters is what the harness
prints, which is what the grep sees. A plant is *exposed* when its own harness can emit an id that
starts with the plant's id.

**Stage 2 — the defect.** For every exposed plant, the mutation was applied in a sandbox exactly as
the worker applies it and the harness run, recording the **full set of red ids** rather than a
boolean. The old predicate (`any red starts with aid`) was then compared against an anchored one.

| | count |
|---|---|
| declared plants | 387 |
| declaring harnesses | 42 |
| **exposed to a prefix collision** | **33** |
| **exposed plants where the two predicates disagree** | **0** |
| unrunnable | 0 |

`phase1.test.sh` prints `ok   <label>` on success, so a green run emits no `PASS:` line and the
running-derivation is blind to its ids. Its 6 plants were checked against the `ok`/`no` call sites
instead — weaker evidence, stated as such — and none has a sibling. The 387 are fully covered.

**So the re-verification the issue called "the work" is the table above, and it came back clean.**
The anchor is a no-op on today's corpus: every exposed plant already goes red on its own id, and the
other 354 have no sibling that could change their verdict. What grows over time is the exposure —
33 today, more tomorrow — not the defect count.

## Decision

### D1 — one anchored predicate, in one function, for both call sites

```
red_re() { printf '^FAIL: %s:?([[:space:]]|$)' "$(… escape …)"; }
```

The boundary is `:?` then whitespace or end of line, because that is the emitted form across the
corpus: `FAIL: <id>: text` and `FAIL: <id> text`.

**The id is escaped before it reaches the regex.** Assertion ids are not all alphanumeric —
`CE-secret-scan.sh` is one — and an unescaped `.` would restore a looser match than the one being
removed, which would be this issue's own defect surviving its fix.

**One function, two call sites, deliberately.** ADR-0140 built the vacuity guard to inherit the
prefix looseness *on purpose*, so that the fired check and the vacuity check would agree. They must
still agree, so they now share a source rather than a convention: ADR-0086's criterion, where two
copies giving different answers would be a defect.

### D2 — the fixture manufactures the case the corpus does not contain

`PP6` in `plant-registry-parallel.test.sh`. The corpus has 33 exposed plants and **0** mis-credited
ones, so nothing in it can demonstrate the defect — an assertion pinned on the real corpus would
have passed before the change as well.

The fixture therefore builds the case: `epsilon`'s plant names `E1` and mutates the marker only
`E1b` reads. `E1b` goes red, `E1` stays green, and the registry must report that the plant did not
fire. Under the old predicate this same fixture reported it as fired.

**The fixture's own harnesses had to be anchored first.** They grep `MARK-<id>`, and `MARK-E1`
matches `MARK-E1b` — the fixture would have reproduced, inside itself, the exact defect it exists to
demonstrate. They now grep `MARK-<id>` **with its trailing space**, which is what separates the two.

### D3 — what this does NOT change

The three recorded boundaries of the registry stand: `PC4` indented declarations (ADR-0115), the
`../docs/` hatch (ADR-0116), and a replacement that cannot contain a newline (ADR-0112). The
convention of naming an eighth assertion `CP8` rather than `CP7b` becomes unnecessary and is not
retired here — it costs nothing and it is one fewer thing to explain.

## Consequences

- **The two numbers here count different trees, and the difference is stated rather than smoothed.**
  The exposure was measured at **387** plants on the Wave 2 branch, which carries
  `brief-to-app.test.sh`'s 10; the acceptance re-run under the anchored predicate is **381 of 381
  firing** on this branch, off `main`, which does not. Neither figure is the other's, and if any
  plant had stopped firing `PC1` would name it.
- `PP2`'s declaration had to move with the line it plants on. A plant whose needle names an
  implementation line is invalidated by any edit to that line, and the registry reports that as
  `BADPLANT` rather than as a passing assertion — the failure is loud, which is the reason the
  needle is allowed to be that specific.
- The exposure count (33) is worth re-deriving after any batch of new assertions. It is not a
  defect count and should never be reported as one.

## References

- Issue #355 and the 2026-08-16 measurement comment on it.
- ADR-0108 (the registry), ADR-0140 (the baseline and the vacuity guard), ADR-0143 (the parallel
  registry and the fixture harness), ADR-0086 (the extraction criterion), CLAUDE.md rules 1, 2, 7.
