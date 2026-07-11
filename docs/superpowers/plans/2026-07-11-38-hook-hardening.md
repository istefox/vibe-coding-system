# Plan — Hook hardening: enum value, lock ownership, trust hash

**Date:** 2026-07-11
**ADR:** [ADR-0034](../../architecture/ADR-0034-38-hook-hardening.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/38-hook-hardening-enum-value-lock-ownership.spec.md`,
issue #38)
**Style:** TDD (red → green → checkpoint). Auto mode active, no intermediate HITL inside this plan;
commit/push stay HITL per repo `CLAUDE.md` invariant (see HITL gates, end of file). Five findings (four
from SPEC plus the disclosed `stop-gate.sh` companion — ADR-0034 §D3/§3.3), each gets its own RED→GREEN
pair; two closing tasks handle the docs-only retirement note and the full regression sweep.

**Task checklist (nine tasks — checked off by the coder as each completes; both `concept-to-code`
SKILL.md's Step 5 pre-dispatch check and `autopilot-build` SKILL.md's Check 5 grep this file for
`- [ ]`, so every task gets one):**

- [x] Task 1 — RED: create `hook-hardening.test.sh` with Test 1 (deny emission); update the legacy
  `tests/pre-flight-pattern-enforce.sh`'s two greps.
- [x] Task 2 — GREEN: `pre-flight-pattern-enforce.sh` — `block` → `deny`.
- [x] Task 3 — RED: add Test 2 (lock ownership) to `hook-hardening.test.sh`.
- [x] Task 4 — GREEN: `chain-memory-capture.sh` — trap only reachable after a real `mkdir` success.
- [x] Task 5 — RED: add Test 3a/3a-ii/3b (hash integrity) to `hook-hardening.test.sh`.
- [x] Task 6 — GREEN: `approve-test-cmd.sh` + `stop-gate.sh` — hash the real path, normalize for
  storage/lookup only.
- [x] Task 7 — RED→GREEN: `prompt-en-prose-detect.sh` dual envelope (Test 4/4b); wire
  `hook-hardening.test.sh` into `docs-ci.yml`.
- [x] Task 8 — Docs: `backup-before-deploy.sh` retirement — blueprint changelog entry +
  `sync-to-claude.sh` MANUAL STEP note. No `ADR-0005` or blueprint §7.6 edit (ADR-0034 §D5).
- [x] Task 9 — Full regression sweep, SPEC.md checkbox update, final report.

---

## Why every RED in this plan is genuine RED (and which assertions are regression pins, not RED)

Findings 1, 2, 3, 3b, and 5 were each confirmed by reading the current, unfixed script in full during
planning (ADR-0034 §1) — none is assumed from SPEC's line numbers alone; all line citations were
re-verified against the currently vendored copy. Two additional assertions in this plan are **not**
RED/GREEN pairs and are called out explicitly so a reviewer does not mistake an already-green result for
a weak test: **Test 3a-ii** (`stop-gate.sh` stays fail-open on an empty hash) verifies a contract this
plan deliberately does **not** change (ADR-0034 §D3) — it is a regression pin, green before and after
Task 6. **Test 4b** (a non-matching prompt stays silent) is the same kind of pin for
`prompt-en-prose-detect.sh`'s existing, unchanged keyword-gate behavior. Both are included because they
sit one line away from code this plan does touch, and a regression there would be easy to introduce
silently and easy to miss without a pin.

**Verified baseline, taken during planning, not assumed:**
```
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # 11/11 green
```
`staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh` (legacy, run directly, not part of the
glob above) reports `PASS=13 FAIL=0` against whatever is **currently deployed** at
`$HOME/.claude/hooks/pre-flight-pattern-enforce.sh` on this machine — confirming today's live hook still
emits `"block"`, matching its pre-fix expectation. After Task 1 updates its two greps to expect
`"deny"`, this same command is expected to report `PASS=11 FAIL=2` (tests 2 and 9) against that same,
still-unsynced deployed copy — **expected, not a regression** (ADR-0034 §D3/Consequences, Negative;
ADR-0024 §2.3).

## Fixture and path conventions (read once, applies to every task below)

- **New file:** `staging/plugin/scripts/tests/hook-hardening.test.sh`. Header: `unset
  CLAUDE_CODE_SESSION_ID` (issue #33 hermeticity convention — defensive; none of the five patched
  scripts reads it, confirmed by reading each in full during planning), then `SCRIPTS=$(cd
  "$(dirname "$0")/.." && pwd)` (matching `hook-verify-workflow.test.sh`'s own convention — resolves to
  `staging/plugin/scripts`), `TMP=$(mktemp -d)`, `trap 'rm -rf "$TMP"' EXIT`, `PASS=0; FAIL=0`, `ok()`/
  `bad()` helpers identical in shape to the existing 11 files. Every script under test is invoked as
  `"$SCRIPTS/<name>.sh"` — the `staging/` original, never `$HOME/.claude/hooks/...`.
- **Test numbering:** 1, 2, 3a, 3a-ii, 3b, 4, 4b — matches which ADR-0034 finding each covers (1↔D1,
  2↔D2, 3/3a/3a-ii/3b↔D3, 4/4b↔D4). Namespacing follows the existing harness convention of a numeric
  suffix on every fixture variable (`SID1`, `MEMDIR2`, `PROJ3A`, etc.).
- **Ambient env vars (issue #33 convention):** `unset CLAUDE_CODE_SESSION_ID` at file top (above).
  `PATTERN_ENFORCE_DIR`, `STOP_GATE_TRUST_FILE`, `STOP_GATE_STATE_DIR`, `STOP_GATE_UNAME` are this
  harness's own explicit per-test overrides, not ambient ones to guard against — every invocation in
  this file sets them explicitly, never relying on a default that could leak real `$HOME` state.
- **Portability of the finding-3/3b tests:** Test 3a and 3a-ii use a `PATH`-prepended stub-binary
  technique (deterministic, no filesystem dependency — see Task 5). Test 3b requires a genuinely
  case-sensitive filesystem to mean anything and uses a standard self-probe (`mkdir X; test -d x`) to
  `SKIP` (counted, not silently dropped) on a case-insensitive host such as this repo's own default
  macOS development machine, while running for real on `docs-ci.yml`'s `ubuntu-latest` runner (ext4).
- **Bash 3.2 / BSD safety (every file touched this plan):** no `${var,,}`/`${var^^}`, no `mapfile`, no
  `<()`, no `declare -A`. Every new test uses only constructs already present in the existing 11-file
  harness.
- **Per-task checkpoint (three checks, all must pass before moving to the next task):**
  1. `bash -n <every file touched this task>`.
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' <changed .sh file>` — must be empty.
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay green throughout (no
     task in this plan adds, removes, or edits a PAIRS entry — ADR-0034 Consequences, Negative,
     explicitly leaves `chain-memory-capture.sh`'s pre-existing missing entry unclosed).

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verified during planning, not assumed): all 11 files under
  `staging/plugin/scripts/tests/*.test.sh` green; legacy `tests/pre-flight-pattern-enforce.sh` reports
  `PASS=13 FAIL=0` against the currently-deployed hook (see above).
- Writes are confined to: `staging/plugin/scripts/pre-flight-pattern-enforce.sh`,
  `staging/plugin/scripts/chain-memory-capture.sh`, `staging/plugin/scripts/approve-test-cmd.sh`,
  `staging/plugin/scripts/stop-gate.sh`, `staging/plugin/scripts/prompt-en-prose-detect.sh`,
  `staging/plugin/scripts/tests/hook-hardening.test.sh` (new),
  `staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh` (legacy, greps only),
  `.github/workflows/docs-ci.yml` (one line, append-only), `docs/vibe-coding-system.md` (one new
  changelog entry, no other line), `staging/sync-to-claude.sh` (MANUAL STEP heredoc only, no PAIRS
  change), `SPEC.md` (checkbox updates, final task), `docs/architecture/` and
  `docs/superpowers/plans/` (already written by this ADR/plan pass).
- Do not touch: any file under `~/.claude` (read-only for this task — the deployed copies keep today's
  five bugs live until a separate, human-gated `sync-to-claude.sh --apply`, ADR-0034 Consequences,
  Negative), `docs/architecture/ADR-0005-vibe-status-skill.md` (left unedited by design, ADR-0034 §D5),
  `docs/vibe-coding-system.md` §7.6's `AS-BUILT 2026-05-19` tree body (left unedited, same decision),
  `staging/plugin/scripts/migrate-trust-paths.sh` (confirmed unaffected during planning — never hashes,
  only re-normalizes already-computed hashes' path strings), `staging/sync-to-claude.sh`'s `PAIRS` block
  (no entry added, changed, or removed by this plan), `staging/plugin/scripts/backup-before-deploy.sh`
  (does not exist in `staging/` — nothing to delete there; Task 8 is documentation only).
- `pre-flight-pattern-enforce.sh` edits are scoped exactly to: the `jq -nc` template and `printf`
  fallback (current lines 152-153) and one new header comment block (v1.5 entry). No other line changes.
- `chain-memory-capture.sh` edits are scoped exactly to the `mkdir` retry loop (current lines 147-149) —
  the `trap` line (current line 150) itself is untouched, only *when it is reached* changes.
- `approve-test-cmd.sh` edits reorder three existing statements (`TCF=`, the hash `if`/`elif`/`else`
  block, `ROOT=$(norm_path "$ROOT")`) and add one new abort line. No other line changes.
- `stop-gate.sh` edits move the `ROOT=$(norm_path "$ROOT")` line and introduce one new variable
  (`ROOT_NORM`) used only in the `LINE=` construction. `run_with_timeout`'s own body, the `emit_block`
  function, and every other line are untouched.
- `prompt-en-prose-detect.sh` edits are scoped to the final `python3 -c` block's `json.dumps(...)`
  argument only.

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` → exit 0 at every task's checkpoint,
  `PASS` count unchanged from this plan's own start (108, confirmed during planning) throughout.
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing under
  `~/.claude` is ever touched.
- The 10 hermetic test files this plan does not touch (`phase1`, `prep`, `hook-probe`,
  `hook-verify-workflow`, `clean-public-repo-history-safety`, `concept-to-code-bsd-autopilot-gates`,
  `concept-to-code-manifest-helpers-guards`, `scope-guards`, `refactor-snapshot-deep-refactor`,
  `claude-md-slim-content-union-whole-line`) stay green, unchanged, throughout.

---

## Task 1 — RED: create `hook-hardening.test.sh` (Test 1); update the legacy test's two greps

- [ ] Create the new hermetic test file with Test 1 (deny emission, targets `staging/` directly).
  Update `tests/pre-flight-pattern-enforce.sh`'s two `"permissionDecision":"block"` greps (its own
  Tests 2 and 9) to `"permissionDecision":"deny"`, plus their `ok`/`bad` label text.

**Files modified:**
- `staging/plugin/scripts/tests/hook-hardening.test.sh` (new).
- `staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh` (current lines 81-84 and 166-169 — the
  legacy harness's own Tests 2 and 9).

**Contract — `hook-hardening.test.sh`, full file header plus Test 1:**
```bash
#!/bin/bash
# hook-hardening.test.sh — offline, hermetic, no network, no $HOME dependency. Bash 3.2 clean.
# Covers issue #38 / ADR-0034's five findings, targeting staging/plugin/scripts/ directly (not
# the deployed $HOME/.claude/hooks/ copy the legacy pre-flight-pattern-enforce.sh test targets).
# Run: bash hook-hardening.test.sh
set -u

# Hermeticity: a live Claude Code session exports CLAUDE_CODE_SESSION_ID (issue #33 convention).
# None of the five scripts under test reads it (confirmed during planning); unset defensively.
unset CLAUDE_CODE_SESSION_ID

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# =====================================================================================
# Test 1 (finding 1 / D1): pre-flight-pattern-enforce.sh emits the verified "deny" enum
# member, not the legacy "block", when PATTERN: is missing from a coder subagent window.
FIXTURE_CWD="/test/hookhardening"
FIXTURE_ENC="-test-hookhardening"
SID1="hh1"; AID1="agent001"
PROJ_DIR1="$TMP/.claude/projects/$FIXTURE_ENC"
mkdir -p "$PROJ_DIR1/$SID1/subagents"
JSONL1="$PROJ_DIR1/$SID1/subagents/agent-$AID1.jsonl"
printf '{"type":"assistant","message":{"content":[{"text":"no pattern header here"}]}}\n' > "$JSONL1"
TP1="$PROJ_DIR1/$SID1.jsonl"
touch "$TP1"
PAYLOAD1=$(printf '{"session_id":"%s","tool_name":"Write","cwd":"%s","agent_type":"coder","agent_id":"%s","transcript_path":"%s"}' \
  "$SID1" "$FIXTURE_CWD" "$AID1" "$TP1")
OUT1=$(printf '%s' "$PAYLOAD1" | HOME="$TMP" PATTERN_ENFORCE_DIR="$TMP/state1" bash "$SCRIPTS/pre-flight-pattern-enforce.sh" 2>&1)
if printf '%s' "$OUT1" | grep -q '"permissionDecision":"deny"'; then
  ok "1: pre-flight-pattern-enforce.sh emits verified 'deny' (not legacy 'block')"
else
  bad "1: expected permissionDecision:deny, got: $OUT1"
fi
```

**Contract — `tests/pre-flight-pattern-enforce.sh`, Test 2 (current lines 76-85), replace the `if`
block:**
```bash
if grep -q '"permissionDecision":"deny"' "$TMP/o2"; then
  ok "2: deny PATTERN missing coder"
else
  bad "2: deny PATTERN missing coder (out=$(cat "$TMP/o2"))"
fi
```

**Contract — `tests/pre-flight-pattern-enforce.sh`, Test 9 (current lines 161-170), replace the `if`
block:**
```bash
if grep -q '"permissionDecision":"deny"' "$TMP/o9"; then
  ok "9: deny lowercase pattern (regex strict)"
else
  bad "9: deny lowercase pattern (out=$(cat "$TMP/o9"))"
fi
```
No other line in the legacy file changes — its `HOOK="$HOME/.claude/hooks/pre-flight-pattern-enforce.sh"`
(current line 14) stays pointed at the deployed copy, by design (ADR-0024 §2.3).

**Expected now (RED):**
- New file, Test 1: fails — the current, unfixed `staging/plugin/scripts/pre-flight-pattern-enforce.sh`
  still emits `"permissionDecision":"block"`.
- Legacy file: `bash staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh` now reports `PASS=11
  FAIL=2` (Tests 2 and 9 red) against the still-unfixed, still-deployed `$HOME/.claude/hooks/...` copy —
  expected and matches the Pre-flight baseline note above; this is not evaluated against `staging/` and
  will not turn green from any edit this plan makes to `staging/`.

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/hook-hardening.test.sh
bash -n staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh
bash staging/plugin/scripts/tests/hook-hardening.test.sh          # expect: PASS=0 FAIL=1
bash staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh   # expect: PASS=11 FAIL=2 (vs. deployed copy — informational)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 2 — GREEN: `pre-flight-pattern-enforce.sh` — `block` → `deny`

- [ ] Change both JSON emission sites from `"block"` to `"deny"`. Add a `v1.5` header entry matching
  the file's own existing changelog convention. Confirm Test 1 turns green.

**Files modified:**
- `staging/plugin/scripts/pre-flight-pattern-enforce.sh`

**Contract — header, insert after the existing `v1.4 fix` block (current lines 32-37), before the blank
line that precedes `DIR="${PATTERN_ENFORCE_DIR:-...}"` (current line 39):**
```bash
#
# v1.5 fix (2026-07-11, issue #38):
# - permissionDecision was "block", outside the verified enum (allow/deny/ask/defer,
#   ADR-0009). Changed to "deny" in both the jq template and the printf fallback.
#   A future Claude Code update that starts strictly validating this enum would
#   otherwise silently fail-open on every coder Edit/Write/MultiEdit — the exact
#   opposite of what this guardrail exists to do.
```

**Contract — replace current lines 151-153 (the `jq -nc` call and its `printf` fallback):**
```bash
jq -nc --arg r "pre-flight-pattern-enforce: PATTERN: header missing in sliding window. ADR-0001 requires emitting \`PATTERN: <CATEGORY> | <payload>\` before every Edit/Write/MultiEdit. Example: \`PATTERN: MODIFY | path/file.py:42 rename var\`. Emit the header and retry. If the block persists, STOP and report to the orchestrator — do NOT attempt to bypass or disable this guardrail." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"missing PATTERN header (see ADR-0001)"}}\n'
```
Current line 150 (`log_audit "$SID" "$TOOL" "block" "PATTERN missing in window=$WINDOW"`) is **not**
changed — its third argument is a free-text internal audit-log label (sibling values: `allow`,
`bypass-env`, `bypass-file`, `bypass-noncoder`, `fail-open`), not part of the JSON contract (ADR-0034
§D1).

**Expected (GREEN):** Test 1 passes. Legacy file's Tests 2/9 remain red against the still-deployed copy
(expected, unrelated to this task's own correctness — this task never writes to `$HOME`).

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/pre-flight-pattern-enforce.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/pre-flight-pattern-enforce.sh   # empty
bash staging/plugin/scripts/tests/hook-hardening.test.sh   # expect: PASS=1 FAIL=0
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 3 — RED: Test 2 (lock ownership)

- [ ] Add Test 2 to `hook-hardening.test.sh`, genuine RED against the current, unfixed
  `chain-memory-capture.sh`.

**Files modified:**
- `staging/plugin/scripts/tests/hook-hardening.test.sh` (append after Test 1's block).

**Contract — insert verbatim:**
```bash
# =====================================================================================
# Test 2 (finding 2 / D2): chain-memory-capture.sh does not delete a lock directory it
# never acquired, and skips the MEMORY.md upsert event on lock-acquisition timeout.
# Single-process, deterministic: pre-creates the lock dir to simulate a foreign holder —
# no real concurrency needed. Bounded: the unfixed code's own retry loop takes ~2s
# (40 * 0.05s) to exhaust before either behavior (old or new) is observable.
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP 2: jq not available on this host (informational, not a failure)"
else
  CMCWD="$TMP/cm2cwd"; CMHOME="$TMP/cm2home"
  mkdir -p "$CMCWD"
  ENC2=$(printf '%s' "$CMCWD" | tr '/' '-')
  MEMDIR2="$CMHOME/.claude/projects/$ENC2/memory"
  mkdir -p "$MEMDIR2"
  FORLOCK2="$MEMDIR2/.chain-memory.lock"
  mkdir -p "$FORLOCK2"   # simulate a foreign process already holding the lock
  MANIFEST2="$TMP/2026-07-11-hh2.manifest.yml"
  cat > "$MANIFEST2" <<EOF
