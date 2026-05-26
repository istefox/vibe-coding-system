# Pre-flight Pattern Enforce Hook — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Changelog:**
- v1.0 (2026-05-20): initial — TDD plan derivato da `ADR-0004-pre-flight-pattern-enforce-hook.md` e dallo spec `2026-05-20-pre-flight-pattern-enforce-hook-design.md`. 7 task: 1 red harness, 1 green hook script, 1 green settings registration, 1 dedicated harness, 1 documental sync (ADR/spec status), 2 deliverable doc + memory + MEMORY.md index.

**Goal:** introdurre `~/.claude/hooks/pre-flight-pattern-enforce.sh` (hook bash 3.2-clean PreToolUse su `Edit|Write|MultiEdit`) che blocca tool call del `coder` agent se manca un `PATTERN:` header well-formed nella sliding window degli ultimi 6 messaggi assistant. 4° layer di defense sopra ai 3 di ADR-0001. Bypass via env (`PATTERN_ENFORCE=off`), file flag (`~/.claude/state/pattern-enforce/disabled`), o disable da settings.json. Fail-open su qualsiasi errore interno (no exit non-zero, no crash visibile). Audit log append-only in `~/.claude/state/pattern-enforce/audit.log`.

**Architecture:** new executable in `~/.claude/hooks/pre-flight-pattern-enforce.sh` (~150 righe bash 3.2-clean). New test harness in `~/.claude/hooks/tests/pre-flight-pattern-enforce.sh` (target PASS=10). Settings.json entry append (PreToolUse matcher `Edit|Write|MultiEdit`). 1 anchor structural in `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (verifica entry in settings.json). Harness review-triage-fix PASS=47 → PASS=48 (additivo, anchor su `settings.json`). Coexistenza esplicita con `protect-files.sh`, `backup-before-deploy.sh`, `auto-format.sh`: nessun event/matcher conflict.

**Tech Stack:** bash 3.2.57 (hook + harness; pattern timeout da `stop-gate.sh` linee 77-88, jq parsing JSON identico a `stop-gate.sh` linee 22-25), jq (richiesto per parse stdin + transcript jsonl), grep -E (regex POSIX-EXT), markdown (plan/spec/ADR/memory).

**Spec:** `docs/superpowers/specs/2026-05-20-pre-flight-pattern-enforce-hook-design.md` (approvato 2026-05-20).
**ADR:** `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` (Proposed 2026-05-20).

---

## Environment notes (read first)

- **No git in `~/.claude/` né in questo repo doc `vibe-coding-system`.** Checkpoint per task = harness verde + TodoWrite update + report. Nessun commit. Nessun HITL gate complesso: deploy aggiunge 1 hook PreToolUse + 1 anchor harness + 1 entry settings.json. La feature è inert per non-coder agent (bypass silent) e inert per orchestrator (bypass silent). Effettiva solo al prossimo dispatch organico del `coder` agent.
- **Bash 3.2 cleanliness.** Hook + harness usano: `[ -f "$X" ]`, `grep -q --`, `grep -E`, `jq -r`, `tail -n N`, `mktemp -d`, `&` background subshell + `wait`. Niente assoc array, niente `mapfile`, niente `${v^^}`, niente `<()` process substitution. Pattern timeout: copia da `stop-gate.sh` linee 77-88 (timeout/gtimeout/subshell+kill fallback).
- **Fail-open by construction.** Ogni branch di errore interno → `exit 0 + stdout vuoto` + riga in audit.log. Mai `exit 1`, mai stderr che genera failure visibile all'utente.
- **Anchor preservation.** I 47 anchor v1.2+ADR-0001+ADR-0002+ADR-0003 restano intatti. Nuovo anchor (Task 1) inserito post-Task-6 di ADR-0001 (post `coder.md` block) e pre-summary line. Harness baseline verificare con `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh` pre-implementation: atteso `PASS=47 FAIL=0`.
- **Backup raccomandato pre-edit di settings.json:** `cp ~/.claude/settings.json ~/.claude/settings.json.bak-2026-05-20`. settings.json è ad alto rischio (rompe se malformed JSON), backup richiesto.
- **Cleanup state pre-deploy:** `mkdir -p ~/.claude/state/pattern-enforce`. La dir contiene `audit.log` (auto-creato al primo append) e opzionale `disabled` flag (touch per bypass).
- **Coexistenza HARD con hook esistenti.** `protect-files.sh` (PreToolUse) e `backup-before-deploy.sh` (PreToolUse) restano. L'aggiunta del nuovo hook DEVE preservare i loro entry e l'ordine di execution (protect-files PRIMA di pattern-enforce). Vedi Task 3.
- **Performance budget.** <100ms typical (jq+tail+grep), 2s hard timeout (fail-open).

## File structure

Tutti i path live (`~/.claude/hooks/`, `~/.claude/state/`, `~/.claude/settings.json`, `~/.claude/skills/review-triage-fix/tests/`); deliverable doc nel repo `vibe-coding-system`; memory in `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/`.

- Create `~/.claude/hooks/pre-flight-pattern-enforce.sh` — hook script ~150 righe bash 3.2.
- Create `~/.claude/hooks/tests/pre-flight-pattern-enforce.sh` — harness dedicato ~120 righe + fixture jsonl inline o in `tests/fixtures/`.
- Create `~/.claude/state/pattern-enforce/` — directory state (mkdir -p, no content).
- Modify `~/.claude/settings.json` — append entry PreToolUse matcher `Edit|Write|MultiEdit`.
- Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — insert nuovo blocco `# --- Task 7: pre-flight-pattern-enforce hook ---` (1 anchor + guard `[ -f settings.json ]`) tra l'ultimo anchor esistente e la summary line.
- Modify `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` — status line da Proposed a Accepted.
- Modify `docs/superpowers/specs/2026-05-20-pre-flight-pattern-enforce-hook-design.md` — status line da "approvato" a "implementato".
- Create `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_pattern-enforce-hook.md` — nuovo project memory entry.
- Modify `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` — append riga nuova in sezione `## Project`.

