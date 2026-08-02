---
name: autopilot-build
description: >
  Standalone unattended implementation skill. Given a manifest at
  `ready_for_implementation` (Gates 1–3 approved, SPEC+ADR+plan+TOFU-trusted test-cmd
  all in place), runs Steps 5–7 of the concept-to-code chain without any human prompt,
  then writes a morning report and stops at a local feature branch commit.
  Never pushes, never opens a PR. Safe hooks (stop-gate, pattern-enforce, db-backup)
  remain active throughout.
---

# `autopilot-build` — Unattended Implementation Skill

Runs the implementation phase of an already-approved feature without human interaction.
The human ran the interactive concept-to-code chain through Gate 3, reviewed SPEC+ADR+plan,
and left the manifest at `ready_for_implementation`. This skill picks up from there.

**Architecture reference:** ADR-0020.

---

## 1. When to invoke

```
/skill autopilot-build <manifest-path>
```

**Prerequisites (all enforced by Phase 0 pre-flight):**
- `current_step: ready_for_implementation` in the manifest.
- Gates 1, 2, 3 all `status: approved`.
- SPEC.md, ADR, and plan exist on disk and plan has unchecked tasks.
- Those artifacts are **committed, on a feature branch** — `concept-to-code` Gate 4.0 produces that
  state (ADR-0071). Step 5's recovery pre-flight refuses to dispatch without it and there is no
  leniency branch on the unattended path, so an uncommitted tree here is an `aborted` report, not a
  prompt. This line used to say only "exist on disk", which contradicted the pre-flight it hands off to.
- `.claude/test-cmd` is not `NONE`, not a placeholder, and SHA-pinned trust is registered.
- `hook_verified` is `true` or `false` (not null — run the smoke test interactively first).
- Session CWD equals `manifest.project_root` or is a parent of it.

**Do NOT invoke:**
- Before Gate 3 is approved (complete the interactive chain first).
- When TOFU trust is absent (run `concept-to-code resume` interactively to approve test-cmd).
- On a manifest for a different project from outside that project's directory.

---

## 2. Three-phase execution

### Phase 0 — Hard pre-flight (nine checks, all read-only Bash)

**Any failure → write an `aborted` morning report and stop. No dispatch, no file changes.**

Run all checks sequentially; emit one line per check (`✓ <label>` or `✗ <label>: <reason>`).

**Check 1 — Scope guard (run FIRST, before reading the manifest):**
<!-- fence-contract: autopilot-build-check-1 -->

```bash
# Extract project_root from the manifest file directly (no yq dependency)
project_root=$(grep '^project_root:' "<manifest-path>" | sed 's/project_root: *"//' | sed 's/".*//' | sed "s/project_root: *//")
cwd=$(pwd -P)
# Normalize: strip trailing slash
project_root_n="${project_root%/}"
cwd_n="${cwd%/}"
# PASS iff cwd == project_root, or project_root is strictly under cwd (slash-anchored, quoted
# pattern side). ADR-0020 D3 #1: "Session CWD equals manifest.project_root or is a parent of it."
in_scope=false
if [ "$cwd_n" = "$project_root_n" ]; then
  in_scope=true
else
  case "$project_root_n" in
    "$cwd_n"/*) in_scope=true ;;
  esac
fi
if [ "$in_scope" = false ]; then
  echo "SCOPE ERROR: manifest project_root ($project_root) is not this session's CWD ($cwd) and is not a subdirectory of it. Open a new session inside a directory at or above $project_root and run autopilot-build from there."
  exit 1
fi
```

