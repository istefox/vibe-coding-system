# ADR-0177: Merge `agent-write-scope.sh` into `test-write-scope.sh` (VCS-046)

## Status

Accepted (2026-08-29)

## Context

`staging/plugin/scripts/agent-write-scope.sh` (ADR-0041, issue #58) and
`staging/plugin/scripts/test-write-scope.sh` (ADR-0049, issue #103) are both `PreToolUse` hooks
wired on the same `Write|Edit|MultiEdit` matcher. Each already opens with the correct
early-bail shape (the pattern VCS-044/045 applied to two other hooks this session): extract
`.agent_type` alone via a single `jq` call, bail immediately if it doesn't match the one agent
type the hook cares about ("architect" / "coder" respectively).

Because `settings.json` wires them as two *separate* `PreToolUse` entries, every single
Edit/Write/MultiEdit call in the whole system — including every orchestrator call, not just
architect/coder dispatches — spawns two `bash` processes and two `jq` processes just to reach
"neither type matches, allow". Unlike VCS-044/045 (whose savings were gated to the
coder/subagent path only), this cost is universal.

Measured before designing on it (rule 13): `sync-to-claude.sh` never programmatically edits a
live `settings.json` — every hook-wiring block only greps for a marker string and, if absent,
prints a "MANUAL STEP" note for a human to paste in. This removed the JSON-surgery risk a merge
could otherwise carry; the settings.json migration is the same manual, deliberate pattern every
other hook in this repo already uses.

## Decisions

**D1 — survivor filename.** `test-write-scope.sh` survives as the physical file;
`agent-write-scope.sh`'s architect-scope logic is ported into it, then the standalone file is
deleted. Measured, not guessed: `test-write-scope.sh`'s own `TI1-TI4` registration assertions,
`agent-metrics.test.sh`'s `GT0/GT1` basename predicate, and 8 mentions across
`concept-to-code/references/step5-implementation.md` all key off this exact filename and stay
valid untouched. The only live operational doc naming the other file was `architect.md` (2
mentions, updated). The name is now slightly imprecise (it also gates the architect) — accepted
as a stated tradeoff in the merged file's own header, since a fresh neutral name would have
touched every one of those now-untouched surfaces for a marginal clarity gain.

**D2 — two log directories preserved, not unified.** The architect branch keeps
`$AGENT_WRITE_SCOPE_DIR` (default `$HOME/.claude/state/agent-write-scope`), the coder branch
keeps `$TEST_WRITE_SCOPE_DIR`, each writing its own audit log. Unifying them would have required
rewriting both test suites' `run()` fixtures; keeping them separate let both suites' existing
env-var setup work with zero changes beyond the new architect coverage section.

**D3 — anchor-comment convention for the ported branch.** The architect logic is wrapped in
literal `# --- ARCHITECT BRANCH START/END (ADR-0041, ex agent-write-scope.sh) ---` markers. This
is load-bearing, not decorative: `agent-write-scope.test.sh`'s F1 assertion (the architect branch
must structurally read no transcript, per issue #127's self-arming class) now scopes its grep to
only the text between those anchors via `awk`, so F1 keeps proving the *architect logic
specifically* touches no transcript — instead of failing (or passing vacuously) once the file
legitimately contains transcript-reading code for the unrelated coder branch.

**D4 — historical record untouched (rule 14).** ADR-0041, ADR-0049, every spec/plan/
`chain-decisions.md` entry naming either script by filename is left exactly as written — each
was a correct snapshot of the day it described. This ADR records the consolidation forward;
neither original is amended or superseded.

**D5 — inverted self-healing note.** `sync-to-claude.sh`'s old "please wire agent-write-scope"
note (fires when the entry is *absent*) is replaced with a "stale agent-write-scope entry"
note (fires when the entry is *still present* in a live `settings.json`) — a leftover old
`PreToolUse` entry now invokes a deleted script and fails file-not-found on every Edit/Write, so
the failure direction needed to invert along with the file's deletion.

## Verification

- `agent-write-scope.test.sh` (retargeted at `test-write-scope.sh`, F1 rescoped): PASS=15 FAIL=0.
- `test-write-scope.test.sh` (new `TN` section, 4 assertions, `Z1` floor bumped 46→50): PASS=53
  FAIL=0.
- `cross-reference-form.test.sh` (retargeted `AWS`): PASS=38 FAIL=0.
- `sync-manual-steps.test.sh` (inverted `WIRED_HOOKS`/`STALE_ARCH_MARK` fixtures, new positive-
  fire `E6`/`E6b`): PASS=48 FAIL=0.
- `agent-metrics.test.sh`, `transcript-scan-rule.test.sh`, `batch-boundary-precedence.test.sh`:
  read first, confirmed no live coupling to the deleted file, run clean with zero changes
  (51/51, 14/14, 20/20).
- Manual functional check: an `agent_type:"architect"` payload with an out-of-scope path piped
  directly through the merged `test-write-scope.sh` returns the correct `deny` JSON, matching
  the original `agent-write-scope.sh`'s exact denial reason text.
- `bash -n` on all five modified shell scripts, `python3 -c "json.load(...)"` on `settings.json`:
  clean.
- Full local suite (91 files): `SUITE_DONE FAIL_COUNT=0`.
- Final `grep -rn "agent-write-scope" staging/plugin/scripts/tests/` sweep: only intentional
  hits remain (the kept `agent-write-scope.test.sh` file itself, VCS-046 explanatory comments,
  and the `CMD_MARK`/`STALE_ARCH_MARK` fixture literals that must still name the string).

## Consequences

**Positive:** every Edit/Write/MultiEdit in the system now spawns one fewer `bash`+`jq` pair
than before, universally (not agent-type-gated). `test-write-scope.sh` alone is now a complete
regression suite for both the architect and coder scope guards.

**Negative:** `test-write-scope.sh`'s filename no longer fully describes its contents (it also
gates the architect's write scope, not only test-file writes). Documented plainly in the file's
own header rather than renamed, per D1's stated tradeoff.

**Out of scope, deliberately:** the live, already-deployed `~/.claude/settings.json` is not
touched by this change — deploying via `sync-to-claude.sh --apply` and manually removing the
stale `agent-write-scope` entry per the new migration note are separate, later, explicit steps.
