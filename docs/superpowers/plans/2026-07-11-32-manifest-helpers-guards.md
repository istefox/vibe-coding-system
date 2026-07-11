# Plan — concept-to-code: manifest helper guards, exit codes, and YAML escaping

**Date:** 2026-07-11
**ADR:** [ADR-0028](../../architecture/ADR-0028-32-manifest-helpers-guards.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/32-manifest-helpers-count-guards-exit-codes.spec.md`, issue #32)
**Style:** TDD (red → green → checkpoint). Auto mode active, no intermediate HITL inside this plan; commit/push
stay HITL per repo `CLAUDE.md` invariant (see HITL gates, end of file). Five independent findings (invariant 9's
count guard, two scripts' exit-code contract, one script's YAML escaping, five `SKILL.md` PATH-RULE sites, one
`SKILL.md` paragraph plus one script comment's pair-count reconciliation) — the fix scope is exactly SPEC's five
findings, nothing broader (ADR-0028 §3 records every scope boundary considered, including two disclosed-but-
deliberately-untouched items).

---

## Why every RED in this plan is genuine RED (no "already passing" companions this time)

Unlike ADR-0026's and ADR-0027's plans, none of this plan's five findings depend on an environment precondition
that fails to reproduce on the runner executing the tests (e.g., a GNU-only `sed` extension, or a script defect
that turns out to already be dead code). ADR-0028 §1's Context reproduced all three script-level findings (1, 2,
3) empirically, directly, in this session, against the real unfixed scripts — every RED task below writes an
assertion already confirmed to fail against today's code, not one assumed to. Findings 4 and 5 are pure `SKILL.md`
text corrections with no script behavior involved, so their RED/GREEN split is a plain textual presence check.
**Non-regression companion tests still exist** (A2, B2, B4, C3, E7) — these guard against a fix over-correcting an
adjacent, already-working case (e.g., Finding 2's fix must not make the *happy* path start failing) — but every one
of them is expected to pass **both** before and after its task, and each task below states which category its own
assertions are, exactly as ADR-0026/0027's plans did.

## Fixture and path conventions (read once, applies to every task below)

- **New test file:** `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh`. Path
  derivation mirrors the six existing files in the same directory exactly:
  ```bash
  SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
  STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
  SKILL_DIR="$STAGING/plugin/skills/concept-to-code"
  SKILL_MD="$SKILL_DIR/SKILL.md"
  INIT="$SKILL_DIR/scripts/manifest-init.sh"
  VAL="$SKILL_DIR/scripts/manifest-validate.sh"
  SETART="$SKILL_DIR/scripts/manifest-set-artifact.sh"
  SETGATE="$SKILL_DIR/scripts/manifest-set-gate.sh"
  TRN="$SKILL_DIR/scripts/manifest-transition.sh"
  ```
  Zero `$HOME` dependency anywhere in the file. **Never** point any variable at `$HOME/.claude/...` — that is the
  deployed copy, out of scope (ADR-0028 §1 baseline note, same convention ADR-0027 §1 established).
- **PASS/FAIL idiom:** identical to the six existing files — `PASS=0; FAIL=0`,
  `ok() { PASS=$((PASS+1)); echo "PASS: $1"; }`, `bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }`, final line
  `printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"`, exit status `[ "$FAIL" -eq 0 ]`.
- **Live manifest fixtures (Sections A, B, C):** one shared `TMP="$(mktemp -d)"` at the top of the file, one
  `trap 'rm -rf "$TMP"' EXIT`. Every fixture gets its own `mktemp -d "$TMP/proj-<slug>.XXXXXX"` project directory
  and a distinct slug (`manifest-init.sh` refuses a same-slug/same-day double-init; distinct slugs also make
  failures unambiguous). Manifest path is always the value `manifest-init.sh` itself prints (capture via
  `M="$(bash "$INIT" ...)"`) — never hand-construct it.
