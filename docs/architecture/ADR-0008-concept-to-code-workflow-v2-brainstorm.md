# ADR-0008 — `concept-to-code` workflow v2: Gate 0, brownfield mode, brainstorm-gate + nuova skill `design-brainstorm`

**Status:** Accepted — 2026-05-21 (implemented via plan `2026-05-21-concept-to-code-workflow-v2.md`; design-brainstorm PASS=9; concept-to-code self-test PASS=20; review-triage-fix PASS=51; smoke-e2e PASS)
**Authors:** Adriano (architect agent) per Stefano Ferri
**Supersedes:** none (estende ADR-0003, non lo rimpiazza)
**Superseded by:** none
**Related:**
- `docs/architecture/ADR-0003-concept-to-code-chain.md` (Accepted 2026-05-20 — chain v1)
- `docs/architecture/ADR-0007-concept-to-code-e2e-smoke.md` (Accepted 2026-05-20 — smoke-e2e)
- `docs/superpowers/specs/2026-05-21-concept-to-code-workflow-v2-design.md`
- `docs/superpowers/specs/2026-05-21-design-brainstorm-skill-design.md`
- `docs/superpowers/plans/2026-05-21-concept-to-code-workflow-v2.md`
- `~/.claude/skills/concept-to-code/SKILL.md` (skill da patchare)
- `~/.claude/skills/concept-to-code/scripts/manifest-{init,validate,transition}.sh`
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` (self-test, baseline PASS=13)
- `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` (smoke, ADR-0007)
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (anchor harness, baseline PASS=49)
- `~/.claude/skills/interview-driver/SKILL.md` (Step 1, produce SPEC)
- `~/.claude/skills/claude-md-generator/SKILL.md` (Step 3, produce CLAUDE.md)
- `~/.claude/agents/architect.md` (dispatched in Step 2)
- Memory `feedback_bash32-constraint.md`
- Memory `feedback_disable-model-invocation-strong.md`
- Memory `feedback_micropiano-refactor-cleanup.md`

---

## 1. Context

ADR-0003 ha trasformato il workflow concept→code (blueprint §11) da prosa a state
machine deterministica con manifest YAML, 5 gate HITL, e dispatch pinned. ADR-0007 ne
ha aggiunto lo smoke-e2e. Il **primo uso reale** del chain (progetto `rempay`,
2026-05-21) lo ha validato end-to-end ma ha esposto **tre gap di workflow** che
condividono lo stesso punto di intervento (`concept-to-code/SKILL.md` + i 3 helper
bash): frammentarli in tre ADR separati produrrebbe debito di coordinamento sullo
stesso file. Sono trattati insieme.

### Gap #1 — Manca Gate 0 (decisione chain-vs-leggero)

La sez. `## 1. When to invoke` dello SKILL.md elenca criteri "Do NOT invoke for"
(SPEC+ADR già esistenti, micro-scope <3 file, iterazione su ADR). Oggi l'orchestrator,
quando rileva questi criteri, decide **in silenzio** se fare il chain completo o fare
fallback a workflow leggero. Nel test reale ha fatto fallback senza chiedere; è servito
l'intervento manuale di Stefano per forzare il chain. La decisione di processo
appartiene all'utente, non all'orchestrator: è una scelta di costo/profondità, non
tecnica.

### Gap #2 — Manca "brownfield mode"

Il chain v1 assume implicitamente greenfield: Step 1 interview scrive `SPEC.md`, Step 3
`claude-md-generator` rigenera `CLAUDE.md` da zero. Sul progetto rempay (brownfield)
l'orchestrator ha gestito **bene ma ad-hoc** due casi:
- **SPEC esistente e congelata:** ha saltato Step 1 (l'interview l'avrebbe sovrascritta)
  e puntato `artifacts.spec` alla SPEC esistente.
- **CLAUDE.md curato a mano (97 righe di gotcha):** ha capito che `claude-md-generator`
  rigenererebbe da zero degradando il file; ha prodotto invece una proposta **additiva**.

Questi comportamenti sono corretti ma non codificati → dipendono dalla sveglieria
dell'orchestrator caso per caso (fragile, non riproducibile, drift garantito al prossimo
uso).

### Gap #3 — Manca un brainstorm-gate opzionale tra SPEC e architettura