Unchanged (vincoli HARD): system prompt `~/.claude/agents/coder.md` (contract PATTERN: vive lì da ADR-0001, immutato), `~/.claude/agents/reviewer.md` (item 5 pattern-drift immutato), `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2 Add+Remove rule resta), tutti gli altri agent, altri hook (`stop-gate.sh`, `protect-files.sh`, `backup-before-deploy.sh`, `auto-format.sh`).

---

### Task 1: Harness anchor failing (red)

**Files:**
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (insert nuovo blocco Task 7 prima della summary line)

**Red phase:** baseline harness `PASS=47 FAIL=0`. Il nuovo blocco Task 7 cerca literal `pre-flight-pattern-enforce` in `~/.claude/settings.json` — assente pre-Task-3. Aspettativa: 1 nuovo `FAIL`, cumulative `PASS=47 FAIL=1`, exit 1.

**Green phase (edit concreto):** localizza nel file l'ultima riga del blocco Task 6 (anchor `coder.md: PATTERN format spec present`, post-ADR-0001) e la summary line `echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"`. Inserisci tra le due (con riga vuota di separazione) il blocco:

```bash

# --- Task 7: pre-flight-pattern-enforce hook ---
S="$HOME/.claude/settings.json"
grep -q -- 'pre-flight-pattern-enforce' "$S" 2>/dev/null && ok "settings.json: pre-flight-pattern-enforce hook registered" || bad "settings.json: pre-flight-pattern-enforce hook missing"

```

Notes:
- 1 anchor totale per il blocco Task 7 (presenza entry hook in settings.json). 3.2-clean: `grep -q --` + `&&`/`||` + `ok`/`bad` (helpers già definiti).
- Match string `pre-flight-pattern-enforce` è il literal del nome script — match sia l'entry hook (Task 3) sia eventuale documentazione inline.
- Cumulative TARGET = `PASS=48 FAIL=0` dopo Task 3 (settings.json patchato).

- [ ] **Step 1: Write the failing test** — edit `~/.claude/skills/review-triage-fix/tests/run-tests.sh` per inserire il blocco Task 7 (1 anchor) prima della summary line.

- [ ] **Step 2: Run test to verify it fails**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: i 47 anchor esistenti ancora `PASS`; il nuovo anchor `settings.json: pre-flight-pattern-enforce hook missing` `FAIL`; summary `PASS=47 FAIL=1`, exit 1.

- [ ] **Step 3: Checkpoint** — failing test in place, baseline rossa confermata. TodoWrite update.

**Stima tempo:** 4 min.

---

### Task 2: Hook script (green primary)

**Files:**
- Create: `~/.claude/hooks/pre-flight-pattern-enforce.sh` (executable, bash 3.2-clean, ~150 righe)
- Create: `~/.claude/state/pattern-enforce/` (directory, mkdir -p)

**Red phase:** il file hook non esiste. `[ -f ~/.claude/hooks/pre-flight-pattern-enforce.sh ]` exit 1. Il harness Task 7 anchor è ancora `FAIL` (settings.json non patchato yet — Task 3 lo fa).

**Green phase (edit concreto):** create lo script con questa logica strutturale:

