# ADR-0001 — Coder pre-flight pattern classifier

**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-coder-preflight-pattern-classifier.md; harness PASS=43)
**Authors:** Adriano (architect agent) per Stefano Ferri
**Supersedes:** none
**Superseded by:** none
**Related:**
- `docs/superpowers/specs/2026-05-20-coder-preflight-pattern-classifier-design.md`
- `docs/superpowers/plans/2026-05-20-coder-preflight-pattern-classifier.md`
- `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2 Add+Remove rule — rete di sicurezza complementare)
- `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/feedback_micropiano-refactor-cleanup.md` (RESOLVED 2026-05-20)

---

## 1. Context

Il sistema multi-agente vibe-coding (sez. 2-3 di `docs/vibe-coding-system.md`) ha un sub-agent
`coder` (Sonnet, `~/.claude/agents/coder.md`) plan-driven: esegue alla lettera quello che riceve.
La skill `review-triage-fix` v1.2 (2026-05-20) ha appena introdotto la regola **Add+Remove**
nello Step 2 del triage, dopo l'osservazione del cycle 2 di `pricing-markup-cli`: il `coder`
aveva ricevuto un micro-piano formulato come "aggiungi autouse fixture" senza esplicitare
"rimuovi la fixture preesistente che fa lo stesso lavoro", e aveva agito conservativamente
lasciando la duplicazione in place — MAJOR al re-review.

La regola v1.2 risolve **il caso specifico substitution** ma resta:

1. **Reattiva.** Agisce in triage del review *dopo* che il codice duplicato è già stato scritto.
   Il coder è già passato, il filesystem live ha 2 fixture autouse.
2. **Single-pattern.** Copre solo SUBSTITUTION. Nessuna leva equivalente per ADD (che potrebbe
   richiedere "ricorda di scrivere il test"), per REMOVE (che potrebbe richiedere "verifica
   caller orfani"), per MODIFY (che non richiede nulla di specifico ma è utile classificare
   per chiarezza dell'intent).
3. **Non scalabile.** Aggiungere altre invarianti analoghe in v1.3/v1.4 significa accumulare
   regole prosaiche su SKILL.md Step 2 senza taxonomy esplicita → entropia.

**Problema architetturale:** il `coder` agent non ha un contract esplicito che lo costringa a
**dichiarare l'intent dell'edit imminente** prima di eseguire il tool call. La disciplina
"micro-piano = 2-3 righe" copre il *cosa*; manca il *tipo strutturale dell'operazione*.

**Direzione:** introdurre un **pre-flight pattern classifier** che il `coder` deve emettere
prima di ogni Edit/Write tool call. 4 categorie esaustive e mutuamente esclusive: `ADD`,
`REMOVE`, `REPLACE`, `MODIFY`. Per `REPLACE` la dichiarazione del pair `Add:`/`Remove:` è
obbligatoria, promuovendo la regola v1.2 da rete di sicurezza post-hoc a contract pre-edit.

### Vincoli ereditati

- **Anchor preservation harness `review-triage-fix`:** il harness in
  `~/.claude/skills/review-triage-fix/tests/run-tests.sh` deve restare PASS=41/41 minimo
  (target post-feature: PASS=42/42 con 1 anchor aggiunto a `coder.md` structural sweep —
  vedi Decision §3.3).
- **Bash 3.2 compat** per ogni script live in `~/.claude/`.
- **No backwards-compat shim:** modifiche al `coder` agent sostituiscono pulito.
- **Coexistenza con v1.2:** la regola Add+Remove in `review-triage-fix` Step 2 resta — è la
  rete di sicurezza per quando il pattern classifier viene dichiarato male o assente
  (failure mode Q6).
- **Sub-agent identity invariata:** `coder.md` resta Sonnet, tools immutati
  (`Read, Edit, Write, Glob, Grep, Bash`), color verde, plan-driven.

### Assunzioni esplicite (non verificate empiricamente)

- L'LLM `coder` (Sonnet) seguirà un contract di output strutturato del tipo "before every Edit
  tool call, emit one line `PATTERN: <CATEGORY> | ...`" con la stessa fedeltà con cui segue
  oggi la disciplina del micro-piano. Plausibile (la disciplina v1.0-v1.2 dei micro-piani 2-3
  righe funziona), ma non verificato per questa esatta forma di output.
- La granularità "1 pattern per Step del plan" è il giusto compromesso (vedi Decision §3.3).
  Validabile solo con un pilota operativo.
- Il reviewer agent può imparare a fare il check di coerenza "pattern dichiarato vs diff
  effettivo" leggendo il transcript del coder + git diff (o snapshot pre/post in non-git).
  Plausibile data l'attuale capacità di scan del reviewer (cita `loc=path:line`), ma è una
  nuova invariante che richiede aggiunta al `reviewer.md` system prompt.

---

## 2. Decision

Introdurre il **Coder Pre-flight Pattern Classifier** come contract di output del `coder`
agent, enforced via system prompt (`~/.claude/agents/coder.md`), con validation post-hoc nel
`reviewer` agent e fallback v1.2 inalterato.

### 2.1 Le 4 categorie

| Pattern | Significato | Invariante richiesta |
|---|---|---|
| `ADD` | Codice nuovo, nessun pattern precedente da rimuovere (nuovo test, nuova funzione, nuovo file, validazione mancante, edge-case test). | Nessuna struttura aggiuntiva — `ADD: <path:line> <one-line-intent>`. |
| `REMOVE` | Cancellazione pura (codice morto, file inutilizzato). | Dichiarare `Callers checked: <list or "none">` per evitare orfani. |
| `REPLACE` | Sostituzione di pattern esistente con pattern nuovo (move import to top-level, extract magic number, consolidate duplicate fixtures, rename helper). | **`Add:` + `Remove:` pair obbligatori.** Forma: `REPLACE \| Add: <path:line> <new> \| Remove: <path:line> <old>`. |
| `MODIFY` | Edit in-place senza cambio di struttura (typo fix, rename var, refactor interno di un'unica funzione che resta logicamente la stessa, comment update). | `MODIFY: <path:line> <one-line-intent>`. |

Le 4 categorie sono esaustive e mutuamente esclusive per costruzione. Edge cases coperti in
Decision §2.5.

### 2.2 Forma dell'output (Q1)

**Self-disciplined output testuale del coder, una riga immediatamente PRIMA del tool call
Edit/Write.** Format strict:

```
PATTERN: <CATEGORY> | <category-specific payload>
```

Esempi concreti:

```
PATTERN: ADD | tests/test_pricing.py:42 add failing test for negative markup
PATTERN: REPLACE | Add: tests/conftest.py:15 new _isolate_user_config autouse | Remove: tests/test_cli.py:8 old no_user_config autouse
PATTERN: MODIFY | src/pricing/markup.py:88 rename `mrg` to `margin` for clarity
PATTERN: REMOVE | src/legacy_util.py (full file) | Callers checked: grep returned 0 hits across src/ and tests/
```

Una riga = un tool call. Se un Step del plan ha multipli Edit indipendenti, multipli
`PATTERN:` headers, uno per ciascun Edit, ciascuno seguito dal suo tool call. Niente JSON,
niente file di state — il classifier vive nel transcript dell'agent ed è ispezionabile
direttamente dall'orchestrator e dal reviewer.

### 2.3 Enforcement (Q2)

**Three-layer defense, ognuno facoltativo singolarmente, robusto collettivamente:**

1. **System prompt del `coder.md` agent (primaria, mandatory in v1.0):** la disciplina
   classifier è specificata come hard contract: "**before every Edit or Write tool call you
   MUST emit a single-line `PATTERN: ...` header**". Identico statuto della disciplina
   micro-piano v1.0-v1.2.
2. **Reviewer post-hoc coerenza check (secondary):** il `reviewer.md` guadagna 1 invariante:
   "se l'agent che ha generato la diff è `coder`, verifica che il transcript contenga
   `PATTERN:` headers coerenti con le hunk del diff; flag MINOR `pattern-drift` se il
   pattern dichiarato non corrisponde al diff effettivo (es. dichiarato `ADD` ma il diff
   contiene rimozioni non-triviali)". Non bloccante, è un MINOR informativo.
3. **review-triage-fix v1.2 Add+Remove rule (tertiary, esistente, immutata):** se il pattern
   classifier fallisce (dichiarato male o omesso) e il bug duplication-by-omission del cycle
   2 ritorna, la rete v1.2 lo cattura come prima. Coesistenza esplicitamente preservata.

**Hook PreToolUse bash come enforcement primario è esplicitamente scartato** (vedi
Alternatives §3.1.c).

### 2.4 Granularità (Q3 + Q5)

**Granularità = 1 dichiarazione `PATTERN:` per tool call Edit/Write.**

- Non per task del plan (troppo grossa, perde multi-pattern).
- Non per "blocco logico" (ambiguo, soggetto a interpretazione).
- Per ciascun tool call individuale (deterministico, ispezionabile).

**Interazione con plan TDD a 5-7 task:** ciascun Step `- [ ]` del plan è un blocco di esecuzione
che tipicamente contiene 1-3 Edit. Il pattern dominante è derivabile dallo Step (red phase →
solitamente `ADD`; green phase → `ADD` o `MODIFY`; sync deliverable → `MODIFY`), ma la
classificazione finale è **run-time, dal coder, per ciascun Edit**, perché:

- La realtà di implementazione può deviare dal plan (e in quel caso classification a freddo
  pre-plan mente).
- Pattern multipli legittimi in uno Step (es. green phase richiede ADD nuova funzione +
  MODIFY caller esistente) devono essere ciascuno classificato.

Il **plan scritto dall'architect NON deve pre-dichiarare i pattern per step**, perché
forzerebbe il coder a un'aderenza che potrebbe nascondere drift legittimi. L'architect resta
agnostico; il coder classifica.

### 2.5 Edge cases della classificazione (Q4 espanso + cover di edge cases)

- **REPLACE quando il file nuovo non esiste ancora** (es. `Add:` punta a `tests/conftest.py`
  appena creato): il coder usa il filename + 1-line description del pattern come
  identificatore — `Add: tests/conftest.py (new file) _isolate_user_config autouse fixture`.
- **REPLACE che tocca >1 location di Remove** (consolidate 3 fixtures duplicate in 1):
  `Remove:` è una lista comma-separated di `path:line` — `Remove: tests/test_a.py:8,
  tests/test_b.py:12, tests/test_c.py:5`.
- **MODIFY che diventa REPLACE in corsa** (es. rename var ma il coder realizza che
  contemporaneamente sta rimuovendo il vecchio nome in 5 altri file): emette un secondo
  `PATTERN:` aggiornato prima del tool call successivo. Non c'è penalty per la
  ri-classificazione: il transcript è la fonte di verità.
- **Edit a un file di doc/markdown** (sync deliverable in plan): si applica lo stesso schema.
  `MODIFY` di solito (sync ref number); `ADD` per nuove sezioni; `REPLACE` raro ma plausibile
  (es. cambio di policy in CLAUDE.md project).
- **Bash tool call NON è classificato.** Solo `Edit` e `Write` tool calls richiedono
  `PATTERN:` header. Il `Read`, `Grep`, `Glob`, `Bash` sono read-only o execution-only e
  escludono la classificazione (allineato con il fatto che la disciplina è sull'intent di
  *mutazione*).

### 2.6 Failure mode (Q6)

Cosa succede se il coder dichiara `ADD` ma il diff effettivo contiene rimozioni
non-triviali?

1. **Reviewer post-hoc invariante (§2.3 layer 2)** lo flagga come MINOR `pattern-drift`.
   Routato a `coder` come micro-piano standard "re-emit classification coerente; se
   classificazione corretta è REPLACE, applica regola Add+Remove (v1.2)".
2. **Se il drift causa duplication-by-omission** (es. dichiarato ADD ma era REPLACE e
   l'old pattern è rimasto): cattura v1.2 Add+Remove rule al ciclo successivo come MAJOR.

Non c'è auto-revert. Non c'è hook che blocca. La filosofia è triple-layer detection con
escalation umana (HITL) come gate finale (allineato `~/.claude/CLAUDE.md` invariante "HITL
gate sempre prima di commit, deploy, modifica schema").

### 2.7 Modifiche puntuali ai file

- **Modify `~/.claude/agents/coder.md`** — aggiungere sezione "Pre-flight Pattern Classifier"
  con la tabella delle 4 categorie e gli esempi di output, inserita dopo "Core
  Responsibilities" e prima di "Process". Modifica sostitutiva (no shim deprecated).
- **Modify `~/.claude/agents/reviewer.md`** — aggiungere bullet "pattern-drift check" alla
  sezione "Core Responsibilities" o "Process", con severity MINOR e categoria di finding
  `pattern-drift`.
- **Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh`** — aggiungere 1 anchor
  structural test che verifica la presenza del literal `Pattern Classifier` in
  `~/.claude/agents/coder.md`. Harness PASS=41 → PASS=42.

  Nota architetturale: il harness `review-triage-fix` è oggi single-target (legge solo
  `SKILL.md`). Estenderlo a leggere un secondo file (`coder.md`) è una **decisione
  architettonica minore ma esplicita**: la skill `review-triage-fix` ha autorità sulla
  qualità del proprio stack (incluso il `coder` che dispatcha). Alternative scartate in §3.3.
