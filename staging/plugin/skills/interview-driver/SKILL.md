---
name: interview-driver
description: This skill should be used when starting a new project or non-trivial feature and a SPEC.md must be produced by interviewing the user in depth with the AskUserQuestion tool. Triggers include "intervistami", "facciamo lo SPEC", "nuovo progetto da zero".
disable-model-invocation: true
---

L'utente vuole costruire: $ARGUMENTS

Intervistalo in profondità con il tool AskUserQuestion. Copri: implementazione tecnica, UI/UX (se applicabile), edge case, trade-off, vincoli operativi, Definition of Done.

Non fare domande ovvie: scava sui punti difficili. Una domanda alla volta, max 3-4 opzioni per domanda. Continua finché non hai coperto tutto.

Poi scrivi `SPEC.md` nella cartella corrente con: obiettivi, scope, stack, architettura, modello dati, API, flussi UI, edge case, success criteria. Niente codice in questa fase.
