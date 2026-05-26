# SPEC — Modalità anonimizzazione contributo strumento per repo pubblici

**Data:** 2026-05-23
**Topic:** gate y/n nel chain `concept-to-code` + skill `clean-public-repo`

## Obiettivo

Permettere che un repo pubblico sia giudicato per la **qualità del codice**, non penalizzato per lo strumento usato. Il sistema produce repo puliti (commit essenziali, doc concisi, nessun file inutile) e **senza tracce esplicite dello strumento** (trailer, commenti, stringhe, emoji-slop). Il lavoro resta dell'utente: lui lo dirige, rivede, testa ed è responsabile.

## Inquadramento etico (vincolo, non opzione)

- Scopo: **non sbandierare lo strumento** + **qualità del codice**.
- NON è: falsificare autori (mai attribuire a persone reali che non hanno contribuito), né mentire attivamente se qualcuno chiede esplicitamente.
- L'attribuzione dello strumento è già disattivata nativamente (`settings.json: attribution {commit:"", pr:""}`).

## Scope

**In scope:**
1. **Gate di attivazione** nel chain `concept-to-code` (auto-detect + conferma): se il repo ha un remote GitHub **pubblico**, il chain propone la modalità anonima con `[y/n]`; su repo privati/locali resta **silenzioso**.
2. **Modalità anonima durante il chain** (se attivata): commit corti/essenziali, doc concisi, nessun file slop, nessun commento-traccia — output già conforme.
3. **Skill `clean-public-repo`** (nome provvisorio): audit + cleanup di un repo, sia nuovo sia **esistente** (cleanup retroattivo, es. plugin Obsidian già pubblicato).

**Out of scope:**
- Normalizzazione stilistica per ingannare review umane (non si fa).
- Test E2E / altri workflow (separati).

## Requisiti funzionali

- **R1 — Attivazione:** auto-detect remote GitHub pubblico → gate `[y/n]`. Silenzioso su privati/locali. (Decisione utente, non auto-applicata.)
- **R2 — Azione ibrida:** la skill **segnala** (report "pronto / da-pulire") e **rimuove su conferma** dell'utente. Mai rimozione cieca.
- **R3 — Cosa pulire (tutto ove possa comparire la traccia):**
  - Trailer commit (`Co-Authored-By: Claude`, `Generated with Claude Code`)
  - Commenti-traccia nel codice (`// added by Claude`, riferimenti a task/AI, TODO generati)
  - File slop / inutili (README ridondanti, scratch) + doc gonfi (da accorciare)
  - Stringhe `claude`/`AI` + emoji decorative non richieste
  - Qualunque altro residuo testuale riconducibile allo strumento
- **R4 — Commit history esistente:** trattamento **caso per caso con conferma**. Il rewrite cambia gli SHA → solo **prima del push pubblico**.
- **R5 — Safety del rewrite:** prima di riscrivere la history, **backup branch/tag automatico** + **dry-run** (mostra cosa cambierebbe) prima di applicare.
- **R6 — Scope retroattivo:** la skill funziona anche standalone su repo esistenti, non solo dal chain.

## Vincoli operativi

- Bash 3.2-clean per ogni script (ambiente macOS system bash).
- Coexistenza con il sistema esistente (chain v2, hook attivi, harness verdi) — anchor-preserving.
- Repo `vibe-coding-system` resta non-git; la feature opera sui **repo target** (git).
- Lingua: doc/comunicazione in italiano; codice/commit in inglese.

## Edge case

- Repo senza remote / remote privato → gate silenzioso, modalità non proposta.
- Repo con history lunga e molte tracce → dry-run + backup obbligatori; rewrite può essere oneroso.
- Falso positivo su stringa legittima (es. una dipendenza che si chiama davvero "claude-*", o "AI" in un nome di dominio) → la rimozione su-conferma protegge; segnalare, non rimuovere ciecamente.
- Repo già pushato pubblicamente → il rewrite della history richiede force-push (azione distruttiva remota): HITL esplicito, mai automatico.
- Branch detached / non-git → la skill degrada senza errori.

## Success criteria / Definition of Done

- Lanciando `clean-public-repo` su un repo, ottengo un **report** che elenca ogni traccia trovata (per categoria R3) con posizione.
- Su conferma, le tracce vengono rimosse; il repo resta funzionante (test verdi pre/post).
- Il gate nel chain si attiva solo su remote pubblico e rispetta la scelta `y/n`.
- Il rewrite della history avviene solo con backup + dry-run + conferma; mai force-push automatico.
- Zero tracce esplicite residue nello scope R3 dopo un cleanup confermato.
- Nessuna falsificazione di autori. Nessun test/guardrail del sistema rotto (harness verdi).

## Da decidere in fase di design (brainstorm/architect)

- Dove esattamente il gate nella state machine del chain (Gate 0 esteso / nuovo gate dedicato).
- Se la modalità anonima è un flag nel manifest che influenza i template di dispatch, o un layer separato.
- Tecnica di history rewrite (filter-repo / rebase / filter-branch) e relativi trade-off.
- Architettura della skill: bash + git, set di pattern di detection, formato del report.
- Nome definitivo della skill.
