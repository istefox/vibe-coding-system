---
name: claude-md-generator
description: This skill should be used when SPEC.md and ARCH.md exist and a lean Anthropic-compliant project CLAUDE.md must be generated.
---

Read `SPEC.md` and `ARCH.md` from the current directory.

Choose the appropriate template from the system project-templates (project-templates zone):
- SwiftUI/iOS stack → `ios-swiftui`
- FastAPI+React web app → `app-fastapi-react`
- Simple website/WordPress/vanilla → `web-vanilla-wordpress`

Generate a root `CLAUDE.md` that is **lean and Anthropic-compliant**:
- Inherits `~/.claude/CLAUDE.md` globally: do NOT duplicate language, HITL, git, security, or style conventions (those live in path-scoped rules).
- Include only what Claude cannot infer from the code: real build/test commands, project architectural decisions, chosen folder structure, gotchas.
- Target < 100 lines. No stack-specific content that belongs in rules.
