# db-backup-guardrail — Implementation Plan (TDD)

> **For agentic workers:** REQUIRED SUB-SKILL: usa superpowers:subagent-driven-development
> (consigliato) o superpowers:executing-plans per implementare task-by-task. Gli step usano
> checkbox (`- [ ]`).

**Changelog:**
- v1.0 (2026-05-22): initial — TDD plan derivato da `ADR-0009-db-backup-guardrail.md` e
  dallo spec `2026-05-22-db-backup-guardrail-design.md`. 8 task: T1 harness anchor red,
  T2 hook script, T3 settings.json registration, T4 harness dedicato, T5 fail-mode +
  edge cases nel harness, T6 anchor review-triage-fix green, T7 doc status sync, T8 memory.
- v1.1 (2026-05-22): **block secco → gate ask/deny via `permissionDecision`**. T2 emette
  `hookSpecificOutput.permissionDecision` (`ask` se `agent_id` assente / orchestrator,
  `deny` se `agent_id` presente / sub-agent) invece di `{"decision":"block"}`. T4/T5
  aggiornati: i test asseriscono il `permissionDecision` corretto in base alla presenza di
  `agent_id` (orchestrator+no-backup→`ask`, sub-agent+no-backup→`deny`, backup→allow,
  ephemeral→allow, non-db→allow). Target harness dedicato 12→14. review-triage-fix anchor
  invariato (51→52). 8 task invariati.

**Goal:** introdurre `~/.claude/hooks/db-backup-guardrail.sh` — hook bash 3.2-clean
`PreToolUse` su matcher `Bash` che intercetta comandi DB distruttivi (DROP/TRUNCATE/DELETE
senza WHERE/ALTER DROP + alembic downgrade/prisma reset/django flush/knex/sequelize/rails
db:drop) ed **escala via `hookSpecificOutput.permissionDecision`** finché non c'è evidenza
di backup recente o conferma esplicita. Gate a 3 esiti: **`ask`** (prompt y/n all'utente)
se `agent_id` ASSENTE (orchestrator), **`deny`** (block) se `agent_id` PRESENTE (sub-agent),
**nessun output** (allow) se backup valido / bypass / comando non-DB. 5° layer
defense-in-depth. Soggetto: TUTTI gli agent + orchestrator (`agent_id` discrimina solo
l'esito, non l'esclusione). Fail-OPEN a monte del match (errori infra, comandi non-DB);
fail-CLOSED sul match (comando distruttivo + backup-check fallito → gate ask/deny, mai
allow). Bypass UMANO: `DB_GUARDRAIL=off`, marker `.claude/db-backup-confirmed` (<N h),
marker `.claude/db-is-ephemeral`, rimozione da settings.json. Audit log append-only in
`~/.claude/state/db-backup-guardrail/audit.log` (esteso con `agent_ctx` + decisione).

**Architecture:** nuovo executable `~/.claude/hooks/db-backup-guardrail.sh` (~180 righe
bash 3.2). Nuovo harness dedicato `~/.claude/hooks/tests/db-backup-guardrail.sh`
(target PASS>=14). Entry settings.json `PreToolUse` matcher `Bash` (append in coda,
nessun overlap con i due entry `Edit|Write*` esistenti). 1 anchor in
`~/.claude/skills/review-triage-fix/tests/run-tests.sh` (verifica entry in settings.json).
Output formato MODERNO `hookSpecificOutput.permissionDecision` (NON il legacy
`{"decision":"block"}`): necessario per i 3 esiti allow/ask/deny. Coexistence: vedi
Environment notes.

**Tech Stack:** bash 3.2.57, jq (parse stdin + emit `permissionDecision` JSON),
grep -iE (regex POSIX-EXT), `stat -f %m`/`stat -c %Y` (mtime, BSD+GNU fallback),
`ls -t | head -1`, markdown.

**Spec:** `docs/superpowers/specs/2026-05-22-db-backup-guardrail-design.md` (proposed 2026-05-22).
**ADR:** `docs/architecture/ADR-0009-db-backup-guardrail.md` (Proposed 2026-05-22).

---

## Environment notes (read first)

- **No git in `~/.claude/` né nel repo `vibe-coding-system`.** Checkpoint per task = harness
  verde + TodoWrite + report. Nessun commit. Nessun HITL gate complesso: il deploy aggiunge
  1 hook PreToolUse + 1 anchor harness + 1 entry settings.json. Inert finché un comando Bash
  DB-distruttivo non viene emesso.
- **Bash 3.2 cleanliness (`feedback_bash32-constraint`).** Vietati: assoc array, `mapfile`,
  `${v^^}`, `<()`, here-string `<<<`. Usa: `grep -iE`, `tr -s ' '`, `stat` con fallback,
  `ls -t | head -1`, loop `while`, `case` per validazione numerica.
- **Fail-mode asimmetrico (ADR D8).** Fail-OPEN su jq mancante / JSON malformato / non-Bash
  / comando non-DB. Fail-CLOSED (gate ask/deny) se comando distruttivo + backup-check
  fallito o in errore. Mai `exit` non-zero, mai crash visibile.
- **Output `permissionDecision` (ADR D3 + sezione "Contratto permissionDecision").** L'hook
  emette il formato MODERNO `{"hookSpecificOutput":{"hookEventName":"PreToolUse",
  "permissionDecision":"<ask|deny>","permissionDecisionReason":"<msg>"}}`. **NON** il legacy
  `{"decision":"block"}` (block secco, no `ask`). Split: `agent_id` ASSENTE → `ask`;
  `agent_id` PRESENTE → `deny`. Allow = nessun output. Gap doc: `ask` in subagent context
  non documentato → mai usato per sub-agent (sempre `deny`).
- **`agent_id` discrimina orchestrator vs sub-agent** (assente = orchestrator; presente =
  sub-agent). Stesso meccanismo di `pre-flight-pattern-enforce` su `agent_type`.
- **`tool_input.command` è la stringa del comando Bash** (verificato, brief + payload-schema
  memory). L'hook NON deve cercare il transcript del sub-agent (a differenza di
  pre-flight-pattern-enforce): lavora solo su `tool_input.command` + filesystem. Questo
  elimina l'intera classe di bug di path-encoding di ADR-0004.
