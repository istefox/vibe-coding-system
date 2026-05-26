# review-triage-fix v1.2 — Add+Remove micro-piano rule — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** patchare `review-triage-fix` SKILL.md Step 2 con un nuovo paragrafo "Add+Remove rule" che istruisce esplicitamente il `coder` plan-driven a enumerare sia `Add:` che `Remove:` per i fix di sostituzione (replace pattern A with pattern B). Chiude la causa-radice del MAJOR M-1 osservato nel cycle 2 di `pricing-markup-cli` (2026-05-19), dove il `coder` ha aggiunto un autouse fixture senza rimuovere il duplicato preesistente perché il micro-piano era formulato solo-additivo.

**Architecture:** prose-only additive patch. Singolo paragrafo bullet appended subito DOPO il bullet esistente "Micro-piano discipline" in SKILL.md Step 2. Anchor-preserving: i 17 `g`-anchor del harness Task 5 restano intatti; ne aggiungo 1 (`Add+Remove rule`). Cumulative harness PASS sale da 40 → 41. Nessun nuovo file, nessuno script toccato, nessun hook/agent/MCP/settings modificato. Disciplina TDD red→green sui due step testabili (T1 harness anchor failing → T2 SKILL.md paragraph green), poi sync deliverable doc (plan/spec/memory) come blocchi documentali coerenti.

**Tech Stack:** markdown (SKILL.md, plan, spec, memory), bash 3.2.57 (harness — la nuova assertion usa `grep -q -- "$1"` esattamente come le 17 esistenti, quindi 3.2-clean by construction).

**Spec:** `docs/superpowers/specs/2026-05-20-review-triage-fix-v1.2-addremove-design.md` (approvato 2026-05-20).

---

## Environment notes (read first)

- **No git in `~/.claude/` né in questo repo vibe-coding-system.** Checkpoint per task = harness verde + TodoWrite update + report. Nessun commit. Nessun HITL gate: la patch è additiva su prose+1-anchor, non tocca hook live, settings.json, agenti, MCP. Tutto inert finché un'invocazione organica di `review-triage-fix` non incontra un fix di sostituzione (validazione operativa pending uso reale, design §6).
- **Bash 3.2 cleanliness.** La nuova structural assertion nell'harness usa `g 'Add+Remove rule' 'add+remove substitution rule'` → si appoggia alla funzione `g()` già definita (`grep -q -- "$1" "$M"`). Nessuna nuova dipendenza, nessun assoc array, nessun `mapfile`/`${v^^}`. Provato 3.2-clean by inheritance (le 17 esistenti girano da Task 5 del piano v1.0).
- **Anchor preservation.** Nessuno dei 17 `g`-anchor v1.0/v1.1 (verify.sh, weakening-scan.sh, triage-state.sh, debugger, refactorer, coder, micro-piano, REPORT-ONLY, CIRCUIT BREAKER A/B/C/D, NESSUN COMMIT, STOP, sub-agent, sequenzial, .triage-fix-last.json) viene rimosso o alterato. Il paragrafo nuovo aggiunge solo testo dopo il bullet "Micro-piano discipline" già esistente (~righe 63-67 della deployed SKILL.md), preservando l'anchor `micro-piano`.
- **Harness count baseline (verificato 2026-05-20):** `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh` riporta `PASS=40 FAIL=0`. Suddivisione: verify ×7 + weakening ×6 + state-diff ×4 + state-commit ×4 + SKILL.md ×19 (= 17 `g`-anchor + 1 frontmatter-name + 1 description). Adding 1 `g`-anchor porta SKILL.md ×20 → cumulative `PASS=41 FAIL=0`.
- **No backup necessario.** SKILL.md è additive-only patch (no overwrite di prose esistente); plan/spec/memory sono già artefatti repo doc (la storia è ricostruibile da context, e dato che il vibe-coding-system repo non ha git, "backup" sarebbe inutile cp). Se servisse un revert, è una rimozione di ~10 righe dal SKILL.md deployed.
- **Portability.** Il deliverable plan (questo file) e il deliverable spec sono nel repo doc `vibe-coding-system`. L'edit operativo è solo su `~/.claude/skills/review-triage-fix/SKILL.md` + `~/.claude/skills/review-triage-fix/tests/run-tests.sh`. Memory in `~/.claude/projects/.../memory/`.

