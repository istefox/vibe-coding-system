# ADR-0013 — Migrare la memoria cross-session degli agenti alla feature NATIVA `memory:` (supersede di ADR-0012, scope `local`)

**Status:** Rejected after pilot — 2026-05-25. La migrazione era stata accettata (scope `local`, Write/Edit su reviewer OK) e la Fase 1 abilitata in coesistenza, ma il **pilota è fallito**: dispatch architect con `memory: local` → la dir nativa `.claude/agent-memory-local/architect/` è rimasta INVARIATA mentre l'agente ha editato autonomamente l'auto-memory curata (`reference_cc-capabilities-research-2026-05.md`), FUORI dalla sua write-scope. Il broad-Write auto-abilitato da `memory:` ha materializzato il downside degli assi 4-5 di questo ADR. Il pilot-gate (precondizione bloccante) NON è passato → **ADR-0012 resta il meccanismo attivo** (mediazione orchestratore, sub-agent senza Write su memoria). `memory: local` rimosso dai 3 agenti, dir seedate ripulite (dati intatti nello store centrale). Caveat: 1 run, possibili confounder (prompt + Sonnet + file tematico scopribile), ma il rischio è strutturale.

**Deciders:** architect (dispatch orchestrator), Stefano Ferri (approvazione finale)

