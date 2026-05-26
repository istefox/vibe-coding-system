# Design — review-triage-fix v1.2: Add+Remove micro-piano rule

**Data:** 2026-05-20
**Stato:** approvato (brainstorming) — pronto per writing-plans
**Autore:** Adriano per Stefano Ferri
**Topic:** prose-only patch a `SKILL.md` (+1 anchor structural test) per
istruire esplicitamente Add+Remove sui fix di sostituzione del micro-piano
`coder`. Area "B" sub-item B1 del brainstorm 2026-05-20 sulle migliorie
all'automazione vibe.

---

## 1. Contesto e problema

Nel cycle 2 di review-triage-fix v1.1 su `pricing-markup-cli` (2026-05-19) il
fix M-3 ("aggiungi autouse fixture per isolamento CONFIG_PATH") è stato
formulato come istruzione additiva ("aggiungi `_isolate_user_config` in
`conftest.py`"), ma il `coder` ha agito conservativamente: ha eseguito l'add
senza rimuovere il fixture `no_user_config` autouse preesistente in
`test_cli.py` che faceva lo stesso lavoro. Risultato: il re-review di Step 4
ha trovato 1 MAJOR (duplicazione autouse).

La causa-radice è nella formulazione del micro-piano: quando il fix è una
**sostituzione** (replace pattern A with pattern B), il `coder` plan-driven
ha bisogno di istruzioni esplicite su entrambi i lati — cosa aggiungere E
cosa rimuovere. La v1.1 discipline ("strictly 2-3 lines, do exactly the
change") non esplicita questa distinzione → il `coder` interpreta la
direttiva come solo-additiva → duplicazione.

La memory `feedback_micropiano-refactor-cleanup.md` ha catturato la lezione
con candidatura a patch v1.2. Questo design implementa quella patch.

## 2. Goal / Non-goal

**Goal:** rendere esplicito nel micro-piano del `coder` che i fix di
sostituzione richiedono enumerare sia `Add:` che `Remove:`. Il `coder`
plan-driven seguirà le istruzioni alla lettera → nessuna duplicazione →
re-review non rilevazione di MAJOR derivati da pattern obsoleti.

**Non-goal:** automatizzare la detection "questo fix è una sostituzione o
additivo". La classificazione resta giudizio LLM dell'orchestratore al
momento del triage Step 2. La regola dice "se classifichi come sostituzione,
allora il micro-piano DEVE avere Add+Remove" — non fornisce algoritmo per
classificare.

**Non-goal:** modificare il behavior di altri agenti (debugger, refactorer)
o dello stop-gate. Solo SKILL.md di review-triage-fix.

**Non-goal:** sblocco del parallel batch mode (sub-area B2). Quello richiede
prerequisito upstream (`isolation: worktree` in `~/.claude/agents/coder.md`)
ed è scope separato.

## 3. Architettura — prose-only additive patch

Aggiunta di un singolo paragrafo "Add+Remove rule" subito DOPO il bullet
esistente "Micro-piano discipline" in `SKILL.md` Step 2. La regola è prose
direttiva con esempi concreti, mirrord allo stile della v1.1 discipline
("strictly 2-3 lines", "do exactly that change and stop").

Coerente con la disciplina micro-piano già stabilita: il paragrafo non
sostituisce la discipline esistente, la rifinisce per il sotto-caso
substitution. Le altre disciplines (NIT batching, snapshot universale,
discipline 2-3 lines) restano invariate.

## 4. Modifiche puntuali

### File modificati

- **`~/.claude/skills/review-triage-fix/SKILL.md`** — append paragrafo
  "Add+Remove rule" dopo il bullet "Micro-piano discipline" in Step 2.
  Wording:

> **Add+Remove rule (for SUBSTITUTION fixes):** when the fix replaces a
> pattern rather than just adding (e.g. move local import to top-level,
> extract magic number to a named constant, consolidate duplicate fixtures,
> rename a helper), the micro-piano MUST list BOTH the new pattern
> (`Add: ...`) AND the old instances to delete (`Remove: <path:line> ...`).
> Without an explicit Remove, the coder typically acts conservatively and
> leaves the old pattern in place → duplication that the re-review then
> flags as a new finding (observed cycle 2 2026-05-20, M-3 autouse fixture
> → M-1 re-review). For purely ADDITIVE fixes (missing input validation,
> new edge-case test, docstring fix), Add: alone suffices — no Remove
> section needed.

- **`~/.claude/skills/review-triage-fix/tests/run-tests.sh`** — append 1
  nuova structural assertion al blocco `# --- Task 5: SKILL.md structural
  completeness ---`:
  ```
  g 'Add+Remove rule' 'add+remove substitution rule'
  ```
  Harness target count va da PASS=40 → **PASS=41**.

- **`docs/superpowers/plans/2026-05-19-review-triage-fix.md`** — sync
  embedded SKILL.md block in Task 5 Step 3 (riproduce paragrafo nuovo); sync
  Task 5 harness block (aggiunge anchor); aggiorna riferimenti numerici
  "PASS=40" → "PASS=41" (Step 4 di Task 5, Step 1 di Task 6, eventuali
  altre occorrenze); aggiungi sezione "v1.2 (2026-05-20)" nel changelog
  dopo "v1.1 (2026-05-19, post-pilot)".

- **`docs/superpowers/specs/2026-05-19-review-triage-fix-design.md`** —
  status line: `… v1.1 (post-pilot parziale 2026-05-19) …` →
  `… v1.1 → v1.2 (2026-05-20 Add+Remove rule) …`.

### File nuovi

Nessuno.

### Memory update

- **`~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/feedback_micropiano-refactor-cleanup.md`**
  — aggiorna da "candidato patch v1.2" a "**RESOLVED 2026-05-20**" con
  riferimento alle spec/plan e a SKILL.md Step 2.

## 5. Deploy strategy

Niente HITL gate complesso. Le modifiche sono:
- Additive (nuovo paragrafo, nessuna rimozione di prose esistente)
- Anchor-preserving (nessuno dei 19 anchor strutturali esistenti viene
  rimosso o modificato; ne aggiungo 1)
- Test-positive (harness conta sale di 1 da PASS=40 a PASS=41)
- Non toccano hook live, settings.json, agenti, MCP

Quindi: edit diretti su SKILL.md + harness + plan/spec/memory. Harness run
finale a conferma. Nessun backup necessario (i .md sono già committati nel
proprio repo doc).

## 6. Testing

L'unica verifica deterministica è la structural assertion nel harness:
```
g 'Add+Remove rule' 'add+remove substitution rule'
```
che greppa la presenza del literal "Add+Remove rule" nel SKILL.md deployed.

L'efficacia operativa della regola (LLM la segue durante triage) è
intrinsecamente non-deterministica e validabile solo nell'uso reale. Il
prossimo ciclo organico di review-triage-fix che incontri un fix di
sostituzione fornirà evidenza empirica. Non è bloccante: la regola è prose
direttiva che il `coder` plan-driven seguirà se l'orchestratore la include
nel micro-piano (responsabilità dell'orchestratore al triage).

**Bash 3.2 / BSD compat:** la nuova assertion usa `grep -q -- "$1"` come
le 19 esistenti — già provato 3.2-clean.

## 7. Vincoli & invarianti

- **Anchor preservation:** nessuno dei 19 anchor v1.1 viene rimosso o
  alterato. Si aggiunge 1 nuovo anchor (`Add+Remove rule`). Test count va a
  PASS=41.
- **Style consistency:** il nuovo paragrafo segue lo stile prose della v1.1
  micro-piano discipline (paragraph bullet con titolo bold, frase
  spiegativa concreta, esempio inline, riferimento forensic dove rilevante).
- **No behavior change su altri Steps:** Step 0, 1, 3, 4, 5 invariati.
  Step 2 invariato eccetto per l'aggiunta del paragrafo.
- **Backward compat dei micro-piani esistenti:** i fix additivi continuano
  a funzionare con la sola Add:; nessun micro-piano esistente diventa
  invalido. La regola è additiva-restrittiva sul sotto-caso substitution.

## 8. Out of scope

- B2 (parallel batch mode) — richiede `isolation: worktree` upstream in
  `coder.md`, scope separato.
- Modifiche al `coder.md` agent — la responsabilità di formulazione del
  micro-piano è dell'orchestratore (SKILL.md), non del `coder`. Il `coder`
  esegue alla lettera ciò che riceve.
- Automatic detection "substitution vs additive" — resta giudizio LLM al
  triage.
- Aggiornamento di altre skill (`adr-writer`, `code-review-checklist`,
  etc.) — restano invariate.

## 9. Confidence

**Alta.** È una patch di prose additiva, ~3 righe + 1 anchor test, su
artefatti già consolidati e bi-revisionati (SKILL.md è uscita da
spec-review + code-quality + final integration review nel ciclo originale,
con i fix v1.1 e M2 caveat applicati). Niente rischi di regressione
(additivo, anchor-preserving). L'unica incertezza è l'efficacia operativa
(LLM-mediated) — non controllabile via test, validabile nell'uso organico.
