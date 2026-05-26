# Coder pre-flight pattern classifier — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Changelog:**
- v1.0 (2026-05-20): initial — TDD plan derivato da `ADR-0001-coder-preflight-pattern-classifier.md` e dallo spec `2026-05-20-coder-preflight-pattern-classifier-design.md`. 6 task: 1 red harness, 2 green system-prompt, 1 documental sync (ADR/spec status), 2 deliverable doc + memory.

**Goal:** introdurre nel `coder` agent (`~/.claude/agents/coder.md`) un contract di output `PATTERN:` da emettere prima di ogni tool call `Edit`/`Write`, con 4 categorie esaustive (`ADD`, `REMOVE`, `REPLACE`, `MODIFY`), enforcement layer-stack: primary system-prompt nel `coder.md` + secondary pattern-drift check nel `reviewer.md` + tertiary safety net v1.2 Add+Remove (invariata in `review-triage-fix/SKILL.md`). Sposta la disciplina substitution → pair Add+Remove da reattiva (post-fix triage) a preventiva (pre-edit contract), generalizzandola a 4 pattern.

**Architecture:** additive-only patch su 2 system prompts agent (`coder.md`, `reviewer.md`) + 2 nuovi structural anchors nel harness `review-triage-fix/tests/run-tests.sh` (un nuovo blocco `# --- Task 6: coder.md classifier section ---` che legge un secondo file via grep literal, bash 3.2-clean). Anchor-preserving: i 41 anchor v1.2 restano intatti; cumulative harness PASS=41 → PASS=43. Nessun hook, nessun MCP, nessun settings.json, nessun helper script, nessuna skill esistente modificata oltre l'harness. Nessuna sostituzione di prose esistente in `coder.md`/`reviewer.md` — solo append di sezioni nuove. Coexistenza esplicita con la regola v1.2 in `review-triage-fix/SKILL.md` Step 2 (non toccata).

**Tech Stack:** markdown (system prompts, plan, spec, memory), bash 3.2.57 (harness — nuovo blocco usa `grep -q -- "..."` con literal string, identico stile dei 41 anchor esistenti, 3.2-clean by construction; nessun assoc array, nessun `mapfile`, nessuna parameter expansion non-portabile).

**Spec:** `docs/superpowers/specs/2026-05-20-coder-preflight-pattern-classifier-design.md` (approvato 2026-05-20).
**ADR:** `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (Proposed 2026-05-20).

---

## Environment notes (read first)

- **No git in `~/.claude/` né in questo repo doc `vibe-coding-system`.** Checkpoint per task = harness verde + TodoWrite update + report. Nessun commit. Nessun HITL gate complesso: la patch è additive su system prompts agent + 2 anchor nel harness, non tocca hook live, settings.json, MCP, helper script. Tutto inert (no behavior change) finché il prossimo dispatch organico del `coder` legge il system prompt aggiornato.
- **Bash 3.2 cleanliness.** Il nuovo blocco harness Task 6 dichiara una variabile `C="$HOME/.claude/agents/coder.md"`, verifica esistenza con `[ -f "$C" ]`, e fa 2 assertion via 2 `grep -q -- "..." "$C"` con `ok`/`bad` (helpers già definiti in cima al harness, righe 8-9). Nessun assoc array, nessun `mapfile`, nessun `${v^^}`, nessun `<()` process substitution. Per ragioni memory `feedback_bash32-constraint.md`.
- **Anchor preservation.** Nessuno dei 41 anchor v1.2 viene rimosso o alterato. Il nuovo blocco Task 6 è appended DOPO la summary line `echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"` viene spostata SOTTO il nuovo blocco — in alternativa il blocco Task 6 va inserito PRIMA della summary line (scelta plan: insert prima della summary, identica strategia di v1.2 Task 1). Il blocco Task 5 chiude con `g 'Add+Remove rule' 'add+remove substitution rule'` (riga 144 attuale) seguito da riga vuota e dalla summary (riga 146). Il blocco Task 6 va inserito tra riga 144 e la summary.
- **Harness count baseline (verificato 2026-05-20 con `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`):** `PASS=41 FAIL=0`. Suddivisione: verify ×7 + weakening ×6 + state-diff ×4 + state-commit ×4 + SKILL.md ×20 (= 17 `g`-anchor v1.0 + 1 frontmatter-name + 1 description + 1 `Add+Remove rule` v1.2). Adding 2 new anchor (Task 6 `coder.md`) porta cumulative a `PASS=43 FAIL=0`.
- **Backup raccomandato pre-edit:** `cp ~/.claude/agents/coder.md ~/.claude/agents/coder.md.bak-2026-05-20` e analogo per `reviewer.md`. Patch è additiva (no overwrite di prose esistente), ma backup conserva la pratica del repo (cfr `vibe-coding-system.md.bak-2026-05-19`). Decisione operativa del coder: opzionale ma raccomandato.
- **Portability.** Edit operativi su `~/.claude/agents/coder.md`, `~/.claude/agents/reviewer.md`, `~/.claude/skills/review-triage-fix/tests/run-tests.sh`. Deliverable doc (questo plan, ADR, spec, memory update) nel repo `vibe-coding-system` + `~/.claude/projects/.../memory/`. Nessun MCP, hook, settings.json toccato.
- **Coexistenza v1.2 HARD.** La regola `Add+Remove rule (for SUBSTITUTION fixes)` in `~/.claude/skills/review-triage-fix/SKILL.md` Step 2 (riga ~67 deployed) NON viene rimossa né modificata in questo cycle. Resta come tertiary safety net post-hoc del layer-stack (vedi ADR §2.3, §3.6).

