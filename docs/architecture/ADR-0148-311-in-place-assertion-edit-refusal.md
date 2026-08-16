# ADR-0148 — the in-place assertion edit stays undetected, re-measured and disclosed at all four callers (issue #311)

- **Date:** 2026-08-16
- **Issue:** #311 — "the weakening scan is blind to an in-place assertion edit"
- **Supersedes:** nothing. **Amends:** ADR-0073 (its measurement is extended, not corrected).

## Status

Accepted.

## Context

ADR-0073 §D4 recorded the blind spot and declined to close it: editing an assertion in place removes
one assert-bearing line and adds one, so `assert-removed`'s count comparison cannot fire, and no
detector in `weakening-scan.sh` sees it. Its closing sentence is the reason this issue exists —
"anyone relying on the weakening gate for assertion integrity is relying on something that does not
exist."

The gate is wired into four paths that can produce a commit with no human present.

### R-01, re-measured before designing: 0 of 6 over 383 commits

ADR-0073 measured a rule on `asrt_rm == asrt_add > 0` over 354 commits and found 2 hits, both prose.
Re-derived 2026-08-16 over **every** non-merge commit reachable from `main` — 383 commits, no
sampling, using the script's own `is_test()` and `is_assert_tok()` predicates:

| commit | file | what it is |
|---|---|---|
| `090a154` | `plant-check.sh` | comment lines reordered, one `emit NOFIRE` message string |
| `9739925` | `secret-dep-gate.test.sh` | a comment containing the word "asserted" |
| `8034de0` | `triage-state-gitignore.test.sh` | a `bad "…"` message string, floor raised 15 → 18 |
| `f9c54df` | `spec-pointer-archive.test.sh` | floor raised 9 → 10 |
| `3c7a382` | `agent-metrics.test.sh` | an `ok "…"` message removed, a comment added |
| `d1fe95b` | `step6-effort-pin.test.sh` | a comment |

**Six findings, zero true positives.** Four are prose or message strings. The other two are genuine
in-place assertion edits and both **raise** a floor, which is the opposite of weakening: the rule
cannot see direction, only that a count matched.

The corpus grew by 8% and the finding count trebled while the precision stayed at zero, so 0-of-2
was not a small-sample artefact. R-01 says ship nothing whose precision does not beat 0 of 2. Zero
of six does not beat zero of two.

## Decision

### D1 — no detector, for the third time on this script, and now with a number that is current

ADR-0051 §D5 shipped `literal-assertion-added` disabled rather than face this wall; ADR-0144 retired
that detector on 0 true positives in 383 commits; ADR-0073 declined to add a sibling. This is the
same refusal with the measurement re-derived rather than inherited (rule 13).

The structural argument outranks the measurement anyway: correcting a wrong test and relaxing a
right one produce **byte-identical diffs**. No rule over a diff separates them, so any detector here
would report "an assertion changed", which is ordinary test maintenance. A signal that is always
wrong is one its readers learn to dismiss, which makes the `CLEAN` line mean less rather than more.

### D2 — R-02 is where the work is: the enforcement point was the one place that never said so

The limit was already stated in three places: `weakening-scan.sh`'s own header, the concept-to-code
Step 5 gate block (`WJ4`) and the `commit` skill's Step 1 block (`WJ5`).

It was **not** stated at CIRCUIT BREAKER B in `review-triage-fix/SKILL.md`, and `commit/SKILL.md`
says of its own call: *"`review-triage-fix`'s own circuit breaker B is the actual enforcement point;
this call is a heads-up at commit time, not a second gate."* The one place a reader is most likely
to mistake for coverage was the one place with no disclosure. Nor was it stated at
`autopilot-build/SKILL.md`'s breaker-B halt, which is the caller that runs with nobody present.

Both now carry it, and `WJ7`/`WJ8` pin them, each with a plant seen RED.

### D3 — the header records both measurements, forward

The 354-commit figure stays and the 383-commit figure is added beside it. `WJ3` still reads `0 of 2`
and `WJ3b` reads `0 of 6` and `383 commits`. Overwriting the older number would delete the evidence
that a larger corpus did not change the answer — which is the whole point of re-measuring (rule 14's
principle applied to a live file: record forward).

## Consequences

- **These assertions pin prose, deliberately** — rule 16, and the ADR says so at the site. A green
  `WJ7` is evidence the sentence is present, never evidence a model read it. The sentence is the
  deliverable here, not a proxy for one.
- `weakening-scan.sh` gains six comment lines and **no behaviour change**. The reporter contract is
  untouched: always exit 0, `CLEAN` on no finding, `grep -q '^WEAKENED'` at all four call sites
  (R-03).
- `weakening-wiring.test.sh` goes from 58 to 61 assertions and gains its first two plants; it had
  none, so WJ1–WJ6 were unplanted and remain so.
- **The blind spot is unchanged and will be rediscovered.** What changed is that a reader arriving
  at any of the four callers now finds it written down before they infer coverage from a silent
  gate.

## References

- ADR-0073 (the blind spot and the 354-commit measurement), ADR-0051 §D5 (the same wall, same
  script), ADR-0144 (`literal-assertion-added` retired on measurement), ADR-0047 (the four call
  sites), ADR-0048 §D7 (a signal always wrong makes CLEAN mean less), CLAUDE.md rules 13, 14, 16.