```bash
#!/bin/bash
# pre-flight-pattern-enforce v1.0 — gate per coder agent: blocca Edit/Write/MultiEdit
# se manca PATTERN: header well-formed nella sliding window (ADR-0004, ADR-0001 contract).
# Contract: exit 0 + empty stdout = allow; exit 0 + {"decision":"block",...} = block.
# Fail-open su qualunque errore interno (no exit non-zero).

DIR="${PATTERN_ENFORCE_DIR:-$HOME/.claude/state/pattern-enforce}"
LOG="$DIR/audit.log"
DISABLED="$DIR/disabled"
WINDOW="${PATTERN_ENFORCE_WINDOW:-6}"
TMO="${PATTERN_ENFORCE_TIMEOUT:-2}"

mkdir -p "$DIR" 2>/dev/null || true

log_audit() {  # $1=session $2=tool $3=action $4=reason
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" >>"$LOG" 2>/dev/null || true
}

# Bypass 1: env var
[ "$PATTERN_ENFORCE" = "off" ] && { log_audit "?" "?" "bypass-env" "env PATTERN_ENFORCE=off"; exit 0; }

# Bypass 2: file flag
[ -f "$DISABLED" ] && { log_audit "?" "?" "bypass-file" "$DISABLED present"; exit 0; }

# Read stdin
INPUT=$(cat)
command -v jq >/dev/null 2>&1 || { log_audit "?" "?" "fail-open" "jq missing"; exit 0; }

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && { log_audit "?" "?" "fail-open" "no session_id"; exit 0; }

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

# Derive transcript_path fallback se non fornito
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  # Fallback: ~/.claude/projects/<encoded-cwd>/<sid>.jsonl
  if [ -n "$CWD" ]; then
    ENC=$(printf '%s' "$CWD" | tr '/' '-')
    CANDIDATE="$HOME/.claude/projects/$ENC/$SID.jsonl"
    [ -f "$CANDIDATE" ] && TRANSCRIPT="$CANDIDATE"
  fi
fi
[ ! -f "$TRANSCRIPT" ] && { log_audit "$SID" "$TOOL" "fail-open" "transcript not found"; exit 0; }

# Discriminator: ultimi 200 jsonl entries, cerca primo subagent_type assistant
SAT=$(tail -n 200 "$TRANSCRIPT" 2>/dev/null \
  | jq -r 'select(.type=="assistant") | .subagent_type // empty' 2>/dev/null \
  | tail -n 1)

# Non-coder o orchestrator → bypass silent (no enforcement)
if [ "$SAT" != "coder" ]; then
  log_audit "$SID" "$TOOL" "bypass-noncoder" "subagent_type=$SAT"
  exit 0
fi

# Coder: estrai window degli ultimi WINDOW messaggi assistant text
RECENT=$(tail -n 200 "$TRANSCRIPT" 2>/dev/null \
  | jq -r 'select(.type=="assistant") | .message.content[]? | .text? // empty' 2>/dev/null \
  | tail -n "$WINDOW")

# Match PATTERN: regex strict
if printf '%s' "$RECENT" | grep -E '^PATTERN: (ADD|REMOVE|REPLACE|MODIFY) \|' >/dev/null 2>&1; then
  log_audit "$SID" "$TOOL" "allow" "PATTERN found in window"
  exit 0
fi

# Block: PATTERN missing
log_audit "$SID" "$TOOL" "block" "PATTERN missing in window=$WINDOW"
jq -nc --arg r "pre-flight-pattern-enforce: missing PATTERN: header nella sliding window. ADR-0001 richiede di emettere \`PATTERN: <CATEGORY> | <payload>\` prima di ogni Edit/Write/MultiEdit. Esempio: \`PATTERN: MODIFY | path/file.py:42 rename var\`. Bypass: env PATTERN_ENFORCE=off o touch $DISABLED." '{decision:"block",reason:$r}' 2>/dev/null \
  || printf '{"decision":"block","reason":"missing PATTERN header (see ADR-0001)"}\n'
exit 0
```

Make executable: `chmod +x ~/.claude/hooks/pre-flight-pattern-enforce.sh`.

Notes:
- Pattern fail-open identico a `stop-gate.sh` (mai exit non-zero su error path).
- Lingua: comment in inglese, reason di block in italiano (user-facing).
- Audit log scrive append-only, una riga per invocazione (allow/block/bypass-*).
- Window=6 default (configurable via env `PATTERN_ENFORCE_WINDOW`).
- Bash 3.2 clean: no assoc array, no mapfile, solo grep+jq+tail.
- Performance: `tail -n 200` su jsonl, `jq -r` su subset, `grep -E` su <50KB testo. Tipico <100ms.
- NB: hard timeout 2s NON applicato direttamente in v1.0 — lo script è già fast. Pattern timeout `stop-gate.sh` può essere added in v1.1 se metriche pilota mostrano slowness.

- [ ] **Step 1: Write the hook script** — `Write` di `~/.claude/hooks/pre-flight-pattern-enforce.sh` con il content sopra.

- [ ] **Step 2: Make executable**

Verify command:
```bash
chmod +x ~/.claude/hooks/pre-flight-pattern-enforce.sh && ls -l ~/.claude/hooks/pre-flight-pattern-enforce.sh
```
Expected: permission `-rwxr-xr-x`.

- [ ] **Step 3: Create state dir**

