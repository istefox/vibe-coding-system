# ADR-0012 — Memoria cross-session degli agenti mediata dall'orchestratore (rimozione di `docs/agent-notes/` dal tree di progetto)

**Status:** Accepted — 2026-05-24 (5 punti confermati da Stefano: label `DURABLE NOTES:`, path `memory/agent-notes/<agente>.md` separato da `MEMORY.md`, harvest manuale fuori dal chain, presidio read-only in vibe-status, clausola di rivalutazione). **Resta il meccanismo ATTIVO.**
_(2026-05-25: ADR-0013 aveva tentato di rimpiazzarlo con la feature nativa `memory: local`, ma il **pilota è fallito** — l'agente con `memory:` ha scritto fuori dalla sua sandbox, nell'auto-memory curata; la mediazione di ADR-0012, in cui i sub-agent non hanno Write su memoria, previene quel rischio. Migrazione respinta, vedi ADR-0013 "Rejected after pilot".)_

**Deciders:** architect (dispatch orchestrator), Stefano Ferri (approvazione finale)

**Related:** ADR-0003 (`concept-to-code` skill orchestratore del chain — è il punto in cui
si innesta il contratto iniezione/raccolta delle agent-notes), ADR-0001 (Coder pre-flight
pattern classifier — precedente del pattern "contratto strutturato nel report del subagent",
qui riusato per `DURABLE NOTES:`), ADR-0004 (Pre-flight Pattern Enforce Hook — fonte della
fragilità dell'encoding project-dir che questa decisione evita lato subagent), ADR-0005
(Vibe-status skill — candidato presidio read-only del round-trip della memoria agente).

---

## Context

### Il meccanismo oggi: due sistemi di memoria paralleli

Il sistema ha **due** meccanismi di memoria cross-session, indipendenti e ridondanti:

1. **Auto-memory centrale dell'orchestratore.** Uno store per-progetto sotto
   `~/.claude/projects/<encoded-project-dir>/memory/`, con un indice curato `MEMORY.md`
   (sezioni Project/Feedback/Reference, link a file per-topic) e file per-topic con
   frontmatter YAML (`node_type: memory`, `type`, `originSessionId`). È gestito
   esclusivamente dall'**orchestratore** (la sessione principale CLI), che ha accesso al
   path encoded della harness. Vive **fuori** dal tree di qualunque progetto target.

2. **Agent-notes per-progetto.** Tre sub-agent attivi hanno un meccanismo separato:
   leggono e **appendono** pattern/decisioni durevoli a `docs/agent-notes/<agente>.md`
   *dentro il tree del progetto su cui lavorano*. Punti esatti verificati nelle
   definizioni live:
   - `~/.claude/agents/architect.md`: Process punto 5 (riga ~33) "Check
     `docs/agent-notes/architect.md` … After designing, append new durable
     decisions/patterns to it (create the file/dir if absent)"; Edge Cases "Write
     scope" (riga ~64) include `docs/agent-notes/architect.md`.
   - `~/.claude/agents/debugger.md`: Process punto 2 (riga ~28) "Check
     `docs/agent-notes/debugger.md` … for similar past issues" e punto 6 (riga ~32)
     "Append the bug pattern + resolution to `docs/agent-notes/debugger.md`".
   - `~/.claude/agents/reviewer.md`: Process punto 3 (riga ~29) "Check
     `docs/agent-notes/reviewer.md` … Append newly observed recurring patterns".

   (Esiste anche `~/.claude/agents/refactorer.md.bak-2026-05-20` con lo stesso pattern, ma
   è un `.bak` **inattivo** — citato solo come storico; il `refactorer.md` live non ha più
   il meccanismo.)

### Il conflitto, e perché ricorre

Una regola di doc-discipline — "no session scaffolding nel tracked tree" — vive nel
**CLAUDE.md dei progetti coding target**, NON nella config condivisa `~/.claude/`. È
verificato: un grep di `agent-notes` su `~/.claude/agents` trova solo le 3 definizioni +
il `.bak`; un grep della frase anti-scaffolding ("session scaffold"/"tracked tree") su
`~/.claude/agents` e `~/.claude/skills` **non trova nulla**; la skill `claude-md-generator`
non è consapevole del meccanismo agent-notes (non lo genera né lo eccettua).

Conseguenza: ogni run dell'architect (o debugger/reviewer) **ricrea** un file untracked
`docs/agent-notes/<agente>.md` che **viola** la regola del progetto e va rimosso prima del
PR. Poiché il meccanismo è **by-design** (gli agenti DEVONO appendere a quel path), una
cancellazione una-tantum non risolve: il file **ricorre** a ogni dispatch. Il conflitto è
strutturale, non un incidente.

### Fatti verificati (2026-05-24)

- Le 3 definizioni agente sopra contengono read+append a `docs/agent-notes/<agente>.md`
  (incluso il write-scope esplicito di `architect.md`). `refactorer.md` live: pulito; solo
  il `.bak` storico mantiene il pattern.
- La regola anti-scaffolding NON è nella config condivisa (grep vuoto su agents+skills).
- L'auto-memory store esiste e ha la struttura descritta (indice `MEMORY.md` curato + file
  per-topic con frontmatter), sotto
  `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/`.