- **Anchor preservation HARD.** Baseline verificati pre-implementazione (NON modificarli):
  review-triage-fix **PASS=51**, concept-to-code PASS=20, design-brainstorm PASS=9,
  refactor-snapshot PASS=18, vibe-status PASS=10, pre-flight-pattern-enforce **PASS=13**
  (dedicated), run-hook-tests PASS=24. Il solo harness modificato è review-triage-fix
  (+1 anchor → PASS=52). Il nuovo harness dedicato db-backup-guardrail parte da zero.
- **Backup pre-edit di settings.json (regola globale "backup prima di file critici"):**
  `cp ~/.claude/settings.json ~/.claude/settings.json.bak-2026-05-22`. settings.json rompe
  se diventa JSON malformato → backup obbligatorio prima dell'edit (T3).
- **Coexistence con hook esistenti.** Entry PreToolUse attuali: `Edit|Write` (protect-files),
  `Edit|Write|MultiEdit` (pre-flight-pattern-enforce). Il nuovo entry è matcher `Bash`:
  **nessun overlap di matcher** → no doppio prompt. `approve-test-cmd.sh` NON è un hook (CLI
  TOFU, non in settings.json). `stop-gate.sh` è su evento `Stop`. → nessun race.
- **Performance budget.** <100ms typical (grep su stringa + stat + ls su `.backups/`).

## File structure

- Create `~/.claude/hooks/db-backup-guardrail.sh` — hook ~180 righe bash 3.2, executable.
- Create `~/.claude/hooks/tests/db-backup-guardrail.sh` — harness dedicato (target PASS>=14).
- Create `~/.claude/state/db-backup-guardrail/` — state dir (mkdir -p, audit.log auto-creato).
- Modify `~/.claude/settings.json` — append entry PreToolUse matcher `Bash` (backup prima).
- Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — +1 anchor (PASS=51→52).
- Modify `docs/architecture/ADR-0009-db-backup-guardrail.md` — Proposed → Accepted (T7).
- Modify `docs/superpowers/specs/2026-05-22-db-backup-guardrail-design.md` — proposed →
  implementato (T7).
