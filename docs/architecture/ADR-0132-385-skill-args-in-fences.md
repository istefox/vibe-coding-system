# ADR-0132 — Skill arguments are substituted into `$<digit>` inside the skill body, so a bash fence renders as code the file does not hold

- **Status:** Proposed
- **Date:** 2026-08-08
- **Issue:** #385 — SPEC `385-skill-args-substituted-in-fences`
- **Phase:** PROJECT.md Phase 12, Wave 1 (R1/R2/R3) — the rendering defect (P0)
- **Evidence:** `docs/AUTOPILOT-RUN-AUDIT-2026-08-08.md` §F1
- **Supersedes / amends:** nothing. It closes a mechanism ADR-0083 assumed and never stated.

---

## Context

When a skill is invoked with arguments, Claude Code whitespace-splits the argument list and
substitutes it into every `$<digit>` token in the skill's own markdown body, **0-indexed**, before
the body reaches the model. A bash fence is text, so it is rewritten too.

Measured three times independently in one run (audit §F1, CC **2.1.226**, run of 2026-08-07 22:30Z
→ 2026-08-08 01:15Z). One row is enough to see the shape: `autopilot` invoked with
`--features 1 --only 294` holds `case "$1" in` on disk and renders `case "1" in`. 0-indexing was
confirmed from the `concept-to-code` invocation's own title words.

**Why this outranks every other finding in that audit.** ADR-0083's whole fence-contract mechanism
rests on the rendered text being the executable text. Under this defect it is not, and the
corruption is *silent* — it produces syntactically valid shell that does the wrong thing. Three
shipped fixes are reintroduced at render time inside the very fences written to fix them:
c2c Step 5.0.1's `rel()` reproduces ADR-0089's defect, and both TOFU probes reproduce ADR-0102's.
`autopilot`'s own argument parser is corrupted, which means the bound ADR-0129 exists to enforce
would not have parsed and the run would have gone unbounded across all 30 pending roadmap rows.

The 2026-08-07 run survived only because the orchestrator read every fence from disk instead of
executing the rendered text. That is an ad-hoc workaround, not a designed mitigation.

**The mechanism is documented nowhere** — no ADR, no line of `CLAUDE.md`. Every one of the 19
occurrences was written by an author with no reason to know, for a good local reason.

### What was measured here, before designing

Re-derived rather than taken from the brief, per this repository's own rule.

| quantity | value |
|---|---|
| staged `SKILL.md` files | **30** |
| fences in them | 337 (**160** opened `bash`, 177 other) |
| lines carrying `$<digit>` | **20** |
| …inside a `bash` fence (the population) | **19** |
| …inside a `swift` fence (out of scope) | 1 — `swiftui-pro:84`, a SwiftUI binding closure |
| …outside any fence (prose) | **0** |

Two corrections to the numbers this feature was briefed with:

- The brief says **13** occurrences sit inside declared fence contracts. Measured: **14**, across
  **7** contracts. The extra one is `autopilot-build:243` (`autopilot-build-check-6`).
- The brief's fix-shape breakdown lists "7 awk field references" and then enumerates 3 + 2 + 2 + 1
  = **8**. Eight is right: 8 awk lines, 10 shell-positional lines, 1 comment = 19.

Per-occurrence map, derived by classifying every line against its enclosing fence:

