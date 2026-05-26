# `concept-to-code` workflow v2 + skill `design-brainstorm` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:executing-plans (o
> subagent-driven-development) per eseguire questo plan task-by-task. Step tracciati con
> checkbox (`- [ ]`).

**Changelog:**
- v1.0 (2026-05-21): initial — TDD plan derivato da
  `ADR-0008-concept-to-code-workflow-v2-brainstorm.md` e dai due spec
  (`2026-05-21-concept-to-code-workflow-v2-design.md`,
  `2026-05-21-design-brainstorm-skill-design.md`). 11 task: 1 red harness anchor + skill
  design-brainstorm + patch dei 3 helper + nuovo gate0-detect + patch SKILL.md + smoke +
  status sync + memory.

**Goal:** implementare il workflow v2 del chain concept-to-code (Gate 0, brownfield mode,
brainstorm-gate 1b) e la nuova skill `design-brainstorm`, su manifest schema 1.1
retrocompatibile con 1.0, mantenendo verdi tutti gli harness e senza rompere i chain già
completati (manifest rempay 1.0).

**Architecture:** una skill nuova additiva (`~/.claude/skills/design-brainstorm/`), patch
in-place dello skill `concept-to-code` (SKILL.md + 3 helper + 1 helper nuovo + 2 test),
1 anchor block appended al harness review-triage-fix. Tutti gli script bash 3.2-clean by
construction (memory `feedback_bash32-constraint.md`). Nessun edit ad agent, hook,
settings, MCP, rules, né alle skill `interview-driver`/`claude-md-generator`/
`review-triage-fix`/`refactor-snapshot`/`vibe-status`.

**Spec:** `docs/superpowers/specs/2026-05-21-concept-to-code-workflow-v2-design.md`,
`docs/superpowers/specs/2026-05-21-design-brainstorm-skill-design.md` (Proposed).
**ADR:** `docs/architecture/ADR-0008-concept-to-code-workflow-v2-brainstorm.md` (Proposed).

---

## Environment notes (read first)

- **No git in `~/.claude/` né nel repo blueprint.** Checkpoint per task = harness verde +
  TodoWrite update. Nessun commit, nessuno step git (vincolo brief).
- **Bash 3.2.57 cleanliness.** Tutti gli script (`gate0-detect.sh`, patch a init/validate/
  transition, harness) usano solo `grep`/`sed`/`[ ]`/`mktemp`/`mv`/`date`/`ls`/`case`/
  `ok`/`bad`. Niente assoc array, `mapfile`, `${v^^}`, `<()`, here-string. `bash -n` su
  ogni script pre-checkpoint.
- **Anchor preservation.** Baseline verificati 2026-05-21:
  - concept-to-code self-test: **PASS=13 FAIL=0**.
  - review-triage-fix harness: **PASS=49 FAIL=0**.
  - smoke-e2e (concept-to-code): integrato nel self-test (assertion 13).
  Nessun anchor esistente rimosso o alterato; solo append. Le 16 transition pair di v1
  RESTANO; il path diretto `gate_1_spec_review → step_2_architecture` è preservato.
- **Schema retrocompat.** `manifest-validate.sh` deve accettare 1.0 OR 1.1; i manifest
  rempay completati (1.0) restano validi. Verificato da una assertion dedicata.
- **Backup pre-edit raccomandato** (consistency con plan ADR-0003): copia `.bak-2026-05-21-v2`
  di SKILL.md, dei 3 helper, dei 2 test del chain e del harness review-triage-fix prima
  di editarli.

## Harness expected delta (esplicito)

| Harness | Baseline | Target | Delta |
|---|---|---|---|
| `design-brainstorm/tests/run-tests.sh` (NEW) | 0 (non esiste) | **PASS=8** | +8 (nuovo) |
| `concept-to-code/tests/run-tests.sh` | PASS=13 | **PASS=20** | +7 anchor |
| `review-triage-fix/tests/run-tests.sh` | PASS=49 | **PASS=51** | +2 anchor |
| `concept-to-code/tests/smoke-e2e.sh` | SMOKE=PASS | SMOKE=PASS | +1 fase (g1b) |
| `refactor-snapshot`, `vibe-status`, `pre-flight-pattern-enforce`, `run-hook-tests` | 18 / 10 / 10 / 24 | invariati | 0 |

