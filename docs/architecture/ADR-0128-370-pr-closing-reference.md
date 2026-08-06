# ADR-0128 — an unattended PR closes the issue it implements

- **Status:** Accepted
- **Date:** 2026-08-06
- **Issues:** #370 (ledger `VCS-007`) — plus one defect in the plant registry found while writing
  this feature's own assertions
- **Amends:** ADR-0022 §D6 (`publish-feature.sh`'s PR body), ADR-0108 (the plant registry's
  attribution rule)
- **Files:** `staging/plugin/scripts/publish-feature.sh`,
  `staging/plugin/skills/project-conductor/SKILL.md`,
  `staging/plugin/scripts/tests/phase1.test.sh`, `staging/plugin/scripts/tests/plant-check.sh`

## Context

`publish-feature.sh` opened every unattended PR with a **fixed inline body string**. It carried no
closing reference, so a feature's issue stayed open after its PR merged. Observed on the
2026-08-04 run: PR #362 implemented issue #292, and #292 closed only because the body was edited by
hand before the merge.

The failure is quiet in the way this repository keeps recording. A PR that merges and leaves its
issue open looks exactly like a PR for work that had no issue — which is a legitimate, common
state. Nothing distinguishes them, so nothing reports one.

## The measurement

Two sources could supply the number, and only one of them survives contact with the data.

| candidate source | verdict |
|---|---|
| `docs/specs/_issue-map.tsv` | **rejected.** Its slug is `<N>-<slugified-title>`; `$SLUG` here is the *manifest topic*, a slugified title truncated to 40 characters with no number prefix. Matching one against the other is a fuzzy match between two names that agree only by convention — the shape ADR-0096 measured as wrong on 38 of 41 inputs while looking correct. |
| `PROJECT.md`'s own line | **accepted.** `roadmap-from-issues.sh` writes `- [ ] <title>  (issue #N)`, and `project-conductor` reads that exact line to pick the feature. The number is already in the caller's hand. |

## Decisions

### D1 — the number is an ARGUMENT, never re-derived

`publish-feature.sh` gains `--issue <N>`. It does not look the number up, and the reason is written
at the parse site rather than here, because that is where the next author stands. This is
ADR-0096's rule applied a second time: **detect upstream where the value is known, pass it down;
a consumer that re-derives a value can disagree with the producer about what it means.**

Absent, the body is byte-identical to what it was before the flag existed. A roadmap not generated
from issues legitimately has no number, and that case stays **silent** — not a warning, because a
warning that fires on every correct run is one people learn to skip.

### D2 — the caller captures the number BEFORE the checkbox flip

`project-conductor` Step 5A flips `- [ ]` to `- [x] <title>  (completed: <date>)`. That rewrite can
carry the `(issue #N)` marker away with it, so reading the number afterwards can find nothing on a
roadmap that has one. The capture is now the **first** action in branch A, above the flip, and
`CR9` asserts the ordering rather than the presence of both lines — both can exist and the feature
still be broken.

An empty result has two causes and only one is fine. A roadmap with **no** issue markers anywhere is
the silent case; a roadmap carrying them that yielded none for *this* feature is an extraction that
did not work, and prints a note. Same distinction as everywhere else in this system: a check that
found nothing must not read like a check that could not look.

### D3 — the dry run PRINTS the body, on stderr

The body is built into `PR_BODY` before the `gh pr create` call so the dry run can show it. This is
why the defect survived every offline test the script has: **a dry run that hides the body verifies
nothing about the body**, and `phase1.test.sh` had exercised this code path since ADR-0022 without
ever being able to see what it would send.

stderr, never stdout — stdout carries the `AUTOPILOT-PUBLISH` status line that the `/goal` evaluator
and the morning report parse, and a body written there would corrupt both silently. `CR2` pins it.

### D4 — the plant registry could not attribute a plant in this harness, and now says so

Found while writing this feature's assertions, not by reading. `plant-check.sh` decides a plant
fired with `grep "^FAIL: <id>"`. **Five harnesses print `FAIL <label>` with no colon** —
`external-dependency-gate`, `hook-probe`, `hook-verify-workflow`, `phase1`, `prep` — so a plant
declared in any of them can never be seen to fire: the grep finds nothing whether the assertion
held or collapsed, and the run reports *"the assertion still passed with the mechanism removed"*.

