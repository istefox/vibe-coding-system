# ADR-0109 — Two entry points that refused each other, and the command that did not exist

- **Status:** Accepted
- **Date:** 2026-08-01
- **Issues:** #319
- **Related:** ADR-0076 (read a manifest field through the helper, never a bare `m.get()`),
  ADR-0095 (the `step_6_review` gap it disclosed, and the one it did not), ADR-0086 (derive rather
  than copy when two answers would be a defect), ADR-0083 (the fence contract), ADR-0078 (build a
  fixture by patching a real manifest), ADR-0092 (a value domain measured against its producers)

## Context

The 2026-07-31 unattended launch left a manifest at `step_0_init` and nothing could touch it. The
chain's own error said *use resume*. Resume said *resume not necessary, continue in current
session*. Both are enforced by code, not by prose.

Measuring the claim before designing — this repository's standing rule, which changed the design on
7 of 12 Phase 8 issues — found the issue **true and under-stated in four ways**.

### What was measured, 2026-08-01, CC 2.1.220

- **M1 — Form A's guard is on FILE EXISTENCE, never on state.** `manifest-init.sh`'s *Refuse
  double-init for same slug same day* guard is `[ -f "$manifest" ]`. No state transition can ever
  unblock it, and Form C (abort) sets `status` while preserving the file, so it does not either.
  The issue framed this as "a manifest sitting at `step_0_init`"; the truth is broader and simpler.
- **M2 — Form B resolved 2 of 13 standard states**: `ready_for_implementation` and
  `step_5_implementation`. Everything else was refused or unlisted.
- **M3 — three states matched no branch at all**: `step_4_session_boundary`, `step_6_review`,
  `step_7_commit`. ADR-0095 disclosed only the second.
- **M4 — the boundary state is the one that mattered, and it was disclosed nowhere.** Gate 4's own
  "Abort chain" message tells the operator to resume from it, and `project-conductor` Step 3 and
  Step 5 branch B both act on it by invoking Form B. A grep of `CLAUDE.md` and of ADR-0095 finds no
  mention. The conductor's primary resume path targeted a state the table could not serve.
- **M5 — Express and Hybrid can never resume at all** (*Resume semantics*), so any interrupted
  express/hybrid chain was same-day wedged with no recovery path whatsoever.
- **M6 — a COMPLETED chain was deadlocked too**: Form A says *use resume*, Form B says *chain
  terminated, create a new manifest* — which Form A had just refused.

**The sentence the whole issue reduces to:** Form B's remedy named a command that does not exist.
The in-session entry point is Form A, and Form A refused on file existence. Neither half was wrong
about its own job; nothing owned the seam between them.

**M7, a correction to the issue's own live instance.** The orphan's path is date-stamped, so it
stopped blocking at midnight — a run today writes a different path. What remains is a stale
duplicate the conductor's `ls -t | head -1` shadows. The structural defect is unchanged; the
instance had already expired when the fix was written, and R-03 is carried by the mechanism rather
than by the file's continued existence.

## Decision

### D1 — one classifier, consumed by both entry points

`manifest-entry-state.sh` reports which entry point can reach an existing manifest. It is a
**CHECKER**: the caller branches on the exit code, then on the token. `weakening-scan.sh`, invoked
a few lines away at the same Step 5 checkpoint, is a **REPORTER** that always exits 0 and signals
`CLEAN` on stdout. Both idioms now appear within a screen of each other in `SKILL.md`, so the
header says which this is and warns against copying one block's branching into the other.

Nine tokens: `NONE`, `ADOPTABLE`, `BOUNDARY`, `RESUMABLE`, `LATE`, `UNRESUMABLE`, `TERMINAL`,
`UNKNOWN`, `UNREADABLE`. Scope decision taken with the operator: route the **whole** table, not
only the pre-Step-4 states the issue names. A classifier that routes 8 of 13 leaves the same defect
in the block it has just rewritten.

### D2 — "no file" and "unparseable" are TOKENS, not exit 3

The first draft folded both into exit 3 as *could not run*. **That is #319 reproduced one level
down**: the caller could no longer distinguish "nothing is there, go ahead and create one" — the
common, legitimate, overwhelmingly most frequent case — from "this machine has no PyYAML". Absence
and corruption are facts about the **input**; exit 3 is a fact about the **environment**. ADR-0076
draws that line for `manifest-field-state.sh`, and it is drawn again here for the same reason.

This is a deliberate departure from the approved plan, made during implementation and recorded
rather than quietly applied.

