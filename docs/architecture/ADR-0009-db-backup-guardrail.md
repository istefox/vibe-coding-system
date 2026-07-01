# ADR-0009 — db-backup-guardrail (PreToolUse hook anti-DB-destruction)

**Status:** Accepted  
**Date:** 2026-05-22  
**Author:** istefox  
**Supersedes:** none  
**Superseded by:** none  
**Related:** ADR-0004 (pre-flight-pattern-enforce hook — reused bash 3.2-clean hook pattern),
ADR-0001 (coder pre-flight classifier — defense-in-depth philosophy),
`feedback_never-bypass-guardrails`, `feedback_pretooluse-payload-schema`,
`feedback_bash32-constraint`.

---

## Context

The user's global rules (`~/.claude/CLAUDE.md`) already impose, **as text**:

- "HITL gate always before: commit, push, deploy, **DB schema modification**, permanent
  deletions."
- "never destructive commands (`rm -rf`, `DROP TABLE`) without asking."
- "Back up before modifying critical files."

These rules are enforced only by LLM discipline — no deterministic mechanism applies them.
The nightmare scenario "prod db deleted by accident" can materialize in two ways:

1. **Orchestrator in auto mode** that, applying a migration or executing a maintenance
   command, launches an `alembic downgrade` / `DROP TABLE` / `prisma migrate reset`
   against a production database without a recent backup.
2. **Sub-agent coder** that, during feature implementation, executes a destructive statement
   via `psql`/`mysql`/migration CLI.

The system already has a consolidated hook pattern (`pre-flight-pattern-enforce.sh`, ADR-0004;
`stop-gate.sh`) bash 3.2-clean, fail-open, with audit log and dedicated harness. This ADR
**formalizes and automates** the above textual rules as the 5th PreToolUse guardrail,
consistent with the system's defense-in-depth philosophy.

**Explicit assumptions (not validated):**

- The PreToolUse payload schema is the one empirically verified in
  `feedback_pretooluse-payload-schema` (fields `session_id`, `tool_input.command`,
  `agent_id`, `agent_type`, `cwd`). Verified for the cited fields; the sub-field
  `tool_input.command` for Bash tools is taken as established by the brief (verified).
- The PreToolUse output contract used by this hook is the **modern** format
  `exit 0 + {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":...,"permissionDecisionReason":...}}`
  (verified at `code.claude.com/docs`, see "permissionDecision Contract" section).
  NOT the legacy `{"decision":"block","reason":...}` of `stop-gate.sh` /
  `pre-flight-pattern-enforce.sh`: the modern format is necessary to discriminate the three
  outcomes `allow`/`ask`/`deny` (legacy has only hard block, no "ask").
- **Discriminant orchestrator vs sub-agent = presence/absence of the `agent_id` field** in the
  payload. Same mechanism already used by `pre-flight-pattern-enforce` for `agent_type`.
  `agent_id` absent -> decision originated from the orchestrator / user in foreground;
  `agent_id` present -> decision originated from a sub-agent in auto mode.
- **Doc gap (not verified):** the behavior of `permissionDecision:"ask"` when the decision
  originates from a sub-agent (user NOT in foreground) is NOT documented. For this reason
  the ADR does NOT rely on `ask` for sub-agents (see D3).
- The user does NOT currently have a standard convention for the DB backup directory. The
  backup-check contract proposed is a **new convention** introduced by this ADR (see Decision D2).

---

## Decision

Introduce `~/.claude/hooks/db-backup-guardrail.sh`: hook **PreToolUse on `Bash` matcher**
that inspects `tool_input.command` and, if it detects a potentially destructive DB command
**without evidence of a recent backup or explicit confirmation**, escalates the outcome via
`hookSpecificOutput.permissionDecision` with a **3-outcome gate** (`allow`/`ask`/`deny`),
differentiated based on the presence of `agent_id` (orchestrator -> `ask`, sub-agent ->
`deny`). Bash 3.2-clean, audit log, dedicated harness, asymmetric fail-mode (see D8 —
motivated exception to the system's fail-open: fail-open upstream of match, but after
match+no-backup never `allow`).

Below is the decision for each of the 8 architectural questions.

### D1 — Detection: which patterns to intercept

