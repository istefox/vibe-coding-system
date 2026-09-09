# ADR-0198: Live Codex model/effort choice at every `reviewer` dispatch site

- **Status:** Accepted
- **Date:** 2026-09-09
- **Extends:** ADR-0193 (moved the review backend ask from chain-start to each dispatch site;
  `codex-reviewer.sh`'s contract, the deployed path, `use_codex_review`/`step5_codex_review_asked`
  and their once-per-manifest gate), ADR-0196 (gave `coder` a live per-dispatch Codex model/effort
  choice — the shape this ADR applies to `reviewer`), ADR-0195 (`--focus security`'s own model/
  effort pin, left untouched by this ADR)

## Context

Stefano asked for two named Codex configurations on the `reviewer` agent and on
`review-triage-fix` (RTF) — "Codex Sol medium" and "Astra high" — then, asked whether a live HITL
choice was feasible instead of fixed presets, chose the live gate.

Before this ADR, `codex-reviewer.sh` (the `reviewer` agent's Codex substitute) hardcoded its model
and effort in a pin block immediately above the `codex exec` call: `gpt-5.6-sol`/`high` under
`--focus security` (ADR-0195 §D3), `gpt-5.6-terra`/`medium` otherwise (the 2026-09-05 cost pin).
Neither was reachable from a flag. Every caller that chose "Codex" — RTF's three dispatch sites
(Step 1, the advisor call, Step 4 re-review) and the two `concept-to-code` Step 5 checkpoint sites
— always spent terra/medium; the two combinations Stefano named were not expressible at all.

The shape to copy exists one agent over: **ADR-0196** gave `coder` exactly this — a live, per-
dispatch, re-asked-every-time model+effort choice (`codex-coder.sh --model <astra|sol> --effort
<level>`). This ADR applies the same shape to every `reviewer` dispatch site, with the divergences
below recorded as deliberate rather than left implicit.

Verified live 2026-09-09 (rule 13), `~/.codex/models_cache.json` (`fetched_at`
`2026-09-09T07:56:52Z`, client 0.153.4): `gpt-6-astra`, `gpt-5.6-sol` and `gpt-5.6-terra` all
exist and all three support `low, medium, high, xhigh, max, ultra`.

## Decision

**`codex-reviewer.sh` gains `--model <astra|sol|terra>` and `--effort <level>`, OPTIONAL and
both-or-neither** — the deliberate inverse of `codex-coder.sh`'s ADR-0196 §R2 required pair
(§Refinements R1). Absent, the existing pin block runs exactly as before. Given, they override
both existing pins — including `--focus security`'s — because an explicit choice at a live gate is
by definition an override. `--model` is a closed set the script maps to a slug (`gpt-6-astra` /
`gpt-5.6-sol` / `gpt-5.6-terra`); an unmapped value is exit 2. `--effort` is a passthrough to
`model_reasoning_effort`; an invalid value fails inside `codex exec` and surfaces as exit 3 with
Codex's own reason, never validated in-script.

**Every `codex` branch at every `reviewer` dispatch site gains a second `AskUserQuestion`, in the
same gate turn as the existing backend question, asking model and effort together:**

- Model: `sol` (default) / `astra` / `terra`.
- Effort: `medium` (default) / `low` / `high` / `xhigh` / `max` / `ultra`.

**RTF Step 0 item 6** (ADR-0193's gate): the sub-ask fires once per RTF cycle, immediately after
the existing backend question, and the chosen pair is appended as `--model`/`--effort` to all
three invocation lines. RTF resolves no manifest of its own; when one is in scope it prefills
from the two new fields below and never writes them (the same read-only posture item 6 already
has for `use_codex_review`).

**The two `concept-to-code` Step 5 checkpoint sites** (also ADR-0193): the backend question keeps
its existing once-per-manifest gate on `step5_codex_review_asked` (§Refinements R2 — untouched).
The model/effort sub-ask does **not** share that gate: it fires on every Step 5 entry, fresh or
resumed, whenever the resolved backend is `codex` — mirroring ADR-0196 §R7's reasoning, applied
here to only the cost-bearing half of an otherwise once-per-manifest gate (§Refinements R3). The
chosen pair is written to two new manifest fields by `sed` substitution (`manifest-set-flag.sh` is
boolean-only) and appended to both checkpoint invocation lines.

**Two new manifest fields, additive under schema `1.4`, no version bump** — the same treatment
ADR-0193, ADR-0194 and ADR-0196 gave theirs:

- `step5_codex_review_model` (string, nullable; `astra` | `sol` | `terra`).
- `step5_codex_review_effort` (string, nullable; `low` | `medium` | `high` | `xhigh` | `max` |
  `ultra`).

Seeded `null` by `manifest-init.sh` beside the existing `use_codex_review` /
`step5_codex_review_asked` pair; validated by new Invariant 30 in `manifest-validate.sh`, copying
Invariant 29's (the coder's) shape line for line, each failure message naming its own field.

**`reviewer.md` itself is unchanged.** The Codex path substitutes the agent; it is not a mode of
it. The Claude-side model choice (sonnet/opus) already existed in the backend gate; `effort`
cannot be passed through the Agent tool at all (ADR-0068 §D7, issue #180) — a disclosed limit this
ADR does not close.

## Refinements folded in after the draft

**R1 — `--model`/`--effort` optional and both-or-neither, the deliberate inverse of ADR-0196
§R2.** `codex-coder.sh` has exactly one caller shape (Step 5 dispatch), so making its flags
required converts a silent config inheritance into an explicit decision with no cost. This script
has two OTHER callers whose model/effort choices are themselves approved, written-down decisions:
`deep-refactor`'s `--mode audit` (ADR-0193 §D4) and `security-audit`'s `--mode review --focus
security` (ADR-0195 §D3). Required flags would force both to pass them or break. Both-or-neither
is exit 2 for the same reason ADR-0196's Invariant 29 treats the coder's pair as one fact: a lone
`--model astra` would silently pair a new model with an effort pinned for a different one — the
"value read from the wrong constant" failure. The exposure ADR-0196 §R2 closed (silent inheritance
from the interactive `~/.codex/config.toml`) does not exist here: the no-flag fallback is an
in-script pin with a written cost rationale, not an invisible user config.

**R2 — the backend question's once-per-manifest gate (`step5_codex_review_asked`) is untouched;
only the model/effort sub-ask is added beneath it.** ADR-0193's correction (2026-09-05) fixed a
real bug: `use_codex_review` alone cannot distinguish "never asked" from "asked, declined",
because both leave the field `false`. That reasoning is about the backend question and stays
correct. This ADR does not reopen it.

**R3 — the model/effort sub-ask deliberately does NOT inherit that once-per-manifest gate, and
this is a live tension between ADR-0193 and ADR-0196 resolved explicitly.** ADR-0193 optimizes
"ask once" for a yes/no decision with no cost attached to declining. ADR-0196 optimizes "ask
always" specifically because model and effort are the half of a gate that spends money, and an
inherited `ultra` on a resumed run nobody re-approved is a silent cost decision. Both are correct
for what they each govern. This feature has both halves in one gate for the first time —
Step 5's own review checkpoint gate — and the resolution is: the backend question keeps ADR-0193's
shape (asked once, skip on resume), the model/effort sub-ask gets ADR-0196's shape (asked every
time the resolved backend is `codex`, never skipped). A single `AskUserQuestion` cannot express
"skip half of me" — hence the sub-ask is a structurally separate, second call, gated on the
resolved backend value rather than on any `_asked` field of its own.

**R4 — the model set includes `terra`, unlike the coder's `astra|sol`.** Stefano's explicit choice
(asked directly): Terra is today's former fixed cost pin and stays reachable by hand from the
gate, rather than becoming an invisible fallback only reachable by omitting the flags entirely.

**R5 — the default is `sol`/`medium`, not `terra`/`medium`.** Also Stefano's explicit choice. This
is a real, disclosed cost change: pressing Enter on the codex branch now buys `gpt-5.6-sol` where
it previously bought the terra pin, at every one of the five dispatch sites this ADR touches.

**R6 — an explicit `--model`/`--effort` overrides `--focus security`'s own pin, unconditionally.**
`--focus security` is reachable only from `security-audit`, which never passes these flags (out of
scope, §D below), so this arm is presently unreachable in practice. It is still resolved explicitly
in the script rather than left to fall through, because a live operator choice is definitionally an
override of any pin, security-focused or not — the alternative (silently keeping the security pin
even when a model was explicitly requested) would be a surprise the day a caller does pass both.

**R7 — the RTF sub-ask and the Step 5 sub-ask duplicate their option vocabulary on purpose (rule
6).** Both ask "which of astra/sol/terra, which of the six efforts" of the same script. A harness
assertion (`codex-review-dispatch-gate.test.sh` G5) pins the script's closed set, Invariant 30's
set, and both gate slices' offered options identical — a value added to one and not the others
would silently reject or omit a choice a gate just offered.

**R8 — two live `codex exec` smoke tests (sol/medium, astra/high) each found real defects no
offline harness assertion caught, both fixed and re-verified before merge.** The sol/medium
review caught the autopilot prose contradicting the invocation-line templates in both
`review-triage-fix/SKILL.md` and `step5-implementation.md` (fixed: RTF's fabricated "unattended
codex cycle" sentence removed — RTF has no path that reaches the codex branch unattended at all;
Step 5's checkpoint invocation lines changed to read `<manifest.step5_codex_review_model>`/
`_effort` directly, mirroring `codex-coder.sh`'s own idiom, instead of a turn-local "chosen"
placeholder that would not exist on a silent resume), plus two test-assertion weaknesses (G3 now
counts `--model` and `--effort` as independent exact counts instead of only `--model`; G6 now
verifies `mktemp` succeeded and asserts the specific stderr reason, not just the exit code, for
each of the three validation-error cases). The astra/high review, run after those fixes, surfaced
two further findings, evaluated on their own merits rather than assumed real or dismissed:
- **Confirmed real and fixed:** a manifest predating this ADR has no
  `step5_codex_review_model:`/`step5_codex_review_effort:` line, so the `sed` substitution
  persisting the sub-ask's answer silently no-ops on it (no error, nothing written). Rather than a
  silent insert (a new idiom this codebase does not otherwise use), the fix follows
  `manifest-set-flag.sh`'s own established convention for a missing key: check presence first,
  HALT with a message naming both fields if absent (rule 11 — absent is a distinct state, not a
  default to paper over). Documented in `step5-implementation.md`'s persistence paragraph, pinned
  by `codex-review-dispatch-gate.test.sh` G7. The identical gap exists in ADR-0196's
  `step5_codex_coder_model`/`_effort` write and is out of scope here (pre-existing, untouched by
  this ADR) but named in the fix's own prose so it is not lost.
- **Investigated and found pre-existing, out of scope:** "a trailing `--model`/`--effort` without
  a value hangs" is real (confirmed live: `codex-reviewer.sh --mode review --model` hangs under a
  timeout) but is not specific to this ADR's two new flags — every flag already in that loop
  (`--mode`, `--diff-scope`, `--out`, …) shares the identical `"${2:-}"; shift 2` idiom and hangs
  identically (confirmed live: `--mode` alone hangs the same way). Fixing it would mean taking on
  six flags this ADR does not otherwise touch; left as a disclosed, separate pre-existing defect
  rather than folded into this change.
