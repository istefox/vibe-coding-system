# db-backup-guardrail — Design spec

**Stato:** implementato — 2026-05-22
**Data:** 2026-05-22
**ADR:** `docs/architecture/ADR-0009-db-backup-guardrail.md` (Accepted)
**Plan:** `docs/superpowers/plans/2026-05-22-db-backup-guardrail.md` (TDD v1.1)
**Harness:** db-backup-guardrail PASS=16 FAIL=0; review-triage-fix PASS=52 FAIL=0 (post settings.json registration)

---

## 1. Problem statement

Le regole globali (`~/.claude/CLAUDE.md`) impongono HITL prima di modifiche schema DB +
backup prima di operazioni critiche, ma sono **solo testo**. Un orchestrator in auto mode
o un coder può eseguire `DROP TABLE` / `alembic downgrade` / `prisma migrate reset` contro
prod senza backup. Serve un guardrail deterministico (5° layer defense-in-depth) che
intercetti il comando Bash distruttivo PRIMA dell'esecuzione ed escali (gate ask/deny)
finché non esiste evidenza di backup recente o conferma esplicita dell'utente.

---

## 2. Hook contract (input/output)

**Evento:** `PreToolUse`, **matcher:** `Bash`.

**Input (stdin JSON, schema verificato — `feedback_pretooluse-payload-schema`):**

```json
{
  "session_id": "<uuid>",
  "transcript_path": "<absolute jsonl path>",
  "cwd": "<absolute path>",
  "agent_type": "coder" | "<other>" | (assente per orchestrator),
  "agent_id": "<id>" | (assente per orchestrator),
  "tool_name": "Bash",
  "tool_input": { "command": "<stringa del comando>" }
}
```

**Discriminante chiave:** la presenza/assenza del campo **`agent_id`** distingue
orchestrator (assente) da sub-agent (presente). Stesso meccanismo già usato da
`pre-flight-pattern-enforce` per `agent_type`.

**Output (formato MODERNO `permissionDecision`, verificato su `code.claude.com/docs`):**

- **Allow:** `exit 0` + **stdout vuoto** (nessun output = "nessuna decisione, flusso
  permessi normale" = esecuzione consentita).
- **Ask** (gate y/n all'utente): `exit 0` + stdout
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"<testo>"}}`.
- **Deny** (block): `exit 0` + stdout
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<testo>"}}`.
- Mai `exit` non-zero, mai crash visibile (fail-open infrastrutturale, vedi §7).

**Contratto verificato:** valori `permissionDecision` ∈ `allow|deny|ask|defer`. `ask`
escala all'utente con prompt di conferma y/n **anche in auto mode**. **Gap doc (NON
verificato):** comportamento di `ask` quando la decisione parte da un sub-agent (utente non
in primo piano) — per questo NON usiamo `ask` per i sub-agent (vedi §5). Questo hook NON
usa il legacy `{"decision":"block"}` (block secco, no `ask`); diverge intenzionalmente da
`stop-gate.sh` / `pre-flight-pattern-enforce.sh`.

---

## 3. Detection — pattern concreti

