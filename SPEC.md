# SPEC: Codex CLI backend for the `coder` agent

**Topic slug:** codex-coder-backend-choice

## Objectives

1. Give the `coder` subagent (`staging/plugin/agents/coder.md`) a selectable backend — today's
   Claude coder, or Codex CLI — chosen once per Step 5 run, at the same per-dispatch-site moment
   ADR-0193 established for `reviewer` and ADR-0194 already implements for `tester`.
2. Unlike `tester` (ADR-0194 R2/R6, which deliberately does not expose a Codex model or effort),
   expose a live choice of **both** Codex model (Astra / Sol) and reasoning effort every time the
   gate fires, with no silent inheritance across a resumed Step 5 run.
3. Preserve full behavioural parity with today's Claude `coder` wherever technically possible;
   document every place parity is structurally impossible as a named, disclosed gap, never a
   silent omission.

## Scope

**In:**
- New script `codex-coder.sh`, structurally mirroring `codex-tester.sh` (same flag shape, same
  availability cascade via `codex doctor --json`, same exit 0/2/3 contract, plus a new exit 4 for
  a scope violation).
- `--model <astra|sol>` and `--effort <low|medium|high|xhigh|max|ultra>` flags on `codex-coder.sh`,
  mapped to `-c model="gpt-6-astra"|"gpt-5.6-sol" -c model_reasoning_effort=<value>` on the
  underlying `codex exec` call. Both required (no silent config.toml inheritance, unlike
  `codex-tester.sh`'s deliberate choice in ADR-0194 R2) — the whole point of this feature is a live
  choice, not an inherited one.
- One `AskUserQuestion` gate immediately before Step 5's coder dispatch, covering both dispatch
  paths (Workflow `pipeline()` and Agent-tool batch), offering `claude-sonnet` (default,
  today's behaviour) / `codex`. On `codex`, two follow-up choices in the same gate turn: model
  (`Astra` default / `Sol`) and effort (`medium` default / `low` / `high` / `xhigh` / `max` /
  `ultra`).
- **The gate re-fires on every Step 5 entry, fresh and resumed alike** — no manifest field is read
  to skip it on a resumed run. This is a deliberate divergence from `codex-tester.sh`'s
  `step5_codex_tester_asked` pattern (ADR-0194 R8's disclosed hole), because Stefano's own
  requirement is a fresh choice every time, not an inherited one.
- New manifest fields, additive under schema `1.4` (no version bump, same treatment ADR-0193/0194
  gave their own fields): `use_codex_coder` (bool, default `false`, records the LAST choice made,
  informational only — since the gate always re-asks, this field is never read to skip the ask),
  `step5_codex_coder_model` (string enum `astra|sol`, nullable), `step5_codex_coder_effort` (string
  enum, nullable). No `step5_codex_coder_asked` field — its entire purpose in the tester's design is
  to skip a re-ask, which this feature explicitly rejects. New conditional Invariants 28 and 29 in
  `manifest-validate.sh` (next free after 26/27).
- Sandbox: `-s workspace-write -C <worktree>` (never read-only, never danger-full-access), exactly
  ADR-0194's mitigation for the same read-write risk `tester` already carries.
- Post-hoc scope-check, reusing ADR-0194 R4's method verbatim (union of `git diff --name-only`,
  `git diff --name-only --cached`, `git ls-files --others --exclude-standard` against a baseline
  captured immediately before `codex exec` runs). A path in the post-run set and not in the
  baseline is flagged if it is: `.claude/test-cmd`, a test file not assigned to this coder's batch,
  or a second (or more) new file under `.claude/agent-memory/coder/topics/`, or any touch to
  `.claude/agent-memory/coder/MEMORY.md`. A `git commit` appearing in the worktree's log since the
  baseline is checked separately (not a path-based check). Any violation is exit 4.
- On exit 3 (DID-NOT-RUN) or exit 4 (scope violation): ask the user — fallback to Claude coder, or
  halt (same never-silent principle as ADR-0187/0193/0194). Exit 4 additionally offers "accept the
  write and continue" (same as `codex-tester.sh`'s exit 4 — the scope-check is a heuristic and can
  false-positive), per Stefano's explicit choice to keep the tester's exact behaviour here rather
  than a stricter always-halt policy.
- Codex's final structured message (`--output-schema`) includes a per-hunk classification
  (ADD/REMOVE/REPLACE/MODIFY) as a documented, weaker substitute for the Claude-side PATTERN
  header, which cannot fire pre-edit on an external, non-interactive `codex exec` run. Verified
  only post-hoc, never blocking.
- Same "Workflow path drops the coder stage from `pipeline()` and runs `codex-coder.sh` in the
  orchestrator's own live turn, sequentially" structural fix as ADR-0194 R5, for the same reason:
  a Workflow script has no `AskUserQuestion` hook, so exit 3/4 resolution is impossible from inside
  a running pipeline stage, and a coder that silently did not run is unlivable (arguably worse than
  R5's tester case — nothing downstream has anything to review or commit).
- Prompt embedded in `codex-coder.sh` hand-ported from `coder.md`'s Hard rules, Process, Quality
  Standards, Output Format, Edge Cases (rule 6/12 duplication, declared exactly as
  `codex-reviewer.sh`/`codex-tester.sh` already declare their own ports).
- Explicit, named documentation of every parity gap (see Documented gaps below) inside the new ADR.

**Out:**
- The `tester` substitution (ADR-0194, done), the `reviewer` substitution (ADR-0187/0193, done).
- `debugger`, `refactorer`, `researcher` backend choice (VCS-074 maps them, undecided, separate
  future work).
- Any change to `codex-reviewer.sh` or `codex-tester.sh` themselves.
- Extraction of a shared `codex-common.sh` availability-cascade module (ADR-0194 R7 already defers
  this across two scripts; a third copy is declared duplication, not solved here).
- Wiring a new eslint MCP server for Codex, or authenticating Codex's own `context7` MCP entry —
  see Documented gaps: MCP parity below, deferred as a named follow-up after this session's live
  check found the eslint side unresolvable within scope and the context7 side needing an
  authentication step outside this feature's boundary.

## Documented gaps (parity is not fully achievable — named, not silent)

1. **Three Claude-hook-enforced controls do not fire on Codex's internal edits.**
   `pre-flight-pattern-enforce.sh`, `write-scope-enforce.sh`/`test-write-scope.sh`, and
   `coder-memory-scope.sh` are Claude PreToolUse/PostToolUse hooks; a `codex exec` subprocess's own
   edits are invisible to them (a Bash call to `codex exec` is one opaque tool call to Claude).
   Mitigation: sandbox containment (`-s workspace-write -C <worktree>`, real enforcement, not an
   instruction) plus the post-hoc scope-check above (a safety net, not a preventive block — the
   write has already happened inside the isolated worktree by the time the check runs).
2. **The PATTERN pre-flight classifier has no per-call equivalent.** Codex produces one final diff
   from a non-interactive run, not a sequence of hookable Edit/Write tool calls. Downgraded to a
   post-hoc, self-reported, non-blocking per-hunk classification in the structured output.
3. **LSP has no Codex-side equivalent at all.** Live-checked this session: `codex mcp list` /
   `codex exec --help` expose no hover/find-references capable server, and Claude's own `LSP` tool
   is a native Claude Code capability, not an MCP server — there is nothing to wire into Codex's
   own MCP mechanism (`codex mcp add`) even in principle. This is a hard gap, not a deferred one.
4. **`eslint` MCP parity is unresolved, not confirmed either way.** Live-checked this session: no
   `eslint` MCP server definition was found anywhere on this machine — not in `~/.claude/settings.json`,
   not in any installed plugin's catalog entry, not in `~/.claude.json`, not in this project's
   (nonexistent) `.mcp.json`. Coder.md's own tool list already tolerates this class of absence
   (`coder.md` step 3: "If those tools are absent from your tool list (native macOS and Linux
   builds, ADR-0038), skip this step without comment") — so a Codex coder without eslint access
   degrades exactly the same way a Claude coder already does in an environment where eslint MCP is
   not configured. Not a new failure mode; the existing graceful-degradation path already covers it.
5. **`context7` parity is partially wired, unauthenticated, unverified live.** Live-checked this
   session: `codex mcp list` already shows a `context7` remote MCP server pre-registered
   (`https://mcp.context7.com/mcp`, `streamable_http`), status `enabled` but `Not logged in`.
   Whether `codex exec` can actually reach it from inside a sandboxed, non-interactive run — and
   whether an OAuth-style login flow is even possible in that context — was not tested live this
   session (would require an interactive login step, out of scope for this feasibility check).
   Recorded as a named follow-up, not solved here.

## Stack / architecture

Same as `codex-tester.sh`/`codex-reviewer.sh`: Bash 3.2-clean script under `staging/plugin/scripts/`,
deployed to `~/.claude/hooks/` via `sync-to-claude.sh`'s PAIRS mechanism (post-PR #575, symlink-write
refusal now enforced there — verify the new script deploys through it cleanly, not around it).
`codex exec -s workspace-write -C <worktree> -c model=<slug> -c model_reasoning_effort=<level>
--output-schema <file> -o <file>`. Two dispatch-site edits in
`staging/plugin/skills/concept-to-code/references/step5-implementation.md` (Workflow path ~line
542/710, Agent-tool path ~line 1585/1596). Manifest schema changes in `manifest-init.sh` and
`manifest-validate.sh`. New harness `codex-coder-dispatch-gate.test.sh`, parallel to
`codex-tester-dispatch-gate.test.sh`, offline/hermetic against a stub `codex` on `PATH` — never a
live Codex call in CI, matching this repo's convention.

## Data model

Manifest additions (schema 1.4, additive):
- `use_codex_coder: false` — last choice made, informational, never read to skip the gate.
- `step5_codex_coder_model: null` — `"astra"` or `"sol"` after a `codex` choice; null otherwise.
- `step5_codex_coder_effort: null` — one of `low|medium|high|xhigh|max|ultra`; null otherwise.

## API / interfaces

```
codex-coder.sh --worktree <dir> --brief <file> --out <file> --model <astra|sol> --effort <level>
```
Exit codes: `0` success, `2` bad invocation, `3` DID-NOT-RUN (named reason on stderr), `4` scope
violation (touched path(s) named on stderr).

## UI flows

One `AskUserQuestion` gate before Step 5's coder dispatch (both paths), options `claude-sonnet`
(default) / `codex`; on `codex`, two follow-up selections in the same turn (model, default Astra;
effort, default medium). Re-presented on every Step 5 entry, fresh or resumed, with no
manifest-driven skip.

On Codex exit 3 or 4: a second `AskUserQuestion` — fallback to Claude coder, or halt (exit 4 also
offers "accept and continue").

## Edge cases

- Codex CLI absent, unauthenticated, or rate-limited → exit 3, same availability cascade as
  `codex-reviewer.sh`/`codex-tester.sh`.
- Zero files touched by Codex → exit 0 with a distinct `NOTE:` on stderr (ADR-0194 R4's precedent:
  "wrote nothing" and "wrote only assigned files" are different facts).
- A resumed Step 5 run with `manifest.use_codex_coder` already set from a prior partial run → the
  gate still re-fires (R-08); the stale value is display-only context, never authoritative.
- `--model`/`--effort` both required on the `codex` branch — no default silently governs if the
  gate is somehow bypassed; a caller invoking `codex-coder.sh` without them exits 2.

## Success criteria

- [ ] R-01 — A single `AskUserQuestion` gate, at the per-dispatch-site moment (before Step 5's
      coder dispatch, both Workflow and Agent-tool paths), offers `claude-sonnet` (default) /
      `codex`.
- [ ] R-02 — On `codex`, the same gate turn additionally asks for model (`astra` default / `sol`)
      and effort (`medium` default / `low`/`high`/`xhigh`/`max`/`ultra`).
- [ ] R-03 — The gate re-fires on every Step 5 entry, fresh or resumed, with no manifest field
      causing it to be silently skipped.
- [ ] R-04 — `codex-coder.sh` exists, structurally mirrors `codex-tester.sh`'s flag shape and
      availability cascade, and requires `--model`/`--effort` explicitly (no config.toml
      inheritance).
- [ ] R-05 — `codex-coder.sh` runs `codex exec -s workspace-write -C <worktree>`, never read-only,
      never danger-full-access.
- [ ] R-06 — A post-run scope-check (union of `git diff --name-only`, `--cached`, and
      `git ls-files --others --exclude-standard` against a pre-run baseline) flags: a touch to
      `.claude/test-cmd`, a touch to an unassigned test file, more than one new file under
      `.claude/agent-memory/coder/topics/`, a touch to `.claude/agent-memory/coder/MEMORY.md`, or a
      `git commit` in the worktree's log since baseline — any of these is exit 4.
- [ ] R-07 — On exit 3 or 4, the user is asked to fall back to Claude or halt; exit 4 additionally
      offers "accept and continue". Never a silent fallback.
- [ ] R-08 — Zero files touched by Codex is exit 0 with a distinct `NOTE:` on stderr, never
      conflated with a scope violation.
- [ ] R-09 — On the `codex` branch, the Workflow path drops the coder stage from `pipeline()` and
      `codex-coder.sh` runs in the orchestrator's own live turn, sequentially, exactly as ADR-0194
      R5 already does for `tester`.
- [ ] R-10 — New manifest fields (`use_codex_coder`, `step5_codex_coder_model`,
      `step5_codex_coder_effort`) are additive under schema `1.4`, seeded in `manifest-init.sh`,
      validated by new conditional Invariants 28/29 in `manifest-validate.sh`.
- [ ] R-11 — The ADR names, explicitly, the five documented gaps above (hook-enforcement,
      PATTERN classifier, LSP, eslint, context7) as disclosed limitations, never silently dropped
      (no-test: this is a documentation requirement the ADR's own text satisfies, not something a
      test asserts).
- [ ] R-12 — A new offline/hermetic test harness (`codex-coder-dispatch-gate.test.sh`) covers the
      exit 0/2/3/4 contract, the scope-check's four violation classes plus the zero-touch case, the
      manifest field trio, and the exactly-two dispatch sites that point back at the single gate —
      against a stub `codex` on `PATH`, never a live Codex call.
- [ ] R-13 — `codex-coder.sh` deploys cleanly through `sync-to-claude.sh`'s PAIRS mechanism,
      confirmed not to trip the post-PR #575 symlink-write refusal (no-test: a one-time deployment
      verification, not an ongoing assertion).
