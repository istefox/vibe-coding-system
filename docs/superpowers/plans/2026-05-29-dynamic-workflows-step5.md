# Dynamic Workflows — Step 5 Replacement (TDD Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement task-by-task. Steps use
> checkboxes (`- [ ]`).

**Changelog:**
- v1.0 (2026-05-29): initial — TDD plan derived from `ADR-0016-dynamic-workflows-step5.md`
  and `SPEC.md`. 7 tasks: T1 smoke test procedure (user-run), T2 SKILL.md Step 5 workflow
  dispatch, T3 SKILL.md step5-report.json schema + read contract, T4 SKILL.md smoke test
  gate, T5 run-tests.sh structural anchors (PASS >= 32), T6 manifest-init.sh additive fields,
  T7 full harness verification (optional verification pass).

**Goal:** replace the Agent-tool batch dispatch in Step 5 of the `concept-to-code` chain with
a keyword-triggered Dynamic Workflows dispatch + `step5-report.json` file handoff. Retain
the current batch dispatch as the fallback path. Add a smoke test prerequisite gate.

**Architecture:** Step 5 section of `~/.claude/skills/concept-to-code/SKILL.md` is rewritten
to: (1) check `hook_verified` in the manifest before dispatch, (2) use "workflow" keyword in
the dispatch prompt, (3) define the `step5-report.json` write contract for the final workflow
subagent, (4) define the orchestrator read contract and fallback path. `manifest-init.sh` gains
two additive fields. The test harness gains 4 structural anchors.

**ADR:** `docs/architecture/ADR-0016-dynamic-workflows-step5.md` (Proposed 2026-05-29).
**SPEC:** `/Users/stefanoferri/developer/vibe-coding-system/SPEC.md`.

---

## Environment notes (read first)

- **Implementation target: `~/.claude/skills/concept-to-code/` (NOT the vibe-coding-system
  doc repo).** The doc repo is the source of ADR and plan only. Never edit source files in the
  doc repo.
- **No git in `~/.claude/`.** Checkpoint per task = harness green + report. No commit step.
- **Bash 3.2-clean for all script changes.** No assoc arrays, mapfile, `${v^^}`, process
  substitution, here-strings `<<<`. Use `grep -Eq`, `case`, `[ -f ]`, `ok`/`bad` helpers.
- **No changes to:** `coder.md`, all hooks (pattern-enforce, stop-gate, db-backup-guardrail),
  `settings.json`, Gates 1-5 in SKILL.md, `manifest-transition.sh`, `manifest-validate.sh`,
  `gate0-detect.sh`, all other skills.
- **Anchor preservation HARD.** Baseline: `concept-to-code PASS=32 FAIL=0`. Do not regress it.
  New anchors: +4 (T5) → target `PASS=36 FAIL=0`. All other harnesses unchanged.
- **Backup pre-edit of critical files:** `cp` with suffix `.bak-2026-05-29` for
  `concept-to-code/SKILL.md` and `manifest-init.sh` before modifying them (T2 and T6).
- **Manifest schema: no version bump.** `hook_verified` and `step5_mode` are additive fields.
  The validator accepts unknown fields in schema 1.1 manifests. Do not touch `manifest-validate.sh`.
- **Smoke test (T1) is user-run.** The chain cannot auto-verify hook firing. T1 documents the
  procedure. T4 adds the gate that blocks dispatch until the user records the result.
- **Testability honesty (ADR-0016 Neutral).** The harness verifies structural anchors
  (text present in SKILL.md, fields present in manifest-init.sh output). Runtime verification
  of hook propagation inside workflow subagents is a pilot-only validation — not reproducible
  headless. Do not claim harness coverage that does not exist.

## File structure

- Modify: `~/.claude/skills/concept-to-code/SKILL.md` — Step 5 section rewrite (T2, T3, T4).
  Backup before editing.
- Modify: `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` — add two additive
  fields (T6). Backup before editing.
- Modify: `~/.claude/skills/concept-to-code/tests/run-tests.sh` — add 4 structural anchors (T5).

