---
name: deep-refactor
description: >
  Use this skill for a whole-codebase health audit with automated regression-safe fixes across
  four dimensions (dead code, performance, structure, security). One invocation = audit ALL source
  files → gate on findings → fix dimension-by-dimension under a global circuit breaker → commit
  report. Trigger phrases: "deep-refactor", "codebase health audit", "full refactor audit",
  "whole-codebase cleanup".
  NEGATIVE: Do NOT use for quick findings-only requests ("review this", "code review", "show me
  the problems") — those go to the built-in code-review skill or review-triage-fix. Do NOT use
  for diff-scoped fixes (changes in the current working set) — use review-triage-fix (RTF) instead.
  deep-refactor is for the ENTIRE source tree, not a bounded changeset.
---

# deep-refactor

Whole-codebase health audit with regression-safe incremental auto-fix.
Pipeline: `pre-flight → parallel audit → findings gate → sequential fix loop → report → commit`.

## Hard constraints (read first)

- **Orchestrator-session only.** Sub-agents do not spawn sub-agents (nesting supported since
  CC 2.1.172; kept flat by design — see blueprint §2.2). If this skill is invoked from inside
  a sub-agent, STOP immediately and say so — you cannot dispatch from there.
- **Dispatch always sequential in the FIX phase.** Parallel fixes on the same codebase produce
  edit conflicts. Sequential is the invariant. The AUDIT phase uses parallel dispatch (Workflow or
  sequential Agent-tool fallback — see Phase 1).
- **Skill isolation.** Do not invoke `writing-plans`, `brainstorming`, `EnterPlanMode`, or any
  `superpowers/*` skill during the cycle. This skill is self-contained.
- **STOP and commit only via Gate 2.** This skill never self-commits. Commit is invoked via the
  `commit` skill after explicit user approval at Gate 2. No push inside this skill.
- **ADR-0001 PATTERN: pre-flight preserved.** Every coder dispatch in Phase 2 must include the
  standard coder contract (PATTERN: header before each Edit/Write). The pattern-enforce hook fires
  unchanged — do not suppress it.
- **SPEC divergence on circuit breaker: this ADR-0018 is authoritative.** SPEC §Phase 2.3
  specifies a per-dimension breaker (continue to next on red). This skill implements a GLOBAL
  circuit breaker (stop ALL remaining dimensions on any red). The brief is authoritative; the SPEC
  text is superseded by ADR-0018. See Phase 2 for the tag string.

## Four dimensions

| Dimension | Agent | Scope |
|---|---|---|
| `dead-code` | reviewer | Unused functions, imports, variables, unreachable branches, dead `#if` blocks |
| `perf` | reviewer | Unnecessary allocations, redundant recomputations, inefficient collection patterns, force-casts, sync I/O on main thread |
| `structure` | reviewer | Oversized files (>400 lines), oversized functions (>60 lines), tangled dependencies, duplicated logic blocks |
| `security` | reviewer | Hardcoded secrets/tokens, unsafe API usage, missing input validation, unguarded URL construction |

**Security is ALWAYS report-only.** Security findings are never auto-fixed, regardless of
`risk_level` or `fix_type`. High-risk security findings (hardcoded secrets, auth bypass) must be
tagged `ACTION REQUIRED — not auto-fixed` in the report.

## model: opus requirement

All dispatched agents in Phases 1 and 2 run at `model: opus`. Audit agents make judgment calls on
risk tagging; fix agents modify production source. Sonnet is insufficient for either role in this
skill.

**This applies to both dispatch mechanisms, not one.** Pin `model` explicitly on every `Agent`-tool
dispatch AND on every `agent()` call in a Workflow script. A Workflow subagent given `agentType`
but no `model` does not fall back to the agent's frontmatter — it inherits the main-loop (CLI
session) model. The same is true of `opts.effort`, documented as "omit to inherit the session
effort", so pin that too, at the agent's own frontmatter value. Naming only the Agent tool here is
what previously left the audit phase's Branch A running on whatever the session happened to use.

---

## Finding schema

Each audit agent returns a JSON array. Each element:

