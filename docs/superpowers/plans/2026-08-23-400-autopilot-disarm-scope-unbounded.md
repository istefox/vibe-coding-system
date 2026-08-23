# Implementation plan — disarm clears guard state; the launch decides whether a bound is spent

- **Issue:** #400 (from `TODO.md` `VCS-018`; live incident in `VCS-020`)
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md` (R-01 … R-08)
- **ADR:** `docs/architecture/ADR-0167-400-autopilot-disarm-scope-unbounded.md`
- **ARCH:** n/a — a scoped bugfix inside an already-documented system.
- **Stack:** Bash 3.2 (macOS `/bin/bash`) and POSIX `awk`/`sed`/`grep`. No `mapfile`, no associative
  arrays, no `${var^^}`/`${var,,}`, no `[[ ]]`, no process substitution. One new script, one new
  harness, two existing harnesses edited, two `SKILL.md` files, one RUNBOOK, one PAIRS entry, one CI
  loop entry.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`

TEST-CMD MODE: brownfield

This feature has no external dependency: no third-party API, no OAuth or consent flow, no cloud
console, no externally provisioned resource. Every file it touches is in this repository.

---

## Read this first — the ADR is 0167

Highest on `main` at `550e188` is ADR-0166; ADR-0165 is in this branch's history. Use **0167**. Do
not add a twenty-first `CLAUDE.md` rule — this feature introduces no new invariant, only instances
of rules 4, 5, 6, 11 and 17.

## Read this second — the state measured before any work (rule 13)

Re-derived 2026-08-23 on `feat/470-chain-never-regenerates-xcode`. **Re-derive it, do not trust this
block.**

```text
autopilot-disarm.sh clear loop:   7 files    (4 guard, 2 config/progress, 1 debris)
readers of  .../scope:            2          (check 9 writes it; conductor-scope-gate reads it)
readers of  .../published:        2          (conductor-scope-gate, conductor-published-skip)
writers of  .../published:        1          (project-conductor Step 5)
assertions pinning OLD behaviour: 3          KB5, D1, D2
plants whose needle dies:         2          KB5, KB6  (needle: "$SDIR/rtf-blocker" "$SDIR/scope")
assertion-id prefix DP:           FREE       (0 hits across staging/, incl. plant declarations)
autopilot-guard-disarm.test.sh:   Z1 floor >= 41
```

## Read this third — the observable contract changes, and where the old one is asserted

This feature inverts an observable contract: **`autopilot-disarm.sh` stops removing
`.claude/autopilot-state/scope` and `.claude/autopilot-state/published`.** Three live assertions and
two plant declarations encode the old behaviour. They were found by grepping
`autopilot-state/scope`, `autopilot-state/published` and `removed:` across the repo; **do not go
looking for more, and do not skip any of these.**

| Where | What it asserts today | Required change |
|---|---|---|
| `staging/plugin/scripts/tests/autopilot-run-scope.test.sh` `KB5`, in section `KB` (fixture `mk_root kb56`) | `[ ! -f "$R/.claude/autopilot-state/scope" ]` — the scope file **is** cleared | **Invert.** Task 3. |
| same file, `# plant: KB5`, in the top-of-file plant block | needle `"$SDIR/rtf-blocker" "$SDIR/scope"` | Needle dies with the loop edit → `BADPLANT`. Re-anchor. Task 3. |
| same file, `# plant: KB6`, same block | same needle, for a still-valid assertion | Re-anchor only; `KB6`'s assertion stays as-is. Task 3. |
| `staging/plugin/scripts/tests/autopilot-guard-disarm.test.sh` `D1`, in section `D` (fixture `mk_root d1`) | `for f in active build-status rtf-blocker scope started-at` must all be gone | Drop `scope` from the loop; add the inverse. Task 3. |
| same file, `D2`, same fixture | `grep -c 'removed:'` **>= 6** | Becomes 5 on that fixture → red. Task 3. |
| same file, `# plant: D1`, top-of-file plant block | needle `"$SDIR/started-at" "$ROOT/.claude/needs-human"; do` | Survives if the loop keeps that adjacency. **Verify with `plant-check.sh`, do not assume.** Task 9. |

