# Spec — Sistema Definitivo di Vibe Coding (architettura completa)

**Data:** 2026-05-18
**Origine:** brainstorming su `docs/vibe-coding-system.md` (intero blueprint v2.1) + audit del `~/.claude/CLAUDE.md` reale contro best practice Anthropic ufficiali
**Stato progetto:** locale, NON versionato in git (istruzione utente)
**Pattern:** tutto generato in `staging/` in questo repo; nessuna scrittura in `~/.claude/` finché l'utente non esegue il deploy (HITL, con backup)

---

## 1. Obiettivo

Costruire il sistema completo di vibe coding descritto dal blueprint: dalla
progettazione di un'app, alla creazione del CLAUDE.md di progetto, fino
all'emanazione di agenti e di tutti i tool necessari. Base portante: un
`~/.claude/CLAUDE.md` globale **fully Anthropic-compliant**, utile per tutti i
progetti. Gli 8 agenti già creati vengono integrati nel sistema.

## 2. Decisioni di brainstorming (fissate)

| Asse | Decisione |
|---|---|
| CLAUDE.md globale | Clean-slate **fully Anthropic-compliant**, stack-neutral, base universale (merge della conoscenza non inferibile del file reale + estrazione stack-specific in rules + invarianti sez.4) |
| settings.json | **Auto mode + allowlist mirata**; rimossi `bypassPermissions` top-level, `skipAutoPermissionPrompt`, `Bash(*)`; `attribution:{commit:"",pr:""}` |
| Stack web | **Dual track** deciso per-progetto; globale stack-neutral |
| Strategia build | **Approccio 1 raffinato: staging plugin-ready** (foundation via staging+deploy; parte plugin-eligible già in layout plugin + `plugin.json`; packaging vero differito post field-test) |
| Riferimenti skill/MCP | Condizionali e graceful ("se disponibile X, altrimenti procedi") |
| Versionamento | Nessuna operazione git |

## 3. Fatti verificati (fonti)

