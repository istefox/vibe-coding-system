# ADR-0164 — three gates that measured a declaration instead of the state it names

- **Topic slug:** `chain-gates-measure-declarations`
- **Issues:** #408, #412, #473 — three of the nine `chain-blocker`-labelled issues open against
  the interactive `concept-to-code` path (the other six are `autopilot`-only).
- **Extends:** ADR-0096/ADR-0152 (#408's archive fence), ADR-0016/ADR-0018 (#412's dispatch
  model), ADR-0060 (#473's feasibility gate). None of those three are superseded; each is
  narrowed or corrected here.

## Status

Accepted — 2026-08-22.

## Context

Three chain-blocker issues share one shape: a gate whose *contract* answers a question about the
world, whose *mechanism* only measures a sentence describing the world.

- **#408.** Step 1's SPEC archive fence (`spec-archive.sh`) halts with exit 3 whenever the
  outgoing SPEC's slug is empty or `unknown`, even when archiving that SPEC is a no-op because
  its content is already sitting in the archive under a different name. 69 of 75 archived SPECs in
  this repository carry no `**Topic slug:**` marker, so `spec_topic_slug=unknown` for them, and
  `spec-from-issue` never writes the marker at all — the population this bites is the norm, not
  the exception. The script had already been reordered once, by issue #455 / ADR-0152, to fix the
  narrower "empty root" case; the slug-before-content check that remained is the same defect one
  level up.
- **#412.** Step 6's Workflow dispatch path runs Phase 3 (parallel fix agents, each in its own
  worktree) and Phase 4 (re-review) inside one continuous workflow invocation. The orchestrator
  never regains control between them, so there is no turn in which Phase 3's worktrees can be
  merged back into the shared checkout before Phase 4 reads it. Phase 4 therefore reviews a
  checkout containing none of the fixes and reports every Phase 1 finding as still `remaining`.
  Measured against every manifest under `docs/manifests/`: `step6_mode` is `null` (42) or
  `"skill_fallback"` (18) — never `"workflow"`. No run has ever taken this path; the defect was
  latent from the day the path was written.
- **#473.** G13, the external-dependency feasibility gate (`external-dependency-check.sh`, ADR-0060)
  passes a dependency the instant the architect writes `provisioned: true`. Nothing checks that the
  named credential, binary, file or port actually exists. ADR-0060 §D2 states the intent in plain
  language: "whether it *does*, right now" — and the implementation never asked the world, only
  read the sentence.

All three were reachable because a checker's exit code and a reporter's declared state are easy to
conflate: the mechanism looks like verification because it sits at a gate and returns a code, but
none of the three ever consulted anything outside the text it was handed.

## Decision

### D1 — #408: compare content before the slug is ever examined

`spec-archive.sh`'s byte-identical comparison loop (the `ALREADY <path>` case) now runs **before**
the empty-or-`unknown` slug refusal, not after. The existence check (`NOSPEC`) and the shape guard
(refusing a slug that is not a bare name) are unchanged and stay in their existing order — moving
either of those would re-break the claims ADR-0152 and this ADR both depend on. The three exit-3
causes are now distinguishable: `SPECARCHIVE_NOSCRIPT` (the fence itself, script not deployed) is
the only one whose remedy is the sync command; every other exit-3 cause is a declined input and
the fence prints the script's own stderr, which names the actual cause.

