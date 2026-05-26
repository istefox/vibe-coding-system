# Stop-gate testcmd (TOFU + 3-tier) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the heuristic Phase-A dirty-clearing with a deterministic 3-tier Stop gate driven by an explicit per-project `.claude/test-cmd`, executed authoritatively under trust-on-first-use, retiring `clear-dirty-on-test.sh`.

**Architecture:** Develop the rewritten gate as a STAGING file (`stop-gate.v2.sh`) tested via the bash harness against isolated state + temp project roots, so live behavior is unchanged until ONE HITL-gated migration task swaps it in, unwires `clear-dirty-on-test.sh`, and deletes it. New `approve-test-cmd.sh` is a user CLI (not a hook).

**Tech Stack:** bash, `jq`, `shasum`/`sha256sum`, Claude Code `Stop`/`PostToolUse`/`SessionStart`/`UserPromptSubmit` hooks, `settings.json`.

**Spec:** `docs/superpowers/specs/2026-05-19-swarm-testcmd-design.md` (supersedes agentic-swarm spec §4.1/§4.2/§4.5).

---

## Environment notes (read first)

- **No git here.** Writing-plans "commit" = **checkpoint**: harness green + report. The only live-global mutation is Task 8 (migration) behind an explicit HITL gate (diff shown → wait for Stefano).
- **Staging discipline:** the live `~/.claude/hooks/stop-gate.sh` (deployed Phase A, wired in settings.json) is NOT edited until Task 8. All new logic lives in `~/.claude/hooks/stop-gate.v2.sh` and is exercised by the harness via the `STOP_GATE_SCRIPT` path. This keeps every running session on the old gate until the single HITL swap.
- **Testability env vars** (the v2 script and harness honor all): `STOP_GATE_STATE_DIR` (dirty/count), `STOP_GATE_TRUST_FILE` (TOFU registry), `STOP_GATE_TEST_TIMEOUT`, `STOP_GATE_MAX_REENTRY`. Project root is discovered from the `cwd` field of the hook stdin JSON → tests inject a temp dir as `cwd`.
- **Fail-open is law (spec §7):** missing `jq`/sha256 tool, unparsable `session_id`, unreadable test-cmd, unwritable state, command timeout/not-runnable → `exit 0`, no block, never exit 2. Only the deliberate tiers block; all blocks are anti-loop bounded (spec §5).
- **§4.3 concretization:** upward project-root search walks `cwd` ancestors until a dir with `.claude/test-cmd` is found, stopping at `/` with a hard cap of 40 levels (deterministic, bounded; the spec's "$HOME ceiling" is realized as the 40-level/`/` bound — equivalent in practice, test-friendly).

## File structure

- Create `~/.claude/hooks/stop-gate.v2.sh` — rewritten gate (staging until Task 8).
- Create `~/.claude/hooks/approve-test-cmd.sh` — TOFU approval CLI (safe to add anytime; not a hook, inert until invoked).
- Modify `~/.claude/hooks/tests/run-hook-tests.sh` — append testcmd tier blocks.
- Task 8 only (HITL): Modify `~/.claude/settings.json` (remove the `clear-dirty-on-test.sh` PostToolUse `Bash` block); replace `~/.claude/hooks/stop-gate.sh` with v2; delete `~/.claude/hooks/clear-dirty-on-test.sh` (after backup).
- Unchanged: `mark-dirty.sh`, `ensure-state-dir.sh`, `reset-gate-counter.sh`.

---

### Task 1: v2 skeleton — fail-open + no-dirty allow + harness wiring

**Files:**
- Create: `~/.claude/hooks/stop-gate.v2.sh`
- Modify: `~/.claude/hooks/tests/run-hook-tests.sh`

- [ ] **Step 1: Write the failing test** — insert before the harness `echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"` line (preserve all existing blocks byte-for-byte):

```bash
# --- testcmd Task 1: v2 skeleton fail-open ---
V2="$HOOKS/stop-gate.v2.sh"
mkdir -p "$STOP_GATE_STATE_DIR"
# no .dirty → allow (exit 0, empty stdout)
O=$(echo '{"session_id":"v1","cwd":"/tmp","hook_event_name":"Stop"}' | bash "$V2" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ -z "$O" ] && ok "v2: no dirty → allow" || bad "v2 no dirty"
# no session_id → fail-open
O=$(echo '{"cwd":"/tmp"}' | bash "$V2" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ -z "$O" ] && ok "v2: no session_id → fail-open" || bad "v2 fail-open sid"
```

- [ ] **Step 2: Run, verify fail**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL: v2 no dirty` (script absent), non-zero exit; pre-existing checks still PASS.

- [ ] **Step 3: Create `~/.claude/hooks/stop-gate.v2.sh`**

```bash
#!/bin/bash
# Stop gate v2: explicit .claude/test-cmd + TOFU + 3-tier ladder.
# Contract: exit 0 + empty stdout = allow; exit 0 + {"decision":"block","reason":..} = block.
# Never exit non-zero / never block on internal error (fail-open, spec §7).
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
TRUST="${STOP_GATE_TRUST_FILE:-$DIR/trust}"
N="${STOP_GATE_MAX_REENTRY:-3}"; case "$N" in ''|*[!0-9]*) N=3;; esac
TMO="${STOP_GATE_TEST_TIMEOUT:-120}"; case "$TMO" in ''|*[!0-9]*) TMO=120;; esac

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

