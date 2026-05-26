# Vibe Coding System — Implementation Plan (sistema definitivo)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **ADATTAMENTI (override utente):** progetto locale, NESSUNA operazione git, NESSUNA scrittura in `~/.claude/`. Gli step "commit" sono sostituiti da "validazione". Verifica = validator/JSON/`bash -n`, non TDD. Tutto in `staging/`.

**Goal:** Generare in `staging/` l'intero sistema di vibe coding (CLAUDE.md globale Anthropic-compliant, settings.json, 6 rules, 8 agenti ricollocati, 7 skill, hook, MCP, 3 project-template) pronto al deploy via RUNBOOK.

**Architecture:** 3 zone — `staging/user/` (deploy in ~/.claude/, non pacchettizzabile), `staging/plugin/` (layout plugin-ready), `staging/project-templates/` (scaffold per progetto). Ogni file lean, Anthropic-compliant, zero duplicazione delle regole globali.

**Tech Stack:** Markdown + YAML frontmatter, JSON (settings/hooks/plugin/mcp), Bash. Validatori: `plugin-dev/scripts/validate-agent.sh`, `python3 -m json.tool`, `bash -n`.

**Definition of Done globale:** tutti i JSON validi; 8 agenti `validate-agent.sh` exit 0; SKILL.md con frontmatter `name`+`description` (terza persona); CLAUDE.md ≤ 55 righe e zero stack-specific; rules con `paths:`; script `bash -n` ok. Warning cosmetici accettati (come ciclo precedente).

**Schema verificato (fonti ufficiali):** agente = `name,description,model,color,tools`; skill = `name,description` (+ opzionale `disable-model-invocation`); NO `argument-hint`/`paths` nelle skill; plugin component = commands/agents/skills/hooks/.mcp.json/scripts.

---

## File Structure

```
staging/
├── user/
│   ├── CLAUDE.md
│   ├── settings.json            # costruito da live + delta
│   └── rules/{python,swift,typescript-react,web-vanilla,sql-migrations,shell}.md
├── plugin/
│   ├── .claude-plugin/plugin.json
│   ├── agents/<8>.md            # mossi da agents/ root
│   ├── skills/{interview-driver,adr-writer,claude-md-generator,swift-vibe,fastapi-react-vibe,code-review-checklist,project-bootstrap}/SKILL.md
│   ├── hooks/hooks.json
│   ├── scripts/{protect-files.sh,auto-format.sh}
│   └── .mcp.json
└── project-templates/
    ├── app-fastapi-react/{CLAUDE.md,.claude/rules/api-conventions.md,.mcp.json,.worktreeinclude,gitignore-snippet.txt}
    ├── web-vanilla-wordpress/CLAUDE.md
    └── ios-swiftui/CLAUDE.md
```

---

### Task 0: Struttura cartelle

- [ ] **Step 1: Crea l'albero**

Run:
```bash
cd /Users/stefanoferri/Developer/vibe-coding-system
mkdir -p staging/user/rules staging/plugin/.claude-plugin staging/plugin/agents staging/plugin/skills staging/plugin/hooks staging/plugin/scripts staging/project-templates/app-fastapi-react/.claude/rules staging/project-templates/web-vanilla-wordpress staging/project-templates/ios-swiftui
```
Expected: exit 0.

- [ ] **Step 2: Verifica**

Run: `find staging -type d | sort`
Expected: elenca tutte le cartelle sopra.

---

### Task 1: `staging/user/CLAUDE.md` (globale, stack-neutral, ≤55 righe)

- [ ] **Step 1: Scrivi il file**

```markdown
# Istruzioni globali — Stefano Ferri

## Identità & Lingua
- IMPORTANT: rispondi sempre in italiano. Codice e commit in inglese; testo all'utente in italiano salvo richiesta diversa.
- Tono: diretto, tecnico, niente filler. Spiega un concetto avanzato in breve quando lo introduci.
- Se non sei sicuro: "Non ho dati sufficienti" — mai inventare dati, fonti o standard.
- Dichiara il livello di confidence in chat (alta/media/bassa), MAI nei file deliverable.
- Distingui sempre i fatti dalle assunzioni.

## Ambiente
- macOS 26 (Tahoe), Terminal (no IDE), Raycast, shell zsh.
- Python: usa `python3` (mai `python`). Venv: `python3 -m venv .venv && source .venv/bin/activate`.
- Dipendenze Python: `pip install -r requirements.txt`, versioni pinnate.
- Node per tooling: usa `npm` (non yarn/pnpm).

## Workflow invarianti
- IMPORTANT: plan mode obbligatorio per task che modifica >1 file o tocca migrazioni/config di produzione.
- IMPORTANT: HITL gate prima di commit, push, deploy, modifica schema DB, eliminazioni permanenti.
- IMPORTANT: mai disabilitare un test per farlo passare; se va cambiato, spiega perché in chat prima.
- Se non puoi verificare un risultato, segnalalo — non assumere che funzioni.
- Prima di dichiarare "fatto": linter + type check + test.

## Git
- Conventional Commits in inglese (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`).
- Sempre su feature branch, mai commit diretto su main. Branch: `type/short-description`.

