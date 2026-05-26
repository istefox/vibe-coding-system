# ADR-0011 — clean-public-repo + modalità anonima nel chain (anonimizzazione contributo strumento per repo pubblici)

**Status:** Accepted — 2026-05-23

**Deciders:** architect (dispatch orchestrator), Stefano Ferri (approvazione finale)

**Related:** ADR-0003 (concept-to-code chain — la chain in cui si innesta il gate di
attivazione), ADR-0008 (workflow v2 brainstorm — precedente di gate opzionale + skill
non-terminale invocata dal chain; schema 1.0→1.1), ADR-0010 (web-e2e-test — precedente
immediato del pattern "skill standalone + gate del chain che la invoca", schema 1.1→1.2,
detection fail-safe, harness honesto su feature non-headless), ADR-0009 (db-backup-guardrail
— fail-mode asimmetrico, HITL gate su operazione distruttiva, freshness via backup),
ADR-0005 (vibe-status — skill standalone con report).

---

## Context

Un repo pubblicato su GitHub viene spesso giudicato anche per i marcatori dello strumento
con cui è stato scritto (trailer di commit, commenti-traccia, file slop, stringhe/emoji
decorative). Lo scopo della feature, **vincolante e dichiarato nello SPEC**, è duplice:
(1) **non sbandierare lo strumento** e (2) **qualità olistica** del repo (commit essenziali,
doc concisi, zero file inutili), così che il lavoro sia giudicato per il codice. Il lavoro
resta dell'utente: lui lo dirige, rivede, testa ed è responsabile.

L'utente ha scelto (BRAINSTORM, Alternativa C★+D★) un'**architettura ibrida**:
- **Prevenzione** sui repo nuovi → una **modalità anonima** nel chain `concept-to-code`
  produce output già conforme (commit/doc puliti dall'inizio, zero rewrite).
- **Rimedio** sui repo esistenti → una **skill standalone `clean-public-repo`** che fa audit
  + cleanup retroattivo (es. plugin Obsidian già pubblicato).
- Per i repo **già pubblici**, default = **fresh-history publish** (repo derivato con history
  pulita; l'originale con tracce resta privato); il **rewrite chirurgico in-place** resta
  opzione di seconda scelta esplicita, mai default. Priorità #1: **nessun rewrite distruttivo
  non protetto**.

Questo ADR progetta: dove innestare il gate di attivazione nel chain, la forma e le dipendenze
della skill, la detection, il contratto del report, il flusso fresh-history, il rewrite
chirurgico protetto, la coexistenza della modalità anonima con `coder.md`/`architect.md`, e i
fail-mode di ogni operazione distruttiva.

### Inquadramento etico (vincolo, non opzione)

Esplicitato perché è un confine di design, non un dettaglio: lo scopo è **non sbandierare lo
strumento + qualità**. NON è: falsificare autori (mai attribuire commit a persone reali che
non hanno contribuito) né mentire attivamente se qualcuno chiede esplicitamente. L'attribuzione
nativa è già disattivata (`settings.json: attribution {commit:"", pr:""}` — fatto verificato
nello SPEC §"Inquadramento etico"). La feature rimuove **marcatori dello strumento**, non
falsifica la **paternità umana**: il commit anonimo resta correttamente attribuito all'autore
git configurato (Stefano), non a un terzo inventato.

### Fatti verificati

- **`git-filter-repo` PRESENTE** sull'ambiente (`/opt/homebrew/bin/git-filter-repo`,
  versione confermata via `git filter-repo --version`). È lo standard de-facto per rewrite
  chirurgico (report researcher); `git filter-branch` è DEPRECATO e non va usato; BFG non è
  adatto a sostituzione testo arbitraria. Supporta `--replace-text` (regex),
  `--message-callback`, `--dry-run`; rifiuta repo non-fresh-clone di default.
- **`gitleaks` ASSENTE** sull'ambiente (`command -v gitleaks` → vuoto). → La skill **non può
  dipendere** da gitleaks; deve degradare con grep custom (vedi D3).
- **`git` PRESENTE** (`/usr/bin/git`).
- **Manifest schema live = `1.0|1.1`** (`manifest-validate.sh` riga 29:
  `^manifest_schema_version: "(1\.0|1\.1)"$`; `VALID_STEPS` righe 57-72). Lo schema 1.1 è
  retrocompat 1.0. Precedente di bump retrocompat: ADR-0008 (1.0→1.1), ADR-0010 (1.1→1.2 —
  vedi nota di coesistenza in D1).
- **Chain `concept-to-code`**: 16 stati; Gate 0 è un *check* in `step_0_init` (non uno stato);
  Gate 1/1b/2/3/4/5 esistenti. `coder.md` NON ha alcuna regola "modalità anonima"; redige un
  Conventional Commit per l'orchestrator (riga 23/76) ma non lo committa mai.
- **Baseline harness vivi** (eseguiti 2026-05-23): review-triage-fix **60**, concept-to-code
  **20**, design-brainstorm 9, refactor-snapshot 18, vibe-status 10,
  pre-flight-pattern-enforce 13, run-hook-tests 24, db-backup-guardrail 16. Tutti `FAIL=0`.

### Assunzioni esplicite (NON validate — la feature poggia su queste)

- **Detection completa del remote pubblico richiede una API call autenticata**
  (`gh repo view --json visibility`). Senza `gh` o senza auth, la visibilità di un remote
  GitHub **non è determinabile in modo affidabile** dal solo URL (un URL `https://github.com/…`
  può puntare a un repo privato). → Decisione fail-safe in D1: se la visibilità non è
  determinabile, NON proporre il gate (silenzioso), per non disturbare su repo privati.
- **L'efficacia del cleanup su una UI/history reale (rewrite, fresh-history publish,
  force-push)** non è testabile headless in modo deterministico: richiede un repo reale con
  remote. Il harness copre solo le parti pure (detection, classificazione, dry-run su fixture
  locale); il resto resta open question validabile solo in pilota (onestà come ADR-0008/0009/0010).
