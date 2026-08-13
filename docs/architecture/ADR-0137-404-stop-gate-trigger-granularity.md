# ADR-0137 — Bound the stop-gate trigger to the changed paths, and bound the ceiling it runs under

- **Status:** Accepted
- **Date:** 2026-08-13
- **Issues:** #404. Files a producer/consumer finding against #309; fixes nothing there.
- **Supersedes / amends:** nothing. Extends ADR-0014 (the `test-cmd` TOFU contract, untouched here)
  and ADR-0024 (which vendored `mark-dirty.sh` as a file and decided nothing about its behaviour).
  This is the first ADR to decide the stop gate's trigger granularity at all.
- **SPEC:** `SPEC.md` (topic slug `404-stop-gate-trigger-granularity`)

---

## Context

`stop-gate.sh` runs a project's entire test command at the `Stop` event whenever anything was
written during the session. `mark-dirty.sh`, the `PostToolUse` hook on `Edit|Write` that arms it,
records *that* a write happened and discards *what* was written. The field it discards is
`tool_input.file_path`, which `post-write-check.sh` already reads on the same event. So editing a
markdown file arms a shell test suite.

"Every `Edit` or `Write`" is an inheritance, not a decision. `stop-gate.sh` appears in ADR-0014 for
the `test-cmd` and its TOFU trust; `mark-dirty.sh` appears in ADR-0024 only as a vendored file.
Changing the trigger therefore supersedes nothing — and has never been argued.

### What was measured before designing, and what it changed

Three premises were checked against the running system. Two did not survive, and the SPEC records
them; they are repeated here because a decision cited without its measurement ages into folklore
(CLAUDE.md rule 13).

**1. The gate is not currently wired, so the symptom cannot reproduce on this machine.** The
deployed `~/.claude/settings.json` registers exactly one `Stop` hook, `chat-done-notify.sh`. The
repository's own versioned copy, `staging/user/settings.json`, registers exactly one `Stop` hook and
it is a *different* one, `stop-gate.sh`. The drift runs in both directions. `mark-dirty.sh` is
registered in both, so the producer keeps running: the state directory holds 71 `.dirty` markers,
the oldest dated 2026-06-20, none ever removed, because markers are removed only on a green run and
no run has occurred. A producer whose consumer is unwired is the shape CLAUDE.md rule 17 names.

**2. The suite takes 2m43s here, not 15m37s.** Timed on this machine: 78 test files, exit 0, all
green, 163 seconds wall clock. The issue quotes 15m37s from a GitHub runner; CI measured 22m20s
today on PR #425. The 120s ceiling still makes a green run unreachable, so the issue's conclusion
holds — but the margin is 43 seconds, not fourteen minutes, which turns "raise the ceiling" from a
theoretical exit into a real one.

**3. "An ADR and a manifest changed, no shell" is not a case where the suite is irrelevant.** The
issue cites commits for #396 and #397 touching `PROJECT.md`, `TODO.md`, an ADR and a manifest as
wasted firings. This suite asserts over exactly those files: the CLAUDE.md-condensation assertions
read the real `CLAUDE.md`, the invariant tests read real manifests, and the rules check reads real
ADR files under `docs/architecture/`. Arming on those commits was correct. **The predicate's yield
on this repository is low, and this ADR does not pretend otherwise** — its value here is the
mechanism and the ceiling half, not a large reduction in firings.

### Two defects sit behind one issue

The predicate is the visible half. The invisible half survives any predicate and any ceiling: on
timeout `stop-gate.sh` exits fail-open and removes the output file but **leaves the marker armed**,
and the anti-loop counter is incremented only inside `emit_block`, which a timeout never reaches. A
timing-out suite therefore re-charges its full ceiling on every subsequent `Stop`, for the rest of
the session, uncounted. Raising the ceiling without fixing this moves the defect to a rarer trigger
and makes each occurrence more expensive.

---

## Decision

