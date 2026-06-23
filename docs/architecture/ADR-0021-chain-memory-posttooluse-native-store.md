# ADR-0021 — Chain memory: a PostToolUse hook records chain task completion and state of fact into the native memory store

**Status:** Accepted
**Date:** 2026-06-22
**Author:** istefox
**Supersedes:** none
**Superseded by:** none
**Related:** ADR-0003 (`concept-to-code` chain — the state machine whose manifest mutations this
hook observes), ADR-0012 (orchestrator-mediated agent memory — the `memory/agent-notes/`
namespace pattern this design mirrors, and the source of the encoded-path resolution rule),
ADR-0013 (native `memory:` pilot failure — the "never let an LLM auto-write to the store" lesson
this design honors), ADR-0016 (Dynamic Workflows Step 5 — the hook-propagation-into-subagents
concern, here shown out of scope), ADR-0014 (TOFU test-cmd — precedent of a deterministic hook
guarding a chain invariant).

---

## Context

The `concept-to-code` chain (ADR-0003) persists per-run state in a YAML manifest at
`<project-root>/docs/manifests/YYYY-MM-DD-<topic>.manifest.yml`. That manifest is the live state
machine of a single run: it is mutated in place, lives in the tracked tree, and is cleaned or
overwritten over a project's life. There is today no persistent, cross-session, cross-run record
of which chain tasks completed and what the current state of fact is, in a place that survives
session boundaries and is recallable later.

### What exists, and why none of it fills the gap

1. **Manifest YAML.** Single-run live state. Not a history; not curated; lives in the tree and is
   subject to `git clean` / publication / deletion.
2. **`.remember/` plugin.** Raw-session journaling with haiku summaries, git-ignored. Session-
   semantic, not chain-semantic: it knows "what happened in this session", not "feature X reached
   Gate 3, next is Step 5". Third-party; we do not fork it.
3. **`memory/agent-notes/` (ADR-0012).** Per-agent durable *patterns and decisions* (what the
   architect/debugger/reviewer learned). A different axis from chain *execution facts*.
4. **Native per-project store** `~/.claude/projects/<encoded>/memory/MEMORY.md`, the documented
   "project knowledge base" tier (blueprint sec. 13), auto-loaded at SessionStart (first 200
   lines / 25KB). Currently empty for this project. This is exactly where chain state belongs.

### Constraint

The persistent memory must not inflate any `CLAUDE.md`. The naive approach (append progress to the
project `CLAUDE.md`) is rejected up front: `CLAUDE.md` is always-loaded config, not a journal, and
growing it is the cost we are avoiding. The store of record is the native memory directory.

### Lessons carried in from prior ADRs

- **ADR-0013:** enabling the native `memory: local` field gave an agent broad auto-Write and it
  escaped its sandbox into the curated store. The lesson is structural: no LLM should choose what
  or where to write in the memory store. A deterministic writer avoids the failure entirely.
- **ADR-0012 D2:** re-encoding `$PWD` with `tr '/' '-'` to find `<encoded>` is fragile (`_`→`-`
  and version-dependent rules); the stable derivation is `dirname(transcript_path)`. Path
  knowledge stays confined to one deterministic component.
- **ADR-0016:** it is undocumented whether PostToolUse hooks fire inside Step-5 *workflow
  subagents*. That concern is out of scope here (see D2).

---

## Decision

Add a **`PostToolUse` hook with matcher `Bash`** that, running in the orchestrator session,
detects successful invocations of the manifest helper scripts and records the chain event plus the
current state of fact into the native memory store. The writer is deterministic (zero-LLM), so the
ADR-0013 failure mode cannot occur. The store is the native `memory/` directory, so the existing
`/memory` browser and the SessionStart auto-load surface it without touching any `CLAUDE.md`.

### D1 — Capture: a deterministic PostToolUse(Bash) hook

`chain-memory-capture.sh` reads the PostToolUse JSON payload on stdin (same pattern as
`auto-format.sh`). It acts only when `.tool_input.command` invokes one of the four manifest
helpers, `manifest-transition.sh` / `manifest-set-gate.sh` / `manifest-set-flag.sh` /
`manifest-set-artifact.sh`, and the mutation succeeded. It is observational: it **always exits 0**
and never blocks the Bash tool. Any parse, IO, or lock failure degrades to a silent no-op. The
event semantics (target step, gate number and status, flag, artifact) are read from the command
arguments; the state-of-fact digest (`current_step`, `status`, `chain_path`, `next_action`, last
approved gate) is read back from the manifest the helper just wrote.