**Check 1b — Permission posture (issue #320, ADR-0110):**

Placed here and not first because Check 1 genuinely must be: the scope guard is what stops this
skill operating outside its session's CWD, and nothing may precede it. Placed here and not last
because a blocking mode can deny or prompt on the checks below, so learning about it after six more
of them wastes the diagnosis.

This runs with no human present, exactly like `nightly-autopilot` Phase M, and reads the **same**
checker for the same reason: two unattended entry points that disagreed about whether a run may
start would be a defect, not a difference.

<!-- fence-contract: autopilot-build-check-1b -->
```bash
_pms=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/permission-mode-state.sh" ]; then
  _pms="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/permission-mode-state.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/permission-mode-state.sh" ]; then
  _pms="$HOME/.claude/skills/concept-to-code/scripts/permission-mode-state.sh"
else
  echo "✗ permission posture: permission-mode-state.sh not found — the check DID NOT RUN."
  echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 1
fi
_pm=$(bash "$_pms" 2>&1); _pmrc=$?
if [ "$_pmrc" -ne 0 ]; then
  echo "✗ permission posture: the check DID NOT RUN (rc=$_pmrc) — $_pm"
  exit 1
fi
case "${_pm%%|*}" in
  NONBLOCKING)
    # Two NONBLOCKING modes, two different guarantees, two different sentences (issue #339).
    # acceptEdits auto-accepts EDITS only; Bash outside permissions.allow still prompts.
    if [ "${_pm#*|}" = "bypassPermissions" ]; then
      echo "✓ permission posture: bypassPermissions — no per-tool prompt can fire."
    else
      echo "✓ permission posture: ${_pm#*|} — edits are auto-accepted, but a Bash command outside"
      echo "  permissions.allow STILL PROMPTS and nobody is here to answer it. Proceeding on the"
      echo "  assumption your allowlist covers this build's Bash surface; relaunch with"
      echo "  bypassPermissions if you have not checked."
    fi ;;
  BLOCKING)
    echo "✗ permission posture: this session is in '${_pm#*|}', which can prompt or deny, and"
    echo "  autopilot-build runs with nobody to answer. Set a non-blocking mode and relaunch."
    echo "  /permissions does NOT set the mode (it manages allow/ask/deny rules); hooks are a"
    echo "  separate axis and stay enabled. Launch with:"
    echo "    claude --permission-mode bypassPermissions   (the mode to use unattended)"
    echo "  or Shift+Tab to it, reading the mode off the status line. acceptEdits is accepted"
    echo "  too but only auto-accepts EDITS — Bash outside permissions.allow still prompts."
    exit 1 ;;
  UNCLASSIFIED)
    echo "✗ permission posture: mode '${_pm#*|}' is UNCLASSIFIED — not known-bad, just unmeasured."
    echo "  A pre-flight refuses the unknown rather than gamble an unattended run on it."
    exit 1 ;;
  UNOBSERVABLE)
    echo "✗ permission posture: the effective mode could not be observed — ${_pm#*|}"
    echo "  A fact about this build, not a bad mode: the transcript field is CC 2.1.220+."
    echo "  This gate fails closed on purpose; verify the mode by hand before relaunching."
    exit 1 ;;
  *)
    echo "✗ permission posture: unrecognised token '${_pm%%|*}'"; exit 1 ;;
esac
```

**Check 2 — Manifest state:**
<!-- fence-contract: autopilot-build-check-2 -->
```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-validate.sh "<manifest-path>" || exit 1
# `sed 's/^current_step: *//;s/"//g'` is manifest-validate.sh's idiom, used at 17 sites there and
# by check 1 above. Do NOT go back to `awk '{print $2}'`: manifest-init.sh and
# manifest-transition.sh both write the value QUOTED, so awk yields `"ready_for_implementation"`
# with the quotes and this check aborted on every manifest the system has ever produced (issue
# #218) — with a message that reads as nonsense and blames the manifest.
step=$(grep '^current_step:' "<manifest-path>" | sed 's/^current_step: *//;s/"//g' | head -1)
[ "$step" = "ready_for_implementation" ] || { echo "✗ state: current_step is $step, not ready_for_implementation. Complete the interactive chain through Gate 3 first."; exit 1; }
```

**Check 3 — Gates 1–3 approved:**
Read `manifest.hitl_gates`. For gates 1, 2, 3: verify each `status: approved`. If any is not
`approved`, abort with: "Gate N not approved. Complete the interactive chain through Gate N first."

<!-- fence-contract: autopilot-build-check-3 -->
```bash
for gate_n in 1 2 3; do
  status=$(python3 -c "
import yaml, sys
m = yaml.safe_load(open('$manifest'))
g = next((g for g in m.get('hitl_gates', []) if g['gate'] == $gate_n), None)
print(g['status'] if g else 'missing')
" 2>/dev/null || echo "missing")
  [ "$status" = "approved" ] || { echo "✗ gate $gate_n: status=$status. Complete the interactive chain first."; exit 1; }
done
```

**Check 4 — Artifacts on disk:**
<!-- fence-contract: autopilot-build-check-4 -->
```bash
spec=$(python3 -c "import yaml; m=yaml.safe_load(open('$manifest')); print(m['artifacts']['spec'] or '')" 2>/dev/null)
adr=$(python3 -c "import yaml; m=yaml.safe_load(open('$manifest')); print(m['artifacts']['adr'] or '')" 2>/dev/null)
plan=$(python3 -c "import yaml; m=yaml.safe_load(open('$manifest')); print(m['artifacts']['plan'] or '')" 2>/dev/null)
for f in "$spec" "$adr" "$plan"; do
  [ -z "$f" ] && { echo "✗ artifacts: one or more artifact paths are null in the manifest."; exit 1; }
  test -f "$f" || { echo "✗ artifacts: not found on disk: $f"; exit 1; }
done
```

**Check 5 — Plan has tasks:**
<!-- fence-contract: autopilot-build-check-5 -->
```bash
# plan-tasks.sh owns the definition of a plan task (ADR-0069 §D1/§D3, issue #172). Do NOT inline a
# grep here: the architect is allowed BOTH `### Task 3 — …` headings and `- [ ]` checkbox items,
# and a checkbox-only count aborts this unattended run on 7 of the 57 plans in the corpus — with a
# message blaming the plan. Cross-skill call, same terms as the manifest-*.sh calls above.
tasks=$(bash ~/.claude/skills/concept-to-code/scripts/plan-tasks.sh --count "$plan"); rc=$?
# rc 2/3 mean the check DID NOT RUN. Aborting is still correct unattended, but say which it was.
[ "$rc" -eq 0 ] || { echo "✗ plan: task check did not run (plan-tasks.sh exit $rc)."; exit 1; }
[ "$tasks" -ge 1 ] || { echo "✗ plan: no recognisable task found. A task is a '## Task N — …' heading (H2-H4) or a '- [ ]' checklist item. The plan may be malformed."; exit 1; }
```

**Check 6 — test-cmd real and trusted:**
<!-- fence-contract: autopilot-build-check-6 -->
```bash
tcf="$project_root/.claude/test-cmd"
test -f "$tcf" || { echo "✗ test-cmd: .claude/test-cmd not found."; exit 1; }
content=$(cat "$tcf")
[ "$content" = "NONE" ] && { echo "✗ test-cmd: value is NONE. Approve a real test command interactively first."; exit 1; }
# Field state via the shared helper (issue #195/ADR-0076; this call site is issue #258). The
# two-tier resolution below is a DELIBERATE second copy of check 7's. ADR-0086's criterion would
# call it extractable — two copies that could disagree are a defect, and these must agree — but a
# fence that borrowed a variable bound in an EARLIER fence would stop being independently
# executable, which is the property ADR-0083 F4/F7 rest on. `fence-contract-coverage.test.sh` E7f
# asserts the two resolution paths stay identical instead of extracting them.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/manifest-field-state.sh" ]; then
  _mfs="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/manifest-field-state.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/manifest-field-state.sh" ]; then
  _mfs="$HOME/.claude/skills/concept-to-code/scripts/manifest-field-state.sh"
