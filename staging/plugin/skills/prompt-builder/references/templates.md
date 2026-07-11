# Scheletri per ambiente target

Leggi solo la sezione dell'ambiente scelto. Gli scheletri mostrano la struttura: riempi solo le parti che il caso richiede, elimina il resto. Le sezioni tra [ ] sono opzionali.

## A. claude.ai (chat o Progetti)

Prompt conversazionale, markdown leggero, niente XML pesante salvo input incollati.

```
[Ruolo: una riga, solo se cambia il comportamento]

## Obiettivo
[Cosa produrre, verbo d'azione + oggetto + perimetro]

## Contesto
[Dominio, retroscena, cosa sa già il lettore]

## Istruzioni
1. [passo o regola]
2. [...]

## Formato output
[Struttura, lunghezza, lingua dell'output]

[## Vincoli
- cosa non fare]

[## Esempio
input → output ideale]

[--- Se il prompt riceve testo incollato: ---
<input>
{{TESTO}}
</input>]
```

Per le istruzioni personalizzate di un Progetto claude.ai: stessa struttura ma formulata come comportamento permanente ("Ogni volta che ricevi X, fai Y"), non come task singolo.

Note di costruzione per claude.ai:

- Se una regola del prompt è stabile e ricorrente (ruolo, tono, glossario, formato), proponi di spostarla al livello giusto invece di ripeterla a ogni messaggio: istruzioni di profilo (valgono in tutte le chat), istruzioni di Progetto (valgono in quel flusso di lavoro), skill (comportamento attivabile a richiesta). Il prompt per-messaggio porta solo ciò che è specifico del task.
- [Se l'output desiderato è un artifact: dichiarane il tipo (documento, tool interattivo, diagramma, checklist) invece di lasciarlo dedurre.]
- [Se il prompt lancia una ricerca approfondita (Research): esplicita "usa lo strumento di ricerca per...", i requisiti di qualità delle fonti e la struttura dell'output; con connettori attivi indica la fonte interna ("recupera il contesto rilevante da [fonte]"). Avvisa l'utente che la ricerca consuma i limiti d'uso più rapidamente di una chat normale.]

## B. API — system prompt di produzione

Rigore massimo: XML, variabili, guardrail. Il system prompt definisce il comportamento; l'input utente arriva nel turno user.

```
Sei [ruolo]. [Missione in una frase.]

<istruzioni>
1. [regola operativa]
2. [...]
</istruzioni>

<contesto>
[Dominio, vincoli di business, definizioni]
</contesto>

<formato_output>
[Schema esatto. Per JSON: campi, tipi, esempio. "Rispondi SOLO con..."]
</formato_output>

<guardrail>
- Se l'informazione manca nell'input: [comportamento esplicito]
- [Altri divieti]
</guardrail>

[<esempi>
<esempio>
<input_esempio>...</input_esempio>
<output_esempio>...</output_esempio>
</esempio>
</esempi>]
```

Turno user del template: `<input_utente>{{VARIABILE}}</input_utente>` + eventuale domanda fissa. Chiudi la consegna con l'elenco delle variabili `{{...}}`. Per output JSON metti nel system prompt: "Rispondi SOLO con JSON valido conforme allo schema, nessun testo prima o dopo; inizia la risposta con {". Non suggerire il prefill del turno assistant: non è più supportato dai modelli Claude 4.6 e successivi (errore 400).

## C. Claude Code

Tre sotto-varianti: chiedi quale, se non chiara.

**C1. Prompt di task (da incollare in chat):** come lo scheletro A, ma aggiungi sempre: percorsi file rilevanti, comandi di verifica ("esegui i test con `...` e correggili prima di dichiarare finito"), definizione di fatto ("il task è completo quando...").

**C2. Sezione CLAUDE.md (comportamento permanente del progetto):** regole brevi, imperative, senza narrativa. Struttura tipica: stack e convenzioni / comandi build-test / regole di stile / cosa non toccare. Ogni riga è un contratto: niente riempitivi.

**C3. Comando o agente (.md con frontmatter):** file con frontmatter YAML (`name`, `description` per il triggering) + corpo con workflow a passi. Per la description vale: dichiarare QUANDO usarlo con frasi trigger concrete, non solo cosa fa.

## D. Cowork

Regola documentata prima del wording: in Cowork il divario tra output mediocre e ottimo non sta quasi mai nella formulazione del prompt, ma nel contesto fornito (cartella, file, connettori). Il prompt deve dichiarare gli input prima di rifinire le frasi.

Come lo scheletro A più questi elementi specifici:

1. **Deliverable e formato file attesi**, con nome file se conta e dove salvarlo.
2. **Input dichiarati:** cartella di lavoro dedicata e perimetrata al task (non una directory ampia "per sicurezza"), file specifici, connettori da usare o evitare ("cerca sul web prima di scrivere", "non toccare i file fuori dalla cartella X").
3. **Definizione di fatto verificabile:** "il task è completo quando..." (copertura, riconciliazioni, sezioni obbligatorie). Senza, l'output non è controllabile in 15 secondi.
4. **Checkpoint e politica d'azione:** dove Claude deve fermarsi per approvazione ("prima di generare il file, mostrami la struttura e attendi OK") e se di default deve procedere da solo o proporre un piano. Conferma esplicita per azioni distruttive o difficilmente reversibili (cancellazioni, sovrascritture, invii).
5. **Comportamento se bloccato:** "se un file è illeggibile, segnalalo e continua con il resto". Per task lunghi: chiedi una nota di avanzamento (es. `progress.md`) aggiornata durante il lavoro.
6. **Contesto durevole nel posto giusto:** la memoria di Cowork vale solo dentro i progetti, non tra sessioni singole. Ciò che deve persistere va nelle istruzioni (globali, di progetto o di cartella) o ripetuto nel brief, mai dato per ricordato.
7. [Se il task tocca app senza connettore, Claude passerà per browser o schermo (computer use): prompt più specifico e perimetrato del solito, priorità dichiarata connettori → browser → schermo, task semplici prima, mai app con dati sensibili (banche, sanità, credenziali).]

## E. Altro LLM (generico)

Scheletro A senza assunzioni su funzioni Claude-specifiche (niente riferimenti a tag XML come garanzia, niente prefill). Regole di struttura e few-shot valgono ovunque; specifica la lingua dell'output in modo esplicito, i modelli non-Claude tendono più spesso a scivolare verso l'inglese.