Verify command:
```bash
mkdir -p ~/.claude/state/pattern-enforce && ls -ld ~/.claude/state/pattern-enforce
```
Expected: directory esiste.

- [ ] **Step 4: Smoke test inline (no transcript)**

Verify command:
```bash
echo '{"session_id":"test","tool_name":"Edit","cwd":"/tmp","transcript_path":"/nonexistent"}' \
  | bash ~/.claude/hooks/pre-flight-pattern-enforce.sh; echo "exit=$?"
```
Expected: `exit=0`, stdout vuoto (fail-open: transcript not found). Audit log contiene riga `fail-open`.

- [ ] **Step 5: Checkpoint** — script live, fail-open behavior verified. TodoWrite update. Harness Task-1 anchor ancora FAIL (settings.json non patchato yet — Task 3).

**Stima tempo:** 25 min.

---

### Task 3: Settings.json registration (green secondary)

**Files:**
- Modify: `~/.claude/settings.json` (append entry PreToolUse matcher `Edit|Write|MultiEdit`)

**Red phase:** baseline `grep -c 'pre-flight-pattern-enforce' ~/.claude/settings.json` returns `0`. Harness Task-7 anchor `FAIL`.

**Green phase (edit concreto):** backup pre-edit:
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak-2026-05-20
```

Editare settings.json. Strategia: leggere current shape, identificare se `hooks.PreToolUse` esiste già. Se sì, append nuovo entry alla lista. Se no, creare la chiave.

**Caso A: `hooks.PreToolUse` esiste con altri hook** (es. protect-files):

Aggiungi entry alla lista:
```json
{
  "matcher": "Edit|Write|MultiEdit",
  "hooks": [
    { "type": "command", "command": "bash ~/.claude/hooks/pre-flight-pattern-enforce.sh" }
  ]
}
```

**Caso B: `hooks.PreToolUse` non esiste:**

Creare la chiave:
```json
"PreToolUse": [
  {
    "matcher": "Edit|Write|MultiEdit",
    "hooks": [
      { "type": "command", "command": "bash ~/.claude/hooks/pre-flight-pattern-enforce.sh" }
    ]
  }
]
```

Notes:
- Coder deve usare `Read` su settings.json prima dell'edit per matchare la shape esatta.
- Validazione JSON post-edit: `jq . ~/.claude/settings.json >/dev/null && echo "OK"`. Se KO, restore da backup e fix.
- Order: l'entry nuovo viene appended in coda alla lista PreToolUse. Se `protect-files` ha matcher specifico, l'esecuzione in chain è OK (Claude Code esegue tutti i hook matching).

- [ ] **Step 1: Backup settings.json**

Verify command:
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak-2026-05-20 && diff ~/.claude/settings.json ~/.claude/settings.json.bak-2026-05-20
```
Expected: backup file presente, identical content.

- [ ] **Step 2: Read settings.json current shape** — `Read` di `~/.claude/settings.json`.

- [ ] **Step 3: Edit settings.json** — applica il caso A o B in base alla shape attuale.

- [ ] **Step 4: Validate JSON post-edit**

Verify command:
```bash
jq . ~/.claude/settings.json >/dev/null && echo "JSON OK"
```
Expected: `JSON OK`. Se errore: `mv ~/.claude/settings.json.bak-2026-05-20 ~/.claude/settings.json` e fix.

- [ ] **Step 5: Harness re-run (anchor verde)**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: tutti i 47 anchor + nuovo anchor `settings.json: pre-flight-pattern-enforce hook registered` `PASS`; summary `PASS=48 FAIL=0`, exit 0. **TARGET RAGGIUNTO** (harness PASS=48).

- [ ] **Step 6: Checkpoint** — hook registrato, harness verde. TodoWrite update. La feature è live: il prossimo Edit/Write da coder agent transita per il hook.

**Stima tempo:** 10 min.

---

### Task 4: Dedicated harness for hook (green)

**Files:**
- Create: `~/.claude/hooks/tests/pre-flight-pattern-enforce.sh` (executable, ~120 righe)
- Create: `~/.claude/hooks/tests/fixtures/` (directory per fixture jsonl, opzionale inline)

**Red phase:** il harness non esiste. `[ -f ~/.claude/hooks/tests/pre-flight-pattern-enforce.sh ]` exit 1.

**Green phase (edit concreto):** create il harness con 10 test cases (vedi spec §3.8):