**Related:** ADR-0012 (`docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` +
`-implementation-plan.md` — la soluzione B-mediata oggi deployata, che questo ADR propone di
supersedeare); ADR-0004 (`docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` —
fonte della fragilità dell'encoding project-dir che il nativo elimina internamente); ADR-0001
(`docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` — il contratto
`DURABLE NOTES:` mediato ne riusava il pattern report-strutturato, che il nativo rende
superfluo); ADR-0003 (`docs/architecture/ADR-0003-concept-to-code-chain.md` — il chain in cui
il contratto mediato è innestato, da semplificare); ADR-0005
(`docs/architecture/ADR-0005-vibe-status-skill.md` — la Section 7b read-only va ri-puntata);
ADR-0011 (`docs/architecture/ADR-0011-clean-public-repo-anonymize.md` — vincolo "fuori dal
tracked tree", che il nativo soddisfa solo con lo scope giusto).

---

## Context

### Cosa è cambiato dopo ADR-0012

ADR-0012 è stato **Accepted e deployato il 2026-05-25** (opzione B-mediata): la memoria
cross-session di `architect`/`debugger`/`reviewer` è stata spostata da `docs/agent-notes/<agente>.md`
(dentro il tree di progetto) allo store centrale `~/.claude/projects/<encoded>/memory/agent-notes/<agente>.md`,
con accesso **mediato dall'orchestratore**: inject del blocco `PRIOR AGENT NOTES` nel brief,
harvest del blocco terminale `DURABLE NOTES:` dal report via helper
`~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh`. I sub-agent **non** toccano
mai memoria né risolvono il path encoded. Lo stato live è **verde** (verificato 2026-05-25):
helper presente, store popolato (`architect.md` ~25KB, `debugger.md` ~7KB, README), nessun
agente usa il campo nativo; harness round-trip 7/7, concept-to-code 25, review-triage-fix 62,
vibe-status 12.

La ricerca del 2026-05-25 sui doc ufficiali (memory `reference_cc-capabilities-research-2026-05.md`)
ha poi scoperto che **Claude Code ha una feature NATIVA** che copre lo stesso bisogno. ADR-0012
stesso prevedeva una **clausola di rivalutazione** (scelta 5) verso alternative più semplici se
le assunzioni non reggevano: questo ADR la esercita non per fallimento operativo, ma perché è
emersa una via più semplice e più robusta che B-mediata aveva dovuto costruire a mano in assenza
di supporto nativo.

### Fatti VERIFICATI sulla feature nativa (fonte: `code.claude.com/docs/en/sub-agents`, sezione "Enable persistent memory", letta 2026-05-25)

Citazioni verificate alla riga indicata del doc ufficiale:

- **Campo frontmatter** `memory: user | project | local` (riga 277 "Persistent memory scope …
  Enables cross-session learning"; riga 433 "The `memory` field gives the subagent a persistent
  directory that survives across conversations").
- **Storage per scope** (righe 452-454, tabella verbatim):
  - `user` → `~/.claude/agent-memory/<name-of-agent>/` — "remember learnings across all projects";
  - `project` → `.claude/agent-memory/<name-of-agent>/` — "project-specific and **shareable via
    version control**";
  - `local` → `.claude/agent-memory-local/<name-of-agent>/` — "project-specific but **should not
    be checked into version control**".
- **Quando attivo** (righe 456-460, verbatim):
  - il system prompt del sub-agent include istruzioni read/write per la dir di memoria;
  - include i **primi 200 righe o 25KB** di `MEMORY.md` di quella dir (il minore dei due), con
    istruzioni a curarlo se eccede il limite;
  - **Read, Write, Edit sono auto-abilitati** "so the subagent can manage its memory files".
- **Chi gestisce la memoria:** il **sub-agent stesso** ("update your agent memory…", riga 444;
  "manage its memory files", riga 460; tip 465-470 "consult its memory before starting / save
  what you learned"). Il path encoded è **risolto internamente** da Claude Code: lo scope nominale
  (`user`/`project`/`local`) mappa al path senza che noi facciamo `tr '/' '-'`.
- `memory` è confermato nei **supported frontmatter fields** e nel JSON `--agents` (riga 225) →
  è una feature di prima classe, documentata, non gated.

### Il legame con la lezione di ADR-0004 / ADR-0009 (PRIOR NOTE di questo task)

La PRIOR NOTE è centrale: ADR-0004 (v1.0/v1.1) è costato due fix proprio perché derivava la
project-dir encoded a mano (`_`→`-`, `cwd` ri-encodato ≠ path reale). B-mediata di ADR-0012 ha
**aggirato** quella trappola confinando l'encoding al solo orchestratore — ma l'encoding fragile
**resta** nel sistema: l'helper `agent-notes-harvest.sh` (righe 43-44) e `vibe-status/aggregate.sh`
(Section 7/7b) usano ancora `printf '%s' "$PWD" | tr '/' '-'`. Lo stesso commento nell'helper lo
ammette ("the same fragile pattern noted in feedback_pretooluse-payload-schema; acceptable HERE…").
Il nativo **elimina** quella derivazione, non la confina: è esattamente l'applicazione della regola
"preferisci input diretto/risoluzione nativa all'encoding derivato quando sufficiente".

### La regola guida

"Building Effective Agents" (Anthropic) e i best-practice ufficiali (confermati al ~85% allineati,
stessa ricerca): **non aggiungere complessità finché il semplice non basta**. ADR-0012 si
giustificava esplicitamente solo perché *non* esisteva supporto nativo e il sistema aveva già
l'infrastruttura per estendere il pattern. Quel presupposto è caduto: ora il semplice (un campo
frontmatter) basta.

### Assunzioni esplicite (NON validate)

- Si assume che il comportamento documentato del nativo sia stabile nella versione di Claude Code
  in uso da Stefano. Non è stato eseguito un test live del campo `memory:` su questo ambiente
  (nessun agente lo usa oggi — grep `^memory:` su `~/.claude/agents/*.md` = vuoto). **Va validato
  in pilota** prima di rimuovere l'infrastruttura mediata (vedi piano di smontaggio, fase ordinata).
- Si assume che la memoria degli agenti **abbia ancora valore** (stessa assunzione di ADR-0012):
  se in pilota emergesse che non producono note utili, l'opzione semplice diventa "non abilitare
  `memory:` affatto" (= Alternativa C di ADR-0012, qui ribadita come fallback).
- Si assume che lo scope `local` produca la dir `.claude/agent-memory-local/<agente>/` **dentro il
  cwd del progetto target** (working tree del progetto su cui l'agente lavora), non dentro `~/.claude`.
  È la lettura diretta del doc ("project-specific"); va confermata in pilota perché determina la
  scelta di scope (vedi asse 3).

---

## Decision

Adottare la **migrazione alla feature nativa `memory:`** per i 3 agenti con memoria, con scope
**`local`** (`.claude/agent-memory-local/<agente>/`, NON checked-in), e **supersedeare ADR-0012**
(smontaggio dell'infrastruttura mediata: helper, inject/harvest nei due SKILL.md, contratto
`DURABLE NOTES:`/`PRIOR AGENT NOTES` nelle 3 definizioni agente). La migrazione avviene **dopo**
una validazione pilota del nativo, con un periodo in cui i dati esistenti restano disponibili.

### Sintesi (<10 righe)

Il nativo fa ciò che B-mediata costruiva a mano, con **zero nostro codice** e **risolvendo il
path encoded internamente** (elimina la trappola di ADR-0004, non la confina). Lo scope `local`
non sporca il tracked tree (vincolo originario di ADR-0012, e di ADR-0011) perché non è
checked-in. Il prezzo — auto-abilitazione di Write/Edit anche su `reviewer` (read-only) e perdita
del controllo HITL dell'orchestratore su cosa entra in memoria — è **accettabile**: la scrittura è
confinata alla dir di memoria dell'agente, non al codice di progetto, e le note degli agenti sono
scaffolding di sessione, non un artefatto che richiede gate umano. Si applica la regola "preferisci
il nativo, non aggiungere complessità finché il semplice non basta".

### D1 — Scope: `local`

Usare **`memory: local`** (`.claude/agent-memory-local/<agente>/`). Razionale per asse 3 (tree
pollution, problema originario di ADR-0012):

- `project` → `.claude/agent-memory/<agente>/` **checked-in**: re-introdurrebbe esattamente il
  conflitto che ADR-0012 ha risolto (file di scaffolding nel tracked tree, in tensione con
  ADR-0011). **Escluso.**
- `user` → `~/.claude/agent-memory/<agente>/`: fuori da ogni tree, mai committato. Ma è
  **cross-progetto**: le note di un debugger su un progetto si mescolerebbero con quelle di un
  altro. Per agenti che imparano pattern *specifici di un progetto* (un bug ricorrente in QUEL
  codebase) è semanticamente sbagliato. Resta valido per pattern davvero universali (vedi punti
  aperti).
- `local` → `.claude/agent-memory-local/<agente>/`: **non checked-in** (no tree pollution) **e**
  per-progetto (semantica corretta della memoria agente). È il default raccomandato per questo
  caso. Richiede una riga `.claude/agent-memory-local/` nel `.gitignore` del progetto target solo
  se il progetto traccia `.claude/` — da verificare in pilota; il doc dice esplicitamente
  "should not be checked into version control", quindi Claude Code lo intende come non-tracciato
  per design.

### D2 — Abilitare `memory: local` sulle 3 definizioni agente

In `~/.claude/agents/{architect,debugger,reviewer}.md` aggiungere al frontmatter `memory: local`
e, nel corpo, una breve istruzione proattiva di consultare/aggiornare la propria memoria (pattern
doc righe 465-470), specifica per il ruolo:

- `architect`: "consulta la tua memoria per decisioni/pattern architetturali passati su questo
  progetto prima di progettare; aggiornala con decisioni durevoli a fine task".
- `debugger`: "consulta la tua memoria per bug-pattern già visti; salva il pattern + risoluzione a
  fine fix".
- `reviewer`: "consulta la tua memoria per pattern ricorrenti; annota nuovi pattern osservati".

Read/Write/Edit vengono auto-abilitati dal nativo per la sola gestione di quella dir (vedi asse 4).

### D3 — Smontare l'infrastruttura mediata di ADR-0012 (REMOVE)

Dopo validazione pilota (D6), rimuovere ciò che B-mediata aveva montato:

1. Dalle 3 definizioni agente: il blocco `PRIOR AGENT NOTES` (factor-in) e la sezione terminale
   `DURABLE NOTES:` (Output Format) introdotti da ADR-0012 Task 3/4 → sostituiti dall'istruzione
   nativa D2. (Il vecchio `docs/agent-notes/` era già stato rimosso da ADR-0012 Task 5; **non**
   re-introdurlo.)
2. Dal chain `concept-to-code/SKILL.md` (Step 2): inject `PRIOR AGENT NOTES` + harvest
   `DURABLE NOTES:` per l'architect (Task 6 di ADR-0012). Il dispatch torna a passare il solo
   brief; la nota §6 va aggiornata.
3. Da `review-triage-fix/SKILL.md`: inject/harvest per reviewer e debugger (Task 7 di ADR-0012).
4. L'helper `~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh` → **eliminazione**
   (HITL gate: rimozione permanente; backup prima).
5. L'harness round-trip `agent-notes-roundtrip.sh` → eliminazione (testa un contratto che non
   esiste più; HITL gate).
6. `vibe-status` Section 7b: ri-puntarla da `~/.claude/projects/<encoded>/memory/agent-notes/` a
   `.claude/agent-memory-local/<agente>/` del progetto corrente (o rimuoverla, vedi punto aperto)
   — read-only, non bloccante; oppure rimuovere del tutto il `tr '/' '-'` di quel segnale.
7. `claude-md-generator` (Task 8 di ADR-0012, riga di guard): se aggiunta, l'aggiornamento diventa
   "non generare regole che vietino `.claude/agent-memory-local/` nel tree" — ma con scope `local`
   non-checked-in il rischio è minore; valutare se la guard serve ancora.

### D4 — Migrazione dei dati esistenti

I dati storici vivono in `~/.claude/projects/<encoded>/memory/agent-notes/{architect.md,debugger.md}`
(migrati da ADR-0012 Task 2). Opzioni, in ordine di preferenza:

- **Seed dei `MEMORY.md` nativi:** copiare il contenuto di `architect.md`/`debugger.md` come
  `MEMORY.md` iniziale nelle rispettive dir native `.claude/agent-memory-local/<agente>/MEMORY.md`
  del progetto pilota. Attenzione: il nativo carica solo i primi 200 righe/25KB — `architect.md`
  è ~25KB → va **potato/curato** al seed (il nativo stesso istruisce a curare `MEMORY.md` se
  eccede). Questa è additiva: copia, non sposta.
- I file sorgente nello store centrale **restano** finché il pilota non conferma (rollback
  garantito). La loro eventuale rimozione è un task separato con HITL gate, post-pilota.

Nota: la memoria di `architect`/`debugger` è per-progetto-blueprint; con scope `local` la dir nativa
è dentro il progetto su cui l'agente lavora di volta in volta. Il seed ha senso solo per i progetti
dove quella memoria storica è rilevante (qui: il repo `vibe-coding-system` stesso, se è quello su
cui gli agenti operano). Per progetti nuovi, la memoria nativa parte vuota — comportamento corretto.

### D5 — Ordine sicuro dello smontaggio (non perdere dati, non rompere a metà)

1. **Pilota del nativo** (D6) su un progetto, con `memory: local` abilitato sui 3 agenti **e**
   l'infrastruttura mediata ancora in piedi (i due meccanismi coesistono temporaneamente:
   ridondanza tollerata, nessuna perdita).
2. **Verifica:** il sub-agent legge e scrive la sua dir nativa; i dati seedati sono consultati;
   nessun file finisce nel tracked tree (scope `local`).
3. Solo a pilota verde: **smontare** l'infrastruttura mediata (D3) — prima i dispatcher (chain +
   review-triage-fix), poi le definizioni agente (rimuovere il contratto `DURABLE NOTES:`), poi
   helper/harness (HITL gate sulle eliminazioni).
4. **Ultimo:** decidere il destino dei dati nello store centrale `memory/agent-notes/` (mantenere
   come archivio storico o rimuovere — HITL gate). Non rimuovere prima del seed verificato (D4).

### D6 — Pilota e presidio

Il rischio non testabile headless di ADR-0012 era "l'orchestratore dimentica l'harvest". Il nativo
**elimina** quel rischio (nessun harvest manuale: l'agente scrive da sé). Il nuovo rischio da
validare in pilota è opposto e più benigno: **l'agente non aggiorna** la sua memoria (omette la
scrittura) — degrada a "memoria vuota", non a corruzione né a leak nel tree. Mitigazione:
istruzione proattiva nel corpo dell'agente (D2). Pilota: un ciclo reale (un dispatch architect + un
ciclo review-triage-fix) su un progetto, verificando che `.claude/agent-memory-local/<agente>/MEMORY.md`
venga creato/aggiornato e NON appaia in `git status` del progetto.