```json
{
  "id": "<dimension>-<file_basename>-<hash3>",
  "dimension": "dead-code | perf | structure | security",
  "severity": "P1 | P2 | P3",
  "risk_level": "low | high",
  "file": "<absolute path>",
  "line": "<integer or null>",
  "description": "<concise problem statement>",
  "fix_type": "coder | refactorer | debugger | report-only",
  "suggested_fix": "<1-2 line description>"
}
```

`risk_level: high` is a hard skip in the fix loop, regardless of `fix_type`. High-risk findings
are always deferred to the report-only section.

---

## Phase 0 — Pre-flight

### Step 0.1 — Git repo check

```sh
git rev-parse --git-dir
```

If this fails (non-zero exit), ABORT immediately with:

```
deep-refactor requires a git repository. The current directory is not a git repo.
Aborting.
```

Do not proceed.

### Step 0.2 — isolation:none pre-check

Determine the project root (the directory containing `.claude/`). If the project root is a
**non-git subdirectory** (i.e., `git rev-parse --show-toplevel` returns a parent directory that
differs from the `.claude/` parent, or the `.claude/` directory exists in a path that is a
subdirectory of the git root), set `ISOLATION_MODE=none` and record it. Fix agents in Phase 2
MUST be dispatched with `isolation: none` (never `isolation: worktree`) when this flag is set.
This mirrors the `feedback_coder-worktree-subdirectory` constraint: worktree dispatch on a
non-git root silently fails.

### Step 0.3 — Baseline commit hash

```sh
git rev-parse HEAD
```

Record this as `BASELINE_COMMIT`. This is the anchor for the partial report if the global circuit
breaker fires mid-run.

### Step 0.4 — Read test-cmd

Read `.claude/test-cmd` from the project root.

Cases:
- File absent, or content is exactly `NONE`: set `TEST_CMD=NONE`.
- File present and non-empty (not `NONE`): set `TEST_CMD=<content>`.

**NOTE:** `.claude/test-cmd` is off-limits for editing. Never modify it. Read-only.

### Step 0.5 — Baseline run and report-only fallback (hard block)

**If `TEST_CMD=NONE` or file is absent:**

Set `BASELINE=RED` (no verifiable baseline). Enter **report-only mode**. No auto-fix will be
applied in Phase 2. Only the findings report is committed. Present this explicitly at Gate 0.

**If `TEST_CMD` is set:**

Run it once. Capture PASS/FAIL.

- `PASS` → `BASELINE=GREEN`. Record test count for delta reporting.
- `FAIL` (any exit code, including Xcode codesign-bound failures) → `BASELINE=RED`. Enter
  **report-only mode**. All auto-fix is blocked. Present this explicitly at Gate 0.

Report-only mode means: audit runs, findings are documented, NO source edits applied, only the
report file is committed (if the user approves at Gate 2).

### Step 0.6 — Enumerate source files

Delegate to the helper:

```sh
bash ~/.claude/skills/deep-refactor/scripts/enumerate-sources.sh <project_root> [<path-override>]
```

The helper uses `git ls-files` and excludes:
- `*.xcarchive`
- `DerivedData/`
- `Pods/`
- `.build/`
- `*.generated.swift`

Record the file count as `SOURCE_FILE_COUNT`. If `SOURCE_FILE_COUNT=0`, abort with a message
explaining that no source files were found.

### Step 0.7 — Dirty working tree check

```sh
git status --porcelain
```

If output is non-empty, set `DIRTY_TREE=true`. Gate 0 will warn the user.

### HITL Gate 0 — Approval to start

```
AskUserQuestion:
  question: |
    deep-refactor — Pre-flight summary

    Project root: <root>
    Files to scan: <SOURCE_FILE_COUNT>
    Baseline: <PASS=N FAIL=0 | RED — test-cmd absent | RED — baseline tests failed>
    Mode: <auto-fix | REPORT-ONLY (no source edits)>
    Dimensions: dead-code, perf, structure, security

    [If DIRTY_TREE=true:]
    WARNING: Working tree has uncommitted changes. Uncommitted files will be mixed into the
    refactor scope. Consider committing first, or proceed knowing refactor changes will include
    your current working changes.

    [If BASELINE=RED:]
    AUTO-FIX BLOCKED: No verifiable baseline. The skill will audit and report only — no source
    files will be modified. Reason: <test-cmd absent | baseline tests failed>.

    This will read all source files and dispatch 4 parallel audit agents.
  options:
    - "Proceed with full audit"
    - "Abort"
```