| skill | line(s) | fence contract | shape |
|---|---|---|---|
| `concept-to-code` | 338 | *(undeclared)* | `shasum … \| awk '{print $1}'` — Form B TOFU probe |
| `concept-to-code` | 935–939 | `c2c-step5-preflight-dirty-classify` | `rel()` positional parameter, 5 lines |
| `concept-to-code` | 2031, 2032 | *(undeclared)* | two `awk -F'\t'` metric readers |
| `concept-to-code` | 3303 | `c2c-gate2b-trust-probe` | `shasum … \| awk '{print $1}'` |
| `autopilot` | 121, 132, 140 | `autopilot-scope-args` | argument parser |
| `autopilot` | 184 | `autopilot-scope-args` | `scope:` block extractor, `$0 ~ …` |
| `project-conductor` | 43 | *(undeclared)* | mode detection + `--fork-from` parse |
| `project-conductor` | 435 | `conductor-step4-nospec-skip` | `[~]` marker, `$0 == "- [ ] " f` |
| `project-conductor` | 682 | `conductor-branch-c-entry-classify` | `[~]` marker, identical program |
| `autopilot-build` | 149 | `autopilot-build-check-2` | a comment quoting an awk second-field extractor |
| `autopilot-build` | 243 | `autopilot-build-check-6` | `shasum … \| awk '{print $1}'` |
| `commit` | 233 | *(undeclared)* | `is_test_path()` positional parameter |

### Two facts that shape the design more than the count does

**The harness cannot see this defect, and never will.** Every test in
`staging/plugin/scripts/tests/` reads a file; the model executes a rendering of that file. A green
run says nothing about the failing quantity. This is stated here rather than left implicit because
it inverts the usual relationship: the guard this ADR adds is a *regression* guard on a property
the harness can check (no token present), not evidence that the *defect* is fixed. The only check
that reads the failing quantity is a live invocation, and it is a human step (§Verification).

**`project-conductor` Step 0 is broken today in a second, adjacent way.** Its fence reads `$1` and
iterates `"$@"` — but a fence executed as a script has no positional parameters at all, so `$@` and
`$#` are empty while `$1` is filled in by the substituter. `autopilot`'s Phase S already solved
this correctly, by declaring a free variable `_args` bound by the orchestrator and doing
`set -- $_args`. Repairing the conductor to that pattern necessarily changes its rendered behaviour
— because its rendered behaviour is wrong. See §Consequences.

---

## Decision

### D1 — Stop putting parameterised logic in a rendered document. A file is never rendered.

Two mechanisms, both already precedented here:

- **Shell positional parameters** move into a script under `staging/plugin/skills/<name>/scripts/`,
  invoked with the arguments. Same shape as `plan-tasks.sh`, `spec-coverage.sh`,
  `manifest-entry-state.sh`, `permission-mode-state.sh`.
- **awk field references** are either rewritten field-free in place, or move into the same kind of
  script, where `$1` and `$0` are legal because nothing renders the file.

Escaping is refused (§A1). Renaming is refused (§A2, with one bounded exception in §D3).

### D2 — Excise the *case*, not the *fence*.

Take out exactly the construct that needs a positional parameter or a field reference, and leave
everything else in the document. The three fences most affected — c2c Step 5.0.1's dirty
classifier, Gate 2b's trust probe, `autopilot`'s Phase S — are gates a human must be able to read
at the point of decision. Moving them wholesale (§A3) would make the document opaque exactly where
it is load-bearing, and would multiply the blast radius across 7 existing contracts, 6 existing
harness files and 12 declared plants.

Concretely, **four new scripts** and **eight in-place rewrites**:

| new script | replaces | invoked from |
|---|---|---|
| `skills/autopilot/scripts/scope-args-parse.sh` | the `set -- $_args` parse and its six variables | `autopilot` §1.3 Phase S |
| `skills/project-conductor/scripts/conductor-args.sh` | `[ "$1" = "autopilot" ]` + the `--fork-from` loop | `project-conductor` Step 0 |
| `skills/project-conductor/scripts/mark-roadmap-skipped.sh` | the two identical `[~]` awk programs | Step 4 no-SPEC skip; branch C |
| `skills/concept-to-code/scripts/repo-rel-path.sh` | `rel()` | c2c Step 5.0.1 |