## File structure

Tutti i path live (`~/.claude/agents/` + `~/.claude/skills/review-triage-fix/tests/`); deliverable doc nel repo `vibe-coding-system`; memory in `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/`.

- Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — insert nuovo blocco `# --- Task 6: coder.md classifier section ---` (4 righe assertion + 2 `g`-equivalent inline) tra riga 144 (ultimo Task-5 anchor) e riga 146 (summary line). Il blocco verifica (i) presenza file `~/.claude/agents/coder.md`, (ii) presenza literal `Pre-flight Pattern Classifier` come heading section, (iii) presenza literal `PATTERN: <CATEGORY>` come format spec spec.
- Modify `~/.claude/agents/coder.md` — insert nuova sezione `## Pre-flight Pattern Classifier` (~35 righe markdown additive) DOPO la sezione `## Core Responsibilities` (5 numbered points, righe 17-23) e PRIMA della sezione `## Process` (riga 25). Nessuna prose esistente rimossa.
- Modify `~/.claude/agents/reviewer.md` — append bullet `- **Pattern-drift check.** ...` (~6 righe) alla sezione `## Core Responsibilities` (righe 18-22), come 5° bullet dopo i 4 esistenti. Nessuna prose esistente rimossa.
- Modify `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` — status line riga 3 da `**Status:** Proposed — 2026-05-20` a `**Status:** Accepted — 2026-05-20`.
- Modify `docs/superpowers/specs/2026-05-20-coder-preflight-pattern-classifier-design.md` — status line riga 3 da `**Stato:** approvato (post-ADR) — pronto per writing-plans` a `**Stato:** implementato — 2026-05-20`.
- Create `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_coder-preflight-classifier.md` — nuovo project memory entry con link a ADR/spec/plan, stato deploy, invariante "classifier-pre-edit + v1.2 safety net coesistono", harness PASS=43.
- Modify `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` — append riga nuova in sezione `## Project` con prefix `**DEPLOYED 2026-05-20**:`.

