# Piano di implementazione — ADR-0012 (memoria agenti mediata dall'orchestratore)

**ADR di riferimento:** `docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` — **Accepted** 2026-05-24.
**Stato del piano:** ✅ **DONE — implementato e verificato 2026-05-25** (T1-T10 completati; harness FAIL=0: concept-to-code 25, review-triage-fix 62, vibe-status 12, round-trip standalone 7/7). Resta da validare in pilota la sola open question: harvest dimenticato nei dispatch diretti fuori dal chain (clausola di rivalutazione, scelta 5).
Le 5 scelte aperte dell'ADR sono confermate da Stefano:
1. label report = `DURABLE NOTES:`
2. path = `~/.claude/projects/<encoded-project-dir>/memory/agent-notes/<agente>.md`, separato da `MEMORY.md`
3. harvest fuori dal chain = disciplina manuale dell'orchestratore (niente hook di enforcement ora)
4. presidio read-only in `vibe-status` sulla freschezza di `agent-notes/` = **incluso**
5. clausola di rivalutazione verso A (git-ignore) / C (rimozione) = accettata

**Natura del deliverable.** Il repo `vibe-coding-system` è solo-blueprint (no git, no codice).
Gli artefatti che questi task modificano vivono in `~/.claude/` (definizioni agente, skill, store
memoria). **Nessun commit step** nel piano: il deploy è applicazione diretta dei file sotto `~/.claude/`
+ migrazione dati, dopo approvazione di Stefano. I 2 file dati da migrare vivono **dentro** questo repo
(`docs/agent-notes/`); la loro rimozione è l'unico passo che tocca il tree del blueprint.

---

## Quadro accertato (verificato leggendo i file, 2026-05-24)

- **3 definizioni agente live** col pattern read+append a `docs/agent-notes/`:
  - `~/.claude/agents/architect.md` — Process p.5 (riga 33) read+append; Write scope (riga 64) include `docs/agent-notes/architect.md`.
  - `~/.claude/agents/debugger.md` — Process p.2 (riga 28) read; Process p.6 (riga 32) append.
  - `~/.claude/agents/reviewer.md` — Process p.3 (riga 29) read+append.
- **`.bak`:** solo `~/.claude/agents/refactorer.md.bak-2026-05-20` contiene il pattern; `refactorer.md.bak-2026-05-20-rfs-runs` **no**; `refactorer.md` live **già pulito**.
- **Dispatch reviewer/debugger NON è nel chain direttamente.** Lo Step 6 del chain `concept-to-code` dispatcha la skill `review-triage-fix`, che internamente dispatcha `reviewer` (Step 1, riga ~64, sempre) e `debugger` (Step 3 route-fix, righe ~77/127, condizionale). **Conseguenza per il piano:** il contratto iniezione/raccolta per reviewer/debugger va innestato nei punti di dispatch di `review-triage-fix`, NON nello Step 6 del chain. Solo l'`architect` è dispatchato direttamente dal chain (Step 2).
- **`claude-md-generator`** (`~/.claude/skills/claude-md-generator/SKILL.md`, 17 righe): grep di `agent-notes`/`scaffold`/`tracked tree` = **vuoto**. Non genera né eccettua la regola. D5 si riduce a un **presidio di non-regressione** (una riga di nota), non a una rimozione.
- **vibe-status** (`~/.claude/skills/vibe-status/scripts/aggregate.sh`): la Section 7 "Memory head" risolve già il path encoded con `ENC=$(printf '%s' "$PWD" | tr '/' '-')` e legge `MEMORY.md`. È il punto naturale e coerente dove agganciare una Section 7b read-only su `agent-notes/`. Harness dedicato in `tests/run-tests.sh` con helper `ok`/`bad`, header `PASS=`/`FAIL=`.
- **Store memoria:** `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/` esiste (`MEMORY.md` + file per-topic con frontmatter). La sottocartella `agent-notes/` **non esiste ancora**.
- **Dati da migrare (dentro questo repo):** `docs/agent-notes/architect.md` (~25KB, log multi-ADR append-only) e `docs/agent-notes/debugger.md` (~7KB, log bug). NON c'è `reviewer.md` né `refactorer.md` nel tree.
- **Vincolo bash 3.2.57** (system bash di `~/.claude`): niente assoc array, `mapfile`, `${v^^}`, `<()`. Pattern harness consolidato: `set -u`, helper `ok`/`bad`, `grep -q -- "literal"`, parsing via `sed -n`.

