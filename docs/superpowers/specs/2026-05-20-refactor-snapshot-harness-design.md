# Design — Behavior-preservation Snapshot Harness per il refactorer agent

**Data:** 2026-05-20
**Stato:** implementato — 2026-05-20 (harness review-triage-fix PASS=45; skill self-test PASS=11; dispatch organico del refactorer validerà fedeltà LLM al contract 8-step, vedi Open questions ADR §4.4)
**Autore:** Adriano per Stefano Ferri
**Topic:** introdurre uno snapshot harness pre/post refactor per il `refactorer`
agent, che cattura output testuale dei test (`stdout`/`stderr`/`exit-code`), confronta
SHA256 pre vs post, e fallisce loud se diff non-zero. Skill bash 3.2-clean
stack-agnostic in `~/.claude/skills/refactor-snapshot/`, invocata dal `refactorer`
agent come gate nel suo Process.

**ADR di riferimento:** `docs/architecture/ADR-0002-refactor-snapshot-harness.md`
(autoritativa per il "perché"; questo spec si concentra sui contract, interfaces e delta
puntuali dei file).

---

## 1. Contesto (sintetico — dettaglio nell'ADR)

Il refactorer è oggi il sub-agent meno usato. Causa: green→green check è proxy debole
di behavior-preservation. Cycle 2 di `pricing-markup-cli` ha prodotto MAJOR M-1 da
refactor che ha *aggiunto* comportamento (autouse fixture duplicata) — green→green
non l'ha catturato. Snapshot harness cattura output testuale pre/post e fallisce su
diff. Triple-angle coverage del rischio "code change non corrisponde a intent":
ADR-0001 (coder pre-flight) + v1.2 (reviewer triage Add+Remove) + ADR-0002 (refactorer
post-edit snapshot).

## 2. Goal / Non-goal

**Goal:** definire e deployare uno snapshot harness behavior-preservation per il
`refactorer` agent, stack-agnostic, zero-dep, integrato con il contract `.claude/test-cmd`
già live.

**Non-goal:**
- Modifiche al sub-agent identity del `refactorer` (`tools:`, `model:`, color) — restano
  `Read,Edit,Glob,Grep,Bash`, `sonnet`, giallo.
- Pure function return values come snapshot (deferred, vedi ADR §3.1).
- AST signatures o call graphs (rejected, vedi ADR §3.1.c-d).
- Per-stack adapter (Python/JS/Swift) — stack-agnostic single harness via
  `.claude/test-cmd` (ADR §2.7).
- Hook PreToolUse di enforcement (rejected, vedi ADR §3.8.d).
- Modifiche a `coder.md`, `reviewer.md`, `debugger.md`, `tester.md`, `doc-writer.md`,
  `researcher.md`, `architect.md` — solo `refactorer.md` (primary).
- Modifiche al `review-triage-fix/SKILL.md` — invariata (ortogonale).
- Modifiche al hook `approve-test-cmd.sh` — il harness *riusa* il contract
  `.claude/test-cmd` ma non interagisce con TOFU.
- Validazione end-to-end empirica della fedeltà LLM al contract — pending pilota
  operativo (open questions ADR §4.4).
- CI/CD integration sul progetto target — scope futuro.

## 3. Architettura — skill bash 3.2 + system prompt patch + anchor

### 3.1 Skill `~/.claude/skills/refactor-snapshot/`

Struttura directory:

```
~/.claude/skills/refactor-snapshot/
├── SKILL.md
├── scripts/
│   ├── capture.sh      # bash 3.2, exec test-cmd, scrive snapshot file
│   └── diff.sh         # bash 3.2, confronta pre/post SHA256, exit 0/1/2
└── tests/
    └── run-tests.sh    # bash 3.2, self-test harness della skill
```

**Frontmatter `SKILL.md`:**

```yaml
---
name: refactor-snapshot
description: Behavior-preservation snapshot harness for the refactorer agent. Captures stdout/stderr/exit-code of project test command pre-refactor, re-runs post-refactor, diffs SHA256. Fails loud on non-zero diff. Stack-agnostic via .claude/test-cmd contract.
---
```

