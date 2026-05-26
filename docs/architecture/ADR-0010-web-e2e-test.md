# ADR-0010 — web-e2e-test (test E2E web live via Chrome MCP)

**Status:** Proposed — 2026-05-22

**Deciders:** architect (dispatch orchestrator), Stefano Ferri (approvazione finale)

**Related:** ADR-0003 (concept-to-code chain — la chain in cui si innesta il gate),
ADR-0008 (workflow v2 brainstorm — precedente di gate opzionale + skill non-terminale
invocata dal chain), ADR-0005 (vibe-status — skill standalone con report), ADR-0007
(concept-to-code e2e-smoke — precedente di smoke-test del chain), ADR-0002/0009 (pattern
"harness structural anchor" e "skill dialogica/orchestrante non testabile end-to-end").

---

## Context

Più volte è emerso un gap operativo: **gli agenti non testano la UI**. Dopo
l'implementazione di una feature frontend (Step 5 del chain concept-to-code, o un fix
diretto), resta a carico dell'utente una "verifica UI manuale" — es. il wizard SwiftUI di
rempay. La chain chiude su "i test unit passano", non su "il codice è live e funziona nel
browser".

Claude Code dispone ora dei tool `claude-in-chrome` (browser automation beta): l'agente
può navigare un browser reale, fare screenshot, leggere la console, monitorare le network
request, cliccare e compilare form, registrare GIF. Per i **progetti web** questo permette
di colmare il gap: esercitare i flussi golden-path della feature appena implementata
**end-to-end sul codice live** e produrre un report E2E (screenshot + errori console +
network failure + esito per flusso).

Questo ADR progetta la capability `web-e2e-test`: forma (skill/gate), web-detection,
server lifecycle, contratto del report, gestione fallimenti, anti-rabbit-hole, e
testabilità della feature stessa.

**Scope esplicito:** la feature vale **solo per progetti web**. Per SwiftUI/macOS/native/
CLI/librerie NON si applica e NON deve attivarsi (no falsi avvii su rempay o su una CLI).
La verifica manuale resta per il non-web.

**Fatti verificati (`code.claude.com/docs/en/chrome`, 2026-05-22):**

- I tool browser si abilitano con `claude --chrome` o `/chrome` in sessione; sono **deferred**
  (aumentano il context, da caricare via `/mcp claude-in-chrome` o ToolSearch quando servono).
