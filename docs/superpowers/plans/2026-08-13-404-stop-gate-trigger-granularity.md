# Implementation plan — bound the stop-gate trigger to the changed paths

- **Issue:** #404. Files a finding against #309; fixes nothing there.
- **SPEC:** `SPEC.md` (topic slug `404-stop-gate-trigger-granularity`)
- **ADR:** `docs/architecture/ADR-0137-404-stop-gate-trigger-granularity.md`
- **Stack:** Bash 3.2 hooks + `jq`, the existing `staging/plugin/scripts/tests/*.test.sh` harness,
  plants per ADR-0108. No runtime code, no new dependency, no schema change.

## Files this plan touches

| Path | Action |
|---|---|
| `staging/plugin/scripts/tests/stop-gate-path-predicate.test.sh` | **create** (harness, tester-owned) |
| `staging/plugin/scripts/mark-dirty.sh` | modify — record the path instead of discarding it |
| `staging/plugin/scripts/stop-gate.sh` | modify — exclusion predicate, ceiling file, timeout counter |
| `.claude/test-ignore` | **create** — this repository's day-one list |
| `.github/workflows/docs-ci.yml` | modify — one name in the `shell-tests` list |
| `docs/architecture/ADR-0137-…md` | modify — one line, the follow-up issue number (Task 9) |

