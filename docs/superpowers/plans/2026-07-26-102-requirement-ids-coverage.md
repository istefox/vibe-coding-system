# Plan — #102 Requirement IDs in the SPEC, and a coverage check

- **Issue:** #102 · **ADR:** `docs/architecture/ADR-0048-102-requirement-ids-coverage.md`
- **SPEC:** `SPEC.md`
- **Branch:** `feat/102-requirement-ids-coverage` (stacked on `feat/101-weakening-scan-wiring`,
  itself stacked on `feat/100-secret-scan-dependency-gate`; both PRs open, neither merged)
- **Test command:** `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
- **Style:** TDD. Every assertion is seen RED before the edit that makes it GREEN, except the
  forward guards, which are labelled as such in the harness and are never fix evidence.

---

## Before you start — read these eight things

1. **The `ADR-NNNN` collision is the whole design.** `grep -rE 'R-[0-9][0-9]' docs/specs/` matches
   30+ of the 34 existing SPECs, every match coming from the letter run in `ADR-0016`, `ADR-0047`.
   The matcher must be anchored on **both** sides:
   `(^|[^A-Za-z0-9_])R-[0-9][0-9]([^0-9]|$)`. With both anchors the only matches in the entire
   repository are two prose lines in `docs/specs/102-*.spec.md`. Do not relax either anchor.
2. **Backward compatibility is the hard gate.** A SPEC with no IDs produces **exit 0, empty stdout,
   empty stderr**. Not a warning, not "0 IDs OK", not a summary line. Task 3 asserts this against all
   34 real specs, and it is the assertion that must never be weakened to make something else pass.
3. **`grep -c` prints `0` AND exits 1 on no match.** `n=$(grep -c X f || echo 0)` yields the two-line
   string `0\n0`. Issue #100 hit this. Use the `count_re()` shape from `secret-scan.sh:103`
   (`_c=$(grep -c "$1" "$2" 2>/dev/null); printf '%s' "${_c:-0}"`), or `|| true`. Never `|| echo 0`.
4. **The neighbouring gate has the opposite caller idiom.** `weakening-scan.sh` always exits 0 and
   signals through stdout; `spec-coverage.sh` signals through the exit code. The two blocks end up
   four lines apart in the same file. Do not copy branching between them, and do not "harmonise"
   them — ADR-0048 §D5 requires the warning sentence to be present at the call site, and Task 6
   asserts it.
5. **Bash 3.2:** no associative arrays, no `mapfile`, no `${v^^}`, no process substitution, no `<<<`.
   BSD `sed`/`awk` on Darwin: no GNU-only `sed a\`, no `\b` in ERE.
6. **`~/.claude` has two script locations.** Skill helpers land at `skills/<name>/scripts/`,
   everything else is flattened into `hooks/`. This script is a skill helper. A resolution block
   copied from #100's two reporters (which are in `hooks/`) resolves nothing and skips the gate
   forever. Task 5 asserts the path shape, including the absence of `hooks/spec-coverage.sh`.
7. **`pairs-completeness.test.sh` cannot catch a missing `PAIRS` entry for this script.** Its
   `check_complete` covers `plugin/agents/*.md`, `user/rules/*.md` and `plugin/skills/*/SKILL.md`
   only — `plugin/skills/*/scripts/*` is deliberately out of its scope (ADR-0024). The new harness
   must carry its own `PAIRS` assertion or the entry can be forgotten with nothing reporting it.
8. **Assertion labels in the new harness are `R`-prefixed** (`RA1`, `RD3`, `RG2`). Nine harnesses use
   bare `A`–`G` and `weakening-wiring` uses `W`; all print into the same CI job.

**Files this feature touches — nothing outside this list:**

| file | what |
|---|---|
| `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` | **new** checker |
| `staging/plugin/scripts/tests/spec-coverage.test.sh` | **new** harness |
| `staging/plugin/skills/concept-to-code/SKILL.md` | Step 5 gate block, report schema, read contract, Step 2 dispatch line |
| `staging/plugin/skills/interview-driver/SKILL.md` | line 13 gains the enumeration requirement |
| `staging/plugin/skills/spec-from-issue/SKILL.md` | Success-criteria template + one guardrail bullet |
| `staging/plugin/agents/architect.md` | Output Format → Implementation plan bullet |
| `staging/sync-to-claude.sh` | one `PAIRS` line |
| `.github/workflows/docs-ci.yml` | one name appended to the explicit list |
| `CLAUDE.md`, `docs/vibe-coding-system.md`, `docs/GUIDA-USO-IT.md` | docs (Task 10) |

**Contract-staleness sweep, already run — these are the call sites of the things being changed.**
Do not go hunting; this is the complete list and each entry is assigned to a task.

- **`step5-report.json` readers** (gaining the additive `requirement_coverage` object):
  - `staging/plugin/skills/concept-to-code/SKILL.md:684-728` — schema block and orchestrator read
    contract (Task 6).
  - `staging/plugin/skills/autopilot-build/SKILL.md:207-210` — Step 5 circuit breaker. **No change**
    (ADR-0048 §D10): the c2c gate halts before autopilot-build interprets the report. Verify it is
    untouched in Task 10.
  - `staging/plugin/scripts/tests/step5-checkpoint-review.test.sh` section D — asserts
    `checkpoint_reviews` only; an additive key cannot break it. **Verify, do not assume** (Task 10).
  - `staging/plugin/scripts/tests/weakening-wiring.test.sh` section WD — asserts
    `weakening_findings` in the same schema block. An addition after it is safe; a **reflow** of the
    block is not. Do not reformat the schema, append to it (Task 6, Task 10).
  - `staging/plugin/skills/concept-to-code/tests/run-tests.sh:326-329` — asserts the string
    `step5-report.json` is present; additive-safe. `$HOME`-coupled and CI-dark; do not run it as
    evidence.
  - `docs/GUIDA-USO-IT.md:282` — Italian circuit-breaker sentence, now incomplete (Task 10).
- **`concept-to-code/SKILL.md` heading references:** `workflow-dispatch-pins.test.sh` B4a/B4b/B5 pin
  two Step 5/Step 6 workflow headings and the absence of an old shared one. **Rename no heading.**
  Adding a new uniquely-named `####` heading is safe and is what §D5 requires.
- **`agents/architect.md` assertions:** `agent-tool-scoping.test.sh` A1, A10–A14 all read **line 4**
  (the `tools:` frontmatter line) or the body's Command-scope bullet. Task 8 edits the Output Format
  section only. Do not touch line 4 and do not touch the Command-scope or Write-scope bullets.
- **`interview-driver/SKILL.md` assertions:** `skill-text-corrections.test.sh` E-section requires
  `disable-model-invocation: true`, F3 requires the frontmatter to parse. Task 8 edits line 13 only
  (body). Do not touch the frontmatter.
- **`spec-from-issue/SKILL.md`:** no harness asserts on it today. Task 7 adds the first assertions.
- **`secret-dep-gate.test.sh` section D** runs `secret-scan.sh` over `git ls-files`, so the new
  harness joins the scanned corpus. Fixtures must contain **no key-shaped literal**, and no fixture
  path may contain `secret`, `credential`, `.env`, `.pem` or `.key` — `protect-files.sh` denies
  writes to those and a fixture that cannot be created is a test that cannot run.

**Run the full suite after every task, not just the new file.** Four of the modified files are read
by other skills or other harnesses; `.claude/test-cmd` globs the whole `tests/` directory for exactly
this reason.

---

## Tasks

### Task 1 — RED: harness skeleton, registration, caller traps, parser and structural-error assertions

- [ ] Create `staging/plugin/scripts/tests/spec-coverage.test.sh`: `set -u`, bash 3.2, hermetic
      (`mktemp -d` + `trap`), no `$HOME` dependency. Model the preamble on
      `weakening-wiring.test.sh` / `secret-dep-gate.test.sh` lines 1–52: `SCRIPTS`/`STAGING`/`REPO`
      path resolution, `ok`/`bad`, `PASS`/`FAIL` counters, final `PASS=$PASS FAIL=$FAIL` line and
      `[ "$FAIL" -eq 0 ]`.
- [ ] Header comment states: labels are `R`-prefixed so they stay distinguishable from the nine
      bare-`A`–`G` harnesses and from `weakening-wiring`'s `W` in the same CI log; fixtures carry no
      key-shaped literal because `secret-dep-gate.test.sh` section D scans this file as part of the
      corpus; the checker under test is a **checker** (exit-code contract), not a **reporter**
      (stdout contract) like its neighbour at the same gate.
- [ ] Resolve `SCOV="$STAGING/plugin/skills/concept-to-code/scripts/spec-coverage.sh"`.
      - `RA0`: the script exists at that path and is readable. **RED until Task 2.** Every other
        `RA`/`RB`/`RC`/`RD`/`RE` assertion is meaningless without it — the `F0` anchor pattern from
        `secret-dep-gate.test.sh`.
- [ ] **Section RG — registration (RED until Task 9).**
      - `RG1`: `docs-ci.yml`'s `for t in …` loop line contains `spec-coverage`, matched with
        `grep -qE '[[:space:]]spec-coverage[[:space:];]'` against the **extracted loop line only** —
        a match anywhere in the file would be satisfiable by a comment.
      - `RG2`: the `PAIRS` heredoc (extract with the same
        `awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f'` that `pairs-completeness.test.sh` uses) contains
        the exact line
        `plugin/skills/concept-to-code/scripts/spec-coverage.sh|skills/concept-to-code/scripts/spec-coverage.sh`.
        Failure message must say that `pairs-completeness.test.sh` cannot catch this — its
        `check_complete` does not cover `plugin/skills/*/scripts/`.
      - `RG3`: the `PAIRS` block does **not** contain `spec-coverage.test` (the harness does not
        deploy — ADR-0048 §D11). Absence assertion, green on arrival.
- [ ] **Section RT — the two caller traps, EXECUTED (forward guards, green on arrival, never fix
      evidence).** These exist so a future edit cannot re-spring traps this codebase has already paid
      for once each.
      - `RT1`: `n=$(printf 'x\n' | grep -c 'nomatch' || echo 0)` produces **two** lines while
        `|| true` produces the single line `0`. Assert both, with the `0\n0` string named in the
        failure message.
      - `RT2`: `weakening-scan.sh` on empty stdin still prints the non-empty sentinel `CLEAN` and
        exits 0 — the neighbouring gate's contract, asserted here so that a reader of *this* harness
        sees why the two blocks must not share an idiom.
- [ ] **Section RA — ID extraction.** Build fixtures under `$TMP` (SPEC files named
      `fixture-a.spec.md` etc.; no forbidden path substrings).
      - `RA1`: a SPEC with `## Success criteria` containing `- [ ] R-01 — first` and
        `- [ ] R-02 — second`, plus a plan citing both and a tests-root mentioning both →
        exit 0, stdout has `COVERED` lines for `R-01` and `R-02`, stderr has one summary line
        containing `2 id(s) declared`.
      - `RA2`: **the `ADR-NNNN` immunity, as a unit assertion.** A SPEC whose success criteria are
        prose items mentioning `ADR-0047`, `ADR-0016` and `PR-01` declares **zero** IDs → the silent
        path (exit 0, both streams empty). Failure message names the boundary rule.
      - `RA3`: position matters — `- [ ] A SPEC with \`R-01\` and \`R-02\` fails` declares zero IDs
        (mention, not declaration). This is the shape of this feature's own SPEC line 43.
      - `RA4`: `- [x] R-03 — done` is a declaration too (checked box, same as unchecked).
      - `RA5`: heading recognition — the same items under `## Acceptance criteria` and under
        `## Definition of done` are found; under `## Notes` they are not, and that case is `RB4`.
      - `RA6`: section end — an `R-NN` item under a `## Edge cases` heading that follows
        `## Success criteria` is **not** counted.
      - `RA7`: `--list` prints `R-01<TAB>first` and `R-02<TAB>second`, exit 0, with the ` — `
        separator stripped. Also assert `--list` on a no-ID SPEC prints nothing and exits 0.