`grep -E` regex (POSIX-EXT, case-insensitive via `grep -iE`) on `tool_input.command`,
normalized (whitespace collapsed to single space) before matching. Two families:

**Family A — Destructive SQL (via psql/mysql/sqlite3 CLI or heredoc/`-c`):**

| # | Pattern (conceptual) | Regex EXT (case-insensitive) |
|---|---|---|
| A1 | DROP TABLE / DROP DATABASE / DROP SCHEMA | `\bdrop[[:space:]]+(table\|database\|schema)\b` |
| A2 | TRUNCATE | `\btruncate[[:space:]]+(table[[:space:]]+)?` |
| A3 | DELETE FROM without WHERE | `\bdelete[[:space:]]+from\b` **AND NOT** `\bwhere\b` (in the same statement) |
| A4 | ALTER TABLE ... DROP COLUMN/CONSTRAINT | `\balter[[:space:]]+table\b.*\bdrop\b` |
| A5 | UPDATE without WHERE | `\bupdate[[:space:]]+[a-z_."]+[[:space:]]+set\b` **AND NOT** `\bwhere\b` |

**Family B — Destructive migration tools:**

| # | Tool | Regex EXT (case-insensitive) |
|---|---|---|
| B1 | alembic downgrade | `\balembic[[:space:]]+downgrade\b` |
| B2 | prisma migrate reset / db push --force-reset | `\bprisma[[:space:]]+(migrate[[:space:]]+reset\|db[[:space:]]+push)\b` |
| B3 | django flush / migrate zero | `\bmanage\.py[[:space:]]+(flush\|sqlflush)\b` or `\bmigrate[[:space:]]+\w+[[:space:]]+zero\b` |
| B4 | knex migrate:rollback / down | `\bknex[[:space:]]+migrate:(rollback\|down)\b` |
| B5 | sequelize db:migrate:undo / db:drop | `\bsequelize[[:space:]]+db:(migrate:undo\|drop)\b` |
| B6 | rails db:drop / db:reset / db:rollback | `\brails[[:space:]]+db:(drop\|reset\|rollback)\b` or `\brake[[:space:]]+db:(drop\|reset)\b` |

**Controlled false positives (MUST remain allow):**

- `DELETE FROM ... WHERE ...` -> A3 excluded by presence of `WHERE` -> allow.
- `SELECT ... -- comment about drop table` or `SELECT 'drop' as col` -> no pattern A
  matches because anchored to `\bdrop[[:space:]]+(table|database|schema)\b` (the DROP keyword
  must precede TABLE/DATABASE/SCHEMA), not the isolated word "drop".
- `pg_dump`, `mysqldump`, `sqlite3 .dump` (backup commands) -> match no destructive
  pattern -> allow (in fact they are the remedy).
- `alembic upgrade head`, `prisma migrate deploy`, `django migrate` (forward) -> do NOT
  match (B1 is only `downgrade`; B2 is only `reset`/`db push`) -> allow.
- `git commit -m "drop table feature"` -> does not match A1 (regex requires `drop` followed by
  whitespace + table/database/schema as SQL keyword; "drop table feature" would match A1).
  **Known limitation:** a commit message containing literally "drop table" produces a false
  positive. Mitigation: the statement must appear in an executable context; the guard does not
  distinguish strings in a quoting-aware manner (bash 3.2, no SQL parser). Accepted as
  trade-off; the false positive is fail-safe (`ask`/`deny` with clear message, the user
  confirms or the sub-agent reports).

**Rationale:** regex anchored to keyword-pairs (DROP+TABLE, not DROP alone; DELETE+FROM
without WHERE) minimize false positives on the "word drop in text" case. Matching is
intentionally lexical and not semantic (no SQL parser) to remain bash 3.2-clean and
stack-agnostic.

### D2 — What counts as a present/recent backup

The backup-check is satisfied (-> `allow`, no output) if **any one** of these conditions
is true, in evaluation order:

1. **Explicit single-call confirmation:** env var `DB_GUARDRAIL=off` (bypass, D6) — NOT a
   "backup" but a human override; evaluated first.
