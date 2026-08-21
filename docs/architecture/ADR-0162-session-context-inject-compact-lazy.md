# ADR-0162 — the project context is delivered at session start, not at every compaction

- **Topic slug:** `session-context-inject-compact-lazy`
- **Issue:** none yet — measured live in the session of 2026-08-21, from that session's own transcript
- **SPEC:** none — a bounded change to one 11-line hook, no requirement ids, no coverage gate
- **Extends:** nothing. The `remember` plugin's `MEMORY` block already ships this shape for its own
  payload; this ADR applies the same shape to the payload this repository owns.
- **Deliberately does not touch:** `autoCompactWindow`, or any claim about what governs the
  autocompact threshold — see §D4.

## Status

Accepted — 2026-08-21.

## Context

`session-context-inject.sh` is a `SessionStart` hook that prints `.claude/context.md` into the
session context. `SessionStart` fires at five sources — `startup`, `resume`, `clear`, `compact`,
`fork` — and the hook read none of them, so it printed the whole file at every one.

Measured on 2026-08-21 from the live session transcript, reading `compactMetadata.preTokens` on
every `subtype: compact_boundary` record: **17 compactions in about 70 minutes**, the first at
140,753 tokens and the following sixteen between 83,898 and 86,906. Claude Code raised its own
thrashing warning ("the context refilled to the limit within 3 turns of the previous compact, 3
times in a row").

`cache_creation_input_tokens` on the first turn after each compaction read 48,456 / 52,942 / 50,057
/ 53,877 / 54,945 / 54,624, against 546–2,008 on the turns after: **~50k of every post-compaction
context is fixed preamble**, re-created each time, leaving ~35k of working room that one large tool
output consumes. `.claude/context.md` is 3,087 bytes of that, re-created 17 times to say what it had
already said once.

The same session's `remember` handoff block was self-reporting "already delivered 18 times since
2026-08-21 08:38". That block already carries the answer for its own `MEMORY` payload — a pointer to
the files rather than the files — and the repository's own hook did not.

## Decision

### D1 — withhold the payload at `source=compact`, and only there

The hook reads `source` from the hook's stdin JSON. When it is exactly `compact` it prints the frame
and one pointer line naming the file; at every other source it prints the file as before.

### D2 — the read runs in ONE direction: absence falls through to injecting

An absent `source`, an unparseable payload, empty stdin, or a value the hook does not recognise all
inject the full context. Skipping happens only on a positively-read, exact `compact`. This is the
strict-unknown convention (ADR-0055 §D2) pointed at the correct strictness for *this* question: the
costly failure here is a context that silently stops being delivered, not a saving that is silently
lost. A payload shape change can cost the saving; it can never cost the context.

### D3 — a withheld payload says so, in the same frame

At `compact` the hook prints `=== PROJECT CONTEXT ===` with a line naming the absolute path of the
file, not silence. Rule 4 applied to a saving rather than to a check: "not delivered this time"
must be distinguishable from "there is nothing to deliver", and the reader must be able to reach the
content without knowing the hook exists.

### D4 — nothing here is a claim about the compaction threshold

The trigger fired at ~85k while `autoCompactWindow` was `300000`, a value `/autocompact` confirms is
read from settings. The mechanism behind that gap is **not established** and is not asserted. This
ADR reduces what is re-injected; it does not explain, and must not be read as explaining, when a
compaction happens.

## Consequences

- 3,087 bytes → 191 bytes per compaction. Against a ~50k baseline that is ~800 tokens per compaction
  turn: real, and small next to the parts of the baseline this repository does not own (system
  prompt, tool schemas, agent-type block, MCP instructions, the compaction summary itself).
- The hook now reads stdin. It is guarded on `[ -t 0 ]` so an interactive invocation cannot hang.
- Six behavioural assertions in `staging/plugin/scripts/tests/session-context-inject.test.sh`
  (SCI1–SCI6), six plants, all six seen RED. Four of the six pin D2's fail-open half, which is the
  half a future change is likely to break.
- The harness is registered in `.github/workflows/docs-ci.yml`; `pairs-completeness`'s CI1 check
  found it unregistered on the first run and is what caught it.

## Verified vs assumed

- **Verified:** the compaction counts and `preTokens` values (read from the session transcript on
  2026-08-21); `source` being one of `startup|resume|clear|compact|fork` and being delivered on the
  hook's stdin (read from
  `~/.claude/plugins/cache/claude-plugins-official/remember/0.20.0/scripts/session-start-hook.sh`,
  lines 170–185, on the same day); the byte counts of both branches, exercised.
- **Assumed:** nothing about why the threshold sits where it does.
