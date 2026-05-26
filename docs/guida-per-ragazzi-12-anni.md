# La guida facile al sistema Vibe Coding

**Per chi è questa guida:** per chi non ha mai programmato (anche un ragazzino di 12 anni), e vuole capire **cosa è stato costruito** e **come usarlo** senza impazzire con parole difficili.

**Cosa imparerai:**
1. Cos'è Claude Code (in 1 minuto)
2. La squadra di "robot programmatori" che ti aiuta
3. Gli strumenti magici (skill)
4. Le guardie del castello (hook)
5. Il quaderno di appunti del computer (memory)
6. Come fare il tuo primo progetto dall'inizio alla fine
7. Cose da NON fare
8. Glossario delle parole difficili

---

## 1. Cos'è Claude Code (in 1 minuto)

Immagina di avere un **amico molto bravo a programmare** che vive dentro al tuo computer. Tu gli scrivi cosa vuoi fare e lui scrive il codice per te. Si chiama **Claude Code**.

Però c'è un problema: un amico solo, anche se molto bravo, non sa fare tutto bene. Per esempio, è bravo a scrivere codice ma forse non è il migliore a controllarlo, o a fare test, o a riorganizzarlo.

**La soluzione:** invece di un amico solo, abbiamo costruito **una squadra di amici-robot**, ognuno specializzato in una cosa diversa. Si chiama **sistema multi-agente** (multi = tanti, agente = robot che fa una cosa specifica).

---

## 2. La squadra di robot programmatori

Pensa a una squadra di calcio: ogni giocatore ha un ruolo. Anche qui abbiamo 8 "giocatori-robot", ognuno con il suo lavoro.

| Robot | Cosa fa | Come ricordarlo |
|-------|---------|-----------------|
| **architect** | Disegna i piani prima di costruire (come un architetto vero) | "Architetto" |
| **coder** | Scrive il codice (il muratore della squadra) | "Codice = code" |
| **reviewer** | Controlla che il codice sia fatto bene (il controllore) | "Review = controllare" |
| **tester** | Fa i test (prova se tutto funziona) | "Test = prova" |
| **debugger** | Trova i bug (i bachi nel codice) | "Bug = baco, debug = trova-baco" |
| **refactorer** | Riorganizza il codice senza romperlo (mette in ordine) | "Refactor = rimettere insieme" |
| **doc-writer** | Scrive la documentazione (i manuali di istruzione) | "Doc = documento" |
| **researcher** | Ricerca informazioni su internet (il bibliotecario) | "Research = ricerca" |

**Regola d'oro della squadra:**
> Solo il "capitano" (l'**orchestrator**, cioè la sessione principale del terminale) può chiamare i giocatori. I giocatori NON possono chiamare altri giocatori. Sono come solisti.

### Come si "chiama" un robot?

Tu non li chiami direttamente: scrivi cosa vuoi all'**orchestrator** (l'amico-Claude principale) e lui decide quale robot mandare. È un po' come dare un ordine all'allenatore, che poi manda in campo i giocatori giusti.

---

## 3. Gli strumenti magici (skill)

Ogni robot può usare degli **strumenti magici** chiamati **skill** (in inglese vuol dire "abilità"). Sono come gli oggetti di un videogioco: ognuno fa una cosa speciale.

Ecco i 3 strumenti più importanti che abbiamo costruito **oggi**:

### Strumento 1: `review-triage-fix` (il ciclo di controllo)

**A cosa serve:** dopo che il coder scrive del codice, questo strumento fa girare il reviewer per trovare problemi, poi fa fixare al coder i problemi più gravi, e ripete finché tutto è a posto.

**Esempio:** è come quando finisci i compiti, la mamma li controlla, ti dice "qui c'è un errore", tu correggi, e poi la mamma li ricontrolla.

### Strumento 2: `refactor-snapshot` (il fotografo)

**A cosa serve:** prima che il refactorer riorganizzi il codice, scatta una **fotografia** di come funziona. Dopo aver riorganizzato, scatta un'altra foto e le confronta. Se le foto sono uguali, perfetto. Se sono diverse, vuol dire che durante la riorganizzazione qualcosa si è rotto e ti avvisa.

**Esempio:** è come quando rimetti in ordine la tua stanza e poi vuoi essere sicuro che tutti i giocattoli funzionino ancora. Prima li provi tutti (foto 1), li sposti, poi li riprovi tutti (foto 2). Se uno non funziona più, l'hai rotto durante il riordino.

