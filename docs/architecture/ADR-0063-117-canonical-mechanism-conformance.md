# ADR-0063 — Canonical-mechanism conformance

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #117 (eighteenth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/117-canonical-mechanism-conformance.spec.md`
- **Closes:** gap **G-16** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (ABSENT, **P3**).

## Context

`staging/user/rules/python.md`, `typescript-react.md`, `swift.md` and `shell.md` carry conventions
as prose with `paths:` frontmatter. `coder.md:66` says stack tooling comes from the project
CLAUDE.md and the rules files.

**Those files carry taste; they do not carry mechanism identity.** No project declares its one true
HTTP client, logger, config accessor, DB access layer or error type, and nothing checks conformance.
The spec's failure mode is an agent hand-rolling an HTTP call — or pulling a new dependency for it —
while a canonical helper already exists in a hundred other places.

## Decision

### D1 — `.claude/rules/canonical-mechanisms.md`, one line per mechanism

`name → import path or symbol`, with `paths:` frontmatter so it loads only for the relevant stack.
It joins the existing rules convention rather than inventing a parallel one, which means it costs
nothing in the loader and is already understood.

Deliberately a flat list, not a schema. The value is in a coder reading one line before writing an
HTTP call; a structured format would raise the cost of writing it and the first casualty would be
that anyone writes it at all.

### D2 — `project-init` drafts it by detecting the dominant mechanism

Most-imported HTTP client, logger, config module. A draft, reviewed by a human — the same
propose-never-write-silently contract ADR-0053 §D6 and ADR-0055 §D5 use.

Detection is the right way to seed this specifically because the canonical mechanism **is** the one
already used most; that is what canonical means here. This is the one place in the roadmap where
auto-derivation is sound, and it is worth naming why: the property being detected and the property
being declared are the same property. Contrast ADR-0055 §A4, where a path heuristic for `risk` was
rejected because location does not determine risk.

### D3 — Conformance is a MINOR reviewer finding, not a gate

Added to `reviewer.md`'s Consistency checklist: flag a hand-rolled equivalent of anything declared
canonical.

MINOR, and not blocking, because a "hand-rolled equivalent" is a judgement — there are legitimate
reasons to bypass a canonical helper, and a gate would have to be argued with on every one of them.
Consistent with the evidence-quality rule this roadmap has applied five times now: heuristics report,
mechanical facts gate.

### D4 — No detector script

The check lives in the reviewer's judgement, not in a pattern matcher. Recognising that
`urllib.request.urlopen` is a hand-rolled equivalent of a declared `httpx` client requires knowing
what the declaration meant, and a grep for the symbol would flag every legitimate low-level use.

This is the same conclusion ADR-0062 §D4 reached for debug-log statements, for the same reason, and
the same one ADR-0051 reached by measurement when a comparable heuristic scored 25% precision.

### D5 — Absent file means inert

No `canonical-mechanisms.md`, no findings. Consistent with ADR-0055 §D2's rule: this *adds* a
constraint, so absent equals the pre-feature behaviour. It does not mean the project has no
canonical mechanisms — it means nobody declared them, and the system cannot tell those apart.

## Alternatives rejected

- **A1 — A conformance detector script.** Rejected under §D4.
- **A2 — Make conformance blocking.** Rejected under §D3: legitimate bypasses exist and a gate would
  be argued with until it was disabled.
- **A3 — A structured schema instead of a flat list.** Rejected under §D1: raises the writing cost,
  and an unwritten declaration protects nothing.
- **A4 — Auto-generate and apply without review.** Rejected under §D2: detection seeds a draft; a
  declaration nobody approved is one nobody will honour.
- **A5 — Fold this into the existing per-language rules files.** Rejected: mechanism identity is
  project-specific, the rules files are stack-generic and shared, and mixing them would put a
  project's private choices into a file meant to be reused.

## Consequences

### Positive

- Projects gain a place to say "this is the HTTP client", which no file previously provided.
- `project-init` makes the first draft nearly free, which is the difference between a convention
  that exists and one that does not.
- No new detector, so no new false-positive surface and nothing added to the advisory load
  ADR-0052 §D5 flagged.

### Negative, stated plainly

- **Nothing enforces it.** §D3 is a reviewer instruction and §D4 declines to detect. Like ADR-0062,
  this is an instruction-layer feature and should be read as one.
- **A stale declaration is worse than none**, because it points at a mechanism the project has
  since moved off. Nothing detects staleness, and `project-init --update` re-drafting is the only
  refresh path.
- **Inert until declared** (§D5), so the value arrives after the merge — the same shape as every
  opt-in feature in this roadmap.
- P3 is the correct priority.
