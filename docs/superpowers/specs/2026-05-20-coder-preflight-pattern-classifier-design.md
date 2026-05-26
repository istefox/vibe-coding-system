# Design — Coder pre-flight pattern classifier

**Data:** 2026-05-20
**Stato:** implementato — 2026-05-20 (harness PASS=43; dispatch organico del coder validerà la fedeltà LLM al contract, vedi Open questions ADR §4.4)
**Autore:** Adriano per Stefano Ferri
**Topic:** introdurre nel `coder` agent un contract di output `PATTERN: ...` da emettere
prima di ogni tool call Edit/Write, con 4 categorie esaustive (ADD, REMOVE, REPLACE,
MODIFY), enforcement via system prompt + reviewer post-hoc + v1.2 safety net.

**ADR di riferimento:** `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md`
(autoritativa per il "perché"; questo spec si concentra sui contract e sui delta puntuali
dei file).

---

## 1. Contesto (sintetico — dettaglio nell'ADR)

Lo skill `review-triage-fix` v1.2 ha introdotto la regola Add+Remove come paragrafo prose
in Step 2, post-mortem alla discovery del MAJOR M-1 (cycle 2 `pricing-markup-cli`,
duplicazione autouse fixture). La regola funziona ma è reattiva e single-pattern. Il
classifier sposta il presidio a pre-flight, scalabile a future invarianti.

## 2. Goal / Non-goal

**Goal:** definire e deployare un contract di classificazione pre-edit per il `coder` agent
con 4 categorie, format strict per ciascuna, validation a layer-stack
(system-prompt → reviewer → v1.2).

**Non-goal:**
- Automazione hook-based dell'enforcement (vedi ADR §3.1.c).
- File JSON di state per il classifier (vedi ADR §3.1.b).
- Modifiche al `coder.md` `tools:` o `model:` — restano `Read,Edit,Write,Glob,Grep,Bash` e
  `sonnet`.
- Modifiche alle skill esistenti (`review-triage-fix`, `adr-writer`, `code-review-checklist`)
  oltre l'1 anchor test additivo nel harness.
- Modifiche agli altri agenti (`debugger`, `refactorer`, `tester`, `doc-writer`, `researcher`,
  `architect`) — solo `coder.md` (primary) e `reviewer.md` (secondary).
