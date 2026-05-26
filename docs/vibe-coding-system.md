# Vibe Coding System per Stefano Ferri — Architettura Multi-Agente v2.1

**Versione:** 2.1 (terza verifica integrale contro documentazione Anthropic ufficiale completa)
**Autore:** Adriano per Stefano Ferri
**Data:** 17 maggio 2026
**Target:** Claude Code (CLI) v2.1.32+ con orchestrazione hybrid, sub-agenti, agent teams (experimental), skill, hook e MCP

---

## Cambiamenti rispetto alle versioni precedenti

### v1.0 → v2.0
Correzioni strutturali (sub-agent come entità formali con YAML, agent-teams come pattern separato, CLAUDE.md size limit, path-scoped rules, hook completi, worktree isolation, skill bundled, 6 permission modes).

### v2.0 → v2.1 (questa versione)
Verifica integrale contro le pagine ufficiali `code.claude.com/docs` (best-practices, sub-agents, agent-teams, memory, skills, hooks-guide, permission-modes, common-workflows, features-overview, mcp, claude-directory, settings, plugins, worktrees). Correzioni puntuali aggiunte:

- **`attribution` setting** (sez. 4): disabilita la firma "Co-Authored-By: Claude" nei commit per branding professionale. Importante perché di default Claude Code aggiunge il trailer ai commit
- **`$schema` in settings.json**: abilita validation JSON in Cursor/VS Code
- **MCP GitHub remote via HTTP**: il pattern moderno è `https://api.githubcopilot.com/mcp/` con Bearer token, non più stdio. Sezione 9.1 aggiornata
- **`claude mcp add` CLI**: pattern raccomandato Anthropic vs editing diretto di `.mcp.json`
- **`alwaysLoad: true`** per MCP server con tool sempre necessari (saltare tool search)
- **`MAX_MCP_OUTPUT_TOKENS`** per limit output MCP (default 25,000)
- **Worktrees: dettagli operativi** (sez. 12): path `.claude/worktrees/<name>/`, branch `worktree-<name>`, `worktree.baseRef: "head"` per branchare da local HEAD, PR worktree con `#<num>`, caveat su `node_modules`/`uv venv` non portati
- **`.worktreeinclude`**: file root del progetto per copiare gitignored (`.env`, `secrets`) nei worktree creati
- **Comandi diagnostici completi** (sez. 16): `/config`, `/context`, `/status`, `/doctor`, `/skills`, `/permissions`, `/plugin`
- **Plugin `--plugin-dir`/`--plugin-url`** (sez. 14): test locale e CI di plugin in development
- **Hook `InstructionsLoaded`** (sez. 7): debug del caricamento path-scoped rules

### Correzione 2026-05-19 (post-verifica hooks live)

Verifica diretta di `code.claude.com/docs/en/hooks` (2026-05-19) ha trovato due
imprecisioni in sez. 7 e sez. 17, qui corrette inline:

- **`type: prompt` e `type: agent` NON sono supportati sull'evento `Stop`**:
  su `Stop` valgono solo `command`, `http`, `mcp_tool`. Le sez. 7.4 e 7.5
  (gate Stop prompt/agent based) sono **errate come scritte** — vedi
  admonition correttiva in loco. Il pattern corretto per un gate su `Stop` è
  un hook `type: command` con contratto `{"decision":"block","reason":"…"}`
  o exit code 2.
- **Nessun `stop_hook_active` / loop-protection nativa per `Stop`**: un guardrail
  anti-loop (contatore per-sessione su `session_id`) è responsabilità
  dell'autore dell'hook, non fornito da Claude Code.

Confermati nella stessa verifica: `session_id` stabile per sessione,
`tool_input.file_path` su PostToolUse, hook multipli per evento in parallelo
(un "block" vince).

### Riconciliazione 2026-05-19 (Stop-gate testcmd — implementato e deployato live)

Il pattern corretto indicato nella correzione precedente non è più solo un
*design*: è stato **implementato e deployato live** in `~/.claude/` (esecuzione
subagent-driven). Lo stato as-built sostituisce ogni descrizione di "design da
fare":

- Il gate `Stop` è un hook `type: command` (`~/.claude/hooks/stop-gate.sh`) con
  ladder a 3 tier su una **dichiarazione esplicita per-progetto**
  `<repo>/.claude/test-cmd`: assente→nudge bounded / `NONE`→opt-out fail-open /
  presente-non-approvato→tier approve (NO exec) / approvato→esegue il comando
  autorevolmente (exit code reale, timeout, anti-loop a contatore).
- **Trust-on-first-use**: un comando reale gira solo dopo approvazione esplicita
  via `~/.claude/hooks/approve-test-cmd.sh` (registro `<sha256>\t<root>` in
  `~/.claude/state/stop-gate/trust`); modificare `test-cmd` invalida l'hash →
  ri-approvazione. **Nel chain `concept-to-code` (Gate 2b, 2026-05-26):** l'approvazione
  passa per `AskUserQuestion` — l'orchestratore chiama `approve-test-cmd.sh` solo dopo
  il click esplicito dell'utente. Questo risolve il loop stop-hook/auto-approve in cui
  l'orchestratore si auto-approvava prima che l'utente potesse rispondere.
- **L'euristica grep `clear-dirty-on-test.sh` è RITIRATA** (eliminata e unwired
  da `settings.json`): risolve strutturalmente il difetto per cui runner
  non-standard non venivano riconosciuti. Niente più pattern-matching
  sull'output dei test.
- **Fail-open totale** (spec §7): jq/sha256/timeout/session_id mancanti, exit
  124/125/126/127 → allow, mai exit≠0.
- Le **Fasi B/C** del vecchio spec agentic-swarm sono **subsunte**
  dall'autoritative tier (nessun lavoro separato residuo).
- Autorità as-built: `docs/superpowers/specs/2026-05-19-swarm-testcmd-design.md`
  + `docs/superpowers/plans/2026-05-19-swarm-testcmd.md`. Harness
  `~/.claude/hooks/tests/run-hook-tests.sh` (PASS=28 FAIL=0). Backup pristine +
  rollback §9 in `~/.claude/state/backups/2026-05-19-swarm-testcmd/`.

Sez. 7.4/7.5 (admonition aggiornate al riferimento as-built) e 7.6 (layout
filesystem aggiornato al deployato) riflettono questo. Validazione tier sul
progetto pilota = unico punto aperto (vedi sez. 17).

### Aggiornamento 2026-05-26

- **`isolation: worktree` su coder — gap chiuso**: il frontmatter di `~/.claude/agents/coder.md` ora include `isolation: worktree` (era presente nel template doc ma non deployato). Comportamento verificato: su repo git crea un worktree isolato, su progetti senza git fa fallback silenzioso (nessun errore, edit diretti). Il chain `concept-to-code` non richiede modifiche: il worktree branch viene già gestito dall'orchestratore nella fase di review/merge (sez. 3.2, 12).
- **`manifest-validate.sh` accetta schema 1.2** (fix post-recovery): un recovery accidentale di skill aveva revertito `scripts/manifest-validate.sh` alla versione pre-ADR-0011, che non accettava `schema_version: "1.2"`. Fix inline applicato; harness concept-to-code 27/0.
- **Gate 2b TOFU redesign** (fix loop stop-hook + auto-approve): nel chain `concept-to-code`, il vecchio pattern "di' all'utente di eseguire `approve-test-cmd.sh`" causava un loop: lo stop hook bloccava prima che l'utente potesse rispondere, l'orchestratore tentava di aggirarlo chiamando lo script via Bash, auto mode lo lasciava passare → auto-approvazione senza revisione umana. Fix: Gate 2b ora usa `AskUserQuestion` con opzioni esplicite [Approvo / Modifica / Salta / Abort]. Solo dopo il click dell'utente l'orchestratore chiama `approve-test-cmd.sh`. Guardrail espliciti nel SKILL.md: MAI chiamare `approve-test-cmd.sh` prima del click; MAI modificare `.claude/test-cmd` autonomamente. Il meccanismo TOFU SHA-pinned è invariato. Harness concept-to-code 29/0.
- **Gate 4 session boundary — reso BLOCKING**: nel chain `concept-to-code`, il confine di sessione tra Step 3 (architettura+CLAUDE.md) e Step 5 (implementazione) non era abbastanza forte — l'orchestratore interpretava lo stato `ready_for_implementation` come segnale per continuare direttamente nel dispatch dei coder. Fix: Gate 4 ora usa `AskUserQuestion` con singola opzione "Confermato — farò /clear e resume" + istruzione esplicita `**STOP — non dispatchare coder, non proseguire**` nel SKILL.md. Il confine `/clear` è un requisito architetturale: il context della sessione interview/architect inquina la fase di implementazione (context window + rischio di sovrascrivere decisioni già prese). Harness concept-to-code +1 anchor (30/0).
- **Blueprint repo su git** (2026-05-26 pomeriggio): `vibe-coding-system` ha ora git inizializzato e remote privato su `github.com/istefox/vibe-coding-system`. `.gitignore` esclude i log di sessione (`.remember/logs/`, `tmp/`, `now.md`, `today-*.md`, ecc.) — solo artefatti source vengono committati. Skill `/commit` field-testata su questo repo: flow completo verifica→diff→gate HITL→commit→push funzionante. Il `CLAUDE.md` del blueprint è stato aggiornato di conseguenza (rimossa nota "git non inizializzato").

### Aggiornamento 2026-05-25 (CC 2.1.147–149)

Novità rilevanti per questo sistema, incorporate inline nelle sezioni indicate:

- **`effort: xhigh` su architect** (sez. 3.1, 3.9): `xhigh` è il livello di effort nativo di Opus 4.7 per task agentici/coding; è ora il default raccomandato. Il template frontmatter architect è aggiornato da `high` a `xhigh`. Fallback automatico a `high` su Sonnet 4.6 quando architect è dispatched con override `model: sonnet` (ADR di routine).
- **Fix status bar effort frontmatter** (2.1.149): la status bar mostrava l'effort di sessione invece di quello del frontmatter skill/agent. Ora riflette correttamente l'override. Confermato funzionante per il nostro `effort: xhigh` su architect.
- **Fix `AskUserQuestion` in auto mode** (2.1.149): l'auto mode sopprimeva `AskUserQuestion` anche quando la skill lo usava esplicitamente. Risolto: il classifier legge le risposte utente come segnale di intento. Rilevante per `interview-driver`, `design-brainstorm`, e tutti i HITL gate del chain `concept-to-code`.
- **`/usage` breakdown per categoria** (2.1.149): mostra dettaglio costi per skill, subagent, plugin, MCP server. Aggiunto a sez. 16 comandi.
- **`/code-review` (ex `/simplify`)** (2.1.147): `/simplify` rinominato; ora report bug di correttezza a effort configurabile (`/code-review high`); `--comment` per inline PR comment. Aggiornato sez. 16.
- **Fix sandbox worktree** (2.1.149): la write allowlist in git worktrees copriva l'intero repo principale invece del solo `.git/` condiviso. Risolto. Rilevante per `isolation: worktree` del coder (sez. 12).
- **Fix `find` macOS vnode table** (2.1.149): il Bash tool esauriva la vnode table di macOS su directory molto grandi, crashando il sistema. Risolto. Anti-pattern `find .` su repo grandi rimosso dalla lista rischi teorici.
- **Meccanismo bootstrap remoto** (2.1.150): CC chiama `api.anthropic.com/api/claude_cli/bootstrap` all'avvio e GrowthBook (`tengu_heron_brook`) ogni 60s; il contenuto viene iniettato nel system prompt. È configurazione first-party (Anthropic), non injection da terze parti. Per ambienti con policy di immutabilità: `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` blocca entrambi i canali (aggiunto sez. 17).

