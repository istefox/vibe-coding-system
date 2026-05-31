# SPEC — deep-refactor skill

**Date:** 2026-05-30
**Topic slug:** deep-refactor-skill
**Manifest:** docs/manifests/2026-05-30-deep-refactor-skill.manifest.yml

---

## Objectives

Create a `deep-refactor` skill that performs a whole-codebase health audit on a working
application and automatically fixes routable findings in a regression-safe incremental loop.

Goals:
1. Surface accumulated technical debt across four dimensions: dead code, performance,
   structure/complexity, and security.
2. Auto-fix low-to-medium risk findings with test verification after each dimension batch.
3. Never introduce regressions: green baseline required; circuit breaker stops on any
   red test; no fix proceeds without a verifiable baseline.
4. Produce a committed findings report alongside the code changes.
5. Integrate as Gate 5.1 in the concept-to-code chain (after RTF, before commit)
   and as a standalone skill (`/skill deep-refactor`).

---

## Scope

### In scope
- `~/.claude/skills/deep-refactor/SKILL.md` — full skill definition
- Integration into `~/.claude/skills/concept-to-code/SKILL.md` at Gate 5.1
- Optional helper scripts in `~/.claude/skills/deep-refactor/scripts/` if needed

### Out of scope
- Changes to existing agents (reviewer, refactorer, coder, debugger) — they are invoked as-is
- Changes to the RTF skill — deep-refactor is additive, not a replacement
- IDE-level or build-system integration (no Xcode project changes)

---

## Invocation

**Standalone:**
```
/skill deep-refactor [<path-override>]
```
- `<path-override>`: optional glob or directory to restrict scope (default: all source files)
- Runs from the current project directory

**As c2c chain step (Gate 5.1):**
- Offered after RTF completes (or is skipped), before the commit step
- User sees a gate: "Run deep-refactor on the full codebase?"
- If skipped, chain proceeds to commit unchanged

---

## Audit Dimensions

Four parallel audit agents, each with a dedicated scope:

| Dimension | Agent type | What it finds |
|---|---|---|
| `dead-code` | reviewer | Unused functions, imports, variables, unreachable branches, dead `#if` blocks |
| `performance` | reviewer | Unnecessary allocations, redundant recomputations, inefficient collection patterns, force-casts, synchronous I/O on main thread |
| `structure` | reviewer | Oversized files (>400 lines), oversized functions (>60 lines), tangled dependencies, duplicated logic blocks |
| `security` | reviewer | Hardcoded secrets/tokens, unsafe API usage, missing input validation, unguarded URL construction |

Each agent returns findings as a JSON array matching the standard **Finding schema** (see Data Model).

---

## Data Model

### Finding schema
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

### Report schema (`docs/deep-refactor/YYYY-MM-DD-<project>.md`)
```markdown
# Deep Refactor Report — <project> — <date>

## Summary
- Baseline: PASS=N FAIL=0
- Post-fix: PASS=M FAIL=0
- Findings total: N
- Fixed: N | Deferred: N | Report-only (security): N
- Regressions caught by circuit breaker: N

## Findings by dimension
### Dead code
...

### Performance
...

### Structure
...

### Security (report-only)
...

## Deferred / Skipped
...
```

---

## Process — Phase by Phase

### Phase 0 — Pre-flight (blocking gate)

1. Verify `git rev-parse --git-dir` succeeds (git repo required).
2. Capture baseline commit hash: `git rev-parse HEAD`.
3. Read `.claude/test-cmd`. If `NONE` or absent:
   - **Block auto-fix.** Present gate: "No test-cmd found. Proceed in report-only mode (no auto-fix) or abort?"
   - Report-only mode: audit runs, findings are documented, NO fixes applied, NO commit.
4. If test-cmd exists: run it. If RED:
   - **Block auto-fix.** Present gate: "Baseline tests are RED. Fix the baseline first, or proceed in report-only mode?"
   - Same report-only path as above.
5. Capture baseline test count for delta reporting.
6. Identify all source files via `git ls-files` (respects .gitignore). Exclude: `*.xcarchive`, `DerivedData/`, `Pods/`, `.build/`, `*.generated.swift`.

**HITL Gate 0 — Approval before starting:**
```
AskUserQuestion:
  question: "deep-refactor — Ready to audit\n\nProject: <root>\nFiles to scan: <N>\nBaseline: PASS=<N> FAIL=0\nDimensions: dead-code, performance, structure, security\n\nThis will read all source files and dispatch 4 parallel audit agents.\nProceed?"
  options:
    - "Proceed with full audit"
    - "Abort"
```

### Phase 1 — Parallel audit (4 agents)

Dispatch all four dimension agents in parallel (Workflow if `hook_verified=true`, else sequential Agent-tool calls). Each agent:
- Reads all source files identified in Phase 0
- Returns a JSON findings array matching Finding schema
- Tags each finding with `risk_level: high` if the finding requires human judgment (all security secrets/auth bypass; any finding touching public API contracts)

Collect and merge findings. Sort by: dimension order (dead-code → perf → structure → security), then severity (P1 → P2 → P3).

**HITL Gate 1 — Findings summary before fixing:**
```
AskUserQuestion:
  question: "deep-refactor — Audit complete\n\nFindings:\n  dead-code: N (P1: x, P2: y, P3: z)\n  performance: N\n  structure: N\n  security: N (low-risk: x, high-risk: y — report-only)\n\nTotal routable (auto-fixable): N\nEstimated time: ~N min\n\nProceed with auto-fix?"
  options:
    - "Fix all routable findings"
    - "Report only — no auto-fix"
    - "Abort"
```