- **NO modify `~/.claude/skills/review-triage-fix/SKILL.md`** — la skill resta invariata.
  La regola Add+Remove v1.2 in Step 2 è coerente per costruzione con il classifier (il
  classifier la rende pre-flight, ma la post-hoc rule resta come safety net).

### 2.8 Lingua

System prompt del `coder.md` e `reviewer.md` in inglese (codice/contract). Spec, plan e
memory in italiano. Tabella categorie e esempi in inglese (sono interface contract). Allineato
con global rule "codice e commit in inglese; testo all'utente in italiano".

---

## 3. Alternatives considered

### 3.1 Dove vive la dichiarazione (Q1)

**a) Self-disciplined output testuale del coder (CHOSEN).** Zero infrastructure, leggibile nel
transcript orchestrator, allineato con disciplina micro-piano. Rischio: drift LLM
(classifier dichiarato male o omesso); mitigato da reviewer post-hoc layer + v1.2 safety net.

**b) File JSON di state `.claude/.pattern-classifier-current.json`** — *Rejected*. Richiede
I/O scaffolding (lock file? cleanup tra cycle? snapshot pre/post?), aggiunge complessità a un
problema che è fondamentalmente di disciplina dichiarativa. Non risolve il vero rischio
(drift LLM): l'LLM può scrivere male il JSON tanto quanto scrivere male la riga
`PATTERN: ...`. State file aggiunge un punto di failure (stale state, race con dispatch
paralleli) senza benefit proporzionato.