**3.1 Capability boundary dei plugin** (fonte: skill ufficiale `plugin-dev/plugin-structure`).
Un plugin Claude Code pacchettizza SOLO: `commands/`, `agents/`, `skills/`,
`hooks/hooks.json`, `.mcp.json`, `scripts/`. **Non esiste meccanismo plugin** per
`~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `.claude/rules/`. Conseguenza:
il sistema è ibrido per natura — la fondazione (A,B,C) non è pacchettizzabile e
richiede staging+deploy; solo D,E,F,G sono plugin-eligible.

**3.2 Best practice CLAUDE.md** (fonti: `code.claude.com/docs/en/memory` e `/best-practices`,
lette il 2026-05-18). Sintesi: target <200 righe; includere solo ciò che Claude
non può inferire (comandi non ovvi, stile diverso dai default, repo etiquette,
decisioni architetturali, env quirks, gotcha); escludere convenzioni standard
note, pratiche self-evident, doc API; struttura markdown; specificità verificabile;
emphasis IMPORTANT sulle regole critiche; stack-specific → path-scoped rules;
contraddizioni → comportamento arbitrario.

**3.3 Audit del `~/.claude/CLAUDE.md` reale (106 righe). Voto 7/10.**
- Bene: dimensione <200, struttura, specificità, env quirks, knowledge non inferibile.
- Male: ~25-30% righe sono default noti (da potare); ~45 righe stack-specific inline
  da spostare in rules path-scoped; staleness "no React"/"Flask" vs blueprint;
  emphasis sotto-usata. → Percorso "Merge + estrazione" confermato.

**3.4 Schema frontmatter agente** (verificato nel ciclo precedente): solo
`name,description,model,color,tools`. Gli 8 agenti già creati lo rispettano (exit 0).

## 4. Architettura — albero di staging

```
vibe-coding-system/
├── docs/
│   ├── vibe-coding-system.md
│   ├── RUNBOOK.md                       # L: workflow concept→code + install step-by-step
│   └── superpowers/{specs,plans}/...
├── staging/
│   ├── user/                            # ZONA 1 → deploy in ~/.claude/ (NON pacchettizzabile)
│   │   ├── CLAUDE.md                    # A
│   │   ├── settings.json                # B
│   │   └── rules/{python,swift,typescript-react,web-vanilla,sql-migrations,shell}.md  # C
│   ├── plugin/                          # ZONA 2 → plugin-ready
│   │   ├── .claude-plugin/plugin.json
│   │   ├── agents/<8>.md                # E (spostati da agents/ root)
│   │   ├── skills/<7>/SKILL.md          # F
│   │   ├── hooks/hooks.json             # D
│   │   ├── scripts/{protect-files,auto-format}.sh   # D
│   │   └── .mcp.json                    # G (sequential-thinking, github)
│   └── project-templates/               # ZONA 3 → copiati per progetto
│       ├── app-fastapi-react/
│       ├── web-vanilla-wordpress/
│       └── ios-swiftui/
└── CLAUDE.md
```

Tre zone, tre destini: Zona 1 deploy-copy in `~/.claude/`; Zona 2 plugin-ready
(deploy-copy oggi, plugin domani a costo ~zero); Zona 3 non deployata (scaffold
per nuovo progetto).

## 5. Sottosistema A — `staging/user/CLAUDE.md` (~50 righe)

Trasformazione del file reale (106→~50 righe), 7 sezioni, zero stack-specific:
`Identità & Lingua` · `Ambiente` · `Workflow invarianti` (NUOVO) · `Git` (potato) ·
`Sicurezza & Guardrail` (IMPORTANT) · `Proattività` · `Dominio Vibrofer` (IMPORTANT).

- **TIENI**: italiano/tono/"Non ho dati sufficienti"/confidence-in-chat/fatti-vs-assunzioni;
  env quirks (macOS 26, Terminal no-IDE, Raycast, zsh, python3, venv, pip+requirements
  pinned, npm); Git (Conventional Commits inglese, feature branch mai main, branch
  naming); Sicurezza (mai delete senza conferma, mai secret, mai overwrite senza diff,
  mai distruttivo senza chiedere, backup file critici, modifiche minime); Proattività;
  Vibrofer (terminologia NEVER, RIVENDITORE, distretto ceramico mai target, brand
  color/font).
- **AGGIUNGI (sez.4 blueprint)**: plan mode se >1 file o migrazioni/config prod;
  HITL gate prima di commit/push/deploy/schema/eliminazioni; mai disabilitare test
  per farli passare; "se non puoi verificare, segnalalo".
- **POTA (default noti)**: f-string, pathlib, except specifico, ordine import,
  UPPER_SNAKE, enumerazione tipi commit, "max 88", idiomi Swift; rimuovi "no React"
  e "Flask" (stale, stack-neutral).
- **SPOSTA → rules C**: Python/Swift/Web/Shell style; → templates Zona 3:
  File Organization, Documentation/CHANGELOG.

## 6. Sottosistema B — `staging/user/settings.json`

File completo proposto, partendo dal reale:
- `attribution: {commit:"", pr:""}`.
- `permissions.defaultMode: "auto"`; **rimossi** top-level `defaultMode:"bypassPermissions"`,
  `skipAutoPermissionPrompt:true`, `Bash(*)`.
- `permissions.allow`: `Read, Edit, Write, mcp__*, WebFetch(*),
  Bash(git status), Bash(git diff*), Bash(git log*), Bash(git add*),
  Bash(git commit*), Bash(pip install*), Bash(pytest*), Bash(python3 -m pytest*),
  Bash(ruff*), Bash(black*), Bash(mypy*), Bash(npm run*), Bash(npm test*),
  Bash(rg*), Bash(fd*), Bash(gh issue *)`.
- `permissions.deny`: `Bash(rm -rf /), Bash(rm -rf ~), Bash(git push --force*),
  Bash(git push -f*)`.
- `hooks`: PreToolUse `Edit|Write`→`~/.claude/hooks/protect-files.sh`;
  PostToolUse `Edit|Write`→`~/.claude/hooks/auto-format.sh`; Stop→prompt-based
  completezza. **Preservato** l'hook SessionStart `.remember/logs` esistente.
- **Invariati**: `cleanupPeriodDays, env, statusLine, enabledPlugins,
  extraKnownMarketplaces, spinnerTipsEnabled, autoMode.allow`.

**Costruzione (importante per correttezza):** il file staged va generato
**leggendo il `~/.claude/settings.json` live al momento dell'esecuzione del
piano** e applicandovi i delta sopra — così resta un *superset fedele* (mantiene
ogni chiave attuale, incluso l'hook `.remember/logs` e `autoMode.allow`) anche se
il live è cambiato dopo questo spec. Questo rende sicuro l'overwrite `cp` del
RUNBOOK Step 3.

Trade-off dichiarato: rispetto a `bypassPermissions` qualche prompt in più su
azioni rischiose nuove (postura Anthropic auto+allowlist). Il live NON è toccato:
al deploy si mostra il diff e l'utente decide.

## 7. Sottosistema C — 6 rules path-scoped

`staging/user/rules/` → `~/.claude/rules/` (user-level). Principio audit: si tiene
solo il delta dai default + preferenze/dominio + high-stakes; si potano i default.
Allineamento: pip/npm (non uv/pnpm), Swift Testing (non XCTest).

| Rule | `paths:` | Sintesi contenuto |
|---|---|---|
| python.md | `**/*.py` | type hints obbligatori; docstring Google (Args/Returns/Raises); commenti sul WHY ("sii generoso, sto imparando"); `logging` non `print`; Black+Ruff; mypy strict; pytest + `test_<module>.py`; single test first. Pota: f-string/pathlib/except/import-order/UPPER_SNAKE/88 |
| swift.md | `**/*.swift` | Swift 6+SwiftUI (no UIKit salvo necessità); iOS+macOS stessa codebase; `@Observable`; mai force-unwrap/`try!` in prod; View<150→estrai; `body` puro; Lazy stack; Localizable.strings; SPM only; **Swift Testing, XCTest solo legacy**; SwiftLint+swift-format; 1 type/file; quirk Xcode auto-reload. Pota: let/var, private, Pascal/camelCase, async/await |
| typescript-react.md | `**/*.{ts,tsx}` | `interface` props/`type` union; mai `any`→`unknown`+narrowing; function comp+hooks; useState/Context\|Zustand; no prop-drilling>2; mai useEffect senza deps; mai mutazione state diretta; **npm** |
| web-vanilla.md | `**/*.{html,css,scss}` | track vanilla, no React; WordPress/Elementor mai core→child-theme/plugin; BEM; mobile-first; HTML semantico+ARIA; brand→rimanda al globale |
| sql-migrations.md | `**/migrations/*.sql`, `**/alembic/versions/*.py` | IMPORTANT mai modificare migration applicata in prod; backup DB pre-migration; HITL gate `alembic upgrade head` fuori da dev; `--autogenerate`; review diff prima del commit |
| shell.md | `**/*.{sh,bash}` | `set -euo pipefail`; shebang `#!/usr/bin/env bash`; `"${VAR}"` quotato; macOS pbcopy/pbpaste/open/osascript; AppleScript via `osascript -e` |

