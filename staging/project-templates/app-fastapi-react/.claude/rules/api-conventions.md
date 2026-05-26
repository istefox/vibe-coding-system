---
paths:
  - "backend/src/**/api/**/*.py"
---

# API conventions
- Un router per dominio in `api/` (uno per feature).
- Response model Pydantic esplicito su ogni endpoint.
- Status code: 200/201/204/400/401/403/404/422/500.
- Dependency injection per DB session, auth, settings.
- Usa `select(Model).where(...)` (no `session.query(...)` legacy).
- Eager loading esplicito: `selectinload`/`joinedload`.
