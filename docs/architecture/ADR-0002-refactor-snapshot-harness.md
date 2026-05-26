# ADR-0002 — Behavior-preservation Snapshot Harness per il refactorer agent

**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-refactor-snapshot-harness.md; harness PASS=45; skill self-test PASS=11)
**Authors:** Adriano (architect agent) per Stefano Ferri
**Supersedes:** none
**Superseded by:** none
**Related:**
- `docs/superpowers/specs/2026-05-20-refactor-snapshot-harness-design.md`
- `docs/superpowers/plans/2026-05-20-refactor-snapshot-harness.md`
- `~/.claude/agents/refactorer.md` (target di modifica primaria)
- `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2 Add+Remove rule — non toccata)
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (anchor harness target, PASS=43 post ADR-0001)
- `~/.claude/hooks/approve-test-cmd.sh` (TOFU + 3-tier per `.claude/test-cmd` — riuso del contract)
- `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (Accepted 2026-05-20, ortogonale)
- Memory `feedback_bash32-constraint.md` (vincolo hard per harness)
- Memory `feedback_micropiano-refactor-cleanup.md` (cycle 2 MAJOR causato da refactor cieco; razionale)

---

## 1. Context

Il sub-agent `refactorer` (`~/.claude/agents/refactorer.md`, Sonnet, tools `Read, Edit, Glob,
Grep, Bash`, color giallo) ha oggi un contract di behavior-preservation puramente
prosaico: "Make behavior-preserving changes only. Run the existing test suite and record
the baseline (must be green to start). Re-run tests; confirm identical results." Il check
è un boolean (green → green) e non cattura regressioni silenziose dove il test suite resta
verde *perché incomplete* ma il comportamento osservabile cambia (output formattato
diverso, exit code identico ma stdout silenziosamente alterato, error message ricomposto).

Tre evidenze convergenti motivano l'intervento:

1. **Memory dell'utente.** Il `refactorer` è oggi il sub-agent **meno usato** del sistema.
   La causa esplicita (memory + brief): l'utente non si fida di delegare refactor
   non-triviali perché non c'è garanzia *empirica* di non-regressione behavior-preserving.
   Il green→green check è necessario ma non sufficiente.

2. **Cycle 2 di `pricing-markup-cli` (MAJOR M-1).** Un refactor di consolidazione fixture
   autouse ha *aggiunto* comportamento (duplicazione autouse). Il refactor passava il
   green→green check perché entrambe le fixture facevano lo stesso lavoro (idempotenza
   apparente), ma il *blast radius* mostrava 2 fixture al posto di 1. Un check di
   behavior-preservation snapshot-based avrebbe catched il delta nel runtime layer
   (stesso output ma più side effects nel transcript), o avrebbe richiesto al refactorer
   di esplicitare il REPLACE pre-edit (ortogonale ad ADR-0001).