| in place | how |
|---|---|
| 3 × `shasum -a 256 X \| awk '{print $1}'` | `shasum -a 256 X \| cut -d' ' -f1` |
| 2 × `awk -F'\t' '$1=="TOKEN"{print $2}'` | `sed -n 's/^TOKEN[[:space:]][[:space:]]*//p'` |
| 1 × `autopilot`'s `scope:` block extractor | field-free awk: a bare `/re/` pattern is `$0 ~ /re/` by definition, so `found && /^[[:space:]]+/ { print; next }` is the same program without naming the record |
| 1 × `commit`'s `is_test_path()` | the function is *eliminated*, not renamed (§D3) |
| 1 × `autopilot-build:149`'s comment | reworded to describe the banned idiom without spelling it |

`mark-roadmap-skipped.sh` is an extraction under ADR-0086's criterion in its strict sense: the two
`[~]` sites are one question — "mark this roadmap row skipped" — and two copies giving different
answers *would* be a defect, because a row marked by one path and not the other is a roadmap that
disagrees with itself. That is the ADR-0069 case, not the ADR-0086 case.

### D3 — `commit`'s `is_test_path()` is eliminated in place, diverging from the SPEC's edge case, deliberately.

The SPEC states: *"A function's `$1` cannot be removed in shell. The six shell-positional cases are
not fixable in place; they require external files."* That premise is true of five of them and false
of this one, because the function has **exactly one call site** (measured: 3 occurrences in the
file — a prose mention, the definition, one call). Inlining the `grep -qE` at the loop deletes the
positional parameter outright rather than relocating it, which satisfies R-01 fully.

The reason to prefer that here specifically, rather than for consistency's sake:

- `commit` is invoked by `concept-to-code` Step 7, `project-init` and `autopilot-build`. A new hard
  `~/.claude` dependency on it is paid by three other skills, on unattended paths.
- **The predicate has no safe degradation.** ADR-0044 records that `commit`'s resolvers degrade to
  today's behaviour because they guard advisory reporters. Here the "today's behaviour" fallback
  would be *no test files found*, which is the silent-omission failure the H4 gate exists to
  prevent — and the block's own prose says under-match is the dangerous direction. An external
  helper would need a fallback with no correct answer; inlining removes the question.

This is recorded as a divergence rather than applied quietly, because it reads at a glance like the
"merely renames them" dodge the SPEC forbids, and it is not: the token is gone, not moved.

### D4 — Every new dependency fails CLOSED, in the fence's own exit vocabulary.

An unresolved helper is *the check did not run*, never *the check found nothing* — the distinction
this repository has drawn in `spec-coverage.sh`, `plan-tasks.sh`, `manifest-field-state.sh`,
`secret-scan.sh` and every recent pre-flight. Each site uses the token its own fence already
documents, and the sync remedy is printed:

| site | unresolved-helper outcome |
|---|---|
| `autopilot` Phase S | exit **3**, the code that fence already documents as "the check DID NOT RUN" |
| `project-conductor` Step 0 | `CONDUCTOR-ARGS: DID-NOT-RUN — …`, exit 3 |
| c2c Step 5.0.1 | `PREFLIGHT_NOHELPER`, exit 3, added to the remediation list beside `PREFLIGHT_NOREPO` |
| `conductor-step4-nospec-skip` / `conductor-branch-c-entry-classify` | reuse each fence's existing `DID-NOT-RUN` exit-3 branch |

Do **not** reconcile Phase S's exit 3 with Phase M's exit 1 thirty lines below it. Each fence has
its own documented exit vocabulary and both abort the launch; a "consistency" pass that renumbers
one of them changes a contract its tests assert.

Each of the four new scripts carries the same three-code contract: **0** = ran and produced a
result, **2** = bad invocation, **3** = could not run. None of them prints a `CLEAN` sentinel and
none should ever grow one — they are not reporters.

### D5 — `project-conductor` Step 0 gains a declared fence contract, and that cascade is taken on purpose.