DIRTY="$DIR/$SID.dirty"
CF="$DIR/$SID.count"
[ ! -f "$DIRTY" ] && exit 0
exit 0
```

Then: `chmod +x ~/.claude/hooks/stop-gate.v2.sh`

- [ ] **Step 4: Run, verify pass**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `PASS: v2: no dirty → allow`, `PASS: v2: no session_id → fail-open`; all pre-existing PASS; `FAIL=0`.

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update. Live `stop-gate.sh` untouched.

---

### Task 2: helpers + "absent → nudge bounded" tier

**Files:** Modify `~/.claude/hooks/stop-gate.v2.sh`, `~/.claude/hooks/tests/run-hook-tests.sh`

- [ ] **Step 1: Write the failing test** — insert before the summary line:

```bash
# --- testcmd Task 2: absent → nudge bounded ---
mkdir -p "$STOP_GATE_STATE_DIR"
PR="$TMP/proj_absent"; mkdir -p "$PR"          # no .claude/test-cmd
: > "$STOP_GATE_STATE_DIR/v2a.dirty"; rm -f "$STOP_GATE_STATE_DIR/v2a.count"
O=$(echo "{\"session_id\":\"v2a\",\"cwd\":\"$PR\"}" | bash "$HOOKS/stop-gate.v2.sh" 2>/dev/null)
echo "$O" | grep -q '"decision":"block"' && [ "$(cat "$STOP_GATE_STATE_DIR/v2a.count")" = "1" ] \
  && ok "v2: absent → nudge block + count=1" || bad "v2 nudge"
echo 3 > "$STOP_GATE_STATE_DIR/v2a.count"
E=$(echo "{\"session_id\":\"v2a\",\"cwd\":\"$PR\"}" | bash "$HOOKS/stop-gate.v2.sh" 2>&1 1>/dev/null); r=$?
O=$(echo "{\"session_id\":\"v2a\",\"cwd\":\"$PR\"}" | bash "$HOOKS/stop-gate.v2.sh" 2>/dev/null)
[ $r -eq 0 ] && echo "$E" | grep -qi "anti-loop" && ! echo "$O" | grep -q '"decision":"block"' \
  && ok "v2: absent → anti-loop cap" || bad "v2 nudge cap"
```

- [ ] **Step 2: Run, verify fail**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL: v2 nudge` (no tier logic yet).

- [ ] **Step 3: Replace the tail of `stop-gate.v2.sh`** — replace the final two lines (`[ ! -f "$DIRTY" ] && exit 0` and `exit 0`) with:

