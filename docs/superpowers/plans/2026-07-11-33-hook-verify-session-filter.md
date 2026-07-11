# Plan — hook-verify-workflow: filter the audit window by session

**Date:** 2026-07-11
**ADR:** [ADR-0029](../../architecture/ADR-0029-33-hook-verify-session-filter.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/33-hook-verify-workflow-filter-the-audit-wi.spec.md`,
issue #33, confirmed byte-identical)
**Style:** TDD (red → green → checkpoint). Auto mode active, no intermediate HITL inside this plan;
commit/push stay HITL per repo `CLAUDE.md` invariant (see HITL gates, end of file). One finding, one
script + its test file + two `SKILL.md` prose bullets — the fix scope is exactly SPEC's single
objective, nothing broader (ADR-0029 §2/§3 records every alternative considered, including the
disclosed, deliberately-unclosed residual gap).

**Task checklist (six tasks — checked off by the coder as each completes; both `concept-to-code`
SKILL.md's Step 5 pre-dispatch check and `autopilot-build` SKILL.md's Check 5 grep this file for
`- [ ]`, so every task gets one, unlike this plan's own prose elsewhere):**

- [x] Task 1 — RED: add the `rowsid()` fixture helper and the S1-S5 session-scoping test cases.
- [x] Task 2 — GREEN: implement the session-filtering fix in `hook-verify-workflow.sh`.
- [x] Task 3 — RED: add the S6-S8 exit-code-contract doc-sync test cases.
- [x] Task 4 — GREEN: update the header comment and `SKILL.md`'s two prose bullets.
- [x] Task 5 — Full regression sweep, bash-safety sweep, scope verification.
- [x] Task 6 — SPEC.md checkbox update, final report.

---

## Why every RED in this plan is genuine RED (except two explicitly-labeled companions)

Every genuine-RED assertion below was checked against the real, unfixed `hook-verify-workflow.sh`
during planning (ADR-0029 §1 Context reproduces the core false positive directly). Two assertions (S1,
S5) are **non-regression companions**, expected to pass **both before and after** their task — they
exist to pin the happy path and the disclosed residual gap (ADR-0029 §2.1/§4 Negative) respectively, not
to prove a defect. Each task below states explicitly which category its own assertions are.

## Fixture and path conventions (read once, applies to every task below)

- **File to extend:** `staging/plugin/scripts/tests/hook-verify-workflow.test.sh` (26 existing
  assertions today — **do not create a sibling file**; SPEC.md explicitly instructs extending this one).
  Existing `SCRIPTS`/`V` path derivation, `PASS`/`FAIL`/`ok`/`no` idiom, and the existing `row()` helper
  (hardcoded `"sess"` session id) all stay byte-identical — **do not touch any line above the insertion
  point** (current lines 1-116).
- **Insertion point:** immediately before the `# --- summary ---` block (current lines 118-120), i.e.
  directly after the existing final case ("one enforcement outweighs a co-occurring bypass," current
  line 116) and its trailing blank line.
- **New fixture helper**, added once, directly after the existing `row()` helper (current line 34):
  ```bash
  # rowsid <ts> <session_id> <tool> <decision> <detail>  — like row(), but with an explicit
  # session id instead of the hardcoded "sess" placeholder. Used only by the session-scoping
  # section below (issue #33); every pre-existing fixture keeps using row()/"sess" untouched.
  rowsid() { printf '%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5"; }
  ```
- **Reuse the file's own existing `$MARK`/`$BEFORE`/`$AFTER` constants** (current lines 20-22) for every
  new fixture — do not introduce new timestamp literals.
- **`SKILL_MD` path for Section 2's static assertions**, derived the same way the file already derives
  `SCRIPTS`/`V` (current lines 10-11), added once alongside them:
  ```bash
  SKILL_MD=$(cd "$SCRIPTS/../skills/concept-to-code" && pwd)/SKILL.md
  ```
- **Bash 3.2 / BSD safety (every file touched this plan):** no `${var,,}`, no `mapfile`, no `<()`, no
  `declare -A`, no GNU-only regex shorthands (`\s`, `\d`) in any `grep -E`/`awk` pattern — this plan uses
  only plain `grep -q` (BRE, no metacharacters in any anchor string used) and `awk -F'\t'` with `-v`
  variable passing, matching the file's own existing style throughout.
- **Per-task checkpoint (three checks, all must pass before moving to the next task):**
  1. `bash -n <every file touched this task>`.
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' <changed .sh file>` — must be empty.
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay green, unchanged (this
     plan adds zero `PAIRS` entries anywhere).

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verified during planning, not assumed):
  `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` → 8/8 files green;
  `hook-verify-workflow.test.sh` itself: `26 passed, 0 failed`.
