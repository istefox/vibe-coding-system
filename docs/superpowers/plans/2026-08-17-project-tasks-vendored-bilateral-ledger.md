# Implementation plan — project-tasks becomes a vendored chain member with a bilateral GitHub ledger

- **Issue:** none. Tracked as ledger entries `VCS-022` and `VCS-023` in `TODO.md`.
- **SPEC:** `/Users/stefer/Developer/vibe-coding-system/SPEC.md` (R-01 … R-23)
- **ADR:** `docs/architecture/ADR-0153-project-tasks-vendored-bilateral-ledger.md`
- **Stack:** Bash 3.2 (macOS-portable — no `[[ ]]`, no arrays, no `mapfile`, no `${var^^}`), POSIX
  `awk`/`sed`/`grep`, markdown. The harnesses under `staging/plugin/scripts/tests/` run by
  `.claude/test-cmd`; plants per ADR-0108/ADR-0149; the sharded registry per ADR-0151. One new
  harness file, one new PAIRS block, two new skill scripts. No new runtime dependency: `gh` is
  optional by design and `python3` is deliberately not used.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`

TEST-CMD MODE: brownfield

EXTERNAL DEPENDENCY: GitHub CLI (`gh`) | command-line tool, authenticated | provisioned: true

EXTERNAL DEPENDENCY: GitHub Issues REST/GraphQL read on `istefox/vibe-coding-system` | third-party API via `gh` | provisioned: true

Both are already provisioned on the development machine — `gh issue list --state open` returned 66
issues on 2026-08-17 during design. Neither is needed by CI or by the harness: every assertion
about the GitHub read drives `gh-issues.sh` through its `--issues-json` fixture hook, offline
(ADR-0153 §D1). Nothing in this plan requires a consent flow.

---

## Read this first — six measured facts that decide half the tasks

Every one was re-derived from the tree on 2026-08-17. Two of them contradict the SPEC, and the
contradiction is the work, not a note.

1. **`project-tasks` IS already declared deployed-only.** `staging/sync-to-claude.sh` carries
   `deployed-only: project-tasks` (added in commit `6e9cddf`), so the registry holds **six**
   entries and `--apply` no longer reports the skill. R-02's work is therefore to **delete** that
   line, not to add anything: once the skill is vendored, `pairs-completeness.test.sh` `DO2`
   classifies it as a stale waiver. **The deletion and the PAIRS additions must land in the same
   task** — split across a batch boundary they produce a red `DO2` that has nothing to do with a
   defect.

2. **R-16 names the wrong file.** `reference/file-format.md` does **not** state *"an item with an
   issue number leaves the file"*. Measured, the rule lives in three other places:
   `reference/chain-integration.md` line 79, `reference/capture-sources.md` line 122, and this
   repository's own `TODO.md` header (lines 6–8). Task 8 targets the measured sites **and** adds
   the new sections and promotion keys to `file-format.md`, which is what R-16's other half asks
   for. Do not "satisfy" R-16 by grepping `file-format.md`, finding nothing and moving on.

3. **Everything under `staging/plugin/scripts/tests/` is TESTER-owned.** `test-write-scope.sh`
   denies the coder any write under a path component named `tests/`. Tasks 1, 4, 6 and 9 are tester
   tasks. `.github/workflows/docs-ci.yml` has no `tests/` component and **is** coder-writable.

4. **A new `*.test.sh` needs a manual append to `docs-ci.yml`'s `shell-tests` list.** That file is
   copied into the plant sandbox but **no plant can target it**, so the assertion about it carries a
   declared no-plant reason at its site — `pairs-completeness.test.sh`'s `CI1` is the precedent and
   the wording to copy. Forgetting the append is self-detecting: `CI1` fails naming the harness.
   `shell-tests` is a **required context** on `main` as of 2026-08-17.

5. **The litter is not gitignored where it would land.** `.gitignore`'s `.claude/test-cmd` and
   `.remember/…` patterns contain internal slashes and are therefore root-anchored.
   `git check-ignore` on `staging/plugin/skills/project-tasks/.remember/now.md` returns nothing. A
   `cp -R` of the deployed tree commits one project's transient state. R-03 is a live risk.

6. **Files under `staging/` are mode 644.** Invoke every script as `bash <path>`, never `./<path>`.
   The vendored skill scripts are no exception, and `SKILL.md` must say `bash scripts/…` (it
   already does for `scan.sh`).

## The seven files being vendored, and their PAIRS destinations

Source is `~/.claude/skills/project-tasks/`. Two new scripts are added later, so the block has nine
lines when the feature lands.

| staging path | PAIRS dst | added by |
|---|---|---|
| `plugin/skills/project-tasks/SKILL.md` | `skills/project-tasks/SKILL.md` | Task 2 |
| `plugin/skills/project-tasks/scripts/scan.sh` | `skills/project-tasks/scripts/scan.sh` | Task 2 |
| `plugin/skills/project-tasks/scripts/selftest.sh` | `skills/project-tasks/scripts/selftest.sh` | Task 2 |
| `plugin/skills/project-tasks/reference/file-format.md` | `skills/project-tasks/reference/file-format.md` | Task 2 |
| `plugin/skills/project-tasks/reference/capture-sources.md` | `skills/project-tasks/reference/capture-sources.md` | Task 2 |
| `plugin/skills/project-tasks/reference/chain-integration.md` | `skills/project-tasks/reference/chain-integration.md` | Task 2 |
| `plugin/skills/project-tasks/templates/TODO.template.md` | `skills/project-tasks/templates/TODO.template.md` | Task 2 |
| `plugin/skills/project-tasks/scripts/gh-issues.sh` | `skills/project-tasks/scripts/gh-issues.sh` | Task 5 |
| `plugin/skills/project-tasks/scripts/ledger-merge.sh` | `skills/project-tasks/scripts/ledger-merge.sh` | Task 7 |

**Deliberately not vendored:** `.remember/` (10 files) and `.claude/test-cmd` from the deployed
tree. Session litter, per SPEC *Deliberately not vendored*.

## Files this plan touches

| Path | Action | Owner |
|---|---|---|
| `staging/plugin/scripts/tests/project-tasks-ledger.test.sh` | **create** — the `NT*` harness | tester |
| `staging/plugin/skills/project-tasks/**` (7 files) | **create** — byte-identical vendoring | coder |
| `staging/plugin/skills/project-tasks/scripts/gh-issues.sh` | **create** | coder |
| `staging/plugin/skills/project-tasks/scripts/ledger-merge.sh` | **create** | coder |
| `staging/sync-to-claude.sh` | modify — 9 PAIRS lines added, 1 deployed-only line removed | coder |
| `.github/workflows/docs-ci.yml` | modify — one name appended to `shell-tests` | coder |
| `staging/plugin/skills/concept-to-code/SKILL.md` | modify — Step 7b wiring | coder |
| `staging/plugin/skills/project-conductor/SKILL.md` | modify — between-features wiring | coder |
| `TODO.md` | modify — header rule inverted, sections reshaped | coder |
| `docs/chain-decisions.md` | modify — one narrative block | coder |
| `CLAUDE.md` | modify — one Chain-decision-index line | coder |
| `PROJECT.md` | modify — one row | coder |
| `docs/architecture/ADR-0153-…md` | **already written** by the architect | — |

**Not touched, deliberately.**

- `PROJECT.md`'s format and `project-conductor`'s roadmap handling — SPEC *Out of scope*.
- GitHub label taxonomy, issue templates, any `Stop`-hook auto-capture — SPEC *Out of scope*;
  `reference/chain-integration.md` already rejected the last one and this feature does not reopen
  it.
- `PROJECT.md` Phase 10.0's required-checks table, which says `shell-tests` is not required. It is
  a correct 2026-08-04 snapshot; **do not correct it in place** (rule 14).
- `scan.sh`'s `GITFILE`/`GITLOG`/`STALE`/`MAP`/`NOTE` record types, its `--max-markers` cap and its
  exit-3 root check. Only the `MARKER` predicate changes.
- `.markdownlint-cli2.jsonc` — `staging/plugin/skills` is already in its ignore list, so the
  vendored markdown needs no lint compliance.

## Assertion ids and the harness contract

Prefix **`NT`** in `project-tasks-ledger.test.sh`. Verified 2026-08-17 as unused anywhere in the
corpus (`NT`, `QT`, `VT`, `JT`, `LT`, `GH` all returned 0 hits) — **re-derive before writing**, an
id collision makes two assertions indistinguishable in the registry's output.

The harness **must** emit `FAIL: <id>` with the colon. `plant-check.sh` refuses a declaring harness
that does not (`BADPLANT`, "unattributable"), and five existing harnesses are already stuck in that
state as `VCS-012` records. Use the standard pair:

```bash
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
```

Hermetic, offline, no `$HOME` dependency, no `.git` dependency. Root resolution is
`$(cd "$(dirname "$0")/../../.." && pwd)` for `staging/`, the idiom every sibling uses, so the
harness redirects into the plant sandbox with no change.

## Requirement-id scope, and why the coverage gate will lie to you

`spec-coverage.sh`'s test axis is scoped to test files **named in this plan** (ADR-0138). This plan
names `staging/plugin/scripts/tests/project-tasks-ledger.test.sh` in prose above and in every task
below, so that file is in scope. Requirement ids restart per feature, so a foreign `R-07` in an
unrelated harness can satisfy the gate for this feature's `R-07` (rule 18).

**Label every new assertion block with the ids it answers in its own comment header**, the form the
corpus already uses (`# NT7/NT8 (R-07, R-10) — …`). That is what makes coverage honest here. A
green gate is not evidence; the evidence is the assertion going RED against its plant.

`R-22` and `R-23` carry `(no-test: …)` in the SPEC. The marker exempts them from the **test** axis
only. They still need a citing task, and they have one (Task 10).

### The two `(no-test:)` markers in this SPEC are INERT, and the gate reports them UNCOVERED

Measured 2026-08-17, and it is a limit of `spec-coverage.sh`'s D4 waiver, not of the SPEC's intent.
The waiver is extracted **line-wise**, from the first line of the checklist item only. Both `R-22`
and `R-23` wrap, and both carry `(no-test: …)` on a **continuation** line, so the awk never sees the
clause. Reproduced minimally:

```text
(checkbox syntax elided below — a literal checklist item here would be counted as a task by
 plan-tasks.sh's deliberately loose --count predicate)

  R-01 — a thing (no-test: reason on the same line)     -> COVERED
  R-02 — a thing that wraps
         (no-test: same reason, one line down)          -> UNCOVERED  R-02  tests
```

Run against this SPEC and this plan at design time, before a line was written:

```text
spec-coverage.sh --spec SPEC.md --plan <this file> --tests-root staging/plugin/scripts/tests
  -> 23 declared, 4 COVERED, 3 UNCOVERED (R-21, R-22, R-23 — all on the tests axis),
     16 UNSCOPED, 5 files in scope
```

The **plan axis is fully covered**: zero ids report `UNCOVERED … plan`. The three on the tests axis
resolve differently:

- **R-21** greens naturally at Task 9. The harness will exist and will cite `R-21` in its header.
- **R-22 and R-23** are documentation obligations with no assertion behind them, which is exactly
  what their markers say. The clean fix is a **one-line rewrap in `SPEC.md`** so each
  `(no-test: …)` clause sits on its item's first line. That is an edit to `SPEC.md` and therefore
  the operator's call at Gate 2, not the coder's and not this plan's — the architect's write scope
  excludes it. Without the rewrap the Step 5 → Step 6 gate reports two ids UNCOVERED on the tests
  axis, and the correct response is to rewrap, **never** to sprinkle `R-22`/`R-23` into a harness
  comment to buy a green. A citation is not an assertion, and manufacturing one is the exact hazard
  ADR-0138 named.

Do not "fix" this by widening the harness's id mentions. Surface it, rewrap, re-run.

## Ownership and batching, with the expected reds declared in advance (ADR-0101)

An assertion must not sit in the same batch as the task that greens it, so intermediate checkpoints
are RED **by design**. Every red below is declared. Anything else halts.

| Batch | Tasks | Agent | Expected checkpoint state |
|---|---|---|---|
| A | 1 | tester | RED — every `NT*` fails; nothing exists yet. `CI1` also RED (new harness not in `docs-ci.yml`) |
| B | 2, 3 | coder | vendoring + scanner reds go green; `gh-issues`/`ledger-merge` blocks still RED |
| C | 4 | tester | `NT` GitHub-read assertions added, all RED |
| D | 5 | coder | GitHub-read block green |
| E | 6 | tester | `NT` merge assertions added, all RED |
| F | 7 | coder | merge block green; full suite green except the prose pins |
| G | 8 | coder | prose pins green; full suite green |
| H | 9 | tester | plants declared, each seen RED once; `plant-check.sh` green |
| I | 10 | coder | record lands; full suite + registry green |

---

### Task 1 — The structural, litter and scanner assertions, written RED (R-01, R-02, R-03, R-15, R-19, R-20)

**Tester-owned.** Create `staging/plugin/scripts/tests/project-tasks-ledger.test.sh`. Every
assertion below fails at the end of this task; that is the point.

- `NT0` (R-01) — **denominator guard.** The vendored tree
  `staging/plugin/skills/project-tasks/` exists and holds at least 7 regular files, each of the
  seven named individually. Zero files reads exactly like a clean absence check (rule 7), so this
  runs before `NT2`.
- `NT1` (R-01) — every one of the nine PAIRS `src|dst` lines in the table above is present in
  `staging/sync-to-claude.sh`'s `PAIRS` block, matched whole-line against the block extracted with
  `awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f'` — the same extraction `pairs-completeness.test.sh`
  uses. **Nine, not seven**: Tasks 5 and 7 add two more and this assertion is what notices if they
  do not.
- `NT2` (R-03) — **absence.** No path component `.remember` and no `.claude/test-cmd` anywhere under
  the vendored skill. Declare at the site, in a comment, that this assertion carries **no plant**
  and why: a plant substitutes a needle inside an existing file and cannot create litter that is
  not there (ADR-0153 §D8).
- `NT3` (R-03) — **backward self-test.** Build a fixture directory under `$TMP` containing
  `.remember/now.md` and `.claude/test-cmd`, run `NT2`'s exact detection predicate against it, and
  assert it flags both. Without this, `NT2` is satisfiable by a predicate that detects nothing —
  the `DO4`/`DO5` shape. **This one carries a plant** (self-targeting on the predicate).
- `NT4` (R-02) — `staging/sync-to-claude.sh` contains **no** `deployed-only: project-tasks` line.
  Build the needle at run time (`DMARK="deployed""-only"`) so this harness does not match its own
  explanatory prose (rule 12) — the idiom `pairs-completeness.test.sh` line 226 already uses.
- `NT5` (R-02) — the deployed-only registry still holds at least 5 declarations after the removal,
  so `DO1`'s floor is not breached by this feature. Vacuity guard, no plant (rule 10 — a floor
  absorbs its own plant).
- `NT6` (R-15) — **the two measured false positives no longer fire.** Fixture holds, verbatim:
  a line `# UF. THE SELF-COLLISION IS EXPECTED, NOT A BUG (ADR-0059 §D4)` and a line
  `# plant: RRP1 | x.sh | needle | echo NONEMPTY-BUG`. Run the vendored `scan.sh --root <fixture>`
  and assert **zero** `MARKER` records from those two lines.
- `NT6b` (R-15) — **a markdown prose line in declaration form does not fire.** Fixture holds
  ``- narrowed: it matches `TODO:`, `FIXME:` and `XXX:` with the colon`` in a `.md` file. Zero
  `MARKER` records. This is the half the colon test alone cannot reject (ADR-0153 §D9).
- `NT7` (R-15) — **genuine markers still fire, in both shapes.** Fixture holds `// TODO: extract`,
  `// FIXME: leaks`, `// HACK: monkeypatch` on their own lines and `foo(); // TODO: fix` as a
  trailing comment. Assert exactly 4 `MARKER` records and that `FIXME` is classified as `FIXME`.
- `NT8` (R-20) — the six hard rules are still stated in the vendored `SKILL.md`: never edits source,
  never writes before the approval gate, never invents an entry, never deletes user text, never
  auto-closes, refuses a project root outside the session CWD. Match a flattened, undecorated,
  case-insensitive copy of each clause (rule 3), not the literal line.
- `NT9` (R-19) — the vendored `SKILL.md`'s `description:` names `concept-to-code` and
  `project-conductor`, **and** both of those skills' own `SKILL.md` name `project-tasks`. Both
  directions in one assertion: a description claiming a wiring that does not exist is what made this
  requirement necessary. RED until Task 8.
- `NT10` (R-01) — `project-tasks` appears in `.github/workflows/docs-ci.yml`'s `shell-tests` list as
  `project-tasks-ledger`. **No plant, declared reason at the site**: `plant-check.sh`'s sandbox
  copies `staging/` and `docs/`, `.github/` is copied for reading but is not a legal plant target,
  so this assertion's mechanism is unreachable by mutation. Copy `CI1`'s wording (issue #331).

Do **not** modify `selftest.sh` here — it is inside the skill tree and belongs to Task 3.

Budget: `staging/plugin/scripts/tests/project-tasks-ledger.test.sh` (~260 lines).

### Task 2 — Vendor byte-identically, wire PAIRS, remove the stale waiver, append to CI (R-01, R-02, R-03)

**Coder-owned.** One task, deliberately: the PAIRS addition and the deployed-only removal cannot be
separated (fact 1).

1. Copy the **seven** files from `~/.claude/skills/project-tasks/` into
   `staging/plugin/skills/project-tasks/`, preserving the directory layout, with **no edit of any
   kind**. Verify with `diff -r` between the two trees, excluding `.remember` and `.claude`: the
   only differences reported must be those two exclusions.
2. Do **not** copy `.remember/` or `.claude/test-cmd`. Confirm with
   `find staging/plugin/skills/project-tasks -name '.remember' -o -name 'test-cmd'` returning
   nothing.
3. Add the **seven** PAIRS lines from the table to `staging/sync-to-claude.sh`. Place them together,
   after the `plugin/skills/project-conductor/…` block, so the diff is one contiguous hunk.
4. **Delete** the `deployed-only: project-tasks` line. Leave the surrounding registry comment intact
   — its explanation of why the registry exists is not about this skill.
5. Append `project-tasks-ledger` to the `for t in …` list in `.github/workflows/docs-ci.yml`'s
   `shell-tests` job. One name, at the end of the list, no reformatting of the line.
6. Run `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` and confirm `DO1`, `DO2`,
   `CI1`, `CI2` and the `check_complete` reverse pass are all green.

**Manual verification, recorded not automated (ADR-0153 §D5, R-01).** Run
`bash staging/sync-to-claude.sh` (dry run, no `--apply`) and confirm it reports **no** `NEW` and no
`CHANGED` for any `skills/project-tasks/…` path — at this instant the vendored copy and the deployed
copy are byte-identical, and this is the only moment in the feature where that is true. Record the
output in the task report. CI cannot check this: it has no `$HOME/.claude`.

Budget: `staging/plugin/skills/project-tasks/**`, `staging/sync-to-claude.sh`,
`.github/workflows/docs-ci.yml` (~30 lines changed outside the copied files).

### Task 3 — Narrow the marker predicate, in the vendored copy only (R-15)

**Coder-owned.** Edit `staging/plugin/skills/project-tasks/scripts/scan.sh` and its `selftest.sh`.

Replace the single `MARKER_RE` test with the two-part predicate of ADR-0153 §D9. A line contributes
a `MARKER` record when **both** hold:

- the keyword is in declaration form — `TODO:`, `FIXME:`, `HACK:`, `XXX:`, `BUG:` — with the colon
  immediately after the keyword and a non-word character or line start before it;
- a comment leader (`//`, `#`, `--`, `/*`, `*`, `<!--`, `;`) appears **earlier on the same line**
  than the keyword, so `foo(); // TODO: fix` qualifies and a markdown prose line does not.

Constraints:

- Bash 3.2 and POSIX ERE. Both the `rg` path and the `grep` fallback must apply the **same**
  predicate — `selftest.sh`'s existing *"grep fallback finds the same markers"* assertion is what
  catches a divergence, and it must stay green.
- `MARKER_RE` is also used by the `STALE`/`marker-gone` detection at `scan.sh` line 148. Narrowing it
  there is correct and intended: a `src:marker` entry whose marker is now only a prose mention should
  be proposed for closure.
- Do **not** exclude `.md` from the scan. That was rejected (ADR-0153 alternative 9).
- Extend `selftest.sh`'s fixture with the two false-positive shapes and the trailing-comment shape,
  and add the matching assertions. Its existing *"finds exactly 3 markers"*, *"ignores
  embedded-keyword decoys"* and *"two consecutive runs are identical"* assertions must stay green —
  all three fixture markers are `// KEYWORD:` and survive the narrowing.

Verify against the real repository: `bash staging/plugin/skills/project-tasks/scripts/scan.sh` from
the repo root must report **zero** `MARKER` records for
`staging/plugin/scripts/tests/untrusted-input.test.sh` and
`staging/plugin/scripts/tests/recovery-preflight.test.sh`, and zero for `SPEC.md`. Record the
before/after counts (5 before) in the task report.

Budget: `staging/plugin/skills/project-tasks/scripts/scan.sh`,
`staging/plugin/skills/project-tasks/scripts/selftest.sh` (~90 lines).

### Task 4 — The GitHub-read assertions, written RED (R-04, R-05, R-06)

**Tester-owned.** Extend `project-tasks-ledger.test.sh`. Every assertion drives `gh-issues.sh`
through `--issues-json <file>`; nothing here calls `gh`, touches the network or reads `$HOME`.

- `NT11` (R-04) — with a fixture JSON of 3 open issues, `gh-issues.sh --issues-json <f>` exits 0 and
  emits exactly 3 `ISSUE` records, one per number, each carrying number, state, title and labels.
- `NT12` (R-04) — a fixture containing the same issue number twice is a **detectable failure**: exit
  3, with the duplicated number named on stderr. Not a silently deduplicated section.
- `NT13` (R-05) — with an empty-array fixture and a `--ledger` whose `GitHub Issues` section already
  holds 2 `#NNN` references, the run emits a `DIDNOTRUN` record naming a broken derivation and exits
  non-zero. Assert the exit code **and** the record: a broken derivation that exits non-zero with no
  record is indistinguishable from a crash.
- `NT13b` (R-05) — with an empty-array fixture and a `--ledger` whose section is **empty**, the run
  exits 0 and emits an empty section. Zero can be correct, and this is the assertion that stops
  `NT13` from being a blanket refusal of zero.
- `NT14` (R-06) — with **no** `--issues-json` and `gh` unavailable on `PATH` (run under a
  `PATH="$TMP/nobin:/usr/bin:/bin"` prefix, the idiom `selftest.sh` line 109 already uses), the run
  emits a `DIDNOTRUN` record whose text names **both** a cause and a remedy, and exits with the
  reserved *did-not-run* code — never 0. Rule 4: an unrun check must not read as a clean one.
- `NT14b` (R-06) — the three causes are distinguishable in the record's text: `gh` absent,
  unauthenticated, and no remote. Drive the second and third through the script's own injectable
  probes; if a cause cannot be produced without a network, assert the branch's message string
  instead and say in the comment header that it is a text pin, not an executed branch (rule 16).
- `NT15` (R-06) — on the `DIDNOTRUN` path the caller must be able to leave the section untouched:
  assert `gh-issues.sh` writes **nothing** to the ledger file under any invocation. It is a reporter
  of evidence, not a writer, exactly as `scan.sh` is.

Each block's comment header cites its ids (`# NT13/NT13b (R-05) — …`) so the scope filter admits
them (ADR-0138).

Budget: `staging/plugin/scripts/tests/project-tasks-ledger.test.sh` (~150 lines added).

### Task 5 — Write `gh-issues.sh` (R-04, R-05, R-06)

**Coder-owned.** Create `staging/plugin/skills/project-tasks/scripts/gh-issues.sh` and add its
PAIRS line.

Contract, stated in the file's own header:

```text
gh-issues.sh — a CHECKER. The caller branches on the exit code.
  0  the read succeeded; ISSUE records on stdout (possibly zero, legitimately)
  2  bad invocation
  3  could not evaluate — DIDNOTRUN record on stdout naming cause and remedy
  4  broken derivation — zero issues where the ledger's section previously held entries

Usage: bash gh-issues.sh [--ledger FILE] [--issues-json FILE] [--repo OWNER/NAME]

Records (TSV):
  ISSUE     number  state  title  labels
  DIDNOTRUN cause   remedy
```

- The only GitHub call is `gh issue list --state open --limit 300 --json number,title,state,labels`.
  `--issues-json <file>` reads the same payload from a file instead, the offline hook
  `staging/plugin/scripts/roadmap-from-issues.sh` line 21 already establishes.
- JSON parsing: `gh --jq` on the live path. On the `--issues-json` path, parse with `awk`/`sed` or
  re-run the payload through `gh`'s jq only if `gh` is present — **the fixture path must work with
  `gh` absent**, which is `NT14`'s whole premise. Prefer a small `awk` reader over adding a `jq`
  dependency the skill does not have.
- Exit 4's guard reads the `--ledger` file's `GitHub Issues` section and counts `#NNN` tokens. Zero
  issues plus zero previous entries is exit 0 (`NT13b`); zero issues plus a non-empty previous
  section is exit 4 (`NT13`). Guard the denominator, not only the matches (rule 7).
- Writes nothing, ever. Bash 3.2 clean.

Budget: `staging/plugin/skills/project-tasks/scripts/gh-issues.sh`, `staging/sync-to-claude.sh`
(~150 lines).

### Task 6 — The ledger-merge assertions, written RED (R-07, R-08, R-09, R-10, R-11, R-12, R-13, R-14, R-18)

**Tester-owned.** Extend `project-tasks-ledger.test.sh`. Fixtures are `TODO.md` files under `$TMP`;
`ledger-merge.sh` never writes, so every assertion compares stdout against an expectation.

- `NT16` (R-07) — **the pass-through contract.** Feed a fixture carrying an unknown section, free
  prose, a hand-written entry with no id, and a stray HTML comment. `diff` the output against the
  input: the only differing lines are inside the `GitHub Issues` section, a provenance comment, or
  the `Steps` header. This is the assertion the whole safety argument rests on (ADR-0153 §D2) — do
  not relax it later to accommodate a new section.
- `NT17` (R-07) — local priority (`**P2**`), file reference (`` `path:line` ``), `src:` and
  `opened:` survive verbatim across a run whose issue payload changes the title, state and labels of
  the same entry.
- `NT18` (R-10) — `runs:` goes absent → `runs:1` → `runs:2` across three successive `--mode full`
  invocations, each fed the previous output. `opened:` is byte-identical in all three.
- `NT19` (R-10, R-08) — under `--mode quick`, `--mode add`, `--mode close` and `--mode map`, `runs:`
  is **unchanged** and no promotion proposal is rendered. Four sub-assertions, one per mode; a loop
  over one mode would pass with three modes unimplemented.
- `NT20` (R-08) — the proposal set under `--mode full` is exactly: every `P1`, every `src:review`,
  and every entry with `runs:` >= 2. Assert an entry that is `P3`, not `src:review`, and at
  `runs:1` is **not** proposed — the negative case is what proves the predicate is a filter and not
  a pass-through.
- `NT21` (R-09) — an entry carrying `promote:declined` is absent from the proposal set on a run
  where every other qualifying condition holds. Then feed the output back and assert it is still
  absent: *never proposed again* is a claim about subsequent runs, not about one.
- `NT22` (R-11) — after `--promote VCS-031=470`, the entry is **one** line in `GitHub Issues`
  carrying both `` `VCS-031` `` and `#470`, and `VCS-031` appears exactly once in the whole file.
  Assert the whole-file count, not just the section's absence.
- `NT23` (R-04) — the helper's own output self-check: a fixture where the rendered section would
  drop an issue exits 3 naming the number. Drive it by handing the helper an issue set the section
  template cannot render, or by planting the count comparison; state which in the comment header.
- `NT24` (R-12) — with a `--manifests` fixture holding exactly one non-terminal manifest, the
  `Steps` header names that manifest and the case token reads *derived*.
- `NT25` (R-13) — with **zero** non-terminal manifests the section is omitted **and** a one-line
  reason is emitted; with **two** the section names both candidates and derives nothing. Assert the
  stated reason in the zero case: a silently absent section and a deliberately omitted one must not
  read alike (rule 4).
- `NT26` (R-14) — an issue number that also appears as a `PROJECT.md` roadmap row renders with a
  phase pointer; one that does not, renders without. Both directions, one `PROJECT.md` fixture.
- `NT27` (R-18) — `--p1-gate --since <date>` classifies an open `P1` with `opened:` after the date
  as **new** and one before it as **pre-existing**, with distinct exit codes so a caller can branch
  (rule 5). Assert both codes and the id lists.

Every block's comment header cites its ids. `NT16`'s header additionally records that it is the
contract assertion of ADR-0153 §D2.

Budget: `staging/plugin/scripts/tests/project-tasks-ledger.test.sh` (~320 lines added).

### Task 7 — Write `ledger-merge.sh` (R-07, R-08, R-09, R-10, R-11, R-12, R-13, R-14, R-18)

**Coder-owned.** Create `staging/plugin/skills/project-tasks/scripts/ledger-merge.sh` and add its
PAIRS line.

Contract, stated in the file's own header:

```text
ledger-merge.sh — a pure filter. Reads TODO.md, writes a CANDIDATE to stdout, never touches disk.

THE CONTRACT: the output is byte-identical to the input EXCEPT inside three regions —
  1. the `GitHub Issues` section
  2. each entry's provenance comment (runs:, promote:)  — never `opened:`, never `src:`
  3. the `Steps — <feature>` section header
Everything else passes through unread: unknown sections, free prose, hand-written entries with
no id, every HTML comment that is not the header.

Usage: bash ledger-merge.sh --ledger FILE [--issues TSV] [--manifests DIR] [--roadmap FILE]
                            [--today YYYY-MM-DD] [--mode full|quick|add|close|map]
                            [--proposals FILE] [--promote ID=NNN] [--promote-declined ID]
                            [--p1-gate --since YYYY-MM-DD]
  0 clean   2 bad invocation   3 could not evaluate / self-check failed
```

Design points that are not negotiable:

- **`runs:` is derived, never accumulated** (ADR-0153 §D3). `<value on disk> + 1`, computed inside a
  filter that never writes. Increment only under `--mode full`.
- **`opened:` is copied verbatim** and is never in the rewritten key set.
- **Self-check before exit** (R-04): every `ISSUE` number in the input appears exactly once in the
  rendered section, and every local id appears exactly once in the whole file. A mismatch is exit 3
  with the ids named — never a short section.
- **`--proposals <file>`** is a separate output stream. Do not multiplex proposals onto stdout,
  which carries the candidate file.
- **The `Steps` section is a header plus a case token only.** The described lines are the model's
  job (ADR-0153 alternative 10). Three cases: exactly one non-terminal manifest → *derived from
  `<name>`*; zero → omitted with a stated reason; two or more → the candidates named, nothing
  derived. "Non-terminal" is `current_step` **and** `status` both non-terminal, and `status:
  aborted` is terminal even when `current_step` is not (ADR-0113).
- **`--p1-gate`** is a checker: distinct exit codes for *new `P1` present*, *only pre-existing `P1`*
  and *none*, with the ids on stdout. Its caller in `concept-to-code` branches on the code.
- Bash 3.2 driving `awk`. No `python3`, no `jq` (ADR-0153 alternatives 3 and 4). One file, not a
  separate `.awk` — one consumer, so ADR-0086's criterion says do not extract.

Budget: `staging/plugin/skills/project-tasks/scripts/ledger-merge.sh`, `staging/sync-to-claude.sh`
(~380 lines).

### Task 8 — The skill text, the reference docs, the ledger reshape and the chain wiring (R-16, R-17, R-18, R-19, R-20)

**Coder-owned.** Prose, in five places. Every claim here is an **instruction, not an enforcement**
(rule 16); the harness pins that the text exists and nothing pins that it is obeyed.

1. **`staging/plugin/skills/project-tasks/SKILL.md`** — add the GitHub read and the merge to the
   workflow checklist (steps 3b and 6b), document the promotion gate, the `DID-NOT-RUN` path and the
   `Steps` section. Keep the six hard rules **verbatim** (`NT8` pins them). Keep the
   `description:` frontmatter's claim about the two chains — Task 8 item 4 makes it true rather than
   narrowing it (R-19). `selftest.sh`'s frontmatter check caps `description:` at 1024 characters;
   re-run it after editing.
2. **`reference/file-format.md`** — document the `GitHub Issues` and `Steps` sections, the
   `runs:`/`promote:` keys, and the field-ownership table. Add the preservation rule for the three
   merge regions (R-16).
3. **The superseded rule, at its three measured sites** (fact 2): rewrite
   `reference/chain-integration.md` line 79's *"A roadmap feature is not duplicated as an entry"*
   into the phase-pointer rule; rewrite `reference/capture-sources.md` line 122's *"Work already
   tracked in `PROJECT.md`… "* the same way; rewrite `TODO.md`'s header (lines 6–8), which currently
   states the rule this feature inverts (R-16).
4. **`staging/plugin/skills/concept-to-code/SKILL.md`** — add Step 7b immediately before Step 7's
   commit gate, invoking `project-tasks` and then branching on `ledger-merge.sh --p1-gate`: a new
   `P1` stops and surfaces, a pre-existing `P1` is reported and does not block (R-17, R-18). Use the
   snippet in `reference/chain-integration.md` as the base and add the gate branch.
5. **`staging/plugin/skills/project-conductor/SKILL.md`** — invoke the skill in the loop that
   advances between features, after a row is marked `[x]`, before the next feature starts. Step 5 or
   Step 6A is the placement; read both and pick the one that runs on every advance (R-17).
6. **`TODO.md`** — reshape to the new section order, keep every existing id and `lastId=27`
   untouched, and move `VCS-022`/`VCS-023` to `Done` with today's date once Tasks 2 and 3 have
   landed. Do not renumber anything.

Budget: `staging/plugin/skills/project-tasks/SKILL.md`,
`staging/plugin/skills/project-tasks/reference/*.md`,
`staging/plugin/skills/concept-to-code/SKILL.md`,
`staging/plugin/skills/project-conductor/SKILL.md`, `TODO.md` (~220 lines).

### Task 9 — Plants for every new assertion, and the registry run (R-21)

**Tester-owned.** One `# plant:` declaration per new assertion, at **column 1**, beside the
assertion it proves, four fields separated by ` | ` (three to delete the needle). ` | ` may not
appear inside any field. The needle must match **exactly once** in the target file.

Targets are staging-relative:
`plugin/skills/project-tasks/scripts/scan.sh`,
`plugin/skills/project-tasks/scripts/gh-issues.sh`,
`plugin/skills/project-tasks/scripts/ledger-merge.sh`,
`plugin/skills/project-tasks/SKILL.md`,
`plugin/skills/project-tasks/reference/*.md`,
`plugin/skills/concept-to-code/SKILL.md`,
`plugin/skills/project-conductor/SKILL.md`,
`sync-to-claude.sh`, and `plugin/scripts/tests/project-tasks-ledger.test.sh` itself for `NT3`
(self-targeting plants work — the registry masks `# plant:` lines before matching).

**Three assertions carry no plant, each with its reason stated at its own site**, not here:

- `NT2` — a plant substitutes, it cannot create litter (ADR-0153 §D8).
- `NT5` — a floor absorbs its own plant (rule 10). Stated as a vacuity guard.
- `NT10` — `.github/` is copied into the sandbox but is not a legal plant target. Copy `CI1`'s
  wording.

Then:

1. `bash staging/plugin/scripts/tests/project-tasks-ledger.test.sh` — green.
2. `bash staging/plugin/scripts/tests/plant-check.sh` — every new plant reports `FIRED`, none
   `NOFIRE`, `BADPLANT` or `VACUOUS`. **Inspect what each plant actually produced** before believing
   the verdict (rule 2). A `VACUOUS` verdict means the assertion was already red in the unmutated
   sandbox — fix the assertion, not the plant.
3. Full suite via `.claude/test-cmd`.
4. `bash staging/plugin/skills/project-tasks/scripts/selftest.sh` — 27+ passed, 0 failed.

Budget: `staging/plugin/scripts/tests/project-tasks-ledger.test.sh` (~60 lines of declarations).

### Task 10 — The record (R-22, R-23)

**Coder-owned.** The ADR is already written; this task lands the other four artifacts.

1. **`docs/chain-decisions.md`** — append a block headed
   `## Decisions from the project-tasks-vendored-bilateral-ledger chain (ADR-0153)`, following the
   established shape: one paragraph naming the files, then `Key architectural decisions:` as
   bullets, then `Detail: docs/architecture/ADR-0153-…md`. It **must** carry the
   instruction-versus-enforcement bullet (R-23): the chain wiring is prose a model is asked to
   follow, and a green harness pinning that the sentence exists is not evidence it is obeyed.
2. **`CLAUDE.md`** — one line at the end of the Chain decision index, matching the existing form:
   `- **ADR-0153** — <one clause> → docs/architecture/ADR-0153-…md`. Nothing else in `CLAUDE.md`
   changes; the nineteen rules are not touched.
3. **`PROJECT.md`** — one row recording the feature. Read the phase table before writing and follow
   the surrounding phase's own form (table row versus checkbox — Phases 11 to 13 use tables and say
   why). **Do not** correct Phase 10.0's required-checks line (rule 14).
4. Re-run `npx markdownlint-cli2` over the touched markdown, and the full suite one final time.

`R-22` and `R-23` carry `(no-test: …)` in the SPEC: the marker exempts them from the test axis, not
from needing a task. This is that task.

Budget: `docs/chain-decisions.md`, `CLAUDE.md`, `PROJECT.md` (~70 lines).

---

## Staleness — what asserts the old behaviour and must be updated

Grepped across the tree at design time, 2026-08-17.

| Site | What it asserts today | Action |
|---|---|---|
| `staging/sync-to-claude.sh` line 116 | `project-tasks` is deployed-only | **delete** (Task 2) |
| `pairs-completeness.test.sh` `DO1` | registry holds >= 5 | unchanged; verify still >= 5 after the deletion (`NT5`) |
| `pairs-completeness.test.sh` `CI1` | every harness is in the CI list | greens when Task 2 appends |
| `pairs-completeness.test.sh` `check_complete plugin/skills '*/SKILL.md'` | every staged SKILL.md is in PAIRS | greens when Task 2 adds the entry |
| `skill-coverage-perimeter.test.sh` `S1` | every skill is named by a test or declares an exemption | greens because `project-tasks-ledger.test.sh` contains the literal `project-tasks/SKILL.md` — **the harness must spell that path literally**, a glob does not satisfy `S1` |
| `skill-coverage-perimeter.test.sh` `S0` | >= 25 staged skills | count rises by one; unaffected |
| `TODO.md` lines 6–8 | an issue-numbered item leaves the file | **rewrite** (Task 8) |
| `TODO.md` `VCS-022`, `VCS-023` | open | **move to Done** (Task 8) |
| `TODO.md` `VCS-027` | records the rule this feature inverts | leave the entry; the rule around it changed |
| `reference/chain-integration.md` line 79 | roadmap features are not duplicated | **rewrite** (Task 8) |
| `reference/capture-sources.md` line 122 | roadmap work never becomes an entry | **rewrite** (Task 8) |
| `selftest.sh` "finds exactly 3 markers" | the old predicate's count | stays 3; **verify**, do not assume (Task 3) |
| `selftest.sh` "grep fallback finds the same markers" | both scan paths agree | must stay green after the narrowing (Task 3) |
| `selftest.sh` frontmatter check | `description:` <= 1024 chars | re-run after Task 8 edits the description |