**Run the FULL suite after Task 2, not just the two autopilot harnesses.** A contract change can
break a harness in an unrelated module that shares the contract; `pairs-completeness.test.sh` in
particular goes red the moment the new harness exists without its CI loop entry (Task 5).

## Read this fourth — this feature's own coverage gate is not evidence about this feature

Both harnesses this plan names by basename cite `ADR-0112` and `ADR-0129`, which this plan also
cites, so under ADR-0154's conjunction they scope in — and both are full of `R-01`…`R-08` tokens
belonging to issues #321, #323 and #365. Several of this feature's own ids will report `COVERED`
before a line of it exists. That is ADR-0154 §D7 class 1 and this feature does not fix it.
**The evidence is each `DP` assertion going RED against its declared plant (Task 9), never the
gate's verdict.**

## Files this plan touches

| File | Owner | What changes |
|---|---|---|
| `staging/plugin/scripts/autopilot-disarm.sh` | coder | clear loop loses 2 entries; `preserved:` block; bound summary |
| `staging/plugin/skills/autopilot/scripts/scope-file-read.sh` | coder | **create** — the REPORTER |
| `staging/plugin/skills/autopilot/SKILL.md` | coder | Phase S fence (`autopilot-scope-args`), check 9 fence (`autopilot-scope-resolve`), §1.3 routing prose, §1.5 Phase P skip |
| `staging/plugin/skills/project-conductor/SKILL.md` | coder | **prose only**, Step 2 — no fence body, no exit code, no plant needle |
| `docs/RUNBOOK-autopilot.md` | coder | "Aborting a run"; "The guard is still armed…" |
| `staging/sync-to-claude.sh` | coder | one PAIRS entry |
| `.github/workflows/docs-ci.yml` | coder | one name in the harness loop |
| `staging/plugin/scripts/tests/autopilot-disarm-scope-preserve.test.sh` | **tester** | **create** — the `DP` section |
| `staging/plugin/scripts/tests/autopilot-guard-disarm.test.sh` | **tester** | `D1`, `D2`, new `D6`/`D7` |
| `staging/plugin/scripts/tests/autopilot-run-scope.test.sh` | **tester** | `KB5` inverted, `KB5`/`KB6` plants re-anchored |
| `docs/chain-decisions.md`, `docs/chain-decision-index.md`, `PROJECT.md`, `TODO.md` | coder | the record |

Everything under `staging/plugin/scripts/tests/` is **tester-owned** — `test-write-scope.sh` denies
the coder any write there. Files under `staging/` are mode 644: run them as `bash <path>`.

## Assertion ids and the harness contract

New assertions use the **`DP`** prefix (verified free 2026-08-23: `grep -rnoE '"DP[0-9]' staging/`
→ no match). New assertions in the two existing harnesses extend their existing `D` and `KB`
sections.

`staging/plugin/scripts/tests/autopilot-disarm-scope-preserve.test.sh` **must contain both
`ADR-0167` and the string `2026-08-23-400-autopilot-disarm-scope-unbounded` in its header**, or
`spec-coverage.sh` descopes it as a precedent citation and this feature's ids report `UNSCOPED`
(ADR-0154). Every block carries an id-mapping comment: `# DP4/DP5 (R-02, R-08) — …`.

The harness is offline, hermetic, no network, no `$HOME` dependency, targets `staging/` directly,
and ends with the repo's standard `PASS=`/`FAIL=` line and a `Z`-prefixed assertion floor.

---

## Task 1 — TEST: the disarm preserves configuration and progress, and still clears guard state (R-02, R-03, R-08)

Owner: **tester**. Create `staging/plugin/scripts/tests/autopilot-disarm-scope-preserve.test.sh`.
Every assertion below is RED until Task 2.

- [ ] `DP1` — fixture: a foreign-session root (`arm "$R" session-AAA`, disarm as `session-BBB`, the
      RECOVERY path) carrying all seven files. After `bash "$DISARM" "$R"`: `scope` and `published`
      **still exist**, byte-identical to what was written.
