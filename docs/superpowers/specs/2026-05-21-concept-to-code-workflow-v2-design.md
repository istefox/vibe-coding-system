# `concept-to-code` workflow v2 — Design Spec (Gate 0 + brownfield + brainstorm-gate)

**Status:** implementato — 2026-05-21
**ADR:** `docs/architecture/ADR-0008-concept-to-code-workflow-v2-brainstorm.md`
**Plan:** `docs/superpowers/plans/2026-05-21-concept-to-code-workflow-v2.md`
**Estende:** ADR-0003 (chain v1), ADR-0007 (smoke-e2e).
**Schema target:** `manifest_schema_version: "1.1"` (retrocompatibile con 1.0).

---

## 1. Sintesi

Tre modifiche coordinate allo skill `concept-to-code` (stesso file → un solo intervento):

1. **Gate 0** — triage chain-vs-leggero all'avvio, decisione all'utente.
2. **Brownfield mode** — comportamento esplicito di Step 1 e Step 3 a seconda della
   presenza di SPEC.md / CLAUDE.md.
3. **Brainstorm-gate (gate 1b)** — gate opzionale tra Step 1 e Step 2 che invoca
   `design-brainstorm`.

Più le modifiche a manifest schema (1.1) e ai 3 helper bash, e un nuovo helper
`gate0-detect.sh`.

---

## 2. Manifest schema 1.1

### 2.1 Campi nuovi (additive su 1.0)

```yaml
manifest_schema_version: "1.1"          # era "1.0"
topic: "<slug>"
topic_full_title: "<title>"
project_root: "<abs>"
mode: "greenfield"                       # NEW: greenfield | brownfield
created_at: "<iso>"
last_updated_at: "<iso>"
current_step: "step_0_init"
status: "in_progress"

gate0:                                   # NEW: esito del triage Gate 0
  decision: null                         # null | chain | leggero | abort
  criteria_spec_adr_exist: false         # bool: SPEC.md + ADR presenti all'avvio
  decided_at: null

artifacts:
  spec: null
  brainstorm: null                       # NEW: path BRAINSTORM.md o null
  adr: null
  arch: null
  plan: null
  project_claude_md: null

hitl_gates:
  - gate: 1
    label: "spec_review"
    ...
  # (gate 2, 3, 5 invariati — array resta >= 4 elementi)
  # gate 1b NON aggiunto all'array hitl_gates (è tracciato dal current_step, non
  #   dall'audit trail) per non rompere l'invariante count; vedi §2.3.
...
```

### 2.2 Migrazione 1.0 → 1.1 (documentata)

- **Forward-only, additive.** Un manifest 1.0 è un manifest 1.1 valido a cui mancano
  i campi opzionali (`mode`, `gate0`, `artifacts.brainstorm`). Nessuna riscrittura dei
  manifest esistenti è necessaria.
- **I manifest rempay completati (schema 1.0, `status: completed`)** restano validi:
  `manifest-validate.sh` accetta `manifest_schema_version` ∈ {"1.0", "1.1"}.
- **`manifest-init.sh` scrive sempre 1.1** con i campi nuovi popolati
  (`mode` derivato da `gate0-detect.sh`, `gate0.criteria_spec_adr_exist`,
  `artifacts.brainstorm: null`).
- **Nessuna procedura di upgrade automatico:** i vecchi manifest restano 1.0; solo i
  nuovi nascono 1.1. La validate gestisce entrambi.

### 2.3 Invarianti validate aggiornate

`manifest-validate.sh` (modifiche puntuali, retrocompat):

- **Inv. 1 (schema version):** da `grep -q '^manifest_schema_version: "1.0"$'` a
  accettare 1.0 OR 1.1. Bash 3.2-clean:
  ```sh
  if ! grep -Eq '^manifest_schema_version: "(1\.0|1\.1)"$' "$MANIFEST"; then
    fail "manifest_schema_version missing or not 1.0/1.1"
  fi
  ```
- **Inv. 5 (current_step enum):** aggiungere `gate_1b_brainstorm_decision` alla lista
  `VALID_STEPS` (temp-file). Tutti gli altri stati invariati.
