# ADR-0009 — db-backup-guardrail (hook PreToolUse anti-distruzione DB)

**Status:** Accepted — 2026-05-22 (implementato; hook + harness PASS=16; settings.json pending orchestrator HITL)

**Deciders:** architect (dispatch orchestrator), Stefano Ferri (approvazione finale)

**Related:** ADR-0004 (pre-flight-pattern-enforce hook — pattern hook bash 3.2-clean
riusato), ADR-0001 (coder pre-flight classifier — filosofia defense-in-depth),
`feedback_never-bypass-guardrails`, `feedback_pretooluse-payload-schema`,
`feedback_bash32-constraint`.

---

## Context

Le regole globali dell'utente (`~/.claude/CLAUDE.md`) impongono già, **come testo**:

- "HITL gate sempre prima di: commit, push, deploy, **modifica schema DB**, eliminazioni
  permanenti."
- "mai comandi distruttivi (`rm -rf`, `DROP TABLE`) senza chiedere."
- "Backup prima di modificare file critici."

Queste regole sono enforced solo dalla disciplina dell'LLM — nessun meccanismo
deterministico le applica. Lo scenario incubo "prod db deleted by accident" può
materializzarsi in due modi:

1. **Orchestrator in auto mode** che, applicando una migrazione o eseguendo un comando di
   maintenance, lancia un `alembic downgrade` / `DROP TABLE` / `prisma migrate reset`
   contro un database di produzione senza backup recente.
2. **Sub-agent coder** che, durante l'implementazione di una feature, esegue uno
   statement distruttivo via `psql`/`mysql`/CLI di migrazione.

Il sistema ha già un pattern hook consolidato (`pre-flight-pattern-enforce.sh`, ADR-0004;
`stop-gate.sh`) bash 3.2-clean, fail-open, con audit log e harness dedicato. Questo ADR
**formalizza e automatizza** le regole testuali sopra come 5° guardrail PreToolUse,
coerente con la filosofia defense-in-depth del sistema.

**Assunzioni esplicite (non validate):**

- Lo schema del payload PreToolUse è quello verificato empiricamente in
  `feedback_pretooluse-payload-schema` (campi `session_id`, `tool_input.command`,
  `agent_id`, `agent_type`, `cwd`). Verificato per i campi citati; il sotto-campo
  `tool_input.command` per i Bash tool è dato per assodato dal brief (verificato).
- Il contratto di output PreToolUse usato da questo hook è il formato **moderno**
  `exit 0 + {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":...,"permissionDecisionReason":...}}`
  (verificato su `code.claude.com/docs`, vedi sezione "Contratto permissionDecision").
  NON il legacy `{"decision":"block","reason":...}` di `stop-gate.sh` /
  `pre-flight-pattern-enforce.sh`: il formato moderno è necessario per discriminare i tre
  esiti `allow`/`ask`/`deny` (il legacy ha solo block secco, niente "ask").
- **Discriminante orchestrator vs sub-agent = presenza/assenza del campo `agent_id`** nel
  payload. Stesso meccanismo già usato da `pre-flight-pattern-enforce` per `agent_type`.
  `agent_id` assente → decisione originata dall'orchestrator / utente in primo piano;
  `agent_id` presente → decisione originata da un sub-agent in auto mode.
- **Gap doc (non verificato):** il comportamento di `permissionDecision:"ask"` quando la
  decisione parte da un sub-agent (utente NON in primo piano) NON è documentato. Per questo
  l'ADR NON si affida ad `ask` per i sub-agent (vedi D3).
- L'utente NON ha oggi una convenzione standard per la directory dei backup DB. Il
  contratto di backup-check proposto è una **nuova convenzione** introdotta da questo ADR
  (vedi Decision D2).

---

## Decision

Introdurre `~/.claude/hooks/db-backup-guardrail.sh`: hook **PreToolUse su matcher `Bash`**
che ispeziona `tool_input.command` e, se rileva un comando DB potenzialmente distruttivo
**senza evidenza di backup recente o conferma esplicita**, escala l'esito tramite
`hookSpecificOutput.permissionDecision` con un **gate a 3 esiti** (`allow`/`ask`/`deny`),
differenziato in base alla presenza di `agent_id` (orchestrator → `ask`, sub-agent →
`deny`). Bash 3.2-clean, audit log, harness dedicato, fail-mode asimmetrico (vedi D8 —
eccezione motivata al fail-open di sistema: a monte fail-open, ma dopo match+no-backup mai
`allow`).