I +7 anchor del self-test concept-to-code: (1) schema 1.1 accept, (2) schema 1.0 ancora
accept [retrocompat], (3) transition g1→g1b legale, (4) transition g1b→2 legale, (5)
enum gate_1b valido, (6) mode brownfield validato, (7) gate0-detect rileva
spec_adr_exist+mode. I +2 anchor review-triage-fix: esistenza `design-brainstorm/SKILL.md`
+ literal `BRAINSTORM.md` nel suo body.

---

## File structure

- Create `~/.claude/skills/design-brainstorm/SKILL.md` — frontmatter + body (Lingua,
  When to invoke, differenze dalle skill, 7 tecniche, flusso dialogico, output contract,
  coexistence). ~280 righe. NO `disable-model-invocation: true`.
- Create `~/.claude/skills/design-brainstorm/tests/run-tests.sh` — 8 assertion structural.
- Create `~/.claude/skills/concept-to-code/scripts/gate0-detect.sh` — bash 3.2, ~25 righe.
- Modify `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` — schema 1.1, campi
  mode/gate0/artifacts.brainstorm, 4° arg opzionale.
- Modify `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` — schema 1.0|1.1,
  enum +gate_1b, hitl_gates >=4, mode condizionale.
- Modify `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` — +2 pair.
- Modify `~/.claude/skills/concept-to-code/SKILL.md` — Gate 0, brownfield, gate 1b,
  dispatch architect, state machine v2, schema 1.1.
- Modify `~/.claude/skills/concept-to-code/tests/run-tests.sh` — +7 assertion.
- Modify `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` — +fase path g1b.
- Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — +2 anchor (append).
- Modify `docs/architecture/ADR-0008-...md` + i 2 spec — status line a "Accepted/implementato".
- Create/Modify memory entry + MEMORY.md index.

Unchanged (HARD): agent (`coder.md`/`reviewer.md`/`refactorer.md`/`architect.md`/...),
hook, `settings.json`, `.mcp.json`, `.claude/rules/`, `interview-driver/SKILL.md`,
`claude-md-generator/SKILL.md`, `review-triage-fix/SKILL.md`, `refactor-snapshot/*`,
`vibe-status/SKILL.md` (salvo eventuale estensione enum stati — vedi T9 risk check).

---

### Task 1: Harness anchor failing (red) — ANCHOR

**Files:** Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh`.

**Red:** baseline `PASS=49 FAIL=0`. Inserisci un nuovo blocco anchor TRA l'ultimo blocco
esistente e la summary line (`echo "----"`), che cerca:
```sh
# --- design-brainstorm skill section ---
DB="$HOME/.claude/skills/design-brainstorm/SKILL.md"
[ -f "$DB" ] && ok "design-brainstorm: SKILL.md present" || bad "design-brainstorm: SKILL.md missing"
grep -q -- 'BRAINSTORM.md' "$DB" 2>/dev/null && ok "design-brainstorm: BRAINSTORM.md output contract present" || bad "design-brainstorm: BRAINSTORM.md contract missing"
```
Entrambi assenti pre-Task-2 → 2 FAIL. Atteso `PASS=49 FAIL=2`, exit 1.

**Verify:** `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo exit=$?`
→ `PASS=49 FAIL=2`.

- [ ] Step 1: write failing anchor block.
- [ ] Step 2: run, confirm red `PASS=49 FAIL=2`.
- [ ] Step 3: checkpoint + TodoWrite.

**Stima:** 5 min.

---

### Task 2: Create skill `design-brainstorm/SKILL.md` (green su anchor T1)

**Files:** Create `~/.claude/skills/design-brainstorm/SKILL.md`.

**Red:** la directory non esiste; `ls -d ~/.claude/skills/design-brainstorm/` → no such.

**Green:** scrivi SKILL.md secondo lo spec `2026-05-21-design-brainstorm-skill-design.md`.
DEVE contenere: frontmatter `name: design-brainstorm` (NO `disable-model-invocation`),
sezione `## Lingua`, le 7 tecniche con le 3 cardine marcate, il flusso dialogico
(routing + regole), il template `BRAINSTORM.md` (literal `BRAINSTORM.md` presente),
sezione coexistence. Literal richiesti dagli anchor: `BRAINSTORM.md`, `first-principles`,
`analogie cross-dominio`, `inversione`/`pre-mortem`, `## Lingua`.