- [ ] **Section RB — structural errors, exit 3.**
      - `RB1`: duplicate `R-01` twice in one SPEC → exit 3, stdout contains `DUPLICATE` and `R-01`.
      - `RB2`: `MALFORMED` — items starting `R-1 —`, `R-001 —`, `R-1a —` each → exit 3, stdout
        contains `MALFORMED` and the offending token. Run each as its own sub-assertion so a partial
        implementation cannot pass.
      - `RB3`: `ORPHAN` — SPEC declares `R-01`, plan task cites `(R-09)` → exit 3, stdout contains
        `ORPHAN` and `R-09`.
      - `RB4`: the narrow inert-guard — a well-formed `- [ ] R-01 — x` at the start of an item under
        `## Notes` (no recognized section anywhere in the file) → exit 3, and the stderr message
        names at least one recognized heading. Failure message: "a gate that is silently inert is the
        ADR-0043 failure shape".
      - `RB5`: exit **2** on invalid invocation — missing `--spec`, missing `--plan`, unknown flag,
        unreadable `--spec` path. Four sub-assertions; stdout empty on each.
- [ ] **Checkpoint:** run the harness. Expect `RG3`, `RT1`, `RT2` green and everything else RED
      (`RA0`, `RG1`, `RG2`, all of RA, all of RB). Record the exact FAIL count in the task notes;
      Task 2 must drive it back to 3 (`RA0` clears, `RG1`/`RG2` remain). If `RG3`/`RT1`/`RT2` are not
      green, the assumptions this feature rests on are not true — stop and report, do not adjust the
      assertions.