## Sicurezza & Guardrail
- IMPORTANT: mai eliminare file senza conferma esplicita.
- IMPORTANT: mai committare `.env`, secret, API key, credenziali.
- IMPORTANT: mai sovrascrivere un file esistente senza prima mostrare il diff.
- IMPORTANT: mai comandi distruttivi (`rm -rf`, `DROP TABLE`) senza chiedere.
- Backup prima di modificare file critici. Quando editi codice esistente: modifiche minime, spiega cosa cambi e perché.

## Proattività
- Proponi migliorie, alternative ed edge case non considerati. Segnala errori, punti deboli, occasioni mancate.
- Se la richiesta è ambigua, chiedi prima di procedere — non tirare a indovinare.
- A fine task operativo proponi azioni concrete successive.

## Dominio Vibrofer
- IMPORTANT: mai "gomma tecnica" → sempre "articoli tecnici in gomma" o "articoli tecnici in gomma e gomma-metallo".
- IMPORTANT: mai "consegna 24h" in modo generico accanto a prodotti su misura.
- Clienti distributori/componentistica = categoria "RIVENDITORE". Distretto ceramico = MAI target strategico.
- Brand color: #be1622 #020a0a #2f4858 #646e78 #ea5b0c #ffcc00. Font: Titillium Web.
```

- [ ] **Step 2: Valida (righe + assenza stack-specific)**

Run:
```bash
wc -l < staging/user/CLAUDE.md
grep -nE 'f-string|pathlib|SwiftUI|React|pytest|Black|Ruff|BEM|UIKit|\.tsx|Elementor' staging/user/CLAUDE.md || echo "STACK-NEUTRAL OK"
```
Expected: righe ≤ 55; output `STACK-NEUTRAL OK`.

---

### Task 2: `staging/user/settings.json` (da live + delta)

**Files:** Create: `staging/user/settings.json`

- [ ] **Step 1: Parti dal file live e applica i delta**

Run:
```bash
cp ~/.claude/settings.json staging/user/settings.json
python3 -m json.tool staging/user/settings.json >/dev/null && echo "base copiata, JSON OK"
```

- [ ] **Step 2: Applica le trasformazioni esatte**

Modifica `staging/user/settings.json` così (preservando ogni altra chiave esistente: `cleanupPeriodDays`, `env`, `statusLine`, `enabledPlugins`, `extraKnownMarketplaces`, `spinnerTipsEnabled`, `autoMode`, e l'hook SessionStart `.remember/logs` già presente):

1. Rimuovi la chiave top-level `"defaultMode": "bypassPermissions"`.
2. Rimuovi la chiave top-level `"skipAutoPermissionPrompt": true`.
3. Imposta `"attribution": { "commit": "", "pr": "" }`.
4. In `permissions`: mantieni `"defaultMode": "auto"`; sostituisci `allow` e `deny` con esattamente:

```json
"allow": [
  "Read", "Edit", "Write", "mcp__*", "WebFetch(*)",
  "Bash(git status)", "Bash(git diff*)", "Bash(git log*)", "Bash(git add*)", "Bash(git commit*)",
  "Bash(pip install*)", "Bash(pytest*)", "Bash(python3 -m pytest*)",
  "Bash(ruff*)", "Bash(black*)", "Bash(mypy*)",
  "Bash(npm run*)", "Bash(npm test*)",
  "Bash(rg*)", "Bash(fd*)", "Bash(gh issue *)"
],
"deny": [
  "Bash(rm -rf /)", "Bash(rm -rf ~)", "Bash(git push --force*)", "Bash(git push -f*)"
]
```

5. Nella chiave `"hooks"` (preserva l'array `SessionStart` `.remember/logs` esistente) aggiungi:

```json
"PreToolUse": [
  { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "\"$HOME\"/.claude/hooks/protect-files.sh" } ] }
],
"PostToolUse": [
  { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "\"$HOME\"/.claude/hooks/auto-format.sh" } ] }
],
"Stop": [
  { "hooks": [ { "type": "prompt", "prompt": "Check if the user's task is complete. If tests should have been run and weren't, or obvious work remains, respond {\"ok\": false, \"reason\": \"specific remaining work\"}. Otherwise {\"ok\": true}." } ] }
]
```

- [ ] **Step 3: Valida**

Run:
```bash
python3 -m json.tool staging/user/settings.json >/dev/null && echo "JSON OK"
python3 -c "import json;d=json.load(open('staging/user/settings.json'));assert d.get('defaultMode')!='bypassPermissions';assert 'skipAutoPermissionPrompt' not in d;assert d['attribution']=={'commit':'','pr':''};assert 'Bash(*)' not in d['permissions']['allow'];assert d['permissions']['defaultMode']=='auto';assert 'PreToolUse' in d['hooks'] and 'PostToolUse' in d['hooks'] and 'Stop' in d['hooks'];print('DELTA OK')"
```
Expected: `JSON OK` e `DELTA OK`.

---

### Task 3: `staging/user/rules/python.md`

- [ ] **Step 1: Scrivi il file**

```markdown
---
paths:
  - "**/*.py"
