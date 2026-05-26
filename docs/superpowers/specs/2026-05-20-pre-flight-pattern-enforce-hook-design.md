# Pre-flight Pattern Enforce Hook — Design spec

**Stato:** implementato — 2026-05-20 (harness PASS=48 + dedicated PASS=10; pilota organico validerà false-positive rate del coder)
**Data:** 2026-05-20
**ADR:** `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` (Proposed)
**Plan:** `docs/superpowers/plans/2026-05-20-pre-flight-pattern-enforce-hook.md` (TDD,
6 task)

---

## 1. Problem statement

ADR-0001 ha specificato la disciplina **pre-flight pattern classifier** del `coder`
agent: prima di ogni `Edit`/`Write` tool call l'agent deve emettere un header
`PATTERN: <CATEGORY> | ...` (4 categorie). La disciplina è oggi enforced via:

1. system prompt di `~/.claude/agents/coder.md` ("you MUST emit")
2. reviewer post-hoc check (`reviewer.md` item 5)
3. `review-triage-fix` v1.2 `Add+Remove rule` (safety net per `REPLACE`)

**Gap residuo audit 2026-05-20:** niente blocca il `coder` se omette il header. Sotto
context pressure / prompt lunghi / dispatch in worktree paralleli, il livello 1
(self-discipline) può fallire silenziosamente. Layer 2 (reviewer) opera post-hoc
(filesystem già scritto). Layer 3 cattura solo `REPLACE`-incomplete, non altri pattern.

**Risultato:** garanzia ADR-0001 è "best effort", non gate runtime.

---

## 2. Goal

Introdurre un **hook bash `PreToolUse`** in `~/.claude/hooks/pre-flight-pattern-enforce.sh`
che ispeziona il transcript della sessione corrente e blocca i tool call `Edit`/`Write`/
`MultiEdit` emessi dal `coder` agent se manca un `PATTERN:` header well-formed nella
sliding window degli ultimi 6 messaggi assistant.

Coesistenza esplicita con i 3 layer ADR-0001 esistenti: il hook è **layer aggiuntivo**,
non sostitutivo. Il reviewer post-hoc check resta in-place; v1.2 Add+Remove resta
safety net per REPLACE-incomplete.

---

## 3. Decisioni di design (refinement post-ADR)

### 3.1 Hook contract input

Stdin JSON con almeno questi campi (da spec hook PreToolUse Claude Code):

```json
{
  "session_id": "<uuid>",
  "cwd": "<absolute path>",
  "tool_name": "Edit" | "Write" | "MultiEdit",
  "tool_input": { "file_path": "...", ... },
  "transcript_path": "<absolute jsonl path>"  // se versione CLI lo supporta
}
```

Se `transcript_path` manca, fallback derivare da `session_id` via convention
`~/.claude/projects/<encoded-cwd>/<session_id>.jsonl` (encoded-cwd = path con `/` → `-`).

Se entrambi mancano (o jsonl inesistente): **fail-open silent** (exit 0, allow). Audit
log riga `fail-open: transcript not found`.

### 3.2 Discriminator coder vs non-coder

Parse jsonl della window (ultimi 200 entries via `tail -n 200`), cerca il primo
messaggio assistant con field `subagent_type`. Caso:

- `subagent_type == "coder"` → enforce strict.
- `subagent_type != "coder"` (architect, reviewer, debugger, refactorer, doc-writer,
  researcher, tester) → bypass silent.
- `subagent_type` assente in tutta la window → bypass silent (orchestrator session).

### 3.3 Regex strict per PATTERN header

```
^PATTERN: (ADD|REMOVE|REPLACE|MODIFY) \|
```

- Match a inizio riga (anchor `^`).
- Categoria one-of (4 esatte).
- Separator `|` con singolo spazio prefix/suffix (relaxed solo se vuoto post-cat).
- **No semantic check del payload.** Solo presenza + forma del prefix.

### 3.4 Sliding window e match

Estrazione testo assistant dalla window:

```bash
tail -n 200 "$TRANSCRIPT" \
  | jq -r 'select(.type=="assistant") | .message.content[]? | .text? // empty' \
  | tail -n "$WINDOW"   # WINDOW=6 default
```

Match:

```bash
echo "$RECENT_TEXT" | grep -E '^PATTERN: (ADD|REMOVE|REPLACE|MODIFY) \|' >/dev/null
```

Se match → exit 0 allow. Se no match → emit block decision.

### 3.5 Block decision payload

```json
{
  "decision": "block",
  "reason": "pre-flight-pattern-enforce: missing PATTERN: header nella sliding window. ADR-0001 richiede di emettere `PATTERN: <CATEGORY> | <payload>` prima di ogni Edit/Write/MultiEdit. Esempio: `PATTERN: MODIFY | path/file.py:42 rename var`. Per bypass legittimo: vedi ~/.claude/hooks/pre-flight-pattern-enforce.sh notes."
}
```

Reason in italiano (user-facing), riferimento esplicito a ADR-0001, esempio concreto per
unblock immediato.

### 3.6 Bypass mechanism

Tre layer di bypass:

1. **Env var single-call:** `PATTERN_ENFORCE=off` → hook esce 0 immediato + log riga
   `bypass-env: session=$SID tool=$TOOL`.
2. **File flag globale:** `~/.claude/state/pattern-enforce/disabled` → hook esce 0 + log
   riga `bypass-file: session=$SID tool=$TOOL`.
3. **Disable da settings.json:** rimuovere entry hook → no execution.

Audit log path: `~/.claude/state/pattern-enforce/audit.log` (append-only). Format riga:

```
<ISO-timestamp>\t<session>\t<tool>\t<action>\t<reason>
```

Action: `allow|block|bypass-env|bypass-file|fail-open`.

### 3.7 Performance

- `tail -n 200` su jsonl: O(n) sulla coda, file mmap, <20ms tipico anche per file
  500MB+.
- `jq -r '...'` su 200 entries: 30-60ms tipico.
- `grep -E` su <50KB testo: <5ms.
- **Total expected: 50-90ms typical.**
- Hard timeout interno: 2s via pattern `stop-gate.sh` linee 77-88 (timeout/gtimeout/
  fallback subshell+kill). Su timeout → fail-open + log.

### 3.8 Tests harness dedicato

`~/.claude/hooks/tests/pre-flight-pattern-enforce.sh`. Cover:

1. **Allow PATTERN: ADD presente in window:** fixture jsonl con `subagent_type=coder` +
   ultimo assistant message contiene `PATTERN: ADD | path:1 intent`. Aspettativa: exit
   0, stdout vuoto.
2. **Block PATTERN missing:** fixture jsonl con `subagent_type=coder` ma nessun
   PATTERN header. Aspettativa: exit 0, stdout JSON `decision:block`.
3. **Bypass su subagent_type != coder:** fixture con `subagent_type=reviewer`, no
   PATTERN. Aspettativa: exit 0, stdout vuoto (no block).
4. **Bypass su subagent_type assente:** fixture orchestrator, no PATTERN, no subagent_type
   field. Aspettativa: exit 0, stdout vuoto.
5. **Bypass via env var:** `PATTERN_ENFORCE=off`, fixture coder no PATTERN. Aspettativa:
   exit 0, no block. Audit log contiene riga `bypass-env`.
6. **Bypass via file flag:** touch `~/.claude/state/pattern-enforce/disabled`, fixture
   coder no PATTERN. Aspettativa: no block. Audit log `bypass-file`. Cleanup: rm flag.
7. **Fail-open su transcript inesistente:** fixture con `transcript_path` non valido.
   Aspettativa: exit 0, no block, audit log `fail-open`.
8. **Fail-open su malformed JSON stdin:** stdin = `not-json`. Aspettativa: exit 0
   (no crash visible), audit log `fail-open`.
9. **Performance smoke:** invocazione su fixture grande (10MB jsonl) misura <500ms (con
   margine sopra tipical 100ms).
10. **PATTERN regex strict:** fixture con `pattern: add` (lowercase). Aspettativa:
    block (no match strict regex).

Target PASS=10 nel proprio harness dedicato.

### 3.9 Anchor in `review-triage-fix` harness

+1 anchor verifica presenza entry hook in `~/.claude/settings.json`:

```bash
S="$HOME/.claude/settings.json"
grep -q -- 'pre-flight-pattern-enforce' "$S" 2>/dev/null \
  && ok "settings.json: pre-flight-pattern-enforce hook registered" \
  || bad "settings.json: pre-flight-pattern-enforce hook missing"
```

Harness PASS=47 → PASS=48. Bash 3.2-clean. Inserito dopo i blocchi anchor esistenti
(post-Task-6 di ADR-0001) e prima della summary line.

### 3.10 Settings.json entry

Add a `~/.claude/settings.json` sotto `hooks.PreToolUse`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/pre-flight-pattern-enforce.sh" }
        ]
      }
    ]
  }
}
```

Edit additive: se altri hook PreToolUse esistono già (protect-files, backup-before-deploy),
estendere l'array `hooks` o creare nuovo entry con matcher specifico. Plan dettaglierà.

---

## 4. Vincoli HARD (riconfermati da ADR)

- Bash 3.2.57 only (no assoc array, no mapfile, no `${v^^}`, no process subst).
- Fail-open su qualsiasi errore interno (no exit non-zero, no crash visibile).
- Anchor preservation: PASS=47 → PASS=48 nel harness `review-triage-fix`.
- Coexistence con hook esistenti (`protect-files`, `backup-before-deploy`,
  `auto-format`): nessun event/matcher conflict.
- Read-only su file di sistema: hook NON modifica nulla (solo legge stdin + transcript +
  scrive audit.log).
- Performance <100ms typical, 2s hard timeout.

---

## 5. Cosa NON è in scope

- **Semantic validation del payload PATTERN.** L'hook valida presenza + forma del prefix
  (`PATTERN: CATEGORY |`), non la coerenza del payload con `tool_input.file_path` o la
  completezza del pair `Add:`/`Remove:` per REPLACE. Quel deep-check resta al reviewer
  (layer 2 ADR-0001) e a v1.2 (layer 3).
- **Enforcement su altri agent** (architect, reviewer, debugger, ecc.). Solo `coder`.
- **Block hard senza bypass.** Sempre presenti 3 layer di escape.
- **Cache della window.** Re-read jsonl ogni invocazione (parallel-safe, no stale).
- **Modifica al system prompt del coder.** Quel contract è già hard-coded da ADR-0001.

---

## 6. Open questions (validation pending dopo deploy)

1. `transcript_path` field disponibile in tutte le versioni CLI di Stefano?
   Fallback `~/.claude/projects/<enc>/<sid>.jsonl` da test empirico.
2. False positive rate sul coder primi 20 dispatch?
3. Performance p95 con session jsonl >50MB?

---

## 7. Riferimenti

- ADR: `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md`
- ADR-0001: `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md`
- Pattern hook bash 3.2-clean: `~/.claude/hooks/stop-gate.sh`
- Hook contract: `code.claude.com/docs/en/docs/claude-code/hooks` (PreToolUse)
- Memory `feedback_bash32-constraint.md`
