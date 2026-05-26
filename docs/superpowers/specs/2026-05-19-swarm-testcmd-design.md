# Design — Stop-gate definitivo: dichiarazione esplicita test-cmd + TOFU + scala a 3 livelli

> Data: 2026-05-19
> Stato: design approvato (brainstorming), pre-implementazione
> Scope: `~/.claude/` (globale) — sostituisce il gate Fase A deployato
> Supera: `docs/superpowers/specs/2026-05-19-agentic-swarm-design.md` §4.1/§4.2/§4.5
> Origine: finding T11 live — `clear-dirty-on-test.sh` infersce via euristica
> pattern/grep e fallisce su runner non-standard (harness bash, monorepo,
> `uv run pytest`, `make test`…). L'inferenza è il difetto di fondo.

## 1. Obiettivo

Sostituire l'inferenza euristica ("i test sono stati eseguiti e sono verdi?")
con **verifica deterministica** basata su una **dichiarazione esplicita
per-progetto** del comando test, eseguita autorevolmente dal gate sull'**exit
code reale**, dietro un modello di fiducia **TOFU** (trust-on-first-use). Il
gate mantiene copertura globale tramite una **scala a 3 livelli** che degrada
in modo sicuro, senza euristiche e senza esecuzione di codice non fidato.

## 2. Non-obiettivi (YAGNI)

- Nessun auto-discovery del runner (pytest/npm guessing): è inferenza, la
  causa del difetto. Eliminata.
- Nessun parsing dell'output dei test (grep `FAILED`/`Traceback`): eliminato.
  La verità è l'exit code.
- Nessun sandbox/jail del comando approvato: gira con shell/env utente
  (equivalente a lanciarlo a mano — accettabile perché esplicitamente
  approvato via TOFU).
- Fase B/C del design agentic-swarm originale sono **sussunte**: il "tier
  autoritativo" È la Fase B fatta correttamente. Non si specca altro qui.

## 3. Architettura — scala a 3 livelli

Il gate decide sempre la stessa domanda: *"codice cambiato (`.dirty`) senza
verifica?"*. Cambia solo **come ottiene la verifica**, in ordine
deterministico. Nessun ramo usa euristiche.

| Stato progetto | Tier | Comportamento |
|---|---|---|
| `.claude/test-cmd` assente | **nudge** | block bounded ("codice cambiato: esegui i test o dichiara `.claude/test-cmd`"), poi anti-loop allow+warn |
| `.claude/test-cmd` = `NONE` | **opt-out** | fail-open (allow) — repo doc-only dichiarano questo una riga |
| `.claude/test-cmd` reale, **non** in registro TOFU o hash diverso | **approve** | block bounded; `reason` contiene il comando esatto di approvazione; **nessuna esecuzione** |
| `.claude/test-cmd` reale, **trusted** | **autoritativo** | esegue il comando (cwd=root progetto, timeout); exit 0 → cancella `.dirty`, allow; exit ≠0 → block bounded, `reason`="test falliti: <coda output>" |

Proprietà garantite: copertura broad (ogni progetto sporco riceve almeno un
nudge bounded), zero euristiche (clear solo per exit 0 autoritativo o opt-out
esplicito), sicurezza (mai exec di comando assente/`NONE`/non approvato).

## 4. Componenti

### 4.1 `.claude/test-cmd` (per-progetto, nel repo)

- File testuale nel progetto. La **prima riga non vuota e non iniziante con
  `#`** è interpretata: se uguale (trim) al token `NONE` → opt-out; altrimenti
  → comando shell test canonico. Righe successive ignorate.
- Esempi: `pytest -q` · `bash ~/.claude/hooks/tests/run-hook-tests.sh` ·
  `make test` · `NONE`.

### 4.2 Registro TOFU `~/.claude/state/stop-gate/trust`

- Una riga per entry approvata: `<sha256>\t<abs-project-root>` (TAB-separato).
- "Trusted" ⟺ esiste una riga con **path-progetto corrente** E
  **sha256 corrente** del file `.claude/test-cmd`. Se il contenuto cambia,
  l'hash non matcha → torna a tier *approve* (ri-approvazione necessaria).
- `sha256` = digest dei byte del file (`shasum -a 256` / `sha256sum`,
  fallback gestito; vedi §6).

### 4.3 `stop-gate.sh` (riscritto — sostituisce la Fase A deployata)

Logica su `Stop` (hook `type: command`):

