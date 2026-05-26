# Guida operativa al workflow di orchestrazione

**Per chi:** Stefano Ferri (utente esperto del sistema vibe-coding).
**Scopo:** mostrare passo per passo come usare il chain `/concept-to-code` (workflow v2) + tutti i tool ausiliari, con i prompt esatti da inserire in ogni step.
**Data:** 2026-05-21 (versione post-deploy ADR-0001…0008, workflow v2).

---

## Sommario

1. [Quando usare cosa — decision tree](#1-quando-usare-cosa)
2. [Setup di una sessione pulita](#2-setup-di-una-sessione-pulita)
3. [Workflow A: feature non-triviale con `/concept-to-code` (v2)](#3-workflow-a-feature-non-triviale)
4. [La skill `design-brainstorm` (brainstorm-gate)](#4-la-skill-design-brainstorm)
5. [Workflow B: hotfix o micro-edit (dispatch diretto coder)](#5-workflow-b-hotfix-o-micro-edit)
6. [Workflow C: refactor con behavior-preservation](#6-workflow-c-refactor-behavior-preserving)
7. [Workflow D: review/fix di codice già scritto](#7-workflow-d-reviewfix-codice-esistente)
8. [Comandi di servizio](#8-comandi-di-servizio)
9. [Come leggere il pattern classifier + hook](#9-pattern-classifier-e-hook)
10. [Troubleshooting](#10-troubleshooting)
11. [Cheat sheet](#11-cheat-sheet)
12. [Prompt template riutilizzabili](#12-prompt-template-riutilizzabili)
13. [Quando NON usare `/concept-to-code`](#13-quando-non-usare-concept-to-code)
14. [Glossario rapido](#14-glossario-rapido)

---

## 1. Quando usare cosa

**Decision tree:**

```
Devi fare qualcosa di nuovo?
├── Vuoi solo ESPLORARE idee liberamente (interfacce, metodologia, niente impegno a costruire)?
│   └── `/superpowers:brainstorming` (standalone, scollegato dal chain) → §11
├── È una feature NON-TRIVIALE (richiede design, multi-file, decisioni architetturali)?
│   └── Usa `/concept-to-code <topic>` → Workflow A
│       (il chain ti offre, se serve, un brainstorm di design strutturato al gate 1b → §4)
├── È un HOTFIX o micro-edit (bug noto, <3 file, no decisione architetturale)?
│   └── Dispatch diretto coder → Workflow B
├── È un REFACTOR (comportamento invariato, struttura migliorata)?
│   └── Dispatch refactorer agent → Workflow C
├── È REVIEW di codice già scritto (vuoi feedback strutturato + fix)?
│   └── Invoca `/skill review-triage-fix` → Workflow D
└── Vuoi SAPERE lo STATO del sistema?
    └── `bash ~/.claude/skills/vibe-status/scripts/aggregate.sh` → §8
```

**Soglia "non-triviale":** ≥3 file modificati o creati, OR almeno una decisione architetturale da prendere, OR richiede una nuova ADR.

**Due brainstorming, due usi distinti:**
- **`/superpowers:brainstorming`** = standalone, esplora liberamente E scrive spec+plan da solo. Usalo fuori dal chain.
- **`design-brainstorm`** (interno al chain, gate 1b) = esplora alternative di design e ritorna un brief che alimenta l'architect. NON scrive spec/plan. Vedi §4.

---

## 2. Setup di una sessione pulita

Apri terminale nella cartella del progetto (es. `cd ~/Developer/Apple/rempay`).

Lancia Claude Code:
```bash
claude
```

**Check iniziali (opzionali ma raccomandati):**

1. **Verifica stato del sistema:**
   ```
   lancia vibe-status
   ```
   Output atteso: `Health: HEALTHY`, harness tutti verdi.

2. **Conferma che il progetto ha `.claude/test-cmd`** (necessario per refactor-snapshot e review):
   ```
   verifica che esista .claude/test-cmd e mostrami il contenuto
   ```

3. **Se il progetto è nuovo (no `.claude/`):** considera prima `/skill project-bootstrap` per scaffolding minimale.

---

## 3. Workflow A: feature non-triviale

Workflow **default** per qualunque feature di una certa dimensione. Il chain `/concept-to-code` v2 orchestra: **Gate 0** → interview (o skip se brownfield) → Gate 1 → **brainstorm-gate 1b** → architect → Gate 2 → CLAUDE.md → Gate 3 → session boundary → implementation → Gate 5 review.

### Step 0 — Invocazione

```
/concept-to-code <topic-full-title>
```

**Esempi:**
```
/concept-to-code Rate limiter middleware per FastAPI
/concept-to-code Wizard documenti a tre box per il nuovo piano
```

Lo skill crea un manifest YAML in `docs/manifests/YYYY-MM-DD-<slug>.manifest.yml` (schema 1.1).

### Gate 0 — Triage chain-vs-leggero (NUOVO in v2)

Prima di partire, il chain controlla se il progetto soddisfa criteri che **sconsigliano** il chain completo:
- `SPEC.md` + ADR già esistenti (progetto "brownfield")
- micro-scope dichiarato (<3 file, nessuna decisione architetturale)

**Se nessun criterio è attivo:** Gate 0 è silenzioso, si procede dritti.

**Se almeno un criterio è attivo, cosa vedi:**
```
============================================================
concept-to-code · Gate 0 · TRIAGE
============================================================
Criteri rilevati:
  [X] SPEC.md + ADR già esistenti (brownfield)
  [ ] micro-scope <3 file
============================================================
  [c] chain completo (con brownfield mode)
  [l] workflow leggero (plan diretto, no chain)
  [a] abort
> _
```

**Cosa scegliere:**
- **`c`** — chain completo. Se brownfield, attiva automaticamente il "brownfield mode" (vedi sotto).
- **`l`** — workflow leggero: l'orchestrator fa un plan diretto in plan mode, senza interview/architect formali. Buono per micro-feature in progetti maturi.
- **`a`** — abort.

> Questo gate esiste perché senza di esso, su progetti con SPEC esistente, l'orchestrator decideva *da solo* di saltare il chain. Ora **decidi tu**.

### Step 1 — Interview (GREENFIELD) o skip (BROWNFIELD)

**Greenfield (progetto senza SPEC):** `interview-driver` ti fa domande via `AskUserQuestion` (multiple choice). Copri obiettivi, scope, stack, edge case, success criteria. Alla fine scrive `SPEC.md`.

**Brownfield (SPEC esiste già — es. rempay):** lo Step 1 è **SALTATO automaticamente**. Il manifest fa puntare `artifacts.spec` alla SPEC esistente (NON la rigenera, NON la sovrascrive) e marca Gate 1 come "spec pre-esistente approvata". Niente interview ridondante.

### Gate 1 — Spec review (solo greenfield)

In greenfield, dopo l'interview:
```
============================================================
concept-to-code · Step 1 · INTERVIEW COMPLETE
============================================================
Artifact: /path/to/SPEC.md
Summary:  <5 righe: obiettivo, scope, stack, edge case, criteri>
============================================================
HITL Gate 1: spec_review
  [y] approva e procedi    [e] revisiona (note)    [a] abort
> _
```

- **`y`** approva
- **`e`** + note per revisionare. Es: `e: restringi lo scope al solo endpoint GET /api/products`
- **`a`** abort

(In brownfield, questo gate è già marcato approvato e si salta al gate 1b.)

### Gate 1b — Brainstorm di design (NUOVO in v2, opzionale)

Tra la spec e l'architettura, il chain ti **offre** una sessione di brainstorming di design:
```
============================================================
concept-to-code · Gate 1b · BRAINSTORM DI DESIGN
============================================================
Vuoi esplorare alternative di approccio prima di fissare l'architettura?
  [y] sì → sessione design-brainstorm (8 tecniche di ideazione)
  [n] no → vai diretto all'architect (comportamento classico)
> _
```

**Quando rispondere `y`:** quando la feature ha più approcci possibili, quando vuoi idee applicative nuove, quando la decisione architetturale è importante e non scontata. È **il momento che fa la differenza** sull'architettura.

**Quando rispondere `n`:** quando l'approccio è ovvio o già deciso (es. una modifica UI semplice).

**Se `y`:** parte la skill `design-brainstorm` (vedi §4). Produce un `BRAINSTORM.md` con 2-4 alternative + trade-off, che viene passato all'architect come contesto. Le alternative del brainstorm diventano le "alternative considerate" dell'ADR.

**Se `n`:** transizione diretta allo Step 2, architect opera come da v1.

### Step 2 — Architecture

Dispatch del sub-agent **`architect`** (con `BRAINSTORM.md` allegato se hai fatto il gate 1b). Produce:
- `docs/architecture/<NNNN>-<topic>.md` (ADR — **attenzione:** la convenzione di numerazione segue quella del repo target, es. rempay usa `0002-titolo.md`, vibe-coding-system usa `ADR-0002`)
- `docs/superpowers/plans/YYYY-MM-DD-<topic>.md` (plan TDD a 6-10 task)
- (opzionale) `ARCH.md`

**Cosa scrivere:** nulla. Aspetta.

### Gate 2 — Architecture review

```
============================================================
concept-to-code · Step 2 · ARCHITECTURE COMPLETE
============================================================
Artifact (ADR):  <path>
Artifact (Plan): <path>
Key decisions:   <top 3>
Risk flags:      <top 3>
============================================================
HITL Gate 2: architecture_review
  [y] approva    [e] revisiona (note)    [a] abort
> _
```

**Cosa verificare:** ogni domanda architetturale ha risposta + alternativa scartata? Plan ha task con file path, red/green, verify command? Risk flag accettabili?

- **`y`** approva
- **`e`** + note vincolanti. Es: `e: l'ADR ha scelto Redis ma serve standalone, no extra dependency. Rifai con LRU in-process.`

### Step 3 — Project memory (CLAUDE.md)

Genera `CLAUDE.md.proposed`.

**Greenfield (no CLAUDE.md):** genera da zero da SPEC + ADR.
**Brownfield (CLAUDE.md curato a mano):** modalità **ADDITIVA** — parte dal CLAUDE.md esistente e aggiunge solo il riferimento al nuovo ADR + eventuali gotcha. Non degrada mai contenuto curato.

### Gate 3 — Project memory review

```
============================================================
concept-to-code · Step 3 · PROJECT MEMORY COMPLETE
============================================================
Proposed: <project-root>/CLAUDE.md.proposed
<contenuto completo (greenfield) o diff (brownfield)>
============================================================
HITL Gate 3: project_memory_review
  [y] applica    [e] revisiona    [s] skip    [a] abort
> _
```

- **`y`** applica (backup esistente in `.bak-<date>`)
- **`s`** skip (mantieni CLAUDE.md attuale invariato — utile se è già perfetto)
- **`e`** + note

### Step 4 — Session boundary (informativo)

```
============================================================
concept-to-code · SESSION BOUNDARY
============================================================
Step 1-3 completi. Ora:
1. Chiudi questa sessione.
2. Apri una NUOVA sessione in: <project-root>
3. Lancia: /concept-to-code resume <manifest-path>

Motivo: una sessione fresca evita di inquinare il context con
i turni di design prima dell'implementazione.
============================================================
```

**Cosa fare:**
1. **Copia il path del manifest** mostrato
2. Esci (`Ctrl+D` o `/exit`)
3. Nuova sessione (`claude`) nella stessa cartella
4. `/concept-to-code resume <manifest-path>`

### Step 5 — Implementation

Dispatch del **`coder`** col plan. Legge plan + ADR + SPEC + CLAUDE.md (+ BRAINSTORM.md se esiste). Esegue ogni task TDD (red → green → verify). **Emette `PATTERN:` prima di ogni Edit** (ora *enforced davvero* dall'hook v1.1 — vedi §9). Implementa su un branch dedicato. Non committa mai.

**Cosa scrivere:** nulla. Aspetta il report.

### Gate 5 — Review cycle (opzionale)

```
============================================================
concept-to-code · Step 5 · IMPLEMENTATION COMPLETE
============================================================
Tasks completed:  N    Files modified: <list>
Test results:     green | red    Harness deltas: <...>
============================================================
HITL Gate 5: review_cycle_decision
  [r] esegui review-triage-fix    [s] skip    [a] abort
> _
```

- **`r`** consigliato per feature >50 LOC: gira reviewer + triage + fix dei MAJOR
- **`s`** skip → manifest `completed`

### Finale

Manifest → `completed`. Il coder NON committa: decidi tu commit/push (es. `/skill commit`). Per UI/frontend (es. SwiftUI), **verifica a mano** prima di push — gli agenti non testano la GUI.

---

## 4. La skill `design-brainstorm`

Si attiva al **gate 1b** (rispondendo `y`) oppure standalone (`/skill design-brainstorm <topic>`). È la skill che esplora **come** realizzare e **cosa di nuovo** è possibile, prima di fissare l'architettura.

**Non confonderla con:**
- `interview-driver` — quella estrae *requisiti* (cosa), questa esplora *approcci* (come)
- `/superpowers:brainstorming` — quella scrive spec+plan da sola; `design-brainstorm` ritorna solo un brief

### Le 8 tecniche di ideazione

La skill non le usa tutte: ne **seleziona 3-4** in base al problema, una tecnica → 1-2 domande → sintesi → avanti.

| # | Tecnica | A cosa serve |
|---|---------|--------------|
| 1 ★ | **First-principles** | scompone il problema agli elementi irriducibili, ricostruisce senza assunzioni ereditate (anti-anchoring) |
| 2 ★ | **Analogie cross-dominio** | "come risolverebbe questo flusso un videogioco / una banca / un sistema biologico / la logistica?" |
| 3 ★ | **Inversione (pre-mortem)** | "come garantiremmo il FALLIMENTO totale?" → inverti per trovare rischi e requisiti nascosti |
| 4 | **Vincoli forzati** | "e se avessi 1/10 del tempo? niente database? offline?" → scova la versione snella |
| 5 | **Assumption-busting** | rende esplicite le assunzioni implicite e le sfida una per una |
| 6 | **Alternative genuinamente diverse** | 2-4 approcci che differiscono per dati/concorrenza/confini/deployment (non varianti) |
| 7 | **Idee adiacenti** | feature vicine che emergono — in-scope / future / esplicitamente escluse |
| 8 | **Prior-art** | "cosa fanno i prodotti concorrenti? dove c'è spazio per fare meglio/diverso?" (delega al `researcher` se serve ricerca) |

★ = cardine, sempre considerate per prime.

### Output: `BRAINSTORM.md`

Scrive `<project-root>/BRAINSTORM.md` con: problema riformulato, assunzioni sfidate, 2-4 alternative con trade-off, rischi pre-mortem, idee adiacenti, raccomandazione **preliminare** (non vincolante). NON scrive SPEC/plan. L'architect lo legge e ne riusa le alternative nell'ADR.

### Cosa fai tu durante il brainstorm

Rispondi alle domande `AskUserQuestion` (multiple choice + "Altro/scrivilo"). La skill sintetizza dopo ogni risposta. Se non sai rispondere a una tecnica, scegli "salta". Convergi in ~6-7 scambi.

---

## 5. Workflow B: hotfix o micro-edit

**Quando:** bug noto, fix piccolo, no decisione architetturale. (Anche l'esito `[l]` del Gate 0 finisce qui.)

**Cosa scrivere:**
```
fixa il bug in validate.py linea 42: regex troppo lasca, deve richiedere path quotato.
contesto: [...].
fix proposto: regex `^"/[^"]+"$`.
aggiungi test che dimostri il bug pre-fix e il fix post-fix.
```

**Cosa fa l'orchestrator:** dispatch diretto al `coder` (no architect, no chain). Il coder scrive test red, fixa, verifica green, emette `PATTERN:`. Nessun gate HITL (auto mode).

**Pattern utile:** mini-piano TDD embedded nel prompt:
```
Task TDD a 3 step:
1. RED: aggiungi test in tests/test_validate.py che dimostra il bug.
2. GREEN: fixa la regex.
3. VERIFY: pytest tests/test_validate.py deve essere green.
```

---

## 6. Workflow C: refactor behavior-preserving

**Quando:** migliorare struttura/leggibilità senza cambiare comportamento.

**Cosa scrivere:**
```
refattora le 3 fixture autouse in tests/conftest.py + test_cli.py + test_pricing.py
in una sola in conftest.py. comportamento osservabile identico.
usa il refactorer agent con snapshot harness.
```

**Cosa fa il refactorer (Process 8-step, ADR-0002):**
1. Baseline check (`.claude/test-cmd` verde pre-refactor)
2-3. PRE-snapshot × N + determinism check (SHA256 identici)
4. Apply refactor
5. POST-snapshot
6. Diff PRE vs POST → PASS / FAIL / UNVERIFIED
7. Se FAIL → STOP + HITL ("behavior cambiato, è voluto?")
8. Se PASS → report

**Env vars:**
- `RFS_RUNS=5` più confidenza determinism (suite flaky) · `RFS_RUNS=1` skip determinism (test deterministico)
- `RFS_FULL=1` suite completa (default = filter sui file toccati)
- `RFS_FILTER='-k test_pricing'` narrowing · `RFS_TIMEOUT=300` timeout per-run (default 120s)

---

## 7. Workflow D: review/fix codice esistente

**Quando:** codice già scritto, vuoi review strutturata + fix dei MAJOR.

**Cosa scrivere:**
```
fai una review-triage-fix sui file modificati nelle ultime 2 ore.
focus: src/pricing/*.py
```

**Cosa fa:** reviewer → findings per severità (BLOCKER/MAJOR/MINOR/NIT) → triage → fix dei MAJOR/BLOCKER → re-review → recap. **Variante v1.2:** un `PATTERN: REPLACE` senza `Remove:` viene escalato a MAJOR (ADR-0001).

> Nota: nel test reale il review ha correttamente lasciato 5 finding come REPORT-ONLY (design-level / fuori-scope / effort Swift6 differito) senza inventare fix. Il triage maturo *non* fixa tutto a forza.

---

## 8. Comandi di servizio

### `vibe-status` — stato del sistema
```
lancia vibe-status
```
Report Markdown con harness/ADR/manifest/skill/hook/memory. <3s. Flag: `--json`, `--skip-harness`, `--plain`.

### `concept-to-code resume / abort`
```
/concept-to-code resume <manifest-path>     # riprendi dopo session boundary
/concept-to-code abort <manifest-path>      # marca aborted, preserva artifact
```

### Hook pattern-enforce (raro)
```bash
tail -50 ~/.claude/state/pattern-enforce/audit.log   # audit: allow/block/bypass per Edit
touch ~/.claude/state/pattern-enforce/disabled       # disabilita temporaneo
rm ~/.claude/state/pattern-enforce/disabled          # riabilita
PATTERN_ENFORCE=off claude                            # disabilita per una sessione
```

---

## 9. Pattern classifier e hook

Il `coder` emette **sempre** un header `PATTERN:` prima di ogni Edit/Write, e l'**hook `pre-flight-pattern-enforce` v1.1 lo enforce davvero** (blocca l'Edit se manca).

| Pattern | Cosa è | Cosa aspettarsi |
|---------|--------|-----------------|
| `ADD` | codice nuovo | solo righe aggiunte |
| `REMOVE` | cancellazione | payload con "Callers checked: ..." |
| `REPLACE` | sostituzione di pattern | OBBLIGATORIA coppia `Add: ... \| Remove: ...` |
| `MODIFY` | edit in-place senza cambio struttura | rename, typo, refactor interno |

**Come funziona l'hook (v1.1):** legge `agent_type` dal payload PreToolUse. Se `coder` → verifica che ci sia un `PATTERN:` negli ultimi 6 messaggi del transcript del sub-agent → `allow`; altrimenti `block`. Altri agent (architect, ecc.) e l'orchestrator → `bypass-noncoder`.

**Verifica live (2026-05-21):** su un coder reale, 26 Edit `allow` / 0 `block` indebiti. Funziona.

**Quando insospettirti:** `PATTERN: ADD` con cancellazioni non-banali nel diff → mis-classificato (reviewer lo prende come `pattern-drift` MINOR). `PATTERN: REPLACE` con solo `Add:` → l'hook avrebbe dovuto bloccare, controlla audit log.

---

## 10. Troubleshooting

### "La skill X non è invocabile da skill"
**Causa:** la skill ha `disable-model-invocation: true`, incompatibile con invocazione da chain.
**Fix:** rimuovere il flag se la skill è parte di un chain. Rif: memory `feedback_disable-model-invocation-strong.md`.

### Hook blocca un Edit del coder ("PATTERN missing in window=6")
**Causa:** il coder non ha emesso il `PATTERN:` negli ultimi 6 messaggi prima dell'Edit.
**Fix:** chiedi al coder di re-emettere il PATTERN: corretto e ritentare. **Non** disabilitare l'hook. Diagnostica: `tail ~/.claude/state/pattern-enforce/audit.log`.

### Il chain salta interview / non chiede nulla su progetto con SPEC
**Non è un bug:** è il **brownfield mode** (v2). Se SPEC esiste, l'interview viene saltata di proposito e `artifacts.spec` punta all'esistente. Se vuoi comunque rifare la spec, gestiscilo a Gate 0 con `[c]` e poi richiedi esplicitamente.

### Refactor in UNVERIFIED
**Causa:** test non-deterministici (timestamp, ID random, ordine dict).
**Fix 1:** sistema il non-determinismo. **Fix 2 (workaround):** crea `.claude/refactor-snapshot-override`:
```
REASON: timestamps in test output, intentional
SCOPE: stdout
EXPIRES: 2026-07-20
```

### Manifest invalid / chain bloccato
- Manifest già esistente stesso topic/giorno → `/concept-to-code abort <path>` o rinomina topic.
- YAML editato a mano e validate fallisce → ripristina o abort + nuovo manifest. (Schema 1.1 è retrocompatibile con 1.0.)

### vibe-status mostra "Harness X/N" con N basso
**Causa:** glob non scopre un harness in posizione non-standard.
**Fix:** già copre `~/.claude/skills/*/tests/run-tests.sh` + `~/.claude/hooks/tests/*.sh`. Aggiungi altri path al glob in `aggregate.sh` se servono.

### Label "Ready to code?" anche quando il chain fa solo design
**Non è un nostro bug:** è il template fisso dell'harness ExitPlanMode. Quando il plan dichiara "solo artefatti di design", uscire dalla plan mode NON scrive codice — fidati del contenuto del plan, non della label.

---

## 11. Cheat sheet

| Cosa vuoi fare | Comando |
|----------------|---------|
| Esplorare idee liberamente (standalone) | `/superpowers:brainstorming` |
| Brainstorm di design (standalone) | `/skill design-brainstorm <topic>` |
| Feature nuova non-triviale | `/concept-to-code <topic>` |
| Resume dopo session boundary | `/concept-to-code resume <manifest-path>` |
| Abortire chain | `/concept-to-code abort <manifest-path>` |
| Hotfix piccolo | Prompt diretto al coder con micro-piano TDD |
| Refactor sicuro | Prompt al refactorer (snapshot automatico) |
| Review + fix codice | `/skill review-triage-fix` |
| Stato del sistema | `bash ~/.claude/skills/vibe-status/scripts/aggregate.sh` |
| Audit del hook | `tail -50 ~/.claude/state/pattern-enforce/audit.log` |
| Disabilita/riabilita hook | `touch`/`rm ~/.claude/state/pattern-enforce/disabled` |
| Refactor con N runs determinism | `RFS_RUNS=N` env var |
| Commit (se git) | `/skill commit` |

---

## 12. Prompt template riutilizzabili

### Feature non-triviale
```
/concept-to-code <Titolo Feature Completo>
```

### Scelta ai gate
```
c        # Gate 0: chain completo
l        # Gate 0: workflow leggero
y        # Gate 1/2/3: approva  ·  Gate 1b: sì al brainstorm  ·  Gate 5: (r per review)
n        # Gate 1b: no al brainstorm, vai diretto all'architect
s        # Gate 3: skip CLAUDE.md  ·  Gate 5: skip review
e: <note concrete su cosa cambiare>     # rifiuto con feedback
a        # abort chain
```

### Hotfix con micro-piano TDD
```
fix bug in <file:line>: <descrizione>.
contesto: <cosa fa ora, cosa dovrebbe>.
plan TDD: T1 RED test che dimostra il bug · T2 GREEN fix · T3 VERIFY .claude/test-cmd.
```

### Refactor con snapshot
```
refattora <area>: <obiettivo, no cambio comportamento>.
usa refactorer agent con snapshot harness. env: RFS_RUNS=<N> RFS_FILTER=<filter>.
```

### Review on demand
```
fai una review-triage-fix sui file modificati <da quando> nel path <pattern>. focus: MAJOR.
```

---

## 13. Quando NON usare `/concept-to-code`

- **Hotfix sotto i 30 minuti:** overhead non giustificato → coder diretto (o Gate 0 `[l]`).
- **Esperimento usa-e-getta:** non ti serve persistere ADR + plan → coder con prompt esplorativo.
- **Tweak a feature esistente** (es. cambio default): è MODIFY, non new feature → coder diretto.
- **Progetto brownfield con micro-scope:** il Gate 0 te lo segnalerà e potrai scegliere `[l]`.

---

## 14. Glossario rapido

- **Orchestrator:** la sessione `claude` principale che dispatcha sub-agent.
- **Sub-agent:** processo isolato (`coder`, `architect`, `reviewer`, ecc.) che riceve un prompt e ritorna un report. NON spawna altri sub-agent.
- **Skill:** modulo markdown in `~/.claude/skills/<name>/SKILL.md` che istruisce l'orchestrator (o un sub-agent).
- **Hook:** script bash in `~/.claude/hooks/` che si attiva su eventi (PreToolUse, ecc.). `pre-flight-pattern-enforce` v1.1 enforce il PATTERN: del coder.
- **Manifest:** YAML che traccia lo stato del chain. In `<project>/docs/manifests/`. Schema 1.1 (retrocompat 1.0).
- **Gate 0:** triage iniziale chain-vs-leggero (v2).
- **Brownfield mode:** modalità per progetti con SPEC/CLAUDE.md esistenti — skip interview, CLAUDE.md additivo (v2).
- **Brainstorm-gate (1b):** gate opzionale tra spec e architettura che invoca `design-brainstorm` (v2).
- **HITL gate:** punto che richiede approvazione esplicita dell'utente.
- **PATTERN: header:** dichiarazione obbligatoria del coder prima di ogni Edit (ADR-0001), enforced dall'hook (ADR-0004).
- **ADR:** Architecture Decision Record, in `docs/architecture/`.
- **BRAINSTORM.md:** output di `design-brainstorm` — alternative + trade-off, alimenta l'architect (non è SPEC né plan).
- **Harness:** script di test automatici (`tests/run-tests.sh`). **Anchor:** grep-pattern che il harness verifica; "anchor preservation" = non romperli.

---

*Fine guida. Per la versione "kid-friendly", vedi `guida-per-ragazzi-12-anni.md`. Per la spec tecnica completa, vedi `vibe-coding-system.md`. Workflow v2 dettagliato: `ADR-0008` + `2026-05-21-concept-to-code-workflow-v2-design.md`.*