- Il chain `concept-to-code` **già inietta direttive condizionali via prompt-template di
  dispatch** (Step 2 architect con brief; Step 5 coder; blocchi `[SE manifest.anonymize=true]`)
  e già passa "a literal prompt template at dispatch time" senza patchare i SKILL.md degli
  agent (SKILL.md righe ~167-271, ~544). È il punto di innesto naturale del contratto
  iniezione/raccolta.
- La fragilità dell'encoding project-dir è documentata (memory
  `feedback_pretooluse-payload-schema.md`): Claude Code converte `_`→`-` (e potenzialmente
  altri caratteri, regola non stabile tra versioni); ri-encodare `cwd` con `tr '/' '-'`
  produce path errati; il modo robusto è derivare la dir da `dirname(transcript_path)`. Un
  subagent che dovesse risolvere da sé il path encoded dello store ricadrebbe in questa
  trappola (è già costata un ADR mal implementato — ADR-0004 v1.0/v1.1).

### Assunzioni esplicite (NON validate)

- Si assume che la **memoria degli agenti abbia valore** sufficiente da non poter essere
  semplicemente rimossa (vedi Alternativa C): il design la **preserva** spostandola, non la
  elimina. Se in pratica gli agenti non producono mai note durevoli utili, l'Alternativa C
  diventerebbe la scelta più semplice.
- Si assume che l'onere ricorrente sull'orchestratore (iniettare prima, raccogliere dopo
  ogni dispatch) sia sostenibile entro il chain, dove il dispatch è già mediato da
  prompt-template. Fuori dal chain (dispatch diretto a un subagent) l'onere ricade sulla
  disciplina dell'orchestratore: rischio di **dimenticare l'harvest** → vedi Consequences e
  il presidio richiesto.

---

## Decision

Adottare l'**Opzione B-mediata**: spostare la memoria cross-session degli agenti **fuori dal
tree di progetto, dentro l'auto-memory centrale**, ma con accesso **mediato
dall'orchestratore** — i sub-agent **non** accedono mai direttamente allo store né risolvono
il path encoded. Il meccanismo `docs/agent-notes/` nel tree viene **rimosso**.

### D1 — Contratto a tre tempi: iniezione → raccolta → persistenza