If "Abort": stop cleanly, no further action.

---

## Phase 1 — Audit dispatch

### Dispatch model

Dispatch 4 `reviewer` dimension agents (dead-code, perf, structure, security).

**Dispatch split — two branches, both must be documented:**

**Branch A — Workflow dispatch (default):**

Use Workflow dispatch to fan-out the 4 reviewer agents in parallel. The audit phase is pure
fan-out with no mid-run HITL — the canonical Workflow use case. Each agent only Reads (no Edits),
so hook propagation risk is low. This is the default regardless of whether a project manifest is
present: the smoke test (ADR-0016) passed on CC v2.1.156 and the result is global.

Every `agent()` call in the script pins both values explicitly — `model: "opus", effort: "high"` —
per the "model: opus requirement" section above. Omit either and the subagent takes the
orchestrator session's value instead of the intended one: `opus` is this skill's stated
requirement for audit agents, and `high` is `reviewer`'s own frontmatter effort. Branch B below
pins `model` for the same reason; the two branches must not diverge.

Conditions for Branch A:
- No project manifest present (standalone invocation): use Branch A.
- Project manifest present with `hook_verified: true` (set by `manifest-init.sh`): use Branch A.

**Branch B — Sequential Agent-tool fallback (only when `hook_verified: false` explicitly set):**

Dispatch the 4 reviewer agents sequentially using the `Agent` tool at `model: opus`. Only active
when the project manifest explicitly contains `hook_verified: false` (manual override to force
sequential mode). Document in the Gate 1 summary that sequential mode was used.

### Mandatory guard 1 — Dead-code reviewer instruction

The dead-code reviewer MUST be given the following instruction verbatim in its dispatch prompt:

> "Tag as risk_level: high → fix_type: report-only any @objc, dynamic var/func, protocol conformances used only in as? casts, #selector(...), NSNotification.Name/string-typed ObjC bridge identifiers, reflection-reachable, protocol-witness symbols."

This guard is non-negotiable. Static analysis cannot prove these symbols are dead; a passing test
suite does not prove it either. The harness verifies this instruction is present as a structural
anchor.

### Mandatory guard 2 — Perf reviewer instruction

The perf reviewer MUST be given the following instruction verbatim in its dispatch prompt:

> "Tag as risk_level: high → fix_type: report-only any finding touching async/await/actor/DispatchQueue/Sendable/nonisolated. Auto-fix only synchronous perf patterns."

This guard is non-negotiable. Unit tests do not catch races that concurrency refactors can
introduce. The harness verifies this instruction is present as a structural anchor.

### Structure reviewer scope

The structure reviewer identifies oversized files (>400 lines), oversized functions (>60 lines),
tangled dependencies, and duplicated logic blocks. No special guard required — structural fixes do
not touch runtime dispatch or concurrency.

### Security reviewer scope

The security reviewer identifies hardcoded secrets/tokens, unsafe API usage, missing input
validation, and unguarded URL construction. **All security findings are always `fix_type:
report-only`.** The reviewer should set `risk_level: high` on secrets and auth bypass, and
`risk_level: low` on lower-severity patterns — but fix_type remains `report-only` for all
security findings regardless of risk_level.

### Merge and dedup findings

Collect all findings arrays from the 4 agents. Merge into a single list.

Dedup rule: if two findings share the same `file` AND same `line` AND have overlapping
`description` text (one is a substring or close variant of the other), keep the one with the
higher severity (P1 > P2 > P3). If severity is equal, keep the one with `risk_level: high` over
`low`.

Sort the merged list:
1. Dimension order: dead-code → perf → structure → security
2. Within each dimension: P1 → P2 → P3
3. Within each severity: `risk_level: high` before `risk_level: low`

Compute `ROUTABLE_TOTAL` = count of findings where `fix_type != "report-only"` AND `risk_level
!= "high"` AND `dimension != "security"`.

### HITL Gate 1 — Findings summary before fixing

