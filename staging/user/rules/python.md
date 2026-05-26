---
paths:
  - "**/*.py"
---

# Python

- Type hint obbligatori su tutte le signature.
- Docstring stile Google su funzioni e classi pubbliche: Args, Returns, Raises.
- Commenti inline: spiega il WHY non il WHAT — sii generoso (sto imparando).
- `logging` in codice di produzione, mai `print()`.
- Formatter: Black. Linter: Ruff. Type check: mypy strict mode.
- Test: pytest, file `test_<module>.py`. Esegui prima il singolo test: `pytest tests/test_x.py::test_y -v`.