### Strumento 3: `concept-to-code` (il direttore d'orchestra)

**A cosa serve:** è lo strumento più importante. Ti accompagna dall'**idea** ("voglio fare un gioco di dadi") al **codice finito**, passando per tutti gli step nel giusto ordine. Chiama in automatico l'architect, poi il coder, poi (se vuoi) il reviewer.

**Esempio:** è come quando prepari un dolce. Non puoi mettere il forno acceso prima di avere gli ingredienti. C'è un ordine. `concept-to-code` è la ricetta che dice "prima fai X, poi Y, poi Z".

---

### Altri strumenti utili (li abbiamo trovati o costruiti)

| Strumento | Cosa fa |
|-----------|---------|
| `interview-driver` | Ti fa tante domande per capire cosa vuoi davvero (intervista) |
| `adr-writer` | Scrive un documento speciale chiamato ADR (vedi glossario) |
| `claude-md-generator` | Crea il "manuale" del progetto (CLAUDE.md) |
| `brainstorming` | Ti aiuta a pensare insieme prima di iniziare |
| `commit` | Salva il tuo lavoro su Git (vedi glossario) |

---

## 4. Le guardie del castello (hook)

Immagina che il tuo computer sia un castello. Ci sono dei punti pericolosi: per esempio, **eliminare un file** è pericoloso perché se sbagli perdi tutto.

Per questo abbiamo messo delle **guardie automatiche** chiamate **hook** (in inglese "gancio", perché si "agganciano" alle azioni pericolose). Quando un robot sta per fare qualcosa di pericoloso, la guardia lo ferma e chiede prima di proseguire.

**Le nostre guardie:**

- **`stop-gate`**: ferma il robot prima che faccia cose pericolose (come eliminare file)
- **`approve-test-cmd`**: chiede prima di lanciare un comando che fa partire i test (perché i test possono modificare file)
- **`migrate-trust-paths`**: pulisce la lista degli "amici fidati" del castello

Tu non devi fare niente per le guardie: lavorano in automatico in sottofondo.

---

## 5. Il quaderno di appunti del computer (memory)

Hai presente quando un compagno di scuola ti dice una cosa e tu te la scrivi in un quaderno per non dimenticartela? Il nostro sistema fa esattamente questo, ma in automatico.

**Dove vive il quaderno:**
`~/.claude/projects/.../memory/`

**Cosa scrive:**
- Cose su di te (esempio: "Stefano preferisce risposte tecniche e brevi")
- Lezioni imparate (esempio: "questo bash non supporta gli array associativi")
- Stato dei progetti in corso
- Link a sistemi esterni

**Quando lo usa:**
Ogni volta che inizia una nuova sessione, il computer rilegge il quaderno e ricorda tutto.

### Il manuale del progetto: `CLAUDE.md`

Oltre al quaderno generale, ogni progetto ha il suo **manuale** chiamato **`CLAUDE.md`**. È come la guida di un videogioco: spiega le regole specifiche di quel progetto.

---

## 6. STEP-BY-STEP: come fare il tuo primo progetto

Diciamo che vuoi fare un piccolo gioco di indovinello. Ecco come faresti.

### Step 1: Apri il terminale e scrivi `claude`

Si apre la chat con l'amico-Claude (l'orchestrator).

### Step 2: Lancia `/concept-to-code`

Digita questo e premi invio:

```
/concept-to-code gioco di indovinello dei numeri
```

Da qui in avanti il sistema ti guida.

### Step 3: L'intervista (Step 1 del chain)

L'`interview-driver` ti farà delle domande per capire bene cosa vuoi:
- Quale linguaggio? (Python? JavaScript?)
- Quanti tentativi può fare il giocatore?
- Vuoi che il computer suggerisca "più alto" / "più basso"?
- Vuoi un punteggio?

Tu rispondi. Alla fine viene scritto un file chiamato `SPEC.md` (la "ricetta" del tuo progetto).

### Step 4: PRIMO GATE — Tu approvi la spec

Il sistema ti mostra `SPEC.md` e chiede: **"Va bene così?"**

Se sì, prosegui. Se no, modifichi e ripeti.

### Step 5: L'architettura (Step 2 del chain)

