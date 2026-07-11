# Plan — concept-to-code: BSD-safe slug stamp and autopilot gate fixes

**Date:** 2026-07-11
**ADR:** [ADR-0027](../../architecture/ADR-0027-31-c2c-bsd-slug-autopilot-gates.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/31-concept-to-code-bsd-safe-slug-stamp-and.spec.md`, issue #31)
**Style:** TDD (red → green → checkpoint). Auto mode active, no intermediate HITL inside this plan; commit/push
stay HITL per repo `CLAUDE.md` invariant (see HITL gates, end of file). These are correctness + unattended-safety
fixes (one P1 portability bug, one Gate-order reachability defect, two autopilot policy violations, one
validator/state-machine defect) — the fix scope is exactly SPEC's five findings, nothing broader (ADR-0027 §3
records every scope boundary considered and rejected, including two explicit hand-offs to issue #32).

---

## Why some of this plan's RED is real RED, and some is an honest non-regression companion

Three of the five findings (1: slug stamp, 4: Gate order, 5-partial: `aborted` transition mechanics) have a
property ADR-0026's plan also flagged for one of its three findings: the underlying script
(`manifest-transition.sh` for Findings 4/5, GNU `awk` semantics on `ubuntu-latest` for Finding 1) already behaves
correctly for the *fixed* procedure even before this plan's SKILL.md edits land, because the defect lives entirely
in the **prose that never invoked** the already-correct capability. For those sub-cases, the "RED" task still
writes the assertion, but discloses up front that it is expected to **already pass** (an always-green mechanical
proof, not a bug reproduction) — the same `ok()`-in-the-RED-task idiom ADR-0026's Task 1 used for its own A4.
Findings 2, 3, and the invariant-7/Gate-E3-abort half of Finding 5 are genuine RED-now/GREEN-after: they assert
against SKILL.md text or `manifest-validate.sh` logic that is provably wrong today and provably correct after the
targeted edit. Each task below states explicitly, per assertion, which category it is — do not infer it from
task position alone.

## Fixture and path conventions (read once, applies to every task below)

- **New test file:** `staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh`. Path derivation
  mirrors `pairs-completeness.test.sh` / `clean-public-repo-history-safety.test.sh` exactly:
  ```bash
  SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
  STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
  SKILL_DIR="$STAGING/plugin/skills/concept-to-code"
  SKILL_MD="$SKILL_DIR/SKILL.md"
  INIT="$SKILL_DIR/scripts/manifest-init.sh"
  VAL="$SKILL_DIR/scripts/manifest-validate.sh"
  TRN="$SKILL_DIR/scripts/manifest-transition.sh"
  ```
  Zero `$HOME` dependency anywhere in the file — it must run identically in CI (`ubuntu-latest`, no `~/.claude`)
  and locally. **Never** point any variable at `$HOME/.claude/...` — that is the deployed copy, out of scope
  (ADR-0027 §1 baseline note).
- **PASS/FAIL idiom:** same as the existing five test files — `PASS=0; FAIL=0`,
  `ok() { PASS=$((PASS+1)); echo "PASS: $1"; }`, `bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }`, final line
  `printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"`, exit status `[ "$FAIL" -eq 0 ]`.
- **Live manifest fixtures (Sections C, D):** every fixture gets its own `mktemp -d` project directory under one
  shared `TMP="$(mktemp -d)"` at the top of the file, one `trap 'rm -rf "$TMP"' EXIT`. Use a distinct slug per
  fixture (`c1-express`, `c2-standard`, `d1-standard`, etc.) — `manifest-init.sh` refuses a same-slug/same-day
  double-init, and distinct slugs also make failures unambiguous in the output. Manifest path is always
  `"$PROJ/docs/manifests/$(date +%Y-%m-%d)-<slug>.manifest.yml"` — **never** construct it any other way (same
  rule the SKILL.md itself states for the orchestrator, `SKILL.md:93`).
- **Manifest field patches:** use the exact `sed -i.bak` substitution shapes already established in
  `staging/plugin/skills/concept-to-code/tests/run-tests.sh` (Assertions 9/11/12) and in `SKILL.md`'s own Gate 0
  click handler (`SKILL.md:1103`, `sed -i.bak 's/^chain_path: null$/chain_path: "<path>"/'`):
  - `chain_path`: `sed -i.bak 's/^chain_path: null$/chain_path: "<express|hybrid|standard>"/' "$M"`
  - `status`: `sed -i.bak 's/^status: .*/status: "completed"/' "$M"`
  - `artifacts.spec`: `sed -i.bak 's|^  spec: null|  spec: "/tmp/SPEC.md"|' "$M"` (quoted absolute path — invariant
    7 requires the quotes; an earlier bug class this repo already regression-tests, do not reintroduce it)
  - This test file's own fixtures run on **bash 5** (`ubuntu-latest`'s default) but must stay bash-3.2-syntax-clean
    regardless (repo-wide discipline) — no `${var,,}`, no `mapfile`, no `<()`, no `declare -A`.
