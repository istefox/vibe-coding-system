# ADR-0003 — `concept-to-code` skill orchestratore del chain concept→code

**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-concept-to-code-chain.md; review-triage-fix harness PASS=47; concept-to-code self-test PASS=10; refactor-snapshot self-test PASS=11 unchanged)
**Authors:** Adriano (architect agent) per Stefano Ferri
**Supersedes:** none
**Superseded by:** none
**Related:**
- `docs/superpowers/specs/2026-05-20-concept-to-code-chain-design.md`
- `docs/superpowers/plans/2026-05-20-concept-to-code-chain.md`
- `docs/vibe-coding-system.md` (blueprint sez. 11 — workflow concept→code)
- `~/.claude/skills/interview-driver/SKILL.md` (skill custom utente, riusato)
- `~/.claude/skills/adr-writer/SKILL.md` (skill custom utente, riusato)
- `~/.claude/skills/claude-md-generator/SKILL.md` (skill custom utente, riusato)
- `~/.claude/agents/architect.md` (sub-agent dispatched in Step 2)
- `~/.claude/agents/coder.md` (sub-agent dispatched in Step 5, ha già Pre-flight Pattern Classifier ADR-0001)
- `~/.claude/agents/reviewer.md` (item 5 Pattern-drift check, ADR-0001)
- `~/.claude/agents/refactorer.md` (Snapshot Harness Integration, ADR-0002)
- `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2 Add+Remove rule, opzionalmente invocata in Step 6)
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (anchor harness target, PASS=45 baseline 2026-05-20)
- ADR-0001 (Pre-flight Pattern Classifier, Accepted 2026-05-20)
- ADR-0002 (Refactor Snapshot Harness, Accepted 2026-05-20)
- Memory `feedback_bash32-constraint.md`
- Memory `feedback_micropiano-refactor-cleanup.md`

---

## 1. Context

Il blueprint del sistema multi-agente (`docs/vibe-coding-system.md` sez. 11) descrive il
workflow concept→code come una catena lineare con HITL gates impliciti:

```
interview → SPEC.md → ARCH.md (+ ADR) → CLAUDE.md di progetto →
  fresh session → scaffold in plan mode → impl multi-agent → review → commit