```bash
[ ! -f "$DIRTY" ] && exit 0

emit_block() {  # $1 = reason text
  local count=0
  [ -f "$CF" ] && count=$(cat "$CF" 2>/dev/null || echo 0)
  case "$count" in ''|*[!0-9]*) count=0;; esac
  if [ "$count" -ge "$N" ]; then
    echo "stop-gate: guardrail anti-loop attivo — sbloccato dopo $N rientri. Verifica manualmente." >&2
    exit 0
  fi
  echo $((count + 1)) > "$CF" 2>/dev/null || true
  jq -nc --arg r "$1" '{decision:"block",reason:$r}' 2>/dev/null \
    || printf '{"decision":"block","reason":"verifica i test prima di concludere"}\n'
  exit 0
}

ROOT=""; d="$CWD"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -f "$d/.claude/test-cmd" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done

if [ -z "$ROOT" ]; then
  emit_block "Codice modificato senza verifica. Esegui i test del progetto, oppure dichiara il comando in .claude/test-cmd (o 'NONE' per opt-out)."
fi
exit 0
```

- [ ] **Step 4: Run, verify pass**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `PASS: v2: absent → nudge block + count=1`, `PASS: v2: absent → anti-loop cap`; `FAIL=0`.

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update.

---

### Task 3: parse `.claude/test-cmd` + opt-out `NONE` + empty → nudge

**Files:** Modify `~/.claude/hooks/stop-gate.v2.sh`, harness

- [ ] **Step 1: Write the failing test** — insert before the summary line:

```bash
# --- testcmd Task 3: NONE opt-out / empty ---
mkdir -p "$STOP_GATE_STATE_DIR"
PN="$TMP/proj_none/.claude"; mkdir -p "$PN"; printf 'NONE\n' > "$PN/test-cmd"
: > "$STOP_GATE_STATE_DIR/v3.dirty"; rm -f "$STOP_GATE_STATE_DIR/v3.count"
O=$(echo "{\"session_id\":\"v3\",\"cwd\":\"$TMP/proj_none\"}" | bash "$HOOKS/stop-gate.v2.sh" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ -z "$O" ] && ok "v2: NONE → fail-open allow" || bad "v2 NONE"
# comment + blank lines then NONE still works
printf '# header\n\nNONE\n' > "$PN/test-cmd"
O=$(echo "{\"session_id\":\"v3\",\"cwd\":\"$TMP/proj_none\"}" | bash "$HOOKS/stop-gate.v2.sh" 2>/dev/null)
[ -z "$O" ] && ok "v2: NONE after comments → allow" || bad "v2 NONE comments"
# empty test-cmd → fail-open allow (spec §7: degenerate declaration must not block globally)
PE="$TMP/proj_empty/.claude"; mkdir -p "$PE"; : > "$PE/test-cmd"
: > "$STOP_GATE_STATE_DIR/v3e.dirty"; rm -f "$STOP_GATE_STATE_DIR/v3e.count"
O=$(echo "{\"session_id\":\"v3e\",\"cwd\":\"$TMP/proj_empty\"}" | bash "$HOOKS/stop-gate.v2.sh" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ -z "$O" ] && ok "v2: empty test-cmd → fail-open allow" || bad "v2 empty"
```

- [ ] **Step 2: Run, verify fail**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL: v2 NONE` (no parse logic yet).

- [ ] **Step 3: Replace the final `exit 0` of `stop-gate.v2.sh`** (the one after the `if [ -z "$ROOT" ]` block) with:

```bash
TCF="$ROOT/.claude/test-cmd"
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$TCF" 2>/dev/null)