else
  echo "✗ test-cmd: manifest-field-state.sh not found in either location. Run: bash <repo>/staging/sync-to-claude.sh --apply"; exit 1
fi
tcp=$(bash "$_mfs" "$manifest" test_cmd_placeholder 2>/dev/null) || tcp="UNREADABLE"
# The line this replaces was `placeholder=$(python3 -c "… m.get('test_cmd_placeholder', False)"
# 2>/dev/null)` tested against "True". An unparseable manifest, or a missing python3/PyYAML,
# produced an EMPTY string — which is not "True" — so this UNATTENDED pre-flight PASSED (#258).
# Assert the valid values; never test for one invalid one (ADR-0075 §D4).
#
# ABSENT PROCEEDS HERE, which is the OPPOSITE of check 7's rule for hook_verified four lines below,
# and the asymmetry is deliberate rather than an oversight: this flag is CORROBORATING, not
# primary. The authoritative signal is the file itself and it is already checked two lines above
# (`content = NONE`), while a real-looking command that was never approved is caught by the TOFU
# check below. `hook_verified` has no such fallback — nothing else records the dispatch mode —
# which is why its absence must abort. Measured: 40 of 41 corpus manifests carry the field, the one
# ABSENT is `completed` and predates it. Do not "reconcile" the two.
case "$tcp" in
  PRESENT\|False) : ;;
  PRESENT\|True)  echo "✗ test-cmd: test_cmd_placeholder=true. Run Gate 2b interactively to register the real command."; exit 1 ;;
  ABSENT\|*)      echo "· test-cmd: test_cmd_placeholder absent (current_step=${tcp#ABSENT|}); this manifest predates the field. Proceeding — the NONE check above and the TOFU check below both cover it." ;;
  UNREADABLE|"")  echo "✗ test-cmd: the manifest could not be read, or the check did not run (python3/PyYAML). That is not the same as a bad value; fix the file or the interpreter and re-run."; exit 1 ;;
  *)              echo "✗ test-cmd: test_cmd_placeholder is \"${tcp#PRESENT|}\" — must be true or false. The manifest is corrupted or was hand-edited; fix or re-init."; exit 1 ;;