- Il repo `vibe-coding-system` è NON-git: i deliverable di questo ADR sono i 3 markdown
  (ADR + plan + eventuale ARCH). Il deploy degli artefatti live
  (`~/.claude/skills/clean-public-repo/`, patch al chain) è un task separato (plan TDD),
  **senza commit step**.

---

## Decision

Adottare l'**architettura ibrida C★ + D★** del BRAINSTORM:

1. **Modalità anonima nel chain** (prevenzione): un flag `anonymize: true` nel manifest
   (schema **1.2**, retrocompat 1.0/1.1) influenza i **template di dispatch** di
   architect/coder e i recap dei gate. Attivato da un **gate dedicato "Gate 0b — anonymize"**,
   condizionale, dopo Gate 0 e prima di Step 1.
2. **Skill standalone `clean-public-repo`** (rimedio): audit + cleanup di un repo nuovo o
   esistente. **Azione ibrida** (segnala → rimuove solo su conferma). Strategie per la history:
   **fresh-history publish (default per i già-pubblici)** e **rewrite chirurgico (opzione 2,
   mai default)**. Detection via **grep custom** (set di marcatori dello strumento) con
   gitleaks come **integrazione opzionale** se presente.
3. **Riuso, non duplicazione:** il chain NON contiene logica di cleanup; per i repo esistenti
   rimanda alla skill (single source of truth, pattern Gate 1b→design-brainstorm,
   Step 6→review-triage-fix, Gate 6→web-e2e-test — 4a istanza).

Di seguito la decisione per ciascuna delle 8 domande architetturali.

### D1 — Dove innestare il gate: **Gate 0b dedicato**, auto-detect via `gh` con fail-safe, flag `anonymize` nel manifest

**Gate dedicato "Gate 0b — anonymize"**, NON estensione di Gate 0. Razionale: Gate 0 ha una
semantica precisa e ortogonale (triage chain-vs-leggero); sovraccaricarlo con l'anonimato
mescolerebbe due decisioni indipendenti e renderebbe i due check non disattivabili
separatamente. Gate 0b è un check condizionale in `step_0_init` (come Gate 0 — non è uno
stato della state machine), eseguito **dopo** Gate 0 (`[c] chain`) e **prima** della
transizione a `step_1_interview`.

**Auto-detect del remote pubblico** (cascata, helper `scripts/detect-public-remote.sh`):
1. `git rev-parse --is-inside-work-tree` → se non-git → **silenzioso** (no gate). Default sicuro.
2. `git remote get-url origin` (e altri remote) → se nessun remote → **silenzioso**.
3. Host = `github.com` (o `git@github.com:`)? Se no (GitLab/Bitbucket/host privato) → **silenzioso**
   (lo scope SPEC R1 è GitHub; estendibile in futuro).
4. Visibilità: se `gh` è presente e autenticato →
   `gh repo view <owner/repo> --json visibility -q .visibility`. `PUBLIC` → proponi gate.
   `PRIVATE`/`INTERNAL` → **silenzioso**.
5. Se `gh` assente o non autenticato → **visibilità non determinabile** → **silenzioso**
   (fail-safe verso "non proporre": meglio non disturbare su un repo privato che esporre la
   modalità su un repo che non è pubblico). Lo SPEC R1 dice "silenzioso su privati/locali":
   l'indeterminato è trattato come "non-pubblico" per non violare quella garanzia.

La modalità resta una **decisione utente** (`[y/n]`), mai auto-applicata (SPEC R1).

