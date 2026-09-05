# ADR-0193: Move the Codex-vs-Claude review choice from chain start to reviewer dispatch time

- Status: Accepted
- Date: 2026-09-05
- Supersedes: ADR-0187's gate-placement decision only (the manifest field, schema, `codex-reviewer.sh` contract and never-silent fallback convention are untouched)

## Context

ADR-0187 introduced `manifest.use_codex_review` and a single chain-start ask ("Gate CDX") deciding
whether the five review-dispatch sites downstream use Codex or Claude for the whole run. That ADR
chose "one gate, once, at chain start" deliberately — asking at every dispatch site instead would
add friction at all five and work against the token/time-saving goal.

In practice the placement costs more than it saves:

- The operator decides about review tokens before the interview has run, with no diff, no plan,
  and no sense of how large the review will actually be.
- Two of the five sites — the Step 5 checkpoint reviews — are dead in almost every run:
  `step5_review_mode: none` is the default, flipped only by a manual edit.
- `review-triage-fix` (RTF), which owns the three live sites, is invocable standalone. There it
  resolves no manifest at all, so the field reads absent and the choice today does not exist for a
  standalone cycle.

Stefano also asked, separately, to expose the Claude reviewer *model* (sonnet/opus) at the same
moment — something Gate CDX never did.

## Decision

Move only the *asking*, not the manifest field, its schema, or the dispatch mechanism itself.

**Chain start (`concept-to-code/SKILL.md`):** Gate CDX is removed. Gate 0b leads straight to Gate
0d as it did before ADR-0187, with a one-line removal note in the shape of the existing Gate 0c
precedent, naming this ADR and VCS-063.

**Inside `review-triage-fix`, once per cycle (Step 0, item 6):** a new item, modeled on the
existing item 5 ("Fix-dispatch model variant") idiom for per-cycle state that no manifest holds.
One `AskUserQuestion`, covering both backend and — new — Claude model:

- `codex` — all three RTF dispatch sites (Step 1, the `advisor` variant's advisor call, Step 4
  re-review) run `~/.claude/scripts/codex-reviewer.sh` in place of dispatching `reviewer`.
- `claude-sonnet` (default) — dispatch `reviewer` at `model: "sonnet"`, today's frontmatter pin.
- `claude-opus` — dispatch `reviewer` at `model: "opus"` instead.

If a manifest is in scope, the ask prefills from `manifest.use_codex_review`. If none is in scope
(a standalone invocation), it defaults to `claude-sonnet` — this is the first point at which the
choice exists at all for a standalone cycle.

Two disclosed limits, not solved here:

- **Autopilot skip is an instruction, not an enforcement (rule 16).** RTF has no `autopilot` field
  or predicate of its own; an unattended invoker states so in the brief and the ask is skipped,
  defaulting silently to `claude-sonnet`.
- **`effort` cannot be passed through the Agent tool** (ADR-0068 §D7, issue #180). A per-dispatch
  `model:` override does not disturb `reviewer.md`'s frontmatter `effort: high` — the advisor call
  already overrides `model` alone the same way — but this is stated as an expectation, not yet
  measured live (rule 13).

**Step 5 checkpoints (`concept-to-code/references/step5-implementation.md`):** the two checkpoint
sites keep reading `manifest.use_codex_review` unchanged. What moves is *when* the field is set —
one `AskUserQuestion` in the orchestrator's own live turn immediately before Step 5 dispatch,
conditional on `manifest.step5_review_mode = checkpoint`, skipped under `--autopilot`, writing the
answer via `manifest-set-flag.sh`. Backend only, never a model choice, here: `manifest-set-flag.sh`
accepts exactly `true`/`false`, and the Workflow dispatch path has no `AskUserQuestion` hook to ask
per-checkpoint.

## Corrections found by a Codex dry-run review (2026-09-05, before first commit)

A dry run of `codex-reviewer.sh --mode review` against this ADR's own uncommitted diff (run to
measure subscription consumption for VCS-064, unrelated to this decision) surfaced two real
defects in the implementation below. Both are fixed in the same working tree, not recorded here
as a forward-pointer correction (rule 14 applies to a *committed* record; this ADR has not been
committed yet):

