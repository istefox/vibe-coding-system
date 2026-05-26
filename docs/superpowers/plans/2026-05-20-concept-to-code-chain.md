# `concept-to-code` skill orchestratore — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Changelog:**
- v1.0 (2026-05-20): initial — TDD plan derivato da `ADR-0003-concept-to-code-chain.md`
  e dallo spec `2026-05-20-concept-to-code-chain-design.md`. 9 task: 1 red harness
  anchor + 5 green (skill SKILL.md + 3 bash helper + self-test) + 3 sync (ADR/spec
  status + project memory + MEMORY.md index).

**Goal:** deployare lo skill `~/.claude/skills/concept-to-code/` (SKILL.md +
3 bash helper 3.2-clean + self-test harness 10 assertion) per orchestrare il
chain concept→code (blueprint sez. 11) come state machine deterministica con
manifest YAML persistente cross-session, HITL gates espliciti, riuso di
`interview-driver` + `claude-md-generator`, e coexistenza ortogonale con
ADR-0001 (coder pre-flight) + ADR-0002 (refactor snapshot) + review-triage-fix
v1.2. Aggiungere 2 anchor structural al harness `review-triage-fix/tests/run-tests.sh`
(PASS=45 → PASS=47).

**Architecture:** skill nuova additiva in `~/.claude/skills/concept-to-code/` (no
overwrite di skill esistenti, no edit a `architect.md`/`coder.md`/`reviewer.md`/
`refactorer.md`). Append-only su harness review-triage-fix (no anchor rimossi).
Tutti gli script bash 3.2-clean by construction (memory `feedback_bash32-constraint.md`).
Coexistenza ortogonale con ADR-0001 + ADR-0002 + v1.2: nessun edit a `coder.md`,
`reviewer.md`, `refactorer.md`, `review-triage-fix/SKILL.md`, hook, settings.json,
MCP, `.claude/rules/`.

**Tech Stack:** markdown (SKILL.md, system prompt template, plan, spec, memory),
bash 3.2.57 (3 helper script + 1 self-test harness + 1 anchor block — 3.2-clean
by construction, identico stile dei 45 anchor target del review-triage-fix harness
e degli 11 anchor del refactor-snapshot self-test).

**Spec:** `docs/superpowers/specs/2026-05-20-concept-to-code-chain-design.md`
(Proposed 2026-05-20).
**ADR:** `docs/architecture/ADR-0003-concept-to-code-chain.md` (Proposed 2026-05-20).

---

## Environment notes (read first)

- **No git in `~/.claude/` né nel repo blueprint `vibe-coding-system`.**
  Checkpoint per task = harness verde + TodoWrite update + report. Nessun
  commit. Nessun HITL gate complesso: il deploy è additivo (nuova skill +
  2 anchor append in harness esistente + deliverable doc), non tocca hook
  live, settings.json, MCP, helper script di altre skill, agent system
  prompt esistenti. Tutto inert finché l'utente non invoca
  `/skill concept-to-code <topic>`.
- **Bash 3.2 cleanliness.** Tutti gli script in
  `~/.claude/skills/concept-to-code/scripts/` + il nuovo blocco anchor in
  `review-triage-fix/tests/run-tests.sh` usano solo `grep -q -- "..."`,
  `[ -f "$x" ]`, `[ "$a" = "$b" ]`, `command -v`, `mktemp`, `mv`, `sed
  's/.../.../g'`, `tr -cs 'a-z0-9' '-'`, `date`, helpers `ok`/`bad` (style
  identico a `verify.sh`/`weakening-scan.sh`/`triage-state.sh` di
  review-triage-fix e a `capture.sh`/`diff.sh` di refactor-snapshot).
  Nessun assoc array, nessun `mapfile`, nessun `${v^^}`, nessun `<()`
  process substitution, nessun here-string. Per ragioni memory
  `feedback_bash32-constraint.md`. Verifica per ogni script con `bash -n
  <script.sh>` pre-merge.
- **Anchor preservation.** Nessuno dei 45 anchor post ADR-0002 viene
  rimosso o alterato. Il nuovo blocco Task 8 è appended TRA il blocco
  Task 7 (refactorer.md, ultimi 2 anchor alle righe ~150-151 attuali) e
  la summary line (`echo "----"`, riga ~153). I 45 anchor restano nelle
  stesse righe.
- **Harness count baseline (verificato 2026-05-20 con
  `bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh`):** `PASS=45
  FAIL=0`. Suddivisione: verify ×7 + weakening ×6 + state-diff ×4 +
  state-commit ×4 + SKILL.md ×20 + coder.md ×2 + refactorer.md ×2. Adding
  2 new anchor (Task 8 concept-to-code/SKILL.md) porta cumulative a
  `PASS=47 FAIL=0`.
- **Skill self-test target:** lo skill `concept-to-code` ha proprio
  self-test harness in `tests/run-tests.sh`. Target `PASS=10 FAIL=0` (10
  assertion: manifest schema validation, state transitions, override
  safe-to-restart, contract invariants — vedi spec §9.4).
