# ADR-0129 — Scope and bound the autopilot run

- **Status:** Accepted
- **Date:** 2026-08-06
- **Issue:** #365
- **SPEC:** `SPEC.md` (topic slug `365-scope-and-bound-the-autopilot-run`), archived to
  `docs/specs/365-scope-and-bound-the-autopilot-run.spec.md` at Step 7.0b
- **Roadmap:** `PROJECT.md` Phase 11 Wave 1 — the only structural blocker before autopilot is the
  primary way this repository is coded
- **Supersedes in part:** ADR-0127 §D5 (the `--budget` argument), §D6 (in full), §D7 (the `[~]` +
  `skipped-features` clause), §D8 (which bound is primary)

---

## Context

`/skill autopilot` takes **no arguments**. A launch therefore attempts every unchecked row of
`PROJECT.md`, and the only brakes are the `/goal` turn budget and a human hand. Measured today:
**31 unchecked rows**, all 31 carrying an `(issue #N)` marker. (The SPEC says 33 and PROJECT.md
Phase 11 says 33; the roadmap moved between the two. Re-derive this number before citing it — that
is the third time in a month a count in a SPEC has aged before the ADR was written.)

ADR-0127 Part 4 proposed two bounds: a feature scope (`--features` / `--only`, §D5) and a token
ceiling (§D6, giving the dormant `token-budget` file the producer it never had). The token half is
removed rather than wired. Three findings, and **only the third settles it** — the first two look
like implementation gaps that could be closed with more work:

1. **The proposed producer cannot produce what the consumer reads.** §D6 accumulates `spent=` from
   `step5-report.json`'s `task_metrics`, citing ADR-0064 — whose four fields are
   `test_count_delta`, `deleted_lines`, `iteration_count` and `elapsed_wall_seconds`. No token
   count appears in any of them. The file's name and its stated source are about different
   quantities.
2. **That block does not exist anyway.** The only real `step5-report.json` on disk carries no
   `task_metrics` at all. `agent-metrics.test.sh` GA1/GA2 assert the field name appears in the
   **schema block inside SKILL.md**, never that a produced report contains it — a green schema over
   an empty report.
3. **The halt is structurally unable to do its job.** `autopilot-guard.sh` is a `PreToolUse` hook
   on `git push` / `gh pr create`, so it gets a turn only at publish — once per feature, at the
   end. A ceiling evaluated afterwards **cannot stop the feature that exceeds it, only the one
   after**. That is cumulative drift, which `--features N` already bounds deterministically and
   without a second number to reason about.

The accepted cost is stated here rather than discovered later: **there is no spend ceiling.** An
anomalous feature costs what it costs. If one is ever wanted it does not come from `task_metrics` —
the only place in this system that knows about tokens is the transcript, which `usage-report.py`
and `context-occupancy.sh` read (`input_tokens`, `output_tokens`, `cache_*`). Any future bound
starts there, is per-session rather than per-feature, and still cannot stop a feature already in
flight. Recorded so the next author does not rebuild it from the same wrong source.

### What this changes

| file | what changes |
|---|---|
| `staging/plugin/skills/autopilot/SKILL.md` | new §1.3 Phase S (argument parsing, source selection, `--dry-run` routing); Phase 0 gains **check 9** (scope resolution + the scope file); §3.3's `token-budget` claim removed and the `rtf-blocker` claim corrected; §4 gains the report `scope` block |
| `staging/plugin/skills/project-conductor/SKILL.md` | Step 2 gains the `conductor-scope-gate` fence; the Step 5 publish path documents that its `published` append **is** the delivered counter |
| `staging/plugin/scripts/autopilot-guard.sh` | the `token-budget` read removed |
| `staging/plugin/scripts/autopilot-disarm.sh` | `token-budget` leaves the cleared set; `scope` joins it, in the same change |
| `docs/RUNBOOK-autopilot.md` | turn budget restated as `N × 60` with its sample size and its new role; the `token-budget` row leaves the stuck-table |

---

## Decision

### D1 — The bound is a feature count, and it travels as a run-scoped file

`/skill autopilot [--features N] [--only <token>[,<token>]] [--dry-run]`.

