# SPEC — Bound the stop-gate trigger to the changed paths

**Topic slug:** 404-stop-gate-trigger-granularity

**Issue:** #404
**Date:** 2026-08-13
**Chain:** concept-to-code, standard path

## Objective

`stop-gate.sh` runs a project's entire test command at the `Stop` event whenever anything was
written during the session. `mark-dirty.sh`, the `PostToolUse` hook that arms it, records *that* a
write happened and discards *what* was written — so editing a markdown file arms a shell test
suite.

This feature gives the gate a path predicate the project owns, and settles the second axis the
issue names: a ceiling that no run of this suite can fit inside, and a timeout that re-charges its
full cost every turn without anything counting it.

## What was measured before designing, and what it changed

Three premises were checked against the running system. Two did not survive.

**1. The gate is not currently wired, so the symptom cannot reproduce.** The deployed
`~/.claude/settings.json` registers exactly one `Stop` hook, `chat-done-notify.sh`. There is no
`settings.local.json`, no project-level settings file, and no plugin registering `stop-gate.sh`.
The repository's own versioned copy, `staging/user/settings.json`, *does* register it on `Stop`.
The two have drifted, which is issue #309's subject.

`mark-dirty.sh` is registered in both, so it keeps running: `~/.claude/state/stop-gate/` holds
**71 `.dirty` markers**, the oldest dated 2026-06-20 and the newest written today. None has ever
been removed, because markers are removed only on a green run and no run has occurred. A producer
whose consumer is unwired is the shape rule 17 names.

**Decision (Q1): this feature designs for the wired state.** Re-wiring belongs to #309, and the
producer/consumer drift is filed as its own finding attached to it rather than absorbed silently
here. R-02's "byte-identical to today" therefore means *the hook file's own behaviour with a marker
present*, never *this machine's current registration*. The feature is inert until settings.json is
synced, and that is stated rather than discovered.

**2. The suite takes 2m43s here, not 15m37s.** Timed on this machine: 78 test files, exit 0, all
green, 163 seconds wall-clock. The issue quotes 15m37s from a GitHub runner; CI measured 22m20s
today on PR #425. The ceiling is 120s, so the issue's conclusion holds — a green run is unreachable
— but the margin is 43 seconds, not fourteen minutes, which makes a raised ceiling a real option
rather than a theoretical one.

**3. "An ADR and a manifest changed, no shell" is not a case where the suite is irrelevant.** The
issue cites commits #396/#397 touching `PROJECT.md`, `TODO.md`, an ADR and a manifest as wasted
firings. This suite asserts over exactly those files: CMC01–CMC12 read the real `CLAUDE.md`, the
invariant tests read real manifests, the rules check reads real ADR files under
`docs/architecture/`. Arming on those commits was correct. The predicate's yield on this repository
is therefore low, and pretending otherwise would disarm the gate precisely where it works.

A naive count of path literals in the test files puts `docs/manifests` at 146 mentions,
`PROJECT.md` at 107 and `CLAUDE.md` at 74, but that count includes strings written into temporary
fixtures and so over-states real-repository reads. The precise set is derived by mutation in the
plan, not asserted here.

## Scope

**In scope**

- `mark-dirty.sh`: record each written path instead of discarding it.
- `stop-gate.sh`: read an optional per-project exclusion list and fire only when at least one
  recorded path is not excluded; read an optional per-project ceiling; count timeouts.
- The staging mirrors of both hooks, which are the versioned copies.
- A minimal `.claude/test-ignore` for this repository, plus the harness assertion that keeps it
  honest.
- An ADR recording the ceiling decision, which the issue's R-07 requires whether or not it is acted
  on.

**Out of scope**

- Re-registering `stop-gate.sh` in the deployed `settings.json`. That is #309's mechanism, and
  wiring one hook by hand here is the practice #309 exists to end.
- Making the test command faster. A different question, with a TOFU cost this feature does not pay.
- Any change to the two blocking paths (no test-cmd found; test-cmd present but untrusted).

## Stack

Bash 3.2-clean shell hooks, `jq` for payload parsing, the existing
`staging/plugin/scripts/tests/*.test.sh` harness, plants declared in the plant registry per
ADR-0108.

## Architecture

### Where the predicate is evaluated (Q3)