- Create `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_db-backup-guardrail.md` (T8).
- Modify `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`
  — append riga in `## Project` (T8).

Unchanged (HARD): tutti gli agent `*.md`, gli altri hook (`stop-gate.sh`, `protect-files.sh`,
`pre-flight-pattern-enforce.sh`, `auto-format.sh`, `mark-dirty.sh`), tutte le altre skill.

**Harness PASS delta atteso:** review-triage-fix PASS=51 → **52** (+1 anchor). Nuovo
harness dedicato db-backup-guardrail: **PASS>=14** (parte da 0). Tutti gli altri harness
**invariati**.

---

### Task 1 — Harness anchor failing (red)

**Files:**
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh`

**Red phase:** baseline `PASS=51 FAIL=0` (verificato). Il nuovo anchor cerca literal
`db-backup-guardrail` in `~/.claude/settings.json` — assente pre-T3. Atteso: `PASS=51 FAIL=1`,
exit non-zero.

**Green phase (edit concreto):** inserisci tra la riga 173 (ultimo anchor design-brainstorm)
e la summary line `echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"` (riga 175) il
blocco:

```bash

# --- db-backup-guardrail hook ---
S="$HOME/.claude/settings.json"
grep -q -- 'db-backup-guardrail' "$S" 2>/dev/null && ok "settings.json: db-backup-guardrail hook registered" || bad "settings.json: db-backup-guardrail hook missing"
```

Note: 1 anchor; 3.2-clean (`grep -q --` + `&&`/`||` + helper `ok`/`bad`). `$S` è già
definito sopra (riga 163), ridichiararlo è innocuo e mantiene il blocco self-contained.

- [ ] Step 1: edita run-tests.sh inserendo il blocco prima della summary line.
- [ ] Step 2: verifica fallimento.
- [ ] Step 3: checkpoint — baseline rossa confermata. TodoWrite.

**Verify command:**
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Atteso: i 51 anchor `PASS`; nuovo anchor `db-backup-guardrail hook missing` `FAIL`;
`PASS=51 FAIL=1`, exit 1.

**Stima:** 4 min.

---

### Task 2 — Hook script (green primary)

**Files:**
- Create: `~/.claude/hooks/db-backup-guardrail.sh` (executable, bash 3.2, ~180 righe)
- Create: `~/.claude/state/db-backup-guardrail/` (mkdir -p)

**Red phase:** il file hook non esiste → `[ -f ... ]` exit 1. L'anchor T1 ancora `FAIL`
(settings.json patchato in T3).

**Green phase — logica strutturale (da spec §2-§7):**

1. Header + var: `DIR="${DB_GUARDRAIL_DIR:-$HOME/.claude/state/db-backup-guardrail}"`,
   `LOG="$DIR/audit.log"`, `MAX_AGE_H="${DB_BACKUP_MAX_AGE_HOURS:-24}"`. `mkdir -p "$DIR" || true`.
2. `log_audit()` 7-campi TAB (timestamp, sid, agent_type, agent_ctx, category, action, reason) —
   copia pattern da `pre-flight-pattern-enforce.sh` linee 34-37, estendi a 7 campi.
3. **Bypass env:** `[ "$DB_GUARDRAIL" = "off" ] && { log_audit ...bypass-env; exit 0; }`
   (nessun output = allow).
4. `INPUT=$(cat)`; `command -v jq || { log_audit fail-open "jq missing"; exit 0; }`.
5. Estrai `SID`, `AGENT_TYPE`, `AGENT_ID` (`agent_id // empty`), `TOOL`, `CWD`, `CMD`
   (`tool_input.command`). Se `TOOL` != `Bash` o `CMD` vuoto → `log_audit not-db; exit 0`
   (fail-open, nessun output).
6. **Calcola contesto agent:** `[ -z "$AGENT_ID" ] && AGENT_CTX="orchestrator" || AGENT_CTX="subagent"`.
   Questo determina lo split ask/deny (passo 11) e va loggato.
