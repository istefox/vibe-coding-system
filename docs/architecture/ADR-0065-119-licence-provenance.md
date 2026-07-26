# ADR-0065 — Licence and provenance scanning

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #119 (twentieth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/119-licence-provenance.spec.md`
- **Builds on:** ADR-0056 (#110) for the opt-in CI-job shape and the pinned-tool rule.
- **Closes:** gap **G-25** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (ABSENT, **P3**).

## Context

`clean-public-repo` handles anonymisation and tool-trace removal (ADR-0011, ADR-0026) and explicitly
refuses to falsify authorship — the right call, and it stays. Nothing scans for licence
contamination or for verbatim reproduction of a licensed snippet.

The spec's default posture is to *treat AI-generated code as if it is under an ambiguous licence*.
The concrete risk it names: a GPL-derived snippet reproduced into a proprietary tree is undetectable
without a scanner, and **open source does not mean public domain**. It also records a
suspicious-output procedure — if output looks verbatim, especially with distinctive comments or
author names, search a unique string before keeping it.

## Decision

### D1 — An opt-in licence-scan job, following ADR-0056's shape exactly

Same pattern as the SAST job: separate, opt-in by a repo marker, pinned tool version. Opt-in because
it is irrelevant to a private single-author repo and adds runtime.

Pinned for ADR-0056 §D2's reason, which applies unchanged here: the CI job is legitimate because a
declared runner plus a pinned version makes two runs of the same commit agree. An unpinned scanner
would reintroduce exactly the machine-dependent verdict ADR-0039 §D4 removed.

### D2 — The suspicious-output procedure is a documented human check, not a detector

Added to `clean-public-repo`'s audit phase: if output looks verbatim — distinctive comments, author
names, unusual identifiers — search a unique string before keeping it.

**Deliberately a procedure and not a script.** Deciding that a snippet "looks verbatim" is a
judgement about style and distinctiveness that no pattern matcher makes, and a heuristic that tried
would fire on every idiomatic implementation of a common algorithm. This is the same conclusion
ADR-0062 §D4 reached for debug logs and ADR-0063 §D4 for canonical mechanisms, and the one ADR-0051
reached by measurement at 25% precision.

The procedure also requires a network search, which is not something a deterministic CI check can do
reproducibly — so it belongs where a human already is.

### D3 — Findings report; they do not block

A licence scanner reports what a dependency *declares*, and declarations are frequently wrong,
missing, or dual. Treating that as a merge gate would block on metadata quality rather than on legal
risk.

Consistent with the evidence-quality rule applied throughout this roadmap: this is closer to a
heuristic than to a mechanical fact, so it reports. Contrast ADR-0053, where a protected signature is
either present or not, and blocking was therefore justified.

### D4 — This is not legal advice and the text must not imply it is

A scanner finding is an input to a human decision about licensing, not a determination. The skill
and CI text say so.

This matters more here than in most features: a green licence scan reads as "we are clear", and that
reading is wrong in a way that could actually harm someone. Same class of overclaim ADR-0059 §D1
refused for prompt injection, and the mitigation is the same — say plainly what the check does and
does not establish.

### D5 — `clean-public-repo`'s refusal to falsify authorship is untouched

ADR-0011 and ADR-0026 settled it. Nothing here weakens it, and provenance scanning must not become a
route to rewriting attribution — the goal is to *notice* contamination, never to hide it.

## Alternatives rejected

- **A1 — Block the build on licence findings.** Rejected under §D3: blocks on metadata quality.
- **A2 — A verbatim-reproduction detector.** Rejected under §D2: needs a judgement about
  distinctiveness and a network search, neither of which is a reproducible CI check.
- **A3 — Make the scan mandatory.** Rejected under §D1: irrelevant to a private single-author repo,
  and a job that runs pointlessly gets disabled, taking the relevant cases with it.
- **A4 — Have the tool auto-strip or rewrite offending code.** Rejected under §D5: that is
  hiding contamination, and it collides with the standing refusal to falsify authorship.

## Consequences

### Positive

- The first provenance signal in the system, against a risk that is genuinely invisible without one.
- The suspicious-output procedure is written down where the human doing a publication audit will
  read it.
- Reuses ADR-0056's job shape, so no new pattern to maintain.

### Negative, stated plainly

- **A green scan does not mean the tree is clean** (§D4). It means declared metadata showed nothing.
  Verbatim reproduction of an unattributed snippet is exactly what it cannot see, and that is the
  risk the spec actually names.
- **Off by default** (§D1), so inert for existing repos — the same shape as #106–#111 and #117.
- **The pinned version will go stale**, the direct cost of §D1's determinism, unsolved here as in
  ADR-0056.
- **§D2 is a procedure a human may skip.** Nothing enforces it, and this is the third P3 feature in a
  row whose real mechanism is instruction rather than machinery.