`mark-dirty.sh` records; `stop-gate.sh` decides. All policy stays in one script, and the gate can
name which path armed it — diagnostics the empty marker cannot give. The alternative, deciding at
write time, would give `mark-dirty.sh` its own root-discovery walk and put policy in two places.

`mark-dirty.sh` reads `tool_input.file_path` — the same field `post-write-check.sh` already reads on
the same event — and appends it to the session marker, deduplicated, so a long session cannot grow
the file without bound. It never discards a path and never decides anything.

`stop-gate.sh` performs the root walk it already performs, looks for the exclusion list at that same
root, and fires only when at least one recorded path fails to match. The list excludes rather than
includes, because an include list fails open: a new source directory nobody listed would silently
stop triggering anything.

### Pattern semantics (Q4, Q5)

Shell globs, one per line, `#` comments and blank lines skipped, matched with bash's own `case`
against the path taken relative to the discovered root. A trailing slash matches a directory prefix.
No external tool, and the semantics are stated in the file's own header rather than inferred.

`gitignore` semantics via `git check-ignore` were rejected: that would also consult `.gitignore` and
`.git/info/exclude`, so "not tracked by git" would silently become "needs no tests" — two different
questions answered by one file.

A recorded path outside the discovered root has no repo-relative form. It **arms** the gate, because
that is today's behaviour and this feature removes firings, so its inert state must be the strict
one. A pattern beginning with `/` or `~` matches the absolute path, which is what lets an operator
exclude `~/.claude/*` — the most frequent write in a session on this repository, and one this
project's suite does not cover in either direction.

### The ceiling axis (Q2)

Two independent defects sit behind the issue's R-07, and only one of them is the ceiling.

**The ceiling.** A file beside `.claude/test-cmd` carries a per-project value; absent means 120s
exactly, so every other project on the machine is unaffected. The value is bounded by a stated
maximum, and a malformed value falls back to the default rather than to whatever `case` happens to
accept. It is not part of the TOFU hash: a ceiling is a bound, not a command, and it can only ever
extend how long an already-approved command runs — which the maximum is there to bound.

**The unbounded half, which survives any ceiling.** On timeout `stop-gate.sh` exits fail-open and
removes the output file but leaves the marker armed, and the anti-loop counter is incremented only
inside `emit_block`, which a timeout never reaches. So a timing-out suite re-charges its full
ceiling on every subsequent Stop, forever, uncounted. A timeout now increments the same counter a
block does; after `STOP_GATE_MAX_REENTRY` consecutive timeouts the marker is disarmed and a stderr
line names why. Without this, raising the ceiling only moves the defect to a rarer trigger.

### Keeping the exemption honest (Q6, Q7)

An exclusion pattern that matches nothing still reads as a working exemption. A harness assertion
checks that every pattern in this repository's own list matches at least one path that exists today,
count-guarded so an empty list cannot pass vacuously, and planted so the assertion is seen RED
against a declared defect.

The check lives in the harness, not in the hook: a hook-time version would tax every Stop, and
"matched nothing this session" is not the same claim as "matches nothing" — a pattern legitimately
matches nothing in a session that never touched the directory it covers.

This repository's list ships with only the patterns proven safe — session logs and editor backups,
both gitignored and read by no assertion — so the harness check has a real subject from day one. The
full safe set is derived by a plan task the only way that proves anything: mutate a candidate path,
re-run the suite, keep the candidate only if no assertion moves.

## Data model

**Session marker** — `<state-dir>/<session-id>.dirty`. Today an empty file whose existence is the
whole signal. It becomes a newline-separated list of written paths, deduplicated, absolute as
received. Its existence keeps its current meaning, so a reader that only tests for the file is
unaffected.

**Exclusion list** — `.claude/test-ignore` at the project root, discovered by the same walk that
finds `.claude/test-cmd`. Optional. Absent means today's behaviour exactly.

**Ceiling** — an optional per-project file beside `.claude/test-cmd`, holding one integer.

**Re-entry counter** — `<state-dir>/<session-id>.count`, already present, now incremented by
timeouts as well as blocks.

## API and control flow

No network API. The contract is the hook payload and the exit convention, both unchanged:
`stop-gate.sh` still exits 0 always, still emits `{"decision":"block","reason":...}` to block, and
still fails open on every internal error.

