# Guida operativa all'uso delle chain e skill del Vibe Coding System

> Aggiornata al 2026-06-18. Companion italiano di `docs/SKILLS-AND-AGENTS-GUIDE.md` (EN).
> Quella guida è per lettori esterni; questa è il riferimento operativo di Stefano.
> Copre l'intero ecosistema custom: chain, skill standalone, agenti, hook.

---

## 1. Modello mentale

Il sistema ha quattro livelli che operano in maniera indipendente ma coordinata.

**Chain orchestratrici** (`concept-to-code`, `project-conductor`, `autopilot-build`) sono
workflow multi-step con stato persistente su un file manifest YAML. Gestiscono gate HITL,
dispatchano agenti, producono artefatti (SPEC.md, ADR, CLAUDE.md). Hanno una macchina a stati
esplicita e sono riprendibili tra sessioni.

**Skill standalone** (`/skill <nome>`) sono operazioni singole con un contratto di ingresso e
uscita definito. Non hanno stato persistente tra sessioni. Alcune hanno gate HITL interni,
nessuna lancia altre skill senza che tu lo sappia.

**Agenti** (`architect`, `coder`, `reviewer`, ...) sono sub-agent dispatchati dall'orchestratore
o dalle chain. Di norma non li invochi direttamente: le chain li chiamano al momento giusto.
Puoi però chiederli esplicitamente in chat ("debugga questo crash", "rivedi il codice appena scritto").

**Hook** (`stop-gate.sh`, `pre-flight-pattern-enforce.sh`, `db-backup-guardrail.sh`, ...) sono
automazioni deterministiche che girano su ogni tool call. Sempre attivi, non disattivabili
durante una sessione. Non li invochi tu: intervengono da soli.

**Regola generale:** per una nuova feature non banale usa una chain. Per un'operazione puntuale
(commit, review, refactor, audit) usa la skill o l'agente corrispondente. Per controllare il
sistema usa `vibe-status`.

---

## 2. Riferimento rapido

| Bisogno | Strumento | Invocazione |
|---|---|---|
| Nuova feature complessa (design + impl) | `concept-to-code` | `/skill concept-to-code <titolo>` |
| Nuova feature piccola/prototipo | `concept-to-code express` | `/skill concept-to-code express <titolo>` |
| Nuova feature media (1-2 layer) | `concept-to-code hybrid` | `/skill concept-to-code hybrid <titolo>` |
| Riprendere impl dopo session boundary | `concept-to-code resume` | `/skill concept-to-code resume <manifest>` |
| Progetto multi-feature da PROJECT.md | `project-conductor` | `/skill project-conductor` |
| Impl non presidiata di feature approvata | `autopilot-build` | `/skill autopilot-build <manifest>` |
| Commit con messaggio Conventional | `commit` | `/skill commit` |
| Review + fix completo in un ciclo | `review-triage-fix` | `/skill review-triage-fix` |
| Audit + fix regressione-safe intera codebase | `deep-refactor` | `/skill deep-refactor` |
| Nuova repo git + GitHub | `git-repo-init` | "nuova repo", "crea repository", ecc. |
| Bootstrap CLAUDE.md progetto esistente | `project-init` | `/skill project-init` |
| Health check del sistema | `vibe-status` | `/skill vibe-status` |
| Pulizia tool-markers prima di pubblicare | `clean-public-repo` | `/skill clean-public-repo` |
| Rimuovere AI tells da prosa EN | `humanize-en` | `/skill humanize-en <file o testo>` |
| Slim CLAUDE.md in path-scoped rules | `claude-md-slim` | `/skill claude-md-slim [--global]` |
| Design UX macOS / HIG review SwiftUI | `macos-ux` | `/skill macos-ux` / `/skill macos-ux review` |
| Audit layout SwiftUI / HTML/CSS | `ui-layout-audit` | `/skill ui-layout-audit [file]` |
| Esplorare approcci prima dell'architettura | `design-brainstorm` | `/skill design-brainstorm` |
| Scrivere un ADR | `adr-writer` | `/skill adr-writer <argomento>` |
| Root cause di un errore runtime | `debugger` (agente) | "debugga questo errore" in chat |
| Review del codice appena scritto | `reviewer` (agente) | "rivedi il codice modificato" |

---

## 3. Le chain orchestratrici

### 3.1 concept-to-code

La chain principale. Gestisce il ciclo completo: interview, design, ADR, CLAUDE.md, session
boundary, implementazione, review, commit. Dalla versione con schema manifest 1.3 (ADR-0017)
esistono tre path distinti, ciascuno con la sua macchina a stati.

#### Invocazione

**Form A — avvia nuova chain:**
```
/skill concept-to-code <titolo>
/skill concept-to-code express <titolo>
/skill concept-to-code hybrid <titolo>
/skill concept-to-code standard <titolo>
```

Se il primo termine è `express`, `hybrid` o `standard`, il path viene forzato e Gate 0 viene
saltato. Altrimenti Gate 0 mostra una raccomandazione automatica e ti chiede di scegliere.