### D1 — `mark-dirty.sh` records, `stop-gate.sh` decides

`mark-dirty.sh` reads `tool_input.file_path` and appends it to the session marker, deduplicated. It
discards nothing and decides nothing. `stop-gate.sh` performs the root walk it already performs,
reads the optional exclusion list at that same root, and fires when at least one recorded path is
not excluded.

All policy stays in one script. The gate can name which path armed it, a diagnostic the empty marker
cannot give. Deciding at write time would give `mark-dirty.sh` its own forty-level root-discovery
walk on every `Edit` and `Write`, and put policy in two places that can disagree.

The marker keeps its current meaning: `<state-dir>/<session-id>.dirty`, whose *existence* is the
arming signal. It becomes a newline-separated list of absolute paths as received. A reader that only
tests for the file is unaffected. The current implementation truncates the marker on every write
(`: >`); the new one creates it if absent and appends only paths not already present, so a long
session cannot grow the file without bound and a session that wrote nothing still arms.

**A marker carrying no paths arms the gate.** That covers three real states: a session that started
under the old `mark-dirty.sh`, a payload with no `file_path`, and a write the JSON parse could not
read. Falling back to strict is what keeps a mixed-version state safe, and it is the same direction
the whole feature is bound by — this change *removes* firings, so its inert state must be the strict
one (the rule ADR-0055 §D2 states for relaxing a guard).

### D2 — The exclusion list: a project file, shell globs, matched with bash's own `case`

`.claude/test-ignore`, at the root the walk already found for `.claude/test-cmd`. Optional; absent
means today's behaviour. One pattern per line, blank lines and lines whose first non-blank character
is `#` skipped. No trailing-comment stripping — a `#` inside a pattern is part of the pattern,
because a path may legitimately contain one and inventing a quoting rule to say otherwise buys
nothing.

Matching is `case "$target" in $pat)`, bash's own pattern matching. Verified on this machine's bash
3.2.57: `*` spans `/`, a prefix glob, a suffix glob and a directory prefix all behave as intended,
and **a pattern held in a variable does not re-expand** — a value containing a command substitution
is matched as literal text, not executed, because bash does not re-expand the result of an
expansion. That last point is the one a reviewer will ask about, so the harness pins it with an
assertion rather than leaving it to this paragraph.

- A pattern ending in `/` matches a directory prefix (`docs/books/` becomes `docs/books/*`).
- A pattern beginning with `~` is expanded against `$HOME` first, which lands it in the next case.
- A pattern beginning with `/` after that expansion is matched against the **absolute** recorded
  path. Everything else is matched against the path taken relative to the discovered root.

The list **excludes**, never includes. An include list fails open: a new source directory nobody
listed would silently stop triggering anything.

### D3 — Where the check sits, and exactly what "byte-identical to today" scopes to

The new step is evaluated **after** the TOFU trust check, so the two blocking paths are untouched: no
`.claude/test-cmd` found still blocks, and a `test-cmd` present but not TOFU-approved still blocks,
whatever the exclusion list says. A consequence worth stating plainly: in a project with no
`.claude/test-cmd`, editing a README still blocks. That is today's behaviour, it is what R-04 pins,
and the exclusion list is deliberately not a way to silence it.

When the predicate declines to run the suite, the gate emits **one line on stderr** naming the count
of excluded paths and the list that excluded them, then exits 0 leaving the marker in place. A guard
that silently stops guarding is this repository's signature failure; this is the cheapest thing that
makes the decline visible. It costs one line in the branch that already exists and nothing at all in
the arming path.

**R-02 and R-09/R-10 are in tension and the tension is resolved here, not silently.** R-02 says the
hook's behaviour with no exclusion list present is byte-identical to today's. R-10 changes the
timeout branch whether or not a list is present. R-02 is scoped to the **path-predicate axis**: with
no list at the discovered root, the predicate branch is inert and the arming decision is exactly
today's. It is not a claim that the file is unchanged, and it could not be, because the ceiling axis
is a separately specified change that R-14 requires be recorded. Additionally, R-02's "today" means
*the hook file's own behaviour with a marker present*, never this machine's current registration —
the gate is unwired here and stays unwired after this feature.