---

# Python

- Type hint obbligatori su tutte le signature.
- Docstring stile Google su funzioni e classi pubbliche: Args, Returns, Raises.
- Commenti inline: spiega il WHY non il WHAT — sii generoso (sto imparando).
- `logging` in codice di produzione, mai `print()`.
- Formatter: Black. Linter: Ruff. Type check: mypy strict mode.
- Test: pytest, file `test_<module>.py`. Esegui prima il singolo test: `pytest tests/test_x.py::test_y -v`.
```

- [ ] **Step 2: Valida**

Run: `head -4 staging/user/rules/python.md | grep -q 'paths:' && echo "FRONTMATTER OK"`
Expected: `FRONTMATTER OK`.

---

### Task 4: `staging/user/rules/swift.md`

- [ ] **Step 1: Scrivi il file**

```markdown
---
paths:
  - "**/*.swift"
---

# Swift / SwiftUI

- Swift 6 + SwiftUI; UIKit solo se una feature lo richiede. iOS + macOS dalla stessa codebase quando possibile.
- `@Observable` (no `ObservableObject`) per nuovo codice. Mai force-unwrap `!` o `try!` in produzione.
- View < 150 righe: estrai in private struct. `body` puro: side-effect in `.task`/`.onAppear`/`.onChange`.
- `LazyVStack`/`LazyHStack` per liste lunghe. Testi utente in `Localizable.strings`.
- Package manager: SPM only (mai CocoaPods/Carthage).
- Test: Swift Testing (Swift 6) per nuovi test; XCTest solo per suite legacy esistenti.
- SwiftLint (+ `.swiftlint.yml`) e swift-format (Apple). 1 type principale per file, raggruppa per feature.
- Quirk: Claude edita i `.swift`, Xcode rileva e ricarica da solo.
```

- [ ] **Step 2: Valida**

Run: `head -4 staging/user/rules/swift.md | grep -q 'paths:' && echo "FRONTMATTER OK"`
Expected: `FRONTMATTER OK`.

---

### Task 5: `staging/user/rules/typescript-react.md`

- [ ] **Step 1: Scrivi il file**

```markdown
---
paths:
  - "**/*.{ts,tsx}"
---

# TypeScript & React

- `interface` per le props, `type` per union/utility.
- Mai `any`: usa `unknown` + narrowing.
- Function component + hooks (no class component).
- `useState` per stato locale; Context o Zustand per stato condiviso. No prop drilling oltre 2 livelli.
- Mai `useEffect` senza dependency array corretto. Mai mutazione diretta dello state.
- Package manager: `npm`.
```

- [ ] **Step 2: Valida**

Run: `head -4 staging/user/rules/typescript-react.md | grep -q 'paths:' && echo "FRONTMATTER OK"`
Expected: `FRONTMATTER OK`.

---

### Task 6: `staging/user/rules/web-vanilla.md`

- [ ] **Step 1: Scrivi il file**

```markdown
---
paths:
  - "**/*.{html,css,scss}"
---

# Web vanilla / WordPress

- Track vanilla: HTML5, CSS3, JS vanilla o framework minimi. NO React in questo track.
- WordPress/Elementor: mai modificare i file core del tema — usa child theme o plugin custom.
- CSS custom: convenzione BEM.
- Mobile-first responsive. HTML semantico + ARIA dove serve.
- Brand Vibrofer (color/font): vedi il CLAUDE.md globale, non duplicare qui.
```

- [ ] **Step 2: Valida**

Run: `head -4 staging/user/rules/web-vanilla.md | grep -q 'paths:' && echo "FRONTMATTER OK"`
Expected: `FRONTMATTER OK`.

---

### Task 7: `staging/user/rules/sql-migrations.md`

- [ ] **Step 1: Scrivi il file**

```markdown
---
paths:
  - "**/migrations/*.sql"
  - "**/alembic/versions/*.py"
---

# DB migrations

- IMPORTANT: mai modificare una migration già applicata in produzione.
- Backup del DB prima di una migration in produzione.
- HITL gate prima di `alembic upgrade head` in qualunque ambiente diverso da dev.
- Genera con `alembic revision --autogenerate -m "..."`.
- Rivedi sempre il diff generato prima del commit.
```

- [ ] **Step 2: Valida**

Run: `head -5 staging/user/rules/sql-migrations.md | grep -q 'paths:' && echo "FRONTMATTER OK"`
Expected: `FRONTMATTER OK`.

---

### Task 8: `staging/user/rules/shell.md`

- [ ] **Step 1: Scrivi il file**

```markdown
---
paths:
  - "**/*.{sh,bash}"
---

# Shell / macOS automation

