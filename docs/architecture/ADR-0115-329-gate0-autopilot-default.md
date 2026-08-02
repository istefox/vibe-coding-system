# ADR-0115 — Gate 0's autopilot default, and the contract nothing enforced

- **Status:** Accepted
- **Date:** 2026-08-02
- **Issue:** #329 (`chain-blocker`, the last of Phase 10.0)
- **Supersedes / amends:** amends the §5 autopilot contract in `concept-to-code/SKILL.md`; amends
  ADR-0111 (issue #324) where it recorded that the c2c pre-flight does *not* hard-abort on a
  missing SPEC.

## Context

`concept-to-code` §5 opens with a promise: when `autopilot = true`, every gate below skips its
`AskUserQuestion` and auto-selects the safe default, listed inline as **[Autopilot default: …]**.

**Gate 0 — the chain's first gate, which fires on every feature — had no such block.** `/goal`
cannot answer an `AskUserQuestion` (ADR-0022), so an unattended run raised a question nobody could
answer before doing any work. That is what the 2026-07-31 launch hit: zero implemented features, one
stall at the first gate.

A second consequence hid behind the first. The only SPEC.md existence check on the routing path sat
**inside the `[auto]` option**, reached by a human click. On the nightly path `project-conductor`
sets `autopilot: true` *before* invoking the chain, so nobody ever clicks `[auto]` and the check had
never run once.

## What was measured

**M1 — the stall is real.** `project-conductor` Step 4 invokes
`Skill(skill="concept-to-code", args="<next-feature>")` at both call sites, with no path prefix.
§2 Form A's fast path skips Gate 0 only when the first word is `express|hybrid|standard`. It is not.

**M2 — Gate 0 is the only genuine gap, and there are four near-misses.** Deriving every
`**Gate N —**` heading in §5: 18 gates, 13 carrying `[Autopilot default:`. Of the five without one —
Gate 0 (the defect), Gate 0b (exempted by the old contract only *"when remote is private"*, so it
prompts unattended on a public remote), Gate 2 (a container heading; 2a/2b/2c each carry one), Gate 4
(covered, spelled `[Autopilot bypass:`), Gate 5.6 (raises no question at all).

**And Gate 4.5 carried a THIRD spelling** — `**[Autopilot default is deliberately NOT …` — which
the contract does not describe and no mechanical check could recognise. Found by the class guard on
its first run, not by reading.

**M3 — nothing in the harness asserted the contract.** Grepping all 72 test files for
`Autopilot default` returned **zero** hits. That is why one missing block survived thirteen present
ones for the life of the file.

**M4 — the safe default is not a guess.** Run live: `gate0-detect.sh` on this repository returns
`spec_adr_exist=true`, and §2 step 7 already says *"if `spec_adr_exist=true` → force recommend
standard"*.

**M5 — it must not be the auto-detect vote either.** Step H1 invokes `interview-driver`
**unconditionally** — unlike standard Step 1, it has no brownfield skip — and Express Step E1 runs
plan mode. Only `standard` completes with nobody present, which is what the `[auto]` label already
said (*"brownfield only"*).

**M6 — the corpus bounds the pre-flight.** Over 41 manifests: `autopilot:true` with
`chain_path:standard` ×18, with `chain_path:null` ×**18**, with `express`/`hybrid` ×**0**.

**M7 — ADR-0111's paragraph inverts.** It rewrote `project-conductor`'s claim to *"the c2c autopilot
pre-flight hard-aborts at Gate 0 … Measured: it does not."* After this change it does.

## Decision

### D1 — Gate 0's autopilot default is `standard`, and says why it is not the vote

`[s]`, matching `[auto]` minus the one thing `[auto]` adds — `autopilot` is already `true` by the
time this gate is reached unattended. The marker states explicitly that it is **not** the
auto-detect recommendation, with M5's reason, because the vote is the obvious-looking choice and it
is the wrong one.

### D2 — the SPEC pre-flight moves out of the option and becomes §2 Form A step 7b

Inside `[auto]` it was unreachable by the only caller that needs it; inside the gate it would be
skipped by the `express|hybrid|standard` prefix fast path. It belongs to the **step**, after
routing, where all three routes converge. A declared `fence-contract:
c2c-autopilot-routing-preflight`, a **CHECKER**:

- Reads `autopilot` and `chain_path` through `manifest-field-state.sh` (ADR-0076 §THE RULE — never
  a bare `m.get()`). Missing helper or `UNREADABLE` → **exit 3**, fail closed. No new dependency
  class: step 4b of the same form already hard-depends on that script.
- `autopilot` ABSENT or `false` → exit 0, silent. Attended runs are byte-unchanged.
- `chain_path` ∈ {`express`,`hybrid`} → abort (M5). `null` and `standard` proceed (M6).
- `SPEC.md` absent → abort, naming the file and both remedies.

**The `[auto]` branch's own copy is deleted, not duplicated.** Two copies of one safety question is
the worst available shape: they can disagree about whether the gate fires. ADR-0086's criterion,
applied — this is one question, so one place answers it.

### D3 — every abort transitions the manifest to `aborted` first

Left in flight, the manifest reads `step_0_init`/`in_progress` → `ADOPTABLE` at
`project-conductor` Step 5 branch C → **run-level halt**, which would reintroduce exactly the blast
radius ADR-0111 had just removed. `aborted` reads `TERMINAL` → contained per-feature skip. Exit 3
deliberately does **not** transition: an unread gate is not a decided end.

### D4 — the conductor's SPEC-COPY guard stays primary, and the text says so

Both defences are now contained per-feature skips, so the difference is what survives: the conductor
settles the feature before any manifest exists; the c2c fence has to create one and then abort it.
The conductor's block carries a *do not remove it on the grounds that the chain now checks too*
line, because the obvious reading of D2 is that it is redundant. It is not, and it also covers the
attended conductor's *"Start in autopilot mode"* branch, which never runs the SPEC copy
(`_nightly=true` only).

### D5 — two marker spellings, enforced; the third normalised

`[Autopilot default:` and `[Autopilot bypass:`, both colon-terminated so they are mechanically
checkable, both named in the contract. **Gate 4 keeps `bypass:`** — the semantics differ (it skips
the gate rather than answering it) and `recovery-preflight.test.sh` (`RH4`, `RI1`) uses
`**[Autopilot bypass` as an awk **extraction boundary**, so renaming it breaks two assertions in
another file. **Gate 4.5's third spelling is normalised** to the colon form with its argument
preserved word for word; nothing extracted on it (verified by search before changing it).

A gate that legitimately needs neither declares `<!-- autopilot-gate-exempt: <reason ≥ 40 chars> -->`
on one line. Gate 2 (container) and Gate 5.6 (no question) hold the only two.

### D6 — Gate 0b gets `[n]`

`anonymize` stays `false` — the same value the `silent` branch and a private remote both produce.
Never `[y]`: the gate's own line says enabling anonymisation is never auto-applied.

## Guard

Section **G** of `concept-to-code-bsd-autopilot-gates.test.sh`, 20 assertions, 19 planted:

- `G0` count-guards the derivation at `>= 15` gates. An unmatched heading pattern empties the
  population and makes `G1`/`G2`/`G2b`/`G2c` pass vacuously — which reads exactly like full
  coverage.
- `G2` requires a marker or an exemption on every derived gate; `G2b` runs it **backwards** (an
  exemption on a gate that also has a marker is stale, and stale reads as clean — ADR-0081 `ZA4`);
  `G2c` requires each reason to be ≥ 40 chars on one line.
- `G4`–`G9` extract the fence by its marker and **execute** it in five states, both directions.
- `G11` asserts the conductor's paragraph **positively** rather than banning yesterday's wording:
  a ban pins one past error and passes the moment anyone rewrites it, correctly or not (ADR-0067
  `F5`).

Instance 10 of the derived-guard pattern; not extracted (ADR-0086 — its own population, its own
question).

## Five defects this found in its own assertions, each caught by planting

Recorded because four of the five are the same shape as defects this repository has recorded before,
and one is new.

1. **`^_c2c=` did not match an indented fence line.** The fence sits inside a numbered list item, so
   every line carries three leading spaces; the redirect from `$HOME/.claude` to `staging/` silently
   did nothing and `G5`–`G8` went **green against the deployed copy** — the exact `$HOME` dependency
   the file header forbids. `G4b` now asserts the redirect landed.
2. **`[^]]*standard` after the marker's colon.** The marker opens with `` `[s]` ``, so a
   `]`-terminated run stops three characters in. It reported a correct marker as missing its value.
3. **The `G1` plant did not fire** because "standard" appears five times in that one marker line.
   The assertion now names the *assignment* (`chain_path: standard`), which is the mechanism.
4. **The `G4` plant did not fire** because the extractor matched `fence-contract: <id>` as a
   substring, and the mutation renamed the id by **appending** to it. Anchoring on the closing
   `" -->"` fixes both.
5. **The `G9` plant did not fire** because the replacement collapsed
   `echo "…"` + `exit 0` onto one line, making `exit 0` two arguments to `echo` — ADR-0112's lesson,
   met again. And `G9` was covered by **two** guards producing exit 3, so it isolated neither
   (ADR-0104): it now asserts the first guard's *message*.

## The registry's own boundary, found the hard way

`plant-check.sh` collects declarations with `grep -n '^# plant:'` — **anchored at column 1**. Eight
declarations written *beside their assertions*, inside an `if`/`else` block, were silently skipped:
they did not run, did not fail, and the only symptom was a file appearing to carry fewer plants than
its author wrote. That is the registry's own failure mode — a plant nobody validated — reproduced
one level up, on the file whose subject is that failure mode.

**`PC4`** now fails on any indented declaration. Verified in the failing direction against a
synthetic file; ADR-0108 recorded that the registry *"is itself an assertion corpus with no plants
of its own"*, and this is one boundary of that gap now closed.

## Consequences

- **This ships an instruction, not an enforcement.** Nothing makes an orchestrator obey an
  `[Autopilot default: …]` block; the guard asserts the block exists, never that it is followed.
  The fence is the one part that executes.
- **The fence is a hard dependency on a deployed script and is worse than inert until sync** — it
  exits 3 and stops the chain when `manifest-field-state.sh` is missing. Same class as ADR-0076's
  two call sites, and deliberate: an unread gate is not a clean gate.
- **`chain_path: null` under autopilot is tolerated** (M6), so a run that genuinely failed to route
  is indistinguishable from 18 historical manifests that completed fine.
- **An exemption reason is a sentence a human wrote.** `G2c` checks it is long; nothing checks it is
  true.
- Gate 0's `⚠ SPEC.md present but its topic could not be verified` warning still renders unattended,
  where nobody reads it. Harmless once the gate no longer waits — a warning with no audience, worth
  a follow-up and not worth widening this change.
- **This does not close Phase 10.0.** The exit criterion is a launch reaching at least one
  `NIGHTLY-PUBLISH` line, and that still needs `permissions.defaultMode` off `auto` — a human
  keystroke, outside this change.