- **Backup raccomandato pre-edit:** `cp
  ~/.claude/skills/review-triage-fix/tests/run-tests.sh
  ~/.claude/skills/review-triage-fix/tests/run-tests.sh.bak-2026-05-20-c2c`.
  Backup è raccomandato non opzionale per consistency con plan ADR-0001 +
  ADR-0002.
- **Portability.** Edit operativi su `~/.claude/skills/concept-to-code/`
  (nuova) + `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (1
  blocco append). Deliverable doc (questo plan, ADR-0003, spec, memory
  update) nel repo `vibe-coding-system` + `~/.claude/projects/.../memory/`.
  Nessun MCP, hook, settings.json, agent system prompt toccato.
- **Coexistenza HARD (ortogonalità):** ADR-0001 sezione `## Pre-flight
  Pattern Classifier` in `coder.md` NON modificata. Item 5 `Pattern-drift
  check` in `reviewer.md` NON modificato. Regola `Add+Remove rule (for
  SUBSTITUTION fixes)` in `review-triage-fix/SKILL.md` Step 2 NON modificata.
  ADR-0002 `Snapshot Harness Integration` in `refactorer.md` NON modificata.
  Hook `approve-test-cmd.sh` + `stop-gate.sh` NON modificati. `architect.md`
  NON modificato (la skill `concept-to-code` non patcha gli agent, passa
  prompt template letterale al dispatch — decisione ADR §2.9).
- **Auto mode (no HITL intermedio):** dal brief — l'architect non chiede
  conferme durante il design (questo dispatch). Il deploy stesso del plan
  da parte del coder è anch'esso auto: backup → edit → harness verify →
  next task. HITL gate solo per uso runtime della skill `concept-to-code`
  (cioè quando l'utente effettivamente la invoca su un progetto target).
- **MEMORY index update.** Sez. finale del plan (Task 9) update di
  `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`
  con voce DEPLOYED riga in sez. `## Project`.

## File structure

Tutti i path live (`~/.claude/skills/concept-to-code/` nuova directory) +
1 edit a `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (append
2 anchor); deliverable doc nel repo `vibe-coding-system`; memory in
`~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/`.

- Create `~/.claude/skills/concept-to-code/SKILL.md` — frontmatter (name +
  description) + body 7 sezioni (When to invoke, Invocation contract, State
  machine summary, Step-by-step dispatch templates, HITL gates, Coexistence
  invariants, Failure handling). ~250 righe.
- Create `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` — bash
  3.2, ~80 righe. Args `<topic-slug> <topic-full-title> <project-root>`.
  Scrive `<project-root>/docs/manifests/<YYYY-MM-DD>-<topic-slug>.manifest.yml`
  con schema v1.0 (vedi spec §2.2). Exit 0/1/2 (vedi spec §9.1).
- Create `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` —
  bash 3.2, ~100 righe. Args `<manifest-path>`. Valida 9 invarianti (spec
  §2.3). No stdout success, errors to stderr. Exit 0/1/2.
- Create `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` —
  bash 3.2, ~120 righe. Args `<manifest-path> <new-current-step>
  [<new-status>]`. Valida transition legale via transition table embedded
  (spec §3.3, 16 transition). Atomic write `mktemp + mv`. Exit 0/1/2/3.
- Create `~/.claude/skills/concept-to-code/tests/run-tests.sh` — bash 3.2,
  self-test harness della skill, ~130 righe. 10 assertion target (vedi
  spec §9.4). Style identico a `~/.claude/skills/refactor-snapshot/tests/run-tests.sh`.
- Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh` — append
  blocco `# --- Task 8: concept-to-code skill section ---` con 2 anchor
  su `~/.claude/skills/concept-to-code/SKILL.md`, tra blocco Task 7
  (refactorer.md, riga ~151 attuale) e summary line (`echo "----"`, riga
  ~153).
- Modify `docs/architecture/ADR-0003-concept-to-code-chain.md` — status
  line da `Proposed — 2026-05-20` a `Accepted — 2026-05-20
  (implemented via plan 2026-05-20-concept-to-code-chain.md; harness
  PASS=47; skill self-test PASS=10)`.
- Modify `docs/superpowers/specs/2026-05-20-concept-to-code-chain-design.md` —
  status line da `proposed (pre-ADR-acceptance)` a `implementato — 2026-05-20`.
- Create `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_concept-to-code-chain.md` —
  nuovo project memory entry con link a ADR-0003/spec/plan, stato deploy,
  invariante "concept-to-code chain orchestrator + ADR-0001 + ADR-0002 +
  v1.2 coesistono ortogonalmente".
- Modify `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md` —
  append riga nuova in sezione `## Project` con prefix `**DEPLOYED
  2026-05-20**:`.