---

## Cambiamenti rispetto alla v1.0

La v1.0 conteneva imprecisioni significative. Verificate contro `code.claude.com/docs`, queste sono le correzioni:

- **Sub-agent**: sono entità formali con file `.claude/agents/<name>.md` e frontmatter YAML, non concetti astratti. Anthropic ne ha già di built-in (`Explore`, `Plan`, `general-purpose`)
- **Sub-agent NON spawnano altri sub-agent**: limite duro. Per nesting serve `agent-teams`
- **Agent teams** (v2.1.32+, experimental): pattern multi-sessione coordinata via task list condivisa. È il pattern corretto per work cross-layer (backend + frontend + test paralleli)
- **CLAUDE.md target <200 righe** (era ~170, comunque alto): asciugato a ~90 righe efficaci
- **`.claude/rules/`** con `paths:` frontmatter: pattern raccomandato per regole stack-specifiche (sostituisce gran parte del CLAUDE.md monolitico)
- **Auto memory**: feature reale in `~/.claude/projects/<repo>/memory/`, da menzionare
- **Hook**: sezione completa mancante in v1.0, è il meccanismo deterministico più importante
- **Worktrees per Coder paralleli**: risolve il conflitto di lock file (punto aperto v1.0)
- **Skill bundled**: `/batch`, `/simplify`, `/debug`, `/loop`, `/claude-api` esistono già out-of-the-box
- **Permission modes**: 6 modi reali (`default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`), non solo "plan/bypass"
- **`/init` con `CLAUDE_CODE_NEW_INIT=1`**: flow interattivo multi-phase per generare CLAUDE.md, skill e hook insieme

---

## 1. Riepilogo

**Topologia.** Orchestrator centrale (Claude Code CLI) → fino a 4 sub-agenti in parallelo (dentro la sessione) per task focalizzati, oppure team di 3-5 teammates indipendenti (sessioni separate) per lavoro cross-layer.

**Extension stack.** CLAUDE.md globale (~90 righe, solo identità+comportamento) + path-scoped rules in `.claude/rules/` per stack-specific + sub-agent files in `.claude/agents/` + skill in `.claude/skills/` + hook in `settings.json` + MCP in `.mcp.json`.

**Permission strategy.** Plan mode di default per nuove feature, `acceptEdits` durante implementazione, `auto` mode (se piano Team/Enterprise) per lavoro lungo con safety classifier in background.

**MCP core.** sequential-thinking, XcodeBuildMCP, github, sqlite/postgres-mcp.

**Workflow concept→code** (sez. 11) basato sul pattern ufficiale Anthropic: interview mode con `AskUserQuestion` → `SPEC.md` → fresh session con plan mode → implementazione parallela → commit + PR.

---

## 2. Architettura del sistema

### 2.1 Topologia logica

```
Orchestrator (sessione principale Claude Code CLI)
    │
    ├─ Built-in sub-agent (Anthropic):
    │  ├─ Explore        (read-only, Haiku, ricerca codebase)
    │  ├─ Plan           (read-only, plan mode, ricerca per planning)
    │  ├─ general-purpose (tutti i tool, multi-step generico)
    │  └─ Bash, statusline-setup, Claude Code Guide
    │
    ├─ Sub-agent custom (.claude/agents/*.md, max 4 paralleli):
    │  ├─ architect       (Opus, planning + ADR)
    │  ├─ coder           (Sonnet, edit, isolation: worktree)
    │  ├─ reviewer        (Sonnet, read-only, memory: project)
    │  ├─ tester          (Sonnet, bash + edit)
    │  ├─ debugger        (Sonnet, edit + bash, memory: project)
    │  ├─ doc-writer      (Haiku, edit testo)
    │  ├─ refactorer      (Sonnet, edit, memory: project)
    │  └─ researcher      (Haiku, read-only + web)
    │
    └─ Agent team (experimental, sessioni separate):
       Per lavoro cross-layer su progetti grandi (backend + frontend + test
       in parallelo) o investigazione con ipotesi competenti
```

### 2.2 Sub-agent vs agent team (decisione critica)

Documentazione ufficiale Anthropic distingue chiaramente:

| Caratteristica | Sub-agent | Agent team |
|---------------|-----------|-----------|
| Architettura | Dentro la sessione corrente | Sessioni indipendenti coordinate |
| Comunicazione | Solo verso il lead (riporto risultati) | Peer-to-peer + task list condivisa |
| Spawn altri | NO | NO (anche nei team, no nested) |
| Stato | `production-ready` | `experimental` (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) |
| Token cost | Più basso (summary back) | Più alto (ogni teammate = sessione completa) |
| Quando usare | Task isolato con output di sintesi | Work che richiede coordinamento e dibattito |

**Regola per Stefano:**
- Sub-agent per: review, research, debug isolato, test di un modulo, scaffold di un componente, doc generation. **Default per tutto.**
- Agent team per: feature cross-strato grande (FastAPI router + React page + test in parallelo), investigazione bug con ipotesi competenti, code review multi-prospettiva. **Solo per task grandi e indipendenti.**

### 2.3 Logica di parallelizzazione dell'orchestrator

L'orchestrator decide quando spawnare sub-agent in parallelo applicando 3 criteri (in ordine):

1. **Indipendenza file**: i sub-agent toccano file/moduli diversi → parallelo possibile
2. **Stato test**: test verdi → parallelo aggressivo; test rossi → seriale (prima fix)
3. **Tipo task**: research+planning seriale; codifica+test+doc parallelizzabile

**Conflitto lock file (risolto):** ogni `coder` parallelo gira con `isolation: worktree` nel frontmatter, ottenendo un copy git isolato. Niente race condition su import o file condivisi.

**Cap massimo:** 4 sub-agent paralleli. Se servono più, batch sequenziali da 3-4.

---

## 3. Sub-agent custom — definizioni complete

Tutti i sub-agent vivono in `~/.claude/agents/` (user-level, validi in tutti i progetti) o `.claude/agents/` (project-level, in repo). Si gestiscono con `/agents`.

### 3.1 architect

File: `~/.claude/agents/architect.md`

```markdown
---
name: architect
description: Designs system architecture, writes ADR, decomposes complex tasks into implementation plans. Use proactively at the start of any non-trivial feature or refactor. Never writes production code.
tools: Read, Grep, Glob, Bash(git *), Bash(rg *), WebSearch, WebFetch
model: opus
permissionMode: plan
memory: project
effort: xhigh
---

You are a senior software architect with 20+ years of experience.

Your job:
1. Read SPEC.md (if present), CLAUDE.md, ARCH.md, and relevant existing code
2. Decompose the task into 3-8 concrete implementation steps
3. Write or update an Architecture Decision Record at docs/architecture/ADR-NNN-<title>.md following this structure:
   - Context (problem statement)
   - Decision (chosen approach)
   - Alternatives considered (and why rejected)
   - Consequences (positive and negative)
4. Identify files to create/modify and the API/contract changes
5. Flag risks, dependencies, and HITL gates needed
6. NEVER write production code. Return the plan and stop.

Use sequential-thinking MCP when the design space is complex.
Update your memory with patterns and decisions you discover.
```

### 3.2 coder

File: `~/.claude/agents/coder.md`

```markdown
---
name: coder
description: Implements production code following an approved plan or ADR. Use after architect has produced a plan and Stefano has approved it. Never commits.
tools: Read, Edit, Write, Glob, Grep, Bash
model: sonnet
isolation: worktree
effort: medium
---

You are a senior implementation engineer.

Your job:
1. Read the relevant ADR or plan provided in context
2. Implement the code following the plan exactly
3. Use Conventional Commits in English in any commit message you draft (but NEVER commit yourself: leave that to the orchestrator)
4. Match existing code style by reading 2-3 similar files first
5. Write minimal, idiomatic code: no over-engineering, no premature abstraction
6. Validate your work with the relevant verification tool (test, lint, build) before declaring done
7. Return a summary: files modified, key decisions, verification status

Stack rules come from project CLAUDE.md and .claude/rules/. Read them before writing.
Run in an isolated worktree to avoid conflicts with other parallel coders.
```

> **Nota deployment (2026-05-26):** `isolation: worktree` è ora attivo nel file deployato `~/.claude/agents/coder.md`. Comportamento su progetti senza git: fallback silenzioso, edit diretti (nessun errore). Il branch risultante su repo git viene gestito dall'orchestratore nella fase di review/merge — nessuna modifica richiesta al chain concept-to-code.

### 3.3 reviewer

File: `~/.claude/agents/reviewer.md`

```markdown
---
name: reviewer
description: Reviews recently changed code for security, correctness, performance, and consistency with project patterns. Use proactively before any commit involving more than 50 lines of change.
tools: Read, Grep, Glob, Bash(git diff*), Bash(git log*)
model: sonnet
memory: project
---

You are a senior code reviewer.

Workflow:
1. Run `git diff` to see recent changes
2. Read modified files in full to understand context
3. Check your memory for known patterns and recurring issues in this project
4. Review against this checklist:
   - Security: input validation, SQL injection, hardcoded secrets, auth flow
   - Correctness: logic bugs, edge cases, error handling
   - Performance: N+1 queries, unnecessary loops, blocking calls in async paths
   - Consistency: matches existing patterns in the codebase
   - ADR alignment: any deviation from documented architectural decisions
5. Format output by severity: BLOCKER, MAJOR, MINOR, NIT
6. For each issue: file:line reference + suggested fix
7. Update your memory with patterns you observe (recurring issues, anti-patterns)

Output is markdown, not a code diff. The orchestrator decides what to apply.
```

### 3.4 tester

File: `~/.claude/agents/tester.md`

```markdown
---
name: tester
description: Writes and runs unit/integration tests targeting ~70% coverage on critical business logic. Use after coder finishes implementing a feature.
tools: Read, Edit, Write, Glob, Grep, Bash
model: sonnet
---

You are a pragmatic test engineer.

Your scope:
- TEST: business logic, calculations, API endpoints, parsing, security-sensitive code
- SKIP: pure UI presentation, glue code, configuration, trivial getters/setters

Framework selection by stack:
- Python: pytest + pytest-asyncio
- TypeScript: Vitest + @testing-library/react
- Swift: XCTest + Swift Testing (prefer Swift Testing for new tests)

Workflow:
1. Read the code under test
2. Read existing tests in the project to match style and conventions
3. Cover: happy path, edge cases, error paths, boundary values
4. Run the test suite and verify all pass
5. Report: tests added, coverage on the touched modules, any failures

Never modify production code. If a test reveals a bug, report it and let the debugger or coder fix it.
```