- Validazione end-to-end empirica della fedeltà LLM al contract — pending pilota operativo
  (open question dell'ADR §4.4).

## 3. Architettura — system-prompt patch + reviewer invariant + anchor

### 3.1 Layer 1 — `~/.claude/agents/coder.md` (primary enforcement)

Inserire una nuova sezione **"Pre-flight Pattern Classifier"** dopo "Core Responsibilities"
(riga ~24 attuale) e prima di "Process" (riga ~25).

Sezione struttura:

```markdown
## Pre-flight Pattern Classifier

Before every `Edit` or `Write` tool call you MUST emit a single-line `PATTERN:` header
declaring the structural intent of the edit. Format:

    PATTERN: <CATEGORY> | <category-specific payload>

Four exhaustive, mutually-exclusive categories:

| Pattern | Meaning | Required payload |
|---|---|---|
| `ADD` | Brand-new code, no prior pattern to remove (new test, new function, new file, missing validation, edge-case test). | `<path:line> <one-line-intent>` |
| `REMOVE` | Pure deletion (dead code, unused file). | `<path> | Callers checked: <list or "none">` |
| `REPLACE` | Substitution of an existing pattern with a new one (move local import to top-level, extract magic number, consolidate duplicate fixtures, rename helper). | `Add: <path:line> <new>` `|` `Remove: <path:line> <old>` — BOTH required |
| `MODIFY` | In-place edit without structural change (typo fix, rename var, internal refactor of one function that remains logically the same). | `<path:line> <one-line-intent>` |

Examples:

    PATTERN: ADD | tests/test_pricing.py:42 add failing test for negative markup
    PATTERN: REPLACE | Add: tests/conftest.py:15 new _isolate_user_config autouse | Remove: tests/test_cli.py:8 old no_user_config autouse
    PATTERN: MODIFY | src/pricing/markup.py:88 rename `mrg` to `margin` for clarity
    PATTERN: REMOVE | src/legacy_util.py (full file) | Callers checked: grep returned 0 hits

Discipline:
- One header per tool call. If a step needs multiple Edits, emit multiple headers (one
  before each).
- `Read`, `Grep`, `Glob`, `Bash` tool calls are NOT classified (read-only / execution-only).
- For `REPLACE` the `Add:` AND `Remove:` pair is MANDATORY — listing only the new pattern
  is the duplication-by-omission failure mode that the v1.2 `review-triage-fix` rule was
  patched to catch post-hoc. The classifier prevents it pre-flight.
- If you realize mid-step that your classification was wrong, emit an updated `PATTERN:`
  header before the next tool call — re-classification is free.
- Files matching `*.md` / docs follow the same schema (typically `MODIFY` for sync edits,
  `ADD` for new sections).
```

Posizionamento: subito dopo "Core Responsibilities" (5 numbered points), perché logicamente
è una rifinitura del contract di output del coder (non un Process step — il Process descrive
*come* leggere/implementare/verify, il classifier descrive *cosa dichiarare* a ogni
mutation tool call).

### 3.2 Layer 2 — `~/.claude/agents/reviewer.md` (secondary)

Aggiungere bullet alla sezione "Core Responsibilities" del reviewer (file da leggere
durante l'implementazione per posizionamento esatto):

```markdown
- **Pattern-drift check.** If the diff under review was authored by the `coder` agent and the
  transcript contains `PATTERN:` headers, verify each declared category matches the
  corresponding hunk. Flag mismatches as MINOR `pattern-drift` finding (e.g. declared `ADD`
  but diff contains non-trivial deletions = should have been `REPLACE` or `MODIFY`). Not
  blocking; informational handoff to the next triage cycle.
```

### 3.3 Layer 3 — `~/.claude/skills/review-triage-fix/SKILL.md` v1.2 (invariata)

**Nessuna modifica.** La regola Add+Remove di Step 2 resta come safety net post-hoc. Il
classifier la rende pre-flight ma non la sostituisce (coesistenza esplicita, vincolo HARD
del task).

### 3.4 Harness anchor — `~/.claude/skills/review-triage-fix/tests/run-tests.sh`

Aggiungere 1 structural assertion al blocco `# --- Task 5: SKILL.md structural completeness ---`
(o un nuovo blocco `# --- Task 6: coder.md classifier section ---` per chiarezza). Il harness
oggi legge solo `SKILL.md`; introduciamo una variante minimale che legge un secondo file.

Strategia 3.2-clean (NO assoc array, NO mapfile):

```bash
# --- Task 6: coder.md classifier section ---
C="$HOME/.claude/agents/coder.md"
[ -f "$C" ] || bad "coder.md: file exists"
grep -q -- 'Pre-flight Pattern Classifier' "$C" 2>/dev/null \
  && ok "coder.md: classifier section present" \
  || bad "coder.md: classifier section missing"
grep -q -- 'PATTERN: <CATEGORY>' "$C" 2>/dev/null \
  && ok "coder.md: PATTERN format spec present" \
  || bad "coder.md: PATTERN format spec missing"
```

Cumulative harness: PASS=41 (v1.2) → PASS=43 (+2 anchors per classifier section + format
spec).

**Nota architetturale:** preferisco 2 anchor (1 per section heading + 1 per format spec
`PATTERN: <CATEGORY>`) anziché solo 1, perché protegge sia la presenza della sezione che la
specificità del contract output. Anchor preservation cost negligibile.

## 4. Format dei `PATTERN:` headers (contract preciso)

Grammar BNF-style:

```
header        := "PATTERN: " category " | " payload
category      := "ADD" | "REMOVE" | "REPLACE" | "MODIFY"
payload       := add-payload | remove-payload | replace-payload | modify-payload
add-payload   := path-line " " intent
remove-payload := path " | Callers checked: " caller-list
replace-payload := "Add: " path-line " " new-intent " | Remove: " path-line " " old-intent
modify-payload := path-line " " intent
path-line     := <path> ":" <line> | <path> " (new file)" | <path> " (full file)"
caller-list   := "none" | <comma-separated path:line list>
intent        := <one-line free text>
```

**Tolleranze:**
- `<path:line>` può essere `<path>:<lineno>` quando esatto, `<path>:<approx>` quando il line
  number cambierà durante la scrittura, o `<path>` solo se l'edit copre il file intero.
- `Remove:` accetta lista comma-separated per consolidamento multi-file.
- L'intent è free-text una riga; il reviewer non ne fa parsing semantico (solo verifica
  presenza).

**Non-tolleranze:**
- `PATTERN:` (con due punti e spazio) è il literal di start — il reviewer pattern-drift
  check cerca questo come anchor.
- `<CATEGORY>` deve essere uno dei 4 letterali maiuscoli — altri valori = drift MINOR.
- Per `REPLACE`, l'assenza di `Remove:` (anche solo come keyword) = drift MAJOR (riproduce
  il fail mode v1.2 originario).

