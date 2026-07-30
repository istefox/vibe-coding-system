# ADR-0086 — The derived-guard pattern stays six copies, and the reason is a criterion

- **Status:** Accepted
- **Date:** 2026-07-30
- **Issues:** none (roadmap item 6.5, first point — the question PROJECT.md deferred until the call
  sites existed)
- **Related:** ADR-0069 (the extraction that WAS right, and the precedent this looks like),
  ADR-0077, ADR-0082, ADR-0083, ADR-0084, ADR-0085 (the six instances)

## Context

Six test files now derive a population at run time, let a file **declare its own waiver** instead of
keeping an exemption list in the test, and guard the derivation with a count. PROJECT.md deferred
one question until they existed: **is that one helper, or N deliberate copies?** Either answer is
acceptable; an unasked question is not.

The question deserves care because this repository has an extraction precedent that appears to
settle it. ADR-0069 pulled `plan-task-predicate.awk` out of three consumers with an argument that
reads as general: *making three files agree would have left three answers that agree today; this
leaves one file that decides.*

## Decision

**Six deliberate copies. No shared helper, no shared source file.** Each instance names itself in
its own header and points here.

### D1 — The criterion, and why ADR-0069 does not apply

The test is: **would two copies giving different answers be a defect?**

For the plan-task predicate, emphatically yes. The three consumers were asking **one** question — is
this line a task? — and got three answers. That is the definition of drift, and it had already
produced issue #172.

The six guards do not ask one question. They ask six, about six populations:

| instance | population unit | count guards |
|---|---|---|
| `transcript-scan-rule` | files, filtered by content | `>= 8` matched, `>= 20` candidates |
| `fence-contract-coverage` | fenced blocks **inside** a file | `>= 100`, `>= 37`, `>= 10`, `>= 1` |
| `cross-reference-form` | token occurrences inside a file | `>= 100`, `>= 15`, `>= 5` |
| `skill-coverage-perimeter` | directories, verified against another tree | `>= 25`, `>= 1`, `>= 2` |
| `skill-text-corrections` F6 | names parsed from one prose line | `>= 5` |
| `agent-command-scope` J | names parsed from a `case` arm | `>= 2`, `>= 4`, `>= 4` |

There is no shared answer that could diverge. `8`, `25`, `100` and `2` are legitimately different
numbers about legitimately different things, and the 40-character reason floor is a convention
rather than a fact. Unifying them would not correct anything; it would make identical what is
already correct while different.

### D2 — Two differences a single helper cannot reconcile

**The marker's relationship to the extractor is OPPOSITE in two instances.**
`fence-contract-coverage`'s marker **is** the extraction anchor and must be found (ADR-0083 §D3).
`cross-reference-form`'s marker must be **excluded** from extraction, or a declaration satisfies
itself: the line naming the exempt tokens contains those tokens, so a waiver covering nothing would
read as live — the reason `cross-reference-form.test.sh`'s header states *"The extractor SKIPS
`xref-exempt:` lines. Without that, a declaration would satisfy itself"*. Same field, two
contradictory requirements.

**The marker's syntax follows the file's language, not the pattern.** Shell comment in the two
hook-facing guards, HTML comment in the two markdown-facing ones. The payload differs too: reason
only, reason plus an id, reason plus a token list. And one instance constrains **position** (within
three lines of the frontmatter close) while the others accept the marker anywhere.

A shared helper would need parameters for population kind, marker syntax, payload semantics,
marker-versus-extractor relationship, position constraint and reverse-check shape. Six parameters
for six callers is not a helper; it is a configuration file with an extra indirection. What is
genuinely common underneath is the count-guard idiom (three lines) and the reason floor (one).

### D3 — Correlated failure is worse than duplication, for guards specifically

Every one of these files is hermetic and independently runnable by design — each header carries
`Run: bash <file>`, and `docs-ci.yml` invokes them one by one. A shared source introduces a failure
mode that does not exist today, and for a set of guards that mode is the expensive one: six
independent checks are worth having **because they fail independently**. A defect in the shared file
disables all six at once, and this repository has watched that exact shape three times (ADR-0081's
false green, ADR-0043's direction, ADR-0083's vanished assertions) — a guard that stops guarding
while staying green.

### D4 — What is extracted is the RULE, and it goes where the seventh author will be

The seventh instance will be written by copying one of the six. So the decision is recorded in each
of the six headers, one line naming the instance and pointing here, rather than in a document
nobody opens while copying a file.

No test asserts that those lines exist. An assertion that a comment is present is ceremony: it
cannot be seen meaningfully RED, it prevents no defect beyond a missing comment, and it would
literally be the seventh instance of the pattern under review.

## Consequences

- **The count-guard idiom and the 40-character floor stay duplicated six times.** That is the price,
  stated plainly: four lines per instance, and nothing stops one of them drifting to 30 characters.
  What is claimed is that such a drift is not a defect, not that it cannot happen.
- **The criterion is the reusable part, not the verdict.** If a future pattern has six callers
  answering ONE question, D1 says extract it, and ADR-0069 is the worked example.
- **This decision has no enforcement**, by choice (D4). A seventh copy that skips the header note is
  invisible. The alternative — a population guard over the marker — was considered and rejected as
  the pattern applied to itself.
- **The instance count is a snapshot.** Six on 2026-07-30, re-derived from the files rather than from
  PROJECT.md, which said four and named the wrong four.
