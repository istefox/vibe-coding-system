# Plan — vibe-status: recursion guard and active-chains wiring

**Date:** 2026-07-11
**ADR:** [ADR-0033](../../architecture/ADR-0033-37-vibe-status-recursion-chains.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/37-vibe-status-recursion-guard-and-active-c.spec.md`,
issue #37, confirmed byte-identical)
**Style:** TDD (red → green → checkpoint). Auto mode active, no intermediate HITL inside this plan;
commit/push stay HITL per repo `CLAUDE.md` invariant (see HITL gates, end of file). Three findings, each
gets its own RED→GREEN pair; a final task runs the full regression sweep and closes SPEC.md.

**Task checklist (eight tasks — checked off by the coder as each completes; both `concept-to-code`
SKILL.md's Step 5 pre-dispatch check and `autopilot-build` SKILL.md's Check 5 grep this file for
`- [ ]`, so every task gets one):**

- [ ] Task 1 — RED: add Test 14 (PGID-scoped group-kill) and Test 15 (recursion guard, hermetic) to
  `tests/run-tests.sh`.
- [ ] Task 2 — GREEN: rewrite `harness-runner.sh` on bash job control; kill the whole process group.
- [ ] Task 3 — GREEN: recursion guard in `aggregate.sh`; simplify Test 10 (remove dead fixture code).
- [ ] Task 4 — RED: add Test 16 (`MEMORY.md` zero-entries count) to `tests/run-tests.sh`.
- [ ] Task 5 — GREEN: fix the `grep -c` count guard in `aggregate.sh` (ADR-0028 idiom).
- [ ] Task 6 — RED: add Test 17 (chain-memory wiring) to `tests/run-tests.sh`.
- [ ] Task 7 — GREEN: execute the ADR-0021 wiring — `aggregate.sh`, `SKILL.md`, `INTEGRATION.md`,
  `sync-to-claude.sh` PAIRS.
- [ ] Task 8 — Full regression sweep, SPEC.md checkbox update, final report.

---

## Why every RED in this plan is genuine RED

Findings 1a (recursion) and 1b (orphaned process group) were both empirically reproduced against the
real, unfixed code during planning (ADR-0033 §1) — not assumed. Finding 2 (Memory count) is the
identical bug class already fixed once in this codebase (ADR-0028 §2.1); its RED reproduces the same
mechanism on a new fixture. Finding 3 (chain-memory wiring) has zero prior test coverage anywhere in the
repo (confirmed by a repo-wide grep during planning) — its RED simply proves the wiring is absent today
before Task 7 adds it. No test in this plan is a non-regression companion; all seven new assertions
(14-17, plus the Test 10 rewrite) are genuine RED at their own checkpoint.

## Fixture and path conventions (read once, applies to every task below)

- **File to extend:** `staging/plugin/skills/vibe-status/tests/run-tests.sh` (13 existing assertions
  today) — **do not create a sibling file**. Existing `TMP`/`SKILL`/`AGG`/`RUNNER`/`PASS`/`FAIL`/`ok`/`bad`
  variables and helpers (current lines 1-13) stay byte-identical.
- **Insertion point for Tests 14-17:** immediately after the existing Test 13 block's closing `fi` and
  blank line (current lines 181-182), directly before `echo "----"` (current line 183). Insert in order:
  14, 15 (Task 1), 16 (Task 4), 17 (Task 6) — each task appends after whatever the previous task already
  inserted, never between existing tests.
- **Header count comment** (current line 2, `# Dedicated harness for vibe-status skill — target
  PASS=13.`): updated to `PASS=17` in Task 6, once the final test (17) is added — not incrementally, to
  avoid a comment that is momentarily wrong between tasks.
- **Namespacing:** every new test's temp paths and variables use a `14`/`15`/`16`/`17` numeric suffix
  (`MARK14`, `TMP_REC`, `ENC16`, `CHAINHOME`, etc.), matching the file's own existing convention of
  per-test-numbered fixture names (`TMP_HOME`, `TMP_CWD`, `TMP_AN`, `ANCWD`, `ADRCWD` for tests 8/9/12/13).
- **Ambient env vars (issue #33 convention):** none of `aggregate.sh`/`harness-runner.sh` read any
  Claude-Code ambient env var (`CLAUDE_CODE_SESSION_ID` etc.) — confirmed by reading both files in full
  during planning. No `unset` is needed in this plan's new tests. `VIBE_STATUS_HARNESS_TIMEOUT` and the
  new `VIBE_STATUS_RECURSING` (Task 3) are this skill's own vars, deliberately set/read by the tests, not
  ambient ones to guard against.
- **Bash 3.2 / BSD safety (every file touched this plan):** no `${var,,}`, no `mapfile`, no `<()`, no
  `declare -A`. `kill -TERM -- "-$P"` (negative-PID group kill) and `set -m` (job control) are POSIX
  shell builtins, not GNU-only — safe on bash 3.2 (this session verified all new `harness-runner.sh`
  logic directly against this machine's actual `/bin/bash` on `PATH`, confirmed bash 3.2.57, not a newer
  Homebrew bash shadowing it).
- **Per-task checkpoint (three checks, all must pass before moving to the next task):**
  1. `bash -n <every file touched this task>`.
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' <changed .sh file>` — must be empty.
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay green (Task 7 is the one
     task expected to change its outcome, from N/A-unaffected to still-green-with-one-more-PASS-line).

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verified during planning, not assumed):
  `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` → 11/11 files green
  (`.claude/test-cmd`'s own command). `staging/plugin/skills/vibe-status/tests/run-tests.sh` is **not**
  in this glob (CI-dark, `$HOME`-coupled by design, confirmed against `docs-ci.yml`'s explicit 11-file
  list during planning) and is run directly, by its own path, throughout this plan instead.
- Writes are confined to: `staging/plugin/skills/vibe-status/scripts/aggregate.sh`,
  `staging/plugin/skills/vibe-status/scripts/harness-runner.sh`,
  `staging/plugin/skills/vibe-status/tests/run-tests.sh`, `staging/plugin/skills/vibe-status/SKILL.md`,
  `staging/plugin/skills/vibe-status/INTEGRATION.md`, `staging/sync-to-claude.sh` (PAIRS block only),
  `SPEC.md` (checkbox updates, final task), `docs/architecture/` and `docs/superpowers/plans/` (already
  written by this ADR/plan pass).
- Do not touch: any file under `~/.claude` (read-only for this task; the deployed copies keep today's
  bugs until a separate, human-gated `sync-to-claude.sh --apply` — ADR-0033 §3.4/D1), `.github/workflows/
  docs-ci.yml` and `.claude/test-cmd` (neither globs `vibe-status/tests/run-tests.sh`, and this issue's
  scope does not ask to change that — ADR-0033 Consequences, Neutral), `chain-memory-section.sh` itself
  (its own internal STATE OF FACT parsing is untouched — only its *caller*, `aggregate.sh`, changes),
  `staging/plugin/skills/review-triage-fix/tests/run-tests.sh` (its vibe-status anchor only checks for
  the literal string `Vibe-Coding System Status` in `SKILL.md`, confirmed unaffected during planning —
  do not edit that file), any historical ADR (immutable — ADR-0005 is **amended by reference**, per this
  ADR's own front matter, never edited in place).
- `aggregate.sh` edits are scoped exactly to: the guard-var block after `RUNNER=...` (current line 25),
  the skills-discovery loop's `case` guard (current lines 36-42), the Memory count fix (current line
  180), the new `MEM_DIR` factoring (current lines 175-200) and the `chain-memory-section.sh` call
  inserted in the render section (current line 293/295 boundary). No other line changes — verify with a
  targeted diff in Task 8's checkpoint.
- `harness-runner.sh` is a near-full-body rewrite (current lines 10-39, the entire kill mechanism) but
  its **output contract is unchanged**: first line `RC=<n> DUR=<s>s`, then harness stdout/stderr;
  `RC=0`/`1`/`124`/`127` mean exactly what they meant before (verified empirically during planning for
  all four cases). The `RC=127` early-exit branches (current lines 12-13) are untouched.

## Anchor invariants (HARD — must stay true after every task)

- `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` → 11/11 green,
  unchanged throughout this entire plan (none of these 11 files are touched).
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` → exit 0 at every task's checkpoint.
- `grep -q 'Vibe-Coding System Status' staging/plugin/skills/vibe-status/SKILL.md` → still matches
  (review-triage-fix's anchor target, untouched by any task here).
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing under
  `~/.claude` is ever touched.

---

## Task 1 — RED: Test 14 (group-kill) and Test 15 (recursion guard)

- [ ] Add Test 14 (PGID-scoped, bounded-wait orphan check) and Test 15 (hermetic recursion-guard check)
  to `tests/run-tests.sh`. Confirm genuine RED against the current, unfixed `harness-runner.sh` and
  `aggregate.sh`.

**Files modified:**
- `staging/plugin/skills/vibe-status/tests/run-tests.sh` (append after current line 181-182, per
  "Fixture and path conventions").

**Contract — insert verbatim:**
```bash
# Test 14: harness-runner.sh timeout kills the WHOLE process group, not just the top PID
# (issue #37 finding 1b — a pre-fix branch kills only one PID, orphaning any grandchild the
# harness itself forked). PGID-scoped, bounded-wait ps assertion — not a fixed sleep, not a
# loose string pgrep.
mkdir -p "$TMP/orphanskill"
MARK14="$TMP/orphan-marker"; PIDFILE14="$TMP/orphan-pgid"
rm -f "$MARK14" "$PIDFILE14"
cat > "$TMP/orphanskill/slow.sh" <<EOF
#!/bin/bash
echo \$\$ > "$PIDFILE14"
( sleep 20; echo done >> "$MARK14" ) &
sleep 20
EOF
chmod +x "$TMP/orphanskill/slow.sh"
bash "$RUNNER" "$TMP/orphanskill/slow.sh" 2 >"$TMP/o14" 2>&1 &
R14=$!

w=0
while [ ! -s "$PIDFILE14" ] && [ $w -lt 5 ]; do sleep 1; w=$((w+1)); done
PGID14=$(cat "$PIDFILE14" 2>/dev/null | tr -d ' ')

wait "$R14" 2>/dev/null

SURVIVORS=1
if [ -n "$PGID14" ]; then
  i=0
  while [ $i -lt 8 ]; do
    if ! ps -eo pgid | tr -d ' ' | grep -qx "$PGID14"; then
      SURVIVORS=0
      break
    fi
    sleep 1; i=$((i+1))
  done
else
  SURVIVORS=2
fi

if [ "$SURVIVORS" -eq 0 ] && [ ! -f "$MARK14" ]; then
  ok "14: harness-runner.sh timeout kills the whole process group (PGID ${PGID14:-?} empty, no orphaned grandchild)"
else
  bad "14: orphan check failed (survivors=$SURVIVORS pgid=${PGID14:-none} marker=$([ -f "$MARK14" ] && echo present || echo absent))"
  [ -n "$PGID14" ] && kill -9 -- "-$PGID14" 2>/dev/null
fi

# Test 15: recursion guard caps vibe-status's self-invocation to exactly one nested level
# (issue #37 finding 1a). Fully hermetic: isolated fake $HOME, does not touch the real one.
TMP_REC="$TMP/recguard"
mkdir -p "$TMP_REC/.claude/skills/vibe-status/scripts" "$TMP_REC/.claude/skills/vibe-status/tests"
cp "$RUNNER" "$TMP_REC/.claude/skills/vibe-status/scripts/harness-runner.sh"
chmod +x "$TMP_REC/.claude/skills/vibe-status/scripts/harness-runner.sh"
MARK15="$TMP/recguard-marker"
rm -f "$MARK15"
cat > "$TMP_REC/.claude/skills/vibe-status/tests/run-tests.sh" <<EOF
#!/bin/bash
echo hit >> "$MARK15"
HOME="$TMP_REC" VIBE_STATUS_HARNESS_TIMEOUT=3 bash "$AGG" >/dev/null 2>&1
echo "PASS=1 FAIL=0"
EOF
chmod +x "$TMP_REC/.claude/skills/vibe-status/tests/run-tests.sh"

START15=$(date +%s)
HOME="$TMP_REC" VIBE_STATUS_HARNESS_TIMEOUT=3 bash "$AGG" >"$TMP/o15" 2>&1
rc15=$?
END15=$(date +%s); DUR15=$((END15 - START15))
hits15=$(wc -l < "$MARK15" 2>/dev/null | tr -d ' '); hits15="${hits15:-0}"

if [ $rc15 -eq 0 ] && [ "$hits15" = "1" ] && [ "$DUR15" -le 12 ]; then
  ok "15: recursion guard caps self-invocation to exactly one nested level (hits=1, ${DUR15}s)"
else
  bad "15: recursion guard (rc=$rc15 hits=$hits15 expected 1, dur=${DUR15}s)"
fi
# Cleanup for this specific RED-phase run: the unfixed aggregate.sh recurses unboundedly inside
# TMP_REC until harness-runner.sh's own per-level TMO bounds it — any stragglers still unwinding
# in the background are scoped to this fixture's own path, safe to force-clean here.
pkill -9 -f "$TMP_REC/.claude/skills/vibe-status" 2>/dev/null
true
```

**Expected now (RED):** Test 14 fails — the current `harness-runner.sh` (whichever of its three
branches this machine takes) does not kill the grandchild's process group; `SURVIVORS` stays `1` and/or
`MARK14` gets written. Test 15 fails — `hits15` is greater than `1` (the unfixed `aggregate.sh` recurses
into itself repeatedly within the ~3-4s bound imposed by the pre-existing, still-firing timeout
mechanism; empirically this session saw the recursion start immediately and multiple levels begin within
that window). Both complete in well under a minute; do not let a genuinely stuck run past ~60s — that
would itself indicate the empirical bound assumed in ADR-0033 §1 does not hold on this machine, and is
worth stopping to re-diagnose rather than raising the ceiling blindly.

**Checkpoint:**
```bash
bash -n staging/plugin/skills/vibe-status/tests/run-tests.sh
bash staging/plugin/skills/vibe-status/tests/run-tests.sh
# expect: 13 (existing) pass + Test 14 fail + Test 15 fail -> "PASS=13 FAIL=2"
ps -eo pgid,command | grep -i "orphanskill\|recguard" | grep -v grep   # should be empty after the run
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 2 — GREEN: `harness-runner.sh` process-group kill

- [ ] Replace the three-way `timeout`/`gtimeout`/manual branch with one job-control-based path. Confirm
  Test 14 turns green without disturbing Test 7 (pre-existing timeout contract) or the RC=0/1/127 paths.

**Files modified:**
- `staging/plugin/skills/vibe-status/scripts/harness-runner.sh`

**Contract — replace current lines 15-39 (from `START=$(date +%s)` through the final `exit 0`) with:**
```bash
START=$(date +%s)
OUT=$(mktemp)

# Job control ON: the backgrounded harness becomes the leader of its own new process group
# (its PGID equals its own PID, $P) regardless of what $H itself forks — no external timeout/
# gtimeout binary required (issue #37; empirically verified: kills a forked grandchild cleanly,
# zero stray job-control text on stderr, RC=0/1/124/127 contract unchanged).
set -m
bash "$H" >"$OUT" 2>&1 &
P=$!
(
  sleep "$TMO"
  kill -0 "$P" 2>/dev/null || exit 0
  kill -TERM -- "-$P" 2>/dev/null
  sleep 1
  kill -0 "$P" 2>/dev/null && kill -KILL -- "-$P" 2>/dev/null
) &
W=$!

wait "$P" 2>/dev/null; RC=$?
kill -9 "$W" 2>/dev/null; wait "$W" 2>/dev/null
set +m

# Any signal-terminated exit (128+signum, e.g. SIGTERM=143/SIGKILL=137) normalizes to the
# existing RC=124 "timeout" contract — unchanged behavior from the pre-fix manual-fallback branch.
[ "$RC" -gt 128 ] && RC=124

END=$(date +%s)
DUR=$((END - START))
echo "RC=$RC DUR=${DUR}s"
cat "$OUT"
rm -f "$OUT"
exit 0
```
Current lines 1-13 (header comment through the `RC=127` early-exit checks) are untouched. Update the
header comment's own summary line (current line 3, "Output format...") only if needed for accuracy — the
`RC=`/`DUR=` line format itself does not change, so no edit is required there.

**Expected (GREEN):** Test 14 passes. Test 7 (existing: slow harness with `TMO=2` → `RC=124`) stays
green. Test 15 stays **red** — expected, the recursion itself is not yet capped; that is Task 3.

**Checkpoint:**
```bash
bash -n staging/plugin/skills/vibe-status/scripts/harness-runner.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/vibe-status/scripts/harness-runner.sh   # empty
bash staging/plugin/skills/vibe-status/tests/run-tests.sh
# expect: 13 existing pass + Test 7 pass (already was) + Test 14 pass + Test 15 fail -> "PASS=14 FAIL=1"
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 3 — GREEN: recursion guard in `aggregate.sh`; simplify Test 10

- [ ] Add the `VIBE_STATUS_RECURSING` sentinel and the discovery-loop `case` guard. Remove Test 10's two
  dead-code blocks and add a wall-clock upper bound. Confirm Test 15 and the rewritten Test 10 both pass.

**Files modified:**
- `staging/plugin/skills/vibe-status/scripts/aggregate.sh`
- `staging/plugin/skills/vibe-status/tests/run-tests.sh` (Test 10 body only)

**Contract — `aggregate.sh`, insert immediately after current line 25 (`RUNNER=...`), before the blank
line and `# --- Section 1 ---` comment:**
```bash

# Recursion guard (issue #37): vibe-status's own harness (tests/run-tests.sh) calls this same
# script as part of testing itself (SKILL.md Discovery). Without a guard, every real invocation
# discovers and re-invokes its own skill's harness, which reaches aggregate.sh again, unbounded —
# empirically reproduced, not hypothetical (ADR-0033 §1). NESTED records whether this process was
# already inside an aggregate.sh sweep when it started (inherited via env export); a nested
# aggregate.sh skips re-discovering the vibe-status entry specifically, capping self-testing to
# exactly one level regardless of recursion depth elsewhere.
NESTED="${VIBE_STATUS_RECURSING:-0}"
export VIBE_STATUS_RECURSING=1
```

**Contract — `aggregate.sh`, current lines 36-42 (the skills-discovery `for` loop), insert one `case`
guard between the existing `[ -x "$h" ] || continue` line and `HARNESS_TOTAL=$((HARNESS_TOTAL + 1))`:**
```bash
  for h in "$HOME"/.claude/skills/*/tests/run-tests.sh; do
    [ -f "$h" ] || continue
    [ -x "$h" ] || continue
    case "$h" in
      */skills/vibe-status/tests/run-tests.sh) [ "$NESTED" = "1" ] && continue ;;
    esac
    HARNESS_TOTAL=$((HARNESS_TOTAL + 1))
    name=$(basename "$(dirname "$(dirname "$h")")")
    ( bash "$RUNNER" "$h" "$TMO" >"$TMP/$name.out" 2>&1 ) &
  done
```
The `hooks/tests/*.sh` discovery loop (current lines 44-50) is untouched — no hook harness calls back
into `aggregate.sh`.

**Contract — `tests/run-tests.sh`, replace Test 10's full body (current lines 103-124, from the `# Test
10:` comment through its closing `fi`) with:**
```bash
# Test 10: skills/*/tests/run-tests.sh + hooks/tests/*.sh harness discovery finds >= 5 harnesses,
# with the recursion guard active (issue #37) — no unbounded self-recursion, no hang.
START10=$(date +%s)
VIBE_STATUS_HARNESS_TIMEOUT=4 bash "$AGG" >"$TMP/o10_full" 2>&1
rc10=$?
END10=$(date +%s); DUR10=$((END10 - START10))
harness_total=$(grep -E '^## Harness \(' "$TMP/o10_full" | sed -n 's/.*(\([0-9]*\)\/\([0-9]*\) passing).*/\2/p')
harness_total="${harness_total:-0}"
if [ $rc10 -eq 0 ] && [ "$harness_total" -ge 5 ] && [ "$DUR10" -le 15 ]; then
  ok "10: skills+hooks harness discovery (found ${harness_total} >= 5, ${DUR10}s, no recursion hang)"
else
  bad "10: harness discovery (found ${harness_total} < 5, rc=$rc10, dur=${DUR10}s)"
fi
```
This removes the unused `bash "$AGG" --skip-harness >"$TMP/o10"` write (current line 105) and the unused
`TMP_AGG_HOME` fixture (current lines 109-115) — both dead code, per ADR-0033 §1/§2.5. The kept
assertion is the same `>= 5` real-`$HOME` discovery check as before, now safe under the guard, plus a new
wall-clock ceiling as an explicit regression pin against the recursion returning unbounded.

**Expected (GREEN):** Test 15 passes (`hits15=1`). Test 10 passes (`harness_total` unchanged at ~16-17
on this machine, `DUR10` a few seconds, comfortably under 15s). All 13 original assertions (1-9, 11-13)
stay green — none of their logic depends on the discovery loop's self-entry, confirmed by re-reading each
during planning.

**Checkpoint:**
```bash
bash -n staging/plugin/skills/vibe-status/scripts/aggregate.sh staging/plugin/skills/vibe-status/tests/run-tests.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/vibe-status/scripts/aggregate.sh   # empty
bash staging/plugin/skills/vibe-status/tests/run-tests.sh
# expect: PASS=15 FAIL=0 (13 original + 14 + 15, Test 10 rewritten but still counted once)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 4 — RED: Test 16 (`MEMORY.md` zero-entries count)

- [ ] Add Test 16, genuine RED against the current `grep -c ... || echo 0` bug.

**Files modified:**
- `staging/plugin/skills/vibe-status/tests/run-tests.sh` (append after Test 15's block).

**Contract — insert verbatim:**
```bash
# Test 16: MEMORY.md with zero '- [' index entries renders a single-line count, not the
# two-line "0\n0..." the unfixed `grep -c ... || echo 0` produces (issue #37 finding 2, same
# bug class ADR-0028/#32 already fixed once in a sibling script).
MEMCWD="$TMP/memcwd"; MEMHOME="$TMP/memhome"
mkdir -p "$MEMCWD"
ENC16=$(printf '%s' "$MEMCWD" | tr '/' '-')
mkdir -p "$MEMHOME/.claude/projects/$ENC16/memory"
printf '# Memory index\n\nNo entries yet.\n' > "$MEMHOME/.claude/projects/$ENC16/memory/MEMORY.md"
( cd "$MEMCWD" && HOME="$MEMHOME" bash "$AGG" --skip-harness >"$TMP/o16" 2>&1 )
rc16=$?
mem16=$(grep -A1 '^## Memory$' "$TMP/o16" | tail -n 1)
if [ $rc16 -eq 0 ] && [ "$mem16" = "0 entries indexed in MEMORY.md" ]; then
  ok "16: MEMORY.md with zero index entries renders single-line '0 entries indexed'"
else
  bad "16: Memory zero-count (rc=$rc16 line='$mem16')"
fi
```

**Expected now (RED):** fails — `mem16` evaluates to `"0"` (the buggy code's first of two printed lines,
which `tail -n 1` after `grep -A1` picks up as the line immediately following the `## Memory` header),
not the full `"0 entries indexed in MEMORY.md"` string.

**Checkpoint:**
```bash
bash -n staging/plugin/skills/vibe-status/tests/run-tests.sh
bash staging/plugin/skills/vibe-status/tests/run-tests.sh
# expect: PASS=15 FAIL=1 (Test 16 red; 1-15 unaffected)
```

---

## Task 5 — GREEN: Memory count guard (ADR-0028 idiom)

- [ ] Fix `aggregate.sh`'s Memory count line. Confirm Test 16 turns green.

**Files modified:**
- `staging/plugin/skills/vibe-status/scripts/aggregate.sh`

**Contract — replace current line 180 (inside the existing `if [ -f "$MEM_FILE" ]; then` block from
§Task 7's `MEM_DIR` context — apply this fix independently of Task 7's later refactor; if Task 7 has not
yet run, `MEM_FILE` is still `"$HOME/.claude/projects/$ENC/memory/MEMORY.md"` unchanged):**
```bash
  pcount=$(grep -c '^\- \[' "$MEM_FILE" 2>/dev/null)
  if [ -z "$pcount" ]; then
    pcount=0
  fi
```
The surrounding `if [ -f "$MEM_FILE" ]; then` / `MEM_LINE="$pcount entries indexed in MEMORY.md"` /
`fi` lines (current lines 179, 181-182) are untouched.

**Expected (GREEN):** Test 16 passes. No other test's Memory-section expectations change (tests 1-13
never assert on `## Memory` content; only Test 16 does).

**Checkpoint:**
```bash
bash -n staging/plugin/skills/vibe-status/scripts/aggregate.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/vibe-status/scripts/aggregate.sh   # empty
bash staging/plugin/skills/vibe-status/tests/run-tests.sh
# expect: PASS=16 FAIL=0
```

---

## Task 6 — RED: Test 17 (chain-memory wiring)

- [ ] Add Test 17, genuine RED against today's unwired `aggregate.sh` (the section never appears).
  Update the header target-count comment to `PASS=17`.

**Files modified:**
- `staging/plugin/skills/vibe-status/tests/run-tests.sh` (append after Test 16's block; update line 2).

**Contract — header comment, current line 2:**
```bash
# Dedicated harness for vibe-status skill — target PASS=17.
```

**Contract — insert verbatim, after Test 16:**
```bash
# Test 17: chain-memory wiring — aggregate.sh calls chain-memory-section.sh at the right point
# with the right MEM_DIR argument (issue #37 finding 3, ADR-0021 follow-up; zero prior coverage
# anywhere in the repo, confirmed by a full grep during planning).
CHAINCWD="$TMP/chaincwd"; CHAINHOME="$TMP/chainhome"
mkdir -p "$CHAINCWD"
ENC17=$(printf '%s' "$CHAINCWD" | tr '/' '-')
CHAINHIST="$CHAINHOME/.claude/projects/$ENC17/memory/chain-history"
mkdir -p "$CHAINHIST"
cat > "$CHAINHIST/demo-chain.md" <<'EOF'
---
node_type: chain-history
topic: demo-chain
---

# Chain history — demo-chain

## STATE OF FACT
- current_step: step_e2_execute
- status: in_progress
- next_action: run tests
EOF
( cd "$CHAINCWD" && HOME="$CHAINHOME" bash "$AGG" --skip-harness >"$TMP/o17a" 2>&1 )
rc17a=$?

NOCHAINCWD="$TMP/nochaincwd"
mkdir -p "$NOCHAINCWD"
( cd "$NOCHAINCWD" && HOME="$CHAINHOME" bash "$AGG" --skip-harness >"$TMP/o17b" 2>&1 )
rc17b=$?

if [ $rc17a -eq 0 ] && grep -q '^## Active chains' "$TMP/o17a" && grep -q 'demo-chain' "$TMP/o17a" \
   && [ $rc17b -eq 0 ] && ! grep -q '^## Active chains' "$TMP/o17b"; then
  ok "17: chain-memory wiring — Active chains present with data, absent without"
else
  bad "17: chain-memory wiring (rc17a=$rc17a rc17b=$rc17b)"
fi
```
Note: `--skip-harness` is used deliberately (as in tests 4, 6, 8, 9, 11-13) — this test targets the
Memory/chain-history render path, not harness discovery, and skipping harness execution keeps it fast.

**Expected now (RED):** fails on both `grep -q '^## Active chains'` checks against `$TMP/o17a` — the
section does not exist yet in either output (the `rc17b`/absent-case checks trivially "pass" today since
the section is absent everywhere, but the overall `if` still fails on the `o17a` presence checks, so the
whole assertion reports red, as intended).

**Checkpoint:**
```bash
bash -n staging/plugin/skills/vibe-status/tests/run-tests.sh
bash staging/plugin/skills/vibe-status/tests/run-tests.sh
# expect: PASS=16 FAIL=1 (Test 17 red; 1-16 unaffected)
```

---

## Task 7 — GREEN: execute the ADR-0021 wiring

- [ ] Factor `MEM_DIR`, wire `chain-memory-section.sh` into `aggregate.sh`'s render path, update
  `SKILL.md` and `INTEGRATION.md`, add the `sync-to-claude.sh` PAIRS entry. Confirm Test 17 turns green.

**Files modified:**
- `staging/plugin/skills/vibe-status/scripts/aggregate.sh`
- `staging/plugin/skills/vibe-status/SKILL.md`
- `staging/plugin/skills/vibe-status/INTEGRATION.md`
- `staging/sync-to-claude.sh`

**Contract — `aggregate.sh`, insert immediately before current line 175 (`# --- Section 7: Memory head
---`... i.e. immediately before the comment that introduces Section 7):**
```bash
MEM_DIR="$HOME/.claude/projects/$ENC/memory"
```
Then, within Section 7 (current lines 176-182), change `MEM_FILE="$HOME/.claude/projects/$ENC/memory/
MEMORY.md"` to `MEM_FILE="$MEM_DIR/MEMORY.md"`. Within Section 7b (current lines 184-200), change
`AN_DIR="$HOME/.claude/projects/$ENC/memory/agent-notes"` to `AN_DIR="$MEM_DIR/agent-notes"`. No other
line in either section changes (Task 5's count-guard fix, already landed, is untouched by this rename).

**Contract — `aggregate.sh`, Markdown/plain render branch, insert immediately after current line 293
(`printf '## Memory\n%s\n\n' "$MEM_LINE"`), before current line 295 (`## Agent notes`):**
```bash
  bash "$HOME/.claude/skills/vibe-status/scripts/chain-memory-section.sh" "$MEM_DIR" || true
```
Exact call INTEGRATION.md already specifies. The `--json` branch is untouched (ADR-0033 §3.4, D2).

**Contract — `SKILL.md`, Discovery → Locale list (current lines 37-41), add one bullet after the
existing "Memory head" line:**
```
- Chain history: `~/.claude/projects/<encoded-cwd>/memory/chain-history/*.md` (active chains)
```

**Contract — `SKILL.md`, Output sample section (current lines 52-55), append one sentence:**
```
The `## Active chains` section appears when the memory store has one or more non-terminal
`concept-to-code` chains recorded (ADR-0021); it is omitted entirely when there are none.
```

**Contract — `INTEGRATION.md`, insert a status line immediately after the title (current line 1), before
the existing intro paragraph:**
```
**Status:** staging-side wiring executed 2026-07-11 (issue #37, ADR-0033). The Deploy section below
is the remaining, separate human step.
```
Replace the "Deploy (live, separate HITL step)" section's numbered `cp`/`chmod` instructions (current
lines 13-20) with:
```
Run the standard sync: `bash staging/sync-to-claude.sh --apply` (dry-run first, no `--apply`, to review
the diff). The PAIRS entry added by ADR-0033 covers `chain-memory-section.sh` alongside the other four
vibe-status files already synced (`SKILL.md`, `aggregate.sh`, `harness-runner.sh`, `tests/run-tests.sh`)
— no manual `cp`/`chmod` step is needed anymore.
```
The "SKILL.md edits" and "Why read-only" sections (current lines 31-41) are untouched — both already
describe exactly what Task 7 does.

**Contract — `sync-to-claude.sh`, `PAIRS` block, insert one line grouped with the other four vibe-status
entries (immediately after `plugin/skills/vibe-status/scripts/harness-runner.sh|skills/vibe-status/
scripts/harness-runner.sh`):**
```
plugin/skills/vibe-status/scripts/chain-memory-section.sh|skills/vibe-status/scripts/chain-memory-section.sh
```

**Expected (GREEN):** Test 17 passes. `pairs-completeness.test.sh`'s PASS count increases by exactly one
(the new entry), FAIL stays 0.

**Checkpoint:**
```bash
bash -n staging/plugin/skills/vibe-status/scripts/aggregate.sh staging/sync-to-claude.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/vibe-status/scripts/aggregate.sh   # empty
bash staging/plugin/skills/vibe-status/tests/run-tests.sh   # expect: PASS=17 FAIL=0
bash staging/plugin/scripts/tests/pairs-completeness.test.sh   # green, one more PASS line than before
```

---

## Task 8 — Full regression sweep, SPEC checkbox update, final report

- [ ] Run the full local test-cmd, the vibe-status harness, the bash-safety sweep, and confirm the
  change set matches Pre-flight's "writes are confined to" list exactly. Check off SPEC.md and report.

**Files modified:**
- `SPEC.md` — check off the four success-criteria boxes.

**Verify (full, repo-wide):**
```bash
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done    # local test-cmd, 11/11 green, unchanged
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                        # green
bash staging/plugin/skills/vibe-status/tests/run-tests.sh                           # PASS=17 FAIL=0
ps -eo pgid,command | grep -iE "orphanskill|recguard|vibe-status/tests" | grep -v grep   # empty — zero leftover processes anywhere in the repo tree
bash -n staging/plugin/skills/vibe-status/scripts/aggregate.sh
bash -n staging/plugin/skills/vibe-status/scripts/harness-runner.sh
bash -n staging/plugin/skills/vibe-status/tests/run-tests.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/vibe-status/scripts/*.sh staging/plugin/skills/vibe-status/tests/run-tests.sh   # empty
grep -q 'Vibe-Coding System Status' staging/plugin/skills/vibe-status/SKILL.md   # review-triage-fix anchor, still present
git status   # confirm change set matches Pre-flight's list exactly; nothing under ~/.claude
```
Run `npx markdownlint-cli2 "staging/plugin/skills/vibe-status/INTEGRATION.md"` for information only —
this path is inside the markdownlint config's `staging/plugin/skills` ignore glob (mirrored-verbatim
content, lint-exempt by design), so a non-zero result here does not block this task.

**Report to dispatcher:**
- ADR path: `docs/architecture/ADR-0033-37-vibe-status-recursion-chains.md`.
- Plan path: `docs/superpowers/plans/2026-07-11-37-vibe-status-recursion-chains.md`.
- Spec path: `SPEC.md` (= `docs/specs/37-vibe-status-recursion-guard-and-active-c.spec.md`).
- `vibe-status/tests/run-tests.sh` final tally (`PASS=17 FAIL=0`) and full local test-cmd result
  (11/11 files green), pasted verbatim.
- Explicit confirmation: `ps` sweep found zero leftover processes from any test fixture.
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted.
- Explicit flag for the human reviewer: `harness-runner.sh` no longer uses `timeout`/`gtimeout` at all
  (job control replaces both) — this is a bigger behavioral rewrite than the SPEC's own wording might
  suggest at a skim; ADR-0033 §2.2/§3.2 records the empirical verification and the rejected alternatives.
- Explicit flag: the deployed copies (`~/.claude/skills/vibe-status/...`) keep today's recursion and
  Memory-count bugs, and do not yet surface Active chains, until a human runs
  `sync-to-claude.sh --apply` (ADR-0033 §2.4/§3.4).
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — `set -m` behaves differently on a bash build this session did not test against.** This
  plan's empirical verification (ADR-0033 §2.2) ran on exactly one machine (bash 3.2.57, arm64 macOS).
  **Mitigation:** Test 7 (pre-existing) and Test 14 (new) both pin the observable contract; if either
  goes red on a different machine, that is the signal to re-diagnose `set -m`'s behavior there before
  assuming the fix is broadly safe, not a signal to weaken the assertions.
- **Risk B — Test 15's genuine-RED checkpoint (Task 1) takes unexpectedly long or leaves orphaned
  processes beyond the fixture's own scoped `pkill` cleanup.** The ~3-4s bound assumed in this plan rests
  on `harness-runner.sh`'s pre-existing timeout mechanism still firing correctly pre-fix (it does — only
  its *cleanup* is broken, not its *firing*). **Mitigation:** the RED-phase checkpoint's own `pkill -9 -f
  "$TMP_REC/..."` line is scoped tightly to that one fixture's unique path — safe to run even if the
  assumption is slightly off, and the "do not let a stuck run past ~60s" note in Task 1's Expected section
  is an explicit stop-and-re-diagnose signal, not a silent extension of the bound.
- **Risk C — the recursion guard's hardcoded path match (`*/skills/vibe-status/tests/run-tests.sh`)
  silently stops matching if this skill is ever renamed.** Accepted and disclosed, not fixed generically
  (ADR-0033 §3.1). **Mitigation:** none needed for this plan; flagged for whoever renames the skill in the
  future, should that ever happen.
- **Risk D — accidentally scoping Task 7's `MEM_DIR` refactor to break Section 7b's agent-notes
  freshness signal (existing Tests 12).** `AN_DIR` must resolve to the exact same path as before
  (`$HOME/.claude/projects/$ENC/memory/agent-notes`), just spelled via `$MEM_DIR`. **Mitigation:** Task
  7's checkpoint runs the full 17-assertion suite, which includes Test 12 — a regression there is the
  signal this happened; the fix is a pure string-refactor with no behavior change, so a red Test 12 means
  the refactor introduced a typo, not a design problem.
- **Risk E — scope creep into `chain-memory-section.sh` itself, `docs-ci.yml`, or `.claude/test-cmd`.**
  All three are adjacent, tempting "while you're in there" edits. **Mitigation:** Pre-flight's "do not
  touch" list is explicit; Task 8's `git status` is the automated backstop.
- **Risk F — the deployed skill keeps all three bugs live until sync.** Not a defect in this plan's own
  execution, but a real operational risk this plan cannot itself close (`~/.claude` is read-only for this
  task). **Mitigation:** flagged with explicit priority in Task 8's report, matching ADR-0024 through
  ADR-0032 precedent.

## HITL gates

- No HITL gate inside this plan itself (auto mode; every edit is additive/corrective to scripts and docs
  already staged; every live script invocation across all eight tasks targets a disposable, isolated
  `mktemp -d` fixture or an explicitly isolated fake `$HOME`, never the real, live `~/.claude` state
  except Test 10's own long-standing, deliberate real-`$HOME` discovery check, which is read-only by
  construction).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push
  remain human-gated, as does the follow-up `sync-to-claude.sh --apply` that would actually deploy this
  fix (Risk F) — that sync is explicitly out of this plan's scope and requires its own separate human
  action.
- No DB schema change, no permanent deletion, no production migration in this plan — none of the
  invariant HITL triggers beyond the standard commit/push gate apply here.
