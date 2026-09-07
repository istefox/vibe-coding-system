# Implementation plan — extend the Codex-vs-Claude review gate to deep-refactor's audit dispatch

- **SPEC:** `/Users/stefer/emdash/worktrees/vibe-coding-system-19f4e0e7/emdash-few-bags-taste-p9p5l/SPEC.md`
  (R-01 … R-14, all fourteen declared, all fourteen cited below)
- **ADR:** `docs/architecture/ADR-0193-codex-review-gate-deep-refactor.md`
- **ARCH:** n/a — a scoped extension of an already-documented architecture
  (ADR-0018 → ADR-0187 → this).
- **Stack:** Bash 3.2 (macOS `/bin/bash`) plus `python3` for every JSON step, POSIX
  `awk`/`sed`/`grep`. No `mapfile`, no bash associative arrays, no `${var^^}`, no `<<<`, no process
  substitution. `set -u` only (the project convention; `~/.claude/rules/shell.md`'s global
  `set -euo pipefail` is deliberately NOT followed here — flag it, do not "fix" it). Plus Markdown
  skill prose and one line of GitHub Actions YAML.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`

TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: sonnet

---

## Read this first — state measured 2026-09-05 at `7dffb11` (rule 13)

**Re-derive every number here before acting on it.** Counts in the SPEC, in ADR-0187 and in this
block are snapshots of the moment they were taken.

```text
staging/plugin/scripts/codex-reviewer.sh                       365 lines
  `<<'SCHEMA_EOF'` blocks in it                                  2  (review, diagnose)
  `PROMPT_EOF` heredoc delimiters in it                          4  (2 openers + 2 terminators)
  SCRIPT_DIR computed at the top                               yes, and currently UNUSED
staging/plugin/skills/deep-refactor/SKILL.md                   650 lines
  ```sh fences                                                   6
  ```bash fences                                                 0
assertion prefix CX free across staging/ + docs/ + .github/    yes (0 occurrences)
`USE_CODEX_AUDIT` anywhere in staging/                           0
`Gate 0-CDX` in staging/                                         0 (3 in docs/, all in ADR-0193)
manifest-field-state.sh exists                                 yes
.claude/test-cmd content                                       NONE  (so deep-refactor's own
                                                               Phase 0.5 would go report-only in
                                                               THIS repo — irrelevant to the work,
                                                               but do not be surprised by it)
```

Harnesses that actually open `deep-refactor/SKILL.md` today — **exactly two**, and both must stay
green untouched:

- `workflow-dispatch-pins.test.sh` — `A2` greps the literal `model: "opus", effort: "high"`, `A3`
  greps the literal `inherit the session`, `A1` asserts the string `in every Agent-tool dispatch`
  is **absent**. All three live in the text this plan wraps.
- `dispatch-completion.test.sh` — `DC21` freezes the `dispatch-site:` declaration set byte-exactly
  (13 names, `deep-refactor-reviewers` and `deep-refactor-fix-agents` among them). **Do not add a
  `dispatch-site:` marker anywhere in this feature** (ADR-0193 §A10). If a task seems to need one,
  stop and report.

The skill-local `staging/plugin/skills/deep-refactor/tests/run-tests.sh` also greps
`Mandatory guard 1` / `Mandatory guard 2` and the `| \`perf\` | reviewer |` table rows. It is
outside `.claude/test-cmd`'s glob and outside CI's named list by design, so **run it by hand**
(`bash staging/plugin/skills/deep-refactor/tests/run-tests.sh`) before declaring Tasks 6–8 done —
nothing else will.

## Read this second — the observable contracts that move, and every call-site found

Greps were run. The call-sites are listed here, not left for the coder to find.

**1. `codex-reviewer.sh`'s `--mode` value set: `review|diagnose` → `review|diagnose|audit`.**
Call-sites of the script, found with
`grep -rn "codex-reviewer.sh" staging/ .github/ docs/ --include='*.md' --include='*.sh' --include='*.yml'`:

- `staging/plugin/skills/review-triage-fix/SKILL.md` — Sites 1, 2, 3 (`review` / `diagnose`).
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` — Sites 4, 5 (`review`).
- `staging/sync-to-claude.sh` — the `PAIRS` line `plugin/scripts/codex-reviewer.sh|hooks/codex-reviewer.sh`.
- `staging/plugin/scripts/tests/codex-reviewer-schema.test.sh` — the schema extractor.

**None of the five dispatch sites needs an edit.** The change is purely additive: both existing
modes keep their argument validation, their prompts, their schemas and their output shapes
byte-for-byte. Task 1's `CX07` pins that in both directions. Do not "tidy" the review/diagnose
branches while adding the third.

**2. `codex-reviewer-schema.test.sh`'s extraction contract: ordinal → all-blocks.** This is the
staleness this plan exists to catch before it happens. The file today does:

```text
extract_schema 1  ->  review-mode schema      (label: "S1 review-mode schema")
extract_schema 2  ->  diagnose-mode schema    (label: "S2 diagnose-mode schema")
```

Adding a third `SCHEMA_EOF` block **before** the diagnose block silently repoints `S2` at the audit
schema while its label still says "diagnose", and the diagnose schema stops being checked at all.
Nothing goes red. Task 5 replaces the ordinal extractor with an all-blocks enumeration plus an
**exact** block-count assertion (not a `>= 2` floor — a floor absorbs its own plant, ADR-0124).
That harness has exactly one consumer, CI's named list, and no other file reads its ids.

**3. `deep-refactor/SKILL.md`'s two dispatch branches gain an IF/ELSE.** Consumers that assert on
this text: `workflow-dispatch-pins.test.sh` `A1`/`A2`/`A3` and `dispatch-completion.test.sh`
`DC21`/`DC24`, both listed above, plus the skill-local `run-tests.sh`. All must stay green with
zero edits to them.

**Run the FULL suite after every batch, not just the new harness.** Three of the files this plan
touches are read by harnesses that never mention this feature by name.

## Read this third — two states that are NOT defects and must not be "fixed"

**(a) `spec-coverage.sh` is uninformative for this feature in both directions.** R-01, R-02, R-05,
R-11 and friends are matched by dozens of foreign test files whose own `R-NN` namespaces restart
per feature — measured today: `R-01` appears in 82 files under
`staging/plugin/scripts/tests/`, `R-05` in 18, `R-11` in 10, `R-14` in 3. Rule 18 exactly. Read the
tool's verdict as a hint, never as this feature's gate. The real evidence is the plant registry
(every `CX` assertion seen RED under `plant-check.sh`) and the requirement ids cited in the new
assertions' own comment headers.

**(b) There is no `docs/specs/` pointer for this topic yet**, so writing this plan file does **not**
resolve a new (spec, plan) pair and the frozen scope baseline should not move. If the baseline
harness (the one carrying `RS0`–`RS10`) does go red after this plan lands, its owner is Step 7.0b's
`c2c-step7-baseline-bump` fence — never hand-edit the `.tsv`, never weaken `RS7`, and do not add a
task for it.

## Read this fourth — the design in one paragraph, so no task re-derives it

`codex-reviewer.sh` grows a third mode. `--mode audit` requires `--dimension` from a closed
four-value set (exit 2 otherwise), accepts `--diff-scope` **optionally** with exactly the three
values `review` mode already validates (exit 2 on any other), and requires `--out`. The availability
cascade is reused unchanged and gains one step: `$SCRIPT_DIR/../skills/deep-refactor/scripts/enumerate-sources.sh`
must exist and be runnable, else exit 3 with that reason named — the file list is derived from that
helper, never re-listed (ADR-0193 §D3). The prompt embeds the file *paths* (Codex reads contents
itself under `--sandbox read-only`) plus, for `dead-code` and `perf` only, the corresponding
Mandatory guard string copied verbatim from `SKILL.md`. The `--output-schema` block carries
`"additionalProperties": false` on every object and all nine `FINDINGS_SCHEMA` fields. A `python3`
post-process writes `--out` as a JSON array, forcing `dimension` to the argument, synthesising `id`,
and forcing `fix_type: report-only` on every finding when and only when the dimension is `security`.
On the skill side a run-local `USE_CODEX_AUDIT` is resolved once before Phase 1 — inherited from
`manifest.use_codex_review` under autopilot-with-manifest, `false` under autopilot-without-manifest,
otherwise asked at a new Gate 0-CDX defaulting to No — and both dispatch branches wrap their
existing text in `IF USE_CODEX_AUDIT … ELSE <today's text, byte-identical> ENDIF`, with a
per-dimension exit-3 fallback to the Claude `reviewer` call for that dimension only. Gate 1 gains a
per-dimension engine line, rendered only when the flag was on.

## Files this plan touches

| File | Task | What |
| --- | --- | --- |
| `staging/plugin/scripts/tests/codex-audit-mode.test.sh` | 1, 9 | new harness, section `CX`, `Z1` |
| `staging/plugin/scripts/codex-reviewer.sh` | 2, 3, 4 | args + cascade, schema + prompt, post-process |
| `staging/plugin/scripts/tests/codex-reviewer-schema.test.sh` | 5 | ordinal to all-blocks, count guard |
| `staging/plugin/skills/deep-refactor/SKILL.md` | 6, 7, 8 | Gate 0-CDX, both branches, Gate 1 |
| `.github/workflows/docs-ci.yml` | 9 | one name appended to the harness list |
| `docs/chain-decision-index.md` | 10 | one ADR-0193 entry |

Nothing else. No `PAIRS` entry is needed (`codex-reviewer.sh` already has one; the deployment-pair
check covers only `plugin/agents/*.md`, `user/rules/*.md` and `plugin/skills/*/SKILL.md`). No
manifest schema change, no new manifest field, no `FINDINGS_SCHEMA` change, no `dispatch-site:`
marker. If a task seems to need any of those, stop and report — that is scope drift.

## Assertion ids and the harness contract

Section `CX`, ids `CX01`–`CX27`, two digits from the start (`plant-check.sh` decides "fired" with a
**prefix** match on `^FAIL: <id>`, so `CX1` beside `CX10` would be ambiguous). Prefix `CX` verified
free across `staging/`, `docs/` and `.github/` on 2026-09-05.