Unchanged (vincoli HARD): `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2
Add+Remove rule resta), `~/.claude/skills/review-triage-fix/scripts/*.sh`
(verify, weakening-scan, triage-state — invariati), `~/.claude/skills/refactor-snapshot/SKILL.md`
+ `scripts/*` + `tests/run-tests.sh` (ADR-0002 invariati), `~/.claude/agents/coder.md`
(ADR-0001 invariata), `~/.claude/agents/reviewer.md` (item 5 invariato),
`~/.claude/agents/refactorer.md` (ADR-0002 invariata), `~/.claude/agents/architect.md`
(invariata — decisione ADR §2.9), `~/.claude/agents/debugger.md`,
`tester.md`, `doc-writer.md`, `researcher.md`, `~/.claude/hooks/approve-test-cmd.sh`,
`stop-gate.sh`, `~/.claude/settings.json`, `.mcp.json`, `.claude/rules/`,
`docs/vibe-coding-system.md`, `~/.claude/skills/interview-driver/SKILL.md`,
`~/.claude/skills/adr-writer/SKILL.md`, `~/.claude/skills/claude-md-generator/SKILL.md`.

**Harness expected delta (esplicito):** review-triage-fix harness PASS=45 →
PASS=47 (+2 anchor). Refactor-snapshot self-test PASS=11 → PASS=11 (invariato,
no touch). Nuovo concept-to-code self-test PASS=0 (non esiste) → PASS=10
(target post-Task 6).

---

### Task 1: Harness anchor failing (red)

**Files:**
- Modify: `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (insert
  nuovo blocco Task 8 tra blocco Task 7 fine e summary line)

**Red phase:** baseline harness `PASS=45 FAIL=0` (post ADR-0002 deploy
2026-05-20, verified pre-Task 1). Il nuovo blocco Task 8 cerca esistenza
di `~/.claude/skills/concept-to-code/SKILL.md` e literal
`manifest_schema_version` al suo interno — entrambi assenti pre-Task-2.
Aspettativa: 2 nuovi `FAIL`, cumulative `PASS=45 FAIL=2`, exit 1.

**Green phase (edit concreto):** localizza nel file la fine del blocco
Task 7 (`grep -q -- 'refactor-snapshot' "$R" 2>/dev/null && ok
"refactorer.md: refactor-snapshot skill reference present" || bad
"refactorer.md: refactor-snapshot skill reference missing"`, attualmente
riga 151 stimata) e la summary line (`echo "----"; echo "PASS=$PASS
FAIL=$FAIL"; rm -rf "$TMP"`, attualmente riga 153 stimata). Inserisci tra
le due (in posizione riga 152 attuale blank line) il blocco:

```bash

# --- Task 8: concept-to-code skill section ---
S="$HOME/.claude/skills/concept-to-code/SKILL.md"
[ -f "$S" ] && ok "concept-to-code: SKILL.md present" || bad "concept-to-code: SKILL.md missing"
grep -q -- 'manifest_schema_version' "$S" 2>/dev/null && ok "concept-to-code: manifest_schema_version reference present" || bad "concept-to-code: manifest_schema_version reference missing"

```

Notes:
- 2 assertion totali (file exists + content literal). Stile identico al
  blocco Task 7 (refactorer.md, 2 anchor) e al blocco Task 6 (coder.md, 2
  anchor con file-exists guard rimosso post-refinement).
- Match string `manifest_schema_version` = literal YAML field nel
  prompt template SKILL.md (Task 2 lo introduce).
- 3.2-clean by construction: `[ -f "$x" ]`, `grep -q -- "..."` literal +
  `&&`/`||` + `ok`/`bad` (definiti righe 8-9 dell'harness). Identico stile
  blocco Task 7 (righe ~150-151) e blocco Task 6 (righe 148-149).
- Conta finale attesa post-Task-2: `PASS=47 FAIL=0`. Conta finale
  post-Task-1 (red): `PASS=45 FAIL=2`.

- [ ] **Step 1: Write the failing test** — edit
  `~/.claude/skills/review-triage-fix/tests/run-tests.sh` per inserire il
  blocco Task 8 (4 righe content + 1 blank leading + 1 blank trailing)
  tra la riga ultima del blocco Task 7 e la summary line.

- [ ] **Step 2: Run test to verify it fails**

Verify command:
```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
```
Expected: i 45 anchor (v1.2 + ADR-0001 + ADR-0002) ancora `PASS`; le 2
nuove check `concept-to-code: SKILL.md present` + `concept-to-code:
manifest_schema_version reference present` entrambe `FAIL`; summary
`PASS=45 FAIL=2`, exit 1.

- [ ] **Step 3: Checkpoint** — failing test in place, baseline rossa
  confermata (`PASS=45 FAIL=2`). TodoWrite update.

**Stima tempo:** 5 min.

---

### Task 2: Create skill `concept-to-code/` (SKILL.md)

**Files:**
- Create: `~/.claude/skills/concept-to-code/SKILL.md`

**Red phase:** la directory `~/.claude/skills/concept-to-code/` non
esiste. Inspectional pre-edit:
```bash
ls -d ~/.claude/skills/concept-to-code/ 2>&1
```
Expected: `No such file or directory`.

**Green phase (edit concreto):**

Crea la directory e scrivi il SKILL.md con frontmatter + 7 sezioni body.
Il contenuto deve:

1. **Frontmatter** (3 righe):
   ```yaml
   ---
   name: concept-to-code
   description: This skill should be used when a non-trivial feature must be designed and implemented end-to-end via the multi-agent chain (interview → architecture → project memory → fresh session → implementation → optional review). Orchestrates interview-driver, architect, claude-md-generator, coder agents with explicit HITL gates and YAML manifest persistence cross-session. Triggers include "fammi il chain concept-to-code", "nuova feature end-to-end", "/skill concept-to-code".
   ---
   ```

2. **Section: When to invoke** — esplicita 2 cases (form A start, form B
   resume); cita esclusione (non per hotfix, non per micro-edits).

3. **Section: Invocation contract** — le 3 form A/B/C (start, resume,
   abort) da spec §4.1. Path manifest format esplicito.

4. **Section: State machine summary** — link a spec §3. ASCII diagram
   succinto (10 righe max) o reference esplicito al file spec.

5. **Section: Step-by-step dispatch templates** — il prompt template
   *letterale* per ognuno dei 5 dispatch (interview-driver Step 1,
   architect Step 2, claude-md-generator Step 3, coder Step 5,
   review-triage-fix Step 6). Triple-backtick blocchi copiabili byte-faithful
   dall'orchestrator. **Critico:** è il defense-in-depth §2.7 ADR.
   Contenuto da spec §7.1-7.5.

6. **Section: HITL gates** — 5 gate (1, 2, 3, 4 info, 5) con display
   format esatto + wait input + reject behavior. Da spec §6.

7. **Section: Coexistence invariants** — list delle 7 cose che NON
   tocca (ADR-0001 coder.md, ADR-0002 refactorer.md, v1.2 SKILL.md,
   hook, settings, MCP, agent system prompt). Da spec §8.

8. **Section: Failure handling** — abort no-retry policy, manifest
   `failure_reason` field, partial artifacts preserve, resume path
   utente. Da ADR §2.8.

**Critical: il literal `manifest_schema_version: "1.0"` DEVE comparire nel
body (target di anchor Task 1).**

Backup raccomandato: non applicabile (file nuovo).

- [ ] **Step 1: Create skill directory**
  ```bash
  mkdir -p ~/.claude/skills/concept-to-code/scripts ~/.claude/skills/concept-to-code/tests
  ```

- [ ] **Step 2: Write SKILL.md** — content come da spec §4.1, §6, §7,
  §8. Verifica frontmatter syntax con `head -5 ~/.claude/skills/concept-to-code/SKILL.md`.

- [ ] **Step 3: Run anchor harness** — verify Task 1 red diventa green:
  ```bash
  bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
  ```
  Expected: `PASS=47 FAIL=0`, exit 0.

- [ ] **Step 4: Checkpoint** — anchor green. TodoWrite update.

**Stima tempo:** 30 min.

---

### Task 3: Create `manifest-init.sh`

**Files:**
- Create: `~/.claude/skills/concept-to-code/scripts/manifest-init.sh`

**Red phase:** lo script non esiste. Self-test harness Task 6 (assertion
1, 2) lo richiede.

**Green phase (edit concreto):**

Script bash 3.2 con:
- `#!/usr/bin/env bash`
- `set -u` (no `set -e` per allineamento con stile harness review-triage-fix
  helper script).
- Args validation: `$#` must be 3, else exit 1 con usage stderr.
- `slug="$1"`, `title="$2"`, `root="$3"`.
- Slug validation: `echo "$slug" | grep -Eq '^[a-z0-9-]{1,40}$'` o exit 1.
- Project root validation: `[ -d "$root" ]` o exit 1.
- Manifests dir create: `mkdir -p "$root/docs/manifests"`.
- Date computation: `today="$(date +%Y-%m-%d)"`.
- Manifest path: `manifest="$root/docs/manifests/$today-$slug.manifest.yml"`.
- Existence check: `[ -f "$manifest" ]` → exit 2 (already exists, use
  resume).
- Timestamp: `now="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"` (ISO 8601 UTC).
- Write manifest via heredoc-free approach (bash 3.2-clean): use multi-line
  `printf` or temp-file + multiple `echo`. Pattern: `mktemp` to temp file,
  write line-by-line with `echo`, then `mv` atomic.

Content del manifest scritto deve matchare lo schema spec §2.2 (manifest
schema v1.0, tutti i field necessari, artifacts null, hitl_gates 4-elem
list, status `in_progress`, current_step `step_0_init`).

Pattern bash 3.2-clean per multi-line write (evitando heredoc per
robustness):
```bash
T="$(mktemp)"
echo 'manifest_schema_version: "1.0"' > "$T"
echo "topic: \"$slug\"" >> "$T"
echo "topic_full_title: \"$title\"" >> "$T"
# ... etc
mv "$T" "$manifest"
```

(Anche se in realtà bash 3.2 supporta heredoc, lo evitiamo per consistency
con pattern `triage-state.sh` di review-triage-fix che usa append echo.)

- [ ] **Step 1: Write script** — bash 3.2-clean, ~80 righe.

- [ ] **Step 2: Syntactic check**
  ```bash
  bash -n ~/.claude/skills/concept-to-code/scripts/manifest-init.sh
  ```
  Expected: no output, exit 0.

- [ ] **Step 3: Chmod +x**
  ```bash
  chmod +x ~/.claude/skills/concept-to-code/scripts/manifest-init.sh
  ```

- [ ] **Step 4: Smoke test manuale** — esegui contro `/tmp` dummy project:
  ```bash
  mkdir -p /tmp/c2c-smoke && bash ~/.claude/skills/concept-to-code/scripts/manifest-init.sh smoke-topic "Smoke topic title" /tmp/c2c-smoke; echo "exit=$?"
  ls /tmp/c2c-smoke/docs/manifests/
  cat /tmp/c2c-smoke/docs/manifests/*.manifest.yml | head -30
  ```
  Expected: exit 0, file presente, schema visibile in head. Cleanup:
  `rm -rf /tmp/c2c-smoke`.

- [ ] **Step 5: Checkpoint** — script funzionante. TodoWrite update.

**Stima tempo:** 30 min.

---

### Task 4: Create `manifest-validate.sh`

**Files:**
- Create: `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh`

**Red phase:** lo script non esiste. Self-test harness Task 6 (assertion
3, 4, 5, 9, 10) lo richiede.

**Green phase (edit concreto):**

Script bash 3.2 con:
- Args validation: `$#` must be 1.
- File exists: `[ -f "$1" ]` o exit 2.
- 9 invariant checks via `grep` line-by-line (spec §2.3):
  1. `grep -q '^manifest_schema_version: "1.0"$' "$1"` o exit 1 with stderr.
  2. Topic: `grep '^topic:' "$1"` then sed-extract value, check regex.
  3. Project root: extract, check `[ -d "$root" ]`.
  4. Current_step: extract, check ∈ enum (hardcoded list of 14 valid
     states, see spec §3.1). Pattern: write states to temp-file, then
     `grep -Fxq -- "$current_step" "$temp"`.
  5. Status: similar enum check (in_progress | failed | completed |
     aborted).
  6. Conditional completed: if `status: completed`, check
     `grep -q '^  spec: /' "$1"` (path absolute, non null) AND
     `grep -q '^  adr: /' "$1"` AND `grep -q '^  plan: /' "$1"`.
  7. Conditional failed: if `status: failed`, check
     `grep -q '^  failed_step:' "$1"` AND value non-null.
  8. HITL gates: count `grep -c '^  - gate:' "$1"`, must be `= 4`.
  9. (Implicit invariant) `topic_full_title` field present.

- Output: silent on success. Errors to stderr with message
  `manifest-validate: <invariant>: <description>`.

- Exit: 0 valid, 1 invalid (with explicit stderr msg), 2 file not found.

- [ ] **Step 1: Write script** — bash 3.2-clean, ~100 righe.

- [ ] **Step 2: Syntactic check** — `bash -n`.

- [ ] **Step 3: Chmod +x**.

- [ ] **Step 4: Smoke test manuale** — manifest fresh-init (from Task 3
  smoke output) deve PASS. Manifest con `current_step: invalid-state`
  hand-edited deve FAIL.

- [ ] **Step 5: Checkpoint** — TodoWrite update.

**Stima tempo:** 40 min.

---

### Task 5: Create `manifest-transition.sh`

**Files:**
- Create: `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh`

**Red phase:** lo script non esiste. Self-test harness Task 6 (assertion
6, 7, 8) lo richiede.

**Green phase (edit concreto):**

Script bash 3.2 con:
- Args validation: `$#` ∈ {2, 3}.
- `manifest="$1"`, `new_step="$2"`, `new_status="${3:-}"`.
- Pre-flight: invoca `manifest-validate.sh "$manifest"` (script sibling),
  exit 2 se invalid.
- Read `current_step` da manifest via grep + sed.
- Validate transition legality: 16 legal transitions hardcoded (spec
  §3.3). Pattern bash 3.2-clean: write `(from,to)` pair list to temp-file,
  one pair per line, then `grep -Fxq -- "$current_step,$new_step" "$temp"`.
  Esempio temp file content:
  ```
  step_0_init,step_1_interview
  step_1_interview,gate_1_spec_review
  gate_1_spec_review,step_2_architecture
  gate_1_spec_review,step_1_interview
  ... (16 pair totali)
  ```
- Also legal: any state → `failed` (tool_error) o → `aborted` (user_abort).
  Append `*,failed` e `*,aborted` come wildcard handled separately (no
  literal `*` in grep — check via `[ "$new_step" = "failed" ] || [ "$new_step"
  = "aborted" ]` short-circuit pre-pair-lookup).
- If legal: write new manifest via temp-file. Update `current_step` line
  (sed replacement), update `last_updated_at` line (sed replacement with
  fresh ISO 8601 timestamp), optionally update `status` line if
  `new_status` provided. Use `mktemp` + sed + `mv` atomic pattern.
- If illegal: exit 1 with stderr message
  `manifest-transition: illegal transition <from> → <to>`.

- Exit: 0 ok, 1 transition illegal, 2 manifest invalid pre-transition, 3
  write error.

- [ ] **Step 1: Write script** — bash 3.2-clean, ~120 righe.

- [ ] **Step 2: Syntactic check** — `bash -n`.

- [ ] **Step 3: Chmod +x**.

- [ ] **Step 4: Smoke test manuale** —
  ```bash
  mkdir -p /tmp/c2c-smoke
  bash ~/.claude/skills/concept-to-code/scripts/manifest-init.sh smoke "Smoke" /tmp/c2c-smoke
  M=/tmp/c2c-smoke/docs/manifests/*.manifest.yml
  bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh $M step_1_interview; echo "ok-legal exit=$?"
  bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh $M step_5_implementation; echo "expected-fail exit=$?"
  rm -rf /tmp/c2c-smoke
  ```
  Expected: legal exit 0, illegal exit 1.

- [ ] **Step 5: Checkpoint** — TodoWrite update.

**Stima tempo:** 45 min.

---

### Task 6: Create self-test harness `tests/run-tests.sh`

**Files:**
- Create: `~/.claude/skills/concept-to-code/tests/run-tests.sh`

**Red phase:** il file non esiste. Harness review-triage-fix è ORTOGONALE
(non testa la skill `concept-to-code` per behavior, solo per esistenza
SKILL.md a Task 1+2). Questa è la self-test della skill.

**Green phase (edit concreto):**

Script bash 3.2-clean, ~130 righe, 10 assertion. Style identico a
`~/.claude/skills/refactor-snapshot/tests/run-tests.sh` (PASS=11).

Struttura:
```bash
#!/usr/bin/env bash
# Self-test harness for concept-to-code skill.
set -u
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SKILL_DIR="$HOME/.claude/skills/concept-to-code"
INIT="$SKILL_DIR/scripts/manifest-init.sh"
VAL="$SKILL_DIR/scripts/manifest-validate.sh"
TRN="$SKILL_DIR/scripts/manifest-transition.sh"

# --- Assertion 1: manifest-init creates valid manifest ---
mkdir -p "$TMP/proj1"
bash "$INIT" smoke-1 "Smoke 1" "$TMP/proj1" >/dev/null 2>&1
M1="$TMP/proj1/docs/manifests/$(date +%Y-%m-%d)-smoke-1.manifest.yml"
[ -f "$M1" ] && ok "manifest-init: writes file at expected path" || bad "manifest-init: file missing"

# --- Assertion 2: manifest-init refuses double-init same slug same day ---
bash "$INIT" smoke-1 "Smoke 1" "$TMP/proj1" >/dev/null 2>&1
[ "$?" = "2" ] && ok "manifest-init: refuses double init (exit 2)" || bad "manifest-init: double init not rejected"

# --- Assertion 3: manifest-validate PASS on fresh-init manifest ---
bash "$VAL" "$M1" >/dev/null 2>&1 && ok "manifest-validate: fresh init passes" || bad "manifest-validate: fresh init fails"

# --- Assertion 4: manifest-validate FAIL without manifest_schema_version ---
M_BAD="$TMP/bad-noversion.yml"
grep -v 'manifest_schema_version' "$M1" > "$M_BAD"
bash "$VAL" "$M_BAD" >/dev/null 2>&1
[ "$?" != "0" ] && ok "manifest-validate: rejects missing schema_version" || bad "manifest-validate: accepts missing schema_version"

# --- Assertion 5: manifest-validate FAIL with invalid current_step ---
M_BAD2="$TMP/bad-step.yml"
sed 's/^current_step: .*/current_step: "step_NOT_REAL"/' "$M1" > "$M_BAD2"
bash "$VAL" "$M_BAD2" >/dev/null 2>&1
[ "$?" != "0" ] && ok "manifest-validate: rejects invalid current_step" || bad "manifest-validate: accepts invalid current_step"

