# Agentic Swarm — Phase A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Phase A deterministic Stop-gate (marker-block) + anti-loop guardrail + sentinel plumbing + Level-2 proactive config, validated on the pilot and deployed globally behind an explicit HITL gate.

**Architecture:** Five small bash hook scripts under `~/.claude/hooks/` driven by a per-`session_id` state directory `~/.claude/state/stop-gate/`. The `Stop` hook is `type: command` (verified 2026-05-19: `prompt`/`agent` unsupported on `Stop`); it blocks via `{"decision":"block","reason":"…"}` on stdout and is bounded by a per-session re-entry counter. Level 2 is config-only (agent `description` hardening + a path-scoped parallelization rule). All global mutation is backed up and manifested (spec §12) and the single `settings.json` change is HITL-gated.

**Tech Stack:** bash, `jq` (JSON on stdin), Claude Code hooks (`Stop`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`), `settings.json`, markdown frontmatter.

**Spec:** `docs/superpowers/specs/2026-05-19-agentic-swarm-design.md` (Phase A scope; Phase B/C are a separate future plan).

---

## Environment notes (read first)

- **No git in this repo / in `~/.claude/`.** The writing-plans "commit" step is replaced by a **checkpoint**: tests green + a `MANIFEST.md` entry (spec §12). The only mutation of live global state happens in Task 10, behind an explicit HITL gate (show diff → wait for Stefano's approval). Per `~/.claude/CLAUDE.md`: backup before modifying critical files; HITL before deploy; never overwrite without showing the diff.
- **Testability:** every script honors `STOP_GATE_STATE_DIR` (default `$HOME/.claude/state/stop-gate`). The test harness points it at a temp dir so tests never touch real state.
- **Fail-open is law (spec §4.4):** on any internal error (missing `jq`, unparsable `session_id`, unwritable state), scripts `exit 0` with no block. Never `exit 2` / `decision:block` on hook error.
- **Contract caveat:** the exact `Stop` block envelope (`{"decision":"block","reason":"…"}` top-level vs a wrapper) is from a 2026-05-19 docs verification (confidence medium-high). Task 6 includes a live empirical check on the pilot; if the installed Claude Code expects a different envelope, fix `stop-gate.sh` once and re-run the suite.

## File structure

Created (all new):

- `~/.claude/hooks/ensure-state-dir.sh` — SessionStart: idempotent `mkdir -p` of state dir. Fail-open.
- `~/.claude/hooks/mark-dirty.sh` — PostToolUse `Edit|Write`: create `<sid>.dirty`.
- `~/.claude/hooks/clear-dirty-on-test.sh` — PostToolUse `Bash`: clear `<sid>.dirty` if a test command ran without obvious failure.
- `~/.claude/hooks/reset-gate-counter.sh` — UserPromptSubmit: delete `<sid>.count`.
- `~/.claude/hooks/stop-gate.sh` — Stop (Phase A): if `<sid>.dirty` and counter `< N` → block + counter++; counter `>= N` → allow + warn; no dirty / no sid → allow.
- `~/.claude/hooks/tests/run-hook-tests.sh` — self-contained bash test harness for all of the above.
- `~/.claude/hooks/backup-before-deploy.sh` — spec §12: backup existing-to-be-modified files + write `MANIFEST.md`.
- `~/.claude/rules/parallelization.md` — path-scoped rule encoding spec §6.2 + §9.1 precedence.

Modified (Task 8, frontmatter `description:` line only):

- `~/.claude/agents/tester.md`, `reviewer.md`, `debugger.md`, `refactorer.md`

Modified (Task 10, HITL-gated):

- `~/.claude/settings.json` — merge new hook entries alongside existing ones.

---

### Task 1: State dir bootstrap — `ensure-state-dir.sh` (SessionStart)

**Files:**
- Create: `~/.claude/hooks/ensure-state-dir.sh`
- Test: `~/.claude/hooks/tests/run-hook-tests.sh` (started here, extended each task)

- [ ] **Step 1: Write the failing test**

Create `~/.claude/hooks/tests/run-hook-tests.sh`:

```bash
#!/bin/bash
# Hook unit test harness. Isolated state dir; never touches real state.
set -u
HOOKS="$HOME/.claude/hooks"
TMP="$(mktemp -d)"
export STOP_GATE_STATE_DIR="$TMP/state"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# --- Task 1: ensure-state-dir.sh ---
rm -rf "$STOP_GATE_STATE_DIR"
echo '{"session_id":"s1","hook_event_name":"SessionStart"}' | bash "$HOOKS/ensure-state-dir.sh" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && [ -d "$STOP_GATE_STATE_DIR" ] && ok "ensure-state-dir creates dir, exit 0" || bad "ensure-state-dir"

echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"
[ $FAIL -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL: ensure-state-dir` (script does not exist yet), final line `PASS=0 FAIL=1`, non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Create `~/.claude/hooks/ensure-state-dir.sh`:

```bash
#!/bin/bash
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
mkdir -p "$DIR" 2>/dev/null || true
exit 0
```

Then: `chmod +x ~/.claude/hooks/ensure-state-dir.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `PASS: ensure-state-dir creates dir, exit 0`, final line `PASS=1 FAIL=0`, exit 0.

- [ ] **Step 5: Checkpoint**

No git here. Checkpoint = harness green. Record progress in TodoWrite. Do NOT touch `~/.claude/settings.json` yet (Task 10).

---

### Task 2: `mark-dirty.sh` (PostToolUse Edit|Write)

**Files:**
- Create: `~/.claude/hooks/mark-dirty.sh`
- Test: append to `~/.claude/hooks/tests/run-hook-tests.sh`

- [ ] **Step 1: Write the failing test**

Insert before the `echo "----"` summary line in the harness:

```bash
# --- Task 2: mark-dirty.sh ---
mkdir -p "$STOP_GATE_STATE_DIR"
echo '{"session_id":"s2","tool_name":"Write","tool_input":{"file_path":"/x/a.py"}}' | bash "$HOOKS/mark-dirty.sh" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && [ -f "$STOP_GATE_STATE_DIR/s2.dirty" ] && ok "mark-dirty creates <sid>.dirty" || bad "mark-dirty creates dirty"
# fail-open: no session_id → exit 0, no file
echo '{"tool_name":"Edit"}' | bash "$HOOKS/mark-dirty.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "mark-dirty fail-open without session_id" || bad "mark-dirty fail-open"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL: mark-dirty creates dirty`, non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Create `~/.claude/hooks/mark-dirty.sh`:

```bash
#!/bin/bash
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0
mkdir -p "$DIR" 2>/dev/null || true
: > "$DIR/$SID.dirty" 2>/dev/null || true
exit 0
```

Then: `chmod +x ~/.claude/hooks/mark-dirty.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `PASS: mark-dirty creates <sid>.dirty`, `PASS: mark-dirty fail-open without session_id`.

- [ ] **Step 5: Checkpoint**

Harness green. TodoWrite update.

---

### Task 3: `reset-gate-counter.sh` (UserPromptSubmit)

**Files:**
- Create: `~/.claude/hooks/reset-gate-counter.sh`
- Test: append to harness

- [ ] **Step 1: Write the failing test**

Insert before the summary line:

```bash
# --- Task 3: reset-gate-counter.sh ---
mkdir -p "$STOP_GATE_STATE_DIR"; echo 2 > "$STOP_GATE_STATE_DIR/s3.count"
echo '{"session_id":"s3","hook_event_name":"UserPromptSubmit","prompt":"hi"}' | bash "$HOOKS/reset-gate-counter.sh" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && [ ! -f "$STOP_GATE_STATE_DIR/s3.count" ] && ok "reset-gate-counter deletes count" || bad "reset-gate-counter"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL: reset-gate-counter`.

- [ ] **Step 3: Write minimal implementation**

Create `~/.claude/hooks/reset-gate-counter.sh`:

```bash
#!/bin/bash
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0
rm -f "$DIR/$SID.count" 2>/dev/null || true
exit 0
```

Then: `chmod +x ~/.claude/hooks/reset-gate-counter.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `PASS: reset-gate-counter deletes count`.

- [ ] **Step 5: Checkpoint**

Harness green. TodoWrite update.

---

### Task 4: `stop-gate.sh` — Phase A (marker-block + anti-loop)

**Files:**
- Create: `~/.claude/hooks/stop-gate.sh`
- Test: append to harness

- [ ] **Step 1: Write the failing test**

Insert before the summary line:

```bash
# --- Task 4: stop-gate.sh (Phase A) ---
mkdir -p "$STOP_GATE_STATE_DIR"

# 4a: no dirty → allow stop (exit 0, no stdout)
rm -f "$STOP_GATE_STATE_DIR/s4.dirty" "$STOP_GATE_STATE_DIR/s4.count"
OUT=$(echo '{"session_id":"s4","hook_event_name":"Stop"}' | bash "$HOOKS/stop-gate.sh" 2>/dev/null); rc=$?
[ $rc -eq 0 ] && [ -z "$OUT" ] && ok "stop-gate: no dirty → allow" || bad "stop-gate no dirty"

# 4b: dirty + counter 0 → block + counter becomes 1
: > "$STOP_GATE_STATE_DIR/s4.dirty"
OUT=$(echo '{"session_id":"s4","hook_event_name":"Stop"}' | bash "$HOOKS/stop-gate.sh" 2>/dev/null)
echo "$OUT" | grep -q '"decision":"block"' && [ "$(cat "$STOP_GATE_STATE_DIR/s4.count")" = "1" ] \
  && ok "stop-gate: dirty → block + counter=1" || bad "stop-gate dirty block"

# 4c: counter at N (=3) → allow + warning on stderr, no block json
echo 3 > "$STOP_GATE_STATE_DIR/s4.count"
ERR=$(echo '{"session_id":"s4","hook_event_name":"Stop"}' | bash "$HOOKS/stop-gate.sh" 2>&1 1>/dev/null); rc=$?
OUT=$(echo '{"session_id":"s4","hook_event_name":"Stop"}' | bash "$HOOKS/stop-gate.sh" 2>/dev/null)
[ $rc -eq 0 ] && echo "$ERR" | grep -qi "anti-loop" && ! echo "$OUT" | grep -q '"decision":"block"' \
  && ok "stop-gate: counter>=N → allow + warn" || bad "stop-gate anti-loop cap"

# 4d: fail-open, no session_id → allow
OUT=$(echo '{"hook_event_name":"Stop"}' | bash "$HOOKS/stop-gate.sh" 2>/dev/null); rc=$?
[ $rc -eq 0 ] && [ -z "$OUT" ] && ok "stop-gate: no session_id → fail-open allow" || bad "stop-gate fail-open"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: the four `stop-gate` checks FAIL (script absent).

- [ ] **Step 3: Write minimal implementation**

Create `~/.claude/hooks/stop-gate.sh`:

```bash
#!/bin/bash
# Phase A: marker-block. Does NOT run tests. Fail-open. Anti-loop bounded.
# Contract: exit 0 + empty stdout = allow stop; exit 0 + {"decision":"block"}
# on stdout = block. Never exit non-zero / never block on internal error.
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
N="${STOP_GATE_MAX_REENTRY:-3}"
case "$N" in ''|*[!0-9]*) N=3;; esac
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0                       # fail-open
DIRTY="$DIR/$SID.dirty"
CF="$DIR/$SID.count"
[ ! -f "$DIRTY" ] && exit 0                    # nothing changed → allow stop

COUNT=0
[ -f "$CF" ] && COUNT=$(cat "$CF" 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0;; esac

if [ "$COUNT" -ge "$N" ]; then
  echo "stop-gate: guardrail anti-loop attivo — sbloccato dopo $N rientri. Verifica manualmente i test." >&2
  exit 0
fi

echo $((COUNT + 1)) > "$CF" 2>/dev/null || true
printf '{"decision":"block","reason":"Hai modificato codice senza eseguire la test suite del progetto. Esegui i test e conferma il verde prima di concludere."}\n'
exit 0
```

Then: `chmod +x ~/.claude/hooks/stop-gate.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: all four `stop-gate` checks PASS.

- [ ] **Step 5: Checkpoint**

Harness green. TodoWrite update.

---

### Task 5: `clear-dirty-on-test.sh` (PostToolUse Bash)

**Files:**
- Create: `~/.claude/hooks/clear-dirty-on-test.sh`
- Test: append to harness

- [ ] **Step 1: Write the failing test**

Insert before the summary line:

```bash
# --- Task 5: clear-dirty-on-test.sh ---
mkdir -p "$STOP_GATE_STATE_DIR"

# 5a: pytest with passing output → clears dirty
: > "$STOP_GATE_STATE_DIR/s5.dirty"
echo '{"session_id":"s5","tool_name":"Bash","tool_input":{"command":"pytest -q"},"tool_output":"3 passed in 0.1s"}' \
  | bash "$HOOKS/clear-dirty-on-test.sh" >/dev/null 2>&1
[ ! -f "$STOP_GATE_STATE_DIR/s5.dirty" ] && ok "clear-dirty: passing pytest clears dirty" || bad "clear-dirty pass"

# 5b: pytest with failure output → keeps dirty
: > "$STOP_GATE_STATE_DIR/s5.dirty"
echo '{"session_id":"s5","tool_name":"Bash","tool_input":{"command":"pytest -q"},"tool_output":"1 failed, 2 passed"}' \
  | bash "$HOOKS/clear-dirty-on-test.sh" >/dev/null 2>&1
[ -f "$STOP_GATE_STATE_DIR/s5.dirty" ] && ok "clear-dirty: failing pytest keeps dirty" || bad "clear-dirty fail-keeps"

# 5c: non-test command → keeps dirty
: > "$STOP_GATE_STATE_DIR/s5.dirty"
echo '{"session_id":"s5","tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_output":"x"}' \
  | bash "$HOOKS/clear-dirty-on-test.sh" >/dev/null 2>&1
[ -f "$STOP_GATE_STATE_DIR/s5.dirty" ] && ok "clear-dirty: non-test keeps dirty" || bad "clear-dirty non-test"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: the three `clear-dirty` checks FAIL.

- [ ] **Step 3: Write minimal implementation**

Create `~/.claude/hooks/clear-dirty-on-test.sh`:

```bash
#!/bin/bash
# Phase A clear: if a recognized test command ran without obvious failure,
# drop the dirty marker. Best-effort (Phase A is advisory; Phase B verifies).
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
OUTP=$(printf '%s' "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null)
case "$CMD" in
  *pytest*|*"npm test"*|*"npm run test"*|*vitest*|*"go test"*) : ;;
  *) exit 0 ;;
esac
# obvious-failure heuristic — keep dirty if present
if printf '%s' "$OUTP" | grep -Eqi '([1-9][0-9]* failed|FAILED|Traceback|^error:|npm ERR!)'; then
  exit 0
fi
rm -f "$DIR/$SID.dirty" 2>/dev/null || true
exit 0
```

Then: `chmod +x ~/.claude/hooks/clear-dirty-on-test.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: the three `clear-dirty` checks PASS; final `FAIL=0`.

- [ ] **Step 5: Checkpoint**

Harness green. TodoWrite update.

---

### Task 6: Full suite + live contract check on the pilot

**Files:**
- Test: `~/.claude/hooks/tests/run-hook-tests.sh` (run whole)
- Verify against: `~/developer/pricing-markup-cli`

- [ ] **Step 1: Run the full unit suite**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: final line `PASS=<n> FAIL=0`, exit 0.

- [ ] **Step 2: Live envelope check (empirical, no settings.json change)**

The block JSON envelope is from a docs verification (medium-high confidence). Verify the installed Claude Code accepts it without committing to a global config:

Run:
```bash
claude --version
echo '{"session_id":"probe","hook_event_name":"Stop"}' | STOP_GATE_STATE_DIR=/tmp/sg-probe bash -c 'mkdir -p /tmp/sg-probe; : > /tmp/sg-probe/probe.dirty; bash ~/.claude/hooks/stop-gate.sh; echo "rc=$?"'
```
Expected: prints `{"decision":"block","reason":"…"}` then `rc=0`.

- [ ] **Step 3: Confirm contract or adjust once**

If, when later wired (Task 10) on the pilot, `Stop` does NOT actually block with this envelope, consult `code.claude.com/docs/en/hooks` for the installed version's exact key (`decision` vs `hookSpecificOutput`), fix `stop-gate.sh` Step 3 of Task 4 once, and re-run the full suite. Record the confirmed envelope as a comment at the top of `stop-gate.sh`.

- [ ] **Step 4: Checkpoint**

Suite green + envelope empirically confirmed (or fixed once and re-greened).

---

### Task 7: Backup + MANIFEST infra (spec §12)

**Files:**
- Create: `~/.claude/hooks/backup-before-deploy.sh`
- Output dir: `~/.claude/state/backups/2026-05-19-swarm-fase-A/`

- [ ] **Step 1: Write the failing test**

Insert before the summary line in the harness:

```bash
# --- Task 7: backup-before-deploy.sh ---
BK="$TMP/backups/2026-05-19-swarm-fase-A"
mkdir -p "$TMP/fakehome/.claude/agents"
echo '{"hooks":{}}' > "$TMP/fakehome/.claude/settings.json"
echo "desc" > "$TMP/fakehome/.claude/agents/tester.md"
BACKUP_SRC_HOME="$TMP/fakehome" BACKUP_DEST="$BK" bash "$HOOKS/backup-before-deploy.sh" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && [ -f "$BK/settings.json" ] && [ -f "$BK/agents/tester.md" ] && [ -f "$BK/MANIFEST.md" ] \
  && grep -q "settings.json" "$BK/MANIFEST.md" && ok "backup: copies files + MANIFEST" || bad "backup infra"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `FAIL: backup infra`.

- [ ] **Step 3: Write minimal implementation**

Create `~/.claude/hooks/backup-before-deploy.sh`:

```bash
#!/bin/bash
set -u
SRC="${BACKUP_SRC_HOME:-$HOME}/.claude"
DEST="${BACKUP_DEST:-$HOME/.claude/state/backups/2026-05-19-swarm-fase-A}"
mkdir -p "$DEST/agents" 2>/dev/null || true
MAN="$DEST/MANIFEST.md"
echo "# Backup MANIFEST — 2026-05-19 swarm Fase A" > "$MAN"
echo "" >> "$MAN"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
backup_one() {  # $1 = relative path under .claude
  local rel="$1" src="$SRC/$1" dst="$DEST/$1"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")" 2>/dev/null || true
    cp -p "$src" "$dst" 2>/dev/null || true
    echo "- \`$rel\` — modified — backup: \`$dst\` — $ts" >> "$MAN"
  else
    echo "- \`$rel\` — created (no pre-existing file to back up) — $ts" >> "$MAN"
  fi
}
backup_one "settings.json"
backup_one "agents/tester.md"
backup_one "agents/reviewer.md"
backup_one "agents/debugger.md"
backup_one "agents/refactorer.md"
echo "" >> "$MAN"
echo "Files created new (backout = remove, HITL): hooks/*.sh, hooks/tests/, rules/parallelization.md, state/stop-gate/" >> "$MAN"
exit 0
```

Then: `chmod +x ~/.claude/hooks/backup-before-deploy.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.claude/hooks/tests/run-hook-tests.sh`
Expected: `PASS: backup: copies files + MANIFEST`, final `FAIL=0`.

- [ ] **Step 5: Checkpoint**

Harness green. TodoWrite update.

---

### Task 8: Level 2 — agent `description` hardening

**Files:**
- Modify: `~/.claude/agents/tester.md`, `reviewer.md`, `debugger.md`, `refactorer.md` (frontmatter `description:` line only)

- [ ] **Step 1: Snapshot current descriptions**

Run:
```bash
grep -H '^description:' ~/.claude/agents/tester.md ~/.claude/agents/reviewer.md ~/.claude/agents/debugger.md ~/.claude/agents/refactorer.md
```
Expected: prints the four current `description:` lines. Save this output into the Task 7 backup dir as `agents-descriptions-before.txt`:
```bash
grep -H '^description:' ~/.claude/agents/{tester,reviewer,debugger,refactorer}.md > ~/.claude/state/backups/2026-05-19-swarm-fase-A/agents-descriptions-before.txt
```

- [ ] **Step 2: Edit `tester.md` description**

Replace the `description:` line in `~/.claude/agents/tester.md` so it reads exactly:
```
description: Writes and runs unit/integration tests. Use proactively after coder finishes implementing a feature or whenever code changed without tests.
```

- [ ] **Step 3: Edit `reviewer.md` description**

Replace the `description:` line in `~/.claude/agents/reviewer.md`:
```
description: Reviews recently changed code for security, correctness, performance, and consistency. Use proactively before any commit involving more than 50 changed lines.
```

- [ ] **Step 4: Edit `debugger.md` description**

Replace the `description:` line in `~/.claude/agents/debugger.md`:
```
description: Root-cause analysis of failures. Use proactively on any runtime error, red test, or unexpected behavior.
```

- [ ] **Step 5: Edit `refactorer.md` description**

Replace the `description:` line in `~/.claude/agents/refactorer.md`:
```
description: Improves code structure without changing behavior. Use when the reviewer flags structural issues or on explicit request.
```

- [ ] **Step 6: Verify only the description line changed**

Run:
```bash
for f in tester reviewer debugger refactorer; do head -5 ~/.claude/agents/$f.md; echo "---"; done
```
Expected: each file still has valid YAML frontmatter (`---`, `name:`, the new `description:`), nothing else altered.

- [ ] **Step 7: Checkpoint**

Descriptions updated; pre-change snapshot stored in the Fase A backup dir. TodoWrite update.

---

### Task 9: Level 2 — parallelization rule

**Files:**
- Create: `~/.claude/rules/parallelization.md`

- [ ] **Step 1: Confirm rules dir & frontmatter convention**

Run: `ls ~/.claude/rules/ 2>/dev/null; head -8 ~/.claude/rules/*.md 2>/dev/null | head -20`
Expected: see whether `paths:` frontmatter is used by existing rules; mirror that exact frontmatter shape. If `~/.claude/rules/` does not exist: `mkdir -p ~/.claude/rules`.

- [ ] **Step 2: Create the rule**

Create `~/.claude/rules/parallelization.md`:

```markdown
---
paths:
  - "**/*.py"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.swift"
---

# Orchestrator parallelization policy

When a coding task spans multiple files, decide serial vs parallel sub-agent
fan-out using these criteria, in order:

1. **File independence** — sub-agents touch disjoint files/modules → parallel
   fan-out allowed.
2. **Test state** — tests green → parallel; tests red → serial (fix first).
3. **Task type** — research/planning → serial; coding/test/doc → parallelizable.

Cap: at most 4 parallel sub-agents; beyond that, sequential batches of 3–4.
Parallel `coder` sub-agents must use `isolation: worktree`.

## Plan-mode e fan-out (chiarimento, spec §9.1 — 2026-05-19)

Plan mode resta OBBLIGATORIO per task che modificano >1 file (regola
IMPORTANT del CLAUDE.md globale: invariata). Il piano di fan-out
dell'orchestrator È l'artefatto da presentare per l'approvazione in plan
mode. Una volta che QUEL piano è approvato dall'utente, l'esecuzione dei
sub-agent al suo interno procede senza richiedere una seconda approvazione
plan-mode separata per lo stesso lavoro già approvato. In nessun caso questo
autorizza a saltare plan mode quando il piano di fan-out non è stato approvato.
```

- [ ] **Step 3: Verify frontmatter parses**

Run: `head -9 ~/.claude/rules/parallelization.md`
Expected: valid `---` frontmatter block with `paths:` list, then the body.

- [ ] **Step 4: Checkpoint**

Rule created. TodoWrite update. (Not yet active until Claude Code reloads rules — that is expected; activation is observed in Task 11.)

---

### Task 10: Wire hooks into `settings.json` (HITL-GATED)

**Files:**
- Modify: `~/.claude/settings.json` (merge — existing `SessionStart`/`PreToolUse`/`PostToolUse` entries must be preserved)

- [ ] **Step 1: Run the backup FIRST**

Run: `bash ~/.claude/hooks/backup-before-deploy.sh && cat ~/.claude/state/backups/2026-05-19-swarm-fase-A/MANIFEST.md`
Expected: MANIFEST lists `settings.json` (modified) + the four agent files + the "created new" line.

- [ ] **Step 2: Compute the merged settings.json (do NOT write yet)**

Run:
```bash
jq '
 .hooks.SessionStart += [{"hooks":[{"type":"command","command":"\"$HOME\"/.claude/hooks/ensure-state-dir.sh"}]}]
 | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{"hooks":[{"type":"command","command":"\"$HOME\"/.claude/hooks/reset-gate-counter.sh"}]}])
 | .hooks.PostToolUse += [
     {"matcher":"Edit|Write","hooks":[{"type":"command","command":"\"$HOME\"/.claude/hooks/mark-dirty.sh"}]},
     {"matcher":"Bash","hooks":[{"type":"command","command":"\"$HOME\"/.claude/hooks/clear-dirty-on-test.sh"}]}
   ]
 | .hooks.Stop = ((.hooks.Stop // []) + [{"hooks":[{"type":"command","command":"\"$HOME\"/.claude/hooks/stop-gate.sh"}]}])
' ~/.claude/settings.json > /tmp/settings.merged.json
diff <(jq -S . ~/.claude/settings.json) <(jq -S . /tmp/settings.merged.json)
```
Expected: a diff showing ONLY additions (new `Stop`, new `UserPromptSubmit`, two new `PostToolUse` blocks, one new `SessionStart` block) and the pre-existing `SessionStart`/`PreToolUse`/`PostToolUse` entries unchanged. Validate `/tmp/settings.merged.json` is valid JSON: `jq -e . /tmp/settings.merged.json >/dev/null && echo VALID`.

- [ ] **Step 3: HITL GATE — STOP and get explicit approval**

Present to Stefano: (a) the `diff` from Step 2, (b) the MANIFEST path, (c) the rollback procedure (spec §12.4). Ask for explicit approval to overwrite `~/.claude/settings.json`. **Do not proceed without it.** (Global CLAUDE.md: HITL before config deploy; never overwrite without showing the diff.)

- [ ] **Step 4: Apply (only after approval)**

Run: `cp /tmp/settings.merged.json ~/.claude/settings.json && jq -e . ~/.claude/settings.json >/dev/null && echo APPLIED`
Expected: `APPLIED`.

- [ ] **Step 5: Checkpoint**

settings.json merged; backup + MANIFEST in place; rollback = restore `settings.json` from `~/.claude/state/backups/2026-05-19-swarm-fase-A/settings.json` + remove created files (HITL) + fresh session.

---

### Task 11: Pilot validation on `pricing-markup-cli` (spec §8)

**Files:**
- Verify in: `~/developer/pricing-markup-cli`

- [ ] **Step 1: Fresh session to load the new config**

Open a new Claude Code session in `~/developer/pricing-markup-cli` (hooks/rules load at session start).

- [ ] **Step 2: §8.1 — anti-loop cap (no real damage)**

In the pilot session, make a trivial Edit to any `.py`, then attempt to end the turn without running tests, three times. Expected: the Stop gate blocks ~3 times with the spec §4.1 reason, then on the next attempt allows stop with the anti-loop warning on stderr (`anti-loop guardrail: …`). Confirms the §5 guardrail caps and the open "loop infinito" flag is closed.

- [ ] **Step 3: §8.2 — fail-open with jq absent**

Run: `PATH=/usr/bin STOP_GATE_STATE_DIR=/tmp/sgfo bash -c 'mkdir -p /tmp/sgfo; : >/tmp/sgfo/x.dirty; echo "{}" | bash ~/.claude/hooks/stop-gate.sh; echo rc=$?'`
Expected: `rc=0`, no block JSON (jq missing / no session_id → fail-open allow).

- [ ] **Step 4: §8.3 — counter reset on new turn**

In the pilot session: trigger one block, then send a new user prompt, then check `~/.claude/state/stop-gate/<sid>.count` is gone (UserPromptSubmit reset). Get `<sid>` from any hook input or `ls ~/.claude/state/stop-gate/`.

- [ ] **Step 5: §8.5 — parallelization fan-out, zero collisions**

Give the pilot a small multi-file task (e.g., touch two independent modules). Expected: orchestrator fans out ≤4 sub-agents on independent files (per the new rule), no shared-file collision; plan-mode does not re-trigger per sub-agent (spec §9.1 precedence honored).

- [ ] **Step 6: Final checkpoint + report**

Summarize: which §8 checks passed, anything that needed a one-time fix (e.g., Stop envelope from Task 6 Step 3), and confirm Phase A is stable. Phase B (real test execution in `stop-gate.sh`) is a SEPARATE future plan, explicitly gated on this Phase A being proven stable in real use (spec §10).

---

## Out of scope (separate future plan)

- **Phase B** — evolve `stop-gate.sh` to actually run the project test suite when dirty (spec §4.2). Gated on Phase A proven stable.
- **Phase C** — escalation / documented agent-teams trigger (spec §10).