**ADR-0154 back-reference, mandatory.** The new harness's header block must carry, verbatim, both
literals `ADR-0193` and
`docs/superpowers/plans/2026-09-05-codex-review-gate-deep-refactor.md`. Without one of them
`spec-coverage.sh` descopes the file and this feature's ids report `UNSCOPED`.

**Plant declarations.** Fifteen assertions carry a `# plant:` line at **column 1**, beside the
assertion, in the form `# plant: <id> | <staging-relative-path> | <needle> | <replacement>` (three
fields = delete). Constraints that bite here:

- A needle may not contain the sequence ` | ` (space-pipe-space). The dimension `case` arm
  `dead-code|perf|structure|security)` has no spaces around its pipes and is safe.
- Exactly one match is required. Zero is `BADPLANT`, not a pass; more than one is a plant hitting
  sites it did not intend.
- Needles must belong to the mechanism and to nothing else (rule 1). Never plant on the bare word
  `audit`, `dimension` or `Codex` — each appears in prose in four or more files by the end of this
  plan. Plant on the `case` arm, the forcing assignment, the guard's own distinctive clause.
- `CX26`'s target is the docs copy, reached with the literal `../docs/` prefix the sandbox allows:
  `../docs/architecture/ADR-0187-codex-review-gate.md`.
- `.github/workflows/docs-ci.yml` is **outside** the plant sandbox (it copies only `staging/` and
  `docs/`), so Task 9's wiring is verified by running the real backward check, not by a plant.

**Assertion-to-requirement map.** Every `CX` id names its SPEC ids in its own comment header — that
is what a later reader greps, and what keeps the citation honest when today's foreign matches are
removed. With one hard exception:

> **Never write the literal tokens `R-12`, `R-13` or `R-14` into `codex-audit-mode.test.sh`, or
> into any other test file.** All three carry `(no-test: …)` in the SPEC, and `spec-coverage.sh`
> treats a `(no-test:)` id that IS mentioned inside a test file the plan scopes in as a
> **`STALE-WAIVER`, exit 3** — a hard block on Step 5→6, whose documented remedy is a SPEC edit at
> a gate, not a harness edit. Verified against the tool's own D4 branch on 2026-09-05. Their
> coverage evidence is the **plan-side** citation in the task headings below (Tasks 1, 9 and 10),
> which is exactly what ADR-0138 intends: the marker exempts the test axis, never the plan axis.
> So the assertions listed with those ids below carry them **here, in the plan, only** — in the
> harness they get a plain prose label and no `R-NN` token.

Assertions affected: `CX02`, `CX14`, `CX15`, `CX17` (plan-side R-12/R-13) and `CX26`, `CX27`
(plan-side R-14). Every other `CX` id writes its `R-NN` citations into the file as normal.

## Batching

| Batch | Tasks | Expected state at the checkpoint |
| --- | --- | --- |
| A | 1 | every `CX` assertion RED except `CX07`, `CX25`, `CX26`, `CX27` (which pin pre-existing state and are GREEN from the start) |
| B | 2 | `CX01`–`CX09` GREEN |
| C | 3 | `CX10`, `CX14`–`CX17` GREEN |
| D | 4 | `CX11`–`CX13`, `CX18`, `CX19` GREEN |
| E | 5 | `codex-reviewer-schema.test.sh` green on three blocks |
| F | 6, 7, 8 | `CX20`–`CX24` GREEN; `workflow-dispatch-pins` and `dispatch-completion` still green |
| G | 9, 10 | full suite green, all fifteen plants fire, CI list backward check green |

Task 1 must not share a batch with any of Tasks 2–8 (an assertion must not land beside the code it
is meant to fail against).

---

## Task 1 — TEST: new harness `codex-audit-mode.test.sh`, section `CX`, every assertion RED (R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-08, R-09, R-10, R-11, R-12, R-13)

Owner: **tester**. Create `staging/plugin/scripts/tests/codex-audit-mode.test.sh` only. Offline,
hermetic, no network, no `$HOME` dependency, **never a live `codex` call** (this repo's standing
rule: CI never spends real Codex quota). Bash 3.2 clean, `set -u`, `ok()`/`bad()`/`PASS`/`FAIL`
in the shape every sibling harness uses, `[ "$FAIL" -eq 0 ]` as the last line.

Header block states: the two ADR-0154 literals, that the section covers SPEC R-01–R-13, that prefix
`CX` was verified free on 2026-09-05, and that `CX01`–`CX24` are RED by construction until Tasks
2–8 (a red assertion at the Batch A checkpoint is the deliverable, not a defect).

**Stub `codex` harness.** Several assertions need `codex` present and cooperative. Build a stub on
an isolated `PATH` in a `mktemp -d`: a `codex` script whose `doctor --json` prints
`{"checks":{"auth.credentials":{"status":"ok"}}}` and whose `exec` writes a canned JSON payload to
the path given after `-o`, **and tees the prompt it received to a file** so `CX17` can inspect what
was actually built. The absent-`codex` assertions use a `PATH` with no `codex` at all.

