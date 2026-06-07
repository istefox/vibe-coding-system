# Plugin e MCP Server — Catalogo e Raccomandazioni

Ricerca condotta il 2026-06-04 via deep-research workflow (101 agenti, 19 fonti primarie/secondarie,
25 claims verificate in modo avversariale). Ogni sezione indica la fonte e il livello di confidenza.

---

## Stato attuale — Plugin installati

| Plugin | Versione | Categoria | Note |
|---|---|---|---|
| `code-review` | 42be4c4 | Review | Skill code-review attiva |
| `frontend-design` | 42be4c4 | Design | Skill frontend-design |
| `superpowers` | 5.1.0 | General | Utility generali |
| `context7` | 42be4c4 | Docs | **Integrato in architect + coder (2026-06-04)** |
| `swift-lsp` | 1.0.0 | LSP | SourceKit-LSP — verificare issue #379 |
| `typescript-lsp` | 1.0.0 | LSP | TS language server — verificare issue #379 |
| `pyright-lsp` | 1.0.0 | LSP | Python type checker — verificare issue #379 |
| `code-simplifier` | 1.0.0 | Quality | Semplificazione codice |
| `feature-dev` | 42be4c4 | Dev | Feature development workflow |
| `skill-creator` | 42be4c4 | Meta | Crea nuovi skill |
| `claude-md-management` | 1.0.0 | Meta | Gestione CLAUDE.md |
| `security-guidance` | 2.0.3 | Security | Linee guida sicurezza |
| `commit-commands` | 42be4c4 | Git | Commit, push, PR |
| `claude-code-setup` | 1.0.0 | Setup | Setup iniziale progetti |
| `plugin-dev` | 42be4c4 | Meta | Sviluppo plugin |
| `remember` | 0.7.3 | Memory | Persistenza sessione |
| `pydantic-ai` | 0.1.0 | AI | Pydantic AI integration |
| `cleaning-agent` | 0.1.0 | Utility | Disk cleanup (local plugin) |
| `warp` | 2.1.0 | Terminal | Warp terminal integration |

**Nessun MCP server esterno** configurato in `settings.json` al momento della ricerca.

---

## LSP plugins — FUNZIONANTI (Issue #379 chiusa)

**2026-06-04 — Investigazione diretta: tutti e tre i server LSP funzionano.**

La diagnosi originale era errata. Il file `.lsp.json` separato non esiste come formato: la
configurazione `lspServers` vive direttamente in `marketplace.json` e viene letta da Claude Code
all'avvio. I plugin non hanno bisogno di file aggiuntivi nella directory cache.

| Plugin | Binario | Stato |
|---|---|---|
| `swift-lsp` | `~/.swiftly/bin/sourcekit-lsp` | Funzionante — documentSymbol + diagnostics |
| `pyright-lsp` | `pyright-langserver` (fnm) | Funzionante — type-check diagnostics in tempo reale |
| `typescript-lsp` | `typescript-language-server` (fnm) | Funzionante — documentSymbol completo |

I file `.in_use/<pid>` nella directory cache confermano che i plugin sono caricati da ogni
sessione attiva — non sono un segnale di errore.

---

## Plugin ufficiali Anthropic — Da installare

### `pr-review-toolkit` — PRIORITÀ ALTA

**Fonte:** `github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit`
**Confidenza:** alta (3-0 adversarial)
**Installs:** non disponibile (plugin recente)

6 sub-agent specializzati per code review:

| Agent | Funzione |
|---|---|
| `comment-analyzer` | Analisi qualità commenti nel codice |
| `pr-test-analyzer` | Copertura test del PR |
| `silent-failure-hunter` | Errori silenziosi e failure handling |
| `type-design-analyzer` | Design dei tipi e interfacce |
| `code-reviewer` | Review generale qualità |
| `code-simplifier` | Opportunità di semplificazione |

Non richiede MCP server esterni. Complementa `review-triage-fix` skill aggiungendo
dimensioni specializzate che il review generico non copre.

```bash
claude plugin install pr-review-toolkit
```

---

### `code-modernization` — PRIORITÀ ALTA

**Fonte:** `github.com/anthropics/claude-plugins-official/tree/main/plugins/code-modernization`
**Confidenza:** alta (3-0 adversarial)
**Ultimo aggiornamento:** 3 giugno 2026

Workflow in 7 comandi sequenziali con 5 sub-agent specializzati. Utile per refactor di
architettura, legacy migration, modernizzazione di codebase esistenti.

**Comandi:**

| Comando | Funzione |
|---|---|
| `assess` | Valutazione iniziale del sistema |
| `map` | Mappatura componenti e dipendenze |
| `extract-rules` | Estrazione regole di business |
| `brief` | Briefing architetturale |
| `reimagine` | Proposta architettura target |
| `transform` | Piano di trasformazione |
| `harden` | Hardening e sicurezza |