---

## Ordine sicuro (razionale)

Il vincolo dell'ordine è **non perdere dati** e **non rompere il sistema a metà**:

1. **Prima la struttura + migrazione dati** (Task 1–2): creare il namespace e copiare i contenuti dei 2 file dentro lo store centrale, mentre gli agenti scrivono ancora nel vecchio path. Nessuna perdita: i dati esistono in entrambi i posti.
2. **Poi cambiare gli agenti** (Task 3–4): da quel momento i nuovi run emettono `DURABLE NOTES:` invece di scrivere file. Il vecchio path non viene più ricreato.
3. **Poi rimuovere i 2 file dal tree** (Task 5, **HITL gate bloccante**): solo dopo che (a) i dati sono migrati e verificati e (b) nessun agente li ricrea più. Rimuovere prima del Task 3 farebbe ricomparire i file al primo dispatch.
4. **Poi il contratto nei dispatcher** (Task 6–7): chain + review-triage-fix, così iniezione/raccolta diventano automatiche.
5. **Poi presidi e test** (Task 8–10): claude-md-generator non-regressione, vibe-status read-only, harness round-trip.

Task 3, 4, 6, 7, 8, 9, 10 sono indipendenti tra loro a valle del Task 5; possono essere batchati. Task 1→2→5 sono una catena stretta (dati).

---

## Task (10, ordinati, bounded — dispatch a batch da 2-3, regola chain ≥6 task)

> Legenda categoria modifica: **ADD** (solo aggiunta) · **REMOVE** (solo rimozione) · **REPLACE** (sostituzione: nuovo + vecchio da togliere) · **MODIFY** (modifica in-place senza add/remove netti).

### Task 1 — Creare il namespace `agent-notes/` nello store centrale

- **File toccati:** crea la dir `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/agent-notes/` (vuota) + un file `~/.claude/projects/.../memory/agent-notes/README.md` minimale che documenta: append-only, non linkato da `MEMORY.md`, un file per agente (`<agente>.md`), scritto solo dall'orchestratore (mai dai subagent).
- **Cosa cambia (ADD):** sola creazione struttura. Nessuna modifica a file esistenti.
- **Verifica:** `test -d ~/.claude/projects/.../memory/agent-notes && test -f ~/.claude/projects/.../memory/agent-notes/README.md`. Confermare che `MEMORY.md` **non** linka `agent-notes/` (grep negativo: `grep -c "agent-notes" MEMORY.md` = 0).
- **Dipendenze:** nessuna. È il prerequisito di Task 2.
- **HITL:** nessuno (solo creazione, nessuna eliminazione/sovrascrittura).

### Task 2 — Migrare il contenuto dei 2 file esistenti nello store centrale

- **File toccati:**
  - **legge** (sorgente, NON modifica, NON elimina): `docs/agent-notes/architect.md` (~25KB), `docs/agent-notes/debugger.md` (~7KB) — dentro questo repo.
  - **scrive** (destinazione): `~/.claude/projects/.../memory/agent-notes/architect.md`, `~/.claude/projects/.../memory/agent-notes/debugger.md`.