current_step: step_e2_execute
status: in_progress
chain_path: standard
next_action: run tests
EOF
  TP2="$CMHOME/.claude/projects/$ENC2/sess2.jsonl"
  touch "$TP2"
  PAYLOAD2=$(printf '{"transcript_path":"%s","tool_input":{"command":"bash manifest-transition.sh %s step_e2_execute"},"tool_response":{"exit_code":0}}' \
    "$TP2" "$MANIFEST2")
  printf '%s' "$PAYLOAD2" | bash "$SCRIPTS/chain-memory-capture.sh" >"$TMP/o2cm" 2>&1
  rc2=$?
  if [ "$rc2" -eq 0 ] && [ -d "$FORLOCK2" ] && [ -f "$MEMDIR2/chain-history/hh2.md" ] && [ ! -f "$MEMDIR2/MEMORY.md" ]; then
    ok "2: foreign lock preserved, per-slug history written, MEMORY.md upsert skipped on timeout"
  else
    bad "2: lock ownership (rc=$rc2 lock=$([ -d "$FORLOCK2" ] && echo present || echo gone) hist=$([ -f "$MEMDIR2/chain-history/hh2.md" ] && echo yes || echo no) memory=$([ -f "$MEMDIR2/MEMORY.md" ] && echo written || echo absent))"
  fi
