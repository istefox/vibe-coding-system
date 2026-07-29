# ADR-0075 — A field that is absent, invalid, or unreadable: three states one comparison could not tell apart

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #123
- **Extends:** ADR-0016 (which added `hook_verified` as an additive field), ADR-0020 (autopilot-build
  pre-flight), ADR-0030 §2.3/§3.3 (which wrote nightly check 6 in its current shape)
- **Reported as:** found while arming the agentic-spec roadmap on 2026-07-26; unblocked by
  backfilling the two manifests, with the check itself left as the real defect.

## Context

`nightly-autopilot` Phase 0 check 6 iterates **every** manifest in `docs/manifests/` and aborts the
whole run if any has a `hook_verified` that is neither `true` nor `false`:

```
✗ hook_verified: <m> has hook_verified=None (must be true/false).
  Manifest is corrupted or was hand-edited; fix or re-init.
```

Two manifests hit it — `2026-05-23-clean-public-repo-anonymize` and
`2026-05-29-dynamic-workflows-step5`. Neither is corrupted. Both are schema 1.1,
`current_step: completed`, and simply **predate the field**, which ADR-0016 added to
`manifest-init.sh` afterwards. Two long-completed chains, unrelated to the roadmap being launched,
would have blocked it entirely, and the diagnostic would have sent the operator looking for damage
that was not there.

Every repository accumulates these. The abort is roadmap-wide and the message is actively
misleading, which is the combination that makes it a latent landmine rather than an inconvenience.

## Decision

### D1 — Four states, distinguished, because `m.get()` cannot tell them apart

`m.get('hook_verified')` returns `None` for a field that is **absent** and for one explicitly set to
null, and the shell one-liner produced an **empty string** when the file could not be parsed at all
(`2>/dev/null` swallowing the traceback). One comparison against `True`/`False` therefore reported
three different situations with one sentence, and that sentence named the least likely of them.

The check now reads a discriminated token — `VALUE|…`, `ABSENT|<current_step>`, `UNREADABLE` — and
branches on it:

| state | verdict | why |
| --- | --- | --- |
| `true` / `false` | pass | the two valid values |
| absent, `current_step: completed` | **pass**, with a note | a completed chain's dispatch mode cannot affect a future run |
| absent, anything else | abort | a chain still in flight whose dispatch mode is unknown |
| present, not a boolean | abort, naming the value | the corruption this check was written for |
| unparseable / no PyYAML | abort, as **did not run** | not the same as finding a bad value |

The fourth row is the one the issue asked for. The fifth is the distinction this repository has now
made in `secret-scan.sh` (exit 3), `spec-coverage.sh` and `plan-tasks.sh`: **a check that reports
nothing must be distinguishable from a check that found nothing.** Reporting an unread file as
having a bad value is the same error one level down from the one being fixed.

### D2 — Leniency is bounded by `current_step`, and the boundary is the point

Absence is tolerated **only** on `completed`. It is not a general "missing means false" rule: on a
chain in flight, nobody knows which dispatch path it took, and guessing is exactly what the safe
default exists to avoid. `C6` (the pre-existing assertion, fixture and expectation unchanged) pins
the in-flight abort; `C7` pins the completed pass; `C12` pins that a tolerated manifest does not
mask an invalid neighbour later in the loop.

### D3 — The loop stays roadmap-wide (the issue's third checkbox, declined with reasons)

Issue #123 raised narrowing the check to the manifests of *pending* roadmap features. Rejected.

It needs a PROJECT.md-feature → manifest mapping, and this repository has already had to fix that
mapping twice for suffix collisions (ADR-0030 §2.2, three call sites, date-anchored glob **and**
`topic:` field equality). A wrong mapping there does not fail loudly — it silently skips a manifest
that matters, which is a worse failure than the one being fixed. The absent-on-completed default
removes the landmine without introducing a lookup that can be wrong.

### D4 — The sibling call site had the MIRROR defect, and it is fixed in the same pass

`autopilot-build` check 7 reads the same field with the same one-liner, one skill over. It reads a
single manifest — the one about to be built, so in flight by definition — and aborting on absence is
correct there. But its test was