**Body `SKILL.md` (sezioni minimali):**

1. `## When to invoke` — esclusivamente dal `refactorer` agent durante il suo Process
   (vedi §3.2). Non auto-invocata, non chained.
2. `## Invocation contract` — il refactorer chiama `capture.sh PRE` prima di edit,
   `capture.sh POST` dopo edit, `diff.sh` come gate. Vedi §3.3 per CLI.
3. `## Outputs` — file `.claude/.refactor-snapshot.txt` (PRE) e
   `.claude/.refactor-snapshot.txt.post` (POST). Exit code `diff.sh`: 0=PASS, 1=FAIL,
   2=UNVERIFIED.
4. `## Stack-agnostic` — il harness legge `.claude/test-cmd` (riuso contract
   swarm-testcmd 2026-05-19). Nessun parsing di linguaggio.
5. `## Override` — `.claude/refactor-snapshot-override` file, formato dichiarativo.
   Solo l'utente lo crea. Audit trail nel report.
6. `## Failure modes` — 3 stati (PASS/FAIL/UNVERIFIED), distinzione via determinism
   check (3 pre-snapshot run).

### 3.2 `~/.claude/agents/refactorer.md` patch (primary)

Sostituire la sezione `## Process` (righe 25-31 attuali) con la sequenza 8-step
dell'ADR §2.6. Append nuova sezione `## Snapshot Harness Integration` (riferimento
alla skill) e voce in `## Edge Cases`.

**Nuovo `## Process` (sostituzione):**

```markdown
## Process

1. **Baseline check.** Run the project test command (`.claude/test-cmd`). If non-zero
   → STOP, report "tests red at baseline, refactor unsafe" (defer to debugger).
2. **Pre-snapshot capture.** Invoke `bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh PRE`.
   Writes `.claude/.refactor-snapshot.txt` with EXIT/STDOUT-SHA256/STDERR-SHA256 + payload.
3. **Determinism check.** Re-run pre-snapshot 2 more times (3 total). If SHA256 differs
   across runs → STOP, output `UNVERIFIED non-deterministic test output`, report
   flakiness with suggestion to create `.claude/refactor-snapshot-override` if intentional.
4. **Apply refactor.** Focused, behavior-preserving edit (≤200 lines per pass — existing
   invariant preserved).
5. **Post-snapshot capture.** Invoke `bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh POST`.
   Writes `.claude/.refactor-snapshot.txt.post`.
6. **Diff.** Invoke `bash ~/.claude/skills/refactor-snapshot/scripts/diff.sh`. Compares
   EXIT + STDOUT-SHA256 + STDERR-SHA256 of PRE vs POST. Exit 0=PASS, 1=FAIL, 2=UNVERIFIED.
7. **On FAIL.** STOP. Report drift with `loc=path:line` for the diverging channel(s)
   (exit/stdout/stderr) + `diff -u` excerpt of the payloads. Refactor remains on disk;
   recommend revert. HITL gate: user decides whether to accept as intentional behavior
   change (not a refactor) or revert.
8. **On PASS.** Report success: `lines changed`, `tests passed`, `snapshot PASS`. Cleanup
   `.refactor-snapshot.txt.post` (PRE kept as baseline for next cycle, or removed if
   MVP cleanup chosen — see SKILL.md).
```

**Nuova sezione `## Snapshot Harness Integration`:**

```markdown
## Snapshot Harness Integration

The behavior-preservation guarantee is provided by
`~/.claude/skills/refactor-snapshot/`, invoked at steps 2/3 (PRE), 5 (POST), 6 (diff)
of Process above.

- `.claude/test-cmd` MUST pre-exist and be approved (TOFU). If absent, snapshot is
  UNVERIFIED → STOP, ask user to deploy test-cmd first.
- For projects with non-deterministic test output (timestamps, random IDs), the user
  may create `.claude/refactor-snapshot-override` with `REASON:`/`SCOPE:`/`EXPIRES:`
  fields. The refactorer NEVER creates this file itself — HITL gate.
- For reflection / dynamic dispatch in the modified files, escalate blast radius via
  `RFS_FULL=1` env var (full project test scope). Declare the escalation in the report.
- For slow test suites, narrow scope via `RFS_FILTER=<pattern>` env var passed to the
  test command. Decide at runtime based on PRE-snapshot baseline duration.
```