- **The Step 5 pre-dispatch gate could re-fire on every run after a "no" answer.**
  `use_codex_review` is seeded `false` and a declined ask also leaves it `false`, so the field
  alone cannot distinguish "never asked" from "asked, declined" — the gate as first written would
  re-prompt every Step 5 run once the answer was "no". Fixed by adding a dedicated
  `manifest.step5_codex_review_asked` field (schema 1.4, Invariant 25), set unconditionally once
  the ask fires regardless of the answer — the same three-state shape as `hook_verified`, as its
  own field because `use_codex_review`'s two legal values were both already spoken for.
- **The RTF advisor call's Claude branch ignored the Step 0 item 6 model choice.** It hardcoded
  `model: "opus"` unconditionally, the only one of the three RTF dispatch sites that did not
  apply the chosen model. Fixed to dispatch at the model chosen in item 6, matching Sites 1 and
  3. The two Codex-unavailable fallback paths that can be reached with no Claude model resolved
  at all (item 6 selected `codex`, then Codex turned out unavailable) now also name an explicit
  default (`sonnet`/`opus`, matching each site's original default) instead of deferring to "as
  below", which had nothing to defer to in that case.

## Consequences

### Positive

- The operator decides with a diff in front of them, not at chain start on faith.
- `review-triage-fix` gains a real choice standalone, where it previously had none.
- The Claude reviewer model (sonnet/opus) is exposed at the same moment, closing a gap Gate CDX
  never addressed.
- Step 5 checkpoints stop asking on every run once answered once per manifest.

### Negative

- Autopilot-skip and the `effort`-preservation expectation are disclosed limits, not closed gaps
  (rules 13, 16).
- One more manifest field (`step5_codex_review_asked`) to keep in sync with `use_codex_review`.

### Neutral

- No schema version bump: the RTF model choice is a per-cycle prose variant, not a manifest field.
- `codex-reviewer.sh`'s contract, availability cascade, and never-silent fallback convention are
  unchanged from ADR-0187.

## Verification

- New harness `staging/plugin/scripts/tests/codex-review-dispatch-gate.test.sh`: Gate CDX's ask
  is absent from `concept-to-code/SKILL.md`'s chain-start section; RTF Step 0 carries the item-6
  ask and item 5's pinned anchor still reads "item 5"; each of the three RTF sites branches on
  the cycle value, not the manifest field, with a count guard on the derived dispatch-site
  population (rule 7); the Step 5 pre-dispatch ask exists and is conditional on
  `step5_review_mode = checkpoint`; the two corrections above (E1-E3, F1-F2). Plants declared and
  seen RED before trusting them green (rules 1, 2), needles matching the mechanism rather than
  the name that describes it (rule 12). 17 assertions, up from the original 12.
- Registered in `.github/workflows/docs-ci.yml`'s shell-tests loop, appended immediately after
  `coder-discipline` (its own `CD10` pins adjacency to `codex-reviewer-schema`, so the new name
  must not be spliced between them). No `sync-to-claude.sh` PAIRS entry needed: this test file is
  not itself deployed, matching `use-codex-review-manifest-field.test.sh`'s precedent.
- Re-run and green: `cross-reference-form`, `use-codex-review-manifest-field`,
  `codex-reviewer-schema`, `concept-to-code-bsd-autopilot-gates`, `human-gate-coverage`,
  `weakening-wiring`, `worktree-isolation-contract`, `step6-effort-pin`, `dispatch-completion`,
  `pairs-completeness`. Full `plant-check.sh` sweep clean. `npx markdownlint-cli2` clean.
- **Deferred to a manual step, not yet run:** a live invocation of `/skill review-triage-fix`
  standalone on a dirty working tree, to confirm the item-6 ask actually appears at cycle start
  and that the chosen branch dispatches — the first real check of the `effort`-preservation
  expectation disclosed above (rule 13).

## References

- `staging/plugin/skills/concept-to-code/SKILL.md` — Gate CDX removed
- `staging/plugin/skills/review-triage-fix/SKILL.md` — Step 0 item 6; Sites 1, 2, 3
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` — pre-dispatch ask; Sites 4, 5
- `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh` — seeds `step5_codex_review_asked: false`
- `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` — Invariant 25
- `docs/architecture/ADR-0187-codex-review-gate.md` — the decision this supersedes
- `staging/plugin/scripts/tests/codex-review-dispatch-gate.test.sh`
- `.github/workflows/docs-ci.yml` — harness list entry
