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