### Task 2 — GREEN: `spec-coverage.sh` part 1 — CLI, parsing, `--list`, structural errors

- [ ] Create `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh`. Header comment in the
      `secret-scan.sh` style: the contract table (exit 0/1/2/3), the sentence **"this is a CHECKER:
      the exit code is the policy channel — unlike `weakening-scan.sh` at the same gate, which is a
      REPORTER that always exits 0"**, the `ADR-NNNN` boundary rationale, and `Bash 3.2 clean: no
      assoc arrays, no mapfile, no process substitution, no <<<`.
- [ ] `set -u`. Argument parsing in the `secret-scan.sh` `while [ $# -gt 0 ]; do case "$1" in` shape:
      `--spec <f>` (required), `--plan <f>` (required), `--tests-root <d>` (optional), `--list`
      (optional), anything else → `usage` + exit 2. Unreadable `--spec`/`--plan` → exit 2. `--list`
      does not require `--plan` to be coverage-checked but still requires it to be readable — keep
      one argument contract, do not branch it.
- [ ] `mktemp -d` + `trap 'rm -rf "$TMPD"' EXIT`.
- [ ] **Success-criteria section extraction** (awk, one pass): start at a line matching
      `^#{2,}[[:space:]]+` followed case-insensitively by `success criteria`, `acceptance criteria`
      or `definition of done`; end at the next line matching `^#{1,2}[[:space:]]`. Emit the section's
      lines. A SPEC may contain more than one recognized section; take all of them.
- [ ] **ID extraction** from the section: a line matching
      `^[[:space:]]*[-*][[:space:]]\[[ xX]\][[:space:]]*` whose remaining text begins with
      `R-[0-9][0-9]` followed by a non-digit or end-of-line. Emit `R-NN<TAB><remaining text>`.
      Use awk with `match()`; do not use `\b` (not portable in BSD ERE).
- [ ] **MALFORMED**: within the same section, an item whose remaining text begins with `[Rr]-[0-9]`
      but does not match the two-digit form → `MALFORMED<TAB><token>`, exit 3.
- [ ] **The narrow inert-guard**: if the recognized sections yield zero IDs **and** some checklist
      item elsewhere in the file begins with a well-formed `R-NN`, print `MALFORMED<TAB>R-NN` plus a
      stderr line naming the three recognized headings, exit 3. Do **not** widen this to "any `R-NN`
      anywhere in the file" — that fires on prose and on this feature's own SPEC (`RA3`).
- [ ] **DUPLICATE**: same ID declared twice → `DUPLICATE<TAB>R-NN`, exit 3.
- [ ] **`--list`**: print `R-NN<TAB><text>` for each ID and exit 0 (after DUPLICATE/MALFORMED
      checks). Separator stripping: trim leading whitespace, then strip **one** leading separator —
      the em dash `—` and en dash `–` by literal `substr`/`index` comparison (3-byte UTF-8, never a
      regex bracket class: that is not portable across BSD and GNU awk), or one of `- : . )` by
      single-character comparison — then trim whitespace again.
- [ ] **ORPHAN**: extract `R-NN` tokens from the plan's task lines (Task 4 defines "task line"); any
      token not in the declared set → `ORPHAN<TAB>R-NN`, exit 3. Implement the extraction here so
      `RB3` can go green; the coverage direction is Task 4.
- [ ] Every `grep -c` goes through a `count_re()` helper copied in shape from `secret-scan.sh:103`.
- [ ] **Checkpoint:** harness back to **exactly 2 FAILs** for the sections that exist so far
      (`RG1`, `RG2`); `RA0`, all of RA and all of RB green. Run the full suite.

### Task 3 — RED: coverage, discovery and backward-compatibility assertions (RC, RD, RE)

- [ ] **Section RC — plan coverage.**
      - `RC1`: **the SPEC's headline criterion.** SPEC declares `R-01`,`R-02`; plan cites only
        `R-01`; tests mention both → exit **1**, stdout contains `UNCOVERED` and `R-02` and does not
        contain `UNCOVERED<TAB>R-01`. Assert the ID is *named* in the output.
      - `RC2`: the missing half is named — the `R-02` line's third field is `plan`.
      - `RC3`: a task **heading** citation counts: `### Task 3 — GREEN: thing (R-02, R-05)`.
      - `RC4`: a **checkbox** citation counts: `- [ ] implement the thing (R-02)`.
      - `RC5`: a citation in the plan **preamble** (a plain prose line, not a task line and not a
        checkbox) does **not** count → still `UNCOVERED … plan`. This is the assertion that makes
        §D3's definition real rather than decorative.
      - `RC6`: both halves missing → third field is exactly `plan,tests`.
- [ ] **Section RD — test discovery.**
      - `RD1`: a mention in `tests/foo.test.sh` counts; the same mention in `tests/notes.txt` does
        not.
      - `RD2`: discovery reaches a nested path (`a/b/c/x_test.py`) under `--tests-root`.
      - `RD3`: **`.md` is never a test file.** A tests-root containing `docs/specs/x.spec.md` that
        mentions `R-01` → `R-01` is still `UNCOVERED … tests`. Failure message: "the SPEC would
        discover itself as a test file and every SPEC would be trivially self-covered".
      - `RD4`: `--tests-root` **omitted** → the test half is not evaluated; a SPEC+plan pair that
        covers everything in the plan and has no tests anywhere exits 0, and stderr says
        `tests=not-checked`.
      - `RD5`: `--tests-root` given at a directory with **zero** discovered test files → exit 1 with
        every ID `UNCOVERED … tests`, and the stderr summary names the discovery count so the cause
        is legible.
- [ ] **Section RE — backward compatibility (the hard gate).**
      - `RE1`: synthetic — a SPEC with a `## Success criteria` section whose items carry no IDs →
        exit 0, stdout **empty**, stderr **empty**. Assert all three, separately, with distinct
        failure messages.
      - `RE2`: a SPEC with **no** success-criteria section at all → same silent pass.
      - `RE3`: **the real corpus.** Loop over every `$REPO/docs/specs/*.spec.md` **and**
        `$REPO/SPEC.md`, running the checker with a throwaway empty plan and no `--tests-root`.
        Require exit 0, empty stdout and empty stderr for each. On failure, name the offending file
        and the first line of its output. One `ok` per file, so the CI log shows the corpus size.
      - `RE4`: guard against a vacuous `RE3` — assert the corpus loop actually visited **at least
        30** files. A glob matching nothing reports nothing, and a silent zero-file result reads
        exactly like full coverage (the `pairs-completeness.test.sh` self-test-2 lesson).
- [ ] **Checkpoint:** run the harness. Record the FAIL count. Task 4 must drive it back to 2
      (`RG1`, `RG2`).

### Task 4 — GREEN: `spec-coverage.sh` part 2 — coverage matching, exit codes, the silent path

- [ ] **The silent no-IDs path, first and explicitly:** zero declared IDs (and no MALFORMED, no
      inert-guard hit) → produce **no output on either stream** and `exit 0`. Put the
      `ADR-0048 §D7 / §D8` reference in a comment beside it and the words "this divergence from
      `secret-scan.sh`'s always-summarize convention is deliberate".
- [ ] **Task-line definition** (used for both plan coverage and ORPHAN): a line matching
      `^[[:space:]]*[-*][[:space:]]\[[ xX]\]` **or** `^#{2,4}[[:space:]].*Task`. Nothing else.
- [ ] **Plan coverage:** for each declared ID, search the plan's task lines for the boundary-anchored
      token. Boundary regex exactly as in Task 2.
- [ ] **Test discovery:** enumerate files under `--tests-root` with `find`, excluding any path
      component `.git`, and keep a file only if its **basename** matches one of: `*.test.*`,
      `test_*`, `*_test.*`, `*Test.*`, `*Tests.*`, `test-*.sh`, `run-tests.sh`, `*.spec.js`,
      `*.spec.ts`, `*.spec.tsx`, `*.spec.jsx`. Then **reject any basename ending in `.md`**, as a
      separate explicit step with its own comment, so the rule is visible rather than implied by the
      pattern list. Grep the surviving files for the boundary-anchored token.
- [ ] **Output and exit:** `COVERED<TAB>R-NN` for each covered ID; `UNCOVERED<TAB>R-NN<TAB><halves>`
      where `<halves>` is `plan`, `tests` or `plan,tests`. Any `UNCOVERED` → exit 1, else exit 0.
- [ ] **stderr summary**, one line, on every run except the silent path:
      `spec-coverage: <n> id(s) declared, <c> covered, <u> uncovered, tests-root=<dir|not-checked>`
      — and when a `--tests-root` was given, append the discovered-file count (`RD5` reads it).
- [ ] Re-verify Bash 3.2 and BSD portability:
      `grep -nE 'declare -A|mapfile|\^\^|<\(|<<<' spec-coverage.sh` must find nothing.
- [ ] **Checkpoint:** harness at **exactly 2 FAILs** (`RG1`, `RG2`). Full suite green otherwise.

### Task 5 — RED: assertions for the c2c Step 5 gate (sections RF, RH)

- [ ] Add **section RF**, reading `CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"`. Extract
      Step 5 once with `awk '/^### Step 5 —/{f=1} /^### Step 6 —/{f=0} f' "$CC" > "$TMP/c2c_step5.txt"`
      and add `RF0` asserting the extract is non-empty.
      - `RF1`: the heading `#### Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)` occurs
        **exactly once** in the whole file (`grep -c` with `|| true`, compare to `1`) — the
        `check_unique_ref` shape from `workflow-dispatch-pins.test.sh`.
      - `RF2`: the block resolves the script under
        `skills/concept-to-code/scripts/spec-coverage.sh` **and** mentions `CLAUDE_PLUGIN_ROOT`.
      - `RF3`: **absence** — the block does **not** contain the string `hooks/spec-coverage.sh`.
        The `~/.claude` two-location trap, asserted in the direction that catches a block copied
        from #100.
      - `RF4`: the exit-code idiom is present — the extract contains `_rc=$?` (or the chosen
        variable) within the gate block, and the literal warning phrase
        `Do not copy one block's branching into the other`.
      - `RF5`: the block names both neighbours' contracts — it contains `weakening-scan.sh` and a
        phrase distinguishing checker from reporter.
      - `RF6`: attended policy — `do NOT transition to` and `step_6_review` inside the gate block.
      - `RF7`: unattended policy — the block mentions `autopilot` and `halt`.
      - `RF8`: fail-open — the block contains `unavailable` and the `_scov=""` else-branch.
      - `RF9`: **cadence** — the block states it runs once at the boundary and **not** per batch;
        assert on the literal phrase chosen in Task 6 (e.g. `once at the Step 5 exit, not at every
        batch checkpoint`). This is the assertion that stops someone "fixing" the asymmetry with
        ADR-0047's gate.
      - `RF10`: both dispatch paths reach it — count occurrences of the literal
        `Requirement-ID coverage gate` inside the Step 5 extract and require `>= 3` (heading,
        Workflow-path pointer, fallback-path pointer). Failure message names the count found.
      - `RF11`: `--tests-root` conditioning — the block mentions `test_cmd_placeholder` and
        `test_cmd_provisional`.
- [ ] Add **section RH** (report schema + read contract), same `$CC`:
      - `RH1`: the documented JSON schema block contains `"requirement_coverage"`.
      - `RH2`: it shows `ids_declared`, `uncovered` and `status` within that object.
      - `RH3`: the read contract states `uncovered` non-empty is a `failure signal`.
      - `RH4`: the read contract states the additive rule — a report without the key is **not**
        malformed.
      - `RH5`: **forward guard, never fix evidence** — the schema block still contains
        `weakening_findings` and `checkpoint_reviews`, and the read contract still contains
        `never a failure signal`. #101's WD assertions read this same block; appending is safe,
        reflowing is not.
      - `RH6`: the Step 2 architect dispatch prompt tells the architect to cite requirement IDs —
        extract Step 2 with `awk '/^### Step 2 —/{f=1} /^### Step 3 —/{f=0} f'` and assert it
        mentions `R-NN` (or the chosen literal) and `cite`.
- [ ] **Checkpoint:** run the harness. Expect 2 + 12 + 6 = **20 FAILs**. Record the exact number.

### Task 6 — GREEN: `concept-to-code/SKILL.md` Step 5 gate block

- [ ] Insert `#### Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)` **after** the
      `#### Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)` block and **before**
      `#### Fallback — Agent-tool batch dispatch (…)`. **Rename no existing heading.**
- [ ] Block contents, in this order:
      1. The two-step resolution block (`CLAUDE_PLUGIN_ROOT` → `$HOME`), path shape
         `skills/concept-to-code/scripts/spec-coverage.sh`, with the `_scov=""` else-branch comment
         "gate did not run — report it, do not infer a clean result".
      2. The input selection: `--spec <manifest.artifacts.spec>`, `--plan <manifest.artifacts.plan>`,
         `--tests-root <project_root>` — **omitted** when `manifest.test_cmd_placeholder = true` or
         `manifest.test_cmd_provisional = true`, with the one-line reason.
      3. The invocation capturing both output and exit code, and a `case "$_rc"` over `0|1|3|2`.
      4. **The idiom warning**, as its own paragraph, containing the literal sentence *"Do not copy
         one block's branching into the other."* and the checker/reporter distinction (`RF4`,`RF5`).
      5. **The cadence sentence** (`RF9`): once at the Step 5 exit, not at every batch checkpoint,
         because mid-run an uncovered ID is the expected state.
      6. Policy: attended → present the uncovered IDs, do **NOT** transition to `step_6_review`
         without acknowledgment. Autopilot → **halt**, do not transition, do not proceed to Gate 5.
         Exit 3 → same blocking treatment, different remedy (fix the artifact, not the coverage).
         Exit 2 or unresolved script → fail-open, record `"status": "unavailable"`.
- [ ] Wire **both** paths so the literal `Requirement-ID coverage gate` appears at least three times
      in Step 5:
      - Workflow path: a new numbered item after the existing item 4 (the ADR-0047 gate), before the
        transition decision.
      - Fallback path: in the **final** step (item 4 of the batch-dispatch policy, beside the closing
        `verify.sh`/`git status`), explicitly **not** in item 2's per-batch checkpoint.
- [ ] **Append** to the `step5-report.json` schema block (do not reflow it):
      ```json
      "requirement_coverage": {
        "ids_declared": 6,
        "uncovered": [ { "id": "R-02", "missing": "plan" } ],
        "status": "pass | fail | no-ids | unavailable"
      }
      ```
- [ ] Add two bullets to the orchestrator read contract, immediately after the
      `weakening_findings` bullets: `requirement_coverage.uncovered` non-empty → **failure signal**;
      absent means the gate did not write one and is **not** malformed.
- [ ] Step 2 architect dispatch: add one line to the `Produce:` constraints —
      "Every plan task cites the SPEC requirement IDs (`R-NN`) it satisfies; every declared ID is
      cited by at least one task; never cite an ID the SPEC does not declare."
- [ ] **Checkpoint:** full suite. Harness back to **exactly 2 FAILs** (`RG1`, `RG2`).
      `workflow-dispatch-pins.test.sh`, `weakening-wiring.test.sh`, `step5-checkpoint-review.test.sh`
      and `secret-dep-gate.test.sh` all still green.

### Task 7 — RED: assertions for the two generators and the architect (section RI)

- [ ] Add **section RI**:
      - `RI1`: `interview-driver/SKILL.md` body mentions `R-01` and requires enumerated
        success-criteria items (assert the literal ID form and a word like `success criteria`).
      - `RI2`: **forward guard** — `interview-driver/SKILL.md` frontmatter still carries
        `disable-model-invocation: true` and still parses. Duplicates
        `skill-text-corrections.test.sh` E/F3 on purpose: this feature edits that file and the
        cheapest way to break the /loop safety design is a careless rewrite.
      - `RI3`: `spec-from-issue/SKILL.md`'s `## Success criteria` template line requires
        `R-NN`-prefixed items starting at `R-01`.
      - `RI4`: `spec-from-issue/SKILL.md` carries the no-fabrication guardrail for IDs — a line
        containing `id` and a phrase forbidding inventing criteria. Failure message: "the instruction
        'give every criterion an ID' is satisfiable by producing more criteria".
      - `RI5`: `agents/architect.md` Output Format requires each plan task to cite its requirement
        IDs — assert `R-NN` (or the chosen literal) plus `cite` within the body, and assert the
        example form `(R-02, R-05)` is present.
      - `RI6`: **forward guard** — `architect.md` line 4 still carries the five read-only git entries
        and no `Bash(git *)`; the Command-scope and Write-scope bullets are still present. Duplicates
        `agent-tool-scoping.test.sh` A1/A12/A14 because this feature edits that file.
- [ ] **Checkpoint:** 2 + 6 = **8 FAILs**, minus the two forward guards, so **6 FAILs** expected
      (`RG1`, `RG2`, `RI1`, `RI3`, `RI4`, `RI5`). If `RI2` or `RI6` is red, the file is not in the
      state this feature assumes — stop and report.

### Task 8 — GREEN: `interview-driver`, `spec-from-issue`, `architect.md`

- [ ] `staging/plugin/skills/interview-driver/SKILL.md`: extend line 13's sentence (or add one
      sentence after it) requiring the success-criteria items to be enumerated `R-01`, `R-02`, … with
      the ID at the **start** of each checklist item. Keep the file's brevity — one sentence, no new
      section. **Do not touch the frontmatter.**