- **Cosa cambia (ADD):** copia 1:1 del contenuto. Aggiungere in testa a ciascun file di destinazione una riga di provenienza: `<!-- migrated from docs/agent-notes/<agente>.md on 2026-05-24 (ADR-0012) -->`. Mantenere il formato append-only esistente (sono già log per-data). NON creare `reviewer.md`/`refactorer.md` (non esistono sorgenti).
- **Verifica:** `diff <(sed '1d' dest/architect.md) docs/agent-notes/architect.md` deve differire solo per la riga di provenienza (oppure usare un confronto di byte-count + spot-check delle prime/ultime 20 righe). Stesso per debugger. **Criterio di successo:** ogni byte di contenuto del sorgente è presente nella destinazione.
- **Dipendenze:** Task 1 (la dir deve esistere).
- **HITL:** nessuno **sui sorgenti** (non vengono toccati). La copia in `~/.claude/` è additiva. La rimozione dei sorgenti è il Task 5 separato, con gate.

### Task 3 — Migrare `~/.claude/agents/architect.md` al contratto iniezione/raccolta

- **File toccati:** `~/.claude/agents/architect.md`.
- **Cosa cambia (REPLACE):**
  - **Riga 33 (Process p.5)** — `Remove:` "Check `docs/agent-notes/architect.md` … After designing, append new durable decisions/patterns to it (create the file/dir if absent)." `Add:` "Factor in the `PRIOR AGENT NOTES` block if present in your brief (past durable decisions/patterns for this project); do not re-litigate settled choices. Do NOT read or write any memory file yourself."
  - **Riga 64 (Edge Cases → Write scope)** — `Remove:` `docs/agent-notes/architect.md` dalla write-scope. `Add:` lasciare la write-scope = solo `docs/architecture/**`.
  - **Nuova sezione "Output Format" (ADD):** aggiungere come ultimo blocco del report la sezione terminale `DURABLE NOTES:` col formato esatto dell'ADR D1.2 (header `DURABLE NOTES:` su riga propria; un bullet per nota `- [<categoria>] <1-2 righe> (<contesto opzionale>)`; riga letterale `DURABLE NOTES: none` se nessuna nota nuova). Specificare: è l'ULTIMA sezione del report (terminale, machine-greppable, sorella di `PATTERN:` di ADR-0001).
- **Verifica:** `grep -c "agent-notes" ~/.claude/agents/architect.md` = **0**; `grep -q "DURABLE NOTES:" ~/.claude/agents/architect.md` = true; `grep -q "PRIOR AGENT NOTES" ~/.claude/agents/architect.md` = true; la write-scope resta solo `docs/architecture/**`.
- **Dipendenze:** Task 2 (migrare prima di togliere il canale di scrittura agli agenti — così non si perde nulla scritto in più nel frattempo). Indipendente da Task 4.
- **HITL:** nessuno (modifica di config agente sotto `~/.claude/`, no eliminazioni).

### Task 4 — Migrare `~/.claude/agents/debugger.md` e `~/.claude/agents/reviewer.md` allo stesso contratto

- **File toccati:** `~/.claude/agents/debugger.md`, `~/.claude/agents/reviewer.md`.
- **Cosa cambia (REPLACE), debugger.md:**
  - **Riga 28 (Process p.2)** — `Remove:` "Check `docs/agent-notes/debugger.md` … for similar past issues; factor in." `Add:` "Factor in the `PRIOR AGENT NOTES` block if present in your brief (past bug patterns on this project)."
  - **Riga 32 (Process p.6)** — `Remove:` "Append the bug pattern + resolution to `docs/agent-notes/debugger.md` (create file/dir if absent)." `Add:` emettere la sezione terminale `DURABLE NOTES:` nell'Output Format (stesso formato di Task 3); non scrivere alcun file di memoria.
- **Cosa cambia (REPLACE), reviewer.md:**
  - **Riga 29 (Process p.3)** — `Remove:` "Check `docs/agent-notes/reviewer.md` … Append newly observed recurring patterns after the review (create file/dir if absent)." `Add:` "Factor in the `PRIOR AGENT NOTES` block if present in your brief; emit recurring patterns observed in this review in a terminal `DURABLE NOTES:` section of your report (format above). Write no memory file."
  - Aggiungere il blocco formato `DURABLE NOTES:` in Output Format anche qui (ADD).