**Aggiunta a `## Edge Cases`:**

```markdown
- **Snapshot UNVERIFIED:** non-deterministic test output (3 PRE runs differ). Do not
  proceed with refactor. Report flakiness; suggest investigating test cleanup or
  creating override file.
- **Test-cmd missing:** `.claude/test-cmd` absent. STOP, defer to user to deploy
  test-cmd before refactor.
```

**NO modifiche** a:
- Frontmatter (name, description, tools, model, color).
- Sezione `## When to invoke`.
- Sezione `## Core Responsibilities` (5 bullet points).
- Sezione `## Quality Standards`.
- Sezione `## Output Format`.

### 3.3 Contract CLI degli script

**`capture.sh`:**

```
Usage: capture.sh <PRE|POST>

Reads:
  - $PWD/.claude/test-cmd  (test command, contract from swarm-testcmd 2026-05-19)
  - $RFS_FILTER             (optional, passed as env to test-cmd)
  - $RFS_FULL               (optional, when set ignores RFS_FILTER)
  - $RFS_TIMEOUT            (optional, default 120s)

Writes:
  - $PWD/.claude/.refactor-snapshot.txt       (when arg=PRE)
  - $PWD/.claude/.refactor-snapshot.txt.post  (when arg=POST)

Output format (both files):
  EXIT=<exit-code>
  STDOUT-SHA256=<hex>
  STDERR-SHA256=<hex>
  ---STDOUT---
  <full stdout>
  ---STDERR---
  <full stderr>

Exit:
  0  on successful capture (regardless of test-cmd exit code — that goes into the file)
  1  on missing .claude/test-cmd
  2  on timeout (>RFS_TIMEOUT)
  3  on usage error (bad arg)
```

**`diff.sh`:**

```
Usage: diff.sh [--baseline <PRE-file>] [--candidate <POST-file>]

Defaults:
  --baseline   $PWD/.claude/.refactor-snapshot.txt
  --candidate  $PWD/.claude/.refactor-snapshot.txt.post

Reads:
  - PRE file, POST file
  - $PWD/.claude/refactor-snapshot-override (optional)

Logic:
  1. Parse SHA256 + EXIT from each file.
  2. If override file exists, read SCOPE (stdout|stderr|exit|all) and ignore diff in
     declared channels.
  3. Compare EXIT, STDOUT-SHA256, STDERR-SHA256 between PRE and POST.
  4. Output PASS/FAIL/UNVERIFIED.

Exit:
  0  PASS  (all three identical, or override-active for all diverging channels)
  1  FAIL  (at least one diverging channel not covered by override)
  2  UNVERIFIED (PRE or POST file malformed / missing)

Stdout (always):
  STATUS=<PASS|FAIL|UNVERIFIED>
  EXIT-MATCH=<yes|no>
  STDOUT-MATCH=<yes|no>
  STDERR-MATCH=<yes|no>
  OVERRIDE=<yes:reason|no>
```

**`tests/run-tests.sh`:**

Self-test harness della skill, identico pattern review-triage-fix. Verifica:
- Frontmatter `name` + `description` di SKILL.md.
- Presenza struttura directory (`scripts/capture.sh`, `scripts/diff.sh`).
- Capture su mock test-cmd green → file con `EXIT=0` + SHA256 valid hex.
- Capture su mock test-cmd red → file con `EXIT=<non-zero>`.
- Capture su `.claude/test-cmd` missing → exit 1.
- Diff su 2 file con SHA256 identici → exit 0 STATUS=PASS.
- Diff su 2 file con SHA256 stdout diversi → exit 1 STATUS=FAIL.
- Diff con override file SCOPE=stdout su 2 file stdout diversi → exit 0 STATUS=PASS
  OVERRIDE=yes.
- Diff su 2 file malformati → exit 2 STATUS=UNVERIFIED.