**Sub-agent:**

| Agent | Ruolo |
|---|---|
| `legacy-analyst` | Analisi codice legacy |
| `business-rules-extractor` | Estrae logica di business implicita |
| `architecture-critic` | Review decisioni architetturali |
| `security-auditor` | Audit sicurezza |
| `test-engineer` | Strategia di test per la migrazione |

Tool locali opzionali (degradano gracefully se assenti): `scc`, `cloc`, `lizard`.

```bash
claude plugin install code-modernization
```

**Invocazione standalone (non integrato nel chain c2c):**

```
/code-modernization:modernize-assess [<system-dir>]
```

È un workflow per la migrazione di sistemi legacy, non per l'aggiunta di feature. Non fa parte
della chain concept-to-code. Usarlo come entry point separato su codebase brownfield da migrare.

---

### `serena` — PRIORITÀ MEDIA

**Fonte:** `claude.com/plugins` (Anthropic-verified badge)
**Confidenza:** alta (3-0 adversarial)
**Installs:** 81.000+

Analisi semantica del codice via LSP. Naviga il codebase corrente: simboli, riferimenti,
call graph. Complementa context7 (che porta docs aggiornate delle librerie) con navigazione
del codice vivo del progetto.

Più utile su codebase grandi con molti simboli da navigare cross-file. Su progetti piccoli
il valore è ridotto.

```bash
claude plugin install serena
```

---

### `greptile` — PRIORITÀ BASSA

**Fonte:** `claude.com/plugins`
**Confidenza:** alta
**Installs:** 50.000+

Ricerca AI-powered nel codebase per esplorazione architetturale. Utile per domande tipo
"dove viene gestita l'autenticazione?" su repo grandi. Meno utile su progetti singoli
già conosciuti.

```bash
claude plugin install greptile
```

---

### `sourcegraph` — PRIORITÀ BASSA

**Fonte:** `claude.com/plugins`
**Confidenza:** alta
**Installs:** 9.800+

Tracciamento riferimenti cross-codebase e analisi impatto refactor. Utile su monorepo o
quando si lavora su librerie condivise tra più progetti.

```bash
claude plugin install sourcegraph
```

---

## MCP Server esterni — Da aggiungere a settings.json

### ESLint MCP — PRIORITÀ ALTA (se usi TypeScript/JavaScript)

**Fonte:** `eslint.org/docs/latest/use/mcp`, `npmjs.com/package/@eslint/mcp`
**Confidenza:** alta (2-1 adversarial)
**Versione:** v0.3.5, giugno 2026
**Maintainer:** ESLint team (ufficiale)

Linting TypeScript/JavaScript diretto via MCP. Estratto dal core ESLint in v9.26.0.
Espone 3 tool: check file, fix issues, mostra violazioni per regola.

Configurazione `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "eslint": {
      "command": "npx",
      "args": ["@eslint/mcp@latest"]
    }
  }
}
```

Se il progetto usa config TypeScript (`.eslint.config.ts`), aggiungere `"-p", "jiti"` agli args:

```json
"args": ["@eslint/mcp@latest", "-p", "jiti"]
```

Nessuna installazione globale richiesta: `npx` scarica e mantiene aggiornato automaticamente.

---

### Semgrep MCP — PRIORITÀ MEDIA (security scanning)

**Fonte:** `github.com/semgrep/mcp`, `semgrep.dev/docs/mcp`
**Confidenza:** alta (3-0 adversarial)
**Path corretto:** via binary `semgrep mcp` (il repo standalone è archiviato da ottobre 2025)

Scanning di sicurezza su codice Swift, Python, TypeScript, e altri linguaggi.
Espone 3 tool: `security_check`, `semgrep_scan`, `semgrep_scan_with_custom_rule`.

Prerequisito:
```bash
pip install semgrep
```

Configurazione `settings.json`:

```json
{
  "mcpServers": {
    "semgrep": {
      "command": "semgrep",
      "args": ["mcp"]
    }
  }
}
```

**Attenzione:** non usare `uvx semgrep-mcp` — path deprecato, refutato in adversarial review (0-3).

---

### mcp-server-analyzer — PRIORITÀ MEDIA (solo Python 3.13+)

**Fonte:** `github.com/Anselmoo/mcp-server-analyzer`, `pypi.org/project/mcp-server-analyzer/`
**Confidenza:** alta (3-0 adversarial)
**Versione:** v0.2.1, maggio 2026
**Requisito:** Python 3.13+

Combina 3 engine in 6 tool MCP:

| Tool | Engine | Funzione |
|---|---|---|
| `ruff-check` | Ruff | Linting Python |
| `ruff-format` | Ruff | Formatting Python |
| `ruff-check-ci` | Ruff | Linting in CI mode |
| `ty-check` | ty (Astral) | Type checking (beta) |
| `vulture-scan` | Vulture | Dead code detection |
| `analyze-code` | tutti | Analisi combinata |

Configurazione `settings.json`:

```json
{
  "mcpServers": {
    "python-analyzer": {
      "command": "uvx",
      "args": ["mcp-server-analyzer"]
    }
  }
}
```

**Caveat:** `ty` è in beta (Astral, maggio 2026). Può generare falsi positivi.
Usare con cautela su progetti Python <3.13 — il server non funziona.

---

### mcp-language-server — PRIORITÀ BASSA (bridge LSP generico)

**Fonte:** `github.com/isaacphi/mcp-language-server`
**Confidenza:** media (2-1 su alcune claims)
**Maintainer:** community (Isaac Phi)

Bridge stdio che espone qualsiasi language server LSP come MCP server. Utile se vuoi
connettere un LSP non coperto dai plugin ufficiali Anthropic.

Tool esposti: `definition`, `references`, `hover`, `rename_symbol`, `edit_file`.

**Nota:** la claim sui diagnostics come linting è stata refutata (1-2). Non affidabile
per linting in senso stretto — utile per navigazione semantica.

Testato con: `gopls`, `rust-analyzer`, `pyright`, `typescript-language-server`, `clangd`.

---

## SwiftLint — Situazione attuale

**Nessun MCP server mantenuto per SwiftLint esiste** al momento della ricerca (giugno 2026).

- `swift-lsp` usa SourceKit-LSP (errori compiler, type checking) — NON esegue regole SwiftLint
- SwiftLens era il candidato principale, ma è archiviato dal 10 marzo 2026
- `mcp-language-server` può bridgare un LSP stdio ma la sua utilità per linting è non verificata

**Soluzione praticabile senza MCP:** hook `PostToolUse` in `settings.json` che esegue
`swiftlint lint --path <file>` dopo ogni Edit su file `.swift` e inietta il risultato
come contesto nella sessione. Approccio deterministico, zero dipendenze MCP.

---

## Plugin da evitare

| Tool | Motivo | Fonte |
|---|---|---|
| SwiftLens | Archiviato 10 marzo 2026, read-only | `github.com/swiftlens/swiftlens` (3-0) |
| ruff-mcp-server (drewsonne) | Claims refutate, tool non affidabile | adversarial vote 0-3 |
| `uvx semgrep-mcp` | Path deprecato (repo archiviato ottobre 2025) | adversarial vote 0-3 |
| DebugBase | 3 commit totali, 58 fix pairs, di fatto abbandonato | `github.com/DebugBase/mcp-server` |
| CodeRabbit (come plugin Claude) | Listing non confermato su claude.com/plugins | adversarial vote 1-2 |

---

## Domande aperte

1. Configurazione Semgrep corretta per `.mcp.json`? Il path `semgrep mcp` via binary
   è confermato ma la configurazione esatta in Claude Code non è stata testata localmente.

2. `mcp-server-analyzer` su Python <3.13: se i progetti non usano ancora 3.13, il server
   non è utilizzabile. Valutare solo dopo aggiornamento runtime.

3. SwiftLint via hook: se l'integrazione nativa manca, implementare il PostToolUse hook
   come soluzione interim.

---

## Riepilogo raccomandazioni

| Priorità | Azione | Comando |
|---|---|---|
| ~~Critica~~ | ~~Verificare issue #379 LSP plugins~~ | CHIUSA — plugin funzionanti |
| ~~Alta~~ | ~~Installare `pr-review-toolkit`~~ | FATTO 2026-06-04 |
| ~~Alta~~ | ~~Installare `code-modernization`~~ | FATTO 2026-06-04 |
| ~~Alta~~ | ~~Aggiungere ESLint MCP~~ | FATTO 2026-06-04 (`~/.claude/.mcp.json`) |
| Media | Installare `serena` | `claude plugin install serena` |
| Media | Aggiungere Semgrep MCP | Configurazione `settings.json` sopra |
| Media | Aggiungere mcp-server-analyzer (Python 3.13+) | Configurazione `settings.json` sopra |
| Bassa | Installare `greptile`, `sourcegraph` | Solo su codebase grandi/multi-repo |
| Futura | SwiftLint via PostToolUse hook | Da progettare se LSP non copre |

---

*Ricerca: deep-research workflow, 2026-06-04. 101 agenti, 19 fonti, 25 claims verificate.*
*Fonti primarie: `claude.com/plugins`, `github.com/anthropics/claude-plugins-official`,*
*`eslint.org/docs/latest/use/mcp`, `semgrep.dev/docs/mcp`, `github.com/isaacphi/mcp-language-server`.*