- Header: `set -euo pipefail`. Shebang: `#!/usr/bin/env bash`.
- Variabili sempre quotate: `"${VAR}"`.
- macOS: preferisci `pbcopy`/`pbpaste`, `open`, `osascript` dove appropriato.
- AppleScript via `osascript -e`.
```

- [ ] **Step 2: Valida**

Run: `head -4 staging/user/rules/shell.md | grep -q 'paths:' && echo "FRONTMATTER OK"`
Expected: `FRONTMATTER OK`.

---

### Task 9: Ricolloca gli 8 agenti

**Files:** Move: `agents/*.md` → `staging/plugin/agents/`

- [ ] **Step 1: Sposta**

Run:
```bash
mv agents/architect.md agents/coder.md agents/reviewer.md agents/tester.md agents/debugger.md agents/doc-writer.md agents/refactorer.md agents/researcher.md staging/plugin/agents/
rmdir agents 2>/dev/null || true
ls staging/plugin/agents/
```
Expected: 8 file elencati; cartella `agents/` root rimossa.

- [ ] **Step 2: Ri-valida (sanity post-move)**

Run:
```bash
V="$HOME/.claude/plugins/cache/claude-plugins-official/plugin-dev/unknown/skills/agent-development/scripts/validate-agent.sh"
fail=0
for f in staging/plugin/agents/*.md; do bash "$V" "$f" >/tmp/v 2>&1 || true; grep -q "Validation failed" /tmp/v && { echo "FAIL $f"; fail=1; } || echo "OK $(basename $f)"; done
test $fail -eq 0 && echo "ALL OK"
```
Expected: 8 `OK`, `ALL OK`.

---

### Task 10: `staging/plugin/.claude-plugin/plugin.json`

- [ ] **Step 1: Scrivi il file**

```json
{
  "name": "stefano-vibe-coding",
  "version": "0.1.0",
  "description": "Stefano Ferri's vibe coding system: subagents, skills, hooks and MCP for concept-to-code workflow.",
  "author": { "name": "Stefano Ferri", "email": "stefano@stefer.it" },
  "keywords": ["workflow", "subagents", "skills", "vibe-coding"]
}
```

- [ ] **Step 2: Valida**

Run: `python3 -m json.tool staging/plugin/.claude-plugin/plugin.json >/dev/null && python3 -c "import json,re;n=json.load(open('staging/plugin/.claude-plugin/plugin.json'))['name'];assert re.fullmatch(r'[a-z0-9]([a-z0-9-]*[a-z0-9])?',n);print('PLUGIN.JSON OK')"`
Expected: `PLUGIN.JSON OK`.

---

### Task 11: `staging/plugin/scripts/protect-files.sh`

- [ ] **Step 1: Scrivi il file**

```bash
#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
PROTECTED=(".env" ".env." "secrets" ".pem" ".key" "credentials" "/.git/" "package-lock.json")
for p in "${PROTECTED[@]}"; do
  if [[ "$FILE_PATH" == *"$p"* ]]; then
    echo "Blocked: $FILE_PATH matches protected pattern '$p'. Ask Stefano explicitly." >&2
    exit 2
  fi
done
exit 0
```

- [ ] **Step 2: Valida sintassi + comportamento**

Run:
```bash
chmod +x staging/plugin/scripts/protect-files.sh
bash -n staging/plugin/scripts/protect-files.sh && echo "SYNTAX OK"
echo '{"tool_input":{"file_path":"/x/.env"}}' | bash staging/plugin/scripts/protect-files.sh; test $? -eq 2 && echo "BLOCK OK"
echo '{"tool_input":{"file_path":"/x/main.py"}}' | bash staging/plugin/scripts/protect-files.sh && echo "ALLOW OK"
```
Expected: `SYNTAX OK`, `BLOCK OK`, `ALLOW OK`.

---

### Task 12: `staging/plugin/scripts/auto-format.sh`

- [ ] **Step 1: Scrivi il file**

```bash
#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in
  *.py)
    command -v ruff >/dev/null 2>&1 && { ruff format "$FILE_PATH" 2>/dev/null || true; ruff check --fix "$FILE_PATH" 2>/dev/null || true; }
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    if [ -f package.json ] && command -v npx >/dev/null 2>&1; then npx --no-install prettier --write "$FILE_PATH" 2>/dev/null || true; fi
    ;;
  *.swift)
    command -v swift-format >/dev/null 2>&1 && { swift-format -i "$FILE_PATH" 2>/dev/null || true; }
    ;;
esac
exit 0
```

- [ ] **Step 2: Valida**

Run:
```bash
chmod +x staging/plugin/scripts/auto-format.sh
bash -n staging/plugin/scripts/auto-format.sh && echo "SYNTAX OK"
echo '{"tool_input":{"file_path":"/tmp/none.txt"}}' | bash staging/plugin/scripts/auto-format.sh && echo "NOOP OK"
```
Expected: `SYNTAX OK`, `NOOP OK`.

---

### Task 13: `staging/plugin/hooks/hooks.json`

- [ ] **Step 1: Scrivi il file**

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/protect-files.sh\"" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/auto-format.sh\"" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "prompt", "prompt": "Check if the user's task is complete. If tests should have been run and weren't, or obvious work remains, respond {\"ok\": false, \"reason\": \"specific remaining work\"}. Otherwise {\"ok\": true}." } ] }
    ]
  }
}
```

- [ ] **Step 2: Valida**

Run: `python3 -m json.tool staging/plugin/hooks/hooks.json >/dev/null && echo "HOOKS JSON OK"`
Expected: `HOOKS JSON OK`.

---

### Task 14: `staging/plugin/.mcp.json`

- [ ] **Step 1: Scrivi il file**

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
      "headers": { "Authorization": "Bearer ${GITHUB_TOKEN}" }
    }
  }
}
```

- [ ] **Step 2: Valida**

Run: `python3 -m json.tool staging/plugin/.mcp.json >/dev/null && grep -q '${GITHUB_TOKEN}' staging/plugin/.mcp.json && echo "MCP OK (no inline secret)"`
Expected: `MCP OK (no inline secret)`.

---

### Task 15: skill `interview-driver`

**Files:** Create: `staging/plugin/skills/interview-driver/SKILL.md`

- [ ] **Step 1: Scrivi il file**

```markdown
---
name: interview-driver
description: This skill should be used when starting a new project or non-trivial feature and a SPEC.md must be produced by interviewing the user in depth with the AskUserQuestion tool. Triggers include "intervistami", "facciamo lo SPEC", "nuovo progetto da zero".
disable-model-invocation: true
---

L'utente vuole costruire: $ARGUMENTS

Intervistalo in profondità con il tool AskUserQuestion. Copri: implementazione tecnica, UI/UX (se applicabile), edge case, trade-off, vincoli operativi, Definition of Done.

Non fare domande ovvie: scava sui punti difficili. Una domanda alla volta, max 3-4 opzioni per domanda. Continua finché non hai coperto tutto.

Poi scrivi `SPEC.md` nella cartella corrente con: obiettivi, scope, stack, architettura, modello dati, API, flussi UI, edge case, success criteria. Niente codice in questa fase.
```

- [ ] **Step 2: Valida**

Run: `python3 -c "import re;t=open('staging/plugin/skills/interview-driver/SKILL.md').read();fm=t.split('---')[1];assert 'name:' in fm and 'description:' in fm and 'argument-hint' not in fm and 'paths:' not in fm;print('SKILL OK')"`
Expected: `SKILL OK`.

---

### Task 16: skill `adr-writer`

- [ ] **Step 1: Scrivi il file**

```markdown
---
name: adr-writer
description: This skill should be used when an architectural decision has been taken (or the architect agent is producing a design) and a standardized Architecture Decision Record must be written under docs/architecture/. Triggers include "scrivi un ADR", "documenta questa decisione architetturale".
---

Crea `docs/architecture/ADR-NNN-$ARGUMENTS.md` (NNN incrementale, allineato all'output dell'agente architect).

Struttura obbligatoria, ogni sezione concreta, niente fluff:
1. Status (Proposed / Accepted / Deprecated / Superseded)
2. Context (problema, vincoli, requisiti)
3. Decision (la scelta presa, in modo netto)
4. Alternatives considered (almeno 2, con motivo del rifiuto)
5. Consequences (positive, negative, neutre)
6. References (ADR correlati, doc, issue)
```

- [ ] **Step 2: Valida**

Run: `python3 -c "t=open('staging/plugin/skills/adr-writer/SKILL.md').read();fm=t.split('---')[1];assert 'name:' in fm and 'description:' in fm and 'argument-hint' not in fm;print('SKILL OK')"`
Expected: `SKILL OK`.

---

### Task 17: skill `claude-md-generator`

- [ ] **Step 1: Scrivi il file**

```markdown
---
name: claude-md-generator
description: This skill should be used when SPEC.md and ARCH.md exist and a lean Anthropic-compliant project CLAUDE.md must be generated. Triggers include "genera il CLAUDE.md di progetto", "crea il claude.md di root".
---

Leggi `SPEC.md` e `ARCH.md` della cartella corrente.

Scegli il template appropriato fra i project-template del sistema (zona project-templates):
- stack SwiftUI/iOS → `ios-swiftui`
- web app FastAPI+React → `app-fastapi-react`
- sito web semplice/WordPress/vanilla → `web-vanilla-wordpress`

Genera `CLAUDE.md` di root **lean e Anthropic-compliant**:
- Eredita il `~/.claude/CLAUDE.md` globale: NON duplicare lingua, HITL, git, sicurezza, convenzioni di stile (sono nelle rules path-scoped).
- Includi solo ciò che Claude non può inferire dal codice: comandi build/test reali, decisioni architetturali del progetto, struttura cartelle scelta, gotcha.
- Target < 100 righe. Niente stack-specific che appartiene alle rules.
```

- [ ] **Step 2: Valida**

Run: `python3 -c "t=open('staging/plugin/skills/claude-md-generator/SKILL.md').read();fm=t.split('---')[1];assert 'name:' in fm and 'description:' in fm;print('SKILL OK')"`
Expected: `SKILL OK`.

---

### Task 18: skill `swift-vibe`

- [ ] **Step 1: Scrivi il file**

```markdown
---
name: swift-vibe
description: This skill should be used when working on SwiftUI/iOS code and ready-to-use modern patterns are helpful (Observable+Bindable iOS 17+, SwiftData @Query, URLSession async/await). Triggers include "pattern SwiftUI", "snippet SwiftData", "come faccio questa view".
---

Best practice SwiftUI con snippet pronti.

Pattern principali:
- `@Observable` + `@Bindable` (iOS 17+) per lo stato.
- SwiftData con `@Query` per il fetch dichiarativo.
- `URLSession` con async/await per il networking.
- View piccole e composte; side-effect in `.task`/`.onAppear`/`.onChange`.

Rispetta la rule `swift.md`. Espandi questa skill con altri pattern man mano che li incontri.
```

- [ ] **Step 2: Valida**

Run: `python3 -c "t=open('staging/plugin/skills/swift-vibe/SKILL.md').read();fm=t.split('---')[1];assert 'paths:' not in fm and 'name:' in fm;print('SKILL OK (no paths)')"`
Expected: `SKILL OK (no paths)`.

---

### Task 19: skill `fastapi-react-vibe`

- [ ] **Step 1: Scrivi il file**

```markdown
---
name: fastapi-react-vibe
description: This skill should be used when adding a CRUD resource to a FastAPI+React project and a full backend+frontend scaffold is needed. Triggers include "scaffolda la risorsa X", "nuovo endpoint CRUD FastAPI+React".
disable-model-invocation: true
---

Genera lo scaffold per la risorsa "$ARGUMENTS".

Backend (`backend/src/<pkg>/`):
- `models/<arguments>.py`: SQLAlchemy 2.x model con `Mapped[]`
- `schemas/<arguments>.py`: Pydantic v2 (Create/Update/Read)
- `services/<arguments>.py`: business logic
- `api/<arguments>.py`: router FastAPI con CRUD
- `tests/<arguments>_test.py`: pytest, 4 test base

Frontend (`frontend/src/`):
- `features/<arguments>/api.ts`: fetch wrapper
- `features/<arguments>/hooks.ts`: useQuery/useMutation
- `features/<arguments>/<Arguments>List.tsx`: tabella shadcn/ui
- `features/<arguments>/<Arguments>Form.tsx`: form react-hook-form + zod
- aggiungi la route alla config di routing

Package manager: `npm`. Segui gli ADR esistenti e lo stile del codice presente.
```

- [ ] **Step 2: Valida**

Run: `python3 -c "t=open('staging/plugin/skills/fastapi-react-vibe/SKILL.md').read();fm=t.split('---')[1];assert 'disable-model-invocation' in fm and 'paths:' not in fm and 'argument-hint' not in fm;print('SKILL OK')"`
Expected: `SKILL OK`.

---

### Task 20: skill `code-review-checklist`

- [ ] **Step 1: Scrivi il file**

```markdown
---
name: code-review-checklist
description: This skill should be used when a structured code review of recent changes is needed, producing findings grouped by severity. Triggers include "review strutturata", "checklist di review", and use by the reviewer agent.
---

Esegui `git diff` e analizza le modifiche recenti.

Output per severità:

## BLOCKER (fix prima del merge)
## MAJOR (should fix)
## MINOR (consider fixing)
## NIT (style/preferenza)

Per ogni issue: `file:line` + descrizione + suggested fix.

Categorie obbligatorie: Sicurezza (input validation, secret, auth), Correttezza (logica, edge case, error handling), Performance (N+1, blocking call), Consistenza (pattern, ADR), Test coverage.
```

- [ ] **Step 2: Valida**

Run: `python3 -c "t=open('staging/plugin/skills/code-review-checklist/SKILL.md').read();fm=t.split('---')[1];assert 'name:' in fm and 'description:' in fm;print('SKILL OK')"`
Expected: `SKILL OK`.

---

### Task 21: skill `project-bootstrap`

- [ ] **Step 1: Scrivi il file**

```markdown
---
name: project-bootstrap
description: This skill should be used only for a small new project that justifies a fast end-to-end bootstrap (interview to SPEC to ARCH to CLAUDE.md to initial commit). Triggers include "bootstrap del progetto", "parti da zero veloce".
disable-model-invocation: true
---

Bootstrap del progetto: $ARGUMENTS

Step (HITL gate dopo ognuno — l'utente approva prima di proseguire):
1. Invoca la skill `interview-driver` con la descrizione → `SPEC.md`.
2. Genera `ARCH.md` (decisioni principali con ADR-001..N); puoi invocare l'agente `architect`.
3. Invoca la skill `claude-md-generator` per il `CLAUDE.md` di root.
4. `git init` + commit iniziale "chore: initial spec and architecture" (questo vale per i progetti NUOVI, non per il repo del sistema).
5. Presenta il riepilogo dei file generati.
```

- [ ] **Step 2: Valida**

Run: `python3 -c "t=open('staging/plugin/skills/project-bootstrap/SKILL.md').read();fm=t.split('---')[1];assert 'disable-model-invocation' in fm and 'name:' in fm;print('SKILL OK')"`
Expected: `SKILL OK`.

---

### Task 22: project-template `app-fastapi-react`

- [ ] **Step 1: `staging/project-templates/app-fastapi-react/CLAUDE.md`**

```markdown
# CLAUDE.md — [NOME_PROGETTO]

Eredita `~/.claude/CLAUDE.md` e le rules globali. Qui solo ciò che è specifico del progetto.

## Progetto
- Web app: backend FastAPI + frontend React.

## Stack
- Backend: FastAPI + SQLAlchemy 2.x + Pydantic v2 + Alembic.
- Frontend: React 19 + TypeScript + Vite + Tailwind + shadcn/ui.
- DB dev: SQLite. Package: pip (Python), npm (Node).

## Comandi
- Backend test: `pytest`
- Backend lint/type: `ruff check` · `mypy src/`
- Frontend test: `npm test`
- Frontend lint/type: `npm run lint` · `npm run tsc`

## Struttura
Backend in `backend/src/`, frontend in `frontend/src/`. Dettagli in `ARCH.md`.

## Note
- Aggiungi `CLAUDE.local.md` a `.gitignore` per preferenze personali non condivise.
```

- [ ] **Step 2: `staging/project-templates/app-fastapi-react/.claude/rules/api-conventions.md`**

```markdown
---
paths:
  - "backend/src/**/api/**/*.py"