- [ ] `staging/plugin/skills/spec-from-issue/SKILL.md`: change the template's `## Success criteria`
      placeholder to require each checklist item to be prefixed with a unique `R-NN` id starting at
      `R-01`, and add one bullet to `## 3. Guardrails`: **IDs are assigned to criteria the issue
      already states; an ID is never a reason to invent a criterion.**
- [ ] `staging/plugin/agents/architect.md`: extend the **Implementation plan** bullet in Output
      Format — each task cites the requirement IDs it satisfies, form `### Task 3 — … (R-02, R-05)`
      or on a checkbox item; every SPEC-declared ID cited by at least one task; never cite an ID the
      SPEC does not declare. **Do not touch line 4, the Command-scope bullet, or the Write-scope
      bullet.**
- [ ] **Checkpoint:** full suite, with attention to `agent-tool-scoping.test.sh` (all sections) and
      `skill-text-corrections.test.sh` (E, F3). Harness back to **exactly 2 FAILs**.

### Task 9 — GREEN: registration in both registries and `PAIRS`

- [ ] `staging/sync-to-claude.sh`: add
      `plugin/skills/concept-to-code/scripts/spec-coverage.sh|skills/concept-to-code/scripts/spec-coverage.sh`
      to the `PAIRS` heredoc, in the existing alphabetical position among the other
      `concept-to-code/scripts/` entries (after `manifest-validate.sh`). Additive only — remove
      nothing.
