# SPEC — PostToolUse backstop hook for Step 7.1 commit-outcome verification

**Topic slug:** commit-outcome-backstop-hook

## Objective

`concept-to-code`'s Step 7.1 classifies what the `commit` skill actually did (`COMMIT_OK` /
`COMMIT_UNCOMMITTED` / `COMMIT_NONTERMINAL` / `COMMIT_OUTCOME_NORUN`) by reading the manifest on
disk. This check exists only as a `SKILL.md` prose instruction with no structural enforcement:
nothing prevents the orchestrator from skipping it, especially deep into a long chain run where
thousands of prior instructions have already been processed.

Precedent: Adnota repo PR #36 (2026-08-23) — a chain's Step 7 snapshot-collapse staged the manifest
before a follow-up write (SPEC archive repoint + `completed` transition) landed, and that write was
never re-staged before the commit. The merged manifest read `current_step: step_7_commit`,
`status: in_progress` instead of `completed`/`completed`. The feature shipped correct; only the
manifest bookkeeping was stale — exactly the `COMMIT_NONTERMINAL` condition Step 7.1 exists to
catch, uncaught because Step 7.1 is prose, not a mechanical check.

This matters beyond bookkeeping hygiene: if `COMMIT_NONTERMINAL`/`COMMIT_UNCOMMITTED` goes
unnoticed, the chain proceeds anyway to post-commit push, a `PROJECT.md` update marking the
feature `[x]` completed, and a cost snapshot. `project-conductor` and `autopilot` read `PROJECT.md`
checkboxes to decide what to work on next, so a false-positive "completed" checkbox can make an
unattended run skip real work believing it is already done.

Objective: give Step 7.1's classification a stateless, mechanical backstop that fires independently
of whether the orchestrator remembered to run the inline check, without introducing a second,
divergent copy of the classification logic.

## Scope

**In scope:**
- Extracting the existing inline classification fence (`c2c-step7-commit-outcome`,
  `~/.claude/skills/concept-to-code/SKILL.md`, the `COMMIT_OK`/`COMMIT_UNCOMMITTED ...`/
  `COMMIT_NONTERMINAL ...`/`COMMIT_OUTCOME_NORUN <reason>` contract) into a shared script,
  `~/.claude/skills/concept-to-code/scripts/commit-outcome-check.sh`, with the identical
  stdout/exit-code contract (exit 0/1/3).
- Rewriting Step 7.1 in `SKILL.md` to call that script instead of inlining the heredoc. No fallback
  to the old inline logic: if the script is not deployed, Step 7.1 reports `DID-NOT-RUN` (the
  existing pattern this file already uses elsewhere for an unresolved helper), never a second
  copy of the classification.
- A new `PostToolUse` hook, `~/.claude/hooks/commit-outcome-backstop.sh`, registered in
  `~/.claude/settings.json` with `"matcher": "Skill"`. It fires on every `Skill` tool call
  (Claude Code's hook matcher filters on tool name only — verified against current hook docs, no
  skill-name-level filtering exists at the matcher or `if`-field level) and no-ops immediately
  unless `tool_input.skill == "commit"`.
- On a `commit` invocation, the hook scans `docs/manifests/*.manifest.yml` under the project root
  (resolved from the hook's `cwd` field) for manifests with `mtime` within the last 24 hours,
  filters to `status: completed` or `current_step: completed`, and runs
  `commit-outcome-check.sh` against each. Any `COMMIT_UNCOMMITTED` or `COMMIT_NONTERMINAL`
  result is surfaced as hook output (visible in the transcript) AND appended to an audit log at
  `~/.claude/state/commit-outcome-backstop/audit.log`, one line per check, same shape as
  `precompact-guard.sh`'s own audit log (timestamp, session id, decision, reason).
- Report-only, never blocking: the hook exits 0 unconditionally. A `PostToolUse` hook can inject
  text but cannot replay Step 7.1's richer stop/no-rollback messaging (ADR-0078 references, exact
  remediation steps) — that messaging stays exclusively in `SKILL.md`.
