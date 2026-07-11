# Tecniche di prompt engineering (fonte: documentazione Anthropic)

Riferimento: documentazione Anthropic, sezione "Prompt engineering" (pagina "Prompting best practices") e blog ufficiale claude.com. Ogni tecnica ha un costo (lunghezza, rigidità): usala solo se il task la giustifica. Il contesto è una risorsa finita ("context rot": più token a basso segnale, peggior richiamo di ciò che conta): ogni riga del prompt deve guadagnarsi il posto.

## 1. Chiarezza e direttezza (sempre)

Il fondamento. Istruzioni esplicite, verbi d'azione, zero ambiguità. Test mentale: "un collega nuovo, competente ma senza contesto, capirebbe cosa fare leggendo solo questo?" Se serve conoscenza implicita, scrivila nel prompt. Dichiarare anche il perché di una regola migliora l'aderenza ("rispondi in max 5 righe perché il testo finirà in una notifica").

Quattro regole documentate in aggiunta:

- **Ambizione esplicita.** Se serve un risultato sopra la media, chiedilo nel prompt ("vai oltre le basi", "includi tutte le funzionalità rilevanti", "implementazione completa"): il modello non deduce l'ambizione da un prompt vago.
- **Passi numerati** quando l'ordine o la completezza dei passaggi contano; prosa per tutto il resto.
- **Azione, non suggerimento.** I modelli recenti seguono le istruzioni alla lettera: "puoi suggerire modifiche?" produce suggerimenti, non modifiche. Se il prompt deve far agire, usa l'imperativo ("correggi", "riscrivi", "genera").
- **Tono normale, niente urla.** L'enfasi aggressiva ("CRITICO: DEVI SEMPRE...") era una stampella per modelli vecchi; sui modelli Claude recenti causa sovra-reazione e comportamenti che scattano troppo spesso. Scrivi "usa questo approccio quando..." al posto di "DEVI ASSOLUTAMENTE...".

## 2. Ruolo / persona (system prompt o apertura)

