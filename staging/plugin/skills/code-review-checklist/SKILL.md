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