# --- Assertion 6: transition step_0_init → step_1_interview legal ---
bash "$TRN" "$M1" step_1_interview >/dev/null 2>&1 && ok "manifest-transition: 0→1 legal" || bad "manifest-transition: 0→1 rejected"

# --- Assertion 7: transition step_0_init → step_5_implementation illegal (after reset) ---
mkdir -p "$TMP/proj2"
bash "$INIT" smoke-2 "Smoke 2" "$TMP/proj2" >/dev/null 2>&1
M2="$TMP/proj2/docs/manifests/$(date +%Y-%m-%d)-smoke-2.manifest.yml"
bash "$TRN" "$M2" step_5_implementation >/dev/null 2>&1
[ "$?" = "1" ] && ok "manifest-transition: skip 0→5 rejected" || bad "manifest-transition: skip 0→5 accepted"

# --- Assertion 8: transition updates last_updated_at ---
BEFORE="$(grep '^last_updated_at:' "$M1")"
sleep 1
bash "$TRN" "$M1" gate_1_spec_review >/dev/null 2>&1
AFTER="$(grep '^last_updated_at:' "$M1")"
[ "$BEFORE" != "$AFTER" ] && ok "manifest-transition: last_updated_at refreshed" || bad "manifest-transition: last_updated_at stale"