**c) Hook PreToolUse bash intercetta il tool call Edit/Write** — *Rejected*. Tre ragioni:
(i) gli hook PreToolUse di Claude Code ricevono `tool_input` JSON, non il testo del response
precedente — l'hook bash non può "vedere" il `PATTERN: ...` header senza side-channel state
file (re-introduce 3.1.b); (ii) violerebbe il vincolo bash 3.2 con scrittura/lettura JSON
robusta; (iii) un hook che blocca un Edit perché manca il pattern viola la filosofia
"l'enforcement primario è disciplina + reviewer post-hoc, non gate hard al filesystem"
(allineato al fatto che anche v1.2 è prose-discipline, non hook-enforcement).

### 3.2 Chi enforca (Q2)

**a) Self-discipline via system prompt (CHOSEN, primary layer).** Lo stesso meccanismo
funziona già per micro-piano discipline v1.0-v1.2. Il `coder` plan-driven segue contract
testuali con alta fedeltà se il contract è chiaro e con esempi.

**b) Hook PreToolUse bash blocca Edit se manca pattern** — *Rejected* (vedi §3.1.c).

**c) Solo reviewer post-hoc, senza system prompt** — *Rejected*. Sposta tutto il carico al
reviewer (che già fa molto), e perde la leva proattiva: il coder *prima* di scrivere il
codice trae beneficio cognitivo dal classificare l'intent (specialmente REPLACE → forzato a
pensare al pair). Reviewer post-hoc resta come secondary layer, non primary.