3. **Pattern v1.2 + ADR-0001 deployati oggi (2026-05-20).** Sono due interventi sullo
   stesso problema (drift dell'intent vs codice) dal lato coder. Il refactorer è il
   *terzo angolo*: drift implicito (silent regression) anziché esplicito (intent
   mismatch). Triple-angle coverage del rischio "code change non corrisponde a intent
   dichiarato".

### Problema architetturale

Il refactor è definito come "behavior-preserving" ma il sistema non ha mai *strumentato*
questa proprietà. Il refactorer si auto-certifica via "tests green before, tests green
after" — un proxy debole. Serve un meccanismo **deterministico e ispezionabile** che
catturi l'output osservabile del codice *prima* del refactor, lo confronti dopo, e fallisca
loud se la differenza è non-zero.

### Direzione

Introdurre un **Behavior-preservation Snapshot Harness**: una skill bash 3.2-clean
(`~/.claude/skills/refactor-snapshot/`) che il `refactorer` agent invoca come gate
nel suo Process. Lo snapshot è l'output testuale (stdout + stderr + exit-code) dei test
case del progetto, eseguiti dal test command già contrattualizzato in `.claude/test-cmd`
(stesso file letto da `~/.claude/hooks/approve-test-cmd.sh`). Diff non-zero ⇒ refactor
ha cambiato comportamento ⇒ refactorer interrompe e segnala.

L'obiettivo è **abilitare la delega di refactor non-triviali al refactorer agent con
fiducia**, sbloccando il sub-agent meno usato del sistema.

### Vincoli ereditati (HARD)

- **Anchor preservation harness `review-triage-fix`:** PASS=43 post ADR-0001
  (2026-05-20). Mai scendere. Target post-feature: PASS=45 (+2 anchor su
  `refactorer.md` structural sweep — vedi Decision §2.7).
- **Bash 3.2.57** per ogni script in `~/.claude/`. Niente assoc array, niente `mapfile`,
  niente `${v^^}`, niente `<()` process substitution. Pattern già consolidato dai 43
  anchor del harness review-triage-fix e dagli helper `verify.sh`, `weakening-scan.sh`,
  `triage-state.sh`.
- **Coesistenza con feature deployati 2026-05-20:** ADR-0001 (Pre-flight Pattern
  Classifier per coder) + review-triage-fix v1.2 Add+Remove rule restano intatti.
  Snapshot harness è **ortogonale** ad entrambi: opera sul refactorer (post-edit
  verification), non sul coder/reviewer (pre-edit declaration / post-edit triage).
- **No backwards-compat shim:** modifiche al `refactorer.md` sostituiscono pulito.
- **Repo NON-git:** vibe-coding-system blueprint repo è non-git per scelta dell'utente;
  `~/.claude/` non è git. Plan non propone operazioni git. Integrazione CI/CD del
  progetto-target è scope futuro.
- **Sub-agent identity invariata:** `refactorer.md` resta Sonnet, tools immutati
  (`Read, Edit, Glob, Grep, Bash`), color giallo.
- **Lingua:** system prompt + skill in inglese (contract); ADR/spec/plan in italiano;
  commit/code in inglese.

### Assunzioni esplicite (non verificate empiricamente)

- La `.claude/test-cmd` contract (riuso dal hook TOFU) è disponibile nei progetti target
  dove il refactorer viene invocato. Verificato per i pilota recenti (swarm-testcmd
  deployato 2026-05-19). Non verificato per progetti nuovi.
- L'output testuale del test command è sufficientemente deterministico (no timestamp,
  no random IDs, no path assoluti incorporati) per produrre snapshot stabili. Per il
  caso non-deterministico esiste override esplicito (vedi Decision §2.8).
- Il `refactorer` LLM (Sonnet) seguirà il contract "pre-snapshot before edit, post-snapshot
  after edit, abort on non-zero diff" con la stessa fedeltà con cui segue oggi
  "tests green before, tests green after". Plausibile (la disciplina test-baseline funziona);
  non verificato per questa esatta sequenza.
- Il blast radius computato come "file modificati nell'edit + loro caller via `grep -rln`"
  è una proxy ragionevole per "test rilevanti". Edge: caller indiretti via reflection /
  dispatch dinamico non catturati — accettato come trade-off MVP.

---

## 2. Decision

Introdurre il **Behavior-preservation Snapshot Harness** come skill bash 3.2-clean
`~/.claude/skills/refactor-snapshot/`, invocata dal `refactorer` agent come gate
nel suo Process. Three-state outcome: PASS (snapshot diff vuoto), FAIL (diff non-zero,
refactor cambia comportamento), UNVERIFIED (test command assente / non-deterministico).
Triple-layer defense con il green→green check esistente come secondary.

### 2.1 Cosa è uno snapshot (Q1)

**Lo snapshot è l'output testuale del test command del progetto target.**

Formato concreto del file snapshot (`.claude/.refactor-snapshot.txt`):

```
EXIT=<exit-code>
STDOUT-SHA256=<hex>
STDERR-SHA256=<hex>
---STDOUT---
<full stdout>
---STDERR---
<full stderr>
```

