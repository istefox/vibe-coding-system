# Implementation plan — Worktree isolation contract for the multi-agent chain

- **Issue:** #176 (supersedes #175)
- **ADR:** `docs/architecture/ADR-0068-176-worktree-isolation-contract.md`
- **SPEC:** `SPEC.md` (topic slug `176-worktree-isolation-contract`)
- **Date:** 2026-07-28
- **Revised:** 2026-07-28, after Task 1's probe. Task 1 is complete; Tasks 4, 5 and 9 are rewritten;
  Task 1b is new; Tasks 6 and 8 take one surgical change each. Tasks 2, 3 and 7 are untouched.
- **Style:** TDD — every behavioural assertion is seen RED before the change that makes it green
  (R-19). Static prose anchors are marked as such; they are still written first and still seen RED.

## What the revision changed, in one paragraph

Task 1 measured the `WorktreeCreate` event (ADR-0068 annex, F13–F18). The payload carries no agent
identity, and a registered hook cannot decline — it must return a worktree path on every invocation
on the machine, and the event has no matcher. `worktree-create.sh` is therefore **not written**:
`worktree.baseRef: "head"` is the mechanism (F15 measured it sufficient on both dispatch paths), the
audit record moves into the Task 6 merge-back where the orchestrator observes the fork point
directly, and five SPEC requirement IDs are re-scoped rather than deleted so the coverage gate sees
an unchanged ID set. Everything about worktrees themselves — merge-back, tester staging, explicit
isolation on both paths, the binding conflict scan — is unaffected and unchanged.

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
- **`**Pre-dispatch: worktree isolation check` is a load-bearing heading.** `recovery-preflight.test.sh:251`
  and `workflow-dispatch-pins.test.sh:84` both anchor on it. **Unchanged by this revision.** Task 3
  rewrites that block's body; the heading line itself must survive verbatim or both files break
  silently. Repeated in Task 3 and in Risk R5 on purpose.
- **Never cite an ID the SPEC does not declare.** The SPEC declares R-01 … R-19 and nothing else.
  Task 1b re-scopes five of them; it adds none and removes none, so the set `spec-coverage.sh` reads
  is identical before and after.
- **Every markdown file this plan writes under `docs/architecture/` is markdownlint-enforced**
  (MD009/MD010/MD018/MD038/MD056 among others). `docs/superpowers/` is in the lint's ignore list;
  the ADRs are not.

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

## Task 1 — Measure the real `WorktreeCreate` contract before writing anything against it (R-03) — **DONE 2026-07-28**

The SPEC's F11 is doc-sourced and disagreed with the current docs on field names and on whether
`agent_type` exists at all. Nothing downstream may be written against F11. **Completed; results are
F13–F16 in the ADR's Measured facts annex, plus F17–F18 in its addendum.**

- [x] Write `staging/plugin/scripts/worktree-capture.sh`: reads stdin, appends it verbatim to
      `$HOME/.claude/state/worktree-probe/payloads.jsonl`, exits **0 with empty stdout**.
- [x] Register it as a `WorktreeCreate` hook in `~/.claude/settings.json` by hand, on a scratch
      branch of this repository.
- [x] **Probe A (payload + decline).** → **F13, F14**. Both answers were negative: the payload has
      six fields and none of them identifies the agent, and empty stdout does not decline — it
      aborts the dispatch with `WorktreeCreate hook failed: hook succeeded but returned no worktree
      path`.
- [x] **Probe B (`baseRef`).** → **F15**. `"fresh"` forks from the default branch (`5518583`, ADR
      absent); `"head"` forks from session `HEAD` (`129d5e0`, ADR present).
- [x] **Probe C (Workflow path).** → **F16**. A worktree *is* created on the Workflow path when
      `opts.isolation: 'worktree'` is passed, and `worktree.baseRef` applies to it identically.
- [x] Fill F13–F16 into the ADR's *Measured facts annex*. Left nothing guessed.
- [x] Unregister the capture hook. Verified: `~/.claude/settings.json` has no `WorktreeCreate` key.
      The scratch branch was not needed — the probe ran on the feature branch.
      `worktree-capture.sh` is **retained**, not deleted (Task 4 rules on it).

**Both recorded fallbacks fired, and the ladder ran off its end.**

- `agent_type` absent → the fallback was "scope on `isolation_mode` plus the `worktree_branch`
  naming convention". **Neither field exists either** (F13), so the fallback was unavailable, and
  its terminal clause applied: *record R-04 as blocked, do not invent a predicate*.
- Decline not honoured → the fallback was "ADR-0068 §D3 reverts to fail-closed; update the
  Consequences and the hook header before Task 4 starts". **Not taken**, because F14 combined with
  the absent matcher makes a fail-closed hook the owner of every worktree creation on the machine.
  §D3 is amended instead: the fail-safe question is moot because nothing is registered.
- The terminal fallback said "ship the hook unregistered". **That is also rejected** — see Task 4's
  ruling and ADR-0068 §A9. Nothing ships.

**Live machine state carried forward, verified 2026-07-28:** `~/.claude/settings.json` now has
`"worktree": { "baseRef": "head" }` (operator-approved, kept). No `WorktreeCreate` hook is
registered. `~/.claude/state/worktree-probe/payloads.jsonl` holds the captured payload and is the
evidence behind F13 and F17.

---