Success gate: if `.tool_response.exit_code` is present and non-zero, the mutation failed and
nothing is recorded. The Bash payload does not always carry an exit code; when absent, success is
assumed (the manifest read-back still reflects whatever state actually landed).

### D2 — The hook fires in the orchestrator session only (ADR-0016 concern out of scope)

Manifest helpers are run exclusively by the orchestrator (the main CLI session), never by Step-5
workflow subagents. The hook therefore depends only on PostToolUse firing in the orchestrator,
which is documented and reliable. The ADR-0016 open question about hook propagation into workflow
subagents does not apply, and chain-memory does not need `hook_verified` to be true.

### D3 — Storage: per-topic files mirroring the ADR-0012 namespace

Events are written to per-topic files at
`~/.claude/projects/<encoded>/memory/chain-history/<topic-slug>.md`, a sibling of ADR-0012's
`memory/agent-notes/`. The slug is derived from the manifest filename. Each file carries:

- a **STATE OF FACT** header block (`current_step`, `status`, `chain_path`, `last_gate`,
  `next_action`, `updated_at`), rewritten in place on every event (atomic temp + `mv`);
- an **append-only Event log**, one line per step/gate/flag/artifact event.

YAML frontmatter (`node_type: chain-history`, `topic`, `manifest`) matches the topic-file
convention of the store. A single shared ledger was rejected: it couples unrelated chains,
complicates archival, and makes the in-place header rewrite awkward.

### D4 — Index: a delimited managed block in MEMORY.md, never CLAUDE.md

The hook maintains a delimited block in `MEMORY.md`, bounded by
`<!-- chain-memory:begin ... -->` / `<!-- chain-memory:end -->`. Everything above the begin marker
is human-curated and never touched. Inside the block: a `### Active chains` section with one
pointer line per in-progress chain (surfaced at SessionStart), and a `### Archived chains` section
holding the last 10 terminal chains. On a terminal status (`completed` / `aborted` / `failed`) the
pointer moves from Active to Archived. The full STATE OF FACT and event log never enter
`MEMORY.md`; only the one-line pointer does. `CLAUDE.md` is never read or written by the hook.

### D5 — Rotation keeps the auto-loaded footprint bounded

Per-topic event log capped at 200 lines (oldest pruned, header preserved). Archived pointers
capped at the last 10. Active pointers are bounded by reality (one per in-progress chain). The
chain-memory sections are designed to stay well under a few KB so they never crowd the curated
content inside the 25KB SessionStart window.

### D6 — Scope-safety: the writer is bound to the session's own project

The destination is derived from `dirname(.transcript_path)`, which is always
`~/.claude/projects/<encoded>/` for the current session. The hook never accepts a path argument
that could redirect it to another project's store, and never re-encodes `$PWD` except as a
last-resort fallback when `transcript_path` is absent. This is the structural answer to ADR-0013:
the writer is a deterministic hook bound to this session's encoded dir, with no LLM choosing the
path.

### D7 — Recall: native `/memory` plus a read-only vibe-status section

`/memory` browses `chain-history/` directly, the primary recall path; no new tool is needed. A
small read-only addition to the `vibe-status` skill lists active chains by reading the STATE OF
FACT headers, mirroring the existing ADR-0012 agent-notes watch. (`vibe-status` is not staged in
this repo, so this addition is a documented follow-up live task.) A dedicated "chain-memory" skill
is rejected as duplicating native `/memory`.

---

## Consequences

### Positive

- **Persistent, cross-session chain state** in the curated store, surfaced automatically at
  SessionStart and browsable via `/memory`, with zero manual upkeep.
- **`CLAUDE.md` untouched.** The explicit constraint is met; progress lives where it belongs.
- **ADR-0013 failure mode cannot recur.** A deterministic hook writes, never an LLM with broad
  auto-Write. Path knowledge stays in one component (D6), as ADR-0012 D2 requires.
