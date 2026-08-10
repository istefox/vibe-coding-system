# SPEC — Skill fences rely on word splitting under zsh (issue #394)

**Topic slug:** 394-skill-fences-rely-on-word-splitting

## Objective

Make the shell that **executes** a bash fence in a `SKILL.md` the same shell the fence was
**written and tested for**, so a fence's executed behaviour cannot diverge from its read behaviour.

This is the same failure shape as issue #385, reached by a different route. There, the renderer
substituted arguments into a fence before the model saw it. Here, the fence text is intact and the
interpreter is not the one its author assumed.

## Measured facts (2026-08-09, this machine)

Everything below was measured by execution, not by reading. All of it is build- and
host-stamped: zsh 5.9, macOS, CC 2.1.226.

- **The host shell that executes fences is zsh 5.9.** zsh does not word-split unquoted parameter
  expansions. `bash "$_sap" $_args` passes **one** argument under zsh and **four** under bash;
  `set -- $_args` behaves identically.
- **The harness executes extracted fences under `bash`.** So the fence tests are green while the
  live path is broken, and no test that reads a file can observe this.
- **At least six word-split sites**, in two skills: `autopilot/SKILL.md` lines 467 and 598,
  `commit/SKILL.md` lines 104, 237 and 489, plus the Phase S invocation that opened the issue.
  The scanner that produced the first five matches `for X in $VAR` and `set -- $VAR` and **does
  not match `cmd $VAR`** — the shape of #394 itself — so the population is a floor, not a count.
- **A second divergence is already observed:** zsh's `nomatch` makes an unmatched glob fail the
  command instead of passing the pattern through. Seen twice in one evening. How many further
  divergences exist is unmeasured.
- **32 `fence-contract` markers and 1 `fence-illustration`** across staged `SKILL.md` files.
  ADR-0107 recorded 18 declarations; the population grows, so it must be re-derived and never
  cited from a prior document.
- **Both `autopilot` sites sit inside declared contracts** (`autopilot-check-6`,
  `autopilot-scope-resolve`). **The `commit` sites at lines 104 and 237 have no marker above
  them** and are outside every declared population, including the guard's.
- **Failure directions differ.** The five loop sites fail **closed** — wrong, loud, diagnosable.
  The Phase S site fails **open**: the `--features` bound is discarded and the run proceeds
  unbounded over every pending roadmap row.
- **The defect predates #385.** The pre-#385 form was `set -- $_args`, which fails the same way,
  so the `--features` bound has never been applied on this machine, from ADR-0129's first run
  onward.

## Scope

**In scope**

- Auditing the zsh/bash divergence class across every bash fence in staged `SKILL.md` files, and
  recording the resulting count and per-class breakdown as a measurement rather than an estimate.
- Making every fence in the chosen population execute its body under `bash`, independent of the
  host shell.
- Bringing the measured-defective but undeclared `commit` fences into the declared population, so
  they are covered by the guard rather than sitting outside it.
- A stdout-and-exit-code-only contract for wrapped fences, and the refactor of any block that
  currently binds a variable read later in its step.
- A structural guard that asserts the wrapper is present, derived at run time.
- Live verification on the host shell, plus an end-to-end acceptance of the original symptom.

**Out of scope, stated so it is a decision rather than an omission**

- Changing the host shell. It comes from the user's profile, zsh is the macOS default, and
  changing it would fix this machine while leaving every other one broken.
- `scripts/*.sh` helper files. They carry a bash shebang and are never subject to the host shell —
  that property is what ADR-0132 relied on and it is unaffected here.
- Illustration fences that nothing executes, unless the audit measures one as divergent.
- Issue #355 (the plant registry's prefix match). Adjacent, separately filed, untouched here.
- Building a per-idiom scanner as the enforcement mechanism. It is used to **measure**; it is not
  the guard, because a per-idiom guard inherits the blind spots of whoever enumerates the idioms.

## Stack

Shell: bash 3.2 (the macOS system bash the scripts target) and zsh 5.9 (the host shell that
executes fences). Portability rules unchanged: BSD `sed`/`awk`, no GNU-only flags. Documents are
markdown `SKILL.md` under `staging/plugin/skills/`. Tests are hermetic bash files under
`staging/plugin/scripts/tests/`, enumerated by name in `.github/workflows/docs-ci.yml` and run on
`ubuntu-latest`.

## Architecture

Five parts, in dependency order.

**1 — Audit.** Enumerate the divergence class across all staged `SKILL.md` bash fences: word
splitting, `nomatch` globs, and whatever else the sweep surfaces. The output is a count with a
per-class breakdown and a per-site list, and it is what fixes the population. The sweep must
declare its own blind spots explicitly; a sweep whose limits are unstated reads as complete.

**2 — Wrapper.** Every fence in the population executes its body under `bash` rather than under
whatever shell the harness happens to invoke. This removes the **class**, not the instances: word
splitting, `nomatch` and any future divergence stop applying together, and the executed shell
returns to being the tested shell. The exact form is the architect's decision; it must preserve
exit codes, must pass stderr through unchanged, must keep the orchestrator's textual variable
substitution working, and must not introduce a positional-parameter token (ADR-0132).

**3 — Population.** Declared fence contracts, plus every fence the audit measures as divergent
whether declared or not. The `commit` sites acquire markers so they enter the guard's population
instead of being repaired once and left unguarded.

