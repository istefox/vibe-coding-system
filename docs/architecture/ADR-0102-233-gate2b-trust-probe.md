# ADR-0102 — A safety gate that fired with a foregone answer on every brownfield run

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #233 (found by the Phase 7 shakedown run at Gate 2b)
- **Related:** ADR-0014 (TOFU trust), ADR-0020 §D4 (trust must pre-exist, never auto-granted),
  ADR-0086 (the extraction criterion, applied to a trust probe), ADR-0096 (the previous fence
  outside `fence_is_abort_capable`'s population), ADR-0090 (the fixture was wrong, not the fence)

## Context

Gate 2b fires whenever `manifest.test_cmd_candidate` is present and not `NONE`. It had **no branch
for "this exact command is already trusted"**.

On the shakedown run the architect reported the project's existing command unchanged,
`.claude/test-cmd` was untouched, and the read-only probe the skill already documents returned
`TRUSTED`. The attended path presented the `AskUserQuestion` anyway — asking a human to authorise a
command a human had already authorised, whose SHA was already pinned. Approving re-ran
`approve-test-cmd.sh` on the same hash: a no-op.

**The mechanism existed and one path used it.** The autopilot branch at the end of the same gate
carries the probe *and* the reasoning — *"reading existing trust is not granting it"*. The attended
path never got the branch.

### Why this is worth fixing rather than tolerating

The cost is not the click. **A gate that fires with a foregone answer, every run, on every
brownfield project, is a gate people learn to approve without reading — and this is the gate that
guards arbitrary command execution.** A safety gate that cries wolf is worse than one that fires
rarely.

## Decision

### D1 — One probe, hoisted above the branch split

The probe runs once, before anything is shown, and both the attended and autopilot paths read its
result. The autopilot branch now **consumes** it instead of repeating it.

ADR-0086's criterion says extract when two copies giving different answers would be a defect, and
there is no place it applies more sharply: two copies of a trust probe is a probe that can disagree
with itself about whether a safety gate fires. Hoisting it **removes** a copy rather than adding a
third — the file had two before (Form B's resume guard and the autopilot branch's), and Form B's
stays because it is a different entry point with no Gate 2b in scope.

### D2 — `TRUSTED` skips the gate; `NOT_TRUSTED` is unchanged

On `TRUSTED`: one line, and straight to `step_3_project_memory`. On `NOT_TRUSTED`: exactly today's
gate.

### D3 — Two invariants restated at the gate, because that is where the reader deciding to skip stands

**`NEVER call approve-test-cmd.sh before the user's explicit click.`** It was in §4's TOFU rules and
in Form B, and **not inside the Gate 2b block** — found by the assertion, not by reading. A skip
branch introduced without it sitting alongside is one edit away from becoming a grant.

**The pin is on content.** If the SHA differs the gate fires even when the command *looks*
identical, because **a changed file is a new authorisation**. `G2B11` executes exactly that: edit
the file, keep the registry, and the probe must flip back to `NOT_TRUSTED`.

## Verification

15 assertions in `gate2b-trust-probe.test.sh`, plus a `Z1` floor. Harness 63/63. The probe is
**executed** against a fixture trust registry in both directions, not merely asserted to exist.

Seen RED against the unmodified tree: **8 of 15** — `G2B2`, `G2B3`, `G2B5`, `G2B6`, `G2B8`, `G2B9`,
`G2B10`, `G2B11`. `G2B1`, `G2B4`, `G2B7`, `G2B3b` and the anchors pass before and after — three of
them forward guards on invariants this must not touch.

Five planted defects, all fired:

| plant | fires |
|---|---|
| the `TRUSTED` skip removed | `G2B3` |
| the never-before-the-click invariant removed from the gate | `G2B5` |
| the content-pin sentence removed | `G2B6` |
| the probe restored as a second copy in the autopilot branch | `G2B1` |
| the probe moved below the `AskUserQuestion` | `G2B2` |

### The fixture was wrong, not the fence, and the positive twin is what showed it

`run_probe`'s first draft was `HOME="$1" sed … "$FBODY" | bash`. **An environment prefix binds to
the first command of a pipeline only**, so `sed` got the fixture `HOME` and `bash` inherited the
real one — reading this machine's actual trust registry.

`G2B9` (empty registry → `NOT_TRUSTED`) and `G2B11` (edited file → `NOT_TRUSTED`) both **passed**
against it, because the real registry happens to hold neither entry. They pinned nothing.
**`G2B10`, the positive twin, is the only thing that failed.** Rule 8 executed rather than quoted: a
negative assertion pins nothing without its positive twin, and here the twin was the whole
difference between a working fixture and a decorative one.

Same family as ADR-0090's `HOME`-redirect hazard and today's `mk_root` subshell: three fixture bugs
this week, each of which reported as a defect in correct code.

## Consequences

- **A HITL gate now fires less often.** That is the point and it is still a reduction in how much a
  human is asked to confirm. It is bounded to the case where the answer is already recorded: same
  file, same SHA, same normalised root.
- **The skip depends on the probe being correct**, and the probe is now the single point where an
  error would silently suppress the gate rather than merely annoy. `G2B9`/`G2B10`/`G2B11` execute it
  in both directions for that reason.
- **The fence is declared and `fence_is_abort_capable` cannot see it** — no literal `exit 1`/`exit 2`
  and no "abort" — so `fence-contract-coverage.test.sh` F3/F4 do not reach it, exactly as with
  ADR-0096's fence. It is executed by its own file instead. Second measured example of what sits
  outside ADR-0083's population.
- Form B's resume-path probe is untouched and remains a second copy in the file, by design: a
  different entry point, no Gate 2b in scope, and merging them would couple two paths that never run
  together.
- Inert until sync.