- [ ] `.github/workflows/docs-ci.yml`: append `spec-coverage` to the `for t in …` list in the
      `shell-tests` job (last entry today is `weakening-wiring`). `ci.yml` needs nothing — it globs.
- [ ] **Checkpoint:** the harness reports **FAIL=0**. First fully green run.

### Task 10 — Verification sweep and docs

- [ ] Run the full suite from a clean shell. Every harness green, with explicit attention to:
      `secret-dep-gate` (section D scans the new harness as corpus — a key-shaped literal in a
      fixture turns it red), `weakening-wiring` (section WD reads the same schema block),
      `step5-checkpoint-review` (section D), `workflow-dispatch-pins` (B4a/B4b/B5),
      `agent-tool-scoping`, `skill-text-corrections`, `pairs-completeness`.
- [ ] `git status --short` shows **no** change under `staging/plugin/skills/autopilot-build/`,
      `nightly-autopilot/`, `project-conductor/`, `commit/`, `review-triage-fix/`, or
      `concept-to-code/scripts/manifest-*.sh`. If any appears, revert it — ADR-0048 §D9/§D10.
- [ ] Confirm no forbidden construct in either new file:
      `grep -nE 'declare -A|mapfile|\^\^|<\(|<<<' staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh staging/plugin/scripts/tests/spec-coverage.test.sh`
      returns nothing.