```bash
#!/bin/bash
# Harness dedicato per pre-flight-pattern-enforce.sh — 10 anchor target.
HOOK="$HOME/.claude/hooks/pre-flight-pattern-enforce.sh"
TMP=$(mktemp -d)
PASS=0; FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Fixture builder
mk_jsonl() {  # $1=path $2=subagent_type $3=text_with_pattern
  : >"$1"
  printf '{"type":"user","message":{"content":[{"text":"dummy"}]}}\n' >>"$1"
  if [ -n "$2" ]; then
    printf '{"type":"assistant","subagent_type":"%s","message":{"content":[{"text":"%s"}]}}\n' "$2" "$3" >>"$1"
  else
    printf '{"type":"assistant","message":{"content":[{"text":"%s"}]}}\n' "$3" >>"$1"
  fi
}

# Test 1: allow when PATTERN ADD present + subagent_type=coder
mk_jsonl "$TMP/t1.jsonl" "coder" "PATTERN: ADD | tests/foo.py:1 add test"
echo "{\"session_id\":\"t1\",\"tool_name\":\"Edit\",\"cwd\":\"/tmp\",\"transcript_path\":\"$TMP/t1.jsonl\"}" \
  | bash "$HOOK" >"$TMP/o1" 2>&1
RC=$?
if [ "$RC" -eq 0 ] && [ ! -s "$TMP/o1" ]; then ok "1: allow PATTERN ADD coder"
else bad "1: allow PATTERN ADD coder (rc=$RC out=$(cat $TMP/o1))"; fi

# Test 2: block when PATTERN missing + coder
mk_jsonl "$TMP/t2.jsonl" "coder" "no pattern here"
echo "{\"session_id\":\"t2\",\"tool_name\":\"Write\",\"cwd\":\"/tmp\",\"transcript_path\":\"$TMP/t2.jsonl\"}" \
  | bash "$HOOK" >"$TMP/o2" 2>&1
grep -q '"decision":"block"' "$TMP/o2" && ok "2: block PATTERN missing coder" \
  || bad "2: block PATTERN missing coder (out=$(cat $TMP/o2))"

# Test 3: bypass on subagent_type != coder
mk_jsonl "$TMP/t3.jsonl" "reviewer" "no pattern here"
echo "{\"session_id\":\"t3\",\"tool_name\":\"Edit\",\"cwd\":\"/tmp\",\"transcript_path\":\"$TMP/t3.jsonl\"}" \
  | bash "$HOOK" >"$TMP/o3" 2>&1
if [ ! -s "$TMP/o3" ]; then ok "3: bypass non-coder reviewer"; else bad "3: bypass non-coder reviewer"; fi

# Test 4: bypass when subagent_type absent (orchestrator)
mk_jsonl "$TMP/t4.jsonl" "" "no pattern here"
echo "{\"session_id\":\"t4\",\"tool_name\":\"Edit\",\"cwd\":\"/tmp\",\"transcript_path\":\"$TMP/t4.jsonl\"}" \
  | bash "$HOOK" >"$TMP/o4" 2>&1
if [ ! -s "$TMP/o4" ]; then ok "4: bypass orchestrator (no subagent_type)"; else bad "4: bypass orchestrator"; fi

# Test 5: bypass via env PATTERN_ENFORCE=off
mk_jsonl "$TMP/t5.jsonl" "coder" "no pattern here"
echo "{\"session_id\":\"t5\",\"tool_name\":\"Edit\",\"cwd\":\"/tmp\",\"transcript_path\":\"$TMP/t5.jsonl\"}" \
  | PATTERN_ENFORCE=off bash "$HOOK" >"$TMP/o5" 2>&1
if [ ! -s "$TMP/o5" ]; then ok "5: bypass via env PATTERN_ENFORCE=off"; else bad "5: bypass via env"; fi

# Test 6: bypass via file flag
DISABLED="$HOME/.claude/state/pattern-enforce/disabled"
touch "$DISABLED"
mk_jsonl "$TMP/t6.jsonl" "coder" "no pattern here"
echo "{\"session_id\":\"t6\",\"tool_name\":\"Edit\",\"cwd\":\"/tmp\",\"transcript_path\":\"$TMP/t6.jsonl\"}" \
  | bash "$HOOK" >"$TMP/o6" 2>&1
RC=$?
rm -f "$DISABLED"
if [ ! -s "$TMP/o6" ]; then ok "6: bypass via file flag"; else bad "6: bypass via file flag"; fi

# Test 7: fail-open on transcript not found
echo '{"session_id":"t7","tool_name":"Edit","cwd":"/tmp","transcript_path":"/nonexistent.jsonl"}' \
  | bash "$HOOK" >"$TMP/o7" 2>&1
if [ ! -s "$TMP/o7" ]; then ok "7: fail-open transcript not found"; else bad "7: fail-open transcript"; fi

# Test 8: fail-open on malformed JSON stdin
echo "not-json" | bash "$HOOK" >"$TMP/o8" 2>&1
RC=$?
if [ ! -s "$TMP/o8" ] && [ "$RC" -eq 0 ]; then ok "8: fail-open malformed JSON stdin"
else bad "8: fail-open malformed JSON (rc=$RC out=$(cat $TMP/o8))"; fi

# Test 9: PATTERN regex strict (lowercase pattern → block)
mk_jsonl "$TMP/t9.jsonl" "coder" "pattern: add | lowercase"
echo "{\"session_id\":\"t9\",\"tool_name\":\"Edit\",\"cwd\":\"/tmp\",\"transcript_path\":\"$TMP/t9.jsonl\"}" \
  | bash "$HOOK" >"$TMP/o9" 2>&1
grep -q '"decision":"block"' "$TMP/o9" && ok "9: block lowercase pattern (regex strict)" \
  || bad "9: block lowercase pattern"

# Test 10: performance smoke (<2s)
mk_jsonl "$TMP/t10.jsonl" "coder" "PATTERN: MODIFY | path:1 ok"
START=$(date +%s)
echo "{\"session_id\":\"t10\",\"tool_name\":\"Edit\",\"cwd\":\"/tmp\",\"transcript_path\":\"$TMP/t10.jsonl\"}" \
  | bash "$HOOK" >/dev/null 2>&1
END=$(date +%s)
DUR=$((END - START))
if [ "$DUR" -le 2 ]; then ok "10: perf <=2s (was ${DUR}s)"; else bad "10: perf too slow (${DUR}s)"; fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$TMP"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
```