2. **Explicit confirmation marker:** file `.claude/db-backup-confirmed` in the project root
   (ascending from `cwd`, like `stop-gate.sh` ascends for `.claude/test-cmd`), with **mtime
   within N hours** (`DB_BACKUP_MAX_AGE_HOURS`, default 24). Stale file (older than N hours) ->
   not valid. Rationale: the marker certifies "I made a backup now", not "I did one at some
   point in my life".
3. **Recent conventional backup file:** at least one file in `<root>/.backups/` with extension
   `*.dump`, `*.sql`, `*.sql.gz`, `*.dump.gz` and **mtime within N hours**. Rationale:
   explicit directory convention (`.backups/`), not a full filesystem scan (bounded, fast).

If no condition is true -> enter the ask/deny gate of D3 (never `allow`).

**Rationale for "recent":** a 3-month-old backup does not protect against the nightmare
scenario. The mtime-within-N-hours constraint ties the backup to the current work session.
N configurable via env for workflows with automated nightly backups (e.g. N=30).

### D3 — Gate outcome: ask/deny split (was: block/warn)

When the command is classified as destructive (D1) and the backup-check is NOT satisfied (D2)
and no bypass is active (D6), the outcome **is not a uniform hard block** but a 3-outcome gate
based on `hookSpecificOutput.permissionDecision`, differentiated based on the presence of
the `agent_id` field:

| Condition | permissionDecision | Audience of reason |
|------------|--------------------|----------------------|
| non-Bash command / non-DB / missing jq / malformed JSON | **no output** (allow, fail-open upstream of match) | — |
| destructive DB + valid backup (marker `.claude/db-backup-confirmed` or file `.backups/*.dump\|*.sql[.gz]` fresh <N h) | **no output** (allow) | — |
| destructive DB + NO backup + bypass active (`DB_GUARDRAIL=off` or marker `.claude/db-is-ephemeral`) | **no output** (allow) | — |
| destructive DB + NO backup + **`agent_id` ABSENT** (orchestrator / user in foreground) | **`ask`** + reason | legitimate remedies (backup + marker) |
| destructive DB + NO backup + **`agent_id` PRESENT** (sub-agent in auto mode) | **`deny`** + reason | "STOP and report to orchestrator" — NO bypass |

**Rationale for the ask/deny split:**

- **Orchestrator -> `ask`:** the user gets the requested interactive y/n gate. `ask` escalates
  to the user even in auto mode (verified at `code.claude.com/docs`), so there is NO need to
  create markers manually for legitimate cases: the user confirms or denies on the fly. The
  reason lists legitimate remedies (backup + marker) for those who want to make the
  confirmation persistent.
- **Sub-agent -> `deny`:** two converging reasons. (1) **Doc gap:** `ask` might NOT be shown
  in subagent context (user not in foreground) — not documented, not relied upon. (2)
  **Discipline:** a sub-agent must not autonomously decide on a destructive DB command — it
  stops and reports (consistent with `feedback_never-bypass-guardrails`). The `deny` reason for
  the sub-agent **does not suggest bypass**: it only says "STOP, this operation requires a
  backup or explicit user confirmation; report to the orchestrator".

Pure warn remains rejected (see Alternatives): it does not prevent the scenario in auto mode.
The `ask` outcome (for the orchestrator) replaces the previous hard block because it gives the
user interactive control without marker friction, while remaining blocking in the absence of
confirmation.

### D4 — Dev vs prod: how to distinguish

**Indiscriminate application with prod-aware override.** The guard applies to all detected
destructive commands, regardless of dev/prod. Rationale: reliably distinguishing prod is
impossible in bash 3.2-clean without parsing the connection string (host, ports, env var
DATABASE_URL not always present in the command). A false negative (prod mistaken for dev) is
the catastrophic failure the guard exists to prevent.

**Escape-hatch for dev ephemeral DB:** marker `.claude/db-is-ephemeral` in the project root
-> the guard degrades to a **silent no-op** (allow, no output) for that project (the user
explicitly declares that repo only works with ephemeral DBs). HUMAN decision, file created by
the user, never by the sub-agent.

**Opportunistic prod signal (for the reason only, not the decision):** if `tool_input.command`
contains a non-localhost host or `DATABASE_URL` with a remote host, the gate reason highlights
it ("detected possible production target"). Does not change the outcome (`ask`/`deny` remains),
only enriches the audit/message.

### D5 — DB scope