- [ ] Confirm no fixture path in the harness contains `secret`, `credential`, `.env`, `.pem` or
      `.key` (`protect-files.sh` would deny the write and the test would not run).
- [ ] Run `bash staging/sync-to-claude.sh` **without** `--apply` (dry run) and confirm the new
      `PAIRS` entry resolves and that no unexpected manual-step notice appears.
      **Do not run `--apply`** — deployment is a human decision at the HITL gate.
- [ ] `CLAUDE.md`: add `## Decisions from the requirement-ID coverage chain (ADR-0048)` after the
      ADR-0047 block, in the established shape (4–6 bullets: the `ADR-NNNN` collision and the
      two-sided boundary rule, the silent-on-no-IDs backward-compatibility contract asserted against
      the real 34-spec corpus, blocking-and-why-it-differs-from-#101's-heuristic, the two adjacent
      gates with opposite caller idioms, `.md` is never a test file and why,
      instruction-not-enforcement).
- [ ] `docs/vibe-coding-system.md`: new changelog entry
      `### Addition 2026-07-26 (issue #102, requirement IDs and the SPEC→plan→test coverage check,
      ADR-0048)` inserted **immediately after** the `### Addition 2026-07-26 (issue #101 …)` block
      (line ~1272) and before `### Update 2026-06-23 (workflow model pinning)`.