- Writes are confined to: `staging/plugin/scripts/hook-verify-workflow.sh`,
  `staging/plugin/scripts/tests/hook-verify-workflow.test.sh`,
  `staging/plugin/skills/concept-to-code/SKILL.md`, `SPEC.md` (checkbox updates, final task),
  `docs/architecture/` and `docs/superpowers/plans/` (already written by this ADR/plan pass).
- Do not touch: any file under `~/.claude` (the deployed copies stay defective until a separate, human-
  gated `sync-to-claude.sh --apply` — ADR-0029 §4 Negative, same convention as ADR-0025/26/27/28),
  `staging/sync-to-claude.sh` (the path mapping for both files already exists, confirmed by reading — no
  new entry needed), `.github/workflows/docs-ci.yml` and `.claude/test-cmd` (both already cover this
  file by name/glob — confirmed by reading before this plan was written, no change needed),
  `staging/plugin/scripts/pre-flight-pattern-enforce.sh` (the guard being read, not modified — this
  issue is about the *reader*, not the *writer*, of the audit log), `staging/plugin/scripts/hook-probe*`
  and its tests (a structurally similar but entirely separate INCONCLUSIVE/exit-3 contract for a
  different feature — do not conflate the two, do not edit either hook-probe file), any historical ADR
  (immutable records — ADR-0016 is **amended by reference**, per ADR-0029's own front-matter, never
  edited in place), `docs/specs/34-*.spec.md` (issue #34's gap is disclosed in ADR-0029 §1, not
  implemented — no edit to that file).
- `hook-verify-workflow.sh` edits are scoped exactly to: the AFTER-window computation and the two
  REFUTED/INCONCLUSIVE branches around it (current lines ~95-137, ADR-0029 §2.1), the summary `printf`
  line (current lines 117-118, gains one field), the exit-codes header comment (current lines 40-48,
  ADR-0029 §2.2), and one new "Known limit" paragraph inserted after the existing one (current lines
  30-33). The `--mark` branch, the marker-format `case` validation, the missing-log INCONCLUSIVE branch
  (current lines 87-93), and the `Usage:` block are **byte-identical, untouched** — verify with a
  targeted diff in Task 5's checkpoint.
- `SKILL.md` edits are scoped exactly to the exit-1 and exit-3 bullets inside the Step 5 smoke-test-gate
  block (current lines 549-556, ADR-0029 §2.3) — confirmed by direct reading before this plan was
  written to be the only two sites in the whole file describing this script's exit codes (`grep -c
  "hook-verify-workflow" SKILL.md` → 2, both are the `--mark`/`--check` invocation lines at 529/543, not
  prose sites; the prose sites live at 549-556). Do **not** touch the `--mark`/`--check` invocation
  lines, the autopilot-default bracket (`SKILL.md:567-572`), or any other Step 5/Step 6 content.

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/prep.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` → exit 0 (untouched by this plan; a collision
  canary since it shares the "INCONCLUSIVE/exit 3" vocabulary with this issue's own script, but is a
  fully separate file and contract).
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` → exit 0, unchanged (no new `PAIRS`
  entries added at any point in this plan).
- `bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` → exit 0, unchanged
  17/17 (untouched by this plan).
- `bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` → exit 0, unchanged
  21/21 (untouched by this plan).
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing under
  `~/.claude` is ever touched.

---

## Task 1 — RED: Section "Session scoping (issue #33)" (S1-S5)

- [x] Add the `rowsid()` fixture helper and the S1-S5 session-scoping test cases (genuine RED for S2-S4;
  S1 and S5 are non-regression companions, already passing).

**Files modified:**
- `staging/plugin/scripts/tests/hook-verify-workflow.test.sh` (add the `rowsid()` helper after line 34;
  insert this section at the point defined in "Fixture and path conventions").

**Contract — insert verbatim (adjust only if the file's exact current line numbers have drifted; anchor
on content, not line number):**
```bash
# --- session scoping: CLAUDE_CODE_SESSION_ID (issue #33) ------------------------------------------