## File structure

Tutti i path live (`~/.claude/` per skill + harness; `~/.claude/projects/.../memory/` per memory; questo repo doc per plan+spec).

- Modify `~/.claude/skills/review-triage-fix/SKILL.md` — append paragrafo "Add+Remove rule" dopo il bullet "Micro-piano discipline" in Step 2 (Triage).
- Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — append 1 `g`-anchor `'Add+Remove rule'` al blocco `# --- Task 5: SKILL.md structural completeness ---`, immediatamente prima della summary line `echo "----"`.
- Modify `docs/superpowers/plans/2026-05-19-review-triage-fix.md` — sync embedded SKILL.md block (Task 5 Step 3) col nuovo paragrafo; sync embedded harness Task-5 block col nuovo anchor; aggiorna 3 occorrenze `PASS=40` → `PASS=41` (righe 27, 727, 741); aggiungi sezione "v1.2 (2026-05-20)" nel changelog dopo "v1.1 (2026-05-19, post-pilot)" attuale (riga 13).
- Modify `docs/superpowers/specs/2026-05-19-review-triage-fix-design.md:4` — status line: `… v1.1 (post-pilot parziale 2026-05-19) — piano …` → `… v1.1 → v1.2 (2026-05-20 Add+Remove rule) — piano …`.
- Modify `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/feedback_micropiano-refactor-cleanup.md` — marca RESOLVED 2026-05-20, prepend "**RESOLVED 2026-05-20**" alla description frontmatter, append nota chiusura corpo con riferimento a spec/plan/SKILL.md Step 2.
- Modify `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` — riga `[micro-piano refactor cleanup]` aggiornata con prefisso `**RESOLVED 2026-05-20**:`.

Unchanged: helper scripts (verify.sh, weakening-scan.sh, triage-state.sh) — intatti, contratti immutati. Tutti gli altri agenti (coder.md, reviewer.md, debugger.md, refactorer.md) e hook/settings — non toccati (Non-goal spec §2).

---

### Task 1: Harness anchor failing (red)

**Files:**
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (append 1 `g` call al blocco Task 5, immediately before the `echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"` summary line)

- [ ] **Step 1: Write the failing test** — il blocco Task 5 attuale termina con `g '.triage-fix-last.json'    'cross-cycle state file'` (~riga 143). Insert SUBITO DOPO quella riga, e PRIMA della summary line:

```bash
g 'Add+Remove rule'          'add+remove substitution rule'
```

Notes:
- Niente altro va modificato nell'harness. La funzione `g()` (definita ~riga 123) gestisce il grep+ok/bad.
- Match string è il literal `Add+Remove rule` — coincide con il bold leading del paragrafo da aggiungere in Task 2 (`**Add+Remove rule (for SUBSTITUTION fixes):**`). `grep -q` matcha il sottostringa, non richiede word-boundary.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: Task 1-4 + i primi 19 anchor Task 5 ancora `PASS`; la nuova check `SKILL.md missing: add+remove substitution rule` `FAIL` (paragrafo non ancora in SKILL.md); summary `PASS=40 FAIL=1`, non-zero exit.

- [ ] **Step 3: Checkpoint** — failing test in place, baseline rossa confermata; TodoWrite update.

---

### Task 2: SKILL.md paragraph (green)

**Files:**
- Modify: `~/.claude/skills/review-triage-fix/SKILL.md` (append paragrafo dopo il bullet "Micro-piano discipline" in Step 2)

