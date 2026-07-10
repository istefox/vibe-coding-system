# Rubrica di confidence e banca domande

Due sezioni: (1) ancoraggi di punteggio per dimensione, (2) banca domande pronte per AskUserQuestion. La confidence complessiva è la somma pesata dei punteggi (pesi in SKILL.md).

## 1. Ancoraggi di punteggio

Scala unica per tutte le dimensioni:

| Fascia | Significato |
|---|---|
| 95-100 | Dichiarato esplicitamente dall'utente, senza ambiguità residue |
| 75-94 | Deducibile con alta certezza dal messaggio o dal contesto di sessione; una sola lettura possibile |
| 50-74 | Inferibile ma con più letture plausibili; servirebbe conferma |
| 25-49 | Solo indizi vaghi; qualunque scelta sarebbe un'assunzione sostanziale |
| 0-24 | Assente |

Criteri specifici per dimensione:

**D1 Obiettivo e task (25%).** A 95+: verbo d'azione + oggetto + perimetro chiari (es. "estrarre i dati di targa da email clienti e restituirli normalizzati"). Sotto 75 se il task è un tema e non un'azione ("qualcosa sui report").

**D2 Contesto e input (20%).** A 95+: si sa esattamente cosa riceverà il prompt in input (tipo di documento, dati, variabili) e il dominio è chiaro. Sotto 50 se non si sa nemmeno se il prompt riceverà un input o lavorerà a vuoto.

**D3 Output atteso (20%).** A 95+: formato (testo libero / markdown / JSON / tabella / file), struttura, ordine di grandezza della lunghezza e lingua dell'output sono fissati. La lingua dell'OUTPUT può differire dalla lingua del PROMPT: vanno distinte.

**D4 Ambiente target e modalità d'uso (15%).** A 95+: ambiente dichiarato (claude.ai / Claude Code / API / Cowork / altro LLM) E modalità d'uso chiara (one-shot vs template riusabile con variabili). L'ambiente cambia lo scheletro: senza, non si supera 50.

**D5 Vincoli, tono, audience (10%).** A 95+: si sa per chi è l'output, con che registro, e cosa NON deve fare. Per task meccanici (estrazione dati, conversione) questa dimensione può partire alta di default: l'audience è irrilevante. Usa giudizio: non chiedere il tono per un parser JSON.

**D6 Criteri di successo ed esempi (10%).** A 95+: c'è un modo dichiarato per giudicare un buon output (esempio positivo, checklist, caso limite). Per task semplici un criterio implicito ovvio vale 75-94 senza domande.

Nota d'uso: le fasce alte di D5 e D6 "di default" per task semplici esistono per evitare interviste pedanti. Il 95% complessivo deve restare raggiungibile in 1 round per prompt medi e 0 round per prompt già ben specificati.

## 2. Banca domande

Adatta sempre etichette e opzioni al caso concreto. Le domande sotto sono scheletri collaudati, non testo da incollare cieco. Massimo 4 domande per round: scegli quelle con (100 - punteggio) × peso più alto.

### Round 1 obbligatorie (se non già note)

**Lingua del prompt finale** (header: "Lingua")
- Italiano
- Inglese (consigliato per task tecnici/codice: marginalmente più affidabile)
- Istruzioni in inglese, output forzato in italiano

**Ambiente di destinazione** (header: "Ambiente")
- claude.ai (chat / Progetti)
- Claude Code (CLAUDE.md, comando, agente)
- API (system prompt di produzione)
- Cowork (task agentico su file e strumenti)

Nota: "altro LLM" non ha un'opzione dedicata perché AskUserQuestion accetta al massimo 4 opzioni e Cowork e altro LLM richiedono scheletri diversi (D vs E di templates.md): tenerli fusi in un'opzione sola rendeva la risposta inutilizzabile. L'utente che punta a un LLM non-Claude risponde a testo libero tramite l'opzione "Altro", sempre disponibile nello strumento: in quel caso usa lo scheletro E.

### D1 Obiettivo

"Qual è il risultato concreto che il prompt deve produrre?" (header: "Obiettivo")
- Analisi o report su dati/documenti
- Generazione di contenuto (testo, email, post)
- Estrazione/trasformazione dati
- Codice o automazione

"Il prompt deve svolgere il task o guidare Claude ad assisterti mentre lo svolgi tu?" (header: "Ruolo Claude") — utile quando l'obiettivo è ambiguo tra esecuzione e coaching.

### D2 Contesto e input

"Cosa riceverà in input il prompt a ogni utilizzo?" (header: "Input")
- Nessun input: lavora da istruzioni
- Testo incollato dall'utente (email, documento, dati)
- File allegati
- Variabili compilate a mano (template)

"C'è contesto di dominio che il prompt deve conoscere in partenza?" (header: "Contesto") — opzioni da costruire sul caso; per temi Vibrofer includi l'opzione "Inietta modulo contesto Vibrofer".

### D3 Output

"In che formato deve uscire il risultato?" (header: "Formato")
- Testo libero / prosa
- Markdown strutturato (sezioni fisse)
- JSON o tabella (dati macchina-leggibili)
- File (docx, xlsx, ...)

"Lunghezza attesa dell'output?" (header: "Lunghezza")
- Sintetico (poche righe)
- Una pagina circa
- Documento esteso
- Nessun vincolo

### D4 Modalità d'uso

"Uso singolo o template riusabile?" (header: "Riuso")
- One-shot: lo lancio una volta
- Template riusabile con variabili {{...}} da compilare ogni volta
- System prompt permanente (definisce comportamento stabile)

### D5 Vincoli, tono, audience

"Chi leggerà l'output?" (header: "Audience")
- Io stesso (uso interno)
- Clienti / esterni (registro formale)
- Tecnici del settore
- Pubblico generico

"Cose da NON fare?" (header: "Divieti") — opzioni sul caso: es. "niente gergo", "mai inventare dati", "non superare N parole", "nessuna emoji".

### D6 Criteri di successo

"Hai un esempio di output ideale (o sbagliato) da usare come riferimento?" (header: "Esempi")
- Sì, lo incollo dopo
- No, ma posso descrivere cosa rende buono l'output
- No: usa il tuo giudizio e proponi tu i criteri

## 3. Calcolo e comunicazione

Dopo ogni round: ricalcola i punteggi delle dimensioni toccate dalle risposte, somma pesata, arrotonda. Comunica: `Confidence: NN% — manca: [dimensioni sotto 90]`. A ≥ 95: dichiara chiusa l'intervista e passa alla costruzione. Il breakdown finale va sempre nella consegna (Fase 4).