- localhost è un caso d'uso primario documentato ("navigate to your local server").
- Su login/CAPTCHA "Claude pauses and asks you to handle it manually".
- I **dialog JavaScript (alert/confirm/prompt) bloccano gli eventi del browser** e impediscono
  a Claude di ricevere comandi; vanno dismessi manualmente ("Dismiss the dialog manually, then
  tell Claude to continue").
- Il **service worker dell'estensione va idle** nelle sessioni lunghe → la connessione cade
  ("Reconnect extension"). Errori tipici: "No tab available", "Receiving end does not exist".
- I permessi per-sito sono ereditati dall'estensione Chrome (gestiti lì).

**Assunzioni esplicite (NON validate — la feature poggia su queste):**

- **I tool `claude-in-chrome` sono disponibili all'ORCHESTRATOR, NON ai sub-agent.** La doc
  ufficiale dice che i sub-agent ereditano i tool del thread, **ma** in pratica è un bug noto
  e ricorrente (anthropics/claude-code issue #7296, #13605, #13898, #34935): i sub-agent
  lanciati via Task tool **non** accedono ai tool MCP e tendono ad allucinare risultati
  plausibili. Per un test E2E un risultato allucinato è il fallimento peggiore (falso verde).
  **Decisione conservativa:** la feature è guidata dall'**orchestrator**, mai delegata a un
  sub-agent. (Coerente col vincolo blueprint §2: i sub-agent non spawnano sub-agent; qui in
  più non hanno i tool browser.)
- Lo `SPEC.md` di un progetto greenfield ha una sezione "success criteria"/"Definition of
  Done" da cui derivare i flussi golden-path (verificato sul template interview-driver del
  sistema; assunto per progetti esterni).
- Non esiste oggi una convenzione utente per dichiarare i flussi E2E o l'URL del dev server.
  Il contratto `.claude/web-e2e.yaml` proposto è una **nuova convenzione** introdotta da
  questo ADR (opzionale; vedi D2/D4).
- Il repo `vibe-coding-system` è NON-git: i deliverable sono i 3 markdown; il deploy degli
  artefatti live (`~/.claude/skills/web-e2e-test/`, gate nel chain) è un task separato (plan
  TDD), senza commit step.

---

## Decision

Introdurre **una skill standalone `web-e2e-test`**, invocabile a richiesta, **riusata da un
nuovo gate opzionale "Gate 6 — E2E web" nel chain concept-to-code** (dopo Gate 5 review).
La skill istruisce l'**orchestrator** a: (1) verificare che il progetto sia web e auto-skip
altrimenti; (2) scoprire/attendere il dev server; (3) caricare i tool `claude-in-chrome`;
(4) esercitare i flussi golden-path (dichiarati o derivati dallo SPEC, con conferma utente);
(5) produrre un report `docs/e2e/<date>-<topic>.md` con screenshot + errori console +
network failure + esito per flusso; (6) applicare guardrail anti-rabbit-hole (timeout,
max-tentativi, stop-and-ask). Manifest schema **1.2** (retrocompat 1.0/1.1) con nuovo campo
`artifacts.e2e`. Harness della skill = **structural anchor** sullo SKILL.md (la feature
pilota un browser reale → non testabile headless in modo deterministico; onesto come
design-brainstorm/ADR-0009).

Di seguito la decisione per ciascuna delle 8 domande architetturali.

### D1 — Forma: skill standalone + gate riusante (entrambi)

**Skill standalone `web-e2e-test`** invocabile a richiesta, **riusata** da un gate opzionale
del chain (`Gate 6 — E2E web`, dopo Gate 5). Non un gate-only, non una skill-only.

Razionale:
- **Standalone** perché il gap "verifica UI manuale" si presenta anche fuori dal chain (fix
  diretto, brownfield senza chain, iterazione su feature esistente). Una skill invocabile
  copre tutti i casi.
- **Gate riusante** perché dentro il chain il momento naturale per l'E2E è subito dopo il
  review (Gate 5): codice implementato + (eventualmente) rivisto → si verifica live. Il gate
  non duplica la logica: **invoca la stessa skill** (stesso pattern di Gate 1b, che invoca
  `design-brainstorm`; e di Step 6, che invoca `review-triage-fix`). Single source of truth.
- **Opzionale e auto-skip:** il gate appare solo se il progetto è web (D2). Su progetti
  non-web il gate è un no-op silenzioso (UX del chain invariata per rempay/CLI).

**Soggetto = orchestrator.** La skill istruisce l'orchestrator (main CLI agent), che è
l'unico ad avere i tool `claude-in-chrome` (vedi assunzione in Context). La skill NON
dispatcha un sub-agent per la parte browser. Coerente con concept-to-code §6 ("this skill
instructs the orchestrator").

### D2 — Web-detection: cascata di segnali, fail-safe verso NON-web

La skill classifica il progetto come web tramite una **cascata di segnali** valutata sul
`project_root` (risalendo da `cwd`), in ordine; il primo che decide vince:

1. **Override esplicito (massima priorità):** file `.claude/web-e2e.yaml` presente →
   `web: true` implicito (l'utente l'ha configurato apposta). Se il file ha `web: false` →
   NON-web esplicito, skip.
2. **`package.json` con dev server noto:** esiste `package.json` e contiene uno script
   `dev`/`start`/`serve` **o** una dependency tra `vite`, `next`, `react-scripts`,
   `@angular/cli`, `vue`, `svelte`, `astro`, `nuxt`, `remix`, `webpack-dev-server` →
   `web: true`.
3. **Static web:** esiste un `index.html` nel root o in `public/`/`src/`/`dist/` →
   `web: true` (sito statico servibile).
4. **Nessun segnale → `web: false`:** la feature **NON si attiva**. Se invocata standalone
   su un progetto non-web, la skill lo dichiara ("progetto non-web rilevato, web-e2e-test
   non applicabile") e termina senza errore. Nel chain, il Gate 6 è no-op silenzioso.

**Anti falso-positivo su rempay/native:** un progetto SwiftUI/macOS non ha `package.json`
con dev server né `index.html` → cade su (4) → skip. Una CLI Python (es. pricing-markup-cli)
idem. Una libreria idem. Il default è "non-web" — la feature si attiva solo su segnale
positivo, mai per assenza di segnale.

### D3 — Server lifecycle: prefer-running, opt-in auto-start, polling readiness

**Default: prefer-running (l'utente avvia il server).** La skill prima **prova a connettersi**
a un URL candidato; solo se nessuno risponde e l'utente lo autorizza, prova ad avviarlo.

**Scoperta dell'URL** (in ordine):
1. `.claude/web-e2e.yaml` campo `base_url` (es. `http://localhost:5173`) → autorevole.
2. Porte candidate note per stack: vite `5173`, next/react-scripts `3000`, vue-cli `8080`,
   angular `4200`, astro `4321`, generico `8000`/`8888`. Probe HTTP (HEAD/GET) su
   `http://localhost:<porta>` finché una risponde.
3. Se nessuna risponde → **stop-and-ask**: chiede all'utente l'URL o l'autorizzazione ad
   avviare il server.

**Avvio del server (opt-in, mai silenzioso):** se nessun URL risponde, la skill **chiede
conferma** prima di lanciare il dev server (HITL — un avvio di processo è un side-effect).
Il comando d'avvio viene da `.claude/web-e2e.yaml` campo `start_cmd` (es. `npm run dev`)
oppure è proposto dall'orchestrator e confermato dall'utente. Lanciato in background
(`run_in_background`).

**Readiness check:** polling HTTP su `base_url` con backoff (es. ogni 1s, max ~30s /
`startup_timeout_s` configurabile). "Pronto" = risposta HTTP < 500 (anche 401/302 conta come
"server su"). Timeout → stop-and-ask (non procede a cieco).

**Teardown:** se **la skill ha avviato** il server, lo **spegne alla fine** (kill del
processo background) e lo annota nel report. Se il server era **già in esecuzione**
(prefer-running), la skill **NON lo spegne** (non è sua proprietà — principio di minima
sorpresa).

### D4 — Cosa testa: flussi dichiarati > derivati-con-conferma (mai auto-generati ciechi)

I flussi golden-path provengono, in ordine di preferenza:

1. **Dichiarati dall'utente:** `.claude/web-e2e.yaml` campo `flows:` (lista di flussi con
   `name`, `steps` in linguaggio naturale, e `expect` opzionale). Massima affidabilità: il
   contratto è esplicito, riproducibile, versionabile.
2. **Derivati dallo SPEC/plan, CON conferma utente:** se non c'è `web-e2e.yaml`, la skill
   **propone** una bozza di flussi estratti dai "success criteria"/"Definition of Done" dello
   `SPEC.md` (o dal plan, nel chain) e li **mostra all'utente per conferma/modifica** prima di
   eseguirli (`AskUserQuestion`). NON esegue flussi auto-generati senza conferma.
3. **Checklist ad-hoc in sessione:** in standalone, l'utente può dettare i flussi a voce nel
   prompt; la skill li struttura e conferma.

**Trade-off automazione vs affidabilità (esplicito):** auto-generare i passi (selettori,
click) dal solo SPEC è inaffidabile — lo SPEC descrive *cosa* in linguaggio naturale, non
*quali selettori DOM*. La skill quindi lavora a livello di **intento** ("compila il form di
login con dati invalidi e verifica che appaia l'errore"), lasciando all'orchestrator+browser
la traduzione in azioni concrete a runtime (è il modello d'uso documentato di
claude-in-chrome: istruzioni in linguaggio naturale, non script Playwright). I selettori NON
sono codificati nella skill (sarebbero fragili e stack-specific): il flusso resta dichiarato
come intento, l'esecuzione è adattiva. Questo massimizza robustezza al costo di
non-determinismo (mitigato da D6/D7).

### D5 — Output: report markdown `docs/e2e/<date>-<topic>.md` + manifest `artifacts.e2e`

La skill scrive **un solo report**: `<project-root>/docs/e2e/YYYY-MM-DD-<topic-slug>.md`
(crea `docs/e2e/` se assente). Gli screenshot sono salvati accanto, in
`docs/e2e/assets/YYYY-MM-DD-<topic-slug>/` e referenziati nel markdown con path relativi.

Struttura del report (template in inglese, prosa in italiano — coerente con SPEC/ARCH/ADR):
- **Header:** data, topic, base_url, modalità server (already-running | started-by-skill),
  fonte flussi (yaml | derived-confirmed | ad-hoc), esito complessivo (PASS | PARTIAL | FAIL).
- **Per flusso:** nome, passi eseguiti, esito (`pass` | `fail` | `blocked`), screenshot
  allegato (almeno 1: stato finale o punto di fallimento), errori console rilevati (filtrati
  per pattern error/warning, non l'intero dump — guida doc), network failure (status >= 400
  o request fallite).
- **Classificazione dei fail (D6):** ogni fail marcato `feature-bug` (errore reale
  dell'app) | `test-fragile` (selettore/flow non più valido) | `infra` (server giù, dialog
  bloccante, connessione persa) | `unknown`.
- **Open questions / verifica manuale residua:** ciò che la skill NON ha potuto verificare
  (login/CAPTCHA, flussi che richiedono stato esterno).

**Integrazione manifest:** nuovo campo `artifacts.e2e` (path del report) nello schema
manifest **1.2** (retrocompat 1.0/1.1: campo opzionale, default null; i manifest 1.0/1.1
restano validi). Il chain popola `artifacts.e2e` dopo il Gate 6. La skill standalone NON
tocca alcun manifest (come design-brainstorm scrive solo BRAINSTORM.md).

### D6 — Gestione fallimenti: continua-e-raccogli + classificazione + stop-and-ask sui blocchi

**Default: continua e raccogli tutti i fail dei flussi** (non si ferma al primo). Un report
E2E ha valore proprio se elenca *tutti* i flussi rotti, non solo il primo. Eccezione: i
**blocchi infrastrutturali** (server giù, dialog JS bloccante, connessione browser persa)
fermano l'esecuzione (stop-and-ask) — D7.

**Classificazione di ogni fail** (euristica, dichiarata nel report):
- **`feature-bug`:** l'elemento esiste e risponde, ma il comportamento osservato contraddice
  l'`expect` del flusso (es. submit con dati invalidi → nessun messaggio d'errore), oppure la
  console mostra un errore applicativo (eccezione JS, 500 sul backend).
- **`test-fragile`:** l'elemento atteso non è trovato / il flusso non è più mappabile sulla
  UI corrente (selettore/label cambiato). NON è necessariamente un bug della feature: spesso
  il flusso dichiarato è stantio. Marcato distintamente per non gridare "bug" a vuoto.
- **`infra`:** server non raggiungibile, dialog bloccante, "Receiving end does not exist",
  "No tab available". Non è né bug né test fragile: è ambiente.
- **`unknown`:** non classificabile con certezza → flaggato per revisione umana.

**HITL sui fail:** la skill NON corregge il codice (non è il suo ruolo: è verifica, non
fix). A fine run presenta il riepilogo e, se ci sono `feature-bug`, **raccomanda** un ciclo
`review-triage-fix` o un dispatch `debugger` (decisione dell'utente). Nel chain, un esito
FAIL/PARTIAL al Gate 6 NON blocca il completamento ma viene evidenziato nel report finale.

### D7 — Anti-rabbit-hole: timeout per-azione, max-tentativi, stop-and-ask dopo N, no-dialog

Incorpora le guida del system prompt ("Avoid rabbit holes") e i fatti doc su dialog/idle:

- **`tabs_context` all'avvio:** prima di agire, la skill istruisce l'orchestrator a leggere
  il contesto delle tab (quali pagine sono disponibili) per non esplorare alla cieca (guida
  doc: "use a file to discover all available pages before exploring further").
- **Timeout per-azione:** ogni azione browser (navigate, click, attesa elemento) ha un budget
  (default ~10s / `action_timeout_s`). Scaduto → marca il passo `blocked`, non ritenta in
  loop.
- **Max-tentativi per elemento:** un elemento non trovato/non responsivo → al massimo
  **2 retry** (es. dopo un breve attesa per rendering async), poi `test-fragile`/`blocked`.
  Mai loop infinito sullo stesso elemento.
- **Stop-and-ask dopo N blocchi infra:** dopo **2** blocchi infrastrutturali (dialog,
  connessione persa, server giù) la skill **si ferma e chiede all'utente** invece di
  insistere. Coerente col fatto che dialog JS e service-worker-idle richiedono intervento
  manuale.
- **No-dialog discipline:** la skill NON tenta di forzare dialog JS bloccanti (la doc dice
  che bloccano gli eventi e vanno dismessi a mano); se rileva un blocco → stop-and-ask.
- **Login/CAPTCHA:** non automatizzati (la doc dice che Claude pausa e chiede). La skill li
  marca come "verifica manuale residua" nel report e prosegue con i flussi che non li
  richiedono.
- **Budget globale di sessione:** un wall-clock cap complessivo (`session_timeout_s`, default
  ~5 min) oltre il quale la skill chiude e scrive un report parziale, per non bruciare
  context/tempo.

### D8 — Harness/testabilità: structural anchor sullo SKILL.md + smoke web-detection (no browser reale)

Una feature che pilota un browser reale **non è testabile headless in modo deterministico**:
non c'è un browser, né un dev server, né una UI nel harness CI. Onestà come design-brainstorm
(ADR-0008) e come il gate `ask` di ADR-0009 (si testa il payload, non il rendering).

**Cosa verifica il harness (deterministico, headless):**
1. **Structural anchor sullo SKILL.md** (`tests/run-tests.sh`, bash 3.2-clean, `ok`/`bad`,
   `PASS=N FAIL=0`): presenza di `name: web-e2e-test`, assenza di
   `disable-model-invocation: true` (deve essere invocabile dal gate), presenza delle sezioni
   contratto (web-detection, server lifecycle, anti-rabbit-hole, report contract, `## Lingua`,
   uso di `tabs_context`, "orchestrator-only").
2. **Smoke della logica web-detection** (l'unico pezzo *puro* e testabile): se la skill
   include uno script helper `detect-web.sh` (decisione del plan), il harness lo esercita su
   fixture `mktemp -d` — `package.json` con `vite` → `web`; SwiftUI fixture (solo `.swift` +
   `Package.swift`) → `non-web`; CLI fixture → `non-web`; `index.html` → `web`;
   `.claude/web-e2e.yaml` con `web:false` → `non-web`. Questo è deterministico e protegge il
   vincolo HARD "no falsi avvii su non-web".
3. **Anchor nel harness del chain** (concept-to-code): verifica che il Gate 6 sia registrato
   nello SKILL.md del chain (literal `Gate 6` / `web-e2e`) e che il manifest schema citi
   `artifacts.e2e` / `1.2`.

**Cosa NON è verificabile dal harness (resta open question, validabile solo nell'uso reale):**
- L'esecuzione browser end-to-end (navigate/click/screenshot reali).
- La readiness del dev server, il teardown, la cattura console/network.
- La classificazione feature-bug vs test-fragile su una UI reale.
- L'anti-rabbit-hole effettivo (timeout/retry reali).

Questi restano validabili **solo in pilota** con un progetto web reale. Il report del plan
deve dichiararlo esplicitamente (come per il gate `ask` di ADR-0009).

---

## Contratto `.claude/web-e2e.yaml` (nuova convenzione, opzionale)

Introdotto da questo ADR. Tutti i campi opzionali; in assenza, la skill cade sui default
di D2/D3/D4. Schema:

```yaml
# .claude/web-e2e.yaml — opzionale; configura web-e2e-test per questo progetto
web: true                       # override esplicito web/non-web (default: cascata D2)
base_url: http://localhost:5173 # URL del dev server (default: probe porte note D3)
start_cmd: npm run dev          # comando d'avvio (usato solo se nessun server risponde, opt-in)
startup_timeout_s: 30           # readiness polling cap
action_timeout_s: 10            # timeout per azione browser
session_timeout_s: 300          # budget globale di sessione
flows:                          # flussi golden-path dichiarati (preferiti ai derivati)
  - name: login-invalid
    steps:
      - "vai a /login"
      - "compila email con 'x' e password vuota, premi Accedi"
    expect: "appare un messaggio d'errore di validazione"
  - name: dashboard-loads
    steps:
      - "vai a / da utente autenticato"
    expect: "la dashboard carica senza errori in console"
```

---

## Alternatives considered (per ognuna delle 8 domande)

### D1 — Forma

- **Solo gate nel chain (no skill standalone):** rifiutata. Il gap "verifica UI manuale" si
  presenta anche fuori dal chain (fix diretti, brownfield, iterazione). Un gate-only
  lascerebbe scoperti tutti i casi non-chain.
- **Solo skill standalone (no gate):** rifiutata. Dentro il chain l'E2E dopo il review è il
  momento naturale; lasciarlo all'utente da invocare a mano romperebbe la continuità
  "concept→code→verified" che il chain promette.
- **Sub-agent dedicato `e2e-tester`:** rifiutata. I sub-agent Task-launched non hanno
  affidabilmente i tool MCP browser (issue documentati): un e2e-tester sub-agent
  allucinerebbe i risultati (falso verde) — il fallimento peggiore per un test. La capability
  DEVE girare sull'orchestrator.

### D2 — Web-detection

- **Config esplicita obbligatoria (`web-e2e.yaml` sempre richiesto):** rifiutata. Troppa
  friction; la feature non si attiverebbe mai su progetti web non ancora configurati,
  vanificando l'auto-skip intelligente nel chain.
- **Detection solo via `package.json`:** rifiutata. Esclude i siti statici (`index.html`
  servito) e i progetti con dev server non-Node. La cascata copre più casi.
- **Attivare di default e disattivare su non-web (denylist):** rifiutata. Inverte il
  fail-safe: rischierebbe falsi avvii su native/CLI per assenza di un marker. Il default DEVE
  essere "non-web"; si attiva solo su segnale positivo.

### D3 — Server lifecycle

- **Auto-start sempre (la skill avvia il server sempre):** rifiutata. Un avvio di processo è
  un side-effect; se il server è già su, raddoppiarlo causa conflitti di porta. Prefer-running
  + opt-in start è meno sorprendente.
- **Mai avviare (richiede sempre server già su):** rifiutata. Friction inutile quando l'utente
  vuole il check completo end-to-end; l'opt-in start con conferma è il compromesso.
- **Readiness via sleep fisso:** rifiutata. Fragile (server lento → falso "non pronto"; server
  veloce → tempo sprecato). Polling con timeout è robusto.

### D4 — Cosa testa

- **Auto-generazione cieca dei flussi dallo SPEC (no conferma):** rifiutata. Lo SPEC descrive
  l'intento in linguaggio naturale, non i selettori; eseguire flussi auto-generati senza
  conferma produce test fragili e falsi fail. La conferma utente è il gate di affidabilità.
- **Solo flussi dichiarati in YAML (no derivazione):** rifiutata come unica via. Troppa
  friction per il primo run; la derivazione-con-conferma abbassa la barriera d'ingresso.
- **Selettori DOM codificati nella skill:** rifiutata. Stack-specific e fragili; la skill
  lavora a livello di intento e lascia l'esecuzione adattiva al browser (modello d'uso
  documentato di claude-in-chrome).

### D5 — Output

- **Solo output in chat (nessun file):** rifiutata. Un report E2E con screenshot va
  persistito per audit/condivisione e per integrazione nel manifest del chain.
- **Report dentro il manifest stesso:** rifiutata. Il manifest è uno stato di macchina, non
  un documento; gli screenshot non ci stanno. Il manifest punta al report (`artifacts.e2e`).
- **Schema manifest senza versione nuova (riusare 1.1):** rifiutata. Aggiungere un campo
  semanticamente nuovo (`artifacts.e2e`) merita il bump a 1.2 per chiarezza di validazione,
  mantenendo la retrocompat (campo opzionale, 1.0/1.1 restano validi). Coerente col precedente
  1.0→1.1 di ADR-0008.

### D6 — Gestione fallimenti

- **Fermarsi al primo fail (fail-fast):** rifiutata. Un report che elenca un solo flusso rotto
  costringe a ri-run multipli; raccogliere tutti i fail dei flussi dà più valore in un colpo.
  (Eccezione: i blocchi infra fermano comunque — D7.)
- **La skill corregge il codice (auto-fix):** rifiutata. Viola la separazione verifica/fix; un
  test che si auto-corregge maschera il bug e può introdurre regressioni. La skill verifica e
  raccomanda; il fix è di `review-triage-fix`/`debugger`/coder, su decisione utente.
- **Non distinguere feature-bug da test-fragile:** rifiutata. Collasserebbe falsi positivi
  (selettore cambiato) in "bug della feature", erodendo la fiducia nel report. La
  classificazione è il discriminator chiave.

### D7 — Anti-rabbit-hole

- **Nessun timeout / retry illimitati:** rifiutata. È esattamente il rabbit-hole che la guida
  del system prompt mette in guardia; un elemento non responsivo bloccherebbe la sessione.
- **Tentare di dismettere i dialog JS via script:** rifiutata. La doc dice che i dialog
  bloccano gli eventi e vanno dismessi manualmente; tentare di forzarli è inaffidabile e
  rischia loop. Stop-and-ask è la via documentata.
- **Automatizzare login/CAPTCHA:** rifiutata. La doc dice che Claude pausa e chiede; tentare
  di automatizzarli viola il design dell'estensione e i permessi sito.

### D8 — Harness/testabilità

- **Harness end-to-end con browser headless reale (Playwright in CI):** rifiutata. Introduce
  uno stack pesante (Node + Playwright + browser), stack-locked, contro il vincolo bash
  3.2-clean / zero-dep del sistema, e comunque non testerebbe i tool `claude-in-chrome` reali
  (che richiedono l'estensione + sessione Claude Code). Il valore non giustifica il costo.
- **Nessun harness (feature non testabile → niente test):** rifiutata. La parte web-detection
  è pura e DEVE essere testata (protegge il vincolo HARD "no falsi avvii su non-web"). Lo
  structural anchor + smoke web-detection è il massimo testabile in modo onesto.
- **Mock dell'intera sessione browser:** rifiutata. Un mock del browser testerebbe il mock,
  non la feature; darebbe falsa sicurezza. Meglio dichiarare onestamente cosa resta
  validabile solo in pilota.

---

## Consequences

### Positive

- Chiude il loop "il codice è live e funziona nel browser", non solo "i test unit passano".
  Colma il gap "verifica UI manuale" per i progetti web.
- **Riuso pulito:** il Gate 6 invoca la stessa skill standalone (single source of truth,
  pattern già collaudato da Gate 1b→design-brainstorm e Step 6→review-triage-fix).
- **Auto-skip su non-web:** nessun falso avvio su rempay (SwiftUI) / CLI / librerie. Il
  default fail-safe è "non-web".
- **Report persistente** con screenshot + console + network + esito per flusso, integrato nel
  manifest (`artifacts.e2e`), utile per audit e per decidere un ciclo di fix.
- **Classificazione feature-bug vs test-fragile** preserva la fiducia nel report (un selettore
  cambiato non viene gridato come bug).
- **Anti-rabbit-hole esplicito** (timeout, max-retry, stop-and-ask, no-dialog) coerente con la
  guida del system prompt e coi fatti doc su dialog/idle.

### Negative

- **Non-determinismo intrinseco:** i flussi a livello di intento eseguiti su una UI reale non
  sono riproducibili al 100%. Mitigato dai flussi dichiarati in YAML (più stabili) e dalla
  classificazione dei fail, ma resta una caratteristica della feature.
- **Fragilità dei tool browser:** service worker idle, dialog bloccanti, connessione persa,
  login/CAPTCHA. Mitigato da stop-and-ask e dalla marcatura "infra"/"verifica manuale", ma può
  comunque interrompere una run.
- **Dipendenza da un'assunzione non validata** (tool browser orchestrator-only): se in futuro
  i sub-agent ereditassero affidabilmente i tool MCP, la scelta resterebbe valida (orchestrator
  funziona comunque) ma sotto-ottimale (parallelizzazione persa). Documentato come open
  question.
- **Testabilità limitata:** il grosso della feature è validabile solo in pilota. Il harness
  copre solo web-detection + structural anchor. Limite noto, annotato (come ADR-0008/0009).
- **Setup richiesto:** l'utente deve avere l'estensione Claude in Chrome installata e
  `--chrome` attivo; senza, la skill non può eseguire (deve rilevarlo e degradare a
  "prerequisiti mancanti", non fingere un run).

### Neutral

- **Manifest schema 1.2:** nuovo campo opzionale `artifacts.e2e`; 1.0/1.1 restano validi
  (retrocompat). `manifest-validate.sh` va esteso ad accettare 1.2 (plan).
- **Nuova convenzione `.claude/web-e2e.yaml`** introdotta da questo ADR; opzionale, va
  documentata in un eventuale CLAUDE.md di progetto target.
- **Tool MCP deferred:** i tool browser aumentano il context se "enabled by default"; la skill
  li carica on-demand (via `/mcp claude-in-chrome` / ToolSearch) solo quando il progetto è web
  e i flussi sono confermati — non a ogni sessione.
- Repo `vibe-coding-system` NON-git: i deliverable sono i 3 markdown; il deploy degli artefatti
  live (`~/.claude/skills/web-e2e-test/`, patch al chain) è un task separato (plan TDD), senza
  commit step.

---

## References

- ADR-0003 — `docs/architecture/ADR-0003-concept-to-code-chain.md` (chain in cui si innesta il
  Gate 6; pattern manifest YAML + gate HITL)
- ADR-0008 — `docs/architecture/ADR-0008-concept-to-code-workflow-v2-brainstorm.md` (precedente
  di gate opzionale + skill non-terminale invocata dal chain; schema 1.0→1.1; harness
  structural anchor onesto su skill dialogica)
- ADR-0005 — `docs/architecture/ADR-0005-vibe-status-skill.md` (skill standalone con report)
- ADR-0007 — `docs/architecture/ADR-0007-concept-to-code-e2e-smoke.md` (smoke-test del chain)
- ADR-0009 — `docs/architecture/ADR-0009-db-backup-guardrail.md` (separazione "payload
  testabile" vs "comportamento runtime validabile solo in pilota"; gap-doc → fail-safe)
- `~/.claude/skills/concept-to-code/SKILL.md` (state machine; pattern gate→skill riuso)
- `~/.claude/skills/design-brainstorm/SKILL.md` (skill invocata dal chain, scrive solo il
  proprio artefatto; structural-anchor harness)
- Chrome integration: `code.claude.com/docs/en/chrome` (verificato 2026-05-22: localhost,
  login/CAPTCHA pause, dialog JS bloccanti, service-worker idle, permessi sito ereditati,
  tool deferred via `/mcp claude-in-chrome`)
- Sub-agent + MCP: `code.claude.com/docs/en/sub-agents` (inheritance documentata) +
  anthropics/claude-code issue #7296/#13605/#13898/#34935 (**gap verificato:** Task-launched
  sub-agents non accedono affidabilmente ai tool MCP → tool browser orchestrator-only)
- `feedback_bash32-constraint` (harness bash 3.2-clean)