Target self-test: PASS=10 minimo (numero esatto da plan).

### 3.4 Harness `review-triage-fix/tests/run-tests.sh` extension

Aggiungere blocco `# --- Task 7: refactorer.md snapshot harness section ---` con 2
anchor su `~/.claude/agents/refactorer.md`:

```bash
# --- Task 7: refactorer.md snapshot harness section ---
R="$HOME/.claude/agents/refactorer.md"
grep -q -- 'Snapshot Harness Integration' "$R" 2>/dev/null && ok "refactorer.md: snapshot integration section present" || bad "refactorer.md: snapshot integration section missing"
grep -q -- 'refactor-snapshot' "$R" 2>/dev/null && ok "refactorer.md: refactor-snapshot skill reference present" || bad "refactorer.md: refactor-snapshot skill reference missing"
```

Cumulative harness: PASS=43 (post ADR-0001) → PASS=45 (+2 anchor refactorer.md).

**Posizionamento:** dopo il blocco Task 6 (coder.md, righe 146-149 attuali) e prima
della summary line `echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"`.

**3.2-clean by construction:** `grep -q -- "..."` literal + `ok`/`bad` helpers
(definiti riga 8-9). Nessun assoc array, nessun mapfile, nessun process substitution.

## 4. Format dei file snapshot (contract preciso)

### 4.1 `.claude/.refactor-snapshot.txt` (e `.post`)

Plaintext deterministico:

```
EXIT=<integer>
STDOUT-SHA256=<64 hex chars>
STDERR-SHA256=<64 hex chars>
---STDOUT---
<full stdout, byte-faithful, no newline normalization>
---STDERR---
<full stderr, byte-faithful, no newline normalization>
```

**Tolleranze:**
- Header lines (EXIT, STDOUT-SHA256, STDERR-SHA256) sempre presenti in quest'ordine,
  uno per riga.
- I separator `---STDOUT---` / `---STDERR---` sempre presenti, esatti.
- Stdout/stderr possono essere vuoti (file termina con `---STDERR---\n` + 0 byte).

**Non-tolleranze:**
- EXIT deve essere integer (0-255). Altri valori → file malformato.
- SHA256 deve essere lowercase hex 64 char esatti. Altri formati → malformato.
- Ordine separator: STDOUT prima di STDERR. Inverso → malformato.

**Compute SHA256:** usa `shasum -a 256` (BSD/macOS default), fallback `sha256sum`
(GNU/Linux). Detect via `command -v shasum` / `command -v sha256sum`.

### 4.2 `.claude/refactor-snapshot-override` (opzionale, user-created)

Plaintext key-value:

```
REASON: <one-line justification>
SCOPE: <stdout|stderr|exit|all>
EXPIRES: <YYYY-MM-DD>
```

**Tolleranze:**
- Whitespace dopo `:` (1+ spaces) tollerato.
- Comment lines (leading `#`) ignorate.
- Trailing blank lines ignorate.

**Non-tolleranze:**
- REASON, SCOPE, EXPIRES tutti e tre obbligatori. Mancanza → override non riconosciuto,
  harness procede senza override.
- SCOPE deve essere uno dei 4 letterali. Altri valori → override non riconosciuto.
- EXPIRES nel passato → override scaduto, ignorato.

**Audit:** il `diff.sh` cita override nel suo output STDOUT (`OVERRIDE=yes:<REASON>`)
e il refactorer cita il path + reason nel report finale.

## 5. File modificati / nuovi

### Creati

- **`~/.claude/skills/refactor-snapshot/SKILL.md`** — frontmatter + body (6 sezioni
  §3.1). ~60 righe.
- **`~/.claude/skills/refactor-snapshot/scripts/capture.sh`** — bash 3.2, ~80 righe.
- **`~/.claude/skills/refactor-snapshot/scripts/diff.sh`** — bash 3.2, ~90 righe.
- **`~/.claude/skills/refactor-snapshot/tests/run-tests.sh`** — bash 3.2, self-test
  harness, ~110 righe (10 assertion).
- **`docs/architecture/ADR-0002-refactor-snapshot-harness.md`** (questo deliverable +
  ADR-0002).
