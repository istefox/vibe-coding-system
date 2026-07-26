# ADR-0053 — Interface immutability gate

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #107 (eighth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/107-interface-immutability-gate.spec.md`
- **Builds on:** ADR-0052 (#106) §D5, which named advisory accumulation as the live risk. This
  feature is the answer to it, not another instance of it — see §D2.
- **Closes:** gap **G-10** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (ABSENT, P2).

## Context

The agentic spec ranks interface immutability **first** in its outer-loop Prevent ordering, on the
grounds that API breakage "alienates customers and destroys trust". Its documented incident: an
agent bypassed every interface, changed function arguments, created "scores of new entry points"
and renamed dictionary keys. The fix-forward attempt cost over two hours; a rollback plus one added
prompt phrase won in ten minutes.

Nothing in this system declares a protected interface. `goal-loop/SKILL.md:59` offers "public API"
as free-text prose inside a prompt template. `agent-write-scope.sh` and `write-scope-enforce.sh`
restrict **paths**, never signatures — an agent confined to exactly the right file can still delete
exactly the wrong function.

## Decision

### D1 — An optional `.claude/protected-interfaces` file, inert when absent

One entry per line: an exact signature or a path glob, `#` comments allowed. **Absent file means
allow-and-exit** — the same inert-by-construction design that keeps `write-scope-enforce.sh`
harmless outside its one call site, and that ADR-0052 §D1 used for budgets.

Inertness is what makes §D2 defensible. A project is only ever blocked by a protection it declared
itself.

### D2 — This check BLOCKS, and that is the point

ADR-0052 §D5 named the trajectory: six advisory arrays in `step5-report.json`, three added in three
consecutive features, each justified by "blocking would be too noisy, so surface instead". Adding a
seventh advisory here would be the default path and would confirm the trend rather than answer it.

The reason this one can block is **evidence quality**, the same axis ADR-0051 §D2 used to keep
`SUSPECT` out of `WEAKENED`:

- `suspect_findings` and `budget_findings` are heuristics. A literal-valued assertion *might* be a
  cardboard muffin; a 300-line diff against a 200-line budget *might* be scope creep. Both need a
  human to judge.
- **A protected signature is either still present or it is not.** That is mechanical. There is no
  judgment call, and the only false-positive class is "the operator declared something they did not
  mean to protect" — which is a one-line edit to a file they own.

This is exactly the argument ADR-0048 §D7 used to let `spec-coverage.sh` block where #100's
reporters do not. Same shape, same conclusion: mechanical facts may gate; heuristics may not.

### D3 — Checker semantics, not reporter semantics

`interface-check.sh` signals through its **exit code**: 0 = no protected interface broken, 3 = one
or more broken, 2 = bad invocation. The caller branches on the exit code.

This makes it the third script in the same directory family with the third distinct contract, and
that is now a genuine hazard rather than a theoretical one:

| script | contract | caller idiom |
|---|---|---|
| `weakening-scan.sh` | reporter | grep stdout for `^WEAKENED` |
| `diff-budget-check.sh` | reporter | grep stdout, `CLEAN` sentinel |
| `spec-coverage.sh` | checker | branch on exit code |
| `interface-check.sh` | **checker** | branch on exit code |

The call site must state which one it is, as ADR-0048 §D7 required and ADR-0052 repeated. Copying
one neighbour's idiom into another is the recurring bug in this family, and it has now been written
down three times, which is itself evidence that prose is not fixing it. Recorded as a residual.

### D4 — Signature comparison is textual and deliberately shallow

The check compares declaration lines in the diff against the declared entries. It does **not** parse
languages, build ASTs, or resolve types — ADR-0039 §D4's determinism rule applies: a verdict that
depends on which parser is installed is not a verdict.

Consequences, stated rather than discovered later: a signature changed by editing a default argument
on a continuation line may be missed, and a pure reformat of a protected declaration may be flagged.
The first is a miss, the second is a one-line file edit. Both acceptable at this depth; a deeper
check needs its own decision.

### D5 — Two call sites: c2c Step 6, and standalone for CI

Step 6, before the review closes — after the code exists, before it is accepted. Also exposed
standalone so a project's CI can call it directly, which is how it reaches repos that never run the
chain.

### D6 — The architect populates the file at Gate 2, and never silently

When the plan touches a public surface, the architect proposes entries. It proposes; it does not
write them unannounced. A protection the operator did not knowingly declare is a block they will not
understand, and §D2's whole defence is that you are only blocked by what you declared.

## Alternatives rejected

- **A1 — Make it advisory like the last three features.** Rejected under §D2. This is the
  alternative the last three features would have chosen by default.
- **A2 — Parse signatures properly with a language-aware parser.** Rejected under §D4: reintroduces
  the tool-dependence ADR-0039 removed, and the shallow check catches the documented incident
  (deleted entry points, renamed keys) without it.
- **A3 — Derive protected interfaces automatically from exported symbols.** Rejected: it would
  protect everything, so it would block constantly, so it would be disabled. Opt-in is what makes a
  blocking gate survivable.
- **A4 — Reuse `weakening-scan.sh`'s reporter shape for consistency with its neighbours.** Rejected
  under §D2 — consistency of *contract* is not worth losing the blocking behaviour, which is the
  entire value here.

## Consequences

### Positive

- The spec's first-ranked Prevent gate exists, and it actually stops the failure instead of
  reporting it afterwards.
- It breaks the advisory-accumulation trend ADR-0052 §D5 named, rather than extending it.
- Inert-by-default means zero migration and zero effect on every existing project.

### Negative, stated plainly

- **A fourth contract in a four-script family**, split 2 reporters / 2 checkers with no naming
  convention distinguishing them. §D3 documents it; nothing enforces it. This is a real trap for the
  next person and deserves its own issue.
- **Shallow textual matching** (§D4) both misses and over-fires in known ways.
- **Inert until someone writes the file** — like ADR-0052 §D1, the feature's value arrives after its
  merge, when projects actually declare interfaces. §D6's architect proposal is what makes that
  likely rather than theoretical.
- Blocking on a declared-but-unmeant entry is possible. The remedy is a one-line edit to a file the
  operator owns, which is why this is acceptable here and would not be for a heuristic.
