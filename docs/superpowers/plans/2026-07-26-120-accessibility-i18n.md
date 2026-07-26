# Implementation plan — #120 Accessibility and i18n gates

- **ADR:** `docs/architecture/ADR-0066-120-accessibility-i18n.md`
- **SPEC:** `SPEC.md` / `docs/specs/120-accessibility-i18n.spec.md`
- **Branch:** `feat/120-accessibility-i18n` (stacked on `feat/119-licence-provenance`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none.

**Recording an answer is the deliverable, not blocking on it** (ADR-0066 §D2). The divergence from
the spec's "gate, not aspiration" wording is deliberate and must stay documented, not quietly
resolved in either direction.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/accessibility-i18n.test.sh`.
  `A`-prefixed labels — grep the existing 42 files to confirm the prefix is unused; several use
  `A1`-style labels, so pick a non-colliding form and say which. Hermetic, bash 3.2. Sections:
  Gate 5.05 records a **checklist result**, not merely that the audit ran (§D1) — assert the named
  items (labels, contrast, dynamic-type/scaling, keyboard or assistive-tech reachability) and that a
  result is written to the report; the i18n items are present and **narrow** (§D3) — Unicode and
  multibyte handling, no English-centric assumptions in examples or fixtures — and assert **no i18n
  framework or string-catalogue convention is imposed**; the gate **records and does not block**
  (§D2), and the ADR's divergence-from-spec note is present so it cannot be silently resolved;
  it stays **conditional on UI-bearing chains** and inert otherwise (§D4); **no detector exists**
  (§D5) — assert the absence; registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — `protect-files.sh` denies any path containing `secrets` (plural).

- [ ] **Task 2 — Gate 5.05 records a result.** Extend the existing gate (`concept-to-code/SKILL.md`,
  around the Gate 5.05 block) so it asserts a checklist result rather than only invoking
  `ui-layout-audit`. A step that always completes is indistinguishable from one that always passes —
  the failure ADR-0043 and ADR-0046 each hit in a different form.

- [ ] **Task 3 — the i18n items.** Add to the same checklist, narrow per §D3. Do not introduce a
  framework, a catalogue format, or a locale strategy — those are a project's architectural choice.

- [ ] **Task 4 — the report field.** The result lands in `step5-report.json` as an additive field, on
  the same terms as every prior extension. **Decide** whether it is a finding (counted in the Gate 5
  advisory roll-up, which ADR-0052 §D5 capped at six arrays) or a metric (outside it, per ADR-0064
  §D2) — and justify the choice. It carries a claim about the work, which is the distinguishing test.

- [ ] **Task 5 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `licence-provenance` — note #119 had to loosen a tail-pin in `agent-metrics.test.sh` for exactly
  this reason, so check whether your append breaks another assertion **before** assuming it will
  not). Then run every `staging/plugin/scripts/tests/*.test.sh`.
  **Run the suite AFTER `git add`** — `secret-dep-gate.test.sh` D1 scans `git ls-files`.

## Risk flags

1. **Silently resolving the spec divergence** — either by making it block (unjustified, §D2) or by
   dropping the note (dishonest). Assert the note's presence.
2. **Scope creep into an i18n framework.** §D3 is narrow on purpose.
3. **A tail-pin breaking on the registry append.** #119 hit this one feature ago. Check first.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