- **`docs/superpowers/specs/2026-05-20-refactor-snapshot-harness-design.md`** (questo
  file).
- **`docs/superpowers/plans/2026-05-20-refactor-snapshot-harness.md`** — plan TDD.
- **`~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/project_refactor-snapshot-harness.md`** —
  memory entry.

### Modificati

- **`~/.claude/agents/refactorer.md`** — sostituire `## Process` (righe 25-31) con la
  sequenza 8-step §3.2. Append `## Snapshot Harness Integration` (~10 righe). Append
  2 bullet a `## Edge Cases`. Frontmatter, `## When to invoke`, `## Core
  Responsibilities`, `## Quality Standards`, `## Output Format` INVARIATI.
- **`~/.claude/skills/review-triage-fix/tests/run-tests.sh`** — append blocco
  `# --- Task 7: refactorer.md snapshot harness section ---` (~4 righe) tra blocco
  Task 6 (riga 149) e summary line (riga 151).
- **`~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/MEMORY.md`** —
  append riga in sezione `## Project` per la nuova feature.

### Nessun cambio

- `~/.claude/skills/review-triage-fix/SKILL.md` — v1.2 Add+Remove rule resta.
- `~/.claude/skills/review-triage-fix/scripts/*.sh` — verify/weakening-scan/triage-state
  invariati.
- `~/.claude/agents/coder.md`, `reviewer.md`, `debugger.md`, `tester.md`, `architect.md`,
  `doc-writer.md`, `researcher.md` — non toccati.
- `~/.claude/hooks/approve-test-cmd.sh`, `stop-gate.sh` — invariati.
- `~/.claude/settings.json`, `.mcp.json` — invariati.
- `docs/vibe-coding-system.md` — invariato (un futuro update v2.2 lo allineerà con la
  sezione snapshot harness, scope separato).

## 6. API minimale del harness skill (estensibilità)

### 6.1 Invocation API (oggi, MVP)

```bash
# Pre-snapshot
bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh PRE
# returns 0 on success, writes .claude/.refactor-snapshot.txt

# Post-snapshot
bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh POST
# returns 0 on success, writes .claude/.refactor-snapshot.txt.post

# Diff
bash ~/.claude/skills/refactor-snapshot/scripts/diff.sh
# returns 0=PASS, 1=FAIL, 2=UNVERIFIED; STDOUT: STATUS + per-channel match
```

### 6.2 Env vars (configurazione runtime)

| Var | Tipo | Default | Effetto |
|---|---|---|---|
| `RFS_TIMEOUT` | int (sec) | 120 | Timeout per ciascun test-cmd run |
| `RFS_FILTER` | string | empty | Pattern passato come arg al test-cmd (es. `pytest -k <pat>`) |
| `RFS_FULL` | bool (0/1) | 0 | Quando 1, ignora RFS_FILTER e usa full test scope |
| `RFS_DETERMINISM_RUNS` | int | 3 | Numero di run nel determinism check |
| `RFS_NORMALIZE` | path | empty | Script opzionale che pre-processa stdout (deferred, non-MVP) |

### 6.3 Estensibilità per multi-stack (deferred)

Helper opzionali in `~/.claude/skills/refactor-snapshot/normalize/`:
- `normalize-timestamps.sh` — strip `\d{4}-\d{2}-\d{2}T...` patterns.
- `normalize-paths.sh` — replace `$PWD` con `<PROJECT_ROOT>` letterale.
- `normalize-pids.sh` — strip `pid=\d+`.

Hook via `RFS_NORMALIZE=<helper-path>`. Non MVP — aggiunti solo se evidenza pilota lo
richiede.

### 6.4 Pure function snapshot (deferred)

Future extension: `scripts/capture-functions.sh <module> <func-list>` che esegue le
funzioni con input fissati e snapshotta return values + SHA256. Stack-locked (richiede
runner Python/Swift/JS). Deferred fino a evidenza pilota.

## 7. Deploy strategy