Oggi, una volta pronto lo SPEC, lo Step 2 dispatcha direttamente l'architect che decide
l'architettura **da solo** (monologico). Manca uno spazio dialogico per esplorare
alternative di *metodologia applicativa* e *idee nuove* CON l'utente, prima di fissare
l'ADR. Questo è il punto in cui un'esplorazione strutturata fa la differenza
sull'architettura finale.

### Direzione

1. **Gate 0** all'avvio del chain: quando rileva criteri di esclusione, si ferma e
   chiede esplicitamente `[c] chain / [l] leggero / [a] abort`. La decisione torna
   all'utente.
2. **Distinzione greenfield/brownfield** codificata: Step 1 e Step 3 si comportano in
   modo diverso a seconda della presenza di SPEC.md / CLAUDE.md.
3. **Brainstorm-gate** opzionale tra Step 1 e Step 2, che invoca una **nuova skill
   `design-brainstorm`** la quale esplora alternative di approccio e produce un
   `BRAINSTORM.md` che alimenta il dispatch dell'architect.
4. **Nuova skill `design-brainstorm`** di alta qualità metodologica (vedi spec
   dedicata), invocabile sia standalone sia dal chain.

### Vincoli ereditati (HARD)

- **Anchor preservation:** review-triage-fix harness PASS=49, concept-to-code self-test
  PASS=13 — mai scendere. Solo append di anchor.
- **Bash 3.2.57** per ogni script: no assoc array, no `mapfile`, no `${v^^}`, no `<()`,
  no here-string. temp-file + grep maps (memory `feedback_bash32-constraint.md`).
- **Coexistence:** il redesign NON deve rompere i chain già completati (manifest rempay
  `status: completed` su schema 1.0). Le nuove transizioni devono essere
  retrocompatibili con schema 1.0 oppure introdurre schema 1.1 con migrazione
  documentata.
- **`disable-model-invocation`:** la skill `design-brainstorm` DEVE essere invocabile
  dal chain (brainstorm-gate) → NON deve avere `disable-model-invocation: true`
  (memory `feedback_disable-model-invocation-strong.md`).
- **Sub-agent non spawnano sub-agent:** lo skill istruisce l'orchestrator (main CLI).
- **Repo blueprint NON-git:** nessuno step git nei plan.

---

## 2. Decision

Le sette domande architetturali del brief sono risolte come segue. Ogni decisione ha le
sue alternative scartate nella sez. 3.

### 2.1 (Q1) Nome della skill: **`design-brainstorm`**

Scelto `design-brainstorm`. Comunica sia il *quando* (fase di design, pre-architettura)
sia il *cosa* (brainstorm di approcci). Frontmatter `name: design-brainstorm`, directory
`~/.claude/skills/design-brainstorm/`.

### 2.2 (Q2) Gate 0 — rilevamento criteri di esclusione: **check deterministici via file + stima da SPEC, decisione all'utente**

Gate 0 fa parte di Form A (start chain), eseguito subito dopo `manifest-init.sh` (stato
`step_0_init`), PRIMA della transizione a `step_1_interview`. Rileva due criteri con
controlli deterministici:

- **Criterio A — "SPEC+ADR già esistenti":** check file. Esiste `<project-root>/SPEC.md`
  AND esiste almeno un file `<project-root>/docs/architecture/ADR-*.md`. Entrambi
  presenti → criterio A attivo.
- **Criterio B — "micro-scope <3 file":** NON è stimabile in modo affidabile prima
  dell'interview/architettura. Quindi Gate 0 NON conta i file: presenta il criterio B
  come **flag dichiarativo** che l'utente può confermare ("è un micro-scope?"). Lo
  conta l'utente, non l'orchestrator. Questo evita falsi negativi/positivi da euristiche
  fragili (lezione `swarm-testcmd`: meglio tier autoritativo che euristica).

Se nessun criterio è attivo → Gate 0 passa silenziosamente (UX invariata per il caso
greenfield comune). Se almeno un criterio è attivo → blocca e chiede:

```
============================================================
concept-to-code · Gate 0 · TRIAGE CHAIN
============================================================
Criteri di esclusione rilevati:
  [x] SPEC.md + ADR già esistenti in <project-root>
  [ ] Micro-scope (<3 file) — confermalo tu
Manifest: <manifest-path>
============================================================
HITL Gate 0: chain_triage
  [c] chain completo (procedi con interview/architettura)
  [l] workflow leggero (plan diretto, niente chain)
  [a] abort chain
> _
```