Razionale:
- **Output testuale** è il proxy più diretto del comportamento osservabile esterno
  (output) + correttezza (exit code). Allineato con la definizione di
  behavior-preservation del refactorer.md attuale ("public outputs and side effects
  identical").
- **stdout/stderr/exit-code** è il triplet canonico di Unix process semantics:
  stack-agnostic, no parsing.
- **SHA256** dei due stream è la baseline rapida del diff (un confronto su 2 hex
  basta per il PASS/FAIL primario; il payload full-text è preservato per diagnostica
  in caso di FAIL).
- **Pure function return values** (Q1 sub-option) sono *deferred* — richiedono
  scaffolding per-stack (importer Python, runner Swift) e duplicano test framework
  esistenti. Scope futuro se MVP risulta insufficiente.
- **AST signatures / call graphs** sono *rejected* — proxy fragili (un refactor
  legittimo cambia call graph) e stack-locked (richiedono parser per linguaggio).
  Vedi Alternatives §3.1.

### 2.2 Tool: build (bespoke bash) vs buy (Q2)

**CHOSEN: bespoke bash 3.2 harness `~/.claude/skills/refactor-snapshot/`.**

Criteri di scelta:

| Opzione | Multi-stack | Zero dep | Multi-agente integr. | Costo manuten. | Verdict |
|---|---|---|---|---|---|
| pytest-snapshot / syrupy | Python only | No (pip dep) | Bridge necessario | Medio | Reject |
| inline-snapshot | Python only | No (pip dep) | Bridge necessario | Medio | Reject |
| jest snapshot | JS/TS only | No (npm dep) | Bridge necessario | Medio | Reject |
| swift-snapshot-testing | Swift only | No (Swift Package) | Bridge necessario | Medio | Reject |
| golden file pattern | Stack-agnostic | Sì | Mediato dall'agent | Basso | Pattern, non tool |
| **Bespoke bash 3.2** | **Stack-agnostic** | **Sì** | **Native** | **Basso** | **CHOSEN** |

Razionale:
- Il sistema multi-agente è esplicitamente multi-stack (`~/.claude/skills/` contiene
  `fastapi-react-vibe`, `swift-vibe`, `swiftui-pro`). Tool stack-locked richiedono
  matrix di adapter, contro il principio "minimal moving parts".
- Bespoke bash riusa il contract `.claude/test-cmd` già live (deploy 2026-05-19
  swarm-testcmd, validato cross-stack). Zero scaffolding aggiuntivo per consumer.
- Il pattern golden file è quello *adottato*, non un tool da installare. Bespoke bash
  ne è l'implementazione minimale.
- Allineato allo stile review-triage-fix (3.2-clean, ok/bad helpers, anchor harness).
  Consistency cognitiva per Stefano + per gli agent.

Alternative scartate dettagliate in §3.2.

### 2.3 Dove vivono gli snapshot (Q3)

**CHOSEN: `.claude/.refactor-snapshot.txt` nel progetto target, gitignored.**

Razionale:
- **Per-progetto** (non centralizzato in `~/.claude/cache/`): traceability con il progetto,
  no race tra worktree/dispatch paralleli, lifecycle legato al lavoro del refactorer
  nel checkout corrente.
- **Gitignored** (non versionato): è un artifact transient del cycle refactor.
  Versionarlo polluiterebbe il repo con file binary-like che cambiano a ogni run.
- **File singolo `.refactor-snapshot.txt`** (non un directory per-test-case): MVP
  semplice; il payload è già un bundle (full stdout/stderr). Granularità file-per-test
  è speculativa — la blast radius (§2.4) seleziona già quali test eseguire.
- **Path identico al pattern v1.2 `.claude/.triage-fix-last.json`**: stessa convenzione
  del repo target per cross-cycle state file. Consistency con il pattern già live.
- Il refactorer aggiunge `.claude/.refactor-snapshot.txt` a `.gitignore` se il progetto è
  git (idempotent, identico al pattern `triage-state.sh` commit). Se non-git, nessun
  side effect (idempotent no-op).

Alternative scartate (§3.3): versionato in repo (pollution), `~/.claude/cache/` esterno
(perde traceability, race condition).

### 2.4 Granularità: blast radius (Q4)

**CHOSEN: blast radius = file modificati nel refactor + loro caller diretti via grep.**

Definizione operativa:
- Pre-edit: il refactorer dichiara l'insieme dei file che sta per modificare (set $F$).
- Caller set $C$ = `grep -rln <module-name>` per ciascun file in $F$, intersezione con file
  test (path matching `test`, `spec`, `tests/`, `__tests__/`).
- Snapshot scope = test command eseguito con env var `RFS_FILTER` (vedi §2.7) per
  restringere ai test che importano/usano $F \cup C$. Se il test command non supporta
  filtering, fallback a test command full (overshoot accettato).

Razionale:
- **Per singolo test** (rejected): troppo fine, richiede parser per individuare singolo
  test case in N framework diversi. Non scala multi-stack.
- **Per modulo** (rejected): proxy ragionevole ma legato a definizione "modulo"
  per-linguaggio. Tossico cross-stack.
- **Per progetto intero** (rejected): overshoot massivo. Refactor di 1 file richiede
  re-eseguire 1000 test se il progetto è grande. Tempo proibitivo.
- **Per blast radius** (CHOSEN): proxy ragionevole, computabile via grep stack-agnostic,
  bounded dal lavoro effettivo del refactor.

Edge: caller indiretti (reflection, plugin, factory) non catturati da grep statico.
**Mitigazione:** se il refactorer rileva uso di reflection/dispatch dinamico nei file in
$F$, escalate a "full project snapshot" (override esplicito, env var `RFS_FULL=1`).
Audit trail: dichiarazione nel report del refactor "blast radius widened to full
because reflection detected in <file>".

### 2.5 Coverage check: quali test eseguire (Q5)

**CHOSEN: tutti i test del progetto via `.claude/test-cmd` (default), con narrowing via
blast radius solo se il refactorer dichiara overhead temporale problematico.**

Razionale operativo:
- **Tutti i test (default)**: safe overshoot, no coverage tooling stack-locked, riuso
  diretto del contract `.claude/test-cmd` già live.
- **Top-N coverage** (rejected): richiede coverage tooling per-stack (pytest-cov,
  jest --coverage, swift coverage). Multi-stack matrix.
- **Test che toccano file modificati** (rejected come default, ammesso come narrowing
  opt-in): richiede coverage map per-progetto. Non disponibile by default.
- **Heuristica AST-based** (rejected): parser stack-locked.

**Override per progetti con test slow:** il refactorer può dichiarare `RFS_FILTER=<pattern>`
nel env del test command per restringere (es. `pytest -k <module>`). Decisione runtime del
refactorer in base a baseline time del pre-snapshot (se >60s, considera filtering).

### 2.6 Flusso TDD del refactorer aggiornato (Q6)

Sostituisce la sezione "Process" di `refactorer.md` con questa sequenza:

1. **Baseline check.** Esegui `.claude/test-cmd`. Se non-zero → STOP, report "tests red
   at baseline, refactor unsafe". (Invariante esistente, preservato.)
2. **Pre-snapshot.** Invoca `~/.claude/skills/refactor-snapshot/scripts/capture.sh PRE`.
   Scrive `.claude/.refactor-snapshot.txt` con EXIT/STDOUT-SHA256/STDERR-SHA256/payload.
3. **Determinism check.** Re-esegui pre-snapshot N=2 volte (totale 3). Se SHA256 stdout
   o stderr cambia tra runs → STOP, output `UNVERIFIED non-deterministic test output`,
   report al user con suggerimento "investigate test flakiness or use RFS_OVERRIDE".
4. **Apply refactor.** Edit focused (≤200 righe per pass, invariante esistente preservato).
5. **Post-snapshot.** Invoca `capture.sh POST`. Scrive `.claude/.refactor-snapshot.txt.post`.
6. **Diff.** Invoca `~/.claude/skills/refactor-snapshot/scripts/diff.sh`. Confronta
   EXIT + SHA256-STDOUT + SHA256-STDERR. Output `PASS` se identici, `FAIL` se diversi.
7. **On FAIL.** STOP. Report al user con `loc=path:line` per ciascuno dei tre delta
   (exit/stdout/stderr) + estratto diff `diff -u` dei payload. Refactor *non* viene
   committed (no-op rispetto al filesystem: l'edit è già su disco, ma il refactorer
   dichiara FAIL e raccomanda revert). HITL gate: l'utente decide se accettare il
   change come "intentional behavior change" (e quindi non era un refactor) o ribaltare.
8. **On PASS.** Refactor è behavior-preserving. Report success: `lines changed`,
   `tests passed`, `snapshot PASS`. Cleanup: rimuovi `.claude/.refactor-snapshot.txt.post`
   (la `.refactor-snapshot.txt` resta come baseline del prossimo cycle, opzionale —
   nel MVP rimuoviamo entrambi per pulizia, lascio scelta nel plan).

Step 1 e 4 sono invarianti esistenti del refactorer.md. Step 2, 3, 5, 6, 7 sono nuovi.
Step 8 è arricchimento dell'esistente "Output Format".

### 2.7 Multi-language strategy (Q7)

**CHOSEN: stack-agnostic single harness, no per-stack adapter, detection automatica via
`.claude/test-cmd`.**

Razionale:
- Il contract `.claude/test-cmd` (deploy swarm-testcmd 2026-05-19) è già il punto di
  detection stack: il progetto target dichiara il proprio test command (es. `pytest -q`,
  `npm test`, `swift test`). Il harness *non sa* qual è lo stack — esegue il comando e
  cattura output.
- **Per-stack adapter** (rejected): introdurrebbe matrix Python/JS/Swift/Go/Rust... senza
  benefit proporzionato. Se in futuro un singolo stack richiede semantic snapshot
  (es. JSON normalizzato per JS), si può aggiungere helper opzionale post-pilota.
- **Auto-detection del stack** (rejected): tentativo di indovinare `pytest` vs `npm test`
  via file presence è fragile e duplica il lavoro che `.claude/test-cmd` già fa.

Estensibilità futura (out of scope MVP):
- Helper opzionali `normalize-python.sh`, `normalize-js.sh` che pre-processano lo stdout
  prima dello SHA256 (es. strip timestamp `\d{4}-\d{2}-\d{2}T...`). Hook via env var
  `RFS_NORMALIZE=<helper-path>`. Non MVP.

### 2.8 Failure mode + override (Q8)

Tre stati di esito del harness:

| Stato | Significato | Azione refactorer |
|---|---|---|
| `PASS` | SHA256 stdout+stderr+exit identici pre/post | Refactor OK, report success |
| `FAIL` | SHA256 diversi su almeno uno dei tre canali | STOP, report drift al user (HITL) |
| `UNVERIFIED` | Pre-snapshot non-deterministico (3 run diversi) | STOP, report flakiness; override possibile |

**Distinguere bug vs snapshot stale:**

Il determinism check (§2.6 step 3) è il discriminator. Se i 3 pre-snapshot consecutivi
producono SHA256 identici → snapshot deterministico, ogni successivo drift è bug del
refactor. Se i 3 pre-snapshot producono SHA256 diversi → snapshot è stale (test flaky,
timestamp, random) → `UNVERIFIED` con flag.

**Override esplicito:**

File `.claude/refactor-snapshot-override` (opzionale, presente solo se utente lo crea
deliberatamente). Format:

```
REASON: <one-line justification>
SCOPE: <stdout|stderr|exit|all>
EXPIRES: <YYYY-MM-DD>
```

Se presente, il harness ignora la differenza nei canali dichiarati in SCOPE e fa
override a `PASS` con flag `OVERRIDE-ACTIVE`. Audit trail: il refactorer cita il file +
REASON nel report.

**No auto-override:** il file va creato dall'utente (HITL gate). Il refactorer *non* lo
crea mai. Il refactorer può *suggerire* la creazione nel suo report di FAIL ("se la
differenza è un timestamp atteso, considera override con SCOPE: stdout").

**Audit trail:**

Il file `.claude/.refactor-snapshot.txt` (pre-snapshot) sopravvive a un PASS come
baseline del prossimo cycle (opzionalmente — cleanup MVP rimuove entrambi). In caso di
FAIL, il file `.refactor-snapshot.txt.post` resta su disco per ispezione user, e il
refactorer lo cita nel report con path assoluto.

### 2.9 Modifiche puntuali ai file

- **Create skill `~/.claude/skills/refactor-snapshot/`:**
  - `SKILL.md` — frontmatter + body con invocation contract.
  - `scripts/capture.sh` — bash 3.2, esegue `.claude/test-cmd`, scrive snapshot file.
  - `scripts/diff.sh` — bash 3.2, confronta pre/post snapshot, exit 0/1/2 per
    PASS/FAIL/UNVERIFIED.
  - `tests/run-tests.sh` — bash 3.2, harness self-test della skill (anchor preservation
    pattern, identico stile review-triage-fix).
- **Modify `~/.claude/agents/refactorer.md`:** sostituisci la sezione `## Process`
  (righe 25-31 attuali) con la sequenza §2.6 (8 step). Append sezione `## Snapshot
  Harness Integration` con riferimento alla skill. Aggiorna `## Edge Cases` con la
  voce "Snapshot UNVERIFIED — non-deterministic test output".
- **Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh`:** append nuovo
  blocco `# --- Task 7: refactorer.md snapshot harness section ---` con 2 anchor su
  `refactorer.md` (presence di `Snapshot Harness Integration` literal + presence di
  `refactor-snapshot` skill reference). Cumulative PASS=43 → PASS=45.

**Nota architetturale:** estendere il harness `review-triage-fix` a leggere un terzo
file (`refactorer.md`, dopo `SKILL.md` e `coder.md`) è coerente con il precedente di
ADR-0001 §3.3 (sub-question). La skill `review-triage-fix` ha già autorità sulla qualità
degli agent che dispatcha (debugger, refactorer, coder); aggiungere structural anchor
su `refactorer.md` è naturale.

### 2.10 Modifiche NON fatte

- **NO modify `~/.claude/skills/review-triage-fix/SKILL.md`** — v1.2 Add+Remove rule
  resta. Ortogonale al snapshot harness (regola del coder, non del refactorer).
- **NO modify `~/.claude/agents/coder.md`** — ADR-0001 Pre-flight Pattern Classifier
  invariato. Il coder non usa snapshot.
- **NO modify `~/.claude/agents/reviewer.md`** — Pattern-drift check ADR-0001 invariato.
  Il reviewer non usa snapshot direttamente (ma può citare il report del refactorer
  come evidenza in review).
- **NO modify `~/.claude/agents/debugger.md`** — il debugger opera su bug, non su
  refactor. Snapshot non applicabile.
- **NO modify `~/.claude/hooks/approve-test-cmd.sh`** — il harness *riusa* il contract
  `.claude/test-cmd` ma non interagisce con TOFU. Il file `.claude/test-cmd` deve
  pre-esistere ed essere già approvato (TOFU + 3-tier deploy 2026-05-19); se assente,
  snapshot UNVERIFIED + abort.
- **NO modify `~/.claude/settings.json`** — nessun hook nuovo, nessun permission rule
  nuovo.
- **NO modify `.mcp.json`** — nessun MCP nuovo.

### 2.11 Lingua

System prompt `refactorer.md` e skill files (`SKILL.md`, `capture.sh`, `diff.sh`,
`run-tests.sh`) in inglese (contract). ADR, spec, plan, memory entry in italiano.
Allineato a global rule "codice e commit in inglese; testo all'utente in italiano".

---

## 3. Alternatives considered

### 3.1 Cosa è uno snapshot (Q1)

**a) Test output testuale (stdout/stderr/exit-code) (CHOSEN).** Stack-agnostic, proxy
diretto di behavior osservabile, riuso `.claude/test-cmd`. Rischio: test non
deterministici (mitigato da determinism check + override).

**b) Pure function return values** — *Rejected come MVP, deferred*. Richiede scaffolding
per-stack (importer Python via `importlib`, runner Swift via `swift run`). Duplica il
test framework esistente. Possibile estensione post-pilota se MVP risulta insufficiente
per casi edge (es. progetti library-only senza test integration).

