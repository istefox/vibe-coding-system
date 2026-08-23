# ADR-0167 — disarm clears guard state; the LAUNCH decides whether a bound is spent

- **Topic slug:** `400-autopilot-disarm-scope-unbounded`
- **Issue:** #400 (from `TODO.md` `VCS-018`, filed 2026-08-11)
- **SPEC:** `SPEC.md` (R-01 … R-08), archived at completion to `docs/specs/`
- **Plan:** `docs/superpowers/plans/2026-08-23-400-autopilot-disarm-scope-unbounded.md`
- **Extends:** ADR-0112 (the transient-set whole-clear and the two disarm modes), ADR-0129 §D1/§D2/
  §D4/§D5 (the `scope` file, `conductor-scope-gate`, the delivered counter), ADR-0127 §D4 (the
  `published` ledger), ADR-0132 (logic out of a fence and into a script), ADR-0076 (ABSENT /
  INVALID / UNREADABLE are three states).
- **Supersedes in part:** ADR-0112's "disarm clears everything in `.claude/autopilot-state/`" — for
  `scope` and `published` only. `active`, `build-status`, `rtf-blocker`, `started-at` and
  `.claude/needs-human` are untouched by this ADR.
- **Supersedes in part:** ADR-0129 §D1's lifecycle for `scope` and ADR-0127 §D4's lifecycle for
  `published`. Their *format*, *writer* and *readers* are unchanged; only *what deletes them*
  moves.

## Status

Accepted — 2026-08-23.

**Numbering.** `main` at `550e188` carries ADR-0166 as the highest number, and ADR-0165 exists on
`feat/470-chain-never-regenerates-xcode` (merged into this branch's history). This ADR is
**0167**. It adds no twenty-first `CLAUDE.md` rule.

## Context

`autopilot-disarm.sh` treats `<root>/.claude/autopilot-state/` as one undifferentiated transient
set and removes every file it names in a single loop:

```text
active   build-status   rtf-blocker   scope   published   started-at   ../needs-human
```

ADR-0112 wrote that loop for a specific, correct reason: the marker is only one of four ways to stay
blocked, so a disarm that clears only `active` looks like it worked while the human is still stopped
by a stale `build-status` reading `RED`, a stale `rtf-blocker`, or a stale `.claude/needs-human`.
Every file in that list *was* a guard condition when the list was written.

`scope` was added to the directory afterwards, by ADR-0129 §D1, and it is not a guard condition. It
is the run's **configuration**: the resolved `--features`/`--only` bound, written once by `autopilot`
Phase 0 check 9 and read at every re-invocation by `conductor-scope-gate`. `published` was added
before it, by ADR-0127 §D4, and it is the run's **progress**: one line per feature that shipped, and
the `delivered` half of the exhaustion comparison `conductor-scope-gate` makes against `features`.
Neither was revisited against ADR-0112's rule when it landed in ADR-0112's directory.

The consequence is recorded in `TODO.md` `VCS-018`:

> a bare `/skill autopilot` after a disarm runs UNBOUNDED, and nothing says the bound is gone. Same
> shape as the defect ADR-0112 closed, pointed the other way — there a leftover file blocked, here a
> removed file silently permits.

Nothing announces it. Not the disarm output (it prints `removed:` for `scope` in a list of six other
removals, indistinguishable from the guard files), not the RUNBOOK's "Aborting a run" section (it
says "disarm the guard" and nothing about the bound), not Phase S at relaunch (it reports
`source=none`, which is literally true and reads as "you never asked for a bound").

### Measurements, re-derived for this ADR rather than carried from the issue (rule 13)

Measured 2026-08-23 on this branch.