Viene chiamato il robot **architect**. Lui legge `SPEC.md` e produce 3 cose:
- Un **ADR** (decisione architetturale — vedi glossario)
- Un file **`ARCH.md`** (come è organizzato il progetto)
- Un **piano TDD** (i passi da seguire)

### Step 6: SECONDO GATE — Tu approvi l'architettura

Il sistema ti mostra i 3 file. Tu controlli e dici "ok, prosegui" oppure "cambia questo".

### Step 7: Il manuale del progetto (Step 3 del chain)

Viene chiamato lo strumento **`claude-md-generator`** che scrive il **manuale del progetto** (`CLAUDE.md`).

### Step 8: TERZO GATE — Tu approvi il manuale

Stessa cosa: controlli, approvi.

### Step 9: Fresh session (Step 4 del chain — IMPORTANTE)

Il sistema ti dice:

> "Ora chiudi questa sessione e aprine una nuova. Quando sei nella nuova, scrivi: `/concept-to-code resume <percorso-del-manifest>`"

**Perché?** Perché la sessione attuale è piena di domande/risposte dell'intervista. Per il prossimo step serve "una mente fresca" (in inglese "fresh session"). È come quando hai studiato 3 ore e devi fare una pausa prima di iniziare a fare il compito vero.

### Step 10: L'implementazione (Step 5 del chain)

Nella nuova sessione, il sistema chiama il robot **coder** che, leggendo tutti i file (`SPEC.md`, ADR, `ARCH.md`, `CLAUDE.md`), inizia a scrivere il codice.

**Cosa fa di speciale il coder:** prima di ogni modifica, dichiara una **etichetta** che dice che tipo di modifica sta facendo:
- `PATTERN: ADD` = sto aggiungendo codice nuovo
- `PATTERN: REMOVE` = sto cancellando codice
- `PATTERN: REPLACE` = sto sostituendo codice vecchio con nuovo (e DEVE dire cosa toglie + cosa mette)
- `PATTERN: MODIFY` = sto modificando una cosa esistente senza cambiare struttura

Questa etichetta si chiama **Pre-flight Pattern Classifier** ed è una delle cose che abbiamo costruito oggi. Serve a evitare che il coder dimentichi di cancellare codice vecchio quando lo sostituisce con nuovo.

### Step 11: Review (Step 6 del chain — opzionale)

Se vuoi, lanci `review-triage-fix` che fa girare il **reviewer** per controllare il codice, segnalare problemi, e fa fixare al coder le cose importanti.

### Step 12: Hai finito!

Il tuo gioco è pronto. Lo provi. Se funziona, festeggi. Se no, vedi sotto.

---

## 7. Cose da NON fare (sicurezza)

1. **MAI cancellare file** senza che ti venga chiesto. Il computer non può rimettere indietro le cose cancellate.
2. **MAI commit di file segreti** (password, chiavi API, file `.env`). Sono come la chiave di casa: non li dai a nessuno.
3. **MAI disabilitare un test** solo per farlo passare. Un test rosso ti dice che c'è un problema. Spegnerlo non risolve il problema, lo nasconde.
4. **MAI lanciare `rm -rf`** senza pensarci 3 volte. Cancella tutto e per sempre.
5. **MAI scrivere direttamente sul ramo `main`** di Git. Sempre su un **feature branch** (vedi glossario).
6. **CHIEDI SEMPRE** prima di fare cose che non capisci. Meglio chiedere 10 volte che rompere tutto 1 volta.

---

## 8. Se qualcosa va storto

### Caso A: il codice non funziona
1. Chiama il robot **debugger**: "trova il problema in questo codice"
2. Lui ti dice cosa non va e perché
3. Tu (o il coder) lo fixate

### Caso B: il computer dice "comando non trovato"
1. Forse hai scritto male un comando
2. Controlla le maiuscole/minuscole (il computer è schizzinoso)

### Caso C: i test diventano rossi
1. Vuol dire che qualcosa si è rotto
2. NON disabilitare i test! Trova il problema.
3. Lancia il **debugger** o chiedi all'amico-Claude

### Caso D: hai paura di rompere tutto
1. Prima di fare modifiche grandi, lancia il **refactor-snapshot** (il fotografo)
2. Così se rompi qualcosa lo sai subito

---

## 9. GLOSSARIO — parole difficili spiegate