1. Legge stdin JSON; `session_id` (assente → fail-open exit 0); `cwd`.
2. `DIR=${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}`. Se
   `<DIR>/<sid>.dirty` assente → exit 0 (allow).
3. **Project root**: da `cwd`, ricerca verso l'alto della `.claude/test-cmd`
   più vicina, risalendo fino a `$HOME` o `/` (deterministica, non euristica).
   Nessuna trovata → tier **nudge**.
4. Risoluzione tier come tabella §3. I tier che bloccano passano dal guardrail
   anti-loop §5 (contatore `<sid>.count`, cap `N`=`${STOP_GATE_MAX_REENTRY:-3}`):
   sotto cap → `count++` + `{"decision":"block","reason":"…"}`; a cap → exit 0
   + warning su stderr.
5. Tier **autoritativo**: esegue il comando con `timeout`/equivalente
   (`${STOP_GATE_TEST_TIMEOUT:-120}`s) nella project root. Exit 0 → `rm -f
   <sid>.dirty`, exit 0 (allow). Exit ≠0 → ramo block bounded con coda output
   nel `reason`. Timeout/comando-non-eseguibile → §7 fail-open.

### 4.4 `approve-test-cmd.sh` (nuovo — CLI utente, NON un hook)

- Stile `direnv allow`. Uso: `bash ~/.claude/hooks/approve-test-cmd.sh
  [project-root]` (default: cwd, con stessa ricerca verso l'alto di §4.3).
- Legge `.claude/test-cmd`, calcola sha256, appende `<sha256>\t<abs-root>` al
  registro **se non già presente** (idempotente). Stampa conferma esplicita
  del comando che verrà reso autoritativo. Non esegue il comando.
- Mai invocato automaticamente: solo l'utente lo lancia (il `reason` del tier
  *approve* gliene fornisce la riga esatta).

### 4.5 Ritiri e invarianti

- **Ritirato**: `clear-dirty-on-test.sh` — script eliminato e **unwired** da
  `settings.json` (hook PostToolUse `Bash` rimosso).
- **Invariati**: `mark-dirty.sh` (PostToolUse `Edit|Write` → setta `.dirty`),
  `ensure-state-dir.sh` (SessionStart), `reset-gate-counter.sh`
  (UserPromptSubmit).

## 5. Guardrail anti-loop (invariato da agentic-swarm §5)

Contatore per-`session_id` (`<sid>.count`). Ogni block previsto incrementa; a
`count >= N` (default 3) → niente block, exit 0 + warning su stderr.
`UserPromptSubmit` resetta. Cinge **tutti** i tier che bloccano (nudge,
approve, autoritativo-rosso).

## 6. Sicurezza (TOFU) — dettagli

- Nessuna esecuzione se `.claude/test-cmd` è assente, `NONE`, non in registro,
  o con hash divergente. L'esecuzione avviene **solo** nel tier autoritativo.
- Hash: `shasum -a 256` o `sha256sum` (qualunque presente); se nessuno dei due
  è disponibile → impossibile validare il trust → **fail-open** (no exec, no
  block per errore: §7), con warning su stderr.
- Il comando approvato eredita shell/PATH/env dell'utente: equivalente a
  esecuzione manuale, accettabile perché l'utente ha approvato esplicitamente
  quel contenuto esatto (hash-pinned).
- Registro creato con permessi utente di default; path sotto `~/.claude/state/`.
- Cambiare `.claude/test-cmd` invalida l'approvazione (hash mismatch) → forza
  re-`approve` cosciente: difesa contro modifica ostile post-approvazione.

## 7. Error handling / fail-open (legge non negoziabile)

Tutti i seguenti → **exit 0, nessun block, mai exit 2**:
`jq` mancante · `session_id` non parsabile · `.claude/test-cmd` illeggibile ·
nessun tool sha256 · registro non leggibile/scrivibile · comando autoritativo
non eseguibile/non trovato · **timeout** del comando autoritativo.
Razionale timeout→fail-open: un hook `Stop` globale che si incastra su una
suite appesa bloccherebbe ogni sessione di ogni progetto; meglio sotto-gated
che wedge globale. Solo i tier deliberati (§3) bloccano, sempre cinti
dall'anti-loop §5.

## 8. Data flow & migrazione

- Flow: `Edit|Write` → `mark-dirty` setta `.dirty`. `Stop` → `stop-gate`
  risolve tier. Nuovo prompt → `reset-gate-counter` azzera `.count`.