**Scelto layer-stack:** primary = system prompt; secondary = reviewer pattern-drift check;
tertiary = v1.2 Add+Remove rule come safety net duplicato-cattura.

### 3.3 Granularità (Q3 + Q5)

**a) Per tool call (CHOSEN).** Deterministico, ispezionabile, segue il "naturale ritmo" del
lavoro del coder. Pattern multipli per Step del plan = multipli headers, normale.

**b) Per task del plan** — *Rejected*. Troppo grossa: un task TDD red+green+sync
contiene 3-5 Edit con pattern potenzialmente diversi (es. red ADD, green ADD+MODIFY, sync
MODIFY). Un singolo pattern per task forzerebbe il "pattern dominante" e maschererebbe i
sotto-pattern, perdendo proprio il valore della classificazione.

**c) Per blocco logico (3-5 Edit correlati)** — *Rejected*. "Blocco logico" è ambiguo, non
testabile, non ispezionabile. Lascerebbe spazio di interpretazione che la classificazione
deve invece chiudere. Anti-pattern di design.

### 3.3 (sub-question) Harness extension cross-file (per anchor test su `coder.md`)

**a) Estendere harness `review-triage-fix` ad assertare anchor su `coder.md` (CHOSEN).** La
skill `review-triage-fix` ha già autorità sulla qualità del coder agent che dispatcha (`debugger`,
`refactorer`, `coder` ne sono i dispatch target). Il harness aggiunge 1 funzione helper
`g_file(file, str, label)` (generalizzazione della `g()` esistente) e 1 assertion finale.
Costo: ~5 righe bash. Beneficio: 1 anchor in più che protegge la "Pattern Classifier" section
del coder.md da rimozioni accidentali future. PASS=41 → PASS=42.

