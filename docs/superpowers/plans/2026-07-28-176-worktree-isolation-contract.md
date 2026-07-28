# Implementation plan — Worktree isolation contract for the multi-agent chain

- **Issue:** #176 (supersedes #175)
- **ADR:** `docs/architecture/ADR-0068-176-worktree-isolation-contract.md`
- **SPEC:** `SPEC.md` (topic slug `176-worktree-isolation-contract`)
- **Date:** 2026-07-28
- **Style:** TDD — every behavioural assertion is seen RED before the change that makes it green
  (R-19). Static prose anchors are marked as such; they are still written first and still seen RED.

## Ground rules for this plan

- **Bash 3.2 clean.** No associative arrays, no `mapfile`, no process substitution, no `sed -i`
  without a suffix argument. macOS/BSD `sed` and `awk`.
- **Anchor-preserving.** The harness at `staging/plugin/scripts/tests/*.test.sh` is the only test
  surface. Do not extend `staging/plugin/skills/concept-to-code/tests/run-tests.sh` — it hardcodes
  the deployed `$HOME/.claude/skills/concept-to-code` copy and is outside both CI registries.
- **Both CI registries.** A new `*.test.sh` is picked up by `.claude/test-cmd` and by `ci.yml`'s
  glob automatically, but `.github/workflows/docs-ci.yml`'s `shell-tests` job uses an **explicit
  named list**. Append there by hand or the file is CI-dark (R-19).
- **Grep anchors use compound phrases**, never bare substrings. `git diff HEAD --name-only` appears
  in a block that must survive (`review-triage-fix/SKILL.md:158`, ADR-0068 §D9) and in blocks that
  must go. Anchor on the surrounding isolation-selection wording, not on the command.
- **Never cite an ID the SPEC does not declare.** The SPEC declares R-01 … R-19 and nothing else.

## Enumerated call sites

`grep -rn 'isolation' staging/` returns **11 sites that name or resolve an `isolation` value**,
consistent with the Step 1 interview's count and three more than issue #176 listed:

| # | Site | What it does |
|---|---|---|
| 1 | `concept-to-code/SKILL.md:676` | ADR-0050 §D4 reconciliation paragraph, names `isolation: "none"` |
| 2 | `concept-to-code/SKILL.md:739` | git-dir check exit 0 → `isolation: worktree` |
| 3 | `concept-to-code/SKILL.md:742` | git-dir check exit non-0 → `isolation: "none"` |
| 4 | `concept-to-code/SKILL.md:752` | dirty-tree condition → `isolation: "none"` |
| 5 | `concept-to-code/SKILL.md:850-855` | conflict-scan advisory clause, `isolation: "none"` ×2 |
| 6 | `concept-to-code/SKILL.md:903-904` | Stage 2 "Resolve `isolation` per the check above" |
| 7 | `concept-to-code/SKILL.md:1453-1460` | Agent-tool fallback dirty-tree → `isolation: "none"` |
| 8 | `autopilot-build/SKILL.md:193-194` | git-dir check → `worktree` / `none` |
| 9 | `autopilot-build/SKILL.md:196-201` | dirty-tree condition → `isolation: "none"` |
| 10 | `deep-refactor/SKILL.md:108-114` | Step 0.2 `isolation:none` pre-check, `ISOLATION_MODE` |
| 11 | `deep-refactor/SKILL.md:384` | dispatch brief `isolation: <none if ISOLATION_MODE=none…>` |

Plus `staging/user/rules/parallelization.md:21` (correct value, incomplete contract — R-15).