| Fact | Value |
|---|---|
| Files named in `autopilot-disarm.sh`'s clear loop | 7 |
| Of those, guard conditions | 4 (`active`, `build-status`, `rtf-blocker`, `needs-human`) |
| Of those, configuration/progress | 2 (`scope`, `published`) |
| Of those, debris | 1 (`started-at`, an invented path — ADR-0112's own header) |
| Readers of `<root>/.claude/autopilot-state/scope` in the codebase | **2** |
| Readers of `<root>/.claude/autopilot-state/published` in the codebase | **2** |
| Writers of `scope` | 1 (`autopilot/SKILL.md` check 9, fence `autopilot-scope-resolve`) |
| Writers of `published` | 1 (`project-conductor/SKILL.md` Step 5 publish path) |
| Existing assertions pinning the OLD behaviour | **3** (`KB5`, `D1`, `D2`) |
| Existing plant declarations whose needle this change destroys | **2** (`KB5`, `KB6`) |

### R-07 — the complete consumer audit

Derived by `grep -rn "autopilot-state/scope\|autopilot-state/published"` across the repo, excluding
`.git`, then classifying every hit. This is the inventory R-07 asks for; **it is four consumers, not
the two the issue guessed.**

| # | Consumer | File / anchor | Reads | Verdict |
|---|---|---|---|---|
| C1 | `autopilot` Phase 0 check 9, fence `autopilot-scope-resolve` | `staging/plugin/skills/autopilot/SKILL.md`, `_sf="$_root/.claude/autopilot-state/scope"` | writes `scope` | **IN SCOPE.** Gains the reuse/spent branch and the `published` reset. §D3. |
| C2 | `project-conductor` Step 2, fence `conductor-scope-gate` | `staging/plugin/skills/project-conductor/SKILL.md`, `fence-contract: conductor-scope-gate` | reads `scope` **and** `published` | **CONFIRMED CORRECT, NOT CHANGED.** §D5. Its `NONE` / `DID-NOT-RUN` split already distinguishes "no bound" from "could not read one" (ADR-0076), which is exactly the distinction this feature needs downstream. |
| C3 | `project-conductor` Step 2, fence `conductor-published-skip` | same file, `_led="$_root/.claude/autopilot-state/published"` | reads `published` | **CONFIRMED CORRECT, NOT CHANGED**, and its stale-ledger exposure is *closed* by §D4 rather than opened — see §D4's third paragraph. |
| C4 | `project-conductor` Step 5 publish path | same file, `printf '%s\n' "<topic-slug>" >> …/published` | appends `published` | **OUT OF SCOPE.** A writer, not a reader; its append semantics are untouched. |

Two further hits are **not** consumers and are listed so the audit's denominator is visible
(rule 7): `autopilot/SKILL.md` §4 Phase 2 calls `autopilot-disarm.sh --completing` (it names the
script, never the files), and `autopilot-guard.sh` names neither file at all — the guard keys off
`active`, `build-status`, `rtf-blocker` and `needs-human` only, which is why R-03 is cheap to
honour.

### The thing the issue did not see: preserving `scope` alone breaks the bound the other way

`conductor-scope-gate` computes exhaustion as `lines(published) >= features`. The two files are two
halves of one comparison.

- Preserve `scope`, clear `published`: a run bounded at 5 that was interrupted after 3 relaunches
  with `delivered = 0`, and delivers **5 more**. The bound is not restored, it is doubled.
- Preserve both, clear neither, ever: a run bounded at 5 that **completed** all 5 leaves
  `features=5` and 5 lines in `published`. The next bare `/skill autopilot` reuses that bound,
  `conductor-scope-gate` reports `EXHAUSTED — 5/5` on the first candidate, and the run ends having
  done **nothing**. Every night after a completed bounded run is a silent no-op.

So "just stop deleting them" is not a fix on its own. Something has to decide whether a surviving
bound is *live* or *spent*, and `autopilot-disarm.sh` is structurally the one place that cannot
know: `--completing` is issued both by Phase 2 on a genuinely finished roadmap **and** by a human
pausing from the owning session (the bare recovery form refuses the owner, so `--completing` is the
only form that works there — this is precisely what happened in `TODO.md` `VCS-020`). The disarm
sees one call and two meanings.

## Decision

**Disarm clears guard state. The next launch decides whether a surviving bound is live or spent.**

### D1 — `scope` and `published` leave `autopilot-disarm.sh`'s clear loop (R-02)

Both modes, `--completing` and the bare recovery form, stop deleting these two files. The loop keeps
`active`, `build-status`, `rtf-blocker`, `started-at` and `.claude/needs-human`, in that order, with
the same `rm -f`, the same per-file `removed:` line and the same exit-3 on a failed removal (R-03).

The rule that replaces ADR-0112's is stated in one line, at the loop, and it is the rule ADR-0112
would have written had `scope` existed then:

> This loop clears **guard conditions** — the files whose mere presence stops a publish. It does not
> clear the run's configuration or its progress, because those two are not conditions and disarm
> cannot tell a paused run from a finished one.

### D2 — the disarm reports what it preserved, and reading a preserved file can never fail it (R-08)

The output grows a `preserved:` block, printed in **both** terminal branches — after `DISARM:
CLEARED` and after `DISARM: NOTHING-ARMED` — because a disarm that found no guard state still needs
to say the bound survived it:

```text
  preserved: .claude/autopilot-state/scope (features=3, only=2 rows)
  preserved: .claude/autopilot-state/published (2 delivered)
  Relaunch with no --features/--only to reuse this bound; pass either to replace it.
```

`preserved:` is a **new line prefix, never `removed:`**. `removed:` after this change names guard
files only, and the harness asserts that in both directions (rule 8): every guard file present is
named `removed:`, and neither preserved path ever appears on a `removed:` line.

The bound summary is best-effort. An unreadable or malformed `scope` degrades to
`preserved: <path> (bound unreadable)` and the disarm still exits 0. **A disarm must not fail
because it could not read a file it is not touching** — the existing exit-3 paths stay bound to what
disarm actually does (the state directory it must traverse, a removal it must complete).

### D3 — precedence at relaunch: explicit argument → preserved bound → marker → unbounded (R-01, R-05)

Phase S (`autopilot-scope-args`) gains one branch, inserted between the argument branch and the
marker branch:

1. **Any `--features`/`--only` on the command line** → `source=arguments`, unchanged. Check 9
   resolves it and writes `scope` with a truncating `>` redirect, so an explicit argument
   **overwrites**; it never merges and never appends (R-05). This is already true by construction
   today and this feature pins it rather than building it.
2. **Otherwise, a preserved `scope` reported `REUSABLE`** → `source=preserved`. The bound is the
   file's own already-resolved contents. Check 9 does **not** re-resolve and does **not** rewrite it.
3. **Otherwise, the `.claude/autopilot.yml` `scope:` block** → `source=marker`, unchanged.
4. **Otherwise** → `source=none`, unbounded, unchanged.

Two consequences are deliberate and stated rather than discovered later.

**The preserved file beats the marker, and only when `source=arguments` is recorded in it.** The
preserved file is only ever `REUSABLE` when it records `source=arguments`, so it can only outrank
the marker in the one case where they can disagree: the operator overrode the marker on the command
line and is now continuing that run. When the preserved file records `source=marker` the marker is
re-read fresh, which is both identical in the ordinary case and *newer* if the human edited the YAML
between the pause and the relaunch. When it records `source=none` there is nothing to reuse.

**Check 9 must not re-resolve a preserved bound.** The file's `only=` lines hold the roadmap row's
**exact text** (ADR-0129 §D2), not the comma-separated tokens the operator typed. Feeding them back
through check 9's token resolver — which matches `(issue #N)` or a 40-character slug — would resolve
nothing and abort the launch. Reuse means *use the file as it stands*.

### D4 — `published` is reset by the LAUNCH, exactly when the launch writes a fresh `scope`

One line of policy, and it is symmetric:

> Check 9 removes `published` **if and only if** it writes a fresh `scope` file.

A new bound is a new run, so its delivered count starts at zero. A reused bound is the same run
continuing, so its delivered count continues. `--dry-run` writes nothing and therefore removes
nothing.

This is what makes preservation safe in both failure directions from the Context section: an
interrupted bounded run resumes with `3/5` and delivers 2, not 5; a completed bounded run's next
launch writes a fresh `scope` (nothing was `REUSABLE`, because §D6 classifies a satisfied bound as
`SPENT`) and clears the 5-line ledger with it, so `EXHAUSTED` cannot carry into a night that has not
started.

It also *closes* a pre-existing hole rather than opening one, which is the answer to C3's exposure.
Today `published` is deleted only by disarm, so a run that crashes and is never disarmed already
carries its ledger into the next launch, where `conductor-published-skip` skips every slug in it.
After this change the launch clears it unconditionally whenever it is not continuing that exact run,
so the stale-ledger window closes at the next launch instead of depending on a human remembering to
disarm.

### D5 — `conductor-scope-gate` and `conductor-published-skip` are confirmed correct and NOT modified (R-07)

Both already read the file the way this feature needs: `NONE` when it is absent (unbounded, exit 0),
`DID-NOT-RUN` when it is present and unreadable (exit 3), never collapsing the two. Their fences,
their exit vocabularies and their nine `CG` plants are untouched.

Their `DID-NOT-RUN` exit 3 **stays a halt**, and this does not conflict with R-06. R-06 governs the
*launch-time* read, where "I cannot read the bound" is indistinguishable from "there is no bound"
and the safe degradation is an announced unbounded run. `conductor-scope-gate` runs *mid-run*,
against a file the launch wrote minutes earlier; there, unreadability is an environment fault during
a run the operator already bounded, and continuing unbounded would blow through the bound they set.
Two call sites, opposite policies on the same state, both right — CLAUDE.md rule 11's case, and it
is why §D6 makes the launch path *remove* a file it could not read rather than leave it for this
gate to trip over.

### D6 — the read is one script, `scope-file-read.sh`, and it is a REPORTER (R-01, R-06)

New file: `staging/plugin/skills/autopilot/scripts/scope-file-read.sh`, deployed to
`skills/autopilot/scripts/scope-file-read.sh`. It follows the `scope-args-parse.sh` precedent
(ADR-0132 §D1): the logic lives in a file because a fence body is rendered — with this skill's own
invocation arguments substituted into it — before the model executes it, and because a file can be
executed directly by a harness.

**It is a REPORTER. It always exits 0** on any state of the file it was asked about, and signals
through stdout alone. It exits 2 only on bad invocation (no root given). It never exits 3: "I could
not read it" is a fact about the *input* it was asked to report on, so it is a reported state, not a
failure to run (ADR-0076's line, and rule 5's "pick one idiom and say which at the call site"). The
call site in Phase S says so in a comment, next to a `scope-args-parse.sh` call three lines above it
that is a CHECKER — the two must not be read as the same shape.

Its stdout is `key=value` lines, `state=` first:

| `state=` | Meaning | Launch does |
|---|---|---|
| `ABSENT` | no `scope` file | nothing; fall through to the marker branch. **No warning** — this is the ordinary "never had a bound" case (R-06's exclusion). |
| `REUSABLE` | `source=arguments`, and the bound is not yet satisfied | reuse it; do not rewrite it; do not clear `published` |
| `SPENT` | `source=arguments`, but `delivered` already satisfies the bound | do not reuse; announce; write a fresh `scope` and clear `published` |
| `NOT-REUSABLE` | `source=marker` or `source=none` | fall through to the marker branch; write a fresh `scope` and clear `published` |
| `MALFORMED` | readable, but no usable `source=`/`features=`/`only=` | **warn, naming the file**; unbounded; remove the file |
| `UNREADABLE` | present, cannot be read | **warn, naming the file**; unbounded; remove the file |

`ABSENT` is this reporter's `CLEAN` (rule 5) and is named as such at its definition, so nobody later
adds a `[ -n "$out" ]` test that is true on every state including the empty one.

`SPENT` is computed the way `conductor-scope-gate` computes exhaustion: `delivered` is
`grep -c . published` (0 when absent), and the bound is satisfied when `features` is a positive
integer and `delivered >= features`, or when `features` is absent and every `only=` row already
appears in `published`. Two copies of one computation would be a defect if they disagreed
(rule 6) — the launch would reuse a bound the gate declares exhausted on the first candidate,
producing exactly the silent no-op run §D4 exists to prevent. They are **not** merged into one
source, because merging means editing `conductor-scope-gate`'s fence and its nine plants for a
feature that has no other reason to touch them; instead the new harness runs both against one
fixture matrix and asserts they agree (rule 17 — a producer specified in one place and consumed in
another needs something checking they meet). **If a third copy of this comparison ever appears,
extract it.**

### D7 — a `MALFORMED`/`UNREADABLE` file is removed at the launch, and only its removal can refuse (R-06)

Warning and moving on is not enough. A file that Phase S could not read is a file
`conductor-scope-gate` cannot read either, and it would exit 3 → `needs-human` → Step 6B on the
first candidate: a run that armed the guard, did nothing, and left a halt marker behind. So check 9
`rm -f`s it before writing, which succeeds on a mode-000 file because removal needs write permission
on the *directory*, not on the file.

If the removal fails, check 9 exits **3 — DID-NOT-RUN**, naming the file and the one-command remedy,
**before** the guard is armed and before Phase 1 starts. This is the only refusal this feature adds,
and it is not the halt R-06 forbids: R-06 forbids treating an unreadable bound as a *reason to stop
the operator's run*, and this is a filesystem that will not let the launch reach a usable state at
all. Rule 4's distinction, kept: found-nothing (`ABSENT`, exit 0, unbounded) and could-not-look
(exit 3) are different answers.

The same removal also fixes a latent bug: check 9 writes with `{ … } > "$_sf"`, and that redirect
*fails* on a mode-000 existing file while the next line still prints `scope: wrote $_sf`.

### D8 — a preserved bound skips Phase P

`source=preserved` means this launch is continuing a run whose Phase P already ran — a `scope` file
exists only because check 9 wrote it, and check 9 runs after Phase P. Re-running Phase P on a
continuation re-does idempotent work with write side effects (`PROJECT.md`, per-feature SPECs,
`.claude/test-cmd`) for no gain, and it has no token list to bound itself with: Phase P passes
`--only "$_scope_only"` as comma-separated tokens, and a preserved bound has rows, not tokens (§D3).

So `source=preserved` takes the existing skip branch, the same one `--dry-run` already uses. An
operator who wants Phase P to run again relaunches with an explicit `--features`/`--only`, which
resets the bound and takes path 1. `TODO.md` `VCS-020` independently records that Phase P had to be
skipped by hand on exactly this relaunch, for the reason in issue #399.

### D9 — the RUNBOOK says it in the two places a human actually reads (R-04)

"Aborting a run" gains the preservation and the override in the same paragraph as the disarm
command, because that is the moment of decision. "The guard is still armed and I cannot push" keeps
its four-row table and its **"four ways to be stuck"** count — the four guard files are unchanged —
and its "It clears the whole transient set" sentence becomes an accurate one about guard state, plus
a pointer to the preserved pair.

## Alternatives considered

**A1 — Announce the loss instead of preventing it: keep clearing `scope`, and make the disarm print
the bound it just deleted plus the exact command that restores it.**
This is R-01's literal reading and the issue's first framing. Rejected: it is an instruction, not an
enforcement (rule 16). It converts a silent unbounded relaunch into an unbounded relaunch the
operator was warned about several minutes and one session boundary earlier, in output they scrolled
past while dealing with whatever made them stop. The failure mode is unchanged; only its blame
moves. The SPEC's own R-01 already concedes this by resolving itself "by construction under R-02's
chosen fork".

**A2 — Split by disarm mode: `--completing` keeps the whole-clear, the bare recovery form
preserves.**
Attractive, and it was this ADR's working design for a while: COMPLETION means "the run is over, its
configuration is spent", RECOVERY means "the run was interrupted, its configuration still means
something". Rejected on the measurement: the bare form **refuses the owning session** (ADR-0112, and
the refusal is deliberate — a foreign session cannot prove the owner is dead). A human pausing from
the live run's own session therefore *must* pass `--completing`, and that is exactly what happened
in `TODO.md` `VCS-020`. The mode split would not have fixed the incident that produced this issue.
The two meanings of `--completing` are not separable at the disarm, which is what drove the decision
to move the judgement to the launch (§D6).

**A3 — Preserve both files unconditionally and add no launch-side logic at all.**
The SPEC's most literal reading. Rejected: it ships the "silent no-op night" regression derived in
Context — a completed bounded run leaves `features=N` and N lines in `published`, and every
subsequent bare launch reports `EXHAUSTED` on its first candidate and stops. Preservation without a
spent/live judgement is not a smaller version of this fix, it is a different bug.

**A4 — Preserve `scope` only; keep clearing `published` with the guard state.**
Rejected: the two files are the two halves of one comparison (`delivered >= features`). Preserving
the numerator's bound while resetting its counter turns a bound of 5 interrupted at 3 into a total
of 8 delivered. It also leaves R-02 half-satisfied, and R-02 names `published` explicitly.

**A5 — Add a `--clear-scope` flag, or a `--keep-scope` flag, to `autopilot-disarm.sh`.**
Rejected, and the SPEC rejects it too ("no new command surface"). It is the same class as A1: a
correct outcome available to whoever remembers a flag. It also multiplies the disarm's mode matrix,
which ADR-0112 spent three paragraphs arguing should stay at exactly two mirrored modes and never
gain a third permissive branch.

**A6 — Move `scope` and `published` to a different directory, e.g. `.claude/autopilot-run/`, so
"clear everything in the state directory" stays literally true.**
Rejected: explicitly out of scope in the SPEC, and it would be a rename touching every reader,
writer, plant needle and test fixture in both skills for a cosmetic gain. The categories differ
inside one directory; that is a fact about the files, and a comment at the loop states it. It is
also the change that would most likely break `conductor-scope-gate` silently, since its path string
appears inside a fence body and inside two plant declarations.

**A7 — Extract the exhaustion comparison into one shared helper used by both `scope-file-read.sh`
and `conductor-scope-gate`.**
Rejected *for this feature*, kept as a named follow-up. Rule 6 supports extraction here — two copies
giving different answers is precisely the defect — but the second copy lives in a fence body carrying
nine plants (`CG1`–`CG9`) in a skill this feature otherwise does not touch, and ADR-0086's
counterweight applies: a shared source that fails disables every consumer at once, and this one
would sit on the autopilot launch path *and* the per-feature conductor gate. The differential
assertion in §D6 buys the same protection at a fraction of the blast radius. The trigger for
revisiting is explicit: a third copy.

**A8 — Timestamp or session-stamp the `scope` file so the launch can tell a fresh bound from a
months-old one.**
Rejected: the SPEC freezes the file format ("keep their current format"), and it would need a new
field that every existing reader must tolerate as ABSENT. The staleness it addresses is real (see
Consequences, negative) but `SPENT` already covers the case that actually recurs — a completed
run — and the launch announces whatever bound it is applying, so a stale one is visible before
anything is armed rather than after.

## Consequences

### Positive

- The bug closes **by construction**: a pause-then-relaunch reuses the same bound with no message to
  read and no step to remember. The operator can do the wrong thing (scroll past the disarm output)
  and still get the right result.
- Two failure modes that were latent before this feature are closed with it. A run that crashes and
  is never disarmed no longer carries its `published` ledger into the next launch (§D4). A `scope`
  file that cannot be written over no longer produces a `scope: wrote …` line that is false (§D7).
- The disarm gets a rule that will survive the next file added to `.claude/autopilot-state/`:
  guard conditions are cleared, configuration and progress are not. ADR-0112's rule could not
  survive `scope` because it was stated about a *directory*; this one is stated about a *category*.
- The judgement moves to the only place with the evidence to make it. `delivered` versus `features`
  is knowable at launch and unknowable at disarm.
- The launch always announces which bound it is applying and where it came from
  (`source=arguments|preserved|marker|none`), so a bounded run is auditable from its own pre-flight
  output — including the case where it is unbounded on purpose.
- `conductor-scope-gate`, `conductor-published-skip` and `autopilot-guard.sh` are unchanged, so
  ADR-0112's `--check`-halts-on-RED behaviour and ADR-0129's nine `CG` plants carry through
  untouched (R-03).

### Negative

- **A preserved bound can be stale.** `scope` now survives indefinitely, so an operator who bounded
  a run in August and launches bare in October gets August's bound if it never reached `SPENT`. It
  is announced at pre-flight and one flag overrides it, but it is a new way to be surprised, and
  A8's timestamp — the thing that would fix it properly — is deferred.
- **Two copies of the exhaustion comparison now exist** (`scope-file-read.sh` and
  `conductor-scope-gate`). A differential test keeps them honest; nothing prevents a future edit to
  one from being made without running that test locally, and CI is where it would surface.
- **A new deployment dependency.** Phase S aborts with exit 3 when `scope-file-read.sh` is not
  deployed, matching the `scope-args-parse.sh` precedent immediately above it. A target repo synced
  before this feature cannot launch autopilot until `staging/sync-to-claude.sh --apply` is re-run.
  The failure is loud and names the command, which is the reason the precedent chose it, but it is a
  hard stop.
- **Three existing assertions and two plant declarations must be inverted or re-anchored**, and one
  of them (`KB5`) asserts the exact opposite of this feature's contract. Repairing a green assertion
  is the part of a contract change most likely to be done by weakening it; the plan makes each
  repair its own step with the deleted assertion's replacement named.
- **The disarm output grows.** It was already seven lines on a full clear; it becomes up to ten.
  A human reading it for the guard files now reads past two lines that are not about them.

### Neutral

- `scope` and `published` keep their paths, their format, their single writer each and their
  existing readers. Nothing migrates and no target repo needs a data change.
- The `--dry-run` path is unchanged in every respect: it writes nothing, removes nothing and reuses
  nothing.
- `started-at`, `rtf-blocker` and `.claude/needs-human` stay in the clear loop. `started-at` is still
  the invented path ADR-0112 named as debris; this ADR does not revisit it.
- The RUNBOOK's "four ways to be stuck" table is unchanged in content and in count — the four guard
  files are exactly the ones still cleared.
- No `CLAUDE.md` rule is added. §D5's two-call-sites-opposite-policies case is rule 11 applied, and
  §D6's reporter/checker split is rule 5 applied; both are instances of existing rules, not new ones.

## References

- `SPEC.md` — R-01 … R-08 (archived at completion to
  `docs/specs/400-autopilot-disarm-scope-unbounded.spec.md`)
- `docs/superpowers/plans/2026-08-23-400-autopilot-disarm-scope-unbounded.md`
- ADR-0112 — `staging/plugin/scripts/autopilot-disarm.sh`, the two mirrored modes, the transient-set
  whole-clear, exit 3 as DID-NOT-RUN
- ADR-0127 §D4 — the `published` ledger and the `delivered` counter
- ADR-0129 §D1/§D2/§D4/§D5 — the `scope` file, its exact-row-text format, `conductor-scope-gate`,
  and why `EXHAUSTED` writes nothing
- ADR-0132 — logic out of a rendered fence and into a script; each fence keeps its own exit
  vocabulary
- ADR-0133 §D1 — a fence body runs under `bash`, `export` forwards free variables, terminator at
  column 0
- ADR-0076 — ABSENT / INVALID / UNREADABLE, and two call sites applying opposite policies to one
  ABSENT state
- ADR-0086 — the counterweight to extraction: a shared source that fails disables every consumer
- ADR-0154 — a harness must name its plan or a cited ADR back, or it descopes itself
- `TODO.md` `VCS-018` (the filed defect), `VCS-020` (the live incident)
- `CLAUDE.md` rules 4, 5, 6, 7, 8, 10, 11, 12, 16, 17, 19