Di seguito la decisione per ciascuna delle 8 domande architetturali.

### D1 — Detection: quali pattern intercettare

Regex `grep -E` (POSIX-EXT, case-insensitive via `grep -iE`) su `tool_input.command`,
normalizzato (whitespace collassato a singolo spazio) prima del match. Due famiglie:

**Famiglia A — SQL distruttivo (via CLI psql/mysql/sqlite3 o eredoc/`-c`):**

| # | Pattern (concettuale) | Regex EXT (case-insensitive) |
|---|---|---|
| A1 | DROP TABLE / DROP DATABASE / DROP SCHEMA | `\bdrop[[:space:]]+(table|database|schema)\b` |
| A2 | TRUNCATE | `\btruncate[[:space:]]+(table[[:space:]]+)?` |
| A3 | DELETE FROM senza WHERE | `\bdelete[[:space:]]+from\b` **AND NOT** `\bwhere\b` (nel medesimo statement) |
| A4 | ALTER TABLE ... DROP COLUMN/CONSTRAINT | `\balter[[:space:]]+table\b.*\bdrop\b` |
| A5 | UPDATE senza WHERE | `\bupdate[[:space:]]+[a-z_."]+[[:space:]]+set\b` **AND NOT** `\bwhere\b` |

**Famiglia B — tool di migrazione distruttivi:**

| # | Tool | Regex EXT (case-insensitive) |
|---|---|---|
| B1 | alembic downgrade | `\balembic[[:space:]]+downgrade\b` |
| B2 | prisma migrate reset / db push --force-reset | `\bprisma[[:space:]]+(migrate[[:space:]]+reset|db[[:space:]]+push)\b` |
| B3 | django flush / migrate zero | `\bmanage\.py[[:space:]]+(flush|sqlflush)\b` o `\bmigrate[[:space:]]+\w+[[:space:]]+zero\b` |
| B4 | knex migrate:rollback / down | `\bknex[[:space:]]+migrate:(rollback|down)\b` |
| B5 | sequelize db:migrate:undo / db:drop | `\bsequelize[[:space:]]+db:(migrate:undo|drop)\b` |
| B6 | rails db:drop / db:reset / db:rollback | `\brails[[:space:]]+db:(drop|reset|rollback)\b` o `\brake[[:space:]]+db:(drop|reset)\b` |

**Falsi-positivi controllati (DEVONO restare allow):**

- `DELETE FROM ... WHERE ...` → A3 esclude per presenza di `WHERE` → allow.
- `SELECT ... -- comment about drop table` o `SELECT 'drop' as col` → nessun pattern A
  matcha perché ancorati a `\bdrop[[:space:]]+(table|database|schema)\b` (la keyword DROP
  deve precedere TABLE/DATABASE/SCHEMA), non la parola "drop" isolata.
- `pg_dump`, `mysqldump`, `sqlite3 .dump` (comandi di backup) → non matchano nessun
  pattern distruttivo → allow (sono anzi il rimedio).
- `alembic upgrade head`, `prisma migrate deploy`, `django migrate` (forward) → NON
  matchano (B1 è solo `downgrade`; B2 è solo `reset`/`db push`) → allow.
- `git commit -m "drop table feature"` → non matcha A1 (la regex richiede `drop` seguito da
  whitespace + table/database/schema come keyword SQL; "drop table feature" matcherebbe
  A1). **Limite noto:** un commit message contenente letteralmente "drop table" produce un
  falso positivo. Mitigazione: lo statement deve apparire in un contesto eseguibile; la
  guardia non distingue stringhe quoting-aware (bash 3.2, no parser SQL). Accettato come
  trade-off; il falso positivo è fail-safe (`ask`/`deny` con messaggio chiaro, l'utente
  conferma o il sub-agent segnala).