**Stack-agnostic, both CLI and migration tool.** Postgres/MySQL/SQLite covered via CLI patterns
(Family A, valid for psql/mysql/sqlite3 that receive inline SQL) and via migration tools
(Family B, covers alembic/prisma/django/knex/sequelize/rails). Matching is on the command text,
so it does not depend on the driver: a `DROP TABLE` inside `psql -c "..."`, `mysql -e "..."`,
`sqlite3 db.sqlite "..."` or a heredoc matches identically. Rationale: consistent with the
multi-stack nature of the system (Python/Swift/JS), zero dependencies, no stack-lock.

### D6 — Bypass (HUMAN decision, never by the sub-agent)

Three layers, all intended to be activated by the **user/orchestrator**, never by the coder.
All produce `allow` (no output) — short-circuit the ask/deny gate of D3:

1. **Single-call env var:** `DB_GUARDRAIL=off` -> immediate allow + audit `bypass-env`.
2. **Explicit confirmation marker:** `.claude/db-backup-confirmed` (within N hours, D2.2) —
   the user creates it after making a backup.
3. **Disable from settings.json:** remove the hook entry (no execution).

(The `.claude/db-is-ephemeral` marker of D4 is a fourth mechanism, but it is project-scoped
and a no-op rather than a per-call bypass.)

**Note — the orchestrator no longer needs to create markers for legitimate cases:** with the
`ask` outcome (D3), a legitimate destructive command from the orchestrator produces an
interactive y/n prompt. The user confirms on the fly. The D6 markers remain useful for: (a)
making the confirmation persistent within the N-hour window (D6.2), (b) contexts where `ask`
is not shown (sub-agent -> but there the route is to do the backup, not the bypass).

**Constraint from `never-bypass-guardrails` feedback:** the gate reason, when `agent_id` is
present (sub-agent), produces `deny` and **does NOT mention any bypass method** — it only says
"STOP and report to the orchestrator". Only when `agent_id` is absent (orchestrator) does the
reason (with `ask` outcome) list legitimate remedies (backup + marker). This avoids teaching
the coder the bypass.

### D7 — Coexistence with other hooks

The db-backup-guardrail is **PreToolUse on `Bash` matcher**. Other existing PreToolUse hooks are
on `Edit|Write` matcher (protect-files) and `Edit|Write|MultiEdit` matcher
(pre-flight-pattern-enforce). **No matcher overlap with these two** -> no double-prompt with them.

The only co-habitant on `Bash` is `approve-test-cmd.sh`, which however **is NOT a hook** (it is
a CLI TOFU invoked manually, not in `settings.json` as PreToolUse hook). `stop-gate.sh` is on
the `Stop` event, not `PreToolUse`. Therefore **no race / double prompt** with active hooks.

Order in `settings.json`: new PreToolUse entry with `Bash` matcher, **after** the two
`Edit|Write*` entries (order between disjoint matchers is irrelevant, but appending preserves
diff readability). When in the future another hook on `Bash` is added, the order will need to
be reconsidered; for now it is isolated.

### D8 — Who is subject + fail-mode

**All agents + the orchestrator.** Unlike `pre-flight-pattern-enforce` (coder-only, because it
enforces a coder-specific contract), the "prod db deleted" scenario can originate from both the
orchestrator (auto mode, maintenance) and a coder (migration in a feature). Therefore **no
filter that excludes agents**: the guard evaluates every destructive Bash command, whoever emits
it. The presence/absence of `agent_id` does not filter *who is subject* — all are subject —
but **discriminates only the gate outcome** (`ask` for the orchestrator, `deny` for the
sub-agent) and the reason text (D3/D6).

**Fail-mode — motivated exception to the system's fail-open:**

- **Fail-OPEN on infrastructural errors upstream of match** (missing jq, malformed JSON, empty
  stdin, non-DB command): if the guard cannot even determine if the command is destructive, **no
  output** (allow) + audit `fail-open`/`not-db`. Consistent with the system: a guard that
  crashes must not block legitimate non-DB work.