1. **Iniezione (pre-dispatch).** L'orchestratore — che ha accesso all'auto-memory store —
   legge le agent-notes rilevanti per l'agente che sta per dispatchare e le **inietta nel
   brief del dispatch**, in un blocco delimitato. Forma proposta, da innestare nei template
   esistenti (Step 2 per architect, e analoghi per debugger/reviewer quando dispatchati dal
   chain o direttamente):

   ```
   PRIOR AGENT NOTES (read-only context — past durable decisions/patterns for this agent
   on this project; factor in, do not repeat work already settled):
   <contenuto di agent-notes/<agente>.md dallo store, o "none yet">
   ```

   Se non esistono note, il blocco riporta `none yet` (mai omesso del tutto: la sua presenza
   segnala all'agente che il canale esiste).

2. **Raccolta (post-report).** Il sub-agent **non accede alla memoria**. Restituisce le note
   durevoli in una **sezione strutturata e terminale del suo report**, con un header
   machine-greppable (stesso spirito del contratto `PATTERN:` di ADR-0001, leggibile sia
   dall'orchestratore sia da un eventuale presidio):

   ```
   DURABLE NOTES:
   - [<categoria>] <pattern/decisione durevole, 1-2 righe> (<contesto opzionale: file:line / ADR>)
   - ...
   (oppure la riga letterale "DURABLE NOTES: none" se non ci sono note nuove)
   ```

   Regole del formato: header esatto `DURABLE NOTES:` su riga propria; ogni nota è un bullet;
   `none` esplicito se vuoto (così l'orchestratore distingue "nessuna nota" da "report
   troncato" — coerente con la lezione `feedback_subagent-truncation-transport.md`).

3. **Persistenza (post-dispatch).** L'orchestratore scrive/aggiorna quelle note in una
   **sottocartella dedicata** dello store centrale, **separata dall'indice curato
   `MEMORY.md`** per non inquinarlo:

   ```
   ~/.claude/projects/<encoded-project-dir>/memory/agent-notes/<agente>.md
   ```

   `MEMORY.md` resta l'indice curato a mano dei topic di progetto; `agent-notes/` è il
   namespace append-only delle note operative degli agenti, non linkato dall'indice. La
   risoluzione del path encoded è **sempre e solo** responsabilità dell'orchestratore (che
   già lo gestisce per il resto dell'auto-memory), mai del subagent.

### D2 — I subagent non toccano mai lo store né il path encoded

Vincolo HARD: nessuna delle 3 definizioni agente deve più contenere un path verso lo store
né logica di risoluzione del project-dir encoded. Questo elimina alla radice la fragilità
documentata (`_`→`-`, `dirname(transcript_path)` vs `cwd`): l'unico componente che conosce
il path è l'orchestratore. Il subagent vede solo testo (brief in ingresso, report in uscita).

### D3 — Migrazione delle 3 definizioni agente

Rimuovere da `architect.md`, `debugger.md`, `reviewer.md` (in `~/.claude/agents/`):

- Il passo "Check `docs/agent-notes/<agente>.md` … for past decisions/patterns" →
  sostituito da: "factor in the `PRIOR AGENT NOTES` block if present in your brief".
- Il passo "Append … to `docs/agent-notes/<agente>.md` (create file/dir if absent)" →
  sostituito da: "emit a terminal `DURABLE NOTES:` section in your report (format above);
  do NOT write any file for memory".
- In `architect.md`, rimuovere `docs/agent-notes/architect.md` dal "Write scope" (resta solo
  `docs/architecture/**`).

Il `.bak` storico (`refactorer.md.bak-2026-05-20`) **non** va toccato (è inattivo; toccarlo
sarebbe rumore). `refactorer.md` live è già pulito.

### D4 — Il contratto è esplicito nel chain (e nel protocollo di dispatch in generale)

Il passo iniezione+raccolta diventa un **contratto del chain `concept-to-code`** (ADR-0003):
i template di dispatch Step 2 (architect) — e i punti dove il chain dispatcha debugger/reviewer
(es. il review cycle a Step 6) — aggiungono il blocco `PRIOR AGENT NOTES` in ingresso e, dopo
il report, l'orchestratore esegue l'harvest del blocco `DURABLE NOTES:` verso
`memory/agent-notes/<agente>.md`. Per il dispatch **diretto** (fuori chain), la regola va
documentata nel protocollo di dispatch dell'orchestratore come passo standard. Pattern già in
uso (iniezione via prompt-template, zero patch ai SKILL.md): questo è additivo e coerente.

### D5 — `claude-md-generator` non genera più la regola in conflitto

`claude-md-generator` deve **smettere di poter generare/ereditare** una regola di
doc-discipline che vieti `docs/agent-notes/` nel tracked tree, perché dopo questa migrazione
quel path **non viene più creato** da nessun agente. Verifica concreta in fase di
implementazione: se la skill (o i suoi template/esempi) menziona `agent-notes` o una regola
anti-scaffolding ad essa legata, va rimossa la menzione; la direttiva additiva di Step 3 resta
invariata per il resto. (Nota: il grep attuale non trova `agent-notes` nelle skill — la
regola vive nei CLAUDE.md dei progetti target generati; l'azione è assicurarsi che il
generatore non la **re-introduca**.)

### D6 — Presidio del round-trip (testabilità)

Il rischio centrale è **dimenticare l'harvest** (l'orchestratore non raccoglie `DURABLE
NOTES:` → la memoria si perde silenziosamente). Si raccomanda un **harness deterministico**
del round-trip su fixture, indipendente da una sessione live:

- iniezione: dato uno store fixture con `agent-notes/<agente>.md`, il template di dispatch
  produce il blocco `PRIOR AGENT NOTES` con quel contenuto (o `none yet` se assente);
- raccolta: dato un report fixture contenente una sezione `DURABLE NOTES:` ben formata, il
  parser dell'orchestratore estrae i bullet corretti, distingue `none`, e tollera un report
  troncato (non scrive note parziali ambigue);
- persistenza: l'append finisce in `memory/agent-notes/<agente>.md`, **mai** in `MEMORY.md`.

Inoltre, `vibe-status` (ADR-0005) è un candidato naturale per **segnalare** in modo read-only
la presenza/freschezza di `memory/agent-notes/` come parte dell'health report (non
bloccante). Ciò che NON è testabile headless (che l'orchestratore *si ricordi* di fare
l'harvest in una sessione reale) resta open question da validare in pilota — onestà coerente
con ADR-0008/0009/0010/0011.

---

## Consequences

### Positive

- **Conflitto risolto alla radice.** Nessun agente crea più file nel tracked tree → la regola
  anti-scaffolding dei progetti target non viene più violata; niente cleanup ricorrente
  pre-PR, niente `.gitignore` per-progetto da aggiungere.
- **Memoria consolidata.** Un solo sistema di memoria (l'auto-memory centrale), con un
  namespace dedicato `agent-notes/` separato dall'indice curato → fine della ridondanza dei
  due sistemi paralleli.
- **Sopravvive a clean-public-repo / git clean / clone.** Le note vivono fuori dal repo: un
  `clean-public-repo` (ADR-0011), un `git clean`, un clone fresco o la pubblicazione non le
  toccano e non le espongono. (Prima, vivendo nel tree, erano sia un rischio di esposizione
  sia un bersaglio di rimozione.)
- **Fragilità dell'encoding eliminata lato subagent.** Solo l'orchestratore risolve il path
  encoded; i subagent non ricadono mai nella trappola `_`→`-` / `cwd` vs
  `dirname(transcript_path)` (ADR-0004, `feedback_pretooluse-payload-schema.md`).
- **Pattern coerente col sistema.** Iniezione via prompt-template (già usata) + report
  strutturato (`DURABLE NOTES:`, sorella di `PATTERN:` di ADR-0001): nessun nuovo paradigma.

### Negative

- **Onere ricorrente sull'orchestratore.** Ogni dispatch dei 3 agenti richiede due passi
  extra: iniettare le note prima, raccogliere `DURABLE NOTES:` dopo. Nel chain è
  automatizzato dai template; nel dispatch diretto è disciplina dell'orchestratore.
- **Rischio di dimenticare l'harvest.** Se l'orchestratore non raccoglie, la memoria si perde
  in silenzio. Mitigazione: contratto esplicito nel chain (D4) + harness round-trip + segnale
  read-only in vibe-status (D6). Resta un rischio operativo per il dispatch fuori chain.
- **Perdita di portabilità col progetto.** Le note non viaggiano più col repo: chi clona il
  progetto su un'altra macchina/account non eredita la memoria degli agenti (prima, vivendo
  nel tree, era — impropriamente — portabile). Trade-off accettato: quelle note sono
  scaffolding di sessione, non artefatti da condividere col progetto.
- **Accoppiamento al path interno della harness.** Il design accoppia la persistenza al
  layout `~/.claude/projects/<encoded>/memory/` — ma l'accoppiamento è confinato
  all'orchestratore (che già lo gestisce), non propagato ai subagent.

### Neutral

- **Nuovo namespace `memory/agent-notes/<agente>.md`** nello store, separato da `MEMORY.md`.
  Append-only, non linkato dall'indice curato.
- **`.bak` storico invariato** (`refactorer.md.bak-2026-05-20`): resta com'è, citato solo come
  storico.
- **Repo `vibe-coding-system` NON-git:** il deliverable di questo ADR è il solo markdown.
  Il deploy degli artefatti live (patch alle 3 definizioni agente, patch al chain
  `concept-to-code`, eventuale patch a `claude-md-generator`, nuovo harness) è un **task
  separato** (plan TDD), **senza commit step**, dopo approvazione di Stefano.
- **Schema manifest invariato.** Il contratto iniezione/raccolta è veicolato via
  prompt-template e protocollo di dispatch; non richiede nuovi campi nel manifest né nuovi
  stati nella state machine.

---

## Alternatives considered

### A — Tenere `docs/agent-notes/` ma git-ignorarlo (per-progetto)

Minimale, rischio quasi-zero (gli agenti non cambiano). Aggiungendo `docs/agent-notes/` al
`.gitignore` del progetto target, il file non finisce mai nel tracked tree e non viola la
regola anti-scaffolding. **Rifiutata** perché: (1) lascia **due sistemi di memoria** paralleli
(non consolida niente — il problema della ridondanza resta); (2) richiede una riga di
`.gitignore` in **ogni** progetto target (onere per-progetto ricorrente, facile da
dimenticare su un repo nuovo → ricade nel conflitto); (3) le note restano dentro il working
tree → ancora a rischio in scenari di pubblicazione/cleanup, anche se non tracciate. Risolve
il sintomo (tracking) ma non la causa (memoria nel posto sbagliato).

### B-naive — Il subagent scrive direttamente nel path encoded dello store

Eliminerebbe l'onere dell'orchestratore (niente raccolta). **Rifiutata** perché **fragile e
accoppiata all'encoding della harness**: il subagent dovrebbe risolvere
`<encoded-project-dir>` da sé, e la regola di encoding è instabile tra versioni di Claude Code
(`_`→`-` e altro; `cwd` ri-encodato ≠ path reale). È esattamente la trappola che ha già
prodotto bug bloccanti (ADR-0004 v1.0/v1.1, `feedback_pretooluse-payload-schema.md`).
Concentrare la conoscenza del path nel **solo** orchestratore è il principio di robustezza che
B-mediata adotta.

### C — Rimuovere del tutto il meccanismo agent-notes

La più semplice: si tolgono i passi read/append dalle 3 definizioni e basta, senza
sostituirli. **Rifiutata** perché **perde la memoria cross-session degli agenti** — il valore
che il meccanismo, pur mal collocato, forniva (un debugger che ricorda un bug-pattern
ricorrente, un architect che ricorda una decisione passata). Se in pilota emergesse che gli
agenti non producono mai note durevoli utili, C tornerebbe la scelta più economica; oggi
l'assunzione è che la memoria valga il suo costo (vedi Assunzioni).

### D — Committare le note nel tracked tree (cambiare la regola)

Si terrebbe `docs/agent-notes/` e si **cambierebbe** la regola di doc-discipline per
permetterlo (versionando le note col progetto). **Rifiutata** perché le note sono
**scaffolding di sessione**, non artefatti di prodotto da condividere: committarle gonfia la
history, le espone in un repo pubblico (in tensione diretta con ADR-0011) e fa rumore nei PR.
La regola anti-scaffolding esiste per una ragione; cambiarla per accomodare un meccanismo mal
collocato è risolvere il conflitto dalla parte sbagliata.

### Perché B-mediata nonostante il costo

B-mediata è l'unica che **consolida** la memoria (un solo sistema), **risolve il conflitto
alla radice** (niente file nel tree), **evita la fragilità dell'encoding** (solo
l'orchestratore conosce il path) e **preserva il valore** della memoria agente (a differenza di
C). Il prezzo è l'onere ricorrente sull'orchestratore e il rischio-harvest, entrambi mitigabili
(contratto nel chain + harness + segnale vibe-status).

**Tensione esplicita con "Building Effective Agents" (Anthropic):** il principio "non
aggiungere complessità finché il semplice non fallisce" spingerebbe verso l'Alternativa A
(git-ignore) o C (rimozione). La scelta di B-mediata si giustifica solo perché **il semplice
ha già fallito in modo ricorrente** (la cancellazione una-tantum non regge un meccanismo
by-design) **e** perché il sistema ha già l'infrastruttura (auto-memory + dispatch via
prompt-template) che rende B-mediata un'estensione di pattern esistenti, non un nuovo
paradigma. Se il pilota mostrasse che l'harvest viene dimenticato sistematicamente o che le
note prodotte sono prive di valore, la decisione andrebbe rivalutata verso A o C — questa
tensione resta un open question dichiarato.