### 3.5 debugger

File: `~/.claude/agents/debugger.md`

```markdown
---
name: debugger
description: Diagnoses errors, test failures, and unexpected behavior. Use proactively on any runtime error, red test, or bug report. Performs root cause analysis.
tools: Read, Edit, Bash, Grep, Glob
model: sonnet
memory: project
---

You are an expert debugger specializing in root cause analysis.

Workflow:
1. Capture the full error: stack trace, log lines, exact reproduction steps
2. Check your memory for similar past issues
3. Isolate the failure: which line, which input, which environment
4. Form 2-3 hypotheses, test each one with minimal probes (logging, repl, isolated repro)
5. Identify root cause (not symptom)
6. Apply minimal fix
7. Verify fix resolves the issue without breaking other paths
8. Update your memory with the bug pattern and resolution

Output:
- Root cause explanation
- Evidence supporting diagnosis
- Code fix applied
- Test added to prevent regression (or recommendation if test framework absent)
- Prevention recommendation

Focus on the underlying issue. Never suppress errors or symptoms.
```

### 3.6 doc-writer

File: `~/.claude/agents/doc-writer.md`

```markdown
---
name: doc-writer
description: Writes README sections, inline documentation, ADR, CHANGELOG entries. Use after a feature merges or on explicit request.
tools: Read, Edit, Write, Glob, Grep
model: haiku
---

You are a technical writer for software projects.

Language rules:
- README user-facing: Italian
- ADR and architectural docs: Italian
- Inline docstrings on public API: English
- Commit messages: English (Conventional Commits)
- Comments explaining domain logic: Italian when it aids understanding

Style:
- Specific over abstract
- Examples over explanations
- Diagrams (ASCII) where structure helps
- Maximum signal per token

For long-form Italian content (LinkedIn posts, articles), invoke the human-writing-style skill.
```

### 3.7 refactorer

File: `~/.claude/agents/refactorer.md`

```markdown
---
name: refactorer
description: Improves code structure without changing behavior. Reduces duplication, simplifies logic, modernizes patterns. Use on explicit request or when reviewer flags structural issues.
tools: Read, Edit, Glob, Grep, Bash
model: sonnet
memory: project
---

You are a refactoring specialist.

Iron rules:
1. Existing tests must stay green. Run them before and after.
2. Maximum 200 lines changed per pass without a checkpoint
3. Each refactor commit must be behavior-preserving
4. If you cannot prove behavior preservation, stop and surface the risk

Patterns to apply:
- Extract method when a block has clear purpose
- Replace magic numbers with named constants
- Collapse duplicated branches
- Remove dead code (verified unused via grep)

Update your memory with refactoring patterns successful in this codebase.
```

### 3.8 researcher

File: `~/.claude/agents/researcher.md`

```markdown
---
name: researcher
description: Researches library documentation, API references, best practices, normative standards. Use when context7 MCP would help or when an unfamiliar library is being adopted.
tools: Read, Grep, Glob, WebSearch, WebFetch
model: haiku
effort: low
---

You are a technical researcher.

Sources priority:
1. Official documentation of the library/standard
2. Authoritative blogs (library author, language team)
3. Well-cited Stack Overflow / GitHub discussions
4. Recent dates only (last 18 months for fast-moving libraries)

Output discipline:
- Every claim has a URL citation
- Distinguish facts, opinions, and hypotheses
- If sources disagree, report the disagreement
- If you cannot verify, say "non verificato"

Return a concise brief, not an essay. The orchestrator decides what to act on.
```

### 3.9 Modello di costi

Modelli e effort scelti per ridurre token spend mantenendo qualità:

| Agente | Modello | Effort | Razionale |
|--------|---------|--------|-----------|
| architect | opus (→ 4.7) | **xhigh** | Default nativo Opus 4.7; ADR/design = passo più impattante della chain. Fallback a `high` automatico se dispatch con `model: sonnet` |
| reviewer, debugger | sonnet (→ 4.6) | **high** | Gate pre-commit e root-cause: richiede ragionamento, non solo esecuzione |
| coder, refactorer, tester | sonnet (→ 4.6) | **medium** | Eseguono piano già definito; reviewer a valle e snapshot harness coprono errori |
| doc-writer, researcher | haiku (→ 4.5) | **low** | Bottleneck è I/O (lettura codice/ricerca), non reasoning |

**Livelli effort disponibili per modello:**
- Opus 4.7: `low`, `medium`, `high`, `xhigh`, `max`
- Opus 4.6 / Sonnet 4.6: `low`, `medium`, `high`, `max` (`xhigh` → fallback a `high`)
- `max` è solo session-level (non persistibile in settings.json)

Override possibile a livello di singola invocazione via `CLAUDE_CODE_SUBAGENT_MODEL`.
Il default di sessione (`effortLevel: high` in settings.json) è overridato dal frontmatter del sub-agent; l'env var `CLAUDE_CODE_EFFORT_LEVEL` prevale su tutto.

---

## 4. CLAUDE.md globale (`~/.claude/CLAUDE.md`)

**Target <200 righe** secondo best practice Anthropic. Solo cose che applicano a ogni sessione. Tutto il resto va in skill, rules, hook.

```markdown
# CLAUDE.md — Stefano Ferri

## Identità

- Utente: Stefano Ferri
- Mi chiamo Adriano. L'utente è Stefano. Mai invertire.
- Lingua conversazione: italiano. Lingua codice e commit: inglese.
- Tono: diretto, conciso, tecnico. Niente filler, hype, soft CTA.

## Regole comportamentali invariabili

- IMPORTANT: Plan mode obbligatorio per qualunque task che modifica >1 file o tocca migrazioni/config produzione
- IMPORTANT: Conventional Commits in inglese (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`)
- IMPORTANT: Mai `git push --force` senza approvazione esplicita di Stefano
- IMPORTANT: Mai modificare migration già applicate in produzione
- IMPORTANT: Mai disabilitare test per farli passare. Se un test va cambiato, spiegare perché in chat prima.
- IMPORTANT: Confidence dichiarata in chat a fine task. Mai nei deliverable.

## Workflow di default

- Per task nuovo non triviale: interview mode → SPEC.md → fresh session → plan mode → implementazione
- Per feature multi-strato grande: considerare agent-teams (richiede `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
- Per task focalizzato: orchestrator + sub-agent custom
- HITL gate sempre prima di: commit, push, deploy, modifica schema DB, eliminazioni permanenti

## Sub-agent custom (in ~/.claude/agents/)

architect, coder, reviewer, tester, debugger, doc-writer, refactorer, researcher.
Vedi /agents per dettagli. Max 4 paralleli.

## Skill custom (in ~/.claude/skills/)

Da creare con `skill-creator` per workflow vibe coding:
claude-md-generator, swift-vibe, fastapi-react-vibe, code-review-checklist,
adr-writer, interview-driver, project-bootstrap.

## MCP server attivi

sequential-thinking, github, XcodeBuildMCP, sqlite/postgres-mcp.
Opzionali se installati: serena, context7, playwright.

## Risposta finale a ogni task

Chiudi con (in ordine):
1. Riepilogo 2-3 righe
2. File modificati (lista)
3. Test status: verde / rosso / non eseguito
4. Confidence (es. "92% — verificato su sample, manca test edge case X")

## Importazioni

Stack-specific va nei CLAUDE.md di progetto (root del progetto) o in .claude/rules/.
```

**Note di adesione (Anthropic):**
- CLAUDE.md è caricato come user message dopo il system prompt, non come system prompt. L'adesione non è garantita: serve specificità
- Parole chiave come "IMPORTANT" o "YOU MUST" aumentano l'adesione (verificato in best practice)
- Block-level HTML comment `<!-- nota -->` non consumano context (vengono strippati). Utili per note di manutenzione

**Settings complementari al CLAUDE.md (`~/.claude/settings.json`):**

Per branding professionale: disabilitare la firma automatica "Co-Authored-By: Claude" nei commit e nei PR.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "attribution": {
    "commit": "",
    "pr": ""
  },
  "permissions": {
    "defaultMode": "acceptEdits"
  }
}
```

- `$schema`: abilita autocomplete e validazione JSON in Cursor/VS Code
- `attribution.commit: ""`: rimuove "Co-Authored-By: Claude Sonnet ..." dal commit message. I commit appariranno come fatti da Stefano, niente attribution AI
- `attribution.pr: ""`: stesso per i PR body
- Senza questo override, Claude Code aggiunge di default un trailer `Co-Authored-By: Claude` (vecchio `includeCoAuthoredBy: false` è deprecato, usare `attribution`)

---

## 5. Path-scoped rules (`.claude/rules/`)

Pattern raccomandato da Anthropic per **non gonfiare CLAUDE.md**. Le rules con `paths:` frontmatter si caricano solo quando Claude tocca file matching.

### 5.1 Rules globali (`~/.claude/rules/`)

`~/.claude/rules/python.md`:

```markdown
---
paths:
  - "**/*.py"
---

# Python rules

- Type hint obbligatori su funzioni pubbliche; mypy strict mode
- Docstring stile Google per moduli e classi pubbliche
- f-string per formatting, mai `%` o `.format()`
- `pathlib.Path` invece di `os.path`
- Mai `print()` in codice produttivo: usa `logging`
- Async per I/O bound, sync per CPU bound
- Package manager: `uv` (non pip)
```

`~/.claude/rules/typescript-react.md`:

```markdown
---
paths:
  - "**/*.{ts,tsx}"
---

# TypeScript & React rules

- `interface` per props, `type` per union/utility
- Mai `any`: usa `unknown` + narrowing
- Function components + hooks, no class components
- `useState` per stato locale, Context/Zustand per condiviso
- Niente prop drilling oltre 2 livelli
- Mai `useEffect` senza dependencies array corretto
- Mai mutazioni dirette di state React
```

`~/.claude/rules/swift.md`:

```markdown
---
paths:
  - "**/*.swift"
---

# Swift & SwiftUI rules

- Preferisci `struct` su `class` salvo gerarchie reali
- `@Observable` (iOS 17+) invece di `ObservableObject` per nuovo codice
- `let` di default, `var` solo se serve mutabilità
- `private` di default
- Mai force-unwrap `!` in produzione, mai `try!` salvo casi documentati
- View < 150 righe, estrai in private struct quando cresce
- `body` puro: usa `.onAppear`, `.task`, `.onChange` per side effect
- `LazyVStack`/`LazyHStack` per liste lunghe
- Localizable.strings per tutti i testi utente
```

`~/.claude/rules/sql-migrations.md`:

```markdown
---
paths:
  - "**/alembic/versions/*.py"
  - "**/migrations/*.sql"
---

# DB migration rules

