---
name: project-bootstrap
description: This skill should be used only for a small new project that justifies a fast end-to-end bootstrap (interview to SPEC to ARCH to CLAUDE.md to initial commit). Triggers include "bootstrap del progetto", "parti da zero veloce".
disable-model-invocation: true
---

Bootstrap del progetto: $ARGUMENTS

Step (HITL gate dopo ognuno — l'utente approva prima di proseguire):
1. Invoca la skill `interview-driver` con la descrizione → `SPEC.md`.
2. Genera `ARCH.md` (decisioni principali con ADR-001..N); puoi invocare l'agente `architect`.
3. Invoca la skill `claude-md-generator` per il `CLAUDE.md` di root.
4. `git init` + commit iniziale "chore: initial spec and architecture" (questo vale per i progetti NUOVI, non per il repo del sistema).
5. Presenta il riepilogo dei file generati.