### Punti che richiedono decisione di Stefano (pending — Status: Proposed)

1. **Scope `local` vs `user`.** Raccomando `local` (per-progetto, no tree pollution). `user` solo
   se Stefano vuole memoria cross-progetto condivisa (semantica diversa). **Decisione.**
2. **Auto-abilitazione Write/Edit su `reviewer`** (oggi read-only by design): accettabile dato che
   è confinata alla dir di memoria? Raccomando sì (asse 4). **Conferma o veto.**
3. **Destino dei dati storici** in `memory/agent-notes/` dopo il seed: archiviare o rimuovere
   (HITL gate). **Decisione post-pilota.**
4. **Eliminazione di helper + harness** (`agent-notes-harvest.sh`, `agent-notes-roundtrip.sh`):
   eliminazione permanente, **HITL gate**, backup prima. **Conferma.**
5. **Seed della memoria nativa** dell'architect dai ~25KB storici (va potato a ≤25KB/200 righe):
   farlo o partire puliti? **Decisione.**

---

## Consequences

### Positive

- **Zero codice nostro da mantenere.** Spariscono l'helper `agent-notes-harvest.sh`, l'harness
  round-trip, e il contratto inject/harvest nei due SKILL.md + nelle 3 definizioni agente. Meno
  superficie, meno test, meno punti di rottura.