### D4 — The ceiling: `.claude/test-timeout`, default 120, maximum 900, and this repository sets none

This is the decision R-14 requires be recorded whether or not it is acted on.

- The value lives in `.claude/test-timeout`, beside `.claude/test-cmd`, found by the same walk. One
  integer, seconds.
- **Absent means 120 seconds exactly**, so every other project on the machine is unaffected.
- **Precedence:** `STOP_GATE_TEST_TIMEOUT` (if a valid positive integer) wins over the file; the file
  wins over the default. The environment variable is the caller's own lever — it is how the harness
  drives fixtures and how a user's `settings.json` can override — and letting a file inside a project
  directory override it would both change existing behaviour and invert the trust ordering.
- **The maximum is 900 seconds, and it bounds the file only.** Rationale, in arithmetic rather than
  taste: this repository's suite measures 163s here, so 900 absorbs a machine five times slower than
  this one, while the 22m20s CI figure is explicitly not the target (CI does not run `Stop` hooks).
  The worst case a raised ceiling can cost is bounded by D5's counter at `STOP_GATE_MAX_REENTRY ×
  ceiling` — 45 minutes per session at the maximum, 6 minutes at the default, against **unbounded**
  today. The environment variable stays unbounded because it is already trusted and bounding it would
  change existing behaviour.
- **A malformed value, or one above the maximum, falls back to 120 and says so on stderr.** Not to
  whatever `case` happens to accept, and not silently: a project that asked for 1800 and got 120 must
  be able to find out why.
- **It is not part of the TOFU hash.** A ceiling is a bound, not a command. It can only ever extend
  how long an already-approved command runs, which is exactly what the maximum exists to bound.
  Folding it into the hash would additionally re-prompt every project on the machine for approval on
  a value change, which is a worse trade than the one it protects against.

**This feature creates no `.claude/test-timeout` for this repository.** The gate is unwired here
pending #309; a ceiling on an unwired gate changes nothing, and shipping one would make the gate's
first real run a 163-second block at every `Stop` for a repository whose suite the operator has not
yet chosen to pay for at that cadence. The recommended value when #309 wires the gate is **300**,
which clears the measured 163s with margin and stays well inside the maximum. No `.gitignore` entry
is added for the file either: an ignore rule for a file that does not exist is an exemption covering
nothing, which is exactly the shape CLAUDE.md rule 9 refuses.

### D5 — A timeout increments the same counter a block increments, and disarms at the cap

On exit code 124 (the timeout, from `timeout`/`gtimeout`, or mapped from 137 in the no-timeout-binary
fallback), the gate reads `<state-dir>/<session-id>.count`, increments it, writes it back, and:

- below the cap, prints the timeout line naming the ceiling and the attempt number, then exits 0 as
  today;
- at or above `STOP_GATE_MAX_REENTRY`, **removes the marker** and prints a stderr line naming the
  disarm and its reason.

**One counter, one budget per session, spent by either failure mode.** Blocks stop blocking at the
cap (today's anti-loop behaviour, unchanged); timeouts disarm at the cap. Two counters were rejected:
the counter's purpose is to bound how much a single session can spend on a check that is not
converging, and a session that has already burned its budget on blocks has burned it.

Exit codes 125, 126 and 127 keep today's message and do **not** increment. They mean the command
could not run, which is instant and costs nothing; the counter exists to bound cost. That leaves a
permanently non-executable `test-cmd` arming forever at zero cost, which is pre-existing, unchanged
and out of scope — recorded so its absence is not later read as coverage.

Two known imprecisions, stated rather than discovered: a test command that itself exits 124 is
indistinguishable from a timeout (pre-existing in the current branch, which already lumps 124 with
125–127), and "consecutive" is approximated by the shared session budget because a green run does not
clear the counter today and this feature does not change that.

### D6 — This repository's day-one list, and the three states of the check that keeps it honest

The list ships with the patterns proven safe — session logs and editor backups, both gitignored and
read by no assertion:

```text
.remember/logs/
*.bak
*.bak-*
```

An exclusion pattern that matches nothing still reads as a working exemption (CLAUDE.md rule 9). A
harness assertion therefore requires every pattern in this repository's list to have a real subject.
It lives in the harness, not in the hook: a hook-time version would tax every `Stop`, and "matched
nothing this session" is not the claim being made — a pattern legitimately matches nothing in a
session that never touched the directory it covers.

The corpus is derived, and **the derivation is count-guarded** (CLAUDE.md rule 7): tracked paths from
`git ls-files` (657 today) union individually-listed ignored paths from `git status --porcelain
--ignored=matching` (93 today on this machine, 53 of them under `.remember/`, 10 `.bak` files). Zero
candidates is a broken derivation and must not read as coverage.

**The check has three outcomes, not two** (CLAUDE.md rule 4), because the day-one patterns are
gitignored by construction and a fresh CI checkout contains none of their subjects:

1. the pattern matches a corpus member → **PASS**;
2. the pattern matches nothing, and a representative path synthesised from it is **not** ignored by
   this repository's own `.gitignore` → **FAIL**. This is the typo case: a mistyped
   session-log directory is classified as not-ignored and fails in CI as loudly as locally;
3. the pattern matches nothing, and the synthesised representative **is** ignored → **SKIP**, with a
   line naming the reason. A fresh checkout cannot exhibit a runtime artefact, and the two dishonest
   alternatives are failing CI for a correct list or having the check create its own subject.

Verified on this machine: a representative for `*.bak` and for `.remember/logs/` is classified
ignored; the representative for a deliberately mistyped `.rember/logs/` is not. The synthesis rule is
mechanical (`*` becomes a literal, a trailing `/` gains a component) and a synthesis that goes wrong
produces outcome 2, never outcome 1 — it fails in the strict direction by construction.

**Using `git check-ignore` here does not re-open the rejected alternative below.** It is not the
hook's predicate and it does not decide whether a path needs testing. It answers a different
question, in the harness only: *why* has this pattern no subject in this checkout.

The whole live block is gated on the repository actually being a git checkout, so a `plant-check.sh`
sandbox — which copies `staging/` and `docs/` and no `.git` — skips it with a stated reason instead
of reporting a defect about a file it cannot see. That is the same care `pairs-completeness.test.sh`
already takes with its CI-list assertion.

### D7 — The harness proposes, the hook decides: no second matcher, and no extracted helper

The subject check needs to answer "does this pattern match this path" with exactly the semantics the
hook applies. Two independent implementations that could disagree would be a defect, which is the
condition ADR-0086 sets for extraction — but extracting a matcher into a sourced helper would give
`stop-gate.sh` a runtime dependency on a second deployed file, whose absence after a partial sync
would be a fail-open hole in a guardrail hook. That trade is worse than the one it fixes.

So neither: the harness runs a cheap `case`-based **prefilter** over the corpus to propose one
candidate path per pattern, then **confirms** it by invoking the real `stop-gate.sh` against a
fixture root — a marker holding the candidate, a `.claude/test-ignore` holding only that pattern, a
trivial trusted `test-cmd` that touches a sentinel. Sentinel absent means the gate declined, which
means the pattern matched, decided by the code that will decide it in production. A prefilter that
over-proposes is rejected by the confirmation; a prefilter that under-proposes reports no subject.
Both directions fail strict. Roughly one hook invocation per pattern, which is three today.

This is also what makes the fixture rig reusable: the same rig answers R-01 (every path excluded →
the command does not run, sentinel absent) and R-03 (one path not excluded → it does, sentinel
present), which are the two directions R-13 requires.

### D8 — A new harness file, and what is plantable

`staging/plugin/scripts/tests/stop-gate-path-predicate.test.sh`, hermetic, bash 3.2, `set -u`,
emitting `PASS: <id>` / `FAIL: <id>` with the colon, ids fixed at two digits (`SGP01`…), because
`plant-check.sh` attributes a plant with a **prefix** match. A new file rather than an extension of
`hook-hardening.test.sh`: provenance, and that file's ids (`1:`, `3a:`) are prefix-unsafe. The cost
is one hand-appended name in `.github/workflows/docs-ci.yml`'s `shell-tests` list, which
`pairs-completeness.test.sh` enforces and which is a plan task, not a footnote.

Plants are declared per ADR-0108 against `staging/plugin/scripts/stop-gate.sh` and
`staging/plugin/scripts/mark-dirty.sh` — both inside the sandbox's copied tree — covering the
excluded direction, the non-excluded direction, the absolute-pattern branch, the ceiling read, the
timeout increment and the path record. The fixture-driven half of the subject check is planted by
self-targeting the harness file, which `plant-check.sh` explicitly supports.

**Two assertions are unplantable by construction and are disclosed rather than worked around:** the
live subject check and its corpus guard read this repository's real `.claude/test-ignore` and its
real git index, neither of which exists in a `plant-check.sh` sandbox. This is the precedent
`triage-state-gitignore.test.sh` set for live-content assertions against repository-root files. Their
mechanism is pinned instead by the fixture pair, which *is* planted, and the disclosure sits in the
harness header where a future reader will meet it.

### D9 — The producer/consumer drift is filed against #309, not fixed here

Re-registering `stop-gate.sh` in the deployed `settings.json` is #309's mechanism, and wiring one
hook by hand is the practice #309 exists to end. The measurement above is filed as a finding attached
to #309 rather than absorbed silently into this feature — including the second direction, that the
staged copy is missing the `chat-done-notify.sh` the deployed copy has, so neither file is a superset
of the other.

**This feature is inert until `settings.json` is synced.** Said here rather than discovered later.

### D10 — What does not move

The TOFU contract and `.claude/test-cmd` itself (the trust pin is a content hash; changing that file
is not a local edit and is out of scope). The exit convention: `stop-gate.sh` still always exits 0,
still emits the block decision as a root-level JSON field, still fails open on every internal error.
`emit_block` and the two blocking paths. The `norm_path` / pre-normalisation hashing arrangement.
`run-hook-tests.sh`, which exercises the deployed copies and whose existing assertions the new
behaviour satisfies unchanged.

---

## Alternatives considered

**1. `gitignore` semantics via `git check-ignore` as the hook's predicate.** Rejected. It would
consult `.gitignore` and `.git/info/exclude` as well as any dedicated file, so "not tracked by git"
would silently become "needs no tests" — two different questions answered by one file, and the wrong
one would win by default. This repository would immediately exclude `.claude/test-cmd` and every
`.bak`, which is coincidentally right, and would also exclude anything a developer had ignored for
unrelated reasons, which is not. It also makes the predicate depend on git being present and on the
path being inside a work tree, giving the hook two new failure modes in exchange for semantics nobody
asked for. (`git check-ignore` is used in the harness under D6, for a different question, and that
distinction is stated there.)

**2. Deciding the predicate at write time, inside `mark-dirty.sh`.** Rejected. It would move policy
into the hook that should only observe, and it would need its own forty-level root-discovery walk on
every single `Edit` and `Write` — the highest-frequency hook in the system — to find a file it would
usually not find. Worse, it puts the policy in two places: `stop-gate.sh` still has to decide what an
empty marker means, so the two would have to agree forever. And it destroys the diagnostic: a gate
that fires can then say *which* path armed it, which a boolean marker written at write time cannot.

**3. A sibling `<sid>.paths` file next to the marker.** Rejected. Two files with one lifetime is two
chances to leave one behind: the green branch removes the marker, and a `.paths` file surviving a
green run would attach a previous session's writes to the next arming. The marker's *existence*
already is the arming signal and its *content* is now the detail; keeping both in one file makes the
clear-on-green path a single unlink, which is what it already is. It also keeps a mixed-version state
safe for free — a marker written by the old `mark-dirty.sh` is simply an empty one, and an empty
marker arms.

**4. Not arming for a path outside the discovered root.** Rejected. It is the wrong direction for a
guardrail. This change removes firings, so its inert and its unknown states must both be the strict
one (ADR-0055 §D2). A path with no repo-relative form is not evidence that the change is irrelevant;
it is evidence that the gate does not know. The operator keeps the ability to exclude such writes
deliberately, through an absolute or `~`-rooted pattern — which is exactly what makes excluding
`~/.claude/*` expressible, the most frequent out-of-root write in a session on this repository.

**5. An include list rather than an exclude list.** Rejected, and the issue argued it first. An
include list fails open: a new source directory nobody listed silently stops triggering anything, and
nothing reports the omission. With an exclude list an unknown path still fires.

**6. Extracting the glob matcher into a helper sourced by both the hook and the harness.** Rejected;
see D7. ADR-0086's criterion does point at extraction here, and the reason it is declined is
specific: the consumer is a globally-registered guardrail hook whose deployed copy must not acquire a
second file it can fail to find. The differential is preserved instead by having the harness confirm
every verdict through the real hook, which is the same guarantee without the deployment coupling.

**7. Raising the ceiling and stopping there.** Rejected. It leaves the marker armed on timeout and
the counter unincremented, so the cost per session stays unbounded and each occurrence becomes more
expensive than before. The ceiling is only defensible once a timeout is counted (D5); shipping D4
without D5 would be a strict regression.

**8. Making the test command faster instead.** Out of scope, and it is a different question with a
cost this feature does not pay: `.claude/test-cmd` is TOFU-pinned by content hash and is read by
`autopilot-build`'s pre-flight and by the chain, so editing it invalidates trust on every machine and
touches three consumers.

**9. Shipping `~/.claude/*` in this repository's own day-one list.** Rejected for now, despite it
being the highest-yield candidate. Its subjects live outside the repository, so no corpus derived
from the checkout can give the D6 subject check a verifiable subject in either environment, and an
assertion that can only be true on one machine is not an assertion. It stays expressible for an
operator who wants it, and the mutation-derivation task can revisit it with evidence.

**10. Two counters, one for blocks and one for timeouts.** Rejected; see D5. The budget being bounded
is what matters, not which failure mode spent it, and two counters means two lifetimes, two clear
points and a new question about which cap a mixed session hits first.

**11. Extending `hook-hardening.test.sh` instead of adding a harness file.** Rejected; see D8. It
avoids one hand-edit in the CI list at the price of prefix-unsafe assertion ids in a file where every
new plant would then be unattributable, and it buries this feature's evidence inside a file named for
a 2026 hook-hardening sweep.

---

## Consequences

### Positive

- A project can declare, in its own repository, which changes do not warrant its suite — and the
  declaration is a plain file with stated semantics rather than a heuristic in a global hook.
- The unbounded half of the issue is closed. A timing-out suite now costs at most
  `STOP_GATE_MAX_REENTRY × ceiling` per session and then disarms with a reason on stderr, against
  "every remaining turn of the session, forever" today.
- A ceiling exists as a per-project bound with a maximum and a stated fallback, so the issue's second
  axis is decided rather than left open under a smaller trigger.
- The gate can name which path armed it, and says on stderr when it declines to run. A guard that
  stops guarding is now visible.
- `mark-dirty.sh` stops discarding a field it was already being handed, which makes any future
  consumer of "what changed this session" possible without touching the write path again.
- The exclusion mechanism arrives with a check that keeps it honest, in three states, so a stale or
  mistyped pattern cannot read as a working exemption.

### Negative

- **The yield on this repository is low, and that is measured, not feared.** The suite reads
  `CLAUDE.md`, real manifests and real ADRs, so the day-one list covers session logs and editor
  backups and little else. Anyone expecting the issue's "editing `TODO.md` arms the shell suite" to
  disappear will find it does not, because `TODO.md` is not on the list and could not be proven safe.
- `stop-gate.sh` grows a loop over recorded paths, each re-reading a small pattern file. The cost is
  negligible in absolute terms and is paid at `Stop`, but the file is a guardrail hook and every line
  added to it is a line that can fail open.
- Two assertions cannot be planted (D8). Their evidence is indirect — a planted fixture pair plus a
  disclosure — which is weaker than every other assertion in the file, and the disclosure is the only
  thing preventing a future reader from assuming otherwise.
- The subject check SKIPs in CI for every pattern the day-one list ships, so in CI it is a check with
  no subject. It is loud about that, but a SKIP nobody reads is a check nobody runs.
- The feature is inert on this machine until #309 syncs `settings.json`, so it ships unexercised in
  production by construction. Every claim about its runtime behaviour rests on the harness.
- The plant registry grows by roughly seven declarations, each re-running the new harness file. The
  registry already exceeds 25 minutes at 343 plants and this makes it slightly worse; that is a known
  P3 item and this feature does not address it.
- `mark-dirty.sh` now does a `grep` per write for deduplication. On a session with a very large number
  of distinct writes this is quadratic in the number of distinct paths. Bounded in practice by session
  length, and the alternative (unbounded append) was worse.

### Neutral

- `.claude/test-ignore` is a tracked file in this repository. `.claude/test-timeout` is not created
  here and gets no `.gitignore` entry.
- The `Stop` exit convention, the TOFU contract, `emit_block`, both blocking paths and the
  `norm_path` arrangement are untouched.
- Both hook files carry `PAIRS` entries, so the change reaches `~/.claude/hooks/` through
  `sync-to-claude.sh --apply` and not before. The new harness file needs no `PAIRS` entry — it is one
  directory below the population `pairs-completeness.test.sh` enumerates.
- The harness is instance 16 of the derived-guard pattern (ADR-0086), a copy on purpose. The number
  is re-derived from the files rather than copied from this ADR: it has collided twice and been
  silently unmarked twice more, and the previous harness caught its own plan proposing an already
  claimed number.
- Recorded so the absence is not later read as coverage: nothing here makes the suite faster, nothing
  re-registers a hook, and no path in this repository beyond the day-one list has been proven safe.

---

## References

- `SPEC.md` (topic slug `404-stop-gate-trigger-granularity`) — the seven interview decisions and the
  three measurements this ADR is built on.
- Issue #404 (the trigger granularity and the ceiling), issue #309 (settings.json is never synced and
  five guardrail hooks are wired by hand).
- ADR-0014 — the `test-cmd` TOFU contract, untouched here.
- ADR-0024 — vendored `mark-dirty.sh` and `stop-gate.sh` into `staging/`; decided nothing about
  either one's behaviour.
- ADR-0055 §D2 — a change that relaxes a guard takes the strict inert state.
- ADR-0086 — the extraction criterion, applied in D7 and declined with a stated reason.
- ADR-0088 — test authoring splits at sub-task granularity; the plan's tester/coder split follows it.
- ADR-0101 — an assertion must not sit in the same batch as the task it depends on.
- ADR-0108 — the plant registry; every new assertion is planted or its unplantability is disclosed.
- ADR-0124 — a floor absorbs its own plant; the assertion-count floor here is a vacuity guard and
  says so at the site.
- CLAUDE.md rules 1, 2, 4, 5, 6, 7, 9, 10, 13, 16, 17.