## Task 1b — Amend the SPEC to match what was measured (R-02, R-03, R-04, R-05, R-17)

**Runs first, before any test is written against an ID.** Five success criteria named a mechanism
the probe found does not exist. The IDs are **re-scoped, never deleted**: `spec-coverage.sh` blocks
the Step 5 → Step 6 boundary on both an uncovered declared ID and a cited undeclared one, so an
unchanged ID set is the only shape that cannot break the gate. This task is transcription of text
the operator approves at this Gate 2 re-entry, not a fresh decision — copy it verbatim, do not
paraphrase.

- [ ] **Success criteria, five replacements.** Replace the existing R-02, R-03, R-04, R-05 and R-17
      checklist items in `SPEC.md` with exactly:

      - [ ] R-02 The base-fork mechanism is `worktree.baseRef: "head"`, not a hook:
            `staging/user/settings.json` declares it, `staging/sync-to-claude.sh` prints a MANUAL
            STEP for the live `~/.claude/settings.json`, and a test asserts both. `worktree-create.sh`
            is not written — F13/F14 refuted its premise (ADR-0068 §D1/§D2).
      - [ ] R-03 A live dispatch confirms that a worktree reports the feature branch's `HEAD`
            commit, not the default branch's, on both the Agent-tool path and the Workflow path —
            recorded as evidence, not asserted. The base-fork half is already satisfied by F15/F16;
            the stage-protocol half is recorded at implementation time.
      - [ ] R-04 Nothing this system installs intercepts worktree creation for any session outside
            the chain: no `WorktreeCreate` registration ships, a test asserts that no file under
            `staging/` registers the event (with a positive twin proving the detector fires on a
            fixture that does), and `staging/plugin/scripts/worktree-capture.sh` is retained
            unregistered with a header stating that registering it aborts every worktree creation
            on the machine (F14).
      - [ ] R-05 The Step 5 pre-flight gains a fourth assertion: `worktree.baseRef` is `"head"` in
            the effective `settings.json`. Absent, wrong, unreadable or unparseable → refuse the
            dispatch and print the literal remediation command. It fails **closed**, like ADR-0050's
            other three assertions and unlike this repository's hooks.
      - [ ] R-17 The `worktree.baseRef: "head"` change reaches `~/.claude/settings.json` through the
            documented sync path — a `sync-to-claude.sh` MANUAL STEP, since sync never edits
            `settings.json` — and `PAIRS` covers every new file that has a deployed counterpart
            (ADR-0043).

- [ ] **Measured-facts table, two rows superseded in place (not deleted — the evidence trail is the
      point).** Append to F4's *Fact* cell: `**Wording superseded by ADR-0068 F16:** frontmatter
      isolation does not reach this path, but a worktree IS created when opts.isolation is passed.`
      Append to F11's *Fact* cell: `**Superseded by ADR-0068 F13 (measured):** the payload carries
      none of these fields; the real six are session_id, transcript_path, cwd, prompt_id,
      hook_event_name, name.`
- [ ] **"What is not verified", third bullet.** It asks whether `opts.isolation: 'worktree'` routes
      through `WorktreeCreate` the way frontmatter isolation does. Replace with the answer: F16
      measured a worktree created on the Workflow path with `baseRef` applying identically.
- [ ] **Architecture — Component 1.** Replace the `worktree-create.sh` description with the one-layer
      contract: `worktree.baseRef: "head"` declared in `staging/user/settings.json`, wired to the
      live file by a sync MANUAL STEP, asserted at Step 5 pre-flight. State that no `WorktreeCreate`
      hook is registered and why (F13 no discriminator, F14 no decline, no matcher).
- [ ] **Architecture — Component 2.** The pre-flight assertion's subject changes from the
      `WorktreeCreate` registration to `worktree.baseRef`. The paragraph's argument — that an unwired
      mechanism must be distinguishable from a working one — is unchanged and gets *stronger*: the
      assertion now checks the key that actually governs the behaviour.
- [ ] **Architecture — Component 3, one added sentence.** The orchestrator records the worktree's
      fork point before committing into it, and halts on a mismatch against the feature branch's
      `HEAD` at dispatch time (ADR-0068 §D5). This is where the deleted hook's audit record went.
- [ ] **Data model.** Rename `worktree_hook_verified` → `worktree_baseref_verified` and restate its
      meaning ("the Step 5 pre-flight found `worktree.baseRef: \"head\"`"). Nothing has shipped
      under the old name.
- [ ] **API / Interfaces.** Delete the `worktree-create.sh` stdin/stdout contract paragraph, including
      the claim that it is "the first hook in this repository that is not
      allow-on-every-failure-mode". Replace with ADR-0068 §D3's surviving rule: the
      allow-on-every-failure-mode convention is a property of `PreToolUse`-class events, which have
      an allow path; `WorktreeCreate` has none, and the one component here that fails closed is a
      pre-flight assertion, not a hook.
- [ ] **Edge cases.** Delete "Duplicate registration" (no registration exists) and "Worktree name
      collision" as a hook concern; keep the worktree-branch-collision case, which the merge-back
      still meets. Leave the other five untouched.
- [ ] **UI flows — "Hook missing".** Rename to "`baseRef` not set" and restate: pre-flight assertion
      4 fails → no dispatch → remediation printed; under autopilot, recorded in the report.

