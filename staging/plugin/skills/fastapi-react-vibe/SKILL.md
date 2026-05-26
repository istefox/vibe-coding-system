---
name: fastapi-react-vibe
description: This skill should be used when adding a CRUD resource to a FastAPI+React project and a full backend+frontend scaffold is needed. Triggers include "scaffolda la risorsa X", "nuovo endpoint CRUD FastAPI+React".
disable-model-invocation: true
---

Genera lo scaffold per la risorsa "$ARGUMENTS".

Backend (`backend/src/<pkg>/`):
- `models/<arguments>.py`: SQLAlchemy 2.x model con `Mapped[]`
- `schemas/<arguments>.py`: Pydantic v2 (Create/Update/Read)
- `services/<arguments>.py`: business logic
- `api/<arguments>.py`: router FastAPI con CRUD
- `tests/<arguments>_test.py`: pytest, 4 test base

Frontend (`frontend/src/`):
- `features/<arguments>/api.ts`: fetch wrapper
- `features/<arguments>/hooks.ts`: useQuery/useMutation
- `features/<arguments>/<Arguments>List.tsx`: tabella shadcn/ui
- `features/<arguments>/<Arguments>Form.tsx`: form react-hook-form + zod
- aggiungi la route alla config di routing

Package manager: `npm`. Segui gli ADR esistenti e lo stile del codice presente.
