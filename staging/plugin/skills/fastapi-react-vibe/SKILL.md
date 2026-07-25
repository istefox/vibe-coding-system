---
name: fastapi-react-vibe
description: This skill should be used when adding a CRUD resource to a FastAPI+React project and a full backend+frontend scaffold is needed.
disable-model-invocation: true
---

Generate the scaffold for the "$ARGUMENTS" resource.

Backend (`backend/src/<pkg>/`):
- `models/<arguments>.py`: SQLAlchemy 2.x model with `Mapped[]`
- `schemas/<arguments>.py`: Pydantic v2 (Create/Update/Read)
- `services/<arguments>.py`: business logic
- `api/<arguments>.py`: FastAPI router with CRUD
- `tests/<arguments>_test.py`: pytest, 4 basic tests

Frontend (`frontend/src/`):
- `features/<arguments>/api.ts`: fetch wrapper
- `features/<arguments>/hooks.ts`: useQuery/useMutation
- `features/<arguments>/<Arguments>List.tsx`: shadcn/ui table
- `features/<arguments>/<Arguments>Form.tsx`: react-hook-form + zod form
- add the route to the routing config

Package manager: `npm`. Follow existing ADRs and the current code style.
