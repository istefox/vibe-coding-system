# Skill `design-brainstorm` — Design Spec

**Status:** implementato — 2026-05-21
**ADR:** `docs/architecture/ADR-0008-concept-to-code-workflow-v2-brainstorm.md`
**Plan:** `docs/superpowers/plans/2026-05-21-concept-to-code-workflow-v2.md`
**Confidence:** vedi report in chat (non nel deliverable).

---

## 0. Scopo in una frase

`design-brainstorm` esplora — in dialogo strutturato con l'utente, con tecniche di
ideazione esplicite — la **metodologia applicativa** ("come" risolvere il problema) e le
**idee applicative nuove** ("cosa di nuovo" è possibile), PRIMA che l'architettura sia
fissata, e ritorna un brief `BRAINSTORM.md` di 2-4 alternative con trade-off. Non estrae
requisiti, non scrive SPEC né plan.

---

## 1. Posizionamento e differenze nette dalle skill esistenti

Questa sezione DEVE comparire (sintetizzata) anche nel body dello SKILL.md, perché la
confusione di ruolo è il rischio numero uno.

| Skill | Risponde a | Output | Stato |
|---|---|---|---|
| `interview-driver` | **What** — quali requisiti | `SPEC.md` (requisiti, scope, DoD) | foglia del chain, Step 1 |
| **`design-brainstorm`** | **How + What-new** — quali approcci, quali idee nuove | `BRAINSTORM.md` (alternative + trade-off) | foglia del chain, gate 1b |
| `architect` (agent) | **Decision** — quale approccio si adotta | ADR + plan | Step 2 |
| `superpowers:brainstorming` | spec + plan completi | scrive spec, invoca writing-plans | **stato terminale** |

**vs `interview-driver`:** l'interview cattura *cosa* deve fare il sistema (requisiti,
scope, edge case, Definition of Done). `design-brainstorm` assume i requisiti già noti
(SPEC esiste o è appena stato scritto) e esplora *come* realizzarli e *cosa di nuovo* è
abilitato. Domanda-tipo interview: "deve supportare login social?". Domanda-tipo
brainstorm: "qual è il modo più semplice possibile di gestire le sessioni — e come lo
farebbe un sistema bancario vs un videogioco?".

**vs `superpowers:brainstorming`:** quella skill è progettata come stato *terminale*:
scrive lo spec e invoca `writing-plans`. Dentro il chain concept-to-code questo
**confliggerebbe** — il chain possiede già Step 2 (architettura → ADR + plan). Quindi
`superpowers:brainstorming` NON va invocata dal chain. `design-brainstorm` è
deliberatamente **non terminale**: non scrive spec, non invoca plan, ritorna solo un
brief strutturato all'orchestrator, che prosegue con lo Step 2 architect. (Stefano può
usare `superpowers:brainstorming` separatamente, fuori dal chain, quando vuole il flusso
spec→plan diretto.)

**vs `architect` (agent):** l'architect *decide e formalizza* (sceglie un approccio,
scrive l'ADR, motiva). `design-brainstorm` *diverge ed esplora* (genera alternative,
non sceglie). Il brainstorm alimenta l'architect con un ventaglio discusso, riducendo il
monologismo della decisione architetturale.

---

## 2. Filosofia di ideazione (perché tecniche esplicite)

Il brainstorming non strutturato converge troppo presto sulla prima idea plausibile
(anchoring) e resta dentro le assunzioni ereditate. La skill impone **divergenza prima
di convergenza**: genera deliberatamente alternative lontane prima di valutarle. Le
tecniche sotto sono i meccanismi per forzare la divergenza. La skill non le applica
tutte ogni volta: ne **seleziona 3-4** in base alla natura del problema (vedi §4
Routing), per evitare un interrogatorio meccanico.

Principio operativo: **una tecnica → una o due domande mirate con `AskUserQuestion` →
sintesi → tecnica successiva.** Mai un monologo, mai uno scarico di tutte le tecniche in
un colpo.

---

## 3. Le otto tecniche di ideazione (catalogo metodologico)