fi
```

**Expected now (RED):** fails on the `[ -d "$FORLOCK2" ]` and `[ ! -f "$MEMDIR2/MEMORY.md" ]` legs — the
current, unfixed script's `trap` fires unconditionally on exit and `rmdir`s the foreign lock even though
it never `mkdir`'d it, and its unlocked write proceeds into the MEMORY.md upsert regardless of the
timeout. Runs in ~2-3s (the loop's own bounded timeout), not instant — do not shorten this; the delay is
the mechanism being tested, not incidental.

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/hook-hardening.test.sh
bash staging/plugin/scripts/tests/hook-hardening.test.sh   # expect: PASS=1 FAIL=1
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 4 — GREEN: `chain-memory-capture.sh` lock ownership

- [ ] Restructure the `mkdir` retry loop so the `trap` line is reachable only through the
  mkdir-succeeded exit path. Confirm Test 2 turns green.

**Files modified:**
- `staging/plugin/scripts/chain-memory-capture.sh`

**Contract — replace current lines 145-150:**
```bash
LOCK="$MEM_DIR/.chain-memory.lock"
i=0
while ! mkdir "$LOCK" 2>/dev/null; do
  i=$((i+1))
  if [ "$i" -ge 40 ]; then
    # Timeout: a foreign lock is still held by another invocation. Do NOT proceed
    # unlocked (would race the concurrent writer) and do NOT fall through to the
    # trap below (would rmdir a lock this process never acquired — issue #38
    # finding 2). Skip this MEMORY.md upsert event; the per-slug chain-history
    # file above (section 7) is unaffected — it is not lock-protected because it
    # is not shared across invocations the way MEMORY.md is.
    exit 0
  fi
  sleep 0.05 2>/dev/null || exit 0