- **Fail-CLOSED once the command is classified as destructive** and the backup-check is not
  satisfied: ask/deny gate (never `allow`). Moreover, if the destructive match is certain but
  the backup-check itself fails for internal error (e.g. unable to read mtime), the ask/deny
  gate is entered anyway (not allow): when in doubt about a command already recognized as
  destructive, protect. The choice between `ask` and `deny` remains governed by `agent_id`
  even in the internal error branch.

Rationale: the system-wide fail-open is correct for discipline guards (pattern-enforce); for an
**irreversible data security guard** the default on ambiguity must be conservative, but **only
after** the command has been recognized as destructive — never block a non-DB command for an
internal error. This balances security and friction.

---

## permissionDecision Contract (modern format, verified)

This section documents the output contract used by the hook, replacing the legacy hard block.

**Output format (stdout, always exit 0):**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "<allow|deny|ask|defer>",
    "permissionDecisionReason": "<text>"
  }
}
```

**`permissionDecision` values (verified at `code.claude.com/docs`):**

- `allow` — executes the tool without prompt. *This hook does not emit it explicitly: for the
  allow outcome it emits no output* (see note below).
- `deny` — blocks tool execution. The sub-agent stops and receives the reason.
- `ask` — escalates to the user with a y/n confirmation prompt. **Works even in auto mode**
  (the doc confirms: `ask` escalates to the user even when auto mode would skip dialogs).
- `defer` — not used by this hook.

**Convention "no output = allow":** when the hook decides allow (non-DB command, valid backup,
bypass active) it does NOT emit any JSON and exits 0. The doc specifies: if the hook emits no
output -> "no decision, normal permissions flow" (= execution allowed). This avoids forcing an
explicit `allow` that might override other hooks/permissions.

**Doc gap — `ask` behavior in subagent context (NOT verified):** the doc does NOT document what
happens when `permissionDecision:"ask"` is emitted while the decision originates from a sub-agent
(user not in foreground). It might: (a) not show the prompt and proceed, (b) implicitly block,
(c) escalate to the orchestrator. **None of these is guaranteed.** For this reason the hook does
NOT use `ask` for sub-agents: if `agent_id` is present, it emits `deny` (defined and safe
outcome). `ask` is reserved for the orchestrator (`agent_id` absent), where the user IS in the
foreground and the prompt is documented as working.

**Orchestrator vs sub-agent discrimination:** presence/absence of the `agent_id` field in the
payload (same mechanism already used by `pre-flight-pattern-enforce` for `agent_type`).
`agent_id` absent -> `ask`; `agent_id` present -> `deny`.

**Ask/deny rationale (summary):** orchestrator gets the requested interactive gate (no manual
markers for legitimate cases); sub-agent gets a deterministic block that stops it and makes it
report, without relying on an undocumented `ask` behavior and without teaching the bypass.

**Example `ask` output (orchestrator, no backup):**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "db-backup-guardrail: potentially destructive DB command (DROP TABLE) without evidence of a recent backup. Proceed? To make it persistent: run a backup in <root>/.backups/ or confirm with touch <root>/.claude/db-backup-confirmed. If the target is an ephemeral DB: touch <root>/.claude/db-is-ephemeral."
  }
}
```

