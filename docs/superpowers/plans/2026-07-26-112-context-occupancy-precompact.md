# Implementation plan — #112 Context occupancy and `PreCompact` guard

- **ADR:** `docs/architecture/ADR-0058-112-context-occupancy-precompact.md`
- **SPEC:** `SPEC.md` / `docs/specs/112-context-occupancy-precompact.spec.md`
- **Branch:** `feat/112-context-occupancy-precompact` (stacked on `feat/111-tracer-bullet-probe`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`.

**The refusal is one-shot** (ADR-0058 §D2). A `PreCompact` hook that can refuse repeatedly does not
protect a session, it strands it — the window fills, nothing can be evicted, the run dies holding
the state it was protecting.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/precompact-occupancy.test.sh`.
  `X`-prefixed labels — check with `grep` across the existing 34 files that the prefix is unused
  before committing to it. Hermetic, bash 3.2. Sections: **XA** the hook forces the handoff write
  when `current_step` is a dispatch state (§D1); **XB** **the refusal is one-shot** — a second
  `PreCompact` in the same cycle proceeds regardless of manifest state, and the one-shot state is
  cleared appropriately (this is the assertion that keeps the hook from being harmful);
  **XC** fail-open on every error path — no manifest, unreadable manifest, `jq` missing, unwritable
  state dir, malformed JSON; **XD** occupancy is **reported, never gated** (§D4) — assert no
  threshold comparison exists that can block; **XE** the figure comes from what the runtime exposes,
  with no independent counter (§D5); **XF** the `Stop` hint reports occupancy; **XG** the hook is
  registered in `PAIRS` and gets a MANUAL-STEP notice, since hooks here are deployed by sync and
  **wired by hand** — `sync-manual-steps.test.sh`'s all-clear fixture enumerates every wired hook,
  so a new notice is a contract change to that existing test, not just an addition (this caught
  ADR-0049 too); **XH** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — `protect-files.sh` denies any path containing `secrets` (plural).

- [ ] **Task 2 — the `PreCompact` hook.** `staging/plugin/scripts/precompact-guard.sh`. Forces the
  handoff write when mid-dispatch; **refuses at most once per compaction cycle**; fails open on
  every error (§D3). State dir + audit log in the same shape as `agent-command-scope.sh`. Exit 0 on
  every path. Header states the one-shot rule and why, so nobody "fixes" it into a persistent
  refusal. → XA/XB/XC green.

- [ ] **Task 3 — occupancy measurement.** Read what the runtime already exposes; **no independent
  token counter** (§D5) — a second counter drifts, and a drifting number that looks authoritative is
  worse than none. Report only, no threshold comparison (§D4). → XD/XE green.

- [ ] **Task 4 — the `Stop` hint.** Extend it to report occupancy. Check first whether plain stdout
  on exit 0 actually reaches the model for this event: ADR-0039 §D-channel and ADR-0040 both record
  that plain stdout reaches only the debug log for every event except UserPromptSubmit /
  UserPromptExpansion / SessionStart, and `post-md-tells-hint.sh` was found to have been a no-op all
  along for exactly this reason. **Verify the channel before relying on it, and say what you found.**
  → XF green.

- [ ] **Task 5 — registration.** `PAIRS` entry, `chmod +x` list, and a conditional MANUAL-STEP
  notice. Note the `chmod +x` trap #108 hit: the assertion matches the physical line containing the
  literal `chmod +x`, not its backslash-continuation lines, so append on the first line.
  `staging/user/settings.json` gains the `PreCompact` reference entry — this event is **not
  currently in the hooks block at all**, so it is a new event key, not an addition to an existing
  one. → XG green.

- [ ] **Task 6 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `tracer-bullet-probe`). Then run every `staging/plugin/scripts/tests/*.test.sh`.
  **Run the suite AFTER `git add`** — `secret-dep-gate.test.sh` D1 scans `git ls-files`, so an
  untracked file is invisible to it; this cost #108 a regression. → XH green.

## Risk flags

1. **A persistent refusal.** The naive reading of the requirement, and actively harmful. XB is the
   guard, and the hook header must say why so it survives a future reader.
2. **`PreCompact` semantics are runtime-defined** and can change under us — the workflow subagent
   transcript layout moved at CC v2.1.154 (ADR-0016). Re-verify after a major bump; do not treat a
   green harness as permanent evidence about the runtime.
3. **The `Stop` hint channel may not reach the model** (Task 4). Verify, do not assume — a hint that
   only reaches the debug log is a no-op, and this system has already shipped one.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
