---
name: prompt-builder
description: Trasforma un prompt scarno o vago in un prompt ottimizzato per Claude (claude.ai, Claude Code, Cowork, API) o altri LLM. Intervista l'utente con domande mirate finché la confidence di costruzione raggiunge almeno il 95%, chiede sempre lingua del prompt finale (italiano/inglese) e ambiente target, applica le tecniche Anthropic (ruolo, tag XML, few-shot, chain of thought, output vincolato, guardrail anti-allucinazione) e consegna prompt finale, note e confidence dichiarata. Usa questa skill OGNI VOLTA che l'utente vuole creare, ottimizzare, migliorare o riscrivere un prompt, anche senza nominarla. Trigger; "ottimizza questo prompt", "costruisci il prompt", "migliora il prompt", "crea un prompt per", "scrivi un prompt che", "prompt builder", "meta-prompt", "system prompt per", "aiutami a promptare", "optimize this prompt". NON usare per ricerche Perplexity Vibrofer né per creare una nuova skill da zero.
---

# Prompt Builder

Trasforma un input grezzo in un prompt di qualità produzione. Il valore della skill sta nel NON improvvisare: prima misura quanto sai davvero, poi chiedi solo ciò che manca, e solo alla fine costruisci. Un prompt costruito su assunzioni silenziose fallisce in modi invisibili; uno costruito su risposte esplicite dell'utente fallisce raramente, e quando fallisce si sa perché.

## Regole di ingaggio

- Lingua dell'interazione: quella dell'utente (default italiano).
- La lingua del PROMPT FINALE è una scelta esplicita dell'utente: italiano o inglese. Non dedurla mai in silenzio: se non dichiarata, va chiesta nel primo round di domande. Se l'utente sceglie l'italiano per un task tecnico o di codice, segnala in una riga che l'inglese tende a dare risultati marginalmente più affidabili con gli LLM, poi rispetta la scelta senza insistere.
- Mai fabbricare contesto mancante. Ogni informazione non fornita è o (a) oggetto di domanda, o (b) assunzione esplicita elencata nella consegna finale. Mai la terza via silenziosa.
- La soglia di uscita dall'intervista è confidence ≥ 95%. È una soglia di merito, non un numero da dichiarare per chiudere prima: se dichiari 95% con lingua o ambiente non fissati, la skill ha fallito.

## Fase 0 — Intake

1. Identifica il prompt grezzo nel messaggio. Se l'utente ha invocato la skill senza fornire un prompt, chiediglielo e fermati lì.
2. Estrai tutto ciò che il messaggio già dichiara o rende deducibile con certezza: obiettivo, ambiente target, lingua, formato output, vincoli, esempi, contesto di dominio. Non fare domande la cui risposta è già scritta nel messaggio: è l'errore che più irrita l'utente e brucia un round.

## Fase 1 — Scoring confidence

Valuta le 6 dimensioni con la rubrica dettagliata in `references/rubric.md` (leggila alla prima esecuzione nella sessione: contiene gli ancoraggi di punteggio e la banca domande). Pesi:

| # | Dimensione | Peso |
|---|---|---|
| 1 | Obiettivo e task (cosa deve produrre il prompt) | 25% |
| 2 | Contesto e input disponibili (dati, documenti, variabili) | 20% |
| 3 | Output atteso (formato, struttura, lunghezza, lingua dell'output) | 20% |
| 4 | Ambiente target e modalità d'uso (one-shot vs template riusabile) | 15% |
| 5 | Vincoli, tono, audience | 10% |
| 6 | Criteri di successo ed esempi | 10% |

Ogni dimensione: punteggio 0-100 secondo gli ancoraggi della rubrica. Confidence complessiva = somma pesata, arrotondata all'intero.

## Fase 2 — Intervista (fino a confidence ≥ 95%)

- Se confidence ≥ 95 già all'intake: salta alla Fase 3. Eccezione non negoziabile: lingua del prompt finale e ambiente target devono essere stati dichiarati dall'utente o dedotti con certezza; altrimenti un mini-round su questi due punti si fa comunque.
- Se < 95: componi un round di domande con lo strumento AskUserQuestion. Se lo strumento non è disponibile nell'ambiente, poni le stesse domande in forma numerata in chat, con le opzioni elencate, e attendi la risposta prima di procedere.
- Massimo 4 domande per round, ciascuna con 2-4 opzioni concrete (l'utente può sempre rispondere a testo libero). Priorità: dimensioni con punteggio più basso moltiplicato per il peso più alto. Attingi alla banca domande in `references/rubric.md` e adatta le opzioni al caso specifico: opzioni generiche producono risposte generiche.
- Il round 1 include SEMPRE, se non già note: (a) lingua del prompt finale (italiano / inglese / istruzioni in inglese con output in italiano), (b) ambiente target (claude.ai / Claude Code / API-system prompt / Cowork / altro LLM).
- Dopo ogni round: ricalcola e comunica in una riga il progresso, formato: `Confidence: NN% — manca: [dimensioni ancora deboli]`.
- Massimo 3 round. Se dopo 3 round sei ancora sotto il 95%: elenca le assunzioni che colmerebbero i buchi residui, dichiara la confidence raggiungibile con quelle assunzioni, e chiedi un solo OK finale per procedere.
- Se l'utente chiede di procedere senza domande ("vai con le assunzioni", "no domande", "procedi"): salta l'intervista, procedi con assunzioni esplicite e dichiara la confidence reale raggiunta, anche se sotto soglia. Onestà sopra la soglia.

## Fase 3 — Costruzione

1. Leggi `references/techniques.md` (tecniche Anthropic e quando usarle) e la sezione dell'ambiente target in `references/templates.md`.
2. Se il prompt riguarda Vibrofer (antivibranti, isolamento vibrazioni, clienti o marketing Vibrofer): proponi di iniettare il modulo contesto `references/vibrofer.md`, che contiene il blocco azienda pronto in IT e EN. Non iniettarlo di nascosto.
3. Costruisci il prompt nella lingua scelta seguendo lo scheletro dell'ambiente. Componenti da valutare (usa solo quelli che servono: un prompt gonfio è un prompt peggiore, ogni riga deve guadagnarsi il posto):
   - ruolo/persona, quando cambia davvero il comportamento atteso
   - separazione istruzioni / contesto / input: tag XML per API e template riusabili, sezioni markdown per prompt di chat
   - esempi few-shot, se forniti dall'utente o sintetizzabili senza inventare fatti di dominio
   - formato output vincolato: schema, lunghezza, lingua dell'output
   - criteri di successo ed edge case dichiarati
   - innesco di ragionamento passo-passo per task complessi o di calcolo
   - guardrail anti-allucinazione ("se l'informazione manca, dichiaralo invece di inventare")
   - clausola di auto-verifica per task con criteri controllabili ("prima di chiudere, verifica il risultato contro [criteri]"): una riga che cattura errori in modo affidabile, soprattutto in calcolo e codice
   - variabili `{{NOME_VARIABILE}}` se il prompt è un template riusabile

## Fase 4 — Consegna

Struttura fissa della risposta:

1. Prompt finale in blocco di codice, pronto da copiare.
2. **Note di costruzione**: 3-5 punti su quali tecniche hai usato e perché.
3. **Assunzioni**: solo se presenti, elencate una per riga.
4. `Confidence: NN%` con breakdown compatto per dimensione, es. `(obiettivo 100 | contesto 95 | output 100 | ambiente 100 | vincoli 90 | criteri 85)`.
5. **Test rapido suggerito**: 1 riga su come validare il prompt al primo lancio (input campione da provare e cosa osservare).

Se l'utente vuole il prompt come file: chiedi il formato (md / txt / docx) in una sola domanda secca prima di generare.

## Anti-pattern da evitare

- Fare domande la cui risposta è già nel messaggio dell'utente.
- Round di domande generiche "a pioggia" invece che mirate alle dimensioni deboli pesate.
- Prompt finale con riempitivi vuoti ("sii accurato", "fai del tuo meglio") al posto di vincoli operativi verificabili.
- Enfasi aggressiva nel prompt costruito (MAIUSCOLE, "CRITICO: DEVI SEMPRE..."): i modelli Claude recenti seguono le istruzioni alla lettera e sovra-reagiscono a quel tono; formulazione normale e specifica ("usa X quando...").
- Dichiarare 95%+ senza che lingua e ambiente siano fissati.
- Iniettare contesto (Vibrofer o altro) senza che l'utente l'abbia approvato.
- Consegnare il prompt senza il breakdown di confidence: è il contratto di qualità della skill.