[ "$CMD" = "NONE" ] && exit 0
[ -z "$CMD" ] && exit 0          # empty/unreadable test-cmd → fail-open (spec §7)
exit 0
```

- [ ] **Step 4: Run, verify pass**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `PASS: v2: NONE → fail-open allow`, `PASS: v2: NONE after comments → allow`, `PASS: v2: empty test-cmd → nudge`; `FAIL=0`.

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update.

---

### Task 4: sha256 + TOFU check + "present unapproved → approve tier (NO exec)"

**Files:** Modify `~/.claude/hooks/stop-gate.v2.sh`, harness

- [ ] **Step 1: Write the failing test** — insert before the summary line:

```bash
# --- testcmd Task 4: unapproved → approve tier, NO execution ---
mkdir -p "$STOP_GATE_STATE_DIR"
export STOP_GATE_TRUST_FILE="$TMP/trust"; : > "$STOP_GATE_TRUST_FILE"
PA="$TMP/proj_app/.claude"; mkdir -p "$PA"
SENT="$TMP/SENTINEL_RAN"; rm -f "$SENT"
printf 'touch %s\n' "$SENT" > "$PA/test-cmd"      # if ever executed, sentinel appears
: > "$STOP_GATE_STATE_DIR/v4.dirty"; rm -f "$STOP_GATE_STATE_DIR/v4.count"
O=$(echo "{\"session_id\":\"v4\",\"cwd\":\"$TMP/proj_app\"}" | bash "$HOOKS/stop-gate.v2.sh" 2>/dev/null)
echo "$O" | grep -q '"decision":"block"' && echo "$O" | grep -q 'approve-test-cmd.sh' \
  && [ ! -f "$SENT" ] && ok "v2: unapproved → approve block, NOT executed" || bad "v2 approve tier"
```

- [ ] **Step 2: Run, verify fail**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL: v2 approve tier`.

- [ ] **Step 3: Replace the final `exit 0` of `stop-gate.v2.sh`** (after the empty-CMD line) with:

```bash
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else return 1; fi
}
H=$(sha256_of "$TCF") || { echo "stop-gate: nessun tool sha256 — fail-open" >&2; exit 0; }
[ -z "$H" ] && exit 0
LINE=$(printf '%s\t%s' "$H" "$ROOT")
TRUSTED=0
[ -f "$TRUST" ] && grep -F -x -q -- "$LINE" "$TRUST" 2>/dev/null && TRUSTED=1

if [ "$TRUSTED" -ne 1 ]; then
  emit_block "Comando test del progetto non approvato (TOFU). Rivedi $TCF ed esegui: bash ~/.claude/hooks/approve-test-cmd.sh \"$ROOT\" — poi i test gireranno automaticamente a fine task."
fi
exit 0
```

- [ ] **Step 4: Run, verify pass**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `PASS: v2: unapproved → approve block, NOT executed`; `FAIL=0`. (Sentinel file never created → command not executed.)

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update.

---

### Task 5: authoritative tier — run trusted cmd (green/red/timeout/hash-change)

**Files:** Modify `~/.claude/hooks/stop-gate.v2.sh`, harness

- [ ] **Step 1: Write the failing test** — insert before the summary line:

```bash
# --- testcmd Task 5: authoritative tier ---
mkdir -p "$STOP_GATE_STATE_DIR"; export STOP_GATE_TRUST_FILE="$TMP/trust"
PG="$TMP/proj_grn/.claude"; mkdir -p "$PG"; printf 'true\n' > "$PG/test-cmd"
HG=$( (command -v shasum >/dev/null && shasum -a 256 "$PG/test-cmd" | awk '{print $1}') || sha256sum "$PG/test-cmd" | awk '{print $1}')
printf '%s\t%s\n' "$HG" "$TMP/proj_grn" >> "$STOP_GATE_TRUST_FILE"
: > "$STOP_GATE_STATE_DIR/v5g.dirty"
O=$(echo "{\"session_id\":\"v5g\",\"cwd\":\"$TMP/proj_grn\"}" | bash "$HOOKS/stop-gate.v2.sh" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ -z "$O" ] && [ ! -f "$STOP_GATE_STATE_DIR/v5g.dirty" ] && ok "v2: approved green → clear+allow" || bad "v2 auth green"
# red
PRd="$TMP/proj_red/.claude"; mkdir -p "$PRd"; printf 'echo boom>&2; exit 1\n' > "$PRd/test-cmd"
HR=$( (command -v shasum >/dev/null && shasum -a 256 "$PRd/test-cmd" | awk '{print $1}') || sha256sum "$PRd/test-cmd" | awk '{print $1}')
printf '%s\t%s\n' "$HR" "$TMP/proj_red" >> "$STOP_GATE_TRUST_FILE"
: > "$STOP_GATE_STATE_DIR/v5r.dirty"; rm -f "$STOP_GATE_STATE_DIR/v5r.count"
O=$(echo "{\"session_id\":\"v5r\",\"cwd\":\"$TMP/proj_red\"}" | bash "$HOOKS/stop-gate.v2.sh" 2>/dev/null)
echo "$O" | grep -q '"decision":"block"' && echo "$O" | grep -qi 'test falliti' && ok "v2: approved red → block" || bad "v2 auth red"
# timeout → fail-open
PTo="$TMP/proj_to/.claude"; mkdir -p "$PTo"; printf 'sleep 5\n' > "$PTo/test-cmd"
HT=$( (command -v shasum >/dev/null && shasum -a 256 "$PTo/test-cmd" | awk '{print $1}') || sha256sum "$PTo/test-cmd" | awk '{print $1}')
printf '%s\t%s\n' "$HT" "$TMP/proj_to" >> "$STOP_GATE_TRUST_FILE"
: > "$STOP_GATE_STATE_DIR/v5t.dirty"
O=$(STOP_GATE_TEST_TIMEOUT=1 bash -c "echo '{\"session_id\":\"v5t\",\"cwd\":\"$TMP/proj_to\"}' | bash \"$HOOKS/stop-gate.v2.sh\" 2>/dev/null"); r=$?
[ $r -eq 0 ] && [ -z "$O" ] && ok "v2: timeout → fail-open allow" || bad "v2 auth timeout"
# hash changed after approval → back to approve tier
printf 'true # changed\n' > "$PG/test-cmd"
: > "$STOP_GATE_STATE_DIR/v5g.dirty"
O=$(echo "{\"session_id\":\"v5g\",\"cwd\":\"$TMP/proj_grn\"}" | bash "$HOOKS/stop-gate.v2.sh" 2>/dev/null)
echo "$O" | grep -q 'approve-test-cmd.sh' && ok "v2: hash changed → approve tier" || bad "v2 hash change"
```

- [ ] **Step 2: Run, verify fail**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL: v2 auth green` (no authoritative logic yet).

- [ ] **Step 3: Replace the final `exit 0` of `stop-gate.v2.sh`** (after the TRUSTED block) with:

```bash
run_with_timeout() {  # $1=secs $2=cmdstring → returns rc; 124=timeout 125=cannot-run
  if command -v timeout >/dev/null 2>&1; then timeout "$1" bash -c "$2"; return $?
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$1" bash -c "$2"; return $?
  else
    bash -c "$2" & local p=$!
    ( sleep "$1"; kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null ) & local w=$!
    wait "$p" 2>/dev/null; local rc=$?
    kill -9 "$w" 2>/dev/null; wait "$w" 2>/dev/null
    [ "$rc" -eq 137 ] && return 124
    return "$rc"
  fi
}
OUT="$DIR/.$SID.testout"
run_with_timeout "$TMO" "cd $(printf %q "$ROOT") && ( $CMD )" >"$OUT" 2>&1
RC=$?
if [ "$RC" -eq 124 ] || [ "$RC" -eq 125 ]; then
  echo "stop-gate: test timeout/non eseguibile — fail-open" >&2
  rm -f "$OUT" 2>/dev/null; exit 0
fi
if [ "$RC" -eq 0 ]; then
  rm -f "$DIRTY" "$OUT" 2>/dev/null || true
  exit 0