Ordering at a `Stop` event, after the changes:

1. Marker absent → exit 0. Unchanged.
2. Root walk for `.claude/test-cmd`. Not found → block. Unchanged.
3. Test command is `NONE`, empty or unreadable → exit 0. Unchanged.
4. TOFU trust check → untrusted blocks. Unchanged.
5. **New:** read the exclusion list at the same root. Every recorded path excluded → exit 0 without
   running anything, leaving the marker in place.
6. **New:** read the ceiling; run the command under it.
7. Green → clear the marker and the paths with it. Unchanged in effect.
8. **New:** timeout → increment the counter; disarm and report once the cap is reached.
9. Red → block with the failing output, as today.

## UI flows

None. Both hooks are non-interactive. The only human-visible surfaces are the stderr line naming a
disarm, and the block reason already delivered to the model.

## Edge cases

- **The list exists but is empty, or holds only comments.** Every path is unmatched, so the gate
  arms exactly as with no list. Not an error.
- **A path recorded before the list was created.** The list is read at Stop, so it applies to
  everything recorded that session. Deliberate: the operator's latest intent wins.
- **A write outside the discovered root.** Arms, unless an absolute pattern excludes it (R-08).
- **The marker exists but holds no paths** — written by the current version of `mark-dirty.sh`, or
  by a session that started before this change. Treated as unknown, so it arms. Falling back to
  strict is what keeps a mixed-version state safe.
- **A path containing a newline.** Cannot be represented in a newline-separated record; such a path
  is recorded in a form that cannot match any pattern, so it arms.
- **The suite times out on a machine slower than this one.** The counter bounds the cost, and the
  disarm says so on stderr rather than failing silently.
- **A ceiling value that is not a positive integer, or above the maximum.** Falls back to the
  default, and says so.
- **Two projects nested inside one another.** The walk stops at the first `.claude/test-cmd`, and
  the exclusion list is read from that same root — the two never diverge, because one walk finds
  both.

## Success criteria

- [ ] R-01 — a session whose every recorded path matches the exclusion list does not run the test
      command at the `Stop` event.
- [ ] R-02 — with no exclusion list present, the hook's behaviour is byte-identical to today's, in
      this repository and in any other project on the machine; "today" means the hook file's own
      behaviour with a marker present, not this machine's current registration.
- [ ] R-03 — a recorded path matching no pattern still arms the gate; the list excludes, never
      includes.
- [ ] R-04 — the two blocking paths are untouched: no `.claude/test-cmd` found, and `test-cmd`
      present but not TOFU-approved, both still block.
- [ ] R-05 — the paths record is cleared on a green run exactly as the marker is today, and is not
      cleared by a turn the predicate skipped.
- [ ] R-06 — `mark-dirty.sh` records every written path, deduplicated, and discards none; a marker
      carrying no paths arms the gate.
- [ ] R-07 — patterns are shell globs, one per line, with `#` comments and blank lines skipped,
      matched against the path relative to the discovered root; a trailing slash matches a directory
      prefix.
- [ ] R-08 — a pattern beginning with `/` or `~` matches the absolute path, and a recorded path
      outside the discovered root arms the gate unless such a pattern excludes it.
- [ ] R-09 — an optional per-project ceiling file overrides the 120s default; absent means 120s
      exactly; a value that is malformed or above the stated maximum falls back to the default and
      reports that it did.
- [ ] R-10 — a timeout increments the same counter a block increments, and after
      `STOP_GATE_MAX_REENTRY` consecutive timeouts the marker is disarmed with a stderr line naming
      the reason.
- [ ] R-11 — this repository ships an exclusion list containing only patterns proven to be read by
      no assertion, and a plan task derives the remaining safe set by mutating a candidate and
      re-running the suite.
- [ ] R-12 — a harness assertion checks that every pattern in this repository's exclusion list
      matches at least one path that exists today, count-guarded so an empty list cannot pass
      vacuously.
- [ ] R-13 — every new assertion is seen RED against a declared plant, in both directions: an
      excluded path and a non-excluded one.
- [ ] R-14 — the ceiling decision is recorded in an ADR, and the producer/consumer drift between the
      deployed and staged `settings.json` is filed against #309 rather than fixed in this feature.