**Razionale:** regex ancorate a keyword-pair (DROP+TABLE, non DROP isolato; DELETE+FROM
senza WHERE) minimizzano i falsi positivi sul caso "parola drop nel testo". Il matching è
volutamente lessicale e non semantico (no SQL parser) per restare bash 3.2-clean e
stack-agnostic.

### D2 — Cosa conta come backup presente/recente

Il backup-check è soddisfatto (→ `allow`, nessun output) se **una qualsiasi** di queste
condizioni è vera, in ordine di valutazione:

1. **Conferma esplicita single-call:** env var `DB_GUARDRAIL=off` (bypass, D6) — NON è un
   "backup" ma un override umano; valutato per primo.
2. **Marker di conferma esplicita:** file `.claude/db-backup-confirmed` nel project root
   (risalendo da `cwd`, come `stop-gate.sh` risale per `.claude/test-cmd`), con **mtime
   entro N ore** (`DB_BACKUP_MAX_AGE_HOURS`, default 24). File stantio (più vecchio di N
   ore) → non valido. Razionale: il marker certifica "ho fatto un backup ora", non "una
   volta nella vita".
3. **File di backup recente convenzionale:** esiste almeno un file in `<root>/.backups/`
   con estensione `*.dump`, `*.sql`, `*.sql.gz`, `*.dump.gz` e **mtime entro N ore**.
   Razionale: convenzione di directory esplicita (`.backups/`), non scan dell'intero
   filesystem (bounded, veloce).

Se nessuna condizione è vera → si entra nel gate ask/deny di D3 (mai `allow`).

**Razionale del "recente":** un backup di 3 mesi fa non protegge dallo scenario incubo.
Il vincolo mtime entro N ore lega il backup alla sessione di lavoro corrente. N
configurabile via env per workflow con backup notturni automatici (es. N=30).

### D3 — Esito del gate: ask/deny split (era: block/warn)

Quando il comando è classificato distruttivo (D1) e il backup-check NON è soddisfatto (D2)
e nessun bypass è attivo (D6), l'esito **non è un block secco uniforme** ma un gate a 3
esiti basato su `hookSpecificOutput.permissionDecision`, differenziato in base alla
presenza del campo `agent_id`:

| Condizione | permissionDecision | Audience del reason |
|------------|--------------------|----------------------|
| comando non-Bash / non-DB / jq mancante / JSON malformato | **nessun output** (allow, fail-open a monte del match) | — |
| db distruttivo + backup valido (marker `.claude/db-backup-confirmed` o file `.backups/*.dump|*.sql[.gz]` fresh <N h) | **nessun output** (allow) | — |
| db distruttivo + NO backup + bypass attivo (`DB_GUARDRAIL=off` o marker `.claude/db-is-ephemeral`) | **nessun output** (allow) | — |
| db distruttivo + NO backup + **`agent_id` ASSENTE** (orchestrator / utente in primo piano) | **`ask`** + reason | rimedi legittimi (backup + marker) |
| db distruttivo + NO backup + **`agent_id` PRESENTE** (sub-agent in auto mode) | **`deny`** + reason | "STOP e segnala all'orchestrator" — NESSUN bypass |

**Razionale dello split ask/deny:**

- **Orchestrator → `ask`:** l'utente ottiene il gate y/n interattivo che ha richiesto
  esplicitamente. `ask` escala all'utente anche in auto mode (verificato su
  `code.claude.com/docs`), quindi NON c'è bisogno di creare marker a mano per i casi
  legittimi: l'utente conferma o nega al volo. Il reason elenca i rimedi legittimi
  (backup + marker) per chi vuole rendere la conferma persistente.
- **Sub-agent → `deny`:** due ragioni convergenti. (1) **Gap doc:** `ask` potrebbe NON
  essere mostrato in subagent context (utente non in primo piano) — non documentato, non
  ci affidiamo. (2) **Disciplina:** un sub-agent non deve decidere autonomamente su un
  comando DB distruttivo — si ferma e segnala (coerente con
  `feedback_never-bypass-guardrails`). Il reason del `deny` per il sub-agent **non
  suggerisce il bypass**: dice solo "STOP, questa operazione richiede un backup o conferma
  dell'utente; segnala all'orchestrator".

