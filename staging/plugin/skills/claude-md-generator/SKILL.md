---
name: claude-md-generator
description: This skill should be used when SPEC.md and ARCH.md exist and a lean Anthropic-compliant project CLAUDE.md must be generated. Triggers include "genera il CLAUDE.md di progetto", "crea il claude.md di root".
---

Leggi `SPEC.md` e `ARCH.md` della cartella corrente.

Scegli il template appropriato fra i project-template del sistema (zona project-templates):
- stack SwiftUI/iOS → `ios-swiftui`
- web app FastAPI+React → `app-fastapi-react`
- sito web semplice/WordPress/vanilla → `web-vanilla-wordpress`

Genera `CLAUDE.md` di root **lean e Anthropic-compliant**:
- Eredita il `~/.claude/CLAUDE.md` globale: NON duplicare lingua, HITL, git, sicurezza, convenzioni di stile (sono nelle rules path-scoped).
- Includi solo ciò che Claude non può inferire dal codice: comandi build/test reali, decisioni architetturali del progetto, struttura cartelle scelta, gotcha.
- Target < 100 righe. Niente stack-specific che appartiene alle rules.