Step 1's stamp guard (`grep -q '**Topic slug:**'`) is separately re-anchored to column 0
(`grep -qiE '^\*\*[[:space:]]*topic[[:space:]]+slug[[:space:]]*:\*\*'`), the same pattern
`gate0-detect.sh` already reads with (ADR-0086's one-extractor criterion). The old file-wide,
unanchored grep is rule 12's exact shape: a SPEC documenting this very defect satisfies its own
explanation and is never stamped — which is how a SPEC ends up unmarked in the first place,
composing directly with the archive fence's halt.

### D2 — #412: Step 6 always dispatches through the skill fallback

`hook_verified` now governs Step 5's dispatch selection only. Step 6 always uses
`review-triage-fix`, unconditionally, and always records `step6_mode: "skill_fallback"`.

The Workflow template is kept, not deleted — the ADR-0129 §D6 precedent set for `rtf-blocker` in
this same repo: a mechanism nothing can currently reach is kept byte-unchanged, with its
unreachability documented and measured, rather than removed. Its heading is renamed to say
outright that it is not selected, and states why: Phase 4 consumes Phase 3's output inside one
run with no orchestrator turn between them to merge worktrees back, unlike Step 5's Workflow
path, where the per-stage merge-back (`#### Merge-back and base-fork audit`) runs as the
orchestrator's own step between each `agent()` call. That block's own lead-in — which claimed to
be referenced by "Step 6's fix-agent dispatch" — is corrected; no such call site ever existed.

`autopilot-build/SKILL.md` named the same retired heading for its own Step 6 and is corrected the
same way, for the same reason.

Options considered and rejected (from the issue): splitting Phase 3/4 into two workflows with an
orchestrator merge between them (preserves the path but is the larger change, for a mechanism with
zero recorded uses); running Phase 3 without worktree isolation (contradicts ADR-0068 §D7, which
requires isolation explicitly on both dispatch paths).

### D3 — #473: `<kind>` becomes a dispatch key for four verifiable classes

`external-dependency-check.sh` now probes a `provisioned: true` declaration when `<kind>` is one
of `env`, `binary`, `file`, `port` — checked with `printenv`, `command -v`, `[ -e ]`, and `lsof`
respectively. A dependency already declared `false`/`unknown` is unmet regardless of kind and is
never probed, since there is nothing to verify about a claim not made.

Any other kind — including `oauth-consent` and `vendor-account`, the two classes ADR-0060 §D2
already names as genuinely unattainable unattended — stays unverifiable: the declaration is
trusted, exactly as before, but that trust is now visible. Two additive stdout tokens:
- `UNMET <name> <kind> declared-true-absent` — the declaration says true, a verifiable probe says
  otherwise. Exit 1, same as any other unmet dependency.
- `UNVERIFIED <name> <kind> declared-true` — an unverifiable kind's declaration, trusted. Exit 0
  (it does not block dispatch, matching the pre-#473 behaviour for this class), but no longer
  silent: rule 4 applies here exactly as it does to a checker's own "did not run" state — a trust
  decision must report a state distinct from a verified-clean one.

Gate 2c's claim "D2's check already passed" is removed. On `_erc = 0` the caller now distinguishes
an `UNVERIFIED`-bearing result (present it to the human before writing `external_dependencies`)
from a genuinely clean one (every declared dependency verified, or none declared — proceed
without asking).

`architect.md`'s declaration instruction is updated to state `<kind>` as a dispatch key with the
four verifiable values named explicitly. Getting the kind wrong for a verifiable dependency only
costs verification, never produces a false failure — an unrecognised kind is unverifiable, not
unmet.

## Consequences

**Positive.** All three fixes are additive to their existing exit-code contracts — 0/1/3 for
`spec-archive.sh`, 0/1/2 for `external-dependency-check.sh` — so no caller's branching logic
breaks. #408's fix closes the common case (unmarked, already-archived SPECs) without touching the
bootstrap case #455 already fixed. #412's fix is a net removal of a documented-but-unreachable
selection branch; nothing that ever ran changes behaviour. #473's fix is opt-in per dependency by
construction: a kind the architect already writes as free text either matches one of the four
verifiable values (gets checked) or does not (stays trusted, now visibly).

**Negative, stated plainly:**
- #408's fix narrows the defect; it does not eliminate every exit-3 cause. A SPEC that exists, is
  genuinely novel content, and carries no slug is still refused — correctly, since a write with no
  name to write it under is a real defect, not a false halt.
- #412 removes a dispatch path's only live selector without replacing the underlying limitation:
  Workflow-based parallel-fix-then-review still cannot merge mid-run. A future fix (splitting the
  workflow, or an orchestrator-visible merge point) is not attempted here.
- #473's four verifiable kinds cover the common cases this repository's own fixtures already use
  (`env`, `binary`, `file`) plus `port`; a fifth class of programmatically-checkable dependency
  (e.g. a running service reachable only by an authenticated API call) is not addressed and falls
  to `UNVERIFIED` like any other unrecognised kind. `port`'s probe depends on `lsof` being present;
  its absence is reported as unverifiable (return 2), never as a false absence.
- ADR-0060's Consequences section claims "Provisioning state is checked, not proven... This
  catches 'absent'." That line was true only of a self-reported absent and is corrected forward,
  not rewritten in place, in a dated `## Correction` on ADR-0060 itself (rule 14).

## Verified vs assumed

**Verified, this session:** the exact current content of `spec-archive.sh`,
`external-dependency-check.sh`, and the Step 6 dispatch selection in
`concept-to-code/SKILL.md`, by direct reading. `step6_mode`'s corpus distribution (42 `null`, 18
`skill_fallback`, 0 `workflow`) measured against every file under `docs/manifests/`. Every new
assertion in `spec-archive.test.sh`, `concept-to-code-bsd-autopilot-gates.test.sh`,
`step6-effort-pin.test.sh`, `workflow-dispatch-pins.test.sh` and
`external-dependency-gate.test.sh` seen RED against a planted or hand-verified mutation before
being left GREEN.

**Assumed:** that `lsof` is an acceptable minimum bar for the `port` kind's probe on the machines
this system runs on (not measured against every target environment).