- [ ] **Step 1: Write the minimal implementation** — il bullet attuale "Micro-piano discipline" in Step 2 (`~/.claude/skills/review-triage-fix/SKILL.md` ~righe 63-67) termina con la frase "...40k+ tokens for a small change is a smell, observed in the v1 pilot)." Insert SUBITO DOPO (riga vuota di separazione + nuovo paragrafo bullet), e PRIMA del paragrafo "Then compute cross-cycle status." (~riga 69):

```markdown

**Add+Remove rule (for SUBSTITUTION fixes):** when the fix replaces a pattern
rather than just adding (e.g. move local import to top-level, extract magic
number to a named constant, consolidate duplicate fixtures, rename a helper),
the micro-piano MUST list BOTH the new pattern (`Add: ...`) AND the old
instances to delete (`Remove: <path:line> ...`). Without an explicit Remove,
the coder typically acts conservatively and leaves the old pattern in place →
duplication that the re-review then flags as a new finding (observed cycle 2
2026-05-20, M-3 autouse fixture → M-1 re-review). For purely ADDITIVE fixes
(missing input validation, new edge-case test, docstring fix), `Add:` alone
suffices — no Remove section needed.
```

Notes:
- Wording dalla spec §4 verbatim (con line-wrap a ~72 char come lo stile delle altre prose blocks della SKILL.md, riga 73-83 della spec).
- Il leading `**Add+Remove rule (for SUBSTITUTION fixes):**` fornisce il literal "Add+Remove rule" che il `g`-anchor cerca.
- Posizione: il paragrafo nuovo va DOPO "Micro-piano discipline" (rifinitura del sotto-caso substitution) e PRIMA del paragrafo "Then compute cross-cycle status..." (che chiude Step 2 con la transizione a `triage-state.sh diff`). Non spostare altro testo.
- Style consistency: paragraph bullet con titolo bold, frase spiegativa concreta, esempi inline tra parentesi, riferimento forensic (`observed cycle 2 2026-05-20`) come il bullet "Micro-piano discipline" precedente (`observed in the v1 pilot`).
- Non rimuovere né modificare il bullet "Micro-piano discipline" preesistente — la regola Add+Remove lo rifinisce, non lo sostituisce.

- [ ] **Step 2: Run test to verify it passes**

Run: `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`
Expected: tutti i 41 anchor `PASS`, inclusa `SKILL.md: add+remove substitution rule`; summary `PASS=41 FAIL=0`, exit 0.

- [ ] **Step 3: Checkpoint** — SKILL.md operativa patchata e green; TodoWrite update. La skill è live-effective al prossimo invoke organico (qualunque triage Step 2 che identifichi un substitution fix vedrà la nuova regola).

---

### Task 3: Plan deliverable sync

**Files:**
- Modify: `docs/superpowers/plans/2026-05-19-review-triage-fix.md`

Niente test deterministico applicabile (sync di doc): verifica via grep/diff inline.

- [ ] **Step 1: Update embedded harness block (Task 5 Step 1)** — nel plan v1.0, il blocco bash embedded di Task 5 Step 1 (righe ~499-523) contiene la sequenza dei `g`-anchor che mirror l'harness reale. Insert subito dopo `g '.triage-fix-last.json'    'cross-cycle state file'` (~riga 522), e PRIMA della chiusura ``` `` ```:

```
g 'Add+Remove rule'          'add+remove substitution rule'
```

Stesso line dell'edit harness reale di Task 1 — questo blocco embedded è la copia documentale per chi rilegge il piano v1.0.

- [ ] **Step 2: Update embedded SKILL.md block (Task 5 Step 3)** — nel plan v1.0, il blocco markdown embedded di Task 5 Step 3 (righe ~532-722) contiene il body completo di SKILL.md. Localizza il bullet "Micro-piano discipline" embedded (~righe 595-599) e append il nuovo paragrafo "Add+Remove rule" subito dopo, identico al testo di Task 2 Step 1 (verbatim, 11 righe wrap a ~72 char). Posizione: prima del paragrafo "Then compute cross-cycle status" embedded (~riga 601).

