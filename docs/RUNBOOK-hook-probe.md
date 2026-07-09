# RUNBOOK — hook-probe

Settles, with evidence, three questions that three ADRs have been guessing at:

- **ADR-0016** — do `PreToolUse` / `PostToolUse` hooks fire inside a **Workflow subagent**, and if they
  fire, does `pre-flight-pattern-enforce.sh` actually *enforce* there? This is the `hook_verified`
  blocker. While it stays `false`, Step-5 dispatch never uses the workflow path.
- **ADR-0022** — does a project `Stop` hook coexist with `/goal`'s evaluator, which is itself a
  session-scoped prompt-based `Stop` hook?
- **Routines** (future ADR) — do hooks fire at all inside a cloud routine? The same probe answers it
  once committed to a target repo.

## Why the old smoke test could not answer this

ADR-0016 §"Smoke test procedure" tells a human to watch the terminal and "confirm the pattern-enforce
hook fires (emits a `PATTERN:` check message)".

That procedure cannot distinguish two very different worlds:

1. The hook never fired.
2. The hook fired, `pre-flight-pattern-enforce.sh` ran, and it **bypassed itself in silence**.

Both look identical from the terminal: no `PATTERN:` message. The bypass is real and easy to hit,
because `pre-flight-pattern-enforce.sh` enforces only when `agent_type == "coder"` and otherwise
exits 0 without a word. The docs note that a subagent shipped by a plugin reports a plugin-scoped
identifier such as `my-plugin:coder`, not the bare name. A workflow subagent may report something
else again.

The probe records the literal `agent_type` the hook system actually delivers. That single field
separates the two worlds.

## What the probe is

`staging/plugin/scripts/hook-probe.sh` — an observational hook. It appends one JSON line per event
and **always exits 0 with empty stdout**. It has no decision logic and no block path, so it cannot
break a session even if it malfunctions. Empty stdout is not cosmetic: for every blockable event,
"exit 0 + empty stdout" means *allow*, and anything printed on stdout would be parsed as a decision.

It is registered in a **project-level `.claude/settings.json` inside a throwaway sandbox**. Nothing in
`~/.claude` is touched, and no real project sees the probe.

## Run it

```bash
bash staging/plugin/scripts/hook-probe-sandbox.sh
```

The script builds the sandbox, refuses to run if the target sits inside an existing git work tree,
and prints the prompts. Hooks load at session start, so the sandbox needs its **own** `claude`
session — you cannot probe from the session that wrote these files.

```bash
cd "${TMPDIR:-/tmp}/hook-probe-sandbox" && claude
```

Accept the workspace trust dialog. The hook system, and therefore `/goal`, requires it.

Then run four contexts, bumping the context file between each:

| | Type this | What it proves |
|---|---|---|
| **C1** | `add a fourth line to probe-target.txt` | Baseline. The probe is wired, and `agent_id` is absent in the main loop |
| **C2** | `! echo C2 > .claude/hook-probe-context` then `use the coder agent to add a fifth line to probe-target.txt` | Agent-tool subagent: `agent_id` appears, and we learn the literal `agent_type` |
| **C3** | `! echo C3 > .claude/hook-probe-context` then `ultracode: add a sixth line to probe-target.txt` | **The blocker.** Hooks in a workflow subagent, and the `agent_type` pattern-enforce would see |
| **C4** | `! echo C4 > .claude/hook-probe-context` then `/goal probe-target.txt has at least six lines, or stop after 2 turns` | Whether a project `Stop` hook fires alongside `/goal`'s evaluator |

Then read the result:

```bash
bash staging/plugin/scripts/hook-probe-verify.sh \
  "${TMPDIR:-/tmp}/hook-probe-sandbox/.claude/hook-probe.jsonl"
```

## Reading the verdict

The verifier prints a matrix, then explicit lines:

```
HOOK_PROBE C3 hooks_fire=yes|no
HOOK_PROBE C3 agent_type=<literal>
HOOK_PROBE C3 enforce_would_run=yes|no
HOOK_PROBE C3 transcript_glob=match|miss
HOOK_PROBE C4 stop_hook_fired=yes|no
HOOK_PROBE C4 subagent_stop_fired=yes|no
RECOMMEND hook_verified=true|false|unchanged
```

`RECOMMEND hook_verified=true` requires **all three** of: hooks fire in C3, `agent_type` is exactly
`coder`, and the subagent transcript resolves where `pre-flight-pattern-enforce.sh` looks for it. Any
one of them failing means the guard cannot enforce, so the flag stays `false`.

### An empty log is INCONCLUSIVE, not a "no"

If the probe never fired, the verifier exits **3** and recommends `hook_verified=unchanged`. It does
not recommend `false`.