**Form B — riprendi dopo session boundary:**
```
/skill concept-to-code resume docs/manifests/YYYY-MM-DD-<slug>.manifest.yml
```
Valida solo per il path Standard (o manifest legacy senza `chain_path`). Express e Hybrid non
attraversano session boundary: tentare resume su di essi è un errore.

**Form C — annulla la chain:**
```
/skill concept-to-code abort docs/manifests/YYYY-MM-DD-<slug>.manifest.yml
```
Idempotente: imposta `status: aborted`, preserva gli artefatti già prodotti.

#### I tre path: quando usare quale

| Path | Quando usarlo | File stimati | Session boundary | Artefatti prodotti |
|---|---|---|---|---|
| **Express** | Prototipo, script, tool CLI, modifica <10 file | <10 | No (sessione singola) | Manifest |
| **Hybrid** | Feature media, 1-2 layer, requisiti chiari | 5-20 | No (sessione singola) | Manifest + SPEC.md |
| **Standard** | Feature complessa, multi-layer, ADR obbligatorio, brownfield | >20 o complesso | Sì (sessione fresca per impl) | SPEC + ARCH + ADR + Plan + CLAUDE.md |

**Routing auto-detect (quando non si forza il path):** lo script `gate0-detect.sh` analizza la
struttura del progetto e vota per un path. Se SPEC.md e un ADR esistono già (brownfield), forza
Standard. Altrimenti vince la maggioranza tra `file_vote` e `keyword_vote`.

#### Path Express (chain_path=express)

Stato, artefatti, gate:

```
step_0_init
  -> step_e1_plan      (EnterPlanMode, opzionale superpowers)
  -> step_e2_execute   (dispatch coder, worktree isolation)
  -> gate_e3_verify    (AskUserQuestion: Approve / Commit later / Abort)
  -> step_e4_commit    (invoca skill commit)
  -> completed
```

Nota: Express usa `EnterPlanMode` in E1. Questo è l'unico punto in tutta la chain dove plan mode
è permesso; in tutti gli altri step è soppresso. Non attraversa session boundary: tutto gira in
una sessione sola. Se la verifica in gate E3 fallisce puoi scegliere "Commit later" (branch
lasciato aperto) o "Abort".

#### Path Hybrid (chain_path=hybrid)

```
step_0_init
  -> step_h1_interview       (intervista leggera via interview-driver)
  -> gate_h1_spec_review     (review SPEC)
     -> [gate_h1b_brainstorm]  (opzionale: design-brainstorm)
  -> step_h2_plan            (EnterPlanMode, piano dettagliato)
  -> step_h3_execute         (dispatch coder, worktree isolation, max 20 file)
  -> gate_h3_verify          (AskUserQuestion: Approve / Re-run / Abort)
     -> [step_h4_review]       (opzionale: review-triage-fix)
  -> step_h5_commit
  -> completed
```

Limite pratico: se la stima supera 20 file in phase H3 la chain ti avvisa e suggerisce di passare
a Standard. Anche Hybrid non ha session boundary: l'implementazione avviene nella stessa sessione.

#### Path Standard (chain_path=standard)

```
step_0_init
  [Gate 0: routing]
  [Gate 0b: repo pubblica? anonymize flag]
  [Gate 0c: humanize flag]
  [Gate 0d: brownfield auto-detect]
  -> step_1_interview        (interview-driver -> SPEC.md)
  [Gate 1: review SPEC]
  [Gate 1b: design-brainstorm opzionale]
  [Gate 1c: macOS/SwiftUI? invoca macos-ux]
  -> step_2_architecture     (agente architect -> ARCH.md + ADR)
  [Gate 2: review architettura]
  [Gate 2b: proposta test-cmd + TOFU trust]
  -> step_3_project_memory   (claude-md-generator -> CLAUDE.md progetto)
  [Gate 3: review CLAUDE.md + plan]
  -> step_4_session_boundary
  -> ready_for_implementation

  [NUOVA SESSIONE -- usa Form B per riprendere]
  -> step_5_implementation   (dispatch coder, worktree isolation, ultracode se hook_verified=true)
  [Gate 5.05: ui-layout-audit se file UI presenti]
  [Gate 5.06: reviewer specializzato opzionale]
  [Gate 5.1: deep-refactor opzionale]
  [Gate 5.5: humanize-en se anonymize=true]
  -> step_6_review           (review-triage-fix)
  [Gate 5 post-review: Approve / Re-run / Close senza step 7]
  -> step_7_commit           (skill commit)
  -> completed
```

**Session boundary:** dopo Gate 3 la chain salva lo stato nel manifest e si ferma. Apri una
sessione fresca nel progetto (non in vibe-coding-system), poi: `/skill concept-to-code resume
<path-manifest>`. La nuova sessione parte da `ready_for_implementation` e prosegue da Step 5.