- [ ] `CX01` (R-01) — `--mode audit --dimension dead-code --out $T` with no `codex` on `PATH` exits
      **3**, not 2. This is the assertion that distinguishes "the mode is recognised" from "bad
      invocation", and it is the one that fails today for the right reason.
- [ ] `CX02` (R-01; R-12 plan-side only) — `--dimension notadimension` exits **2** and its stderr
      names all four valid values. Plant: neutralise the `--dimension` `case` guard. Write only
      `R-01` into the file's comment header.
- [ ] `CX03` (R-01) — `--mode audit` with `--dimension` omitted exits **2**.
- [ ] `CX04` (R-01) — `--mode audit --dimension perf` with `--out` omitted exits **2** (the shared
      requirement is not bypassed by the new branch).
- [ ] `CX05` (R-01) — `--diff-scope sometimes` in audit mode exits **2**. Plant: neutralise the
      audit-side `--diff-scope` validation.
- [ ] `CX06` (R-01) — all three locked `--diff-scope` values (`uncommitted`, `base:HEAD`,
      `commit:HEAD`) are accepted in audit mode: none exits 2. Loop over exactly three values and
      **assert the loop ran three times** before believing the result (rule 7 — a collapsed
      denominator and a clean result look identical).
- [ ] `CX07` (R-01, R-11) — **the two existing modes are unchanged, both directions.**
      `--mode review --diff-scope bogus` exits 2; `--mode diagnose` with no `--finding` exits 2;
      `--mode notamode` exits 2 and its message still names `review` and `diagnose`. GREEN from
      Batch A — it pins pre-existing behaviour, and a red here at any later checkpoint means a task
      broke a shipped contract.
- [ ] `CX08` (R-01) — with `codex` stubbed present but the enumerate helper made unreachable (run
      against a `cp -R` of `staging/` with that one file moved aside), audit mode exits **3** and
      its stderr names the helper. Never a silent fall-back onto a duplicated exclusion list.
- [ ] `CX09` (R-01) — the relative path `../skills/deep-refactor/scripts/enumerate-sources.sh`,
      resolved from `codex-reviewer.sh`'s own directory exactly as the script resolves it, exists in
      the staging tree. Assert the string form too, so the deployed-tree resolution
      (`~/.claude/hooks/` + `../skills/…`) is pinned by the same literal.
- [ ] `CX10` (R-02) — the audit `--output-schema` block parses as JSON and its `findings` item
      `required` array is a **superset** of the field set extracted from `deep-refactor/SKILL.md`'s
      own finding-schema fence. Count guard: fewer than seven extracted field names is a hard FAIL,
      never a skip. Plant: delete one field from the schema's `required`.
- [ ] `CX11` (R-02) — end to end against the stub: `--out` holds valid JSON, a top-level array, and
      **every** element carries all nine fields (`id`, `dimension`, `severity`, `risk_level`,
      `file`, `line`, `description`, `fix_type`, `suggested_fix`). Report the element count in the
      failure message.
- [ ] `CX12` (R-02) — the stub returns `"dimension": "structure"` while the call passes
      `--dimension perf`; the output says `perf` on every element. Plant: remove the forcing.
- [ ] `CX13` (R-02) — the stub returns `"id": "STUB-JUNK"`; no output element carries it, and every
      `id` matches `^<dimension>-[^-]+-.{3}$` in shape. Plant: remove the synthesis.
- [ ] `CX14` (R-03; R-13 plan-side only) — Mandatory guard 1's string, **extracted from `SKILL.md`**
      (not typed into this file), appears whitespace-flattened in `codex-reviewer.sh`. Plant: mutate
      the guard text inside `codex-reviewer.sh`. Write only `R-03` into the file.
- [ ] `CX15` (R-03; R-13 plan-side only) — Mandatory guard 2's string, same extraction, same
      flattened match, same plant shape. Write only `R-03` into the file.
- [ ] `CX16` (R-03) — the extraction's own denominator: exactly **two** guard strings are extracted
      from `SKILL.md` and each is at least 80 characters. Zero extracted must FAIL, never pass
      vacuously (rule 7).
- [ ] `CX17` (R-03; R-13 plan-side only) — **dimension-correct embedding, all four directions.** Capture the
      prompt the stub receives for each dimension: `dead-code` contains guard 1 and not guard 2;
      `perf` contains guard 2 and not guard 1; `structure` and `security` contain neither. Plant:
      make the guard block unconditional.
- [ ] `CX18` (R-04) — the stub returns `"fix_type": "coder"` on a security finding; `--out` shows
      `report-only` on **every** element for `--dimension security`. Plant: remove the forcing
      assignment.
- [ ] `CX19` (R-04) — the same stub payload through `--dimension dead-code` leaves `fix_type` as
      `coder`. The direction `CX18` cannot see by itself (rule 8): the forcing must be scoped to
      security, not global.
- [ ] `CX20` (R-05, R-06) — both branches under `### Dispatch model` in `SKILL.md` carry the
      IF/ELSE on the flag, each naming `codex-reviewer.sh --mode audit --dimension` and each
      stating the per-dimension exit-3 fallback to the Claude `reviewer` call for that dimension
      only. Assert **two** such branches, exactly. Plant: delete one branch's IF.