Pipeline: leggi `tool_input.command` → normalizza (collassa whitespace/newline a singolo
spazio, mantieni il case originale per l'audit ma matcha con `grep -iE`) → applica le
regex. Se **nessun** pattern matcha → comando non-DB-distruttivo → allow (fail-open).

### 3.1 Famiglia A — SQL distruttivo

```
A1  DROP TABLE/DATABASE/SCHEMA   \bdrop[[:space:]]+(table|database|schema)\b
A2  TRUNCATE                     \btruncate[[:space:]]+(table[[:space:]]+)?
A4  ALTER TABLE ... DROP         \balter[[:space:]]+table\b.*\bdrop\b
```

A3 (DELETE senza WHERE) e A5 (UPDATE senza WHERE) sono **composti** (match positivo +
assenza di WHERE) e vanno valutati per-statement:

```
A3  ha "delete from"  →  \bdelete[[:space:]]+from\b
    AND NON ha where  →  ! grep -iqE '\bwhere\b'
A5  ha "<tab> set"    →  \bupdate[[:space:]]+[a-z0-9_."]+[[:space:]]+set\b
    AND NON ha where  →  ! grep -iqE '\bwhere\b'
```

Implementazione A3/A5 bash 3.2-clean: estrai i candidate statement che contengono
`delete from` / `update ... set`, poi su ciascuno verifica l'assenza di `where`. Per
semplicità v1: se il comando intero contiene `delete from` e NON contiene `where` in tutto
il comando → match. (Limite: un comando con due statement, uno DELETE senza WHERE e un
altro qualunque con WHERE, sfugge — accettato per v1, annotato in §9 Open questions.)

### 3.2 Famiglia B — migration tool distruttivi

```
B1  alembic downgrade           \balembic[[:space:]]+downgrade\b
B2  prisma reset / db push      \bprisma[[:space:]]+(migrate[[:space:]]+reset|db[[:space:]]+push)\b
B3  django flush / migrate zero \b(manage\.py|django-admin)[[:space:]]+(flush|sqlflush)\b
                                o  \bmigrate[[:space:]]+[a-z_]+[[:space:]]+zero\b
B4  knex rollback/down          \bknex[[:space:]]+migrate:(rollback|down)\b
B5  sequelize undo/drop         \bsequelize[[:space:]]+db:(migrate:undo|drop)\b
B6  rails/rake db destructive   \b(rails|rake)[[:space:]]+db:(drop|reset|rollback)\b
```

### 3.3 Anti-falso-positivo (DEVONO restare allow — test case obbligatori)

| Comando | Esito atteso | Perché |
|---|---|---|
| `psql -c "DELETE FROM users WHERE id=1"` | allow | A3 esclusa da WHERE |
| `psql -c "SELECT 'drop' AS note"` | allow | nessun `drop <kw>` reale; "drop" non seguito da table/database/schema. Vedi nota* |
| `echo "remember to drop the old logs"` | allow | nessun `drop (table|database|schema)` |
| `pg_dump mydb > .backups/x.sql` | allow | comando di backup, non distruttivo |
| `alembic upgrade head` | allow | B1 è solo `downgrade` |
| `prisma migrate deploy` | allow | B2 è solo `reset`/`db push` |
| `python3 manage.py migrate` | allow | B3 è solo `flush`/`sqlflush`/`... zero` |

*Nota onesta: `SELECT 'drop table' AS note` matcherebbe A1 (`drop[[:space:]]+table`).
Questo è un falso positivo accettato (gate ask/deny fail-safe). Il test case del brief
"SELECT che contiene la parola drop nel testo → allow" è soddisfatto dal caso
`SELECT 'drop' AS col` / `-- comment drop` (drop **non** seguito da table/database/schema),
NON da `SELECT 'drop table'`. Il test harness userà la variante senza keyword-pair per il
caso allow, e potrà documentare la variante con keyword-pair come falso positivo noto.

---

## 4. Backup-check — contratto

Ordine di valutazione (corto-circuito al primo match → allow, nessun output):

1. **`DB_GUARDRAIL=off`** (env) → allow, audit `bypass-env`. (Override umano, non backup.)
2. **Marker progetto effimero** `<root>/.claude/db-is-ephemeral` presente → allow,
   audit `bypass-ephemeral`. (D4: db usa-e-getta.)
3. **Marker conferma backup** `<root>/.claude/db-backup-confirmed` con
   `mtime` entro `DB_BACKUP_MAX_AGE_HOURS` (default 24) → allow, audit `allow-marker`.
4. **File backup recente** in `<root>/.backups/` con estensione in
   {`.dump`, `.sql`, `.sql.gz`, `.dump.gz`} e mtime entro N ore → allow, audit
   `allow-backup-file`.
5. Altrimenti → **gate ask/deny** (§5), audit `ask` o `deny` in base alla presenza di
   `agent_id`. **Mai allow.**

**Risalita `<root>`:** identica a `stop-gate.sh` (linee 46-51): da `cwd` risali finché
trovi una dir con `.claude/` (o usa `.git`/filesystem root come stop). Riusa il loop
`while [ -n "$d" ] && [ "$i" -lt 40 ]`.

**Calcolo "mtime entro N ore" bash 3.2-clean (BSD/macOS):**

```bash
# now in epoch
now=$(date +%s)
# mtime epoch del file (BSD stat -f %m; fallback GNU stat -c %Y)
mt=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
case "$mt" in ''|*[!0-9]*) mt=0;; esac
age_h=$(( (now - mt) / 3600 ))
[ "$age_h" -le "$MAX_AGE_H" ] && fresh=1
```

Il file di backup più recente in `.backups/` si trova con `ls -t` + `head -1` (bash
3.2-clean, no assoc array). Itera sulle estensioni note.

**Fail-mode del backup-check (D8):** se il comando è già classificato distruttivo ma il
backup-check fallisce per errore interno (stat illeggibile, `.backups/` non accessibile) →
si entra nel **gate ask/deny** (non allow). In dubbio su comando distruttivo, si protegge;
la scelta ask/deny resta governata da `agent_id`.

---

## 5. Gate ask/deny — contratto permissionDecision (audience-aware, D3/D6)

Quando il backup-check fallisce (§4.5), l'esito dipende dalla presenza di `agent_id`:

### 5.1 Decision logic (tabella)

| Condizione | permissionDecision | Output |
|---|---|---|
| non-Bash / non-DB / jq mancante / JSON malformato | — | nessun output (allow) |
| db distruttivo + backup valido / bypass | — | nessun output (allow) |
| db distruttivo + NO backup + **`agent_id` ASSENTE** (orchestrator) | **`ask`** | JSON con reason rimedi |
| db distruttivo + NO backup + **`agent_id` PRESENTE** (sub-agent) | **`deny`** | JSON con reason "STOP e segnala" |

Selezione bash 3.2-clean: estrai `AGENT_ID` da `agent_id` con jq (`// empty`). Se
`[ -z "$AGENT_ID" ]` → ramo `ask` (orchestrator); else → ramo `deny` (sub-agent).

### 5.2 Caso sub-agent (`agent_id` presente) → `deny`, reason NON menziona bypass

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "db-backup-guardrail: comando potenzialmente distruttivo sul DB (<categoria>) senza evidenza di un backup recente. STOP: non eseguire. Questa operazione richiede un backup o una conferma esplicita dell'utente. Segnala all'orchestrator e attendi istruzioni. Non tentare di aggirare questo guardrail."
  }
}
```

### 5.3 Caso orchestrator (`agent_id` assente) → `ask`, reason elenca i rimedi legittimi

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "db-backup-guardrail: comando potenzialmente distruttivo sul DB (<categoria>) senza evidenza di un backup recente. Procedere? Per renderlo persistente: (1) esegui un backup (es. pg_dump/mysqldump in <root>/.backups/), oppure (2) se hai gia' un backup recente: touch <root>/.claude/db-backup-confirmed. Se il target e' un DB usa-e-getta: touch <root>/.claude/db-is-ephemeral. [se rilevato host non-localhost:] ATTENZIONE: possibile target di produzione."
  }
}
```