- **Inv. 9 (hitl_gates count):** da `== 4` a `>= 4`:
  ```sh
  if [ "$gate_count" -lt 4 ]; then
    fail "hitl_gates must have at least 4 entries (found $gate_count)"
  fi
  ```
  (Retrocompat: i manifest a esattamente 4 gate restano validi. Si rilassa per non
  bloccare un eventuale audit trail futuro; oggi nessun gate viene aggiunto all'array.)
- **Inv. nuova (mode, condizionale):** se la riga `^mode:` è presente, il valore deve
  essere `greenfield` o `brownfield`; se assente (manifest 1.0), skip (no fail).
  Bash 3.2-clean:
  ```sh
  if grep -q '^mode:' "$MANIFEST"; then
    mode_val="$(grep '^mode:' "$MANIFEST" | sed 's/^mode: *//;s/"//g' | head -1)"
    case "$mode_val" in
      greenfield|brownfield) ;;
      *) fail "mode '$mode_val' invalid (greenfield|brownfield)" ;;
    esac
  fi
  ```

Tutte le altre invarianti (topic, project_root, status, completed-requires-artifacts,
failed-requires-failed_step) restano identiche.

---

## 3. State machine v2

### 3.1 Enum stati (15 → 16)

Aggiunto **uno** stato: `gate_1b_brainstorm_decision`.

```
step_0_init → step_1_interview → gate_1_spec_review
  → gate_1b_brainstorm_decision        ← NEW (opzionale, può essere bypassato)
  → step_2_architecture → gate_2_architecture_review
  → step_3_project_memory → gate_3_project_memory_review
  → step_4_session_boundary → ready_for_implementation
  [FRESH SESSION]
  → step_5_implementation → step_6_review → gate_5_review_decision
  → completed
```

Terminali: `completed`, `failed`, `aborted`. Gate 0 NON è uno stato (è un check in
`step_0_init`). Brownfield NON è uno stato (è il flag `mode`).

### 3.2 Transizioni legali (16 → 18)

Le 16 pair di v1 RESTANO TUTTE LEGALI (incluso il path diretto
`gate_1_spec_review → step_2_architecture`, preservato per retrocompat con manifest 1.0
e con lo smoke-e2e esistente). Si AGGIUNGONO 2 pair:

```
gate_1_spec_review,gate_1b_brainstorm_decision        ← NEW
gate_1b_brainstorm_decision,step_2_architecture       ← NEW
```

`manifest-transition.sh`: aggiungere queste 2 righe al blocco PAIRS (temp-file), senza
toccare le 16 esistenti. La wildcard `* → failed | aborted` resta invariata e copre
Gate 0 `[l]`/`[a]`.

Tabella completa (18 pair):
```
step_0_init,step_1_interview
step_1_interview,gate_1_spec_review
gate_1_spec_review,step_2_architecture            (preservata — path "no brainstorm" legacy)
gate_1_spec_review,step_1_interview
gate_1_spec_review,gate_1b_brainstorm_decision    NEW
gate_1b_brainstorm_decision,step_2_architecture   NEW
step_2_architecture,gate_2_architecture_review
gate_2_architecture_review,step_3_project_memory
gate_2_architecture_review,step_2_architecture
step_3_project_memory,gate_3_project_memory_review
gate_3_project_memory_review,step_4_session_boundary
gate_3_project_memory_review,step_3_project_memory
step_4_session_boundary,ready_for_implementation
ready_for_implementation,step_5_implementation
step_5_implementation,step_6_review
step_6_review,gate_5_review_decision
gate_5_review_decision,completed
step_5_implementation,gate_5_review_decision
```

### 3.3 Path runtime per scenario

- **Greenfield + brainstorm n:** 0→1→g1→[g1b? no, va diretto]→2... — l'orchestrator,
  quando brainstorm-gate=n, può usare sia la pair diretta `g1→2` sia passare per
  `g1→g1b→2`. **Convenzione v2:** passa SEMPRE per `g1b` (registra l'esito n nel
  manifest), così il manifest documenta che il brainstorm è stato offerto e rifiutato.
  La pair diretta `g1→2` resta legale solo per retrocompat (smoke-e2e v1, manifest 1.0).
- **Greenfield + brainstorm y:** 0→1→g1→g1b→[invoca design-brainstorm, scrive
  BRAINSTORM.md, popola artifacts.brainstorm]→2 (dispatch architect con brief).
- **Brownfield (SPEC esiste):** Gate 0 mostra criterio A; utente `[c]`. Step 1 è
  no-op (punta artifacts.spec all'esistente), transizione 0→1→g1 con Gate 1 marcato
  "spec pre-esistente approvata"→g1b→2.

---

## 4. Gate 0 — triage chain-vs-leggero

### 4.1 Posizione nel flusso

Form A (`/skill concept-to-code <topic>`):
1. Genera slug, determina project_root.
2. `manifest-init.sh` (stato `step_0_init`, scrive `mode` da gate0-detect).
3. **Gate 0:** esegui `gate0-detect.sh <project-root>`. Se nessun criterio attivo →
   passa silenziosamente. Se criterio attivo → mostra il box e attendi input.
4. `[c]` → transizione `step_0_init → step_1_interview` (prosegui). `[l]` → transizione
   `* → aborted aborted`, scrivi `gate0.decision: leggero`, `next_action` documenta il
   fallback. `[a]` → abort.

### 4.2 `gate0-detect.sh`

```
Usage: gate0-detect.sh <project-root>
Output (stdout, una riga per fatto):
  spec_adr_exist=true|false        # SPEC.md esiste AND almeno un docs/architecture/ADR-*.md
  mode=greenfield|brownfield       # brownfield sse SPEC.md esiste
Exit: 0 sempre (detector, non validatore).
```

Bash 3.2-clean:
```sh
#!/usr/bin/env bash
set -u
[ "$#" = "1" ] || { echo "usage: gate0-detect.sh <project-root>" >&2; exit 1; }
root="$1"
spec="no"; [ -f "$root/SPEC.md" ] && spec="yes"
adr="no"
if ls "$root"/docs/architecture/ADR-*.md >/dev/null 2>&1; then adr="yes"; fi
if [ "$spec" = "yes" ] && [ "$adr" = "yes" ]; then
  echo "spec_adr_exist=true"
else
  echo "spec_adr_exist=false"
fi
if [ "$spec" = "yes" ]; then echo "mode=brownfield"; else echo "mode=greenfield"; fi
exit 0
```

(Il criterio B "micro-scope <3 file" NON è rilevato dallo script — è un flag dichiarativo
che l'orchestrator presenta all'utente nel box, vedi ADR §2.2. Lo conta l'utente.)

### 4.3 Box Gate 0 (italiano)

```
============================================================
concept-to-code · Gate 0 · TRIAGE CHAIN
============================================================
Criteri di esclusione rilevati:
  [x] SPEC.md + ADR già esistenti in <project-root>     (se spec_adr_exist=true)
  [ ] Micro-scope (<3 file) — confermalo tu
Manifest: <manifest-path>
============================================================
HITL Gate 0: chain_triage
  [c] chain completo (procedi con interview/architettura)
  [l] workflow leggero (plan diretto, niente chain)
  [a] abort chain
> _
```

Quando `spec_adr_exist=false` e l'utente non ha dichiarato micro-scope, Gate 0 NON viene
mostrato (UX greenfield invariata).

---

## 5. Brownfield mode

### 5.1 Determinazione

`mode` è scritto da `manifest-init.sh` (derivato da `gate0-detect.sh`): `brownfield` sse
`<project-root>/SPEC.md` esiste all'avvio. Confermato implicitamente dalla scelta `[c]`
al Gate 0.

### 5.2 Step 1 in brownfield

- Greenfield: invoca `interview-driver`, scrive SPEC.md nuovo.
- **Brownfield:** SALTA `interview-driver`. `artifacts.spec = <project-root>/SPEC.md`
  (l'esistente). Transizione `step_0_init → step_1_interview → gate_1_spec_review`
  (lo stato interview esiste ma è no-op). Gate 1 mostrato con label/nota
  **"spec pre-esistente approvata"**:
  ```
  ============================================================
  concept-to-code · Step 1 · SPEC PRE-ESISTENTE
  ============================================================
  Artifact: <project-root>/SPEC.md (pre-esistente, non rigenerato)
  Modalità: brownfield — l'interview è stato saltato per non sovrascrivere la SPEC.
  ...
  HITL Gate 1: spec_review (spec pre-esistente)
    [y] approva la SPEC esistente e procedi
    [e] voglio rigenerarla via interview (passa a greenfield per questo topic)
    [a] abort
  ```
  `[e]` → consente all'utente di forzare l'interview (override esplicito: setta
  `mode: greenfield`, invoca interview-driver). Questo copre il caso "la SPEC esiste ma
  voglio rifarla".

### 5.3 Step 3 in brownfield (e su CLAUDE.md esistente, sempre)

Lo Step 3 diventa **sempre additivo** quando `CLAUDE.md` esiste (indipendentemente da
greenfield/brownfield):

- `CLAUDE.md` NON esiste → `claude-md-generator` genera da zero (come oggi).
- `CLAUDE.md` esiste → `claude-md-generator` invocato in **modalità additiva**: produce
  `CLAUDE.md.proposed` = contenuto attuale **preservato** + sezione appended
  `## Decisioni dal chain <topic>` che referenzia il nuovo ADR (`artifacts.adr`). MAI
  rigenerare da zero degradando i gotcha curati. Gate 3 mostra il `diff` (solo le righe
  aggiunte).

Il dispatch a `claude-md-generator` (Step 3) passa esplicitamente la direttiva additiva
quando `CLAUDE.md` esiste. Lo SKILL.md di `claude-md-generator` NON viene modificato:
la direttiva additiva è veicolata nel prompt template del dispatch (coerente con la
strategia "prompt template versionato nello skill" di ADR-0003 §2.9).

---

## 6. Brainstorm-gate (gate 1b)

### 6.1 Posizione e box

Dopo Gate 1 approvato (`current_step` transiziona `gate_1_spec_review →
gate_1b_brainstorm_decision`). Box:

```
============================================================
concept-to-code · Gate 1b · BRAINSTORM (opzionale)
============================================================
SPEC pronto: <artifacts.spec>
Esplorare alternative di design (metodologia + idee nuove) prima di fissare l'ADR?
La sessione di brainstorm produce un BRAINSTORM.md che alimenta l'architect.
============================================================
HITL Gate 1b: brainstorm_decision
  [y] sì, esplora con design-brainstorm
  [n] no, vai diretto all'architect (comportamento standard)
> _
```

### 6.2 Esito `n`

Transizione `gate_1b_brainstorm_decision → step_2_architecture`. `artifacts.brainstorm`
resta null. Dispatch architect **identico ad ADR-0003** (nessun brief). Zero regressioni.

### 6.3 Esito `y`

1. Invoca la skill `design-brainstorm` IN-SESSION (non un fresh session — il brainstorm
   precede l'architettura ed è parte del lavoro di design):
   ```
   Use the design-brainstorm skill.
   Requirements source: SPEC.md at <project-root>/SPEC.md.
   Explore design approaches and new application ideas with the user using structured
   ideation techniques. Write the structured brief to <project-root>/BRAINSTORM.md.
   Do NOT write SPEC, ADR, or plan. Do NOT invoke writing-plans. Return when BRAINSTORM.md
   is written.
   ```
2. Dopo che `design-brainstorm` ritorna, l'orchestrator scrive
   `artifacts.brainstorm = <project-root>/BRAINSTORM.md` nel manifest (stesso pattern
   YAML-edit di artifacts.spec).
3. Transizione `gate_1b_brainstorm_decision → step_2_architecture`.
4. Step 2: dispatch architect con BRAINSTORM.md aggiunto al contesto (vedi §6.4).

### 6.4 Dispatch architect aggiornato (Step 2)

Il prompt template di Step 2 (ADR-0003 §Step 2) acquisisce una riga condizionale:
```
Read SPEC.md at <project-root>/SPEC.md.
If a brainstorm brief exists, read it at <manifest.artifacts.brainstorm> and treat its
alternatives as candidate inputs for the ADR's "Alternatives considered" section; state
which you adopt and why.
Produce: ADR ..., Plan ..., optional ARCH.md ...
```
Quando `artifacts.brainstorm` è null, la riga è no-op (l'architect opera come oggi).

---

## 7. Coexistence e retrocompat (HARD)

- **Manifest rempay completati (1.0):** restano validi (validate accetta 1.0 OR 1.1).
- **smoke-e2e v1:** il path diretto `gate_1_spec_review → step_2_architecture` è
  preservato → lo smoke-e2e esistente continua a passare senza modifiche. Si AGGIUNGE
  una nuova fase smoke per il path `g1 → g1b → 2` (vedi plan).
- **Self-test concept-to-code (PASS=13):** anchor-preserving. Nuove assertion appended
  (mode validate, gate 1b transition, schema 1.1 accept, gate0-detect). Vedi plan per
  il delta.
- **review-triage-fix harness (PASS=49):** +N anchor per la nuova skill
  `design-brainstorm` e per i nuovi campi del chain. Solo append.
- **Skill non modificate:** `interview-driver`, `claude-md-generator` (la direttiva
  additiva è nel prompt template del chain, non nel loro SKILL.md), `review-triage-fix`,
  `refactor-snapshot`, `vibe-status`. Agent non modificati.
- **`vibe-status`:** se legge i manifest, deve tollerare lo stato nuovo
  `gate_1b_brainstorm_decision` e schema 1.1. Verificare nel plan (anchor o smoke) che
  non rompa; se vibe-status enumera gli stati validi, va esteso. (Risk flag.)

---

## 8. Riepilogo modifiche file

- `~/.claude/skills/concept-to-code/SKILL.md` — Gate 0, brownfield branching su Step 1/3,
  gate 1b, dispatch architect aggiornato, sezione state machine v2, schema 1.1.
- `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` — schema 1.1, campi
  `mode`/`gate0`/`artifacts.brainstorm`, 4° arg opzionale `mode`.
- `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` — schema 1.0|1.1,
  enum +gate_1b, hitl_gates `>=4`, mode condizionale.
- `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` — +2 pair legali.
- `~/.claude/skills/concept-to-code/scripts/gate0-detect.sh` — NUOVO.
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` — +assertion (anchor-preserving).
- `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` — +fase per path g1b.
- `~/.claude/skills/design-brainstorm/SKILL.md` + `tests/run-tests.sh` — NUOVI.
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — +anchor (append).
