# CLAUDE.md — [NOME_PROGETTO]

Eredita `~/.claude/CLAUDE.md` e le rules globali. Qui solo ciò che è specifico del progetto.

## Progetto
- Web app: backend FastAPI + frontend React.

## Stack
- Backend: FastAPI + SQLAlchemy 2.x + Pydantic v2 + Alembic.
- Frontend: React 19 + TypeScript + Vite + Tailwind + shadcn/ui.
- DB dev: SQLite. Package: pip (Python), npm (Node).

## Comandi
- Backend test: `pytest`
- Backend lint/type: `ruff check` · `mypy src/`
- Frontend test: `npm test`
- Frontend lint/type: `npm run lint` · `npm run tsc`

## Struttura
Backend in `backend/src/`, frontend in `frontend/src/`. Dettagli in `ARCH.md`.

## Note
- Aggiungi `CLAUDE.local.md` a `.gitignore` per preferenze personali non condivise.
