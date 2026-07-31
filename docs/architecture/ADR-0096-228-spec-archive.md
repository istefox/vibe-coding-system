# ADR-0096 — The chain detected that root SPEC.md belonged to someone else, and overwrote it anyway

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #228 (found by the Phase 7 shakedown run at Step 1, which stopped rather than let it
  happen), #267 (filed by this work, measured on the way)
- **Related:** ADR-0023 (the `docs/specs/` convention), ADR-0086 (one extractor, one answer),
  ADR-0083 (fence contracts, and a boundary of its classifier), ADR-0085 (guard the denominator),
  ADR-0075 (the precedent for leaving historical records alone), ADR-0091 (a check that matches
  nothing looks exactly like a check that finds nothing)

## Context

`concept-to-code` Step 1's greenfield branch dispatches `interview-driver` with *"Save output to
`<project-root>/SPEC.md`"*. **Two different states reach that branch, and only one of them is "no
SPEC.md on disk."**

The other is a root `SPEC.md` belonging to a different topic. `gate0-detect.sh` reads the
`**Topic slug:**` marker, reports `spec_topic_match=false`, and flips the chain to greenfield. The
skill's own note describes what that means:

> `spec_topic_match=false` never reaches Gate 0 (gate0-detect.sh already flipped mode=greenfield, so
> the SPEC is disowned before routing).

"Disowned" is about **routing**. The file is still sitting at the path the dispatch writes to, and
Gate 4.0 (ADR-0071) would then commit the overwrite as part of the new chain's planning commit.

**The detection existed, was correct, fired, and protected nothing.** That is the interesting part:
this is not a missing check, it is a check wired to a decision that does not include the file.

## Two premises of the issue were wrong, and measuring changed the design

**1. The unarchived SPEC named in the issue was already archived.** #228 says #176's SPEC is the
only one missing from `docs/specs/`. It was archived by #229 in `162b019`. The live subject is
whatever the slot currently holds — which, when this was written, was #222's.

**2. `docs/specs/<slug>.spec.md` is not how the archive is named.** Measured over the real corpus:
**3 of 41** manifest topic slugs name an existing archive. Archive names come from the SPEC's own
title, while a topic slug is truncated to 40 characters —
`100-secrets-and-dependency-gate-content` against
`100-secrets-and-dependency-gate-content-scan.spec.md`.

So the obvious "is it already archived?" check — does `docs/specs/<slug>.spec.md` exist — **would
have missed 38 existing archives and written a duplicate beside each**, while looking correct and
reporting nothing. ADR-0091's shape, in a new place.

## Decision

### D1 — Archive, do not halt; detect by CONTENT, write by NAME

The check for "already archived" compares **content** against every file in `docs/specs/`, which is
what makes it idempotent against a corpus named by a convention it does not follow. The destination
is `docs/specs/<slug>.spec.md`, which is what makes it deterministic going forward. Nothing else
combines both.

Archiving rather than halting is the issue's own preference and the right default: it is mechanical,
reversible, and it is what the convention already says should have happened.

### D2 — It copies, it never moves

Two reasons and both are load-bearing. Nothing is deleted without a human saying so, and the
incoming interview overwrites the root slot anyway — so a move buys nothing and loses the file if
the interview then fails.

### D3 — The slug is an ARGUMENT, produced by `gate0-detect.sh`

`gate0-detect.sh` gains one additive output line, `spec_topic_slug=<marker|unknown>` — the slug the
**existing** SPEC claims, not the one the caller asked for. `spec-archive.sh` takes it as an
argument and does not re-derive it.

ADR-0086's criterion applies and says extract: two marker extractors that disagree would archive
under a name the detector never saw, or skip a SPEC the detector flagged. One extractor, one answer.

### D4 — A checker, with `3` distinct from `0`

`0` = ran (`NOSPEC` | `ALREADY <path>` | `ARCHIVED <path>`), `1` = refused (`COLLISION <path>`),
`3` = did not run.