```

Oggi questo workflow è **prosa**, non eseguibile. Ogni feature deployata segue il chain
ad memoriam dell'orchestrator. Tre evidenze convergenti motivano l'intervento.

### Evidenze

1. **Pattern ripetuto nella sessione 2026-05-20.** Sono stati dispatched manualmente
   `architect` → `coder` due volte nella stessa giornata (ADR-0001 + ADR-0002) con
   prompt template quasi identico. La ripetizione manuale è la firma di un'automation
   mancante. Drift potenziale tra dispatch (es. varianti di brief, vincoli HARD
   ricopiati mano).

2. **Workflow blueprint sez. 11 è raccomandazione, non skill.** La distanza fra
   blueprint e pratica si traduce in inconsistenza fra feature consecutive: ADR-0001
   ha generato 8 task TDD, ADR-0002 ne ha generati 8 con struttura simile ma non
   identica. La drift è invisibile finché non si confrontano due plan side-by-side.

3. **Le 3 feature deployate 2026-05-20** (ADR-0001 coder pre-flight + ADR-0002
   refactor-snapshot + review-triage-fix v1.2 Add+Remove) condividono lo *stesso* flow
   `architect produce 3 deliverable → coder implementa 6-8 task TDD`. Una skill
   orchestratore unica avrebbe ridotto 3 dispatch manuali a 1, con drift azzerato per
   costruzione.

### Problema architetturale

Il workflow concept→code è uno *state machine deterministico* (Step 1..6, HITL gates,
fresh session checkpoint, manifest tra sessioni) ma è oggi codificato come prosa
descrittiva. Quattro conseguenze:

- **Drift cross-feature:** ogni dispatch architect→coder reinventa il prompt template.
- **Loss of state allo Step 4 (fresh session):** quando l'orchestrator apre nuova
  sessione perde tutto il context di interview/ADR/CLAUDE.md. Oggi si ri-anchora
  rileggendo i file, ma senza guarantee che riprenda dal punto giusto.
- **HITL gates impliciti:** l'utente non sa a priori quanti gate ci sono né cosa
  approva. Il "concept-to-code" oggi *sembra* atomico ma è 3-4 turni HITL.
- **Coexistenza fragile con feature deployate 2026-05-20:** Pre-flight Pattern
  Classifier (coder), Pattern-drift check (reviewer), Snapshot Harness (refactorer)
  sono attive ma non orchestrate. Un dispatch manuale può saltarle senza errore.

### Direzione

Introdurre una **skill markdown chiamabile** `concept-to-code` in
`~/.claude/skills/concept-to-code/` che codifica il chain blueprint sez. 11 come
state machine eseguibile con:

- **Manifest YAML persistente** in `docs/manifests/YYYY-MM-DD-<topic>.manifest.yml`
  del progetto target, stato del chain attraverso fresh-session boundary.
- **HITL gates espliciti** (3 bloccanti + 1 fresh-session checkpoint informativo).
- **Resume semantics** via `/concept-to-code resume <manifest-path>` dopo fresh
  session.
- **Dispatch pinned** ad agent esistenti (`architect`, `coder`) con prompt template
  versionati dentro la skill (no drift per costruzione).
- **Riuso** delle 3 skill custom già presenti: `interview-driver` (NON
  `superpowers:brainstorming`), `adr-writer`, `claude-md-generator`.
- **Coexistenza ortogonale** con ADR-0001 / ADR-0002 / v1.2: la skill *invoca* le
  feature deployate, non le sostituisce.

L'obiettivo: trasformare il chain concept→code da "prosa raccomandata" a "skill con
state machine deterministica e guard rail", riducendo drift e HITL fatigue.

### Vincoli ereditati (HARD)

- **Anchor preservation `review-triage-fix` harness:** PASS=45 post ADR-0002
  (2026-05-20). Mai scendere. Target post-feature: **PASS=47** (+2 anchor structural
  in `review-triage-fix/tests/run-tests.sh` su esistenza skill `concept-to-code` e
  reference a manifest schema — vedi Decision §2.10).
- **Skill self-test target:** la skill `concept-to-code` ha proprio harness in
  `tests/run-tests.sh`. Target **PASS=10** (10 assertion: manifest schema validation,
  step-state transitions, resume semantics, override safe-to-restart, contract
  invariants).
- **Bash 3.2.57** per ogni script helper della skill (manifest parser/validator). No
  assoc array, no `mapfile`, no `${v^^}`, no `<()` process substitution, no
  here-string. Pattern già consolidato dai 45 anchor del harness review-triage-fix
  e dai 11 self-test refactor-snapshot.
- **Sub-agent non spawnano sub-agent** (blueprint sez. 2). Lo skill è istruzione
  per l'**orchestrator** (main agent), non per sub-agent. I dispatch
  `architect`/`coder` partono dall'orchestrator (sessione CLI principale), MAI da
  un sub-agent. La skill markdown chiarisce questo invariante esplicitamente nel
  body.
- **Fresh session caveat (blueprint sez. 11):** lo skill DEVE rispettare il "fresh
  session" tra interview/architecture (Step 1-3) e implementazione (Step 5) perché
  il context window dell'orchestrator si riempie di interview Q&A. Il manifest YAML
  è il meccanismo di state-passing cross-session.
- **Coesistenza con feature deployate 2026-05-20:** Pre-flight Pattern Classifier
  (coder, ADR-0001), Pattern-drift check (reviewer, ADR-0001), Snapshot Harness
  (refactorer, ADR-0002), Add+Remove rule v1.2 — **tutti restano attivi e invariati**.
  La skill USA queste feature, non le edita.
- **No backwards-compat shim:** se la skill modifica `coder.md` per supportare
  `--manifest` input, è una sostituzione pulita (no flag legacy parallelo). MA: la
  decisione corrente (vedi §2.9) è di **non modificare coder.md**: la skill passa
  il manifest content nel prompt del dispatch, non come argomento esterno.
- **Lingua:** SKILL.md in inglese (contract), ADR/spec/plan/memory in italiano,
  manifest YAML field name in inglese, commit/code in inglese.
- **Repo blueprint NON-git:** vibe-coding-system non ha git inizializzato. Il plan
  non propone operazioni git per i deliverable doc. La skill stessa, quando
  eseguita su un progetto target git-tracked, NON propone commit nel Step 6: il
  commit resta HITL gate manuale dell'utente (coerente con global CLAUDE.md).
- **Auto mode per questo dispatch architect:** nessun HITL durante il design. Però
  il design della skill prevede HITL al runtime (vedi §2.4).

### Assunzioni esplicite (non verificate empiricamente)

- L'orchestrator (main agent CLI) onora le istruzioni di una skill markdown
  `disable-model-invocation: false`. Verificato dal pattern usage di
  `interview-driver`, `adr-writer`, `claude-md-generator`. Non verificato per skill
  con state machine multi-step e resume.
- La directory `docs/manifests/` può essere creata nel progetto target senza
  conflitto con convenzioni esistenti. Per i progetti pilota attuali (es.
  `pricing-markup-cli`, `swarm-testcmd`) verificato come safe (path libero).
- L'utente accetta 3 HITL gate sincroni nel flow base (Step 1-3) come trade-off
  contro drift. Razionalizzato dalla memory `feedback_hitl-and-security-discipline.md`
  ("security-warning vanno trattati seriamente, riscrittura conservativa") —
  l'utente preferisce gate espliciti a dispatch silenziosi.
- La fresh session in Step 4 viene effettivamente aperta dall'utente in una nuova
  shell CLI Claude Code. Non automatizzabile lato skill (la skill non può
  `exec claude --new-session`). Risolto via instruction esplicita + manifest
  pickup.

---

## 2. Decision

Deploy della skill `~/.claude/skills/concept-to-code/` come orchestratore del chain
concept→code, decomposto nelle 10 decisioni che seguono. Ognuna corrisponde a una
delle 10 domande architetturali del brief.

### 2.1 — Forma del componente (Q1)

**Decisione:** skill markdown chiamabile in `~/.claude/skills/concept-to-code/SKILL.md`
+ 3 helper bash 3.2 in `scripts/` (manifest validator, step-state transition,
resume detector) + self-test in `tests/run-tests.sh`. NO slash command dedicato,
NO agent dedicato.

**Razionale:** lo skill è la primitiva nativa di Claude Code per istruire il
main agent (vedi pattern di `interview-driver`, `adr-writer`, `claude-md-generator`
già in uso). Slash command sarebbero un duplicate layer sopra lo skill. Un
`orchestrator-chain` agent dedicato violerebbe il vincolo HARD blueprint sez. 2
("sub-agent non spawnano sub-agent"): l'orchestrator è già la sessione principale,
non un sub-agent. La skill viene invocata via prompt utente
(`/skill concept-to-code <topic>` o pattern naturale "fammi il chain concept→code
per <topic>") e dispatcha gli agent dall'orchestrator.

### 2.2 — State persistence (Q2)

**Decisione:** manifest YAML in
`<project-root>/docs/manifests/YYYY-MM-DD-<topic-slug>.manifest.yml`. State
machine fields: `version`, `topic`, `created_at`, `current_step`, `status`,
`artifacts.{spec,arch,adr,plan,project_claude_md}` con path assoluti, `hitl_gates`
list con timestamp di approval, `session_boundary` flag (true dopo Step 4), `next_action`
hint stringa.

**Razionale:** manifest YAML è leggibile dall'utente (debug), versionabile in
git con il progetto target, persiste cross-session by design (Step 4 fresh
session apre il manifest, non ricostruisce stato dal prompt). JSON era
candidate ma YAML è più human-readable per il use case (l'utente *deve* poter
leggere il manifest per sbloccare manualmente uno stallo). State inline nel
prompt fallisce allo Step 4 boundary (context window perso). Niente
persistence fallisce alla resume (nessun anchor per dove riprendere). Path
sotto `docs/manifests/` segue convenzione esistente (`docs/architecture/`,
`docs/superpowers/specs|plans/`).

### 2.3 — Resume/restart semantics (Q3)

**Decisione:** comando esplicito invocato dall'utente in fresh session:
`/skill concept-to-code resume <manifest-path>`. Auto-detection NO (troppo
implicito, rischio di pickup del manifest sbagliato). La skill, ricevuta
l'invocazione `resume`, legge il manifest, valida la struttura via
`scripts/manifest-validate.sh`, controlla il campo `current_step`, e procede
dal Step 5 se `current_step == "ready_for_implementation"`. Se il manifest
ha `current_step` antecedente a Step 4, fallisce con errore: "resume non
necessario, riprendi dalla sessione esistente". Se il manifest ha
`status: completed`, fallisce con errore: "chain già completo".

**Razionale:** invocazione esplicita evita ambiguità (l'utente sceglie quale
manifest riprendere; coexistenza con manifest in flight di altri progetti).
Auto-detection scartata: con multipli progetti aperti il rischio di picking
sbagliato è alto. Validation pre-resume tramite helper bash è cheap e blocca
manifest corrotti (es. editing manuale errato).

### 2.4 — HITL gate count + tipo (Q4)

**Decisione:** **3 HITL gates bloccanti** + 1 fresh-session checkpoint
informativo + 1 review gate opzionale.

| Gate    | Tipo          | Dopo Step | Cosa mostra                                         | Cosa attende                          |
| ------- | ------------- | --------- | --------------------------------------------------- | ------------------------------------- |
| Gate 1  | bloccante     | Step 1    | path SPEC.md + summary 5 righe                      | conferma "spec ok" / richiesta edit  |
| Gate 2  | bloccante     | Step 2    | path ADR + ARCH + plan + key decisions              | conferma "architecture ok" / edit    |
| Gate 3  | bloccante     | Step 3    | path CLAUDE.md generato + diff se overwrite         | conferma "project memory ok" / skip  |
| Gate 4  | checkpoint    | Step 4    | manifest path + comando resume                      | nessuna attesa (informativo)         |
| Gate 5  | opzionale     | Step 6    | review report + propose cycle review-triage-fix     | "run review" / "skip review"         |

**Razionale:** 3 gate sincroni mappano i 3 confini di "promise" del workflow
blueprint (spec→arch, arch→memory, memory→impl). Step 4 NON è gate: la skill
non può forzare la fresh session, può solo istruire. Step 5 NON è gate: una
volta dispatched il coder, il sub-agent gestisce il proprio flow (con
Pre-flight Pattern Classifier ADR-0001 che è esso stesso una forma di
self-gate). Step 6 review è opzionale perché la review-triage-fix v1.2 cycle
ha costo non-banale e non sempre giustificato. Bloccante > informativo
perché la memory `feedback_hitl-and-security-discipline.md` rinforza la
preferenza utente per gate espliciti su drift silenziosi. Auto mode futuro
(non in scope di questo ADR) potrà bypassare Gate 1 e Gate 3, MAI Gate 2
(architecture decision è irreversibile in pratica).

### 2.5 — Interview skill choice (Q5)

**Decisione:** **usare la skill custom esistente `interview-driver`**
(`~/.claude/skills/interview-driver/SKILL.md`). NON usare
`superpowers:brainstorming`. NON creare una nuova skill.

**Razionale:** `interview-driver` è già custom-tuned per il workflow
dell'utente: usa `AskUserQuestion` tool, una domanda alla volta, output
SPEC.md nella cartella corrente con sezioni standard. `superpowers:brainstorming`
è skill ufficiale superpowers ma non garantita per stabilità nel tempo
(dipende dal package superpowers); inoltre il suo output potrebbe non essere
strict-SPEC. Creare un nuovo `interview-driver-v2` introdurrebbe drift
gratuito (3 skill custom interview parallele). Mantenere unica fonte custom
riduce surface di manutenzione. La skill `concept-to-code` invoca
`interview-driver` come Step 1 e si aspetta `SPEC.md` nella cwd (path
catturato nel manifest).

### 2.6 — CLAUDE.md handling (Q6)

**Decisione:** **diff-aware con HITL gate**. Se `CLAUDE.md` non esiste alla
root del progetto target, generalo (via `claude-md-generator` skill) e
mostralo all'utente in Gate 3. Se esiste già, esegui `diff CLAUDE.md
CLAUDE.md.proposed` e mostra il diff in Gate 3 con opzioni:
`overwrite` / `merge manual` / `skip`. Default: `skip` (conservativo).

**Razionale:** overwrite cieco rischia di distruggere CLAUDE.md curati
dall'utente (es. progetto `vibe-coding-system` stesso ha CLAUDE.md di
~80 righe con riferimenti specifici alla specifica autoritativa).
Diff-aware è opzione safe-by-default. Skip-by-default rispetta la
preferenza utente "mai sovrascrivere un file esistente senza prima
mostrare il diff" (global CLAUDE.md, sezione Sicurezza & Guardrail). Append-only
scartato: CLAUDE.md è di solito riorganizzato semanticamente, append cieco
rompe la struttura. Merge manual è soluzione esplicita per il caso
ambiguo (l'utente legge il diff, decide a mano, poi ri-invoca la skill).

### 2.7 — Sub-agent dispatch enforcement (Q7)

**Decisione:** **anchor structural test nel harness review-triage-fix**
(+2 anchor su esistenza `~/.claude/skills/concept-to-code/SKILL.md` e
reference a `manifest_schema_version` nella SKILL.md). Skill template
strict: il body della SKILL.md contiene il prompt template letterale
(triple-backtick block) che l'orchestrator DEVE copiare nel dispatch
all'architect/coder. Niente "describe what you want", solo "execute exactly
this prompt".

**Razionale:** garantire che l'orchestrator segua effettivamente la skill
e non improvvisi è un problema impossibile in assoluto (l'orchestrator è
un LLM, può sempre divergere). Mitigation a strati:
1. SKILL.md con prompt template letterale (riduce variability nel dispatch).
2. Self-test harness della skill che valida il manifest schema (rileva
   manifest corrotti dovuti a improvvisazione).
3. Anchor structural test nel harness review-triage-fix (rileva
   rimozione/rottura della skill).
4. HITL gates al runtime (l'utente può catchare la divergenza al Gate 1/2/3).

Non c'è bullet-proof guarantee; c'è defense-in-depth.

### 2.8 — Failure mode (Q8)

**Decisione:** **state machine "abort, no auto-retry"**. Se architect
dispatch fallisce a metà (API overload, tool error, agent timeout), la
skill marca `manifest.current_step.status = failed` con `failure_reason`
field, scrive l'ultimo output disponibile (parziale ADR/plan/spec se
esiste) in path `*.partial`, e si ferma. L'utente decide manualmente:
re-invocare la skill con stesso topic (riparte dal Step ultimo green) o
abbandonare (delete manuale del manifest). Niente auto-retry, niente
skip-to-next.

**Razionale:** auto-retry rischia di amplificare il problema (rate limit
loop). Skip-to-next rompe la dependency chain (Step 3 senza Step 2 verde
genera CLAUDE.md su architettura inconsistente). Manual resume preserva
controllo utente. Il `failure_reason` field è hint diagnostico (es.
`"architect_timeout_60s"`, `"api_overload_529"`, `"file_write_permission_denied"`).
Coerente con global CLAUDE.md "Se non puoi verificare un risultato,
segnalalo — non assumere che funzioni".

### 2.9 — Coexistenza con dispatch manuali (Q9)

**Decisione:** **lo skill diventa "default" ma NON "obbligatorio"**.
Dispatch manuali di `architect` e `coder` restano possibili e validi.
La skill `concept-to-code` non modifica `architect.md` né `coder.md`.
Il README del repo blueprint (sez. dedicata in `docs/vibe-coding-system.md`
o GUIDA-CREARE-PROGETTO.md — futuro, non in scope di questo plan) menziona
la skill come entry point preferito.

**Razionale:** rigida obbligatorietà violerebbe il principio "power-user
override always available". Esempi legittimi di bypass: fix critico
hotline (no time per chain completo), iterazione su ADR esistente (no
nuova interview), feature micro-scope (skip Step 3 CLAUDE.md). La skill
ha vinto se l'utente la sceglie per natural fit, non se è forzata.

### 2.10 — Output finale (Q10)

**Decisione:** triple output. (a) **Report markdown** stampato in chat al
termine dello Step 6 con: file generati, durata totale, HITL gates
passati, harness deltas, link al manifest. (b) **Manifest update** a
`status: completed` + `completed_at` timestamp. (c) **Memory entry**
auto-suggerita ma NON auto-scritta: la skill compone il testo di una
voce per `MEMORY.md` (linea `## Project`) e la mostra all'utente in
Gate 5 con opzioni `append` / `skip`. Niente notification OS-level.