7. **Normalizza** `CMD`: `NORM=$(printf '%s' "$CMD" | tr '\n' ' ' | tr -s ' ')`.
8. **Detection** (spec §3): per ogni pattern A1/A2/A4/B1-B6 fai
   `printf '%s' "$NORM" | grep -iqE '<regex>' && CAT="<name>"`. Per A3:
   `grep -iqE '\bdelete[[:space:]]+from\b'` AND `! grep -iqE '\bwhere\b'`. A5 analogo con
   `update ... set`. Prima regex che matcha → set `CAT`, break. Se nessuna → `CAT=""`.
9. Se `CAT` vuoto → comando non distruttivo → `log_audit allow not-db; exit 0` (fail-open,
   nessun output).
10. **Risalita root** da `CWD` cercando `.claude/` (loop `while ... [ "$i" -lt 40 ]`, copia
    da `stop-gate.sh` 46-51). `ROOT` può essere vuoto (nessun `.claude/` → backup-check
    degrada: solo env bypass conta; nessun marker/file → gate ask/deny).
11. **Backup-check** (spec §4), corto-circuito → allow (nessun output):
    - marker `$ROOT/.claude/db-is-ephemeral` esiste → `log_audit bypass-ephemeral; exit 0`.
    - marker `$ROOT/.claude/db-backup-confirmed` fresh (<MAX_AGE_H) → `log_audit allow-marker; exit 0`.
    - file in `$ROOT/.backups/` con est. {dump,sql,sql.gz,dump.gz} fresh → `log_audit allow-backup-file; exit 0`.
    - helper `fresh_mtime()` con `stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null`,
      `case` validazione numerica, `age_h=$(((now-mt)/3600))`, `[ "$age_h" -le "$MAX_AGE_H" ]`.
    - file recente: `ls -t "$ROOT/.backups/"*.dump "$ROOT/.backups/"*.sql ... 2>/dev/null | head -1`.
    - **fail-closed:** se durante il check uno `stat` necessario fallisce su comando già
      distruttivo → si entra nel gate ask/deny (non allow).
12. **Gate ask/deny** (spec §5) se nessuna condizione allow:
    - Scegli decisione: `[ "$AGENT_CTX" = "subagent" ]` → `DECISION="deny"` + `MSG` testo
      sub-agent (no bypass, "STOP e segnala"). Else (`orchestrator`) → `DECISION="ask"` +
      `MSG` testo orchestrator (rimedi: backup, marker; + nota host non-localhost se
      rilevato).
    - Emetti:
      `jq -nc --arg d "$DECISION" --arg r "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'`
      con fallback `printf` (come pre-flight-pattern-enforce 118-120, ma formato moderno).
    - `log_audit "$DECISION"` (action = `ask` o `deny`). `exit 0`.

`chmod +x` lo script.

- [ ] Step 1: scrivi `db-backup-guardrail.sh` (PATTERN: ADD); `mkdir -p` state dir; chmod +x.
- [ ] Step 2: smoke manuale (vedi verify — verifica entrambi gli esiti ask/deny).
- [ ] Step 3: checkpoint TodoWrite.

**Verify command:**
```bash
# deny: DROP TABLE senza backup, SUB-AGENT (agent_id presente)
TMP=$(mktemp -d); mkdir -p "$TMP/.claude"
printf '{"session_id":"s","agent_id":"a1","agent_type":"coder","tool_name":"Bash","cwd":"%s","tool_input":{"command":"psql -c \\"DROP TABLE users\\""}}' "$TMP" \
  | DB_GUARDRAIL_DIR="$TMP/state" bash ~/.claude/hooks/db-backup-guardrail.sh; echo " rc=$?"
# atteso: {"hookSpecificOutput":{...,"permissionDecision":"deny",...}} rc=0
# ask: stesso comando, ORCHESTRATOR (agent_id assente)
printf '{"session_id":"s","tool_name":"Bash","cwd":"%s","tool_input":{"command":"psql -c \\"DROP TABLE users\\""}}' "$TMP" \
  | DB_GUARDRAIL_DIR="$TMP/state" bash ~/.claude/hooks/db-backup-guardrail.sh; echo " rc=$?"
# atteso: {"hookSpecificOutput":{...,"permissionDecision":"ask",...}} rc=0
rm -rf "$TMP"
```

**Stima:** 35 min.

---

### Task 3 — settings.json registration (green)