**b) Creare un harness separato dedicato al `coder.md`** — *Rejected*. Ridondante:
duplicherebbe la stessa logica `grep -q literal in file`. Aggiungerebbe un nuovo
deployment point in `~/.claude/agents/` o simile, contrario al principio "minimal moving
parts".

**c) Nessun structural anchor test** — *Rejected*. Senza anchor, una refactor accidentale del
coder.md (es. consolidare sezioni, riscrivere) potrebbe far perdere la disciplina classifier
silenziosamente, senza alert. Anchor è la rete di sicurezza standard del sistema (la stessa
filosofia di v1.0-v1.2 di review-triage-fix harness).

### 3.4 Cosa fa REPLACE (Q4)

**a) Pair `Add:` + `Remove:` esplicito obbligatorio (CHOSEN).** Promuove la regola v1.2 da
post-hoc a pre-flight. Format strict `REPLACE | Add: <loc> | Remove: <loc>`. Force il coder a
*pensare* alla rimozione mentre pensa all'aggiunta — la cognitive leverage è la chiave
dell'intervento.

**b) Flag promemoria "ricorda Add+Remove" senza format strict** — *Rejected*. Reintroduce il
fail mode v1.1 (il coder può "ricordare" senza esplicitare e poi non agire). La regola v1.2
ha appena risolto questo, sarebbe un regresso semantico.

**c) Checklist auto generata dal sistema** — *Rejected*. Richiede infrastructure (vedi
§3.1.b state file). Non scala (chi popola la checklist? in che linguaggio?).

### 3.5 Interazione TDD plan (Q5)

**a) Run-time per-tool-call (CHOSEN, già motivato in §2.4).** L'architect/plan non
pre-dichiara pattern; il coder classifica a runtime.

**b) Plan pre-dichiara il pattern di ciascuno Step** — *Rejected*. Forzerebbe aderenza a un
contract scritto a freddo dall'architect. La realtà di implementazione può legittimamente
deviare, e in quel caso il coder dovrebbe poter ri-classificare senza chiedere amendment al
plan.

### 3.6 Failure mode (Q6)

**a) Reviewer post-hoc invariante + v1.2 safety net (CHOSEN).** Triple-layer
(system-prompt → reviewer → v1.2). Nessun gate hard, escalation HITL come ultima.

**b) Hook che diff-controlla declared-vs-actual** — *Rejected* (vedi §3.1.c).

**c) Solo v1.2 safety net senza reviewer invariante** — *Rejected*. v1.2 cattura
duplication-by-omission per substitution, ma NON cattura altri pattern-drift (es. dichiarato
ADD ma diff è REMOVE non-triviale). Reviewer invariante è il caso generale.

---

## 4. Consequences

