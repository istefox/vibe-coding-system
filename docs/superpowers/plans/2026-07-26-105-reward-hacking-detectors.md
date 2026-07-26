# Implementation plan — #105 Reward-hacking detectors

- **ADR:** `docs/architecture/ADR-0051-105-reward-hacking-detectors.md`
- **SPEC:** `SPEC.md` / `docs/specs/105-reward-hacking-detectors.spec.md`
- **Branch:** `feat/105-reward-hacking-detectors` (stacked on `feat/104-recovery-readiness-preflight`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`, a Step 5 → Step 6 gate.

**The reporter contract is the thing most likely to be broken here.** `weakening-scan.sh` always
exits 0 and prints `CLEAN` when there is nothing. Do not turn it into a checker. Do not change its
path. ADR-0047 wired four skills to call it by reference; that is the payoff being collected.

## Task checklist

- [x] **Task 1 — RED harness.** `staging/plugin/scripts/tests/reward-hack-detectors.test.sh`.
  `H`-prefixed labels, hermetic (`mktemp -d`, diffs built inline), bash 3.2 (no assoc arrays,
  `mapfile`, `${v^^}`, `<<<`, process substitution). Sections: **HA** the four detectors fire on a
  minimal true-positive diff each; **HB** each detector's declared exclusion suppresses it (§D5);
  **HC** the reporter contract — always exit 0, `CLEAN` only when there is neither a `WEAKENED` nor
  a `SUSPECT`, `CLEAN` never printed alongside a finding; **HD** `SUSPECT` does **not** match
  `^WEAKENED`, pinning §D2 so a future edit cannot silently promote it into the halting gates;
  **HE** the existing four `WEAKENED` detectors still fire unchanged (regression guard); **HF**
  `suspect_findings` in the `step5-report.json` schema block and the Gate 5 summary text; **HG**
  the awk feature guard (see Task 2); **HH** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key`.

- [x] **Task 2 — the four detectors in `weakening-scan.sh`.** Extend the existing awk pipeline in
  place; the file stays at `staging/plugin/skills/review-triage-fix/scripts/weakening-scan.sh`.
  New sentinel line shape `SUSPECT<TAB><file><TAB><detector>`, mirroring the existing
  `WEAKENED<TAB><file><TAB><reason>`. Preserve `exit 0` and the `CLEAN` semantics of §D4.
  **Guard the awk feature set the way ADR-0046 did:** if the rules need interval syntax (`{n}`) or
  anything a pre-2019 awk treats literally, detect it and fail loudly rather than going silently
  inert — a detector that reports nothing must be distinguishable from one that finds nothing.
  → HA/HC/HE/HG green.

- [x] **Task 3 — exclusions.** Implement each detector's declared exclusion per ADR-0051 §D5.
  → HB green.

- [x] **Task 4 — measure the false-positive rate against this repo's real history.** Not a fixture.
  Run the scan over a meaningful range of this repository's own commits (e.g. the last 50, or the
  Phase 2 feature branches) and record the per-detector hit count and a spot-check of whether each
  hit is a true positive. This is the method ADR-0046 §D1 used on 350 tracked files and ADR-0048
  §RE on 34 SPECs. **A detector whose rate is high enough to be useless ships disabled, with the
  measurement recorded in the ADR and the report** — say which and why. Add the measurement as a
  harness section so it does not rot.

- [x] **Task 5 — surfacing (§D3).** `suspect_findings` array of `{file, detector, line}` in the
  `step5-report.json` schema block in `concept-to-code/SKILL.md`; the Gate 5 summary prints the
  count and per-detector breakdown explicitly; `commit` Step 1 prints them attended and does **not**
  abort on them even under `--autopilot`. Restate the caller trap at each site: never
  `[ -n "$out" ]`, never `grep -c … || echo 0` (use `|| true`). → HF green.

- [x] **Task 6 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob is automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append
  after `recovery-preflight`). Then run every `staging/plugin/scripts/tests/*.test.sh` — this
  changes a script four skills call and `step5-report.json`, so `weakening-wiring.test.sh` is the
  key regression reader. Report anything already failing separately from anything newly caused.
  → HH green.

## Risk flags

1. **Promoting `SUSPECT` to `WEAKENED`.** The most likely future "fix", and it would put a noisy
   heuristic into gates that halt unattended runs. HD exists to make that fail CI.
2. **`literal-assertion-added` noise.** Requires both halves (implementation *and* test changed);
   a test-only diff must never fire it. If Task 4 shows it is still unusable, ship it disabled —
   that is an allowed outcome, not a failure.
3. **Silently inert awk.** ADR-0046's lesson: a check that reports nothing must be distinguishable
   from a check that finds nothing. HG pins the guard.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
