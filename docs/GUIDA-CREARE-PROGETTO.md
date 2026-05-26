# Guida — Come creare un progetto con il tuo sistema Vibe Coding

Spiegata semplice, passo per passo. Niente cose date per scontate.

---

## 1. Cos'è questo sistema (in 30 secondi)

Immagina di avere una **squadra di assistenti specializzati** dentro Claude
Code. Ognuno è bravo in una cosa sola:

- chi **progetta** (architect),
- chi **scrive il codice** (coder),
- chi **scrive i test** (tester),
- chi **trova i bug** (debugger),
- chi **controlla la qualità** (reviewer),
- chi **scrive la documentazione** (doc-writer),
- chi **riordina il codice** (refactorer),
- chi **cerca informazioni** (researcher).

Più dei **comandi speciali** (le "skill", iniziano con `/`) che fanno partire
procedure pronte (es. l'intervista per capire cosa vuoi costruire).

Più delle **regole automatiche** che si attivano da sole (es. quando tocchi un
file `.py` partono le regole Python; dopo ogni modifica il codice viene
formattato; i file segreti tipo `.env` sono bloccati).

Tu sei il **capo**. Dai gli ordini, approvi le decisioni importanti, e la
squadra lavora.

---

## 2. Le 2 fasi (la regola d'oro più importante)

Costruire un progetto si fa in **due fasi separate**, in **due sessioni
diverse** di Claude:

- **FASE 1 — PENSARE**: decidi *cosa* costruire. Si crea un documento `SPEC.md`
  (la "lista della spesa" del progetto) e le decisioni di architettura (ADR).
- **FASE 2 — COSTRUIRE**: scrivi il codice vero, seguendo quello che hai deciso
  in Fase 1.

**Perché separate?** Perché se mischi "pensare" e "scrivere codice" nella stessa
chat, Claude si confonde (troppa roba in testa). Tra Fase 1 e Fase 2 si apre una
**sessione nuova e pulita**.

> Parola difficile spiegata:
> - **SPEC.md** = il foglio che dice *cosa* deve fare il progetto.
> - **ADR** = il foglio che dice *come* è stato deciso di farlo e *perché*
>   (Architecture Decision Record). Si trova in `docs/architecture/`.
> - **HITL gate** = un punto in cui Claude si ferma e aspetta il tuo OK
>   ("Human In The Loop" = c'è l'umano nel giro). Succede prima di commit,
>   push, deploy, cancellazioni.

---

## 3. Prima di iniziare (controllo veloce, 1 volta)

Il sistema è **già installato**. Per essere sicuro che funzioni, apri Claude in
una cartella qualsiasi e digita questi comandi (uno alla volta), premi Invio,
guarda:

- `/agents` → devi vedere: architect, coder, reviewer, tester, debugger,
  doc-writer, refactorer, researcher.
- `/skills` → devi vedere le skill custom (adr-writer, claude-md-generator,
  swift-vibe, ecc.).
- `/mcp` → `github` e `sequential-thinking` devono essere "connected".

Se li vedi, sei pronto.

---

## 4. Creare un progetto — passo per passo

### Passo 0 — Crea la cartella del progetto

Apri il Terminale. Scrivi questi comandi **uno alla volta** (sostituisci
`nome-progetto` col nome vero, senza spazi):

```
mkdir -p ~/developer/nome-progetto
```
```
cd ~/developer/nome-progetto && git init
```
```
cd ~/developer/nome-progetto && python3 -m venv .venv && source .venv/bin/activate
```

> Cosa hai fatto: creato la cartella, acceso il "salvataggio storia" (git),
> creato un ambiente Python isolato (venv) così non sporchi il computer.

### Passo 1 — Apri Claude DENTRO la cartella

```
cd ~/developer/nome-progetto
claude
```

Da qui in poi, i comandi `/...` e `@...` si scrivono **dentro Claude**, non nel
Terminale.

### Passo 2 — FASE 1: l'intervista (cosa vuoi costruire)

Scrivi dentro Claude:

```
/interview-driver descrivi qui in una riga cosa vuoi costruire
```

Claude ti farà **domande, una alla volta**. Rispondi con calma: scava sui punti
difficili, non dare risposte vaghe. Alla fine scrive il file `SPEC.md`.

> Trucco: se è un progetto piccolo e vuoi fare tutto in colpo solo, usa
> `/project-bootstrap descrizione` al posto di `/interview-driver`: fa
> l'intervista, l'architettura e il CLAUDE.md di fila (fermandosi a chiederti
> OK tra un passo e l'altro).

### Passo 3 — Le decisioni di architettura (ADR)

Sempre dentro Claude, chiama l'**architetto**:

```
@"architect (agent)" leggi SPEC.md e scrivi un ADR in docs/architecture/ con le decisioni principali e le alternative scartate. Non scrivere codice.
```

Leggi l'ADR che produce. Se ti convince → **approva**. Se c'è qualcosa che non
va → diglielo e lo corregge.

> Importante: l'**ADR è il piano**. Per progetti piccoli/medi non serve un piano
> separato: l'ADR con i suoi passi basta.

### Passo 4 — Il CLAUDE.md del progetto

```
/claude-md-generator
```

Crea il `CLAUDE.md` del progetto: un foglietto di istruzioni specifiche di
*questo* progetto (comandi, struttura, regole sue). Eredita le regole globali,
non le ripete. Controlla che sia sensato e corto (< ~100 righe).

### Passo 5 — STOP e pulisci (passaggio Fase 1 → Fase 2)

per orHai finito di "pensare". Ora:

1. Fai il primo salvataggio nel progetto (nel Terminale):
   ```
   cd ~/developer/nome-progetto && git add -A && git commit -m "chore: spec e architettura iniziali"
   ```
2. **Chiudi questa sessione Claude** e **aprine una nuova** nella stessa
   cartella (sessione pulita per la Fase 2). Oppure dentro Claude scrivi
   `/clear`.

### Passo 6 — FASE 2: scrivere il codice

Chiama il **coder**, dicendogli di seguire SPEC e ADR:

```
@"coder (agent)" implementa il progetto seguendo SPEC.md, l'ADR in docs/architecture/ e CLAUDE.md. Non committare.
```

Il coder scrive il codice. Tu non tocchi niente, guardi.

### Passo 7 — I test

```
@"tester (agent)" scrivi ed esegui i test (pytest) per la logica principale, inclusi i casi limite. Non modificare il codice di produzione.
```

### Passo 8 — Se qualcosa è rotto

```
@"debugger (agent)" [incolla qui l'errore o il test che fallisce]. Trova la causa vera e applica il fix minimo.
```

### Passo 9 — Il controllo qualità

```
@"reviewer (agent)" rivedi le modifiche recenti per sicurezza, correttezza, performance e coerenza. Output per gravità.
```

Ti dà una lista divisa in BLOCKER (bloccante) / MAJOR / MINOR / NIT. Decidi tu
cosa applicare.

### Passo 10 — La documentazione (opzionale)

```
@"doc-writer (agent)" aggiorna il README e il CHANGELOG con quello che è stato fatto.
```

### Passo 11 — Salva e (se vuoi) apri la Pull Request

Nel Terminale:
```
cd ~/developer/nome-progetto && git add -A && git commit -m "feat: descrizione di cosa hai fatto"
```
Per una PR (serve `gh` configurato):
```
cd ~/developer/nome-progetto && gh pr create --fill
```

> Claude ti chiederà conferma prima di azioni importanti (commit, push): è
> l'HITL gate. È normale e voluto.

### Passo 12 — Ripeti per ogni nuova funzione

Per ogni funzione nuova: torna al Passo 6 (coder → tester → reviewer → commit).
**Tra funzioni diverse e non collegate, scrivi `/clear`** per ripulire la testa
di Claude.

---

## 5. Tabella rapida — le skill (comandi `/`)

| Comando | Quando si usa | Si attiva da... |
|---|---|---|
| `/interview-driver` | inizio progetto/feature: capire cosa costruire | solo tu (a mano) |
| `/project-bootstrap` | progetto piccolo: fa tutta la Fase 1 in fila | solo tu (a mano) |
| `/claude-md-generator` | creare il CLAUDE.md del progetto | a mano (o da solo) |
| `/adr-writer` | scrivere una decisione di architettura | da solo quando serve |
| `/fastapi-react-vibe` | creare un pezzo CRUD FastAPI+React | solo tu (a mano) |
| `/code-review-checklist` | review strutturata | da solo / via reviewer |
| `/swift-vibe` | aiuto pattern SwiftUI | da solo quando serve |

> "solo tu (a mano)" = Claude NON la fa partire da solo, devi scriverla tu.

## 6. Tabella rapida — gli agenti (`@"nome (agent)"`)

| Agente | Cosa fa | Quando |
|---|---|---|
| architect | progetta, scrive ADR, NON scrive codice | inizio feature non banale |
| coder | scrive il codice seguendo l'ADR | dopo l'ADR approvato |
| tester | scrive ed esegue i test | dopo il coder |
| debugger | trova la causa vera dei bug | quando qualcosa è rotto |
| reviewer | controlla qualità/sicurezza (solo legge) | prima del commit |
| doc-writer | README, CHANGELOG, docstring | a feature finita |
| refactorer | riordina senza cambiare comportamento | su richiesta / dopo review |
| researcher | cerca documentazione con fonti | libreria/API sconosciuta |

## 7. Comandi utili da sapere

| Comando / tasti | A cosa serve |
|---|---|
| `/clear` | pulisce la memoria di Claude tra task diversi |
| `/memory` | mostra CLAUDE.md e regole caricate |
| `/agents` `/skills` `/hooks` `/mcp` | mostrano cosa è attivo |
| `Shift+Tab` | cambia "modalità permessi" (plan mode, ecc.) |
| `Esc` | ferma Claude a metà azione (senza perdere il contesto) |
| `Esc Esc` o `/rewind` | torna indietro a un punto precedente |
| `! comando` | esegue un comando di terminale da dentro Claude |
| `@nomefile` | fa leggere a Claude un file specifico |

## 8. Le 7 regole d'oro (stampatele in testa)

1. **Fase 1 e Fase 2 in sessioni separate.** Mai mischiare pensare e codificare.
2. **`/clear` tra task diversi.** Contesto pulito = Claude più bravo.
3. **L'ADR è il piano.** Se c'è l'ADR approvato, il coder può partire.
4. **Approva tu le cose importanti** (commit, push, deploy): è l'HITL gate.
5. **Mai incollare segreti in chat** (token, password). Vanno in `~/.zshrc` o
   file di config, mai nei messaggi.
6. **Se un test fallisce, NON disabilitarlo per farlo passare.** Chiama il
   debugger.
7. **Comandi lunghi nel terminale**: incollali uno alla volta, corti, per
   evitare che si spezzino.

## 9. Cosa succede da solo (non te ne preoccupare)

- Apri un file `.py` → si caricano le regole Python (type hint, docstring…).
  Stesso per `.swift`, `.ts/.tsx`, ecc.
- Salvi un file → viene **formattato automaticamente** (ruff/prettier).
- Provi a toccare `.env` o file segreti → **bloccato** automaticamente.
- Comando rischioso → la modalità **auto** ti chiede conferma; comando sicuro e
  noto → parte senza disturbarti.

---

## 10. Il giro completo, in una riga

**cartella + git + venv → `claude` dentro → `/interview-driver` → `@architect`
(ADR) → `/claude-md-generator` → sessione nuova → `@coder` → `@tester` →
(`@debugger` se serve) → `@reviewer` → commit → ripeti.**

Fine. Se ti perdi, riapri questa guida al passo dove sei.