**Addendum — added by the orchestrator during implementation, operator-approved.** The Task 1b
dispatch correctly refused to widen its own scope and reported three `WorktreeCreate` references
left stale by the checklist above, all of which contradict the sections it had just amended in the
same file. A fourth was found in the same pass. All four are fixed here rather than deferred to
Task 8, whose scope is other documents:

- [x] **Intro, "The contract, stated once", clause 2.** "created through the project's
      `WorktreeCreate` hook" → created through CC's own mechanism with `worktree.baseRef: "head"`,
      citing F13/F14 and ADR-0068 §D1.
- [x] **Scope, "In." first item.** "The `WorktreeCreate` hook and its registration" → "The
      `worktree.baseRef: \"head\"` declaration and its sync path".
- [x] **Edge cases, "Non-default default branch".** "The hook must not hardcode `main`" → nothing in
      the design hardcodes it; `baseRef: "head"` never resolves a default branch. Notes that the
      Step 5 pre-flight's own default-branch resolution is ADR-0050's and unchanged.
- [x] **"What is not verified", second bullet.** The non-git-CWD question rested on F11, which F13
      supersedes, and on a hook that no longer ships. Marked moot, pointing at R-13's refusal.

Left deliberately: the third "What is not verified" bullet keeps the verbatim replacement text the
operator approved above, even though it now states a resolved fact inside a list of open ones.

*Budget: `SPEC.md` (~90 lines)*

**Verification for this task, run before Task 2 starts:**

```bash
bash staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh \
  --spec SPEC.md \
  --plan docs/superpowers/plans/2026-07-28-176-worktree-isolation-contract.md --list
```

It must list R-01 … R-19, exactly nineteen IDs, with no `ORPHAN`, no `MALFORMED` and no
`DUPLICATE`. An ID count other than 19 means a checklist item lost its leading ID token during the
edit — the checker declares an ID only when it is the **first token after the checkbox marker**, so
re-indenting a criterion can silently undeclare it.

**HITL:** `SPEC.md` is the Gate-1-approved artefact. Amending it is the substance of this Gate 2
re-entry; the operator approves the text above by approving this plan, and no further gate is
inserted mid-implementation.

---

## Task 2 — RED: the isolation-value guard and the retirement anchors (R-01, R-11, R-19)

*Unchanged by the revision.*

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

*Unchanged by the revision.*

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

**Addendum — added during implementation, operator-approved. Two sites this task's own table did
not name.**

- [x] **Site 5 was mandatory, not optional.** The conflict-scan's advisory/load-bearing split still
      contained two literal `isolation: "none"` strings and referenced the dirty-tree block this
      task deletes, so section A1 could not go green without it. Rewritten to unconditionally
      advisory. **Task 7 rewrites the same block again**, into the binding form R-10 requires; this
      was the minimum needed here, not a pre-emption of that task.
- [x] **`test-write-scope.test.sh` TL1 is a cross-feature contradiction, and the task list never
      named it.** TL1 (ADR-0049) asserts `autopilot-build`'s Step 5 **restates** the dirty-tree
      condition. R-11 requires that condition **retired**, and ADR-0068's own header records that it
      supersedes ADR-0049 §D2 in part. So the assertion's premise was revoked by an approved ADR —
      it is inverted, not deleted, to keep a forward guard against reintroduction, mirroring B1c.
      The dispatched coder correctly refused to edit a test file and reported it instead; a tester
      made the change. **The lesson for the remaining tasks: a plan that retires a contract must
      grep the whole harness for assertions pinning that contract, not only the source that
      implements it.**

**Contract change — call sites to update.** `isolation: "none"` disappears from the chain's
vocabulary. Grep confirms no `.sh` script and no test reads that string as a value today; the only
consumers are the SKILL.md blocks above and the two doc surfaces in Task 8. `recovery-preflight.test.sh:251-255`
and `workflow-dispatch-pins.test.sh:84` both anchor on the heading
`**Pre-dispatch: worktree isolation check` — **that heading must survive verbatim** or both files
break. Keep the heading, change the body. Run the **full** suite after this task, not just the new
file: two existing test files reference these blocks.

---

## Task 4 — The base-fork mechanism, and the standing decision to register no `WorktreeCreate` hook (R-02, R-04)

**Rewritten 2026-07-28.** The original Task 4 wrote `worktree-create.sh` — a hook that reads the
supplied `base`, ignores it, forks from `HEAD`, and declines for agent types outside the chain's
modification set. F13 removed the field it would scope on, F14 removed the decline it would scope
*by*, and `WorktreeCreate` has no matcher. That hook is not written. What ships instead is one
settings key and a forward guard against re-proposing the hook without re-measuring.