fi
TAIL=$(tail -c 600 "$OUT" 2>/dev/null); rm -f "$OUT" 2>/dev/null
emit_block "Test falliti (exit $RC). Coda output: $TAIL"
exit 0
```

- [ ] **Step 4: Run, verify pass**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `PASS` for `v2 auth green`, `v2 auth red`, `v2 timeout`, `v2 hash change`; `FAIL=0`.

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update. `stop-gate.v2.sh` now feature-complete.

---

### Task 6: `approve-test-cmd.sh` CLI

**Files:** Create `~/.claude/hooks/approve-test-cmd.sh`; modify harness

- [ ] **Step 1: Write the failing test** — insert before the summary line:

```bash
# --- testcmd Task 6: approve-test-cmd.sh ---
export STOP_GATE_TRUST_FILE="$TMP/trust6"; rm -f "$STOP_GATE_TRUST_FILE"
PC="$TMP/proj_apr/.claude"; mkdir -p "$PC"; printf 'pytest -q\n' > "$PC/test-cmd"
bash "$HOOKS/approve-test-cmd.sh" "$TMP/proj_apr" >/dev/null 2>&1; r=$?
HC=$( (command -v shasum >/dev/null && shasum -a 256 "$PC/test-cmd" | awk '{print $1}') || sha256sum "$PC/test-cmd" | awk '{print $1}')
[ $r -eq 0 ] && grep -F -x -q -- "$(printf '%s\t%s' "$HC" "$TMP/proj_apr")" "$STOP_GATE_TRUST_FILE" \
  && ok "approve: writes trust entry" || bad "approve writes"
# idempotent: second call → still one line
bash "$HOOKS/approve-test-cmd.sh" "$TMP/proj_apr" >/dev/null 2>&1
[ "$(grep -c . "$STOP_GATE_TRUST_FILE")" = "1" ] && ok "approve: idempotent" || bad "approve idempotent"
# subdir arg uses upward search
mkdir -p "$TMP/proj_apr/sub/deep"
bash "$HOOKS/approve-test-cmd.sh" "$TMP/proj_apr/sub/deep" >/dev/null 2>&1
[ "$(grep -c . "$STOP_GATE_TRUST_FILE")" = "1" ] && ok "approve: subdir upward search" || bad "approve subdir"
```

- [ ] **Step 2: Run, verify fail**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL: approve writes`.

- [ ] **Step 3: Create `~/.claude/hooks/approve-test-cmd.sh`**

```bash
#!/bin/bash
# TOFU approval CLI (NOT a hook). Usage: approve-test-cmd.sh [project-or-subdir]
# Records <sha256>\t<project-root> for the project's .claude/test-cmd. Never runs it.
TRUST="${STOP_GATE_TRUST_FILE:-${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}/trust}"
start="${1:-$PWD}"
[ -d "$start" ] || { echo "approve-test-cmd: path inesistente: $start" >&2; exit 1; }
start=$(cd "$start" 2>/dev/null && pwd) || { echo "approve-test-cmd: cd fallita" >&2; exit 1; }
ROOT=""; d="$start"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -f "$d/.claude/test-cmd" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done
[ -z "$ROOT" ] && { echo "approve-test-cmd: nessun .claude/test-cmd risalendo da $start" >&2; exit 1; }
TCF="$ROOT/.claude/test-cmd"
if command -v shasum >/dev/null 2>&1; then H=$(shasum -a 256 "$TCF" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then H=$(sha256sum "$TCF" | awk '{print $1}')
else echo "approve-test-cmd: nessun tool sha256" >&2; exit 1; fi
mkdir -p "$(dirname "$TRUST")" 2>/dev/null || true
LINE=$(printf '%s\t%s' "$H" "$ROOT")
if [ -f "$TRUST" ] && grep -F -x -q -- "$LINE" "$TRUST" 2>/dev/null; then
  echo "Già approvato: $ROOT"
  exit 0
fi
printf '%s\n' "$LINE" >> "$TRUST" || { echo "approve-test-cmd: scrittura registro fallita" >&2; exit 1; }
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$TCF")
echo "Approvato per $ROOT — comando reso autoritativo: $CMD"
exit 0
```

Then: `chmod +x ~/.claude/hooks/approve-test-cmd.sh`

- [ ] **Step 4: Run, verify pass**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `PASS: approve: writes trust entry`, `PASS: approve: idempotent`, `PASS: approve: subdir upward search`; `FAIL=0`.

- [ ] **Step 5: Checkpoint** — harness green; TodoWrite update.

---

### Task 7: full suite + spec coverage gate

**Files:** none (verification)

- [ ] **Step 1: Run full suite**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: final `PASS=<n> FAIL=0`, exit 0. All pre-existing (ensure-state-dir, mark-dirty, reset-gate-counter, old stop-gate, backup) PASS + all testcmd Tasks 1–6 PASS.