**c) AST signatures** — *Rejected*. Refactor legittimi *cambiano* l'AST (extract
method, rename var, inline function). AST signature è una proxy non-allineata con la
definizione di behavior-preserving (preserva *behavior*, non *struttura*). Stack-locked
(richiede parser per linguaggio).

**d) Function call graphs** — *Rejected*. Cambiano legittimamente in refactor (call
graph è proprio il target del refactor). Same problem di (c).

**e) Combinazione di (a) + (b) + (c)** — *Rejected come MVP*. Over-engineering. (a) è
sufficiente per il MVP; estensioni successive se evidenza pilota lo richiede.

### 3.2 Tool: buy vs build (Q2)

**a) Bespoke bash 3.2 stack-agnostic (CHOSEN).** Vedi tabella §2.2.

**b) pytest-snapshot / syrupy (Python)** — *Rejected*. Stack-locked (Python only).
Matrix di adapter cross-stack proibitiva. Richiede pip dep nel progetto target.

**c) inline-snapshot (Python)** — *Rejected*. Stack-locked. Modifica il sorgente del
progetto target inserendo snapshot inline — invasivo, non-removable senza VCS.
Inadatto per behavior-preservation gate (modifica il sorgente che dovrebbe restare
identico).

**d) jest snapshot (JS/TS)** — *Rejected*. Stack-locked. Stesso problema di (b).