**Verify:**
```sh
mkdir -p ~/.claude/skills/design-brainstorm/tests
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo exit=$?   # → PASS=51 FAIL=0
head -20 ~/.claude/skills/design-brainstorm/SKILL.md
grep -c 'disable-model-invocation' ~/.claude/skills/design-brainstorm/SKILL.md  # → 0
```

- [ ] Step 1: mkdir skill dir.
- [ ] Step 2: write SKILL.md.
- [ ] Step 3: run review-triage-fix harness → `PASS=51 FAIL=0`.
- [ ] Step 4: checkpoint + TodoWrite.

**Stima:** 50 min (è il deliverable di qualità — contenuto metodologico ricco).

---

### Task 3: Create `design-brainstorm/tests/run-tests.sh` (self-test PASS=8)

**Files:** Create `~/.claude/skills/design-brainstorm/tests/run-tests.sh`.

**Red:** il file non esiste.

**Green:** harness bash 3.2-clean, 8 assertion structural sul SKILL.md (spec §7):
1 file exists, 2 `name: design-brainstorm`, 3 NON contiene `disable-model-invocation: true`,
4 `first-principles`, 5 `cross-dominio`/`cross-domain`, 6 `inversione`/`pre-mortem`,
7 `BRAINSTORM.md`, 8 `## Lingua`. Stile identico a refactor-snapshot self-test.

**Verify:** `bash ~/.claude/skills/design-brainstorm/tests/run-tests.sh; echo exit=$?`
→ `PASS=8 FAIL=0`.

- [ ] Step 1: write harness. Step 2: `bash -n`. Step 3: chmod +x. Step 4: run → PASS=8.
- [ ] Step 5: checkpoint + TodoWrite.

**Stima:** 25 min.

---

### Task 4: Create `gate0-detect.sh`

**Files:** Create `~/.claude/skills/concept-to-code/scripts/gate0-detect.sh`.

**Red:** lo script non esiste; il self-test T9 (assertion gate0) lo richiede.

**Green:** bash 3.2-clean per spec §4.2. Args `<project-root>`. Stampa
`spec_adr_exist=true|false` e `mode=greenfield|brownfield`. Exit 0 sempre (arg errato →
exit 1 con usage). `ls docs/architecture/ADR-*.md` per ADR; `[ -f SPEC.md ]` per SPEC.

**Verify:**
```sh
bash -n ~/.claude/skills/concept-to-code/scripts/gate0-detect.sh
chmod +x ~/.claude/skills/concept-to-code/scripts/gate0-detect.sh
D=$(mktemp -d); bash gate0-detect.sh "$D"            # → spec_adr_exist=false / mode=greenfield
touch "$D/SPEC.md"; mkdir -p "$D/docs/architecture"; touch "$D/docs/architecture/ADR-0001-x.md"
bash gate0-detect.sh "$D"                            # → spec_adr_exist=true / mode=brownfield
rm -rf "$D"
```

- [ ] Step 1: write. Step 2: `bash -n`. Step 3: chmod +x. Step 4: smoke (greenfield +
  brownfield). Step 5: checkpoint.

**Stima:** 20 min.

---

### Task 5: Patch `manifest-init.sh` (schema 1.1 + campi nuovi)

**Files:** Modify `~/.claude/skills/concept-to-code/scripts/manifest-init.sh`.

**Red:** init scrive ancora `manifest_schema_version: "1.0"` e non ha mode/gate0/
artifacts.brainstorm. Self-test T9 (schema 1.1, mode) lo richiede.

**Green:** backup `.bak-2026-05-21-v2`. Modifiche:
- `manifest_schema_version: "1.0"` → `"1.1"`.
- 4° arg opzionale `mode="${4:-greenfield}"` (validare ∈ {greenfield,brownfield}, default
  greenfield).
- Aggiungi riga `mode: "$mode"` dopo `project_root`.
- Aggiungi blocco `gate0:` (decision null, criteria_spec_adr_exist false, decided_at null).
- Aggiungi `brainstorm: null` nell'array `artifacts:` (tra spec e adr).
- L'array `hitl_gates` resta a 4 elementi (invariato — gate 1b non vi è aggiunto).