**4 — Contract.** A wrapped fence communicates only through stdout tokens and its exit code. Most
declared contracts already do. A block that binds a variable consumed later in its step is
rewritten to print it, which also removes an implicit inter-block dependency that nothing
currently documents.

**5 — Guard.** A structural assertion that every fence in the population carries the wrapper. It
is deliberately **not** an idiom scan: if the wrapper is present the interpreter is bash and the
question is closed regardless of the construct, so the guard has no per-idiom blind spot. Because
a structural check proves a shape and not a behaviour, it is paired with at least one **executed**
proof under the host shell.

## Data model

No persistent data. The vocabulary this feature touches is the fence marker set already in use:
`<!-- fence-contract: <id> -->` and `<!-- fence-illustration: <reason> -->`. Whether the wrapper
needs a declaration of its own, or whether its presence in the body is its own evidence, is an
architecture decision. If a new marker is introduced it follows the existing conventions: one
line, reason of at least 40 characters where a reason applies, and a derived guard rather than a
list held inside a test.

## API and interfaces

- **Per-fence exit codes and stdout tokens are the interface, and they do not change.** Callers
  branch on them today: `PREFLIGHT_CLEAN`, `SCOPE-PARSE:`, `COLLAPSED`, `BASELINE_OK` and the
  rest. Exit 3 keeps meaning *the check did not run*, distinct from *the check found nothing*.
- **The wrapper is an implementation detail of the fence**, invisible to every caller.
- **The guard is a checker**: it branches on an exit code, prints no `CLEAN` sentinel, and
  distinguishes "did not run" from "found nothing". It is placed where it cannot be deployed —
  outside `PAIRS`, outside the `.test.sh` glob if it is a standalone checker — so this feature
  adds no inert-until-sync failure mode of its own.

## UI flows

None. The operator-visible change is behavioural: gates that silently discarded their arguments
now honour them, and a run bounded by `--features` is actually bounded. The first run after this
lands may therefore look different from every previous run, and that difference is the fix, not a
regression.

## Edge cases

- A fence whose body contains the wrapper's own delimiter, or a nested heredoc.
- A fence that binds a variable read later in the step — the contract case above.
- The single `fence-illustration`, which deliberately does not parse as bash.
- Fences that are already shell-agnostic: they must not change behaviour, and ideally not change
  at all beyond the wrapper.
- `zsh` availability on the CI runner is **unverified**. If a differential check is ever added it
  must not become a silently skipped CI-dark test, the class ADR-0032 named.
- The wrapper must not break `fence-contract-coverage.test.sh`'s extraction, which anchors on the
  marker rather than the body, nor `plant-check.sh`'s sandbox, which copies only `staging/` and
  `docs/`.
- Stderr must still reach the caller: several fences print their remediation there.
- A wrapped body runs in a separate process, so a fence that changes the caller's working
  directory or environment cannot do so any more — any such fence must be found by the audit
  rather than discovered at runtime.
- ADR-0132's rule holds throughout: no positional-parameter token may appear in a fence body.

## Success criteria

- [ ] R-01 — The zsh/bash divergence class is measured across every bash fence in staged
      `SKILL.md` files, and the total, the per-class breakdown and the per-site list are recorded
      in the ADR, together with the sweep's own declared blind spots.
- [ ] R-02 — Every fence in the population executes its body under `bash` regardless of the shell
      that invokes it, verified by execution and not by inspection.
- [ ] R-03 — The population is the declared fence contracts together with every fence the audit
      measures as divergent; the defective `commit` fences carry markers and are inside the
      guard's population.
- [ ] R-04 — A wrapped fence communicates only through stdout tokens and its exit code, and no
      fence in the population binds a variable that is read later in its step.
- [ ] R-05 — A structural guard asserts that every fence in the population carries the wrapper,
      derives its population at run time rather than from a list, and count-guards its denominator
      so a glob that stops resolving fails loudly instead of reading as full coverage.
- [ ] R-06 — The guard runs in CI, named explicitly in `.github/workflows/docs-ci.yml`, and its
      assertions carry declared plants that are observed to fire.
- [ ] R-07 — At least one wrapped fence is executed live on the host shell and its stdout token
      and exit code are compared against the expected values, with the result recorded in the ADR.
- [ ] R-08 — `autopilot --features 1 --only 293 --dry-run` resolves `source=arguments`,
      `features=1` and exactly one roadmap row, demonstrating end to end that the symptom that
      opened the issue is gone.
- [ ] R-09 — Every wrapped fence's exit codes and stdout tokens are unchanged from before this
      feature, so no caller's branching is altered.
- [ ] R-10 — No positional-parameter token is introduced into any fence body, and the existing
      ADR-0132 guard stays green.
- [ ] R-11 — The ADR records that the defect predates issue #385 and that the `--features` bound
      has never been applied on this machine, so any prior claim that a run was bounded is read
      against that fact.
- [ ] R-12 — A fence that is genuinely shell-agnostic and outside the population is left
      unmodified, and the ADR states the boundary rather than leaving it implicit.
- [ ] R-13 — This feature introduces no new inert-until-sync failure mode: either the guard is
      placed outside every deployment path, or its dependency is stated and fails closed with the
      sync remedy printed.