Unchanged (vincoli HARD): `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2 Add+Remove rule resta), `~/.claude/skills/review-triage-fix/scripts/*.sh` (verify, weakening-scan, triage-state — invariati), tutti gli altri agenti (`architect.md`, `debugger.md`, `refactorer.md`, `tester.md`, `doc-writer.md`, `researcher.md`), hook in `~/.claude/settings.json`, MCP in `.mcp.json`, rules in `.claude/rules/`, `docs/vibe-coding-system.md`.

---

### Task 1: Harness anchor failing (red)

**Files:**
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (insert nuovo blocco Task 6 prima della summary line)

**Red phase:** baseline harness `PASS=41 FAIL=0`. Il nuovo blocco Task 6 cerca `Pre-flight Pattern Classifier` e `PATTERN: <CATEGORY>` in `~/.claude/agents/coder.md` — entrambi assenti pre-Task-2/3. Aspettativa: 2 nuovi `FAIL`, cumulative `PASS=41 FAIL=2`, exit 1.

**Green phase (edit concreto):** localizza nel file l'ultima riga del blocco Task 5 (`g 'Add+Remove rule'          'add+remove substitution rule'`, attualmente riga 144) e la summary line (`echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"`, attualmente riga 146). Inserisci tra le due (in posizione riga 145 attuale, dopo blank line di separazione) il blocco:

```bash

# --- Task 6: coder.md classifier section ---
C="$HOME/.claude/agents/coder.md"
[ -f "$C" ] && ok "coder.md: file exists" || bad "coder.md: file exists"
grep -q -- 'Pre-flight Pattern Classifier' "$C" 2>/dev/null && ok "coder.md: classifier section present" || bad "coder.md: classifier section missing"
grep -q -- 'PATTERN: <CATEGORY>' "$C" 2>/dev/null && ok "coder.md: PATTERN format spec present" || bad "coder.md: PATTERN format spec missing"

```

Notes:
- 3 assertion totali per il blocco Task 6 (presenza file + 2 anchor structural). Il `[ -f "$C" ]` agisce come guard: se per qualunque ragione `coder.md` viene rinominato/spostato, il fail emerge subito con label esplicita anziché propagare 2 fail criptici di `grep`.
- Match string `Pre-flight Pattern Classifier` è il literal del section heading H2 in `coder.md` (Task 2 lo introduce). `PATTERN: <CATEGORY>` è il literal del format spec in body (Task 2 lo introduce nello stesso edit).
- 3.2-clean by construction: `grep -q -- "..."` + `&&`/`||` + `ok`/`bad` (helpers definiti righe 8-9) = identico stile delle 18 `g`-style assertion del blocco Task 5.
- Conta finale: 3 nuovi PASS attesi (file exists + 2 anchor) dopo Task 2/3 → cumulative `PASS=44`? **No.** Specifica ADR §2.7 + spec §3.4 dichiarano +2 anchor totali. Il `file exists` guard NON conta nei "2 anchor classifier section" della ADR — è metadata defense. Cumulative TARGET = `PASS=43 FAIL=0` (41 baseline + 2 anchor: `classifier section present` + `PATTERN format spec present`). Il `file exists` guard è additivo per safety ma fa salire PASS a 44. **Decisione plan:** rimuovi il guard `[ -f "$C" ]` per stick a `PASS=43` come da ADR/spec contract. Versione finale del blocco (3 righe assertion, no guard):

```bash

# --- Task 6: coder.md classifier section ---
C="$HOME/.claude/agents/coder.md"
grep -q -- 'Pre-flight Pattern Classifier' "$C" 2>/dev/null && ok "coder.md: classifier section present" || bad "coder.md: classifier section missing"
grep -q -- 'PATTERN: <CATEGORY>' "$C" 2>/dev/null && ok "coder.md: PATTERN format spec present" || bad "coder.md: PATTERN format spec missing"

```

`grep -q` su file inesistente ritorna non-zero senza errore visibile (stderr → `/dev/null`); il `bad "..."` cattura comunque. La label esplicita "missing" copre sia "file assente" sia "literal mancante in file presente".

- [ ] **Step 1: Write the failing test** — edit `~/.claude/skills/review-triage-fix/tests/run-tests.sh` per inserire il blocco Task 6 (3 righe, vedi sopra, no guard `[ -f ]`) tra riga 144 e riga 146.

- [ ] **Step 2: Run test to verify it fails**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: i 41 anchor v1.2 ancora `PASS`; le 2 nuove check `coder.md: classifier section present` + `coder.md: PATTERN format spec present` entrambe `FAIL` (anchor non ancora in `coder.md`); summary `PASS=41 FAIL=2`, exit 1.

- [ ] **Step 3: Checkpoint** — failing test in place, baseline rossa confermata (`PASS=41 FAIL=2`). TodoWrite update.

**Stima tempo:** 5 min.

---

### Task 2: coder.md "Pre-flight Pattern Classifier" section (green primary)

**Files:**
- Modify: `~/.claude/agents/coder.md` (insert nuova sezione `## Pre-flight Pattern Classifier` tra `## Core Responsibilities` e `## Process`)

**Red phase:** harness `PASS=41 FAIL=2` post-Task-1. Le 2 nuove check Task-6 falliscono perché `coder.md` non contiene ancora i literal `Pre-flight Pattern Classifier` né `PATTERN: <CATEGORY>`.

**Green phase (edit concreto):** localizza in `~/.claude/agents/coder.md` la fine della sezione `## Core Responsibilities` (riga 23, ultimo numbered point: `5. Draft a Conventional Commits message in English for the orchestrator — but never run the commit yourself.`) e l'inizio della sezione `## Process` (riga 25). Inserisci tra riga 23 e riga 25 (sostituendo la riga vuota 24 con: riga vuota + nuova sezione + riga vuota + riga vuota) il blocco markdown:

```markdown

## Pre-flight Pattern Classifier

Before every `Edit` or `Write` tool call you MUST emit a single-line `PATTERN:` header declaring the structural intent of the edit. Format:

    PATTERN: <CATEGORY> | <category-specific payload>

Four exhaustive, mutually-exclusive categories:

| Pattern | Meaning | Required payload |
|---|---|---|
| `ADD` | Brand-new code, no prior pattern to remove (new test, new function, new file, missing validation, edge-case test). | `<path:line> <one-line-intent>` |
| `REMOVE` | Pure deletion (dead code, unused file). | `<path> \| Callers checked: <list or "none">` |
| `REPLACE` | Substitution of an existing pattern with a new one (move local import to top-level, extract magic number, consolidate duplicate fixtures, rename helper). | `Add: <path:line> <new> \| Remove: <path:line> <old>` — BOTH required |
| `MODIFY` | In-place edit without structural change (typo fix, rename var, internal refactor of one function that remains logically the same). | `<path:line> <one-line-intent>` |

Examples:

    PATTERN: ADD | tests/test_pricing.py:42 add failing test for negative markup
    PATTERN: REPLACE | Add: tests/conftest.py:15 new _isolate_user_config autouse | Remove: tests/test_cli.py:8 old no_user_config autouse
    PATTERN: MODIFY | src/pricing/markup.py:88 rename `mrg` to `margin` for clarity
    PATTERN: REMOVE | src/legacy_util.py (full file) | Callers checked: grep returned 0 hits

Discipline:
- One header per tool call. If a step needs multiple Edits, emit multiple headers (one before each).
- `Read`, `Grep`, `Glob`, `Bash` tool calls are NOT classified (read-only / execution-only).
- For `REPLACE` the `Add:` AND `Remove:` pair is MANDATORY — listing only the new pattern is the duplication-by-omission failure mode that the v1.2 `review-triage-fix` rule was patched to catch post-hoc. The classifier prevents it pre-flight.
- If you realize mid-step that your classification was wrong, emit an updated `PATTERN:` header before the next tool call — re-classification is free.
- Files matching `*.md` / docs follow the same schema (typically `MODIFY` for sync edits, `ADD` for new sections).

```

Notes:
- Wording verbatim dallo spec §3.1 (lines 50-85). Le pipe `|` interne alle celle table sono escape via `\|` come da convenzione markdown standard.
- Posizionamento: subito DOPO "Core Responsibilities" perché logicamente è rifinitura del contract di output del coder (non un Process step — il Process descrive *come* leggere/implementare/verify, il classifier descrive *cosa dichiarare* a ogni mutation tool call). Vedi spec §3.1.
- Lingua: sezione in inglese (system prompt agent = code/contract, ereditato dal coder.md esistente che è all-English). Allineato a regola globale "codice e commit in inglese".
- Anchor literals (per harness Task 6):
  - `Pre-flight Pattern Classifier` → presente come heading H2 alla riga 2 del blocco.
  - `PATTERN: <CATEGORY>` → presente come literal nella riga `PATTERN: <CATEGORY> | <category-specific payload>` (riga 4 del blocco).
- Non rimuovere né modificare nessuna delle 5 numbered points di `## Core Responsibilities` (righe 19-23). Non rimuovere né modificare la sezione `## Process` (righe 25-31). Edit additive-only.
- Backup raccomandato pre-edit (decisione operativa del coder): `cp ~/.claude/agents/coder.md ~/.claude/agents/coder.md.bak-2026-05-20`.

- [ ] **Step 1: Write the minimal implementation** — edit `~/.claude/agents/coder.md` per inserire la nuova sezione markdown (~35 righe) come specificato sopra.

- [ ] **Step 2: Run test to verify partial green**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: tutti i 41 anchor v1.2 ancora `PASS`; le 2 nuove check Task-6 ora entrambe `PASS` (`coder.md: classifier section present` + `coder.md: PATTERN format spec present`); summary `PASS=43 FAIL=0`, exit 0. **TARGET RAGGIUNTO** (harness PASS=43).

- [ ] **Step 3: Spot-check direct grep**

Verify command (sanity):
```bash
grep -c '^## Pre-flight Pattern Classifier$' ~/.claude/agents/coder.md && grep -c 'PATTERN: <CATEGORY>' ~/.claude/agents/coder.md
```
Expected: `1` e `1` (un section heading exact match, un format spec literal). Conferma che l'inserzione è singola (no duplicati) e nel posto giusto.

- [ ] **Step 4: Checkpoint** — `coder.md` patchato e harness verde a `PASS=43`. TodoWrite update. La feature è live-effective al prossimo dispatch organico del `coder` agent (il subagent loaderà il system prompt aggiornato).

**Stima tempo:** 8 min.

---

### Task 3: reviewer.md "Pattern-drift check" bullet (green secondary)

**Files:**
- Modify: `~/.claude/agents/reviewer.md` (append bullet alla sezione `## Core Responsibilities`)

**Red phase:** harness post-Task-2 è `PASS=43 FAIL=0`. Questo task NON aggiunge anchor (vedi nota fine task). Red phase = inspectional: `grep -c 'Pattern-drift' ~/.claude/agents/reviewer.md` returns `0`.

**Green phase (edit concreto):** localizza in `~/.claude/agents/reviewer.md` la fine della sezione `## Core Responsibilities` (righe 18-22, 4 numbered points: ultimo è `4. Report findings by severity with \`file:line\` and a suggested fix.` alla riga 22). Append 1 bullet come 5° elemento (mantieni la numerazione attuale ma il prompt è in lista numerata; meglio aggiungere come continuazione bullet oppure come item 5). **Decisione plan:** continuare la numbered list con item 5, stile consistente con i 4 precedenti.

Inserisci tra riga 22 (`4. Report findings ...`) e riga 23 (blank line prima di `## Process`) la nuova riga:

```markdown
5. **Pattern-drift check.** If the diff under review was authored by the `coder` agent and the transcript contains `PATTERN:` headers, verify each declared category matches the corresponding hunk. Flag mismatches as MINOR `pattern-drift` finding (e.g. declared `ADD` but diff contains non-trivial deletions = should have been `REPLACE` or `MODIFY`). For declared `REPLACE` missing the `Remove:` half, flag as MAJOR (reproduces the duplication-by-omission failure mode caught by `review-triage-fix` v1.2). Not blocking; informational handoff to the next triage cycle.
```

Notes:
- Wording dallo spec §3.2 (lines 92-103), con leggera estensione per il caso REPLACE-incomplete → MAJOR (preserva la severity scaling dell'ADR §2.6 + spec §4 non-tolleranze).
- Posizione: come item 5 della numbered list `## Core Responsibilities`. Mantiene la simmetria stilistica (numbered list di 4-5 responsabilità, ciascuna 1 frase con leading bold).
- Non rimuovere né modificare i 4 numbered points esistenti (righe 19-22). Edit additive-only.
- **Nessun anchor structural in harness per reviewer.md.** Decisione plan: il `reviewer.md` non ha protezione anchor in questo cycle. Razionale: ADR §2.7 + spec §3.4 specificano "+2 anchor classifier section" come totale, riferito a `coder.md`. Aggiungere anchor anche su `reviewer.md` espanderebbe lo scope oltre quanto progettato. Trade-off accettato: il bullet `Pattern-drift check` è protetto solo da review umana del file, non da harness. Estensione futura possibile in v1.3 (defer).

- [ ] **Step 1: Write the implementation** — edit `~/.claude/agents/reviewer.md` per aggiungere item 5 alla numbered list `## Core Responsibilities`.

- [ ] **Step 2: Spot-check direct grep**

Verify command:
```bash
grep -c 'Pattern-drift check' ~/.claude/agents/reviewer.md && grep -c 'pattern-drift' ~/.claude/agents/reviewer.md
```
Expected: `1` e `≥1` (il leading bold + il finding label inline).

- [ ] **Step 3: Harness re-run (regressione anchor v1.2 + Task-6)**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: cumulative `PASS=43 FAIL=0`, exit 0 — invariato da fine Task 2. Il `reviewer.md` non è osservato dal harness, ma la re-run conferma che nessuna mod accidentale ha rotto i 43 anchor.

- [ ] **Step 4: Checkpoint** — `reviewer.md` patchato, secondary layer attivo, harness verde a `PASS=43`. TodoWrite update.

**Stima tempo:** 5 min.

---

### Task 4: ADR + spec status sync

**Files:**
- Modify: `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (status line)
- Modify: `docs/superpowers/specs/2026-05-20-coder-preflight-pattern-classifier-design.md` (status line)

**Red phase:** ADR riga 3 dice `**Status:** Proposed — 2026-05-20`. Spec riga 3 dice `**Stato:** approvato (post-ADR) — pronto per writing-plans`. Inspectional grep:
```bash
grep '^\*\*Status:\*\*' docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md
grep '^\*\*Stato:\*\*' docs/superpowers/specs/2026-05-20-coder-preflight-pattern-classifier-design.md
```
Mostrano stato pre-implementazione.

**Green phase (edit concreto):**

1. In `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` sostituisci riga 3:
   - Da: `**Status:** Proposed — 2026-05-20`
   - A: `**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-coder-preflight-pattern-classifier.md; harness PASS=43)`

2. In `docs/superpowers/specs/2026-05-20-coder-preflight-pattern-classifier-design.md` sostituisci riga 3:
   - Da: `**Stato:** approvato (post-ADR) — pronto per writing-plans`
   - A: `**Stato:** implementato — 2026-05-20 (harness PASS=43; dispatch organico del coder validerà la fedeltà LLM al contract, vedi Open questions ADR §4.4)`

Notes:
- Solo modifica a status line, no altro contenuto modificato. Mantiene il resto dei due deliverable integro.
- "Accepted" in ADR convenzionale (ADR template: Proposed → Accepted | Deprecated | Superseded). Allineato a stile ADR-MADR.

- [ ] **Step 1: Edit ADR status line** — applica la sostituzione 1.

- [ ] **Step 2: Edit spec status line** — applica la sostituzione 2.

- [ ] **Step 3: Verify both statuses updated**

Verify command:
```bash
grep '^\*\*Status:\*\*' /Users/stefanoferri/Developer/vibe-coding-system/docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md && grep '^\*\*Stato:\*\*' /Users/stefanoferri/Developer/vibe-coding-system/docs/superpowers/specs/2026-05-20-coder-preflight-pattern-classifier-design.md
```
Expected: entrambe le righe mostrano il nuovo stato `Accepted` / `implementato`. Nessun residuo di `Proposed` / `approvato (post-ADR)`.

- [ ] **Step 4: Checkpoint** — deliverable doc allineati a "implemented". TodoWrite update.

**Stima tempo:** 3 min.

---

### Task 5: Memory entry — new project file

**Files:**
- Create: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_coder-preflight-classifier.md`

**Red phase:** il file non esiste. Verify pre-edit:
```bash
ls ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_coder-preflight-classifier.md 2>&1
```
Expected: `No such file or directory`.

**Green phase (edit concreto):** crea il nuovo memory file con questo body:

```markdown
# Coder pre-flight pattern classifier

**Stato:** DEPLOYED LIVE 2026-05-20 in `~/.claude/agents/coder.md` + `~/.claude/agents/reviewer.md` + 2 anchor in `~/.claude/skills/review-triage-fix/tests/run-tests.sh`.

**Cosa:** contract di output `PATTERN: <CATEGORY> | <payload>` che il `coder` agent emette prima di ogni tool call `Edit`/`Write`. 4 categorie esaustive: `ADD`, `REMOVE`, `REPLACE`, `MODIFY`. Per `REPLACE` il pair `Add:` + `Remove:` è obbligatorio (promuove la regola v1.2 di `review-triage-fix` da post-hoc a pre-flight).

**Layer-stack enforcement:**
1. Primary: system prompt `~/.claude/agents/coder.md` (sezione `## Pre-flight Pattern Classifier`).
2. Secondary: pattern-drift check nel `~/.claude/agents/reviewer.md` (item 5 di Core Responsibilities); flag MINOR per drift, MAJOR per `REPLACE` senza `Remove:`.
3. Tertiary safety net: regola `Add+Remove rule (for SUBSTITUTION fixes)` in `~/.claude/skills/review-triage-fix/SKILL.md` Step 2 (v1.2, **invariata**) — coesistenza esplicita.

**Harness:** `~/.claude/skills/review-triage-fix/tests/run-tests.sh` PASS=41 (v1.2 baseline) → PASS=43 (+2 anchor `classifier section present` + `PATTERN format spec present` su `coder.md`). Cross-file structural assertion: prima volta che il harness `review-triage-fix` legge `coder.md` (vedi ADR §3.3 sub-question).

**Deliverable:**
- ADR: `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (Accepted 2026-05-20).
- Spec: `docs/superpowers/specs/2026-05-20-coder-preflight-pattern-classifier-design.md` (implementato 2026-05-20).
- Plan: `docs/superpowers/plans/2026-05-20-coder-preflight-pattern-classifier.md` (TDD 6 task, v1.0).

**Validazione pending:**
- Fedeltà LLM al contract `PATTERN:` (hit-rate >90% target). Validabile solo nell'uso organico.
- Reviewer pattern-drift detection rate. Validabile su 3-5 cicli `review-triage-fix` post-deploy.
- Granularità per-tool-call: overhead testuale problematico? Validabile con metriche pilota.
Vedi ADR §4.4 (Open questions).

**Subsume / supersede:**
- NON subsume `feedback_micropiano-refactor-cleanup` (RESOLVED 2026-05-20 da v1.2). Il classifier è additivo al layer-stack; v1.2 resta tertiary safety net.
- Si lega architetturalmente a `feedback_bash32-constraint` (harness 3.2-clean by construction).

**Invariante HARD:**
- Anchor preservation: PASS≥43 in ogni futuro change. Mai scendere sotto 41 (v1.2 baseline).
- Coexistenza v1.2: regola `Add+Remove rule` in SKILL.md Step 2 NON va rimossa né riassorbita nel classifier. Sono complementari.
- Bash 3.2: blocco Task 6 del harness 3.2-clean (literal `grep -q --` + ok/bad helpers).
```

Notes:
- Stile coerente con `project_swarm-testcmd.md`, `project_approve-testcmd-path-case.md` (memory esistenti): titolo h1 + stato leading + sezioni chiare + invariant esplicite.
- Lingua italiano (memory layer interno, allineato a `MEMORY.md` esistente).
- No path absolute fragile: i riferimenti file usano `~/.claude/` (portable) e path relativi al repo per i deliverable.

- [ ] **Step 1: Create the memory file** — `Write` del file `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_coder-preflight-classifier.md` con il content sopra.

- [ ] **Step 2: Verify creation**

Verify command:
```bash
test -f ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_coder-preflight-classifier.md && head -3 ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_coder-preflight-classifier.md
```
Expected: exit 0; output mostra titolo `# Coder pre-flight pattern classifier`, riga blank, riga stato `DEPLOYED LIVE 2026-05-20`.

- [ ] **Step 3: Checkpoint** — memory entry creato, deploy state catturato. TodoWrite update.

**Stima tempo:** 5 min.

---

### Task 6: MEMORY.md index update

**Files:**
- Modify: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` (append nuova riga in sezione `## Project`)

**Red phase:** baseline `MEMORY.md` ha 4 voci in `## Project` (righe 4-7) e 3 voci in `## Feedback` (righe 10-12). Nessuna voce per "coder pre-flight classifier". Verify pre-edit:
```bash
grep -c 'coder-preflight' ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md
```
Expected: `0`.

**Green phase (edit concreto):** append una nuova riga alla sezione `## Project` come 5° voce, immediatamente dopo riga 7 (`[approve-testcmd path case]...`) e prima della riga 8 (blank) / riga 9 (`## Feedback`). Nuova riga:

```markdown
- [Coder pre-flight classifier](project_coder-preflight-classifier.md) — **DEPLOYED 2026-05-20**: contract `PATTERN:` pre-Edit per `coder` agent (4 categorie ADD/REMOVE/REPLACE/MODIFY); layer-stack con `reviewer.md` pattern-drift + v1.2 safety net; harness PASS=43
```

Notes:
- Stile identico alle 4 voci esistenti: dash-prefix bullet + `[Title](file.md)` + em-dash + description + clauses semicolon-separated + closing senza punto finale.
- Posizionamento alla fine della sezione `## Project` per ordine cronologico-deploy (2026-05-19 swarm-testcmd → 2026-05-20 approve-testcmd → 2026-05-20 coder-preflight-classifier; il classifier è l'evento più recente).
- Non toccare le voci esistenti. Edit additive-only.

- [ ] **Step 1: Append the new row** — edit `MEMORY.md` per inserire la nuova riga in `## Project`.

- [ ] **Step 2: Verify update**

Verify command:
```bash
grep -c 'coder-preflight' ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md
```
Expected: `1` (la nuova riga; sale da 0 a 1).

- [ ] **Step 3: Final harness re-run (regressione end-to-end)**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: `PASS=43 FAIL=0`, exit 0. Conferma che tutti i task 1-5 lasciano l'harness verde, e che il task 6 (solo doc) non ha effetto sul harness.

- [ ] **Step 4: Checkpoint** — index aggiornato, ricerca memoria futura troverà il classifier. TodoWrite update. **Implementazione completa.**

**Stima tempo:** 4 min.

---

## Harness expected delta

| Stato | PASS | FAIL | Note |
|---|---|---|---|
| Baseline v1.2 (pre-implementazione, verificato 2026-05-20) | 41 | 0 | 17 g-anchor v1.0 + 1 frontmatter-name + 1 description + 1 v1.1 anchor (no — v1.1 non aggiunse anchor) + 1 v1.2 `Add+Remove rule`. Suddivisione: verify ×7 + weakening ×6 + state-diff ×4 + state-commit ×4 + SKILL.md ×20. |
| Post-Task-1 (red phase) | 41 | 2 | Nuovo blocco Task 6 emette 2 FAIL (`coder.md: classifier section missing`, `coder.md: PATTERN format spec missing`). Exit 1. |
| Post-Task-2 (green primary, target) | 43 | 0 | I 2 nuovi anchor passano (literal presenti in `coder.md`). Exit 0. **TARGET FINALE.** |
| Post-Task-3 (reviewer.md edit) | 43 | 0 | No change ai 43 anchor (reviewer.md non osservato dal harness). |
| Post-Task-4 (status doc sync) | 43 | 0 | No change al harness (solo doc edit). |
| Post-Task-5 (memory entry) | 43 | 0 | No change al harness (solo memory file). |
| Post-Task-6 (MEMORY.md index) | 43 | 0 | No change al harness. **Stato finale invariato.** |

**Delta totale dichiarato:** PASS=41 → PASS=43 (+2 anchor in nuovo blocco Task 6 del harness, entrambi su `coder.md`).

**Anchor preservation invariante:** in nessun task viene rimosso o alterato uno dei 41 anchor v1.2. Il blocco Task 6 è inserito tra l'ultimo anchor di Task 5 (`Add+Remove rule`, riga 144) e la summary line (`echo "----"...`, riga 146). I 41 anchor restano nelle stesse righe; il rebase delle line numbers post-insert sposta solo la summary line di +5 righe (4 righe blocco + 1 blank di separazione).

**Cumulative test post-deploy (sanity, opzionale):**
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh 2>&1 | grep -c '^PASS:'
# Expected: 43
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh 2>&1 | grep -c '^FAIL:'
# Expected: 0
```

---

## Risk summary

- **R1 — LLM drift sul contract `PATTERN:`.** Il `coder` agent potrebbe omettere il header in stress conditions (context pieno, prompt lungo). Mitigato da reviewer post-hoc (Task 3) e v1.2 safety net (preservato). Severity: medium. Validabile solo nell'uso organico (ADR §4.4 open question).
- **R2 — Bash 3.2 trap nel blocco Task 6.** Nuovo blocco usa `[ -f "$C" ]`-style guard rimosso in fase di refinement (vedi Task 1 Step 1 nota). Versione finale = solo `grep -q --` literal su `"$HOME/.claude/agents/coder.md"`. 3.2-clean by construction. Test: `bash --version` su macOS 26 è 3.2.57 (memory `feedback_bash32-constraint.md`). Severity: low.
- **R3 — Anchor breakage.** Inserimento accidentale del blocco Task 6 PRIMA della summary `echo "----"` ma in posizione errata potrebbe rompere il count finale. Mitigazione: il plan specifica posizione esatta (tra riga 144 e riga 146, post-`Add+Remove rule` anchor, pre-summary). Verify Task 1 Step 2 confronta `PASS=41 FAIL=2` esatto (non `PASS=39 FAIL=4` che indicherebbe breakage). Severity: low.
- **R4 — Reviewer non vede il transcript del coder.** Il pattern-drift check di Task 3 assume che il reviewer abbia accesso al transcript completo del coder per correlare `PATTERN:` headers con git diff. Se il reviewer è invocato in una sessione separata senza transcript context, il check è no-op silenzioso. Mitigazione: l'orchestrator deve fornire transcript come context al reviewer (responsabilità orchestrator, non plan). Severity: medium. Validabile in pilota.
- **R5 — Coexistenza v1.2 confusion.** Possibile drift cognitivo: "il classifier sostituisce v1.2?". HARD invariante (ADR §2.3, spec §3.3, questo plan): NO. v1.2 resta. Mitigazione: memory entry Task 5 esplicita "coesistono"; il `Add+Remove rule` in SKILL.md NON è modificato in nessun task. Severity: low (governance issue, non runtime).
- **R6 — Doc fragility.** Status line sync (Task 4) e memory entry (Task 5-6) sono doc-only; se un futuro coder riassorbe il classifier nel core senza aggiornare MEMORY.md, il search-by-keyword nel memory layer perde la voce. Mitigazione: convenzione "ogni feature merge aggiorna MEMORY.md" (vedi memory esistenti). Severity: low.

## HITL gate

Nessun gate hard richiesto dal deploy stesso (additivo, no destructive, no hook live, no settings.json, no schema DB). Le decisioni HITL del `~/.claude/CLAUDE.md` global (`commit, push, deploy, modifica schema DB, eliminazioni permanenti`) non si applicano: questo è un edit di system prompt agent + harness + doc, senza commit (repo doc senza git, `~/.claude/` senza git).

Validazione operativa POST-deploy è osservativa, non bloccante: il primo dispatch organico del `coder` agent post-deploy fornirà evidenza empirica della hit-rate dei `PATTERN:` headers. Se hit-rate <90% sui primi 20 tool calls, considera amendment v1.1 al classifier (es. rinforzo del wording "MUST" nel system prompt, esempi extra, eccetera).