**e) swift-snapshot-testing (Swift)** — *Rejected*. Stack-locked. Richiede Swift Package
dep. Inadatto per Python/JS progetti.

**f) Pattern golden file generico (Go-style)** — *Adopted come pattern, non come tool*.
La scelta CHOSEN (bash 3.2) *è* l'implementazione minimale del golden file pattern.

### 3.3 Dove vivono gli snapshot (Q3)

**a) `.claude/.refactor-snapshot.txt` per-progetto gitignored (CHOSEN).** Consistency
con `.claude/.triage-fix-last.json` (review-triage-fix). Lifecycle legato al progetto.

**b) Versionato in repo target** — *Rejected*. Snapshot è transient (cambia a ogni
cycle refactor). Pollution del VCS history con artifact binary-like. Anti-pattern
golden file (golden file *test fixture* sì, golden file *transient cycle artifact* no).

**c) `~/.claude/cache/refactor-snapshot/<project-hash>/`** — *Rejected*. Cache esterna
perde traceability (chi guarda `~/.claude/cache/` quando il refactor fallisce?). Race
condition con worktree paralleli sullo stesso project hash. Lifecycle disaccoppiato dal
progetto (cleanup quando?).

**d) `/tmp/refactor-snapshot-<pid>/`** — *Rejected*. Volatile (perso al reboot, allo
shutdown del dispatch session). Inadatto per cross-cycle baseline.