```sh
[ "$hv" = "None" ] || [ -z "$hv" ] && { …; exit 1; }
```

so **anything that is neither passes**. `hook_verified: maybe` sailed through and the run then
branched on it. Nightly check 6 aborted on too much; autopilot-build check 7 aborted on too little.
Same field, same one-liner, opposite failure — which is why the audit had to look at both rather
than at the one named in the title.

Corrected to assert the two **valid** values and reject everything else, which is the form that
cannot rot as the invalid set grows. Pinned by section D of `scope-guards.test.sh`, `D3` and `D4`
seen RED.

### D5 — The related `project_root` observation: recorded, not fixed, and the count corrected

Issue #123 noted that `2026-05-23-clean-public-repo-anonymize.manifest.yml` carries
`project_root: /Users/stefanoferri/Developer/vibe-coding-system`, a path that does not exist on this
machine, so `manifest-validate.sh` fails invariant 4 on it.

**It is five manifests, not one** — the same five that predate the current machine's path. Verified
by sweeping the corpus. Nothing in the nightly path, and nothing anywhere, iterates `project_root`
across manifests (checked: no glob-based consumer exists), so it blocks nothing today.

Left unfixed deliberately. Rewriting five completed historical records to point at a path they were
never created under is falsifying the record for no consumer. Anyone who later builds something that
*does* iterate `project_root` across manifests will meet these five, and this paragraph is what
tells them the paths are historical rather than corrupt.

## Alternatives considered

### A — Backfill `hook_verified: false` into every pre-schema manifest and leave the check alone

Rejected, and it is what was done on 2026-07-26 to unblock the roadmap. It fixes this machine's
corpus and nothing else: the next repository, and the next manifest written before a future additive
field, hits the identical abort. The issue exists because the backfill was a workaround.

### B — Treat absence as `false` unconditionally

Rejected per §D2. It would silently guess the dispatch mode of a chain still running, which is the
one case where the value actually matters.

### C — Drop the check

Rejected. The corruption case is real and cheap to catch; `C8` keeps it caught even on a completed
manifest, because a value someone wrote is different in kind from a value nobody wrote.

## Consequences

### Positive

- A repository that accumulates pre-schema manifests no longer has a roadmap-wide abort waiting in
  it, and the operator who does hit an abort is told which of four things happened.
- An unreadable manifest, and a missing PyYAML, stop being reported as bad data.
- `autopilot-build` no longer accepts a garbage `hook_verified` and branches on it.

### Negative

- **Check 6 now passes on strictly more inputs**, and one of them is a real absence of information.
  It is bounded to completed chains, where the field cannot affect anything, but it is a guard
  relaxing.
- The lenient branch prints a `note:` per tolerated manifest. On a corpus with many pre-schema
  manifests that is several lines of pre-flight output nobody needs to act on.
- Five manifests still fail `manifest-validate.sh` invariant 4 (§D5). Known, unfixed, and now
  written down with the right count.
- `C8`, `C9`, `C12`, `C13` and `D1`/`D2` pass before and after. Forward guards, not fix evidence —
  `C7`, `C10`, `C11`, `D3`, `D4` are the five that were RED.

### Neutral

- No script changes: both fixes are inside `SKILL.md` bash fences, extracted and executed by the
  harness (rule 11 — a prose code block nobody has executed is unverified code).
- No new test file, no new `PAIRS` entry (both skills already have theirs), no CI registry change.
- No manifest field, no schema bump. Pre-ADR-0075 manifests are the input this exists to accept.
- Inert until sync.

## References

- Issue #123, including the third checkbox declined in §D3 and the related note corrected in §D5
- `docs/architecture/ADR-0030-34-scope-guards.md` §2.3/§3.3 — where check 6 was written, and §2.2,
  the manifest-lookup fragility §D3 declines to depend on
- `docs/architecture/ADR-0016-dynamic-workflows-step5.md` — the additive field whose lateness is the
  root cause
- `staging/plugin/scripts/tests/scope-guards.test.sh` sections C7–C13 and D