Il warn puro resta rifiutato (vedi Alternatives): non previene lo scenario in auto mode.
L'esito `ask` (per l'orchestrator) sostituisce il block secco precedente perché dà
all'utente il controllo interattivo senza friction di marker, pur restando bloccante in
assenza di conferma.

### D4 — Dev vs prod: come distinguere

**Applicazione indistinta con override prod-aware.** La guardia si applica a tutti i
comandi distruttivi rilevati, indipendentemente da dev/prod. Razionale: distinguere prod
in modo affidabile è impossibile in bash 3.2-clean senza parsing della connection string
(host, porte, env var DATABASE_URL non sempre presenti nel comando). Un falso negativo
(prod scambiato per dev) è il fallimento catastrofico che la guardia esiste per prevenire.

**Escape-hatch per db usa-e-getta di dev:** marker `.claude/db-is-ephemeral` nel project
root → la guardia degrada a **no-op silent** (allow, nessun output) per quel progetto
(l'utente dichiara esplicitamente che quel repo lavora solo su DB effimeri). Decisione
UMANA, file creato dall'utente, mai dal sub-agent.

**Segnale prod opportunistico (solo per il reason, non per la decisione):** se
`tool_input.command` contiene un host non-localhost o `DATABASE_URL` con host remoto, il
reason del gate lo evidenzia ("rilevato possibile target di produzione"). Non cambia
l'esito (`ask`/`deny` resta tale), arricchisce solo l'audit/messaggio.

### D5 — Scope DB

**Stack-agnostic, sia CLI sia migration tool.** Postgres/MySQL/SQLite coperti via i
pattern CLI (Famiglia A, validi per psql/mysql/sqlite3 che ricevono SQL inline) e via i
migration tool (Famiglia B, copre alembic/prisma/django/knex/sequelize/rails). Il matching
è sul testo del comando, quindi non dipende dal driver: un `DROP TABLE` dentro
`psql -c "..."`, `mysql -e "..."`, `sqlite3 db.sqlite "..."` o un heredoc matcha
identicamente. Razionale: coerente con la natura multi-stack del sistema (Python/Swift/JS),
zero dipendenze, nessuno stack-lock.

### D6 — Bypass (decisione UMANA, mai del sub-agent)

Tre layer, tutti pensati per essere azionati dall'**utente/orchestrator**, mai dal coder.
Tutti producono `allow` (nessun output) — cortocircuitano il gate ask/deny di D3:

1. **Env var single-call:** `DB_GUARDRAIL=off` → allow immediato + audit `bypass-env`.
2. **Marker di conferma esplicita:** `.claude/db-backup-confirmed` (entro N ore, D2.2) —
   l'utente lo crea dopo aver fatto un backup.
3. **Disable da settings.json:** rimuovere l'entry hook (no execution).

(Il marker `.claude/db-is-ephemeral` di D4 è un quarto meccanismo, ma è project-scoped e
no-op anziché bypass per-call.)

**Nota — l'orchestrator non ha più bisogno di creare marker per i casi legittimi:** con
l'esito `ask` (D3), un comando distruttivo legittimo dall'orchestrator produce un prompt
y/n interattivo. L'utente conferma al volo. I marker di D6 restano utili per: (a) rendere
la conferma persistente entro la finestra N ore (D6.2), (b) i contesti dove `ask` non è
mostrato (sub-agent → ma lì la via è far fare il backup, non il bypass).

**Vincolo dal feedback `never-bypass-guardrails`:** il reason del gate, quando `agent_id`
è presente (sub-agent), produce `deny` e **NON menziona alcun metodo di bypass** — dice
solo "STOP e segnala all'orchestrator". Solo quando `agent_id` è assente (orchestrator) il
reason (con esito `ask`) elenca i rimedi legittimi (backup + marker). Questo evita di
insegnare il bypass al coder.

### D7 — Coesistenza con altri hook

Il db-backup-guardrail è **PreToolUse su matcher `Bash`**. Gli altri PreToolUse esistenti
sono su matcher `Edit|Write` (protect-files) e `Edit|Write|MultiEdit`
(pre-flight-pattern-enforce). **Nessun overlap di matcher con questi due** → nessun
doppio-prompt con essi.

L'unico co-abitante su `Bash` è `approve-test-cmd.sh`, che però **NON è un hook** (è una
CLI TOFU invocata manualmente, non in `settings.json` come hook PreToolUse). `stop-gate.sh`
è su evento `Stop`, non `PreToolUse`. Quindi **nessun race / doppio prompt** con gli hook
attivi.