**A definite verdict from a check that could not look** — this file's own subject, one level up. It
is now a `BADPLANT` (the registry could not run) and never a `NOFIRE` (the assertion pins nothing),
and the needle is the **emitter**, not the string, so a comment mentioning the prefix cannot excuse
a harness that does not print it.

None of the five had ever declared a plant, which is why nobody had hit it. `phase1.test.sh` is
aligned to the colon form here because this feature needs plants in it; **the other four are left
as they are and are named in the guard's own comment.** Converting them is a separate change with
no assertion behind it today.

**Running the guard corrected it twice, and neither defect was visible by reading it.** The check
was verified in both directions on an isolated tree carrying exactly one declaration — a plant in
`prep.test.sh` (rejected as unattributable, `PC1` still green) and the same plant in
`phase1.test.sh` (run, fired, `PC2` green). That run showed:

- **The guard sat downstream of the machinery it declares unusable.** It ran after the sandbox copy
  and after the mutation had been written, so a plant that could never be attributed still paid for
  a full tree copy and a source rewrite. It now runs against the real file immediately after the
  field parse, before any sandbox exists.
- **`PC1` printed `1 run` for a run in which nothing ran.** `RUN_N` names the sandbox directory, so
  it must advance even for a rejected declaration; it was also being reported as the number of
  plants executed. A count that does not track its population has stopped measuring — this file's
  own subject, in this file, in the change that added the guard. Split into `RUN_N` (declarations)
  and `RAN_N` (executions), and `PC1` now reads `<RAN_N> of <RUN_N> declarations run`.

The three other failures that run produced — `PC0`, `PC3` and `Z1` — are the denominator guards
working: a collector finding one declaration is reported as **broken**, never as clean.

### D5 — a malformed `--issue` is a hard fail, not a warning

A non-zero exit here **stops the whole roadmap** — `project-conductor` Step 5A treats a publish
failure as run-level. That is a heavy consequence, and it is still the right one: the only caller
passes this after extracting digits from a line it just read, so a malformed value cannot come from
the intended path. It is a defect in that extraction, and a broken extraction breaks for **every**
feature. Halting on the first beats opening twelve PRs that all silently close nothing.

### D6 — `--issue` is passed unconditionally, empty value and all

Never `${_issue:+--issue $_issue}`. That idiom relies on word splitting to become two arguments, and
**this shell may be zsh, where an unquoted expansion does not split** (issue #366) — flag and value
would arrive as one argument and the parse would fail. An empty `--issue` is *defined* to mean "no
closing reference", so the empty case is a reachable, tested input rather than an edge case.

### D7 — the body's "overnight" wording is corrected in the same edit

ADR-0127 repositioned this runner away from the overnight frame; the PR body still said
`Automated overnight run`. One line, in the block already being changed, in a string a human reads
on every PR. Recorded as a deliberate widening of scope rather than left to a cleanup nobody
returns for. Nothing asserted the old string (measured: one occurrence, no test).

## Consequences

- **Nine assertions, six planted.** `CR4` is **unplantable** in registry v1 — removing the blank
  line before the reference needs a replacement containing a newline, which the declaration syntax
  cannot express (ADR-0112). `CR5` and `CR6` are **negative**, and deleting a mechanism cannot
  break "X must not happen"; inverting them means flipping the body's `[ -n "$ISSUE" ]` guard,
  whose needle is not unique in the file. `CR3` is their positive twin and is planted, which is
  what stops the pair going green against a body that never appends anything.
- **This closes issues on merge, and only on merge into the default branch.** Every feature PR
  targets `main` (ADR-0127 §D4), which is what makes the keyword effective; a prep PR closes
  nothing and passes no `--issue`. If `--base` ever stops being `main`, this feature stops working
  and nothing will report it.
- **The four remaining colon-less harnesses are still outside plant attribution.** They now fail
  loudly if anyone declares a plant in them, rather than lying — but they are not fixed, and a
  green `plant-check.sh` says nothing about assertions in those files.
- **Inert until sync.** `publish-feature.sh` is deployed through `PAIRS`; the conductor's SKILL.md
  likewise. Until then the deployed copy opens PRs with the old body.
- The note on a failed extraction goes to stderr in an unattended run, where it reaches the
  transcript and the report but nothing acts on it. It is a disclosure, not a gate.