If "Report only": skip Phases 2-3, go directly to Phase 4 (report + commit report file only).

### Phase 2 — Incremental fix loop (dimension by dimension)

**Order:** dead-code → performance → structure → security (low-risk only)

For each dimension batch:
1. Group findings by file within the dimension.
2. Dispatch fix agents in parallel per file group, using `model: "opus"`:
   - `fix_type: coder` → coder agent with micro-piano
   - `fix_type: refactorer` → refactorer agent
   - `fix_type: debugger` → debugger agent
   - `fix_type: report-only` → skip (goes to deferred list)
   - `risk_level: high` → skip regardless of fix_type (goes to report-only section)
3. After all fixes in the dimension complete: run test-cmd.
   - **GREEN:** log "dimension <X> clean — N findings fixed", proceed to next dimension.
   - **RED:** **circuit breaker fires.** Record which dimension caused regression. Skip remaining findings in this dimension. Log `REGRESSION: <dimension>` in report. Proceed to next dimension (do NOT abort entire skill — other dimensions may be safe).
4. After all dimensions: run test-cmd once more for final verification.

### Phase 3 — Security report-only section

Collect all `security` findings with `risk_level: high`. Write them as a dedicated section in the report with:
- File, line, description
- Suggested remediation (from audit agent)
- Tag: `ACTION REQUIRED — not auto-fixed`

### Phase 4 — Output

1. Write report to `<project-root>/docs/deep-refactor/YYYY-MM-DD-<slug>.md`.
2. Stage report + all modified source files: `git add -A`.
3. **HITL Gate 2 — Commit approval:**
```
AskUserQuestion:
  question: "deep-refactor — Ready to commit\n\nFixed: N findings\nDeferred: N\nSecurity report-only: N\nRegressions caught: N\nTest delta: PASS=N (+M)\n\nApprove commit?"
  options:
    - "Approve and commit"
    - "Stage only (no commit)"
    - "Abort (discard changes)"
```
4. On approve: invoke `commit` skill with context-hint `"deep-refactor: <project> audit"`.
5. On "Stage only": leave staged, user commits manually.
6. On "Abort": `git reset HEAD` (unstage), leave working tree as-is.

---

## Integration — Gate 5.1 in concept-to-code

After RTF completes (or is skipped at Gate 5), before Gate 5.5 (humanize) and Step 7 (commit):

```
AskUserQuestion:
  question: "Gate 5.1 — Deep refactor (optional)\n\nRTF cycle complete. Run a full-codebase health audit?\nThis scans ALL source files (not just changed ones).\nEstimated: 10–20 min depending on codebase size.\n\nOnly meaningful if the project has accumulated technical debt."
  options:
    - "Run deep-refactor"
    - "Skip (proceed to commit)"
```

"Run deep-refactor" → invoke `/skill deep-refactor` (Skill tool). After completion, transition to Gate 5.5 / Step 7.
"Skip" → silent no-op, proceed to Gate 5.5 / Step 7 as before.

---

## Edge Cases

- **No test-cmd (`NONE`):** skill blocks auto-fix, offers report-only mode explicitly.
- **Xcode codesign-bound tests:** test-cmd fails without signed bundle. Same path as NONE — block, offer report-only.
- **Circuit breaker fires mid-dimension:** remaining findings in that dimension are deferred; other dimensions continue. Report documents which dimension caused regression with the specific finding.
- **All findings are `report-only`:** skill produces report, no code changes, no commit of source (only report file committed).
- **Empty audit (0 findings):** emit "Codebase is clean across all dimensions" and exit without committing.
- **Large codebase (>200 files):** Workflow dispatch required; sequential Agent-tool fallback may be slow but still correct.
- **Skill invoked mid-chain (dirty working tree):** pre-flight warns if `git status` shows uncommitted changes. Gate 0 includes a warning; user can proceed (uncommitted changes mixed into refactor) or abort to commit first.

---

## Success Criteria

- [ ] Pre-flight blocks when baseline is RED or test-cmd is absent — no silent auto-fix on unverifiable codebases
- [ ] Parallel audit covers all four dimensions in a single invocation
- [ ] HITL gate shows findings summary before any fix is applied
- [ ] Fix loop runs dimension-by-dimension with test verification after each batch
- [ ] Circuit breaker correctly stops a dimension on regression without aborting the whole skill
- [ ] High-risk security findings are NEVER auto-fixed — always REPORT-ONLY
- [ ] Report committed alongside code changes with accurate delta counts
- [ ] Gate 5.1 integrates cleanly into c2c chain without regressions in existing paths
- [ ] Skill invokable standalone on any project with a `.claude/test-cmd`
- [ ] Empty result (0 findings) handled gracefully without committing

---

## Stack / Constraints

- Bash 3.2 compatible for any helper scripts
- Uses existing agents: reviewer (audit), coder/refactorer/debugger (fix), all at `model: opus`
- Workflow dispatch (Parallel) for audit phase when `hook_verified=true`; sequential Agent-tool fallback otherwise
- No new agent types required
- Report stored at `<project-root>/docs/deep-refactor/` (directory created if absent)
- Inherits all existing safety invariants: Pre-flight Pattern Classifier (ADR-0001), no test weakening (RTF weakening-scan not required here — circuit breaker is the equivalent)
