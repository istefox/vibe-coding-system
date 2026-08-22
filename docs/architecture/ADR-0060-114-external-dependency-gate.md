# ADR-0060 — External-dependency feasibility gate (G13)

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #114 (fifteenth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/114-external-dependency-gate.spec.md`
- **Builds on:** ADR-0023, which kept the TOFU-trust and gh-auth wall human. §D2 generalises that
  decision rather than inventing a new one.
- **Closes:** gap **G-21** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (ABSENT, P2).

## Context

`nightly-autopilot`'s pre-flight covers roadmap presence, TOFU trust and `gh` auth. Nothing checks
whether the **feature about to be built** needs a credential, an OAuth consent screen, or a cloud
console that does not yet exist.

The spec's evidence (§15.4) is unusually sharp. Three people attempted the same task in three
environments. The returning-after-twenty-years non-professional finished; **both expert authors
failed** — one on an obscure authentication error, the other trying to create a Google OAuth consent
screen. The decisive factor was that the winning platform was **already authenticated**.

For an unattended runner the failure is specific and expensive: an agent blocked in a consent flow
cannot self-unblock, and burns tokens until a budget stops it.

## Decision

### D1 — The architect declares external dependencies in the plan

Third-party APIs, auth flows, cloud consoles, externally provisioned resources. Declared per
feature, in the plan, at design time — when someone is actually thinking about the feature rather
than at 3am when a dispatch stalls.

### D2 — The gate asks "is it already provisioned", not "can it be provisioned"

This is the whole point, and it follows ADR-0023's existing wall rather than inventing a new rule.

An unattended agent **cannot complete a consent flow**. Not "finds it difficult" — cannot. It is the
same hard capability boundary ADR-0023 recognised when it kept TOFU trust and `gh auth` human, and
ADR-0020 recognised when it refused to let autopilot self-approve a test command. The question a
gate can usefully answer is not whether a credential *could* exist but whether it *does*, right now,
before dispatch.

So G13 checks provisioning state and refuses to dispatch unattended when a declared dependency is
unmet. The remedy is a named human action, not a retry.

### D3 — An unmet dependency skips ONE feature. It must not halt the roadmap. Today it would.

**This is a defect found while designing the gate, and it is not confined to this feature.**

`nightly-guard.sh:86` treats `.claude/needs-human` as a **run-level** halt: once written, every
subsequent publish is blocked. `nightly-autopilot/SKILL.md:177` documents that as intended for a
feature that fails to reach `completed`.

But `spec-from-issue` already writes that same marker to SKIP a *thin issue*, and ADR-0059 (#113)
just added a second writer for an injection-suspect issue. So **one thin issue in a twenty-feature
roadmap silently halts the other nineteen**, and that is a pre-existing latent defect this feature
would otherwise have made worse by adding a third writer.

The two situations are genuinely different and need different markers:

- **Run-level halt** — something is wrong with the *run*: a red build, an RTF blocker, a budget
  breach, a feature that failed mid-flight leaving unknown state. Stopping is correct; continuing
  risks compounding damage.
- **Per-feature skip** — this *one* feature cannot proceed for a known, contained reason: thin
  issue, suspected injection, unprovisioned dependency. The other features are unaffected, and
  halting them buys nothing.

So this ADR introduces a per-feature skip note distinct from the run-level halt marker, and moves
the existing thin-issue and injection-suspect writers onto it. The morning report lists skipped
features; the run continues.

**Scope note, stated because it is a real widening:** fixing #113's and `spec-from-issue`'s marker
use is beyond this issue's literal ask. It is included because adding a third writer to a known-broken
mechanism, having just noticed it is broken, would be indefensible. ADR-0047 §D-scope made the same
call for `autopilot-build`'s circuit breaker.

### D4 — The gate runs at c2c Gate 2 and in nightly Phase P

Gate 2 is where a human is present and can provision. Phase P is where the unattended run finds out
before spending anything. Same check, two call sites, one implementation.

### D5 — Declaration absent means the gate is inert

Consistent with ADR-0055 §D2's rule: this *adds* a constraint, so absent equals the pre-feature
behaviour. A plan with no declared dependencies passes silently. It does not mean "no dependencies
exist" — it means nobody said — and the gate cannot tell the difference, which is stated rather than
implied.

## Alternatives rejected

- **A1 — Detect dependencies automatically from the code or plan text.** Rejected: a missed
  detection produces false confidence, and the declaration costs the architect one line while it is
  already thinking about the feature.
- **A2 — Let the unattended run attempt the auth flow and fail naturally.** Rejected under §D2:
  that is the documented expensive failure — an agent that cannot self-unblock burning tokens until
  a budget stops it.
- **A3 — Use the existing `needs-human` marker for an unmet dependency.** Rejected under §D3: it
  halts the whole roadmap for one contained problem.
- **A4 — Leave #113's and `spec-from-issue`'s marker use alone as out of scope.** Rejected under
  §D3's scope note.
- **A5 — Gate on "can this be provisioned".** Rejected under §D2: unanswerable before the fact, and
  the answer that matters is the present-tense one.

## Consequences

### Positive

- The unattended path stops paying for failures it structurally cannot recover from.
- A pre-existing latent defect is fixed: one thin issue no longer halts nineteen healthy features.
- The run-level / per-feature distinction is now explicit, so the next writer of a marker has to
  choose deliberately.

### Negative, stated plainly

- **Declaration is voluntary and absent means inert** (§D5). A feature whose dependencies nobody
  declared sails through, and the gate cannot distinguish that from a feature with none.
- **§D3 widens the scope of this issue** and touches `nightly-guard.sh`, `spec-from-issue` and
  #113's fresh code. The blast radius is real; the alternative was knowingly adding a third writer
  to a broken mechanism.
- **Provisioning state is checked, not proven.** A credential that exists but is expired, scoped
  wrongly, or rate-limited passes the gate. This catches "absent", not "wrong".
- Instruction, not enforcement, for the declaration half: nothing makes an architect declare
  honestly or completely.

**Correction (2026-08-22, issue #473, ADR-0164):** the "checked, not proven" line above was true
only of a self-reported absent — until #473, nothing in `external-dependency-check.sh` touched the
environment at all, so a `provisioned: true` declaration that was simply wrong (the credential was
never created, the variable was never set) passed the gate exactly like a true one. That is a
stronger claim than "checked, not proven" concedes: it is not proven for the reasons stated above
(expired, scoped wrongly, rate-limited all still pass), but until #473 it was also not checked for
the plain case of "declared true, actually absent". ADR-0164 adds a real probe for four verifiable
`<kind>` values (`env`, `binary`, `file`, `port`); everything else — including the
genuinely-unattainable-unattended classes this ADR's §D2 names — stays a trusted declaration,
now reported as such (`UNVERIFIED`) rather than folded silently into a clean result.
