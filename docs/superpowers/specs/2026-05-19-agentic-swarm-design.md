# Design — Sciame agentivo: intervento automatico a due livelli (globale)

> Data: 2026-05-19
> Stato: design approvato (brainstorming), pre-implementazione
> Scope: `~/.claude/` (globale, tutti i progetti)
> Riferimenti blueprint: `docs/vibe-coding-system.md` sez. 2.1–2.3, 3, 7.2–7.5, 17

## 1. Obiettivo

Rendere l'intervento dei sub-agent (tester, reviewer, debugger, refactorer)
**automatico durante codifica e build**, con due livelli distinti:

- **Livello 1 — gate deterministici**: alcune cose DEVONO succedere sempre
  (test girati/verdi e niente lavoro ovvio rimasto prima di dichiarare "fatto").
- **Livello 2 — sciame proattivo probabilistico**: gli agenti intervengono in
  parallelo quando l'orchestrator lo ritiene utile, best-effort.

Vincolo architetturale verificato (blueprint sez. 2.2, `code.claude.com/docs/sub-agents`):
i sub-agent **non spawnano altri sub-agent** e non comunicano peer-to-peer. Non
esiste uno "sciame" autonomo: la topologia reale è orchestrator → fan-out ≤4
sub-agent in-sessione, oppure agent-teams (experimental, fuori scope qui).
"Sciame" in questo design = fan-out orchestrato + gate deterministici, non
agenti peer indipendenti.

## 2. Non-obiettivi (YAGNI)