- IMPORTANT: Mai modificare una migration già applicata in produzione
- Backup DB pre-migration in produzione
- HITL gate prima di `alembic upgrade head` in qualunque ambiente diverso da dev
- Migration generate con `alembic revision --autogenerate -m "..."`
- Verificare sempre il diff generato prima del commit
```

### 5.2 Rules di progetto (`<repo>/.claude/rules/`)

Ogni progetto può avere rules specifiche commit-ate in git, condivise col team. Esempio per un'API in FastAPI:

`<repo>/.claude/rules/api-conventions.md`:

```markdown
---
paths:
  - "backend/src/**/api/**/*.py"
---

# API conventions

- Router per dominio in api/ (uno per feature)
- Response model Pydantic esplicito su ogni endpoint
- Status code: 200/201/204/400/401/403/404/422/500
- Dependency injection per DB session, auth, settings
- Mai `session.query(Model).filter(...)` (legacy): usa `select(Model).where(...)`
- Eager loading esplicito con `selectinload` / `joinedload`
```

### 5.3 Vantaggi pattern rules

1. CLAUDE.md resta sotto soglia <200 righe
2. Stefano vede solo le rules pertinenti al file su cui lavora
3. Context cost minimo (caricamento lazy per match path)
4. Modulare: aggiungere/rimuovere senza toccare CLAUDE.md

---

## 6. Template CLAUDE.md di progetto

### 6.1 Template SwiftUI / iOS

`<progetto-ios>/CLAUDE.md`:

```markdown
# CLAUDE.md — [NOME_PROGETTO] (iOS)

Eredita ~/.claude/CLAUDE.md. Specializza per questo progetto.

## Progetto

- Tipo: iOS app SwiftUI
- Target: iOS 17+
- Bundle ID: com.example.[nome]
- Swift 5.10+, SwiftUI puro, SwiftData

## Comandi (via XcodeBuildMCP)

- Build: `build` (Debug default)
- Test: `test` (XCTest + Swift Testing)
- Clean: `clean`
- Simulator: `simulator boot/install`
- Archive: solo su HITL gate esplicito

## Struttura

App/, Features/<Feature>/, Core/, DesignSystem/, Resources/, Tests/.

## Test target

70% coverage su business logic. UI test minimi: smoke + happy path.
Snapshot test opzionali per DesignSystem.

## Accessibility (obbligatoria)

- Ogni View interattiva ha .accessibilityLabel
- VoiceOver testato sui flussi principali
- Dynamic Type supportato

## Importazioni

@~/.claude/rules/swift.md
```

### 6.2 Template generico (FastAPI + React + Python)

`<progetto>/CLAUDE.md`:

```markdown
# CLAUDE.md — [NOME_PROGETTO]

Eredita ~/.claude/CLAUDE.md. Specializza per questo progetto.

## Progetto

- Tipo: web app (FastAPI backend + React frontend)
- Repository: [URL]
- Maintainer: Stefano Ferri

## Stack

| Layer | Scelte | Versione |
|-------|--------|----------|
| Backend | FastAPI + SQLAlchemy 2.x + Pydantic v2 + Alembic | latest |
| Frontend | React 19.2 + TypeScript 5.9 + Vite 6.4 + Tailwind 4.2 + shadcn/ui 4.0 | latest |
| DB dev | SQLite | — |
| DB prod | [DB di produzione: SQL Server / PostgreSQL / MySQL] | — |
| Package | uv (Python), pnpm (Node) | — |

## Comandi

- Backend test: `uv run pytest`
- Backend lint: `uv run ruff check`
- Frontend test: `pnpm test`
- Frontend lint: `pnpm lint`
- Type check: `uv run mypy src/` e `pnpm tsc --noEmit`

## Struttura

Vedi ARCH.md per dettagli. Backend in backend/src/, frontend in frontend/src/.

## Importazioni

@~/.claude/rules/python.md
@~/.claude/rules/typescript-react.md
@~/.claude/rules/sql-migrations.md
@./docs/architecture/ADR-INDEX.md
```

---

## 7. Hook — automazione deterministica

Gli hook sono shell command che girano in punti precisi del lifecycle. Sono **deterministici**: niente LLM coinvolto (salvo `type: prompt` o `agent`, **non disponibili su `Stop`** — vedi correzione 2026-05-19 in testa e admonition in 7.4/7.5). Garantiscono che un'azione succeda sempre.

**Ispezione:** `/hooks` apre l'hooks browser con tutti gli hook configurati per evento. Read-only, per modificare editare `settings.json`.

**Debug:** `InstructionsLoaded` hook fires quando un CLAUDE.md o un rules file viene caricato — utile per debug del path-scoped loading o lazy-load nei subdirectory.

### 7.1 Hook critici da configurare in `~/.claude/settings.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/auto-format.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Reminder: stack è FastAPI+React+TS, NO Flask/Bootstrap. Conventional Commits in inglese. Test verdi prima del commit.'"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude attende input\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}
```

### 7.2 Hook `protect-files.sh` (blocca .env, migration applicate, .git)

`~/.claude/hooks/protect-files.sh`:

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

PROTECTED_PATTERNS=(".env" "package-lock.json" "uv.lock" ".git/" "secrets.env")

for pattern in "${PROTECTED_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "Blocked: $FILE_PATH matches protected pattern '$pattern'. Ask Stefano explicitly." >&2
    exit 2
  fi
done

exit 0
```

```bash
chmod +x ~/.claude/hooks/protect-files.sh
```

### 7.3 Hook `auto-format.sh` (formattazione automatica dopo edit)

`~/.claude/hooks/auto-format.sh`:

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

case "$FILE_PATH" in
  *.py)
    ruff format "$FILE_PATH" 2>/dev/null
    ruff check --fix "$FILE_PATH" 2>/dev/null
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    if [ -f "package.json" ]; then
      npx prettier --write "$FILE_PATH" 2>/dev/null
    fi
    ;;
  *.swift)
    swift-format -i "$FILE_PATH" 2>/dev/null
    ;;
esac

exit 0
```

### 7.4 Hook avanzato — verifica test green prima dello Stop (prompt-based)

> ⚠️ **CORREZIONE 2026-05-19 — questo esempio è ERRATO.** Verifica live di
> `code.claude.com/docs/en/hooks`: `type: prompt` **non è supportato
> sull'evento `Stop`** (solo `command`, `http`, `mcp_tool`). Inoltre il
> contratto di blocco reale è `{"decision":"block","reason":"…"}` o exit code
> 2, **non** `{"ok": false}`. Pattern corretto: hook `type: command` su `Stop`
> + guardrail anti-loop a contatore (nessun `stop_hook_active` nativo).
> **AS-BUILT 2026-05-19:** implementato e deployato live come gate testcmd
> 3-tier + TOFU — vedi riconciliazione in testa e
> `docs/superpowers/specs/2026-05-19-swarm-testcmd-design.md` (+ plan omonimo).
> L'esempio JSON sotto è lasciato solo come storico.

In `~/.claude/settings.json`, sotto `hooks`:

```json
{
  "Stop": [
    {
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Check if the user's task is complete. If tests should have been run and weren't, or if obvious work remains, respond with {\"ok\": false, \"reason\": \"specific remaining work\"}. Otherwise {\"ok\": true}."
        }
      ]
    }
  ]
}
```

Questo hook usa Haiku in background per verificare la completezza. Se non OK, restituisce feedback che fa proseguire Claude.

### 7.5 Hook agent-based — verifica test green effettiva (più costoso)

> ⚠️ **CORREZIONE 2026-05-19 — questo esempio è ERRATO.** `type: agent` **non
> è supportato sull'evento `Stop`** (verifica live `code.claude.com/docs/en/hooks`).
> Per eseguire davvero i test prima dello Stop usare un hook `type: command`
> che invoca la test suite e blocca con `{"decision":"block","reason":"…"}` /
> exit code 2. **AS-BUILT 2026-05-19:** questa è esattamente la funzione
> dell'autoritative tier deployato (esegue il comando dichiarato in
> `.claude/test-cmd`, approvato via TOFU, exit code reale) — la "Fase B" del
> vecchio spec agentic-swarm è **subsunta** da esso. Vedi
> `docs/superpowers/specs/2026-05-19-swarm-testcmd-design.md` (+ plan omonimo).
> Esempio JSON sotto lasciato solo come storico.

```json
{
  "Stop": [
    {
      "hooks": [
        {
          "type": "agent",
          "prompt": "Run the project test suite. If any test fails or no test was run since last code change, respond with {\"ok\": false, \"reason\": \"test failures: <details>\"}.",
          "timeout": 120
        }
      ]
    }
  ]
}
```

Più affidabile (verifica reale), più costoso (subagent con tool access, fino a 50 turn).

### 7.6 Filesystem layout hook

```
~/.claude/                       # AS-BUILT 2026-05-19 (Stop-gate testcmd live)
├── settings.json                # hook globali (Stop→stop-gate.sh)
├── hooks/
│   ├── protect-files.sh         # PreToolUse  Edit|Write
│   ├── auto-format.sh           # PostToolUse Edit|Write
│   ├── mark-dirty.sh            # PostToolUse Edit|Write  → segna .dirty
│   ├── ensure-state-dir.sh      # SessionStart            → crea state dir
│   ├── reset-gate-counter.sh    # UserPromptSubmit        → reset anti-loop
│   ├── stop-gate.sh             # Stop  → gate 3-tier testcmd (CANONICO)
│   ├── stop-gate.v2.sh          #   gemello byte-identico (artefatto backout)
│   ├── approve-test-cmd.sh      # CLI TOFU (non un hook): approva test-cmd
│   ├── backup-before-deploy.sh  # utility backup pre-deploy
│   └── tests/run-hook-tests.sh  # harness unit (PASS=28 FAIL=0)
└── state/stop-gate/             # stato runtime: trust, <sid>.dirty/.count

<repo>/.claude/
├── test-cmd                     # dichiarazione per-progetto: comando | NONE
└── settings.json                # eventuali hook progetto-specifici
```

---

## 8. Skill — knowledge e workflow

### 8.1 Skill bundled (già disponibili in Claude Code)

| Skill | Uso |
|-------|-----|
| `/batch <instruction>` | Migrazione/refactor large-scale: decompose in 5-30 unità, parallelizza in worktree git, apre PR. Pattern Anthropic ufficiale per batch ops |
| `/simplify [focus]` | Review automatico recente: spawna 3 sub-agent review in parallelo, aggrega findings, applica fix |
| `/debug [description]` | Abilita debug logging, analizza log della sessione |
| `/loop [interval] <prompt>` | Esegui prompt ripetuto (utile per polling deploy, CI) |
| `/claude-api` | Carica reference API Claude per il linguaggio del progetto (Python, TS, Java, Go, ecc.) |

### 8.2 Skill custom — mapping agente → skill

| Sub-agent | Skill consigliate |
|-----------|-------------------|
| architect | `adr-writer` (nuova), `multi-role-brainstorm` (se presente) |
| coder | `swift-vibe` (nuova), `fastapi-react-vibe` (nuova), `json-validator` |
| reviewer | `code-review-checklist` (nuova) |
| tester | (nessuna specifica) |
| debugger | `pdf-reading`, `file-reading` |
| doc-writer | `human-writing-style` (se presente), `docx`/`pptx`/`xlsx`/`pdf` |
| refactorer | (nessuna specifica) |
| researcher | `youtube-dl` (se presente) |

### 8.3 Skill nuove da creare (con `skill-creator`)

Tutte in `~/.claude/skills/<nome>/SKILL.md`.

**`interview-driver`** — Avvia interview mode con prompt standard.

```yaml
---
name: interview-driver
description: Avvia interview mode con AskUserQuestion per definire SPEC.md di un nuovo progetto o feature. Use proattivamente all'inizio di qualunque progetto nuovo o feature non triviale.
argument-hint: [descrizione breve del progetto/feature]
disable-model-invocation: true
---