done
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
```
The `trap` line's own text is unchanged — only which exit paths can reach it changes. No line outside
this block (current lines 145-150) is touched.

**Expected (GREEN):** Test 2 passes.

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/chain-memory-capture.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/chain-memory-capture.sh   # empty
bash staging/plugin/scripts/tests/hook-hardening.test.sh   # expect: PASS=2 FAIL=0
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 5 — RED: Test 3a / 3a-ii / 3b (hash integrity)

- [ ] Add three assertions to `hook-hardening.test.sh`: `approve-test-cmd.sh` aborts on an empty hash
  (portable), `stop-gate.sh` keeps its fail-open contract on an empty hash (regression pin, already
  green), and a case-sensitivity-conditional end-to-end round-trip of both scripts together.

**Files modified:**
- `staging/plugin/scripts/tests/hook-hardening.test.sh` (append after Test 2's block).

**Contract — insert verbatim:**
```bash
# =====================================================================================
# Test 3a (finding 3 / D3): approve-test-cmd.sh aborts (nonzero exit) instead of writing
# a hash-less trust line when hash computation yields empty output. Portable: stubs
# shasum/sha256sum on PATH to simulate the failure deterministically — no filesystem
# case-sensitivity dependency, runs identically on every host.
STUBDIR="$TMP/stubbin3"; mkdir -p "$STUBDIR"
printf '#!/bin/bash\nexit 0\n' > "$STUBDIR/shasum"
printf '#!/bin/bash\nexit 0\n' > "$STUBDIR/sha256sum"
chmod +x "$STUBDIR/shasum" "$STUBDIR/sha256sum"

PROJ3A="$TMP/proj3a"; mkdir -p "$PROJ3A/.claude"
echo "echo hi" > "$PROJ3A/.claude/test-cmd"
TRUST3A="$TMP/trust3a"
PATH="$STUBDIR:$PATH" STOP_GATE_TRUST_FILE="$TRUST3A" bash "$SCRIPTS/approve-test-cmd.sh" "$PROJ3A" >"$TMP/o3a" 2>&1
rc3a=$?
if [ "$rc3a" -ne 0 ] && [ ! -s "$TRUST3A" ]; then
  ok "3a: approve-test-cmd.sh aborts on empty hash, no trust line written"
else
  bad "3a: approve-test-cmd.sh empty-hash guard (rc=$rc3a trust_has_content=$([ -s "$TRUST3A" ] && echo yes || echo no))"
fi

# Test 3a-ii: REGRESSION PIN, not a RED assertion (already green before Task 6 too) —
# stop-gate.sh's own, separate, pre-existing fail-open-on-internal-error contract
# (spec §7) must stay exactly as-is: exit 0, silent, no block, when hash computation
# fails. This fix does not and must not change stop-gate.sh's error-handling philosophy.
PROJ3AII="$TMP/proj3aii"; mkdir -p "$PROJ3AII/.claude"
echo "echo hi" > "$PROJ3AII/.claude/test-cmd"
SID3AII="stopgate3aii"
STATE3AII="$TMP/state3aii"; mkdir -p "$STATE3AII"
touch "$STATE3AII/$SID3AII.dirty"
PAYLOAD3AII=$(printf '{"session_id":"%s","cwd":"%s"}' "$SID3AII" "$PROJ3AII")
OUT3AII=$(printf '%s' "$PAYLOAD3AII" | PATH="$STUBDIR:$PATH" STOP_GATE_STATE_DIR="$STATE3AII" bash "$SCRIPTS/stop-gate.sh" 2>&1)
rc3aii=$?
if [ "$rc3aii" -eq 0 ] && [ -z "$OUT3AII" ]; then
  ok "3a-ii: stop-gate.sh stays fail-open (silent allow) when hash computation fails [regression pin]"
else
  bad "3a-ii: stop-gate.sh fail-open regression (rc=$rc3aii out='$OUT3AII')"
fi