# --- Assertion 9: validate completed manifest requires artifacts populated ---
M_COMPL="$TMP/completed.yml"
sed -e 's/^status: .*/status: "completed"/' -e 's|^  spec: null|  spec: /tmp/SPEC.md|' "$M1" > "$M_COMPL"
# Still missing adr and plan as absolute paths → should fail
bash "$VAL" "$M_COMPL" >/dev/null 2>&1
[ "$?" != "0" ] && ok "manifest-validate: completed requires artifacts" || bad "manifest-validate: completed accepts null artifacts"

# --- Assertion 10: validate failed manifest requires failure.failed_step ---
M_FAIL="$TMP/failed.yml"
sed 's/^status: .*/status: "failed"/' "$M1" > "$M_FAIL"
# failure.failed_step is null in fresh-init → should fail
bash "$VAL" "$M_FAIL" >/dev/null 2>&1
[ "$?" != "0" ] && ok "manifest-validate: failed requires failed_step" || bad "manifest-validate: failed accepts null failed_step"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
```

(Sketch sopra è il contract; coder lo cesella esatto.)

- [ ] **Step 1: Write self-test harness** — 10 assertion, style
  identico a refactor-snapshot.

- [ ] **Step 2: Syntactic check** — `bash -n`.

- [ ] **Step 3: Chmod +x**.

- [ ] **Step 4: Run self-test**
  ```bash
  bash ~/.claude/skills/concept-to-code/tests/run-tests.sh; echo "exit=$?"
  ```
  Expected: `PASS=10 FAIL=0`, exit 0.

- [ ] **Step 5: Run review-triage-fix harness** — assicurarsi 47 ancora
  green:
  ```bash
  bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh; echo "exit=$?"
  ```
  Expected: `PASS=47 FAIL=0`, exit 0.

- [ ] **Step 6: Run refactor-snapshot harness** — assicurarsi 11
  invariato:
  ```bash
  bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh; echo "exit=$?"
  ```
  Expected: `PASS=11 FAIL=0`, exit 0.

- [ ] **Step 7: Checkpoint** — tutti e 3 gli harness verdi.
  TodoWrite update.

**Stima tempo:** 60 min.

---

### Task 7: Update ADR-0003 + spec status

**Files:**
- Modify: `/Users/stefanoferri/Developer/vibe-coding-system/docs/architecture/ADR-0003-concept-to-code-chain.md`
- Modify: `/Users/stefanoferri/Developer/vibe-coding-system/docs/superpowers/specs/2026-05-20-concept-to-code-chain-design.md`

**Red phase:** entrambi i file hanno status `Proposed` / `proposed
(pre-ADR-acceptance)`.

**Green phase (edit concreto):**

In `ADR-0003-concept-to-code-chain.md` line 3:
- Da: `**Status:** Proposed — 2026-05-20`
- A: `**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-concept-to-code-chain.md; review-triage-fix harness PASS=47; concept-to-code self-test PASS=10; refactor-snapshot self-test PASS=11 unchanged)`

In `2026-05-20-concept-to-code-chain-design.md` line ~3:
- Da: `**Status:** proposed (pre-ADR-acceptance) — pronto per writing-plans dopo conferma utente`
- A: `**Status:** implementato — 2026-05-20`

- [ ] **Step 1: Edit ADR-0003 status line**.

- [ ] **Step 2: Edit spec status line**.

- [ ] **Step 3: Verify** — `head -5` su entrambi i file, verifica le 2
  status line aggiornate.

- [ ] **Step 4: Checkpoint** — TodoWrite update.

**Stima tempo:** 5 min.

---

### Task 8: Create project memory entry

**Files:**
- Create: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_concept-to-code-chain.md`

