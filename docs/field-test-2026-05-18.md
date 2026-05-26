# Field test 2026-05-18 — pricing-markup-cli

Validazione sul campo di trigger e `description` di skill/agenti del sistema vibe
coding deployato. Runbook: `docs/superpowers/plans/2026-05-18-pilot-field-test.md`.
Spec: `docs/superpowers/specs/2026-05-18-pilot-field-test-design.md`.

Stato: **IN CORSO** — avvio 2026-05-18.

## Tabella trigger (compilata man mano dalle osservazioni utente)

| Skill/Agente | Trigger atteso | Trigger reale | Auto/Manuale OK | Esito | Note/mis-fire |
|---|---|---|---|---|---|
| interview-driver | solo manuale (/), produce SPEC.md | attivata solo su `/interview-driver` esplicito; ha prodotto SPEC.md | OK (manuale, coerente con disable-model-invocation) | ✅ ottimo | Domande di alta qualità: ha scovato conflitti di dominio reali e non ovvi (markup vs margine; charm rounding vs margine garantito; IVA scope; virgola IT; soglie invalide). Ha flaggato un'assunzione residua (`--ending`) con confidence dichiarata. Ha offerto come opzione "TDD diretto" che bypasserebbe l'architect (non un mis-fire, scelta di scope). |
| architect | @agent, ADR, no codice prod | ADR-001-pricing-core.md creato, Status Accepted, struttura corretta; ha flaggato rischi/incongruenze SPEC e HITL gate; aderente allo SPEC (no regressione half-up/markup) | OK (no codice produttivo) | ✅ buono | Ha scritto anche `docs/agent-notes/architect.md` (by-design dal suo system prompt = memory-intent), nonostante il prompt ad-hoc dicesse "solo l'ADR" → ha dato priorità al system prompt. NON mis-fire, ma sorpresa per l'utente → tweak di chiarezza. sequential-thinking MCP: non riportato (da confermare). Ottimo: ha segnalato l'incongruenza §6/§5.2 sui default built-in (comportamento architect corretto: surfacing rischi). |
| claude-md-generator | manuale, degrada grazioso fuori-template | CLAUDE.md generico per CLI Python, 68 righe, eredita globale senza duplicare, usa ADR al posto di ARCH.md assente | OK (manuale) | ✅ ottimo | Degrado fuori-template eccellente (no forzatura template React/iOS); gestione graziosa di ARCH.md assente via ADR; lean Anthropic-compliant. Tweak candidato (positivo): codificare nella description/body "se nessuno dei 3 template combacia, genera CLAUDE.md generico lean" — ora è comportamento emergente corretto, meglio renderlo intenzionale-by-spec. |
| coder | @agent, Decimal, no commit | _da rilevare_ | | | |
| rule python.md | caricata su *.py | _da rilevare_ | n/a | | |
| hook auto-format | riformatta dopo edit .py | _da rilevare_ | n/a | | |
| hook protect-files | blocca file protetti se toccati | _da rilevare_ | n/a | | |
| tester | @agent, pytest edge, no codice prod | _da rilevare_ | | | |
| debugger | @agent, root cause vera, fix minimo | _da rilevare_ | | | |
| reviewer | @agent, severità, read-only | _da rilevare_ | | | |
| auto mode | nessun falso blocco su azione legittima | _da rilevare_ | n/a | | |

## Mis-fire / no-fire osservati

- T1 interview-driver: **nessun mis-fire**. Trigger manuale corretto, qualità alta.
- Nota minore: `interview-driver` offre tra i next-step un percorso "TDD diretto" che salterebbe l'agente `architect`. Non è un difetto, ma per chi vuole il flusso completo concept→code può indurre a saltare l'ADR.
- T2 architect: nessun mis-fire funzionale. Tensione "prompt ad-hoc vs system prompt": l'invocazione diceva "solo l'ADR" ma l'agente ha (correttamente) scritto anche `docs/agent-notes/architect.md` come da suo system prompt. Tweak candidato: nel system prompt dell'architect chiarire che la scrittura di agent-notes è un'azione di *memoria/meta* distinta dall'"output di progettazione", così non sorprende chi vincola l'output ad-hoc.
- T2: la sessione del pilota propone spontaneamente un flusso proprio (writing-plans / agente Plan / TDD su feature branch) diverso dal runbook del field test (prossimo step previsto = `/claude-md-generator`). Osservazione: l'orchestratore del pilota tende a re-pianificare invece di seguire la sequenza concept→code del blueprint.
- T3 (workflow, non skill): le decisioni prese in conversazione (default `ending=0.99`/`margin` obbligatorio) NON rifluiscono automaticamente in SPEC/ADR/CLAUDE.md → il CLAUDE.md generato riporta ancora "default vuoti / decisione aperta". Rischio reale: il `coder` leggerebbe i doc e implementerebbe `ending` come obbligatorio (errato vs decisione). Mitigazione adottata: passare la decisione esplicitamente nel prompt del `coder` (Task 4). Tweak/processo candidato: step di "sync decisione → SPEC/ADR" prima dell'implementazione, oppure far sì che le skill di decisione aggiornino i doc.

## Tweak proposti (description/prompt) — da applicare in ciclo separato

### PRIORITARIO — frizione "plan mode vs delega agenti" (osservato 3× a T1/T2/T4)
L'orchestratore ri-pianifica invece di delegare a `@coder`, perché segue la
regola globale `~/.claude/CLAUDE.md` "plan mode obbligatorio per >1 file".
Corretto-by-design ma crea attrito col flusso architect→coder. Tweak proposti
(scegliere uno o combinare):
1. In `~/.claude/CLAUDE.md` (Workflow invarianti): aggiungere che **un ADR
   Accepted con decomposizione/mappatura architettura soddisfa il requisito di
   plan mode** → l'orchestratore può delegare a `coder` senza ri-pianificare.
2. Nella `description`/system prompt dell'agente `coder`: esplicitare che il
   coder esegue il piano contenuto nell'ADR (l'ADR È il piano per feature
   piccole/medie).
3. Nella `description` dell'agente `architect`: chiarire che il suo output
   (ADR + 3-8 step) è il deliverable che assolve il plan-mode, così l'orchestratore
   non invoca anche `writing-plans`.

_(altri tweak da compilare a fine test)_
