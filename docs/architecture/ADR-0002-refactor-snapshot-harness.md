# ADR-0002 — Behavior-preservation Snapshot Harness for the refactorer agent

**Status:** Accepted  
**Date:** 2026-05-20  
**Author:** istefox  
**Supersedes:** none  
**Superseded by:** none  
**Related:**
- `docs/superpowers/specs/2026-05-20-refactor-snapshot-harness-design.md`
- `docs/superpowers/plans/2026-05-20-refactor-snapshot-harness.md`
- `~/.claude/agents/refactorer.md` (primary modification target)
- `~/.claude/skills/review-triage-fix/SKILL.md` (v1.2 Add+Remove rule — not modified)
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (anchor harness target, PASS=43 post ADR-0001)
- `~/.claude/hooks/approve-test-cmd.sh` (TOFU + 3-tier for `.claude/test-cmd` — contract reuse)
- `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (Accepted 2026-05-20, orthogonal)
- Memory `feedback_bash32-constraint.md` (hard constraint for harness)
- Memory `feedback_micropiano-refactor-cleanup.md` (cycle 2 MAJOR caused by blind refactor; rationale)

---

## 1. Context

The `refactorer` sub-agent (`~/.claude/agents/refactorer.md`, Sonnet, tools `Read, Edit, Glob,
Grep, Bash`, yellow color) currently has a purely prosaic behavior-preservation contract: "Make
behavior-preserving changes only. Run the existing test suite and record the baseline (must be
green to start). Re-run tests; confirm identical results." The check is a boolean (green -> green)
and does not catch silent regressions where the test suite stays green *because it is incomplete*
but the observable behavior changes (differently formatted output, identical exit code but
silently altered stdout, recomposed error message).

Three converging pieces of evidence motivate the intervention:

1. **User memory.** The `refactorer` is today the **least used** sub-agent in the system.
   The explicit reason (memory + brief): the user does not trust delegating non-trivial refactors
   because there is no *empirical* guarantee of non-regression behavior-preservation. The
   green->green check is necessary but not sufficient.

2. **Cycle 2 of `pricing-markup-cli` (MAJOR M-1).** A fixture consolidation refactor had
   *added* behavior (autouse duplication). The refactor passed the green->green check because
   both fixtures did the same work (apparent idempotency), but the *blast radius* showed 2
   fixtures instead of 1. A snapshot-based behavior-preservation check would have caught the
   delta in the runtime layer (same output but more side effects in the transcript), or would
   have required the refactorer to explicitly state REPLACE pre-edit (orthogonal to ADR-0001).

3. **Pattern v1.2 + ADR-0001 deployed today (2026-05-20).** These are two interventions on the
   same problem (intent vs code drift) from the coder side. The refactorer is the *third angle*:
   implicit drift (silent regression) rather than explicit (intent mismatch). Triple-angle
   coverage of the risk "code change does not correspond to declared intent".

### Architectural problem

The refactor is defined as "behavior-preserving" but the system has never *instrumented* this
property. The refactorer self-certifies via "tests green before, tests green after" — a weak
proxy. A **deterministic and inspectable** mechanism is needed that captures the observable
output of the code *before* the refactor, compares it after, and fails loudly if the difference
is non-zero.

### Direction

Introduce a **Behavior-preservation Snapshot Harness**: a bash 3.2-clean skill
(`~/.claude/skills/refactor-snapshot/`) that the `refactorer` agent invokes as a gate
in its Process. The snapshot is the textual output (stdout + stderr + exit-code) of the test
cases of the project, executed from the test command already contracted in `.claude/test-cmd`
(same file read by `~/.claude/hooks/approve-test-cmd.sh`). Non-zero diff => refactor
has changed behavior => refactorer stops and reports.

The objective is to **enable delegation of non-trivial refactors to the refactorer agent with
confidence**, unblocking the least used sub-agent in the system.

### Inherited constraints (HARD)

- **Anchor preservation harness `review-triage-fix`:** PASS=43 post ADR-0001
  (2026-05-20). Never decrease. Post-feature target: PASS=45 (+2 anchors on
  `refactorer.md` structural sweep — see Decision §2.7).
- **Bash 3.2.57** for every script in `~/.claude/`. No assoc array, no `mapfile`,
  no `${v^^}`, no `<()` process substitution. Pattern already consolidated by the 43
  anchors of the review-triage-fix harness and by the `verify.sh`, `weakening-scan.sh`,
  `triage-state.sh` helpers.
- **Coexistence with features deployed 2026-05-20:** ADR-0001 (Pre-flight Pattern
  Classifier for coder) + review-triage-fix v1.2 Add+Remove rule remain intact.
  Snapshot harness is **orthogonal** to both: it operates on the refactorer (post-edit
  verification), not on the coder/reviewer (pre-edit declaration / post-edit triage).
- **No backwards-compat shim:** changes to `refactorer.md` replace cleanly.
- **NON-git repo:** vibe-coding-system blueprint repo is non-git by user choice;
  `~/.claude/` is not git. Plan does not propose git operations. CI/CD integration of the
  target project is future scope.
- **Sub-agent identity unchanged:** `refactorer.md` remains Sonnet, tools unchanged
  (`Read, Edit, Glob, Grep, Bash`), yellow color.
- **Language:** system prompt + skill in English (contract); ADR/spec/plan in Italian;
  commits/code in English.

### Explicit assumptions (not empirically verified)

- The `.claude/test-cmd` contract (reuse from the TOFU hook) is available in the target projects
  where the refactorer is invoked. Verified for recent pilots (swarm-testcmd
  deployed 2026-05-19). Not verified for new projects.
- The textual output of the test command is sufficiently deterministic (no timestamps,
  no random IDs, no embedded absolute paths) to produce stable snapshots. For the
  non-deterministic case an explicit override exists (see Decision §2.8).
- The `refactorer` LLM (Sonnet) will follow the contract "pre-snapshot before edit, post-snapshot
  after edit, abort on non-zero diff" with the same fidelity with which it follows today
  "tests green before, tests green after". Plausible (the test-baseline discipline works);
  not verified for this exact sequence.
- The blast radius computed as "files modified in the edit + their callers via `grep -rln`"
  is a reasonable proxy for "relevant tests". Edge: indirect callers via reflection /
  dynamic dispatch not captured — accepted as MVP trade-off.

---

## 2. Decision

Introduce the **Behavior-preservation Snapshot Harness** as a bash 3.2-clean skill
`~/.claude/skills/refactor-snapshot/`, invoked by the `refactorer` agent as a gate
in its Process. Three-state outcome: PASS (empty snapshot diff), FAIL (non-zero diff,
refactor changes behavior), UNVERIFIED (test command absent / non-deterministic).
Triple-layer defense with the existing green->green check as secondary.

### 2.1 What a snapshot is (Q1)

**The snapshot is the textual output of the target project's test command.**

Concrete format of the snapshot file (`.claude/.refactor-snapshot.txt`):

```
EXIT=<exit-code>
STDOUT-SHA256=<hex>
STDERR-SHA256=<hex>
---STDOUT---
<full stdout>
---STDERR---
<full stderr>
```

Rationale:
- **Textual output** is the most direct proxy for observable external behavior
  (output) + correctness (exit code). Aligned with the current refactorer.md definition of
  behavior-preservation ("public outputs and side effects identical").
- **stdout/stderr/exit-code** is the canonical Unix process semantics triplet:
  stack-agnostic, no parsing.
- **SHA256** of the two streams is the fast baseline of the diff (a comparison of 2 hex
  values suffices for the primary PASS/FAIL; the full-text payload is preserved for
  diagnostics in case of FAIL).
- **Pure function return values** (Q1 sub-option) are *deferred* — they require
  per-stack scaffolding (Python importer, Swift runner) and duplicate existing test
  frameworks. Future scope if MVP proves insufficient.
- **AST signatures / call graphs** are *rejected* — fragile proxies (a legitimate refactor
  changes call graphs) and stack-locked (require a parser per language).
  See Alternatives §3.1.

### 2.2 Tool: build (bespoke bash) vs buy (Q2)

**CHOSEN: bespoke bash 3.2 harness `~/.claude/skills/refactor-snapshot/`.**

Selection criteria:

| Option | Multi-stack | Zero dep | Multi-agent integr. | Maint. cost | Verdict |
|---|---|---|---|---|---|
| pytest-snapshot / syrupy | Python only | No (pip dep) | Bridge needed | Medium | Reject |
| inline-snapshot | Python only | No (pip dep) | Bridge needed | Medium | Reject |
| jest snapshot | JS/TS only | No (npm dep) | Bridge needed | Medium | Reject |
| swift-snapshot-testing | Swift only | No (Swift Package) | Bridge needed | Medium | Reject |
| golden file pattern | Stack-agnostic | Yes | Mediated by agent | Low | Pattern, not tool |
| **Bespoke bash 3.2** | **Stack-agnostic** | **Yes** | **Native** | **Low** | **CHOSEN** |

Rationale:
- The multi-agent system is explicitly multi-stack (`~/.claude/skills/` contains
  `fastapi-react-vibe`, `swift-vibe`, `swiftui-pro`). Stack-locked tools require
  a matrix of adapters, against the "minimal moving parts" principle.
- Bespoke bash reuses the `.claude/test-cmd` contract already live (deployed 2026-05-19
  swarm-testcmd, validated cross-stack). Zero additional scaffolding for consumers.
- The golden file pattern is the one *adopted*, not a tool to install. Bespoke bash
  is its minimal implementation.
- Aligned with review-triage-fix style (3.2-clean, ok/bad helpers, anchor harness).
  Cognitive consistency for Stefano + for the agents.

Rejected alternatives detailed in §3.2.

### 2.3 Where snapshots live (Q3)

**CHOSEN: `.claude/.refactor-snapshot.txt` in the target project, gitignored.**

Rationale:
- **Per-project** (not centralized in `~/.claude/cache/`): traceability with the project,
  no race between worktree/parallel dispatches, lifecycle tied to the refactorer's work
  in the current checkout.
- **Gitignored** (not versioned): it is a transient artifact of the refactor cycle.
  Versioning it would pollute the repo with binary-like files that change on every run.
- **Single file `.refactor-snapshot.txt`** (not a per-test-case directory): simple MVP;
  the payload is already a bundle (full stdout/stderr). Per-test granularity is speculative
  — the blast radius (§2.4) already selects which tests to run.
- **Path identical to the v1.2 pattern `.claude/.triage-fix-last.json`**: same convention
  in the target repo for cross-cycle state files. Consistency with the already live pattern.
- The refactorer adds `.claude/.refactor-snapshot.txt` to `.gitignore` if the project is
  git (idempotent, identical to the `triage-state.sh` commit pattern). If non-git, no
  side effect (idempotent no-op).

Rejected alternatives (§3.3): versioned in repo (pollution), `~/.claude/cache/` external
(loses traceability, race condition).

### 2.4 Granularity: blast radius (Q4)

**CHOSEN: blast radius = files modified in the refactor + their direct callers via grep.**

Operational definition:
- Pre-edit: the refactorer declares the set of files it is about to modify (set $F$).
- Caller set $C$ = `grep -rln <module-name>` for each file in $F$, intersection with test
  files (path matching `test`, `spec`, `tests/`, `__tests__/`).
- Snapshot scope = test command executed with env var `RFS_FILTER` (see §2.7) to
  restrict to tests that import/use $F \cup C$. If the test command does not support
  filtering, fall back to full test command (overshoot accepted).

Rationale:
- **Per single test** (rejected): too fine, requires a parser to identify individual
  test cases in N different frameworks. Does not scale multi-stack.
- **Per module** (rejected): reasonable proxy but tied to "module" definition
  per-language. Toxic cross-stack.
- **Per entire project** (rejected): maximum overshoot. Refactoring 1 file requires
  re-running 1000 tests if the project is large. Prohibitive time.
- **Per blast radius** (CHOSEN): reasonable proxy, computable via stack-agnostic grep,
  bounded by the actual refactor work.

Edge: indirect callers (reflection, plugins, factory) not captured by static grep.
**Mitigation:** if the refactorer detects use of reflection/dynamic dispatch in the files in
$F$, escalate to "full project snapshot" (explicit override, env var `RFS_FULL=1`).
Audit trail: declaration in the refactor report "blast radius widened to full
because reflection detected in <file>".

### 2.5 Coverage check: which tests to run (Q5)

**CHOSEN: all project tests via `.claude/test-cmd` (default), with narrowing via
blast radius only if the refactorer declares problematic time overhead.**

Operational rationale:
- **All tests (default)**: safe overshoot, no stack-locked coverage tooling, direct
  reuse of the `.claude/test-cmd` contract already live.
- **Top-N coverage** (rejected): requires per-stack coverage tooling (pytest-cov,
  jest --coverage, swift coverage). Multi-stack matrix.
- **Tests that touch modified files** (rejected as default, admitted as opt-in narrowing):
  requires per-project coverage map. Not available by default.
- **AST-based heuristic** (rejected): stack-locked parser.

**Override for projects with slow tests:** the refactorer can declare `RFS_FILTER=<pattern>`
in the test command env to restrict (e.g. `pytest -k <module>`). Runtime decision by
the refactorer based on pre-snapshot baseline time (if >60s, consider filtering).

### 2.6 Updated TDD flow of the refactorer (Q6)

Replaces the "Process" section of `refactorer.md` with this sequence:

1. **Baseline check.** Execute `.claude/test-cmd`. If non-zero -> STOP, report "tests red
   at baseline, refactor unsafe". (Existing invariant, preserved.)
2. **Pre-snapshot.** Invoke `~/.claude/skills/refactor-snapshot/scripts/capture.sh PRE`.
   Writes `.claude/.refactor-snapshot.txt` with EXIT/STDOUT-SHA256/STDERR-SHA256/payload.
3. **Determinism check.** Re-run pre-snapshot N=2 more times (3 total). If SHA256 stdout
   or stderr changes between runs -> STOP, output `UNVERIFIED non-deterministic test output`,
   report to user with suggestion "investigate test flakiness or use RFS_OVERRIDE".
4. **Apply refactor.** Focused Edit (<=200 lines per pass, existing invariant preserved).
5. **Post-snapshot.** Invoke `capture.sh POST`. Writes `.claude/.refactor-snapshot.txt.post`.
6. **Diff.** Invoke `~/.claude/skills/refactor-snapshot/scripts/diff.sh`. Compares
   EXIT + SHA256-STDOUT + SHA256-STDERR. Output `PASS` if identical, `FAIL` if different.
7. **On FAIL.** STOP. Report to user with `loc=path:line` for each of the three deltas
   (exit/stdout/stderr) + `diff -u` extract of the payloads. Refactor is *not*
   committed (no-op relative to filesystem: the edit is already on disk, but the refactorer
   declares FAIL and recommends revert). HITL gate: the user decides whether to accept the
   change as "intentional behavior change" (and thus it was not a refactor) or reverse it.
8. **On PASS.** Refactor is behavior-preserving. Report success: `lines changed`,
   `tests passed`, `snapshot PASS`. Cleanup: remove `.claude/.refactor-snapshot.txt.post`
   (the `.refactor-snapshot.txt` remains as baseline for the next cycle, optional —
   in MVP we remove both for cleanliness, the choice is left to the plan).

Steps 1 and 4 are existing invariants of refactorer.md. Steps 2, 3, 5, 6, 7 are new.
Step 8 enriches the existing "Output Format".

### 2.7 Multi-language strategy (Q7)

**CHOSEN: stack-agnostic single harness, no per-stack adapter, automatic detection via
`.claude/test-cmd`.**

Rationale:
- The `.claude/test-cmd` contract (swarm-testcmd deploy 2026-05-19) is already the stack
  detection point: the target project declares its own test command (e.g. `pytest -q`,
  `npm test`, `swift test`). The harness does *not know* the stack — it executes the command and
  captures output.
- **Per-stack adapter** (rejected): would introduce a Python/JS/Swift/Go/Rust... matrix without
  proportional benefit. If in the future a single stack requires semantic snapshot
  (e.g. normalized JSON for JS), an optional helper can be added post-pilot.
- **Stack auto-detection** (rejected): attempting to guess `pytest` vs `npm test`
  via file presence is fragile and duplicates the work that `.claude/test-cmd` already does.

Future extensibility (out of MVP scope):
- Optional helpers `normalize-python.sh`, `normalize-js.sh` that pre-process stdout
  before the SHA256 (e.g. strip timestamps `\d{4}-\d{2}-\d{2}T...`). Hook via env var
  `RFS_NORMALIZE=<helper-path>`. Not MVP.

### 2.8 Failure mode + override (Q8)

Three harness outcome states:

| State | Meaning | Refactorer action |
|---|---|---|
| `PASS` | SHA256 stdout+stderr+exit identical pre/post | Refactor OK, report success |
| `FAIL` | SHA256 different on at least one of the three channels | STOP, report drift to user (HITL) |
| `UNVERIFIED` | Pre-snapshot non-deterministic (3 different runs) | STOP, report flakiness; override possible |

**Distinguishing bug vs stale snapshot:**

The determinism check (§2.6 step 3) is the discriminator. If the 3 consecutive pre-snapshots
produce identical SHA256 values -> snapshot deterministic, any subsequent drift is a refactor bug.
If the 3 pre-snapshots produce different SHA256 values -> snapshot is stale (flaky tests,
timestamp, random) -> `UNVERIFIED` with flag.

**Explicit override:**

File `.claude/refactor-snapshot-override` (optional, present only if user creates it
deliberately). Format:

```
REASON: <one-line justification>
SCOPE: <stdout|stderr|exit|all>
EXPIRES: <YYYY-MM-DD>
```

If present, the harness ignores the difference in the channels declared in SCOPE and
overrides to `PASS` with flag `OVERRIDE-ACTIVE`. Audit trail: the refactorer cites the file +
REASON in the report.

**No auto-override:** the file must be created by the user (HITL gate). The refactorer *never*
creates it. The refactorer can *suggest* creation in its FAIL report ("if the difference is an
expected timestamp, consider override with SCOPE: stdout").

**Audit trail:**

The file `.claude/.refactor-snapshot.txt` (pre-snapshot) survives a PASS as the baseline for
the next cycle (optionally — MVP cleanup removes both). In case of FAIL, the
`.refactor-snapshot.txt.post` file stays on disk for user inspection, and the refactorer cites
it in the report with absolute path.

### 2.9 Precise file changes

- **Create skill `~/.claude/skills/refactor-snapshot/`:**
  - `SKILL.md` — frontmatter + body with invocation contract.
  - `scripts/capture.sh` — bash 3.2, executes `.claude/test-cmd`, writes snapshot file.
  - `scripts/diff.sh` — bash 3.2, compares pre/post snapshot, exit 0/1/2 for
    PASS/FAIL/UNVERIFIED.
  - `tests/run-tests.sh` — bash 3.2, skill self-test harness (anchor preservation
    pattern, identical style to review-triage-fix).
- **Modify `~/.claude/agents/refactorer.md`:** replace the `## Process` section
  (current lines 25-31) with the §2.6 sequence (8 steps). Append section `## Snapshot
  Harness Integration` with reference to the skill. Update `## Edge Cases` with the
  entry "Snapshot UNVERIFIED — non-deterministic test output".