**Verify:**
```sh
bash -n manifest-init.sh
D=$(mktemp -d); bash manifest-init.sh smoke-v2 "Smoke V2" "$D" brownfield
grep -E '^manifest_schema_version: "1.1"$|^mode: "brownfield"$|^  brainstorm: null$' "$D"/docs/manifests/*.yml
rm -rf "$D"
```
Atteso: 3 match. Default greenfield se il 4° arg manca.

- [ ] Step 1: backup. Step 2: edit. Step 3: `bash -n`. Step 4: smoke. Step 5: checkpoint.

**Stima:** 25 min.

---

### Task 6: Patch `manifest-validate.sh` (1.0|1.1, enum, hitl>=4, mode)

**Files:** Modify `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh`.

**Red:** validate accetta solo `"1.0"` esatto, enum senza gate_1b, hitl `==4`. Self-test
T9 (schema 1.1 accept, retrocompat 1.0, enum gate_1b, mode) lo richiede.

**Green:** backup. Modifiche (spec §2.3):
- Inv.1: `grep -Eq '^manifest_schema_version: "(1\.0|1\.1)"$'`.
- Inv.5: aggiungi `gate_1b_brainstorm_decision` al temp-file `VALID_STEPS`.
- Inv.9: `[ "$gate_count" -lt 4 ]` invece di `!= "4"`.
- Inv. nuova mode: se `grep -q '^mode:'`, valida ∈ {greenfield,brownfield}; se assente,
  skip (retrocompat 1.0).

**Verify:**
```sh
bash -n manifest-validate.sh
# 1.1 fresh init valido; 1.0 legacy valido; current_step gate_1b valido; mode invalido fallisce
```

- [ ] Step 1: backup. Step 2: edit (4 punti). Step 3: `bash -n`. Step 4: smoke (1.1 ok,
  1.0 ok, gate_1b ok, mode=xxx fail). Step 5: checkpoint.

**Stima:** 30 min.

---

### Task 7: Patch `manifest-transition.sh` (+2 pair)

**Files:** Modify `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh`.

**Red:** la transition table ha 16 pair; `gate_1_spec_review,gate_1b_brainstorm_decision`
e `gate_1b_brainstorm_decision,step_2_architecture` sono illegali. Self-test T9 le
richiede legali.

**Green:** backup. Aggiungi al blocco PAIRS (temp-file) le 2 righe:
```sh
echo "gate_1_spec_review,gate_1b_brainstorm_decision" >> "$PAIRS"
echo "gate_1b_brainstorm_decision,step_2_architecture" >> "$PAIRS"
```
NON rimuovere `gate_1_spec_review,step_2_architecture` (retrocompat — preservata).

**Verify:**
```sh
bash -n manifest-transition.sh
# init → 0→1→g1; poi g1→g1b legale (exit 0); g1b→2 legale (exit 0); g1→2 ancora legale
```

- [ ] Step 1: backup. Step 2: edit. Step 3: `bash -n`. Step 4: smoke. Step 5: checkpoint.

**Stima:** 15 min.

---

### Task 8: Patch `concept-to-code/SKILL.md` (Gate 0 + brownfield + gate 1b)

**Files:** Modify `~/.claude/skills/concept-to-code/SKILL.md`.

**Red:** SKILL.md non documenta Gate 0, brownfield, gate 1b; schema linea dice 1.0.

**Green:** backup. Modifiche (spec §4-6):
- Linea schema: `manifest_schema_version: "1.1"`.
- Sez. 1: aggiungi nota Gate 0 (triage chain-vs-leggero).
- Sez. 2 (Invocation contract Form A): inserisci passo Gate 0 (esegui gate0-detect,
  mostra box se criterio attivo, decisione utente `[c]/[l]/[a]`).
- Sez. 3 (State machine): aggiorna enum (+gate_1b), diagram, transizioni (+2 pair,
  path diretto preservato).
- Sez. 4 Step 1: branch greenfield/brownfield (brownfield = no interview, spec
  pre-esistente, Gate 1 nota "spec pre-esistente").
- Sez. 4 Step 2 dispatch architect: riga condizionale `if BRAINSTORM.md exists, read it`.
- Sez. 4 Step 3: direttiva additiva su CLAUDE.md esistente (mai degradare).
- Sez. 5: aggiungi Gate 0 box e Gate 1b box; aggiorna Gate 1 per brownfield.
- Sez. 6 coexistence: aggiungi `design-brainstorm` (invocata al gate 1b, scrive solo
  BRAINSTORM.md).