`project-conductor` owns the loop — it is what finds the first `- [ ]` line and advances — so the
resolved scope has to be readable by the conductor **at every re-invocation**, not resolved once in
the runner's memory. It travels as `<root>/.claude/autopilot-state/scope`, on exactly the terms
`autopilot-state/published` already established (issue #364, ADR-0127 §D4): run-scoped, written by
the runner, read by the conductor through a declared fence, cleared by `autopilot-disarm.sh`.

**The alternative is rejected on its failure mode, not on elegance.** Threading the scope through
every `Skill(skill="project-conductor", …)` invocation means a call site that forgets to re-pass it
loses the bound **silently** — the producer/consumer class this repository has now recorded four
times (#173, #248, #319, #365 itself, in the shape of a consumer with no producer).

**File format**, `key=value`, one key per line, following the `active` marker's shape:

```
source=arguments
features=2
only=task_num extracts digits only so a lettered task collides with its sibling  (issue #293)
only=plan-tasks.sh has two modes with opposite failure directions and nothing stops a caller picking the wrong one  (issue #294)
```

An absent or empty `features=` means uncapped. **Zero `only=` lines means every row is in scope**,
never "nothing is in scope" — the fence branches on the list being empty, because the two readings
of an empty list are the difference between an unscoped run and a run that does nothing.

### D2 — The `only=` value is the EXACT roadmap line text, never a re-derived slug

The conductor derives a `topic-slug` from the feature text ("lowercase kebab, max 40 chars") in
four places. Storing a slug in the scope file would add a fifth derivation, and two derivations of
one value that disagree is ADR-0069's defect exactly. The scope file stores the **feature line's
own text**, with the leading checkbox marker stripped, and the conductor matches it against
`_feature` with `grep -qxF` — whole-line and literal, the same idiom `conductor-published-skip`
uses and for the same reason (a title that is a prefix of another must not collide).

This also composes with the conductor's existing rule that a feature title is arbitrary GitHub text
and must be matched exactly, never through a `sed` regex.

### D3 — `--only` resolves an issue number first, a topic-slug second; a derivation mismatch aborts loudly

The roadmap line `roadmap-from-issues.sh` writes is `- [ ] <title>  (issue #N)`. `--only` accepts,
in order:

1. **An issue number** (`--only 293,294`) — the primary form. It is already on the roadmap line, it
   is what a human reads on GitHub, and it is the same source `publish-feature.sh --issue` was just
   made authoritative for (issue #370, ADR-0128). Matched with the **closing parenthesis included**
   in the needle — `(issue #29)` is not a substring of `(issue #293)`, so the obvious prefix
   collision is closed by construction rather than by a length check.
2. **A full topic-slug** — for roadmaps written by hand, which carry no `(issue #N)` marker.

Form 2 needs a slug derivation inside the resolver, and that is a second derivation of a value the
conductor also derives. It is accepted here, bounded, and the bound is what makes it safe: **the
derivation is used for MATCHING ONLY, and what is stored is the exact line text (D2).** A
derivation that disagrees with the conductor's therefore cannot select the wrong feature — it can
only fail to resolve a token, which is a loud abort naming the token. The failure direction is the
whole argument.

Extracting a shared `topic-slug.sh` was considered and rejected for this feature: the conductor's
derivation is **prose, not a script**, so extracting it is a new file, four call-site rewrites and
its own regression surface — a larger change than the one being made, in service of a failure mode
that is already loud. Recorded as a known gap below rather than half-built.

**A token that resolves as neither aborts in Phase 0 pre-flight, naming the token**, before the
guard is armed and before any feature starts. On an unattended runner a typo costs a whole night;
failing fast and loudly is the safe direction and is what every other pre-flight check already
does. **A token resolving to more than one row also aborts, naming the token and the rows** — a
bound nobody wrote is worse than no bound.

### D4 — A slot is consumed by a PUBLISH, and the delivered count is derived from `published`

A feature skipped for a known contained reason — a thin issue, an unmet external dependency, a
`TERMINAL` entry state the conductor cannot route — produces no PR and consumes no slot.
`--features 2` promises **two PRs or an exhausted roadmap**, never *two rows examined*.

Stated cost: on a roadmap that skips heavily the run lasts longer than the number suggests. The
alternative — counting attempts — is predictable in cost and can deliver zero PRs while reporting
success, which reads as a broken runner.

**`delivered` is the line count of `<root>/.claude/autopilot-state/published`, not a second
counter.** That file already exists, is appended exactly once per successful publish (one writer,
`project-conductor` Step 5 branch A, pinned by `conductor-entry-failure-split.test.sh` FK7), is
run-scoped, and is cleared by the same disarm. A separate `delivered` file would be a second
producer of one fact that can disagree with the first, and there is a window — between the push and
the counter write — in which it would. The SPEC's "the publish path increments the delivered count"
is satisfied by the existing append; what this change adds is the sentence at the publish site
saying so, because otherwise the next person to optimise the ledger silently removes the bound.

The count is read with the guard's own idiom (`grep -c .` then a `case` on non-digits), never
`grep -c … || echo 0` — that yields a two-line `0\n0` on no match, the trap issue #174 documented
in this repository.

### D5 — Running out of slots leaves the roadmap untouched, and this supersedes ADR-0127 §D7 in part

**The first unreached feature stays `- [ ]` and the run ends.** No `[~]` marker, no
`skipped-features` entry, nothing to undo.

ADR-0127 §D7 says the run "marks the next feature `[~]`, appends to `skipped-features`, and stops".
Measured: `project-conductor` Step 2 selects the first `- [ ]` line, so **`[~]` is invisible to it
permanently**. Under §D7's text every bounded run would leave behind a feature that no later run
picks up without a human editing the roadmap by hand — the bound would quietly delete work from the
roadmap.

**The other half of §D7 stands and is not superseded:** the run must never write `needs-human`, and
running out of budget must be the *least* alarming way for a long session to end. Only the
`[~]`/`skipped-features` clause is reversed. This follows ADR-0042's precedent of superseding
ADR-0036 §2.1 **in part** — one clause, named, with the rest left standing — rather than reversing
a decision wholesale.

**Why §D7 was written that way, recorded so the reversal is legible:** the framing was inherited
from a *token* bound, which can be reached mid-feature and therefore genuinely leaves a feature
half-attempted and worth marking. A feature count cannot: it is checked between features, so the
next one is simply never started, and there is nothing to skip. The clause was correct for the
mechanism it was written for and wrong for the one that shipped.

The reason is written at the exhausted branch in `project-conductor/SKILL.md`, where the old
behaviour would otherwise look like an omission.

### D6 — `token-budget` is removed; `rtf-blocker` keeps its mechanism, and the verdict is NOT transferred

`token-budget` goes from all three sites: the read in `autopilot-guard.sh`, the clear in
`autopilot-disarm.sh`, and the claim in `autopilot/SKILL.md` §3.3. The RUNBOOK's stuck-table row
goes with them, and the table's "five ways to be stuck" becomes four.

**`rtf-blocker` keeps its read in the guard and its clear in the disarm, byte-unchanged.** What
changes is the sentence: §3.3 currently states that `rtf-blocker` and `token-budget` are *"written
by the review step and this skill's `/goal` overlay respectively"*. Neither is. The file will
instead state that `rtf-blocker` is deliberately unproduced **and why**, which is a measured reason
rather than a deferral:

> `concept-to-code` Gate 5's autopilot default is "Skip review", and `project-conductor` invokes
> `concept-to-code` for every feature on both branches — the `_autopilot=true` path and the
> `_autopilot=false` path — never `autopilot-build`. So no review cycle runs during an unattended
> roadmap run, and a producer inside `review-triage-fix` could never fire on the one path where the
> guard that reads this file exists.

**`token-budget`'s verdict is deliberately not transferred to `rtf-blocker`, and this paragraph
exists so a future reader does not "tidy" the second away for consistency with the first.** The two
cases differ in kind: `token-budget`'s halt was **structurally unable to work** — evaluated after
the only thing it could have stopped — whereas `rtf-blocker`'s halt **would work correctly the
moment something wrote it**. Removing a mechanism that cannot work is a correction; removing one
that works and is merely unreached is deleting a safeguard because the path it guards is currently
unused. `VCS-010` in `TODO.md` and PROJECT.md Phase 11 Wave 1 both asked for "a producer or its
honest removal"; the honest answer is the third one — the mechanism is sound, the reason it is
unreached is a larger finding about unattended review (see *Findings recorded, not fixed*), and the
file now says so.

### D7 — Two fences, split by what each needs to read

**Fence 1 — `autopilot-scope-args`**, in a new §1.3 **Phase S**, running **before Phase M**. It
parses `--features`, `--only` and `--dry-run`, selects the source, validates the numeric form, and
prints one line saying which source is in effect. It reads the arguments and the opt-in marker and
**nothing else** — in particular not `PROJECT.md`, which in auto-design mode does not exist yet.

It runs first, before Phase M and Phase P, because a `--features 0` typo must not cost a Phase P
run, and because a `--dry-run` must not trigger Phase P's writes.

**Fence 2 — `autopilot-scope-resolve`**, in §2 Phase 0 as **check 9**. It resolves the tokens
against `PROJECT.md` — which check 4 immediately above it has just asserted exists — aborts naming
an unresolvable or ambiguous token, and writes the scope file.

R-05 puts the abort in Phase 0 pre-flight, so check 9 it is. **Phase 0's header sentence
"The permission posture is NOT one of these eight, and must not be added as a ninth" becomes
count-bearing and stale the moment a ninth check exists**, so it is reworded count-free ("is not one
of the checks in this section, and must not be added as one"). That is not a weakening: the
sentence's job is to stop a second posture check being added *here*, and a needle on a count rots
at every subsequent addition, which is ADR-0067 §F5's lesson. `permission-mode-state.test.sh` PMP2
is re-anchored on the count-free clause in the same change. **Precedent, not improvisation:**
ADR-0110 added check 1b to `autopilot-build` and updated that file's header count in the same edit,
which is what PMP3 pins today.

### D8 — `--dry-run` skips Phase M, Phase P and checks 1–8, and writes nothing

R-11 requires a dry run to exit "without arming the guard or touching the roadmap". Phase P
*creates* `PROJECT.md` and the per-feature SPECs, so a dry run that ran Phase P would have touched
the roadmap before printing anything. Phase S therefore routes `dry_run=true` straight into fence 2
in read-only mode, prints the resolved list and its source, and stops. Phase M, Phase P, checks 1–8
and Phase 1 never run.

**`--dry-run` requires a roadmap that already exists.** With no `PROJECT.md`, fence 2 exits 3
`DID-NOT-RUN` naming the file. That is honest rather than convenient: you cannot dry-run the
resolution of a roadmap that has not been generated.

**A dry run does not write the scope file either**, and this is a decision rather than an omission
the SPEC forgot. Phase 2 is what clears the run's transient state; a dry run never reaches Phase 2,
so a scope file written by one would be stale by construction — every single time. Given that a
stale scope file is an accepted risk mitigated only by the disarm (D9), guaranteeing one on every
dry run would be trading a probe for a landmine.

The pre-flight checks 1–8 are deliberately **not** run under `--dry-run`. They are about whether a
run may start (`gh auth`, TOFU trust, branch protection) and two of them make network calls; a
dry run is about scope resolution and must stay cheap and offline.

### D9 — The stale scope file is an accepted risk, recorded rather than solved

A `scope` file left behind by a run that died is ADR-0112's stale-marker class, with exactly the
exposure `published` already carries and mitigated the same way: `autopilot-disarm.sh` clears it,
and the RUNBOOK's *"The guard is still armed and I cannot push"* section is the documented exit.

A session-marked scope file was considered and not taken. `published` — the file with the same
lifetime, the same writer and the same reader — carries no session marker either, and adding one to
the newer of the two would leave two run-scoped files under one directory with two different
ownership models and nothing explaining which is which. If session-marking is ever wanted it is
wanted for the whole `autopilot-state` directory, in one decision, not per file.

### D10 — The report's `scope` block is additive, and `turns_per_feature` is a labelled self-report

Schema v2.2 gains one object, on the same additive terms as every prior extension of it and with no
version bump:

```json
"scope": {
  "source": "arguments",
  "requested": { "features": 2, "only": ["…", "…"] },
  "delivered": 2,
  "remaining_in_roadmap": 29,
  "turns_per_feature": [ { "feature": "…", "turns": 48 } ]
}
```

`delivered` is read from `published` and `source`/`requested` from `scope` — **both before the
disarm**, which deletes both. §4 already writes the report before disarming; this change states the
dependency at the site, because two files whose reader sits four lines above their deleter is
exactly the ordering that gets "tidied".

`remaining_in_roadmap` is mechanical: the count of `- [ ]` rows in `PROJECT.md` at report time.

**`turns_per_feature` is an orchestrator self-report and is labelled as one in the SKILL.md.** No
per-turn counter is exposed to a skill; what is observable is the sequence of `AUTOPILOT-PUBLISH`
lines the publish step already prints, and the orchestrator counting its own turns between them.
That is a self-report, and ADR-0047 §A3's rule against trusting one does **not** apply, for
ADR-0073's stated reason: the rule is about **gates**, and this figure feeds a human re-deriving a
turn budget. A wrong figure leaves the reader exactly where they were before the field existed, so
it can only add information. It is never read by a gate, and the budget it informs is now a
fail-safe rather than the bound (D11) — which is precisely why an imprecise number is tolerable
here and would not be anywhere a decision hung on it.

### D11 — The turn budget is restated as `N × 60`, with its sample size and its new job

The RUNBOOK's `stop after 200 turns` was written for 13 features at ~15 turns each. Measured: a
full standard chain costs roughly **50 orchestrator turns, n = 1**, and a 110-turn budget delivered
one feature.

The RUNBOOK restates it as `stop after N × 60 turns`, with the reasoning beside the number: 60 is
~50 plus margin from a **single** measurement; the budget is now a **fail-safe for a run that
hangs**, not the bound; and the report records actual per-feature turns so the figure is
**re-derived rather than re-estimated**. ADR-0127 §D8 called the token bound "the primary one" and
this "the backstop" — with the token bound gone, `--features N` is the bound and the turn budget is
the fail-safe. That is the reversal, and it is stated where the number is.

A bare corrected number would repeat the error that produced #365 in the first place: a figure with
no reasoning next to it ages, and nobody knows why it was that.

---

## Alternatives considered

**A1 — Wire `token-budget` as ADR-0127 §D6 proposed.** Rejected on finding 3 of the three above,
which is structural rather than an implementation gap: the guard is a `PreToolUse` hook on the
publish, so a ceiling it evaluates can only ever stop the feature *after* the one that breached it.
Findings 1 and 2 (wrong source field, absent producer block) are fixable; finding 3 is not fixable
without a different hook at a different point in the chain, which is a larger design than
issue #365 asks for. Deferring the decision was also rejected: `PROJECT.md` Phase 11 Wave 1 is explicit
that a halt nothing can raise is not a safeguard, it is a comment.

**A2 — Thread the scope through the `Skill(skill="project-conductor", …)` invocation instead of a
file.** Rejected on the failure mode. The conductor is re-invoked per feature and by two other
paths (Step 3's resume branch, Step 5 branch B's session-boundary resume); a call site that forgets
to re-pass the argument loses the bound with nothing on screen. This repository has recorded that
producer/consumer class four times, and a bound that silently disappears is worse than no bound —
the operator believes the run is capped.

**A3 — Count attempts rather than publishes.** Rejected: predictable in cost, but a roadmap that
skips heavily delivers zero PRs while the runner reports having done its two features, which reads
as a broken runner and is the exact shape of failure autopilot cannot afford unattended. The
accepted cost of the chosen rule — a heavily-skipping roadmap makes the run longer than the number
suggests — is visible in the report (`features_skipped[]` beside `delivered`) rather than silent.

**A4 — Per-key override between the `scope:` marker block and the arguments.** Rejected on a
concrete failure: an `only:` list left in the marker from last week survives a `--features 2` that
meant something else entirely, the operator gets one feature instead of two, and nothing on screen
explains why. One source at a time, printed, never a combination nobody wrote. **Passing any
scoping argument discards the whole block.**

**A5 — A separate `delivered` counter file.** Rejected as a second producer of one fact (D4). The
`published` ledger already increments exactly once per publish and has one writer; a counter beside
it can disagree with it, and the window in which it does is the crash window the bound exists for.

**A6 — Store the resolved topic-slug in the scope file.** Rejected: it adds a fifth derivation of a
value four other sites derive, and a disagreement would select the *wrong feature* silently.
Storing the exact line text (D2) makes a derivation disagreement fail as a loud unresolved token
instead.

**A7 — Extract a shared `topic-slug.sh` so the resolver and the conductor cannot disagree.**
Rejected **for this feature**, not on principle — ADR-0086's criterion would call it extractable.
The conductor's derivation is prose in a SKILL.md, not a script, so extraction means a new
deployable file, a `PAIRS` entry, four call-site rewrites and its own regression surface, in
service of a failure mode that D3 has already made loud. Recorded as a known gap.

**A8 — Put the scope resolution in a new phase after Phase 0 rather than as check 9.** Rejected
because R-05 places the abort in Phase 0 pre-flight, and because a "pre-flight" that a run can fail
*after* is not one. The cost — Phase 0's header sentence carries a count that goes stale — is paid
by rewording it count-free, which is an improvement the sentence needed anyway.

**A9 — Let `--dry-run` run Phase P first, so it works on a roadmap that does not exist yet.**
Rejected: Phase P writes `PROJECT.md`, the per-feature SPECs and the prep branch. A dry run that
does that has touched the roadmap, which is the one thing R-11 forbids. `--dry-run` requires an
existing roadmap and says so.

**A10 — Session-mark the scope file so a stale one is diagnosable.** Rejected for this feature
(D9): `published` has the identical lifetime and no marker, and marking only the newer file leaves
two ownership models in one directory with nothing explaining the split. The question belongs to
`autopilot-state` as a whole.

**A11 — Remove `rtf-blocker` for consistency with `token-budget`.** Rejected, and D6 states the
reason at length precisely because the consistency argument is the tempting one: the two halts fail
in different ways. One cannot work; the other is unreached. Deleting the second is deleting a
working safeguard because nothing currently exercises it.

---

## Consequences

### Positive

- A launch can be bounded. `--features 2` on a 31-row roadmap is the difference between a scoped
  overnight run and an all-or-nothing one, and it is the Phase 11 Wave 1 blocker for every
  measurement Waves 2–6 depend on.
- `--dry-run` makes the resolution auditable without spending a roadmap. It is what stands in for a
  real validation run in this feature's Definition of Done.
- A dead mechanism leaves the codebase. `token-budget` was read by a guard, cleared by a disarm,
  documented in a RUNBOOK table and asserted by three test files, and written by nothing — four
  surfaces maintaining a file that never existed.
- Two claims that named non-existent producers are corrected, and the surviving one now carries a
  *measured* reason instead of a deferral.
- The turn budget stops being a number with no reasoning beside it — the property whose absence
  produced this issue.

### Negative

- **No spend ceiling exists, and after this change nothing gestures at one.** An anomalous feature
  costs what it costs. That is deliberate (A1) and is the single most important thing an operator
  reading a green run must not misread.
- **Three test assertions are deleted** (`phase1.test.sh` ×2, `external-dependency-gate.test.sh`
  EE4) because the mechanism they exercise is gone. `weakening-scan.sh` will flag this, correctly —
  it cannot tell a legitimate deletion from a relaxation, and ADR-0073 §177 recorded that no rule
  over a diff can. The Gate 5 reviewer and the human at the commit gate are the only things that
  can, and this ADR is the record they read.
- **Inert until sync, and the failure is loud rather than silent.** All three new fences run in the
  SKILL.md files; the scope file is written by a fence, not a deployed script, so there is no new
  `PAIRS` entry and no new "not found — the check DID NOT RUN" dependency. What *is* deployment-
  dependent is unchanged: the guard and the disarm still reach `~/.claude` through their existing
  entries, and until `sync-to-claude.sh --apply` runs, the deployed guard still reads
  `token-budget` and the deployed disarm still clears it rather than `scope`. A run launched from
  an un-synced machine therefore leaves a `scope` file behind after Phase 2.
- **`turns_per_feature` is unverified and always will be.** A short list reads as evidence; it is a
  self-report. D10 says so in the ADR and the SKILL.md says so at the field.
- **The slug derivation is duplicated** (A7). Bounded to matching, loud on disagreement, and named
  here rather than fixed.
- **Phase 0 gains a ninth check**, so the pre-flight is one step longer on every launch, and one
  sentence of ADR-0110's prose had to be reworded to stop carrying a count.
- **A new harness file** — `autopilot-run-scope.test.sh` — must be appended by hand to
  `.github/workflows/docs-ci.yml`'s `shell-tests` named list. `.claude/test-cmd` is a glob and picks
  it up automatically; the workflow is not. That divergence has left four harnesses CI-dark before
  (ADR-0113), which is why it is a plan task rather than a footnote.

### Neutral

- No schema version bump. The report's `scope` block is the sixth additive extension of v2.2 on the
  same terms as `features_skipped[]`, `required_checks` and the ADR-0064 metrics.
- No manifest field, no new state, no transition pair. The scope lives entirely in run-scoped files
  the disarm already owns.
- `.claude/autopilot.yml` may now carry a `scope:` block. Absent, the run behaves exactly as it does
  today, which is what makes every existing repo's opt-in marker still correct.
- Historical ADRs are not edited in place (ADR-0034 precedent). ADR-0127 gains a dated
  `## Correction` naming §D5's `--budget`, §D6, §D7's `[~]` clause and §D8's "primary bound";
  ADR-0022 and ADR-0111 keep their `token-budget` references, correct for their moment.
- `TODO.md` `VCS-010` is answered by D6 and closed there.

---

## Findings recorded, not fixed

Three findings were measured while writing the SPEC and are **out of scope for this feature**. Do
not plan work for them here; the full statement is in the SPEC's *Findings recorded, not fixed*
section.

1. **No unattended run performs a review.** `concept-to-code` Gate 5's autopilot default is "Skip
   review" and `project-conductor` invokes `concept-to-code` for every feature on both branches, so
   every PR an unattended roadmap opens has passed no review cycle. This is *why* `rtf-blocker` has
   no producer (D6) and is a larger question than the marker it explains. Belongs to `PROJECT.md`
   Phase 11; needs its own issue.
2. **An unmarked leftover `SPEC.md` is mishandled in both directions.** `gate0-detect.sh` reports
   `spec_topic_match=unknown` when the root SPEC carries no `**Topic slug:**` marker, and `unknown`
   routes **brownfield** — so the chain silently adopts another feature's SPEC; on the greenfield
   branch the same missing marker makes Step 1's archive fence exit 3, which halts the chain. One
   missing marker, two wrong outcomes. Observed on this very chain. Needs its own issue.
3. **The Step 1 slug stamp skips itself on any SPEC that mentions the marker in prose.** Its
   idempotence guard is an unanchored `grep -q` for the marker string, so a SPEC discussing the
   marker satisfies it and the stamp never runs — **rule 12 inside the chain's own machinery**.
   Observed on this file: it was written without its own marker for exactly that reason. The fix is
   a column-anchored `^\*\*Topic slug:\*\*`, which prose cannot satisfy because prose indents or
   quotes it. Compounds with finding 2 — a SPEC that skips its own stamp is the next chain's
   unmarked leftover. Needs its own issue.

---

## References

- `SPEC.md` — the approved specification, R-01 … R-11
- `docs/superpowers/plans/2026-08-06-365-scope-and-bound-the-autopilot-run.md` — implementation plan
- `PROJECT.md` Phase 11 Wave 1 — the authoritative roadmap scope
- ADR-0127 §D5–§D8 — superseded in part; see the `## Correction` appended there
- ADR-0128 (issue #370) — `publish-feature.sh --issue`, the authority `--only`'s issue-number form
  reuses
- ADR-0112 (issues #321/#323) — the stale-marker class D9 inherits, and `autopilot-disarm.sh`
- ADR-0111 (issue #324) — the contained-skip versus run-level-halt split D5 must not violate
- ADR-0110 (issue #320) — the precedent for adding a pre-flight check and updating its count
- ADR-0073 (issues #177/#178) — why a self-report feeding a human decision is not the thing
  ADR-0047 §A3 forbids
- ADR-0069 / ADR-0086 — the extract-or-duplicate criterion applied in D2, D4 and A7
- ADR-0064 (issue #118) — `task_metrics`' four fields, none of which is a token count
- ADR-0042 — the supersedes-in-part precedent D5 follows
