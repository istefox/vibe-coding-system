# Implementation plan — one classification, two callers: the Step 7.1 commit-outcome backstop

- **Issue:** none — from a live incident (Adnota PR #36), drafted as
  `docs/proposal-c4-commit-outcome-hook.md`
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md` (R-01 … R-08)
- **ADR:** `docs/architecture/ADR-0168-commit-outcome-backstop-hook.md`
- **ARCH:** n/a — a scoped addition inside an already-documented system.
- **Stack:** Bash 3.2 (macOS `/bin/bash`) plus POSIX `awk`/`sed`/`grep`/`find`, and `jq` for the
  hook's stdin JSON. No `mapfile`, no associative arrays, no `${var^^}`/`${var,,}`, no `[[ ]]`, no
  process substitution. Two new scripts, one new harness, two existing harnesses edited, one
  `SKILL.md` fence body, `sync-to-claude.sh`, the staged reference `settings.json`, one CI list
  entry.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`

TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: sonnet

EXTERNAL DEPENDENCY: jq | binary | provisioned: true

---

## Read this first — the ADR is 0168, and it overrides `SPEC.md` in two places

`git log --all --diff-filter=A` over `docs/architecture/ADR-016*` puts the highest at **0167**. Use
**0168**. Add no twenty-first `CLAUDE.md` rule.

**Two deliberate deviations from `SPEC.md`, both argued in ADR-0168's Context and both required for
the SPEC's own criteria to be satisfiable. Do not "correct" the implementation back to the SPEC's
literal wording.**

1. **The manifest filter is wider than Scope says.** `SPEC.md` Scope says "filters to
   `status: completed` or `current_step: completed`". R-04's own fixture is
   `current_step: step_7_commit`, `status: in_progress` — it satisfies neither, so the SPEC's filter
   would drop the fixture before classification. ADR-0168 §D5 keeps both disjuncts and adds the three
   commit-stage states from `manifest-transition.sh`'s graph.
2. **A `CLEAN` audit line is written when the window holds nothing.** `SPEC.md` Edge cases say
   "nothing logged". ADR-0168 §D6 overrides that clause only: **stdout stays empty** (the "zero
   transcript noise" requirement is honoured verbatim), the audit log gets one line. Reason in the
   ADR: a hook whose common path leaves no trace is indistinguishable from a hook the matcher never
   matched, which is ADR-0127's `nightly-guard.sh` failure exactly.

## Read this second — state measured before any work (rule 13)

Re-derived 2026-08-23 at `9d08df1`. **Re-derive it; do not trust this block.**

```text
Step 7.1 classification copies in tree:            1   SKILL.md fence body
harnesses EXECUTING that fence body:               1   commit-transition-order.test.sh CTO12 (A-E)
harnesses asserting its PROSE:                     1   same file, CTO13
skills invoking the `commit` skill:                3   concept-to-code, autopilot-build, deep-refactor
agent definitions invoking it:                     0
Skill tool_use payload (live transcripts):         {"name":"Skill","input":{"skill":"commit","args":…}}
commit-stage states (manifest-transition.sh):      step_7_commit · step_e4_commit · step_h5_commit
two-tier CLAUDE_PLUGIN_ROOT lookups in SKILL.md:  10
assertion-id prefix CO:                            FREE   (grep -rnoE '\bCO[0-9]+\b' staging/ → 0)
PostToolUse entries in ~/.claude/settings.json:    5
MANUAL STEP notices in sync-to-claude.sh:          6
```

## Read this third — the observable contract change, and every call-site that asserts the old one

The change: **the `c2c-step7-commit-outcome` fence body stops containing the classification and
starts resolving and invoking a script.** Found by grepping `COMMIT_NONTERMINAL`,
`COMMIT_UNCOMMITTED`, `COMMIT_OUTCOME_NORUN` and `c2c-step7-commit-outcome` across the whole tree.
**These are all of them. Do not go looking for more, and do not skip any.**

| Where | What it does today | Required change |
|---|---|---|
| `staging/plugin/scripts/tests/commit-transition-order.test.sh` — `run_outcome_fence()` | extracts the fence body, `sed`s `<manifest-path>`, runs it under one outer `bash` with **no** `CLAUDE_PLUGIN_ROOT` export | **Must export `CLAUDE_PLUGIN_ROOT="$STAGING/plugin"`.** Without it, all five fixtures return `COMMIT_OUTCOME_NORUN noScript` on an undeployed machine, or silently test the *deployed* copy on a deployed one — breaking that file's own "no `$HOME` dependency" header claim. Task 3. |
| same file — `CTO12` cases A–E | assert `COMMIT_OK` / `COMMIT_UNCOMMITTED modified` / `… untracked` / `COMMIT_NONTERMINAL` / `COMMIT_OUTCOME_NORUN` from the extracted body | **Unchanged assertions.** They are the proof the extraction is behaviour-preserving. Do not weaken, do not delete, do not add a skip. |
| same file — `CTO13` | compound needle `commit_uncommitted` + `no rollback` + `no transition` + `absorbing` in the flattened Step 7 block | **Unchanged.** ADR-0168 §D2 keeps that prose word for word. |
| same file — `# plant: CTO12` | needle `mk_manifest "$FXA/manifest.yml" completed completed` | Survives — it targets the fixture, not the fence. **Verify with `plant-check.sh`, do not assume.** Task 8. |
| `staging/plugin/scripts/tests/fence-contract-coverage.test.sh` — F4 | requires the literal `fence-contract: c2c-step7-commit-outcome -->` to appear in a test file | Satisfied unchanged by `commit-transition-order.test.sh`. No edit. Named here so nobody "cleans up" that literal. |
| `docs/architecture/ADR-0135-*.md`, `docs/superpowers/plans/2026-08-12-410-*.md` | 9 + 4 mentions of the tokens | **Historical records — do not edit** (rule 14). ADR-0168 records the change forward. |

**Run the FULL suite after Task 4 and again after Task 6, not just the touched harnesses.** A fence
body change reaches `fence-contract-coverage`, `skill-fence-positional-tokens` and
`skill-coverage-perimeter`; a new file under `staging/plugin/scripts/` reddens
`pairs-completeness.test.sh` the moment it exists without its `PAIRS` entry.

## Read this fourth — this feature's own coverage gate is not evidence about this feature

`commit-transition-order.test.sh` cites ADR-0135, which this plan also cites, so under ADR-0154's
conjunction it scopes in — and it is full of `R-01`…`R-15` tokens belonging to issue #410. Several of
this feature's ids will report `COVERED` before a line of it exists (ADR-0154 §D7 class 1). **The
evidence is each `CO` assertion going RED against its declared plant at Task 8, never the gate's
verdict.**

## Files this plan touches

| File | Owner | What changes |
|---|---|---|
| `staging/plugin/skills/concept-to-code/scripts/commit-outcome-check.sh` | coder | **create** — the CHECKER |
| `staging/plugin/scripts/commit-outcome-backstop.sh` | coder | **create** — the REPORTER hook |
| `staging/plugin/skills/concept-to-code/SKILL.md` | coder | Step 7.1 fence **body only** |
| `staging/sync-to-claude.sh` | coder | 2 `PAIRS` entries, `chmod +x` list, 1 MANUAL STEP block |
| `staging/user/settings.json` | coder | 1 `PostToolUse` reference entry |
| `.github/workflows/docs-ci.yml` | coder | 1 name in the `shell-tests` loop |
| `docs/proposal-c4-commit-outcome-hook.md` | coder | superseded header |
| `docs/chain-decisions.md`, `docs/chain-decision-index.md`, `PROJECT.md` | coder | the record |
| `staging/plugin/scripts/tests/commit-outcome-backstop.test.sh` | **tester** | **create** — the `CO` sections |
| `staging/plugin/scripts/tests/commit-transition-order.test.sh` | **tester** | `run_outcome_fence()` export only |
| `staging/plugin/scripts/tests/sync-manual-steps.test.sh` | **tester** | `build_home` "yes" fixture + new section |

Everything under `staging/plugin/scripts/tests/` is **tester-owned** — `test-write-scope.sh` denies
the coder any write there. Files under `staging/` are mode 644: run them as `bash <path>`.

## Assertion ids and the harness contract

New assertions use the **`CO`** prefix (verified free 2026-08-23). The new harness
`staging/plugin/scripts/tests/commit-outcome-backstop.test.sh` **must contain both the literal
`ADR-0168` and the literal `2026-08-23-commit-outcome-backstop-hook` in its header**, or
`spec-coverage.sh` descopes it as a precedent citation and this feature's ids report `UNSCOPED`
(ADR-0154). Every block carries an id-mapping comment: `# CO7/CO8 (R-02) — …`.

The harness is offline, hermetic, no network, **no `$HOME` dependency** (override
`COMMIT_OUTCOME_BACKSTOP_DIR` and `CLAUDE_PLUGIN_ROOT`; override `HOME` only in the one case that
proves the second tier, and declare it in the file header), targets `staging/` directly, and ends
with the repo's standard `PASS=`/`FAIL=` line plus a `COZ1` assertion floor.

Every `CO` id carries a `# plant:` declaration at column 1 (ADR-0149 grammar), and `plant-check.sh`
must report every one as FIRED at Task 8. An assertion nobody planted pins nothing (rule 2).

## Batching

An assertion must not sit in the same batch as the task it depends on (ADR-0101 rule 1).

| Batch | Tasks | Expected state at checkpoint |
|---|---|---|
| A | 1, 3 | Task 1 fully RED. Task 3 **green before and after** — the export is inert while the fence is still inline. |
| B | 2, 4 | Task 1's `CO1`–`CO6` green; `CO7`/`CO8` green after Task 4. |
| C | 5 | `CO9`–`CO18` RED. |
| D | 6, 7 | `CO9`–`CO18` green. |
| E | 8 | Everything green; plants FIRED; live wiring probed. |

---

## Task 1 — TEST: the checker's five classifications and its unresolved-script path (R-01)

Owner: **tester**. Create `staging/plugin/scripts/tests/commit-outcome-backstop.test.sh` with its
header (including the two ADR-0154 literals) and section `CO1`–`CO6`. Every assertion is RED until
Task 2.

Build fixtures the way `commit-transition-order.test.sh` already does — patch a **real** manifest
from `docs/manifests/` that passes `manifest-validate.sh`, `sed`-replacing `project_root`,
`current_step` and `status`, so the quoting is the quoting `manifest-init.sh` actually writes. Real
`git init` trees, real commits.

- [ ] `CO1` (R-01) — terminal, committed, clean → stdout `COMMIT_OK`, exit **0**.
- [ ] `CO2` (R-01) — terminal, tracked and modified after the commit → `COMMIT_UNCOMMITTED modified`,
      exit **1**. Exact qualifier, not a prefix.
- [ ] `CO3` (R-01) — terminal, never added → `COMMIT_UNCOMMITTED untracked`, exit **1**. Exact
      qualifier.
- [ ] `CO4` (R-01) — `current_step: step_7_commit`, `status: in_progress`, committed and clean →
      `COMMIT_NONTERMINAL current_step`, exit **1**.
- [ ] `CO5` (R-01) — manifest outside any git repository → `COMMIT_OUTCOME_NORUN`, exit **3**; and a
      path that does not exist → `COMMIT_OUTCOME_NORUN noManifest`, exit **3**.
- [ ] `CO6` (R-01) — `sync-to-claude.sh`'s `PAIRS` block carries
      `plugin/skills/concept-to-code/scripts/commit-outcome-check.sh|skills/concept-to-code/scripts/commit-outcome-check.sh`.
      Without the entry the script never reaches `~/.claude` and both callers resolve nothing on a
      real machine (`pairs-completeness.test.sh` does not require it — skills are vendored
      selectively — so nothing else would catch this).
- [ ] `CO18` (rule 7) — **denominator guard**: the base-manifest search found at least one manifest
      passing `manifest-validate.sh`. Zero candidates and zero failures are indistinguishable from
      outside, and this harness derives every fixture from that one file.

Plants: `CO1`–`CO5` target `commit-outcome-check.sh` (invert one comparison each, e.g.
`[ "$_cs" != "completed" ]` → `[ "$_cs" = "completed" ]`); `CO6` targets the `PAIRS` line;
`CO18` self-targets.

Budget: `staging/plugin/scripts/tests/commit-outcome-backstop.test.sh` (~200 lines)

## Task 2 — CODE: create `commit-outcome-check.sh` (R-01)

Owner: **coder**. Turns `CO1`–`CO6` green.

- Create `staging/plugin/skills/concept-to-code/scripts/commit-outcome-check.sh`, `#!/bin/bash`,
  `set -u`, one argument `<manifest-path>`.
- **Move the current fence body verbatim.** Read it out of the `c2c-step7-commit-outcome` fence in
  `staging/plugin/skills/concept-to-code/SKILL.md` and change nothing but the variable source
  (`_m="$1"` instead of the substituted placeholder) and the addition of a usage guard for a missing
  argument (`COMMIT_OUTCOME_NORUN noManifest`, exit 3). Same `grep`/`sed` field reads, same
  `git -C "$_d" status --porcelain -- "$(basename "$_m")"`, same `case` on `'??'*`, same tokens,
  same exit codes.
- Header comment states: this is a **CHECKER** (branched on by exit code 0/1/3, rule 5), its two
  callers are `SKILL.md` Step 7.1 and `commit-outcome-backstop.sh`, and the contract must not change
  in one without the other (ADR-0168 §D1). Name ADR-0135 §D3 as the origin of the four tokens.
- Add the `PAIRS` entry named in `CO6`, in the `concept-to-code/scripts/` run, alphabetically among
  its siblings.

Budget: `staging/plugin/skills/concept-to-code/scripts/commit-outcome-check.sh`,
`staging/sync-to-claude.sh` (~60 lines)

## Task 3 — TEST: `run_outcome_fence()` resolves the staging copy, not the deployed one (R-02)

Owner: **tester**. Edit `staging/plugin/scripts/tests/commit-transition-order.test.sh` only.

- [ ] Add `CLAUDE_PLUGIN_ROOT="$STAGING/plugin"` to the environment of the `bash "$TMP/outcome-run.sh"`
      call inside `run_outcome_fence()`, in a subshell `export` exactly as
      `spec-coverage-baseline-bump.test.sh`'s `NB16` does for the sibling Step 7.0b fence. Do **not**
      change what `CTO12` asserts, do not touch `CTO13`, do not touch `CTOZ1`.
- [ ] Add a comment above the export naming **why**: after ADR-0168 §D2 the fence resolves a script
      two-tier, and without this export the harness would either fail on an undeployed machine or
      silently exercise `$HOME/.claude`, contradicting this file's own "no `$HOME` dependency" header.

This edit is green before Task 4 and green after it. That is intentional: it is the one repair that
can land ahead of the change it protects against.

Budget: `staging/plugin/scripts/tests/commit-transition-order.test.sh` (~12 lines)

## Task 4 — CODE: Step 7.1 calls the checker; no second copy of the classification (R-02)

Owner: **coder**. Rewrite the body of the `c2c-step7-commit-outcome` fence in
`staging/plugin/skills/concept-to-code/SKILL.md`.

**Keep unchanged:** the `<!-- fence-contract: c2c-step7-commit-outcome -->` marker, the
`bash <<'FENCE_BASH'` wrapper with its **column-0** terminator (ADR-0133), the single
`<manifest-path>` placeholder (three harnesses substitute it textually), no positional-parameter
token anywhere in the body (ADR-0132), and every word of the four-branch prose table below the fence
— `COMMIT_OK` / `COMMIT_UNCOMMITTED …` / `COMMIT_NONTERMINAL …` / exit 3, including the
"no rollback is attempted", "no transition is added" and "absorbing" clauses that `CTO13` matches.

**New body:** an `export CLAUDE_PLUGIN_ROOT` prologue *outside* the heredoc (the Step 7.0b fence's
exact shape), then two-tier resolution of
`skills/concept-to-code/scripts/commit-outcome-check.sh` — `CLAUDE_PLUGIN_ROOT` first,
`$HOME/.claude` second — then `exec`/`bash "$_check" "<manifest-path>"` passing stdout and the exit
code straight through. Unresolved → `COMMIT_OUTCOME_NORUN noScript`, a second line naming the remedy
(`bash <repo>/staging/sync-to-claude.sh --apply`), exit **3**. **No inline fallback classification**
(ADR-0168 §D3).

Add one sentence above the fence stating the extraction and naming `commit-outcome-check.sh` as the
single definition shared with the backstop hook.

Budget: `staging/plugin/skills/concept-to-code/SKILL.md` (~35 lines)

## Task 5 — TEST: the hook — no-op, the Adnota fixture, the window, the population, the error paths (R-03, R-04, R-05, R-06, R-07)

Owner: **tester**. Extend `commit-outcome-backstop.test.sh` with sections `CO7`–`CO17`. All RED until
Task 6 (`CO7`/`CO8` green after Task 4; keep them here so the fence and the hook are asserted from
one file).

Drive the hook the way every hook harness here does: pipe a synthetic payload on stdin, with
`COMMIT_OUTCOME_BACKSTOP_DIR` and `CLAUDE_PLUGIN_ROOT` pointed at fixture paths.

- [ ] `CO7` (R-02) — the fence body **names** `commit-outcome-check.sh` and **no longer contains**
      `git status --porcelain`. Two directions, both required (rule 8): the first says the new
      mechanism is there, the second says the old one is gone. Anchor on the mechanism, never on the
      word "classification" (rule 12).
- [ ] `CO8` (R-02) — **executed proof**: extract the fence by its marker, substitute
      `<manifest-path>`, run it (a) with `CLAUDE_PLUGIN_ROOT="$STAGING/plugin"` against a terminal
      committed fixture → `COMMIT_OK` exit 0; (b) with `CLAUDE_PLUGIN_ROOT` at an empty tree **and**
      `HOME` at a tree with no `.claude` → `COMMIT_OUTCOME_NORUN noScript`, exit **3**. Case (b) is
      the only `HOME` override in this file — declare it in the header.
- [ ] `CO9` (R-03) — payload with `tool_input.skill` = `"interview-driver"`: exit **0**, stdout
      **empty**, and **no audit file created at all**. Assert all three.
- [ ] `CO10` (R-03) — `staging/user/settings.json` carries a `PostToolUse` entry with
      `"matcher": "Skill"` whose command names `commit-outcome-backstop.sh`; and
      `sync-to-claude.sh` prints its MANUAL STEP notice when the fixture `settings.json` lacks that
      name, and does not print it when the fixture has it. (The second half belongs in
      `sync-manual-steps.test.sh` — see the last bullet.)
- [ ] `CO11` (R-04) — **the Adnota fixture.** A git tree with `docs/manifests/<date>-x.manifest.yml`
      at `current_step: step_7_commit`, `status: in_progress`, mtime now, committed and clean; a
      payload with `skill: "commit"` and `cwd` inside that tree. Assert: stdout contains
      `COMMIT_NONTERMINAL current_step` **and** names the manifest path; the audit log gains exactly
      **one** line whose 4th tab-field is `COMMIT_NONTERMINAL`; exit **0**.
- [ ] `CO12` (R-05) — same fixture, `touch -t 202001010000` on the manifest → **not scanned**: no
      `COMMIT_NONTERMINAL` on stdout, and the audit log's only line is a `CLEAN` one. Assert on the
      absence of the classification *and* the presence of `CLEAN`, or "not scanned" and "hook did not
      run" are the same observation (rule 4).
- [ ] `CO13` (R-05, rule 8, **reverse direction**) — a manifest in the window at
      `current_step: step_3_project_memory`, `status: in_progress`, uncommitted → **not reported**.
      This is ADR-0168 §D5's population rule asserted from the outside: an in-flight chain must not
      generate a report on every unrelated commit.
- [ ] `CO14` (R-04, R-05) — the population **includes** `step_e4_commit` and `step_h5_commit`, not
      only `step_7_commit` and `completed`. One fixture per state. Without this the widening in §D5
      is asserted for one of three chain paths.
- [ ] `CO15` (R-06) — four error paths, each exit **0** and each leaving the payload's tool call
      unharmed: (a) no `docs/manifests/` anywhere up from `cwd`; (b) `jq` absent (shadow it with a
      `PATH` fixture — capture the real interpreter path first, see the `VAR=value cmd` trap);
      (c) `COMMIT_OUTCOME_BACKSTOP_DIR` pointed at an unwritable path; (d) `commit-outcome-check.sh`
      unresolved.
- [ ] `CO16` (R-06, rule 4) — path (d) above reports its **own** condition (`NORUN`/`noScript` in the
      audit line and on stdout), distinct from the `CLEAN` line path (a)/(c) produce. An unrun check
      must not read as a clean result.
- [ ] `CO17` (R-07) — the project root comes from the payload's **`cwd`**: two fixture trees, each
      with its own stale manifest, produce reports naming only their own tree's manifest when
      `cwd` points at them, with `PWD` set to the *other* tree. `SPEC.md` marks R-07 `(no-test: …)`;
      this assertion exceeds that and is cheap — keep it.
- [ ] `CO-CI` — this harness's own name is in `.github/workflows/docs-ci.yml`'s `shell-tests` loop
      list (the self-registration convention every recent harness here follows; `ci.yml` globs and
      needs nothing).
- [ ] `COZ1` — assertion-count floor, **re-measured** from the finished file, not copied from this
      plan. Comment at the site that it is a vacuity guard, not the pin (rule 10).
- [ ] In `staging/plugin/scripts/tests/sync-manual-steps.test.sh`: extend `build_home`'s **"yes"**
      fixture JSON with the new `PostToolUse` entry, and add a section asserting the notice fires on
      the "no" fixture and not on "yes". That file's header says in as many words that whoever adds
      the next notice must do this or its all-clear assertion rots.

Plants: one per `CO` id. `CO7`/`CO8` target the `SKILL.md` fence; `CO9`–`CO17` target
`commit-outcome-backstop.sh` (delete the skill pre-filter; delete the mtime predicate; widen the
state `case` to `*`; remove the `CLEAN` write; invert the fail-open `exit 0`); `CO10` targets the
`staging/user/settings.json` entry. Needles must not be the mechanism's *name* (rule 12) — plant the
`case` arm, the `-mtime -1` token, the `grep -q '"skill"…'` line, not the words "skill" or "window".

Budget: `staging/plugin/scripts/tests/commit-outcome-backstop.test.sh`,
`staging/plugin/scripts/tests/sync-manual-steps.test.sh` (~330 lines)

## Task 6 — CODE: write the backstop hook (R-03, R-04, R-05, R-06, R-07)

Owner: **coder**. Create `staging/plugin/scripts/commit-outcome-backstop.sh`. Turns `CO9`–`CO17`
green. Model the file on `staging/plugin/scripts/precompact-guard.sh` — same header shape (what it
does / what must never be "fixed" / fail-open guarantee / contract line), same `log_audit` helper,
same walk-up loop, same `yval()` field reader, same `set -u`, bash 3.2 clean.

Order of operations, which is load-bearing (ADR-0168 §D7):

1. `INPUT=$(cat)`; empty → exit 0 silent.
2. `printf '%s' "$INPUT" | grep -q '"skill"[[:space:]]*:[[:space:]]*"commit"'` → no match, **exit 0
   silent, before any `jq`, any log, any scan.** This is R-03's no-op and it runs on every skill call
   on the machine.
3. `command -v jq` → absent: `log_audit` one `jq missing` line, exit 0.
4. `jq -r` for `.tool_name`, `.tool_input.skill`, `.cwd`, `.session_id`. Require
   `tool_name == "Skill"` **and** `tool_input.skill == "commit"`; otherwise exit 0 silent. The grep
   in step 2 is a pre-filter, never the authority.
5. Walk up from `cwd` (max 40 iterations, stop at `/`) looking for `docs/manifests/`; absent → exit 0
   silent, no log — most `commit` calls are not in a chain project (`SPEC.md` Edge cases).
6. `find "$ROOT/docs/manifests" -name '*.manifest.yml' -mtime -1` — `-mtime -1` is the one spelling
   BSD and GNU `find` agree on (`-newermt` is GNU-only, `stat` flags differ). Iterate line-wise with
   `while IFS= read -r`, never over an unquoted expansion (the host shell is zsh).
7. For each: read `current_step`/`status` with `yval`; keep it only if
   `current_step ∈ {completed, step_7_commit, step_e4_commit, step_h5_commit}` **or**
   `status == completed`, via an `is_commit_stage_state()` `case` mirroring
   `precompact-guard.sh`'s `is_dispatch_state()`. Write the three-path reason in a comment above it,
   and state that it deliberately exceeds `SPEC.md`'s two-disjunct sketch per ADR-0168 §D5.
8. Resolve `commit-outcome-check.sh` two-tier (`CLAUDE_PLUGIN_ROOT` → `$HOME/.claude`). Unresolved →
   one `NORUN` audit line **and** one stdout line naming the remedy, exit 0. Never silence.
9. Run the checker per kept manifest. `COMMIT_OK` → audit line only, **no stdout**. Anything else →
   one stdout report line (manifest path, token, and a pointer to Step 7.1 — do not restate Step
   7.1's remediation, ADR-0168 §D4) plus one audit line.
10. Nothing kept → one `CLEAN` audit line, **stdout empty** (ADR-0168 §D6). Comment the override at
    the site, with the ADR-0127 reason.
11. `exit 0` on every path, including every error path.

Also: `${COMMIT_OUTCOME_BACKSTOP_DIR:-$HOME/.claude/state/commit-outcome-backstop}`; audit format
`ts\tsid\tmanifest\tclassification\treason`; `mkdir -p` failure is non-fatal; every write
`>>… 2>/dev/null || true`.

Then: `PAIRS` entry `plugin/scripts/commit-outcome-backstop.sh|hooks/commit-outcome-backstop.sh`
(**required** — `pairs-completeness.test.sh` direction 2 covers `plugin/scripts/*.sh`), the file
added to `sync-to-claude.sh`'s `chmod +x` list, and this harness's name appended to
`.github/workflows/docs-ci.yml`'s `shell-tests` loop.

The hook reads no transcript, so it is outside `transcript-scan-rule.test.sh`'s population. **If you
add a `transcript_path` read, you must add a `transcript-scan-exempt:` declaration** or that harness
goes red.

Budget: `staging/plugin/scripts/commit-outcome-backstop.sh`, `staging/sync-to-claude.sh`,
`.github/workflows/docs-ci.yml` (~180 lines)

## Task 7 — CODE: the wiring artefacts, the superseded proposal, the record (R-03, R-07, R-08)

Owner: **coder**.

- `staging/sync-to-claude.sh`: a seventh MANUAL STEP block, gated on
  `grep -q 'commit-outcome-backstop' "$DEST/settings.json"`, in the exact shape of the six that
  exist. Body: the JSON entry to add, the fact that the hook is report-only and inert outside a
  project with `docs/manifests/`, and that until the entry exists the hook is deployed but never
  invoked.
- `staging/user/settings.json`: add the same `PostToolUse` entry to the staged reference copy. This
  file is **deliberately not in `PAIRS`** (ADR-0025) — it documents, it does not deploy.
- `docs/proposal-c4-commit-outcome-hook.md`: add a header line
  `> **Superseded by ADR-0168** (…) — kept for provenance; the ADR is authoritative.` **Do not delete
  the file** (R-08 allows either; deletion is a HITL decision and the file is untracked, so the
  deletion would not even be a diff). Leave the deletion to the operator at Gate 7.
- `docs/chain-decision-index.md`: one entry for ADR-0168, in the established one-line form.
  `docs/chain-decisions.md`: the narrative block. `PROJECT.md`: the feature row.
- **Do not add a twenty-first `CLAUDE.md` rule.**

Budget: `staging/sync-to-claude.sh`, `staging/user/settings.json`,
`docs/proposal-c4-commit-outcome-hook.md`, `docs/chain-decision-index.md`, `docs/chain-decisions.md`,
`PROJECT.md` (~90 lines)

## Task 8 — Verify: plants fire, the full suite is green, and the hook actually fires (R-03, R-06)

Owner: **coder** (verification only, no new logic).

- `bash staging/plugin/scripts/tests/plant-check.sh` — every `CO` id **FIRED**, no `NOFIRE`, no
  `BADPLANT`. A `NOFIRE` means that assertion pins nothing; fix the assertion or the needle, never
  the plant's expected verdict.
- The **full** suite: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
  (run it in the background — it exceeds the 2-minute foreground tool timeout).
- `bash staging/sync-to-claude.sh` (dry run) — the new MANUAL STEP notice prints, the two new `PAIRS`
  sources resolve, no `source missing` line.
- **The one thing no harness can prove: that the `Skill` matcher actually fires.** Live hook
  documentation lists the matcher's vocabulary as built-in tool names plus `mcp__…` and does not
  document a `Skill` tool at all (ADR-0168 A5, and the Negative consequence that follows it). After
  the operator wires `~/.claude/settings.json` (HITL), invoke any skill and check
  `~/.claude/state/commit-outcome-backstop/audit.log`:
  - a `CLEAN` line appeared → the matcher fires, feature complete;
  - **no file, no line** → the matcher does not match `Skill`. Remedy is one line: change the
    matcher to `".*"`. The hook already re-checks `tool_name` itself (ADR-0168 §D7), so no script
    change is needed. Report this to the operator; do not edit `settings.json` yourself.
  This step is the reason §D6 writes a `CLEAN` line at all. Without it, "wired and inert" and
  "wired and quiet" are the same observation, which is precisely how `nightly-guard.sh` stayed
  broken (ADR-0127).

---

## Risks, dependencies and HITL gates

**Risks**

- **The `Skill` matcher may not exist** (open, mitigated, not eliminated). The only genuinely
  unresolved risk from the proposal's three. Verification and one-line remedy in Task 8.
- **The wiring gap.** Vendored ≠ wired. Six hooks in this repo have sat deployed-but-unregistered
  before. The gated notice plus Task 8's probe are the mitigation.
- **`cwd` vs the committed tree.** Measured from live transcripts: an orchestrator sometimes invokes
  `commit` against a different worktree than its own `cwd`. The backstop then scans the session
  root's manifests. Failure direction is a **missed report**, never a false alarm. Recorded, not
  fixed.
- **Subagent-invoked `commit`: resolved, a non-issue.** Zero agent definitions invoke the skill; the
  three invokers are all orchestrator-level. Do not add handling for a case that does not occur.
- **Stale-manifest false positives: resolved.** The commit-stage filter (§D5), not the 24h window, is
  the discriminator; `CO13` asserts it from the outside.
- **Global cost.** One `grep` per `Skill` tool call on the machine. Keep step 2 of Task 6 first and
  cheap; anything expensive above it is paid by every session.
- **`CTO12`'s hidden `$HOME` coupling.** If a future edit drops Task 3's export, the harness silently
  starts testing the deployed copy. The comment Task 3 requires is the only thing that will say so.

**Dependencies**

- `jq` (declared above; already a dependency of `precompact-guard.sh` and others).
- `git` in the fixture trees; `find` with `-mtime` (BSD and GNU both).
- The `PAIRS` entries must land in the same commit as the scripts, or `pairs-completeness.test.sh`
  goes red for the hook and the deployment silently misses the checker.

**HITL gates**

- **Gate 2** — this plan, the ADR, and the two deliberate deviations from `SPEC.md` (the widened
  filter; the `CLEAN` audit line). Both need to be seen and agreed, not inherited.
- **Gate 4** — implementation mode.
- **Gate 5** — review cycle.
- **Commit / push / PR** — the standard chain gates; nothing here commits.
- **`~/.claude/settings.json`** — a machine-local hand edit by the operator. No agent writes it, no
  script writes it (ADR-0025).
- **Deleting `docs/proposal-c4-commit-outcome-hook.md`** — operator's call, after the ADR is
  committed. Task 7 marks it superseded and stops.

## Requirement coverage

| Id | Tasks |
|---|---|
| R-01 | 1, 2 |
| R-02 | 3, 4, 5 |
| R-03 | 5, 6, 7, 8 |
| R-04 | 5, 6 |
| R-05 | 5, 6 |
| R-06 | 5, 6, 8 |
| R-07 | 5, 6, 7 |
| R-08 | 7 |