NB: l'anchor del review-triage-fix harness su `manifest_schema_version` (literal) resta
soddisfatto (la stringa compare ancora nel body). Verificare che NON scenda.

**Verify:**
```sh
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo exit=$?   # → PASS=51 FAIL=0
grep -c 'gate_1b_brainstorm_decision\|Gate 0\|brownfield\|design-brainstorm' SKILL.md   # >0
```

- [ ] Step 1: backup. Step 2: edit (8 punti). Step 3: review-triage-fix harness PASS=51.
  Step 4: checkpoint.

**Stima:** 45 min.

---

### Task 9: Extend self-test `concept-to-code/tests/run-tests.sh` (+7 assertion, PASS=20) + smoke g1b

**Files:** Modify `~/.claude/skills/concept-to-code/tests/run-tests.sh` e
`~/.claude/skills/concept-to-code/tests/smoke-e2e.sh`.

**Red:** self-test = PASS=13; le 7 nuove assertion (schema 1.1, retrocompat 1.0, g1→g1b,
g1b→2, enum gate_1b, mode brownfield, gate0-detect) non esistono. smoke-e2e non copre g1b.

**Green:** backup di entrambi i file. Append (anchor-preserving, TRA assertion 12 e
assertion 13 smoke-e2e — oppure dopo la 13, mantenendo la 13 come ultima logica) 7
assertion nuove:
14. init scrive schema 1.1 (`grep -q '^manifest_schema_version: "1.1"$'`).
15. validate accetta un manifest 1.0 legacy hand-crafted (retrocompat).
16. transition `gate_1_spec_review → gate_1b_brainstorm_decision` legale (exit 0).
17. transition `gate_1b_brainstorm_decision → step_2_architecture` legale (exit 0).
18. validate accetta `current_step: gate_1b_brainstorm_decision`.
19. validate rifiuta `mode: "bogus"` (exit !=0).
20. `gate0-detect.sh` su dir con SPEC.md+ADR stampa `spec_adr_exist=true` e
   `mode=brownfield`.

Aggiorna la summary attesa a `PASS=20`. Nello smoke-e2e: aggiungi una mini-fase
"brainstorm path" che esegue `g1 → g1b → 2` su un manifest fresco e verifica current_step.

**Verify:**
```sh
bash ~/.claude/skills/concept-to-code/tests/run-tests.sh; echo exit=$?   # → PASS=20 FAIL=0
bash ~/.claude/skills/concept-to-code/tests/smoke-e2e.sh; echo exit=$?   # → SMOKE=PASS
```

- [ ] Step 1: backup. Step 2: append 7 assertion + smoke fase. Step 3: `bash -n` su
  entrambi. Step 4: run → PASS=20, SMOKE=PASS. Step 5: checkpoint.

**Stima:** 40 min.

---

### Task 10: Risk check su `vibe-status` + full harness suite

**Files:** nessun edit pianificato (read-only check; edit SOLO se vibe-status rompe).

**Red/check:** `vibe-status` legge i manifest. Verifica che tolleri schema 1.1 e lo stato
`gate_1b_brainstorm_decision`.
```sh
grep -n 'current_step\|step_\|gate_\|1\.0\|schema' ~/.claude/skills/vibe-status/SKILL.md ~/.claude/skills/vibe-status/scripts/*.sh 2>/dev/null
bash ~/.claude/skills/vibe-status/tests/run-tests.sh; echo exit=$?
```
Se vibe-status enumera gli stati validi (whitelist) e omette gate_1b → estendere l'enum
(edit minimo + anchor-preserving sul suo harness PASS=10). Se invece è agnostico
(stampa qualunque current_step) → nessun edit. **Decisione registrata nel checkpoint.**

**Verify (full suite):**
```sh
bash ~/.claude/skills/design-brainstorm/tests/run-tests.sh | tail -1   # PASS=8
bash ~/.claude/skills/concept-to-code/tests/run-tests.sh | tail -1     # PASS=20
bash ~/.claude/skills/concept-to-code/tests/smoke-e2e.sh | tail -1     # SMOKE=PASS
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh | tail -1   # PASS=51
bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh | tail -1   # PASS=18 (invariato)
bash ~/.claude/skills/vibe-status/tests/run-tests.sh | tail -1         # PASS=10 (invariato o esteso)
```

