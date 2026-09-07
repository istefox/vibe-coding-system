---
name: task678-deep-refactor-skill-gate-cdx
description: deep-refactor/SKILL.md Gate 0-CDX, dispatch-model IF/ELSE wrap, Gate 1 engine attribution (Tasks 6-8, ADR-0193) — exact-count string traps and file conventions
metadata:
  type: project
---

Implemented Tasks 6-8 of `docs/superpowers/plans/2026-09-05-codex-review-gate-deep-refactor.md`
(ADR-0193) in `staging/plugin/skills/deep-refactor/SKILL.md` only: Gate 0-CDX subsection, the
IF/ELSE wrap of both dispatch branches under `### Dispatch model`, and Gate 1's per-dimension
engine-attribution block. Tasks 1-5 (the `codex-audit-mode.test.sh` harness itself and
`codex-reviewer.sh`'s `--mode audit`) were already on disk before this dispatch — read the test
file first; it tells you exactly what string, at what count, in what scope.

**CX21 is an exact-count-of-1 check across the WHOLE file, not just the touched section.** The four
frozen literals (`model: "opus", effort: "high"`, `inherit the session`,
`Dispatch the 4 reviewer agents sequentially using the`, the `dispatch-site:` marker) are checked
with `flat_count(SKILL_TEXT, needle) == 1` each — `SKILL_TEXT` is the entire file, not the dispatch
block. The plan's own Task 7 prose asks the new `IF USE_CODEX_AUDIT = true` halves to state that
the Codex-fallback pins `model`/`effort` "exactly as the ELSE branch pins them" — writing that as
the literal quoted string a second time would silently break CX21 (count becomes 2, not 1). Paraphrase
instead: refer to the pin without repeating the quoted `"opus"`/`"high"` substring (I used
`` `model` and `effort` ... exactly as the ELSE branch below does (`opus` / `high`) `` — no matching
substring). Before adding a second occurrence of any "frozen literal" string named in a plan or ADR,
grep the whole target file for it first, not just the section you're editing.

**CX20 scopes to one section only, via awk between two heading anchors**
(`/^### Dispatch model$/` through the next `/^### /`), so it does NOT see Gate 0-CDX or Gate 1 —
only content physically inside `### Dispatch model` counts toward its exact-2 checks
(`codex-reviewer.sh --mode audit --dimension` and `USE_CODEX_AUDIT = true`, each exactly twice, one
per branch). Read the test's awk/grep extraction logic before assuming a check is file-wide or
section-scoped — they differ per assertion in this file (CX20 section-scoped, CX21/23/24 file-wide,
CX22 position-anchored between two other headings via line-number comparison at runtime, never a
hardcoded line number per rule 12).

**CX23 is case-sensitive and lowercase-only.** It checks `flat_count(SKILL_TEXT, "with no
manifest")` (lowercase "with"). A sentence starting a paragraph with capitalized "With no manifest
present..." will NOT match — `flat_count` is `grep -F` with no `-i`. Write the clause mid-sentence
("...; with no manifest present, ...") to keep the lowercase "with".

**Heading/label style in this file for a conditional split is bold text, not a markdown heading.**
`**Branch A — ...:**` / `**Branch B — ...:**` are bold paragraph labels, not `###` headings. I
followed suit with **IF `USE_CODEX_AUDIT = true`:** / **ELSE (`USE_CODEX_AUDIT = false` — today's
behaviour):** — also bold text, not `####` or `###`. This matters mechanically, not just
stylistically: CX20's awk terminates its capture on the next line matching `^###` followed by a
space, so introducing a real
`###` heading anywhere inside the Branch A/B content would truncate or split `DISPATCH_BLOCK` and
break the exact-2 counts.

**This file's shell-fence convention is ` ```sh `, always at column 0, never indented inside a
bullet unless the surrounding list item is itself indented (see the existing Phase-2 per-finding
loop, which uses 2-space-indented ` ```sh `).** Zero ` ```bash ` fences exist here and none should be
added — that would pull in `fence-contract-coverage.test.sh`'s population and an obligation for a
`<!-- fence-contract: ... -->` marker plus an executing test, which this plan explicitly did not
ask for (ADR-0193's own Consequences section calls this out as a stated boundary, not an oversight).
I added two new ` ```sh ` fences (one per branch, both column-0) for the
`codex-reviewer.sh --mode audit --dimension ...` illustration; verify count before/after with
`grep -c '^```sh$'` / `^```bash$'` rather than trusting the plan's own snapshot numbers (rule 13 —
re-derive, they can drift).

**AskUserQuestion blocks in this file use a plain, untagged ` ``` ` fence, not ` ```sh `.** Gate 0,
Gate 0-CDX and Gate 1 all use bare triple-backtick fences for the pseudo-YAML `AskUserQuestion:
question: | ...` block — it is not real executable shell, so tagging it `sh` would be wrong.

**`git diff --stat` is a fast, free way to confirm a "cut-and-paste, not a rewrite" instruction was
actually honored.** After wrapping Branch A/B in IF/ELSE (moving the original text into the ELSE
half unmodified), `git diff --stat` on the file showed insertions-only, zero deletions — proof the
original lines were preserved as pure context rather than deleted-and-retyped, which is the
strongest cheap signal that no reflow/rewrap/typo-fix crept in per the plan's "byte-for-byte" order.

**Where to look for expected exact-string test needles when a plan is vague on wording:** the plan
prose (`docs/superpowers/plans/...md`) states requirements narratively; the actual `.test.sh` file
(when it already exists, per Task 1's tests-first ordering) has the literal `flat_count`/`flat_has`
calls with the exact needle strings, the exact scope (whole file vs. section-extracted), and the
exact comparison (`>= 1` vs `-eq N`). Read the test file's assertions directly rather than
reverse-engineering wording from the plan's English description — the plan and the test can differ
in surface wording (e.g. plan says "the value is inherited from `use_codex_review`", the actual
CX23 check just wants three independent substrings present somewhere, not that exact clause).
