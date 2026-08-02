# ADR-0118: RTF's gitignore glob and this repo's own entry differ by a dash

## Status

Proposed

## Context

Issue #287. `review-triage-fix/scripts/triage-state.sh`'s `commit` path appends a glob to a
project's `.gitignore` — `${pref}.triage-fix-last-*.json` — only when `git check-ignore` reports
the state file is not already covered by some existing rule (ADR-0094 / issue #250). The issue's
premise was that this repository's own `.gitignore` carries a single entry that differs from the
script's glob "by a dash," and asked whether the two rules cover the same set.

**Measured, not assumed**, before designing anything:

```
$ grep -n 'triage-fix-last' .gitignore
7:.claude/.triage-fix-last*.json
36:.claude/.triage-fix-last-*.json
```

The repository carries **two** entries, not one — the SPEC's own correction to the issue's premise,
confirmed live. `git check-ignore -v` against concrete candidate paths:

```
$ git check-ignore -v -- ".claude/.triage-fix-last-feat_222-vendor-deployed-only-skills.json"
.gitignore:36:.claude/.triage-fix-last-*.json	.claude/.triage-fix-last-feat_222-vendor-deployed-only-skills.json

$ git check-ignore -v -- ".claude/.triage-fix-lastFOO.json"
.gitignore:7:.claude/.triage-fix-last*.json	.claude/.triage-fix-lastFOO.json
```

`git check-ignore -v` reports the **last** matching line by number when several rules match a
path — it does not enumerate every rule that matches, only the one that decides. So the first
result does not by itself prove line 7 covers nothing on its own; it only proves line 36 is the
rule git reports for a per-branch-shaped path when both lines are present. The second result
does prove something real: line 7's bare `*` independently matches a `triage-fix-last`-prefixed
name with **no** dash at all, which line 36's pattern (`.triage-fix-last-*.json`, dash required)
structurally cannot match — so line 7 is not merely "a similar rule", it is a strict *superset* of
what line 36 covers, by gitignore's own documented `*`-matches-anything-but-`/` semantics.

The strongest evidence that line 7 **alone**, with no line 36 present, already suppresses the
append for a *real, per-branch, script-produced* filename is not a new experiment — it already
exists and already passes: `triage-state-gitignore.test.sh`'s **T5** seeds a fresh fixture repo
with exactly `.claude/.triage-fix-last*.json` (line 7's literal form, no line 36) and runs a real
`triage-state.sh commit` for branch `feat_zzz`, then asserts the resulting `.gitignore` still holds
exactly one line. It does, today (`bash triage-state-gitignore.test.sh` → `PASS=18 FAIL=0`,
`T5: a broader hand-written rule (.claude/.triage-fix-last*.json) suppresses the append`). That is
the harness itself proving, via a real isolated repo and a real script invocation, that the
broader no-dash form independently covers the script's actual output.

**How line 36 got there**, reconstructed from `git log -p -- .gitignore`: line 7 has been present
since the very first commit of this repository (`ac207d5`, the initial blueprint commit — it
predates the RTF feature's implementation entirely). Line 36 was added by commit `a482dbb` (2026-07-30,
PR #251, the #222 vendor-deployed-only-skills chain dogfooding `review-triage-fix` on its own
branch), whose message says the append replaces "the branch-named path review-triage-fix appended
during this run" with "the glob `.claude/.triage-fix-last-*.json`" — i.e. a human manually swapped
a dead per-branch line for the script's own canonical glob, without checking that line 7 already
covered it. The check-ignore mechanism itself (ADR-0094) was not at fault; a human re-introduced
the exact redundant form ADR-0094's own commentary in `triage-state.sh` explicitly warns about
("this repository's own .gitignore carried `.claude/.triage-fix-last*.json` before the glob below
existed").

**No other file in `staging/` writes or expects the no-dash form.** `vibe-status/scripts/aggregate.sh`
reads a legacy flat fallback name (`.triage-fix-last.json`, no branch, no dash) and
`review-triage-fix/tests/run-tests.sh` (a `$HOME`-coupled, CI-dark legacy harness — see PRIOR AGENT
NOTES) still asserts that flat name literally — both predate the per-branch/glob design and are out
of this issue's scope. Line 7's broader pattern is the only thing that still protects that vestigial
flat name; line 36 never did (it requires a dash).

## Decision

**Resolve to one rule: keep line 7 (`.claude/.triage-fix-last*.json`), delete line 36
(`.claude/.triage-fix-last-*.json`) as the redundant duplicate, and add a one-line comment above the
survivor so a future "chore" commit does not reintroduce the narrower form.** Add a permanent
regression pin against the real, committed `.gitignore` (not a fixture) proving the count stays at
one, plus a live `check-ignore` forward guard proving the survivor still covers a realistic
per-branch name. Add one new fixture-based assertion generalizing T5-T8's "already covered" proof
from a single pre-existing rule to *multiple, differently-shaped* pre-existing rules coexisting —
the actual historical shape this repository produced — with a declared plant (ADR-0108) proving the
assertion is not vacuous. `triage-state.sh`'s own glob variable and check-ignore logic are untouched
(ADR-0094's design is out of scope and was never the defect).

The survivor is chosen for safety, not for textual symmetry with the script: line 7 is a *strict
coverage superset* of line 36 (confirmed by gitignore's `*` semantics and independently by T5's
existing pass), it predates the RTF feature by the whole life of this repository, and removing it
instead would strip protection for the vestigial flat filename two other files still reference.
Removing line 36 touches zero currently-passing pinned assertions (T2/T3/T8 pin the *script's*
glob-writing behavior on a *fresh* repo with no pre-existing rule at all, which line 7's removal or
survival does not affect).

## Alternatives considered

1. **Change `triage-state.sh`'s glob to the no-dash form, so the script itself writes the broader
   pattern going forward.** Rejected: the per-branch state-file design, including this exact glob
   string, is explicitly out of scope ("ADR-0094 keeps it"); T2/T3/T8 already pin the dash-glob as
   the script's documented output on a fresh repo, and changing it would touch those pinned
   assertions for zero behavioural gain — the check-ignore mechanism already generalizes correctly
   to *any* pre-existing covering rule, dash or not. It would also make the script itself write a
   looser pattern on every OTHER target project that has no pre-existing broad rule, an unrelated
   and unjustified widening.

2. **Keep both lines and only document the redundancy in a comment, without removing either.**
   Rejected: the SPEC's Objective 2 is explicit — "resolve the difference down to one rule …
   rather than documenting the divergence." A safe, reversible, one-line removal is available; there
   is no reason to leave a live duplicate on record as merely explained.

3. **Remove line 7 (the broad no-dash rule) and keep line 36 (the script's own canonical dash-glob)
   as the survivor**, so the repository's rule reads textually identical to the string
   `triage-state.sh` itself writes. Rejected in favor of removing line 36: line 7 is a strict
   coverage superset, proven both by gitignore's documented `*` semantics and by T5's own passing
   assertion; it predates the feature; and keeping it costs nothing while removing it would
   silently drop coverage for the vestigial flat filename `vibe-status/scripts/aggregate.sh` and
   the legacy `review-triage-fix/tests/run-tests.sh` still reference (both out of scope, but real
   dependents that would be affected). Symmetry with the script's own string is a cosmetic
   preference; superset coverage with zero collateral narrowing is not.

4. **Extend `plant-check.sh`'s sandbox with a new escape hatch so a plant can target the real
   repository-root `.gitignore` directly**, mirroring ADR-0116's `../docs/` extension for RUNBOOK
   claims. Rejected for this feature: the two new "live content" assertions (checking the real,
   already-committed `.gitignore` — see Task 1 and Task 3 of the companion plan) are not a
   re-creatable *mechanism* with a rule-12-shaped failure mode; they are direct byte-content checks
   of one specific file, exactly the shape `T12` (already in the same test file, already unplanted)
   establishes as not needing one. ADR-0086's extraction criterion — "extract only when two copies
   giving different answers would be a defect" — does not even apply here; there is nothing to
   extract, only a single narrow escape hatch to add for a single feature's two straightforward
   checks. Widening a shared, delicate registry mechanism for that is disproportionate. Deferred and
   disclosed as a known limitation (see Known consequences), not silently worked around.

## Consequences

**Positive:**
- One rule in `.gitignore`, matching the SPEC's explicit "resolve, don't document" instruction;
  superset coverage confirmed both by measured `git check-ignore -v` output and by the pre-existing,
  already-passing T5 assertion — no new coverage gap is introduced.
- A permanent regression pin (the plan's T15) catches, going forward, the exact class of mistake
  that produced the duplicate in the first place: a well-intentioned "chore" commit re-adding the
  script's own glob by hand without checking `check-ignore` first. That mistake is not hypothetical
  — it is this repository's own recorded history (commit `a482dbb`).
- A new fixture assertion (the plan's T17) generalizes the mechanism's existing proof (T5-T8: one
  pre-existing covering rule suppresses the append) to the case this repository's own history
  actually produced: *multiple, differently-shaped* pre-existing rules coexisting, with none of
  them being appended a third time.
- Zero changes to `triage-state.sh`'s logic and zero changes to any currently-passing assertion —
  T0 through T14 (and the file's existing `Z1` floor concept) are extended, not altered, per the
  anchor-preserving constraint.
- No new CI wiring is needed: the harness file is already in `docs-ci.yml`'s explicit list (T13)
  and already covered by `ci.yml`'s glob (T14); both keep passing unmodified.

**Negative:**
- The repository's `.gitignore` still does not read textually identical to `triage-state.sh`'s own
  glob variable — the "difference by a dash" persists as a literal string mismatch, resolved in
  *coverage*, not in *textual symmetry*. A comment is added at the survivor specifically so a future
  reader does not "fix" that textual mismatch by reintroducing the redundant duplicate again.
- The two live-content assertions (T15, T16 in the companion plan) carry no declared plant, per the
  T12 precedent and the disproportionate cost of widening `plant-check.sh`'s sandbox for one
  feature's two straightforward checks (Alternative 4). This is a disclosed, deliberate limitation,
  not a silent gap — and it mirrors a decision this same test file has already made once.
- The vestigial flat filename `.triage-fix-last.json` (no dash, no branch) remains referenced only
  by a legacy, `$HOME`-coupled, CI-dark test file (`review-triage-fix/tests/run-tests.sh`) and by
  `vibe-status/scripts/aggregate.sh`'s fallback read path; neither is touched here (explicitly out
  of scope), and both continue to rely on the surviving broad rule's coverage of that name — a
  pre-existing dependency, unaffected by this fix, not a new one created by it.
- The new fixture assertion's seed had to be chosen carefully, and the naive choice would have
  reproduced ADR-0094's own named mistake one level up: replaying this repository's *exact*
  historical two-line pair (the broad no-dash rule together with the literal dash-glob) as the seed
  would pass under a mutated, check-ignore-disabled implementation too, because the pre-existing
  literal-grep fallback in `triage-state.sh` recognizes the exact glob string verbatim regardless of
  whether `check-ignore` ran at all — the assertion would pin nothing. This was found by tracing
  `triage-state.sh`'s control flow rather than by a live differential run: the architect's command
  scope (ADR-0042/ADR-0045) forbids creating a scratch git repository directly, so the coder's task
  must explicitly run the declared plant and observe both the pre-mutation PASS and the
  post-mutation FAIL before considering the task done (ADR-0108's "inspect what the plant actually
  produced" discipline, ADR-0090/ADR-0104/ADR-0111/ADR-0112).

**Neutral:**
- `git check-ignore`, when more than one rule in a file matches a path, reports the **last**
  matching line by number — irrelevant to `-q`'s exit-code contract (which only cares whether *any*
  rule matches) but worth recording, since a future reader inspecting `-v` output on a repository
  with more than one covering rule should not read "line 36 matched" as "line 7 does not also
  match."
- ADR-0094's own body is not edited in place (ADR-0034 precedent: a completed ADR's illustrative
  text is a snapshot of its moment); this ADR extends its design rather than correcting it — the
  check-ignore mechanism itself was never the defect.

## References

- Issue #287 (this feature); issue #250 / ADR-0094 (the per-branch design and the check-ignore
  mechanism, unchanged here).
- ADR-0108 (the plant registry — every new assertion's plant, declared and run in the failing
  direction).
- ADR-0086 (the derived-guard extraction criterion, cited for why `plant-check.sh`'s sandbox is not
  widened for this feature).
- ADR-0116 (the `../docs/` escape-hatch precedent in `plant-check.sh`, compared against and
  declined to replicate here).
- ADR-0042 / ADR-0045 (the architect's read-only git command scope, which bounded how this ADR's
  own measurement could be verified live).
- `staging/plugin/scripts/tests/triage-state-gitignore.test.sh` (the harness extended by the
  companion plan).
- `staging/plugin/skills/review-triage-fix/scripts/triage-state.sh` (unchanged).