- [ ] Step 1: vibe-status read-only check. Step 2: decisione (edit o no). Step 3: full
  suite verde. Step 4: checkpoint.

**Stima:** 25 min.

---

### Task 11: Status sync ADR/spec + memory + MEMORY.md index

**Files:**
- Modify `docs/architecture/ADR-0008-concept-to-code-workflow-v2-brainstorm.md` (status).
- Modify i 2 spec (`2026-05-21-concept-to-code-workflow-v2-design.md`,
  `2026-05-21-design-brainstorm-skill-design.md`) (status → implementato).
- Create `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_concept-to-code-workflow-v2.md`.
- Modify `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`.

**Green:**
- ADR-0008 status: `Proposed` → `Accepted — 2026-05-21 (implemented via plan
  2026-05-21-concept-to-code-workflow-v2.md; design-brainstorm PASS=8; concept-to-code
  self-test PASS=20; review-triage-fix PASS=51; smoke-e2e PASS)`.
- Spec status → `implementato — 2026-05-21`.
- Memory entry: link ADR-0008 + 2 spec + plan; file deployati; harness delta; invarianti
  (schema 1.1 retrocompat, design-brainstorm no disable-model-invocation, coexistence
  ortogonale, brownfield additivo su CLAUDE.md).
- MEMORY.md: riga in `## Project` con prefix `**DEPLOYED 2026-05-21**`.

**Verify:** `head -5` su ADR + 2 spec; `grep -c 'workflow-v2' MEMORY.md` → 1.

- [ ] Step 1: ADR status. Step 2: 2 spec status. Step 3: memory entry. Step 4: MEMORY.md.
  Step 5: verify. Step 6: final checkpoint (tutti gli 11 task chiusi).

**Stima:** 15 min.

---

## Summary

**Totale task:** 11 (1 red anchor + 2 skill design-brainstorm + 4 helper/script chain +
1 SKILL.md + 1 self-test+smoke + 1 risk-check + 1 status/memory sync).

**Totale tempo stimato:** 5+50+25+20+25+30+15+45+40+25+15 = **295 min ≈ 4h 55min**.

**Harness expected delta (riassunto):**
- `design-brainstorm` (nuovo): PASS=0 → **PASS=8**.
- `concept-to-code` self-test: PASS=13 → **PASS=20** (+7).
- `concept-to-code` smoke-e2e: SMOKE=PASS → **SMOKE=PASS** (+1 fase g1b).
- `review-triage-fix`: PASS=49 → **PASS=51** (+2 anchor).
- `refactor-snapshot` PASS=18 / `vibe-status` PASS=10 / `pre-flight-pattern-enforce`
  PASS=10 / `run-hook-tests` PASS=24: **invariati** (vibe-status possibile +N se enum
  esteso, anchor-preserving — vedi T10).

**Coexistenza HARD verificata:**
- 16 transition pair v1 preservate; path diretto `g1→2` non rimosso → smoke-e2e v1 passa.
- Manifest rempay 1.0 completati restano validi (validate accetta 1.0 OR 1.1).
- Agent, hook, settings, MCP, rules non toccati. `interview-driver`,
  `claude-md-generator`, `review-triage-fix/SKILL.md`, `refactor-snapshot` non toccati
  (direttiva additiva CLAUDE.md veicolata nel prompt template del chain).
- `design-brainstorm` senza `disable-model-invocation` (invocabile dal chain).

**Deliverable operativi finali:**
1. `~/.claude/skills/design-brainstorm/SKILL.md` (new)
2. `~/.claude/skills/design-brainstorm/tests/run-tests.sh` (new)
3. `~/.claude/skills/concept-to-code/scripts/gate0-detect.sh` (new)
4. `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` (modify)
5. `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` (modify)
6. `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` (modify)
7. `~/.claude/skills/concept-to-code/SKILL.md` (modify)
8. `~/.claude/skills/concept-to-code/tests/run-tests.sh` (modify)
9. `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` (modify)
10. `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (modify: +2 anchor)
11. memory entry + MEMORY.md (modify)

+ doc status updates nel repo blueprint (ADR-0008 + 2 spec).
