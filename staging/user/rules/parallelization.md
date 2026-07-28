---
paths:
  - "**/*.py"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.swift"
---

# Orchestrator parallelization policy

When a coding task spans multiple files, decide serial vs parallel sub-agent
fan-out using these criteria, in order:

1. **File independence** — sub-agents touch disjoint files/modules → parallel
   fan-out allowed.
2. **Test state** — tests green → parallel; tests red → serial (fix first).
3. **Task type** — research/planning → serial; coding/test/doc → parallelizable.

Cap: at most 4 parallel sub-agents; beyond that, sequential batches of 3–4.
Parallel modification sub-agents run in a git worktree forked from `HEAD`; the orchestrator
merges each stage back into the feature branch before the next worktree is created. A non-git
CWD is refused with an actionable message, not downgraded to any other mode (ADR-0068).

## Plan-mode e fan-out (chiarimento, spec §9.1 — 2026-05-19)

Plan mode resta OBBLIGATORIO per task che modificano >1 file (regola
IMPORTANT del CLAUDE.md globale: invariata). Il piano di fan-out
dell'orchestrator È l'artefatto da presentare per l'approvazione in plan
mode. Una volta che QUEL piano è approvato dall'utente, l'esecuzione dei
sub-agent al suo interno procede senza richiedere una seconda approvazione
plan-mode separata per lo stesso lavoro già approvato. In nessun caso questo
autorizza a saltare plan mode quando il piano di fan-out non è stato approvato.