**Razionale:** report markdown è auditabile e copy-pasta-able. Manifest
update è già implicito nello state machine, ma esplicitarlo nel contract
evita stale manifest. Memory entry auto-suggerita risolve il pattern
osservato in MEMORY.md attuale (entry manuali scritte sempre nello stesso
formato dall'utente: "[topic](project_<slug>.md) — DEPLOYED YYYY-MM-DD
descr"); auto-write violerebbe il principio "no side-effect non
richiesti" (dal brief: side-effect su `agent-notes/architect.md` segnalato
come precedente errore).

### Sintesi 10 decisioni

| Q  | Decisione                                                                 |
| -- | ------------------------------------------------------------------------- |
| Q1 | Skill markdown `concept-to-code` + 3 bash helper + self-test              |
| Q2 | Manifest YAML in `docs/manifests/YYYY-MM-DD-<topic>.manifest.yml`         |
| Q3 | Resume esplicito: `/skill concept-to-code resume <manifest-path>`         |
| Q4 | 3 HITL bloccanti + 1 checkpoint + 1 review opzionale                      |
| Q5 | Riusa `interview-driver` esistente, NON `brainstorming`, NON nuova skill  |
| Q6 | CLAUDE.md diff-aware, default `skip` se esiste                            |
| Q7 | Defense-in-depth: prompt template letterale + self-test + anchor + HITL   |
| Q8 | Abort no-retry, `failure_reason` field, resume manuale utente             |
| Q9 | Default ma non obbligatorio; dispatch manuali restano validi              |
| Q10 | Report MD + manifest `completed` + memory entry auto-suggerita HITL      |

