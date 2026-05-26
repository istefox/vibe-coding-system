# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Cos'è questo repository

Non è un progetto di codice: è il **repository del blueprint** del "Vibe Coding System per
Stefano Ferri — Architettura Multi-Agente v2.1". Contiene un unico artefatto autorevole:

- `docs/vibe-coding-system.md` (~1770 righe) — specifica completa del setup Claude Code
  multi-agente: sub-agent, agent-teams, path-scoped rules, hook, MCP, permission modes,
  workflow concept→code. È la **single source of truth**: ogni decisione va riconciliata
  con questo documento.

Il file supera i 25k token: leggilo con `Read` usando `offset`/`limit` per sezioni, non
in blocco. Le sezioni sono numerate (1–17) e si referenziano a vicenda nel testo.

## Eredita le regole globali

Questo progetto eredita `~/.claude/CLAUDE.md` (Stefano Ferri), già caricato in ogni
sessione. **Non duplicare qui** le convenzioni generali (Python/Swift/web style, git
workflow, terminologia Vibrofer, safety): valgono già. Questo file specializza solo
per questo repo.

## Regole comportamentali invariabili

Dalla sez. 4 del documento, coerenti con le convenzioni globali — applicano qui e a
qualunque sistema generato da questo blueprint:

- Plan mode obbligatorio per qualunque task che modifica >1 file o tocca migrazioni/config produzione
- Conventional Commits in inglese (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`)
- Mai `git push --force` senza approvazione esplicita di Stefano
- Mai modificare migration già applicate in produzione
- Mai disabilitare un test per farlo passare: se va cambiato, spiegare perché in chat prima
- Confidence dichiarata in chat a fine task, **mai** nei file deliverable
- HITL gate sempre prima di: commit, push, deploy, modifica schema DB, eliminazioni permanenti
- Lingua: italiano in chat e nei doc; inglese per codice, commit, docstring API
- Tono: diretto, conciso, tecnico — niente filler

## Architettura descritta nel documento (big picture)

Serve per orientarsi senza rileggere tutte le 1770 righe. Dettagli e razionali nelle
sezioni indicate.

- **Topologia (sez. 2):** Orchestrator (sessione principale CLI) → fino a 4 sub-agent
  paralleli *dentro* la sessione (task isolati, ritornano summary) **oppure** 3–5
  teammate di un agent-team in *sessioni separate* (lavoro cross-strato, experimental,
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). Sub-agent NON spawnano altri sub-agent.
- **8 sub-agent custom (sez. 3)** in `~/.claude/agents/`: `architect` (Opus, plan,
  solo ADR), `coder` (Sonnet, `isolation: worktree`), `reviewer`/`tester`/`debugger`/
  `refactorer` (Sonnet), `doc-writer`/`researcher` (Haiku). Modello scelto per
  bilanciare costo/capacità (sez. 3.9).
- **Extension stack a livelli:** `~/.claude/CLAUDE.md` globale (solo identità+comportamento,
  <200 righe) → path-scoped rules in `.claude/rules/` con frontmatter `paths:` (sez. 5)
  → sub-agent in `.claude/agents/` → skill in `.claude/skills/` (sez. 8) → hook in
  `settings.json` (sez. 7, automazione deterministica) → MCP in `.mcp.json` (sez. 9).
  Il pattern rules sostituisce gran parte del CLAUDE.md monolitico.
- **Permission strategy (sez. 10):** `acceptEdits` default, plan mode esplicito per
  feature nuove, allowlist per comandi ricorrenti; gli hook deny vincono su qualunque
  permission mode (difesa a strati).
- **Workflow concept→code (sez. 11):** interview mode (`AskUserQuestion`) → `SPEC.md`
  → `ARCH.md` (+ ADR) → CLAUDE.md di progetto → **fresh session** → scaffold in plan
  mode → implementazione multi-agente parallela (worktree) → review → commit + PR.
  Mai mischiare interview e coding nella stessa sessione.
- **Convenzione identità (sez. 4, parte del design proposto):** assistente "Adriano",
  utente "Stefano" — annotata qui come elemento del blueprint; l'identità effettiva
  resta governata da `~/.claude/CLAUDE.md`.

## Lavorare con il documento

- Quando aggiorni `docs/vibe-coding-system.md`: mantieni coerenti la numerazione delle
  sezioni, i blocchi "Cambiamenti rispetto a…" (changelog di versione in testa) e la
  "Confidence finale" + "Cose verificate vs assunte" in coda.
- Preserva la distinzione esplicita **verificato vs assunto**: il documento cita
  `code.claude.com/docs` come fonti primarie verificate. Non promuovere un'assunzione a
  fatto senza verifica e relativa citazione.
- Le checklist (sez. 15) e i template (sez. 4, 6) sono destinati a essere copiati in
  altri repo: tienili autoconsistenti e validi standalone.

## Comandi

Repository di sola documentazione: **nessun comando** di build, lint, test o run.
Solo Markdown. Git non è inizializzato in questo repo. Gli artefatti del sistema
descritto (agents, skills, hook, rules) vivono in `~/.claude/` e nei `.claude/` dei
progetti target — non qui.

## Decisioni dal chain clean-public-repo (ADR-0011)

Modalità anonimizzazione per repo pubblici: Gate 0b nel chain (auto-detect remote
pubblico → flag `anonymize`) + skill `clean-public-repo` (audit/rimedio, fresh-history
publish di default, rewrite chirurgico opt-in con backup+dry-run+HITL). Scopo:
qualità + nessuna auto-attribuzione dello strumento; **mai** falsificare autori.
Dettaglio: `docs/architecture/ADR-0011-clean-public-repo-anonymize.md`.