# S1 (non-regression companion, already passing today): same-session rows only, with
# CLAUDE_CODE_SESSION_ID set to the matching id => VERIFIED. Already true today too, because the
# unfixed script is session-blind (an allow row alone already verifies regardless of session id or
# env var) -- this pins the happy path so the filtering logic added in Task 2 cannot silently break it.
D="$tmp/sid-same"; mklog "$D" "$(rowsid "$AFTER" sess-mine Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" CLAUDE_CODE_SESSION_ID=sess-mine bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "S1 same-session rows, CLAUDE_CODE_SESSION_ID set => exit 0 VERIFIED" \
  || no "S1 same-session rows => exit 0 (got $RC)"

# S2 (dynamic, genuine RED): foreign-session rows only, CLAUDE_CODE_SESSION_ID set to a DIFFERENT id
# => REFUTED, not VERIFIED. Expected now (RED): exit 0 VERIFIED -- the unfixed script ignores field 2
# entirely, so a foreign session's own allow row still flips hook_verified to true (empirically
# reproduced against the real script during planning -- ADR-0029 Context -- the exact false positive
# SPEC.md and ADR-0016 both name).
D="$tmp/sid-foreign"; mklog "$D" "$(rowsid "$AFTER" sess-other Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" CLAUDE_CODE_SESSION_ID=sess-mine bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "S2 foreign-session rows, CLAUDE_CODE_SESSION_ID set => exit 1 REFUTED" \
  || no "S2 foreign-session rows => exit 1 (got $RC)"
printf '%s' "$OUT" | grep -q 'other, concurrent Claude Code session' \
  && ok "S2 => reason names concurrent-session exclusion, not a hooks-disabled guess" \
  || no "S2 => reason should name concurrent-session exclusion"

# S3 (dynamic, genuine RED): mixed rows, CLAUDE_CODE_SESSION_ID set => verdict AND the count use ONLY
# the matching session. sess-mine alone would REFUTE (workflow-subagent bypass); sess-other's allow
# row must not rescue it. Expected now (RED): exit 0 VERIFIED and decisions_after_mark=2 (both rows
# counted unconditionally today).
D="$tmp/sid-mixed"; mklog "$D" \
  "$(rowsid "$AFTER" sess-mine  Edit bypass-noncoder 'agent_type=workflow-subagent')" \
  "$(rowsid "$AFTER" sess-other Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" CLAUDE_CODE_SESSION_ID=sess-mine bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "S3 mixed rows => foreign allow does not rescue this session's bypass" \
  || no "S3 mixed rows => exit 1 (got $RC)"
printf '%s' "$OUT" | grep -q 'decisions_after_mark=1' \
  && ok "S3 => count is scoped to this session (1, not 2)" \
  || no "S3 => decisions_after_mark should be scoped to 1"

# S4 (dynamic, genuine RED): no CLAUDE_CODE_SESSION_ID, rows from 2 different sessions after the
# marker => INCONCLUSIVE, not a guess in either direction. Expected now (RED): exit 0 VERIFIED (both
# rows' allow decisions are currently counted with no session awareness at all).
D="$tmp/sid-ambiguous"; mklog "$D" \
  "$(rowsid "$AFTER" sess-a Edit allow 'PATTERN found in window')" \
  "$(rowsid "$AFTER" sess-b Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 3 ] && ok "S4 ambiguous multi-session window, no CLAUDE_CODE_SESSION_ID => exit 3 INCONCLUSIVE" \
  || no "S4 ambiguous window => exit 3 (got $RC)"
printf '%s' "$OUT" | grep -q 'status=INCONCLUSIVE' && ok "S4 => status line says INCONCLUSIVE" || no "S4 => status line"
printf '%s' "$OUT" | grep -q 'hook_verified=unchanged' && ok "S4 => recommends nothing (same discipline as the missing-log case)" || no "S4 => recommends nothing"
printf '%s' "$OUT" | grep -q '2 different Claude Code sessions' && ok "S4 => reason names the session count" || no "S4 => reason should name the session count"