**Disclosed, not changed:** `review-triage-fix/SKILL.md:158` (ADR-0068 §D9),
`staging/plugin/scripts/hook-probe-sandbox.sh:102,108` (comments, correct),
`concept-to-code/SKILL.md:1849` (Express "No worktree isolation" note, contradicts
`docs/GUIDA-USO-IT.md:117`, out of this SPEC's scope).

**Doc surfaces:** `docs/GUIDA-USO-IT.md:632-633`, `docs/SKILLS-AND-AGENTS-GUIDE.md:355-356` (same
false fallback claim, not named in the SPEC's Scope but the same class — the SPEC deliberately does
not close the count).

---

## Task 1 — Measure the real `WorktreeCreate` contract before writing anything against it (R-03)

The SPEC's F11 is doc-sourced and disagrees with the current docs on field names and on whether
`agent_type` exists at all (ADR-0068 §W3). Nothing downstream may be written against F11.

- [ ] Write `staging/plugin/scripts/worktree-capture.sh`: reads stdin, appends it verbatim to
      `$HOME/.claude/state/worktree-probe/payloads.jsonl`, exits **0 with empty stdout**.
- [ ] Register it as a `WorktreeCreate` hook in `~/.claude/settings.json` by hand, on a scratch
      branch of this repository.
- [ ] **Probe A (payload + decline).** Dispatch one `Agent(subagent_type="coder", isolation="worktree")`
      with a trivial write task. Record: the exact field names present; whether `agent_type` /
      `agent_id` appear; the value of `isolation_mode`; and whether the worktree was created anyway
      (which proves empty stdout declines to the default) → **F13, F14**.
- [ ] **Probe B (`baseRef`).** With the capture hook still declining, dispatch the same coder twice
      from a session on a feature branch carrying a commit absent from the default branch: once with
      `worktree.baseRef: "fresh"`, once with `"head"`. Record `git -C <worktreePath> rev-parse HEAD`
      each time → **F15**.
- [ ] **Probe C (Workflow path).** Dispatch one workflow agent with
      `agent(prompt, { agentType: "coder", model: "sonnet", effort: "high", isolation: "worktree" })`
      and record whether a payload line appears and what base the worktree reports → **F16**.
      (`opts.effort` exists on this path only; the Agent tool has no `effort` parameter.)
- [ ] Fill F13–F16 into the ADR's *Measured facts annex*, in the SPEC's table form, with the probe
      that produced each. Leave nothing guessed.
- [ ] Unregister the capture hook and delete the scratch branch.

**Decision points this task settles, with their recorded fallbacks:**
- `agent_type` absent → R-04's scoping falls back to `isolation_mode` + `worktree_branch` naming;
  if neither discriminates, record R-04 as blocked, ship the hook unregistered, and let the
  pre-flight assertion check `baseRef` only (ADR-0068 §D2). Do not invent a predicate.
- Decline not honoured → ADR-0068 §D3 reverts to fail-closed; update the ADR's Consequences and the
  hook header before Task 4 starts.

*Budget: `staging/plugin/scripts/worktree-capture.sh`, `docs/architecture/ADR-0068-176-worktree-isolation-contract.md` (~60 lines)*

**HITL:** this task edits `~/.claude/settings.json` on the operator's machine and dispatches live
agents. It needs the operator present. It is the only task that does.

---

## Task 2 — RED: the isolation-value guard and the retirement anchors (R-01, R-11, R-19)

New test file `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh`, written and seen
RED before any source change.

- [ ] **Section A — schema conformance (R-01).** Extract every `isolation` value named in
      `staging/plugin/skills/*/SKILL.md` and `staging/plugin/agents/*.md` and assert each is one of
      `worktree` or `remote`. Written as an **allowlist over discovered values**, never a denylist
      of `none` — a denylist cannot see the next invented value, which is the ADR-0043 direction
      lesson at the schema level. Include a count guard (`>= 1` value discovered) so a broken
      extraction cannot pass vacuously.
- [ ] **Section A2 — positive twin.** Assert the extractor actually finds `worktree` on
      `agents/coder.md:8`. Without this, a regex that matches nothing passes section A for the wrong
      reason (the `cfile=/dev/null` lesson: a negative-case assertion pins nothing alone).
- [ ] **Section A3 — synthetic invented value.** Run the extractor over a fixture naming
      `isolation: sandbox` and assert it fails. This is what makes A a forward guard rather than a
      record of today's two bad values.
- [ ] **Section B — dirty-tree retirement (R-11).** For each of `concept-to-code/SKILL.md`,
      `autopilot-build/SKILL.md`: assert **no isolation-selection block survives**, anchored on the
      compound phrase (e.g. `Non-empty output → dispatch` … `isolation`), not on the bare
      `git diff HEAD --name-only`.
- [ ] **Section B2 — D9 guard.** Assert `review-triage-fix/SKILL.md` **still contains** its
      stale-worktree pre-check. A test that removes too much is the failure mode here; this is the
      positive twin of section B.
- [ ] Register the file in `.github/workflows/docs-ci.yml`'s `shell-tests` named list. `ci.yml`'s
      glob and `.claude/test-cmd` pick it up automatically (R-19).
- [ ] Run it. Sections A, B **must be RED**; A2, A3, B2 green from the start (forward guards, not
      fix evidence — labelled as such in the file so a checkpoint is not mistaken for proof).

*Budget: `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh`, `.github/workflows/docs-ci.yml` (~220 lines)*

---

## Task 3 — GREEN: purge `isolation: "none"`, retire the dirty-tree condition, refuse a non-git CWD (R-01, R-11, R-13)

All 11 enumerated sites, in one pass. Turns Task 2 sections A and B green.

- [ ] **Sites 2-3** (`concept-to-code/SKILL.md:730-744`): the git-dir check keeps its `exit 0` arm
      (`isolation: worktree`) and its `exit non-0` arm becomes a **refusal** with the literal
      message: `"Worktree isolation contract: the session CWD is not inside a git repository. The
      chain cannot dispatch a modification agent here. Run the chain from inside the repository, or
      `git init` the project root, and re-invoke Step 5."` No second mode (R-13).
- [ ] **Sites 4, 7, 9**: delete the dirty-tree condition blocks entirely (R-11).
- [ ] **Site 1** (`SKILL.md:676`): rewrite the ADR-0050 §D4 reconciliation paragraph. It reconciles
      this pre-flight against a condition that no longer exists. Replace with one sentence stating
      the surviving invariant: at Step 5 entry the tree is clean, and every stage's output is
      committed and merged before the next stage's worktree is created.
- [ ] **Site 6** (`SKILL.md:903-904`): "Resolve `isolation` per the worktree isolation check above"
      → `isolation: "worktree"`, stated as a literal.
- [ ] **Sites 8-9** (`autopilot-build/SKILL.md:189-201`): same treatment; the "worktree disabled"
      report note goes with the branch that produced it.
- [ ] **Sites 10-11** (`deep-refactor/SKILL.md:108-114, 384`): delete Step 0.2 and `ISOLATION_MODE`;
      the non-git-subdirectory case joins the refusal of R-13. The dispatch brief's
      `isolation: <none if …>` becomes `isolation: worktree`.
- [ ] Re-run Task 2. Sections A and B green; A2, A3, B2 still green.

*Budget: `staging/plugin/skills/concept-to-code/SKILL.md`, `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/skills/deep-refactor/SKILL.md` (~180 lines)*

**Contract change — call sites to update.** `isolation: "none"` disappears from the chain's
vocabulary. Grep confirms no `.sh` script and no test reads that string as a value today; the only
consumers are the SKILL.md blocks above and the two doc surfaces in Task 8. `recovery-preflight.test.sh:251-255`
and `workflow-dispatch-pins.test.sh:84` both anchor on the heading
`**Pre-dispatch: worktree isolation check` — **that heading must survive verbatim** or both files
break. Keep the heading, change the body. Run the **full** suite after this task, not just the new
file: two existing test files reference these blocks.

---

## Task 4 — `worktree-create.sh`: fork from HEAD for the modification set, decline for everything else (R-02, R-04)

Written against F13–F16 from Task 1, never against the SPEC's F11.

- [ ] **RED first.** Extend `worktree-isolation-contract.test.sh` with:
      - **Section C (R-02).** Pipe a synthetic payload with a modification `agent_type` into the
        hook inside a fixture repo on a feature branch carrying a commit absent from the default
        branch. Assert: exit 0, stdout is exactly the worktree path, the worktree exists, and
        `git -C <path> rev-parse HEAD` equals the **feature branch's** HEAD sha — not the default
        branch's. Assert the supplied `base_branch` is ignored.
      - **Section D (R-04).** Same payload with `agent_type: reviewer`, with an unknown agent type,
        and with the field absent. Each: exit 0, **empty stdout**, no worktree created. This is the
        decline path and it is tested as a first-class case, not an afterthought (ADR-0068 §A3).
      - **Section E (fail-safe, ADR-0068 §D3).** `jq` unavailable, unparseable stdin, `cwd` not a
        git repository, `worktree_path` already exists, `worktree_branch` already resolves. Each
        must exit **0 with empty stdout**. Assert the hook emits a non-zero exit in no case.
      - **Section F (audit).** Assert one line is appended recording `agent_type`, the supplied
        `base_branch`, and the resolved `head_sha`.
- [ ] **GREEN.** Write `staging/plugin/scripts/worktree-create.sh`. Structure mirrors
      `agent-write-scope.sh`: header comment stating the contract and the *why*, `jq` guard,
      audit-log helper, early decline for the common path. Modification set: `coder`, `refactorer`,
      `debugger`, `tester`. Take-over path: precondition checks → `git -C "$cwd" worktree add -b
      "$worktree_branch" "$worktree_path" "$head_sha"` → `.worktreeinclude` replay (literal path
      entries only; anything skipped is written to the audit log, per ADR-0068 Consequences) →
      `printf '%s\n' "$worktree_path"`. On any `git worktree add` failure: best-effort
      `git worktree remove --force`, then decline.
- [ ] Add the `PAIRS` entry `plugin/scripts/worktree-create.sh|hooks/worktree-create.sh` to
      `staging/sync-to-claude.sh`. `pairs-completeness.test.sh`'s reverse check fails without it.

*Budget: `staging/plugin/scripts/worktree-create.sh`, `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh`, `staging/sync-to-claude.sh` (~260 lines)*

---

## Task 5 — Step 5 pre-flight assertion 4, its manifest record, and the sync wiring (R-05, R-17)

- [ ] **RED.** Extend the test file with **section G**: assert `concept-to-code/SKILL.md` contains a
      fourth pre-flight assertion (`Step 5.0.4`) naming `WorktreeCreate`; assert it names the
      literal remediation command; assert `autopilot-build/SKILL.md` restates it and records the
      failure in the report rather than prompting (ADR-0050 §D6 — no leniency branch for autopilot).
      Extend `sync-manual-steps.test.sh` with the `worktree-create` wiring notice: fires when absent,
      suppressed once wired, fires independently of the six existing notices, and fail-safes on a
      missing `settings.json` (the D1–D4 pattern already in that file).
- [ ] **GREEN — assertion 4.** Add `Step 5.0.4` after `Step 5.0.3` in `concept-to-code/SKILL.md`.
      It is compound and both halves must hold (ADR-0068 §D1):
      ```bash
      grep -q 'worktree-create' ~/.claude/settings.json 2>/dev/null
      python3 -c "import json,sys; d=json.load(open('$HOME/.claude/settings.json')); sys.exit(0 if d.get('worktree',{}).get('baseRef')=='head' else 1)"
      ```
      Either failing → refuse to dispatch, print the literal remediation: the `settings.json`
      `WorktreeCreate` entry to add and `"worktree": { "baseRef": "head" }`. Record
      `worktree_hook_verified` accordingly.
- [ ] **GREEN — manifest.** Add `worktree_hook_verified: false` and `worktree_merges: []` to
      `manifest-init.sh` as additive fields. Add conditional invariants 20 and 21 to
      `manifest-validate.sh`, both "if present" so pre-existing manifests stay valid with no
      migration. `worktree_hook_verified` is boolean → `manifest-set-flag.sh` sets it;
      `worktree_merges` is an array → bash `sed` on the additive field, with the exact command in a
      manifest comment (the `step5_review_mode` precedent — that comment is the only place a human
      finds it).
- [ ] **GREEN — sync.** Add the `worktree-create` MANUAL STEP block to `staging/sync-to-claude.sh`,
      following the existing six verbatim in shape. The note must say what the other six say and one
      thing more: **until this entry exists the hook is deployed but never invoked, and the chain
      falls back to `worktree.baseRef` alone.** Set `"baseRef": "head"` in
      `staging/user/settings.json` (reference copy; `sync-to-claude.sh` does not auto-edit
      `settings.json`, so the live change is a documented manual step).

*Budget: `staging/plugin/skills/concept-to-code/SKILL.md`, `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh`, `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh`, `staging/sync-to-claude.sh`, `staging/user/settings.json`, `staging/plugin/scripts/tests/sync-manual-steps.test.sh` (~200 lines)*

---

## Task 6 — The stage protocol: explicit isolation on both paths, tester in a worktree, orchestrator merge-back (R-06, R-07, R-08, R-09, R-14)

- [ ] **RED.** Extend the test file with **section H**:
      - every `agent(` call with `agentType: "coder"` in `concept-to-code/SKILL.md` — Step 5 Stage 2
        **and** Step 6's fix-agent dispatch — carries `isolation: 'worktree'` (R-06);
      - Step 5 Stage 1's tester dispatch carries `isolation: "worktree"` (R-09);
      - a merge-back block exists naming `worktreePath` and `worktreeBranch`, and it appears
        **between** the tester stage and the coder stage (positional assertion, the
        `recovery-preflight.test.sh` RE5 idiom) (R-07, R-09);
      - the merge-back block states the empty/auto-removed case as "nothing to merge" with neither
        an error nor an empty commit (R-14);
      - `agents/coder.md` still contains "never commits" and **no** dispatch prompt in
        `concept-to-code/SKILL.md` or `autopilot-build/SKILL.md` instructs any coder to commit
        (R-08). This one is green from the start — a forward guard, labelled as such.
      - no `agent(` call anywhere carries an `effort` key on an `Agent(` (Agent-tool) call. The
        Agent tool has no `effort` parameter; `opts.effort` is Workflow-only.
- [ ] **GREEN — Workflow path.** Step 5 Stage 1 gains `isolation: "worktree"` on the tester
      `agent()` call; Stage 2 gains `isolation: 'worktree'` on the coder call (F4: frontmatter does
      not reach this path). Step 6's `agent(...)` fix dispatch gains it too.
- [ ] **GREEN — Agent-tool path.** The fallback's tester and coder dispatches pass
      `isolation: "worktree"` explicitly rather than inheriting it, for the same reason `model` and
      `effort` are pinned there.
- [ ] **GREEN — merge-back block.** One new resolution site in `concept-to-code/SKILL.md`, stated
      once and referenced by both dispatch paths (the `#### Proportional audit depth` /
      `#### Pattern seed handoff` single-resolution-site convention):
      ```bash
      # $WT = worktreePath, $WB = worktreeBranch, both from the dispatch result (F10)
      [ -d "$WT" ] || { echo "nothing to merge: worktree auto-removed"; }   # F6, not an error
      if [ -d "$WT" ] && [ -n "$(git -C "$WT" status --porcelain 2>/dev/null)" ]; then
        git -C "$WT" add -A
        git -C "$WT" commit -m "chore(step5): snapshot <stage> worktree (<agent_type>)"
        git merge --no-edit "$WB" || <conflict halt, Task 7>
        git worktree remove "$WT" 2>/dev/null || true
      fi
      ```
      State explicitly, at this site: **the orchestrator commits, never the agent** — `coder.md`'s
      "never commits" is untouched and the snapshot happens after the dispatch has returned (R-08).
      Append one `worktree_merges` entry per merged stage; append none when nothing was merged
      (R-14).
- [ ] **GREEN — ordering.** State that the tester's merge completes **before** the coder's worktree
      is created, so the coder forks from a `HEAD` containing the red tests (R-09).
- [ ] **GREEN — report.** `step5-report.json` gains the additive `worktree_merges` array; its
      absence means a pre-feature run, not a malformed report.
- [ ] **GREEN — pruning.** After a successful merge, prune the worktree. An **unmerged** worktree is
      reported, never silently deleted.

*Budget: `staging/plugin/skills/concept-to-code/SKILL.md`, `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` (~260 lines)*

---

## Task 7 — Binding conflict scan and the conflict halt (R-10, R-12)

- [ ] **RED.** Extend the test file with **section I**: the file-conflict scan block states that
      groups naming the same file are **sequenced, never dispatched in the same `parallel()` batch**
      (R-10); its old "advisory only when every conflicting group keeps `isolation: worktree`"
      clause is gone; a conflict-halt block exists naming `git merge --abort`, branch preservation,
      and `--diff-filter=U` (R-12); and it states that no automatic resolution is attempted.
- [ ] **GREEN — scan.** Rewrite `concept-to-code/SKILL.md:847-858`. The advisory/load-bearing split
      collapses: the scan is binding in every case, because merges are now real and a conflict halts.
      Groups with no path overlap keep the default parallel dispatch.
- [ ] **GREEN — halt.** Add the halt to the merge-back block from Task 6:
      ```bash
      CONFLICTS=$(git diff --name-only --diff-filter=U)   # capture BEFORE the abort
      git merge --abort
      ```
      Report the worktree branch name and `$CONFLICTS`, preserve the branch, halt. No rebase, no
      `-X ours`, no resolver dispatch. Under autopilot the halt is recorded in the report rather
      than prompted, exactly as ADR-0050's assertions behave.
- [ ] Restate the halt by reference in `autopilot-build/SKILL.md` and note that
      `nightly-autopilot` inherits it (it reuses c2c Steps 5–7 verbatim).

*Budget: `staging/plugin/skills/concept-to-code/SKILL.md`, `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` (~140 lines)*

---

## Task 8 — Documentation surfaces, forward-recorded corrections, and issue #175 (R-15, R-16, R-18)

- [ ] **RED.** Extend the test file with **section J**: `staging/user/rules/parallelization.md`
      states the contract as measured and names no fallback; `docs/GUIDA-USO-IT.md` no longer
      promises `isolation: none` automatically; ADR-0016, ADR-0049 and ADR-0050 each carry a dated
      correction block naming ADR-0068 (R-15, R-16).
- [ ] **GREEN — `parallelization.md:21`.** Replace the single line with the contract: parallel
      modification sub-agents run in a worktree forked from `HEAD`; the orchestrator merges each
      stage back before the next worktree is created; a non-git CWD is refused, not downgraded.
- [ ] **GREEN — `docs/GUIDA-USO-IT.md:632-633`.** Delete the false fallback sentence; state the
      refusal. Check lines 117, 136, 167 and 275 for the same claim while there.
- [ ] **GREEN — `docs/SKILLS-AND-AGENTS-GUIDE.md:355-356`.** Same false claim ("isolation falls back
      to `none`"), same fix. Not named in the SPEC's Scope; the SPEC deliberately does not close the
      site count, so it is fixed rather than merely disclosed.
- [ ] **GREEN — forward-recorded corrections (ADR-0034 precedent, no in-place edits).** Append a
      dated correction block to ADR-0016 (§ *Cross-repo isolation constraint* and the probe finding
      about `isolation: none` for cross-repo), ADR-0049 (§D2 retired), ADR-0050 (§D4 retired). Each
      names ADR-0068, what is superseded, and why (R-16).
- [ ] **GREEN — `CLAUDE.md`.** Add the `## Decisions from the worktree isolation contract chain
      (ADR-0068)` section, in the shape every chain since #28 uses.
- [ ] **GREEN — issue #175.** Record the closure reason in the ADR and in the PR body: its
      dirty-tree check is **retired** by R-11, not rewritten, so the `git diff HEAD --name-only`
      untracked-file blindness it reported is moot (R-18). Closing the issue on GitHub is a HITL
      action for the operator, not an agent action.

*Budget: `staging/user/rules/parallelization.md`, `docs/GUIDA-USO-IT.md`, `docs/SKILLS-AND-AGENTS-GUIDE.md`, `docs/architecture/ADR-0016-dynamic-workflows-step5.md`, `docs/architecture/ADR-0049-103-generator-verifier-separation.md`, `docs/architecture/ADR-0050-104-recovery-readiness-preflight.md`, `CLAUDE.md`, `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` (~200 lines)*

---

## Task 9 — Live evidence on both dispatch paths, and full-suite verification (R-03, R-19)

- [ ] Deploy: `bash staging/sync-to-claude.sh` (dry run), review the diff, then `--apply`. Perform
      the printed MANUAL STEP for `worktree-create` and set `"worktree": { "baseRef": "head" }` in
      `~/.claude/settings.json` by hand.
- [ ] **Evidence, Agent-tool path.** On a feature branch carrying a commit absent from the default
      branch, run one real Step 5 task group. Record: the worktree's `HEAD` sha equals the feature
      branch's; the tester's tests are visible inside the coder's worktree; both branches merged;
      `worktree_merges` has two entries.
- [ ] **Evidence, Workflow path.** Same, with `hook_verified = true`. Record the same four facts.
- [ ] Append both records to the ADR's *Measured facts annex* as the R-03 evidence. **Recorded as
      evidence, not asserted** — the SPEC is explicit that this is not a test assertion, because it
      needs a live dispatch that CI cannot run.
- [ ] Run the **full** suite: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`.
      Not just the new file — Task 3 touches blocks that `recovery-preflight.test.sh` and
      `workflow-dispatch-pins.test.sh` anchor into, and Task 5 touches `sync-manual-steps.test.sh`
      and the manifest helpers.
- [ ] Confirm `worktree-isolation-contract` is present in **both** CI registries (R-19).
- [ ] Confirm `pairs-completeness.test.sh` passes with the new `worktree-create.sh` entry.

**HITL:** deploy (`--apply`), the `settings.json` edit, the commit, the push, and closing #175 are
all operator actions.

---

## Risks

- **R1 — the design is contingent on Task 1.** If `agent_type` is absent from the payload, R-04 is
  blocked and the hook ships unregistered; if decline is not honoured, ADR-0068 §D3 reverts to
  fail-closed. Both fallbacks are written down. Task 1 must complete and the annex must be filled
  before Task 4 starts.
- **R2 — `WorktreeCreate` has no matcher.** The hook runs on every worktree creation on the
  machine, including `--worktree` sessions. Sections D and E of the test file are the only thing
  standing between a bug in it and every worktree the operator creates.
- **R3 — `.worktreeinclude` replay is partial.** Literal path entries only; gitignore-syntax
  patterns are skipped and logged. A generated `app-fastapi-react` project using a pattern rather
  than a literal path will lose that file inside a modification agent's worktree.
- **R4 — a merge conflict now halts an unattended run.** `autopilot-build` and `nightly-autopilot`
  inherit it. This is the intended trade, but it changes overnight behaviour.
- **R5 — the heading `**Pre-dispatch: worktree isolation check` is load-bearing** for two existing
  test files. Task 3 rewrites that block's body; changing the heading breaks
  `recovery-preflight.test.sh:251` and `workflow-dispatch-pins.test.sh:84` silently.
- **R6 — `settings.json` is not auto-synced.** Both halves of the D1 contract — the hook
  registration and `baseRef: "head"` — are manual steps. The Task 5 pre-flight assertion is what
  makes a missed step visible; without it the chain reverts to the defect with no signal.
- **R7 — this ships an instruction, not an enforcement** for the stage protocol. Every merge-back
  and halt is prose in a SKILL.md a model is asked to follow. The harness pins that the instruction
  exists; nothing pins that it is obeyed. Enforcing it in `manifest-transition.sh` was rejected on
  blast radius (ADR-0068 §A7).

## HITL gates

- **Task 1** — registering a capture hook in `~/.claude/settings.json` and running live dispatches.
- **Task 9** — `sync-to-claude.sh --apply`, the `settings.json` manual wiring, `baseRef` change.
- **Commit / push / PR** — operator, as always.
- **Closing issue #175** — operator.

TEST-CMD CANDIDATE: for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done
TEST-CMD MODE: brownfield
