---
name: goal-loop
description: >
  Write and operate an effective `/goal` condition — the persistent agent loop where Claude keeps
  working across turns until a verifiable stop condition holds. Use when the user mentions `/goal`,
  "goal loop", "Ralph loop", wants a long-running autonomous run bounded by a stop condition, or asks
  how to phrase a goal so the evaluator can actually judge it. Differentiator vs `prompt-builder`
  (which optimizes a single prompt) and `nightly-autopilot` (which drives a whole roadmap): this
  skill produces one `/goal` contract and explains how to steer it.
disable-model-invocation: true
---

# `/goal` loop

## Provenance

Adapted from the `goal-loop` skill in `github.com/davidondrej/skills` (David Ondrej, MIT).
The contract template, the reward-hacking prohibition, the meta-prompting technique, and the
"contract enforcer, not a run-forever button" framing are his. Everything factual about how `/goal`
behaves has been rewritten against the official documentation — the upstream skill states that
`/goal` is TUI-only and requires subscription auth, and **both claims are contradicted** by
`code.claude.com/docs/en/goal`. See ADR-0022 for why that matters here.

## What `/goal` is

`/goal` sets a completion condition. After each turn, a separate small fast model (the **evaluator**,
Haiku by default) reads the conversation and decides whether the condition holds. If not, Claude
starts another turn instead of returning control. The goal clears itself once the condition is met.

Mechanically, `/goal` is a wrapper around a session-scoped **prompt-based Stop hook**. That single
fact explains most of its constraints.

It is **not** a budget command, not a safety boundary, not "run forever", and not a replacement for
plan mode. It is a contract enforcer with a verification loop.

## Verified requirements

All of the following are from `code.claude.com/docs/en/goal` (fetched 2026-07-09):

- Claude Code **v2.1.139 or later**.
- The workspace **trust dialog must be accepted** — the evaluator is part of the hooks system.
- Unavailable when `disableAllHooks` is set at any settings level, or when `allowManagedHooksOnly`
  is set in managed settings. In both cases the command says why rather than silently doing nothing.
- **One goal per session.** Setting a new one replaces the active one.
- The condition is capped at **4,000 characters**.
- The evaluator **cannot call tools**. It judges only what Claude already surfaced in the transcript.
- Evaluator tokens bill on the small fast model configured for your provider.

There is **no subscription requirement and no API-key restriction.** The evaluator runs on whichever
provider the session is configured for.

## The contract

Every goal needs five parts. Write them as separate lines, not flowing prose.

```
**Objective:** <one sentence, one concrete outcome>
**Read first:** <files / plan / issue>
**Constraints:** <what must NOT change: public API, files, libs, conventions>
**Validate:** `<exact command>` after each change
**Stop when:** <verifiable condition>, OR when further changes require human input
```

Do not prefix the block with `/goal` — that is typed in the composer.

### Writing rules

- **One objective, one stop condition.** A goal is not a backlog.
- **The condition must be provable from the transcript.** The evaluator reads; it does not run
  commands or open files. "All tests in `tests/auth` pass" works because Claude runs the tests and
  the output lands in the transcript. "The code is clean" does not.
- **Bound the run.** Append a turn or time clause: `or stop after 20 turns`. This is the documented
  way to cap a run. Claude reports progress against the clause each turn.
- **Forbid reward-hacking explicitly:** "Do not delete, skip, weaken, or narrow tests to make the
  goal pass." Otherwise the agent games the stop condition.
- **Forbid scope creep explicitly:** "Do not refactor unrelated code. Do not add dependencies."
- **Tell it when to pause:** "If `<condition>`, stop and ask before proceeding."
- **Never instruct the agent to create new ADRs.** ADRs need explicit human approval; a goal prompt
  must not pre-authorize them.
- Use literal strings for paths, commands, and issue numbers. Exact, not paraphrased.
- Over 4,000 chars: move the detail into `PLAN.md` and point the goal at it.
- A short, vague goal burns tokens for no gain over a normal prompt.

### The HITL gates still apply

A `/goal` run does not bypass this system's gates. Commit, push, deploy, DB schema change, and
permanent deletion each still require explicit approval, and `stop-gate.sh` still fires. `/goal`
removes the per-turn prompt, not the authorization. Auto mode is the complementary piece: it removes
per-tool prompts within a turn. Neither answers an `AskUserQuestion`.