- **Verifica:** per entrambi: `grep -c "agent-notes"` = **0**; `grep -q "DURABLE NOTES:"` = true; `grep -q "PRIOR AGENT NOTES"` = true. Coerenza del formato `DURABLE NOTES:` identico tra architect/debugger/reviewer (stesso header, stessa convenzione `none`).
- **Dipendenze:** Task 2. Indipendente da Task 3 (batchabile con Task 3).
- **HITL:** nessuno.

### Task 5 — Rimuovere i 2 file `docs/agent-notes/` dal tree del repo (HITL GATE BLOCCANTE)

- **File toccati:** `docs/agent-notes/architect.md`, `docs/agent-notes/debugger.md` (eliminazione); valutare la rimozione della dir `docs/agent-notes/` se resta vuota.
- **Cosa cambia (REMOVE):** eliminazione dei 2 file dal tree (e della dir se vuota).
- **PRECONDIZIONI bloccanti (tutte verde prima del gate):**
  1. Task 2 completato e **verificato** (contenuto presente nello store centrale — byte-count + spot-check).
  2. Task 3 e Task 4 completati (nessun agente ricrea più il path → la rimozione è definitiva, non ricorrente).
  3. Mostrare a Stefano un **dry-run**: i path esatti da eliminare, il loro size, e la conferma che esistono copie in `~/.claude/.../memory/agent-notes/`. Non eliminare nulla prima dell'`ok` esplicito.
- **Verifica post-rimozione:** `test ! -e docs/agent-notes/architect.md && test ! -e docs/agent-notes/debugger.md`. Le copie nello store restano intatte (`test -f ~/.claude/.../memory/agent-notes/architect.md`).
- **Dipendenze:** Task 2, 3, 4 (catena stretta — NON anticipabile).
- **HITL:** **GATE BLOCCANTE** — eliminazione permanente di file. Regola globale Stefano: "mai eliminare file senza conferma esplicita" + "mostrare diff/dry-run". L'orchestratore esegue la rimozione solo dopo `ok`.
- **Rollback:** se qualcosa va storto, i contenuti sono ancora in `~/.claude/.../memory/agent-notes/` (copia da Task 2) → ricopiabili nel tree. Consigliato un backup tar dei 2 file prima dell'eliminazione (`docs/agent-notes/.bak-2026-05-24.tar`) tenuto fuori dal commit, finché il pilota non conferma.

### Task 6 — Innestare il contratto iniezione/raccolta nel chain `concept-to-code` (dispatch architect)

- **File toccati:** `~/.claude/skills/concept-to-code/SKILL.md`.
- **Cosa cambia (ADD):**
  - **Step 2 — dispatch architect (template righe ~186-208).** Aggiungere, in testa al brief, il blocco iniezione:
    ```
    PRIOR AGENT NOTES (read-only context — past durable decisions/patterns for the
    architect on this project; factor in, do not repeat settled work):
    <orchestrator inserisce qui il contenuto di memory/agent-notes/architect.md, o "none yet">
    ```
    Aggiungere alla riga "Return a report with: …" la richiesta esplicita della sezione terminale `DURABLE NOTES:`.
  - **Dopo il ritorno dell'architect (righe ~210-211, "After architect returns…").** Aggiungere il passo di **raccolta**: l'orchestratore estrae il blocco `DURABLE NOTES:` dal report e, se ≠ `none`, lo appende a `memory/agent-notes/architect.md` (mai a `MEMORY.md`). Specificare che la risoluzione del path encoded è responsabilità dell'orchestratore (mai del subagent — D2).
  - **§6 Coexistence invariants (riga ~544).** Aggiornare la nota su `architect.md`: oggi dice "not patched; this skill passes a literal prompt template at dispatch time" → resta vero, ma aggiungere che il template ora **inietta `PRIOR AGENT NOTES` e raccoglie `DURABLE NOTES:`** (contratto ADR-0012).