**Red phase:** il file non esiste. MEMORY.md non lo referenzia.

**Green phase (edit concreto):**

Markdown ~30 righe con:
- Titolo: `# Project memory — concept-to-code chain orchestrator skill`
- Date: `**Deployed:** 2026-05-20`
- Status: `**Status:** ACTIVE`
- Links:
  - ADR-0003: `/Users/stefanoferri/Developer/vibe-coding-system/docs/architecture/ADR-0003-concept-to-code-chain.md`
  - Spec: `/Users/stefanoferri/Developer/vibe-coding-system/docs/superpowers/specs/2026-05-20-concept-to-code-chain-design.md`
  - Plan: `/Users/stefanoferri/Developer/vibe-coding-system/docs/superpowers/plans/2026-05-20-concept-to-code-chain.md`
- Files deployed (5):
  - `~/.claude/skills/concept-to-code/SKILL.md`
  - `~/.claude/skills/concept-to-code/scripts/manifest-init.sh`
  - `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh`
  - `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh`
  - `~/.claude/skills/concept-to-code/tests/run-tests.sh`
- Harness deltas:
  - review-triage-fix: PASS=45 → PASS=47 (+2 anchor)
  - concept-to-code self-test: PASS=10 (new)
  - refactor-snapshot self-test: PASS=11 (unchanged)