- [ ] **RED first.** Extend `worktree-isolation-contract.test.sh` with:
      - **Section C (R-02) — the mechanism is declared.** Parse `staging/user/settings.json` with
        `python3 -c` (JSON, not grep: a grep for `head` matches a comment, a sibling key, or a value
        under the wrong parent) and assert `worktree.baseRef == "head"`. **Positive twin in the same
        section:** assert the parse finds a `worktree` object at all, and assert the same predicate
        returns non-zero against a fixture declaring `"baseRef": "fresh"`. Without both, a parse that
        silently returns `None` passes for the wrong reason.
      - **Section C2 (R-02) — the deployment path is declared.** Assert `staging/sync-to-claude.sh`
        contains a MANUAL STEP block for the `baseRef` settings key, and that it names both the key
        path and the literal value. Static prose anchor; see Task 5 for the block itself and for the
        `sync-manual-steps.test.sh` behavioural assertions.
      - **Section D (R-04) — nothing registers the event.** Assert no file under `staging/` registers
        a `WorktreeCreate` hook: no `WorktreeCreate` key in `staging/user/settings.json`'s hooks
        object, and no `PAIRS` entry whose destination lands a `worktree-create` hook.
        **Positive twin, mandatory:** run the same detector over a fixture `settings.json` that *does*
        register one and assert it fires. A detector that reports nothing must be distinguishable
        from a subject that contains nothing — this is the ADR-0043 direction lesson and the
        ADR-0039 `cfile=/dev/null` correction, and section D is exactly the shape that failed both
        times.
      - **Section D2 (R-04) — the retained instrument is labelled.** Assert
        `staging/plugin/scripts/worktree-capture.sh` exists, and that its header contains the
        do-not-register warning naming F14's consequence (every worktree creation on the machine
        aborts) and the words `measuring instrument`. Assert it is **not** in `PAIRS`.
      - **Section D3 — the reason is in the test file's own header.** Assert the test file's header
        names F13 and F14 as the reason no hook exists. Self-referential on purpose: the next person
        to propose the hook reads the test that forbids it, and the test must carry the evidence, not
        just the prohibition.
- [ ] **GREEN — the settings key.** Set `"baseRef": "head"` in `staging/user/settings.json`
      (currently `"fresh"` at line 300). This is the reference copy; the live
      `~/.claude/settings.json` already carries it (set during Task 1, operator-approved) and
      `sync-to-claude.sh` never edits `settings.json`, which is why Task 5 adds the MANUAL STEP.
- [ ] **GREEN — rewrite `worktree-capture.sh`'s header and its exit behaviour.** The file as it
      stands **teaches the refuted belief**: its header states a three-exit-state contract in which
      exit 0 with empty stdout declines and falls through to default git behaviour. F14 refuted that
      and the header is now the single most misleading paragraph in the repository on this subject.
      Rewrite it to state, in its first five lines: this is a measuring instrument, not a hook to
      wire; `WorktreeCreate` has **two** outcomes, path-or-abort, and no abstain state; registering
      this script aborts every worktree creation on this machine, in every project, until it is
      unregistered. Change the script to **exit non-zero with an explanatory stderr line** instead of
      exit 0 with empty stdout — both abort (F14), so it should abort with a message that names
      itself rather than with the platform's generic `hook succeeded but returned no worktree path`.
      Keep the capture behaviour and the payload path unchanged; that file is F13's and F17's
      evidence.
- [ ] **GREEN — no new `PAIRS` entry, deliberately.** `worktree-capture.sh` must never be deployed
      to `~/.claude/hooks/`: a file sitting there next to a wiring note reads like something to wire.
      This matches `hook-probe-sandbox.sh`, `hook-probe.sh` and `hook-probe-verify.sh`, which are
      likewise staging-only with no entry. It is also not a CI failure: `pairs-completeness.test.sh`'s
      reverse check covers `plugin/agents/*.md`, `user/rules/*.md` and `plugin/skills/*/SKILL.md`
      only — **the original plan asserted the opposite for `worktree-create.sh` and was wrong about
      it**, a claim about a check's behaviour made without running the check.
- [ ] **Not written, recorded here so the absence is deliberate rather than forgotten:**
      `staging/plugin/scripts/worktree-create.sh`, its `PAIRS` entry, its `.worktreeinclude` replay,
      and the hook-wiring MANUAL STEP that would have accompanied it.
- [ ] Re-run Task 2's file. Sections C, C2, D, D2, D3 green.

*Budget: `staging/user/settings.json`, `staging/plugin/scripts/worktree-capture.sh`, `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` (~150 lines)*

---

## Task 5 — Step 5 pre-flight assertion 4, its manifest record, and the sync wiring (R-05, R-17)

**Rewritten 2026-07-28.** The assertion's subject moves from the `WorktreeCreate` registration to
`worktree.baseRef`, which is an improvement rather than a downgrade: it now checks the key that
actually governs the behaviour, so it cannot pass while the mechanism is wrong.

- [ ] **RED.** Extend the test file with **section G**: assert `concept-to-code/SKILL.md` contains a
      fourth pre-flight assertion (`Step 5.0.4`) naming `worktree.baseRef` and the literal value
      `head`; assert it names the literal remediation command; assert it states that an unreadable or
      unparseable `settings.json` counts as **not verified** (fails closed); assert
      `autopilot-build/SKILL.md` restates it and records the failure in the report rather than
      prompting (ADR-0050 §D6 — no leniency branch for autopilot). Extend
      `sync-manual-steps.test.sh` with the `baseRef` notice: fires when the key is absent, fires when
      the key is present but not `"head"`, suppressed once correct, fires independently of the six
      existing notices, and fail-safes on a missing `settings.json` (the D1–D4 pattern already in
      that file).