L'utente vuole costruire: $ARGUMENTS

Usa il tool AskUserQuestion per intervistare in profondità.
Copri: implementazione tecnica, UI/UX (se applicabile), edge case,
trade-off, vincoli operativi, Definition of Done.

Non fare domande ovvie. Scava sui punti difficili. Una domanda alla volta,
max 3-4 opzioni per domanda.

Continua finché non hai coperto tutto. Poi scrivi SPEC.md nella cartella corrente
con: obiettivi, scope, stack, architettura, modello dati, API, UI flows,
edge case, success criteria.
```

**`adr-writer`** — Genera ADR standardizzato.

```yaml
---
name: adr-writer
description: Genera Architecture Decision Record nella cartella docs/architecture/. Use quando l'utente prende una decisione architetturale o usa l'agente architect.
argument-hint: [titolo decisione]
---

Crea ADR-NNN-$ARGUMENTS.md in docs/architecture/ (con NNN incrementale).

Struttura obbligatoria:
1. Status (Proposed / Accepted / Deprecated / Superseded)
2. Context (problema, vincoli, requisiti)
3. Decision (scelta presa, in modo netto)
4. Alternatives considered (almeno 2, con motivo del rifiuto)
5. Consequences (positive, negative, neutre)
6. References (link a ADR correlati, doc, issue)

Niente fluff. Ogni sezione concreta e specifica.
```

**`claude-md-generator`** — Genera CLAUDE.md di progetto.

```yaml
---
name: claude-md-generator
description: Genera CLAUDE.md di root per un nuovo progetto basandosi su SPEC.md e ARCH.md. Use dopo che SPEC e ARCH sono pronti.
---

Leggi SPEC.md e ARCH.md della cartella corrente.

Genera CLAUDE.md di progetto seguendo il template appropriato:
- Se stack è SwiftUI/iOS → template iOS (sezione 6.1 del Vibe Coding System)
- Altrimenti → template generico (sezione 6.2)

Adatta: nome progetto, stack effettivo, comandi reali, struttura cartelle scelta.

Importa @~/.claude/rules/ rilevanti per lo stack.
Target: sotto 100 righe efficaci.
```

**`swift-vibe`** — Pattern e snippet SwiftUI.

```yaml
---
name: swift-vibe
description: Best practice SwiftUI con snippet pronti per View, ViewModel, SwiftData, async/await. Use quando si lavora su progetti iOS/SwiftUI.
paths:
  - "**/*.swift"
---

Best practice SwiftUI con snippet pronti.
Pattern: Observable+Bindable (iOS 17+), SwiftData @Query, URLSession async.
Espandi questa skill con altri pattern man mano che li incontri.
```

**`fastapi-react-vibe`** — Scaffold endpoint FastAPI + componente React.

```yaml
---
name: fastapi-react-vibe
description: Genera scaffold di un endpoint FastAPI con Pydantic schema, service, router, test, e relativo componente React con fetch hook. Use quando si aggiunge una feature CRUD a un progetto FastAPI+React.
argument-hint: [nome risorsa]
disable-model-invocation: true
---

Genera scaffold per la risorsa "$ARGUMENTS":

Backend (backend/src/<pkg>/):
- models/<arguments>.py: SQLAlchemy 2.x model con Mapped[]
- schemas/<arguments>.py: Pydantic v2 con Create/Update/Read
- services/<arguments>.py: business logic
- api/<arguments>.py: FastAPI router con CRUD endpoints
- tests/<arguments>_test.py: pytest con 4 test base

Frontend (frontend/src/):
- features/<arguments>/api.ts: fetch wrappers
- features/<arguments>/hooks.ts: useQuery / useMutation
- features/<arguments>/<Arguments>List.tsx: tabella shadcn/ui
- features/<arguments>/<Arguments>Form.tsx: form react-hook-form + zod
- routes: aggiungi route a routing config

Segui ADR esistenti. Match style con codice esistente.
```

**`code-review-checklist`** — Output strutturato per reviewer agent.

```yaml
---
name: code-review-checklist
description: Esegue review strutturata su git diff con checklist categorica. Use quando l'agente reviewer fa code review.
---

Esegui `git diff` e analizza le modifiche recenti.

Output strutturato per severità:

## BLOCKER (must fix prima di merge)
- ...

## MAJOR (should fix)
- ...

## MINOR (consider fixing)
- ...

## NIT (style/preference)
- ...

Per ogni issue: file:line + descrizione + suggested fix.

Categorie obbligatorie da coprire:
- Sicurezza (input validation, secret, auth)
- Correttezza (logica, edge case, error handling)
- Performance (N+1, blocking calls)
- Consistenza (pattern, ADR alignment)
- Test coverage
```

**`project-bootstrap`** — Esegue FASE 1 del workflow concept→code in un colpo.

```yaml
---
name: project-bootstrap
description: Esegue il bootstrap completo di un nuovo progetto (interview → SPEC.md → ARCH.md → CLAUDE.md). Use solo per progetti nuovi piccoli che giustificano un workflow rapido.
argument-hint: [descrizione breve]
disable-model-invocation: true
---

Bootstrap progetto: $ARGUMENTS

Step 1: invoca interview-driver con la descrizione
Step 2: dopo SPEC.md, genera ARCH.md (decisioni architetturali principali con ADR-001..N)
Step 3: invoca claude-md-generator per CLAUDE.md di root
Step 4: inizializza git, fai commit iniziale "chore: initial spec and architecture"
Step 5: presenta riepilogo dei file generati

HITL gate dopo ogni step. Stefano deve approvare prima di proseguire.
```

### 8.4 Path-scoped skills

Pattern: skill con `paths:` frontmatter si caricano solo per file matching. Riduce noise context.

Es. `swift-vibe` ha `paths: ["**/*.swift"]` — Claude vede la skill solo quando edita file Swift.

### 8.5 Skill con `context: fork`

Per skill che girano in sub-agent isolato (research pesante, batch ops):

```yaml
---
name: deep-research
description: Research approfondita in contesto isolato
context: fork
agent: Explore
---

Research $ARGUMENTS:
1. Usa Glob/Grep per trovare file rilevanti
2. Leggi e analizza
3. Riassumi findings con file references
```

`agent: Explore` usa il built-in Explore (Haiku, read-only). Il subagent fa il lavoro, il context principale riceve solo il sintesi.

---

## 9. MCP server

### 9.1 MCP core (da installare con priorità)

**Pattern raccomandato Anthropic**: usare il CLI `claude mcp add` invece di editare a mano `.mcp.json`. Lo scope di default è `local` (solo nel progetto corrente, in `~/.claude.json`). Per condividere col team: `--scope project` scrive in `.mcp.json` versionato.

```bash
# Sequential thinking (stdio)
claude mcp add --transport stdio --scope user sequential-thinking \
  -- npx -y @modelcontextprotocol/server-sequential-thinking

# GitHub remote MCP (HTTP — sostituisce il vecchio stdio @modelcontextprotocol/server-github)
claude mcp add --transport http --scope user github \
  https://api.githubcopilot.com/mcp/ \
  --header "Authorization: Bearer $GITHUB_TOKEN"

# SQLite locale (stdio)
claude mcp add --transport stdio --scope project sqlite \
  -- npx -y @modelcontextprotocol/server-sqlite --db-path ./dev.db

# XcodeBuildMCP (già installato da Stefano)
```

In alternativa, `.mcp.json` in root progetto per scope project (versionato col team):

```json
{
  "mcpServers": {
    "sequential-thinking": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer ${GITHUB_TOKEN}"
      },
      "alwaysLoad": false
    },
    "sqlite": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sqlite", "--db-path", "./dev.db"]
    }
  }
}
```

**Note importanti:**
- `${VAR}` espande env var; `${VAR:-default}` con fallback. Secret token mai inline
- Server-name `workspace` è riservato, mai usarlo
- `alwaysLoad: true` forza il caricamento di tutti i tool del server a session start (vedi 9.3 tool search)

### 9.2 MCP opzionali consigliati

- **serena**: LSP wrapper, code intelligence semantica. Utile su codebase grandi per refactor accurati
- **context7**: docs aggiornate librerie. Riduce allucinazioni quando il researcher fa lookup su API
- **playwright**: E2E test web automatici per il tester
- **filesystem-mcp esteso**: operazioni file batch

### 9.3 Tool search MCP

Anthropic abilita tool search di default (`ENABLE_TOOL_SEARCH=true`): solo i nomi dei tool MCP caricano a startup, gli schema completi sono deferred fino all'uso. Cost MCP idle è minimo.

Per server con tool che servono in ogni turn (es. github): `"alwaysLoad": true` nel server config. Carica tutti i tool a startup. Trade-off: più context consumato sempre, ma niente search step.

**Limiti output MCP:**
- Default 25,000 token per tool result; warning a 10,000
- Override: `MAX_MCP_OUTPUT_TOKENS=50000` in env per tool che producono output grandi (database query, log file)
- Server author può marcare singolo tool con `_meta["anthropic/maxResultSizeChars"]` fino a 500,000

**Diagnostica:** `/mcp` mostra status, token cost per server, e tool count. Disconnetti server inutilizzati.

---

## 10. Permission modes — guida operativa

Sei modi disponibili. Cycle con `Shift+Tab` (modalità incluse: default → acceptEdits → plan → auto). Auto e bypassPermissions richiedono attivazione esplicita.

| Modo | Comportamento | Quando usarlo |
|------|---------------|---------------|
| `default` | Chiede per ogni edit e bash | Inizio sessione, task sensibili, esplorazione |
| `acceptEdits` | Auto-accetta edit file, chiede per bash | Durante implementazione attiva |
| `plan` | Read-only, propone piano senza eseguire | Inizio nuova feature, refactor strutturale |
| `auto` | Classifier in background, blocca prompt injection e scope escalation | Task lunghi su Team/Enterprise plan |
| `dontAsk` | Auto-deny tutto tranne allowlist | CI, ambienti locked |
| `bypassPermissions` | Skip controlli (con eccezioni `.git`, `.claude`) | Container isolati, devcontainer |

### Per Stefano specificatamente

Memory dice "bypassPermissions mode configured". È OK ma rischioso per prompt injection. Alternative migliori:

1. **Se piano Pro/Max** (caso probabile di Stefano):
   - Default: `acceptEdits` (impostalo come default in `~/.claude/settings.json` → `permissions.defaultMode`)
   - Plan mode esplicito per nuove feature (`/plan` o `Shift+Tab` in sessione, `--permission-mode plan` a startup)
   - Allowlist per comandi ricorrenti (`uv run pytest`, `pnpm test`, `pnpm lint`, ecc.)

2. **Se passi a Team/Enterprise/API plan**:
   - `auto` mode è la nuova best practice: classifier Sonnet 4.6 in background, blocca prompt injection automatico
   - Richiede Sonnet 4.6 o Opus 4.6 come modello principale

3. **Per codebase grandi**: combina con hook `protect-files.sh` (sez. 7.2). I deny rules dei hook hanno precedenza su qualunque permission mode, inclusi `bypassPermissions`. Layered defense.

### Allowlist consigliata per Stefano

`~/.claude/settings.json` (esempio completo che combina permission mode, allowlist, attribution):

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "attribution": {
    "commit": "",
    "pr": ""
  },
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash(uv run pytest*)",
      "Bash(uv run ruff*)",
      "Bash(uv run mypy*)",
      "Bash(pnpm test*)",
      "Bash(pnpm lint*)",
      "Bash(pnpm build*)",
      "Bash(git status)",
      "Bash(git diff*)",
      "Bash(git log*)",
      "Bash(git add*)",
      "Bash(git commit*)",
      "Bash(rg*)",
      "Bash(fd*)"
    ],
    "deny": [
      "Bash(git push --force*)",
      "Bash(rm -rf*)"
    ]
  }
}
```