- **Dismissed as a review-sandbox artifact, not a code defect:** the astra/high verdict also noted
  "the dispatch suite could not complete because the read-only sandbox blocked mktemp" — this is
  `codex exec`'s own `-s read-only` sandbox (the mechanism this same script sets, §Context) blocking
  Codex's attempt to *execute* test commands during static review, not a defect in the reviewed
  code; the harness itself runs `mktemp` successfully outside that sandbox (confirmed by every
  green harness run in this ADR's verification).

## Alternatives considered

1. **Make `--model`/`--effort` required, exactly as `codex-coder.sh` does.** Rejected (§R1): breaks
   `deep-refactor` and `security-audit`, both of which call this script today without either flag.
2. **A single combined `AskUserQuestion` offering backend × model × effort as one flat option
   list.** Rejected: `AskUserQuestion` options are not compositional — a flat list of
   `codex-sol-medium` / `codex-astra-high` / `claude-sonnet` / … is exactly the fixed-preset shape
   Stefano explicitly asked to move away from, and it would need one option per combination (18 for
   three models × six efforts, plus the two Claude options) rather than three small, independently
   understandable questions.
3. **Persist the model/effort choice with its own `_asked` field, mirroring the backend
   question's shape.** Rejected (§R3): defeats the requirement directly. An inherited `ultra` on a
   resumed run nobody re-approved is the exact silent-cost defect ADR-0196 §R7 already rejected
   this shape over, for the coder.
4. **Extend the Step 5 checkpoint sites to the coder's full ADR-0196 treatment (an unconditional,
   always-live gate independent of `step5_review_mode`).** Rejected: the checkpoint reviewer, unlike
   the coder, is conditional on `manifest.step5_review_mode = checkpoint` (off by default) — the
   backend question's existing conditionality is untouched by this ADR (R2), and the model/effort
   sub-ask inherits that same conditionality by construction, since it only fires once the backend
   question has resolved to `codex`.