## 5. File modificati / nuovi

### Modificati

- **`~/.claude/agents/coder.md`** — inserita sezione "Pre-flight Pattern Classifier" dopo
  "Core Responsibilities". ~35 righe markdown additivo. Nessuna prose esistente rimossa.
- **`~/.claude/agents/reviewer.md`** — aggiunto bullet "Pattern-drift check" alla sezione
  "Core Responsibilities". ~6 righe markdown additive.
- **`~/.claude/skills/review-triage-fix/tests/run-tests.sh`** — aggiunto blocco `# --- Task
  6: coder.md classifier section ---` con 2 anchor (presence + format). Cumulative
  PASS=41 → PASS=43.
- **`docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md`** (questo deliverable)
  — ADR finale.
- **`docs/superpowers/specs/2026-05-20-coder-preflight-pattern-classifier-design.md`** (questo
  file) — design spec.
- **`docs/superpowers/plans/2026-05-20-coder-preflight-pattern-classifier.md`** — plan TDD
  da implementare.

### Memory update

- **`~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/`**
  — aggiungere file `project_coder-preflight-classifier.md` con stato, link a ADR/spec/plan,
  invariante "classifier-pre-edit + v1.2 safety net coesistono"; aggiornare `MEMORY.md`
  index con riga nuova in sezione "Project".

### Nessun cambio

- Helper scripts `verify.sh`, `weakening-scan.sh`, `triage-state.sh` — invariati.
- Tutti gli altri agenti (`architect`, `debugger`, `refactorer`, `tester`, `doc-writer`,
  `researcher`) — non toccati.
- Skill `review-triage-fix/SKILL.md` — invariata (v1.2 Add+Remove rule resta come safety net).
- Hook in `settings.json`, MCP in `.mcp.json`, rules in `.claude/rules/` — invariati.
- `docs/vibe-coding-system.md` — invariato in questo cycle (un futuro update lo allineerà
  alla v2.2 con la sezione classifier, ma è scope separato).

## 6. Deploy strategy

Modifiche additive su system prompts agent (file in `~/.claude/agents/`) + 1 blocco bash 3.2
nel harness. Nessun HITL gate complesso:

- Le modifiche a `coder.md` e `reviewer.md` sono additive (no overwrite di prose esistente).
- L'harness sale di 2 PASS (no regressione).
- Nessun hook live, settings.json, MCP toccato.
- La skill `review-triage-fix` non viene modificata → harness baseline resta 41 anche
  *prima* dell'aggiunta dei 2 nuovi anchor.

Edit diretti su file live, harness run finale come conferma. Backup pre-edit di
`coder.md` e `reviewer.md` raccomandato (cp `.bak` nello stesso path con date suffix —
allineato pratica `vibe-coding-system.md.bak-2026-05-19`).

## 7. Testing

### Deterministico (harness)

```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh
# expected: PASS=43 FAIL=0, exit 0
# (v1.2 baseline 41 + 2 new anchors for coder.md classifier)
```

I 2 anchor verificano:
1. Presenza section heading "Pre-flight Pattern Classifier" in `~/.claude/agents/coder.md`.
2. Presenza format spec `PATTERN: <CATEGORY>` nel body della section.

### Non-deterministico (pilota operativo)

L'efficacia operativa della disciplina classifier è LLM-mediated, validabile solo nell'uso
reale. Il primo dispatch organico del `coder` post-deploy fornirà evidenza empirica della
hit-rate dei `PATTERN:` headers. Metriche da osservare in pilota:

- **Hit-rate compliance:** % di tool calls Edit/Write preceduti da `PATTERN:` header.
  Target: >90% sui primi 20 tool calls del pilota.
- **REPLACE pair completeness:** % di `PATTERN: REPLACE` headers che includono entrambi
  `Add:` e `Remove:`. Target: 100%.
- **Reviewer pattern-drift detection:** numero di MINOR `pattern-drift` flagged dal
  reviewer nelle prime 3 review-triage-fix cycles. Target: catturare almeno 1 drift se
  l'LLM ne produce.

Non bloccanti per il deploy: validano la design hypothesis, non il deploy stesso.

### Bash 3.2 / BSD compat