### 3.4 Granularità (Q4)

**a) Blast radius = file modificati + caller diretti via grep (CHOSEN).** Bounded dal
lavoro effettivo, computabile stack-agnostic, proxy ragionevole.

**b) Per singolo test case** — *Rejected*. Richiede parser per individuare test case.
Stack-locked.

**c) Per modulo** — *Rejected*. "Modulo" è concept stack-specifico (Python module vs
JS module vs Swift module). Tossico cross-stack.

**d) Per progetto intero** — *Rejected come default*. Overshoot temporale (re-eseguire
1000 test per modificare 1 file). Ammesso come fallback override (`RFS_FULL=1`) per
casi reflection.

**e) Per file modificati (no caller expansion)** — *Rejected*. Troppo stretto: refactor
del file $f$ può rompere comportamento dei caller di $f$, e i test che testano i caller
sono il vero gate.

### 3.5 Coverage check (Q5)

**a) Tutti i test (CHOSEN come default).** Safe overshoot. Riuso `.claude/test-cmd`.

**b) Top-N test per coverage statement** — *Rejected*. Coverage tooling stack-locked
(pytest-cov, jest --coverage). Matrix.

**c) Test che toccano file modificati (via coverage map)** — *Rejected come default,
ammesso come narrowing opt-in*. Richiede coverage map pre-computata. Non disponibile
by default.

