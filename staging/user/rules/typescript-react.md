---
paths:
  - "**/*.{ts,tsx}"
---

# TypeScript & React

- `interface` per le props, `type` per union/utility.
- Mai `any`: usa `unknown` + narrowing.
- Function component + hooks (no class component).
- `useState` per stato locale; Context o Zustand per stato condiviso. No prop drilling oltre 2 livelli.
- Mai `useEffect` senza dependency array corretto. Mai mutazione diretta dello state.
- Package manager: `npm`.
