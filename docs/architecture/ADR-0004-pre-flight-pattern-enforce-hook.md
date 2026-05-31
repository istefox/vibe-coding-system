# ADR-0004 — Pre-flight Pattern Enforce Hook

**Status:** Accepted  
**Date:** 2026-05-20  
**Author:** istefox  
**Supersedes:** none  
**Superseded by:** none  
**Related:**
- `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (closes the enforcement gap of the classifier discipline)
- `docs/superpowers/specs/2026-05-20-pre-flight-pattern-enforce-hook-design.md`
- `docs/superpowers/plans/2026-05-20-pre-flight-pattern-enforce-hook.md`
- `~/.claude/hooks/stop-gate.sh`, `~/.claude/hooks/approve-test-cmd.sh` (coexistence with existing hooks)
- Memory `feedback_bash32-constraint.md` (constraint for live scripts)

---

## 1. Context

ADR-0001 introduced the **pre-flight pattern classifier**: before every `Edit`/`Write` tool
call, the `coder` agent must emit a line `PATTERN: <CATEGORY> | ...` (4 categories ADD/REMOVE/REPLACE/MODIFY).
The discipline is hard-coded in the system prompt of `~/.claude/agents/coder.md` (lines 25-52) and
is today enforced via **three-layer**:

1. system prompt (`coder.md` lines 26-52, "you MUST emit")
2. reviewer post-hoc check (pattern-drift, item 5 of `reviewer.md`)
3. `review-triage-fix` v1.2 Add+Remove rule (safety net for `REPLACE`)

**Residual gap identified in audit 2026-05-20:**

- Level 1 is **self-discipline**: nothing blocks the `coder` if it omits the header. Under
  context pressure, long prompts, dispatch in parallel worktrees, the LLM may skip it.
- Level 2 (reviewer) operates **post-hoc**: the filesystem is already written, the tool call
  has already passed. The catch is in the next cycle, not immediate.
- For **parallel coders in worktree** (sec. 2 of `vibe-coding-system.md`), the reviewer
  often does not have the full transcript of all coders — the coherence check
  `PATTERN:`-vs-diff can silently slip.

Consequence: the ADR-0001 guarantee is the coder's "best effort", not a structural gate.
The drift observed in cycle 2 of pricing-markup-cli (memory
`feedback_micropiano-refactor-cleanup`, RESOLVED) remains possible in high-attention windows.

**Direction:** introduce a **`PreToolUse` bash hook** in `~/.claude/hooks/` that, before
every `Edit`/`Write` tool call, inspects the recent transcript (sliding window) and
**blocks** the invocation if it does not find a valid `PATTERN:` header preceding the edit.
Promotes the classifier discipline from a textual contract to a **runtime gate** at tool call
level, complementary to the 3 existing layers.

### Inherited constraints

- **Anchor preservation harness `review-triage-fix`:** PASS=47 must remain >= 47.
- **Bash 3.2.57 compat** for every hook in `~/.claude/hooks/`. No assoc array,
  `mapfile`, `${v^^}`, `<()`. Only `grep`/`awk`/`sed`/`jq`.
- **Coexistence with existing hooks.** `stop-gate.sh` (PostToolUse Stop), `approve-test-cmd.sh`
  (utility user-invoked), `migrate-trust-paths.sh` (utility). The new hook is `PreToolUse`
  -> different event, no race.
- **Fail-open by default on internal error.** Identical pattern of `stop-gate.sh` (spec
  §7): if the hook crashes, do not block the user.
- **HITL ban in design phase:** auto mode, no intermediate gate in the plan.
- **NON-git repo:** no commit step.

### Explicit assumptions (not empirically verified)

- **The Claude Code PreToolUse hook receives via stdin JSON containing `tool_name`,
  `tool_input` and (crucially) a field accessible to the recent transcript.** From hook
  contract documentation (`code.claude.com/docs`): `PreToolUse` receives a JSON with at least
  `session_id`, `tool_name`, `tool_input`, `cwd`. The **full transcript is NOT** passed via
  stdin in a robust cross-version way. Assumption: the `session_id` is sufficient to derive
  a transcript file path (e.g. `~/.claude/projects/<encoded>/...` contains the `*.jsonl`
  of the session) and the hook can read it. If this assumption fails, the fallback is the
  **marker file** written by the coder (see §2.2 alternatives).
- **The hook executes in <100ms typical.** Bash + `grep -E` + `tail` on a jsonl file of
  a few MB is under 100ms in preliminary measurements (not verified in this audit).
- **The `coder` agent emits `PATTERN:` as text in the assistant message immediately
  preceding the tool call.** ADR-0001 discipline explicitly states this pattern; the hook
  looks in the transcript for the header in the last N entries.
- **Identifying "the dispatch is the coder agent" is feasible via `subagent_type` in the
  transcript jsonl.** Verified: the session jsonl log includes `subagent_type` for sub-agent
  messages. If this field is missing for orchestrator edits, the hook **bypasses by default**
  (no false positive on orchestrator).

---

## 2. Decision

Introduce the **hook `pre-flight-pattern-enforce.sh`** in `~/.claude/hooks/`, registered
in `~/.claude/settings.json` as `PreToolUse` on tool matcher `Edit|Write|MultiEdit`,
with **block-on-missing** strict logic for coder dispatches + **fail-open** on orchestrator.

### 2.1 Answers to the 7 architectural questions

#### Q1 — Source of truth for the PATTERN: header

**Session transcript file, derived from `session_id`.**

The hook PreToolUse receives JSON stdin with `session_id`, `cwd`, `tool_name`, `tool_input`,
and (in recent CLI versions) a `transcript_path` field pointing directly to the session jsonl.
Fallback path derivable from: encoding cwd -> directory in
`~/.claude/projects/<encoded-cwd>/` containing the jsonl.

Reading: `tail -n <WINDOW> "$TRANSCRIPT" | jq -r 'select(.type=="assistant") | .message.content[]? | .text? // empty' | grep -E '^PATTERN: (ADD|REMOVE|REPLACE|MODIFY) \|'`.

Rejected alternatives see §3.1.

#### Q2 — Sliding window dimension

**Window = last 6 non-tool-result assistant messages** (configurable via env
`PATTERN_ENFORCE_WINDOW`, default 6).

Rationale:
- Too small (1): false positives if coder declares PATTERN, does Read/Grep, then Edit
  — the header is "old".
- Too large (50): false negatives — `PATTERN: ADD` from a previous Edit matches for
  a new Edit of a different type. Distorts the "1 PATTERN per tool call" contract.
- **6** = one Edit + 5 typical context-gathering Read/Grep/Bash. Aligned with the pattern
  observed in the coder during 2026-05-20 dispatches (Read 2-3 files -> emit PATTERN -> Edit).

Implementation: the hook reads the last N assistant messages, NOT the tool_result/user
messages (jq filter `.type=="assistant"`).

#### Q3 — Block vs warn

**Block strict for coder dispatch; warn-only otherwise.**

- If `subagent_type == "coder"` in the recent transcript AND a valid `PATTERN:` is missing in
  the window -> exit with `{"decision":"block","reason":"..."}` (PreToolUse hook contract:
  exit 0 + JSON decision block).
- If not identified as coder (orchestrator, other agent, missing field) -> fail-open,
  exit 0 silent (no block, optional stderr warn logged to `~/.claude/state/pattern-enforce/`).

Rationale: the coder is the only agent with hard-coded classifier discipline (ADR-0001).
Blocking orchestrator/architect/reviewer on Edit (legitimate) would be pure friction.

Combination: **strict block but with bypass mechanism** (Q5) for legitimate cases.

#### Q4 — Scope: coder vs other agents

**Distinction via `subagent_type` in the transcript jsonl.**

The hook scans the window and looks for the first assistant message that declares the subagent
context. Three cases:

1. `subagent_type == "coder"` present -> **strict enforce** (block on missing).
2. `subagent_type` present but different (`architect`, `reviewer`, `debugger`, etc.) ->
   **silent bypass** (no enforcement; those agents do not have the classifier discipline).
3. `subagent_type` absent (direct orchestrator session) -> **silent bypass** (no block;
   the orchestrator can Edit freely).

Edge: old messages from the same session have the `subagent_type` of a previous dispatch.
Mitigation: the hook only looks within the window (last N), which captures the "current speaker".

#### Q5 — Bypass mechanism

**Three bypass layers, from most granular to most drastic:**

1. **Env var for single tool call:** `PATTERN_ENFORCE=off` set by the coder/orchestrator
   before the tool call. The hook reads `os.environ` and exits 0 immediately. Usable in
   transcript via shell escape if needed, but requires propagated env (rare). Soft escape.
2. **Global flag file:** `~/.claude/state/pattern-enforce/disabled` (touch the file ->
   disable; rm -> re-enable). Bypass for troubleshooting/maintenance without editing
   `settings.json`. Persists between sessions — the user is responsible for cleaning it up.
3. **Complete disable via settings.json:** remove the PreToolUse hook entry. Last resort,
   equivalent to uninstalling the hook.

In all bypass cases the hook logs to `~/.claude/state/pattern-enforce/audit.log`
(append-only, 1 line per skip) for audit trail.

#### Q6 — Validation regex and REPLACE-incomplete edge case

**Strict regex:** `^PATTERN: (ADD|REMOVE|REPLACE|MODIFY) \|`

- Strict match of prefix + category + `|` separator.
- Validates **form**, not semantics: the hook does not parse the payload, does not verify
  that `path:line` is consistent with `tool_input.file_path`. That deep-check remains with
  the reviewer (item 5 of reviewer.md, layer 2 of ADR-0001).
- **REPLACE-incomplete (missing `Remove:`):** the hook **does not block** this specific case.
  Rationale: semantic validation of the payload is scope creep — it is sufficient for the
  header to be present and well-formed. The v1.2 `Add+Remove rule` remains the post-hoc
  tertiary safety net. Trade-off accepted: the hook is a pre-edit gate for the *presence* of
  the classifier, not for the *completeness* of the payload (deferred to reviewer).

Future extension v1.1: possible to enrich the regex to `^PATTERN: REPLACE \| Add: .+ \| Remove: .+`
to catch REPLACE-incomplete pre-edit. Deferred to avoid gold-plating v1.0.

#### Q7 — Performance

**Target <100ms typical, fail-open on slow path.**

Implementation:
- `cat /dev/stdin | jq -r '.session_id, .cwd, .tool_name'` (1 jq invocation).
- Derive `transcript_path` from `session_id` (~5ms file lookup).
- `tail -n 200 "$TRANSCRIPT" | jq -r '...' | grep -E '...'` on typically <5MB file,
  tail+jq+grep <50ms on macOS M-series.
- Total expected: 30-80ms typical, internal hard timeout via `timeout 2s` for fail-open
  on slow path (analogous to `stop-gate.sh` lines 78-87 pattern).

Concrete measurement in the plan (Task 6: benchmark verify).

### 2.2 Hook architecture

```
~/.claude/hooks/pre-flight-pattern-enforce.sh    (executable bash 3.2-clean)
~/.claude/hooks/tests/pre-flight-pattern-enforce.sh    (deterministic test harness)
~/.claude/state/pattern-enforce/                  (audit.log, disabled flag)
~/.claude/settings.json                           (entry PreToolUse matcher Edit|Write|MultiEdit)
```

**Hook contract input (stdin JSON):**

```json
{
  "session_id": "abc123...",
  "cwd": "/Users/.../project",
  "tool_name": "Edit",
  "tool_input": {"file_path": "...", "old_string": "...", "new_string": "..."},
  "transcript_path": "/Users/.../.claude/projects/<enc>/abc123.jsonl"
}
```

**Hook contract output:**

- Allow: `exit 0` + empty stdout.
- Block: `exit 0` + stdout `{"decision":"block","reason":"<msg>"}`.
- Internal error: stderr message + `exit 0` (fail-open).

### 2.3 Coexistence with existing hooks

| Hook | Event | Tool matcher | Conflict risk |
|---|---|---|---|
| `pre-flight-pattern-enforce.sh` (new) | PreToolUse | `Edit\|Write\|MultiEdit` | — |
| `stop-gate.sh` | Stop | `*` | None — different event |
| `approve-test-cmd.sh` | (user-invoked, not hook entry) | — | None |
| `migrate-trust-paths.sh` | (user-invoked, not hook entry) | — | None |
| `auto-format.sh` | PostToolUse | `Edit\|Write` | None — Post vs Pre |
| `backup-before-deploy.sh` | PreToolUse | (different matcher) | Low — both PreToolUse but possibly distinct matchers; chained execution safe |
| `protect-files.sh` | PreToolUse | (different) | Low — chained, fail-fast: if protect blocks, pattern-enforce does not run (acceptable) |

Ordering: Claude Code executes PreToolUse hooks in order of registration in `settings.json`.
**Decision:** register `pre-flight-pattern-enforce.sh` **after** `protect-files.sh` and
`backup-before-deploy.sh`. Rationale: protect-files (security boundary) is top priority;
pattern-enforce (governance) comes after. If an Edit is already blocked by protect-files,
pattern-enforce does not run — safe.

### 2.4 Anchor preservation strategy

The `review-triage-fix` harness (PASS=47) does NOT observe hook files. To protect the new
hook from accidental regressions, decisions:

- **Dedicated test harness:** `~/.claude/hooks/tests/pre-flight-pattern-enforce.sh` with
  example JSON fixtures + 6-8 cases (block valid, allow valid, bypass via flag, bypass
  via env, fail-open on non-existent transcript, non-coder skip, malformed JSON,
  performance smoke). Not integrated into the `review-triage-fix` harness — it is a
  parallel harness invoked manually or by future system-validation skills.
- **Structural anchor in `review-triage-fix` harness:** +1 anchor `grep -q -- 'pre-flight-pattern-enforce'`
  in `~/.claude/settings.json` to verify that the hook entry remains registered.
  Trade-off: ties `review-triage-fix` to a third file (after `SKILL.md` and `coder.md` from
  ADR-0001), but the principle "review-triage-fix has authority over the quality of the coder
  stack" extends (ADR-0001 §3.3 sub-question).

**Harness PASS=47 -> PASS=48** (+1 anchor on `settings.json`).

### 2.5 Language

Hook script in bash with comments in English (code = English, global rule).
Reason field of the block message in Italian (user-facing). Spec, plan, memory in Italian.
ADR in Italian. Aligned with Stefano global rule.

---

## 3. Alternatives considered

### 3.1 Source of truth for the PATTERN: header (Q1)

**a) Transcript file via `session_id` / `transcript_path` (CHOSEN).** Single source of
native Claude Code truth, no additional infrastructure, readable cross-version.

**b) Marker file explicitly written by the coder before the tool call** — *Rejected*.
Requires modifying the coder system prompt to emit `Bash: echo "PATTERN: ..." > /tmp/<sid>.pattern`.
Adds an extra tool call to every edit, complicates the pattern (Bash -> Edit, not just Edit),
and introduces race conditions between parallel coders in worktrees (who writes `/tmp/<sid>.pattern`?
namespacing needed). State file = external state to clean, drift inevitable.

**c) Env var propagated from coder to hook** — *Rejected*. Env vars do not
cross from assistant message to hook bash process in a robust way. Claude Code does not
expose a documented mechanism for "agent set env var visible to hook". Anti-pattern.

**d) System prompt section exposed to the hook** — *Rejected*. The sub-agent system prompt
is not exposed to PreToolUse hooks natively. The hook cannot "see" the coder's contract;
it can only read the transcript (see a).

### 3.2 Sliding window dimension (Q2)

**a) Window = 6 last assistant messages (CHOSEN).** Empirically balanced for the
observed coder pattern (Read context-gathering -> emit PATTERN -> Edit).

**b) Window = 1 (only last)** — *Rejected*. Too strict: coder that does a Read between
PATTERN and Edit is common reality. Would produce false positives at a high rate.

**c) Window = entire session** — *Rejected*. False negatives — `PATTERN: ADD` declared 30
edits ago matches for a new Edit of a different type. Distorts the "1 PATTERN per tool call"
contract.

**d) Time-based window (last 30s)** — *Rejected*. Time is not an intrinsic metric of
the jsonl (variable timestamps for LLM latency). Count-based is deterministic.

### 3.3 Block vs warn (Q3)

**a) Block strict for coder, warn-silent others (CHOSEN).** Targeted friction. Coder is
the only agent with hard-coded discipline; others do not deserve blocking.

**b) Warn-only always** — *Rejected*. Does not close the enforcement gap: same "best effort"
as today, only adds stderr noise. Zero incremental benefit over the ADR-0001 status quo.

**c) Block always (even orchestrator)** — *Rejected*. The orchestrator legitimately does
Edit without classifier discipline (e.g. update doc, MEMORY.md). Blocking it = pure friction,
generates forced bypasses that disable the feature.

**d) Block + auto-emit fallback `PATTERN: MODIFY | <auto>`** — *Rejected*. Anti-pattern:
auto-completion defeats the cognitive value of the classifier (ADR-0001 §4.1 — the value is
*forcing the coder to think*). Auto-emit renders it a no-op.

### 3.4 Scope coder vs others (Q4)

**a) `subagent_type == "coder"` discrimination (CHOSEN).** Native field of the jsonl,
deterministic, no additional marker.

**b) Marker injection in the coder system prompt** — *Rejected*. Requires prompt mod,
escapable by the LLM (can omit the marker), and duplicates the `subagent_type` mechanism
already present.

**c) Enforce on all agents** — *Rejected*. Only coder has ADR-0001 discipline;
other sub-agents do not have the `PATTERN:` contract. Extending to all = imposing a
discipline that does not exist.

### 3.5 Bypass mechanism (Q5)

**a) Three layers (env + file flag + settings.json) (CHOSEN).** Granularity for use cases:
single-call (env), session/maintenance (file flag), permanent disable (settings.json). Each
has a log/audit-trail.

**b) Only file flag** — *Rejected*. Missing single-call granularity. Forces touch+rm for
each legitimate exception, operational friction.

**c) No bypass** — *Rejected*. A hook that blocks without escape is an anti-pattern.
Legitimate edge case (coder does non-classifiable Edit, debug session, recovery):
impossible to handle without bypass disable.

### 3.6 Validation regex and REPLACE-incomplete (Q6)

**a) Strict form regex, no semantic check (CHOSEN).** Gate "presence of well-formed PATTERN".
Semantic (e.g. REPLACE pair complete) deferred to reviewer (layer 2 ADR-0001).

**b) Complete semantic validation (REPLACE pair, path:line consistency)** — *Rejected
in v1.0*. Scope creep, complicates bash hook, slows performance. Defer v1.1 if pilot
metrics show REPLACE-incomplete is frequent.

**c) Lenient regex (case-insensitive, partial match)** — *Rejected*. Leaves escape room
for the coder to write malformed (e.g. `pattern: add ...`). Strict regex = discipline
aligned with the ADR-0001 contract (exact examples).

### 3.7 Performance approach (Q7)

**a) Bash + jq + tail + grep with 2s hard timeout (CHOSEN).** 3.2-clean, fail-open on slow,
typical <100ms. Pattern already consolidated in `stop-gate.sh` (robust timeout, lines 77-88).

**b) Python helper script** — *Rejected*. Adds Python dependency (never needed so far in
`~/.claude/hooks/`), Python interpreter startup overhead ~150-200ms (beyond <100ms target
even before any logic).

**c) Caching the window in `~/.claude/state/`** — *Rejected v1.0*. Premature optimization.
Tail+jq on files <5MB is sufficient. Cache requires invalidation logic (stale state).

---

## 4. Consequences

### 4.1 Positive

- **Runtime gate to the classifier discipline.** First time the system enforces `PATTERN:`
  at tool call level, not just via post-hoc review.
- **Targeted friction.** Only the coder agent sees the block. Other agents (orchestrator,
  architect, reviewer) remain fluid.
- **Defense in depth.** Fourth layer to the ADR-0001 stack (system prompt -> hook gate ->
  reviewer post-hoc -> v1.2 safety net). Hook closes the gap "parallel coder in worktree
  without reviewer transcript".
- **Audit trail.** All blocks and bypasses logged to `~/.claude/state/pattern-enforce/audit.log`.
  Observable pilot metrics (hit-rate, bypass rate).
- **Anchor preserved.** Harness PASS=47 -> PASS=48 (additive).
- **Acceptable performance.** <100ms typical, 2s hard timeout, fail-open on error.
- **Zero new dependencies.** Bash 3.2 + jq (already used by `stop-gate.sh`).

### 4.2 Negative

- **Friction on coder if transcript_path is not resolvable.** Edge case: fresh session
  where the jsonl has not yet flushed; the hook fail-open silently (acceptable), but the first
  Edit might bypass the check. Mitigated by reviewer post-hoc (layer 3 ADR-0001).
- **Dependency on Claude Code jsonl format.** Future breaking format change -> hook degrades.
  Mitigation: fail-open on jq parse error.
- **Initial estimated false positive rate 5-15%.** Coder might legitimately do an Edit without
  PATTERN if the LLM drifts. Bypass mechanism (Q5) covers it, but generates friction until
  the pattern stabilizes. Validatable in pilot.
- **Coupling settings.json + harness.** Adding hook entry in settings.json verifies anchor of
  review-triage-fix. Future settings.json refactor requires anchor update.
- **Performance not guaranteed on transcript >50MB.** Long-running sessions with huge jsonl
  files may slow down the tail+jq. Mitigated by `tail -n 200` (O(n) tail reading of the queue),
  not full file parse.

### 4.3 Neutral

- ADR-0001 remains authoritative for the **pattern definition** (categories, format).
  This ADR adds only an enforcement layer.
- The reviewer.md pattern-drift check (item 5) remains unchanged — layer 3 preserves the
  semantic check that the hook explicitly does not do (REPLACE pair complete, etc.).
- Memory `feedback_micropiano-refactor-cleanup` remains RESOLVED. This ADR is additive.

### 4.4 Open questions (validation pending)

- **Is the `transcript_path` field available in all CLI versions active on Stefano's Mac
  (Claude Code 2.x)?** Verifiable by testing the hook with a real dispatch in pilot.
  Fallback: derive from `session_id` via cwd encoding (more fragile but feasible).
- **Actual false positive rate of the coder in the first 20-30 dispatches.** Measurable via
  audit.log of blocks. If >20%, consider amendment v1.1 (window dimension, regex lenience,
  semantic skip for certain tool_input patterns).
- **Performance under load.** Measurable with `time` benchmark on harness Task 6.
  If >150ms p95, consider cache layer (defer to v1.1).

---

## 5. References

- `~/.claude/agents/coder.md` (ADR-0001 discipline enforced by this hook)
- `~/.claude/agents/reviewer.md` (complementary layer 3)
- `~/.claude/hooks/stop-gate.sh` (pattern of bash 3.2-clean hook: timeout, fail-open, JSON
  emit via jq)
- `~/.claude/hooks/approve-test-cmd.sh` (existing utility hook, coexistence no conflict)
- `~/.claude/settings.json` (target PreToolUse entry registration)
- `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (pattern definition)
- `docs/vibe-coding-system.md` sec. 7 (hooks deterministic automation) + sec. 10
  (permission strategy)
- Memory `feedback_bash32-constraint.md` (shell compat)
- Claude Code docs `code.claude.com/docs/en/docs/claude-code/hooks` (PreToolUse contract)