- [ ] **Step 2: End-to-end tier walk on a temp project**

Run:
```bash
T=$(mktemp -d); export STOP_GATE_STATE_DIR="$T/s" STOP_GATE_TRUST_FILE="$T/tr"; mkdir -p "$STOP_GATE_STATE_DIR" "$T/p/.claude"
printf 'true\n' > "$T/p/.claude/test-cmd"; : > "$STOP_GATE_STATE_DIR/e2e.dirty"
echo "unapproved:"; echo "{\"session_id\":\"e2e\",\"cwd\":\"$T/p\"}" | bash ~/.claude/hooks/stop-gate.v2.sh
bash ~/.claude/hooks/approve-test-cmd.sh "$T/p"
: > "$STOP_GATE_STATE_DIR/e2e.dirty"
echo "approved green (expect empty + dirty removed):"; echo "{\"session_id\":\"e2e\",\"cwd\":\"$T/p\"}" | bash ~/.claude/hooks/stop-gate.v2.sh; ls "$STOP_GATE_STATE_DIR/e2e.dirty" 2>/dev/null || echo "dirty cleared OK"
rm -rf "$T"; unset STOP_GATE_STATE_DIR STOP_GATE_TRUST_FILE
```
Expected: unapproved → block JSON mentioning `approve-test-cmd.sh`; after approve, green → empty output + "dirty cleared OK".

- [ ] **Step 3: Spec coverage check (self, inline)** — confirm spec §3 tiers (nudge/opt-out/approve/authoritative) all have passing tests; §6 TOFU (hash match + change); §7 fail-open (no-jq path via Task 1, timeout via Task 5, no-sha256 documented); §10 cases 1–10 mapped. Note any gap and add a test before Task 8.

- [ ] **Step 4: Checkpoint** — suite green, e2e walk correct.

---

### Task 8: MIGRATION — backup + swap + unwire + delete (HITL GATE)

**Files:** Modify `~/.claude/settings.json`; replace `~/.claude/hooks/stop-gate.sh`; delete `~/.claude/hooks/clear-dirty-on-test.sh`

- [ ] **Step 1: Backup FIRST (pristine, before any write)**

Run:
```bash
BK=~/.claude/state/backups/2026-05-19-swarm-testcmd; mkdir -p "$BK"
cp -p ~/.claude/settings.json "$BK/settings.json"
cp -p ~/.claude/hooks/stop-gate.sh "$BK/stop-gate.sh"
cp -p ~/.claude/hooks/clear-dirty-on-test.sh "$BK/clear-dirty-on-test.sh"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{ echo "# MANIFEST — 2026-05-19 swarm-testcmd"; echo;
  echo "- settings.json — modified — backup \`$BK/settings.json\` — $ts";
  echo "- hooks/stop-gate.sh — modified(replaced by v2) — backup \`$BK/stop-gate.sh\` — $ts";
  echo "- hooks/clear-dirty-on-test.sh — removed — backup \`$BK/clear-dirty-on-test.sh\` — $ts";
  echo "- hooks/approve-test-cmd.sh — created (backout=remove, HITL) — $ts";
  echo "- hooks/stop-gate.v2.sh — staging (backout=remove) — $ts"; } > "$BK/MANIFEST.md"
cat "$BK/MANIFEST.md"
```
Expected: MANIFEST printed with all four entries; backup files present.

- [ ] **Step 2: Compute the merged settings.json (NO write yet)**

Run:
```bash
jq '(.hooks.PostToolUse) |= map(select(
      (.hooks // []) | any(.command // "" | test("clear-dirty-on-test\\.sh")) | not))' \
   ~/.claude/settings.json > /tmp/settings.testcmd.json
jq -e . /tmp/settings.testcmd.json >/dev/null && echo VALID || echo INVALID
echo "=== DIFF (current → merged, sorted) ==="
diff <(jq -S . ~/.claude/settings.json) <(jq -S . /tmp/settings.testcmd.json)
```
Expected: `VALID`; diff shows ONLY removal of the `clear-dirty-on-test.sh` PostToolUse `Bash` block; `mark-dirty.sh`, `auto-format.sh`, `protect-files.sh`, `stop-gate.sh`, `ensure-state-dir.sh`, `reset-gate-counter.sh` entries untouched.