**Files:**
- Modify: `~/.claude/settings.json` (backup prima: `cp ... .bak-2026-05-22`)

**Red phase:** anchor T1 `FAIL` (literal `db-backup-guardrail` assente in settings.json).

**Green phase (edit concreto):** nel blocco `hooks.PreToolUse` (attualmente 2 entry:
`Edit|Write` protect-files, `Edit|Write|MultiEdit` pre-flight), **append in coda** un terzo
entry:

```json
{
  "matcher": "Bash",
  "hooks": [
    { "type": "command", "command": "bash ~/.claude/hooks/db-backup-guardrail.sh" }
  ]
}
```

Vincoli: preserva gli altri 2 entry e il loro ordine. JSON deve restare valido. NON
modificare altri blocchi (`SessionStart`, `PostToolUse`, `Stop`, `permissions`, ...).

- [ ] Step 1: backup settings.json.
- [ ] Step 2: edita aggiungendo l'entry `Bash` (PATTERN: ADD).
- [ ] Step 3: valida JSON + checkpoint.

**Verify command:**
```bash
jq -e '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command | test("db-backup-guardrail")' ~/.claude/settings.json && echo "JSON ok + entry presente"
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh | tail -1; echo "exit=$?"
```
Atteso: `jq -e` true; harness `PASS=52 FAIL=0` (anchor T1 ora verde).

**Stima:** 8 min.

---

### Task 4 — Harness dedicato: detection + esito ask/deny (green)

**Files:**
- Create: `~/.claude/hooks/tests/db-backup-guardrail.sh` (bash 3.2, fixture via `mktemp -d`)

**Red phase:** harness non esiste.

**Green phase — struttura (copia scaffolding da `tests/pre-flight-pattern-enforce.sh`
16-34: `ok`/`bad`, `PASS`/`FAIL`, `TMP=$(mktemp -d)`, `run_hook` con
`env DB_GUARDRAIL_DIR="$TMP/state" bash "$HOOK"`).** Helper
`mk_payload(cmd, cwd, agent_id)` che emette il JSON
`{"session_id":"t","tool_name":"Bash","cwd":..,"agent_id":..(omesso se vuoto),"tool_input":{"command":..}}`
(escape delle doppie virgolette interne via `jq -nc --arg`; per il caso orchestrator OMETTI
`agent_id`). Helper assert `decision_is(out, val)`: estrai
`.hookSpecificOutput.permissionDecision` con jq e confronta con `val` (o asserisci stdout
vuoto per allow). Test case di questo task (detection + split ask/deny + happy path):

1. **DROP TABLE + sub-agent (agent_id presente) + no backup → `deny`** (dir con `.claude/`,
   no `.backups/`): `.hookSpecificOutput.permissionDecision == "deny"`, audit `deny`.