- [ ] `DP2` — the mirror, same fixture through `--completing` from the **owning** session. Both
      files survive there too. ADR-0167 §A2 rejects the mode split; this assertion is what stops it
      being reintroduced as a "small" fix.
- [ ] `DP3` (R-03) — same fixture: `active`, `build-status`, `rtf-blocker`, `started-at` and
      `.claude/needs-human` are **all gone**, and `bash autopilot-guard.sh --check "$R"` exits 0
      afterwards. This is ADR-0112's behaviour asserted from inside the feature that changes the
      file, so a partial disarm of the guard set cannot ship unnoticed.
- [ ] `DP4` (R-08) — the output names each surviving file on a `preserved:` line, with the bound:
      `preserved: .claude/autopilot-state/scope (features=3, only=2 rows)` and
      `preserved: .claude/autopilot-state/published (2 delivered)`.
- [ ] `DP5` (R-08) — **the reverse direction** (rule 8): neither `scope` nor `published` ever
      appears on a line beginning `removed:`. Assert on the `removed:` lines' own text, not on a
      whole-output grep — the paths appear in the `preserved:` lines and a naive scan is satisfied
      by those (rule 12).
- [ ] `DP6` (R-08) — the `preserved:` block prints in the **`NOTHING-ARMED`** branch too: a root
      with `scope` and `published` and no guard files at all exits 0, prints `NOTHING-ARMED`, and
      still names both preserved files.
- [ ] `DP7` (R-08) — the output names the override: a relaunch with no `--features`/`--only` reuses
      the bound, passing either replaces it. Match a **flattened, undecorated, case-insensitive**
      copy (rule 3).
- [ ] `DP8` — a `scope` file at mode 000 (skip the case if the harness runs as root and `[ -r ]`
      still succeeds — the established idiom in `autopilot-run-scope.test.sh` section `CG`) still
      leaves the disarm at **exit 0**, printing `preserved: … (bound unreadable)`. A disarm must not
      fail on a file it is not touching.

Budget: `staging/plugin/scripts/tests/autopilot-disarm-scope-preserve.test.sh` (~230 lines)

## Task 2 — CODE: `autopilot-disarm.sh` clears guard conditions only (R-02, R-03, R-08)

Owner: **coder**. Turns Task 1 green. Minimal diff — this file's header is load-bearing prose and
most of it stays.

- [ ] Remove `"$SDIR/scope"` and `"$SDIR/published"` from the `for f in …` loop. Keep the remaining
      five in their current order and keep `"$SDIR/started-at" "$ROOT/.claude/needs-human"; do`
      **adjacent** — `# plant: D1`'s needle is that exact substring.
- [ ] Replace the two paragraph-comments above the loop (the `published` one and the `scope` one)
      with the §D1 rule: this loop clears **guard conditions**, not the run's configuration or its
      progress, because disarm cannot tell a paused run from a finished one. Name ADR-0167 and
      issue #400. Do not delete the ADR-0112 rationale above them — it still explains the five that
      remain.
- [ ] Add a `PRESERVED` accumulator built the same way `CLEARED` is (a leading-newline string, drained
      through `printf '%s\n' … | sed '/^$/d'`), covering `$SDIR/scope` and `$SDIR/published` when
      present.
- [ ] Bound summary, **best-effort and failure-proof**: for `scope`, `features=` via
      `grep '^features=' … | head -1 | sed …` and the `only=` count via `grep -c '^only='` guarded
      with `|| true` (never `|| echo 0` — that yields a two-line `0\n0` on no match, rule 5). For
      `published`, `grep -c . … 2>/dev/null || true`. Unreadable or empty → `(bound unreadable)`.
      **No exit-3 path may be added here.**
- [ ] Print the `preserved:` block plus the one-line override hint in **both** terminal branches —
      after `DISARM: CLEARED` and after `DISARM: NOTHING-ARMED` — before the existing
      `autopilot-guard is now inert…` line.