## Consequences

### Positive

- The two configurations Stefano named ("Codex Sol medium", "Astra high") are now directly
  selectable, plus a third (Terra) and all six effort tiers, at every one of the five `reviewer`
  dispatch sites that support a Codex backend.
- Every existing caller of `codex-reviewer.sh` — `deep-refactor`, `security-audit` — is
  byte-identical when the new flags are absent (R1), so this ADR ships with zero regression risk
  to either.
- The cost-bearing half of the Step 5 checkpoint gate is now a live choice every time, closing for
  `reviewer` the same exposure ADR-0196 closed for `coder`.
- A harness assertion (`codex-review-dispatch-gate.test.sh` G5) makes future drift between the
  script's model set, the manifest validator, and the two gates' prose fail loudly instead of
  silently rejecting or omitting an option a gate just offered.

### Negative

- **The Sol/medium default is a real cost increase over today's terra/medium pin**, on every
  codex-branch dispatch across all five sites, disclosed rather than buried (R5). An operator who
  presses Enter through the sub-ask without reading it now spends more per cycle than before this
  ADR.
- **The Step 5 checkpoint gate now asks two questions instead of one on a fresh `[yes]` answer**,
  and re-asks the second one on every subsequent Step 5 entry for the life of the manifest once the
  backend is `codex` — more interaction than today's silent-terra behavior, which is the explicit
  price of a live cost decision (R3).
- **`--focus security` overridden by an explicit `--model`/`--effort` is presently untested against
  a real caller**, since no caller passes both today (R6). The behavior is resolved unambiguously
  in the script and covered by the offline exit-2 assertions (G6), but the override path itself has
  no live end-to-end exercise until `security-audit` (or a future caller) actually reaches it.
- **Out of scope, deliberately:** `deep-refactor`'s `--mode audit` and `security-audit`'s `--focus
  security` keep their own fixed pins untouched. Widening either to a live per-dispatch choice is a
  separate decision, named here as a follow-up, not smuggled into this one.
