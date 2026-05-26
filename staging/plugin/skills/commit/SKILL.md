---
name: commit
description: Use this skill for ANY git commit request — including "commit", "committa", "commit and push", "commit e crea PR", "committa e crea PR". Generates a Conventional Commits message with explicit HITL approval gate before executing. Optionally pushes and creates a PR after commit. Reads context (diff, CLAUDE.md, ADR/manifest). NEVER commits before the explicit user click. Supersedes commit-commands:commit and commit-commands:commit-push-pr.
---

# `commit` — Commit Wizard Skill

Chiude il ciclo di implementazione con un commit Conventional Commits verificato via HITL.
**MAI eseguire `git commit` prima del click esplicito "Approvo".**

## Lingua

Comunicazione verso l'utente in italiano. Commit message in inglese (Conventional Commits).

## When to invoke

- Dopo implementazione + review: codice pronto, manca solo il commit.
- Come Step 7 nel chain `concept-to-code` (dopo Gate 5 / review cycle).
- Standalone su qualsiasi branch con modifiche da committare.

**Do NOT invoke if:**
- Non c'è repo git (`git rev-parse --git-dir` fallisce).
- `git status --short` è vuoto (nulla da committare).

## Arguments

```
/commit [context-hint]
```

`context-hint` opzionale: breve descrizione della feature per il commit body.
Dal chain concept-to-code: `<topic-full-title> (ADR: <adr-path>)`.

---

## Process

### Step 1 — Verifica repo e stato

```bash
git rev-parse --git-dir
```

Se fallisce: report "Non sono in un repo git" e termina.

```bash
git status --short
git diff --stat HEAD
```

- Output vuoto → report "Niente da committare" e termina.
- Solo unstaged (niente staged): nel gate (Step 4) mostra tutti i file modificati come "verranno inclusi
  tramite `git add .`"; l'utente può abortire per stagiarli selettivamente.
- Staged + unstaged: includi solo i file staged nel commit; menziona gli unstaged come "non inclusi".

### Step 2 — Leggi contesto

In ordine di priorità:
1. `git diff --staged` (o `git diff HEAD` se niente staged) — cosa cambia
2. `CLAUDE.md` project root — stack, pattern, convenzioni
3. Manifest più recente in `docs/manifests/` se esiste — topic, ADR path
4. ADR più recente in `docs/architecture/` se esiste — decisioni del ciclo
5. `context-hint` passato come argomento

### Step 3 — Genera commit message

Formato Conventional Commits (inglese):
```
<type>(<scope>): <subject>

<body>
```

- **type**: `feat` | `fix` | `refactor` | `test` | `docs` | `chore` | `perf`
- **scope**: modulo/componente principale toccato (opzionale ma raccomandato)
- **subject**: imperativo, minuscolo, no punto finale, subject + type + scope ≤ 72 chars
- **body**: solo se aggiunge "perché" non ovvio dal diff (max 5 righe)
- **MAI** trailer `Co-Authored-By: Claude` o simili (`settings.json attribution` già disabilitato)
- **MAI** `BREAKING CHANGE` non verificato esplicitamente dal diff

### Step 4 — HITL gate (AskUserQuestion, BLOCKING)

Usa `AskUserQuestion`:

```
question: "Commit — Revisione messaggio\n\n
  Messaggio proposto:\n\n```\n<commit-message>\n```\n\n
  File inclusi (<N>):\n<file-list max 10 righe, poi '... e altri N'>\n\n
  Approvi?"
header: "Commit · Gate"
options:
  - label: "Approvo"
    description: "Esegue git commit con questo messaggio"
  - label: "Modifica messaggio"
    description: "Seleziona Other e digita il messaggio corretto"
  - label: "Abort"
    description: "Non committare nulla — termina senza modifiche"
```

**MAI eseguire `git commit` prima del click "Approvo".**
**MAI auto-rispondere o auto-completare l'AskUserQuestion.**

### Step 5 — Esegui commit (SOLO dopo click "Approvo")

```bash
# Se ci sono file unstaged da includere:
git add .
# Commit con messaggio approvato:
git commit -m "$(cat <<'COMMITMSG'
<commit-message>
COMMITMSG
)"
```

Verifica exit code:
- 0 → report successo: hash + subject (`git log -1 --oneline`)
- non-0 → report errore, non ritentare automaticamente

Dopo "Modifica messaggio" con testo fornito dall'utente via Other:
1. Aggiorna il messaggio con quello fornito.
2. Ri-mostra Gate commit con il nuovo messaggio (stessa struttura `AskUserQuestion`).
3. Solo dopo il secondo "Approvo" esegui `git commit`.

Dopo "Abort": termina senza fare nulla.

### Step 6 — PR (opzionale, solo dopo commit riuscito)

Usa `AskUserQuestion`:

```
question: "Vuoi creare una Pull Request?\n\nBranch: <current-branch> → <default-branch>"
header: "PR · Opzionale"
options:
  - label: "Sì — push + crea PR"
    description: "git push origin <branch>, poi PR via GitHub MCP"
  - label: "No — solo commit locale"
    description: "Fine"
```

Se "Sì":
1. `git push -u origin <branch>` (push solo dopo click esplicito)
2. `mcp__github__create_pull_request` con:
   - `title`: subject del commit message
   - `body`: body del commit message + riferimento ADR se presente nel contesto

## Guardrail invariabili

- **MAI `git commit` prima del click esplicito su Gate commit.**
- **MAI `git push --force`** in nessun caso.
- **MAI `git commit --no-verify`** — non bypassare hook.
- **MAI creare commit vuoti** — controlla `git status` prima.
- **MAI committare `.env`, secret, API key** — se `git status` mostra file sospetti (`.env`,
  `*secret*`, `*credential*`, `*.pem`), fermati e avvisa l'utente prima di procedere.
