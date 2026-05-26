# RUNBOOK — Vibe Coding System

Due parti:
1. **Installazione step-by-step** del sistema (deploy `staging/` → `~/.claude/`).
2. **Workflow operativo concept→code** per ogni nuovo progetto.

> ⚠️ Prerequisito: l'albero `staging/` deve essere già stato generato dal piano
> di implementazione (`docs/superpowers/plans/2026-05-18-vibe-coding-system.md`).
> Finché `staging/` non esiste, questa è la procedura di riferimento, non eseguibile.
> Ogni step di scrittura in `~/.claude/` è **HITL**: si esegue solo con tua conferma
> esplicita, sempre dopo backup.

---

## PARTE 1 — Installazione

### Step 0 — Prerequisiti

```bash
claude --version          # atteso v2.1.59+ (auto memory, hooks prompt-based)
command -v jq             # richiesto dagli hook script
command -v ruff black mypy 2>/dev/null   # formatter Python (opzionali, hook graceful)
command -v swift-format 2>/dev/null       # opzionale (hook Swift)
cd /Users/stefanoferri/Developer/vibe-coding-system
ls staging/               # deve mostrare: user/  plugin/  project-templates/
```

### Step 1 — Backup completo di `~/.claude/` (obbligatorio)

```bash
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.claude/_backup-$TS
cp -p ~/.claude/CLAUDE.md      ~/.claude/_backup-$TS/ 2>/dev/null || true
cp -p ~/.claude/settings.json  ~/.claude/_backup-$TS/ 2>/dev/null || true
cp -Rp ~/.claude/rules         ~/.claude/_backup-$TS/ 2>/dev/null || true
cp -Rp ~/.claude/agents        ~/.claude/_backup-$TS/ 2>/dev/null || true
cp -Rp ~/.claude/skills        ~/.claude/_backup-$TS/ 2>/dev/null || true
cp -Rp ~/.claude/hooks         ~/.claude/_backup-$TS/ 2>/dev/null || true
echo "Backup in ~/.claude/_backup-$TS"
ls -la ~/.claude/_backup-$TS
```

### Step 2 — Zona 1: CLAUDE.md globale

```bash
# Confronto col file attuale PRIMA di sovrascrivere
diff -u ~/.claude/CLAUDE.md staging/user/CLAUDE.md | less
```
**HITL:** rivedi il diff. Su tuo OK:
```bash
cp staging/user/CLAUDE.md ~/.claude/CLAUDE.md
```

### Step 3 — Zona 1: settings.json (con diff obbligatorio)

```bash
# Validità JSON dello staged
python3 -m json.tool staging/user/settings.json >/dev/null && echo "JSON OK"
# Diff vs live (qui vedi: rimozione bypassPermissions/Bash(*), auto+allowlist, attribution, hooks)
diff -u ~/.claude/settings.json staging/user/settings.json | less
```
**HITL:** approva il diff (è il cambio di postura permessi auto+allowlist). Su OK:
```bash
cp staging/user/settings.json ~/.claude/settings.json
python3 -m json.tool ~/.claude/settings.json >/dev/null && echo "settings live OK"
```

### Step 4 — Zona 1: rules path-scoped

```bash
mkdir -p ~/.claude/rules
cp staging/user/rules/*.md ~/.claude/rules/
ls ~/.claude/rules/        # atteso: python swift typescript-react web-vanilla sql-migrations shell
```

### Step 5 — Zona 2: hook script

```bash
mkdir -p ~/.claude/hooks
cp staging/plugin/scripts/protect-files.sh ~/.claude/hooks/
cp staging/plugin/scripts/auto-format.sh   ~/.claude/hooks/
chmod +x ~/.claude/hooks/protect-files.sh ~/.claude/hooks/auto-format.sh
bash -n ~/.claude/hooks/protect-files.sh && bash -n ~/.claude/hooks/auto-format.sh && echo "script syntax OK"
```
(La registrazione degli hook è già dentro il `settings.json` deployato allo Step 3.)

### Step 6 — Zona 2: agenti

```bash
mkdir -p ~/.claude/agents
cp staging/plugin/agents/*.md ~/.claude/agents/
# Ri-validazione
V="$HOME/.claude/plugins/cache/claude-plugins-official/plugin-dev/unknown/skills/agent-development/scripts/validate-agent.sh"
for f in ~/.claude/agents/*.md; do bash "$V" "$f" >/tmp/v 2>&1; grep -q "Validation failed" /tmp/v && echo "FAIL $f" || echo "OK $f"; done
```

### Step 7 — Zona 2: skill

```bash
mkdir -p ~/.claude/skills
cp -R staging/plugin/skills/* ~/.claude/skills/
ls ~/.claude/skills/   # 7 cartelle, ognuna con SKILL.md
```

