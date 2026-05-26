# ADR-0014 — L'architect propone `.claude/test-cmd` nel chain `concept-to-code` (Step 2), approvazione TOFU umana invariata

**Status:** Accepted — 2026-05-25 (Stefano: greenfield = **opzione A** "approva-l'intenzione-ora + fail-open dei consumatori finché non eseguibile"; formato blocco `TEST-CMD CANDIDATE:` / `TEST-CMD MODE:` confermato. Implementato: edit a `concept-to-code` Step 2 + nota coexistence; TOFU/`approve-test-cmd.sh` invariati.)

**Deciders:** architect (dispatch orchestrator), Stefano Ferri (approvazione finale)

**Related:** ADR-0002 (`docs/architecture/ADR-0002-refactor-snapshot-harness.md` — definisce
`.claude/test-cmd` come unico punto di contatto stack-specifico per la behavior-preservation,
strumentata via SHA256 dell'output del comando; questo ADR ne automatizza la *proposta*, non il
contratto); ADR-0003 (`docs/architecture/ADR-0003-concept-to-code-chain.md` — il chain in cui si
innesta la proposta, allo Step 2); ADR-0009 + swarm-testcmd (il fail-mode asimmetrico e la TOFU
SHA-pinned: "un test-cmd sbagliato dà falsa sicurezza → meglio UNVERIFIED che auto-indovinare";
questo ADR NON tocca quel gate); ADR-0012 (`docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md`
— precedente di come i contratti dell'architect sono veicolati dal **template del chain**, non
gonfiando `architect.md`; pattern riusato qui per il blocco `TEST-CMD CANDIDATE`).

---

## Context

### Il file `.claude/test-cmd` e i suoi consumatori (VERIFICATO 2026-05-25)

`.claude/test-cmd` è un file a una riga utile (più commenti `#` e righe vuote) che dichiara il
comando di test del progetto. È il **solo punto di contatto stack-specifico** della
behavior-preservation (ADR-0002). Formato e parser sono identici in tutti i consumatori (awk:
prima riga non-vuota, non-commento; valore speciale `NONE` = opt-out). I consumatori risalgono
l'albero da cwd cercando `.claude/test-cmd` (max 40 livelli):

- `~/.claude/hooks/stop-gate.sh` — a fine task, se il codice è "dirty", **esegue** il comando se
  e solo se il file è TOFU-trusted; altrimenti blocca chiedendo l'approvazione. Fail-open su
  file assente/`NONE`/vuoto/non-eseguibile/timeout (mai falsa conferma).
- `~/.claude/skills/review-triage-fix/scripts/verify.sh` — reporter (non gate): PASS / FAIL /
  **UNVERIFIED** come primo token; UNVERIFIED se file assente, `NONE`, vuoto o non eseguibile.
- `~/.claude/skills/refactor-snapshot/` + `~/.claude/agents/refactorer.md` — il refactorer
  ESIGE che il file pre-esista e sia approvato; se assente → snapshot UNVERIFIED → STOP.
- `~/.claude/hooks/approve-test-cmd.sh` — CLI TOFU (NON un hook). Calcola lo SHA256 del file e
  registra `<sha256>\t<root-normalizzato>` nel trust file. **Non esegue mai il comando.** Cambiare
  il file invalida il trust → riapprovazione necessaria.

### Il problema: frizione "crealo a mano"

Oggi `.claude/test-cmd` deve essere **scritto a mano** e poi approvato con la CLI. Il chain
`concept-to-code` non lo scaffolda: lo cita solo nelle coexistence invariants (SKILL.md riga 559).
Conseguenza: ogni nuovo progetto passato dal chain arriva all'implementazione senza test-cmd, e i
tre consumatori restano in stato non-verificato (block/UNVERIFIED/STOP) finché Stefano non crea il
file manualmente. La frizione è inutile: allo **Step 2** del chain l'architect ha già letto SPEC,
ARCH e lo stack/framework — è il punto **più informato** del workflow per dedurre il comando di
test corretto. Spostare la deduzione lì elimina il lavoro manuale senza spostare il gate di
sicurezza.

### Greenfield vs brownfield: la tensione da risolvere