- **Modify `~/.claude/skills/review-triage-fix/tests/run-tests.sh`:** append new
  block `# --- Task 7: refactorer.md snapshot harness section ---` with 2 anchors on
  `refactorer.md` (presence of `Snapshot Harness Integration` literal + presence of
  `refactor-snapshot` skill reference). Cumulative PASS=43 -> PASS=45.

**Architectural note:** extending the `review-triage-fix` harness to read a third
file (`refactorer.md`, after `SKILL.md` and `coder.md` from ADR-0001) is consistent with the
precedent of ADR-0001 §3.3 (sub-question). The `review-triage-fix` skill already has authority
over the quality of the agents it dispatches (debugger, refactorer, coder); adding a structural
anchor on `refactorer.md` is natural.

### 2.10 Changes NOT made

- **NO modify `~/.claude/skills/review-triage-fix/SKILL.md`** — v1.2 Add+Remove rule
  remains. Orthogonal to the snapshot harness (coder rule, not refactorer).
- **NO modify `~/.claude/agents/coder.md`** — ADR-0001 Pre-flight Pattern Classifier
  unchanged. The coder does not use snapshots.
- **NO modify `~/.claude/agents/reviewer.md`** — Pattern-drift check ADR-0001 unchanged.
  The reviewer does not use snapshots directly (but can cite the refactorer report
  as evidence in review).
