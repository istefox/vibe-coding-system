# ADR-0179 — `notify_when_idle` at Gate 4: evaluated, not adopted

- **Status:** Accepted (decision: do not implement)
- **Date:** 2026-08-29
- **Builds on:** ADR-0097 (Gate 4's two independent choices: WHERE and HOW Steps 5-7 run), the
  "Update 2026-05-26" blueprint changelog entry (Gate 4 made explicitly blocking after the
  orchestrator once treated `ready_for_implementation` as license to continue unattended), `VCS-038`
  (CC 2.1.220–2.1.245 adoption evaluation, which carved this item out as `VCS-050` rather than
  deciding it inline).

## Context

CC 2.1.236 added `notify_when_idle` to cross-session `SendMessage`: a session can ask another,
already-running, named Claude Code session on the same machine to send one notice when it next goes
idle — opt-in, one-shot, no polling. `VCS-038`'s original framing speculated this "could automate
the 'fresh session ready' half of Gate 4's `/clear`+resume flow" in `concept-to-code`
(`references/hitl-gates.md:789-838`).

**What Gate 4's "Confirmed" branch actually requires of the human**, read from the current
implementation: after clicking "Confirmed — I will /clear and resume", the model emits a two-line
instruction block (`/clear` then `/skill concept-to-code resume <manifest-path>`) and stops. The
human then manually types both commands, in their own time, in the same terminal. No second session
exists yet at the moment Gate 4 fires — it is created by the human's own `/clear` action.

**Why `notify_when_idle` cannot automate this, mechanically, not just by policy.** The primitive
requires an already-running, addressable target session — `SendMessage`/`ListAgents` name a live
session by session name or ref. At the instant Gate 4 presents its options, the fresh session does
not exist: it comes into being only when the human runs `/clear`, which destroys the current
session's addressability entirely (there is nothing to `SendMessage` a soon-to-be-cleared session
about, and nothing to name before the human creates its replacement). There is no session on either
side of the boundary that the feature's actual mechanic — "notify me when a *named, running*
session goes idle" — can attach to. This is not a design choice this system could work around with a
different wiring; the primitive's precondition (a live named target) is never satisfied at this
boundary.

**Checked for a narrower, legitimate use elsewhere in the chain** before closing the item outright:
`project-conductor`'s per-feature dispatch (`references/steps-4-7-chain-execution.md:202`,
"Immediately after concept-to-code returns (do NOT wait for user input): go to Step 5") already
proceeds in-session with no background-session wait to notify on. `autopilot`/`autopilot-build`
dispatch coders as isolated worktree subagents (ADR-0068) tracked through the Workflow tool's own
completion signaling, not through session-level idle notifications. No call site in this system
waits on an already-running named session going idle; grepped `SendMessage`/`background
session`/`idle`/`polling` across `project-conductor`, `autopilot`, and `concept-to-code` — the one
hit is the line quoted above, which is a same-session continuation, not a candidate.

## Alternative considered: programmatic session spawn

After this ADR's initial "do not implement" finding, a narrower alternative was raised: instead
of pointing `notify_when_idle` at Gate 4's manual flow directly, have the current session spawn a
**new, addressable** background session itself — `claude --bg -n <name> -p "/skill
concept-to-code resume <manifest-path>"` — and only then `notify_when_idle` on that session, once
it genuinely exists.

**Verified live, not assumed**, that the primitive for this exists: `claude --help` documents
`--bg`/`--background` ("Start the session in the background and return immediately... `claude
agents` lists them") and `-n`/`--name`. `ListAgents` in this session confirms a session started
with `--bg` is a real, addressable peer, not an invisible subprocess — a `· bg ·` row appeared
in this session's own peer list, in the same form as an interactive session.

**Rejected anyway**, because the mechanism is beside the point: what makes Gate 4's "Confirmed"
branch a real barrier is not the absence of a session to notify, it is that the human's manual
`/clear` + resume is the authorization act. Spawning the resumed session is one `Bash` call the
model itself could issue the instant "Confirmed" is clicked — which collapses the click back into
license to continue unattended, the exact failure ADR-0097's 2026-05-26 correction fixed. Adding
`notify_when_idle` on top would only make the model's own unattended continuation faster to
report back on; it does not make it attended. Confirmed by direct evaluation: **Gate 4's value is
high** (it is the only physical human re-entry point before production code is written) and its
cost (manual `/clear` + resume friction) is small by comparison — not worth trading for either
form of automation.

This closes the open question the original ADR-0179 "Negative" note left forward: a primitive
that could *launch* a session did turn out to exist, was evaluated against the "does this let a
human bypass the boundary unintentionally" question, and fails it for the same reason
`notify_when_idle` alone does.

## Decision

**Do not implement `notify_when_idle` anywhere in this system, and do not implement the
programmatic-session-spawn alternative either.** The premise in `VCS-038`'s original
note does not survive contact with what the primitive actually does — it notifies about an existing
session's idle transition, and Gate 4's automatable half is not "wait for a session to go idle" but
"create the session and type two commands," which `notify_when_idle` has no mechanism to do. No
narrower legitimate use was found elsewhere in `concept-to-code`, `project-conductor`, or
`autopilot`.

**Gate 4 itself is unchanged and stays exactly as designed.** Nothing about this finding weakens the
case for the gate's blocking design (ADR-0097, "Update 2026-05-26"); if anything it confirms there
is currently no CC-native primitive that could automate past it without a human physically starting
the fresh session, which is the guarantee the gate exists to preserve.

## Consequences

### Positive

- Closes `VCS-050` with a verified, mechanics-level answer instead of a speculative one — the next
  session reading `VCS-038`'s original note will not re-open the same investigation from scratch.
- No `SKILL.md` change, no new automation surface, no new failure mode introduced at a
  safety-critical human boundary.

### Negative, stated plainly

- The manual `/clear` + `/skill concept-to-code resume <manifest-path>` friction at Gate 4 remains
  unautomated, deliberately: see "Alternative considered" above, where the one candidate that
  could have removed it (`claude --bg` programmatic spawn) was evaluated and rejected on the same
  grounds. This ADR does not claim no future CC feature could ever help here, only that none found
  so far clears the bar.