**TOFU (Gate 2b):** l'architetto propone il comando di test. Tu lo approvi, viene registrato
con SHA-pin in `~/.claude/state/stop-gate/trust`. In tutte le sessioni successive quella firma
viene verificata prima di eseguire test automatici. Senza TOFU registrato, autopilot-build non
parte.

**ultracode (Step 5):** se nel manifest `hook_verified=true`, lo Step 5 usa il Workflow engine
per dispatchare i coder in parallelo (keyword trigger `ultracode`). Se `hook_verified=false`,
usa Agent-tool in batch da 2-3 task. La scelta è automatica.

#### Gate HITL per path

| Gate | Standard | Hybrid | Express |
|---|---|---|---|
| Gate 0 (routing) | Si | Si | Si (o saltato se forzi path) |
| Gate 0b (anonymize) | Si | Si | No |
| Gate 1 (SPEC review) | Si | Si | No |
| Gate 1b (brainstorm) | Opzionale | Opzionale | No |
| Gate 2 (architettura) | Si | No (H2=EnterPlanMode) | No |
| Gate 2b (test-cmd TOFU) | Si | No | No |
| Gate 3 (CLAUDE.md+plan) | Si | No | No |
| Gate E3/H3 (verify impl) | No | Si | Si |
| Gate 5.x (post-impl) | Opzionale | No | No |
| Gate commit | Sempre (salta con --autopilot) | Sempre | Sempre |

---

### 3.2 project-conductor

Esegue più feature in sequenza: per ogni feature crea un manifest e invoca concept-to-code.
Non ha argomenti: legge tutto da `PROJECT.md` nella root del progetto corrente.

```
/skill project-conductor
```

**Trigger testuali alternativi:** "run all features in sequence", "orchestrate project",
"project conductor".

**PROJECT.md:** se assente, project-conductor avvia un'intervista a 3 round e lo crea.
I marker di stato per ogni feature sono:

| Marker | Significato |
|---|---|
| `- [ ] Feature X` | In attesa, da processare |
| `- [x] Feature X` | Completata (manifest in `completed`) |
| `- [~] Feature X` | Skippata manualmente |

Re-invocare project-conductor riprende automaticamente dalla prima feature `[ ]`, riconciliando
i manifest già completati. Non procede mai a una feature successiva finché quella corrente non è
in `completed` o `aborted`.

---

### 3.3 autopilot-build

Esegue l'implementazione di una feature già approvata (Steps 5-7 di concept-to-code Standard)
senza supervisione umana. Tu avvii, esci, torni a trovare un branch con commit locale e un
report JSON.

```
/skill autopilot-build <path-manifest>
```

Non ha argomenti opzionali. Il manifest deve essere a `current_step: ready_for_implementation`.

#### Autonomy boundary (ADR-0020)

| Azioni consentite non presidiate | Mai non presidiato |
|---|---|
| Implementazione codice (dispatch coder) | `git push` / `git push -u` |
| Esecuzione del test-cmd approvato | Apertura PR, merge |
| Ciclo review + fix | Force-push, cancellazione branch/file |
| Commit locale su feature branch | Modifiche schema DB, deploy |

La skill termina sempre con un commit locale su `type/<slug>`. Push e PR restano a te.

#### Phase 0: 8 controlli pre-flight (tutti read-only)

Qualsiasi fallimento scrive un report `aborted` e si ferma. Nessuna modifica ai file.

1. **Scope guard** (primo, prima di leggere il manifest): `project_root` nel manifest deve
   coincidere con la CWD della sessione, oppure esserne una sottodirectory. In ogni altro caso:
   abort con SCOPE ERROR.
2. **Stato manifest**: `manifest-validate.sh` OK e `current_step == ready_for_implementation`.
3. **Gate 1-3 approvati**: ogni gate deve avere `status: approved` nel manifest.
4. **Artefatti su disco**: `test -f` su SPEC.md, ADR, plan.
5. **Plan con task aperti**: almeno un `- [ ]` nel plan file.
6. **test-cmd reale e TOFU-trusted**: il file `.claude/test-cmd` esiste, non è `NONE`, non è
   placeholder, e la coppia `(SHA, project_root_normalizzata)` è presente nel trust store.
   Se il trust è assente: abort. La skill non registra mai trust da sola: devi averlo fatto in
   un'interattiva precedente (Gate 2b del path Standard).
7. **hook_verified noto**: deve essere `true` o `false`, non null. Se null: abort (esegui prima
   il smoke test manuale per verificare che il pattern-enforce hook funzioni nei subagent).
8. **Git repo presente** nella CWD (`git rev-parse --git-dir`), per abilitare worktree isolation.

#### Phase 1: Steps 5-7 non presidiati

Riusa esattamente la logica di dispatch di concept-to-code Steps 5-7, con gate auto-risolti al
"safe default" senza `AskUserQuestion`.