**Gestione UI:**
- `/config` apre l'interfaccia tabbed settings (Status, Config). Più comodo dell'editing diretto del JSON
- `/status` mostra quali setting source sono attive nella sessione corrente (User / Project / Local / Managed). Conferma che il file viene caricato

**Settings precedence** (alto → basso):
1. Managed settings (server o MDM)
2. CLI args (`--permission-mode`, `--settings`)
3. `.claude/settings.local.json` (gitignored, personale per il progetto)
4. `.claude/settings.json` (progetto, versionato)
5. `~/.claude/settings.json` (user)

Array (`permissions.allow`, `deny`) si **concatenano e deduplicano** attraverso gli scope; scalari (`defaultMode`, `model`) usano il valore con priorità più alta.

---

## 11. Workflow end-to-end: concept → code

> Pattern ufficiale Anthropic da `code.claude.com/docs/en/best-practices`
> (sezioni "Explore first, then plan, then code" e "Let Claude interview you").

### 11.1 Principi fondanti

1. **Interview before code**: per feature/progetti non triviali, AskUserQuestion prima del codice. Decisioni scoperte quando ancora "a buon mercato"
2. **Spec as source of truth**: output dell'intervista = `SPEC.md`
3. **Fresh session per implementare**: sessione nuova per coding (context pulito). Mai mischiare interview e coding nella stessa sessione
4. **Plan mode**: separa exploration da execution. `Ctrl+G` per editare il piano in editor
5. **Verification**: ogni feature ha modo di auto-verifica (test, screenshot, output atteso)
6. **Context aggressivo**: `/clear` tra task non correlati, `/compact` se serve compatibilità con focus, sub-agent per investigazioni profonde

### 11.2 Cowork vs Claude Code per fase

| Fase | Strumento ottimale |
|------|-------------------|
| Brainstorming, raccolta sorgenti | **Cowork** (UI, connector Gmail/GDrive/Notion) |
| Generazione SPEC.md (interview mode) | **Cowork** o **Claude Code** (entrambi validi) |
| Generazione ARCH.md | **Claude Code** (preferito, vicino al codice) |
| Generazione CLAUDE.md di root | **Claude Code** (testato subito) |
| Scaffold, dipendenze, struttura | **Claude Code** |
| Implementazione codice | **Claude Code** |
| Test, refactor, debug | **Claude Code** |
| PR, review, CI | **Claude Code** + `gh` CLI |
| Slide, doc cliente | **Cowork** (skill docx/pptx/pdf) |

### 11.3 Workflow A — Cowork → Claude Code

**Tempo stimato:** FASE 1 in Cowork 30-90 minuti, FASE 2 dipende dal progetto.

#### FASE 1 — Cowork (concept → spec → struttura)

**Step 1.1.** Apri Cowork. Tab Cowork → Nuovo progetto → nome `<nome-progetto>`. Allega cartella locale `~/dev/<nome>`. Mode: "Ask before acting".

**Step 1.2.** Brain dump. 2-3 paragrafi liberi dell'idea. Allega documenti, screenshot, mockup. Usa connettori (Notion, GDrive, GitHub) se utili.

**Step 1.3.** Avvia Interview Mode. Prompt:

```
Voglio costruire [breve descrizione 1-2 righe].

Intervistami in modo approfondito usando il tool AskUserQuestion.
Copri: implementazione tecnica, UI/UX, edge case, trade-off,
vincoli operativi, Definition of Done.

Non fare domande ovvie. Una domanda alla volta, max 3-4 opzioni.
Continua finché non hai coperto tutto. Poi scrivi SPEC.md.
```

**Step 1.4.** Rispondi alle domande (tipicamente 15-40, fino a 40+ per progetti grandi).

**Step 1.5.** Cowork genera SPEC.md. Verifica: obiettivi, scope, stack, architettura, dati, API, UI flows, edge case, success criteria.

**Step 1.6.** Genera ARCH.md:
```
Sulla base di SPEC.md, crea ARCH.md con diagramma a blocchi (ASCII),
decisioni architetturali (ADR-001..N), trade-off scartati,
struttura cartelle proposta.
```

**Step 1.7.** HITL gate: rileggi SPEC.md e ARCH.md. Modifica direttamente se serve. Quando ok, chiudi Cowork.

#### FASE 2 — Claude Code (CLAUDE.md → scaffold → implementazione)

**Step 2.1.** Apri Claude Code:
```bash
cd ~/dev/<nome>
claude
```

Verifica con `/memory` che `~/.claude/CLAUDE.md` sia caricato.

**Step 2.2.** Genera CLAUDE.md di progetto:
```
/claude-md-generator
```
(skill custom — sez. 8.3). Oppure prompt diretto:
```
Sulla base di SPEC.md e ARCH.md, genera CLAUDE.md di root usando il template
appropriato (SwiftUI/iOS o generico). Importa rules da ~/.claude/rules/.
Target sotto 100 righe.
```

**Step 2.3.** Inizializza git e commit iniziale:
```
inizializza git, fai commit iniziale "chore: initial spec and architecture"
con SPEC.md, ARCH.md, CLAUDE.md, docs/architecture/
```

**Step 2.4.** Scaffold del progetto. Entra in plan mode:
```
/plan
Leggi SPEC.md, ARCH.md, CLAUDE.md.
Proponi piano per scaffold iniziale: struttura cartelle, config file
(pyproject.toml / package.json / Package.swift), dipendenze minime,
test framework, linter, .gitignore.
Solo scaffold, no codice produttivo.
```

**Step 2.5.** HITL gate: approva il piano. `Ctrl+G` per editare.

**Step 2.6.** Esci da plan mode (Shift+Tab → acceptEdits). Esecuzione scaffold. Verifica setup funzioni. Commit.

**Step 2.7.** Prima feature (workflow multi-agente):

```
Implementa feature [nome] descritta in SPEC.md sezione [X].

Workflow:
1. Invoca @"architect (agent)" per ADR-NNN-<nome>.md
2. STOP per mia approvazione
3. Parallelizza max 4 sub-agenti:
   - @"coder (agent)" backend (se applicabile, isolation: worktree)
   - @"coder (agent)" frontend (se applicabile, isolation: worktree)
   - @"tester (agent)" 
   - @"doc-writer (agent)"
4. @"reviewer (agent)" finale
5. STOP per approvazione commit
6. Commit Conventional Commits in inglese
```

**Step 2.8.** Iterazione. Dopo ogni feature: `/clear` per pulire context. Per task non correlato: nuova sessione.

**Step 2.9.** PR finale:
```
Crea PR via github MCP. Titolo "feat(<scope>): <descrizione>".
Body: riassunto, link SPEC.md sezione, file modificati, test results.
```

### 11.4 Workflow B — Tutto in Claude Code

Identico ma con FASE 1 dentro Claude Code:

**Step B.1.** Crea cartella e apri Claude Code.

**Step B.2.** Invoca skill custom:
```
/project-bootstrap [descrizione breve]
```

Oppure manualmente:
```
/interview-driver [descrizione breve]
```

**Step B.3.** Stessi step 1.5-1.7 della variante A.

**Step B.4.** CRUCIALE: `/clear` o fresh session prima di scaffold (`claude --continue` o nuovo `claude`). Il context della interview inquina l'implementazione.

**Step B.5.** Procedi da Step 2.4 di variante A.

### 11.5 Diagramma del workflow

```
┌────────────────────────────────────────────────────────────┐
│ FASE 1 — CONCEPT & SPEC (Cowork o Claude Code)             │
│                                                             │
│   Brain dump → Interview mode (AskUserQuestion 15-40q)     │
│        ↓                                                    │
│   SPEC.md  ←──── HITL Stefano                              │
│        ↓                                                    │
│   ARCH.md (+ ADR-001..N)  ←──── HITL Stefano               │
│        ↓                                                    │
│   CLAUDE.md di root  ←──── HITL Stefano                    │
└─────────────────────┬──────────────────────────────────────┘
                      │
                /clear o fresh session
                      │
                      ▼
┌────────────────────────────────────────────────────────────┐
│ FASE 2 — IMPLEMENTAZIONE (Claude Code)                     │
│                                                             │
│   Scaffold (plan mode → HITL → execute → commit)           │
│        ↓                                                    │
│   ┌── Per ogni feature: ──────────────────────────────┐    │
│   │  architect → ADR → HITL                           │    │
│   │       ↓                                            │    │
│   │  [coder+tester+doc-writer paralleli (worktree)]   │    │
│   │       ↓                                            │    │
│   │  reviewer → HITL                                   │    │
│   │       ↓                                            │    │
│   │  Commit Conventional → PR github MCP              │    │
│   │       ↓                                            │    │
│   │  /clear                                            │    │
│   └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘
```

### 11.6 Quando usare agent-teams (anziché sub-agent)

Per feature complesse cross-strato Stefano può valutare agent-teams. Esempio per un'app web FastAPI+React:

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
claude
```

Prompt:
```
Crea un team di 4 teammate per implementare la feature [X]:
- backend-dev: implementa endpoint FastAPI + service + schema
- frontend-dev: implementa pagina React + form + tabella
- test-engineer: scrive test pytest e vitest per la feature
- reviewer: revisiona tutto il lavoro e segnala issue