- [ ] `CX21` (R-07, R-11) — **byte-preservation of the Claude-only ELSE.** A frozen list of four
      literals must each appear exactly as today: `model: "opus", effort: "high"`;
      `inherit the session`; `Dispatch the 4 reviewer agents sequentially using the` ; and the
      `dispatch-site: deep-refactor-reviewers` marker. Exact count of four, not a floor. Plant:
      reword one of the four.
- [ ] `CX22` (R-08) — `Gate 0-CDX` exists in `SKILL.md`, is `AskUserQuestion`-shaped, sits between
      the `HITL Gate 0` heading and the `## Phase 1` heading (compare line numbers computed at
      runtime — never write a line number into the assertion, rule 12), and lists the
      `No — Claude only` option first with `(Recommended)` on its label. Plant: move or delete the
      gate block.
- [ ] `CX23` (R-09) — the unattended path is stated: no question is asked under autopilot; the value
      is inherited from `use_codex_review` read through `manifest-field-state.sh`; with no manifest
      the resolution is Claude-only. Three separate clause matches, flattened (rule 3). Plant:
      delete the no-manifest clause.
- [ ] `CX24` (R-10) — Gate 1's summary block carries a per-dimension engine line naming both
      `Codex` and `Claude (fallback)`, conditional on the flag having been on for the run. Plant:
      delete the conditional block.
- [ ] `CX25` (R-11) — **no collateral drift.** The four `| <dimension> | reviewer |` table rows are
      still present, and the finding-schema fence still declares nine field names. GREEN from
      Batch A; a red here means a later task edited something it was told not to.
- [ ] `CX26` (R-14 plan-side only — no `R-NN` token in the file) — ADR-0187's deferral sentence
      survives verbatim (whitespace-flattened) in
      `docs/architecture/ADR-0187-codex-review-gate.md`: *"…to Gate 5.06 / `security-audit` /
      `deep-refactor`, or to `--autopilot` runs — all explicitly deferred, not solved."* Rule 14 —
      the historical record is not corrected in place. GREEN from Batch A. Plant (via the
      `../docs/` prefix): mutate that sentence, and watch this go RED.
- [ ] `CX27` (R-14 plan-side only — no `R-NN` token in the file) —
      `docs/architecture/ADR-0193-codex-review-gate-deep-refactor.md` exists and
      names `ADR-0187`, and `docs/chain-decision-index.md` carries an `ADR-0193` entry that also
      names `ADR-0187`. The index half is RED until Task 10.
- [ ] `Z1` — vacuity floor only, and say so at the site: `>= 28` assertions ran. A floor absorbs its
      own plant (rule 10), so this pins nothing about identity — `CX01`–`CX27` are the frozen set.

Budget: `staging/plugin/scripts/tests/codex-audit-mode.test.sh` (~540 lines)

## Task 2 — CODE: `--mode audit` argument surface and availability cascade (R-01)

Owner: **coder**. Edit `staging/plugin/scripts/codex-reviewer.sh` only.

- Add `DIMENSION=""` beside the existing five variables; add `--dimension) DIMENSION="${2:-}"; shift 2 ;;`
  to the `while` parser. Without the parser arm even a correct call exits 2 on "unknown argument".
- `case "$MODE" in review|diagnose|audit) ;;` and update the failure message to name all three.
- After the `--out` check, add the audit block: `--dimension` required and validated against
  `dead-code|perf|structure|security` (exit 2, message naming all four); `--diff-scope`, **when
  non-empty**, validated by the same `case` arm shape `review` mode uses — `uncommitted|base:*|commit:*`
  — exit 2 otherwise. Empty is legal and means whole-tree (ADR-0193 §D2).
- Extend the git-work-tree guard from `[ "$MODE" = "review" ]` to review-or-audit.
- Add the helper probe after the auth probe: resolve
  `ENUM="$SCRIPT_DIR/../skills/deep-refactor/scripts/enumerate-sources.sh"`; if not readable, exit
  3 with `codex-reviewer: DID-NOT-RUN: enumerate-sources.sh not found at <path>`. Only in audit
  mode — the two existing modes must not gain a new failure path.
- Update the header comment block in the file's existing style: add the third mode to the "TWO
  MODES" list (retitle it), state the exit contract is unchanged, and state that audit-mode output
  is `FINDINGS_SCHEMA` JSON rather than markdown.

`bash -n` clean. `CX01`–`CX09` go green here; nothing else does.

Budget: `staging/plugin/scripts/codex-reviewer.sh` (~70 lines)

## Task 3 — CODE: audit schema block, file-list derivation, and the two verbatim guards (R-02, R-03)

Owner: **coder**. Edit `staging/plugin/scripts/codex-reviewer.sh` only.

- **Placement matters.** Add the audit branch so the existing review and diagnose `SCHEMA_EOF`
  blocks keep their relative order, and note in a comment beside the new block that
  `codex-reviewer-schema.test.sh` reads all blocks and pins the count (Task 5) — so the next mode
  added must bump that count deliberately.