- [ ] **Step 3: HITL GATE — STOP, get explicit approval**

Present to Stefano: (a) the Step 2 diff, (b) MANIFEST path + that backup is pristine, (c) the rollback (spec §9: restore settings.json + stop-gate.sh from backup, recreate clear-dirty-on-test.sh from backup and re-wire its hook, remove approve/v2, fresh session). Ask explicit approval to: overwrite `settings.json`, replace `stop-gate.sh` with `stop-gate.v2.sh`, delete `clear-dirty-on-test.sh`. **Do not proceed without it.**

- [ ] **Step 4: Apply (only after approval)**

Run:
```bash
cp /tmp/settings.testcmd.json ~/.claude/settings.json && jq -e . ~/.claude/settings.json >/dev/null && echo "settings APPLIED"
cp ~/.claude/hooks/stop-gate.v2.sh ~/.claude/hooks/stop-gate.sh && chmod +x ~/.claude/hooks/stop-gate.sh && echo "stop-gate SWAPPED"
rm -f ~/.claude/hooks/clear-dirty-on-test.sh && echo "clear-dirty-on-test REMOVED"
```
Expected: `settings APPLIED`, `stop-gate SWAPPED`, `clear-dirty-on-test REMOVED`.

- [ ] **Step 5: Post-migration regression**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL=0`. (Old-stop-gate harness checks still target behavior now served by v2 content; testcmd checks invoke `stop-gate.v2.sh` which is byte-identical to the live `stop-gate.sh`.) Note: the legacy harness block "Task 5 clear-dirty" tests the now-deleted script via the harness's own temp copy expectation — if it references `$HOOKS/clear-dirty-on-test.sh`, mark that block obsolete in this step: replace its 3 assertions with `ok "clear-dirty retired (testcmd design)"` x1 and remove the other 2 lines, then re-run; expected `FAIL=0`.

- [ ] **Step 6: Checkpoint** — migration applied behind HITL; rollback ready.

---

### Task 9: Declarations & validation (Stefano-run pieces)

**Files:** Create `~/Developer/vibe-coding-system/.claude/test-cmd`; pilot declarations

- [ ] **Step 1: Opt-out this doc-only repo**

Run: `mkdir -p ~/Developer/vibe-coding-system/.claude && printf 'NONE\n' > ~/Developer/vibe-coding-system/.claude/test-cmd && cat ~/Developer/vibe-coding-system/.claude/test-cmd`
Expected: `NONE`. Effect: future Stop in this repo → opt-out tier → fail-open (the T11 doc-repo defect is now structurally closed).

- [ ] **Step 2: Pilot declaration (prepare; Stefano runs/approves)**

Instructions for Stefano in `~/developer/pricing-markup-cli`:
```bash
mkdir -p .claude && printf 'pytest -q\n' > .claude/test-cmd
bash ~/.claude/hooks/approve-test-cmd.sh "$PWD"   # TOFU approve
```

- [ ] **Step 3: Pilot tier validation (Stefano, fresh session in `~/developer/pricing-markup-cli`)**
  - Edit a `.py`, end turn WITHOUT running tests, with a passing suite → expect: gate runs `pytest -q` itself, green → allow (no block). Confirms authoritative tier + no heuristics.
  - Introduce a failing test, edit, end turn → expect block with "Test falliti …" + tail; anti-loop bounded.
  - Change `.claude/test-cmd` content → expect approve-tier block (hash changed) until re-approved.
  - Remove `.claude/test-cmd` → expect nudge-bounded.

- [ ] **Step 4: Final report** — summarize tier behavior observed; confirm spec §12 success criteria; note Phase B/C of the old agentic-swarm spec are subsumed/closed.

---

## Out of scope

- Old agentic-swarm spec Phase B/C: subsumed by the authoritative tier; no separate work.
- Sandboxing the approved command: explicitly a non-goal (spec §2); TOFU is the control.