`[l]` → `manifest-transition.sh <m> aborted aborted` con `next_action` che documenta il
fallback a workflow leggero (l'utente prosegue fuori dal chain). Non è un fallimento:
è una scelta legittima. `[a]` → abort. `[c]` → procede a Step 1.

Il rilevamento dei criteri è incapsulato in un nuovo helper `scripts/gate0-detect.sh`
(bash 3.2-clean) per testabilità isolata e riuso.

### 2.3 (Q3) Brownfield detection: **automatica (presenza file) + conferma utente al Gate 0**

Brownfield è derivato deterministicamente dalla presenza di `<project-root>/SPEC.md`:

- **Greenfield** (no `SPEC.md`): Step 1 interview produce SPEC nuovo; Step 3 genera
  `CLAUDE.md` (da zero se assente, additivo se presente — vedi sotto).
- **Brownfield** (`SPEC.md` esiste): Step 1 SALTATO; `artifacts.spec` punta alla SPEC
  esistente; Gate 1 marcato "spec pre-esistente approvata".

La detection è **automatica** (check file), ma la **conferma è implicita nel Gate 0**:
quando `SPEC.md` esiste, il criterio A è già attivo e l'utente, scegliendo `[c]`, sta di
fatto confermando di voler procedere in brownfield mode. Non si introduce un gate
separato per la conferma brownfield (eviterebbe gate fatigue, antipattern noto da
ADR-0003 §1).

Il flag `mode: greenfield|brownfield` viene scritto nel manifest (nuovo campo
top-level, vedi 2.6) per renderlo ispezionabile e per pilotare il comportamento di Step
1 e Step 3 in modo deterministico, non a discrezione dell'orchestrator.

Ortogonalmente, il comportamento di Step 3 su `CLAUDE.md` esistente diventa **sempre
additivo** (mai degradante), indipendentemente da greenfield/brownfield: se `CLAUDE.md`
esiste, `claude-md-generator` produce `CLAUDE.md.proposed` in **modalità additiva**
(CLAUDE.md attuale preservato + sezione "## Decisioni dal chain <topic>" che referenzia
il nuovo ADR), e Gate 3 mostra il diff. Questo codifica la mossa ad-hoc di rempay.

### 2.4 (Q4) Dove vive `BRAINSTORM.md`: **project root + campo `artifacts.brainstorm` nel manifest**

`BRAINSTORM.md` vive in `<project-root>/BRAINSTORM.md` (stesso livello di SPEC.md/ARCH.md
— coerenza posizionale con gli altri artefatti di design del chain). Il manifest lo
traccia con il nuovo campo `artifacts.brainstorm` (assente=null, popolato quando il
brainstorm-gate produce il file). Vive accanto a SPEC.md e ARCH.md, non in `docs/`,
perché è un artefatto di alto livello (come SPEC/ARCH) e non un documento di archivio.

### 2.5 (Q5 + Q7) State machine: **schema 1.1 con nuovi campi opzionali; nessun nuovo stato `current_step` obbligatorio per Gate 0/brownfield; un solo nuovo stato per il brainstorm-gate**

Principio guida: minimizzare i nuovi stati nella enum `current_step` (ogni stato nuovo
= nuove transizioni legali + rischio rottura smoke-e2e). Si usano **flag nel manifest**
dove possibile, **stati nuovi** solo dove serve un punto di ripresa cross-sessione.

- **Gate 0:** NON è uno stato. È un check eseguito in `step_0_init` prima della
  transizione a `step_1_interview`. Esito registrato nel campo `gate0` del manifest. La
  transizione `step_0_init → step_1_interview` resta legale e invariata. `[l]`/`[a]`
  usano la transizione wildcard `* → aborted` già supportata.
- **Brownfield:** NON è uno stato. È il flag `mode: brownfield`. In brownfield, Step 1
  è saltato → si usa la transizione **nuova** `step_1_interview → gate_1_spec_review`
  che già esiste, ma serve poterci arrivare senza interview reale. Soluzione: in
  brownfield l'orchestrator transiziona comunque `step_0_init → step_1_interview` (lo
  stato "interview" esiste ma è no-op: punta `artifacts.spec` all'esistente) →
  `step_1_interview → gate_1_spec_review`. Nessuna transizione nuova richiesta. Gate 1
  marcato "spec pre-esistente".
- **Brainstorm-gate:** richiede UN nuovo stato `gate_1b_brainstorm_decision` tra
  `gate_1_spec_review` e `step_2_architecture`, perché è un punto in cui può partire una
  sessione di brainstorming potenzialmente lunga e l'utente può scegliere y/n. Nuove
  transizioni legali:
  - `gate_1_spec_review → gate_1b_brainstorm_decision` (sostituisce di fatto il path
    diretto; ma il path diretto `gate_1_spec_review → step_2_architecture` RESTA legale
    per retrocompat con manifest v1.0 e smoke-e2e esistente).
  - `gate_1b_brainstorm_decision → step_2_architecture` (esito n, o esito y completato).

  Il brainstorm-gate `n` → transizione diretta a `step_2_architecture` (comportamento
  identico a oggi: architect diretto). Il brainstorm-gate `y` → la skill
  `design-brainstorm` viene invocata in-session, scrive `BRAINSTORM.md`, popola
  `artifacts.brainstorm`, poi transizione a `step_2_architecture` con il brief incluso
  nel dispatch architect.

- **Schema version:** si passa a `manifest_schema_version: "1.1"`. La validate accetta
  **sia 1.0 sia 1.1** (retrocompat: i manifest rempay completati restano validi). I
  campi nuovi (`mode`, `gate0`, `artifacts.brainstorm`) sono **opzionali** in 1.1:
  `manifest-validate.sh` non li richiede, ma se presenti ne valida i valori. Migrazione
  documentata: un manifest 1.0 è un manifest 1.1 valido senza i campi nuovi (additive,
  forward-only). `manifest-init.sh` scrive 1.1 con i campi nuovi popolati.

### 2.6 (Q6) Chi scrive il manifest: **la skill `design-brainstorm` scrive SOLO `BRAINSTORM.md`; l'orchestrator (concept-to-code) aggiorna `artifacts.brainstorm`**

Separazione delle responsabilità coerente con ADR-0003: le skill foglia (interview-driver,
claude-md-generator) producono artefatti, l'orchestrator (concept-to-code) possiede il
manifest. `design-brainstorm` non conosce il manifest né lo schema → resta riusabile
standalone fuori dal chain. Dopo che `design-brainstorm` ritorna, l'orchestrator scrive
`artifacts.brainstorm = <project-root>/BRAINSTORM.md` con lo stesso pattern di edit YAML
già usato per `artifacts.spec`/`adr`/`plan`.

### 2.7 Helper bash nuovo e modifiche agli script esistenti

- **Nuovo `scripts/gate0-detect.sh`** (bash 3.2): args `<project-root>`, stampa su
  stdout i criteri attivi (`spec_adr_exist` se SPEC.md+ADR presenti; `mode=greenfield`
  o `mode=brownfield`). Exit 0 sempre (è un detector, non un validatore). Testabile
  isolatamente.
- **`manifest-init.sh`:** scrive `manifest_schema_version: "1.1"`, aggiunge campi
  `mode`, `gate0`, e `artifacts.brainstorm: null`. Il valore di `mode` è passato come
  4° argomento opzionale (default `greenfield`); `init` può chiamare `gate0-detect.sh`
  per derivarlo, oppure riceverlo dall'orchestrator.
- **`manifest-validate.sh`:** accetta schema 1.0 OR 1.1; aggiunge `gate_1b_brainstorm_decision`
  alla enum degli stati validi; se `mode` presente, valida ∈ {greenfield, brownfield};
  invariante hitl_gates resta `>= 4` (era `== 4`; si rilassa a `>= 4` per ammettere un
  eventuale gate0/gate1b nell'audit trail senza rompere i manifest a 4 gate). Vedi 3.5.
- **`manifest-transition.sh`:** aggiunge le 2 nuove pair legali (vedi 2.5),
  preservando le 16 esistenti.

### 2.8 La skill `design-brainstorm` (riassunto; dettaglio nella spec dedicata)

Esplora **metodologia applicativa** e **idee nuove** PRIMA che l'architettura sia
fissata. NON estrae requisiti (interview-driver), NON scrive SPEC/plan (resto del chain),
NON invoca writing-plans (differenza chiave da `superpowers:brainstorming`, che è uno
stato terminale e confliggerebbe col chain). Usa `AskUserQuestion` in flusso dialogico
multiple-choice, una tecnica alla volta. Tecniche cardine: first-principles, analogie
cross-dominio, inversione, vincoli forzati, assumption-busting, alternative genuinamente
diverse (2-4), idee adiacenti. Output: `BRAINSTORM.md` strutturato (problema riformulato,
assunzioni sfidate, 2-4 alternative con trade-off, idee adiacenti, raccomandazione
preliminare). Lingua: comunicazione in italiano, template in inglese. No
`disable-model-invocation`.

---

## 3. Alternative considerate e scartate

### 3.1 (Q1) Nome skill — alternative

- **`brainstorm-explore`** — scartato: ridondante (brainstorm già implica esplorazione)
  e non comunica la fase di design. Confondibile con un tool generico di esplorazione.
- **`design-explore`** — scartato: troppo generico, si sovrappone semanticamente a
  `interview-driver` (anche l'interview "esplora").
- **`approach-brainstorm`** — scartato: "approach" è preciso ma poco idiomatico;
  `design-` come prefisso è più leggibile nel namespace skill.
- **Scelto `design-brainstorm`:** prefisso `design-` ancora la fase, `-brainstorm`
  il metodo. Distinto da `interview-driver` (requisiti) e da `superpowers:brainstorming`
  (che scrive spec).

### 3.2 (Q2) Gate 0 — alternative

- **Conteggio file automatico per il micro-scope** — scartato: impossibile stimare i
  file toccati prima di interview/architettura senza euristiche fragili (numero di file
  esistenti ≠ file da toccare). Falsi positivi/negativi minerebbero la fiducia nel gate.
  Lezione `swarm-testcmd`: preferire tier autoritativo (l'utente) all'euristica.
- **Decisione automatica dell'orchestrator (status quo)** — scartato: è esattamente il
  Gap #1. La scelta è di processo/costo, appartiene all'utente.
- **Gate 0 sempre mostrato anche in greenfield pulito** — scartato: gate fatigue
  inutile sul caso comune (nuovo progetto senza SPEC/ADR). Gate 0 è silenzioso quando
  nessun criterio è attivo.
- **Scelto:** check deterministici (file presence) per criterio A; flag dichiarativo
  utente-confermato per criterio B; gate mostrato solo se almeno un criterio attivo.

### 3.3 (Q3) Brownfield detection — alternative

- **Esplicita via flag CLI** (`/concept-to-code --brownfield <topic>`) — scartato:
  l'utente non dovrebbe dover sapere se è greenfield/brownfield; la presenza di SPEC.md
  è il segnale autoritativo. Flag manuale = dimenticabile = drift.
- **Solo automatica, senza conferma** — scartato: rischierebbe di saltare l'interview su
  un progetto dove l'utente VOLEVA rigenerare la SPEC. La conferma implicita al Gate 0
  copre il caso senza un gate dedicato.
- **Gate brownfield dedicato separato da Gate 0** — scartato: due gate consecutivi
  all'avvio = fatigue. Si fonde nella scelta `[c]` del Gate 0.
- **Scelto:** automatica (presenza SPEC.md) + conferma implicita nella scelta `[c]` del
  Gate 0 + flag `mode` nel manifest per determinismo.

### 3.4 (Q4) Posizione di BRAINSTORM.md — alternative

- **Sezione del manifest YAML** — scartato: il brief è prosa lunga e dialogica; inquinerebbe
  il manifest (che deve restare parsabile da grep in bash 3.2) e violerebbe la
  separazione "manifest = stato, file = artefatto" di ADR-0003.
- **`docs/brainstorm/<date>-<topic>.md`** — scartato: troppo nascosto per un artefatto
  che l'utente deve leggere prima di approvare l'architettura; incoerente con
  SPEC.md/ARCH.md a project root.
- **`docs/superpowers/specs/`** — scartato: quella cartella è per gli spec di design del
  *sistema*, non per i brief di brainstorming dei *progetti target*.
- **Scelto:** `<project-root>/BRAINSTORM.md` + `artifacts.brainstorm` nel manifest.

### 3.5 (Q5) State machine — alternative

- **Nessun nuovo stato, tutto a flag** — scartato per il brainstorm-gate: il brainstorm
  può essere una sessione lunga; serve un punto di ripresa nominato e un esito
  ispezionabile. Per Gate 0 e brownfield invece i flag bastano (nessun lavoro lungo da
  riprendere).
- **Tre nuovi stati (gate_0, brownfield_skip, gate_1b)** — scartato: gate_0 e
  brownfield non hanno bisogno di un punto di ripresa cross-sessione (sono istantanei
  all'avvio); aggiungere stati = più transizioni legali = più superficie di rottura per
  lo smoke-e2e e la validate. Si aggiunge solo `gate_1b_brainstorm_decision`.
- **Riscrivere lo schema da zero a 2.0** — scartato: romperebbe i manifest rempay
  completati. Schema 1.1 additive è retrocompatibile.
- **Invariante `hitl_gates == 4` mantenuta rigida** — scartato: bloccherebbe
  l'eventuale audit trail di Gate 0/1b. Si rilassa a `>= 4` (additive: i manifest
  esistenti a 4 gate restano validi).
- **Scelto:** schema 1.1 additive; 1 nuovo stato (`gate_1b_brainstorm_decision`); 2
  nuove pair; path diretto `gate_1_spec_review → step_2_architecture` preservato per
  retrocompat; `hitl_gates >= 4`.

### 3.6 (Q6) Chi scrive il manifest — alternative

- **`design-brainstorm` scrive anche `artifacts.brainstorm`** — scartato: accoppierebbe
  la skill al manifest schema, rompendo la sua riusabilità standalone e violando la
  separazione di responsabilità di ADR-0003 (le foglie non conoscono il manifest).
- **Scelto:** `design-brainstorm` scrive solo `BRAINSTORM.md`; concept-to-code aggiorna
  `artifacts.brainstorm`.

### 3.7 (Q7) Fallback brainstorm-gate=n — alternative

- **Comportamento diverso da oggi (es. mini-prompt)** — scartato: il brief richiede
  esplicitamente che `n` sia identico al comportamento attuale (architect diretto). Zero
  regressioni per chi non usa il brainstorm.
- **Scelto:** `n` → transizione a `step_2_architecture`, dispatch architect identico ad
  ADR-0003 (nessun `BRAINSTORM.md`, `artifacts.brainstorm` resta null).

---

## 4. Consequences

### Positive

- Gap #1/#2/#3 risolti insieme su un unico punto di intervento → zero debito di
  coordinamento sullo SKILL.md.
- La decisione chain-vs-leggero e greenfield-vs-brownfield diventano **deterministiche e
  riproducibili**, non dipendenti dalla sveglieria dell'orchestrator.
- Il brainstorm-gate aggiunge esplorazione dialogica di alta qualità senza alterare il
  path di default (n = comportamento attuale).
- Retrocompat totale: schema 1.1 additive, path diretto preservato, manifest rempay
  completati restano validi.
- `design-brainstorm` è riusabile standalone e dal chain (no `disable-model-invocation`).

### Negative

- Aumenta la superficie dello SKILL.md (Gate 0 + 1b + brownfield branching) → più
  complesso da leggere. Mitigato dalla sez. State machine aggiornata e da uno schema
  diagram chiaro.
- Schema 1.1 introduce un check di versione dual (1.0 OR 1.1) nella validate → leggera
  complessità in più.
- Nuova skill = nuovo harness da mantenere verde (debito di manutenzione).
- Il flag `mode` aggiunge un punto in cui l'orchestrator deve agire correttamente; è
  mitigato dal fatto che `gate0-detect.sh` lo deriva deterministicamente.

### Neutral

- `BRAINSTORM.md` è opzionale: assente quando il brainstorm-gate è `n`.
- Il workflow leggero scelto al Gate 0 esce dal chain (manifest `aborted` con
  `next_action` documentato); non è gestito dal chain oltre quel punto.
- Numero di gate HITL variabile (4 senza brainstorm, 5+ con) — coerente con la natura
  opzionale del brainstorm-gate.

---

## 5. References

- ADR-0003 (chain v1), ADR-0007 (smoke-e2e).
- Spec workflow v2: `docs/superpowers/specs/2026-05-21-concept-to-code-workflow-v2-design.md`.
- Spec skill: `docs/superpowers/specs/2026-05-21-design-brainstorm-skill-design.md`.
- Plan: `docs/superpowers/plans/2026-05-21-concept-to-code-workflow-v2.md`.
- Blueprint §11 (workflow concept→code), §8 (skill).
- Memory: `feedback_bash32-constraint.md`, `feedback_disable-model-invocation-strong.md`,
  `feedback_micropiano-refactor-cleanup.md`.