- Invariants:
  - "concept-to-code chain orchestrator + ADR-0001 + ADR-0002 + v1.2 Add+Remove rule
    coesistono ortogonalmente; nessuna sovrascrittura di feature precedenti."
  - "Sub-agent constraint (blueprint sez. 2) rispettato: la skill istruisce
    l'orchestrator (main agent CLI), no sub-agent spawning."
- Validation pilota: "Validation pilota: pending — primo uso reale su un
  topic non-banale validerà il flow end-to-end (in particolare lo Step 4
  fresh-session boundary)."

- [ ] **Step 1: Write project memory file**.

- [ ] **Step 2: Verify** — `ls -la` + `head -20` del nuovo file.

- [ ] **Step 3: Checkpoint** — TodoWrite update.

**Stima tempo:** 10 min.

---

### Task 9: Update MEMORY.md index

**Files:**
- Modify: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`

**Red phase:** MEMORY.md sez. `## Project` non contiene voce
`concept-to-code-chain`.

**Green phase (edit concreto):**

Append nella sezione `## Project` (dopo l'ultima voce esistente, prima
della sezione `## Feedback`), una nuova riga:

```markdown
- [Concept-to-code chain](project_concept-to-code-chain.md) — **DEPLOYED 2026-05-20**: skill orchestratore del workflow blueprint sez. 11 (interview → architecture → project memory → fresh session → impl → optional review) con manifest YAML cross-session, 3 HITL gates bloccanti + 1 checkpoint + 1 opzionale; riusa interview-driver + claude-md-generator; coesiste ortogonale con ADR-0001 + ADR-0002 + v1.2; harness PASS=47 + self-test PASS=10
```