# S5 (non-regression companion, already passing both before AND after this fix -- disclosed residual
# gap, ADR-0029 Section 2.1/Section 4 Negative, not a bug): no CLAUDE_CODE_SESSION_ID, exactly ONE
# session id in the window (which happens not to be "ours," but there is nothing to compare it
# against) => falls through to legacy, session-blind behavior. Pinned deliberately so a future change
# cannot silently alter this documented limitation without this assertion failing first.
D="$tmp/sid-single-unscoped"; mklog "$D" "$(rowsid "$AFTER" sess-only-one Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "S5 single session id, no CLAUDE_CODE_SESSION_ID => exit 0 VERIFIED (disclosed residual gap, not a bug)" \
  || no "S5 single unscoped session => exit 0 (got $RC)"
```

**Expected now (RED):** S1 passes (already true). S2 fails (`RC=0` not `1`). S3 fails (`RC=0` not `1`;
`decisions_after_mark=2` not `1`). S4 fails (`RC=0` not `3`; none of the three grep checks match). S5
passes (already true).

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/hook-verify-workflow.test.sh
bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh
# expect: 26 (existing) + S1 pass + S2 fail + S3 fail(x2 assertions) + S4 fail(x3 assertions, S4's own RC check also fails) + S5 pass
# i.e. RED tallies per the itemized case list; 39 total assertions once S1-S8 all land (several S-cases carry multiple ok/no assertions)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 2 — GREEN: session-filtering fix (`hook-verify-workflow.sh`, ADR-0029 §2.1)

- [x] Implement `CLAUDE_CODE_SESSION_ID` filtering and the multi-session ambiguity fallback so S2-S4
  turn green without disturbing S1, S5, or any of the 26 pre-existing assertions.

**Files modified:**
- `staging/plugin/scripts/hook-verify-workflow.sh`

**Contract — replace the AFTER-window computation (current line 96) and everything through the first
REFUTED branch (current lines 96-103) with:**
```bash
# Lines strictly after the marker. Field 1 is the timestamp; a lexical > is chronologically correct.
AFTER_RAW=$(awk -F'\t' -v m="$MARK" '$1 > m' "$LOG" 2>/dev/null)

# Session scoping (issue #33): when Claude Code exposes CLAUDE_CODE_SESSION_ID (Bash-tool subprocess
# env var, code.claude.com/docs/en/env-vars -- the same value as the session_id field in the audit
# log's own field 2), filter the AFTER window to this session and its subagents. Subagents dispatched
# within one session (Task/Agent tool, or a workflow agent()) share the parent's session_id --
# confirmed by pre-flight-pattern-enforce.sh's own subagent-transcript-path derivation, which nests
# under the SAME $SID a coder subagent's hook payload reports (ADR-0004). This is what actually
# distinguishes "my workflow's coder" from any other concurrent Claude Code session on this machine
# writing to the same global audit log.
#
# When the env var is unavailable, there is no reference id to compare rows against. If the window
# carries rows from more than one distinct session, refuse to guess (INCONCLUSIVE, exit 3) rather than
# pick a side. If exactly one session id appears, fall through to the original, session-blind logic --
# this is also what every pre-existing fixture in this test file exercises, since none of them set the
# env var or mix session ids (ADR-0029 Section 2.1).
#
# Known residual gap (ADR-0029 Section 4, Negative, disclosed and pinned by test S5): with the env var
# unavailable AND exactly one OTHER (not ours) concurrent session producing the only post-marker row,
# this script still cannot tell it apart from our own and reports VERIFIED on foreign evidence. No
# stronger guarantee is possible from a stateless, read-only script (see the script's own header).
SID_SELF="${CLAUDE_CODE_SESSION_ID:-}"
SESSION_SCOPE="none"

if [ -n "$SID_SELF" ]; then
  AFTER=$(printf '%s\n' "$AFTER_RAW" | awk -F'\t' -v sid="$SID_SELF" '$2 == sid')
  SESSION_SCOPE="$SID_SELF"