2. **DROP TABLE + orchestrator (agent_id ASSENTE) + no backup → `ask`** (stesso comando,
   payload senza `agent_id`): `.hookSpecificOutput.permissionDecision == "ask"`, audit `ask`.
   *(test chiave dello split — verifica che la presenza/assenza di `agent_id` cambi l'esito.)*
3. **DELETE con WHERE → allow:** `DELETE FROM users WHERE id=1` → stdout vuoto, rc 0.
4. **SELECT con "drop" nel testo → allow:** `psql -c "SELECT 'drop' AS col"` (drop NON
   seguito da table/database/schema) → stdout vuoto.
5. **backup file recente → allow:** crea `$ROOT/.backups/db.sql` (mtime now), comando
   `DROP TABLE x` (anche con agent_id presente) → stdout vuoto, audit `allow-backup-file`.
   *(verifica che il backup valido vinca sull'esito deny anche per sub-agent.)*
6. **marker db-backup-confirmed fresh → allow:** `touch $ROOT/.claude/db-backup-confirmed`,
   comando `TRUNCATE t` → allow, audit `allow-marker`.
7. **bypass env → allow:** `DB_GUARDRAIL=off`, comando `DROP DATABASE x` (con agent_id) →
   allow, audit `bypass-env`. *(verifica che il bypass env vinca sull'esito deny.)*

- [ ] Step 1: scrivi harness con i 7 test (PATTERN: ADD).
- [ ] Step 2: esegui.
- [ ] Step 3: checkpoint.

**Verify command:**
```bash
bash ~/.claude/hooks/tests/db-backup-guardrail.sh; echo "exit=$?"
```
Atteso: `PASS=7 FAIL=0`, exit 0.

**Stima:** 30 min.

---

### Task 5 — Harness dedicato: fail-mode + edge cases (green)

**Files:**
- Modify: `~/.claude/hooks/tests/db-backup-guardrail.sh` (append test 8-14)

**Red phase:** i test 8-14 non esistono.

**Green phase — append test case (edge + fail-mode, spec §7):**

8. **migration tool: alembic downgrade + sub-agent + no backup → `deny`**:
   `.hookSpecificOutput.permissionDecision == "deny"`.
9. **migration tool: alembic downgrade + orchestrator + no backup → `ask`**:
   `.hookSpecificOutput.permissionDecision == "ask"` (split anche per Famiglia B).
10. **migration tool forward NON escala: `alembic upgrade head` → allow** (regressione anti
    falso-positivo su forward migration): stdout vuoto.
11. **fail-open su tool non-Bash:** payload con `tool_name:"Edit"` → allow, audit `not-db`,
    stdout vuoto.
12. **fail-open su JSON malformato:** stdin `not-json` → rc 0, stdout vuoto, audit `fail-open`.
13. **marker ephemeral → allow:** `touch $ROOT/.claude/db-is-ephemeral`, comando `DROP TABLE x`
    (con agent_id) → allow, audit `bypass-ephemeral` (vince sull'esito deny).
14. **marker stantio NON sblocca → gate:** `db-backup-confirmed` con mtime vecchio (>N h,
    via `touch -t` di una data passata), comando `DROP TABLE x` + sub-agent →
    `.hookSpecificOutput.permissionDecision == "deny"` (verifica che il vincolo mtime sia
    effettivo, non solo presenza file). Bash 3.2-clean per back-date: `touch -t 202001010000 "$f"`.

Opzionale (se rapido): 15. **reason del `deny` (sub-agent) NON contiene "touch" né "off":**
fixture `agent_id:"a1"` + `DROP TABLE` → estrai
`.hookSpecificOutput.permissionDecisionReason` con jq, asserisci
`! grep -iq 'touch\|DB_GUARDRAIL=off\|bypass'` (lezione `never-bypass-guardrails`).
16. **reason dell'`ask` (orchestrator) CONTIENE i rimedi:** stessa fixture senza `agent_id`,
    asserisci che il reason contenga `db-backup-confirmed` o `.backups` (rimedio legittimo
    presente per l'orchestrator).

- [ ] Step 1: append test 8-14 (+15/16 opzionali) (PATTERN: ADD).
- [ ] Step 2: esegui harness completo.
- [ ] Step 3: checkpoint.

**Verify command:**
```bash
bash ~/.claude/hooks/tests/db-backup-guardrail.sh; echo "exit=$?"
```
Atteso: `PASS=14 FAIL=0` (o `PASS=16` con i due test opzionali), exit 0.

**Stima:** 30 min.

---

### Task 6 — Anchor review-triage-fix green (verify integrazione)

**Files:** nessuna modifica nuova — gate di verifica che T1+T3 hanno portato l'anchor verde
e che tutti gli altri harness sono intatti.

**Red→Green:** già coperto da T1 (red) + T3 (green). Questo task è il **gate anchor-preserving**.

- [ ] Step 1: esegui tutti gli harness vivi.
- [ ] Step 2: confronta con baseline dichiarato.
- [ ] Step 3: checkpoint.

**Verify command:**
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh | tail -1
bash ~/.claude/hooks/tests/pre-flight-pattern-enforce.sh | tail -1
bash ~/.claude/hooks/tests/run-hook-tests.sh | tail -1
bash ~/.claude/hooks/tests/db-backup-guardrail.sh | tail -1
```
Atteso: review-triage-fix `PASS=52 FAIL=0`; pre-flight-pattern-enforce `PASS=13 FAIL=0`
(intatto); run-hook-tests `PASS=24 FAIL=0` (intatto); db-backup-guardrail `PASS>=14 FAIL=0`.

**Stima:** 5 min.

---

### Task 7 — Doc status sync

**Files:**
- Modify: `docs/architecture/ADR-0009-db-backup-guardrail.md` (Status: Proposed → Accepted)
- Modify: `docs/superpowers/specs/2026-05-22-db-backup-guardrail-design.md` (proposed →
  implementato, con nota PASS finali)

**Green phase:** aggiorna le due status line. Nello spec aggiungi il PASS reale del harness
dedicato e `review-triage-fix PASS=52`.

- [ ] Step 1: edita ADR status (PATTERN: MODIFY).
- [ ] Step 2: edita spec status (PATTERN: MODIFY).
- [ ] Step 3: checkpoint.

**Verify command:**
```bash
grep -n 'Status:' docs/architecture/ADR-0009-db-backup-guardrail.md | head -1
grep -n 'Stato:' docs/superpowers/specs/2026-05-22-db-backup-guardrail-design.md | head -1
```
Atteso: ADR `Accepted`; spec `implementato`.

**Stima:** 4 min.

---

### Task 8 — Memory + index

**Files:**
- Create: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_db-backup-guardrail.md`
- Modify: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`
  (append riga in `## Project`)

**Green phase:** project memory con: hook deployato (path), pattern detection (A1-A5/B1-B6),
**gate ask/deny via `permissionDecision`** (split su `agent_id`: orchestrator→`ask`,
sub-agent→`deny`; gap doc su `ask` in subagent context → mai usato per sub-agent),
fail-mode asimmetrico (open a monte, closed sul match → ask/deny — **scelta non-standard,
evidenziala**), soggetto = tutti gli agent, bypass umano, harness PASS=14 +
review-triage-fix 52, cross-link `[[feedback_never-bypass-guardrails]]`,
`[[feedback_pretooluse-payload-schema]]`, `[[project_pattern-enforce-hook]]`. Frontmatter
coerente con le altre memory (`name`, `description`, `metadata.node_type: memory`,
`type: project`).

- [ ] Step 1: crea project memory (PATTERN: ADD).
- [ ] Step 2: append riga index in MEMORY.md (PATTERN: MODIFY).
- [ ] Step 3: checkpoint finale.

**Verify command:**
```bash
ls -la ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_db-backup-guardrail.md
grep -c 'db-backup-guardrail' ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md
```
Atteso: file presente; almeno 1 occorrenza in MEMORY.md.

**Stima:** 8 min.

---

## Harness PASS delta atteso (riepilogo)

| Harness | Baseline | Atteso post-plan |
|---|---|---|
| review-triage-fix | 51 | **52** (+1 anchor) |
| db-backup-guardrail (nuovo, dedicato) | — | **>=14** (7 detection/split + 7 fail-mode/edge; +2 opzionali) |
| pre-flight-pattern-enforce (dedicated) | 13 | 13 (intatto) |
| run-hook-tests | 24 | 24 (intatto) |
| concept-to-code | 20 | 20 (intatto) |
| design-brainstorm | 9 | 9 (intatto) |
| refactor-snapshot | 18 | 18 (intatto) |
| vibe-status | 10 | 10 (intatto) |

**Stima totale:** ~124 min.

## Rollback (HITL, no auto-delete)

Backout = ripristina `settings.json.bak-2026-05-22`, rimuovi le 2 entry da run-tests.sh,
rimuovi `db-backup-guardrail.sh` + harness + state dir. Tutte eliminazioni → HITL utente
(regola globale: mai eliminare file senza conferma). L'agent può solo *proporre* il backout.

## Riferimenti

- ADR: `docs/architecture/ADR-0009-db-backup-guardrail.md`
- Spec: `docs/superpowers/specs/2026-05-22-db-backup-guardrail-design.md`
- Pattern hook: `~/.claude/hooks/pre-flight-pattern-enforce.sh`, `~/.claude/hooks/stop-gate.sh`
- Harness scaffolding: `~/.claude/hooks/tests/pre-flight-pattern-enforce.sh`
- Memory: `feedback_never-bypass-guardrails`, `feedback_pretooluse-payload-schema`,
  `feedback_bash32-constraint`
