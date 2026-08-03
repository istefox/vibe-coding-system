# ADR-0123 — Phase 2 could not disarm the run it owns

- **Issue:** none (found by running the chain, 2026-08-03)
- **Status:** Accepted
- **Date:** 2026-08-03
- **Amends in part:** ADR-0112 §R-04 (the ownership refusal, and only its scope)
- **Related:** ADR-0109 (#319, the producer/consumer seam), ADR-0076 (a fact about the INPUT is
  not a fact about the ENVIRONMENT), ADR-0086 (when to extract), ADR-0108 (plant registry)

---

## Context

ADR-0112 gave a stale `.claude/nightly-state/active` marker an exit. `nightly-disarm.sh` refuses
when the marker's recorded `session_id` equals `CLAUDE_CODE_SESSION_ID`, because a session cannot
prove that a run it does not own is dead. That is R-04, and it is right.

`nightly-autopilot` Phase 2 then cleared the marker **by calling that script**, from the session
that armed it. So the primary path ran into the recovery path's refusal, on every completed run.

The two files pointed at each other, in as many words:

- `nightly-disarm.sh` — *"A run does not disarm itself. If the run really is over, finish it
  (**Phase 2 clears the marker**) or run this from a different session."*
- `nightly-autopilot/SKILL.md` §4 — Phase 2 clears the marker by running `nightly-disarm.sh`.

The consequence is the exact failure ADR-0112 was written to remove — a marker outliving its run,
`nightly-guard` live in the human's own later sessions — arriving through the **normal** path
instead of through a crash. It is the shape of #319 (ADR-0109): two halves each correct about
their own job, nobody owning the seam, and the remedy naming a path that refuses.

**The SKILL stated the guarantee inverted**, which is why it survived review:

> "It refuses (exit 1) if the marker was armed by a *different* session than the one running it.
> On this path that cannot happen — this is the session that armed it — so a refusal here means
> the marker was rewritten mid-run"

Being the arming session **is** the refusal condition, not its exclusion. A refusal there meant
nothing had been rewritten; it meant the ordinary case, every time.

**Live evidence:** the guard on this repository was armed by the session that found this, and
could not be cleared from it.

## Decision

### D1 — Two modes, exact mirrors, one legitimate caller each

`nightly-disarm.sh` gains `--completing`.

| invocation | legitimate caller | ownership rule |
|---|---|---|
| `nightly-disarm.sh <root>` | a human recovering a stale marker | **owner refused** (unchanged) |
| `nightly-disarm.sh --completing <root>` | `nightly-autopilot` Phase 2 | **foreign refused** (new) |

R-04's content is preserved rather than weakened: *no session disarms on the strength of a claim
it cannot back*. A foreign session cannot prove the owner is dead, which is why the bare form
refuses the owner and why ADR-0112's "no liveness oracle" paragraph stands verbatim. The owning
session at Phase 2 backs its claim with identity — it **is** the run, and it is ending. That was
always the one caller with certainty, and it was the one being refused.

The mirror is what makes this a scoped grant instead of a bypass. A flag that merely skipped the
ownership check would let any session clear any marker by adding a word. `CP6` pins the bare
form's refusal for that reason and passes before and after: it is a forward guard, not fix
evidence.

### D2 — Two leniencies, both copied from the recovery path, neither invented

- **An ownerless (legacy) marker completes.** ADR-0112 already decided ABSENT is not FOREIGN and
  not CORRUPT (ADR-0076). Refusing here would strand a run whose marker predates #321.
- **Owner set, `CLAUDE_CODE_SESSION_ID` unset → proceed with a note.** Ownership cannot be
  established either way, and failing closed there is this ADR's own bug in a narrower case: a run
  that cannot finish clearing up after itself. The note says ownership could not be established
  rather than claiming the caller is the owner.

### D3 — An unknown option is named as one

`--bogus` used to be read as the project root and exited 2 because no such directory exists — the
right code for the wrong cause. `CP5` therefore asserts the **wording**, not the exit code, and its
plant removes the wording while keeping the code. An assertion that cannot distinguish the two
reasons pins nothing (rule 8's family).

## Consequences

- **Enforcement on the script side, instruction on the SKILL side.** The mirror is code and cannot
  be talked out of; that Phase 2 passes the flag is prose in a `SKILL.md` a model is asked to
  follow, pinned by `CP7` and nothing else. Same split as ADR-0041/ADR-0045.
- **Inert until sync.** `PAIRS` already carries `plugin/scripts/nightly-disarm.sh`, so a
  `sync-to-claude.sh --apply` deploys both halves; until then Phase 2 on the deployed copy still
  calls the bare form and is still refused. The failure direction is the current one, not a worse
  one.
- **The refusal text changed on both paths**, so anyone with the old sentence memorised will read
  a different message. The bare form no longer points at Phase 2 as the remedy, because that
  pointer was the circle.
- **This does not detect a stale marker proactively.** ADR-0112's residual limit is untouched: a
  human still has to be blocked once to learn the recovery command exists. What changes is that a
  *completed* run no longer produces one.
- **Editing the script silently invalidated two pre-existing plants, and that is worth recording as
  a habit rather than an incident.** `O5`'s needle quoted the usage string this change reworded, and
  `S4`'s quoted the Phase 2 invocation line this change edited. Both fell to **zero** matches, which
  `plant-check.sh` reports as `PC2 malformed` — correctly, and it was missed on the first read
  because the run was piped through a `grep` that did not match the detail lines. **The
  registry caught it; my filter hid it.** The rule: after editing any file a plant targets, re-count
  every needle against it before believing a green summary. `O5`'s replacement needle now targets a
  message that exists only in the branch it asserts about, rather than a usage string printed from
  two places.
- **The recovery branch is a nested `if`, not an `elif`, and that is deliberate.** As an `elif` it
  still matched `O2`'s needle — because `elif [ -n` contains `if [ -n` as a substring — so the plant
  kept firing by coincidence rather than by construction. Mode dispatch and ownership rule are two
  questions and are now two constructs.
- **`CP2`'s red evidence is partly circumstantial and is recorded as such.** Before the change,
  `--completing` was read as the project root, so all of `CP1`–`CP5` failed at argument parsing
  rather than at the branch each one is about. The declared plants are what pin the branches:
  `CP1` and `CP2` share a needle and carry different replacements precisely so each isolates its
  own half of the condition.

## Alternatives rejected

- **Move the disarm out of Phase 2 into a separate session.** There is no separate session at the
  end of an overnight run; that is the whole premise.
- **Drop R-04 and let any session disarm.** It would fix Phase 2 by removing the property that
  makes the recovery path honest, and ADR-0112 §"no liveness oracle" is the reason it exists.
- **Have Phase 2 `rm -f` the state directly.** That is what the step used to be, and ADR-0112
  removed it because clearing only `active` leaves `build-status` and `needs-human` blocking.
  `SKILL.md` still carries the "Do not replace this with `rm -f`" sentence, untouched.