Modifiche additive:
- Nuova skill (no overwrite di skill esistenti).
- `refactorer.md` Process section sostituito (no shim, no backwards-compat — il
  Process esistente è 6 step prosaic, il nuovo è 8 step strutturato; sostituzione
  pulita).
- `review-triage-fix/tests/run-tests.sh` append nuovo blocco (no rimozione di anchor
  esistenti).

Nessun hook live, settings.json, MCP toccato. Nessun HITL gate richiesto dal deploy.

Backup pre-edit raccomandato per `refactorer.md` (cp `.bak-2026-05-20`) e
`review-triage-fix/tests/run-tests.sh` (cp `.bak-2026-05-20`). Allineato pratica repo.

## 8. Testing

### Deterministico (self-test della skill)

```bash
bash ~/.claude/skills/refactor-snapshot/tests/run-tests.sh
# expected: PASS=10 FAIL=0, exit 0
```

Le 10 assertion coprono i contract di capture.sh, diff.sh e l'integrazione override.

### Deterministico (anchor harness review-triage-fix)

```bash
bash ~/.claude/skills/review-triage-fix/tests/run-tests.sh
# expected: PASS=45 FAIL=0, exit 0
# (43 baseline post ADR-0001 + 2 new anchor refactorer.md)
```

### Non-deterministico (pilota operativo)

Validazione operativa del valore della feature è LLM-mediated + workflow-dependent,
validabile solo nell'uso reale. Metriche da osservare in pilota:

- **Hit-rate compliance:** % di cycle refactor in cui il refactorer invoca capture.sh
  + diff.sh. Target: >95%.
- **FAIL rate:** % di cycle che producono FAIL (snapshot drift catturato). Atteso
  baseline 5-15% (refactor genuini sono rari da rompere, ma il fail mode esiste).
- **UNVERIFIED rate:** % di cycle che producono UNVERIFIED per test flakiness. Target
  sweet spot: <20%. Oltre indica problema sistemico di test cleanup nei progetti
  pilota.
- **Override file usage:** % di cycle che usano `.claude/refactor-snapshot-override`.
  Target sweet spot: 5-15%.
- **Delega rate:** se l'utente Stefano effettivamente delega più refactor al
  refactorer post-deploy. Misura outcome del razionale "sub-agent meno usato".

Non bloccante per il deploy: validano la design hypothesis, non il deploy stesso.

### Bash 3.2 / BSD compat

Tutti gli script bash 3.2-clean by construction:
- `grep -q -- "literal"` per match deterministico.
- `ok`/`bad` helpers (PASS counter / FAIL counter) per harness self-test.
- `shasum -a 256` / `sha256sum` con detect via `command -v`.
- Nessun assoc array, nessun `mapfile`, nessun `${v^^}`, nessun `<()`.
- `mktemp -d` per temp file isolation.

## 9. Vincoli & invarianti

- **Anchor preservation:** PASS=43 (post ADR-0001) → PASS=45 (+2 anchor refactorer.md).
  Mai scendere. ADR-0001 baseline 43 mantenuto.
- **No backwards-compat shim:** il nuovo Process sostituisce il vecchio Process del
  refactorer pulito.
- **Coexistenza ortogonale:** ADR-0001 (coder pre-flight) + v1.2 (reviewer Add+Remove)
  restano invariati. Snapshot harness opera sul refactorer, non li tocca.
- **Sub-agent contract immutato:** refactorer resta Sonnet, `tools: Read, Edit, Glob,
  Grep, Bash` (nota: NO Write, lo era già; il refactorer non scrive file nuovi —
  modifica esistenti), color giallo, behavior-preserving constraint.
- **Riuso contract `.claude/test-cmd`:** swarm-testcmd 2026-05-19 deploy, TOFU + 3-tier.
  Lo snapshot harness NON crea / modifica test-cmd; richiede pre-esistenza.
- **Lingua:** SKILL.md, capture.sh, diff.sh, run-tests.sh, refactorer.md in inglese
  (contract). ADR/spec/plan/memory in italiano.
- **HITL gate:** richiesto solo per creazione override file
  `.claude/refactor-snapshot-override` (user-only). Il refactorer non lo crea mai.