**d) Heuristica AST-based** — *Rejected*. Parser stack-locked.

### 3.6 Flusso TDD (Q6)

**a) Sequenza 8-step §2.6 (CHOSEN).** Esplicita determinism check (step 3) e on-FAIL
HITL gate (step 7).

**b) Sequenza minimale (baseline → refactor → diff)** — *Rejected*. Manca determinism
check → falso negativo (test flaky catalogati come "refactor changed behavior" senza
distinguere).

**c) Snapshot post-only, confronto con repo VCS history** — *Rejected*. Richiede git
+ history pulito. Non applicabile a progetti non-git o con dirty working tree.

### 3.7 Multi-language strategy (Q7)

**a) Stack-agnostic single harness via `.claude/test-cmd` (CHOSEN).** Riuso contract
già live. Zero scaffolding per-stack.

**b) Per-stack adapter Python + Swift + JS** — *Rejected come MVP*. Matrix
maintenance. Possibile estensione futura solo se MVP risulta insufficiente.

**c) Auto-detection del stack via file presence** — *Rejected*. Fragile, duplica il
lavoro di `.claude/test-cmd`. Anti-pattern.

### 3.8 Failure mode + override (Q8)

**a) Three-state PASS/FAIL/UNVERIFIED + override file `.claude/refactor-snapshot-override`
(CHOSEN).** Triple discriminator (determinism check + diff check + manual override).

**b) Boolean PASS/FAIL senza UNVERIFIED** — *Rejected*. Confonde test flakiness con
refactor regression. Falsi positivi sui progetti con test non-deterministici.

**c) Auto-override quando il refactorer rileva timestamp / random ID nello stdout** —
*Rejected*. Rischio di auto-override silente che maschera regressioni reali. HITL gate
è il pattern corretto (allineato a CLAUDE.md global "HITL gate sempre prima di ...
modifica schema DB, eliminazioni permanenti").

**d) Hook PreToolUse che blocca Edit se snapshot non capturato** — *Rejected*. Stesso
razionale di ADR-0001 §3.1.c: hook bash 3.2 non può ispezionare il response LLM, e gli
hook PreToolUse Edit ricevono `tool_input` JSON. Filosofia "enforcement primario è
disciplina + gate skill-based, non hook hard al filesystem" (consistente con tutto il
resto del sistema).

---

## 4. Consequences

### 4.1 Positive

- **Sblocca delega di refactor non-triviali al refactorer.** Risolve la causa root
  (memory dell'utente): non c'è garanzia di non-regressione. Snapshot harness *è* la
  garanzia, deterministica e ispezionabile.
- **Cattura il fail mode cycle 2 pricing-markup-cli alla source.** Refactor che cambia
  comportamento → SHA256 diversi → FAIL. Triple-angle coverage (coder pre-flight
  classifier ADR-0001 + reviewer Add+Remove triage v1.2 + refactorer snapshot
  ADR-0002).
- **Pattern riusabile per altri agent.** Se in futuro vogliamo un "behavior-preservation
  check" anche per `debugger` (fix non deve cambiare comportamento di codice non
  bug-target) o `tester` (nuovo test non deve influenzare run di test esistenti),
  la skill `refactor-snapshot` si può adattare.
- **Stack-agnostic by construction.** Riuso `.claude/test-cmd` contract già validato
  cross-stack (Python pricing-markup-cli, Swift swift-vibe, JS fastapi-react-vibe).
- **Zero nuove dipendenze.** Solo bash 3.2, `sha256sum` (o `shasum -a 256` su macOS),
  `diff` (POSIX). Niente pip/npm/swift pkg deps.
- **Anchor preservation rispettato.** PASS=43 → PASS=45 (+2 anchor structural per
  `refactorer.md`). Additivo, no regressione.
- **Coexistenza pulita con ADR-0001 + v1.2.** Ortogonali (operano su agent diversi).
  Nessuna race condition.
- **Audit trail completo.** `.refactor-snapshot.txt`, `.refactor-snapshot.txt.post`,
  `.refactor-snapshot-override` (se presente), report del refactorer — quattro
  artefatti ispezionabili per ricostruire ogni cycle.

