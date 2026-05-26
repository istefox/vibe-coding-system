# Skill `web-e2e-test` — Design Spec

**Status:** proposed — 2026-05-22
**ADR:** `docs/architecture/ADR-0010-web-e2e-test.md`
**Plan:** `docs/superpowers/plans/2026-05-22-web-e2e-test.md`
**Confidence:** vedi report in chat (non nel deliverable).

---

## 0. Scopo in una frase

`web-e2e-test` esercita i flussi golden-path di una feature **web** sul codice live in un
browser reale (via `claude-in-chrome`, guidato dall'**orchestrator**), e ritorna un report
E2E (screenshot + errori console + network failure + esito per flusso). Chiude il loop "il
codice funziona davvero nel browser", non solo "i test unit passano". **Non si attiva su
progetti non-web.**

---

## 1. Posizionamento e differenze dalle skill/agent esistenti

| Componente | Risponde a | Output | Quando |
|---|---|---|---|
| `tester` (agent) | i test (unit/integration) passano? | esito test suite | Step impl |
| `review-triage-fix` | il codice ha difetti rilevabili a lettura? | review + fix | Gate 5 / Step 6 |
| **`web-e2e-test`** | la feature **funziona live nel browser**? | report E2E + screenshot | **Gate 6** / standalone |
| `debugger` (agent) | perché un bug accade? | diagnosi + fix | post-fail, su richiesta |

**Differenza netta:** gli altri verificano il codice *staticamente* o via test suite
*headless*; `web-e2e-test` verifica il **comportamento osservabile nel browser reale**. È
l'unica capability che esercita la UI live. **Non corregge il codice** (verifica, non fix):
a fronte di `feature-bug` raccomanda un ciclo `review-triage-fix` o un dispatch `debugger`,
ma la decisione è dell'utente.

**Orchestrator-only (vincolo HARD).** I tool `claude-in-chrome` sono disponibili
all'orchestrator (sessione principale), non ai sub-agent (gap MCP-inheritance documentato:
issue anthropics/claude-code #7296/#13605/#13898). Un sub-agent allucinerebbe i risultati
(falso verde). Quindi: la skill istruisce l'**orchestrator**, mai dispatcha un sub-agent
per la parte browser. (Coerente con concept-to-code §6.)

---

## 2. Forma: skill standalone riusata dal Gate 6

- **Skill standalone** `~/.claude/skills/web-e2e-test/SKILL.md`, invocabile a richiesta
  (`/skill web-e2e-test`, o trigger naturali "testa la UI nel browser", "verifica E2E web").
- **Riusata dal chain** concept-to-code come **Gate 6 — E2E web**, dopo Gate 5 (review).
  Il gate **invoca la stessa skill** (pattern Gate 1b→design-brainstorm, Step 6→
  review-triage-fix). Single source of truth.
- **Auto-skip su non-web:** standalone → dichiara "non-web, non applicabile" e termina; nel
  chain → Gate 6 no-op silenzioso (UX del chain invariata su rempay/CLI).

Niente `disable-model-invocation: true` (deve essere invocabile dal gate — lezione
`feedback_disable-model-invocation-strong`).

---

## 3. Web-detection (cascata, fail-safe verso NON-web)

Valutata sul `project_root` (risalita da `cwd` cercando `.claude/`, come `stop-gate.sh`).
Implementata in uno script puro `scripts/detect-web.sh` (testabile headless — §8). Ordine;
il primo che decide vince:

1. **`.claude/web-e2e.yaml` con campo `web:`** → autorevole (`web:true`→web; `web:false`→skip).
2. **`package.json`** con script `dev`/`start`/`serve` **o** dependency in
   {`vite`,`next`,`react-scripts`,`@angular/cli`,`vue`,`svelte`,`astro`,`nuxt`,`remix`,
   `webpack-dev-server`} → **web**.
3. **`index.html`** in `./`, `public/`, `src/`, `dist/` → **web** (statico servibile).
4. **Nessun segnale → NON-web** → la feature NON si attiva.

`detect-web.sh` stampa su stdout una sola riga: `web` | `non-web`, e (se web) una seconda
riga con il segnale che ha deciso (per audit/report). Bash 3.2-clean.

**Anti falso-positivo (vincolo HARD):** SwiftUI/macOS (`Package.swift`+`.swift`, no
`package.json` con dev server, no `index.html`) → non-web. CLI Python → non-web. Libreria →
non-web. Il default è non-web: si attiva solo su segnale positivo.

---

## 4. Server lifecycle (prefer-running, opt-in start, polling readiness)

### 4.1 Scoperta URL (ordine)

1. `.claude/web-e2e.yaml` `base_url` → autorevole.
2. Probe HTTP su porte note per stack: vite `5173`, next/react-scripts `3000`, vue `8080`,
   angular `4200`, astro `4321`, generico `8000`/`8888`. Prima che risponde (< 500) vince.
3. Nessuna risponde → **stop-and-ask** (chiede URL o autorizzazione ad avviare).

### 4.2 Avvio server (opt-in, mai silenzioso)

Solo se nessun URL risponde **e** l'utente conferma (HITL: avvio processo = side-effect).
Comando da `web-e2e.yaml` `start_cmd` o proposto dall'orchestrator e confermato. Lanciato in
background. **Mai** avviato in auto senza conferma.

### 4.3 Readiness check

Polling HTTP su `base_url` con backoff (~1s, cap `startup_timeout_s` default 30s). "Pronto"
= risposta HTTP < 500 (401/302 contano come "server su"). Timeout → stop-and-ask.

### 4.4 Teardown

- Server **avviato dalla skill** → spento alla fine (kill del processo background) + annotato
  nel report.
- Server **già in esecuzione** (prefer-running) → **NON** spento (non è sua proprietà).

---

## 5. Cosa testa: flussi (dichiarati > derivati-con-conferma > ad-hoc)

1. **Dichiarati:** `web-e2e.yaml` campo `flows:` (`name`, `steps` in linguaggio naturale,
   `expect` opzionale). Preferiti: espliciti, riproducibili, versionabili.
2. **Derivati dallo SPEC/plan, CON conferma:** se nessun `flows:`, la skill **propone** una
   bozza estratta dai "success criteria"/"Definition of Done" dello SPEC (o dal plan nel
   chain) e la mostra all'utente per conferma/modifica (`AskUserQuestion`) **prima** di
   eseguire. Mai esecuzione cieca.
3. **Ad-hoc:** in standalone l'utente detta i flussi nel prompt; la skill li struttura e
   conferma.

**Livello di intento, non selettori:** i flussi sono espressi come intento ("compila il
form di login con dati invalidi e verifica l'errore"), NON come selettori DOM. L'esecuzione
è adattiva (modello d'uso documentato di claude-in-chrome: istruzioni naturali, non script
Playwright). Trade-off: robustezza vs determinismo (il non-determinismo è mitigato da §7).

---

## 6. Flusso operativo passo-passo (quali tool `claude-in-chrome`, in che ordine)

La skill è una **guida procedurale per l'orchestrator** (come concept-to-code), non uno
script che chiama i tool. I tool sono **deferred**: vanno caricati via ToolSearch /
`/mcp claude-in-chrome` solo quando si arriva al passo 4.

**Fase 0 — Preludio (no browser).**
1. Risali `project_root`. Esegui `scripts/detect-web.sh`. Se `non-web` → dichiara e termina
   (standalone) / Gate 6 no-op (chain).
2. Carica config `.claude/web-e2e.yaml` se presente (base_url, start_cmd, timeout, flows).
3. Verifica prerequisito: l'estensione Claude in Chrome è attiva (`--chrome`/`/chrome`). Se
   non rilevata → dichiara "prerequisiti mancanti (Chrome non connesso), non eseguo un run
   finto" e termina. (Mai fingere un run.)

**Fase 1 — Server.**
4. Scopri URL (§4.1). Se nessuno risponde → stop-and-ask / opt-in start (§4.2) + readiness
   polling (§4.3).

**Fase 2 — Flussi.**
5. Determina i flussi (§5). Se derivati → conferma con `AskUserQuestion`.

**Fase 3 — Esecuzione browser (tool deferred, carica ora).** Per ciascun flusso:
6. **`tabs_context`** (o `tabs_*`) all'avvio: leggi le tab/pagine disponibili PRIMA di
   navigare (anti-rabbit-hole, guida doc "discover all available pages before exploring").
7. **`navigate`** all'URL/route del flusso.
8. **`read_page`/screenshot** per leggere lo stato del DOM e catturare il punto di partenza.
9. Per ogni step: **`computer`/`click`/`form_input`** secondo l'intento; tra le azioni,
   **`read_page`** per verificare il rendering, con timeout per-azione (§7).
10. **`read_console_messages`** filtrato per pattern error/warning (NON dump completo — guida
    doc), e **`read_network_requests`** per status >= 400 / request fallite.
11. **screenshot** dello stato finale (o del punto di fallimento).
12. Valuta `expect` del flusso → esito `pass`/`fail`/`blocked` + classificazione (§7/D6).
13. (Opzionale, se richiesto) **`gif_creator`** per registrare un flusso da documentare.

**Fase 4 — Chiusura.**
14. Teardown server se avviato dalla skill (§4.4).
15. Scrivi il report (§9). Se chain → l'orchestrator popola `manifest.artifacts.e2e`.
16. Se ci sono `feature-bug` → raccomanda `review-triage-fix`/`debugger` (decisione utente).

---

## 7. Anti-rabbit-hole (guardrail)

Incorpora la guida "Avoid rabbit holes" del system prompt + i fatti doc su dialog/idle:

- **`tabs_context` all'avvio** (passo 6): mappa le pagine prima di esplorare.
- **Timeout per-azione** (`action_timeout_s`, default 10s): azione scaduta → step `blocked`,
  niente loop.
- **Max 2 retry per elemento** (con breve attesa per rendering async), poi
  `test-fragile`/`blocked`. Mai loop infinito sullo stesso elemento.
- **Stop-and-ask dopo 2 blocchi infra** (dialog JS, connessione persa, server giù): la skill
  si ferma e chiede invece di insistere.
- **No-dialog discipline:** NON forzare dialog JS bloccanti (la doc: bloccano gli eventi, si
  dismettono a mano). Rilevato blocco → stop-and-ask.
- **Login/CAPTCHA:** non automatizzati (la doc: Claude pausa e chiede). Marcati come
  "verifica manuale residua", si prosegue coi flussi che non li richiedono.
- **Budget globale** (`session_timeout_s`, default ~300s): superato → report parziale e
  chiusura, per non bruciare context/tempo.

---

## 8. Classificazione dei fail (D6)

Ogni fail è marcato (euristica, dichiarata nel report):

- **`feature-bug`:** elemento presente e responsivo, ma comportamento ≠ `expect`, oppure
  errore applicativo in console / 500 backend.
- **`test-fragile`:** elemento atteso non trovato / flusso non più mappabile sulla UI
  (selettore/label cambiato). NON necessariamente un bug della feature.
- **`infra`:** server giù, dialog bloccante, "Receiving end does not exist", "No tab
  available". Ambiente, non bug.
- **`unknown`:** non classificabile con certezza → revisione umana.

**Default: continua e raccogli tutti i fail dei flussi** (non fail-fast). Eccezione: i
blocchi `infra` fermano (stop-and-ask, §7).

---

## 9. Contratto di output — report `docs/e2e/<date>-<topic>.md`

### 9.1 Posizione

`<project-root>/docs/e2e/YYYY-MM-DD-<topic-slug>.md` (crea `docs/e2e/` se assente).
Screenshot in `docs/e2e/assets/YYYY-MM-DD-<topic-slug>/`, referenziati con path relativi.
La skill standalone scrive SOLO questo (+ assets); NON tocca alcun manifest. Nel chain,
l'orchestrator popola `manifest.artifacts.e2e` col path del report.

### 9.2 Struttura (template in inglese, prosa in italiano)

```markdown
# E2E Web Test — <topic>

**Data:** YYYY-MM-DD
**Base URL:** <url>
**Server:** [already-running | started-by-skill]
**Flows source:** [yaml | derived-confirmed | ad-hoc]
**Esito complessivo:** [PASS | PARTIAL | FAIL]

## Prerequisiti
- Chrome extension: [connected | <perché mancante>]
- Web-detection: [signal che ha attivato la feature]

## Flussi

### Flow: <name> — [pass | fail | blocked]
- **Passi eseguiti:** <lista>
- **Expect:** <atteso> — **Osservato:** <reale>
- **Classificazione (se fail):** [feature-bug | test-fragile | infra | unknown]
- **Screenshot:** ![](assets/.../flow-<name>-final.png)
- **Console (filtrata error/warning):** <righe rilevanti, o "nessun errore">
- **Network failure:** <status>=400 / request fallite, o "nessuna">

(ripeti per ogni flusso)

## Riepilogo
- Flussi: <N pass> / <N fail> / <N blocked>
- Feature-bug rilevati: <N> → raccomandazione: <review-triage-fix | debugger | nessuna>

## Verifica manuale residua
- <login/CAPTCHA, stato esterno, flussi non automatizzabili>
```

### 9.3 Invarianti di qualità (verificabili dall'harness — structural)

- Header con `Esito complessivo` ∈ {PASS, PARTIAL, FAIL}.
- Almeno una sezione `### Flow:` per ogni flusso eseguito.
- Ogni fail ha una `Classificazione`.
- Sezione "Verifica manuale residua" presente (anche se "nessuna").
- NON contiene fix di codice (è verifica, non fix).

---

## 10. Integrazione col chain (Gate 6) e manifest schema 1.2

### 10.1 Posizione nel chain

Dopo Gate 5 (`gate_5_review_decision`). Nuovo stato opzionale `gate_6_e2e_web` prima di
`completed`. Il path diretto `gate_5 → completed` resta (retrocompat: se non-web o utente
skip). Transizioni nuove:
- `gate_5_review_decision → gate_6_e2e_web` (se web + utente opta `[e] run E2E`).
- `gate_6_e2e_web → completed`.
- Preservata: `gate_5_review_decision → completed` (skip / non-web).

### 10.2 Display Gate 6 (italiano)

```
============================================================
concept-to-code · Gate 6 · E2E WEB (opzionale)
============================================================
Progetto web rilevato (<signal>). Base URL candidato: <url o "da scoprire">.
Eseguire un test E2E live nel browser dei flussi golden-path?
Produce un report con screenshot + errori console + esito per flusso.
============================================================
HITL Gate 6: e2e_web_decision
  [e] esegui test E2E web (invoca web-e2e-test)
  [s] salta (verifica manuale a carico dell'utente)
  [a] abort chain
> _
```

`[s]` → transizione diretta `completed` (UX invariata). `[e]` → invoca la skill, popola
`artifacts.e2e`, poi `completed`. Su **non-web** il Gate 6 NON è mostrato (no-op silenzioso).

### 10.3 Schema manifest 1.2 (retrocompat)

- `manifest_schema_version: "1.2"` per i nuovi manifest. `1.0`/`1.1` restano validi.
- Nuovo campo opzionale `artifacts.e2e` (path del report; default null).
- Nuovi stati legali `gate_6_e2e_web` + 2 transizioni (§10.1).
- `manifest-validate.sh` esteso ad accettare `1.0|1.1|1.2` e i nuovi stati/transizioni.

---

## 11. Frontmatter e struttura file della skill

```yaml
---
name: web-e2e-test
description: This skill should be used when a WEB feature must be verified end-to-end in a
  real browser via claude-in-chrome (navigate, screenshot, read console, network), exercising
  golden-path flows on the LIVE code and producing an E2E report (screenshots + console errors
  + per-flow pass/fail). Driven by the ORCHESTRATOR (browser MCP tools are not reliably
  available to sub-agents). Auto-skips on non-web projects (SwiftUI/CLI/library). Invokable
  standalone and reused by the concept-to-code chain (Gate 6 — E2E web, after Gate 5).
  Triggers include "testa la UI nel browser", "verifica E2E web", "/skill web-e2e-test".
---
```

Struttura directory:
```
~/.claude/skills/web-e2e-test/
  SKILL.md              # body: Lingua, When to invoke, Orchestrator-only, Web-detection,
                        # Server lifecycle, Flussi, Flusso operativo (tool order),
                        # Anti-rabbit-hole, Report contract, Coexistence
  scripts/detect-web.sh # web-detection puro (testabile headless), bash 3.2-clean
  tests/run-tests.sh    # self-test: structural anchors + smoke detect-web.sh (§ harness)
```

Lo SKILL.md è una guida procedurale per l'orchestrator (non orchestra state machine come
concept-to-code); l'unico bash funzionale è `detect-web.sh` (+ il self-test).

---

## 12. Self-test harness (`tests/run-tests.sh`)

Bash 3.2-clean, `ok`/`bad`, `PASS=N FAIL=0`. Due classi di assertion:

**A. Structural anchor sullo SKILL.md (la parte browser non è testabile headless):**
1. `SKILL.md` esiste.
2. Frontmatter `name: web-e2e-test`.
3. NON contiene `disable-model-invocation: true` (anchor negativo critico — invocabile dal gate).
4. Contiene `claude-in-chrome` (o `tabs_context` / `read_console_messages`).
5. Contiene `orchestrator` (orchestrator-only).
6. Contiene la sezione web-detection (literal `web-detection` o `detect-web`).
7. Contiene `anti-rabbit-hole` (o `rabbit hole` / `timeout` + `stop-and-ask`).
8. Contiene il contratto report `docs/e2e/`.
9. Contiene `## Lingua`.

**B. Smoke di `detect-web.sh` (l'unico pezzo puro, deterministico — protegge "no falsi
avvii su non-web"):** fixture via `mktemp -d`:
10. `package.json` con `"vite"` → output `web`.
11. fixture SwiftUI (`Package.swift` + `App.swift`, no package.json/index.html) → `non-web`.
12. fixture CLI (solo `*.py` + `requirements.txt`) → `non-web`.
13. `index.html` nel root → `web`.
14. `.claude/web-e2e.yaml` con `web: false` (su fixture peraltro web) → `non-web` (override).

Target: **PASS=14 FAIL=0**. (Vedi plan T1 per gli anchor red nel harness del chain.)

**Cosa NON copre (open question, validabile solo in pilota):** esecuzione browser reale,
readiness/teardown server, cattura console/network, classificazione su UI reale,
anti-rabbit-hole effettivo. Onestà come design-brainstorm/ADR-0009.

---

## 13. Lingua

Sezione `## Lingua` obbligatoria nello SKILL.md: comunicazione verso l'utente in italiano
(domande `AskUserQuestion`, recap, narrazione, display Gate 6, prosa del report). Restano in
inglese: il frontmatter `description`, le intestazioni di sezione del report (per uniformità
con SPEC/ARCH), i nomi di campo di `web-e2e.yaml`, i path file.

---

## 14. Coexistence

- NON modifica gli agent (`tester`/`debugger`/`reviewer`/`coder`/...): la skill istruisce
  l'orchestrator; non patcha alcun agent.
- NON modifica `review-triage-fix`/`design-brainstorm`/`interview-driver`/
  `claude-md-generator`/`refactor-snapshot`/`vibe-status`. (Il Gate 6 può *raccomandare*
  `review-triage-fix` su `feature-bug`, ma non lo modifica.)
- NON modifica gli hook (`stop-gate.sh`, `protect-files.sh`, `pre-flight-pattern-enforce.sh`,
  `db-backup-guardrail.sh`) né `settings.json` né `.mcp.json`. (Il server dev avviato in
  background è un comando Bash: NON è DB-distruttivo → db-backup-guardrail lo lascia passare.)
- **Modifica il chain concept-to-code** (Gate 6 + schema 1.2 + manifest-validate.sh): è
  l'unico componente del sistema che questa feature estende. Tutto il resto è orthogonale.
- Skill `using-superpowers`: esplicitamente fuori scope (per richiesta del brief).