**Forma del flag:** `anonymize: true|false` nel manifest (schema **1.2**), default `false`.
Influenza i **template di dispatch** (D7), non il SKILL.md degli agent. È un dato di stato del
chain, coerente con `mode`/`gate0`/`brainstorm` già nel manifest.

### D2 — Forma di `clean-public-repo`: **skill standalone + script bash 3.2**, dipendenze esterne opzionali con degrade graceful

**Skill standalone** `~/.claude/skills/clean-public-repo/` (SKILL.md procedurale orchestrator
+ `scripts/` bash 3.2-clean + `tests/run-tests.sh`). Invocabile a richiesta (SPEC R6) e
**riusata** dal chain solo come *raccomandazione* (il chain non fa cleanup retroattivo — vedi
D7). Soggetto = **orchestrator**: le operazioni git distruttive richiedono HITL interattivo;
un sub-agent in auto mode non deve poterle eseguire (coerente ADR-0010 D1, ADR-0009).

**Dipendenze esterne e gestione dell'assenza (vincolo HARD — verificato: gitleaks assente):**

| Dipendenza | Uso | Se ASSENTE |
|---|---|---|
| `git` | core (sempre) | la skill non può operare su una history → degrada ad audit dei soli file working-tree + commit-message via `git log` se presente; se proprio assente, dichiara "non-git" e termina senza errore (SPEC edge "branch detached / non-git → degrada senza errori"). |
| `git-filter-repo` | rewrite chirurgico (opzione 2) | **presente** sull'ambiente, ma la skill **verifica sempre** `command -v git-filter-repo`. Se assente → la strategia rewrite è **disabilitata** con messaggio install (`brew install git-filter-repo` o `pip3 install git-filter-repo`); fresh-history publish (che usa solo `git` core) resta disponibile. |
| `gitleaks` | detection secret bonus + cross-check stringhe | **assente** sull'ambiente. La skill funziona **senza** gitleaks (grep custom è la detection primaria — D3). Se presente, lo usa come **integrazione opzionale** (genera `.gitleaks.toml` custom + parsa JSON) e lo annota nel report; se assente → nessun errore, nota "gitleaks non installato: detection lessicale via grep (secret-scanning bonus non disponibile; install: `brew install gitleaks`)". |
| `gh` | detection visibilità remote (D1) + eventuale creazione repo derivato (D5) | se assente/non auth → D1 silenzioso; D5 degrada a istruzioni manuali (l'utente crea il repo su GitHub e fornisce l'URL). |

Principio: **una dipendenza assente non blocca mai il percorso minimo** (grep custom +
fresh-history via git core). Le dipendenze migliorano la copertura, non la abilitano.

### D3 — Detection: **grep custom (primario) sul set di marcatori SPEC R3** + gitleaks opzionale; report con copertura e LIMITI

Detection **lessicale via grep custom** come motore primario (zero-dep, bash 3.2-clean,
stack-agnostico). Set di pattern derivato da SPEC R3, su due superfici:

- **Working tree (file tracciati):** `git ls-files` → per ogni file di testo, grep dei pattern:
  - Trailer/marcatori commit residui nei file: `Co-Authored-By: Claude`, `Generated with Claude Code`.
  - Commenti-traccia: `// added by Claude`, `# generated by`, riferimenti a task/AI, TODO
    chiaramente generati (pattern conservativi, vedi falsi positivi sotto).
  - Stringhe `claude` / `AI` + emoji decorative non richieste (range emoji + parola chiave).
  - File slop / inutili: euristica su nomi (`scratch`, `notes`, `*-COPY`, README ridondanti) →
    **segnalati, mai rimossi d'ufficio** (R2).
- **Commit history (messaggi):** `git log --format=%B` → stessi pattern trailer/marcatori.