- **Consistent with existing patterns.** `chain-history/` is a sibling of `agent-notes/`;
  registration mirrors the existing PostToolUse hook. No new paradigm.
- **Fails safe.** Observational, always exits 0, degrades to no-op; cannot disturb the chain.

### Negative

- **PostToolUse(Bash) fires on every Bash call.** Overhead is one `jq` read plus an early grep
  gate that no-ops the vast majority of calls. If this ever proves material, the helper-embed
  alternative (below) is the fallback.
- **Command-string parsing is tolerant, not a shell parser.** Manifest paths with spaces would
  break tokenization; manifest filenames are slug-based and space-free, so this is accepted and
  documented.
- **Residual encoding risk on the fallback path** only (when `transcript_path` is absent), carried
  over from the still-present `tr '/' '-'` fallbacks elsewhere (ADR-0013).

### Neutral

- **New namespace `memory/chain-history/<slug>.md`** plus a delimited managed block in
  `MEMORY.md`, both separate from the human-curated index body.
- **No manifest schema change.** The hook only reads the manifest; it adds no fields and no states.
- **Deploy is a separate task.** This ADR plus the blueprint edits and the staged
  `chain-memory-capture.sh` are the deliverable. Installing the hook into `~/.claude/hooks/`,
  registering it in `~/.claude/settings.json`, and the pilot are a separate, HITL-gated step.

---

## Alternatives considered

### A — Append progress to the project CLAUDE.md

Simplest to find later (always loaded). **Rejected:** it inflates always-loaded config (the very
cost the request asks to avoid) and mixes mutable journal data into stable behavioral rules.

### B — Embed the chain-history write inside each manifest helper script

Append directly inside `manifest-transition.sh` and the three siblings instead of via a hook.
*Pro:* no payload parsing, the helper knows its own args exactly, no PostToolUse-on-every-Bash
overhead. *Con:* it edits four live scripts (more surface, copies to keep in sync), couples
chain-memory into the chain's critical mutation path (a bug there could break the chain), and is
not a hook. **Rejected** in favor of the decoupled, single-file, fail-safe hook; kept on record as
the fallback if PostToolUse overhead ever proves material.

### C — Extend the `.remember/` plugin

Add chain semantics to the existing session journal. **Rejected:** it is a third-party plugin
(forking is maintenance debt), it is git-ignored and session-semantic, and the native store is the
documented home for curated project knowledge (sec. 13).

### D — A dedicated "chain-memory" recall skill

A new `/skill` to query chain history. **Rejected:** it duplicates native `/memory`; the
read-only `vibe-status` section (D7) covers the aggregate view at far lower cost.

### E — Subagent writes its own memory (native `memory:` field)

The path ADR-0013 piloted. **Rejected on evidence:** the pilot showed an agent escaping its
write-scope into the curated store. The deterministic hook removes the LLM from the write path
entirely.

---

## CC 2.1.186 alignment (2026-06-23)

CC 2.1.186 added a native reminder that nudges the agent to compact its `MEMORY.md` index near the size limit (assumed, changelog 2.1.186). No conflict here: the chain-memory managed block is self-bounded, with the event log capped at 200 entries and archived pointers capped at 10, so the reminder targets the human-curated index above the managed markers and never the block this hook owns.

---

## References

- `staging/plugin/scripts/chain-memory-capture.sh` — the hook (this ADR's primary artifact).
- `staging/user/settings.json`, `staging/plugin/hooks/hooks.json` — PostToolUse(Bash) registration.
- `docs/vibe-coding-system.md` sec. 7 (hooks) and sec. 13 (auto memory) — blueprint integration.
- ADR-0012 — `docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` (namespace pattern
  mirrored; encoded-path rule).
- ADR-0013 — `docs/architecture/ADR-0013-native-subagent-memory-supersede-mediated.md` (no-LLM-
  auto-write lesson).
- ADR-0016 — `docs/architecture/ADR-0016-dynamic-workflows-step5.md` (hook-propagation scope).
- ADR-0003 — `docs/architecture/ADR-0003-concept-to-code-chain.md` (manifest state machine).
- Native store for this project:
  `~/.claude/projects/-Users-stefer-Developer-vibe-coding-system/memory/`.
