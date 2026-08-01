# ADR-0110 — The precondition stated three times and checked nowhere

- **Status:** Accepted
- **Date:** 2026-08-01
- **Issues:** #320
- **Related:** ADR-0029 (`CLAUDE_CODE_SESSION_ID` is the correct variable name), ADR-0076 (input
  facts and environment facts are different states), ADR-0086 (one answer where two would be a
  defect), ADR-0016 (the substrate moves — stamp the build), ADR-0077 (the transcript-scan rule and
  its declared exemptions), ADR-0109 (#319, the same silent-seam class one week earlier)

## Context

`nightly-autopilot/SKILL.md` states its first launch precondition three times in prose — *set a
non-blocking permission mode* — and **Phase 0's eight checks verified it nowhere**. On 2026-07-31
pre-flight printed `PASSED`, the guard armed, the roadmap started, and the chain died at its first
Gate 0 write, a compound Bash command, with nobody present to answer the prompt.

Every other precondition Phase 0 checks — opt-in marker, TOFU trust, `gh` auth, CI — fails **loudly
and early**. This one failed **silently and late**, and it is the only one whose failure is
*guaranteed* fatal rather than conditional.

### What was measured, 2026-08-01, CC 2.1.220

The issue asked the right question before proposing anything: *is the effective mode observable at
all?* The answer was better than it expected, and it is not where anyone would look first.

- **M1 — not in the environment.** The nine `CLAUDE*` variables a skill's Bash can see carry no
  permission field.
- **M2 — `settings.json` is the wrong source, and wrong in the direction that matters.** It holds
  `permissions.defaultMode`. A session started with `--permission-mode`, or switched at runtime
  with Shift+Tab, never writes there. So a stored `acceptEdits` would **pass** the check while the
  session actually runs `auto` and dies — precisely the failure being fixed. Proven live: while
  this was being written, `settings.json` said `auto` and the session was in `plan`.
- **M3 — the session transcript records the effective mode.** `permissionMode` is a **top-level**
  key on `user` entries and on a dedicated `type: "permission-mode"` entry emitted on change. The
  last one is the mode in force.
- **M4 — the transcript is reachable from inside a skill.** `CLAUDE_CODE_SESSION_ID` matches the
  transcript basename exactly.
- **M5 — the signal is build-new.** 39 of 42 local transcripts carry it; the two real exceptions
  are both **CC 2.1.219**. It first appears at the first user entry, so it is present by the time
  any pre-flight runs.
- **M6 — the gap is in two entry points.** `autopilot-build`'s pre-flight had no posture check
  either. `project-conductor nightly` is reached only through `nightly-autopilot`, so it is covered
  transitively.
- **M7 — Phase P runs *before* Phase 0** and writes `.claude/test-cmd`, `PROJECT.md` and
  per-feature SPECs. A check placed inside Phase 0, as the issue's text implies, would let a
  blocking mode stall all of that first.

## Decision

### D1 — read the transcript, never the stored default

`permission-mode-state.sh` reports `NONBLOCKING` / `BLOCKING` / `UNCLASSIFIED` / `UNOBSERVABLE`.
It is a **checker** (the caller branches on the exit code) and it reads only.

**The last recorded value wins.** Reading a first or stored value is M2's defect wearing different
clothes: a session that *started* non-blocking and was switched to `auto` would pass. `PM4` is that
assertion and it is the centre of the harness; `PM12` proves behaviourally that a `settings.json`
saying `auto` cannot override a transcript saying `acceptEdits`.

### D2 — `UNOBSERVABLE` is a token, exit 3 is for the environment

"This build does not record the mode" is a fact about the **input**; "there is no python3" is a
fact about the **environment**. A caller that cannot tell them apart reports both with one
sentence, and that sentence is wrong for one of them. ADR-0076 draws this line; ADR-0109 had to
redraw it a week ago after a first draft folded "no file" into exit 3.

### D3 — a top-level JSON key, not a grep, and the reason is not the obvious one

Measured on a real transcript that contained the field quoted inside a tool result: grep 114,
parser 114 — **no divergence**. The naive grep survives only because JSON escapes the quotes of
nested strings, which is an accidental property of the format rather than a designed guarantee.
Relying on it would be rule 12 at run time, so the value is taken as a top-level key and `PM8`
pins it with a nested-decoy fixture.

This is also why the script carries a declared `transcript-scan-exempt` (ADR-0077): it reads the
**last** value rather than the first `user` entry, deliberately, and the #127 self-arming hazard
cannot reach it because quoted text is never matched as text.

`import json` is stdlib, so unlike its siblings in that directory this script needs no PyYAML — and
a fixture that redirects `HOME`, which hides per-user site-packages (ADR-0090's trap), does not
break it.

### D4 — `dontAsk` is refused as UNCLASSIFIED, and the message says so

Its semantics could not be established from the CC binary. For a pre-flight the safe direction is
to refuse the unknown: aborting a run that would have worked costs a night, while passing one that
stalls costs a night **and** leaves half-written state. Both call sites must say **unclassified,
not known-bad** — an operator told their mode is unsafe when nobody has measured it will go looking
for a problem that may not exist.

### D5 — placement: before Phase P in one skill, after the scope guard in the other

- `nightly-autopilot` gets a new **Phase M**, above Phase P (M7). Phase 0 gains a sentence saying
  the check is *not* one of its eight and **must not be added as a ninth** — otherwise the obvious
  next edit creates a second answer to "may this run start".
- `autopilot-build` gets **check 1b**: not first, because check 1 is the scope guard and nothing
  may precede it; not last, because a blocking mode can deny the checks in between and learning
  about it after six more wastes the diagnosis. That rationale is written at the site, because a
  reader who does not know it will move the check.

Both read the **same** script (`PMF9`). Two unattended entry points that disagreed about whether a
run may start would be a defect, not a difference — ADR-0086's criterion applied where it matters
most.

### D6 — fail closed on `UNOBSERVABLE`, with the cost stated

Chosen explicitly by the operator. The cost is real and is printed in the message: **on builds
before CC 2.1.220 the unattended paths will not start.** The alternative is the silent `PASSED`
that cost the 2026-07-31 run, which is the thing being fixed.

### D7 — the prose gains the `how`

The launch order said *set a non-blocking permission mode* and named no command. It now names all
three routes — Shift+Tab (from `auto`, two presses), `--permission-mode` at launch,
`permissions.defaultMode` for the durable default — and states that **`/permissions` does not set
the mode** (it manages allow/ask/deny rules) and that **hooks are a separate axis it does not
touch**. Both were established the hard way this session, and an instruction whose remedy names no
runnable command is exactly the defect ADR-0109 closed one level up.

## Known consequences, recorded rather than fixed

- **Whether `acceptEdits` is *sufficient* for a fully unattended run is unmeasured.** Under it,
  file edits are auto-accepted but Bash commands outside the allowlist still prompt. This check
  asserts the mode is one the skill declares non-blocking; it does not prove no prompt can fire.
  Anyone reading a green posture check as "no prompt is possible" is reading more than it says.
- **The signal is CC 2.1.220-era and nothing else.** ADR-0016's v2.1.154 experience is the
  precedent. Re-measure after a major bump: if the field moves or disappears, every unattended run
  fails closed on `UNOBSERVABLE` — loudly, which is the intended direction, but it will look like a
  regression.
- **`dontAsk` blocks runs today.** If it turns out to be non-blocking, this refuses a valid posture
  until someone measures it and extends the enumeration. That is the trade D4 makes on purpose.
- **Inert until sync**, and worse than inert: both fences abort with "the check DID NOT RUN" until
  the `PAIRS` entry reaches `~/.claude`. `pairs-completeness.test.sh` cannot see a skill `scripts/`
  file (ADR-0043), so `PM0b` is the only guard.
- **The checker cannot see a mode change that happens after it runs.** Nothing can; a pre-flight is
  a snapshot. A human who switches to `plan` mid-run gets the old failure back.
- `PM0`, `PM10`, `PM11` and `PMF9` pass before and after — forward guards, not fix evidence. The
  six seen RED under `plant-check.sh` are `PM2`, `PM3`, `PM4`, `PM9b`, `PMF3`, `PMF7`.
- **`PM9b`'s plant did not fire on its first run, and the plant was what was wrong.** It rewrote
  `-ne 0` to `-ne 999`, which with a stub `python3` exiting 7 is TRUE — so the guard fired *more*,
  the assertion passed, and the registry correctly reported an assertion pinning nothing. Disabling
  a guard and retuning it are not the same edit. ADR-0090's rule — inspect what the plant actually
  produced — applied to a plant written the same hour as the ADR citing it.

**A false positive that found a true defect, worth recording because ADR-0051 tracks this
detector's precision.** `weakening-scan.sh`'s advisory `swallowed-error` heuristic flagged the
per-line `except Exception: continue` around `json.loads`. That swallow is **correct**: a transcript
is append-only and is being written while this runs, so its last line can legitimately be
half-flushed. But investigating the flag surfaced a genuinely wrong branch two statements below —
the `python3` call had `2>/dev/null` and no status check, so an interpreter failure produced an
empty result and fell into the branch that tells the operator *"a pre-2.1.220 build does not write
it"*. **A cause that is not the cause**, inside the file whose entire subject is reporting the right
reason for a state. `PM9b` pins it with a stub `python3` that exits 7. The finding was wrong and the
investigation it triggered was not; an advisory reporter earning its keep by being read rather than
by being right.

**Harness lesson, and it is the third fixture bug of its family this week.** `PMF2`–`PMF7` first
failed against *correct* fences because `stub_home` built a malformed stub with a mis-quoted
`printf`. Its first draft also named the stub directory from a counter incremented inside `$(...)`
— a subshell, so every call would have returned the same directory. That is ADR-0096's `mk_root`
bug exactly, met again by the same hand ten days later, which is the argument for reading what a
fixture *produced* rather than what its assertion reports.