Usa subagent definitions (architect per planning iniziale, poi spawna teammate
con i tool del subagent corrispondente). Coordinati via task list condivisa.
```

Vantaggi vs sub-agent:
- Ogni teammate ha context completo per il suo strato (vs sub-agent che ha solo summary)
- Possono dibattere e sfidarsi (utile in debugging con ipotesi competenti)
- Self-claim task: riducono coordinamento dell'orchestrator

Limitazioni:
- Solo Sonnet 4.6/Opus 4.6 per il lead
- No `/resume` con teammate in-process
- Più costoso (ogni teammate = sessione completa)
- 3-5 teammate ottimale, no scaling oltre
- `display mode`: `tmux` (split panes) o `in-process`. Su macOS Stefano può usare iTerm2 con `it2` CLI

---

## 12. Worktrees — parallelizzazione robusta

I sub-agent `coder` paralleli usano `isolation: worktree` nel frontmatter: ottengono automaticamente un worktree git isolato. Pattern interno gestito da Claude Code, niente da configurare lato sub-agent.

**Per Stefano (worktree manuali):**

```bash
# Terminal 1: feature auth
claude --worktree feature-auth
# crea .claude/worktrees/feature-auth/ con branch worktree-feature-auth

# Terminal 2: bug fix in parallelo
claude -w bugfix-payments
# -w è alias short di --worktree

# Worktree da PR specifico (review parallelo)
claude --worktree "#456"
# fetch pull/456/head e crea .claude/worktrees/pr-456/
```

**Pattern di branching (`worktree.baseRef` in settings.json):**

- Default `"fresh"`: branch da `origin/<default-branch>`. Worktree pulito, allineato col remote
- `"head"`: branch da HEAD locale. Porta commit non-pushati e stato feature-branch nel worktree. Utile per sub-agent che lavorano su work in-progress

```json
{
  "worktree": {
    "baseRef": "head",
    "symlinkDirectories": ["node_modules", ".cache"]
  }
}
```

**Caveats importanti:**
- Worktree NON copia automaticamente file gitignored (`.env`, `secrets.json`, ecc.) — vedi `.worktreeinclude` sotto
- Worktree condivide `.git` object database con la repo principale (efficiente su disco) ma non porta `node_modules`, `uv venv`, `target/`, `.next/`. Per progetti grandi due opzioni:
  - `worktree.symlinkDirectories: ["node_modules"]` — symlink dalla repo principale (rischio: lock file conflict, da testare)
  - Reinstallare deps nel worktree (`uv sync`, `pnpm install`) — sicuro, più lento

**`.worktreeinclude` — copia file gitignored nel worktree**

File a root del progetto (versionato col team) che lista file gitignored da copiare in ogni nuovo worktree. Sintassi gitignore.

```
# .worktreeinclude
.env
.env.local
config/secrets.json
```

Senza questo, ogni worktree appena creato manca dei file di env e deve essere setup-pato manualmente prima che test/build funzionino.

**Cleanup automatico:** worktree senza modifiche viene cleaned up automaticamente quando la sessione finisce. Worktree con modifiche persiste per review/merge manuale.

> **Fix 2.1.149 — sandbox write allowlist:** prima di questa versione la write allowlist in un worktree copriva l'intero repo principale invece del solo `.git/` condiviso (con `hooks/` e `config` denied). Risolto. Il sub-agent `coder` con `isolation: worktree` è ora correttamente sandboxato.

**Limiti pratici:**
- 2-4 worktree paralleli sono il ceiling ragionevole (oltre c'è solo overhead review)
- IDE multi-checkout: VS Code/Cursor OK. Altri (Xcode su iOS, alcuni JetBrains) flaky con i worktree

---

## 13. Auto memory

Feature reale di Claude Code (v2.1.59+). Salva learnings automatici in `~/.claude/projects/<repo>/memory/MEMORY.md`.

- Caricamento: prime 200 righe o 25KB di MEMORY.md ad ogni sessione
- Topic files (debugging.md, patterns.md, ecc.) caricati on-demand
- Ispezione: `/memory` per browse e edit
- Disable: `autoMemoryEnabled: false` in settings.json oppure `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` come env var
- Path personalizzato: `autoMemoryDirectory: "~/my-memory"` in settings (accettato solo da user settings, non da project — security: una repo clonata potrebbe redirigere le memory)

Per Stefano: lascia attivo. Claude accumula nel tempo pattern dei tuoi progetti (build command, debug insight, convenzioni). Verifica periodicamente via `/memory` per controllare cosa ha salvato.

**Sub-agent con `memory: project`** (definiti in sez. 3): hanno memoria separata in `.claude/agent-memory/<name>/`. Il reviewer accumula recurring issues, il debugger pattern di bug, l'architect decisioni passate. Condivisibili via git (utile su codebase con più collaboratori).

---

## 14. Plugin Anthropic marketplace

Pacchetti pronti da `/plugin`:

- **`superpowers`** (obra/superpowers): TDD enforcement, Socratic brainstorming, planning granulare, code review automatico tra task. Plugin ufficiale Anthropic marketplace.
- **`spec-kit`** (GitHub): Spec-Driven Development toolkit. Struttura Constitution → Specify → Plan → Tasks. Compatibile con qualunque agente di coding.
- **code intelligence plugin**: se installato per il linguaggio (Python, TypeScript, Swift), Claude ottiene symbol navigation precisa e error detection automatica dopo edit. Consigliato.

Installazione: `/plugin` → browse marketplace → install.

**Test locale prima di pacchettizzare un plugin:**

```bash
# Carica plugin direttamente da cartella locale (development/test)
claude --plugin-dir ./my-plugin