Gli helper scripts esistenti (`verify.sh`, `weakening-scan.sh`, `triage-state.sh`) non sono
toccati. Il nuovo blocco harness usa `grep -q -- "..."` con string literal — identico stile
delle 18 `g()` assertion esistenti, 3.2-clean by construction.

## 8. Vincoli & invarianti

- **Anchor preservation:** i 41 anchor v1.2 restano intatti. Aggiunti 2 nuovi anchor (presence
  + format spec in `coder.md`). Cumulative PASS=43.
- **No backwards-compat shim:** il classifier sostituisce pulito; non c'è "vecchio
  contract" del coder da deprecare (il coder oggi non ha contract di output strutturato
  oltre il summary post-task). La regola v1.2 in SKILL.md NON è un "vecchio contract da
  rimuovere" — è una safety net complementare, esplicitamente preservata.
- **Coexistenza v1.2:** la regola Add+Remove in `SKILL.md` Step 2 resta. Coesiste con il
  classifier come tertiary layer (vedi ADR §2.3).
- **Sub-agent contract immutato:** `coder.md` resta Sonnet, `tools: Read, Edit, Write, Glob,
  Grep, Bash`, color verde, plan-driven, no spawn di altri sub-agent (sez. 2 del blueprint).
- **Lingua:** system prompt in inglese (contract); ADR/spec/plan in italiano; commit/code
  in inglese.
- **HITL gate:** nessun gate richiesto dal deploy stesso (additivo, no destructive). Validazione
  operativa è osservativa, non gate.
- **Bash 3.2.57:** harness scrupolosamente 3.2-clean per le ragioni memory
  `feedback_bash32-constraint.md`.

## 9. Out of scope

- Validazione end-to-end empirica della fedeltà LLM al contract (defer al primo dispatch
  organico del `coder` post-deploy).
- Estensione delle 4 categorie con sotto-pattern (es. `ADD-TEST`, `ADD-IMPL`) — speculative
  future-proofing, scartato in questo cycle.
- Hook PreToolUse di enforcement bash (scartato in ADR §3.1.c).
- Aggiornamento `docs/vibe-coding-system.md` con sezione classifier (defer a v2.2 del
  blueprint, scope separato).
- Modifiche a `debugger.md`, `refactorer.md` per estendere il classifier anche a loro (i 2
  agent sono fix-driven e operano su singola finding; aggiungere classifier introdurebbe
  overhead senza valore proporzionato in questo cycle — possibile estensione futura se i
  pilota evidenzia drift su finding ambigui).
- Auto-detection algoritmica "substitution vs additive" — resta giudizio LLM del coder
  (analogo a v1.2 dove resta giudizio LLM dell'orchestratore al triage).

## 10. Confidence

**Media-alta.**

**Alta sui delta puntuali e sui contract:**
- Modifiche additive a 2 system prompts agent (no overwrite, no shim) — 100% definite.
- 2 anchor structural test in harness — 100% definiti, 3.2-clean by construction.
- Coesistenza v1.2 ↔ classifier — invariante esplicito, no race condition possibili.

**Media sull'efficacia operativa:**
- Il contract `PATTERN: ...` è plausibile da seguire per Sonnet (analogo a micro-piano
  discipline che già funziona), ma non verificato per questa esatta forma.
- Reviewer pattern-drift check è nuovo: la capacità del reviewer agent di parsare il
  transcript del coder + correlare con diff è plausibile ma non verificata.
- Il pilota operativo è l'unica vera validation; il deploy è low-risk (additivo, harness
  verde), ma il *valore* della feature è validato solo nell'uso.

**Cose verificate (fatti):**
- Harness baseline PASS=41 (contestualmente confermato dal task brief — v1.2 deploy concluso
  2026-05-20).
- File path live `~/.claude/agents/coder.md` (51 righe attualmente, ispezionato).
- File path live `~/.claude/agents/reviewer.md` (esiste, da ispezionare per posizionamento
  esatto del nuovo bullet — sarà fatto in plan Task 2).
- Vincolo bash 3.2 (memory `feedback_bash32-constraint.md`).
- Regola v1.2 Add+Remove esistente in `SKILL.md` Step 2 (ispezionata).

**Cose assunte:**
- L'LLM Sonnet seguirà il contract con hit-rate >90% (analogia con micro-piano, non
  verificato).
- 2 anchor sono il giusto compromesso (1 troppo permissivo, 3+ over-engineering).
- Per-tool-call granularity non produce overhead testuale problematico.
- Reviewer riesce a parsare `PATTERN:` headers dal transcript (capacità LLM standard,
  non verificata empiricamente per questo caso).