This distinction is the whole point. An empty log means the probe was not registered, or the session
was not restarted after the settings were written. It does **not** mean hooks do not fire. Reading it
as a "no" would flip the flag for the wrong reason, and would look exactly like the correct answer.

### What each outcome means

**`hooks_fire=yes`, `enforce_would_run=yes`, `transcript_glob=match`.** Set `hook_verified: true`.
The Step-5 workflow path may be opened. Record the evidence in ADR-0016 and retire the manual smoke
test.

**`hooks_fire=yes`, `enforce_would_run=no`.** Hooks propagate into workflow subagents, but
`pre-flight-pattern-enforce.sh` bails at its `agent_type == "coder"` check and enforces nothing. The
guard is **inert while appearing installed**. This is what the 2026-07-10 run saw for a *default*
workflow subagent, which reports `workflow-subagent`. The remedy is to pass `agentType: 'coder'` in
the `agent()` call, and optionally to widen ADR-0004's matcher as defence in depth (accept a set of
identifiers, or `agent_id` present plus a suffix match on `:coder`, which also survives a future
plugin-scoped `plugin:coder`). Then re-run the probe.

**`hooks_fire=yes`, `enforce_would_run=yes`, `transcript_glob=miss`.** The hook runs and wants to
enforce, but cannot find the subagent's transcript, so it fails open silently and never checks the
`PATTERN:` header. Fix the path resolution in `pre-flight-pattern-enforce.sh`, then re-run.

**`hooks_fire=no`.** The ADR-0016 blocker is real as written. Keep the Agent-tool fallback
permanently and record that the platform does not propagate `PreToolUse` into workflow subagents.

**C4 `stop_hook_fired=yes` while `/goal` kept iterating.** A project `Stop` hook coexists with the
`/goal` evaluator. ADR-0022's open item closes. If `subagent_stop_fired=yes` as well, the documented
conversion of `Stop` into `SubagentStop` inside subagents is confirmed, which matters because
`stop-gate.sh` is registered on `Stop`.

## Testing the probe itself

```bash
bash staging/plugin/scripts/tests/hook-probe.test.sh
```

Offline, no network, no live session. It feeds synthetic payloads and asserts every verdict line,
including the silent-bypass case and both inconclusive paths.

**A green run here is not evidence about hook propagation.** It tests the probe, not the platform.
Only the live sandbox run produces evidence. Keep the two straight: the harness proving itself
correct is exactly the kind of result that invites over-reading.

## Result of the first live run (2026-07-10)

Recorded here so nobody re-runs this to learn what is already known. Full analysis in ADR-0016.

Hooks fire inside a Workflow subagent, and the transcript resolves through the `subagents/workflows/`
glob. The default workflow subagent reports `agent_type = "workflow-subagent"` and
`pre-flight-pattern-enforce.sh` stands down; a workflow agent spawned with `agentType: 'coder'`
reports `coder`, and the guard enforces on the merits. Its own audit log shows both, minutes apart:
`bypass-noncoder agent_type=workflow-subagent` and then `allow  PATTERN found in window`.

So `hook_verified: true` holds **only** for a dispatch that passes `agentType: 'coder'`.

Three things the run taught that this document had wrong.

The guard is not silent. It writes `bypass-noncoder` to `~/.claude/state/pattern-enforce/audit.log`
every time it stands down. It is silent only to an operator watching the terminal, which is what the
old smoke test asked for. When interpreting a probe result, read that audit log too: it is the
authoritative record of what the guard decided, and the probe only records what it saw.

An agent under `isolation: worktree` carries its own copy of `.claude/` and runs with a different
`cwd`. Before the log was pinned to an absolute path, its events landed in a **second** log inside the
worktree. Reading only the root log said "PreToolUse never fires in subagents", which is the exact
opposite of the truth. `hook-probe-sandbox.sh` now pins `HOOK_PROBE_LOG`. If you ever register the
probe by hand, pin it too, and before deleting a worktree check whether it holds the only copy of an
agent's rows.

A bare `SubagentStop` fires after nearly every main-loop turn, carrying an `agent_id` and an
**empty-string** `agent_type` with no matching `SubagentStart`. Empty is not null, so it wins a naive
`head -1`. It broke the verifier on the first live run, which then reported `agent_type=(absent)` for a
context that plainly contained a `coder`: right verdict, wrong reason. Every selection in
`hook-probe-verify.sh` now filters on `agent_type != ""`, and a regression test pins it.

## Afterwards

Delete the sandbox. It is a throwaway:

```bash
rm -rf "${TMPDIR:-/tmp}/hook-probe-sandbox"
```

Flipping `hook_verified` is a human decision. The verifier recommends; it never writes to a manifest.
