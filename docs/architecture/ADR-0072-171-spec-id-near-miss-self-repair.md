# ADR-0072 — The coverage gate detects the near-miss and repairs it, instead of blocking

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #171
- **Extends:** ADR-0048 (`spec-coverage.sh`), ADR-0069/ADR-0070 (the shared-predicate pattern),
  ADR-0071 (Gate 4.0, which is what makes an automatic in-place edit reversible)
- **Reported as:** a live chain failure on the first end-to-end run in an external project.

## Context

`spec-coverage.sh` ran against a SPEC declaring 17 requirements, reported nothing, and exited 0.
The requirements were written as

```
- R-01 — …
```

and the checker recognises a declaration only as the first token of a **checklist item**. A plain
bullet was examined by nothing at all: the token reached neither the declared set, nor the malformed
set, nor the out-of-section set. `DECL_N` stayed 0 and the SPEC took the documented silent no-IDs
path. The Step 5 → Step 6 gate passed vacuously.

The root cause is a contract stated on one producer path and not the other. `spec-from-issue`
carries a literal template (`- [ ] R-01 — …`); `interview-driver` carried prose in which the word
"checklist" was doing load-bearing work that nothing made visible, and there was no template at all.

## Decision

### D1 — Repair, do not regenerate, and do not block

The issue framed the open question as detect-and-fail versus ignore. Both are worse than a third
option: **detect and heal**. A chain that stops with a precise, correct command is better than one
that stops with a wrong one; a chain that applies the command itself is better still.

Regeneration was rejected outright. Re-invoking `interview-driver` means redoing the interview;
re-invoking `spec-from-issue` rebuilds from the issue and discards every human edit. In both cases
the SPEC has already passed Gate 1, so regeneration destroys an approved review.

Normalisation is safe in a way regeneration is not: `- R-01 — X` and `- [ ] R-01 — X` declare the
same requirement, and only the second is a form the checker reads. Adding the marker changes no
content. This is a **formatting repair**, and the ADR is explicit about that boundary so nothing
later grows into rewriting requirement text.

### D2 — One predicate file, two consumers, one of which writes

`spec-id-predicate.awk` holds `is_spec_section_heading()`, `is_near_miss_bullet()` and
`to_checklist_item()`. `spec-coverage.sh` loads it to detect; `spec-normalize-ids.sh` loads it to
repair. It depends on `plan-task-predicate.awk` (ADR-0069) for `heading_level()` and
`is_checklist_item()`, loaded first.

A repair keyed on a different rule than the check is the failure mode this prevents: it would either
rewrite lines the check accepts, or miss the ones it rejects. Two files rather than one because they
answer questions about different documents — one about a plan's tasks, one about a SPEC's
requirements.

### D3 — The gate applies the repair automatically and prints the diff afterwards

Not gated. The edit is mechanical, has one sensible answer, and ADR-0071's Gate 4.0 has already
committed the planning artifacts, so `git checkout -- <spec>` reverses it. **The two changes
compose: without #173's producer this would be writing to an unversioned file.**

Gating it would also be a halt on the unattended paths, where there is nobody to approve a checkbox
marker. The diff is printed under a named heading so the edit is visible after the fact rather than
invisible.

The repair runs at most once per gate invocation. If the re-run still fails, the gate stops as it
did before — the cause was something else.

### D4 — The detection is bound by the repair's reach

**Every line the checker flags as a near-miss must become a line it reads once the marker is added.**
A detection the repair cannot heal is worse than none: it reports a problem, rewrites the file, and
the gate still fails.

That invariant is what excludes a bold-wrapped id (`- **R-01** — …`). The checker's `item_text()`
strips the marker and then requires `R-` immediately, so `- [ ] **R-01**` is invisible to it too —
normalising would produce a line that still does not parse. Bold ids are a **pre-existing blind spot
of the checker in both forms**, independent of #171, and out of scope here. `RN12` pins the
exclusion so it stays a decision on record rather than a bug in waiting.

### D5 — The near-miss guard is NOT conditioned on `DECL_N`, unlike its sibling

