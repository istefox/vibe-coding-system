# ADR-0076 — One reader for manifest field state, and a rule that reaches the author of the next checker

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #195
- **Extends:** ADR-0075 (#123, the instance), ADR-0069 (the shared-predicate pattern), ADR-0016 and
  ADR-0039 (the additive fields whose lateness is the root cause), ADR-0047 (the cross-skill
  `scripts/` dependency precedent)
- **Reported as:** derived from the #123 fix, not from a failure. Phase 4.1 of `PROJECT.md`.

## Context

Fields reach `manifest-init.sh` as **additive** — no schema bump, no migration — so a manifest
written before a field simply does not carry it. That is correct and deliberate: ADR-0016 added
`hook_verified` that way, ADR-0039 added `step5_review_mode` that way, and `step5-report.json` has
taken five extensions on the same terms.

Then a checker gets written over the manifest corpus and reads the field with

```sh
python3 -c "import yaml; m=yaml.safe_load(open('$m')); print(m.get('hook_verified'))" 2>/dev/null
```

`m.get()` returns `None` for a field that is **absent** and for one explicitly set to null, and the
shell one-liner returns an **empty string** when the file could not be parsed at all, because the
traceback went to `/dev/null`. Issue #123 is what that costs: `nightly-autopilot` aborted a whole
roadmap on two long-completed chains that merely predate the field, and told the operator they were
"corrupted or hand-edited".

Neither half was wrong on its own. The field being additive is right; validating it is right.
**Nothing connected the two** — no rule told a checker's author that absence is an expected state
with an era attached, rather than an error.

Issue #123 fixed both call sites and left **two hand-written copies of the same five-state extraction**,
which is the shape ADR-0069 had just removed from the plan-task predicate for the same reason.

## Decision

### D1 — `manifest-field-state.sh` reports; it never decides

`concept-to-code/scripts/manifest-field-state.sh <manifest> <field>` prints exactly one line:

| stdout | meaning |
| --- | --- |
| `PRESENT\|<value>` | the field exists; `<value>` is `str()` of the parsed YAML |
| `ABSENT\|<current_step>` | the field is not in the mapping; the step is the **era signal** |
| `UNREADABLE` | the file is not parseable YAML, or does not parse to a mapping |

Exit `0` a state was determined (including `UNREADABLE` — that *is* a determination), `2` bad
invocation or a missing file, `3` **the check could not run** (no `python3`, no PyYAML).

Exit 3 is separate from `UNREADABLE` on purpose: one is a fact about the input, the other a fact
about the environment. It is the ADR-0046 exit-3 precedent and #123's own lesson applied one level
down — a checker reporting nothing must be distinguishable from a checker finding nothing.

### D2 — The policy stays at each call site, because the two policies are opposite and both right

| call site | reads | `ABSENT` means | verdict |
| --- | --- | --- | --- |
| `nightly-autopilot` check 6 | every manifest in the repo, mostly long completed | predates the field | **tolerate** |
| `autopilot-build` check 7 | the one manifest about to be built, in flight by definition | dispatch mode unknown | **abort** |

A helper returning a *verdict* would have to flatten that asymmetry or grow a policy argument for
it. It returns a **fact**, and each caller keeps its own rule visible at its own site.

The value domain is the caller's for the same reason, and it has to be: `hook_verified` is a
boolean, `step5_mode` is `workflow|agent_fallback|null`, `step5_review_mode` is `none|checkpoint`.
There is no general "valid".

**This asymmetry is the thing most at risk from a later reader** who finds two call sites treating
one state differently and reconciles them. Both sites carry the sentence "Do not `reconcile` the
two", and `manifest-field-state.test.sh` section P asserts both branches and both notes still
exist — including `P4`, that neither site kept a private copy of the extraction.

### D3 — A missing helper fails the gate closed, and never falls back to inline logic

Resolution is the two-tier order `project-conductor` and `commit` already use:
`$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/` then `$HOME/.claude/skills/…`. If **neither**
resolves, the pre-flight aborts with the exact remedy (`sync-to-claude.sh --apply`).

`commit`'s own resolver takes the opposite branch — it runs neither scanner and keeps today's
behaviour — and that is right *there*, because it degrades an advisory reporter. Here the caller is
a **gate**, so an infrastructure gap must be loud and actionable. A silent inline fallback would
recreate the duplication on the one path where nobody is watching.

**The dependency class is not new.** `nightly-autopilot`'s own check 8 already executes
`~/.claude/hooks/set-branch-protection.sh` inside the same pre-flight, and ADR-0047 established
three skills depending on a fourth's private `scripts/`. This adds a fourth consumer of
`concept-to-code/scripts/`, not a new kind of coupling.

### D4 — The rule is written where the author of the next checker meets it

The helper prevents recurrence only for someone who knows to use it. The rule is what makes them
know, so it goes in `CLAUDE.md` — loaded every session — pointing at the helper:

> A checker that reads a manifest field must treat **absent** as a distinct state from **invalid**
> and from **unreadable**, and must decide what absence means from the manifest's `current_step`.
> Read the state through `manifest-field-state.sh`; never with a bare `m.get()`.

`manifest-validate.sh` already applies this rule as a *habit*, case by case: invariant 12 is
conditional "if present" so pre-ADR-0040 manifests stay valid, invariant 14 likewise for ADR-0039.
That is the same rule, discovered independently, three times, in one file — which is the evidence
that it is a rule and not a series of coincidences.

### D5 — Strictness is preserved exactly, including one case that looks like a bug

`PRESENT|<value>` is `str()` of the parsed YAML, so a boolean reads `True`/`False` and a **quoted**
`"true"` reads `true`. A caller asserting `True`/`False` therefore rejects the quoted form. That is
what the one-liners this replaces already did, and it is retained deliberately: a quoted boolean in
a machine-generated manifest is a hand-edit, which is exactly what the check exists to catch.
Pinned by `S11`.

## Alternatives considered

### A — Write the rule only, ship no helper

Rejected. A rule with no cheap way to follow it is followed by whoever remembers it. The two copies
that #123 created would also stay, and they are the drift the rule is about.

### B — Ship the helper only, write no rule

Rejected, and it is the weaker half. The helper prevents recurrence only for an author who already
knows the problem exists; the rule is what reaches one who does not. ADR-0067's F6 is the standing
evidence that instance-level fixes do not generalise on their own.

### C — Have the helper return a verdict (`pass`/`abort`)

Rejected per §D2. It would have to encode a policy that is legitimately opposite at the two known
call sites, and the parameter that expressed that would put the policy *further* from the code that
owns it.

### D — Keep the call sites self-contained, deduplicate nothing

Rejected. It was tempting on one real ground: the fences currently have no external dependency, and
adding one means a sync gap becomes a nightly abort. That ground dissolved on inspection — check 8
of the same pre-flight already executes a `~/.claude` script, so the failure mode is present in the
same function, and §D3 makes this one loud rather than silent.

## Consequences

### Positive

- One parser. The next additive field's checker inherits the four-state distinction for free.
- The rule reaches an author who has never read #123.
- The two opposite absence policies are now *documented as deliberate at both sites*, where before
  they were two similar-looking blocks that a tidy-minded reader would have merged.
- `manifest-field-state.sh` answers about **any** field (`S12`), so it is not a `hook_verified`
  special case wearing a general name.

### Negative

- **Two pre-flight gates now depend on a deployed script.** Inert until sync, and until then both
  fail closed. That is the correct direction and it is still a new way for an un-synced machine to
  stop a nightly run.
- The rule is prose in `CLAUDE.md`. Nothing enforces that a new checker uses the helper — issue
  #193's derived-guard instrument would be the shape that could, and it is not applied here.
- `manifest-validate.sh`'s 28 invariants are **not** converted. Its conditionals already implement
  the rule by hand and rewriting them is a much larger blast radius; invariant 4 specifically is
  issue #197's subject and is deliberately left to it.
- `P1`/`P2`/`R1` pass before and after in substance — they guard the design rather than evidence a
  fix. `D1` (the `PAIRS` entry) and the four assertions listed below were the ones that were RED.

### Neutral

- No manifest field, no schema bump, no state-machine change.
- Behaviour is unchanged at both call sites: every `scope-guards.test.sh` C and D assertion from
  ADR-0075 still passes, unmodified.
- One new `PAIRS` entry, pinned by `D1` — `pairs-completeness.test.sh` cannot see skill `scripts/`
  (ADR-0043), the same gap ADR-0069's `PTB7` had to cover by hand.

## Lessons the harness caught, recorded because they recur

- **`X6` first "failed" at exit 127.** Emptying `PATH` to hide `python3` also hides `bash`, so the
  harness could not launch the helper at all and the failure had nothing to do with the code.
  Invoked through an absolute `/bin/bash` instead.
- **`P3` failed on a comment line wrap.** The do-not-reconcile sentence wraps across two comment
  lines in one file, so a plain flatten leaves a `#` inside the phrase. The matcher now strips
  comment markers before flattening — the ADR-0073 line-wrap lesson, one layer down.
- **`P4` counted the explanation as the defect.** Its needle was `m.get('hook_verified')`, which
  both files legitimately quote while explaining why it was replaced. Comment lines excluded — rule
  12, and #127's own failure mode in miniature.

## References

- Issue #195, including the acceptance criterion §D2 answers about preserving the asymmetry
- `docs/architecture/ADR-0075-123-hook-verified-states.md` — the instance
- `docs/architecture/ADR-0069-172-plan-task-form.md` — one place decides, loaded not pasted
- `docs/architecture/ADR-0047-101-weakening-scan-wiring.md` — the cross-skill `scripts/` precedent
- `staging/plugin/scripts/tests/manifest-field-state.test.sh`

## Correction 2026-07-31 (issue #240) — the worked example named a value nothing writes

§D2's sentence *"`step5_mode` is `workflow|agent_fallback|null`"* is **wrong**, and has been since
this ADR shipped. Nothing has ever written `agent_fallback`. Measured over the 41-manifest corpus:
18 `agent_batch`, 2 `workflow`, 19 `null`, 2 without the field, **0 `agent_fallback`**. Both
producers write `agent_batch` (`concept-to-code/SKILL.md`, at the Workflow-refusal branch and at the
fallback activation).

The body is left unedited, per the ADR-0034 precedent for historical records. What is corrected
forward is everything derived from it: `manifest-field-state.sh`'s header — the live worked example
§D2 tells the next author to follow — and both `CLAUDE.md` summaries.

**ADR-0016 §Manifest fields had it right all along**, writing `"workflow" | "agent_batch"`. The
error entered in a **summary** of that ADR and spread from the summary, which is why the issue's own
description named ADR-0016 as a carrier and was wrong. A derived guard now asserts the documented
domain against the values the producers actually write, in both directions, so this class of drift
fails CI instead of waiting for a corpus sweep — see `manifest-field-state.test.sh` section V.

Nothing about the rule changes: absence stays distinct from invalid and from unreadable, and the
value domain stays the caller's.