esac
# TOFU trust check
hash=$(shasum -a 256 "$tcf" | awk '{print $1}')
root_n=$(cd "$project_root" && pwd -P | tr '[:upper:]' '[:lower:]')
grep -qxF "${hash}	${root_n}" "$HOME/.claude/state/stop-gate/trust" 2>/dev/null \
  || { echo "✗ test-cmd: not TOFU-trusted. Run the interactive chain (concept-to-code resume) to approve the test command for this project."; exit 1; }
```

**Check 7 — hook_verified known:**
<!-- fence-contract: autopilot-build-check-7 -->
```bash
# Field state via the shared helper (issue #195, ADR-0076). Two-tier resolution; if neither
# resolves this gate fails closed, because an infrastructure gap must never be silently absorbed
# by a second copy of the logic.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/manifest-field-state.sh" ]; then
  _mfs="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/manifest-field-state.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/manifest-field-state.sh" ]; then
  _mfs="$HOME/.claude/skills/concept-to-code/scripts/manifest-field-state.sh"
else
  echo "✗ hook_verified: manifest-field-state.sh not found in either location. Run: bash <repo>/staging/sync-to-claude.sh --apply"; exit 1
fi
hv=$(bash "$_mfs" "$manifest" hook_verified 2>/dev/null) || hv="UNREADABLE"
# Assert the two VALID values, never enumerate the invalid ones (issue #123, ADR-0075 §D4). The
# old test was `[ "$hv" = "None" ] || [ -z "$hv" ]`, so anything that was neither — `maybe`, a
# typo, a string "false" from a quoted YAML value — PASSED, and the run then branched on it.
#
# ABSENCE IS AN ABORT HERE, and that is the OPPOSITE of nightly-autopilot check 6, which reads the
# same field through the same helper and tolerates it. Both are right: that one sweeps a corpus of
# long-completed chains whose dispatch mode cannot affect anything; this one reads the single
# manifest about to be built, in flight by definition. The helper reports the state and leaves the
# policy at each call site precisely so this asymmetry stays visible (ADR-0076 §D2). Do not
# "reconcile" the two.
case "$hv" in
  PRESENT\|True|PRESENT\|False) : ;;
  ABSENT\|*)  echo "✗ hook_verified: field absent (current_step=${hv#ABSENT|}). This manifest is the one about to be built, so its dispatch mode must be known. Run the Step 5 smoke test in an interactive session first."; exit 1 ;;
  UNREADABLE|"") echo "✗ hook_verified: the manifest could not be read, or the check did not run (python3/PyYAML). This is not the same as a bad value; fix the file or the interpreter and re-run."; exit 1 ;;
  *)          echo "✗ hook_verified: value is \"${hv#PRESENT|}\" — must be true or false. The manifest is corrupted or was hand-edited; fix or re-init."; exit 1 ;;