Per ciascuna: scopo, quando usarla, prompt-template di domanda (in italiano, multiple
choice dove possibile), output che alimenta il brief. Le tre **cardine** (sempre
considerate per prime) sono marcate ★.

### 3.1 ★ First-principles decomposition

**Scopo:** scomporre il problema ai suoi elementi irriducibili e ricostruire la
soluzione senza ereditare assunzioni di "come si fa di solito".

**Quando:** sempre per prima su problemi dove esiste una "soluzione ovvia/di default"
che rischia di essere accettata acriticamente. È la tecnica anti-anchoring fondamentale.

**Procedura:**
1. Riformula il problema come domanda di scopo: "qual è il risultato irriducibile che
   serve davvero?" (non la soluzione, il bisogno).
2. Elenca i 3-5 fatti/vincoli che sono *fisicamente o logicamente veri* (non
   convenzioni).
3. Ricostruisci una soluzione partendo solo da quei fatti.

**Domanda-template (`AskUserQuestion`):**
```
Riduciamo all'osso. Di questo problema, qual è il risultato irriducibile?
  [A] <riformulazione orientata al dato>
  [B] <riformulazione orientata all'azione utente>
  [C] <riformulazione orientata al vincolo di business>
  [D] Altro (scrivilo)
```

**Output al brief:** la sezione "Problema riformulato" e l'elenco assunzioni → §3.5.

### 3.2 ★ Analogie cross-dominio

**Scopo:** importare pattern collaudati da domini lontani per rompere la fissità
funzionale. "Come risolverebbe questo flusso un dominio X completamente diverso?"

**Quando:** quando il problema è un flusso/processo (orchestrazione, stato, code,
concorrenza, fiducia) — domini maturi hanno già risolto varianti del problema.

**Domini di riferimento da proporre (sceglierne 2-3 pertinenti):**
- **Videogiochi:** game loop, state machine, ottimismo/rollback, sistemi a eventi.
- **Banca / finanza:** ledger append-only, riconciliazione, idempotenza, audit trail.
- **Sistema biologico:** ridondanza, degradazione graziosa, auto-guarigione, sciami.
- **Logistica / postale:** routing, code prioritarie, tracking, dead-letter.
- **Editoria / redazione:** bozza/revisione/pubblicazione, embargo, versioning.

**Domanda-template:**
```
Come gestirebbe questo flusso un dominio diverso?
  [A] Come un videogioco (game loop / stato ottimistico)
  [B] Come una banca (ledger append-only / idempotenza)
  [C] Come un sistema biologico (degradazione graziosa / ridondanza)
  [D] Come la logistica (routing / dead-letter queue)
```
Dopo la scelta, una domanda di follow-up che traduce l'analogia nel dominio reale.

**Output al brief:** una o più delle "Alternative" (§3.6) nascono spesso da qui.

### 3.3 ★ Inversione (pre-mortem)

**Scopo:** invece di chiedere "come la facciamo funzionare?", chiedere "come
garantiremmo il FALLIMENTO totale di questa feature?" — poi invertire le risposte per
ottenere la lista dei rischi reali e dei requisiti non-funzionali nascosti.

**Quando:** sempre prima di chiudere, come rete di sicurezza; specialmente quando ci
sono dati sensibili, integrazioni esterne, o operazioni distruttive.

**Procedura:**
1. "Elenca 3 modi sicuri per far fallire miseramente questa feature in produzione."
2. Inverti ciascuno → diventa un rischio da mitigare e spesso un requisito implicito.

**Domanda-template:**
```
Pre-mortem. È sei mesi dopo il lancio e la feature è un disastro. Cosa è andato storto?
  [A] Si è rivelata troppo lenta/non scalabile sotto carico reale
  [B] Un edge case ha corrotto i dati / perso lavoro utente
  [C] Nessuno l'ha usata: risolveva il problema sbagliato
  [D] È diventata impossibile da mantenere/estendere
```

**Output al brief:** popola i trade-off "negativi" delle alternative e la sezione rischi
della raccomandazione.

### 3.4 Vincoli forzati (constraint injection)

**Scopo:** un vincolo artificiale estremo forza soluzioni che il pensiero "comodo" non
genererebbe. Spesso la soluzione vincolata è migliore anche senza il vincolo.