Ordine in `settings.json`: nuovo entry PreToolUse con matcher `Bash`, **dopo** i due entry
`Edit|Write*` esistenti (l'ordine tra matcher disgiunti è irrilevante, ma append in coda
preserva la leggibilità dei diff). Quando in futuro venisse aggiunto un altro hook su
`Bash`, l'ordine andrà riconsiderato; per ora è isolato.

### D8 — Chi è soggetto + fail-mode

**Tutti gli agent + l'orchestrator.** A differenza di `pre-flight-pattern-enforce`
(solo-coder, perché enforca un contract specifico del coder), lo scenario "prod db deleted"
può originare sia dall'orchestrator (auto mode, maintenance) sia da un coder (migrazione in
una feature). Quindi **nessun filtro che escluda agent**: la guardia valuta ogni comando
Bash distruttivo, chiunque lo emetta. La presenza/assenza di `agent_id` non filtra *chi è
soggetto* — soggetti sono tutti — ma **discrimina solo l'esito del gate** (`ask` per
l'orchestrator, `deny` per il sub-agent) e il testo del reason (D3/D6).

**Fail-mode — eccezione motivata al fail-open di sistema:**

- **Fail-OPEN sugli errori infrastrutturali a monte del match** (jq mancante, JSON
  malformato, stdin vuoto, comando non-DB): se la guardia non riesce nemmeno a determinare
  se il comando è distruttivo, **nessun output** (allow) + audit `fail-open`/`not-db`.
  Coerente col sistema: una guardia che crasha non deve bloccare il lavoro legittimo
  non-DB.
- **Fail-CLOSED una volta che il comando è classificato distruttivo** e il backup-check
  non è soddisfatto: gate ask/deny (mai `allow`). Inoltre, se il match distruttivo è certo
  ma il backup-check stesso fallisce per errore interno (es. impossibile leggere mtime), si
  entra comunque nel gate ask/deny (non allow): in dubbio su un comando già riconosciuto
  come distruttivo, si protegge. La scelta tra `ask` e `deny` resta governata da `agent_id`
  anche nel ramo di errore interno.

Razionale: il fail-open globale del sistema è giusto per guardie di disciplina
(pattern-enforce); per una guardia di **sicurezza dati irreversibile** il default su
ambiguità deve essere conservativo, ma **solo dopo** che il comando è stato riconosciuto
distruttivo — non si blocca mai un comando non-DB per un errore interno. Questo bilancia
sicurezza e friction.

---

## Contratto permissionDecision (formato moderno, verificato)

Questa sezione documenta il contratto di output usato dall'hook, sostituendo il block secco
legacy.

