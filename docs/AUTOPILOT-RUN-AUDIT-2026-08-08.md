# Autopilot run audit — 2026-08-08, issue #294

Subject: the `/skill autopilot --features 1 --only 294` run of 2026-08-07 22:30Z → 2026-08-08 01:15Z.
Outcome: PR #383, 1/1 delivered, all four CI checks green, nothing merged. The run **succeeded**;
this document is about what it exposed on the way.

Every finding below was verified against the tree or the logs at audit time. Where something is
inferred rather than measured, it says so.

---

## F1 — Skill arguments are substituted into `$0`/`$1`/`$2` **inside the skill body**

**Severity: P0. This is the root cause and everything else in section F is downstream of it.**

When a skill is invoked with arguments, the argument list is whitespace-split and substituted into
every `$<digit>` token in the skill's own markdown body, **0-indexed** — before the body reaches the
model. Bash fences are text, so they are rewritten too.

Measured three times independently in one run:

| Skill | Invoked with | On disk | As rendered |
|---|---|---|---|
| `autopilot` | `--features 1 --only 294` | `case "$1" in` | `case "1" in` |
| `autopilot` | same | `_cli_features="$2"` | `_cli_features="--only"` |
| `project-conductor` | `autopilot --fork-from main` | `[ "$1" = "autopilot" ]` | `[ "--fork-from" = "autopilot" ]` |
| `project-conductor` | same | `awk '{ if ($0 == "- [ ] " f)` | `awk '{ if (autopilot == "- [ ] " f)` |
| `concept-to-code` | `plan-tasks.sh has two modes …` | `_d=$(dirname "$1")` | `_d=$(dirname "has")` |
| `concept-to-code` | same | `awk '{print $1}'` | `awk '{print has}'` |
| `concept-to-code` | same | `awk -F'\t' '$1=="DELETED_LINES"{print $2}'` | `… 'has=="DELETED_LINES"{print two}'` |

0-indexing confirmed by the c2c case: the title's words are `plan-tasks.sh`(0) `has`(1) `two`(2),
and `$1`→`has`, `$2`→`two`.

**Why it matters more than a cosmetic glitch.** ADR-0083's whole fence-contract mechanism rests on
the rendered text being the executable text. Under this defect the rendered text is *not* the file's
text, and the corruption is silent — it produces syntactically valid shell that does the wrong thing.

What was actually broken during this run, had the fences been executed as rendered:

- **`autopilot`'s argument parser is itself corrupted** (`case "$1"`, both `$2` reads). `--features`
  and `--only` would not have parsed, `_has_scoping_arg` would not have been set, and the run would
  have gone **unbounded across all 30 pending roadmap features** — the exact failure ADR-0129 §A4
  exists to prevent, reintroduced one layer above it.
- **`project-conductor`'s autopilot detection** (`[ "$1" = "autopilot" ]`) → `_autopilot` stays
  false → the scope gate reports `INACTIVE`, the Step 3 gate prompts, no publish.
- **`project-conductor`'s `[~]` marking** (2 sites) → the `$0 == "- [ ] " f` comparison can never
  match → a skipped feature is silently *not* marked, on both the no-SPEC skip and the branch-C
  terminal skip.
- **c2c Step 5.0.1 `rel()`** (5 lines) → every artifact classifies as `OTHER`, the manifest
  exemption goes inert, the pre-flight refuses every run. **This is ADR-0089's own bug, reintroduced
  at render time**, in the fence written to fix it.
- **c2c Gate 2b + Form B TOFU probes** (2 sites) → `H` is garbage → `grep -qxF` never matches →
  always `NOT_TRUSTED`. **ADR-0102's bug, reintroduced at render time.**
- **c2c task metrics** (2 sites) → `_dl`/`_tcd` silently empty.

The run survived only because the orchestrator read every fence from disk instead of executing the
rendered text — an ad-hoc workaround, not a designed mitigation.

**Population: 20 lines across 6 staged `SKILL.md` files** (`concept-to-code` 9, `autopilot` 4,
`project-conductor` 3, `autopilot-build` 2, `commit` 1, `swiftui-pro` 1).