- **Verifica:** `grep -q "PRIOR AGENT NOTES" SKILL.md` e `grep -q "DURABLE NOTES:" SKILL.md` = true; il passo di harvest è descritto nel testo dopo lo Step 2. **Contratto osservabile cambiato** (forma del brief + forma del report richiesto) → vedi Task 10 per il presidio round-trip; nessun call-site esterno asserisce il vecchio brief (grep `PRIOR AGENT NOTES`/`DURABLE NOTES` nel resto di `~/.claude/skills` e `~/.claude/agents` = solo i file che questo piano tocca).
- **Dipendenze:** Task 3 (l'architect deve già emettere `DURABLE NOTES:`). Logicamente indipendente da Task 7.
- **HITL:** nessuno.

### Task 7 — Innestare il contratto iniezione/raccolta in `review-triage-fix` (dispatch reviewer + debugger)

- **File toccati:** `~/.claude/skills/review-triage-fix/SKILL.md`.
- **Razionale:** reviewer e debugger NON sono dispatchati dal chain direttamente, ma da questa skill (Step 6 del chain → review-triage-fix). Quindi il contratto per loro vive qui.
- **Cosa cambia (ADD):**
  - **Step 1 — Review (riga ~64), dispatch reviewer.** Aggiungere al brief il blocco `PRIOR AGENT NOTES` per `reviewer` (contenuto di `memory/agent-notes/reviewer.md` o `none yet`) e richiedere il `DURABLE NOTES:` terminale nel report. Dopo il report del reviewer, harvest verso `memory/agent-notes/reviewer.md`.
  - **Step 3 — Route-fix (righe ~126-129), dispatch debugger.** Quando il route porta a `debugger`, aggiungere il blocco `PRIOR AGENT NOTES` per `debugger` e l'harvest del `DURABLE NOTES:` post-report verso `memory/agent-notes/debugger.md`. (Il `coder` e il `refactorer` non sono soggetti del contratto — l'ADR riguarda solo i 3 agenti con memoria; non aggiungere il blocco ai loro dispatch.)
  - Aggiungere una nota in testa alla skill: la risoluzione del path encoded e l'harvest sono responsabilità dell'orchestratore che esegue la skill (D2).
- **Verifica:** `grep -c "PRIOR AGENT NOTES" SKILL.md` ≥ 2 (reviewer + debugger); `grep -q "DURABLE NOTES:" SKILL.md` = true; il `coder`/`refactorer` dispatch NON contengono il blocco (grep di contesto). **Contratto osservabile cambiato** (brief reviewer/debugger) → harness round-trip (Task 10) copre la forma; nessun altro file asserisce il vecchio brief.
- **Dipendenze:** Task 4 (reviewer e debugger devono già emettere `DURABLE NOTES:`). Indipendente da Task 6.
- **HITL:** nessuno.

### Task 8 — Presidio di non-regressione su `claude-md-generator` (D5)