- **NO modify `~/.claude/agents/debugger.md`** — the debugger operates on bugs, not on
  refactors. Snapshot not applicable.
- **NO modify `~/.claude/hooks/approve-test-cmd.sh`** — the harness *reuses* the
  `.claude/test-cmd` contract but does not interact with TOFU. The file `.claude/test-cmd`
  must pre-exist and already be approved (TOFU + 3-tier deploy 2026-05-19); if absent,
  snapshot UNVERIFIED + abort.
- **NO modify `~/.claude/settings.json`** — no new hook, no new permission rule.
- **NO modify `.mcp.json`** — no new MCP.

### 2.11 Language

System prompt `refactorer.md` and skill files (`SKILL.md`, `capture.sh`, `diff.sh`,
`run-tests.sh`) in English (contract). ADR, spec, plan, memory entry in Italian.
Aligned with global rule "code and commits in English; text to user in Italian".

---

## 3. Alternatives considered

### 3.1 What a snapshot is (Q1)

**a) Textual test output (stdout/stderr/exit-code) (CHOSEN).** Stack-agnostic, direct proxy of
observable behavior, reuse `.claude/test-cmd`. Risk: non-deterministic tests (mitigated by
determinism check + override).

**b) Pure function return values** — *Rejected as MVP, deferred*. Requires per-stack scaffolding
(Python importer via `importlib`, Swift runner via `swift run`). Duplicates the existing test
framework. Possible post-pilot extension if MVP proves insufficient for edge cases (e.g.
library-only projects without integration tests).