**Undocumented.** No ADR and no line of `CLAUDE.md` mentions it.

---

## F2 — Every autopilot PR is titled with a raw slug

**Severity: P0 (every future unattended PR).**

`publish-feature.sh:148` passes `--title "$SLUG"`. PR #383 is titled
`plan-tasks-sh-has-two-modes-with-opposit` — a 40-char truncated kebab slug.

The eight most recent PRs: #383 is the **only** one titled this way. Every other has a Conventional
Commits subject, because every other was created by the `commit` skill from the commit message.
**#383 is the first PR this system has ever created through `publish-feature.sh`**, so the defect has
been latent since ADR-0022 and only a genuinely unattended publish could surface it.

The commit subject (`feat(plan-tasks): bind each caller to the mode its question needs`) was on the
branch and unused.

---

## F3 — `project-conductor` never passes `mode` to `manifest-init.sh`

**Severity: P1.**

`concept-to-code` §2 Form A step 6 requires the `mode` from `gate0-detect.sh` to be passed as the 4th
argument. `project-conductor` Step 4 calls `manifest-init.sh` itself and omits it, so the manifest is
created `greenfield` by default.

This run: manifest said `greenfield`, `gate0-detect.sh` said `brownfield`. Uncorrected, c2c Step 1
takes the greenfield branch and dispatches `interview-driver` — **interactive, with nobody present**.
That is the issue #329 failure class reached through a door #329 did not close. The orchestrator
corrected the field by hand.

---

## F4 — Merge-back prunes the worktree and never deletes the branch

**Severity: P1 (unbounded growth).**

The merge-back block runs `git worktree remove "$WT"` on success and never touches `$WB`. The
*conflict* path says "no branch deletion" deliberately; the *success* path simply never mentions it.

`worktree-agent-*` local branches: **20 before this run, 23 after**. They accumulate forever, one per
dispatched stage, on every chain run.

---

## F5 — `plan_deviations` is coder-only, so a tester's deviation never reaches Gate 5

**Severity: P1.**

ADR-0073 §D1 puts the `PLAN DEVIATIONS:` block in the **coder** brief only. ADR-0049 then made the
tester a first-class producer, and the disclosure mechanism did not follow.

Measured: the tester added a finding token `STALE-MODE-EXEMPT` to `mode-binding-check.sh`. That token
appears **0 times in ADR-0131** — a real departure from the ADR's §D3 taxonomy. It reached the
orchestrator only as prose in the agent's report, never entered `plan_deviations`, and would not have
rendered at Gate 5 for a human.

---

## F6 — Hook audit logs are global and unscoped by project

**Severity: P1.**

`~/.claude/state/<hook>/audit.log` is shared across every session and every repository. During this
run a concurrent session in `/Users/stefer/Developer/vibiso-system` interleaved its entries:
`agent-command-scope` logged 874 events in the window, of which **16** belong to this repo.

The session id *is* in column 2, so filtering is possible — but no consumer filters, and the ADR-0029
lesson (`hook-verify-workflow.sh` needed exactly this filter to stop reading another session's rows
as its own) was not carried across to the audit logs.

---

## F7 — Phase P step 3 is scope-blind

**Severity: P2.**