- Global scope: the hook is vendored from this repo to `~/.claude/hooks/` like every other hook
  here, and applies to every project's manifests under `concept-to-code`, not only this repo's own.
- A dedicated test fixture reconstructing the Adnota PR #36 manifest state
  (`current_step: step_7_commit`, `status: in_progress`) and asserting the hook's classification
  surfaces it as `COMMIT_NONTERMINAL`.
- Fail-open on every error path (missing manifest directory, unreadable manifest, `jq` absent,
  unwritable audit-log directory): the same convention every other hook in this repo already
  follows. An error in the backstop must never itself block or crash the tool call it observes.

**Out of scope:**
- Any blocking behavior. This hook never halts a commit, a chain, or a session — Step 7.1's own
  richer stop/no-rollback contract remains the only halting mechanism.
- Fixing the Adnota incident itself, or any other already-merged stale manifest. This SPEC covers
  detection going forward, not remediation of past occurrences.
- Extending the classification contract (`COMMIT_OK`/`COMMIT_UNCOMMITTED`/`COMMIT_NONTERMINAL`/
  `COMMIT_OUTCOME_NORUN`) itself. The extraction must be behavior-preserving.
- Any change to how or when `commit`'s own Step 4 HITL gate operates. This backstop runs strictly
  after `commit` has already returned.
- Filtering by skill name at the hook-matcher level. Verified unsupported by current Claude Code
  hook documentation; the internal `tool_input.skill` check is the only available mechanism, not a
  gap to close later.

## Stack

Bash 3.2-clean (macOS default `/bin/bash`), same conventions as every other script and hook in this
repo: no associative arrays, no `mapfile`, no process substitution. `jq` for JSON parsing of the
hook's stdin payload (same dependency `precompact-guard.sh` already has). No new runtime
dependency introduced.

## Architecture

Three new/changed pieces, one shared contract:

1. **`~/.claude/skills/concept-to-code/scripts/commit-outcome-check.sh <manifest-path>`** — pure
   function of one manifest file to one classification. Same logic currently inlined in
   `SKILL.md`'s `c2c-step7-commit-outcome` fence: read `current_step`/`status` from the manifest,
   check `git status --porcelain` on the manifest's own directory, emit exactly one of
   `COMMIT_OK` (exit 0) / `COMMIT_UNCOMMITTED untracked|modified` (exit 1) /
   `COMMIT_NONTERMINAL current_step|status` (exit 1) / `COMMIT_OUTCOME_NORUN <reason>` (exit 3).

2. **`~/.claude/hooks/commit-outcome-backstop.sh`** — the `PostToolUse` hook. Reads stdin JSON
   (`tool_input.skill`, `cwd`, `session_id`), no-ops (exit 0, silent) unless
   `tool_input.skill == "commit"`. On a `commit` match: resolve the project root by walking up from
   `cwd` looking for `docs/manifests/` (same walk-up pattern `precompact-guard.sh` already uses),
   enumerate `docs/manifests/*.manifest.yml` with `mtime` in the last 24 hours, filter to
   `status: completed` or `current_step: completed`, run `commit-outcome-check.sh` against each,
   and for every non-`COMMIT_OK` result print a report line and append an audit-log entry. Always
   exits 0.

3. **`SKILL.md` Step 7.1**, rewritten to invoke `commit-outcome-check.sh` instead of the inline
   fence, with the same branch table (`COMMIT_OK` → proceed; `COMMIT_UNCOMMITTED ...`/
   `COMMIT_NONTERMINAL ...` → stop and report, no rollback since `completed` is absorbing;
   `COMMIT_OUTCOME_NORUN`/exit 3 → report did-not-run) preserved verbatim.

Registration: `~/.claude/settings.json`, `PostToolUse` block, `{"matcher": "Skill", "hooks": [{"type": "command", "command": "\"$HOME\"/.claude/hooks/commit-outcome-backstop.sh"}]}` — same shape as the
existing `Edit|Write` entries.

## Data model