---

# API conventions
- Un router per dominio in `api/` (uno per feature).
- Response model Pydantic esplicito su ogni endpoint.
- Status code: 200/201/204/400/401/403/404/422/500.
- Dependency injection per DB session, auth, settings.
- Usa `select(Model).where(...)` (no `session.query(...)` legacy).
- Eager loading esplicito: `selectinload`/`joinedload`.
```

- [ ] **Step 3: `staging/project-templates/app-fastapi-react/.mcp.json`**

```json
{
  "mcpServers": {
    "sqlite": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sqlite", "--db-path", "./dev.db"]
    }
  }
}
```

- [ ] **Step 4: `staging/project-templates/app-fastapi-react/.worktreeinclude`**

```
.env
.env.local
config/secrets.json
```

- [ ] **Step 5: `staging/project-templates/app-fastapi-react/gitignore-snippet.txt`**

```
# Aggiungi questa riga al .gitignore del progetto:
CLAUDE.local.md
```

- [ ] **Step 6: Valida**

Run: `python3 -m json.tool staging/project-templates/app-fastapi-react/.mcp.json >/dev/null && test -f staging/project-templates/app-fastapi-react/.claude/rules/api-conventions.md && echo "APP TEMPLATE OK"`
Expected: `APP TEMPLATE OK`.

---

### Task 23: project-template `web-vanilla-wordpress`

- [ ] **Step 1: `staging/project-templates/web-vanilla-wordpress/CLAUDE.md`**

```markdown
# CLAUDE.md — [NOME_PROGETTO]