- **`chmod`-based write-failure simulation (Section B only) — new technique for this suite, use exactly this
  shape:**
  ```bash
  assert_unwritable_exit4() {
    _label="$1"; _script="$2"; _manifest="$3"; shift 3
    _dir="$(dirname "$_manifest")"
    chmod 555 "$_dir"
    bash "$_script" "$_manifest" "$@" >/dev/null 2>"$TMP/unwritable.err"
    _rc=$?
    chmod 755 "$_dir"
    if [ "$_rc" -eq 4 ]; then
      ok "$_label: exits 4 against an unwritable manifest directory"
    else
      bad "$_label: exits $_rc against an unwritable manifest directory, expected 4"
    fi
  }
  ```
  **Always** restore `755` immediately after capturing `$_rc`, before the next assertion — the outer `trap 'rm -rf
  "$TMP"' EXIT` cannot remove a `555` subdirectory's contents, and a leaked read-only directory would break the
  file's own cleanup. ADR-0028 §4/Negative discloses the one known coverage caveat this technique carries
  (CI's execution-user identity) — do not attempt to "fix" that in this plan; it is a disclosed, accepted risk, not
  a defect to resolve here.
- **YAML round-trip check (Section C only) — pass values through the environment, never inline-interpolate into
  Python source:**
  ```bash
  EXPECT_TITLE="$TITLE" MANIFEST_PATH="$M" python3 -c "
  import os, sys, yaml
  d = yaml.safe_load(open(os.environ['MANIFEST_PATH']))
  sys.exit(0 if d.get('topic_full_title') == os.environ['EXPECT_TITLE'] else 1)
  " 2>"$TMP/yaml.err"
  ```
  Do not build the expected value into the Python source as a string literal (triple-quoted or otherwise) — a
  title containing `"`/`\` breaks that the same way it breaks the underlying bug this finding is about (ADR-0028
  §3.7). PyYAML is already a project dependency (`autopilot-build/SKILL.md`'s pre-flight checks); confirmed present
  on `ubuntu-latest` GitHub Actions images and on this session's local machine — no `pip install` at test time (the
  `shell-tests` CI job is explicitly offline).
- **Bash 3.2 / BSD safety (every file touched this plan):** no `${var,,}`, no `mapfile`, no `<()`, no
  `declare -A`, no GNU-only regex shorthands (`\s`, `\d`) in any `grep -E`/`awk` pattern — use `[[:space:]]` or
  literal character classes instead (confirmed necessary during planning: an initial pair-count draft using `\s`
  happened to work locally on macOS's BSD `grep` but is not POSIX-guaranteed; the shipped version avoids it).
- **Per-task checkpoint (four checks, all must pass before moving to the next task):**
  1. `bash -n <every .sh file touched this task>`.
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' <changed-file>` — must be empty.
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay green (this plan adds zero `PAIRS`
     entries anywhere; the four edited scripts already have mappings, and the new test file, like its
     predecessors, gets none — ADR-0028 §2.6).
  4. `bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` — must stay green, 17/17,
     unchanged (collision canary with #31's immediately-preceding, same-directory work).

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verify, do not assume from the ADR):
  `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` → 7/7 green (one more than
  ADR-0027's own 6/6 baseline — #31 added the 7th file during its own execution).
- Writes are confined to: `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh`,
  `staging/plugin/skills/concept-to-code/scripts/manifest-set-artifact.sh`,
  `staging/plugin/skills/concept-to-code/scripts/manifest-set-gate.sh`,
  `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh`,
  `staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh` (Task 8 only, its line-50 **comment**,
  zero `PAIRS`-table lines), `staging/plugin/skills/concept-to-code/SKILL.md`,
  `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` (new file),
  `.github/workflows/docs-ci.yml`, `SPEC.md` (checkbox updates, final task), `docs/architecture/`,
  `docs/superpowers/plans/` (already written by this ADR/plan pass).
- Do not touch: `staging/sync-to-claude.sh` (all four edited scripts already have `PAIRS` mappings; no additions
  needed — ADR-0028 §2.6), `staging/plugin/skills/concept-to-code/tests/{run-tests.sh,smoke-e2e.sh,
  agent-notes-roundtrip.sh}` (hardcode `$HOME/.claude/...`, target the deployed copy by design — ADR-0027 §1
  baseline, unchanged — do not add assertions there for this issue), any file under `~/.claude`,
  `manifest-transition.sh`'s `PAIRS` table itself (lines 52-101; only the line-50 **comment** above it changes —
  verify with a targeted diff in Task 8's checkpoint), `SKILL.md:569` (Finding 4's disclosed-but-untouched sixth
  mention — ADR-0028 §3.6), `docs/architecture/ADR-0017*.md` and other historical ADRs (immutable records, never
  retroactively edited).
- `manifest-validate.sh` edits are scoped exactly to invariant 9's `gate_count=` line (current line 147). Do
  **not** touch invariant 7's or invariant 9's own `chain_path_val` computations, the `min_gates` `case`
  statement, or the final `if`/`fail` — all four stay byte-identical (ADR-0028 §3.2).
- `manifest-set-artifact.sh`/`manifest-set-gate.sh` edits mirror `manifest-set-flag.sh`'s existing
  `TMP=""; TMP2=""; trap ...; ... || { ...; exit 4; }` shape **verbatim** — do not invent a differently-shaped
  error-handling idiom (e.g. `set -e`) for these two scripts (ADR-0028 §3.3).
- `manifest-init.sh` edits are scoped exactly to one new `title_esc=` line and the `topic_full_title` echo line
  (current line 61). Do **not** apply the same escaping to `slug` (already regex-validated, no special characters
  possible) or any other field — SPEC names `topic_full_title` only.
- `SKILL.md` edits are scoped exactly to: five PATH-RULE sites (current lines 120, 547, 549, 1175, 1352 —
  path-prefix substitution only, surrounding sentence text otherwise untouched) and the pair-count paragraph
  (current lines 221-224, plus the helper-description line 237). Do **not** touch `SKILL.md:569` (disclosed,
  deliberately deferred — ADR-0028 §3.6) or any gate-logic/state-transition content (issue #31's already-closed
  scope).

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/prep.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` → exit 0, unchanged `PASS` count throughout this
  plan (no new `PAIRS` entries added at any point).
- `bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` → exit 0 (untouched by this plan).
- `bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` → exit 0, unchanged 17/17
  (collision canary with issue #31's immediately-preceding, same-directory work).
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing under `~/.claude` is
  ever touched.

---

## Task 1 — RED: Section A (Finding 1, invariant 9 count guard)

**Files created:**
- `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` (scaffold: shebang, header
  comment naming all five sections up front — mirror ADR-0027's file header style — path derivation per "Fixture
  and path conventions," `PASS`/`FAIL` idiom, Section A's 2 tests).

**Contract:**
- **Helper `mk_empty_gates_fixture <slug>`:** `manifest-init.sh`, then strip every `  - gate:` block from the
  `hitl_gates:` list via `awk` (key line retained, resumes normal printing at the following blank line):
  ```bash
  mk_empty_gates_fixture() {
    _slug="$1"
    _proj="$(mktemp -d "$TMP/proj-$_slug.XXXXXX")"
    _m="$(bash "$INIT" "$_slug" "Test $_slug" "$_proj")"
    awk '
      /^hitl_gates:$/ { print; ingates=1; next }
      ingates && /^  - gate:/ { next }
      ingates && /^    (label|status|approved_at|notes):/ { next }
      ingates && /^$/ { ingates=0; print; next }
      { print }
    ' "$_m" > "$_m.tmp" && mv "$_m.tmp" "$_m"
    FIX_MANIFEST="$_m"
  }
  ```
- **A1 (dynamic, genuine RED).** `mk_empty_gates_fixture "a1-empty-gates"`. Run `bash "$VAL" "$FIX_MANIFEST"`
  capturing stderr. Assert exit **non-zero** AND stderr contains `hitl_gates must have at least`. **Expected now
  (RED):** exit `0` (invariant 9 silently skipped — ADR-0028 §1 Finding 1, empirically reproduced during
  planning).
- **A2 (dynamic, non-regression companion, already passing).** Fresh, unmodified fixture (default 4 gate lines,
  slug `a2-default`). Run `bash "$VAL" "$M"`. Assert exit `0`. **Expected now: already passing** — state this
  explicitly in the test's own comment; this is the guard against Task 2 over-tightening invariant 9 for the
  normal case.

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh
bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh   # Section A: PASS=1 FAIL=1 (A2 passing, A1 red)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                          # unchanged, exit 0
```

---

## Task 2 — GREEN: Finding 1 fix (`manifest-validate.sh:147`)

**Files modified:**
- `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh`

**Contract — exact replacement of the one `gate_count=` line, the four lines after it untouched:**
```bash
gate_count="$(grep -c '^  - gate:' "$MANIFEST" 2>/dev/null)"
if [ -z "$gate_count" ]; then
  gate_count=0
fi
```
`chain_path_val="$(grep '^chain_path:' ...)"`, the `min_gates` `case`, and the final `if [ "$gate_count" -lt
"$min_gates" ]; then fail ...; fi` stay byte-identical (ADR-0028 §2.1/§3.2 — do not touch invariant 7's separate
copy of the same `chain_path_val` pipeline either).

**Expected (GREEN):** A1 passes; A2 unchanged (was already passing).

**Checkpoint:**
```
bash -n staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh   # empty
bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh   # Section A: PASS=2 FAIL=0
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 3 — RED: Section B (Finding 2, exit-4 write-failure contract)

**Files modified:**
- `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` (append Section B, 4 tests, plus
  the `assert_unwritable_exit4` helper from "Fixture and path conventions").

**Contract:**
- **B1 (dynamic, genuine RED).** Fresh fixture (slug `b1-artifact-fail`). `assert_unwritable_exit4 "B1"
  "$SETART" "$FIX_MANIFEST" spec "/tmp/SPEC.md"`. **Expected now (RED):** exits `0` (ADR-0028 §1 Finding 2,
  empirically reproduced during planning).
- **B2 (dynamic, non-regression companion, already passing).** Fresh fixture (slug `b2-artifact-ok`, normal
  writable directory). `bash "$SETART" "$M" spec "/tmp/SPEC.md"`. Assert exit `0` AND
  `grep -qF '  spec: "/tmp/SPEC.md"' "$M"`. **Expected now: already passing.**
- **B3 (dynamic, genuine RED).** Fresh fixture (slug `b3-gate-fail`). `assert_unwritable_exit4 "B3" "$SETGATE"
  "$FIX_MANIFEST" 1 approved`. **Expected now (RED):** exits `0`.
- **B4 (dynamic, non-regression companion, already passing).** Fresh fixture (slug `b4-gate-ok`). `bash
  "$SETGATE" "$M" 1 approved`. Assert exit `0` AND `grep -qF '    status: "approved"' "$M"`. **Expected now:
  already passing.**

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh
bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh   # Section A: 2/2 green; Section B: PASS=2 FAIL=2 (B2,B4 passing; B1,B3 red)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                          # unchanged, exit 0
```

---

## Task 4 — GREEN: Finding 2 fix (`manifest-set-artifact.sh`, `manifest-set-gate.sh`)

**Files modified:**
- `staging/plugin/skills/concept-to-code/scripts/manifest-set-artifact.sh`
- `staging/plugin/skills/concept-to-code/scripts/manifest-set-gate.sh`

**Contract, both files identically shaped (mirrors `manifest-set-flag.sh` verbatim — ADR-0028 §2.2/§3.3):**
- Header comment: `# Exit: 0 ok | 1 usage | 2 not found | 3 key not present` (artifact) / `3 gate not present`
  (gate) gains `| 4 write failed`.
- Immediately before the first `mktemp` call, insert:
  ```bash
  TMP=""
  TMP2=""
  trap 'rm -f "${TMP:-}" "${TMP2:-}"' EXIT
  ```
- Each of the two existing `awk ... > "$TMP{,2}" && mv "$TMP{,2}" "$MANIFEST"` lines gains
  `\n  || { echo "<script-basename>: write failed for $MANIFEST" >&2; exit 4; }` (use the script's own basename in
  the message, matching `manifest-set-flag.sh`'s own self-naming convention).
- Final `exit 0` unchanged (reached only if both writes succeeded).

**Expected (GREEN):** B1, B3 pass; B2, B4 unchanged (were already passing).

**Checkpoint:**
```
for f in manifest-set-artifact.sh manifest-set-gate.sh; do
  bash -n "staging/plugin/skills/concept-to-code/scripts/$f"
  grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' "staging/plugin/skills/concept-to-code/scripts/$f"   # empty
done
bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh   # Sections A+B: PASS=6 FAIL=0
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 5 — RED: Section C (Finding 3, YAML escaping)

**Files modified:**
- `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` (append Section C, 3 tests).

**Contract:**
- **C1 (dynamic, genuine RED).** Fresh fixture, title `Feature "Quoted" \Backslash\` (slug `c1-quoted`). Run the
  env-var-passed `yaml.safe_load` round-trip check from "Fixture and path conventions." Assert exit `0`.
  **Expected now (RED):** `yaml.safe_load` raises `ParserError` (ADR-0028 §1 Finding 3, empirically reproduced
  during planning) — the round-trip check's own exit is non-zero.
- **C2 (static, genuine RED).** `grep -qF 'echo "topic_full_title: \"$title\"" >> "$T"' "$INIT"` finds **no**
  match. **Expected now (RED):** it matches — the unescaped form is still present verbatim. A companion positive
  check, `grep -qF 'title_esc' "$INIT"` finds a match, is **expected now to fail** (no match) — combine both into
  one assertion (both conditions must hold for `ok`).
- **C3 (dynamic, non-regression companion, already passing).** Fresh fixture, title `Normal Title No Specials`
  (slug `c3-normal`). Same round-trip check. Assert exit `0`. **Expected now: already passing** — nothing to
  escape, so the current unescaped code already produces valid YAML for this input.

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh
bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh   # Sections A+B: 6/6 green; Section C: PASS=1 FAIL=2 (C3 passing; C1,C2 red)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                          # unchanged, exit 0
```

---

## Task 6 — GREEN: Finding 3 fix (`manifest-init.sh:61`)

**Files modified:**
- `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh`

**Contract — insert before the `T="$(mktemp)"` atomic-write block (current line ~56-57):**
```bash
# Escape YAML-breaking characters (backslash first, then double-quote -- order matters: a
# quote-escape's inserted backslash must not itself be re-escaped) before embedding the title
# inside a double-quoted YAML scalar (ADR-0028 Finding 3).
title_esc="$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g')"
```
Change the existing line (current line 61) from
`echo "topic_full_title: \"$title\"" >> "$T"` to `echo "topic_full_title: \"$title_esc\"" >> "$T"`. No other
field's echo line changes (`slug`, `root`, `mode` are not touched — ADR-0028 §2.3/pre-flight scope note).

**Expected (GREEN):** C1, C2 pass; C3 unchanged (was already passing).

**Checkpoint:**
```
bash -n staging/plugin/skills/concept-to-code/scripts/manifest-init.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/concept-to-code/scripts/manifest-init.sh   # empty
bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh   # Sections A+B+C: PASS=9 FAIL=0
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 7 — RED: Sections D+E (Finding 4 PATH-RULE sites, Finding 5 pair-count reconciliation)

**Files modified:**
- `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` (append Sections D and E, 5 + 7 =
  12 tests, all static except E7).

**Contract — Section D (static, genuine RED, one compound anchor per site — ADR-0028 §2.6):**
- **D1.** `grep -qF 'in the manifest (via `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`); proceed to step 8b.' "$SKILL_MD"` — no match yet.
- **D2.** `grep -qF 'exit 0 (VERIFIED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified true`' "$SKILL_MD"` — no match yet.
- **D3.** `grep -qF 'exit 1 (REFUTED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified false`' "$SKILL_MD"` — no match yet.
- **D4.** `grep -qF '`[y]` → set `manifest.anonymize = true` (via `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`); proceed.' "$SKILL_MD"` — no match yet.
- **D5.** `grep -qF '`[yes]` → `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`; proceed.' "$SKILL_MD"` — no match yet.

(Write each as a literal `grep -F` pattern in the test file, backticks included in the search string — quote the
whole pattern in single quotes at the shell level, matching the style `concept-to-code-bsd-autopilot-gates.test.sh`
already uses for its own backtick-containing anchors.)

**Contract — Section E (Finding 5, ADR-0028 §2.5/§2.6):**
- **E1 (static, genuine RED).** `grep -qF 'Legal transition pairs (48 total — 28 standard + 6 express + 14 hybrid, including Gate 0d routing and direct-close shortcuts):' "$SKILL_MD"` — no match yet (today: 44/26/12).
- **E2 (static, genuine RED).** `grep -qF 'performs legal state transitions atomically (48 pairs).' "$SKILL_MD"` — no match yet (today: 51).
- **E3 (static, genuine RED).** `grep -qF '# Build legal transition pairs into temp file (spec §3.3, 48 transitions)' "$TRN"` — no match yet (today: 16).
- **E4 (static, genuine RED).** `grep -qF '`gate_h1b_brainstorm→gate_h1c_macos_ux`' "$SKILL_MD" && grep -qF '`gate_h1c_macos_ux→step_h2_plan`' "$SKILL_MD"` — neither matches yet. (Confirmed during planning: the
  differently-formatted, spaced prose sentences at `SKILL.md:1020`/`:1025` do **not** collide with this no-space
  compact-list anchor.)
- **E5 (static, genuine RED).** `grep -qF 'Standard (preserved): all 28 existing pairs unchanged' "$SKILL_MD"` — no match yet (today: 21).
- **E6 (static, genuine RED).** `grep -qF '`step_e4_commit→completed`, `gate_e3_verify→completed`' "$SKILL_MD"` — no match yet (today: enumeration ends at `step_e4_commit→completed`).
- **E7 (dynamic, mechanical proof, already passing today — independent of this task's own `SKILL.md` edits).**
  ```bash
  actual_pairs="$(awk '/PAIRS="\$\(mktemp\)"/,/if ! grep -Fxq/' "$TRN" | grep -Ec '^ *echo "[a-z_0-9]+,[a-z_0-9]+" >')"
  [ "$actual_pairs" -eq 48 ]
  ```
  **Expected now: already passing** (48, confirmed by direct recount during planning — ADR-0028 §1 Finding 5). This
  assertion never depends on `SKILL.md`'s prose; state that explicitly in the test's own comment — it is a
  permanent drift-detector for `manifest-transition.sh` itself, not a RED/GREEN pair for this task.

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh
bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh   # A+B+C: 9/9 green; Section D: PASS=0 FAIL=5; Section E: PASS=1 FAIL=6 (E7 passing; E1-E6 red)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                          # unchanged, exit 0
```

---

## Task 8 — GREEN: Finding 4 fix (five PATH-RULE sites) + Finding 5 fix (pair-count reconciliation)

**Files modified:**
- `staging/plugin/skills/concept-to-code/SKILL.md`
- `staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh` (one comment line only)

**Contract — Finding 4, five path-prefix substitutions, surrounding text otherwise untouched (current lines):**
- **120:** `scripts/manifest-set-flag.sh` → `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh`.
- **547:** `bash manifest-set-flag.sh` → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh`.
- **549:** `bash manifest-set-flag.sh` → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh`.
- **1175:** `scripts/manifest-set-flag.sh` → `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh`.
- **1352:** `scripts/manifest-set-flag.sh` → `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh`.

Do **not** touch `SKILL.md:569` (ADR-0028 §3.6 — disclosed, deliberately out of scope).

**Contract — Finding 5, current lines 221-224 and 237, plus `manifest-transition.sh:50`:**
- **221:** `Legal transition pairs (44 total — 26 standard + 6 express + 12 hybrid, ...)` → `(48 total — 28
  standard + 6 express + 14 hybrid, ...)` (rest of the sentence unchanged).
- **222:** `Standard (preserved): all 21 existing pairs unchanged` → `Standard (preserved): all 28 existing pairs
  unchanged` (number only).
- **223:** Express enumeration gains one item at the end: `..., `step_e4_commit→completed`` becomes
  `..., `step_e4_commit→completed`, `gate_e3_verify→completed``.
- **224:** Hybrid enumeration gains two items, inserted immediately after `` `gate_h1b_brainstorm→step_h2_plan` ``
  (matching the script's own line order): `` `gate_h1b_brainstorm→gate_h1c_macos_ux`, `gate_h1c_macos_ux→step_h2_plan` ``.
- **237:** `...atomically (51 pairs).` → `...atomically (48 pairs).`.
- `manifest-transition.sh:50`: `# Build legal transition pairs into temp file (spec §3.3, 16 transitions)` →
  `# Build legal transition pairs into temp file (spec §3.3, 48 transitions)`. **No other line in this file
  changes** — verify with the diff command in this task's checkpoint.

**Expected (GREEN):** D1-D5, E1-E6 pass; E7 unchanged (was already passing).

**Checkpoint:**
```
bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh   # full file green: PASS=21 FAIL=0
diff <(git show HEAD:staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh) staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh
# expect exactly one changed line (the line-50 comment) -- confirms the PAIRS table itself is untouched
grep -c 'manifest-set-flag.sh' staging/plugin/skills/concept-to-code/SKILL.md   # expect 10 (unchanged mention count, only prefixes changed; includes the deferred SKILL.md:569 bare mention)
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 9 — GREEN: CI wiring

**Files modified:**
- `.github/workflows/docs-ci.yml` — append `concept-to-code-manifest-helpers-guards` to the `shell-tests` job's
  `for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety
  concept-to-code-bsd-autopilot-gates` list, becoming `for t in phase1 prep hook-probe hook-verify-workflow
  pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates
  concept-to-code-manifest-helpers-guards; do`.

No change needed to `.claude/test-cmd` — its existing glob (`staging/plugin/scripts/tests/*.test.sh`) already picks
up the new file automatically (confirmed unchanged during planning).

**Checkpoint:**
```
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # local test-cmd verbatim: 8/8 green
grep -n 'concept-to-code-manifest-helpers-guards' .github/workflows/docs-ci.yml   # exactly one match, inside the shell-tests `for t in ...` line
```

---

## Task 10 — Final verification, bash-safety sweep, SPEC checkbox update, report

**Files modified:**
- `SPEC.md` — check off the success-criteria boxes genuinely satisfied (expect all 5: invariant-9-fires-on-zero-
  gates harness test; set-artifact-unwritable-exits-4 harness test; init-with-quoted-title-parses harness test;
  bash 3.2 clean; no `~/.claude` file touched).

**Verify (full, repo-wide):**
```
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done    # local test-cmd, 8/8 green
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                       # unchanged, exit 0
for f in staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh \
         staging/plugin/skills/concept-to-code/scripts/manifest-set-artifact.sh \
         staging/plugin/skills/concept-to-code/scripts/manifest-set-gate.sh \
         staging/plugin/skills/concept-to-code/scripts/manifest-init.sh \
         staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh; do
  bash -n "$f" || exit 1
  grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' "$f" && exit 1
  grep -nF '<<<' "$f" && exit 1
done
echo "bash 3.2 / BSD safety: clean"
diff <(git show HEAD:staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh) staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh   # exactly one line changed (the comment)
grep -c 'manifest-set-flag.sh' staging/plugin/skills/concept-to-code/SKILL.md      # 10, unchanged mention count (includes the deferred SKILL.md:569 bare mention)
npx --yes markdownlint-cli2 "docs/architecture/ADR-0028-32-manifest-helpers-guards.md"   # expect exit 0 (SKILL.md and docs/superpowers are lint-ignored by design, ADR files are not)
git status   # confirm change set matches Pre-flight "writes are confined to" list; nothing under ~/.claude
```

**Report to dispatcher:**
- ADR path, spec path, plan path.
- New test file's final tally (expect `PASS=21 FAIL=0`, sections A=2, B=4, C=3, D=5, E=7).
- Full local `test-cmd` glob result (8/8 files green) pasted verbatim.
- Explicit confirmation `manifest-transition.sh` has exactly a one-line diff from `HEAD` (the line-50 comment) —
  the `PAIRS` table itself needed zero changes.
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted during this session.
- Explicit flag: the *deployed* `concept-to-code` copy at `~/.claude/skills/concept-to-code/` still contains all
  five defects until a human runs `sync-to-claude.sh --apply`.
- Explicit flag for the human reviewer: Finding 5's fix touched two numbers (`SKILL.md:222`'s "21"→"28", and the
  Express bullet's added `gate_e3_verify→completed` pair) that SPEC's finding text does not name by digit — a
  disclosed, reasoned scope extension (ADR-0028 §3.5), not a silent one, but worth a second look at review time.
- Explicit flag: `SKILL.md:569`'s sixth, unnamed bare `manifest-set-flag.sh` mention (Finding 4) was found during
  research and deliberately left unfixed (ADR-0028 §3.6) — a disclosed candidate for a future issue, not this
  one's scope.
- Explicit flag: Section B's `chmod 555`-based write-failure tests carry a disclosed, unresolved coverage caveat
  for CI's execution-user identity (ADR-0028 §4/Negative) — verified correct locally in both directions, not
  independently re-verified on `ubuntu-latest` itself in this session.
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — the `chmod 555` write-failure simulation may silently no-op if the executing user is root (or has
  equivalent override capability).** If Task 3/4's B1/B3 assertions pass even *before* Task 4's fix lands (i.e.,
  they are not observed to be genuine RED when the coder actually runs Task 3's checkpoint), this is the most
  likely cause — stop and flag it rather than proceeding as if the fix were verified; do not weaken the assertion
  to force a pass. **Mitigation:** Task 3's checkpoint explicitly expects `PASS=2 FAIL=2`; if B1/B3 show `PASS`
  instead of the expected `FAIL` at that checkpoint, halt and report the anomaly before writing Task 4's fix.
- **Risk B — Section D's five compound anchors are near-duplicates of each other (three of the five share the
  identical `anonymize true` payload) and could be miswritten to match the wrong site.** A anchor that is too
  short (e.g., just the absolute path fragment) would match all three `anonymize`-related sites indiscriminately,
  masking a missed fix at one specific line. **Mitigation:** Task 7's contract gives the exact, full compound
  string for each of the five sites, including enough unique surrounding text to disambiguate — copy them
  verbatim, do not shorten.
- **Risk C — Finding 3's `sed` escape order is easy to get backwards.** Escaping quotes before backslashes (the
  wrong order) silently corrupts any title containing both characters, and a naive test using a title with only
  one of the two characters would not catch the ordering bug. **Mitigation:** C1's fixture title
  (`Feature "Quoted" \Backslash\`) deliberately contains both, in an order chosen so an escape-order bug produces
  a detectably wrong round-trip, not a coincidentally-correct one — do not simplify the fixture title to only one
  special character.
- **Risk D — scope creep into `SKILL.md:569`, `manifest-transition.sh`'s `PAIRS` table, or Hybrid's Gate H3
  `Abort` line (already out of scope per ADR-0027 §3.4).** All are tempting "fix while you're in there" edits.
  **Mitigation:** Pre-flight constraints and ADR-0028 §3.5/§3.6 are explicit that these are deliberately out of
  scope; the one-line-diff check on `manifest-transition.sh` in Task 8 and Task 10 is the automated backstop; `git
  status` in Task 10 is the backstop for the rest.
- **Risk E — the deployed skill keeps all five defects until sync.** Not a defect in this plan's own execution,
  but a real operational risk this plan cannot itself close. **Mitigation:** flagged with explicit priority in
  Task 10's report, matching ADR-0026/0027's precedent.

## HITL gates

- No HITL gate inside this plan itself (auto mode; every edit is additive/corrective text or a conditional-guard
  addition; no destructive git operations; every live script invocation in Tasks 1-8 targets a disposable, isolated
  `mktemp -d` fixture, never this repository's own real manifests).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push remain
  human-gated, as does the follow-up `sync-to-claude.sh --apply` that would actually deploy these fixes (Risk E) —
  that sync is explicitly out of this plan's scope and requires its own separate human action.
- No DB schema change, no permanent deletion, no production migration in this plan — none of the invariant HITL
  triggers beyond the standard commit/push gate apply here.
