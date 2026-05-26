# Spec — Miglioramento e creazione degli 8 agenti del Vibe Coding System

**Data:** 2026-05-17
**Origine:** brainstorming su `docs/vibe-coding-system.md` (sez. 3.1–3.8)
**Stato progetto:** locale, NON versionato in git (istruzione utente)

---

## 1. Obiettivo

Migliorare e creare gli 8 sub-agent custom descritti nel documento blueprint,
applicando l'**Approccio A**: riscrittura per-agente, file lean, frontmatter
schema-valido. Roster e intento dei ruoli **invariati**; si interviene su
correttezza, qualità dei prompt, trigger accuracy, tool scoping, guardrail e
allineamento al `~/.claude/CLAUDE.md` reale dell'utente.

## 2. Decisioni di brainstorming (fissate)

| Asse | Decisione |
|---|---|
| Obiettivo | Correttezza + qualità prompt (roster invariato) |
| Destinazione file | Staging in questo repo (`agents/`); l'utente copierà in `~/.claude/agents/` |
| Riferimenti a skill/MCP inesistenti | Condizionali e graceful ("se disponibile X, altrimenti procedi") |
| Versionamento | Nessuna operazione git (progetto locale) |

## 3. Fatti verificati — schema frontmatter agente

Fonte: skill ufficiale `plugin-dev/agent-development` (SKILL.md).

**Campi validi (e solo questi):**

- `name` (obbligatorio): lowercase + cifre + trattini, 3–50 char, inizia/finisce alfanumerico.
- `description` (obbligatorio): condizioni di trigger + sintesi in prosa degli scenari
  + rimando a sezione "When to invoke" nel corpo. 10–5000 char (ottimale 200–1000).
- `model` (obbligatorio): `inherit` | `sonnet` | `opus` | `haiku`.
- `color` (obbligatorio): `blue` | `cyan` | `green` | `yellow` | `magenta` | `red`.
- `tools` (opzionale): lista di nomi-tool. **Convenzione reale Claude Code**
  (verificata su agenti ufficiali): stringa separata da virgole — `tools: Read, Grep, Bash`
  (non array YAML). Se omesso → tutti i tool. Least privilege raccomandato.
  Nelle sez. 7.x i tool-set sono indicati come array per leggibilità ma nei file
  vanno resi come stringa csv.

**Campi del documento NON esistenti nello schema** → rimossi dal frontmatter,
intento migrato altrove:

| Campo doc | Migrazione |
|---|---|
| `effort: high/medium/low` | Istruzione esplicita di profondità di ragionamento nel system prompt |
| `permissionMode: plan` | Guardrail forte nel prompt ("mai codice produttivo") + tool scoping |
| `memory: project` | Convenzione file `docs/agent-notes/<name>.md` (read/append), **relativo al progetto in cui l'agente gira** (non a questo repo di staging) |
| `isolation: worktree` | Nota nel prompt: l'isolamento worktree è gestito dall'orchestrator |

**Errore di sintassi del documento corretto trasversalmente:** la forma
`tools: Read, Bash(git *), Bash(rg *)` è sintassi `permissions` di settings.json,
**invalida** nel frontmatter agente. Tutti gli 8 agenti useranno array di nomi-tool;
lo scoping fine di Bash (es. solo `git diff`/`git log`) viene spostato nel system
prompt come vincolo comportamentale.

## 4. Struttura di staging

```
vibe-coding-system/
├── agents/                      # NUOVA cartella staging (draft, non auto-attiva)
│   ├── architect.md
│   ├── coder.md
│   ├── reviewer.md
│   ├── tester.md
│   ├── debugger.md
│   ├── doc-writer.md
│   ├── refactorer.md
│   └── researcher.md
├── docs/
│   ├── vibe-coding-system.md
│   └── superpowers/specs/2026-05-17-agents-improvement-design.md
└── CLAUDE.md
```

Cartella `agents/` e non `.claude/agents/`: è staging, non deve attivarsi come
agente di progetto. L'utente copierà gli 8 file in `~/.claude/agents/` quando
approva (con backup degli eventuali preesistenti).

## 5. Frontmatter target — model + color

| Agente | model | color | Razionale colore |
|---|---|---|---|
| architect | opus | magenta | generazione/design |
| coder | sonnet | green | task produttivo |
| reviewer | sonnet | blue | analisi/review |
| tester | sonnet | yellow | validazione |
| debugger | sonnet | red | critico |
| doc-writer | haiku | cyan | analisi/scrittura |
| refactorer | sonnet | yellow | cautela (behavior-preserving) |
| researcher | haiku | blue | analisi |

`model` resta esplicito (non `inherit`): il modello di costo della sez. 3.9 del
blueprint è una scelta deliberata.

## 6. Allineamenti trasversali al `~/.claude/CLAUDE.md` reale

Applicati ovunque pertinente, **senza ripeterli nei file** (principio lean —
sono ereditati dal CLAUDE.md globale):

- Italiano in chat / inglese in codice, commit, docstring API.
- `pip` + `requirements.txt` e `npm` (NON `uv`/`pnpm` come nei rule di esempio del doc).
- **Swift Testing (Swift 6) per nuovi test; XCTest solo legacy** (il doc diceva "XCTest + Swift Testing").
- Confidence dichiarata in chat, mai nei deliverable; distinguere fatti da assunzioni.
- Mai azioni distruttive senza conferma; backup prima di modificare file critici; modifiche minime.
- Conventional Commits in inglese; mai commit diretto su main.

## 7. Modifiche per agente

Struttura comune a tutti i system prompt: seconda persona, sezioni standard
(Core Responsibilities → Process → Quality Standards → Output Format → Edge Cases),
sezione "When to invoke" con 2–4 scenari in prosa, < 10.000 caratteri,
nessuna duplicazione delle regole globali.