esac
```

**Check 8 — Git repo at CWD:**
<!-- fence-contract: autopilot-build-check-8 -->
```bash
git rev-parse --git-dir >/dev/null 2>&1 || { echo "✗ git: CWD is not inside a git repository. Worktree isolation will fail."; exit 1; }
```

On all eight checks passing, emit:
```
autopilot-build · pre-flight PASSED (8/8) · dispatching Step 5...
```

No `AskUserQuestion` is called anywhere after this point.

**Permission posture (CC 2.1.186/187).** Since CC 2.1.186 a background subagent that reaches for a
tool outside the allowlist surfaces a permission prompt in the main session instead of auto-denying
it. With no human present that prompt is a hang condition, not a silent deny. So an unattended
dispatch is only safe when the Step-5 allowlist covers every tool the subagents actually use; verify
allowlist completeness together with Check 6 before dispatching. CC 2.1.187 closed the related
empty-output background-job hang, but this permission-prompt stall is a separate path and remains the
open risk for autopilot.

---

### Phase 1 — Unattended Steps 5, 6, 7

This phase reuses the exact dispatch logic from `~/.claude/skills/concept-to-code/SKILL.md`
(Steps 5–7). The human-decision layer is suppressed — all gate choices are auto-resolved to
their "safe default" without prompting. All safety hooks remain active.

Read the manifest to populate these variables before dispatch:
- `project_root` — from `manifest.project_root`
- `plan_path` — from `manifest.artifacts.plan`
- `adr_path` — from `manifest.artifacts.adr`
- `spec_path` — from `manifest.artifacts.spec`
- `project_claude_md` — from `manifest.artifacts.project_claude_md` (may be null)
- `coder_model` — from `manifest.coder_model` (may be null)
- `hook_verified` — from `manifest.hook_verified`
- `topic_full_title` — from `manifest.topic_full_title`
- `topic_slug` — from `manifest.topic` (the kebab slug)
- `anonymize` — from `manifest.anonymize`

Also check for PROJECT.md:
```bash
_project_context=""
if [ -f "$project_root/PROJECT.md" ]; then
  _project_context=$(cat "$project_root/PROJECT.md")
fi
```

#### Step 5 — Implementation dispatch

**Recovery-readiness pre-flight (same as c2c Step 5, "Recovery-readiness pre-flight (ADR-0050)" block) — run BEFORE the worktree isolation check below:** working tree clean (`git status --porcelain` empty), a feature branch checked out (not the default branch, resolved via `git symbolic-ref refs/remotes/origin/HEAD` rather than a hardcoded `main`), HEAD sha recorded once as `recovery_baseline_sha`, and Step 5.0.4's `worktree.baseRef == "head"` check (ADR-0068 §D1) against the effective `settings.json` — non-zero, including a missing or unparseable file, is not verified and fails closed like the other three. Refuses identically to the attended path — no leniency branch for `autopilot: true` (ADR-0050 §D6). On refusal: write an `aborted` report naming the failed assertion and the literal remediation command, do not dispatch — recorded in the report rather than prompted, since there is no `AskUserQuestion` on this path.

**Worktree isolation check (same as c2c Step 5, "Pre-dispatch: worktree isolation check"):**
```bash
git rev-parse --git-dir 2>/dev/null
```
- exit 0 → dispatch coder with `isolation: worktree`. There is no second mode (ADR-0068 §D1,
  §D10).
- exit non-0 → refuse to dispatch and write an `aborted` report. Print the literal message:
  "Worktree isolation contract: the session CWD is not inside a git repository. The chain cannot
  dispatch a modification agent here. Run the chain from inside the repository, or `git init` the
  project root, and re-invoke Step 5." Check 8 above already refuses at pre-flight for this same
  reason, so this arm is redundant in practice and kept for defense in depth.

**Parallel-conflict scan (binding, same as c2c Step 5, "Before dispatch — parallel task conflict scan (GAP E)"; R-10):**
Read the plan. If the same absolute file path appears in multiple unchecked task descriptions,
sequence those task groups instead of dispatching them in the same batch — the scan is binding,
not advisory, because merges are real (ADR-0068 §D5) and a genuine conflict halts the run. Groups
with no path overlap keep the default parallel dispatch. A merge conflict during Step 5's
merge-back halts the run exactly as in c2c (see c2c's `#### Merge-back and base-fork audit`
Conflict halt): report the worktree branch and the conflicting files, preserve the branch, attempt
no automatic resolution (no rebase, no `-X ours`, no resolver dispatch), and record the halt in
`autopilot-report.json` rather than prompting — there is no human to prompt here. `nightly-autopilot`
inherits this same conflict halt unchanged, since it reuses c2c Steps 5–7 verbatim.