**c) AST signatures** — *Rejected*. Legitimate refactors *change* the AST (extract method,
rename var, inline function). AST signature is a proxy misaligned with the definition of
behavior-preserving (preserves *behavior*, not *structure*). Stack-locked (requires a parser
per language).

**d) Function call graphs** — *Rejected*. Legitimately change in refactors (call graphs are
exactly the target of the refactor). Same problem as (c).

**e) Combination of (a) + (b) + (c)** — *Rejected as MVP*. Over-engineering. (a) is
sufficient for the MVP; subsequent extensions if pilot evidence requires it.

### 3.2 Tool: buy vs build (Q2)

**a) Bespoke bash 3.2 stack-agnostic (CHOSEN).** See table §2.2.

**b) pytest-snapshot / syrupy (Python)** — *Rejected*. Stack-locked (Python only).
Cross-stack adapter matrix prohibitive. Requires pip dep in target project.

**c) inline-snapshot (Python)** — *Rejected*. Stack-locked. Modifies the source of the
target project by inserting inline snapshots — invasive, non-removable without VCS.
Unsuitable for behavior-preservation gate (modifies the source that should remain identical).

**d) jest snapshot (JS/TS)** — *Rejected*. Stack-locked. Same problem as (b).

**e) swift-snapshot-testing (Swift)** — *Rejected*. Stack-locked. Requires Swift Package dep.
Unsuitable for Python/JS projects.