Make executable: `chmod +x ~/.claude/hooks/tests/pre-flight-pattern-enforce.sh`.

Notes:
- 10 anchor test deterministici. Bash 3.2-clean.
- Fixture jsonl in tempdir, cleanup automatico.
- Test 8 (malformed JSON) usa stdin `not-json`; il `jq -r` interno emette empty → fail-open path triggered.
- Test 10 (perf) tollerante: 2s ceiling per evitare flakiness su CI lente; tipical run <100ms.

- [ ] **Step 1: Write the harness** — `Write` di `~/.claude/hooks/tests/pre-flight-pattern-enforce.sh` con il content sopra.

- [ ] **Step 2: Make executable**

Verify command:
```bash
chmod +x ~/.claude/hooks/tests/pre-flight-pattern-enforce.sh && ls -l ~/.claude/hooks/tests/pre-flight-pattern-enforce.sh
```

- [ ] **Step 3: Run harness — full green**

Verify command:
```bash
bash ~/.claude/hooks/tests/pre-flight-pattern-enforce.sh; echo "exit=$?"
```
Expected: `PASS=10 FAIL=0`, exit 0. Se 1+ FAIL: debug case-by-case, fix hook script o test.

- [ ] **Step 4: Re-run review-triage-fix harness (no regression)**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: `PASS=48 FAIL=0`, exit 0. Invariato da Task 3.

- [ ] **Step 5: Checkpoint** — dedicated harness verde, hook validato end-to-end. TodoWrite update.

**Stima tempo:** 35 min.

---

### Task 5: ADR + spec status sync

**Files:**
- Modify: `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` (status line)
- Modify: `docs/superpowers/specs/2026-05-20-pre-flight-pattern-enforce-hook-design.md` (status line)

**Red phase:** ADR riga 3 dice `**Status:** Proposed — 2026-05-20`. Spec riga 3 dice `**Stato:** approvato (post-ADR) — pronto per writing-plans`.

**Green phase (edit concreto):**

1. In `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` sostituisci riga 3:
   - Da: `**Status:** Proposed — 2026-05-20`
   - A: `**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-pre-flight-pattern-enforce-hook.md; harness review-triage-fix PASS=48; dedicated harness PASS=10)`

2. In `docs/superpowers/specs/2026-05-20-pre-flight-pattern-enforce-hook-design.md` sostituisci riga 3:
   - Da: `**Stato:** approvato (post-ADR) — pronto per writing-plans`
   - A: `**Stato:** implementato — 2026-05-20 (harness PASS=48 + dedicated PASS=10; pilota organico validerà false-positive rate del coder)`

- [ ] **Step 1: Edit ADR status line.**
- [ ] **Step 2: Edit spec status line.**
- [ ] **Step 3: Verify both updated**

Verify command:
```bash
grep '^\*\*Status:\*\*' /Users/stefanoferri/Developer/vibe-coding-system/docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md && grep '^\*\*Stato:\*\*' /Users/stefanoferri/Developer/vibe-coding-system/docs/superpowers/specs/2026-05-20-pre-flight-pattern-enforce-hook-design.md
```

- [ ] **Step 4: Checkpoint** — deliverable doc allineati. TodoWrite update.

**Stima tempo:** 3 min.

---

### Task 6: Memory entry — new project file

**Files:**
- Create: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_pattern-enforce-hook.md`

**Red phase:** file non esiste.

**Green phase (edit concreto):** crea memory file con body:

```markdown
# Pre-flight pattern enforce hook

**Stato:** DEPLOYED LIVE 2026-05-20 in `~/.claude/hooks/pre-flight-pattern-enforce.sh` + `~/.claude/settings.json` PreToolUse entry + dedicated harness `~/.claude/hooks/tests/pre-flight-pattern-enforce.sh` PASS=10.