**Dispatch:**
- `hook_verified=true`: Workflow dispatch (ultracode keyword — same prompt as c2c's "Workflow dispatch path — Step 5 implementation (hook_verified = true)" block),
  with `$_project_context` injection if non-empty, with `coder_model` if set. That block pins `model` AND `effort` on every `agent()`
  call; carry both across unchanged, since a Workflow subagent inherits the session value for
  whichever one is omitted.
- `hook_verified=false`: Agent-tool batch fallback (same as c2c fallback, groups of 2–3 tasks).

Set `step5_mode` in manifest via bash sed after dispatch completes.

**Circuit breaker — read `.claude/step5-report.json` after dispatch.** Run the gate from c2c's
`Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)` block (named by heading, never a line
range — ADR-0018) as part of this same read:
- Report absent or malformed → halt, status=partial, abort_reason="step5-report.json missing or malformed".
- `test_result = RED` → halt, status=partial, abort_reason="tests RED after Step 5".
- `tasks_failed > 0` → halt, status=partial, abort_reason="N tasks failed in Step 5".
- `weakening_findings` non-empty, or the gate's own scan prints a `WEAKENED` line → halt,
  status=partial, abort_reason="test weakening detected in Step 5".

On halt: skip Steps 6 and 7, jump to Phase 2 (morning report).

#### Step 6 — Review + fix

Same dispatch as c2c Step 6: Workflow path (`hook_verified=true`, c2c's "Workflow dispatch path — Step 6 review cycle (hook_verified = true)" block)
or `review-triage-fix` skill fallback.

After fixes: re-run the approved test-cmd:
```bash
bash -c "$(cat $project_root/.claude/test-cmd)"
```
- RED → halt, status=partial, abort_reason="tests RED after Step 6 fix cycle".
- GREEN → continue to Step 7.
- Any anti-test-weakening BLOCKER in the review-triage-fix recap → halt, status=partial,
  abort_reason="test weakening flagged by review-triage-fix in Step 6". CIRCUIT BREAKER B
  flags and never reverts, so without this bullet a weakening introduced by the fix cycle
  itself would reach the commit unstopped.

Set `step6_mode` in manifest via bash sed after dispatch completes.

#### Step 7 — Local commit only

```
Use the commit skill (invoke via Skill tool, not Agent tool).
Context hint: "<topic_full_title> (ADR: <adr_path>) --autopilot"
```

The `--autopilot` flag in the commit skill's args:
- Skips the HITL gate (no `AskUserQuestion`).
- Commits immediately with the generated Conventional Commits message.
- Skips push and PR entirely (the commit skill's `--autopilot` argument description: "Step 6 (PR) is also skipped in autopilot mode").

After commit completes: capture the commit SHA via `git log -1 --format=%H`.

Transition manifest:
```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh "<manifest-path>" completed completed
```

**Do NOT update PROJECT.md.** The human reviews the report and decides whether the feature is
truly done before marking it complete in the roadmap.

---

### Phase 2 — Morning report

Write `<project_root>/.claude/autopilot-report.json` on every exit path (including aborted and
partial). Use `date -u +%Y-%m-%dT%H:%M:%SZ` for `ended_at`.

```json
{
  "schema": "1.0",
  "manifest": "<manifest-path>",
  "topic": "<topic_full_title>",
  "status": "success | partial | aborted",
  "abort_reason": null,
  "started_at": "<ISO-8601 from session context or --started-at arg>",
  "ended_at": "<ISO-8601>",
  "branch": "<type/topic-slug>",
  "steps": {
    "step5": "done | failed | not_run",
    "step6": "done | failed | not_run",
    "step7": "done | failed | not_run"
  },
  "tasks_completed": 0,
  "tasks_failed": 0,
  "test_result": "GREEN | RED | NOT_RUN",
  "files_modified": [],
  "weakening_findings": [],
  "commit_sha": null,
  "review_remaining": [],
  "next_action": ""
}
```

`next_action` values:
- `status=success`: `"Review diff on branch <branch> and push when ready: git push -u origin <branch>"`
- `status=partial`: `"Tests failed or tasks incomplete. Check .claude/step5-report.json and resume interactively: /skill concept-to-code resume <manifest-path>"`
- `status=aborted`: `"Pre-flight failed: <abort_reason>. Fix the issue and re-run autopilot-build."`

Emit one terminal line:
```
autopilot-build · <status> · report: <project_root>/.claude/autopilot-report.json
```

---

## 3. Safety invariants

These hold on every run, regardless of status:

- **Scope guard is script-level.** Check 1 is a Bash condition, not a prompt reminder. It cannot
  be satisfied by a well-formed prompt that happens to reference a different project.
- **TOFU trust is never auto-granted.** If trust is absent, the skill aborts. It does not call
  `approve-test-cmd.sh` with a write intent. (It reads the trust file — that is the only access.)
- **No push, no PR, no remote mutation.** The commit skill's `--autopilot` mode hard-skips push.
  There is no code path in this skill that calls `git push` or `gh pr create`.
- **Safety hooks are always active.** `stop-gate.sh`, `pre-flight-pattern-enforce.sh`,
  `protect-files.sh`, and `db-backup-guardrail.sh` fire on every tool call exactly as they do
  in an interactive session. Autopilot does not disable or bypass hooks.
- **No test disabling.** If tests are RED, the skill halts. It never modifies `.claude/test-cmd`
  or skips the test-run to achieve a green status.
- **Bounded, not open-ended, under failure.** For the autopilot session env, set
  `CLAUDE_CODE_RETRY_WATCHDOG` so a hung or looping dispatch stays bounded (the changelog gives no
  value format, so this is a documented recommendation, not a pinned setting).
  `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT` bounds a hung remote-MCP call (CC 2.1.187, 5-minute default).
  Neither disables a safety mechanism; both cap an unattended run that would otherwise stall.

---

## 4. Out of scope (v1)

- Multi-feature overnight queue — extend `project-conductor` to call `autopilot-build` per
  feature; deferred.
- `--push` opt-in — needs a separate ADR; crosses the autonomy boundary.
- `CLAUDE_CLIENT_PRESENCE_FILE` — a launch-time env var the skill cannot set; document it as
  an optional launch-time flag: `CLAUDE_CLIENT_PRESENCE_FILE=/tmp/claude-present autopilot-build <manifest>`.
- Cron scheduling — wrap with `CronCreate` once the skill has field-tested successfully.

---

## 5. Verification checklist

Manual verification against a real or throwaway project:

- [ ] Pre-flight check 1: wrong CWD → SCOPE ERROR, `aborted` report written, no dispatch.
- [ ] Pre-flight check 2: manifest at wrong step → abort message, no dispatch.
- [ ] Pre-flight check 6: `test-cmd = NONE` → abort. `test_cmd_placeholder=true` → abort. Untrusted → abort.
- [ ] Pre-flight check 7: `hook_verified=null` → abort.
- [ ] Happy path: small approved feature, run to completion → local commit on `type/<slug>`,
  GREEN test, `status: success`, no push performed (`git log origin/..HEAD` shows the new commit
  as local only).
- [ ] Circuit breaker: plan task that makes tests RED → `status: partial`, no commit, report
  names the failure.
- [ ] Scope guard regression: invoke from outside the project directory → SCOPE ERROR abort.