Phase P step 3 iterates **every** row of `docs/specs/_issue-map.tsv` whose SPEC is absent, with no
reference to the `--only` / `--features` bound Phase S resolved minutes earlier. On this run that
meant 4 SPEC generations for closed issues (#363–#366) outside a run explicitly bounded to one
feature. The orchestrator declined them and said so.

ADR-0129 bounded what a run *implements* and left what it *designs* unbounded.

---

## F8 — Phase P step 4 has no "nothing was generated" branch

**Severity: P2.**

Step 4 instructs creating `autopilot/prep-<date>`, committing Phase P's outputs, pushing it, and
recording `$_prep_ref`. It has a skip-if-present branch for an existing prep branch but **no branch
for steps 1–3 having all skipped**, which is the normal brownfield case and was this run's. The
orchestrator used `main` as the fork point and recorded that; the skill does not sanction it.

---

## F9 — `test-write-scope.sh` classifies a production deliverable as a test file

**Severity: P2.**

The predicate is a `tests/` path component. ADR-0131 §D3 deliberately places `mode-binding-check.sh`
— a 431-line production checker — under `staging/plugin/scripts/tests/` precisely to stay outside
`.claude/test-cmd`'s glob, `docs-ci.yml`'s named list and `pairs-completeness.test.sh`'s population.

Both decisions are individually correct and they collide: the checker had to be dispatched to the
**tester**, because the coder is denied any write under `tests/`.

---

## F10 — `test-write-scope.sh` logged no tester write

**Severity: P2, and it is an open question rather than a confirmed defect.**

In this session's window the hook logged exactly 3 events, all from the coder dispatch. The three
tester dispatches — which wrote `plan-task-count.test.sh`, `mode-binding-check.sh` and
`batch-dispatch-openers.test.sh` — produced **no audit entry at all**.

Either the hook did not observe those writes, or it exits before logging on some path. Not resolved
here. It matters because the hook is the backstop ADR-0088 relies on.

---

## F11 — `shell-tests` is not a required check

**Severity: P2. Known (ADR-0114), restated because this run measured it again.**

The CI job that runs the whole 74-file harness *and* the plant registry does not gate a merge on
`main`. It passed on #383. `required-checks-audit.sh` reports it on every run.

---

## F12 — Root `SPEC.md` is never stamped with a topic slug on the brownfield path

**Severity: P3. Issue #375, confirmed still live.**

`gate0-detect.sh` reported `spec_topic_match=unknown`. c2c Step 1 stamps the `**Topic slug:**` marker
only on the **greenfield** branch; the conductor's just-in-time copy does not stamp it either. Every
conductor-driven chain therefore routes with an unverifiable SPEC identity.

---

## F13 — `plant-check.sh` runtime exceeds a 10-minute budget

**Severity: P3, now measured.**

268 declared plants, each re-running a harness file: **> 25 minutes**. It timed out a 10-minute
foreground run and had to be backgrounded. Result was correct (`PASS=274 FAIL=0`).

---

## F14 — Orchestrator error: `isolation` omitted on the first dispatch

**Severity: P1 for the run, no code change needed.**

The Batch A tester was dispatched without `isolation: "worktree"`. ADR-0068 §D7 requires it
explicitly because `tester` carries no `isolation` in its frontmatter, so an omitted value means no
worktree at all. The agent wrote directly into the shared checkout.

No work was lost. Note the second-order problem: **the escape check could not have caught it**,
because that check reads `git ls-files --others` (untracked only) and the file the agent edited was
tracked.

---

# Roadmap

Ordered by what unblocks or endangers the most. Each item names its own verification, because several
of these are exactly the "a green run proves nothing" shape this repository keeps re-learning.

## Wave 1 — the rendering defect (P0)

**R1. Move every `$<digit>` out of every staged `SKILL.md` bash fence.**
The fix is not to escape them — it is to stop putting logic that needs positional parameters or awk
field references inside a rendered document. Two mechanisms, both already precedented here:

- shell positional params (`autopilot`'s argument parser, `project-conductor`'s mode detection) move
  into a script under `staging/plugin/skills/<skill>/scripts/`, invoked with the arguments. Same
  shape as `plan-tasks.sh`, `spec-coverage.sh`, `manifest-entry-state.sh`.
- awk programs (`rel()`, the two TOFU probes, the metrics readers, the `[~]` markers) move into
  `.awk` files loaded with `awk -f`, or into a helper script. A file is never rendered, so `$1`
  survives.

**R2. A derived guard: no `$<digit>` inside a bash fence in any staged `SKILL.md`.**
Population = `staging/plugin/skills/*/SKILL.md`, count-guarded on the denominator (an unmatched glob
must fail loudly, not read as full coverage). Waiver via a declared one-line marker for a genuine
prose mention. Verify in the failing direction: reintroduce one `$1` and watch it go red.

**R3. Record the mechanism in `CLAUDE.md` and an ADR.** It is undocumented, and the next author will
otherwise write `$1` into a fence for the same good reasons the current ones were written.

**Verification for the wave:** re-run `/skill autopilot --dry-run --only <n>` and confirm the
rendered fence is byte-identical to the file. That is the only check that tests the actual failure.

## Wave 2 — publish quality and chain correctness (P0/P1)

**R4. `publish-feature.sh` takes a real PR title.** Accept `--title`, default to the branch's last
non-snapshot commit subject, fall back to the slug only if that cannot be resolved. Assert the
resulting title is not equal to the slug for a branch whose tip has a Conventional Commits subject.

**R5. `project-conductor` passes `mode` to `manifest-init.sh`.** Run `gate0-detect.sh` in Step 4
before the init call and forward the 4th argument. Assert the created manifest's `mode` equals what
`gate0-detect.sh` reports for the same root — in both directions, so a hardcoded `brownfield` fails
too.

**R6. Merge-back deletes the merged worktree branch.** `git branch -d "$WB"` after a successful
`git worktree remove`, never `-D`, and never on the conflict or halt paths (which preserve it by
design). Assert a successful merge leaves no `worktree-agent-*` branch and a halted one does.
Then clean up the 23 existing branches as a separate, human-gated step.

**R7. `plan_deviations` covers the tester.** Add the `PLAN DEVIATIONS:` block to both tester brief
templates (Workflow Stage 1 and the Agent-tool batch template) and widen the schema note to say the
array records deviations from *any* dispatched agent. Assert both briefs carry it.

**R8. Scope hook audit logs by project.** Either write to `<root>/.claude/state/…` or add a project
column and filter on read. The session id is already in column 2; whatever consumers exist must use
it. Assert a foreign-repo line cannot be read as this repo's.

## Wave 3 — Phase P and the write-scope collision (P2)

**R9. Phase P step 3 honours the resolved scope.** Filter the issue-map iteration by the `--only`
list when one is in effect. Say explicitly what an unbounded run still does, so the change reads as a
bound rather than a narrowing.

**R10. Phase P step 4 gets an explicit "nothing generated" branch** naming the default branch as the
fork point and recording it as `prep_ref`, so the case that actually occurs is sanctioned rather than
improvised.

**R11. Decide the `tests/`-directory collision.** Either `test-write-scope.sh` gains a declared
exemption mechanism for non-test deliverables under `tests/`, or the repo adopts a different home for
"checker that must not deploy". Do not fix it by moving `mode-binding-check.sh` — its placement is
load-bearing for three separate reasons (ADR-0131 §D3).

**R12. Resolve F10.** Determine whether `test-write-scope.sh` observes tester writes at all. If it
does not, ADR-0088's backstop does not exist and that has to be said plainly.

**R13. Make `shell-tests` a required check on `main`** — repo-admin decision, not a code change.

## Wave 4 — long tail (P3)

**R14. Stamp the topic slug on the brownfield path** (issue #375), either in c2c Step 1's brownfield
branch or in the conductor's JIT copy. One place, not both.

**R15. Bound `plant-check.sh` runtime** — parallelism, or only running plants whose target file
changed. Any change here must keep the full-sweep mode available, since a partial run that reads like
a full one is this repository's signature failure.

---

## What this run did NOT expose

Recorded so the absence is not later read as coverage:

- No gate mis-fired. All five HITL gates recorded `approved` with notes — the first complete
  ADR-0099 trail in the corpus.
- `secret-scan`, `dependency-scan` and `weakening-scan` all ran and were clean; none was tested
  against a real positive.
- The ADR-0102 Gate 2b trust skip, ADR-0106 archive-on-completion, ADR-0104 snapshot collapse,
  ADR-0128 `Closes #N` and ADR-0129's bound all worked as designed.
- The bound was **verified in both directions**: #293 was refused `OUT-OF-SCOPE`, and the run stopped
  at `EXHAUSTED 1/1` without writing `[~]`, `skipped-features` or `needs-human`.