# Test 3b (findings 3 + 3b together): on a case-sensitive filesystem, approve-test-cmd.sh
# computes the correct hash for a mixed-case project root, and stop-gate.sh subsequently
# recognizes it as trusted AND successfully cd's into the real (case-preserving) root to
# run the test command. rc alone cannot distinguish old vs. new code here — both fail
# open silently either way (that silence is the bug). The decisive signals are: (a) the
# trust line matches an independently-computed reference hash, and (b) the .dirty marker
# is actually cleared, which only happens after stop-gate.sh's run_with_timeout genuinely
# executes the command with rc=0 — proof the cd into the real path succeeded.
# Portable self-probe: SKIP (counted, not a false PASS/FAIL) on a case-insensitive host.
CASEDIR="$TMP/casecheck3b"; mkdir -p "$CASEDIR/MixedCase"
if [ -d "$CASEDIR/mixedcase" ]; then
  echo "SKIP 3b: host filesystem is case-insensitive, cannot exercise this path (informational)"
else
  PROJ3B="$TMP/CaseSensitiveProj3B"; mkdir -p "$PROJ3B/.claude"
  echo "echo marker3b" > "$PROJ3B/.claude/test-cmd"
  TRUST3B="$TMP/trust3b"
  STOP_GATE_TRUST_FILE="$TRUST3B" STOP_GATE_UNAME=Darwin bash "$SCRIPTS/approve-test-cmd.sh" "$PROJ3B" >"$TMP/o3b-approve" 2>&1
  rc3b_approve=$?
  EXPECT_HASH=$(shasum -a 256 "$PROJ3B/.claude/test-cmd" | awk '{print $1}')
  LOWER3B=$(printf '%s' "$PROJ3B" | tr '[:upper:]' '[:lower:]')
  TRUSTLINE_OK=0
  grep -F -x -q -- "$(printf '%s\t%s' "$EXPECT_HASH" "$LOWER3B")" "$TRUST3B" 2>/dev/null && TRUSTLINE_OK=1

  SID3B="stopgate3b"
  STATE3B="$TMP/state3b"; mkdir -p "$STATE3B"
  touch "$STATE3B/$SID3B.dirty"
  PAYLOAD3B=$(printf '{"session_id":"%s","cwd":"%s"}' "$SID3B" "$PROJ3B")
  OUT3B=$(printf '%s' "$PAYLOAD3B" | STOP_GATE_STATE_DIR="$STATE3B" STOP_GATE_TRUST_FILE="$TRUST3B" STOP_GATE_UNAME=Darwin bash "$SCRIPTS/stop-gate.sh" 2>&1)
  rc3b_stopgate=$?

  if [ "$rc3b_approve" -eq 0 ] && [ "$TRUSTLINE_OK" -eq 1 ] && [ "$rc3b_stopgate" -eq 0 ] \
     && [ -z "$OUT3B" ] && [ ! -f "$STATE3B/$SID3B.dirty" ]; then
    ok "3b: mixed-case root — approve writes the correct hash, stop-gate trusts it and runs the command"
  else
    bad "3b: mixed-case root (rc_approve=$rc3b_approve trustline_ok=$TRUSTLINE_OK rc_stopgate=$rc3b_stopgate out='$OUT3B' dirty_cleared=$([ ! -f "$STATE3B/$SID3B.dirty" ] && echo yes || echo no))"
  fi
fi
```

**Expected now (RED / pinned / conditional):**
- 3a: fails — the unfixed script writes a hash-less line (`rc=0`, trust file has content).
- 3a-ii: **already passes** today (regression pin, not RED — `stop-gate.sh`'s empty-hash path is
  untouched by this plan).
- 3b: on a case-sensitive host (CI), fails — `TRUSTLINE_OK` is 0 (unfixed `approve-test-cmd.sh` writes
  an empty-hash line that cannot match `EXPECT_HASH`) and `.dirty` is never cleared (unfixed
  `stop-gate.sh` independently fail-opens at its own empty-`H` check before ever running the command).
  On a case-insensitive host (this repo's own default dev machine): `SKIP`, not a failure.

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/hook-hardening.test.sh
bash staging/plugin/scripts/tests/hook-hardening.test.sh
# expect on a case-sensitive host: PASS=3 FAIL=2 (3a-ii and one prior stay green; 3a and 3b red)
# expect on a case-insensitive host (this repo's dev default): PASS=3 FAIL=1, 3b reported as SKIP
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 6 — GREEN: `approve-test-cmd.sh` + `stop-gate.sh` hash integrity

- [ ] Reorder both scripts to hash the pre-normalization (real, case-preserving) path;
  `approve-test-cmd.sh` additionally aborts on an empty digest. Confirm Tests 3a/3a-ii/3b turn/stay
  green.

**Files modified:**
- `staging/plugin/scripts/approve-test-cmd.sh`
- `staging/plugin/scripts/stop-gate.sh`

**Contract — `approve-test-cmd.sh`, replace current lines 25-31:**
```bash
# v4: hash the pre-normalization (case-preserving) path — this is the path that
# actually resolves on disk. Normalizing ROOT first (issue #38) could silently
# point shasum at a nonexistent lowercased path on a case-sensitive volume,
# yielding an empty digest without aborting.
TCF="$ROOT/.claude/test-cmd"
if command -v shasum >/dev/null 2>&1; then H=$(shasum -a 256 "$TCF" 2>/dev/null | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then H=$(sha256sum "$TCF" 2>/dev/null | awk '{print $1}')
else echo "approve-test-cmd: no sha256 tool available" >&2; exit 1; fi
[ -z "$H" ] && { echo "approve-test-cmd: hash computation failed for $TCF (empty digest) — aborting, not writing an invalid trust line" >&2; exit 1; }
# v4: normalize ROOT for case-invariant trust STORAGE only, after hashing.
ROOT=$(norm_path "$ROOT")
mkdir -p "$(dirname "$TRUST")" 2>/dev/null || true
```
Everything from `LINE=$(printf '%s\t%s' "$H" "$ROOT")` onward (current lines 32-40) is unchanged — `H`
and `ROOT` still have the same names and the same final values as before, just computed in the corrected
order. The trailing `CMD=$(awk ... "$TCF")` (current line 38) is also unchanged — `TCF` is now built
from the pre-normalization `ROOT` throughout the whole script, so this line's correctness improves too,
as a side effect, not a separate edit.

**Contract — `stop-gate.sh`, replace current lines 65-79:**
```bash
if [ -z "$ROOT" ]; then
  emit_block "Code modified without verification. Run the project tests, or declare the command in .claude/test-cmd (or 'NONE' to opt-out)."
fi
# v4: read/hash test-cmd on the pre-normalization (case-preserving) path — same fix as
# approve-test-cmd.sh (issue #38). ROOT is normalized afterward, into a SEPARATE
# variable, for the case-invariant trust LOOKUP only: run_with_timeout below still
# needs to cd into the real path, so ROOT itself is never overwritten in this script.
TCF="$ROOT/.claude/test-cmd"
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$TCF" 2>/dev/null)

[ "$CMD" = "NONE" ] && exit 0
[ -z "$CMD" ] && exit 0          # empty/unreadable test-cmd → fail-open (spec §7)
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else return 1; fi
}
H=$(sha256_of "$TCF") || { echo "stop-gate: no sha256 tool — fail-open" >&2; exit 0; }
[ -z "$H" ] && exit 0
ROOT_NORM=$(norm_path "$ROOT")
LINE=$(printf '%s\t%s' "$H" "$ROOT_NORM")
```
The `sha256_of` function body and the two fail-open guards (`[ "$CMD" = "NONE" ]`, `[ -z "$H" ]`) are
byte-identical to today — **deliberately not hardened to an abort**, unlike `approve-test-cmd.sh`
(ADR-0034 §D3/§3.3: different scripts, different failure philosophies, by original design). Below this
block, current lines 80-85 (`TRUSTED=0; [ -f "$TRUST" ] && grep ... "$LINE" ...; if [ "$TRUSTED" -ne 1
]; then emit_block ...\"$ROOT\"...; fi`) are **unchanged** — they already read `$LINE` (now built from
`$ROOT_NORM`, transparently) and `$ROOT` (the real path, now correctly preserved, used in the
human-facing message). Current lines 86-111 (`run_with_timeout`'s definition and its call, which does
`cd $(printf %q "$ROOT")`) are **entirely unchanged** — this is the reason `ROOT` itself must never be
reassigned in this script.

