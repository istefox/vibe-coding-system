---
name: adr-writer
description: This skill should be used when an architectural decision has been taken (or the architect agent is producing a design) and a standardized Architecture Decision Record must be written under docs/architecture/.
---
<!-- skill-coverage-exempt: prompt template only — every line is an instruction to a model, so there is no mechanical contract a test could assert without inventing one (ADR-0084). -->

Create `docs/architecture/ADR-NNN-$ARGUMENTS.md` (NNN incremental, aligned with the architect agent output).

Mandatory structure, each section concrete, no fluff:
1. Status (Proposed / Accepted / Deprecated / Superseded)
2. Context (problem, constraints, requirements)
3. Decision (the choice made, stated clearly)
4. Alternatives considered (at least 2, with reason for rejection)
5. Consequences (positive, negative, neutral)
6. References (related ADRs, docs, issues)

Never let a line wrap so an issue number like `#123` lands at column 1 — `markdownlint`'s MD018
reads it as a heading. Keep the number on the previous line.