- **Fragilità dell'encoding ELIMINATA (non confinata).** Il nativo risolve `local`/`user`/`project`
  → path internamente: niente `tr '/' '-'` nostro né in fase di inject/harvest né (ri-puntando o
  rimuovendo la Section 7b) in `vibe-status`. È l'applicazione diretta della PRIOR NOTE
  (ADR-0004/0009).
- **Rischio-harvest azzerato.** Il rischio operativo TOP di ADR-0012 (orchestratore dimentica di
  raccogliere → memoria persa in silenzio) sparisce: l'agente scrive da sé, non c'è passo
  orchestratore da ricordare. Vale anche per i dispatch diretti fuori dal chain — dove B-mediata
  era più debole.
- **No tree pollution con scope `local`.** `.claude/agent-memory-local/` è non-checked-in by
  design (doc): il vincolo originario di ADR-0012 e di ADR-0011 è soddisfatto senza store centrale.
- **Feature di prima classe, basso rischio dipendenza.** A differenza del Workflow tool (gated,
  thread chiuso), `memory:` è documentato nei supported frontmatter fields e nel JSON `--agents`.
- **Pattern coerente coi best-practice ufficiali** ("subagent che accumula insight nella sua
  memoria" è l'esempio del doc, riga 444) e con la regola "preferisci il nativo".

### Negative

- **Tool surface dei sub-agent allargata.** Read/Write/Edit auto-abilitati anche su `reviewer`
  (oggi read-only). Confinati alla dir di memoria, ma è una concessione rispetto alla disciplina
  di ADR-0012 (sub-agent vede solo testo in/out). Vedi asse 4: accettabile, non gratis.
- **Perdita del controllo orchestratore/HITL su cosa entra in memoria.** B-mediata curava
  l'harvest; il nativo è autonomia dell'agente. Per scaffolding di sessione è il trade-off giusto;
  se la memoria contenesse mai dati sensibili sarebbe un problema (ma lo scope `local` non-checked-in
  e il confinamento alla dir limitano l'esposizione).
- **Costo di smontaggio + migrazione dati.** ADR-0012 è deployato e verde: smontarlo è lavoro reale
  (rimuovere contratto, helper, harness; seedare/migrare i dati; ri-puntare vibe-status). Mitigato
  dall'ordine sicuro (D5) e dalla coesistenza temporanea.
- **Dipendenza dal comportamento nativo non ancora testato live** su questo ambiente: il pilota è
  precondizione bloccante allo smontaggio.

### Neutral

- **Token cost:** sostanzialmente neutro/leggermente migliore. Il nativo carica ≤200 righe/25KB di
  `MEMORY.md` nel system prompt dell'agente (caricamento mirato e cap-ato); B-mediata iniettava il
  blocco `PRIOR AGENT NOTES` nel brief (l'`architect.md` storico è ~25KB → ordine di grandezza
  simile). Il cap nativo a 25KB è di fatto una protezione che B-mediata non aveva (iniettava tutto).
- **Reversibilità:** alta finché si tiene la coesistenza temporanea. Se il nativo deludesse in
  pilota, si torna a B-mediata (ancora in piedi) senza perdita — o si ripiega su Alternativa C di
  ADR-0012 (rimozione). I dati storici restano nello store centrale fino a conferma.
- **`.bak` storico** (`refactorer.md.bak-2026-05-20`): invariato, come in ADR-0012.
- **Repo `vibe-coding-system` NON-git:** il deliverable di questo ADR è il solo markdown. Lo
  smontaggio degli artefatti live (definizioni agente, 2 SKILL.md, helper/harness, vibe-status) è
  un **task separato** (plan, **senza commit step**), dopo approvazione e pilota.

---

## Alternatives considered

### A — Tenere ADR-0012 (mediazione) così com'è, ignorare il nativo

**Rifiutata.** È la scelta a costo-di-cambiamento zero (nulla da smontare) e mantiene il controllo
HITL dell'orchestratore. Ma: (1) **viola la regola guida** — manteniamo a mano (helper + contratto
in 2 skill + 3 agenti + harness) ciò che una feature ufficiale fa con un campo frontmatter; (2)
**conserva la fragilità dell'encoding** `tr '/' '-'` nell'helper e in vibe-status (la PRIOR NOTE
dice esplicitamente di preferire la risoluzione nativa); (3) **conserva il rischio-harvest** TOP
(orchestratore che dimentica di raccogliere, specie fuori dal chain). Il controllo HITL che B-mediata
offre non serve davvero per scaffolding di sessione (asse 5): non è un artefatto che richiede
approvazione umana su cosa entra. Mantenere complessità per un controllo non necessario è il caso
esatto che la regola "non aggiungere complessità finché il semplice non basta" vieta.

### B — Ibrido: nativo per la persistenza, ma orchestratore continua a curare/iniettare

**Rifiutata.** Si terrebbe il nativo per lo storage (path risolto da CC) ma l'orchestratore
continuerebbe a iniettare/curare le note. **Incoerente:** il nativo carica già `MEMORY.md`
nell'agente automaticamente — iniettarlo di nuovo nel brief è ridondanza pura (doppio caricamento,
doppio token). E se l'orchestratore cura, servono comunque l'helper e il path encoded → non si
elimina la fragilità né il codice. L'ibrido prende il costo di entrambi e il beneficio di nessuno.
L'unica giustificazione sarebbe il controllo HITL sulla scrittura, già scartato in A come non
necessario per scaffolding.