### Step 8 — Verifica caricamento in sessione

In una nuova sessione `claude` nella cartella di un progetto qualunque:
```
/memory      # conferma che ~/.claude/CLAUDE.md e le rules sono caricati
/agents      # conferma i 7+1 agenti custom (architect, coder, ...)
/skills      # conferma le 7 skill custom
/hooks       # conferma PreToolUse/PostToolUse/Stop registrati
/status      # conferma settings source = User
```

### Step 9 — MCP (setup separato; richiede token)

```bash
# 1) Token GitHub: NON inline. Esporta in ~/.zshrc (riga da aggiungere a mano):
#    export GITHUB_TOKEN="ghp_..."
# 2) Registra i server globali (scope user):
claude mcp add --transport stdio --scope user sequential-thinking \
  -- npx -y @modelcontextprotocol/server-sequential-thinking
claude mcp add --transport http --scope user github \
  https://api.githubcopilot.com/mcp/ \
  --header "Authorization: Bearer $GITHUB_TOKEN"
claude mcp list      # verifica
```
`sqlite` NON è globale: lo porta il template di progetto (`.mcp.json` Zona 3).

### Step 10 — Rollback (se qualcosa va storto)

```bash
TS=<timestamp-del-backup>
cp -p  ~/.claude/_backup-$TS/CLAUDE.md     ~/.claude/CLAUDE.md
cp -p  ~/.claude/_backup-$TS/settings.json ~/.claude/settings.json
rm -rf ~/.claude/rules ~/.claude/agents ~/.claude/skills ~/.claude/hooks
cp -Rp ~/.claude/_backup-$TS/rules   ~/.claude/ 2>/dev/null || true
cp -Rp ~/.claude/_backup-$TS/agents  ~/.claude/ 2>/dev/null || true
cp -Rp ~/.claude/_backup-$TS/skills  ~/.claude/ 2>/dev/null || true
cp -Rp ~/.claude/_backup-$TS/hooks   ~/.claude/ 2>/dev/null || true
```

### (Futuro) Step 11 — Pacchettizzazione plugin (post field-test)

Quando le skill/agenti sono validati sul campo:
```bash
claude --plugin-dir staging/plugin     # test locale come plugin
# poi: pubblicazione su repo privato + /plugin install
```

---

## PARTE 2 — Workflow operativo concept→code (per ogni nuovo progetto)

> FASE 1 e FASE 2 in **sessioni separate** (mai mischiare interview e coding).

### FASE 1 — Concept → Spec → Struttura
1. `mkdir ~/dev/<nome> && cd ~/dev/<nome> && claude`
2. `/project-bootstrap <descrizione breve>` — oppure manuale:
   - `/interview-driver <descrizione>` → risposte → `SPEC.md`
   - genera `ARCH.md` (+ ADR-001..N) con l'agente `architect`
   - `/claude-md-generator` → CLAUDE.md di progetto (sceglie tra i 3 template Zona 3)
3. HITL gate dopo ogni step. `git init` + commit iniziale.

### FASE 2 — Implementazione (sessione fresh)
4. `/clear` o nuova sessione. Plan mode per lo scaffold → HITL → esegui → commit.
5. Per ogni feature:
   - `@"architect (agent)"` → ADR → **HITL**
   - in parallelo (max 4): `@"coder (agent)"` (backend/frontend), `@"tester (agent)"`, `@"doc-writer (agent)"`
   - `@"reviewer (agent)"` → **HITL** commit
   - commit Conventional Commits → PR
   - `/clear` tra feature non correlate

### Setup per-progetto (da template Zona 3)
```bash
cp -R <repo-vibe>/staging/project-templates/app-fastapi-react/. ~/dev/<nome>/
# oppure web-vanilla-wordpress/ o ios-swiftui/
# personalizza: nome, stack reale, comandi; aggiungi CLAUDE.local.md a .gitignore
```

---

## Note di sicurezza

- Nessuno step scrive in `~/.claude/` senza tua conferma esplicita; backup sempre prima (Step 1).
- Secret (`GITHUB_TOKEN`) mai inline: solo env var.
- Gli hook `protect-files.sh` (deny) hanno precedenza su qualunque permission mode: difesa a strati anche con auto mode.
- Il live `~/.claude/settings.json` cambia solo allo Step 3, previo diff approvato.

## Emendamento 2026-05-18 — Stop hook scartato

Lo Stop hook `type: prompt` è stato rimosso (live + staging): falsi positivi
sulle pause volute → loop. Restano solo PreToolUse (protect-files) e PostToolUse
(auto-format). Se in futuro vuoi un Stop hook, scrivilo con loop-guard su
`stop_hook_active` (vedi Anthropic hooks-guide); ma per un flusso interattivo
con pause frequenti è sconsigliato.