Unchanged (HARD): all agents (`coder.md`, `architect.md`, etc.), all hooks, `settings.json`,
`.mcp.json`, `manifest-validate.sh`, `manifest-transition.sh`, `gate0-detect.sh`, all other
skills, the ADR and plan files themselves (read-only from the coder's perspective).

**Harness PASS delta expected:**
- `concept-to-code`: 32 → **36** (+4 structural anchors, T5)
- All other harnesses: **unchanged**

---

### Task 1 — Smoke test procedure (user-run, documented in SKILL.md)

**Nature:** documentation task — defines the smoke test procedure that a human user must run
once to verify hook propagation inside Dynamic Workflows subagents. This task does not modify
any file yet; it produces the specification used by T2/T4.

**No file changes in this task.** This is a design clarification step.

**Smoke test procedure (to be embedded verbatim in SKILL.md at T2/T4):**

```
SMOKE TEST — Dynamic Workflows hook verification
Run ONCE per environment before first production use.
Record result as hook_verified: true|false in the manifest.

Steps:
  1. Create a sandbox: mkdir /tmp/wf-smoke-test && cd /tmp/wf-smoke-test
     git init && echo "hello" > test.txt && git add . && git commit -m "init"
  2. In the same Claude Code session where you will run the chain, send this prompt:
     "Use a workflow to edit /tmp/wf-smoke-test/test.txt: append the line 'smoke test ok'."
  3. Observe the terminal output during the workflow run.
  4. Look for: a line beginning with "PATTERN:" emitted before the Edit call.
     - If you see PATTERN: → hooks fire inside workflow subagents.
       Record hook_verified: true. Workflow path is available.
     - If you do NOT see PATTERN: → hooks do NOT fire inside workflow subagents.
       Record hook_verified: false. Workflow path is blocked. Fallback activates.
  5. Clean up: rm -rf /tmp/wf-smoke-test
```

**Rationale:** the pattern-enforce hook emits a `PATTERN:` check to stderr before every `Edit`
or `Write`. This is observable in the terminal during any subagent run. The smoke test exploits
this as a proxy for "hooks fire inside workflow subagents".

- [ ] Step 1: review the procedure above. Verify it matches the current pattern-enforce hook
      behavior (check `~/.claude/hooks/` for the hook file name and its stderr output).
- [ ] Step 2: record the procedure. It will be embedded by T4 in SKILL.md.
- [ ] Step 3: checkpoint.

**Estimate:** 10 min.

---

### Task 2 — SKILL.md Step 5: replace batch dispatch with workflow dispatch + fallback

**Files:**
- Modify: `~/.claude/skills/concept-to-code/SKILL.md` (backup first: `.bak-2026-05-29`)

**Context:** the current Step 5 section (§4 Step 5 in SKILL.md) contains the batch-dispatch
policy and the single-batch template. Replace the dispatch instructions with the workflow
dispatch path, retaining the batch template as a clearly labelled fallback.

**Green phase — edit:**

1. **Backup:** `cp ~/.claude/skills/concept-to-code/SKILL.md ~/.claude/skills/concept-to-code/SKILL.md.bak-2026-05-29`

2. **Replace the Step 5 section header and dispatch policy** (the block from "### Step 5" to
   the end of the single batch dispatch template) with the following structure:

   ```
   ### Step 5 — Implementation (dispatch coder, post-resume)

   **Dispatch mode selection:**
   - If `manifest.hook_verified = true`: use Workflow dispatch path (below).
   - If `manifest.hook_verified = false` or `null`: present smoke test gate (see "Smoke test
     gate" block below) and STOP until user records result.
   - If Dynamic Workflows is unavailable or the keyword does not trigger script generation:
     fall back to Agent-tool batch dispatch (see "Fallback — Agent-tool batch dispatch" below).

   **Pre-dispatch: worktree isolation check (run ONCE before any dispatch):**
   [keep existing git rev-parse block unchanged]

   **Workflow dispatch path (hook_verified = true):**

   Step 5 dispatch prompt (send as a single message to the session):
   """
   Use a workflow to dispatch the following coder tasks in parallel.
   Read plan at <manifest.artifacts.plan>.
   Read ADR at <manifest.artifacts.adr>.
   Read SPEC.md at <manifest.artifacts.spec>.
   Read project CLAUDE.md at <manifest.artifacts.project_claude_md> (if not null).

   Dispatch one coder subagent per task group. Use your Pre-flight Pattern Classifier
   (ADR-0001) for every Edit operation. Auto mode active. No intermediate HITL.

   After all tasks complete, the final subagent MUST write
   <project_root>/.claude/step5-report.json with the schema defined in the
   step5-report.json contract section (see SKILL.md §4 Step 5 contract).

   [IF manifest.anonymize=true — add this block, otherwise omit:]
   Anonymize mode: ON (ADR-0011). [same anonymize block as current template]
   """

   After the workflow completes:
   1. Read `<project_root>/.claude/step5-report.json`.
   2. If the file is absent → fall back to `git diff + test run` directly (do NOT re-dispatch).
   3. If `tasks_failed` is non-empty OR `test_result` is `red` → failure signal. Present to
      user; do NOT transition to step_6_review without user acknowledgment.
   4. If all tasks passed and test_result is `green` or `n/a` → transition to step_6_review.
      Present Gate 5.

   Set `step5_mode: "workflow"` in the manifest (via manifest-set-flag.sh or direct bash
   sed substitution on the additive field — NOT via Edit tool).

   **Fallback — Agent-tool batch dispatch (hook_verified = false or workflow unavailable):**
   [keep existing batch-dispatch policy and single-batch template VERBATIM, labelled "Fallback"]

   Set `step5_mode: "agent_batch"` in the manifest when the fallback activates.
   ```

**Constraints:** preserve all existing text in the batch-dispatch section unchanged. The only
structural change is demoting it to "Fallback". Do NOT change Gates 1-5, the worktree check,
or any section outside Step 5.

- [ ] Step 1: backup SKILL.md.
- [ ] Step 2: edit Step 5 section — add workflow dispatch path above the existing fallback
      content. Label the existing batch-dispatch as "Fallback". (PATTERN: MODIFY)
- [ ] Step 3: verify the word "workflow" appears in the new dispatch prompt template.
- [ ] Step 4: verify the fallback label and batch-dispatch text are still present.
- [ ] Step 5: checkpoint.

**Verify command:**
```bash
grep -c 'workflow' ~/.claude/skills/concept-to-code/SKILL.md
grep -c 'Fallback' ~/.claude/skills/concept-to-code/SKILL.md
grep -c 'step5_mode' ~/.claude/skills/concept-to-code/SKILL.md
grep -c 'hook_verified' ~/.claude/skills/concept-to-code/SKILL.md
```
Expected: each >= 1. Fallback and batch-dispatch text still present.

**Estimate:** 35 min.

---

### Task 3 — SKILL.md Step 5: add step5-report.json schema + orchestrator read contract

**Files:**
- Modify: `~/.claude/skills/concept-to-code/SKILL.md` (already backed up at T2)

**Context:** T2 added a reference to the `step5-report.json` schema. T3 adds the schema
definition and the orchestrator read contract as a named subsection within Step 5 in SKILL.md.

**Green phase — edit:**

Add the following block immediately after the workflow dispatch prompt template in the Step 5
section (before the Fallback section):

```markdown
#### step5-report.json schema and orchestrator read contract

The final workflow subagent writes this file to `<project_root>/.claude/step5-report.json`.
The orchestrator reads it after the workflow exits.

Schema (JSON):
```json
{
  "step5_mode": "workflow",
  "workflow_completed_at": "<ISO8601 timestamp>",
  "tasks_completed": [1, 2, 3],
  "tasks_failed": [],
  "files_modified": [
    { "path": "<absolute path>", "operation": "edit|create|delete" }
  ],
  "test_result": "green | red | n/a",
  "test_output_tail": "<last 20 lines of test output or empty string>",
  "harness_deltas": "PASS=N FAIL=0 (delta from baseline, or n/a)",
  "errors": []
}
```

**Orchestrator read contract:**
- Stale detection: compare `workflow_completed_at` against `manifest.last_updated_at`.
  If `workflow_completed_at` is older than `last_updated_at`, the file is from a prior run.
  Ignore it and use `git diff + test run` directly.
- `tasks_failed` non-empty → failure signal.
- `test_result: "red"` → failure signal.
- Failure signal behavior: present to user, do NOT auto-transition to step_6_review.
- `step5-report.json` absent → git diff + test run directly (not a blocking error).
- Schema validation: check that `step5_mode`, `tasks_completed`, and `workflow_completed_at`
  fields are present. If any are missing, treat the file as malformed → git diff fallback.
```

- [ ] Step 1: add the schema block after the workflow dispatch prompt in Step 5. (PATTERN: ADD)
- [ ] Step 2: verify the JSON schema contains all required fields.
- [ ] Step 3: verify stale detection logic and failure signal behavior are documented.
- [ ] Step 4: checkpoint.

**Verify command:**
```bash
grep -c 'step5-report.json' ~/.claude/skills/concept-to-code/SKILL.md
grep -c 'tasks_failed' ~/.claude/skills/concept-to-code/SKILL.md
grep -c 'workflow_completed_at' ~/.claude/skills/concept-to-code/SKILL.md
grep -c 'stale' ~/.claude/skills/concept-to-code/SKILL.md
```
Expected: each >= 1.

**Estimate:** 20 min.

---

### Task 4 — SKILL.md Step 5: add smoke test pre-dispatch gate

**Files:**
- Modify: `~/.claude/skills/concept-to-code/SKILL.md` (already backed up at T2)

**Context:** T2 references the smoke test gate. T4 adds the gate definition and the smoke test
procedure verbatim as a named block within Step 5 in SKILL.md.

**Green phase — edit:**

Add the following block immediately before the "Workflow dispatch path" section in Step 5
(after "Dispatch mode selection"):

```markdown
#### Smoke test gate (pre-dispatch, blocks if hook_verified = false)

If `manifest.hook_verified = false` or the field is absent from the manifest:

Display to user:
```
============================================================
concept-to-code · Step 5 · SMOKE TEST REQUIRED
============================================================
Dynamic Workflows hook behavior in this environment has not been verified.
Run the smoke test below before this chain can dispatch via workflow.

SMOKE TEST PROCEDURE:
  1. In this Claude Code session, run:
     mkdir -p /tmp/wf-smoke-test && cd /tmp/wf-smoke-test
     git init && echo "hello" > test.txt && git add . && git commit -m "init"
  2. Send this prompt: "Use a workflow to edit /tmp/wf-smoke-test/test.txt:
     append the line 'smoke test ok'."
  3. Watch the terminal during the workflow run.
  4. Look for a line beginning with "PATTERN:" before the Edit call.
     - Seen PATTERN: → hooks fire. Report: hook_verified = true
     - Not seen PATTERN: → hooks do NOT fire. Report: hook_verified = false
  5. rm -rf /tmp/wf-smoke-test

IMPORTANT: if hook_verified = false, the workflow path is blocked.
The chain will use the Agent-tool batch dispatch (fallback).
============================================================
```

After user reports result:
- `hook_verified = true`: record via `bash manifest-set-flag.sh <manifest> hook_verified true`
  (extend the existing manifest-set-flag.sh helper for boolean fields, or use sed on the
  additive field). Proceed to Workflow dispatch path.
- `hook_verified = false`: record via `bash manifest-set-flag.sh <manifest> hook_verified false`.
  Proceed to Fallback (Agent-tool batch dispatch).

The gate fires ONCE per manifest. After `hook_verified` is recorded, the gate is silent for
all subsequent Step 5 runs on the same manifest.
```

- [ ] Step 1: add the smoke test gate block before the workflow dispatch path in Step 5.
      (PATTERN: ADD)
- [ ] Step 2: verify the gate text references `hook_verified`.
- [ ] Step 3: verify the fallback activation path is documented if `hook_verified = false`.
- [ ] Step 4: verify the one-time gate behavior is documented (fires ONCE per manifest).
- [ ] Step 5: checkpoint.

**Verify command:**
```bash
grep -c 'SMOKE TEST' ~/.claude/skills/concept-to-code/SKILL.md
grep -c 'hook_verified' ~/.claude/skills/concept-to-code/SKILL.md
grep -c 'manifest-set-flag' ~/.claude/skills/concept-to-code/SKILL.md
```
Expected: SMOKE TEST >= 1, hook_verified >= 2 (dispatch mode selection + gate body),
manifest-set-flag >= 1.

**Estimate:** 20 min.

---

### Task 5 — Update run-tests.sh: add 4 structural anchors for ADR-0016

**Files:**
- Modify: `~/.claude/skills/concept-to-code/tests/run-tests.sh`

**Context:** the current harness baseline is PASS=32 FAIL=0. T2/T3/T4 added new text to
SKILL.md. T5 anchors the four invariants that must not regress: workflow trigger keyword
present, step5-report.json schema documented, fallback path present, smoke test gate present.

**Red phase:** before running T2/T3/T4, these anchors will fail (the text is not yet in
SKILL.md). After T2/T3/T4 complete, they must be green.

**For this plan, T5 runs AFTER T2/T3/T4** (green-first variant since T1-T4 define what text
must be present; writing anchors first when the contract is fully defined reduces churn).

**Green phase — edit:**

Insert the following block immediately before the final summary lines
(`echo "----"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" = "0" ] && exit 0 || exit 1`):

```bash

# --- ADR-0016: Dynamic Workflows Step 5 anchors ---
CC="$SKILL_DIR/SKILL.md"
# Anchor 1: workflow keyword present in Step 5 dispatch prompt
grep -q -- 'workflow' "$CC" 2>/dev/null \
  && ok "concept-to-code: ADR-0016 workflow keyword present in Step 5" \
  || bad "concept-to-code: ADR-0016 workflow keyword missing from Step 5"

# Anchor 2: step5-report.json schema documented
grep -q -- 'step5-report.json' "$CC" 2>/dev/null \
  && ok "concept-to-code: ADR-0016 step5-report.json schema documented" \
  || bad "concept-to-code: ADR-0016 step5-report.json schema missing"

# Anchor 3: fallback path present (Agent-tool batch dispatch retained)
grep -q -- 'Fallback' "$CC" 2>/dev/null \
  && ok "concept-to-code: ADR-0016 fallback Agent-tool path present" \
  || bad "concept-to-code: ADR-0016 fallback path missing"

# Anchor 4: smoke test gate present
grep -q -- 'hook_verified' "$CC" 2>/dev/null \
  && ok "concept-to-code: ADR-0016 smoke test gate (hook_verified) present" \
  || bad "concept-to-code: ADR-0016 smoke test gate missing"
```

**Constraints:** insert BEFORE the final `echo "----"` line. Use the existing `CC="$SKILL_DIR/SKILL.md"`
variable — it is defined earlier in the harness. Bash 3.2-clean (`grep -q`, no assoc arrays).

- [ ] Step 1: insert the 4-anchor block before the summary. (PATTERN: ADD)
- [ ] Step 2: run harness. Verify PASS=36 FAIL=0 (assuming T2/T3/T4 complete).
      If running before T2/T3/T4: expect PASS=32 FAIL=4 (confirms anchors are correctly red).
- [ ] Step 3: if PASS=36 FAIL=0 → checkpoint done. If FAIL > 0 → diagnose before proceeding.

**Verify command:**
```bash
bash ~/.claude/skills/concept-to-code/tests/run-tests.sh | tail -3
```
Expected (post-T2/T3/T4): `PASS=36 FAIL=0`, exit 0.
Expected (pre-T2/T3/T4): `PASS=32 FAIL=4`, exit 1.

**Estimate:** 15 min.

---

### Task 6 — manifest-init.sh: add hook_verified and step5_mode additive fields

**Files:**
- Modify: `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` (backup first: `.bak-2026-05-29`)

**Context:** new manifests should include `hook_verified: false` and `step5_mode: null` as
documented additive fields. This makes the smoke test gate's field-presence check reliable
(the field exists with a known default, not absent/undefined).

**Green phase — edit:**

1. **Backup:** `cp ~/.claude/skills/concept-to-code/scripts/manifest-init.sh ~/.claude/skills/concept-to-code/scripts/manifest-init.sh.bak-2026-05-29`

2. **Find the insertion point.** The manifest-init.sh writes fields in order. The appropriate
   location is after the existing `anonymize: false` line and before the `created_at` block
   (or after `test_cmd_provisional: false` — keep it with the other tracking fields).

3. **Insert these two lines** (using the existing `echo "..." >> "$T"` pattern):

   ```bash
   echo "" >> "$T"
   echo "# Dynamic Workflows Step 5 tracking (ADR-0016)" >> "$T"
   echo "hook_verified: false" >> "$T"
   echo "step5_mode: null" >> "$T"
   ```

   Insert this block after the `test_cmd_provisional: false` line and before the blank line
   that precedes the `# Artifacts` comment.

**Constraints:** use the existing `echo "..." >> "$T"` pattern (bash 3.2-clean). Do NOT use
here-docs or process substitution. Do NOT change any other field. The `mv "$T" "$manifest"`
final step is unchanged.

- [ ] Step 1: backup manifest-init.sh.
- [ ] Step 2: add the 4-line block after `test_cmd_provisional: false`. (PATTERN: ADD)
- [ ] Step 3: smoke the init script.
- [ ] Step 4: verify the existing harness assertions 1 and 3 still pass (the manifest the
      harness generates now includes the new fields — they are additive and must not break
      the validator).
- [ ] Step 5: checkpoint.

**Verify command:**
```bash
TMP=$(mktemp -d)
bash ~/.claude/skills/concept-to-code/scripts/manifest-init.sh smoke-wf16 "Smoke WF16" "$TMP" >/dev/null 2>&1
M="$TMP/docs/manifests/$(date +%Y-%m-%d)-smoke-wf16.manifest.yml"
grep -q '^hook_verified: false' "$M" && echo "hook_verified written"
grep -q '^step5_mode: null' "$M" && echo "step5_mode written"
bash ~/.claude/skills/concept-to-code/scripts/manifest-validate.sh "$M" && echo "validate still passes"
rm -rf "$TMP"
```
Expected: `hook_verified written`, `step5_mode written`, `validate still passes`.

**Estimate:** 15 min.

---

### Task 7 (optional) — Full harness verification pass

**Files:** none modified — read-only verification gate.

**Context:** after T2-T6, verify all harnesses in the system are at or above baseline. This
task is optional if T5 already confirmed PASS=36 FAIL=0 for concept-to-code and the coder
has not touched other harnesses.

- [ ] Step 1: run all live harnesses.
- [ ] Step 2: compare against baseline. Document any delta in the checkpoint.

**Verify command:**
```bash
bash ~/.claude/skills/concept-to-code/tests/run-tests.sh | tail -1
bash ~/.claude/skills/concept-to-code/tests/smoke-e2e.sh | tail -1
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh | tail -1
bash ~/.claude/skills/design-brainstorm/tests/run-tests.sh | tail -1
bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh | tail -1
bash ~/.claude/skills/vibe-status/tests/run-tests.sh | tail -1
bash ~/.claude/hooks/tests/pre-flight-pattern-enforce.sh | tail -1
bash ~/.claude/hooks/tests/run-hook-tests.sh | tail -1
bash ~/.claude/hooks/tests/db-backup-guardrail.sh | tail -1
```
Expected: concept-to-code **PASS=36 FAIL=0**. All other harnesses at their prior baselines,
FAIL=0. Any regression → diagnose before declaring done.

**Estimate:** 8 min.

---

## Harness PASS delta expected (summary)

| Harness | Baseline | Expected post-plan |
|---|---|---|
| concept-to-code | 32 | **36** (+4 anchors: workflow keyword, step5-report.json, fallback path, hook_verified gate) |
| review-triage-fix | 62 | 62 (unchanged) |
| design-brainstorm | 9 | 9 (unchanged) |
| refactor-snapshot | 18 | 18 (unchanged) |
| vibe-status | 10 | 10 (unchanged) |
| pre-flight-pattern-enforce | 13 | 13 (unchanged) |
| run-hook-tests | 24 | 24 (unchanged) |
| db-backup-guardrail | 16 | 16 (unchanged) |

## Testability note (honesty — ADR-0016 Neutral)

The harness verifies only what is deterministic and headless: structural anchors on SKILL.md
text and manifest-init.sh output. Runtime verification of hook propagation inside workflow
subagents (the smoke test) is a user-run, one-time pilot — not reproducible headless. The
harness does not and cannot verify that `PATTERN:` fires inside a live workflow. Do not claim
coverage that does not exist.

## Rollback

Backout = restore `concept-to-code/SKILL.md.bak-2026-05-29` and `manifest-init.sh.bak-2026-05-29`,
remove the 4 anchors from `run-tests.sh`. All deletions require HITL user confirmation (global
rule: never delete files without explicit confirmation). The coder may only propose the backout
procedure — never execute deletions autonomously.

## References

- ADR: `docs/architecture/ADR-0016-dynamic-workflows-step5.md`
- SPEC: `/Users/stefanoferri/developer/vibe-coding-system/SPEC.md`
- Dynamic Workflows docs: `https://code.claude.com/docs/en/workflows`
- Chain SKILL.md: `~/.claude/skills/concept-to-code/SKILL.md`
- Harness: `~/.claude/skills/concept-to-code/tests/run-tests.sh`
- manifest-init.sh: `~/.claude/skills/concept-to-code/scripts/manifest-init.sh`
- manifest-set-flag.sh: `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh`
  (existing helper; may need extension for boolean `hook_verified` field — verify at T4)
- Memory: `project_c2c-chain-hardening-2026-05-28`, `feedback_subagent-truncation-transport`,
  `feedback_bash32-constraint`