**f) Generic golden file pattern (Go-style)** — *Adopted as pattern, not as tool*.
The CHOSEN option (bash 3.2) *is* the minimal implementation of the golden file pattern.

### 3.3 Where snapshots live (Q3)

**a) `.claude/.refactor-snapshot.txt` per-project gitignored (CHOSEN).** Consistency
with `.claude/.triage-fix-last.json` (review-triage-fix). Lifecycle tied to the project.

**b) Versioned in target repo** — *Rejected*. Snapshot is transient (changes with every
refactor cycle). VCS history pollution with binary-like artifacts. Anti-pattern for golden
files (golden file *test fixture* yes, golden file *transient cycle artifact* no).

**c) `~/.claude/cache/refactor-snapshot/<project-hash>/`** — *Rejected*. External cache loses
traceability (who looks in `~/.claude/cache/` when the refactor fails?). Race condition with
parallel worktrees on the same project hash. Lifecycle decoupled from the project (when to clean?).

**d) `/tmp/refactor-snapshot-<pid>/`** — *Rejected*. Volatile (lost on reboot, on
dispatch session shutdown). Unsuitable for cross-cycle baseline.

### 3.4 Granularity (Q4)

**a) Blast radius = modified files + direct callers via grep (CHOSEN).** Bounded by actual
work, computable stack-agnostic, reasonable proxy.