**gitleaks opzionale:** se presente, generato un `.gitleaks.toml` con regole custom per i
marcatori dello strumento (oltre alle regole secret native), output JSON parsato e **unito** al
report grep. È un cross-check + il secret-scanning bonus (annotato come future nello SPEC, qui
solo se gitleaks c'è). **Mai requisito.**

**Falsi positivi (SPEC edge):** dipendenze legittime (`claude-*` come nome pacchetto), `AI` in
un dominio/nome proprio. → La detection **segnala con contesto** (path:linea + match), non
rimuove (R2). La rimozione è sempre su-conferma per categoria/elemento.

**Copertura e LIMITI nel report (requisito emerso nel BRAINSTORM, vincolante):** il report
DEVE dichiarare esplicitamente cosa **NON** copre, per evitare falso senso di sicurezza:
binari, immagini, file generati/minificati, metadati git (autore/committer date già OK perché
non falsifichiamo autori), tracce semantiche non lessicali (stile di scrittura), contenuto in
file non tracciati / `.gitignore`d. Vedi D4.

### D4 — Contratto del report (azione ibrida): markdown `docs/clean-report/<date>-<topic>.md`, categorie R3, sezione COPERTURA/LIMITI obbligatoria

La skill scrive **un report** in `<project-root>/docs/clean-report/YYYY-MM-DD-<slug>.md`
(crea la dir se assente). Struttura (intestazioni inglese, prosa italiano — coerente con il
sistema):

- **Header:** data, repo path, remote+visibilità (o "non determinabile"), strategia history
  proposta (fresh-history publish | rewrite chirurgico | nessuna), esito audit
  (`ready` | `da-pulire`).
- **Findings per categoria R3:** per ciascuna (trailer commit, commenti-traccia, file slop/doc
  gonfi, stringhe claude/AI+emoji, altro residuo) → lista `path:linea — match — categoria`,
  e per i commit `<sha-corto> — riga del messaggio`. Ogni finding marcato
  `auto-removable` (rimozione testuale sicura) | `review-needed` (possibile falso positivo:
  dipendenza/nome) | `manual` (file slop: decisione umana).
- **Strategia history (se ci sono tracce nei commit):** raccomandazione fresh-history (default
  se già-pubblico) vs rewrite chirurgico (opzione 2), con i requisiti di safety (D6).
- **COPERTURA & LIMITI (sezione obbligatoria):** cosa è stato scansionato (file di testo
  tracciati + messaggi di commit) e **cosa NON** (binari, generati, metadati, tracce
  semantiche, file non tracciati). Dichiarazione esplicita: "questo audit riduce i marcatori
  lessicali noti; NON garantisce l'indistinguibilità totale e NON sostituisce una revisione
  umana".
- **Azioni proposte:** elenco confermabile per categoria (`[y]` rimuovi auto-removable / `[s]`
  salta / dettaglio per-elemento). **Nessuna rimozione cieca** (R2).

Esito `ready` quando zero finding `auto-removable` residui dopo un cleanup confermato (SPEC DoD).

### D5 — Fresh-history publish (default per già-pubblici): repo pubblico derivato, history originale privata

Flusso (helper `scripts/fresh-history-publish.sh` — guida + dry-run; le azioni mutanti dietro
HITL):
1. **Backup obbligatorio** della `.git/` originale: `tar -czf .git-backup-<ts>.tar.gz .git`
   (best practice researcher; SPEC R5). Mai procedere senza.
2. **Cleanup del working tree** sui finding `auto-removable` confermati (D4) → commit pulito
   nel branch corrente (NON ancora pubblicato).
3. **Orphan branch:** `git checkout --orphan public-clean` → `git add -A` →
   un singolo commit curato (`git commit`), messaggio essenziale (modalità anonima D7). La
   history di sviluppo (con tracce) **resta intatta** sul branch originale, **privata**.
4. **Pubblicazione del derivato:** preferibilmente come **nuovo repo pubblico** (l'utente lo
   crea su GitHub; se `gh` presente e autorizzato, `gh repo create` su conferma) con remote
   dedicato; push del solo `public-clean`. **Nessun force-push sul repo originale** → nessun
   buco sospetto, nessun rischio di corruzione (BRAINSTORM Alternativa D, rischio TOP mitigato).
5. La history originale privata non viene mai toccata distruttivamente.

Default per i repo **già pubblici** perché evita del tutto il force-push (l'azione più rischiosa).

### D6 — Rewrite chirurgico (opzione 2, mai default): `git-filter-repo` con clone fresco + backup tar + dry-run + HITL prima del force-push

Solo come **seconda scelta esplicita** (l'utente lo richiede deliberatamente), per il caso
"esistente non-ancora-pubblico" o quando si vuole preservare la granularità storica. Flusso
(helper `scripts/surgical-rewrite.sh` — orchestratore di safety, mai automatico):
1. **Pre-condizione fresh-clone:** `git-filter-repo` di default rifiuta un repo non-fresh-clone;
   la skill lo rispetta e **istruisce** l'utente a operare su un clone fresco (mai sul working
   repo). Non passa `--force` per aggirare la protezione.
2. **Backup tar obbligatorio** della `.git/` prima di qualunque operazione (SPEC R5; researcher).
3. **Dry-run sempre prima:** `git filter-repo --replace-text <patterns> --dry-run` (+
   `--message-callback` per i trailer) → mostra cosa cambierebbe (SPEC R5: "dry-run mostra cosa
   cambierebbe").
4. **Backup branch/tag automatico** prima dell'applicazione (SPEC R5).
5. **Applicazione** del rewrite sul clone.
6. **Force-push SOLO dopo HITL esplicito** (`AskUserQuestion` / box di conferma): è un'azione
   distruttiva remota (rompe cloni/fork). **Mai automatico, mai da sub-agent.** Coerente con
   `db-backup-guardrail` (ADR-0009): un'operazione irreversibile sta dietro un gate umano.

Il SKILL.md dichiara che il rewrite chirurgico è opt-in e che fresh-history è il default per i
già-pubblici.

### D7 — Modalità anonima nel chain: via **template di dispatch** (no patch a coder.md/architect.md), coexistenza con la regola coder esistente

Quando `manifest.anonymize=true`, il chain **estende i prompt-template di dispatch** (NON
modifica i SKILL.md degli agent — stesso pattern della direttiva additiva di
`claude-md-generator`, concept-to-code §3 Step 3). Concretamente:

- **Dispatch coder (Step 5):** il template aggiunge un blocco "Anonymize mode active":
  - Commit message Conventional **corti ed essenziali** (subject + body minimale, niente
    narrazione, niente trailer di strumento — già nativamente off via `settings.json`, ribadito).
  - **Nessun commento-traccia** nel codice (`// added by Claude`, riferimenti a task/AI, TODO
    generati): scrivere solo commenti che un autore umano scriverebbe.
  - **Nessun file slop** (README ridondanti, scratch): solo i file richiesti dal plan.
  - **Nessuna emoji decorativa** non richiesta; doc concisi.
- **Dispatch architect (Step 2):** il template chiede ADR/plan **concisi**, senza meta-commenti
  sullo strumento. (L'architect scrive solo doc, non codice; il vincolo è di stile/concisione.)
- **Recap dei gate:** invariati nella forma, ma il box mostra `Anonymize: ON` per trasparenza.

**Coexistenza con `coder.md` (verificato: nessuna regola anonima oggi):** il coder già redige
un Conventional Commit per l'orchestrator e non committa mai (riga 23/76). La modalità anonima
**non contraddice** il Pre-flight Pattern Classifier (ADR-0001) né nessuna regola esistente:
aggiunge solo vincoli di output (concisione, no-traccia) veicolati nel prompt, non nel SKILL.md.
Quando `anonymize=false` (default), i template restano **identici a oggi** → zero regressioni
sul comportamento corrente del chain. La modalità anonima è puramente **additiva e opt-in**.

### D8 — Safety / fail-mode: ogni operazione distruttiva dietro HITL esplicito + backup; harness honesto

- **HITL su ogni operazione distruttiva** (rewrite, force-push, eliminazione file): mai
  automatica, mai da sub-agent (coerente regola globale "HITL gate prima di eliminazioni
  permanenti / push" e ADR-0009). La skill **propone**, l'utente **conferma**.
- **Backup before destructive** (regola globale "backup prima di file critici"): tar della
  `.git/` prima di rewrite/fresh-history; backup branch/tag prima del rewrite (SPEC R5).
- **Dry-run before apply** (SPEC R5): rewrite mostra il diff atteso prima di applicare.
- **Auto mode classifier:** se il chain gira in auto mode e tenta un force-push, il classifier
  di Claude Code chiederà comunque conferma su un'operazione distruttiva — coerente con la
  scelta (vincolo §8 del dispatch). La skill non aggira questo comportamento.
- **Harness (testabilità honesta):** il harness `clean-public-repo/tests/run-tests.sh` (bash
  3.2-clean, target dichiarato nel plan) verifica SOLO ciò che è puro e deterministico:
  structural anchor sullo SKILL.md (sezioni contratto + "orchestrator-only" + "no falsificazione
  autori" + sezione LIMITI documentata), smoke di `detect-public-remote.sh` (non-git → silenzioso;
  remote non-github → silenzioso; nessun remote → silenzioso) su fixture `mktemp -d`, e smoke
  della detection grep su una fixture con marcatori noti (trova i pattern attesi, NON trova un
  `claude-foo` dipendenza marcato come review-needed). **NON è verificabile headless:** il
  rewrite reale, il fresh-history publish reale, il force-push, l'integrazione gitleaks/gh su un
  remote vero → restano **open question, validabili solo in pilota** con un repo reale (onestà
  come ADR-0008/0009/0010). Mai mockare l'intera sessione git (testerebbe il mock).

---

## Alternatives considered (per ognuna delle 8 domande)

Le alternative di approccio architetturale provengono dal BRAINSTORM (A/B/C/D); per le
sotto-decisioni si elencano le opzioni scartate con la ragione.

### Approccio globale (dal BRAINSTORM)

- **Alternativa A — solo prevenzione (clean-by-construction):** rifiutata come architettura
  completa. Copre i repo nuovi a costo zero, ma **non copre gli esistenti** (es. plugin
  Obsidian già pubblicato) che sono esplicitamente in scope (SPEC R6). Adottata come *parte*
  dell'ibrido (modalità anonima nel chain).
- **Alternativa B — solo rimedio (scan + scrub on-demand):** rifiutata come architettura
  completa. Copre gli esistenti, ma i repo nuovi accumulerebbero tracce da ripulire a ogni
  giro (lavoro ripetuto evitabile). Adottata come *parte* dell'ibrido (skill standalone).
- **Alternativa C — ibrido prevenzione+rimedio ★:** **adottata**. Ogni caso usa l'approccio
  giusto (nuovi→A, esistenti→B); copre l'intero scope SPEC. Contro accettato: due superfici da
  mantenere (mitigato dal riuso — il chain non duplica la skill).
- **Alternativa D — fresh-history publish ★:** **adottata** come strategia di **default per i
  già-pubblici** (D5). Evita del tutto il force-push sul repo originale (rischio TOP del
  pre-mortem). Contro accettato: si perde la granularità storica nel pubblico (compensato dal
  rewrite chirurgico come opzione 2 per chi la vuole).

### D1 — Dove innestare il gate

- **Estendere Gate 0 (triage chain-vs-leggero):** rifiutata. Mescola due decisioni ortogonali
  (chain-vs-leggero vs anonimo-sì/no) in un unico prompt; rende impossibile presentare l'una
  senza l'altra e confonde l'UX. Gate 0b dedicato è più chiaro e disattivabile separatamente.
- **Auto-applicare la modalità anonima su ogni remote GitHub pubblico (no `[y/n]`):** rifiutata.
  Viola SPEC R1 ("decisione utente, non auto-applicata") e l'inquadramento etico (la modalità
  è una scelta consapevole dell'utente, non un default imposto).
- **Detection visibilità dal solo URL del remote (no `gh`):** rifiutata. Un URL
  `github.com/...` non rivela la visibilità (può essere privato); dedurre "pubblico" dall'URL
  causerebbe falsi positivi che disturbano su repo privati (viola R1 "silenzioso su privati").
  La cascata usa `gh` e tratta l'indeterminato come non-pubblico (fail-safe).

### D2 — Forma della skill / dipendenze

- **Rewriter custom in bash (no git-filter-repo):** rifiutata. Riscrivere una history a mano è
  error-prone e rischioso (rischio TOP); `git-filter-repo` è lo standard maturo con dry-run e
  protezioni (report researcher). Non reinventare un tool critico per la sicurezza dei dati.
- **Dipendenza HARD da gitleaks per la detection:** rifiutata — **gitleaks è assente
  sull'ambiente** (verificato). Renderebbe la skill inutilizzabile out-of-the-box. La detection
  primaria deve essere grep custom (zero-dep); gitleaks è un bonus opzionale.
- **Sub-agent dedicato per il cleanup:** rifiutata. Le operazioni git distruttive richiedono
  HITL interattivo; un sub-agent in auto mode non deve eseguirle (coerente ADR-0010 D1 /
  ADR-0009). La skill gira sull'orchestrator.

### D3 — Detection

- **Detection semantica/ML (riconoscere "stile AI"):** rifiutata. Fuori scope, non
  deterministica, non bash 3.2-clean; il bisogno irriducibile (BRAINSTORM first-principles) è
  rimuovere **marcatori lessicali noti**, non indovinare lo stile.
- **Solo gitleaks (no grep custom):** rifiutata. gitleaks è secret-oriented e assente
  sull'ambiente; i marcatori dello strumento (trailer, commenti, emoji) non sono il suo target
  primario e richiederebbero comunque regole custom. grep custom è il motore giusto e
  zero-dep.
- **Rimozione automatica di tutti i match (no conferma):** rifiutata. Viola SPEC R2 ("mai
  rimozione cieca") e il caso falso-positivo (dipendenza `claude-*`). L'azione è ibrida:
  segnala → rimuove su conferma.

### D4 — Contratto del report

- **Report senza sezione LIMITI:** rifiutata. È il requisito esplicito emerso nel BRAINSTORM
  (falso senso di sicurezza): un report che non dichiara cosa NON copre (binari, metadati,
  generati) induce l'utente a credere il repo "pulito al 100%". La sezione COPERTURA & LIMITI
  è obbligatoria.
- **Output solo in chat (nessun file):** rifiutata. Un audit di pulizia va persistito per
  revisione umana e per ri-esecuzione; il file è il record dell'azione confermata.
- **Cancellare i file slop d'ufficio:** rifiutata. SPEC R2 + edge falso-positivo: i file slop
  sono segnalati come `manual`, la decisione resta umana.

### D5 — Fresh-history publish

- **Force-push sul repo originale (rewrite in-place come default per i già-pubblici):**
  rifiutata come default. È il rischio TOP del pre-mortem (corrompe/perde il repo, rompe
  cloni/fork, è visibile e sospetto). Default = repo derivato; rewrite in-place solo opzione 2
  esplicita (D6).
- **Riscrivere la history del repo originale e renderla privata:** rifiutata. Più complessa e
  rischiosa del semplice orphan branch + repo derivato; non c'è motivo di toccare l'originale.
- **Squash interattivo manuale (no orphan):** rifiutata come meccanismo. L'orphan branch è
  idiomatico e deterministico (report researcher); il rebase interattivo è manuale, error-prone
  e non automatizzabile in modo sicuro.

### D6 — Rewrite chirurgico

- **`git filter-branch`:** rifiutata. **DEPRECATO** (report researcher), lento, error-prone;
  la doc git stessa raccomanda `git-filter-repo`.
- **BFG Repo-Cleaner:** rifiutata. Ottimo per blob grandi/secret noti, ma **non adatto a
  sostituzione testo arbitraria** dei marcatori (report researcher); `git-filter-repo
  --replace-text` copre il caso.
- **Rewrite automatico senza dry-run / senza fresh-clone:** rifiutata. Viola SPEC R5 e il
  rischio TOP; la protezione fresh-clone di git-filter-repo va rispettata, non aggirata con
  `--force`.

### D7 — Modalità anonima nel chain

- **Patchare `coder.md`/`architect.md` con la regola anonima:** rifiutata. Renderebbe la regola
  globale e sempre-attiva (anche fuori dal chain, anche su repo privati), e creerebbe un
  "vecchio contract da deprecare". Il pattern del sistema è veicolare le direttive condizionali
  nel **prompt-template di dispatch** (come la direttiva additiva di claude-md-generator):
  additivo, opt-in, zero regressioni quando off.
- **Layer separato (post-processing dei commit dopo il coder):** rifiutata. Un post-processor
  che riscrive i commit appena fatti è di fatto un mini-rewrite (rischio) per qualcosa che si
  ottiene gratis facendo scrivere bene il coder dall'inizio (prevenzione = Alternativa A). Meglio
  clean-by-construction.
- **Normalizzazione stilistica per ingannare review umane:** rifiutata — **fuori scope per
  vincolo etico** (SPEC §"Inquadramento etico", out-of-scope). La modalità rimuove marcatori e
  cura la qualità; non maschera la natura del lavoro a chi chiede.

### D8 — Safety / fail-mode

- **Force-push automatico in auto mode:** rifiutata. Operazione distruttiva remota irreversibile;
  va sempre dietro HITL (coerente ADR-0009, regola globale). L'auto mode non esenta dal gate
  umano sulle operazioni distruttive.
- **Nessun backup prima del rewrite:** rifiutata. Viola SPEC R5 e la regola globale "backup
  prima di file critici"; senza backup il rischio TOP non è mitigabile.
- **Harness end-to-end con un repo git reale + remote:** rifiutata. Richiederebbe un remote
  GitHub reale, force-push reali, e comunque non sarebbe deterministico/headless. Il harness
  copre le parti pure (detection, fail-safe della detection-remote); il resto è open question da
  pilota (onestà ADR-0008/0009/0010). Mai mockare l'intera sessione git.

---

## Consequences

### Positive

- **Copre l'intero scope SPEC:** nuovi (prevenzione via modalità anonima) + esistenti (rimedio
  via skill), con la strategia history giusta per ogni caso.
- **Rischio TOP mitigato by design:** il default per i già-pubblici (fresh-history publish) evita
  del tutto il force-push sul repo originale; il rewrite chirurgico in-place è opt-in con
  backup+dry-run+HITL. Nessun rewrite distruttivo non protetto (priorità #1).
- **Zero-dep out-of-the-box:** la skill funziona con solo `git` (presente); gitleaks/gh
  migliorano la copertura ma non sono richiesti (verificato: gitleaks assente).
- **Riuso pulito:** il chain non duplica la logica di cleanup; la modalità anonima è additiva
  via prompt-template (zero regressioni quando off). 4a istanza del pattern skill-standalone +
  gate del chain.
- **Trasparenza etica:** il report dichiara COPERTURA & LIMITI (no falso senso di sicurezza); la
  feature non falsifica autori (commit resta attribuito a Stefano).
- **Detection con contesto:** falsi positivi (`claude-*` dipendenze, "AI" in nomi) marcati
  `review-needed`, mai rimossi ciecamente (SPEC R2).

### Negative

- **Due superfici da mantenere** (modalità anonima nel chain + skill standalone) — costo
  accettato dell'ibrido, mitigato dal non-duplicare (il chain rimanda alla skill).
- **Detection lessicale limitata:** grep custom non cattura tracce semantiche/stilistiche né
  marcatori in binari/generati. Limite dichiarato nel report (LIMITI); NON garantisce
  indistinguibilità totale.
- **Visibilità remote indeterminabile senza `gh`:** su un ambiente senza `gh` autenticato il
  Gate 0b non si attiva mai (fail-safe verso silenzioso) → la prevenzione automatica non parte;
  l'utente può comunque attivarla a mano o usare la skill. Trade-off conservativo accettato.
- **Operazioni history reali non testabili headless:** rewrite/fresh-history/force-push
  validabili solo in pilota; il harness copre solo le parti pure. Limite noto (ADR-0008/0009/0010).
- **Dipendenza da `git-filter-repo` per l'opzione 2:** se rimosso dall'ambiente, il rewrite
  chirurgico si disabilita (degrade graceful con messaggio install); fresh-history resta
  disponibile.

### Neutral

- **Manifest schema 1.2:** nuovo campo opzionale `anonymize: false` (default); 1.0/1.1 restano
  validi (retrocompat additiva). `manifest-validate.sh` va esteso ad accettare 1.2.
  **Nota di coesistenza:** ADR-0010 (web-e2e-test) ha già pianificato un bump 1.1→1.2
  (`artifacts.e2e` + stato `gate_6_e2e_web`). Se ADR-0010 è deployato prima, questo ADR riusa lo
  schema 1.2 esistente e aggiunge SOLO il campo `anonymize` (additivo, nessun nuovo stato — Gate
  0b è un check, non uno stato); se ADR-0010 non è ancora deployato, questo ADR introduce 1.2 con
  `anonymize`. In entrambi i casi 1.2 resta retrocompat 1.0/1.1; il plan verifica lo stato live
  dello schema prima di editare la regex (vedi plan, Note di coesistenza).
- **Nuova convenzione `docs/clean-report/`** per i report; opzionale, creata on-demand.
- **Gate 0b non è uno stato** della state machine (come Gate 0): è un check condizionale in
  `step_0_init`. Nessun nuovo stato → nessuna estensione di `VALID_STEPS`/transition pairs per
  il gate (solo il campo `anonymize`).
- Repo `vibe-coding-system` NON-git: i deliverable sono i markdown; il deploy degli artefatti
  live (`~/.claude/skills/clean-public-repo/`, patch al chain) è un task separato (plan TDD),
  senza commit step.

---

## References

- SPEC: `/Users/stefanoferri/Developer/vibe-coding-system/SPEC.md` (R1-R6, edge case, DoD,
  inquadramento etico)
- BRAINSTORM: `/Users/stefanoferri/Developer/vibe-coding-system/BRAINSTORM.md` (Alternative
  A/B/C★/D★, pre-mortem rischio TOP, requisito COPERTURA & LIMITI)
- ADR-0003 — `docs/architecture/ADR-0003-concept-to-code-chain.md` (chain + manifest YAML + gate HITL)
- ADR-0008 — `docs/architecture/ADR-0008-concept-to-code-workflow-v2-brainstorm.md` (gate
  opzionale + skill non-terminale invocata dal chain; schema 1.0→1.1; harness honesto)
- ADR-0010 — `docs/architecture/ADR-0010-web-e2e-test.md` (pattern skill-standalone + gate;
  schema 1.1→1.2; detection fail-safe verso default sicuro; testabilità honesta non-headless)
- ADR-0009 — `docs/architecture/ADR-0009-db-backup-guardrail.md` (HITL su operazione
  distruttiva; backup come precondizione; fail-mode asimmetrico)
- ADR-0001 — `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (la modalità
  anonima coesiste col Pre-flight Pattern Classifier, non lo contraddice)
- `~/.claude/skills/concept-to-code/SKILL.md` (state machine; pattern gate→skill riuso;
  direttiva additiva via prompt-template — §3 Step 3)
- `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` (schema regex riga 29,
  VALID_STEPS righe 57-72)
- `~/.claude/agents/coder.md` (nessuna regola anonima oggi; redige commit per l'orchestrator,
  non committa — coexistenza D7)
- Prior-art tooling (report researcher): `git-filter-repo` (standard rewrite chirurgico,
  `--replace-text`/`--message-callback`/`--dry-run`, rifiuta non-fresh-clone; install
  `brew install git-filter-repo` / `pip3 install git-filter-repo`); `git filter-branch`
  DEPRECATO; BFG non adatto a testo arbitrario; `git checkout --orphan` per fresh-history;
  `gitleaks` per detection (regole custom `.gitleaks.toml`, output JSON) — opzionale qui;
  backup `tar -czf` di `.git/` + `--dry-run` come safety best practice.
- `feedback_bash32-constraint` (harness + script bash 3.2-clean)
- Fatti ambiente verificati 2026-05-23: `git-filter-repo` presente (`/opt/homebrew/bin`),
  `gitleaks` assente, baseline harness (review-triage-fix 60, concept-to-code 20, ecc.)