```
AskUserQuestion:
  question: |
    deep-refactor — Audit complete

    Findings:
      dead-code: N (P1: x, P2: y, P3: z) — routable: N
      perf: N (P1: x, P2: y, P3: z) — routable: N
      structure: N (P1: x, P2: y, P3: z) — routable: N
      security: N (all report-only)

    Total routable (auto-fixable): <ROUTABLE_TOTAL>
    High-risk (skipped in fix loop): N
    Report-only (fix_type=report-only or security): N

    [If BASELINE=RED or report-only mode active:]
    NOTE: Auto-fix is blocked (no verifiable baseline). Only "Report only" is available.

    [If audit dispatch used sequential fallback (hook_verified: false explicitly set):]
    NOTE: Audit ran in sequential mode (hook_verified=false override active). Results are correct;
    sequential mode is slower but complete.
  options:
    - "Fix all routable findings"
    - "Report only — no auto-fix"
    - "Abort"
```

If "Report only": skip Phase 2, go directly to Phase 3 (security section) then Phase 4 (report).
If "Abort": stop cleanly. No report committed.
If "Fix all routable findings" AND `BASELINE=RED`: override to "Report only" — auto-fix is
blocked when the baseline is RED regardless of user selection. Explain the override.

---

## Phase 2 — Fix loop (sequential, dimension by dimension)

> **ADR-0018 is authoritative on circuit-breaker scope.** SPEC §Phase 2.3 specifies a
> per-dimension breaker (continue to next dimension on RED). This skill implements a GLOBAL
> circuit breaker: any RED test run stops ALL remaining fixes across ALL remaining dimensions.
> The brief is authoritative; the SPEC text is superseded by ADR-0018.

**Pre-condition:** This phase runs only if Gate 1 choice was "Fix all routable findings"
AND `BASELINE=GREEN`. If either condition is false, skip to Phase 3.

**Dimension order (fixed, non-negotiable):** dead-code → perf → structure

Security is NEVER processed in this phase (always report-only, handled in Phase 3).

Initialize:
- `DIMENSIONS_COMPLETED=[]`
- `CIRCUIT_BREAKER_FIRED=false`
- `CIRCUIT_BREAKER_DIMENSION=none`

---

### Phase 2 — Per-dimension loop

For each dimension D in [dead-code, perf, structure]:

  **If `CIRCUIT_BREAKER_FIRED=true`:** skip this dimension entirely. Record it as `SKIPPED`.

  **Step 2.D.1 — Filter routable findings for this dimension**

  From the merged findings list, select findings where:
  - `dimension == D`
  - `fix_type != "report-only"`
  - `risk_level != "high"`

  If the filtered list is empty, record dimension D as "no routable findings" and continue to
  the next dimension (no test run needed, no commit needed for this dimension).

  Sort the filtered list: P1 → P2 → P3. Within each severity: `low` risk before skipped
  (`high` was already filtered out).

  **Step 2.D.2 — Dispatch fix agents sequentially**

  For each finding F in the sorted list:

  Determine the agent type from `F.fix_type`:
  - `coder` → dispatch `coder` agent at `model: opus`
  - `refactorer` → dispatch `refactorer` agent at `model: opus`
  - `debugger` → dispatch `debugger` agent at `model: opus`

  **Dispatch brief template (fill in finding details):**

  ```
  Agent: <fix_type>
  model: opus
  isolation: <none if ISOLATION_MODE=none, else worktree>

  MANDATORY: Emit a PATTERN: pre-flight header before every Edit or Write call, per ADR-0001.
  The pattern-enforce hook is active and will block any Edit without a preceding PATTERN: line
  in your assistant text. Do NOT suppress the pre-flight contract.

  [For coder only: use a micro-piano (one-step plan with PATTERN: headers) before any edit.]

  Scope: fix this single finding only. Do not refactor adjacent code. Do not add tests.
  Return a one-line summary: "Fixed <F.id>: <what was done>" or "Skipped <F.id>: <reason>".

  Fix the following finding in the codebase:

  File: <F.file>
  Line: <F.line>
  Dimension: <F.dimension>
  Severity: <F.severity>
  Description: <F.description>
  Suggested fix: <F.suggested_fix>
  ```

  Record each agent's result (fixed / skipped / error).

  **No-op detection (after each fix dispatch).** Before recording a result as "fixed", check:
  ```sh
  git -C <project_root> diff HEAD --name-only 2>/dev/null
  ```
  If this returns empty: the agent made no file changes despite reporting "Fixed". Record
  `NO-OP <F.id>: agent returned without modifying any files`, mark the finding as not fixed,
  and continue to the next finding. Do NOT fire the circuit breaker (the suite is unchanged).
  Do NOT count no-ops toward the fixed total in the Phase 4 report.

  **Step 2.D.3 — Run test-cmd ONCE after all findings in this dimension are processed**

  ```sh
  <TEST_CMD>
  ```

  Capture exit code.

  **If GREEN (exit 0):**
  - Mark dimension D as `COMPLETED`.
  - Append D to `DIMENSIONS_COMPLETED`.
  - Invoke the `commit` skill (Skill tool) with a context hint:
    ```
    deep-refactor: <project_name> — <D> dimension fixes
    ```
    This commit-per-dimension provides auditability: each dimension's fixes are a separate
    commit and can be reverted independently (BRAINSTORM note 3 — auditability over atomicity).
  - Continue to the next dimension.

  **If RED (any non-zero exit):**
  - Set `CIRCUIT_BREAKER_FIRED=true`.
  - Set `CIRCUIT_BREAKER_DIMENSION=D`.
  - **GLOBAL CIRCUIT BREAKER FIRED.** Do NOT continue to any remaining dimension.
  - Mark dimension D and all subsequent dimensions as `SKIPPED`.
  - Record: `CIRCUIT BREAKER FIRED AT: <D>`
  - The report (Phase 4) MUST be tagged `CIRCUIT BREAKER FIRED AT: <D>`.

  **Note:** The global circuit breaker fires on the test run of the failing dimension — it does
  not retry or run partial commits for the failing dimension. Fixes applied in the failing
  dimension remain in the working tree (unstaged) for the user to inspect.