- [ ] `docs/GUIDA-USO-IT.md:282`: the Italian circuit-breaker sentence lists `test_result=RED`, task
      falliti, report mancante, and (since #101) test weakening — add the requirement-coverage
      condition. Italian, one clause, matching the surrounding register.
- [ ] **Checkpoint:** full suite green; markdown links in the new/edited docs resolve (docs-ci runs
      lychee over `**/*.md` and internal links are blocking).

---

## Definition of done

- [ ] `spec-coverage.test.sh` is green and registered in **both** registries.
- [ ] The full suite is green, including every harness this feature did not write.
- [ ] All 34 existing specs plus `SPEC.md` pass **silently** (exit 0, empty stdout, empty stderr),
      asserted against the real corpus by `RE3`, with `RE4` proving the loop was not vacuous.
- [ ] `spec-coverage.sh` has a `PAIRS` entry, asserted by `RG2` — nothing else in CI can catch its
      absence.
- [ ] The six SPEC success criteria that can be evidenced statically are each pinned by a named
      assertion, and the report says which assertion covers which criterion.
- [ ] No manifest field, no new invariant, no schema version bump, no `settings.json` wiring, no
      hook, no manual sync step.
- [ ] `autopilot-build`, `nightly-autopilot`, `project-conductor`, `commit` and `review-triage-fix`
      are byte-identical to their state at branch point.