else
  DISTINCT_SIDS=$(printf '%s\n' "$AFTER_RAW" | awk -F'\t' 'NF>0{print $2}' | sort -u | wc -l | tr -d ' ')
  if [ "$DISTINCT_SIDS" -gt 1 ]; then
    printf 'HOOK_VERIFY status=INCONCLUSIVE\n'
    printf 'reason=%s\n' "CLAUDE_CODE_SESSION_ID is not set and $DISTINCT_SIDS different Claude Code sessions recorded pattern-enforce decisions after $MARK. Cannot tell which one ran this workflow's smoke test, so this is not evidence either way. Re-run when no other Claude Code session is active on this machine, or use a Claude Code CLI version that sets CLAUDE_CODE_SESSION_ID (code.claude.com/docs/en/env-vars)."
    printf 'RECOMMEND hook_verified=unchanged\n'
    exit 3
  fi
  AFTER="$AFTER_RAW"
fi

if [ -z "$AFTER" ]; then
  if [ -n "$SID_SELF" ] && [ -n "$AFTER_RAW" ]; then
    printf 'HOOK_VERIFY status=REFUTED\n'
    printf 'reason=%s\n' "no pattern-enforce decision recorded for this session (CLAUDE_CODE_SESSION_ID=$SID_SELF) after $MARK. Decisions were recorded after $MARK, but they belong to other, concurrent Claude Code session(s) and are not evidence for this session's workflow smoke test. Confirm the workflow in THIS session actually dispatched with agentType: 'coder', then re-run."
    printf 'RECOMMEND hook_verified=false\n'
    exit 1
  fi
  printf 'HOOK_VERIFY status=REFUTED\n'
  printf 'reason=%s\n' "no pattern-enforce decision recorded after $MARK. The guard never saw an Edit/Write. Either the workflow never dispatched, or hooks are disabled (check disableAllHooks, allowManagedHooksOnly, and the workspace trust dialog)."
  printf 'RECOMMEND hook_verified=false\n'
  exit 1
fi
```
The original, unfiltered "no lines after marker" message (last `printf`/`exit 1` pair above) is
**byte-identical** to today's current lines 99-102 — do not reword it.

**Contract — the summary `printf` (current lines 117-118) gains one field, everything else on those two
lines unchanged:**
```bash
printf 'HOOK_VERIFY decisions_after_mark=%s enforced_on_coder=%s bypassed_workflow_subagent=%s session_scope=%s\n' \
  "$TOTAL" "$ENFORCED" "$BYPASSED_WF" "$SESSION_SCOPE"
```
`ENFORCED`, `BYPASSED_WF`, and `TOTAL` themselves (current lines 108-115) are **untouched** — they
already read from `$AFTER`, which now holds the filtered set whenever `SID_SELF` is set, so no further
change is needed for the counts to be correctly scoped. The VERIFIED branch, the workflow-subagent
bypass REFUTED branch, and the final "ran in the main loop" REFUTED branch (current lines 120-137) are
**byte-identical, untouched**.

**Expected (GREEN):** S2, S3, S4 pass; S1, S5 unchanged (were already passing). All 26 pre-existing
assertions unaffected — traced individually in ADR-0029 §2.1/§2.5: none of their fixtures set
`CLAUDE_CODE_SESSION_ID` and none mix more than one session id, so every one of them takes the
`AFTER="$AFTER_RAW"` fallback branch exactly as before.

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/hook-verify-workflow.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/hook-verify-workflow.sh   # empty
bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh   # expect: 36 pass, 3 fail (S6-S8 still red, added in Task 3)
for t in phase1 prep hook-probe pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates concept-to-code-manifest-helpers-guards; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```
(Note: `hook-verify-workflow` itself is intentionally run directly above, not through the loop, since its
count is still non-zero until Task 4.)

---

## Task 3 — RED: Section "Exit-code contract sync (issue #33)" (S6-S8)

- [ ] Add the three static doc-sync assertions (S6-S8), genuine RED against today's header/SKILL.md text.

**Files modified:**
- `staging/plugin/scripts/tests/hook-verify-workflow.test.sh` (append after Task 1's section; add the
  `SKILL_MD` path derivation from "Fixture and path conventions" once, near the top alongside
  `SCRIPTS`/`V`).