**b) Per single test case** — *Rejected*. Requires a parser to identify test cases. Stack-locked.

**c) Per module** — *Rejected*. "Module" is a stack-specific concept (Python module vs
JS module vs Swift module). Toxic cross-stack.

**d) Per entire project** — *Rejected as default*. Time overshoot (re-running 1000 tests
to modify 1 file). Admitted as fallback override (`RFS_FULL=1`) for reflection cases.

**e) Per modified files (no caller expansion)** — *Rejected*. Too narrow: refactoring
file $f$ can break the behavior of callers of $f$, and the tests that test the callers
are the real gate.

### 3.5 Coverage check (Q5)

**a) All tests (CHOSEN as default).** Safe overshoot. Reuse `.claude/test-cmd`.

**b) Top-N tests by statement coverage** — *Rejected*. Stack-locked coverage tooling
(pytest-cov, jest --coverage). Matrix.

**c) Tests touching modified files (via coverage map)** — *Rejected as default,
admitted as opt-in narrowing*. Requires pre-computed coverage map. Not available by default.

**d) AST-based heuristic** — *Rejected*. Stack-locked parser.

### 3.6 TDD flow (Q6)

**a) 8-step sequence §2.6 (CHOSEN).** Explicit determinism check (step 3) and on-FAIL
HITL gate (step 7).

