# ADR-0004 — Pre-flight Pattern Enforce Hook

**Status:** Accepted — 2026-05-20 (implemented via plan 2026-05-20-pre-flight-pattern-enforce-hook.md; harness review-triage-fix PASS=48; dedicated harness PASS=10)
**Authors:** Adriano (architect agent) per Stefano Ferri
**Supersedes:** none
**Superseded by:** none
**Related:**
- `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (chiude il gap di enforcement della disciplina classifier)
- `docs/superpowers/specs/2026-05-20-pre-flight-pattern-enforce-hook-design.md`
- `docs/superpowers/plans/2026-05-20-pre-flight-pattern-enforce-hook.md`
- `~/.claude/hooks/stop-gate.sh`, `~/.claude/hooks/approve-test-cmd.sh` (coesistenza hook esistenti)
- Memory `feedback_bash32-constraint.md` (vincolo per script live)

---

## 1. Context

ADR-0001 ha introdotto il **pre-flight pattern classifier**: prima di ogni tool call
`Edit`/`Write`, il `coder` agent deve emettere una riga `PATTERN: <CATEGORY> | ...` (4
categorie ADD/REMOVE/REPLACE/MODIFY). La disciplina è hard-coded nel system prompt di
`~/.claude/agents/coder.md` (righe 25-52) ed è oggi enforced via **three-layer**:

1. system prompt (`coder.md` linee 26-52, "you MUST emit")
2. reviewer post-hoc check (pattern-drift, item 5 di `reviewer.md`)
3. `review-triage-fix` v1.2 Add+Remove rule (safety net per `REPLACE`)

**Gap residuo identificato in audit 2026-05-20:**

- Il livello 1 è **self-discipline**: niente blocca il `coder` se omette il header. Sotto
  context pressure, prompt lunghi, dispatch in worktree paralleli, l'LLM può sorvolare.
- Il livello 2 (reviewer) opera **post-hoc**: il filesystem è già scritto, il tool call è
  già passato. La cattura è in cycle successivo, non immediate.
- Per **parallel coders in worktree** (sez. 2 di `vibe-coding-system.md`), il reviewer
  spesso non ha il transcript completo di tutti i coder — il check di coerenza
  `PATTERN:`-vs-diff può saltare silenziosamente.

Conseguenza: la garanzia ADR-0001 è "best effort" del coder, non gate strutturale.
Ricomparire il drift osservato nel cycle 2 di pricing-markup-cli (memory
`feedback_micropiano-refactor-cleanup`, RESOLVED) resta possibile in finestre di
attenzione carica.

**Direzione:** introdurre un **hook `PreToolUse` bash** in `~/.claude/hooks/` che, prima
di ogni tool call `Edit`/`Write`, ispeziona il transcript recente (sliding window) e
**blocca** l'invocazione se non trova un `PATTERN:` header valido che precede l'edit.
Promuove la disciplina classifier da contract testuale a **gate runtime** a livello di
tool call, complementare ai 3 layer esistenti.

### Vincoli ereditati

- **Anchor preservation harness `review-triage-fix`:** PASS=47 deve restare ≥ 47.
- **Bash 3.2.57 compat** per ogni hook in `~/.claude/hooks/`. Niente assoc array,
  `mapfile`, `${v^^}`, `<()`. Solo `grep`/`awk`/`sed`/`jq`.
- **Coesistenza con hook esistenti.** `stop-gate.sh` (PostToolUse Stop), `approve-test-cmd.sh`
  (utility user-invoked), `migrate-trust-paths.sh` (utility). Il nuovo hook è `PreToolUse`
  → diverso event, no race.
- **Fail-open per default su errore interno.** Identico pattern di `stop-gate.sh` (spec
  §7): se l'hook crasha, non bloccare l'utente.
- **HITL ban nel design phase:** auto mode, no gate intermedio nel piano.
- **Repo NON-git:** no commit step.

### Assunzioni esplicite (non verificate empiricamente)

- **L'hook PreToolUse di Claude Code riceve via stdin JSON contenente `tool_name`,
  `tool_input` e (cruciale) un campo accessibile al transcript recente.** Da hook
  contract documentato (`code.claude.com/docs`): `PreToolUse` riceve un JSON con almeno
  `session_id`, `tool_name`, `tool_input`, `cwd`. Il **transcript completo NON è**
  passato per stdin in modo robusto cross-version. Assunzione: il `session_id` è
  sufficiente per derivare un transcript file path (es. `~/.claude/projects/<encoded>/...`
  contiene il `*.jsonl` della sessione) e l'hook può leggerlo. Se questa assunzione
  cade, il fallback è il **marker file** scritto dal coder (vedi §2.2 alternative).
- **L'hook esegue in <100ms typical.** Bash + `grep -E` + `tail` su un file jsonl di
  pochi MB è sotto 100ms in misurazioni preliminari (non verificato in questo audit).
- **Il `coder` agent emette `PATTERN:` come testo nel messaggio assistant immediatamente
  precedente al tool call.** Disciplina ADR-0001 esplicitamente questo pattern; il hook
  cerca nel transcript il header nelle ultime N entry.
- **Identificare "il dispatch è il coder agent" è fattibile tramite `subagent_type` nel
  transcript jsonl.** Verificato: il jsonl session log include `subagent_type` per messaggi
  di sub-agent. Se questo campo manca per orchestrator edit, l'hook **bypassa di default**
  (no false positive su orchestrator).

---

## 2. Decision

Introdurre il **hook `pre-flight-pattern-enforce.sh`** in `~/.claude/hooks/`, registrato
in `~/.claude/settings.json` come `PreToolUse` su tool matcher `Edit|Write|MultiEdit`,
con logica **block-on-missing** strict per dispatch coder + **fail-open** su orchestrator.

### 2.1 Risposta alle 7 domande architetturali

#### Q1 — Source of truth per il PATTERN: header

**Transcript file della sessione corrente, derivato da `session_id`.**

L'hook PreToolUse riceve JSON stdin con `session_id`, `cwd`, `tool_name`, `tool_input`,
e (in versioni recenti del CLI) un campo `transcript_path` che punta direttamente al
jsonl della sessione. Path fallback derivable: encoding cwd → directory in
`~/.claude/projects/<encoded-cwd>/` contenente i jsonl.

Letturra: `tail -n <WINDOW> "$TRANSCRIPT" | jq -r 'select(.type=="assistant") | .message.content[]? | .text? // empty' | grep -E '^PATTERN: (ADD|REMOVE|REPLACE|MODIFY) \|'`.

Alternative scartate vedi §3.1.

#### Q2 — Sliding window dimension

**Window = ultimi 6 messaggi assistant non-tool-result** (configurabile via env
`PATTERN_ENFORCE_WINDOW`, default 6).

Razionale:
- Troppo piccolo (1): false positive se coder dichiara PATTERN, fa Read/Grep, poi Edit
  — l'header è "vecchio".
- Troppo grande (50): false negative — `PATTERN: ADD` di un Edit precedente match per
  un nuovo Edit di tipo diverso.
- **6** = un Edit + 5 Read/Grep/Bash di context-gathering tipici. Allineato al pattern
  osservato del coder in 2026-05-20 dispatches (Read 2-3 file → emit PATTERN → Edit).

Implementazione: l'hook legge gli ultimi N assistant messages, NON i tool_result/user
messages (jq filter `.type=="assistant"`).

#### Q3 — Block vs warn

**Block strict per dispatch coder; warn-only altrimenti.**

- Se `subagent_type == "coder"` nel transcript recente E manca un `PATTERN:` valido nella
  window → exit con `{"decision":"block","reason":"..."}` (PreToolUse hook contract:
  exit 0 + JSON decision block).
- Se non identificato come coder (orchestrator, altro agent, missing field) → fail-open,
  exit 0 silent (no block, opzionale stderr warn loggato in `~/.claude/state/pattern-enforce/`).

Razionale: il coder è l'unico agent con disciplina classifier hard-coded (ADR-0001).
Bloccare orchestrator/architect/reviewer su Edit (legittimi) sarebbe friction-puro.

Combination: **block strict ma con bypass mechanism** (Q5) per casi legitimi.

#### Q4 — Scope: coder vs altri agent

**Distinzione via `subagent_type` nel transcript jsonl.**

L'hook scansiona la window e cerca il primo messaggio assistant che dichiari il subagent
context. Tre casi:

1. `subagent_type == "coder"` presente → **enforce strict** (block on missing).
2. `subagent_type` presente ma diverso (`architect`, `reviewer`, `debugger`, etc.) →
   **bypass silent** (no enforcement; quegli agent non hanno la disciplina classifier).
3. `subagent_type` assente (orchestrator session diretta) → **bypass silent** (no block;
   l'orchestrator può Edit liberamente).

Edge: messaggi vecchi della stessa sessione hanno `subagent_type` di un dispatch
precedente. Mitigazione: l'hook guarda solo nella window (ultimi N), che cattura il
"current speaker".

#### Q5 — Bypass mechanism

**Tre layer di bypass, dal più granulare al più drastico:**

1. **Env var per single tool call:** `PATTERN_ENFORCE=off` impostato dal coder/orchestrator
   prima del tool call. L'hook legge `os.environ` ed esce 0 immediatamente. Usabile in
   transcript via shell escape se serve, ma richiede l'env propagato (rare). Soft escape.
2. **File flag globale:** `~/.claude/state/pattern-enforce/disabled` (touch il file →
   disable; rm → re-enable). Bypass per troubleshooting/maintenance senza editare
   `settings.json`. Persiste tra sessioni — l'utente è responsabile di pulirlo.
3. **Disabilitazione completa via settings.json:** rimuovere l'entry hook PreToolUse.
   Ultima risorsa, equivalente a uninstall del hook.

In tutti i casi di bypass l'hook logga in `~/.claude/state/pattern-enforce/audit.log`
(append-only, 1 riga per skip) per audit-trail.

#### Q6 — Validation regex e edge case REPLACE-incomplete

**Regex strict:** `^PATTERN: (ADD|REMOVE|REPLACE|MODIFY) \|`

- Match strict del prefix + categoria + separator `|`.
- Validazione **forma**, non semantica: l'hook non parsa il payload, non verifica
  `path:line` consistente con `tool_input.file_path`. Quel deep-check resta al reviewer
  (item 5 di reviewer.md, layer 2 di ADR-0001).
- **REPLACE-incomplete (manca `Remove:`):** l'hook **non blocca** questo caso specifico.
  Razionale: validation semantica del payload è scope creep — basta che il header sia
  presente e ben formato. La regola v1.2 `Add+Remove rule` resta tertiary safety net post-hoc.
  Trade-off accepted: l'hook è gate pre-edit per la *presenza* del classifier, non per la
  *completezza* del payload (defer al reviewer).

Estensione futura v1.1: possibile arricchire la regex a `^PATTERN: REPLACE \| Add: .+ \| Remove: .+`
per catturare REPLACE-incomplete pre-edit. Defer per non gold-plate v1.0.

#### Q7 — Performance

**Target <100ms typical, fail-open su slow path.**

Implementazione:
- `cat /dev/stdin | jq -r '.session_id, .cwd, .tool_name'` (1 jq invocation).
- Derive `transcript_path` da `session_id` (~5ms file lookup).
- `tail -n 200 "$TRANSCRIPT" | jq -r '...' | grep -E '...'` su file tipicamente <5MB,
  tail+jq+grep <50ms su macOS M-series.
- Total expected: 30-80ms typical, hard timeout interno via `timeout 2s` per fail-open
  su slow path (analogo a `stop-gate.sh` line 78-87 pattern).

Misurazione concreta nel piano (Task 6: benchmark verify).

### 2.2 Architettura del hook

```
~/.claude/hooks/pre-flight-pattern-enforce.sh    (executable bash 3.2-clean)
~/.claude/hooks/tests/pre-flight-pattern-enforce.sh    (test harness deterministico)
~/.claude/state/pattern-enforce/                  (audit.log, disabled flag)
~/.claude/settings.json                           (entry PreToolUse matcher Edit|Write|MultiEdit)
```

**Hook contract input (stdin JSON):**

```json
{
  "session_id": "abc123...",
  "cwd": "/Users/.../project",
  "tool_name": "Edit",
  "tool_input": {"file_path": "...", "old_string": "...", "new_string": "..."},
  "transcript_path": "/Users/.../.claude/projects/<enc>/abc123.jsonl"
}
```

**Hook contract output:**

- Allow: `exit 0` + empty stdout.
- Block: `exit 0` + stdout `{"decision":"block","reason":"<msg>"}`.
- Internal error: stderr message + `exit 0` (fail-open).

### 2.3 Coesistenza con hook esistenti

| Hook | Event | Tool matcher | Conflict risk |
|---|---|---|---|
| `pre-flight-pattern-enforce.sh` (new) | PreToolUse | `Edit\|Write\|MultiEdit` | — |
| `stop-gate.sh` | Stop | `*` | None — diverso event |
| `approve-test-cmd.sh` | (user-invoked, not hook entry) | — | None |
| `migrate-trust-paths.sh` | (user-invoked, not hook entry) | — | None |
| `auto-format.sh` | PostToolUse | `Edit\|Write` | None — Post vs Pre |
| `backup-before-deploy.sh` | PreToolUse | (different matcher) | Low — entrambi PreToolUse ma matcher possibly distinct; chained execution safe |
| `protect-files.sh` | PreToolUse | (different) | Low — chained, fail-fast: se protect blocca, pattern-enforce non gira (acceptable) |

Ordering: Claude Code esegue hook PreToolUse in ordine di registrazione `settings.json`.
**Decisione:** registrare `pre-flight-pattern-enforce.sh` **dopo** `protect-files.sh` e
`backup-before-deploy.sh`. Razionale: protect-files (security boundary) è top priority;
pattern-enforce (governance) viene dopo. Se un Edit è già bloccato da protect-files,
pattern-enforce non viene eseguito — safe.

### 2.4 Anchor preservation strategy

Il harness `review-triage-fix` (PASS=47) NON osserva i file hook. Per proteggere il nuovo
hook da regressioni accidentali, decisioni:

- **Test harness dedicato:** `~/.claude/hooks/tests/pre-flight-pattern-enforce.sh` con
  fixture JSON di esempio + 6-8 case (block valid, allow valid, bypass via flag, bypass
  via env, fail-open su transcript inesistente, non-coder skip, malformed JSON,
  performance smoke). Non integrato in `review-triage-fix` harness — è un harness
  parallelo invocato manualmente o da future skill di system-validation.
- **Anchor structural in `review-triage-fix` harness:** +1 anchor `grep -q -- 'pre-flight-pattern-enforce'`
  in `~/.claude/settings.json` per verificare che l'entry hook resti registrato.
  Trade-off: lega `review-triage-fix` a un terzo file (oltre `SKILL.md` e `coder.md` di
  ADR-0001), ma il principio "review-triage-fix ha autorità sulla qualità dello stack
  coder" si estende (ADR-0001 §3.3 sub-question).

**Harness PASS=47 → PASS=48** (+1 anchor su `settings.json`).

### 2.5 Lingua

Hook script in bash con comment in inglese (codice = inglese, regola globale).
Reason field del block message in italiano (utente-facing). Spec, plan, memory in italiano.
ADR in italiano. Allineato a Stefano global rule.

---

## 3. Alternatives considered

### 3.1 Source of truth per il PATTERN: header (Q1)

**a) Transcript file via `session_id` / `transcript_path` (CHOSEN).** Single source of
truth nativa di Claude Code, no infrastructure aggiuntiva, leggibile cross-version.

**b) Marker file scritto esplicitamente dal coder prima del tool call** — *Rejected*.
Richiede modifica al system prompt del coder per emettere `Bash: echo "PATTERN: ..." > /tmp/<sid>.pattern`.
Aggiunge tool call extra ad ogni edit, complica il pattern (Bash → Edit, non solo Edit),
e introduce race condition tra parallel coders in worktree (chi scrive `/tmp/<sid>.pattern`?
serve namespacing). Stato file = state externo da pulire, drift inevitabile.

**c) Variabile env propagata dal coder all'hook** — *Rejected*. Le env var non
attraversano da assistant message a hook bash process in modo robusto. Claude Code non
espone meccanismo documentato per "agent set env var visible to hook". Anti-pattern.

**d) Sezione system_prompt esposta all'hook** — *Rejected*. Il sub-agent system prompt
non è esposto a PreToolUse hook nativamente. L'hook non può "vedere" il contract del
coder; può solo leggere il transcript (vedi a).

### 3.2 Sliding window dimension (Q2)

**a) Window = 6 ultimi assistant messages (CHOSEN).** Empiricamente bilanciato per
pattern osservato del coder (Read context-gathering → emit PATTERN → Edit).

**b) Window = 1 (solo ultimo)** — *Rejected*. Troppo strict: coder che fa Read tra
PATTERN e Edit è realtà comune. Falserebbero positive ad alto rate.

**c) Window = intera sessione** — *Rejected*. Falsi negative: PATTERN dichiarato 30
edit fa match per un Edit nuovo di categoria diversa. Distorce il contract "1 PATTERN
per tool call".

**d) Window time-based (ultimi 30s)** — *Rejected*. Time non è una metrica intrinseca
del jsonl (timestamp variabili per LLM latency). Count-based è deterministico.

### 3.3 Block vs warn (Q3)

**a) Block strict per coder, warn-silent altri (CHOSEN).** Friction mirata. Coder è
l'unico agent con disciplina hard-coded; altri non meritano block.

**b) Warn-only sempre** — *Rejected*. Non chiude il gap di enforcement: stesso "best
effort" attuale, solo aggiunge rumore stderr. Zero benefit incrementale rispetto al
status quo ADR-0001.

**c) Block sempre (anche orchestrator)** — *Rejected*. L'orchestrator legittimamente fa
Edit senza disciplina classifier (es. update doc, MEMORY.md). Bloccarlo = friction puro,
genera bypass forzati che disabilitano la feature.

**d) Block + auto-emit fallback `PATTERN: MODIFY | <auto>`** — *Rejected*. Anti-pattern:
auto-completion vanifica il valore cognitivo del classifier (ADR-0001 §4.1 — il valore è
*forzare il coder a pensare*). Auto-emit lo restituisce a no-op.

### 3.4 Scope coder vs altri (Q4)

**a) `subagent_type == "coder"` discrimination (CHOSEN).** Field nativo del jsonl,
deterministico, no marker aggiuntivo.

**b) Marker injection nel system prompt del coder** — *Rejected*. Richiede mod al prompt,
escapable dal LLM (può omettere il marker), e duplicato del meccanismo `subagent_type`
già presente.

**c) Enforce su tutti gli agent** — *Rejected*. Solo coder ha la disciplina ADR-0001;
altri sub-agent non hanno contract `PATTERN:`. Estendere a tutti = imporre disciplina che
non c'è.

### 3.5 Bypass mechanism (Q5)

**a) Tre layer (env + file flag + settings.json) (CHOSEN).** Granularità su use case:
single-call (env), session/maintenance (file), permanent disable (settings.json). Ognuno
ha log/audit-trail.

**b) Solo file flag** — *Rejected*. Manca granularità single-call. Force a touch+rm per
ogni eccezione legittima, friction operativa.

**c) Nessun bypass** — *Rejected*. Hook che blocca senza escape è anti-pattern. Edge case
legittimo (coder fa Edit non-classifiable, debug session, recovery): impossibile da
gestire senza disable bypass.

### 3.6 Validation regex e REPLACE-incomplete (Q6)

**a) Regex strict di forma, no semantic check (CHOSEN).** Gate "presenza PATTERN well-formed".
Semantic (es. REPLACE pair completo) defer al reviewer (layer 2 ADR-0001).

**b) Validation semantica completa (REPLACE pair, path:line consistency)** — *Rejected
in v1.0*. Scope creep, complica hook bash, rallenta performance. Defer v1.1 se metriche
pilota mostrano REPLACE-incomplete frequente.

**c) Regex lenient (case-insensitive, partial match)** — *Rejected*. Lascia escape al
coder per scrivere malformato (es. `pattern: add ...`). Strict regex = disciplina
allineata al contract ADR-0001 (esempi esatti).

### 3.7 Performance approach (Q7)

**a) Bash + jq + tail + grep con hard timeout 2s (CHOSEN).** 3.2-clean, fail-open su slow,
typical <100ms. Pattern già consolidato in `stop-gate.sh` (timeout robusto, righe 77-88).

**b) Python helper script** — *Rejected*. Aggiunge dipendenza Python (mai necessaria
finora in `~/.claude/hooks/`), startup overhead Python interpreter ~150-200ms (oltre
target <100ms anche prima di qualsiasi logica).

**c) Caching della window in `~/.claude/state/`** — *Rejected v1.0*. Premature
optimization. Tail+jq su file <5MB è sufficiente. Cache richiede invalidation logic
(stale state).

---

## 4. Consequences

### 4.1 Positive

- **Gate runtime alla disciplina classifier.** Prima volta che il sistema enforca
  `PATTERN:` a livello di tool call, non solo via review post-hoc.
- **Friction mirata.** Solo coder agent vede il block. Altri agent (orchestrator,
  architect, reviewer) restano fluid.
- **Defense in depth.** Quarto layer al stack ADR-0001 (system prompt → hook gate →
  reviewer post-hoc → v1.2 safety net). Hook chiude il gap "parallel coder in worktree
  senza reviewer transcript".
- **Audit trail.** Tutti i block e bypass loggati in `~/.claude/state/pattern-enforce/audit.log`.
  Metriche di pilota osservabili (hit-rate, bypass rate).
- **Anchor preservato.** Harness PASS=47 → PASS=48 (additivo).
- **Performance accettabile.** <100ms typical, hard timeout 2s, fail-open su error.
- **Zero nuove dipendenze.** Bash 3.2 + jq (già usato da `stop-gate.sh`).

### 4.2 Negative

- **Friction sul coder se transcript_path non risolvibile.** Edge case: sessione fresh
  dove il jsonl non è ancora flushed; l'hook fail-open silent (acceptable), ma il primo
  Edit potrebbe bypassare il check. Mitigato da reviewer post-hoc (layer 3 ADR-0001).
- **Dipendenza dal formato jsonl di Claude Code.** Cambio breaking del formato future
  → hook degrada. Mitigazione: fail-open su jq parse error.
- **False positive rate iniziale stimato 5-15%.** Coder potrebbe legittimamente fare
  Edit senza PATTERN se l'LLM ha drift. Bypass mechanism (Q5) copre, ma genera friction
  finché il pattern si stabilizza. Validabile in pilota.
- **Coupling settings.json + harness.** Aggiunta entry hook in settings.json verifica
  anchor di review-triage-fix. Refactor futuro di settings.json richiede update anchor.
- **Performance non garantita su transcript >50MB.** Sessioni long-running con jsonl
  enormi possono lenire il tail+jq. Mitigato dal `tail -n 200` (lettura O(n) della coda),
  non parse full file.

### 4.3 Neutral

- ADR-0001 resta autoritativo per la **definizione del pattern** (categorie, format).
  Questo ADR aggiunge solo enforcement layer.
- Il reviewer.md pattern-drift check (item 5) resta invariato — layer 3 conserva il
  semantic check che l'hook esplicitamente non fa (REPLACE pair completo, etc.).
- Memory `feedback_micropiano-refactor-cleanup` resta RESOLVED. Questo ADR è additive.

### 4.4 Open questions (validation pending)

- **`transcript_path` field è disponibile in tutte le versioni del CLI attive sul Mac di
  Stefano (Claude Code 2.x)?** Verificabile testando l'hook con un dispatch reale in pilota.
  Fallback: derivare da `session_id` via encoding cwd (più fragile ma feasible).
- **False positive rate effettivo del coder nei primi 20-30 dispatch.** Misurabile via
  audit.log dei block. Se >20%, considerare amendment v1.1 (window dimension, regex
  lenience, semantic skip per certi tool_input pattern).
- **Performance under load.** Misurabile con benchmark `time` sul harness Task 6.
  Se >150ms p95, considerare cache layer (defer to v1.1).

---

## 5. References

- `~/.claude/agents/coder.md` (disciplina ADR-0001 enforced da questo hook)
- `~/.claude/agents/reviewer.md` (layer 3 complementare)
- `~/.claude/hooks/stop-gate.sh` (pattern di hook bash 3.2-clean: timeout, fail-open, JSON
  emit via jq)
- `~/.claude/hooks/approve-test-cmd.sh` (utility hook esistente, coesistenza no conflict)
- `~/.claude/settings.json` (target registration entry PreToolUse)
- `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (definizione pattern)
- `docs/vibe-coding-system.md` sez. 7 (hooks deterministic automation) + sez. 10
  (permission strategy)
- Memory `feedback_bash32-constraint.md` (compat shell)
- Claude Code docs `code.claude.com/docs/en/docs/claude-code/hooks` (PreToolUse contract)