**Contract — insert verbatim:**
```bash
# --- exit-code contract documentation stays in sync (issue #33) -------------------------------------

# S6 (static, genuine RED): the script's own header documents the second INCONCLUSIVE cause, not just
# the missing log.
grep -q 'CLAUDE_CODE_SESSION_ID is unset' "$V" \
  && ok "S6 header documents the session-ambiguity INCONCLUSIVE cause" \
  || no "S6 header should document the session-ambiguity INCONCLUSIVE cause"

# S7 (static, genuine RED): SKILL.md's exit-3 bullet no longer implies a missing audit log is the only
# INCONCLUSIVE cause.
grep -q 'CLAUDE_CODE_SESSION_ID` was unavailable and the post-marker window mixed rows' "$SKILL_MD" \
  && ok "S7 SKILL.md exit-3 bullet documents the second INCONCLUSIVE cause" \
  || no "S7 SKILL.md exit-3 bullet should document the second INCONCLUSIVE cause"

# S8 (static, genuine RED): SKILL.md's exit-1 bullet's failure enumeration also names the third
# REFUTED cause.
grep -q 'belongs to a different, concurrent Claude Code session' "$SKILL_MD" \
  && ok "S8 SKILL.md exit-1 bullet names the concurrent-session REFUTED cause" \
  || no "S8 SKILL.md exit-1 bullet should name the concurrent-session REFUTED cause"
```

**Expected now (RED):** S6, S7, S8 all fail (none of the three strings exist yet).

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/hook-verify-workflow.test.sh
bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh   # expect: 36 pass, 3 fail (S6, S7, S8)
```

---

## Task 4 — GREEN: header + `SKILL.md` doc-sync fix (ADR-0029 §2.2/§2.3)

- [ ] Update the script's exit-code header comment and `SKILL.md`'s exit-1/exit-3 bullets so S6-S8 turn
  green and the full file reaches 39/39.

**Files modified:**
- `staging/plugin/scripts/hook-verify-workflow.sh` (header comment only)
- `staging/plugin/skills/concept-to-code/SKILL.md` (two prose bullets only)

**Contract — `hook-verify-workflow.sh`, replace the exit-codes block (current lines 40-48):**
```
# Exit codes:
#   0  verified   — the guard enforced inside a workflow subagent. Record hook_verified=true.
#   1  refuted    — hooks did not enforce, or only a different, concurrent Claude Code session did.
#                    Record hook_verified=false. The reason says which failure.
#   2  usage
#   3  INCONCLUSIVE — either the audit log is missing/unreadable, or CLAUDE_CODE_SESSION_ID is unset
#      and the post-marker window mixes rows from more than one Claude Code session with no way to
#      tell which one is ours (issue #33). Record NOTHING either way.
#
# Exit 3 is the one that matters. A missing audit log means the guard is not installed; an ambiguous
# multi-session window means the evidence exists but cannot be attributed to this session. Neither
# means hooks fail to fire. Collapsing exit 3 into exit 1 would repeat, in the opposite direction,
# precisely the mistake the old terminal-watching procedure made.
```

**Contract — `hook-verify-workflow.sh`, insert a new paragraph immediately after the existing "Known
limit" line (current lines 30-33, ends "...Do not run this check while another coder agent is working
in the same session."):**
```
#
# Known limit (issue #33): when CLAUDE_CODE_SESSION_ID is unset (older CLI, or invoked outside a
# Claude Code subprocess) and exactly one OTHER Claude Code session -- not this one -- writes the
# only post-marker row, this script cannot tell it apart from our own session and still reports
# VERIFIED on foreign evidence. Session scoping (below) only closes the gap when the env var is set,
# or when 2+ concurrent sessions are involved (ambiguity is then detectable without knowing which one
# is ours). No stronger guarantee is possible from a stateless, read-only script reading a global log.
```

