# ADR-0197 — one producer, one file, for cross-session state

- **Topic slug:** `session-state-single-producer`
- **Issue:** none yet — raised in conversation while auditing the memory system, 2026-09-08
- **SPEC:** none — a bounded consolidation of an existing hand-written template, no requirement ids
- **Extends:** ADR-0162 (delivery timing of `.claude/context.md`); narrows ADR-0135 (semantics of
  the `Open decisions` field, unchanged here, only bounded against a new sibling field)
- **Deliberately does not touch:** `TODO.md` / `project-tasks`, native memory, or chain-memory —
  distinct producers answering distinct questions, out of scope

## Status

Accepted — 2026-09-08.

## Context

Three producers wrote into four session-state files, two of which were injected into every
`SessionStart`: `.claude/context.md` (written inline by `commit` Step 5.5 and, with a divergent
seed template, by `project-init`), and the `remember` plugin's `remember.md` / `now.md` /
`recent.md` / `archive.md` (one written manually via `/remember`, the rest by a nested Haiku
summarisation pipeline on `PostToolUse`/`SessionEnd`).

Measured on 2026-09-08, from a live `SessionStart` payload: 11,768 bytes injected, of which 845
(`.claude/context.md`) were current. The remainder — `=== LAST HANDOFF ===` (1,869 bytes),
`=== MEMORY ===` + `Recent` (3,546 bytes), `# Archive` (5,508 bytes, 14 weekly digests back to the
week of 2026-06-15) — were stale: the handoff last written 2026-09-06, the automatic summary last
written 2026-09-05.

Root cause of the staleness, read from `pipeline/host.py:218` (`sniff_envelope`,
`remember@claude-plugins-official` 0.25.0) against a live transcript's first line: Claude Code's
transcript envelope now opens with `{"leafUuid": …, "sessionId": …, "type": "last-prompt"}`.
`sniff_envelope` recognises only a `message` dict or `type` in `(user, assistant, summary,
system)`; anything else is `"unrecognised"` and the whole file is discarded. The automatic half of
the pipeline has therefore been producing zero memory since 2026-09-05, while continuing to run
every 2–3 minutes on `PostToolUse` and writing 20–88 KB of log per day — through, among other
work, the PR #578 merge and ADR-0196. This is a bug in a vendored plugin cache, overwritten on
every plugin update; a local patch would not survive. Not reported upstream — the plugin is being
removed from this workflow, and a fix would land in a dependency no longer in use.

Two template drifts, both symptoms of having no single owner:
- `project-init/SKILL.md`'s seed template for `.claude/context.md` had already lost the
  `Last commit` field present in `commit`'s version — the exact failure CLAUDE.md rule 6 names:
  two copies answering the same question, silently diverging.
- `commit`'s template had no field for non-obvious gotchas, blockers, or deferred risks — the one
  thing `remember.md`'s `## Context` field captured that `context.md` did not. In practice this
  content was getting stuffed into `Next` instead (the file's own history, before this ADR, is the
  example: a "Known deferred risk" note living inside `**Next:**`).

## Decision

### D1 — one file, one producer, two callers

`.claude/context.md` becomes the single cross-session state file. `session-state`
(`staging/plugin/skills/session-state/SKILL.md`) becomes its single producer. Two callers:
`commit` Step 5.5, automatically, after every successful commit (`concept-to-code` inherits this
transitively — its own Step 7 already invokes `commit`); and manual invocation, at any point, most
notably to snapshot in-progress uncommitted work before ending a session without a commit.
`project-init` keeps writing its own minimal seed inline (no session history exists yet to derive
a `Notes` field from — a structurally empty field is worse than its absence) but the seed template
now names `session-state` as the owner of the full field set, closing the drift named above.

### D2 — the template gains one field, and a rule for the field it replaces