**Formato output (stdout, exit 0 sempre):**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "<allow|deny|ask|defer>",
    "permissionDecisionReason": "<testo>"
  }
}
```

**Valori `permissionDecision` (verificato su `code.claude.com/docs`):**

- `allow` — esegue il tool senza prompt. *Questo hook non lo emette esplicitamente: per
  l'esito allow non emette alcun output* (vedi nota sotto).
- `deny` — blocca l'esecuzione del tool. Il sub-agent si ferma e riceve il reason.
- `ask` — escala all'utente con un prompt di conferma y/n. **Funziona anche in auto mode**
  (la doc conferma: `ask` escala all'utente anche quando auto mode salterebbe i dialog).
- `defer` — non usato da questo hook.

**Convenzione "nessun output = allow":** quando l'hook decide allow (comando non-DB, backup
valido, bypass attivo) NON emette alcun JSON ed esce 0. La doc specifica: se l'hook non
emette output → "nessuna decisione, flusso permessi normale" (= esecuzione consentita).
Questo evita di forzare un `allow` esplicito che potrebbe scavalcare altri hook/permessi.

**Gap doc — comportamento di `ask` in subagent context (NON verificato):** la doc NON
documenta cosa accade quando `permissionDecision:"ask"` è emesso mentre la decisione parte
da un sub-agent (utente non in primo piano). Potrebbe: (a) non mostrare il prompt e
proseguire, (b) bloccare implicitamente, (c) escalare all'orchestrator. **Nessuno di questi
è garantito.** Per questo l'hook NON usa `ask` per i sub-agent: se `agent_id` è presente,
emette `deny` (esito definito e sicuro). `ask` è riservato all'orchestrator (`agent_id`
assente), dove l'utente È in primo piano e il prompt è documentato come funzionante.

**Discriminazione orchestrator vs sub-agent:** presenza/assenza del campo `agent_id` nel
payload (stesso meccanismo già usato da `pre-flight-pattern-enforce` per `agent_type`).
`agent_id` assente → `ask`; `agent_id` presente → `deny`.

**Razionale ask/deny (sintesi):** orchestrator ottiene il gate interattivo richiesto
(niente marker manuali per i casi legittimi); sub-agent ottiene un block deterministico che
lo ferma e lo fa segnalare, senza affidarsi a un comportamento `ask` non documentato e
senza insegnare il bypass.

**Esempio output `ask` (orchestrator, no backup):**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "db-backup-guardrail: comando potenzialmente distruttivo sul DB (DROP TABLE) senza evidenza di un backup recente. Procedere? Per renderlo persistente: esegui un backup in <root>/.backups/ oppure conferma con touch <root>/.claude/db-backup-confirmed. Se il target e' un DB usa-e-getta: touch <root>/.claude/db-is-ephemeral."
  }
}
```

**Esempio output `deny` (sub-agent, no backup):**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "db-backup-guardrail: comando potenzialmente distruttivo sul DB (DROP TABLE) senza evidenza di un backup recente. STOP: non eseguire. Questa operazione richiede un backup o una conferma esplicita dell'utente. Segnala all'orchestrator e attendi istruzioni. Non tentare di aggirare questo guardrail."
  }
}
```

**Fail-mode asimmetrico preservato:** fail-open a monte del match (nessun output = allow);
dopo match + no-backup → mai `allow`, sempre `ask` (orchestrator) o `deny` (sub-agent).

---

## Alternatives considered (per ognuna delle 8 domande)

### D1 — Detection

- **AST/SQL parser per match semantico (es. sqlparse, libpg_query):** rifiutata. Introduce
  una dipendenza stack-locked, viola bash 3.2-clean e zero-dep. Il guadagno in precisione
  non giustifica il costo per un guardrail che è comunque un layer (non l'unica difesa).
- **Match su parola `drop`/`delete`/`truncate` isolata:** rifiutata. Falsi positivi
  inaccettabili (SELECT con "drop" nel testo, commit message). Le regex keyword-pair sono
  il compromesso.
- **Allowlist invece di denylist (blocca tutto tranne pattern noti safe):** rifiutata.
  Bloccherebbe ogni comando Bash di default → friction enorme, incompatibile con auto mode.

### D2 — Backup presente/recente

- **Solo presenza di un file in `.backups/` senza vincolo mtime:** rifiutata. Un backup
  stantio non protegge dallo scenario incubo; darebbe falsa sicurezza.
- **Backup rilevato dal transcript (comando pg_dump eseguito nella stessa sessione):**
  rifiutata come meccanismo primario. Fragile (parsing transcript, encoding path già fonte
  di bug in ADR-0004 v1.1), e un pg_dump fallito ma presente nel transcript darebbe falso
  positivo. Tenuto eventualmente come arricchimento futuro, non in scope ora.
- **Nessun concetto di "recente", solo marker permanente:** rifiutata, stesso problema del
  backup stantio.

### D3 — Esito del gate (ask/deny vs block secco vs warn)

- **Block secco uniforme (`{"decision":"block"}` legacy, esito unico per tutti):** rifiutata
  (era la decisione precedente). Il legacy non distingue audience né offre il prompt
  interattivo: l'orchestrator era costretto a creare un marker a mano anche per operazioni
  legittime → friction. Il formato moderno `permissionDecision` permette `ask` per
  l'orchestrator (gate y/n al volo) e `deny` per il sub-agent (block deterministico), che
  è strettamente superiore.
- **`ask` per tutti (anche sub-agent):** rifiutata. Il comportamento di `ask` in subagent
  context NON è documentato (gap doc): potrebbe non mostrare alcun prompt e proseguire,
  vanificando la guardia per il caso coder. Inoltre violerebbe `never-bypass-guardrails`
  (un sub-agent non deve decidere su un comando distruttivo). Per il sub-agent serve un
  esito definito = `deny`.
- **`deny` per tutti (anche orchestrator):** rifiutata. Funzionerebbe ma è inutilmente
  rigido per l'orchestrator/utente in primo piano: nega senza dare la via interattiva,
  costringendo a creare marker a mano. `ask` dà il gate y/n richiesto dall'utente.
- **Solo warn (audit, no gate):** rifiutata. In auto mode l'LLM ignorerebbe il warn e
  procederebbe — non previene lo scenario.

### D4 — Dev vs prod

- **Detection prod via parsing connection string / DATABASE_URL:** rifiutata come
  discriminante della decisione. Inaffidabile (host non sempre nel comando, env var non
  catturabili dall'hook), e un falso negativo è catastrofico. Usata solo per arricchire il
  reason del gate.
- **Applicare solo a prod (skip dev):** rifiutata. Richiederebbe la detection prod
  affidabile sopra, che non esiste. Default più sicuro = applicare a tutti, con escape
  esplicito per db effimeri.

### D5 — Scope DB

- **Solo Postgres via psql:** rifiutata. Il sistema è multi-stack; coprire un solo motore
  lascia buchi (un progetto Django/MySQL resterebbe scoperto).
- **Solo migration tool (no SQL CLI diretto):** rifiutata. Un `psql -c "DROP TABLE"` diretto
  è proprio il caso più pericoloso e bypasserebbe la guardia.

### D6 — Bypass

- **Bypass via flag inline nel comando (es. `# db-guardrail-ok`):** rifiutata. Un sub-agent
  potrebbe aggiungerlo da sé → viola `never-bypass-guardrails`.