**Contract — `SKILL.md`, current lines 549-553 (exit-1 bullet), change only the failure enumeration
(the instruction to record `false` and take the fallback is unchanged):**
```
- **exit 1 (REFUTED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified false`.
  Proceed to Fallback (Agent-tool batch dispatch). The printed reason names which failure occurred:
  no decision recorded after the marker (hooks disabled, or the workflow never dispatched), every
  workflow agent reported `workflow-subagent` (the dispatch omitted `agentType: 'coder'` — a
  workflow-script bug, not a platform limitation), or every decision after the marker belongs to a
  different, concurrent Claude Code session (`CLAUDE_CODE_SESSION_ID` was set and filtered them out —
  issue #33).
```

**Contract — `SKILL.md`, current lines 554-556 (exit-3 bullet), full replacement:**
```
- **exit 3 (INCONCLUSIVE)** → record NOTHING, do not call `manifest-set-flag.sh`. Either the audit log
  is missing (`pre-flight-pattern-enforce.sh` is not installed — fix the install, then re-run), or
  `CLAUDE_CODE_SESSION_ID` was unavailable and the post-marker window mixed rows from more than one
  concurrent Claude Code session, so the check cannot tell which one is this session's (re-run when no
  other session is active, or on a CLI version that sets `CLAUDE_CODE_SESSION_ID` — issue #33). The
  printed `reason=` line names which of the two applies. **Never record `false` on exit 3.** Neither
  cause is evidence that hooks fail to fire.
```

**Expected (GREEN):** S6, S7, S8 pass. Full test file: **39/39 green**.

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/hook-verify-workflow.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/hook-verify-workflow.sh   # empty
bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh   # expect: 39 passed, 0 failed
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # full local test-cmd, 8/8 green
```

---

## Task 5 — Full regression sweep, bash-safety sweep, scope verification

- [ ] Run the full local test-cmd, the bash-3.2/BSD safety sweep, and confirm the change set matches the
  Pre-flight "writes are confined to" list exactly.

**Files modified:** none (verification only).

**Verify (full, repo-wide):**
```bash
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done    # local test-cmd, 8/8 green
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                       # unchanged, exit 0
bash -n staging/plugin/scripts/hook-verify-workflow.sh
bash -n staging/plugin/scripts/tests/hook-verify-workflow.test.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/hook-verify-workflow.sh staging/plugin/scripts/tests/hook-verify-workflow.test.sh   # empty
grep -nF '<<<' staging/plugin/scripts/hook-verify-workflow.sh staging/plugin/scripts/tests/hook-verify-workflow.test.sh   # empty
echo "bash 3.2 / BSD safety: clean"
diff <(git show HEAD:staging/plugin/scripts/hook-verify-workflow.sh) staging/plugin/scripts/hook-verify-workflow.sh
# manually confirm: --mark branch, marker-format case, missing-log INCONCLUSIVE branch (lines ~87-93),
# and the Usage: block are untouched; only the AFTER-window logic, the two REFUTED/INCONCLUSIVE
# branches around it, the summary printf, and the two header-comment regions changed.
grep -c "hook-verify-workflow" staging/plugin/skills/concept-to-code/SKILL.md   # 2, unchanged (both are --mark/--check invocation lines, not prose sites)
git status   # confirm change set matches Pre-flight "writes are confined to" list; nothing under ~/.claude
```

**Report to dispatcher (accumulate for Task 6):**
- Full local `test-cmd` glob result (8/8 files green) pasted verbatim.
- `hook-verify-workflow.test.sh` final tally: expect `39 passed, 0 failed` (26 original + 13 assertions across S1-S8).
- Confirmation the `hook-verify-workflow.sh` diff touches only the regions named in Pre-flight's scoping
  note above — nothing else.
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted.

---

## Task 6 — SPEC checkbox update, final report

- [ ] Check off SPEC.md's satisfied success criteria and produce the final report for the dispatcher.

**Files modified:**
- `SPEC.md` — check off the success-criteria boxes genuinely satisfied (expect all 4: test file gains
  the described cases; existing test cases still pass; bash 3.2 / BSD-awk clean; no `~/.claude` file
  modified).

**Report to dispatcher:**
- ADR path: `docs/architecture/ADR-0029-33-hook-verify-session-filter.md`.
- Plan path: `docs/superpowers/plans/2026-07-11-33-hook-verify-session-filter.md`.
- Spec path: `SPEC.md` (= `docs/specs/33-hook-verify-workflow-filter-the-audit-wi.spec.md`).
- `hook-verify-workflow.test.sh` final tally (`39 passed, 0 failed`) and full local test-cmd result
  (8/8 files green), pasted verbatim from Task 5.
- Explicit flag for the human reviewer: the environment variable used, `CLAUDE_CODE_SESSION_ID`, is
  **not** the literal name SPEC.md's own text uses (`CLAUDE_SESSION_ID`) — a verified correction
  (ADR-0029 §1 "External-dependency verification"), not a silent deviation; call this out explicitly at
  review time since a reviewer skimming SPEC.md's literal wording would not expect the name to differ.
- Explicit flag: a disclosed residual gap remains and is intentionally not closed by this fix — with
  `CLAUDE_CODE_SESSION_ID` unset and exactly one *other* concurrent session producing the only
  post-marker row, the check still reports a false VERIFIED (ADR-0029 §4 Negative; pinned by test S5).
- Explicit flag: the *deployed* copies (`~/.claude/skills/concept-to-code/scripts/hook-verify-workflow.sh`,
  `~/.claude/hooks/tests/hook-verify-workflow.test.sh`) keep today's false-positive-prone behavior until
  a human runs `sync-to-claude.sh --apply`.
- Explicit flag: issue #34's spec assumes a "global smoke-test record" this script does not write and
  never has (ADR-0029 §1 "Gap flagged for issue #34") — not addressed by this issue, left open for #34's
  own design.
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — using the SPEC's literal `CLAUDE_SESSION_ID` name instead of the verified
  `CLAUDE_CODE_SESSION_ID`.** If the coder implements the issue's literal text instead of following this
  plan's Task 2 contract exactly, the fix will pass every offline test (which fully controls its own env
  var name) while being a complete no-op in real usage — the most dangerous kind of defect, since it is
  invisible to the test suite. **Mitigation:** Task 2's contract gives the exact, verified variable name;
  do not "correct" it back to the SPEC's wording, and do not add a second, unverified alias (ADR-0029
  §3.1).