**Circuit breaker:** dopo Step 5 legge `.claude/step5-report.json`. Se `test_result=RED`,
task falliti, report mancante, `weakening_findings` non vuoto (test indebolito o cancellato,
ADR-0047), o `requirement_coverage.uncovered` non vuoto (ID `R-NN` dichiarati nello SPEC ma non
citati dal piano o non coperti dai test, ADR-0048): si ferma, scrive un report `partial`, non fa
il commit. Stesso meccanismo dopo il re-run di Step 6.

Tutti gli hook di sicurezza restano attivi: `stop-gate.sh`, `pre-flight-pattern-enforce.sh`,
`db-backup-guardrail.sh`. Autopilot sopprime i gate umani, non i guard automatici.

#### Phase 2: Morning report

Scrive sempre `<project_root>/.claude/autopilot-report.json`, su ogni exit path.

Campi chiave: `status` (success/partial/aborted), `abort_reason`, `branch`, `steps` (step5/6/7:
done/failed/not_run), `test_result`, `files_modified`, `commit_sha`, `next_action`.

`next_action` spiega esattamente cosa fare dopo: push del branch, resume interattiva, fix
del problema che ha causato l'abort.

#### Quando NON usare autopilot-build

- Prima che Gate 3 sia approvato (completa il path Standard interattivo fino a `ready_for_implementation`).
- Se TOFU trust è assente (fai un resume interattivo con concept-to-code Form B per approvare il test-cmd).
- Se `hook_verified` è null nel manifest (fai lo smoke test in una sessione interattiva).
- Se sei in una sessione con CWD diversa dal `project_root` del manifest.

---

## 4. Skill standalone operative

### 4.1 commit

Wizard HITL per commit Conventional Commits. Supersede la vecchia `commit-push-pr`.

```
/skill commit [context-hint] [--autopilot]
```