**Cosa:** hook bash 3.2-clean `PreToolUse` su `Edit|Write|MultiEdit` che blocca tool call del `coder` agent (riconosciuto via `subagent_type` nel jsonl) se manca `PATTERN: <CATEGORY> | ...` header well-formed nella sliding window degli ultimi 6 messaggi assistant. 4° layer di defense sopra ai 3 di ADR-0001 (system prompt → reviewer → v1.2 safety net → hook gate runtime).

**Bypass mechanism (3 layer):**
1. Env single-call: `PATTERN_ENFORCE=off`.
2. File flag: `touch ~/.claude/state/pattern-enforce/disabled`.
3. Remove entry da `~/.claude/settings.json` (uninstall).

**Audit log:** `~/.claude/state/pattern-enforce/audit.log` append-only, 1 riga per invocazione: timestamp + session + tool + action (allow|block|bypass-env|bypass-file|bypass-noncoder|fail-open).

**Coexistenza HARD con hook esistenti:** `protect-files.sh`, `backup-before-deploy.sh`, `auto-format.sh` restano. Ordering chained (Claude Code esegue tutti i hook matching). Pattern-enforce gira DOPO protect-files (security boundary top priority).

**Harness:**
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` PASS=47 → PASS=48 (+1 anchor `settings.json: pre-flight-pattern-enforce hook registered`).
- `~/.claude/hooks/tests/pre-flight-pattern-enforce.sh` (dedicato) PASS=10: allow/block/bypass-env/bypass-file/bypass-noncoder/bypass-orchestrator/fail-open-transcript/fail-open-json/regex-strict/perf.

**Performance:** <100ms typical (tail+jq+grep su jsonl). Hard timeout 2s (defer pattern stop-gate.sh in v1.1 se metriche pilota mostrano slowness).

**Deliverable:**
- ADR: `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` (Accepted 2026-05-20).
- Spec: `docs/superpowers/specs/2026-05-20-pre-flight-pattern-enforce-hook-design.md` (implementato 2026-05-20).
- Plan: `docs/superpowers/plans/2026-05-20-pre-flight-pattern-enforce-hook.md` (TDD 7 task, v1.0).

**Validazione pending:**
- `transcript_path` field disponibile in CLI Stefano? Fallback derive da session_id già implementato.
- False-positive rate sul coder primi 20-30 dispatch? Misurabile via audit.log.
- Performance p95 con jsonl >50MB?
Vedi ADR §4.4.

**Subsume / supersede:**
- NON subsume ADR-0001 (definizione del pattern). ADR-0004 aggiunge layer 4 di enforcement.
- Si lega architetturalmente a `feedback_bash32-constraint` (hook 3.2-clean).

**Invariante HARD:**
- Anchor preservation: PASS≥48 in ogni futuro change. Mai scendere sotto 47.
- Fail-open by construction: ogni branch errore → exit 0 + log.
- Coexistenza hook esistenti: protect-files/backup/auto-format restano intatti.
- Bypass mechanism non viene rimosso (almeno 1 layer di escape sempre presente).
```

- [ ] **Step 1: Create the memory file** — `Write` di `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_pattern-enforce-hook.md`.

- [ ] **Step 2: Verify creation**

Verify command:
```bash
test -f ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_pattern-enforce-hook.md && head -3 ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_pattern-enforce-hook.md
```
Expected: exit 0; output mostra titolo h1 + stato DEPLOYED LIVE.

- [ ] **Step 3: Checkpoint** — memory entry creato. TodoWrite update.

**Stima tempo:** 5 min.

---

### Task 7: MEMORY.md index update + final harness sync

**Files:**
- Modify: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` (append nuova riga in sezione `## Project`)

**Red phase:** `grep -c 'pattern-enforce-hook' MEMORY.md` returns `0`.

**Green phase (edit concreto):** append una nuova riga in `## Project` come voce più recente. Nuova riga:

```markdown
- [Pre-flight pattern enforce hook](project_pattern-enforce-hook.md) — **DEPLOYED 2026-05-20**: hook PreToolUse blocca Edit/Write/MultiEdit del `coder` se manca PATTERN: header (ADR-0001 layer 4); 3 bypass layer; audit log; harness PASS=48 + dedicated PASS=10
```

Notes:
- Stile identico alle voci esistenti.
- Posizionamento: dopo l'entry più recente in `## Project`.

- [ ] **Step 1: Append the new row** — edit `MEMORY.md` per inserire la nuova riga.

- [ ] **Step 2: Verify update**

Verify command:
```bash
grep -c 'pattern-enforce-hook' ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md
```
Expected: `1`.

