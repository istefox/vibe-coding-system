# ADR-0170 — `chain-memory-capture.sh` write gate, and wiring the occupancy Stop hint

- **Status:** Accepted
- **Date:** 2026-08-27
- **Builds on:** ADR-0021 (chain-memory PostToolUse hook), ADR-0058 (context-occupancy /
  `PreCompact` guard).

## Context

An audit of the anti-context-rot memory system, run against the live `~/.claude/` deployment
rather than the staged source, found two defects next to a mechanism (`precompact-guard.sh`)
that was working correctly.

**D1 — the occupancy report never ran.** ADR-0058 §D4 requires the `Stop` hint
(`usage-daily-hint.sh`) to report context occupancy. The script existed, was deployed, and its
own unit tests were green — but it was never entered into `Stop` in either
`staging/user/settings.json` or the live `~/.claude/settings.json`, both of which listed only
`stop-gate.sh` (plus, live-only, `chat-done-notify.sh`). Unlike `precompact-guard.sh`,
`sync-to-claude.sh` carried no MANUAL-STEP notice for this wiring, so nothing detected the gap.
Same shape as the `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` drift already on record: staged intent,
different live behaviour, no detector.

**D2 — `MEMORY.md`'s `### Active chains` block was permanently corrupted.** That block is
injected at every SessionStart — it is exactly the surface the whole memory system exists to
keep useful. 61 of its 71 pointers read `step=?, status=?, next: (none)`. Root cause, measured:
`chain-memory-capture.sh` extracts a manifest path from the raw text of a Bash command
(`grep -oE '...\.manifest\.yml'`) without expanding or validating it. Of 68 files in
`chain-history/`, 44 carry a `manifest:` field that never resolves — an unexpanded
`$PWD/docs/manifests/...`, an unexpanded `$(date +%Y-%m-%d)-$SLUG`, a literal `*` from a failed
glob. The old code at step 6 degraded on an unreadable manifest (`if [ -r "$MANIFEST" ]`) rather
than aborting, so it wrote a record with every field defaulted to `"?"` anyway. A `"?"` status
is never terminal, so the record is never archived, and `MEMORY.md`'s own cleanup
(`grep -v -e "^- $SLUG — "`) only ever matches an *exact* slug — a malformed one is invisible to
it and stays in `Active chains` forever.

## Decision

### D1 — Wire `usage-daily-hint.sh` to `Stop`

Added to `staging/user/settings.json` and to the live `~/.claude/settings.json` directly (the
latter is deliberately excluded from `sync-to-claude.sh`'s automated deploy, by design, so a
human reviews it — which is precisely the gap that let this drift stand unnoticed). A new
MANUAL-STEP block was added to `sync-to-claude.sh`, modelled on the existing `precompact-guard`
block, so a future re-deploy that omits this wiring is reported instead of silent.

### D2 — A three-gate refusal in `chain-memory-capture.sh`, ABORT not degrade

Inserted immediately after the slug is derived, before any file is touched. All three `exit 0`
on failure — the file's existing best-effort posture, never disturb the Bash tool flow:

- **Gate A — sane slug.** `case "$SLUG" in *[!A-Za-z0-9._-]*) exit 0 ;; esac`. Rejects any
  character outside a plain filename component: kills an unexpanded token, a bare glob, a
  `????-??-??` stamp.
- **Gate B — readable manifest.** `[ -r "$MANIFEST" ] || exit 0`. Replaces the old degrade-to-`?`
  branch. This is the dominant real case: 44 of the 51 measured malformed entries.
- **Gate C — manifest resolves under the payload's `cwd`, when the field is present.** Guards
  against a leaked absolute path into a test-harness scratch directory that happens to be
  readable and well-named. **Degrades (no-op) when `cwd` is absent**, rather than reject — a
  runtime that omits the field must not silently lose legitimate events, and Gates A and B alone
  already cover the measured majority.

**Why abort instead of degrade (the actual decision):** a `"?"` STATE OF FACT record is not "no
information" the way an absent record is. It is a permanent, indistinguishable-from-real line in
a file injected into the model's context at every SessionStart. Degrading was the direct cause of
D2 above. This repository's own rule 7 ("guard the denominator, not only the matches") and rule 4
("did not run is not found nothing") both point the same way: a corrupted reference must produce
a visibly different outcome (no write) from a legitimate one, not a lookalike record with `?`
fields.

None of the three gates is a heuristic — each is a mechanical fact about the reference itself
(character set, readability, containment), consistent with this roadmap's standing rule that
heuristics report and mechanical facts gate (ADR-0051 §D2, ADR-0053 §D2, ADR-0054 §D5,
ADR-0058 §D4).

### D3 — Orphaned `chain-history/` files are left on disk; only `MEMORY.md`'s pointers are cleaned

The 44 malformed files are not deleted. Some carry a real event log for a real feature (e.g.
`100-secrets-and-dependency-gate-content.md`) predating this gate. `chain-history/` is read
on-demand via `/memory`, not auto-loaded at SessionStart, so leaving them there costs nothing the
way a corrupted `MEMORY.md` pointer does. Only the 61 `step=?` lines in `MEMORY.md`'s
`### Active chains` block were removed, restoring the section to the hook's own empty-state
convention (`- (none active)`, per `chain-memory-capture.sh`'s existing render logic).

## Alternatives rejected

- **Delete the 44 orphaned `chain-history/` files.** Rejected: destroys the only surviving event
  log for at least one real, completed feature (100-secrets-and-dependency-gate-content), for a
  file that costs nothing sitting unread on disk.
- **A looser gate (readability + slug sanity only, no cwd containment).** Rejected: covers the
  measured majority (44/51) but leaves a real hole — a test harness leaking a manifest path into
  a live session's `chain-history/` and `MEMORY.md` (the `test-topic`, `repro2-slug` cases) would
  still corrupt the store.
- **Rewrite the historical `?` entries in place instead of just clearing the pointers.** Rejected
  under this repo's rule 14 — a snapshot inside a completed chain-history file is not corrected in
  place; here there was no correct snapshot to begin with (the records were noise from the start),
  so the pointers are removed rather than "fixed."

## Consequences

### Positive

- The occupancy report (ADR-0058 §D4) actually runs for the first time since it was written.
- `MEMORY.md`'s `Active chains` block reflects reality again; the recurring corruption is closed
  at its source, not just cleaned up once.
- A future re-deploy that drops the `Stop` wiring is caught by `sync-to-claude.sh`'s dry-run,
  the same detection path already trusted for `PreCompact`.

### Negative, stated plainly

- **Gate C's cwd-containment check degrades silently when `cwd` is absent from the payload.**
  If a future Claude Code version stops sending `cwd` on `PostToolUse`, Gate C goes fully inert
  and only Gates A/B remain — no alert fires. Same standing trade every fail-open hook in this
  system makes (ADR-0058 §D3).
- **The 44 orphaned files remain, unlabelled, in `chain-history/`.** Nothing distinguishes "real
  event log, corrupted reference" from "pure noise" without opening each file. A future
  `vibi-status`-style pass could triage them; out of scope here.
- Adding a third hook to `Stop` does not change `stop-gate.sh`'s blocking behaviour (already
  pinned by an existing assertion), but any future `Stop` hook addition should keep verifying
  that non-interference, since three hooks now share the event.
