---
paths:
  - "**/migrations/*.sql"
  - "**/alembic/versions/*.py"
---

# DB migrations

- IMPORTANT: mai modificare una migration già applicata in produzione.
- Backup del DB prima di una migration in produzione.
- HITL gate prima di `alembic upgrade head` in qualunque ambiente diverso da dev.
- Genera con `alembic revision --autogenerate -m "..."`.
- Rivedi sempre il diff generato prima del commit.