`<categoria>` è derivata dal pattern che ha matchato (es. "DROP TABLE", "alembic
downgrade"). **Razionale split** (`never-bypass-guardrails` + gap doc): `ask` escala
all'utente in primo piano (documentato), il reason può quindi elencare i rimedi; `deny`
ferma il sub-agent in modo deterministico (il comportamento di `ask` in subagent context
NON è documentato), e il suo reason NON insegna il bypass.

Emissione bash 3.2-clean: costruisci `MSG`, poi
`jq -nc --arg d "$DECISION" --arg r "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'`
con fallback `printf` se jq non disponibile (ma jq è già verificato presente a §7, il
ramo fallback è difensivo). `DECISION` ∈ {`ask`, `deny`}.

---

## 6. Audit log — schema

Path: `~/.claude/state/db-backup-guardrail/audit.log` (append-only, auto-creato).
Override dir via `DB_GUARDRAIL_DIR`. Una riga per invocazione (TAB-separated, come
`pre-flight-pattern-enforce.sh`), estesa con il **contesto agent** e la **decisione**:

```
<ISO-8601-UTC>\t<session_id>\t<agent_type>\t<agent_ctx>\t<matched_category>\t<action>\t<reason>
```

- `<agent_ctx>` ∈ {`orchestrator` (agent_id assente), `subagent` (agent_id presente)}.
  Registra il contesto che ha determinato lo split ask/deny. Campo mancante → `?`.
- `<action>` ∈ {`allow`, `ask`, `deny`, `bypass-env`, `bypass-ephemeral`, `allow-marker`,
  `allow-backup-file`, `fail-open`, `not-db`}. Sostituisce il vecchio `block` con la coppia
  `ask`/`deny` (la decisione `permissionDecision` effettivamente emessa).
- `<matched_category>` = nome pattern (`A1-DROP-TABLE`, `B1-alembic-downgrade`, ...) o `-`
  se non-DB.
- Campi mancanti → `?` (come gli altri hook).

Invariante audit: per ogni comando distruttivo senza backup, la riga registra
`action ∈ {ask, deny}` coerente con `agent_ctx` (`orchestrator`→`ask`, `subagent`→`deny`).

---

## 7. Fail-mode (riepilogo, D8)

- **Fail-OPEN** (allow, nessun output, + audit `fail-open` o `not-db`): jq mancante, JSON
  malformato/vuoto, `tool_name` != Bash, `tool_input.command` assente, **comando non matcha
  alcun pattern distruttivo**.
- **Fail-CLOSED** (gate ask/deny, mai allow): comando classificato distruttivo +
  backup-check non soddisfatto, OPPURE comando distruttivo + backup-check in errore interno.
  La scelta `ask`/`deny` segue `agent_id`.

Mai `exit` non-zero. Mai stderr che generi failure visibile. `mkdir -p` della state dir
con `|| true`.

---

## 8. Bypass mechanism (D6, sintesi operativa)

| Meccanismo | Chi lo usa | Scope | Audit action |
|---|---|---|---|
| `DB_GUARDRAIL=off` (env) | utente | single-call | `bypass-env` |
| `.claude/db-backup-confirmed` (marker, <N h) | utente | progetto, finestra N h | `allow-marker` |
| `.claude/db-is-ephemeral` (marker) | utente | progetto, permanente | `bypass-ephemeral` |
| rimozione entry da settings.json | utente | globale | (no execution) |

Nessuno di questi è azionabile dal sub-agent senza intervento umano; il reason del `deny`
per sub-agent non li menziona. Con l'esito `ask`, l'orchestrator non ha più bisogno di
creare un marker per i casi legittimi (conferma y/n al volo); i marker servono solo a
rendere persistente la conferma entro la finestra N ore.

---

## 9. Vincoli HARD (da ADR)

- Bash 3.2.57 only: no assoc array, no `mapfile`, no `${v^^}`, no `<()`, no here-string.
  Usa `grep -iE`, `tr`, `stat -f`/`stat -c` fallback, `ls -t | head -1`, loop `while`.
- Fail-open infrastrutturale + fail-closed (gate ask/deny) sul match (asimmetria motivata, §7).
- Output formato MODERNO `hookSpecificOutput.permissionDecision` (NON il legacy
  `{"decision":"block"}`): necessario per i 3 esiti allow/ask/deny.
- Audit log (esteso con `agent_ctx` + decisione) + harness dedicato (stile
  `pre-flight-pattern-enforce`).
- Anchor-preserving su tutti gli harness esistenti (review-triage-fix, ecc.).
- Reason del `deny` (sub-agent) NON suggerisce bypass.
- Read-only su file di sistema: l'hook NON modifica nulla (solo legge stdin + filesystem +
  scrive audit.log).