**Quando:** quando la prima alternativa è "ovvia e pesante" e si sospetta esista una via
più snella.

**Vincoli-template da iniettare (uno alla volta):**
- "E se avessi **1/10 del tempo**? Cosa taglieresti e cosa resterebbe essenziale?"
- "E se **non potessi usare un database**? Dove vivrebbe lo stato?"
- "E se dovesse **funzionare completamente offline**?"
- "E se dovesse **costare zero in infrastruttura**?"
- "E se dovesse essere **spiegabile a un non-tecnico in 2 minuti**?"

**Domanda-template:**
```
Iniettiamo un vincolo estremo per scovare la versione snella:
  [A] Metà del tempo di sviluppo — cosa resta?
  [B] Nessun database — dove vive lo stato?
  [C] Deve girare offline — cosa cambia?
  [D] Salta questa tecnica
```

**Output al brief:** spesso genera l'alternativa "minimal/snella" del ventaglio.

### 3.5 Assumption-busting

**Scopo:** rendere esplicite le assunzioni implicite e sfidarle una per una. Le
assunzioni invisibili sono il vincolo più forte e meno giustificato.

**Quando:** subito dopo first-principles; produce la sezione "Assunzioni sfidate" del
brief.

**Procedura:**
1. La skill PROPONE 3-5 assunzioni implicite che ha rilevato dallo SPEC/contesto
   (es. "si assume che gli utenti siano online", "si assume un solo tenant", "si assume
   che i dati stiano in memoria").
2. Per ciascuna chiede: "questa assunzione è un vincolo reale o un'abitudine?"

**Domanda-template (una per assunzione, multiple choice):**
```
Assunzione rilevata: "<assunzione>". È un vincolo reale?
  [A] Reale e immutabile (è un requisito vero)
  [B] Probabile ma non verificato (da confermare con dato)
  [C] Abitudine — possiamo sfidarla
```

**Output al brief:** sezione "Assunzioni sfidate" con esito (mantenuta / da verificare /
caduta) per ciascuna.

### 3.6 Esplorazione di alternative genuinamente diverse

**Scopo:** il cuore del brief. Generare **2-4 approcci genuinamente diversi** — non
varianti dello stesso (es. "stesso approccio ma con libreria X vs Y" NON conta come due
alternative). Diversi nell'asse architetturale fondamentale (es. sincrono vs event-driven;
stato centralizzato vs distribuito; build vs buy; batch vs streaming).

**Regola di qualità (DA ENFORCARE nello SKILL.md):** due alternative sono "genuinamente
diverse" solo se cambiano almeno uno tra: il modello dati, il modello di concorrenza/
temporalità, il confine di responsabilità (chi possiede cosa), o il modello di
deployment. Se due "alternative" condividono tutti e quattro, sono una sola alternativa
con due implementazioni → vanno fuse.

**Procedura:**
1. Sintetizza ciò che è emerso da analogie + vincoli + first-principles in 2-4
   candidate.
2. Per ciascuna: nome, descrizione in 2-3 righe, asse di differenza dalle altre.
3. Per ciascuna chiede all'utente di pesare i trade-off (non li decide la skill).

**Domanda-template (per ciascuna alternativa, sui trade-off):**
```
Alternativa <N> — "<nome>". Qual è il trade-off che ti pesa di più?
  [A] Complessità iniziale alta, ma scala meglio
  [B] Semplice subito, ma debito tecnico se cresce
  [C] Dipendenza esterna (buy) vs controllo (build)
  [D] Altro (scrivilo)
```

**Output al brief:** sezione "Alternative" — la più importante.

### 3.7 Idee adiacenti (adjacent possible)

**Scopo:** identificare casi d'uso/feature vicine che emergono naturalmente dal problema
e che potrebbero valere la pena (o, al contrario, segnalare scope creep da escludere
esplicitamente).

**Quando:** verso la fine, dopo le alternative; non per espandere lo scope, ma per
renderlo consapevole.

**Domanda-template:**
```
Risolvendo questo, si aprono naturalmente delle porte vicine. Quale ti interessa annotare?
  [A] <feature adiacente 1 rilevata dal contesto>
  [B] <feature adiacente 2>
  [C] Nessuna ora — annotale solo come "fuori scope, future"
```