Nota `.js`: non globbato globalmente (collisione tooling Node); il track è
dichiarato dal CLAUDE.md di progetto (Zona 3).

## 8. Sottosistema D — hooks + script (`staging/plugin/`)

| Artefatto | Evento | Comportamento |
|---|---|---|
| `scripts/protect-files.sh` | PreToolUse `Edit\|Write` | exit 2 su `.env, .env.*, secrets*, *.pem, *.key, credentials*, .git/, package-lock.json` (no `uv.lock`; `requirements.txt` editabile) |
| `scripts/auto-format.sh` | PostToolUse `Edit\|Write` | `.py`→ruff format+--fix; `.ts/.tsx/.js/.jsx`→prettier se package.json; `.swift`→swift-format -i. Graceful: solo se `command -v` |
| Stop hook | Stop | `type: prompt`: lavoro residuo/test non eseguiti → `{ok:false,reason}` (Haiku, economico). Variante agent-based citata, non attiva |

Dualità: `plugin/hooks/hooks.json` usa `${CLAUDE_PLUGIN_ROOT}/scripts/...`; il
deploy-oggi registra in `settings.json` (B) verso `~/.claude/hooks/...`. Script
unici, identici (leggono JSON da stdin). I deny/protect hanno precedenza su
qualunque permission mode. Hook `.remember/logs` resta separato.

## 9. Sottosistema E — 8 agenti

Spostati da `agents/` → `staging/plugin/agents/` (sola fonte). Già validati
exit 0 nel ciclo precedente; spostamento, non riscrittura; ri-validazione
post-move per sanity path.

## 10. Sottosistema F — 7 skill (`staging/plugin/skills/<name>/SKILL.md`)

| Skill | Funzione | Migliorie |
|---|---|---|
| interview-driver | Interview→SPEC.md | `disable-model-invocation:true`, argument-hint |
| adr-writer | ADR in docs/architecture/ | Output allineato all'agente architect |
| claude-md-generator | CLAUDE.md di progetto da SPEC/ARCH | Produce CLAUDE.md lean Anthropic-compliant; sceglie tra i 3 template Zona 3 |
| swift-vibe | Pattern SwiftUI | Rimosso `paths:` (concetto da rules, non da skill) |
| fastapi-react-vibe | Scaffold FastAPI+React | `disable-model-invocation:true`; npm; rimosso `paths:` |
| code-review-checklist | Review BLOCKER/MAJOR/MINOR/NIT | Linkato graceful dall'agente reviewer |
| project-bootstrap | Orchestratore FASE 1 (interview→ARCH→claude-md→git init+commit) | git init OK (progetti nuovi); HITL dopo ogni step; può invocare agente architect |