**b) Minimal sequence (baseline -> refactor -> diff)** — *Rejected*. Missing determinism
check -> false negative (flaky tests catalogued as "refactor changed behavior" without
distinguishing).

**c) Post-only snapshot, comparison with VCS history** — *Rejected*. Requires git
+ clean history. Not applicable to non-git projects or dirty working trees.

### 3.7 Multi-language strategy (Q7)

**a) Stack-agnostic single harness via `.claude/test-cmd` (CHOSEN).** Reuse of already live
contract. Zero per-stack scaffolding.

**b) Per-stack adapter Python + Swift + JS** — *Rejected as MVP*. Matrix maintenance. Possible
future extension only if MVP proves insufficient.

**c) Stack auto-detection via file presence** — *Rejected*. Fragile, duplicates the work of
`.claude/test-cmd`. Anti-pattern.

### 3.8 Failure mode + override (Q8)

**a) Three-state PASS/FAIL/UNVERIFIED + override file `.claude/refactor-snapshot-override`
(CHOSEN).** Triple discriminator (determinism check + diff check + manual override).

**b) Boolean PASS/FAIL without UNVERIFIED** — *Rejected*. Confuses test flakiness with
refactor regression. False positives on projects with non-deterministic tests.

**c) Auto-override when the refactorer detects timestamps / random IDs in stdout** —
*Rejected*. Risk of silent auto-override that masks real regressions. HITL gate is the correct
pattern (aligned with CLAUDE.md global "HITL gate always before ... DB schema modification,
permanent deletions").

**d) Hook PreToolUse that blocks Edit if snapshot not captured** — *Rejected*. Same
rationale as ADR-0001 §3.1.c: bash 3.2 hook cannot inspect the LLM response, and
PreToolUse Edit hooks receive `tool_input` JSON. Philosophy "primary enforcement is
discipline + skill-based gate, not hard hook at filesystem" (consistent with the rest of the
system).

---

## 4. Consequences

### 4.1 Positive

- **Unblocks delegation of non-trivial refactors to the refactorer.** Resolves the root cause
  (user memory): no non-regression guarantee exists. Snapshot harness *is* the guarantee,
  deterministic and inspectable.
- **Catches the cycle 2 pricing-markup-cli failure mode at the source.** Refactor that changes
  behavior -> different SHA256 -> FAIL. Triple-angle coverage (coder pre-flight
  classifier ADR-0001 + reviewer Add+Remove triage v1.2 + refactorer snapshot ADR-0002).
- **Reusable pattern for other agents.** If in the future we want a "behavior-preservation
  check" also for `debugger` (fix must not change behavior of non-bug-target code) or `tester`
  (new test must not influence existing test runs), the `refactor-snapshot` skill can be adapted.
- **Stack-agnostic by construction.** Reuse `.claude/test-cmd` contract already validated
  cross-stack (Python pricing-markup-cli, Swift swift-vibe, JS fastapi-react-vibe).
- **Zero new dependencies.** Only bash 3.2, `sha256sum` (or `shasum -a 256` on macOS),
  `diff` (POSIX). No pip/npm/swift pkg deps.
- **Anchor preservation respected.** PASS=43 -> PASS=45 (+2 structural anchors for
  `refactorer.md`). Additive, no regression.
- **Clean coexistence with ADR-0001 + v1.2.** Orthogonal (operate on different agents).
  No race conditions.
- **Complete audit trail.** `.refactor-snapshot.txt`, `.refactor-snapshot.txt.post`,
  `.refactor-snapshot-override` (if present), refactorer report — four inspectable artifacts
  to reconstruct every cycle.

### 4.2 Negative