**Output al brief:** sezione "Idee adiacenti emerse" (con marcatura in-scope / future /
esplicitamente-escluse).

### 3.8 Prior-art / stato dell'arte (analisi del dominio specifico)

**Scopo:** mentre le analogie cross-dominio (3.2) importano pattern da domini *lontani*,
il prior-art guarda il dominio *vicino*: cosa fanno i prodotti/soluzioni concorrenti
diretti che affrontano lo stesso problema? Serve a generare **idee applicative nuove** per
differenziazione (fare meglio/diverso) ed evitare di reinventare male ciò che esiste già.

**Quando:** quando la feature ha equivalenti noti sul mercato o nel dominio, o quando
l'utente vuole posizionarsi rispetto a soluzioni esistenti. Tecnica di supporto, non
cardine.

**Caveat (importante):** `design-brainstorm` è dialogica, **non fa ricerca web**. Il
prior-art si basa su ciò che l'utente già conosce. Se serve un'analisi competitiva
documentata, la skill lo segnala e raccomanda di delegare al `researcher` agent
(fuori da questa sessione) — NON tenta ricerche che non può fare.

**Procedura:**
1. Chiedi all'utente quali soluzioni/prodotti esistenti conosce per questo problema.
2. Per ognuna: cosa fa bene, cosa fa male, cosa manca.
3. Estrai "spazi vuoti" (cosa nessuno fa bene = opportunità di differenziazione).

**Domanda-template (`AskUserQuestion`):**
```
Conosci soluzioni/prodotti esistenti che affrontano questo problema?
  [A] Sì, e so cosa fanno bene/male (descrivimele)
  [B] Sì, ma vorrei un'analisi competitiva approfondita → delega al researcher
  [C] No / non rilevante — salta questa tecnica
```

**Output al brief:** sezione "Prior-art e spazi di differenziazione" — cosa esiste, cosa
manca, dove c'è opportunità di fare diverso/meglio. Alimenta spesso le "Alternative" (3.6)
e le "Idee adiacenti" (3.7).

---

## 4. Flusso dialogico (orchestrazione delle tecniche)

### 4.1 Routing — quali 3-4 tecniche selezionare

La skill NON applica tutte e sette. Sceglie in base alla natura del problema. Euristica
di routing (incapsulata come guida testuale nello SKILL.md, non come codice):

- **Sempre incluse (cardine ★):** first-principles (3.1), poi assumption-busting (3.5),
  poi inversione/pre-mortem (3.3) come rete di sicurezza finale.
- **Aggiungi analogie cross-dominio (3.2)** se il problema è un *flusso/processo*
  (orchestrazione, stato, concorrenza, fiducia, code).
- **Aggiungi vincoli forzati (3.4)** se la prima soluzione emersa è "ovvia e pesante" o
  se ci sono vincoli di costo/tempo dichiarati.
- **Aggiungi prior-art (3.8)** se la feature ha equivalenti noti sul mercato/dominio o
  se l'utente vuole differenziarsi da soluzioni esistenti.
- **Idee adiacenti (3.7)** sempre come penultimo passo, breve.
- **Alternative (3.6)** sempre come passo di sintesi obbligatorio prima del brief.

Sequenza tipica (5 passi dialogici): first-principles → assumption-busting →
[analogie | vincoli, scelta in base al routing] → alternative (sintesi) → inversione
(pre-mortem sulle alternative) → idee adiacenti → scrittura brief.

### 4.2 Regole di conduzione del dialogo

- **Una domanda alla volta** con `AskUserQuestion`, max 4 opzioni, sempre con un'opzione
  "Altro/scrivilo" o "salta" dove ha senso.