- **A3's extract-and-execute helper (Section A only):**
  ```bash
  extract_slug_stamp() {
    awk '
      /Stamp slug marker/ { grab=1 }
      grab && /^```bash/ { infence=1; next }
      grab && infence && /^```/ { exit }
      grab && infence { print }
    ' "$SKILL_MD"
  }
  ```
  Substitute placeholders with bash global pattern-replacement (`${VAR//pattern/repl}`, bash-3.2-safe), write to
  a temp script, execute with `bash`:
  ```bash
  RAW="$(extract_slug_stamp)"
  CMD="${RAW//<project-root>/$FIXTURE_DIR}"
  CMD="${CMD//<topic-slug>/test-topic-slug}"
  printf '%s\n' "$CMD" > "$TMP/stamp-cmd.sh"
  bash "$TMP/stamp-cmd.sh"
  ```
- **Per-task checkpoint (three checks, all must pass before moving to the next task):**
  1. `bash -n staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` (and, once modified,
     `bash -n staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh`).
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' <changed-file>` — must be empty, for every file
     touched this task (bash 3.2 / BSD-safety gate, same idiom as ADR-0024/ADR-0026's plans).
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay green (this plan adds zero PAIRS
     entries; the new test file, like its two predecessors, gets none — ADR-0027 §2.6).

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verify, do not assume from the ADR):
  `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` → 6/6 green (this is the repo's
  own already-TOFU-trusted `.claude/test-cmd`).
- Writes are confined to: `staging/plugin/skills/concept-to-code/SKILL.md`,
  `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh`,
  `staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` (new file),
  `.github/workflows/docs-ci.yml`, `SPEC.md` (checkbox updates, final task), `docs/architecture/`,
  `docs/superpowers/plans/` (already written by this ADR/plan pass).