### C — Scope `project` (checked-in) invece di `local`

**Rifiutata.** `project` (`.claude/agent-memory/<agente>/`) è "shareable via version control":
re-introdurrebbe **esattamente** il conflitto che ADR-0012 ha risolto (file di scaffolding nel
tracked tree, esposti in pubblicazione, in tensione diretta con ADR-0011). Il driver originario di
ADR-0012 era "no scaffolding nel tracked tree": sceglierlo ora sarebbe annullare quel risultato. Va
escluso a meno che Stefano voglia deliberatamente versionare la memoria col progetto (improbabile,
date le regole esistenti).

### D — Scope `user` (cross-progetto) invece di `local`

**Rifiutata come default**, tenuta come opzione consapevole. `user` (`~/.claude/agent-memory/<agente>/`)
è fuori da ogni tree (no pollution) — bene. Ma è **cross-progetto**: mescola le note di tutti i
progetti in un'unica dir per agente. Per memoria *project-specific* (un bug-pattern di QUEL
codebase, una decisione di QUEL sistema) è semanticamente errato e rumoroso. `local` dà la stessa
assenza di pollution **e** l'isolamento per-progetto. `user` resta sensato solo per pattern
davvero universali (es. una convenzione che vale ovunque) — punto aperto per Stefano.

