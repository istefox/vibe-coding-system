# Spec — Field test del sistema vibe coding su progetto pilota

**Data:** 2026-05-18
**Scopo:** validare sul campo trigger e `description` di skill/agenti del sistema deployato, eseguendo il workflow concept→code reale su un mini-progetto.
**Approccio:** A — workflow reale completo + osservazione strumentata.

---

## 1. Progetto pilota

`pricing-markup-cli` — CLI Python: dati `--cost`, `--markup` (percentuale) e
`--rounding` (regola), stampa il prezzo finale. Dominio-reale (pricing/rounding,
rispecchia il lavoro `fix/pricing-rounding`). Piccolo ma con edge case veri:

- arrotondamento half-up vs banker's (ROUND_HALF_UP vs ROUND_HALF_EVEN)
- precisione valuta a 2 decimali (`decimal.Decimal`, non float)
- input non validi: costo/markup negativi, zero, markup > 100%
- output deterministico, testabile

## 2. Collocazione e git

- Directory **separata**: `~/developer/pricing-markup-cli` (sotto la cartella
  Developer dell'utente, accanto a `vibe-coding-system`; macOS case-insensitive).
- **`git init` + commit iniziale**: parte del workflow reale (sez.11 /
  `project-bootstrap` step 4) ed è oggetto di validazione.
- Il repo blueprint `vibe-coding-system` resta **no-git** come prima: entità distinta.
- Lo spec e il log del field test vivono in `vibe-coding-system/docs/` (no-git).

## 3. Workflow da esercitare (è anche lo script del test)

1. `/interview-driver` con "CLI Python per calcolo prezzo con markup" → `SPEC.md`
   nel pilota. (Skill con `disable-model-invocation`: si verifica che si invochi
   solo a mano, non in automatico.)
2. Fresh session → agente `architect` → ADR sulle decisioni di rounding
   (`docs/architecture/ADR-001-rounding.md`) → HITL.
3. `/claude-md-generator` → `CLAUDE.md` di progetto. **Punto di test chiave:**
   una CLI Python pura non combacia con nessuno dei 3 project-template
   (app-fastapi-react / web-vanilla-wordpress / ios-swiftui) → si valida se la
   skill **degrada con grazia** su stack fuori-template. Segnale prezioso, non
   un difetto da correggere nel pilota.
4. Agente `coder` → implementazione per ADR (usa `decimal.Decimal`).
5. Agente `tester` → pytest: happy path + edge (`.5` half-up vs even, negativi,
   zero, markup > 100%).
6. Bug deliberato (es. off-by-one nell'arrotondamento di `.5`) → agente
   `debugger` → root cause + fix minimo + test di regressione.
7. Agente `reviewer` → report per severità (BLOCKER/MAJOR/MINOR/NIT).

## 3bis. Modalità di esecuzione (importante)

Questo field test **NON è un batch autonomo** (a differenza dei piani
precedenti). Per natura richiede:

- risposte umane all'interview (`AskUserQuestion`),
- confini di sessione reali (`/clear` o nuova sessione tra FASE concept e
  implementazione),
- HITL gate (approvazione ADR, commit).

Quindi il "piano di implementazione" prodotto sarà un **runbook interattivo
guidato dall'utente**, non una lista di task auto-eseguibili. Ruoli:

- **Utente**: lancia le sessioni nel pilota, risponde all'interview, approva
  gli HITL, esegue i comandi `/skill` e le invocazioni `@agent`.
- **Assistente (in questa sessione di coordinamento)**: fornisce il runbook
  passo-passo, e raccoglie/registra le osservazioni dei trigger nel log
  deliverable man mano che l'utente riporta cosa è successo.

La parte sistematica e ripetibile è il **protocollo di osservazione** (sez.4-5),
non l'esecuzione del codice.

## 4. Cosa si osserva (criteri di successo del field test)

Per ogni skill e agente coinvolto, registrare:

- **Trigger atteso vs reale**: ha agito quando previsto?
- **Auto vs manuale**: i 3 skill `disable-model-invocation` (interview-driver,
  project-bootstrap, fastapi-react-vibe) NON devono auto-attivarsi; gli altri sì.
- **Mis-fire / no-fire**: la `description` ha causato attivazioni sbagliate o
  mancate? Su quale frase?
- **Rules**: `python.md` si è caricata lavorando sui `.py`?
- **Hook**: `auto-format.sh` ha formattato dopo edit `.py`? `protect-files.sh`
  ha bloccato un eventuale tentativo su file protetti?
- **Auto mode**: ha bloccato qualcosa di legittimo (falso positivo)?

Il test ha successo se produce un quadro chiaro di questi punti, non se la CLI
è "perfetta" (la CLI è strumentale).

## 5. Deliverable

`vibe-coding-system/docs/field-test-2026-05-18.md` con:

- Tabella: per ogni skill/agente → trigger atteso, trigger reale, esito.
- Elenco mis-fire/no-fire osservati con la frase scatenante.
- **Lista concreta di tweak** alle `description`/prompt da applicare (il valore
  vero del test).

Il codice della CLI è secondario / usa-e-getta.

## 6. Fuori scope

- Qualità/completezza della CLI come prodotto (è strumentale).
- Modifiche a skill/agenti durante il test (si raccolgono solo osservazioni;
  i tweak si applicano dopo, in un ciclo separato).
- Track FastAPI+React / iOS / vanilla (questo pilota copre il core Python loop;
  gli altri track in field test successivi se serve).

## 7. Criteri di successo

Workflow eseguito end-to-end; log osservazioni completo con tabella trigger e
lista tweak; nessuna modifica a `~/.claude/` durante il test; pilota in git
proprio, blueprint repo intatto/no-git.