- **Reason del gate uguale per tutti gli audience (con istruzioni di bypass):** rifiutata
  esplicitamente — è l'errore corretto in ADR-0004 v1.2. Il reason del `deny` per il
  sub-agent non deve insegnare il bypass; solo l'`ask` per l'orchestrator elenca i rimedi.

### D7 — Coesistenza

- **Matcher `*` (tutti i tool):** rifiutata. Sprecato (la guardia ha senso solo su Bash);
  introdurrebbe overlap inutile con protect-files e pattern-enforce.
- **Fondere nel pre-flight-pattern-enforce esistente:** rifiutata. Viola single
  responsibility (uno enforca contract coder su Edit/Write, l'altro protegge il DB su
  Bash); harness e fail-mode diversi (pattern-enforce è fail-open puro, questo è
  fail-closed sul match). Tenerli ortogonali è coerente col "triple-angle coverage" delle
  agent-notes.

### D8 — Chi è soggetto + fail-mode

- **Solo-coder (come pre-flight-pattern-enforce):** rifiutata. L'orchestrator in auto mode
  è una sorgente realistica dello scenario incubo; escluderlo lascia il buco principale.
- **Fail-open puro (come gli altri hook del sistema):** rifiutata per la fase post-match.
  Per una guardia di dati irreversibili, l'ambiguità su un comando già riconosciuto come
  distruttivo deve risolversi nel gate ask/deny (mai allow). Si conserva il fail-open solo
  a monte (errori infrastrutturali / comandi non-DB) per non aggiungere friction al lavoro
  legittimo.

---

## Consequences

### Positive

- Le regole testuali di `~/.claude/CLAUDE.md` su DB diventano enforced deterministicamente.
- Previene lo scenario incubo "prod db deleted" sia da orchestrator sia da coder.
- **Gate interattivo per l'orchestrator (`ask`):** l'utente ottiene un prompt y/n al volo
  per le operazioni legittime, senza dover creare marker a mano. Friction ridotta rispetto
  al block secco precedente.
- **Block deterministico per il sub-agent (`deny`):** il coder si ferma e segnala, senza
  affidarsi a un comportamento `ask` non documentato e senza imparare il bypass.