### E — Rimuovere del tutto la memoria agenti (= Alternativa C di ADR-0012)

**Rifiutata oggi, ma è il fallback dichiarato.** È la più semplice in assoluto: nessun campo, nessun
contratto. Si giustifica solo se il pilota mostrasse che gli agenti non producono note utili (stessa
assunzione non validata di ADR-0012). Finché si assume che la memoria valga, il nativo la preserva a
costo quasi-nullo, quindi rimuoverla butterebbe via valore. Se il pilota smentisse l'assunzione,
questa diventa la scelta corretta — più semplice ancora del nativo.

### Perché il nativo (scope `local`) nonostante il costo di smontaggio

È l'unica opzione che **rispetta la regola guida** (sostituisce codice nostro con una feature
ufficiale), **elimina** (non confina) la fragilità dell'encoding della PRIOR NOTE, **azzera** il
rischio-harvest TOP di ADR-0012 anche fuori dal chain, e **mantiene** l'assenza di tree pollution
(scope `local`). Il costo — tool surface allargata + perdita del controllo HITL orchestratore — è
proporzionato e accettabile per *scaffolding di sessione* (non artefatti di prodotto). Il costo di
smontaggio è una-tantum e protetto dall'ordine sicuro + coesistenza temporanea. ADR-0012 si
giustificava "solo perché non esisteva il nativo": quel presupposto è caduto.