## When to use it

All three must hold:

1. The task is more than ~30 minutes of mechanical work.
2. A **verifiable** stop condition exists (tests pass, coverage threshold, build green, queue empty).
3. The repo is agent-ready: working build, real tests, project `CLAUDE.md` present.

Fits: migrations, coverage lifts, TDD feature builds, refactors behind contract tests, bug-repro-then-fix.

Bad fits: exploratory work, "improve this", anything without a definition of done, production
credentials, destructive shared-infra operations.

## Example — migration

```
**Objective:** Migrate this project from Pydantic v1 to v2.
**Read first:** pyproject.toml, src/, tests/
**Constraints:** no public API changes; keep imports backwards-compatible via shims; no new deps
**Validate:** `pytest -q` after each change
**Stop when:** the full suite passes with zero deprecation warnings, OR a change requires an
architecture decision. Do not weaken or skip tests. Or stop after 30 turns.
```

## Running it

Interactive: type `/goal <contract>` in the composer. A `◎ /goal active` indicator shows the elapsed
time. The evaluator's most recent reason appears in the status view and the transcript.

Headless: `/goal` works in non-interactive mode. `claude -p "/goal <contract>"` runs the loop to
completion in a single invocation. Ctrl+C interrupts it. This is the mode `nightly-autopilot` uses
(ADR-0022, D4).

## Controlling a running goal

| Command | Effect |
|---|---|
| `/goal` (no argument) | Status: condition, elapsed time, turns evaluated, token spend, latest evaluator reason |
| `/goal <new condition>` | Replaces the active goal |
| `/goal clear` | Removes the active goal. Aliases: `stop`, `off`, `reset`, `none`, `cancel` |
| `/clear` | Starts a new conversation and removes any active goal |

**Resuming resets the budget.** A goal still active when a session ended is restored by `--resume` or
`--continue`, and the condition carries over — but the turn count, the timer, and the token-spend
baseline **all reset**. An `or stop after N turns` clause therefore grants a fresh N turns after a
resume. Do not rely on it as a durable cap across resumes; enforce the real budget outside the
condition. A goal already achieved or cleared is not restored.

## When a goal drifts

- **Minor drift:** type a correction in the composer. Any typed message takes priority.
- **Loose objective:** read the status, then replace the contract with a tighter one. Do not pile
  instructions onto a vague goal.
- **Bad mess:** `/goal clear`, inspect with `git status`, rewrite the contract, restart.

Never let a drifting goal run on "to see where it goes". Tokens burn and the diff compounds.

## Meta-prompting (highest leverage)

Hand-written goals under-specify. Ask a second session — Claude with the codebase loaded, or a
separate agent thread in the same directory — to inspect the repo, surface hidden assumptions and
edge cases, and emit the five-part contract. Paste that. It produces materially better runs than a
goal written from memory.

## Operational discipline

- **Always review the diff.** Longer autonomy means more code to validate, not less. Oversight
  becomes more important, not optional.
- First run: pick a scoped 30-minute task, so you learn how `/goal` actually stops before trusting it
  overnight.
- Bake recurring policy into the project `CLAUDE.md` — the validation command, adversarial
  self-review before declaring done — so every goal inherits it without restating it.
- Check status periodically with a bare `/goal`.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `/goal` missing from the slash popup | CC older than 2.1.139 — update |
| Command reports it is unavailable | `disableAllHooks`, or `allowManagedHooksOnly` in managed settings, or the workspace trust dialog was never accepted |
| Evaluator never says done | The condition is not provable from the transcript. Rewrite it around something Claude's own output demonstrates |
| Goal ran longer than the turn clause allowed | The session was resumed; turn count reset. Enforce the budget outside the condition |

## Mental model

Stop writing prompts. Start writing specifications with stop conditions. Spend the effort up front on
the definition of done; the run takes care of itself.

## References

- `code.claude.com/docs/en/goal` — the only authoritative source for `/goal` behavior
- `docs/architecture/ADR-0022-nightly-autopilot-goal.md` — `/goal` as the outer loop for the
  overnight runner, D4 condition template, and the resume-reset risk