---

## References

- `~/.claude/agents/architect.md` (Process p.5 ~riga 33; Write scope ~riga 64) — read+append
  e write-scope verso `docs/agent-notes/architect.md` da rimuovere.
- `~/.claude/agents/debugger.md` (Process p.2 ~riga 28, p.6 ~riga 32) — read+append da rimuovere.
- `~/.claude/agents/reviewer.md` (Process p.3 ~riga 29) — read+append da rimuovere.
- `~/.claude/agents/refactorer.md.bak-2026-05-20` — `.bak` inattivo con lo stesso pattern
  (storico; non toccare).
- `~/.claude/skills/concept-to-code/SKILL.md` — dispatch via prompt-template (Step 2 architect
  ~167-202, Step 5 coder ~259-271, nota "not patched / literal prompt template" ~544); punto di
  innesto del contratto iniezione/raccolta.
- `~/.claude/skills/claude-md-generator/SKILL.md` — non deve re-introdurre la regola in
  conflitto (D5).
- Auto-memory store: `~/.claude/projects/-Users-stefanoferri-Developer-vibe-coding-system/memory/`
  (`MEMORY.md` indice curato + file per-topic con frontmatter) — modello del namespace
  `agent-notes/` separato.
- `feedback_pretooluse-payload-schema.md` (stesso store) — fragilità encoding project-dir
  (`_`→`-`, `dirname(transcript_path)` vs `cwd`) evitata lato subagent (D2).
- `feedback_subagent-truncation-transport.md` (stesso store) — perché `DURABLE NOTES: none`
  esplicito serve a distinguere "nessuna nota" da "report troncato".
- ADR-0003 — `docs/architecture/ADR-0003-concept-to-code-chain.md` (chain in cui si innesta il
  contratto).
- ADR-0001 — `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (precedente del
  report strutturato machine-greppable, sorella di `DURABLE NOTES:`).
- ADR-0004 — `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` (fonte della
  fragilità encoding).
- ADR-0005 — `docs/architecture/ADR-0005-vibe-status-skill.md` (candidato presidio read-only del
  round-trip).
- ADR-0011 — `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` (le note fuori dal tree
  sopravvivono a clean-public-repo / fresh-history publish).