---

## 3. Alternatives considered

Per ognuna delle 10 domande, almeno una alternativa scartata con motivo del
rifiuto. Tabelle sintetiche per leggibilità.

### Q1 — Forma del componente

- **Slash command dedicato `/concept-to-code`** — *rifiutato*: layer duplicato
  sopra lo skill. I slash command custom richiedono setup `.claude/commands/` di
  progetto (per-repo) o framework override. La skill markdown è invocabile sia
  via natural language ("fammi il chain concept→code per X") sia via prefix
  ufficiale (`/skill concept-to-code`), copre entrambi i casi senza file extra.
- **Agent dedicato `orchestrator-chain`** — *rifiutato*: violerebbe blueprint
  sez. 2 ("sub-agent non spawnano sub-agent"). L'orchestrator è il main agent
  della sessione CLI, non è un sub-agent. Un nuovo agent `orchestrator-chain`
  sarebbe un sub-agent che chiama altri sub-agent — non supportato.
- **Combinazione skill + agent dedicato** — *rifiutato*: complessità
  superflua. La skill da sola è sufficiente; aggiungere un agent introduce
  duplicate intent (sia lo skill sia l'agent definirebbero lo stesso state
  machine).

### Q2 — State persistence

- **File JSON in `.claude/state/concept-to-code-<topic>.json`** — *rifiutato*:
  JSON è meno human-readable. L'utente *deve* poter leggere/editare il
  manifest in caso di stallo (es. correggere un path stale). YAML vince per
  leggibilità.