### D3 — the state enum is DERIVED from `manifest-validate.sh`, not copied

ADR-0086's criterion: extract only when two copies giving different answers would be a **defect**.
Here they would — the day either file gains a state, the copy answers `UNKNOWN` on a perfectly
valid manifest. The derivation is count-guarded at `>= 25`: a validator refactor that stops matching
yields exit 3, never a silently empty known-set that would read as *every state is unknown*
(ADR-0085's denominator lesson).

**Validity is judged on `current_step` alone, not by running `manifest-validate.sh`.** That script
carries 28 invariants and a manifest can fail one for a reason entirely unrelated to routing —
ADR-0078's dead `project_root` is the live example, on five of this repository's own manifests.
Refusing to route an adoptable chain over an unrelated invariant would be a stricter defect than
the one being fixed.

### D4 — `status` is read as well as `current_step`, and that is the Form C case

Form C sets `status: aborted` and leaves `current_step` exactly where it was. A classifier reading
only `current_step` would route an aborted `step_0_init` chain as `ADOPTABLE` and quietly restart a
chain a human had deliberately stopped. `MES8` is that assertion and it is the negative twin of
`MES2` — the same fixture, one field apart, opposite verdicts.

### D5 — `manifest-init.sh`'s exit-2 contract is deliberately untouched (R-04)

It stops being the *decision* and becomes the *backstop*. Form A step 4b classifies first, so init
is reached only when there is nothing there — **or** when the date rolls between the check and the
call, which is the one case a file-existence guard still has to catch on its own. Removing it would
delete the only protection against that race and make "manifest already exists" indistinguishable
from "the classifier did not run".

### D6 — the unattended policy is deferred to #324, at the call site

What a `nightly` run does with a non-`NONE` answer — mark the feature `[~]` and continue, or halt
the roadmap — is #324's subject. The sentence is written into the Form A block itself, because
without it the two fixes would invent that policy separately in the same block. `MESB5` pins it.

### D7 — the classifier never writes

No transition, no overwrite, no deletion, no temp file in the project tree. R-02 is held by
construction rather than by care, and `MESW` asserts the manifest and its directory come back
byte-identical anyway.

## Known consequences, recorded rather than fixed

- **The manifest corpus cannot validate this value domain, and the sweep was run to find that
  out.** ADR-0092 derives a domain by comparing what producers write against what the docs claim.
  Here the producers are transient chain states: classifying all 42 manifests on disk yields **41
  `TERMINAL` and 1 `ADOPTABLE`**, because a stored corpus is terminal by nature. Six tokens are
  justified by a named state in the validator's enum plus a route in `SKILL.md`, and pinned by
  fixtures — never by a corpus frequency. Anyone re-running that sweep expecting coverage evidence
  will find none.
- **R-03 is split across two assertions on purpose, and the reason generalises.** `MES2` pins the
  orphan's recorded **shape** against a fixture; `MES2b` reads the real file and asserts only that
  the mechanism **reaches** it — `ADOPTABLE` before Form C, `TERMINAL` after. An assertion that
  uses a mutable, untracked file as its oracle passes today and fails tomorrow for a *correct*
  reason, and the next reader cannot tell that failure from a regression. A test coupled to
  housekeeping is worse than no test.
- **The routing is an instruction, not an enforcement.** The classifier is a script and its exit
  codes are real; the block that reads it is prose in a `SKILL.md` a model is asked to follow. The
  harness pins that the instruction exists and that the fence it contains executes correctly.
  Nothing pins that a model obeys it.
- **`ADOPTABLE` means "this session may continue it", not "this session knows how".** Adoption
  reads the manifest and resumes at the step it names; how faithfully that happens is the model's
  judgement, exactly as every other step of the chain is.
- **Inert until sync.** Both call sites invoke `~/.claude/…`, so without the `PAIRS` entry the
  fence exits 127 and the DID-NOT-RUN branch fires on every chain start.
  `pairs-completeness.test.sh` cannot see a skill `scripts/` file (ADR-0043), so `MES0b` is the
  only guard and it asserts the entry directly.
- **The date race survives by design.** A chain started seconds before midnight still meets
  `manifest-init.sh`'s exit 2 with no classifier having seen it. That is D5's whole justification,
  and it is a narrower window than the one being closed, not a closed one.
- `MES0`, `MES1`, `MESX4` and `MESW` pass before and after — forward guards, not fix evidence. The
  five that were seen RED under `plant-check.sh` are `MES2`, `MES4`, `MES8`, `MESF2`, `MESB1`.