- **File toccati:** `~/.claude/skills/claude-md-generator/SKILL.md`.
- **Cosa cambia (ADD, minimale):** il grep attuale conferma che la skill **non** menziona `agent-notes` né una regola anti-scaffolding → non c'è nulla da rimuovere. L'azione D5 è **garantire la non re-introduzione**: aggiungere una riga di guard nel SKILL.md, p.es. nella sezione di generazione: "Non generare regole di doc-discipline che vietino `docs/agent-notes/` nel tracked tree: dopo ADR-0012 quel path non è più creato da alcun agente (la memoria agenti vive in `~/.claude/projects/<encoded>/memory/agent-notes/`, gestita dall'orchestratore)."
- **Verifica:** `grep -q "agent-notes" SKILL.md` = true (la sola nota di guard); la direttiva additiva di Step 3 del chain (`claude-md-generator` invocato as-is) resta invariata — confermare che la modifica è una riga additiva, non tocca il flusso generativo.
- **Dipendenze:** nessuna funzionale (può andare in batch con Task 6/7). Logicamente segue la decisione, non i dati.
- **HITL:** nessuno.
- **Nota / alternativa:** se Stefano preferisce **zero** menzione di `agent-notes` in una skill (per non re-introdurre per sbaglio l'associazione), l'alternativa è non aggiungere la riga e affidarsi al grep di non-regressione nel harness (Task 10) come unico presidio. Raccomando la riga di guard: è esplicita e a costo nullo. **Decisione di Stefano** (vedi Rischi).

### Task 9 — Segnale read-only su freschezza `agent-notes/` in `vibe-status`

- **File toccati:** `~/.claude/skills/vibe-status/scripts/aggregate.sh`; `~/.claude/skills/vibe-status/tests/run-tests.sh` (un nuovo test); opzionale 1 riga in `~/.claude/skills/vibe-status/SKILL.md` (sezione Discovery).
- **Cosa cambia (ADD):**
  - In `aggregate.sh`, dopo la Section 7 (Memory head, righe ~170-177), aggiungere una **Section 7b — Agent notes**: riusare lo stesso `ENC=$(printf '%s' "$PWD" | tr '/' '-')` già calcolato; puntare a `$HOME/.claude/projects/$ENC/memory/agent-notes/`; se la dir esiste, contare i file `*.md` e riportare l'mtime più recente (freschezza). Output read-only, fail-graceful (dir assente → "(no agent-notes)"). NON bloccante: non altera il calcolo `HEALTH`.
  - Aggiungere il rendering della Section 7b nel blocco Markdown (vicino a `## Memory`) e un campo opzionale nel ramo `--json`.
  - In `run-tests.sh`, aggiungere **un** test: dato un fake store con `agent-notes/<agente>.md`, l'output contiene la sezione agent-notes con conteggio ≥ 1; con dir assente, degrada a "(no agent-notes)" e `exit 0`.
- **Vincolo bash 3.2.57:** seguire lo stile esistente (`set -u`, niente assoc array/mapfile/`${v^^}`/`<()`, `stat -f`/`stat -c` con fallback come riga ~134, `grep -q --`).
- **Verifica:** `bash run-tests.sh` → `PASS=` incrementato di 1, `FAIL=0`. Smoke: `bash aggregate.sh --skip-harness` mostra la sezione agent-notes ed esce 0 anche con dir assente.
- **Dipendenze:** Task 1 (la dir target deve esistere per il caso "presente"; il caso "assente" è testabile comunque con fake store). Indipendente dagli altri.
- **HITL:** nessuno (read-only).
- **Accoppiamento noto da dichiarare:** la Section 7b riusa `tr '/' '-'` per l'encoding, come la Section 7 esistente. È il pattern fragile avvertito da `feedback_pretooluse-payload-schema.md` (`_`→`-`, `cwd` vs `dirname(transcript_path)`). Qui è **accettabile** perché: (a) è confinato a uno script dell'orchestratore (mai a un subagent — D2), (b) è coerente con la Section 7 già in produzione (non introduce una seconda convenzione), (c) è solo un segnale read-only (un encoding errato produce un falso "(no agent-notes)", non corruzione). Non replicare questa risoluzione lato subagent.

### Task 10 — Harness round-trip del contratto (D6)

- **File toccati:** nuovo `~/.claude/skills/concept-to-code/tests/agent-notes-roundtrip.sh` (o aggiunte a `tests/run-tests.sh` se preferito un singolo entrypoint; vedi nota). Eseguibile (`chmod +x`).
- **Cosa cambia (ADD):** harness deterministico bash 3.2-clean (stile `vibe-status/tests/run-tests.sh`: `set -u`, `ok`/`bad`, `PASS=`/`FAIL=`, `mktemp -d`, mai toccare lo store reale) che verifica i 3 tempi del contratto su fixture:
  1. **Iniezione** — dato un fixture store con `agent-notes/architect.md` di contenuto noto, la routine di iniezione (estratta in uno script helper o simulata via grep del template) produce un blocco `PRIOR AGENT NOTES` contenente quel testo; dato store assente, produce `none yet`.
  2. **Raccolta/parse** — dato un report fixture con una sezione `DURABLE NOTES:` ben formata (≥1 bullet), il parser estrae i bullet corretti; dato `DURABLE NOTES: none`, estrae zero note; dato un report **troncato** a metà della sezione, il parser NON scrive note parziali (tollera la troncatura — lezione `feedback_subagent-truncation-transport.md`).
  3. **Persistenza** — l'append finisce in `agent-notes/<agente>.md` del fixture store, **mai** in `MEMORY.md` (asserire che `MEMORY.md` fixture resta byte-identico).
- **Nota implementativa.** Iniezione e harvest, nel design B-mediata, sono **azioni dell'orchestratore descritte in prosa nei template** (non c'è un binario unico). Per renderle testabili headless, il Task 10 deve estrarre la logica deterministica (parse del blocco `DURABLE NOTES:`, distinzione `none`/troncato, target del path) in un **piccolo helper bash** (es. `~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh`) che l'harness invoca e che il template di Task 6/7 referenzia. Questo è additivo e coerente col pattern "skill standalone riusata dal gate". **Decisione di Stefano** se vuole l'helper estratto o un harness che asserisce solo gli structural anchor nei SKILL.md (più debole ma zero nuovo codice eseguibile) — vedi Rischi.
- **Vincolo bash 3.2.57:** come sopra.
- **Verifica:** `bash agent-notes-roundtrip.sh` → `FAIL=0`. Allineare il target PASS allo stile (annunciare `PASS=N` nel report). Se l'harness vive in `concept-to-code/tests/`, `vibe-status` lo scopre automaticamente (Discovery globale `~/.claude/skills/*/tests/run-tests.sh`) **solo** se chiamato `run-tests.sh`; se è un file separato, aggiungerlo all'entrypoint o accettare che giri standalone.
- **Dipendenze:** Task 6 e Task 7 (il contratto deve essere innestato per essere testato end-of-template). L'helper (se estratto) va creato qui e referenziato retroattivamente da 6/7 — in tal caso eseguire Task 10-helper prima di 6/7, o coordinare nello stesso batch.
- **HITL:** nessuno.