- The audit `<<'SCHEMA_EOF'` block: a root object with `findings` (array) plus
  `"additionalProperties": false` on the root **and** on the item object. Item properties are the
  nine `FINDINGS_SCHEMA` fields; `severity` enum `P1|P2|P3`, `risk_level` enum `low|high`,
  `fix_type` enum `coder|refactorer|debugger|report-only`, `line` typed `["integer","null"]`.
  **Every property must also appear in `required`** — OpenAI's structured-output mode has no
  optional properties; nullability is how "may be absent" is expressed. ADR-0187's Correction is
  the precedent for taking this seriously: a stub cannot reproduce the API's own schema validation.
- File list: `FILE_LIST=$("$ENUM" "$(git rev-parse --show-toplevel)")` for the whole-tree case; when
  `--diff-scope` is non-empty, intersect it with the diff's changed paths using the same three
  `case` arms review mode uses (`git diff HEAD --name-only`, `git diff <ref>...HEAD --name-only`,
  `git show --name-only --pretty=format: <sha>`). An empty result is **exit 0 with `[]` written to
  `--out`**, mirroring review mode's empty-diff precedent — not exit 3.
- Prompt construction, an unquoted `PROMPT_EOF` heredoc (interpolation is needed), building
  `GUARD_BLOCK` first:
  - `dead-code` → Mandatory guard 1's string, **on one source line**, copied character for
    character from `SKILL.md` including the `→`.
  - `perf` → Mandatory guard 2's string, same treatment.
  - `structure`, `security` → empty.
  Guard the `$` and backtick hazards: neither guard string contains either today; if a future edit
  introduces one, the heredoc must become quoted and the interpolation restructured.
- The prompt states the dimension's scope in `SKILL.md`'s own words, the P1/P2/P3 rubric, the
  `risk_level: high` = hard-skip semantics, and — for `security` — that every finding is
  `report-only`. That last sentence is belt to Task 4's braces: the prompt asks, the post-process
  enforces (rule 16).

`bash -n` clean. `CX10`, `CX14`–`CX17` go green here.

Budget: `staging/plugin/scripts/codex-reviewer.sh` (~120 lines)

## Task 4 — CODE: the `python3` post-process — JSON out, `id` synthesis, security forcing (R-02, R-04)

Owner: **coder**. Edit `staging/plugin/scripts/codex-reviewer.sh` only.

Add a third arm to the formatting section, in the same `RAW_OUT=… CR_OUT=… python3 -c` shape the
two existing arms use, with the same exit-3-on-unparseable handling and the same `FORMAT_RC`
branching. It writes `--out` as a JSON **array** (not the schema's `{"findings": …}` wrapper — the
skill merges arrays).

Per finding, in this order:

1. `dimension` = the `--dimension` argument, unconditionally. Never the model's value.
2. `id` = `<dimension>-<basename(file)>-<hash3>`, where `hash3` is the first three hex characters of
   a stable digest of `file + str(line) + description`. Deterministic across runs on the same input
   — the dedup and report stages key on it.
3. `fix_type` = `report-only` when `DIMENSION` is `security`, unconditionally; otherwise the model's
   value, defaulted to `report-only` if it is not one of the four legal values (an unrecognised
   value must never route a fix agent).
4. `risk_level`, `severity`, `file`, `line`, `description`, `suggested_fix` pass through, each with
   a safe default so a partial object cannot crash the formatter.

`bash -n` clean. `CX11`–`CX13`, `CX18`, `CX19` go green here.

Budget: `staging/plugin/scripts/codex-reviewer.sh` (~95 lines)

## Task 5 — TEST: `codex-reviewer-schema.test.sh` from ordinal to all-blocks (R-02)

Owner: **tester**. Edit `staging/plugin/scripts/tests/codex-reviewer-schema.test.sh` only. This is
the observable-contract repair from "Read this second" item 2, and it is a separate task precisely
so it is not buried in a code batch.

- Replace `extract_schema <ordinal>` with an enumeration over **every** `SCHEMA_EOF` block, running
  the existing `check_schema` on each as `S1`, `S2`, `S3`, … The awk extractor's structure is
  reusable; only the ordinal selection goes.
- Add `SC1`: the block count is **exactly 3**, equal to the mode count. An exact equality, not a
  floor — and say at the site that this is deliberate, and that adding a fourth mode means bumping
  this number on purpose.
- Update the header comment: state that extraction was ordinal until 2026-09-05, that ADR-0193 §D7
  records why it changed, and that a position-dependent extractor rots the same way a line-number
  cross-reference does (rule 12).
- Leave a comment where the ordinal extractor stood, naming issue-less ADR-0193 (rule 19 — a
  deleted assertion leaves a note).
- Bump `Z1`'s floor. Measured 2026-09-05 before this task: the file runs `S0`, `S1`, `S2` and `Z1`
  — `PASS=3` plus the `Z1` line, floor `>= 2`. After this task it runs `S0`, `S1`, `S2`, `S3`,
  `SC1` and `Z1`, so the floor becomes `>= 5`. Re-derive rather than trusting those numbers.

`S1`–`S3` and `SC1` green after Task 3 has landed; RED before it, which is why this task follows
Task 3 rather than preceding it.

Budget: `staging/plugin/scripts/tests/codex-reviewer-schema.test.sh` (~60 lines)