### 7.1 architect — opus, magenta
- `tools: ["Read","Grep","Glob","Bash","WebSearch","WebFetch","Write"]`.
- `Write` consentito **solo** per ADR/planning docs in `docs/architecture/**`,
  mai codice produttivo (guardrail forte; sostituisce `permissionMode: plan`).
- `memory:project` → `docs/agent-notes/architect.md`.
- `effort:high` → istruzione "ragiona in profondità, valuta ≥2 alternative".
- Graceful: usa `sequential-thinking` MCP se disponibile per design complessi.
- `description` riscritta + "When to invoke" (inizio feature/refactor non triviale,
  decisione architetturale, decomposizione task complesso).

### 7.2 coder — sonnet, green
- `tools: ["Read","Edit","Write","Glob","Grep","Bash"]`.
- `isolation:worktree` → nota: isolamento gestito dall'orchestrator; non assumere worktree.
- Niente hardcode package manager: "segui CLAUDE.md/rules di progetto; default utente pip/npm".
- Conventional Commits in inglese **ma mai commit** (resta all'orchestrator).
- Standard di qualità espliciti: no over-engineering, leggi 2–3 file simili prima,
  verifica con test/lint/build prima di dichiarare "fatto".

### 7.3 reviewer — sonnet, blue
- `tools: ["Read","Grep","Glob","Bash"]`; Bash ristretto via prompt a `git diff`/`git log` (read-only).
- `memory:project` → `docs/agent-notes/reviewer.md` (pattern ricorrenti, anti-pattern).
- Graceful ref a skill `code-review-checklist`.
- Output per severità BLOCKER/MAJOR/MINOR/NIT con `file:line` in sez. "Output Format".

### 7.4 tester — sonnet, yellow
- `tools: ["Read","Edit","Write","Glob","Grep","Bash"]`.
- Conflitto risolto: "Swift: Swift Testing (Swift 6) per nuovi test; XCTest solo legacy".
  Python: pytest (+pytest-asyncio). TS: Vitest + testing-library.
- Guardrail: mai modificare codice produttivo; bug trovato → riporta a debugger/coder.
- Run-single-test-first; lint+typecheck+test prima di "done".

### 7.5 debugger — sonnet, red
- `tools: ["Read","Edit","Bash","Grep","Glob"]`.
- `memory:project` → `docs/agent-notes/debugger.md` (pattern di bug e risoluzioni).
- Workflow root-cause: cattura errore → ipotesi → probe minime → fix minimo →
  verifica → niente soppressione sintomi; "se non verificabile, segnalalo".

### 7.6 doc-writer — haiku, cyan
- `tools: ["Read","Edit","Write","Glob","Grep"]`.
- Regole lingua non ripetute (ereditate); richiamo sintetico solo dove l'agente
  devia (README/ADR italiano, docstring API inglese — coerente col globale).
- Graceful ref a skill `human-writing-style` per long-form italiano.

### 7.7 refactorer — sonnet, yellow
- `tools: ["Read","Edit","Glob","Grep","Bash"]`.
- `memory:project` → `docs/agent-notes/refactorer.md`.
- Iron rules rafforzate: test verdi prima/dopo; max ~200 righe/pass con checkpoint;
  ogni commit behavior-preserving; se non puoi provare l'invarianza, fermati e segnala.

### 7.8 researcher — haiku, blue
- `tools: ["Read","Grep","Glob","WebSearch","WebFetch"]`.
- `effort:low` rimosso.
- Graceful ref a `context7` MCP (preferiscilo per docs librerie se disponibile).
- Disciplina citazioni: ogni claim con URL; distingui fatti/opinioni/ipotesi;
  "non verificato" se non confermabile.

## 8. Validazione (definition of done per file)

1. Frontmatter: solo i 5 campi validi; `name` regex-conforme; `description`
   200–1000 char con "When to invoke" nel corpo; `model` valido; `color` valido;
   `tools` array di nomi.
2. System prompt: seconda persona, struttura standard, < 10.000 char, ≥ 2 edge case.
3. Validazione automatica con `scripts/validate-agent.sh` del plugin `plugin-dev`.
   **Definition of Done = exit 0 (zero ERRORI).** Lo script dà solo *warning*
   (exit 0, "passed with warnings") per `<example>` mancanti o description su
   più righe: il suo parser è naive (grep su `^description:`) — i warning sono
   cosmetici e li danno anche gli agenti ufficiali Anthropic, quindi accettati.
   Errori bloccanti solo su: frontmatter assente/non chiuso, campi obbligatori
   mancanti, `name` malformato, system prompt vuoto/<20 char.
4. Nessuna regola in conflitto col `~/.claude/CLAUDE.md` reale; nessuna duplicazione di esso.
5. Confidence dichiarata in chat a fine lavoro (non nei file).

## 9. Criteri di successo

- 8 file in `agents/` che passano la validazione schema.
- Roster e intento invariati rispetto al doc.
- Ogni scostamento dal doc tracciato in tabella "Modifiche vs documento" nel
  piano di implementazione, **non** nei file agente (deliverable puliti).
- File copiabili 1:1 in `~/.claude/agents/` senza ulteriori edit.

## 10. Fuori scope

- Skill custom (sez. 8.3), file `rules/` (sez. 5), hook (sez. 7), setup MCP
  (sez. 9), agent-teams (sez. 11.6): NON inclusi. Solo gli 8 file agente.
- Built-in Anthropic (Explore/Plan/general-purpose): non toccati.
- Nessuna operazione git.

## 11. Deliverable

- `agents/{architect,coder,reviewer,tester,debugger,doc-writer,refactorer,researcher}.md`
- Questo spec: `docs/superpowers/specs/2026-05-17-agents-improvement-design.md`