### 4.2 Negative

- **Overhead temporale per cycle refactor.** Determinism check richiede 3 run del test
  command + 1 post-run = 4 run totali per cycle. Su progetti con test slow (>30s) il
  refactor cycle passa da ~30s (1 run baseline + 1 post-run) a ~2 min. Mitigazione:
  `RFS_FILTER` narrow scope (§2.5 override). Non eliminato.
- **Falsi positivi su test non-deterministici.** Progetti con test che includono
  timestamp / random ID / path assoluti producono `UNVERIFIED`. Il refactorer deve
  abortire o l'utente deve creare override. Friction-inducing finché il pilota non
  produce best-practice "test cleanup pre-refactor". Severity: medium.
- **Dipendenza da `.claude/test-cmd` pre-esistente.** Se il progetto target non ha
  test-cmd configurato (TOFU not done), snapshot UNVERIFIED → refactor abortito.
  Forza il user a deployare test-cmd prima. Allineato pratica esistente (
  approve-test-cmd hook) ma è gate aggiuntivo.
- **Coupling minore harness `review-triage-fix` ↔ `refactorer.md`.** Il harness ora
  legge 3 file (`SKILL.md`, `coder.md`, `refactorer.md`). Se in futuro rinominiamo
  refactorer.md, 2 anchor da aggiornare. Costo accettabile (consistency con coupling
  coder.md già stabilito in ADR-0001).
- **MVP non gestisce snapshot per pure function return values.** Progetti library-only
  senza test integration (es. tiny util library) non beneficiano. Deferred (vedi §3.1).
- **Blast radius via grep miss caller indiretti via reflection.** Override `RFS_FULL=1`
  esiste ma richiede giudizio refactorer. Possibile falso negativo se refactorer non
  rileva reflection. Severity: medium.

### 4.3 Neutral

- **Plan TDD scritto dall'architect resta agnostico al snapshot.** Architect non
  pre-dichiara snapshot expectation negli step del plan; è runtime, dal refactorer.
  Allineato a pattern ADR-0001 (architect agnostico al classifier).
- **MEMORY.md aggiornato.** Nuova voce "Refactor snapshot harness" in sezione Project.
- **Orchestrator invariato.** Dispatcha `refactorer` come prima; il refactorer ora
  produce report più ricco (PASS/FAIL/UNVERIFIED + audit artifacts).
- **Sub-agent identity invariata.** Refactorer resta Sonnet, tools immutati, color
  giallo.

### 4.4 Open questions (validation pending)

- **Hit-rate compliance:** % di cycle refactor in cui il refactorer effettivamente
  invoca capture.sh prima/dopo edit. Target: >95%. Validabile solo nell'uso organico.
- **Falso positivo rate su test non-deterministici:** quanti progetti pilota hanno test
  flaky tali da forzare `UNVERIFIED` o override? Validabile su 3-5 cycle pilota.
- **Blast radius narrow scope efficacia:** quanto tempo risparmia `RFS_FILTER` rispetto a
  full test command? Target: ≥3x speedup sui progetti grandi. Validabile con metriche
  pilota.
- **Reflection / dispatch dinamico false negative rate:** quanti refactor passano
  snapshot ma rompono behavior in caller indiretti? Validabile post-pilota con review
  dei MAJOR successivi.
- **Override file `.refactor-snapshot-override` usage rate:** se troppi cycle richiedono
  override, il harness è troppo strict. Se nessun cycle lo usa, è una feature non
  necessaria. Target sweet spot: 5-15% dei cycle. Validabile post-pilota.

---

## 5. References

- `~/.claude/agents/refactorer.md` (target di modifica primaria)
- `~/.claude/skills/refactor-snapshot/` (skill da creare)
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (target +2 anchor)
- `~/.claude/hooks/approve-test-cmd.sh` (contract `.claude/test-cmd` riuso)
- `docs/vibe-coding-system.md` sez. 3.x (8 sub-agent), sez. 8 (skill), sez. 11
  (workflow concept→code)
- `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (Accepted
  2026-05-20, ortogonale)
- `docs/superpowers/specs/2026-05-19-swarm-testcmd-design.md` (TOFU + 3-tier per
  `.claude/test-cmd`)
- `docs/superpowers/specs/2026-05-19-review-triage-fix-design.md` (pattern anchor
  harness)
- Memory `feedback_micropiano-refactor-cleanup.md` (RESOLVED 2026-05-20; razionale
  cycle 2 MAJOR)
- Memory `feedback_bash32-constraint.md` (vincolo bash 3.2 invariante)
- Field test `docs/field-test-2026-05-18.md` (storia pilota)