- **Bash 3.2.57:** tutti gli script live in `~/.claude/skills/refactor-snapshot/` 3.2-clean.
- **No git operation nel plan:** repo NON-git (vibe-coding-system blueprint repo +
  `~/.claude/`). Plan non propone commit.

## 10. Out of scope

- Pure function return value snapshot (deferred per evidenza pilota).
- AST signature snapshot (rejected, vedi ADR §3.1).
- Per-stack adapter Python/JS/Swift (rejected, ADR §3.7).
- Hook PreToolUse di enforcement (rejected, ADR §3.8.d).
- Helper di normalizzazione `normalize-*.sh` (deferred).
- CI/CD integration sul progetto target (scope futuro).
- Aggiornamento `docs/vibe-coding-system.md` v2.2 con sezione snapshot harness
  (scope separato).
- Estensione snapshot harness al `debugger` o `tester` agent (possibile futuro, scope
  separato).
- Auto-detection di test flakiness con suggerimento di cleanup (out of scope MVP;
  il refactorer riporta UNVERIFIED e suggerisce override, ma non auto-fix).

## 11. Confidence

**Media-alta.**

**Alta sui contract di file e CLI:**
- Format `.refactor-snapshot.txt` (EXIT/SHA256/separator/payload) è deterministico e
  ispezionabile — 100% definito.
- CLI di `capture.sh` e `diff.sh` (arg, env, exit code, stdout) — 100% definita.
- Format override file — 100% definito.
- 2 anchor structural in harness review-triage-fix — 3.2-clean by construction.
- Coexistenza ortogonale con ADR-0001 + v1.2 — no race condition possibili.

**Media sull'efficacia operativa:**
- Il contract di invocazione (refactorer chiama capture/diff nel suo Process) è
  plausibile da seguire per Sonnet (analogo a "tests green before, tests green after"
  che già funziona), ma non verificato per questa esatta sequenza 8-step.
- Determinism check (3 run consecutivi) potrebbe risultare temporal overhead
  problematico su progetti con test slow. Mitigazione `RFS_FILTER` esiste ma
  effectiveness validabile solo in pilota.
- Falso positivo rate su test non-deterministici è la principal incognita.
- Reflection / dispatch dinamico false negative rate validabile solo in pilota.

**Bassa su:**
- Quantificazione del beneficio "delega rate" (sub-agent meno usato → più usato). È
  un outcome cognitivo dell'utente, non un metrica tecnica deterministica.

**Cose verificate (fatti):**
- Harness baseline PASS=43 (verificato 2026-05-20 post ADR-0001).
- File path live `~/.claude/agents/refactorer.md` (52 righe attualmente, ispezionato).
- Contract `.claude/test-cmd` (TOFU + 3-tier deploy 2026-05-19 swarm-testcmd, validato).
- Pattern anchor harness review-triage-fix (43 anchor 3.2-clean).
- Pattern skill bash 3.2 (`verify.sh`/`weakening-scan.sh`/`triage-state.sh` esistenti).
- Vincolo bash 3.2 memory `feedback_bash32-constraint.md`.
- Razionale MAJOR M-1 cycle 2 pricing-markup-cli memory
  `feedback_micropiano-refactor-cleanup.md` (RESOLVED 2026-05-20).

**Cose assunte:**
- L'LLM Sonnet seguirà il contract di invocazione capture/diff con hit-rate >95%
  (analogia con "tests green before/after", non verificato per questa esatta sequenza).
- Determinism check 3 run è il giusto compromesso (1 run troppo permissivo, 5+
  over-engineering).
- Blast radius via `grep -rln <module>` è proxy ragionevole per "caller diretti"
  (caller indiretti via reflection esclusi, accettato come trade-off MVP).
- `.claude/test-cmd` è disponibile nei progetti dove il refactorer viene invocato
  (verificato per pilota recenti, non per progetti nuovi).
- Format `.refactor-snapshot.txt` è sufficientemente espressivo per i casi di edge
  (test che producono binary output, output >10MB, character non-UTF-8). Edge non
  testati; MVP assume output testuale UTF-8 ragionevole.