The `3` is the point. Without it a caller cannot tell "no SPEC to archive" — the common, legitimate
case — from "this could not run at all", and treating the second as the first is how a guard comes
to protect nothing while looking green. Which is, one level up, exactly what #228 is.

`COLLISION` halts rather than overwrites: writing over an existing archive would be #228 reproduced
inside the directory that exists to prevent it.

## Verification

23 assertions in `spec-archive.test.sh`, plus a `Z1` floor. **The fix was executed on the real
repository, not only written**: running it archived the live root slot to
`docs/specs/222-vendor-deployed-only-skills.spec.md`, and a second run reported `ALREADY`.

`SA0`/`SA0b` re-derive both premises at run time — the corpus size, and the 3-of-41 by-name
insufficiency that `SA3` exists for. If that ratio ever stops holding, `SA0b` fails and says the
rationale needs re-measuring rather than letting `SA3` assert something about a vanished convention.

### Three assertions failed against correct code, and two of the reasons are worth keeping

**`SA3`/`SA4` failed on a fixture bug, not on the script.** `mk_root` incremented a counter and
returned `$TMP/r$N` — but `r=$(mk_root)` runs the function in a **subshell**, so the increment was
discarded and every call returned the same directory. The fixtures accumulated into each other.
Found by reading what the fixture had produced rather than what the assertion reported, which is
ADR-0090's plant lesson met on a fixture instead of a plant.

**`SA10`'s first draft was lexical and failed on a correct script**: `grep -iE 'topic[[:space:]]+slug'`
matched the comment **explaining why the slug is not re-derived**. Rule 12, third instance here — a
scan whose needle is a literal counts its own explanation. It is now behavioural: a SPEC whose marker
says `222-beta-topic`, archived under the argument `111-alpha-topic`, proves the argument wins. A
behavioural check cannot be satisfied by prose.

### The fence is declared AND executed, and ADR-0083's classifier cannot see it

The Step 1 block carries `<!-- fence-contract: c2c-step1-spec-archive -->`. `fence-contract-coverage.test.sh`
does **not** cover it: `fence_is_abort_capable` is lexical, looking for `exit 1`/`exit 2` or the word
"abort", while this fence ends `exit "$_rc"` and its abort belongs to the caller on rc 1 or 3.

So the fence aborts a chain in practice and is invisible to the population that would have required
it to be run. Section `SF` extracts and runs it anyway, against the archive, collision and
unsynced-machine cases. **A real boundary of ADR-0083's classifier, recorded rather than worked
around** — twelve declared contracts is a floor on that set, as ADR-0083 already said, and this is
the first measured example of what sits outside it.

## Consequences

- **Every greenfield chain now writes a file before the interview runs.** On a repository with no
  root `SPEC.md` it is a no-op; on one with a foreign SPEC it adds one archived file to the planning
  commit. Visible, committed by Gate 4.0, and never silent.
- **A `COLLISION` halts Step 1**, including on the unattended paths, where the remediation is
  recorded rather than prompted. That is the correct fail direction for a data-loss guard, and it is
  a new way for an unattended chain to stop.
- **The fence is a hard dependency on a deployed script**, failing closed (rc 3) until sync —
  ADR-0076's rule for a gate.
- **`spec_topic_slug` is additive output.** Any caller parsing `gate0-detect.sh` line by line is
  unaffected; a caller doing a positional read of the last line is not, and none does.
- **`artifacts.spec` still points at the root slot in all 41 manifests**, so 40 of them name a file
  holding a different chain's SPEC. Measured here, **not fixed here** — filed as #267. The archive
  is the precondition for fixing it, not the fix.
- Two slug forms now coexist in `docs/specs/`: 35 named from SPEC titles, and new ones named from
  the 40-character topic slug. Deterministic going forward, inconsistent with the past, and not
  worth renaming 35 historical files over.