# Carica plugin da .zip remoto (CI/sharing veloce)
claude --plugin-url https://example.com/plugin.zip
```

**Quando Stefano avrà testato sul campo le 7 skill custom della sez. 8.3** (interview-driver, adr-writer, claude-md-generator, swift-vibe, fastapi-react-vibe, code-review-checklist, project-bootstrap), può impacchettarle in un plugin `stefano-vibe-coding` (skill + agents) e condividerlo via private GitHub repo. Vantaggio: versionato, aggiornabile, riutilizzabile.

---

## 15. Checklist installazione

### Globale (una volta sola, sui Mac di lavoro)

- [ ] Crea `~/.claude/CLAUDE.md` (sez. 4) — target <100 righe
- [ ] Crea `~/.claude/settings.json` con `attribution: {commit:"", pr:""}` per disabilitare firma Claude nei commit
- [ ] Crea `~/.claude/rules/python.md`, `typescript-react.md`, `swift.md`, `sql-migrations.md` (sez. 5.1)
- [ ] Crea sub-agent files in `~/.claude/agents/` per architect, coder, reviewer, tester, debugger, doc-writer, refactorer, researcher (sez. 3) — usa `/agents` interactive
- [ ] Crea hook globali in `~/.claude/settings.json` + script in `~/.claude/hooks/` (sez. 7)
- [ ] Configura permission mode default `acceptEdits` + allowlist (sez. 10)
- [ ] Installa MCP core via `claude mcp add --scope user` (sez. 9.1): sequential-thinking (stdio), github (HTTP), sqlite. XcodeBuildMCP già presente.
- [ ] Crea skill custom in `~/.claude/skills/` (`interview-driver`, `adr-writer`, `claude-md-generator`, `swift-vibe`, `fastapi-react-vibe`, `code-review-checklist`, `project-bootstrap`) usando `skill-creator`
- [ ] Valuta installazione plugin: `superpowers`, `spec-kit`, code intelligence per Python/TS/Swift
- [ ] Sync skill custom e agent custom via Git repo privato tra le macchine di sviluppo. Mai dentro iCloud Drive.

### Per progetto (per ogni nuovo progetto)

- [ ] Crea SPEC.md (interview mode FASE 1)
- [ ] Crea ARCH.md (con ADR-001..N)
- [ ] Crea CLAUDE.md di root (template appropriato, sez. 6) — target <100 righe
- [ ] Crea `.claude/rules/` con regole specifiche di progetto (es. API conventions, deployment)
- [ ] Crea `.mcp.json` di progetto con server specifici (es. sqlite con path dev.db locale)
- [ ] Crea `.claude/settings.json` con hook progetto-specifici (es. pre-commit lint)
- [ ] Crea `.worktreeinclude` con file gitignored da copiare nei worktree paralleli (`.env`, `secrets.json`)
- [ ] Aggiungi `CLAUDE.local.md` a `.gitignore` se servono preferenze personali non condivise

### Test end-to-end

- [ ] Esegui workflow concept→code completo su un mini-progetto pilota (es. piccolo tool Python)
- [ ] Verifica che sub-agent paralleli con `isolation: worktree` non creino conflitti
- [ ] Verifica hook `protect-files.sh` blocchi tentativi di edit a `.env`
- [ ] Verifica hook `auto-format.sh` formatti automaticamente dopo edit
- [ ] (Solo se hai Team/Enterprise plan) Test `auto` mode su task lungo

---

## 16. Best practice Anthropic — reference rapido

Top 10 da seguire sempre (da `code.claude.com/docs/en/best-practices`):

1. **Verification path sempre presente**: test, screenshot, output atteso
2. **Explore → Plan → Implement → Commit**: quattro fasi, mai mischiarle
3. **Context specifico**: file con `@`, riferimenti a pattern, descrizione sintomo
4. **Interview before code**: feature grandi → AskUserQuestion → SPEC.md
5. **Context aggressivo**: `/clear` tra task non correlati, sub-agenti per investigare
6. **Course-correct early**: `Esc` per stop, `/rewind` per checkpoint
7. **CLAUDE.md <200 righe**: taglia tutto ciò che Claude può inferire dal codice
8. **Hook per must-happen**: più deterministici di CLAUDE.md instructions
9. **Trust then verify**: sempre verification before ship
10. **Develop intuition**: queste regole sono starting point, non dogma

### Comandi e shortcut critici

| Comando | Funzione |
|---------|----------|
| `/init` (o `CLAUDE_CODE_NEW_INIT=1 /init`) | Genera CLAUDE.md base da codebase esistente |
| `/config` | UI tabbed per gestire settings (Status, Config) |
| `/status` | Mostra setting source attive nella sessione (User/Project/Local/Managed) |
| `/context` | Token usage per categoria: system prompt, memory, skill, MCP, messages |
| `/usage` | Breakdown costi per categoria: skill, subagent, plugin, MCP server (CC 2.1.149) |
| `/doctor` | Diagnostica installazione e configurazione |
| `/agents` | Browse/crea/edita sub-agent |
| `/hooks` | Browse hook configurati (read-only) |
| `/skills` | Skill disponibili da project, user, plugin |
| `/permissions` | Allowlist/denylist tool corrente |
| `/memory` | Browse CLAUDE.md, rules e auto memory |
| `/mcp` | Status MCP server, token cost, autenticazione OAuth |
| `/plugin` | Browse marketplace, install/enable plugin |
| `/clear` | Reset context |
| `/compact <istruzioni>` | Compatta con focus |
| `/rewind` o `Esc Esc` | Checkpoint precedenti |
| `/plan` | Single-turn plan mode (prefisso al prompt) |
| `/batch <instruction>` | Migrazione/refactor large-scale |
| `/code-review [effort]` | Review correttezza a effort configurabile; `--comment` per inline PR comment (ex `/simplify`, rinominato CC 2.1.147) |
| `/effort [level]` | Imposta effort level per la sessione; senza argomento apre slider interattivo |
| `/debug [desc]` | Debug logging sessione |
| `/loop [interval] <prompt>` | Polling task |
| `/btw <domanda>` | Quick question fuori context |
| `Ctrl+G` | Edita piano in editor |
| `Ctrl+B` | Backgroundizza task corrente |
| `Esc` | Stop Claude mid-action (mantiene context) |
| `Shift+Tab` | Cycle permission modes |
| `Shift+Down` | Cycle teammate (in agent-teams) |
| `@<file>` | Riferimento file diretto |
| `@"<agent-name> (agent)"` | Invocazione esplicita sub-agent |
| `claude --continue` | Riprendi ultima sessione |
| `claude --resume` | Scegli sessione da lista |
| `claude --worktree <name>` o `-w <name>` | Sessione in worktree isolato |
| `claude --worktree "#<pr>"` | Worktree da pull request |
| `claude --from-pr <number>` | Riprendi sessione associata a PR |
| `claude --agent <name>` | Avvia sessione come sub-agent (system prompt override) |
| `claude --plugin-dir <path>` | Test locale di un plugin in development |
| `claude -p "<prompt>"` | Non-interactive mode |

### Pattern Writer/Reviewer

Per code review critici, due sessioni distinte:

| Sessione A (Writer) | Sessione B (Reviewer) |
|---------------------|----------------------|
| Implementa la feature | (fresh context) |
| | Review @src/<file>.ts — cerca edge case, race condition, coerenza |
| Applica feedback B | |

Sessione B "fresh" → niente bias verso codice appena scritto.

### Anti-pattern Anthropic (da evitare)

| Errore | Sintomo | Fix |
|--------|---------|-----|
| Kitchen sink session | Context inquinato da task multipli | `/clear` tra task non correlati |
| Correzioni infinite | Bug + correzione + bug + correzione | Dopo 2 correzioni: `/clear` + prompt migliore |
| CLAUDE.md over-specified | Claude ignora regole | Pruning aggressivo, target <200 righe |
| Trust-then-verify gap | Codice plausibile ma rotto | Sempre verification (test/screenshot) |
| Infinite exploration | Claude legge 100 file, context pieno | Scope esplicito o sub-agente |
| Stessa sessione per interview + code | Context inquinato | Sessione fresh per coding |
| Saltare plan mode su multi-file | Codice "solve the wrong problem" | Plan mode quando: change multi-file, codice sconosciuto, approccio incerto |

---

## 17. Note finali

### Decisioni che possono evolvere

- **Modelli per agente**: oggi mappati su (Opus architect, Sonnet coder/reviewer/tester/debugger/refactorer, Haiku doc-writer/researcher). Da rivedere quando escono nuovi modelli o si misura il rapporto qualità/costo reale sui propri progetti
- **Cap parallelizzazione 4**: può salire a 5-6 una volta validata stabilità. Anthropic non impone hard limit
- **Coverage 70%**: alzabile a 85% sui moduli più critici (es. calcoli, validazione input sensibili, integrazioni esterne)
- **Agent teams in produzione**: oggi experimental. Quando esce GA, può sostituire molti pattern di sub-agent + worktree manuali

### Punti aperti residui

- **Validazione tier Stop-gate testcmd sul pilota**: il gate è deployato live e harness-verde, ma i 4 tier (nudge / opt-out / approve / autoritativo green+red) vanno validati end-to-end in sessione fresca su `~/developer/pricing-markup-cli` (piano swarm-testcmd Task 9 Steps 2-4, Stefano-run). Caveat: il pilota non ha test → serve almeno un test passante e un `test-cmd` robusto al PATH (es. `.venv/bin/pytest -q`)
- **Performance reale `auto` mode**: richiede passaggio a Team/Enterprise plan per testarlo. Se Stefano resta su Pro/Max, `acceptEdits` + hook protect è la strada
- **Auto memory hygiene**: pulire periodicamente `~/.claude/projects/<repo>/memory/` se cresce troppo o accumula errori. `/memory` per ispezione
- **Bootstrap remoto (CC 2.1.150)**: CC chiama `api.anthropic.com/api/claude_cli/bootstrap` all'avvio e GrowthBook (`tengu_heron_brook`) ogni 60s; inietta contenuto nel system prompt. È configurazione first-party (Anthropic), non injection da terze parti. Per ambienti con policy di immutabilità del prompt: aggiungere `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` in `settings.json` `env` block — blocca entrambi i canali
- **Skill testing**: le 7 skill custom proposte (sez. 8.3) vanno create con `skill-creator` e testate sul campo. Iterare description in base a trigger accuracy
- **`CLAUDE_CODE_NEW_INIT=1`**: vale la pena testare il nuovo flow multi-phase di `/init` che esplora codebase, fa follow-up question, propone CLAUDE.md + skill + hook insieme. Potrebbe sostituire il workflow concept→code per progetti piccoli

### Cose verificate vs assunte

**Verificate** contro doc Anthropic ufficiale:
- Architettura sub-agent (file YAML, frontmatter, built-in)
- Agent teams (architettura, limitazioni, attivazione)
- Permission modes (sei modi, behaviour, classifier)
- CLAUDE.md (load order, size target, AGENTS.md import)
- Skill (path-scoped, bundled, context: fork)
- Hook (eventi, type, esempi)
- MCP (configurazione, scoping, tool search)
- Workflow Explore→Plan→Implement→Commit
- Interview mode con AskUserQuestion → SPEC.md → fresh session

**Assunte/da validare in uso**:
- Modelli specifici per agente (Opus/Sonnet/Haiku mix proposto)
- Coverage 70% come target sensato per progetti tipici
- Cap 4 paralleli (può variare in pratica)
- Trigger description efficaci per skill custom

---

## Confidence finale

**98%** — alta confidenza su:

- Architettura sub-agent / agent-teams (sez. 2-3): verificata contro `code.claude.com/docs/en/sub-agents` e `agent-teams`. Built-in subagent, frontmatter fields, memory persistente, isolation worktree, model selection sono concetti reali e documentati Anthropic
- CLAUDE.md hygiene + `attribution` setting (sez. 4): target <200 righe è raccomandazione esplicita Anthropic, `attribution.commit:""` è il pattern moderno per disabilitare firma Claude (sostituisce deprecato `includeCoAuthoredBy`)
- Path-scoped rules in `.claude/rules/` (sez. 5): pattern documentato, glob support, frontmatter `paths:` verificato
- Hook (sez. 7): esempi protect-files, auto-format, SessionStart compact reinjection sono pattern Anthropic ufficiali. `/hooks` browser e `InstructionsLoaded` debug confermati. **CORREZIONE 2026-05-19:** la claim "`Stop` prompt/agent based" era **errata** — `type: prompt`/`agent` non supportati su `Stop` (verifica live docs). Spostato da "verificato" a corretto; vedi correzione 2026-05-19 in testa e admonition 7.4/7.5. **AS-BUILT 2026-05-19:** il pattern corretto (gate `type: command` 3-tier testcmd + TOFU + anti-loop) è **implementato e deployato live**, harness verde (PASS=28 FAIL=0) e verificato in sessione — verifica *as-built interna* (deploy + test), distinta dalla verifica-doc Anthropic; euristica `clear-dirty` ritirata
- MCP (sez. 9): `claude mcp add` CLI, scope local/project/user, transport http/sse/stdio, `alwaysLoad`, tool search, `MAX_MCP_OUTPUT_TOKENS` tutti verificati. GitHub HTTP remote endpoint è quello ufficiale corrente
- Permission modes (sez. 10): sei modi mappati 1:1 con doc, settings precedence verificata, `/config` e `/status` confermati
- Worktrees (sez. 12): `--worktree`, `-w`, `#<pr>`, `worktree.baseRef`, `.worktreeinclude`, path `.claude/worktrees/<name>/`, branch `worktree-<name>` tutti verificati da doc + search results recenti
- Workflow concept→code (sez. 11): pattern interview → SPEC.md → fresh session direttamente da doc best-practices
- Skill bundled (sez. 8.1): `/batch`, `/simplify`, `/debug`, `/loop`, `/claude-api` sono skill bundled reali, documentate
- Comandi diagnostici (sez. 16): `/config`, `/context`, `/status`, `/doctor`, `/skills`, `/permissions`, `/plugin` tutti verificati da claude-directory.md

**Resto 2%** — incertezza residua:

- Comportamento esatto di `isolation: worktree` con import condivisi (es. Python virtual env, `node_modules`). Teoricamente worktree git separato basta; in pratica va testato su progetti reali dove `uv` e Node modules sono pesanti. Mitigazioni note: `worktree.symlinkDirectories` o reinstall deps nel worktree
- Le 7 skill custom proposte (sez. 8.3) sono progettate ma non testate. Vanno create, testate sul trigger accuracy, iterate. Anthropic raccomanda iterazione su `description` field
- `auto` mode classifier comportamento reale su workflow Stefano: senza piano Team/Enterprise non posso testarlo. Indicazioni Anthropic chiare ma performance dipende da codebase

Riduzione del 2% richiede esecuzione reale + iterazione su progetto pilota.

---

**Fonti primarie verificate** (`code.claude.com/docs/`):

- `/en/best-practices` — best practice ufficiali
- `/en/sub-agents` — architettura sub-agent
- `/en/agent-teams` — multi-sessione coordinato
- `/en/memory` — CLAUDE.md, rules, auto memory
- `/en/skills` — skill system completo
- `/en/hooks-guide` — automazione hook
- `/en/permission-modes` — sei modi permission
- `/en/common-workflows` — workflow comuni
- `/en/features-overview` — quando usare cosa
- `/en/mcp` — MCP completo (transport, scope, OAuth, tool search, managed)
- `/en/claude-directory` — struttura `.claude/` e `~/.claude/`
- `/en/settings` — settings.json schema completo, precedence, attribution
- `/en/plugins` — sistema plugin completo
- `/en/worktrees` — verificata via search (URL non direttamente fetchable)
- `/en/llms.txt` — indice completo documentazione

Supplementari:
- `anthropic.com/engineering/claude-code-best-practices` — engineering blog
- `support.claude.com/.../get-started-with-claude-cowork` — help center Cowork
- `kondasamy.com/blog/2026/claude-code-interview-mode/` — pattern interview mode
- `developersdigest.tech/blog/claude-code-interview-mode` — pattern operativi
- `datacamp.com/tutorial/claude-code-best-practices` — TDD e spec-driven
- `pub.towardsai.net/...worktree-isolation...` — pattern worktree isolation aggiornato