- [ ] **GREEN — assertion 4.** Add `Step 5.0.4` after `Step 5.0.3` in `concept-to-code/SKILL.md`:

      ```bash
      python3 -c "import json,os,sys; p=os.path.expanduser('~/.claude/settings.json'); d=json.load(open(p)); sys.exit(0 if d.get('worktree',{}).get('baseRef')=='head' else 1)"
      ```

      Non-zero, **including a missing or unparseable file**, → refuse to dispatch. Print the literal
      remediation: `Recovery-readiness pre-flight: set "worktree": { "baseRef": "head" } in
      ~/.claude/settings.json and re-invoke Step 5. Without it every modification agent's worktree
      forks from the default branch and cannot see this feature branch's commits (ADR-0068 F15).`
      State at the site that this assertion **fails closed**, like ADR-0050's other three and unlike
      every hook in this repository — a reader who pattern-matches on the hook convention will guess
      the opposite. Record `worktree_baseref_verified` accordingly.
- [ ] **GREEN — manifest.** Add `worktree_baseref_verified: false` and `worktree_merges: []` to
      `manifest-init.sh` as additive fields. Add conditional invariants 20 and 21 to
      `manifest-validate.sh`, both "if present" so pre-existing manifests stay valid with no
      migration. `worktree_baseref_verified` is boolean → `manifest-set-flag.sh` sets it;
      `worktree_merges` is an array → bash `sed` on the additive field, with the exact command in a
      manifest comment (the `step5_review_mode` precedent — that comment is the only place a human
      finds it). The field is **not** named `worktree_hook_verified`: no hook is verified, and the
      old name would also collide in a reader's eye with ADR-0016's unrelated `hook_verified`.
- [ ] **GREEN — sync.** Add a MANUAL STEP block to `staging/sync-to-claude.sh` under a **new
      heading**, `--- MANUAL STEP: settings key (not auto-applied) ---`. It is not hook wiring and
      must not share the existing `MANUAL STEP: hook wiring` heading, which
      `sync-manual-steps.test.sh` already treats as a two-notice shared marker. Gate it on the state
      it describes, like the other seven: print only when
      `python3 -c "...baseRef...=='head'"` fails against `$DEST/settings.json`. The note must say
      what to add, and one thing more: **until this key is set, every modification agent's worktree
      forks from the default branch and the chain's Step 5 pre-flight will refuse to dispatch.**

*Budget: `staging/plugin/skills/concept-to-code/SKILL.md`, `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh`, `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh`, `staging/sync-to-claude.sh`, `staging/plugin/scripts/tests/sync-manual-steps.test.sh` (~180 lines)*

**Addendum — added during implementation, operator-approved.**

- [x] **The invariants are 22 and 23, not 20 and 21.** Those two numbers were already taken by
      `tracer_bullet_red_decision` and `external_dependencies`, added by features that landed after
      this plan was drafted. The implementing agent reconciled against the file's actual state
      rather than the plan text — the correct direction, and the ADR-0028 precedent for a
      count/number reconciliation.
- [x] **`sync-manual-steps.test.sh`'s A3 fixture was stale, the same class of finding as Task 3's
      TL1.** A3 asserts the all-clear line prints "when nothing is outstanding", against a
      fully-wired fixture that predates the eighth notice this task adds. Adding a notice makes
      every previously-complete fixture incomplete. The fixture was extended, A3's predicate
      untouched, and its RED-when-outstanding capability re-proved before the green was accepted.
      **The file already documented this obligation** in its line-50 comment, from the last time a
      notice was added (`PreCompact`); that comment now names the `baseRef` key too.
      **Generalising both findings: adding a check invalidates fixtures that enumerate "all
      checks", exactly as retiring a contract invalidates assertions that pin it. Grep the harness
      in both directions.**

---

## Task 6 — The stage protocol: explicit isolation on both paths, tester in a worktree, orchestrator merge-back and base-fork audit (R-06, R-07, R-08, R-09, R-14)

*Substantially unchanged. One addition: the merge-back now carries the audit record that the deleted
hook was going to produce (ADR-0068 §D5), marked* **NEW** *below.*

- [ ] **RED.** Extend the test file with **section H**:
      - every `agent(` call with `agentType: "coder"` in `concept-to-code/SKILL.md` — Step 5 Stage 2
        **and** Step 6's fix-agent dispatch — carries `isolation: 'worktree'` (R-06);
      - Step 5 Stage 1's tester dispatch carries `isolation: "worktree"` (R-09);
      - a merge-back block exists naming `worktreePath` and `worktreeBranch`, and it appears
        **between** the tester stage and the coder stage (positional assertion, the
        `recovery-preflight.test.sh` RE5 idiom) (R-07, R-09);
      - the merge-back block states the empty/auto-removed case as "nothing to merge" with neither
        an error nor an empty commit (R-14);
      - **NEW** — the merge-back block captures the worktree's fork point with
        `rev-parse HEAD` **before** the snapshot commit, records it as `base_sha`, compares it
        against the feature branch's `HEAD` captured at dispatch time, and halts on a mismatch. Two
        assertions: the ordering (capture precedes commit) and the halt (R-07);
      - `agents/coder.md` still contains "never commits" and **no** dispatch prompt in
        `concept-to-code/SKILL.md` or `autopilot-build/SKILL.md` instructs any coder to commit
        (R-08). This one is green from the start — a forward guard, labelled as such.
      - no `agent(` call anywhere carries an `effort` key on an `Agent(` (Agent-tool) call. The
        Agent tool has no `effort` parameter; `opts.effort` is Workflow-only.
