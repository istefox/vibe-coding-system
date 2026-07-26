# ADR-0048 — Requirement IDs in the SPEC, and a coverage check between SPEC, plan and tests

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #102 (third feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/102-requirement-ids-in-spec-and-a-coverage-c.spec.md`
- **Builds on:** ADR-0046 (#100) for the reporter output shape and the `grep -c` trap; ADR-0047
  (#101) for the Step 5 → Step 6 gate placement and the two-step script resolution.
- **Supersedes:** nothing. **Amends:** nothing.
- **Enables:** issue #103, which dispatches a `tester` agent briefed from these IDs. §D3 and §D6
  exist for that consumer and for no other reason.
- **Explicitly untouched:** `staging/plugin/skills/autopilot-build/`,
  `staging/plugin/skills/nightly-autopilot/`, `staging/plugin/skills/project-conductor/`,
  `staging/plugin/skills/commit/`, `staging/plugin/skills/review-triage-fix/`,
  `staging/plugin/skills/concept-to-code/scripts/manifest-*.sh`. See §D9 and §D10.

## Context

The chain produces three artifacts that are supposed to say the same thing three times: a SPEC's
success criteria, a plan's tasks, and a test suite. Nothing checks that they do. A requirement can
be written into `SPEC.md` at Step 1, quietly not decomposed into a plan task at Step 2, and never
tested at Step 5, and every gate in the chain still shows green — because every gate measures
whether the *plan* was executed, never whether the *SPEC* was.

The chain's own history is the evidence. ADR-0030 §3.3 records a SPEC clause ("consult the global
smoke-test record") that turned out to name something that did not exist; it was caught by an
architect reading carefully, not by any mechanism. ADR-0035 records a SPEC line that scoped a fix to
`find-skills` line 3, leaving the body prose broader than the frontmatter — again caught by a human.
Both were found. The interesting question is how many were not, and the honest answer is that the
system currently has no way to know.

Three constraints shape the design.

**The check must be invisible to 34 existing SPECs.** `docs/specs/` holds 34 files, none with a
requirement ID, and every one must keep passing. The SPEC is explicit that a SPEC with no IDs passes
**silently** — not "skipped with a warning", not "0 IDs, OK". This is the conditional-invariant
discipline `manifest-validate.sh` invariants 10–14 already use ("if present, validate; absent is
valid"), applied to a different substrate.

**`R-NN` collides with `ADR-NNNN` if the matcher is naive, and this repository is made of ADR
references.** Measured, not assumed: `grep -rE 'R-[0-9][0-9]' docs/specs/` matches 30+ of the 34
existing SPEC files, every one of them from the letter run in `ADR-0016`, `ADR-0047`, and so on. A
matcher without boundaries would report the entire corpus as ID-bearing on day one. §D2 is the
discharge of that.

**A third gate is landing at a boundary that already has two.** #101 put the anti-test-weakening
gate at the Step 5 → Step 6 exit last week. This one goes beside it. The two checks have opposite
caller idioms — one must never read the exit code, the other reads nothing else — and putting them
four lines apart in the same SKILL.md without saying so would be an invitation to copy the wrong
block. §D5 says so, at the call site, in the file.

## Decision

### D1 — The ID lives at the start of a success-criteria checklist item, and nowhere else

A requirement ID is the literal token `R-` followed by **exactly two digits**, zero-padded,
beginning at the text of a checklist item inside the SPEC's success-criteria section:

```markdown
## Success criteria
- [ ] R-01 — A SPEC with no `R-` IDs passes silently.
- [ ] R-02 — A duplicate ID is reported as an error.
```

Three properties, each chosen against a specific failure:

- **Two digits, exactly.** `R-1` and `R-001` are *not* IDs, and a checklist item starting with
  `R-` and a wrong digit count is a `MALFORMED` error (exit 3), not a silent non-match. A silent
  non-match is the ADR-0043 failure shape: the item looks enumerated to a human and is invisible to
  the checker. The two-digit cap means 99 requirements per SPEC. No SPEC in this repository has more
  than eight success criteria; a SPEC that needs a hundred has a decomposition problem this ADR is
  not going to solve.
- **At the start of the item text.** `- [ ] A SPEC with \`R-01\`,\`R-02\` and a plan covering only
  \`R-01\` fails` — an actual line from this feature's own SPEC — mentions two IDs and declares
  none. Position is what separates declaration from reference, and it is what lets this feature's
  own SPEC take the backward-compatibility path (§D8).
- **Scoped to the success-criteria section.** Recognized headings are `Success criteria`,
  `Acceptance criteria`, and `Definition of done`, matched case-insensitively at `##` or deeper, and
  the section ends at the next `#`/`##` heading. Scoping is what makes "unique within one SPEC"
  well-defined. It also opens a hole — a generator that emits IDs under an unrecognized heading
  yields zero IDs and passes silently, the gate quietly inert — and that hole is closed narrowly:
  a **well-formed ID at the start of a checklist item outside every recognized section** is exit 3
  with a message naming the headings that were looked for. Narrowly, because the broad version of
  that rule ("any `R-NN` anywhere") fires on this feature's own SPEC, which is prose.

The separator after the ID is free. The generators emit ` — `; the parser takes any of space,
`—`, `–`, `-`, `:`, `.`, `)`. Pinning a separator would make an em-dash-vs-hyphen edit break the
build, and that trade buys nothing.

### D2 — Matching is boundary-anchored on both sides, and this is the load-bearing detail

The token regex is:

```
(^|[^A-Za-z0-9_])R-[0-9][0-9]([^0-9]|$)
```

The **left** boundary is what makes `ADR-0047` not contain `R-00`; the **right** boundary is the
second, independent defence (`R-00` in `ADR-0047` is followed by `4`). Either one alone would be
enough for the `ADR-NNNN` case; both are present because `PR-01`, `VAR-01` and `ISSUE-R-013` are
each defeated by exactly one of them and not the other.

Verified against the corpus before the design was fixed, not after: with the boundary rule, the only
matches in all of `docs/specs/`, `docs/superpowers/plans/` and `staging/` are two lines in this
feature's own SPEC, both prose references. Without it, most of the corpus matches. The assertion
that re-runs this measurement lives in the harness (section RE) and is the single most valuable test
in the file — every other assertion tests a behaviour, this one tests that 34 unrelated documents
are still none of the checker's business.

### D3 — Coverage has two halves with different definitions, and both are named on failure

**Plan coverage.** An ID is plan-covered when the token appears on a *task line* of the plan file: a
checkbox item (`^[[:space:]]*[-*] \[[ xX]\]`) or a task heading (`^#{2,4}[[:space:]].*Task`). Not
"anywhere in the plan" — a plan preamble that lists the SPEC's IDs in a summary table would
otherwise satisfy the check without a single task citing one, which is precisely the drift being
detected.

**Test coverage.** An ID is test-covered when the token appears anywhere in a discovered test file:
name, function name, comment, or docstring. The SPEC says "by name or docstring mention"; language-
aware extraction of test names across bash, Python, Swift, Go and TypeScript is a parser project,
and the cheap version — the token appears in the file at all — has the same false-negative rate and
a bounded false-positive rate, because the token is boundary-anchored and appears in no other kind
of text (§D2).

**Discovery is by basename, and `.md` is never a test file.** The predicate is a narrowed sibling of
`weakening-scan.sh`'s own `is_test()`: `*.test.<ext>`, `test_*`, `*_test.<ext>`, `*Test(s).<ext>`,
`test-*.sh`, `run-tests.sh`, `*.spec.<js|ts|tsx|jsx>`. The `.md` exclusion is not tidiness. Run
`weakening-scan.sh`'s predicate against this repository and `docs/specs/102-…​.spec.md` matches
`\.spec\.[a-zA-Z]+$` — so with `--tests-root <project-root>`, the SPEC file itself would be
discovered as a test file, every ID it declares would be found in it, and **every SPEC would be
trivially test-covered by itself**. A checker that always passes is worse than no checker. The
exclusion is a `RD` assertion, with that sentence as its failure message.

On failure the output names *which half* was missing:

```
UNCOVERED	R-02	plan
UNCOVERED	R-03	tests
UNCOVERED	R-04	plan,tests
```

TAB-separated, prefix-first, matching `SECRET`/`NEWDEP`/`WEAKENED`.

### D4 — Exit codes carry the policy, and `--tests-root` is what makes the test half optional

```
spec-coverage.sh --spec <file> --plan <file> [--tests-root <dir>] [--list]
```

| exit | meaning | stdout |
| --- | --- | --- |
| 0 | every declared ID covered, **or** the SPEC declares no IDs | `COVERED	R-NN` lines, or nothing |
| 1 | at least one ID uncovered | `UNCOVERED	R-NN	plan\|tests\|plan,tests` |
| 2 | invalid invocation, unreadable file | nothing |
| 3 | structural error in the SPEC or plan | `DUPLICATE` / `MALFORMED` / `ORPHAN` lines |

`ORPHAN` is the SPEC's "an ID cited by a plan task that does not exist in the SPEC" — a plan task
citing `R-09` against a SPEC that declares `R-01`–`R-06`. It is exit 3 rather than exit 1 because it
is a defect in the *artifacts*, not a gap in the coverage, and the caller's remedy is different: an
uncovered ID means write the task, an orphan means someone renumbered.

Separating 1 from 3 is the whole reason exit codes and not stdout prefixes carry policy here.
`secret-scan.sh` established 2 = bad invocation and 3 = "believe nothing about this run"; this script
keeps 2 and repurposes 3 for "the inputs are malformed", which is the same instruction to the caller
in a different guise: do not read the coverage result, fix the artifact.

**`--tests-root` omitted → the test half is not evaluated at all.** The summary says
`tests=not-checked` and only plan coverage can fail. **`--tests-root <dir>` given with zero
discovered test files → every declared ID is uncovered in `tests`**, exit 1, with the discovery
count in the summary so the cause reads as "0 test files found under `<dir>`" rather than as a
mystery. That asymmetry is deliberate: omitting the flag is the caller saying "do not check this",
and passing a directory with no tests in it is the caller saying "check this" about a project that
has nothing to check with. Guessing which one the user meant is how a gate becomes untrustworthy.

### D5 — The gate sits beside #101's at the Step 5 exit, blocks, and states why its idiom differs

A new `#### Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)` block in
`concept-to-code/SKILL.md`, placed immediately **after**
`#### Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)` and **before**
`#### Fallback — Agent-tool batch dispatch (…)`. Unique heading, so `workflow-dispatch-pins.test.sh`'s
uniqueness discipline holds and a future skill can reference it by name (ADR-0018).

**It blocks.** The SPEC's word is "assert … before Step 6 closes", #101 established a blocking
idiom at this exact boundary, and the argument that makes ADR-0047's blocking uncomfortable does not
apply here. That gate blocks on a *heuristic*: a legitimately deleted test file halts an unattended
run and there is no suppression pragma. This one blocks on a *mechanical* fact — an ID is cited or
it is not — and its only false-positive class is "the coder implemented the requirement but did not
cite the ID", which is exactly the condition the feature exists to surface. Policy shape is copied
from ADR-0047 §D5 verbatim so the two read as one rule:

- **Attended:** present the uncovered IDs and do **not** transition to `step_6_review` without user
  acknowledgment.
- **Autopilot (`manifest.autopilot = true`):** halt — do not transition, do not proceed to Gate 5.
- **Exit 2, or the script does not resolve:** fail-open, visibly. Record
  `"status": "unavailable"` in `step5-report.json` and proceed. ADR-0047 §D2's reasoning applies
  unchanged: a missing helper is a partial sync, not a finding, and halting an overnight roadmap
  over one absent file is the wrong failure direction.

**It runs once, at the final boundary, on both dispatch paths** — not at every batch checkpoint the
way #101's does. Mid-run, an uncovered ID is the expected state: task 7 has not run yet, so the ID
task 7 satisfies is legitimately uncovered at the batch-2 checkpoint. Running it per batch would
produce a guaranteed failure on every multi-batch chain. The divergence from the adjacent gate is
stated in the block, because the two blocks are four lines apart and the next person to read them
will assume they behave alike.

**The caller reads the exit code, and the block says so in as many words:**

```bash
_out=$(bash "$_scov" --spec "$_spec" --plan "$_plan" ${_troot:+--tests-root "$_troot"} 2>&1)
_rc=$?
```

with this note beside it: *"This gate branches on the exit code. The anti-test-weakening gate
immediately above must never do that — `weakening-scan.sh` always exits 0 and signals through
stdout. Two adjacent gates, two idioms, on purpose: `spec-coverage.sh` is a checker with an
exit-code contract, `weakening-scan.sh` is a reporter that never decides policy. Do not copy one
block's branching into the other."* ADR-0046 predicted the reverse mistake and #101 had to discharge
it; this is the same warning pointed the other way, and it is pinned by an assertion rather than
left as prose someone can reflow away.

**Script resolution** is the two-step block from ADR-0047 §D2, with the skill-helper path shape:

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/spec-coverage.sh" ]; then
  _scov="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/spec-coverage.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/spec-coverage.sh" ]; then
  _scov="$HOME/.claude/skills/concept-to-code/scripts/spec-coverage.sh"
else
  _scov=""     # gate did not run — report it, do not infer a clean result
fi
```

`skills/concept-to-code/scripts/`, **not** `hooks/`. `~/.claude` has two script locations — skill
helpers under `skills/<name>/scripts/`, everything else flattened into `hooks/` — and a resolution
block copied from #100's two reporters resolves nothing and skips the gate forever. ADR-0047 §D2
recorded this trap in one direction; this is the same trap, and the harness asserts the path shape
rather than trusting the prose.

**Inputs at the call site:** `--spec <manifest.artifacts.spec>`, `--plan <manifest.artifacts.plan>`,
and `--tests-root <project_root>` — the project root, not a `tests/` guess, because discovery is by
basename and this repository's tests live at `staging/plugin/scripts/tests/`, which no fixed guess
list would find. `--tests-root` is **omitted** when `manifest.test_cmd_placeholder = true` or
`manifest.test_cmd_provisional = true`: a project that has declared it has no test command, or whose
tests are still intent, cannot be held to test coverage. That is ADR-0018's "no test-cmd =
report-only mode" applied to a narrower question, reusing a signal that already exists instead of
inventing one.

### D6 — Both generators emit IDs; the architect's plan template cites them; `--list` briefs the tester

- **`interview-driver/SKILL.md`** — line 13 names the SPEC sections in one sentence. It gains the
  enumeration requirement in the same register: success-criteria items are numbered `R-01`, `R-02`,
  … from the start of each item. The file is 13 lines and its whole character is brevity; this adds
  one sentence, not a section.
- **`spec-from-issue/SKILL.md`** — the template's `## Success criteria` placeholder becomes "…as a
  checklist, each item prefixed with a unique `R-NN` id starting at `R-01`", plus one guardrail
  bullet: **IDs are assigned to criteria the issue already states; an ID is never a reason to invent
  a criterion.** That bullet is not decoration. This skill's entire contract is that it never
  fabricates (ADR-0023 §D5), and "give every criterion an ID" is exactly the kind of instruction a
  model satisfies by producing more criteria.
- **`agents/architect.md`** — the Output Format's *Implementation plan* bullet gains: every task
  cites the requirement IDs it satisfies, in the form `### Task 3 — … (R-02, R-05)` or on a checkbox
  item; every ID declared by the SPEC must be cited by at least one task; never cite an ID the SPEC
  does not declare. Stated in the agent's own file because that is where the contract belongs —
  ADR-0035's lesson, learned when `claude-md-generator`'s missing contract was being papered over by
  a chain dispatch override.
- **`concept-to-code/SKILL.md` Step 2 dispatch** gains one line saying the same thing. Deliberate
  duplication, on the ADR-0039 precedent where both dispatch paths state a contract independently
  and a test pins them together: the deployed `architect.md` can be stale (§Risks), and the chain
  should not depend on which of the two files reached `~/.claude` most recently.

**`--list`** prints `R-NN<TAB><requirement text>` for each declared ID and exits 0, silent when
there are none. It exists for issue #103: a `tester` agent briefed from requirement IDs needs the
text of each requirement, and the alternative is #103 re-implementing this parser. One flag now
against a second source of truth later. Separator stripping for `--list` is done with `substr`/
`index` rather than a regex, because the em dash is a three-byte UTF-8 sequence and a bracket class
containing it is not portable across BSD and GNU awk.

### D7 — Output conventions, and the one place this script is deliberately silent

stdout is the machine channel: `COVERED`, `UNCOVERED`, `DUPLICATE`, `ORPHAN`, `MALFORMED`,
TAB-separated, prefix-first. stderr carries one summary line per run:

```
spec-coverage: 6 id(s) declared, 5 covered, 1 uncovered, tests-root=<dir|not-checked>
```

**Except on the no-IDs path, where both streams are empty and the exit is 0.** This is an explicit
divergence from ADR-0046 §D5's "the summary always goes to stderr, on every run", and it is the
SPEC's requirement, stated twice and in the brief a third time: silently, not "skipped with a
warning". The reasoning behind the divergence is sound rather than merely obedient — this is the
path 34 existing SPECs and every pre-ADR-0048 chain run take, and a per-run warning on the normal
case is how a check trains its readers to ignore it. The ADR-0043 concern ("a check that reports
nothing must not look like a check that found nothing") is answered by the fact that the *caller*
knows: c2c records `"status": "no-ids"` in `step5-report.json`, so the three states — no IDs,
covered, unavailable — remain distinguishable to anything reading the report, which is where a
human or a morning report looks. Silence is at the script's stderr only, never in the record.

### D8 — Backward compatibility is the hard gate, and it is asserted against the real corpus

A SPEC with no IDs produces no output and exit 0 (§D7). The assertion is not a fixture. Section RE
of the harness runs the checker over **every** `docs/specs/*.spec.md` and the repository's own
`SPEC.md`, and requires, for each: exit 0, empty stdout, empty stderr. 34 files, one loop, and the
failure message names the file that broke.

A fixture-only test would prove that a hand-written empty-ish SPEC passes. Only the corpus proves
that the thing this feature must not break is not broken, and the `ADR-NNNN` collision (§D2) is
precisely the kind of defect a fixture would never contain.

This feature's own SPEC is part of that corpus, and it declares no IDs — its success-criteria items
mention `R-01` mid-sentence and start with prose (§D1). So the #102 chain's own Step 5 exit takes
the backward-compatibility path. The feature does not bootstrap itself, and that is a property worth
naming rather than a gap: the first SPEC to carry IDs will be the first one written by a generator
that has been taught to emit them.

### D9 — No manifest field, no new invariant, no schema bump

`step5-report.json` gains one additive object:

```json
"requirement_coverage": {
  "ids_declared": 6,
  "uncovered": [ { "id": "R-02", "missing": "plan" } ],
  "status": "pass | fail | no-ids | unavailable"
}
```

`uncovered` non-empty → **failure signal**, the same term the read contract already gives
`tasks_failed`, `test_result: "red"` and `weakening_findings`. Absent means the gate did not write
one and is **not** malformed — the malformed check stays `step5_mode` + `tasks_completed`, unchanged.
Same additive discipline as `step5_mode` (ADR-0016), `checkpoint_reviews` (ADR-0039) and
`weakening_findings` (ADR-0047), and the same reason no version bump is needed.

**No manifest change.** No field, no invariant 15, no transition pair, no gate letter. The
conditional-invariant idiom from `manifest-validate.sh` 10–14 is copied as a *design pattern* into
the checker's no-IDs path — "if present, validate; absent is valid" — not as a fifteenth invariant.
There is nothing about this feature a manifest needs to remember: the ID set lives in the SPEC, the
citations live in the plan, and the outcome lives in the report. A manifest flag would be a fourth
copy of a fact that is already derivable from the first, and `manifest-set-flag.sh` is boolean-only
besides. Recorded as a decision so its absence does not read as an oversight.

### D10 — `autopilot-build` and `nightly-autopilot` are not modified

Both inherit the gate. `autopilot-build` reuses c2c's Step 5–7 mechanics by reference (ADR-0020) and
`nightly-autopilot` delegates through `project-conductor nightly` to c2c in autopilot mode, where
§D5's halt fires before either skill's own circuit breaker gets a turn. The chain never reaches
`completed`, the conductor's branch C writes the run-level `needs-human` marker, and
`nightly-guard.sh` blocks the publish — the machinery ADR-0047 §D8 already walked through, working
here for the same reason.

The SPEC's scope names one call site, and this ADR ships one. `autopilot-build`'s Step 5 circuit
breaker will not name `requirement_coverage` explicitly, so a report written by a *non-halting*
path would carry the field unread; that is a cosmetic gap in a state §D5 makes unreachable, and
closing it is a two-bullet edit that belongs to whoever next opens that file. Named here, not
silently omitted, on the ADR-0047 §D8 precedent.

### D11 — Registration: one new `PAIRS` entry, one new harness in both registries

- **`staging/sync-to-claude.sh` `PAIRS` gains one line:**
  `plugin/skills/concept-to-code/scripts/spec-coverage.sh|skills/concept-to-code/scripts/spec-coverage.sh`.
  It is required and nothing else would catch its absence: `pairs-completeness.test.sh`'s
  `check_complete` covers `plugin/agents/*.md`, `user/rules/*.md` and `plugin/skills/*/SKILL.md`,
  and is **blind to `plugin/skills/*/scripts/*`** by ADR-0024's deliberate scope. So the new
  harness carries its own `PAIRS`-entry assertion, and that assertion is the only thing standing
  between this script and ADR-0043's exact defect — a repo-side file whose edits never deploy, with
  nothing reporting it.
- **`staging/plugin/scripts/tests/spec-coverage.test.sh`**, registered in **both** registries:
  `ci.yml` globs `*.test.sh`, `docs-ci.yml` needs an explicit append to its named list (last entry
  today: `weakening-wiring`). The harness gets **no** `PAIRS` entry — harnesses do not deploy —
  and asserts its own absence from `PAIRS`, matching `secret-dep-gate`'s G3 and `weakening-wiring`'s
  WG3.
- **Assertion labels are `R`-prefixed** (`RA1`, `RD3`, `RG2`). Bare `A`–`G` are used by nine
  harnesses and `W` by `weakening-wiring`; all of them print into the same CI job, and an
  unqualified `D3: …` in that log identifies nothing.
- **The new harness's fixtures must contain no key-shaped literal.** `secret-dep-gate.test.sh`
  section D runs `secret-scan.sh` over `git ls-files`, so this file joins the scanned corpus the
  moment it is committed. No fixture path may contain `secret`, `credential`, `.env`, `.pem` or
  `.key` either — `protect-files.sh` denies writes to those, and a fixture the harness cannot create
  is a test that cannot run.
- **`workflow-dispatch-pins.test.sh` is not extended.** No skill references the new heading by name
  yet (§D10), so there is nothing for it to pin. The new harness carries the uniqueness assertion
  for the heading it introduces, on ADR-0047 §D10's one-file-per-issue reasoning.

## Alternatives considered

**A1 — Report-only: print uncovered IDs at the Step 5 exit and never block.** The tempting option,
and it is what a cautious reading of "backward compatibility is the hard gate" suggests. Rejected,
and the rejection is the central call of this ADR. A report nobody must act on is a report nobody
reads: the entire motivation for the feature is that requirements go missing *without anyone
noticing*, and a check whose failure mode is "a line in a report" reproduces that condition one
layer up. It is also the ADR-0047 §D7 lesson, already learned once in this codebase and at the same
boundary — RTF breaker B flagged test weakening into a recap that nothing consumed, so weakening
introduced by the fix cycle was flagged and then committed. The blocking risk that makes A1
attractive is the false-positive rate, and that risk is much smaller here than for #101's gate: this
check is mechanical, not heuristic, and its zero-ID path makes it inert for every existing project.
Blocking, with a silent no-op for anything that has not opted in, is strictly better than reporting
into a void.

**A2 — Enforce the coverage check in `manifest-transition.sh`, refusing the
`step_5 → step_6_review` transition.** The only option that produces enforcement rather than
instruction, and rejected for exactly the reason ADR-0047 A2 rejected it: the helper is a 48-pair
state machine whose pair count ADR-0028 had to independently recount across three places, it touches
no files outside the manifest today, and teaching it to read a SPEC and a plan would give every
transition in every chain a new failure mode. This ADR ships an **instruction, not an enforcement**.
A subagent that ignores the block, or an orchestrator that compacts it out of context, is not
stopped by anything here. Closing that gap means a `PreToolUse` hook or a transition-time guard,
which is its own issue — the ADR-0041 shape, applied to a different instruction.

**A3 — Free-form IDs (`REQ-AUTH-LOGIN`, or the criterion's own text as its key).** Rejected on
matching, not on aesthetics. Text-as-key breaks the instant anyone rewords a criterion, which is the
most common edit a SPEC receives. Free-form alphanumeric keys have no reliable boundary — the whole
of §D2 exists because a two-letter prefix already collides with `ADR-`, and an unconstrained prefix
space would collide with identifiers in the code being checked. `R-NN` is short enough to cite
inline in a task heading without noise and constrained enough to match with two anchors and no
false positives across a 34-document corpus. Verified, not assumed.

**A4 — Three digits (`R-001`), for headroom.** Rejected: it buys capacity for a SPEC that would be
unmanageable for other reasons, and it costs the `ADR-NNNN` immunity that makes §D2 work with a
single right-boundary rule. `R-004` inside `ADR-0047` would be a live collision under a three-digit
grammar, defeated only by the left boundary, halving the defence. The narrower grammar is the
stronger one here.

**A5 — Language-aware test-name extraction (parse `def test_*`, `func Test*`, `it(…)`, `ok "…"`).**
Rejected on cost and on honesty about the benefit. Five languages appear in the chain's target
projects and the shell harnesses in this repository do not use a test-function convention at all —
their "test names" are `ok "RD3: …"` string literals. A parser would have to special-case each, and
its output for the common case would be identical to the cheap version's, because a file that
mentions `R-03` in a comment and nowhere else is a file whose author was thinking about `R-03`.
Whole-file token matching has the same recall, a bounded false-positive surface (§D2), and no
per-language maintenance.

**A6 — Put the checker in `staging/plugin/scripts/` beside `secret-scan.sh` and
`dependency-scan.sh`, deploying to `~/.claude/hooks/`.** Rejected, and the SPEC names the other
location anyway. The two ADR-0046 reporters live there because issue #108 needs them runnable from a
plain shell in a target project's CI with no agent present. This checker's inputs are
`manifest.artifacts.spec` and `manifest.artifacts.plan` — chain artifacts — so it is a c2c helper in
the same sense `manifest-validate.sh` is, and it belongs beside its siblings. The cost of that
placement is the resolution-path trap §D5 warns about; the cost of the other placement would be a
detector directory holding one script that is not a detector.

**A7 — Have the coder agent self-report coverage in `step5-report.json` and skip the orchestrator
run.** Rejected on the same ground ADR-0047 A3 and `review-triage-fix` Step 3 settled: the agent
whose work is being examined would be the one reporting on it. Here the objection is sharper than
usual, because the thing being checked is whether the agent's own plan execution matched the SPEC —
a self-assessment with a direct incentive. The orchestrator's cost is one awk pass over three files.

**A8 — Retrofit IDs into the 34 existing SPECs so the gate is live everywhere immediately.**
Explicitly out of scope per the SPEC, and correctly so. Those 34 SPECs describe features that are
already shipped; assigning IDs to them would be archaeology producing citations that no plan or test
will ever gain, i.e. 34 documents that fail the gate the day they are annotated. The gate is for
SPECs written from now on, and the generators are what make that happen.

**A9 — Run the gate at every batch checkpoint, matching ADR-0047 §D5's fallback-path placement.**
Rejected on a fact about the check rather than a preference: mid-run, uncovered IDs are the correct
state. Task 7 has not executed at the batch-2 checkpoint, so the IDs task 7 satisfies are uncovered,
and the gate would fire on every multi-batch chain, every time. The two gates sit four lines apart
with different cadences, and §D5 says so in the file so the asymmetry reads as a decision.

**A10 — A `--strict` flag making the no-ID path a failure, so projects can opt into mandatory IDs.**
Rejected as speculative: no caller wants it today, the c2c call site would have to decide when to
pass it, and that decision would need a manifest field (§D9 declines to add one). The generators
emitting IDs is the mechanism that makes IDs universal, not a flag. Adding it later is one `case`
branch and one assertion, if anyone ever asks.

## Consequences

### Positive

- A requirement that never becomes a task, or a task whose requirement never becomes a test, stops
  the chain at the Step 5 exit with the ID named and the missing half named. That gap has been open
  since the chain existed and was previously closed only by a human reading carefully.
- Backward compatibility is proved against the real corpus, not a fixture: 34 SPEC files plus the
  repository's own `SPEC.md`, each asserted to produce exit 0 and two empty streams (§D8). The
  `ADR-NNNN` collision that would have broken all of them is measured by the same section.
- The `R-NN` grammar is small enough to cite inline in a plan task heading and constrained enough to
  match with no false positives across the whole repository — a property that was verified before
  the grammar was chosen, which is why §D4's three-digit alternative could be rejected on evidence.
- Issue #103 gets `--list` and does not re-implement the parser. One flag, designed against a known
  consumer, instead of a second SPEC reader six weeks from now.
- The two SPEC generators diverging on ID format is impossible to introduce quietly: both are
  asserted, and `spec-from-issue`'s no-fabrication guardrail is asserted alongside its template
  change, so "give every criterion an ID" cannot decay into "produce more criteria".
- Two adjacent gates with opposite caller idioms are documented as such **at the call site**, with
  the warning pinned by an assertion rather than left as prose. ADR-0046 predicted this class of
  mistake, #101 discharged it in one direction, and this closes the other.
- The blast radius is one new script, one new harness, four modified files and two registry lines.
  No manifest change, no schema bump, no hook, no `settings.json` wiring, no manual sync step.

### Negative

- **This is an instruction, not an enforcement** (A2). Every gate in this ADR is prose in a SKILL.md
  that a model is asked to follow. The harness pins that the instruction exists; nothing in this
  repository can pin that it is obeyed. Anyone reading the gate as a guarantee will be wrong in the
  same way ADR-0047 and ADR-0045 already documented for their own subjects.
- **The check measures citation, not implementation.** An ID cited by a task that does nothing, and
  mentioned in a test that asserts nothing, is fully covered. This is a drift detector, not a
  correctness proof, and its green result must never be read as "the requirement is met". Issue #105
  (literal-assertion detectors) is the feature that narrows this, and it is not this one.
- **Test coverage is whole-file token matching** (§D3, A5). An `R-03` in a comment at the top of a
  test file that tests something else counts. The false-positive direction is toward passing, which
  is the wrong direction for a gate, and it is accepted because the alternative is a five-language
  parser whose recall would be no better.
- **A blocking gate on a mechanical check still blocks.** A coder that implements a requirement
  perfectly and forgets to write `(R-04)` in the task heading halts an unattended run. The remedy is
  a one-line edit, but on the nightly path the halt is run-level (ADR-0022), so one missing citation
  stops the remaining roadmap features too. Inherited from the marker design, not introduced here,
  and real.
- **The gate is inert for a SPEC that puts its criteria under an unrecognized heading**, and the
  narrow escape hatch (§D1: a well-formed ID at the start of an item outside every recognized
  section is exit 3) only fires if IDs are present at all. A SPEC with a `## Requirements` section
  and no IDs is indistinguishable from a SPEC with no criteria. Three heading names are recognized;
  a fourth convention needs an edit here.
- **A fifth cross-file coupling arrives at the Step 5 exit.** `concept-to-code/SKILL.md` Step 5 now
  reads `step5-report.json`, runs `weakening-scan.sh`, runs `spec-coverage.sh`, and is reused by
  reference from `autopilot-build`. Every edit in that region is a cross-skill contract change, and
  the region is now long enough that a reflow is a plausible way to break something silently. Three
  harnesses (`step5-checkpoint-review`, `weakening-wiring`, and this one) assert into it, which
  makes a break loud but does not make the region shorter.
- **`architect.md` edits do not reach a running agent until `sync-to-claude.sh --apply` runs.** The
  file gained its first `PAIRS` entry only in ADR-0042; before that, PR #90's fix to the same file
  never deployed and nothing reported it (ADR-0043). The entry exists now, so the path is there, but
  the deployed copy stays stale until a human syncs — which means the next chain run's architect will
  not cite IDs unless that sync has happened. §D6's duplicated line in the c2c Step 2 dispatch is the
  hedge against exactly this, and the hedge is a duplication with its own drift risk.
- **`.md` is hard-excluded from test discovery** (§D3). A project that genuinely tests through
  markdown — a literate-testing or doctest-in-docs setup — gets zero test coverage credit and no
  explanation beyond the discovery count in the summary. Chosen because the alternative is a checker
  that passes itself, but it is a real limitation for a real (if rare) project shape.

### Neutral

- One new file under `staging/plugin/skills/concept-to-code/scripts/`, one new harness, four modified
  files (`concept-to-code/SKILL.md`, `interview-driver/SKILL.md`, `spec-from-issue/SKILL.md`,
  `agents/architect.md`), one `PAIRS` line, one `docs-ci.yml` name.
- `step5-report.json` gains an additive object with no version bump — the fourth time this schema has
  been extended on those terms (ADR-0016, ADR-0039, ADR-0047, now). The malformed check is unchanged.
- This feature's own SPEC declares no IDs, so the #102 chain's Step 5 exit takes the
  backward-compatibility path (§D8). The feature does not dogfood itself, deliberately: the first
  ID-bearing SPEC will be produced by a generator, which is the mechanism being installed.
- `manifest-validate.sh`, the manifest schema, the gate letters and the 48 transition pairs are all
  untouched. The conditional-invariant idiom is borrowed as a pattern, not extended as an invariant.
- Silence on the no-ID path is a deliberate divergence from ADR-0046 §D5's always-summarize rule
  (§D7). Two scripts in the same system with different stderr conventions, recorded so the next
  reader does not "fix" one to match the other.
- `--tests-root` is omitted by the c2c call site whenever `test_cmd_placeholder` or
  `test_cmd_provisional` is true, which couples this gate to two manifest fields it does not own.
  Read-only coupling, no new field.

## References

- SPEC: `/Users/stefer/Developer/vibe-coding-system/SPEC.md`, and
  `docs/specs/102-requirement-ids-in-spec-and-a-coverage-c.spec.md`
- Plan: `docs/superpowers/plans/2026-07-26-102-requirement-ids-coverage.md`
- The adjacent gate, its placement, resolution block and blocking idiom:
  `docs/architecture/ADR-0047-101-weakening-scan-wiring.md`
- Reporter output shape, the `grep -c` trap, the always-summarize convention this ADR diverges from:
  `docs/architecture/ADR-0046-100-secret-scan-dependency-gate.md`
- Conditional-invariant idiom (invariants 10–14):
  `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh`
- Test-file predicate this ADR narrows, and the `.spec.md` match that motivated the `.md` exclusion:
  `staging/plugin/skills/review-triage-fix/scripts/weakening-scan.sh`
- Additive report fields, two dispatch paths: `docs/architecture/ADR-0016-dynamic-workflows-step5.md`
- Never trust the agent's self-report: `docs/architecture/ADR-0039-early-coder-feedback.md`
- A check that reports nothing must not look like a check that found nothing; `PAIRS` completeness
  and its blind spot for `skills/*/scripts/`: `docs/architecture/ADR-0043-93-pairs-completeness.md`
- Contract belongs in the agent's own file, not in the dispatch override:
  `docs/architecture/ADR-0035-39-skill-text-corrections.md`
- `architect.md`'s `PAIRS` entry and why it did not exist before:
  `docs/architecture/ADR-0042-91-architect-git-grant.md`
- No test-cmd = report-only mode: `docs/architecture/ADR-0018-deep-refactor-skill.md`
- Headless generator that must never fabricate: `docs/architecture/ADR-0023-nightly-auto-design.md`
- Instruction vs enforcement, and what closing that gap costs:
  `docs/architecture/ADR-0041-58-agent-write-scope.md`
- Unattended halt markers, run-level by design: `docs/architecture/ADR-0022-nightly-autopilot-goal.md`,
  `docs/architecture/ADR-0020-autopilot-build-skill.md`
- Name headings, not line ranges: `docs/architecture/ADR-0018-deep-refactor-skill.md`
- One-file-per-issue hermetic harness: `docs/architecture/ADR-0028-32-manifest-helpers-guards.md`
- `PAIRS` additive-only, one entry per file, selective skill vendoring:
  `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md`
- Downstream consumer of `--list`: `docs/specs/103-generator-verifier-separation-dispatch-t.spec.md`