Eredita `~/.claude/CLAUDE.md` e le rules globali. Qui solo specifico del progetto.

## Progetto
- Track vanilla: sito web HTML/CSS/JS (eventuale WordPress/Elementor). NESSUN React.

## Convenzioni
- WordPress: child theme o plugin custom, mai core del tema.
- CSS custom: BEM. Mobile-first. HTML semantico + ARIA.
- Nessun build step salvo necessità esplicita; se serve, dichiararlo qui.

## Comandi
- (compila qui gli eventuali comandi reali: lint, build, deploy)

## Note
- Brand Vibrofer: vedi CLAUDE.md globale.
```

- [ ] **Step 2: Valida**

Run: `grep -q 'NESSUN React' staging/project-templates/web-vanilla-wordpress/CLAUDE.md && echo "WEB TEMPLATE OK"`
Expected: `WEB TEMPLATE OK`.

---

### Task 24: project-template `ios-swiftui`

- [ ] **Step 1: `staging/project-templates/ios-swiftui/CLAUDE.md`**

```markdown
# CLAUDE.md — [NOME_PROGETTO] (iOS/macOS)

Eredita `~/.claude/CLAUDE.md` e la rule `swift.md`. Qui solo specifico del progetto.

## Progetto
- App SwiftUI, target iOS 17+ (e macOS se multipiattaforma). Swift 6, SwiftData.