- **Risk B — accidentally scoping `ENFORCED`/`BYPASSED_WF`/`TOTAL` (current lines 108-115) to
  `$AFTER_RAW` instead of the now-filtered `$AFTER`.** This would silently undo the whole fix while
  still passing S1 (which does not distinguish the two) — S3's `decisions_after_mark=1` assertion is the
  one that would catch this specific mistake; do not weaken or remove it. **Mitigation:** Task 2's
  contract states explicitly that these three lines are untouched and already read `$AFTER`; verify
  after the edit that no line in the diff touches them.
- **Risk C — the `DISTINCT_SIDS -gt 1` fallback threshold being written as `-ge 1` (or similar
  off-by-one).** This would make every pre-existing fixture (all of which have exactly one distinct
  session id, `"sess"`) suddenly report INCONCLUSIVE instead of their original VERIFIED/REFUTED verdict,
  breaking all 26 pre-existing assertions at once. **Mitigation:** Task 1's checkpoint runs the full
  file immediately after Task 2's fix and expects the specific `36 pass, 3 fail` split — a mass failure
  of the *original* 26 assertions at that checkpoint is the signal this happened; halt and re-check the
  threshold rather than proceeding to Task 3.
- **Risk D — scope creep into `pre-flight-pattern-enforce.sh`, `hook-probe*`, or any other `SKILL.md`
  section beyond the two named bullets.** All three are tempting "fix while you're in there" edits (the
  guard being read, a structurally similar sibling script, and adjacent Step 5 prose). **Mitigation:**
  Pre-flight's "do not touch" list is explicit; Task 5's `git status` and targeted `diff` are the
  automated backstop.
- **Risk E — the deployed skill keeps the false-positive defect until sync.** Not a defect in this
  plan's own execution, but a real operational risk this plan cannot itself close. **Mitigation:**
  flagged with explicit priority in Task 6's report, matching ADR-0025/26/27/28 precedent.

## HITL gates

- No HITL gate inside this plan itself (auto mode; every edit is additive/corrective text or a
  conditional-guard addition to a read-only script; no destructive git operations; every live script
  invocation in Tasks 1-4 targets a disposable, isolated `mktemp -d` fixture, never the real, live
  `~/.claude/state/pattern-enforce/audit.log`).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push
  remain human-gated, as does the follow-up `sync-to-claude.sh --apply` that would actually deploy this
  fix (Risk E) — that sync is explicitly out of this plan's scope and requires its own separate human
  action.
- No DB schema change, no permanent deletion, no production migration in this plan — none of the
  invariant HITL triggers beyond the standard commit/push gate apply here.