- [ ] Bump the header version line and add the one-line changelog entry, the form every other
      version bump in this file uses.

Budget: `staging/plugin/scripts/autopilot-disarm.sh` (~60 lines changed)

## Task 3 — TEST: repair the three assertions and two plants that pin the old contract (R-02, R-03, R-08)

Owner: **tester**. These are green today and go red at Task 2. **Repair, never weaken** — each
inverted assertion keeps an equally strong claim pointed the other way, and rule 19 requires a
comment where a deleted assertion stood, naming the issue and the ADR.

- [ ] `autopilot-run-scope.test.sh` `KB5` — invert: the `scope` file **survives** the disarm.
      Leave a comment at the site: `KB5 was "a scope file is cleared by autopilot-disarm.sh"
      (issue #365, ADR-0129 §D1); inverted by issue #400, ADR-0167 §D1`. Keep the message text
      specific enough that a future reader sees which direction it now runs in.
- [ ] `autopilot-run-scope.test.sh` `# plant: KB5` and `# plant: KB6` — the needle
      `"$SDIR/rtf-blocker" "$SDIR/scope"` no longer exists, so `plant-check.sh` reports **BADPLANT**
      (needle matched 0 times; it requires exactly 1). Re-anchor both onto a needle that exists
      after Task 2 and that each assertion genuinely depends on. `KB6`'s assertion (token-budget
      survives) is unchanged; only its plant moves.
- [ ] `autopilot-guard-disarm.test.sh` `D1` — drop `scope` from the `for f in …` presence loop, and
      add `D6`: on the same fixture, `scope` and `published` are still present. `D1`'s own message
      ("the whole transient set is cleared") must be reworded to "the whole **guard** set" — an
      assertion whose message describes the superseded contract is how the next reader re-breaks it.
- [ ] `autopilot-guard-disarm.test.sh` `D2` — `>= 6` becomes an **exact 5** for this fully
      controlled fixture. Rule 10: a floor absorbs its own plant, and this one has no slack to
      justify staying a floor. Add `D7`: no `removed:` line names `scope` or `published`.
- [ ] Do **not** touch `Z1`'s `>= 41` floor — assertions are being added, not removed.

Budget: `staging/plugin/scripts/tests/autopilot-run-scope.test.sh` (~40 lines), `staging/plugin/scripts/tests/autopilot-guard-disarm.test.sh` (~30 lines)

## Task 4 — TEST: the `scope-file-read.sh` reporter contract, and the differential against `conductor-scope-gate` (R-01, R-05, R-06)

Owner: **tester**. Extends the new harness. RED until Task 5.

- [ ] `DP10`–`DP15` — one assertion per `state=`, driving the script directly with a built fixture
      root: `ABSENT`, `REUSABLE`, `SPENT`, `NOT-REUSABLE` (once for `source=marker`, once for
      `source=none`), `MALFORMED`, `UNREADABLE`.
- [ ] `DP16` (rule 5) — **it is a REPORTER**: every one of those six states exits **0**. Assert the
      exit code on all six, not just the interesting ones. A reporter that exits non-zero on one
      state is a checker nobody branched on.
- [ ] `DP17` (rule 5) — `ABSENT` is this reporter's `CLEAN`: it prints `state=ABSENT` on stdout
      rather than printing nothing, so a caller writing `[ -n "$out" ]` cannot read "no file" as
      "some state".