| Parola | Cosa vuol dire (versione semplice) |
|--------|-----------------------------------|
| **agent / agente** | Un robot che fa una cosa specifica |
| **orchestrator** | Il robot-capo che chiama gli altri robot |
| **skill** | Uno strumento magico che un robot può usare |
| **hook** | Una guardia automatica che ferma cose pericolose |
| **CLAUDE.md** | Il manuale di istruzioni di un progetto |
| **memory** | Il quaderno di appunti del computer |
| **terminal** | La finestra nera dove scrivi i comandi |
| **prompt** | Quello che scrivi all'amico-Claude |
| **Git** | Un sistema che salva tutte le versioni del tuo codice (come "salva con nome" su scala enorme) |
| **commit** | Salvare una versione del codice in Git |
| **branch** | Una "versione parallela" del codice, dove puoi sperimentare senza rompere quella principale |
| **main branch** | La versione "ufficiale" del codice |
| **feature branch** | Una versione di prova dove fai cose nuove |
| **PR (Pull Request)** | Una richiesta di unire il tuo branch con il main |
| **ADR** | Architecture Decision Record — un documento che spiega PERCHÉ abbiamo deciso una cosa in un certo modo |
| **SPEC** | Specifica — cosa deve fare il programma (la ricetta) |
| **ARCH** | Architettura — come è organizzato il programma (lo schema del palazzo) |
| **TDD** | Test-Driven Development — scrivi prima i test, poi il codice. Funziona meglio di tutti gli altri metodi |
| **plan / piano** | La lista dei passi da seguire (la to-do list) |
| **harness** | Un sistema automatico che controlla che le cose siano ancora a posto |
| **anchor** | Una specie di "segnalibro" nel codice che permette ai test automatici di trovare le cose |
| **bash** | Il linguaggio dei comandi del terminale (Mac/Linux) |
| **Python** | Un linguaggio di programmazione semplice e potente |
| **MCP** | Una connessione a servizi esterni (es. GitHub, Slack) |
| **fresh session** | Aprire una nuova chat con l'amico-Claude da zero |
| **HITL gate** | "Human In The Loop" — un punto dove serve la tua approvazione |
| **dispatch** | Mandare in campo un robot |
| **manifest** | Una lista (in formato YAML) che dice cosa contiene un progetto e a che punto è |

---

## 10. Riassunto in 5 frasi

1. **Claude Code** è un amico programmatore che vive nel terminale.
2. Lavora con una **squadra di 8 robot specializzati**.
3. Ognuno usa **strumenti magici (skill)** per fare il suo lavoro.
4. Quando vuoi un nuovo progetto, lancia **`/concept-to-code`** e segui le istruzioni.
5. **Mai cancellare cose senza pensarci** e **chiedi sempre** se non sei sicuro.

---

## 11. Cose buffe da sapere

- Il nostro sistema sa che **gli script bash girano su una versione del 2007** (bash 3.2 di Mac), quindi quando scrive codice bash sta attento a non usare cose nuove. È come scrivere a una nonna in dialetto.
- I robot lavorano **in parallelo** (tipo fino a 4 contemporaneamente): l'orchestrator può mandare 4 robot in 4 finestre diverse a fare cose diverse, e poi raccoglie tutti i risultati. È come avere 4 cuochi che cucinano 4 piatti diversi nella stessa cucina.
- Quando un robot sbaglia, **non si nasconde**: te lo dice. Per esempio se gli chiedi di cancellare un file importante, dice "no, fammi sapere se sei sicuro".
- Ogni tanto **Anthropic** (la ditta che fa Claude) aggiorna i robot e diventano più bravi. Il sistema dietro è studiato per non rompersi con gli aggiornamenti.

---

## 12. Cosa fare domani

Se questa è la tua prima volta:

1. **Apri il terminale** e scrivi `claude` per chiamare l'amico-Claude
2. Chiedigli "**aiutami a fare un piccolo programma in Python che mi dice se un numero è pari o dispari**"
3. Guarda cosa fa
4. Quando hai finito quel programma, prova con `**/concept-to-code**` per qualcosa di più complicato

E ricorda: **non c'è niente di magico**. È tutto codice e file. Se rompi qualcosa, di solito si può aggiustare. L'importante è **chiedere**, **controllare**, e **divertirsi**.

---

*Questa guida è la versione "facile" del documento tecnico `vibe-coding-system.md`. Se un giorno vorrai i dettagli completi, quello è il file da leggere — ma non prima dei 16 anni, fa venire mal di testa anche agli adulti.*