---

### Phase 2 — Deferred findings log

Collect all findings that were skipped during Phase 2 (i.e., `fix_type: report-only` OR
`risk_level: high`). These go to the deferred/report-only section of the Phase 4 report.
Do not attempt to fix these.

---

## Phase 3 — Security report-only section

All security findings (dimension == "security") are ALWAYS report-only, regardless of
`risk_level` or `fix_type`. Security findings are NEVER auto-fixed in this skill.

For each security finding F:

```
File: <F.file>
Line: <F.line>
Severity: <F.severity>
Risk level: <F.risk_level>
Description: <F.description>
Suggested remediation: <F.suggested_fix>
Tag: ACTION REQUIRED — not auto-fixed
```

High-risk security findings (hardcoded secrets, auth bypass, unguarded credential exposure)
MUST be surfaced first, before lower-risk findings, in the report. Tag each with:

```
ACTION REQUIRED — not auto-fixed
```

This tag is a harness anchor. Do not alter it.

Collect all security findings into `SECURITY_REPORT_ITEMS`. If the security audit found zero
findings, record "No security findings detected."

---

## Phase 4 — Report and commit gate

### Step 4.1 — Write the report

Report path: `<project_root>/docs/deep-refactor/YYYY-MM-DD-<slug>.md`

Where:
- `YYYY-MM-DD` = today's date (ISO 8601)
- `<slug>` = `<project_name>-audit` (e.g., `notchdrop-audit`, `cleankey-audit`)

If `<project_root>/docs/deep-refactor/` does not exist, create it before writing.

**Report schema (required sections, in order):**

