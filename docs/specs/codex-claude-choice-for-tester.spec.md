# SPEC: Codex-vs-Claude backend choice for the tester subagent

**Topic slug:** codex-claude-choice-for-tester

## Objectives

Give the `tester` subagent the same Codex-vs-Claude backend choice already shipped for the
`reviewer` agent (ADR-0187, ADR-0193), at its two dispatch sites in `concept-to-code` Step 5. Unlike
the reviewer, the tester must write real test files and run the suite, not just produce a read-only
report — so the mechanism needs a write-sandboxed Codex wrapper, not a reuse of
`codex-reviewer.sh`. As a related, explicitly requested change, also lower the tester's default
Claude effort pin from `xhigh` to `high` globally (frontmatter and Step 5 Workflow dispatch), to
reduce cost on every tester dispatch regardless of backend.

## Scope

**In scope:**
- A new script `codex-tester.sh` (mirrors `codex-reviewer.sh`'s structure and exit-code contract),
  running `codex exec -s workspace-write -C <worktree>` to write test files and run the suite inside
  a worktree it cannot write outside of.
- A post-run `git diff --name-only` scope check inside `codex-tester.sh`: if Codex wrote to a
  non-test file, exit 4 (new, in addition to the existing 0/2/3 contract).
- A free-text `model_reasoning_effort` override on the codex branch (default: config.toml's current
  value, `medium`), passed as `-c model_reasoning_effort=<value>` to `codex exec`. No `-m/--model`
  override — the codex model itself stays whatever `~/.codex/config.toml` configures.
- Two new `AskUserQuestion` gates, one at each Step 5 tester dispatch site
  (`concept-to-code/references/step5-implementation.md:574-622` Workflow path, `:1769-1806`
  Agent-tool batch path), offering `codex` / `claude-sonnet` (default) / `claude-opus` — model only,
  no effort choice on the Claude branches (kept pinned, per the reviewer's own Step 5 precedent).
- Two new manifest fields, `use_codex_tester` / `step5_codex_tester_asked`, additive under the
  existing schema `1.4` (no version bump — same treatment ADR-0193 gave the reviewer's own fields),
  new Invariants 26/27 in `manifest-validate.sh`, seeded in `manifest-init.sh`.
- Lower the tester's default Claude effort pin from `xhigh` to `high`: `staging/plugin/agents/
  tester.md` frontmatter, and the Step 5 Workflow dispatch site's explicit `effort: "xhigh"` pin
  (`references/step5-implementation.md:574-622`). The Agent-tool batch path already omits `effort`
  (the tool has no such parameter, ADR-0068 §D7) — unaffected.
- `docs/architecture/ADR-0194-codex-tester-choice.md` moves from Proposed to Accepted once this
  plan is approved and implemented, with any interview-driven refinements folded in.

**Out of scope:**
- Any change to `codex-reviewer.sh` itself, or to the `reviewer` agent's own dispatch sites.
- A structural/automated check that Codex's report actually contains all six `tester.md` Output
  Format sections. Parity is a prompt instruction only (same trust level as `codex-reviewer.sh`'s
  own report-shape parity with `reviewer.md` — no parser validates that either).
- Exposing a Codex model override (`-m`) — only `model_reasoning_effort` is exposed, because the
  set of valid Codex model names was not confirmed live (config.toml default: `gpt-5.6-terra`; a
  `Sol`/`Terra`/`Luna` family exists per local docs but its capability ranking was not verified).
- Any change to `review-triage-fix` or its own codex dispatch sites.

## Stack / architecture

No new runtime dependency. `codex-tester.sh` is a Bash 3.2-clean script, deployed via
`sync-to-claude.sh`'s `PAIRS` mapping (`staging/plugin/scripts/codex-tester.sh` →
`~/.claude/hooks/codex-tester.sh`), same shape as `codex-reviewer.sh`.

**Availability cascade** (mirrors `codex-reviewer.sh`): `command -v codex` → `codex doctor --json`
→ `auth.credentials.status == "ok"` → not any of these, exit 3 (`DID-NOT-RUN`), never silent.

**Sandbox**: `codex exec -s workspace-write -C <worktree-dir>` — verified live (`codex exec --help`,
2026-09-06) that both flags exist and compose to scope writes to exactly the given directory. This
reuses the worktree isolation the tester dispatch already establishes
(`isolation: "worktree"` on the Workflow path; explicit worktree write-path briefing on the
Agent-tool batch path) rather than inventing a second isolation boundary.

**Post-run scope check** (new, no reviewer-side precedent): after `codex exec` returns 0, run
`git -C <worktree> diff --name-only` against the pre-dispatch baseline and classify each changed
path by the project's own test-file convention (same file-name/path heuristic `tester.md`'s own
framework detection already uses per stack). Any non-test-file change → exit 4, `--out` still
written (partial), caller must surface it and never treat exit 4 as success.

## Data model (manifest, schema 1.4, additive)

```yaml
use_codex_tester: false          # bool, default false — mirrors use_codex_review
step5_codex_tester_asked: false  # bool, default false — mirrors step5_codex_review_asked;
                                  # distinguishes "never asked" from "asked, declined" (both leave
                                  # use_codex_tester=false), same reasoning as ADR-0193's own fix
                                  # for the equivalent reviewer-side bug.
```

`manifest-validate.sh` — new conditional Invariants (numbered after the existing 25):
- **Invariant 26**: if `use_codex_tester` present, must be `true`/`false`.
- **Invariant 27**: if `step5_codex_tester_asked` present, must be `true`/`false`.

`manifest-init.sh` seeds both to `false` alongside the existing `use_codex_review`/
`step5_codex_review_asked` lines.

## Dispatch flow (both Step 5 sites)

1. Immediately before the tester dispatch, `AskUserQuestion`: `codex` / `claude-sonnet` (default) /
   `claude-opus`. Skipped under `--autopilot`, same disclosed instruction-not-enforcement limit as
   the reviewer's own Step 5 ask (rule 16). Writes the answer via `manifest-set-flag.sh` and sets
   `step5_codex_tester_asked: true` regardless of the answer (so it never re-fires after a "no",
   same fix ADR-0193 already made for the reviewer).
2. **`codex` branch**: dispatch `~/.claude/hooks/codex-tester.sh --worktree <dir> --brief <file>
   --out <file> [--effort <value>]`, brief content identical to what the Claude `tester` receives
   (SPEC requirement IDs / Success Criteria / plan task text, never implementation files — ADR-0049
   §D1, ADR-0088). Branch on exit code:
   - `0` → read `--out` as the tester's report, exactly as if the Claude `tester` had produced it.
   - `2` → bad invocation, report the stderr line, halt this dispatch.
   - `3` → DID-NOT-RUN. `AskUserQuestion`: fallback to Claude `tester`, or halt. Never silent.
   - `4` → wrote outside test scope. Report the offending paths from `--out`, `AskUserQuestion`:
     fallback to Claude `tester` (recommended), or accept the write and continue, or halt.
3. **`claude-sonnet`/`claude-opus` branch**: dispatch `tester` at that `model:`, `effort: "high"` on
   the Workflow path (post-lowering default; see below), no `effort` on the Agent-tool path
   (unchanged, ADR-0068 §D7).

## Effort pin change (tester default, both backends)

- `staging/plugin/agents/tester.md` frontmatter: `effort: xhigh` → `effort: high`.
- `references/step5-implementation.md:574-622` (Workflow path) explicit pin: `effort: "xhigh"` →
  `effort: "high"`.
- Agent-tool batch path (`:1769-1806`): unaffected, already omits `effort`.
- This applies unconditionally, independent of which Step 5 dispatch-site ask above is answered —
  it is a default-cost change, not part of the codex/claude choice itself.

## Edge cases

- **Codex unavailable (exit 3) mid-chain, after already writing some files in a prior attempt on
  the same worktree**: not possible in this design — `codex-tester.sh`'s availability cascade runs
  before any `codex exec` invocation, so exit 3 is always a no-op with respect to the filesystem.
- **Codex writes a file that is ambiguous between test and production** (e.g. a shared fixture
  file): classified by the same heuristic `tester.md`'s own framework detection already uses; a
  false positive here is a caller-visible exit 4, not a silent pass — the operator decides via the
  fallback `AskUserQuestion` in step 2 above.
- **`model_reasoning_effort` override rejected by Codex** (invalid value): `codex exec` itself fails
  non-zero; `codex-tester.sh` propagates this as exit 3 or 2 per its own availability-cascade /
  bad-invocation classification (not a new state) — the failure is visible, not silently ignored.
- **Autopilot run**: both new Step 5 asks skipped, `use_codex_tester` stays `false`, `tester`
  dispatches on Claude exactly as it does today (minus the effort-pin lowering, which applies
  unconditionally).

## Success criteria

- [ ] R-01 — A new script `staging/plugin/scripts/codex-tester.sh` exists, deployable via
      `sync-to-claude.sh`'s `PAIRS` mapping to `~/.claude/hooks/codex-tester.sh`.
- [ ] R-02 — `codex-tester.sh` runs `codex exec -s workspace-write -C <worktree>`, never
      `-s read-only` and never `danger-full-access`.
- [ ] R-03 — `codex-tester.sh` implements the same availability cascade as `codex-reviewer.sh`
      (codex CLI present, `codex doctor --json` auth check), exiting 3 with a `DID-NOT-RUN` stderr
      line on any failure of that cascade.
- [ ] R-04 — `codex-tester.sh` exits 0 on success with the report written to `--out` in
      `tester.md`'s six-field Output Format shape (no-test: this is a prompt-authoring requirement
      verified by reading the script's embedded prompt text, not something a harness assertion can
      mechanically confirm without inventing an unwanted structural parser).
- [ ] R-05 — `codex-tester.sh` runs a post-run `git diff --name-only` scope check and exits 4 with
      the offending file paths on stderr when a non-test file was modified.
- [ ] R-06 — `codex-tester.sh` accepts an optional `--effort <value>` flag, passed through as
      `-c model_reasoning_effort=<value>` to `codex exec`; omitted entirely when not provided (uses
      `~/.codex/config.toml`'s own default).
- [ ] R-07 — `concept-to-code/references/step5-implementation.md`'s Workflow-path tester dispatch
      (currently lines 574-622) is preceded by an `AskUserQuestion` offering `codex` /
      `claude-sonnet` (default) / `claude-opus`, skipped under `--autopilot`.
- [ ] R-08 — `concept-to-code/references/step5-implementation.md`'s Agent-tool batch-path tester
      dispatch (currently lines 1769-1806) is preceded by the same `AskUserQuestion` as R-07.
- [ ] R-09 — On the `codex` branch at either site, exit 0 from `codex-tester.sh` is consumed as the
      tester's report; exit 2 halts that dispatch and reports stderr; exit 3 triggers a
      fallback-or-halt `AskUserQuestion`, never a silent fallback; exit 4 triggers a
      fallback-accept-or-halt `AskUserQuestion` naming the offending files.
- [ ] R-10 — `manifest-init.sh` seeds `use_codex_tester: false` and
      `step5_codex_tester_asked: false`.
- [ ] R-11 — `manifest-validate.sh` gains conditional Invariants 26 and 27 validating those two
      fields are boolean when present, schema stays `1.4` (no version bump).
- [ ] R-12 — Each Step 5 ask sets `step5_codex_tester_asked: true` unconditionally once it fires,
      regardless of the answer chosen, so it never re-prompts on a later run of the same manifest
      after a decline.
- [ ] R-13 — `staging/plugin/agents/tester.md` frontmatter `effort:` changes from `xhigh` to
      `high`.
- [ ] R-14 — `concept-to-code/references/step5-implementation.md`'s Workflow-path dispatch pin
      changes from `effort: "xhigh"` to `effort: "high"`; the Agent-tool batch path is left
      unchanged (it already omits `effort`).
- [ ] R-15 — `docs/architecture/ADR-0194-codex-tester-choice.md` is updated to Accepted status,
      reflecting any interview-driven refinements above (workspace-write sandbox confirmed live,
      effort-override mechanism, effort-pin lowering) that were not yet settled when it was
      drafted as Proposed (no-test: this is a documentation-state requirement, not something a
      test can assert without inventing a doc-content parser).