- **Time overhead for the refactor cycle.** Determinism check requires 3 test command runs
  + 1 post-run = 4 total runs per cycle. On projects with slow tests (>30s) the
  refactor cycle goes from ~30s (1 baseline run + 1 post-run) to ~2 min. Mitigation:
  `RFS_FILTER` narrow scope (§2.5 override). Not eliminated.
- **False positives on non-deterministic tests.** Projects with tests that include
  timestamps / random IDs / absolute paths produce `UNVERIFIED`. The refactorer must
  abort or the user must create an override. Friction-inducing until the pilot produces
  best-practice "test cleanup pre-refactor". Severity: medium.
- **Dependency on pre-existing `.claude/test-cmd`.** If the target project does not have
  test-cmd configured (TOFU not done), snapshot UNVERIFIED -> refactor aborted.
  Forces the user to deploy test-cmd first. Aligned with existing practice
  (approve-test-cmd hook) but is an additional gate.
- **Minor coupling harness `review-triage-fix` <-> `refactorer.md`.** The harness now
  reads 3 files (`SKILL.md`, `coder.md`, `refactorer.md`). If in the future we rename
  refactorer.md, 2 anchors to update. Acceptable cost (consistency with coder.md coupling
  already established in ADR-0001).
- **MVP does not handle snapshots for pure function return values.** Library-only projects
  without integration tests (e.g. tiny util library) do not benefit. Deferred (see §3.1).
- **Blast radius via grep misses indirect callers via reflection.** Override `RFS_FULL=1`
  exists but requires refactorer judgment. Possible false negative if refactorer does not
  detect reflection. Severity: medium.

### 4.3 Neutral

- **TDD plan written by the architect remains agnostic to the snapshot.** Architect does not
  pre-declare snapshot expectations in plan steps; it is runtime, by the refactorer.
  Aligned with ADR-0001 pattern (architect agnostic to the classifier).
- **MEMORY.md updated.** New entry "Refactor snapshot harness" in the Project section.
- **Orchestrator unchanged.** Dispatches `refactorer` as before; the refactorer now
  produces a richer report (PASS/FAIL/UNVERIFIED + audit artifacts).
- **Sub-agent identity unchanged.** Refactorer remains Sonnet, tools unchanged, yellow color.

### 4.4 Open questions (validation pending)

- **Compliance hit-rate:** % of refactor cycles in which the refactorer actually
  invokes capture.sh before/after edit. Target: >95%. Validatable only in organic use.
- **False positive rate on non-deterministic tests:** how many pilot projects have flaky
  tests that force `UNVERIFIED` or override? Validatable over 3-5 pilot cycles.
- **Blast radius narrow scope effectiveness:** how much time does `RFS_FILTER` save compared to
  full test command? Target: >=3x speedup on large projects. Validatable with pilot metrics.
- **Reflection / dynamic dispatch false negative rate:** how many refactors pass the
  snapshot but break behavior in indirect callers? Validatable post-pilot with review of
  subsequent MAJORs.
- **Override file `.refactor-snapshot-override` usage rate:** if too many cycles require
  override, the harness is too strict. If no cycle uses it, it is an unnecessary feature.
  Target sweet spot: 5-15% of cycles. Validatable post-pilot.

---

## 5. References

- `~/.claude/agents/refactorer.md` (primary modification target)
- `~/.claude/skills/refactor-snapshot/` (skill to create)
- `~/.claude/skills/review-triage-fix/tests/run-tests.sh` (target +2 anchors)
- `~/.claude/hooks/approve-test-cmd.sh` (`.claude/test-cmd` contract reuse)
- `docs/vibe-coding-system.md` sec. 3.x (8 sub-agents), sec. 8 (skill), sec. 11
  (workflow concept->code)
- `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (Accepted
  2026-05-20, orthogonal)
- `docs/superpowers/specs/2026-05-19-swarm-testcmd-design.md` (TOFU + 3-tier for
  `.claude/test-cmd`)
- `docs/superpowers/specs/2026-05-19-review-triage-fix-design.md` (anchor harness pattern)
- Memory `feedback_micropiano-refactor-cleanup.md` (RESOLVED 2026-05-20; cycle 2 MAJOR
  rationale)
- Memory `feedback_bash32-constraint.md` (bash 3.2 invariant constraint)
- Field test `docs/field-test-2026-05-18.md` (pilot history)