---

## References

- `code.claude.com/docs/en/sub-agents` — sezione "Enable persistent memory" (campo `memory:` riga
  277/433; storage per scope righe 452-454; comportamento auto-abilitazione + caricamento MEMORY.md
  righe 456-460; tip righe 465-470; `memory` nei supported fields + JSON `--agents` riga 225).
  **Fonte primaria verificata 2026-05-25.**
- ADR-0012 — `docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` +
  `ADR-0012-implementation-plan.md` (la soluzione B-mediata deployata, superseded da questo ADR;
  Task 1-10 = lista esatta di ciò che va smontato).
- `~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh` — helper mediato da eliminare
  (righe 43-44 = il `tr '/' '-'` fragile che il nativo rende superfluo).
- `~/.claude/skills/concept-to-code/SKILL.md` (Step 2 inject/harvest architect) e
  `~/.claude/skills/review-triage-fix/SKILL.md` (inject/harvest reviewer+debugger) — i due
  dispatcher da semplificare.
- `~/.claude/agents/{architect,debugger,reviewer}.md` — aggiungere `memory: local`; rimuovere il
  contratto `PRIOR AGENT NOTES`/`DURABLE NOTES:`.
- `~/.claude/skills/vibe-status/scripts/aggregate.sh` — Section 7b da ri-puntare/rimuovere
  (elimina un altro `tr '/' '-'`).
- Store dati storici: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/agent-notes/{architect.md,debugger.md}`
  — da seedare nella memoria nativa, poi destino post-pilota (HITL gate).
- ADR-0004 — `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` e
  `feedback_pretooluse-payload-schema` (la fragilità encoding `_`→`-`/`cwd` che il nativo elimina).
- ADR-0009 — `docs/architecture/ADR-0009-db-backup-guardrail.md` (la PRIOR NOTE "preferisci input
  diretto/risoluzione nativa all'encoding derivato quando sufficiente").
- ADR-0011 — `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` (vincolo "fuori dal
  tracked tree": soddisfatto da scope `local` non-checked-in; scope `project` lo violerebbe).
- Memoria `reference_cc-capabilities-research-2026-05.md` (headline: il nativo overlappa ADR-0012)
  e `adr0012-agent-memory-mediated.md` (stato deploy + clausola di rivalutazione scelta 5).

---

DURABLE NOTES:
- [pattern] Quando una feature nativa ufficiale copre un meccanismo che avevamo costruito a mano, la regola "preferisci il nativo / non aggiungere complessità finché il semplice non basta" prevale anche su una soluzione già deployata e verde — purché esista coesistenza temporanea + pilota che evitano perdita dati (ADR-0013 supersede ADR-0012).
- [decisione] Per memoria agente NON-checked-in usare scope `memory: local` (.claude/agent-memory-local/), non `project` (checked-in → re-introduce il tree pollution di ADR-0012) né `user` (cross-progetto → semantica errata per memoria project-specific).
- [tradeoff] Il nativo `memory:` auto-abilita Write/Edit anche su agenti read-only (es. reviewer): accettabile perché confinato alla dir di memoria, ma è una concessione esplicita rispetto alla disciplina "sub-agent vede solo testo in/out" di ADR-0012.
- [robustezza] Il nativo risolve il path encoded internamente (scope→path), eliminando il `tr '/' '-'` fragile (ADR-0004/0009 PRIOR NOTE) invece di confinarlo all'orchestratore come faceva B-mediata.