**Example `deny` output (sub-agent, no backup):**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "db-backup-guardrail: potentially destructive DB command (DROP TABLE) without evidence of a recent backup. STOP: do not execute. This operation requires a backup or explicit user confirmation. Report to the orchestrator and wait for instructions. Do not attempt to bypass this guardrail."
  }
}
```

**Asymmetric fail-mode preserved:** fail-open upstream of match (no output = allow);
after match + no-backup -> never `allow`, always `ask` (orchestrator) or `deny` (sub-agent).

---

## Alternatives considered (for each of the 8 questions)

### D1 — Detection

- **AST/SQL parser for semantic matching (e.g. sqlparse, libpg_query):** rejected. Introduces
  a stack-locked dependency, violates bash 3.2-clean and zero-dep. The precision gain does not
  justify the cost for a guardrail that is in any case a layer (not the only defense).
- **Match on isolated word `drop`/`delete`/`truncate`:** rejected. Unacceptable false positives
  (SELECT with "drop" in text, commit messages). Keyword-pair regex is the right trade-off.
- **Allowlist instead of denylist (block everything except known-safe patterns):** rejected.
  Would block every Bash command by default -> enormous friction, incompatible with auto mode.

### D2 — Present/recent backup

- **Only presence of a file in `.backups/` without mtime constraint:** rejected. A stale backup
  does not protect against the nightmare scenario; it would give false security.
- **Backup detected from transcript (pg_dump command executed in the same session):** rejected
  as primary mechanism. Fragile (transcript parsing, path encoding already a source of bugs in
  ADR-0004 v1.1), and a failed but present pg_dump in the transcript would give a false
  positive. Possibly held as future enrichment, not in scope now.
- **No concept of "recent", only permanent marker:** rejected, same problem as stale backup.

### D3 — Gate outcome (ask/deny vs hard block vs warn)

- **Uniform hard block (`{"decision":"block"}` legacy, single outcome for all):** rejected (was
  the previous decision). Legacy does not distinguish audience nor offers the interactive prompt:
  the orchestrator was forced to create a marker by hand even for legitimate operations ->
  friction. The modern `permissionDecision` format allows `ask` for the orchestrator (on-the-fly
  y/n gate) and `deny` for the sub-agent (deterministic block), which is strictly superior.
- **`ask` for all (including sub-agents):** rejected. The behavior of `ask` in subagent context
  is NOT documented (doc gap): it might not show any prompt and proceed, defeating the guard for
  the coder case. Moreover it would violate `never-bypass-guardrails` (a sub-agent must not
  decide on a destructive command). For the sub-agent a defined outcome is needed = `deny`.
- **`deny` for all (including orchestrator):** rejected. Would work but is unnecessarily rigid
  for the orchestrator/user in foreground: denies without giving the interactive path, forcing
  manual marker creation. `ask` gives the requested y/n gate.
- **Warn-only (audit, no gate):** rejected. In auto mode the LLM would ignore the warn and
  proceed — does not prevent the scenario.

### D4 — Dev vs prod

- **Prod detection via connection string / DATABASE_URL parsing:** rejected as the decision
  discriminant. Unreliable (host not always in the command, env vars not capturable by the hook),
  and a false negative is catastrophic. Used only to enrich the gate reason.
- **Apply only to prod (skip dev):** rejected. Would require the reliable prod detection above,
  which does not exist. Safer default = apply to all, with explicit escape for ephemeral DBs.

### D5 — DB scope

- **Postgres-only via psql:** rejected. The system is multi-stack; covering only one engine
  leaves gaps (a Django/MySQL project would remain unprotected).
- **Migration tools only (no direct SQL CLI):** rejected. A direct `psql -c "DROP TABLE"` is
  precisely the most dangerous case and would bypass the guard.

### D6 — Bypass

- **Bypass via inline command flag (e.g. `# db-guardrail-ok`):** rejected. A sub-agent could
  add it by itself -> violates `never-bypass-guardrails`.
- **Same gate reason for all audiences (with bypass instructions):** rejected explicitly — it
  is the error corrected in ADR-0004 v1.2. The `deny` reason for the sub-agent must not teach
  the bypass; only the `ask` for the orchestrator lists remedies.

### D7 — Coexistence

- **Matcher `*` (all tools):** rejected. Wasteful (the guard only makes sense on Bash);
  would introduce unnecessary overlap with protect-files and pattern-enforce.
- **Merge into existing pre-flight-pattern-enforce:** rejected. Violates single responsibility
  (one enforces coder contract on Edit/Write, the other protects the DB on Bash); harness and
  fail-mode differ (pattern-enforce is pure fail-open, this is fail-closed on match). Keeping
  them orthogonal is consistent with the "triple-angle coverage" of agent-notes.

### D8 — Who is subject + fail-mode

- **Coder-only (like pre-flight-pattern-enforce):** rejected. The orchestrator in auto mode is
  a realistic source of the nightmare scenario; excluding it leaves the main gap open.
- **Pure fail-open (like other system hooks):** rejected for the post-match phase. For an
  irreversible data guard, ambiguity on a command already recognized as destructive must resolve
  to the ask/deny gate (never allow). Fail-open is preserved only upstream (infrastructural
  errors / non-DB commands) to avoid adding friction to legitimate non-DB work.

---

## Consequences

### Positive

