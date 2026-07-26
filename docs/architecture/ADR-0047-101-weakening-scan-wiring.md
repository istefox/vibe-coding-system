# ADR-0047 — Wire the anti-test-weakening detector into every unattended path

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #101 (second feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/101-wire-the-anti-test-weakening-detector-in.spec.md`
- **Builds on:** ADR-0046 (#100) — this feature adds the third reporter to the `Pre-commit findings`
  block that ADR-0046 §D9 built as "a named, extensible list".
- **Supersedes:** nothing. **Amends:** nothing.
- **Explicitly untouched:** `staging/plugin/skills/review-triage-fix/` in its entirety —
  `SKILL.md`, `scripts/weakening-scan.sh`, `tests/run-tests.sh`. Not one byte. See §D1 and §D9.

## Context

`weakening-scan.sh` has existed since the review-triage-fix skill was built. It takes a unified
diff on stdin and prints `CLEAN`, or one `WEAKENED<TAB><file><TAB><reason>` line per finding, for
four behaviours: a deleted test file, an added skip/xfail marker, more assertions removed than
added, and a test function removed with none added. It always exits 0.

It fires in exactly one place: inside `review-triage-fix` Step 3's per-fix loop, feeding CIRCUIT
BREAKER B. `review-triage-fix` is a skill a human invokes, and in the `concept-to-code` chain it is
reached only through Gate 5, whose **autopilot default is "Skip review"**. So on the three paths
that can produce a commit with no human present — `concept-to-code` in autopilot, `autopilot-build`,
`nightly-autopilot` — the detector never runs at all. An agent that deletes a failing test to turn
the suite green produces a green `step5-report.json`, a green commit, and on the nightly path a
pushed branch with an open PR. Nothing in the pipeline looks at the tests themselves.

That is the gap. Three things shape how it gets closed.

**The detector is a heuristic, and it stays one.** Its own header says so: "Heuristic on purpose
(design §7-B). No auto-revert." Issue #105 adds `SUSPECT` detectors to it and is a separate feature;
this one changes no line of the script. What changes is *who calls it* and *what a caller does with
a finding*.

**Blocking is the caller's job, and the caller has to be told how.** The script always exits 0, and
it prints the sentinel `CLEAN` when it finds nothing. Both facts are traps for a caller written by
analogy with ADR-0046's two reporters, which exit 0 on a completed scan but print **nothing** when
they find nothing. ADR-0046 §Consequences flagged this divergence by name and said "#101, which
calls all three, must not assume one convention". §D3 below is the discharge of that warning.

**The three unattended paths are not three independent orchestrators.** `nightly-autopilot`
delegates its per-feature loop to `project-conductor nightly`, which delegates each feature to
`concept-to-code` in autopilot mode. `autopilot-build` reuses c2c's Step 5–7 mechanics by reference.
So a single gate placed at the c2c Step 5 → Step 6 boundary is inherited by all three, and the work
on the other two is to make the inherited halt *visible* in their own reports and markers, not to
re-implement detection. §D6 and §D7 are that work, and they are deliberately small.

## Decision

### D1 — The script is invoked where it lives; it is not moved, not copied, not symlinked

Every new call site invokes `<skills-root>/review-triage-fix/scripts/weakening-scan.sh` in place.

The alternative shapes all fail on something concrete:

- **Moving** it to `staging/plugin/scripts/` would require editing `review-triage-fix/SKILL.md` (two
  call sites), its harness anchor (`tests/run-tests.sh:128`, which greps for the literal
  `scripts/weakening-scan.sh`), and removing a `PAIRS` entry — and ADR-0024 fixed `PAIRS` as
  additive-only. It also breaks the one hard constraint this feature was given: `review-triage-fix`
  and its harness stay byte-identical.
- **Copying** creates a second source of truth, which this repository forbids outright, and the
  forbidding is not ceremonial here: issue #105 will edit the detector, and a copy would leave three
  of the four call sites running yesterday's heuristics with nothing to say so.
- **Symlinking** `staging/plugin/scripts/weakening-scan.sh` at the skill copy would be dereferenced
  by `sync-to-claude.sh`'s `cp -p` into a real second file at the destination — a copy with extra
  steps. ADR-0024 already skipped one foreign symlink (website-auditor) rather than reason about it.

**The coupling this creates is real and is named:** three skills now depend on a fourth skill's
private `scripts/` directory. It is not, however, novel. `autopilot-build/SKILL.md:78` and `:244`
already call `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` and
`manifest-transition.sh`. Cross-skill script dependency is an established pattern in this tree, and
the alternative to accepting it here is one of the three rejected shapes above. What the coupling
buys, beyond one source of truth: #105's new detectors reach all four call sites for free, with no
second edit and no version skew.

Consequence for the reader: `review-triage-fix` can no longer be renamed or deleted without
breaking three other skills. That is a fact about the tree after this ADR, and it belongs in the
Negative consequences rather than in a footnote.

### D2 — Script resolution: two-step, with an explicit "did not run" state

Every call site resolves the script with the same block, in the order ADR-0046 §D9 established from
`project-conductor/SKILL.md:44-47`:

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/review-triage-fix/scripts/weakening-scan.sh" ]; then
  _wscan="$CLAUDE_PLUGIN_ROOT/skills/review-triage-fix/scripts/weakening-scan.sh"
elif [ -f "$HOME/.claude/skills/review-triage-fix/scripts/weakening-scan.sh" ]; then
  _wscan="$HOME/.claude/skills/review-triage-fix/scripts/weakening-scan.sh"
else
  _wscan=""     # scan did not run — report it, do not infer a clean result
fi
```

Note the path shape differs from ADR-0046's: those two scripts deploy to `~/.claude/hooks/`, this
one to `~/.claude/skills/review-triage-fix/scripts/` (existing `PAIRS` entry, unchanged). A caller
that copies #100's block verbatim resolves nothing and silently skips the scan forever, which is why
the resolution block is pinned by the harness at every site rather than described once in prose.

**`_wscan` empty is fail-open, deliberately, and the reasoning is not "it is easier".** The house
convention is fail-open for advisory checks (ADR-0039) and fail-closed only for the publish guard
(ADR-0022 §D7), where "allowing an unchecked publish" is the dangerous direction. This check sits
with the former: it is a heuristic, not a security boundary, and the failure mode it protects
against is an agent taking a shortcut — the ADR-0045 framing, applied to a different substrate.
Failing closed would mean an entire overnight roadmap halts because one helper file is missing.
Against that, the probability of the "did not run" state is low by construction: the prose that
makes the call and the script it calls arrive on a machine through the same `sync-to-claude.sh`
run, so an un-resolvable script requires a partial sync.

The cost of fail-open is paid in visibility, not in silence: an unresolved script emits a line at
the call site and is recorded as `"weakening_scan": "unavailable"` in `step5-report.json`. That is
the ADR-0043 lesson — a check that reports nothing must never be indistinguishable from a check that
found nothing.

### D3 — How a reporter that always exits 0 produces blocking behaviour at the caller

This is the question the whole feature turns on, so it is answered as a rule, not as an example.

**The exit code carries no policy and the caller never reads it. The caller branches on the content
of stdout.** One idiom, used identically at every call site:

```bash
_wk=$(git diff "$_pre5" 2>/dev/null | bash "$_wscan" 2>/dev/null)
if printf '%s\n' "$_wk" | grep -q '^WEAKENED'; then
  # blocking path
fi
```

Three properties of that idiom are load-bearing, and each one is a mistake somebody would otherwise
make:

1. **`grep -q '^WEAKENED'`, anchored.** `grep -q` exits 0 on a match and 1 on none and prints
   nothing, so it composes into an `if` with no count string to mis-parse.
2. **Never `[ -n "$_wk" ]`.** The script prints `CLEAN` when it finds nothing, so the output is
   *never* empty and an emptiness test is always true. This is exactly the convention divergence
   ADR-0046 recorded: for `secret-scan.sh` and `dependency-scan.sh`, non-empty stdout means a
   finding; for this script it does not. A caller written by analogy blocks every single run.
3. **Never `n=$(… | grep -c '^WEAKENED' || echo 0)`.** `grep -c` prints `0` **and** exits 1 when
   there is no match, so the `|| echo 0` appends a second line and `n` becomes the two-line string
   `0\n0`, which then fails every numeric comparison. Issue #100 hit this. Where a count is genuinely
   needed for a report, the form is `n=$(printf '%s\n' "$_wk" | grep -c '^WEAKENED' || true)`.

The harness executes all three against the real script, including the negative one — an assertion
that proves `[ -n "$out" ]` is true on `CLEAN` output is what stops the trap being re-sprung by a
future edit.

### D4 — The input is the cumulative Step 5 diff, taken from a pre-dispatch mark

Before any Step 5 dispatch, alongside the existing pre-dispatch checks:

```bash
_pre5=$(git rev-parse HEAD 2>/dev/null)
```

After dispatch, the scan input is `git diff "$_pre5" 2>/dev/null` — which covers both committed and
uncommitted changes since the mark, i.e. everything Step 5 did, however the coder's worktree was
merged back. If `_pre5` is empty (no commits yet, or not a git repository) the input is
`git diff 2>/dev/null`, which is empty there, and an empty stdin makes the scan print `CLEAN`. The
SPEC's "a non-git or empty diff must not error" is satisfied by the awk program's own behaviour, not
by a guard the caller has to remember.

Two properties of `git diff` shape what is and is not covered, and both are correct here:

- A **deleted** test file appears with its `deleted file mode` line, which is the strongest single
  signal the detector has.
- An **untracked, brand-new** file does not appear at all. Adding a test is not weakening, so the
  blind spot is aligned with the threat. It is the same asymmetry ADR-0046 §D9 recorded for the
  dependency gate, and it is recorded again rather than assumed known.

### D5 — The gate lives at the c2c Step 5 → Step 6 boundary, and the orchestrator runs it itself

A new `#### Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)` block in
`concept-to-code/SKILL.md`, immediately after the `step5-report.json` read contract. Both dispatch
paths reach it.

**The orchestrator runs the scan. The dispatched agent's report is not the gate.** This is not
suspicion for its own sake: the agent whose work is being examined for test weakening is the one
that would be reporting on it, and `review-triage-fix` Step 3 already codifies the answer — "re-run
verification yourself (do not trust the agent's self-report for the breakers)". The same sentence
governs here. The `weakening_findings` array in `step5-report.json` is a **record** written by
whoever writes the report; the orchestrator's own scan is the **gate**. If the two disagree — an
empty array and a `WEAKENED` line — the orchestrator's result wins and the disagreement is itself
reported.

**Where it runs on each path,** because the two dispatch mechanisms genuinely differ and pretending
otherwise is how ADR-0039 nearly mis-specified its checkpoint:

- **Workflow path:** once, after the workflow script exits and the report is read. The workflow runs
  to completion with no orchestrator-visible mid-run checkpoint, and making the scan a `pipeline()`
  stage would hand detection back to a subagent, which §D5 just rejected.
- **Agent-tool batch fallback:** at *every* batch checkpoint (where `verify.sh` and `git status`
  already run) and again at the final boundary. It is the same command against the same cumulative
  diff with the same policy, evaluated at more points — one rule, not a second policy. An unattended
  run that weakens a test in batch 1 then stops before burning batches 2..N.

**Policy, both paths:** any `WEAKENED` line is a **failure signal**, in the precise sense the read
contract already gives that term for `tasks_failed` and `test_result: "red"`. Attended: present the
findings and do **not** transition to `step_6_review` without user acknowledgment. Autopilot
(`manifest.autopilot = true`): halt — do not transition, do not proceed to Gate 5.

The deliberate contrast, stated in the read contract next to the existing sentence it mirrors:
`checkpoint_reviews` is **never** a failure signal (ADR-0039); `weakening_findings` **always** is.
Two arrays in one schema with opposite gate semantics is the kind of thing that gets conflated six
months later, so both sentences sit in the same block.

### D6 — `step5-report.json` gains `weakening_findings`, additive, no schema bump

```json
"weakening_findings": [
  { "file": "tests/test_billing.py", "reason": "deleted-test-file" }
],
"weakening_scan": "ran | unavailable"
```

`file` and `reason` are fields 2 and 3 of the script's own TAB-separated line, unmodified. Absent
means none, and every report written before this change stays valid and readable — the same additive
discipline ADR-0016 used for `step5_mode` and ADR-0039 for `checkpoint_reviews`, and the reason no
schema version bump is required. The orchestrator read contract gains one bullet, and the malformed
check (`step5_mode` and `tasks_completed` must be present) is unchanged, so a missing
`weakening_findings` key never makes a report malformed.

`weakening_scan` is the §D2 visibility field. It is the difference between "scanned, nothing found"
and "never scanned", which is the whole of ADR-0043's lesson expressed in one string.

No manifest change: no new field, no invariant in `manifest-validate.sh`, no new transition pair, no
new gate letter. The blast radius stays inside the report schema and four SKILL.md files.

### D7 — `autopilot-build`: one circuit-breaker bullet at Step 5, one at Step 6

Step 5's existing circuit breaker reads `step5-report.json` and halts on three conditions. A fourth
joins them, in the same shape:

- `weakening_findings` non-empty, **or** the orchestrator's own scan prints a `WEAKENED` line →
  halt, `status=partial`, `abort_reason="test weakening detected in Step 5"`. Skip Steps 6 and 7,
  jump to the morning report.

Step 6 gets a second, different bullet, and it exists because of a gap found while writing this ADR
rather than because the SPEC asked for it. `review-triage-fix` runs inside `autopilot-build`'s Step
6, and its CIRCUIT BREAKER B *does* fire there — but breaker B's defined behaviour is to mark the
finding `UNRESOLVED — test weakened` and raise a BLOCKER flag **in the recap**, deliberately without
reverting anything. `autopilot-build`'s Step 6 breaker only inspects the test colour, so a weakening
introduced by the *fix* cycle is flagged in prose that nothing reads and then committed. So:

- Any anti-test-weakening BLOCKER in the review-triage-fix recap → halt, `status=partial`,
  `abort_reason="test weakening flagged by review-triage-fix in Step 6"`.

This consumes a signal that already exists rather than running a second scan, which keeps the SPEC's
"must not be called twice in one cycle" edge case intact, leaves breaker B exactly as written, and
brings `autopilot-build` in line with `nightly-autopilot`, which has halted on an `rtf-blocker`
marker since ADR-0022.

`autopilot-report.json` gains `weakening_findings: []`, additive, no `schema` bump — same rule as
§D6, same precedent.

### D8 — `nightly-autopilot`: documentation of an inherited halt, not a fourth call site

The per-feature loop is `project-conductor nightly`, which runs each feature through `concept-to-code`
in autopilot. A §D5 halt therefore means the chain never reaches `completed`; the conductor's branch
C already fires on exactly that, writes `build-status` RED and a run-level `needs-human` marker, and
`nightly-guard.sh` then blocks that publish **and every subsequent one**, because the halt markers
are run-level by design.

So the nightly path is already blocked by the c2c gate, through machinery that predates this
feature. What `nightly-autopilot/SKILL.md` gains is the marker contract stated explicitly — a
weakening halt in a feature's Step 5 surfaces as `needs-human`, stops the roadmap rather than
skipping one feature, and is recorded in `guard_halts[]` in the morning report.

**`project-conductor/SKILL.md` is not modified.** Branch C's generic marker already produces the
run-level halt; the specific reason reaches the human through `step5-report.json` and the morning
report. Adding a conductor branch for this one cause would widen the blast radius from four files to
five to make a report line marginally more specific. Recorded as a decision so a reviewer does not
read the absence as an oversight.

### D9 — `commit` Step 1 gains the third reporter; `WEAKENED` is advisory attended, blocking unattended

ADR-0046 §D9 built the Step 1 reporter block and §D4's `Pre-commit findings` list to take a third
entry without restructuring. This is that entry:

```bash
weakening_findings=""
if [ -n "$_wscan" ]; then
  weakening_findings=$(git diff HEAD 2>/dev/null | bash "$_wscan" 2>/dev/null)
fi
```

It reuses the `git diff HEAD` that `dependency-scan.sh` is already given in that block, so the
commit path costs one extra awk pass and no extra git invocation.

Policy:

- **Attended: advisory.** `WEAKENED` lines render in the Step 4 `Pre-commit findings` block and stop
  nothing. A human is about to look at them and click, and the SPEC is explicit that a legitimate
  test deletion (a removed feature) is *reported*, never auto-resolved. The Step 4 template's
  rendering line changes from "the SECRET and NEWDEP lines" to "the SECRET, NEWDEP and WEAKENED
  lines" — that one phrase is the whole UI change.
- **`--autopilot`: aborts the commit,** prints the findings, exits without committing. Step 4 is
  skipped there, so the gate cannot be what catches it, and this is an unattended path in the sense
  SPEC objective 2 means. It sits alongside `SECRET` aborts / `NEWDEP` proceeds, and it is the third
  net behind §D5 and §D7 rather than the first.

The commit call site also covers a path nothing else does: the **Express and Hybrid** chain paths
(Steps E2/E4 and H3/H5) have no Step 5, no `step5-report.json`, and no `autopilot-build`, and they
reach a commit through this skill. Without §D9 they would be the one uncovered route to a commit,
which is why the SPEC lists four call sites and not three.

### D10 — Registration, and why nothing needs a new `PAIRS` entry

- **No new script,** so no new `PAIRS` entry. `weakening-scan.sh` has had one since it was vendored
  (`plugin/skills/review-triage-fix/scripts/weakening-scan.sh|…`), and all four modified SKILL.md
  files are already covered — verified by reading the `PAIRS` heredoc, not assumed. The harness
  asserts the detector's entry is still there as a forward guard: this feature makes three more
  skills depend on that one line reaching `~/.claude`.
- **One new harness,** `staging/plugin/scripts/tests/weakening-wiring.test.sh`, registered in
  **both** registries: `ci.yml` picks it up by glob, `docs-ci.yml` needs an explicit append to its
  named list. It gets **no** `PAIRS` entry, matching every harness added since ADR-0041. As in
  ADR-0046 §D12, the registration assertion lives inside the harness it registers, so the file
  cannot go green while unregistered.
- **Assertion labels are prefixed `W`** (`WA1`, `WC3`, `WF2`, …). `secret-dep-gate.test.sh` already
  uses bare `F1`–`F6` and both files print into the same CI job; identical labels from two harnesses
  in one log is a diagnosis problem waiting to happen.
- **`workflow-dispatch-pins.test.sh` is not extended.** `autopilot-build` will name one more c2c
  heading, which is precisely that harness's subject, but the one-file-per-issue hermetic pattern
  (ADR-0028) wins: the new harness carries an equivalent uniqueness assertion for the new reference.
  Disclosed rather than left to be noticed — the same invariant is now enforced from two files.
- **The new gate is a `####` heading, uniquely named,** so it can be referenced by name from
  `autopilot-build` per ADR-0018's "name headings, not line ranges". No existing heading is renamed;
  `workflow-dispatch-pins.test.sh` B4a/B4b/B5 pin two Step 5/Step 6 heading strings and the absence
  of an old shared one, and all three survive untouched.

## Alternatives considered

**A1 — Put the scan inside `review-triage-fix` and call RTF from the unattended paths instead.**
Rejected on two independent grounds. RTF is a full review→triage→fix→re-review cycle costing 5–10
minutes and several agent dispatches; running it purely to get one awk pass over a diff is
absurdly disproportionate. And c2c Gate 5's autopilot default is "Skip review" precisely because
the cycle is expensive — flipping that default to make this feature work would silently change the
cost profile of every unattended run, a decision far larger than the one being made here and one
that belongs to whoever wants to argue for it on its own merits.

**A2 — Enforce the gate in `manifest-transition.sh`: refuse the `step_5 → step_6_review`
transition when a weakening marker exists.** This is the only option that produces *enforcement*
rather than instruction, and it is genuinely attractive for that reason. Rejected on blast radius:
the helper is a 48-pair state machine whose pair count ADR-0028 had to independently recount and
reconcile across three places, it currently touches no git and no project tree, and making it
git-aware would give every chain a new failure mode on every transition. The honest position is
that this ADR ships an **instruction, not an enforcement** — the same distinction ADR-0016 addendum
25c drew for Step 6 Phase 3's write scope, and which ADR-0041 later closed with a dedicated hook.
The equivalent here would be a `PreToolUse` hook or a transition-time guard, it needs its own issue,
and nothing in this ADR should be read as claiming a subagent cannot route around the gate.

**A3 — Have the dispatched agent run the scan and report the result, with no orchestrator run.**
Rejected: the agent under examination would be the one reporting on itself, and `review-triage-fix`
Step 3 already resolved this exact question in the opposite direction for the same detector ("do not
trust the agent's self-report for the breakers"). The cost of the orchestrator running it is one awk
pass. It is also the cheaper design in practice: no dispatch-prompt change is strictly required for
the gate to work, so a truncated or non-compliant agent report cannot disable it.

**A4 — Move `weakening-scan.sh` to `staging/plugin/scripts/` beside the two ADR-0046 reporters,
for a uniform "all detectors live in one directory" story.** Genuinely tempting, and it is where the
script would live if it were being written today — #105 and #108 will both treat it as a peer of
`secret-scan.sh`. Rejected because the move requires editing `review-triage-fix/SKILL.md`, its
harness anchor, and a `PAIRS` entry (a removal, against ADR-0024's additive-only rule), and this
feature's hard constraint is that `review-triage-fix` stays byte-identical. Worth doing eventually,
as its own issue, at a moment when RTF is being touched anyway — noted here so the next person does
not conclude it was never considered.

**A5 — Copy the script into `staging/plugin/scripts/` and leave the RTF copy alone.** Rejected on
the repository's standing rule against a second source of truth, with a specific cost: #105 edits
the detector, and the copy would leave the three new call sites running the old heuristics with no
signal that they had diverged. A drifted copy of a *detector* is worse than no detector, because it
reports and is believed.

**A6 — Block on `WEAKENED` at the interactive `commit` gate as well, for consistency with the
unattended paths.** Rejected: the SPEC says the commit path renders findings in the Step 4 gate, and
a human is one click away from the decision. Blocking there would make the most common false-positive
case — deleting the tests of a feature that was legitimately removed — unresolvable without editing
the skill, since there is no suppression pragma (ADR-0046 §D11 and this feature does not add one).
The asymmetry is the design: block where nobody can judge, report where somebody can.

**A7 — Emit a machine-readable marker file from the scan and have the guard read it, rather than
branching in skill prose.** Rejected as a solution to a problem that does not exist on the nightly
path: `needs-human` is already written by the conductor on any feature that fails to reach
`completed`, the markers are already run-level, and `nightly-guard.sh` already blocks every
subsequent publish once one is set (§D8). Adding a fifth marker type would duplicate a working
mechanism, and every marker is a new file that has to be cleaned up on disarm.

**A8 — Scan at every batch checkpoint on the Workflow path too, by making it a `pipeline()` stage.**
Rejected for the reason in §D5: a pipeline stage runs as a subagent, which puts detection back
inside the thing being examined (A3), and ADR-0016's hook-propagation caveats apply to workflow
subagents in a way they do not apply to the orchestrator. The asymmetry between the two dispatch
paths — per-batch on the fallback, once at the boundary on the Workflow path — is a property of the
two mechanisms and is stated rather than papered over.

## Consequences

### Positive

- The detector fires on every path that can produce a commit, which was the point. The specific
  scenario that motivated the issue — an agent deleting a failing test to turn the suite green,
  overnight, ending in a pushed branch with an open PR — now stops at the Step 5 → Step 6 boundary
  with the finding in the morning report.
- One source of truth for the detector survives the wiring, so issue #105's new `SUSPECT` outputs
  reach all four call sites with no further edit and no possibility of version skew.
- The `Pre-commit findings` block gets its third and final reporter exactly as ADR-0046 §D9
  designed it: a human sees secrets, new dependencies, and test weakening in one list, at one click.
- Blocking is expressed once, as a rule (§D3), with all three failure modes of the naive
  implementation pinned by executed assertions — including the `CLEAN` sentinel trap that ADR-0046
  predicted this feature would hit.
- `weakening_scan: "ran | unavailable"` means a scan that never ran can never be read as a clean
  one, on any of the four paths.
- A gap nobody asked about is closed on the way past: weakening introduced by the *fix* cycle in
  `autopilot-build` Step 6 was flagged by RTF breaker B into a recap that nothing read, and is now a
  halt (§D7).
- Nothing in `review-triage-fix` moves, so CIRCUIT BREAKER B's behaviour is bit-for-bit what it was
  and its `$HOME`-coupled harness stays green without being touched.

### Negative

- **Three skills now depend on a fourth skill's private `scripts/` directory** (§D1). Renaming or
  removing `review-triage-fix` breaks `concept-to-code`, `autopilot-build` and `commit`, and only
  the harness's resolution assertions would say so. A4 is the eventual fix and is not this feature.
- **This is an instruction, not an enforcement** (A2). Every gate here is prose in a SKILL.md that a
  model is asked to follow. A subagent that ignores it, or an orchestrator that compacts the block
  out of context, is not stopped by anything. The harness pins that the *instruction* exists; no
  assertion in this repository can pin that it is obeyed.
- **The detector is heuristic, and the blocking paths now inherit its false positives.** A
  legitimately deleted test file, or a refactor that consolidates three assertions into one, halts an
  unattended run. There is no suppression pragma, by ADR-0046 §D11 which this feature does not
  reopen, so the only resolution is a human resuming interactively. On the nightly path the halt is
  run-level, so one false positive stops the remaining roadmap features too — the cost of the
  run-level marker design, inherited, not introduced.
- **The scan is fail-open when the script does not resolve** (§D2). A partially synced machine gets
  a visible `unavailable` and proceeds. Defensible for a heuristic, and wrong if anyone ever reads
  this gate as a security boundary. It is not one.
- **Two harnesses now assert on `autopilot-build`'s heading references** — `workflow-dispatch-pins`
  and the new file (§D10). Renaming the new c2c heading turns two files red, which is louder than
  necessary but never silent.
- **Four SKILL.md files change, and two of them are called by three skills each.** `commit/SKILL.md`
  is invoked by `concept-to-code` Step 7, `project-init` and `autopilot-build`; c2c Step 5 is reused
  by reference from `autopilot-build`. Every edit here is a cross-skill contract change, which is why
  the F-section of #100's harness exists and why this feature adds its own.
- **The new harness will itself be scanned** by `secret-dep-gate.test.sh` section D, which runs
  `secret-scan.sh` over `git ls-files` and fails if any content rule fires. Its fixture diffs must
  contain no key-shaped literal. Cheap to honour, invisible until CI says otherwise.

### Neutral

- One new file, four modified SKILL.md files, one line appended to `docs-ci.yml`. No new script, no
  new `PAIRS` entry, no `settings.json` wiring, no manual sync step, no hook.
- `step5-report.json` and `autopilot-report.json` each gain additive fields with no version bump —
  the same treatment ADR-0016 gave `step5_mode` and ADR-0039 gave `checkpoint_reviews`. Issue #103
  will add `tests_written_by` to the same schema on the same terms; the two are independent.
- `weakening_findings` is always a failure signal and `checkpoint_reviews` never is, in one schema.
  Both sentences live in the same block of the read contract so the contrast is read, not inferred.
- `project-conductor/SKILL.md` is unchanged (§D8), and `manifest-validate.sh`, the manifest schema,
  the gate letters and the transition pairs are all untouched.
- The `CLEAN` sentinel divergence between this detector and ADR-0046's two reporters is now
  permanent and load-bearing at four call sites. Unifying it would mean editing the detector, which
  is #105's territory and would break RTF's harness.

## References

- SPEC: `/Users/stefer/Developer/vibe-coding-system/SPEC.md`, and
  `docs/specs/101-wire-the-anti-test-weakening-detector-in.spec.md`
- Plan: `docs/superpowers/plans/2026-07-26-101-weakening-scan-wiring.md`
- The detector, unchanged: `staging/plugin/skills/review-triage-fix/scripts/weakening-scan.sh`
- Existing call site and CIRCUIT BREAKER B: `staging/plugin/skills/review-triage-fix/SKILL.md`
  (Step 3 — Route-fix)
- Reporter contract, `Pre-commit findings` list, `CLEAN`-divergence warning, filename traps:
  `docs/architecture/ADR-0046-100-secret-scan-dependency-gate.md`
- Downstream, read for forward compatibility: `docs/specs/105-reward-hacking-detectors-literal-asserti.spec.md`,
  `docs/specs/108-run-the-deterministic-checks-in-the-targ.spec.md`,
  `docs/specs/103-generator-verifier-separation-dispatch-t.spec.md`
- Additive report fields and the two dispatch paths: `docs/architecture/ADR-0016-dynamic-workflows-step5.md`
- Never trust the agent's self-report; `checkpoint_reviews` is never a failure signal:
  `docs/architecture/ADR-0039-early-coder-feedback.md`
- Unattended autonomy boundary and the run-level halt markers:
  `docs/architecture/ADR-0020-autopilot-build-skill.md`,
  `docs/architecture/ADR-0022-nightly-autopilot-goal.md`
- Instruction vs enforcement, and what closing that gap costs:
  `docs/architecture/ADR-0041-58-agent-write-scope.md`,
  `docs/architecture/ADR-0045-58-interpreter-wrapper-bypass.md`
- A check that reports nothing must not look like a check that found nothing:
  `docs/architecture/ADR-0043-93-pairs-completeness.md`
- `PAIRS` additive-only, one entry per file: `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md`
- Name headings, not line ranges: `docs/architecture/ADR-0018-deep-refactor-skill.md`
- One-file-per-issue hermetic harness: `docs/architecture/ADR-0028-32-manifest-helpers-guards.md`