- [ ] **Step 3: Update PASS=40 → PASS=41 (3 occorrenze)** — sostituisci in `docs/superpowers/plans/2026-05-19-review-triage-fix.md`:
  - Riga 27: `Helper scripts and harness unchanged (40/40 PASS preserved — anchors intact).` → `Helper scripts and harness unchanged through v1.1 (40/40 PASS preserved); v1.2 patch adds 1 anchor → 41/41 PASS (see "v1.2" section below).`
  - Riga 727 (Task 5 Step 4 Expected): `cumulative PASS=40 FAIL=0 (verify 7 + weakening 6 + state-diff 4 + state-commit 4 + SKILL.md 19), exit 0.` → `cumulative PASS=40 FAIL=0 (verify 7 + weakening 6 + state-diff 4 + state-commit 4 + SKILL.md 19), exit 0. (v1.2 patch: PASS=41 with 1 added anchor "Add+Remove rule" — SKILL.md ×20.)`
  - Riga 741 (Task 6 Step 1 Expected): `Expected: final PASS=40 FAIL=0, exit 0 (Task 1 verify ×7, Task 2 weakening ×6, Task 3 state-diff ×4, Task 4 state-commit ×4, Task 5 SKILL.md ×19).` → `Expected: final PASS=40 FAIL=0 (v1.1) or PASS=41 FAIL=0 (v1.2), exit 0 (Task 1 verify ×7, Task 2 weakening ×6, Task 3 state-diff ×4, Task 4 state-commit ×4, Task 5 SKILL.md ×19 [v1.1] / ×20 [v1.2]).`

- [ ] **Step 4: Add v1.2 changelog section** — il plan v1.0 ha una sezione "v1.1 (2026-05-19, post-pilot)" alla riga 13 che descrive le 4 modifiche post-pilot. SUBITO DOPO quella sezione (cioè dopo la riga 27 `Helper scripts and harness unchanged (40/40 PASS preserved — anchors intact).` originale, ora modificata in Step 3), insert blocco:

```markdown

**v1.2 (2026-05-20, Add+Remove rule):** SKILL.md patched in Step 2 to add an
explicit "Add+Remove rule (for SUBSTITUTION fixes)" paragraph after the
"Micro-piano discipline" bullet. Root cause of the M-1 MAJOR observed in
`pricing-markup-cli` cycle 2 (2026-05-19): the M-3 fix asked the coder to
"add an autouse fixture" without explicitly listing the existing duplicate
fixture to remove → coder acted only-additively → re-review flagged the
duplication. The new rule mandates `Add:` AND `Remove: <path:line>` lists
for substitution fixes (replace pattern A with pattern B); purely additive
fixes still need only `Add:`. Harness +1 anchor (`Add+Remove rule`),
cumulative PASS=41. No helper script touched. Spec:
`docs/superpowers/specs/2026-05-20-review-triage-fix-v1.2-addremove-design.md`.
Memory: `feedback_micropiano-refactor-cleanup.md` (now RESOLVED).
```

- [ ] **Step 5: Verify deliverable sync** — `grep -n 'PASS=40\|PASS=41\|Add+Remove\|v1.2' docs/superpowers/plans/2026-05-19-review-triage-fix.md`. Expected: zero `PASS=40` orphan refs (tutte ora hanno il companion `PASS=41`/`v1.2`); 3+ `Add+Remove rule` hits (changelog + embedded harness + embedded SKILL.md body); 4+ `v1.2` hits.

- [ ] **Step 6: Checkpoint** — plan v1.0 deliverable in sync con v1.2 live; TodoWrite update.

---

### Task 4: Spec status line + memory sync

**Files:**
- Modify: `docs/superpowers/specs/2026-05-19-review-triage-fix-design.md:4`
- Modify: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/feedback_micropiano-refactor-cleanup.md`
- Modify: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`