- Do not touch: `staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh` (zero pairs need to
  change — ADR-0027 §2.4, verify with the exact pair-count check in Task 4's checkpoint), `staging/sync-to-claude.sh`
  (no PAIRS changes needed, ADR-0027 §2.6), `staging/plugin/skills/concept-to-code/tests/{run-tests.sh,
  smoke-e2e.sh,agent-notes-roundtrip.sh}` (target deployed `$HOME/.claude/...` by design — ADR-0027 §1 baseline —
  do not add assertions there for this issue), `docs/RUNBOOK.md` / `docs/RUNBOOK-nightly-autopilot.md` (confirmed
  zero `concept-to-code` mentions in either during planning, no edit needed), any file under `~/.claude`.
- `manifest-validate.sh` edits are scoped exactly to invariant 7 (lines ~108-119 of the current file): add one
  `chain_path_val` computation immediately before it, wrap the existing three `fail` checks in a `case`
  statement. Do **not** touch invariant 9's own, separate, pre-existing `chain_path_val` computation four
  invariants later — leave it exactly as-is, duplicate computation and all (ADR-0027 §3.3 — issue #32 is
  concurrently editing this same script's other invariants; touching invariant 9 at all is out of scope here).
- `SKILL.md` edits are scoped exactly to: lines ~100-127 (§2 Form A Gate 0/0b + old step 9), line ~887 (§4 Step
  E1's opening sentence, one-line wording only), lines ~1117-1120 (§5 Gate 0 click handlers), line ~1187 (Gate 0d
  autopilot bracket), lines ~819-821 (Step 7 push trigger condition + guard sentence), lines ~1465-1501 (Gate 2b
  autopilot bracket + TRUSTED check), lines ~943-947 (Gate E3 `Commit later`/`Abort` split), lines ~270-274 (slug
  stamp command). Do **not** touch: `manifest-transition.sh`'s legal-pair table (no pairs need to change), the
  "44 total — 26/6/12" summary line (`SKILL.md:213` — confirmed already wrong independent of this plan; deferred
  to issue #32, ADR-0027 §3.5), Hybrid's Gate H3 `Abort` line (`SKILL.md:1050` — ADR-0027 §3.4), the interactive
  Q4 "Commit and push to remote" option text (`SKILL.md:1271-1272` — a legitimate human choice, unrelated to the
  autopilot bug).

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/prep.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` → exit 0, unchanged PASS count throughout this
  plan (no new PAIRS entries added at any point).
- `bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` → exit 0 (untouched by this plan;
  re-confirm after every task purely as a collision canary).
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing under `~/.claude` is
  ever touched.

---

## Task 1 — RED: Section A (Finding 1, slug stamp) — static anchors + non-regression correctness proof

**Files created:**
- `staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` (scaffold: shebang, header comment
  naming all four sections up front, path derivation per "Fixture and path conventions," PASS/FAIL idiom, Section
  A's 3 tests).

**Contract:**
- **A1 (static, genuine RED).** `grep -F 'a\\n**Topic slug:**' "$SKILL_MD"` finds **no** match. **Expected now
  (RED):** it matches — the old GNU sed one-liner (`sed -i.bak '/^# /a\\n**Topic slug:** <topic-slug>' ...`) is
  still present verbatim.
- **A2 (static, genuine RED).** `grep -F 'awk -v slug=' "$SKILL_MD"` finds a match. **Expected now (RED):** no
  match — the awk replacement has not been written yet.
- **A3 (dynamic, non-regression/correctness companion — expected already passing).** Build a fixture
  `FIXTURE_DIR="$TMP/a3"` (`mkdir -p`), write `printf '# Some Feature Title\n\nBody text.\n' >
  "$FIXTURE_DIR/SPEC.md"`. Use the `extract_slug_stamp` helper (Fixture conventions) to pull the current bash
  block, substitute `<project-root>` → `$FIXTURE_DIR`, `<topic-slug>` → `test-topic-slug`, execute. Assert: exit
  `0`; `grep -q '\*\*Topic slug:\*\* test-topic-slug' "$FIXTURE_DIR/SPEC.md"`; the marker line immediately follows
  a blank line that immediately follows the `# Some Feature Title` line (`awk 'NR==1,NR==3' "$FIXTURE_DIR/SPEC.md"`
  equals the three expected lines, checked with an explicit 3-line comparison, not a loose substring grep).
  Re-run the **same** extracted-and-substituted command a second time against the now-stamped file; assert the
  file is byte-for-byte unchanged (idempotency). **Expected now: already passing.** State explicitly in the
  test's own comments why: `ubuntu-latest`'s GNU sed accepts and correctly processes the current one-line `a\`
  form (a documented GNU extension), so the platform-specific BSD failure this finding is about does not
  reproduce on this runner — A1/A2 are this finding's true RED, A3 is forward-correctness/idempotency coverage,
  verified for the BSD side by hand during planning (ADR-0027 §2.1), not by this CI job.

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh   # empty
bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh   # expect Section A: PASS=1 FAIL=2 (A3 passing; A1, A2 red)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                     # unchanged, exit 0
```

---

## Task 2 — GREEN: Finding 1 fix (slug stamp, `SKILL.md:270-274`)

**Files modified:**
- `staging/plugin/skills/concept-to-code/SKILL.md`

**Contract — exact replacement, the fenced bash block only (heading text "Stamp slug marker (idempotent)" stays,
so A3's extraction anchor keeps working unmodified):**
```bash
grep -q '\*\*Topic slug:\*\*' "<project-root>/SPEC.md" || {
  cp "<project-root>/SPEC.md" "<project-root>/SPEC.md.bak" &&
  awk -v slug="<topic-slug>" '
    { print }
    !done && /^# / { print ""; print "**Topic slug:** " slug; done=1 }
  ' "<project-root>/SPEC.md" > "<project-root>/SPEC.md.tmp" &&
  mv "<project-root>/SPEC.md.tmp" "<project-root>/SPEC.md"
}
```
Add one short sentence immediately below the block (already-empirically-verified claim, ADR-0027 §2.1): `awk`'s
basic pattern-match/print semantics are POSIX and behave identically across BSD awk (macOS) and GNU/`mawk`
(Ubuntu) — no OS branch needed. Do not add an `if uname == Darwin` branch or any other conditional — the whole
point of this fix is that one command works on both (SPEC's own "Success criteria": "runs the exact command
against a fixture SPEC.md," singular).

**Expected (GREEN):** A1 and A2 both pass; A3 unchanged (was already passing).

**Checkpoint:**
```
bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh   # Section A: PASS=3 FAIL=0
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 3 — RED: Section D (Finding 4, Gate order) — mechanical proofs + one genuine static RED

**Files modified:**
- `staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` (append Section D, 4 tests).

**Contract:**
- **D1 (dynamic, non-regression/mechanical proof — expected already passing).** Fresh fixture/manifest (slug
  `d1-standard`). Patch `chain_path: null` → `chain_path: "standard"`. Run
  `bash "$TRN" "$MD1" gate_0d_scaffolding`; assert exit `0`. Then `bash "$TRN" "$MD1" step_1_interview`; assert
  exit `0`. **Expected now: already passing** — both pairs (`step_0_init,gate_0d_scaffolding` and
  `gate_0d_scaffolding,step_1_interview`) already exist in the unmodified `manifest-transition.sh` (confirmed
  during planning by direct reading, ADR-0027 §1/§2.4). This proves Finding 4's fix needs zero script changes;
  state that explicitly in the test's own comment.
- **D2 (dynamic, same category).** Same shape, slug `d2-express`, `chain_path: "express"`,
  `gate_0d_scaffolding` then `step_e1_plan`. **Expected now: already passing**, same reason.
- **D3 (dynamic, same category).** Same shape, slug `d3-hybrid`, `chain_path: "hybrid"`, `gate_0d_scaffolding`
  then `step_h1_interview`. **Expected now: already passing**, same reason.
- **D4 (static, genuine RED).** `grep -F '`express` → transition `step_0_init → step_e1_plan`' "$SKILL_MD"` finds
  **no** match. **Expected now (RED):** it matches — §2 Form A's fast-path bullet still performs this direct,
  Gate-0b/0c/0d-bypassing transition.

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh
bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh   # Section A: 3/3 green (Task 2 landed); Section D: PASS=3 FAIL=1 (D1-D3 already green, D4 red)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                     # unchanged, exit 0
```

---

## Task 4 — GREEN: Finding 4 fix (Gate order canonicalization) — `SKILL.md` only, zero script changes

**Files modified:**
- `staging/plugin/skills/concept-to-code/SKILL.md`

**Contract — §2 Form A, steps 7-9 (current lines ~100-127):**
- Step 7 (Gate 0): both the fast-path branch and the normal-path `[e]`/`[h]`/`[s]`/`[a]` click handlers stop
  performing any `manifest-transition.sh` call. Every branch (fast-path `express`/`hybrid`/`standard`, and
  normal-path `[e]`/`[h]`/`[s]`) sets `chain_path` only, then falls through uniformly to "proceed to step 8
  below." `[a]` still aborts the chain (unchanged).
- Step 8 (Gate 0b): unchanged logic; its `[y]`/`[n]`/silent branches now say "proceed to step 8b" instead of
  implicitly ending the described sequence.
- **New step 8b (Gate 0c):** one short pointer — "See §5 Gate 0c for the full trigger logic and display; proceed
  to step 8c once it resolves (silently or via click)." Do not duplicate §5 Gate 0c's content into §2.
- **New step 8c (Gate 0d):** one short pointer — "See §5 Gate 0d for the full git-auto-detect / license / Xcode /
  commit survey. Gate 0d performs the chain's **single** `current_step` transition out of `step_0_init`:
  `step_0_init → gate_0d_scaffolding`, then immediately `gate_0d_scaffolding → step_1_interview`
  (`chain_path=standard`/null) or `→ step_e1_plan` (express) or `→ step_h1_interview` (hybrid) — see
  `SKILL.md:1326-1329` for the exact transition block, unmodified by this task." Do not duplicate §5 Gate 0d's
  content into §2.
- Old step 9 (the direct `step_0_init → step_1_interview` transition) is **removed**, replaced by one sentence:
  "For `chain_path=standard` with `mode=brownfield`, Step 1 is a no-op (§4 Step 1 already handles this);
  otherwise execution continues in the matching path's own Step 1 definition (§4 Step 1 / Step E1 / Step H1),
  reached via the routing transition in step 8c above."

**Contract — §5 Gate 0 click handlers (current lines ~1117-1120):** `[e]` and `[h]` change from "transition
`step_0_init → step_e1_plan`/`step_h1_interview`. Go to Express/Hybrid path" to "set `chain_path: express`/
`hybrid`. Proceed to step 8 (Gate 0b) in §2 Form A — the path begins after Gate 0d routes to `step_e1_plan`/
`step_h1_interview` (§4 Express/Hybrid)." `[s]` and `[auto]` are unchanged (they already say "proceed to step 8").

**Contract — §4 Step E1's opening sentence (current line ~887):** "Immediately after Gate 0 selects express:" →
"Immediately after Gate 0d routes to `step_e1_plan`:". One line, wording only, state unchanged. §4 Step H1 has no
equivalent phrase — confirmed during planning, no edit.

**Explicitly not modified this task (verify in the checkpoint below):**
`staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh` — every pair the corrected flow uses
already exists.

**Expected (GREEN):** D4 passes; D1-D3 unchanged (were already passing) — Section D fully green, proving the
fix is entirely a documentation/routing-prose correction.

**Checkpoint:**
```
bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh   # Sections A+D: PASS=7 FAIL=0
diff <(git show HEAD:staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh) staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh   # empty — zero diff, confirms no script edit happened
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 5 — RED: Section B (Findings 2+3, autopilot no-unattended-trust / no-unattended-push)

**Files modified:**
- `staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` (append Section B, 4 tests, all
  genuine RED — static text anchors against SKILL.md, no subprocess execution).

**Contract:**
- **B1.** `grep -F '"Approve" → run `approve-test-cmd.sh` and proceed' "$SKILL_MD"` finds **no** match. **Expected
  now (RED):** matches — Gate 2b's autopilot bracket still calls `approve-test-cmd.sh` unconditionally.
- **B2.** `grep -F 'NOT_TRUSTED → autopilot must never establish trust unattended' "$SKILL_MD"` finds a match.
  **Expected now (RED):** no match — the TRUSTED/NOT_TRUSTED probe has not been written yet.
- **B3.** `grep -F '`_git_remote` non-empty → `initial_commit_push: "push"`' "$SKILL_MD"` finds **no** match.
  **Expected now (RED):** matches — Gate 0d's autopilot bracket still conditions push on remote presence. (This
  compound anchor is deliberate, not a bare `initial_commit_push: "push"` substring — that bare string also
  legitimately appears in the interactive Q4 "Commit and push to remote" option, `SKILL.md:1271-1272`, which must
  stay untouched; a looser anchor would never be satisfiable. ADR-0027 §2.6.)
- **B4.** `grep -F 'AND manifest.autopilot != true' "$SKILL_MD"` finds a match. **Expected now (RED):** no match —
  Step 7's push block has no autopilot guard in its trigger condition yet.

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh
bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh   # Sections A+D: 7/7 green; Section B: PASS=0 FAIL=4 (all red)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                     # unchanged, exit 0
```

---

## Task 6 — GREEN: Findings 2+3 fix (Gate 2b TOFU check, Gate 0d always-commit, Step 7 autopilot guard)

**Files modified:**
- `staging/plugin/skills/concept-to-code/SKILL.md`

**Contract — Gate 2b autopilot bracket (current line ~1501), full replacement:** the bracket must (a) never call
`approve-test-cmd.sh` unconditionally, (b) probe pre-existing trust read-only using the **same** mechanism as the
Form-B resume-path guard (`SKILL.md:152-158`, unmodified — `shasum -a 256` of `.claude/test-cmd` compared against
`~/.claude/state/stop-gate/trust`), (c) on `TRUSTED`, proceed silently to `step_3_project_memory` (reading
existing trust is not granting it), (d) on `NOT_TRUSTED`, do exactly what the interactive "Skip" branch two lines
above already does (`manifest.test_cmd_placeholder = true`, transition to `step_3_project_memory`) and emit the
literal phrase `NOT_TRUSTED → autopilot must never establish trust unattended` somewhere in the bracket text (this
exact phrase is Task 5's B2 anchor — use it verbatim, do not paraphrase), (e) contain no `approve-test-cmd.sh`
invocation on either branch (B1's anchor phrase must not reappear anywhere in the bracket). No new manifest schema
field (ADR-0027 §3.1) — reuse `test_cmd_placeholder` only.

**Contract — Gate 0d autopilot bracket (current line ~1187):** remove the `_git_remote`-conditional entirely.
Replace with: always `initial_commit_push: "commit"`, regardless of remote state, with a one-clause reason
("autopilot never pushes unattended; the nightly opt-in publishes separately, after a local commit, never through
this field"). B3's anchor phrase (`` `_git_remote` non-empty → `initial_commit_push: "push"` ``) must not appear
anywhere in the bracket after this edit.

**Contract — Step 7 push trigger (current lines ~819-821):** change the heading to "**Post-commit push (conditional
on `manifest.initial_commit_push = "push"` AND `manifest.autopilot != true`):**", add one guard sentence
immediately below it stating the block is skipped unconditionally when `autopilot=true` (containing the literal
phrase `AND manifest.autopilot != true` — Task 5's B4 anchor, use verbatim) and one sentence on why no
nightly-opt-in exception is threaded through here (nightly's publish runs entirely outside this block —
`project-conductor`'s `publish-feature.sh`, ADR-0027 §1/Finding-3-Context, re-confirmed by `grep -n -i "nightly"
SKILL.md` returning nothing both before and after this task). Change the actual trigger sentence itself
("After the commit skill completes successfully, if...") to require both conditions.

**Expected (GREEN):** B1-B4 all pass.

**Checkpoint:**
```
bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh   # Sections A+D+B: PASS=11 FAIL=0
grep -n -i "nightly" staging/plugin/skills/concept-to-code/SKILL.md   # still zero matches — confirms no nightly-specific branch was introduced
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 7 — RED: Section C (Finding 5, invariant 7 conditional + Gate E3 abort split)

**Files modified:**
- `staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` (append Section C, 6 tests).

**Contract:**
- **C1 (dynamic, genuine RED).** Fresh fixture (slug `c1-express`). Patch `chain_path` → `"express"`, `status` →
  `"completed"` (leave all `artifacts.*` null — realistic for Express, which never sets any of them). Run
  `bash "$VAL" "$M1"`; assert exit `0`. **Expected now (RED):** invariant 7 is unconditional today; exits
  non-zero.
- **C2 (dynamic, non-regression companion — expected already passing).** Fresh fixture (slug `c2-standard`).
  Patch `status` → `"completed"` only (`chain_path` stays `null`, the legacy/Standard default). Run
  `bash "$VAL" "$M2"`; assert exit **non-zero**. **Expected now: already passing** — invariant 7 already
  (correctly) rejects this. State explicitly this must stay failing after Task 8 too — it is the guard against
  Task 8 over-relaxing the Standard path.
- **C3 (dynamic, genuine RED).** Fresh fixture (slug `c3-hybrid`). Patch `chain_path` → `"hybrid"`, `status` →
  `"completed"`, `artifacts.spec` → `"/tmp/SPEC.md"` (quoted absolute path; `adr`/`plan` stay null — realistic for
  Hybrid). Run `bash "$VAL" "$M3"`; assert exit `0`. **Expected now (RED):** invariant 7 is unconditional today;
  exits non-zero (requires `adr`/`plan` too).
- **C4 (dynamic, non-regression companion — expected already passing).** Fresh fixture (slug
  `c4-hybrid-nospec`). Patch `chain_path` → `"hybrid"`, `status` → `"completed"` (`artifacts.spec` stays null
  too, unlike C3). Run `bash "$VAL" "$M4"`; assert exit **non-zero**. **Expected now: already passing** (and must
  stay failing after Task 8) — proves the Hybrid conditional carve-out is narrower than Express's blanket skip:
  Hybrid still requires `spec`.
- **C5 (static, genuine RED).** `` grep -F '`Commit later` / `Abort`:' "$SKILL_MD" `` finds **no** match.
  **Expected now (RED):** it matches — Gate E3 still shares one label/transition block for both options.
- **C6 (dynamic, non-regression/mechanical proof — expected already passing).** Fresh fixture (slug `c6-abort`,
  no `chain_path`/`status` patches needed). Run `bash "$TRN" "$M6" aborted aborted"`; assert exit `0`. Assert
  `grep -q '^status: "aborted"$' "$M6"`. Run `bash "$VAL" "$M6"`; assert exit `0`. **Expected now: already
  passing** — `manifest-transition.sh`'s "any state → `aborted` is unconditionally legal" rule
  (`manifest-transition.sh:47`) needs no change, and a fresh manifest transitioned straight to `aborted` triggers
  no invariant (7 only fires on `completed`; 8 only on `failed`). State explicitly this proves Task 8's SKILL.md
  fix has a real, already-legal call to route `Abort` to.

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh
bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh   # Sections A+D+B: 11/11 green; Section C: PASS=3 FAIL=3 (C2,C4,C6 already green; C1,C3,C5 red)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                     # unchanged, exit 0
```

---

## Task 8 — GREEN: Finding 5 fix (`manifest-validate.sh` invariant 7 + `SKILL.md` Gate E3 split)

**Files modified:**
- `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh`
- `staging/plugin/skills/concept-to-code/SKILL.md`

**Contract (`manifest-validate.sh`), exact insertion at invariant 7 (current lines ~108-119), invariant 9 (current
lines ~129-140) left completely untouched:**
```bash
chain_path_val="$(grep '^chain_path:' "$MANIFEST" | sed 's/^chain_path: *//;s/"//g' | head -1)"
if [ "$status_val" = "completed" ]; then
  case "$chain_path_val" in
    express)
      : # no artifact files expected for the express path; invariant 7 does not apply
      ;;
    hybrid)
      if ! grep -Eq '^  spec: "/[^"]+"$' "$MANIFEST"; then
        fail "status=completed (chain_path=hybrid) but artifacts.spec is null or not a quoted absolute path"
      fi
      ;;
    *)
      if ! grep -Eq '^  spec: "/[^"]+"$' "$MANIFEST"; then
        fail "status=completed but artifacts.spec is null or not a quoted absolute path"
      fi
      if ! grep -Eq '^  adr: "/[^"]+"$' "$MANIFEST"; then
        fail "status=completed but artifacts.adr is null or not a quoted absolute path"
      fi
      if ! grep -Eq '^  plan: "/[^"]+"$' "$MANIFEST"; then
        fail "status=completed but artifacts.plan is null or not a quoted absolute path"
      fi
      ;;
  esac
fi
```
The `*)` (default) arm's three `fail` messages are byte-identical to today's unconditional checks — this is a
wrap, not a reword, so the Standard/legacy path's behavior and error text are unchanged (C2 must keep failing with
the same message it fails with today).

**Contract (`SKILL.md` Gate E3, current lines ~943-947):** split the shared block into two:
```
`Commit later`:
```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed
```
No commit skill invoked. Implementation is complete; the user will commit manually later.

`Abort`:
```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> aborted aborted
```
No commit skill invoked. Matches the option's own description ("Stop here. Changes remain in the working
tree.") — an abandonment, not a completion.
```
No `manifest-transition.sh` change needed — confirm with the same zero-diff check as Task 4. Hybrid's Gate H3
`Abort` line (`SKILL.md:1050`) is explicitly **not** touched (ADR-0027 §3.4).

**Expected (GREEN):** C1, C3, C5 pass; C2, C4, C6 unchanged (were already passing).

**Checkpoint:**
```
bash -n staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh   # empty
bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh   # Sections A+D+B+C: PASS=17 FAIL=0 (full file green)
diff <(git show HEAD:staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh) staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh   # empty
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 9 — GREEN: CI wiring

**Files modified:**
- `.github/workflows/docs-ci.yml` — append `concept-to-code-bsd-autopilot-gates` to the `shell-tests` job's
  `for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety` list
  (line ~44), becoming `for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness
  clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates; do`.

No change needed to `.claude/test-cmd` — its existing glob (`staging/plugin/scripts/tests/*.test.sh`) already
picks up the new file automatically (confirmed during planning by reading its current, single-line, unchanged
content — ADR-0027 §2.6).

**Checkpoint:**
```
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # local test-cmd verbatim: 7/7 green
grep -n 'concept-to-code-bsd-autopilot-gates' .github/workflows/docs-ci.yml     # exactly one match, inside the shell-tests `for t in ...` line
```

---

## Task 10 — Final verification, bash-safety sweep, SPEC checkbox update, report

**Files modified:**
- `SPEC.md` — check off the success-criteria boxes that are genuinely satisfied; leave any unchecked and explain
  in the report if one is not (expect all 5 checked: BSD slug stamp; no unattended approve-test-cmd.sh/push;
  express-completed-null-artifacts passes while standard-null still fails; transition-pair legality — see the
  explicit reinterpretation in ADR-0027 §3.5 for why the "44 total" arithmetic itself stays unchecked/deferred if
  the box is worded that specifically; zero `~/.claude` files touched).

**Verify (full, repo-wide):**
```
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done    # local test-cmd, 7/7 green
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                      # unchanged, exit 0
for f in staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh \
         staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh; do
  bash -n "$f" || exit 1
  grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' "$f" && exit 1
  grep -nF '<<<' "$f" && exit 1
done
echo "bash 3.2 / BSD safety: clean"
diff <(git show HEAD:staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh) staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh   # empty, confirms zero script edits across the whole plan
grep -n -i "nightly" staging/plugin/skills/concept-to-code/SKILL.md              # still zero matches
npx --yes markdownlint-cli2 "staging/plugin/skills/concept-to-code/SKILL.md"     # expect exit 0
git status   # confirm change set matches Pre-flight "writes are confined to" list; nothing under ~/.claude
```

**Report to dispatcher:**
- ADR path, spec path, plan path.
- New test file's final tally (expect `PASS=17 FAIL=0`, sections A=3, B=4, C=6, D=4).
- Full local `test-cmd` glob result (7/7 files green) pasted verbatim.
- Explicit confirmation `manifest-transition.sh` has a zero-line diff from `HEAD` (Finding 4 and the Gate-E3-abort
  half of Finding 5 needed no script pair changes — the whole point of §2.4/§2.5's design).
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted during this session.
- Explicit flag: the *deployed* `concept-to-code` copy at `~/.claude/skills/concept-to-code/` still contains all
  five defects, including the P1, until a human runs `sync-to-claude.sh --apply`.
- Explicit flag for the human reviewer: Gate 0b/0c/0d now fire unconditionally for Express and Hybrid chains,
  where before they never fired at all — a real, user-visible behavior change for those two paths, not merely an
  invisible bug fix (ADR-0027 §4/Negative). Call this out prominently, do not bury it in a routine "done" message.
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — B3's compound anchor is brittle to paraphrasing.** If Task 6's rewrite of the Gate 0d autopilot
  bracket happens to retain the substring `initial_commit_push: "push"` in some other clause (e.g., an
  explanatory aside quoting the old behavior for contrast), B3 could false-negative (report "fixed" when the
  literal old compound phrase is merely reworded around). **Mitigation:** Task 6's contract states the exact
  clause to remove and gives the exact anchor B3 checks — write the replacement text to not contain that specific
  compound substring anywhere, and re-read the full bracket line after editing before considering Task 6 done.
- **Risk B — Section D's "already passing" tests silently mask a real script defect if `manifest-init.sh`'s
  default `chain_path: null` line ever changes.** All three of D1-D3's fixtures depend on the `sed
  's/^chain_path: null$/chain_path: "..."/'` patch matching literally — if a future, unrelated change makes
  `manifest-init.sh` emit `chain_path: null # comment` or similar, the patch silently no-ops and the fixture
  stays `chain_path: null`, changing what D1-D3 actually test without changing their PASS/FAIL outcome (since
  `null` also validates against the `*)` default case). **Mitigation:** none needed for this plan — the exact
  literal in `manifest-init.sh:65` was confirmed during planning; flagged here only so a future contributor
  investigating an unexpected D1-D3 result checks this first.
- **Risk C — Gate 0b/0c/0d newly firing for Express/Hybrid could surprise a human mid-flight if this lands
  without the Task 10 report's explicit callout.** Not a defect in this plan's execution, but a real behavior
  change this plan cannot itself soften (ADR-0027 §2.4/§3.2 already chose this over the narrower alternative).
  **Mitigation:** Task 10's report requirement to flag this prominently is the backstop.
- **Risk D — scope creep into Hybrid's Gate H3 `Abort` line, the "44 total" summary arithmetic, or
  `manifest-transition.sh`'s legal-pair table.** All three are tempting "fix while you're in there" edits with
  low individual risk but real collision risk with issue #32's concurrent, same-file work. **Mitigation:**
  Pre-flight constraints and ADR-0027 §3.4/§3.5/§2.4 are explicit that these are deliberately out of scope; the
  zero-diff `manifest-transition.sh` check in Tasks 4, 8, and 10 is the automated backstop for the third; `git
  status` in Task 10 is the backstop for the first two.
- **Risk E — the deployed skill keeps all five defects, including the P1, until sync.** Not a defect in this
  plan's own execution, but a real operational risk this plan cannot itself close (staging-only scope is this
  roadmap's established, unchanged convention). **Mitigation:** flagged with explicit priority in Task 10's
  report, matching ADR-0026's precedent for its own P1 finding.

## HITL gates

- No HITL gate inside this plan itself (auto mode; every edit is additive/corrective text or a conditional-guard
  addition, no destructive git operations, no `manifest-transition.sh`/`manifest-validate.sh` change is ever
  *executed* against this repository's own real manifests by this plan — every live invocation in Tasks 1-8
  targets a disposable, isolated `mktemp -d` fixture).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push remain
  human-gated, as does the follow-up `sync-to-claude.sh --apply` that would actually deploy these fixes (Risk E)
  — that sync is explicitly out of this plan's scope and requires its own separate human action.
- No DB schema change, no permanent deletion, no production migration in this plan — none of the invariant HITL
  triggers beyond the standard commit/push gate apply here.