**Run the FULL suite after Tasks 2, 3, 7 and 8**, not just the new harness. Every one of them
changes a contract another harness reads: `sync-to-claude.sh`'s PAIRS block is read by
`pairs-completeness.test.sh`, `litter-discipline.test.sh` and `skill-coverage-perimeter.test.sh`;
`concept-to-code/SKILL.md` is read by roughly a dozen.

## Risks and HITL gates

- **`ledger-merge.sh` edits the user's durable record.** The byte-identical-outside-three-regions
  contract (`NT16`) is the only thing standing between a bug and silent loss of hand-written ledger
  content. Do not relax `NT16` to accommodate a future section.
- **`docs-ci.yml`'s append is unplantable.** `NT10` asserts it and cannot be proven by mutation. The
  real guard is `CI1`, which is planted and lives in a different file.
- **The deployed-only deletion and the PAIRS addition are one task by necessity.** Splitting them
  produces a red `DO2` with no defect behind it.
- **`DO1`'s floor lands exactly on 5 after the deletion.** The next removal turns it red for a
  reason unrelated to that removal.
- **`gh` is optional and every assertion about it runs offline.** Nothing here needs a consent flow
  or a token in CI.
- **HITL gates:** commit, push, and the `sync-to-claude.sh --apply` that deploys the vendored skill
  over the live one in `~/.claude/`. The `--apply` is a write outside the repository and must not
  happen unattended. No schema change, no deletion of user data, no migration.

## Requirement coverage map

| Id | Tasks |
|---|---|
| R-01 | 1, 2 |
| R-02 | 1, 2 |
| R-03 | 1, 2 |
| R-04 | 4, 5, 6 |
| R-05 | 4, 5 |
| R-06 | 4, 5 |
| R-07 | 6, 7 |
| R-08 | 6, 7 |
| R-09 | 6, 7 |
| R-10 | 6, 7 |
| R-11 | 6, 7 |
| R-12 | 6, 7 |
| R-13 | 6, 7 |
| R-14 | 6, 7 |
| R-15 | 1, 3 |
| R-16 | 8 |
| R-17 | 8 |
| R-18 | 6, 7, 8 |
| R-19 | 1, 8 |
| R-20 | 1, 8 |
| R-21 | 9 |
| R-22 | 10 |
| R-23 | 10 |

CODER-MODEL CANDIDATE: sonnet