**Fasi:**
1. Verifica stato repo e diff.
2. Legge contesto (CLAUDE.md, manifest, ADR attivi).
3. Genera messaggio Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`).
4. Se il repo è pubblico e `anonymize=true` nel manifest: Gate 3.5 passa il messaggio per `humanize-en`.
5. **Gate HITL:** mostra il messaggio proposto e chiede Approva / Modifica / Abort.
6. Commit, poi opzionale push + apertura PR.

**Flag `--autopilot`:** salta il gate HITL (step 4) e salta push + PR. Usato da
`concept-to-code` e `autopilot-build` quando la pipeline è non presidiata. Non lo usare
manualmente se vuoi il gate di approvazione.

I prefissi seguono sempre la specifica Conventional Commits. Il soggetto è ≤72 caratteri,
imperativo, senza punto finale.

---

### 4.2 review-triage-fix (RTF)

Un singolo ciclo bounded: pre-flight, review del codice, triage delle finding, routing ai fix
agent, re-review, riepilogo, stop. Non fa commit, non fa push, non si itera automaticamente.

```
/skill review-triage-fix
```

**Trigger testuali:** "review and fix", "full review cycle", "triage findings and fix".

**Routing dei finding:** le issue vengono smistate a `debugger` (bug runtime, red test),
`refactorer` (struttura), `coder` (nuove funzionalità mancanti).

**Circuit breaker A:** se un fix provoca una regressione nei test, si ferma immediatamente.

**Verdetti possibili:**

| Verdetto | Significato |
|---|---|
| SAFE | Nessuna issue rilevante trovata |
| RE-RUN | Fix applicati, suggerito un secondo ciclo |
| STOP | Fix impossibili senza decisioni umane |
| UNVERIFIED | Nessun test-cmd configurato: review solo report-only |

**Security findings:** mai auto-fixati, sempre report-only, indipendentemente dal risk level.

Lo stato del ciclo viene salvato in `.claude/.triage-fix-last-<branch>.json` per riferimento.

---

### 4.3 deep-refactor

Audit completo della codebase + fix regressione-safe. Dispatcha 4 agenti reviewer in parallelo
(tutti model opus), poi risolve in sequenza. È pensato per una sessione dedicata: non invocarlo
dentro una chain attiva.

```
/skill deep-refactor
```

**4 dimensioni di audit:**

| Dimensione | Auto-fix? | Note |
|---|---|---|
| `dead-code` | Si (P1 first) | Attenzione: `@objc`/`dynamic`/protocol-witness solo report-only |
| `perf` | Si (P1 first) | Attenzione: `async`/`actor`/`Sendable` solo report-only |
| `structure` | Si (P1 first) | |
| `security` | **Mai** | Sempre report-only, qualunque risk_level |

**Circuit breaker globale (ADR-0018):** il primo RED test ferma TUTTO. Le dimensioni
rimanenti vengono taggate `SKIPPED` nel report. Se il test baseline è già RED o non c'è
test-cmd, entra in report-only mode (nessun fix automatico).

**Output:** `docs/deep-refactor/YYYY-MM-DD-<slug>.md` + commit per dimensione (via skill
`commit`, non push). Gate 1 (review finding) e Gate 2 (approvazione commit) sono HITL.

---

### 4.4 clean-public-repo

Rimuove marker e segni del tool (comment markers, ADR references interne, identifiers) prima
di rendere pubblica una repo o di fare un push su un remote pubblico.

```
/skill clean-public-repo
```

**Due strategie di storia:**

| Strategia | Default | Quando usarla |
|---|---|---|
| Fresh-history publish | Si | Prima pubblicazione: nessuna storia da ripulire |
| Surgical rewrite (git-filter-repo) | No, opt-in | Storia già pubblica con commit da modificare; richiede backup + dry-run + HITL |

Lo script `scripts/detect-public-remote.sh` (usato anche da concept-to-code Gate 0b) rileva
automaticamente se il remote è pubblico su GitHub.

---

### 4.5 humanize-en

Rimuove AI-tells dalla prosa inglese. Interviene su vocabolario blacklist (delve, leverage,
seamless, robust, tapestry, pivotal, ...), opener vietati (Additionally, Moreover, Furthermore,
...), costruzioni passive, frasi chatbot di chiusura.

```
/skill humanize-en [target]
```

`target` può essere un path file o testo inline. Se omesso chiede incolla o path.

**Regola globale (ADR-0040):** passa per humanize-en solo la prosa inglese destinata a un
pubblico esterno: post Reddit e HN, thread di forum, blog, newsletter, annunci, testi
promozionali, email a terzi. Non si applica ad artefatti interni e di programmazione: codice,
file di config, commit message, testo di PR e issue, ADR, spec, piani, README e altre docs di
repo, changelog, release notes, testo in italiano, messaggi di chat. Invocazione solo manuale,
nessuna skill e nessuno step di catena la chiama in automatico.

**Modifica file:** mostra il testo rielaborato e chiede Write / Show diff / Discard prima di
sovrascrivere qualcosa.

---

### 4.6 claude-md-slim

Estrae sezioni per tipo di file dal CLAUDE.md di progetto in file path-scoped
(`.claude/rules/<dominio>.md`) con frontmatter `paths:`. Riduce i token sempre caricati.

```
/skill claude-md-slim [--global] [<project-root>]
```

`project-root` default a `$PWD`. Senza flag, analizza solo il CLAUDE.md del progetto.

**Flag `--global`:** attiva la scansione cross-file contro `~/.claude/CLAUDE.md` (read-only)
per identificare duplicati da eliminare nel CLAUDE.md del progetto.

**Guardrail obbligatori:**
- `content-union-check.sh`: prima di qualsiasi scrittura verifica che
  `union(CLAUDE.md_trimmed + tutti_rules_files)` contenga ogni riga dell'originale. Se fallisce,
  abort senza modifiche.
- Backup automatico con suffisso `.bak-YYYY-MM-DD` prima di sovrascrivere.
- Gate HITL (Step 6): mostra il diff unificato, chiede Approva / Rifiuta / Abort.

**DoD (Definition of Done):** riduzione ≥30% righe + frontmatter `paths:` valido su tutti i
rules file + nessun riferimento rotto nel CLAUDE.md trimmed.

---

### 4.7 vibe-status

Health check read-only del sistema. Dura meno di 10 secondi.

```
/skill vibe-status [--json] [--plain] [--skip-harness]
```

**Output:** header `HEALTHY / DEGRADED / CRITICAL` + lista harness (pass/fail), skill rilevate,
agenti, hook, ADR, manifest attivi, stato memoria.

**Flag:**
- `--json`: output machine-readable.
- `--plain`: nessun ANSI color.
- `--skip-harness`: salta i test harness (più veloce, meno informazioni).

**Variabile `VIBE_STATUS_HARNESS_TIMEOUT`:** default 12s per harness. Il harness
concept-to-code su alcuni sistemi sfiora il limite e produce un falso DEGRADED: imposta
`VIBE_STATUS_HARNESS_TIMEOUT=15` se vedi questo comportamento.

Da invocare dopo ogni recovery di skill cancellate o dopo una sessione di manutenzione.

---

## 5. Skill di avvio e scaffolding

### 5.1 git-repo-init

Wizard italiano a 4 fasi per creare una nuova repo git locale + remote GitHub. Non va usata
su repo esistenti: per quelle usa `git` direttamente o `project-init`.

**Trigger:** la skill è keyword-triggered, non serve `/skill`. Frasi che la attivano:
"nuova repo", "crea repository", "setup repo", "inizializza progetto", "git init",
"nuovo progetto su github", "nuova app macOS/iOS", "nuovo progetto Swift/Xcode".

**Path fissi:**
- Progetti generici: `~/Developer/<nome-kebab-case>`
- Progetti Swift/Apple: `~/Developer/Apple/<NomePascalCase>`

**Le 4 fasi dell'intervista:**

1. **Identità repo:** nome, descrizione, visibilità (pubblico/privato), licenza.
2. **Stack e architettura:** scelta dello stack; per Swift legge il file di riferimento
   `references/swift-xcode-setup.md` e guida la configurazione Tuist (Team ID, bundle id,
   target test, build verificata). Supporta: macOS, iOS, menu-bar, Swift Package.
3. **Convenzioni git:** branch naming, commit style, .gitignore.
4. **Livello di scaffolding:** minimal / standard / completo.

**Output:** repo locale + remote GitHub via `gh cli`, `CLAUDE.md` + `PROJECT_BRIEF.md`
(handoff pronto per il prossimo `/skill concept-to-code`). Se visibilità pubblica: offre di
passare per `clean-public-repo` prima del primo push.

---

### 5.2 project-init

Bootstrap di `CLAUDE.md` + `.claude/context.md` per un progetto esistente, senza SPEC/ADR.
Usa auto-detection del filesystem (stack, framework, struttura directory).

```
/skill project-init [--update]
```

Senza `--update`: abortisce se `CLAUDE.md` esiste già (protegge da sovrascrittura).
Con `--update`: rigenera mostrando il diff, senza chiedere permesso.

Per i progetti che passeranno per concept-to-code Standard, usa invece `claude-md-generator`
(che legge SPEC.md + ARCH.md già prodotti dal chain).

---

### 5.3 Skill usabili da sola ma invocate dalla chain

Queste skill hanno un contratto standalone, ma la chain le chiama automaticamente ai passi
giusti. Puoi invocarle da sola quando hai bisogno fuori da una chain.

**`interview-driver`** -- conduce un'intervista strutturata e produce `SPEC.md`.
```
/skill interview-driver
```
Trigger: "interview me", "let's spec it", "fammi l'intervista". Invocata da concept-to-code
Step 1 (Standard/Hybrid). Non produce codice, solo SPEC.

**`design-brainstorm`** -- esplora 3-4 approcci progettuali con 8 tecniche di ideazione
(first-principles, cross-domain analogy, inversion/pre-mortem, ...). Produce `BRAINSTORM.md`.
```
/skill design-brainstorm
```
Trigger: "let's explore approaches". Invocata da concept-to-code Gate 1b. Non scrive SPEC,
ADR o plan: è un passaggio creativo pre-architetturale.

**`adr-writer`** -- scrive `docs/architecture/ADR-NNN-<slug>.md` con la struttura standard
(Status / Context / Decision / Alternatives / Consequences / References).
```
/skill adr-writer <argomento>
```
Invocato dall'agente architect a Gate 2. Puoi chiamarlo direttamente quando aggiungi una
decisione architetturale fuori da una chain.

**`claude-md-generator`** -- genera un `CLAUDE.md` di progetto (<100 righe) leggendo
SPEC.md + ARCH.md. Sceglie un template (ios-swiftui / app-fastapi-react / web-vanilla).
Invocato da concept-to-code Step 3. Non ha senso senza SPEC+ARCH.

---

## 6. Skill UI e macOS

### 6.1 macos-ux

Due modalità selezionate dall'argomento.

**Design mode** (nessun argomento):
```
/skill macos-ux
```
Conduce un'intervista HIG, produce `UX-BLUEPRINT.md` con: tipologia finestre, navigazione,
Settings panel, menu bar, toolbar, keyboard shortcuts. Invocata da concept-to-code Gate 1c
quando rileva un progetto macOS/SwiftUI nel SPEC.

**Review mode:**
```
/skill macos-ux review [<file>]
```
Analizza violazioni strutturali HIG nel file (o nei file modificati se omesso). Solo
violazioni strutturali: non valuta qualità layout o code style.

---

### 6.2 ui-layout-audit

Cerca e corregge bug di layout: testo troncato, overflow, scrollbar indesiderate,
dimensioni hard-coded, problemi Dynamic Type.

```
/skill ui-layout-audit [<file-o-glob>]
```

Se l'argomento è omesso usa `git diff` per trovare i file Swift/HTML/CSS/TSX/JSX/Vue
modificati nella sessione corrente.

**Regole SwiftUI:** S1-S13 (frame flessibili, GeometryReader, lineLimitScaled, ...).
**Regole Web:** W1-W12 (overflow hidden, min-height, word-break, ...).

Invocata automaticamente da concept-to-code Gate 5.05 se ci sono file UI nell'implementazione.

---

## 7. Gli 8 agenti

Sono dispatchati automaticamente dalle chain. Puoi richiamarli esplicitamente in chat
usando descrizioni del ruolo ("debugga questa crash", "scrivi i test per questa funzione").

| Agente | Scopo | Modello | Effort | Dispatch automatico |
|---|---|---|---|---|
| `architect` | Piani, ADR, design. Mai codice di produzione. Esplora alternative, verifica libs via context7 | opus | max | c2c Step 2 |
| `coder` | Implementa il piano approvato esattamente. Worktree isolation. Memory local. Non fa commit | sonnet | high | c2c Step 5, autopilot-build Phase 1 |
| `reviewer` | Review per security/correctness/perf/consistency. Proattivo su >50 righe modificate | sonnet | high | c2c Gate 5.06, RTF, pre-commit |
| `tester` | Scrive e lancia test unit/integration dopo l'implementazione | sonnet | medium | post-coder o esplicito |
| `debugger` | Root-cause di failure: runtime error, red test. Staged fix, non fa commit | opus | high | RTF, su failure |
| `refactorer` | Migliora struttura senza cambiare comportamento. Usa refactor-snapshot harness | sonnet | medium | reviewer-flagged o esplicito |
| `doc-writer` | README, inline docs, ADR, CHANGELOG. Dopo merge o su richiesta | haiku | low | post-merge o esplicito |
| `researcher` | Brief con fonti citate su libs/API/standard. context7 -> WebSearch -> WebFetch | haiku | low | lookup-needed o esplicito |

**Note importanti:**

`coder` ha `isolation: worktree`: opera su una copia git forkata da `HEAD`
(`worktree.baseRef: "head"`), che l'orchestratore fa confluire nel branch della feature con un
merge dopo ogni stage. Se la CWD non è una repo git completa, la chain rifiuta con un messaggio
azionabile: non esiste una modalità alternativa (ADR-0068).

`debugger` usa opus a effort high anche se gli altri agenti analitici usano sonnet: è
l'agente dove la qualità del ragionamento ha più impatto (root cause analysis su problemi
non ovvi).

`refactorer` richiede che ci sia un `.claude/test-cmd` valido: senza test, il harness
`refactor-snapshot` non può verificare la preservation del comportamento e blocca.

---

## 8. Skill interne e di terze parti

### Skill interne (non invocare direttamente)

**`refactor-snapshot`** -- harness di behavior-preservation usato esclusivamente dall'agente
`refactorer`. Tre script: `pre-runs.sh` (determinismo PRE ×N), `capture.sh POST`,
`diff.sh` (gate SHA256). Stack-agnostic via `.claude/test-cmd`.

**`code-review-checklist`** -- checklist strutturata per severità, usata internamente
dall'agente `reviewer`. Non ha utilità come skill standalone.

### Skill keyword-triggered (si attivano da sole)

**`agent-design`** -- knowledge base su architettura di agenti, MCP, A2A, orchestration
(fonte: Gigi Sayfan). Si attiva quando discuti di design di agenti o orchestration patterns.

**`swift-vibe`** -- quick reference pattern SwiftUI/iOS moderni: `@Observable`+`@Bindable`
iOS 17+, `@Query` SwiftData, `URLSession` async/await. Si attiva quando scrivi codice
Swift/SwiftUI.

### Skill di terze parti (citate, non custom)

**`swiftui-pro`** (Paul Hudson, MIT, v1.1) -- code review SwiftUI per API moderne,
maintainability, performance. Keyword-triggered.

**`find-skills`** -- scopre e installa skill dall'ecosistema open di Claude Code.
Keyword-triggered ("is there a skill for...").

---

## 9. Ricette: flussi di lavoro comuni

### (a) Nuova feature da zero (Standard)

```
# Sessione 1: design
/skill concept-to-code Autenticazione OAuth2 con refresh token