Assegna un ruolo quando cambia davvero il comportamento: "Sei un ingegnere acustico senior che scrive per uffici tecnici" produce lessico e priorità diverse da un prompt neutro. Basta una frase. Non assegnarlo per task meccanici (parsing, conversioni): è rumore. Non sovra-vincolare il ruolo ("massimo esperto mondiale che non sbaglia mai" peggiora l'output): spesso è più efficace dichiarare la prospettiva desiderata ("analizza dal punto di vista del rischio di fornitura") che costruire un personaggio. Nell'API il ruolo va nel parametro `system`; in chat, nella prima riga.

## 3. Tag XML per struttura

Quando il prompt mescola istruzioni, contesto e dati di input, separali con tag: `<istruzioni>`, `<contesto>`, `<input>`, `<esempi>`, `<formato_output>`. Claude è addestrato a rispettarli. Indispensabili in system prompt API e template riusabili (il testo variabile finisce dentro un tag dedicato, es. `<email_cliente>{{EMAIL}}</email_cliente>`); in prompt di chat brevi bastano sezioni markdown: i modelli recenti capiscono bene la struttura anche senza XML.

## 4. Esempi few-shot (multishot)

La tecnica con il miglior rapporto resa/sforzo per formati di output non banali. Scala progressiva documentata: parti da 1 esempio; per formati critici 3-5 esempi diversi tra loro danno i risultati migliori. Regole: esempi realistici, rilevanti (rispecchiano il caso d'uso reale) e diversificati (coprono i casi limite senza introdurre pattern indesiderati), racchiusi in `<esempio>` (più esempi dentro `<esempi>`), mai in conflitto con le istruzioni scritte. Se l'utente ha un esempio di output ideale, usalo; se no, sintetizzane uno e fallo validare. Si può anche chiedere a Claude di valutare gli esempi per rilevanza e diversità, o di generarne altri a partire dal set iniziale. Non inventare fatti di dominio dentro gli esempi.

## 5. Ragionamento passo-passo (chain of thought)

Per task di analisi, calcolo o decisione multi-fattore. Preferenza documentata: un'istruzione generale ("ragiona a fondo sul problema prima di rispondere") produce spesso ragionamenti migliori di una scaletta di passi prescritta a mano, perché il ragionamento del modello supera di frequente il piano che gli scriveresti. Usa la variante strutturata ("Ragiona per passi dentro <ragionamento>, poi dai la risposta dentro <risposta>") quando chi consuma il prompt deve mostrare solo la risposta. Su claude.ai il ragionamento esteso si attiva dalle impostazioni: quando disponibile è in genere preferibile al CoT manuale, che resta il fallback (es. piani senza extended thinking). Non usarlo per task banali: allunga output e latenza senza guadagno.

## 6. Formato output vincolato

Dichiara sempre: struttura (schema JSON con nomi campo, template markdown con sezioni fisse, tabella con colonne nominate), lunghezza attesa in numeri ("max 200 parole", "10 righe": gli aggettivi vaghi come "breve" vengono interpretati in modo incoerente), lingua dell'output. Tre leve documentate:

- **In positivo.** Di' cosa fare, non solo cosa evitare: "scrivi in paragrafi di prosa fluida" funziona meglio di "niente markdown". Se l'intervista ha raccolto divieti, traducili in vincoli positivi dove possibile.
- **Style matching.** La formattazione del prompt influenza quella dell'output: un prompt pieno di markdown genera output pieno di markdown. Allinea lo stile del prompt allo stile desiderato per l'output.
- **Per JSON.** "Rispondi SOLO con JSON valido conforme allo schema, nessun testo prima o dopo; inizia la risposta con {". Nota: il prefill del turno assistant non è più supportato dai modelli Claude 4.6 e successivi (la richiesta restituisce errore 400): non suggerirlo; l'istruzione esplicita qui sopra lo sostituisce.

## 7. Guardrail anti-allucinazione

Dai a Claude una via d'uscita esplicita: "Se un'informazione non è presente nell'input, scrivi 'dato non disponibile' invece di stimarla". Per compiti su documenti: "Cita il passaggio esatto su cui basi ogni affermazione"; per verifiche forti aggiungi "se non trovi una citazione a supporto, ritratta l'affermazione". Senza via d'uscita dichiarata, il modello tende a riempire i buchi.

## 8. Auto-verifica finale

Per task con criteri controllabili, chiudi il prompt con una clausola di verifica: "Prima di terminare, verifica il risultato contro [criteri]". Costa una riga e cattura errori in modo affidabile, soprattutto in calcolo e codice. Rende al massimo quando i criteri citati sono gli stessi dichiarati nella sezione criteri di successo del prompt.

## 9. Variabili e template riusabili

Per prompt da riusare: placeholder `{{NOME_VARIABILE}}` in MAIUSCOLO, ciascuno dentro il proprio tag XML, ed elenco finale delle variabili con una riga di spiegazione ciascuna. Così il template è auto-documentato.

## 10. Prompt lunghi e documenti (long context)

Con input voluminosi (indicativamente 20k+ token: PDF lunghi, più documenti, report incollati): documenti IN ALTO, istruzioni e domanda IN FONDO al prompt. Nei test Anthropic la query in fondo migliora la qualità della risposta fino a ~30% su input multi-documento complessi. Documenti multipli: ciascuno in `<documento indice="N">` con sottotag per contenuto e fonte. Chiedi prima l'estrazione delle citazioni rilevanti, poi la risposta: il quote grounding taglia il rumore del resto del documento.

## 11. Concatenamento (prompt chaining)

Se il task richiede due mestieri diversi (es. estrarre dati E scrivere un report elegante), meglio due prompt in catena che uno ibrido. Il pattern di catena più comune e documentato è l'auto-correzione: bozza → revisione contro criteri espliciti → rifinitura. Segnala all'utente quando il suo prompt scarno nasconde una catena: consegnare due o tre prompt collegati è un esito legittimo della skill.

## Scelta della lingua

L'inglese tende a dare risultati marginalmente più affidabili su task tecnici, di codice e con output strutturato (più dati di addestramento, terminologia nativa). L'italiano è pari per contenuti destinati a lettori italiani e per sfumature di registro locali. Terza via spesso ottima: istruzioni in inglese + vincolo "Write all output in Italian". La scelta resta dell'utente: la skill la chiede, consiglia una volta, non insiste.