---

## Verifica finale (tutto verde prima di dichiarare fatto)

1. **Nessun agente referenzia più `agent-notes/`:** `grep -rl "agent-notes" ~/.claude/agents/` ritorna **solo** `refactorer.md.bak-2026-05-20` (`.bak` storico intoccato). architect/debugger/reviewer puliti.
2. **Contratto presente nei 3 agenti:** ciascuno di architect/debugger/reviewer contiene `PRIOR AGENT NOTES` (factor-in) e `DURABLE NOTES:` (formato terminale).
3. **Write-scope architect:** solo `docs/architecture/**` (niente `docs/agent-notes/`).
4. **Dati migrati:** `~/.claude/.../memory/agent-notes/{architect,debugger}.md` contengono l'intero contenuto dei sorgenti (byte-count + spot-check), `MEMORY.md` non li linka.
5. **Tree pulito:** `docs/agent-notes/` rimosso dal repo (dopo gate); copie nello store intatte.
6. **Chain + review-triage-fix** iniettano/raccolgono (grep `PRIOR AGENT NOTES`/`DURABLE NOTES:` nei due SKILL.md).
7. **claude-md-generator** non re-introduce la regola (presidio Task 8).
8. **vibe-status** mostra la Section 7b agent-notes ed esce 0 in tutti i casi; `bash ~/.claude/skills/vibe-status/tests/run-tests.sh` → `FAIL=0`.
9. **Harness round-trip** verde: `FAIL=0`.
10. **Regressione sistema:** eseguire `/skill vibe-status` (o `aggregate.sh`) → health non peggiorata; in particolare gli harness esistenti `review-triage-fix` e `concept-to-code` restano verdi (i Task 6/7 hanno modificato i loro SKILL.md → far girare i rispettivi `tests/run-tests.sh` interi, non solo il nuovo test — un cambio di contratto può rompere anchor esistenti in quegli harness).