## Task 6 — SKILL: Gate 0-CDX and the unattended inheritance rule (R-08, R-09, R-11)

Owner: **coder**. Edit `staging/plugin/skills/deep-refactor/SKILL.md` only. Insert **after** the
`### HITL Gate 0 — Approval to start` block (including its "If Abort" line) and **before** the
`---` that precedes `## Phase 1`.

New subsection `### HITL Gate 0-CDX — Audit engine (Codex or Claude)`:

- Names the run-local variable `USE_CODEX_AUDIT` and says outright it is **not**
  `manifest.use_codex_review` and **not** a manifest field — `deep-refactor` runs standalone with
  no manifest, which is its own documented Branch A condition.
- The unattended rule first: under `manifest.autopilot = true` no question is asked; with a manifest
  present the value is `manifest.use_codex_review` read through `manifest-field-state.sh`, with
  ABSENT / INVALID / UNREADABLE all resolving to `false` (rule 11 — three states, and absent must
  equal the pre-feature behaviour); with no manifest, `false`.
- Then the attended `AskUserQuestion` block in this file's existing gate format, options in this
  order: `"No — Claude only (current behaviour) (Recommended)"`, then
  `"Yes — use Codex for the 4 audit dimensions, with per-dimension fallback"`.
- One sentence stating that when `USE_CODEX_AUDIT` is false every downstream behaviour in this
  skill is byte-identical to before this feature (R-11's readable form).
- The naming note: `Gate 0-CDX`, not `Gate 0c` — that identifier is retired in `concept-to-code`'s
  namespace and repo convention does not reuse retired names.

Any shell shown uses ` ```sh `, this file's convention throughout (it has six ```sh fences and zero
```bash). **Disclosed rather than left silent:** the fence-declaration harness's population is
```bash fences only, so a ```sh fence here carries no declaration obligation. That is a coverage
boundary, not an exemption — if the operator wants the call covered, the fence must become ```bash
with a `<!-- fence-contract: … -->` marker and a test that executes it.

`CX22`, `CX23` go green here.

Budget: `staging/plugin/skills/deep-refactor/SKILL.md` (~60 lines)

## Task 7 — SKILL: the IF/ELSE wrap at both dispatch branches (R-05, R-06, R-07, R-11)

Owner: **coder**. Edit `staging/plugin/skills/deep-refactor/SKILL.md` only, inside
`### Dispatch model`.

**The ELSE is a move, not a rewrite.** Cut today's Branch A text and today's Branch B text and paste
them, character for character, under `ELSE (USE_CODEX_AUDIT = false — today's behaviour)`. Do not
reflow, do not re-wrap, do not fix a typo, do not touch the
`<!-- dispatch-site: deep-refactor-reviewers … -->` marker. Four literals must survive verbatim and
are asserted by `CX21`: `model: "opus", effort: "high"`, `inherit the session`,
`Dispatch the 4 reviewer agents sequentially using the`, and the marker line.

The new `IF USE_CODEX_AUDIT = true` half, once per branch:

- **Branch A** — the same fan-out shape, one call per dimension, still parallel: for each of the
  four dimensions run
  `bash ~/.claude/hooks/codex-reviewer.sh --mode audit --dimension <d> --out <tmp-<d>.json>`.
  Exit `0` → parse the JSON array into the same in-memory findings shape the Claude path produces,
  so merge/dedup/sort/Gate 1 are untouched. Exit `3` → that **one** dimension falls back to the
  existing Claude `reviewer` `agent()` call for that dimension, with `model: "opus", effort: "high"`
  pinned exactly as the ELSE branch pins them; the other three stay on Codex. Exit `2` → **not** a
  fallback: it is a defect in this dispatch site's own arguments, so stop and report it.
- **Branch B** — the identical substitution, sequential, in the branch's already-fixed order
  dead-code → perf → structure → security, with the same per-dimension exit-3 fallback and the same
  exit-2 refusal.
- Record, per dimension, which engine served it. Task 8 renders it; this task produces it (rule 17
   — a producer in one place and a consumer in another need something making them meet, and here
  that is `CX24` plus this sentence).

No `dispatch-site:` marker is added. `CX20`, `CX21` go green here. Re-run
`workflow-dispatch-pins.test.sh` and `dispatch-completion.test.sh` immediately after this task —
they are the two harnesses this edit can break.

Budget: `staging/plugin/skills/deep-refactor/SKILL.md` (~80 lines)

## Task 8 — SKILL: Gate 1 engine attribution (R-10)

Owner: **coder**. Edit `staging/plugin/skills/deep-refactor/SKILL.md` only, inside
`### HITL Gate 1 — Findings summary before fixing`.

Add, in the same `[If <condition>:]` idiom the block already uses twice, one conditional block
rendered **only** when `USE_CODEX_AUDIT` was true for the run:

```text
[If USE_CODEX_AUDIT was true for this run:]
Audit engine per dimension:
  dead-code: <Codex | Claude (fallback)>
  perf:      <Codex | Claude (fallback)>
  structure: <Codex | Claude (fallback)>
  security:  <Codex | Claude (fallback)>
```

Plus one sentence stating that `Claude (fallback)` means Codex returned DID-NOT-RUN for that
dimension only and the run continued unblocked, and that nothing about the findings themselves
differs — engine attribution is display-only and is **not** a `FINDINGS_SCHEMA` field
(ADR-0193 §D8). Do not add a field to the finding schema. Do not change the existing three summary
lines, the option list, or the two existing `[If …]` blocks.

`CX24` goes green here.

Budget: `staging/plugin/skills/deep-refactor/SKILL.md` (~25 lines)

## Task 9 — WIRING: register the harness in CI, then run every plant (R-12, R-13)

Owner: **coder** for the YAML line; **tester** for the plant run and the `Z1` bump.

1. Append the bare name `codex-audit-mode` (no `.test.sh` suffix — the list uses bare names) to the
   `for t in …` harness list in `.github/workflows/docs-ci.yml`'s `shell-tests` job. **This is not
   optional and not a footnote:** `.claude/test-cmd` globs `staging/plugin/scripts/tests/*.test.sh`
   and picks the file up automatically, CI's named list does not, and the backward check that every
   staged harness appears in that list (`CI1`, ADR-0113) goes red without it. Four prior features
   shipped this gap. Do not touch any other line in that file — the sharded plant topology pins
   several of them.
2. Run `bash staging/plugin/scripts/tests/plant-check.sh` and confirm **all fifteen** declared `CX`
   plants report fired, not `NOFIRE` and not `BADPLANT`. Inspect what each plant actually produced
   before believing what it reports (rule 2). A `BADPLANT` means the needle matched zero or more
   than one site — fix the needle, never the assertion.
3. Adjust `Z1`'s floor if the final assertion count differs from the planned 28.
4. Run the **full** suite plus the skill-local
   `bash staging/plugin/skills/deep-refactor/tests/run-tests.sh`, which is in neither CI's list nor
   `.claude/test-cmd`'s glob and will otherwise never run.

Budget: `.github/workflows/docs-ci.yml`, `staging/plugin/scripts/tests/codex-audit-mode.test.sh` (~10 lines)

## Task 10 — DOC: index entry, and confirm ADR-0187 was not edited in place (R-14)

Owner: **doc-writer**.

The ADR itself was written at Step 2 and is already on disk at
`docs/architecture/ADR-0193-codex-review-gate-deep-refactor.md`. This task closes the two things it
cannot do for itself:

1. Append one entry to `docs/chain-decision-index.md`, in that file's existing single-line format,
   naming **ADR-0193** and **ADR-0187** and the `deep-refactor` scope. ADR-0187 has no entry of its
   own in that index (verified 2026-09-05: zero matches), so this line is the index's only pointer
   to the Codex gate — write it so a reader searching the index for "Codex" finds both.
2. Confirm `docs/architecture/ADR-0187-codex-review-gate.md` is **byte-unchanged** by this feature:
   `git diff --stat -- docs/architecture/ADR-0187-codex-review-gate.md` must be empty. Rule 14 — a
   historical record is not corrected in place; ADR-0193 supersedes that one scope note going
   forward instead. `CX26` pins the sentence's survival mechanically; this is the human-readable
   half of the same guarantee.

`CX27` goes green here.

Budget: `docs/chain-decision-index.md` (~2 lines)

---

## Risks, dependencies, and HITL gates

- **HITL — Gate 2 (architecture review):** `--diff-scope` optional in audit mode is the one place
  this plan does not implement a locked interview decision literally (ADR-0193 §D2, §A5, §A6).
  Confirm or overrule it before Task 2.
- **HITL — commit and push.** Ten tasks across six files including a CI workflow. No task commits.
- **Unmeasured:** a whole-tree Codex audit's latency and quota cost per dimension. The plan cannot
  measure it without spending real quota, and this repo's standing rule forbids that in CI. The
  realistic failure is a rate-limit exit 3 on later dimensions, which the per-dimension fallback
  absorbs — at the cost of a mixed-engine run whose cost profile is neither clean case.
- **Deferred to a manual pre-ship probe (the same deferral ADR-0187 made, and the same one that
  found a real defect):** one hand-run `--mode audit` against a live Codex in a scratch repo outside
  this repository, to confirm the audit schema is accepted by OpenAI's structured-output validation.
  A stub cannot reproduce that validation — that is exactly how ADR-0187's `additionalProperties`
  defect survived a full green harness.
- **Coupling introduced:** `codex-reviewer.sh` now depends on `deep-refactor`'s
  `enumerate-sources.sh` through a relative path. `CX08`/`CX09` pin it; a rename of that helper
  breaks a script in another subtree and surfaces as exit 3, not as an obvious missing file.
- **Autopilot boundary moves** (ADR-0193 §D1, and named again in its Consequences): an unattended
  run with `use_codex_review: true` now routes `deep-refactor`'s audit to Codex where no autopilot
  run previously used Codex at all.
- **Three harnesses can break from edits they never mention:** `workflow-dispatch-pins.test.sh`
  (`A1`/`A2`/`A3`), `dispatch-completion.test.sh` (`DC21`/`DC24`), and the skill-local
  `deep-refactor/tests/run-tests.sh`. Run the full suite after every batch, and the skill-local
  runner by hand.