The existing guard fires only when `DECL_N == 0`, and that narrowness is right for it: a well-formed
id outside every recognised section is evidence of a problem only if nothing was declared —
otherwise it is most likely prose elsewhere in the document.

A plain bullet **inside** a recognised requirements section has no innocent reading. The mixed SPEC
is in fact the worse case, because it is only *partially* silent: some requirements are gated and
some vanish. The first draft of this change reused the `DECL_N == 0` condition and the mixed fixture
in `RN1`–`RN4` is what caught it.

Measured cost: `RN13b` sweeps all 35 SPECs in the repository and none is affected.

### D6 — The producer template is fixed too, and both producers are pinned together

`interview-driver` gains the literal `- [ ] R-01 — …` template. `RN15` derives the check from both
producers and asserts each shows the marker, because instance-level anchoring on a single file is
what let this through in the first place (rule 9 of `.claude/context.md`).

Prevention, detection and repair are three layers, not alternatives. The repair exists for SPECs
written before the template — not as licence to skip it, and the skill says so.

## Alternatives considered

### A — Detect and block (the issue's implied default)

Rejected in favour of D1 on the operator's own argument: the best way to handle a broken chain is a
precise command that heals it and resumes, not a stop. Blocking is what the pre-existing guard does
for the sibling case, and it is the reason this issue exists as a *silent* failure rather than a
loud one — but a loud failure with a mechanical fix is a fix the machine should apply.

### B — Warn on stderr, leave the exit code alone

Rejected. A vacuous SPEC would keep passing the gate, which fixes visibility and not the defect.
This repository's own rule, learned at this exact boundary (ADR-0047 §D7, RTF breaker B): a report
nobody must act on is a report nobody reads.

### C — Fix only the producer template

Rejected as the issue itself recommends — it fixes the next SPEC and leaves the checker blind. A
hand-written SPEC, or one from a model that does not follow the template, falls into the same
silence.

### D — Widen the checker to accept plain bullets as declarations

Rejected, and ADR-0048 §D2 already argued this: the declaration rule is position-based on purpose,
and loosening it toward "any R-NN anywhere" fires on prose, including the script's own header.
Repairing the document is narrower than widening the parser, and it leaves exactly one declaration
form in circulation instead of two.

## Consequences

### Positive

- A SPEC written in the plain-bullet form is repaired and the chain continues, attended or not.
- The gate stops being satisfiable by a SPEC it cannot read.
- The mixed case — some requirements gated, some invisible — is caught, and it was the more
  dangerous of the two.
- One place decides what a requirement declaration looks like, for both the reader and the writer.

### Negative

- **A gate now edits a human-reviewed artifact without asking.** Bounded to adding a checklist
  marker inside a recognised section, reversible by `git checkout`, and printed as a diff — but it
  is a real change in what the chain is allowed to do to a SPEC, and it is the first of its kind.
- Bold-wrapped ids remain invisible to the checker in both forms (§D4). Named, tested, unfixed.
- `spec-coverage.sh` gains a second stderr sentence. Callers that match on the old wording of the
  out-of-section message are unaffected — it is unchanged — but a caller that matched on *any*
  stderr now sees a new cause.

### Neutral

- No new stdout token: the near-miss reports as `MALFORMED`, and the two causes are distinguished on
  stderr. The caller's exit-code contract is untouched.
- No manifest field, no schema bump.
- Inert until sync; two new `PAIRS` entries, pinned by `RN14` since
  `pairs-completeness.test.sh` cannot see skill `scripts/` (ADR-0043).

## References

- Issue #171, including the open question this ADR answers in §D5 and the RE-corpus constraint
- `docs/architecture/ADR-0048-102-requirement-ids-coverage.md` §D1, §D2, §D7, §D8
- `docs/architecture/ADR-0071-173-step5-preflight-producer.md` — Gate 4.0, without which the
  automatic edit would have nothing to revert to
- `staging/plugin/scripts/tests/spec-coverage.test.sh` section RN