- [ ] **GREEN — Workflow path.** Step 5 Stage 1 gains `isolation: "worktree"` on the tester
      `agent()` call; Stage 2 gains `isolation: 'worktree'` on the coder call (F4 as corrected by
      F16: frontmatter does not reach this path, but a worktree *is* created when the value is
      passed). Step 6's `agent(...)` fix dispatch gains it too.
- [ ] **GREEN — Agent-tool path.** The fallback's tester and coder dispatches pass
      `isolation: "worktree"` explicitly rather than inheriting it, for the same reason `model` and
      `effort` are pinned there.
- [ ] **GREEN — merge-back block.** One new resolution site in `concept-to-code/SKILL.md`, stated
      once and referenced by both dispatch paths (the `#### Proportional audit depth` /
      `#### Pattern seed handoff` single-resolution-site convention):

      ```bash
      # $PRE = git rev-parse HEAD, captured on the feature branch BEFORE this stage was dispatched
      # $WT  = worktreePath, $WB = worktreeBranch, both from the dispatch result (F10)
      [ -d "$WT" ] || { echo "nothing to merge: worktree auto-removed"; }   # F6, not an error
      if [ -d "$WT" ] && [ -n "$(git -C "$WT" status --porcelain 2>/dev/null)" ]; then
        BASE_SHA=$(git -C "$WT" rev-parse HEAD)      # NEW: fork point, BEFORE any commit lands
        [ "$BASE_SHA" = "$PRE" ] || <base-fork halt: report both shas, preserve $WB, stop>
        git -C "$WT" add -A
        git -C "$WT" commit -m "chore(step5): snapshot <stage> worktree (<agent_type>)"
        git merge --no-edit "$WB" || <conflict halt, Task 7>
        git worktree remove "$WT" 2>/dev/null || true
      fi
      ```

      State explicitly, at this site: **the orchestrator commits, never the agent** — `coder.md`'s
      "never commits" is untouched and the snapshot happens after the dispatch has returned (R-08).
      Append one `worktree_merges` entry per merged stage, carrying `base_sha`; append none when
      nothing was merged (R-14).
- [ ] **GREEN — NEW, the base-fork halt and why it is a halt.** State at the same site that
      `BASE_SHA != $PRE` means the worktree forked from somewhere other than the feature branch —
      the exact defect this feature exists to fix, occurring *after* the pre-flight assertion passed
      (a mid-run `settings.json` edit, or a future CC build changing the semantics). It halts on the
      same path as the Task 7 conflict halt, with its own message naming both shas. State the
      false-positive analysis in one sentence, because a halt nobody can explain gets removed: the
      stage protocol serialises dispatch → merge → next dispatch, so `HEAD` cannot legitimately move
      between `$PRE` and the worktree's fork point, and the auto-removed/empty cases are already
      handled as nothing-to-merge above.
- [ ] **GREEN — ordering.** State that the tester's merge completes **before** the coder's worktree
      is created, so the coder forks from a `HEAD` containing the red tests (R-09). Add one sentence
      naming why `baseRef: "head"` does not make this step redundant: `"head"` is the commit `HEAD`
      points at, not the working tree, and a worktree forks from a commit (ADR-0068 §D6/§D9).
- [ ] **GREEN — report.** `step5-report.json` gains the additive `worktree_merges` array; its
      absence means a pre-feature run, not a malformed report.
- [ ] **GREEN — pruning.** After a successful merge, prune the worktree. An **unmerged** worktree is
      reported, never silently deleted.

*Budget: `staging/plugin/skills/concept-to-code/SKILL.md`, `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` (~280 lines)*

**Addendum — added during implementation, operator-approved.**

- [x] **Section H's `effort` sweep caught a live pre-existing defect, and it is this feature's own
      failure mode in a different parameter.** Step 4.5's tracer-bullet dispatch (ADR-0057) read
      `Agent({ agentType: "coder", model: "sonnet", effort: "high", … })`. The Agent tool has no
      `effort` parameter — `opts.effort` is Workflow-only, already settled in this repo's
      `CLAUDE.md` — and an unexpected parameter is **rejected outright**, exactly as
      `isolation: "none"` is. Step 4.5 would have failed on dispatch for anyone who opted into it.
      Removed, with a forward-guard note citing ADR-0068 §D7. **The general lesson is R-01's, widened:
      a prescribed parameter the tool does not accept is a live failure waiting for its branch to be
      taken, and `isolation` was never the only one.** A future issue should sweep every
      tool-parameter name this repository prescribes against the actual schemas.
- [x] **`autopilot-build/SKILL.md` needed no edit.** It refers to c2c's Step 5/6 blocks by heading
      rather than restating them, so the merge-back site and the isolation pins reach it by
      reference. That is the ADR-0049 §D5 "single resolution site" convention working as intended —
      and the reason Task 3's `autopilot-build` edits were needed is that those blocks *were*
      restated there.
- [x] **The `Agent({...})` blocks use `agentType`, not the Agent tool's real `subagent_type`.**
      Consistent across the whole file (Gate 5.06 included), so it is the file's own shorthand
      rather than a defect of this task. Deliberately not changed; recorded here so the sweep above
      has somewhere to start.

---

## Task 7 — Binding conflict scan and the conflict halt (R-10, R-12)