- Nessun agent-teams automatico (resta opt-in via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`).
- Nessun "demone" che osserva il repo fuori sessione: non esiste in Claude Code.
- Nessun hook semantico ("intervieni quando serve un test"): impossibile, gli
  hook scattano solo su confini fissi del lifecycle.
- Fase C (escalation tiered + trigger agent-teams) NON è speccata qui: è orizzonte.

## 3. Architettura

```
Task di codifica
   │
   ▼
[L2] Sciame proattivo probabilistico
   • description rinforzate (tester/reviewer/debugger/refactorer)
   • rule globale = policy parallelizzazione (blueprint sez. 2.3)
   • fan-out ≤4 sub-agent, isolation: worktree
   │  (orchestrator decide serial vs parallelo)
   ▼
[L1] Gate deterministici (hook ~/.claude/settings.json)
   • Stop gate = hook type:command (A: marker-block · B: esegue i test)
   • sentinel .dirty set/clear (PostToolUse Edit|Write / Bash)
   • protect-files / auto-format (esistenti, invariati)
   ▼
[X] Guardrail anti-loop (trasversale)
   • contatore per-session_id; cap N → exit 0 (no block) + warning
```

Fasatura: **A** (command gate: blocca su sentinel "dirty", non esegue i test)
→ **B** (stesso command gate: esegue davvero la test suite) → **C** (orizzonte,
non speccato).

## 4. Livello 1 — Gate deterministici

> **Provenienza del design (verificato 2026-05-19).** Verifica live di
> `code.claude.com/docs/en/hooks`: gli hook `type: prompt` e `type: agent`
> **non sono supportati sull'evento `Stop`** (solo `command`, `http`,
> `mcp_tool`); non esiste `stop_hook_active` né loop-protection nativa. Il
> design originale (blueprint sez. 7.4/7.5, ora corretto in loco) era
> irrealizzabile. Tutto il gate `Stop` è quindi un unico hook
> **`type: command`**, contratto di blocco
> `{"decision":"block","reason":"…"}` su stdout **oppure** exit code 2;
> "permetti lo stop" = exit 0 senza output di blocco. `session_id` (stabile
> per sessione) è la chiave dei file di stato.

### 4.1 Stop gate — Fase A (marker-block, NON esegue i test)

- Un solo hook `Stop`, `type: command`: `~/.claude/hooks/stop-gate.sh`.
- Logica:
  1. Legge `session_id` da stdin (JSON).
  2. Se il sentinel `~/.claude/state/stop-gate/<session_id>.dirty` **non**
     esiste → exit 0 (permetti stop).
  3. Se esiste → consulta il guardrail anti-loop (§5). Se contatore `>= N` →
     exit 0 + warning su stderr (sblocco anti-loop). Altrimenti → incrementa
     contatore ed emette
     `{"decision":"block","reason":"Hai modificato codice senza eseguire la
     test suite. Esegui i test del progetto e conferma il verde prima di
     concludere."}`.
- **Fase A non esegue i test**: si limita a rilevare "codice toccato, test non
  ancora eseguiti" via sentinel. È lo scaffold di sicurezza (sentinel +
  anti-loop + fail-open) da validare sul pilota perché **non cicli mai**.
- Il sentinel viene azzerato quando il PostToolUse rileva un comando di test
  andato a buon fine (§4.5), così Claude — ri-sollecitato dal `reason` — può
  sbloccare lo stop eseguendo davvero i test.

### 4.2 Stop gate — Fase B (esegue davvero la test suite)

- **Stesso** hook `command` `~/.claude/hooks/stop-gate.sh`, evoluto: quando il
  sentinel `.dirty` è presente, **esegue la test suite del progetto** invece
  di delegare a Claude.
- Discovery del comando test per-progetto (deterministico, fail-open se
  ignoto): `pytest` se `pyproject.toml`/`pytest.ini`; `npm test` se
  `package.json` con script `test`; estendibile. Comando ignoto → exit 0
  (fail-open, non bloccare).
- Test verdi → cancella `.dirty`, exit 0. Test rossi → contatore++ (se `< N`)
  ed emette `{"decision":"block","reason":"test falliti: <sintesi>"}`; se
  contatore `>= N` → exit 0 + warning.
- Resta `type: command` (supportato su `Stop`): nessun `type: agent`.
- Subordinato a guardrail anti-loop (§5) **provato stabile** in Fase A.

### 4.3 Gate esistenti (invariati)

- `protect-files.sh` (PreToolUse, matcher `Edit|Write`): blocca `.env`,
  lock file, `.git/`.
- `auto-format.sh` (PostToolUse, matcher `Edit|Write`).

### 4.4 Regola di design critica: fail-open

Ogni hook globale, in caso di errore interno (`jq` mancante, `session_id` non
parsabile, file di stato non scrivibile, comando test ignoto in Fase B), DEVE
uscire con **exit 0 senza output di blocco** (= permetti lo stop). Mai exit 2
/ `decision:block` su errore dell'hook. Un hook `Stop` globale fail-closed
bloccherebbe ogni sessione di ogni progetto. Fail-open è non negoziabile.

### 4.5 Sentinel "dirty" — set & clear

- **Set**: hook `PostToolUse` (matcher `Edit|Write`),
  `~/.claude/hooks/mark-dirty.sh`, crea
  `~/.claude/state/stop-gate/<session_id>.dirty` (usa `tool_input.file_path`
  per ignorare modifiche fuori dal codice se utile; default: qualunque
  Edit/Write segna dirty).
- **Clear, Fase A**: hook `PostToolUse` (matcher `Bash`),
  `~/.claude/hooks/clear-dirty-on-test.sh`: se `tool_input.command` è un
  comando di test riconosciuto (`pytest`, `npm test`, `npm run test`,
  `vitest`, `go test`) **e** `tool_output` non indica fallimento → cancella
  `.dirty`. Così Claude, ri-sollecitato dal `reason` del gate, sblocca lo stop
  eseguendo davvero i test.
- **Clear, Fase B**: lo `stop-gate.sh` stesso cancella `.dirty` quando esegue
  i test e sono verdi (§4.2).
- Effetto: il gate non blocca se non è cambiato codice dall'ultimo verde.

## 5. Componente trasversale — Guardrail anti-loop

Rende sicuro A→B in globale e chiude il flag aperto "sospetto loop infinito".

- Stato: file contatore per-sessione, path
  `~/.claude/state/stop-gate/<session-id>.count` (intero, default assente = 0).
- Ogni volta che il gate sta per emettere un blocco
  (`{"decision":"block"}`) → incremento del contatore.
- Hook `UserPromptSubmit` (`~/.claude/hooks/reset-gate-counter.sh`) → reset
  del contatore (nuovo turno utente = budget fresco).
- Soglia `N` (default **3**): quando `count >= N`, il gate **non blocca** —
  exit 0 + warning visibile su stderr ("anti-loop guardrail: gate sbloccato
  dopo N rientri, verifica manuale").
- Directory `~/.claude/state/stop-gate/` creata idempotentemente da un hook
  `SessionStart` (`mkdir -p`, fail-open).

## 6. Livello 2 — Sciame proattivo

### 6.1 Hardening description

Rinforzo del campo `description` (frontmatter) dei sub-agent in
`~/.claude/agents/`, con trigger proattivi già abbozzati nel blueprint sez. 3:

- `tester`: "Use after coder finishes implementing a feature."
- `reviewer`: "Use proactively before any commit involving more than 50 lines."
- `debugger`: "Use proactively on any runtime error, red test, or bug report."
- `refactorer`: "Use when reviewer flags structural issues."

È il meccanismo (probabilistico) con cui l'orchestrator decide il fan-out
senza richiesta esplicita.

### 6.2 Rule globale di parallelizzazione

Nuovo file rule in `~/.claude/rules/` (path-scoped, frontmatter `paths:` per
applicarsi ai file di codice) che codifica come istruzione esplicita i 3
criteri di blueprint sez. 2.3, in ordine:

1. File indipendenti tra sub-agent → fan-out parallelo possibile.
2. Test verdi → parallelo aggressivo; test rossi → seriale (prima fix).
3. research/planning → seriale; codifica/test/doc → parallelizzabile.

Cap: max 4 sub-agent paralleli; oltre → batch sequenziali da 3–4. I `coder`
paralleli usano `isolation: worktree`.

### 6.3 Agent-teams

Nessuna attivazione automatica in A/B. Resta opt-in esplicito (env var +
prompt). Trigger semi-automatico = Fase C, non speccato.

## 7. Failure modes & error handling

| Rischio | Mitigazione |
|---|---|
| Loop | Contatore anti-rientro (§5): cap `N` → warn + pass. Mitigazione primaria. |
| Falso "dirty" persistente (A) — codice toccato ma nessun test eseguibile | Cappato dal contatore (sblocco a `N`); Fase B esegue i test direttamente |
| Worktree senza venv/`node_modules` (residuo 2% blueprint sez. 17) | `worktree.symlinkDirectories` o reinstall deps; rischio noto, validare sul pilota |
| Cost spike Fase B globale | `stop-gate.sh` esegue i test solo se sentinel "dirty"; skip se nulla cambiato (§4.2) |
| Comando test non riconosciuto (B) | Fail-open: exit 0, nessun blocco (§4.4) |
| Hook in errore | Fail-open obbligatorio (§4.4) |

## 8. Testing strategy

Validazione **sul pilota `pricing-markup-cli`** prima del deploy globale
(anche se il target è globale):

1. Contatore anti-loop cappa correttamente con `ok:false` persistente simulato
   (forzare il gate a fallire ripetutamente, verificare sblocco a `N`).
2. Gate fail-open con `jq` assente / file di stato assente (nessun blocco).
3. Reset contatore su `UserPromptSubmit` (nuovo turno → budget ripristinato).
4. (Fase B) test-gate parte solo se sentinel "dirty"; si azzera sul verde.
5. Rule di parallelizzazione: task multi-file → fan-out ≤4 in worktree, zero
   collisioni su file condivisi.

Solo dopo prova sul pilota → diff mostrato + **HITL gate esplicito** → commit
della modifica globale a `~/.claude/settings.json`.

## 9. Rischi e decisioni aperte (da risolvere in implementazione)

### 9.1 Collisione regola plan-mode vs agent-delegation — RISOLTA

Il CLAUDE.md globale impone "plan mode obbligatorio per task che modifica >1
file". La rule di parallelizzazione (§6.2) fa fan-out su task multi-file. Le
due regole potevano confliggere: il plan mode poteva scattare e impedire il
fan-out, oppure il fan-out aggirare un gate voluto.

**Decisione (confermata da Stefano, 2026-05-19; formulazione conservativa
post-security-review):** plan mode resta OBBLIGATORIO per task >1 file
(regola IMPORTANT del CLAUDE.md: invariata). Il piano di fan-out
dell'orchestrator è l'artefatto presentato per l'approvazione in plan mode;
una volta approvato QUEL piano, l'esecuzione dei sub-agent al suo interno non
richiede una seconda approvazione plan-mode separata per lo stesso lavoro già
approvato. Non autorizza in alcun caso a saltare plan mode se il piano di
fan-out non è stato approvato. La rule §6.2 esplicita questo come
*chiarimento che preserva il guardrail*, non come soppressione del
re-trigger (evita la deriva "indebolisce plan-mode").

### 9.2 HITL su settings.json globale

Modifica a `~/.claude/settings.json` (alto blast radius: ogni progetto):
richiede diff mostrato + approvazione esplicita di Stefano prima del commit
(CLAUDE.md globale). Nessun deploy globale senza prova sul pilota (§8).

## 10. Sequenza di consegna (fasi)

- **Fase A**: `stop-gate.sh` marker-block (§4.1) + guardrail anti-loop (§5) +
  sentinel set/clear (§4.5: `mark-dirty.sh`, `clear-dirty-on-test.sh`) +
  hardening description (§6.1) + rule parallelizzazione (§6.2) + hook
  `SessionStart`/`UserPromptSubmit` di supporto. Validazione pilota → HITL →
  deploy globale.
- **Fase B**: evoluzione di `stop-gate.sh` a esecuzione reale dei test (§4.2),
  subordinata a guardrail Fase A provato stabile. HITL prima del globale.
- **Fase C** (orizzonte, non speccato): escalation/trigger documentato
  agent-teams.

## 11. Criteri di successo

- Fase A deployata in globale senza loop osservabili su 1 settimana di uso reale.
- Almeno un caso reale in cui il gate fa proseguire Claude su lavoro
  effettivamente incompleto (test non girati).
- Fan-out parallelo osservato su un task multi-file del pilota, zero collisioni.
- Flag "sospetto loop infinito" chiuso (guardrail §5 verificato sul pilota).

## 12. Rollback / backout tracciato

Il target è globale (`~/.claude/`, alto blast radius). Ogni fase deve essere
**reversibile in modo meccanico**. Tracciamento obbligatorio.

### 12.1 File globali toccati (superficie di modifica)

| File | Fase | Tipo modifica |
|---|---|---|
| `~/.claude/settings.json` | A, B | hook aggiunti (Stop, UserPromptSubmit, SessionStart, PostToolUse) |
| `~/.claude/agents/{tester,reviewer,debugger,refactorer}.md` | A | solo campo `description` |
| `~/.claude/rules/<parallelization>.md` | A | file nuovo |
| `~/.claude/hooks/*.sh` (stop-gate, anti-loop, sentinel) | A, B | file nuovi |
| `~/.claude/state/stop-gate/` | A | dir di stato runtime (non codice) |

### 12.2 Backup pre-modifica (obbligatorio prima di ogni fase)

Prima di qualunque scrittura globale, copia timestampata dei file *esistenti*
toccati in `~/.claude/state/backups/2026-05-19-swarm-fase-<A|B>/`, preservando
i path relativi. Coerente con CLAUDE.md globale ("backup prima di modificare
file critici"). I file *nuovi* non necessitano backup (il backout li rimuove).

### 12.3 Manifest di tracciamento

File `~/.claude/state/backups/2026-05-19-swarm-fase-<A|B>/MANIFEST.md` che
elenca, per ogni file: path, azione (`modified`|`created`), timestamp, e per i
modificati il path del backup. Il backout è guidato esclusivamente dal
manifest — nessuna ricostruzione a memoria.

### 12.4 Procedura di backout

1. Per ogni voce `modified` nel manifest → ripristina il file dal backup.
2. Per ogni voce `created` → rimuovi il file/dir (previa conferma esplicita,
   mai delete senza HITL).
3. Rimuovi le chiavi hook aggiunte da `settings.json` (il backup di §12.2 è la
   fonte di verità: ripristino integrale del file, non patch manuale).
4. Sessione fresca per ricaricare `settings.json` pulito.

### 12.5 Trigger di rollback

Backout immediato se, dopo deploy globale, si osserva: loop non cappato dal
guardrail §5; comportamento fail-closed (Stop bloccato da bug dell'hook);
regressione su un progetto non-pilota; spike di costo Fase B fuori controllo.

### 12.6 Granularità

Fase A e Fase B hanno backup e manifest **separati**: si può fare rollback di
B mantenendo A. C non tocca il globale finché non speccata.