# Gate 0: scegli Standard (o lascia che auto-detect lo suggerisca)
# Rispondi all'intervista (interview-driver -> SPEC.md)
# Gate 1: approva SPEC
# Opzionale: brainstorm approcci (Gate 1b)
# Arch: l'agente architect produce ARCH.md + ADR
# Gate 2: approva architettura
# Gate 2b: approva test-cmd proposto dall'architect (TOFU registration)
# Gate 3: approva CLAUDE.md + piano di implementazione
# Session boundary: il manifest è a ready_for_implementation

# Sessione 2 (apri nel progetto target, NON in vibe-coding-system):
/skill concept-to-code resume /path/al/manifest.yml

# Steps 5-7: impl, review, commit (tutti con gate HITL)
```

### (b) Nuova feature piccola (Express)

```
/skill concept-to-code express Script batch import CSV prodotti

# Sessione singola:
# E1: EnterPlanMode, piano leggero
# E2: dispatch coder
# Gate E3: verifica, approva
# E4: commit
```

### (c) Fix di un bug

Non serve una chain. Descrivi il problema in chat o usa direttamente l'agente:

```
# In chat (l'orchestratore dispatcha debugger automaticamente):
"La funzione calculateTax lancia un NilPointerException quando
l'oggetto product è senza categoria. Debugga e proponi il fix."