- [ ] `DP18` — bad invocation (no root) exits **2**, and no argument shape produces exit 3. Rule 4's
      distinction lives at the *caller* here (Task 6's `DP24`), not in this script.
- [ ] `DP19` (R-05) — `SPENT` boundary: `features=3` with 2 delivered is `REUSABLE`, with 3 is
      `SPENT`, with 4 is `SPENT`. Assert all three; an off-by-one here is a silent no-op night.
- [ ] `DP20` (R-05) — `features` absent, `only=` rows present: `SPENT` only when **every** row is in
      `published`; `REUSABLE` when one is missing.
- [ ] `DP21` (rule 17) — **the differential.** Over a fixture matrix (at least: bounded-unstarted,
      bounded-partial, bounded-exhausted, only-list-partial, only-list-complete), assert
      `scope-file-read.sh`'s `SPENT`/`REUSABLE` verdict agrees with `conductor-scope-gate`'s
      `EXHAUSTED`/not-`EXHAUSTED` exit. Drive the gate through the harness's existing
      `run_fence "conductor-scope-gate" …` helper (see `autopilot-run-scope.test.sh` section `CG`
      for the call shape and the `export`ed free variables). ADR-0167 §D6 keeps two copies of this
      comparison; **this assertion is the entire reason that is acceptable.**
- [ ] `DP22` — `bash -n` parses the new script.

Budget: `staging/plugin/scripts/tests/autopilot-disarm-scope-preserve.test.sh` (~200 lines added)

## Task 5 — CODE: create `scope-file-read.sh` and wire it into deployment and CI (R-01, R-05, R-06)

Owner: **coder**. Turns Task 4 green.

- [ ] Create `staging/plugin/skills/autopilot/scripts/scope-file-read.sh`. Bash 3.2, `set -u`, no
      `set -e`. Usage: `scope-file-read.sh <project-root>`. **It is a REPORTER** — say so in the
      header in the same words `scope-args-parse.sh`'s neighbours use, and say that the CHECKER
      three lines above it in the calling fence is the opposite idiom (rule 5).
- [ ] Emit `key=value` lines with `state=` first, then `source=`, `features=`, `only_count=`,
      `delivered=`. Exit 0 on every state of the input; exit 2 only on a missing/invalid root.
      Never exit 3.
- [ ] `delivered` is `grep -c . "<root>/.claude/autopilot-state/published"` guarded with `|| true`,
      0 when absent. `features` is validated with `case "$_f" in ''|*[!0-9]*)` exactly as
      `conductor-scope-gate` validates it — same guard, same shape, so the differential in `DP21`
      is comparing two implementations of one rule and not two different rules.
- [ ] `MALFORMED` = readable but no `source=` line, or a `source=` value outside
      `arguments|marker|none`, or `source=arguments` with neither a usable `features=` nor any
      `only=` line. `UNREADABLE` = present and `[ ! -r ]`. Absent = `ABSENT`. Three states, never
      two (rule 11, ADR-0076).
- [ ] Add the PAIRS entry to `staging/sync-to-claude.sh`, immediately after the `scope-args-parse.sh`
      line: `plugin/skills/autopilot/scripts/scope-file-read.sh|skills/autopilot/scripts/scope-file-read.sh`.
- [ ] Add `autopilot-disarm-scope-preserve` to the harness loop in `.github/workflows/docs-ci.yml`.
      `pairs-completeness.test.sh` checks that list in **both directions** (rule 8) and is red
      without this.

Budget: `staging/plugin/skills/autopilot/scripts/scope-file-read.sh` (~100 lines), `staging/sync-to-claude.sh` (~5 lines), `.github/workflows/docs-ci.yml` (~5 lines)

## Task 6 — TEST: launch precedence, the `published` reset, the malformed path, and the consumer audit (R-01, R-04, R-05, R-06, R-07)

Owner: **tester**. Extends the new harness. RED until Tasks 7 and 8.

- [ ] `DP23` (R-05) — precedence, driven through `run_fence "autopilot-scope-args"`: with a
      `REUSABLE` file on disk, `--features 2` still yields `source=arguments`; with no argument it
      yields `source=preserved`; with no argument, no file and a marker `scope:` block it yields
      `source=marker`; with none of the three, `source=none`. Four assertions, one per path.
- [ ] `DP24` (R-06, rule 4) — the malformed/unreadable path at `autopilot-scope-resolve`: a
      `MALFORMED` file is **removed**, the run proceeds unbounded, and the output carries an
      explicit warning **naming the file**. Then the refusal case: with removal made impossible,
      the fence exits **3** and its message names both the file and the manual remedy. `DID-NOT-RUN`
      and found-nothing must be visibly different answers.
- [ ] `DP25` (R-06) — an **absent** file produces no warning at all. This is the ordinary
      never-had-a-bound case and a warning there trains the operator to ignore the real one.
- [ ] `DP26` (R-05, ADR-0167 §D4) — the `published` reset, both directions: check 9 removes
      `published` exactly when it writes a fresh `scope`, and leaves it exactly when it reuses a
      preserved one. Assert **both**, plus a third case: `--dry-run` removes nothing and writes
      nothing.
- [ ] `DP27` (R-01) — a preserved bound is **announced**: check 9's output names the source and the
      bound it is about to apply. Match a flattened, undecorated copy (rule 3).
- [ ] `DP28` (R-05) — an explicit `--features` **overwrites**: after the fence, the `scope` file
      contains the new bound and **no line of the old one**. Never merged, never appended — assert
      the absence of an old `only=` row, not just the presence of the new value.
- [ ] `DP29` (ADR-0167 §D8) — `source=preserved` takes the Phase P skip branch. Assert on the
      routing prose in `autopilot/SKILL.md` §1.3/§1.5, flattened and undecorated. This is an
      **instruction, not an enforcement** (rule 16) — say so in the assertion's comment so a green
      result is not read as proof the model skipped Phase P.
- [ ] `DP30` (R-04) — the RUNBOOK's "Aborting a run" section states all three facts: the two files
      survive, a bare relaunch reuses the bound, `--features`/`--only` overrides it. Target
      `../docs/RUNBOOK-autopilot.md` (the one `..` prefix `plant-check.sh` allows), flattened and
      undecorated.
- [ ] `DP31` (R-04) — the "guard is still armed" section still says **"four ways to be stuck"** and
      still has its four-row table. `autopilot-run-scope.test.sh` `KB8` also pins this; `DP31` is
      the local regression guard for an edit made in this feature, and its comment says so rather
      than claiming independent evidence.
- [ ] `DP32` (R-07) — the consumer audit is recorded and each consumer accounted for: assert that
      `project-conductor/SKILL.md`'s Step 2 prose names the preserved-file lifecycle and states why
      `conductor-scope-gate`'s exit-3 stays a halt. This is the audit's landing place in the code;
      the inventory itself is ADR-0167's R-07 table.

Budget: `staging/plugin/scripts/tests/autopilot-disarm-scope-preserve.test.sh` (~260 lines added)

## Task 7 — CODE: Phase S precedence and check 9's reuse/reset branches (R-01, R-05, R-06, R-07)

Owner: **coder**. `staging/plugin/skills/autopilot/SKILL.md` only. Turns most of Task 6 green.

**Fence hygiene, non-negotiable (rule 15, ADR-0133 §D1):** both fences already run their body under
`bash <<'FENCE_BASH'` with the terminator at **column 0**. Every new free variable must be added to
the fence's own `export` line or it does not survive the subprocess boundary — a plain shell
variable silently arrives empty and the branch below it silently takes the wrong path. Introduce **no
positional-parameter token** into either body: the markdown is rendered with this skill's invocation
arguments substituted in before the model sees it (ADR-0132 §D1), which is why the read logic is a
file and not a fence.

- [ ] Phase S fence `autopilot-scope-args`: resolve `scope-file-read.sh` through the same two-branch
      `CLAUDE_PLUGIN_ROOT` → `$HOME/.claude` lookup `scope-args-parse.sh` uses, with the same
      not-deployed exit 3 and the same `Run: bash <repo>/staging/sync-to-claude.sh --apply` remedy.
      Add a comment at the call marking it a **REPORTER** and the parser above it a **CHECKER**.
- [ ] Insert the preserved branch **between** the `_has_scoping_arg` branch and the marker branch:
      `REUSABLE` → `_source=preserved`, `_features`/`_only` from the file. `SPENT`, `NOT-REUSABLE`,
      `ABSENT` → fall through unchanged. `MALFORMED`/`UNREADABLE` → print the warning naming the
      file, fall through, and set the state variable check 9 reads.
- [ ] Extend the `SCOPE-PARSE:` line with the preserved state so check 9 can act on it, and extend
      the paragraph below the fence that tells the caller what to carry forward. Both are read by
      existing `AR`/`SAP` assertions — keep the existing tokens intact and add, never rewrite.
- [ ] Check 9 fence `autopilot-scope-resolve`: add `_scope_preserved` (or whatever Phase S emits) to
      the **`export` line**. Then three branches — reuse (do not re-resolve, do not rewrite, print
      the preserved bound, leave `published`), stale-file (`rm -f` then continue; exit 3 with the
      remedy if removal fails), normal (resolve and write as today, then `rm -f` `published`).
- [ ] The reuse branch must not run the token resolver. The file's `only=` lines are exact roadmap
      row text, not tokens (ADR-0129 §D2); re-resolving them matches nothing and aborts the launch.
- [ ] §1.3 `--dry-run` routing paragraph and §1.5 Phase P: state that `source=preserved` skips
      Phase P, and why (the continuation's Phase P already ran; a preserved bound has rows, not
      tokens). Prose only in §1.5 — do not touch the `autopilot-prep-row-select` fence body.

Budget: `staging/plugin/skills/autopilot/SKILL.md` (~180 lines)

## Task 8 — CODE: the RUNBOOK, the conductor's Step 2 prose, and the record (R-04, R-07)

Owner: **coder**. Turns `DP30`–`DP32` green. **Prose only — no fence body, no exit code, no plant
needle is touched in `project-conductor/SKILL.md`.**

- [ ] `docs/RUNBOOK-autopilot.md`, "Aborting a run": after the disarm command, state that `scope`
      and `published` survive it, that a bare relaunch reuses the bound, and that passing
      `--features`/`--only` replaces it. Same register as the rest of the page.
- [ ] Same file, "The guard is still armed and I cannot push": the sentence "It clears the whole
      transient set, because the marker is only one of four ways to be stuck" becomes accurate about
      **guard state**. **Keep the exact phrase "four ways to be stuck"** and the four-row table —
      `KB8` in `autopilot-run-scope.test.sh` pins both, correctly, and the four guard files are
      genuinely unchanged. Add a short note on the two preserved files below the table.
- [ ] `staging/plugin/skills/project-conductor/SKILL.md`, Step 2, in the paragraph above
      `conductor-scope-gate`: record that `scope`/`published` now survive a disarm and are reset by
      the launch (ADR-0167 §D4), and that this gate's `DID-NOT-RUN` exit 3 **stays a halt** because
      mid-run unreadability is not launch-time absence (§D5, rule 11).
- [ ] The record: `docs/chain-decisions.md` narrative block, one line in
      `docs/chain-decision-index.md`, `PROJECT.md` roadmap row, and `TODO.md` — `VCS-018` is already
      `[x]`; `VCS-020`'s relaunch instruction now names the wrong mechanism and needs a forward
      correction (rule 14: correct forward, do not rewrite the dated entry's body).

Budget: `docs/RUNBOOK-autopilot.md` (~40 lines), `staging/plugin/skills/project-conductor/SKILL.md` (~20 lines), `docs/chain-decisions.md` (~30 lines), `docs/chain-decision-index.md` (~1 lines), `PROJECT.md` (~5 lines), `TODO.md` (~5 lines)

## Task 9 — Verify: plants fire, the full suite is green, nothing else moved (R-03, R-07)

Owner: **tester**, then a full-suite run.

- [ ] Declare a `# plant:` line at **column 1** for every new `DP` assertion, three or four fields,
      ` | `-separated, no ` | ` inside a field. For the negative assertions (`DP5`, `DP25`, `DP31`)
      the mutation must **make the banned thing happen** or **invert the condition** — deleting the
      mechanism leaves a negative assertion trivially satisfied. That mistake cost five plants in
      this very harness family; the note is in `autopilot-guard-disarm.test.sh`'s header.
- [ ] Run `bash staging/plugin/scripts/tests/plant-check.sh`. Every `DP` plant must fire. **Confirm
      `# plant: D1`, `KB5` and `KB6` still resolve to exactly one match each** — a needle matching
      zero times is a `BADPLANT`, not a pass. Inspect what each plant actually produced before
      believing what it reports (rule 2, ADR-0090).
- [ ] Run the **full** suite: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit
      1; done`. Not the two autopilot harnesses — `pairs-completeness.test.sh`,
      `fence-contract-coverage.test.sh` and `skill-coverage-perimeter.test.sh` all read the files
      this feature edits and none of them is named in any task above.
- [ ] Confirm R-03 by diff, not by assertion: `git diff` on `autopilot-disarm.sh` shows **no change**
      to the ownership block, the two refusal messages, the exit-2 and exit-3 paths, or the five
      surviving loop entries.
- [ ] Confirm R-07 by re-running the audit grep from "Read this second" and checking the count still
      lands on the four consumers in ADR-0167's R-07 table. A fifth means the table is stale.

---

## Risks, dependencies and HITL gates

- **`plant-check.sh` BADPLANT on `KB5`/`KB6` is the single most likely way this lands broken.** The
  needle dies in Task 2 and is repaired in Task 3; if the batches are ordered so Task 2 merges
  without Task 3, the registry — sharded across four CI machines (ADR-0151) — goes red for reasons
  that read as unrelated. Keep 2 and 3 in the same batch.
- **A silently empty free variable across the fence boundary.** `_scope_preserved` missing from
  check 9's `export` line arrives empty and takes the "normal" branch, which writes a fresh scope
  file and clears `published` — a plausible-looking run that quietly discards the bound this feature
  exists to preserve. `DP26` is the assertion that catches it; it must be seen RED.
- **A stale preserved bound.** ADR-0167 accepts it (§A8 deferred, Consequences/negative). An
  operator who bounded a run weeks ago gets that bound on a bare relaunch. Announced, overridable,
  not prevented.
- **New deployment dependency.** Phase S exits 3 when `scope-file-read.sh` is not deployed. A target
  repo synced before this feature cannot launch autopilot until `staging/sync-to-claude.sh --apply`
  is re-run. Matches the `scope-args-parse.sh` precedent immediately above it, but it is a hard stop
  and worth saying out loud at the gate.
- **Two copies of the exhaustion comparison** (`scope-file-read.sh` and `conductor-scope-gate`).
  `DP21` is the only thing keeping them in agreement. If `DP21` is dropped or weakened, ADR-0167 §A7
  must be reopened.
- **`conductor-scope-gate` is deliberately untouched** and its nine `CG` plants must stay green. Any
  task that finds itself editing that fence body has left this plan's scope.
- **Auto mode is active: no intermediate HITL.** The gates that still apply are the standing ones —
  **commit** and **push** at Step 6/7. No schema change, no deletion of a tracked file, no deploy,
  no migration. `sync-to-claude.sh --apply` writes into `~/.claude/` and is a deploy action outside
  the session's working directory: it is **not** part of any task above and stays a human decision.
- **`SPEC.md` is not edited by any task** (rule 14, and it is outside both agents' write scope). The
  R-06/`conductor-scope-gate` tension and the R-08/`--completing` scoping are resolved forward in
  ADR-0167 §D5 and §D2, not by editing the SPEC.

## Requirement coverage

| Id | Tasks |
|---|---|
| R-01 | 4, 5, 6, 7 |
| R-02 | 1, 2, 3 |
| R-03 | 1, 2, 3, 9 |
| R-04 | 6, 8 |
| R-05 | 4, 5, 6, 7 |
| R-06 | 4, 5, 6, 7 |
| R-07 | 6, 7, 8, 9 |
| R-08 | 1, 2, 3 |

R-07 carries `(no-test: …)` in the SPEC. It is exempt from the test axis only, never from the plan
axis (ADR-0138): it is cited by four tasks above, and `DP32` asserts the audit's landing place in
the code even though the inventory itself is verified by reading ADR-0167's R-07 table.