- [ ] **Step 1: Update spec v1.0 status line** — `docs/superpowers/specs/2026-05-19-review-triage-fix-design.md` linea 4 attuale:

```
**Stato:** approvato → implementato → v1.1 (post-pilot parziale 2026-05-19) — piano `docs/superpowers/plans/2026-05-19-review-triage-fix.md` (sezione "v1.1"); helper unit-test verdi 40/40 invariati; pilota organico v1.1 pending (Stefano-run)
```

→

```
**Stato:** approvato → implementato → v1.1 (post-pilot parziale 2026-05-19) → v1.2 (2026-05-20 Add+Remove rule) — piano `docs/superpowers/plans/2026-05-19-review-triage-fix.md` (sezione "v1.2"); spec v1.2 `docs/superpowers/specs/2026-05-20-review-triage-fix-v1.2-addremove-design.md`; harness 41/41; pilota organico v1.1+v1.2 pending (Stefano-run)
```

- [ ] **Step 2: Update memory `feedback_micropiano-refactor-cleanup.md`** — patch frontmatter `description:` aggiungendo prefisso `**RESOLVED 2026-05-20**:` mantenendo il resto invariato. Poi append in fondo al corpo (dopo l'ultima frase "Possibile patch v1.2 a SKILL.md Step 2 dopo il bullet 'Micro-piano discipline'."):

```markdown

**RESOLVED 2026-05-20.** Patch v1.2 applicata: `~/.claude/skills/review-triage-fix/SKILL.md`
Step 2 ora include il paragrafo "Add+Remove rule (for SUBSTITUTION fixes)"
dopo il bullet "Micro-piano discipline". Spec:
`docs/superpowers/specs/2026-05-20-review-triage-fix-v1.2-addremove-design.md`.
Piano: `docs/superpowers/plans/2026-05-20-review-triage-fix-v1.2-addremove.md`.
Harness +1 anchor, cumulative PASS=41/0. Validazione operativa pending: il
prossimo ciclo organico che incontri un substitution fix confermerà che il
`coder` segue la regola Add+Remove se l'orchestratore la include nel micro-piano.
```

- [ ] **Step 3: Update MEMORY.md index riga** — `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` riga 12 attuale:

```
- [micro-piano refactor cleanup](feedback_micropiano-refactor-cleanup.md) — micro-piano di review-triage-fix per refactor che SOSTITUISCE un pattern deve esplicitare "Add" e "Remove", altrimenti il coder lascia duplicazioni (osservato cycle 2 pricing-markup-cli, MAJOR autouse duplicata)
```

→

```
- [micro-piano refactor cleanup](feedback_micropiano-refactor-cleanup.md) — **RESOLVED 2026-05-20**: patch v1.2 a SKILL.md Step 2 con paragrafo "Add+Remove rule"; harness 41/41; validazione operativa pending uso reale
```

- [ ] **Step 4: Verify doc sync** — `grep -n 'v1.2\|RESOLVED 2026-05-20\|Add+Remove' docs/superpowers/specs/2026-05-19-review-triage-fix-design.md ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/feedback_micropiano-refactor-cleanup.md ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`. Expected: spec linea 4 ha "v1.2 (2026-05-20 Add+Remove rule)"; feedback memory ha `**RESOLVED 2026-05-20**` sia in description sia in body; MEMORY.md riga 12 prefissata `**RESOLVED 2026-05-20**`.

- [ ] **Step 5: Checkpoint** — spec status + 2 memory file in sync con SKILL.md live; TodoWrite update.

---

### Task 5: Final verification & self-review

**Files:** none (read-only verification).

- [ ] **Step 1: Full harness run (final)** — `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`. Expected: `PASS=41 FAIL=0`, exit 0. Verifica che la riga `PASS: SKILL.md: add+remove substitution rule` appaia tra le ultime 5-6 righe di output. Tutti i 17 anchor v1.0/v1.1 precedenti (verify.sh, weakening-scan.sh, triage-state.sh, debugger, refactorer, coder, micro-piano, REPORT-ONLY, breakers A/B/C/D, NESSUN COMMIT, STOP, sub-agent, sequenzial, .triage-fix-last.json) restano PASS.

- [ ] **Step 2: SKILL.md anchor scan (structural)** — `grep -c 'Add+Remove rule\|SUBSTITUTION\|Remove:' ~/.claude/skills/review-triage-fix/SKILL.md`. Expected: ≥3 (titolo bold + esempi `Remove:` inline + nota `SUBSTITUTION` nel titolo). Conferma posizionamento: `grep -n 'Micro-piano discipline\|Add+Remove rule\|Then compute cross-cycle' ~/.claude/skills/review-triage-fix/SKILL.md` deve riportare le 3 occorrenze in ordine crescente (Micro-piano discipline < Add+Remove rule < Then compute).

- [ ] **Step 3: Spec coverage check (self, inline)** — verifica spec→delivery mapping:
  - Spec §2 Goal: "rendere esplicito Add+Remove" → SKILL.md Step 2 nuovo paragrafo. ✔
  - Spec §3 Architettura: "singolo paragrafo dopo Micro-piano discipline" → posizione confermata Task 2 Step 1 + Task 5 Step 2. ✔
  - Spec §4 modifiche puntuali: SKILL.md ✔ (Task 2); harness +1 `g` ✔ (Task 1); plan sync ✔ (Task 3); spec status ✔ (Task 4 Step 1); memory ✔ (Task 4 Steps 2-3). ✔
  - Spec §5 deploy strategy: edit diretti, no HITL gate, no backup. ✔
  - Spec §6 testing: structural assertion harness coverage + nota non-deterministic validation. ✔
  - Spec §7 vincoli & invarianti: anchor preservation (17→18), style consistency (paragraph bullet bold + esempi inline + forensic ref), no behavior change altri Steps, backward compat. ✔
  - Spec §8 out of scope: B2 parallel mode, coder.md, auto-detect, altre skill — nessuna toccata. ✔

- [ ] **Step 4: Placeholder scan** — `grep -nE 'TODO|TBD|FIXME|XXX|<.*>' ~/.claude/skills/review-triage-fix/SKILL.md | grep -v '^.*<path:line>' | grep -v '^.*<root>' | grep -v '^.*<cmd>' | grep -v '^.*<test dirs>' | grep -v '^.*<live test files>' | grep -v '^.*<reason>' | grep -v '^.*<file>' | grep -v '^.*<finding>' | grep -v '^.*<TAB>' | grep -v '^.*<name>' | grep -v '^.*<N+1>'`. Expected: nessun hit (i `<...>` legittimi sono placeholder didattici già presenti pre-v1.2, esclusi dal filtro). Il nuovo paragrafo introduce solo il placeholder didattico `<path:line>` (già nella whitelist filtri).

- [ ] **Step 5: Final report** — riassumi: SKILL.md patched, harness 41/41, plan/spec/memory in sync. Note: validazione operativa della regola (LLM-mediated) pending uso organico (design §6 §9). Confidence finale alta (patch additiva, anchor-preserving, test-positive).

- [ ] **Step 6: Checkpoint** — v1.2 live-effective, deliverable doc allineata, harness verde. TodoWrite update finale.

---

## Out of scope (echoed from spec §8)

- B2 parallel batch mode — richiede `isolation: worktree` upstream in `~/.claude/agents/coder.md`, scope separato.
- Modifiche a `coder.md` — la responsabilità di formulazione del micro-piano è dell'orchestratore (SKILL.md), non del `coder`.
- Automatic detection "substitution vs additive" — resta giudizio LLM al triage Step 2.
- Aggiornamento di altre skill (`adr-writer`, `code-review-checklist`, etc.) — non toccate.
- Validazione end-to-end operativa — defer al prossimo ciclo organico di `review-triage-fix` su un repo con substitution fix reali (design §6, non bloccante).