# Poi verifica e commit:
/skill commit fix: handle nil category in calculateTax
```

### (d) Ciclo di review e fix

```
/skill review-triage-fix
# Reviewer analizza il codice modificato
# Triage: issue smistate a debugger/refactorer/coder
# Fix sequenziali con circuit breaker
# Re-review finale
# Poi committi tu con: /skill commit
```

### (e) Progetto nuovo end-to-end

```
# Prima crea la repo:
"crea repository per la nuova app iOS TaskMaster"
# git-repo-init: wizard 4 fasi, crea repo locale + GitHub

# Poi la prima feature:
/skill concept-to-code express Setup base SwiftUI + navigazione tab
```

### (f) Progetto multi-feature

```
# Crea/aggiorna PROJECT.md con la lista delle feature,
# ciascuna come "- [ ] Nome feature"

/skill project-conductor
# Per ogni feature [ ]: avvia concept-to-code
# Segna [x] quando completata
# Riprende da dove si era fermato se interrotto
```

### (g) Implementazione non presidiata (autopilot)

```
# Precondizione: hai già completato il path Standard fino a Gate 3
# Il manifest è a ready_for_implementation
# Hai test-cmd TOFU registrato e hook_verified=true nel manifest

/skill autopilot-build docs/manifests/2026-06-18-my-feature.manifest.yml