**Not touched, deliberately:** `.claude/test-cmd` (TOFU trust is a content hash; changing it breaks
the pin and is out of scope — ADR-0137 §D10), `.gitignore` (no `.claude/test-timeout` is created, so
an ignore rule for it would be an exemption covering nothing — CLAUDE.md rule 9),
`staging/user/settings.json` and the deployed `~/.claude/settings.json` (#309's mechanism —
ADR-0137 §D9), `staging/sync-to-claude.sh` (both hooks already carry `PAIRS` entries; the new harness
is one directory below `pairs-completeness.test.sh`'s population and needs none),
`staging/plugin/scripts/tests/run-hook-tests.sh` (its existing assertions are satisfied unchanged —
verify, do not edit), `PROJECT.md` (#404 has no roadmap row; that is known and is not this feature's
job), `hook-hardening.test.sh` (ADR-0137 §D8).

## Ownership, and why it is split

`test-write-scope.sh` (ADR-0088) denies a **coder** any write under a path component named `tests/`.
Tasks 1, 4, 6a and 7 write `staging/plugin/scripts/tests/stop-gate-path-predicate.test.sh` and must
be dispatched to the **tester**. Tasks 2, 3, 5, 6b, 8 and 9 write hooks, a repository-root file, the
CI workflow and the ADR, none of which sit under `tests/` — **coder**. Do not merge the owners inside
a task; where a task has both, its sub-steps say which is which.

## Batching and the expected reds (ADR-0101)

Rule 1 outranks rule 2: an assertion must not sit in the same batch as the task that greens it, even
though that leaves an intermediate checkpoint red. Every red below is **declared in advance**.
Anything else halts.

| Batch | Tasks | Agent | Expected checkpoint state |
|---|---|---|---|
| A | 1 | **tester**, plus one **coder** sub-step for `docs-ci.yml` | RED: `SGP01`–`SGP09`. Green at Tasks 2–3 |
| B | 2, 3 | **coder** | GREEN for `SGP01`–`SGP09` |
| C | 4 | **tester** | RED: `SGP10`–`SGP14`. Green at Task 5 |
| D | 5 | **coder** | GREEN for `SGP01`–`SGP14` |
| E | 6 | **tester** (6a) then **coder** (6b) | GREEN for the whole file; `SGP17` SKIPs in a sandbox |
| F | 7 | **tester** | GREEN, plus `plant-check.sh` reporting every new plant fired |
| G | 8 | **coder** | GREEN; the list may gain patterns, in which case `SGP16`/`SGP17` must stay green |
| H | 9 | **coder** | GREEN |

## Assertion ids

`SGP01`…`SGP18` plus `SGPZ1`. **Two digits from the start, deliberately:** `plant-check.sh` decides a
plant fired with `grep -q "^FAIL: $aid"`, a **prefix** match, so `SGP1` would be satisfied by `SGP10`
failing. No `SGP1b`-style suffixes, for the same reason. The harness must emit `FAIL: <id>` with the
colon or every plant in it is unattributable — `plant-check.sh` rejects such a harness outright.

## The fixture rig, used by Tasks 1, 4 and 6

One helper, built once in Task 1 and reused: given a list of recorded paths, an optional
`.claude/test-ignore` body and an optional `.claude/test-timeout` body, it builds an `mktemp -d`
project root containing `.claude/test-cmd` whose command touches a **sentinel** file, pre-approves
that `test-cmd` in a fixture trust file (`STOP_GATE_TRUST_FILE`, the technique
`hook-hardening.test.sh` already uses), writes the marker into a fixture `STOP_GATE_STATE_DIR`, and
pipes a synthetic `Stop` payload into `staging/plugin/scripts/stop-gate.sh`.

**Sentinel present ⇒ the suite ran. Sentinel absent ⇒ it did not.** That is a positive observation of
each direction, not an inference from silence — the gate exits 0 on both the excluded path and
several fail-open paths, so exit code alone cannot tell them apart.

---

### Task 1 — The path-predicate harness, written against the pre-fix hooks (R-01, R-02, R-03, R-06, R-07, R-08)

Create `staging/plugin/scripts/tests/stop-gate-path-predicate.test.sh`. Hermetic, no `$HOME`
dependency, bash 3.2, `set -u`, `ok`/`bad` emitting `PASS: <id>` / `FAIL: <id>`. Resolve the repo from
`$(dirname "$0")` so a `plant-check.sh` sandbox copy redirects with no change.

**Header must state:** the rule the file enforces; that it is written against the pre-fix files on
purpose and which assertions are RED at this checkpoint; the two-digit id convention and its reason;
and the derived-guard instance number. **Re-derive that number from the files, do not copy it from
the ADR** — the ADR says 16 and the previous harness caught its own plan proposing an already-claimed
number. Grep every `staging/plugin/scripts/tests/*.sh` header for a literal instance claim first.

- [ ] `SGP01` — every recorded path matches the list ⇒ **sentinel absent**. The excluded direction.
      (R-01)
- [ ] `SGP02` — two recorded paths, one matching and one not ⇒ **sentinel present**. The list
      excludes, never includes; one unknown path is enough to arm. (R-03)
- [ ] `SGP03` — no `.claude/test-ignore` at the root, one recorded path ⇒ sentinel present. The
      inert state is today's. (R-02)
- [ ] `SGP04` — a marker that exists and holds **no** paths ⇒ sentinel present. Covers a session
      started under the old `mark-dirty.sh` and a payload with no `file_path`. (R-02, R-06)
- [ ] `SGP05` — list grammar: blank lines and `#`-comment lines are skipped; a list that is empty or
      holds only comments behaves exactly as no list (sentinel present). (R-07)
- [ ] `SGP06` — a trailing-slash pattern matches a directory prefix and only that prefix: a path
      under it is excluded, a sibling directory sharing a name prefix is not. (R-07)
- [ ] `SGP07` — patterns are matched against the path **relative to the discovered root**: the same
      relative pattern excludes under root A and does not accidentally match an identically-named
      path under a different root. (R-07)
- [ ] `SGP08` — a pattern beginning with `/` matches the absolute path, and a `~`-rooted pattern is
      expanded against `$HOME` (set `HOME` to the fixture, do not touch the real one) before that
      test. (R-08)
- [ ] `SGP09` — a recorded path **outside** the discovered root arms the gate when only
      root-relative patterns are present, and is excluded when an absolute pattern covers it. Both
      directions in one assertion pair; the arming half is the R-08 default. (R-08)
- [ ] `SGP18` — **injection**: a list containing a pattern whose text is a command substitution
      touching a canary must leave the canary absent. Verified at design time on bash 3.2.57 (a
      pattern held in a variable is not re-expanded), pinned here because a reviewer will ask and
      because the guarantee is load-bearing for reading a pattern out of a project file.
- [ ] `SGPZ1` — assertion-count floor, **stated at the site as a vacuity guard only** (ADR-0124: a
      floor absorbs its own plant, so per-assertion pinning is the plants' job, not this line's).
      Raise it in the same edit whenever assertions are added.

**Coder sub-step (not the tester):** append `stop-gate-path-predicate` to the `for t in …` list in
`.github/workflows/docs-ci.yml`'s `shell-tests` job. The list is an explicit hand-maintained list of
bare names without the `.test.sh` suffix, not a glob; `.claude/test-cmd` picks the file up
automatically and CI does not. `pairs-completeness.test.sh` `CI1` fails without this line. Do **not**
add a CI-list assertion to the new harness: `CI1` already answers that question and a second answer
would fail in every plant sandbox.

**Record in the task note:** the exact RED output of `SGP01`–`SGP09`. It is the pre-fix evidence and
it is unrecoverable after Task 3.

Budget: `staging/plugin/scripts/tests/stop-gate-path-predicate.test.sh`, `.github/workflows/docs-ci.yml` (~400 lines)

---

### Task 2 — `mark-dirty.sh` records the written path (R-06)

Edit `staging/plugin/scripts/mark-dirty.sh` only. It stays eight-to-thirty lines, fail-open on every
branch, exit 0 always.

- [ ] Read `tool_input.file_path` from the payload with the same `jq` expression
      `post-write-check.sh` uses on the same event. A failed parse yields the empty string and is not
      an error.
- [ ] **Stop truncating.** The current `: > "$DIR/$SID.dirty"` destroys the record on every write.
      Create the marker if absent, then append; never truncate.
- [ ] Append the path only if the file does not already carry that exact line
      (`grep -F -x -q -- "$P"`, with the `--` so a path beginning with `-` is not read as an option).
      Deduplicated, so a long session cannot grow the file without bound.
- [ ] An empty `file_path` records nothing and still creates the marker. Existence keeps its current
      meaning; a marker with no paths arms the gate (asserted by `SGP04`).
- [ ] A path containing a newline cannot be one record line. Write it on one line with newlines
      replaced by spaces and **prefixed with a single space**, so it does not begin with `/`. Nothing
      is discarded and nothing can match a pattern — Task 3 treats any line not beginning with `/` as
      unmatchable. Do not drop the record: R-06 says discards none.

**Checkpoint:** `SGP04` green. Nothing else changes yet.

Budget: `staging/plugin/scripts/mark-dirty.sh` (~30 lines)

---

### Task 3 — `stop-gate.sh` reads the exclusion list and decides (R-01, R-02, R-03, R-04, R-05, R-07, R-08)

Edit `staging/plugin/scripts/stop-gate.sh` only. The new block goes **after** the TOFU trust check
and **before** `run_with_timeout`.

- [ ] The two blocking paths are untouched and must be re-verified, not assumed: no
      `.claude/test-cmd` found still blocks; `test-cmd` present but not TOFU-approved still blocks.
      The exclusion list is read at the same `ROOT` the walk already found — one walk finds both, so
      they cannot diverge in a monorepo. (R-04)
- [ ] Skip the whole block when the list is absent or the marker holds no paths (`[ -s ]`), so the
      inert state is today's exactly. (R-02)
- [ ] For each recorded line: a line not beginning with `/` is **unmatchable** — the gate arms and
      the loop stops. Compute the root-relative form with the bash 3.2-safe quoted strip
      `${p#"$ROOT"/}` (verified on 3.2.57 against a `ROOT` containing a glob metacharacter); a path
      outside `ROOT` has no relative form and only an absolute pattern can exclude it. (R-08)
- [ ] For each pattern: skip blank and `#`-leading lines; expand a leading `~` against `$HOME`; a
      pattern ending in `/` gains a trailing `*`; a pattern beginning with `/` after that expansion
      matches the absolute recorded path, everything else matches the relative form. Match with
      `case "$target" in $pat)` — unquoted, so it is a glob, and safe because bash does not re-expand
      the result of an expansion. (R-07, R-08)
- [ ] Fire when **at least one** recorded path is unexcluded. Exit 0 only when every one is, and
      leave the marker in place — a skipped turn must not clear the record. The record is cleared on
      a green run and only there, by the existing single `rm -f "$DIRTY"`. (R-01, R-03, R-05)
- [ ] On the decline branch, emit **one** stderr line naming the count of excluded paths and the list
      that excluded them. A guard that stops guarding must be visible; this is the only new output on
      the arming side of the hook. (R-01)
- [ ] Keep the fail-open philosophy: an unreadable list, an unreadable marker or any internal error
      arms rather than declines.

**Checkpoint:** `SGP01`–`SGP09` and `SGP18` green. Re-run `bash staging/plugin/scripts/tests/run-hook-tests.sh`
against the deployed copies **after** a later sync, not now — it is `$HOME`-coupled and tests
`~/.claude/hooks/`, so it is unaffected until Task 9's sync note is acted on.

Budget: `staging/plugin/scripts/stop-gate.sh` (~70 lines)

---

### Task 4 — The ceiling and timeout-counter assertions, written against the pre-fix file (R-09, R-10)

Extend `staging/plugin/scripts/tests/stop-gate-path-predicate.test.sh`. Tester-owned. Reuse the
Task 1 rig; a fixture `test-cmd` that sleeps longer than the fixture ceiling produces a real timeout,
so keep the fixture ceilings at one or two seconds.

- [ ] `SGP10` — absent ceiling file ⇒ 120 seconds exactly. Assert the value the hook uses, not the
      elapsed time: pin it through an observable (a fixture command that reports the timeout it was
      given, or the stderr line), never by timing a 120-second sleep. (R-09)
- [ ] `SGP11` — a valid ceiling file overrides the default; `STOP_GATE_TEST_TIMEOUT` overrides the
      file. Both directions of the precedence, in one assertion pair. (R-09)
- [ ] `SGP12` — a malformed value (empty, non-numeric, negative, zero) and a value above the stated
      maximum both fall back to 120 **and say so on stderr**. Two halves: the fallback and the
      report. R-09 requires both. (R-09)
- [ ] `SGP13` — a timeout increments `<sid>.count`. Below the cap the marker survives, as today.
      (R-10)
- [ ] `SGP14` — at `STOP_GATE_MAX_REENTRY` consecutive timeouts the marker is **removed** and a
      stderr line names the reason. Set `STOP_GATE_MAX_REENTRY` low in the fixture so the assertion
      costs seconds, not minutes. (R-10)
- [ ] Assert in the **negative direction too**: exit code 127 (command not found) keeps today's
      message and does **not** increment the counter. Without this the increment could be written on
      the whole 124–127 branch and every positive assertion would still pass. (R-10)
- [ ] Raise `SGPZ1` in this same edit. Slack in a floor equals the number of assertions that can
      vanish silently.

**Checkpoint:** `SGP10`–`SGP14` RED. Record the exact output in the task note.

Budget: `staging/plugin/scripts/tests/stop-gate-path-predicate.test.sh` (~160 lines)

---

### Task 5 — The ceiling file, and a timeout that counts (R-09, R-10)

Edit `staging/plugin/scripts/stop-gate.sh` only.

- [ ] Read `.claude/test-timeout` at the same `ROOT`. Precedence: a valid `STOP_GATE_TEST_TIMEOUT`
      wins over the file; the file wins over the default 120. The environment variable stays
      unbounded — bounding it would change existing behaviour and it is the caller's own lever.
      (R-09)
- [ ] Bound the **file** value at a stated maximum of 900 seconds. A value that is not a positive
      integer, or is above the maximum, falls back to 120 and emits one stderr line naming the value
      it rejected and the value it used. Do not fall back to whatever `case` happens to accept.
      (R-09)
- [ ] The ceiling is **not** part of the TOFU hash. Do not touch `sha256_of`, `TCF` or the trust
      line — a ceiling is a bound, not a command. (R-09)
- [ ] Split the current `124|125|126|127` branch. **124 only** increments `<sid>.count`, using the
      same read-and-validate idiom `emit_block` uses (a non-numeric file reads as 0). Below the cap:
      one stderr line naming the ceiling and the attempt number, then exit 0 as today. At or above
      `STOP_GATE_MAX_REENTRY`: `rm -f "$DIRTY"` and one stderr line naming the disarm and its reason.
      (R-10)
- [ ] 125, 126 and 127 keep today's message and do not increment. State the reason in a comment at
      the site: the counter bounds *cost*, and those exit instantly. (R-10)
- [ ] Still exit 0 on every path; still `rm -f "$OUT"`.

**Checkpoint:** the whole file green except `SGP15`–`SGP17`, which do not exist yet.

Budget: `staging/plugin/scripts/stop-gate.sh` (~55 lines)

---

### Task 6 — This repository's list, and the check that keeps it honest (R-11, R-12)

**6a (tester)** — extend the harness with the subject check. The corpus is derived, and the
derivation is count-guarded: tracked paths from `git ls-files` (657 today) union individually-listed
ignored paths from `git status --porcelain --ignored=matching` (93 today, 53 under `.remember/`,
10 `.bak`). `--ignored=matching` is required: plain `--ignored` collapses a wholly-ignored directory
into one entry and the corpus loses every file inside it.

The check **proposes with a prefilter and confirms through the hook** (ADR-0137 §D7): a `case`-based
scan over the corpus proposes one candidate path per pattern; the Task 1 rig then confirms it by
running the real `stop-gate.sh` with a fixture list holding only that pattern. Never a second
independent matcher.

- [ ] `SGP15` — **fixture pair**, runs everywhere including a plant sandbox: a fixture corpus plus a
      fixture list holding one pattern with a subject and one deliberate typo. The typo is reported,
      the good pattern is not. This is the planted half of the mechanism. (R-12)
- [ ] `SGP16` — **live**, count guard on the denominator: the tracked corpus is at least 300 entries
      and this repository's list holds at least one non-comment pattern. Zero candidates is a broken
      derivation and must not read as coverage; an empty list must not pass vacuously. (R-12)
- [ ] `SGP17` — **live**, three outcomes per pattern (CLAUDE.md rule 4): matches a corpus member ⇒
      PASS; matches nothing and a representative path synthesised from the pattern is **not** ignored
      by this repository's `.gitignore` ⇒ **FAIL** (the typo case, loud in CI); matches nothing and
      the representative **is** ignored ⇒ **SKIP** with a line naming the reason, because a fresh
      checkout cannot exhibit a runtime artefact. Verified at design time: representatives for
      `*.bak` and `.remember/logs/` classify ignored, a mistyped `.rember/logs/` does not. Synthesis
      is mechanical and a wrong synthesis produces the FAIL branch, never the PASS branch. (R-12)
- [ ] Gate `SGP16`/`SGP17` on the repository being a real git checkout (`[ -d "$REPO/.git" ]`) and
      print an explicit SKIP line otherwise — a `plant-check.sh` sandbox copies `staging/` and
      `docs/` and no `.git`, and a check that cannot see its subject must not report a defect about
      it. Record in the harness header that these two are **unplantable by construction**, following
      `triage-state-gitignore.test.sh`'s precedent for live repository-root content.
- [ ] Raise `SGPZ1` again in this same edit.

**6b (coder)** — create `.claude/test-ignore` at the repository root: a header stating the semantics
(shell globs, one per line, `#` comments and blank lines skipped, relative to this root, trailing
slash means directory prefix, a leading `/` or `~` means absolute) and a pointer to ADR-0137, then
the three day-one patterns `.remember/logs/`, `*.bak`, `*.bak-*`. Nothing else — every other pattern
waits for Task 8's evidence. The file is tracked; add no `.gitignore` entry. (R-11)

**Checkpoint:** whole file green locally; `SGP17` reports three SKIPs here and would report three
SKIPs in CI, which is expected and is stated in its own message.

Budget: `staging/plugin/scripts/tests/stop-gate-path-predicate.test.sh`, `.claude/test-ignore` (~170 lines)

---

### Task 7 — Plants: every new assertion seen RED, in both directions (R-13)

Extend the harness with `# plant:` declarations at **column 1** (an indented one is silently skipped
by the collector) and run `bash staging/plugin/scripts/tests/plant-check.sh`. A needle must match
**exactly once** in its target; a ` | ` sequence cannot appear inside a field.

- [ ] `SGP01` — target `plugin/scripts/stop-gate.sh`, neutralise the decline branch's exit so an
      all-excluded session runs the suite anyway. The **excluded** direction. (R-13)
- [ ] `SGP02` — target `plugin/scripts/stop-gate.sh`, neutralise the "one unexcluded path arms"
      escape so everything reads as excluded. The **non-excluded** direction. R-13 requires both and
      neither alone is evidence. (R-13)
- [ ] `SGP09` — target `plugin/scripts/stop-gate.sh`, make an absolute pattern match the relative
      form. Pins the R-08 branch specifically; the `SGP01`/`SGP02` plants walk straight past it.
- [ ] `SGP12` — target `plugin/scripts/stop-gate.sh`, remove the maximum bound so an over-max file
      value is accepted.
- [ ] `SGP14` — target `plugin/scripts/stop-gate.sh`, neutralise the timeout increment.
- [ ] `SGP04` — target `plugin/scripts/mark-dirty.sh`, neutralise the append so paths are never
      recorded.
- [ ] `SGP15` — **self-targeting** the harness file, neutralise the corpus derivation so it yields
      nothing; the count guard must fire. `plant-check.sh` masks `# plant:` lines before
      substituting, so a self-targeting plant is supported and its own declaration cannot satisfy it.
- [ ] Verify each plant is *usable* as well as firing: `PC2` rejects a target that does not exist, a
      needle matching zero or many sites, and a harness that does not emit the `FAIL: <id>` prefix.
      A plant nobody validated is worth as much as an assertion nobody planted.
- [ ] **Record in the task note** which assertions carry no plant and why: `SGP16` and `SGP17`
      (unplantable — live repository-root content outside the sandbox), `SGP03`, `SGP05`–`SGP08`,
      `SGP10`, `SGP11`, `SGP13`, `SGP18` (covered transitively by the plants above; say so rather
      than implying full per-assertion coverage).

Note the cost: `plant-check.sh` re-runs the declaring file once per plant and already exceeds
25 minutes at 343 plants. Seven more is a few minutes on this file alone.

Budget: `staging/plugin/scripts/tests/stop-gate-path-predicate.test.sh` (~20 lines)

---

### Task 8 — Derive the remaining safe set by mutation, and record the verdict (R-11)

**This is the only method that proves anything**: mutate a candidate path, re-run the full suite, keep
the candidate only if **no assertion moves**. A grep for path literals over the test files
over-states real-repository reads, because it counts strings written into temporary fixtures — the
SPEC records 146 apparent `docs/manifests` mentions, 107 `PROJECT.md` and 74 `CLAUDE.md` for exactly
that reason, and none of those counts is usable as evidence.

Each run costs **2m43s** measured on this machine. Budget four runs plus contingency, roughly 15–25
minutes of wall clock. This task is a measurement, not an edit; its deliverable is the record, and
"nothing further proved safe" is a complete and expected result.

- [ ] Baseline first: run `.claude/test-cmd` unmutated and record the pass count. Without a baseline
      a moved assertion is indistinguishable from a pre-existing failure.
- [ ] Candidate A — `docs/manifests/*.manifest.yml`. Expected **unsafe**; run it anyway, because it
      is the single highest-frequency write in a chain session and confirming the SPEC's third
      measurement empirically is worth one run.
- [ ] Candidate B — `TODO.md`. Unmeasured; one run.
- [ ] Candidate C — `docs/books/`. Expected safe; note that
      `docs/books/INTEGRATION-REPORT-agentic-spec.md` is tracked while the rest of the directory is
      ignored, so mutate the tracked file, which is the strict direction.
- [ ] Candidate D — the ignored `.claude/` runtime artefacts (`agent-memory-local/`,
      `autopilot-state/`, `.triage-fix-last*.json`), batched into one run by mutating one
      representative of each. If any assertion moves, bisect — and pay the extra runs rather than
      discarding the batch.
- [ ] **Restore after every run, and verify the restore before the next one.** Use `git checkout --`
      for tracked files and a saved copy for ignored ones. A mutation left in place makes every later
      run measure the wrong thing.
- [ ] Add to `.claude/test-ignore` only the candidates that moved nothing, each with a one-line
      comment naming the date of the run that proved it. If a candidate is added, re-run the harness:
      `SGP16` and `SGP17` must stay green, and a newly added pattern with no subject in this checkout
      must classify into the SKIP branch, not the FAIL branch.
- [ ] Record the full table (candidate, verdict, evidence) in the task note **and** in a comment
      block at the head of `.claude/test-ignore`, so the next person to widen the list starts from
      evidence instead of repeating the measurement.

---

### Task 9 — File the producer/consumer drift against #309, and the sync note (R-14)

- [ ] `gh issue create` in `istefox/vibe-coding-system`, referencing #309 and #404. Body states the
      measurement: the deployed `~/.claude/settings.json` registers exactly one `Stop` hook,
      `chat-done-notify.sh`; `staging/user/settings.json` registers exactly one, `stop-gate.sh`;
      **neither file is a superset of the other**, so the drift runs in both directions.
      `mark-dirty.sh` is registered in both, so the producer has been running against an unwired
      consumer — 71 `.dirty` markers, oldest 2026-06-20, none ever removed. Say explicitly that this
      feature is **inert until settings.json is synced** and that re-registering the hook by hand is
      the practice #309 exists to end. (R-14)
- [ ] Add the new issue number to ADR-0137 §D9 as a one-line forward reference. Do not restate the
      finding there; the issue carries it. (R-14)
- [ ] **Note, do not perform:** `staging/sync-to-claude.sh --apply` is what carries the two edited
      hooks to `~/.claude/hooks/`. Both files already have `PAIRS` entries, so no table edit is
      needed. Running it is the operator's call at the HITL gate; state in the task note that
      `run-hook-tests.sh` (which tests the deployed copies and is `$HOME`-coupled) should be re-run
      immediately after, and that its existing assertions are expected to pass unchanged.

Budget: `docs/architecture/ADR-0137-404-stop-gate-trigger-granularity.md` (~5 lines)

---

## Verification before Gate 5

- `.claude/test-cmd` green, whole suite, 78 files plus the new one.
- `bash staging/plugin/scripts/tests/plant-check.sh` — every declared plant fired, `PC0`–`PC4` green.
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — `CI1` green, proving the
  `docs-ci.yml` append landed.
- A contract changed here: the `<sid>.dirty` marker's **content** (empty file ⇒ newline-separated
  path list) and `stop-gate.sh`'s timeout branch. Grep for consumers of both across the whole tree
  before declaring done. Measured at design time: `run-hook-tests.sh` is the only other reader of the
  marker, and it tests only for the file's existence, which is preserved. **Run the full suite, not
  just the new file** — a contract change can break assertions in modules that share it.

TEST-CMD CANDIDATE: none
TEST-CMD MODE: brownfield

EXTERNAL DEPENDENCY: GitHub issues API via the `gh` CLI | api | provisioned: true