- Performance: <100ms typical (grep + stat + ls su dir piccola).

---

## 10. Cosa NON è in scope

- SQL parser / quoting-aware tokenization (resta lessicale, falso positivo su keyword in
  stringhe accettato come fail-safe).
- Detection prod affidabile via connection string (solo arricchimento del reason).
- Backup rilevato dal transcript della sessione (rifiutato in ADR, fragile).
- Per-statement splitting robusto per A3/A5 multi-statement (v1: match sul comando intero).
- Esecuzione automatica del backup da parte dell'hook (mai side-effect distruttivi né
  costruttivi sul DB).
- Verifica del comportamento UI reale di `ask` (prompt y/n) — il harness verifica solo il
  JSON emesso, non il dialog interattivo (vedi §11).

---

## 11. Open questions (validazione post-deploy)

1. Tasso reale di falsi positivi sui primi N comandi Bash del pilota (specie commit message
   con keyword SQL, documentazione con esempi).
2. **Comportamento di `ask` in subagent context** (gap doc): aggirato by design (`deny` per
   i sub-agent), ma da osservare se in futuro si volesse usare `ask` anche lì. Verificare
   anche che `ask` per l'orchestrator renda effettivamente il prompt y/n in auto mode.
3. **Testabilità di `ask` nel harness:** il harness asserisce il JSON emesso
   (`permissionDecision` corretto in base a `agent_id`), NON il prompt interattivo reale.
   Il gate y/n reso all'utente è verificato solo a livello di payload. Confermare sul pilota
   che l'esito UI corrisponda al payload.
4. A3/A5 multi-statement: serve splitting per `;` in v2?
5. `DB_BACKUP_MAX_AGE_HOURS` default 24 è adeguato ai workflow di Stefano o va alzato per
   backup notturni?

---

## 12. Riferimenti

- ADR: `docs/architecture/ADR-0009-db-backup-guardrail.md`
- Pattern hook bash 3.2-clean: `~/.claude/hooks/pre-flight-pattern-enforce.sh`,
  `~/.claude/hooks/stop-gate.sh` (risalita root, timeout, jq parse, audit log)
- Memory: `feedback_never-bypass-guardrails`, `feedback_pretooluse-payload-schema`,
  `feedback_bash32-constraint`
- Hook contract: `code.claude.com/docs` — PreToolUse (`hookSpecificOutput.permissionDecision`
  valori `allow|deny|ask|defer`; `ask` escala all'utente anche in auto mode; "nessun output
  = flusso permessi normale"; gap doc: comportamento `ask` in subagent context)