- **Inline nel prompt (state machine pure functional)** — *rifiutato*:
  fallisce allo Step 4 fresh session boundary. Il context window della nuova
  sessione non contiene lo state precedente.
- **Niente persistence (re-derivabile dai file)** — *rifiutato*: re-derivare
  state da SPEC.md/ADR esistenti è euristico (timestamp file? ultima modifica?)
  e fragile. Manifest esplicito è deterministico.

### Q3 — Resume semantics

- **Auto-detection del manifest in flight** — *rifiutato*: rischio di pickup
  del manifest sbagliato in presenza di multipli progetti aperti. L'utente
  potrebbe avere 3 manifest pending in 3 progetti; auto-pickup del "più
  recente" è euristico, non deterministico.
- **Override safe-to-restart (force resume even if completed)** — *rifiutato*:
  silenziosa overwrite di stato già consolidato. Se completed, la skill
  fallisce e suggerisce all'utente di creare un NUOVO manifest (no `resume
  --force`).

### Q4 — HITL gate count + tipo

- **Tutti gate informativi (mostra e procedi)** — *rifiutato*: viola la
  preferenza utente esplicita per HITL gates espliciti (memory
  `feedback_hitl-and-security-discipline.md` + global CLAUDE.md sez. HITL).
- **Tutti gate bloccanti incluso Step 4 e Step 5** — *rifiutato*: Step 4 NON
  può essere gate sincrono (skill non può forzare apertura nuova sessione).
  Step 5 dispatch coder è esso stesso un sub-process autonomo; aggiungere
  HITL prima del dispatch è ridondante (Gate 2 già copre).
- **Solo 1 HITL finale (mega-gate)** — *rifiutato*: 1 gate finale = utente
  approva o respinge tutto il chain in blocco. Edit granulari diventano
  impossibili (es. "spec ok ma ADR è da rivedere" richiede 2 gate
  indipendenti).

### Q5 — Interview skill choice

- **`superpowers:brainstorming` ufficiale** — *rifiutato*: dipendenza esterna
  (package superpowers), evoluzione non controllata, output non strict-SPEC.
  La skill custom `interview-driver` è già autoritativa per l'utente.
- **Nuovo `interview-driver-v2`** — *rifiutato*: 2 skill custom interview in
  parallelo creano drift di manutenzione. Refining `interview-driver`
  esistente, se serve, è preferibile.
- **Mix (brainstorming per draft, interview-driver per refinement)** —
  *rifiutato*: 2 invocazioni per Step 1 raddoppiano la durata e introducono
  variability tra draft e refinement.

### Q6 — CLAUDE.md handling

- **Always overwrite** — *rifiutato*: distruggerebbe CLAUDE.md curati
  manualmente (es. quello del repo `vibe-coding-system` con riferimenti
  alla spec). Viola global CLAUDE.md guardrail.
- **Solo se non esiste (skip silenzioso)** — *rifiutato*: utente non
  apprende che ci sarebbe stato un update potenziale. Diff-aware con HITL
  è più trasparente.
- **Append-only** — *rifiutato*: CLAUDE.md ha struttura semantica; append
  cieco la rompe (sez. duplicate, ordering caotico).

### Q7 — Sub-agent dispatch enforcement

- **Strict template + hook validator** — *rifiutato*: hook che ispezionano
  il prompt dell'orchestrator pre-dispatch non sono il pattern usato oggi
  (hook in `~/.claude/hooks/` sono per test-cmd e stop-gate, non per
  prompt inspection). Aggiungere un hook nuovo per questo è scope creep.
- **Solo skill template strict (senza anchor harness)** — *rifiutato*: la
  skill può essere accidentalmente modificata o cancellata; senza anchor
  in `review-triage-fix/tests/run-tests.sh` la regressione passa silente.
- **Solo HITL gates (no defense-in-depth)** — *rifiutato*: HITL fatigue è
  rischio reale (vedi memory). Più strati = meno dipendenza dal singolo
  gate.

### Q8 — Failure mode

- **Auto-retry con backoff** — *rifiutato*: rate limit / API overload
  loop diventa pernicioso. L'utente preferisce abort esplicito (decide
  retry manualmente).
- **Skip-to-next con flag `--continue`** — *rifiutato*: Step N+1 dipende
  da Step N (CLAUDE.md generato richiede ARCH.md valido). Skip rompe
  dependency invariant.
- **Rollback automatico al checkpoint precedente** — *rifiutato*: file
  generati intermediamente (SPEC.md parziale) sono recuperabili
  manualmente; auto-delete è destructive senza beneficio chiaro.

### Q9 — Coexistenza dispatch manuali

- **Forced via hook (disable manual dispatch)** — *rifiutato*: power-user
  override è esplicitamente preservato (global CLAUDE.md "Proattività"
  implica utente esperto sceglie il flow). Hook che blocca dispatch
  manuali sarebbe ostile.
- **Soft warning su dispatch manuale ("considera concept-to-code")** —
  *rifiutato*: noise nel pattern dispatch ricorrente. Memory utente
  ricorda della skill, non serve nudge inline.

### Q10 — Output finale

- **Solo report markdown (no manifest update)** — *rifiutato*: manifest
  stale resta in flight, falsa la auto-detection futura (se mai
  implementata). State machine consistency richiede status terminale
  esplicito.
- **Auto-write a MEMORY.md** — *rifiutato*: side-effect non richiesto. Il
  brief stesso cita il caso `agent-notes/architect.md` come precedente
  side-effect indesiderato. Auto-suggest + HITL append è la giusta linea.
- **Notification OS-level (Hammerspoon/AppleScript)** — *rifiutato*:
  scope creep, dipendenza piattaforma, fuori dal contract di una skill
  markdown.

---

## 4. Consequences

### Positive

- **Drift azzerato cross-feature:** prompt template versionato dentro la
  skill, ogni dispatch architect/coder è identico per costruzione. ADR-0004
  + ADR-0005 + ADR-NNN useranno lo stesso flow byte-faithful.
- **State machine deterministica:** manifest YAML è ispezionabile, debug-able,
  versionabile. Stallo a metà chain = manifest legibile dall'utente che
  decide come procedere.
- **HITL gates espliciti:** l'utente sa a priori che ci sono 3 gate
  bloccanti. Niente sorprese tipo "credevo fosse atomico ma mi chiede 4
  conferme".
- **Fresh session boundary risolto cleanly:** Step 4 + manifest YAML + Step
  5 resume = transizione cross-session senza loss of state, senza
  re-prompting dell'utente.
- **Coexistenza ortogonale con ADR-0001/ADR-0002/v1.2:** Pre-flight Pattern
  Classifier (coder), Pattern-drift check (reviewer), Snapshot Harness
  (refactorer) restano attivi e invocati naturalmente nel Step 5 (impl) e
  Step 6 (review). Triple-angle coverage del drift "code change vs intent"
  + new chain orchestration = quadruple-angle.
- **Skill custom esistenti riusate:** `interview-driver`, `adr-writer`,
  `claude-md-generator` finalmente orchestrate in chain unitario.
- **Sub-agent constraint rispettato:** la skill istruisce l'orchestrator
  (main agent), no sub-agent spawning. Blueprint sez. 2 invariata.
- **Auditabilità completa:** manifest + report finale + memory entry
  auto-suggerita = 3 livelli di trace.

### Negative

- **Surface di manutenzione aumentata:** 1 skill nuova + 3 helper bash + 1
  self-test harness. Stima ~250 righe markdown + ~250 righe bash. Future
  changes a `interview-driver`/`adr-writer`/`claude-md-generator` API
  richiedono allineamento della skill.
- **HITL fatigue rischio:** 3 gate sincroni nel base flow. Se l'utente
  fa 5 cycle concept-to-code in una settimana, sono 15 conferme. Mitigation
  futura: auto-mode flag per skip Gate 1 e Gate 3 (NON Gate 2). Non in
  scope di questo ADR.
- **Manifest stale come failure mode silente:** se l'utente abbandona un
  chain a metà senza marcare il manifest, il file resta in flight. Niente
  auto-cleanup. Mitigation: la `MEMORY.md` aggiornata e il fatto che
  manifest sia ispezionabile riducono il rischio di confusione.
- **Curva di apprendimento iniziale:** la skill ha 6 step, 3 gate, 1
  resume command. Più complessa di un dispatch architect manuale (1 step,
  0 gate). Mitigation: doc dedicata + report finale che spiega cosa è
  successo.
- **Dipendenza implicita su `interview-driver`:** se l'utente decommissiona
  `interview-driver`, la skill `concept-to-code` rompe. Hard-coded path
  nel SKILL.md body. Mitigation: anchor harness su esistenza
  `~/.claude/skills/interview-driver/SKILL.md` (out of scope per questo
  plan, candidate per future plan).

### Neutral

- **No edit a `architect.md` né `coder.md`:** decisione §2.9. La skill
  passa il content del manifest nel prompt del dispatch, no flag esterno.
  Coerente con "no backwards-compat shim" perché non c'è feature
  preesistente da shimmare.
- **No hook modifica:** la skill è puro markdown + bash userland. Niente
  `settings.json` / `.mcp.json` / hook touch.
- **No skill superpowers dipendenza:** la skill `concept-to-code` non
  importa `superpowers:brainstorming` né altre skill superpowers.
  Autonomia da package esterni.
- **Manifest schema versioning:** field `manifest_schema_version: "1.0"`
  obbligatorio. Future schema changes via bump del version. Nessuna
  migration tool in v1.0 (refactoring manuale dei manifest esistenti se
  cambia lo schema).
- **Path absoluto vs relativo nel manifest:** scelta path assoluti
  (`/Users/stefanoferri/...`) per coerenza con pattern memory MEMORY.md
  esistente. Vincolo: manifest non portabile fra machine. Accettato:
  il manifest è state locale, non shared artifact.

---

## 5. References

- Blueprint: `docs/vibe-coding-system.md` sez. 11 (workflow concept→code)
- Spec design: `docs/superpowers/specs/2026-05-20-concept-to-code-chain-design.md`
- Implementation plan: `docs/superpowers/plans/2026-05-20-concept-to-code-chain.md`
- Skill orchestrata (interview): `~/.claude/skills/interview-driver/SKILL.md`
- Skill orchestrata (ADR): `~/.claude/skills/adr-writer/SKILL.md`
- Skill orchestrata (CLAUDE.md): `~/.claude/skills/claude-md-generator/SKILL.md`
- Sub-agent dispatched in chain: `~/.claude/agents/architect.md`, `~/.claude/agents/coder.md`
- Feature deployate 2026-05-20 (coexistenza):
  - ADR-0001 `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md`
  - ADR-0002 `docs/architecture/ADR-0002-refactor-snapshot-harness.md`
  - review-triage-fix v1.2 `~/.claude/skills/review-triage-fix/SKILL.md`
- Anchor harness baseline: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` PASS=45 (2026-05-20)
- Memory: `feedback_bash32-constraint.md`, `feedback_hitl-and-security-discipline.md`,
  `feedback_micropiano-refactor-cleanup.md`