`Notes` is added: non-obvious gotchas, blockers, deferred risks — exactly what `remember.md`'s
`## Context` field held and `context.md` lacked. The omission rule matters more than the field:
`Notes` is left out of the file entirely when there is nothing to say, never written empty or with
a placeholder. Boundary against the existing `Open decisions` field (ADR-0135, unchanged): that
field stays scoped to what derives from a manifest at `status: in_progress` or a recent ADR;
everything else that is not a formally open decision goes to `Notes`. Without this boundary the two
fields compete for the same content. The line cap moves from 10 to 20 — the file already ran to 14
before this change, so the new cap codifies existing practice rather than inviting new sprawl.

### D3 — the `remember` plugin is removed from this workflow

`claude plugin uninstall remember@claude-plugins-official`. The manual-save use case it covered
(`/remember`, "snapshot before I lose the session") is covered by manually invoking `session-state`
instead. The automatic use case (catch a session that ends without an explicit save) is not
replaced — see Consequences. The `claude-plugins-official` marketplace itself is not removed: 14
other installed plugins depend on it. The hand-added `SessionStart` hook in `~/.claude/settings.json`
that creates `.remember/logs` (not part of the plugin, would outlive its uninstall) is removed
separately, as a global-config change outside this repository. The existing `.remember/` archive
(68 `today-*.done.md` files, `archive.md`, `recent.md`) is left on disk, untouched.

### D4 — nothing here changes what `session-context-inject.sh` does

The hook still `cat`s `.claude/context.md` unparsed, still withholds the payload at
`source=compact` per ADR-0162. Verified before this change: no test, no planted assertion, and no
script anywhere in this repository pins the template's field set or line count —
`session-context-inject.sh` (the file's only runtime consumer) reads it as an opaque blob. The 14
tests that load `commit/SKILL.md` all operate on other regions (Step 1, the CI-tier fence, HITL
gate coverage, Step 4 branch logic); none extract Step 5.5 by line range. `staging/plugin/skills`
is excluded from markdownlint (ADR-0024, ADR-0025), and the template's fence carries no language
tag, so it is outside `fence-contract-coverage.test.sh`'s population.

## Consequences

- SessionStart payload: 11,768 → ~900 bytes. The stale `LAST HANDOFF` / `MEMORY` / `Recent` /
  `Archive` blocks stop being injected.
- Three producers (agent via `commit`, agent via manual `/remember`, nested-Haiku pipeline) become
  one (agent via `session-state`, two call sites).
- **A session that ends with no commit and no manual `session-state` invocation now leaves no
  trace at all**, where before the (broken, since 2026-09-05) automatic pipeline was nominally
  meant to catch it. This is accepted, not overlooked: the old safety net had been silently dead
  for three days, spanning the PR #578 merge and ADR-0196, and its absence went unnoticed. A
  deterministic `SessionEnd` hook that appends a factual, non-narrative block on session end
  (branch, dirty-file count, last commit — never an LLM summary, never an overwrite) was
  considered and deferred: it is a real option if the gap is felt in practice, but is new
  behaviour, not a consolidation, and earns its own review.
- `ADR-0162`'s own byte counts (3,087 bytes re-created 17 times per compaction) are a correct
  snapshot of 2026-08-21 and are not corrected in place (CLAUDE.md rule 14): this ADR's ~900-byte
  figure is the current one, recorded forward here.
- Numbering risk: the chain paused at its own Gate 3 on
  `chore/deploy-roadmap-phase-3-deep-refactor-migration` already collides on ADR-0196 and on this
  same `staging/sync-to-claude.sh`'s PAIRS block; this ADR and its PAIRS entry inherit the same
  collision, to reconcile at merge time.

## Verified vs assumed

- **Verified:** the SessionStart payload byte counts, from a live injected block on 2026-09-08; the
  `now.md`/`remember.md`/`recent.md` file mtimes (2026-09-05, 2026-09-06); the envelope-mismatch
  root cause, read directly from `pipeline/host.py:218` against a live transcript's first line;
  that no test, plant, or script in this repository parses `.claude/context.md`'s content; that
  `concept-to-code` Step 7 invokes `commit`, making its context-write transitive.
- **Assumed:** that a future Claude Code release will not revert the transcript envelope shape —
  irrelevant here since the plugin is removed, not patched. That the manual-save gap (D3) will not
  be felt often enough to justify D2's deferred `SessionEnd` option — a judgment call, not a
  measurement.