*Unchanged by the revision.*

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
      than prompted, exactly as ADR-0050's assertions behave. Task 6's base-fork halt shares this
      path and adds its own message.
- [ ] Restate the halt by reference in `autopilot-build/SKILL.md` and note that
      `nightly-autopilot` inherits it (it reuses c2c Steps 5–7 verbatim).

*Budget: `staging/plugin/skills/concept-to-code/SKILL.md`, `staging/plugin/skills/autopilot-build/SKILL.md`, `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` (~140 lines)*

---

## Task 8 — Documentation surfaces, forward-recorded corrections, and issue #175 (R-15, R-16, R-18)

*One item changed by the revision: `CLAUDE.md` is* **revised, not appended to** *— its ADR-0068
section already exists and describes the refuted design.*

- [ ] **RED.** Extend the test file with **section J**: `staging/user/rules/parallelization.md`
      states the contract as measured and names no fallback; `docs/GUIDA-USO-IT.md` no longer
      promises `isolation: none` automatically; ADR-0016, ADR-0049 and ADR-0050 each carry a dated
      correction block naming ADR-0068 (R-15, R-16). **Added:** assert no documentation surface
      under `docs/` or `staging/user/rules/` promises a `WorktreeCreate` hook, and that `CLAUDE.md`'s
      ADR-0068 section names `worktree.baseRef` rather than `worktree-create.sh`.
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
      names ADR-0068, what is superseded, and why (R-16). These three have shipped; ADR-0068 itself
      has not, which is why it was edited in place instead (ADR-0068 §D12).
- [ ] **GREEN — `CLAUDE.md`, REVISE not append.** The `## Decisions from the worktree isolation
      contract chain (ADR-0068)` section already exists, written at the first pass's Gate 3, and
      describes the two-layer contract, `worktree-create.sh` and §D3's decline fail-safe — all three
      refuted. Rewrite it against the amended ADR: one layer (`worktree.baseRef: "head"`), no hook
      and why (F13 no discriminator, F14 no decline, no matcher), the audit record relocated into the
      merge-back, and the retained-but-never-wire probe instrument. Keep the section heading and the
      `Detail:` trailer so nothing else that points at it breaks.
- [ ] **GREEN — issue #175.** Record the closure reason in the ADR and in the PR body: its
      dirty-tree check is **retired** by R-11, not rewritten, so the `git diff HEAD --name-only`
      untracked-file blindness it reported is moot (R-18). Closing the issue on GitHub is a HITL
      action for the operator, not an agent action.

*Budget: `staging/user/rules/parallelization.md`, `docs/GUIDA-USO-IT.md`, `docs/SKILLS-AND-AGENTS-GUIDE.md`, `docs/architecture/ADR-0016-dynamic-workflows-step5.md`, `docs/architecture/ADR-0049-103-generator-verifier-separation.md`, `docs/architecture/ADR-0050-104-recovery-readiness-preflight.md`, `CLAUDE.md`, `staging/plugin/scripts/tests/worktree-isolation-contract.test.sh` (~210 lines)*

---

## Task 9 — Live evidence on both dispatch paths, and full-suite verification (R-03, R-17, R-19)

**Rewritten 2026-07-28.** No hook is deployed, so the deploy step has no hook-wiring MANUAL STEP;
the `baseRef` key is already set live and the job is to verify it survived rather than to add it.

- [ ] Deploy: `bash staging/sync-to-claude.sh` (dry run), review the diff, then `--apply`. The only
      MANUAL STEP this feature adds is the `baseRef` settings key. Confirm the notice **does not**
      print, because the live key is already `"head"` — and confirm it **does** print against a
      temporary copy of `settings.json` with the key removed. A notice that never fires is
      indistinguishable from a notice that is broken.
- [ ] Re-verify the live key after the sync: `python3 -c "import json,os;
      print(json.load(open(os.path.expanduser('~/.claude/settings.json'))).get('worktree'))"`
      must print `{'baseRef': 'head'}` (R-17).
- [ ] Confirm no `WorktreeCreate` key exists in the live `~/.claude/settings.json` and that
      `~/.claude/hooks/worktree-create.sh` does not exist. The capture instrument stays in
      `staging/` and is not deployed.
- [ ] **Evidence, Agent-tool path.** On a feature branch carrying a commit absent from the default
      branch, run one real Step 5 task group. Record: the worktree's `HEAD` sha equals the feature
      branch's; the tester's tests are visible inside the coder's worktree; both branches merged;
      `worktree_merges` has two entries, each with a `base_sha` matching its stage's `$PRE`.
- [ ] **Evidence, Workflow path.** Same, on a manifest with `hook_verified = true` (ADR-0016's
      Dynamic-Workflows flag — unrelated to worktrees and not to be confused with
      `worktree_baseref_verified`). Record the same four facts.
- [ ] Append both records to the ADR's *Measured facts annex* as the R-03 evidence. **Recorded as
      evidence, not asserted** — the SPEC is explicit that this is not a test assertion, because it
      needs a live dispatch that CI cannot run. The base-fork half of R-03 is already satisfied by
      F15/F16; these two records cover the stage protocol.