```markdown
# deep-refactor audit — <project_name> — <YYYY-MM-DD>

## Summary

- Baseline: <PASS=N FAIL=0 | RED — <reason>>
- Post-fix: <PASS=N FAIL=0 | N/A — report-only mode | CIRCUIT BREAKER FIRED AT: <dimension>>
- Dimensions completed: <list or "none — report-only mode">
- Dimensions skipped: <list or "none">
- Fixed: <count>
- Deferred (report-only / high-risk): <count>
- Regressions caught: <count — circuit breaker fires>
- Source files scanned: <SOURCE_FILE_COUNT>

[If CIRCUIT_BREAKER_FIRED=true:]
## Circuit breaker

CIRCUIT BREAKER FIRED AT: <CIRCUIT_BREAKER_DIMENSION>

The global circuit breaker fired when the test suite turned RED after applying fixes in the
<CIRCUIT_BREAKER_DIMENSION> dimension. All remaining dimensions were halted immediately.
Fixes applied before the breaker fired are committed (per-dimension commits). Fixes in the
failing dimension remain in the working tree, unstaged.

## Per-dimension findings

### dead-code

[For each finding in dead-code dimension:]
- **<severity>** `<file>:<line>` — <description>
  Status: <Fixed by <fix_type> agent | Deferred — report-only | Deferred — high-risk | SKIPPED>
  [If deferred:] Suggested fix: <suggested_fix>

### perf

[same pattern]

### structure

[same pattern]

## Security findings

[For each security finding — use SECURITY_REPORT_ITEMS:]
- **<severity>** `<file>:<line>` — <description>
  ACTION REQUIRED — not auto-fixed
  Suggested remediation: <suggested_fix>

[If no security findings:]
No security findings detected.

## Deferred findings (not auto-fixed)

[List all report-only and high-risk findings from all non-security dimensions:]
- `<file>:<line>` — <description> — Reason: <report-only fix_type | risk_level: high>
  Suggested fix: <suggested_fix>

[If no deferred findings:]
No deferred findings.
```

**Edge cases:**

- **0 findings total (all dimensions):** Write a minimal report with the line:

  ```
  Codebase is clean across all dimensions. No findings detected.
  ```

  Then exit without committing anything. Do NOT invoke Gate 2 or the commit skill. Stop cleanly.

- **All findings are report-only (ROUTABLE_TOTAL=0 or user chose "Report only"):** Write the
  full report. Commit the report file only (no source changes to commit). Proceed to Gate 2.

### Step 4.2 — Stage the report

```sh
git add <project_root>/docs/deep-refactor/YYYY-MM-DD-<slug>.md
```

### HITL Gate 2 — Commit approval

```
AskUserQuestion:
  question: |
    deep-refactor — Audit complete. Report staged.

    Report: docs/deep-refactor/<YYYY-MM-DD-slug>.md
    Fixed: <count> findings across <N> dimension(s)
    Deferred: <count> findings (report-only / high-risk)
    Security: <count> findings — all ACTION REQUIRED (not auto-fixed)

    [If CIRCUIT_BREAKER_FIRED=true:]
    CIRCUIT BREAKER FIRED AT: <CIRCUIT_BREAKER_DIMENSION>
    Commits landed for: <DIMENSIONS_COMPLETED>
    Remaining dimensions: SKIPPED
    Unstaged changes from <CIRCUIT_BREAKER_DIMENSION> are present in the working tree (run 'git diff' to inspect).
    [If DIRTY_TREE=true:]
    This run started with a dirty working tree (Gate 0 warning). The unstaged changes above are
    now a MIX of your own pre-existing edits and this dimension's failed fix attempts --
    'git checkout -- .' would discard both indiscriminately. Inspect 'git diff' file by file and
    revert selectively ('git checkout -- <path>' per file), or run 'git stash' to set everything
    aside non-destructively until you have reviewed it.
    [If DIRTY_TREE=false:]
    This run started from a clean working tree, so 'git checkout -- .' safely reverts these
    unstaged changes if unwanted.

    [If BASELINE=RED or report-only mode:]
    Mode: REPORT-ONLY (no source edits were applied)

    Choose an action:
  options:
    - "Approve and commit"
    - "Stage only — I will commit manually"
    - "Abort — unstage everything"
```

**On "Approve and commit":**

Invoke the `commit` skill (Skill tool) with context hint:

```
deep-refactor: <project_name> audit
```

This commits the staged report file (and any remaining staged source changes if the user
staged them externally). The commit skill handles the commit message and HITL per its own
contract. Do not self-commit.

**On "Stage only":**

Leave the working tree as-is (report staged, any source changes staged from Phase 2 commits
already landed). Return control to the user with a note of what is staged.

**On "Abort":**

```sh
git reset HEAD
```

This unstages the report file. Leave the working tree intact (source changes from Phase 2
dimension commits are already committed and are not affected by this reset). Inform the user
that the report has been unstaged and the working tree is unchanged.