Schema frontmatter skill verificato in planning su `plugin-dev:skill-development`
(come fatto per gli agenti). Riferimenti graceful. Le skill sfruttano gli 8 agenti.

## 11. Sottosistema G — `.mcp.json`

- `staging/plugin/.mcp.json` (globale): `sequential-thinking` (stdio npx);
  `github` (http, `Authorization: Bearer ${GITHUB_TOKEN}` — mai inline).
- `sqlite` (`--db-path ./dev.db`) è project-relative → template Zona 3, non globale.
- Token GitHub = step di setup nel RUNBOOK (non stageabile). Deploy: `claude mcp add`
  o copia `.mcp.json` (RUNBOOK).

## 12. Sottosistemi J/K/L — templates + runbook

3 template di progetto (Zona 3): `app-fastapi-react/` (CLAUDE.md lean +
`.claude/rules/api-conventions.md` + `.mcp.json` sqlite + `.worktreeinclude` +
snippet .gitignore), `web-vanilla-wordpress/` (CLAUDE.md, dichiara il track
vanilla), `ios-swiftui/` (CLAUDE.md, comandi XcodeBuildMCP). Tutti lean,
ereditano il globale, Anthropic-compliant.

`docs/RUNBOOK.md`: workflow concept→code (sez.11) + **procedura di installazione
step-by-step** (vedi RUNBOOK), ogni step con HITL + backup. Documentazione, non
eseguito in fase di build.

## 13. Validazione (DoD)

Validazione statica: JSON validi (settings.json, hooks.json, plugin.json,
.mcp.json); 8 agenti `validate-agent.sh` exit 0; 7 skill conformi a schema;
CLAUDE.md ≤ ~55 righe e stack-neutral; rules con `paths:` corretti; script bash
`bash -n` ok. Pilota E2E live = post-deploy (documentato nel runbook), non in
questo build.

## 14. Tracciabilità "Modifiche vs blueprint + CLAUDE.md reale"

| Area | Modifica principale |
|---|---|
| CLAUDE.md globale | Da 106→~50 righe; stack-specific→rules; potati default; +invarianti sez.4; rimossi "no React"/"Flask" (riconciliato dual-track) |
| settings.json | Rimossi bypassPermissions/skipAutoPermissionPrompt/Bash(*); auto+allowlist+deny; attribution disabilitata |
| rules | uv→pip, pnpm→npm; XCTest→Swift Testing; +shell.md +web-vanilla.md (non nel blueprint) |
| skill | Rimosso `paths:` da swift-vibe/fastapi-react-vibe (schema errato nel blueprint); claude-md-generator → output Anthropic-compliant + 3 template |
| .mcp.json | sqlite spostato a project-template (era globale nel blueprint); token solo env var |
| agenti | Rimossi campi inventati (effort/permissionMode/memory/isolation); +color; tools csv; già fatti nel ciclo precedente |
| struttura | Layout staging plugin-ready a 3 zone (non nel blueprint); packaging differito post field-test |

## 15. Fuori scope (esplicito)

Pilota E2E live; packaging/publishing plugin; esecuzione install MCP /
provisioning `GITHUB_TOKEN`; scrittura in `~/.claude/*` (solo al deploy HITL;
l'hook `.remember` già messo resta); git su questo repo; agenti/skill built-in
Anthropic; sync `~/.claude` multi-Mac (solo raccomandazione nel runbook).

## 16. Criteri di successo

Albero `staging/` completo e validato; RUNBOOK con install step-by-step; tabella
tracciabilità (sez.14); nulla scritto in `~/.claude/`; nessun git; confidence in
chat non nei deliverable; file copiabili 1:1 al deploy senza ulteriori edit.

---

## Emendamento 2026-05-18 — Stop hook scartato

Lo Stop hook `type: prompt` (sez.6 e sez.8) è stato **rimosso** dal sistema dopo
il deploy: in uso reale dava falsi positivi sistematici sulle pause volute
(assistente in attesa di input/decisione utente), generando loop di
ri-attivazione fino all'override del runtime (cap a 9 blocchi). Causa: i prompt
hook vanno scritti con loop-guard su `stop_hook_active`, ma anche con quello il
valore in un flusso interattivo con pause frequenti resta basso vs il rischio.
Decisione: **niente Stop hook prompt-based**. Rimosso da `~/.claude/settings.json`
(live, Opzione A), da `staging/user/settings.json` e da
`staging/plugin/hooks/hooks.json`. Restano `PreToolUse` (protect-files) e
`PostToolUse` (auto-format): hook deterministici di comando, nessun rischio loop.