### 4.1 Positive

- **Cognitive leverage proattiva.** Il coder, costretto a classificare prima di scrivere,
  pensa meglio all'intent. Specialmente REPLACE → forza il pair Add+Remove al *punto
  giusto* (pre-edit), spostando v1.2 da rete di sicurezza a contract.
- **Scalabilità del modello.** Se in v1.3 vogliamo aggiungere "REMOVE deve dichiarare
  caller-check", "ADD deve dichiarare test paired", etc., aggiungiamo righe alla tabella
  delle 4 categorie senza riscrivere il framework.
- **Trasparenza per orchestrator + reviewer.** Il transcript del coder è auto-documentato:
  scrolling delle righe `PATTERN: ...` produce un audit log dell'intent.
- **Tre layer di difesa contro duplication-by-omission.** v1.2 alone cattura solo a
  re-review post-fix; classifier pre-flight cattura *prima* dell'edit; reviewer pattern-drift
  cattura mid-cycle.
- **Anchor preservato.** PASS=41 → PASS=42 (additivo, no regressione).
- **Zero nuove dipendenze.** Solo system prompt edits + 1 anchor test bash 3.2-clean.

### 4.2 Negative

- **Overhead testuale nel transcript del coder.** Ogni Edit/Write è preceduto da 1 riga
  `PATTERN: ...`. Per task con 10 Edit, +10 righe. Non bloccante (cheap tokens), ma
  rumoroso.
- **Rischio di drift dell'LLM.** Il coder potrebbe omettere il pattern header in stress
  conditions (context window pieno, prompt lungo). Mitigato da reviewer post-hoc, ma non
  eliminato.
- **Dipendenza dal reviewer agent per il check secondary.** Se review-triage-fix non viene
  invocata su un cycle, il pattern-drift check è bypassato. Mitigato da v1.2 safety net (che
  resta attiva nei prossimi review-triage-fix invocati).
- **Couplig minore tra `review-triage-fix/tests/run-tests.sh` e `~/.claude/agents/coder.md`.**
  Il harness ora legge 2 file. Se in futuro splittiamo o rinominiamo coder.md, anchor va
  aggiornato. Costo accettabile (1 path string da aggiornare).

### 4.3 Neutral

- Il plan TDD scritto dall'architect resta agnostico al classifier — nessun cambio
  workflow per architect agent.
- La memory `feedback_micropiano-refactor-cleanup.md` resta RESOLVED (v1.2 chiude la causa,
  il classifier è additivo).
- L'orchestrator non cambia: dispatcha `coder` come prima, riceve summary, ispeziona
  transcript come prima — solo che ora il transcript ha i `PATTERN:` headers.

### 4.4 Open questions (validation pending)

- **L'LLM segue il contract `PATTERN: ...` con la stessa fedeltà di micro-piano?**
  Validabile solo con pilota operativo (es. invocare il coder su un task realistico, contare
  hit-rate dei headers). Confidence iniziale: media — il contract è simile a micro-piano ma
  più strutturato.
- **Quanti drift il reviewer pattern-drift check cattura realmente?** Validabile con un
  pilota di 3-5 cicli review-triage-fix dopo il deploy.
- **Granularità "1 pattern per tool call" produce headers troppi in plan grossi?**
  Validabile con metriche dal pilota.

---

## 5. References

- `~/.claude/agents/coder.md` (target di modifica primaria)
- `~/.claude/agents/reviewer.md` (target di modifica secondaria)
- `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2, complement; non modificato)
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (target +1 anchor)
- `docs/vibe-coding-system.md` sez. 3.x (8 sub-agent) e sez. 11 (workflow concept→code)
- `docs/superpowers/specs/2026-05-19-review-triage-fix-design.md` (v1.0 → v1.2 history)
- `docs/superpowers/specs/2026-05-20-review-triage-fix-v1.2-addremove-design.md`
- `docs/superpowers/plans/2026-05-20-review-triage-fix-v1.2-addremove.md`
- Memory `feedback_micropiano-refactor-cleanup.md` (RESOLVED 2026-05-20)
- Memory `feedback_bash32-constraint.md` (vincolo per harness)
- Field test `docs/field-test-2026-05-18.md` (storia pilota)