- **Sintetizza dopo ogni risposta** in 1-2 righe prima della domanda successiva (mostra
  all'utente che lo stai ascoltando, evita derive).
- **Non decidere al posto dell'utente** sui trade-off: la skill genera le opzioni e
  pesa i pro/contro, ma la scelta di preferenza resta all'utente. La raccomandazione
  finale è "preliminare" e motivata, non vincolante.
- **Time-box implicito:** se dopo ~6-7 scambi il ventaglio è chiaro, converge al brief.
  Non trascinare.
- **Nessuna fase di requisiti:** se emergono requisiti nuovi (non "come" ma "cosa"),
  annotali nel brief come "da riportare in SPEC" e NON deviare l'interview — non è il
  ruolo di questa skill.

### 4.3 Edge case dialogici

- **L'utente non sa rispondere a una tecnica:** offri l'opzione "salta" e passa alla
  successiva; annota la lacuna nel brief.
- **L'utente ha già un'idea forte:** non assecondare subito; usa inversione +
  assumption-busting su quell'idea per stress-testarla, poi genera almeno 1 alternativa
  di confronto. Una sola alternativa nel brief è un fallimento di qualità.
- **Problema banale (non merita brainstorm):** la skill lo segnala onestamente
  ("questo problema ha una soluzione canonica chiara, il brainstorm aggiunge poco —
  vuoi procedere comunque o andare diretto all'architect?") e lascia decidere.

---

## 5. Contratto di output — `BRAINSTORM.md`

### 5.1 Posizione

`<project-root>/BRAINSTORM.md`. La skill scrive SOLO questo file. NON tocca il manifest
(lo aggiorna l'orchestrator concept-to-code, scrivendo `artifacts.brainstorm`). NON
scrive SPEC, ADR, plan.

### 5.2 Struttura obbligatoria (template in inglese, prosa in italiano)

```markdown
# BRAINSTORM — <topic>

**Data:** YYYY-MM-DD
**Fonte requisiti:** <path SPEC.md, o "requisiti discussi in sessione">
**Tecniche applicate:** <lista delle 3-4 tecniche usate>

## Problema riformulato (first-principles)
<2-4 righe: il bisogno irriducibile, non la soluzione>

## Assunzioni sfidate
- <assunzione 1> — esito: [mantenuta | da verificare | caduta] — <perché>
- <assunzione 2> — ...
(3-5 voci)

## Alternative di approccio
### Alternativa A — <nome>
- **Idea:** <2-3 righe>
- **Asse di differenza:** <dati | concorrenza | confini | deployment>
- **Pro:** <bullet>
- **Contro:** <bullet>
- **Costo/tempo indicativo:** <basso | medio | alto>

### Alternativa B — <nome>
...
(2-4 alternative, genuinamente diverse per la regola §3.6)

## Rischi emersi (inversione / pre-mortem)
- <rischio 1> → mitigazione possibile: <...>
(dai risultati dell'inversione)

## Idee adiacenti emerse
- <idea> — [in-scope ora | future | esplicitamente esclusa]

## Raccomandazione preliminare
<2-4 righe: quale alternativa sembra più promettente e perché — DICHIARATA come
preliminare, da validare dall'architect. NON è una decisione vincolante.>

## Note per l'architect
<cosa l'architect dovrebbe approfondire/decidere; eventuali requisiti nuovi da
riportare in SPEC>
```

### 5.3 Invarianti di qualità del brief (verificabili dall'harness)

- Contiene almeno 2 alternative (`## Alternativa` ricorre >= 2 volte).
- Contiene la sezione "Assunzioni sfidate" non vuota.
- Contiene "Raccomandazione preliminare" con marcatura "preliminare".
- NON contiene blocchi di codice di implementazione (è un brief, non un plan).
- NON è uno SPEC (niente sezione "Requisiti"/"Definition of Done") né un plan (niente
  task TDD): se servono, rimanda al chain.

### 5.4 Come il brief alimenta l'architect (Step 2)

L'orchestrator, in Step 2, include `BRAINSTORM.md` nel dispatch dell'architect come
contesto aggiuntivo (oltre a SPEC.md): l'architect legge le alternative e la
raccomandazione preliminare, e nell'ADR documenta quale ha scelto e perché (riusando la
sezione "Alternative considerate e scartate" dell'ADR template — sinergia diretta:
le alternative del brainstorm diventano le alternative dell'ADR). Quando
`artifacts.brainstorm` è null (gate 1b = n), l'architect opera come oggi.

---

## 6. Frontmatter e struttura file della skill

```yaml
---
name: design-brainstorm
description: This skill should be used when requirements are known (SPEC exists or just
  written) and design APPROACHES and NEW APPLICATION IDEAS must be explored with the user
  BEFORE the architecture is fixed. Uses structured ideation techniques (first-principles,
  cross-domain analogy, inversion/pre-mortem, forced constraints, assumption-busting,
  genuinely-different alternatives, adjacent ideas) via AskUserQuestion, one technique at a
  time. Produces a structured BRAINSTORM.md brief (2-4 alternatives with trade-offs). Does
  NOT extract requirements (that is interview-driver), does NOT write SPEC/plan, does NOT
  invoke writing-plans. Invokable from the concept-to-code chain (brainstorm-gate 1b) and
  standalone. Triggers include "esploriamo gli approcci", "brainstorm di design",
  "/skill design-brainstorm".
---
```

NB: **niente** `disable-model-invocation: true` (memory
`feedback_disable-model-invocation-strong.md`): la skill DEVE essere invocabile dal chain.

Struttura directory:
```
~/.claude/skills/design-brainstorm/
  SKILL.md              # body con: Lingua, When to invoke, Differenze dalle skill,
                        # Le 7 tecniche (catalogo), Flusso dialogico (routing+regole),
                        # Output contract (BRAINSTORM.md template), Coexistence
  tests/run-tests.sh    # self-test harness (structural anchors, vedi §7)
```

Lo SKILL.md NON contiene script bash funzionali (è una skill dialogica, non orchestrante
state): l'unico bash è il self-test harness, che fa anchor structural sul contenuto del
SKILL.md (presenza delle sezioni e delle tecniche cardine).

---

## 7. Self-test harness (`tests/run-tests.sh`)

Stile identico agli altri self-test (bash 3.2-clean, `ok`/`bad`, `PASS=N FAIL=0`).
Essendo una skill dialogica senza script funzionali, gli anchor sono **structural** sul
SKILL.md: verificano che il contratto sia presente nel testo (così come il harness
review-triage-fix verifica anchor su SKILL.md). Assertion target (PASS=8):

1. `SKILL.md` esiste.
2. Frontmatter `name: design-brainstorm` presente.
3. NON contiene `disable-model-invocation: true` (anchor negativo critico).
4. Contiene la tecnica cardine `first-principles` (literal).
5. Contiene `analogie cross-dominio` (o `cross-domain`).
6. Contiene `inversione` / `pre-mortem`.
7. Contiene la stringa contratto output `BRAINSTORM.md`.
8. Contiene la sezione `## Lingua` (policy lingua italiana).
9. Contiene la tecnica di supporto `prior-art` (stato dell'arte / analisi del dominio).

Target: **PASS=9 FAIL=0**. (Vedi plan T1 per l'anchor red nel harness del chain.)

---

## 8. Lingua

Sezione `## Lingua` obbligatoria nel SKILL.md (come negli altri skill, lezione gap #6
del 2026-05-21): **comunicazione verso l'utente in italiano** — tutte le domande
`AskUserQuestion`, le sintesi, i recap e la narrazione di stato in italiano. Restano in
**inglese**: il frontmatter `description`, il template di `BRAINSTORM.md` (intestazioni
di sezione), eventuali nomi di campo. Il brief stesso: prosa in italiano, intestazioni
di sezione in inglese (per uniformità con SPEC/ARCH).

---

## 9. Coexistence

- NON modifica `interview-driver` (ruolo distinto: requisiti vs approcci).
- NON modifica `claude-md-generator`, `review-triage-fix`, `refactor-snapshot`,
  `vibe-status`.
- NON modifica gli agent (`architect.md` ecc.): il brief è passato come contesto al
  dispatch, non patcha l'agent.
- NON invoca `superpowers:brainstorming` (conflitto: stato terminale, scrive spec/plan).
- È invocata dal chain concept-to-code al gate 1b; aggiorna SOLO `BRAINSTORM.md`,
  l'orchestrator aggiorna `artifacts.brainstorm`.
- Skill `using-superpowers`: esplicitamente fuori scope (per richiesta del brief).
