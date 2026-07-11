---
name: adr-writer
description: This skill should be used when an architectural decision has been taken (or the architect agent is producing a design) and a standardized Architecture Decision Record must be written under docs/architecture/.
---

Create `docs/architecture/ADR-NNN-$ARGUMENTS.md` (NNN incremental, aligned with the architect agent output).

Mandatory structure, each section concrete, no fluff:
1. Status (Proposed / Accepted / Deprecated / Superseded)
2. Context (problem, constraints, requirements)
3. Decision (the choice made, stated clearly)
4. Alternatives considered (at least 2, with reason for rejection)
5. Consequences (positive, negative, neutral)
6. References (related ADRs, docs, issues)