- Migrazione (modifica **globale** `~/.claude/`): sostituzione
  `stop-gate.sh`; aggiunta `approve-test-cmd.sh`; eliminazione
  `clear-dirty-on-test.sh`; rimozione del suo hook PostToolUse `Bash` da
  `settings.json` (merge **sottrattivo** mirato, preservando tutto il resto).
  Backup pristine + MANIFEST prima di qualunque scrittura; **HITL gate**
  esplicito con diff mostrato prima di toccare `settings.json` (CLAUDE.md
  globale; coerente con la disciplina già applicata).

## 9. Rollback / backout tracciato (spec §12-style)

- Dir backup `~/.claude/state/backups/2026-05-19-swarm-testcmd/`. **Prima di
  qualunque scrittura**, copiarvi i file *modificati o rimossi*: `settings.json`,
  `stop-gate.sh`, **e** `clear-dirty-on-test.sh` (va backup-ato perché viene
  eliminato e il backup `2026-05-19-swarm-fase-A` precedente non lo conteneva).
  `MANIFEST.md` elenca per ogni file: azione (modified|removed|created),
  timestamp, path-backup.
- Backout: ripristina i *modificati* dal backup; rimuovi i *nuovi*
  (`approve-test-cmd.sh`) con conferma HITL; ricrea il *rimosso*
  (`clear-dirty-on-test.sh`) dal backup e ri-wire il suo hook; sessione fresca.
- Trigger di rollback: loop non cinto, fail-closed osservato, regressione su
  progetto reale, exec inattesa di comando non approvato.

## 10. Testing strategy

Harness bash esteso (`STOP_GATE_STATE_DIR` isolato + project root temporanei):

1. `.claude/test-cmd` assente → tier nudge: block + `count` incrementa; a cap
   → allow + warning.
2. `.claude/test-cmd` = `NONE` → fail-open allow, nessun block.
3. presente non approvato → block, `reason` contiene la riga
   `approve-test-cmd.sh`, **comando NON eseguito** (sentinella: il comando
   scrive un file marker che NON deve comparire).
4. `approve-test-cmd.sh` → scrive entry; idempotente (doppia invocazione = una
   riga).
5. presente approvato + comando che esce 0 → `.dirty` cancellato, allow.
6. presente approvato + comando che esce ≠0 → block bounded, `reason` con coda
   output.
7. contenuto `.claude/test-cmd` modificato dopo approvazione → hash mismatch →
   torna tier approve (no exec).
8. timeout: comando che dorme oltre `STOP_GATE_TEST_TIMEOUT` (settato basso in
   test) → fail-open allow.
9. ricerca verso l'alto: `.claude/test-cmd` in root, cwd in subdir → trovato.
10. fail-open: `session_id` assente → allow (automatizzato). Il ramo "assenza
    tool sha256 → fail-open" è verificato **per ispezione del codice**
    (`H=$(sha256_of …) || exit 0`): la simulazione PATH-strip in test è troppo
    fragile per essere affidabile (richiederebbe `jq` presente ma
    `shasum`/`sha256sum` assenti) — deviazione accettata e tracciata.

Validazione reale sul pilota `~/developer/pricing-markup-cli` (dichiara
`.claude/test-cmd=pytest -q`, approva, verifica i 4 tier) **prima** del
consolidamento; e su questo repo doc-only (`.claude/test-cmd=NONE` → silenzio
corretto).

## 11. Knob con default scelti (modificabili senza ridisegno)

- `STOP_GATE_TEST_TIMEOUT` default **120s**.
- `STOP_GATE_MAX_REENTRY` default **3** (invariato).
- Ricerca project-root: verso l'alto da `cwd` fino a `$HOME` o `/`.
- Registro: TSV `<sha256>\t<abs-root>` in `~/.claude/state/stop-gate/trust`.

## 12. Criteri di successo

- Su questo repo doc-only con `.claude/test-cmd=NONE`: zero block a fine turno
  (difetto T11 chiuso strutturalmente).
- Sul pilota con `pytest -q` approvato: codice modificato + test rossi →
  block; test verdi → allow automatico; nessun grep di output coinvolto.
- `.claude/test-cmd` non approvato → block con istruzione di approvazione,
  comando mai eseguito (verificato con sentinella).
- Harness completo verde; nessuna regressione sugli hook invariati.
- Nessuna esecuzione di comando non approvato in nessuno scenario di test.