- **Brownfield** (progetto esistente con test): il comando dedotto dall'architect è
  **eseguibile subito**. La proposta è anche immediatamente verificabile.
- **Greenfield** (progetto nuovo, test non ancora scritti): il comando è quello *previsto*
  (es. `pytest -q`, `npm test`) ma **non gira** finché i test non esistono (tipicamente fino
  allo scaffold/impl). Approvare ora un comando non ancora eseguibile è sicuro per la TOFU (SHA
  pinned su un'intenzione), ma non è ancora "verificato in esecuzione": al primo run i consumatori
  fail-open su "non eseguibile" (stop-gate fail-open, verify.sh UNVERIFIED) — quindi **nessuna
  falsa conferma**, ma serve decidere QUANDO l'approvazione/uso diventa sensato. Questa tensione
  è risolta esplicitamente in Decision punto 4 (con la decisione finale deferita a Stefano).

---

## Decision

1. **Punto di proposta = architect, Step 2.** Nel report dell'architect viene aggiunto un blocco
   strutturato terminale `TEST-CMD CANDIDATE:` con il comando di test dedotto dallo stack, e il
   flag greenfield/brownfield (formato in Decision punto 3). Il contratto è veicolato dal
   **template del chain** (SKILL.md Step 2), NON da `architect.md` — coerente con ADR-0012, per
   non gonfiare la definizione dell'agente con logica specifica del chain.

2. **L'orchestratore scrive il candidato; l'umano approva.** Dopo il ritorno dell'architect,
   l'orchestratore estrae il comando dal blocco e scrive `<project-root>/.claude/test-cmd` come
   **candidato** (con un commento `#` che lo marca proposto + flag greenfield se applicabile).
   Poi presenta un **gate HITL** che mostra il comando e chiede a Stefano di approvarlo eseguendo
   `bash ~/.claude/hooks/approve-test-cmd.sh "<project-root>"`. Si **riusa il meccanismo TOFU
   esistente**: nessun nuovo gate, nessun nuovo trust store, nessuna nuova CLI.

3. **Formato del blocco architect** (terminale, dopo `DURABLE NOTES:`):
   ```
   TEST-CMD CANDIDATE: <comando di test su una riga>
   TEST-CMD MODE: greenfield | brownfield
   ```
   Se l'architect non può dedurre un comando affidabile → la riga letterale
   `TEST-CMD CANDIDATE: none` (l'orchestratore NON scrive il file e lo segnala al gate).

4. **Risoluzione greenfield (deferita a Stefano — punto aperto).** Approccio raccomandato:
   **approvazione-dell'intenzione ora + verifica-eseguibilità al primo uso reale**. Lo
   `.claude/test-cmd` greenfield si scrive e si approva subito (SHA pinned sull'intenzione);
   marcato col commento `# greenfield: provisional — non eseguibile finché i test non esistono`.
   Fino ad allora i consumatori fail-open correttamente (stop-gate fail-open su rc 124/125/126/127,
   verify.sh → UNVERIFIED): mai falsa conferma. Quando appaiono i primi test (scaffold/impl), il
   comando diventa eseguibile **senza alcuna ri-approvazione** purché il file non sia cambiato; se
   l'architect aveva sbagliato il comando e va corretto, il cambio del file invalida la TOFU e
   forza una riapprovazione — comportamento desiderato. **Alternativa che Stefano deve valutare:**
   spostare il gate di approvazione greenfield *dopo* i primi test (approvare solo un comando già
   eseguibile), al costo di lasciare il progetto non-verificato durante lo scaffold iniziale.

5. **Sicurezza invariata.** L'approvazione SHA-pinned resta **umana e singola**. Il sistema
   PROPONE (scrive un candidato), non auto-esegue **mai** un comando non approvato: lo scrivere il
   file NON lo rende trusted — il trust nasce solo dall'esecuzione esplicita di `approve-test-cmd.sh`
   da parte di Stefano. Questo **non indebolisce la TOFU**: l'oggetto pinnato (SHA del file) e il
   gate (CLI umana) sono invariati; cambia solo *chi redige il candidato* (architect anziché
   Stefano a mano), che è a monte del pin.

6. **Coexistence invariata.** Il candidato è scritto nello stesso formato a una riga consumato
   da stop-gate / verify.sh / refactor-snapshot; nessuno script consumatore cambia. Le coexistence
   invariants del chain (SKILL.md) restano valide; si aggiorna solo la nota da "non scaffolda
   test-cmd" a "scaffolda un candidato test-cmd allo Step 2, approvazione TOFU invariata".

---

## Consequences

**Positive**
- Elimina la frizione "crealo a mano": il comando lo redige il punto più informato del chain.
- Zero nuova superficie di sicurezza: riusa TOFU + trust store + CLI esistenti.
- Coerente con ADR-0012: contratto nel template del chain, `architect.md` non si gonfia.
- I consumatori (stop-gate/verify.sh/refactorer) non cambiano: rischio di regressione minimo.

**Negative**
- L'architect può dedurre un comando sbagliato; mitigato dal fatto che il gate HITL mostra il
  comando a Stefano *prima* dell'approvazione, e che un comando errato dà UNVERIFIED (non falsa
  conferma) finché non corretto + riapprovato.
- Greenfield introduce uno stato "provvisorio" che richiede disciplina (la decisione su quando
  approvare resta aperta, punto 4).

**Neutral**
- Il chain acquisisce un micro-step in più (scrittura candidato + gate). Su brownfield è anche
  immediatamente verificabile; su greenfield è dichiarativo.
- Se l'architect emette `TEST-CMD CANDIDATE: none`, il comportamento è identico ad oggi (nessun
  file, consumatori in stato non-verificato): nessuna regressione rispetto allo status quo.

---

## Alternatives considered

**(A) Status quo — creazione manuale del test-cmd.** Rifiutata: è esattamente la frizione che
Stefano vuole rimuovere. Lascia ogni nuovo progetto del chain senza test-cmd fino a intervento
manuale, con i tre consumatori bloccati/UNVERIFIED. Nessun guadagno se non l'assenza di lavoro di
design.

**(B) Auto-detect euristico a runtime, senza coinvolgere l'architettura.** Uno script che, al
primo uso, indovina il comando dai file presenti (presenza di `pytest.ini`, `package.json`,
`Cargo.toml`…) e lo scrive/esegue. Rifiutata: l'euristica è **meno informata dell'architect** (non
conosce SPEC/ARCH né le scelte di test del progetto), e — per il principio di ADR-0009/swarm-testcmd
— un test-cmd indovinato male dà **falsa sicurezza**. Eseguire senza approvazione viola la TOFU;
nessun euristico è abbastanza affidabile da bypassare il gate umano.

**(C) Proposta allo Step 2 (architect) + approvazione TOFU singola — SCELTA.** L'architect, già il
punto più informato del chain, dichiara il comando nel report; l'orchestratore scrive un candidato;
Stefano approva una volta con la CLI esistente. Combina il vantaggio informativo di un'analisi a
livello di architettura con il gate di sicurezza umano invariato. Motivo della scelta: massimizza
la qualità della proposta e azzera la nuova superficie di sicurezza, mantenendo il PROPONE-non-esegue.

**(D) Gate di approvazione spostato a fine chain (dopo i primi test, solo comandi eseguibili).**
Scartata come default, ma trattenuta come opzione greenfield in Decision punto 4: garantisce che si
approvi solo un comando già eseguibile, al costo di lasciare lo scaffold iniziale non-verificato e
di spostare il gate lontano dal punto in cui il comando è dedotto.

---

## References

- `~/.claude/hooks/approve-test-cmd.sh` — CLI TOFU (SHA256-pinning, mai esegue il comando).
- `~/.claude/hooks/stop-gate.sh` — enforce TOFU + esecuzione a fine task, fail-open asimmetrico.
- `~/.claude/skills/review-triage-fix/scripts/verify.sh` — reporter PASS/FAIL/UNVERIFIED.
- `~/.claude/agents/refactorer.md` — consumatore che ESIGE test-cmd approvato (snapshot UNVERIFIED se assente).
- `~/.claude/skills/concept-to-code/SKILL.md` — Step 2 (dispatch architect, ~righe 167-221) punto di innesto; coexistence invariants riga ~559.
- ADR-0002, ADR-0003, ADR-0009, ADR-0012 (vedi Related).