- [ ] Run the **full** suite: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`.
      Not just the new file — Task 3 touches blocks that `recovery-preflight.test.sh` and
      `workflow-dispatch-pins.test.sh` anchor into, and Task 5 touches `sync-manual-steps.test.sh`
      and the manifest helpers.
- [ ] Run `npx markdownlint-cli2 "docs/architecture/*.md" "*.md"`. Task 8 edits four ADRs and
      `CLAUDE.md`; `docs/superpowers/` is lint-ignored but `docs/architecture/` is not.
- [ ] Confirm `worktree-isolation-contract` is present in **both** CI registries (R-19).
- [ ] Confirm `pairs-completeness.test.sh` passes **without** any new entry — no file with a
      deployed counterpart was added by this feature (R-17).
- [ ] Re-run the Task 1b coverage command one final time: nineteen IDs, no `ORPHAN`, no `UNCOVERED`.

**HITL:** deploy (`--apply`), the commit, the push, and closing #175 are all operator actions.

---

## Task 10 — Both worktree-identity retrieval methods in the merge-back (R-07, R-09)

**Added during implementation, operator-approved. Task 9's evidence step found this; that is what
the evidence step is for.** Task 6's merge-back read `$WT`/`$WB` "from the dispatch result (F10)",
and F10 was measured on the Agent-tool path only. The Workflow path — the one taken whenever
`hook_verified` is true, so the default in any verified environment — reports no worktree identity
at all (F19). The instruction was therefore unexecutable on half its call sites, and the failure
mode was ADR-0068's own defect reappearing: a coder's work orphaned on an unmerged branch.

- [x] **RED.** Section K of `worktree-isolation-contract.test.sh`: both retrieval methods stated;
      `git worktree list` named for the Workflow path; the F19 identity gap cited so the two are
      not collapsed back into one; and a **precedence** check that enumeration is presented before
      the `<runId>-<n>` convention. K4 was labelled **vacuously green** in the file itself and
      proved separately on fixtures, since with neither method present it passed for the wrong
      reason.
- [x] **GREEN.** The merge-back section now states both, with enumeration preferred over run-id
      derivation — F20 records the naming convention as *observed*, not as a reported contract, and
      building on it is the class of undocumented assumption this ADR exists to stop.
- [x] Re-synced to `~/.claude` after the fix; the first sync had shipped the half-correct form.

**The generalisable finding: a fact measured on one dispatch path is not a fact about the chain.**
F10 was true, correctly recorded, and silently assumed to be universal — the same shape as
ADR-0016 asserting `isolation: none` without checking it against the tool schema, which is the
defect this whole ADR was written to correct. It recurred inside the correction.

---

## Risks

- **R1 — the mechanism is one global settings key with no repository-side enforcement.** It lives in
  user-scope `~/.claude/settings.json`, changes `--worktree` and `EnterWorktree` behaviour for every
  project on this machine, and can be edited back to `"fresh"` at any time. Two detectors exist and
  both fire late: the Step 5 pre-flight assertion (Task 5) at dispatch time, and the per-stage
  base-fork comparison (Task 6) after the dispatch returns. Nothing detects the edit itself.
- **R2 — `worktree-capture.sh` stays in the tree and is dangerous if wired.** Registering it aborts
  every worktree creation on the machine (F14). Task 4 rewrites its header to say so in the first
  five lines and section D2 pins that text, but the file exists and a header is not a guard.
- **R3 — F13–F18 are true of CC 2.1.220 and of nothing else.** ADR-0016's v2.1.154 experience is the
  precedent: the substrate moves. A build that adds an agent discriminator and an abstain state to
  `WorktreeCreate` reopens the hook question on its merits — re-run the probe before re-reading the
  ADR as settled.
- **R4 — a merge conflict now halts an unattended run, and so does a base-fork mismatch.**
  `autopilot-build` and `nightly-autopilot` inherit both. Intended, but it changes overnight
  behaviour and adds a second halt reason nobody has seen fire yet.
- **R5 — the heading `**Pre-dispatch: worktree isolation check` is load-bearing** for
  `recovery-preflight.test.sh:251` and `workflow-dispatch-pins.test.sh:84`. Task 3 rewrites that
  block's body; changing the heading breaks both files silently. **Unchanged by this revision.**
- **R6 — five SPEC requirement IDs change meaning mid-chain (Task 1b).** The IDs are kept so the
  coverage gate sees an unchanged set, which is the safe move mechanically and the confusing one
  historically: `git log -p SPEC.md` shows two different meanings behind the same five labels on the
  same day. The ADR's Consequences records it; nothing enforces that a future reader notices.
- **R7 — this ships an instruction, not an enforcement** for the stage protocol. Every merge-back,
  halt and base comparison is prose in a SKILL.md a model is asked to follow. The harness pins that
  the instruction exists; nothing pins that it is obeyed. Enforcing it in `manifest-transition.sh`
  was rejected on blast radius (ADR-0068 §A7).
- **R8 — Task 1b edits the Gate-1-approved SPEC.** The amendment text is stated verbatim so the
  edit is transcription rather than interpretation, and the coverage command in that task is the
  check that a mis-indented criterion did not silently undeclare an ID. A paraphrased edit is the
  realistic failure mode here.

## HITL gates

- **Gate 2 re-entry (now)** — approving this plan approves the `SPEC.md` amendment text in Task 1b.
- **Task 9** — `sync-to-claude.sh --apply`.
- **Commit / push / PR** — operator, as always.
- **Closing issue #175** — operator.

TEST-CMD CANDIDATE: for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done
TEST-CMD MODE: brownfield