# Esci. La mattina dopo leggi:
cat .claude/autopilot-report.json

# Se status=success:
git log --oneline
git diff main...HEAD  # revisione del lavoro
git push -u origin feat/my-feature
```

### (h) Health check del sistema

```
/skill vibe-status
# Risultato: HEALTHY / DEGRADED / CRITICAL
# Se DEGRADED su concept-to-code harness:
VIBE_STATUS_HARNESS_TIMEOUT=15 /skill vibe-status
```

### (i) Preparare una repo per uso pubblico

```
/skill clean-public-repo
# Rimuove marker interni, segni del tool, tracce del workflow
# Default: fresh-history (git squash history prima del push)
# Opzionale: surgical rewrite via git-filter-repo
# Poi: primo push su remote pubblico
```

---

## 10. Invarianti chiave

Queste regole si applicano sempre, in ogni skill e chain. Non hanno eccezioni.

**HITL gate obbligatori:** prima di commit, push, deploy, modifiche schema DB, cancellazioni
permanenti c'è sempre un gate di approvazione esplicito. L'unica eccezione è `--autopilot`
(commit skill), usato solo dalla chain quando sai che sei in modalità non presidiata.

**Session scope:** ogni sessione Claude Code opera su un solo progetto. Una skill o chain non
può mai leggere, scrivere o dispatchare agenti fuori dalla CWD della sessione corrente. Se il
`project_root` nel manifest non coincide con la CWD né ne è una sottodirectory, la chain abortisce con SCOPE ERROR. Questo
vale anche per i sub-agent di workflow.

**TOFU (Trust On First Use) per test-cmd:** il comando di test deve essere approvato
esplicitamente con SHA-pin almeno una volta da un umano. Senza quel pin, step automatici che
eseguono test (autopilot-build, deep-refactor) non partono. Il pin viene verificato a ogni
session start dal `stop-gate.sh`.

**Circuit breaker globale:** in `deep-refactor`, il primo test RED ferma tutte le dimensioni
rimanenti. In `autopilot-build` e `review-triage-fix`, un test RED ferma il ciclo corrente.
Non si bypassa mai: se i test sono rossi, si risolve prima di procedere.

**Security findings sempre report-only:** nessuna skill o chain auto-fixa mai un finding
classificato come security, qualunque sia il risk level. La decisione su sicurezza è sempre
umana.

**No test disabling:** se i test falliscono non si disabilita il test per far passare la
pipeline. Si trova e si risolve la causa. Questa regola si applica a tutti gli agenti e hook.

**Bash 3.2:** tutti gli script in `~/.claude/` girano su bash 3.2.57 (default macOS). Nessun
associative array, nessun `mapfile`, nessun `${v^^}`. Usa file temporanei + grep per le map.
Questo vincolo si applica a hook, script harness e alle porzioni bash delle skill.

---

## Appendice: mappa artefatti prodotti

| Skill/Chain | Artefatti principali | Posizione |
|---|---|---|
| `concept-to-code` | SPEC.md, ARCH.md, ADR, CLAUDE.md, plan, manifest | `<project-root>/docs/manifests/` + root |
| `autopilot-build` | `autopilot-report.json` | `<project-root>/.claude/` |
| `deep-refactor` | Report audit per dimensione | `<project-root>/docs/deep-refactor/` |
| `design-brainstorm` | BRAINSTORM.md | `<project-root>/` |
| `interview-driver` | SPEC.md | `<project-root>/` |
| `adr-writer` | ADR-NNN-<slug>.md | `<project-root>/docs/architecture/` |
| `claude-md-generator` | CLAUDE.md | `<project-root>/` |
| `claude-md-slim` | `.claude/rules/<dominio>.md`, CLAUDE.md trimmed + `.bak` | `<project-root>/.claude/rules/` |
| `review-triage-fix` | `.triage-fix-last-<branch>.json` | `<project-root>/.claude/` |
| `git-repo-init` | CLAUDE.md, PROJECT_BRIEF.md, repo git + GitHub | `~/Developer/<nome>/` |
| `project-init` | CLAUDE.md, `.claude/context.md` | `<project-root>/` |
| `macos-ux` (design) | UX-BLUEPRINT.md | `<project-root>/` |