- [ ] **Step 3: Final cross-harness sanity run**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh && bash ~/.claude/hooks/tests/pre-flight-pattern-enforce.sh; echo "exit=$?"
```
Expected: review-triage-fix `PASS=48 FAIL=0`, dedicated `PASS=10 FAIL=0`, exit 0. Conferma che tutto il sistema è coerente post-deploy.

- [ ] **Step 4: Checkpoint** — index aggiornato, harness verde end-to-end. TodoWrite update. **Implementazione completa.**

**Stima tempo:** 4 min.

---

## Harness expected delta

| Stato | review-triage-fix PASS | dedicated PASS | Note |
|---|---|---|---|
| Baseline (pre-implementazione) | 47 | n/a | 3 ADR + v1.2 anchor. Verificato 2026-05-20. |
| Post-Task-1 (red) | 47 FAIL=1 | n/a | +1 anchor settings.json fail. Exit 1. |
| Post-Task-2 (hook script) | 47 FAIL=1 | n/a | Anchor ancora fail (settings.json non patchato yet). Hook script live ma non registrato. |
| Post-Task-3 (settings.json) | 48 | n/a | Anchor verde. **TARGET review-triage-fix PASS=48.** |
| Post-Task-4 (dedicated harness) | 48 | 10 | Dedicated harness verde end-to-end. **TARGET dedicated PASS=10.** |
| Post-Task-5 (doc sync) | 48 | 10 | No harness change. |
| Post-Task-6 (memory entry) | 48 | 10 | No harness change. |
| Post-Task-7 (MEMORY.md) | 48 | 10 | **Stato finale.** |

**Delta totale dichiarato:**
- `review-triage-fix` harness PASS=47 → PASS=48 (+1 anchor su settings.json).
- Dedicated harness PASS=10 (new, target full coverage 10 test case).

**Anchor preservation invariante:** in nessun task viene rimosso o alterato uno dei 47 anchor v1.2+ADR-0001+ADR-0002+ADR-0003. Il blocco Task 7 è inserito pre-summary line, post-Task-6 (ADR-0001 coder.md block).

---

## Risk summary

- **R1 — `transcript_path` field non disponibile in CLI di Stefano.** Severity: medium. Fallback `~/.claude/projects/<enc-cwd>/<sid>.jsonl` already implementato in Task 2 Step 1. Verifica empirica al primo dispatch organico del coder post-deploy. Se ancora KO: log emerge `fail-open: transcript not found`, hook degrada a no-op silent (zero false positive).
- **R2 — False positive rate iniziale sul coder.** Severity: medium. Sotto context pressure, coder può omettere PATTERN; hook blocca; friction. Mitigazione: bypass via env/file flag; metriche audit.log catturano la baseline; ADR §4.4 open question per amendment v1.1 (window dimension, regex lenience).
- **R3 — Settings.json malformazione post-edit.** Severity: high. settings.json malformed rompe Claude Code globale. Mitigazione: backup pre-edit (Task 3 Step 1), validazione `jq . settings.json` post-edit (Task 3 Step 4), restore da backup se KO.
- **R4 — Conflitto ordering con `protect-files.sh`.** Severity: low. Entrambi PreToolUse; Claude Code esegue in ordine di registrazione. Decisione plan: append in coda (protect-files prima). Acceptable: se protect-files blocca, pattern-enforce non gira (skip, no negative interaction).
- **R5 — Performance degradation con session jsonl >50MB.** Severity: low-medium. `tail -n 200` su file di 100MB+: tipical <100ms su SSD M-series, ma worst-case 500ms-1s. Mitigazione: hard timeout 2s (defer v1.1, pattern `stop-gate.sh`). Validabile via benchmark Task 4 Step 3.
- **R6 — Bypass mechanism rotto da refactor settings.json.** Severity: low. Se utente rimuove l'entry hook senza ripristinare il flag-file, lose bypass via file (env e settings.json bypass restano). Mitigazione: doc in memory entry + ADR esplicita i 3 layer.
- **R7 — Bash 3.2 trap su nuova syntax.** Severity: low. Hook + harness usano solo subset 3.2-clean (`[ -f ]`, `&&`/`||`, `printf`, `grep -E`, `tail -n`, `jq -r`, `mktemp -d`). No assoc array, no mapfile, no `${v^^}`, no process subst. Verificato pre-Task-2.

## HITL gate

Nessun gate hard richiesto dal deploy. Edit additive su `~/.claude/hooks/` + new file + settings.json (con backup) + 1 anchor harness + doc. Nessun commit (no git). Nessun schema DB. Nessuna eliminazione permanente. Le decisioni HITL globali (`commit, push, deploy, modifica schema DB, eliminazioni permanenti`) non si applicano.

Validazione operativa POST-deploy è osservativa, non bloccante:
- Primo dispatch organico del coder agent post-deploy: verifica audit.log per `allow|block|fail-open` distribution.
- Se >20% block sui primi 20 dispatch → amendment v1.1 (window+regex tuning).
- Se >5% fail-open su transcript not found → investiga `transcript_path` availability.