- [ ] **Step 1: Edit MEMORY.md** — append riga in sezione Project (NON
  in sezione Feedback).

- [ ] **Step 2: Verify** — `grep -c 'concept-to-code-chain' ~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`.
  Expected: 1.

- [ ] **Step 3: Final verification — full harness suite**
  ```bash
  echo "=== review-triage-fix harness ==="
  bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh | tail -3
  echo "=== concept-to-code self-test ==="
  bash ~/.claude/skills/concept-to-code/tests/run-tests.sh | tail -3
  echo "=== refactor-snapshot self-test ==="
  bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh | tail -3
  ```
  Expected:
  - review-triage-fix: `PASS=47 FAIL=0`
  - concept-to-code: `PASS=10 FAIL=0`
  - refactor-snapshot: `PASS=11 FAIL=0`

- [ ] **Step 4: Final checkpoint** — TodoWrite tutti i 9 task chiusi.

**Stima tempo:** 5 min.

---

## Summary

**Totale task:** 9 (1 red + 5 green deploy + 1 ADR/spec sync + 2 memory).

**Totale tempo stimato:** 5+30+30+40+45+60+5+10+5 = **230 min ≈ 3h 50min**.

**Harness expected delta (riassunto):**
- review-triage-fix: PASS=45 → **PASS=47** (+2 anchor).
- concept-to-code (nuovo): PASS=0 → **PASS=10** (10 self-test assertion).
- refactor-snapshot: PASS=11 → **PASS=11** (invariato).

**Coexistenza HARD verificata:**
- `coder.md` (ADR-0001): non modificato.
- `reviewer.md` (ADR-0001): non modificato.
- `refactorer.md` (ADR-0002): non modificato.
- `architect.md`: non modificato.
- `review-triage-fix/SKILL.md` (v1.2): non modificato.
- Hook, settings, MCP, rules: non modificati.
- Skill orchestrate (`interview-driver`, `adr-writer`, `claude-md-generator`):
  non modificate.

**Deliverable finali (8 file):**
1. `~/.claude/skills/concept-to-code/SKILL.md` (new)
2. `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` (new)
3. `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` (new)
4. `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` (new)
5. `~/.claude/skills/concept-to-code/tests/run-tests.sh` (new)
6. `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (modify: +1 block, 2 anchor)
7. `~/.claude/projects/.../memory/project_concept-to-code-chain.md` (new)
8. `~/.claude/projects/.../memory/MEMORY.md` (modify: +1 row in `## Project`)

+ doc updates in repo blueprint:
- `docs/architecture/ADR-0003-concept-to-code-chain.md` (status line)
- `docs/superpowers/specs/2026-05-20-concept-to-code-chain-design.md` (status line)