---

## Rischi, dipendenze e decisioni che richiedono Stefano prima di partire

- **[GATE] Eliminazione dei 2 file (Task 5).** Eliminazione permanente nel tree del repo. Richiede `ok` esplicito di Stefano dopo dry-run; precondizione = dati migrati e verificati (Task 2) + agenti già migrati (Task 3/4). Backup tar consigliato finché il pilota non conferma. **Non procedere senza conferma.**
- **[DECISIONE] Forma del presidio claude-md-generator (Task 8).** Aggiungere una riga di guard che menziona `agent-notes` (esplicita, raccomandata) **oppure** lasciare la skill intatta e affidarsi al solo grep di non-regressione nell'harness. Trade-off: la riga è esplicita ma re-introduce il termine in una skill; l'assenza è più pulita ma il presidio diventa implicito. Raccomando la riga di guard.
- **[DECISIONE] Estrazione dell'helper harvest (Task 10).** Per rendere il round-trip testabile headless serve estrarre la logica di parse `DURABLE NOTES:` in un piccolo script bash riusato da chain + review-triage-fix. Alternativa più leggera: harness che asserisce solo gli structural anchor nei SKILL.md (nessun nuovo eseguibile, ma non testa davvero il parse/troncatura). Raccomando l'helper estratto: D6 chiede esplicitamente di testare il parse e la tolleranza alla troncatura, non solo la presenza degli anchor.
- **[RISCHIO operativo non testabile headless] Harvest dimenticato fuori dal chain.** Il dispatch diretto a un subagent (fuori chain/fuori review-triage-fix) resta disciplina manuale dell'orchestratore (scelta 3 confermata, nessun hook di enforcement). L'harness verifica il parse, NON che l'orchestratore *si ricordi* di raccogliere in una sessione live. Resta open question da validare in pilota → clausola di rivalutazione verso A (git-ignore) o C (rimozione) accettata (scelta 5).
- **[RISCHIO encoding] Path encoded `tr '/' '-'`.** Confinato all'orchestratore e a `vibe-status/aggregate.sh` (mai ai subagent — D2). Coerente con la Section 7 esistente. Un encoding errato degrada a falso "(no agent-notes)" / harvest mancato, non a corruzione. Non replicare lato subagent.
- **[DIPENDENZA d'ordine] Catena stretta Task 1→2→5.** I dati non vanno persi: creare struttura → migrare → (solo dopo aver migrato gli agenti) rimuovere. Task 3/4 devono precedere Task 5, altrimenti i file ricompaiono al primo dispatch (il conflitto è by-design, non one-shot).
- **[NOTA] `.bak` intoccati.** `refactorer.md.bak-2026-05-20` mantiene il pattern ma è inattivo: NON toccarlo (rumore inutile, conferma ADR). Il secondo `.bak` (`-rfs-runs`) non ha il pattern.
- **[NOTA] Nessun commit.** Repo blueprint non-git; gli artefatti vivono in `~/.claude/`. Il deploy è applicazione diretta dei file + migrazione, senza commit step. L'unico tocco al tree del repo è il Task 5 (rimozione, sotto gate).

---

## Sintesi dispatch a batch (regola chain: plan ≥6 task → batch da 2-3)

- **Batch 1 (dati, catena stretta):** Task 1 → Task 2. Verifica migrazione.
- **Batch 2 (agenti):** Task 3 + Task 4 (indipendenti tra loro).
- **Batch 3 (rimozione, GATE):** Task 5 — solo dopo HITL `ok`.
- **Batch 4 (contratto dispatcher + helper):** Task 10-helper (se estratto) → Task 6 + Task 7.
- **Batch 5 (presidi + test):** Task 8 + Task 9 + Task 10-harness.
- **Chiusura:** Verifica finale (10 punti) + regressione harness interi.