- The textual rules of `~/.claude/CLAUDE.md` on DB become deterministically enforced.
- Prevents the nightmare scenario "prod db deleted" from both orchestrator and coder.
- **Interactive gate for the orchestrator (`ask`):** the user gets an on-the-fly y/n prompt for
  legitimate operations, without having to create markers by hand. Reduced friction compared to
  the previous hard block.
- **Deterministic block for the sub-agent (`deny`):** the coder stops and reports, without
  relying on an undocumented `ask` behavior and without learning the bypass.
- Stack-agnostic, zero dependencies, consistent with the consolidated hook pattern (ADR-0004).
- Audit log provides a trace of every intercepted destructive command + the decision taken
  (ask/deny/allow) + the agent context.
- Orthogonal to other guardrails: no race, no double prompt.

### Negative

- **Possible false positives** on commands that contain literal SQL keyword-pairs in non-executable
  contexts (e.g. commit message "drop table X", documentation with SQL examples). Mitigation: the
  false positive is fail-safe (`ask`/`deny` + clear reason), the user confirms or the sub-agent
  reports. The actual rate needs to be measured in the pilot.
- **Friction on dev ephemeral DBs** until the user creates `.claude/db-is-ephemeral`.
- The fail-closed on match introduces an asymmetry compared to other hooks (all fail-open):
  requires clear documentation to avoid confusing a future debugger.
- **`ask` behavior in subagent context not guaranteed (doc gap):** mitigated by not using `ask`
  for sub-agents (always `deny`). The theoretical risk remains that `ask` may not behave as
  expected even for the orchestrator in some edge (e.g. orchestrator itself dispatched) — to be
  validated in the pilot.
- **`ask` testability in the harness:** the harness verifies the JSON output
  (`permissionDecision` correct based on `agent_id` presence), NOT the real interactive prompt
  (not reproducible in a headless harness). The y/n gate shown to the user is therefore verified
  only for the emitted payload, not for the UI behavior of Claude Code. Known limitation,
  annotated as open question.
- Possible **confusion window** if the user has automatic nightly backups and N=24h covers it,
  but one day the cron skips: the guard would escalate (`ask`/`deny`). Mitigation: N
  configurable.

### Neutral

- **PreToolUse output contract resolved:** the previous open question (legacy `decision` vs
  modern `permissionDecision`) is closed in favor of the modern format
  `hookSpecificOutput.permissionDecision`, verified at `code.claude.com/docs` and necessary for
  the three outcomes. This hook intentionally diverges from the legacy format used by
  `stop-gate.sh` / `pre-flight-pattern-enforce.sh` (hard block): it is the only hook in the
  system to use the modern format, because it is the only one that requires `ask`.
- **Residual doc gap:** `ask` in subagent context not documented -> worked around by design
  (`deny` for sub-agents). Still to validate in the pilot.
- The new conventions `.backups/` + `.claude/db-backup-confirmed` + `.claude/db-is-ephemeral`
  are introduced by this ADR; they should be documented in a target project's CLAUDE.md.
- Repo `vibe-coding-system` NON-git: the deliverables are the 3 markdowns; the actual deploy
  of the live artifacts (`~/.claude/`) is a separate task (TDD plan), without commit step.

---

## References

- ADR-0004 — `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` (bash 3.2-clean
  hook pattern, fail-open, audit, harness; block message that does not teach bypass to the coder)
- ADR-0001 — `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md`
  (defense-in-depth multi-layer)
- `~/.claude/hooks/pre-flight-pattern-enforce.sh` (v1.2 — implementation reference;
  discriminates on `agent_type`, same mechanism used here for `agent_id`)
- `~/.claude/hooks/stop-gate.sh` (timeout pattern, root ascent for `.claude/`, jq parse)
- Memory: `feedback_never-bypass-guardrails`, `feedback_pretooluse-payload-schema`,
  `feedback_bash32-constraint`
- `~/.claude/CLAUDE.md` (global rules on HITL DB + destructive commands + backup)
- Hook contract: `code.claude.com/docs` — PreToolUse (verified: payload schema with
  `agent_id`/`agent_type`; `hookSpecificOutput.permissionDecision` values
  `allow|deny|ask|defer`; `ask` escalates to user even in auto mode; "no output =
  no decision, normal permissions flow"). **Verified gap:** `ask` behavior in subagent
  context NOT documented.
