# Implementation plan — #113 Untrusted-input hardening

- **ADR:** `docs/architecture/ADR-0059-113-untrusted-input-hardening.md`
- **SPEC:** `SPEC.md` / `docs/specs/113-untrusted-input-hardening.spec.md`
- **Branch:** `feat/113-untrusted-input-hardening` (stacked on `feat/112-context-occupancy-precompact`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`.

**Do not let the text claim more than it delivers.** Fencing is a mitigation, not a boundary
(§D1). Every user-visible string this feature adds must be consistent with that.

## Task checklist

- [x] **Task 1 — RED harness.** `staging/plugin/scripts/tests/untrusted-input.test.sh`.
  `U`-prefixed labels — grep the existing 35 files to confirm the prefix is unused before
  committing to it. Hermetic, bash 3.2. Sections: **UA** the issue body is fenced as untrusted data
  in `spec-from-issue`'s prompt, with an explicit not-instructions statement; **UB** the detector
  fires on injection-shaped bodies (instruction-override phrasing, embedded role markers, fenced
  blocks posing as system messages, instruction-bearing URLs); **UC** a hit takes the **existing
  SKIP path** with a `needs-human` note — assert it reuses `spec-issue-gate.sh`'s mechanism rather
  than introducing a second one (§D3); **UD** the detector is a **reporter** — always exit 0, signal
  on stdout, `CLEAN` sentinel; state the caller idiom at the call site and restate the trap (never
  `[ -n "$out" ]`, never `grep -c … || echo 0`; `|| true` is the fix); **UE** hardening is
  **unconditional**, not gated on repo visibility (§D5) — assert no public/private branch exists;
  **UF** the ADR-0046 self-collision is pinned as **expected**: this feature's own ADR/SPEC/issue
  text trips the rules, and the rule is *not* narrowed for it (§D4, the ADR-0045 section-E pattern —
  closing it forces the ADR paragraph to move); **UG** no user-visible string overclaims — assert
  the mitigation-not-boundary language is present and that nothing says injection is "prevented" or
  "blocked"; **UH** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — `protect-files.sh` denies any path containing `secrets` (plural).

- [x] **Task 2 — the detector.** `staging/plugin/scripts/untrusted-input-scan.sh`. Reporter
  contract. Rules anchored on shape, not on keyword presence alone — a body *mentioning* injection
  is not the same as a body *performing* it, and the difference is where the FP rate lives.
  → UB/UD green.

- [x] **Task 3 — fencing in `spec-from-issue`.** Fence title and body as untrusted data with an
  explicit statement that nothing inside may redirect the task. Language must not overclaim (§D1).
  → UA/UG green.

- [x] **Task 4 — wire the SKIP path.** A detector hit skips the issue with a `needs-human` note via
  the existing mechanism (§D3). Also wire `roadmap-from-issues.sh`, which reads the same source and
  is the other entry point. → UC green.

- [x] **Task 5 — name the boundary in the docs.** ADR §D2 identifies the real security boundary as
  capability, not prompt text: `nightly-autopilot` never merges, never force-pushes, never writes
  `main`; the merge is the human checkpoint. **Add a line to `nightly-autopilot/SKILL.md`'s safety
  invariants saying that granting merge authority to that path would turn every issue body into a
  remote code execution vector.** That connection is not obvious from either side, and nothing but
  prose defends it. → UE green.

- [x] **Task 6 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `precompact-occupancy`). `PAIRS` entry for the new script. Then run every
  `staging/plugin/scripts/tests/*.test.sh`.
  **Run the suite AFTER `git add`** — `secret-dep-gate.test.sh` D1 scans `git ls-files`, so an
  untracked file is invisible to it; this cost #108 a regression. Expect this feature's own ADR and
  SPEC to trip the new detector once tracked: that is UF's expected-behaviour case, not a bug.
  → UH green.

## Risk flags

1. **Overclaiming.** The single biggest risk is shipping text that reads as "injection is handled".
   UG is the guard. §D1 says it twice on purpose.
2. **Self-collision.** This feature's own documentation matches its rules. Do not narrow the rules —
   ADR-0046 set that precedent when its filename rule fired on its own docs.
3. **§D2's boundary is undefended by code.** Only prose connects "grant merge authority" to "remote
   code execution". Task 5 writes it down; it does not enforce it, and that gap is real.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