**Expected (GREEN):** Test 3a passes. Test 3a-ii stays passing (unchanged contract, confirmed not
regressed). Test 3b passes on a case-sensitive host; stays `SKIP` (not a new failure) on a
case-insensitive one.

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/approve-test-cmd.sh staging/plugin/scripts/stop-gate.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/approve-test-cmd.sh staging/plugin/scripts/stop-gate.sh   # empty
bash staging/plugin/scripts/tests/hook-hardening.test.sh   # expect: PASS=5 FAIL=0 (case-sensitive host) or PASS=4 FAIL=0 + 1 SKIP (case-insensitive)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 7 — RED→GREEN: `prompt-en-prose-detect.sh` dual envelope; wire `docs-ci.yml`

- [ ] Add Test 4 (dual envelope) and Test 4b (silent-on-no-match regression pin) to
  `hook-hardening.test.sh`; fix the script; append `hook-hardening` to `docs-ci.yml`'s explicit list.

**Files modified:**
- `staging/plugin/scripts/tests/hook-hardening.test.sh` (append after Test 3b's block).
- `staging/plugin/scripts/prompt-en-prose-detect.sh`
- `.github/workflows/docs-ci.yml`

**Contract — `hook-hardening.test.sh`, insert verbatim:**
```bash
# =====================================================================================
# Test 4 (finding 5 / D4): prompt-en-prose-detect.sh emits both the legacy top-level
# additionalContext key and the documented hookSpecificOutput envelope (verified against
# code.claude.com/docs during planning — ADR-0034 §1 Finding 5).
PAYLOAD4='{"prompt":"please draft a README section for this feature"}'
OUT4=$(printf '%s' "$PAYLOAD4" | bash "$SCRIPTS/prompt-en-prose-detect.sh" 2>&1)
rc4=$?
TOP4=$(printf '%s' "$OUT4" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('additionalContext',''))
except Exception:
    print('')" 2>/dev/null)
ENV4=$(printf '%s' "$OUT4" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))
except Exception:
    print('')" 2>/dev/null)
EVT4=$(printf '%s' "$OUT4" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('hookEventName',''))
except Exception:
    print('')" 2>/dev/null)
if [ "$rc4" -eq 0 ] && [ -n "$TOP4" ] && [ -n "$ENV4" ] && [ "$EVT4" = "UserPromptSubmit" ]; then
  ok "4: prompt-en-prose-detect.sh emits both top-level and hookSpecificOutput envelope forms"
else
  bad "4: dual-envelope (rc=$rc4 top='$TOP4' env='$ENV4' evt='$EVT4')"
fi

# Test 4b: REGRESSION PIN, not RED (already green before this task too) — a non-matching
# prompt must stay completely silent, unchanged by this fix.
PAYLOAD4B='{"prompt":"fix the off-by-one bug in the loop"}'
OUT4B=$(printf '%s' "$PAYLOAD4B" | bash "$SCRIPTS/prompt-en-prose-detect.sh" 2>&1)
rc4b=$?
if [ "$rc4b" -eq 0 ] && [ -z "$OUT4B" ]; then
  ok "4b: non-matching prompt stays silent (no tokens spent) [regression pin]"
else
  bad "4b: non-matching prompt regression (rc=$rc4b out='$OUT4B')"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
```
This closing block (`echo "----"` through the final `exit`) is the file's **last** statement — it
belongs at the very end of `hook-hardening.test.sh`, after Test 4b, not appended earlier by any prior
task.

**Contract — `prompt-en-prose-detect.sh`, replace current lines 28-43:**
```python
# Emit BOTH the top-level additionalContext key (legacy shape this script has always
# used) and the documented hookSpecificOutput envelope (issue #38 finding 5 — verified
# during planning against code.claude.com/docs, "Add context for Claude" section: the
# nested hookSpecificOutput.additionalContext form is the only documented valid shape
# for a UserPromptSubmit context injection; a bare top-level key is not documented
# anywhere). Emitting both is a zero-cost safety net — no live probe confirms which
# shape the currently-installed Claude Code version actually reads (ADR-0034 §D4/§3.4).
python3 -c "
import json
ctx = (
    'EN prose detected. Apply humanize-en rules: '
    'no em-dash (use comma or period instead), '
    'no delve/tapestry/leverage/foster/showcase/pivotal/seamless, '
    'no paragraph openers Additionally/Moreover/Furthermore, '
    'vary sentence length, '
    'active voice and name the actor, '
    'use is/has not serves-as/stands-as, '
    'no chatbot closers, specific details over vague claims. '
    'After drafting run /skill humanize-en for a final pass.'
)
print(json.dumps({
    'additionalContext': ctx,
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': ctx
    }
}))
" 2>/dev/null || true
```
The blank line and `exit 0` immediately following (original lines 44-45) are outside this replacement
range and stay exactly as they are — this contract touches only lines 28-43.

**Contract — `.github/workflows/docs-ci.yml`, replace the `for t in ...; do` line inside the
`shell-tests` job (current line, single line, append at the end of the list):**
```
          for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates concept-to-code-manifest-helpers-guards scope-guards refactor-snapshot-deep-refactor claude-md-slim-content-union-whole-line hook-hardening; do
```
Append-only — no existing entry reordered, edited, or removed, matching the ADR-0024 PAIRS discipline
extended here to this list. `.claude/test-cmd`'s own `*.test.sh` glob picks up the new file
automatically; no edit needed there.

**Expected (GREEN):** Test 4 passes. Test 4b stays passing (confirmed not regressed).
`hook-hardening.test.sh` reports `PASS=6 FAIL=0` on a case-sensitive host (7 assertions total, 3b
counted as passing) or `PASS=5 FAIL=0` plus one `SKIP` line on a case-insensitive host.

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/hook-hardening.test.sh staging/plugin/scripts/prompt-en-prose-detect.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/prompt-en-prose-detect.sh staging/plugin/scripts/tests/hook-hardening.test.sh   # empty
bash staging/plugin/scripts/tests/hook-hardening.test.sh
python3 -c "import yaml" 2>/dev/null && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/docs-ci.yml'))" && echo "docs-ci.yml: valid YAML"
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 8 — Docs: `backup-before-deploy.sh` retirement

- [ ] Add one blueprint changelog entry and one `sync-to-claude.sh` MANUAL STEP note. No edit to
  `ADR-0005` or blueprint §7.6 (ADR-0034 §D5 — both are dated, point-in-time illustrations, not
  live-status claims; corrected by reference through this ADR instead).

**Files modified:**
- `docs/vibe-coding-system.md` (one new changelog entry).
- `staging/sync-to-claude.sh` (one new paragraph inside the existing trailing heredoc).

**Contract — `docs/vibe-coding-system.md`, insert immediately after the current most-recent top-block
entry (`### Correction 2026-07-11 (project-bootstrap retired from staging)`, ending at current line
440) and before the next one (`### Update 2026-06-23 (workflow model pinning)`, starting at current line
441):**
```markdown
### Correction 2026-07-11 (backup-before-deploy.sh retired from staging)

`docs/specs/38-hook-hardening-enum-value-lock-ownership.spec.md` (issue #38, ADR-0034) confirms
`backup-before-deploy.sh` was never vendored into `staging/plugin/scripts/` by ADR-0024's vendoring
pass: its body is a hardcoded one-shot backup dated 2026-05-19, and it is wired to no hook event in the
deployed `settings.json`. It is retired; `docs/RUNBOOK.md` and `staging/sync-to-claude.sh`'s PAIRS table
name no further deploy path for it, and `staging/sync-to-claude.sh` now carries a MANUAL STEP note for a
human to review and delete the deployed-side copy (`~/.claude/hooks/backup-before-deploy.sh`) — this
repo does not write under `~/.claude`.

Deliberately **not** touched, and stated here so it is not later mistaken for an omission: sec. 7.6's
`AS-BUILT 2026-05-19` hook filesystem tree (`~line 1437`) and
`docs/architecture/ADR-0005-vibe-status-skill.md`'s own Q5 example report (`~line 201`) both name
`backup-before-deploy.sh`; both are dated, point-in-time illustrations, not live-status claims (the same
category the correction immediately above already applied to sec. 8.3's design catalog). ADR-0034 is
the amendment of record for this staleness, consistent with the precedent ADR-0033 already set for
`ADR-0005` itself (amended by reference, never edited in place). A repo-wide grep for
`backup-before-deploy` confirms these are its only two mentions anywhere in this document or in
`ADR-0005`; sec. 15's installation checklist and sec. 8.6's "Deployed custom skills" table — the two
locations this document's own convention treats as live-status claims — never named a hook at all, so
there is nothing to correct there.
```

**Contract — `staging/sync-to-claude.sh`, extend the existing trailing `cat <<'NOTE' ... NOTE` heredoc
(current lines ~150-159) with a second paragraph, inserted between the existing nightly-guard note and
the closing `NOTE` delimiter:**
```

--- MANUAL STEP: retired hook cleanup (not auto-applied) ---
backup-before-deploy.sh is retired (issue #38, ADR-0034): never vendored into staging/, so this
sync script has no PAIRS entry and no way to remove it from a deployed tree. If a deployed
~/.claude/hooks/backup-before-deploy.sh still exists, review it (it is wired to no hook event in
settings.json and its body is a hardcoded one-shot backup dated 2026-05-19) and delete it by hand
after confirming you no longer need that specific historical backup snapshot.
```
The existing nightly-guard MANUAL STEP paragraph and the `NOTE` delimiter itself are unchanged; this is
a pure insertion between them, inside the same heredoc, in the same style.

**Expected:** no test result changes — this task touches no script under test. The change is verified by
direct inspection (grep/diff), not a pass/fail assertion.

**Checkpoint:**
```bash
grep -n "backup-before-deploy.sh retired from staging" docs/vibe-coding-system.md
grep -n "MANUAL STEP: retired hook cleanup" staging/sync-to-claude.sh
bash -n staging/sync-to-claude.sh
npx markdownlint-cli2 "docs/vibe-coding-system.md" 2>&1 | tail -5   # informational — this file is large and pre-existing; confirm no NEW error introduced by this task's insertion specifically (compare against the pre-task baseline captured during planning)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh   # unaffected, must stay green
```

---

## Task 9 — Full regression sweep, SPEC checkbox update, final report

- [ ] Run the full local test-cmd, the bash-safety sweep, and confirm the change set matches
  Pre-flight's "writes are confined to" list exactly. Check off SPEC.md and report.

**Files modified:**
- `SPEC.md` — check off the four success-criteria boxes.

**Verify (full, repo-wide):**
```bash
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # 12/12 green (11 prior + hook-hardening)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                     # green, PASS unchanged from plan start (108)
bash staging/plugin/scripts/tests/hook-hardening.test.sh                         # final tally, paste verbatim in the report
bash staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh                  # legacy, vs. deployed copy — PASS=11 FAIL=2 expected (informational, not a gate)
bash -n staging/plugin/scripts/pre-flight-pattern-enforce.sh staging/plugin/scripts/chain-memory-capture.sh staging/plugin/scripts/approve-test-cmd.sh staging/plugin/scripts/stop-gate.sh staging/plugin/scripts/prompt-en-prose-detect.sh staging/plugin/scripts/tests/hook-hardening.test.sh staging/plugin/scripts/tests/pre-flight-pattern-enforce.sh staging/sync-to-claude.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/pre-flight-pattern-enforce.sh staging/plugin/scripts/chain-memory-capture.sh staging/plugin/scripts/approve-test-cmd.sh staging/plugin/scripts/stop-gate.sh staging/plugin/scripts/prompt-en-prose-detect.sh staging/plugin/scripts/tests/hook-hardening.test.sh   # empty
npx markdownlint-cli2 "docs/architecture/ADR-0034-38-hook-hardening.md" "docs/vibe-coding-system.md"   # ADR must be clean; blueprint result compared against its pre-task baseline (Task 8)
git status   # confirm change set matches Pre-flight's list exactly; nothing under ~/.claude; no ADR-0005 edit
```

**SPEC.md — check off:**
```markdown
- [x] Harness tests cover: deny emission, lock timeout leaves the foreign lock in place, approve-test-cmd aborts on empty hash, prose-detect output parses and carries both keys
- [x] No documentation still lists backup-before-deploy.sh as an active hook
- [x] Scripts stay bash 3.2 clean
- [x] No file under `~/.claude` modified
```

**Report to dispatcher:**
- ADR path: `docs/architecture/ADR-0034-38-hook-hardening.md`.
- Plan path: `docs/superpowers/plans/2026-07-11-38-hook-hardening.md`.
- Spec path: `SPEC.md` (= `docs/specs/38-hook-hardening-enum-value-lock-ownership.spec.md`).
- `hook-hardening.test.sh` final tally, pasted verbatim, including whether Test 3b ran or `SKIP`ped
  (host filesystem case-sensitivity) — this determines whether finding 3b's CI-relevant coverage was
  exercised for real on this run or only structurally reviewed.
- Full local test-cmd result (12/12 files green) and the legacy `pre-flight-pattern-enforce.sh` tally
  against deployment (expected `PASS=11 FAIL=2`), pasted verbatim, with an explicit one-line note that
  the 2 failures are expected and deployment-coupled, not a regression from this plan.
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted.
- Explicit confirmation: `docs/architecture/ADR-0005-vibe-status-skill.md` was not touched.
- Explicit flag for the human reviewer: this plan patches `stop-gate.sh` in addition to the four files
  SPEC names — a disclosed scope extension (ADR-0034 §D3/§3.3), not an oversight; the reviewer should
  specifically confirm they agree with that call before merge.
- Explicit flag: deployed copies of all five patched scripts keep today's bugs live until a human runs
  `sync-to-claude.sh --apply`; `chain-memory-capture.sh` additionally still has no PAIRS entry after
  this plan (pre-existing gap, not closed here — ADR-0034 Consequences, Negative).
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — Test 3b never produces a real PASS on this repo's own default development machine**
  (case-insensitive APFS), only `SKIP`. **Mitigation:** the checkpoint commands throughout Tasks 5-9
  explicitly show both expected outcomes (case-sensitive host vs. case-insensitive host) so a `SKIP` is
  never mistaken for a failure or silently unnoticed; the final report explicitly names whether 3b ran
  or skipped on this run.
- **Risk B — Task 3's Test 2 takes a real ~2-3 seconds per run** (the lock-timeout loop must genuinely
  exhaust). **Mitigation:** this is bounded and small; do not attempt to shorten `chain-memory-capture.sh`'s
  own retry/timeout constants to speed up the test — that would change the fix's own production timing
  behavior for a test-speed convenience, not requested by SPEC or ADR-0034.