- Stack-agnostic, zero dipendenze, coerente col pattern hook consolidato (ADR-0004).
- Audit log fornisce traccia di ogni comando distruttivo intercettato + la decisione presa
  (ask/deny/allow) + il contesto agent.
- Ortogonale agli altri guardrail: nessun race, nessun doppio prompt.

### Negative

- **Falsi positivi possibili** su comandi che contengono letteralmente keyword-pair SQL in
  contesti non eseguibili (es. commit message "drop table X", documentazione con esempi
  SQL). Mitigazione: il falso positivo è fail-safe (`ask`/`deny` + reason chiaro), l'utente
  conferma o il sub-agent segnala. Il tasso reale va misurato sul pilota.
- **Friction su DB di dev usa-e-getta** finché l'utente non crea `.claude/db-is-ephemeral`.
- Il fail-closed sul match introduce un'asimmetria rispetto agli altri hook (tutti
  fail-open): richiede documentazione chiara per non confondere il debugger in futuro.
- **Comportamento `ask` in subagent context non garantito (gap doc):** mitigato non usando
  `ask` per i sub-agent (sempre `deny`). Resta il rischio teorico che `ask` non si comporti
  come atteso anche per l'orchestrator in qualche edge (es. orchestrator dispatchato a sua
  volta) — va validato sul pilota.
- **Testabilità di `ask` nel harness:** il harness verifica il JSON di output
  (`permissionDecision` corretto in base alla presenza di `agent_id`), NON il prompt
  interattivo reale (non riproducibile in un harness headless). Il gate y/n reso all'utente
  è quindi verificato solo per il payload emesso, non per il comportamento UI di Claude
  Code. Limite noto, annotato come open question.
- Possibile **finestra di confusione** se l'utente ha backup automatici notturni e N=24h
  copre, ma un giorno il cron salta: la guardia escalerebbe (`ask`/`deny`). Mitigazione: N
  configurabile.

### Neutral

- **Contratto di output PreToolUse risolto:** l'open question precedente (legacy `decision`
  vs moderno `permissionDecision`) è chiusa a favore del formato moderno
  `hookSpecificOutput.permissionDecision`, verificato su `code.claude.com/docs` e necessario
  per i tre esiti. Questo hook diverge intenzionalmente dal formato legacy usato da
  `stop-gate.sh` / `pre-flight-pattern-enforce.sh` (block secco): è l'unico hook del sistema
  a usare il formato moderno, perché è l'unico che richiede `ask`.
- **Gap doc residuo:** `ask` in subagent context non documentato → aggirato by design
  (`deny` per i sub-agent). Resta da validare sul pilota.
- La nuova convenzione `.backups/` + `.claude/db-backup-confirmed` + `.claude/db-is-ephemeral`
  è introdotta da questo ADR; va documentata in un eventuale CLAUDE.md di progetto target.
- Repo `vibe-coding-system` NON-git: i deliverable sono i 3 markdown; il deploy effettivo
  degli artefatti live (`~/.claude/`) è un task separato (il plan TDD), senza commit step.

---

## References

- ADR-0004 — `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` (pattern hook
  bash 3.2-clean, fail-open, audit, harness; messaggio block che non insegna bypass al coder)
- ADR-0001 — `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md`
  (defense-in-depth multi-layer)
- `~/.claude/hooks/pre-flight-pattern-enforce.sh` (v1.2 — riferimento implementativo;
  discrimina su `agent_type`, stesso meccanismo qui usato per `agent_id`)
- `~/.claude/hooks/stop-gate.sh` (pattern timeout, risalita root per `.claude/`, jq parse)
- Memory: `feedback_never-bypass-guardrails`, `feedback_pretooluse-payload-schema`,
  `feedback_bash32-constraint`
- `~/.claude/CLAUDE.md` (regole globali su HITL DB + comandi distruttivi + backup)
- Hook contract: `code.claude.com/docs` — PreToolUse (verificato: schema payload con
  `agent_id`/`agent_type`; `hookSpecificOutput.permissionDecision` valori
  `allow|deny|ask|defer`; `ask` escala all'utente anche in auto mode; "nessun output =
  nessuna decisione, flusso permessi normale"). **Gap verificato:** comportamento di `ask`
  in subagent context NON documentato.