No new persistent data structures beyond:
- The audit log: `~/.claude/state/commit-outcome-backstop/audit.log`, tab-separated
  `timestamp<TAB>session_id<TAB>manifest_path<TAB>classification<TAB>reason`, append-only, same
  shape as `precompact-guard.sh`'s `audit.log`.

No change to the manifest schema itself.

## API / interfaces

`commit-outcome-check.sh` is the shared contract both `SKILL.md` Step 7.1 and the new hook call.
Its stdout/exit-code shape is the interface both sides depend on and must not change independently
of each other — the entire point of the extraction is that there is exactly one definition of
"what does this manifest's outcome classify as."

## UI / flows

No user-facing UI. The only observable surface is:
- Hook output appended to the transcript after a `commit` skill call, when a stale/non-terminal
  manifest is found (rare — only fires on a bug this backstop exists to catch).
- The audit log, for a human or a future automated check to inspect after the fact.

## Edge cases

- **Manifest directory absent** (no `docs/manifests/` anywhere up from `cwd`) → hook no-ops
  silently, exit 0. Not an error: most `commit` invocations are not inside a `concept-to-code`
  project at all.
- **`jq` missing** → fail open, exit 0, log `"jq missing"` to the audit log (same convention as
  `precompact-guard.sh`).
- **Manifest directory unwritable, or audit-log directory uncreatable** → fail open; report to
  stdout only, skip the audit-log write.
- **No manifest within the 24h window** → exit 0, no output, nothing logged. This is the
  overwhelmingly common case and must produce zero transcript noise.
- **`commit-outcome-check.sh` itself unresolved** (not deployed) → the hook reports this once per
  invocation as a distinct condition, not silently as "no stale manifest found" — an unrun check is
  not a clean result.
- **`commit` invoked with `--include`/`--branch`/`--autopilot`/`--no-pr` flags** → irrelevant to
  this backstop; it classifies whatever manifests it finds regardless of how `commit` was
  parameterized.

## Success criteria

- [ ] R-01 — `commit-outcome-check.sh` exists and, given a manifest, emits the identical
      classification (`COMMIT_OK`/`COMMIT_UNCOMMITTED ...`/`COMMIT_NONTERMINAL ...`/
      `COMMIT_OUTCOME_NORUN ...`) and exit code the current inline `SKILL.md` fence would have
      produced for the same manifest state, for at least one fixture per classification.
- [ ] R-02 — `SKILL.md` Step 7.1 is rewritten to call `commit-outcome-check.sh` and no longer
      contains the inline `c2c-step7-commit-outcome` classification logic duplicated a second time.
- [ ] R-03 — `commit-outcome-backstop.sh` exists, is registered in `~/.claude/settings.json` under
      `PostToolUse` with `"matcher": "Skill"`, and no-ops (exit 0, no output) when
      `tool_input.skill` is not `"commit"`.
- [ ] R-04 — Given a fixture manifest reproducing the Adnota PR #36 state
      (`current_step: step_7_commit`, `status: in_progress`, `mtime` within 24h) and a `commit`
      skill invocation, the hook's output classifies it as `COMMIT_NONTERMINAL current_step` and
      appends one matching entry to the audit log.
- [ ] R-05 — A manifest with `mtime` older than 24 hours is never scanned, even if it is
      `status: completed` and has an uncommitted manifest file.
- [ ] R-06 — The hook exits 0 in every tested error path (missing `docs/manifests/`, missing `jq`,
      unwritable audit-log directory, unresolved `commit-outcome-check.sh`) — it never blocks or
      crashes the `commit` tool call it observes.
- [ ] R-07 — The hook resolves the project root from the `cwd` field of its own stdin payload, not
      from any hardcoded or session-global path, so it works correctly for any project running
      `concept-to-code`, not only this repo (no-test: this is validated by the deployment/vendoring
      convention this repo already uses for every other hook, not by a project-specific test).
- [ ] R-08 — Documentation: `docs/proposal-c4-commit-outcome-hook.md`'s content is superseded by
      the ADR this chain produces; the proposal file itself is removed or clearly marked superseded
      once the ADR exists (no-test: a documentation-state check, not a behavior the harness runs).