- **Risk C — the finding-3b scope extension (`stop-gate.sh`) was decided without a human turn in the
  loop** (auto mode). **Mitigation:** ADR-0034 §D3/§3.3 argues the case at length and this plan's Task 9
  report explicitly flags it for the human reviewer as a specific thing to confirm, rather than letting
  it pass unnoticed inside a larger diff.
- **Risk D — accidentally reassigning `ROOT` in place inside `stop-gate.sh`** (mirroring
  `approve-test-cmd.sh`'s simpler shape "for consistency") would silently reintroduce a `cd`-into-a-
  lowercased-nonexistent-path failure on exactly the case-sensitive volumes this fix targets.
  **Mitigation:** Task 6's contract is explicit and verbatim about the two-variable (`ROOT`/`ROOT_NORM`)
  shape and states the reason; Test 3b's `dirty_cleared` assertion is the automated backstop — a
  regression here shows up as 3b going red (or, worse, silently un-skippable-checked) rather than
  passing quietly.
- **Risk E — scope creep into `docs/RUNBOOK.md`, `migrate-trust-paths.sh`, the `sync-to-claude.sh`
  PAIRS block, or `chain-memory-capture.sh`'s missing PAIRS entry.** All four are adjacent, tempting
  "while you're in there" edits, none requested by SPEC or ADR-0034. **Mitigation:** Pre-flight's "do
  not touch" list is explicit; Task 9's `git status` is the automated backstop.
- **Risk F — the deployed copies of all five scripts keep every one of today's bugs live until sync.**
  Not a defect in this plan's own execution, but a real operational risk this plan cannot itself close
  (`~/.claude` is read-only for this task). **Mitigation:** flagged with explicit priority in Task 9's
  report, matching ADR-0024 through ADR-0033 precedent.

## HITL gates

- No HITL gate inside this plan itself (auto mode; every edit is additive/corrective to scripts, one new
  test file, and docs already staged; every live script invocation across all nine tasks targets a
  disposable, isolated `mktemp -d` fixture, never the real, live `~/.claude` state — the one exception,
  the legacy `tests/pre-flight-pattern-enforce.sh`, is read-only against the deployed hook by its own
  long-standing design, unchanged by this plan).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push
  remain human-gated, as does the follow-up `sync-to-claude.sh --apply` that would actually deploy these
  five fixes (Risk F) — that sync is explicitly out of this plan's scope and requires its own separate
  human action.
- The finding-3b scope extension (`stop-gate.sh`, Risk C) is a plan-time judgment call under auto mode,
  not a HITL bypass — it is surfaced loudly (ADR-0034, this plan's risk register, Task 9's report) for
  the human review that already gates commit/push, not skipped because auto mode is active.
- No DB schema change, no permanent deletion, no production migration in this plan — none of the other
  invariant HITL triggers apply here.