Adding a fail-closed helper resolution makes Step 0's fence abort-capable, and ADR-0083 §F3 then
requires a declaration, which §F4 then requires a test to execute. All three follow: the fence
becomes `<!-- fence-contract: conductor-step0-args -->` and is executed by
`conductor-entry-failure-split.test.sh`, which already carries `run_fence` machinery pointed at
that file.

This is a net gain rather than a tax. Step 0 decides whether the whole roadmap runs unattended, and
it is executed by nothing today. There is also no safe default on an unresolved helper: `false`
means an attended run prompting with nobody present (the #329 class), `true` means unattended when
nobody asked for it. Refusing is the only defensible answer, and refusing is what makes it
abort-capable.

### D6 — The guard partitions, it does not merely grep.

`staging/plugin/scripts/tests/skill-fence-positional-tokens.test.sh` derives every `$<digit>` line
in `staging/plugin/skills/*/SKILL.md` and splits it three ways — **BASH fence / non-BASH fence /
outside any fence** — then asserts the three buckets sum to the file-wide count.

The partition is what gives the count guard teeth. A denominator guard (`>= 25` files, `>= 100`
bash fences) catches a glob or a parser that has stopped resolving wholesale; it cannot catch a
fence predicate that has narrowed slightly and now under-reports, which reads exactly like a clean
corpus. The sum identity does: a line that stops being recognised as *inside a bash fence* has to
land in another bucket, and it cannot vanish.

It also makes R-03 structural rather than a special case. `swiftui-pro:84` is not an exclusion list
entry — it is a member of the non-BASH bucket, and the guard asserts that bucket is **non-empty**,
so the language filter is exercised by a real occurrence rather than asserted about. A rewrite of
that Swift line fails the assertion loudly instead of leaving a stale exemption reading as clean
(ADR-0081 `ZA4`, ADR-0078 `C2`).

One further exclusion is asserted because this feature creates it: `skills/*/scripts/*.sh` is **not**
in the population. The four new scripts are full of legitimate `$1`, and a guard that later widened
to all of `staging/` would fail on its own fix.

Instance **14** of the derived-guard pattern (ADR-0086) — **not extracted**, a deliberate copy: it
asks its own question about its own population, so two copies disagreeing would not be a defect.
Derive the number at implementation time from the marker sweep rather than trusting this one; the
sequence already carries two collisions (10 and 12 are each claimed twice), which are pre-existing
and not this feature's to fix.

### D7 — The waiver is per-line, not per-fence, and starts empty.

`# fence-dollar-exempt: <reason ≥ 40 chars>` on the offending line, or on the line immediately
above it. **One line** — a reason that wraps is a prose assertion depending on where the text
breaks, the family this repository has been bitten by seven times (ADR-0073, ADR-0076, ADR-0080,
ADR-0082, ADR-0098, ADR-0101, ADR-0111).

Per-line rather than per-fence for two reasons. A fence already carries at most one HTML marker and
`enumerate_fences` overwrites a pending one, so a fence-level waiver would collide with
`fence-contract:`. And a line-level waiver says *which* occurrence is excused; a fence-level one
excuses every future occurrence in that fence, which is a hole shaped like a waiver.

**The corpus will hold zero waivers when this ships**, so the reason-length and staleness
assertions are vacuous. That is stated in the passing message rather than papered over, and the
waiver parser is exercised against a temp-directory fixture in both directions so the mechanism
itself is tested without planting a waiver in a real `SKILL.md`. The population function therefore
takes **file paths**, never a directory — ADR-0085's lesson, which is what makes the fixture
possible at all.

### D8 — Prose occurrences are reported, not gated.

A `$<digit>` in prose is substituted too, so a sentence reading *never write a positional token
here* renders as a sentence naming somebody's argument. The corpus has **zero** today. The SPEC
scopes R-01/R-02 to bash fences, so the guard reports the prose count as an informational line and
does not fail on it. Recorded as a candidate follow-up rather than silently widened.

Consequence for every author touching these files, including this feature's own coder: **write
`$<digit>` or "a positional-parameter token" in prose and in comments, never a literal**. The
`autopilot-build:149` comment is the existing instance of exactly that mistake — a comment
instructing readers not to use an idiom, by spelling it.

---

## Alternatives considered

### A1 — Escape the tokens in place (`\$1`, `${1}`, HTML entities)

**Rejected.** The substituter's escaping rules are undocumented and were not measured; the audit
established *that* substitution happens and its indexing, not what it respects. An escape that
turns out to be honoured on one build and not the next fails silently and produces the same
syntactically-valid-but-wrong shell. It also leaves parameterised logic inside a rendered document,
so the next token — a new `$2`, an awk `$0` — reintroduces the defect for the same good local
reason the current 19 were written. And a guard cannot check an escape mechanically without
encoding rules nobody has verified.

### A2 — Keep the logic in the fence, pass values through named variables

Concretely: `rel()` reads `$_rel_in` instead of `$1`; `autopilot`'s parser reads a pre-split array.
Legal shell, no new files, no deployment dependency, no new failure mode, and every existing fence
test passes byte-unchanged.

**Rejected**, on three grounds and in that order. The SPEC rules it out explicitly ("they require
external files"). It leaves executable logic in a document whose rendering is untrustworthy, so the
property only holds while nobody adds a positional parameter — which makes the new guard
load-bearing for *correctness* rather than for regression, an inversion worth avoiding on a safety
gate. And the idiom exists nowhere else in this repository, so it is the shape a future reader
"tidies" back into `$1`.

Adopted in exactly one place (§D3) where the function can be **eliminated** rather than renamed,
which is a different operation with a different result.

### A3 — Move each affected fence wholesale into a script, leaving a resolver + invocation

**Rejected.** It maximises what this change touches: 12 declared plants inside `autopilot`'s Phase
S region alone would need retargeting (measured), against 4 under the narrow excision. It makes the
document opaque at the three places a human is expected to read the mechanism before approving —
Step 5.0.1's classification, Gate 2b's probe, Phase S's scope resolution. And `recovery-preflight.
test.sh`'s RJ suite reconstructs a "pre-#239" variant by `sed`-transforming the extracted fence;
moving the classification out of the fence would require rewriting that reconstruction, which is
red evidence for ADR-0089 and worth more than the tidiness.

### A4 — Document the mechanism, fix nothing, and rely on the convention

**Rejected.** The 19 occurrences already exist and already corrupt at render time; three of them
reintroduce shipped bugs. A convention with no check is precisely what produced them — every author
had a good local reason and no way to know. This repository's own history says the same thing four
times over (ADR-0107, ADR-0117, ADR-0121, ADR-0125): a property that holds and is checked by
nothing is one edit from a property that does not hold and is checked by nothing.

### A5 — Guard every `$<digit>` in the file, prose included

**Rejected for this feature**, on SPEC scope (R-01/R-02 name bash fences). The corpus has zero
prose occurrences, so widening would gate nothing today while constraining how the ADR's own
lesson can be written into the five `SKILL.md` files. The count is reported (§D8) so the absence is
measured rather than assumed, and the widening is a named follow-up.

### A6 — Share `enumerate_fences` / `fence_body` with `fence-contract-coverage.test.sh`

**Rejected**, per ADR-0086 §D1: extract only when two copies giving different answers would be a
DEFECT. These two ask different questions of the same corpus — "which fences declare themselves"
versus "which fences hold a positional token" — and each is independently runnable by design, which
is the property that makes six independent guards worth having. A defect in a shared source
disables both at once, in the stay-green way this repository has watched three times.

The cost is real and is accepted: the two fence parsers can drift on what counts as a bash fence.
§D6's partition identity is the mitigation — a narrowed predicate breaks the sum inside this file,
without needing the other file to agree.

### A7 — Put the new guard where it cannot deploy (`staging/plugin/scripts/tests/<name>.sh`, no `.test.sh`)

The ADR-0117 / ADR-0120 / ADR-0131 placement, chosen there to keep a *checker* out of `PAIRS`,
`docs-ci.yml` and `.claude/test-cmd` and so avoid the inert-until-sync class.

**Rejected.** That pattern exists for checkers something else must *invoke*. This guard has no
runtime consumer — it is a harness assertion and nothing else — so a plain `*.test.sh` is correct,
runs in `.claude/test-cmd`'s glob automatically, and is covered by `pairs-completeness.test.sh`'s
`CI0`/`CI1` named-list check (ADR-0113), which turns the `docs-ci.yml` append from a thing to
remember into a thing CI enforces.

---

## Consequences

### Positive

- The text a model executes becomes the text the file holds, for the 19 lines where it is not.
  Three shipped fixes (ADR-0089's `rel()`, ADR-0102's two TOFU probes) stop being reintroduced at
  render time.
- `autopilot`'s bound (ADR-0129) becomes real under argument invocation. Today the parser that
  enforces it is the first thing the substituter corrupts.
- The mechanism is written down, so the next author has a reason not to reach for a positional
  parameter, and a guard that says so before review does.
- `project-conductor` Step 0 — which decides whether an entire roadmap runs unattended — gains its
  first executed test.
- Two roadmap-marking sites become one script, so a `[~]` written by one path and not the other is
  no longer expressible.
- `repo-rel-path.sh` makes `rel()` directly unit-testable. It has had three normalisation defects
  in two issues (#239 symlinks, #344 case), each found by a chain run rather than by a test, because
  it could only ever be exercised through the whole fence.

### Negative

- **Four new hard `~/.claude` dependencies, each failing closed, so the affected gates are worse
  than inert until `staging/sync-to-claude.sh --apply` is run.** This is the class that has bitten
  six recent ADRs, taken knowingly: the alternative is leaving a P0 silent corruption in place. The
  most exposed is c2c Step 5.0.1, where an un-synced machine refuses **every** Step 5 with
  `PREFLIGHT_NOHELPER` rather than mis-classifying. The failure direction is right; the failure is
  still new.
- **`skills/*/scripts/*.sh` is invisible to `pairs-completeness.test.sh`.** Its `check_complete`
  covers `plugin/skills` with the pattern `*/SKILL.md` only, so a missing `PAIRS` entry for any of
  the four new scripts is caught by nothing except this feature's own assertion. Precedent:
  ADR-0109 `MES0b`, ADR-0069 `PTB7`.
- **`project-conductor` Step 0's rendered behaviour changes**, because its rendered behaviour is
  wrong: `$1` is filled by the substituter while `$@`/`$#` are the executing shell's (empty), so
  neither mode detection nor `--fork-from` works as written. The repair moves both to a script and
  requires the fence to declare a free `_args` bound by the orchestrator, the pattern `autopilot`'s
  Phase S already uses. The SPEC's "must not alter its behaviour" is honoured as *must not alter the
  designed semantics*; the audit's §F1 records what those are.
- **Four plant declarations move with their needles** (`AR8`, `AV1`, `AV2`, `AV3` in
  `autopilot-run-scope.test.sh`, measured against the Phase S region), and each must still match
  exactly once in its new target. `plant-check.sh` decides a plant fired with a **prefix** match on
  `^FAIL: <id>` (the open #355 defect), so new assertion ids must be chosen not to prefix an
  existing one.
- **Two cross-file assertions break by design and must be re-anchored, not deleted:**
  `human-gate-coverage.test.sh` `HIA6c` greps the *name* `is_test_path` in `commit/SKILL.md`, and
  `recovery-preflight.test.sh` `RJ13b` greps `rev-parse --show-prefix` in the *extracted fence*.
  Both are assertions on an identifier or a location rather than on a behaviour, and both are
  re-pointed at the mechanism in its new home.
- **The guard's R-01 assertion is red for most of the implementation** (19 → 12 → 10 → 5 → 2 → 1 →
  0). It is declared expected in the plan with the residual count per task. It is safe because
  `autopilot-build`'s circuit breaker reads `step5-report.json` once at the **end** of Step 5
  (ADR-0101 §BP6), and the last fix task greens it inside Step 5.
- The waiver mechanism ships unexercised by the real corpus. Its assertions are vacuous until
  somebody writes the first waiver; a fixture covers the parser, and the passing message says so.
- Three `SKILL.md` fences and one comment gain a "do not write a positional token here" note. Small
  prompt cost, accepted on ADR-0083 / ADR-0084 terms.

### Neutral

- No manifest field, no schema change, no state file, no new gate. `step5-report.json` is untouched.
- The `swift` occurrence is untouched and must stay: it is what makes the non-BASH bucket non-empty,
  and therefore what makes the language filter exercised rather than asserted.
- The measurement is **build-stamped to CC 2.1.226**. ADR-0016's v2.1.154 experience is the
  precedent — the substrate moves. If a future build changes the substitution rule, re-run the
  §Verification probe and record the result rather than trusting this date. The fix is inert-safe
  under any change: removing the tokens is correct whether or not they are still substituted.
- The `CLAUDE.md` record (R-04) is asserted by a grep that **always fails inside a plant sandbox**,
  because `plant-check.sh` copies only `staging/` and `docs/` (ADR-0122's `RG1` class). It carries
  no declared plant, is given an id that prefixes no other id in the file, and is labelled at its
  own site so nobody chases it.

---

## Verification

A green harness proves nothing here. The only check that reads the failing quantity is a live
invocation, and it runs against the **deployed** copy, so it is available only after the human sync
step:

1. `bash staging/sync-to-claude.sh --apply` (HITL — shows a diff before overwriting).
2. `/skill autopilot --dry-run --only <n>` — an invocation with two argument tokens, safe by
   construction (Phase S resolves, prints, and stops; no guard armed, nothing written).
3. Compare every `bash` fence in the rendered body against
   `~/.claude/skills/autopilot/SKILL.md`. **Byte-identical is the pass condition.** Any difference
   is a residual occurrence, and it names its own line.

Record the result and the CC build in this ADR when it is run.

---

## References

- `docs/AUTOPILOT-RUN-AUDIT-2026-08-08.md` §F1 (the measurement), and its Wave 1 R1/R2/R3.
- `PROJECT.md` Phase 12, Wave 1.
- ADR-0083 (#206) — fence contracts; the mechanism whose premise this defect breaks.
- ADR-0107 (#281) — the fence-contract population; why a declaration that is true and unchecked
  reads exactly like one that is verified.
- ADR-0086 — extract only when two copies giving different answers would be a defect. Applied in
  both directions here: §D2 extracts the `[~]` program, §D6 and §A6 keep the guard a copy.
- ADR-0069 (#172) / ADR-0070 (#184) — one shared predicate, loaded and never pasted.
- ADR-0089 (#239) and ADR-0102 (#233) — the two shipped fixes this defect reintroduces at render
  time.
- ADR-0129 (#365) — the run bound `autopilot`'s corrupted parser would have discarded.
- ADR-0076 §THE RULE / ADR-0090 (#258) — a check that did not run must not read as a check that
  found nothing; the source of §D4's exit-3 contract.
- ADR-0043 (#93) — a check's direction: `check_complete` validates the entries a list holds and is
  blind to a file the list omits. The reason §D6 partitions and §Consequences names the
  `skills/*/scripts/` blind spot.
- ADR-0108 (#284) — the plant registry, and why the four moved plants must be re-verified rather
  than re-declared.
- ADR-0122 (#291) — the plant sandbox copies only `staging/` and `docs/`; the `RG1` class.
- ADR-0113 (#331) — `docs-ci.yml`'s named list and the `CI0`/`CI1` guard that now enforces the
  append.