## Comandi (via XcodeBuildMCP)
- Build: `build` (Debug default)
- Test: `test` (Swift Testing)
- Clean: `clean` · Simulator: `simulator boot/install`
- Archive: solo su HITL gate esplicito.

## Struttura
`App/`, `Features/<Feature>/`, `Core/`, `DesignSystem/`, `Resources/`, `Tests/`.

## Accessibilità (obbligatoria)
- `.accessibilityLabel` su ogni View interattiva. VoiceOver sui flussi principali. Dynamic Type.
```

- [ ] **Step 2: Valida**

Run: `test -f staging/project-templates/ios-swiftui/CLAUDE.md && grep -q 'XcodeBuildMCP' staging/project-templates/ios-swiftui/CLAUDE.md && echo "IOS TEMPLATE OK"`
Expected: `IOS TEMPLATE OK`.

---

### Task 25: Validazione complessiva (DoD)

- [ ] **Step 1: Tutti i JSON validi**

Run:
```bash
for j in staging/user/settings.json staging/plugin/.claude-plugin/plugin.json staging/plugin/hooks/hooks.json staging/plugin/.mcp.json staging/project-templates/app-fastapi-react/.mcp.json; do python3 -m json.tool "$j" >/dev/null && echo "OK $j" || echo "FAIL $j"; done
```
Expected: 5 righe `OK`.

- [ ] **Step 2: 8 agenti validi**

Run:
```bash
V="$HOME/.claude/plugins/cache/claude-plugins-official/plugin-dev/unknown/skills/agent-development/scripts/validate-agent.sh"
n=0; for f in staging/plugin/agents/*.md; do bash "$V" "$f" >/tmp/v 2>&1||true; grep -q "Validation failed" /tmp/v && echo "FAIL $f" || n=$((n+1)); done; echo "agents OK: $n/8"
```
Expected: `agents OK: 8/8`.

- [ ] **Step 3: 7 skill con frontmatter valido**

Run:
```bash
for s in staging/plugin/skills/*/SKILL.md; do python3 -c "import sys;t=open('$s').read();fm=t.split('---')[1];assert 'name:' in fm and 'description:' in fm and 'argument-hint' not in fm and 'paths:' not in fm" && echo "OK $s" || echo "FAIL $s"; done
```
Expected: 7 righe `OK`.

- [ ] **Step 4: script bash + CLAUDE.md lean**

Run:
```bash
bash -n staging/plugin/scripts/protect-files.sh && bash -n staging/plugin/scripts/auto-format.sh && echo "SCRIPTS OK"
L=$(wc -l < staging/user/CLAUDE.md); echo "CLAUDE.md righe: $L"; test "$L" -le 55 && echo "LEAN OK"
grep -nE 'pathlib|f-string|React|SwiftUI|pytest|Black' staging/user/CLAUDE.md || echo "STACK-NEUTRAL OK"
```
Expected: `SCRIPTS OK`, `LEAN OK`, `STACK-NEUTRAL OK`.

- [ ] **Step 5: Inventario finale**

Run:
```bash
echo "rules: $(ls staging/user/rules/*.md | wc -l | tr -d ' ')/6"
echo "agents: $(ls staging/plugin/agents/*.md | wc -l | tr -d ' ')/8"
echo "skills: $(ls -d staging/plugin/skills/*/ | wc -l | tr -d ' ')/7"
echo "templates: $(ls -d staging/project-templates/*/ | wc -l | tr -d ' ')/3"
test -f docs/RUNBOOK.md && echo "RUNBOOK present"
```
Expected: `rules 6/6`, `agents 8/8`, `skills 7/7`, `templates 3/3`, `RUNBOOK present`.

- [ ] **Step 6: Report finale per l'utente** — riepilogo + reminder che il deploy è il RUNBOOK Parte 1 (HITL, con backup). Nessuna operazione git, nulla scritto in `~/.claude/`.

---

## Self-Review (eseguita in scrittura piano)

**1. Spec coverage:** A→Task1; B→Task2; C→Task3-8; D→Task11-13; E→Task9; F→Task15-21; G→Task14; J→Task22-24; plugin.json→Task10; L(RUNBOOK)→già scritto; M→Task25. Tutti i sottosistemi coperti. OK.

**2. Placeholder scan:** nessun TBD/TODO; contenuto integrale per ogni file; `[NOME_PROGETTO]` nei template è placeholder *intenzionale* di scaffold (lo compila chi crea il progetto), non incompletezza del piano. OK.

**3. Type/consistency:** path validator identico ovunque; nomi skill = nomi cartella; `disable-model-invocation` solo su interview-driver/fastapi-react-vibe/project-bootstrap (coerente con spec sez.10); settings.json costruito da live+delta (coerente con spec sez.6); `${GITHUB_TOKEN}` mai inline (coerente con sez.11/15). OK.

**4. Adattamenti dichiarati:** no git; validazione al posto di TDD/commit; DoD = validator/JSON/bash -n; warning cosmetici accettati. OK.
```

---

## Emendamento post-esecuzione 2026-05-18 — Stop hook scartato

Dopo il deploy, lo Stop hook `type: prompt` (Task 2 Step 2 e Task 13) è stato
**rimosso**: falsi positivi sistematici sulle pause volute → loop fino
all'override runtime. Niente Stop hook prompt-based. Aggiornati:
`staging/user/settings.json` (no `hooks.Stop`), `staging/plugin/hooks/hooks.json`
(solo PreToolUse+PostToolUse), e `~/.claude/settings.json` live (Opzione A).
I task non vengono riscritti (storico d'esecuzione preservato); vale questo
emendamento.
